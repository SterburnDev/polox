extends "res://tests/test_case.gd"
const Http := preload("res://scripts/home/helper_http.gd")
const Tell := preload("res://scripts/home/tell_polox.gd")


func test_explicit_provider_payload_and_capabilities() -> void:
	var request := Http.request_data("openai", {"openai_model": "chosen-model", "openai_key": "synthetic-key"}, "Only reviewed text", Tell.WORDS_SCHEMA, false)
	check(request.ok)
	eq(request.url, "https://api.openai.com/v1/responses")
	eq(request.body.input, "Only reviewed text")
	check(not request.body.store and not request.body.has("tools"), "reading text uses no search or stored API response")
	check(request.body.text.format.strict, "structured response required")
	var props: Dictionary = request.body.text.format.schema.properties
	check("null" in props.questions.type, "optional fields represented as nullable")
	check(not request.body.text.format.schema.additionalProperties, "closed object schema")
	check(not Http.request_data("openai", {}, "", {}, false).ok, "no invented model")
	var compatible := {"compatible_url": "http://localhost:11434/v1", "compatible_model": "local-model"}
	check(Http.request_data("compatible", compatible, "", Tell.WORDS_SCHEMA, false).ok, "local optional key supported")
	eq(Http.request_data("compatible", compatible, "", {}, true).why, "capability", "no falsely grounded research")
	compatible.compatible_url = "https://user:password@example.test/v1"
	check(not Http.request_data("compatible", compatible, "", {}, false).ok, "embedded credentials refused")


func test_http_errors_are_precise_and_private() -> void:
	for status in [401, 403, 429, 400, 500]:
		var result := Http.response("openai", [HTTPRequest.RESULT_SUCCESS, status, [], '{"error":{"message":"private home details"}}'.to_utf8_buffer()])
		check(not result.ok)
		check(not JSON.stringify(result).contains("private home details"), "provider error body never displayed")
	eq(Http.response("openai", [HTTPRequest.RESULT_TIMEOUT, 0, [], PackedByteArray()]).why, "timeout")
	eq(Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 403, [], '{"error":{"code":"unsupported_country_region_territory","message":"Country, region, or territory not supported"}}'.to_utf8_buffer()]).why, "provider", "a region refusal isn't blamed on the key")
	eq(Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 403, [], '{"error":{"message":"missing scope"}}'.to_utf8_buffer()]).why, "key")
	eq(Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 429, [], '{"error":{"code":"insufficient_quota"}}'.to_utf8_buffer()]).why, "quota")
	# OpenAI's answer for an empty balance, as it really arrives.
	var broke := Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 429, [], '{"error":{"type":"insufficient_quota","code":"credit_balance_exhausted","message":"You have no credits remaining."}}'.to_utf8_buffer()])
	eq(broke.why, "quota", "no credit left isn't a rate limit")
	check(str(broke.error).contains("no API credit"), "and the player is told to add credit, not to wait")
	eq(Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 429, [], '{"error":{"code":"rate_limit_exceeded","message":"Rate limit reached"}}'.to_utf8_buffer()]).why, "rate_limit")
	check(not Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 200, [], "{}".to_utf8_buffer()]).ok, "HTTP 200 alone is insufficient")
	var reply := {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": '{"changes":[],"questions":null}'}]}]}
	var good := Http.response("openai", [HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify(reply).to_utf8_buffer()])
	check(good.ok and not good.value.has("questions"), "optional nulls normalize before shared validation")
	eq(Tell.validate_helper(good.value), "")


func test_cancelled_transport_cannot_return_late_success() -> void:
	var job := Http.new()
	tree.root.add_child(job)
	job.transport = func(_request):
		job.cancel()
		await frames(2)
		return [HTTPRequest.RESULT_SUCCESS, 200, [], '{"choices":[{"finish_reason":"stop","message":{"content":"{}"}}]}'.to_utf8_buffer()]
	var result: Dictionary = await job.run("compatible", {"compatible_url": "http://localhost:11434/v1", "compatible_model": "test"}, "fixture", Tell.WORDS_SCHEMA, false)
	eq(result.why, "cancelled")
	job.queue_free()
	await frames(2)
