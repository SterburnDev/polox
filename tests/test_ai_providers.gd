extends "res://tests/test_case.gd"
## 1.27 AI fixes: each provider keeps its own key (an old shared key moves to its owner and is never
## sent to Ollama or another server); Ollama through its own API with any installed model, a missing
## model replaced by an installed one; OpenAI-style servers that want max_completion_tokens or no
## temperature are asked their way; a phone waits for a slow PC's answer but not for a missing PC;
## Venice. All servers here are fakes on 127.0.0.1.

const Presets := preload("res://scripts/ai/presets.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const PEPE := "freehuntx/Assistant_Pepe:8b"
const REPLY := "{\"segments\":[{\"emotion\":\"happy\",\"text\":\"Hi from the PC!\"}],\"memory_note\":\"\"}"


func _stub(prefix: String, handler: Callable) -> Node:
	var stub: Node = preload("res://scripts/phone/http_server.gd").new()
	tree.root.add_child(stub)
	stub.api_prefix = prefix
	stub.api_handler = handler
	listen_on_free_port(func(p: int) -> String: return stub.start(p, "127.0.0.1"), "the fake server")
	return stub


func _done(stub: Node) -> void:
	AIClient.configure({"preset": "mock"})
	AIClient.last_switch = ""
	stub.stop()
	stub.queue_free()
	await frames(2)


func _body(req: Dictionary) -> Dictionary:
	var d: Variant = JSON.parse_string((req.body as PackedByteArray).get_string_from_utf8())
	return d if d is Dictionary else {}


func test_each_provider_keeps_its_own_key() -> void:
	var groq := {"preset": "ollama", "api_key": "gsk_" + "a".repeat(52)}
	check(Presets.migrate_keys(groq), "an old shared key is migrated")
	eq(str(groq.keys.get("groq", "")), "gsk_" + "a".repeat(52), "a Groq key goes to Groq (by its prefix)")
	check(not groq.has("api_key"), "and the shared key is gone")
	eq(str(Presets.resolve(groq).api_key), "", "Ollama never receives another provider's key")
	var unknown := {"preset": "ollama", "api_key": "k".repeat(53)}
	Presets.migrate_keys(unknown)
	eq(unknown.keys.keys(), ["custom"], "an unknown key chosen with Ollama is kept for a custom server, not sent to Ollama")
	var gem := {"preset": "groq", "api_key": "AIza" + "b".repeat(35)}
	Presets.migrate_keys(gem)
	eq(str(gem.keys.get("gemini", "")), "AIza" + "b".repeat(35), "a Google key goes to Gemini")
	# Google's newer keys start "AQ.": they are Gemini's too, and one an older version filed under
	# "Custom server" is given to Gemini as well (the custom entry is left alone).
	var newer := {"preset": "ollama", "api_key": "AQ." + "c".repeat(50)}
	Presets.migrate_keys(newer)
	eq(str(newer.keys.get("gemini", "")), "AQ." + "c".repeat(50), "a newer Google key goes to Gemini")
	var misfiled := {"preset": "ollama", "keys": {"custom": "AQ." + "d".repeat(50)}}
	check(Presets.migrate_keys(misfiled), "a Google key filed under Custom server is noticed")
	eq(str(misfiled.keys.get("gemini", "")), "AQ." + "d".repeat(50), "and Gemini gets it")
	eq(str(misfiled.keys.get("custom", "")), "AQ." + "d".repeat(50), "the custom entry stays")
	check(not Presets.migrate_keys(misfiled), "once")
	var own := {"preset": "ollama", "keys": {"custom": "AQ." + "e".repeat(50), "gemini": "AIza_mine"}}
	check(not Presets.migrate_keys(own), "a Gemini key already there is never replaced")
	var chosen := {"preset": "venice", "api_key": "v".repeat(40)}
	Presets.migrate_keys(chosen)
	eq(str(chosen.keys.get("venice", "")), "v".repeat(40), "otherwise it stays with the provider chosen with it")
	check(not Presets.migrate_keys({"preset": "groq", "keys": {}}), "nothing to migrate twice")
	var both := {"preset": "groq", "keys": {"groq": "gsk_one", "gemini": "AIza_two"}}
	eq(str(Presets.resolve(both).api_key), "gsk_one")
	both.preset = "gemini"
	eq(str(Presets.resolve(both).api_key), "AIza_two", "switching provider switches the key")
	both.preset = "custom"
	eq(str(Presets.resolve(both).api_key), "", "a custom server gets no key it wasn't given")
	eq(Presets.all_keys(both).size(), 2, "every key is known (to keep it out of logs)")
	AIClient.configure(both)
	check(ChatLog.redact("x gsk_one y AIza_two").find("gsk_one") == -1 and ChatLog.redact("AIza_two").find("AIza_two") == -1, "both keys are redacted from logs")
	AIClient.configure({"preset": "mock"})


func test_venice_preset() -> void:
	var v := Presets.resolve({"preset": "venice", "keys": {"venice": "FAKE-venice"}})
	eq(v.base_url, "https://api.venice.ai/api/v1")
	eq(str(v.model), "zai-org-glm-5", "Venice's documented default model")
	check(bool(v.needs_key), "Venice needs a key")
	eq(v.extra.venice_parameters.include_venice_system_prompt, false, "the friend's own words, not Venice's system prompt")
	check("venice" in Presets.ORDER, "Venice is offered in Settings")
	eq(Presets.ollama_host("http://localhost:11434/v1/"), "http://127.0.0.1:11434")


func test_ollama_uses_installed_models_and_replaces_a_missing_one() -> void:
	fresh_save_root()
	var seen: Array = []
	var stub := _stub("/api/", func(req: Dictionary, _ip: String) -> PackedByteArray:
		if str(req.path) == "/api/tags":
			return HttpUtil.json_response(200, {"models": [
				{"name": PEPE, "size": 4900000000, "details": {"family": "llama", "parameter_size": "8.0B", "quantization_level": "Q4_K_M"}},
				{"name": "nomic-embed-text:latest", "size": 270000000, "details": {"family": "nomic-bert"}}]})
		var body := _body(req)
		seen.append(body)
		if str(body.get("model", "")) == PEPE:
			return HttpUtil.json_response(200, {"model": PEPE, "message": {"role": "assistant", "content": REPLY}, "done": true})
		return HttpUtil.json_response(404, {"error": "model \"%s\" not found, try pulling it first" % str(body.get("model", ""))}))
	var base := "http://127.0.0.1:%d/v1" % stub.port
	GameState.settings["ai"] = {"preset": "ollama", "base_url": base, "model": "qwen2.5:7b-instruct", "timeout_s": 10}
	GameState.save_settings()
	# Earlier suites do synchronous disk work. Let that frame finish before a
	# timed HTTPRequest starts, and let the fixture's server thread settle.
	await frames(2)
	var models: Array = await AIClient.ollama_models()
	eq(models.map(func(m): return str(m.name)), [PEPE], "installed chat models (an embedding model can't talk)")
	if models.is_empty():
		print("[ollama fixture] host=", AIClient.config.get("base_url"), " server=", stub.recent())
		await _done(stub)
		return
	eq(str(models[0].params), "8.0B")
	eq(Array(await AIClient.list_models()), [PEPE], "Settings' List models shows what Ollama has, custom models included")
	var r: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {"max_tokens": 50})
	check(r.ok, "the chat works with the model that is installed: " + str(r.get("error", "")))
	eq(str(r.text), REPLY)
	eq(str(GameState.settings.ai.model), PEPE, "the missing model is replaced in Settings, so it doesn't happen again")
	check(AIClient.last_switch.contains("qwen2.5:7b-instruct") and AIClient.last_switch.contains(PEPE), "and the player is told which and why")
	var sent: Dictionary = seen.back()
	eq(sent.get("stream"), false)
	eq(sent.get("format"), "json", "JSON replies")
	eq(int(sent.options.num_ctx), AIClient.OLLAMA_CTX, "a bigger memory than Ollama's default")
	eq(str(sent.keep_alive), AIClient.OLLAMA_KEEP_ALIVE, "the model stays loaded between messages")
	eq(sent.get("think"), false, "thinking models answer straight away")
	# A friend's own model (Friends > their page) goes with that request only.
	var own: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {"model": PEPE})
	check(own.ok)
	eq(str(seen.back().model), PEPE)
	# Ollama not running.
	AIClient.configure({"preset": "ollama", "base_url": "http://127.0.0.1:9/v1", "model": PEPE, "timeout_s": 3})
	AIClient.backoff_base_s = 0.05
	var down: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {})
	check(not down.ok and str(down.error).contains("Ollama"), "Ollama not running says so: " + str(down.error))
	AIClient.backoff_base_s = 1.5
	await _done(stub)


