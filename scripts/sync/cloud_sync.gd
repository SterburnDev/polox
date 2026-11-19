extends RefCounted
## [CLOUD_SYNC] Keeps a world in step between devices through a cloud folder, for when the PC that
## Phone Link needs is switched off. Each world is one package file in the folder (cloud_package.gd);
## each device remembers the revision it last agreed on, and a sync compares three things:
##
##   this device's world now  /  the revision last agreed on (the "base")  /  the cloud's package
##
##   nothing changed                         -> nothing to do
##   only this device changed                -> PUSH: a new revision replaces the cloud's package
##   only the cloud changed, from our base   -> PULL: this device takes the cloud's files
##   both changed                            -> MERGE file by file (cloud_merge.gd). If every file both
##                                              sides changed combines by rule, the result is installed
##                                              here and pushed. If not, NOTHING is changed and the
##                                              player chooses: this device's, the cloud's, or both.
##
## What makes "never silently overwrite" true:
##   * A package names its ancestors (history). A cloud package that doesn't descend from our base was
##     made without knowing our changes, so it is never taken as a plain update: it is merged or asked
##     about, even when this device changed nothing since.
##   * Before a push replaces the cloud's package, the package is read again; if it is no longer the
##     one this sync looked at, the push stops (another device got there first).
##   * Before this device's files change, the world is zipped (backups/before_cloud_*.zip), and the
##     incoming package is kept until every file is in place: an interrupted install is finished from
##     it the next time (see _finish_interrupted_install).
##   * Whenever the cloud's package is replaced by this device's choice, the replaced package is kept
##     in cloud/kept/ on this device.
##   * A package is used only after cloud_package.validate() passed, so a half-uploaded or damaged
##     file is reported, never applied.
##
## Order inside one sync (callers rely on it): finish any interrupted install, look (check), then at
## most one of push / pull / merge+push. The caller saves the open world first and reloads it when
## `changed_paths` isn't empty.
##
## Everything works on a save root given at creation, not on the running game's, so tests can run two
## devices and a cloud folder in one process.
## Tags: [CLOUD_SYNC] [PERSONAL_DATA]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const CloudPackage := preload("res://scripts/sync/cloud_package.gd")
const CloudMerge := preload("res://scripts/sync/cloud_merge.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")

## Everything cloud sync keeps on this device lives under <save root>/cloud/ and is never packed.
const STATE_FILE := "cloud/state.json"
const BASE_DIR := "cloud/base"           # the package of the revision last agreed on, per world
const INCOMING_DIR := "cloud/incoming"   # a package being installed (the journal for interruptions)
const KEPT_DIR := "cloud/kept"           # packages this device chose to replace: never deleted by sync
const WORK_DIR := "cloud/work"           # scratch copies; safe to delete at any time
const KEEP_SAFETY_ZIPS := 5              # before_cloud_*.zip kept per world
const STATE_VERSION := 1

var root := ""          # the save root this engine works on
var store: RefCounted   # a CloudStore.FolderStore or .DocumentStore
var device_name := ""   # how this device is named inside packages ("Windows PC")


func _init(save_root: String, cloud_store: RefCounted, name_of_device: String = "") -> void:
	root = save_root
	store = cloud_store
	device_name = name_of_device if name_of_device != "" else default_device_name()


static func default_device_name() -> String:
	if OS.has_feature("android"):
		return "Android phone"
	return "%s PC" % OS.get_name() if OS.get_name() in ["Windows", "Linux"] else OS.get_name()


# --- What this device remembers -----------------------------------------------------------------------

func _state() -> Dictionary:
	var saved: Variant = JsonUtil.read_json(root.path_join(STATE_FILE), {})
	var state: Dictionary = saved if saved is Dictionary else {}
	if not state.get("worlds") is Dictionary:
		state["worlds"] = {}
	state["version"] = STATE_VERSION
	return state


func _save_state(state: Dictionary) -> bool:
	JsonUtil.ensure_dir(root.path_join(STATE_FILE).get_base_dir())
	return JsonUtil.write_json(root.path_join(STATE_FILE), state)


## This device's own id (random, made once). It tells devices apart inside packages; it is not a key.
func device_id() -> String:
	var state := _state()
	if str(state.get("device_id", "")) == "":
		state["device_id"] = _new_id()
		_save_state(state)
	return str(state.device_id)


static func _new_id() -> String:
	return Crypto.new().generate_random_bytes(12).hex_encode()


