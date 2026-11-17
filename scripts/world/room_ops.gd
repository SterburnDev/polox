extends RefCounted
## Pure data operations for the editor's layers and tools (no nodes): tiles on
## any tile layer (tile_layers.gd), shape rasterizing (line, rectangle, flood
## fill, brush), region copy/paste/rotate/flip (stamps), and the "Room check".
## Block pieces themselves live in room_editor.gd.

const RoomEditor := preload("res://scripts/world/room_editor.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")

## Layers with their own visible/lock/opacity in room.layers: the backdrop
## picture and the 3D block pieces. Tile layers keep theirs in the layer itself.
const LAYERS: PackedStringArray = ["backdrop", "pieces"]
const ORIENTS: PackedStringArray = ["floor", "wall_n", "wall_e", "wall_s", "wall_w", "standing"]
const MAX_ELEVATION := 5
const FILL_LIMIT := 10000


static func layer_defaults() -> Dictionary:
	var out := {}
	for l in LAYERS:
		out[l] = {"visible": true, "lock": false, "opacity": 1.0}
	return out


## visible / lock / opacity of a layer: a tile layer's own fields, or the
## backdrop / pieces state. (Old name "blocks" = the pieces.)
static func layer_state(room: Dictionary, layer: String) -> Dictionary:
	var tl := TileLayers.find(room, layer)
	if not tl.is_empty() and layer != "pieces":
		return {"visible": bool(tl.visible), "lock": bool(tl.locked), "opacity": float(tl.opacity)}
	var key := "pieces" if layer == "blocks" and tl.is_empty() else layer
	var layers: Variant = room.get("layers", {})
	if not layers is Dictionary:
		room["layers"] = layer_defaults()
		layers = room["layers"]
	if not layers.has(key):
		var old: Variant = layers.get("blocks") if key == "pieces" else null
		layers[key] = old.duplicate() if old is Dictionary else {"visible": true, "lock": false, "opacity": 1.0}
	return layers[key]


static func set_layer_state(room: Dictionary, layer: String, field: String, value: Variant) -> void:
	var tl := TileLayers.find(room, layer)
	if not tl.is_empty() and layer != "pieces":
		tl[{"lock": "locked"}.get(field, field)] = value
		return
	layer_state(room, layer)[field] = value


# --- Tiles on any layer --------------------------------------------------------------------

## The layer to paint on: the one asked for, else the first of the type.
static func _layer(room: Dictionary, layer_id: String, type: String) -> Dictionary:
	if layer_id != "":
		var l := TileLayers.find(room, layer_id)
		if not l.is_empty():
			return l
	return TileLayers.ensure_type(room, type)


static func cell_at(room: Dictionary, layer_id: String, x: int, z: int) -> Dictionary:
	var l := TileLayers.find(room, layer_id)
	return {} if l.is_empty() else TileLayers.get_cell(l, x, z)


## Paints a tile on a layer (replacing what was in that cell). Returns the cell or {}.
static func paint(room: Dictionary, layer_id: String, x: int, z: int, set_id: String, tile_id: String, flags: Dictionary = {}) -> Dictionary:
	var l := TileLayers.find(room, layer_id)
	if l.is_empty() or not RoomEditor.in_bounds(room, x, z) or set_id == "" or tile_id == "":
		return {}
	var orient := str(flags.get("o", ""))
	if orient == str(TileLayers.DEFAULT_ORIENT.get(str(l.type), "")):
		orient = ""
	var c := TileLayers.make_cell(set_id, tile_id, orient, flags)
	TileLayers.put(l, x, z, c)
	return c


static func erase(room: Dictionary, layer_id: String, x: int, z: int) -> bool:
	var l := TileLayers.find(room, layer_id)
	return not l.is_empty() and TileLayers.erase(l, x, z)


# Shorthands for the default layers (templates, tests and older callers).

static func ground_at(room: Dictionary, x: int, z: int, layer_id: String = "") -> Dictionary:
	return TileLayers.get_cell(_layer(room, layer_id, "ground"), x, z)


