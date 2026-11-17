extends RefCounted
## Generates the built-in pixel art (32x32) in code, so the game ships with
## zero image files: a round "blob friend" with 8 expressions, a player
## avatar, and a potted plant prop. Players can repaint all of it in the
## Character Creator.

const SIZE := 32
const INK := Color("#22183d")
const WHITE := Color("#fffaf0")
const BLUSH := Color("#ff8fab")
const TEAR := Color("#8fd3ff")
const LEAF := Color("#7ad6b0")


static func blank() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _px(img: Image, pts: Array, c: Color) -> void:
	for p in pts:
		if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
			img.set_pixel(p.x, p.y, c)


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			img.set_pixel(x, y, c)


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)


## Darkens the edge of every opaque shape: crisp, readable sprites.
static func outline(img: Image, c: Color) -> void:
	var src := img.duplicate() as Image
	for y in SIZE:
		for x in SIZE:
			if src.get_pixel(x, y).a < 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x < 0 or n.y < 0 or n.x >= SIZE or n.y >= SIZE or src.get_pixel(n.x, n.y).a < 0.5:
					img.set_pixel(x, y, c)
					break


static func blob(emotion: String, body: Color = Color("#c9b6ff")) -> Image:
	var img := blank()
	_ellipse(img, 16, 18.5, 12.5, 11.5, body)
	_rect(img, 9, 27, 12, 29, body)    # feet
	_rect(img, 19, 27, 22, 29, body)
	_rect(img, 15, 4, 16, 7, LEAF.darkened(0.3))  # sprout
	_rect(img, 17, 3, 19, 5, LEAF)
	_rect(img, 12, 4, 14, 5, LEAF)
	outline(img, body.darkened(0.62))
	# soft shading + highlight
	for y in range(20, 29):
		for x in range(17, 28):
			if img.get_pixel(x, y) == body:
				img.set_pixel(x, y, body.darkened(0.1))
	_rect(img, 9, 11, 11, 12, body.lightened(0.45))
	_face(img, emotion)
	return img


static func _face(img: Image, emotion: String) -> void:
	var blush := false
	match emotion:
		"happy":
			_px(img, [Vector2i(10, 18), Vector2i(11, 17), Vector2i(12, 17), Vector2i(13, 18)], INK)
			_px(img, [Vector2i(18, 18), Vector2i(19, 17), Vector2i(20, 17), Vector2i(21, 18)], INK)
			_px(img, [Vector2i(13, 22), Vector2i(14, 23), Vector2i(15, 23), Vector2i(16, 23), Vector2i(17, 23), Vector2i(18, 22)], INK)
			blush = true
		"sad":
			_rect(img, 11, 18, 12, 19, INK)
			_rect(img, 19, 18, 20, 19, INK)
			_px(img, [Vector2i(10, 16), Vector2i(11, 15), Vector2i(12, 15), Vector2i(19, 15), Vector2i(20, 15), Vector2i(21, 16)], INK)
			_px(img, [Vector2i(14, 24), Vector2i(15, 23), Vector2i(16, 23), Vector2i(17, 24)], INK)
			_px(img, [Vector2i(11, 21), Vector2i(11, 22)], TEAR)
		"angry":
			_rect(img, 11, 17, 12, 18, INK)
			_rect(img, 19, 17, 20, 18, INK)
			_px(img, [Vector2i(9, 14), Vector2i(10, 14), Vector2i(11, 15), Vector2i(12, 15), Vector2i(13, 16)], INK)
			_px(img, [Vector2i(22, 14), Vector2i(21, 14), Vector2i(20, 15), Vector2i(19, 15), Vector2i(18, 16)], INK)
			_rect(img, 13, 23, 18, 23, INK)
			_px(img, [Vector2i(14, 22), Vector2i(17, 22)], INK)
		"surprised":
			for c in [Vector2i(11, 17), Vector2i(20, 17)]:
				_rect(img, c.x - 1, c.y - 1, c.x + 1, c.y + 1, INK)
				_px(img, [c + Vector2i(-1, -1)], WHITE)
			_rect(img, 15, 22, 16, 24, INK)
		"embarrassed":
			_px(img, [Vector2i(10, 16), Vector2i(11, 17), Vector2i(12, 18), Vector2i(11, 19), Vector2i(10, 20)], INK)
			_px(img, [Vector2i(21, 16), Vector2i(20, 17), Vector2i(19, 18), Vector2i(20, 19), Vector2i(21, 20)], INK)
			_px(img, [Vector2i(13, 23), Vector2i(14, 22), Vector2i(15, 23), Vector2i(16, 22), Vector2i(17, 23), Vector2i(18, 22)], INK)
			_rect(img, 7, 21, 10, 22, BLUSH)
			_rect(img, 21, 21, 24, 22, BLUSH)
		"thinking":
			_rect(img, 12, 15, 13, 16, INK)
			_rect(img, 20, 15, 21, 16, INK)
			_rect(img, 16, 22, 18, 22, INK)
			_px(img, [Vector2i(24, 7), Vector2i(26, 6), Vector2i(28, 5)], WHITE)
		"sleepy":
			_rect(img, 10, 18, 13, 18, INK)
			_rect(img, 18, 18, 21, 18, INK)
			_rect(img, 15, 22, 16, 23, INK)
			_px(img, [Vector2i(24, 3), Vector2i(25, 3), Vector2i(26, 3), Vector2i(25, 4), Vector2i(24, 5), Vector2i(25, 5), Vector2i(26, 5)], WHITE)
		_:  # neutral
			_rect(img, 11, 16, 12, 18, INK)
			_rect(img, 19, 16, 20, 18, INK)
			_px(img, [Vector2i(11, 16), Vector2i(19, 16)], WHITE)
			_rect(img, 14, 22, 17, 22, INK)
	if blush:
		_rect(img, 7, 20, 9, 21, BLUSH)
		_rect(img, 22, 20, 24, 21, BLUSH)