## What is remembered about one world's sync, or {} when the world isn't synced.
func world_state(slot_id: String) -> Dictionary:
	var remembered: Variant = _state().worlds.get(slot_id, {})
	return remembered if remembered is Dictionary else {}


func _remember(slot_id: String, world: Dictionary) -> bool:
	var state := _state()
	state.worlds[slot_id] = world
	return _save_state(state)


func synced_slots() -> PackedStringArray:
	return PackedStringArray(_state().worlds.keys())


func world_dir(slot_id: String) -> String:
	return root.path_join("slots").path_join(slot_id)


func _world_name(slot_id: String) -> String:
	var card: Variant = JsonUtil.read_json(world_dir(slot_id).path_join(CloudPackage.CARD_FILE), {})
	return str(card.get("name", slot_id)) if card is Dictionary else slot_id


func _base_package(world_uid: String) -> String:
	return root.path_join(BASE_DIR).path_join(world_uid + "." + CloudPackage.EXTENSION)


func _incoming_package(world_uid: String) -> String:
	return root.path_join(INCOMING_DIR).path_join(world_uid + "." + CloudPackage.EXTENSION)


## While a combined world is being installed, the cloud's own package waits here to become the base.
func _incoming_base_package(world_uid: String) -> String:
	return root.path_join(INCOMING_DIR).path_join(world_uid + ".base." + CloudPackage.EXTENSION)


func _work_file(world_uid: String, purpose: String) -> String:
	return root.path_join(WORK_DIR).path_join("%s.%s.%s" % [world_uid, purpose, CloudPackage.EXTENSION])


# --- Switching a world's sync on and off -------------------------------------------------------------

## Starts syncing a world that is on this device. `ref` is where its package goes (a FolderStore makes
## a file name when none is given; a DocumentStore needs the picked document). Nothing is sent until
## sync() runs. Returns {ok, error}.
func enable(slot_id: String, ref: String = "") -> Dictionary:
	if not FileAccess.file_exists(world_dir(slot_id).path_join("world.json")):
		return {"ok": false, "error": "That world isn't on this device."}
	var world := world_state(slot_id)
	if world.is_empty():
		world = {"world_uid": _new_id(), "base_revision_id": "", "base_hash": "", "history": [], "revision": 0, "last_sync": ""}
	if ref != "":
		world["ref"] = ref
	elif str(world.get("ref", "")) == "":
		if store.kind() != "folder":
			return {"ok": false, "error": "Choose where this world's cloud copy goes first."}
		world["ref"] = CloudPackage.file_name(_world_name(slot_id), str(world.world_uid))
	return {"ok": _remember(slot_id, world), "error": ""}


## Stops syncing a world on this device. The cloud's package and this device's world both stay as
## they are; only the link is forgotten.
func disable(slot_id: String) -> void:
	var world := world_state(slot_id)
	if world.is_empty():
		return
	DirAccess.remove_absolute(_base_package(str(world.world_uid)))
	DirAccess.remove_absolute(_incoming_package(str(world.world_uid)))
	DirAccess.remove_absolute(_incoming_base_package(str(world.world_uid)))
	var state := _state()
	state.worlds.erase(slot_id)
	_save_state(state)


# --- Looking ------------------------------------------------------------------------------------------

