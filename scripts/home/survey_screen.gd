extends Control
## The Survey: the first time you step into the Light World the screen goes black and a voice asks
## about your home (survey_data.gd). Slow typed text, its song (the Survey theme in Settings > Music:
## the Light World creation cue's song, or its own low hum), a heart for a cursor. One tap finishes
## a line, the next goes on; SKIP passes any question; LEAVE ends it (the Light World starts as a plain
## room, and Settings > Light World > Map my home asks again later). The last screen says plainly what
## would leave this computer and to whom, and nothing does until you choose LOOK IT UP. Then the house
## draws itself in while the helper works (show_building / progress_line / show_plan).
##
## Mouse, touch or keys alone. Reduce motion: lines appear whole, the heart doesn't glide.

signal done(result: Dictionary)   # {"answers": {...}, "choice": "lookup" | "answers" | "skipped", "helper": ""}
signal back_requested
signal preview_chosen

const SurveyData := preload("res://scripts/home/survey_data.gd")
const Research := preload("res://scripts/home/research.gd")
const SketchView := preload("res://scripts/home/sketch_view.gd")
const Synth := preload("res://scripts/core/synth.gd")
const Moment := preload("res://scripts/ui/moment.gd")
const SurveyDraft := preload("res://scripts/home/survey_draft.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const MusicPlayer := preload("res://scripts/world/music_player.gd")

const WHITE := Color("#f4f0e8")
const YELLOW := Color("#ffe14d")
const RED := Color("#ff2a48")
const GREY := Color("#9a958c")
const CPS := 38.0                 # typed characters a second

var answers: Dictionary = {}
var step_i := -1
var choice := ""
var helper := "none"
var reduced := false
var finished := false
var available: Dictionary = {}    # Research.available() (tests can set it)

var _font: Font
var _big := 32
var _col: VBoxContainer
var _text: Label
var _hint: Label
var _area: VBoxContainer          # the choices / input
var _skip: Button
var _leave: Button
var _heart: Control
var _heart_target := Vector2.ZERO
var field: LineEdit
var _counts: Dictionary = {}
var _lines: Array = []
var _line_i := 0
var _typing := false
var _type_t := 0.0
var _waiting_tap := false
var _tune: AudioStreamPlayer   # the Survey's song, or its own hum
var _blip: AudioStreamPlayer
var _music: Node        # the music that was on (music_player.gd): it waits while the Survey's tune plays
var _sketch: Control
var _progress: Label
var _history: Array = []          # step indices visited (GO BACK)
var _back: Button
var _draft_text: Dictionary = {}
var _draft_dirty := false
var _draft_wait := 0.0
var _completed := false


class Heart extends Control:
	func _draw() -> void:
		var s := size.x / 9.0
		var px := [[1, 0], [2, 0], [6, 0], [7, 0], [0, 1], [1, 1], [2, 1], [3, 1], [5, 1], [6, 1], [7, 1], [8, 1],
			[0, 2], [1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [8, 2], [0, 3], [1, 3], [2, 3], [3, 3], [4, 3], [5, 3], [6, 3], [7, 3], [8, 3],
			[1, 4], [2, 4], [3, 4], [4, 4], [5, 4], [6, 4], [7, 4], [2, 5], [3, 5], [4, 5], [5, 5], [6, 5], [3, 6], [4, 6], [5, 6], [4, 7]]
		for p in px:
			draw_rect(Rect2(Vector2(p[0], p[1]) * s, Vector2(s, s)), Color("#ff2a48"))


func _ready() -> void:
	add_to_group("survey_flow")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	reduced = Moment.reduced()
	if available.is_empty():
		available = Research.available()
	_font = preload("res://scripts/ui/theme_builder.gd").survey_font()   # (the same typewriter the title and world creation use)
	_big = 32   # (phones: the canvas is ~600 px wide, so this is about 20 px on the screen)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := ScrollContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 28
	center.offset_right = -28
	center.offset_top = 90
	center.offset_bottom = -120
	center.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.scroll_deadzone = 16
	add_child(center)
	_col = VBoxContainer.new()
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_col.add_theme_constant_override("separation", 22)
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_col)
	_text = _label(_big, WHITE)
	_text.custom_minimum_size = Vector2(0, _big * 3.2)
	_col.add_child(_text)
	_hint = _label(int(_big * 0.62), GREY)
	_hint.visible = false
	_col.add_child(_hint)
	_area = VBoxContainer.new()
	_area.add_theme_constant_override("separation", 10)
	_col.add_child(_area)
	_heart = Heart.new()
	_heart.size = Vector2(_big * 0.8, _big * 0.8)
	_heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heart.visible = false
	add_child(_heart)
	_skip = _plain_button("SKIP ›", func(): _skip_step())
	_skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.offset_left = -190
	_skip.offset_top = -24 - UiKit.touch_target()
	_skip.offset_right = -24
	_skip.offset_bottom = -24
	_skip.visible = false
	add_child(_skip)
	_leave = _plain_button("LEAVE", func(): _finish("skipped"))
	_leave.position = Vector2(20, 18)
	add_child(_leave)
	_back = _plain_button("GO BACK", on_back)
	_back.name = "SurveyBack"
	_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_back.offset_left = 24
	_back.offset_top = -24 - UiKit.touch_target()
	_back.offset_right = 210
	_back.offset_bottom = -24
	add_child(_back)
	if bool(available.get("claude_code", false)) and Research.sign_in_state == -1:
		_check_sign_in.call_deferred()
	var main: Node = get_tree().current_scene
	_music = main.music_now() if main and main.has_method("music_now") else null
	if _music:
		_music.hold()   # (Map my home from the Light World: Festival waits for the Survey's tune)
	_tune = AudioStreamPlayer.new()
	var song := MusicPlayer.theme_path("survey")
	if song != "":
		_tune.stream = MusicPlayer.load_stream(song)
		_tune.playback_type = AudioServer.PLAYBACK_TYPE_STREAM   # (streamed in the browser too, as in music_player.gd)
		_tune.volume_db = MusicPlayer.song_db() + MusicPlayer.gain_db(song)
	elif MusicPlayer.theme("survey") == MusicPlayer.OWN_TUNE:
		_tune.stream = drone()
		_tune.volume_db = linear_to_db(maxf(0.0001, float(GameState.settings.get("music_volume", 0.7)) * 0.35))
	add_child(_tune)
	if _tune.stream:
		var loud := _tune.volume_db
		_tune.volume_db = -40.0
		_tune.play()
		create_tween().tween_property(_tune, "volume_db", loud, 1.2)   # (in while the world's song fades out)
	_blip = AudioStreamPlayer.new()
	_blip.stream = Synth.get_sound("blip")
	_blip.pitch_scale = 0.55
	_blip.volume_db = linear_to_db(maxf(0.0001, float(GameState.settings.get("sfx_volume", 0.8)) * 0.35))
	add_child(_blip)
	var draft := SurveyDraft.read()
	if not draft.is_empty():
		answers = draft.answers
		step_i = int(draft.step)
		_history = draft.history
		_draft_text = draft.text
		helper = str(draft.helper)
		_show_step()
	else:
		if answers.is_empty() and HomeStore.exists():
			answers = HomeStore.load_home().get("answers", {}).duplicate(true)
			helper = str(answers.get("helper", "none"))
		next_step()


func _label(fs: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _plain_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", int(_big * 0.6))
	b.add_theme_color_override("font_color", GREY)
	b.add_theme_color_override("font_hover_color", WHITE)
	b.add_theme_color_override("font_focus_color", WHITE)
	b.custom_minimum_size = Vector2(140, UiKit.touch_target())
	b.pressed.connect(cb)
	return b


## A choice: white, yellow when the heart is on it.
func _option(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", _big)
	b.add_theme_color_override("font_color", WHITE)
	b.add_theme_color_override("font_hover_color", YELLOW)
	b.add_theme_color_override("font_focus_color", YELLOW)
	b.add_theme_color_override("font_pressed_color", YELLOW)
	b.custom_minimum_size = Vector2(0, maxf(UiKit.touch_target(), _big * 1.7))
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = _big * 1.4
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): _point_at(b))
	return b


func _point_at(c: Control, beside: bool = false) -> void:
	_heart.visible = true
	_heart_target = c.global_position + Vector2(-_big * 1.1 if beside else _big * 0.25, (c.size.y - _heart.size.y) / 2.0)
	if reduced or not _heart.visible:
		_heart.global_position = _heart_target


func _process(delta: float) -> void:
	if _draft_dirty:
		_draft_wait += delta
		if _draft_wait >= 0.4:
			_save_draft()
	# The heart follows whatever choice has focus (layouts settle a frame after a question appears).
	var fo := get_viewport().gui_get_focus_owner()
	if fo and is_instance_valid(fo) and _area.is_ancestor_of(fo) and fo.is_visible_in_tree():
		var beside := bool(fo.get_meta("heart_beside", false))
		var target := fo.global_position + Vector2(-_big * 1.1 if beside else _big * 0.25, (fo.size.y - _heart.size.y) / 2.0)
		if fo is LineEdit:
			target = fo.global_position + Vector2(-_big * 1.1, (fo.size.y - _heart.size.y) / 2.0)
		if fo.get_parent() is HBoxContainer and fo.get_parent().get_parent() is GridContainer:
			var row: Control = fo.get_parent()
			target = row.global_position + Vector2(-_big * 1.1, (row.size.y - _heart.size.y) / 2.0)
		_heart_target = target
		_heart.visible = true
	if _heart.visible:
		_heart.global_position = _heart.global_position.lerp(_heart_target, 1.0 if reduced else minf(1.0, delta * 18.0))
	if not _typing:
		return
	var line: String = _lines[_line_i]
	_type_t += delta
	var before := _text.visible_characters
	var n := int(_type_t * CPS)
	_text.visible_characters = mini(n, line.length())
	if _text.visible_characters != before and _text.visible_characters % 2 == 0 and _text.visible_characters < line.length():
		var ch := line[_text.visible_characters - 1]
		if ch != " " and ch != ".":
			_blip.pitch_scale = 0.5 + randf() * 0.1
			_blip.play()
	if _text.visible_characters >= line.length():
		_typing = false
		_line_done()


# --- Steps ------------------------------------------------------------------------------------------

func step() -> Dictionary:
	return SurveyData.STEPS[step_i] if step_i >= 0 and step_i < SurveyData.STEPS.size() else {}


func next_step() -> void:
	if finished:
		return
	if step_i >= 0:
		_capture_input()
		_history.append(step_i)
	step_i += 1
	while step_i < SurveyData.STEPS.size() and not SurveyData.applies(SurveyData.STEPS[step_i], answers):
		step_i += 1
	if step_i >= SurveyData.STEPS.size():
		_finish("answers")
		return
	_show_step()
	_save_draft()


func _show_step() -> void:
	var s := step()
	for c in _area.get_children():
		_area.remove_child(c)
		c.queue_free()
	_heart.visible = false
	_hint.visible = false
	field = null
	_counts = {}
	_back.visible = true
	_back.disabled = _history.is_empty()
	_skip.visible = str(s.kind) != "say" and str(s.kind) != "consent"
	if str(s.kind) == "helper" and _helper_options().size() <= 1:
		# Nobody else is here to look: the answers will do.
		helper = "none"
		_lines = ["NOBODY ELSE IS HERE TO LOOK.", "YOUR ANSWERS WILL DO."]
	else:
		_lines = (s.get("lines", []) as Array).duplicate()
	_line_i = 0
	_type_line()


func _type_line() -> void:
	_text.text = str(_lines[_line_i])
	_type_t = 0.0
	_waiting_tap = false
	if reduced:
		_text.visible_characters = -1
		_typing = false
		_line_done()
	else:
		_text.visible_characters = 0
		_typing = true


## A line is all there: more lines wait for a tap; the last one shows the question's choices.
func _line_done() -> void:
	if _line_i < _lines.size() - 1 or str(step().kind) == "say" or (str(step().kind) == "helper" and _helper_options().size() <= 1):
		_waiting_tap = true
		return
	_build_inputs()


func _tap() -> void:
	if _typing:
		_typing = false
		_text.visible_characters = -1
		_line_done()
		return
	if not _waiting_tap:
		return
	if _line_i < _lines.size() - 1:
		_line_i += 1
		_type_line()
	else:
		next_step()


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = UiKit.tap_down(event)
	if pressed:
		_tap()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back") or event.is_action_pressed("ui_cancel"):
		on_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and (_typing or _waiting_tap):
		_tap()
		get_viewport().set_input_as_handled()


func _skip_step() -> void:
	if finished:
		return
	if str(step().kind) == "text" and field:
		field.release_focus()
	next_step()


func _answer(value: Variant) -> void:
	var s := step()
	if str(s.get("key", "")) != "":
		SurveyData.set_answer(answers, str(s.key), value)
		_draft_text.erase(str(s.key))
	if str(s.get("key", "")) == "address":
		answers["address_level"] = SurveyData.address_level(str(value))
	Synth.play(self, "click", 0.4)
	next_step()


func _build_inputs() -> void:
	var s := step()
	if str(s.get("hint", "")) != "":
		_hint.text = str(s.hint)
		_hint.visible = true
	var first: Control = null
	match str(s.kind):
		"choice":
			for o in s.options:
				var b := _option(str(o[1]), func(): _answer(o[0]))
				_area.add_child(b)
				if first == null or SurveyData.get_answer(answers, str(s.key)) == o[0]:
					first = b
				if SurveyData.get_answer(answers, str(s.key)) == o[0]:
					b.add_theme_color_override("font_color", YELLOW)
		"text":
			field = LineEdit.new()
			field.placeholder_text = str(s.get("placeholder", ""))
			field.add_theme_font_override("font", _font)
			field.add_theme_font_size_override("font_size", int(_big * 0.8))
			field.add_theme_color_override("font_color", WHITE)
			field.add_theme_color_override("font_placeholder_color", Color(GREY, 0.6))
			field.add_theme_color_override("caret_color", YELLOW)
			var line := StyleBoxFlat.new()
			line.bg_color = Color(1, 1, 1, 0.04)
			line.border_color = WHITE
			line.border_width_bottom = 2
			line.content_margin_left = 10
			line.content_margin_top = 8
			line.content_margin_bottom = 8
			for st in ["normal", "focus", "read_only"]:
				field.add_theme_stylebox_override(st, line)
			field.custom_minimum_size = Vector2(0, maxf(UiKit.touch_target(), _big * 1.8))
			field.max_length = 600 if bool(s.get("long", false)) else 160
			var saved: Variant = SurveyData.get_answer(answers, str(s.key))
			field.text = str(_draft_text.get(str(s.key), "" if saved == null else str(saved)))
			field.text_changed.connect(func(t):
				_draft_text[str(s.key)] = t
				_draft_dirty = true)
			if bool(s.get("number", false)):
				field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
			field.text_submitted.connect(func(t): _submit_text(t))
			_area.add_child(field)
			var ok := _option("THAT'S IT", func(): _submit_text(field.text))
			_area.add_child(ok)
			first = field
		"counts":
			_counts = {}
			var saved: Variant = SurveyData.get_answer(answers, str(s.key))
			for o in s.options:
				_counts[str(o[0])] = clampi(int(saved.get(str(o[0]), o[2])), 0, 8) if saved is Dictionary else int(o[2])
			var grid := GridContainer.new()
			grid.columns = 2 if get_viewport_rect().size.x > 700.0 else 1
			var pad := MarginContainer.new()
			pad.add_theme_constant_override("margin_left", int(_big * 1.4))
			grid.add_theme_constant_override("h_separation", 24)
			for o in s.options:
				grid.add_child(_count_row(str(o[0]), str(o[1])))
			pad.add_child(grid)
			_area.add_child(pad)
			var done_b := _option("THAT'S ALL OF THEM", func(): _answer(_counts.duplicate()))
			_area.add_child(done_b)
			first = done_b
		"color":
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 12)
			flow.add_theme_constant_override("v_separation", 12)
			for sw in SurveyData.WALL_SWATCHES:
				var b := _swatch(Color(str(sw[0])), str(sw[1]), func(): _answer(str(sw[0])))
				flow.add_child(b)
				if first == null or SurveyData.get_answer(answers, str(s.key)) == sw[0]:
					first = b
			_area.add_child(flow)
		"picture":
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 14)
			row.add_theme_constant_override("v_separation", 14)
			for o in s.options:
				var b := _floor_pick(str(o[0]), str(o[1]), func(): _answer(str(o[0])))
				row.add_child(b)
				if first == null or SurveyData.get_answer(answers, str(s.key)) == o[0]:
					first = b
			_area.add_child(row)
		"helper":
			for o in _helper_options():
				var b := _option(str(o[1]), func():
					helper = str(o[0])
					_answer(str(o[0])))
				b.name = "Helper_" + str(o[0])
				_area.add_child(b)
				if first == null or helper == str(o[0]):
					first = b
		"consent":
			_build_consent()
			return
	if first:
		_focus_later.call_deferred(first.get_instance_id())


