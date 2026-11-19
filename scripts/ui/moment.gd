extends Control
## A big moment (moving between places, a Dream Gate opening, falling into a Dream World, a
## battle starting...): animated, never an instant cut, and skippable with one tap, click or key.
## Settings > Accessibility > Reduce motion swaps every animation for a short fade (reduced()).
##
##   var m := Moment.begin(main)          # a full-screen catcher for the skip, with a small hint
##   if not await m.wait(0.6): ...        # true when skipped: jump straight to the end state
##   m.finish()

signal skipped

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

const FADE_S := 0.18   # what Reduce motion uses instead of an animation

var was_skipped := false
var hint: Label
var _waiting := false


static func reduced() -> bool:
	return bool(GameState.settings.get("reduce_motion", false))


## Starts a moment over everything (on main's top layer). Tests pass any Node with a tree.
static func begin(main: Node, show_hint: bool = true) -> Control:
	var m: Control = load("res://scripts/ui/moment.gd").new()
	var host: Node = main.toast_layer() if main and main.has_method("toast_layer") else main
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	if host is CanvasLayer:
		host.add_child(m)
	elif host:
		host.add_child(m)
	if show_hint:
		m.hint = Label.new()
		m.hint.text = "Tap to skip"
		m.hint.add_theme_font_size_override("font_size", 16)
		m.hint.add_theme_color_override("font_color", Color(ThemeBuilder.CREAM, 0.7))
		m.add_child(m.hint)
		m.hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 84)
	return m


## Waits `seconds` (or until skipped). Returns true when it was skipped.
func wait(seconds: float) -> bool:
	if was_skipped or not is_inside_tree():
		return was_skipped
	_waiting = true
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0) and not was_skipped and is_inside_tree():
		await get_tree().process_frame
	_waiting = false
	return was_skipped


func skip() -> void:
	if not was_skipped:
		was_skipped = true
		skipped.emit()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION) or (event is InputEventScreenTouch and event.pressed):
		skip()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		skip()
		get_viewport().set_input_as_handled()


func finish() -> void:
	queue_free()
