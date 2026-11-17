extends "res://tests/test_case.gd"
## [PERSONAL_DATA] [MIGRATION] Where personal data lives and how older folders are brought over: once,
## verified, never deleting the old folders, never replacing anything newer, and safe to run again.
## Tags: [PERSONAL_DATA] [MIGRATION]

const PersonalData := preload("res://scripts/core/personal_data.gd")
const PDM := preload("res://scripts/core/personal_data_migration.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")


func _write(path: String, data: Variant) -> void:
	JsonUtil.ensure_dir(path.get_base_dir())
	JsonUtil.write_json(path, data)


func _base() -> String:
	var b := ProjectSettings.globalize_path("res://tests/.tmp_save/personal_data")
	JsonUtil.remove_tree(b)
	JsonUtil.ensure_dir(b)
	return b


func test_the_folder_is_beside_polox() -> void:
	var dir := PersonalData.install_dir()
	if OS.has_feature("template"):
		eq(dir, OS.get_executable_path().get_base_dir(), "an exported game: beside Polox.exe")
	else:
		eq(dir, ProjectSettings.globalize_path("res://").trim_suffix("/"), "from source: the project folder")
	eq(PersonalData.folder(), dir.path_join("PersonalData"), "the PersonalData folder there")
	eq(PersonalData.fallback_reason, "", "and it can be written")
	var b := _base()
	JsonUtil.write_json(b.path_join("a_file"), {})
	check(not PersonalData.writable(b.path_join("a_file").path_join("inside")), "a folder that can't be made isn't writable")
	check(PersonalData.writable(b.path_join("ok")), "a normal folder is")
	var ignored := FileAccess.get_file_as_string("res://.gitignore")
	check(ignored.contains("/PersonalData/"), "Git ignores it")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.count("PersonalData/*") >= 3, "every export leaves it out")


func test_old_folders_come_over_once_and_nothing_newer_is_replaced() -> void:
	var b := _base()
	var old_main := b.path_join("old_main")     # (the POLOX_SAVE_ROOT folder)
	var old_docs := b.path_join("old_docs")     # (Documents/Polox)
	var target := b.path_join("PersonalData")
	_write(old_main.path_join("settings.json"), {"active_slot": "home", "ai": {"keys": {"anthropic": "test-key-not-real"}}})
	_write(old_main.path_join("slots/home/world.json"), {"name": "Home from main"})
	_write(old_docs.path_join("settings.json"), {"active_slot": "other"})
	_write(old_docs.path_join("slots/home/world.json"), {"name": "Home from docs (must not mix in)"})
	_write(old_docs.path_join("slots/other/world.json"), {"name": "Other world"})
	_write(old_docs.path_join("library/song.json"), {"t": 1})
	JsonUtil.ensure_dir(target)   # (the write test made it, empty)
	var r := PDM.run(target, PackedStringArray([old_main, old_docs]))
	check(r.ok and r.ran, "it ran: " + str(r))
	eq(JsonUtil.read_json(target.path_join("settings.json"), {}).get("active_slot"), "home", "settings and keys from the main old folder")
	eq(JsonUtil.read_json(target.path_join("slots/home/world.json"), {}).get("name"), "Home from main", "its world, not mixed with the other copy")
	eq(JsonUtil.read_json(target.path_join("slots/other/world.json"), {}).get("name"), "Other world", "a world only the other folder had comes too")
	check(FileAccess.file_exists(target.path_join("library/song.json")), "and its library")
	check(FileAccess.file_exists(old_main.path_join("settings.json")) and FileAccess.file_exists(old_docs.path_join("slots/other/world.json")), "the old folders are untouched")
	check(PDM.pending_note(target).contains("PersonalData"), "the title screen will say so once")
	# Play on: the new folder gets newer data.
	_write(target.path_join("settings.json"), {"active_slot": "other", "newer": true})
	_write(old_main.path_join("slots/home/world.json"), {"name": "An old copy edited later"})
	var again := PDM.run(target, PackedStringArray([old_main, old_docs]))
	check(not again.ran, "it doesn't run twice")
	var forced := PDM.run(target, PackedStringArray([old_main, old_docs]), true)
	check(forced.ok and forced.ran, "forced, it can run again safely")
	check(bool(JsonUtil.read_json(target.path_join("settings.json"), {}).get("newer", false)), "newer settings are kept")
	eq(JsonUtil.read_json(target.path_join("slots/home/world.json"), {}).get("name"), "Home from main", "nothing that exists is replaced")
	PDM.mark_noted(target)
	eq(PDM.pending_note(target), "", "noted once")


func test_everything_still_loads_after_a_restart() -> void:
	var b := _base()
	var old := b.path_join("old")
	var target := b.path_join("PersonalData")
	# A real old save: made by Polox itself in the old folder.
	SaveManager.set_root(old)
	SaveManager.new_slot("Restart test")
	preload("res://scripts/core/starter_content.gd").create_world()
	GameState.settings["ai"] = {"preset": "mock"}
	GameState.save_settings()
	var slot := SaveManager.slot_id
	var characters := Array(SaveManager.list_characters())
	PDM.run(target, PackedStringArray([old]))
	# "Restart": open the new folder from scratch.
	SaveManager.set_root(target)
	GameState.reload_settings()
	eq(SaveManager.slot_id, slot, "the same world is active")
	eq(Array(SaveManager.list_characters()), characters, "with its friends")
	check(GameState.has_world(), "and it loads")
	fresh_save_root()


