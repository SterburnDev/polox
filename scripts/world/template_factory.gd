extends RefCounted
## The built-in level templates, built in code from the starter tile sets:
## Cozy Room, Hallway, Garden, Cave, Castle Hall, Night Rooftop, Dream
## Island, Empty, a 3-room Cozy Apartment, the Tile Playground, two
## Platform Mode courses (Sky Steps, Moon Ledges) and the seven-course
## Movement Lab. Written to the Library,
## and written again when BUILTIN_VERSION goes up (your own templates are
## never touched).

const Templates := preload("res://scripts/world/templates.gd")
const TilesetFactory := preload("res://scripts/world/tileset_factory.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const BUILTIN: PackedStringArray = ["cozy_room", "hallway", "garden", "cave", "castle_hall", "night_rooftop", "dream_island", "empty", "cozy_apartment", "tile_playground", "sky_steps", "moon_ledges", "seaside_pier", "tea_room", "glasshouse", "reading_nook", "movement_lab",
	"kitchen", "bathroom", "town_street", "snowy_village", "farm", "crystal_cave", "old_library", "candy_land"]
## 2 (Phase 17): the Tile Playground got a Platform Pillar; Sky Steps and Moon Ledges.
## 3 (Update 9): the Movement Lab.
const BUILTIN_VERSION := 3
## The Movement Lab's courses, in order (each has a door on to the next).
const LAB: PackedStringArray = ["lab_flat", "lab_slopes", "lab_jumps", "lab_landing", "lab_corners", "lab_ledges", "lab_speed"]


static func ensure_builtin() -> void:
	TilesetFactory.ensure_builtin()
	var have := Templates.ids()
	for id in BUILTIN:
		if not id in have or int(Templates.load_template(id).get("builtin_version", 1)) < BUILTIN_VERSION:
			make(id)
			var meta := Templates.dir().path_join(id).path_join("template.json")
			var t: Variant = JsonUtil.read_json(meta, {})
			if t is Dictionary:
				t["builtin_version"] = BUILTIN_VERSION
				JsonUtil.write_json(meta, t)


static func make(id: String) -> void:
	match id:
		"cozy_room":
			Templates.save_rooms(id, "Cozy Room", "Wood floor, a rug, a window and a bookshelf. A soft place to start.", ["home", "small"], {"cozy_room": cozy_room("cozy_room", "Cozy Room")}, "cozy_room", thumb(cozy_room("x", "x")), true)
		"hallway":
			Templates.save_rooms(id, "Hallway", "A long corridor with lamps, ready for doors on both ends.", ["home", "connector"], {"hallway": hallway("hallway", "Hallway")}, "hallway", thumb(hallway("x", "x")), true)
		"garden":
			Templates.save_rooms(id, "Garden", "Grass, flowers, a pond and a tree whose canopy you can walk behind.", ["outside", "nature"], {"garden": garden("garden", "Garden")}, "garden", thumb(garden("x", "x")), true)
		"cave":
			Templates.save_rooms(id, "Cave", "Mossy stone, a glowing rune and torches in the dark.", ["dark", "nature"], {"cave": cave("cave", "Cave")}, "cave", thumb(cave("x", "x")), true)
		"castle_hall":
			Templates.save_rooms(id, "Castle Hall", "Brick walls, banners, pillars and an iron gate.", ["dark", "castle", "big"], {"castle_hall": castle_hall("castle_hall", "Castle Hall")}, "castle_hall", thumb(castle_hall("x", "x")), true)
		"night_rooftop":
			Templates.save_rooms(id, "Night Rooftop", "A rooftop under the stars with floating lanterns and clouds.", ["night", "sky"], {"night_rooftop": rooftop("night_rooftop", "Night Rooftop")}, "night_rooftop", thumb(rooftop("x", "x")), true)
		"dream_island":
			Templates.save_rooms(id, "Dream Island", "A tiny island of grass in a sea of stars.", ["night", "nature", "dream"], {"dream_island": island("dream_island", "Dream Island")}, "dream_island", thumb(island("x", "x")), true)
		"empty":
			Templates.save_rooms(id, "Empty", "A plain 12 x 10 room, nothing in it.", ["blank"], {"empty": Defaults.room("empty", "Empty Room")}, "empty", thumb(Defaults.room("x", "x")), true)
		"cozy_apartment":
			var living := cozy_room("living_room", "Living Room")
			var hall := hallway("hall", "Hall")
			var bedroom := bedroom("bedroom", "Bedroom")
			_link(living, hall, Vector2i(11, 5), Vector2i(0, 2))
			_link(hall, bedroom, Vector2i(15, 2), Vector2i(0, 4))
			Templates.save_rooms(id, "Cozy Apartment", "Three linked rooms: a living room, a hall and a bedroom.", ["home", "set", "3 rooms"], {"living_room": living, "hall": hall, "bedroom": bedroom}, "living_room", thumb(living), true)
		"tile_playground":
			var demo := tile_playground("tile_playground", "Tile Playground")
			Templates.save_rooms(id, "Tile Playground", "A safe tour of Ground, Blocks, Backdrop and fading Foreground tiles, with a Platform Pillar to try running and jumping.", ["tiles", "editor", "demo"], {"tile_playground": demo}, "tile_playground", thumb(demo), true)
		"sky_steps":
			var steps := sky_steps("sky_steps", "Sky Steps")
			Templates.save_rooms(id, "Sky Steps", "A Platform Mode course: steps into the night sky, a jump pad, a moving platform, a checkpoint and Memory Shards.", ["platform", "course", "night"], {"sky_steps": steps}, "sky_steps", thumb(steps), true)
		"moon_ledges":
			var ledges := moon_ledges("moon_ledges", "Moon Ledges")
			Templates.save_rooms(id, "Moon Ledges", "A Platform Mode course: ledges you jump up through, slippery moon dust, a drifting platform and shards at the top.", ["platform", "course", "moon"], {"moon_ledges": ledges}, "moon_ledges", thumb(ledges), true)
		"seaside_pier", "tea_room", "glasshouse", "reading_nook":
			var names := {"seaside_pier": "Seaside Pier", "tea_room": "Tea Room", "glasshouse": "Glasshouse", "reading_nook": "Reading Nook"}
			var descriptions := {"seaside_pier": "A boardwalk to the water, with shells, beach grass and a quiet bench.",
				"tea_room": "A little table for two, honey parquet and blue curtains.", "glasshouse": "Terracotta paths, green corners and a place to sit.",
				"reading_nook": "Bookshelves, a soft chair and a record turning in the corner."}
			var place := creative_place(id, str(names[id]))
			Templates.save_rooms(id, str(names[id]), str(descriptions[id]), ["cozy", "outside" if id == "seaside_pier" else "home"], {id: place}, id, thumb(place), true)
		"kitchen", "bathroom", "town_street", "snowy_village", "farm", "crystal_cave", "old_library", "candy_land":
			var more := {
				"kitchen": ["Kitchen", "Tiles, a counter under the window and a table in the middle.", ["home", "small"]],
				"bathroom": ["Bathroom", "Small blue tiles, a bath and a sink.", ["home", "small"]],
				"town_street": ["Town Street", "A road with lane lines, kerbs, sidewalks, a crossing and hedges.", ["outside", "town"]],
				"snowy_village": ["Snowy Village", "Snow, an ice-brick cottage with a warm window, pines and a frozen pond.", ["outside", "winter"]],
				"farm": ["Farm", "Crop rows, wheat, a pumpkin patch, a barn, hay and a trough.", ["outside", "nature"]],
				"crystal_cave": ["Crystal Cave", "Glowing crystals and mushrooms round a dark pool.", ["dark", "nature"]],
				"old_library": ["Old Library", "Parquet, a carpet runner, book walls, columns and reading desks.", ["home", "big"]],
				"candy_land": ["Candy Land", "Frosting, sprinkles, a cookie path, candy canes and gumdrops.", ["dream", "outside"]],
			}
			var place := _more_place(id, str(more[id][0]))
			Templates.save_rooms(id, str(more[id][0]), str(more[id][1]), more[id][2], {id: place}, id, thumb(_more_place(id, "x")), true)
		"movement_lab":
			var lab := movement_lab()
			Templates.save_rooms(id, "Movement Lab", "Seven small Platform Mode courses for trying the physics profiles: a flat run, slopes, jumps, precision landing, tight corners, ledges with a moving platform, and a long runway into a wall.", ["platform", "course", "practice"], lab, "lab_flat", thumb(lab.lab_flat), true)


