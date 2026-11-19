extends RefCounted
## Pure data operations on room dictionaries (no nodes), used by build mode
## and covered by tests: stacking tiles, objects, painting, resizing, and
## room-level management (create / rename / duplicate / delete / link doors).

const BlockFactory := preload("res://scripts/world/block_factory.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")

const MAX_HEIGHT := 6.0
const MAX_SIZE := 100   # cells per side (the tile layers are chunked, so big rooms stay fast)


## Drops anything a hand edit (or a bad copy) left malformed: tiles and
## objects must be dictionaries with numeric positions inside the room.
## Returns how many entries were dropped.
static func sanitize(room: Dictionary) -> int:
	var dropped := 0
	var size: Variant = room.get("size", {})
	if not size is Dictionary:
		room["size"] = {"w": 12, "d": 10, "h": 3}
	room["size"]["w"] = clampi(int(room["size"].get("w", 12)), 3, MAX_SIZE)
	room["size"]["d"] = clampi(int(room["size"].get("d", 10)), 3, MAX_SIZE)
	room["size"]["h"] = clampf(float(room["size"].get("h", 3)), 1.0, 8.0)
	TileLayers.upgrade(room)   # a room from before 0.9: ground/foreground lists become tile layers
	var tiles: Array = []
	for t in room.get("tiles", []) if room.get("tiles", []) is Array else []:
		if t is Dictionary and _num(t.get("x")) and _num(t.get("z")) and in_bounds(room, int(t.x), int(t.z)):
			if not _num(t.get("y")):
				t["y"] = 0.0
			if not str(t.get("type", "")) in BlockFactory.TILE_TYPES and str(t.get("type", "")) != "sprite":
				t["type"] = "cube"
			tiles.append(t)
		else:
			dropped += 1
	room["tiles"] = tiles
	for l in TileLayers.all(room):
		for k in (l.cells as Dictionary).keys():
			var c := TileLayers.parse_key(str(k))
			if not in_bounds(room, c.x, c.y):
				l.cells.erase(k)
				dropped += 1
	if not room.get("layers") is Dictionary:
		room["layers"] = Defaults.room()["layers"]
	var objects: Array = []
	for o in room.get("objects", []) if room.get("objects", []) is Array else []:
		var pos: Variant = o.get("pos") if o is Dictionary else null
		if pos is Array and pos.size() >= 3 and _num(pos[0]) and _num(pos[1]) and _num(pos[2]) and in_bounds(room, int(pos[0]), int(pos[2])):
			if str(o.get("id", "")) == "":
				o["id"] = next_object_id(room, str(o.get("type", "prop")))
			objects.append(o)
		else:
			dropped += 1
	room["objects"] = objects
	var sp: Variant = room.get("spawn")
	if not (sp is Array and sp.size() >= 2 and _num(sp[0]) and _num(sp[1])):
		room["spawn"] = [floori(int(room.size.w) / 2.0), int(room.size.d) - 2]
	for surface in ["floor", "wall", "sky"]:
		if not room.get(surface) is Dictionary:
			room[surface] = Defaults.room()[surface]
	if not room.get("ambiance") is Dictionary:
		room["ambiance"] = Defaults.room()["ambiance"]
	return dropped


static func _num(v: Variant) -> bool:
	return v is int or v is float


static func in_bounds(room: Dictionary, x: int, z: int) -> bool:
	var s: Dictionary = room.get("size", {})
	return x >= 0 and z >= 0 and x < int(s.get("w", 12)) and z < int(s.get("d", 10))


## Height of the top of everything stacked on cell (x, z).
static func stack_top(room: Dictionary, x: int, z: int) -> float:
	var top := 0.0
	for t in room.get("tiles", []):
		if int(t.get("x", -1)) == x and int(t.get("z", -1)) == z:
			top = maxf(top, float(t.get("y", 0)) + BlockFactory.height_of(str(t.get("type", "cube"))))
	return top


static func object_at(room: Dictionary, x: int, z: int) -> Dictionary:
	for o in room.get("objects", []):
		var p: Array = o.get("pos", [0, 0, 0])
		if int(p[0]) == x and int(p[2]) == z:
			return o
		if str(o.get("type", "")) == "furniture" and load("res://scripts/world/furniture.gd").footprint(o).has_point(Vector2i(x, z)):
			return o   # (a bed or a sofa covers more than one cell)
	return {}