## Compares this device's world with the cloud's package without changing anything. Returns
## {state, detail, local_hash, remote (the package's meta or {}), package (a local copy's path or ""),
##  skipped (files too big to sync)}. `state` is one of:
##   off             the world isn't synced
##   unreachable     the store can't be used right now (`detail` says why)
##   not_uploaded    synced, but nothing is in the cloud yet
##   cloud_missing   it was in the cloud, and now it isn't
##   cloud_damaged   the cloud's file fails its checks (cut off while uploading, or damaged)
##   newer_format    the cloud's file was written by a newer Polox
##   wrong_world     the file at that place belongs to another world
##   synced          both the same
##   local_changes   only this device changed
##   cloud_changes   only the cloud changed, and it descends from what this device has
##   both_changed    both changed, or the cloud's copy was made without knowing this device's
func check(slot_id: String) -> Dictionary:
	var result := {"state": "off", "detail": "", "local_hash": "", "remote": {}, "package": "", "skipped": []}
	var world := world_state(slot_id)
	if world.is_empty():
		return result
	var skipped: Array = []
	var local_files := CloudPackage.tracked_files(world_dir(slot_id), skipped)
	result.skipped = skipped
	result.local_hash = CloudPackage.content_hash(local_files)
	var problem := str(store.reachable())
	if problem != "":
		return _with(result, "unreachable", problem)
	var ref := str(world.get("ref", ""))
	if not store.exists(ref):
		if str(world.get("base_revision_id", "")) == "":
			return _with(result, "not_uploaded", "This world hasn't been sent to the cloud yet.")
		return _with(result, "cloud_missing", "This world's cloud copy is gone from %s." % store.label(ref))
	var copy := _work_file(str(world.world_uid), "check")
	problem = str(store.fetch(ref, copy))
	if problem != "":
		return _with(result, "unreachable", problem)
	result.package = copy
	var checked := CloudPackage.validate(copy)
	if not checked.ok:
		result.remote = checked.meta
		return _with(result, "newer_format" if checked.code == "newer_format" else "cloud_damaged", str(checked.error))
	var remote: Dictionary = checked.meta
	result.remote = remote
	if str(remote.world_uid) != str(world.world_uid):
		return _with(result, "wrong_world", "The file there is a different world (%s)." % str(remote.get("world_name", "?")))
	var local_changed := str(result.local_hash) != str(world.get("base_hash", ""))
	var base_id := str(world.get("base_revision_id", ""))
	if str(remote.revision_id) == base_id:
		return _with(result, "local_changes" if local_changed else "synced", "")
	if str(remote.content_hash) == str(result.local_hash):
		return _with(result, "synced", "")   # the same content reached both by different routes
	if base_id != "" and base_id in (remote.get("history", []) as Array):
		return _with(result, "both_changed" if local_changed else "cloud_changes", "")
	return _with(result, "both_changed", "")


static func _with(result: Dictionary, state: String, detail: String) -> Dictionary:
	result.state = state
	result.detail = detail
	return result


# --- One sync -----------------------------------------------------------------------------------------

## Brings this device and the cloud into step for one world. `choice` answers a question an earlier
## sync() asked: "" (none), "upload" (send this device's copy when the cloud's is missing or damaged),
## "use_this_device", "use_cloud" or "keep_both" (a conflict).
## Returns {ok, action, state, error, conflicts, changed_paths, remote, skipped, new_slot}:
##   action         none | pushed | pulled | merged | ask (a question for the player; nothing changed)
##   conflicts      [{path, what, why}] when action is "ask" for a conflict
##   changed_paths  files this sync changed on this device (reload the world if it is open)
##   new_slot       the world made by "keep_both" ("" otherwise)
func sync(slot_id: String, choice: String = "") -> Dictionary:
	var out := {"ok": false, "action": "none", "state": "off", "error": "", "conflicts": [], "changed_paths": [],
		"remote": {}, "skipped": [], "new_slot": ""}
	if world_state(slot_id).is_empty():
		out.error = "This world isn't synced."
		return out
	var finished := _finish_interrupted_install(slot_id)
	if not finished.ok:
		out.error = str(finished.error)
		return out
	out.changed_paths = finished.changed_paths
	var looked := check(slot_id)
	out.state = looked.state
	out.remote = looked.remote
	out.skipped = looked.skipped
	match str(looked.state):
		"unreachable", "newer_format", "wrong_world":
			out.error = str(looked.detail)
		"synced":
			out.ok = _adopt(slot_id, looked)
		"not_uploaded", "local_changes":
			_push(slot_id, looked, out)
		"cloud_missing", "cloud_damaged":
			if choice == "upload":
				_keep_replaced(slot_id, looked)
				_push(slot_id, looked, out)
			else:
				out.action = "ask"
				out.error = str(looked.detail)
		"cloud_changes":
			_pull(slot_id, looked, out)
		"both_changed":
			_resolve_both_changed(slot_id, looked, choice, out)
	if out.ok:
		out.state = "synced"
	return out


## Both copies hold the same content: remember the cloud's revision as the base without moving files.
func _adopt(slot_id: String, looked: Dictionary) -> bool:
	var world := world_state(slot_id)
	var remote: Dictionary = looked.remote
	if str(remote.get("revision_id", "")) == str(world.get("base_revision_id", "")):
		return true
	_store_base(world, str(looked.package))
	return _remember(slot_id, _based_on(world, remote, str(looked.local_hash)))