func _focus_later(id: int) -> void:
	var control := instance_from_id(id) as Control
	if control and control.is_inside_tree() and not control.is_queued_for_deletion():
		control.grab_focus()


func _submit_text(t: String) -> void:
	var s := step()
	var v := t.strip_edges()
	if v == "":
		SurveyData.set_answer(answers, str(s.key), "")
		next_step()
		return
	if bool(s.get("number", false)):
		if v.length() == 4 and v.is_valid_int() and int(v) > 1600 and int(v) <= Time.get_date_dict_from_system().year:
			_answer(int(v))
		else:
			_hint.text = "Enter a four-digit year from 1601 to this year, or leave it blank."
			_hint.visible = true
		return
	_answer(v)


func _count_row(key: String, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := _label(int(_big * 0.75), WHITE)
	l.text = label
	l.custom_minimum_size = Vector2(_big * 7.5, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	var n := _label(int(_big * 0.8), YELLOW)
	n.text = str(_counts[key])
	n.custom_minimum_size = Vector2(_big * 1.4, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var minus := _plain_button("−", func():
		_counts[key] = maxi(0, int(_counts[key]) - 1)
		n.text = str(_counts[key])
		_draft_dirty = true)
	var plus := _plain_button("+", func():
		_counts[key] = mini(8, int(_counts[key]) + 1)
		n.text = str(_counts[key])
		_draft_dirty = true)
	for b in [minus, plus]:
		b.custom_minimum_size = Vector2(UiKit.touch_target(), UiKit.touch_target())
		b.add_theme_font_size_override("font_size", _big)
		b.focus_entered.connect(func(): _point_at(row, true))
		b.mouse_entered.connect(func(): _point_at(row, true))
	minus.name = "Minus_" + key
	plus.name = "Plus_" + key
	row.add_child(minus)
	row.add_child(n)
	row.add_child(plus)
	return row


func _swatch(c: Color, label: String, cb: Callable) -> Button:
	var b := _option("", cb)
	b.custom_minimum_size = Vector2(_big * 3.2, _big * 3.2)
	b.tooltip_text = label
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 0
	var sbf := sb.duplicate() as StyleBoxFlat
	sbf.border_color = YELLOW
	sbf.set_border_width_all(4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbf)
	b.add_theme_stylebox_override("focus", sbf)
	b.add_theme_stylebox_override("pressed", sbf)
	b.name = "Swatch_" + label
	b.set_meta("heart_beside", true)
	return b


## A floor to pick: a little drawing of it (planks, carpet, tiles, vinyl) with its name.
func _floor_pick(kind: String, label: String, cb: Callable) -> Button:
	var b := _option(label, cb)
	b.custom_minimum_size = Vector2(_big * 6.0, _big * 5.0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var plain := StyleBoxEmpty.new()
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(1, 1, 1, 0.04)
	ring.border_color = YELLOW
	ring.set_border_width_all(3)
	ring.set_corner_radius_all(6)
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, plain)
	for st in ["hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(st, ring)
	b.icon = ImageTexture.create_from_image(floor_image(kind, 96))
	b.expand_icon = false
	b.name = "Floor_" + kind
	b.set_meta("heart_beside", true)
	return b


static func floor_image(kind: String, s: int) -> Image:
	var img := Image.create(s, s * 3 / 4, false, Image.FORMAT_RGBA8)
	var h := s * 3 / 4
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"wood":
			var plank := h / 5
			for z in 5:
				var base := Color("#c9a27a").darkened(rng.randf_range(0.0, 0.18))
				img.fill_rect(Rect2i(0, z * plank, s, plank - 1), base)
				img.fill_rect(Rect2i(0, z * plank + plank - 1, s, 1), Color("#7a5a3c"))
				var cut := rng.randi_range(10, s - 10)
				img.fill_rect(Rect2i(cut, z * plank, 1, plank), Color("#7a5a3c"))
		"carpet":
			img.fill(Color("#b9ab9b"))
			for i in s * h / 6:
				img.set_pixel(rng.randi_range(0, s - 1), rng.randi_range(0, h - 1), Color("#b9ab9b").darkened(rng.randf_range(0.05, 0.2)))
		"tile":
			img.fill(Color("#d9d5cd"))
			var t := s / 4
			for i in range(0, s, t):
				img.fill_rect(Rect2i(i, 0, 2, h), Color("#9a958c"))
			for j in range(0, h, t):
				img.fill_rect(Rect2i(0, j, s, 2), Color("#9a958c"))
		_:
			img.fill(Color("#cbbfa8"))
			for z in range(0, h, h / 6):
				img.fill_rect(Rect2i(0, z, s, 1), Color("#cbbfa8").darkened(0.1))
	return img


func _helper_options() -> Array:
	var out: Array = []
	for h in Research.HELPERS:
		if bool(available.get(h, false)):
			var label := str({"claude_code": "CLAUDE, ON THIS COMPUTER", "claude_api": "CLAUDE, WITH MY KEY", "gemini": "GEMINI", "none": "NOBODY. JUST MY ANSWERS."}.get(h, str(Research.HELPER_LABELS.get(h, h)).to_upper()))
			if h == "claude_code" and Research.sign_in_state == 0:
				label += " (SIGN IN FIRST)"
			out.append([h, label])
	return out


## The plain screen: exactly what would be sent, to whom, and the choice.
func _build_consent() -> void:
	_skip.visible = false
	var addr := str(answers.get("address", "")).strip_edges()
	var radius := int(answers.get("radius", 250))
	var coords: bool = not load("res://scripts/home/osm.gd").parse_coords(addr).is_empty()
	var lines: PackedStringArray = []
	var active := SurveyData.active_answers(answers)
	lines.append("Your home: %s, %d floor(s). Your room, colours and furniture choices will be kept." % [str(active.get("home_type", "home")), int(active.get("floors", 1))])
	var unused := SurveyData.inactive_keys(answers)
	if not unused.is_empty():
		lines.append("Saved for a different answer, not used now: " + ", ".join(unused) + ". Go back to change them.")
	if HomeStore.exists():
		lines.append("This rebuilds your mapped rooms. Your manual edits stay on top; a snapshot lets you roll back.")
	lines.append("If you choose Look it up, Polox will send:")
	if helper != "none":
		lines.append("  •  to %s:" % str(Research.WHO.get(helper, "")))
		lines.append("      the address you typed (\"%s\") and what you said about the building (the kind of home, floors, rooms, the year it was built)." % addr)
		lines.append("      It looks through public records for building facts only: the county assessor's record and building sketch, building permits, the parcel map, listings and archived pages. Names of people are never kept.")
		if helper == "claude_code":
			lines.append("      It uses your own Claude sign-in and counts toward your Claude plan (capped at about $%s of use)." % Research.MAX_BUDGET_USD)
			if Research.sign_in_state != 1:
				lines.append("      If Claude Code isn't signed in, SIGN IN TO CLAUDE opens its own sign-in window (in your browser). Polox never sees your account.")
	lines.append("  •  to OpenStreetMap: where your home is (as map coordinates) and how far to map (%d m), for the map of your streets." % radius)
	if not coords:
		lines.append("      To find those coordinates%s, OpenStreetMap's search (Nominatim) gets the address." % (" if the helper doesn't" if helper != "none" else ""))
	lines.append("")
	lines.append("Your memories and the rest of your answers aren't sent. Everything that comes back stays in Documents\\Polox\\my_home on this computer.")
	var body := Label.new()
	body.text = "\n".join(lines)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", int(_big * 0.62))
	body.add_theme_color_override("font_color", WHITE)
	body.name = "ConsentText"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := ScrollContainer.new()
	box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.custom_minimum_size = Vector2(0, get_viewport_rect().size.y * 0.4)
	box.scroll_deadzone = 16
	box.add_child(body)
	_area.add_child(box)
	if helper != "none" and helper != "manual" and addr != "":
		# Word for word, the question the helper would get (the copy/paste helper shows its own).
		var exact := _option("SHOW EXACTLY WHAT'S SENT", func():
			if not body.text.contains("WORD FOR WORD"):
				body.text += "\n\nWORD FOR WORD, TO %s:\n%s" % [str(Research.short_name(helper)).to_upper(), load("res://scripts/home/research_prompt.gd").question(addr, SurveyData.building_answers(answers))])
		exact.name = "ShowPayload"
		_area.add_child(exact)
	var look := _option("LOOK IT UP", func():
		preload("res://scripts/ui/haptics.gd").confirm()
		_finish("lookup"))
	look.name = "LookItUp"
	look.visible = addr != ""
	_area.add_child(look)
	if helper == "claude_code" and Research.sign_in_state != 1 and bool(available.get("claude_code", false)):
		var sign := _option("SIGN IN TO CLAUDE", func(): _sign_in())
		sign.name = "SignInClaude"
		sign.visible = Research.sign_in_state == 0
		_area.add_child(sign)
		_area.move_child(sign, look.get_index())
	var mine := _option("JUST USE MY ANSWERS", func(): _finish("answers"))
	mine.name = "JustMyAnswers"
	_area.add_child(mine)
	_focus_later.call_deferred((look if look.visible else mine).get_instance_id())


## Asks Claude Code whether it's signed in (in the background; the answer shows on the helper and consent steps).
func _check_sign_in() -> void:
	var r: Node = Research.new()
	add_child(r)
	await r.check_sign_in()
	r.queue_free()
	if not is_inside_tree() or finished or _area == null:
		return
	var sign: Control = _area.find_child("SignInClaude", false, false)
	if sign:
		sign.visible = Research.sign_in_state == 0
	var option: Button = _area.find_child("Helper_claude_code", false, false)
	if option:
		for o in _helper_options():
			if str(o[0]) == "claude_code":
				option.text = str(o[1])


## SIGN IN TO CLAUDE: Claude Code's own sign-in window, then a check every few seconds until it's done.
func _sign_in() -> void:
	var sign: Button = _area.find_child("SignInClaude", false, false)
	if not Research.open_sign_in():
		_hint.text = "CLAUDE CODE COULDN'T OPEN ITS SIGN-IN. IN A TERMINAL: claude auth login"
		_hint.visible = true
		return
	if sign:
		sign.text = "WAITING FOR THE SIGN-IN..."
		sign.disabled = true
	var r: Node = Research.new()
	add_child(r)
	var ok: bool = await r.wait_for_sign_in(5.0)
	r.queue_free()
	if not is_inside_tree() or finished:
		return
	if sign and is_instance_valid(sign):
		sign.text = "SIGNED IN. READY." if ok else "SIGN IN TO CLAUDE"
		sign.disabled = ok


func _go_back() -> void:
	if _history.is_empty():
		return
	_capture_input()
	step_i = int(_history.pop_back())
	while not _history.is_empty() and not SurveyData.applies(step(), answers):
		step_i = int(_history.pop_back())
	_show_step()
	_save_draft()


func on_back() -> void:
	if finished:
		back_requested.emit()
	else:
		_go_back()


func _capture_input() -> void:
	if field and is_instance_valid(field):
		_draft_text[str(step().get("key", ""))] = field.text
	if not _counts.is_empty() and str(step().get("kind", "")) == "counts":
		SurveyData.set_answer(answers, str(step().key), _counts.duplicate())


func _save_draft() -> void:
	if _completed or step_i < 0:
		return
	_capture_input()
	SurveyDraft.write(answers, step_i, _history, helper, _draft_text)
	_draft_dirty = false
	_draft_wait = 0.0


func complete_draft() -> void:
	_completed = true
	SurveyDraft.clear()


func resume_review() -> void:
	finished = false
	choice = ""
	step_i = SurveyData.STEPS.size() - 1
	_leave.visible = true
	_sketch = null
	_progress = null
	_show_step()
	_save_draft()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_save_draft()


func _exit_tree() -> void:
	_save_draft()
	# The Survey's song is let go here, not left to the player being freed: a game that closes on
	# the Survey would otherwise shut down with the song's file still in use (audio_exit.gd).
	preload("res://scripts/core/audio_exit.gd").release(_tune)
	if is_instance_valid(_music):
		_music.release()
		_music = null


func _finish(how: String) -> void:
	if finished:
		return
	_save_draft()
	finished = true
	choice = how
	_skip.visible = false
	_leave.visible = false
	for c in _area.get_children():
		_area.remove_child(c)
		c.queue_free()
	_heart.visible = false
	done.emit({"answers": SurveyData.active_answers(answers), "choice": how, "helper": helper if how == "lookup" else "none", "streets": how == "lookup"})


# --- Building -----------------------------------------------------------------------------------

## The house takes shape: a line of progress and the sketch, drawing itself in.
func show_building() -> void:
	_text.text = "THE HOUSE IS TAKING SHAPE."
	_text.visible_characters = -1
	_progress = _label(int(_big * 0.6), GREY)
	_progress.text = ""
	_area.add_child(_progress)
	_sketch = SketchView.new()
	_sketch.custom_minimum_size = Vector2(0, get_viewport_rect().size.y * 0.45)
	_sketch.reveal = 0.0
	_area.add_child(_sketch)


func show_preview(plan: Dictionary, lines: String) -> void:
	for c in _area.get_children():
		_area.remove_child(c)
		c.queue_free()
	_sketch = null
	_progress = null
	show_building()
	_text.text = "DOES THIS FEEL LIKE HOME?"
	_progress.text = lines
	_sketch.set_plan(plan)
	_sketch.reveal = 1.0
	_sketch.custom_minimum_size.y = get_viewport_rect().size.y * 0.28
	var keep := _option("KEEP THIS HOME", func(): preview_chosen.emit())
	keep.name = "KeepHomePreview"
	_area.add_child(keep)
	_back.disabled = false
	_back.visible = true
	_focus_later.call_deferred(keep.get_instance_id())


func progress_line(line: String) -> void:
	if _progress:
		_progress.text = line.to_upper()


## Draws the plan in, room by room (a tap shows it all). Returns when it's drawn.
func show_plan(plan: Dictionary) -> void:
	if _sketch == null:
		show_building()
	_sketch.set_plan(plan)
	var dur := 0.2 if reduced else 2.6
	var t := 0.0
	while t < dur and is_inside_tree():
		t += get_process_delta_time()
		_sketch.reveal = clampf(t / dur, 0.0, 1.0)
		_sketch.queue_redraw()
		if _typing == false and _waiting_tap:
			break
		await get_tree().process_frame
	_sketch.reveal = 1.0
	_sketch.queue_redraw()


## The last words, then the screen fades (the caller shows the room underneath).
func farewell(text: String = "WELCOME HOME.") -> void:
	_text.text = text
	_text.visible_characters = -1
	if _progress:
		_progress.text = ""
	var until := Time.get_ticks_msec() + int((0.3 if reduced else 1.4) * 1000.0)
	while Time.get_ticks_msec() < until and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2 if reduced else 0.9)
	tw.parallel().tween_property(_tune, "volume_db", -60.0, 0.2 if reduced else 0.9)
	var fade_until := Time.get_ticks_msec() + int((0.4 if reduced else 1.1) * 1000.0)
	while is_instance_valid(tw) and tw.is_running() and is_inside_tree() and Time.get_ticks_msec() < fade_until:
		await get_tree().process_frame


## The hum: two low tones beating slowly over a breath of noise (made in code, loops cleanly).
static func drone() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 6
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var y := 0.0
	for i in n:
		var t := float(i) / rate
		y += 0.02 * (rng.randf_range(-1.0, 1.0) - y)
		var v := sin(TAU * 55.0 * t) * 0.32 + sin(TAU * (55.0 + 1.0 / 6.0) * t + 0.4) * 0.26 + sin(TAU * 82.5 * t) * 0.08 + y * 0.9
		var s := int(clampf(v * 0.5, -1.0, 1.0) * 32767.0)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return Synth.looping(data, n, rate)
