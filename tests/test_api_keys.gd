extends "res://tests/test_case.gd"
## API keys and what providers answer. A key is told apart by its mark and is only ever kept for (and
## sent to) the service it belongs to; a refused key, an empty balance, a refused network and a real
## rate limit are four different answers, each said plainly and none retried by mistake; a rate limit
## waits what the provider asked (1 to 60 s) and the wait can be stopped; keys stay out of logs,
## exports and crash reports. Servers here are fakes on 127.0.0.1; every key is made up.
## Tags: [AI_HELPER] [PERSONAL_DATA]

const KeyFormat := preload("res://scripts/ai/key_format.gd")
const ApiErrors := preload("res://scripts/ai/api_errors.gd")
const Presets := preload("res://scripts/ai/presets.gd")
const Http := preload("res://scripts/home/helper_http.gd")
const Research := preload("res://scripts/home/research.gd")
const Tell := preload("res://scripts/home/tell_polox.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const CrashLog := preload("res://scripts/core/crash_log.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")

# Made up, in each provider's shape, and put together when the tests run: nothing written in this
# file is shaped like a key (the public-source check and key scanners read every file).
const F := "FAKEfake"
var GROQ := "gsk_" + F.repeat(6) + "0000"
var GEMINI_OLD := "AIza" + F.repeat(4) + "000"
var GEMINI_NEW := "AQ." + F.repeat(6)
var OPENAI := "sk-" + "proj-" + F.repeat(5)
var OPENAI_OLD := "sk-" + F.repeat(6)
var ANTHROPIC := "sk-" + "ant-api03-" + F.repeat(4) + "FAKE"
var OPENROUTER := "sk-" + "or-v1-" + F.repeat(5)
var VENICE := "VENICE-" + "INFERENCE-KEY-" + F.repeat(3)
const UNMARKED := "v3n1c3FAKEunmarked0123456789abcdefghijkl"

var main: Node


func _stub(prefix: String, handler: Callable) -> Node:
	var stub: Node = preload("res://scripts/phone/http_server.gd").new()
	tree.root.add_child(stub)
	stub.api_prefix = prefix
	stub.api_handler = handler
	listen_on_free_port(func(p: int) -> String: return stub.start(p, "127.0.0.1"), "the fake server")
	# (Earlier suites' requests don't count against these: the limiter starts empty.)
	AIClient.limiter._stamps.clear()
	AIClient.limiter.blocked_until = 0.0
	return stub


func _done(stub: Node) -> void:
	AIClient.configure({"preset": "mock"})
	AIClient.backoff_base_s = 1.5
	stub.stop()
	stub.queue_free()
	await frames(2)


func _json(code: int, data: Variant, headers: Dictionary = {}) -> PackedByteArray:
	return HttpUtil.response(code, JSON.stringify(data).to_utf8_buffer(), "application/json", headers)


const HELLO := [{"role": "user", "content": "hi"}]
const GOOD := {"choices": [{"message": {"content": "{\"segments\":[]}"}}]}


# --- Whose key it is ------------------------------------------------------------------------------

func test_a_key_is_told_apart_by_its_mark() -> void:
	for pair in [[GROQ, "groq"], [GEMINI_OLD, "gemini"], [GEMINI_NEW, "gemini"], [OPENAI, "openai"], [OPENAI_OLD, "openai"],
			[ANTHROPIC, "anthropic"], [OPENROUTER, "openrouter"], [VENICE, "venice"], [UNMARKED, ""], ["", ""]]:
		eq(KeyFormat.kind(str(pair[0])), str(pair[1]), "whose key %s... is" % str(pair[0]).left(8))
	eq(KeyFormat.kind("  " + GROQ + "\n"), "groq", "spaces around it don't matter")
	eq(KeyFormat.kind("SK-ANT-shouting"), "", "marks are exact (a key is case-sensitive)")
	# Typed letter by letter, a Claude key is never called OpenAI's on the way.
	for typed in ["s", "sk", "sk-", "sk-a", "sk-an", "sk-ant", "sk-o", "sk-or"]:
		eq(KeyFormat.kind(typed), "", "\"%s\" could still become anything" % typed)
	eq(KeyFormat.kind("sk-ant-"), "anthropic")
	eq(KeyFormat.kind("sk-p"), "openai")
	eq(KeyFormat.kind("sk-ab"), "openai", "no longer on the way to sk-ant-")
	# An Anthropic key starts "sk-" too: it is never taken for an OpenAI one, nor an OpenRouter one.
	check(not KeyFormat.fits(ANTHROPIC, "openai") and not KeyFormat.fits(OPENROUTER, "openai"), "sk-ant- and sk-or- aren't OpenAI's")
	check(KeyFormat.fits(OPENAI, "openai") and KeyFormat.fits(OPENAI_OLD, "openai") and KeyFormat.fits(ANTHROPIC, "anthropic"))
	# A key without a known mark belongs wherever the player put it (Venice publishes no format).
	for slot in ["groq", "gemini", "venice", "openai", "anthropic", "custom"]:
		check(KeyFormat.fits(UNMARKED, slot), "an unmarked key is the player's call (%s)" % slot)
	# A custom server takes anything; a named provider never takes another's.
	for key in [GROQ, GEMINI_NEW, OPENAI, ANTHROPIC, OPENROUTER, VENICE]:
		check(KeyFormat.fits(key, "custom"), "a custom server takes any key")
	check(not KeyFormat.fits(GEMINI_NEW, "groq") and not KeyFormat.fits(GROQ, "gemini") and not KeyFormat.fits(OPENAI, "venice")
		and not KeyFormat.fits(GROQ, "venice") and not KeyFormat.fits(OPENAI, "anthropic"), "a named provider never takes another's key")


func test_a_pasted_key_is_tidied() -> void:
	eq(KeyFormat.clean("  " + GROQ + " \r\n"), GROQ, "spaces and the line break")
	eq(KeyFormat.clean("\"" + OPENAI + "\""), OPENAI, "quotes")
	eq(KeyFormat.clean("Bearer " + ANTHROPIC), ANTHROPIC, "Bearer")
	eq(KeyFormat.clean("export GEMINI_API_KEY=\"" + GEMINI_NEW + "\""), GEMINI_NEW, "a line from a terminal")
	eq(KeyFormat.clean("$env:OPENAI_API_KEY = '" + OPENAI + "'"), OPENAI, "or from PowerShell")
	eq(KeyFormat.clean(GEMINI_OLD.left(20) + "\n" + GEMINI_OLD.substr(20)), GEMINI_OLD, "a key wrapped onto two lines")
	eq(KeyFormat.clean(UNMARKED + "=="), UNMARKED + "==", "a key's own = signs stay")
	eq(KeyFormat.clean(""), "")


func test_a_wrong_key_says_whose_it_is_and_where_it_goes() -> void:
	eq(KeyFormat.mismatch(GROQ, "groq"), "")
	eq(KeyFormat.mismatch(UNMARKED, "gemini"), "")
	var gem_in_groq := KeyFormat.mismatch(GEMINI_NEW, "groq")
	check(gem_in_groq.contains("Google Gemini key") and gem_in_groq.contains("never sent to Groq") and gem_in_groq.contains("Choose Google Gemini"), gem_in_groq)
	var claude_in_gemini := KeyFormat.mismatch(ANTHROPIC, "gemini")
	check(claude_in_gemini.contains("Claude (Anthropic) key") and claude_in_gemini.contains("Helper setup"), claude_in_gemini)
	var openai_in_venice := KeyFormat.mismatch(OPENAI, "venice")
	check(openai_in_venice.contains("OpenAI key") and openai_in_venice.contains("Custom server"), openai_in_venice)
	var openai_in_claude := KeyFormat.mismatch(OPENAI, "anthropic")
	check(openai_in_claude.contains("OpenAI API key box"), openai_in_claude)
	var groq_in_openai := KeyFormat.mismatch(GROQ, "openai")
	check(groq_in_openai.contains("Settings > AI") and groq_in_openai.contains("Groq"), groq_in_openai)
	for said in [gem_in_groq, claude_in_gemini, openai_in_venice, openai_in_claude, groq_in_openai]:
		check(not said.contains("FAKE"), "the key itself is never repeated")
	eq(KeyFormat.chat_slot(GEMINI_NEW), "gemini")
	eq(KeyFormat.chat_slot(OPENAI), "", "no chat provider of its own")


func test_a_key_is_never_sent_to_another_provider() -> void:
	# Filed under the wrong provider (an older version, or a hand-edited settings file).
	var wrong := {"preset": "groq", "keys": {"groq": GEMINI_NEW}}
	eq(str(Presets.resolve(wrong).api_key), "", "Groq is never given a Google key, even one filed under it")
	AIClient.configure(wrong)
	check(AIClient.is_mock(), "so Groq counts as having no key")
	check(Presets.migrate_keys(wrong), "loading the settings puts it right")
	eq(str(wrong.keys.get("gemini", "")), GEMINI_NEW, "the key moves to Gemini")
	check(not wrong.keys.has("groq"), "and is gone from Groq")
	check(not Presets.migrate_keys(wrong), "once")
	# A key with no chat provider of its own is kept for a custom server (the player's own address).
	var openai := {"preset": "venice", "keys": {"venice": OPENAI}}
	Presets.migrate_keys(openai)
	eq(openai.keys, {"custom": OPENAI}, "an OpenAI key under Venice moves to Custom server")
	# Its own provider already has a key: nothing is overwritten, and it still isn't sent.
	var taken := {"preset": "gemini", "keys": {"gemini": GROQ, "groq": "gsk_another_one_already_here"}}
	check(not Presets.migrate_keys(taken), "nothing is replaced")
	eq(str(Presets.resolve(taken).api_key), "", "and Google still never gets the Groq key")
	# The old single key, by its mark.
	for case in [[OPENAI, "groq", "custom"], [ANTHROPIC, "gemini", "custom"], [VENICE, "groq", "venice"], [GROQ, "venice", "groq"],
			[UNMARKED, "venice", "venice"], [OPENAI, "custom", "custom"], [GEMINI_NEW, "custom", "gemini"]]:
		eq(Presets.guess_owner(str(case[0]), str(case[1])), str(case[2]), "%s... chosen with %s" % [str(case[0]).left(8), case[1]])
	# The home helpers refuse a key that is another service's before anything is sent.
	var to_openai := Http.request_data("openai", {"openai_model": "m", "openai_key": ANTHROPIC}, "p", Tell.WORDS_SCHEMA, false)
	check(not to_openai.ok and str(to_openai.why) == "key" and not str(to_openai.error).contains("FAKE"), "an Anthropic key is never sent to OpenAI: " + str(to_openai.error))
	check(Http.request_data("compatible", {"compatible_url": "http://localhost:1/v1", "compatible_model": "m", "compatible_key": ANTHROPIC}, "p", Tell.WORDS_SCHEMA, false).ok, "a compatible endpoint takes whatever key you give it")
	GameState.settings["ai"] = {"preset": "mock", "keys": {"gemini": OPENAI}}
	eq(Research.gemini_key(), "", "the Gemini helper never uses an OpenAI key")
	GameState.settings["ai"] = {"preset": "mock", "keys": {"gemini": GEMINI_NEW}}
	eq(Research.gemini_key(), GEMINI_NEW)
	GameState.settings["ai"] = {"preset": "mock"}
	AIClient.configure({"preset": "mock"})


func test_settings_turns_a_wrong_key_away_and_offers_its_provider() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	GameState.settings["ai"] = {"preset": "groq", "keys": {}}
	GameState.settings["light_world"] = {}
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)
	var s: Control = SettingsScreen.new()
	s.main = main
	s.start_on = "AI"
	main.open_panel(s)
	await frames(3)
	var note: Label = s.find_child("KeyNote", true, false)
	var fix: Button = s.find_child("KeyFix", true, false)
	if check(note != null and fix != null and s._key != null, "Settings > AI has the key box and its note"):
		check(not note.is_visible_in_tree(), "no note until there's something to say")
		# A Google key pasted while Groq is chosen (with the quotes it was copied in).
		s._key.text = "\"" + GEMINI_NEW + "\"\n"
		s._key.text_changed.emit(s._key.text)
		await frames(1)
		eq(str(GameState.settings.ai.keys.get("groq", "")), "", "it is not kept for Groq")
		check(not FileAccess.get_file_as_string(SaveManager.settings_path()).contains(GEMINI_NEW), "nor saved anywhere yet")
		check(note.is_visible_in_tree() and note.text.contains("Google Gemini key"), "the note says whose it is: " + note.text)
		check(fix.visible and fix.text.contains("Google Gemini"), "and offers its provider: " + fix.text)
		fix.pressed.emit()
		await frames(1)
		eq(str(GameState.settings.ai.get("preset", "")), "gemini", "one tap chooses Google Gemini")
		eq(str(GameState.settings.ai.keys.get("gemini", "")), GEMINI_NEW, "with the key, tidied")
		eq(str(GameState.settings.ai.keys.get("groq", "")), "", "Groq still has none")
		check(not note.is_visible_in_tree(), "and the note is gone")
		# The right kind of key for the chosen provider is simply kept.
		s._key.text = GEMINI_OLD
		s._key.text_changed.emit(s._key.text)
		eq(str(GameState.settings.ai.keys.get("gemini", "")), GEMINI_OLD)
		# An OpenAI key has no chat provider of its own: turned away, with where it goes, no button.
		s._key.text = OPENAI
		s._key.text_changed.emit(s._key.text)
		eq(str(GameState.settings.ai.keys.get("gemini", "")), "", "an OpenAI key is not kept for Gemini")
		check(note.text.contains("OpenAI key") and not fix.visible, "and the note says where it goes: " + note.text)
	main.go_back()
	await frames(2)
	# Helper setup: an OpenAI key in the Claude box.
	var setup: Control = load("res://scripts/ui/settings_helpers_panel.gd").new()
	main.open_panel(setup)
	setup.setup_helpers()
	await frames(2)
	var claude: LineEdit = setup.find_child("ClaudeKey", true, false)
	var openai: LineEdit = setup.find_child("OpenAIKey", true, false)
	var compatible: LineEdit = setup.find_child("CompatibleKey", true, false)
	if check(claude != null and openai != null and compatible != null, "Helper setup has its key boxes"):
		claude.text_changed.emit(OPENAI)
		eq(str(GameState.settings.light_world.get("claude_api_key", "")), "", "an OpenAI key is not kept as the Claude key")
		check(str(setup.result_line.text).contains("OpenAI API key box"), "and it says where it goes: " + str(setup.result_line.text))
		claude.text_changed.emit(" " + ANTHROPIC + " ")
		eq(str(GameState.settings.light_world.get("claude_api_key", "")), ANTHROPIC, "the Claude key is kept, tidied")
		eq(str(setup.result_line.text), "", "and the note goes")
		openai.text_changed.emit(ANTHROPIC)
		eq(str(GameState.settings.light_world.get("openai_key", "")), "", "a Claude key is not kept as the OpenAI key")
		openai.text_changed.emit(OPENAI)
		eq(str(GameState.settings.light_world.get("openai_key", "")), OPENAI)
		compatible.text_changed.emit(OPENROUTER)
		eq(str(GameState.settings.light_world.get("compatible_key", "")), OPENROUTER, "a compatible endpoint takes any key")
	main._close_all_panels()
	main.queue_free()
	GameState.settings["ai"] = {"preset": "mock"}
	GameState.settings["light_world"] = {}
	GameState.save_settings()
	await frames(2)