static func creative_place(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 12, "d": 10, "h": 3}
	r["spawn"] = [6, 8]
	if id == "seaside_pier":
		r["kind"] = "outdoor"
		r["walls"] = {"north": false, "east": false, "south": false, "west": false}
		r["background"] = {"sky": "auto", "ground": true, "ground_color": "#427f92", "layers": []}
		_fill_ground(r, "seaside", "sand", "pebbles", 11)
		for x in 12:
			for z in 4:
				RoomOps.set_ground(r, x, z, "seaside", "sea")
				if x < 5 or x > 7:
					RoomOps.add_sprite(r, x, 0, z, "seaside", "sea", "floor", true)
		for x in range(5, 8):
			for z in 10:
				RoomOps.set_ground(r, x, z, "seaside", "boardwalk")
		for x in [2, 9]:
			RoomOps.add_sprite(r, x, 0, 6, "seaside", "beach_grass", "standing", false)
			RoomOps.add_sprite(r, x + 1, 0, 8, "seaside", "shell", "floor", false)
		_furniture(r, "bench", 5, 1)
	else:
		_fill_ground(r, "town_house", "terracotta" if id == "glasshouse" else "parquet")
		_wall_row(r, "town_house", "sage_wall", 0)
		for x in [2, 8]:
			RoomOps.add_fg(r, x, 1, 0, "town_house", "lit_window", "wall_n", {"fade": false})
			RoomOps.add_fg(r, x + 1, 1, 0, "town_house", "blue_curtain", "wall_n", {"fade": false})
		match id:
			"tea_room":
				_furniture(r, "dining_table", 5, 4)
				_furniture(r, "chair", 5, 3, 2)
				_furniture(r, "chair", 6, 5)
				_furniture(r, "plant", 1, 1)
			"glasshouse":
				for x in [1, 3, 8, 10]:
					for z in [1, 3, 5]:
						_furniture(r, "plant", x, z)
				_furniture(r, "armchair", 5, 3)
				_furniture(r, "birdbath", 6, 2)
			"reading_nook":
				for x in range(1, 11, 2):
					_furniture(r, "bookshelf", x, 0)
				_furniture(r, "armchair", 4, 4)
				_furniture(r, "coffee_table", 5, 4)
				_furniture(r, "record_player", 9, 3)
				_furniture(r, "floor_cushion", 7, 6)
	return r


static func _furniture(r: Dictionary, model: String, x: int, z: int, rot: int = 0) -> void:
	var o: Dictionary = load("res://scripts/world/furniture.gd").make(model, x, z, rot)
	o["id"] = RoomEditor.next_object_id(r, model)
	(r.objects as Array).append(o)


static func tile_playground(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 14, "d": 12, "h": 3}
	r["floor"] = {"color": "#3f7a5a", "texture": ""}
	r["sky"] = {"color": "#15132d", "texture": ""}
	_fill_ground(r, "dream_meadow", "grass", "flowers", 7)
	for z in range(1, 11):
		RoomOps.set_ground(r, 7, z, "dream_meadow", "path")
	var back := TileLayers.of_type(r, "backdrop")
	TileLayers.put(back, 1, 1, TileLayers.make_cell("night_sky", "stars", "wall_n"))
	RoomOps.add_sprite(r, 3, 0, 3, "dream_meadow", "bush", "standing", true)
	RoomOps.add_sprite(r, 10, 0, 4, "dark_castle", "torch", "standing", false)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			RoomOps.add_fg(r, 10 + dx, 2, 7 + dz, "dream_meadow", "canopy", "standing")
	# Platform Mode, a few steps from the start: a pillar and a tiny course.
	_place(r, "platform_pillar", 3, 8, {"label": "Try Platform Mode", "color": "#c58cff"})
	RoomEditor.add_tile(r, 11, 10, "cube", "#8a7bc8")
	RoomEditor.add_tile(r, 12, 10, "cube", "#8a7bc8")
	RoomEditor.add_tile(r, 12, 10, "cube", "#8a7bc8")
	RoomEditor.add_tile(r, 13, 10, "slab", "#c9b6ff")
	_place(r, "shard", 12, 10, {"memory": "You tried something new today."})
	_place(r, "jump_pad", 1, 5, {"strength": 12.0})
	r["spawn"] = [6, 10]
	return r


