extends "res://tests/test_case.gd"
## Phase 37, the Light World's helper works: the question and the answer's shape reach Claude Code whole
## (Windows used to strip every quote, so Claude Code refused the shape before it even looked); Polox
## checks Claude Code's sign-in first and offers Claude's own sign-in window; when a helper can't answer
## the selected helper fails, no other recipient receives private data; an older Claude Code gets the Opus alias;
## Tell Polox's reading (no tools) arrives with its empty tool list intact; Gemini's thinking is left out of
## its answer. A stand-in Claude Code (tests/fixtures/fake_claude) answers: never the real one, never the network.

const Research := preload("res://scripts/home/research.gd")
const ResearchPrompt := preload("res://scripts/home/research_prompt.gd")
const ProcArgs := preload("res://scripts/core/proc_args.gd")
const SurveyScreen := preload("res://scripts/home/survey_screen.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")

const FIXTURE := "res://tests/fixtures/home_research_madeup.json"
const WORDS := "res://tests/fixtures/words_madeup.json"
## An address with everything Windows' command line could mangle: quotes, backslashes (one before a quote,
## some at the end), a tab, a newline, and the characters that make Godot add quotes.
const TRICKY := "12 \"Example\" Lane\\ & Co (Testville)\t#3\nC:\\Old\\\"Road\\\\"

var _log := ""


func test_external_api_key_refusal_does_not_claim_the_account_is_signed_out() -> void:
	fresh_save_root()
	var previous := Research.sign_in_state
	Research.sign_in_state = 1
	var r := Research.new()
	r._result_text = "ERROR: Invalid API key · Fix external API key"
	var result := r._finish_claude_code()
	check(not bool(result.ok), "the live CLI's refusal is handled")
	eq(str(result.why), "key", "the refused credential is classified precisely")
	check(str(result.error).contains("external API key"), "the message points to the refused credential")
	eq(Research.sign_in_state, 1, "an external key error does not erase the account's sign-in status")
	Research.sign_in_state = previous
	r.free()


func _stand_in(mode: String) -> void:
	Research.exe_override = OS.get_executable_path()
	Research.exe_prefix = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://tests/fixtures/fake_claude"), "-s", "res://fake_claude.gd", "--"])
	Research.sign_in_state = -1
	Research.gemini_search_off = false
	Research.sign_in_opened = 0
	_log = ProjectSettings.globalize_path("res://tests/.tmp_save").path_join("fake_claude_%s.json" % current)
	DirAccess.make_dir_recursive_absolute(_log.get_base_dir())
	if FileAccess.file_exists(_log):
		DirAccess.remove_absolute(_log)
	OS.set_environment("FAKE_CLAUDE", mode)
	OS.set_environment("FAKE_CLAUDE_LOG", _log)
	# This transport fixture promises a schema-conforming provider response. The
	# legacy home fixture also contains privacy-filtering cases tested separately.
	var answer_path := _log + ".answer.json"
	var answer: Dictionary = preload("res://scripts/home/helper_json.gd").project(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)), ResearchPrompt.response_schema())
	preload("res://scripts/core/json_util.gd").write_json(answer_path, answer)
	OS.set_environment("FAKE_CLAUDE_ANSWER", answer_path)


func _done() -> void:
	Research.exe_override = ""
	Research.exe_prefix = PackedStringArray()
	Research.sign_in_state = -1
	Research.gemini_search_off = false
	OS.set_environment("FAKE_CLAUDE", "")


## What the stand-in received: {"args": [...], "problems": [...]}.
func _received() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_log)) if FileAccess.file_exists(_log) else null
	return d if d is Dictionary else {}


func _research(av: Dictionary) -> Node:
	fresh_save_root()
	GameState.settings["light_world"] = {}
	GameState.settings["ai"] = {"preset": "mock"}
	var r: Node = Research.new()
	r.available_override = av
	tree.root.add_child(r)
	return r


func _wait(r: Node, seconds: float = 40.0) -> Dictionary:
	var out := {"res": {}}
	r.finished.connect(func(res): out.res = res, CONNECT_ONE_SHOT)
	var t := Time.get_ticks_msec()
	while (out.res as Dictionary).is_empty() and Time.get_ticks_msec() - t < int(seconds * 1000.0):
		await frames(2)
	return out.res


