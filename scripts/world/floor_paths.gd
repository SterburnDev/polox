extends RefCounted
## Where you can walk on a floor of your home, and making sure no furniture ever shuts part of it off.
## A floor is a grid of one-metre cells: cells under solid furniture (beds, desks, chairs, the stairs) are
## out, and thin walls stand on the cell lines except where they have a door. The house builder
## (layout_builder.gd) checks each piece with this before it places it, and every floor is checked again
## when it loads (light_home.gd), so a home built before the rule gets the blocking piece moved instead of
## you boxed into a corner of your room (1.27.10: a desk, its chair and a lamp did exactly that).

const Furniture := preload("res://scripts/world/furniture.gd")

const STEPS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## The cells you can walk to from `start` (four ways, not through `solid` cells or walls: "v|x|z" is the
## wall on cell x's west side, "h|x|z" the one on cell z's north side).
static func walk(start: Vector2i, solid: Dictionary, walls: Dictionary, w: int, d: int) -> Dictionary:
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for step in STEPS:
			var n: Vector2i = c + step
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= d or seen.has(n) or solid.has(n) or walls.has(wall_between(c, n)):
				continue
			seen[n] = true
			todo.append(n)
	return seen


## The key of the wall between two neighbouring cells.
static func wall_between(a: Vector2i, b: Vector2i) -> String:
	if a.y == b.y:
		return "v|%d|%d" % [maxi(a.x, b.x), a.y]
	return "h|%d|%d" % [a.x, maxi(a.y, b.y)]


## A floor's walls that stop you (doors don't): {"h|x|z": true, ...}.
static func walls_of(room: Dictionary) -> Dictionary:
	var out := {}
	for e in room.get("edge_walls", []) if room.get("edge_walls") is Array else []:
		if e is Dictionary and not bool(e.get("door", false)):
			out["%s|%d|%d" % [str(e.get("dir", "h")), int(e.get("x", 0)), int(e.get("z", 0))]] = true
	return out


## Cells under solid furniture (the stairs too), leaving out the piece with id `skip`, plus `extra` (a
## piece you're about to put down).
static func solids_of(room: Dictionary, skip: String = "", extra: Rect2i = Rect2i()) -> Dictionary:
	var out := {}
	for o in room.get("objects", []):
		if o is Dictionary and str(o.get("type", "")) == "furniture" and str(o.get("id", "")) != skip and Furniture.blocks(str(o.get("model", ""))):
			_mark(out, Furniture.footprint(o))
	_mark(out, extra)
	return out


static func _mark(cells: Dictionary, r: Rect2i) -> void:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			cells[Vector2i(x, z)] = true


## A floor of the house plan (layout_builder.gd) as a place, for these checks.
static func plan_floor(f: Dictionary) -> Dictionary:
	var objects: Array = []
	for p in f.get("furniture", []):
		objects.append({"type": "furniture", "id": "piece_%d" % objects.size(), "model": str(p.model), "pos": [int(p.x), 0, int(p.z)], "rot": int(p.rot)})
	var st: Array = f.get("stairs", [])
	if st.size() >= 2:
		objects.append({"type": "furniture", "id": "stairs", "model": "stairs", "pos": [int(st[0]), 0, int(st[1])], "rot": 1})
	return {"size": {"w": int(f.get("w", 0)), "d": int(f.get("d", 0))}, "edge_walls": f.get("edges", []), "objects": objects, "rooms": f.get("rooms", [])}


## Where walking starts: the cells on both sides of each door, and the cells you step onto off the stairs
## (not through a wall).
static func entrances(room: Dictionary) -> Array:
	var out: Array = []
	for e in room.get("edge_walls", []) if room.get("edge_walls") is Array else []:
		if e is Dictionary and bool(e.get("door", false)):
			var c := Vector2i(int(e.get("x", 0)), int(e.get("z", 0)))
			out.append(c)
			out.append(c - (Vector2i(0, 1) if str(e.get("dir", "h")) == "h" else Vector2i(1, 0)))
	var walls := walls_of(room)
	for o in room.get("objects", []):
		if o is Dictionary and str(o.get("model", "")) == "stairs":
			var fp: Rect2i = Furniture.footprint(o)
			for z in range(fp.position.y, fp.end.y):
				for x in range(fp.position.x, fp.end.x):
					for step in STEPS:
						var n: Vector2i = Vector2i(x, z) + step
						if not fp.has_point(n) and not walls.has(wall_between(Vector2i(x, z), n)):
							out.append(n)
	return out


## Every cell inside the floor's rooms.
static func room_cells(room: Dictionary) -> Dictionary:
	var out := {}
	for r in room.get("rooms", []) if room.get("rooms") is Array else []:
		var rr: Array = r.get("rect", [0, 0, 0, 0]) if r is Dictionary else [0, 0, 0, 0]
		for z in range(int(rr[1]), int(rr[1]) + int(rr[3])):
			for x in range(int(rr[0]), int(rr[0]) + int(rr[2])):
				out[Vector2i(x, z)] = true
	return out


