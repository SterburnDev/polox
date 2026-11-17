extends RefCounted
## Builds the Light World's places from a floor plan (layout_builder.gd): one place per floor, the
## rooms' floors in their own colours, thin walls on the cell lines with doors and windows in them,
## the furniture, stairs between floors, a lawn around the ground floor (your street joins it in Phase
## 32), and the Dream Gate in your room. Places your edits touched keep them (home_model.gd).

const Realms := preload("res://scripts/world/realms.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const LayoutBuilder := preload("res://scripts/home/layout_builder.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")

## Lawn around the house on the ground floor (cells).
const YARD := 3
## The outside of the house (until the records or you say otherwise).
const EXTERIOR := "#e6dccb"


static func place_id(level: int) -> String:
	return "lw_floor_%s" % (("b%d" % -level) if level < 0 else str(level))


## {place id: place} for every floor. `plan` is layout_builder's result.
static func build(plan: Dictionary) -> Dictionary:
	var out := {}
	var floors: Array = plan.get("floors", [])
	var levels: Array = floors.map(func(f): return int(f.level))
	# What a helper found the house's outside to be (home_edit.gd rebuild puts it in the plan), else the default.
	var exterior := str(plan.get("exterior", "")) if str(plan.get("exterior", "")) != "" else EXTERIOR
	for f in floors:
		var level := int(f.level)
		var margin := YARD if level == 0 else 0
		var w := int(f.w) + margin * 2
		var d := int(f.d) + margin * 2
		var id := place_id(level)
		var p := LightHome.base_place(id, str(f.name), w, d, "indoor")
		p["walls"] = {"north": false, "east": false, "south": false, "west": false}   # the house's own walls are edge walls
		p["floor"] = {"color": LightHome.GRASS if margin > 0 else "#8a8478", "texture": ""}
		p["house"] = {"x": margin, "z": margin, "w": int(f.w), "d": int(f.d), "level": level}
		if level != 0:
			p["background"] = {"sky": "auto", "ground": true, "ground_color": LightHome.GRASS, "layers": LightHome.SCENERY.layers.duplicate(true), "below": 2.8 * level}
		var areas: Array = []
		for r in f.rooms:
			var rr: Array = r.rect
			areas.append({"rect": [int(rr[0]) + margin, int(rr[1]) + margin, int(rr[2]), int(rr[3])], "color": LayoutBuilder.floor_color(str(r.get("floor", "wood"))),
				"material": str(r.get("floor", "wood")), "room": str(r.id), "name": str(r.name)})
		p["floor_areas"] = areas
		var walls: Array = []
		for e in f.edges:
			var room_a := int(e.get("a", -1))
			var room_b := int(e.get("b", -1))
			var wall_room: int = room_a if room_a >= 0 else room_b
			# Each side of a wall wears its own room's paint (outside: the house's own colour).
			var ca := str(f.rooms[room_a].get("wall", LightHome.WALL_CREAM)) if room_a >= 0 else exterior
			var cb := str(f.rooms[room_b].get("wall", LightHome.WALL_CREAM)) if room_b >= 0 else exterior
			walls.append({"x": int(e.x) + margin, "z": int(e.z) + margin, "dir": str(e.dir), "outer": bool(e.outer), "door": bool(e.door),
				"window": bool(e.window), "front": bool(e.front), "color_a": ca, "color_b": cb, "inside": "a" if room_a >= 0 else "b",
				"color": str(f.rooms[wall_room].get("wall", LightHome.WALL_CREAM)) if wall_room >= 0 else LightHome.WALL_CREAM})
		p["edge_walls"] = walls
		p["rooms"] = (f.rooms as Array).map(func(r): return {"id": str(r.id), "name": str(r.name), "kind": str(r.kind), "mine": bool(r.get("mine", false)),
			"rect": [int(r.rect[0]) + margin, int(r.rect[1]) + margin, int(r.rect[2]), int(r.rect[3])]})
		p["objects"] = []
		for piece in f.furniture:
			var o := LightHome.add(p, str(piece.model), int(piece.x) + margin, int(piece.z) + margin, int(piece.rot), str(piece.get("color", "")))
			o["room"] = str(f.rooms[int(piece.room)].id)
		# Stairs: up from the ground floor, down from the floors above (and from the basement up).
		# One flight per floor, in the same spot on every floor: it leads up, down, or (between two
		# floors) asks which way.
		var st: Array = f.get("stairs", [])
		if st.size() >= 2 and (levels.has(level + 1) or levels.has(level - 1)):
			var s := LightHome.add(p, "stairs", int(st[0]) + margin, int(st[1]) + margin, 1)
			s["door_target"] = place_id(level + 1) if levels.has(level + 1) else ""
			s["down_target"] = place_id(level - 1) if levels.has(level - 1) else ""
			s["label"] = "Stairs" if levels.has(level + 1) and levels.has(level - 1) else ("Stairs up" if levels.has(level + 1) else "Stairs down")
		# The spawn: your room if it's on this floor, else the stairs, else the front door.
		p["spawn"] = _spawn(p, f, margin)
		LightHome.restore_street_exit(p)
		out[id] = p
	# The Dream Gate stands in your room.
	var mine_level := int(plan.get("mine_level", 0))
	var host: Dictionary = out.get(place_id(mine_level), out.values()[0] if not out.is_empty() else {})
	if not host.is_empty():
		var mr := mine_rect(host)
		var near := mr.get_center() if mr.size.x > 0 else Vector2i(int(host.spawn[0]), int(host.spawn[1]))
		var g := Realms.add_gate(host, near, Realms.DARK, "")
		if not g.is_empty() and mr.size.x > 0 and not mr.has_point(Vector2i(int(g.pos[0]), int(g.pos[2]))):
			(host.objects as Array).erase(g)
			g = _gate_in(host, mr)
		host["entry"] = true
	return out


static func mine_rect(p: Dictionary) -> Rect2i:
	for r in p.get("rooms", []):
		if bool(r.get("mine", false)):
			var rr: Array = r.rect
			return Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3]))
	return Rect2i()