func test_openai_style_server_that_wants_reasoning_model_settings() -> void:
	var asked := [0]
	var stub := _stub("/v1/", func(req: Dictionary, _ip: String) -> PackedByteArray:
		asked[0] += 1
		var body := _body(req)
		if body.has("max_tokens"):
			return HttpUtil.json_response(400, {"error": {"message": "Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead."}})
		if body.has("temperature"):
			return HttpUtil.json_response(400, {"error": {"message": "Unsupported value: 'temperature' does not support 0.85 with this model. Only the default (1) value is supported."}})
		return HttpUtil.json_response(200, {"choices": [{"message": {"role": "assistant", "content": REPLY}}]}))
	AIClient.configure({"preset": "custom", "base_url": "http://127.0.0.1:%d/v1" % stub.port, "model": "gpt-6-luna", "timeout_s": 5})
	var r: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {})
	check(r.ok, "the request is reshaped as the server asks: " + str(r.get("error", "")))
	eq(asked[0], 3, "once per thing it refused, then it works")
	var again: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {})
	check(again.ok)
	eq(asked[0], 4, "and from then on it is asked the right way first")
	await _done(stub)


func test_venice_request_carries_its_parameters() -> void:
	var seen: Array = []
	var stub := _stub("/api/v1/", func(req: Dictionary, _ip: String) -> PackedByteArray:
		seen.append(_body(req))
		return HttpUtil.json_response(200, {"choices": [{"message": {"role": "assistant", "content": REPLY}}]}))
	AIClient.configure({"preset": "venice", "base_url": "http://127.0.0.1:%d/api/v1" % stub.port, "keys": {"venice": "FAKE-venice-key"}, "timeout_s": 5})
	var r: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {})
	check(r.ok, str(r.get("error", "")))
	eq(seen[0].model, "zai-org-glm-5")
	eq(seen[0].venice_parameters.include_venice_system_prompt, false)
	await _done(stub)


