extends Node
## The phone's side of sync. Its save folder (browser storage on a phone) is
## a working copy; the PC is the master. One sync: fetch the PC's manifest,
## compare both sides with what they were after the last sync, then push
## phone changes (the PC snapshots first), pull PC changes (a local snapshot
## first), and remember the new common state. Files changed on both sides:
## JSON merges field by field, with the PC keeping genuinely conflicting fields and stashing the phone's
## original in conflicts/; chat logs merge by message id instead.
## Tags: [PAIRING]

signal status_changed(state: String, detail: String)
signal _pulls_done

const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Pairing := preload("res://scripts/phone/pairing.gd")
const RequestSig := preload("res://scripts/phone/request_sig.gd")

const TIMEOUT_S := 30.0
const KEEP_LOCAL_SNAPSHOTS := 3
const PULL_WIDTH := 6       # files fetched at once: a request waits a few frames, a phone runs at 30 fps
const RETRY_DELAYS_S: Array[float] = [0.4, 1.2]

var base_url := ""          # e.g. http://192.168.1.20:8737 (the page's own origin on a phone)
var only_slots := ""        # the world(s) to sync ("a,b"; "" = what the PC picks: its active one)
var token := ""
var sign := false           # paired with pair_v:1: every request is signed (request_sig.gd), the key never sent
var local_root := ""
var state := "idle"         # idle | syncing | ok | conflict | offline | unpaired | error
## Your Light World as the PC said at the last sync: "shared", "private", "none" ("" before the first).
var home_state := ""
var detail := ""
var last_result: Dictionary = {}
var busy := false
## Called with the slot ids whose files changed here and the files pulled, so a running game reloads.
var on_pulled: Callable = Callable()
var _cancel_epoch := 0
var _active_http: Array = []


func _alive(epoch: int) -> bool:
	return epoch == _cancel_epoch and is_inside_tree()


## Cancels any in-flight sync or HTTP request and clears busy state.
func cancel() -> void:
	_cancel_epoch += 1
	busy = false
	var pending := _active_http.duplicate()
	_active_http.clear()
	for h in pending:
		if is_instance_valid(h):
			h.cancel_request()
			h.queue_free()
	_pulls_done.emit()


func _exit_tree() -> void:
	cancel()


func _set_state(s: String, d: String = "") -> void:
	state = s
	detail = d
	status_changed.emit(s, d)


func base_path() -> String:
	return local_root.path_join("phone").path_join("sync_base.json")


## Runs one full sync. Returns {ok, pulled, pushed, merged, conflicts, error}.
func sync() -> Dictionary:
	if busy:
		return {"ok": false, "error": "busy"}
	var epoch := _cancel_epoch
	busy = true
	_set_state("syncing", "Syncing...")
	var result := await _sync(epoch)
	if epoch == _cancel_epoch:
		busy = false
	last_result = result
	if _alive(epoch):
		_notify_committed(result)
		if result.ok:
			_set_state("conflict" if int(result.conflicts) > 0 else "ok",
				("%d conflict(s): the PC kept its version (see Worlds on the PC)" % result.conflicts) if int(result.conflicts) > 0 else "Synced " + Time.get_time_string_from_system().substr(0, 5))
	elif state == "syncing":
		_set_state("idle", "")
	return result


## What to do with one file, from its hash on the PC (`r`), on this phone (`l`) and at the last sync (`b`);
## "" means it isn't there. The rule on its own, away from the network: "same" and "forget" need no
## transfer, "pull" and "push" copy it one way, "drop_local" and "drop_remote" follow a deletion, and
## "pull_first" is a file both sides made before they ever synced (the PC's copy is taken, the phone's kept
## in a backup; logs are merged by the PC instead).
static func decide(r: String, l: String, b: String, is_log: bool) -> String:
	if l == r:
		return "forget" if l == "" else "same"
	if l == b:
		return "drop_local" if r == "" else "pull"
	if r == b:
		return "drop_remote" if l == "" else "push"
	if b == "" and l != "" and r != "" and not is_log:
		return "pull_first"
	return "push"   # both changed: the PC decides (merge or conflict), then we take its copy


