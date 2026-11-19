extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd [-- --only=test_ai,test_core] [--dir=res://tests/e2e]
## Runs every tests/test_*.gd suite and exits non-zero if anything fails.
## tests/e2e/ holds the end-to-end Phone Link suites (they listen on this PC's
## real network addresses): only check_phone.bat runs them.

const TEST_DIR := "res://tests"

var _started := false


func _process(_delta: float) -> bool:
	# Autoloads are added to the tree before the first frame; start then.
	if not _started:
		_started = true
		_run_all()
	return false


func _run_all() -> void:
	await process_frame
	var only := PackedStringArray()
	var test_dir := TEST_DIR
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
		elif arg.begins_with("--dir="):
			test_dir = arg.trim_prefix("--dir=")
	# Tests must never touch the player's real save folder or the network.
	# (autoloads are fetched by path: this script compiles before they exist)
	root.get_node("AIClient").set("mock_delay_s", 0.0)
	var files: Array = []
	for f in DirAccess.get_files_at(test_dir):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			if only.is_empty() or f.get_basename() in only:
				files.append(f)
	files.sort()
	var total := 0
	var failures: PackedStringArray = []
	for f in files:
		var script: Script = load(test_dir.path_join(f))
		if script == null or not script.can_instantiate():
			failures.append("%s: could not load (parse error?)" % f)
			continue
		var suite: Object = script.new()
		suite.set("tree", self)
		var names: Array = []
		for m in script.get_script_method_list():
			if str(m.name).begins_with("test_") and not str(m.name) in names:
				names.append(str(m.name))
		for method in names:
			suite.set("current", "%s.%s" % [f.get_basename(), method])
			# Every test starts with the comfort and graphics settings at their defaults: a suite that
			# turned on Reduce motion (journeys skip their animation) must not change the next one's timing.
			var game_state: Node = root.get_node_or_null("GameState")   # (an autoload: not known when this compiles)
			if game_state:
				for k in ["reduce_motion", "frame_rate", "graphics"]:
					(game_state.get("settings") as Dictionary).erase(k)
			var before: int = suite.get("failures").size()
			await suite.call(method)
			total += 1
			var after: PackedStringArray = suite.get("failures")
			var status := "ok  " if after.size() == before else "FAIL"
			print("  %s %s.%s" % [status, f.get_basename(), method])
			if "--trace-orphans" in OS.get_cmdline_user_args():
				await process_frame
				await process_frame
				print("[orphans] after %s.%s" % [f.get_basename(), method])
				Node.print_orphan_nodes()
		failures.append_array(suite.get("failures"))
	# A node taken out of the tree and never freed stays in memory until the program ends (Godot then
	# warns "ObjectDB instances were leaked at exit"). No test and nothing it ran may leave one behind.
	await process_frame
	await process_frame
	var strays := Node.get_orphan_node_ids()
	if not strays.is_empty():
		failures.append("%d node(s) were left in no tree and never freed (listed above as Stray Node)" % strays.size())
		Node.print_orphan_nodes()
	print("")
	if failures.is_empty():
		print("ALL %d TESTS PASSED" % total)
	else:
		print("%d FAILURE(S) in %d tests:" % [failures.size(), total])
		for line in failures:
			print("  - " + line)
	quit(0 if failures.is_empty() else 1)
