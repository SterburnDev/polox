extends "res://tests/test_case.gd"
## Phase 30, the Survey and Map my home: the questionnaire alone makes a correct layout (rooms, doors,
## connected floors, furniture out of the doorways); a recorded helper answer (a made-up house: an
## assessor sketch, permits, a listing) becomes a layout with its sources, conflicts and a history
## timeline, and no person's name survives; with no helper everything still works; nothing is sent before
## LOOK IT UP; no key or address in any log; the house built as Light World places you can walk through
## (thin walls, doors, stairs between floors, the Dream Gate in your room). No live calls: recorded
## answers only.

const LayoutBuilder := preload("res://scripts/home/layout_builder.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const SurveyData := preload("res://scripts/home/survey_data.gd")
const SurveyScreen := preload("res://scripts/home/survey_screen.gd")
const Research := preload("res://scripts/home/research.gd")
const Realms := preload("res://scripts/world/realms.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const FIXTURE := "res://tests/fixtures/home_research_madeup.json"
const ADDRESS := "12 Example Lane, Testville"
const FAKE_KEY := "sk-ant-test-THIS-IS-NOT-A-KEY-0042"

var main: Node


class PairedPhoneWithoutHome extends Node:
	var client := {"home_state": "missing"}
	var syncs := 0
	func paired() -> bool:
		return true
	func sync_now() -> void:
		syncs += 1
		await get_tree().process_frame


func test_paired_phone_placeholder_still_runs_creation_and_returns_to_dark() -> void:
	await _boot_world()
	GameState.settings["reduce_motion"] = true
	var home_script := preload("res://scripts/world/light_home.gd")
	home_script.ensure_entry() # the placeholder made by the broken paired-phone flow
	var phone := PairedPhoneWithoutHome.new()
	main.add_child(phone)
	main.phone = phone
	var finished := {"value": false}
	var travel := func() -> void:
		await main.game.dark.go_light()
		finished.value = true
	travel.call()
	await frames(5)
	var mapper: Node = main.game.dark.get_node_or_null("HomeMapper")
	check(mapper != null, "a paired phone with a placeholder gets the Survey")
	if mapper == null:
		main.phone = null
		main.queue_free()
		await frames(2)
		return
	eq(phone.syncs, 1, "first checks for an existing shared home")
	await _drive_survey(mapper.screen, "consent")
	_press(mapper.screen, "JustMyAnswers")
	var start := Time.get_ticks_msec()
	while not finished.value and Time.get_ticks_msec() - start < 15000:
		if is_instance_valid(mapper):
			_accept_home_preview(mapper)
			if is_instance_valid(mapper.screen) and (mapper.screen._typing or mapper.screen._waiting_tap):
				mapper.screen._tap()
		await frames(2)
	check(finished.value, "the creation and first arrival finish")
	check(GameState.current_room_id.begins_with("lw_floor_"), "arrives in the generated house")
	eq(main.game.dark.last_moment, "first_look", "the first-look creation scene played")
	check(not home_script.needs_survey(), "the mapped house will not ask again")
	for i in 3:
		await main.game.dark.go_dark()
		eq(GameState.current_room_id, "home", "return to Dream World %d" % i)
		await main.game.dark.go_light()
		check(GameState.current_room_id.begins_with("lw_floor_"), "return to mapped home %d" % i)
	main.phone = null
	main.queue_free()
	await frames(2)


func test_resuming_old_phone_placeholder_offers_survey() -> void:
	await _boot_world()
	GameState.settings["reduce_motion"] = true
	var light := preload("res://scripts/world/light_home.gd")
	main.game.load_room(light.ensure_entry())
	main.start_game()
	await frames(5)
	var mapper: Node = main.game.dark.get_node_or_null("HomeMapper")
	check(mapper != null, "resuming an unfinished placeholder starts creation")
	if mapper:
		_press(mapper.screen, "LEAVE")
		var deadline := Time.get_ticks_msec() + 8000
		while main.game.dark.busy and Time.get_ticks_msec() < deadline:
			await frames(2)
		check(not light.needs_survey(), "explicitly leaving is remembered locally")
		check(not preload("res://scripts/phone/sync_files.gd").home_file("my_home/survey_skipped.json".split("/")), "the skip choice is not synced")
	main.queue_free()
	await frames(2)


func _answers() -> Dictionary:
	return {"address": ADDRESS, "address_level": "full", "home_type": "house", "floors": 2, "basement": false,
		"rooms": {"bedroom": 3, "bathroom": 2, "kitchen": 1, "living": 1, "dining": 1, "office": 0, "laundry": 1, "garage": 0},
		"entry_room": "hall", "my_room": {"floor": 1, "where": "front", "wall": "#a9c4dc", "floor_kind": "carpet", "bed": "single", "desk": true, "view": "street"},
		"floor_kinds": {"kitchen": "tile", "living": "wood"}, "year_built": 0, "renovations": "We put in a deck in 2014", "memory": "Pancakes every Sunday"}


## Rooms reachable from the front door (ground floor) or the stairs, walking through doors only.
func _reachable(f: Dictionary, start: int) -> Dictionary:
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var a: int = q.pop_front()
		for e in f.edges:
			if bool(e.door) and not bool(e.outer):
				var other := -1
				if int(e.a) == a:
					other = int(e.b)
				elif int(e.b) == a:
					other = int(e.a)
				if other >= 0 and not seen.has(other):
					seen[other] = true
					q.append(other)
	return seen


func _room_of_cell(f: Dictionary, x: int, z: int) -> int:
	for i in (f.rooms as Array).size():
		var r: Array = f.rooms[i].rect
		if Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(Vector2i(x, z)):
			return i
	return -1


func test_the_questionnaire_alone_makes_a_correct_layout() -> void:
	var plan := LayoutBuilder.build(_answers())
	var floors: Array = plan.floors
	eq(floors.size(), 2, "two floors")
	var kinds := {}
	for f in floors:
		# Every cell belongs to exactly one room.
		var cells := 0
		for r in f.rooms:
			cells += int(r.rect[2]) * int(r.rect[3])
			check(int(r.rect[2]) >= 1 and int(r.rect[3]) >= 1, "%s has room" % str(r.name))
			kinds[str(r.kind)] = int(kinds.get(str(r.kind), 0)) + 1
		eq(cells, int(f.w) * int(f.d), "%s: the rooms fill the floor exactly" % str(f.name))
		var hall := -1
		for i in (f.rooms as Array).size():
			if str(f.rooms[i].kind) == "hall":
				hall = i
		check(hall >= 0, "%s has a hallway" % str(f.name))
		eq(_reachable(f, hall).size(), (f.rooms as Array).size(), "%s: every room has a door you can reach" % str(f.name))
		eq((f.stairs as Array).size(), 2, "%s has the stairs" % str(f.name))
		# No furniture overlaps, and none stands in a doorway's way.
		var taken := {}
		for p in f.furniture:
			var fp: Rect2i = Furniture.footprint({"model": str(p.model), "pos": [int(p.x), 0, int(p.z)], "rot": int(p.rot)})
			for z in range(fp.position.y, fp.end.y):
				for x in range(fp.position.x, fp.end.x):
					check(not taken.has(Vector2i(x, z)), "%s overlaps something" % str(p.model))
					taken[Vector2i(x, z)] = str(p.model)
					eq(_room_of_cell(f, x, z), int(p.room), "%s stays in its room" % str(p.model))
		for e in f.edges:
			if bool(e.door):
				var inside := [Vector2i(int(e.x), int(e.z))]
				inside.append(Vector2i(int(e.x), int(e.z) - 1) if str(e.dir) == "h" else Vector2i(int(e.x) - 1, int(e.z)))
				for c in inside:
					if taken.has(c):
						check(not Furniture.blocks(str(taken[c])), "a doorway is clear (%s at %s)" % [str(taken[c]), str(c)])
	eq(floors[0].stairs, floors[1].stairs, "the stairs line up between floors")
	eq(int(kinds.get("bedroom", 0)), 3, "three bedrooms")
	eq(int(kinds.get("bathroom", 0)), 2, "two bathrooms")
	check(kinds.has("kitchen") and kinds.has("living") and kinds.has("dining"), "kitchen, living room, dining room")
	var ground: Dictionary = floors[0]
	check((ground.edges as Array).any(func(e): return bool(e.front) and str(e.dir) == "h" and int(e.z) == int(ground.d)), "a front door on the street side")
	var up: Dictionary = floors[1]
	var mine: Array = (up.rooms as Array).filter(func(r): return bool(r.get("mine", false)))
	eq(mine.size(), 1, "your room is upstairs, as you said")
	if not mine.is_empty():
		eq(str(mine[0].wall), "#a9c4dc", "with the walls you picked")
		eq(str(mine[0].floor), "carpet", "and the floor")
		var mi := (up.rooms as Array).find(mine[0])
		check((up.furniture as Array).any(func(p): return int(p.room) == mi and str(p.model) == "bed"), "a bed in your room")
		check((up.furniture as Array).any(func(p): return int(p.room) == mi and str(p.model) == "desk"), "and your desk")
		check(int(mine[0].rect[1]) + int(mine[0].rect[3]) == int(up.d), "at the front (the street side)")
	check(ground.rooms.any(func(r): return str(r.kind) == "kitchen" and str(r.floor) == "tile"), "the kitchen floor you picked")
	eq(int(plan.mine_level), 1)
	eq(JSON.stringify(LayoutBuilder.build(_answers())), JSON.stringify(plan), "the same answers make the same house")


func test_a_one_floor_apartment_and_an_empty_survey_still_make_homes() -> void:
	var flat := LayoutBuilder.build({"home_type": "apartment", "rooms": {"bedroom": 1, "bathroom": 1, "kitchen": 1, "living": 1, "dining": 0, "laundry": 0}})
	eq((flat.floors as Array).size(), 1, "an apartment is one floor")
	var f: Dictionary = flat.floors[0]
	check((f.rooms as Array).any(func(r): return bool(r.get("mine", false))), "your room is in it")
	eq(_reachable(f, 0).size(), (f.rooms as Array).size(), "every room reachable")
	check((f.edges as Array).any(func(e): return bool(e.front)), "a front door")
	var nothing := LayoutBuilder.build({})
	check((nothing.floors as Array).size() >= 1, "no answers at all still make a home")


func test_a_recorded_answer_becomes_a_layout_with_sources_and_history() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var r := HomeModel.clean_research(raw)
	var a := _answers()
	a["floors"] = 0   # let the records say how many floors
	var home := HomeModel.make(a, r, "recorded")
	var facts := HomeModel.facts_by_key(home)
	eq(int(facts.floors), 2, "two floors from the assessor")
	eq(int(round(float(facts.footprint_w))), 10, "the outline from the assessor's sketch (10.4 m)")
	var plan := LayoutBuilder.build(a, facts)
	eq(int(plan.w), 10, "the house is as wide as the sketch")
	eq(int(plan.d), 8, "and as deep")
	eq(str(plan.made_from), "answers+research")
	# Sources, with what each said.
	var ids: Array = (home.sources as Array).map(func(s): return str(s.id))
	for want in ["assessor", "permits", "listing2019", "plat", "you"]:
		check(want in ids, "source kept: %s" % want)
	check(str(HomeModel.source(home, "assessor").url).begins_with("https://"), "with its link")
	check(str(HomeModel.source(home, "permits").said).contains("2014 deck"), "and what it said")
	# The conflict is shown, not hidden.
	var sq: Array = (home.conflicts as Array).filter(func(c): return str(c.key) == "sqft")
	eq(sq.size(), 1, "the square footage conflict (1,450 vs 1,520) is listed")
	if not sq.is_empty():
		eq((sq[0].values as Array).size(), 2)
	# The history timeline: built, three permits, the plat, and what you said.
	var t: Array = home.timeline
	check(t.any(func(e): return str(e.kind) == "built" and int(e.year) == 1962), "built in 1962")
	eq(t.filter(func(e): return str(e.kind) == "permit").size(), 3, "three permits")
	check(t.any(func(e): return str(e.kind) == "permit" and int(e.year) == 2014 and str(e.text).contains("deck")), "the 2014 deck")
	check(t.any(func(e): return str(e.kind) == "memory" and str(e.source) == "you"), "your memory")
	var years: Array = t.filter(func(e): return int(e.year) > 0).map(func(e): return int(e.year))
	var sorted_years := years.duplicate()
	sorted_years.sort()
	eq(years, sorted_years, "oldest first")
	eq((home.blocked as Array).size(), 1, "what only you can get (a login) is listed with its link")
	eq((home.open_questions as Array).size(), 2, "the helper's open questions")
	eq((home.neighbourhood as Array).size(), 2, "public places only")
	# Nobody's name, email or phone number is kept.
	var text := JSON.stringify(home) + JSON.stringify(r)
	for name in ["Jane", "Sample", "Agentman", "Bob Roofer", "John Doe", "agent@example.org", "555-123-4567"]:
		check(not text.contains(name), "no person's details kept: %s" % name)
	check(not (r as Dictionary).has("owner"), "the owner field is dropped")
	check(str(r.permits[1].work).contains("wall between kitchen and dining room removed"), "the building facts stay")


func test_scrubbing_people_out_of_text() -> void:
	eq(HomeModel.scrub_text("Owner: Jane Doe. Built 1962."), "Owner (name left out). Built 1962.")
	eq(HomeModel.scrub_text("listed by Sam Lee, 555-123-4567"), "listed by (name left out),")
	check(not HomeModel.scrub_text("Contact jane@example.com today").contains("@"), "emails go")
	eq(HomeModel.scrub_text("Kitchen remodel, 2009"), "Kitchen remodel, 2009", "building facts stay as they are")
	eq(HomeModel.scrub_text("1,450 sq ft on a 0.25 acre lot"), "1,450 sq ft on a 0.25 acre lot", "numbers aren't phone numbers")


func test_the_home_as_light_world_places_you_can_walk_through() -> void:
	fresh_save_root()
	StarterContent.create_world("Mine", "Sam")
	GameState.load_world()
	var entry := HomeMapper.build_home(_answers(), {}, "")
	eq(entry, HomePlaces.place_id(1), "you start upstairs, where your room is")
	eq(LightHome.entry_id(), entry, "the Light World starts there")
	var ids := Array(SaveManager.list_light_rooms())
	check(HomePlaces.place_id(0) in ids and HomePlaces.place_id(1) in ids, "a place per floor")
	check(not Realms.ENTRY in ids, "the plain room gave way to the house")
	var up := SaveManager.load_room(entry)
	var down := SaveManager.load_room(HomePlaces.place_id(0))
	eq(Realms.realm(up), Realms.LIGHT)
	var gate := Realms.gate_of(up)
	check(not gate.is_empty(), "the Dream Gate is upstairs")
	check(HomePlaces.mine_rect(up).has_point(Vector2i(int(gate.pos[0]), int(gate.pos[2]))), "in your room")
	var st_up: Array = (up.objects as Array).filter(func(o): return str(o.get("model", "")) == "stairs")
	var st_down: Array = (down.objects as Array).filter(func(o): return str(o.get("model", "")) == "stairs")
	eq(st_up.size(), 1)
	eq(st_down.size(), 1)
	if st_up.size() == 1 and st_down.size() == 1:
		eq(str(st_up[0].down_target), HomePlaces.place_id(0), "the stairs lead down")
		eq(str(st_down[0].door_target), entry, "and up")
	check((down.edge_walls as Array).any(func(e): return bool(e.front)), "the front door downstairs")
	check(int(down.size.w) == int(up.size.w) + HomePlaces.YARD * 2, "a lawn around the ground floor")
	check(HomeStore.exists(), "home.json saved in my_home")
	check(FileAccess.file_exists(SaveManager.home_dir().path_join("home.json")), "(there)")
	eq(str(HomeStore.load_home().address.text), ADDRESS, "your address is kept there, on this PC")
	# Walking: from your room to the front door, through doors (the walls stop you elsewhere).
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.start_game()
	await frames(3)
	var g: Node = main.game
	g.load_room(entry)
	await frames(2)
	var mr := HomePlaces.mine_rect(up)
	var bed: Array = (up.objects as Array).filter(func(o): return str(o.get("model", "")) == "bed")
	check(not bed.is_empty(), "your bed is there")
	var from: Vector2i = g.room.nav.nearest_walkable(mr.get_center())
	check(mr.has_point(from), "you can stand in your room")
	var stairs: Dictionary = st_up[0] if not st_up.is_empty() else {}
	var to: Vector2i = g.room.nav.best_neighbor(Vector2i(int(stairs.pos[0]), int(stairs.pos[2])), from) if not stairs.is_empty() else from
	check(to.x >= 0, "there's a spot beside the stairs")
	var path: Array = g.room.nav.path(from, to)
	check(not path.is_empty() or from == to, "a way from your room to the stairs")
	var door_cells := 0
	for e in up.edge_walls:
		if bool(e.door) and not bool(e.outer):
			door_cells += 1
	check(door_cells >= 3, "doors between the rooms upstairs (%d)" % door_cells)
	# A wall of your room that isn't a door: you can't step straight through it.
	var tested := false
	for e in up.edge_walls:
		if bool(e.door) or bool(e.outer):
			continue
		var a := Vector2i(int(e.x), int(e.z))
		var b := Vector2i(int(e.x), int(e.z) - 1) if str(e.dir) == "h" else Vector2i(int(e.x) - 1, int(e.z))
		if not (mr.has_point(a) or mr.has_point(b)):
			continue
		check(g.room.nav.blocked_between(a, b), "a wall stops you between rooms")
		if g.room.nav.walkable(a) and g.room.nav.walkable(b):
			var around: Array = g.room.nav.path(a, b)
			check(around.is_empty() or around.size() > 1, "no stepping through it: the way round is longer (%d)" % around.size())
		tested = true
	check(tested, "found a wall of your room to try")
	check(g.room.edge_wall_count() > 10, "thin walls drawn (%d)" % g.room.edge_wall_count())
	main.queue_free()
	await frames(2)


func _press(screen: Control, name_or_text: String) -> bool:
	for b in screen.find_children("*", "Button", true, false):
		if is_instance_valid(b) and b.is_visible_in_tree() and (str(b.name) == name_or_text or (b as Button).text.begins_with(name_or_text)):
			(b as Button).pressed.emit()
			return true
	return false


## Taps through the Survey: every line finished and advanced, each question answered with its first
## option (or skipped), up to the helper and consent screens.
func _drive_survey(screen: Control, until_kind: String) -> void:
	for _i in 400:
		if screen.finished:
			return
		var s: Dictionary = screen.step()
		if str(s.get("kind", "")) == until_kind and not screen._typing and screen._area.get_child_count() > 0:
			return
		if screen._typing or screen._waiting_tap:
			screen._tap()
			await frames(1)
			continue
		match str(s.get("kind", "")):
			"text":
				if str(s.key) == "address":
					screen.field.text = ADDRESS
					screen._submit_text(ADDRESS)
				else:
					screen._skip_step()
			"counts":
				_press(screen, "THAT'S ALL")
			"choice", "picture", "color", "helper":
				var buttons: Array = screen._area.find_children("*", "Button", true, false)
				if not buttons.is_empty():
					(buttons[0] as Button).pressed.emit()
				else:
					screen._skip_step()
			_:
				pass
		await frames(1)


func _boot_world() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)


func test_no_helper_everything_still_works() -> void:
	await _boot_world()
	GameState.settings["reduce_motion"] = true
	var mapper := HomeMapper.new()
	main.add_child(mapper)
	mapper.available_override = {"none": true}
	var job := func() -> String: return await mapper.run(main)
	var result := {"entry": ""}
	var run := func() -> void: result.entry = await job.call()
	run.call()
	await frames(2)
	await _drive_survey(mapper.screen, "consent")
	# With nobody to look, the last screen only asks about the map of your streets: just the answers.
	if is_instance_valid(mapper.screen) and str(mapper.screen.step().get("kind", "")) == "consent":
		var consent: Label = mapper.screen.find_child("ConsentText", true, false)
		check(consent != null and not consent.text.contains("Anthropic"), "no helper on the last screen")
		_press(mapper.screen, "JustMyAnswers")
	var t := Time.get_ticks_msec()
	while str(result.entry) == "" and Time.get_ticks_msec() - t < 15000:
		_accept_home_preview(mapper)
		if is_instance_valid(mapper.screen) and (mapper.screen._typing or mapper.screen._waiting_tap):
			mapper.screen._tap()
		await frames(2)
	eq(str(mapper.last_result.get("choice", "")), "answers", "with nobody to look, the answers do")
	eq(str(mapper.last_result.get("helper", "")), "none")
	check(str(result.entry) != "" and SaveManager.room_exists(str(result.entry)), "the house was built")
	check(not mapper.has_node("Research") and mapper.research == null, "no helper was ever started")
	check(HomeStore.exists(), "home.json saved")
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func test_nothing_is_sent_before_look_it_up() -> void:
	await _boot_world()
	GameState.settings["reduce_motion"] = true
	var mapper := HomeMapper.new()
	main.add_child(mapper)
	mapper.available_override = {"claude_code": true, "none": true}
	mapper.recorded = ProjectSettings.globalize_path(FIXTURE)
	var result := {"entry": ""}
	var run := func() -> void: result.entry = await mapper.run(main)
	run.call()
	await frames(2)
	await _drive_survey(mapper.screen, "consent")
	var sc: Control = mapper.screen
	eq(str(sc.step().get("kind", "")), "consent", "the last screen asks first")
	eq(sc.helper, "claude_code", "the helper picked")
	check(mapper.research == null, "nothing started yet")
	var consent: Label = sc.find_child("ConsentText", true, false)
	check(consent != null and consent.text.contains(ADDRESS), "it shows the exact address it would send")
	check(consent != null and consent.text.contains("Anthropic"), "and to whom")
	check(consent != null and not consent.text.contains("Pancakes"), "(your memories aren't part of it)")
	# Go back, then come forward again: still nothing sent.
	_press(sc, "GO BACK")
	await frames(2)
	await _drive_survey(sc, "consent")
	check(mapper.research == null, "going back sends nothing")
	check(_press(sc, "LookItUp"), "LOOK IT UP")
	var t := Time.get_ticks_msec()
	var saw_research := false
	while str(result.entry) == "" and Time.get_ticks_msec() - t < 20000:
		_accept_home_preview(mapper)
		if mapper.research != null:
			saw_research = true
		await frames(2)
	check(saw_research, "only now does the helper start")
	eq(str(mapper.last_result.get("choice", "")), "lookup")
	var home := HomeStore.load_home()
	eq(str(home.get("helper", "")), "claude_code")
	check((home.sources as Array).any(func(s): return str(s.id) == "assessor"), "what it found is in the home")
	check(HomeStore.last_research().has("facts"), "and its answer saved in my_home/research")
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func test_leaving_the_survey_gives_the_plain_room() -> void:
	await _boot_world()
	GameState.settings["reduce_motion"] = true
	var mapper := HomeMapper.new()
	main.add_child(mapper)
	mapper.available_override = {"none": true}
	var result := {"entry": ""}
	var run := func() -> void: result.entry = await mapper.run(main)
	run.call()
	await frames(4)
	check(_press(mapper.screen, "LEAVE"), "LEAVE")
	var t := Time.get_ticks_msec()
	while str(result.entry) == "" and Time.get_ticks_msec() - t < 8000:
		await frames(2)
	eq(str(result.entry), Realms.ENTRY, "the plain room")
	check(not HomeStore.exists(), "nothing kept about a home you didn't describe")
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func test_no_key_or_address_in_any_log() -> void:
	await _boot_world()
	GameState.settings["light_world"] = {"helper": "claude_api", "claude_api_key": FAKE_KEY}
	SaveManager.save_settings(GameState.settings)
	GameState.settings["reduce_motion"] = true
	var mapper := HomeMapper.new()
	main.add_child(mapper)
	mapper.available_override = {"claude_api": true, "none": true}
	mapper.recorded = ProjectSettings.globalize_path(FIXTURE)
	var result := {"entry": ""}
	var run := func() -> void: result.entry = await mapper.run(main)
	run.call()
	await frames(2)
	await _drive_survey(mapper.screen, "consent")
	_press(mapper.screen, "LookItUp")
	var t := Time.get_ticks_msec()
	while str(result.entry) == "" and Time.get_ticks_msec() - t < 20000:
		_accept_home_preview(mapper)
		await frames(2)
	check(str(result.entry) != "", "built")
	# Every file under the save root, except settings.json (the key's home) and my_home (your address's).
	var leaks: Array = []
	_scan(SaveManager.root, "", leaks)
	eq(leaks, [], "no key or address anywhere else")
	GameState.settings["reduce_motion"] = false
	GameState.settings.erase("light_world")
	main.queue_free()
	await frames(2)


func _accept_home_preview(mapper: Node) -> void:
	if is_instance_valid(mapper.screen):
		_press(mapper.screen, "KeepHomePreview")


func _scan(root: String, rel: String, leaks: Array) -> void:
	var d := root.path_join(rel)
	for f in DirAccess.get_files_at(d):
		var r := rel.path_join(f) if rel != "" else f
		if r == "settings.json" or r.begins_with("settings.json") or r.begins_with("my_home"):
			continue
		if f.get_extension() in ["png", "jpg", "zip", "wav", "ogg"]:
			continue
		var text := FileAccess.get_file_as_string(d.path_join(f))
		if text.contains(FAKE_KEY) or text.contains("Example Lane"):
			leaks.append(r)
	for sub in DirAccess.get_directories_at(d):
		var r2 := rel.path_join(sub) if rel != "" else sub
		if r2.begins_with("my_home"):
			continue
		_scan(root, r2, leaks)


func test_helpers_are_found_without_calling_anything() -> void:
	var av := Research.available()
	check(av.has("claude_code") and av.has("claude_api") and av.has("gemini") and bool(av.none), "every helper has an answer")
	var p := Research.claude_code_path()
	check(p == "" or FileAccess.file_exists(p), "Claude Code, if found, is a real file")
	var q := ResearchQuestion.make()
	check(q.contains("assessor") and q.contains("permit") and q.contains("plat") and q.contains("Wayback"), "the detective's list")
	check(q.contains("Never include names of owners"), "building facts only")
	check(q.contains("no logins") and q.contains("CAPTCHA"), "no workarounds")
	check(not q.contains("Pancakes"), "nothing personal")


class ResearchQuestion:
	static func make() -> String:
		var a := {"address": ADDRESS, "memory": "Pancakes every Sunday", "floors": 2, "rooms": {"bedroom": 3}}
		return preload("res://scripts/home/research_prompt.gd").question(ADDRESS, preload("res://scripts/home/survey_data.gd").building_answers(a))


func test_the_first_trip_home_starts_the_survey() -> void:
	await _boot_world()
	GameState.settings["reduce_motion"] = true
	var g: Node = main.game
	check(LightHome.entry_id() == "", "no Light World yet")
	var gate: Dictionary = Realms.gate_of(g.room.data)
	g.dark.use_gate(gate)
	await frames(2)
	var chose := false
	for p in main.panels:
		if is_instance_valid(p) and p.has_method("ask"):
			for b in p.buttons:
				if (b as Button).text == "Go home":
					(b as Button).pressed.emit()
					chose = true
	check(chose, "Go home")
	await frames(4)
	var survey: Control = null
	for c in main.toast_layer().get_children():
		if c.get_script() == SurveyScreen:
			survey = c
	check(survey != null, "the screen goes black: the Survey")
	if survey:
		check(_press(survey, "LEAVE"), "LEAVE")
	var t := Time.get_ticks_msec()
	while g.dark.busy or GameState.current_room_id != Realms.ENTRY:
		if Time.get_ticks_msec() - t > 15000:
			break
		await frames(2)
	eq(GameState.current_room_id, Realms.ENTRY, "then home, to the plain room")
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func test_the_memory_book_tells_the_home_story_without_copying_it() -> void:
	await _boot_world()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	HomeMapper.build_home(_answers(), HomeModel.clean_research(raw), "recorded")
	var before := JSON.stringify(GameState.journal)
	var mb: Control = load("res://scripts/ui/memory_book.gd").new()
	main.open_panel(mb)
	await frames(2)
	var pages: Array = mb.find_children("HomePage_*", "PanelContainer", true, false)
	check(pages.size() >= 5, "pages from the home's history (%d)" % pages.size())
	var text := ""
	for p in pages:
		for l in p.find_children("*", "Label", true, false):
			text += (l as Label).text + " "
	check(text.contains("1962"), "built in 1962")
	check(text.contains("deck"), "the deck")
	check(text.contains("Pancakes"), "your memory")
	eq(JSON.stringify(GameState.journal), before, "nothing copied into the world's journal")
	main.queue_free()
	await frames(2)


func test_editing_the_house_and_undo_puts_it_back_exactly() -> void:
	await _boot_world()
	HomeMapper.build_home(_answers(), {}, "")
	var g: Node = main.game
	var panel: Control = load("res://scripts/home/map_home_panel.gd").new()
	main.open_panel(panel)
	panel.setup_home(g)
	await frames(2)
	var original := JSON.stringify(HomeStore.load_home().plan)
	var up: Dictionary = HomeEdit_floor(1)
	var mine := -1
	var other := -1
	for i in (up.rooms as Array).size():
		if bool(up.rooms[i].get("mine", false)):
			mine = i
		elif str(up.rooms[i].kind) == "bedroom" and other < 0:
			other = i
	panel.sketch.level = 1
	check(panel.edit({"type": "rename", "level": 1, "room": str(up.rooms[other].id), "name": "Studio"}), "renamed")
	check(panel.edit({"type": "wall", "level": 1, "room": str(up.rooms[mine].id), "color": "#b5cfa8"}), "painted")
	var inner: Dictionary = {}
	for e in up.edges:
		if not bool(e.outer) and not bool(e.door):
			inner = e
			break
	check(panel.edit({"type": "edge", "level": 1, "x": int(inner.x), "z": int(inner.z), "dir": str(inner.dir), "to": "door"}), "a wall became a door")
	var now := HomeEdit_floor(1)
	check((now.rooms as Array).any(func(r): return str(r.name) == "Studio"), "the new name is in the plan")
	eq(str(now.rooms[mine].wall), "#b5cfa8", "the new paint")
	var places_wall := false
	for e in SaveManager.load_room(HomePlaces.place_id(1)).edge_walls:
		if str(e.get("color_a", "")) == "#b5cfa8" or str(e.get("color_b", "")) == "#b5cfa8":
			places_wall = true
	check(places_wall, "and in the Light World's place")
	var tl: Array = HomeStore.load_home().timeline
	check(tl.filter(func(t): return str(t.get("source", "")) == "editor").size() >= 3, "each change on the timeline")
	panel.undo()
	panel.undo()
	panel.undo()
	eq(JSON.stringify(HomeStore.load_home().plan), original, "three undos: exactly as it was")
	main.queue_free()
	await frames(2)


func HomeEdit_floor(level: int) -> Dictionary:
	for f in HomeStore.load_home().plan.floors:
		if int(f.level) == level:
			return f
	return {}


## Claude Code's stream (recorded from the real program's format): searches become progress lines,
## the structured answer is read and cleaned; an expired sign-in says so plainly.
func test_claude_code_answers_are_read_from_its_stream() -> void:
	var lines := []
	var done := []
	var r: Node = Research.new()
	tree.root.add_child(r)
	r.progress.connect(func(l): lines.append(l))
	r.helper = "claude_code"
	for line in FileAccess.get_file_as_string("res://tests/fixtures/claude_code_success.jsonl").split("\n", false):
		r._on_event(line)
	done.append(r._finish_claude_code())
	check(lines.has("Reading the county assessor's record..."), "the assessor search shows as progress")
	check(lines.has("Looking through building permits..."), "and the permits")
	check(lines.has("Reading an archived page..."), "and the archived listing")
	eq(done.size(), 1)
	if done.size() == 1:
		check(bool(done[0].ok), "the answer is read")
		check((done[0].research.facts as Array).size() >= 5, "with its facts")
		check(not JSON.stringify(done[0].research).contains("Jane"), "cleaned of names")
	done.clear()
	r._result_text = ""
	r._structured = null
	for line in FileAccess.get_file_as_string("res://tests/fixtures/claude_code_auth_error.jsonl").split("\n", false):
		r._on_event(line)
	done.append(r._finish_claude_code())
	eq(done.size(), 1)
	if done.size() == 1:
		check(not bool(done[0].ok), "an expired sign-in is a failure")
		check(str(done[0].error).contains("isn't signed in"), "said plainly: %s" % str(done[0].error))
	r.queue_free()