static func set_ground(room: Dictionary, x: int, z: int, set_id: String, tile_id: String, rot: int = 0, flip: bool = false, tint: String = "#ffffff", layer_id: String = "") -> Dictionary:
	return paint(room, str(_layer(room, layer_id, "ground").id), x, z, set_id, tile_id, {"r": rot, "fl": flip, "tint": tint})


static func remove_ground(room: Dictionary, x: int, z: int, layer_id: String = "") -> bool:
	return TileLayers.erase(_layer(room, layer_id, "ground"), x, z)


static func fg_at(room: Dictionary, x: int, z: int, _y: int = -1, layer_id: String = "") -> Dictionary:
	if layer_id != "":
		return TileLayers.get_cell(_layer(room, layer_id, "foreground"), x, z)
	var best: Dictionary = {}
	var best_y := -INF
	for l in TileLayers.all(room):
		if str(l.type) != "foreground":
			continue
		var c := TileLayers.get_cell(l, x, z)
		var y := float(TileLayers.level_of(l, c)) if not c.is_empty() else -INF
		if y > best_y:
			best = c
			best_y = y
	return best


static func add_fg(room: Dictionary, x: int, y: int, z: int, set_id: String, tile_id: String, orient: String = "standing", flags: Dictionary = {}, layer_id: String = "") -> Dictionary:
	var f := flags.duplicate()
	f["y"] = clampi(y, 0, MAX_ELEVATION)
	f["o"] = orient if orient in ORIENTS else "standing"
	for pair in [["rot", "r"], ["flip", "fl"]]:
		if f.has(pair[0]):
			f[pair[1]] = f[pair[0]]
	var target := _layer(room, layer_id, "foreground")
	if layer_id == "":
		var found_empty := false
		for l in TileLayers.all(room):
			if str(l.type) == "foreground" and TileLayers.get_cell(l, x, z).is_empty():
				target = l
				found_empty = true
				break
		if not found_empty and not target.is_empty() and not TileLayers.get_cell(target, x, z).is_empty():
			target = TileLayers.add(room, "", "foreground")
	return paint(room, str(target.get("id", "")), x, z, set_id, tile_id, f)


static func remove_fg_top(room: Dictionary, x: int, z: int, layer_id: String = "") -> bool:
	if layer_id != "":
		return TileLayers.erase(_layer(room, layer_id, "foreground"), x, z)
	var best: Dictionary = {}
	var best_layer: Dictionary = {}
	var best_y := -INF
	for l in TileLayers.all(room):
		if str(l.type) != "foreground":
			continue
		var c := TileLayers.get_cell(l, x, z)
		var y := float(TileLayers.level_of(l, c)) if not c.is_empty() else -INF
		if y > best_y:
			best = c
			best_layer = l
			best_y = y
	return not best.is_empty() and TileLayers.erase(best_layer, x, z)


## A picture standing in the room (or on a wall) on a Blocks layer.
static func add_sprite(room: Dictionary, x: int, y: int, z: int, set_id: String, tile_id: String, orient: String = "standing", solid: Variant = null, layer_id: String = "") -> Dictionary:
	if not RoomEditor.object_at(room, x, z).is_empty():
		return {}
	var f := {"y": clampi(y, 0, MAX_ELEVATION), "o": orient if orient in ORIENTS else "standing"}
	if solid != null:
		f["solid"] = bool(solid)
	return paint(room, str(_layer(room, layer_id, "blocks").id), x, z, set_id, tile_id, f)


## Anything at (x, z) that stops walking: block pieces, solid pictures, unwalkable ground.
static func blocks_walk(room: Dictionary, x: int, z: int) -> bool:
	for t in room.get("tiles", []):
		if int(t.get("x", -1)) != x or int(t.get("z", -1)) != z:
			continue
		if str(t.get("type", "cube")) in ["cube", "ramp", "pillar"] and float(t.get("y", 0)) < 1.0:
			return true
	return TileLayers.blocks_walk(room, x, z, Tilesets.info)


# --- Shapes -------------------------------------------------------------------------------

