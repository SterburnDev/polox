extends Button
## A banner at the top of the PC's screen, over the game or any menu: "Phone
## connecting: PIN 482 913" when a phone first reaches Phone Link, "Phone
## connected" / "paired" after. Click it (or tap) to open Settings > Phone
## Link. Goes away by itself after a while; a newer banner replaces it.

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

const SECONDS := 25.0

var on_open: Callable = Callable()
var _left := SECONDS


func show_text(text: String, hint: String = "Click to open Phone Link") -> void:
	text = text + ("\n" + hint if hint != "" else "")
	self.text = text
	_left = SECONDS
	visible = true
	modulate.a = 1.0
	_place.call_deferred()


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	add_theme_font_size_override("font_size", 26)
	add_theme_stylebox_override("normal", ThemeBuilder.box(Color(ThemeBuilder.PANEL, 0.97), ThemeBuilder.YELLOW, 3, 14, 14))
	add_theme_stylebox_override("hover", ThemeBuilder.box(Color(ThemeBuilder.PANEL_LIGHT, 0.97), ThemeBuilder.YELLOW, 3, 14, 14))
	add_theme_stylebox_override("pressed", ThemeBuilder.box(Color(ThemeBuilder.PANEL_LIGHT, 0.97), ThemeBuilder.CREAM, 3, 14, 14))
	add_theme_color_override("font_color", ThemeBuilder.CREAM)
	add_theme_color_override("font_hover_color", ThemeBuilder.YELLOW)
	pressed.connect(func():
		visible = false
		if on_open.is_valid():
			on_open.call())
	get_viewport().size_changed.connect(_place)


func _place() -> void:
	reset_size()
	position = Vector2((get_viewport().get_visible_rect().size.x - size.x) / 2.0, 70.0)


func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	if _left < 1.0:
		modulate.a = maxf(0.0, _left)
	if _left <= 0.0:
		visible = false
