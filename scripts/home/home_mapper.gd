extends Node
## "Map my home": the Survey, the lookup you confirmed (or just your answers), then the house built
## and saved as Light World places. Used the first time you go home, and from Settings > Light World >
## Map my home. Emits `mapped` with the entry place's id ("" when you left the Survey: the plain room).
## Tags: [LIGHT_WORLD_MAP]

signal mapped(entry: String)

const SurveyScreen := preload("res://scripts/home/survey_screen.gd")
const Research := preload("res://scripts/home/research.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const LayoutBuilder := preload("res://scripts/home/layout_builder.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const SurveyData := preload("res://scripts/home/survey_data.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const HomeEdit := preload("res://scripts/home/home_edit.gd")
const Osm := preload("res://scripts/home/osm.gd")
const HoodBuilder := preload("res://scripts/home/hood_builder.gd")
const HelperRequest := preload("res://scripts/home/helper_request.gd")

var main: Node
var screen: Control
var research: Node
var recorded := ""          # tests / drives: a recorded helper answer instead of a live call
var available_override: Dictionary = {}
var recorded_osm := ""      # tests / drives: a recorded OpenStreetMap answer instead of a live call
var recorded_coords: Dictionary = {}
var last_result: Dictionary = {}
var _generation := 0
var _preview_ok := false
var _applying := false
var _home_applied := false
var _osm: Node
var _map_preview: Control
var _lookup_request: Dictionary = {}   # the helper request the research answers (closed with the home)


func run(main_node: Node) -> String:
	main = main_node
	screen = SurveyScreen.new()
	if not available_override.is_empty():
		screen.available = available_override
	main.toast_layer().add_child(screen)
	screen.back_requested.connect(_cancel_to_review)
	screen.preview_chosen.connect(func(): _preview_ok = true)
	var screen_queue: Array = []
	screen.done.connect(func(d: Dictionary): screen_queue.append(d))
	while is_instance_valid(screen) and is_inside_tree():
		while screen_queue.is_empty() and is_instance_valid(screen) and is_inside_tree():
			await get_tree().process_frame
		if screen_queue.is_empty() or not is_instance_valid(screen) or not is_inside_tree():
			break
		var res: Dictionary = screen_queue.pop_front()
		last_result = res
		if str(res.choice) == "skipped":
			var tpl_id := str(res.get("template", ""))
			var e := LightHome.apply_template(tpl_id) if tpl_id != "" else ""
			if e == "":
				LightHome.defer_survey()
				await screen.farewell("...ANOTHER TIME, THEN.")
				e = LightHome.ensure_entry()
			else:
				await screen.farewell("YOUR TEMPLATE HOME IS READY.")
			if is_instance_valid(screen):
				screen.remove_from_group("survey_flow")
				screen.hide()
				screen.queue_free()
			mapped.emit(e)
			return e
		_generation += 1
		var ticket := _generation
		var base_revision := JSON.stringify(HomeStore.load_home()).sha256_text()
		var answers: Dictionary = res.answers
		var found := {}
		screen.show_building()
		if str(res.choice) == "lookup" and str(res.helper) != "none":
			found = await _look_up(str(res.helper), answers)
		if ticket != _generation:
			continue
		var proposal := prepare_home(answers, found, str(res.helper) if not found.is_empty() else "")
		_preview_ok = false
		screen.show_preview(proposal.plan, "A sketch from your answers%s. Unknown details are guesses. Your manual edits stay. Go back to revise; nothing changes until Keep." % (" and the reviewed research" if not found.is_empty() else ""))
		while not _preview_ok and ticket == _generation and is_inside_tree():
			await get_tree().process_frame
		if ticket != _generation:
			continue
		if base_revision != JSON.stringify(HomeStore.load_home()).sha256_text():
			_cancel_to_review()
			GameState.notify("Your home changed while this sketch was open. Review it again before keeping it.")
			continue
		_applying = true
		# The research's request is closed in the same save as the home it built.
		var extra := HelperRequest.closing_writes(_lookup_request, "applied") if not found.is_empty() else {}
		var entry := build_home(answers, found, str(res.helper) if not found.is_empty() else "", extra)
		_applying = false
		if entry != "":
			_lookup_request = {}
		if entry == "":
			_cancel_to_review()
			GameState.notify("Couldn't save the home. Your previous home and draft are kept.")
			continue
		screen.complete_draft()
		_home_applied = true
		# Mapping is separately consented; its preview/apply flow preserves this house.
		if bool(res.get("streets", false)):
			await map_streets(answers, found)
		await screen.farewell()
		screen.queue_free()
		mapped.emit(entry)
		return entry
	return ""


func _cancel_to_review() -> void:
	if _applying:
		return
	_generation += 1
	if is_instance_valid(research):
		research.cancel()
	if is_instance_valid(_osm):
		_osm.cancel()
	if is_instance_valid(_map_preview):
		_map_preview.queue_free()
	if is_instance_valid(screen) and not _home_applied:
		screen.resume_review()


## Asks the helper; any failure falls back to your answers (with a line saying so).
func _look_up(helper: String, answers: Dictionary) -> Dictionary:
	var ticket := _generation
	_lookup_request = {}
	if helper == "manual":
		var manual := preload("res://scripts/home/helper_manual_panel.gd").new()
		main.open_panel(manual)
		manual.setup_manual("research", {"location": str(answers.get("address", "")), "known": SurveyData.building_answers(answers)})
		var incoming := {"done": false, "value": {}}
		manual.prepared.connect(func(value, request):
			_lookup_request = request
			incoming.value = value
			incoming.done = true)
		manual.closed.connect(func(): incoming.done = true)
		while not incoming.done and ticket == _generation and is_instance_valid(manual) and is_inside_tree():
			await get_tree().process_frame
		if is_instance_valid(manual):
			manual.queue_free()
		return HomeModel.clean_research(incoming.value) if ticket == _generation and not incoming.value.is_empty() else {}
	research = Research.new()
	add_child(research)
	var job := research
	var reply := {"done": false, "value": {}}
	job.finished.connect(func(r):
		if ticket == _generation:
			reply.value = r
			reply.done = true)
	job.progress.connect(func(line):
		if ticket == _generation and is_instance_valid(screen):
			screen.progress_line(line))
	if recorded != "":
		research.start_recorded(recorded, 0.15)
	else:
		_lookup_request = HelperRequest.create("research", {"location": str(answers.get("address", "")), "known": SurveyData.building_answers(answers)}, helper)
		research.start(helper, str(answers.get("address", "")), SurveyData.building_answers(answers))
	while not bool(reply.done) and ticket == _generation and is_inside_tree():
		await get_tree().process_frame
	job.queue_free()
	if ticket != _generation or not is_inside_tree():
		return {}
	var r: Dictionary = reply.value
	if bool(r.get("ok", false)) and not _lookup_request.is_empty():
		# The same boundary as a pasted answer: this request, this home, the strict check.
		var accepted := HelperRequest.accept(r.get("raw", {}), _lookup_request)
		if not bool(accepted.ok):
			r = {"ok": false, "error": str(accepted.error), "why": "shape"}
	if not bool(r.get("ok", false)):
		screen.progress_line(Research.advice(r) + " Your answers will do; My home > Look again can try later.")
		var pause_until := Time.get_ticks_msec() + 1200
		while Time.get_ticks_msec() < pause_until and ticket == _generation and is_inside_tree():
			await get_tree().process_frame
		return {}
	return r.research


## Your streets from OpenStreetMap (only after LOOK IT UP): where the home is (coordinates you pasted, else
## the helper's answer, else OpenStreetMap's search), then the map around it, built into Light World places.
var say_to: Callable = Callable()   # where progress lines go when there's no Survey screen (My home)


func _say(line: String) -> void:
	if say_to.is_valid():
		say_to.call(line)
	elif is_instance_valid(screen):
		screen.progress_line(line)


func map_streets(answers: Dictionary, found: Dictionary) -> bool:
	_generation += 1
	var ticket := _generation
	var revision := JSON.stringify(HomeStore.load_home()).sha256_text()
	var where := recorded_coords if not recorded_coords.is_empty() else Osm.parse_coords(str(answers.get("address", "")))
	if where.is_empty() and preload("res://scripts/home/map_validation.gd").coordinates(found.get("location")):
		where = {"lat": float(found.location.lat), "lon": float(found.location.lon)}
	var osm: Node = Osm.new()
	_osm = osm
	add_child(osm)
	osm.progress.connect(func(l): _say(l))
	if where.is_empty() and recorded_osm == "":
		_say("Finding your street on the map...")
		var located: Dictionary = await osm.locate(str(answers.get("address", "")))
		if bool(located.get("ok", false)):
			var candidates: Array = located.candidates
			var index := 0
			if candidates.size() > 1:
				var labels: Array = candidates.map(func(c): return str(c.label))
				index = await _choose("Which location?", "Several places match. Choose the right one, or Cancel and paste coordinates.", labels, ticket)
			if index >= 0:
				where = {"lat": candidates[index].lat, "lon": candidates[index].lon}
		else:
			_say(str(located.get("error", "Couldn't find that location.")))
	if ticket != _generation:
		osm.queue_free()
		return false
	if where.is_empty() and recorded_osm == "":
		osm.queue_free()
		_say("Couldn't find your street on the map. (My home can try again.)")
		return false
	var extract := {}
	if recorded_osm != "":
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(recorded_osm))
		var c: Dictionary = where if not where.is_empty() else {"lat": 10.0, "lon": 10.0}
		var validated := preload("res://scripts/home/map_validation.gd").overpass(raw, float(c.lat), float(c.lon), int(answers.get("radius", 250)))
		if not validated.ok:
			_say(str(validated.error))
			osm.queue_free()
			return false
		extract = Osm.clean(raw if raw is Dictionary else {}, float(c.lat), float(c.lon), int(answers.get("radius", 250)))
	else:
		var osm_reply := {"done": false, "value": {}}
		osm.finished.connect(func(d: Dictionary):
			osm_reply.value = d
			osm_reply.done = true, CONNECT_ONE_SHOT)
		osm.fetch(float(where.lat), float(where.lon), int(answers.get("radius", 250)))
		while not bool(osm_reply.done) and ticket == _generation and is_instance_valid(osm) and is_inside_tree():
			await get_tree().process_frame
		if not bool(osm_reply.done) or ticket != _generation or not is_inside_tree():
			if is_instance_valid(osm):
				osm.cancel()
				osm.queue_free()
			return false
		var r: Dictionary = osm_reply.value
		if not bool(r.get("ok", false)):
			osm.queue_free()
			_say(str(r.get("error", "")))
			return false
		extract = r.extract
	osm.queue_free()
	if ticket != _generation or not is_inside_tree():
		return false
	var count: int = extract.get("features", []).size()
	var caption := "This map has %d features within %d metres. Existing decorations will be retained where they fit. A snapshot lets you undo." % [count, int(extract.get("radius", 250))]
	if count < 3:
		caption = "There is very little mapped here (%d features). Adjust the location or keep this sparse map and edit it by hand. Your old streets stay unless you apply." % count
	var picked := await _choose("Review your streets", caption, ["Apply this map"], ticket, extract)
	if picked != 0 or ticket != _generation:
		return false
	if revision != JSON.stringify(HomeStore.load_home()).sha256_text():
		_say("Your home changed during the lookup. Review a fresh map before applying.")
		return false
	return build_streets(extract, answers)