## `world` with its base set to the revision `meta` describes.
func _based_on(world: Dictionary, meta: Dictionary, content_hash: String) -> Dictionary:
	var updated := world.duplicate(true)
	updated["base_revision_id"] = str(meta.get("revision_id", ""))
	updated["base_hash"] = content_hash
	updated["history"] = meta.get("history", [])
	updated["revision"] = int(meta.get("revision", 0))
	updated["last_sync"] = Time.get_datetime_string_from_system(false, true)
	updated.erase("pending")
	return updated


func _store_base(world: Dictionary, package_path: String) -> void:
	var base := _base_package(str(world.world_uid))
	JsonUtil.ensure_dir(base.get_base_dir())
	if package_path != base and FileAccess.file_exists(package_path):
		DirAccess.copy_absolute(package_path, base)


# --- Push ---------------------------------------------------------------------------------------------

## Sends this device's world as a new revision. `looked` is what check() saw; its remote (when valid)
## becomes the new revision's parent, so every other device can tell the new one descends from it.
func _push(slot_id: String, looked: Dictionary, out: Dictionary) -> void:
	var world := world_state(slot_id)
	var remote: Dictionary = looked.remote if str(looked.state) in ["local_changes", "both_changed"] else {}
	var parent_history: Array = (remote.get("history", []) as Array) if not remote.is_empty() else (world.get("history", []) as Array)
	var revision_id := _new_id()
	var history: Array = [revision_id]
	history.append_array(parent_history)
	var meta := {
		"world_uid": str(world.world_uid), "world_name": _world_name(slot_id),
		"revision_id": revision_id, "revision": maxi(int(remote.get("revision", 0)), int(world.get("revision", 0))) + 1,
		"history": history.slice(0, CloudPackage.HISTORY_LENGTH),
		"device_id": device_id(), "device_name": device_name,
	}
	var outgoing := _work_file(str(world.world_uid), "out")
	var built := CloudPackage.build(world_dir(slot_id), outgoing, meta)
	if not built.ok:
		out.error = str(built.error)
		return
	# Compare-and-swap, as far as a folder allows: the cloud's package must still be the one this
	# sync looked at. If another device replaced it meanwhile, stop; the next sync sees both changes.
	var ref := str(world.ref)
	var expected_id := str(looked.remote.get("revision_id", "")) if str(looked.state) in ["local_changes", "both_changed"] else ""
	if expected_id != "" or str(looked.state) == "not_uploaded":
		var now_there := _revision_in_store(world)
		if now_there != expected_id:
			out.error = "The cloud copy changed while syncing (another device just synced). Sync again."
			out.state = "both_changed"
			return
	var problem := str(store.publish(ref, outgoing))
	if problem != "":
		out.error = problem
		out.state = "unreachable"
		return
	# Read it back: only a package that arrived whole becomes the new base.
	if _revision_in_store(world) != revision_id:
		out.error = "The upload couldn't be confirmed. Your world is safe on this device; sync again."
		return
	_store_base(world, outgoing)
	_remember(slot_id, _based_on(world, built.meta, str(built.meta.content_hash)))
	out.ok = true
	out.action = "pushed" if out.action == "none" else out.action
	out.remote = built.meta


## The revision id of the package in the store right now ("" when there is none or it can't be read).
func _revision_in_store(world: Dictionary) -> String:
	var ref := str(world.get("ref", ""))
	if not store.exists(ref):
		return ""
	var copy := _work_file(str(world.world_uid), "verify")
	if str(store.fetch(ref, copy)) != "":
		return ""
	return str(CloudPackage.read_meta(copy).get("revision_id", ""))


## Before this device replaces a cloud package it didn't make, a copy stays in cloud/kept/.
func _keep_replaced(slot_id: String, looked: Dictionary) -> void:
	var package := str(looked.package)
	if package == "" or not FileAccess.file_exists(package):
		return
	var world := world_state(slot_id)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var kept := root.path_join(KEPT_DIR).path_join(str(world.world_uid)).path_join("%s_%s.%s" % [
		stamp, str(looked.remote.get("revision_id", "unreadable")).left(8), CloudPackage.EXTENSION])
	JsonUtil.ensure_dir(kept.get_base_dir())
	DirAccess.copy_absolute(package, kept)


# --- Pull ---------------------------------------------------------------------------------------------

func _pull(slot_id: String, looked: Dictionary, out: Dictionary) -> void:
	var installed := _install(slot_id, str(looked.package), looked.remote, str(looked.package), looked.remote)
	out.changed_paths.append_array(installed.changed_paths)
	if not installed.ok:
		out.error = str(installed.error)
		return
	out.ok = true
	out.action = "pulled"


