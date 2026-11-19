extends RefCounted
## Turns what Polox knows about your home (survey answers, and research facts when a helper found any)
## into a floor plan: floors, rooms as rectangles of one-metre cells, doors and windows on the walls
## between them, stairs, and the main furniture. Everything is deterministic, so the same answers make
## the same house.
##
## A floor: {"level": 0, "name": "Ground floor", "w": 12, "d": 9,
##           "rooms": [{"id", "name", "kind", "mine": bool, "rect": [x, z, w, d], "floor": "wood", "wall": "#hex"}],
##           "edges": [{"x", "z", "dir": "h" | "v", "outer": bool, "door": bool, "window": bool, "front": bool}],
##           "furniture": [{"room", "model", "x", "z", "rot", "color"}], "stairs": [x, z] | []}
## Edges are the walls along the cell grid: "h" at (x, z) runs from (x, z) to (x + 1, z) (between rows
## z - 1 and z); "v" at (x, z) runs from (x, z) to (x, z + 1) (between columns x - 1 and x).
## South (+z) is the street side: the front door is on the south wall.

const FloorPaths := preload("res://scripts/world/floor_paths.gd")

const ROOM_KINDS := {
	"living": {"name": "Living room", "area": 18.0, "band": "front", "floor": "wood", "wall": "#e8dcc8"},
	"kitchen": {"name": "Kitchen", "area": 11.0, "band": "back", "floor": "tile", "wall": "#f2ecda"},
	"dining": {"name": "Dining room", "area": 10.0, "band": "back", "floor": "wood", "wall": "#eadfcc"},
	"bedroom": {"name": "Bedroom", "area": 11.0, "band": "back", "floor": "carpet", "wall": "#dfe4ea"},
	"bathroom": {"name": "Bathroom", "area": 5.0, "band": "back", "floor": "tile", "wall": "#e2eef0"},
	"office": {"name": "Office", "area": 8.0, "band": "front", "floor": "wood", "wall": "#e6e0d2"},
	"laundry": {"name": "Laundry", "area": 4.0, "band": "back", "floor": "tile", "wall": "#eceae4"},
	"garage": {"name": "Garage", "area": 20.0, "band": "front", "floor": "concrete", "wall": "#d8d4cc"},
	"hall": {"name": "Hallway", "area": 0.0, "band": "hall", "floor": "wood", "wall": "#ece4d4"},
	"family": {"name": "Family room", "area": 16.0, "band": "back", "floor": "carpet", "wall": "#e4dccc"},
	"storage": {"name": "Storage", "area": 6.0, "band": "back", "floor": "concrete", "wall": "#d8d4cc"},
}
const FLOOR_COLORS := {"wood": "#c9a27a", "carpet": "#b9ab9b", "tile": "#d9d5cd", "vinyl": "#cbbfa8", "concrete": "#aaa69e", "stone": "#b8b0a4"}
const FLOOR_NAMES := {-1: "Basement", 0: "Ground floor", 1: "Upstairs", 2: "Top floor"}
const MIN_W := 2
const MAX_SIDE := 26


static func floor_color(kind: String) -> String:
	return str(FLOOR_COLORS.get(kind, FLOOR_COLORS.wood))


static func floor_name(level: int, floors: int) -> String:
	if level == 1 and floors > 2:
		return "First floor"
	return str(FLOOR_NAMES.get(level, "Floor %d" % level))


## The whole house. `answers`: the survey's (see survey_data.gd). `facts`: research facts by key
## (home_model.facts_by_key): "floors", "sqft", "footprint_w", "footprint_d", "bedrooms", "bathrooms",
## "rooms" (list of {"kind", "floor"}). Your answers win where they say something.
static func build(answers: Dictionary, facts: Dictionary = {}) -> Dictionary:
	var floors := _floors_count(answers, facts)
	var basement := bool(answers.get("basement", false)) or bool(facts.get("basement", false))
	var plan := _rooms_by_floor(answers, facts, floors, basement)
	var size := _footprint(answers, facts, plan, floors)
	var w: int = size.x
	var d: int = size.y
	var levels: Array = plan.keys()
	levels.sort()
	var stairs := floors > 1 or basement
	var stairs_x := w - 3
	var out_floors: Array = []
	var mine_floor := int((answers.get("my_room", {}) as Dictionary).get("floor", -99)) if answers.get("my_room") is Dictionary else -99
	# The ground floor first: its hallway row is every floor's, so the stairs line up.
	levels.sort_custom(func(a, b): return absi(int(a)) < absi(int(b)) or (absi(int(a)) == absi(int(b)) and int(a) > int(b)))
	var hall_z := -1
	for level in levels:
		var opts := {"level": level, "stairs": stairs, "stairs_x": stairs_x, "front_door": level == 0,
			"entry": str(answers.get("entry_room", "hall")), "where": str((answers.get("my_room", {}) as Dictionary).get("where", "")) if answers.get("my_room") is Dictionary else ""}
		if hall_z >= 0:
			opts["hall_z"] = hall_z
		var f := layout_floor(plan[level], w, d, opts)
		if hall_z < 0 and int(f.get("hall_z", -1)) >= 0:
			hall_z = int(f.hall_z)
		f["level"] = level
		f["name"] = floor_name(level, floors)
		_style(f, answers)
		furnish(f, answers)
		out_floors.append(f)
	out_floors.sort_custom(func(a, b): return int(a.level) < int(b.level))
	var mine_level := 0
	for f in out_floors:
		for r in f.rooms:
			if bool(r.get("mine", false)):
				mine_level = int(f.level)
	if mine_floor != -99 and plan.has(mine_floor):
		mine_level = mine_floor
	return {"floors": out_floors, "w": w, "d": d, "mine_level": mine_level, "made_from": "answers" if facts.is_empty() else "answers+research"}