func _choose(title: String, body: String, options: Array, ticket: int, extract: Dictionary = {}) -> int:
	if not is_instance_valid(main):
		_say("A map preview needs an open home screen. Your saved map is unchanged.")
		return -1
	var chosen := {"index": -2}
	var panel: Control = load("res://scripts/ui/choice_panel.gd").new()
	_map_preview = panel
	# Above the Survey, which is on the toast layer rather than the normal panel layer.
	main.open_panel(panel)
	panel.reparent(main.toast_layer())
	panel.add_to_group("survey_flow")
	var choices: Array = []
	for i in options.size():
		choices.append([str(options[i]), func(): chosen.index = i])
	choices.append(["Cancel", func(): chosen.index = -1])
	panel.ask(title, body, choices)
	if not extract.is_empty():
		var map: Control = load("res://scripts/home/hood_map_view.gd").new()
		map.custom_minimum_size = Vector2(0, 180)
		panel.body.add_child(map.clipped_container())
		if map.has_method("set_extract"):
			map.set_extract(extract)
	while int(chosen.index) == -2 and is_instance_valid(panel) and not panel.is_queued_for_deletion() and ticket == _generation and is_inside_tree():
		await get_tree().process_frame
	if is_instance_valid(panel):
		panel.queue_free()
	return int(chosen.index) if ticket == _generation and is_inside_tree() else -1


