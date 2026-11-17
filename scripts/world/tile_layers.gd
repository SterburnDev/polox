extends RefCounted
## A room's tile layers (Phase 14): each layer is a sparse grid of cells,
## drawn in list order (first = bottom). Custom layers (Phase 15) are just
## more entries.
##
##   room.tile_layers = [layer, ...]
##   layer = {id, name, type, elevation, opacity, visible, locked, cells: {"x,z": cell}}
##   cell  = {s: set, t: tile, o: orient, y: level (+elevation), r: quarter turns,
##            fl: mirrored, tint: "#rrggbb", fade: bool, solid: bool}
##           (keys at their default are left out to keep files small)
##
## Types: backdrop (pictures on the walls, behind everything), ground (flat on
## the floor), blocks (pictures standing in the room: scenery, solid when the
## tile says so), foreground (in front of people; fades when hiding someone).
## Rooms from before 0.9 kept ground/foreground lists and "sprite" blocks:
## upgrade() turns those into layers (nothing is lost; stacks in one cell
## become an extra layer of the same type).

const VERSION := 1
const TYPES: PackedStringArray = ["backdrop", "ground", "blocks", "foreground"]
const TYPE_NAMES := {"backdrop": "Backdrop", "ground": "Ground", "blocks": "Blocks", "foreground": "Foreground"}
const DEFAULT_ORIENT := {"backdrop": "wall_n", "ground": "floor", "blocks": "standing", "foreground": "standing"}
const ORIENTS: PackedStringArray = ["floor", "wall_n", "wall_e", "wall_s", "wall_w", "standing"]
const MAX_LAYERS := 16
## Names kept for the backdrop picture and the 3D pieces (room.layers), never a tile layer's id.
const RESERVED_IDS: PackedStringArray = ["backdrop", "pieces"]
const MAX_LEVEL := 5
const CHUNK := 16


static func new_layer(id: String, name: String, type: String) -> Dictionary:
	var t := type if type in TYPES else "ground"
	return {"id": id, "name": name if name != "" else str(TYPE_NAMES[t]), "type": t, "elevation": 0, "opacity": 1.0, "visible": true, "locked": false, "cells": {}}


## Ground, Blocks, Foreground: what every new room starts with.
static func default_layers() -> Array:
	return [new_layer("ground", "Ground", "ground"), new_layer("blocks", "Blocks", "blocks"), new_layer("foreground", "Foreground", "foreground")]


# --- Upgrade and sanitize ----------------------------------------------------------------------

## Makes sure the room has tile layers (converting a pre-0.9 room). Returns true if it changed.
static func upgrade(room: Dictionary) -> bool:
	if room.get("tile_layers") is Array:
		_sanitize(room)
		var old_ground: Variant = room.get("ground", [])
		var old_foreground: Variant = room.get("foreground", [])
		var has_old: bool = false
		if old_ground is Array:
			has_old = not old_ground.is_empty()
		if old_foreground is Array:
			has_old = has_old or not old_foreground.is_empty()
		for t in room.get("tiles", []):
			if t is Dictionary and str(t.get("type", "")) == "sprite":
				has_old = true
				break
		if not has_old:
			return false
		_convert_legacy(room)
		return true
	var states: Dictionary = room.get("layers", {}) if room.get("layers") is Dictionary else {}
	var layers := default_layers()
	for l in layers:
		var st: Dictionary = states.get(l.id, {}) if states.get(l.id) is Dictionary else {}
		l["visible"] = bool(st.get("visible", true))
		l["locked"] = bool(st.get("lock", false))
		l["opacity"] = clampf(float(st.get("opacity", 1.0)), 0.0, 1.0)
	room["tile_layers"] = layers
	for g in (room.get("ground", []) if room.get("ground") is Array else []):
		if g is Dictionary and str(g.get("set", "")) != "":
			_put_or_overflow(room, "ground", int(g.get("x", 0)), int(g.get("z", 0)), make_cell(str(g.set), str(g.get("tile", "")), "floor", {"r": g.get("rot", 0), "fl": g.get("flip", false), "tint": g.get("tint", "#ffffff")}))
	var keep: Array = []
	for t in (room.get("tiles", []) if room.get("tiles") is Array else []):
		if t is Dictionary and str(t.get("type", "")) == "sprite":
			_put_or_overflow(room, "blocks", int(t.get("x", 0)), int(t.get("z", 0)), make_cell(str(t.get("set", "")), str(t.get("tile", "")), str(t.get("orient", "standing")),
				{"y": t.get("y", 0), "r": t.get("rot", 0), "fl": t.get("flip", false), "tint": t.get("tint", "#ffffff"), "solid": t.get("solid", false)}))
		else:
			keep.append(t)
	room["tiles"] = keep
	for f in (room.get("foreground", []) if room.get("foreground") is Array else []):
		if f is Dictionary and str(f.get("set", "")) != "":
			_put_or_overflow(room, "foreground", int(f.get("x", 0)), int(f.get("z", 0)), make_cell(str(f.set), str(f.get("tile", "")), str(f.get("orient", "standing")),
				{"y": f.get("y", 0), "r": f.get("rot", 0), "fl": f.get("flip", false), "tint": f.get("tint", "#ffffff"), "fade": f.get("fade", true), "solid": f.get("solid", false)}))
	room.erase("ground")
	room.erase("foreground")
	room["tile_layers_version"] = VERSION
	return true