## Makes this device's world match `package` (already validated; `meta` is its meta) and sets the base
## to the revision `base_meta` describes, whose own package is `base_package` (the same file for a
## plain pull; the cloud's package when `package` is a combined world). Steps, in this order:
##   1. zip the world as it is (backups/before_cloud_*.zip)
##   2. keep the package in cloud/incoming/ and note the install as pending (the journal)
##   3. write each differing file (temp file, then rename), remove files the package doesn't have
##   4. check the result's content hash against the package's
##   5. make the package the base copy and clear the note
## A stop anywhere after 2 is finished by _finish_interrupted_install from the kept package.
## Returns {ok, error, changed_paths}.
func _install(slot_id: String, package: String, meta: Dictionary, base_package: String, base_meta: Dictionary) -> Dictionary:
	var world := world_state(slot_id)
	var folder := world_dir(slot_id)
	if FileAccess.file_exists(folder.path_join("world.json")):
		if SyncFiles.snapshot(root, slot_id, "before_cloud") == "":
			return {"ok": false, "error": "Couldn't back up this device's world first (is storage full?). Nothing was changed.", "changed_paths": []}
		_prune_safety_zips(slot_id)
	var incoming := _incoming_package(str(world.world_uid))
	JsonUtil.ensure_dir(incoming.get_base_dir())
	if package != incoming and DirAccess.copy_absolute(package, incoming) != OK:
		return {"ok": false, "error": "Couldn't keep the incoming copy on this device (is storage full?). Nothing was changed.", "changed_paths": []}
	var incoming_base := _incoming_base_package(str(world.world_uid))
	DirAccess.remove_absolute(incoming_base)
	if base_package != package and DirAccess.copy_absolute(base_package, incoming_base) != OK:
		return {"ok": false, "error": "Couldn't keep the cloud's copy on this device (is storage full?). Nothing was changed.", "changed_paths": []}
	world["pending"] = {"base_meta": {"revision_id": base_meta.get("revision_id", ""), "history": base_meta.get("history", []),
		"revision": base_meta.get("revision", 0), "content_hash": base_meta.get("content_hash", "")}}
	if not _remember(slot_id, world):
		return {"ok": false, "error": "Couldn't save sync progress on this device. Nothing was changed.", "changed_paths": []}
	return _apply_incoming(slot_id)


## Steps 3 to 5 of _install, from the package kept in cloud/incoming/. Safe to run again after a stop:
## files already in place are skipped.
func _apply_incoming(slot_id: String) -> Dictionary:
	var world := world_state(slot_id)
	var folder := world_dir(slot_id)
	var incoming := _incoming_package(str(world.world_uid))
	var meta := CloudPackage.read_meta(incoming)
	var wanted: Dictionary = meta.get("files", {})
	var changed: Array = []
	var have := CloudPackage.tracked_files(folder)
	for path in wanted:
		if str(have.get(path, "")) == str(wanted[path]):
			continue
		var bytes := CloudPackage.read_file(incoming, path)
		if path == CloudPackage.CARD_FILE:
			bytes = _card_keeping_play_time(bytes, folder.path_join(path))
		if not JsonUtil.write_bytes(folder.path_join(path), bytes):
			return {"ok": false, "error": "Couldn't save %s on this device (is storage full?). Sync again to finish." % path, "changed_paths": changed}
		changed.append(path)
	for path in have:
		if not wanted.has(path):
			if not JsonUtil.remove_file(folder.path_join(path)):
				return {"ok": false, "error": "Couldn't remove %s on this device. Sync again to finish." % path, "changed_paths": changed}
			changed.append(path)
	var result_hash := CloudPackage.content_hash(CloudPackage.tracked_files(folder))
	if result_hash != str(meta.get("content_hash", "")):
		return {"ok": false, "error": "The world changed on this device while the cloud copy was coming in. Sync again.", "changed_paths": changed}
	var pending: Dictionary = world.get("pending", {})
	var base_meta: Dictionary = pending.get("base_meta", meta)
	var incoming_base := _incoming_base_package(str(world.world_uid))
	_store_base(world, incoming_base if FileAccess.file_exists(incoming_base) else incoming)
	DirAccess.remove_absolute(incoming_base)
	# The base is the revision named in the note; this device's content is `result_hash`. After a
	# plain pull they are equal; after a merge the result differs from the base on purpose, so the
	# next step (push) sends it.
	var updated := _based_on(world, base_meta, str(base_meta.get("content_hash", result_hash)))
	_remember(slot_id, updated)
	DirAccess.remove_absolute(incoming)
	return {"ok": true, "error": "", "changed_paths": changed}


