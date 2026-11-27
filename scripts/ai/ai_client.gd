extends Node
## Autoload: the only code that talks to an AI provider.
## Speaks OpenAI-compatible POST {base_url}/chat/completions (Ollama: its own POST /api/chat, so any
## model installed on the PC, your own included, with a bigger memory and kept loaded between
## messages); requests are queued one at a time, rate-limited, retried with backoff, and every
## failure becomes a friendly message instead of a crash.
##
## Usage: var r: Dictionary = await AIClient.chat(messages, {"mock": meta})
##        r = {ok: bool, text: String, error: String (friendly), code: int}
## opts may also carry "model": a friend's own model (Friends > their page) instead of Settings' one.
## Tags: [AI_HELPER]

signal status_changed(state: String, message: String)

const Presets := preload("res://scripts/ai/presets.gd")
## A phone asking its PC: if the PC doesn't even pick up within this, it isn't there (offline lines
## at once); once it has, the phone waits for the answer as long as a local model may need.
const PC_CONNECT_TIMEOUT_S := 4.0
const PC_ANSWER_TIMEOUT_S := 180.0
const OLLAMA_CTX := 8192            # tokens of memory for a local model (Ollama's own default is smaller)
const OLLAMA_KEEP_ALIVE := "30m"    # keep the model loaded between messages: no reload wait each time
const OLLAMA_KEEP_ALIVE_S := 1800.0
const OLLAMA_COLD_TIMEOUT_S := 90.0
const OLLAMA_WARM_TIMEOUT_S := 30.0
const OLLAMA_TAGS_TIMEOUT_S := 6.0
const RateLimiter := preload("res://scripts/ai/rate_limiter.gd")
const MockBrain := preload("res://scripts/ai/mock_brain.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const ApiErrors := preload("res://scripts/ai/api_errors.gd")
const RequestSig := preload("res://scripts/phone/request_sig.gd")
const KeyFormat := preload("res://scripts/ai/key_format.gd")
const WebSearch := preload("res://scripts/ai/web_search.gd")

const MAX_RETRIES := 2
## How long to wait after a 429 whose provider didn't say how long.
const UNSAID_WAIT_S := 8.0

var config: Dictionary = {}          # resolved settings["ai"]
var state: String = "mock"            # mock | ready | thinking | waiting | error
var status_message: String = "Mock mode"
var mock_delay_s: float = 0.6         # tests set this to 0
var backoff_base_s: float = 1.5       # 1.5 s, then 3 s (tests shrink it)
var mock: MockBrain = MockBrain.new()
var limiter: RateLimiter = RateLimiter.new(20)
var web_search: WebSearch = null
var _json_mode_ok: bool = true        # flipped off if a provider rejects response_format
var _max_completion := false          # an OpenAI-style server asked for max_completion_tokens instead
var _no_temperature := false          # ...or refused temperature (reasoning models)
var _no_reasoning := false            # ...or refused reasoning/thinking fields
var last_switch := ""                 # why Polox switched to another Ollama model (Settings shows it)
var ollama_answered := false          # the last ollama_models() reached Ollama (an empty list then means: no models)
var _next_ticket: int = 0
var _serving: int = 0
var _pending: int = 0
var pc_token: String = ""              # Phone Link device token (phones only; never logged)
var pc_sign := false                  # paired with pair_v:1: /api/ai is signed (request_sig.gd), the token never sent
var models_note := ""                 # why the last list_models() came back empty ("" when it didn't)
var _cancels := 0                     # cancel() adds one: every chat still out ends as "Stopped."
var _skips := 0                       # the provider or its key changed: a wait meant for the old one ends
var _sends_to := 0                    # which provider, address and key the waits belong to (a hash, not the key)
var _ollama_warm_model := ""
var _ollama_warm_until := 0.0
var _ollama_warm_host := ""
var _pending_switch_note := ""


func _ready() -> void:
	web_search = WebSearch.new()
	web_search.name = "WebSearch"
	add_child(web_search)
	configure({"preset": "mock"})


## Applies settings["ai"]. Called at startup and whenever Settings change.
func configure(ai: Dictionary) -> void:
	config = Presets.resolve(ai)
	limiter.per_minute = max(1, int(config.get("requests_per_minute", 20)))
	_json_mode_ok = true
	_max_completion = false
	_no_temperature = false
	_no_reasoning = false
	var secrets := Presets.all_keys(ai)
	secrets.append(str(config.get("api_key", "")))
	# The home helpers' keys too (GameState comes after this autoload: not there on the first call).
	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.get("settings") is Dictionary:
		secrets.append_array(KeyFormat.stored(game_state.get("settings")))
	ChatLog.set_secrets(secrets)
	# Another provider, address or key: what the old one asked us to wait for no longer applies.
	var sends_to := hash([str(config.get("preset", "")), str(config.get("base_url", "")), str(config.get("api_key", ""))])
	var changed_target := sends_to != _sends_to
	if changed_target:
		_sends_to = sends_to
		limiter.blocked_until = 0.0
		_skips += 1
		_clear_ollama_warm()
		last_switch = ""
		_pending_switch_note = ""
	if is_mock():
		var why := "Mock mode" if config.get("preset") == "mock" else "Mock mode (no API key yet)"
		_set_status("mock", why)
	elif _pending == 0 or changed_target:
		_set_status("ready", "%s ready" % Presets.label(str(config.get("preset", ""))))


## True when no real provider can be used (mock preset, or a key is missing).
func is_mock() -> bool:
	if str(config.get("preset", "mock")) == "mock":
		return true
	if str(config.get("base_url", "")).strip_edges() == "":
		return true
	return bool(config.get("needs_key", false)) and str(config.get("api_key", "")).strip_edges() == ""


func busy() -> bool:
	return _pending > 0


## How many requests background chatter may still use this minute.
func spare_capacity() -> int:
	return limiter.remaining(_now())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _set_status(new_state: String, msg: String) -> void:
	state = new_state
	status_message = msg
	status_changed.emit(new_state, msg)


## Sends a chat request. opts: {mock: meta-for-MockBrain, max_tokens, json: bool}
func chat(messages: Array, opts: Dictionary = {}) -> Dictionary:
	if str(config.get("preset", "")) == "pc" and not is_mock():
		return await _chat_via_pc(messages, opts)
	if is_mock():
		if not is_inside_tree():
			return _stopped()
		_pending += 1
		var mock_mine := _cancels
		if mock_delay_s > 0.0:
			var until := _now() + mock_delay_s * randf_range(0.6, 1.4)
			while _now() < until and mock_mine == _cancels and is_inside_tree():
				await get_tree().process_frame
		_pending -= 1
		if mock_mine != _cancels or not is_inside_tree():
			return _stopped()
		return {"ok": true, "text": mock.respond(opts.get("mock", {})), "error": "", "code": 200}
	if not is_inside_tree():
		return _stopped()
	# Simple FIFO: one request in flight at a time keeps token use predictable.
	var ticket := _next_ticket
	_next_ticket += 1
	_pending += 1
	var mine := _cancels
	while _serving != ticket and mine == _cancels and is_inside_tree():
		await get_tree().process_frame
	var send_messages := messages if (mine != _cancels or not is_inside_tree()) else await _prepare_messages(messages, opts, mine)
	var result: Dictionary = _stopped() if (mine != _cancels or not is_inside_tree()) else await _send_with_retries(send_messages, opts, mine)
	_serving += 1
	_pending -= 1
	if _pending == 0:
		if is_mock():
			var why := "Mock mode" if config.get("preset") == "mock" else "Mock mode (no API key yet)"
			_set_status("mock", why)
		elif result.ok or result.get("cancelled", false):
			_set_status("ready", "%s ready" % Presets.label(str(config.get("preset", ""))))
		else:
			_set_status("error", result.error)
	if not result.ok:
		_pending_switch_note = ""
	return result


## Stops every chat that is waiting (its turn, a rate limit, a retry) or being answered: each one
## returns {ok: false, cancelled: true} at once, and nothing more is sent for it.
func cancel() -> void:
	_cancels += 1


func _exit_tree() -> void:
	cancel()


func _stopped() -> Dictionary:
	var r := _fail(0, "Stopped.", false)
	r["cancelled"] = true
	return r


## Waits `seconds` of real time, counting down in the status line (`words` has one %d). False when
## cancel() ended it (the caller stops); true early when the provider or its key changed (go on now).
func _wait(seconds: float, words: String, mine: int) -> bool:
	var until := _now() + seconds
	var skips := _skips
	var shown := -1
	while _now() < until and mine == _cancels and skips == _skips and is_inside_tree():
		var left := maxi(1, ceili(until - _now() - 0.05))   # (60.00001 s left reads 60, not 61)
		if left != shown:
			shown = left
			_set_status("waiting", words % left)
		await get_tree().process_frame
	return mine == _cancels and is_inside_tree()


## A request's outcome, as request_completed gives it. cancel() ends it at once: Godot's
## cancel_request never emits request_completed, so this looks each frame instead of awaiting it.
func _answer(http: HTTPRequest, mine: int = -1) -> Array:
	var cancel_epoch := mine if mine >= 0 else _cancels
	var box := {"res": []}
	http.request_completed.connect(func(a, b, c, d): box.res = [a, b, c, d], CONNECT_ONE_SHOT)
	var timeout_s := http.timeout if is_instance_valid(http) and http.timeout > 0.0 else 60.0
	var deadline := _now() + timeout_s + 15.0
	while (box.res as Array).is_empty() and is_inside_tree() and _now() < deadline:
		if cancel_epoch != _cancels:
			if is_instance_valid(http):
				http.cancel_request()
			return [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]
		await get_tree().process_frame
	if (box.res as Array).is_empty():
		if is_instance_valid(http):
			http.cancel_request()
		if is_inside_tree() and cancel_epoch == _cancels:
			return [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
		return [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]
	return box.res


## Phone Link: POST the messages to the PC's /api/ai. If the PC can't be
## reached, answer like Mock mode and show "PC offline" (chats keep working).
func _chat_via_pc(messages: Array, opts: Dictionary) -> Dictionary:
	if not is_inside_tree():
		return _stopped()
	var mine := _cancels
	_pending += 1
	_set_status("thinking", "Asking your PC...")
	var http := HTTPRequest.new()
	# Two waits (before 1.27 there was one, of 4 s, so a local model on the PC never had time to answer
	# and the phone always fell back to offline lines): the PC must pick up within a few seconds, or it
	# isn't there; then the phone waits for the answer itself as long as a slow model may take.
	http.timeout = PC_ANSWER_TIMEOUT_S
	add_child(http)
	var body := {"messages": messages, "opts": {}}
	for k in ["max_tokens", "json", "temperature", "mock", "model", "allow_web_search", "reasoning_effort"]:
		if opts.has(k):
			body.opts[k] = opts[k]
	var body_text := JSON.stringify(body)
	var signed := RequestSig.signed(pc_token, "POST", "/api/ai", body_text.to_utf8_buffer()) if pc_sign else {}
	var headers := PackedStringArray(["Content-Type: application/json", str(signed.header) if pc_sign else "Authorization: Bearer " + pc_token])
	var err := http.request(str(config.get("base_url", "")).trim_suffix("/") + "/api/ai", headers, HTTPClient.METHOD_POST, body_text)
	var res: Array = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	if err == OK:
		var box := {"done": false, "res": res}
		http.request_completed.connect(func(a, b, c, d):
			box.done = true
			box.res = [a, b, c, d], CONNECT_ONE_SHOT)
		var started := _now()
		var deadline := started + PC_ANSWER_TIMEOUT_S + 10.0
		var picked_up := false
		while not box.done and is_instance_valid(http) and is_inside_tree() and mine == _cancels and _now() < deadline:
			await get_tree().process_frame
			var st := http.get_http_client_status()
			if st in [HTTPClient.STATUS_REQUESTING, HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED]:
				if not picked_up:
					picked_up = true
					_set_status("thinking", "Your PC is thinking...")
			elif not picked_up and _now() - started > PC_CONNECT_TIMEOUT_S:
				http.cancel_request()   # the PC didn't pick up: it's off, asleep or out of reach
				break
		if not box.done and is_instance_valid(http):
			http.cancel_request()
		res = box.res
	http.queue_free()
	_pending -= 1
	if mine != _cancels or not is_inside_tree():
		return _stopped()
	var code := int(res[1]) if int(res[0]) == HTTPRequest.RESULT_SUCCESS else 0
	if pc_sign and code != 0 and not RequestSig.verify_answer(pc_token, str(signed.nonce), code, res[2], res[3]):
		_set_status("error", "The PC's answer didn't verify")   # changed on the way, or not the PC's: not shown
		return {"ok": false, "text": "", "error": "The PC's answer didn't verify: possible interference on the network.", "code": code}
	var data: Variant = JsonUtil.parse((res[3] as PackedByteArray).get_string_from_utf8())
	if code == 200 and data is Dictionary and bool(data.get("ok", false)):
		_set_status("ready", "Talking through your PC")
		return {"ok": true, "text": str(data.get("text", "")), "error": "", "code": 200}
	if code == 200 and data is Dictionary:
		_set_status("error", str(data.get("error", "")))
		return {"ok": false, "text": "", "error": str(data.get("error", "The PC's AI had a problem.")), "code": 200}
	_set_status("offline", "PC offline · offline lines" if code != 401 else "Phone not paired · offline lines")
	return {"ok": true, "text": mock.respond(opts.get("mock", {})), "error": "", "code": code, "offline": true}


func _send_with_retries(messages: Array, opts: Dictionary, mine: int = -1) -> Dictionary:
	if mine < 0:
		mine = _cancels
	var result := {}
	var attempt := 0
	var iterations := 0
	while attempt <= MAX_RETRIES and iterations < MAX_RETRIES + 8 and is_inside_tree():
		iterations += 1
		# (Asked again after each wait: a wait can end early when the provider changes.)
		while mine == _cancels and limiter.wait_time(_now()) > 0.0 and is_inside_tree():
			if not await _wait(limiter.wait_time(_now()), "Taking a breath (rate limit)... %ds", mine):
				return _stopped()
		if mine != _cancels or not is_inside_tree():
			return _stopped()
		_set_status("thinking", "Thinking...")
		limiter.record(_now())
		result = await _send_once(messages, opts, mine)
		if mine != _cancels:
			return _stopped()
		if result.ok:
			return result
		if result.code == 400 and result.has("provider_message"):
			# A server that rejects a setting says which: fix that one and retry (free, once each).
			# (Not a 400 that is really a refused key, an empty balance or a refused place: asking
			# again without JSON mode would only be a second refusal.)
			var said := str(result.get("provider_message", "")).to_lower()
			if not _max_completion and said.contains("max_completion_tokens"):
				_max_completion = true
				continue
			if not _no_temperature and said.contains("temperature"):
				_no_temperature = true
				continue
			if not _no_reasoning and (said.contains("reasoning") or said.contains("thinking") or said.contains("budget") or said.contains("think")):
				_no_reasoning = true
				continue
			if _json_mode_ok and bool(opts.get("json", true)):
				# Some models reject response_format; retry once without it (free retry).
				_json_mode_ok = false
				continue
		if not result.get("retry", false):
			return result
		attempt += 1
		if attempt > MAX_RETRIES:
			break
		# A rate limit waits what the provider asked (it also holds the limiter, above, for everyone
		# else in the queue); anything else backs off 1.5 s, then 3 s.
		var backoff: float = result.get("retry_after", backoff_base_s * pow(2.0, attempt - 1))
		if not await _wait(backoff, "Trying again in %ds...", mine):
			return _stopped()
	return result


func _model_for(opts: Dictionary) -> String:
	var own := str(opts.get("model", "")).strip_edges()
	return own if own != "" and own.length() <= 120 and not own.contains("\n") else str(config.get("model", "")).strip_edges()


func web_search_enabled(opts: Dictionary = {}) -> bool:
	if bool(opts.get("no_web_search", false)):
		return false
	if opts.has("allow_web_search"):
		return bool(opts.get("allow_web_search", false))
	return bool(config.get("web_search", false))


func _prepare_messages(messages: Array, opts: Dictionary, mine: int) -> Array:
	if not web_search_enabled(opts) or Presets.uses_native_search(config) or str(config.get("preset", "")) == "pc":
		return messages
	if web_search == null or messages.is_empty():
		return messages
	var user_idx := -1
	var user_text := ""
	for i in range(messages.size() - 1, -1, -1):
		var m: Variant = messages[i]
		if m is Dictionary and str((m as Dictionary).get("role", "")) == "user":
			user_idx = i
			user_text = str((m as Dictionary).get("content", ""))
			break
	if user_idx < 0 or not web_search.should_search(user_text):
		return messages
	_set_status("thinking", "Searching the web...")
	var snippets := await web_search.lookup(user_text)
	if mine != _cancels or not is_inside_tree() or snippets == "":
		return messages
	var out := messages.duplicate(true)
	out.insert(user_idx, {"role": "system", "content": snippets})
	return out


func _send_gemini_search(messages: Array, opts: Dictionary, mine: int) -> Dictionary:
	var key := str(config.get("api_key", "")).strip_edges()
	var model := _model_for(opts)
	if key == "" or model == "":
		return {"ok": false, "fallback_openai": true}
	var sys_parts: PackedStringArray = PackedStringArray()
	var contents: Array = []
	for m in messages:
		if not (m is Dictionary):
			continue
		var d := m as Dictionary
		var role := str(d.get("role", "user"))
		var txt := str(d.get("content", ""))
		if txt == "":
			continue
		if role == "system":
			sys_parts.append(txt)
		else:
			contents.append({"role": "model" if role == "assistant" else "user", "parts": [{"text": txt}]})
	if contents.is_empty():
		return {"ok": false, "fallback_openai": true}
	var gen_cfg: Dictionary = {
		"maxOutputTokens": int(opts.get("max_tokens", config.get("max_tokens", 400))),
	}
	if not _no_temperature:
		gen_cfg["temperature"] = float(opts.get("temperature", config.get("temperature", 0.85)))
	var effort := Presets.normalize_effort(str(opts.get("reasoning_effort", config.get("reasoning_effort", "auto"))))
	if not _no_reasoning and effort != "auto":
		var budgets := {"off": 0, "low": 512, "medium": 2048, "high": 8192}
		gen_cfg["thinkingConfig"] = {"thinkingBudget": int(budgets.get(effort, 0))}
	var body: Dictionary = {
		"contents": contents,
		"tools": [{"google_search": {}}],
		"generationConfig": gen_cfg,
	}
	if not sys_parts.is_empty():
		body["system_instruction"] = {"parts": [{"text": "\n\n".join(sys_parts)}]}
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % model.uri_encode()
	var headers := PackedStringArray(["Content-Type: application/json", "x-goog-api-key: " + key])
	var http := HTTPRequest.new()
	http.timeout = float(config.get("timeout_s", 20))
	add_child(http)
	if http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		return {"ok": false, "fallback_openai": true}
	var res: Array = await _answer(http, mine)
	http.queue_free()
	if mine != _cancels or not is_inside_tree():
		return _stopped()
	var result_code: int = int(res[0])
	var code: int = int(res[1])
	var raw_text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return _interpret(res[0], res[1], res[2], res[3])
	if code == 200:
		var parsed: Variant = JsonUtil.parse(raw_text)
		if parsed is Dictionary and (parsed as Dictionary).get("candidates") is Array:
			var cands: Array = (parsed as Dictionary).get("candidates", [])
			if not cands.is_empty() and cands[0] is Dictionary:
				var parts: Variant = (cands[0] as Dictionary).get("content", {}).get("parts", [])
				if parts is Array:
					var chunks := PackedStringArray()
					for p in parts:
						if p is Dictionary and (p as Dictionary).has("text") and not bool((p as Dictionary).get("thought", false)):
							chunks.append(str((p as Dictionary).get("text", "")))
					var combined := "\n".join(chunks).strip_edges()
					if combined != "":
						return {"ok": true, "text": combined, "error": "", "code": 200}
	if code == 400:
		var msg_low := _provider_message(raw_text).to_lower()
		if msg_low.contains("search") or msg_low.contains("tool") or msg_low.contains("grounding") or msg_low.contains("response_mime_type"):
			return {"ok": false, "fallback_openai": true}
	return _interpret(res[0], res[1], res[2], res[3])


func _send_once(messages: Array, opts: Dictionary, mine: int = -1) -> Dictionary:
	if mine < 0:
		mine = _cancels
	if str(config.get("preset", "")) == "ollama":
		return await _send_ollama(messages, opts, false, mine)
	if not is_inside_tree():
		return _stopped()
	var preset_id := str(config.get("preset", ""))
	var base := str(config.get("base_url", "")).to_lower()
	var want_search := web_search_enabled(opts)
	if (preset_id == "gemini" or base.contains("generativelanguage.googleapis.com")) and want_search:
		var gem := await _send_gemini_search(messages, opts, mine)
		if gem.get("fallback_openai", false) == false:
			return gem
	var body := {"model": _model_for(opts), "messages": messages}
	if not _no_temperature:
		body["temperature"] = float(opts.get("temperature", config.get("temperature", 0.85)))
	# Newer OpenAI-style reasoning models want max_completion_tokens (a server that says so is
	# asked that way from then on).
	body["max_completion_tokens" if _max_completion else "max_tokens"] = int(opts.get("max_tokens", config.get("max_tokens", 400)))
	var extra: Dictionary = config.get("extra", {})
	for k in extra:
		body[k] = extra[k]
	Presets.apply_reasoning_and_search(body, config, opts, not _no_reasoning, want_search)
	if _json_mode_ok and bool(opts.get("json", true)):
		body["response_format"] = {"type": "json_object"}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var key := str(config.get("api_key", "")).strip_edges()
	if key != "":
		headers.append("Authorization: Bearer " + key)
	var http := HTTPRequest.new()
	http.timeout = float(config.get("timeout_s", 20))
	add_child(http)
	var url := Presets.endpoint(str(config.get("base_url", "")))
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return _fail(0, "Couldn't start the request. Check the Base URL in Settings.", false)
	var res: Array = await _answer(http, mine)
	http.queue_free()
	if mine != _cancels or not is_inside_tree():
		return _stopped()
	return _interpret(res[0], res[1], res[2], res[3])


## Maps an HTTP outcome to {ok, text} or a friendly, non-technical error.
func _interpret(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	var who := Presets.label(str(config.get("preset", "")))
	if result == HTTPRequest.RESULT_TIMEOUT:
		return _fail(0, "%s took too long to answer." % who, true)
	if result != HTTPRequest.RESULT_SUCCESS:
		if str(config.get("preset", "")) == "ollama":
			return _fail(0, "Can't reach Ollama. Is the Ollama app running?", true)
		return _fail(0, "Can't reach %s. Check your internet connection." % who, true)
	var text := body.get_string_from_utf8()
	if code == 200:
		var data: Variant = JsonUtil.parse(text)
		if data is Dictionary and data.get("choices") is Array and not data["choices"].is_empty():
			var msg: Variant = data["choices"][0].get("message", {})
			if msg is Dictionary:
				return {"ok": true, "text": str(msg.get("content", "")), "error": "", "code": 200}
		return _fail(200, "%s sent back something unexpected." % who, true)
	# The four answers that each want something different from the player (api_errors.gd).
	match ApiErrors.kind(code, text):
		ApiErrors.CREDIT:
			# (No amount of waiting helps: retrying only spends the player's time.)
			return _fail(code, "%s says this account has no credit left. Add credit on its billing page, or choose another provider in Settings > AI." % who, false)
		ApiErrors.RATE_LIMIT:
			var r := _fail(429, "%s says we're sending too fast. Waiting a moment." % who, true)
			var after := _retry_after(headers, text)
			r["retry_after"] = after
			limiter.block_for(after, _now())
			return r
		ApiErrors.NETWORK:
			# (Seen for real: Groq answers every request from some networks this way, whatever the key.)
			return _fail(code, "%s is refusing connections from this network (a VPN, a work or school network, or a region it doesn't serve). Try another network, or another provider in Settings > AI." % who, false)
		ApiErrors.KEY:
			# (401 and 403; Gemini says it with a 400.)
			return _fail(code, "%s didn't accept the API key: it is wrong, expired or switched off. Check it in Settings > AI." % who, false)
	if code == 404:
		var said := _provider_message(text)
		var model := str(config.get("model", ""))
		if said.to_lower().contains("model"):
			return _fail(code, "%s has no model called \"%s\" for this key. Settings > AI > List models shows the ones you can use." % [who, model], false)
		return _fail(code, "%s couldn't find that model or address. Check Model and Base URL." % who, false)
	if code == 400:
		var r400 := _fail(code, "%s rejected the request: %s" % [who, _provider_message(text)], false)
		r400["provider_message"] = _provider_message(text)
		return r400
	if code >= 500:
		return _fail(code, "%s is having trouble right now (error %d)." % [who, code], true)
	return _fail(code, "%s answered with error %d: %s" % [who, code, _provider_message(text)], false)


## (Both live in api_errors.gd now; kept here for the callers that ask the chat client.)
static func refused_this_network(body_text: String) -> bool:
	return ApiErrors.refused_this_network(body_text)


static func out_of_credit(body_text: String) -> bool:
	return ApiErrors.out_of_credit(body_text)


func _fail(code: int, friendly: String, retry: bool) -> Dictionary:
	return {"ok": false, "text": "", "error": ChatLog.redact(friendly), "code": code, "retry": retry}


## Seconds to wait after a 429: what the provider asked (1 to 60 s), or a short guess when it didn't say.
func _retry_after(headers: PackedStringArray, body_text: String = "") -> float:
	var asked := ApiErrors.retry_after(headers, body_text)
	return asked if asked > 0.0 else UNSAID_WAIT_S


func _provider_message(text: String) -> String:
	var data: Variant = JsonUtil.parse(text)
	var msg := ""
	if data is Dictionary:
		var e: Variant = data.get("error", {})
		msg = str(e.get("message", "")) if e is Dictionary else str(e)
	if data is Array and not data.is_empty() and data[0] is Dictionary:
		msg = str(data[0].get("error", {}).get("message", ""))
	if msg == "":
		msg = text.substr(0, 160)
	return ChatLog.redact(msg.substr(0, 200))


## Settings > "Test connection". Returns {ok, message, ms}.
func test_connection() -> Dictionary:
	var started := Time.get_ticks_msec()
	if is_mock():
		return {"ok": true, "message": "Mock mode works (no internet needed).", "ms": 0}
	var msgs := [
		{"role": "system", "content": "Reply only with JSON."},
		{"role": "user", "content": "Reply with {\"segments\":[{\"emotion\":\"happy\",\"text\":\"Hello!\"}],\"memory_note\":\"\"}"},
	]
	var r := await chat(msgs, {"max_tokens": 120, "temperature": 0.2})
	var ms := Time.get_ticks_msec() - started
	if r.ok:
		var used_model := str(r.get("model", config.get("model", "")))
		return {"ok": true, "message": "Connected to %s (%s) in %.1f s." % [Presets.label(str(config.get("preset", ""))), used_model, ms / 1000.0], "ms": ms}
	return {"ok": false, "message": r.error, "ms": ms}


## Lists model ids: Ollama's installed models (your own included), else GET {base_url}/models.
## [] on failure.
func list_models() -> PackedStringArray:
	var out := PackedStringArray()
	models_note = ""
	if str(config.get("preset", "")) == "ollama":
		for m in await ollama_models():
			out.append(str(m.name))
		if out.is_empty():
			models_note = ollama_empty_note()
		return out
	if str(config.get("base_url", "")) == "" or not is_inside_tree():
		return out
	var mine := _cancels
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var headers := PackedStringArray()
	var key := str(config.get("api_key", "")).strip_edges()
	if key != "":
		headers.append("Authorization: Bearer " + key)
	if http.request(Presets.endpoint(str(config.base_url), "models"), headers) != OK:
		http.queue_free()
		return out
	var res: Array = await _answer(http, mine)
	http.queue_free()
	if mine != _cancels or not is_inside_tree():
		return out
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		# A refused key, an empty balance or a refused network is worth saying (a server that simply
		# has no list isn't: the player types the name).
		if res[0] != HTTPRequest.RESULT_SUCCESS or ApiErrors.kind(res[1], (res[3] as PackedByteArray).get_string_from_utf8()) in [ApiErrors.KEY, ApiErrors.CREDIT, ApiErrors.NETWORK]:
			models_note = str(_interpret(res[0], res[1], res[2], res[3]).error)
		return out
	var data: Variant = JsonUtil.parse(res[3].get_string_from_utf8())
	if data is Dictionary and data.get("data") is Array:
		for m in data["data"]:
			if m is Dictionary and m.has("id"):
				out.append(str(m["id"]).trim_prefix("models/"))
	out.sort()
	return out


# --- Ollama ---------------------------------------------------------------------------------------

## Why Ollama returned no models: unreachable (off / HTML proxy) vs running with an empty library.
func ollama_empty_note() -> String:
	return "Can't reach Ollama. Is the Ollama app running?" if not ollama_answered else "Ollama has no models yet. Install one in the Ollama app (or: ollama pull llama3.2)."


## Installed models from Ollama's own list (GET /api/tags), newest first, embedding-only models left
## out: [{name, size_gb, params, family, quant}]. [] when Ollama isn't running.
func ollama_models(mine: int = -1) -> Array:
	var out: Array = []
	ollama_answered = false
	if (mine >= 0 and mine != _cancels) or not is_inside_tree():
		return out
	var epoch := mine if mine >= 0 else _cancels
	var http := HTTPRequest.new()
	http.timeout = minf(OLLAMA_TAGS_TIMEOUT_S, maxf(0.1, float(config.get("timeout_s", OLLAMA_TAGS_TIMEOUT_S))))
	add_child(http)
	var host := Presets.ollama_host(str(config.get("base_url", "")))
	if http.request(host + "/api/tags") != OK:
		http.queue_free()
		return out
	var res: Array = await _answer(http, epoch)
	http.queue_free()
	if epoch != _cancels or not is_inside_tree():
		return out
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return out
	var data: Variant = JsonUtil.parse((res[3] as PackedByteArray).get_string_from_utf8())
	if not data is Dictionary or not data.get("models") is Array:
		return out
	ollama_answered = true
	for m in data.models:
		if not m is Dictionary or str(m.get("name", "")) == "":
			continue
		var details: Dictionary = m.get("details", {}) if m.get("details") is Dictionary else {}
		var family := str(details.get("family", "")).to_lower()
		var name := str(m.name)
		if name.to_lower().contains("embed") or family in ["bert", "nomic-bert"]:
			continue   # turns text into numbers; it can't talk
		out.append({"name": name, "size": int(m.get("size", 0)), "size_gb": snappedf(float(m.get("size", 0)) / 1e9, 0.1),
			"params": str(details.get("parameter_size", "")), "family": str(details.get("family", "")),
			"quant": str(details.get("quantization_level", ""))})
	return out


## [AI_HELPER] Which installed model to fall back to (choose_model): a chat model before one made for
## code, and the smallest of those (it loads and answers fastest; a 20 GB model can take minutes per
## reply on a PC whose graphics card can't hold it). Found when a chosen 12B model went missing and
## Polox switched to a 35B coding model: every later chat timed out.
static func choose_model(installed: Array, missing: String) -> String:
	var best := ""
	var best_key := [true, INF]
	for m in installed:
		var name := str(m.get("name", ""))
		if name == "" or name == missing:
			continue
		var lower := name.to_lower()
		var family := str(m.get("family", "")).to_lower()
		if lower.contains("embed") or family in ["bert", "nomic-bert"]:
			continue
		var for_code := lower.contains("code") or lower.contains("coder") or lower.contains("coding") or lower.contains("devstral")
		var size_gb := float(m.get("size_gb", 0.0))
		if size_gb <= 0.0 and float(m.get("size", 0.0)) > 0.0:
			size_gb = float(m.get("size", 0.0)) / 1e9
		var key := [for_code, size_gb if size_gb > 0.0 else 999.0]
		if best == "" or (not key[0] and best_key[0]) or (key[0] == best_key[0] and key[1] < best_key[1]):
			best = name
			best_key = key
	return best


static func _installed_ollama_model(installed: Array, wanted: String) -> String:
	var target := wanted.strip_edges()
	if target == "":
		return ""
	for m in installed:
		var name := str(m.get("name", ""))
		if name == target:
			return name
	var lower := target.to_lower()
	for m in installed:
		var name := str(m.get("name", ""))
		if name.to_lower() == lower:
			return name
	if not lower.contains(":"):
		var with_latest := lower + ":latest"
		for m in installed:
			var name := str(m.get("name", ""))
			if name.to_lower() == with_latest:
				return name
	return ""


func _clear_ollama_warm() -> void:
	_ollama_warm_model = ""
	_ollama_warm_until = 0.0
	_ollama_warm_host = ""


func is_ollama_warm(model: String = "") -> bool:
	if str(config.get("preset", "")) != "ollama":
		return false
	var target := model.strip_edges() if model.strip_edges() != "" else str(config.get("model", "")).strip_edges()
	var host := Presets.ollama_host(str(config.get("base_url", "")))
	return target != "" and _ollama_warm_model == target and _ollama_warm_host == host and _now() < _ollama_warm_until


func ollama_timeout_for(model: String = "") -> float:
	var cold := maxf(0.1, float(config.get("timeout_s", OLLAMA_COLD_TIMEOUT_S)))
	if is_ollama_warm(model):
		var warm := maxf(0.1, float(config.get("warm_timeout_s", OLLAMA_WARM_TIMEOUT_S)))
		return minf(cold, warm)
	return cold


func _use_ollama_model(installed: Array, missing: String) -> String:
	var chosen := choose_model(installed, missing)
	if chosen == "":
		return ""
	last_switch = ("\"%s\" isn't installed in Ollama, so Polox answered with \"%s\". Settings > AI > Model to choose another." % [missing, chosen]) if missing != "" \
		else "Polox answered with \"%s\", the model installed in Ollama. Settings > AI > Model to choose another." % chosen
	_pending_switch_note = last_switch
	var ai: Dictionary = GameState.settings.get("ai", {})
	var settings_model := str(ai.get("model", "")).strip_edges()
	var settings_host := Presets.ollama_host(str(Presets.resolve(ai).get("base_url", "")))
	var active_host := Presets.ollama_host(str(config.get("base_url", "")))
	if str(ai.get("preset", "")) == "ollama" and settings_host == active_host and (settings_model == "" or _installed_ollama_model(installed, settings_model) == ""):
		ai["model"] = chosen
		GameState.settings["ai"] = ai
		GameState.save_settings()   # (configure() runs again: config.model is now this one)
	elif missing == "" or missing == str(config.get("model", "")).strip_edges():
		config["model"] = chosen
	return chosen


## The model to use when the chosen one isn't installed (or none is chosen yet): choose_model's pick.
## Saved in Settings and said once, so the next chats don't go looking again. "" when Ollama has
## none (or isn't running).
func _pick_ollama_model(missing: String, mine: int = -1) -> String:
	var installed := await ollama_models(mine)
	if mine >= 0 and mine != _cancels:
		return ""
	return _use_ollama_model(installed, missing)


## One chat through Ollama's own API: any installed model (custom ones too), JSON when asked, a bigger
## memory than its default and the model kept loaded. A missing model is replaced by an installed one.
func _send_ollama(messages: Array, opts: Dictionary, healed: bool = false, mine: int = -1) -> Dictionary:
	if mine < 0:
		mine = _cancels
	var model := _model_for(opts)
	var host := Presets.ollama_host(str(config.get("base_url", "")))
	if not healed:
		var installed := await ollama_models(mine)
		if mine != _cancels:
			return _stopped()
		if not ollama_answered:
			# (Found by the live check: with Ollama switched off this used to say "no models yet".)
			_clear_ollama_warm()
			return _fail(0, "Can't reach Ollama. Is the Ollama app running?", true)
		if installed.is_empty():
			_clear_ollama_warm()
			return _fail(0, "Ollama has no models yet. Install one in the Ollama app (or: ollama pull llama3.2), then choose it in Settings > AI.", false)
		var matched := _installed_ollama_model(installed, model)
		if matched != "":
			model = matched
		else:
			model = _use_ollama_model(installed, model)
			if model == "":
				return _fail(0, "Ollama has no models yet. Install one in the Ollama app (or: ollama pull llama3.2), then choose it in Settings > AI.", false)
	elif model == "":
		model = await _pick_ollama_model("", mine)
		if mine != _cancels:
			return _stopped()
		if model == "" and not ollama_answered:
			_clear_ollama_warm()
			return _fail(0, "Can't reach Ollama. Is the Ollama app running?", true)
		if model == "":
			return _fail(0, "Ollama has no models yet. Install one in the Ollama app (or: ollama pull llama3.2), then choose it in Settings > AI.", false)
	var warm := is_ollama_warm(model)
	_set_status("thinking", "Thinking..." if warm else "Loading %s..." % model)
	var effort := Presets.normalize_effort(str(opts.get("reasoning_effort", config.get("reasoning_effort", "auto"))))
	var want_think := effort in ["low", "medium", "high"]
	var base_predict := int(opts.get("max_tokens", config.get("max_tokens", 400)))
	if want_think and not _no_reasoning:
		var bonus := {"low": 800, "medium": 1200, "high": 1800}
		base_predict = maxi(base_predict, int(bonus.get(effort, base_predict)))
	var body := {
		"model": model,
		"messages": messages,
		"stream": false,
		"keep_alive": OLLAMA_KEEP_ALIVE,
		"options": {"temperature": float(opts.get("temperature", config.get("temperature", 0.85))),
			"num_predict": base_predict, "num_ctx": OLLAMA_CTX},
	}
	if not _no_reasoning:
		body["think"] = want_think   # "auto"/"off" answer straight away; low/medium/high enable thinking
	if _json_mode_ok and bool(opts.get("json", true)):
		body["format"] = "json"
	if mine != _cancels or not is_inside_tree():
		return _stopped()
	var http := HTTPRequest.new()
	http.timeout = ollama_timeout_for(model)
	add_child(http)
	var url := host + "/api/chat"
	if http.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		_clear_ollama_warm()
		return _fail(0, "Couldn't start the request to Ollama. Check its address in Settings > AI.", false)
	var res: Array = await _answer(http, mine)
	http.queue_free()
	if mine != _cancels:
		return _stopped()
	var result := interpret_ollama(int(res[0]), int(res[1]), (res[3] as PackedByteArray).get_string_from_utf8(), model)
	if result.ok:
		_ollama_warm_model = model
		_ollama_warm_host = host
		_ollama_warm_until = _now() + OLLAMA_KEEP_ALIVE_S
		result["model"] = model
		if _pending_switch_note != "":
			var note := _pending_switch_note
			_pending_switch_note = ""
			GameState.notify(note)
		return result
	_clear_ollama_warm()
	if int(res[0]) == HTTPRequest.RESULT_TIMEOUT and not warm:
		result["retry"] = false
	if not result.ok and str(result.get("why", "")) == "missing_model" and not healed:
		var other := await _pick_ollama_model(model, mine)
		if mine != _cancels:
			return _stopped()
		if other != "":
			var again := opts.duplicate()
			again.erase("model")   # (a friend's own model that's gone: Settings' one now)
			return await _send_ollama(messages, again, true, mine)
	return result


## Ollama's answer (or error) -> {ok, text} or a friendly message. Static parts for the tests.
func interpret_ollama(result: int, code: int, text: String, model: String) -> Dictionary:
	if result == HTTPRequest.RESULT_TIMEOUT:
		return _fail(0, "Ollama took too long to answer (a big model loading for the first time can: try again).", true)
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail(0, "Can't reach Ollama. Is the Ollama app running?", true)
	var data: Variant = JsonUtil.parse(text)
	var said := ""
	if data is Dictionary and data.get("error") is String:
		said = ChatLog.redact(str(data.error)).substr(0, 200)
	if code == 200 and data is Dictionary and data.get("message") is Dictionary:
		return {"ok": true, "text": str((data.message as Dictionary).get("content", "")), "error": "", "code": 200}
	if code == 404 or said.to_lower().contains("not found"):
		var r := _fail(404, "Ollama doesn't have \"%s\" installed." % model, false)
		r["why"] = "missing_model"
		return r
	if said.to_lower().contains("memory"):
		return _fail(code, "This model needs more memory than the PC has free. Choose a smaller one in Settings > AI.", false)
	if code == 400:
		var r400 := _fail(code, "Ollama rejected the request: %s" % said, false)
		r400["provider_message"] = said
		return r400
	if code >= 500:
		return _fail(code, "Ollama had a problem (%s)." % (said if said != "" else "error %d" % code), true)
	return _fail(code, "Ollama answered with error %d: %s" % [code, said], false)


## The Ollama app on Windows, where its installer puts it ("" when it isn't there): Settings' Start
## Ollama button runs it (only when pressed).
static func ollama_app() -> String:
	if OS.get_name() != "Windows":
		return ""
	var app := OS.get_environment("LOCALAPPDATA").path_join("Programs").path_join("Ollama").path_join("ollama app.exe")
	return app if FileAccess.file_exists(app) else ""

