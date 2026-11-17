extends Control
## The backdrop of the title and the steps that make a world. On the title it's the soft twinkling night
## (deep indigo to a warm purple glow); while a world is being made (the "survey" palette) it's plain
## black, like the Survey.

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

## The stars drift slowly (a few pixels a second): drawing them 30 times a second looks the same as 60 and
## halves the title screen's cost, which is where a phone often sits for a while.
const REDRAW_S := 1.0 / 30.0

var _stars: Array = []  # [pos01: Vector2, size: float, phase: float, speed: float]
var _t := 0.0
var _since_draw := 0.0
var _drawn_black := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 140:
		_stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(1.0, 3.0), rng.randf() * TAU, rng.randf_range(0.6, 2.0)])


func _process(delta: float) -> void:
	_t += delta
	_since_draw += delta
	if _since_draw < REDRAW_S:
		return
	_since_draw = 0.0
	if not (_drawn_black and black()):   # black stays still; the night twinkles
		queue_redraw()


## Plain black while a world is being made.
static func black() -> bool:
	return ThemeBuilder.world == "survey"


func _draw() -> void:
	var s := size
	_drawn_black = black()
	if _drawn_black:
		draw_rect(Rect2(Vector2.ZERO, s), Color.BLACK)
		return
	# Vertical gradient: deep indigo to a warm purple glow near the bottom.
	var steps := 24
	for i in steps:
		var c := ThemeBuilder.BG.lerp(Color("#3a2160"), pow(float(i) / steps, 2.2))
		draw_rect(Rect2(0, s.y * i / steps, s.x, s.y / steps + 1), c)
	for st in _stars:
		var a := 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * st[3] + st[2]))
		var p: Vector2 = st[0] * s
		p.y = fmod(p.y + _t * 4.0 * st[1], s.y)
		draw_rect(Rect2(p, Vector2(st[1], st[1])), Color(ThemeBuilder.CREAM, a))
