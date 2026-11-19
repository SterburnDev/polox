extends "res://tests/test_case.gd"
## Mapping your house and streets with any AI chat, no key (1.26.0): the prompt asks for one clear answer
## shape; a reply as chat AIs really write it (a sentence round a ```json block, numbers as text, an option in
## capitals, a field of their own, a person's name, a trailing comma, a mistyped long ID, or no envelope at all)
## is tidied, with a list of what changed, then passes the same strict check; My home and the Survey both map
## the house from it, and the streets from the location it gives; a stale house prompt can be used with a
## fresh one; Tell Polox needs your words first; the map server is your choice. Recorded replies only.

const Paste := preload("res://scripts/home/helper_paste.gd")
const Request := preload("res://scripts/home/helper_request.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const ReviewPanel := preload("res://scripts/home/helper_review_panel.gd")
const ManualPanel := preload("res://scripts/home/helper_manual_panel.gd")
const Osm := preload("res://scripts/home/osm.gd")

const REPLY := "res://tests/fixtures/chat_reply_research.txt"
const BARE := "res://tests/fixtures/chat_reply_research_bare.txt"
const ADDRESS := "12 Example Lane, Testville"

var main: Node


func _answers() -> Dictionary:
	return {"address": ADDRESS, "home_type": "house", "floors": 2, "rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1},
		"my_room": {"floor": 1, "where": "front", "desk": true}, "radius": 250}


func _reply(request: Dictionary, path: String = REPLY) -> String:
	# The AI copied the request id right and the long base revision wrong (it happens).
	return FileAccess.get_file_as_string(path).replace("__REQUEST_ID__", str(request.request_id)).replace("__BASE_REVISION_TYPO__", str(request.base_revision).left(40) + "0000")


func _boot() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	GameState.settings["reduce_motion"] = true
	GameState.settings["light_world"] = {}
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)


func _shutdown() -> void:
	main._close_all_panels()
	main.queue_free()
	GameState.settings["reduce_motion"] = false   # (later suites measure the real animations)
	await frames(2)


func _panel(script: Script) -> Control:
	for i in range(main.panels.size() - 1, -1, -1):
		var p: Variant = main.panels[i]
		if is_instance_valid(p) and (p as Node).get_script() == script:
			return p
	return null


func _wait_for(script: Script, seconds: float = 8.0) -> Control:
	var t := Time.get_ticks_msec()
	while _panel(script) == null and Time.get_ticks_msec() - t < int(seconds * 1000.0):
		await frames(2)
	return _panel(script)


func _press(root: Node, name: String) -> bool:
	var b: Node = root.find_child(name, true, false)
	if b is BaseButton and (b as BaseButton).is_visible_in_tree():
		(b as BaseButton).pressed.emit()
		return true
	return false


func test_tidy_reads_what_chat_ais_write() -> void:
	fresh_save_root()
	HomeMapper.build_home(_answers(), {}, "")
	var request := Request.create("research", {"location": ADDRESS, "known": {}})
	check(not bool(Request.prepare(_reply(request), request).ok), "(the strict check alone refuses the chat reply, as it should)")
	var t := Paste.tidy(_reply(request), request)
	check(bool(t.ok), "tidied: %s" % str(t.error))
	var notes := ", ".join(PackedStringArray(t.notes))
	for want in ["took the JSON out", "left out", "read "]:
		check(notes.contains(want), "it says it %s: %s" % [want, notes])
	check(not notes.contains("Jane") and not notes.contains("Room sizes"), "the notes never repeat the reply's words")
	var r := Request.prepare(str(t.text), request)
	check(bool(r.ok), "the tidied reply passes the strict check: %s" % str(r.get("error", "")))
	check(not str(t.text).contains("Jane") and not str(t.text).contains("assumptions"), "a person's name and the AI's own field are left out unread")
	eq(str(r.value.sources[0].kind), "assessor", "an option in capitals matches")
	eq(r.value.facts[1].value, 1450, "a number written as text is a number")
	# Typographic quotes (a chat app's "smart" quotes) are made plain.
	var curly := Paste.tidy("{“address_found”: false, “facts”: [], “sources”: []}", request)
	check(bool(curly.ok) and ", ".join(PackedStringArray(curly.notes)).contains("fixed quote marks"), "curly quotes: %s" % str(curly.get("error", "")))
	# No envelope at all: added round the answer for this prompt.
	var bare := Paste.tidy(FileAccess.get_file_as_string(BARE), request)
	check(bool(bare.ok) and ", ".join(PackedStringArray(bare.notes)).contains("added this prompt's details"), "a bare answer gets the envelope")
	check(bool(Request.prepare(str(bare.text), request).ok), "and passes")
	# What's never fixed.
	var other := _reply(request).replace(str(request.request_id), "0".repeat(32))
	check(not bool(Paste.tidy(other, request).ok), "a reply for another prompt")
	check(not bool(Paste.tidy(_reply(request).replace("\"schema_version\": 1", "\"schema_version\": 2"), request).ok), "another Polox version")
	check(not bool(Paste.tidy(_reply(request).replace("\"task\": \"research\"", "\"task\": \"words\""), request).ok), "another kind of request")
	check(not bool(Paste.tidy("```json\n{\"facts\": []}\n```\nand also\n```json\n{\"sources\": []}\n```", request).ok), "two JSON objects: which one?")
	check(not bool(Paste.tidy("I couldn't find anything, sorry.", request).ok), "no JSON at all")
	check(not bool(Paste.tidy("", request).ok), "an empty box")
	var unsourced := _reply(request).replace("\"source\": \"s1\", \"confidence\": \"0.95\"", "\"source\": \"nowhere\", \"confidence\": \"0.95\"")
	var u := Paste.tidy(unsourced, request)
	check(not bool(Request.prepare(str(u.text), request).ok), "a fact without a real source still fails the strict check")


