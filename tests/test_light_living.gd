extends "res://tests/test_case.gd"
## Phase 33, living in the Light World: Edit my room instead of Build mode (one tap opens it, one closes it;
## only real-life furniture and decor inside, small things outside; placing, moving, turning, recolouring,
## taking away and painting all kept as your edits, Undo putting them back); the Light World never shows Dark
## World-only things (outlines, void skies, battles, platform pillars, blocks); daily life (things to do in
## the room you're in, watering a plant, the curtains, the view, the journal kept private, footsteps by
## floor, "this used to be..." once a day); your 1.13.1 choices untouched.

const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeEdit := preload("res://scripts/home/home_edit.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const Realms := preload("res://scripts/world/realms.gd")
const LightLife := preload("res://scripts/world/light_life.gd")
const DecorEditor := preload("res://scripts/world/decor_editor.gd")

var main: Node


func _answers() -> Dictionary:
	return {"address": "12 Example Lane, Testville", "home_type": "house", "floors": 2,
		"rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1, "dining": 1}, "my_room": {"floor": 1, "where": "front", "desk": true, "view": "trees"},
		"used_to_be": "", "renovations": ""}


func _boot_home() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	HomeMapper.build_home(_answers(), {}, "")
	GameState.settings["reduce_motion"] = true
	await main.game.dark.go_light()
	await frames(2)
	return main.game


func _shutdown() -> void:
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func _mine_rect(g: Node) -> Rect2i:
	return HomePlaces.mine_rect(g.room.data)


## A free cell where a solid piece shuts nothing off (Edit my room refuses one that would: floor_paths.gd).
func _free_cell(g: Node, rect: Rect2i) -> Vector2i:
	var FloorPaths: GDScript = load("res://scripts/world/floor_paths.gd")
	var shut := (FloorPaths.pockets(g.room.data) as Dictionary).size()
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, z)
			if g.room.nav.walkable(c) and load("res://scripts/world/room_editor.gd").object_at(g.room.data, x, z).is_empty() and c != g.player.cell() \
					and (FloorPaths.pockets(g.room.data, "", Rect2i(c, Vector2i.ONE)) as Dictionary).size() <= shut:
				return c
	return Vector2i(-1, -1)


func test_edit_my_room_is_limited_and_kept() -> void:
	var g: Node = await _boot_home()
	g.build.enter()
	await frames(2)
	check(not g.build.active, "Build mode doesn't open in your real home...")
	check(g.decor.active, "...Edit my room does (one tap)")
	var picks: Array = g.decor.find_children("Pick_*", "Button", true, false).map(func(b): return str(b.name).trim_prefix("Pick_"))
	check(picks.has("plant") and picks.has("rug") and picks.has("picture") and picks.has("lamp"), "real-life furniture and decor")
	for no in ["cube", "pillar", "platform_pillar", "door", "battle_spot", "dark_fountain", "bench", "car", "stairs"]:
		check(not picks.has(no), "no %s inside" % no)
	var spot := _free_cell(g, _mine_rect(g))
	check(spot.x >= 0, "a free spot in your room")
	g.decor.choose("plant")
	g.decor.tap_cell(spot)
	await frames(2)
	var o: Dictionary = load("res://scripts/world/room_editor.gd").object_at(g.room.data, spot.x, spot.y)
	eq(str(o.get("model", "")), "plant", "a plant where you tapped")
	var edits: Array = HomeStore.load_home().edits
	check(edits.any(func(e): return str(e.type) == "place" and str(e.model) == "plant"), "kept as your edit")
	# Recolour it, move it, turn it.
	g.decor.pick(o)
	g.decor.recolor("#c96a5a")
	await frames(2)
	o = load("res://scripts/world/room_editor.gd").object_at(g.room.data, spot.x, spot.y)
	eq(str(o.get("color", "")), "#c96a5a", "recoloured")
	var spot2 := _free_cell(g, _mine_rect(g))
	g.decor.pick(o)
	g.decor.moving = true
	g.decor.tap_cell(spot2)
	await frames(2)
	eq(str(load("res://scripts/world/room_editor.gd").object_at(g.room.data, spot2.x, spot2.y).get("model", "")), "plant", "moved")
	# Paint the room you're standing in.
	var mr := _mine_rect(g)
	g.player.position = g.room.cell_center(mr.get_center())
	g.decor.paint_here("#e8bfc4")
	await frames(2)
	var plan_mine: Dictionary = {}
	for f in HomeStore.load_home().plan.floors:
		for r in f.rooms:
			if bool(r.get("mine", false)):
				plan_mine = r
	eq(str(plan_mine.get("wall", "")), "#e8bfc4", "your room painted")
	# Undo the paint, then the move: back where it was.
	g.decor.undo_last()
	g.decor.undo_last()
	await frames(2)
	eq(str(load("res://scripts/world/room_editor.gd").object_at(g.room.data, spot.x, spot.y).get("model", "")), "plant", "Undo: back where it was")
	# And it survives the house being rebuilt (Map my home again).
	HomeMapper.build_home(_answers(), {}, "")
	var up := SaveManager.load_room(HomePlaces.place_id(1))
	check((up.objects as Array).any(func(x): return str(x.get("model", "")) == "plant" and str(x.get("color", "")) == "#c96a5a"), "mapped again: your plant stays")
	g.decor.close()
	check(not g.decor.active, "one tap closes it")
	await _shutdown()


