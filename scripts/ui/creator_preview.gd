extends PanelContainer
## A mini dialogue box in the Creator that shows the face being drawn,
## live, with the character's name. "Play faces" cycles all expressions.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

var portrait: TextureRect
var name_label: Label
var line: Label
var play_btn: Button
var playing := false
var _t := 0.0
var _index := 0
## Returns [emotion names with pixels]; set by the Creator.
var faces: Callable
## Shows a face by name; set by the Creator.
var show_face: Callable


func _ready() -> void:
	add_theme_stylebox_override("panel", ThemeBuilder.box(Color(0.02, 0.01, 0.05), ThemeBuilder.CREAM, 3, 8, 6))
	var row := UiKit.hbox(12)
	add_child(row)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(76, 76)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(portrait)
	var col := UiKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	name_label = UiKit.label("", 22, ThemeBuilder.YELLOW)
	col.add_child(name_label)
	line = UiKit.para("", 18)
	col.add_child(line)
	play_btn = UiKit.button("▶ Play", _toggle, 100)
	play_btn.tooltip_text = "Cycle through all faces"
	play_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(play_btn)


func set_face(tex: Texture2D, display_name: String, emotion: String) -> void:
	portrait.texture = tex
	var who := display_name if display_name != "" else "???"
	name_label.text = who
	line.text = "(%s) Hi! I'm %s." % [emotion, who]


func _toggle() -> void:
	playing = not playing
	play_btn.text = "■ Stop" if playing else "▶ Play"
	_t = 0.0


func _process(delta: float) -> void:
	if not playing or not faces.is_valid():
		return
	_t += delta
	if _t >= 0.8:
		_t = 0.0
		var names: Array = faces.call()
		if names.is_empty():
			return
		_index = (_index + 1) % names.size()
		show_face.call(names[_index])
