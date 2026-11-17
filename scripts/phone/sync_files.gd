extends RefCounted
## The file side of Phone Link sync, shared by the PC (server) and the
## phone (client). Works on any save root, so tests can run both in one
## process.
##
## What syncs: library/ plus the chosen slots/<id>/ folders (and your Light World, my_home's home.json,
## osm.json and places/, when the PC shares it: home_shared; never your address, your survey answers,
## the journal, your saved files, the helpers' raw answers or the snapshots), only plain
## data files (json, jsonl, png, jpg, webp), never settings.json, backups/,
## conflicts/, manifest.json or .tmp/.bak/.broken leftovers, nothing over
## the size limits, and not the built-in templates (every copy of the game
## writes its own, stamped with the time it was made). The PC copy is the master. When both sides changed
## a JSON file, the PC merges it field by field against the copy both last agreed on (json_merge.gd;
## the PC keeps those copies in phone/base/): only a value both changed differently keeps the PC's,
## and then the phone's whole file goes to conflicts/ too. Chat logs (.jsonl) merge by message id.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const JsonMerge := preload("res://scripts/sync/json_merge.gd")

const EXTENSIONS: PackedStringArray = ["json", "jsonl", "png", "jpg", "jpeg", "webp"]
const SKIP_DIRS: PackedStringArray = ["backups", "conflicts", "exports", "photos"]
const SKIP_FILES: PackedStringArray = ["manifest.json"]
const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_LOG_BYTES := 16 * 1024 * 1024
## The Light World's files that may sync (inside my_home/): what the house and streets are made of.
const HOME_FILES: PackedStringArray = ["home.json", "osm.json"]
const BASE_DIR := "phone/base"
const BASE_KEEP_DAYS := 30
const BASE_KEEP_FILES := 4000
const BASE_KEEP_BYTES := 64 * 1024 * 1024

## The PC shares your Light World with paired phones (Settings > Light World > On my phone, on by default);
## on a phone: the PC said it does (its manifest).
static var home_shared := false


static func max_bytes(path: String) -> int:
	return MAX_LOG_BYTES if path.ends_with(".jsonl") else MAX_FILE_BYTES


## True if a phone may read or write this path (relative to the save root)
## for these synced slots.
static func allowed(path: String, slots: PackedStringArray) -> bool:
	if not HttpUtil.safe_rel_path(path):
		return false
	if not path.get_extension().to_lower() in EXTENSIONS:
		return false
	var parts := path.split("/")
	if parts.size() < 2:
		return false   # nothing at the root itself (settings.json, polox.json...)
	if parts[0] == "library":
		if parts.size() >= 3 and parts[1] == "templates" and parts[2] in TemplateFactory.BUILTIN:
			return false
	elif parts[0] == "my_home":
		if not home_shared or not home_file(parts):
			return false
	elif parts[0] == "slots" and parts.size() >= 3 and parts[1] in slots:
		if parts[2] in SKIP_DIRS:
			return false
	else:
		return false
	if parts[parts.size() - 1] in SKIP_FILES:
		return false
	return true


## Files whose arrival changes what's on screen (a running game reloads for them): not the cover picture,
## the playtime in slot.json, chat logs or photos.
static func needs_reload(paths: Array) -> bool:
	for p in paths:
		var parts := str(p).split("/")
		if parts.size() >= 2 and parts[0] == "my_home":
			return true   # the Light World's house or streets
		if parts.size() < 3 or parts[0] != "slots":
			continue
		var rest := "/".join(parts.slice(2))
		if rest in ["cover.png", "slot.json", "manifest.json"] or rest.begins_with("logs/") or rest.begins_with("photos/"):
			continue
		return true
	return false


## {path: {sha256, size, mtime}} for everything that syncs under `root`.
static func scan(root: String, slots: PackedStringArray) -> Dictionary:
	var out := {}
	_walk(root, "library", out, slots)
	if home_shared:
		_walk(root, "my_home", out, slots)
	for s in slots:
		if DirAccess.dir_exists_absolute(root.path_join("slots").path_join(s)):
			_walk(root, "slots/" + s, out, slots)
	return out