## A Platform Mode piece with its defaults plus `extra`.
static func _place(r: Dictionary, type: String, x: int, z: int, extra: Dictionary = {}) -> Dictionary:
	var o := RoomEditor.add_object(r, x, z, type)
	if o.is_empty():
		return o
	o.merge(_piece_defaults(type), true)
	o.merge(extra, true)
	return o


static func _piece_defaults(type: String) -> Dictionary:
	match type:
		"platform_pillar":
			return {"label": "", "repeat": "repeat", "target_room": "", "target_spawn": []}
		"jump_pad":
			return {"strength": 14.0}
		"one_way":
			return {"elev": 1}
		"mover":
			return {"elev": 1, "dx": 3, "dy": 0, "dz": 0, "speed": 1.5}
		"shard":
			return {"elev": 0, "memory": ""}
	return {}


static func _column(r: Dictionary, x: int, z: int, height: int, color: String) -> void:
	for i in height:
		RoomEditor.add_tile(r, x, z, "cube", color)


## Sky Steps: a staircase into the stars over soft cloud-goo, a checkpoint
## halfway, a jump pad up to a high deck, a moving platform across, shards.
static func sky_steps(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 18, "d": 10, "h": 4}
	r["floor"] = {"color": "#1b1538", "texture": ""}
	r["sky"] = {"color": "#0e0a20", "texture": ""}
	r["weather"] = "none"
	_fill_ground(r, "night_sky", "star_floor", "stars", 9)
	for z in range(3, 8):
		for x in range(4, 18):
			RoomOps.set_ground(r, x, z, "night_sky", "void")
	_place(r, "platform_pillar", 1, 2, {"label": "Sky Steps", "color": "#8fd3ff"})
	var lilac := "#8a7bc8"
	var gold := "#e8c36a"
	for z in range(4, 7):
		_column(r, 5, z, 1, lilac)
		_column(r, 7, z, 2, lilac)
		_column(r, 9, z, 2, lilac)
		_column(r, 10, z, 2, lilac)
		_column(r, 12, z, 4, gold)
		_column(r, 13, z, 4, gold)
		_column(r, 17, z, 4, gold)
	_place(r, "checkpoint", 9, 5)
	_place(r, "jump_pad", 10, 5, {"strength": 14.0})
	_place(r, "mover", 14, 5, {"elev": 4, "dx": 2, "dy": 0, "dz": 0, "speed": 1.2, "color": "#7ad6b0"})
	_place(r, "shard", 7, 4, {"elev": 1, "memory": "One step, then another."})
	_place(r, "shard", 17, 5, {"memory": "Look how high you climbed."})
	for x in [4, 6, 8, 11, 14, 15, 16]:
		for z in range(4, 7):
			_place(r, "hazard", x, z, {"color": "#e86a8a"})   # (cells already holding a piece keep it)
	var sign := RoomEditor.add_object(r, 2, 7, "sign")
	if not sign.is_empty():
		sign["interaction_text"] = "Sky Steps: activate the pillar, then climb to the gold deck. Falling just puts you back at the lantern."
	r["spawn"] = [2, 5]
	return r


## Moon Ledges: thin ledges spiralling up (jump up through them), a slippery
## strip of moon dust, a drifting platform and shards at the top.
static func moon_ledges(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 14, "d": 14, "h": 4}
	r["floor"] = {"color": "#2a2445", "texture": ""}
	r["sky"] = {"color": "#0b0818", "texture": ""}
	r["weather"] = "none"
	_fill_ground(r, "night_sky", "moon", "star_floor", 6)
	var ground := TileLayers.of_type(r, "ground")
	for x in range(3, 11):
		var c := TileLayers.make_cell("night_sky", "cloud")
		c["slip"] = true   # slippery moon dust (Platform Mode)
		TileLayers.put(ground, x, 11, c)
	_place(r, "platform_pillar", 1, 12, {"label": "Moon Ledges", "color": "#ffd166"})
	var spiral := [[4, 9, 1], [6, 8, 2], [8, 7, 3], [9, 5, 4], [8, 3, 5], [6, 2, 5]]
	for s in spiral:
		_place(r, "one_way", int(s[0]), int(s[1]), {"elev": int(s[2]), "color": "#c9b6ff"})
	_column(r, 3, 2, 4, "#5b4b8a")
	_column(r, 2, 2, 4, "#5b4b8a")
	_column(r, 10, 5, 4, "#5b4b8a")
	_place(r, "checkpoint", 10, 5)   # on a column beside the 4th ledge
	_place(r, "mover", 5, 2, {"elev": 5, "dx": -1, "dy": 0, "dz": 0, "speed": 0.8, "color": "#ffd166"})
	_place(r, "shard", 2, 2, {"memory": "The moon looked close enough to touch."})
	_place(r, "shard", 8, 7, {"elev": 4, "memory": "You kept going."})
	_place(r, "jump_pad", 11, 9, {"strength": 12.0})
	for x in range(5, 9):
		_place(r, "hazard", x, 5, {"color": "#7af0ff"})
	r["spawn"] = [2, 12]
	return r


