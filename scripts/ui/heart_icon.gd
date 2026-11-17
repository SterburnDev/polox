extends Control
## The title screen's Soul (soul.gd: an add-on's picture, or Polox's own Dream Drop) with a soft glow and
## a gentle heartbeat (still with Reduce motion). `drawn_heart` = the old smooth heart shape instead.

const VectorIcons := preload("res://scripts/ui/vector_icons.gd")
const Soul := preload("res://scripts/ui/soul.gd")

var drawn_heart := false

var color := Color("#ff8fb1")
var _t := 0.0
var _beat := 0.0


func _init(px: float = 56.0, c: Color = Color("#ff8fb1")) -> void:
	color = c
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	var still := bool(GameState.settings.get("reduce_motion", false))
	# A soft "lub-dub" every 1.6 s.
	var phase := fmod(_t, 1.6)
	_beat = 0.0 if still else maxf(_pulse(phase, 0.0), 0.6 * _pulse(phase, 0.22))
	queue_redraw()


static func _pulse(phase: float, at: float) -> float:
	var x := (phase - at) / 0.16
	return 0.0 if x < 0.0 or x > 1.0 else sin(x * PI)


func _draw() -> void:
	var s := 1.0 + 0.07 * _beat
	if not drawn_heart:
		var px := minf(size.x, size.y) * s
		for k in 3:
			draw_circle(size / 2.0, px * (0.42 + 0.07 * k), Color(color, (0.07 + 0.05 * _beat) / (k + 1)))
		draw_texture_rect(Soul.texture(), Rect2((size - Vector2(px, px)) / 2.0, Vector2(px, px)), false)
		return
	var box_size := size * 0.86 * s
	var box := Rect2((size - box_size) / 2.0, box_size)
	var pts := VectorIcons.heart_points(box)
	# Glow: a few soft, growing copies behind.
	for k in 3:
		var g := 1.0 + 0.08 * (k + 1)
		var gsize := box_size * g
		var gp := VectorIcons.heart_points(Rect2((size - gsize) / 2.0, gsize), 48)
		draw_colored_polygon(gp, Color(color, (0.08 + 0.05 * _beat) / (k + 1)))
	draw_colored_polygon(pts, color)
	var edge := pts.duplicate()
	edge.append(pts[0])
	draw_polyline(edge, color.lightened(0.08), 1.5, true)   # an anti-aliased edge
	# A small highlight on the upper left lobe.
	var hl := box.position + box.size * Vector2(0.28, 0.28)
	draw_circle(hl, box.size.x * 0.07, Color(1, 1, 1, 0.35))
