extends RefCounted
## The built-in starter tile sets, drawn in code (32 px, seeded, so they look
## the same on every PC): Cozy Home, Dream Meadow, Dark Castle, Night Sky... and
## Tiny Town, cut from Kenney's CC0 pixel sheet. Generated into the Library once;
## worlds copy them on use.

const Tilesets := preload("res://scripts/world/tilesets.gd")

const N := 32
const BUILTIN: PackedStringArray = ["cozy_home", "dream_meadow", "dark_castle", "night_sky", "seaside", "town_house",
	"everyday_home", "streets", "snow", "farm", "crystal_cave", "library", "candy", "tiny_town"]
## Kenney's Tiny Town (CC0, assets/kenney/tiny_town/): 16 px tiles, doubled with crisp pixels.
## [number in the 12-wide sheet, id, name, flags]
const TINY_TOWN := "res://assets/kenney/tiny_town/tilemap_packed.png"
const TINY_TOWN_TILES := [
	[0, "tt_grass", "Grass", {"step": "grass"}], [1, "tt_grass_tufts", "Grass tufts", {"step": "grass"}],
	[2, "tt_flowers", "Grass with flowers", {"step": "grass"}], [25, "tt_dirt", "Dirt path", {"step": "soft"}],
	[43, "tt_cobbles", "Cobbles in grass", {"step": "stone"}], [97, "tt_castle_wall", "Castle wall", {"solid": true}],
	[48, "tt_slate_roof", "Slate roof", {"solid": true}], [52, "tt_red_roof", "Red roof", {"solid": true}],
	[72, "tt_wood_wall", "Wooden wall", {"solid": true}], [84, "tt_wood_window", "Wooden window", {"solid": true}],
	[85, "tt_wood_door", "Wooden door", {}], [76, "tt_stone_wall", "Stone wall", {"solid": true}],
	[88, "tt_stone_window", "Stone window", {"solid": true}], [89, "tt_stone_door", "Stone door", {}],
	[5, "tt_bush", "Bush", {"solid": true}], [28, "tt_tree", "Little tree", {"solid": true}],
	[27, "tt_autumn_tree", "Autumn tree", {"solid": true}], [29, "tt_mushrooms", "Mushrooms", {}],
	[17, "tt_sprouts", "Sprouts", {}], [83, "tt_sign", "Signpost", {"solid": true}],
	[94, "tt_beehive", "Beehive", {"solid": true}], [104, "tt_well", "Well", {"solid": true}],
	[107, "tt_barrel", "Barrel", {"solid": true}], [103, "tt_ladder", "Ladder", {}],
]


## Makes every built-in set that is missing from the Library.
static func ensure_builtin() -> void:
	for id in BUILTIN:
		if not Tilesets.exists(id, true):
			make(id)