## The Movement Lab: small courses for trying (and measuring) the platform physics profiles, joined
## door to door. Every course plays with your chosen profile (Settings > Game > Platform physics,
## "physics_profile": "player"); the straight ones keep to an X course plane so Classic Momentum
## works there, and the tight corners are 3D (Classic plays as Polox there and says so).
## Every step is within a Polox running jump (1 up, 4 across), so all three profiles can finish.
static func movement_lab() -> Dictionary:
	var rooms := {"lab_flat": _lab_flat(), "lab_slopes": _lab_slopes(), "lab_jumps": _lab_jumps(), "lab_landing": _lab_landing(),
		"lab_corners": _lab_corners(), "lab_ledges": _lab_ledges(), "lab_speed": _lab_speed()}
	for i in range(LAB.size() - 1):
		var a: Dictionary = rooms[LAB[i]]
		var b: Dictionary = rooms[LAB[i + 1]]
		_link(a, b, Vector2i(a.lab_exit[0], a.lab_exit[1]), Vector2i(b.lab_entry[0], b.lab_entry[1]))
	for id in rooms:
		(rooms[id] as Dictionary).erase("lab_exit")
		(rooms[id] as Dictionary).erase("lab_entry")
	return rooms


## A course room: w x d, your chosen profile, a pillar and a sign at the start.
static func _lab_room(id: String, name: String, w: int, d: int, plane: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": w, "d": d, "h": 4}
	r["floor"] = {"color": "#3f7a5a", "texture": ""}
	r["sky"] = {"color": "#1d2550", "texture": ""}
	r["weather"] = "none"
	r["physics_profile"] = "player"
	if plane != "":
		r["platform_plane"] = plane
	_fill_ground(r, "dream_meadow", "grass")
	# Distance stripes every 5 blocks along the course.
	for x in range(0, w, 5):
		for z in d:
			RoomOps.set_ground(r, x, z, "dream_meadow", "path")
	r["lab_entry"] = [0, 0]
	r["lab_exit"] = [w - 1, floori(d / 2.0)]
	r["spawn"] = [2, floori(d / 2.0)]
	return r


static func _lab_start(r: Dictionary, label: String, tip: String) -> void:
	var mid := floori(int(r.size.d) / 2.0)
	_place(r, "platform_pillar", 1, mid, {"label": label, "color": "#8fd3ff"})
	var sign := RoomEditor.add_object(r, 1, mid + 1 if mid + 1 < int(r.size.d) else mid - 1, "sign")
	if not sign.is_empty():
		sign["interaction_text"] = tip


## Soft-hazard gap cells (deep void underneath, the checkpoint puts you back).
static func _lab_gap(r: Dictionary, x: int, z: int) -> void:
	RoomOps.set_ground(r, x, z, "night_sky", "void")
	_place(r, "hazard", x, z, {"color": "#e86a8a"})   # (a cell already holding a piece keeps it)


static func _lab_flat() -> Dictionary:
	var r := _lab_room("lab_flat", "Lab: Flat run", 28, 5, "x")
	_lab_start(r, "Lab: Flat run", "Flat run: hold right to speed up, let go to slow down, push back to brake. Stripes every 5 blocks. The door at the end goes on to slopes.")
	return r


static func _lab_slopes() -> Dictionary:
	var r := _lab_room("lab_slopes", "Lab: Slopes", 28, 5, "x")
	for z in 5:
		# A 1-high hill: ramp up, top, ramp down.
		RoomEditor.add_tile(r, 5, z, "ramp", "#c9b6ff", "", 2)
		for x in range(6, 9):
			RoomEditor.add_tile(r, x, z, "cube", "#8a7bc8")
		RoomEditor.add_tile(r, 9, z, "ramp", "#c9b6ff", "", 0)
		# A 2-high hill: two ramps up, a top, two ramps down (roll down it with the momentum profiles).
		RoomEditor.add_tile(r, 13, z, "ramp", "#c9b6ff", "", 2)
		RoomEditor.add_tile(r, 14, z, "cube", "#8a7bc8")
		RoomEditor.add_tile(r, 14, z, "ramp", "#c9b6ff", "", 2)
		for x in range(15, 18):
			_column(r, x, z, 2, "#8a7bc8")
		RoomEditor.add_tile(r, 18, z, "cube", "#8a7bc8")
		RoomEditor.add_tile(r, 18, z, "ramp", "#c9b6ff", "", 0)
		RoomEditor.add_tile(r, 19, z, "ramp", "#c9b6ff", "", 0)
	_lab_start(r, "Lab: Slopes", "Slopes: walk up and over two hills. With Classic or Adventure Momentum, roll down a slope to pick up speed.")
	_place(r, "checkpoint", 11, 2)
	return r


static func _lab_jumps() -> Dictionary:
	var r := _lab_room("lab_jumps", "Lab: Jumps", 28, 5, "x")
	for z in 5:
		for x in [6, 10, 11, 15, 16, 17]:
			_lab_gap(r, x, z)
		for x in range(21, 24):
			RoomEditor.add_tile(r, x, z, "cube", "#8a7bc8")   # a 1-high step to jump up
	_lab_start(r, "Lab: Jumps", "Jumps: gaps 1, 2 and 3 blocks wide, then a block to jump up. Hold the jump longer to jump higher (momentum profiles).")
	_place(r, "checkpoint", 13, 2)
	_place(r, "shard", 22, 2, {"memory": "You cleared all three gaps."})
	return r


static func _lab_landing() -> Dictionary:
	var r := _lab_room("lab_landing", "Lab: Landing", 24, 5, "x")
	var posts := {5: 1, 8: 1, 11: 2, 14: 2, 17: 1}   # x -> height, one block wide, on the middle line
	for x in posts:
		_column(r, x, 2, int(posts[x]), "#e8c36a")
	_lab_start(r, "Lab: Landing", "Landing: hop from post to post. Each is one block wide.")
	_place(r, "checkpoint", 11, 2)
	for x in range(3, 21):
		for z in 5:
			if not (z == 2 and posts.has(x)):
				_lab_gap(r, x, z)
	return r


static func _lab_corners() -> Dictionary:
	var r := _lab_room("lab_corners", "Lab: Corners", 14, 14, "")
	# Walls two blocks high make a winding corridor three blocks wide: right, up, left, up, right, up, left.
	for x in range(0, 11):
		_column(r, x, 3, 2, "#5b4b8a")
		_column(r, x, 11, 2, "#5b4b8a")
	for x in range(3, 14):
		_column(r, x, 7, 2, "#5b4b8a")
	r["spawn"] = [2, 1]
	r["lab_exit"] = [0, 13]
	r["lab_entry"] = [0, 0]
	_place(r, "platform_pillar", 1, 1, {"label": "Lab: Corners", "color": "#8fd3ff"})
	var sign := RoomEditor.add_object(r, 1, 2, "sign")
	if not sign.is_empty():
		sign["interaction_text"] = "Corners: follow the corridor round its tight turns without stopping. (Free 3D: Classic Momentum plays as Polox here.)"
	_place(r, "shard", 12, 1, {"memory": "Round the first bend."})
	_place(r, "checkpoint", 1, 9)
	_place(r, "shard", 12, 9, {"memory": "Nearly out."})
	return r


static func _lab_ledges() -> Dictionary:
	var r := _lab_room("lab_ledges", "Lab: Ledges", 26, 5, "x")
	for z in 5:
		for x in range(17, 20):
			_column(r, x, z, 2, "#8a7bc8")
	_place(r, "one_way", 5, 2, {"elev": 1, "color": "#c9b6ff"})
	_place(r, "one_way", 7, 2, {"elev": 2, "color": "#c9b6ff"})
	_place(r, "mover", 9, 2, {"elev": 2, "dx": 5, "dy": 0, "dz": 0, "speed": 1.4, "color": "#7ad6b0"})
	_lab_start(r, "Lab: Ledges", "Ledges: jump up through the thin ledges, ride the moving platform, hop to the deck.")
	_place(r, "checkpoint", 18, 2)
	for x in range(4, 17):
		for z in 5:
			_lab_gap(r, x, z)
	return r


static func _lab_speed() -> Dictionary:
	var r := _lab_room("lab_speed", "Lab: Speed", 44, 5, "x")
	for z in 5:
		RoomEditor.add_tile(r, 20, z, "slab", "#c9b6ff")   # a half-block lip to run up at speed
		for x in range(21, 41):
			RoomEditor.add_tile(r, x, z, "slab", "#c9b6ff")
		_column(r, 41, z, 3, "#5b4b8a")   # the wall at the end: nothing goes through it
	_lab_start(r, "Lab: Speed", "Speed: charge (Roll while standing), then launch down the runway. The wall at the end must stop you, however fast you go.")
	return r


## A door in `a` at cell_a leading to `b`, and one back in `b` at cell_b.
static func _link(a: Dictionary, b: Dictionary, cell_a: Vector2i, cell_b: Vector2i) -> void:
	var da := RoomEditor.add_object(a, cell_a.x, cell_a.y, "door", "", "", 1)
	if not da.is_empty():
		da["door_target"] = str(b.id)
		da["interaction_text"] = "To the " + str(b.name).to_lower()
	var db := RoomEditor.add_object(b, cell_b.x, cell_b.y, "door", "", "", 1)
	if not db.is_empty():
		db["door_target"] = str(a.id)
		db["interaction_text"] = "To the " + str(a.name).to_lower()


static func _fill_ground(r: Dictionary, set_id: String, tile: String, alt: String = "", every: int = 0) -> void:
	for x in int(r.size.w):
		for z in int(r.size.d):
			var t := tile
			if alt != "" and every > 0 and (x * 7 + z * 3) % every == 0:
				t = alt
			RoomOps.set_ground(r, x, z, set_id, t)


static func _wall_row(r: Dictionary, set_id: String, tile: String, z: int, orient: String = "wall_n", y: int = 0) -> void:
	for x in int(r.size.w):
		RoomOps.add_fg(r, x, y, z, set_id, tile, orient, {"fade": false})


static func cozy_room(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 12, "d": 10, "h": 3}
	r["floor"] = {"color": "#9c6b43", "texture": ""}
	r["wall"] = {"color": "#4b3c7a", "texture": ""}
	_fill_ground(r, "cozy_home", "wood_floor")
	for x in range(4, 8):
		for z in range(4, 7):
			RoomOps.set_ground(r, x, z, "cozy_home", "rug")
	_wall_row(r, "cozy_home", "wallpaper", 0)
	RoomOps.add_fg(r, 5, 1, 0, "cozy_home", "window", "wall_n", {"fade": false})
	RoomOps.add_fg(r, 6, 1, 0, "cozy_home", "window", "wall_n", {"fade": false})
	RoomOps.add_sprite(r, 1, 0, 1, "cozy_home", "bookshelf", "standing", true)
	RoomOps.add_sprite(r, 2, 0, 1, "cozy_home", "bookshelf", "standing", true)
	RoomOps.add_sprite(r, 10, 0, 1, "cozy_home", "lamp", "standing", true)
	RoomOps.add_fg(r, 9, 0, 9, "cozy_home", "curtain", "standing")
	RoomEditor.add_tile(r, 8, 2, "slab", "#e8d3b0")
	RoomEditor.add_tile(r, 9, 2, "slab", "#e8d3b0")
	var plant := RoomEditor.add_object(r, 10, 8, "prop")
	if not plant.is_empty():
		plant["interaction_text"] = "A happy little plant."
	r["spawn"] = [6, 7]
	return r


static func bedroom(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 9, "d": 8, "h": 3}
	r["floor"] = {"color": "#7a5234", "texture": ""}
	_fill_ground(r, "cozy_home", "checker")
	for x in range(1, 4):
		for z in range(1, 3):
			RoomEditor.add_tile(r, x, z, "slab", "#ffb3c7")  # the bed
	RoomOps.add_sprite(r, 7, 0, 1, "cozy_home", "lamp", "standing", true)
	_wall_row(r, "cozy_home", "wallpaper", 0)
	RoomOps.add_fg(r, 4, 1, 0, "cozy_home", "window", "wall_n", {"fade": false})
	r["spawn"] = [4, 6]
	return r


static func hallway(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 16, "d": 5, "h": 3}
	r["floor"] = {"color": "#8b5e3c", "texture": ""}
	_fill_ground(r, "cozy_home", "wood_floor")
	for x in range(2, 14, 4):
		RoomOps.add_sprite(r, x, 0, 0, "cozy_home", "lamp", "standing", true)
	_wall_row(r, "cozy_home", "wallpaper", 0)
	r["spawn"] = [8, 3]
	return r


static func garden(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 14, "d": 12, "h": 2}
	r["floor"] = {"color": "#3f7a5a", "texture": ""}
	r["wall"] = {"color": "#2a4d3c", "texture": ""}
	r["sky"] = {"color": "#1b2440", "texture": ""}
	_fill_ground(r, "dream_meadow", "grass", "flowers", 5)
	for z in int(r.size.d):
		RoomOps.set_ground(r, 7, z, "dream_meadow", "path")
	for x in range(2, 5):
		for z in range(8, 11):
			RoomOps.set_ground(r, x, z, "dream_meadow", "water")
			RoomOps.add_sprite(r, x, 0, z, "dream_meadow", "water", "floor", true)
	for p in [Vector2i(1, 2), Vector2i(12, 3), Vector2i(11, 9)]:
		RoomOps.add_sprite(r, p.x, 0, p.y, "dream_meadow", "bush", "standing", true)
	# A tree: trunk block, canopy overhead that fades when you walk behind it.
	RoomEditor.add_tile(r, 10, 5, "pillar", "#6b4a2e")
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			RoomOps.add_fg(r, 10 + dx, 2, 5 + dz, "dream_meadow", "canopy", "standing")
	for x in int(r.size.w):
		RoomOps.add_fg(r, x, 0, 0, "dream_meadow", "fence", "wall_n", {"fade": false, "solid": false})
	RoomOps.add_sprite(r, 5, 0, 3, "dream_meadow", "mushroom", "standing", false)
	r["spawn"] = [7, 10]
	return r


static func cave(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 12, "d": 12, "h": 3}
	r["floor"] = {"color": "#3f3b52", "texture": ""}
	r["wall"] = {"color": "#2a2538", "texture": ""}
	r["sky"] = {"color": "#0b0818", "texture": ""}
	_fill_ground(r, "dark_castle", "moss", "cobble", 3)
	RoomOps.set_ground(r, 6, 6, "dark_castle", "rune")
	for p in [Vector2i(2, 0), Vector2i(9, 0)]:
		RoomOps.add_fg(r, p.x, 1, p.y, "dark_castle", "torch", "wall_n", {"fade": false})
	for p in [Vector2i(0, 3), Vector2i(1, 3), Vector2i(11, 8), Vector2i(10, 9), Vector2i(3, 10)]:
		RoomEditor.add_tile(r, p.x, p.y, "cube", "#4a4660")
		RoomEditor.add_tile(r, p.x, p.y, "slab", "#55516a")
	r["spawn"] = [6, 10]
	return r


static func castle_hall(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 16, "d": 14, "h": 4}
	r["floor"] = {"color": "#5a5670", "texture": ""}
	r["wall"] = {"color": "#2e1f33", "texture": ""}
	_fill_ground(r, "dark_castle", "stone")
	_wall_row(r, "dark_castle", "brick_wall", 0)
	_wall_row(r, "dark_castle", "brick_wall", 0, "wall_n", 1)
	for x in range(2, 14, 4):
		RoomOps.add_fg(r, x, 2, 0, "dark_castle", "banner", "wall_n", {"fade": false})
		RoomEditor.add_tile(r, x, 4, "pillar", "#6b6786")
		RoomEditor.add_tile(r, x, 9, "pillar", "#6b6786")
	for p in [Vector2i(0, 0), Vector2i(15, 0)]:
		RoomOps.add_fg(r, p.x, 1, p.y, "dark_castle", "torch", "wall_n", {"fade": false})
	RoomOps.add_sprite(r, 7, 0, 0, "dark_castle", "gate", "wall_n", true)
	RoomOps.add_sprite(r, 8, 0, 0, "dark_castle", "gate", "wall_n", true)
	r["spawn"] = [8, 12]
	return r


static func rooftop(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 12, "d": 10, "h": 2}
	r["floor"] = {"color": "#2e2552", "texture": ""}
	r["wall"] = {"color": "#1b1538", "texture": ""}
	r["sky"] = {"color": "#0b0818", "texture": ""}
	_fill_ground(r, "night_sky", "star_floor")
	for x in int(r.size.w):
		RoomOps.add_fg(r, x, 0, 0, "night_sky", "stars", "wall_n", {"fade": false})
	for p in [Vector2i(2, 2), Vector2i(9, 3), Vector2i(5, 7)]:
		RoomOps.add_sprite(r, p.x, 1, p.y, "night_sky", "lantern", "standing", false)
	for p in [Vector2i(1, 8), Vector2i(10, 8)]:
		RoomOps.add_fg(r, p.x, 1, p.y, "night_sky", "cloud", "standing")
	RoomOps.add_fg(r, 6, 2, 0, "night_sky", "moon", "wall_n", {"fade": false})
	r["spawn"] = [6, 8]
	return r


static func island(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 11, "d": 11, "h": 2}
	r["floor"] = {"color": "#120e24", "texture": ""}
	r["wall"] = {"color": "#120e24", "texture": ""}
	r["sky"] = {"color": "#0b0818", "texture": ""}
	_fill_ground(r, "night_sky", "stars", "nebula", 9)
	for x in int(r.size.w):
		for z in int(r.size.d):
			if Vector2(x - 5, z - 5).length() <= 3.6:
				RoomOps.set_ground(r, x, z, "dream_meadow", "grass")
			elif Vector2(x - 5, z - 5).length() <= 4.4:
				RoomOps.add_sprite(r, x, 0, z, "night_sky", "void", "floor", true)
	RoomOps.add_sprite(r, 5, 0, 3, "dream_meadow", "mushroom", "standing", false)
	RoomOps.add_fg(r, 7, 1, 7, "night_sky", "cloud", "standing")
	r["spawn"] = [5, 6]
	return r


## A tiny top-down picture of a room for the gallery (one pixel block per cell).
static func thumb(r: Dictionary, cell_px: int = 12) -> Image:
	var w := int(r.size.w)
	var d := int(r.size.d)
	var img := Image.create(w * cell_px, d * cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color.from_string(str(r.get("floor", {}).get("color", "#5b4b8a")), Color("#5b4b8a")))
	var paint := func(x: int, z: int, c: Color, inset: int):
		for py in range(z * cell_px + inset, (z + 1) * cell_px - inset):
			for px in range(x * cell_px + inset, (x + 1) * cell_px - inset):
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, c)
	var set_colors := {"cozy_home": Color("#b7865c"), "dream_meadow": Color("#4e9a5a"), "dark_castle": Color("#5a5670"), "night_sky": Color("#1b1538")}
	var room := r
	if not r.get("tile_layers") is Array:
		room = r.duplicate(true)
		TileLayers.upgrade(room)
	var inset := {"backdrop": 0, "ground": 0, "blocks": 1, "foreground": 3}
	for l in room.tile_layers:
		if not bool(l.get("visible", true)):
			continue
		for k in l.cells:
			var c := TileLayers.parse_key(str(k))
			var col: Color = set_colors.get(str(l.cells[k].s), Color("#8a7bc8")) if str(l.type) == "ground" else (Color("#ffd166") if str(l.type) != "foreground" else Color("#7ad6b0"))
			paint.call(c.x, c.y, col, int(inset.get(str(l.type), 0)))
	for t in room.get("tiles", []):
		paint.call(int(t.x), int(t.z), Color.from_string(str(t.get("color", "")), Color("#c9b6ff")).darkened(0.1), 1)
	for o in r.get("objects", []):
		paint.call(int(o.pos[0]), int(o.pos[2]), Color("#e86a8a") if str(o.get("type", "")) == "door" else Color("#f3e9d2"), 2)
	return img


