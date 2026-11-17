extends RefCounted
## Fine surface detail for plain-coloured floors, walls and blocks: a grey picture (light, never
## brighter than white) that the colour is multiplied with, so a "#5b4b8a" floor reads as boards and
## a block as a block, in the room's own colours. 32 pixels a metre, crisp like the sprites, made once
## (no files). Pictures the player chose are never touched.
##   floor  boards: four a metre, staggered ends, seams, a little grain
##   wall   plaster: soft mottling, a darker band at the foot
##   block  a bevelled edge and a few chips, so neighbouring cubes stay apart
##   ground open land to the horizon (place_backdrop.gd): soft patches four metres across and
##          scattered tufts, repeating without a seam

const PX := 32

static var _cache: Dictionary = {}


## Forgets the textures drawn so far (memory_relief.gd); surfaces in the scene keep theirs.
static func clear_cache() -> void:
	_cache.clear()


static func texture(kind: String) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]
	var img: Image
	match kind:
		"floor":
			img = _boards()
		"wall":
			img = _plaster()
		"block":
			img = _block()
		"ground":
			img = _ground()
		_:
			return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[kind] = tex
	return tex


static func _grey(v: float) -> Color:
	var c := clampf(v, 0.0, 1.0)
	return Color(c, c, c)


static func _noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n


static func _boards() -> Image:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4101
	var grain := _noise(7, 0.35)
	var rows := 4
	var row_h := PX / rows
	for r in rows:
		var shade := rng.randf_range(0.92, 1.0)
		var cut := rng.randi_range(4, PX - 4)   # where this board's end meets the next one
		for y in range(r * row_h, (r + 1) * row_h):
			for x in PX:
				var v := shade + grain.get_noise_2d(x * 0.4, y * 2.5) * 0.03
				if y == r * row_h:
					v = 0.84                       # the seam between boards
				elif y == r * row_h + 1:
					v = minf(v + 0.03, 1.0)       # the board's lit edge
				if x == cut and y != r * row_h:
					v = 0.88
				img.set_pixel(x, y, _grey(v))
	return img


static func _plaster() -> Image:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGB8)
	var soft := _noise(11, 0.09)
	var fine := _noise(12, 0.6)
	for y in PX:
		for x in PX:
			var v := 0.95 + soft.get_noise_2d(x, y) * 0.04 + fine.get_noise_2d(x, y) * 0.015
			img.set_pixel(x, y, _grey(v))
	return img


## Open ground, 64 pixels for four metres. Seamless: every pixel blends the same noise read from the
## four copies of the tile it could belong to, and the tufts wrap around the edges.
static func _ground() -> Image:
	const SIZE := 64
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var soft := _noise(21, 0.05)
	var fine := _noise(22, 0.3)
	for y in SIZE:
		for x in SIZE:
			var v := 0.0
			for corner in [[0, 0], [SIZE, 0], [0, SIZE], [SIZE, SIZE]]:
				var weight := (1.0 - absf(x - corner[0]) / SIZE) * (1.0 - absf(y - corner[1]) / SIZE)
				var sx := float(x - corner[0])
				var sy := float(y - corner[1])
				v += weight * (soft.get_noise_2d(sx, sy) * 0.045 + fine.get_noise_2d(sx, sy) * 0.012)
			img.set_pixel(x, y, _grey(0.94 + v))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4113
	for i in 26:   # tufts: a short darker blade with a lit tip beside it
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		img.set_pixel(x, y, _grey(0.86))
		img.set_pixel(x, (y + 1) % SIZE, _grey(0.88))
		img.set_pixel((x + 1) % SIZE, y, _grey(1.0))
	return img


static func _block() -> Image:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4107
	var soft := _noise(13, 0.12)
	for y in PX:
		for x in PX:
			var v := 0.96 + soft.get_noise_2d(x, y) * 0.03
			var edge := mini(mini(x, y), mini(PX - 1 - x, PX - 1 - y))
			if edge == 0:
				v = 0.74
			elif edge == 1:
				v = minf(v + 0.04, 1.0) if (x == 1 or y == 1) else 0.86   # lit top-left, shaded bottom-right
			img.set_pixel(x, y, _grey(v))
	for i in 5:   # a few chips
		var p := Vector2i(rng.randi_range(4, PX - 5), rng.randi_range(4, PX - 5))
		img.set_pixelv(p, _grey(0.84))
		img.set_pixelv(p + Vector2i(1, 0), _grey(0.88))
	return img
