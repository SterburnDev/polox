extends RefCounted
## Voice & Live Conversation settings inside Settings > Gameplay > Sound.
## Kept out of test_soul.gd's COPY_FILES word budget.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const VoiceEngine := preload("res://scripts/audio/voice_engine.gd")


static func add_rows(v: Control) -> void:
	var heading := UiKit.label("Voice & Live Conversation", 22, ThemeBuilder.YELLOW)
	heading.add_theme_constant_override("line_spacing", 0)
	v.add_child(heading)

	var cfg := VoiceEngine.get_config()
	var mode_idx := maxi(0, VoiceEngine.VOICE_MODES.find(str(cfg.get("mode", "blips"))))
	var mode_opt := UiKit.option(VoiceEngine.VOICE_MODE_LABELS, mode_idx)
	mode_opt.name = "VoiceMode"
	v.add_child(UiKit.field_row("Voice mode", mode_opt))

	var replace := CheckBox.new()
	replace.name = "ReplaceBlipsCheck"
	replace.text = "Replace dialogue blips with voice"
	replace.tooltip_text = "Uses your chosen voice mode during regular character dialogue instead of classic blips"
	replace.button_pressed = bool(cfg.get("replace_blips", true))
	replace.toggled.connect(func(on): _save("replace_blips", on))
	v.add_child(replace)

	var auto_listen := CheckBox.new()
	auto_listen.name = "VoiceAutoListen"
	auto_listen.text = "Live mode: auto-listen after reply"
	auto_listen.button_pressed = bool(cfg.get("auto_listen", true))
	auto_listen.toggled.connect(func(on): _save("auto_listen", on))
	v.add_child(auto_listen)

	var details := UiKit.vbox(8)
	v.add_child(details)

	var api_idx := maxi(0, VoiceEngine.API_PROVIDERS.find(str(cfg.get("api_provider", "openai"))))
	var api_opt := UiKit.option(VoiceEngine.API_PROVIDER_LABELS, api_idx)
	api_opt.name = "VoiceApiProvider"
	var api_row := UiKit.field_row("Voice API", api_opt)
	details.add_child(api_row)

	var local_edit := UiKit.line_edit("http://127.0.0.1:8880/v1/audio/speech", str(cfg.get("local_url", "")))
	local_edit.name = "VoiceLocalUrl"
	local_edit.text_submitted.connect(func(t): _save("local_url", t.strip_edges()))
	local_edit.focus_exited.connect(func(): _save("local_url", local_edit.text.strip_edges()))
	var local_row := UiKit.field_row("Local voice URL", local_edit)
	details.add_child(local_row)

	var base_edit := UiKit.line_edit("Leave blank for provider default", str(cfg.get("base_url", "")))
	base_edit.name = "VoiceBaseUrl"
	base_edit.text_submitted.connect(func(t): _save("base_url", t.strip_edges()))
	base_edit.focus_exited.connect(func(): _save("base_url", base_edit.text.strip_edges()))
	var base_row := UiKit.field_row("Voice Base URL", base_edit)
	details.add_child(base_row)

	var model_edit := UiKit.line_edit("Optional (e.g. gpt-4o-mini-tts, kokoro)", str(cfg.get("model", "")))
	model_edit.name = "VoiceModel"
	model_edit.text_submitted.connect(func(t): _save("model", t.strip_edges()))
	model_edit.focus_exited.connect(func(): _save("model", model_edit.text.strip_edges()))
	var model_row := UiKit.field_row("Voice model", model_edit)
	details.add_child(model_row)

	var voice_edit := UiKit.line_edit("Optional (e.g. alloy, Kore, af_heart)", str(cfg.get("voice_name", "")))
	voice_edit.name = "VoiceName"
	voice_edit.text_submitted.connect(func(t): _save("voice_name", t.strip_edges()))
	voice_edit.focus_exited.connect(func(): _save("voice_name", voice_edit.text.strip_edges()))
	var voice_row := UiKit.field_row("Voice name", voice_edit)
	details.add_child(voice_row)

	var key_edit := UiKit.line_edit("Blank reuses matching AI key", str(cfg.get("api_key", "")))
	key_edit.name = "VoiceKey"
	key_edit.secret = true
	key_edit.text_submitted.connect(func(t): _save("api_key", t.strip_edges()))
	key_edit.focus_exited.connect(func(): _save("api_key", key_edit.text.strip_edges()))
	var key_row := UiKit.field_row("Voice API key", key_edit)
	details.add_child(key_row)

	var stt_edit := UiKit.line_edit("Optional Whisper URL for desktop Live mic", str(cfg.get("stt_url", "")))
	stt_edit.name = "VoiceSttUrl"
	stt_edit.text_submitted.connect(func(t): _save("stt_url", t.strip_edges()))
	stt_edit.focus_exited.connect(func(): _save("stt_url", stt_edit.text.strip_edges()))
	var stt_row := UiKit.field_row("Local STT URL", stt_edit)
	details.add_child(stt_row)

	var btn_row := UiKit.flow_row(10)
	var test_btn := UiKit.button("Test voice", func():
		VoiceEngine.speak(v, "Hello! Polox voice is ready.", "happy", true), 170)
	test_btn.name = "VoiceTestButton"
	var stop_btn := UiKit.button("Stop voice", func(): VoiceEngine.stop(), 160)
	stop_btn.name = "VoiceStopButton"
	btn_row.add_child(test_btn)
	btn_row.add_child(stop_btn)
	v.add_child(btn_row)

	v.add_child(UiKit.para(
		"System TTS works completely offline on Windows & Android. Live mode uses Android's built-in speech recognizer on phones or microphone + STT on desktop.",
		16,
		ThemeBuilder.MUTED
	))

	var refresh_vis := func():
		var cur := str(VoiceEngine.get_config().get("mode", "blips"))
		var p := str(VoiceEngine.get_config().get("api_provider", "openai"))
		replace.visible = cur != "blips"
		local_row.visible = cur == "local"
		api_row.visible = cur == "api"
		base_row.visible = cur == "api" and p == "custom"
		model_row.visible = cur in ["local", "api"]
		voice_row.visible = cur != "blips"
		key_row.visible = cur == "api"

	refresh_vis.call()
	mode_opt.item_selected.connect(func(i):
		if i >= 0 and i < VoiceEngine.VOICE_MODES.size():
			_save("mode", VoiceEngine.VOICE_MODES[i])
			refresh_vis.call())
	api_opt.item_selected.connect(func(i):
		if i >= 0 and i < VoiceEngine.API_PROVIDERS.size():
			_save("api_provider", VoiceEngine.API_PROVIDERS[i])
			refresh_vis.call())


static func _save(key: String, value: Variant) -> void:
	var v: Dictionary = (GameState.settings.get("voice", {}) as Dictionary).duplicate(true) if GameState.settings.get("voice") is Dictionary else {}
	v[key] = value
	GameState.settings["voice"] = v
	if key == "api_key":
		AIClient.configure(GameState.settings.get("ai", {}))
	GameState.save_settings()
