extends RefCounted
## Fine procedural surface detail + normal maps for plain-coloured floors, walls, blocks, and
## stylized surfaces. Built once into memory using fast PackedByteArray loops (zero external files)
## so rooms have tactile wood grain, plaster mottling, architectural bevels, glossy Frutiger Aero
## tiles, Dream World brickwork, checkered floors, and woven tatami mats that catch 3D lights.
## Pictures chosen by the player are never modified.
## Tags: [GRAPHICS]

const PX := 32

static var _albedo_cache: Dictionary = {}
static var _normal_cache: Dictionary = {}


## Releases cached procedural textures (memory_relief.gd); surfaces already in the scene keep theirs.
static func clear_cache() -> void:
	_albedo_cache.clear()
	_normal_cache.clear()


## Returns the list of built-in procedural surface detail kinds.
static func kinds() -> PackedStringArray:
	return PackedStringArray(["floor", "wall", "block", "ground", "aero_tile", "dream_brick", "checkered", "tatami"])


## Albedo multiplier texture (light greyscale so the room's own colour stays true).
static func texture(kind: String) -> Texture2D:
	if _albedo_cache.has(kind):
		return _albedo_cache[kind]
	var height_img := _height_image(kind)
	if height_img == null:
		return null
	height_img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(height_img)
	_albedo_cache[kind] = tex
	return tex


## Matching tangent-space normal map derived from the surface heightfield via Sobel filtering.
static func normal_texture(kind: String, strength: float = 2.2) -> Texture2D:
	var cache_key := "%s|%.2f" % [kind, strength]
	if _normal_cache.has(cache_key):
		return _normal_cache[cache_key]
	var height_img := _height_image(kind)
	if height_img == null:
		return null
	var nrm_img := _height_to_normal(height_img, strength)
	nrm_img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(nrm_img)
	_normal_cache[cache_key] = tex
	return tex


static func _height_image(kind: String) -> Image:
	match kind:
		"floor":
			return _boards()
		"wall":
			return _plaster()
		"block":
			return _block()
		"ground":
			return _ground()
		"aero_tile":
			return _aero_tile()
		"dream_brick":
			return _dream_brick()
		"checkered":
			return _checkered()
		"tatami":
			return _tatami()
		_:
			return null


static func _noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return noise


static func _write_rgb_grey(bytes: PackedByteArray, idx: int, v: float) -> void:
	var byte_val := clampi(int(roundf(v * 255.0)), 0, 255)
	bytes[idx] = byte_val
	bytes[idx + 1] = byte_val
	bytes[idx + 2] = byte_val


static func _boards() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(PX * PX * 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4101
	var grain := _noise(7, 0.35)
	var rows := 4
	var row_h := PX / rows
	for r in rows:
		var shade := rng.randf_range(0.92, 1.0)
		var cut := rng.randi_range(4, PX - 4)
		for y in range(r * row_h, (r + 1) * row_h):
			for x in PX:
				var v := shade + grain.get_noise_2d(x * 0.4, y * 2.5) * 0.032
				if y == r * row_h:
					v = 0.83
				elif y == r * row_h + 1:
					v = minf(v + 0.035, 1.0)
				if x == cut and y != r * row_h:
					v = 0.87
				_write_rgb_grey(bytes, (y * PX + x) * 3, v)
	return Image.create_from_data(PX, PX, false, Image.FORMAT_RGB8, bytes)


static func _plaster() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(PX * PX * 3)
	var soft := _noise(11, 0.09)
	var fine := _noise(12, 0.6)
	for y in PX:
		for x in PX:
			var v := 0.95 + soft.get_noise_2d(x, y) * 0.04 + fine.get_noise_2d(x, y) * 0.015
			_write_rgb_grey(bytes, (y * PX + x) * 3, v)
	return Image.create_from_data(PX, PX, false, Image.FORMAT_RGB8, bytes)


## Seamless open ground (64 px per 4 metres) with periodic noise blending and subtle grass tufts.
static func _ground() -> Image:
	const SIZE := 64
	var bytes := PackedByteArray()
	bytes.resize(SIZE * SIZE * 3)
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
			_write_rgb_grey(bytes, (y * SIZE + x) * 3, 0.94 + v)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4113
	for _i in 28:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		_write_rgb_grey(bytes, (y * SIZE + x) * 3, 0.86)
		_write_rgb_grey(bytes, (((y + 1) % SIZE) * SIZE + x) * 3, 0.88)
		_write_rgb_grey(bytes, (y * SIZE + ((x + 1) % SIZE)) * 3, 1.0)
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, bytes)


static func _block() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(PX * PX * 3)
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
				v = minf(v + 0.04, 1.0) if (x == 1 or y == 1) else 0.86
			_write_rgb_grey(bytes, (y * PX + x) * 3, v)
	for _i in 5:
		var px := rng.randi_range(4, PX - 5)
		var py := rng.randi_range(4, PX - 5)
		_write_rgb_grey(bytes, (py * PX + px) * 3, 0.84)
		_write_rgb_grey(bytes, (py * PX + px + 1) * 3, 0.88)
	return Image.create_from_data(PX, PX, false, Image.FORMAT_RGB8, bytes)