## The cells you can walk to from the doors and stairs ({} on a floor without rooms or ways in).
static func reachable(room: Dictionary, skip: String = "", extra: Rect2i = Rect2i()) -> Dictionary:
	var size: Dictionary = room.get("size", {})
	var w := int(size.get("w", 0))
	var d := int(size.get("d", 0))
	var solid := solids_of(room, skip, extra)
	var walls := walls_of(room)
	var reach := {}
	for c in entrances(room):
		if c.x >= 0 and c.y >= 0 and c.x < w and c.y < d and not solid.has(c) and not reach.has(c):
			reach.merge(walk(c, solid, walls, w, d))
	return reach


## Free cells inside the rooms that you can't walk to: {} when nothing is shut off. `skip` leaves a piece
## out; `extra` adds a solid piece that isn't there yet.
static func pockets(room: Dictionary, skip: String = "", extra: Rect2i = Rect2i()) -> Dictionary:
	var reach := reachable(room, skip, extra)
	if reach.is_empty():
		return {}
	var solid := solids_of(room, skip, extra)
	var out := {}
	for c in room_cells(room):
		if not solid.has(c) and not reach.has(c):
			out[c] = true
	return out


## Moves furniture until nothing is shut off: each time, the smallest piece whose moving opens a shut-off
## corner goes to the nearest spot in its room that keeps everything open (or, if it fits nowhere, out of
## the house). Returns how many pieces moved. Changes `room` in memory only.
static func open_pockets(room: Dictionary) -> int:
	var moved := 0
	for _try in 8:
		var shut := pockets(room)
		if shut.is_empty():
			break
		var piece := _blocker(room, shut)
		if piece.is_empty():
			break
		_move_away(room, piece)
		moved += 1
	return moved


## The spawn on a cell you can walk away from: kept if it is one, else the nearest such cell.
static func safe_spawn(room: Dictionary) -> void:
	var s: Array = room.get("spawn", [])
	if s.size() < 2:
		return
	var reach := reachable(room)
	var at := Vector2i(int(s[0]), int(s[1]))
	if reach.is_empty() or reach.has(at):
		return
	var best := at
	var best_d := INF
	for c in reach:
		var dist := Vector2(c - at).length_squared()
		if dist < best_d:
			best_d = dist
			best = c
	room["spawn"] = [best.x, best.y]


## The smallest solid piece touching the shut-off cells whose moving would open some of them.
static func _blocker(room: Dictionary, shut: Dictionary) -> Dictionary:
	var near: Array = []
	for o in room.get("objects", []):
		if not (o is Dictionary) or str(o.get("type", "")) != "furniture" or str(o.get("model", "")) == "stairs" or not Furniture.blocks(str(o.get("model", ""))):
			continue
		var fp: Rect2i = Furniture.footprint(o)
		if shut.keys().any(func(c): return fp.grow(1).has_point(c)):
			near.append(o)
	near.sort_custom(func(a, b): return Furniture.footprint(a).get_area() < Furniture.footprint(b).get_area())
	for o in near:
		if pockets(room, str(o.get("id", ""))).size() < shut.size():
			return o
	return {}


## Puts `piece` on the nearest free spot in its own room (any turn) that shuts nothing off; out of the
## house if there's none.
static func _move_away(room: Dictionary, piece: Dictionary) -> void:
	var id := str(piece.get("id", ""))
	var target := pockets(room, id).size()
	var rect := _room_rect(room, str(piece.get("room", "")))
	var keep := {}
	for c in entrances(room):
		keep[c] = true
	var from := Vector2i(int(piece.pos[0]), int(piece.pos[2]))
	var old_pos: Array = (piece.pos as Array).duplicate()
	var old_rot := int(piece.get("rot", 0))
	var spots: Array = []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			spots.append(Vector2i(x, z))
	spots.sort_custom(func(a, b): return Vector2(a - from).length_squared() < Vector2(b - from).length_squared())
	for c in spots:
		for turn in 4:
			piece["pos"] = [c.x, 0, c.y]
			piece["rot"] = (old_rot + turn) % 4
			var fp: Rect2i = Furniture.footprint(piece)
			if rect.encloses(fp) and _free(room, fp, piece, keep) and pockets(room).size() <= target:
				return
	piece["pos"] = old_pos
	piece["rot"] = old_rot
	(room.objects as Array).erase(piece)
	push_warning("Furniture %s shut part of %s off and fit nowhere else in its room: left out." % [id, str(room.get("id", ""))])


## Whether `fp` is clear of every other object and of the doorways.
static func _free(room: Dictionary, fp: Rect2i, piece: Dictionary, keep: Dictionary) -> bool:
	for z in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			if keep.has(Vector2i(x, z)):
				return false
			for o in room.get("objects", []):
				if o is Dictionary and not is_same(o, piece) and _covers(o, Vector2i(x, z)):
					return false
	return true


static func _covers(o: Dictionary, c: Vector2i) -> bool:
	if str(o.get("type", "")) == "furniture":
		return Furniture.footprint(o).has_point(c)
	var p: Array = o.get("pos", [0, 0, 0])
	return int(p[0]) == c.x and int(p[2]) == c.y


## The rectangle of the room with this id (the whole floor if it isn't found).
static func _room_rect(room: Dictionary, id: String) -> Rect2i:
	for r in room.get("rooms", []) if room.get("rooms") is Array else []:
		if r is Dictionary and str(r.get("id", "")) == id:
			var rr: Array = r.rect
			return Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3]))
	var size: Dictionary = room.get("size", {})
	return Rect2i(0, 0, int(size.get("w", 0)), int(size.get("d", 0)))