func _exit_tree() -> void:
	_generation += 1
	if is_instance_valid(research):
		research.cancel()
	if is_instance_valid(_osm):
		_osm.cancel()
	if is_instance_valid(_map_preview):
		_map_preview.queue_free()
	if is_instance_valid(screen):
		screen.queue_free()


## The extract -> your streets as places, joined to your front gate. Kept in my_home/osm.json.
static func build_streets(extract: Dictionary, answers: Dictionary) -> bool:
	if not preload("res://scripts/home/map_validation.gd").extract_valid(extract):
		return false
	var home := HomeStore.load_home()
	var places := HoodBuilder.build(extract, str(answers.get("places", "")), home.get("neighbourhood", []), preload("res://scripts/home/home_look.gd").of(home))
	var writes := HoodBuilder.prepare_writes(places)
	writes["osm.json"] = extract
	var removals := PackedStringArray()
	for id in SaveManager.list_light_rooms():
		if str(id).begins_with("lw_hood_") and not places.has(id):
			removals.append("places/" + str(id) + ".json")
	if HomeStore.exists() and HomeStore.snapshot("before_streets") == "":
		return false
	return HomeStore.apply_batch(writes, removals)


## Answers (+ research) -> the home model -> the floor plan -> the Light World's places. Snapshot
## first when there was a home before. Returns the entry place's id.
static func build_home(answers: Dictionary, found: Dictionary, helper: String, extra: Dictionary = {}) -> String:
	var home := prepare_home(answers, found, helper)
	if HomeStore.exists() and HomeStore.snapshot("before_mapping") == "":
		return ""
	var writes := HomeStore.home_writes(home)
	if not found.is_empty():
		writes[HomeStore.RESEARCH_FILE] = found
	writes.merge(extra, true)
	var places := HomePlaces.build(home.plan)
	if places.has("lw_floor_0"):
		LightHome.restore_street_exit(places.lw_floor_0)
	var removals := PackedStringArray()
	var entry := ""
	for id in places:
		writes["places/" + str(id) + ".json"] = places[id]
		if bool(places[id].get("entry", false)):
			entry = str(id)
	for id in SaveManager.list_light_rooms():
		if (str(id).begins_with("lw_floor_") or str(id) == "lw_my_room") and not places.has(id):
			removals.append("places/" + str(id) + ".json")
	if entry == "" or not HomeStore.apply_batch(writes, removals):
		return ""
	return entry


static func prepare_home(answers: Dictionary, found: Dictionary, helper: String) -> Dictionary:
	var old := {}
	if HomeStore.exists():
		old = HomeStore.load_home()
	var home := HomeModel.make(answers, found, helper)
	# Your own edits win over the new answers and research.
	var edits: Array = old.get("edits", []) if old.get("edits") is Array else []
	home["edits"] = edits
	var plan := HomeEdit.rebuild(home)
	for t in old.get("timeline", []):
		if t is Dictionary and str(t.get("source", "")) in ["editor", "words", "photo"]:
			(home.timeline as Array).append(t)
	home["plan"] = plan
	return home
