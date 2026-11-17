extends RefCounted
## The Soul: the little creature you are on the title screen and in battle (the dodging cursor). Its picture
## is what's built in (Mochi, assets/local) or an add-on's (textures > "soul"); without one, or with Polox
## Originals on ("@dream_drop"), Polox draws its own, the Dream Drop: an original shape, not a heart. A picture is made ready once: a plain white background around it goes, it's
## cropped, squared and given a soft light outline so it stays visible on the battle box's black.
## Only how it looks changes: the battle cursor's movement and hit area are its own (heart_motion.gd).

const Addons := preload("res://scripts/core/addons.gd")
const SIZE := 128
const OUTLINE := 5          # px of light rim (at SIZE)

static var _tex: Texture2D
static var _rev := -1
static var _custom := false


## The Soul's picture now (an add-on's, or the Dream Drop).
static func texture() -> Texture2D:
	if _tex == null or _rev != Addons.revision:
		_rev = Addons.revision
		var t := Addons.texture("soul")   # (null for @dream_drop: Polox Originals)
		var img: Image = prepare(t.get_image()) if t else null
		_custom = img != null
		_tex = ImageTexture.create_from_image(img if img else dream_drop())
	return _tex


## True when an add-on's picture is the Soul.
static func custom() -> bool:
	texture()
	return _custom


## Draws the Soul centred on `at`, `px` across (its picture keeps its shape), with an optional ring in the
## battle mode's colour.
static func draw(ci: CanvasItem, at: Vector2, px: float, ring: Color = Color(0, 0, 0, 0)) -> void:
	if ring.a > 0.0:
		ci.draw_arc(at, px * 0.62, 0, TAU, 24, ring, maxf(1.5, px * 0.09), true)
	ci.draw_texture_rect(texture(), Rect2(at - Vector2(px, px) / 2.0, Vector2(px, px)), false)


## A picture made ready to be the Soul (null if it has nothing in it).
static func prepare(src: Image) -> Image:
	if src == null or src.is_empty():
		return null
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var longest := maxi(img.get_width(), img.get_height())
	if longest > 256:
		img.resize(maxi(1, img.get_width() * 256 / longest), maxi(1, img.get_height() * 256 / longest), Image.INTERPOLATE_LANCZOS)
	_clear_background(img)
	var used := img.get_used_rect()
	if used.size.x < 2 or used.size.y < 2:
		return null
	img = img.get_region(used)
	# Square, with room for the outline.
	var inner := SIZE - OUTLINE * 2 - 2
	var k := float(inner) / maxf(img.get_width(), img.get_height())
	img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var at := Vector2i((SIZE - img.get_width()) / 2, (SIZE - img.get_height()) / 2)
	out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	return _outlined(out)


## A white (or nearly) background that touches the picture's edge becomes see-through.
static func _clear_background(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if seen[i]:
			continue
		seen[i] = 1
		var x := i % w
		var y := i / w
		var c := img.get_pixel(x, y)
		if c.a > 0.05 and (c.r < 0.9 or c.g < 0.9 or c.b < 0.9):
			continue
		img.set_pixel(x, y, Color(0, 0, 0, 0))
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)


## A soft light rim around whatever is drawn (visible on black and on the night sky).
static func _outlined(img: Image) -> Image:
	# The silhouette in the rim's colour, stamped in a ring of offsets around the picture (native blends).
	var rim := Color("#fff4fb")
	var shape := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				shape.set_pixel(x, y, Color(rim, minf(1.0, a * 1.4)))
	var out := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for r in range(1, OUTLINE + 1):
		var steps := 8 + r * 4
		for i in steps:
			var off := Vector2.from_angle(TAU * i / steps) * r
			out.blend_rect(shape, Rect2i(0, 0, SIZE, SIZE), Vector2i(roundi(off.x), roundi(off.y)))
	out.blend_rect(img, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
	return out


## Polox's own Soul: the Dream Drop, a rounded drop of rose light leaning a little, with a dark rim, a
## shine and a tiny star in it. Drawn in code (nothing borrowed).
static func dream_drop() -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var body := Color("#ff6f9f")
	var deep := Color("#b8326b")
	var edge := Color("#5a1033")
	for y in SIZE:
		for x in SIZE:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / SIZE   # 0..1
			# Lean the drop: rotate around the centre by ~-14 degrees.
			var q := (p - Vector2(0.5, 0.52)).rotated(0.24)
			var d := _drop_sd(q)
			if d > 0.035:
				continue
			var c: Color
			if d > 0.0:
				c = Color(Color("#fff4fb"), clampf(1.0 - d / 0.035, 0.0, 1.0) * 0.9)   # the light rim
			elif d > -0.03:
				c = edge
			else:
				var shade := clampf((q.y + 0.35) / 0.75, 0.0, 1.0)
				c = body.lerp(deep, shade * 0.75)
				var shine := (q - Vector2(-0.1, 0.02)).length()
				if shine < 0.075:
					c = c.lerp(Color.WHITE, 0.75)
			img.set_pixel(x, y, c)
	# A tiny four-point star in the drop.
	for i in range(-9, 10):
		for w in range(-1, 2):
			var a := 1.0 - absf(i) / 10.0
			_star_px(img, 74 + i, 80 + w, a)
			_star_px(img, 74 + w, 80 + i, a)
	return img


static func _star_px(img: Image, x: int, y: int, a: float) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE and img.get_pixel(x, y).a > 0.9:
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color("#fff3c4"), a * 0.85))


## Signed distance (in 0..1 units) to the drop: a circle below, drawn up to a soft point above.
static func _drop_sd(q: Vector2) -> float:
	var r := 0.3
	var c := Vector2(0, 0.08)
	var circle := (q - c).length() - r
	# The point: a cone from the circle to the tip at y = -0.42.
	var tip := Vector2(0, -0.42)
	var t := clampf((q.y - tip.y) / (c.y - tip.y), 0.0, 1.0)
	var half := r * 0.93 * pow(t, 0.75)
	var cone := absf(q.x) - half
	if q.y < tip.y:
		cone = (q - tip).length()
	return minf(circle, maxf(cone, q.y - c.y) if q.y < c.y else circle)