## Builds one named set into the Library (or the world when library=false).
static func make(id: String, library: bool = true) -> Dictionary:
	var specs: Array = []
	var name := ""
	match id:
		"cozy_home":
			name = "Cozy Home"
			specs = [
				["wood_floor", "Wood floor", _planks(Color("#9c6b43"), Color("#7a5234")), {}],
				["rug", "Rug", _rug(Color("#b7405e"), Color("#ffd166")), {}],
				["checker", "Checker tiles", _checker(Color("#f3e9d2"), Color("#d8c3a5")), {}],
				["wallpaper", "Wallpaper", _dots(Color("#4b3c7a"), Color("#6a57a8")), {}],
				["window", "Window", _window(), {"height": 1.0}],
				["bookshelf", "Bookshelf", _bookshelf(), {"solid": true}],
				["lamp", "Lamp", _lamp(), {"solid": true}],
				["curtain", "Curtain", _curtain(Color("#c9578a")), {}],
			]
		"dream_meadow":
			name = "Dream Meadow"
			specs = [
				["grass", "Grass", _speckle(Color("#4e9a5a"), Color("#67b56f"), 60), {}],
				["flowers", "Flowery grass", _flowers(), {}],
				["path", "Dirt path", _speckle(Color("#b08a5c"), Color("#9a7449"), 40), {}],
				["water", "Water", _water(), {"solid": true, "walkable": false}],
				["bush", "Bush", _bush(), {"solid": true}],
				["canopy", "Tree canopy", _canopy(), {}],
				["fence", "Fence", _fence(), {"solid": true}],
				["mushroom", "Mushroom", _mushroom(), {}],
			]
		"dark_castle":
			name = "Dark Castle"
			specs = [
				["stone", "Stone floor", _bricks(Color("#5a5670"), Color("#3f3b52"), 8), {}],
				["cobble", "Cobbles", _speckle(Color("#55516a"), Color("#6b6786"), 90), {}],
				["brick_wall", "Brick wall", _bricks(Color("#4a3450"), Color("#2e1f33"), 6), {"solid": true}],
				["banner", "Banner", _banner(Color("#8a2040"), Color("#ffd166")), {}],
				["torch", "Torch", _torch(0), {"frames": [_torch(1)], "fps": 4}],
				["gate", "Iron gate", _gate(), {"solid": true}],
				["moss", "Mossy stone", _speckle(Color("#4e5a4a"), Color("#6f8a5c"), 70), {}],
				["rune", "Rune floor", _rune(), {}],
			]
		"seaside":
			name = "Seaside"
			specs = [
				["sand", "Warm sand", _speckle(Color("#ddc798"), Color("#bba67c"), 80), {}],
				["pebbles", "Pebbles", _speckle(Color("#a9aaa0"), Color("#767f7d"), 130), {}],
				["boardwalk", "Boardwalk", _planks(Color("#ae9175"), Color("#786958")), {}],
				["sea", "Sea", _sea(0), {"solid": true, "walkable": false, "frames": [_sea(1)], "fps": 2}],
				["foam", "Sea foam", _sea(1), {"solid": true, "walkable": false}],
				["shell", "Shell", _shell(), {}],
				["rope_fence", "Rope fence", _fence(), {"solid": true}],
				["beach_grass", "Beach grass", _beach_grass(), {}],
			]
		"town_house":
			name = "Town House"
			specs = [
				["parquet", "Honey parquet", _planks(Color("#b68a59"), Color("#86633f")), {}],
				["terrazzo", "Terrazzo", _speckle(Color("#d8d4c7"), Color("#879e98"), 95), {}],
				["terracotta", "Terracotta", _bricks(Color("#b97156"), Color("#d4b89c"), 16), {}],
				["sage_wall", "Sage wallpaper", _dots(Color("#779385"), Color("#9fb1a1")), {}],
				["red_brick", "Red brick", _bricks(Color("#985e50"), Color("#c7aa8b"), 8), {"solid": true}],
				["blue_curtain", "Blue curtain", _curtain(Color("#5e86a8")), {}],
				["striped_rug", "Striped rug", _rug(Color("#538a88"), Color("#e3cc9a")), {}],
				["lit_window", "Lamplit window", _window(), {}],
			]
		"everyday_home", "streets", "snow", "farm", "crystal_cave", "library", "candy":
			var more := _specs_more(id)
			name = str(more[0])
			specs = more[1]
		"tiny_town":
			name = "Tiny Town"
			specs = _tiny_town()
		_:
			id = "night_sky"
			name = "Night Sky"
			specs = [
				["stars", "Star field", _stars(Color("#120e24"), 14), {}],
				["void", "Deep void", _speckle(Color("#0b0818"), Color("#16102a"), 20), {}],
				["moon", "Moon tile", _moon(), {}],
				["cloud", "Cloud", _cloud(), {}],
				["nebula", "Nebula", _nebula(), {}],
				["comet", "Comet", _comet(0), {"frames": [_comet(1)], "fps": 3}],
				["lantern", "Floating lantern", _lantern(0), {"frames": [_lantern(1)], "fps": 2, "solid": true}],
				["star_floor", "Starry floor", _stars(Color("#1b1538"), 8), {}],
			]
	if Tilesets.exists(id, library):
		Tilesets.delete_set(id, library)
	var s := Tilesets.defaults(id, name)
	s["builtin"] = true
	Tilesets.save_set(s, library)
	for spec in specs:
		var flags: Dictionary = spec[3].duplicate()
		var frames: Array = flags.get("frames", [])
		flags.erase("frames")
		flags["id"] = spec[0]
		var t := Tilesets.add_tile(s, spec[1], spec[2], flags, library)
		for i in frames.size():
			Tilesets.set_tile_image(s, str(t.id), frames[i], i + 1, library)
	return Tilesets.load_set(id, library)


static func _tiny_town() -> Array:
	var tex: Texture2D = load(TINY_TOWN) if ResourceLoader.exists(TINY_TOWN) else null
	if tex == null:
		return []
	var sheet := tex.get_image()
	if sheet.is_compressed():
		sheet.decompress()
	sheet.convert(Image.FORMAT_RGBA8)
	var out: Array = []
	for t in TINY_TOWN_TILES:
		var tile := sheet.get_region(Rect2i(int(t[0]) % 12 * 16, int(t[0]) / 12 * 16, 16, 16))
		tile.resize(N, N, Image.INTERPOLATE_NEAREST)
		out.append([t[1], t[2], tile, t[3]])
	return out


# --- Pixel helpers (all 32x32, seeded) -------------------------------------------------------

static func _sea(frame: int) -> Image:
	var img := _img(Color("#427f92"))
	for y in range(4, N, 8):
		for x in range(-8, N, 16):
			_rect(img, x + frame * 4, y, x + 8 + frame * 4, y + 1, Color("#96c8c8"))
	return img


static func _shell() -> Image:
	var img := _img()
	_disc(img, 16, 17, 9, Color("#edd2b9"))
	for x in range(9, 25, 4):
		_rect(img, x, 11, x, 24, Color("#c99583"))
	_rect(img, 13, 24, 19, 27, Color("#e2bfa6"))
	return img


static func _beach_grass() -> Image:
	var img := _img()
	for x in [8, 12, 17, 21, 25]:
		_rect(img, x, 8 + x % 9, x + 1, 29, Color("#81936a"))
		_rect(img, x - 2, 11 + x % 9, x, 13 + x % 9, Color("#bdc08c"))
	return img

static func _img(bg: Color = Color(0, 0, 0, 0)) -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	return img


static func _rng(seed_text: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed_text)
	return r


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(maxi(0, y0), mini(N, y1 + 1)):
		for x in range(maxi(0, x0), mini(N, x1 + 1)):
			img.set_pixel(x, y, c)


static func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for y in N:
		for x in N:
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= r:
				img.set_pixel(x, y, c)


static func _speckle(base: Color, fleck: Color, count: int) -> Image:
	var img := _img(base)
	var r := _rng(base.to_html() + fleck.to_html() + str(count))
	for i in count:
		img.set_pixel(r.randi_range(0, N - 1), r.randi_range(0, N - 1), fleck)
	return img


static func _checker(a: Color, b: Color) -> Image:
	var img := _img(a)
	_rect(img, 0, 0, 15, 15, b)
	_rect(img, 16, 16, 31, 31, b)
	return img


