extends Node
## OpenAI Responses and explicitly configured Chat Completions-compatible services.
## Tags: [AI_HELPER]
const Json := preload("res://scripts/home/helper_json.gd")
const ApiErrors := preload("res://scripts/ai/api_errors.gd")
const KeyFormat := preload("res://scripts/ai/key_format.gd")
var cancelled := false
var wait_scale := 1.0   # (tests shrink the rate-limit wait)
var transport: Callable
var _http: HTTPRequest


static func strict_schema(schema: Dictionary) -> Dictionary:
	var out := schema.duplicate(true)
	if out.get("properties") is Dictionary:
		var required: Array = out.get("required", [])
		for key in out.properties:
			var child := strict_schema(out.properties[key])
			if not key in required:
				var types: Variant = child.get("type", "string")
				child["type"] = types.duplicate() if types is Array else [types]
				child.type.append("null")
				if child.has("enum"):
					child.enum.append(null)
			out.properties[key] = child
		out["required"] = out.properties.keys()
		out["additionalProperties"] = false
	if out.get("items") is Dictionary:
		out.items = strict_schema(out.items)
	return out


static func without_nulls(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value:
			if value[key] != null:
				out[key] = without_nulls(value[key])
		return out
	if value is Array:
		return value.map(func(item): return without_nulls(item))
	return value


## format: "schema" (strict JSON schema), "json" (JSON mode) or "none" (the prompt alone asks for JSON):
## a compatible server that rejects one is asked with the next (run()).
static func request_data(provider: String, config: Dictionary, prompt: String, schema: Dictionary, web: bool, format: String = "schema") -> Dictionary:
	var official := provider == "openai"
	var model := str(config.get("openai_model" if official else "compatible_model", "")).strip_edges()
	var key := str(config.get("openai_key" if official else "compatible_key", "")).strip_edges()
	if model == "":
		return fail("Choose the provider's model ID in Settings > Light World.", "model")
	if official and key == "":
		return fail("Add an OpenAI API key. ChatGPT subscription access does not supply API credits.", "key")
	if official and not KeyFormat.fits(key, "openai"):
		return fail(KeyFormat.mismatch(key, "openai"), "key")   # (another service's key is never sent to OpenAI)
	if not official and web:
		return fail("This compatible endpoint has no verified web-search tool. Use it for Tell Polox, or use the manual research prompt with sources.", "capability")
	var base := "https://api.openai.com/v1" if official else str(config.get("compatible_url", "")).strip_edges().trim_suffix("/")
	if not (base.begins_with("https://") or base.begins_with("http://")) or base.contains("@") or base.contains("?") or base.contains("#") or base.contains("\n") or base.contains("\r"):
		return fail("Set a valid HTTP(S) base URL without credentials, query or fragment.", "configuration")
	if key.contains("\n") or key.contains("\r"):
		return fail("The API key contains invalid characters.", "key")
	var headers := PackedStringArray(["Content-Type: application/json"])
	if key != "":
		headers.append("Authorization: Bearer " + key)
	var shape := {"type": "json_schema", "name": "polox_home", "strict": true, "schema": strict_schema(schema)}
	var body := {"model": model}
	if official:
		# Reasoning and web searches count toward the output limit: room for both, and the answer.
		body.merge({"input": prompt, "store": false, "max_output_tokens": 32000, "text": {"format": shape}})
		if web:
			body["tools"] = [{"type": "web_search"}]
	else:
		body.merge({"messages": [{"role": "user", "content": prompt}], "max_tokens": 16000})
		if format == "schema":
			body["response_format"] = {"type": "json_schema", "json_schema": {"name": "polox_home", "strict": true, "schema": shape.schema}}
		elif format == "json":
			body["response_format"] = {"type": "json_object"}
	return {"ok": true, "url": base + ("/responses" if official else "/chat/completions"), "headers": headers, "body": body}


static func fail(message: String, why: String) -> Dictionary:
	return {"ok": false, "error": message, "why": why, "value": {}}


## A provider's error words in a safe explanation: what kind of problem, and what to do. The words
## themselves are never shown (they can repeat the prompt, an address included).
static func explain(said: String) -> String:
	var s := said.to_lower()
	if s.contains("model") and (s.contains("not exist") or s.contains("not found") or s.contains("does not have access") or s.contains("unknown model")):
		return "The provider doesn't offer that model to this key. Check the model ID in Settings > Light World."
	if s.contains("context") and (s.contains("length") or s.contains("too long") or s.contains("maximum")):
		return "The request is too long for this model. Try a model with a bigger context."
	if s.contains("billing") or s.contains("credit") or s.contains("quota") or s.contains("payment"):
		return "The provider says the account needs credit or billing set up."
	if s.contains("response_format") or s.contains("json_schema") or s.contains("structured"):
		return "This model or endpoint can't return structured JSON."
	if s.contains("rate") and s.contains("limit"):
		return "The provider is rate limited. Wait before retrying."
	return ""


## The provider's own error words (its "error.message"), short, with any key taken out: kept for
## deciding what to retry, never shown.
static func provider_said(parsed: Dictionary, key: String = "") -> String:
	var said := ""
	if parsed.ok and parsed.value is Dictionary:
		var e: Variant = parsed.value.get("error")
		said = str(e.get("message", "")) if e is Dictionary else (str(e) if e is String else "")
	if key != "":
		said = said.replace(key, "[key]")
	return said.substr(0, 220)


static func response(provider: String, result: Array, key: String = "", model: String = "") -> Dictionary:
	if result.size() < 4:
		return fail("The request returned no usable response.", "offline")
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return fail("The request timed out. Retry when ready." if int(result[0]) == HTTPRequest.RESULT_TIMEOUT else "Couldn't reach the selected provider.", "timeout" if int(result[0]) == HTTPRequest.RESULT_TIMEOUT else "offline")
	var status := int(result[1])
	var parsed := Json.parse((result[3] as PackedByteArray).get_string_from_utf8())
	if status != 200:
		var said := provider_said(parsed, key)
		var raw := (result[3] as PackedByteArray).get_string_from_utf8()
		# The same four kinds of "no" as in chats (api_errors.gd), each with what to do about it.
		match ApiErrors.kind(status, raw):
			ApiErrors.NETWORK:
				return fail("The provider is refusing connections from this network or region (a VPN can cause this). Try another network or another helper.", "provider")
			ApiErrors.KEY:
				return fail("The provider refused this API key or its permissions (wrong, expired or switched off).", "key")
			ApiErrors.CREDIT:
				# OpenAI's real answer for an empty balance is 429 with type "insufficient_quota" and
				# code "credit_balance_exhausted" (found by the live check).
				return fail("The account has no API credit left. Add credit on the provider's billing page (a ChatGPT subscription doesn't include API credit).", "quota")
			ApiErrors.RATE_LIMIT:
				var limited := fail("The provider is rate limited. Wait before retrying.", "rate_limit")
				limited["retry_after"] = ApiErrors.retry_after(PackedStringArray(result[2]), raw)   # -1: it didn't say
				return limited
		if status == 404 and said.to_lower().contains("model"):
			return fail("The provider has no model called \"%s\" for this key. Check the model ID in Settings > Light World." % model, "model")
		if status in [500, 502, 503, 504]:
			return fail("The provider is having trouble right now (HTTP %d). Try again in a little while." % status, "provider")
		var known := explain(said)
		var r := fail(known if known != "" else "The provider refused the request (HTTP %d). Check model, endpoint and structured-output support." % status,
			"capability" if status in [400, 404, 422] else "provider")
		var low := said.to_lower()
		# (Only whether the server refused the JSON format, for run()'s fallback: never its words.)
		r["format_refused"] = low.contains("response_format") or low.contains("json_schema") or low.contains("structured") or low.contains("json")
		return r
	if not parsed.ok:
		return fail("The provider returned malformed JSON.", "shape")
	var reply: Dictionary = parsed.value
	var text := ""
	var searched := 0
	if provider == "openai":
		if str(reply.get("status", "")) != "completed" or not reply.get("output") is Array:
			var why := str(reply.get("incomplete_details", {}).get("reason", "")) if reply.get("incomplete_details") is Dictionary else ""
			if why == "max_output_tokens":
				return fail("The answer was cut off before it ended (too long). Nothing has been applied.", "incomplete")
			if why == "content_filter":
				return fail("The provider declined this request. Nothing has been applied.", "refusal")
			return fail("The provider did not complete the response%s. Nothing has been applied." % ((" (" + why + ")") if why != "" else ""), "incomplete")
		for item in reply.output:
			if item is Dictionary and str(item.get("type", "")) == "web_search_call":
				searched += 1   # the web search really ran (research is only grounded if it did)
			if not item is Dictionary or not item.get("content") is Array:
				continue
			for part in item.content:
				if part is Dictionary and str(part.get("type", "")) == "refusal":
					return fail("The provider declined this request.", "refusal")
				if part is Dictionary and str(part.get("type", "")) == "output_text":
					text += str(part.get("text", ""))
	else:
		if not reply.get("choices") is Array or reply.choices.is_empty() or not reply.choices[0] is Dictionary:
			return fail("The endpoint returned no message.", "shape")
		var choice: Dictionary = reply.choices[0]
		if str(choice.get("finish_reason", "")) == "length":
			return fail("The answer was cut off before it ended (too long). Nothing has been applied.", "incomplete")
		if str(choice.get("finish_reason", "")) == "content_filter":
			return fail("The endpoint declined this request. Nothing has been applied.", "refusal")
		if str(choice.get("finish_reason", "")) != "stop" or not choice.get("message") is Dictionary or not choice.message.get("content") is String:
			return fail("The endpoint returned an incomplete or unsupported message.", "shape")
		text = choice.message.content
	var answer := Json.parse(text)
	if not answer.ok:
		return fail(str(answer.error), "shape")
	return {"ok": true, "value": without_nulls(answer.value), "error": "", "why": "", "searched": searched}


func run(provider: String, config: Dictionary, prompt: String, schema: Dictionary, web: bool) -> Dictionary:
	var official := provider == "openai"
	var key := str(config.get("openai_key" if official else "compatible_key", "")).strip_edges()
	var model := str(config.get("openai_model" if official else "compatible_model", "")).strip_edges()
	var result := {}
	# A compatible server that can't do strict JSON schemas is asked for JSON mode, then plain text
	# (the prompt asks for the JSON, and the strict check after this catches anything off).
	for format in (["schema"] if official else ["schema", "json", "none"]):
		var request := request_data(provider, config, prompt, schema, web, format)
		if not request.ok:
			return request
		result = await _send(provider, request, key, model)
		# A rate limit that says how long (Retry-After, 1 to 60 s) is waited out once: the refused
		# request cost nothing. One that doesn't say is left to the player. Cancel ends the wait.
		if not cancelled and float(result.get("retry_after", -1.0)) > 0.0:
			if not await _pause(float(result.retry_after) * wait_scale):
				return fail("Cancelled.", "cancelled")
			result = await _send(provider, request, key, model)
		if cancelled or bool(result.ok) or official or not bool(result.get("format_refused", false)):
			return result
	return result


## Waits (real time), watching for cancel(). False when cancelled.
func _pause(seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and not cancelled and is_inside_tree():
		await get_tree().process_frame
	return not cancelled and is_inside_tree()


func _send(provider: String, request: Dictionary, key: String, model: String) -> Dictionary:
	if transport.is_valid():
		var result: Array = await transport.call(request)
		return fail("Cancelled.", "cancelled") if cancelled else response(provider, result, key, model)
	if not is_inside_tree():
		return fail("Cancelled.", "cancelled")
	_http = HTTPRequest.new()
	_http.timeout = 600.0   # reasoning models with web search can take minutes
	_http.body_size_limit = Json.MAX_BYTES
	_http.max_redirects = 0
	add_child(_http)
	var completed := {"done": false, "result": []}
	_http.request_completed.connect(func(a, b, c, d): completed.done = true; completed.result = [a, b, c, d])
	if _http.request(request.url, request.headers, HTTPClient.METHOD_POST, JSON.stringify(request.body)) != OK:
		_http.queue_free()
		return fail("Couldn't start the provider request.", "offline")
	var deadline := Time.get_ticks_msec() + 615000
	while not completed.done and not cancelled and is_inside_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if is_instance_valid(_http):
		if not completed.done:
			_http.cancel_request()
		_http.queue_free()
	if not completed.done:   # cancelled, timed out, or this helper left the tree
		return fail("Cancelled.", "cancelled") if (cancelled or not is_inside_tree()) else fail("The helper took too long to answer.", "timeout")
	return fail("Cancelled.", "cancelled") if cancelled else response(provider, completed.result, key, model)


func cancel() -> void:
	cancelled = true
	if is_instance_valid(_http):
		_http.cancel_request()


func _exit_tree() -> void:
	cancel()
