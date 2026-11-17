extends RefCounted
## [CLOUD_SYNC] One world as one file: the package that cloud sync writes into a cloud folder
## (docs/SYNC.md). A package is a zip of the world's files plus polox-sync.json, which says which world
## it is, which revision, what it descends from and the SHA-256 of every file inside.
##
## What goes in (TRANSFER ALLOWLIST): only a world's plain data files, the same kinds Phone Link sends
## (sync_files.gd): .json, .jsonl, .png, .jpg, .jpeg, .webp, each under the size limits there. Never:
## backups/, conflicts/, exports/, photos/, manifest.json, recovery leftovers (.tmp .bak .broken .part),
## hidden files, or anything outside the world's own folder. Settings, AI keys, pairing keys, add-ons
## and the Light World (your real home) are not part of a world folder, so they can't be packed.
##
## A package is checked completely before anything in it is used (validate): the zip must be safe to
## unpack, the format must be one this version reads, every file must be on the allowlist, be listed,
## and match its hash, and nothing unlisted may be inside. A cut-off upload or a damaged download
## fails that check and is never applied.
## Tags: [CLOUD_SYNC] [PERSONAL_DATA]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")

## The package format this version writes. Readers accept this number and lower ones.
const FORMAT := 1
const META_FILE := "polox-sync.json"
const EXTENSION := "poloxsync"
const CARD_FILE := "slot.json"
## Fields of the world's card that change every time it is opened. They travel in the package but
## don't count as "the world changed", or two devices that only looked at a world would disagree.
const VOLATILE_CARD_KEYS: PackedStringArray = ["last_played", "playtime_s"]
## How many ancestor revision ids a package remembers (enough to tell "newer than mine" from
## "made without knowing mine" after many syncs on another device).
const HISTORY_LENGTH := 40
const RECOVERY_SUFFIXES: PackedStringArray = [".tmp", ".bak", ".broken", ".part"]


# --- What is in a world ------------------------------------------------------------------------------

## True if `relative` (inside a world folder, forward slashes) may be packed.
static func allowed(relative: String) -> bool:
	if not HttpUtil.safe_rel_path(relative) or relative == META_FILE:
		return false
	if not relative.get_extension().to_lower() in SyncFiles.EXTENSIONS:
		return false
	for suffix in RECOVERY_SUFFIXES:
		if relative.ends_with(suffix):
			return false
	var parts := relative.split("/")
	if parts.size() > 1 and parts[0] in SyncFiles.SKIP_DIRS:
		return false
	return not parts[parts.size() - 1] in SyncFiles.SKIP_FILES


## The world's files that sync: {relative path: sha256}. `skipped` receives the paths that are the
## right kind but over the size limit (they stay on this device; the screen says so).
static func tracked_files(world_dir: String, skipped: Array = []) -> Dictionary:
	var files := {}
	_collect(world_dir, "", files, skipped)
	return files


static func _collect(world_dir: String, relative_dir: String, files: Dictionary, skipped: Array) -> void:
	var here := world_dir.path_join(relative_dir) if relative_dir != "" else world_dir
	for folder_name in DirAccess.get_directories_at(here):
		_collect(world_dir, relative_dir.path_join(folder_name) if relative_dir != "" else folder_name, files, skipped)
	for file_name in DirAccess.get_files_at(here):
		var relative := relative_dir.path_join(file_name) if relative_dir != "" else file_name
		if not allowed(relative):
			continue
		var full := world_dir.path_join(relative)
		var file := FileAccess.open(full, FileAccess.READ)
		if file == null:
			continue
		var size := file.get_length()
		file.close()
		if size > SyncFiles.max_bytes(relative):
			skipped.append(relative)
			continue
		files[relative] = _file_hash(full, relative)


## A file's SHA-256, except the card: its hash ignores the fields that change on every visit.
static func _file_hash(full: String, relative: String) -> String:
	if relative != CARD_FILE:
		return FileAccess.get_sha256(full)
	return card_hash(FileAccess.get_file_as_bytes(full))


static func card_hash(card_bytes: PackedByteArray) -> String:
	var card: Variant = JsonUtil.parse(card_bytes.get_string_from_utf8())
	if not card is Dictionary:
		return HttpUtil.sha256_bytes(card_bytes)
	var stable := (card as Dictionary).duplicate(true)
	for key in VOLATILE_CARD_KEYS:
		stable.erase(key)
	return HttpUtil.sha256_bytes(JSON.stringify(stable, "", true).to_utf8_buffer())


## One hash for a whole set of files: equal when two devices hold the same world content.
static func content_hash(files: Dictionary) -> String:
	var lines := PackedStringArray()
	for relative in files:
		lines.append("%s\t%s" % [relative, files[relative]])
	lines.sort()
	return HttpUtil.sha256_bytes("\n".join(lines).to_utf8_buffer())


# --- Writing ------------------------------------------------------------------------------------------

