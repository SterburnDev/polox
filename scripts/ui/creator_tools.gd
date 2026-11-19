extends VBoxContainer
## The Creator's tool column: tools, brush size, mirror, undo/redo, palette
## and custom color. Every control is a big button.
## Tags: [DRAWING]


const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

const PALETTE := [
	"#22183d", "#4a3426", "#c08a5a", "#f2c9a0",
	"#fffaf0", "#e86a8a", "#ffb3c7", "#c0392b",
	"#ff9f43", "#ffd166", "#7ad6b0", "#3f7a5a",
	"#2e86de", "#8fd3ff", "#c9b6ff", "#9a94b0",
]

var canvas: Control           # paint_canvas.gd
var _tool_buttons: Dictionary = {}
var _size_buttons: Array[Button] = []
var _current: ColorRect
var _picker: ColorPickerButton
var _undo_btn: Button
var _redo_btn: Button
var _mirror_btn: Button


func bind(paint: Control) -> void:
	canvas = paint
	canvas.changed.connect(_refresh)
	canvas.color_picked.connect(func(c): _set_color(c))
	add_theme_constant_override("separation", 8)
	custom_minimum_size.x = 214
	var tools := GridContainer.new()
	tools.columns = 2
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	for t in [["pencil", "Pencil"], ["eraser", "Eraser"], ["fill", "Fill"], ["picker", "Pick"]]:
		var b := UiKit.button(t[1], func(): _set_tool(t[0]), 100)
		b.toggle_mode = true
		_tool_buttons[t[0]] = b
		tools.add_child(b)
	add_child(tools)
	var sizes := UiKit.hbox(4)
	for n in [1, 2, 3, 4]:
		var b := UiKit.button(str(n), func(): _set_brush(n), 48)
		b.toggle_mode = true
		b.tooltip_text = "Brush size %d" % n
		_size_buttons.append(b)
		sizes.add_child(b)
	add_child(sizes)
	var hist := UiKit.hbox(6)
	_undo_btn = UiKit.button("↶ Undo", func(): canvas.undo(), 100)
	_redo_btn = UiKit.button("↷ Redo", func(): canvas.redo(), 100)
	hist.add_child(_undo_btn)
	hist.add_child(_redo_btn)
	add_child(hist)
	_mirror_btn = UiKit.button("Mirror: off", _toggle_mirror)
	_mirror_btn.tooltip_text = "Paint both halves at once (great for faces)"
	add_child(_mirror_btn)
	var pal := GridContainer.new()
	pal.columns = 4
	pal.add_theme_constant_override("h_separation", 4)
	pal.add_theme_constant_override("v_separation", 4)
	for hex in PALETTE:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(48, 48)  # big, easy targets
		sw.tooltip_text = hex
		sw.focus_mode = Control.FOCUS_NONE
		sw.add_theme_stylebox_override("normal", ThemeBuilder.box(Color(hex), Color(ThemeBuilder.CREAM, 0.3), 1, 4, 0))
		sw.add_theme_stylebox_override("hover", ThemeBuilder.box(Color(hex), ThemeBuilder.YELLOW, 2, 4, 0))
		sw.add_theme_stylebox_override("pressed", ThemeBuilder.box(Color(hex), Color.WHITE, 3, 4, 0))
		sw.pressed.connect(func(): _set_color(Color(hex)))
		pal.add_child(sw)
	add_child(pal)
	var cur := UiKit.hbox(6)
	_current = UiKit.color_swatch(canvas.color, 52)
	cur.add_child(_current)
	_picker = ColorPickerButton.new()
	_picker.text = "More colors"
	_picker.tooltip_text = "Pick any color"
	_picker.custom_minimum_size = Vector2(150, 52)
	_picker.edit_alpha = false
	_picker.color = canvas.color
	_picker.color_changed.connect(func(c): _set_color(c))
	cur.add_child(_picker)
	add_child(cur)
	_set_tool("pencil")
	_set_brush(1)



func _set_tool(t: String) -> void:
	canvas.tool = t
	for k in _tool_buttons:
		_tool_buttons[k].set_pressed_no_signal(k == t)


func _set_brush(n: int) -> void:
	canvas.brush = n
	for i in _size_buttons.size():
		_size_buttons[i].set_pressed_no_signal(i + 1 == n)


func _set_color(c: Color) -> void:
	canvas.color = c
	_current.color = c
	_picker.color = c
	if canvas.tool in ["eraser", "picker"]:
		_set_tool("pencil")


func _toggle_mirror() -> void:
	canvas.mirror = not canvas.mirror
	_mirror_btn.text = "Mirror: on" if canvas.mirror else "Mirror: off"
	canvas.queue_redraw()


func _refresh() -> void:
	_undo_btn.disabled = not canvas.can_undo()
	_redo_btn.disabled = not canvas.can_redo()
