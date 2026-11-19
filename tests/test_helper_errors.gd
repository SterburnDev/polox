extends "res://tests/test_case.gd"
## 1.27 helper API fixes. The Claude lookup: Anthropic's errors said safely (a provider's own words can
## repeat the prompt, an address included, so they are never shown), a busy or overloaded API retried,
## the server-side refusal fallback asked for and dropped once if the account doesn't have it, a
## paused search continued, a refusal or a cut-off answer said as such. OpenAI and compatible
## endpoints: why an answer was incomplete, and a compatible server that can't return strict JSON
## schemas asked for JSON mode, then plain text. Servers here are fakes on 127.0.0.1.

const Research := preload("res://scripts/home/research.gd")
const Http := preload("res://scripts/home/helper_http.gd")
const Tell := preload("res://scripts/home/tell_polox.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const PRIVATE := "12 Example Lane, private details"


func test_claude_errors_are_safe_and_say_what_to_do() -> void:
	var private := {"type": "error", "error": {"type": "invalid_request_error", "message": "messages.0: " + PRIVATE}}
	for code in [400, 401, 402, 403, 404, 413, 429, 500, 529]:
		var e: Dictionary = Research.claude_error(code, private, PackedStringArray())
		check(str(e.error) != "", "HTTP %d has a message" % code)
		check(not str(e.error).contains(PRIVATE), "HTTP %d never shows the provider's words" % code)
	eq(Research.claude_error(401, {}, PackedStringArray()).why, "key")
	eq(Research.claude_error(402, {}, PackedStringArray()).why, "quota", "billing")
	check(bool(Research.claude_error(529, {}, PackedStringArray()).get("retry", false)), "overloaded: worth another go")
	var limited: Dictionary = Research.claude_error(429, {}, PackedStringArray(["retry-after: 7"]))
	check(bool(limited.retry) and is_equal_approx(float(limited.wait), 7.0), "rate limited: waits as long as asked")
	var beta: Dictionary = Research.claude_error(400, {"error": {"type": "invalid_request_error", "message": "Unexpected value(s) `server-side-fallback-2026-07-01` for the `anthropic-beta` header."}}, PackedStringArray())
	check(bool(beta.get("drop_fallback", false)), "an account without the fallback beta: plain requests instead")
	var key_echo: Dictionary = Research.claude_error(400, {"error": {"message": "bad sk-ant-FAKEKEY"}}, PackedStringArray(), "sk-ant-FAKEKEY")
	check(not str(key_echo.error).contains("FAKEKEY"), "the key never shows")


func test_the_claude_lookup_retries_continues_and_reports_a_refusal() -> void:
	fresh_save_root()
	GameState.settings["light_world"] = {"claude_api_key": "FAKE-claude-key"}
	var bodies: Array = []
	var replies := [
		[400, {"type": "error", "error": {"type": "invalid_request_error", "message": "Unexpected value(s) `server-side-fallback-2026-07-01` for the `anthropic-beta` header."}}],
		[529, {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}],
		[200, {"stop_reason": "pause_turn", "content": [{"type": "server_tool_use", "id": "srvtoolu_1", "name": "web_search", "input": {"query": "library"}}]}],
		[200, {"stop_reason": "refusal", "content": [], "stop_details": {"type": "refusal", "category": "cyber"}}],
	]
	var stub: Node = preload("res://scripts/phone/http_server.gd").new()
	tree.root.add_child(stub)
	stub.api_prefix = "/v1/"
	stub.api_handler = func(req: Dictionary, _ip: String) -> PackedByteArray:
		bodies.append(JSON.parse_string((req.body as PackedByteArray).get_string_from_utf8()))
		var r: Array = replies[mini(bodies.size() - 1, replies.size() - 1)]
		return HttpUtil.json_response(int(r[0]), r[1])
	listen_on_free_port(func(p: int) -> String: return stub.start(p, "127.0.0.1"), "the fake provider")
	Research.claude_url = "http://127.0.0.1:%d/v1/messages" % stub.port
	Research.claude_fallback_ok = true
	var r: Node = Research.new()
	tree.root.add_child(r)
	r._prompt = "Read this made-up note."
	r.wait_scale = 0.02   # (the wait before the busy retry, shortened)
	r._web = true
	r._cleaner = func(raw: Dictionary) -> Dictionary: return raw
	var result: Dictionary = await r._claude_api()
	eq(bodies.size(), 4, "fallback dropped, busy retried, paused search continued, then the answer")
	eq(str(bodies[0].get("fallbacks", "")), "default", "the server-side refusal fallback is asked for")
	check(not bodies[1].has("fallbacks"), "and dropped for an account that doesn't have it")
	eq(str(bodies[0].output_config.effort), Research.CLAUDE_EFFORT, "effort is explicit (Opus 5.5 would use medium)")
	eq(str(bodies[0].thinking.type), "adaptive")
	eq((bodies[3].messages as Array).size(), 2, "the paused turn went back as it was, with no extra message")
	eq(str(bodies[3].messages[1].role), "assistant")
	check(not result.ok and str(result.why) == "refusal", "a refusal is said as one: " + str(result.get("error", "")))
	check(str(result.error).contains("declined"))
	# A cut-off answer.
	bodies.clear()
	replies.clear()
	replies.append([200, {"stop_reason": "max_tokens", "content": [{"type": "text", "text": "{\"changes\": ["}]}])
	var cut: Dictionary = await r._claude_api()
	check(not cut.ok and str(cut.error).contains("cut off"), "a cut-off answer is said as one: " + str(cut.get("error", "")))
	# A good one.
	replies[0] = [200, {"stop_reason": "end_turn", "content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": "{\"changes\":[]}"}]}]
	r._web = false
	var good: Dictionary = await r._claude_api()
	check(good.ok, "a finished answer is read from its text blocks: " + str(good.get("error", "")))
	Research.claude_url = ""
	Research.claude_fallback_ok = true
	r.queue_free()
	stub.stop()
	stub.queue_free()
	await frames(2)