func _sync(epoch: int = -1) -> Dictionary:
	var active_epoch := _cancel_epoch if epoch < 0 else epoch
	var out := {"ok": false, "pulled": [], "pushed": [], "merged": [], "conflicts": 0, "deleted": [], "local_deleted": [], "deferred": [], "error": ""}
	var m := await request("GET", "/api/manifest" + (("?slots=" + only_slots.uri_encode()) if only_slots != "" else ""))
	if not _alive(active_epoch):
		out.error = "cancelled"
		return out
	if not m.ok:
		_fail_state(m)
		out.error = str(m.error)
		return out
	if not m.json is Dictionary or not m.json.get("slots") is Array or not m.json.get("files") is Dictionary:
		out.error = "The PC sent an invalid sync manifest; local files were kept."
		_set_state("error", out.error)
		return out
	var slots := PackedStringArray(m.json.get("slots", []))
	home_state = str(m.json.get("home", ""))
	SyncFiles.home_shared = home_state == "shared"
	var remote: Dictionary = m.json.get("files", {})
	var local := SyncFiles.scan(local_root, slots)
	var saved: Variant = JsonUtil.read_json(base_path(), {})
	var base: Dictionary = saved if saved is Dictionary else {}
	_drop_placeholder_room(remote, local, base)
	var plan := _plan(remote, local, base, slots)
	var pulls: Array = plan.pulls
	var drop_local: Array = plan.drop_local
	if not await _begin_changes(plan.pushes, plan.drop_remote, out, active_epoch):
		return out
	if not await _push_files(plan.pushes, base, remote, pulls, out, active_epoch):
		return out
	if not await _delete_on_pc(plan.drop_remote, base, pulls, out, active_epoch):
		return out
	if not _back_up_before_pull(pulls + drop_local, out):
		return out
	var fail: Dictionary = await _pull_files(pulls, base, out, remote, local, active_epoch)
	if not _alive(active_epoch):
		_save_base(base)
		out.error = "cancelled"
		return out
	if not fail.is_empty():
		_fail_state(fail)
		out.error = str(fail.error)
		_save_base(base)
		return out
	if not _delete_here(drop_local, local, base, out):
		return out
	await request("POST", "/api/sync/end", JSON.stringify({"changed": out.pushed + out.merged + out.deleted}).to_utf8_buffer())
	if not _alive(active_epoch):
		out.error = "cancelled"
		return out
	if not _save_base(base):
		out.error = "Couldn't save sync progress on this phone. Free storage and retry."
		_set_state("error", out.error)
		return out
	out.ok = true
	return out


## An old offline phone may have made a temporary room before it received the house.
## The mapped house replaces that room; never upload it back to the PC as another home.
func _drop_placeholder_room(remote: Dictionary, local: Dictionary, base: Dictionary) -> void:
	var placeholder := "my_home/places/lw_my_room.json"
	if remote.keys().any(func(p): return str(p).begins_with("my_home/places/lw_floor_")) and local.has(placeholder) and not remote.has(placeholder):
		_first_sync_backup(placeholder)
		DirAccess.remove_absolute(local_root.path_join(placeholder))
		local.erase(placeholder)
		base.erase(placeholder)


