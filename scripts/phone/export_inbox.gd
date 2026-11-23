extends RefCounted
## The PC's side of "send my export to the PC": a paired phone uploads a file it exported (a world's
## .polox, a chat log's .txt) in chunks, and the PC files it under <save root>/exports/, where the
## Worlds screen's "Import .polox" and Explorer can reach it.
##
##   PUT /api/export?name=<file>&offset=<bytes already sent>&total=<bytes>&sha256=<hex>   body = the next chunk
##   -> 200 {ok, done, have, saved}   (saved = "exports/<name>" once the whole file arrived and checked out)
##   -> 409 {have}                    (the PC holds a different amount: carry on from `have`)
##
## A chunk is written at its offset only when the partial file is exactly that long, so a repeated
## request never doubles a chunk. The finished file must match its SHA-256, and a .polox must be a
## Polox world (a zip with world.json) before it leaves exports/.incoming/.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")

const EXTENSIONS: PackedStringArray = ["polox", "txt", "zip"]   # zip = a world backup made on the phone (Backup button)
const BACKUPS := "phone_backups"
const CHUNK_MAX := 8 * 1024 * 1024                    # (the client sends 4 MB; the server reads up to 16 MB)
const MAX_TOTAL := SlotArchive.MAX_BUNDLE_BYTES       # the biggest world a bundle may hold
const INCOMING := ".incoming"
const PART_MAX_AGE_S := 24.0 * 3600.0


## Abandoned chunks are not part of a world or a report. Collect them after a
## day, both when Phone Link starts and whenever another chunk arrives.
static func sweep(root: String, now_s: float = -1.0) -> int:
	var inbox := folder(root).path_join(INCOMING)
	if not DirAccess.dir_exists_absolute(inbox):
		return 0
	var now := Time.get_unix_time_from_system() if now_s < 0.0 else now_s
	var removed := 0
	for name in DirAccess.get_files_at(inbox):
		if not str(name).ends_with(".part"):
			continue
		var path := inbox.path_join(str(name))
		var modified := FileAccess.get_modified_time(path)
		if modified > 0 and now - float(modified) > PART_MAX_AGE_S and DirAccess.remove_absolute(path) == OK:
			removed += 1
	return removed


## A plain file name a phone may send ("" when it isn't one).
static func clean_name(name: String) -> String:
	var n := name.strip_edges()
	if n == "" or n.length() > 120 or n != n.get_file() or n.begins_with(".") or n.contains("..") or not n.is_valid_filename():
		return ""
	return n if n.get_extension().to_lower() in EXTENSIONS else ""


static func folder(root: String) -> String:
	return root.path_join("exports")


## Where a finished file goes: exports/ (worlds, chat logs) or phone_backups/<world>/ (backup zips).
static func destination(root: String, name: String, slot: String) -> String:
	if name.get_extension().to_lower() == "zip":
		var world := slot if slot != "" and slot.is_valid_filename() and slot == slot.get_file() and not slot.begins_with(".") else "world"
		return root.path_join(BACKUPS).path_join(world)
	return folder(root)


## One chunk. Returns [http status, response dictionary].
static func receive(root: String, device_id: String, query: Dictionary, body: PackedByteArray) -> Array:
	sweep(root)
	var name := clean_name(str(query.get("name", "")))
	var total := str(query.get("total", "")).to_int()
	var offset := str(query.get("offset", "")).to_int()
	var sha := str(query.get("sha256", "")).to_lower()
	if name == "":
		return [400, {"ok": false, "error": "only a .polox world or a .txt chat log can be sent"}]
	if sha.length() != 64 or not sha.is_valid_hex_number():
		return [400, {"ok": false, "error": "missing checksum"}]
	if total <= 0 or total > MAX_TOTAL:
		return [413, {"ok": false, "error": "too big to send to the PC"}]
	if body.size() > CHUNK_MAX or offset < 0 or offset + body.size() > total or (body.is_empty() and offset < total):
		return [400, {"ok": false, "error": "bad chunk"}]
	var inbox := folder(root).path_join(INCOMING)
	JsonUtil.ensure_dir(inbox)
	var part := inbox.path_join("%s_%s.part" % [device_id.validate_filename().left(32), sha])
	var have := _size(part)
	if offset != have:
		if offset == 0:
			DirAccess.remove_absolute(part)   # starting over
			have = 0
		else:
			return [409, {"ok": false, "error": "carry on from %d" % have, "have": have}]
	var f := FileAccess.open(part, FileAccess.READ_WRITE if have > 0 else FileAccess.WRITE)
	if f == null:
		return [507, {"ok": false, "error": "the PC couldn't write the file (disk full?)"}]
	f.seek(have)
	f.store_buffer(body)
	f.close()
	have = _size(part)
	if have < total:
		return [200, {"ok": true, "done": false, "have": have}]
	var got := FileAccess.get_sha256(part)
	if got != sha:
		DirAccess.remove_absolute(part)
		return [422, {"ok": false, "error": "the file arrived changed: send it again", "have": 0}]
	if name.get_extension().to_lower() in ["polox", "zip"]:
		var check := SlotArchive.inspect_zip(part)
		if not bool(check.get("ok", false)) or not "world.json" in check.get("files", []):
			DirAccess.remove_absolute(part)
			return [415, {"ok": false, "error": "that isn't a Polox world", "have": 0}]
	var dir := destination(root, name, str(query.get("slot", "")))
	JsonUtil.ensure_dir(dir)
	var dest := _free_name(dir, name, sha)
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(part)   # the same file is already there
	elif DirAccess.rename_absolute(part, dest) != OK:
		return [507, {"ok": false, "error": "the PC couldn't keep the file (disk full?)"}]
	return [200, {"ok": true, "done": true, "have": have, "saved": dest.trim_prefix(root.trim_suffix("/") + "/")}]


## exports/<name>, or "<name> (2)" and so on when another file has the name; a file with the same
## checksum counts as already there.
static func _free_name(dir: String, name: String, sha: String) -> String:
	var base := name.get_basename()
	var ext := name.get_extension()
	var candidate := dir.path_join(name)
	var n := 2
	while FileAccess.file_exists(candidate) and FileAccess.get_sha256(candidate) != sha and n < 1000:
		candidate = dir.path_join("%s (%d).%s" % [base, n, ext])
		n += 1
	return candidate


static func _size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n