func test_arguments_reach_claude_code_whole() -> void:
	# The escaping itself: a quote, backslashes before a quote and at the end, a tab, an empty argument.
	eq(ProcArgs.win_arg("say \"hi\""), "say \\\"hi\\\"", "a quote is escaped")
	eq(ProcArgs.win_arg("a\\\"b c"), "a\\\\\\\"b c", "backslashes before a quote are doubled")
	eq(ProcArgs.win_arg("C:\\x y\\"), "C:\\x y\\\\", "trailing backslashes are doubled when Godot adds quotes")
	eq(ProcArgs.win_arg("C:\\xy\\"), "C:\\xy\\", "and left alone when it doesn't")
	eq(ProcArgs.win_arg(""), "\"\"", "an empty argument survives")
	eq(ProcArgs.win_arg("a\tb"), "a    b", "a tab can't split it")
	eq(ProcArgs.for_os(PackedStringArray(["x\"y"]), false), PackedStringArray(["x\"y"]), "untouched off Windows")
	# The real thing: a lookup through the stand-in, with an address that has all of it.
	_stand_in("ok")
	var r := _research({"claude_code": true})
	var lines: Array = []
	r.progress.connect(func(l): lines.append(l))
	r.start("claude_code", TRICKY, {"floors": 2})
	var res := await _wait(r)
	var got := _received()
	var args: Array = got.get("args", [])
	check((got.get("problems", ["no log"]) as Array).is_empty(), "the stand-in found nothing mangled: %s" % str(got.get("problems", "no log")))
	var p := args.find("-p")
	check(p >= 0 and str(args[p + 1]) == ResearchPrompt.question(TRICKY.replace("\t", "    "), {"floors": 2}), "the question arrives exactly as written")
	var js := args.find("--json-schema")
	# Update 9: Claude Code gets the stricter response schema (enums, bounds, no extra fields): the one answers are checked against.
	var closed := preload("res://scripts/home/helper_json.gd").closed(ResearchPrompt.response_schema())
	check(js >= 0 and JSON.parse_string(str(args[js + 1])) is Dictionary and JSON.stringify(JSON.parse_string(str(args[js + 1]))) == JSON.stringify(JSON.parse_string(JSON.stringify(closed))), "the answer's shape arrives as valid, identical JSON")
	check(not JSON.parse_string(str(args[js + 1])).get("additionalProperties", true), "and closed: no fields beyond the schema")
	var m := args.find("--model")
	check(m >= 0 and str(args[m + 1]) == "claude-opus-5-5", "the newest Opus by name")
	var tl := args.find("--tools")
	check(tl >= 0 and str(args[tl + 1]) == "WebSearch,WebFetch", "web search and reading only")
	check(bool(res.get("ok", false)), "the answer is read: %s" % str(res.get("error", "")))
	check((res.get("research", {}).get("facts", []) as Array).size() >= 5, "with its facts")
	check(lines.has("Checking Claude Code's sign-in...") and lines.has("Reading the county assessor's record..."), "progress shows: %s" % str(lines))
	eq(Research.sign_in_state, 1, "and Claude Code counts as signed in")
	eq(r.calls, 1, "one run")
	r.queue_free()
	_done()


func test_signed_out_claude_code_is_said_plainly_without_changing_recipient() -> void:
	_stand_in("signed_out")
	var r := _research({"claude_code": true})
	r.start("claude_code", "12 Example Lane, Testville", {})
	var res := await _wait(r)
	check(not bool(res.get("ok", true)), "no answer without a sign-in")
	eq(str(res.get("why", "")), "signin", "and it says why")
	eq(r.calls, 0, "the lookup never started (the sign-in check said no first)")
	eq(Research.sign_in_state, 0, "remembered as not signed in")
	check(Research.advice(res).contains("Sign in to Claude"), "and where to sign in: %s" % Research.advice(res))
	r.queue_free()
	# Expired mid-run must not resend private data to other configured providers.
	_stand_in("expired")
	r = _research({"claude_code": true, "claude_api": true, "gemini": true})
	var lines: Array = []
	r.progress.connect(func(l): lines.append(l))
	r.start("claude_code", "12 Example Lane, Testville", {})
	res = await _wait(r)
	eq(r.tried, PackedStringArray(["claude_code"]), "only the explicitly selected recipient")
	check(not lines.any(func(l): return str(l).contains("instead")), "no automatic provider handover")
	eq(str(res.get("why", "")), "signin", "the selected provider's actual failure is retained")
	r.queue_free()
	_done()


func test_an_older_claude_code_gets_the_opus_alias() -> void:
	_stand_in("old_model")
	var r := _research({"claude_code": true})
	r.start("claude_code", "12 Example Lane, Testville", {})
	var res := await _wait(r, 60.0)
	check(bool(res.get("ok", false)), "it answered the second time: %s" % str(res.get("error", "")))
	eq(r.calls, 2, "asked by name, then by alias")
	var args: Array = _received().get("args", [])
	var m := args.find("--model")
	check(m >= 0 and str(args[m + 1]) == "opus", "the alias the second time")
	r.queue_free()
	_done()