# --- What a provider's "no" means -----------------------------------------------------------------

func test_each_kind_of_no_is_told_apart() -> void:
	var cases := [
		# A refused, expired or switched-off key.
		[401, '{"error":{"message":"Incorrect API key provided: sk-proj-****. You can find your API key at ...","code":"invalid_api_key"}}', "key"],
		[401, '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}', "key"],
		[400, '{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}', "key"],
		[400, '{"error":{"code":400,"message":"API key expired. Please renew the API key.","status":"INVALID_ARGUMENT"}}', "key"],
		[403, '{"error":{"message":"This key lacks permission for the model."}}', "key"],
		# Nothing left to spend.
		[429, '{"error":{"type":"insufficient_quota","code":"credit_balance_exhausted","message":"You have no credits remaining."}}', "credit"],
		[429, '{"error":{"message":"You exceeded your current quota, please check your plan and billing details.","type":"insufficient_quota","code":"insufficient_quota"}}', "credit"],
		[402, '{"error":"Insufficient USD or Diem balance to complete request"}', "credit"],
		[400, '{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."}}', "credit"],
		# The provider refuses this network or place, whatever the key.
		[403, '{"error":{"message":"Access denied. Please check your network settings."}}', "network"],
		[403, "<!DOCTYPE html><html><head><title>Attention Required! | Cloudflare</title>", "network"],
		[403, '{"error":{"code":"unsupported_country_region_territory","message":"Country, region, or territory not supported"}}', "network"],
		[403, '{"error":{"type":"forbidden","message":"Request not allowed"}}', "network"],
		[400, '{"error":{"code":400,"message":"User location is not supported for the API use.","status":"FAILED_PRECONDITION"}}', "network"],
		# A real rate limit.
		[429, '{"error":{"message":"Rate limit reached for model in organization org-x on requests per min (RPM): Limit 3, Used 3. Please try again in 20s.","type":"requests","code":"rate_limit_exceeded"}}', "rate_limit"],
		[429, '[{"error":{"code":429,"message":"You exceeded your current quota, please check your plan and billing details.","status":"RESOURCE_EXHAUSTED"}}]', "rate_limit"],
		[429, '{"type":"error","error":{"type":"rate_limit_error","message":"This request would exceed your organization rate limit"}}', "rate_limit"],
		[429, "", "rate_limit"],
		# Not one of the four: the caller's to explain.
		[400, '{"error":{"message":"Unsupported parameter: max_tokens"}}', ""],
		[404, '{"error":{"message":"The model does not exist"}}', ""],
		[500, "", ""],
		[503, '{"error":{"message":"The region us-east is overloaded"}}', ""],
	]
	for c in cases:
		eq(ApiErrors.kind(int(c[0]), str(c[1])), str(c[2]), "HTTP %d %s" % [c[0], str(c[1]).left(70)])