func test_a_phone_waits_for_a_slow_pc_but_not_a_missing_one() -> void:
	var stub := _stub("/api/", func(req: Dictionary, _ip: String) -> PackedByteArray:
		await tree.create_timer(6.0).timeout   # a local model taking its time (longer than the old 4 s cap)
		var opts: Dictionary = _body(req).get("opts", {})
		return HttpUtil.json_response(200, {"ok": true, "text": "slow but real (%s)" % str(opts.get("model", "")), "error": ""}))
	AIClient.configure({"preset": "pc", "base_url": "http://127.0.0.1:%d" % stub.port})
	AIClient.pc_token = "FAKE-device-token"
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {"model": PEPE})
	check(r.ok and str(r.text) == "slow but real (%s)" % PEPE, "the PC's real answer arrives, after %.1f s: %s" % [(Time.get_ticks_msec() - t0) / 1000.0, str(r)])
	check(not bool(r.get("offline", false)), "not the offline lines")
	# No PC at that address: offline lines at once.
	AIClient.configure({"preset": "pc", "base_url": "http://127.0.0.1:9"})
	t0 = Time.get_ticks_msec()
	var gone: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {})
	check(bool(gone.get("offline", false)), "a PC that isn't there: offline lines")
	check(Time.get_ticks_msec() - t0 < AIClient.PC_CONNECT_TIMEOUT_S * 1000.0 + 1500.0, "and quickly")
	AIClient.pc_token = ""
	await _done(stub)