## Every file either side knows, sorted into what this sync must do (see `decide`). Files that already
## agree are noted in `base` here; a "pull_first" file is backed up on this phone before it is replaced.
func _plan(remote: Dictionary, local: Dictionary, base: Dictionary, slots: PackedStringArray) -> Dictionary:
	var plan := {"pulls": [], "pushes": [], "drop_local": [], "drop_remote": []}
	var every := {}
	for d in [remote, local, base]:
		for p in d:
			every[p] = true
	for p in every:
		if not SyncFiles.allowed(str(p), slots):
			continue
		var r := str(remote.get(p, {}).get("sha256", "")) if remote.get(p) is Dictionary else ""
		var l := str(local.get(p, {}).get("sha256", "")) if local.get(p) is Dictionary else ""
		match decide(r, l, str(base.get(p, "")), str(p).ends_with(".jsonl")):
			"forget":
				base.erase(p)
			"same":
				base[p] = l
			"drop_local":
				plan.drop_local.append(p)
			"pull":
				plan.pulls.append(p)
			"drop_remote":
				plan.drop_remote.append(p)
			"push":
				plan.pushes.append(p)
			"pull_first":
				# Never synced, on both sides: a fresh phone's own defaults (e.g. the built-in tile
				# sets it made on first start). The PC is the master copy: take its version and keep
				# the phone's in a local backup, instead of filing a "phone conflict" on the PC.
				_first_sync_backup(p)
				plan.pulls.append(p)
	return plan


## The PC snapshots each world before the phone changes it. False (with the error set) if it can't be told.
func _begin_changes(pushes: Array, drop_remote: Array, out: Dictionary, epoch: int = -1) -> bool:
	var active_epoch := _cancel_epoch if epoch < 0 else epoch
	if not _alive(active_epoch):
		out.error = "cancelled"
		return false
	if pushes.is_empty() and drop_remote.is_empty():
		return true
	var touched := {}
	for p in pushes + drop_remote:
		var parts := str(p).split("/")
		if parts[0] == "slots":
			touched[parts[1]] = true
	var begin := await request("POST", "/api/sync/begin", JSON.stringify({"slots": touched.keys()}).to_utf8_buffer())
	if not _alive(active_epoch):
		out.error = "cancelled"
		return false
	if not begin.ok:
		_fail_state(begin)
		out.error = str(begin.error)
		return false
	return true


## Sends what this phone changed. The PC answers applied, same, merged or conflict; a merged or conflicting
## file is pulled back afterwards (added to `pulls`). False on the first failure, with progress saved.
func _push_files(pushes: Array, base: Dictionary, remote: Dictionary, pulls: Array, out: Dictionary, epoch: int = -1) -> bool:
	var active_epoch := _cancel_epoch if epoch < 0 else epoch
	for p in pushes:
		if not _alive(active_epoch):
			out.error = "cancelled"
			_save_base(base)
			return false
		var bytes := FileAccess.get_file_as_bytes(local_root.path_join(p))
		var r := await request("PUT", "/api/file?path=%s&base=%s" % [str(p).uri_encode(), str(base.get(p, ""))], bytes)
		if not _alive(active_epoch):
			out.error = "cancelled"
			_save_base(base)
			return false
		var status := str(r.json.get("status", "")) if r.json is Dictionary else ""
		var before_sha := str(remote.get(p, {}).get("sha256", ""))
		if status in ["merged", "conflict"] and r.json is Dictionary:
			remote[p] = {"sha256": str(r.json.get("sha256", ""))}
		if r.code == 409 and status == "conflict":
			out["conflicts"] = int(out.conflicts) + 1
			if str(r.json.get("sha256", "")) != before_sha:
				out.merged.append(p)   # non-conflicting fields still changed on the PC: reload them there too
			pulls.append(p)          # the PC version wins here too
		elif r.ok and status in ["applied", "same"]:
			base[p] = str(r.json.get("sha256", ""))
			out.pushed.append(p)
		elif r.ok and status == "merged":
			out.merged.append(p)
			pulls.append(p)          # bring the merged log back
		else:
			_fail_state(r)
			out.error = str(r.error)
			_save_base(base)
			return false
	return true


