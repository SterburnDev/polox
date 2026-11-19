extends "res://tests/test_case.gd"
## Phase 32, your neighbourhood: a small saved OpenStreetMap extract of a made-up town (in the repository)
## becomes Light World places joined at their edges, with its streets, buildings, the park and the pond; no
## neighbour's name, number or anything else is kept; your front door opens onto your street and your
## ground floor's gate leads back out; walking from your door to the park works; the World Map shows the
## streets hand-drawn with "© OpenStreetMap contributors"; nothing goes to OpenStreetMap before LOOK IT UP.
## Tags: [LIGHT_WORLD_MAP]

const Osm := preload("res://scripts/home/osm.gd")
const HoodBuilder := preload("res://scripts/home/hood_builder.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const Places := preload("res://scripts/world/places.gd")
const Realms := preload("res://scripts/world/realms.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")

const TOWN := "res://tests/fixtures/osm_madeup_town.json"

var main: Node


func _extract(radius: int = 250) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TOWN))
	return Osm.clean(raw, 10.0, 10.0, radius)


func _answers() -> Dictionary:
	return {"address": "12 Example Lane, Testville", "home_type": "house", "floors": 2, "radius": 250, "places": "Maple Park, the corner shop",
		"rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1}, "my_room": {"floor": 1}}


func test_the_extract_keeps_streets_and_leaves_people_out() -> void:
	var e := _extract()
	var feats: Array = e.features
	var kinds := {}
	for f in feats:
		kinds[str(f.kind)] = int(kinds.get(str(f.kind), 0)) + 1
	eq(int(kinds.get("road", 0)), 2, "two streets")
	eq(int(kinds.get("path", 0)), 1, "a footpath")
	check(int(kinds.get("building", 0)) >= 10, "the houses and the school (%d)" % int(kinds.get("building", 0)))
	eq(int(kinds.get("park", 0)), 1, "the park")
	eq(int(kinds.get("water", 0)), 1, "the pond")
	eq(int(kinds.get("tree", 0)), 4, "trees")
	eq(int(kinds.get("bench", 0)), 1, "a bench")
	check(feats.any(func(f): return str(f.kind) == "poi" and str(f.name) == "Corner Shop"), "the corner shop by name (a public place)")
	check(feats.any(func(f): return str(f.kind) == "building" and str(f.name) == "Testville Elementary"), "the school by name")
	var text := JSON.stringify(e)
	check(not text.contains("Samples"), "a house's name is never kept")
	check(not text.contains("Somebody Private"), "nor an owner")
	check(not text.contains("housenumber") and not text.contains("addr:"), "nor house numbers")
	eq(str(e.credit), "© OpenStreetMap contributors")
	var home: Array = feats.filter(func(f): return str(f.kind) == "building" and Geometry2D.is_point_in_polygon(Vector2.ZERO, PackedVector2Array((f.pts as Array).map(func(q): return Vector2(float(q[0]), float(q[1]))))))
	eq(home.size(), 1, "your house is the shape at the middle")


func test_the_town_becomes_joined_places() -> void:
	var places := HoodBuilder.build(_extract(), "Maple Park", [{"name": "Maple Park", "note": "A small park with a pond and a playground."}])
	var ids: Array = places.keys().filter(func(k): return str(k).begins_with("lw_hood_"))
	check(ids.size() >= 4, "a few blocks (%d)" % ids.size())
	for id in ids:
		var p: Dictionary = places[id]
		eq(Realms.realm(p), Realms.LIGHT, "%s is in the Light World" % id)
		eq(str(p.kind), "outdoor")
	var a: Dictionary = places[HoodBuilder.chunk_id(0, 0)]
	var b: Dictionary = places[HoodBuilder.chunk_id(1, 0)]
	eq(Places.edge(a, "east"), HoodBuilder.chunk_id(1, 0), "blocks join east...")
	eq(Places.edge(b, "west"), HoodBuilder.chunk_id(0, 0), "...and back")
	var roads := 0
	var water := 0
	var parks := 0
	var buildings := 0
	var mine := 0
	var signs: Array = []
	for id in ids:
		var p: Dictionary = places[id]
		for ar in p.floor_areas:
			match str(ar.kind):
				"road":
					roads += int(ar.rect[2]) * int(ar.rect[3])
				"water":
					water += int(ar.rect[2]) * int(ar.rect[3])
				"park":
					parks += int(ar.rect[2]) * int(ar.rect[3])
		for bl in p.buildings:
			buildings += 1
			if str(bl.kind) == "mine":
				mine += 1
			if str(bl.kind) == "home":
				eq(str(bl.name), "", "a neighbour's house has no name")
		for o in p.objects:
			if str(o.get("type", "")) == "sign":
				signs.append(str(o.get("interaction_text", "")))
	check(roads > 200, "the streets are there (%d cells)" % roads)
	check(water > 10, "the pond (%d)" % water)
	check(parks > 200, "the park (%d)" % parks)
	check(buildings >= 10, "the buildings (%d)" % buildings)
	check(mine >= 1, "your house")
	check(signs.any(func(t): return str(t).contains("Maple Park") and str(t).contains("playground")), "the park's sign, with what's public about it")
	check(signs.any(func(t): return str(t).contains("Corner Shop")), "the corner shop's sign")
	var hc := str(places.home_chunk)
	var home_place: Dictionary = places[hc]
	var door: Array = (home_place.objects as Array).filter(func(o): return str(o.get("type", "")) == "door" and str(o.get("door_target", "")) == HomePlaces.place_id(0))
	eq(door.size(), 1, "your front door, into your ground floor")


func _front_door(p: Dictionary) -> Dictionary:
	for o in p.objects:
		if str(o.get("type", "")) == "door" and str(o.get("door_target", "")) == HomePlaces.place_id(0):
			return o
	return {}


## Your front door is set into your house's wall, facing the street, the size of the neighbours' doors
## (it stood in the middle of the path's first cell, as tall as the house); the mailbox stands beside it.
func test_your_front_door_is_in_your_house_wall() -> void:
	var places := HoodBuilder.build(_extract())
	var hp: Dictionary = places[str(places.home_chunk)]
	var door := _front_door(hp)
	check(bool(door.get("front_door", false)), "marked as your front door")
	eq(float(door.get("scale", 0.0)), LightHome.FRONT_DOOR_SCALE, "the street's size")
	var wall := LightHome.door_wall(hp, door)
	check(not wall.is_empty(), "your house is right behind it")
	var cell := Vector2i(int(door.pos[0]), int(door.pos[2]))
	var f: Vector2i = BlockFactory.facing(int(door.rot))
	eq(Vector2i(int(hp.spawn[0]), int(hp.spawn[1])), cell + f, "it faces your path, where you arrive")
	var boxes: Array = (hp.objects as Array).filter(func(o): return str(o.get("model", "")) == "mailbox")
	eq(boxes.size(), 1, "a mailbox")
	if boxes.size() == 1:
		var m := Vector2i(int(boxes[0].pos[0]), int(boxes[0].pos[2]))
		check((m - cell).length_squared() == 1 and (m - cell).x * f.x + (m - cell).y * f.y == 0, "beside the door, along the house")
		check(not HoodBuilder._building_at(hp, m), "not in a house")


## A street made before: its door (rot 0, full size, maybe turned sideways) gets set into the wall when the
## place loads, once; turned away from the house afterwards, it stands in its own cell and stays as you left it.
func test_an_older_streets_door_is_set_in_when_it_loads() -> void:
	var places := HoodBuilder.build(_extract())
	var hp: Dictionary = places[str(places.home_chunk)]
	var door := _front_door(hp)
	var right := int(door.rot)
	door.erase("front_door")
	door["rot"] = (right + 1) % 4
	door["scale"] = 1.0
	check(LightHome.door_wall(hp, door).is_empty(), "an old door isn't in the wall")
	LightHome.sanitize(hp)
	eq(int(door.rot), right, "turned to face out")
	eq(float(door.scale), LightHome.FRONT_DOOR_SCALE, "and down to the street's size")
	check(not LightHome.door_wall(hp, door).is_empty(), "in your house's wall now")
	door["rot"] = (right + 2) % 4
	LightHome.sanitize(hp)
	eq(int(door.rot), (right + 2) % 4, "turned round in Build mode, it stays that way")
	check(LightHome.door_wall(hp, door).is_empty(), "and stands in its own cell")


func test_the_mailbox_goes_beside_the_door_whichever_way_it_faces() -> void:
	var p := {"size": {"w": 20, "d": 20}, "objects": [], "barriers": [{"cells": [[6, 4]]}],
		"buildings": [{"kind": "mine", "cells": [[5, 5], [6, 5], [5, 6], [6, 6]]}]}
	eq(HoodBuilder.mailbox_cell(p, Vector2i(5, 7), Vector2i(0, 1)), Vector2i(6, 7), "south front: to the east, as before")
	eq(HoodBuilder.mailbox_cell(p, Vector2i(7, 5), Vector2i(1, 0)), Vector2i(7, 6), "east front: along the wall, not in front of the door")
	eq(HoodBuilder.mailbox_cell(p, Vector2i(4, 6), Vector2i(-1, 0)), Vector2i(4, 7), "west front: not in the house")
	eq(HoodBuilder.mailbox_cell(p, Vector2i(5, 4), Vector2i(0, -1)), Vector2i(4, 4), "north front: the other side of the fence")
	p.objects.append({"type": "prop", "pos": [7, 0, 6]})
	p.objects.append({"type": "prop", "pos": [7, 0, 4]})
	eq(HoodBuilder.mailbox_cell(p, Vector2i(7, 5), Vector2i(1, 0)), Vector2i(-1, -1), "both sides taken: none")


## A walk from your front door to the park, across the blocks (each block's own ground: buildings and
## water in the way, streets, paths and grass open).
func test_walking_from_your_door_to_the_park() -> void:
	var places := HoodBuilder.build(_extract(), "", [])
	var size := 0
	var ids: Array = places.keys().filter(func(k): return str(k).begins_with("lw_hood_"))
	var n := int(sqrt(float(ids.size())))
	size = n * HoodBuilder.CHUNK
	var blocked := {}
	var park := {}
	var start := Vector2i(-1, -1)
	for id in ids:
		var p: Dictionary = places[id]
		var ox := int(p.hood.ci) * HoodBuilder.CHUNK
		var oz := int(p.hood.cj) * HoodBuilder.CHUNK
		for bl in p.buildings:
			for c in bl.cells:
				blocked[Vector2i(int(c[0]) + ox, int(c[1]) + oz)] = true
		for ar in p.floor_areas:
			var r: Array = ar.rect
			for z in range(int(r[1]), int(r[1]) + int(r[3])):
				for x in range(int(r[0]), int(r[0]) + int(r[2])):
					if str(ar.kind) == "water":
						blocked[Vector2i(x + ox, z + oz)] = true
					elif str(ar.kind) == "park":
						park[Vector2i(x + ox, z + oz)] = true
		for o in p.objects:
			if str(o.get("type", "")) == "door" and str(o.get("door_target", "")) == HomePlaces.place_id(0):
				start = Vector2i(int(o.pos[0]) + ox, int(o.pos[2]) + oz)
	check(start.x >= 0, "your front door is on the map")
	var seen := {start: true}
	var q: Array = [start]
	var reached := false
	while not q.is_empty() and not reached:
		var c: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: Vector2i = c + d
			if nx.x < 0 or nx.y < 0 or nx.x >= size or nx.y >= size or seen.has(nx) or blocked.has(nx):
				continue
			seen[nx] = true
			if park.has(nx):
				reached = true
				break
			q.append(nx)
	check(reached, "from your door to the park on foot")


func test_in_the_game_door_gate_and_the_edge_between_blocks() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var g: Node = main.game
	HomeMapper.build_home(_answers(), {}, "")
	check(HomeMapper.build_streets(_extract(), _answers()), "the streets built")
	check(FileAccess.file_exists(HomeStore.path("osm.json")), "the map kept in my_home (offline after)")
	var gid := HomePlaces.place_id(0)
	var ground := SaveManager.load_room(gid)
	var gate: Array = (ground.objects as Array).filter(func(o): return bool(o.get("street_gate", false)))
	eq(gate.size(), 1, "your ground floor's gate out to the street")
	var hc := str(gate[0].door_target) if not gate.is_empty() else ""
	check(SaveManager.room_exists(hc), "it leads to your street")
	GameState.settings["reduce_motion"] = true
	await g.dark.go_light()
	g.load_room(hc, gid)
	await frames(3)
	eq(GameState.current_room_id, hc, "out on your street")
	check(g.room.edge_walls.buildings > 3, "the houses drawn (%d)" % g.room.edge_walls.buildings)
	var door: Dictionary = g.room.door_to(gid)
	check(not door.is_empty(), "arriving beside your front door")
	check(Vector2(g.player.cell() - g.room.obj_cell(door)).length() <= 2.0, "right beside it")
	# Drawn in your house's wall (on the face of its block), not out on the path.
	var node: Node3D = g.room.object_nodes.get(str(door.get("id", "")))
	var wall := LightHome.door_wall(g.room.data, door)
	check(node != null and not wall.is_empty(), "your front door in your house's wall")
	if node and not wall.is_empty():
		var c: Vector2i = g.room.obj_cell(door)
		var f: Vector2i = wall[1]
		check(node.position.distance_to(Vector3(c.x + 0.5 - f.x * 0.51, node.position.y, c.y + 0.5 - f.y * 0.51)) < 0.001, "on the wall's face")
		check(is_equal_approx(node.scale.x, LightHome.FRONT_DOOR_SCALE), "the size of the neighbours' doors")
		eq(g.room.nav.nearest_walkable(c), c, "and its cell still walkable (that's how you go in)")
	# Walk off the east edge into the next block.
	var east := Places.edge(g.room.data, "east")
	if east != "":
		await g.cross_edge("east", Vector2i(g.room.w - 1, int(g.room.d / 2)))
		eq(GameState.current_room_id, east, "across the join into the next block")
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func test_the_world_map_draws_the_streets_with_the_credit() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var g: Node = main.game
	HomeMapper.build_home(_answers(), {}, "")
	HomeMapper.build_streets(_extract(), _answers())
	GameState.settings["reduce_motion"] = true
	await g.dark.go_light()
	var map: Control = load("res://scripts/ui/world_map_view.gd").new()
	main.open_panel(map)
	map.setup_map(g)
	await frames(3)
	eq(map.layer, "light")
	check(map.hood_view != null and map.hood_view.is_visible_in_tree(), "the streets, hand-drawn")
	var credit: Label = map.find_child("OsmCredit", true, false)
	check(credit != null and credit.text.contains("© OpenStreetMap contributors"), "with the credit")
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func test_nothing_goes_to_openstreetmap_before_look_it_up() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	GameState.settings["reduce_motion"] = true
	var mapper: Node = HomeMapper.new()
	main.add_child(mapper)
	mapper.available_override = {"none": true}
	mapper.recorded_osm = ProjectSettings.globalize_path(TOWN)
	var result := {"entry": ""}
	var run := func() -> void: result.entry = await mapper.run(main)
	run.call()
	await frames(2)
	var sc: Control = mapper.screen
	# Through the Survey to the last screen, without a helper: the streets still need your OK.
	for _i in 400:
		var st: Dictionary = sc.step()
		if str(st.get("kind", "")) == "consent" and sc._area.get_child_count() > 0 and not sc._typing:
			break
		if sc._typing or sc._waiting_tap:
			sc._tap()
		elif str(st.get("kind", "")) == "text":
			if str(st.key) == "address":
				sc.field.text = "12 Example Lane, Testville"
				sc._submit_text(sc.field.text)
			else:
				sc._skip_step()
		elif str(st.get("kind", "")) == "counts":
			for b in sc._area.find_children("*", "Button", true, false):
				if (b as Button).text.begins_with("THAT'S"):
					(b as Button).pressed.emit()
					break
		else:
			var bs: Array = sc._area.find_children("*", "Button", true, false)
			if not bs.is_empty():
				(bs[0] as Button).pressed.emit()
		await frames(1)
	var consent: Label = sc.find_child("ConsentText", true, false)
	check(consent != null and consent.text.contains("OpenStreetMap"), "the last screen names OpenStreetMap")
	check(not FileAccess.file_exists(HomeStore.path("osm.json")), "no map fetched yet")
	for b in sc.find_children("JustMyAnswers", "Button", true, false):
		(b as Button).pressed.emit()
	var t := Time.get_ticks_msec()
	while str(result.entry) == "" and Time.get_ticks_msec() - t < 15000:
		if is_instance_valid(sc):
			for b in sc.find_children("KeepHomePreview", "Button", true, false):
				(b as Button).pressed.emit()
		await frames(2)
	check(not FileAccess.file_exists(HomeStore.path("osm.json")), "just your answers: no map fetched at all")
	check(not Array(SaveManager.list_light_rooms()).any(func(id): return str(id).begins_with("lw_hood_")), "and no streets")
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func test_coordinates_from_a_map_app() -> void:
	eq(Osm.parse_coords("40.7128, -74.0060"), {"lat": 40.7128, "lon": -74.006})
	eq(Osm.parse_coords("(51.5, -0.12)"), {"lat": 51.5, "lon": -0.12})
	eq(Osm.parse_coords("12 Example Lane"), {}, "an address isn't coordinates")
	eq(Osm.parse_coords("100, 10"), {}, "nor is nonsense")
	var q := Osm.query(10.0, 10.0, 250)
	check(q.contains("around:250,10.000000,10.000000") and q.contains("out geom"), "the Overpass question: coordinates and radius only")
	check(not q.contains("Example"), "never the address")