# --- 1.26.0's templates (drafted for Update 8) ---------------------------------------------------------------------

static func kitchen(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 10, "d": 8, "h": 3}
	r["floor"] = {"color": "#e9e6df", "texture": ""}
	r["wall"] = {"color": "#efe6d8", "texture": ""}
	_fill_ground(r, "everyday_home", "kitchen_tile")
	_wall_row(r, "everyday_home", "painted_wall", 0)
	RoomOps.add_fg(r, 4, 1, 0, "cozy_home", "window", "wall_n", {"fade": false})
	RoomOps.add_fg(r, 5, 1, 0, "cozy_home", "window", "wall_n", {"fade": false})
	for x in range(1, 9):
		RoomEditor.add_tile(r, x, 1, "slab", "#d8cdb4")   # the counter
	for x in range(3, 7):
		for z in range(4, 6):
			RoomEditor.add_tile(r, x, z, "slab", "#a9744a")   # the table
	RoomOps.set_ground(r, 5, 7, "everyday_home", "doormat")
	r["spawn"] = [5, 6]
	return r


static func bathroom(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 7, "d": 6, "h": 3}
	r["floor"] = {"color": "#bfe0ea", "texture": ""}
	r["wall"] = {"color": "#f4f7fb", "texture": ""}
	_fill_ground(r, "everyday_home", "bath_tile")
	_wall_row(r, "everyday_home", "painted_wall", 0)
	for x in range(1, 4):
		RoomEditor.add_tile(r, x, 1, "slab", "#f4f7fb")   # the bath
	RoomEditor.add_tile(r, 5, 1, "cube", "#f4f7fb")       # the sink
	r["spawn"] = [3, 4]
	return r