## Glossy Frutiger Aero bevelled glass mosaic tile (2x2 glossy cells per metre).
static func _aero_tile() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(PX * PX * 3)
	var cell := PX / 2
	for y in PX:
		for x in PX:
			var lx := x % cell
			var ly := y % cell
			var v := 0.94
			if lx == 0 or ly == 0:
				v = 0.78   # Clean grout line
			elif lx == 1 or ly == 1:
				v = 1.0    # Glossy top-left bevel highlight
			elif lx == cell - 1 or ly == cell - 1:
				v = 0.86   # Soft shaded lower rim
			elif ly < cell / 2:
				v = 0.98 - float(ly) * 0.008   # Upper glass sheen gradient
			_write_rgb_grey(bytes, (y * PX + x) * 3, v)
	return Image.create_from_data(PX, PX, false, Image.FORMAT_RGB8, bytes)


## Dream World whimsical staggered stone brick with tiny starlight mineral flecks.
static func _dream_brick() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(PX * PX * 3)
	var soft := _noise(31, 0.18)
	var rows := 4
	var row_h := PX / rows
	for y in PX:
		var r := y / row_h
		var offset := (PX / 4) if (r % 2 == 1) else 0
		for x in PX:
			var bx := (x + offset) % (PX / 2)
			var by := y % row_h
			var v := 0.93 + soft.get_noise_2d(x, y) * 0.045
			if by == 0 or bx == 0:
				v = 0.75
			elif by == 1 or bx == 1:
				v = minf(v + 0.05, 1.0)
			_write_rgb_grey(bytes, (y * PX + x) * 3, v)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for _i in 6:
		var sx := rng.randi_range(2, PX - 3)
		var sy := rng.randi_range(2, PX - 3)
		_write_rgb_grey(bytes, (sy * PX + sx) * 3, 1.0)
	return Image.create_from_data(PX, PX, false, Image.FORMAT_RGB8, bytes)


## Classic cozy checkered diner/hallway tile pattern.
static func _checkered() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(PX * PX * 3)
	var half := PX / 2
	for y in PX:
		for x in PX:
			var light_sq := ((x / half) + (y / half)) % 2 == 0
			var v := 0.99 if light_sq else 0.84
			if (x % half) == 0 or (y % half) == 0:
				v -= 0.05
			_write_rgb_grey(bytes, (y * PX + x) * 3, v)
	return Image.create_from_data(PX, PX, false, Image.FORMAT_RGB8, bytes)


## Woven cozy tatami reed texture with fine horizontal weave and border band.
static func _tatami() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(PX * PX * 3)
	for y in PX:
		for x in PX:
			var v := 0.92 + (0.04 if ((y + (x % 2)) % 2 == 0) else -0.02)
			if y < 2 or y >= PX - 2:
				v = 0.76   # Woven cloth border hem
			_write_rgb_grey(bytes, (y * PX + x) * 3, v)
	return Image.create_from_data(PX, PX, false, Image.FORMAT_RGB8, bytes)


## Converts a tileable greyscale height image into a crisp tangent-space normal map via Sobel filter.
static func _height_to_normal(height_img: Image, strength: float) -> Image:
	var w := height_img.get_width()
	var h := height_img.get_height()
	var src := height_img.get_data()
	var out := PackedByteArray()
	out.resize(w * h * 3)
	for y in h:
		var ym := (y - 1 + h) % h
		var yp := (y + 1) % h
		for x in w:
			var xm := (x - 1 + w) % w
			var xp := (x + 1) % w
			var tl := float(src[(ym * w + xm) * 3]) / 255.0
			var tc := float(src[(ym * w + x) * 3]) / 255.0
			var tr := float(src[(ym * w + xp) * 3]) / 255.0
			var ml := float(src[(y * w + xm) * 3]) / 255.0
			var mr := float(src[(y * w + xp) * 3]) / 255.0
			var bl := float(src[(yp * w + xm) * 3]) / 255.0
			var bc := float(src[(yp * w + x) * 3]) / 255.0
			var br := float(src[(yp * w + xp) * 3]) / 255.0
			var dx := (tr + 2.0 * mr + br - (tl + 2.0 * ml + bl)) * strength
			var dy := (bl + 2.0 * bc + br - (tl + 2.0 * tc + tr)) * strength
			var n := Vector3(-dx, -dy, 1.0).normalized()
			var idx := (y * w + x) * 3
			out[idx] = clampi(int(roundf((n.x * 0.5 + 0.5) * 255.0)), 0, 255)
			out[idx + 1] = clampi(int(roundf((n.y * 0.5 + 0.5) * 255.0)), 0, 255)
			out[idx + 2] = clampi(int(roundf((n.z * 0.5 + 0.5) * 255.0)), 0, 255)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, out)
