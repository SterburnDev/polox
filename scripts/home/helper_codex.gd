extends Node
## Supported noninteractive CLI (`codex exec`), isolated from the game checkout and from my_home: each
## job gets an empty temporary folder of its own (Godot's user data, never the home or a repository),
## a read-only sandbox, no shell/exec/plugin tools, no user config or rules, no saved session. It uses
## the player's own Codex sign-in (a ChatGPT plan or an API key, as Codex itself is set up).
## Research turns on Codex's live web search (`-c web_search="live"`; checked against codex-cli
## 0.163.0 on 2026-10-23: a real search ran and its answer matched the schema). The JSON event stream
## says whether it actually searched, so an ungrounded answer is never presented as researched.
## Tags: [AI_HELPER]
const Job := preload("res://scripts/core/background_job.gd")
const Args := preload("res://scripts/core/proc_args.gd")
const Json := preload("res://scripts/home/helper_json.gd")
const Http := preload("res://scripts/home/helper_http.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const MAX_PROMPT := 200000  # (through a file now, not the command line; still bounded)
const EXIT_WAIT_MS := 3000  # how long leaving the tree waits for a stopped Codex to be gone
var control := {"cancelled": false}
var _job: Dictionary = {}                       # the program running now ({} before the first)
var _workspace_dir := ""                        # this run's folder and the files written into it
var _workspace_files := PackedStringArray()
static var exe_override := ""
static var prefix_override := PackedStringArray()


static func executable() -> String:
	if exe_override != "":
		return exe_override
	if OS.has_feature("android") or OS.has_feature("web"):
		return ""
	var filename := "codex.exe" if OS.has_feature("windows") else "codex"
	for folder in OS.get_environment("PATH").split(";" if OS.has_feature("windows") else ":", false):
		var path := folder.path_join(filename)
		if FileAccess.file_exists(path):
			return path
	if OS.has_feature("windows"):
		var root := OS.get_environment("LOCALAPPDATA").path_join("OpenAI/Codex/bin")
		# (Asked first: listing a folder that isn't there prints an engine error, which a PC without
		# Codex showed three times at every start. Seen on a clean Windows 11.)
		var versions := DirAccess.get_directories_at(root) if DirAccess.dir_exists_absolute(root) else PackedStringArray()
		versions.sort()
		versions.reverse()
		for version in versions:
			var path := root.path_join(version).path_join(filename)
			if FileAccess.file_exists(path):
				return path
	return ""


## Where jobs run: outside my_home (where the private files are) and outside any repository.
static func jobs_dir() -> String:
	return OS.get_user_data_dir().path_join("helper_jobs")


## `codex exec` arguments; the prompt itself is "-" (read from stdin, see launcher()).
static func arguments(folder: String, schema_path: String, output_path: String, prompt: String = "-", model: String = "", web: bool = false, images: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var args := prefix_override.duplicate()
	args.append_array(PackedStringArray(["exec", "--sandbox", "read-only", "--cd", folder, "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--ignore-rules", "--disable", "shell_tool", "--disable", "unified_exec", "--disable", "plugins", "--enable", "skip_host_skill_discovery", "--output-schema", schema_path, "--output-last-message", output_path, "--color", "never", "--json"]))
	# Without the user's config, web search is whatever this says: on only for research. (No quotes:
	# Codex takes a value that isn't TOML as the plain word, and the line goes through cmd.exe.)
	args.append_array(PackedStringArray(["-c", "web_search=live" if web else "web_search=disabled"]))
	for image in images:
		args.append_array(PackedStringArray(["--image", image]))
	if model != "":
		args.append_array(PackedStringArray(["--model", model]))
	args.append(prompt)
	return args


## How to start Codex so its stdin is the prompt file. `codex exec` reads piped stdin until it ends, and
## the pipe Godot gives a child never ends: through OS.execute_with_pipe alone it waited forever
## ("Reading additional input from stdin...", seen on 2026-10-23). A redirect from the file ends cleanly,
## and the prompt (your address, for research) stays out of the command line other programs can see.
## {} if a path can't be written safely on a cmd.exe line (a % or a quote in it).
static func launcher(exe: String, args: PackedStringArray, prompt_path: String) -> Dictionary:
	if not OS.has_feature("windows"):
		return {"exe": "/bin/sh", "args": PackedStringArray(["-c", "exec \"$@\" < \"$0\"", prompt_path, exe]) + args, "raw": true}
	var parts := PackedStringArray()
	for a in PackedStringArray([exe]) + args + PackedStringArray([prompt_path]):
		if a.contains("%") or a.contains("\"") or a.contains("\n") or a.contains("\r"):
			return {}
	parts.append("\"%s\"" % exe)
	for a in args:
		var needs := a == "" or a.contains(" ") or a.contains("&") or a.contains("|") or a.contains("<") or a.contains(">") or a.contains("^") or a.contains("(") or a.contains(")")
		parts.append("\"%s\"" % a if needs else a)
	parts.append("< \"%s\"" % prompt_path)
	# One argument: Godot wraps it in quotes, and /s makes cmd take everything inside them as written.
	var comspec := OS.get_environment("COMSPEC")
	return {"exe": comspec if comspec != "" else "cmd.exe", "args": PackedStringArray(["/d", "/v:off", "/s", "/c", " ".join(parts)]), "raw": true}


static func _execute(exe: String, args: PackedStringArray, limit: float, state: Dictionary, raw: bool = false) -> Dictionary:
	var info := OS.execute_with_pipe(exe, args if raw else Args.for_os(args), false)
	if info.is_empty():
		return {"ok": false, "why": "missing", "text": "", "searched": 0}
	var pid := int(info.get("pid", -1))
	var output := ""
	var searched := 0
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid):
		for pipe in [info.get("stdio"), info.get("stderr")]:
			if pipe:
				var text: String = pipe.get_buffer(16384).get_string_from_utf8()
				if output.length() < Json.MAX_BYTES:
					output += text
		if bool(state.cancelled) or Time.get_ticks_msec() - started > int(limit * 1000):
			_kill_tree(pid)
			return {"ok": false, "why": "cancelled" if bool(state.cancelled) else "timeout", "text": "", "searched": searched}
		OS.delay_msec(30)
	for pipe in [info.get("stdio"), info.get("stderr")]:
		if pipe:
			for _i in 8:
				var rest: String = pipe.get_buffer(16384).get_string_from_utf8()
				if rest == "":
					break
				if output.length() < Json.MAX_BYTES:
					output += rest
	searched = _searches_in(output)
	return {"ok": true, "text": output, "why": "", "searched": searched}


## The launcher (cmd.exe / sh) and Codex under it: stopping only the launcher would leave Codex running.
static func _kill_tree(pid: int) -> void:
	if OS.has_feature("windows"):
		OS.execute("taskkill", PackedStringArray(["/PID", str(pid), "/T", "/F"]))
	if OS.is_process_running(pid):
		OS.kill(pid)


## Finished web searches in a stretch of `--json` events (`item.completed` of type web_search).
static func _searches_in(text: String) -> int:
	var seen := {}
	for line in text.split("\n", false):
		var parser := JSON.new()
		if parser.parse(line) != OK or not parser.data is Dictionary:
			continue
		var event: Dictionary = parser.data
		var item: Variant = event.get("item", {})
		if str(event.get("type", "")) == "item.completed" and item is Dictionary and str(item.get("type", "")) == "web_search":
			seen[str(item.get("id", line))] = true
	return seen.size()


## Runs `work` on a thread of its own. Closing the game tells it to stop (background_job.gd joins its
## threads before this node hears about the closing, so the job carries its own way to be told).
func _start(work: Callable) -> Dictionary:
	var state := control
	_job = Job.run(work, func() -> void: state["cancelled"] = true)
	return _job


## Waits for a job, a frame at a time. False when this node left the tree first: the job is told to
## stop, ends on its own thread, and its answer is not read.
func _finished(job: Dictionary, limit_s: float = 315.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit_s * 1000.0)
	while not bool(job.done):
		if not is_inside_tree() or bool(control.get("cancelled", false)) or Time.get_ticks_msec() >= deadline:
			control.cancelled = true
			return false
		await get_tree().process_frame
	return not bool(control.get("cancelled", false))


func check() -> Dictionary:
	var exe := executable()
	if exe == "":
		return Http.fail("Codex CLI was not found on this computer.", "missing")
	var job := _start(_execute.bind(exe, prefix_override + PackedStringArray(["exec", "--help"]), 20.0, control))
	if not await _finished(job, 25.0):
		return Http.fail("Codex request cancelled. Nothing was applied.", "cancelled")
	if not job.result.ok:
		return Http.fail("Couldn't inspect Codex CLI.", str(job.result.why))
	for flag in ["--ignore-user-config", "--ignore-rules", "--ephemeral", "--output-schema", "--output-last-message"]:
		if not str(job.result.text).contains(flag):
			return Http.fail("This Codex CLI lacks the required noninteractive isolation flags. Update it or use copy/paste.", "capability")
	job = _start(_execute.bind(exe, prefix_override + PackedStringArray(["login", "status"]), 20.0, control))
	if not await _finished(job):
		return Http.fail("Codex request cancelled. Nothing was applied.", "cancelled")
	if not job.result.ok:
		return Http.fail("Couldn't check Codex sign-in.", str(job.result.why))
	if not str(job.result.text).to_lower().contains("logged in"):
		return Http.fail("Codex is signed out. Use codex login, then check again.", "signin")
	return {"ok": true, "error": "", "why": "", "access": "ChatGPT" if str(job.result.text).contains("ChatGPT") else "CLI credentials"}


## {"ok", "value", "error", "why", "searched"}: `searched` counts the web searches Codex really ran.
func run(prompt: String, schema: Dictionary, model: String = "", web: bool = false, images: PackedStringArray = PackedStringArray()) -> Dictionary:
	var checked := await check()
	if not checked.ok:
		return checked
	if prompt.length() > MAX_PROMPT:
		return Http.fail("This prompt is too large for the CLI adapter. Use Save prompt / Import JSON.", "size")
	var folder := jobs_dir().path_join(Crypto.new().generate_random_bytes(16).hex_encode())
	var schema_path := folder.path_join("schema.json")
	var output_path := folder.path_join("response.json")
	var prompt_path := folder.path_join("prompt.txt")
	_workspace_dir = folder
	_workspace_files = PackedStringArray([schema_path, output_path, prompt_path])
	if not JsonUtil.write_json(schema_path, Http.strict_schema(schema)):
		_remove_workspace()
		return Http.fail("Couldn't create the private CLI workspace.", "storage")
	# A photo is copied in, so Codex sees that one picture and nothing else of yours.
	var copies := PackedStringArray()
	for i in images.size():
		var ext := images[i].get_extension().to_lower()
		if not ext in ["png", "jpg", "jpeg", "webp"]:
			continue
		var copy := folder.path_join("photo_%d.%s" % [i, ext])
		if DirAccess.copy_absolute(images[i], copy) == OK:
			copies.append(copy)
			_workspace_files.append(copy)
	var lead := "Return only the requested JSON data. Do not execute commands, inspect files, edit a repository or call tools other than web search. Unknown facts must stay empty.\n"
	var pf := FileAccess.open(prompt_path, FileAccess.WRITE)
	if pf == null:
		_remove_workspace()
		return Http.fail("Couldn't create the private CLI workspace.", "storage")
	pf.store_string(lead + prompt)
	pf.close()
	var result: Dictionary
	if model != "" and not _safe_word(model):
		result = Http.fail("That Codex model name has characters Polox won't pass on. Use letters, digits, '.', '-', ':' or '_'.", "configuration")
	else:
		var launch := launcher(executable(), arguments(folder, schema_path, output_path, "-", model, web, copies), prompt_path)
		if launch.is_empty():
			result = Http.fail("Polox's data folder path can't be passed to Codex safely (it contains % or a quote). Use copy/paste instead.", "capability")
		else:
			result = await _run_launch(launch, 300.0 if web else 180.0, output_path)
	_remove_workspace()
	return result


## Removes this run's files (the prompt holds what you asked, so it never outlives the run) and their
## folder. Only the adapter's own known files are removed; no recursive deletion or auth-file access.
func _remove_workspace() -> void:
	if _workspace_dir == "":
		return
	for path in _workspace_files:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
	DirAccess.remove_absolute(_workspace_dir)
	_workspace_dir = ""
	_workspace_files = PackedStringArray()


static func _safe_word(text: String) -> bool:
	for ch in text:
		if not ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in [".", "-", ":", "_"]):
			return false
	return text.length() <= 80