static func town_street(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 18, "d": 12, "h": 2}
	r["kind"] = "outdoor"
	r["walls"] = {"north": false, "east": false, "south": false, "west": false}
	r["floor"] = {"color": "#6fa35a", "texture": ""}
	_fill_ground(r, "streets", "lawn")
	for x in 18:
		RoomOps.set_ground(r, x, 2, "streets", "sidewalk")
		RoomOps.set_ground(r, x, 3, "streets", "curb")
		for z in range(4, 8):
			RoomOps.set_ground(r, x, z, "streets", "asphalt")
		RoomOps.set_ground(r, x, 5, "streets", "road_line" if x % 3 != 2 else "asphalt")
		RoomOps.set_ground(r, x, 8, "streets", "curb")
		RoomOps.set_ground(r, x, 9, "streets", "sidewalk")
	for z in range(4, 8):
		RoomOps.set_ground(r, 8, z, "streets", "crosswalk")
		RoomOps.set_ground(r, 9, z, "streets", "crosswalk")
	RoomOps.set_ground(r, 14, 6, "streets", "manhole")
	for x in [2, 6, 12, 16]:
		RoomOps.add_sprite(r, x, 0, 1, "streets", "hedge", "standing", true)
	for x in range(0, 18, 4):
		RoomOps.add_sprite(r, x, 0, 11, "streets", "hedge", "standing", true)
	r["spawn"] = [9, 10]
	return r