static func _dots(bg: Color, dot: Color) -> Image:
	var img := _img(bg)
	for y in range(4, N, 8):
		for x in range(4, N, 8):
			_rect(img, x - 1, y - 1, x, y, dot)
	return img


static func _planks(light: Color, dark: Color) -> Image:
	var img := _img(light)
	var r := _rng("planks")
	for y in range(0, N, 8):
		_rect(img, 0, y, N - 1, y, dark)
		var gap := r.randi_range(4, 26)
		_rect(img, gap, y + 1, gap, y + 7, dark)
	for i in 30:
		img.set_pixel(r.randi_range(0, N - 1), r.randi_range(0, N - 1), light.darkened(0.12))
	return img


static func _bricks(face: Color, mortar: Color, rows: int) -> Image:
	var img := _img(mortar)
	var h := N / rows
	for row in rows:
		var off := (h * 2) if row % 2 == 1 else 0
		var x := -off
		while x < N:
			_rect(img, x + 1, row * h + 1, x + h * 2 - 2, row * h + h - 2, face)
			x += h * 2
	return img


static func _rug(base: Color, trim: Color) -> Image:
	var img := _img(base)
	_rect(img, 2, 2, 29, 29, base.lightened(0.1))
	_rect(img, 5, 5, 26, 26, base)
	for i in range(2, 30, 4):
		img.set_pixel(i, 2, trim)
		img.set_pixel(i, 29, trim)
		img.set_pixel(2, i, trim)
		img.set_pixel(29, i, trim)
	_rect(img, 12, 12, 19, 19, trim)
	_rect(img, 14, 14, 17, 17, base)
	return img


static func _window() -> Image:
	var img := _img()
	_rect(img, 3, 2, 28, 29, Color("#5b4634"))
	_rect(img, 6, 5, 25, 26, Color("#8fd3ff"))
	_rect(img, 15, 5, 16, 26, Color("#5b4634"))
	_rect(img, 6, 15, 25, 16, Color("#5b4634"))
	_rect(img, 8, 7, 11, 9, Color("#ffffff"))
	return img


static func _bookshelf() -> Image:
	var img := _img()
	_rect(img, 2, 0, 29, 31, Color("#6b4a2e"))
	var r := _rng("books")
	for shelf in 3:
		var y := 3 + shelf * 10
		_rect(img, 4, y, 27, y + 7, Color("#3d2a19"))
		var x := 4
		while x < 26:
			var w := r.randi_range(2, 4)
			_rect(img, x, y + r.randi_range(0, 2), mini(27, x + w - 1), y + 7, [Color("#e86a8a"), Color("#7ad6b0"), Color("#ffd166"), Color("#8fd3ff"), Color("#c9b6ff")][r.randi_range(0, 4)])
			x += w + 1
	return img


static func _lamp() -> Image:
	var img := _img()
	_rect(img, 10, 2, 21, 12, Color("#ffd166"))
	_rect(img, 11, 3, 20, 11, Color("#fff1b0"))
	_rect(img, 15, 13, 16, 27, Color("#5b4634"))
	_rect(img, 10, 28, 21, 30, Color("#5b4634"))
	return img


static func _curtain(c: Color) -> Image:
	var img := _img()
	for x in range(2, 30):
		var fold := (x / 4) % 2 == 0
		_rect(img, x, 0, x, 28, c.darkened(0.2) if fold else c)
	_rect(img, 0, 0, 31, 2, Color("#5b4634"))
	_rect(img, 2, 26, 29, 28, c.darkened(0.35))
	return img


static func _flowers() -> Image:
	var img := _speckle(Color("#4e9a5a"), Color("#67b56f"), 40)
	var r := _rng("flowers")
	for i in 7:
		var x := r.randi_range(2, 29)
		var y := r.randi_range(2, 29)
		var c: Color = [Color("#ffb3c7"), Color("#ffd166"), Color("#ffffff"), Color("#c9b6ff")][i % 4]
		img.set_pixel(x, y, c)
		img.set_pixel(x - 1, y, c)
		img.set_pixel(x + 1, y, c)
		img.set_pixel(x, y - 1, c)
		img.set_pixel(x, y + 1, c)
	return img


static func _water() -> Image:
	var img := _img(Color("#2e86de"))
	for y in range(3, N, 7):
		for x in range(0, N):
			if (x + y) % 9 < 4:
				img.set_pixel(x, y, Color("#8fd3ff"))
	return img


static func _bush() -> Image:
	var img := _img()
	_disc(img, 16, 19, 12, Color("#2f7a4a"))
	_disc(img, 11, 15, 7, Color("#3f9a5a"))
	_disc(img, 21, 14, 7, Color("#3f9a5a"))
	_disc(img, 16, 12, 6, Color("#55b56f"))
	return img


static func _canopy() -> Image:
	var img := _img()
	_disc(img, 16, 16, 15, Color("#2f7a4a"))
	_disc(img, 12, 12, 8, Color("#3f9a5a"))
	_disc(img, 21, 13, 7, Color("#55b56f"))
	_disc(img, 16, 21, 6, Color("#3f9a5a"))
	var r := _rng("canopy")
	for i in 10:
		img.set_pixel(r.randi_range(4, 27), r.randi_range(4, 27), Color("#ffb3c7"))
	return img


