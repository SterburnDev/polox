extends "res://tests/test_case.gd"

const Archive := preload("res://scripts/core/slot_archive.gd")
const Slots := preload("res://scripts/core/slots.gd")
const Json := preload("res://scripts/core/json_util.gd")
const Defaults := preload("res://scripts/core/defaults.gd")


func _slot() -> String:
	fresh_save_root()
	var id := SaveManager.new_slot("Archive validation")
	Json.write_json(Slots.dir(id).path_join("world.json"), Defaults.world())
	Json.write_json(Slots.dir(id).path_join("rooms/home.json"), Defaults.room())
	Json.write_json(Slots.dir(id).path_join("world.json.bak"), {"keep": "recovery sibling"})
	Json.write_json(Slots.dir(id).path_join("conflicts/keep.json"), {"keep": "conflict"})
	return id


func _zip(entries: Dictionary) -> String:
	var path := SaveManager.root.path_join("candidate.zip")
	var zip := ZIPPacker.new()
	eq(zip.open(path), OK)
	for name in entries:
		eq(zip.start_file(name), OK)
		eq(zip.write_file(str(entries[name]).to_utf8_buffer()), OK)
		eq(zip.close_file(), OK)
	eq(zip.close(), OK)
	return path


func _hashes(folder: String, prefix: String = "") -> Dictionary:
	var out := {}
	for file in DirAccess.get_files_at(folder):
		out[prefix + file] = FileAccess.get_sha256(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		out.merge(_hashes(folder.path_join(sub), prefix + sub + "/"))
	return out


func test_invalid_world_archives_leave_every_live_byte_unchanged() -> void:
	var id := _slot()
	var before := _hashes(Slots.dir(id))
	var cases: Array = [{"note.txt": "not a world"}]
	for body in ["{ broken", "null", "[]", "42", "\"world\"", "{\"player\": []}", "{\"start_room\": \"../outside\"}"]:
		cases.append({"world.json": body, "rooms/home.json": JSON.stringify(Defaults.room())})
	for entries in cases:
		var result := Archive.restore_backup(id, _zip(entries))
		check(not result.ok, "reject invalid archive: " + str(entries))
		check(str(result.error) != "", "actionable failure")
		eq(_hashes(Slots.dir(id)), before, "no files, metadata, backups or recovery siblings changed")


func test_missing_or_malformed_rooms_cannot_replace_the_live_world() -> void:
	var id := _slot()
	var before := _hashes(Slots.dir(id))
	for room in ["", "{ broken", "[]", "null"]:
		var entries := {"world.json": JSON.stringify(Defaults.world())}
		if room != "":
			entries["rooms/home.json"] = room
		check(not Archive.restore_backup(id, _zip(entries)).ok)
		eq(_hashes(Slots.dir(id)), before)


func test_legacy_world_without_name_or_start_room_restores() -> void:
	var id := _slot()
	var meta := FileAccess.get_file_as_bytes(Slots.dir(id).path_join(Slots.META))
	var entries := {"world.json": "{\"version\": 1, \"player\": {}}", "rooms/old_garden.json": "{\"id\": \"old_garden\"}"}
	var result := Archive.restore_backup(id, _zip(entries))
	check(result.ok, str(result.error))
	var restored: Dictionary = Json.parse_file(Slots.dir(id).path_join("world.json"))
	eq(restored.version, 1)
	eq(restored.player, {})
	check(not restored.has("name") and not restored.has("start_room"), "legacy contents preserved without filling fields")
	check(FileAccess.file_exists(Slots.dir(id).path_join("rooms/old_garden.json")))
	check(not FileAccess.file_exists(Slots.dir(id).path_join("rooms/home.json")))
	eq(FileAccess.get_file_as_bytes(Slots.dir(id).path_join(Slots.META)), meta, "missing archive metadata keeps live card")
	check(FileAccess.file_exists(Slots.dir(id).path_join("conflicts/keep.json")))
	check(Archive.backups(id).any(func(b): return b.kind == "before_restore"))
	eq(DirAccess.get_directories_at(Archive.backups_dir(id)).size(), 0, "successful staging cleaned")


func test_valid_snapshot_restores_a_corrupt_live_world_and_keeps_snapshot() -> void:
	var id := _slot()
	var backup := Archive.snapshot(id)
	var world_path := Slots.dir(id).path_join("world.json")
	var expected := FileAccess.get_sha256(world_path)
	var file := FileAccess.open(world_path, FileAccess.WRITE)
	file.store_string("{ corrupt live world")
	file.close()
	var result := Archive.restore_backup(id, backup)
	check(result.ok, str(result.error))
	eq(FileAccess.get_sha256(world_path), expected)
	check(FileAccess.file_exists(backup), "source snapshot retained")
	var safety := Archive.backups(id).filter(func(b): return b.kind == "before_restore")
	check(safety.size() == 1)
	if not safety.is_empty():
		eq(Archive.read_zip_file(safety[0].path, "world.json").get_string_from_utf8(), "{ corrupt live world")


func test_extraction_failure_does_not_touch_live_files() -> void:
	var id := _slot()
	var before := _hashes(Slots.dir(id))
	var path := _zip({"world.json": JSON.stringify(Defaults.world()), "rooms": "blocks directory creation", "rooms/home.json": "{}"})
	check(not Archive.restore_backup(id, path).ok)
	eq(_hashes(Slots.dir(id)), before)


func test_reserved_recovery_paths_and_ambiguous_paths_are_rejected() -> void:
	var id := _slot()
	var before := _hashes(Slots.dir(id))
	for name in ["backups/overwrite.zip", "Conflicts/keep.json", "rooms/../escape.json", "rooms\\home.json", "world.json."]:
		var path := _zip({"world.json": "{}", "rooms/home.json": "{}", name: "overwrite"})
		check(not Archive.restore_backup(id, path).ok, "reject " + name)
		eq(_hashes(Slots.dir(id)), before)


func test_failed_install_rolls_back_originals_and_records_recovery_locations() -> void:
	var id := _slot()
	var live := Slots.dir(id)
	# Directly exercise the installation failure branch: the staged backups entry
	# collides with the preserved, nonempty live backups directory, after assets moved.
	var work := Archive.backups_dir(id).path_join("failure_fixture")
	var staged := work.path_join("staged")
	Json.write_json(staged.path_join("assets/new.json"), {"new": true})
	Json.write_json(staged.path_join("backups/block.json"), {})
	var before := _hashes(live)
	var result := Archive._install_restore(live, staged, work.path_join("original"))
	check(not result.ok, "forced installation failure")
	eq(result.recovery, work)
	check(str(result.error).contains(work), "UI error includes explicit recovery path")
	var recovery: Variant = Json.parse_file(work.path_join("recovery.json"))
	check(recovery is Dictionary, "durable record survives failure")
	if recovery is Dictionary:
		eq(recovery.live, live)
		eq(recovery.original, work.path_join("original"))
		eq(recovery.staged, staged)
	var after := _hashes(live)
	after.erase("backups/failure_fixture/recovery.json")
	eq(after, before, "partial install undone, all originals and recovery siblings preserved")
	check(not DirAccess.dir_exists_absolute(live.path_join("assets")))
