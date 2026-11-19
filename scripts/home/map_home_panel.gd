extends "res://scripts/ui/screen_panel.gd"
## Settings > Light World > My home: the top-down sketch of your home beside where every fact came from.
##   Sketch: each floor; tap a room to rename it, paint its walls, change its floor; drag one room onto
##           another to swap them; "Walls" mode: tap a wall to make it a door, a window, or a wall again.
##           Every change goes on the timeline and can be undone.
##   Sources: what each source said (with its link), the conflicts and which value is used, the guesses.
##   Timeline: the house's history and your changes (Undo any of yours). Not sure: Polox's open questions:
##           answer any (the house changes at once), skip any, dismiss any. Look again: the lookup again,
##           only what's new shown to keep. Tell Polox about home: your own words.
##   Save these: what only you can get (behind a login), and the folder to drop them in.
## Map my home again re-runs the Survey; Forget my home deletes everything in my_home.

const SketchView := preload("res://scripts/home/sketch_view.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeEdit := preload("res://scripts/home/home_edit.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const LayoutBuilder := preload("res://scripts/home/layout_builder.gd")
const SurveyData := preload("res://scripts/home/survey_data.gd")
const OpenQuestions := preload("res://scripts/home/open_questions.gd")
const LookAgain := preload("res://scripts/home/look_again.gd")
const Research := preload("res://scripts/home/research.gd")
const MAP_STREETS := "Map my streets"
const ResearchPrompt := preload("res://scripts/home/research_prompt.gd")
const HelperRequest := preload("res://scripts/home/helper_request.gd")
const ReviewPanel := preload("res://scripts/home/helper_review_panel.gd")
const CHANGED := "Home changed. Ask again."
const ROOM_FROM := {"you": "Answered", "records": "Records", "guess": "Guessed"}

var world: Node
var home: Dictionary = {}
var sketch: Control
var tab := "sketch"
var walls_mode := false
var undo_stack: Array = []        # edit batches, newest last
var _content: VBoxContainer
var _tools: VBoxContainer
var _floor_row: HFlowContainer
var _drag_from := -1
var _status: Label


func setup_home(game_world: Node) -> void:
	world = game_world
	setup("My home", Vector2(1080, 700))
	_status = UiKit.para("", 16, ThemeBuilder.YELLOW)
	_status.name = "HelperStatus"
	body.add_child(_status)
	home = HomeStore.load_home()
	if not home.is_empty():
		var before := JSON.stringify(home)
		OpenQuestions.generate(home)
		if JSON.stringify(home) != before:   # (saving when nothing changed only moved the "updated" time)
			HomeStore.save_home(home)
	var tabs := UiKit.flow_row(8)
	for t in [["sketch", "Sketch"], ["sources", "Sources"], ["timeline", "Timeline"], ["unsure", "Not sure"], ["save", "Save these"]]:
		var b := UiKit.button(str(t[1]), func(): show_tab(str(t[0])), 0)
		b.name = "Tab_" + str(t[0])
		b.toggle_mode = true
		tabs.add_child(b)
	body.add_child(tabs)
	_content = UiKit.vbox(10)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_content)
	var row := UiKit.flow_row(8)
	var tell := UiKit.button("Tell Polox about home", func(): _tell(), 0)
	tell.name = "Tell"
	row.add_child(tell)
	var look := UiKit.button("Look again", func(): look_again(), 0)
	look.name = "LookAgain"
	row.add_child(look)
	row.add_child(UiKit.button("Research with any AI", _manual_research, 0))
	var streets := UiKit.button(MAP_STREETS + " again" if FileAccess.file_exists(HomeStore.path("osm.json")) else MAP_STREETS, func(): map_streets(), 0)
	streets.name = "MapStreets"
	streets.disabled = str(home.get("address", {}).get("text", "")) == "" or OS.has_feature("web")
	row.add_child(streets)
	var again := UiKit.button("Map my home again", func(): map_again(), 0)
	again.name = "MapAgain"
	row.add_child(again)
	var forget := UiKit.button("Forget my home", func(): _confirm_forget(), 0)
	forget.name = "Forget"
	row.add_child(forget)
	body.add_child(row)
	show_tab("sketch" if not home.is_empty() else "empty")


