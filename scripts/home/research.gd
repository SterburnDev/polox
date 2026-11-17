extends Node
## Looks up your home with the helper you picked, only after you confirm (the Survey's "Look it up?"
## screen): Claude through Claude Code on this PC (your own Claude sign-in, no key stored in Polox),
## Claude through the API with your key, or Gemini with your chat key. Progress comes back as short
## lines; the answer is the fixed JSON shape in research_prompt.gd, cleaned by home_model.gd.
## Keys and your address never go to the log. Tests use recorded answers (start_recorded) or a stand-in
## Claude Code (exe_override), never live calls.
##
## Only the explicitly selected helper receives the payload. Failure never grants permission to send
## private home details to another provider; the player must select and confirm that recipient.
## Tags: [AI_HELPER]

signal progress(line: String)
signal finished(result: Dictionary)   # {"ok": bool, "research": {...cleaned...}, "error": "", "helper": "", "why": ""}
signal _one_done(result: Dictionary)

const ResearchPrompt := preload("res://scripts/home/research_prompt.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const TellPolox := preload("res://scripts/home/tell_polox.gd")
const ProcArgs := preload("res://scripts/core/proc_args.gd")
const BackgroundJob := preload("res://scripts/core/background_job.gd")
const ApiErrors := preload("res://scripts/ai/api_errors.gd")
const KeyFormat := preload("res://scripts/ai/key_format.gd")

const HELPERS: PackedStringArray = ["claude_code", "claude_api", "gemini", "openai", "codex", "compatible", "pc", "manual", "none"]
static var HELPER_LABELS := {"claude_code": "Claude, on this computer (Claude Code)", "claude_api": "Claude, with your API key",
	"gemini": "Gemini, with your chat key", "openai": "OpenAI API (separate API billing)", "codex": "Codex CLI (your CLI sign-in)", "compatible": "Compatible endpoint (no verified web search)", "manual": "Copy prompt / paste AI response (no key)", "none": "Nobody: just my answers", "pc": "Helper on my paired PC"}
const SHORT := {"claude_code": "Claude Code", "claude_api": "Claude (your key)", "gemini": "Gemini", "openai": "OpenAI API", "codex": "Codex CLI", "compatible": "your configured endpoint", "recorded": "the recording", "pc": "your PC helper"}
static var WHO := {"claude_code": "Anthropic (Claude), through Claude Code on this computer, which searches the web",
	"claude_api": "Anthropic (Claude), using your API key, which searches the web", "gemini": "Google (Gemini), which searches the web", "openai": "OpenAI, using your separately billed API key and web search", "codex": "OpenAI through your Codex CLI sign-in, which searches the web", "compatible": "the endpoint you configured in Settings (no verified web search)", "pc": "your paired PC, then its configured helper", "manual": "the AI you choose outside Polox, only after you review and copy the prompt"}
const CLAUDE_MODEL := "claude-opus-5-5"
## Claude Code is asked for the newest Opus by name; one that doesn't know the name yet gets its alias.
const CLAUDE_CODE_MODEL := "claude-opus-5-5"
const CLAUDE_CODE_ALIAS := "opus"
const GEMINI_MODEL := "gemini-3.6-flash"   # (Google's current Flash; gemini-3.5-flash now routes to it)
const API_URL := "https://api.anthropic.com/v1/messages"
const MAX_BUDGET_USD := "5"
const TIMEOUT_S := 900.0
const SIGN_IN_TEXT := "Claude Code isn't signed in yet (or its sign-in ran out)."

static var pc_helper: Dictionary = {}

static func phone_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for node in tree.root.get_children():
			if node.get_script() and node.get_script().resource_path == "res://scripts/core/main.gd":
				return node.get("phone")
	return null


static var exe_override := ""                     # tests: a stand-in for Claude Code
static var claude_url := ""                       # tests: a stand-in for the Anthropic API ("" = the real one)
static var exe_prefix := PackedStringArray()      # tests: what the stand-in needs before Claude Code's own arguments
static var sign_in_opened := 0                    # tests: how often the sign-in window was asked for
## Claude Code's sign-in, as last checked: -1 not known, 0 not signed in, 1 signed in.
static var sign_in_state := -1
## Google refused web search on the Gemini key this session (the free plan may not include it).
static var gemini_search_off := false
## Anthropic's server-side refusal fallback (beta): asked for by default; an account that doesn't have it
## answers 400 about the header once, and then requests go without it.
static var claude_fallback_ok := true
const CLAUDE_FALLBACK_BETA := "server-side-fallback-2026-07-01"
const CLAUDE_EFFORT := "high"   # (Opus 5.5 defaults to medium; looking a home up deserves more)
const MAX_BUSY_RETRIES := 2

var helper := ""
var running := false
var calls := 0                   # (tests) how many times a helper was actually started
var tried: PackedStringArray = []        # the helpers asked in this run, in order
var available_override: Dictionary = {}  # tests: which helpers count as set up
var _pid := -1
var _pipe: FileAccess
var _err_pipe: FileAccess
var _buf := ""
var _err_buf := ""
var _t := 0.0
var _result_text := ""
var _structured: Variant = null
var _cancelled := false
## Which run this is: start() and cancel() each begin a new one. Everything a run waits on (a request,
## a pause, Claude Code starting or answering) compares its own number with this afterwards, so a run
## that was stopped never reports, even when another one started in the same frame.
var _run := 0
var _cancel_seq := 0
var _http: HTTPRequest           # the provider request in flight (Claude with your key, Gemini)
var _spawning: Dictionary = {}   # Claude Code being started: {"cancelled"} read by the starting thread
var wait_scale := 1.0            # (tests shrink the waits before a retry)
var _model := ""
## What this run asks: the lookup (the detective's question, with web search) or your words (Tell Polox
## about home: no web, the photo you added) and how its answer is cleaned.
var _prompt := ""
var _schema: Dictionary = {}
var _http_helper: Node
var _web := true
var _files := PackedStringArray()
var _cleaner: Callable = HomeModel.clean_research
## Web searches/fetches the helper really made in this run: a lookup without any is only guesses,
## and the preview says so ("grounded" in the result).
var searched := 0
var _photo_dir := ""             # Claude Code reads the photo from a folder holding only that copy


# --- Which helpers are here ----------------------------------------------------------------------

## The Claude Code program, if it's installed ("" if not). Prefers the native claude.exe.
static func claude_code_path() -> String:
	if exe_override != "":
		return exe_override
	if _in_tests():
		return ""   # the tests never start the real Claude Code (a stand-in, or nothing)
	var home := OS.get_environment("USERPROFILE") if OS.has_feature("windows") else OS.get_environment("HOME")
	var appdata := OS.get_environment("APPDATA")
	var candidates: PackedStringArray = []
	if OS.has_feature("windows"):
		candidates.append(home.path_join(".local/bin/claude.exe"))
		if appdata != "":
			candidates.append(appdata.path_join("npm/node_modules/@anthropic-ai/claude-code/bin/claude.exe"))
		candidates.append(OS.get_environment("LOCALAPPDATA").path_join("Programs/claude/claude.exe"))
		for p in OS.get_environment("PATH").split(";", false):
			candidates.append(p.path_join("claude.exe"))
	else:
		candidates.append(home.path_join(".local/bin/claude"))
		candidates.append("/usr/local/bin/claude")
		candidates.append("/opt/homebrew/bin/claude")
	for c in candidates:
		if c != "" and FileAccess.file_exists(c):
			return c
	return ""


static func _in_tests() -> bool:
	for a in OS.get_cmdline_args():
		if a.ends_with("run_tests.gd"):
			return true
	return false


static func settings() -> Dictionary:
	var lw: Variant = GameState.settings.get("light_world", {})
	return lw if lw is Dictionary else {}


## The Gemini key from Settings > AI (Gemini's own: each provider keeps its key since 1.27).
static func gemini_key() -> String:
	var ai: Dictionary = GameState.settings.get("ai", {}) if GameState.settings.get("ai") is Dictionary else {}
	if ai.get("keys") is Dictionary:
		var own := str((ai.keys as Dictionary).get("gemini", "")).strip_edges()
		return own if KeyFormat.fits(own, "gemini") else ""   # (another service's key is never sent to Google)
	if str(ai.get("preset", "")) == "gemini" or str(ai.get("base_url", "")).contains("generativelanguage"):
		return str(ai.get("api_key", "")).strip_edges()   # (settings from before 1.27)
	return ""


## {helper id: true/false}: which helpers could run right now (nothing is called to find out).
static func available() -> Dictionary:
	var s := settings()
	return {"claude_code": not OS.has_feature("web") and not OS.has_feature("android") and claude_code_path() != "",
		"claude_api": str(s.get("claude_api_key", "")).strip_edges() != "",
		"gemini": gemini_key() != "", "openai": str(s.get("openai_key", "")) != "" and str(s.get("openai_model", "")) != "",
		"codex": not _in_tests() and preload("res://scripts/home/helper_codex.gd").executable() != "",
		"compatible": str(s.get("compatible_url", "")) != "" and str(s.get("compatible_model", "")) != "", "pc": bool(pc_helper.get("ready", false)) and phone_node() != null, "manual": true, "none": true}


## Preserve an explicit choice even when its credentials/tool become unavailable.
static func preferred() -> String:
	var av := available()
	var chosen := str(settings().get("helper", ""))
	if chosen in HELPERS:
		return chosen
	for h in HELPERS:
		if h != "manual" and bool(av.get(h, false)):
			return h
	return "none"


## Compatibility entry point: availability never authorizes another recipient.
static func chain(first: String, _av: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if first in HELPERS and first != "none":
		out.append(first)
	return out


## What to say when no helper could answer: why, and (for a sign-in) where to fix it.
static func advice(res: Dictionary) -> String:
	var e := str(res.get("error", "")).strip_edges()
	if e == "":
		e = "It couldn't look."
	if str(res.get("why", "")) == "signin":
		e += " (Settings > Light World > Sign in to Claude.)"
	return e


static func short_name(h: String) -> String:
	return str(SHORT.get(h, h))


## How a helper stands, in a few words for Settings and the Survey.
static func state_note(h: String, av: Dictionary) -> String:
	match h:
		"pc":
			return "ready through your PC" if bool(av.get("pc", false)) else "connect and Sync with your PC"
		"manual":
			return "copy and paste; no connection needed"
		"none":
			return "your answers only"
		"claude_code":
			if not bool(av.get("claude_code", false)):
				return "not on this computer"
			return str({1: "ready", 0: "sign in first"}.get(sign_in_state, "installed"))
		"claude_api":
			return "ready" if bool(av.get("claude_api", false)) else "needs a key"
		"gemini":
			if not bool(av.get("gemini", false)):
				return "set up in AI"
			return "can't search on this key" if gemini_search_off else "ready"
		"openai", "compatible":
			return "configured" if bool(av.get(h, false)) else "needs setup below"
		"codex":
			return "installed (check its sign-in below)" if bool(av.get(h, false)) else "not installed"
	return ""


# --- Claude Code's sign-in -----------------------------------------------------------------------

## Asks Claude Code whether it's signed in (`claude auth status`, a few seconds, nothing sent anywhere).
## Returns 1 (signed in), 0 (not) or -1 (couldn't tell), and remembers it in sign_in_state.
## (Starting Claude Code takes about a second and a half on Windows, so it happens on a thread: the game
## never freezes for it.)
func check_sign_in() -> int:
	var exe := claude_code_path()
	if exe == "":
		return -1
	var seq := _cancel_seq
	var args := exe_prefix.duplicate()
	args.append_array(PackedStringArray(["auth", "status", "--json"]))
	var control := {"cancelled": false}
	var job := BackgroundJob.run(_run_and_read.bind(exe, ProcArgs.for_os(args), 20.0, control), func() -> void: control["cancelled"] = true)
	var deadline := Time.get_ticks_msec() + 25000
	while not bool(job.done):
		if not is_inside_tree() or seq != _cancel_seq or Time.get_ticks_msec() >= deadline:
			control["cancelled"] = true   # nobody waits for the answer any more: the check stops too
			return -1
		await get_tree().process_frame
	var d: Variant = _json_in(str(job.result))
	var state := -1
	if d is Dictionary and (d as Dictionary).has("loggedIn"):
		state = 1 if bool(d.loggedIn) else 0
	sign_in_state = state
	return state


## (On a thread.) Starts a program, reads what it prints until it ends, `limit_s` passes or
## `state.cancelled` is set (the game is closing, or whoever asked is gone): then it's stopped.
static func _run_and_read(exe: String, args: PackedStringArray, limit_s: float, state: Dictionary = {}) -> String:
	var info: Dictionary = OS.execute_with_pipe(exe, args, false)
	if info.is_empty() or int(info.get("pid", -1)) <= 0:
		return ""
	var pid := int(info.pid)
	var pipe: FileAccess = info.get("stdio")
	var out := ""
	var t0 := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < int(limit_s * 1000.0) and not bool(state.get("cancelled", false)):
		out += pipe.get_buffer(65536).get_string_from_utf8()
		OS.delay_msec(50)
	if OS.is_process_running(pid):
		OS.kill(pid)
	out += pipe.get_buffer(65536).get_string_from_utf8()
	return out


## (On a thread.) Starts a program and hands back its pipes: {pid, stdio, stderr} or {}. A program whose
## start was cancelled meanwhile (`state.cancelled`) is stopped again at once: {}.
static func _spawn(exe: String, args: PackedStringArray, state: Dictionary = {}) -> Dictionary:
	var info: Dictionary = OS.execute_with_pipe(exe, args, false)
	if bool(state.get("cancelled", false)):
		if int(info.get("pid", -1)) > 0:
			OS.kill(int(info.pid))
		return {}
	return info


## Opens Claude Code's own sign-in in a window of its own (`claude auth login`: it opens your browser).
## Polox never sees your account; it only asks afterwards whether Claude Code is signed in.
static func open_sign_in() -> bool:
	var exe := claude_code_path()
	if exe == "":
		return false
	if exe_override != "":
		sign_in_opened += 1   # tests: no window
		return true
	if OS.has_feature("windows"):
		return OS.create_process("cmd.exe", PackedStringArray(["/c", "start", "Sign in to Claude", exe, "auth", "login"])) > 0
	return OS.create_process(exe, PackedStringArray(["auth", "login"])) > 0


## After the sign-in window opened: checks every few seconds (up to `minutes`) until Claude Code is
## signed in. Returns true once it is.
func wait_for_sign_in(minutes: float = 5.0) -> bool:
	var seq := _cancel_seq
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(minutes * 60000.0) and is_inside_tree() and seq == _cancel_seq:
		if await check_sign_in() == 1:
			return true
		var pause_until := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < pause_until and is_inside_tree() and seq == _cancel_seq:
			await get_tree().process_frame
	return false


# --- Running -------------------------------------------------------------------------------------

func start(which: String, where: String, known: Dictionary, files: PackedStringArray = PackedStringArray()) -> void:
	_prompt = ResearchPrompt.question(where, known, files)
	_schema = preload("res://scripts/home/helper_json.gd").closed(ResearchPrompt.response_schema())
	_web = true
	_files = files
	_cleaner = HomeModel.clean_research
	_run_chain(which)


## Tell Polox about home, read by a helper (only when you tap "Ask Claude to read it"): your words and
## the photo, the rooms you have, no address, no web. The answer is the same proposal the offline reader makes.
func start_words(which: String, text: String, plan: Dictionary, photo: String = "") -> void:
	_prompt = TellPolox.words_prompt(text, plan, photo != "")
	_schema = preload("res://scripts/home/helper_json.gd").closed(TellPolox.WORDS_SCHEMA)
	_web = false
	_files = PackedStringArray([photo]) if photo != "" else PackedStringArray()
	_cleaner = func(raw: Dictionary) -> Dictionary: return TellPolox.clean_helper(raw, plan)
	_run_chain(which)


func _run_chain(first: String) -> void:
	_run += 1
	var mine := _run
	_cancelled = false
	_abort_active()
	searched = 0
	tried.clear()
	if is_inside_tree():
		await get_tree().process_frame   # the caller is awaiting `finished` by then, even if nothing can run
	if mine != _run or not is_inside_tree():
		return
	var order := chain(first, available_override if not available_override.is_empty() else available())
	if order.is_empty():
		running = false
		finished.emit(_fail("No helper is set up.", "missing"))
		return
	tried.append(order[0])
	var last := await _run_one(order[0], mine)
	if mine != _run or not is_inside_tree():
		return   # stopped (or stopped and asked again): this run says nothing
	running = false
	finished.emit(last)


## Lets go of a helper node this run made. A stopped run that ends late must not take away the helper
## of the run that started after it.
func _drop_helper(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
	if _http_helper == node:
		_http_helper = null


func _run_one(which: String, mine: int) -> Dictionary:
	helper = which
	match which:
		"pc":
			if not _files.is_empty():
				return _fail("The PC helper reads text only. Remove the photo or choose a photo helper.", "capability")
			var pc: Node = preload("res://scripts/home/helper_pc.gd").new()
			_http_helper = pc
			add_child(pc)
			progress.emit("Asking the helper on your PC...")
			var result: Dictionary = await pc.run(phone_node(), str(pc_helper.get("provider", "")), _prompt, _schema, _web)
			_drop_helper(pc)
			if mine != _run:
				return _stopped()
			searched += int(result.get("searched", 0))
			if not bool(result.get("ok", false)):
				return _fail(str(result.get("error", "PC helper failed.")), str(result.get("why", "offline")))
			return _ok(result.get("value", {}))
		"claude_code":
			if claude_code_path() == "":
				return _fail("Claude Code isn't installed on this computer.", "missing")
			progress.emit("Checking Claude Code's sign-in...")
			var signed_in := await check_sign_in()
			if mine != _run:
				return _stopped()
			if signed_in == 0:
				return _fail(SIGN_IN_TEXT, "signin")
			_model = str(settings().get("claude_model", "")).strip_edges()
			if _model == "":
				_model = CLAUDE_CODE_MODEL
			var now: Dictionary = await _launch_claude_code(mine)
			if not now.is_empty():
				return now
			var r: Dictionary = await _one_done
			if mine != _run:
				return _stopped()
			if str(r.get("why", "")) == "model" and _model != CLAUDE_CODE_ALIAS:
				_model = CLAUDE_CODE_ALIAS   # this Claude Code doesn't know the newest Opus by name yet
				now = await _launch_claude_code(mine)
				if not now.is_empty():
					return now
				r = await _one_done
				if mine != _run:
					return _stopped()
			if str(r.get("why", "")) == "model":
				r = _fail("Claude Code didn't know the model to use (Settings > Light World > Claude model).", "other")
			return r
		"claude_api":
			return await _claude_api(mine)
		"gemini":
			return await _gemini(mine)
		"codex":
			var codex: Node = preload("res://scripts/home/helper_codex.gd").new()
			_http_helper = codex
			add_child(codex)
			running = true
			calls += 1
			progress.emit("Asking Codex to look (live web search)..." if _web else "Asking Codex to read it...")
			var result: Dictionary = await codex.run(_prompt, _schema, str(settings().get("codex_model", "")), _web, _files)
			_drop_helper(codex)
			if mine != _run:
				return _stopped()
			searched += int(result.get("searched", 0))
			if not bool(result.ok):
				return _fail(str(result.error), str(result.get("why", "shape")))
			return _ok(result.value)
		"openai", "compatible":
			if not _files.is_empty():
				return _fail("This adapter currently reads text only. Remove the photo or use a supported photo helper.", "capability")
			var adapter: Node = preload("res://scripts/home/helper_http.gd").new()
			_http_helper = adapter
			add_child(adapter)
			running = true
			calls += 1
			progress.emit("Asking " + short_name(which) + "...")
			var result: Dictionary = await adapter.run(which, settings(), _prompt, _schema, _web)
			_drop_helper(adapter)
			if mine != _run:
				return _stopped()
			searched += int(result.get("searched", 0))
			if not bool(result.ok):
				return _fail(str(result.error), str(result.why))
			return _ok(result.value)
	return _fail("No helper.", "missing")


## What a run that was stopped hands back (it is never reported: see _run_chain).
func _stopped() -> Dictionary:
	return _fail("Stopped.", "other")


func _fail(error: String, why: String) -> Dictionary:
	return {"ok": false, "research": {}, "error": error, "helper": helper, "why": why}


## Every helper's answer passes the same strict check as a pasted one (types, bounds, enums, source
## references) before anything is cleaned or shown; `raw` goes on to helper_request.accept().
func _ok(answer: Dictionary) -> Dictionary:
	# Automatic and manual answers obey the same exact schema; do not conceal
	# malformed provider output by projecting unsupported fields away.
	var raw := answer
	var error := ResearchPrompt.validate_response(raw) if _web else TellPolox.validate_helper(raw)
	if error != "":
		return _fail("The helper's answer didn't fit what Polox can use (%s). Nothing changed." % error, "shape")
	var cleaned: Dictionary = _cleaner.call(raw)
	if _web:
		cleaned["grounded"] = searched > 0
	return {"ok": true, "research": cleaned, "raw": raw, "error": "", "helper": helper, "why": "", "searched": searched}


## Tests and drives: a recorded answer instead of a live call (no network at all).
func start_recorded(path: String, delay_s: float = 0.2) -> void:
	_run += 1
	var mine := _run
	_cancelled = false
	_abort_active()
	helper = "recorded"
	running = true
	for line in ["Reading the county records...", "Comparing the listing's floor plan..."]:
		progress.emit(line)
		if not is_inside_tree():
			running = false
			return
		await get_tree().process_frame   # (always a frame: the caller is awaiting `finished` by then)
		if not await _pause(delay_s, mine):
			return   # stopped, or this node left the tree: like a real lookup, it says nothing
	if mine != _run or not is_inside_tree():
		running = false
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	running = false
	if not raw is Dictionary:
		finished.emit({"ok": false, "research": {}, "error": "the recorded answer isn't JSON", "helper": helper, "why": "shape"})
		return
	finished.emit({"ok": true, "research": HomeModel.clean_research(raw), "error": "", "helper": helper, "why": ""})


func _abort_active() -> void:
	if is_instance_valid(_http_helper):
		_http_helper.cancel()
	if is_instance_valid(_http):
		_http.cancel_request()
	if not _spawning.is_empty():
		_spawning["cancelled"] = true
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	_pipe = null
	_err_pipe = null
	running = false
	_clear_photo_dir()


## Stops the lookup: whatever it is doing ends now (the helper's request is cancelled, Claude Code is
## stopped, one that is still starting is stopped as soon as it has started) and `finished` is not emitted.
func cancel() -> void:
	_cancelled = true
	_run += 1
	_cancel_seq += 1
	_abort_active()
	# A run waiting for Claude Code's answer stops waiting (it sees the new run number and says nothing).
	_one_done.emit(_stopped())


func _exit_tree() -> void:
	cancel()


# --- Claude Code ---------------------------------------------------------------------------------

## Claude Code, headless: only web search and web fetch (and reading the files you saved), no session
## kept, a spending cap, JSON out. It uses your own Claude sign-in. Returns {} once it's running
## (the answer comes as _one_done), or the failure.
func _launch_claude_code(mine: int) -> Dictionary:
	var exe := claude_code_path()
	var tool_list: PackedStringArray = []
	if _web:
		tool_list.append_array(["WebSearch", "WebFetch"])
	if not _files.is_empty():
		tool_list.append("Read")
	var tools := ",".join(tool_list)
	var prompt := _prompt
	# The photo goes as a copy in a folder of its own: Read can open that one picture, not the rest of
	# my_home/files (a permit list, a sketch, other photos you never chose to send).
	_clear_photo_dir()
	if not _files.is_empty():
		_photo_dir = preload("res://scripts/home/helper_codex.gd").jobs_dir().path_join("photo_" + Crypto.new().generate_random_bytes(8).hex_encode())
		DirAccess.make_dir_recursive_absolute(_photo_dir)
		var copy := _photo_dir.path_join("photo." + _files[0].get_extension().to_lower())
		if DirAccess.copy_absolute(_files[0], copy) != OK:
			_clear_photo_dir()
			return _fail("Couldn't prepare the photo for Claude Code.", "other")
		prompt += "\nThe photo is at: " + copy
	var args := exe_prefix.duplicate()
	args.append_array(PackedStringArray(["-p", prompt, "--model", _model,
		"--output-format", "stream-json", "--verbose", "--tools", tools, "--allowedTools", tools,
		"--no-session-persistence", "--strict-mcp-config", "--max-budget-usd", MAX_BUDGET_USD,
		"--json-schema", JSON.stringify(_schema)]))
	if _photo_dir != "":
		args.append_array(["--add-dir", _photo_dir])
	# (Starting it takes a moment, so it starts on a thread. Stopped meanwhile, by cancel() or by this
	# node leaving the tree: the thread stops the program again as soon as it has started.)
	var state := {"cancelled": false}
	_spawning = state
	var job := BackgroundJob.run(_spawn.bind(exe, ProcArgs.for_os(args), state), func() -> void: state["cancelled"] = true)
	var spawn_deadline := Time.get_ticks_msec() + 30000
	while not bool(job.done) and is_inside_tree() and mine == _run and Time.get_ticks_msec() < spawn_deadline:
		await get_tree().process_frame
	if is_same(_spawning, state):
		_spawning = {}
	if mine != _run or not is_inside_tree() or not bool(job.done):
		state["cancelled"] = true
		var started: Dictionary = job.result if bool(job.done) and job.result is Dictionary else {}
		if int(started.get("pid", -1)) > 0 and OS.is_process_running(int(started.pid)):
			OS.kill(int(started.pid))   # (it had started just before the stop was seen)
		_clear_photo_dir()
		return _stopped() if (mine != _run or not is_inside_tree()) else _fail("Claude Code took too long to start.", "timeout")
	var info: Dictionary = job.result if job.result is Dictionary else {}
	calls += 1
	if info.is_empty() or int(info.get("pid", -1)) <= 0:
		_clear_photo_dir()
		return _fail("Claude Code wouldn't start.", "missing")
	_pid = int(info.pid)
	_pipe = info.get("stdio")
	_err_pipe = info.get("stderr")
	_buf = ""
	_err_buf = ""
	_t = 0.0
	_result_text = ""
	_structured = null
	running = true
	progress.emit("Asking Claude to look..." if _web else "Asking Claude to read it...")
	return {}


func _process(delta: float) -> void:
	if not running or _pid <= 0:
		return
	_t += delta
	_read_pipe()
	if _t > TIMEOUT_S:
		var pid := _pid
		_pid = -1
		running = false
		if OS.is_process_running(pid):
			OS.kill(pid)
		_clear_photo_dir()
		_one_done.emit(_fail("It took too long. Try again later, or use your answers.", "timeout"))
		return
	if not OS.is_process_running(_pid):
		_read_pipe()
		running = false
		_pid = -1
		_clear_photo_dir()
		_one_done.emit(_finish_claude_code())


func _clear_photo_dir() -> void:
	if _photo_dir == "":
		return
	for f in DirAccess.get_files_at(_photo_dir):
		DirAccess.remove_absolute(_photo_dir.path_join(f))
	DirAccess.remove_absolute(_photo_dir)
	_photo_dir = ""


func _read_pipe() -> void:
	if _err_pipe != null:
		var err_reads := 0
		var e := _err_pipe.get_buffer(65536)
		while e.size() > 0 and err_reads < 64:
			err_reads += 1
			_err_buf += e.get_string_from_utf8()
			e = _err_pipe.get_buffer(65536)
		if _err_buf.length() > 20000:
			_err_buf = _err_buf.right(20000)
	if _pipe == null:
		return
	var out_reads := 0
	var chunk := _pipe.get_buffer(65536)
	while chunk.size() > 0 and out_reads < 64:
		out_reads += 1
		_buf += chunk.get_string_from_utf8()
		chunk = _pipe.get_buffer(65536)
	var lines := 0
	while _buf.contains("\n") and lines < 512:
		lines += 1
		var i := _buf.find("\n")
		var line := _buf.left(i).strip_edges()
		_buf = _buf.substr(i + 1)
		if line != "":
			_on_event(line)


## One stream-json event: tool calls become progress lines, the result is kept.
func _on_event(line: String) -> void:
	var ev: Variant = _quiet_json(line)   # (other lines, like a warning, are skipped quietly)
	if not ev is Dictionary:
		return
	match str(ev.get("type", "")):
		"assistant":
			var msg: Dictionary = ev.get("message", {}) if ev.get("message") is Dictionary else {}
			for c in msg.get("content", []):
				if c is Dictionary and str(c.get("type", "")) == "tool_use":
					if str(c.get("name", "")) in ["WebSearch", "WebFetch"]:
						searched += 1
					progress.emit(_describe_tool(str(c.get("name", "")), c.get("input", {})))
		"result":
			_result_text = str(ev.get("result", ""))
			_structured = ev.get("structured_output")
			if bool(ev.get("is_error", false)):
				_result_text = "ERROR:" + _result_text


static func _describe_tool(tool_name: String, input: Variant) -> String:
	var inp: Dictionary = input if input is Dictionary else {}
	match tool_name:
		"WebSearch":
			var q := str(inp.get("query", "")).to_lower()
			for w in [["assessor", "Reading the county assessor's record..."], ["permit", "Looking through building permits..."],
					["parcel", "Finding the parcel map..."], ["plat", "Finding the plat map..."], ["sanborn", "Opening old fire-insurance maps..."],
					["listing", "Looking at listings..."], ["floor plan", "Looking for a floor plan..."], ["zillow", "Looking at listings..."],
					["redfin", "Looking at listings..."], ["archive", "Checking archived pages..."]]:
				if q.contains(str(w[0])):
					return str(w[1])
			return "Searching the public record..."
		"WebFetch":
			var u := str(inp.get("url", "")).to_lower()
			if u.contains("web.archive.org"):
				return "Reading an archived page..."
			if u.contains("permit"):
				return "Reading a permit page..."
			if u.contains("gis") or u.contains("parcel"):
				return "Reading the county map..."
			return "Reading a page..."
		"Read":
			return "Reading the files you saved..."
	return "Thinking it over..."


## Claude Code finished: its answer (cleaned), or why it couldn't give one.
func _finish_claude_code() -> Dictionary:
	if _buf.strip_edges() != "":
		_on_event(_buf.strip_edges())   # a last line without its newline
		_buf = ""
	if _result_text.begins_with("ERROR:") or (_result_text == "" and _structured == null):
		var why := (_result_text.trim_prefix("ERROR:") + " " + _err_buf).strip_edges()
		var low := why.to_lower()
		if low.contains("api key"):
			return _fail("Claude Code's external API key was refused. Fix it in Claude Code or choose another helper.", "key")
		if low.contains("login") or low.contains("authenticat") or low.contains("not logged") or low.contains("oauth") or low.contains("credential"):
			sign_in_state = 0
			return _fail(SIGN_IN_TEXT, "signin")
		if low.contains("model") and (low.contains("not found") or low.contains("invalid") or low.contains("not exist") or low.contains("not available") or low.contains("unknown")):
			return _fail("Claude Code didn't know that model.", "model")
		if low.contains("budget"):
			return _fail("The lookup hit its spending cap before it finished.", "budget")
		if low.contains("rate limit") or low.contains("usage limit") or low.contains("429") or low.contains("overloaded") or low.contains("limit reached"):
			return _fail("Claude is at its usage limit for now.", "quota")
		if low.contains("enotfound") or low.contains("econn") or low.contains("network") or low.contains("fetch failed") or low.contains("timed out"):
			return _fail("Claude Code couldn't reach the internet.", "offline")
		var first := why.get_slice("\n", 0).strip_edges().left(140)
		return _fail("Claude Code stopped%s." % ((": " + first) if first != "" else " without an answer"), "other")
	sign_in_state = 1
	var raw: Variant = _structured if _structured is Dictionary else _json_in(_result_text)
	if not raw is Dictionary:
		return _fail("Claude's answer wasn't in the shape Polox needs.", "shape")
	return _ok(raw)


## The JSON object in a reply (it may come wrapped in a ```json block or a sentence).
static func _json_in(text: String) -> Variant:
	var t := text.strip_edges()
	var a := t.find("{")
	var b := t.rfind("}")
	if a < 0 or b <= a:
		return null
	return _quiet_json(t.substr(a, b - a + 1))


static func _quiet_json(text: String) -> Variant:
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


# --- Claude with your API key --------------------------------------------------------------------

## The Messages API with web search and web fetch (server tools); long searches pause and continue.
func _claude_api(mine: int = -1) -> Dictionary:
	if mine < 0:
		mine = _run   # (called on its own, by a test: the run as it is now)
	var key := str(settings().get("claude_api_key", "")).strip_edges()
	if key == "":
		return _fail("There's no Claude API key in Settings > Light World.", "key")
	if not KeyFormat.fits(key, "anthropic"):
		return _fail(KeyFormat.mismatch(key, "anthropic"), "key")   # (another service's key is never sent to Anthropic)
	running = true
	calls += 1
	var content: Array = [{"type": "text", "text": _prompt}]
	for f in _files:
		var ext := f.get_extension().to_lower()
		var bytes := FileAccess.get_file_as_bytes(f)
		if bytes.size() == 0 or bytes.size() > 8 * 1024 * 1024:
			continue
		if ext == "pdf":
			content.append({"type": "document", "source": {"type": "base64", "media_type": "application/pdf", "data": Marshalls.raw_to_base64(bytes)}})
		elif ext in ["png", "jpg", "jpeg", "webp"]:
			content.append({"type": "image", "source": {"type": "base64", "media_type": "image/" + ("jpeg" if ext == "jpg" else ext), "data": Marshalls.raw_to_base64(bytes)}})
	var messages: Array = [{"role": "user", "content": content}]
	progress.emit("Asking Claude to look..." if _web else "Asking Claude to read it...")
	var turns := 0
	var busy := 0
	var steps := 0
	while turns < 8 and steps < 24:
		steps += 1
		if mine != _run or not is_inside_tree():
			running = false
			return _stopped()
		var api_model := str(settings().get("claude_model", "")).strip_edges()
		var body := {"model": api_model if api_model != "" else CLAUDE_MODEL, "max_tokens": 16000, "thinking": {"type": "adaptive"},
			"output_config": {"effort": CLAUDE_EFFORT}, "messages": messages}
		if _web:
			body["tools"] = [{"type": "web_search_20260209", "name": "web_search"}, {"type": "web_fetch_20260209", "name": "web_fetch"}]
		var headers := PackedStringArray(["content-type: application/json", "x-api-key: " + key, "anthropic-version: 2023-06-01"])
		if claude_fallback_ok:
			# A safety decline is retried on the model Anthropic recommends for it, server-side.
			body["fallbacks"] = "default"
			headers.append("anthropic-beta: " + CLAUDE_FALLBACK_BETA)
		var http := HTTPRequest.new()
		http.timeout = 600.0
		add_child(http)
		if http.request(claude_url if claude_url != "" else API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
			http.queue_free()
			running = false
			return _fail("Couldn't reach Anthropic.", "offline")
		var res: Array = await _answer(http, mine)
		http.queue_free()
		if mine != _run:
			return _stopped()
		if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
			running = false
			return _fail("Anthropic took too long to answer. Try again." if int(res[0]) == HTTPRequest.RESULT_TIMEOUT else "Couldn't reach Anthropic.", "offline")
		var code: int = res[1]
		var body_text := (res[3] as PackedByteArray).get_string_from_utf8()
		var reply: Variant = JSON.parse_string(body_text)
		if code != 200 or not reply is Dictionary:
			var err := claude_error(code, reply, res[2], key, body_text)
			if bool(err.get("drop_fallback", false)) and claude_fallback_ok:
				claude_fallback_ok = false   # this account has no fallback beta: plain requests from now on
				continue
			if bool(err.get("retry", false)) and busy < MAX_BUSY_RETRIES:
				busy += 1
				# What Anthropic asked (Retry-After, 1 to 60 s) is waited as asked; when it didn't say,
				# a little longer each time. Stop ends the wait at once.
				var wait := float(err.wait) if bool(err.get("asked", false)) else minf(ApiErrors.RETRY_MAX_S, float(err.get("wait", 4.0)) * busy)
				progress.emit("Anthropic is busy; trying again in %d s..." % ceili(wait))
				if not await _pause(wait * wait_scale, mine):
					if mine == _run:
						running = false
					return _stopped()
				continue
			running = false
			return _fail(str(err.error), str(err.why))
		busy = 0
		for c in reply.get("content", []):
			if c is Dictionary and str(c.get("type", "")) == "server_tool_use":
				searched += 1
				progress.emit(_describe_tool("WebSearch" if str(c.get("name", "")) == "web_search" else "WebFetch", c.get("input", {})))
		var stop := str(reply.get("stop_reason", ""))
		if stop == "pause_turn":
			# A long search paused: send its turn back as it is and Claude carries on (no extra message).
			messages.append({"role": "assistant", "content": reply.get("content", [])})
			turns += 1
			continue
		running = false
		if stop == "refusal":
			return _fail("Claude declined this lookup (Anthropic's safety check). Nothing changed. Try the Copy prompt way or another helper.", "refusal")
		var text := ""
		for c in reply.get("content", []):
			if c is Dictionary and str(c.get("type", "")) == "text":
				text += str(c.get("text", ""))
		if stop == "max_tokens":
			return _fail("Claude's answer was cut off before it ended (too long). Try with fewer photos or files.", "shape")
		var raw: Variant = _json_in(text)
		if not raw is Dictionary:
			return _fail("Claude's answer wasn't in the shape Polox needs.", "shape")
		return _ok(raw)
	running = false
	return _fail("The lookup went on too long.", "timeout")


## Waits before a retry (real time), watching for Stop. False when stopped.
func _pause(seconds: float, mine: int) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and mine == _run and is_inside_tree():
		await get_tree().process_frame
	return mine == _run and is_inside_tree()


## A provider request's outcome, as request_completed gives it. Stop (or this node leaving the tree)
## ends the wait at once and cancels the request, so nothing more is sent or paid for: Godot's
## cancel_request never emits request_completed, so this looks each frame instead of awaiting it
## (as ai_client.gd's _answer does).
func _answer(http: HTTPRequest, mine: int) -> Array:
	_http = http
	var box := {"res": []}
	http.request_completed.connect(func(a, b, c, d): box.res = [a, b, c, d], CONNECT_ONE_SHOT)
	var timeout_s := http.timeout if is_instance_valid(http) and http.timeout > 0.0 else 600.0
	var deadline := Time.get_ticks_msec() + int((timeout_s + 15.0) * 1000.0)
	while (box.res as Array).is_empty() and mine == _run and is_inside_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if _http == http:
		_http = null
	if (box.res as Array).is_empty():
		if is_instance_valid(http):
			http.cancel_request()
		if mine == _run and is_inside_tree():
			return [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
		return [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]
	return box.res


## An Anthropic error -> {error (said to the player, Anthropic's own words where they help), why,
## retry (busy or overloaded: worth one more go), wait (seconds), drop_fallback (the fallback beta
## isn't on this account)}. The key never appears in what's shown.
static func claude_error(code: int, reply: Variant, headers: PackedStringArray, key: String = "", raw: String = "") -> Dictionary:
	var kind := ""
	var said := ""
	if reply is Dictionary and reply.get("error") is Dictionary:
		kind = str(reply.error.get("type", ""))
		said = str(reply.error.get("message", ""))
	if key != "":
		said = said.replace(key, "[key]")
	said = said.substr(0, 220)
	# How long Anthropic asked us to wait (1 to 60 s); "asked" is false when it didn't say.
	var asked := ApiErrors.retry_after(headers)
	var wait := asked if asked > 0.0 else 4.0
	if code == 400 and said.to_lower().contains("anthropic-beta"):
		return {"error": "Anthropic couldn't use this request.", "why": "other", "drop_fallback": true}
	# A refused network (a block page, or "Request not allowed") or an empty balance, whatever the
	# code they came with, are not the key's fault and not worth a retry.
	var what := ApiErrors.kind(code, raw if raw != "" else said)
	if what == ApiErrors.NETWORK:
		return {"error": "Anthropic is refusing connections from this network or region (a VPN can cause this). Try another network or another helper.", "why": "provider"}
	if what == ApiErrors.CREDIT:
		return {"error": "Anthropic says this account has no credit left. Add credit or set up billing at console.anthropic.com.", "why": "quota"}
	match code:
		401:
			return {"error": "Anthropic didn't accept the API key: it is wrong, expired or switched off (Settings > Light World).", "why": "key"}
		403:
			return {"error": "This key isn't allowed to do that (check its permissions in console.anthropic.com).", "why": "key"}
		404:
			return {"error": "Anthropic has no model of that name for this key (Settings > Light World > Claude model).", "why": "other"}
		413:
			return {"error": "The photos or files are too big together. Use fewer or smaller ones.", "why": "other"}
		429:
			return {"error": "Anthropic is at this key's limit right now. Try again in a minute.", "why": "quota", "retry": true, "wait": wait, "asked": asked > 0.0}
		500, 502, 503, 504, 529:
			return {"error": "Anthropic is busy or overloaded right now. Try again in a little while.", "why": "quota", "retry": true, "wait": wait, "asked": asked > 0.0}
		400:
			var known := preload("res://scripts/home/helper_http.gd").explain(said)
			return {"error": known if known != "" else "Anthropic couldn't use this request (%s)." % (kind if kind != "" else "HTTP 400"), "why": "other"}
	return {"error": "Anthropic said no (HTTP %d)." % code, "why": "other"}


# --- Gemini --------------------------------------------------------------------------------------

## Gemini with Google Search grounding (your chat key); Tell Polox's reading needs no search.
func _gemini(mine: int = -1) -> Dictionary:
	if mine < 0:
		mine = _run
	var key := gemini_key()
	if key == "":
		return _fail("There's no Gemini key in Settings > AI.", "key")
	if _web and gemini_search_off:
		return _fail("Gemini can't search the web on this key right now.", "quota")
	running = true
	calls += 1
	progress.emit("Asking Gemini to look..." if _web else "Asking Gemini to read it...")
	var model := str(settings().get("gemini_model", "")).strip_edges()
	if model == "":
		model = GEMINI_MODEL
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % model
	var parts: Array = [{"text": _prompt}]
	for f in _files:
		var ext := f.get_extension().to_lower()
		var bytes := FileAccess.get_file_as_bytes(f)
		if ext in ["png", "jpg", "jpeg", "webp"] and bytes.size() > 0 and bytes.size() <= 8 * 1024 * 1024:
			parts.append({"inline_data": {"mime_type": "image/" + ("jpeg" if ext == "jpg" else ext), "data": Marshalls.raw_to_base64(bytes)}})
	var body := {"contents": [{"role": "user", "parts": parts}]}
	if _web:
		body["tools"] = [{"google_search": {}}]
	var headers := PackedStringArray(["Content-Type: application/json", "x-goog-api-key: " + key])
	var res: Array = []
	for attempt in 2:
		if mine != _run or not is_inside_tree():
			running = false
			return _stopped()
		var http := HTTPRequest.new()
		http.timeout = 300.0
		add_child(http)
		if http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
			http.queue_free()
			running = false
			return _fail("Couldn't reach Google.", "offline")
		res = await _answer(http, mine)
		http.queue_free()
		if mine != _run or not is_inside_tree() or int(res[0]) != HTTPRequest.RESULT_SUCCESS or not int(res[1]) in [500, 502, 503, 504] or attempt == 1:
			break
		progress.emit("Google is busy; trying again...")
		if not await _pause(4.0 * wait_scale, mine):
			if mine == _run:
				running = false
			return _stopped()
	if mine != _run or not is_inside_tree():
		running = false
		return _stopped()
	running = false
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return _fail("Google took too long to answer. Try again." if int(res[0]) == HTTPRequest.RESULT_TIMEOUT else "Couldn't reach Google.", "offline")
	var code := int(res[1])
	var body_text := (res[3] as PackedByteArray).get_string_from_utf8()
	var reply: Variant = JSON.parse_string(body_text)
	var what := ApiErrors.kind(code, body_text)
	if what == ApiErrors.NETWORK:
		# (Google's "User location is not supported", or a block page: not the key's fault.)
		return _fail("Google is refusing connections from this network or region (a VPN can cause this). Try another network or another helper.", "provider")
	if what == ApiErrors.CREDIT:
		return _fail("Google says this account has no credit left or needs billing set up.", "quota")
	if code == 429:
		if _web:
			gemini_search_off = true
			return _fail("Gemini can't search the web on this key right now (Google says its limit is used up; a free key may not include search).", "quota")
		return _fail("Gemini is at this key's limit right now.", "quota")
	if what == ApiErrors.KEY:
		return _fail("Google didn't accept the Gemini key: it is wrong, expired or switched off (Settings > AI).", "key")
	if code != 200 or not reply is Dictionary:
		var said := str(reply.get("error", {}).get("message", "")).replace(key, "[key]").substr(0, 220) if reply is Dictionary and reply.get("error") is Dictionary else ""
		if code == 404:
			return _fail("Google has no Gemini model called \"%s\" for this key (Settings > Light World)." % model, "other")
		var known := preload("res://scripts/home/helper_http.gd").explain(said)
		return _fail(known if known != "" else "Gemini said no (HTTP %d)." % code, "other")
	var finish := str(((reply.get("candidates", [{}]) as Array).front() as Dictionary).get("finishReason", "")) if reply.get("candidates") is Array and not (reply.candidates as Array).is_empty() and (reply.candidates as Array).front() is Dictionary else ""
	if finish in ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII"]:
		return _fail("Gemini declined this lookup (Google's safety check). Nothing changed.", "refusal")
	if finish == "MAX_TOKENS":
		return _fail("Gemini's answer was cut off before it ended. Try with fewer photos.", "shape")
	searched += gemini_searches(reply)
	var raw: Variant = _json_in(gemini_text(reply))
	if not raw is Dictionary:
		return _fail("Gemini's answer wasn't in the shape Polox needs.", "shape")
	return _ok(raw)


## How many Google searches grounded Gemini's first candidate (its groundingMetadata), 0 if none ran.
static func gemini_searches(reply: Dictionary) -> int:
	for cand in reply.get("candidates", []):
		if cand is Dictionary and cand.get("groundingMetadata") is Dictionary:
			var queries: Variant = cand.groundingMetadata.get("webSearchQueries", [])
			return (queries as Array).size() if queries is Array else 0
		break
	return 0


## Gemini's answer text: the first candidate's parts, leaving out its thinking (thinking can hold braces
## that would spoil reading the JSON).
static func gemini_text(reply: Dictionary) -> String:
	var text := ""
	for cand in reply.get("candidates", []):
		if not cand is Dictionary or not cand.get("content") is Dictionary:
			break
		for part in (cand.content as Dictionary).get("parts", []):
			if part is Dictionary and not bool(part.get("thought", false)):
				text += str(part.get("text", ""))
		break
	return text