static func _fence() -> Image:
	var img := _img()
	for x in [3, 12, 21, 28]:
		_rect(img, x, 6, x + 2, 31, Color("#c08a5a"))
		_rect(img, x, 4, x + 2, 5, Color("#8b5e3c"))
	_rect(img, 0, 12, 31, 14, Color("#a0714d"))
	_rect(img, 0, 22, 31, 24, Color("#a0714d"))
	return img


static func _mushroom() -> Image:
	var img := _img()
	_rect(img, 13, 16, 18, 29, Color("#f3e9d2"))
	_disc(img, 16, 14, 10, Color("#c0392b"))
	_rect(img, 6, 15, 25, 16, Color("#c0392b"))
	for p in [Vector2i(11, 10), Vector2i(19, 8), Vector2i(16, 13), Vector2i(22, 13)]:
		_rect(img, p.x, p.y, p.x + 1, p.y + 1, Color("#ffffff"))
	return img


static func _banner(c: Color, trim: Color) -> Image:
	var img := _img()
	_rect(img, 2, 0, 29, 2, Color("#6b4a2e"))
	_rect(img, 6, 3, 25, 26, c)
	_rect(img, 6, 27, 25, 29, trim)
	_rect(img, 13, 10, 18, 18, trim)
	_rect(img, 15, 12, 16, 16, c)
	return img


static func _torch(frame: int) -> Image:
	var img := _img()
	_rect(img, 14, 14, 17, 29, Color("#6b4a2e"))
	_rect(img, 12, 12, 19, 15, Color("#4a3426"))
	var flame := Color("#ff9f43") if frame == 0 else Color("#ffd166")
	_disc(img, 16, 8 + frame, 5, flame)
	_disc(img, 16 - frame, 7, 3, Color("#fff1b0"))
	return img


static func _gate() -> Image:
	var img := _img()
	_rect(img, 0, 0, 31, 2, Color("#3a3a4a"))
	for x in range(3, 30, 6):
		_rect(img, x, 2, x + 1, 31, Color("#6a6a80"))
	_rect(img, 0, 14, 31, 15, Color("#6a6a80"))
	return img


static func _rune() -> Image:
	var img := _bricks(Color("#5a5670"), Color("#3f3b52"), 4)
	var glow := Color("#7ad6b0")
	_rect(img, 15, 6, 16, 25, glow)
	_rect(img, 8, 12, 23, 13, glow)
	_rect(img, 10, 19, 21, 20, glow)
	return img


static func _stars(bg: Color, count: int) -> Image:
	var img := _img(bg)
	var r := _rng("stars" + str(count))
	for i in count:
		var x := r.randi_range(0, N - 1)
		var y := r.randi_range(0, N - 1)
		img.set_pixel(x, y, Color("#fff8e0"))
		if i % 3 == 0:
			img.set_pixel(mini(N - 1, x + 1), y, Color("#c9b6ff"))
	return img


static func _moon() -> Image:
	var img := _stars(Color("#120e24"), 6)
	_disc(img, 17, 15, 10, Color("#fff1b0"))
	_disc(img, 21, 12, 8, Color("#120e24"))
	return img


static func _cloud() -> Image:
	var img := _img()
	_disc(img, 11, 20, 7, Color("#e8e4ff"))
	_disc(img, 20, 19, 8, Color("#e8e4ff"))
	_disc(img, 16, 14, 7, Color("#f6f3ff"))
	_rect(img, 4, 20, 27, 26, Color("#e8e4ff"))
	return img


static func _nebula() -> Image:
	var img := _stars(Color("#1b1538"), 5)
	var r := _rng("nebula")
	for i in 220:
		var x := r.randi_range(0, N - 1)
		var y := r.randi_range(0, N - 1)
		var d := Vector2(x - 16, y - 16).length()
		if d < 13:
			img.set_pixel(x, y, Color("#6a3d9a").lerp(Color("#e86a8a"), r.randf()) * Color(1, 1, 1, 1))
	return img


static func _comet(frame: int) -> Image:
	var img := _stars(Color("#120e24"), 5)
	var c := Color("#8fd3ff")
	for i in 14:
		var x := 6 + i + frame * 3
		var y := 24 - i
		if x < N and y >= 0:
			img.set_pixel(x, y, c.lerp(Color("#120e24"), i / 16.0))
	_disc(img, 21 + frame * 2, 9, 3, Color("#ffffff"))
	return img


static func _lantern(frame: int) -> Image:
	var img := _img()
	_rect(img, 15, 0, 16, 5, Color("#c08a5a"))
	_rect(img, 10, 6, 21, 24, Color("#ff9f43") if frame == 0 else Color("#ffb86b"))
	_rect(img, 12, 8, 19, 22, Color("#ffd166") if frame == 0 else Color("#fff1b0"))
	_rect(img, 13, 25, 18, 27, Color("#c08a5a"))
	return img


# --- 1.26.0's sets: an everyday home, town streets, a snowy village, a farm, a crystal cave, an old library and
# candy land (drafted for Update 8, ported here). Same 32 px, seeded, helpers below. ---------------------------------------------