## The cloud's card, but with this device's own "last played" and play time when they are further on:
## those two fields don't count as changes, so neither side's are lost by taking the other's card.
static func _card_keeping_play_time(incoming_bytes: PackedByteArray, local_card_path: String) -> PackedByteArray:
	var incoming: Variant = JsonUtil.parse(incoming_bytes.get_string_from_utf8())
	var local: Variant = JsonUtil.read_json(local_card_path, {})
	if not incoming is Dictionary or not local is Dictionary:
		return incoming_bytes
	if str(local.get("last_played", "")) > str(incoming.get("last_played", "")):
		incoming["last_played"] = local.last_played
	incoming["playtime_s"] = maxi(int(incoming.get("playtime_s", 0)), int(local.get("playtime_s", 0)))
	return JSON.stringify(incoming, "\t", false).to_utf8_buffer()


## An install that was interrupted (the app closed, the battery died) is finished before anything
## else looks at the world. If its package is gone or no longer valid, the note is dropped and the
## base forgotten, so the next sync treats the half-changed world as "both changed" and merges or asks.
func _finish_interrupted_install(slot_id: String) -> Dictionary:
	var world := world_state(slot_id)
	if not world.has("pending"):
		return {"ok": true, "error": "", "changed_paths": []}
	var incoming := _incoming_package(str(world.world_uid))
	if FileAccess.file_exists(incoming) and CloudPackage.validate(incoming).ok:
		return _apply_incoming(slot_id)
	world.erase("pending")
	world["base_hash"] = ""
	_remember(slot_id, world)
	DirAccess.remove_absolute(incoming)
	DirAccess.remove_absolute(_incoming_base_package(str(world.world_uid)))
	return {"ok": true, "error": "", "changed_paths": []}


func _prune_safety_zips(slot_id: String) -> void:
	var folder := world_dir(slot_id).path_join("backups")
	var zips := Array(JsonUtil.list_files(folder, ["zip"])).filter(func(name): return str(name).begins_with("before_cloud_"))
	zips.sort()
	while zips.size() > KEEP_SAFETY_ZIPS:
		DirAccess.remove_absolute(folder.path_join(str(zips.pop_front())))


# --- Both changed -------------------------------------------------------------------------------------

func _resolve_both_changed(slot_id: String, looked: Dictionary, choice: String, out: Dictionary) -> void:
	match choice:
		"use_cloud":
			_pull(slot_id, looked, out)
			return
		"use_this_device":
			_keep_replaced(slot_id, looked)
			_push(slot_id, looked, out)
			return
		"keep_both":
			var copy := add_as_separate_world(str(looked.package), looked.remote)
			if not copy.ok:
				out.error = str(copy.error)
				return
			out.new_slot = str(copy.slot_id)
			_keep_replaced(slot_id, looked)
			_push(slot_id, looked, out)
			return
	var combined := _combine(slot_id, looked)
	if not (combined.conflicts as Array).is_empty():
		out.action = "ask"
		out.conflicts = combined.conflicts
		out.error = "This world changed on two devices in ways that can't be combined automatically."
		return
	if not combined.ok:
		out.error = str(combined.error)
		return
	var installed := _install(slot_id, str(combined.package), combined.meta, str(looked.package), looked.remote)
	out.changed_paths.append_array(installed.changed_paths)
	if not installed.ok:
		out.error = str(installed.error)
		return
	# This device now holds the combined world on top of the cloud's revision: send it.
	out.action = "merged"
	var after := check(slot_id)
	if str(after.state) == "local_changes":
		_push(slot_id, after, out)
	else:
		out.ok = str(after.state) == "synced"
		if not out.ok:
			out.error = str(after.detail) if str(after.detail) != "" else "The cloud copy changed again while combining. Sync again."