## Found by tools/api_live_check.gd: with no model chosen and Ollama switched off, the chat said "Ollama
## has no models yet" (advice to install one) when the truth was that nothing answered at all.
func test_ollama_switched_off_is_not_called_empty() -> void:
	AIClient.backoff_base_s = 0.01
	AIClient.configure({"preset": "ollama", "base_url": "http://127.0.0.1:9/v1", "model": "", "timeout_s": 3})
	var r: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {"max_tokens": 20})
	check(not r.ok, "nothing answers on that port")
	check(str(r.error).contains("Can't reach Ollama"), "the player is told Ollama isn't running: " + str(r.error))
	check(not str(r.error).contains("no models"), "and not to install a model")
	AIClient.backoff_base_s = 1.5
	AIClient.configure({"preset": "mock"})


func test_ollama_probes_tags_avoids_coding_fallback_and_handles_empty_or_off() -> void:
	fresh_save_root()
	var seen_paths: Array = []
	var seen_models: Array = []
	var html_tags := {"on": false}
	var tags_payload := {"models": [
		{"name": "qwen3.6:35b-a3b-coding", "size": 22621314381, "details": {"family": "qwen35moe"}},
		{"name": "devstral:24b", "size": 14000000000, "details": {"family": "mistral"}},
		{"name": "gemma-4:12b", "size": 7556507919, "details": {"family": "gemma4"}},
		{"name": "llama3.2:3b", "size": 2000000000, "details": {"family": "llama"}},
	]}
	var stub := _stub("/api/", func(req: Dictionary, _ip: String) -> PackedByteArray:
		seen_paths.append(str(req.path))
		if str(req.path) == "/api/tags":
			if html_tags.on:
				return HttpUtil.response(200, "<html>not ollama</html>".to_utf8_buffer(), "text/html")
			return HttpUtil.json_response(200, tags_payload)
		var body := _body(req)
		var m := str(body.get("model", ""))
		seen_models.append(m)
		return HttpUtil.json_response(200, {"model": m, "message": {"role": "assistant", "content": REPLY}, "done": true}))
	var base := "http://127.0.0.1:%d/v1" % stub.port
	GameState.settings["ai"] = {"preset": "ollama", "base_url": base, "model": "gone-model:7b", "timeout_s": 10}
	GameState.save_settings()
	await frames(2)
	var toasts: PackedStringArray = []
	var on_toast := func(t: String) -> void:
		toasts.append(t)
	GameState.toast.connect(on_toast)
	var r: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {"max_tokens": 50})
	GameState.toast.disconnect(on_toast)
	check(r.ok, "falls back cleanly after probing tags: " + str(r.get("error", "")))
	eq(seen_paths, ["/api/tags", "/api/chat"], "probes GET /api/tags before POST /api/chat")
	eq(seen_models, ["llama3.2:3b"], "picks smallest chat model and avoids coding models without wasting a /api/chat call")
	eq(str(r.get("model", "")), "llama3.2:3b", "tells caller which model answered")
	eq(str(GameState.settings.ai.model), "llama3.2:3b", "saves lightweight fallback model")
	check(AIClient.last_switch.contains("gone-model:7b") and AIClient.last_switch.contains("llama3.2:3b"), "informs player which model answered")
	check(toasts.size() == 1 and toasts[0].contains("gone-model:7b") and toasts[0].contains("llama3.2:3b"), "emits toast notification informing player which model answered: " + str(toasts))
	# Reachable Ollama with 0 chat models reports no models yet without calling /api/chat.
	seen_paths.clear()
	seen_models.clear()
	tags_payload["models"] = []
	AIClient.configure({"preset": "ollama", "base_url": base, "model": "gone-model:7b", "timeout_s": 5})
	var empty_res: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {})
	check(not empty_res.ok and str(empty_res.error).contains("no models yet"), "reachable empty Ollama says no models: " + str(empty_res.error))
	eq(seen_paths, ["/api/tags"], "stops after /api/tags when no models exist")
	# Non-Ollama HTTP 200 HTML response on /api/tags is treated as unreachable, never "no models yet".
	seen_paths.clear()
	html_tags.on = true
	AIClient.backoff_base_s = 0.01
	var html_res: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {})
	check(not html_res.ok and str(html_res.error).contains("Can't reach Ollama"), "non-Ollama 200 HTML is reported unreachable: " + str(html_res.error))
	check(not str(html_res.error).contains("no models"), "non-Ollama 200 HTML never says no models yet")
	# Unreachable Ollama even WITH a configured model name never says "no models yet".
	AIClient.configure({"preset": "ollama", "base_url": "http://127.0.0.1:9/v1", "model": "llama3.2:3b", "timeout_s": 3})
	var listed_off := await AIClient.list_models()
	eq(Array(listed_off), [], "list_models empty when Ollama is off")
	check(AIClient.models_note.contains("Can't reach Ollama") and not AIClient.models_note.contains("no models"), "list_models note says unreachable when Ollama is off: " + AIClient.models_note)
	var off_res: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {})
	check(not off_res.ok and str(off_res.error).contains("Can't reach Ollama"), "unreachable Ollama with configured model reports unreachable: " + str(off_res.error))
	check(not str(off_res.error).contains("no models"), "never says no models when unreachable")
	AIClient.backoff_base_s = 1.5
	await _done(stub)