## Packs the world at `world_dir` into `dest` (written as dest.part, then renamed: a package that was
## cut short never has the final name). `meta` carries world_uid, revision_id, revision, history,
## device_id, device_name, world_name; this adds the format, the file list and the content hash.
## Returns {ok, error, meta, skipped}.
static func build(world_dir: String, dest: String, meta: Dictionary) -> Dictionary:
	var skipped: Array = []
	var files := tracked_files(world_dir, skipped)
	if not files.has("world.json"):
		return {"ok": false, "error": "this world has no world.json to send", "meta": {}, "skipped": skipped}
	var full_meta := meta.duplicate(true)
	full_meta["format"] = FORMAT
	full_meta["files"] = files
	full_meta["content_hash"] = content_hash(files)
	full_meta["saved_at"] = Time.get_datetime_string_from_system(true, false) + "Z"
	full_meta["game_version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	JsonUtil.ensure_dir(dest.get_base_dir())
	var part := dest + ".part"
	var packer := ZIPPacker.new()
	if packer.open(part) != OK:
		return {"ok": false, "error": "couldn't write the package file", "meta": {}, "skipped": skipped}
	var written := _add(packer, META_FILE, JSON.stringify(full_meta, "\t", true).to_utf8_buffer())
	for relative in files:
		if not written:
			break
		var bytes := FileAccess.get_file_as_bytes(world_dir.path_join(relative))
		# The file may have changed since it was hashed (the game saving): pack what was hashed or stop.
		var still_same := (card_hash(bytes) if relative == CARD_FILE else HttpUtil.sha256_bytes(bytes)) == str(files[relative])
		written = still_same and _add(packer, relative, bytes)
	if packer.close() != OK:
		written = false
	if not written:
		DirAccess.remove_absolute(part)
		return {"ok": false, "error": "the world changed while it was being packed; try again", "meta": {}, "skipped": skipped}
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	if DirAccess.rename_absolute(part, dest) != OK:
		DirAccess.remove_absolute(part)
		return {"ok": false, "error": "couldn't finish the package file", "meta": {}, "skipped": skipped}
	return {"ok": true, "error": "", "meta": full_meta, "skipped": skipped}


static func _add(packer: ZIPPacker, name: String, bytes: PackedByteArray) -> bool:
	return packer.start_file(name) == OK and packer.write_file(bytes) == OK and packer.close_file() == OK


# --- Reading ------------------------------------------------------------------------------------------

## The package's polox-sync.json, or {} when the file isn't a readable package. No other checks: use
## validate() before trusting what it says.
static func read_meta(package_path: String) -> Dictionary:
	if not FileAccess.file_exists(package_path):
		return {}
	var parsed: Variant = JsonUtil.parse(SlotArchive.read_zip_file(package_path, META_FILE).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## Checks a whole package. Returns {ok, error, code, meta}. `code` names the reason for the screen:
## "" (fine), "unreadable", "newer_format", "damaged".
static func validate(package_path: String) -> Dictionary:
	var inspected := SlotArchive.inspect_zip(package_path)
	if not inspected.ok:
		return _invalid("unreadable", "The cloud copy can't be opened: it is damaged or was cut off while uploading (%s)." % inspected.error)
	var meta := read_meta(package_path)
	if meta.is_empty() or not meta.get("files") is Dictionary:
		return _invalid("unreadable", "The cloud copy is damaged or isn't a Polox world: it has no sync information in it.")
	if int(meta.get("format", 0)) > FORMAT:
		return {"ok": false, "code": "newer_format", "meta": meta,
			"error": "The cloud copy was saved by a newer Polox (%s). Update Polox on this device to use it." % str(meta.get("game_version", "?"))}
	if int(meta.get("format", 0)) < 1 or str(meta.get("world_uid", "")) == "" or str(meta.get("revision_id", "")) == "":
		return _invalid("damaged", "The cloud copy is damaged: its sync information is incomplete.")
	var listed: Dictionary = meta.files
	var reader := ZIPReader.new()
	if reader.open(package_path) != OK:
		return _invalid("unreadable", "The cloud copy can't be opened: it is damaged or was cut off while uploading.")
	var problem := ""
	var seen := {}
	for name in reader.get_files():
		if name.ends_with("/") or name == META_FILE:
			continue
		if not allowed(name) or not listed.has(name):
			problem = "it contains a file that doesn't belong in a world: " + name
			break
		var bytes := reader.read_file(name)
		if bytes.size() > SyncFiles.max_bytes(name):
			problem = "a file in it is too big: " + name
			break
		var packed_hash := card_hash(bytes) if name == CARD_FILE else HttpUtil.sha256_bytes(bytes)
		if packed_hash != str(listed[name]):
			problem = "a file in it is damaged: " + name
			break
		var invalid := SyncFiles.validate(name, bytes)
		if invalid != "":
			problem = "%s is %s" % [name, invalid]
			break
		seen[name] = true
	reader.close()
	if problem == "" and seen.size() != listed.size():
		problem = "%d of its files are missing" % (listed.size() - seen.size())
	if problem == "" and not listed.has("world.json"):
		problem = "it has no world.json"
	if problem == "" and content_hash(listed) != str(meta.get("content_hash", "")):
		problem = "its file list doesn't match its checksum"
	if problem != "":
		return _invalid("damaged", "The cloud copy is damaged or was cut off while uploading (%s)." % problem)
	return {"ok": true, "error": "", "code": "", "meta": meta}


static func _invalid(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "meta": {}}


## One packed file's bytes (empty when it isn't in the package).
static func read_file(package_path: String, relative: String) -> PackedByteArray:
	return SlotArchive.read_zip_file(package_path, relative)


## A file name for a world's package: readable, safe on every file system, and unique per world.
static func file_name(world_name: String, world_uid: String) -> String:
	var readable := JsonUtil.slugify(world_name)
	if readable == "":
		readable = "world"
	return "%s-%s.%s" % [readable.left(40), world_uid.left(8), EXTENSION]