func show_tab(t: String) -> void:
	tab = t
	for c in _content.get_children():
		c.queue_free()
	for b in body.find_children("Tab_*", "Button", true, false):
		(b as Button).set_pressed_no_signal(str(b.name) == "Tab_" + t)
	if home.is_empty():
		_content.add_child(UiKit.para("No home mapped.", 18))
		return
	match t:
		"sketch":
			_sketch_tab()
		"sources":
			_sources_tab()
		"timeline":
			_timeline_tab()
		"unsure":
			_unsure_tab()
		"save":
			_save_tab()


# --- Sketch and editing ---------------------------------------------------------------------------

func _sketch_tab() -> void:
	var cols := UiKit.columns(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(cols)
	var left := UiKit.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	_floor_row = UiKit.flow_row(6)
	left.add_child(_floor_row)
	sketch = SketchView.new()
	sketch.style = "paper"
	sketch.custom_minimum_size = Vector2(420, 360)
	sketch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sketch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sketch.set_plan(home.get("plan", {}))
	sketch.room_picked.connect(func(_l, i): _on_room(i))
	sketch.room_long_pressed.connect(func(_l, i): _room_options(i))
	sketch.gui_input.connect(_sketch_input)
	left.add_child(sketch)
	for f in sketch.floors():
		var lvl := int(f.level)
		var b := UiKit.button(str(f.name), func():
			sketch.level = lvl
			sketch.selected = -1
			sketch.queue_redraw()
			_tools_for(-1), 0)
		b.name = "Floor_%d" % lvl
		_floor_row.add_child(b)
	var wb := UiKit.button("Walls: off", func(): _toggle_walls(), 0)
	wb.name = "WallsMode"
	_floor_row.add_child(wb)
	var ub := UiKit.button("Undo", func(): undo(), 0)
	ub.name = "Undo"
	_floor_row.add_child(ub)
	_tools = UiKit.vbox(8)
	_tools.custom_minimum_size = Vector2(300, 0)
	cols.add_child(_tools)
	_tools_for(-1)


func _toggle_walls() -> void:
	walls_mode = not walls_mode
	var wb: Button = body.find_child("WallsMode", true, false)
	if wb:
		wb.text = "Walls: on" if walls_mode else "Walls: off"
	_tools_for(sketch.selected if not walls_mode else -1)


func _tools_for(i: int) -> void:
	for c in _tools.get_children():
		c.queue_free()
	if walls_mode:
		_tools.add_child(UiKit.para("Tap a wall: wall, door, window.", 18))
		return
	var f: Dictionary = sketch.current()
	if i < 0 or i >= (f.get("rooms", []) as Array).size():
		_tools.add_child(UiKit.para("Tap a room; drag to swap.", 16))
		_tools.add_child(UiKit.para("%s • made from %s" % [str(f.get("name", "")), "answers + research" if str(home.get("plan", {}).get("made_from", "")) == "answers+research" else "your answers"], 16, ThemeBuilder.MUTED))
		return
	var room: Dictionary = f.rooms[i]
	_tools.add_child(UiKit.label(str(room.name), 22, ThemeBuilder.YELLOW))
	if room.has("from"):
		# Where this room came from (layout_builder.gd): your answers, the records, or Polox's guess.
		var tag := UiKit.para(str(ROOM_FROM.get(str(room.from), "Guessed")), 16, ThemeBuilder.MUTED)
		tag.name = "RoomFrom"
		_tools.add_child(tag)
	var name_edit := UiKit.line_edit("Name", str(room.name))
	name_edit.name = "RoomName"
	_tools.add_child(name_edit)
	_tools.add_child(UiKit.button("Rename", func(): edit({"type": "rename", "level": sketch.level, "room": str(room.id), "name": name_edit.text}), 0))
	_tools.add_child(UiKit.label("Walls", 18))
	var sw := UiKit.flow_row(6)
	for c in SurveyData.WALL_SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		b.tooltip_text = str(c[1]).capitalize()
		b.name = "Paint_" + str(c[1])
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(str(c[0]))
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.pressed.connect(func(): edit({"type": "wall", "level": sketch.level, "room": str(room.id), "color": str(c[0])}))
		sw.add_child(b)
	_tools.add_child(sw)
	_tools.add_child(UiKit.label("Floor", 18))
	var fr := UiKit.flow_row(6)
	for k in ["wood", "carpet", "tile", "vinyl"]:
		var b2 := UiKit.button(k.capitalize(), func(): edit({"type": "floor", "level": sketch.level, "room": str(room.id), "floor": k}), 0)
		b2.name = "FloorKind_" + k
		fr.add_child(b2)
	_tools.add_child(fr)


var _swap_from := -1


func _on_room(i: int) -> void:
	if walls_mode:
		return
	if _swap_from >= 0 and _swap_from != i:
		var f: Dictionary = sketch.current()
		edit({"type": "swap", "level": sketch.level, "room": str(f.rooms[_swap_from].id), "other": str(f.rooms[i].id)})
		_swap_from = -1
		return
	_tools_for(i)


## A long press on a room (touch): its options in a short sheet.
func _room_options(i: int) -> void:
	if world == null:
		return
	var f: Dictionary = sketch.current()
	var p: Control = load("res://scripts/ui/choice_panel.gd").new()
	world.main.open_panel(p)
	p.ask(str(f.rooms[i].name), "Change what?", [
		["Name, paint, floor", func(): _tools_for(i)],
		["Swap rooms", func():
			_swap_from = i
			_status.text = "Now tap the other room."],
		["Nothing", func(): pass]])


func _sketch_input(event: InputEvent) -> void:
	var f: Dictionary = sketch.current()
	var down: bool = UiKit.tap_down(event)
	var up: bool = UiKit.tap_up(event)
	if walls_mode and down:
		var e := nearest_edge(f, sketch.px_to_cell(event.position))
		if not e.is_empty():
			edit({"type": "edge", "level": sketch.level, "x": int(e.x), "z": int(e.z), "dir": str(e.dir), "to": HomeEdit.next_edge_state(e)})
		return
	if down:
		_drag_from = room_at(f, sketch.px_to_cell(event.position))
	elif up and _drag_from >= 0:
		var to := room_at(f, sketch.px_to_cell(event.position))
		if to >= 0 and to != _drag_from:
			edit({"type": "swap", "level": sketch.level, "room": str(f.rooms[_drag_from].id), "other": str(f.rooms[to].id)})
		_drag_from = -1


static func room_at(f: Dictionary, cell: Vector2) -> int:
	for i in (f.get("rooms", []) as Array).size():
		var r: Array = f.rooms[i].rect
		if Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).has_point(cell):
			return i
	return -1