## Builds the combined world as a package without touching this device's files. Returns
## {ok, error, conflicts: [{path, what, why}], package, meta}. With conflicts, nothing was built.
func _combine(slot_id: String, looked: Dictionary) -> Dictionary:
	var world := world_state(slot_id)
	var folder := world_dir(slot_id)
	var remote_package := str(looked.package)
	var remote: Dictionary = looked.remote
	var base_package := _base_package(str(world.world_uid))
	var base_meta := CloudPackage.read_meta(base_package)
	# The base copy is the common ancestor only when (1) it really is the revision this device last
	# agreed on and (2) the cloud's package descends from that revision. A cloud package made
	# without knowing our base (another device overwrote it from an older state) shares no known
	# ancestor with us: comparing against our base would read "the cloud never had this file" as
	# "the cloud deleted it". So without a common ancestor nothing is ever deleted or replaced by
	# rule: files only one side has are kept, chats are joined, and any other file that differs
	# is a question for the player.
	var base_id := str(world.get("base_revision_id", ""))
	var base_usable := base_id != "" and str(base_meta.get("revision_id", "")) == base_id and base_id in (remote.get("history", []) as Array)
	var base_files: Dictionary = base_meta.get("files", {}) if base_usable else {}
	var local_files := CloudPackage.tracked_files(folder)
	var plan := CloudMerge.plan(base_files, local_files, remote.get("files", {}))
	var conflicts: Array = []
	var merged_bytes := {}
	for path in plan.both_changed:
		var local_bytes := FileAccess.get_file_as_bytes(folder.path_join(path)) if local_files.has(path) else PackedByteArray()
		var remote_bytes := CloudPackage.read_file(remote_package, path) if (remote.files as Dictionary).has(path) else PackedByteArray()
		var base_bytes := CloudPackage.read_file(base_package, path) if base_files.has(path) else PackedByteArray()
		var merged := CloudMerge.merge_file(path, base_bytes, local_bytes, remote_bytes)
		if merged.ok:
			merged_bytes[path] = merged.bytes
		else:
			conflicts.append({"path": path, "what": CloudMerge.describe(path, local_bytes if not local_bytes.is_empty() else remote_bytes), "why": str(merged.why)})
	if not conflicts.is_empty():
		return {"ok": false, "error": "", "conflicts": conflicts, "package": "", "meta": {}}
	# The combined world: this device's files, with the cloud's where only the cloud changed, the
	# combined ones where both did, and without what only the cloud removed.
	var entries := {}
	for path in local_files:
		if not path in plan.delete_local:
			entries[path] = FileAccess.get_file_as_bytes(folder.path_join(path))
	for path in plan.take_remote:
		entries[path] = CloudPackage.read_file(remote_package, path)
	for path in merged_bytes:
		entries[path] = merged_bytes[path]
	var staging := root.path_join(WORK_DIR).path_join(str(world.world_uid) + ".combined")
	JsonUtil.remove_tree(staging)
	for path in entries:
		JsonUtil.ensure_dir(staging.path_join(path).get_base_dir())
		var file := FileAccess.open(staging.path_join(path), FileAccess.WRITE)
		if file == null:
			JsonUtil.remove_tree(staging)
			return {"ok": false, "error": "Couldn't prepare the combined world (is storage full?). Nothing was changed.", "conflicts": [], "package": "", "meta": {}}
		file.store_buffer(entries[path])
		file.close()
	var combined_package := _work_file(str(world.world_uid), "combined")
	var built := CloudPackage.build(staging, combined_package, {
		"world_uid": str(world.world_uid), "world_name": _world_name(slot_id), "revision_id": _new_id(),
		"revision": int(remote.get("revision", 0)), "history": remote.get("history", []),
		"device_id": device_id(), "device_name": device_name, "combined": true})
	JsonUtil.remove_tree(staging)
	if not built.ok:
		return {"ok": false, "error": str(built.error), "conflicts": [], "package": "", "meta": {}}
	return {"ok": true, "error": "", "conflicts": [], "package": combined_package, "meta": built.meta}


# --- Worlds that are in the cloud but not here ---------------------------------------------------------