static func line_cells(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return out


static func rect_cells(a: Vector2i, b: Vector2i, filled: bool) -> Array:
	var out: Array = []
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if filled or x == lo.x or x == hi.x or y == lo.y or y == hi.y:
				out.append(Vector2i(x, y))
	return out


## A square brush of `size` cells (1-5) around the cursor.
static func brush_cells(center: Vector2i, size: int) -> Array:
	var out: Array = []
	var n := clampi(size, 1, 5)
	var r0 := -floori((n - 1) / 2.0)
	for dy in range(r0, r0 + n):
		for dx in range(r0, r0 + n):
			out.append(center + Vector2i(dx, dy))
	return out


## Cells connected to `start` that hold the same tile on that layer (or are all empty).
static func flood_cells(room: Dictionary, start: Vector2i, layer_id: String = "") -> Array:
	var w := int(room.size.w)
	var d := int(room.size.d)
	if start.x < 0 or start.y < 0 or start.x >= w or start.y >= d:
		return []
	var l := _layer(room, layer_id, "ground")
	var key := _tile_key(l, start.x, start.y)
	var seen := {}
	var out: Array = []
	var stack: Array = [start]
	while not stack.is_empty() and out.size() < FILL_LIMIT:
		var p: Vector2i = stack.pop_back()
		if seen.has(p) or p.x < 0 or p.y < 0 or p.x >= w or p.y >= d:
			continue
		seen[p] = true
		if _tile_key(l, p.x, p.y) != key:
			continue
		out.append(p)
		for n in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			stack.append(p + n)
	return out


static func _tile_key(l: Dictionary, x: int, z: int) -> String:
	var c := TileLayers.get_cell(l, x, z)
	return "" if c.is_empty() else "%s/%s" % [c.s, c.t]


# --- Regions (select, copy, paste, rotate, flip) --------------------------------------------------

## Everything inside the cell rectangle as a stamp, positions relative to its corner:
## {version: 2, w, d, cells: [{layer, type, x, z, cell}], tiles (block pieces), objects}
static func copy_region(room: Dictionary, a: Vector2i, b: Vector2i) -> Dictionary:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var stamp := {"version": 2, "w": hi.x - lo.x + 1, "d": hi.y - lo.y + 1, "cells": [], "tiles": [], "objects": []}
	for l in TileLayers.all(room):
		for z in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var c := TileLayers.get_cell(l, x, z)
				if not c.is_empty():
					stamp.cells.append({"layer": str(l.id), "type": str(l.type), "x": x - lo.x, "z": z - lo.y, "cell": c.duplicate(true)})
	for t in room.get("tiles", []):
		var x := int(t.get("x", -1))
		var z := int(t.get("z", -1))
		if x >= lo.x and x <= hi.x and z >= lo.y and z <= hi.y:
			var c: Dictionary = t.duplicate(true)
			c["x"] = x - lo.x
			c["z"] = z - lo.y
			stamp.tiles.append(c)
	for o in room.get("objects", []):
		var pos: Array = o.get("pos", [0, 0, 0])
		if int(pos[0]) >= lo.x and int(pos[0]) <= hi.x and int(pos[2]) >= lo.y and int(pos[2]) <= hi.y:
			var c: Dictionary = o.duplicate(true)
			c["pos"] = [int(pos[0]) - lo.x, pos[1], int(pos[2]) - lo.y]
			stamp.objects.append(c)
	return stamp


## A stamp from before 0.9 (ground / foreground lists, sprite blocks) in today's form.
static func upgrade_stamp(stamp: Dictionary) -> Dictionary:
	if int(stamp.get("version", 1)) >= 2:
		return stamp
	var room := {"tiles": stamp.get("tiles", []).duplicate(true), "ground": stamp.get("ground", []), "foreground": stamp.get("foreground", [])}
	TileLayers.upgrade(room)
	var out := {"version": 2, "w": int(stamp.get("w", 1)), "d": int(stamp.get("d", 1)), "cells": [], "tiles": room.tiles, "objects": stamp.get("objects", []).duplicate(true)}
	for l in room.tile_layers:
		for k in l.cells:
			var c := TileLayers.parse_key(str(k))
			out.cells.append({"layer": str(l.id), "type": str(l.type), "x": c.x, "z": c.y, "cell": l.cells[k]})
	for key in ["name", "id", "created"]:
		if stamp.has(key):
			out[key] = stamp[key]
	return out


static func clear_region(room: Dictionary, a: Vector2i, b: Vector2i) -> void:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var inside := func(x: int, z: int) -> bool: return x >= lo.x and x <= hi.x and z >= lo.y and z <= hi.y
	for l in TileLayers.all(room):
		for z in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				TileLayers.erase(l, x, z)
	room["tiles"] = room.get("tiles", []).filter(func(e): return not inside.call(int(e.get("x", -1)), int(e.get("z", -1))))
	room["objects"] = room.get("objects", []).filter(func(o): return not inside.call(int(o.pos[0]), int(o.pos[2])))


## Puts a stamp down with its corner at `origin`. mode: "merge" keeps what is
## under empty stamp cells; "replace" clears the whole footprint first. Cells
## go to the layer they came from (same id), else the first layer of that type.
static func paste(room: Dictionary, stamp_in: Dictionary, origin: Vector2i, mode: String = "merge") -> int:
	var stamp := upgrade_stamp(stamp_in)
	var placed := 0
	var w := int(stamp.get("w", 1))
	var d := int(stamp.get("d", 1))
	if mode == "replace":
		clear_region(room, origin, origin + Vector2i(w - 1, d - 1))
	for e in stamp.get("cells", []):
		var x := origin.x + int(e.x)
		var z := origin.y + int(e.z)
		if not RoomEditor.in_bounds(room, x, z):
			continue
		var l := TileLayers.find(room, str(e.get("layer", "")))
		if l.is_empty() or str(l.type) != str(e.get("type", "")):
			l = TileLayers.ensure_type(room, str(e.get("type", "ground")))
		if l.is_empty():
			continue
		TileLayers.put(l, x, z, (e.cell as Dictionary).duplicate(true))
		placed += 1
	for t in stamp.get("tiles", []):
		var x := origin.x + int(t.x)
		var z := origin.y + int(t.z)
		if not RoomEditor.in_bounds(room, x, z) or not RoomEditor.object_at(room, x, z).is_empty():
			continue
		var c: Dictionary = t.duplicate(true)
		c["x"] = x
		c["z"] = z
		# Keep stacks sane: a block lands on top of whatever is already there.
		var y := RoomEditor.stack_top(room, x, z)
		if y + BlockFactory.height_of(str(c.get("type", "cube"))) > RoomEditor.MAX_HEIGHT:
			continue
		c["y"] = y
		room["tiles"].append(c)
		placed += 1
	for o in stamp.get("objects", []):
		var x := origin.x + int(o.pos[0])
		var z := origin.y + int(o.pos[2])
		var made := RoomEditor.add_object(room, x, z, str(o.get("type", "prop")), str(o.get("color", "")), str(o.get("texture", "")), int(o.get("rot", 0)))
		if not made.is_empty():
			made["interaction_text"] = str(o.get("interaction_text", ""))
			made["door_target"] = str(o.get("door_target", ""))
			made["scale"] = float(o.get("scale", 1.0))
			for k in ["item", "count", "respawn"]:   # pickups keep what they hold (but start untaken)
				if o.has(k):
					made[k] = o[k]
			placed += 1
	return placed


## A quarter turn clockwise (as seen from above).
static func rotate_stamp(stamp_in: Dictionary) -> Dictionary:
	var out: Dictionary = upgrade_stamp(stamp_in).duplicate(true)
	var w := int(out.get("w", 1))
	var d := int(out.get("d", 1))
	out["w"] = d
	out["d"] = w
	for e in out.get("cells", []):
		var x := int(e.x)
		var z := int(e.z)
		e["x"] = d - 1 - z
		e["z"] = x
		var r := posmod(int(e.cell.get("r", 0)) + 1, 4)
		if r == 0:
			e.cell.erase("r")
		else:
			e.cell["r"] = r
	for e in out.get("tiles", []):
		var x := int(e.x)
		var z := int(e.z)
		e["x"] = d - 1 - z
		e["z"] = x
		e["rot"] = posmod(int(e.get("rot", 0)) + 1, 4)
	for o in out.get("objects", []):
		var x := int(o.pos[0])
		var z := int(o.pos[2])
		o["pos"] = [d - 1 - z, o.pos[1], x]
		o["rot"] = posmod(int(o.get("rot", 0)) + 1, 4)
	return out


static func flip_stamp(stamp_in: Dictionary) -> Dictionary:
	var out: Dictionary = upgrade_stamp(stamp_in).duplicate(true)
	var w := int(out.get("w", 1))
	for e in out.get("cells", []):
		e["x"] = w - 1 - int(e.x)
		if bool(e.cell.get("fl", false)):
			e.cell.erase("fl")
		else:
			e.cell["fl"] = true
	for e in out.get("tiles", []):
		e["x"] = w - 1 - int(e.x)
		e["flip"] = not bool(e.get("flip", false))
	for o in out.get("objects", []):
		o["pos"] = [w - 1 - int(o.pos[0]), o.pos[1], o.pos[2]]
	return out


# --- Room check --------------------------------------------------------------------------------

## Problems a player would hit: [{problem, where, severity}].
static func room_check(room: Dictionary) -> Array:
	var issues: Array = []
	var w := int(room.size.w)
	var d := int(room.size.d)
	var blocked := {}
	for x in w:
		for z in d:
			if blocks_walk(room, x, z) or str(RoomEditor.object_at(room, x, z).get("type", "")) in ["sign", "prop"]:
				blocked[Vector2i(x, z)] = true
	var sp: Array = room.get("spawn", [0, 0])
	var spawn := Vector2i(int(sp[0]), int(sp[1]))
	if blocked.has(spawn) or not RoomEditor.object_at(room, spawn.x, spawn.y).is_empty():
		issues.append({"problem": "The start spot is blocked (someone arriving would be nudged elsewhere).", "where": spawn, "severity": "warn"})
	# Reachability from the spawn (same rules as the walking grid, 8 directions).
	var reach := {}
	var stack: Array = [spawn]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if reach.has(p) or p.x < 0 or p.y < 0 or p.x >= w or p.y >= d or (blocked.has(p) and p != spawn):
			continue
		reach[p] = true
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx != 0 or dz != 0:
					stack.append(p + Vector2i(dx, dz))
	var ids := {}
	for o in room.get("objects", []):
		var cell := Vector2i(int(o.pos[0]), int(o.pos[2]))
		var id := str(o.get("id", ""))
		if ids.has(id):
			issues.append({"problem": "Two objects share the id '%s'." % id, "where": cell, "severity": "warn"})
		ids[id] = true
		if str(o.get("type", "")) == "door":
			var target := str(o.get("door_target", ""))
			if target == "":
				issues.append({"problem": "A door leads nowhere yet.", "where": cell, "severity": "note"})
			elif not SaveManager.room_exists(target):
				issues.append({"problem": "A door leads to a room that doesn't exist (%s)." % target, "where": cell, "severity": "warn"})
			if not reach.has(cell):
				issues.append({"problem": "A door can't be reached from the start spot.", "where": cell, "severity": "warn"})
		if str(o.get("texture", "")) != "" and SaveManager.load_texture(str(o.texture)) == null:
			issues.append({"problem": "An object's picture is missing (%s)." % str(o.texture).get_file(), "where": cell, "severity": "warn"})
	var missing := {}
	for l in TileLayers.all(room):
		for k in l.cells:
			var c: Dictionary = l.cells[k]
			if Tilesets.info(str(c.s), str(c.t)).is_empty() and not missing.has("%s/%s" % [c.s, c.t]):
				missing["%s/%s" % [c.s, c.t]] = true
				issues.append({"problem": "A tile on \"%s\" uses a picture this world doesn't have (%s/%s)." % [l.name, c.s, c.t], "where": TileLayers.parse_key(str(k)), "severity": "warn"})
	for t in room.get("tiles", []):
		if str(t.get("texture", "")) != "" and SaveManager.load_texture(str(t.texture)) == null:
			issues.append({"problem": "A block's picture is missing (%s)." % str(t.texture).get_file(), "where": Vector2i(int(t.get("x", 0)), int(t.get("z", 0))), "severity": "warn"})
	return issues
