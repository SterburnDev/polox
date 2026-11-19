extends "res://tests/test_case.gd"
## Isolated regression cases for home rollback and snapshot private overlays.

const Store := preload("res://scripts/home/home_store.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")


func _root() -> String:
	return fresh_save_root("restore_recovery_%d_%d_%s" % [OS.get_process_id(), Time.get_ticks_usec(), current])


func _archive(home: Dictionary, private: Variant = null) -> String:
	var file := SaveManager.root.path_join("restore_recovery_snapshot.zip")
	var zip := ZIPPacker.new()
	check(zip.open(file) == OK)
	check(zip.start_file("home.json") == OK)
	check(zip.write_file(JSON.stringify(home).to_utf8_buffer()) == OK)
	check(zip.close_file() == OK)
	if private != null:
		check(zip.start_file("private.json") == OK)
		check(zip.write_file(JSON.stringify(private).to_utf8_buffer()) == OK)
		check(zip.close_file() == OK)
	check(zip.close() == OK)
	return file


func _lock(file: String, sharing: String) -> Dictionary:
	var marker := SaveManager.root.path_join("restore_recovery_lock_%d" % Time.get_ticks_usec())
	var command := "$f=[System.IO.File]::Open('%s',[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::%s); try { [System.IO.File]::WriteAllText('%s','ready'); $end=[DateTime]::UtcNow.AddSeconds(30); while (-not [System.IO.File]::Exists('%s.release') -and [DateTime]::UtcNow -lt $end) { Start-Sleep -Milliseconds 20 } } finally { $f.Dispose(); [System.IO.File]::WriteAllText('%s.released','done') }" % [file.replace("'", "''"), sharing, marker, marker, marker]
	var pid := OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", command])
	var deadline := Time.get_ticks_msec() + 10000
	while pid > 0 and not FileAccess.file_exists(marker) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	check(pid > 0 and FileAccess.file_exists(marker), "recovery fixture lock acquired")
	return {"pid": pid, "marker": marker}


func _unlock(lock: Dictionary) -> void:
	check(JsonUtil.write_bytes(str(lock.marker) + ".release", "release".to_utf8_buffer()))
	var deadline := Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(str(lock.marker) + ".released") and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	check(FileAccess.file_exists(str(lock.marker) + ".released"), "fixture confirms file handle released")
	if not FileAccess.file_exists(str(lock.marker) + ".released") and int(lock.pid) > 0:
		OS.kill(int(lock.pid))


func test_backup_only_original_survives_failed_batch() -> void:
	_root()
	var room := "places/lw_backup.json"
	var original := '{ "id": "lw_backup", "name": "Original bytes" }\n'.to_utf8_buffer()
	check(JsonUtil.write_bytes(Store.path(room) + ".bak", original))
	JsonUtil.ensure_dir(Store.path("osm.json.tmp"))
	check(not Store.apply_batch({room: {"id": "lw_backup", "name": "Replacement"}, "osm.json": {"new": true}}))
	eq(FileAccess.get_file_as_bytes(Store.path(room)), original, "backup-only original restored byte for byte")
	check(not DirAccess.dir_exists_absolute(Store.path(Store.TRANSACTION)))


func test_temporary_original_precedes_backup_and_bad_temp_falls_back() -> void:
	for valid_temp in [true, false]:
		_root()
		var file := Store.path("private.json")
		check(JsonUtil.write_json(file + ".bak", {"address": "backup"}))
		check(JsonUtil.write_bytes(file + ".tmp", ('{"address":"temporary"}' if valid_temp else '{broken').to_utf8_buffer()))
		JsonUtil.ensure_dir(Store.path("osm.json.tmp"))
		check(not Store.apply_batch({"private.json": {"address": "replacement"}, "osm.json": {}}))
		eq(JsonUtil.parse_file(file), {"address": "temporary" if valid_temp else "backup"})


func test_unrecoverable_sibling_aborts_before_live_changes() -> void:
	_root()
	check(JsonUtil.write_json(Store.path("home.json"), {"tag": "live"}))
	check(JsonUtil.write_bytes(Store.path("private.json.bak"), '{broken'.to_utf8_buffer()))
	check(not Store.apply_batch({"home.json": {"tag": "replacement"}, "private.json": {}}))
	eq(JsonUtil.parse_file(Store.path("home.json")), {"tag": "live"})
	eq(FileAccess.get_file_as_string(Store.path("private.json.bak")), '{broken')


func test_checked_reads_distinguish_empty_from_missing() -> void:
	_root()
	var file := Store.path("empty.json")
	check(JsonUtil.write_bytes(file, PackedByteArray()))
	var empty := Store._read_bytes_checked(file)
	check(empty.ok, "zero bytes can be a successful read")
	eq(empty.get("bytes"), PackedByteArray())
	check(not Store._read_bytes_checked(file + ".missing").ok)
	check(not Store._read_bytes_checked(Store.dir()).ok)


