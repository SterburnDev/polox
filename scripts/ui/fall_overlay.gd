extends Control
## Going through a Dream Gate, drawn in code over the whole screen:
##   "down" (entering): a fall through darkness, geometric shapes rushing up past you, the outlines
##          of you and your friends glowing, then the Dream World fades in under you
##   "up"   (returning): rising into light, colours flooding back, the Light World below
## The characters' pictures come in as textures. Skippable (Moment); Reduce motion: a short fade.

const SHAPES := 26

var direction := "down"
var faces: Array = []          # Texture2D: you first, then friends coming along
var progress := 0.0            # 0..1 (tests read it)
var _shapes: Array = []        # [x (0..1), y (0..1), size, kind, spin, speed]
var _t := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the Moment above catches the skip
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in SHAPES:
		_shapes.append([rng.randf(), rng.randf(), rng.randf_range(10, 46), rng.randi() % 3, rng.randf_range(-2.0, 2.0), rng.randf_range(0.6, 1.6)])


## Plays from `from_p` to `to_p` of the whole fall over `seconds` (or until skipped); returns true
## when skipped. The world changes between two calls (0 -> 0.6, then 0.6 -> 1: the end reveals it).
func play(m: Control, seconds: float, from_p: float = 0.0, to_p: float = 1.0) -> bool:
	_t = 0.0
	var t0 := Time.get_ticks_msec()
	while _t < seconds and is_instance_valid(m) and m.is_inside_tree():   # (a moment that left the tree no longer waits)
		if await m.wait(0.0333):
			progress = 1.0
			queue_redraw()
			return true
		_t = (Time.get_ticks_msec() - t0) / 1000.0   # real time: never slow motion on a slow frame rate
		progress = lerpf(from_p, to_p, clampf(_t / seconds, 0.0, 1.0))
		queue_redraw()
	progress = to_p
	queue_redraw()
	return false


func _draw() -> void:
	var sz := size if size.x > 0 else get_viewport_rect().size
	var p := progress
	var down := direction == "down"
	# The sky: darkness falling (down), or dawn rising (up).
	var top := Color("#05020c") if down else Color("#fff3d6").lerp(Color("#8fc4e8"), p)
	var bottom := Color("#1a0f33") if down else Color("#c9a0ff").lerp(Color("#ffffff"), p)
	# Fades in fast, holds, and lets the place show through at the end.
	var env := minf(1.0, p * 5.0) * (1.0 - smoothstep(0.85, 1.0, p))
	var steps := 24
	for i in steps:
		var f := float(i) / steps
		var c := top.lerp(bottom, f)
		c.a = env
		draw_rect(Rect2(0, sz.y * f, sz.x, sz.y / steps + 1), c)
	# Shapes rushing past: upward while falling, downward while rising.
	for s in _shapes:
		var travel := p * float(s[5]) * 2.2
		var y := fposmod(float(s[1]) + (-travel if down else travel), 1.0) * sz.y
		var x := float(s[0]) * sz.x
		var r := float(s[2]) * (0.6 + p * 0.6)
		var a := (0.25 + 0.55 * sin(p * PI)) * (1.0 if down else 0.6) * env
		var col := Color("#7a5cc8", a) if down else Color("#ffd166", a)
		var ang := float(s[4]) * p * TAU
		match int(s[3]):
			0:
				_poly_square(Vector2(x, y), r, ang, col)
			1:
				draw_circle(Vector2(x, y), r * 0.5, col)
			2:
				_triangle(Vector2(x, y), r, ang, col)
	# You (and friends), glowing, drifting through the middle.
	var n := faces.size()
	for i in n:
		var tex: Texture2D = faces[i]
		if tex == null:
			continue
		var h := sz.y * 0.22
		var w := h * float(tex.get_width()) / maxf(1.0, tex.get_height())
		var cx := sz.x * 0.5 + (i - (n - 1) / 2.0) * w * 1.15
		var cy := sz.y * (0.5 + sin(p * TAU + i) * 0.03)
		var glow := Color("#b48cff") if down else Color("#fff3c4")
		for k in 3:
			var g := 6.0 + k * 5.0
			draw_texture_rect(tex, Rect2(cx - w / 2.0 - g / 2.0, cy - h / 2.0 - g / 2.0, w + g, h + g), false, Color(glow, 0.18 * sin(p * PI)))
		draw_texture_rect(tex, Rect2(cx - w / 2.0, cy - h / 2.0, w, h), false, Color(1, 1, 1, clampf(sin(p * PI) * 1.6, 0.0, 1.0)))


func _poly_square(c: Vector2, r: float, ang: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 4:
		pts.append(c + Vector2(r * 0.5, 0).rotated(ang + k * PI / 2.0))
	draw_colored_polygon(pts, col)


func _triangle(c: Vector2, r: float, ang: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 3:
		pts.append(c + Vector2(r * 0.55, 0).rotated(ang + k * TAU / 3.0))
	draw_colored_polygon(pts, col)