func test_chats_say_each_kind_plainly_and_retry_only_a_rate_limit() -> void:
	AIClient.configure({"preset": "groq", "keys": {"groq": GROQ}})
	var ok := HTTPRequest.RESULT_SUCCESS
	var key := AIClient._interpret(ok, 401, PackedStringArray(), ('{"error":{"message":"Invalid API Key %s"}}' % GROQ).to_utf8_buffer())
	check(not key.retry and str(key.error).contains("didn't accept the API key") and str(key.error).contains("expired"), "a refused key: " + str(key.error))
	check(not str(key.error).contains("FAKE"), "without repeating it")
	var expired := AIClient._interpret(ok, 400, PackedStringArray(), '{"error":{"code":400,"message":"API key expired. Please renew the API key.","status":"INVALID_ARGUMENT"}}'.to_utf8_buffer())
	check(not expired.retry and str(expired.error).contains("didn't accept the API key"), "an expired key (Google's 400): " + str(expired.error))
	for body in ['{"error":{"type":"insufficient_quota","code":"credit_balance_exhausted","message":"You have no credits remaining."}}', ""]:
		var code := 429 if body != "" else 402
		var broke := AIClient._interpret(ok, code, PackedStringArray(["Retry-After: 20"]), body.to_utf8_buffer())
		check(not broke.retry and str(broke.error).contains("no credit left") and not broke.has("retry_after"), "HTTP %d, no credit: said so, never waited out" % code)
		eq(AIClient.limiter.wait_time(AIClient._now()), 0.0, "and nobody else is made to wait for it")
	var blocked := AIClient._interpret(ok, 403, PackedStringArray(), '{"error":{"type":"forbidden","message":"Request not allowed"}}'.to_utf8_buffer())
	check(not blocked.retry and str(blocked.error).contains("this network") and not str(blocked.error).contains("API key"), "a refused network isn't blamed on the key: " + str(blocked.error))
	var place := AIClient._interpret(ok, 400, PackedStringArray(), '{"error":{"code":400,"message":"User location is not supported for the API use."}}'.to_utf8_buffer())
	check(not place.retry and str(place.error).contains("this network"), "nor a place the provider doesn't serve: " + str(place.error))
	var limited := AIClient._interpret(ok, 429, PackedStringArray(["retry-after: 12"]), '{"error":{"message":"Rate limit reached"}}'.to_utf8_buffer())
	check(limited.retry and is_equal_approx(float(limited.retry_after), 12.0) and str(limited.error).contains("too fast"), "a real rate limit waits what was asked")
	AIClient.limiter.blocked_until = 0.0
	var unsaid := AIClient._interpret(ok, 429, PackedStringArray(), PackedByteArray())
	check(unsaid.retry and is_equal_approx(float(unsaid.retry_after), AIClient.UNSAID_WAIT_S), "one that doesn't say how long gets a short wait")
	AIClient.limiter.blocked_until = 0.0
	AIClient.configure({"preset": "mock"})


