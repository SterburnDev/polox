extends "res://tests/test_case.gd"
## The game is called Polox now: no user-facing "Pocket Dream World" is left,
## and an old Documents/PocketDarkWorld save is copied (never moved) over.

const Migration := preload("res://scripts/core/migration.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")

const OLD_NAMES := ["Pocket Dream World", "PocketDarkWorld", "pocket-dark-world", "POCKET DREAM WORLD"]


func test_no_user_facing_old_name_in_scripts() -> void:
	# Comments may explain the history; strings (what the player sees) may not.
	# migration.gd is the one place the old folder name is allowed to live.
	var offenders := PackedStringArray()
	for path in _scripts_in("res://scripts"):
		if path.ends_with("migration.gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			for old in OLD_NAMES:
				if code.findn(old) != -1:
					offenders.append("%s:%d" % [path, n])
	check(offenders.is_empty(), "old name still shown to the player in: " + ", ".join(offenders))


func test_project_and_window_are_named_polox() -> void:
	eq(ProjectSettings.get_setting("application/config/name"), "Polox")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	eq(main.get_window().title, "Polox")
	main.queue_free()
	await frames(1)
	eq(SaveManager.FOLDER_NAME, "Polox")


func test_old_save_is_copied_verified_and_left_in_place() -> void:
	var base := fresh_save_root()
	var old := base.path_join("PocketDarkWorld")
	var new_root := base.path_join("Polox")
	# An Update-1 folder: one world directly inside, as Pocket Dream World left it.
	var Defaults := preload("res://scripts/core/defaults.gd")
	var w := Defaults.world()
	w["name"] = "Old World"
	JsonUtil.write_json(old.path_join("world.json"), w)
	JsonUtil.write_json(old.path_join("rooms/home.json"), Defaults.room("home", "Home"))
	JsonUtil.write_json(old.path_join("rooms/garden.json"), Defaults.room("garden", "Garden"))
	var c := Defaults.character("mochi", "Mochi")
	c["expressions"] = preload("res://scripts/characters/sprite_factory.gd").write_blob_set(old.path_join("characters/mochi"), Color("#c9b6ff"))
	JsonUtil.write_json(old.path_join("characters/mochi/character.json"), c)
	JsonUtil.write_json(old.path_join("settings.json"), {"version": 1, "ai": {"preset": "mock"}})
	JsonUtil.ensure_dir(old.path_join("logs"))
	var f := FileAccess.open(old.path_join("logs/mochi.jsonl"), FileAccess.WRITE)
	f.store_line(JSON.stringify({"ts": "2026-10-05T23:18:00", "room": "home", "character": "mochi", "role": "user", "text": "hello from before the rename", "emotion": ""}))
	f.close()
	var old_world_hash := FileAccess.get_sha256(old.path_join("world.json"))
	check(Migration.needs_copy(new_root), "an old world with no new folder needs copying")
	var r := Migration.copy_and_verify(new_root)
	check(r.ok, "copy verified: " + str(r.get("error", "")))
	check(r.files >= 12, "copied the whole folder (%d files)" % r.files)
	check(DirAccess.dir_exists_absolute(new_root), "new folder exists")
	check(not DirAccess.dir_exists_absolute(new_root + ".migrating"), "staging folder gone")
	check(FileAccess.file_exists(old.path_join("world.json")), "old folder untouched")
	eq(FileAccess.get_sha256(old.path_join("world.json")), old_world_hash, "old files unchanged")
	eq(FileAccess.get_sha256(new_root.path_join("world.json")), old_world_hash, "copied world identical")
	check(not Migration.needs_copy(new_root), "never copies twice")
	SaveManager.set_root(new_root)  # also moves the copy into the slots/ layout
	eq(SaveManager.slot_id, "old_world", "the copied world is the active slot")
	eq(SaveManager.load_world().name, "Old World", "the copy opens")
	eq(ChatLog.read_all("mochi").size(), 1, "logs came along")
	check(FileAccess.file_exists(old.path_join("world.json")), "the old folder still has its own layout")
	var note := Migration.pending_note(new_root)
	check(note.find("copied") != -1 and note.find("PocketDarkWorld") != -1, "one-time note mentions the copy")
	Migration.mark_noted(new_root)
	eq(Migration.pending_note(new_root), "", "note shown once")


func test_verify_catches_a_bad_copy() -> void:
	var base := fresh_save_root()
	var a := base.path_join("a")
	var b := base.path_join("b")
	JsonUtil.write_json(a.path_join("world.json"), {"x": 1})
	JsonUtil.write_json(a.path_join("rooms/home.json"), {"id": "home"})
	JsonUtil.copy_tree(a, b)
	check(Migration.verify_copy(a, b).ok, "faithful copy passes")
	JsonUtil.write_json(b.path_join("rooms/home.json"), {"id": "changed"})
	var r := Migration.verify_copy(a, b)
	check(not r.ok and r.error.find("home.json") != -1, "a changed file is reported")
	DirAccess.remove_absolute(b.path_join("world.json"))
	check(not Migration.verify_copy(a, b).ok, "a missing file is reported")


func _scripts_in(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_scripts_in(dir.path_join(d)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