static func _walk(root: String, rel: String, out: Dictionary, slots: PackedStringArray) -> void:
	var here := root.path_join(rel)
	if not DirAccess.dir_exists_absolute(here):
		return
	for d in DirAccess.get_directories_at(here):
		_walk(root, rel + "/" + d, out, slots)
	for f in DirAccess.get_files_at(here):
		var p := rel + "/" + f
		if not allowed(p, slots):
			continue
		var full := root.path_join(p)
		var file := FileAccess.open(full, FileAccess.READ)
		if file == null:
			continue
		var size := file.get_length()
		file.close()
		if size > max_bytes(p):
			continue
		out[p] = {"sha256": FileAccess.get_sha256(full), "size": size, "mtime": FileAccess.get_modified_time(full)}


## The manifest with revision numbers. Revisions live in `state_path`
## ({path: {sha256, rev}}); a file whose content changed gets rev + 1.
static func manifest(root: String, slots: PackedStringArray, state_path: String) -> Dictionary:
	var files := scan(root, slots)
	var state: Variant = JsonUtil.read_json(state_path, {})
	var revs: Dictionary = state if state is Dictionary else {}
	var changed := false
	for p in files:
		var known: Dictionary = revs.get(p, {}) if revs.get(p) is Dictionary else {}
		if str(known.get("sha256", "")) != str(files[p].sha256):
			revs[p] = {"sha256": files[p].sha256, "rev": int(known.get("rev", 0)) + 1}
			changed = true
		files[p]["rev"] = int(revs[p].rev)
	if changed:
		JsonUtil.ensure_dir(state_path.get_base_dir())
		JsonUtil.write_json(state_path, revs)
	return files


# --- Writing ---------------------------------------------------------------------------------

## Checks a file's bytes before they replace anything: JSON must parse,
## pictures must open. Returns "" if fine, else a reason.
static func validate(path: String, bytes: PackedByteArray) -> String:
	if bytes.size() > max_bytes(path):
		return "too big"
	match path.get_extension().to_lower():
		"json":
			if not JsonUtil.parse(bytes.get_string_from_utf8()) is Dictionary and not JsonUtil.parse(bytes.get_string_from_utf8()) is Array:
				return "not valid JSON"
		"png", "jpg", "jpeg", "webp":
			var img := Image.new()
			var err := OK
			match path.get_extension().to_lower():
				"png":
					err = img.load_png_from_buffer(bytes)
				"webp":
					err = img.load_webp_from_buffer(bytes)
				_:
					err = img.load_jpg_from_buffer(bytes)
			if err != OK or img.is_empty():
				return "not a picture"
	return ""


## Writes atomically (temp file, then rename over the old one).
static func write_atomic(full: String, bytes: PackedByteArray) -> bool:
	return JsonUtil.write_bytes(full, bytes)


static func sha_of(full: String) -> String:
	return FileAccess.get_sha256(full) if FileAccess.file_exists(full) else ""


## Applies an upload from the other side. `base` is the sha256 the sender
## last synced ("" = it believes the file is new). Returns
## {status: applied|same|merged|conflict|rejected, sha256, stash, error}.
static func put(root: String, path: String, bytes: PackedByteArray, base: String) -> Dictionary:
	var why := validate(path, bytes)
	if why != "":
		return {"status": "rejected", "error": why}
	var full := root.path_join(path)
	var cur := sha_of(full)
	var incoming := HttpUtil.sha256_bytes(bytes)
	if cur == incoming:
		keep_base(root, path, bytes)
		return {"status": "same", "sha256": cur}
	if path.ends_with(".jsonl") and cur != "":
		var merged := merge_jsonl(FileAccess.get_file_as_bytes(full), bytes)
		if not write_atomic(full, merged):
			return {"status": "rejected", "error": "couldn't write"}
		return {"status": "merged", "sha256": sha_of(full)}
	if cur == base:
		if not write_atomic(full, bytes):
			return {"status": "rejected", "error": "couldn't write"}
		keep_base(root, path, bytes)
		return {"status": "applied", "sha256": sha_of(full)}
	# Changed on both sides. A JSON file merges field by field against the copy both last agreed on.
	var old := base_bytes(root, base) if path.ends_with(".json") and cur != "" else PackedByteArray()
	if not old.is_empty():
		var b: Variant = JsonUtil.parse(old.get_string_from_utf8())
		var m: Variant = JsonUtil.parse(FileAccess.get_file_as_string(full))
		var t: Variant = JsonUtil.parse(bytes.get_string_from_utf8())
		if b != null and m != null and t != null:
			var r := JsonMerge.merge3(b, m, t)
			var stash := ""
			if not (r.conflicts as Array).is_empty():
				stash = stash_conflict(root, path, bytes)
				if stash == "":
					return {"status": "rejected", "error": "couldn't preserve the phone's conflicting file"}
			var text := JSON.stringify(r.merged, "\t", false).to_utf8_buffer()
			if not write_atomic(full, text):
				return {"status": "rejected", "error": "couldn't write"}
			keep_base(root, path, text)
			if (r.conflicts as Array).is_empty():
				return {"status": "merged", "sha256": sha_of(full)}
			# A value both changed differently: the PC's stays in the merged file; the phone's whole file is kept.
			return {"status": "conflict", "sha256": sha_of(full), "stash": stash, "fields": r.conflicts}
	# No common copy to compare with: the PC version stays, the other one is kept safe.
	var stash := stash_conflict(root, path, bytes)
	if stash == "":
		return {"status": "rejected", "error": "couldn't preserve the phone's conflicting file"}
	return {"status": "conflict", "sha256": cur, "stash": stash}


