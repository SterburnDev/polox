extends "res://tests/test_case.gd"
## Offline tests for AI web search, thinking/effort controls, Credits screen,
## Voice Engine + blip replacement, MicRecorder WAV/STT, and Live Conversation UI.

const Presets := preload("res://scripts/ai/presets.gd")
const WebSearch := preload("res://scripts/ai/web_search.gd")
const KeyFormat := preload("res://scripts/ai/key_format.gd")
const CreditsPanel := preload("res://scripts/ui/credits_panel.gd")
const VoiceEngine := preload("res://scripts/audio/voice_engine.gd")
const MicRecorder := preload("res://scripts/audio/mic_recorder.gd")
const LiveConvoPanel := preload("res://scripts/ui/live_convo_panel.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const DialogueBox := preload("res://scripts/ui/dialogue_box.gd")


func test_reasoning_effort_and_native_search_payloads() -> void:
	eq(Presets.normalize_effort("HIGH"), "high", "normalizes case")
	eq(Presets.normalize_effort("invalid"), "auto", "falls back to auto")
	check(Presets.uses_native_search({"preset": "gemini", "base_url": ""}), "Gemini uses native search")
	check(Presets.uses_native_search({"preset": "venice", "base_url": ""}), "Venice uses native search")
	check(Presets.uses_native_search({"preset": "custom", "base_url": "https://openrouter.ai/api/v1"}), "OpenRouter uses native search")
	check(not Presets.uses_native_search({"preset": "groq", "base_url": "https://api.groq.com/openai/v1"}), "Groq uses fallback search")

	var body_venice := {"model": "llama", "messages": []}
	Presets.apply_reasoning_and_search(body_venice, {"preset": "venice", "base_url": "https://api.venice.ai/api/v1"}, {"reasoning_effort": "high"}, true, true)
	eq(body_venice.get("reasoning_effort"), "high", "sets reasoning_effort")
	eq(body_venice.get("venice_parameters", {}).get("enable_web_search"), "on", "sets Venice web search flag")

	var body_or := {"model": "gpt", "messages": []}
	Presets.apply_reasoning_and_search(body_or, {"preset": "custom", "base_url": "https://openrouter.ai/api/v1"}, {"reasoning_effort": "off"}, true, true)
	eq(body_or.get("reasoning_effort"), "none", "maps off effort to none")
	eq(body_or.get("plugins", []), [{"id": "web"}], "adds OpenRouter web plugin")


func test_web_search_mock_lookup() -> void:
	var ws := WebSearch.new()
	tree.root.add_child(ws)
	check(not ws.should_search("hi"), "skips greeting")
	check(ws.should_search("Who won the Stanley Cup in 2025?"), "accepts factual question")
	eq(ws.clean_query("  hello \n  world  "), "hello world", "cleans whitespace")
	ws.transport = func(url: String, _headers: PackedStringArray, _body: String) -> Dictionary:
		if url.contains("api.duckduckgo.com"):
			return {
				"ok": true,
				"code": 200,
				"text": JSON.stringify({
					"AbstractText": "Godot is an open-source 2D and 3D game engine.",
					"AbstractURL": "https://godotengine.org",
					"RelatedTopics": [{"Text": "GDScript is Godot's integrated language."}],
				}),
			}
		if url.contains("wikipedia.org"):
			return {
				"ok": true,
				"code": 200,
				"text": JSON.stringify(["Godot", ["Godot (game engine)"], ["Cross-platform game engine"], ["https://en.wikipedia.org/wiki/Godot_(game_engine)"]]),
			}
		return {"ok": false, "code": 404, "text": ""}
	var out: String = await ws.lookup("What is Godot Engine?")
	check(out.contains("Web search snippets"), "returns snippet header")
	check(out.contains("Godot is an open-source"), "includes DDG abstract")
	ws.queue_free()
	await tree.process_frame


func test_key_format_scrubs_voice_key() -> void:
	fresh_save_root("ai_voice_credits_keys")
	var fake_voice_secret := "sk_test_voice_9876543210abc"
	var stored := KeyFormat.stored({"ai": {}, "voice": {"api_key": fake_voice_secret}})
	check(Array(stored).has(fake_voice_secret), "KeyFormat.stored tracks voice.api_key")
	var prev_ai: Variant = GameState.settings.get("ai", {}).duplicate(true)
	var prev_voice: Variant = GameState.settings.get("voice", {})
	GameState.settings["voice"] = {"api_key": fake_voice_secret}
	AIClient.configure(GameState.settings.get("ai", {}))
	var redacted := ChatLog.redact("Voice error using " + fake_voice_secret)
	check(not redacted.contains(fake_voice_secret), "ChatLog redacts voice API key")
	GameState.settings["voice"] = prev_voice
	AIClient.configure(prev_ai)


func test_credits_panel_content() -> void:
	fresh_save_root("ai_voice_credits_panel")
	var old_ui_sounds: Variant = GameState.settings.get("ui_sounds", true)
	GameState.settings["ui_sounds"] = false
	var panel := CreditsPanel.new()
	tree.root.add_child(panel)
	await tree.process_frame
	var texts := ""
	for node in panel.find_children("*", "Label", true, false):
		texts += " " + (node as Label).text
	for expected in ["SterburnDev", "Gemini", "Claude", "Codex", "Kenney", "Poly Haven", "Godot Engine", "Mochi Soul", "Those Who Fight", "House Theme", "Extras Menu"]:
		check(texts.contains(expected), "Credits shows " + expected)
	panel.queue_free()
	GameState.settings["ui_sounds"] = old_ui_sounds
	await tree.process_frame


func test_voice_engine_and_dialogue_blips_toggle() -> void:
	fresh_save_root("ai_voice_credits_voice")
	var prev_voice: Variant = GameState.settings.get("voice", {})
	var old_ui_sounds: Variant = GameState.settings.get("ui_sounds", true)
	GameState.settings["ui_sounds"] = false

	GameState.settings["voice"] = {"mode": "blips", "replace_blips": true}
	check(not VoiceEngine.replaces_blips(), "classic blips mode never suppresses blips")
	eq(VoiceEngine.effective_mode(true), "tts", "live mode falls back from blips to TTS")

	GameState.settings["voice"] = {"mode": "tts", "replace_blips": true}
	check(VoiceEngine.replaces_blips(), "TTS with replace_blips suppresses blips")

	# Valid 16-bit WAV decode + Gemini PCM decode
	var raw_wav := AudioStreamWAV.new()
	raw_wav.format = AudioStreamWAV.FORMAT_16_BITS
	raw_wav.mix_rate = 16000
	raw_wav.data = PackedByteArray([0, 0, 10, 0, 20, 0, 0, 0])
	var riff := MicRecorder.encode_wav_16bit(raw_wav)
	check(riff.size() == 44 + 8, "encodes valid 16-bit WAV header + PCM payload")
	var decoded := VoiceEngine.decode_audio_buffer(riff)
	check(decoded is AudioStreamWAV, "VoiceEngine decodes WAV buffer")

	var gem_json := JSON.stringify({
		"candidates": [{
			"content": {
				"parts": [{
					"inlineData": {
						"mimeType": "audio/L16;codec=pcm;rate=24000",
						"data": Marshalls.raw_to_base64(PackedByteArray([0, 0, 1, 0, 2, 0, 3, 0])),
					},
				}],
			},
		}],
	})
	var gem_stream := VoiceEngine.decode_gemini_audio_json(gem_json)
	check(gem_stream is AudioStreamWAV, "VoiceEngine wraps Gemini L16 PCM in AudioStreamWAV")

	# DialogueBox Live button shown for characters, hidden for signs
	var box := DialogueBox.new()
	tree.root.add_child(box)
	await tree.process_frame
	box.open("Mochi", {}, {}, true)
	var live_btn := box.find_child("LiveButton", true, false) as Control
	check(live_btn != null and live_btn.visible, "LiveButton visible in character dialogue")
	box.open("Wooden Sign", {}, {}, false)
	check(not live_btn.visible, "LiveButton hidden on signs")
	box.close_box()
	VoiceEngine.stop()
	box.queue_free()
	GameState.settings["voice"] = prev_voice
	GameState.settings["ui_sounds"] = old_ui_sounds
	await tree.process_frame


func test_mic_recorder_wav_and_stt_mock() -> void:
	fresh_save_root("ai_voice_credits_mic")
	var prev_voice: Variant = GameState.settings.get("voice", {})
	GameState.settings["voice"] = {"mode": "api", "api_provider": "openai", "api_key": "sk-test-123"}
	var mic := MicRecorder.new()
	tree.root.add_child(mic)
	var wav_in := AudioStreamWAV.new()
	wav_in.format = AudioStreamWAV.FORMAT_16_BITS
	wav_in.mix_rate = 16000
	wav_in.data = PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	var bytes := MicRecorder.encode_wav_16bit(wav_in)
	MicRecorder.transport = func(_url: String, _headers: PackedStringArray, _body: PackedByteArray) -> Dictionary:
		return {"ok": true, "text": JSON.stringify({"text": "Hello there Mochi!"}), "error": ""}
	var res := await mic.transcribe_wav(bytes)
	check(res.get("ok", false), "mock Whisper transcription succeeds")
	eq(str(res.get("text", "")), "Hello there Mochi!", "extracts Whisper transcript")
	MicRecorder.transport = Callable()
	mic.queue_free()
	GameState.settings["voice"] = prev_voice
	await tree.process_frame


func test_settings_ui_voice_and_ai_controls() -> void:
	fresh_save_root("ai_voice_credits_settings")
	var prev_settings := GameState.settings.duplicate(true)
	GameState.settings["ui_sounds"] = false
	var s := SettingsScreen.new()
	tree.root.add_child(s)
	await tree.process_frame
	for ctrl_name in ["ReasoningEffort", "WebSearchToggle", "VoiceMode", "ReplaceBlipsCheck", "VoiceAutoListen", "CreditsButton"]:
		check(s.find_child(ctrl_name, true, false) != null, "Settings exposes " + ctrl_name)
	s.queue_free()
	VoiceEngine.stop()
	GameState.settings = prev_settings
	await tree.process_frame


func test_live_convo_panel_mock_turn() -> void:
	fresh_save_root("ai_voice_credits_live")
	var prev_voice: Variant = GameState.settings.get("voice", {})
	var prev_ai: Variant = GameState.settings.get("ai", {}).duplicate(true)
	var old_ui_sounds: Variant = GameState.settings.get("ui_sounds", true)
	GameState.settings["ui_sounds"] = false
	GameState.settings["voice"] = {"mode": "tts", "auto_listen": false}
	AIClient.configure({"preset": "mock"})
	AIClient.mock_delay_s = 0.0

	var spoken := []
	VoiceEngine.tts_hook = func(txt: String, _cfg: Dictionary):
		spoken.append(txt)

	var live := LiveConvoPanel.new()
	live.setup_session(null, "mochi", "Mochi")
	tree.root.add_child(live)
	await tree.process_frame
	var input := live.find_child("LiveInput", true, false) as LineEdit
	check(input != null, "LiveInput exists")
	input.text = "How are you today?"
	input.text_submitted.emit(input.text)
	for _i in range(25):
		await tree.process_frame
		if not spoken.is_empty():
			break
	check(not spoken.is_empty(), "LiveConvoPanel spoke friend reply")

	VoiceEngine.tts_hook = Callable()
	VoiceEngine.stop()
	live.queue_free()
	GameState.settings["voice"] = prev_voice
	AIClient.configure(prev_ai)
	GameState.settings["ui_sounds"] = old_ui_sounds
	await tree.process_frame
