extends Control
## RPG-style dialogue box: portrait, name, typewriter text with blips
## in the speaker's own voice (sound, pitch, speed). Click anywhere (or
## E/Z/Enter) to finish or advance. After the last segment, a chat row
## appears: type, then the big Send button. Your own line types out above
## the box in your voice, next to a little picture of your face.

signal sent(text: String)
signal closed
signal save_moment
signal segment_started(emotion: String)
signal gift_pressed
signal reply_chosen(text: String)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const InputSetup := preload("res://scripts/core/input_setup.gd")
const Synth := preload("res://scripts/core/synth.gd")
const EmoteMotion := preload("res://scripts/characters/emote_motion.gd")
const Voice := preload("res://scripts/characters/voice.gd")
const SymbolFont := preload("res://scripts/ui/symbol_font.gd")
const Feelings := preload("res://scripts/characters/feelings.gd")
const TouchGestures := preload("res://scripts/ui/touch_gestures.gd")

var portrait: TextureRect
var name_label: Label
var text_label: Label
var arrow: Label
var you_label: Label
var input_row: HFlowContainer    # wraps onto two lines on narrow (phone) screens
var chips: HFlowContainer        # quick replies: tap one to say it
var _reply_count := 0
var input: LineEdit
var send_btn: Button
var state := "hidden"            # typing | waiting | input | thinking | hidden
var chat_enabled := true         # false for signs: just read and close
var textures: Dictionary = {}    # emotion -> Texture2D
var voice: Dictionary = {"sound": "blip", "pitch": 1.0, "speed": 1.0}
var player_voice: Dictionary = {"sound": "soft", "pitch": 1.15, "speed": 1.0}
var player_textures: Dictionary = {}   # emotion -> Texture2D (your faces)
var you_face: TextureRect
var _you_shown := 0.0
var _you_typing := false
var _you_blip: AudioStreamPlayer
var _queue: Array = []
var _shown := 0.0
var _pause := 0.0
var _t := 0.0
var _blip: AudioStreamPlayer
var _last_blip_char := -1
var _box: PanelContainer
var _kb_lift := 0.0                    # px kept free at the bottom for the phone page's text bar


func _ready() -> void:
	UiKit.fill(self)
	mouse_filter = Control.MOUSE_FILTER_STOP   # full-screen catcher: clicks advance, never walk
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", ThemeBuilder.box(Color(0.02, 0.01, 0.05, 1.0), ThemeBuilder.CREAM, 4, 8, 14))
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 24
	box.offset_right = -24
	box.offset_top = -292
	box.offset_bottom = -20
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(box)
	_box = box
	resized.connect(_fit_box)
	var row := UiKit.hbox(18)
	box.add_child(row)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, Color(ThemeBuilder.CREAM, 0.4), 2, 8, 6))
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(frame)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(176, 176)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(portrait)
	var col := UiKit.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	name_label = UiKit.label("", 26, ThemeBuilder.YELLOW)
	col.add_child(name_label)
	text_label = UiKit.para("", 26, ThemeBuilder.CREAM)
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_label.custom_minimum_size.y = 100
	col.add_child(text_label)
	chips = HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 6)
	chips.visible = false
	col.add_child(chips)
	input_row = HFlowContainer.new()
	input_row.add_theme_constant_override("h_separation", 10)
	input_row.add_theme_constant_override("v_separation", 8)
	col.add_child(input_row)
	input = UiKit.line_edit("Say something... (Enter to send)")
	input.max_length = 600
	input.context_menu_enabled = false
	input.text_submitted.connect(func(_t): _send())
	input.custom_minimum_size.x = 240
	input_row.add_child(input)
	send_btn = UiKit.button("Send", _send, 120)
	input_row.add_child(send_btn)
	var star := UiKit.button("★ Save", func(): save_moment.emit(), 110)
	star.tooltip_text = "Save this moment to your Memory Book"
	input_row.add_child(star)
	var gift := UiKit.button("Gift", func(): gift_pressed.emit(), 100)
	gift.tooltip_text = "Give a little gift from your bag (up to three per friend a day)"
	input_row.add_child(gift)
	input_row.add_child(UiKit.button("Bye", close_box, 100))
	# The arrow lives on the full-screen layer (a PanelContainer would stretch it).
	arrow = UiKit.label("▼", 26, ThemeBuilder.YELLOW)
	arrow.autowrap_mode = TextServer.AUTOWRAP_OFF
	arrow.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	arrow.offset_left = -76
	arrow.offset_top = -70
	arrow.offset_right = -46
	arrow.offset_bottom = -36
	add_child(arrow)
	you_label = UiKit.para("", 20, ThemeBuilder.MUTED)
	you_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	you_label.offset_left = 96
	you_label.offset_right = -40
	you_label.offset_top = -336
	you_label.offset_bottom = -300
	add_child(you_label)
	you_face = TextureRect.new()
	you_face.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	you_face.offset_left = 40
	you_face.offset_right = 88
	you_face.offset_top = -346
	you_face.offset_bottom = -298
	you_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	you_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	you_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	you_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(you_face)
	_blip = AudioStreamPlayer.new()
	_blip.stream = Synth.get_sound("blip")
	add_child(_blip)
	_you_blip = AudioStreamPlayer.new()
	add_child(_you_blip)
	visible = false


