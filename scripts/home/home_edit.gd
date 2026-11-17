extends RefCounted
## Your own changes to the house: from the Map my home sketch (rename, paint, floors, swap rooms, walls
## into doors or windows), from "Tell Polox about home" (things added or taken away, what a room used to
## be, notes), and later from arranging furniture in the Light World. They're kept in order in
## home.edits, and the house is always rebuilt as: your answers + what research found + your edits on
## top (rebuild). So your edits always win over research, "Map my home again" and "Look again" keep
## them, and any one of them can be undone exactly (undo removes it and rebuilds). A snapshot of
## my_home comes before every batch, too.
##
## Edit: {"type": "rename" | "wall" | "floor" | "edge" | "swap" | "add" | "remove" | "move" | "used_to_be" | "note",
##        "level": int, "room": "<room id>", "room_name": "...", ... the type's fields ...,
##        "date", "batch": "<id>", "source": "editor" | "words" | "photo" | "answer" | "room"}

const LayoutBuilder := preload("res://scripts/home/layout_builder.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const FloorPaths := preload("res://scripts/world/floor_paths.gd")

const EDGE_CYCLE := ["wall", "door", "window"]


static func floor_of(plan: Dictionary, level: int) -> Dictionary:
	for f in plan.get("floors", []):
		if int(f.level) == level:
			return f
	return {}


static func room_index(f: Dictionary, id: String, fallback_name: String = "") -> int:
	var rooms: Array = f.get("rooms", [])
	for i in rooms.size():
		if str(rooms[i].id) == id:
			return i
	if fallback_name != "":
		for i in rooms.size():
			if str(rooms[i].name) == fallback_name:
				return i
		# (a room the research has since named, "Office 1" -> "Study", still answers to its plain name)
		for i in rooms.size():
			if str(rooms[i].get("alias", "")) == fallback_name:
				return i
	return -1


static func edge_index(f: Dictionary, x: int, z: int, dir: String) -> int:
	var edges: Array = f.get("edges", [])
	for i in edges.size():
		if int(edges[i].x) == x and int(edges[i].z) == z and str(edges[i].dir) == dir:
			return i
	return -1


static func edge_state(e: Dictionary) -> String:
	return "door" if bool(e.get("door", false)) else ("window" if bool(e.get("window", false)) else "wall")


## The next state for a wall you tap: wall -> door -> window -> wall (inside walls skip the window).
static func next_edge_state(e: Dictionary) -> String:
	var cur := edge_state(e)
	var n: String = EDGE_CYCLE[(EDGE_CYCLE.find(cur) + 1) % EDGE_CYCLE.size()]
	if n == "window" and not bool(e.get("outer", false)):
		n = "wall"
	return n


## Applies one edit to the plan (in place). Returns true when something changed.
static func apply(plan: Dictionary, edit: Dictionary, answers: Dictionary = {}) -> bool:
	var f := floor_of(plan, int(edit.get("level", 0)))
	if f.is_empty():
		return false
	var i := room_index(f, str(edit.get("room", "")), str(edit.get("room_name", "")))
	match str(edit.get("type", "")):
		"rename":
			return _rename_room(f, i, edit)
		"wall":
			return _set_on_room(f, i, "wall", str(edit.get("color", "#efe6d8")))
		"floor":
			return _set_on_room(f, i, "floor", str(edit.get("floor", "wood")))
		"used_to_be":
			return _set_on_room(f, i, "used_to_be", str(edit.get("was", "")).left(80))
		"edge":
			return _change_edge(f, edit, answers)
		"swap":
			return _swap_rooms(f, i, edit, answers)
		"add":
			return _add_to_room(f, i, edit)
		"place":
			return _place_at(f, str(edit.get("model", "")), int(edit.get("x", -1)), int(edit.get("z", -1)), int(edit.get("rot", 0)), str(edit.get("color", "")))
		"remove_at":
			return _remove_piece_at(f, edit)
		"remove":
			return _remove_from_room(f, i, edit)
		"move":
			return _move_piece(f, edit)
		"note":
			return _add_note(plan, f, i, edit)
	return false


static func _rename_room(f: Dictionary, i: int, edit: Dictionary) -> bool:
	if i < 0 or str(edit.get("name", "")).strip_edges() == "":
		return false
	f.rooms[i]["name"] = str(edit.name).strip_edges().left(40)
	return true


## One thing about a room (its paint, its floor, what it used to be).
static func _set_on_room(f: Dictionary, i: int, key: String, value: String) -> bool:
	if i < 0:
		return false
	f.rooms[i][key] = value
	return true


## A wall you tapped becomes a wall, a door or a window.
static func _change_edge(f: Dictionary, edit: Dictionary, answers: Dictionary) -> bool:
	var ei := edge_index(f, int(edit.get("x", -1)), int(edit.get("z", -1)), str(edit.get("dir", "")))
	if ei < 0:
		return false
	var e: Dictionary = f.edges[ei]
	var to := str(edit.get("to", "wall"))
	if bool(e.get("outer", false)) and to == "door" and int(f.get("level", 0)) != 0:
		return false   # upstairs, a door in an outside wall would open onto thin air
	if not bool(e.get("outer", false)) and to == "window":
		to = "wall"   # inside walls get doors, not windows
	e["door"] = to == "door"
	e["window"] = to == "window"
	_refurnish(f, answers)
	return true


## Two rooms trade places: what each is (name, kind, paint, floor, notes), not its walls.
static func _swap_rooms(f: Dictionary, i: int, edit: Dictionary, answers: Dictionary) -> bool:
	var j := room_index(f, str(edit.get("other", "")), str(edit.get("other_name", "")))
	if i < 0 or j < 0 or i == j:
		return false
	for k in ["name", "kind", "mine", "floor", "wall", "used_to_be", "notes"]:
		var t: Variant = f.rooms[i].get(k)
		var u: Variant = f.rooms[j].get(k)
		if u == null:
			f.rooms[i].erase(k)
		else:
			f.rooms[i][k] = u
		if t == null:
			f.rooms[j].erase(k)
		else:
			f.rooms[j][k] = t
	_refurnish(f, answers)
	return true


## One or more of a piece into a room, where they fit.
static func _add_to_room(f: Dictionary, i: int, edit: Dictionary) -> bool:
	if i < 0 or not Furniture.exists(str(edit.get("model", ""))):
		return false
	# "The hallway has a blue runner" when it already has one: you're describing that one.
	if int(edit.get("count", 1)) <= 1 and str(edit.get("color", "")) != "":
		for p in f.get("furniture", []):
			if int(p.room) == i and str(p.model) == str(edit.model):
				p["color"] = str(edit.color)
				p["user"] = true
				return true
	var placed := 0
	for _n in clampi(int(edit.get("count", 1)), 1, 8):
		if _place(f, i, str(edit.model), str(edit.get("color", ""))):
			placed += 1
	return placed > 0


## The piece of that model at that exact spot goes.
static func _remove_piece_at(f: Dictionary, edit: Dictionary) -> bool:
	var list: Array = f.get("furniture", [])
	for k in list.size():
		if str(list[k].model) == str(edit.get("model", "")) and int(list[k].x) == int(edit.get("x", -1)) and int(list[k].z) == int(edit.get("z", -1)):
			list.remove_at(k)
			return true
	return false


## The first piece of that model in the room goes.
static func _remove_from_room(f: Dictionary, i: int, edit: Dictionary) -> bool:
	if i < 0:
		return false
	var list: Array = f.get("furniture", [])
	for k in list.size():
		if int(list[k].room) == i and str(list[k].model) == str(edit.get("model", "")):
			list.remove_at(k)
			return true
	return false


## A piece moved by hand in the Light World: by its model and old spot, to a new spot (not one that
## would shut part of the floor off: floor_paths.gd).
static func _move_piece(f: Dictionary, edit: Dictionary) -> bool:
	var list: Array = f.get("furniture", [])
	for p in list:
		if str(p.model) == str(edit.get("model", "")) and int(p.x) == int(edit.get("from_x", -1)) and int(p.z) == int(edit.get("from_z", -1)):
			var was := [int(p.x), int(p.z), int(p.rot)]
			var shut_before := FloorPaths.pockets(FloorPaths.plan_floor(f)).size()
			p["x"] = int(edit.get("x", p.x))
			p["z"] = int(edit.get("z", p.z))
			p["rot"] = int(edit.get("rot", p.rot))
			if Furniture.blocks(str(p.model)) and FloorPaths.pockets(FloorPaths.plan_floor(f)).size() > shut_before:
				p["x"] = was[0]
				p["z"] = was[1]
				p["rot"] = was[2]
				return false
			if edit.has("color"):
				p["color"] = str(edit.color)
			return true
	return false


## Something you told Polox about a room, or (with no room named) about the house as a whole ("the back
## door sticks").
static func _add_note(plan: Dictionary, f: Dictionary, i: int, edit: Dictionary) -> bool:
	if i < 0 and str(edit.get("room", "")) == "":
		var house_notes: Array = plan.get("notes", []) if plan.get("notes") is Array else []
		house_notes.append(str(edit.get("text", "")).left(200))
		plan["notes"] = house_notes
		return true
	if i < 0:
		return false
	var notes: Array = f.rooms[i].get("notes", []) if f.rooms[i].get("notes") is Array else []
	notes.append(str(edit.get("text", "")).left(200))
	f.rooms[i]["notes"] = notes
	return true


## The room's furniture again after its doors changed (pieces you added are put back after).
static func _refurnish(f: Dictionary, answers: Dictionary) -> void:
	var extra: Array = (f.get("furniture", []) as Array).filter(func(p): return bool(p.get("user", false)))
	LayoutBuilder.furnish(f, answers)
	for p in extra:
		if bool(p.get("placed", false)):
			_place_at(f, str(p.model), int(p.x), int(p.z), int(p.rot), str(p.get("color", "")))
			continue
		if bool(p.get("added", false)):
			_place(f, int(p.room), str(p.model), str(p.get("color", "")))
			continue
		for q in f.get("furniture", []):   # a piece you recoloured: the same one, recoloured again
			if int(q.room) == int(p.room) and str(q.model) == str(p.model):
				q["color"] = str(p.get("color", ""))
				q["user"] = true
				break


## Puts one more piece in a room where it fits (against a wall, out of the doorways).
static func _place(f: Dictionary, ri: int, model: String, color: String) -> bool:
	var r: Array = f.rooms[ri].rect
	var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	var taken := {}
	for p in f.get("furniture", []):
		for c in Furniture.cells({"model": str(p.model), "pos": [int(p.x), 0, int(p.z)], "rot": int(p.rot)}):
			taken[c] = true
	var keep := {}
	for e in f.get("edges", []):
		if bool(e.door):
			keep[Vector2i(int(e.x), int(e.z))] = true
			keep[Vector2i(int(e.x), int(e.z) - 1) if str(e.dir) == "h" else Vector2i(int(e.x) - 1, int(e.z))] = true
	var st: Array = f.get("stairs", [])
	if st.size() >= 2:
		for k in 3:
			taken[Vector2i(int(st[0]) + k, int(st[1]))] = true
	var owner: Array = f.get("owner_rows", [])
	var extra := "middle" if model in ["dining_table", "coffee_table"] else ("hall" if model == "runner" else "")
	var shut_before := FloorPaths.pockets(FloorPaths.plan_floor(f)).size()
	var keeps_open := func(fp: Rect2i) -> bool:
		return FloorPaths.pockets(FloorPaths.plan_floor(f), "", fp).size() <= shut_before
	var spot := LayoutBuilder._spot(Furniture, model, [0, 1, 2, 3], rect, taken, keep, owner, ri, extra, {}, keeps_open)
	if spot.is_empty():
		return false
	(f["furniture"] as Array).append({"room": ri, "model": model, "x": int(spot.x), "z": int(spot.z), "rot": int(spot.rot), "color": color, "user": true, "added": true})
	return true


## A piece you put at an exact spot (Edit my room): it must fit on free floor inside the house.
static func _place_at(f: Dictionary, model: String, x: int, z: int, rot: int, color: String) -> bool:
	if not Furniture.exists(model):
		return false
	var o := {"model": model, "pos": [x, 0, z], "rot": rot}
	var owner: Array = f.get("owner_rows", [])
	var taken := {}
	for p in f.get("furniture", []):
		for c in Furniture.cells({"model": str(p.model), "pos": [int(p.x), 0, int(p.z)], "rot": int(p.rot)}):
			taken[c] = true
	var st: Array = f.get("stairs", [])
	if st.size() >= 2:
		for k in 3:
			taken[Vector2i(int(st[0]) + k, int(st[1]))] = true
	var ri := -1
	for c in Furniture.cells(o):
		if c.x < 0 or c.y < 0 or c.x >= int(f.w) or c.y >= int(f.d) or taken.has(c):
			return false
		if owner.size() > c.y:
			ri = int(owner[c.y][c.x]) if ri < 0 else ri
	if Furniture.blocks(model) and FloorPaths.pockets(FloorPaths.plan_floor(f), "", Furniture.footprint(o)).size() > FloorPaths.pockets(FloorPaths.plan_floor(f)).size():
		return false   # (it would shut part of the floor off: floor_paths.gd)
	(f["furniture"] as Array).append({"room": maxi(ri, 0), "model": model, "x": x, "z": z, "rot": posmod(rot, 4), "color": color, "user": true, "placed": true})
	return true


## A line for the timeline.
static func describe(edit: Dictionary) -> String:
	var rn := str(edit.get("room_name", "a room"))
	match str(edit.get("type", "")):
		"rename":
			return "Renamed %s to %s." % [rn, str(edit.get("name", ""))]
		"wall":
			return "Painted the walls of %s." % rn
		"floor":
			return "New floor in %s (%s)." % [rn, str(edit.get("floor", ""))]
		"edge":
			return "Made a %s in the walls." % str(edit.get("to", "wall"))
		"swap":
			return "Swapped %s and %s." % [rn, str(edit.get("other_name", ""))]
		"add":
			return "Added %s to %s." % [str(Furniture.name_of(str(edit.get("model", "")))).to_lower(), rn]
		"remove":
			return "Took the %s out of %s." % [str(Furniture.name_of(str(edit.get("model", "")))).to_lower(), rn]
		"move":
			return "Moved the %s." % str(Furniture.name_of(str(edit.get("model", "")))).to_lower()
		"place":
			return "Put a %s in." % str(Furniture.name_of(str(edit.get("model", "")))).to_lower()
		"remove_at":
			return "Took the %s away." % str(Furniture.name_of(str(edit.get("model", "")))).to_lower()
		"used_to_be":
			return "%s used to be %s." % [rn, str(edit.get("was", ""))]
		"note":
			return "%s: %s" % [rn, str(edit.get("text", ""))]
	return "Changed the house."


## The house, freshly: your answers + research + every kept edit, in order.
static func rebuild(home: Dictionary) -> Dictionary:
	var answers: Dictionary = home.get("answers", {}) if home.get("answers") is Dictionary else {}
	var plan: Dictionary = (home.base_plan as Dictionary).duplicate(true) if answers.is_empty() and home.get("base_plan") is Dictionary else LayoutBuilder.build(answers, HomeModel.facts_by_key(home))
	for e in home.get("edits", []):
		if e is Dictionary:
			apply(plan, e, answers)
	# [LIGHT_WORLD_MAP] The outside of the house in the colour a helper found (home_look.gd), when one did.
	var look: Dictionary = preload("res://scripts/home/home_look.gd").of(home)
	if look.has("wall"):
		plan["exterior"] = str(look.wall)
	else:
		plan.erase("exterior")
	return plan


## Every kept edit on top of a (new) plan.
static func reapply_all(plan: Dictionary, edits: Array, answers: Dictionary) -> void:
	for e in edits:
		if not e is Dictionary:
			continue
		if e is Dictionary:
			apply(plan, e, answers)


## Makes changes for real, as one batch: snapshot, keep them, rebuild the house and its Light World
## places, put them on the timeline. Returns {"snapshot", "batch", "applied": n} ({} if nothing changed).
## `extra`: more my_home files committed in the same transaction (a helper request's closing record).
static func commit(edits: Array, source: String = "editor", extra: Dictionary = {}) -> Dictionary:
	var home := HomeStore.load_home()
	if home.is_empty():
		return {}
	var plan: Dictionary = home.get("plan", {})
	var answers: Dictionary = home.get("answers", {}) if home.get("answers") is Dictionary else {}
	var probe := plan.duplicate(true)
	var good: Array = []
	var batch := "b%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec() % 100000]
	var date := Time.get_datetime_string_from_system(false, false)
	for e in edits:
		if not e is Dictionary:
			continue
		var edit: Dictionary = (e as Dictionary).duplicate(true)
		var f := floor_of(probe, int(edit.get("level", 0)))
		var i := room_index(f, str(edit.get("room", "")), str(edit.get("room_name", "")))
		if i >= 0:
			edit["room_name"] = str(f.rooms[i].name)
		if str(edit.get("type", "")) == "swap":
			var j := room_index(f, str(edit.get("other", "")))
			if j >= 0:
				edit["other_name"] = str(f.rooms[j].name)
		if apply(probe, edit, answers):
			edit["date"] = date
			edit["batch"] = batch
			edit["source"] = str(edit.get("source", source))
			good.append(edit)
	if good.is_empty():
		if not extra.is_empty() and HomeStore.apply_batch(extra):
			return {"snapshot": "", "batch": "", "applied": 0}
		return {}
	var snap := HomeStore.snapshot("before_" + source)
	if snap == "":
		return {}
	var kept: Array = home.get("edits", []) if home.get("edits") is Array else []
	kept.append_array(good)
	home["edits"] = kept
	var tl: Array = home.get("timeline", []) if home.get("timeline") is Array else []
	for e in good:
		tl.append({"year": int(Time.get_date_dict_from_system().year), "date": date.left(10), "kind": "used_to_be" if str(e.type) == "used_to_be" else ("note" if str(e.type) == "note" else "edit"),
			"text": describe(e), "source": str(e.source), "batch": batch})
	home["timeline"] = tl
	if not _save(home, extra):
		return {}
	return {"snapshot": snap, "batch": batch, "applied": good.size()}


## Undoes a batch (or one edit by index): it's taken out and the house rebuilt, exactly as if it had
## never happened. The timeline keeps a line saying so.
static func undo(batch: String) -> bool:
	var home := HomeStore.load_home()
	var kept: Array = home.get("edits", []) if home.get("edits") is Array else []
	var left := kept.filter(func(e): return str(e.get("batch", "")) != batch)
	if left.size() == kept.size():
		return false
	if HomeStore.snapshot("before_undo") == "":
		return false
	home["edits"] = left
	var tl: Array = home.get("timeline", []) if home.get("timeline") is Array else []
	home["timeline"] = tl.filter(func(t): return str(t.get("batch", "")) != batch)
	return _save(home)


## The newest batch (for "Undo" right after Keep).
static func last_batch() -> String:
	var kept: Array = HomeStore.load_home().get("edits", [])
	return str(kept[-1].get("batch", "")) if not kept.is_empty() else ""


static func _save(home: Dictionary, extra: Dictionary = {}) -> bool:
	home["plan"] = rebuild(home)
	var batch := HomePlaces.batch_files(HomePlaces.build(home.plan))
	if str(batch.entry) == "":
		return false
	var writes := HomeStore.home_writes(home)
	writes.merge(batch.writes, true)
	writes.merge(extra, true)
	return HomeStore.apply_batch(writes, batch.removals)