func test_retry_after_is_read_and_kept_within_bounds() -> void:
	eq(ApiErrors.retry_after(PackedStringArray(["Retry-After: 7"])), 7.0)
	eq(ApiErrors.retry_after(PackedStringArray(["content-type: application/json", "RETRY-AFTER:  2.5 "])), 2.5, "any case, any spacing")
	eq(ApiErrors.retry_after(PackedStringArray(["Retry-After: 0"])), 1.0, "never less than a second")
	eq(ApiErrors.retry_after(PackedStringArray(["Retry-After: 3600"])), 60.0, "never more than a minute")
	eq(ApiErrors.retry_after(PackedStringArray(["Retry-After: -5"])), -1.0, "a wait before now was never said")
	eq(ApiErrors.retry_after(PackedStringArray(["retry-after: 20", "retry-after-ms: 1500"])), 1.5, "the exact one wins")
	eq(ApiErrors.retry_after(PackedStringArray(["Retry-After: soon"])), -1.0, "nonsense is not a wait")
	eq(ApiErrors.retry_after(PackedStringArray(["x-ratelimit-limit-requests: 30"])), -1.0, "not said: the caller decides")
	eq(ApiErrors.retry_after(PackedStringArray()), -1.0)
	# A date instead of seconds.
	var now := float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 21, "hour": 7, "minute": 28, "second": 0}))
	eq(ApiErrors.retry_after(PackedStringArray(["Retry-After: Wed, 21 Oct 2026 07:28:30 GMT"]), "", now), 30.0, "a date is a wait until then")
	eq(ApiErrors.retry_after(PackedStringArray(["Retry-After: Wed, 21 Oct 2026 09:00:00 GMT"]), "", now), 60.0)
	eq(ApiErrors.retry_after(PackedStringArray(["Retry-After: Wed, 21 Oct 2026 07:00:00 GMT"]), "", now), 1.0, "a date already past")
	# Google says it in the answer.
	var google := '{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay": "34s"}]}}'
	eq(ApiErrors.retry_after(PackedStringArray(), google), 34.0, "Gemini's retryDelay")
	eq(ApiErrors.retry_after(PackedStringArray(["Retry-After: 5"]), google), 5.0, "the header first")