## On a small window (or a big UI scale) the box takes at most half the
## height, and the portrait shrinks with it, so the room stays visible.
func _fit_box() -> void:
	if _box == null:
		return
	var h := minf(292.0, maxf(190.0, size.y * 0.5))
	if size.x < 900.0 and size.y > size.x:
		h = minf(450.0, size.y * 0.38)   # portrait phone: taller box, the buttons wrap
	var top := h + _kb_lift
	_box.offset_bottom = -20.0 - _kb_lift
	_box.offset_top = -top
	you_label.offset_top = -top - 44
	you_label.offset_bottom = -top - 8
	you_face.offset_top = -top - 54
	you_face.offset_bottom = -top - 6
	var p := clampf(h - 116.0, 96.0, 176.0)
	if size.x < 900.0:
		p = 96.0  # narrow screens: more room for the words
	portrait.custom_minimum_size = Vector2(p, p)
	# Portrait phones: the speaker is right there in the room; give the words the width.
	portrait.get_parent().visible = not textures.is_empty() and not (size.x < 700.0 and size.y > size.x)


## Starts a conversation box for a character (or a sign when chat=false).
## speaker_voice: {sound, pitch, speed} (see voice.gd).
func open(display_name: String, expression_textures: Dictionary, speaker_voice: Dictionary = {}, chat: bool = true) -> void:
	name_label.text = display_name
	textures = expression_textures
	voice = {"sound": str(speaker_voice.get("sound", "blip")), "pitch": float(speaker_voice.get("pitch", 1.0)), "speed": float(speaker_voice.get("speed", 1.0))}
	_blip.stream = Voice.stream(str(voice.sound))
	_you_blip.stream = Voice.stream(str(player_voice.get("sound", "soft")))
	chat_enabled = chat
	you_label.text = ""
	you_face.texture = null
	_you_typing = false
	portrait.get_parent().visible = not textures.is_empty()
	_set_portrait("neutral")
	_fit_box()
	visible = true
	state = "waiting"


func _set_portrait(emotion: String) -> void:
	var tex: Texture2D = textures.get(emotion, textures.get("neutral", null))
	portrait.texture = tex


## Queues reply segments [{emotion, text}] and starts typing the first.
func show_segments(segments: Array) -> void:
	_queue = segments.duplicate()
	_next_segment()


## The portrait does the same little bounce/shake as the character.
func _wiggle_portrait(emotion: String) -> void:
	var steps := EmoteMotion.portrait_steps(emotion)
	if steps.is_empty():
		return
	portrait.pivot_offset = portrait.size / 2.0
	var tw := create_tween()
	for s in steps:
		tw.tween_property(portrait, "rotation", s[0], s[2]).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(portrait, "scale", s[1], s[2]).set_trans(Tween.TRANS_SINE)


## Quick-reply chips for the next input (an empty list hides them).
func set_replies(list: Array) -> void:
	for c in chips.get_children():
		c.queue_free()
	for r in list.slice(0, 3):
		var text := str(r)
		var b := UiKit.button(SymbolFont.displayable(text), func(): choose_reply(text), 0)
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size.y = 48
		b.tooltip_text = "Say this"
		chips.add_child(b)
	_reply_count = mini(list.size(), 3)
	chips.visible = _reply_count > 0 and state == "input"


func choose_reply(text: String) -> void:
	if state != "input":
		return
	input.text = text
	reply_chosen.emit(text)
	_send()


## Your line, typed out in your voice next to your face for `emotion`.
func show_player_line(text: String, emotion: String = "neutral") -> void:
	you_label.text = "You: " + text
	you_face.texture = player_textures.get(emotion, player_textures.get("neutral", null))
	if _speed() <= 0.0:
		you_label.visible_characters = -1
		return
	_you_shown = 5.0  # "You: " appears at once
	you_label.visible_characters = 5
	_you_typing = true


func set_thinking() -> void:
	state = "thinking"
	_set_portrait("thinking")
	text_label.text = ""
	input_row.visible = false
	chips.visible = false
	arrow.visible = false


func _next_segment() -> void:
	if _queue.is_empty():
		_enter_input()
		return
	var seg: Dictionary = _queue.pop_front()
	_finish_you_line()  # never two voices at once
	_set_portrait(str(seg.get("emotion", "neutral")))
	segment_started.emit(str(seg.get("emotion", "neutral")))
	_wiggle_portrait(str(seg.get("emotion", "neutral")))
	text_label.text = SymbolFont.displayable(str(seg.get("text", "")))
	text_label.visible_characters = 0
	_shown = 0.0
	_pause = 0.0
	_last_blip_char = -1
	state = "typing"
	_drop_keyboard()
	input_row.visible = false
	chips.visible = false
	arrow.visible = false
	if _speed() <= 0.0:
		_finish_typing()