## Deletes on the PC what was deleted here (a file the PC changed meanwhile is pulled back instead).
func _delete_on_pc(drop_remote: Array, base: Dictionary, pulls: Array, out: Dictionary, epoch: int = -1) -> bool:
	var active_epoch := _cancel_epoch if epoch < 0 else epoch
	for p in drop_remote:
		if not _alive(active_epoch):
			out.error = "cancelled"
			_save_base(base)
			return false
		var r := await request("DELETE", "/api/file?path=%s&base=%s" % [str(p).uri_encode(), str(base.get(p, ""))])
		if not _alive(active_epoch):
			out.error = "cancelled"
			_save_base(base)
			return false
		if r.ok:
			base.erase(p)
			out.deleted.append(p)
		elif r.code == 409:
			pulls.append(p)
		else:
			_fail_state(r)
			out.error = str(r.error)
			_save_base(base)
			return false
	return true


## A local snapshot of each world, and of the home, that the PC's changes are about to touch.
func _back_up_before_pull(paths: Array, out: Dictionary) -> bool:
	var pulled_slots := {}
	var home_pulled := false
	for p in paths:
		var parts := str(p).split("/")
		if parts[0] == "my_home":
			home_pulled = true
		if parts[0] == "slots" and not pulled_slots.has(parts[1]):
			pulled_slots[parts[1]] = true
			if not _local_snapshot(parts[1]):
				out.error = "Couldn't back up this phone's world. Free storage and retry."
				_set_state("error", out.error)
				return false
	if home_pulled:
		if FileAccess.file_exists(local_root.path_join("my_home/home.json")) and SyncFiles.snapshot_home(local_root, KEEP_LOCAL_SNAPSHOTS) == "":
			out.error = "Couldn't back up this phone's home. Free storage and retry."
			_set_state("error", out.error)
			return false
	return true


## Removes here what was deleted on the PC, unless the file changed on this phone since the scan (then it
## waits for the next sync).
func _delete_here(drop_local: Array, local: Dictionary, base: Dictionary, out: Dictionary) -> bool:
	for p in drop_local:
		var expected := str(local.get(p, {}).get("sha256", ""))
		if SyncFiles.sha_of(local_root.path_join(p)) != expected:
			out.deferred.append(p)
			continue
		if not JsonUtil.remove_file(local_root.path_join(p)):
			out.error = "Couldn't remove a deleted file on this phone. Free storage and retry."
			_set_state("error", out.error)
			_save_base(base)
			return false
		base.erase(p)
		out.deleted.append(p)
		out.local_deleted.append(p)
	return true


## Downloads `paths` a few at a time, writing each file as it arrives.
## Returns {} or the first failed response (the rest wait for next time).
## Every file is checked against the PC's SHA-256 before it's kept (one retry).
func _pull_files(paths: Array, base: Dictionary, out: Dictionary, remote: Dictionary = {}, local: Dictionary = {}, epoch: int = -1) -> Dictionary:
	var active_epoch := _cancel_epoch if epoch < 0 else epoch
	var width := mini(PULL_WIDTH, paths.size())
	var job := {"queue": paths.duplicate(), "left": width, "fail": {}, "remote": remote, "local": local, "epoch": active_epoch}
	for i in width:
		_pull_worker(job, base, out)   # not awaited: they run side by side
	var deadline := Time.get_ticks_msec() + int((TIMEOUT_S * float(maxi(1, paths.size())) + 30.0) * 1000.0)
	while int(job.left) > 0 and _alive(active_epoch):
		if Time.get_ticks_msec() >= deadline:
			if (job.fail as Dictionary).is_empty():
				job["fail"] = {"ok": false, "code": 0, "error": "Sync timed out"}
			break
		await get_tree().process_frame
	if int(job.left) > 0 and (job.fail as Dictionary).is_empty():
		job["fail"] = {"ok": false, "code": 0, "error": "cancelled"}
	return job.fail


