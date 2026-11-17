extends "res://tests/test_case.gd"
## How the Light World's layout is made, as its player drew it (1.29): a prompt goes to an AI; the prompt
## says how the game works, how the house gets built and which tools to use; the AI finds out when the home
## was built, its colours, its street and what listing sites say; what it found lives as files in the
## home's Info folder, which the game reads; and the house is built from it, in those colours, with your
## own answers still winning. The data folder says where each layout is. Made-up homes, recorded answers.

const ResearchPrompt := preload("res://scripts/home/research_prompt.gd")
const Request := preload("res://scripts/home/helper_request.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const HomeLook := preload("res://scripts/home/home_look.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HoodBuilder := preload("res://scripts/home/hood_builder.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const Osm := preload("res://scripts/home/osm.gd")
const PersonalData := preload("res://scripts/core/personal_data.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const ManualPanel := preload("res://scripts/home/helper_manual_panel.gd")
const LookAgain := preload("res://scripts/home/look_again.gd")

const ADDRESS := "12 Example Lane, Testville"
const RESEARCH := "res://tests/fixtures/home_research_madeup.json"
const TOWN := "res://tests/fixtures/osm_madeup_town.json"


func _answers() -> Dictionary:
	return {"address": ADDRESS, "home_type": "house", "floors": 2, "radius": 250,
		"rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1}, "my_room": {"floor": 1}}


## The made-up research answer, with what a listing's photos and a street-level photo would add.
func _found() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RESEARCH))
	(raw.facts as Array).append_array([
		{"key": "exterior_color", "value": "Light blue siding with white trim", "source": "listing2019", "confidence": 0.8},
		{"key": "roof_color", "value": "charcoal", "source": "listing2019", "confidence": 0.7},
		{"key": "door_color", "value": "red", "source": "listing2019", "confidence": 0.6},
		{"key": "roof", "value": "hip roof", "source": "assessor", "confidence": 0.7},
	])
	for room in raw.rooms:
		if str(room.kind) == "living":
			room["wall_color"] = "sage green"
			room["floor_material"] = "Hardwood"
		if str(room.kind) == "kitchen":
			room["wall_color"] = "no idea"          # not a colour: left out, the room keeps its default
			room["floor_material"] = "ceramic tile"
	return HomeModel.clean_research(raw)


func _room(plan: Dictionary, kind: String) -> Dictionary:
	for f in plan.floors:
		for r in f.rooms:
			if str(r.kind) == kind:
				return r
	return {}


func test_the_prompt_explains_the_game_the_building_and_the_tools() -> void:
	var q := ResearchPrompt.question(ADDRESS, {"floors": 2})
	var at := -1
	for heading in ["HOW THE GAME WORKS", "HOW THE HOUSE GETS BUILT", "WHAT TOOLS TO USE", "WHAT TO FIND OUT", "Rules you must follow"]:
		check(q.find(heading) > at, "the prompt has \"%s\", in that order" % heading)
		at = q.find(heading)
	for said in ["one cell is one metre", "You don't draw anything", "web search tool", "page-reading tool", "Zillow", "Redfin",
		"Wayback Machine", "Street View", "OpenStreetMap", "When it was built", "Its colours", "Its street", "Listing information",
		"exterior_color", "roof_color", "door_color", "wall_color", "floor_material"]:
		check(q.contains(said), "it says: " + said)
	check(q.contains("Never include names of owners") and q.contains("no logins") and q.contains("Leave prices out"),
		"and still keeps people, prices and sites' terms out of it")
	fresh_save_root()
	HomeMapper.build_home(_answers(), {}, "")
	var request := Request.create("research", {"location": ADDRESS, "known": {"floors": 2}})
	var p := Request.prompt(request)
	check(p.contains("HOW TO ANSWER") and p.contains("prompt.txt") and p.contains("answer.json"), "an AI that works with files is told where its answer goes")
	check(p.contains("wall_color") and p.contains("floor_material"), "the answer's fields list a room's paint and floor")
	# What the prompt asks for passes the check the answer goes through.
	eq(ResearchPrompt.validate_response(_found()), "", "an answer with colours, a roof and painted rooms is a valid answer")


func test_colour_words_become_colours() -> void:
	eq(HomeLook.colour("Light grey vinyl siding with white trim"), HomeLook.NAMES["light grey"], "the colour named first, in full")
	eq(HomeLook.colour("dark green"), HomeLook.NAMES["dark green"], "not just green")
	eq(HomeLook.colour("Red brick"), HomeLook.NAMES["red brick"])
	eq(HomeLook.colour("blue-grey shingles"), HomeLook.NAMES["blue grey"], "a hyphen is a space")
	eq(HomeLook.colour("#A8C0D8"), "#a8c0d8", "a hex colour as it is")
	eq(HomeLook.colour("two storeys, vinyl siding"), "", "no colour named, none invented")
	eq(HomeLook.roof_shape("Hip roof, asphalt shingles"), "hipped")
	eq(HomeLook.roof_shape("composition"), "")
	eq(HomeLook.floor_material("Hardwood floors"), "wood")
	eq(HomeLook.floor_material("ceramic tile"), "tile")
	var look := HomeLook.of({"facts": [
		{"key": "exterior_color", "value": "sage green", "confidence": 0.5}, {"key": "exterior_color", "value": "beige stucco", "confidence": 0.9},
		{"key": "roof", "value": "hipped, dark grey shingles", "confidence": 0.8}, {"key": "door_color", "value": "red", "confidence": 0.7}]})
	eq(str(look.wall), HomeLook.NAMES["beige"], "the surest fact wins")
	eq(str(look.roof_shape), "hipped")
	eq(str(look.roof), HomeLook.NAMES["dark grey"], "a roof fact can say its colour too")
	eq(str(look.door), HomeLook.NAMES["red"])
	check(HomeLook.of({"facts": [{"key": "exterior_color", "value": "vinyl siding", "confidence": 0.9}]}).is_empty(), "a fact that names no colour changes nothing")
	check(HomeLook.of({}).is_empty(), "a home without facts keeps Polox's own colours")
	# Storeys: the floors the house has, cellar not counted; a height the map measured is left alone.
	var tall := HomeLook.of({"plan": {"floors": [{"level": -1}, {"level": 0}, {"level": 1}, {"level": 2}]}})
	eq(int(tall.levels), 3)
	var street := {"buildings": [{"kind": "mine", "levels": 1, "h": 2.5, "wall": "#fff", "roof": "#000"}, {"kind": "home", "levels": 1, "h": 2.5},
		{"kind": "mine", "levels": 1, "h": 4.4, "wall": "#fff", "roof": "#000"}]}
	check(HomeLook.apply_to_street(street, tall), "the street changes")
	eq(int(street.buildings[0].levels), 3)
	check(is_equal_approx(float(street.buildings[0].h), 1.6 + 0.9 * 3), "three storeys tall")
	eq(int(street.buildings[1].levels), 1, "a neighbour's house is never touched")
	eq(float(street.buildings[2].h), 4.4, "a height the map measured stays")
	check(not HomeLook.apply_to_street(street, tall), "and nothing changes the second time")


## What a real lookup of a public museum house showed (1.29): the rooms the AI names keep their names, a
## hall it found dresses the hallway instead of crowding a room out, and your room is on the floor you said.
func test_rooms_the_ai_found_keep_their_names_and_all_get_built() -> void:
	var LayoutBuilder: Script = load("res://scripts/home/layout_builder.gd")
	var HomeEdit: Script = load("res://scripts/home/home_edit.gd")
	eq(HomeModel.room_name("Dining room (the first kitchen)"), "Dining room", "a note in brackets is not part of the name")
	eq(HomeModel.room_name("  Playroom "), "Playroom")
	check(HomeModel.room_name("The very long name of a room that goes on and on").length() <= 24, "short enough for a door plate")
	var home := {"facts": [{"key": "sqft", "value": 2163, "confidence": 0.6}, {"key": "floors", "value": 2, "confidence": 0.9}], "rooms": [
		{"kind": "hall", "name": "Entrance hall", "floor": 0, "wall_color": "green"},
		{"kind": "living", "name": "Living room", "floor": 0},
		{"kind": "office", "name": "Study (the first dining room)", "floor": 0},
		{"kind": "storage", "name": "Pantry", "floor": 0, "floor_material": "wood"},
		{"kind": "dining", "name": "Dining room (the first kitchen)", "floor": 0, "wall_color": "gold", "floor_material": "tile"},
		{"kind": "kitchen", "name": "Kitchen (added 1895)", "floor": 0},
		{"kind": "bedroom", "name": "Maid's room", "floor": 0},
		{"kind": "hall", "name": "Studio reception hall", "floor": 0, "wall_color": "gold"},
		{"kind": "office", "name": "Studio office", "floor": 0},
		{"kind": "office", "name": "Studio library (eight-sided)", "floor": 0},
		{"kind": "office", "name": "Drafting room", "floor": 0, "width_m": 8.4, "depth_m": 8.4},
		{"kind": "garage", "name": "Garage (1911)", "floor": 0},
		{"kind": "bedroom", "name": "Children's bedroom (north half)", "floor": 1},
		{"kind": "bedroom", "name": "Children's bedroom (south half)", "floor": 1},
		{"kind": "bedroom", "name": "Main bedroom", "floor": 1},
		{"kind": "bathroom", "name": "Bathroom", "floor": 1},
		{"kind": "family", "name": "Day room (first a nursery)", "floor": 1, "wall_color": "white"},
		{"kind": "family", "name": "Playroom", "floor": 1, "wall_color": "brick"}]}
	var answers := {"home_type": "house", "floors": 2, "rooms": {"bedroom": 2, "kitchen": 1, "living": 1}, "my_room": {"floor": 1, "where": "front"}}
	var plan: Dictionary = LayoutBuilder.build(answers, HomeModel.facts_by_key(home))
	var names := {}
	var mine_on := -9
	for f in plan.floors:
		for r in f.rooms:
			check(not names.has(str(r.name)), "no two rooms share a name: " + str(r.name))
			names[str(r.name)] = r
			if bool(r.get("mine", false)):
				mine_on = int(f.level)
	for wanted in ["Study", "Pantry", "Dining room", "Kitchen", "Maid's room", "Studio office", "Studio library", "Drafting room", "Garage",
			"Children's bedroom", "Main bedroom", "Bathroom", "Day room", "Playroom", "Living room", "Entrance hall"]:
		check(names.has(wanted), "the room the AI found is built under its own name: %s (built: %s)" % [wanted, str(names.keys())])
	eq(mine_on, 1, "your room is on the floor you said, though the records listed a bedroom downstairs first")
	eq(int(plan.mine_level), 1)
	eq(str(names["Entrance hall"].kind), "hall", "the hall it found is the hallway, not one more room")
	eq(str(names["Entrance hall"].wall), HomeLook.NAMES["green"], "in the paint it found")
	check(not names.has("Studio reception hall") and not names.has("Hallway 1"), "a second hall on the floor adds nothing")
	eq(str(names["Playroom"].wall), HomeLook.NAMES["brick"])
	eq(str(names["Pantry"].floor), "wood")
	# A change made under a room's plain name (before the research named it) still finds the room.
	var ground: Dictionary = HomeEdit.floor_of(plan, 0)
	var study: int = HomeEdit.room_index(ground, "no_such_id", "Study")
	check(study >= 0 and HomeEdit.room_index(ground, "no_such_id", str(ground.rooms[study].alias)) == study, "the plain name is kept as an alias: " + str(ground.rooms[study].get("alias", "")))
	# Without any names (older research, or a helper that gave none) the house is named as before.
	var bare := home.duplicate(true)
	for r in bare.rooms:
		r.erase("name")
	var plain: Dictionary = LayoutBuilder.build(answers, HomeModel.facts_by_key(bare))
	var plain_names := PackedStringArray()
	for f in plain.floors:
		for r in f.rooms:
			plain_names.append(str(r.name))
			check(not r.has("alias"), "no alias where nothing was renamed")
	check("Office 1" in plain_names and "Hallway" in plain_names and "My room" in plain_names, "plain names as before: " + str(plain_names))


func test_what_the_ai_found_is_shown_in_plain_words() -> void:
	for key in ResearchPrompt.FACT_KEYS:
		check(ResearchPrompt.FACT_NAMES.has(key), "every fact the prompt asks for has a name a player would use: " + key)
	eq(ResearchPrompt.fact_name("sqft"), "Size")
	eq(ResearchPrompt.fact_name("exterior_color"), "Outside colour")
	eq(ResearchPrompt.fact_name("porch_kind"), "Porch Kind", "a key the game doesn't know is still spelled out as words")
	eq(ResearchPrompt.fact_value("sqft", 2163.0), "2,163 sq ft")
	eq(ResearchPrompt.fact_value("lot_sqft", 14570), "14,570 sq ft")
	eq(ResearchPrompt.fact_value("sqft", 950.0), "950 sq ft")
	eq(ResearchPrompt.fact_value("sqft", 1234567.0), "1,234,567 sq ft")
	eq(ResearchPrompt.fact_value("year_built", 1889.0), "1889", "a year never gets a comma")
	eq(ResearchPrompt.fact_value("footprint_w_m", 8.4), "8.4 m")
	eq(ResearchPrompt.fact_value("basement", true), "yes")
	eq(ResearchPrompt.fact_value("garage", false), "no")
	eq(ResearchPrompt.fact_value("roof", "gabled, cedar shingles"), "gabled, cedar shingles", "words stay as they were found")
	var d: Dictionary = LookAgain.diff({"facts": [{"key": "sqft", "value": 1800.0}]},
		{"facts": [{"key": "sqft", "value": 2163.0}, {"key": "year_built", "value": 1889.0}, {"key": "basement", "value": true}]})
	check("Size: now 2,163 sq ft (it was 1,800 sq ft)" in d.lines, "what changed, in the review: " + str(d.lines))
	check("Built: 1889" in d.lines and "Basement: yes" in d.lines, "and what is new: " + str(d.lines))


func test_the_house_is_built_in_the_colours_the_ai_found() -> void:
	fresh_save_root()
	check(HomeMapper.build_home(_answers(), _found(), "manual") != "", "the home is built from the answers and the AI's answer")
	var home := HomeStore.load_home()
	var blue: String = HomeLook.NAMES["light blue"]
	eq(str(home.plan.get("exterior", "")), blue, "the plan has the outside colour the listing showed")
	var ground := SaveManager.load_room("lw_floor_0")
	var outside := (ground.edge_walls as Array).filter(func(w): return bool(w.outer))
	check(not outside.is_empty() and outside.all(func(w): return str(w.color_a) == blue or str(w.color_b) == blue), "every outside wall wears it on its outer face")
	var living := _room(home.plan, "living")
	eq(str(living.get("wall", "")), HomeLook.NAMES["sage"], "the living room has the paint the listing's photos showed")
	eq(str(living.get("floor", "")), "wood", "and its hardwood floor")
	var kitchen := _room(home.plan, "kitchen")
	eq(str(kitchen.get("floor", "")), "tile")
	check(str(kitchen.get("wall", "")).begins_with("#"), "a room whose colour wasn't a colour keeps its own")
	check((home.timeline as Array).any(func(t): return str(t.kind) == "built" and int(t.year) == 1962), "the year it was built is on the home's timeline")
	# What you said yourself wins over a listing.
	var said := _answers()
	said["floor_kinds"] = {"living": "carpet"}
	HomeMapper.build_home(said, _found(), "manual")
	eq(str(_room(HomeStore.load_home().plan, "living").get("floor", "")), "carpet", "your own answer about the living room floor wins")
	# Without an AI's answer nothing is coloured by guesswork.
	fresh_save_root("light_world_info_plain")
	HomeMapper.build_home(_answers(), {}, "")
	check(not HomeStore.load_home().plan.has("exterior"), "a home built from your answers alone keeps Polox's default outside")


func test_your_house_on_the_street_wears_them_too() -> void:
	fresh_save_root()
	HomeMapper.build_home(_answers(), _found(), "manual")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TOWN))
	var extract := Osm.clean(raw, 10.0, 10.0, 250)
	# A street built before the colours were known...
	var plain := HoodBuilder.build(extract)
	var before := {}
	for id in plain:
		if plain[id] is Dictionary:
			for b in plain[id].get("buildings", []):
				if str(b.kind) == "mine":
					before = b
	eq(str(before.get("wall", "")), HomeLook.DEFAULT_WALL, "your house starts in Polox's warm default")
	# ...and one built after: the same streets, your house in its own colours, nobody else's touched.
	var look := HomeLook.of(HomeStore.load_home())
	var built := HoodBuilder.build(extract, "", [], look)
	var mine := 0
	var others_changed := 0
	for id in built:
		if not built[id] is Dictionary:
			continue
		var plain_buildings: Array = plain[id].get("buildings", [])
		var buildings: Array = built[id].get("buildings", [])
		for i in buildings.size():
			if str(buildings[i].kind) == "mine":
				mine += 1
				eq(str(buildings[i].wall), HomeLook.NAMES["light blue"], "your house's walls")
				eq(str(buildings[i].roof), HomeLook.NAMES["charcoal"], "its roof")
				eq(int(buildings[i].levels), 2, "as many storeys as the house itself has (the map gave none)")
				check(is_equal_approx(float(buildings[i].h), 1.6 + 0.9 * 2), "and as tall as that: " + str(buildings[i].h))
			elif str(buildings[i].wall) != str(plain_buildings[i].wall) or str(buildings[i].roof) != str(plain_buildings[i].roof):
				others_changed += 1
	check(mine >= 1, "your house is on the street")
	eq(others_changed, 0, "no other building changes colour")
	# An older street follows the facts the next time it is opened (in memory: light_home.gd sanitize).
	check(HomeMapper.build_streets(extract, _answers()), "streets saved")
	var home_chunk := ""
	for id in SaveManager.list_light_rooms():
		if str(id).begins_with("lw_hood_"):
			var place := SaveManager.load_room(id)
			if (place.get("buildings", []) as Array).any(func(b): return str(b.kind) == "mine"):
				home_chunk = str(id)
	check(home_chunk != "", "the block with your house is saved")
	var old := SaveManager.load_room(home_chunk)
	for b in old.buildings:
		if str(b.kind) == "mine":
			b["wall"] = HomeLook.DEFAULT_WALL      # as a street made by an older Polox has it
			b["roof"] = HomeLook.DEFAULT_ROOF
	LightHome.sanitize(old)
	for b in old.buildings:
		if str(b.kind) == "mine":
			eq(str(b.wall), HomeLook.NAMES["light blue"], "an older street's house takes the colours when it is opened")
	var door := (old.objects as Array).filter(func(o): return bool(o.get("front_door", false)))
	check(not door.is_empty() and str(door[0].get("color", "")) == HomeLook.NAMES["red"], "and its front door is the red the listing showed")


