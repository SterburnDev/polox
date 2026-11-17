extends Control
## The "more below" cue for a scroll page without a bar (ui_kit.gd page / hide_bar): a soft fade along
## the bottom edge and a small chevron, shown only while there's more to scroll to. Also gives the page
## Page Up / Page Down / Home / End while it has the focus inside it. Never takes a click.
## Tags: [GLASS_UI]

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const HEIGHT := 34.0

var _s: ScrollContainer


func watch(s: ScrollContainer) -> void:
	_s = s
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true   # (a scroll container resets its other children's layout: this one follows it by hand)
	s.get_v_scroll_bar().value_changed.connect(func(_v): _update())
	s.get_v_scroll_bar().changed.connect(_update)
	s.resized.connect(_update)
	_update.call_deferred()
	set_process_input(true)


func more() -> bool:
	if _s == null:
		return false
	var bar := _s.get_v_scroll_bar()
	return bar.max_value - bar.page > 2.0 and bar.value < bar.max_value - bar.page - 2.0


func _update() -> void:
	visible = more()
	_place()
	queue_redraw()


func _place() -> void:
	if _s == null or not _s.is_inside_tree():
		return
	var at := _s.global_position + Vector2(0, _s.size.y - HEIGHT)
	if global_position != at or size != Vector2(_s.size.x, HEIGHT):
		global_position = at
		size = Vector2(_s.size.x, HEIGHT)


func _process(_delta: float) -> void:
	if visible:
		_place()   # (the page moves: a sheet sliding up, a window resized)


func _draw() -> void:
	var w := size.x
	var bg := ThemeBuilder.PANEL
	for i in 8:
		var y := HEIGHT * i / 8.0
		draw_rect(Rect2(0, y, w, HEIGHT / 8.0 + 1.0), Color(bg, 0.85 * i / 7.0))
	var c := Vector2(w / 2.0, HEIGHT - 12.0)
	draw_polyline(PackedVector2Array([c + Vector2(-9, -4), c + Vector2(0, 4), c + Vector2(9, -4)]), Color(ThemeBuilder.AQUA, 0.9), 2.5, true)


func _input(event: InputEvent) -> void:
	if _s == null or not _s.is_visible_in_tree() or not event is InputEventKey or not event.pressed:
		return
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not _s.is_ancestor_of(f) or f is LineEdit or f is TextEdit:
		return
	var bar := _s.get_v_scroll_bar()
	match event.keycode:
		KEY_PAGEDOWN:
			_s.scroll_vertical += int(_s.size.y * 0.85)
		KEY_PAGEUP:
			_s.scroll_vertical -= int(_s.size.y * 0.85)
		KEY_HOME:
			_s.scroll_vertical = 0
		KEY_END:
			_s.scroll_vertical = int(bar.max_value)
		_:
			return
	get_viewport().set_input_as_handled()