static func _floors_count(answers: Dictionary, facts: Dictionary) -> int:
	var n := int(answers.get("floors", 0))
	if n <= 0:
		n = int(facts.get("floors", 0))
	if n <= 0:
		n = 1 if str(answers.get("home_type", "house")) == "apartment" else 2
	return clampi(n, 1, 3)


static func _count(answers: Dictionary, facts: Dictionary, kind: String, fallback: int) -> int:
	var rooms: Variant = answers.get("rooms")
	if rooms is Dictionary and (rooms as Dictionary).has(kind):
		return clampi(int(rooms[kind]), 0, 8)
	var fk := {"bedroom": "bedrooms", "bathroom": "bathrooms"}
	if fk.has(kind) and int(facts.get(fk[kind], 0)) > 0:
		return clampi(int(facts[fk[kind]]), 0, 8)
	return fallback


## Which rooms go on which floor: living spaces downstairs, bedrooms and most bathrooms upstairs (in a
## one-floor home, everything together), laundry and storage in a basement if there is one.
static func _rooms_by_floor(answers: Dictionary, facts: Dictionary, floors: int, basement: bool) -> Dictionary:
	var plan := {}
	for l in floors:
		plan[l] = []
	if basement:
		plan[-1] = []
	var beds := _count(answers, facts, "bedroom", 2)
	var baths := _count(answers, facts, "bathroom", 1)
	var up := 1 if floors > 1 else 0
	var mine: Dictionary = answers.get("my_room", {}) if answers.get("my_room") is Dictionary else {}
	var mine_level := clampi(int(mine.get("floor", up)), -1 if basement else 0, floors - 1)
	if mine_level == -1 and not basement:
		mine_level = up
	# Rooms the research placed on a floor come first.
	var placed := {}
	var research_rooms: Variant = facts.get("rooms")
	if research_rooms is Array:
		for rr in research_rooms:
			if rr is Dictionary and ROOM_KINDS.has(str(rr.get("kind", ""))):
				var lv := clampi(int(rr.get("floor", 0)), -1 if basement else 0, floors - 1)
				placed[str(rr.kind)] = int(placed.get(str(rr.kind), 0)) + 1
				var found := _room(str(rr.kind), float(rr.get("area", 0.0)))
				found["from"] = "records"
				# The room's own paint and floor, when a listing showed them (_style lets your answers win).
				if str(rr.get("wall", "")) != "":
					found["wall"] = str(rr.wall)
				if str(rr.get("floor_material", "")) != "":
					found["floor"] = str(rr.floor_material)
				# ...and its own name ("Playroom", "Study"), given to it once the plain names are settled below.
				# (A hall the research found is not one more room: layout_floor gives its paint, floor and
				#  name to the floor's own hallway.)
				if str(rr.get("name", "")) != "":
					found["own_name"] = str(rr.name)
				(plan[lv] as Array).append(found)
	var want := {"living": _count(answers, facts, "living", 1), "kitchen": _count(answers, facts, "kitchen", 1),
		"dining": _count(answers, facts, "dining", 1), "office": _count(answers, facts, "office", 0),
		"laundry": _count(answers, facts, "laundry", 1), "garage": _count(answers, facts, "garage", 0),
		"family": _count(answers, facts, "family", 0)}
	for k in want:
		for i in maxi(0, int(want[k]) - int(placed.get(k, 0))):
			var lv := 0
			if k == "laundry" and basement:
				lv = -1
			var r0 := _room(k)
			r0["from"] = _from(answers, facts, k)
			(plan[lv] as Array).append(r0)
	var my_done := false
	for i in maxi(0, beds - int(placed.get("bedroom", 0))):
		var r := _room("bedroom")
		r["from"] = _from(answers, facts, "bedroom")
		var lv := up
		if not my_done:
			r["mine"] = true
			r["name"] = "My room"
			r["from"] = "you"   # (you told the Survey about your room)
			lv = mine_level
			my_done = true
		(plan[lv] as Array).append(r)
	if not my_done:
		# No bedrooms counted, or the research placed them all: one of them is yours. On the floor you
		# said your room is on, when you said (your answers win); else the first one found.
		var search: Array = plan.keys()
		if mine.has("floor"):
			search = [mine_level] + plan.keys().filter(func(level): return int(level) != mine_level)
		for lv in search:
			for r in plan[lv]:
				if str(r.kind) == "bedroom" and not my_done:
					r["mine"] = true
					r["name"] = "My room"
					my_done = true
		if not my_done:
			var r2 := _room("bedroom")
			r2["mine"] = true
			r2["name"] = "My room"
			r2["from"] = "you"
			(plan[mine_level] as Array).append(r2)
	for i in maxi(0, baths - int(placed.get("bathroom", 0))):
		var lv := 0 if (i == 0 and floors == 1) or (i == 1 and floors > 1) else up
		var bath := _room("bathroom")
		bath["from"] = _from(answers, facts, "bathroom")
		(plan[lv] as Array).append(bath)
	if basement and (plan[-1] as Array).is_empty():
		(plan[-1] as Array).append(_room("storage"))   # ("from": a guess)
	# Number repeated rooms ("Bedroom 2"), keep "My room". (A found hall is not a room: see layout_floor.)
	var totals := {}
	for lv in plan:
		for r in plan[lv]:
			if not bool(r.get("mine", false)) and str(r.kind) != "hall":
				totals[str(r.kind)] = int(totals.get(str(r.kind), 0)) + 1
	var nth := {}
	for lv in plan.keys():
		for r in plan[lv]:
			if bool(r.get("mine", false)) or str(r.kind) == "hall":
				continue
			var k := str(r.kind)
			nth[k] = int(nth.get(k, 0)) + 1
			if int(totals[k]) > 1:
				r["name"] = "%s %d" % [str(ROOM_KINDS[k].name), int(nth[k])]
	_use_found_names(plan)
	return plan