## The wall closest to a point (in cells), within half a cell.
static func nearest_edge(f: Dictionary, cell: Vector2) -> Dictionary:
	var best := {}
	var best_d := 0.5
	for e in f.get("edges", []):
		var mid := Vector2(float(e.x) + 0.5, float(e.z)) if str(e.dir) == "h" else Vector2(float(e.x), float(e.z) + 0.5)
		var d := mid.distance_to(cell)
		if d < best_d:
			best_d = d
			best = e
	return best


## Makes the change for real (snapshot first, onto the timeline, the places rebuilt).
func edit(e: Dictionary) -> bool:
	var res := HomeEdit.commit([e], "editor")
	if res.is_empty():
		_status.text = "Nothing to change there."
		return false
	undo_stack.append(str(res.batch))
	home = HomeStore.load_home()
	var lvl: int = sketch.level
	var sel: int = sketch.selected
	sketch.set_plan(home.get("plan", {}), lvl)
	sketch.selected = sel
	sketch.queue_redraw()
	_status.text = "Done. (Undo's here.)"
	if world and load("res://scripts/world/realms.gd").is_light(world.room.data) and SaveManager.room_exists(GameState.current_room_id):
		world.load_room(GameState.current_room_id, "", world.player.cell())
	if not walls_mode:
		_tools_for(sel)
	return true


