extends RefCounted
## Crisp icons drawn from shapes at any size: 4x supersampled, then smoothed down (with mipmaps),
## so they stay sharp on a 1080p phone and on a PC alike. Phones have no emoji or symbol fonts, and
## the stand-in 12-pixel symbols (symbol_font.gd) looked blocky once scaled up: the phone's tab bar
## and the title heart use these instead.
##
##   VectorIcons.texture("heart", 80)   -> an 80 x 80 ImageTexture, white (tint it with modulate or
##                                         the button's icon colours)
## Names: heart, world (a folded map), bag (a parcel), build (a hammer), menu (three bars).

const SS := 4                  # supersampling
const NAMES: PackedStringArray = ["heart", "world", "bag", "build", "menu"]

static var _cache := {}


## One icon as a texture `px` pixels square. Cached per name, size and colour.
static func texture(icon: String, px: int, color: Color = Color.WHITE) -> ImageTexture:
	px = clampi(px, 8, 512)
	var key := "%s|%d|%s" % [icon, px, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := image(icon, px, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()


## The icon as an Image (with mipmaps). Transparent pixels keep the icon's colour, so smoothing
## never darkens the edges.
static func image(icon: String, px: int, color: Color = Color.WHITE) -> Image:
	var n := px * SS
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(color, 0.0))
	var u := float(n)
	match icon:
		"heart":
			fill(img, heart_points(Rect2(0.06 * u, 0.1 * u, 0.88 * u, 0.82 * u)), color)
		"world":
			fill(img, _scaled([[0.08, 0.24], [0.36, 0.13], [0.64, 0.24], [0.92, 0.13], [0.92, 0.77], [0.64, 0.88], [0.36, 0.77], [0.08, 0.88]], u), color)
			fill(img, _scaled([[0.36, 0.13], [0.64, 0.24], [0.64, 0.88], [0.36, 0.77]], u), Color(color.darkened(0.35), color.a))
			circle(img, Vector2(0.22, 0.42) * u, 0.055 * u, Color(color.darkened(0.45), color.a))
		"bag":
			fill(img, _scaled([[0.5, 0.1], [0.9, 0.29], [0.5, 0.48], [0.1, 0.29]], u), color)
			fill(img, _scaled([[0.1, 0.29], [0.5, 0.48], [0.5, 0.92], [0.1, 0.73]], u), Color(color.darkened(0.25), color.a))
			fill(img, _scaled([[0.5, 0.48], [0.9, 0.29], [0.9, 0.73], [0.5, 0.92]], u), Color(color.darkened(0.45), color.a))
			thick_line(img, Vector2(0.3, 0.195) * u, Vector2(0.7, 0.385) * u, 0.07 * u, Color(color.darkened(0.3), color.a))
		"build":
			thick_line(img, Vector2(0.22, 0.86) * u, Vector2(0.6, 0.42) * u, 0.12 * u, color)
			var head_c := Vector2(0.64, 0.34) * u
			var along := (Vector2(0.6, 0.42) - Vector2(0.22, 0.86)).normalized()
			var across := Vector2(-along.y, along.x)
			fill(img, PackedVector2Array([head_c + across * 0.3 * u + along * 0.11 * u, head_c - across * 0.24 * u + along * 0.11 * u,
				head_c - across * 0.24 * u - along * 0.11 * u, head_c + across * 0.3 * u - along * 0.11 * u]), color)
		"menu":
			for y in [0.27, 0.5, 0.73]:
				thick_line(img, Vector2(0.16, y) * u, Vector2(0.84, y) * u, 0.11 * u, color)
		_:
			circle(img, Vector2(0.5, 0.5) * u, 0.3 * u, color)
	img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


## A classic heart curve (x = 16 sin^3 t, y = 13 cos t - 5 cos 2t - 2 cos 3t - cos 4t), point down,
## fitted into `box`. Also what HeartIcon draws on the title screen.
static func heart_points(box: Rect2, steps: int = 96) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var t := TAU * i / steps
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(x, -y))
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var s := minf(box.size.x / (hi.x - lo.x), box.size.y / (hi.y - lo.y))
	var off := box.get_center() - (lo + hi) / 2.0 * s
	for i in pts.size():
		pts[i] = pts[i] * s + off
	return pts


static func _scaled(pairs: Array, u: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in pairs:
		pts.append(Vector2(float(p[0]), float(p[1])) * u)
	return pts


## Even-odd scanline fill of a simple polygon (pixel centres).
static func fill(img: Image, pts: PackedVector2Array, c: Color) -> void:
	var h := img.get_height()
	var w := img.get_width()
	var n := pts.size()
	if n < 3:
		return
	var y0 := maxi(0, floori(_min_y(pts)))
	var y1 := mini(h - 1, ceili(_max_y(pts)))
	for y in range(y0, y1 + 1):
		var sy := y + 0.5
		var xs: Array[float] = []
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var xa := maxi(0, ceili(xs[k] - 0.5))
			var xb := mini(w - 1, floori(xs[k + 1] - 0.5))
			for x in range(xa, xb + 1):
				img.set_pixel(x, y, c)


static func circle(img: Image, center: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array()
	var steps := maxi(12, int(r))
	for i in steps:
		var a := TAU * i / steps
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	fill(img, pts, c)


## A line `width` wide with round ends.
static func thick_line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * width / 2.0
	fill(img, PackedVector2Array([a + n, b + n, b - n, a - n]), c)
	circle(img, a, width / 2.0, c)
	circle(img, b, width / 2.0, c)


static func _min_y(pts: PackedVector2Array) -> float:
	var m := pts[0].y
	for p in pts:
		m = minf(m, p.y)
	return m


static func _max_y(pts: PackedVector2Array) -> float:
	var m := pts[0].y
	for p in pts:
		m = maxf(m, p.y)
	return m