func test_only_a_real_rate_limit_is_tried_again() -> void:
	var hits := {"n": 0}
	var answer := {"code": 401, "body": {"error": {"message": "Invalid API Key"}}, "headers": {}}
	var stub := _stub("/v1/", func(_req: Dictionary, _ip: String) -> PackedByteArray:
		hits.n += 1
		return _json(int(answer.code), answer.body, answer.headers))
	var base := "http://127.0.0.1:%d/v1" % stub.port
	AIClient.backoff_base_s = 0.05
	var cases := [
		[401, {"error": {"message": "Invalid API Key"}}, "API key"],
		[400, {"error": {"code": 400, "message": "API key expired. Please renew the API key.", "status": "INVALID_ARGUMENT"}}, "API key"],
		[400, {"error": {"code": 400, "message": "User location is not supported for the API use.", "status": "FAILED_PRECONDITION"}}, "this network"],
		[429, {"error": {"type": "insufficient_quota", "code": "credit_balance_exhausted", "message": "You have no credits remaining."}}, "no credit left"],
		[403, {"error": {"message": "Access denied. Please check your network settings."}}, "this network"],
	]
	for i in cases.size():
		answer.code = cases[i][0]
		answer.body = cases[i][1]
		answer.headers = {"Retry-After": "1"}   # (even when the answer carries one)
		hits.n = 0
		# (A key of its own each time: a new provider or key starts with a clean slate.)
		AIClient.configure({"preset": "custom", "base_url": base, "model": "m", "timeout_s": 5, "keys": {"custom": "FAKE-custom-key-%d" % i}})
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = await AIClient.chat(HELLO, {})
		check(not r.ok and str(r.error).contains(str(cases[i][2])), "HTTP %d says: %s" % [answer.code, str(r.error)])
		eq(hits.n, 1, "HTTP %d (%s) is asked once, never again" % [answer.code, cases[i][2]])
		check(Time.get_ticks_msec() - t0 < 900, "and at once, without a wait")
	# A real rate limit: one wait of what was asked, then the answer.
	answer.code = 429
	answer.body = {"error": {"message": "Rate limit reached"}}
	answer.headers = {"Retry-After": "1"}
	hits.n = 0
	AIClient.configure({"preset": "custom", "base_url": base, "model": "m", "timeout_s": 5, "keys": {"custom": "FAKE-custom-key-limited"}})
	var seen := PackedStringArray()
	var watch := func(state: String, message: String) -> void:
		if state == "waiting":
			seen.append(message)
		if state == "waiting" and int(answer.code) == 429:
			answer.code = 200
			answer.body = GOOD
			answer.headers = {}
	AIClient.status_changed.connect(watch)
	var started := Time.get_ticks_msec()
	var after: Dictionary = await AIClient.chat(HELLO, {})
	AIClient.status_changed.disconnect(watch)
	check(after.ok, "after the wait the answer arrives: " + str(after.get("error", "")))
	eq(hits.n, 2, "one retry")
	var waited := (Time.get_ticks_msec() - started) / 1000.0
	check(waited >= 0.9 and waited < 5.0, "it waited the second it was asked to (%.2f s)" % waited)
	check(not seen.is_empty() and seen[0].contains("1s"), "and said so while waiting: " + str(seen))
	await _done(stub)


