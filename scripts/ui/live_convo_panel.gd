extends "res://scripts/ui/screen_panel.gd"
class_name LiveConvoPanel

## Real-time spoken conversation overlay opened from DialogueBox ("Live").
## Combines speech input (Android RecognizerIntent on mobile, MicRecorder + STT on desktop,
## plus typed fallback), AIClient/Conversation turn generation, and VoiceEngine playback.

signal transcript_added(speaker: String, text: String)

const AndroidNative := preload("res://scripts/core/android_native.gd")
const VoiceEngine := preload("res://scripts/audio/voice_engine.gd")
const MicRecorder := preload("res://scripts/audio/mic_recorder.gd")

var talk_controller: Node = null
var friend_id: String = ""
var friend_name: String = "Friend"

var _status_label: Label
var _log_box: VBoxContainer
var _scroll: ScrollContainer
var _listen_btn: Button
var _auto_check: CheckBox
var _input: LineEdit
var _mic: MicRecorder
var _busy: bool = false
var _closing: bool = false
var _waiting_android_speech: bool = false


func setup_session(tc: Node, id: String, display_name: String) -> void:
	talk_controller = tc
	friend_id = id
	friend_name = display_name if display_name != "" else "Friend"


func _ready() -> void:
	setup("Live Conversation — " + friend_name, Vector2(880, 620))
	_mic = MicRecorder.new()
	_mic.name = "MicRecorder"
	add_child(_mic)

	_status_label = UiKit.para("Ready — press Speak or type below.", 18, ThemeBuilder.YELLOW)
	_status_label.name = "LiveStatus"
	body.add_child(_status_label)

	_log_box = UiKit.vbox(8)
	_scroll = UiKit.scroll(_log_box)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)

	var controls := UiKit.flow_row(10)
	_listen_btn = UiKit.button("Speak", _on_listen_pressed, 170)
	_listen_btn.name = "LiveListenButton"
	controls.add_child(_listen_btn)

	var stop_btn := UiKit.button("Stop voice", func(): VoiceEngine.stop(), 150)
	stop_btn.name = "LiveStopVoice"
	controls.add_child(stop_btn)

	_auto_check = CheckBox.new()
	_auto_check.name = "LiveAutoListen"
	_auto_check.text = "Auto-listen"
	_auto_check.button_pressed = bool(VoiceEngine.get_config().get("auto_listen", true))
	_auto_check.toggled.connect(func(on):
		var v: Dictionary = (GameState.settings.get("voice", {}) as Dictionary).duplicate(true) if GameState.settings.get("voice") is Dictionary else {}
		v["auto_listen"] = on
		GameState.settings["voice"] = v
		GameState.save_settings())
	controls.add_child(_auto_check)

	var end_btn := UiKit.button("End live", close, 140)
	end_btn.name = "LiveCloseButton"
	controls.add_child(end_btn)
	body.add_child(controls)

	var text_row := UiKit.hbox(8)
	_input = UiKit.line_edit("Or type what you want to say...", "")
	_input.name = "LiveInput"
	_input.text_submitted.connect(func(t: String):
		var clean := t.strip_edges()
		if clean != "":
			_input.text = ""
			_submit_player_turn(clean))
	var send_btn := UiKit.button("Send", func():
		var clean := _input.text.strip_edges()
		if clean != "":
			_input.text = ""
			_submit_player_turn(clean), 110)
	send_btn.name = "LiveSendButton"
	text_row.add_child(_input)
	text_row.add_child(send_btn)
	body.add_child(text_row)

	if OS.has_feature("android"):
		AndroidNative.connect_speech_result(_on_android_speech_result)
	_append_turn(friend_name, "Live conversation active! Mode: %s." % VoiceEngine.effective_mode(true))


func _on_listen_pressed() -> void:
	if _busy or _closing:
		return
	VoiceEngine.stop()
	if OS.has_feature("android") and AndroidNative.speech_available():
		_waiting_android_speech = true
		_set_status("Listening with Android speech...")
		AndroidNative.start_speech_input("Talk to " + friend_name)
		return
	if _mic.is_recording():
		_listen_btn.text = "Speak"
		_set_status("Transcribing speech...")
		var wav := _mic.stop_get_wav()
		var stt := await _mic.transcribe_wav(wav)
		if _closing:
			return
		if not stt.get("ok", false):
			_set_status(str(stt.get("error", "Couldn't transcribe speech.")))
			return
		await _submit_player_turn(str(stt.get("text", "")))
		return
	if _mic.start():
		_listen_btn.text = "Send voice"
		_set_status("Recording microphone... press Send voice when done.")
	else:
		_set_status("No microphone input available. Type below or configure Whisper STT in Settings > Audio.")


func _on_android_speech_result(err: String, transcript: String) -> void:
	if not _waiting_android_speech or _closing:
		return
	_waiting_android_speech = false
	if err == "cancelled":
		_set_status("Ready — press Speak or type below.")
		return
	if err != "" or transcript.strip_edges() == "":
		_set_status(err if err != "" else "Didn't catch any speech.")
		return
	_submit_player_turn(transcript.strip_edges())


func _submit_player_turn(player_text: String) -> void:
	if _busy or _closing:
		return
	_busy = true
	_listen_btn.disabled = true
	var p_name := str(SaveManager.load_world().get("player_name", "You"))
	_append_turn(p_name if p_name != "" else "You", player_text)
	_set_status(friend_name + " is thinking...")

	var reply_text := ""
	var reply_emotion := "neutral"
	if talk_controller and talk_controller.has_method("live_exchange"):
		var r: Variant = await talk_controller.live_exchange(player_text)
		if r is Dictionary:
			reply_text = str((r as Dictionary).get("text", ""))
			reply_emotion = str((r as Dictionary).get("emotion", "neutral"))
	else:
		var res: Dictionary = await AIClient.chat(
			[{"role": "user", "content": player_text}],
			{"max_tokens": 220, "json": false, "mock": {"name": friend_name, "line": player_text}}
		)
		reply_text = str(res.get("text", "")) if res.get("ok", false) else str(res.get("error", "..."))

	if _closing or not is_inside_tree():
		_busy = false
		return
	if reply_text == "":
		reply_text = "..."
	_append_turn(friend_name, reply_text)
	_set_status(friend_name + " is speaking...")
	await VoiceEngine.speak(self, reply_text, reply_emotion, true)
	if _closing or not is_inside_tree():
		_busy = false
		return
	_busy = false
	_listen_btn.disabled = false
	_set_status("Ready — press Speak or type below.")
	if _auto_check.button_pressed and OS.has_feature("android") and AndroidNative.speech_available():
		_on_listen_pressed()


func _append_turn(who: String, text: String) -> void:
	var color := ThemeBuilder.YELLOW if who == friend_name else ThemeBuilder.CREAM
	_log_box.add_child(UiKit.para("%s: %s" % [who, text], 16, color))
	UiKit.show_later(_scroll, _log_box.get_child(_log_box.get_child_count() - 1) as Control)
	transcript_added.emit(who, text)


func _set_status(msg: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = msg


func _exit_tree() -> void:
	_closing = true
	_waiting_android_speech = false
	VoiceEngine.stop()
	if _mic:
		_mic.stop_and_discard()