func _run_launch(launch: Dictionary, limit: float, output_path: String) -> Dictionary:
	var job := _start(_execute.bind(str(launch.exe), launch.args, limit, control, bool(launch.raw)))
	if not await _finished(job, limit + 15.0):
		return Http.fail("Codex request cancelled. Nothing was applied.", "cancelled")
	var result: Dictionary
	if not job.result.ok:
		result = Http.fail("Codex request " + str(job.result.why) + ". Nothing was applied.", str(job.result.why))
	elif FileAccess.file_exists(output_path):
		var file := FileAccess.open(output_path, FileAccess.READ)
		result = Json.parse(file.get_as_text()) if file and file.get_length() <= Json.MAX_BYTES else Http.fail("Codex output exceeded the supported size.", "shape")
		if file:
			file.close()
		if result.ok:
			result.value = Http.without_nulls(result.value)
	else:
		var diagnostic := str(job.result.text).to_lower()
		var why := "quota" if diagnostic.contains("usage limit") or diagnostic.contains("quota") else ("model" if diagnostic.contains("model") and (diagnostic.contains("not found") or diagnostic.contains("not supported")) else "provider")
		result = Http.fail("Codex returned no JSON response. " + ("The account's usage limit was reached." if why == "quota" else "Check its sign-in, model and availability, or use copy/paste."), why)
	result["searched"] = int(job.result.get("searched", 0))
	return result


func cancel() -> void:
	control.cancelled = true


## Leaving the tree (the lookup was closed, or the game is closing) while Codex runs: run() can't go on
## to its own tidying from here, so the program is stopped, given a moment to end, and its files removed.
func _exit_tree() -> void:
	cancel()
	var until := Time.get_ticks_msec() + EXIT_WAIT_MS
	while not _job.is_empty() and not bool(_job.done) and Time.get_ticks_msec() < until:
		OS.delay_msec(10)
	_remove_workspace()
