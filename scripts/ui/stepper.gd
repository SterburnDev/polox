extends HBoxContainer
## A labelled value with − and + buttons, used instead of a slider (Settings has no sliders: they fight
## the page's own scrolling on a phone and are fiddly to set exactly). Holding − or + repeats. The
## value is a field too: type a number and press Enter (or leave the field) to set it directly.
## Keeps the same range and step as the slider it replaced; `value_changed` and `value` work the same.
## Tags: [GLASS_UI]

signal value_changed(value: float)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const TouchGestures := preload("res://scripts/ui/touch_gestures.gd")

var min_value := 0.0
var max_value := 1.0
var step := 0.1
var _v := 0.0
var value: float:
	get:
		return _v
	set(v):
		_set_value(v, false)
## How the value is shown ("70%", "45 letters/s"); typed numbers are read in the same units (`display_scale`).
var format := Callable()
var display_scale := 1.0      # e.g. 100 for a 0..1 value shown as a percentage

var minus: Button
var plus: Button
var field: LineEdit
var _hold := 0.0
var _held := 0                # -1 or +1 while a button is held
var _repeats := 0


static func make(lo: float, hi: float, stp: float, v: float, fmt: Callable = Callable(), scale: float = 1.0) -> HBoxContainer:
	var s: HBoxContainer = load("res://scripts/ui/stepper.gd").new()
	s.min_value = lo
	s.max_value = hi
	s.step = stp
	s.format = fmt
	s.display_scale = scale
	s._set_value(v, false)
	return s


func _init() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tap := UiKit.touch_target()
	minus = UiKit.button("−", func(): _step_on_release(-1), tap)
	minus.name = "Minus"
	minus.tooltip_text = "Less (hold to keep going)"
	plus = UiKit.button("+", func(): _step_on_release(1), tap)
	plus.name = "Plus"
	plus.tooltip_text = "More (hold to keep going)"
	field = UiKit.line_edit("", "")
	field.name = "Value"
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.custom_minimum_size = Vector2(150, tap)
	field.size_flags_horizontal = Control.SIZE_FILL
	field.select_all_on_focus = true
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	field.text_submitted.connect(func(_t): _typed())
	field.focus_exited.connect(_typed)
	add_child(minus)
	add_child(field)
	add_child(plus)
	for pair in [[minus, -1], [plus, 1]]:
		var b: Button = pair[0]
		var dir: int = pair[1]
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.gui_input.connect(_claim_touch_hold)
		b.button_down.connect(func():
			_held = dir
			_hold = 0.0
			_repeats = 0
			set_process(true))
		b.button_up.connect(func(): _held = 0)
	set_process(false)


func _ready() -> void:
	_show()


func _claim_touch_hold(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		get_tree().call_group(TouchGestures.INPUT_GROUP, &"claim_hold", get_viewport(), event.index)


func _process(delta: float) -> void:
	if _held == 0 or not (minus.button_pressed or plus.button_pressed):
		_held = 0
		set_process(false)
		return
	_hold += delta
	# Wait a moment, then repeat, faster the longer it's held.
	var every := 0.12 if _repeats < 8 else 0.05
	if _hold > 0.4 + every * _repeats:
		_repeats += 1
		nudge(_held)


func _step_on_release(dir: int) -> void:
	# The scroll container can cancel a press while the finger is still down.
	# A hold has already stepped the value by the time the button is released.
	if _repeats == 0:
		nudge(dir)
	_repeats = 0


## One step up (+1) or down (-1).
func nudge(dir: int) -> void:
	_set_value(_v + dir * step, true)
	if _held != 0:
		set_process(true)


func _typed() -> void:
	var digits := ""
	for ch in field.text:
		if ch in "0123456789.-":
			digits += ch
	if digits == "" or not digits.is_valid_float():
		_show()
		return
	_set_value(digits.to_float() / display_scale, true)


func _set_value(v: float, emit: bool) -> void:
	var snapped_v := clampf(snappedf(v, step) if step > 0.0 else v, min_value, max_value)
	var was := _v
	_v = snapped_v
	_show()
	if emit and not is_equal_approx(was, snapped_v):
		value_changed.emit(snapped_v)


func _show() -> void:
	if field == null:
		return
	var v := _v
	field.text = str(format.call(v)) if format.is_valid() else _plain(v)
	minus.disabled = v <= min_value + 0.00001
	plus.disabled = v >= max_value - 0.00001


func _plain(v: float) -> String:
	if is_equal_approx(step, roundf(step)):
		return str(roundi(v))
	return String.num(v, 2)