## A room the research named keeps that name ("Playroom", "Study") in place of the plain one ("Family room
## 2"), which stays as its alias: a change you made under the plain name still finds the room. No two rooms
## share a name, and "My room" stays "My room".
static func _use_found_names(plan: Dictionary) -> void:
	var taken := {}
	for lv in plan:
		for r in plan[lv]:
			if bool(r.get("mine", false)) or not r.has("own_name"):
				taken[str(r.name)] = true
	for lv in plan:
		for r in plan[lv]:
			if str(r.kind) == "hall":
				continue   # (kept for layout_floor, which names the hallway)
			var found := str(r.get("own_name", ""))
			r.erase("own_name")
			if found == "" or bool(r.get("mine", false)):
				continue
			var wanted := found
			var n := 2
			while taken.has(wanted):
				wanted = "%s %d" % [found, n]
				n += 1
			taken[wanted] = true
			if wanted != str(r.name):
				r["alias"] = str(r.name)
				r["name"] = wanted


static func _room(kind: String, area: float = 0.0) -> Dictionary:
	var k: Dictionary = ROOM_KINDS.get(kind, ROOM_KINDS.bedroom)
	return {"kind": kind, "name": str(k.name), "area": area if area > 0.0 else float(k.area), "band": str(k.band), "mine": false, "from": "guess"}


## Where a room's count came from: "you" (the Survey's room counts), "records" (a helper's research) or
## "guess" (Polox's default for a home like yours). The sketch shows it; you can correct any of them.
static func _from(answers: Dictionary, facts: Dictionary, kind: String) -> String:
	var rooms: Variant = answers.get("rooms")
	if rooms is Dictionary and (rooms as Dictionary).has(kind):
		return "you"
	if kind in ["bedroom", "bathroom"] and int(facts.get(kind + "s", 0)) > 0:
		return "records"
	return "guess"


## The house's outline in cells: from the research when it has measurements (the assessor's sketch),
## else from the square footage, else from the rooms themselves. Wider along the street.
static func _footprint(answers: Dictionary, facts: Dictionary, plan: Dictionary, floors: int) -> Vector2i:
	var fw := int(round(float(facts.get("footprint_w", 0.0))))
	var fd := int(round(float(facts.get("footprint_d", 0.0))))
	if fw >= 4 and fd >= 4:
		return Vector2i(clampi(fw, 5, MAX_SIDE), clampi(fd, 5, MAX_SIDE))
	var area := 0.0
	var sqft := float(facts.get("sqft", 0.0))
	if sqft > 0.0:
		area = sqft * 0.0929 / maxf(1.0, floors)
	else:
		for lv in plan:
			var a := 0.0
			for r in plan[lv]:
				a += float(r.area)
			area = maxf(area, a * 1.6)   # hallways, stairs and walls take room too
	area = clampf(area, 55.0, 400.0)
	var w := int(round(sqrt(area * 1.25)))
	var d := int(round(area / maxf(1.0, w)))
	return Vector2i(clampi(w, 6, MAX_SIDE), clampi(d, 6, MAX_SIDE))


# --- One floor ----------------------------------------------------------------------------------

## Lays out one floor: a hallway across the middle (with a stub to the front door downstairs), the
## street-side rooms in front of it and the rest behind; small floors skip the hallway. Returns the
## floor dictionary (rooms, edges, stairs).
static func layout_floor(rooms_in: Array, w: int, d: int, opts: Dictionary) -> Dictionary:
	var rooms: Array = []
	var found_hall := {}   # what the research said of this floor's hall: it dresses the hallway below
	for r in rooms_in:
		if str(r.kind) == "hall":
			if found_hall.is_empty():
				found_hall = r
			continue
		rooms.append((r as Dictionary).duplicate(true))
	var owner := []   # owner[z][x] = room index
	for z in d:
		var row := []
		row.resize(w)
		row.fill(-1)
		owner.append(row)
	var out_rooms: Array = []
	var level := int(opts.get("level", 0))
	var stairs := bool(opts.get("stairs", false))
	var use_hall := rooms.size() >= 4 or stairs
	var entry := str(opts.get("entry", "hall"))
	var front_door := bool(opts.get("front_door", false))
	var where := str(opts.get("where", ""))
	var bands := _bands(rooms, where, use_hall)
	var front: Array = bands[0]
	var back: Array = bands[1]
	var hall_d := 0
	if use_hall:
		hall_d = 2 if d >= 11 else 1
	var front_d := _front_depth(front, back, d - hall_d, opts, use_hall)
	var back_d := d - hall_d - front_d
	var hall_idx := -1
	if use_hall:
		hall_idx = out_rooms.size()
		out_rooms.append(_hallway(level, found_hall, [0, back_d, w, hall_d]))
		for z in range(back_d, back_d + hall_d):
			for x in w:
				owner[z][x] = hall_idx
	# Downstairs, the hallway reaches the front door unless the door opens into the living room.
	var stub := Rect2i()
	if use_hall and front_door and entry != "living" and front.size() >= 2:
		var sw := 2 if w >= 12 else 1
		var sx := w / 2 - sw / 2
		stub = Rect2i(sx, back_d + hall_d, sw, front_d)
		for z in range(stub.position.y, stub.end.y):
			for x in range(stub.position.x, stub.end.x):
				owner[z][x] = hall_idx
		out_rooms[hall_idx]["stub"] = [stub.position.x, stub.position.y, stub.size.x, stub.size.y]
	# The bands.
	if back_d > 0:
		_slice(back, 0, 0, w, back_d, owner, out_rooms, Rect2i())
	_slice(front, 0, back_d + hall_d, w, front_d, owner, out_rooms, stub)
	var floor_rooms := _keep_built_rooms(out_rooms, owner, w, d)
	var hall := -1
	for i in floor_rooms.size():
		if str(floor_rooms[i].kind) == "hall":
			hall = i
	var f := {"w": w, "d": d, "rooms": floor_rooms, "edges": [], "furniture": [], "stairs": [], "owner": owner}
	if hall >= 0:
		f["hall_z"] = int(floor_rooms[hall].rect[1])
	var stair_cells := {}
	if stairs and hall >= 0:
		var r: Array = floor_rooms[hall].rect
		var sx2 := clampi(int(opts.get("stairs_x", w - 3)), 0, w - 3)
		f["stairs"] = [sx2, int(r[1])]
		for i in 3:
			stair_cells[Vector2i(sx2 + i, int(r[1]))] = true
	_edges(f)
	_doors(f, hall, front_door, entry, stair_cells)
	_windows(f)
	f.erase("owner")
	f["owner_rows"] = []
	for z in d:
		f.owner_rows.append(PackedInt32Array(owner[z]))
	return f


