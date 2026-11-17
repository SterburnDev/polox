extends "res://tests/test_case.gd"

const Archive := preload("res://scripts/core/slot_archive.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")


func test_missing_source_does_not_replace_an_existing_archive() -> void:
	var root := fresh_save_root()
	var source := root.path_join("source")
	JsonUtil.write_json(source.path_join("world.json"), {"name": "Keep me"})
	var target := root.path_join("saved.zip")
	check(Archive.zip_folder(source, target), "initial archive succeeds")
	var original := FileAccess.get_sha256(target)
	check(not Archive.zip_folder(root.path_join("missing"), target), "missing source fails")
	eq(FileAccess.get_sha256(target), original, "existing archive survives the failed replacement")
	check(not FileAccess.file_exists(target + ".part"), "no partial archive remains")


func test_archive_inside_source_excludes_its_own_output() -> void:
	var root := fresh_save_root()
	JsonUtil.write_json(root.path_join("world.json"), {"name": "Round trip"})
	var target := root.path_join("saved.zip")
	for attempt in 2:
		check(Archive.zip_folder(root, target), "archive and replacement succeed")
		var reader := ZIPReader.new()
		eq(reader.open(target), OK, "completed archive opens")
		eq(reader.get_files(), PackedStringArray(["world.json"]), "archive contains only source data")
		reader.close()