static func _specs_more(id: String) -> Array:
	match id:
		"everyday_home":
			return ["Everyday Home", [
				["hardwood", "Hardwood", _planks_tone(Color("#a9744a"), Color("#8a5a36"), "hardwood"), {"step": "wood"}],
				["laminate", "Light laminate", _planks_tone(Color("#d8b98f"), Color("#bf9d73"), "laminate"), {"step": "wood"}],
				["carpet", "Carpet", _speckle(Color("#b9a99a"), Color("#a89888"), 140), {"step": "soft"}],
				["kitchen_tile", "Kitchen tiles", _tiles_grid(Color("#e9e6df"), Color("#c9c4ba"), 16), {"step": "stone"}],
				["bath_tile", "Bathroom tiles", _tiles_grid(Color("#bfe0ea"), Color("#9cc3cf"), 8), {"step": "stone"}],
				["painted_wall", "Painted wall", _speckle(Color("#efe6d8"), Color("#e6dccb"), 50), {"solid": true}],
				["red_brick", "Red brick", _bricks(Color("#a5533f"), Color("#d8cdb4"), 8), {"solid": true}],
				["doormat", "Doormat", _rug(Color("#7a5a3a"), Color("#c9a27a")), {"step": "soft"}],
			]]
		"streets":
			return ["Town Streets", [
				["asphalt", "Asphalt", _speckle(Color("#55575c"), Color("#64666c"), 160), {"step": "stone"}],
				["road_line", "Road line", _road_line(), {"step": "stone"}],
				["crosswalk", "Crosswalk", _crosswalk(), {"step": "stone"}],
				["sidewalk", "Sidewalk", _slabs(Color("#c8c4bb"), Color("#a9a59c")), {"step": "stone"}],
				["curb", "Curb", _curb(), {"step": "stone"}],
				["lawn", "Lawn", _speckle(Color("#6fa35a"), Color("#82b86b"), 90), {"step": "grass"}],
				["gravel", "Gravel", _gravel(), {"step": "stone"}],
				["manhole", "Manhole", _manhole(), {"step": "metal"}],
				["parking", "Parking line", _parking(), {"step": "stone"}],
				["hedge", "Hedge", _hedge(), {"solid": true}],
			]]
		"snow":
			return ["Snowy Village", [
				["snow", "Snow", _speckle(Color("#f4f7fb"), Color("#dfe7f2"), 70), {"step": "soft"}],
				["packed_snow", "Packed snow", _speckle(Color("#dfe6ee"), Color("#c9d3df"), 90), {"step": "soft"}],
				["ice", "Ice", _ice(), {"step": "stone"}],
				["frozen_lake", "Frozen lake", _frozen(), {"step": "stone"}],
				["pine", "Snowy pine", _pine(), {"solid": true}],
				["snowdrift", "Snowdrift", _drift(), {"solid": true}],
				["ice_brick", "Ice bricks", _bricks(Color("#cfe9f7"), Color("#a9cfe6"), 6), {"solid": true}],
				["warm_window", "Warm window", _warm_window(), {"solid": true}],
			]]
		"farm":
			return ["Farm", [
				["soil", "Tilled soil", _rows(Color("#6b4a32"), Color("#57392a")), {"step": "soft"}],
				["crops", "Young crops", _crops(Color("#5aa04a")), {}],
				["wheat", "Wheat", _wheat(), {}],
				["pumpkins", "Pumpkin patch", _pumpkins(), {}],
				["hay", "Hay bale", _hay(), {"solid": true}],
				["barn_wall", "Barn wall", _barn_wall(), {"solid": true}],
				["barn_floor", "Barn floor", _planks_tone(Color("#9a7448"), Color("#76552f"), "barn"), {"step": "wood"}],
				["trough", "Water trough", _trough(), {"solid": true}],
			]]
		"crystal_cave":
			return ["Crystal Cave", [
				["cave_floor", "Cave floor", _speckle(Color("#3e3a4a"), Color("#4f4a5e"), 110), {"step": "stone"}],
				["cave_wall", "Cave wall", _rock(Color("#4a4458")), {"solid": true}],
				["crystal", "Crystal", _crystal(0), {"frames": [_crystal(1)], "fps": 2, "solid": true}],
				["glow_shroom", "Glow mushroom", _glow_shroom(0), {"frames": [_glow_shroom(1)], "fps": 2}],
				["cave_pool", "Cave pool", _waves(Color("#2a4f7a"), Color("#6fb7e8"), 0), {"frames": [_waves(Color("#2a4f7a"), Color("#6fb7e8"), 1)], "fps": 1, "solid": true, "walkable": false}],
				["stalagmite", "Stalagmite", _stalagmite(), {"solid": true}],
				["gem_floor", "Gem floor", _gem_floor(), {"step": "stone"}],
				["moss_rock", "Mossy rock", _speckle(Color("#3e4a3e"), Color("#6f9a5c"), 80), {"step": "stone"}],
			]]
		"library":
			return ["Old Library", [
				["parquet", "Parquet", _parquet(), {"step": "wood"}],
				["marble", "Marble", _marble(), {"step": "stone"}],
				["runner", "Carpet runner", _runner(), {"step": "soft"}],
				["book_wall", "Book wall", _bookshelf(), {"solid": true}],
				["column", "Column", _column_tile(), {"solid": true}],
				["globe", "Globe", _globe(), {"solid": true}],
				["green_lamp", "Reading lamp", _green_lamp(), {"solid": true}],
				["desk", "Writing desk", _desk_tile(), {"solid": true}],
			]]
		"candy":
			return ["Candy Land", [
				["frosting", "Frosting", _speckle(Color("#ee8fae"), Color("#f7b8cd"), 70), {"step": "soft"}],
				["sprinkles", "Sprinkles", _sprinkles(), {"step": "soft"}],
				["chocolate", "Chocolate", _choc(), {"step": "soft"}],
				["cookie", "Cookie floor", _cookie(), {"step": "soft"}],
				["candy_cane", "Candy cane", _cane(), {"solid": true}],
				["gumdrop", "Gumdrop", _gumdrop(), {"solid": true}],
				["licorice", "Licorice", _licorice(), {"solid": true}],
				["jelly", "Jelly", _jelly(), {"step": "soft"}],
			]]
	return []


