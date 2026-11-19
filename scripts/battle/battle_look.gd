extends RefCounted
## A battle's Presentation (Battle Maker > Presentation): the backdrop behind the arena and a light
## effect drifting over it. Drawn in code, quiet enough that bullets and the Soul always read first;
## with Reduce motion the effects stand still. A battle skin's own background picture still wins.
## Tags: [BATTLE_MAKER]

const BACKDROPS := {
	"black": [Color("#000000"), Color("#000000")],
	"night": [Color("#05061a"), Color("#1b1440")],
	"dusk": [Color("#1a0f2e"), Color("#5a2a4a")],
	"forest": [Color("#06120c"), Color("#163a26")],
	"sea": [Color("#02101e"), Color("#0b3550")],
	"candy": [Color("#1d0c22"), Color("#4a2050")],
}


static func backdrop(ci: CanvasItem, sz: Vector2, id: String, _t: float, _still: bool) -> void:
	var pair: Array = BACKDROPS.get(id, BACKDROPS.black)
	var bands := 12
	for i in bands:
		var k := float(i) / (bands - 1)
		ci.draw_rect(Rect2(0, sz.y * i / bands, sz.x, sz.y / bands + 1.0), (pair[0] as Color).lerp(pair[1], k))


static func effect(ci: CanvasItem, sz: Vector2, id: String, t: float, still: bool) -> void:
	if id == "none":
		return
	var time := 0.0 if still else t
	for i in 28:
		var seed_x := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var seed_s := 0.6 + fposmod(sin(i * 78.233) * 12345.678, 1.0) * 0.8
		var x := seed_x * sz.x
		var y := fposmod(seed_x * 997.0 + time * 40.0 * seed_s, sz.y + 40.0) - 20.0
		match id:
			"stars":
				var c := Color(1, 0.95, 0.7, 0.35 + 0.25 * sin(time * 3.0 + i))
				ci.draw_line(Vector2(x, y), Vector2(x - 10, y - 10), Color(c, c.a * 0.4), 1.5)
				ci.draw_circle(Vector2(x, y), 1.8, c)
			"rain":
				y = fposmod(seed_x * 997.0 + time * 380.0 * seed_s, sz.y + 40.0) - 20.0
				ci.draw_line(Vector2(x, y), Vector2(x - 3, y + 14), Color(0.6, 0.75, 1.0, 0.28), 1.2)
			"snow":
				x += sin(time * 0.8 + i) * 12.0
				ci.draw_circle(Vector2(x, y), 2.2 * seed_s, Color(1, 1, 1, 0.45))
			"petals":
				x += sin(time * 1.2 + i) * 20.0
				ci.draw_circle(Vector2(x, y), 3.0 * seed_s, Color("#ff9ec4", 0.4))
			"bubbles":
				y = sz.y - fposmod(seed_x * 997.0 + time * 30.0 * seed_s, sz.y + 40.0) + 20.0
				ci.draw_arc(Vector2(x, y), 5.0 * seed_s, 0, TAU, 14, Color("#9fe8ff", 0.35), 1.2)