func test_outside_only_small_things() -> void:
	var g: Node = await _boot_home()
	var town: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/osm_madeup_town.json"))
	HomeMapper.build_streets(load("res://scripts/home/osm.gd").clean(town, 10.0, 10.0, 250), _answers())
	var gid := HomePlaces.place_id(0)
	var street := ""
	for o in SaveManager.load_room(gid).objects:
		if bool(o.get("street_gate", false)):
			street = str(o.door_target)
	g.load_room(street, gid)
	await frames(2)
	g.build.enter()
	var picks: Array = g.decor.find_children("Pick_*", "Button", true, false).map(func(b): return str(b.name).trim_prefix("Pick_"))
	check(picks.has("bench") and picks.has("flowers") and picks.has("mailbox"), "outside: a bench, flowers, a mailbox")
	check(not picks.has("sofa") and not picks.has("bed"), "not a sofa or a bed")
	check(not g.decor.place("sofa", g.player.cell() + Vector2i(1, 0)), "a sofa outside is refused")
	var c: Vector2i = g.player.cell() + Vector2i(2, 0)
	if g.room.nav.walkable(c):
		check(g.decor.place("bench", c), "a bench on your street")
		HomeMapper.build_streets(load("res://scripts/home/osm.gd").clean(town, 10.0, 10.0, 250), _answers())
		check((SaveManager.load_room(street).objects as Array).any(func(o): return bool(o.get("user", false)) and str(o.get("model", "")) == "bench"), "kept when the streets are mapped again")
	g.decor.close()
	await _shutdown()


func test_the_light_world_never_shows_dark_world_things() -> void:
	var g: Node = await _boot_home()
	# Something that doesn't belong, written into your room's file by hand.
	var id: String = GameState.current_room_id
	var data := SaveManager.load_room(id)
	(data.objects as Array).append({"id": "pp", "type": "platform_pillar", "pos": [1, 0, 1], "rot": 0})
	(data.objects as Array).append({"id": "bs", "type": "battle_spot", "pos": [2, 0, 1], "rot": 0})
	(data.objects as Array).append({"id": "df", "type": "dark_fountain", "pos": [3, 0, 1], "rot": 0, "state": "new"})
	(data.tiles as Array).append({"x": 1, "y": 0, "z": 2, "type": "cube", "color": "#8a7bc8"})
	SaveManager.save_room(data)
	g.load_room(id)
	await frames(2)
	var types: Array = (g.room.data.objects as Array).map(func(o): return str(o.get("type", "")))
	check(not types.has("platform_pillar"), "no platform pillar")
	check(not types.has("battle_spot"), "no battle spot")
	eq(types.filter(func(t): return t == "dark_fountain").size(), 1, "only the way to the Dream World")
	eq((g.room.data.tiles as Array).size(), 0, "no blocks")
	eq(g.dark_look.lines_built, 0, "no glowing outlines")
	check(str(g.room.data.background.sky) != "void", "no void sky")
	g.battles.forced_roll = 0.0
	g.battles.last_encounter = -1e9
	check(not await g.battles.try_encounter(), "no encounters")
	g.battles.open_setup("")
	await frames(2)
	check(not main.panels.any(func(p): return is_instance_valid(p) and str(p.get_script().resource_path).ends_with("battle_setup_panel.gd")), "no battles from the menu either")
	await _shutdown()