func test_unreadable_later_original_prevents_all_rollback_mutation() -> void:
	_root()
	var tx := Store.path(Store.TRANSACTION)
	var originals := {"places/lw_new.json": false, "home.json": true, "private.json": true}
	check(JsonUtil.write_json(Store.path("places/lw_new.json"), {"id": "lw_new"}))
	check(JsonUtil.write_json(Store.path("home.json"), {"tag": "live"}))
	check(JsonUtil.write_json(Store.path("private.json"), {"address": "live"}))
	check(JsonUtil.write_json(tx.path_join("old/home.json"), {"tag": "old"}))
	var locked := tx.path_join("old/private.json")
	check(JsonUtil.write_json(locked, {"address": "old"}))
	check(JsonUtil.write_json(tx.path_join("journal.json"), {"version": 1, "state": "prepared", "original": originals}))
	var journal_before := FileAccess.get_file_as_bytes(tx.path_join("journal.json"))
	# Windows FileShare.None reproduces an existing file whose open-for-read fails.
	var lock := {}
	if OS.get_name() == "Windows":
		lock = await _lock(locked, "None")
	else:
		check(DirAccess.remove_absolute(locked) == OK)
	check(not Store.recover_transaction(), "unreadable last original blocks rollback")
	check(FileAccess.file_exists(Store.path("places/lw_new.json")), "earlier absent-original entry not deleted")
	eq(JsonUtil.parse_file(Store.path("home.json")), {"tag": "live"}, "earlier readable original not restored yet")
	eq(JsonUtil.parse_file(Store.path("private.json")), {"address": "live"})
	eq(FileAccess.get_file_as_bytes(tx.path_join("journal.json")), journal_before)
	check(FileAccess.file_exists(tx.path_join("old/home.json")), "recovery copies retained")
	if not lock.is_empty():
		await _unlock(lock)
	else:
		check(JsonUtil.write_json(locked, {"address": "old"}))
	check(Store.recover_transaction(), "retry succeeds once every original is readable")
	eq(JsonUtil.parse_file(Store.path("home.json")), {"tag": "old"})
	eq(JsonUtil.parse_file(Store.path("private.json")), {"address": "old"})
	check(not FileAccess.file_exists(Store.path("places/lw_new.json")))
	check(not DirAccess.dir_exists_absolute(tx))


func test_restore_without_private_removes_overlay_and_siblings() -> void:
	_root()
	var archive := _archive({"tag": "old", "timeline": []})
	check(JsonUtil.write_json(Store.path("private.json"), {"address": "new", "answers": {"rooms": 2}, "survey_timeline": [{"text": "new memory"}]}))
	check(JsonUtil.write_json(Store.path("private.json.bak"), {"address": "backup"}))
	check(JsonUtil.write_json(Store.path("private.json.tmp"), {"address": "temporary"}))
	check(Store.restore(archive))
	var home := Store.load_home()
	check(not home.has("address") and not home.has("answers"))
	eq(home.timeline, [])
	for suffix in ["", ".tmp", ".bak"]:
		check(not FileAccess.file_exists(Store.path("private.json") + suffix))


func test_legacy_inline_private_values_survive_restore_and_migration() -> void:
	_root()
	var memory := {"source": "you", "kind": "memory", "text": "old memory"}
	var archive := _archive({"address": "old address", "answers": {}, "timeline": [memory], "updated": "old date"})
	check(JsonUtil.write_json(Store.path("private.json"), {"address": "new address", "answers": {"new": true}, "survey_timeline": [{"text": "new memory"}]}))
	check(Store.restore(archive))
	var home := Store.load_home()
	eq(home.address, "old address")
	eq(home.answers, {})
	eq(home.timeline, [memory])
	check(Store.split_private())
	home = Store.load_home()
	eq(home.address, "old address")
	eq(home.answers, {})
	eq(home.timeline, [memory])
	check(not (JsonUtil.parse_file(Store.path("home.json")) as Dictionary).has("address"))


func test_archive_private_overlay_is_restored_when_present() -> void:
	_root()
	var archive := _archive({"timeline": []}, {"address": "archived", "answers": {}})
	check(JsonUtil.write_json(Store.path("private.json"), {"address": "new"}))
	check(Store.restore(archive))
	eq(Store.load_home().address, "archived")


func test_failed_private_removal_restores_home_and_private() -> void:
	_root()
	var archive := _archive({"tag": "archived"})
	check(JsonUtil.write_json(Store.path("home.json"), {"tag": "live"}))
	check(JsonUtil.write_json(Store.path("private.json.bak"), {"address": "recoverable"}))
	# Allow staging to read OSM, but deny deletion after private removal succeeds.
	check(JsonUtil.write_json(Store.path("osm.json"), {"tag": "live map"}))
	if OS.get_name() != "Windows":
		return
	var map_file := Store.path("osm.json")
	var lock: Dictionary = await _lock(map_file, "Read")
	check(not Store.restore(archive))
	await _unlock(lock)
	eq(JsonUtil.parse_file(Store.path("home.json")), {"tag": "live"})
	eq(JsonUtil.parse_file(Store.path("private.json")), {"address": "recoverable"})
	eq(JsonUtil.parse_file(map_file), {"tag": "live map"})