func test_ollama_cold_vs_warm_timeout_cancel_and_single_flight() -> void:
	fresh_save_root()
	var resolved_default := Presets.resolve({"preset": "ollama"})
	eq(int(resolved_default.timeout_s), 90, "cold-start Ollama timeout defaults to 90s")
	eq(int(resolved_default.get("warm_timeout_s", 0)), 30, "warm Ollama timeout defaults to 30s")
	eq(int(Presets.resolve({"preset": "ollama", "timeout_s": 20}).timeout_s), 90, "upgrades generic 20s default to 90s for Ollama")

	var state := {"delay_s": 0.0, "in_flight": 0, "max_in_flight": 0, "slow_done": true, "chat_hits": 0}
	var chat_order: Array = []
	var stub := _stub("/api/", func(req: Dictionary, _ip: String) -> PackedByteArray:
		if str(req.path) == "/api/tags":
			return HttpUtil.json_response(200, {"models": [
				{"name": "llama3.2:3b", "size": 2000000000, "details": {"family": "llama"}},
				{"name": "gemma-4:12b", "size": 7556507919, "details": {"family": "gemma4"}},
			]})
		state.chat_hits = int(state.chat_hits) + 1
		state.in_flight = int(state.in_flight) + 1
		state.max_in_flight = maxi(int(state.max_in_flight), int(state.in_flight))
		var body := _body(req)
		var msgs: Array = body.get("messages", [])
		var user_msg := str(msgs.back().get("content", "")) if not msgs.is_empty() else ""
		chat_order.append(user_msg)
		if float(state.delay_s) > 0.0:
			state.slow_done = false
			await tree.create_timer(float(state.delay_s)).timeout
		state.in_flight = int(state.in_flight) - 1
		state.slow_done = true
		return HttpUtil.json_response(200, {"model": str(body.get("model", "")), "message": {"role": "assistant", "content": REPLY}, "done": true}))
	var base := "http://127.0.0.1:%d/v1" % stub.port
	AIClient.configure({"preset": "ollama", "base_url": base, "model": "llama3.2:3b"})
	await frames(2)
	check(not AIClient.is_ollama_warm("llama3.2:3b"), "cold before first answer")
	check(is_equal_approx(AIClient.ollama_timeout_for("llama3.2:3b"), 90.0), "cold timeout is 90s")
	var cold_res: Dictionary = await AIClient.chat([{"role": "user", "content": "cold"}], {})
	check(cold_res.ok, "cold chat succeeds: " + str(cold_res.get("error", "")))
	check(AIClient.is_ollama_warm("llama3.2:3b"), "marked warm after HTTP 200")
	check(is_equal_approx(AIClient.ollama_timeout_for("llama3.2:3b"), 30.0), "warm timeout drops to 30s")
	check(is_equal_approx(AIClient.ollama_timeout_for("gemma-4:12b"), 90.0), "different model still gets 90s cold timeout")

	# Single-flight request queuing under rapid concurrent messages.
	chat_order.clear()
	state.max_in_flight = 0
	state.delay_s = 0.05
	var batch := {"a": {}, "b": {}, "c": {}}
	var send_msg := func(slot: String, text: String) -> void:
		batch[slot] = await AIClient.chat([{"role": "user", "content": text}], {})
	send_msg.call("a", "msg 1")
	send_msg.call("b", "msg 2")
	send_msg.call("c", "msg 3")
	var t0 := Time.get_ticks_msec()
	while (batch.a.is_empty() or batch.b.is_empty() or batch.c.is_empty()) and Time.get_ticks_msec() - t0 < 8000:
		await frames(1)
	check(bool(batch.a.get("ok", false)) and bool(batch.b.get("ok", false)) and bool(batch.c.get("ok", false)), "all queued chats succeed")
	eq(int(state.max_in_flight), 1, "requests never overlap in flight")
	eq(chat_order, ["msg 1", "msg 2", "msg 3"], "FIFO single-flight order preserved")
	check(not AIClient.busy() and AIClient.state == "ready", "clean state after queue drains")

	# Clean user cancellation during cold-start loading (with queued follower + immediate fresh message after cancel).
	AIClient.configure({"preset": "ollama", "base_url": base, "model": "gemma-4:12b"})
	AIClient._clear_ollama_warm()
	state.delay_s = 0.25
	var cancel_toasts: PackedStringArray = []
	var on_cancel_toast := func(t: String) -> void:
		cancel_toasts.append(t)
	GameState.toast.connect(on_cancel_toast)
	var cbox := {"a": {}, "b": {}, "after": {}}
	var start_a := func() -> void:
		cbox.a = await AIClient.chat([{"role": "user", "content": "slow cold a"}], {"model": "missing-cancel:7b"})
	var start_b := func() -> void:
		cbox.b = await AIClient.chat([{"role": "user", "content": "queued cold b"}], {})
	start_a.call()
	start_b.call()
	t0 = Time.get_ticks_msec()
	while not AIClient.status_message.contains("Loading llama3.2:3b") and Time.get_ticks_msec() - t0 < 3000:
		await frames(1)
	check(AIClient.status_message.contains("Loading llama3.2:3b"), "reports cold-start loading status: " + AIClient.status_message)
	AIClient.cancel()
	var start_after := func() -> void:
		cbox.after = await AIClient.chat([{"role": "user", "content": "fresh after cancel"}], {})
	start_after.call()
	t0 = Time.get_ticks_msec()
	while (cbox.a.is_empty() or cbox.b.is_empty() or cbox.after.is_empty()) and Time.get_ticks_msec() - t0 < 5000:
		await frames(1)
	GameState.toast.disconnect(on_cancel_toast)
	check(bool(cbox.a.get("cancelled", false)) and not bool(cbox.a.get("ok", true)), "cancel stops active cold-start load cleanly: " + str(cbox.a))
	check(bool(cbox.b.get("cancelled", false)) and not bool(cbox.b.get("ok", true)), "cancel stops queued request cleanly: " + str(cbox.b))
	check(not AIClient.is_ollama_warm("llama3.2:3b"), "cancelled cold load is not marked warm")
	check(bool(cbox.after.get("ok", false)), "fresh message sent right after cancel succeeds cleanly: " + str(cbox.after))
	check(cancel_toasts.is_empty(), "cancelled fallback does not emit answered toast: " + str(cancel_toasts))
	check(not AIClient.busy() and AIClient.state == "ready", "not stuck busy or error after cancel+fresh")
	t0 = Time.get_ticks_msec()
	while not state.slow_done and Time.get_ticks_msec() - t0 < 2000:
		await frames(1)

	# Cold-start timeout does not repeat full timeout 3 times and clears warm state.
	AIClient.configure({"preset": "ollama", "base_url": base, "model": "gemma-4:12b", "timeout_s": 0.25})
	AIClient._clear_ollama_warm()
	state.chat_hits = 0
	state.delay_s = 0.6
	var tout_res: Dictionary = await AIClient.chat([{"role": "user", "content": "timeout test"}], {})
	check(not tout_res.ok and str(tout_res.error).contains("too long"), "cold timeout gives friendly error: " + str(tout_res.error))
	eq(int(state.chat_hits), 1, "cold timeout does not stall 3x retrying full cold timeout")
	check(not AIClient.is_ollama_warm("gemma-4:12b"), "timed-out load is not marked warm")
	t0 = Time.get_ticks_msec()
	while not state.slow_done and Time.get_ticks_msec() - t0 < 2000:
		await frames(1)
	await frames(2)
	await _done(stub)