static func _planks_tone(light: Color, dark: Color, seed_text: String) -> Image:
	var img := _img(light)
	var r := _rng(seed_text)
	for y in range(0, N, 8):
		_rect(img, 0, y, N - 1, y, dark)
		var gap := r.randi_range(4, 26)
		_rect(img, gap, y + 1, gap, y + 7, dark)
		var shade := light.darkened(r.randf_range(0.0, 0.08))
		_rect(img, 0, y + 1, gap - 1, y + 7, shade)
	for i in 40:
		img.set_pixel(r.randi_range(0, N - 1), r.randi_range(0, N - 1), light.darkened(0.14))
	return img


static func _tiles_grid(face: Color, grout: Color, size: int) -> Image:
	var img := _img(face)
	for i in range(0, N, size):
		_rect(img, i, 0, i, N - 1, grout)
		_rect(img, 0, i, N - 1, i, grout)
	var r := _rng(face.to_html() + str(size))
	for i in 12:
		img.set_pixel(r.randi_range(1, N - 1), r.randi_range(1, N - 1), face.lightened(0.12))
	return img


static func _slabs(face: Color, joint: Color) -> Image:
	var img := _speckle(face, face.darkened(0.06), 50)
	_rect(img, 0, 0, N - 1, 0, joint)
	_rect(img, 0, 16, N - 1, 16, joint)
	_rect(img, 0, 0, 0, N - 1, joint)
	_rect(img, 16, 0, 16, N - 1, joint)
	return img


static func _road_line() -> Image:
	var img := _speckle(Color("#55575c"), Color("#64666c"), 160)
	_rect(img, 14, 2, 17, 13, Color("#f2c94c"))
	_rect(img, 14, 18, 17, 29, Color("#f2c94c"))
	return img


static func _crosswalk() -> Image:
	var img := _speckle(Color("#55575c"), Color("#64666c"), 120)
	for x in range(2, N, 8):
		_rect(img, x, 0, x + 3, N - 1, Color("#eeeeea"))
	return img


static func _curb() -> Image:
	var img := _speckle(Color("#55575c"), Color("#64666c"), 80)
	_rect(img, 0, 0, N - 1, 9, Color("#b9b5ac"))
	_rect(img, 0, 10, N - 1, 11, Color("#8f8b83"))
	return img


static func _gravel() -> Image:
	var img := _img(Color("#a39b8c"))
	var r := _rng("gravel")
	for i in 90:
		var x := r.randi_range(0, N - 2)
		var y := r.randi_range(0, N - 2)
		var c: Color = [Color("#8c8476"), Color("#bdb5a5"), Color("#7a7366")][i % 3]
		_rect(img, x, y, x + 1, y + 1, c)
	return img


static func _manhole() -> Image:
	var img := _speckle(Color("#55575c"), Color("#64666c"), 120)
	_disc(img, 16, 16, 12, Color("#3e4046"))
	_disc(img, 16, 16, 10, Color("#4d5056"))
	for y in range(9, 24, 4):
		_rect(img, 9, y, 23, y, Color("#3e4046"))
	return img


static func _parking() -> Image:
	var img := _speckle(Color("#55575c"), Color("#64666c"), 160)
	_rect(img, 0, 2, 2, N - 1, Color("#eeeeea"))
	return img


static func _hedge() -> Image:
	var img := _img(Color("#2f6b3a"))
	var r := _rng("hedge")
	for i in 160:
		img.set_pixel(r.randi_range(0, N - 1), r.randi_range(0, N - 1), [Color("#3f8a4a"), Color("#265a30"), Color("#4f9a55")][i % 3])
	return img


static func _waves(deep: Color, foam: Color, frame: int) -> Image:
	var img := _img(deep)
	for y in range(2, N, 6):
		for x in N:
			if (x + y + frame * 3) % 10 < 3:
				img.set_pixel(x, y, foam)
	var r := _rng(deep.to_html() + str(frame))
	for i in 10:
		img.set_pixel(r.randi_range(0, N - 1), r.randi_range(0, N - 1), deep.lightened(0.15))
	return img


static func _rock(c: Color) -> Image:
	var img := _img()
	_disc(img, 16, 18, 13, c.darkened(0.2))
	_disc(img, 14, 15, 11, c)
	_disc(img, 11, 11, 4, c.lightened(0.2))
	return img


static func _ice() -> Image:
	var img := _img(Color("#cdeaf7"))
	for i in range(0, N, 1):
		if i % 11 == 0:
			for k in 8:
				img.set_pixel(clampi(i + k, 0, N - 1), clampi(4 + k, 0, N - 1), Color("#ffffff"))
	_rect(img, 20, 22, 26, 22, Color("#ffffff"))
	return img


static func _frozen() -> Image:
	var img := _img(Color("#9fc9e3"))
	var r := _rng("frozen")
	for i in 6:
		var x := r.randi_range(0, N - 8)
		var y := r.randi_range(0, N - 1)
		for k in 7:
			img.set_pixel(x + k, clampi(y + (k % 3) - 1, 0, N - 1), Color("#e3f3fb"))
	return img


static func _pine() -> Image:
	var img := _img()
	for row in 4:
		var w := 4 + row * 3
		var y0 := 3 + row * 6
		for y in range(y0, y0 + 7):
			_rect(img, 16 - w + (y - y0) / 2, y, 15 + w - (y - y0) / 2, y, Color("#2f5f45"))
		_rect(img, 16 - w, y0, 15 + w, y0 + 1, Color("#f4f7fb"))
	_rect(img, 14, 27, 17, 31, Color("#6b4a2e"))
	return img