func _pull_worker(job: Dictionary, base: Dictionary, out: Dictionary) -> void:
	var queue: Array = job.queue
	var active_epoch := int(job.get("epoch", _cancel_epoch))
	while not queue.is_empty() and (job.fail as Dictionary).is_empty() and _alive(active_epoch):
		var p := str(queue.pop_front())
		var expected := str(job.local.get(p, {}).get("sha256", ""))
		var want := str((job.remote as Dictionary).get(p, {}).get("sha256", "")) if (job.remote as Dictionary).get(p) is Dictionary else ""
		var g := await request("GET", "/api/file?path=" + p.uri_encode())
		if not _alive(active_epoch):
			break
		if g.ok and want != "" and HttpUtil.sha256_bytes(g.body) != want and not str(p).ends_with(".jsonl"):
			g = await request("GET", "/api/file?path=" + p.uri_encode())   # arrived damaged (or changed meanwhile): once more
			if not _alive(active_epoch):
				break
			if g.ok and HttpUtil.sha256_bytes(g.body) != want:
				g = {"ok": false, "code": 409, "error": "The PC file changed during sync or failed its checksum. Retry sync; the existing file was kept.", "body": PackedByteArray(), "json": {}}
		# A local edit while GET was awaiting belongs to the player. Leave its base
		# unchanged so the next sync can merge it against the PC's current version.
		if SyncFiles.sha_of(local_root.path_join(p)) != expected:
			if not out.has("deferred"):
				out["deferred"] = []
			out.deferred.append(p)
			continue
		if g.code == 404:
			if not JsonUtil.remove_file(local_root.path_join(p)):
				job["fail"] = {"ok": false, "code": 507, "error": "Couldn't remove a file on this phone."}
				break
			base.erase(p)
			if not out.has("local_deleted"):
				out["local_deleted"] = []
			out.local_deleted.append(p)
		elif not g.ok:
			if (job.fail as Dictionary).is_empty():
				job["fail"] = g
		else:
			var invalid := SyncFiles.validate(p, g.body)
			if invalid != "":
				job["fail"] = {"ok": false, "code": 422, "error": "The PC sent invalid file data: " + invalid}
				break
			if not SyncFiles.write_atomic(local_root.path_join(p), g.body):
				job["fail"] = {"ok": false, "code": 500, "error": "Couldn't save %s on this phone. Free some storage and sync again." % p}
				break
			base[p] = HttpUtil.sha256_bytes(g.body)
			out.pulled.append(p)
	job["left"] = int(job.left) - 1
	if int(job.left) == 0:
		_pulls_done.emit()


## The phone's own copy of a file it had never synced, kept before the PC's copy replaces it.
func _first_sync_backup(p: String) -> void:
	var src := local_root.path_join(p)
	var dst := local_root.path_join("phone").path_join("first_sync_backup").path_join(p)
	JsonUtil.ensure_dir(dst.get_base_dir())
	DirAccess.copy_absolute(src, dst)


func _save_base(base: Dictionary) -> bool:
	JsonUtil.ensure_dir(base_path().get_base_dir())
	return JsonUtil.write_json(base_path(), base)


func _local_snapshot(slot: String) -> bool:
	var folder := local_root.path_join("slots").path_join(slot)
	if not FileAccess.file_exists(folder.path_join("world.json")):
		return true
	if SyncFiles.snapshot(local_root, slot) == "":
		return false
	var dir := local_root.path_join("slots").path_join(slot).path_join("backups")
	var zips := Array(JsonUtil.list_files(dir, ["zip"])).filter(func(f): return str(f).begins_with("before_sync_"))
	zips.sort()
	while zips.size() > KEEP_LOCAL_SNAPSHOTS:
		DirAccess.remove_absolute(dir.path_join(str(zips.pop_front())))
	return true


## Even a failed sync may have committed files before the failing request. Reload
## those paths so an older in-memory world cannot silently save over them.
func _notify_committed(result: Dictionary) -> void:
	var paths: Array = result.get("pulled", []) + result.get("local_deleted", [])
	if paths.is_empty() or not on_pulled.is_valid():
		return
	var slots := {}
	var home := false
	for path in paths:
		var parts := str(path).split("/")
		if parts.size() > 2 and parts[0] == "slots":
			slots[parts[1]] = true
		elif parts[0] == "my_home":
			home = true
	if home and SaveManager.slot_id != "":
		slots[SaveManager.slot_id] = true
	on_pulled.call(slots.keys(), paths)