## Packages the store lists, with what they say about themselves: [{ref, world_uid, world_name,
## device_name, saved_at, revision, slot_id (the world here it belongs to, or ""), duplicate (another
## file for a world that already has one: a cloud app's "conflicted copy")}]. Only stores that can
## list (a folder) return anything.
func discover() -> Array:
	var found: Array = []
	var by_uid := {}
	var linked := {}
	var state := _state()
	for slot_id in state.worlds:
		linked[str(state.worlds[slot_id].get("world_uid", ""))] = {"slot_id": slot_id, "ref": str(state.worlds[slot_id].get("ref", ""))}
	for ref in store.list():
		# A folder's packages are read where they are (only the small sync record inside each one).
		var readable := str(store.path_of(ref)) if store.kind() == "folder" else ""
		if readable == "":
			readable = root.path_join(WORK_DIR).path_join("discover." + CloudPackage.EXTENSION)
			if str(store.fetch(ref, readable)) != "":
				continue
		var meta := CloudPackage.read_meta(readable)
		var world_uid := str(meta.get("world_uid", ""))
		if world_uid == "":
			continue
		var here: Dictionary = linked.get(world_uid, {})
		var entry := {"ref": ref, "world_uid": world_uid, "world_name": str(meta.get("world_name", ref)),
			"device_name": str(meta.get("device_name", "")), "saved_at": str(meta.get("saved_at", "")),
			"revision": int(meta.get("revision", 0)), "slot_id": str(here.get("slot_id", "")),
			"duplicate": (not here.is_empty() and str(here.ref) != ref) or by_uid.has(world_uid)}
		by_uid[world_uid] = true
		found.append(entry)
	return found


## Brings a world that is only in the cloud onto this device and links it. Returns {ok, error, slot_id}.
func add_from_cloud(ref: String) -> Dictionary:
	var copy := root.path_join(WORK_DIR).path_join("add." + CloudPackage.EXTENSION)
	var problem := str(store.fetch(ref, copy))
	if problem != "":
		return {"ok": false, "error": problem, "slot_id": ""}
	var checked := CloudPackage.validate(copy)
	if not checked.ok:
		return {"ok": false, "error": str(checked.error), "slot_id": ""}
	var meta: Dictionary = checked.meta
	var state := _state()
	for slot_id in state.worlds:
		if str(state.worlds[slot_id].get("world_uid", "")) == str(meta.world_uid):
			return {"ok": false, "error": "That world is already on this device (%s)." % _world_name(slot_id), "slot_id": slot_id}
	var unpacked := _unpack_as_new_world(copy, meta, "")
	if not unpacked.ok:
		return unpacked
	var world := {"world_uid": str(meta.world_uid), "ref": ref}
	_store_base(world, copy)
	_remember(str(unpacked.slot_id), _based_on(world, meta, str(meta.content_hash)))
	return unpacked


## A second file for a world that already has one (a cloud app's "conflicted copy") comes onto this
## device as its own, separate world, so the player can look at both. Returns {ok, error, slot_id}.
func add_copy_from_cloud(ref: String) -> Dictionary:
	var copy := root.path_join(WORK_DIR).path_join("add." + CloudPackage.EXTENSION)
	var problem := str(store.fetch(ref, copy))
	if problem != "":
		return {"ok": false, "error": problem, "slot_id": ""}
	var checked := CloudPackage.validate(copy)
	if not checked.ok:
		return {"ok": false, "error": str(checked.error), "slot_id": ""}
	return _unpack_as_new_world(copy, checked.meta, " (second copy)")


## "Keep both": the cloud's copy becomes its own, separate world here (not synced, renamed so the two
## can be told apart). Returns {ok, error, slot_id}.
func add_as_separate_world(package: String, meta: Dictionary) -> Dictionary:
	var from := str(meta.get("device_name", "another device"))
	return _unpack_as_new_world(package, meta, " (from %s)" % from)


func _unpack_as_new_world(package: String, meta: Dictionary, name_suffix: String) -> Dictionary:
	var slots_dir := root.path_join("slots")
	var wanted := JsonUtil.slugify(str(meta.get("world_name", "world")) + name_suffix)
	if wanted == "":
		wanted = "world"
	var slot_id := wanted
	var number := 2
	while DirAccess.dir_exists_absolute(slots_dir.path_join(slot_id)):
		slot_id = "%s_%d" % [wanted, number]
		number += 1
	var folder := slots_dir.path_join(slot_id)
	for path in (meta.get("files", {}) as Dictionary):
		if not JsonUtil.write_bytes(folder.path_join(path), CloudPackage.read_file(package, path)):
			JsonUtil.remove_tree(folder)
			return {"ok": false, "error": "Couldn't save the world on this device (is storage full?).", "slot_id": ""}
		# (write_bytes leaves no .bak for a new file, so the new world starts clean)
	if name_suffix != "":
		var card_path := folder.path_join(CloudPackage.CARD_FILE)
		var card: Variant = JsonUtil.read_json(card_path, {})
		if card is Dictionary:
			card["name"] = str(card.get("name", meta.get("world_name", "World"))) + name_suffix
			JsonUtil.write_json(card_path, card)
	return {"ok": true, "error": "", "slot_id": slot_id}