static func _drift() -> Image:
	var img := _img()
	_disc(img, 10, 22, 9, Color("#e4ebf4"))
	_disc(img, 21, 20, 10, Color("#f4f7fb"))
	_rect(img, 1, 22, 30, 31, Color("#e9eff7"))
	return img


static func _warm_window() -> Image:
	var img := _bricks(Color("#cfe9f7"), Color("#a9cfe6"), 6)
	_rect(img, 7, 7, 24, 24, Color("#6b4a2e"))
	_rect(img, 9, 9, 22, 22, Color("#ffd27a"))
	_rect(img, 15, 9, 16, 22, Color("#6b4a2e"))
	_rect(img, 9, 15, 22, 16, Color("#6b4a2e"))
	return img


static func _rows(soil: Color, furrow: Color) -> Image:
	var img := _img(soil)
	for y in range(3, N, 8):
		_rect(img, 0, y, N - 1, y + 1, furrow)
	var r := _rng("soil")
	for i in 30:
		img.set_pixel(r.randi_range(0, N - 1), r.randi_range(0, N - 1), soil.lightened(0.1))
	return img


static func _crops(green: Color) -> Image:
	var img := _rows(Color("#6b4a32"), Color("#57392a"))
	for y in range(6, N, 8):
		for x in range(3, N, 6):
			_rect(img, x, y - 3, x, y, green)
			img.set_pixel(x - 1, y - 2, green.lightened(0.15))
			img.set_pixel(x + 1, y - 3, green.lightened(0.15))
	return img


static func _wheat() -> Image:
	var img := _img(Color("#c9a14a"))
	var r := _rng("wheat")
	for i in 70:
		var x := r.randi_range(0, N - 1)
		var y := r.randi_range(2, N - 1)
		_rect(img, x, y - 2, x, y, Color("#e6c46a"))
	return img


static func _pumpkins() -> Image:
	var img := _crops(Color("#4f8a3a"))
	for p in [Vector2i(9, 12), Vector2i(22, 20), Vector2i(12, 26)]:
		_disc(img, p.x, p.y, 4, Color("#e07a2a"))
		img.set_pixel(p.x, p.y - 4, Color("#4f8a3a"))
	return img


static func _hay() -> Image:
	var img := _img()
	_rect(img, 3, 6, 28, 28, Color("#d9b45a"))
	var r := _rng("hay")
	for i in 80:
		img.set_pixel(r.randi_range(3, 28), r.randi_range(6, 28), Color("#b8923f"))
	_rect(img, 3, 13, 28, 14, Color("#8a6a2a"))
	_rect(img, 3, 21, 28, 22, Color("#8a6a2a"))
	return img


static func _barn_wall() -> Image:
	var img := _img(Color("#a33a2e"))
	for x in range(0, N, 6):
		_rect(img, x, 0, x, N - 1, Color("#7e2a22"))
	_rect(img, 0, 0, N - 1, 1, Color("#f3e9d2"))
	return img


static func _trough() -> Image:
	var img := _img()
	_rect(img, 3, 12, 28, 27, Color("#8a6a44"))
	_rect(img, 5, 14, 26, 20, Color("#5fb3e0"))
	_rect(img, 5, 21, 26, 25, Color("#6e5234"))
	return img


static func _crystal(frame: int) -> Image:
	var img := _img()   # (it stands upright: the background is clear)
	_rect(img, 5, 27, 27, 30, Color("#4a4458"))
	var c := Color("#7ae0e8") if frame == 0 else Color("#b4f4f8")
	for s in [[10, 26, 4, 18], [17, 28, 5, 24], [23, 27, 3, 14]]:
		for k in int(s[3]):
			var half := int(int(s[2]) * (1.0 - float(k) / float(s[3])))
			_rect(img, int(s[0]) - half, int(s[1]) - k, int(s[0]) + half, int(s[1]) - k, c if k % 4 != 0 else c.lightened(0.3))
	return img


static func _glow_shroom(frame: int) -> Image:
	var img := _img()
	var cap := Color("#8a6bff") if frame == 0 else Color("#b49cff")
	for p in [Vector2i(10, 20), Vector2i(21, 24)]:
		_rect(img, p.x - 1, p.y, p.x, p.y + 6, Color("#e9e1d0"))
		_disc(img, p.x, p.y, 5, cap)
		img.set_pixel(p.x - 2, p.y - 2, Color("#ffffff"))
	return img


static func _stalagmite() -> Image:
	var img := _img()
	for k in 26:
		var half := int(7.0 * (1.0 - float(k) / 26.0)) + 1
		_rect(img, 16 - half, 30 - k, 16 + half, 30 - k, Color("#6a6278") if k % 5 != 0 else Color("#7d758c"))
	return img


static func _gem_floor() -> Image:
	var img := _speckle(Color("#3e3a4a"), Color("#4f4a5e"), 80)
	var r := _rng("gems")
	for i in 6:
		var x := r.randi_range(2, 29)
		var y := r.randi_range(2, 29)
		_rect(img, x, y, x + 1, y + 1, [Color("#e86a8a"), Color("#7ae0e8"), Color("#ffd166")][i % 3])
	return img


static func _parquet() -> Image:
	var img := _img(Color("#a87a4f"))
	for by in range(0, N, 8):
		for bx in range(0, N, 8):
			var horiz := ((bx + by) / 8) % 2 == 0
			for i in range(0, 8, 2):
				if horiz:
					_rect(img, bx, by + i, bx + 7, by + i, Color("#8f6440"))
				else:
					_rect(img, bx + i, by, bx + i, by + 7, Color("#8f6440"))
	return img


