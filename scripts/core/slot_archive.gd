extends RefCounted
## Zips for a save slot: rolling snapshots (autosave/manual/quick), the
## restore timeline, .polox bundles (export/import, validated), a SHA-256
## manifest and a verify pass that spots broken files.
## Tags: [PERSONAL_DATA]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Slots := preload("res://scripts/core/slots.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")

const BUNDLE_EXT := "polox"
const MANIFEST := "manifest.json"
## Folders inside a slot that never go into a snapshot or bundle.
const SKIP_DIRS: PackedStringArray = ["backups", "conflicts"]
const MAX_BUNDLE_FILES := 20000
const MAX_BUNDLE_BYTES := 512 * 1024 * 1024


static func backups_dir(id: String) -> String:
	return Slots.dir(id).path_join("backups")


# --- Snapshots ----------------------------------------------------------------------------

## Zips the slot into backups/<kind>_<stamp>.zip. kind: auto | manual | quick | before_restore | pre_migration
static func snapshot(id: String, kind: String = "manual") -> String:
	var zip_path := snapshot_path(id, kind)
	if zip_path == "" or not zip_folder(Slots.dir(id), zip_path):
		return ""
	return zip_path


## The main-thread half of a snapshot: the manifest written and the zip's path ("" when the slot is
## gone). zip_folder(Slots.dir(id), path) is the half that may run on a worker thread.
static func snapshot_path(id: String, kind: String) -> String:
	if not Slots.exists(id):
		return ""
	write_manifest(id)
	JsonUtil.ensure_dir(backups_dir(id))
	# Milliseconds keep two snapshots in the same second apart.
	var stamp := "%s_%03d" % [Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_"), Time.get_ticks_msec() % 1000]
	return backups_dir(id).path_join("%s_%s.zip" % [kind, stamp])


## Every backup of a slot, newest first: {path, kind, stamp, bytes, when}.
static func backups(id: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("^(.*?)_(\\d{4}-\\d{2}-\\d{2}_\\d{6}(?:_\\d+)?)$")  # kind_YYYY-MM-DD_HHMMSS[_ms]
	for f in JsonUtil.list_files(backups_dir(id), ["zip"]):
		var base := f.get_basename()
		var m := re.search(base)
		var kind := m.get_string(1) if m else base
		var stamp := m.get_string(2) if m else ""
		var fa := FileAccess.open(backups_dir(id).path_join(f), FileAccess.READ)
		out.append({"path": backups_dir(id).path_join(f), "kind": kind, "stamp": stamp, "bytes": fa.get_length() if fa else 0,
			"when": stamp.replace("_", " ").replace("T", " ")})
	out.sort_custom(func(a, b): return str(a.stamp) > str(b.stamp))
	return out


## Keeps only the newest `keep` automatic snapshots (manual ones are never pruned).
static func prune(id: String, keep: int) -> int:
	var autos: Array = backups(id).filter(func(b): return str(b.kind) in ["auto", "quick"])
	var removed := 0
	for i in range(keep, autos.size()):
		DirAccess.remove_absolute(str(autos[i].path))
		removed += 1
	return removed


## Validate extracted content before touching live files. Keep both a snapshot and
## the original files (including recovery siblings) until installation succeeds.
static func restore_backup(id: String, zip_path: String) -> Dictionary:
	if not Slots.exists(id) or not FileAccess.file_exists(zip_path):
		return {"ok": false, "error": "backup not found"}
	var check := inspect_zip(zip_path)
	if not check.ok:
		return check
	for rel in check.files:
		if str(rel).get_slice("/", 0).to_lower() in SKIP_DIRS:
			return {"ok": false, "error": "backup contains reserved recovery folder: " + str(rel)}
	var d := Slots.dir(id)
	var work := backups_dir(id).path_join(".restore_%d" % Time.get_ticks_usec())
	if DirAccess.dir_exists_absolute(work) or DirAccess.make_dir_recursive_absolute(work) != OK:
		return {"ok": false, "error": "could not create restore staging folder"}
	var staged := work.path_join("staged")
	var result := unzip_to(zip_path, staged)
	if result.ok:
		result = _validate_restore(staged)
	if not result.ok:
		JsonUtil.remove_tree(work)
		return result
	if snapshot(id, "before_restore") == "":
		JsonUtil.remove_tree(work)
		return {"ok": false, "error": "could not snapshot the current state first"}
	result = _install_restore(d, staged, work.path_join("original"))
	if result.ok:
		JsonUtil.remove_tree(work)
		SaveManager.forget_baselines_under(d)
	return result


static func _validate_restore(folder: String) -> Dictionary:
	# Do not use read_json: a broken primary must not silently pass via .bak/.tmp.
	var world: Variant = JsonUtil.parse(FileAccess.get_file_as_string(folder.path_join("world.json"))) if FileAccess.file_exists(folder.path_join("world.json")) else null
	if not world is Dictionary:
		return {"ok": false, "error": "backup has no valid world.json object"}
	if (world.has("name") and not world.name is String) or (world.has("player") and not world.player is Dictionary):
		return {"ok": false, "error": "backup world.json has invalid world content"}
	var start: Variant = world.get("start_room", "home")
	if not start is String or start == "" or start.get_file() != start or start.contains("\\") or start.contains(":") or start.contains(".."):
		return {"ok": false, "error": "backup world.json has an invalid start_room"}
	# Older worlds may omit start_room or refer to a removed room. GameState
	# falls back to another saved room; do not reject that supported layout.
	for file in JsonUtil.list_files(folder.path_join("rooms"), ["json"]):
		var room: Variant = JsonUtil.parse(FileAccess.get_file_as_string(folder.path_join("rooms").path_join(file)))
		if room is Dictionary:
			return {"ok": true, "error": ""}
	return {"ok": false, "error": "backup contains no valid room object in rooms/"}


## Rename whole entries on the same filesystem, checking every move. On failure
## restore moved originals; retain the recovery folder even if rollback fails.
static func _install_restore(live: String, staged: String, original: String) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(original) != OK:
		return {"ok": false, "error": "could not create rollback folder", "recovery": original.get_base_dir()}
	# Persist locations before the first move so an interrupted process still
	# leaves an explicit recovery record alongside its untouched originals.
	if not JsonUtil.write_json(original.get_base_dir().path_join("recovery.json"), {"live": live, "original": original, "staged": staged, "instruction": "Restore entries from original into live; unmoved originals remain in live. A before_restore ZIP is also in backups."}):
		return {"ok": false, "error": "could not write restore recovery record", "recovery": original.get_base_dir()}
	var moved: Array = []
	var installed: Array = []
	var error := ""
	var entries := DirAccess.get_directories_at(live)
	entries.append_array(DirAccess.get_files_at(live))
	for entry in entries:
		if entry in SKIP_DIRS or (entry == Slots.META and not FileAccess.file_exists(staged.path_join(Slots.META))):
			continue
		if DirAccess.rename_absolute(live.path_join(entry), original.path_join(entry)) != OK:
			error = "could not preserve " + entry
			break
		moved.append(entry)
	if error == "":
		entries = DirAccess.get_directories_at(staged)
		entries.append_array(DirAccess.get_files_at(staged))
		for entry in entries:
			if DirAccess.rename_absolute(staged.path_join(entry), live.path_join(entry)) != OK:
				error = "could not install " + entry
				break
			installed.append(entry)
	if error == "":
		return {"ok": true, "error": ""}
	var rolled_back := true
	for entry in installed:
		if DirAccess.rename_absolute(live.path_join(entry), staged.path_join(entry)) != OK:
			rolled_back = false
	for entry in moved:
		if DirAccess.rename_absolute(original.path_join(entry), live.path_join(entry)) != OK:
			rolled_back = false
	return {"ok": false, "error": error + ("; original files restored" if rolled_back else "; rollback incomplete") + "; recovery: " + original.get_base_dir(), "recovery": original.get_base_dir()}


# --- Bundles (.polox) -----------------------------------------------------------------------

static func export_bundle(id: String, dest: String) -> bool:
	if not Slots.exists(id):
		return false
	write_manifest(id)
	JsonUtil.ensure_dir(dest.get_base_dir())
	return zip_folder(Slots.dir(id), dest)


## Unpacks a validated bundle into a new slot. Returns {ok, id, error}.
static func import_bundle(path: String, name_hint: String = "") -> Dictionary:
	var check := inspect_zip(path)
	if not check.ok:
		return {"ok": false, "id": "", "error": check.error}
	if not "world.json" in check.files:
		return {"ok": false, "id": "", "error": "not a Polox world (no world.json inside)"}
	var meta_bytes: PackedByteArray = check.get("meta", PackedByteArray())
	var card: Variant = JsonUtil.parse(meta_bytes.get_string_from_utf8()) if not meta_bytes.is_empty() else null
	var name := name_hint if name_hint != "" else (str(card.get("name", "")) if card is Dictionary else path.get_file().get_basename())
	var id := Slots.create(name)
	var r := unzip_to(path, Slots.dir(id))
	if not r.ok:
		JsonUtil.remove_tree(Slots.dir(id))
		return {"ok": false, "id": "", "error": r.error}
	var m := Slots.meta(id)
	m["name"] = name if name != "" else m.name
	m["last_played"] = ""
	m["playtime_s"] = 0
	Slots.save_meta(id, m)
	return {"ok": true, "id": id, "error": ""}


# --- Manifest / verify ------------------------------------------------------------------------

## Writes manifest.json: {relative path: sha256} for every world file.
static func write_manifest(id: String) -> Dictionary:
	var d := Slots.dir(id)
	var files := {}
	for rel in _walk(d):
		if rel == MANIFEST or rel.get_file() == Slots.META:
			continue
		files[rel] = FileAccess.get_sha256(d.path_join(rel))
	JsonUtil.write_json(d.path_join(MANIFEST), {"version": 1, "written": Time.get_datetime_string_from_system(false, false), "files": files})
	return files


## Checks every file in the slot. Returns {ok, issues: [{file, problem, severity}], files, bytes}.
## severity: "broken" (data lost unless restored) | "changed" (differs from the
## manifest: hand edit or damage) | "note".
static func verify(id: String) -> Dictionary:
	var d := Slots.dir(id)
	var issues: Array = []
	var files := 0
	var bytes := 0
	var manifest: Variant = JsonUtil.read_json(d.path_join(MANIFEST), {})
	var known: Dictionary = manifest.get("files", {}) if manifest is Dictionary else {}
	for rel in _walk(d):
		files += 1
		var full := d.path_join(rel)
		var fa := FileAccess.open(full, FileAccess.READ)
		bytes += fa.get_length() if fa else 0
		if rel.get_extension() == "json" and rel != MANIFEST:
			if JsonUtil.parse_file(full) == null:
				var has_backup := JsonUtil.parse_file(full + ".bak") != null or JsonUtil.parse_file(full + ".tmp") != null
				issues.append({"file": rel, "problem": "can't be read" + (" (a .bak copy exists and will be used)" if has_backup else ""), "severity": "note" if has_backup else "broken"})
		elif rel.get_extension() == "png":
			var img := Image.load_from_file(full)
			if img == null or img.is_empty():
				issues.append({"file": rel, "problem": "picture can't be opened", "severity": "broken"})
		if known.has(rel) and str(known[rel]) != FileAccess.get_sha256(full) and rel.get_extension() == "json":
			issues.append({"file": rel, "problem": "differs from the last manifest (edited by hand, or damaged)", "severity": "changed"})
	for rel in known:
		if not FileAccess.file_exists(d.path_join(rel)):
			issues.append({"file": rel, "problem": "missing since the last manifest", "severity": "broken" if rel.get_extension() == "json" else "note"})
	if not FileAccess.file_exists(d.path_join("world.json")):
		issues.append({"file": "world.json", "problem": "missing", "severity": "broken"})
	for c in JsonUtil.list_dirs(d.path_join("characters")):
		var cj := d.path_join("characters").path_join(c).path_join("character.json")
		var data: Variant = JsonUtil.parse_file(cj)
		if data is Dictionary:
			for e in data.get("expressions", {}):
				if not FileAccess.file_exists(d.path_join("characters").path_join(c).path_join(str(data.expressions[e]))):
					issues.append({"file": "characters/%s/%s" % [c, data.expressions[e]], "problem": "face picture missing", "severity": "note"})
	var broken := issues.any(func(i): return i.severity == "broken")
	return {"ok": not broken, "issues": issues, "files": files, "bytes": bytes}


# --- Zip helpers ----------------------------------------------------------------------------

static func _walk(d: String, rel_dir: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var abs_dir := d.path_join(rel_dir) if rel_dir != "" else d
	for sub in DirAccess.get_directories_at(abs_dir):
		if rel_dir == "" and sub in SKIP_DIRS:
			continue
		out.append_array(_walk(d, rel_dir.path_join(sub) if rel_dir != "" else sub))
	for f in DirAccess.get_files_at(abs_dir):
		if f.ends_with(".tmp") or f.ends_with(".bak") or f.ends_with(".broken"):
			continue
		out.append(rel_dir.path_join(f) if rel_dir != "" else f)
	return out


## Zips into "<zip>.part" and renames it when complete, so a zip cut short (the app killed in the
## background) never shows up as a backup.
static func zip_folder(folder: String, zip_path: String) -> bool:
	# Directory enumeration returns an empty list on failure. Never replace a good archive with
	# an empty zip when its source disappeared (for example while a world was being removed).
	if DirAccess.open(folder) == null:
		return false
	var part := zip_path + ".part"
	if not _zip_into(folder, part, zip_path):
		DirAccess.remove_absolute(part)
		return false
	if DirAccess.rename_absolute(part, zip_path) == OK:
		return true
	DirAccess.remove_absolute(zip_path)   # an older file of that name (an export saved again)
	if DirAccess.rename_absolute(part, zip_path) == OK:
		return true
	DirAccess.remove_absolute(part)
	return false


static func _zip_into(folder: String, zip_path: String, final_path: String) -> bool:
	var zip := ZIPPacker.new()
	if zip.open(zip_path) != OK:
		return false
	var ok := true
	for rel in _walk(folder):
		# A snapshot destination can live under the source (layout migration).
		if folder.path_join(rel).simplify_path() in [zip_path.simplify_path(), final_path.simplify_path()]:
			continue
		var source := FileAccess.open(folder.path_join(rel), FileAccess.READ)
		if source == null:
			ok = false
			break
		var length := source.get_length()
		var bytes := source.get_buffer(length)
		source.close()
		if bytes.size() != length:
			ok = false
			break
		if zip.start_file(rel) != OK or zip.write_file(bytes) != OK or zip.close_file() != OK:
			ok = false
			break
	if zip.close() != OK:
		ok = false
	if not ok:
		DirAccess.remove_absolute(zip_path)
	return ok


## Opens a zip and refuses anything that could write outside the target.
## Returns {ok, error, files, bytes, meta (slot.json bytes if present)}.
static func inspect_zip(zip_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"ok": false, "error": "not a zip file", "files": []}
	var files := reader.get_files()
	if files.size() > MAX_BUNDLE_FILES:
		reader.close()
		return {"ok": false, "error": "too many files", "files": []}
	var bytes := 0
	var seen := {}
	for f in files:
		var key := f.trim_suffix("/").to_lower()
		var unsafe := f.begins_with("/") or f.contains("\\") or f.find("..") != -1 or f.find(":") != -1 or seen.has(key)
		for part in f.trim_suffix("/").split("/"):
			unsafe = unsafe or part == "" or part.ends_with(".") or part.ends_with(" ")
		if unsafe:
			reader.close()
			return {"ok": false, "error": "unsafe path inside the bundle: " + f, "files": []}
		seen[key] = true
		if f.ends_with("/"):
			continue
		bytes += reader.read_file(f).size()
		if bytes > MAX_BUNDLE_BYTES:
			reader.close()
			return {"ok": false, "error": "bundle is too big", "files": []}
	var meta := reader.read_file(Slots.META) if Slots.META in files else PackedByteArray()
	reader.close()
	return {"ok": true, "error": "", "files": files, "bytes": bytes, "meta": meta}


## One file's bytes out of a zip (empty if missing).
static func read_zip_file(zip_path: String, name: String) -> PackedByteArray:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return PackedByteArray()
	var out := reader.read_file(name) if name in reader.get_files() else PackedByteArray()
	reader.close()
	return out


static func unzip_to(zip_path: String, folder: String) -> Dictionary:
	var check := inspect_zip(zip_path)
	if not check.ok:
		return check
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"ok": false, "error": "not a zip file"}
	for f in reader.get_files():
		if f.ends_with("/"):
			continue
		var dest := folder.path_join(f)
		JsonUtil.ensure_dir(dest.get_base_dir())
		var fa := FileAccess.open(dest, FileAccess.WRITE)
		if fa == null:
			reader.close()
			return {"ok": false, "error": "could not write " + f}
		var contents := reader.read_file(f)
		fa.store_buffer(contents)
		fa.flush()
		var error := fa.get_error()
		fa.close()
		if error != OK or FileAccess.get_file_as_bytes(dest) != contents:
			reader.close()
			return {"ok": false, "error": "could not verify extracted file " + f}
	reader.close()
	return {"ok": true, "error": ""}