func test_the_ais_info_is_files_the_game_reads() -> void:
	fresh_save_root()
	GameState.settings["light_world"] = {}
	HomeMapper.build_home(_answers(), {}, "")
	check(not DirAccess.dir_exists_absolute(HomeStore.info_dir()), "no Info folder until an AI is asked")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var panel := ManualPanel.new()
	main.open_panel(panel)
	panel.setup_manual("research", {"location": ADDRESS, "known": {"floors": 2}})
	await frames(2)
	var info := HomeStore.info_dir()
	check(FileAccess.file_exists(info.path_join(HomeStore.INFO_GUIDE)), "the Info folder explains itself")
	var prompt_file := info.path_join(HomeStore.INFO_PROMPT)
	eq(FileAccess.get_file_as_string(prompt_file), panel.prompt_box.text, "the prompt on screen is prompt.txt in the Info folder")
	check(FileAccess.get_file_as_string(prompt_file).contains("HOW THE GAME WORKS"), "the whole prompt")
	check(panel.find_child("ReadInfoAnswer", true, false) != null and panel.find_child("OpenInfo", true, false) != null, "the screen offers the folder and reading from it")
	# An AI that works with files saves its answer there: the envelope the prompt asked for.
	var request: Dictionary = panel.request
	var answer := {"schema_version": Request.VERSION, "request_id": request.request_id, "base_revision": request.base_revision, "task": "research", "result": _found()}
	var answer_file := info.path_join(HomeStore.INFO_ANSWER)
	var f := FileAccess.open(answer_file, FileAccess.WRITE)
	f.store_string(JSON.stringify(answer, "  "))
	f.close()
	eq(HomeStore.waiting_answer(), answer_file, "the game sees an answer waiting")
	panel.read_info_answer(true)
	check(panel.response_box.text.contains("exterior_color"), "and reads it into the reply box")
	check(panel.status.text.contains("answer.json") and panel.status.text.contains("nothing changes until you Keep"), "saying what it read, and that nothing has changed")
	eq(str(HomeStore.load_home().plan.get("exterior", "")), "", "reading a file builds nothing")
	var got := {"value": {}, "request": {}}
	panel.prepared.connect(func(value, req):
		got.value = value
		got.request = req)
	panel.preview_response()   # (a reply that passes closes the screen and hands the answer on)
	await frames(2)
	check(not (got.value as Dictionary).is_empty(), "the file passes the same check as a pasted reply")
	# Keep: the house is rebuilt and the request closed in one save; the Info folder follows.
	var found := HomeModel.clean_research(got.value)
	check(HomeMapper.build_home(_answers(), found, "manual", Request.closing_writes(got.request)) != "", "kept")
	eq(str(HomeStore.load_home().plan.get("exterior", "")), HomeLook.NAMES["light blue"], "the house is built from the file's facts")
	check(not FileAccess.file_exists(prompt_file), "the prompt (your address is in it) is gone once the request is finished")
	check(not FileAccess.file_exists(answer_file), "the answer leaves the inbox")
	var kept := Array(DirAccess.get_files_at(info.path_join(HomeStore.INFO_KEPT)))
	check(kept.any(func(n): return str(n).contains("as it arrived")), "it is kept as it arrived")
	check(kept.any(func(n): return str(n).ends_with(".json") and not str(n).contains("as it arrived")), "beside what the home is now built from")
	eq(HomeStore.waiting_answer(), "", "nothing is offered twice")
	check(HomeStore.last_research().has("facts"), "Look again compares with it")
	# An answer saved under another name is found too; one that is set aside goes to its own folder.
	var second := Request.create("research", {"location": ADDRESS, "known": {}})
	var other := info.path_join("polox answer.txt")
	f = FileAccess.open(other, FileAccess.WRITE)
	f.store_string("Here you go:\n```json\n" + JSON.stringify({"result": _found()}) + "\n```")
	f.close()
	eq(HomeStore.waiting_answer(), other, "a reply saved as a text file counts")
	check(Request.dismiss(second), "set aside")
	check(not FileAccess.file_exists(other) and not Array(DirAccess.get_files_at(info.path_join(HomeStore.INFO_SET_ASIDE))).is_empty(), "it moves to \"set aside\"")
	# The folder never leaves this computer, and Forget my home takes it too.
	SyncFiles.home_shared = true
	check(SyncFiles.allowed("my_home/home.json", PackedStringArray()), "(the house itself can go to a paired phone)")
	for private_path in ["my_home/Info/prompt.txt", "my_home/Info/answer.json", "my_home/Info/kept/a.json", "my_home/Info/READ ME.txt"]:
		check(not SyncFiles.allowed(private_path, PackedStringArray()), "never synced: " + private_path)
	SyncFiles.home_shared = false
	HomeStore.forget_all()
	check(not DirAccess.dir_exists_absolute(info), "Forget my home deletes the Info folder with the rest")
	main._close_all_panels()
	main.queue_free()
	await frames(2)