func test_a_wait_can_be_stopped_and_ends_when_the_key_changes() -> void:
	var hits := {"n": 0}
	var limited := {"on": true}
	var stub := _stub("/v1/", func(_req: Dictionary, _ip: String) -> PackedByteArray:
		hits.n += 1
		if limited.on:
			return _json(429, {"error": {"message": "Rate limit reached"}}, {"Retry-After": "600"})
		return _json(200, GOOD))
	var base := "http://127.0.0.1:%d/v1" % stub.port
	AIClient.configure({"preset": "custom", "base_url": base, "model": "m", "timeout_s": 5, "keys": {"custom": "FAKE-custom-key-one"}})
	# 1. Stop, during the wait a rate limit asked for (ten minutes, kept to one).
	var box := {"first": {}, "second": {}}
	var ask := func(slot: String) -> void: box[slot] = await AIClient.chat(HELLO, {})
	ask.call("first")
	ask.call("second")   # (queued behind the first)
	var t0 := Time.get_ticks_msec()
	while AIClient.state != "waiting" and Time.get_ticks_msec() - t0 < 5000:
		await frames(1)
	eq(AIClient.state, "waiting", "the chat is waiting out the rate limit")
	check(AIClient.status_message.contains("60s") or AIClient.status_message.contains("59s"), "for no more than a minute: " + AIClient.status_message)
	eq(hits.n, 1)
	AIClient.cancel()
	t0 = Time.get_ticks_msec()
	while (box.first.is_empty() or box.second.is_empty()) and Time.get_ticks_msec() - t0 < 3000:
		await frames(1)
	check(bool(box.first.get("cancelled", false)) and not bool(box.first.get("ok", true)), "Stop ends the wait at once: " + str(box.first))
	check(bool(box.second.get("cancelled", false)), "and the chat queued behind it")
	eq(hits.n, 1, "nothing more was sent")
	check(not AIClient.busy(), "nothing is left pending")
	check(AIClient.state != "error", "and stopping isn't shown as an error")
	# The queue still works afterwards (the provider's own wait still stands until it is over).
	AIClient.limiter.blocked_until = 0.0
	limited.on = false
	var next: Dictionary = await AIClient.chat(HELLO, {})
	check(next.ok, "the next chat goes through: " + str(next.get("error", "")))
	# 2. Waiting on one key's rate limit, then the key is changed in Settings: the wait is over.
	limited.on = true
	hits.n = 0
	box.first = {}
	ask.call("first")
	t0 = Time.get_ticks_msec()
	while AIClient.state != "waiting" and Time.get_ticks_msec() - t0 < 5000:
		await frames(1)
	eq(AIClient.state, "waiting")
	limited.on = false
	AIClient.configure({"preset": "custom", "base_url": base, "model": "m", "timeout_s": 5, "keys": {"custom": "FAKE-custom-key-two"}})
	t0 = Time.get_ticks_msec()
	while box.first.is_empty() and Time.get_ticks_msec() - t0 < 3000:
		await frames(1)
	check(bool(box.first.get("ok", false)), "the new key is tried at once, not after the old one's wait: " + str(box.first))
	eq(hits.n, 2)
	# 3. Stop while the provider is still answering.
	var served := {"done": false}
	var slow := _stub("/v1/", func(_req: Dictionary, _ip: String) -> PackedByteArray:
		await tree.create_timer(1.0).timeout
		served.done = true
		return _json(200, GOOD))
	AIClient.configure({"preset": "custom", "base_url": "http://127.0.0.1:%d/v1" % slow.port, "model": "m", "timeout_s": 10})
	box.first = {}
	ask.call("first")
	await frames(20)
	eq(AIClient.state, "thinking")
	AIClient.cancel()
	t0 = Time.get_ticks_msec()
	while box.first.is_empty() and Time.get_ticks_msec() - t0 < 2000:
		await frames(1)
	check(bool(box.first.get("cancelled", false)), "Stop ends a request in flight too: " + str(box.first))
	check(not AIClient.busy())
	check(not served.done, "(the fake provider hadn't answered yet)")
	while not served.done:
		await frames(1)
	await frames(2)
	slow.stop()
	slow.queue_free()
	await _done(stub)