func undo() -> void:
	if undo_stack.is_empty():
		_status.text = "Nothing to undo."
		return
	var batch := str(undo_stack.pop_back())
	if HomeEdit.undo(batch):
		home = HomeStore.load_home()
		sketch.set_plan(home.get("plan", {}), sketch.level)
		_status.text = "Put back."
		if world and load("res://scripts/world/realms.gd").is_light(world.room.data) and SaveManager.room_exists(GameState.current_room_id):
			world.load_room(GameState.current_room_id, "", world.player.cell())


# --- Sources, timeline, questions, things to save ----------------------------------------------------

func _sources_tab() -> void:
	var v := UiKit.vbox(8)
	var sources: Array = home.get("sources", [])
	if sources.size() <= 1:
		v.add_child(UiKit.para("All from your answers.", 18))
	# OpenStreetMap / Google Maps / Street View links, nearby places, and what the streets are made of
	# (from the map, or filled in, with your fixes): their own screen.
	if FileAccess.file_exists(HomeStore.path("osm.json")):
		var refs := UiKit.button("Map and references", func(): _map_refs(), 0)
		refs.name = "MapRefs"
		v.add_child(refs)
	for s in sources:
		var box := UiKit.vbox(2)
		box.add_child(UiKit.label("%s  •  %s" % [str(s.get("title", "")), str(s.get("kind", "")).capitalize()], 18, ThemeBuilder.YELLOW))
		if str(s.get("said", "")) != "":
			box.add_child(UiKit.para(str(s.said), 16))
		var facts: Array = (home.get("facts", []) as Array).filter(func(f): return str(f.get("source", "")) == str(s.get("id", "")))
		for f in facts:
			var conf := float(f.get("confidence", 0.5))
			box.add_child(UiKit.para("• %s: %s%s" % [ResearchPrompt.fact_name(f.key), ResearchPrompt.fact_value(f.key, f.value), "  (a guess)" if conf < 0.5 else ("  (fairly sure)" if conf < 0.8 else "")], 16, ThemeBuilder.MUTED))
		if _web_url(str(s.get("url", ""))):   # (research and synced files are data: only web pages open)
			var url := str(s.url)
			var link := UiKit.button("Open the page", func(): OS.shell_open(url), 0)
			box.add_child(link)
		v.add_child(box)
	var conflicts: Array = home.get("conflicts", [])
	if not conflicts.is_empty():
		v.add_child(UiKit.label("Disagreements", 20, ThemeBuilder.YELLOW))
		for c in conflicts:
			var parts: Array = (c.get("values", []) as Array).map(func(x): return "%s says %s" % [_source_name(str(x.get("source", ""))), ResearchPrompt.fact_value(c.key, x.get("value", ""))])
			var chosen := str(c.get("chosen", ""))
			v.add_child(UiKit.para("• %s: %s%s" % [ResearchPrompt.fact_name(c.key), "; ".join(parts), ("  (yours wins)" if chosen == "you" else "")], 16))
	_content.add_child(UiKit.scroll(v))


func _source_name(id: String) -> String:
	if id == "you":
		return "you"
	if id == "records":
		return "the records"
	var s := HomeModel.source(home, id)
	return str(s.get("title", id)) if not s.is_empty() else id