func test_the_data_folder_says_where_each_layout_is() -> void:
	var root := fresh_save_root()
	PersonalData.write_guide(root)
	var guide := FileAccess.get_file_as_string(root.path_join(PersonalData.GUIDE_FILE))
	for said in ["Dark World layout", "Light World layout", "slots", "my_home", "Info", "settings.json"]:
		check(guide.contains(said), "the map names " + said)
	if OS.get_name() != "Windows":
		return
	var dark := FileAccess.get_file_as_string(root.path_join("Dark World layout.url"))
	check(dark.begins_with("[InternetShortcut]") and dark.contains("URL=file:///") and dark.contains("/slots"), "a shortcut named as players say it opens the worlds: " + dark.left(80))
	check(not dark.contains(" "), "a folder with spaces in its path is written safely")
	check(not FileAccess.file_exists(root.path_join("Light World layout.url")), "no shortcut to a home that isn't mapped yet")
	HomeMapper.build_home(_answers(), {}, "")
	PersonalData.write_guide(root)
	check(FileAccess.get_file_as_string(root.path_join("Light World layout.url")).contains("/my_home"), "once it is mapped, the Light World's shortcut appears")
	var written := FileAccess.get_modified_time(root.path_join(PersonalData.GUIDE_FILE))
	PersonalData.write_guide(root)
	eq(FileAccess.get_modified_time(root.path_join(PersonalData.GUIDE_FILE)), written, "nothing is rewritten when nothing changed")
	HomeStore.forget_all()
	PersonalData.write_guide(root)
	check(not FileAccess.file_exists(root.path_join("Light World layout.url")), "and it goes when the home is forgotten")
	eq(PersonalData.folder_shortcut("C:/Users/Example/Polox Folder/PersonalData").split("\r\n")[1], "URL=file:///C:/Users/Example/Polox%20Folder/PersonalData")