func test_an_installed_copy_keeps_its_data_outside_the_program_folder() -> void:
	# [PERSONAL_DATA] The Windows setup writes polox-install.json beside Polox.exe. With it, PersonalData
	# lives in %LOCALAPPDATA%/Polox, so upgrades and an uninstall never touch it. Without it: portable.
	var b := _base()
	var portable := b.path_join("portable_copy")
	var installed := b.path_join("Program Files/Polox")   # (a path with a space, like the real one)
	JsonUtil.ensure_dir(portable)
	JsonUtil.ensure_dir(installed)
	check(not PersonalData.is_installed(portable), "no marker: a portable copy")
	eq(PersonalData.install_marker(portable), {}, "and nothing to read")
	_write(installed.path_join(PersonalData.INSTALL_MARKER), {"layout": "installed", "import_from": []})
	check(PersonalData.is_installed(installed), "the setup's marker: an installed copy")
	var f := FileAccess.open(portable.path_join(PersonalData.INSTALL_MARKER), FileAccess.WRITE)
	f.store_string("not json at all")
	f.close()
	check(not PersonalData.is_installed(portable), "a damaged marker is ignored (portable again), never an error")
	_write(portable.path_join(PersonalData.INSTALL_MARKER), {"layout": "something-new"})
	check(not PersonalData.is_installed(portable), "an unknown layout too")
	var data := PersonalData.installed_data_folder()
	check(data.ends_with("/Polox/PersonalData"), "the data folder is <local app data>/Polox/PersonalData: " + data)
	check(not data.contains("\\"), "written with forward slashes like every other path")
	if OS.get_environment("LOCALAPPDATA") != "":
		check(data.to_lower().begins_with(OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower()), "under %LOCALAPPDATA%")
	check(not PersonalData.is_installed(), "this run (from source or the test runner) is never 'installed'")


func test_the_setup_can_ask_for_a_portable_copys_worlds() -> void:
	# [MIGRATION] "import_from" in the marker names PersonalData folders to bring over. The first start
	# takes the first one whole; a folder named later (an upgrade) only adds worlds that aren't there.
	var b := _base()
	var app := b.path_join("app")
	var old_copy := b.path_join("Old Polox/PersonalData")
	var second_copy := b.path_join("usb/PersonalData")
	var target := b.path_join("LocalAppData/Polox/PersonalData")
	_write(old_copy.path_join("settings.json"), {"active_slot": "home"})
	_write(old_copy.path_join("slots/home/world.json"), {"name": "Home (portable)"})
	_write(old_copy.path_join("addons/my-addon/addon.json"), {"id": "my-addon"})
	_write(second_copy.path_join("settings.json"), {"active_slot": "beach"})
	_write(second_copy.path_join("slots/home/world.json"), {"name": "Home (usb, must not replace)"})
	_write(second_copy.path_join("slots/beach/world.json"), {"name": "Beach"})
	_write(app.path_join(PersonalData.INSTALL_MARKER), {"layout": "installed", "import_from": [old_copy.replace("/", "\\"), b.path_join("not there"), old_copy]})
	eq(Array(PersonalData.requested_imports(app)), [old_copy], "the folders that exist, once each, with forward slashes")
	JsonUtil.ensure_dir(target)
	var first := PDM.run(target, PersonalData.requested_imports(app))
	check(first.ok and first.ran and first.primary == old_copy, "the first start brings the portable copy over whole: " + str(first))
	eq(JsonUtil.read_json(target.path_join("slots/home/world.json"), {}).get("name"), "Home (portable)", "its world")
	check(FileAccess.file_exists(target.path_join("addons/my-addon/addon.json")), "and its add-ons")
	check(FileAccess.file_exists(old_copy.path_join("slots/home/world.json")), "the portable copy is left as it was")
	eq(Array(PDM.new_sources(target, PersonalData.requested_imports(app))), [], "the same request isn't new the second time")
	check(not PDM.import_requested(target, PersonalData.requested_imports(app)).ran, "so nothing runs again")
	# An upgrade names another copy.
	_write(app.path_join(PersonalData.INSTALL_MARKER), {"layout": "installed", "import_from": [old_copy, second_copy]})
	eq(Array(PDM.new_sources(target, PersonalData.requested_imports(app))), [second_copy], "only the new folder")
	var later := PDM.import_requested(target, PersonalData.requested_imports(app))
	check(later.ok and later.ran, "it is brought over: " + str(later))
	eq(Array(later.added), ["slots/beach"], "adding only the world that wasn't there")
	eq(JsonUtil.read_json(target.path_join("slots/home/world.json"), {}).get("name"), "Home (portable)", "the existing world is not replaced or mixed")
	eq(JsonUtil.read_json(target.path_join("settings.json"), {}).get("active_slot"), "home", "and the settings stay")
	check(not PDM.import_requested(target, PersonalData.requested_imports(app)).ran, "and that request is remembered too")
	check(not PDM.import_requested(b.path_join("never_migrated"), PersonalData.requested_imports(app)).ran, "a folder that never migrated waits for the first start instead")