## A gate on any free cell of your room (when the nearest free cell was outside it).
static func _gate_in(p: Dictionary, mr: Rect2i) -> Dictionary:
	for z in range(mr.position.y, mr.end.y):
		for x in range(mr.position.x, mr.end.x):
			if RoomEditor.object_at(p, x, z).is_empty():
				var o := RoomEditor.add_object(p, x, z, "dark_fountain")
				if not o.is_empty():
					o.merge({"gate": true, "leads": Realms.DARK, "target": "", "state": "open", "label": "Dream Gate"}, true)
					return o
	return {}


static func _spawn(p: Dictionary, f: Dictionary, margin: int) -> Array:
	var mr := mine_rect(p)
	if mr.size.x > 0:
		var c := mr.get_center()
		return [c.x, c.y]
	var st: Array = f.get("stairs", [])
	if st.size() >= 2:
		return [int(st[0]) + margin - 1 if int(st[0]) > 0 else int(st[0]) + margin + 3, int(st[1]) + margin]
	return [int(f.w) / 2 + margin, int(f.d) + margin + 1]


## Writes the places (replacing the old floors, keeping anything else in the Light World, like your
## street) and returns the entry place's id (the floor with your room).
static func save_all(places: Dictionary) -> String:
	var batch := batch_files(places)
	if str(batch.entry) == "" or not load("res://scripts/home/home_store.gd").apply_batch(batch.writes, batch.removals):
		return ""
	return str(batch.entry)


## The mapper/editor can commit these alongside the model and map cache.
static func batch_files(places: Dictionary) -> Dictionary:
	var writes := {}
	var removals := PackedStringArray()
	for id in SaveManager.list_light_rooms():
		if str(id).begins_with("lw_floor_") and not places.has(id):
			removals.append("places/" + id + ".json")
	if SaveManager.room_exists(Realms.ENTRY) and not places.has(Realms.ENTRY):
		removals.append("places/" + Realms.ENTRY + ".json")
	var entry := ""
	for id in places:
		writes["places/" + str(id) + ".json"] = places[id]
		if bool(places[id].get("entry", false)):
			entry = str(id)
	return {"writes": writes, "removals": removals, "entry": entry}
