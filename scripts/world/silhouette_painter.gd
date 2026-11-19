extends RefCounted
## Paints the background layers of a place, procedurally (original art, nothing downloaded): a
## horizontally repeating strip with a silhouette at the bottom (hills, trees, mountains, a city,
## dunes, clouds, floating shapes or stars) in one colour, transparent above. The same kind, colour
## and seed always give the same picture, so a place looks the same every visit and two joined
## places that share a layer line up.

const W := 1024
const H := 256

static var _cache: Dictionary = {}


static func texture(kind: String, color: Color, seed_n: int) -> ImageTexture:
	var key := "%s|%s|%d" % [kind, color.to_html(), seed_n]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(paint(kind, color, seed_n))
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()


## Smooth repeating noise: heights in 0..1 for x in 0..W (wraps around).
static func _ridge(rng: RandomNumberGenerator, octaves: int, base_freq: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(W)
	var amp := 1.0
	var total := 0.0
	var freq := base_freq
	for _o in octaves:
		var pts := PackedFloat32Array()
		for _i in freq:
			pts.append(rng.randf())
		for x in W:
			var f := float(x) / W * freq
			var i := int(f)
			var t := f - i
			var a := pts[i % freq]
			var b := pts[(i + 1) % freq]
			t = t * t * (3.0 - 2.0 * t)
			out[x] += lerpf(a, b, t) * amp
		total += amp
		amp *= 0.5
		freq *= 2
	for x in W:
		out[x] /= total
	return out


static func paint(kind: String, color: Color, seed_n: int) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(color, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%d" % [kind, seed_n])
	var solid := Color(color, 1.0)
	match kind:
		"hills", "dunes", "mountains":
			var r := _ridge(rng, 4 if kind == "mountains" else 3, 3 if kind == "dunes" else 4)
			var lo := 0.35 if kind == "mountains" else 0.55
			var hi := 0.95 if kind == "mountains" else 0.85
			for x in W:
				var hgt := r[x]
				if kind == "mountains":
					hgt = pow(hgt, 1.6)   # sharper peaks
				var top := int(H * (1.0 - lerpf(lo, hi, hgt) * (0.9 if kind != "mountains" else 1.0)))
				_column(img, x, clampi(top, 0, H - 1), solid)
		"trees":
			var base := _ridge(rng, 2, 6)
			for x in W:
				_column(img, x, int(H * 0.82 - base[x] * 18.0), solid)
			var n := 40 + rng.randi() % 20
			for _i in n:
				var cx := rng.randi() % W
				var r2 := 10 + rng.randi() % 18
				var cy := int(H * 0.8) - rng.randi() % 30 - r2
				_disc(img, cx, cy, r2, solid)   # the crown...
				for xx in range(cx - 2, cx + 3):
					_column(img, posmod(xx, W), cy, solid)   # ...on its trunk
		"city":
			var x := 0
			while x < W:
				var bw := 18 + rng.randi() % 40
				var bh := int(H * (0.25 + rng.randf() * 0.5))
				for xx in range(x, mini(x + bw, W)):
					_column(img, xx, H - bh, solid)
				# a few lit windows, slightly lighter
				var lit := Color(solid.lightened(0.45), 1.0)
				for _k in rng.randi() % 6:
					var wx := x + 3 + rng.randi() % maxi(1, bw - 6)
					var wy := H - bh + 6 + rng.randi() % maxi(1, bh - 12)
					img.fill_rect(Rect2i(wx % W, wy, 3, 4), lit)
				x += bw + rng.randi() % 4
		"clouds":
			for _i in 14:
				var cx := rng.randi() % W
				var cy := 40 + rng.randi() % 120
				for _p in 5:
					var r3 := 14 + rng.randi() % 22
					var ox := rng.randi_range(-30, 30)
					var oy := rng.randi_range(-8, 8)
					_disc(img, posmod(cx + ox, W), cy + oy, r3, Color(color, 0.85))
		"shapes":
			for _i in 18:
				var cx := rng.randi() % W
				var cy := 30 + rng.randi() % 170
				var s := 6 + rng.randi() % 20
				var c := Color(color, 0.55 + rng.randf() * 0.4)
				if rng.randf() < 0.5:
					img.fill_rect(Rect2i(cx, cy, s, s), c)
				else:
					_disc(img, cx, cy, s / 2, c)
		"stars":
			for _i in 260:
				var c2 := Color(color, 0.4 + rng.randf() * 0.6)
				var px := rng.randi() % W
				var py := rng.randi() % (H - 20)
				img.set_pixel(px, py, c2)
				if rng.randf() < 0.12:
					img.set_pixel(posmod(px + 1, W), py, c2)
					img.set_pixel(px, mini(py + 1, H - 1), c2)
	return img


static func _column(img: Image, x: int, top: int, c: Color) -> void:
	var t := clampi(top, 0, H)
	if t < H:
		img.fill_rect(Rect2i(x, t, 1, H - t), c)


static func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for dy in range(-r, r + 1):
		var yy := cy + dy
		if yy < 0 or yy >= H:
			continue
		var half := int(sqrt(maxf(0.0, r * r - dy * dy)))
		var x0 := posmod(cx - half, W)
		var span := 2 * half + 1
		if x0 + span <= W:
			img.fill_rect(Rect2i(x0, yy, span, 1), c)
		else:   # wraps around the seam
			img.fill_rect(Rect2i(x0, yy, W - x0, 1), c)
			img.fill_rect(Rect2i(0, yy, span - (W - x0), 1), c)