func _fail_state(r: Dictionary) -> void:
	if bool(r.get("clock", false)):
		_set_state("error", str(r.error))
	elif int(r.code) == 401:
		_set_state("unpaired", "Not paired: pair this phone again (it keeps your saves).")
	elif int(r.code) == 0:
		_set_state("offline", "PC offline")
	elif int(r.code) == 403:
		_set_state("error", "The PC refused this address or account: %s" % str(r.error))
	else:
		_set_state("error", str(r.error))


# --- HTTP ---------------------------------------------------------------------------------------

## {ok, code, body: PackedByteArray, json: Variant, error}. code 0 = couldn't reach the PC.
## Requests that are safe to repeat are retried on a network hiccup (0.4 s, then 1.2 s).
func request(method: String, path: String, body: PackedByteArray = PackedByteArray()) -> Dictionary:
	return await _request_epoch(method, path, body, _cancel_epoch)


func _request_epoch(method: String, path: String, body: PackedByteArray, epoch: int) -> Dictionary:
	var repeatable := method in ["GET", "PUT", "DELETE"] or path in ["/api/manifest", "/api/sync/begin", "/api/sync/end", "/api/status"]
	var r := await _request_once(method, path, body, epoch)
	for delay in RETRY_DELAYS_S:
		if int(r.code) != 0 or not repeatable or not _alive(epoch):
			break
		var until := Time.get_ticks_msec() + int(delay * 1000.0)
		while Time.get_ticks_msec() < until and _alive(epoch):
			await get_tree().process_frame
		if not _alive(epoch):
			return {"ok": false, "code": 0, "body": PackedByteArray(), "json": {}, "error": "cancelled"}
		r = await _request_once(method, path, body, epoch)
	if sign and int(r.code) == 401 and r.json is Dictionary and bool(r.json.get("clock", false)) and _alive(epoch):
		RequestSig.learn_clock(r.json)   # the PC's time came with the refusal: sign with it, once
		r = await _request_once(method, path, body, epoch)
		if int(r.code) == 401 and r.json is Dictionary and bool(r.json.get("clock", false)):
			r["clock"] = true
			r["error"] = "This phone's clock and the PC's are far apart: set both to the time from the network."
	return r


func _request_once(method: String, path: String, body: PackedByteArray, epoch: int = -1) -> Dictionary:
	var active_epoch := _cancel_epoch if epoch < 0 else epoch
	if not base_url.begins_with("http"):
		return {"ok": false, "code": 0, "body": PackedByteArray(), "json": {}, "error": "PC offline"}
	if not is_inside_tree():
		return {"ok": false, "code": 0, "body": PackedByteArray(), "json": {}, "error": "cancelled"}
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	add_child(http)
	_active_http.append(http)
	var box := {"done": false, "res": []}
	http.request_completed.connect(func(result: int, code: int, hdrs: PackedStringArray, resp_body: PackedByteArray) -> void:
		box["done"] = true
		box["res"] = [result, code, hdrs, resp_body], CONNECT_ONE_SHOT)
	var headers := PackedStringArray([RequestSig.header(token, method, path, body) if sign and token != "" else "Authorization: Bearer " + token])
	if not body.is_empty() and method == "POST":
		headers.append("Content-Type: application/json")
	var methods := {"GET": HTTPClient.METHOD_GET, "PUT": HTTPClient.METHOD_PUT, "POST": HTTPClient.METHOD_POST, "DELETE": HTTPClient.METHOD_DELETE}
	var err := http.request_raw(base_url + path, headers, int(methods.get(method, HTTPClient.METHOD_GET)), body)
	if err != OK:
		_active_http.erase(http)
		http.queue_free()
		return {"ok": false, "code": 0, "body": PackedByteArray(), "json": {}, "error": "couldn't start the request"}
	var deadline := Time.get_ticks_msec() + int((TIMEOUT_S + 5.0) * 1000.0)
	while not bool(box.done) and _alive(active_epoch):
		if Time.get_ticks_msec() >= deadline:
			break
		await get_tree().process_frame
	if is_instance_valid(http):
		_active_http.erase(http)
		if not bool(box.done):
			http.cancel_request()
		http.queue_free()
	if not _alive(active_epoch):
		return {"ok": false, "code": 0, "body": PackedByteArray(), "json": {}, "error": "cancelled"}
	if not bool(box.done):
		return {"ok": false, "code": 0, "body": PackedByteArray(), "json": {}, "error": "PC offline"}
	var res: Array = box.res
	var code := int(res[1]) if int(res[0]) == HTTPRequest.RESULT_SUCCESS else 0
	var bytes: PackedByteArray = res[3]
	var file_download := method == "GET" and path.begins_with("/api/file?")
	var json: Variant = null if file_download else JsonUtil.parse(bytes.get_string_from_utf8())
	var e := ""
	if code == 0:
		e = "PC offline"
	elif code >= 400:
		e = str(json.get("error", "HTTP %d" % code)) if json is Dictionary else "HTTP %d" % code
	return {"ok": code >= 200 and code < 300, "code": code, "body": bytes, "json": json if json != null else {}, "error": e}


