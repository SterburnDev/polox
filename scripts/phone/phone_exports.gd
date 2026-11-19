extends RefCounted
## Files exported on a phone (a world's .polox from the Worlds screen, a chat log's .txt) are written into
## Polox's private storage, which no file manager or PC can open. So each one is also:
##   - copied into the phone's Downloads (the app: Download/Polox/ through PoloxAndroid; the browser
##     version: a normal browser download), and
##   - sent to the paired PC (PUT /api/export, export_inbox.gd), which keeps it in its exports folder.
## Files that couldn't go yet (no PC in reach) go the next time the phone connects; what went where is
## remembered in <save root>/phone/exports_shared.json, so nothing is copied or sent twice.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const AndroidNative := preload("res://scripts/core/android_native.gd")

const CHUNK := 4 * 1024 * 1024
static var chunk_bytes := CHUNK   # (tests send smaller chunks)
const SEND_ROUNDS_FACTOR := 4     # send_to_pc gives up after this many times the rounds a file needs
const KINDS := {"polox": "application/octet-stream", "txt": "text/plain", "zip": "application/zip"}
const KEEP_BACKUPS := 3   # of the phone's own manual backups, the newest few go to the PC


static func state_path(root: String) -> String:
	return root.path_join("phone").path_join("exports_shared.json")


static func _state(root: String) -> Dictionary:
	var s: Variant = JsonUtil.read_json(state_path(root), {})
	return s if s is Dictionary else {}


static func _remember(root: String, rel: String, key: String, value: String) -> void:
	var s := _state(root)
	var entry: Dictionary = s.get(rel, {}) if s.get(rel, {}) is Dictionary else {}
	entry["size"] = _size(root.path_join(rel))
	entry["mtime"] = FileAccess.get_modified_time(root.path_join(rel))
	entry[key] = value
	s[rel] = entry
	JsonUtil.ensure_dir(state_path(root).get_base_dir())
	JsonUtil.write_json(state_path(root), s)


## What a file is relative to the save root ("" when it lies outside it).
static func rel_of(root: String, path: String) -> String:
	var r := root.trim_suffix("/") + "/"
	return path.trim_prefix(r) if path.begins_with(r) else ""


## Every exported file on this device: worlds in exports/, chat logs in each world's exports/.
static func exported(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in JsonUtil.list_files(root.path_join("exports"), ["polox"]):
		out.append("exports/" + f)
	var slots := root.path_join("slots")
	if DirAccess.dir_exists_absolute(slots):
		for id in DirAccess.get_directories_at(slots):
			for f in JsonUtil.list_files(slots.path_join(id).path_join("exports"), ["txt"]):
				out.append("slots/%s/exports/%s" % [id, f])
			var backups := Array(JsonUtil.list_files(slots.path_join(id).path_join("backups"), ["zip"])).filter(func(f): return str(f).begins_with("manual_"))
			backups.sort()
			for f in backups.slice(maxi(0, backups.size() - KEEP_BACKUPS)):
				out.append("slots/%s/backups/%s" % [id, f])
	return out


## True when this file (as it is now) already went to `key` ("downloads" or "pc").
static func done(root: String, rel: String, key: String) -> bool:
	var entry: Variant = _state(root).get(rel, {})
	var path := root.path_join(rel)
	return entry is Dictionary and str(entry.get(key, "")) != "" and int(entry.get("size", -1)) == _size(path) 		and int(entry.get("mtime", -1)) == FileAccess.get_modified_time(path)


## A copy in the phone's Downloads. Returns where it went for the player to read
## ("Download/Polox/x.polox", "your browser's downloads"), "" when this device can't.
static func save_to_downloads(root: String, path: String) -> String:
	var mime := str(KINDS.get(path.get_extension().to_lower(), "application/octet-stream"))
	var where := ""
	if OS.has_feature("web"):
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			JavaScriptBridge.download_buffer(bytes, path.get_file(), mime)
			where = "your browser's downloads"
	elif OS.has_feature("android"):
		where = AndroidNative.save_to_downloads(ProjectSettings.globalize_path(path), path.get_file(), mime)
	var rel := rel_of(root, path)
	if where != "" and rel != "":
		_remember(root, rel, "downloads", where)
	return where


## The app on start: every export not in Downloads yet goes there (exports made before 1.27.17 too).
static func copy_missing_to_downloads(root: String) -> int:
	if not OS.has_feature("android"):
		return 0
	var n := 0
	for rel in exported(root):
		if not done(root, rel, "downloads") and save_to_downloads(root, root.path_join(rel)) != "":
			n += 1
	return n


## Sends one file to the paired PC through `client` (sync_client.gd). Returns {ok, saved, error}:
## saved is where the PC keeps it ("exports/x.polox").
static func send_to_pc(client: Node, root: String, path: String) -> Dictionary:
	var total := _size(path)
	if total <= 0:
		return {"ok": false, "saved": "", "error": "the file is missing"}
	var sha := FileAccess.get_sha256(path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "saved": "", "error": "couldn't read the file"}
	var offset := 0
	var restarts := 0
	var result := {"ok": false, "saved": "", "error": "the PC didn't take the file"}
	# Every round sends one part. A PC that takes whole parts needs total / part rounds; this allows
	# a few times that (short takes, the three restarts) and then stops, whatever the PC answers.
	var rounds_left := (total / maxi(1, chunk_bytes) + 1) * SEND_ROUNDS_FACTOR + 8
	while rounds_left > 0 and is_instance_valid(client) and client.is_inside_tree():
		rounds_left -= 1
		f.seek(offset)
		var chunk := f.get_buffer(mini(chunk_bytes, total - offset))
		var q := "/api/export?name=%s&offset=%d&total=%d&sha256=%s&slot=%s" % [path.get_file().uri_encode(), offset, total, sha, _slot_of(root, path).uri_encode()]
		var r: Dictionary = await client.request("PUT", q, chunk)
		var j: Dictionary = r.get("json") if r.get("json") is Dictionary else {}   # (a failed request has no body)
		if int(r.get("code", 0)) == 409 and j.has("have") and restarts < 3:
			offset = clampi(int(j.have), 0, total)   # the PC holds a different amount: carry on from there
			restarts += 1
			continue
		if not bool(r.get("ok", false)):
			result = {"ok": false, "saved": "", "error": str(r.get("error", "not sent"))}
			break
		if bool(j.get("done", false)):
			result = {"ok": true, "saved": str(j.get("saved", "")), "error": ""}
			break
		var have := int(j.get("have", -1))
		if have <= offset or have > total:
			result = {"ok": false, "saved": "", "error": "the PC didn't take the file"}
			break
		offset = have
	f.close()
	var rel := rel_of(root, path)
	if bool(result.ok) and rel != "":
		_remember(root, rel, "pc", str(result.saved))
	return result


## Every export the PC doesn't have yet. Returns how many went.
static func send_missing_to_pc(client: Node, root: String) -> int:
	var n := 0
	for rel in exported(root):
		if done(root, rel, "pc"):
			continue
		var r: Dictionary = await send_to_pc(client, root, root.path_join(rel))
		if bool(r.get("ok", false)):
			n += 1
		elif str(r.get("error", "")) == "PC offline":
			break
	return n


## The world a backup belongs to ("" for anything else).
static func _slot_of(root: String, path: String) -> String:
	var parts := rel_of(root, path).split("/")
	return parts[1] if parts.size() == 4 and parts[0] == "slots" and parts[2] == "backups" else ""


static func _size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n