## Stacks a tile on (x, z). Returns the tile, or {} if out of bounds / too tall.
static func add_tile(room: Dictionary, x: int, z: int, type: String, color: String, texture: String = "", rot: int = 0) -> Dictionary:
	if not in_bounds(room, x, z) or not object_at(room, x, z).is_empty():
		return {}
	var y := stack_top(room, x, z)
	if y + BlockFactory.height_of(type) > MAX_HEIGHT:
		return {}
	var t := {"x": x, "y": y, "z": z, "type": type, "color": color, "texture": texture, "rot": posmod(rot, 4)}
	room["tiles"].append(t)
	return t


## Removes the top-most tile on (x, z). Returns true if something was removed.
static func remove_top_tile(room: Dictionary, x: int, z: int) -> bool:
	var best := -1
	var best_y := -1.0
	var tiles: Array = room.get("tiles", [])
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		if int(t.get("x", -1)) == x and int(t.get("z", -1)) == z and float(t.get("y", 0)) > best_y:
			best = i
			best_y = float(t.get("y", 0))
	if best == -1:
		return false
	tiles.remove_at(best)
	return true


static func next_object_id(room: Dictionary, type: String) -> String:
	var taken := {}
	for o in room.get("objects", []):
		taken[str(o.get("id", ""))] = true
	var n := 1
	while taken.has("%s_%d" % [type, n]):
		n += 1
	return "%s_%d" % [type, n]


## Places a door / sign / prop on top of the stack at (x, z).
static func add_object(room: Dictionary, x: int, z: int, type: String, color: String = "", texture: String = "", rot: int = 0) -> Dictionary:
	if not in_bounds(room, x, z) or not object_at(room, x, z).is_empty():
		return {}
	var o := {
		"id": next_object_id(room, type), "type": type, "pos": [x, stack_top(room, x, z), z],
		"rot": posmod(rot, 4), "scale": 1.0, "color": color, "texture": texture,
		"interaction_text": "", "door_target": "",
	}
	room["objects"].append(o)
	return o


static func remove_object(room: Dictionary, id: String) -> bool:
	var objs: Array = room.get("objects", [])
	for i in objs.size():
		if str(objs[i].get("id", "")) == id:
			objs.remove_at(i)
			return true
	return false


## Recolors the object on (x, z), or else the top-most tile there.
## Returns false if the cell is empty (nothing to paint).
static func paint_piece_at(room: Dictionary, x: int, z: int, color: String, texture: String = "") -> bool:
	var target := object_at(room, x, z)
	if target.is_empty():
		for t in room.get("tiles", []):
			if int(t.get("x", -1)) == x and int(t.get("z", -1)) == z and (target.is_empty() or float(t.get("y", 0)) > float(target.get("y", 0))):
				target = t
	if target.is_empty():
		return false
	target["color"] = color
	target["texture"] = texture
	return true


## Turns every tile on (x, z) a quarter turn. Returns false if there are none.
static func rotate_tiles_at(room: Dictionary, x: int, z: int) -> bool:
	var any := false
	for t in room.get("tiles", []):
		if int(t.get("x", -1)) == x and int(t.get("z", -1)) == z:
			t["rot"] = posmod(int(t.get("rot", 0)) + 1, 4)
			any = true
	return any


## surface: "floor" | "wall" | "sky"
static func paint_surface(room: Dictionary, surface: String, color: String, texture: String = "") -> void:
	room[surface] = {"color": color, "texture": texture}


## Changes the room size, dropping anything that no longer fits.
static func resize(room: Dictionary, w: int, d: int) -> void:
	room["size"]["w"] = clampi(w, 3, MAX_SIZE)
	room["size"]["d"] = clampi(d, 3, MAX_SIZE)
	room["tiles"] = room.get("tiles", []).filter(func(t): return in_bounds(room, int(t.get("x", 0)), int(t.get("z", 0))))
	for l in TileLayers.all(room):
		for k in (l.cells as Dictionary).keys():
			var c := TileLayers.parse_key(str(k))
			if not in_bounds(room, c.x, c.y):
				l.cells.erase(k)
	room["objects"] = room.get("objects", []).filter(func(o): return in_bounds(room, int(o.pos[0]), int(o.pos[2])))
	var sp: Array = room.get("spawn", [0, 0])
	room["spawn"] = [clampi(int(sp[0]), 0, int(room.size.w) - 1), clampi(int(sp[1]), 0, int(room.size.d) - 1)]