## The PC's copy of a JSON file as a phone has it (sent to it or taken from it), by content: the common
## ground for merging the next time both sides changed it.
static func keep_base(root: String, path: String, bytes: PackedByteArray) -> void:
	if not path.ends_with(".json") or bytes.is_empty():
		return
	var file := root.path_join(BASE_DIR).path_join(HttpUtil.sha256_bytes(bytes) + ".json")
	if FileAccess.file_exists(file):
		return
	JsonUtil.ensure_dir(file.get_base_dir())
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()


static func base_bytes(root: String, sha: String) -> PackedByteArray:
	if sha.length() != 64 or not sha.is_valid_hex_number():
		return PackedByteArray()
	var file := root.path_join(BASE_DIR).path_join(sha + ".json")
	return FileAccess.get_file_as_bytes(file) if FileAccess.file_exists(file) else PackedByteArray()


## Base copies older than a month go (and the oldest, beyond a few thousand).
static func prune_bases(root: String) -> int:
	var dir := root.path_join(BASE_DIR)
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	var now := Time.get_unix_time_from_system()
	var files: Array = []
	var total_bytes := 0
	for f in DirAccess.get_files_at(dir):
		var file := FileAccess.open(dir.path_join(f), FileAccess.READ)
		var bytes := file.get_length() if file else 0
		if file:
			file.close()
		total_bytes += bytes
		files.append([FileAccess.get_modified_time(dir.path_join(f)), f, bytes])
	files.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and str(a[1]) < str(b[1])))
	var removed := 0
	for i in files.size():
		if now - float(files[i][0]) > BASE_KEEP_DAYS * 86400.0 or files.size() - i > BASE_KEEP_FILES or total_bytes > BASE_KEEP_BYTES:
			DirAccess.remove_absolute(dir.path_join(str(files[i][1])))
			total_bytes -= int(files[i][2])
			removed += 1
	return removed


## my_home/home.json, my_home/osm.json, my_home/places/<id>.json.
static func home_file(parts: PackedStringArray) -> bool:
	if parts.size() == 2:
		return parts[1] in HOME_FILES
	return parts.size() == 3 and parts[1] == "places" and parts[2].ends_with(".json") and parts[2].begins_with("lw_")


## Keep the home before another device changes it. These backups never leave the device.
static func snapshot_home(root: String, keep: int = 20) -> String:
	var home := root.path_join("my_home")
	if not FileAccess.file_exists(home.path_join("home.json")):
		return ""
	var folder := home.path_join("snapshots")
	JsonUtil.ensure_dir(folder)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var zip := folder.path_join("before_sync_%s_%d.zip" % [stamp, Time.get_ticks_usec()])
	var pack := ZIPPacker.new()
	if pack.open(zip) != OK:
		return ""
	var files: Array = ["home.json", "private.json", "osm.json"]
	for file in DirAccess.get_files_at(home.path_join("places")):
		if str(file).ends_with(".json"):
			files.append("places/" + str(file))
	var ok := true
	for rel in files:
		if FileAccess.file_exists(home.path_join(rel)):
			var source := FileAccess.open(home.path_join(rel), FileAccess.READ)
			if source == null:
				ok = false
				break
			var bytes := source.get_buffer(source.get_length())
			source.close()
			if pack.start_file(rel) != OK or pack.write_file(bytes) != OK or pack.close_file() != OK:
				ok = false
				break
	if pack.close() != OK:
		ok = false
	if not ok:
		DirAccess.remove_absolute(zip)
		return ""
	var backups := Array(DirAccess.get_files_at(folder)).filter(func(f): return str(f).begins_with("before_sync_") and str(f).ends_with(".zip"))
	backups.sort()
	while backups.size() > keep:
		DirAccess.remove_absolute(folder.path_join(str(backups.pop_front())))
	return zip


