extends "res://tests/test_case.gd"
## Phase 31, your home keeps growing: Tell Polox about home in your own words (offline, and with a
## recorded helper reading), a preview before anything changes, Keep / Adjust / Undo; your own edits kept
## when you tell it more and when it's mapped again, Undo restoring the house exactly; "Things Polox isn't
## sure about" (answering changes the house and the question goes; dismissing; nothing asks unprompted);
## the home's timeline with undo for any change; Look again showing only what's new.

const TellPolox := preload("res://scripts/home/tell_polox.gd")
const OpenQuestions := preload("res://scripts/home/open_questions.gd")
const LookAgain := preload("res://scripts/home/look_again.gd")
const HomeEdit := preload("res://scripts/home/home_edit.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const Realms := preload("res://scripts/world/realms.gd")
const LightHome := preload("res://scripts/world/light_home.gd")

const FIXTURE := "res://tests/fixtures/home_research_madeup.json"
const LATER := "res://tests/fixtures/home_research_madeup_later.json"

var main: Node


func _answers() -> Dictionary:
	return {"address": "12 Example Lane, Testville", "home_type": "house", "floors": 2,
		"rooms": {"bedroom": 3, "bathroom": 2, "kitchen": 1, "living": 1, "dining": 1, "laundry": 1},
		"entry_room": "hall", "my_room": {"floor": 1, "where": "front", "desk": true}}


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _shutdown() -> void:
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func _plan() -> Dictionary:
	return HomeStore.load_home().get("plan", {})


func _room(plan: Dictionary, pred: Callable) -> Dictionary:
	for f in plan.floors:
		for r in f.rooms:
			if pred.call(r):
				return r
	return {}


func test_reading_your_own_words() -> void:
	var plan: Dictionary = load("res://scripts/home/layout_builder.gd").build(_answers())
	var p := TellPolox.read("We painted my room green last summer. The hallway has a blue runner and our family photos.", plan)
	var types: Array = (p.changes as Array).map(func(e): return str(e.type))
	check("wall" in types, "the paint")
	var wall: Array = (p.changes as Array).filter(func(e): return str(e.type) == "wall")
	if not wall.is_empty():
		eq(str(wall[0].room_name), "My room")
		eq(str(wall[0].color), TellPolox.COLORS.green)
	var adds: Array = (p.changes as Array).filter(func(e): return str(e.type) == "add")
	check(adds.any(func(e): return str(e.model) == "runner" and str(e.color) == TellPolox.COLORS.blue), "a blue runner")
	check(adds.any(func(e): return str(e.model) == "picture" and int(e.count) >= 2), "family photos")
	check(adds.all(func(e): return str(e.room_name).begins_with("Hallway")), "in the hallway (%s)" % str(adds.map(func(e): return e.room_name)))
	var q := TellPolox.read("My room used to be the playroom", plan)
	eq((q.changes as Array).size(), 1)
	if not (q.changes as Array).is_empty():
		eq(str(q.changes[0].type), "used_to_be")
		eq(str(q.changes[0].was), "the playroom")
	var n := TellPolox.read("The kitchen floor is tiled and the kitchen door sticks", plan)
	check((n.changes as Array).any(func(e): return str(e.type) == "floor" and str(e.floor) == "tile"), "the tiles")
	var u := TellPolox.read("There's a piano somewhere", plan)
	eq((u.changes as Array).size(), 0, "no room: nothing changes...")
	eq((u.unsure as Array).size(), 1, "...it asks which room")
	var gone := TellPolox.read("We got rid of the sofa in the living room", plan)
	check((gone.changes as Array).any(func(e): return str(e.type) == "remove" and str(e.model) == "sofa"), "things that went")


func test_telling_it_keeps_your_edits_and_undo_is_exact() -> void:
	await _boot()
	HomeMapper.build_home(_answers(), {}, "")
	var mine := _room(_plan(), func(r): return bool(r.get("mine", false)))
	var bed2 := _room(_plan(), func(r): return str(r.name) == "Bedroom 1")
	# An edit by hand first (the sketch): rename a bedroom.
	check(not HomeEdit.commit([{"type": "rename", "level": 1, "room": str(bed2.id), "name": "Studio"}], "editor").is_empty(), "renamed by hand")
	var before := JSON.stringify(_plan())
	var g: Node = main.game
	var panel: Control = load("res://scripts/home/tell_polox_panel.gd").new()
	main.open_panel(panel)
	panel.setup_tell(g, "We painted my room green. The hallway has a blue runner.")
	await frames(2)
	var shown: Array = panel.preview.find_children("Change*", "Label", true, false)
	check(shown.size() >= 2, "a preview of the changes (%d)" % shown.size())
	eq(JSON.stringify(_plan()), before, "nothing changed yet")
	panel.keep()
	var after := _plan()
	var applied_once := JSON.stringify(HomeStore.load_home())
	panel.keep()
	eq(JSON.stringify(HomeStore.load_home()), applied_once, "duplicate Keep cannot apply a second batch")
	var mine2 := _room(after, func(r): return bool(r.get("mine", false)))
	eq(str(mine2.wall), TellPolox.COLORS.green, "your room is green")
	check(_room(after, func(r): return str(r.name) == "Studio") != {}, "your own edit is kept")
	var runner_level := -9
	for f in after.floors:
		if (f.furniture as Array).any(func(p): return str(p.model) == "runner" and bool(p.get("user", false))):
			runner_level = int(f.level)
	check(runner_level != -9, "the runner is in (a hallway)")
	var place := SaveManager.load_room(HomePlaces.place_id(runner_level if runner_level != -9 else 0))
	check((place.objects as Array).any(func(o): return str(o.get("model", "")) == "runner"), "and in the Light World")
	panel.undo()
	eq(JSON.stringify(_plan()), before, "Undo: exactly the house before")
	check(_room(_plan(), func(r): return str(r.name) == "Studio") != {}, "your earlier edit still there")
	# Mapped again: your edits stay on top.
	panel.text_box.text = "We painted my room green."
	panel.read_it()
	check(not HomeEdit.commit([{"type": "note", "level": 1, "room": str(bed2.id), "text": "A newer correction."}], "editor").is_empty(), "concurrent edit after preview")
	var newer := JSON.stringify(HomeStore.load_home())
	panel.keep()
	eq(JSON.stringify(HomeStore.load_home()), newer, "stale preview cannot overwrite a newer correction")
	panel.read_it()
	panel.keep()
	HomeMapper.build_home(_answers(), {}, "")
	check(_room(_plan(), func(r): return str(r.name) == "Studio") != {}, "mapped again: the rename stays")
	eq(str(_room(_plan(), func(r): return bool(r.get("mine", false))).wall), TellPolox.COLORS.green, "and the paint")
	await _shutdown()


func test_any_change_on_the_timeline_can_be_undone() -> void:
	await _boot()
	HomeMapper.build_home(_answers(), {}, "")
	var mine := _room(_plan(), func(r): return bool(r.get("mine", false)))
	var kitchen := _room(_plan(), func(r): return str(r.kind) == "kitchen")
	var a := HomeEdit.commit([{"type": "wall", "level": 1, "room": str(mine.id), "color": "#e8bfc4"}], "editor")
	var b := HomeEdit.commit([{"type": "floor", "level": 0, "room": str(kitchen.id), "floor": "wood"}], "words")
	check(not a.is_empty() and not b.is_empty(), "two changes")
	check(HomeEdit.undo(str(a.batch)), "undo the older one")
	var plan := _plan()
	check(str(_room(plan, func(r): return bool(r.get("mine", false))).wall) != "#e8bfc4", "the paint is gone")
	eq(str(_room(plan, func(r): return str(r.kind) == "kitchen").floor), "wood", "the newer change stays")
	var tl: Array = HomeStore.load_home().timeline
	check(not tl.any(func(t): return str(t.get("batch", "")) == str(a.batch)), "and off the timeline")
	await _shutdown()


func test_manual_ai_response_uses_preview_keep_and_undo_without_credentials() -> void:
	await _boot()
	HomeMapper.build_home(_answers(), {}, "")
	var before := JSON.stringify(_plan())
	var panel: Control = load("res://scripts/home/tell_polox_panel.gd").new()
	main.open_panel(panel)
	panel.setup_tell(main.game, "We painted my room blue.")
	panel._manual_helper()
	await frames(2)
	var manual: Control = main.panels[-1]
	check(manual.prompt_box.text.contains("request_id"), "exact schema and request shown for payload review")
	var request: Dictionary = manual.request
	manual.response_box.text = JSON.stringify({"schema_version": 1, "request_id": request.request_id, "base_revision": request.base_revision, "task": "words", "result": {"changes": [{"type": "wall", "room": "my room", "color": "blue"}], "questions": []}})
	manual.preview_response()
	await frames(2)
	eq(JSON.stringify(_plan()), before, "pasting only prepares a preview")
	check(panel.proposal.changes.size() == 1, "validated response enters normal preview")
	panel.keep()
	eq(str(_room(_plan(), func(r): return bool(r.get("mine", false))).wall), TellPolox.COLORS.blue, "Keep applies imported proposal")
	panel.undo()
	eq(JSON.stringify(_plan()), before, "Undo restores the prior layout")
	await _shutdown()


func test_open_questions_change_the_house_and_never_nag() -> void:
	var g: Node = await _boot()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	HomeMapper.build_home(_answers(), HomeModel.clean_research(raw), "recorded")
	var home := HomeStore.load_home()
	OpenQuestions.generate(home)
	HomeStore.save_home(home)
	var open := OpenQuestions.open_list(HomeStore.load_home())
	check(open.size() >= 3, "a few things Polox isn't sure about (%d)" % open.size())
	check(open.any(func(q): return str(q.get("source", "")) == "research"), "from the research")
	var wall_q: Array = open.filter(func(q): return str(q.get("kind", "")) == "color" and str(q.room_name) == "Kitchen")
	check(not wall_q.is_empty(), "the kitchen walls")
	if not wall_q.is_empty():
		var res := OpenQuestions.answer(str(wall_q[0].id), "#b5cfa8")
		check(not res.is_empty(), "answered")
		eq(str(_room(_plan(), func(r): return str(r.kind) == "kitchen").wall), "#b5cfa8", "the kitchen is green now")
		check(not OpenQuestions.open_list(HomeStore.load_home()).any(func(q): return str(q.id) == str(wall_q[0].id)), "and the question is gone")
	var back: Array = OpenQuestions.open_list(HomeStore.load_home()).filter(func(q): return str(q.id) == "h_back_door")
	if not back.is_empty():
		OpenQuestions.answer("h_back_door", true)
		var ground: Dictionary = HomeEdit.floor_of(_plan(), 0)
		check((ground.edges as Array).any(func(e): return bool(e.door) and bool(e.outer) and int(e.z) == 0), "a back door")
	var free: Array = OpenQuestions.open_list(HomeStore.load_home()).filter(func(q): return str(q.get("source", "")) == "research")
	if not free.is_empty():
		OpenQuestions.dismiss(str(free[0].id))
		check(not OpenQuestions.open_list(HomeStore.load_home()).any(func(q): return str(q.id) == str(free[0].id)), "dismissed")
	# Going home with questions still open: nothing asks you anything.
	GameState.settings["reduce_motion"] = true
	var panels_before: int = main.panels.size()
	var toasts_before: int = main.toast_layer().get_child_count()
	await g.dark.go_light()
	await frames(10)
	eq(main.panels.size(), panels_before, "no panel pops up")
	var asked := false
	for c in main.toast_layer().get_children():
		for l in c.find_children("*", "Label", true, false):
			if (l as Label).text.contains("?") and (l as Label).text.to_lower().contains("polox"):
				asked = true
	check(not asked, "no question in a toast either")
	await _shutdown()


func test_look_again_shows_only_whats_new() -> void:
	await _boot()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var first := HomeModel.clean_research(raw)
	HomeMapper.build_home(_answers(), first, "recorded")
	HomeStore.save_research(first)
	var later := HomeModel.clean_research(JSON.parse_string(FileAccess.get_file_as_string(LATER)))
	var d := LookAgain.diff(HomeStore.last_research(), later)
	eq((d.permits as Array).size(), 1, "one new permit")
	eq((d.sources as Array).size(), 1, "one new source")
	eq((d.neighbourhood as Array).size(), 1, "one new place nearby")
	eq((d.facts as Array).size(), 0, "no fact changed (same bathrooms, different listing)")
	check((d.lines as Array).any(func(l): return str(l).contains("fence")), "said in a line: the fence")
	check(LookAgain.diff(first, first).lines.is_empty(), "the same answer twice: nothing new")
	LookAgain.keep(later, d)
	var tl: Array = HomeStore.load_home().timeline
	check(tl.any(func(t): return str(t.kind) == "permit" and int(t.year) == 2024), "the new permit is in the home's history")
	check((HomeStore.load_home().neighbourhood as Array).any(func(n): return str(n.name) == "Corner Cafe"), "the cafe nearby")
	check(LookAgain.diff(HomeStore.last_research(), later).lines.is_empty(), "looking again right after: nothing new")
	await _shutdown()


func test_a_helper_can_read_your_words_when_you_ask() -> void:
	var plan: Dictionary = load("res://scripts/home/layout_builder.gd").build(_answers())
	var raw := {"changes": [{"type": "wall", "room": "my room", "color": "sage"}, {"type": "add", "room": "Living room", "model": "piano", "count": 1},
		{"type": "add", "room": "Garage", "model": "car"}, {"type": "add", "room": "Kitchen", "model": "spaceship"}],
		"questions": ["Is the piano upright or grand?"]}
	var p := TellPolox.clean_helper(raw, plan)
	check((p.changes as Array).any(func(e): return str(e.type) == "wall" and str(e.color) == TellPolox.COLORS.sage), "the paint, matched to your room")
	check((p.changes as Array).any(func(e): return str(e.type) == "add" and str(e.model) == "piano"), "the piano")
	check(not (p.changes as Array).any(func(e): return str(e.get("model", "")) == "spaceship"), "only pieces Polox can draw")
	check((p.unsure as Array).any(func(q): return str(q.text).contains("Garage")), "a room you don't have becomes a question")
	check((p.unsure as Array).any(func(q): return str(q.text).contains("upright")), "and its own question")
	var prompt := TellPolox.words_prompt("my room is sage", plan, false)
	check(not prompt.contains("Example Lane"), "the address is never part of it")


func test_reminders_only_when_you_turn_them_on() -> void:
	var g: Node = await _boot()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	HomeMapper.build_home(_answers(), HomeModel.clean_research(raw), "recorded")
	var notes := []
	GameState.notified.connect(func(t): notes.append(str(t))) if GameState.has_signal("notified") else null
	g.light_life.on_room_loaded(SaveManager.load_room(LightHome.entry_id()))
	var lw: Dictionary = GameState.settings.get("light_world", {}) if GameState.settings.get("light_world") is Dictionary else {}
	check(str(lw.get("last_reminder", "")) == "", "reminders off: nothing said")
	lw["question_reminders"] = true
	GameState.settings["light_world"] = lw
	g.light_life.on_room_loaded(SaveManager.load_room(LightHome.entry_id()))
	eq(str(GameState.settings.light_world.get("last_reminder", "")), Time.get_date_string_from_system(), "on: one gentle line today")
	GameState.settings.erase("light_world")
	await _shutdown()


func test_wall_pictures_and_house_notes() -> void:
	var plan: Dictionary = load("res://scripts/home/layout_builder.gd").build(_answers())
	var hall := {}
	for f in plan.floors:
		for r in f.rooms:
			if str(r.kind) == "hall" and int(f.level) == 0:
				hall = r
	check(HomeEdit.apply(plan, {"type": "add", "level": 0, "room": str(hall.id), "model": "picture", "count": 3}), "three pictures hung")
	var pics := (HomeEdit.floor_of(plan, 0).furniture as Array).filter(func(p): return str(p.model) == "picture")
	eq(pics.size(), 3)
	check(not load("res://scripts/world/furniture.gd").blocks("picture"), "pictures don't block the way")
	check(HomeEdit.apply(plan, {"type": "note", "level": 0, "room": "", "text": "The back door sticks"}), "a note about the house itself")
	check((plan.get("notes", []) as Array).has("The back door sticks"))