## The default player avatar: a little person in a cozy hoodie.
static func player(hoodie: Color = Color("#e86a8a")) -> Image:
	var img := blank()
	var skin := Color("#f2c9a0")
	var hair := Color("#4a3426")
	_rect(img, 12, 27, 14, 30, Color("#2e2552"))   # legs
	_rect(img, 17, 27, 19, 30, Color("#2e2552"))
	_rect(img, 10, 17, 21, 27, hoodie)              # hoodie
	_rect(img, 8, 18, 9, 25, hoodie)
	_rect(img, 22, 18, 23, 25, hoodie)
	_ellipse(img, 16, 11, 7, 6.5, skin)             # head
	_rect(img, 9, 4, 22, 8, hair)                   # hair
	_rect(img, 9, 8, 10, 12, hair)
	_rect(img, 21, 8, 22, 12, hair)
	_rect(img, 12, 8, 14, 9, hair)
	outline(img, INK)
	_rect(img, 13, 11, 13, 12, INK)                 # eyes
	_rect(img, 18, 11, 18, 12, INK)
	_rect(img, 15, 15, 16, 15, Color("#b5655a"))
	_rect(img, 14, 19, 17, 19, hoodie.lightened(0.3))  # hoodie strings
	return img


## Default "billboard prop": a potted plant.
static func plant() -> Image:
	var img := blank()
	_rect(img, 11, 22, 20, 29, Color("#c97b4f"))
	_rect(img, 10, 21, 21, 22, Color("#e09a6b"))
	_ellipse(img, 16, 14, 7, 7, LEAF)
	_ellipse(img, 11, 11, 4, 4, LEAF.darkened(0.1))
	_ellipse(img, 21, 10, 4, 4, LEAF.lightened(0.1))
	_rect(img, 15, 17, 16, 21, LEAF.darkened(0.4))
	outline(img, INK)
	return img


## The face of a sign's board, 40 x 22: pale planks with three lines of "writing", a lit top edge, a
## shaded bottom edge and four nails. Drawn pale on purpose: the sign's own colour tints it
## (block_factory.gd), so the writing stays dark on any colour a player picks. Original artwork.
static func sign_face() -> Image:
	const W := 40
	const H := 22
	var plank := Color("#fff3dc")
	var seam := Color("#e3cfa8")
	var ink := Color("#4a3122")
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(plank)
	_rect(img, 0, 7, W - 1, 7, seam)
	_rect(img, 0, 14, W - 1, 14, seam)
	# Grain: a few short darker strokes per plank, the same every time.
	for stroke in [[4, 2, 6], [22, 4, 5], [30, 9, 6], [9, 11, 4], [17, 17, 7], [31, 19, 4]]:
		_rect(img, stroke[0], stroke[1], stroke[0] + stroke[2], stroke[1], Color("#f1e0bd"))
	_rect(img, 0, 0, W - 1, 0, Color.WHITE)
	_rect(img, 0, H - 1, W - 1, H - 1, Color("#cdb68c"))
	# Writing: three lines, each of "words" with gaps, the last one shorter (a sentence that ends).
	for line in [[4, [[6, 13], [16, 22], [25, 33]]], [10, [[6, 10], [13, 24], [27, 31]]], [16, [[6, 17], [20, 25]]]]:
		for word in line[1]:
			_rect(img, word[0], line[0], word[1], line[0] + 1, ink)
	_px(img, [Vector2i(2, 2), Vector2i(W - 3, 2), Vector2i(2, H - 3), Vector2i(W - 3, H - 3)], Color("#8a6a4a"))
	return img


## Writes all default expressions for a blob character into `dir`
## and returns the {emotion: relative path} map for character.json.
static func write_blob_set(dir: String, body: Color) -> Dictionary:
	var out := {}
	DirAccess.make_dir_recursive_absolute(dir.path_join("expressions"))
	for e in preload("res://scripts/core/defaults.gd").DEFAULT_EXPRESSIONS:
		var rel := "expressions/%s.png" % e
		blob(e, body).save_png(dir.path_join(rel))
		out[e] = rel
	return out