func test_repair_preserves_quoted_content() -> void:
	var original := "Keep ,} and ,] plus “quoted words” and someone’s name."
	var broken := JSON.stringify({"text": original})
	broken = broken.left(-1) + ",}"
	var found := Paste.find_object(broken)
	check(bool(found.ok), "a trailing comma can be repaired")
	if bool(found.ok):
		eq(found.value.text, original, "syntax repair preserves punctuation inside strings")
	var wrapped := Paste.find_object("Here's the answer: " + JSON.stringify({"text": "A “quote” then } and { inside text"}) + " Hope it helps.")
	check(bool(wrapped.ok), "smart quotes within a normal string do not end the JSON object early")
	if bool(wrapped.ok):
		eq(wrapped.value.text, "A “quote” then } and { inside text", "wrapped content is preserved")


func test_malformed_facts_reach_validation_without_crashing() -> void:
	fresh_save_root()
	HomeMapper.build_home(_answers(), {}, "")
	var request := Request.create("research", {"location": ADDRESS, "known": {}})
	for facts in ["not a list", 42, {}, true]:
		var tidied := Paste.tidy(JSON.stringify({"facts": facts, "sources": []}), request)
		check(bool(tidied.ok), "malformed facts survive tidying for validation")
		check(not bool(Request.prepare(str(tidied.text), request).ok), "invalid facts are rejected")


func test_the_prompt_is_one_clear_shape() -> void:
	fresh_save_root()
	HomeMapper.build_home(_answers(), {}, "")
	var request := Request.create("research", {"location": ADDRESS, "known": {"floors": 2}})
	var p := Request.prompt(request)
	check(p.contains(str(request.request_id)) and p.contains(str(request.base_revision)), "it carries its request")
	check(p.contains("HOW TO ANSWER") and p.contains("```json") and p.contains("Search the web"), "plain instructions and an example block")
	check(not p.contains("Answer with one JSON object in exactly this shape"), "no second, different answer shape")
	check(p.contains("open_questions") and p.contains("location: {lat, lon, source}"), "the fields listed in words")
	check(not p.contains("\"value\": 1962"), "the example has no sample facts an AI could pass off as found")
	check(p.length() < 14000, "a prompt a chat accepts (%d characters)" % p.length())
	var w := Request.prompt(Request.create("words", {"text": "Blue walls in my room."}))
	check(w.contains("Blue walls") and w.contains("changes: a list of") and not w.contains("Search the web"), "the words prompt")


