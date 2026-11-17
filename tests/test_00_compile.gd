extends "res://tests/test_case.gd"
## Recompiles every script with the autoloads present. This complements the
## --check-only pass in check.bat, which can't resolve autoload names.


func test_every_script_compiles() -> void:
	var paths := _scripts_in("res://scripts") + _scripts_in("res://tests")
	check(paths.size() > 10, "found scripts to check")
	for p in paths:
		# Normal cached load: scripts already running (autoloads, the runner)
		# compiled fine; everything else compiles now, with autoloads present.
		# (Reloading a running script with CACHE_MODE_IGNORE crashes the VM.)
		var s: Script = load(p)
		check(s != null and s.can_instantiate(), "%s compiles" % p)


func test_tests_use_scratch_save_root() -> void:
	check(SaveManager.root.find("tests") != -1 and SaveManager.root.find(".tmp_save") != -1, "tests run against tests/.tmp_save, got " + SaveManager.root)


func _scripts_in(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_scripts_in(dir.path_join(d)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