func _enter_input() -> void:
	if not chat_enabled:
		close_box()
		return
	state = "input"
	input_row.visible = true
	chips.visible = _reply_count > 0
	arrow.visible = false
	input.editable = true
	var phone := _phone()
	if phone and TouchGestures.phone_layout() and phone.uses_page_keyboard():
		# Phones open their keyboard reliably for a real page input (see phone_mode.gd).
		phone.show_keyboard("Say something...", func(text: String):
			input.text = text
			_send())
		if OS.has_feature("web"):
			# That bar sits at the bottom of the page: our own field would hide under it,
			# so keep only Save / Gift / Bye and lift the box above the bar.
			input.visible = false
			send_btn.visible = false
			var lift := float(phone.keyboard_cover()) * size.y
			if absf(lift - _kb_lift) > 1.0:
				_kb_lift = lift
				_fit_box()
	else:
		input.visible = true
		send_btn.visible = true
		if not OS.has_feature("android"):   # the app: tapping the field opens Android's keyboard (not on every turn)
			input.call_deferred("grab_focus")


func _phone() -> Node:
	var m: Node = get_tree().current_scene if is_inside_tree() else null
	return m.get("phone") if m else null


func _speed() -> float:
	var s := float(GameState.settings.get("text_speed", 45))
	return 0.0 if s >= 120.0 else s * float(voice.get("speed", 1.0))


func _finish_you_line() -> void:
	_you_typing = false
	you_label.visible_characters = -1


func _process(delta: float) -> void:
	_t += delta
	if _you_typing:
		var before := int(_you_shown)
		_you_shown += delta * float(GameState.settings.get("text_speed", 45)) * 1.6 * float(player_voice.get("speed", 1.0))
		var n := mini(int(_you_shown), you_label.text.length())
		you_label.visible_characters = n
		if n != before and n % 2 == 0 and you_label.text.substr(n - 1, 1) != " ":
			_play_voice(_you_blip, player_voice)
		if n >= you_label.text.length():
			_finish_you_line()
	if state == "thinking":
		text_label.text = ".".repeat(1 + int(_t * 3.0) % 3)
	elif state == "typing":
		if _pause > 0.0:
			_pause -= delta
			return
		_shown += delta * _speed()
		var n := mini(int(_shown), text_label.text.length())
		if n != text_label.visible_characters:
			text_label.visible_characters = n
			var ch := text_label.text.substr(n - 1, 1) if n > 0 else ""
			if ch in [".", "!", "?", "…"]:
				_pause = 0.16
			if n % 2 == 0 and ch != " " and n != _last_blip_char:
				_play_blip()
				_last_blip_char = n
		if n >= text_label.text.length():
			_finish_typing()
	elif state == "waiting":
		arrow.modulate.a = 0.4 + 0.6 * absf(sin(_t * 4.0))


func _play_blip() -> void:
	_play_voice(_blip, voice)


func _play_voice(player: AudioStreamPlayer, v: Dictionary) -> void:
	if not GameState.settings.get("text_blips", true):
		return
	player.pitch_scale = clampf(float(v.get("pitch", 1.0)), 0.5, 2.0) * randf_range(0.95, 1.05)
	player.volume_db = linear_to_db(maxf(0.001, float(GameState.settings.get("sfx_volume", 0.8)) * 0.6))
	player.play()


func _finish_typing() -> void:
	text_label.visible_characters = -1
	state = "waiting"
	arrow.visible = true
	if _queue.is_empty() and chat_enabled:
		_enter_input()


## Click / confirm: finish the line, show the next one, or close a sign.
func advance() -> void:
	match state:
		"typing":
			_finish_typing()
		"waiting":
			if _queue.is_empty():
				_enter_input()
			else:
				_next_segment()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("confirm") and not InputSetup.typing(get_viewport()):
		advance()
		get_viewport().set_input_as_handled()


func _send() -> void:
	var text := input.text.strip_edges()
	if text == "" or state != "input":
		return
	input.text = ""
	set_replies([])
	_drop_keyboard()
	show_player_line(text, Feelings.guess(text))
	sent.emit(text)


## Not your turn any more: the phone page's text bar goes away until it is.
func _drop_keyboard() -> void:
	var phone := _phone()
	if phone:
		phone.hide_keyboard()


func close_box() -> void:
	if not visible:
		return
	visible = false
	state = "hidden"
	_queue.clear()
	if _phone():
		_phone().hide_keyboard()
	input.release_focus()
	if _kb_lift > 0.0:
		_kb_lift = 0.0
		_fit_box()
	closed.emit()
