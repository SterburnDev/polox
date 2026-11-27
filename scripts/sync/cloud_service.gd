extends RefCounted
## [CLOUD_SYNC] The running game's side of cloud sync: where the cloud folder is (settings), an engine
## for the real save folder, and the two things only the running game can do around a sync, in this
## order: write the open world to disk BEFORE (so the sync sees what the player sees) and load it again
## AFTER when the sync changed its files (so the game doesn't write an older copy back over them).
##
## cloud_sync.gd is the engine and knows nothing about the game; ui/cloud_sync_tab.gd is the screen.
## Settings live under "cloud" in settings.json, which is never synced:
##   folder   the cloud folder on this PC ("" until chosen; unused on Android, where each world's
##            document is picked instead)
##   auto     sync by itself when the title screen shows (on by default once a folder is chosen)
## Tags: [CLOUD_SYNC]

const CloudSync := preload("res://scripts/sync/cloud_sync.gd")
const CloudStore := preload("res://scripts/sync/cloud_store.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const AndroidNative := preload("res://scripts/core/android_native.gd")

const SETTINGS_KEY := "cloud"


## Cloud sync exists on PCs and in the Android app. The browser version lives inside Phone Link and
## has no storage of its own to sync.
static func supported() -> bool:
	if OS.has_feature("web"):
		return false
	return not OS.has_feature("android") or AndroidNative.documents_available()


static func is_android() -> bool:
	return OS.has_feature("android")


static func tree_uri() -> String:
	return str(config().get("tree_uri", ""))


static func set_tree_uri(uri: String) -> void:
	_save("tree_uri", uri)


static func uses_tree() -> bool:
	return OS.has_feature("android") and AndroidNative.tree_available() and tree_uri() != ""


static func uses_documents() -> bool:
	return OS.has_feature("android") and not uses_tree()


static func config() -> Dictionary:
	var saved: Variant = GameState.settings.get(SETTINGS_KEY, {})
	return saved if saved is Dictionary else {}


static func _save(key: String, value: Variant) -> void:
	var cloud := config().duplicate(true)
	cloud[key] = value
	GameState.settings[SETTINGS_KEY] = cloud
	GameState.save_settings()


static func folder() -> String:
	return str(config().get("folder", ""))


static func set_folder(path: String) -> void:
	_save("folder", path.replace("\\", "/").trim_suffix("/"))


static func automatic() -> bool:
	return bool(config().get("auto", true))


static func set_automatic(on: bool) -> void:
	_save("auto", on)


## True once there is somewhere to sync to.
static func is_set_up() -> bool:
	return supported() and (OS.has_feature("android") or folder() != "")


static func store() -> RefCounted:
	if uses_tree():
		return CloudStore.TreeStore.new(tree_uri())
	if uses_documents():
		return CloudStore.DocumentStore.new()
	return CloudStore.FolderStore.new(folder())


static func engine() -> CloudSync:
	return CloudSync.new(SaveManager.root, store())


## Syncs one world from the running game. `main` is the game's Main node (it owns the open world).
## Returns cloud_sync.gd's sync() result.
static func sync_world(main: Node, slot_id: String, choice: String = "") -> Dictionary:
	var is_open := main != null and main.get("game") != null and SaveManager.slot_id == slot_id
	if is_open:
		main.flush_all()
	var result := engine().sync(slot_id, choice)
	var changed: Array = result.get("changed_paths", [])
	if is_open and not changed.is_empty():
		# needs_reload() speaks in paths from the save root, as Phone Link does.
		var from_root := changed.map(func(path): return "slots/%s/%s" % [slot_id, path])
		if SyncFiles.needs_reload(from_root):
			main.reload_world_from_disk()
	return result


## Syncs every synced world without asking anything: questions (a conflict, a missing or damaged
## cloud copy) are left for the Cloud sync page and counted in `waiting`. Returns
## {synced, sent, received, combined, waiting, unreachable (a sentence, or "")}.
static func sync_all(main: Node) -> Dictionary:
	var summary := {"synced": 0, "sent": 0, "received": 0, "combined": 0, "waiting": 0, "unreachable": ""}
	if not is_set_up():
		return summary
	var sync_engine := engine()
	for slot_id in sync_engine.synced_slots():
		if not DirAccess.dir_exists_absolute(sync_engine.world_dir(slot_id)):
			continue   # (the world was deleted here; its link waits in case it comes back from the trash)
		var result := sync_world(main, slot_id)
		match str(result.get("action", "none")):
			"pushed":
				summary.sent += 1
			"pulled":
				summary.received += 1
			"merged":
				summary.combined += 1
			"ask":
				summary.waiting += 1
		if str(result.get("state", "")) == "unreachable":
			summary.unreachable = str(result.get("error", ""))
			break   # (the folder is away: the other worlds would say the same)
		if bool(result.get("ok", false)):
			summary.synced += 1
	return summary


## Sends what changed on this device and nothing else: no files here are touched, so it is safe while
## a world is open or the game is closing. Worlds that would need a download, a merge or an answer
## wait for the next full sync. Returns how many worlds were sent.
static func send_changes(main: Node) -> int:
	if not is_set_up():
		return 0
	var sync_engine := engine()
	var sent := 0
	for slot_id in sync_engine.synced_slots():
		if not DirAccess.dir_exists_absolute(sync_engine.world_dir(slot_id)):
			continue
		if main != null and main.get("game") != null and SaveManager.slot_id == slot_id:
			main.flush_all()
		var state := str(sync_engine.check(slot_id).state)
		if state == "unreachable":
			break
		if state in ["local_changes", "not_uploaded"] and bool(sync_engine.sync(slot_id).ok):
			sent += 1
	return sent


## What sync_all() did, in one line for a toast ("" when nothing worth saying happened).
static func summary_text(summary: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(summary.received) > 0:
		parts.append("%d updated from the cloud" % int(summary.received))
	if int(summary.sent) > 0:
		parts.append("%d sent" % int(summary.sent))
	if int(summary.combined) > 0:
		parts.append("%d combined" % int(summary.combined))
	if int(summary.waiting) > 0:
		parts.append("%d need%s your answer (Settings > Cloud sync)" % [int(summary.waiting), "s" if int(summary.waiting) == 1 else ""])
	return "" if parts.is_empty() else "☁ Worlds: " + ", ".join(parts)


## A world's sync state in a few plain words (cloud_sync.gd check() states).
static func state_text(state: String) -> String:
	match state:
		"off":
			return "Only on this device"
		"synced":
			return "In step with the cloud"
		"not_uploaded":
			return "Not sent yet"
		"local_changes":
			return "Changes here to send"
		"cloud_changes":
			return "Newer in the cloud"
		"both_changed":
			return "Changed here and in the cloud"
		"cloud_missing":
			return "Its cloud copy is gone"
		"cloud_damaged":
			return "Its cloud copy is damaged"
		"newer_format":
			return "Saved by a newer Polox"
		"wrong_world":
			return "Another world's file is in its place"
		"unreachable":
			return "The cloud can't be reached"
	return state