# --- Room management (touches the save folder) -----------------------------------

static func create_room(display_name: String, w: int = 10, d: int = 8) -> String:
	var id := SaveManager.unique_id(display_name, SaveManager.list_rooms())
	var r := Defaults.room(id, display_name.strip_edges() if display_name.strip_edges() != "" else "New Room")
	resize(r, w, d)
	r["spawn"] = [floori(w / 2.0), d - 2]
	SaveManager.save_room(r)
	return id


static func rename_room(id: String, new_name: String) -> void:
	var r := SaveManager.load_room(id)
	r["name"] = new_name.strip_edges()
	SaveManager.save_room(r)


static func duplicate_room(id: String) -> String:
	var r := SaveManager.load_room(id)
	var new_id := SaveManager.unique_id(str(r.get("name", id)) + " copy", SaveManager.list_rooms())
	r["id"] = new_id
	r["name"] = str(r.get("name", id)) + " (copy)"
	if r.get("edges") is Dictionary and not (r.edges as Dictionary).is_empty():
		r["edges"] = {}   # a join belongs to one pair of places; the copy stands on its own
	SaveManager.save_room(r)
	return new_id


## Deletes a room safely: unlinks doors that pointed to it and moves its
## residents to the start room. Refuses to delete the last room.
static func delete_room(id: String) -> bool:
	var rooms := SaveManager.list_rooms()
	if rooms.size() <= 1 or not id in rooms:
		return false
	rooms.remove_at(rooms.find(id))
	var start := str(GameState.world.get("start_room", "home"))
	if start == id or not start in rooms:
		start = rooms[0]
		GameState.world["start_room"] = start
		GameState.save_world()
	for other in rooms:
		var r := SaveManager.load_room(other)
		var changed := false
		for o in r.get("objects", []):
			if str(o.get("door_target", "")) == id:
				o["door_target"] = ""
				changed = true
		var e: Variant = r.get("edges")
		if e is Dictionary:
			for side in (e as Dictionary).keys():
				if str(e[side]) == id:
					(e as Dictionary).erase(side)   # that side stays open (a wall can go back in the Place tab)
					changed = true
		if changed:
			SaveManager.save_room(r)
	for cid in GameState.characters:
		var c: Dictionary = GameState.characters[cid]
		if str(c.get("home_room", "")) == id:
			c["home_room"] = start
			c["pos"] = []
			GameState.save_character(c)
	SaveManager.delete_room(id)
	return true


## Links door `door_id` in room `from_id` to room `to_id`, and makes sure the
## target room has a door leading back (creating one near its spawn).
static func link_door(from_id: String, door_id: String, to_id: String) -> void:
	var from := SaveManager.load_room(from_id)
	for o in from.get("objects", []):
		if str(o.get("id", "")) == door_id:
			o["door_target"] = to_id
			if str(o.get("interaction_text", "")) == "":
				o["interaction_text"] = "To " + str(SaveManager.load_room(to_id).get("name", to_id))
	SaveManager.save_room(from)
	if to_id == from_id:
		return
	var to := SaveManager.load_room(to_id)
	for o in to.get("objects", []):
		if str(o.get("type", "")) == "door" and str(o.get("door_target", "")) == from_id:
			return
	# No way back yet: put a door on the west edge, in line with the spawn.
	var sp: Array = to.get("spawn", [1, 1])
	var z := clampi(int(sp[1]), 0, int(to.size.d) - 1)
	var x := 0
	while x < int(to.size.w) and (not object_at(to, x, z).is_empty() or stack_top(to, x, z) > 0.0):
		x += 1
	var back := add_object(to, x, z, "door", "", "", 1)
	if not back.is_empty():
		back["door_target"] = from_id
		back["interaction_text"] = "Back to " + str(from.get("name", from_id))
		SaveManager.save_room(to)
