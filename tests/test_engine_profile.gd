extends "res://tests/test_case.gd"
## Polox's own engine (tools/build_engine.py) leaves out the parts of Godot the game doesn't use
## (native/godot/polox_profile.py). A script naming a missing class wouldn't even load on the phone, the web or
## the Windows build, so these checks keep the game from coming to depend on one of them.

const REMOVED := "res://native/godot/removed_classes.txt"
const GAME_DIRS := ["res://scripts", "res://scenes", "res://assets", "res://shaders", "res://audio", "res://addons"]
const EXTS := ["gd", "tscn", "tres", "gdshader", "gdshaderinc", "import", "cfg"]


func test_the_game_names_no_class_the_engine_leaves_out() -> void:
	var names := PackedStringArray()
	for line in FileAccess.get_file_as_string(REMOVED).split("\n"):
		if line != "" and not line.begins_with("#"):
			names.append(line)
	check(names.size() > 100, "the list of left-out classes is there (%d)" % names.size())
	var rx := RegEx.new()
	eq(rx.compile("\\b(" + "|".join(names) + ")\\b"), OK)
	var found := []
	for path in _game_files():
		for m in rx.search_all(FileAccess.get_file_as_string(path)):
			found.append("%s: %s" % [path, m.get_string(1)])
	eq(found, [], "no game file names a class Polox's engine leaves out")


func test_the_settings_need_nothing_the_engine_leaves_out() -> void:
	var physics := str(ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))
	check(physics in ["DEFAULT", "GodotPhysics3D"], "3D physics is Godot Physics (Jolt is left out): " + physics)
	check(not bool(ProjectSettings.get_setting("gui/theme/default_font_multichannel_signed_distance_field", false)), "no MSDF default font (msdfgen is left out)")
	check(not bool(ProjectSettings.get_setting("xr/openxr/enabled", false)), "no OpenXR")
	var msdf := []
	for path in _game_files():
		if path.ends_with(".import") and FileAccess.get_file_as_string(path).contains("multichannel_signed_distance_field=true"):
			msdf.append(path)
	eq(msdf, [], "no font imported as MSDF")


func _game_files(dir: String = "", out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var dirs: Array = GAME_DIRS if dir == "" else [dir]
	for d in dirs:
		if not DirAccess.dir_exists_absolute(d):
			continue
		for sub in DirAccess.get_directories_at(d):
			if not sub.begins_with("."):
				_game_files(d.path_join(sub), out)
		for f in DirAccess.get_files_at(d):
			if f.get_extension() in EXTS:
				out.append(d.path_join(f))
	if dir == "":
		out.append("res://project.godot")
	return out
