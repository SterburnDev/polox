extends Control
## A moment's title: a few big words that fade in over the scene and away again ("Home.", your street's name,
## "The Dream World", "Welcome back"). Never blocks a tap (the Moment underneath takes the skip), and is just a
## quicker fade under Reduce motion.

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

signal done

static var shown: Array = []   # (tests) titles shown, newest last

var _title: Label
var _sub: Label


## Shows `title` (and a quieter `sub`) on the toast layer for about `hold` seconds. Returns the card.
static func play(main: Node, title: String, sub: String = "", hold: float = 1.6) -> Control:
	var card: Control = load("res://scripts/ui/title_card.gd").new()
	var host: Node = main.fly_layer() if main and main.has_method("fly_layer") else main
	host.add_child(card)
	card._run(title, sub, hold)
	shown.append(title)
	return card


func _run(title: String, sub: String, hold: float) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var phone := get_viewport_rect().size.x < 600.0 if is_inside_tree() else false
	_title = Label.new()
	_title.text = title
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 46 if phone else 56)
	_title.add_theme_color_override("font_color", ThemeBuilder.CREAM)
	_title.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.1, 0.85))
	_title.add_theme_constant_override("outline_size", 10)
	v.add_child(_title)
	if sub != "":
		_sub = Label.new()
		_sub.text = sub
		_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sub.add_theme_font_size_override("font_size", 22)
		_sub.add_theme_color_override("font_color", ThemeBuilder.YELLOW)
		_sub.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.1, 0.85))
		_sub.add_theme_constant_override("outline_size", 6)
		v.add_child(_sub)
	modulate.a = 0.0
	var quick := bool(GameState.settings.get("reduce_motion", false))
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.12 if quick else 0.5)
	tw.tween_interval(hold * (0.6 if quick else 1.0))
	tw.tween_property(self, "modulate:a", 0.0, 0.12 if quick else 0.7)
	tw.tween_callback(func():
		done.emit()
		queue_free())


## Gone at once (a skipped moment).
func dismiss() -> void:
	if is_queued_for_deletion():
		return
	done.emit()
	queue_free()