## The rooms in two bands, [street side, back], each in its left-to-right order. Your room goes to the
## side you said; the bands are kept balanced (the smallest rooms move across until neither side is more
## than twice the other) and neither is left empty when there are rooms to share.
static func _bands(rooms: Array, where: String, use_hall: bool) -> Array:
	var front: Array = []
	var back: Array = []
	for r in rooms:
		var b := str(r.band)
		if bool(r.get("mine", false)) and where in ["front", "back"]:
			b = where
		(front if b == "front" else back).append(r)
	_balance(front, back)
	if front.is_empty() and not back.is_empty():
		front.append(back.pop_back())
	if not use_hall and back.is_empty() and front.size() > 1:
		back.append(front.pop_back())
	_order(front, where)
	_order(back, where)
	return [front, back]


## How many cells deep the street-side band is, of the `avail` left beside the hallway: by the rooms' areas
## (between 40% and 60%), or whatever keeps the hallway on the same row as downstairs (opts.hall_z).
static func _front_depth(front: Array, back: Array, avail: int, opts: Dictionary, use_hall: bool) -> int:
	var fa := 0.0
	for r in front:
		fa += float(r.area)
	var ba := 0.0
	for r in back:
		ba += float(r.area)
	var min_band := 3 if avail >= 6 else 2
	var front_d := clampi(int(round(avail * clampf(fa / maxf(1.0, fa + ba), 0.4, 0.6))), min_band, avail - min_band) if not back.is_empty() else avail
	if opts.has("hall_z") and use_hall and not back.is_empty():
		front_d = clampi(avail - int(opts.hall_z), 1, avail - 1)   # the same hallway row as downstairs
	return front_d


## The floor's own hallway (the landing in a basement), dressed in what the research said of the hall it
## found there: its paint, its floor and its name (the plain name stays as an alias).
static func _hallway(level: int, found_hall: Dictionary, rect: Array) -> Dictionary:
	var hallway := {"id": "hall_%d" % level, "name": "Hallway" if level != -1 else "Landing", "kind": "hall", "mine": false, "rect": rect}
	for look in ["wall", "floor"]:
		if str(found_hall.get(look, "")) != "":
			hallway[look] = str(found_hall[look])
	if str(found_hall.get("own_name", "")) != "":
		hallway["alias"] = str(hallway.name)
		hallway["name"] = str(found_hall.own_name)
	return hallway


## The rooms that got at least one cell (a band too narrow for all of them leaves some without), with
## `owner` renumbered to match and any cell left over joined to its neighbour.
static func _keep_built_rooms(out_rooms: Array, owner: Array, w: int, d: int) -> Array:
	var floor_rooms: Array = []
	var remap := {}
	for i in out_rooms.size():
		var cells := 0
		for z in d:
			for x in w:
				if int(owner[z][x]) == i:
					cells += 1
		if cells > 0:
			remap[i] = floor_rooms.size()
			floor_rooms.append(out_rooms[i])
	for z in d:
		for x in w:
			var o := int(owner[z][x])
			owner[z][x] = int(remap.get(o, -1))
	for z in d:
		for x in w:
			if int(owner[z][x]) < 0:
				owner[z][x] = int(owner[z][maxi(0, x - 1)]) if x > 0 and int(owner[z][x - 1]) >= 0 else (int(owner[maxi(0, z - 1)][x]) if z > 0 else 0)
	return floor_rooms


static func _balance(front: Array, back: Array) -> void:
	for _i in 6:
		var fa := 0.0
		for r in front:
			fa += float(r.area)
		var ba := 0.0
		for r in back:
			ba += float(r.area)
		if ba > fa * 2.2 and back.size() > 1:
			back.sort_custom(func(a, b): return float(a.area) < float(b.area))
			var moved = back.pop_front()
			if bool(moved.get("mine", false)) and back.size() > 0:
				back.append(moved)
				moved = back.pop_front()
			front.append(moved)
		elif fa > ba * 2.2 and front.size() > 1:
			front.sort_custom(func(a, b): return float(a.area) < float(b.area))
			back.append(front.pop_front())
		else:
			return


## Left to right: your room first if it's on the left, last if on the right; kitchen beside dining,
## bathrooms next to bedrooms.
static func _order(band: Array, where: String) -> void:
	var rank := {"garage": 0, "living": 1, "office": 2, "family": 2, "dining": 3, "kitchen": 4, "laundry": 5, "bathroom": 6, "bedroom": 7, "storage": 8}
	band.sort_custom(func(a, b):
		var ra := float(rank.get(str(a.kind), 9)) + (0.5 if bool(a.get("mine", false)) else 0.0)
		var rb := float(rank.get(str(b.kind), 9)) + (0.5 if bool(b.get("mine", false)) else 0.0)
		if bool(a.get("mine", false)) and where == "left":
			ra = -1.0
		if bool(b.get("mine", false)) and where == "left":
			rb = -1.0
		if bool(a.get("mine", false)) and where == "right":
			ra = 99.0
		if bool(b.get("mine", false)) and where == "right":
			rb = 99.0
		return ra < rb)