static func snowy_village(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 16, "d": 12, "h": 2}
	r["kind"] = "outdoor"
	r["walls"] = {"north": false, "east": false, "south": false, "west": false}
	r["floor"] = {"color": "#f4f7fb", "texture": ""}
	r["sky"] = {"color": "#2a3550", "texture": ""}
	_fill_ground(r, "snow", "snow")
	for x in 16:
		RoomOps.set_ground(r, x, 7, "snow", "packed_snow")
	for z in range(0, 7):
		RoomOps.set_ground(r, 8, z, "snow", "packed_snow")
	for x in range(11, 15):
		for z in range(9, 12):
			RoomOps.set_ground(r, x, z, "snow", "frozen_lake")
	for x in range(2, 6):
		RoomOps.add_fg(r, x, 0, 2, "snow", "ice_brick", "wall_n", {"fade": false})
		RoomOps.add_fg(r, x, 1, 2, "snow", "ice_brick" if x != 3 else "warm_window", "wall_n", {"fade": false})
	for p in [Vector2i(1, 9), Vector2i(4, 11), Vector2i(13, 2), Vector2i(15, 5), Vector2i(10, 1)]:
		RoomOps.add_sprite(r, p.x, 0, p.y, "snow", "pine", "standing", true)
	RoomOps.add_sprite(r, 6, 0, 10, "snow", "snowdrift", "standing", true)
	r["spawn"] = [8, 9]
	return r