## SaveManager merges new defaults before returning an old room, so a legacy
## room may already have empty tile_layers. Merge legacy content into those
## layers rather than letting the defaults hide the old arrays.
static func _convert_legacy(room: Dictionary) -> void:
	for g in (room.get("ground", []) if room.get("ground") is Array else []):
		if g is Dictionary and str(g.get("set", "")) != "":
			_put_or_overflow(room, "ground", int(g.get("x", 0)), int(g.get("z", 0)), make_cell(str(g.set), str(g.get("tile", "")), "floor", {"r": g.get("rot", 0), "fl": g.get("flip", false), "tint": g.get("tint", "#ffffff")}))
	var keep: Array = []
	for t in (room.get("tiles", []) if room.get("tiles", []) is Array else []):
		if t is Dictionary and str(t.get("type", "")) == "sprite":
			_put_or_overflow(room, "blocks", int(t.get("x", 0)), int(t.get("z", 0)), make_cell(str(t.get("set", "")), str(t.get("tile", "")), str(t.get("orient", "standing")),
				{"y": t.get("y", 0), "r": t.get("rot", 0), "fl": t.get("flip", false), "tint": t.get("tint", "#ffffff"), "solid": t.get("solid", false)}))
		else:
			keep.append(t)
	room["tiles"] = keep
	for f in (room.get("foreground", []) if room.get("foreground") is Array else []):
		if f is Dictionary and str(f.get("set", "")) != "":
			_put_or_overflow(room, "foreground", int(f.get("x", 0)), int(f.get("z", 0)), make_cell(str(f.set), str(f.get("tile", "")), str(f.get("orient", "standing")),
				{"y": f.get("y", 0), "r": f.get("rot", 0), "fl": f.get("flip", false), "tint": f.get("tint", "#ffffff"), "fade": f.get("fade", true), "solid": f.get("solid", false)}))
	room.erase("ground")
	room.erase("foreground")
	room["tile_layers_version"] = VERSION


## A second picture in the same cell of a pre-0.9 room goes to "<Layer> 2" (then 3...).
static func _put_or_overflow(room: Dictionary, base_id: String, x: int, z: int, cell: Dictionary) -> void:
	var id := base_id
	var n := 1
	while n <= MAX_LAYERS + 4:
		var l := find(room, id)
		if l.is_empty():
			var base := find(room, base_id)
			l = new_layer(id, "%s %d" % [str(base.get("name", base_id)), n], str(base.get("type", "ground")))
			var layers: Array = room.tile_layers
			layers.insert(index_of(room, "%s_%d" % [base_id, n - 1] if n > 2 else base_id) + 1, l)
		if not (l.cells as Dictionary).has(key(x, z)):
			put(l, x, z, cell)
			return
		n += 1
		id = "%s_%d" % [base_id, n]