## Cuts a band into rooms side by side, widths by area (at least MIN_W cells each). A stub (the hallway
## to the front door) splits the band in two. Rooms that can't fit stack two to a slot.
static func _slice(band: Array, x0: int, z0: int, w: int, d: int, owner: Array, out_rooms: Array, stub: Rect2i) -> void:
	if band.is_empty() or d <= 0:
		return
	var spans: Array = []   # [x, width]
	if stub.size.x > 0:
		spans = [[x0, stub.position.x - x0], [stub.end.x, x0 + w - stub.end.x]]
	else:
		spans = [[x0, w]]
	# Share the rooms between the spans by area.
	var groups: Array = []
	for s in spans:
		groups.append([])
	if spans.size() == 2:
		var total := 0.0
		for r in band:
			total += float(r.area)
		var left_target := total * float(spans[0][1]) / maxf(1.0, float(spans[0][1]) + float(spans[1][1]))
		var acc := 0.0
		for r in band:
			if acc < left_target and (groups[0] as Array).size() * MIN_W + MIN_W <= int(spans[0][1]):
				(groups[0] as Array).append(r)
				acc += float(r.area)
			else:
				(groups[1] as Array).append(r)
		if (groups[0] as Array).is_empty() and (groups[1] as Array).size() > 1:
			(groups[0] as Array).append((groups[1] as Array).pop_front())
	else:
		groups[0] = band
	for gi in spans.size():
		var sx: int = spans[gi][0]
		var sw: int = spans[gi][1]
		var rooms: Array = groups[gi]
		if rooms.is_empty() or sw <= 0:
			continue
		# Slots: pairs of small rooms share one when there isn't width for all.
		var slots: Array = []
		for r in rooms:
			slots.append([r])
		while slots.size() * MIN_W > sw and slots.size() > 1:
			slots.sort_custom(func(a, b): return _area(a) < _area(b))
			var a: Array = slots.pop_front()
			var b: Array = slots.pop_front()
			slots.append(a + b)
		var total := 0.0
		for s in slots:
			total += _area(s)
		var widths: Array = []
		var used := 0
		for i in slots.size():
			var ww := maxi(MIN_W, int(round(float(sw) * _area(slots[i]) / maxf(1.0, total))))
			widths.append(ww)
			used += ww
		var i2 := 0
		while used != sw and slots.size() > 0:
			var j := i2 % slots.size()
			if used > sw and int(widths[j]) > MIN_W:
				widths[j] = int(widths[j]) - 1
				used -= 1
			elif used < sw:
				widths[j] = int(widths[j]) + 1
				used += 1
			i2 += 1
			if i2 > 400:
				break
		var x := sx
		for si in slots.size():
			var slot: Array = slots[si]
			var ww: int = widths[si]
			var zz := z0
			for ri in slot.size():
				var r: Dictionary = slot[ri]
				var dd := d if slot.size() == 1 else (d - (d / slot.size()) * (slot.size() - 1) if ri == slot.size() - 1 else d / slot.size())
				var idx := out_rooms.size()
				var k: Dictionary = ROOM_KINDS.get(str(r.kind), ROOM_KINDS.bedroom)
				out_rooms.append({"id": "%s_%d_%d" % [str(r.kind), z0, x], "name": str(r.name), "kind": str(r.kind), "mine": bool(r.get("mine", false)),
					"rect": [x, zz, ww, dd], "floor": str(r.get("floor", k.floor)), "wall": str(r.get("wall", k.wall)), "from": str(r.get("from", "guess"))})
				if r.has("alias"):
					out_rooms[idx]["alias"] = str(r.alias)
				for z in range(zz, mini(zz + dd, z0 + d)):
					for xx in range(x, mini(x + ww, sx + sw)):
						owner[z][xx] = idx
				zz += dd
			x += ww


static func _area(slot: Array) -> float:
	var a := 0.0
	for r in slot:
		a += float(r.area)
	return a


## Every wall: between cells of different rooms, and around the outside.
static func _edges(f: Dictionary) -> void:
	var w: int = f.w
	var d: int = f.d
	var owner: Array = f.owner
	var edges: Array = []
	for z in range(d + 1):
		for x in w:
			var a := int(owner[z - 1][x]) if z > 0 else -1
			var b := int(owner[z][x]) if z < d else -1
			if a != b:
				edges.append({"x": x, "z": z, "dir": "h", "outer": a < 0 or b < 0, "door": false, "window": false, "front": false, "a": a, "b": b})
	for x in range(w + 1):
		for z in d:
			var a := int(owner[z][x - 1]) if x > 0 else -1
			var b := int(owner[z][x]) if x < w else -1
			if a != b:
				edges.append({"x": x, "z": z, "dir": "v", "outer": a < 0 or b < 0, "door": false, "window": false, "front": false, "a": a, "b": b})
	f["edges"] = edges