func test_listing_models_says_why_it_came_back_empty() -> void:
	var answer := {"code": 401, "body": {"error": {"message": "Invalid API Key"}}}
	var stub := _stub("/v1/", func(_req: Dictionary, _ip: String) -> PackedByteArray:
		return _json(int(answer.code), answer.body))
	AIClient.configure({"preset": "custom", "base_url": "http://127.0.0.1:%d/v1" % stub.port, "model": "m", "keys": {"custom": "FAKE-custom-key"}})
	eq((await AIClient.list_models()).size(), 0)
	check(AIClient.models_note.contains("API key"), "a refused key is said: " + AIClient.models_note)
	answer.code = 404
	answer.body = {"error": "no such route"}
	eq((await AIClient.list_models()).size(), 0)
	eq(AIClient.models_note, "", "a server that just has no list isn't an error")
	answer.code = 200
	answer.body = {"data": [{"id": "one"}, {"id": "two"}]}
	eq((await AIClient.list_models()).size(), 2)
	eq(AIClient.models_note, "")
	await _done(stub)


# --- The home helpers -----------------------------------------------------------------------------

func test_the_helpers_tell_the_same_four_apart() -> void:
	var ok := HTTPRequest.RESULT_SUCCESS
	eq(Http.response("openai", [ok, 400, [], '{"error":{"message":"API key expired. Please renew the API key."}}'.to_utf8_buffer()]).why, "key", "an expired key said with a 400")
	eq(Http.response("openai", [ok, 402, [], '{"error":"Insufficient balance"}'.to_utf8_buffer()]).why, "quota", "402 is no credit")
	eq(Http.response("compatible", [ok, 403, [], "<html>blocked</html>".to_utf8_buffer()]).why, "provider", "a block page is the network, not the key")
	var limited := Http.response("openai", [ok, 429, PackedStringArray(["Retry-After: 9"]), '{"error":{"message":"Rate limit reached"}}'.to_utf8_buffer()])
	check(str(limited.why) == "rate_limit" and is_equal_approx(float(limited.retry_after), 9.0), "a rate limit carries the wait it was asked for")
	check(not Http.response("openai", [ok, 429, [], '{"error":{"code":"insufficient_quota"}}'.to_utf8_buffer()]).has("retry_after"), "no credit carries none")
	# Anthropic.
	var blocked: Dictionary = Research.claude_error(403, null, PackedStringArray(), "", "<!DOCTYPE html><title>Just a moment...</title>")
	check(str(blocked.why) == "provider" and str(blocked.error).contains("network") and not bool(blocked.get("retry", false)), "Anthropic behind a block page: " + str(blocked.error))
	var not_allowed: Dictionary = Research.claude_error(403, {"error": {"type": "forbidden", "message": "Request not allowed"}}, PackedStringArray(), "", '{"error":{"type":"forbidden","message":"Request not allowed"}}')
	eq(str(not_allowed.why), "provider", "Anthropic refusing a region isn't the key's fault")
	eq(str(Research.claude_error(403, {"error": {"type": "permission_error", "message": "Your API key does not have permission to use the specified resource."}}, PackedStringArray()).why), "key")
	var low: Dictionary = Research.claude_error(400, {"error": {"type": "invalid_request_error", "message": "Your credit balance is too low to access the Anthropic API."}}, PackedStringArray())
	check(str(low.why) == "quota" and str(low.error).contains("no credit left") and not bool(low.get("retry", false)), "Anthropic's empty balance (a 400): " + str(low.error))
	var busy: Dictionary = Research.claude_error(429, {}, PackedStringArray(["retry-after: 900"]))
	check(bool(busy.retry) and bool(busy.asked) and is_equal_approx(float(busy.wait), 60.0), "Anthropic's rate limit: what it asked, within a minute")
	check(not bool(Research.claude_error(529, {}, PackedStringArray()).asked), "overloaded without a wait: Polox picks one")


func test_a_helper_waits_out_a_rate_limit_once_and_cancel_ends_the_wait() -> void:
	var config := {"compatible_url": "http://localhost:11434/v1", "compatible_model": "test"}
	var good := [HTTPRequest.RESULT_SUCCESS, 200, [], '{"choices":[{"finish_reason":"stop","message":{"content":"{\\"changes\\":[]}"}}]}'.to_utf8_buffer()]
	var limit_said := [HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(["Retry-After: 2"]), '{"error":{"message":"Rate limit reached"}}'.to_utf8_buffer()]
	var limit_unsaid := [HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(), '{"error":{"message":"Rate limit reached"}}'.to_utf8_buffer()]
	var calls := {"n": 0}
	# Asked to wait: waited once, then the answer.
	var job := Http.new()
	tree.root.add_child(job)
	job.wait_scale = 0.05
	job.transport = func(_request):
		calls.n += 1
		return limit_said if calls.n == 1 else good
	var result: Dictionary = await job.run("compatible", config, "fixture", Tell.WORDS_SCHEMA, false)
	check(bool(result.ok), "after the wait it is asked again: " + str(result.get("error", "")))
	eq(calls.n, 2)
	# Still limited after the wait: said, not tried a third time.
	calls.n = 0
	job.transport = func(_request):
		calls.n += 1
		return limit_said
	result = await job.run("compatible", config, "fixture", Tell.WORDS_SCHEMA, false)
	check(not bool(result.ok) and str(result.why) == "rate_limit", "still limited: said so")
	eq(calls.n, 2, "one retry, no more")
	# Not told how long: nothing is guessed, the player decides.
	calls.n = 0
	job.transport = func(_request):
		calls.n += 1
		return limit_unsaid
	result = await job.run("compatible", config, "fixture", Tell.WORDS_SCHEMA, false)
	eq(str(result.why), "rate_limit")
	eq(calls.n, 1, "no Retry-After, no retry")
	job.queue_free()
	# Cancel during the wait.
	var waiting := Http.new()
	tree.root.add_child(waiting)
	calls.n = 0
	waiting.transport = func(_request):
		calls.n += 1
		return [HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(["Retry-After: 60"]), PackedByteArray()]
	var box := {"result": {}}
	var go := func() -> void: box.result = await waiting.run("compatible", config, "fixture", Tell.WORDS_SCHEMA, false)
	go.call()
	await frames(10)
	check(box.result.is_empty(), "it is waiting")
	waiting.cancel()
	await frames(3)
	eq(str(box.result.get("why", "")), "cancelled", "Cancel ends the wait")
	eq(calls.n, 1, "and nothing more is sent")
	waiting.queue_free()
	await frames(2)


