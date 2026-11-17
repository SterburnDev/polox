extends "res://tests/test_case.gd"
## Update 9: homes that look lived in. Furniture placed by what it goes with (a nightstand at the bed's
## head, the TV across from the sofa, the coffee table and rug in front of it, chairs round the table and
## at the desk, turned to them); floors drawn in their material; where each room came from (your answers,
## the records or a guess), shown in My home; and the World Map fitted to the neighbourhood, not the roads.

const LayoutBuilder := preload("res://scripts/home/layout_builder.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const EdgeWalls := preload("res://scripts/world/edge_walls.gd")
const HoodMapView := preload("res://scripts/home/hood_map_view.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const FloorPaths := preload("res://scripts/world/floor_paths.gd")

const ANSWERS := {"home_type": "house", "floors": 2,
	"rooms": {"bedroom": 3, "bathroom": 2, "kitchen": 1, "living": 1, "dining": 1, "office": 1, "laundry": 1, "garage": 0},
	"entry_room": "hall", "my_room": {"floor": 1, "where": "front", "wall": "#a9c4dc", "floor_kind": "carpet", "bed": "single", "desk": true},
	"floor_kinds": {"kitchen": "tile", "living": "wood"}}


func test_wall_segments_have_flat_normals_and_no_length_overlap() -> void:
	var ew := EdgeWalls.new()
	tree.root.add_child(ew)
	ew.build({"edge_walls": [{"x": 0, "z": 0, "dir": "h"}]}, 2.6)
	var mesh: ArrayMesh = ew.get_node("Walls").mesh
	var arrays := mesh.surface_get_arrays(0)
	for v in arrays[Mesh.ARRAY_VERTEX]:
		check(v.x >= -0.0001 and v.x <= 1.0001, "wall stays within its segment instead of overlapping the next")
	for n in arrays[Mesh.ARRAY_NORMAL]:
		check(absf(absf(n.x) + absf(n.y) + absf(n.z) - 1.0) < 0.001, "box face has an axis-aligned normal (packed mesh precision): %s" % n)
	ew.build({"edge_walls": [{"x": 0, "z": 0, "dir": "h", "door": true}]}, 2.6)
	eq(ew.doors, 1, "door leaf and header build")
	ew.build({}, 2.6)
	check(ew.walls_mat == null and ew.glass_mat == null and ew.floor_mat == null, "leaving the house releases material references")
	ew.queue_free()
	await frames(1)


func _pieces(plan: Dictionary) -> Array:
	var out: Array = []
	for f in plan.floors:
		for p in f.furniture:
			var q: Dictionary = p.duplicate()
			q["level"] = int(f.level)
			q["kind"] = str(f.rooms[int(p.room)].kind)
			q["fp"] = Furniture.footprint({"model": str(p.model), "pos": [p.x, 0, p.z], "rot": p.rot})
			out.append(q)
	return out


func _gap(a: Rect2i, b: Rect2i) -> int:
	# Cells between two footprints (0 = touching).
	var dx := maxi(0, maxi(a.position.x - b.end.x, b.position.x - a.end.x))
	var dz := maxi(0, maxi(a.position.y - b.end.y, b.position.y - a.end.y))
	return maxi(dx, dz)


func _with(all: Array, level: int, room: int, model: String) -> Array:
	return all.filter(func(p): return int(p.level) == level and int(p.room) == room and str(p.model) == model)


func test_furniture_goes_with_what_it_belongs_to() -> void:
	var plan := LayoutBuilder.build(ANSWERS)
	var all := _pieces(plan)
	var beds := all.filter(func(p): return str(p.model) in ["bed", "double_bed"])
	check(beds.size() >= 3, "a bed in each bedroom (%d)" % beds.size())
	var by_bed := 0
	for b in beds:
		for n in _with(all, int(b.level), int(b.room), "nightstand"):
			if _gap(b.fp, n.fp) == 0 and int(n.rot) == int(b.rot):
				by_bed += 1
	check(by_bed >= beds.size() - 1, "nightstands stand at their beds' heads (%d of %d)" % [by_bed, beds.size()])
	var sofas := all.filter(func(p): return str(p.model) == "sofa")
	check(not sofas.is_empty(), "a sofa")
	for s in sofas:
		var tvs := _with(all, int(s.level), int(s.room), "tv")
		if not tvs.is_empty():
			var tv: Dictionary = tvs[0]
			eq(int(tv.rot), (int(s.rot) + 2) % 4, "the TV faces the sofa")
			var sc := Vector2(s.fp.get_center())
			var tc := Vector2(tv.fp.get_center())
			check((absf(sc.x - tc.x) if int(s.rot) % 2 == 0 else absf(sc.y - tc.y)) <= 2.0, "and lines up with it (%s / %s)" % [str(sc), str(tc)])
		for t in _with(all, int(s.level), int(s.room), "coffee_table"):
			check(_gap(s.fp, t.fp) <= 1, "the coffee table is in front of the sofa")
	var tables := all.filter(func(p): return str(p.model) == "dining_table")
	check(not tables.is_empty(), "a dining table")
	for t in tables:
		var chairs := _with(all, int(t.level), int(t.room), "chair")
		check(chairs.size() >= 2, "chairs at the table (%d)" % chairs.size())
		for c in chairs:
			check(_gap(t.fp, c.fp) == 0, "each chair at the table")
			var to := Vector2(t.fp.get_center()) - Vector2(c.fp.get_center())
			var facing: Vector2 = LayoutBuilder.FACING[int(c.rot)]
			check(facing.dot(to) > 0.0, "turned to it (rot %d, table at %s)" % [int(c.rot), str(to)])
	var desks := all.filter(func(p): return str(p.model) == "desk")
	for d in desks:
		var dc := _with(all, int(d.level), int(d.room), "chair")
		check(not dc.is_empty() and _gap(d.fp, dc[0].fp) == 0, "a chair at the desk")
	# Same answers, same house.
	eq(JSON.stringify(LayoutBuilder.build(ANSWERS)), JSON.stringify(plan), "deterministic")


## No piece of furniture shuts any part of a floor off, and you start where you can walk away from (a desk,
## its chair and a lamp once boxed the player into a corner of their room: 1.27.10).
func test_no_furniture_shuts_any_part_of_a_floor_off() -> void:
	var homes := [ANSWERS, {"home_type": "apartment", "floors": 1, "rooms": {"bedroom": 1, "bathroom": 1, "kitchen": 1, "living": 1, "dining": 0}},
		{"home_type": "house", "floors": 3, "basement": true, "rooms": {"bedroom": 5, "bathroom": 3, "office": 1, "family": 1, "garage": 1, "dining": 1}},
		{"home_type": "house", "floors": 2, "rooms": {"bedroom": 4, "bathroom": 2}, "my_room": {"floor": 1, "where": "front", "desk": true, "bed": "double"}}]
	for answers in homes:
		var places := HomePlaces.build(LayoutBuilder.build(answers))
		for id in places:
			var p: Dictionary = places[id]
			var shut := FloorPaths.pockets(p)
			check(shut.is_empty(), "%s: nothing shut off (%s)" % [str(p.name), str(shut.keys())])
			LightHome.sanitize(p)
			var s: Array = p.spawn
			check(FloorPaths.reachable(p).has(Vector2i(int(s[0]), int(s[1]))), "%s: you start where you can walk away from" % str(p.name))


## A home built before that rule, boxed in like the player's own room was: when it loads, the smallest piece
## that shuts the corner off moves aside, and the spawn is somewhere you can walk from.
func test_a_floor_that_boxes_you_in_is_opened_when_it_loads() -> void:
	var p := LightHome.base_place("lw_floor_1", "Upstairs", 6, 6)
	p["rooms"] = [{"id": "mine", "kind": "bedroom", "mine": true, "rect": [0, 0, 4, 4]}, {"id": "hall", "kind": "hall", "mine": false, "rect": [0, 4, 6, 2]}]
	var walls: Array = []
	for x in 4:
		walls.append({"x": x, "z": 4, "dir": "h", "door": x == 0})
	for z in 4:
		walls.append({"x": 4, "z": z, "dir": "v", "door": false})
	p["edge_walls"] = walls
	p["objects"] = []
	for piece in [["double_bed", 0, 0, 0], ["nightstand", 2, 0, 0], ["wardrobe", 3, 0, 0], ["desk", 1, 3, 2], ["chair", 1, 2, 0], ["lamp", 3, 3, 2]]:
		var o := LightHome.add(p, str(piece[0]), int(piece[1]), int(piece[2]), int(piece[3]))
		o["room"] = "mine"
	p["spawn"] = [2, 2]
	var shut := FloorPaths.pockets(p)
	check(shut.has(Vector2i(2, 2)) and shut.size() == 4, "as built, you're boxed into four cells (%s)" % str(shut.keys()))
	var count := (p.objects as Array).size()
	LightHome.sanitize(p)
	check(FloorPaths.pockets(p).is_empty(), "after loading, nothing is shut off")
	eq((p.objects as Array).size(), count, "every piece is still in the room")
	check(FloorPaths.reachable(p).has(Vector2i(int(p.spawn[0]), int(p.spawn[1]))), "and you can walk out of your room")


func test_doors_stay_reachable_with_free_standing_pieces() -> void:
	var homes := [ANSWERS, {"home_type": "apartment", "floors": 1, "rooms": {"bedroom": 1, "bathroom": 1, "kitchen": 1, "living": 1, "dining": 0}},
		{"home_type": "house", "floors": 3, "basement": true, "rooms": {"bedroom": 5, "bathroom": 3, "office": 1, "family": 1, "garage": 1, "dining": 1}},
		{"home_type": "house", "floors": 1, "rooms": {"bedroom": 4, "bathroom": 2, "dining": 1, "office": 1, "laundry": 1}, "my_room": {"where": "back", "desk": true, "bed": "double"}}]
	for answers in homes:
		_walk_every_floor(LayoutBuilder.build(answers))


func _walk_every_floor(plan: Dictionary) -> void:
	for f in plan.floors:
		var blocked := {}
		for p in f.furniture:
			if Furniture.blocks(str(p.model)):
				var fp := Furniture.footprint({"model": str(p.model), "pos": [p.x, 0, p.z], "rot": p.rot})
				for z in range(fp.position.y, fp.end.y):
					for x in range(fp.position.x, fp.end.x):
						blocked[Vector2i(x, z)] = true
		var walls := {}
		for e in f.edges:
			if bool(e.door):
				var sides := [Vector2i(int(e.x), int(e.z)), Vector2i(int(e.x), int(e.z) - 1)] if str(e.dir) == "h" else [Vector2i(int(e.x), int(e.z)), Vector2i(int(e.x) - 1, int(e.z))]
				for c in sides:
					if c.x >= 0 and c.y >= 0 and c.x < int(f.w) and c.y < int(f.d):
						check(not blocked.has(c), "%s: the doorway at %s is clear" % [str(f.name), str(c)])
			else:
				walls["%s|%d|%d" % [str(e.dir), int(e.x), int(e.z)]] = true
		var st: Array = f.get("stairs", [])
		if st.size() >= 2:
			for i in 3:
				blocked[Vector2i(int(st[0]) + i, int(st[1]))] = true
		# Walk from the hallway (or the first room): every room has somewhere you can stand.
		var start := Vector2i(-1, -1)
		for r in f.rooms:
			if start.x < 0 or str(r.kind) == "hall":
				for z in range(int(r.rect[1]), int(r.rect[1]) + int(r.rect[3])):
					for x in range(int(r.rect[0]), int(r.rect[0]) + int(r.rect[2])):
						if not blocked.has(Vector2i(x, z)) and (start.x < 0 or str(r.kind) == "hall"):
							start = Vector2i(x, z)
		var seen := {start: true}
		var todo := [start]
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			for step in [[Vector2i(1, 0), "v|%d|%d" % [c.x + 1, c.y]], [Vector2i(-1, 0), "v|%d|%d" % [c.x, c.y]], [Vector2i(0, 1), "h|%d|%d" % [c.x, c.y + 1]], [Vector2i(0, -1), "h|%d|%d" % [c.x, c.y]]]:
				var n: Vector2i = c + step[0]
				if n.x < 0 or n.y < 0 or n.x >= int(f.w) or n.y >= int(f.d) or seen.has(n) or blocked.has(n) or walls.has(step[1]):
					continue
				seen[n] = true
				todo.append(n)
		var all_in := true
		for r in f.rooms:
			var reached := false
			for z in range(int(r.rect[1]), int(r.rect[1]) + int(r.rect[3])):
				for x in range(int(r.rect[0]), int(r.rect[0]) + int(r.rect[2])):
					reached = reached or seen.has(Vector2i(x, z))
			all_in = all_in and reached
			check(reached, "%s: you can walk into the %s" % [str(f.name), str(r.name)])
		if not all_in:
			# The floor as text: room letter (lower case = reached), # furniture, | and _ walls, doors as gaps.
			for z in int(f.d):
				var row := ""
				var under := ""
				for x in int(f.w):
					var c := Vector2i(x, z)
					var ri := int(f.owner_rows[z][x])
					var ch := "#" if blocked.has(c) else String.chr(65 + ri)
					if seen.has(c) and ch != "#":
						ch = ch.to_lower()
					row += ("|" if walls.has("v|%d|%d" % [x, z]) else " ") + ch
					under += " " + ("_" if walls.has("h|%d|%d" % [x, z + 1]) else " ")
				print("    " + row)
				print("    " + under)
			for i in f.rooms.size():
				print("    %s = %s %s" % [String.chr(65 + i), str(f.rooms[i].name), str(f.rooms[i].rect)])
			print("    furniture: ", (f.furniture as Array).map(func(p): return "%s@%d,%d r%d" % [p.model, p.x, p.z, p.rot]))


func test_floors_have_materials_and_rooms_say_where_they_came_from() -> void:
	var plan := LayoutBuilder.build(ANSWERS)
	var places := HomePlaces.build(plan)
	var mats := {}
	for id in places:
		for a in places[id].floor_areas:
			mats[str(a.material)] = true
	for m in ["wood", "tile", "carpet"]:
		check(mats.has(m), "a %s floor" % m)
	var froms := {}
	for f in plan.floors:
		for r in f.rooms:
			if str(r.kind) != "hall":
				froms[str(r.kind)] = str(r.get("from", ""))
	eq(froms.get("kitchen", ""), "you", "the Survey counted the kitchen")
	eq(froms.get("bedroom", ""), "you", "and the bedrooms")
	var guessed := LayoutBuilder.build({"home_type": "house", "floors": 1})
	var kinds := {}
	for f in guessed.floors:
		for r in f.rooms:
			if str(r.kind) != "hall" and not bool(r.mine):
				kinds[str(r.get("from", ""))] = true
	check(kinds.has("guess") and not kinds.has("you"), "without counts, the rooms are marked as guesses: %s" % str(kinds))
	var records := LayoutBuilder.build({"home_type": "house", "floors": 1}, {"bedrooms": 3})
	var rec := false
	for f in records.floors:
		for r in f.rooms:
			rec = rec or (str(r.kind) == "bedroom" and not bool(r.mine) and str(r.get("from", "")) == "records")
	check(rec, "bedrooms the records counted say so")
	# The floor material reaches the renderer (in the vertex colour's alpha).
	var ew: Node3D = EdgeWalls.new()
	tree.root.add_child(ew)
	ew.build({"floor_areas": [{"rect": [0, 0, 2, 2], "color": "#d9d5cd", "material": "tile"}], "edge_walls": []}, 2.6)
	var mesh: ArrayMesh = ew.get_node("RoomFloors").mesh
	var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	eq(int(cols[0].a * 8.0), EdgeWalls.FLOOR_CODES.tile, "tile is drawn as tile")
	ew.queue_free()
	await frames(1)


func test_world_map_fits_the_neighbourhood_not_the_roads() -> void:
	var view: Control = HoodMapView.new()
	view.size = Vector2(400, 300)
	var houses: Array = []
	for i in 6:
		houses.append({"kind": "building", "sub": "home", "pts": [[i * 12 - 30, 10], [i * 12 - 22, 10], [i * 12 - 22, 18], [i * 12 - 30, 18]]})
	houses.append({"kind": "road", "name": "Long Road", "pts": [[-240, 0], [240, 0]]})
	view.extract = {"radius": 250, "features": houses}
	tree.root.add_child(view)
	await frames(2)
	check(view._scale > 1.5, "a few houses fill the map, the long road runs off it (%.2f px/m)" % view._scale)
	check(view.chunk_at(view.size / 2.0) != "", "and a tap still finds the block")
	view.queue_free()
	await frames(1)