## Doors: every room opens onto the hallway when it touches it; the rest join up through their
## neighbours (a spanning tree from the entry), so every room can be reached. The front door is in the
## middle of the south wall (into the hallway's stub, or the entry room).
static func _doors(f: Dictionary, hall: int, front_door: bool, entry: String, stair_cells: Dictionary = {}) -> void:
	var n: int = (f.rooms as Array).size()
	var shared := {}   # "a|b" -> [edge indices]
	for i in (f.edges as Array).size():
		var e: Dictionary = f.edges[i]
		if bool(e.outer):
			continue
		# Never a door onto the stairs.
		var c1 := Vector2i(int(e.x), int(e.z))
		var c2 := Vector2i(int(e.x), int(e.z) - 1) if str(e.dir) == "h" else Vector2i(int(e.x) - 1, int(e.z))
		if stair_cells.has(c1) or stair_cells.has(c2):
			continue
		var k := "%d|%d" % [mini(int(e.a), int(e.b)), maxi(int(e.a), int(e.b))]
		if not shared.has(k):
			shared[k] = []
		shared[k].append(i)
	var connected := {}
	var start := hall
	if start < 0:
		start = 0
		for i in n:
			if str(f.rooms[i].kind) == entry or (entry == "hall" and str(f.rooms[i].kind) == "living"):
				start = i
				break
	connected[start] = true
	if hall >= 0:
		for i in n:
			if i != hall and shared.has("%d|%d" % [mini(i, hall), maxi(i, hall)]):
				_open_door(f, shared["%d|%d" % [mini(i, hall), maxi(i, hall)]])
				connected[i] = true
	var guard := 0
	while connected.size() < n and guard < 200:
		guard += 1
		var linked := false
		for k in shared:
			var ab: PackedStringArray = str(k).split("|")
			var a := int(ab[0])
			var b := int(ab[1])
			if connected.has(a) != connected.has(b):
				_open_door(f, shared[k])
				connected[a] = true
				connected[b] = true
				linked = true
				break
		if not linked:
			break
	if front_door:
		var w: int = f.w
		var d: int = f.d
		var target := hall if hall >= 0 and (f.rooms[hall] as Dictionary).has("stub") else -1
		if target < 0:
			for i in n:
				if str(f.rooms[i].kind) == entry and int(f.rooms[i].rect[1]) + int(f.rooms[i].rect[3]) == d:
					target = i
			if target < 0:
				for i in n:
					if int(f.rooms[i].rect[1]) + int(f.rooms[i].rect[3]) == d and str(f.rooms[i].kind) in ["living", "hall", "dining", "kitchen", "family"]:
						target = i
						break
		var best := -1
		var best_d := 1 << 20
		for i in (f.edges as Array).size():
			var e: Dictionary = f.edges[i]
			if str(e.dir) == "h" and int(e.z) == d and (target < 0 or int(e.a) == target):
				var dist := absi(int(e.x) - w / 2)
				if dist < best_d:
					best_d = dist
					best = i
		if best >= 0:
			f.edges[best]["door"] = true
			f.edges[best]["front"] = true


## Opens the middle edge of a shared wall.
static func _open_door(f: Dictionary, idxs: Array) -> void:
	if idxs.is_empty():
		return
	var mid: int = idxs[idxs.size() / 2]
	f.edges[mid]["door"] = true


## Windows on outside walls: one every three metres or so, not on the hallway, one small one in a bathroom.
static func _windows(f: Dictionary) -> void:
	var per_room := {}
	for i in (f.edges as Array).size():
		var e: Dictionary = f.edges[i]
		if not bool(e.outer) or bool(e.door):
			continue
		var r := int(e.a) if int(e.a) >= 0 else int(e.b)
		if r < 0:
			continue
		var kind := str(f.rooms[r].kind)
		if kind in ["hall", "garage", "storage"]:
			continue
		var side := "%s%d" % [str(e.dir), int(e.z) if str(e.dir) == "h" else int(e.x)]
		var key := "%d|%s" % [r, side]
		if not per_room.has(key):
			per_room[key] = []
		per_room[key].append(i)
	var bath_done := {}
	for key in per_room:
		var idxs: Array = per_room[key]
		var r := int(str(key).split("|")[0])
		var kind := str(f.rooms[r].kind)
		if kind in ["bathroom", "laundry"]:
			if bath_done.has(r):
				continue
			bath_done[r] = true
			f.edges[idxs[idxs.size() / 2]]["window"] = true
			continue
		var n := idxs.size()
		var count := maxi(1, n / 3)
		for c in count:
			var at := int((float(c) + 0.5) * n / count)
			f.edges[idxs[clampi(at, 0, n - 1)]]["window"] = true


static func _style(f: Dictionary, answers: Dictionary) -> void:
	var mine: Dictionary = answers.get("my_room", {}) if answers.get("my_room") is Dictionary else {}
	var floors: Dictionary = answers.get("floor_kinds", {}) if answers.get("floor_kinds") is Dictionary else {}
	for r in f.rooms:
		var k: Dictionary = ROOM_KINDS.get(str(r.kind), ROOM_KINDS.bedroom)
		if not r.has("floor"):
			r["floor"] = str(k.floor)
		if not r.has("wall"):
			r["wall"] = str(k.wall)
		if floors.has(str(r.kind)):
			r["floor"] = str(floors[str(r.kind)])
		if bool(r.get("mine", false)):
			if str(mine.get("wall", "")) != "":
				r["wall"] = str(mine.wall)
			if str(mine.get("floor_kind", "")) != "":
				r["floor"] = str(mine.floor_kind)


# --- Furniture ----------------------------------------------------------------------------------