static func _sanitize(room: Dictionary) -> void:
	var seen := {}
	var out: Array = []
	for l in room.tile_layers:
		if not l is Dictionary:
			continue
		var t := str(l.get("type", "ground"))
		if not t in TYPES:
			t = "ground"
		var id := str(l.get("id", ""))
		if id == "" or seen.has(id) or id in RESERVED_IDS:
			id = "%s_%d" % [t, out.size() + 1]
		seen[id] = true
		var cells: Variant = l.get("cells", {})
		var clean := {}
		if cells is Dictionary:
			for k in cells:
				if cells[k] is Dictionary and str(cells[k].get("s", "")) != "":
					clean[str(k)] = cells[k]
		out.append({"id": id, "name": str(l.get("name", TYPE_NAMES[t])).substr(0, 40), "type": t,
			"elevation": clampi(int(l.get("elevation", 0)), -MAX_LEVEL, MAX_LEVEL), "opacity": clampf(float(l.get("opacity", 1.0)), 0.0, 1.0),
			"visible": bool(l.get("visible", true)), "locked": bool(l.get("locked", false)), "cells": clean})
	room["tile_layers"] = out.slice(0, MAX_LAYERS)


# --- Layers -----------------------------------------------------------------------------------

static func all(room: Dictionary) -> Array:
	if not room.get("tile_layers") is Array:
		upgrade(room)
	return room.tile_layers


static func find(room: Dictionary, id: String) -> Dictionary:
	for l in room.get("tile_layers", []):
		if str(l.get("id", "")) == id:
			return l
	return {}


static func index_of(room: Dictionary, id: String) -> int:
	var layers: Array = room.get("tile_layers", [])
	for i in layers.size():
		if str(layers[i].get("id", "")) == id:
			return i
	return -1


## The first layer of a type (bottom-most), or {}.
static func of_type(room: Dictionary, type: String) -> Dictionary:
	for l in all(room):
		if str(l.type) == type:
			return l
	return {}


## The first layer of a type, made if the room has none.
static func ensure_type(room: Dictionary, type: String) -> Dictionary:
	var l := of_type(room, type)
	return l if not l.is_empty() else add(room, "", type)


static func add(room: Dictionary, name: String, type: String) -> Dictionary:
	var layers := all(room)
	if layers.size() >= MAX_LAYERS:
		return {}
	var t := type if type in TYPES else "ground"
	var taken := {"backdrop": true, "pieces": true}
	var same := 0
	for l in layers:
		taken[str(l.id)] = true
		if str(l.type) == t:
			same += 1
	var n := 1
	var id := t
	while taken.has(id):
		n += 1
		id = "%s_%d" % [t, n]
	var auto_name := "%s %d" % [TYPE_NAMES[t], same + 1] if same > 0 else str(TYPE_NAMES[t])
	var l := new_layer(id, name.strip_edges().substr(0, 40) if name.strip_edges() != "" else auto_name, t)
	layers.append(l)
	return l


static func remove(room: Dictionary, id: String) -> bool:
	var i := index_of(room, id)
	if i < 0:
		return false
	(room.tile_layers as Array).remove_at(i)
	return true


static func move(room: Dictionary, id: String, delta: int) -> bool:
	var i := index_of(room, id)
	var layers: Array = room.get("tile_layers", [])
	var j := clampi(i + delta, 0, layers.size() - 1)
	if i < 0 or j == i:
		return false
	var l: Dictionary = layers.pop_at(i)
	layers.insert(j, l)
	return true


# --- Cells ------------------------------------------------------------------------------------

static func key(x: int, z: int) -> String:
	return "%d,%d" % [x, z]


static func parse_key(k: String) -> Vector2i:
	var c := k.find(",")
	return Vector2i(k.substr(0, c).to_int(), k.substr(c + 1).to_int())


static func get_cell(layer: Dictionary, x: int, z: int) -> Dictionary:
	var cells: Dictionary = layer.get("cells", {})
	return cells.get(key(x, z), {})


static func put(layer: Dictionary, x: int, z: int, cell: Dictionary) -> void:
	if not layer.get("cells") is Dictionary:
		layer["cells"] = {}
	layer.cells[key(x, z)] = cell


static func erase(layer: Dictionary, x: int, z: int) -> bool:
	var cells: Dictionary = layer.get("cells", {})
	return cells.erase(key(x, z))