## Removes a file the other side deleted, if it hasn't changed here since.
static func delete(root: String, path: String, base: String) -> Dictionary:
	var full := root.path_join(path)
	var cur := sha_of(full)
	if cur == "":
		return {"status": "same", "sha256": ""}
	if cur != base:
		return {"status": "conflict", "sha256": cur}
	if not JsonUtil.remove_file(full):
		return {"status": "rejected", "sha256": cur, "error": "couldn't delete"}
	return {"status": "applied", "sha256": ""}


## slots/<id>/conflicts/<stamp>/<rest of the path> (or conflicts/library/... at the root).
static func stash_conflict(root: String, path: String, bytes: PackedByteArray) -> String:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_") + "_%03d" % (Time.get_ticks_msec() % 1000)
	var parts := path.split("/")
	var rel := ""
	if parts[0] == "slots":
		rel = "slots/%s/conflicts/%s/%s" % [parts[1], stamp, "/".join(parts.slice(2))]
	else:
		rel = "conflicts/%s/%s" % [stamp, path]
	return rel if write_atomic(root.path_join(rel), bytes) else ""


## Every stashed conflict for a slot: [{path (stash), original, when}].
static func conflicts(root: String, slot: String) -> Array:
	var out: Array = []
	var base := root.path_join("slots").path_join(slot).path_join("conflicts")
	for stamp in JsonUtil.list_dirs(base):
		_collect(base.path_join(stamp), "", stamp, slot, out)
	return out


static func _collect(dir: String, rel: String, stamp: String, slot: String, out: Array) -> void:
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), rel + d + "/", stamp, slot, out)
	for f in DirAccess.get_files_at(dir):
		out.append({"stash": "slots/%s/conflicts/%s/%s%s" % [slot, stamp, rel, f], "original": "slots/%s/%s%s" % [slot, rel, f], "when": stamp})


# --- Chat logs ------------------------------------------------------------------------------------

## A message's id (older lines without one get a stable id from their content).
static func line_id(e: Dictionary) -> String:
	var id := str(e.get("id", ""))
	if id != "":
		return id
	return "h" + HttpUtil.sha256_bytes(("%s|%s|%s|%s" % [e.get("ts", ""), e.get("role", ""), e.get("character", ""), e.get("text", "")]).to_utf8_buffer()).substr(0, 16)


## Union of two JSONL logs by message id, in time order (stable: PC lines first on ties).
static func merge_jsonl(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var seen := {}
	var rows: Array = []
	var n := 0
	for src in [a, b]:
		for line in src.get_string_from_utf8().split("\n"):
			var data: Variant = JsonUtil.parse(line.strip_edges())
			if not data is Dictionary:
				continue
			var id := line_id(data)
			if seen.has(id):
				continue
			seen[id] = true
			rows.append([str(data.get("ts", "")), n, line.strip_edges()])
			n += 1
	rows.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := PackedStringArray()
	for r in rows:
		out.append(str(r[2]))
	return ("\n".join(out) + ("\n" if not out.is_empty() else "")).to_utf8_buffer()


## A safety zip of a slot under any root (backups/before_sync_<stamp>.zip).
static func snapshot(root: String, slot: String, kind: String = "before_sync") -> String:
	var dir := root.path_join("slots").path_join(slot)
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_") + "_%03d" % (Time.get_ticks_msec() % 1000)
	var zip := dir.path_join("backups").path_join("%s_%s.zip" % [kind, stamp])
	JsonUtil.ensure_dir(zip.get_base_dir())
	return zip if SlotArchive.zip_folder(dir, zip) else ""