func test_incomplete_answers_say_why() -> void:
	var cut := {"status": "incomplete", "incomplete_details": {"reason": "max_output_tokens"}, "output": []}
	var r := Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify(cut).to_utf8_buffer()])
	check(not r.ok and str(r.error).contains("cut off"), str(r.error))
	var filtered := {"status": "incomplete", "incomplete_details": {"reason": "content_filter"}, "output": []}
	eq(Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify(filtered).to_utf8_buffer()]).why, "refusal")
	var length := {"choices": [{"finish_reason": "length", "message": {"content": "{"}}]}
	check(str(Http.response("compatible", [HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify(length).to_utf8_buffer()]).error).contains("cut off"))
	var missing := Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 404, [], '{"error":{"message":"The model `gpt-6-lunar` does not exist or you do not have access to it."}}'.to_utf8_buffer()], "", "gpt-6-lunar")
	check(str(missing.error).contains("gpt-6-lunar") and str(missing.why) == "model", "a wrong model ID is named: " + str(missing.error))


func test_a_compatible_server_without_strict_schemas_is_asked_for_json() -> void:
	var formats: Array = []
	var job := Http.new()
	tree.root.add_child(job)
	job.transport = func(request: Dictionary) -> Array:
		var rf: Variant = request.body.get("response_format")
		formats.append(str(rf.type) if rf is Dictionary else "none")
		if rf is Dictionary and str(rf.type) == "json_schema":
			return [HTTPRequest.RESULT_SUCCESS, 400, [], '{"error":{"message":"response_format json_schema is not supported by this model"}}'.to_utf8_buffer()]
		return [HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify({"choices": [{"finish_reason": "stop", "message": {"content": "{\"changes\":[]}"}}]}).to_utf8_buffer()]
	var result: Dictionary = await job.run("compatible", {"compatible_url": "http://127.0.0.1:11434/v1", "compatible_model": "local"}, "fixture", Tell.WORDS_SCHEMA, false)
	check(result.ok, "the second way works: " + str(result.get("error", "")))
	eq(formats, ["json_schema", "json_object"], "strict schema first, then JSON mode")
	job.queue_free()
	await frames(2)