func test_my_home_maps_the_house_from_a_pasted_chat_reply() -> void:
	await _boot()
	HomeMapper.build_home(_answers(), {}, "")
	var floors_before: int = (HomeStore.load_home().plan.floors as Array).size()
	var hp: Control = load("res://scripts/home/map_home_panel.gd").new()
	main.open_panel(hp)
	hp.setup_home(main.game)
	hp.recorded_osm = ProjectSettings.globalize_path("res://tests/fixtures/osm_madeup_town.json")
	hp._manual_research()
	var manual := await _wait_for(ManualPanel)
	if not check(manual != null, "Research with any AI opens the copy/paste screen"):
		await _shutdown()
		return
	manual.response_box.text = _reply(manual.request)
	manual.preview_response()
	await frames(2)
	check(manual.status.text.contains("tidied"), "the reply is offered tidied: %s" % manual.status.text)
	check(_press(manual, "UseTidied"), "Use it")
	var review := await _wait_for(ReviewPanel)
	if not check(review != null, "the new facts are shown for review"):
		await _shutdown()
		return
	review._decide("keep")
	await frames(3)
	var home := HomeStore.load_home()
	check(str(home.get("researched", "")) != "", "kept")
	check((home.get("rooms", []) as Array).any(func(r): return str(r.get("name", "")) == "Primary bedroom"), "the AI's rooms are the house's rooms now")
	check(home.get("footprint", {}).get("width_m", 0.0) == 10.4, "and its outline")
	check(not JSON.stringify(home).contains("Jane"), "no person's name stored")
	eq(str(JSON.parse_string(FileAccess.get_file_as_string(HomeStore.path(HomeStore.REQUEST_FILE))).get("state", "")), "applied", "the request is closed with the change")
	check((home.plan.floors as Array).size() >= floors_before, "the house is rebuilt from it")
	# The streets, from the location the reply gave.
	check(_press(hp, "MapStreetsToo"), "Map my streets is offered right after")
	await frames(2)
	var choice: Control = main.panels[-1]
	var go: Button = null
	for b in choice.find_children("*", "Button", true, false):
		if (b as Button).text == "Map my streets":
			go = b
	if check(go != null, "it asks first (coordinates to the map server)"):
		go.pressed.emit()
	var t := Time.get_ticks_msec()
	while not FileAccess.file_exists(HomeStore.path("osm.json")) and Time.get_ticks_msec() - t < 15000:
		# "Review your streets" (on the top layer, above any screen): Apply this map.
		for b in main.toast_layer().find_children("*", "Button", true, false):
			if (b as Button).text == "Apply this map" and (b as Button).is_visible_in_tree():
				(b as Button).pressed.emit()
		await frames(4)
	check(FileAccess.file_exists(HomeStore.path("osm.json")), "the streets are mapped")
	check(Array(SaveManager.list_light_rooms()).any(func(id): return str(id).begins_with("lw_hood_")), "and walkable")
	await _shutdown()


func test_the_survey_maps_house_and_streets_from_a_pasted_reply() -> void:
	await _boot()
	var mapper: Node = HomeMapper.new()
	main.add_child(mapper)
	mapper.available_override = {"manual": true, "none": true}
	mapper.recorded_osm = ProjectSettings.globalize_path("res://tests/fixtures/osm_madeup_town.json")
	var result := {"entry": ""}
	var run := func() -> void: result.entry = await mapper.run(main)
	run.call()
	await frames(3)
	var sc: Control = mapper.screen
	for _i in 500:
		var st: Dictionary = sc.step()
		if str(st.get("kind", "")) == "consent" and sc._area.get_child_count() > 0 and not sc._typing:
			break
		if sc._typing or sc._waiting_tap:
			sc._tap()
		elif str(st.get("kind", "")) == "text":
			if str(st.key) == "address":
				sc.field.text = ADDRESS
				sc._submit_text(ADDRESS)
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
	eq(sc.helper, "manual", "the copy/paste helper was picked in the Survey")
	check(_press(sc, "LookItUp"), "LOOK IT UP")
	var manual := await _wait_for(ManualPanel)
	if not check(manual != null, "the copy/paste screen opens with the house prompt"):
		await _shutdown()
		return
	check(manual.prompt_box.text.contains(ADDRESS), "with the address you typed, for you to review")
	manual.response_box.text = FileAccess.get_file_as_string(BARE)
	manual.preview_response()
	await frames(2)
	check(_press(manual, "UseTidied"), "the bare chat answer is offered tidied, and used")
	var t := Time.get_ticks_msec()
	var decided := false
	while str(result.entry) == "" and Time.get_ticks_msec() - t < 30000:
		if is_instance_valid(sc):
			_press(sc, "KeepHomePreview")
		var preview = mapper._map_preview
		if not decided and is_instance_valid(preview) and not preview.is_queued_for_deletion() and not (preview.buttons as Array).is_empty():
			(preview.buttons[0] as Button).pressed.emit()
			decided = true
		await frames(2)
	check(str(result.entry) != "", "the Survey finished")
	var home := HomeStore.load_home()
	check((home.get("sources", []) as Array).any(func(s): return str(s.get("id", "")) == "county"), "the pasted research is part of the home")
	check(FileAccess.file_exists(HomeStore.path("osm.json")), "and the streets are mapped")
	await _shutdown()