## Pairs with a code typed on the phone. Returns {ok, token, phrase, pair_v} or {ok: false, error,
## stale_salt?}. A PC that offers pair_v:1 (GET /api/pairing?wrap=1) gets the PIN sealed to its key
## and sends the key back encrypted (pairing.gd); only a PC that doesn't offer it (an older Polox)
## gets the PIN as is, and never when `require_wrap` (this phone paired with that PC safely before).
## `client_id`: this phone's own id, so pairing again replaces its old entry on the PC instead of adding one.
func pair(code: String, device_name: String, client_id: String = "", require_wrap: bool = false) -> Dictionary:
	var saved := token
	token = ""
	var capability := await request("GET", "/api/pairing?wrap=1")
	if int(capability.code) == 0:
		token = saved
		return {"ok": false, "error": capability.error}
	var offered: bool = capability.ok and capability.json is Dictionary and (capability.json as Dictionary).has("pair_v")
	var body := {"device": device_name, "client": client_id}
	var opener := {}
	if offered:
		var sealed := Pairing.seal_request(capability.json, code)
		if not bool(sealed.ok):
			token = saved
			return {"ok": false, "error": str(sealed.error)}
		body.merge(sealed.body, true)
		opener = sealed.open
	elif require_wrap:
		token = saved   # a PC that paired safely before now answers like an old one: someone may be in between
		return {"ok": false, "error": Pairing.PAIR_FAILED}
	else:
		body["code"] = code
	var r := await request("POST", "/api/pair", JSON.stringify(body).to_utf8_buffer())
	if r.ok and r.json is Dictionary:
		if offered:
			var opened := Pairing.open_answer(r.json, code, opener)
			token = str(opened.token) if bool(opened.ok) else saved
			if not bool(opened.ok):
				return {"ok": false, "error": str(opened.error)}
			sign = true   # this PC knows the phone signs: its key alone never opens anything now
			RequestSig.learn_clock(capability.json)
			return {"ok": true, "token": token, "phrase": str(opened.phrase), "pair_v": Pairing.PAIR_WRAP_VERSION, "sig": true}
		if str(r.json.get("token", "")) != "":
			token = str(r.json.token)
			sign = false
			return {"ok": true, "token": token, "phrase": "", "pair_v": 0, "sig": false}
	if not opener.is_empty():
		Pairing._wipe(opener.secret)
	token = saved
	var failure := {"ok": false, "error": r.error}
	if r.json is Dictionary and bool(r.json.get("stale_salt", false)):
		failure["stale_salt"] = true
	return failure
