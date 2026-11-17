extends RefCounted
## [MIGRATION] [PERSONAL_DATA] Brings what older versions saved elsewhere into the PersonalData folder
## (personal_data.gd), once, without ever deleting or changing the old folders.
##
##   1. PersonalData not in use yet (no settings.json): the first old folder (the "primary": the
##      POLOX_SAVE_ROOT folder, else Documents/Polox, else Documents/PocketDarkWorld) is copied into a
##      staging folder, every file checked by SHA-256 (migration.gd verify_copy), then moved into place.
##      Its settings (AI keys, the active world, Phone Link) become yours.
##   2. Every other old folder adds only what PersonalData doesn't have, whole: a world (slots/<id>)
##      that isn't there yet, a top-level folder or file that isn't there yet. Nothing that exists is
##      replaced, so newer data always wins and a world is never mixed from two copies.
##   3. A note (personal_data_migration.json) records what came from where. With the note there, the
##      migration doesn't run again; run(force = true) repeats step 2 only, which is safe any number of
##      times (it still never replaces anything).
##   4. The Windows setup can ask for more later (a portable copy pointed at during an upgrade):
##      import_requested() runs step 2 for the folders no earlier run has seen.
## Tags: [PERSONAL_DATA] [MIGRATION]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Migration := preload("res://scripts/core/migration.gd")
const NOTE := "personal_data_migration.json"


static func done(target: String) -> bool:
	return FileAccess.file_exists(target.path_join(NOTE))


## Returns {ok, ran, primary, added: [what came from the other folders], files, error}.
static func run(target: String, sources: PackedStringArray, force: bool = false) -> Dictionary:
	var report := {"ok": true, "ran": false, "primary": "", "added": [], "files": 0, "error": ""}
	if sources.is_empty() or (done(target) and not force):
		return report
	report.ran = true
	if not FileAccess.file_exists(target.path_join("settings.json")):
		var primary := sources[0]
		var copied := _copy_whole(primary, target)
		if not copied.ok:
			report.ok = false
			report.error = copied.error
			return report
		report.primary = primary
		report.files = int(copied.files)
	for src in sources:
		if src == report.primary:
			continue
		for item in _add_missing(src, target):
			report.added.append(item)
	var note: Variant = JsonUtil.read_json(target.path_join(NOTE), {})
	var earlier: Array = (note.get("runs", []) as Array) if note is Dictionary else []
	earlier.append({"when": Time.get_datetime_string_from_system(false, false), "primary": report.primary, "added": report.added, "files": report.files, "sources": Array(sources)})
	JsonUtil.write_json(target.path_join(NOTE), {"version": 1, "runs": earlier, "noted": note.get("noted", false) if note is Dictionary else false})
	return report


## The folders in `requested` that no earlier run brought over (compared as written in the note).
static func new_sources(target: String, requested: PackedStringArray) -> PackedStringArray:
	var seen := {}
	var note: Variant = JsonUtil.read_json(target.path_join(NOTE), {})
	if note is Dictionary:
		for earlier_run in note.get("runs", []):
			if earlier_run is Dictionary:
				for source in earlier_run.get("sources", []):
					seen[_comparable(str(source))] = true
	var out := PackedStringArray()
	for folder_path in requested:
		if not seen.has(_comparable(folder_path)) and _comparable(folder_path) != _comparable(target):
			out.append(folder_path)
	return out


## Brings over folders the setup asked for after the first migration already ran. Adds only what
## `target` lacks (whole worlds, whole top-level folders), so it can't replace or mix anything.
## Returns run()'s report; `ran` is false when there was nothing new to look at.
static func import_requested(target: String, requested: PackedStringArray) -> Dictionary:
	var fresh := new_sources(target, requested)
	if fresh.is_empty() or not done(target):
		return {"ok": true, "ran": false, "primary": "", "added": [], "files": 0, "error": ""}
	return run(target, fresh, true)


static func _comparable(folder_path: String) -> String:
	return folder_path.replace("\\", "/").trim_suffix("/").to_lower()


## Copy + verify + move into place. `target` may exist already if it's empty (the write test made it).
static func _copy_whole(from: String, target: String) -> Dictionary:
	var staging := target + ".migrating"
	JsonUtil.remove_tree(staging)   # an attempt that died mid-way
	JsonUtil.copy_tree(from, staging)
	var check := Migration.verify_copy(from, staging)
	if not check.ok:
		JsonUtil.remove_tree(staging)
		return check
	if DirAccess.dir_exists_absolute(target):
		if _has_files(target):
			# Something is there already (not a settings.json, or step 1 wouldn't run): keep it, add the rest.
			for item in _add_missing(staging, target):
				pass
			JsonUtil.remove_tree(staging)
			return check
		JsonUtil.remove_tree(target)
	if DirAccess.rename_absolute(staging, target) != OK:
		JsonUtil.remove_tree(staging)
		return {"ok": false, "files": 0, "bytes": 0, "error": "could not move the copied folder into place"}
	return check


## Adds whole entries `target` lacks: each world folder under slots/, and each other top-level file or
## folder. Returns what was added ("slots/my_world", "notes", ...).
static func _add_missing(from: String, target: String) -> Array:
	var added: Array = []
	JsonUtil.ensure_dir(target)
	for d in DirAccess.get_directories_at(from):
		if d == "slots":
			for slot in DirAccess.get_directories_at(from.path_join("slots")):
				var to := target.path_join("slots").path_join(slot)
				if not DirAccess.dir_exists_absolute(to):
					JsonUtil.copy_tree(from.path_join("slots").path_join(slot), to)
					added.append("slots/" + slot)
		elif not DirAccess.dir_exists_absolute(target.path_join(d)):
			JsonUtil.copy_tree(from.path_join(d), target.path_join(d))
			added.append(d)
	for f in DirAccess.get_files_at(from):
		if f == NOTE or FileAccess.file_exists(target.path_join(f)):
			continue
		DirAccess.copy_absolute(from.path_join(f), target.path_join(f))
		added.append(f)
	return added


static func _has_files(dir: String) -> bool:
	if not DirAccess.get_files_at(dir).is_empty():
		return true
	for d in DirAccess.get_directories_at(dir):
		if _has_files(dir.path_join(d)):
			return true
	return false


## The one-time message on the title screen, or "".
static func pending_note(target: String) -> String:
	var note: Variant = JsonUtil.read_json(target.path_join(NOTE), {})
	if not note is Dictionary or bool(note.get("noted", true)) or (note.get("runs", []) as Array).is_empty():
		return ""
	var first: Dictionary = note.runs[0]
	var from := str(first.get("primary", ""))
	return "Your saves, settings and keys now live in one folder: %s.%s Nothing was deleted: the old folder%s stayed as %s, and you can remove %s once you're happy. Settings > Gameplay > Open Personal Data Folder shows it." % [
		target, (" Copied from %s (%d files, each checked)." % [from, int(first.get("files", 0))]) if from != "" else "",
		"s" if (first.get("sources", []) as Array).size() > 1 else "", "they were" if (first.get("sources", []) as Array).size() > 1 else "it was",
		"them" if (first.get("sources", []) as Array).size() > 1 else "it"]


static func mark_noted(target: String) -> void:
	var path := target.path_join(NOTE)
	var note: Variant = JsonUtil.read_json(path, {})
	if note is Dictionary:
		note["noted"] = true
		JsonUtil.write_json(path, note)
