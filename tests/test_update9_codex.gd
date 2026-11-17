extends "res://tests/test_case.gd"
const Cli := preload("res://scripts/home/helper_codex.gd")
const Tell := preload("res://scripts/home/tell_polox.gd")


func _fixture(log_path: String) -> void:
	OS.set_environment("POLOX_CODEX_ARGV_FIXTURE", log_path)
	Cli.exe_override = OS.get_executable_path()
	Cli.prefix_override = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://tests/fixtures/fake_claude"), "--script", "res://fake_codex.gd", "--"])
	if OS.has_feature("windows"):
		# Godot's Windows console setup reopens stdin and loses cmd's redirected file.
		# Use a native reader that preserves the inherited handle, like the real CLI.
		Cli.exe_override = SaveManager.root.path_join("fake_codex.exe")
		var compiler := OS.get_environment("SystemRoot").path_join("Microsoft.NET/Framework64/v4.0.30319/csc.exe")
		var output: Array = []
		var code := OS.execute(compiler, preload("res://scripts/core/proc_args.gd").for_os(PackedStringArray([
			"/nologo", "/reference:System.Web.Extensions.dll", "/out:" + Cli.exe_override.replace("/", "\\"),
			ProjectSettings.globalize_path("res://tests/fixtures/fake_claude/fake_codex.cs").replace("/", "\\")])), output)
		check(code == 0, "native fixture compiles: " + str(output))
		Cli.prefix_override = PackedStringArray()


func _clear_fixture() -> void:
	Cli.exe_override = ""
	Cli.prefix_override = PackedStringArray()
	OS.unset_environment("POLOX_CODEX_ARGV_FIXTURE")


## Regression (Update 9 review): `codex exec` reads piped stdin until it ends, and Godot's pipe never
## ends, so every real request waited until its timeout. The prompt now comes from a file on stdin.
func test_codex_windows_arguments_and_data_only_workspace_roundtrip() -> void:
	fresh_save_root()
	var log_path := SaveManager.root.path_join("codex_argv.json")
	_fixture(log_path)
	var cli := Cli.new()
	tree.root.add_child(cli)
	var prompt := 'A "quoted" room, C:\\Example\\ and & punctuation, 100% sure, café.'
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = await cli.run(prompt, Tell.WORDS_SCHEMA, "fixture-model")
	check(result.ok, "CLI structured output is read: " + str(result.get("error", "")))
	check(Time.get_ticks_msec() - t0 < 60000, "it finishes (stdin ends) instead of waiting for its timeout")
	eq(int(result.get("searched", -1)), 0, "reading words never searches")
	var logged: Variant = JSON.parse_string(FileAccess.get_file_as_string(log_path))
	check(logged is Dictionary, "native argument log exists")
	if logged is Dictionary:
		var args: Array = logged.args
		eq(str(args[-1]), "-", "the prompt comes from stdin")
		check(str(logged.stdin).ends_with(prompt), "quotes, slashes, %, & and accents arrive intact on stdin")
		check(not JSON.stringify(args).contains("quoted"), "and never on the command line")
		eq(args[args.find("--sandbox") + 1], "read-only", "minimum write permissions")
		var workspace := str(args[args.find("--cd") + 1])
		check(workspace.begins_with(Cli.jobs_dir()), "a temporary workspace of its own")
		check(not workspace.begins_with(SaveManager.home_dir()) and not workspace.begins_with(ProjectSettings.globalize_path("res://")), "outside my_home and outside the game's repository")
		check("web_search=disabled" in args, "no web search when only reading words")
		check("--ephemeral" in args and "--ignore-user-config" in args and "--ignore-rules" in args, "no inherited user jobs or session persistence")
		check("shell_tool" in args and "plugins" in args, "command and plugin tools disabled")
		check(not FileAccess.file_exists(str(args[args.find("--output-last-message") + 1])), "temporary response removed")
		check(not DirAccess.dir_exists_absolute(workspace), "workspace (with the prompt file) removed")
	_clear_fixture()
	cli.queue_free()
	await frames(2)


## Research turns on live search, and the adapter counts the searches Codex reports, so an answer made
## without one is never shown as researched. A photo is copied into the job folder, nothing else.
func test_codex_research_uses_live_search_and_counts_it() -> void:
	fresh_save_root()
	var log_path := SaveManager.root.path_join("codex_argv.json")
	_fixture(log_path)
	var photo := SaveManager.root.path_join("photo.png")
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.save_png(photo)
	var cli := Cli.new()
	tree.root.add_child(cli)
	var result: Dictionary = await cli.run("Public landmark research fixture.", Tell.WORDS_SCHEMA, "", true, PackedStringArray([photo]))
	check(result.ok)
	eq(int(result.get("searched", 0)), 1, "the reported web search is counted")
	var logged: Variant = JSON.parse_string(FileAccess.get_file_as_string(log_path))
	if check(logged is Dictionary):
		var args: Array = logged.args
		check("web_search=live" in args, "live search on for research")
		var image := str(args[args.find("--image") + 1])
		check(image.begins_with(Cli.jobs_dir()) and image != photo, "the photo travels as a copy inside the job folder")
		check(not FileAccess.file_exists(image), "the copy is removed afterwards")
	check(FileAccess.file_exists(photo), "the player's own photo stays")
	_clear_fixture()
	cli.queue_free()
	await frames(2)


func test_unsafe_model_names_and_launcher_paths_are_refused() -> void:
	fresh_save_root()
	_fixture(SaveManager.root.path_join("unused.json"))
	var cli := Cli.new()
	tree.root.add_child(cli)
	var result: Dictionary = await cli.run("x", Tell.WORDS_SCHEMA, "gpt & del")
	eq(str(result.why), "configuration", "a model name can't smuggle a command")
	if OS.has_feature("windows"):
		check(Cli.launcher("C:/a%PATH%/codex.exe", PackedStringArray(["exec"]), "C:/p.txt").is_empty(), "no % expansion on the cmd line")
		var ok := Cli.launcher("C:/Program Files/codex.exe", PackedStringArray(["exec", "--cd", "C:/a b"]), "C:/x y/p.txt")
		check(str(ok.args[-1]).contains("< \"C:/x y/p.txt\""), "stdin from the prompt file")
	_clear_fixture()
	cli.queue_free()
	await frames(2)