func test_daily_life() -> void:
	var g: Node = await _boot_home()
	var mr := _mine_rect(g)
	g.player.position = g.room.cell_center(mr.get_center())
	await frames(2)
	var list: Array = g.light_life.things_to_do()
	var keys: Array = list.map(func(t): return str(t[2]))
	check(keys.has("desk"), "sit at your desk")
	check(keys.has("window"), "look out of the window")
	check(keys.has("curtains"), "the curtains")
	check(keys.has("journal"), "write in your journal")
	# The view you told the Survey.
	g.light_life.look_out()
	await frames(2)
	# The curtains, remembered.
	var rid := str(g.light_life.room_here().get("id", "room"))
	check(g.light_life.curtains_open_here(), "open to start")
	g.light_life.curtains(rid)
	check(not g.light_life.curtains_open_here(), "drawn")
	check(FileAccess.file_exists(HomeStore.path("life.json")), "remembered in my_home")
	g.light_life.curtains(rid)
	# The journal: yours alone.
	check(load("res://scripts/home/journal_panel.gd").write("A slow, good day."), "a journal line kept")
	check(FileAccess.get_file_as_string(HomeStore.path("journal.json")).contains("A slow, good day."), "in my_home/journal.json")
	var synced: Dictionary = load("res://scripts/phone/sync_files.gd").scan(SaveManager.root, PackedStringArray([SaveManager.slot_id]))
	check(not synced.keys().any(func(p): return str(p).contains("journal.json") and str(p).contains("my_home")), "never synced")
	# Tapping yourself shows the list.
	var before: int = main.panels.size()
	g.light_life.open_things_to_do()
	await frames(2)
	eq(main.panels.size(), before + 1, "things to do")
	await _shutdown()


func test_a_room_remembers_what_it_used_to_be() -> void:
	var g: Node = await _boot_home()
	var mine := {}
	for f in HomeStore.load_home().plan.floors:
		for r in f.rooms:
			if bool(r.get("mine", false)):
				mine = r
	HomeEdit.commit([{"type": "used_to_be", "level": 1, "room": str(mine.id), "was": "the playroom"}], "words")
	g.load_room(GameState.current_room_id, "", g.player.cell())
	await frames(2)
	eq(LightLife.history_line(g.light_life.room_here()), "This used to be the playroom.", "the line for your room")
	g.light_life._here_room = ""
	g.light_life._moment_in_room()
	eq(str(g.light_life._room_seen.get(str(mine.id), "")), Time.get_date_string_from_system(), "shown once today")
	g.light_life._here_room = ""
	var seen_before: Dictionary = g.light_life._room_seen.duplicate()
	g.light_life._moment_in_room()
	eq(g.light_life._room_seen, seen_before, "and not again today")
	await _shutdown()


func test_footsteps_sound_like_the_floor() -> void:
	var room := {"floor_areas": [{"rect": [0, 0, 3, 3], "color": load("res://scripts/home/layout_builder.gd").FLOOR_COLORS.carpet},
		{"rect": [3, 0, 3, 3], "color": load("res://scripts/home/layout_builder.gd").FLOOR_COLORS.tile},
		{"rect": [6, 0, 3, 3], "color": load("res://scripts/home/layout_builder.gd").FLOOR_COLORS.wood}], "kind": "indoor", "id": "lw_floor_1"}
	eq(LightLife.step_sound(room, Vector2i(1, 1)), "step_soft", "carpet")
	eq(LightLife.step_sound(room, Vector2i(4, 1)), "step_stone", "tiles")
	eq(LightLife.step_sound(room, Vector2i(7, 1)), "step_wood", "wood")
	var street := {"floor_areas": [{"rect": [0, 0, 5, 2], "kind": "road", "color": "#8a8a90"}], "kind": "outdoor", "id": "lw_hood_1_1"}
	eq(LightLife.step_sound(street, Vector2i(1, 1)), "step_stone", "the road")
	eq(LightLife.step_sound(street, Vector2i(1, 4)), "step_grass", "the grass")