static func farm(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 16, "d": 12, "h": 2}
	r["kind"] = "outdoor"
	r["walls"] = {"north": false, "east": false, "south": false, "west": false}
	r["floor"] = {"color": "#6fa35a", "texture": ""}
	_fill_ground(r, "streets", "lawn")
	for x in range(1, 7):
		for z in range(1, 5):
			RoomOps.set_ground(r, x, z, "farm", "crops" if z % 2 == 1 else "soil")
	for x in range(1, 7):
		for z in range(6, 9):
			RoomOps.set_ground(r, x, z, "farm", "wheat")
	for x in range(8, 11):
		for z in range(1, 4):
			RoomOps.set_ground(r, x, z, "farm", "pumpkins")
	for x in range(11, 16):
		for z in range(6, 12):
			RoomOps.set_ground(r, x, z, "farm", "barn_floor")
	for x in range(11, 16):
		RoomOps.add_fg(r, x, 0, 6, "farm", "barn_wall", "wall_n", {"fade": false})
	for p in [Vector2i(9, 8), Vector2i(9, 9)]:
		RoomOps.add_sprite(r, p.x, 0, p.y, "farm", "hay", "standing", true)
	RoomOps.add_sprite(r, 7, 0, 10, "farm", "trough", "standing", true)
	for x in 16:
		RoomOps.add_fg(r, x, 0, 0, "dream_meadow", "fence", "wall_n", {"fade": false, "solid": false})
	r["spawn"] = [8, 10]
	return r


static func crystal_cave(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 14, "d": 12, "h": 3}
	r["floor"] = {"color": "#3e3a4a", "texture": ""}
	r["wall"] = {"color": "#2a2633", "texture": ""}
	r["sky"] = {"color": "#0b0818", "texture": ""}
	_fill_ground(r, "crystal_cave", "cave_floor", "gem_floor", 7)
	_wall_row(r, "crystal_cave", "cave_wall", 0)
	for x in range(8, 12):
		for z in range(6, 9):
			RoomOps.set_ground(r, x, z, "crystal_cave", "cave_pool")
			RoomOps.add_sprite(r, x, 0, z, "crystal_cave", "cave_pool", "floor", true)
	for p in [Vector2i(2, 3), Vector2i(12, 2), Vector2i(4, 9), Vector2i(7, 1)]:
		RoomOps.add_sprite(r, p.x, 0, p.y, "crystal_cave", "crystal", "standing", true)
	for p in [Vector2i(1, 6), Vector2i(10, 10), Vector2i(6, 6)]:
		RoomOps.add_sprite(r, p.x, 0, p.y, "crystal_cave", "glow_shroom", "standing", false)
	RoomOps.add_sprite(r, 12, 0, 10, "crystal_cave", "stalagmite", "standing", true)
	r["spawn"] = [5, 10]
	return r


static func old_library(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 14, "d": 10, "h": 3}
	r["floor"] = {"color": "#a87a4f", "texture": ""}
	r["wall"] = {"color": "#4a3426", "texture": ""}
	_fill_ground(r, "library", "parquet")
	for z in 10:
		RoomOps.set_ground(r, 7, z, "library", "runner")
	_wall_row(r, "library", "book_wall", 0)
	_wall_row(r, "library", "book_wall", 0, "wall_n", 1)
	for p in [Vector2i(3, 3), Vector2i(11, 3), Vector2i(3, 7), Vector2i(11, 7)]:
		RoomOps.add_sprite(r, p.x, 0, p.y, "library", "column", "standing", true)
	RoomOps.add_sprite(r, 5, 0, 5, "library", "desk", "standing", true)
	RoomOps.add_sprite(r, 9, 0, 5, "library", "desk", "standing", true)
	RoomOps.add_sprite(r, 12, 0, 1, "library", "globe", "standing", true)
	RoomOps.add_sprite(r, 1, 0, 1, "library", "green_lamp", "standing", true)
	r["spawn"] = [7, 8]
	return r


static func candy_land(id: String, name: String) -> Dictionary:
	var r := Defaults.room(id, name)
	r["size"] = {"w": 14, "d": 12, "h": 2}
	r["kind"] = "outdoor"
	r["walls"] = {"north": false, "east": false, "south": false, "west": false}
	r["floor"] = {"color": "#ffc4d6", "texture": ""}
	r["sky"] = {"color": "#ffd6f0", "texture": ""}
	_fill_ground(r, "candy", "frosting", "sprinkles", 4)
	for x in 14:
		RoomOps.set_ground(r, x, 6, "candy", "cookie")
	for x in range(2, 6):
		for z in range(8, 11):
			RoomOps.set_ground(r, x, z, "candy", "chocolate")
	for x in range(9, 12):
		for z in range(1, 4):
			RoomOps.set_ground(r, x, z, "candy", "jelly")
	for p in [Vector2i(1, 2), Vector2i(12, 9), Vector2i(7, 3)]:
		RoomOps.add_sprite(r, p.x, 0, p.y, "candy", "candy_cane", "standing", true)
	for p in [Vector2i(4, 2), Vector2i(10, 10), Vector2i(13, 4)]:
		RoomOps.add_sprite(r, p.x, 0, p.y, "candy", "gumdrop", "standing", true)
	RoomOps.add_sprite(r, 7, 0, 11, "candy", "licorice", "standing", true)
	r["spawn"] = [7, 9]
	return r


static func _more_place(id: String, name: String) -> Dictionary:
	match id:
		"kitchen":
			return kitchen(id, name)
		"bathroom":
			return bathroom(id, name)
		"town_street":
			return town_street(id, name)
		"snowy_village":
			return snowy_village(id, name)
		"farm":
			return farm(id, name)
		"crystal_cave":
			return crystal_cave(id, name)
		"old_library":
			return old_library(id, name)
	return candy_land(id, name)
