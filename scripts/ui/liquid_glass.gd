extends PanelContainer
## [GLASS_UI] Liquid Glass: an original Polox component (inspired by iOS 26) for things that float over
## the world: the world's navigation and quick actions, the phone's tab bar, the title's card and
## temporary sheets. What's behind shows through blurred and bent a little at the edge, the tint follows
## the background (darker over a bright room, lighter over the night) so the labels on it stay readable,
## and a light rim catches the top edge (shaders/liquid_glass.gdshader).
##
## How it reads the screen: a BackBufferCopy sits just in front of the glass (an internal child, drawn
## first), so the glass samples everything drawn before it, including another glass under it (Godot's
## screen texture is otherwise copied once and later glasses would see the screen without the earlier
## ones). The contents are ordinary children drawn after the glass, never through the shader, so text
## and icons stay sharp.
##
## Solid instead, with no screen reading, when Reduce transparency is on, on Battery saver, under memory
## pressure, and in the Survey's square look: the same shape and tint, opaque (`solid_style`).
## Tags: [GLASS_UI] [GRAPHICS]

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Graphics := preload("res://scripts/core/graphics.gd")
const SHADER := preload("res://shaders/liquid_glass.gdshader")

var radius := 26.0
var tint := Color(0, 0, 0, 0)        # (transparent black = the world's own panel colour, half tinted)
var blur := 2.6
var pad := Vector4(10, 8, 10, 8)      # left, top, right, bottom
var round_bottom := true

var _copy: BackBufferCopy
var _glass: ColorRect
var _mat: ShaderMaterial
var _live := false


## A glass of this shape around `content` (added as its child).
static func wrap(content: Control, r: float = 26.0, p: Vector4 = Vector4(10, 8, 10, 8)) -> PanelContainer:
	var g: PanelContainer = load("res://scripts/ui/liquid_glass.gd").new()
	g.radius = r
	g.pad = p
	g.add_child(content)
	return g


## True when glass that reads the screen is right here (not Reduce transparency, Battery saver, memory
## pressure or the Survey).
static func available() -> bool:
	if ThemeBuilder.solid or ThemeBuilder.world == "survey":
		return false
	if Graphics.pressure >= 1:
		return false
	return Graphics.quality(GameState.settings) != "saver"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	refresh()
	resized.connect(_fit)
	# A window resized or a phone turned moves it on screen without moving it on its canvas.
	get_viewport().size_changed.connect(_fit)


## Rebuilds as glass or solid (after Reduce transparency or the quality changes).
func refresh() -> void:
	if tint == Color(0, 0, 0, 0):
		tint = Color(ThemeBuilder.PANEL, 0.5)
	_live = available()
	var sb := StyleBoxEmpty.new() if _live else solid_style()
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	add_theme_stylebox_override("panel", sb)
	if _live and _glass == null:
		_copy = BackBufferCopy.new()
		_copy.copy_mode = BackBufferCopy.COPY_MODE_RECT
		add_child(_copy, false, Node.INTERNAL_MODE_FRONT)
		_glass = ColorRect.new()
		_glass.name = "Glass"
		_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glass.set_anchors_preset(Control.PRESET_FULL_RECT)
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_glass.material = _mat
		add_child(_glass, false, Node.INTERNAL_MODE_FRONT)   # (after the copy: it reads that copy)
	elif not _live and _glass != null:
		_glass.queue_free()
		_copy.queue_free()
		_glass = null
		_copy = null
	_fit()


func solid_style() -> StyleBox:
	var sb := ThemeBuilder.box(Color(tint.r, tint.g, tint.b, 0.97), Color(ThemeBuilder.CREAM, 0.3), 1, int(radius), 0)
	if not round_bottom:
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
	return sb


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_fit()
	elif what == NOTIFICATION_SORT_CHILDREN and _glass:
		# A container lays out its internal children too: the glass had been inset by the padding, so the
		# text sat on its very edge. The glass is the whole panel.
		_glass.position = Vector2.ZERO
		_glass.size = size


func _fit() -> void:
	if _glass == null:
		return
	set_notify_transform(true)
	# The copy covers the glass and a margin (the blur and the lens read a little beyond the edge).
	var m := 24.0
	var local := Rect2(Vector2(-m, -m), size + Vector2(m, m) * 2.0)
	# [PLATFORM] Godot 4.7.2 bug: BackBufferCopy's rect is documented in the node's own coordinates, and
	# the canvas culler does work out where that is on screen (copy_back_buffer->screen_rect), but both
	# renderers (renderer_canvas_render_rd.cpp, rasterizer_canvas_gles3.cpp) then copy `rect` itself as
	# if it were render-target pixels: a glass away from the top-left corner copied the wrong part of the
	# screen and read black. So it's given the on-screen rectangle (canvas -> window pixels).
	if is_inside_tree():
		var xf := get_viewport().get_final_transform() * get_global_transform_with_canvas()
		_copy.rect = xf * local
	else:
		_copy.rect = local
	_mat.set_shader_parameter("size_px", size)
	_mat.set_shader_parameter("radius", radius)
	_mat.set_shader_parameter("tint", tint)
	_mat.set_shader_parameter("blur", blur)
	_mat.set_shader_parameter("round_bottom", 1.0 if round_bottom else 0.0)


## Is it reading the screen now (tests, the graphics benchmark)?
func is_live() -> bool:
	return _live


## Flat buttons for a glass bar: no key of their own, a soft highlight on hover and a tinted pill when
## pressed, so the glass is the surface (iOS 26 toolbars).
static func flat_button(b: Button, r: int = 22) -> void:
	var T := ThemeBuilder
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 14
	none.content_margin_right = 14
	var over: StyleBox = T.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, r, 0)
	var down: StyleBox = T.box(Color(T.AQUA, 0.32), Color(T.AQUA, 0.6), 1, r, 0)
	for sb in [over, down]:
		sb.content_margin_left = 14
		sb.content_margin_right = 14
	b.add_theme_stylebox_override("normal", none)
	b.add_theme_stylebox_override("hover", over)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("hover_pressed", down)
	b.add_theme_stylebox_override("focus", T.box(Color(0, 0, 0, 0), T.YELLOW, 2, r, 0))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
