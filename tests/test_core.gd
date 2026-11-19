extends "res://tests/test_case.gd"
## Save folder, JSON helpers, chat log basics.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Defaults := preload("res://scripts/core/defaults.gd")


func test_slugify() -> void:
	eq(JsonUtil.slugify("Mabel the Moth!"), "mabel_the_moth")
	eq(JsonUtil.slugify("  ***  "), "thing")
	eq(JsonUtil.slugify("Café 2"), "caf_2")


func test_merge_defaults_fills_missing_keys() -> void:
	var merged := JsonUtil.merge_defaults({"a": 1, "nested": {"x": 5}}, {"a": 0, "b": 2, "nested": {"x": 0, "y": 3}})
	eq(merged.a, 1, "keeps existing")
	eq(merged.b, 2, "adds missing")
	eq(merged.nested.x, 5, "keeps nested")
	eq(merged.nested.y, 3, "adds nested")


func test_json_roundtrip_and_broken_file() -> void:
	var root := fresh_save_root()
	var p := root.path_join("thing.json")
	check(JsonUtil.write_json(p, {"version": 1, "hello": "world"}), "write ok")
	eq(JsonUtil.read_json(p, {}).get("hello"), "world")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	eq(JsonUtil.read_json(p, {"fallback": true}).get("fallback"), true, "broken file gives fallback")


func test_save_manager_layout_and_kinds() -> void:
	var root := fresh_save_root()
	SaveManager.ensure_slot("T")
	for sub in ["rooms", "characters", "logs", "textures", "backups"]:
		check(DirAccess.dir_exists_absolute(SaveManager.slot_dir().path_join(sub)), "folder %s exists" % sub)
	var room := Defaults.room("cafe", "Cafe")
	SaveManager.save_room(room)
	check("cafe" in SaveManager.list_rooms(), "room listed")
	eq(SaveManager.load_room("cafe").get("name"), "Cafe")
	var c := Defaults.character("mabel", "Mabel")
	SaveManager.save_character(c)
	check("mabel" in SaveManager.list_characters(), "character listed")
	# Missing fields come back from defaults (simple migration).
	JsonUtil.write_json(SaveManager.character_dir("old").path_join("character.json"), {"version": 1, "name": "Old"})
	var old := SaveManager.load_character("old")
	eq(old.get("id"), "old")
	check(old.has("mood") and old.mood.has("energy"), "old character gains mood")


func test_unique_id() -> void:
	eq(SaveManager.unique_id("Home", PackedStringArray(["home", "home_2"])), "home_3")


func test_chat_log_append_query_export() -> void:
	fresh_save_root()
	ChatLog.append("mabel", "home", "user", "hello there", "")
	ChatLog.append("mabel", "home", "ai", "hi!", "happy")
	ChatLog.append("mabel", "garden", "ai", "flowers", "happy", {"kind": "npc_chat", "with": "bo"})
	eq(ChatLog.read_all("mabel").size(), 3)
	eq(ChatLog.recent("mabel", 10).size(), 2, "recent skips npc chatter")
	eq(ChatLog.query({"room": "garden"}).size(), 1)
	eq(ChatLog.query({"search": "HELLO"}).size(), 1, "search is case-insensitive")
	var today := Time.get_date_string_from_system()
	eq(ChatLog.query({"date_from": today, "date_to": today}).size(), 3)
	eq(ChatLog.query({"date_to": "2000-01-01"}).size(), 0)
	var files := ChatLog.export({})
	eq(files.size(), 2)
	check(FileAccess.get_file_as_string(files[0]).find("hello there") != -1, "txt export has text")


func test_chat_log_redacts_secret() -> void:
	fresh_save_root()
	ChatLog.set_secret("FAKE-supersecret-123")
	ChatLog.append("bo", "home", "user", "my key is FAKE-supersecret-123 lol")
	ChatLog.set_secret("")
	var text := FileAccess.get_file_as_string(ChatLog.log_path("bo"))
	check(text.find("supersecret") == -1, "key never reaches the log")
	check(text.find("[redacted]") != -1, "redaction marker present")


func test_partial_log_line_is_skipped() -> void:
	fresh_save_root()
	ChatLog.append("bo", "home", "user", "first")
	var f := FileAccess.open(ChatLog.log_path("bo"), FileAccess.READ_WRITE)
	f.seek_end()
	f.store_string("{\"ts\": \"2026-")  # simulated crash mid-write
	f.close()
	ChatLog.append("bo", "home", "user", "second")
	eq(ChatLog.read_all("bo").size(), 2, "broken line ignored, later lines kept")


func test_backup_zip_blanks_api_key() -> void:
	var root := fresh_save_root()
	var s := SaveManager.load_settings()
	s.ai.api_key = "FAKE-should-not-leak"
	SaveManager.save_settings(s)
	SaveManager.save_world(Defaults.world())
	var zip_path := SaveManager.backup()
	check(FileAccess.file_exists(zip_path), "zip created")
	var reader := ZIPReader.new()
	eq(reader.open(zip_path), OK)
	var files := reader.get_files()
	check("world.json" in files, "world.json in zip")
	check(not "settings.json" in files, "settings (and the key) are never inside a world backup")
	for f in files:
		check(reader.read_file(f).get_string_from_utf8().find("FAKE-should-not-leak") == -1, "no key in " + f)
	reader.close()
	check(root != "", "root set")