## What each kind of room gets, in order: [model, rotations to try, extra, where]. `where` places a piece
## by one already in the room ("mode:model,model"): "beside" (a nightstand at the bed's head, along the
## same wall), "facing" (the TV on the wall across from the sofa, lined up with it), "front" (the coffee
## table or rug in front of the sofa, the rug at the foot of the bed) and "around" (chairs at a table or a
## desk, turned to it; left out when there's no table). Rotation 0 has its back to the north wall.
const FURNISH := {
	"bedroom": [["bed", [0, 2]], ["nightstand", [0, 2], "", "beside:bed,double_bed"], ["wardrobe", [0, 1, 3, 2]], ["desk", [0, 2, 1, 3], "desk"],
		["chair", [0], "", "around:desk"], ["rug", [0], "", "front:bed,double_bed"], ["lamp", [0], "", "beside:desk"], ["plant", [0]]],
	"living": [["sofa", [2, 0, 1, 3]], ["tv", [0, 2, 1, 3], "", "facing:sofa"], ["coffee_table", [0], "", "front:sofa"], ["armchair", [1, 3, 0, 2], "", "beside:coffee_table"],
		["lamp", [0], "", "beside:sofa"], ["plant", [0]], ["rug", [0], "", "front:sofa"]],
	"kitchen": [["fridge", [0, 1, 3, 2]], ["stove", [0, 1, 3, 2]], ["counter", [0, 1, 3, 2]], ["sink", [0, 1, 3, 2]], ["counter", [0, 1, 3, 2]], ["dining_table", [0, 1], "middle"],
		["chair", [0], "", "around:dining_table"], ["chair", [0], "", "around:dining_table"]],
	"dining": [["dining_table", [0, 1], "middle"], ["chair", [0], "", "around:dining_table"], ["chair", [0], "", "around:dining_table"],
		["chair", [0], "", "around:dining_table"], ["chair", [0], "", "around:dining_table"], ["plant", [0]]],
	"bathroom": [["toilet", [0, 1, 3, 2]], ["washbasin", [0, 1, 3, 2]], ["bathtub", [0, 2, 1, 3]], ["shower", [0, 1, 3, 2]]],
	"office": [["desk", [0, 2, 1, 3]], ["chair", [0], "", "around:desk"], ["bookshelf", [0, 1, 3, 2]], ["lamp", [0], "", "beside:desk"], ["plant", [0]]],
	"laundry": [["washer", [0, 1, 3, 2]], ["counter", [0, 1, 3, 2]]],
	"garage": [["car", [0, 2]]],
	"family": [["sofa", [2, 0, 1, 3]], ["tv", [0, 2, 1, 3], "", "facing:sofa"], ["bookshelf", [0, 1, 3, 2]], ["rug", [0], "", "front:sofa"]],
	"storage": [["bookshelf", [0, 1, 3, 2]]],
	"hall": [["runner", [0, 1], "hall"], ["plant", [0]]],
}
## Which way a piece faces (rotation 0 has its back to the north wall, so it faces south, +z).
const FACING := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]


## Puts the main furniture in each room, against walls, keeping doorways and the stairs clear.
static func furnish(f: Dictionary, answers: Dictionary) -> void:
	var Furniture: Script = load("res://scripts/world/furniture.gd")
	var w: int = f.w
	var d: int = f.d
	var taken := {}
	var keep := {}   # cells next to doors (both sides) stay free
	for e in f.edges:
		if bool(e.door):
			if str(e.dir) == "h":
				keep[Vector2i(int(e.x), int(e.z))] = true
				keep[Vector2i(int(e.x), int(e.z) - 1)] = true
			else:
				keep[Vector2i(int(e.x), int(e.z))] = true
				keep[Vector2i(int(e.x) - 1, int(e.z))] = true
	var st: Array = f.get("stairs", [])
	if st.size() >= 2:
		for i in 3:
			taken[Vector2i(int(st[0]) + i, int(st[1]))] = true
		for i in 3:
			keep[Vector2i(int(st[0]) + i, int(st[1]) + 1)] = true
			keep[Vector2i(int(st[0]) - 1, int(st[1]))] = true
	# Solid pieces must never shut any part of the floor off: a plant across a one-cell hallway once left
	# half the rooms out of reach, and a desk, its chair and a lamp boxed you into a corner of your room.
	var walls := {}
	for e in f.edges:
		if not bool(e.door):
			walls["%s|%d|%d" % [str(e.dir), int(e.x), int(e.z)]] = true
	var solid := taken.duplicate()   # cells you can't walk through: the stairs, then each solid piece
	var doorways: Array = keep.keys().filter(func(c): return c.x >= 0 and c.y >= 0 and c.x < w and c.y < d and not solid.has(c))
	var start: Vector2i = doorways[0] if not doorways.is_empty() else Vector2i(-1, -1)
	var open := {"cells": FloorPaths.walk(start, solid, walls, w, d) if start.x >= 0 else {}}   # every cell you can walk to so far
	var open_check := func(fp: Rect2i) -> bool:
		return _keeps_open(fp, solid, walls, open.cells, start, w, d)
	var mine: Dictionary = answers.get("my_room", {}) if answers.get("my_room") is Dictionary else {}
	var furniture: Array = []
	for ri in (f.rooms as Array).size():
		var room: Dictionary = f.rooms[ri]
		var r: Array = room.rect
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		var list: Array = FURNISH.get(str(room.kind), [])
		for item in list:
			var model := str(item[0])
			var extra := str(item[2]) if item.size() > 2 else ""
			if model == "bed" and bool(room.get("mine", false)) and str(mine.get("bed", "")) == "double":
				model = "double_bed"
			if extra == "desk" and not (bool(room.get("mine", false)) and bool(mine.get("desk", true))):
				continue
			if model in ["bathtub"] and rect.size.x * rect.size.y < 6:
				continue
			if model == "shower" and furniture.any(func(p): return int(p.room) == ri and str(p.model) == "bathtub"):
				continue
			if model == "dining_table" and str(room.kind) == "kitchen" and furniture.any(func(p): return str(p.model) == "dining_table"):
				continue
			if model == "dining_table" and str(room.kind) == "kitchen" and (f.rooms as Array).any(func(o): return str(o.kind) == "dining"):
				continue
			var hint := {}
			var where := str(item[3]) if item.size() > 3 else ""
			if where != "":
				var mode := where.get_slice(":", 0)
				var anchors := where.get_slice(":", 1).split(",")
				var found: Array = furniture.filter(func(p): return int(p.room) == ri and str(p.model) in anchors)
				if found.is_empty():
					if mode == "around" or model == "lamp":
						continue   # no chair without its table, no lamp without what it lights
				else:
					var a: Dictionary = found[0]
					hint = {"mode": mode, "rot": int(a.rot), "at": Furniture.footprint({"model": str(a.model), "pos": [a.x, 0, a.z], "rot": a.rot})}
			var spot := _spot(Furniture, model, item[1], rect, taken, keep, f.owner_rows if f.has("owner_rows") else f.get("owner", []), ri, extra, hint, open_check)
			if spot.is_empty():
				continue
			var piece := {"room": ri, "model": model, "x": int(spot.x), "z": int(spot.z), "rot": int(spot.rot), "color": ""}
			if bool(room.get("mine", false)) and model in ["bed", "double_bed"] and str(mine.get("bed_color", "")) != "":
				piece["color"] = str(mine.bed_color)
			furniture.append(piece)
			var fp: Rect2i = Furniture.footprint({"model": model, "pos": [spot.x, 0, spot.z], "rot": spot.rot})
			var blocks: bool = Furniture.blocks(model)
			for z in range(fp.position.y, fp.end.y):
				for x in range(fp.position.x, fp.end.x):
					taken[Vector2i(x, z)] = true
					if blocks:
						solid[Vector2i(x, z)] = true
			if blocks and start.x >= 0:
				open.cells = FloorPaths.walk(start, solid, walls, w, d)
	f["furniture"] = furniture