static func _marble() -> Image:
	var img := _img(Color("#ece9e3"))
	var r := _rng("marble")
	for v in 4:
		var x := r.randi_range(0, N - 1)
		for y in N:
			x = clampi(x + r.randi_range(-1, 1), 0, N - 1)
			img.set_pixel(x, y, Color("#c9c4bb"))
	_rect(img, 0, 0, N - 1, 0, Color("#d8d3ca"))
	_rect(img, 0, 0, 0, N - 1, Color("#d8d3ca"))
	return img


static func _runner() -> Image:
	var img := _img(Color("#8a2a35"))
	_rect(img, 0, 3, N - 1, 4, Color("#ffd166"))
	_rect(img, 0, 27, N - 1, 28, Color("#ffd166"))
	for x in range(4, N, 8):
		_rect(img, x, 13, x + 3, 18, Color("#b8404e"))
	return img


static func _column_tile() -> Image:
	var img := _img()
	_rect(img, 6, 0, 25, 3, Color("#d8d3ca"))
	_rect(img, 9, 4, 22, 27, Color("#ece9e3"))
	for x in [11, 15, 19]:
		_rect(img, x, 5, x, 26, Color("#c9c4bb"))
	_rect(img, 6, 28, 25, 31, Color("#d8d3ca"))
	return img


static func _globe() -> Image:
	var img := _img()
	_disc(img, 16, 13, 10, Color("#4f8fbf"))
	_rect(img, 10, 9, 15, 13, Color("#6faf5a"))
	_rect(img, 18, 14, 22, 17, Color("#6faf5a"))
	_rect(img, 15, 23, 16, 27, Color("#8a6a44"))
	_rect(img, 10, 28, 21, 30, Color("#8a6a44"))
	return img


static func _green_lamp() -> Image:
	var img := _img()
	_rect(img, 8, 6, 23, 12, Color("#2f7a4a"))
	_rect(img, 9, 12, 22, 13, Color("#fff1b0"))
	_rect(img, 15, 13, 16, 26, Color("#c9a14a"))
	_rect(img, 10, 27, 21, 29, Color("#c9a14a"))
	return img


static func _desk_tile() -> Image:
	var img := _img()
	_rect(img, 2, 8, 29, 13, Color("#6b4a2e"))
	_rect(img, 3, 14, 6, 30, Color("#5a3d24"))
	_rect(img, 25, 14, 28, 30, Color("#5a3d24"))
	_rect(img, 9, 4, 18, 7, Color("#f3e9d2"))
	_rect(img, 21, 3, 22, 7, Color("#3d2a19"))
	return img


static func _sprinkles() -> Image:
	var img := _img(Color("#ee8fae"))
	var r := _rng("sprinkles")
	for i in 40:
		var x := r.randi_range(0, N - 3)
		var y := r.randi_range(0, N - 1)
		_rect(img, x, y, x + 2, y, [Color("#7ad6b0"), Color("#ffd166"), Color("#8fd3ff"), Color("#c9b6ff"), Color("#ffffff")][i % 5])
	return img


static func _choc() -> Image:
	var img := _img(Color("#6b3f26"))
	for i in range(0, N, 16):
		_rect(img, i, 0, i, N - 1, Color("#4f2d1a"))
		_rect(img, 0, i, N - 1, i, Color("#4f2d1a"))
	for i in range(2, N, 16):
		_rect(img, i, i, i + 11, i, Color("#85563a"))
	return img


static func _cookie() -> Image:
	var img := _speckle(Color("#c4843f"), Color("#a86c2e"), 90)
	var r := _rng("cookie")
	for i in 7:
		var x := r.randi_range(2, 28)
		var y := r.randi_range(2, 28)
		_rect(img, x, y, x + 2, y + 1, Color("#4f2d1a"))
	return img


static func _cane() -> Image:
	var img := _img()
	for y in range(8, 31):
		_rect(img, 14, y, 18, y, Color("#ffffff") if ((y / 3) % 2 == 0) else Color("#e04a5a"))
	for a in range(0, 12):
		var p := Vector2(20, 8) + Vector2(cos(PI + a * PI / 11.0), sin(PI + a * PI / 11.0)) * 5.0
		_rect(img, int(p.x) - 2, int(p.y) - 1, int(p.x) + 2, int(p.y) + 1, Color("#ffffff") if a % 3 != 0 else Color("#e04a5a"))
	return img


static func _gumdrop() -> Image:
	var img := _img()
	_disc(img, 16, 20, 11, Color("#3fbf6a"))
	_rect(img, 5, 20, 27, 28, Color("#3fbf6a"))
	var r := _rng("gum")
	for i in 20:
		img.set_pixel(r.randi_range(7, 25), r.randi_range(12, 27), Color("#c8f5d6"))
	return img


static func _licorice() -> Image:
	var img := _img()
	for x in [7, 15, 23]:
		_rect(img, x, 2, x + 4, 30, Color("#1e1a22"))
		_rect(img, x + 1, 2, x + 1, 30, Color("#3a3342"))
	return img


static func _jelly() -> Image:
	var img := _img(Color("#7ad65a"))
	_rect(img, 2, 2, 12, 6, Color("#b4f09a"))
	var r := _rng("jelly")
	for i in 12:
		img.set_pixel(r.randi_range(0, N - 1), r.randi_range(0, N - 1), Color("#5ab83e"))
	return img