## A cell with only the keys that differ from the defaults.
static func make_cell(set_id: String, tile_id: String, orient: String = "", flags: Dictionary = {}) -> Dictionary:
	var c := {"s": set_id, "t": tile_id}
	if orient != "" and orient in ORIENTS:
		c["o"] = orient
	var y := clampi(int(flags.get("y", 0)), 0, MAX_LEVEL)
	if y != 0:
		c["y"] = y
	var r := posmod(int(flags.get("r", 0)), 4)
	if r != 0:
		c["r"] = r
	if bool(flags.get("fl", false)):
		c["fl"] = true
	var tint := str(flags.get("tint", "#ffffff")).to_lower()
	if tint != "#ffffff" and tint != "" and tint != "#ffffffff":
		c["tint"] = tint
	if flags.has("fade") and not bool(flags.fade):
		c["fade"] = false
	if flags.has("solid") and flags.solid != null:
		c["solid"] = bool(flags.solid)
	for extra in ["event", "event_done", "smart_group", "smart_mask", "smart_tile"]:
		if flags.has(extra):
			c[extra] = flags[extra]
	return c


static func orient_of(layer: Dictionary, cell: Dictionary) -> String:
	var o := str(cell.get("o", ""))
	return o if o in ORIENTS else str(DEFAULT_ORIENT.get(str(layer.get("type", "ground")), "floor"))


## Height above the floor in cells: the layer's elevation plus the cell's own level.
static func level_of(layer: Dictionary, cell: Dictionary) -> int:
	return int(layer.get("elevation", 0)) + int(cell.get("y", 0))


static func count(room: Dictionary) -> int:
	var n := 0
	for l in all(room):
		n += (l.cells as Dictionary).size()
	return n


## Every [set, tile] a room or a stamp paints with (old rooms are read
## through a converted copy; the room itself is left alone).
static func tiles_used(room: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	var add_one := func(c: Variant):
		if c is Dictionary and str(c.get("s", "")) != "":
			var k := "%s/%s" % [c.s, c.get("t", "")]
			if not seen.has(k):
				seen[k] = true
				out.append([str(c.s), str(c.get("t", ""))])
	if room.get("cells") is Array:   # a stamp
		for e in room.cells:
			if e is Dictionary:
				add_one.call(e.get("cell"))
		return out
	var r := room
	if not room.get("tile_layers") is Array:
		r = room.duplicate(true)
		upgrade(r)
	for l in r.tile_layers:
		for c in (l.cells as Dictionary).values():
			add_one.call(c)
	return out


## A stand-in room holding a stamp's tiles as layers (for thumbnails).
static func room_from_stamp(stamp: Dictionary) -> Dictionary:
	var r := {"size": {"w": int(stamp.get("w", 1)), "d": int(stamp.get("d", 1))}, "tiles": stamp.get("tiles", []), "objects": stamp.get("objects", []), "tile_layers": []}
	for e in stamp.get("cells", []):
		var l := find(r, str(e.get("layer", "")))
		if l.is_empty():
			l = new_layer(str(e.get("layer", "")), "", str(e.get("type", "ground")))
			(r.tile_layers as Array).append(l)
		put(l, int(e.x), int(e.z), e.cell)
	return r


## Cells of every layer of one type, as [[layer, Vector2i, cell], ...] (for tools and checks).
static func cells_of_type(room: Dictionary, type: String) -> Array:
	var out: Array = []
	for l in all(room):
		if str(l.type) == type:
			for k in l.cells:
				out.append([l, parse_key(str(k)), l.cells[k]])
	return out


# --- Walking ------------------------------------------------------------------------------------

## Does any tile stop walking on (x, z)? `info` = Callable(set, tile) -> tile flags.
## Ground: a tile with walkable = false (water, a gap). Blocks and Foreground:
## a solid picture standing on the floor (level 0).
static func blocks_walk(room: Dictionary, x: int, z: int, info: Callable) -> bool:
	var k := key(x, z)
	for l in all(room):
		var c: Variant = (l.cells as Dictionary).get(k)
		if c == null:
			continue
		match str(l.type):
			"ground":
				if level_of(l, c) == 0 and not bool(info.call(str(c.s), str(c.t)).get("walkable", true)):
					return true
			"blocks", "foreground":
				if level_of(l, c) == 0:
					var solid: Variant = c.get("solid")
					if solid == null:
						solid = bool(info.call(str(c.s), str(c.t)).get("solid", false)) if str(l.type) == "blocks" else false
					if bool(solid):
						return true
	return false