func _timeline_tab() -> void:
	var v := UiKit.vbox(6)
	var t: Array = home.get("timeline", [])
	if t.is_empty():
		v.add_child(UiKit.para("No history yet.", 18))
	for e in t:
		var when := str(e.get("date", "")) if str(e.get("date", "")) != "" else (str(int(e.year)) if int(e.get("year", 0)) > 0 else "Some time")
		var row := UiKit.hbox(8)
		var l := UiKit.para("%s — %s  (%s)" % [when, str(e.text), _source_name(str(e.get("source", "")))], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var batch := str(e.get("batch", ""))
		if batch != "":
			var ub := UiKit.button("Undo", func(): _undo_batch(batch), 0)
			ub.name = "UndoEntry"
			row.add_child(ub)
		v.add_child(row)
	# Every bigger change made a snapshot first; any of them can be put back whole (its own screen).
	if not HomeStore.snapshots().is_empty():
		var earlier := UiKit.button("Earlier versions", func(): _versions(), 0)
		earlier.name = "EarlierVersions"
		v.add_child(earlier)
	_content.add_child(UiKit.scroll(v))


func _map_refs() -> void:
	var p: Control = load("res://scripts/home/map_refs_panel.gd").new()
	if world and world.main:
		world.main.open_panel(p)
	else:
		add_child(p)
	p.on_changed = func():
		home = HomeStore.load_home()
		_refresh_world()
	p.setup_refs()


func _versions() -> void:
	var p: Control = load("res://scripts/home/home_versions_panel.gd").new()
	if world and world.main:
		world.main.open_panel(p)
	else:
		add_child(p)
	p.setup_versions(world.main if world else null)
	p.restored.connect(func():
		home = HomeStore.load_home()
		_refresh_world()
		show_tab("timeline"))


func _undo_batch(batch: String) -> void:
	if HomeEdit.undo(batch):
		home = HomeStore.load_home()
		_status.text = "Undone."
		_refresh_world()
		show_tab("timeline")


func _refresh_world() -> void:
	if world and load("res://scripts/world/realms.gd").is_light(world.room.data):
		var id: String = GameState.current_room_id
		if not SaveManager.room_exists(id):
			id = load("res://scripts/world/light_home.gd").entry_id()
		world.load_room(id, "", world.player.cell())


func _unsure_tab() -> void:
	var v := UiKit.vbox(10)
	var open := OpenQuestions.open_list(home)
	if open.is_empty():
		v.add_child(UiKit.para("No open questions.", 18))
	else:
		v.add_child(UiKit.para("Answer any, or none.", 16, ThemeBuilder.MUTED))
	for q in open:
		var id := str(q.id)
		v.add_child(UiKit.label(str(q.text), 18, ThemeBuilder.YELLOW))
		var row := UiKit.flow_row(6)
		match str(q.get("kind", "free")):
			"color":
				for c in SurveyData.WALL_SWATCHES:
					var b := Button.new()
					b.custom_minimum_size = Vector2(40, 40)
					b.tooltip_text = str(c[1]).capitalize()
					var sb := StyleBoxFlat.new()
					sb.bg_color = Color(str(c[0]))
					sb.set_corner_radius_all(6)
					b.add_theme_stylebox_override("normal", sb)
					b.add_theme_stylebox_override("hover", sb)
					b.pressed.connect(func(): _answer(id, str(c[0])))
					row.add_child(b)
			"floor":
				for k in ["wood", "carpet", "tile", "vinyl"]:
					row.add_child(UiKit.button(k.capitalize(), func(): _answer(id, k), 0))
			"yesno":
				row.add_child(UiKit.button("Yes", func(): _answer(id, true), 0))
				row.add_child(UiKit.button("No", func(): _answer(id, false), 0))
			"view":
				for o in OpenQuestions.VIEWS:
					row.add_child(UiKit.button(str(o[1]), func(): _answer(id, str(o[0])), 0))
			_:
				var field := UiKit.line_edit("Your answer")
				field.custom_minimum_size.x = 320
				row.add_child(field)
				row.add_child(UiKit.button("Answer", func(): _answer(id, field.text), 0))
		row.add_child(UiKit.button("Not now", func(): _dismiss(id), 0))
		v.add_child(row)
	_content.add_child(UiKit.scroll(v))


func _answer(id: String, value: Variant) -> void:
	if value is String and str(value).strip_edges() == "":
		return
	OpenQuestions.answer(id, value)
	home = HomeStore.load_home()
	_status.text = "Thanks. Noted."
	_refresh_world()
	if world and world.has_method("flourish") and load("res://scripts/world/realms.gd").is_light(world.room.data):
		world.flourish()
	show_tab("unsure")


func _dismiss(id: String) -> void:
	OpenQuestions.dismiss(id)
	home = HomeStore.load_home()
	show_tab("unsure")


func _save_tab() -> void:
	var v := UiKit.vbox(8)
	var blocked: Array = home.get("blocked", [])
	if blocked.is_empty():
		v.add_child(UiKit.para("Nothing to save.", 16))
	else:
		v.add_child(UiKit.para("Login required. Save in my_home files.", 18))
	for b in blocked:
		var url := str(b.get("url", ""))
		v.add_child(UiKit.label(str(b.what), 18, ThemeBuilder.YELLOW))
		if str(b.get("why", "")) != "":
			v.add_child(UiKit.para(str(b.why), 16, ThemeBuilder.MUTED))
		if _web_url(url):
			v.add_child(UiKit.button("Open the page", func(): OS.shell_open(url), 0))
	var open_dir := UiKit.button("Open my_home files", func(): SaveManager.open_folder(HomeStore.files_dir()), 0)   # (on a phone: says to use the PC)
	open_dir.name = "OpenFiles"
	v.add_child(open_dir)
	var files := HomeStore.user_files()
	if not files.is_empty():
		v.add_child(UiKit.para("In there: " + ", ".join(Array(files).map(func(p): return str(p).get_file())), 16, ThemeBuilder.MUTED))
	_content.add_child(UiKit.scroll(v))


# --- Tell, look again, map again, forget ---------------------------------------------------------------

func _tell() -> void:
	if world == null:
		return
	close()
	var p: Control = load("res://scripts/home/tell_polox_panel.gd").new()
	world.main.open_panel(p)
	p.setup_tell(world)


## Your streets from OpenStreetMap, after asking: the coordinates (or, to find them, the address) and the radius.
var recorded_osm := ""   # tests / drives: a recorded OpenStreetMap answer instead of a live call


func map_streets() -> void:
	if world == null:
		return
	var a: Dictionary = home.get("answers", {})
	var addr := str(home.get("address", {}).get("text", ""))
	var coords: bool = not load("res://scripts/home/osm.gd").parse_coords(addr).is_empty() or home.get("location") is Dictionary
	var p: Control = load("res://scripts/ui/choice_panel.gd").new()
	world.main.open_panel(p)
	p.ask("Map my streets?", "Sends your home's map coordinates and a %d m radius to OpenStreetMap.%s Nothing else." % [int(a.get("radius", 250)), "" if coords else " (Nominatim gets the address to find them.)"],
		[[MAP_STREETS, func(): _run_streets()], ["Not now", func(): pass]])


func _run_streets() -> void:
	var mapper: Node = load("res://scripts/home/home_mapper.gd").new()
	mapper.main = world.main
	add_child(mapper)
	mapper.say_to = func(l): _status.text = str(l)
	mapper.recorded_osm = recorded_osm
	_status.text = "Asking OpenStreetMap..."
	var found := {}
	if home.get("location") is Dictionary:
		found["location"] = home.location
	var ok: bool = await mapper.map_streets(home.get("answers", {}), found)
	mapper.queue_free()
	if ok:
		_status.text = "Streets mapped."


## The lookup again: first exactly what would be sent and to whom; then only what's new, one tick per
## change, to keep or leave. Every answer (automatic or pasted) belongs to one helper request, checked
## like a pasted one and closed in the same save as Keep; Undo puts the home back from the snapshot.
func look_again() -> void:
	if str(home.get("address", {}).get("text", "")).strip_edges() == "":
		_status.text = "Map your home first."
		UiKit.show_later(_hscroll, _status)
		return
	if world == null:
		return
	var helper := Research.preferred()
	if recorded_look != "":
		_run_look_again(helper)
		return
	if helper == "none":
		_status.text = "Choose a helper in Settings."
		UiKit.show_later(_hscroll, _status)
		return
	if helper == "manual":
		_manual_research()
		return
	var review := ReviewPanel.new()
	world.main.open_panel(review)
	review.review_payload("Look again?", str(Research.WHO.get(helper, helper)), ResearchPrompt.question(str(home.get("address", {}).get("text", "")), SurveyData.building_answers(home.get("answers", {}))))
	var answer: Array = await review.decided
	if str(answer[0]) == "send" and is_inside_tree():
		_run_look_again(helper)


var recorded_look := ""   # tests / drives: a recorded answer instead of a live call
var _research_revision := ""
var _research_request: Dictionary = {}   # the open request the previewed research answers ({} for a recording)
var _research_job: Node


func _run_look_again(helper: String) -> void:
	_cancel_research()
	_research_revision = HelperRequest.revision(HomeStore.load_home())
	_research_request = {}
	var r: Node = Research.new()
	_research_job = r
	add_child(r)
	var reply := {"done": false, "res": {}}
	r.finished.connect(func(d: Dictionary):
		reply.res = d
		reply.done = true, CONNECT_ONE_SHOT)
	_status.text = "Looking again..."
	r.progress.connect(func(l): _status.text = str(l))
	if recorded_look != "":
		r.start_recorded(recorded_look, 0.05)
	else:
		var a: Dictionary = home.get("answers", {})
		_research_request = HelperRequest.create("research", {"location": str(home.get("address", {}).get("text", "")), "known": SurveyData.building_answers(a)}, helper)
		r.start(helper, str(home.get("address", {}).get("text", "")), SurveyData.building_answers(a))
	while not bool(reply.done) and is_instance_valid(r) and r == _research_job and is_inside_tree():
		await get_tree().process_frame
	if not bool(reply.done) or not is_instance_valid(r) or r != _research_job or not is_inside_tree():
		if is_instance_valid(r):
			r.cancel()
			r.queue_free()
		return   # cancelled or replaced while it ran: a late answer is ignored
	var res: Dictionary = reply.res
	r.queue_free()
	_research_job = null
	if not bool(res.get("ok", false)):
		_status.text = Research.advice(res)
		return
	if not _research_request.is_empty():
		var accepted := HelperRequest.accept(res.get("raw", {}), _research_request)
		if not bool(accepted.ok):
			_status.text = str(accepted.error)
			return
	_preview_research(res.research)


func _cancel_research() -> void:
	if is_instance_valid(_research_job):
		_research_job.cancel()
		_research_job.queue_free()
	_research_job = null


func _exit_tree() -> void:
	_cancel_research()


func _manual_research() -> void:
	if world == null:
		return
	var current := HomeStore.load_home()
	var manual := preload("res://scripts/home/helper_manual_panel.gd").new()
	world.main.open_panel(manual)
	manual.setup_manual("research", {"location": str(current.get("address", {}).get("text", "")), "known": SurveyData.building_answers(current.get("answers", {}))})
	manual.prepared.connect(func(raw: Dictionary, request: Dictionary):
		_research_revision = str(request.base_revision)
		_research_request = request
		_preview_research(HomeModel.clean_research(raw)))


func _preview_research(fresh: Dictionary) -> void:
	var preview_request := str(_research_request.get("request_id", ""))
	var preview_revision := _research_revision
	if _research_revision != HelperRequest.revision(HomeStore.load_home()):
		_status.text = CHANGED
		return
	var d := LookAgain.diff(HomeStore.last_research(), fresh)
	if LookAgain.is_empty(d):
		HelperRequest.dismiss(_research_request)   # looked at, nothing to keep: closed
		_research_request = {}
		_status.text = "Nothing new."
		return
	_status.text = "Here's what's new."
	var review := ReviewPanel.new()
	world.main.open_panel(review)
	review.review_changes("Something new", d.items, bool(fresh.get("grounded", true)))
	var answer: Array = await review.decided
	if not is_inside_tree():
		return
	if preview_request != str(_research_request.get("request_id", "")) or preview_revision != _research_revision:
		return # A replacement request owns the newer preview.
	match str(answer[0]):
		"keep":
			_keep_new(fresh, d, answer[1])
		"dismiss":
			HelperRequest.dismiss(_research_request)
			_research_request = {}
			_status.text = "Set aside."
		_:
			_status.text = "Saved for later." if not _research_request.is_empty() else "Not now."


func _keep_new(fresh: Dictionary, d: Dictionary, accepted: Variant = null) -> void:
	if _research_revision != HelperRequest.revision(HomeStore.load_home()):
		_status.text = CHANGED
		return
	var extra := {}
	if not _research_request.is_empty():
		if not HelperRequest.is_open(_research_request):
			_status.text = "Already used. Ask again."
			return
		extra = HelperRequest.closing_writes(_research_request, "applied")
	if accepted is Array and (accepted as Array).is_empty():
		HelperRequest.dismiss(_research_request)
		_research_request = {}
		_status.text = "Nothing ticked."
		return
	if not LookAgain.keep(fresh, d, accepted, extra):
		_status.text = HomeStore.last_error if HomeStore.last_error != "" else "Couldn't save. Nothing changed."
		return
	_research_request = {}
	_last_research_snapshot = HomeStore.last_snapshot
	home = HomeStore.load_home()
	_status.text = "Kept. (See Timeline.)"
	_refresh_world()
	show_tab(tab)
	_last_research_revision = HelperRequest.revision(HomeStore.load_home())
	_offer_undo()
	if home.get("location") is Dictionary or str(home.get("address", {}).get("text", "")) != "":
		var streets := UiKit.button(MAP_STREETS, func(): map_streets(), 0)
		streets.name = "MapStreetsToo"
		_content.add_child(streets)


var _last_research_snapshot := ""
var _last_research_revision := ""


## Right after keeping research: Undo puts the whole home (and its places and streets) back as it was.
func _offer_undo() -> void:
	var undo := UiKit.button("Undo", func(): undo_research(), 0)
	undo.name = "UndoResearch"
	_content.add_child(undo)


func undo_research() -> bool:
	if _last_research_revision != HelperRequest.revision(HomeStore.load_home()):
		_status.text = "Changed since. See Timeline."
		return false
	if _last_research_snapshot == "" or not HomeStore.restore(_last_research_snapshot):
		_status.text = "Couldn't undo."
		return false
	_last_research_snapshot = ""
	home = HomeStore.load_home()
	_status.text = "Undone."
	_refresh_world()
	show_tab(tab)
	return true


func map_again() -> void:
	close()
	if world:
		await world.dark.map_home()


func _confirm_forget() -> void:
	if world == null:
		return
	var p: Control = load("res://scripts/ui/choice_panel.gd").new()
	world.main.open_panel(p)
	p.ask("Forget my home?", "Everything here goes. The Dream World stays.",
		[["Forget it all", func(): forget()], ["Keep it", func(): pass]])


func forget() -> void:
	var in_light: bool = world != null and load("res://scripts/world/realms.gd").is_light(world.room.data)
	HomeStore.forget_all()
	home = {}
	close()
	if in_light and world:
		await world.dark.go_dark()
	GameState.notify("Forgotten, every bit.")


## Only http(s) pages open from research or synced home files (never a file, program or other link kind).
static func _web_url(url: String) -> bool:
	var u := url.strip_edges().to_lower()
	return u.begins_with("https://") or u.begins_with("http://")