func test_tell_polox_reading_keeps_its_empty_tool_list() -> void:
	_stand_in("ok")
	OS.set_environment("FAKE_CLAUDE_ANSWER", ProjectSettings.globalize_path(WORDS))
	var r := _research({"claude_code": true})
	var plan := {"floors": [{"name": "Upstairs", "level": 1, "rooms": [{"id": "r1", "name": "My room", "kind": "bedroom"}]}]}
	r.start_words("claude_code", "My room's walls are \"light blue\" now, and there's a plant.", plan)
	var res := await _wait(r)
	var got := _received()
	var args: Array = got.get("args", [])
	check((got.get("problems", ["no log"]) as Array).is_empty(), "nothing mangled: %s" % str(got.get("problems", "no log")))
	var tl := args.find("--tools")
	check(tl >= 0 and str(args[tl + 1]) == "" and str(args[tl + 2]) == "--allowedTools", "no tools at all, said as an empty list")
	check(not str(args).contains("12 Example"), "no address")
	check(bool(res.get("ok", false)), "the reading comes back: %s" % str(res.get("error", "")))
	r.queue_free()
	_done()


func test_the_sign_in_window_and_waiting_for_it() -> void:
	_stand_in("ok")
	check(Research.open_sign_in(), "Claude's own sign-in opens")
	eq(Research.sign_in_opened, 1, "(the stand-in counts it instead of opening a window)")
	var r := _research({"claude_code": true})
	var ok: bool = await r.wait_for_sign_in(0.5)
	check(ok, "Polox notices once Claude Code is signed in")
	eq(Research.state_note("claude_code", {"claude_code": true}), "ready", "and says it's ready")
	Research.sign_in_state = 0
	eq(Research.state_note("claude_code", {"claude_code": true}), "sign in first", "or that it needs signing in")
	eq(Research.state_note("claude_code", {"claude_code": false}), "not on this computer", "or isn't here")
	Research.gemini_search_off = true
	eq(Research.state_note("gemini", {"gemini": true}), "can't search on this key", "and when Gemini can't search")
	r.queue_free()
	_done()


func test_the_survey_and_settings_offer_the_sign_in() -> void:
	_stand_in("signed_out")
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	GameState.settings["reduce_motion"] = true
	GameState.settings["light_world"] = {"helper": "claude_code"}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var sc: Control = SurveyScreen.new()
	sc.available = {"claude_code": true, "none": true}
	main.toast_layer().add_child(sc)
	await frames(2)
	await _check_until(sc)
	eq(Research.sign_in_state, 0, "the Survey asked Claude Code whether it's signed in (no)")
	sc.helper = "claude_code"
	sc.answers = {"address": "12 Example Lane, Testville", "radius": 250}
	sc._build_consent()
	await frames(2)
	var sign: Button = sc.find_child("SignInClaude", true, false)
	check(sign != null and sign.visible, "SIGN IN TO CLAUDE on the last screen")
	check(sc.find_child("LookItUp", true, false) != null, "with LOOK IT UP still there")
	var opts: Array = sc._helper_options()
	check(opts.any(func(o): return str(o[1]).contains("SIGN IN FIRST")), "the helper choice says so too")
	if sign:
		sign.pressed.emit()
		await frames(2)
		eq(Research.sign_in_opened, 1, "the sign-in window was asked for")
	sc.queue_free()
	# Settings > Light World says how Claude Code stands, with the sign-in beside it.
	Research.sign_in_state = 0
	var tab: Control = load("res://scripts/ui/settings_light_tab.gd").new()
	main.open_panel(tab)
	await frames(3)
	var state: Label = tab.find_child("ClaudeCodeState", true, false)
	check(state != null and state.text.contains("sign in first"), "Settings: %s" % (state.text if state else "missing"))
	check(tab.find_child("SignInClaude", true, false) != null and tab.find_child("CheckClaude", true, false) != null, "Sign in to Claude and Check")
	main._close_all_panels()
	main.queue_free()
	await frames(2)
	_done()


func _check_until(sc: Control) -> void:
	var t := Time.get_ticks_msec()
	while Research.sign_in_state == -1 and Time.get_ticks_msec() - t < 20000:
		await frames(2)
	await frames(2)
	if sc.get("_area") == null:
		return


func test_gemini_thinking_is_left_out() -> void:
	var reply := {"candidates": [{"content": {"parts": [{"text": "Let me think {about the {braces}", "thought": true}, {"text": "{\"facts\": [], \"sources\": [], \"address_found\": false}"}]}}]}
	var text := Research.gemini_text(reply)
	check(not text.contains("think"), "the thinking is skipped")
	check(Research._json_in(text) is Dictionary, "so the answer reads as JSON")
	eq(Research.gemini_text({}), "", "an empty reply is empty")


func test_selected_recipient_is_the_entire_chain() -> void:
	eq(Research.chain("gemini", {"claude_code": true, "claude_api": false, "gemini": true}), PackedStringArray(["gemini"]), "availability does not authorize another provider")
	eq(Research.chain("none", {"claude_code": true}), PackedStringArray(), "nobody means no requests")
	eq(Research.chain("invalid", {"claude_code": true}), PackedStringArray(), "unknown selections fail closed")
