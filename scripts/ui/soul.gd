extends RefCounted
## The Soul: the little emblem representing you on the title screen and as the battle cursor.
##
## Uses the built-in local picture (`assets/local/pictures/mochi.png`, Mochi) or an active add-on's
## `"soul"` texture when present; otherwise (or when Polox Originals overrides with `"@dream_drop"`)
## Polox renders its own original procedural Soul: the Dream Drop.
##
## Prepared once per add-on revision using fast PackedByteArray pixel operations: edge-connected
## white backgrounds become transparent, the sprite is cropped & squared to SIZE x SIZE, and a soft
## light outline rim keeps it crisp on the dark battle arena. Battle movement and collision bounds
## stay untouched in `heart_motion.gd`.
## Tags: [ADDONS]

const Addons := preload("res://scripts/core/addons.gd")
const SIZE := 128
const OUTLINE := 5   # Light rim width in pixels at SIZE

static var _tex: Texture2D
static var _rev := -1
static var _custom := false


## Returns the active Soul texture (Mochi / add-on picture, or Polox's original Dream Drop).
static func texture() -> Texture2D:
	if _tex == null or _rev != Addons.revision:
		_rev = Addons.revision
		var raw_tex := Addons.texture("soul")   # null when @dream_drop (Polox Originals) or no override
		var prepared: Image = prepare(raw_tex.get_image()) if raw_tex else null
		_custom = prepared != null
		_tex = ImageTexture.create_from_image(prepared if prepared else dream_drop())
	return _tex


## True when a custom/local Soul picture (e.g. Mochi) is active.
static func custom() -> bool:
	texture()
	return _custom


## Draws the Soul centred on `at` at `px` diameter, with an optional battle-mode indicator ring.
static func draw(ci: CanvasItem, at: Vector2, px: float, ring: Color = Color(0, 0, 0, 0)) -> void:
	if ring.a > 0.0:
		ci.draw_arc(at, px * 0.62, 0.0, TAU, 24, ring, maxf(1.5, px * 0.09), true)
	ci.draw_texture_rect(texture(), Rect2(at - Vector2(px, px) / 2.0, Vector2(px, px)), false)


## Prepares an image into a crisp SIZE x SIZE Soul sprite with transparent background and light rim.
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
	img = _clear_background(img)
	var used := img.get_used_rect()
	if used.size.x < 2 or used.size.y < 2:
		return null
	img = img.get_region(used)
	var inner := SIZE - OUTLINE * 2 - 2
	var scale_k := float(inner) / maxf(img.get_width(), img.get_height())
	img.resize(maxi(1, roundi(img.get_width() * scale_k)), maxi(1, roundi(img.get_height() * scale_k)), Image.INTERPOLATE_LANCZOS)
	var centered := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var offset := Vector2i((SIZE - img.get_width()) / 2, (SIZE - img.get_height()) / 2)
	centered.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), offset)
	return _outlined(centered)


## Flood-fills edge-connected near-white pixels to transparent using fast raw byte buffer access.
static func _clear_background(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
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
		var p := i * 4
		var a := data[p + 3]
		if a > 12 and (data[p] < 230 or data[p + 1] < 230 or data[p + 2] < 230):
			continue
		data[p] = 0
		data[p + 1] = 0
		data[p + 2] = 0
		data[p + 3] = 0
		var x := i % w
		var y := i / w
		if x > 0:
			stack.append(i - 1)
		if x < w - 1:
			stack.append(i + 1)
		if y > 0:
			stack.append(i - w)
		if y < h - 1:
			stack.append(i + w)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


## Adds a soft cream-rose outer rim around the silhouette for clear visibility on dark backgrounds.
static func _outlined(img: Image) -> Image:
	var src := img.get_data()
	var rim_bytes := PackedByteArray()
	rim_bytes.resize(SIZE * SIZE * 4)
	for i in SIZE * SIZE:
		var p := i * 4
		var alpha := src[p + 3]
		if alpha > 0:
			rim_bytes[p] = 255
			rim_bytes[p + 1] = 244
			rim_bytes[p + 2] = 251
			rim_bytes[p + 3] = mini(255, int(alpha * 1.4))
	var shape := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, rim_bytes)
	var out := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var full_rect := Rect2i(0, 0, SIZE, SIZE)
	for radius in range(1, OUTLINE + 1):
		var steps := 8 + radius * 4
		for step_idx in steps:
			var offset := Vector2.from_angle(TAU * step_idx / steps) * radius
			out.blend_rect(shape, full_rect, Vector2i(roundi(offset.x), roundi(offset.y)))
	out.blend_rect(img, full_rect, Vector2i.ZERO)
	return out


## Polox's original public fallback Soul: the Dream Drop — a leaning rose-light droplet with a glossy
## highlight, crisp outline, and a tiny four-point star drawn completely in code.
static func dream_drop() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(SIZE * SIZE * 4)
	var body := Color("#ff6f9f")
	var deep := Color("#b8326b")
	var edge := Color("#5a1033")
	var rim_col := Color("#fff4fb")
	var inv_size := 1.0 / float(SIZE)
	var cos_a := cos(0.24)
	var sin_a := sin(0.24)

	for y in SIZE:
		var py := (float(y) + 0.5) * inv_size - 0.52
		for x in SIZE:
			var px := (float(x) + 0.5) * inv_size - 0.5
			var q := Vector2(px * cos_a - py * sin_a, px * sin_a + py * cos_a)
			var dist := _drop_sd(q)
			if dist > 0.035:
				continue
			var c: Color
			if dist > 0.0:
				c = Color(rim_col.r, rim_col.g, rim_col.b, clampf(1.0 - dist / 0.035, 0.0, 1.0) * 0.9)
			elif dist > -0.03:
				c = edge
			else:
				var shade := clampf((q.y + 0.35) / 0.75, 0.0, 1.0)
				c = body.lerp(deep, shade * 0.75)
				var shine := (q - Vector2(-0.1, 0.02)).length()
				if shine < 0.075:
					c = c.lerp(Color.WHITE, 0.75)
			var idx := (y * SIZE + x) * 4
			bytes[idx] = clampi(int(roundf(c.r * 255.0)), 0, 255)
			bytes[idx + 1] = clampi(int(roundf(c.g * 255.0)), 0, 255)
			bytes[idx + 2] = clampi(int(roundf(c.b * 255.0)), 0, 255)
			bytes[idx + 3] = clampi(int(roundf(c.a * 255.0)), 0, 255)

	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, bytes)
	for i in range(-9, 10):
		for w in range(-1, 2):
			var a := 1.0 - absf(i) / 10.0
			_star_px(img, 74 + i, 80 + w, a)
			_star_px(img, 74 + w, 80 + i, a)
	return img


static func _star_px(img: Image, x: int, y: int, a: float) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE and img.get_pixel(x, y).a > 0.9:
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color("#fff3c4"), a * 0.85))


## Signed distance (0..1 units) to the Dream Drop shape: a circle below tapering to a gentle point above.
static func _drop_sd(q: Vector2) -> float:
	var r := 0.3
	var c := Vector2(0.0, 0.08)
	var circle := (q - c).length() - r
	var tip := Vector2(0.0, -0.42)
	var t := clampf((q.y - tip.y) / (c.y - tip.y), 0.0, 1.0)
	var half := r * 0.93 * pow(t, 0.75)
	var cone := absf(q.x) - half
	if q.y < tip.y:
		cone = (q - tip).length()
	return minf(circle, maxf(cone, q.y - c.y) if q.y < c.y else circle)