## Cells between two footprints (0 = touching, corners too).
static func _gap(a: Rect2i, b: Rect2i) -> int:
	var dx := maxi(0, maxi(a.position.x - b.end.x, b.position.x - a.end.x))
	var dz := maxi(0, maxi(a.position.y - b.end.y, b.position.y - a.end.y))
	return maxi(dx, dz)


## Whether every cell you can walk to (`open`, from `start`) still can with a solid piece on `fp`: no
## piece may shut a doorway, a corner or anything else off.
static func _keeps_open(fp: Rect2i, solid: Dictionary, walls: Dictionary, open: Dictionary, start: Vector2i, w: int, d: int) -> bool:
	if open.is_empty():
		return true
	if fp.has_point(start):
		return false
	var added: Array = []
	for z in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			var c := Vector2i(x, z)
			if not solid.has(c):
				solid[c] = true
				added.append(c)
	var seen := FloorPaths.walk(start, solid, walls, w, d)
	for c in added:
		solid.erase(c)
	return open.keys().all(func(c): return fp.has_point(c) or seen.has(c))


## The first place a piece fits: inside the room, on free cells, not in a doorway's way, its back to a
## wall (or, for "middle" pieces, away from the walls). `hint` (FURNISH's `where`): {"mode", "rot", "at"
## (the anchor piece's footprint)} orders the search by that piece; "front" and "around" pieces stand
## free, and "around" turns to face the anchor.
static func _spot(Furniture: Script, model: String, rots: Array, rect: Rect2i, taken: Dictionary, keep: Dictionary, owner: Array, ri: int, extra: String, hint: Dictionary = {}, open_check: Callable = Callable()) -> Dictionary:
	var flat: bool = not Furniture.blocks(model)
	var mode := str(hint.get("mode", ""))
	var tries: Array = rots.duplicate()
	if mode in ["beside", "facing"]:
		var want := int(hint.rot) if mode == "beside" else (int(hint.rot) + 2) % 4
		tries.erase(want)
		tries.push_front(want)
	var at: Rect2i = hint.get("at", Rect2i())
	var ac := Vector2(at.position) + Vector2(at.size) / 2.0
	for rot in tries:
		var size: Vector2i = Furniture.base_size(model)
		if int(rot) % 2 == 1:
			size = Vector2i(size.y, size.x)
		if extra == "hall" and (int(rot) % 2 == 1) != (rect.size.x >= rect.size.y):
			continue   # a runner lies along the hallway
		var order: Array = []
		for z in range(rect.position.y, rect.end.y - size.y + 1):
			for x in range(rect.position.x, rect.end.x - size.x + 1):
				order.append(Vector2i(x, z))
		if extra == "middle":
			var c := rect.get_center()
			order.sort_custom(func(a, b): return Vector2(a + size / 2).distance_to(Vector2(c)) < Vector2(b + size / 2).distance_to(Vector2(c)))
		elif mode != "":
			var target := ac
			if mode == "front":
				target = ac + FACING[int(hint.rot)] * (maxf(at.size.x, at.size.y) / 2.0 + 0.8)
			var score := func(q: Vector2i) -> float:
				var pc := Vector2(q) + Vector2(size) / 2.0
				if mode == "facing":
					return (absf(pc.x - ac.x) if int(rot) % 2 == 0 else absf(pc.y - ac.y)) * 10.0 + pc.distance_to(ac) * 0.01
				return pc.distance_to(target)
			order.sort_custom(func(a, b): return score.call(a) < score.call(b))
		for p in order:
			var fp := Rect2i(p, size)
			if mode == "around" and _gap(fp, at) > 0:
				continue   # a chair at its table or desk, or none
			var ok := true
			for z in range(fp.position.y, fp.end.y):
				for x in range(fp.position.x, fp.end.x):
					var c2 := Vector2i(x, z)
					if taken.has(c2) or (not flat and keep.has(c2)) or (owner.size() > z and int(owner[z][x]) != ri):
						ok = false
			if not ok:
				continue
			if not flat and open_check.is_valid() and not open_check.call(fp):
				continue   # it would wall something off
			if mode == "around":
				# Turned to the table: face whichever way it lies furthest.
				var to := ac - (Vector2(p) + Vector2(size) / 2.0)
				var face := 0 if absf(to.y) >= absf(to.x) and to.y > 0.0 else (2 if absf(to.y) >= absf(to.x) else (3 if to.x > 0.0 else 1))
				return {"x": p.x, "z": p.y, "rot": face}
			if flat or extra == "middle" or extra == "hall" or mode == "front":
				return {"x": p.x, "z": p.y, "rot": int(rot)}
			var against := false
			match int(rot):
				0:
					against = fp.position.y == rect.position.y
				1:
					against = fp.end.x == rect.end.x
				2:
					against = fp.end.y == rect.end.y
				3:
					against = fp.position.x == rect.position.x
			if against:
				return {"x": p.x, "z": p.y, "rot": int(rot)}
	return {}