# --- Keys stay where they belong ------------------------------------------------------------------

func test_no_key_reaches_a_log_an_export_or_a_crash_report() -> void:
	var root := fresh_save_root()
	preload("res://scripts/core/starter_content.gd").create_world("Keys", "Sam")
	GameState.load_world()
	GameState.settings["ai"] = {"preset": "mock", "keys": {"groq": GROQ, "gemini": GEMINI_NEW, "venice": UNMARKED, "custom": "FAKE-custom-server-key"}}
	GameState.settings["light_world"] = {"claude_api_key": ANTHROPIC, "openai_key": OPENAI, "compatible_key": "FAKE-compatible-endpoint-key"}
	GameState.save_settings()
	var stored := KeyFormat.stored(GameState.settings)
	eq(stored.size(), 7, "every key in the settings is known")
	# Every stored key, and anything shaped like a key that isn't stored (OpenRouter's here, an old
	# Google one), typed into a chat.
	var typed := "my keys: " + " ".join(stored) + " and " + OPENROUTER + " and " + GEMINI_OLD + " ok?"
	var kept := ChatLog.redact(typed)
	check(not kept.contains("FAKE"), "no key survives: " + kept)
	check(kept.begins_with("my keys: ") and kept.ends_with(" ok?"), "the words around them stay")
	eq(ChatLog.redact("the task-oriented, risk-averse AQ. and sk- of it"), "the task-oriented, risk-averse AQ. and sk- of it", "ordinary words are left alone")
	ChatLog.append("mochi", "home", "user", typed)
	check(not FileAccess.get_file_as_string(ChatLog.log_path("mochi")).contains("FAKE"), "nor reaches the chat log")
	# A line written before its key was known is cleaned on the way out of an export.
	var f := FileAccess.open(ChatLog.log_path("mochi"), FileAccess.READ_WRITE)
	f.seek_end()
	f.store_line(JSON.stringify({"id": "p1", "ts": "2026-11-01T10:00:00", "room": "home", "character": "mochi", "role": "user", "text": "old line " + VENICE, "emotion": ""}))
	f.close()
	var exported := ChatLog.export({})
	eq(exported.size(), 2)
	for path in exported:
		var text := FileAccess.get_file_as_string(path)
		check(text.contains("old line") and not text.contains("FAKE"), "the export has the chat, not the keys (%s)" % path.get_file())
	# Crash reports: an error line that happens to hold a key is kept without it.
	var recorder := CrashLog.Recorder.new()
	var no_traces: Array[ScriptBacktrace] = []
	recorder._log_error("_send", "res://scripts/x.gd", 12, "request failed", "Authorization: Bearer " + OPENAI + " refused", false, Logger.ERROR_TYPE_ERROR, no_traces)
	var lines := recorder.take()
	check(lines.size() == 1 and str(lines[0]).contains("refused") and not str(lines[0]).contains("FAKE"), "the flight recorder: " + str(lines))
	var report := CrashLog.as_report({"errors": ["12:00:00 x.gd:1 f() key " + ANTHROPIC + " seen"], "where": {}})
	check(not JSON.stringify(report).contains("FAKE") and JSON.stringify(report).contains("seen"), "a report sent to the PC")
	var arrived: Dictionary = preload("res://scripts/net/report_sink.gd").sanitize_report({"v": 1, "log": ["line with " + GROQ]})
	check(not JSON.stringify(arrived).contains("FAKE"), "and one arriving from a phone")
	# The keys are in settings.json (and its own backup copies), and in no other file.
	var holders := PackedStringArray()
	var all := PackedStringArray()
	_files(root, all)
	for path in all:
		var text := FileAccess.get_file_as_bytes(path).get_string_from_ascii()   # (keys are plain ASCII; pictures aren't text)
		for key in stored:
			if text.contains(key) and not path.get_file() in holders:
				holders.append(path.get_file())
	for name in holders:
		check(name.begins_with("settings.json"), "a key is in %s" % name)
	check("settings.json" in holders, "(they are in settings.json, where they belong)")
	GameState.settings["ai"] = {"preset": "mock"}
	GameState.settings["light_world"] = {}
	GameState.save_settings()


func _files(dir: String, out: PackedStringArray) -> void:
	for d in DirAccess.get_directories_at(dir):
		_files(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))