func test_a_stale_house_prompt_can_still_be_used() -> void:
	await _boot()
	HomeMapper.build_home(_answers(), {}, "")
	var hp: Control = load("res://scripts/home/map_home_panel.gd").new()
	main.open_panel(hp)
	hp.setup_home(main.game)
	hp._manual_research()
	var manual := await _wait_for(ManualPanel)
	var old_request: Dictionary = manual.request
	var home := HomeStore.load_home()
	home["first_look"] = "just now"   # you walked into the house while the AI was thinking: that's no change
	HomeStore.save_home(home)
	home = HomeStore.load_home()
	home.plan.floors[0].rooms[0]["name"] = "Renamed while the AI was thinking"   # a real change
	HomeStore.save_home(home)
	manual.response_box.text = _reply(old_request)
	manual.preview_response()
	await frames(2)
	check(manual.status.text.begins_with("Your home changed"), "it says why: %s" % manual.status.text)
	check(_press(manual, "ReuseReply"), "and offers a fresh prompt for the same lookup")
	var review := await _wait_for(ReviewPanel)
	check(review != null, "which previews like any reply")
	check(str(Request.pending().request_id) != str(old_request.request_id), "with a new request, not the stale one")
	await _shutdown()


func test_tell_polox_needs_your_words_first() -> void:
	await _boot()
	HomeMapper.build_home(_answers(), {}, "")
	var panel: Control = load("res://scripts/home/tell_polox_panel.gd").new()
	main.open_panel(panel)
	panel.setup_tell(main.game, "")
	panel._manual_helper()
	await frames(2)
	check(_panel(ManualPanel) == null, "no prompt about nothing")
	check(panel._status.text.contains("Write what changed first"), "it asks for your words: %s" % panel._status.text)
	await _shutdown()


func test_you_choose_the_map_server() -> void:
	await _boot()
	var setup: Control = load("res://scripts/ui/settings_helpers_panel.gd").new()
	main.open_panel(setup)
	setup.setup_helpers()
	await frames(2)
	var pick: OptionButton = setup.find_child("MapServer", true, false)
	if check(pick != null and pick.item_count == Osm.MAP_SERVERS.size(), "a map server choice"):
		pick.select(1)
		pick.item_selected.emit(1)
		eq(str(GameState.settings.light_world.get("overpass_url", "")), str(Osm.MAP_SERVERS[1][1]), "saved")
		var o: Node = Osm.new()
		eq(o._endpoint("overpass_url", Osm.OVERPASS), str(Osm.MAP_SERVERS[1][1]), "and used, on its own (never another behind your back)")
		o.free()
	var busy := Osm.http_result([HTTPRequest.RESULT_SUCCESS, 502, PackedStringArray(), PackedByteArray()])
	check(str(busy.error).contains("pick another map server"), "a busy server points to the choice")
	await _shutdown()


## Make the prompt, close My home (or the game), come back with the AI's answer: still fresh. Opening My home
## used to re-save the home with a new time, which made every waiting prompt stale.
func test_coming_back_later_keeps_the_prompt_fresh() -> void:
	await _boot()
	HomeMapper.build_home(_answers(), {}, "")
	var hp: Control = load("res://scripts/home/map_home_panel.gd").new()
	main.open_panel(hp)
	hp.setup_home(main.game)
	hp._manual_research()
	var manual := await _wait_for(ManualPanel)
	var request: Dictionary = manual.request
	main._close_all_panels()
	await frames(2)
	var again: Control = load("res://scripts/home/map_home_panel.gd").new()
	main.open_panel(again)
	again.setup_home(main.game)
	await frames(2)
	var home := HomeStore.load_home()
	home["first_look"] = "now"   # walking in for the first time meanwhile changes nothing in the house
	HomeStore.save_home(home)
	var t := Paste.tidy(_reply(request), request)
	check(bool(t.ok) and bool(Request.prepare(str(t.text), request).ok), "the answer still fits the prompt you made earlier")
	await _shutdown()
