extends RefCounted
## Small JSON + filesystem helpers shared by everything that saves.
## Static only, so tests and autoloads can use it without instancing.


## Files that read_json had to rescue from a .tmp/.bak copy (the UI tells
## the player once, then clears this).
static var recoveries: PackedStringArray = []


## Reads a JSON file. Returns `fallback` if the file is missing or broken,
## so a hand-edited save with a typo never crashes the game. A broken or
## missing file is first rescued from its .tmp (a finished write that never
## got renamed) or .bak (the previous good version) sibling.
static func read_json(path: String, fallback: Variant = null) -> Variant:
	var data: Variant = parse_file(path)
	if data != null:
		return data
	var exists := FileAccess.file_exists(path)
	for alt in [path + ".tmp", path + ".bak"]:
		var rescued: Variant = parse_file(alt)
		if rescued != null:
			push_warning("Recovered %s from its %s copy" % [path.get_file(), alt.get_extension()])
			if exists:
				DirAccess.rename_absolute(path, path + ".broken")  # keep the evidence
			write_json(path, rescued)
			recoveries.append(path)
			return rescued
	return fallback


## Parsed contents of one JSON file, or null if missing/empty/broken.
static func parse_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("Could not read %s: %s (line %d)" % [path, json.get_error_message(), json.get_error_line()])
		return null
	return json.data


## Parses JSON text without printing engine errors (AI output and hand-edited
## files are often broken, and that's expected). Returns null on failure.
static func parse(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## Writes pretty JSON atomically: temp file -> read it back -> keep the old
## file as .bak -> rename the temp into place. A crash at any point leaves
## either the old file, the .bak, or the finished .tmp for read_json to find.
static func write_json(path: String, data: Variant) -> bool:
	return write_bytes(path, JSON.stringify(data, "\t", false).to_utf8_buffer())


## Verified replacement shared by saves and sync. The previous file remains recoverable
## as .bak until the new bytes have reached the destination; failures never report success.
static func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	ensure_dir(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.flush()
	var error := f.get_error()
	f.close()
	if error != OK or FileAccess.get_file_as_bytes(tmp) != bytes:
		DirAccess.remove_absolute(tmp)
		return false
	var bak := path + ".bak"
	var had_original := FileAccess.file_exists(path)
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak) and DirAccess.remove_absolute(bak) != OK:
			DirAccess.remove_absolute(tmp)
			return false
		if DirAccess.rename_absolute(path, bak) != OK:
			DirAccess.remove_absolute(tmp)
			return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		if had_original:
			DirAccess.rename_absolute(bak, path)
		DirAccess.remove_absolute(tmp)
		return false
	return true


static func ensure_dir(path: String) -> void:
	if path != "" and not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


## Intentional deletion includes recovery siblings, so read_json cannot revive it.
static func remove_file(path: String) -> bool:
	for suffix in [".tmp", ".bak", ""]:
		if FileAccess.file_exists(path + suffix) and DirAccess.remove_absolute(path + suffix) != OK:
			return false
	return not FileAccess.file_exists(path)


## Fills in keys missing from `data` using `defaults` (recursively for
## dictionaries). This is our whole migration strategy for additive changes.
static func merge_defaults(data: Dictionary, defaults: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	for key in defaults:
		if not out.has(key):
			out[key] = _copy(defaults[key])
		elif out[key] is Dictionary and defaults[key] is Dictionary:
			out[key] = merge_defaults(out[key], defaults[key])
	return out


static func _copy(v: Variant) -> Variant:
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v


## Lists sub-directory names (not paths) of `path`, sorted.
static func list_dirs(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(path):
		return out
	for d in DirAccess.get_directories_at(path):
		if not d.begins_with("."):
			out.append(d)
	out.sort()
	return out


## Lists file names in `path` with one of the given extensions, sorted.
static func list_files(path: String, extensions: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(path):
		return out
	for f in DirAccess.get_files_at(path):
		if f.get_extension().to_lower() in extensions:
			out.append(f)
	out.sort()
	return out


## Turns "Mabel the Moth!" into "mabel_the_moth" for ids and file names.
static func slugify(text: String) -> String:
	var out := ""
	for c in text.to_lower().strip_edges():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif not out.ends_with("_"):
			out += "_"
	out = out.trim_prefix("_").trim_suffix("_")
	return out if out != "" else "thing"


## Recursively deletes a folder. Only ever called on paths inside the save root.
static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


## Recursively copies a folder (used to duplicate rooms/characters).
static func copy_tree(from: String, to: String) -> void:
	ensure_dir(to)
	for d in DirAccess.get_directories_at(from):
		copy_tree(from.path_join(d), to.path_join(d))
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
