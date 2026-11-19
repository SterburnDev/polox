extends RefCounted
## One-time move from the old save folder (Documents/PocketDarkWorld) to the
## new one (Documents/Polox). The old folder is COPIED, verified file by file
## (SHA-256), and only then switched to; it is never moved or deleted. A note
## in migration.json lets the title screen tell the player once.
## Tags: [PERSONAL_DATA] [MIGRATION]

const JsonUtil := preload("res://scripts/core/json_util.gd")

## The only place the old name lives (see tests/test_rename.gd).
const LEGACY_FOLDER_NAME := "PocketDarkWorld"
const NOTE_FILE := "migration.json"


## Old save folder next to the new one, e.g. .../Documents/PocketDarkWorld.
static func legacy_root(new_root: String) -> String:
	return new_root.get_base_dir().path_join(LEGACY_FOLDER_NAME)


## True when there is an old world to bring over and no new folder yet.
static func needs_copy(new_root: String) -> bool:
	var old := legacy_root(new_root)
	if DirAccess.dir_exists_absolute(new_root):
		return false
	return FileAccess.file_exists(old.path_join("world.json")) or FileAccess.file_exists(old.path_join("settings.json"))


## Copies the old folder into a temporary sibling, verifies every file, then
## renames it into place so a crash mid-copy can never leave a half folder
## that looks real. Returns {ok, files, bytes, error}.
static func copy_and_verify(new_root: String) -> Dictionary:
	var old := legacy_root(new_root)
	var staging := new_root + ".migrating"
	JsonUtil.remove_tree(staging)  # a previous attempt that died mid-way
	JsonUtil.copy_tree(old, staging)
	var report := verify_copy(old, staging)
	if not report.ok:
		JsonUtil.remove_tree(staging)
		return report
	if DirAccess.rename_absolute(staging, new_root) != OK:
		JsonUtil.remove_tree(staging)
		return {"ok": false, "files": 0, "bytes": 0, "error": "could not rename the copied folder into place"}
	JsonUtil.write_json(new_root.path_join(NOTE_FILE), {
		"version": 1,
		"from": old,
		"when": Time.get_datetime_string_from_system(false, false),
		"files": report.files,
		"bytes": report.bytes,
		"verified": true,
		"noted": false,
	})
	return report


## Every file under `from` must exist under `to` with the same SHA-256.
static func verify_copy(from: String, to: String) -> Dictionary:
	var files := 0
	var bytes := 0
	var queue: Array[String] = [""]
	while not queue.is_empty():
		var rel: String = queue.pop_back()
		var src_dir := from.path_join(rel) if rel != "" else from
		for d in DirAccess.get_directories_at(src_dir):
			queue.append(rel.path_join(d) if rel != "" else d)
		for f in DirAccess.get_files_at(src_dir):
			var r := rel.path_join(f) if rel != "" else f
			var a := from.path_join(r)
			var b := to.path_join(r)
			if not FileAccess.file_exists(b):
				return {"ok": false, "files": files, "bytes": bytes, "error": "missing after copy: " + r}
			if FileAccess.get_sha256(a) != FileAccess.get_sha256(b):
				return {"ok": false, "files": files, "bytes": bytes, "error": "copy differs: " + r}
			files += 1
			var fa := FileAccess.open(b, FileAccess.READ)
			if fa:
				bytes += fa.get_length()
	return {"ok": true, "files": files, "bytes": bytes, "error": ""}


## The one-time message for the player, or "" if there is nothing to say.
static func pending_note(root: String) -> String:
	var note: Variant = JsonUtil.read_json(root.path_join(NOTE_FILE), {})
	if not note is Dictionary or bool(note.get("noted", true)):
		return ""
	return "Your world moved house! Everything was copied from %s to %s (%d files, checked one by one). The old folder was left untouched, so you can delete it whenever you like." % [
		str(note.get("from", "")), root, int(note.get("files", 0))]


static func mark_noted(root: String) -> void:
	var path := root.path_join(NOTE_FILE)
	var note: Variant = JsonUtil.read_json(path, {})
	if note is Dictionary:
		note["noted"] = true
		JsonUtil.write_json(path, note)
