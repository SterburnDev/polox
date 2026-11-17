extends "res://tests/test_case.gd"
## Phase 34, a phone UI made for phones (portrait, touch): the bottom tab bar (World, Bag, Build, Friends,
## Menu) in the thumb's reach with finger-sized targets, left hand mirrored; screens as bottom sheets that
## swipe down to close (short questions as tall as their contents); a buzz on taps, placing and confirming
## (and none when it's off); pull down from the top to sync; the home sketch by touch (pinch, long press);
## every main screen fitting 412 x 892 and 360 x 780 with nothing to slide sideways; and the main loops by
## touch alone: walk, talk, build, map my home, tell Polox about home, battle, sync.

const Haptics := preload("res://scripts/ui/haptics.gd")
const WorldMenu := preload("res://scripts/world/world_menu.gd")
const ChoicePanel := preload("res://scripts/ui/choice_panel.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const Realms := preload("res://scripts/world/realms.gd")

var main: Node
var _size_before := Vector2i.ZERO
var _min_before := Vector2i.ZERO


func _phone(size: Vector2i = Vector2i(412, 892), left := false) -> Node:
	fresh_save_root()
	_size_before = tree.root.size
	_min_before = tree.root.min_size
	tree.root.min_size = Vector2i.ZERO
	tree.root.size = size
	GameState.settings["touch_ui"] = "on"
	GameState.settings["hand"] = "left" if left else "right"
	GameState.settings["haptics"] = true
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	for n in main.ui.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()
	await frames(2)
	return main.game


func _done() -> void:
	GameState.settings["touch_ui"] = "auto"
	GameState.settings["hand"] = "right"
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)
	tree.root.size = _size_before
	tree.root.min_size = _min_before


## A tap: the touch, and the click Godot makes from it on a phone.
func _tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = pressed
		main.get_viewport().push_input(t, true)
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.position = pos
		m.global_position = pos
		m.pressed = pressed
		main.get_viewport().push_input(m, true)


func _tap_control(c: Control) -> void:
	_tap(c.get_global_rect().get_center())


func _top_panel() -> Control:
	for i in range(main.panels.size() - 1, -1, -1):
		if is_instance_valid(main.panels[i]):
			return main.panels[i]
	return null


## Screen pixels for a length in the game's canvas units.
func _px(units: float) -> float:
	return units * float(tree.root.size.y) / main.get_viewport().get_visible_rect().size.y


func test_the_tab_bar() -> void:
	var g: Node = await _phone()
	var bar: HBoxContainer = g.hud.tab_bar
	check(bar != null and bar.is_visible_in_tree(), "a tab bar on a phone")
	var names: Array = bar.get_children().map(func(b): return (b as Button).text.split("\n")[-1])
	eq(names, ["World", "Bag", "Build", "Friends", "Menu"], "World, Bag, Build, Friends, Menu")
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	for b in bar.get_children():
		var r: Rect2 = (b as Control).get_global_rect()
		check(r.position.y > view.y * 2.0 / 3.0, "%s in the bottom third (thumb's reach)" % names[bar.get_children().find(b)])
		check(_px(r.size.y) >= 48.0 and _px(r.size.x) >= 48.0, "finger-sized: %dx%d px" % [int(_px(r.size.x)), int(_px(r.size.y))])
	_tap_control(bar.get_child(0))
	await frames(3)
	var top := _top_panel()
	check(top != null and str(top.get_script().resource_path).ends_with("world_sheet.gd"), "World opens the World sheet")
	top.close()
	await frames(2)
	_tap_control(bar.get_child(3))
	await frames(3)
	top = _top_panel()
	check(top != null and top.title_label.text.begins_with("Friends"), "Friends opens your friends")
	top.close()
	await frames(2)
	_tap_control(bar.get_child(2))
	await frames(3)
	check(g.build.active, "Build opens Build mode (Dream World)")
	g.build.exit()
	await _done()
	g = await _phone(Vector2i(412, 892), true)
	names = g.hud.tab_bar.get_children().map(func(b): return (b as Button).text.split("\n")[-1])
	eq(names, ["Menu", "Friends", "Build", "Bag", "World"], "left hand: Menu on the left")
	await _done()


func test_furniture_categories_and_touch_targets_on_small_phones() -> void:
	for phone_size in [Vector2i(360, 780), Vector2i(412, 892)]:
		var g: Node = await _phone(phone_size)
		HomeMapper.build_home({"floors": 2, "rooms": {"bedroom": 2, "kitchen": 1, "living": 1}, "my_room": {"floor": 1}}, {}, "")
		GameState.settings["reduce_motion"] = true
		await g.dark.go_light()
		g.decor.open()
		await frames(4)
		var view: Vector2 = main.get_viewport().get_visible_rect().size
		var bar: Rect2 = g.decor._bar.get_global_rect()
		check(bar.position.x >= -1 and bar.end.x <= view.x + 1, "the editing tray fits %s" % phone_size)
		check(bar.position.y > view.y * 0.5, "at least half the home stays visible")
		for name in ["DecorUndo", "DecorDone", "Pick_plant"]:
			var b: Button = g.decor.find_child(name, true, false)
			check(_px(b.size.y) >= 47.9, "%s: 48 screen pixels tall" % name)
		var category: OptionButton = g.decor.find_child("DecorCategory", true, false)
		category.select(5)
		category.item_selected.emit(5)
		await frames(2)
		check(g.decor.find_child("Pick_plant", true, false).visible, "Decor contains plants")
		check(not g.decor.find_child("Pick_bed", true, false).visible, "the category hides beds")
		g.decor.close()
		for i in 3:
			g.hud.apply_layout(true, false)
		await frames(2)
		eq(g.hud.find_children("TabBack", "Control", false, false).size(), 1, "reapplying the phone layout leaves one tab background")
		await _done()


func test_bottom_sheets() -> void:
	var g: Node = await _phone()
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	main.open_panel(WorldMenu.bag(g))
	await frames(3)
	await tree.create_timer(0.3).timeout   # (the sheet slides up first: Phase 35)
	var p := _top_panel()
	check(p.sheet, "a bottom sheet on an upright phone")
	var r: Rect2 = p.panel.get_global_rect()
	check(absf(r.end.y - view.y) < 2.0, "from the bottom edge (%s)" % r)
	check(r.size.x >= view.x - 2.0, "full width")
	# A small swipe snaps back; a long one closes it.
	var handle: Control = p.find_child("SheetHandle", true, false)
	check(handle != null, "a handle to grab")
	var at := handle.get_global_rect().get_center()
	_drag(at, Vector2(0, 40))
	await frames(2)
	check(is_instance_valid(p) and not p.is_queued_for_deletion(), "a small swipe: still open")
	_drag(at, Vector2(0, 160))
	await frames(3)
	check(not is_instance_valid(p) or p.is_queued_for_deletion(), "swiped down: closed")
	# A short question is as tall as it needs to be.
	var c: Control = ChoicePanel.new()
	main.open_panel(c)
	c.ask("A question", "Yes or no?", [["Yes", func(): pass], ["No", func(): pass]])
	await frames(3)
	check(c.panel.get_global_rect().size.y < view.y * 0.5, "a short sheet for a short question")
	c.close()
	await _done()


func _drag(from: Vector2, by: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = from
	t.pressed = true
	main.get_viewport().push_input(t, true)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = from
	mb.global_position = from
	mb.pressed = true
	main.get_viewport().push_input(mb, true)
	for i in 4:
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = from + by * (i + 1) / 4.0
		d.relative = by / 4.0
		main.get_viewport().push_input(d, true)
		var mm := InputEventMouseMotion.new()
		mm.position = d.position
		mm.global_position = d.position
		mm.relative = by / 4.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		main.get_viewport().push_input(mm, true)
	t.pressed = false
	t.position = from + by
	main.get_viewport().push_input(t, true)
	mb.pressed = false
	mb.position = from + by
	mb.global_position = from + by
	main.get_viewport().push_input(mb, true)


func test_a_buzz_under_your_finger() -> void:
	var g: Node = await _phone()
	var before := Haptics.count
	_tap_control(g.hud.tab_bar.get_child(1))
	await frames(2)
	check(Haptics.count > before and Haptics.last == "tap", "a tap buzzes")
	_top_panel().close()
	await frames(2)
	GameState.settings["haptics"] = false
	before = Haptics.count
	_tap_control(g.hud.tab_bar.get_child(1))
	await frames(2)
	eq(Haptics.count, before, "off in Settings: no buzz")
	_top_panel().close()
	GameState.settings["haptics"] = true
	HomeMapper.build_home({"home_type": "house", "floors": 1, "rooms": {"bedroom": 1, "bathroom": 1, "kitchen": 1, "living": 1}, "my_room": {"desk": true}}, {}, "")
	GameState.settings["reduce_motion"] = true
	await g.dark.go_light()
	g.build.enter()
	var mr: Rect2i = load("res://scripts/home/home_places.gd").mine_rect(g.room.data)
	var FloorPaths: GDScript = load("res://scripts/world/floor_paths.gd")
	var shut := (FloorPaths.pockets(g.room.data) as Dictionary).size()
	var spot := Vector2i(-1, -1)
	for z in range(mr.position.y, mr.end.y):
		for x in range(mr.position.x, mr.end.x):
			# (a free cell where a plant shuts nothing off: Edit my room refuses one that would)
			if spot.x < 0 and g.room.nav.walkable(Vector2i(x, z)) and load("res://scripts/world/room_editor.gd").object_at(g.room.data, x, z).is_empty() and Vector2i(x, z) != g.player.cell() \
					and (FloorPaths.pockets(g.room.data, "", Rect2i(x, z, 1, 1)) as Dictionary).size() <= shut:
				spot = Vector2i(x, z)
	g.decor.choose("plant")
	g.decor.tap_cell(spot)
	await frames(2)
	eq(Haptics.last, "place", "placing buzzes a little more")
	g.decor.close()
	await _done()


## A stand-in for the phone's sync (the app or browser version), counting syncs.
class FakePhone extends Node:
	var syncs := 0
	func sync_now() -> void:
		syncs += 1


func test_pull_down_to_sync() -> void:
	await _phone()
	var fake := FakePhone.new()
	main.add_child(fake)
	main.set("phone", fake)
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	_drag(Vector2(view.x / 2.0, view.y * 0.05), Vector2(0, 200))
	await frames(2)
	eq(fake.syncs, 1, "pulled down from the top: a sync")
	_drag(Vector2(view.x / 2.0, view.y * 0.5), Vector2(0, 200))
	await frames(2)
	eq(fake.syncs, 1, "from the middle: nothing")
	_drag(Vector2(view.x / 2.0, view.y * 0.05), Vector2(0, 50))
	await frames(2)
	eq(fake.syncs, 1, "a short pull: nothing")
	main.set("phone", null)
	await _done()


func test_the_home_sketch_by_touch() -> void:
	var g: Node = await _phone()
	HomeMapper.build_home({"home_type": "house", "floors": 1, "rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1}, "my_room": {"desk": true}}, {}, "")
	var hp: Control = load("res://scripts/home/map_home_panel.gd").new()
	main.open_panel(hp)
	hp.setup_home(g)
	await frames(3)
	var sk: Control = hp.sketch
	var c := sk.get_global_rect().get_center()
	# Pinch out: zoom in.
	var z0: float = sk.zoom
	_pinch(c, 60.0, 140.0)
	await frames(2)
	check(sk.zoom > z0 * 1.4, "pinching zooms in (%.2f -> %.2f)" % [z0, sk.zoom])
	# A long press on a room: its options.
	sk.set_zoom(1.0)
	sk.pan = Vector2.ZERO
	sk.queue_redraw()
	await frames(2)
	var f: Dictionary = sk.current()
	var r: Array = f.rooms[0].rect
	var room_px: Vector2 = sk.get_global_position() + sk.cell_to_px(float(r[0]) + float(r[2]) / 2.0, float(r[1]) + float(r[3]) / 2.0)
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = room_px
	t.pressed = true
	main.get_viewport().push_input(t, true)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900:
		await frames(1)
	t.pressed = false
	main.get_viewport().push_input(t, true)
	await frames(2)
	var top := _top_panel()
	check(top != null and top.get_script() == ChoicePanel, "a long press: the room's options")
	check(is_instance_valid(hp) and not hp.is_queued_for_deletion(), "and the sketch stays open (the long press isn't 'back')")
	await _done()


func _pinch(c: Vector2, from_d: float, to_d: float) -> void:
	for i in 2:
		var t := InputEventScreenTouch.new()
		t.index = i
		t.position = c + Vector2((from_d / 2.0) * (1 if i == 0 else -1), 0)
		t.pressed = true
		main.get_viewport().push_input(t, true)
	for step in range(1, 6):
		var d := lerpf(from_d, to_d, step / 5.0)
		for i in 2:
			var e := InputEventScreenDrag.new()
			e.index = i
			e.position = c + Vector2((d / 2.0) * (1 if i == 0 else -1), 0)
			e.relative = Vector2(((to_d - from_d) / 10.0) * (1 if i == 0 else -1), 0)
			main.get_viewport().push_input(e, true)
	for i in 2:
		var t2 := InputEventScreenTouch.new()
		t2.index = i
		t2.position = c
		t2.pressed = false
		main.get_viewport().push_input(t2, true)


func test_every_main_screen_fits_a_phone() -> void:
	for size in [Vector2i(412, 892), Vector2i(360, 780)]:
		var g: Node = await _phone(size)
		HomeMapper.build_home({"home_type": "house", "floors": 2, "rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1}, "my_room": {"floor": 1}}, {}, "")
		var view: Vector2 = main.ui.get_viewport_rect().size
		var screens := {
			"menu": func(): return WorldMenu.make(g), "bag": func(): return WorldMenu.bag(g), "friends": func(): return WorldMenu.friends(g),
			"world": func():
				var s: Control = load("res://scripts/ui/world_sheet.gd").new()
				s.setup_world(g)
				return s,
			"map": func():
				var m: Control = load("res://scripts/ui/world_map_view.gd").new()
				m.setup_map(g)
				return m,
			"my home": func():
				var h: Control = load("res://scripts/home/map_home_panel.gd").new()
				h.setup_home(g)
				return h,
			"tell": func():
				var tp: Control = load("res://scripts/home/tell_polox_panel.gd").new()
				tp.setup_tell(g, "We painted my room green.")
				return tp,
			"journal": func(): return load("res://scripts/home/journal_panel.gd").new(),
			"story": func(): return load("res://scripts/ui/story_panel.gd").new(),
			"memory": func(): return load("res://scripts/ui/memory_book.gd").new(),
			"settings": func(): return load("res://scripts/ui/settings_screen.gd").new(),
		}
		for key in screens:
			var p: Control = screens[key].call()
			if "main" in p and p.get("main") == null:
				p.set("main", main)
			main.open_panel(p)
			await frames(3)
			await tree.create_timer(0.3).timeout   # (after it has slid up)
			var r: Rect2 = (p.get("panel") as Control).get_global_rect()
			var where := "%s at %s" % [key, size]
			check(r.position.x >= -0.5 and r.end.x <= view.x + 0.5 and r.position.y >= -0.5 and r.end.y <= view.y + 0.5, "%s: on screen %s" % [where, r])
			var body: Control = p.get("body")
			var room: float = (p.get("_hscroll") as Control).size.x
			check(body.get_combined_minimum_size().x <= room + 0.5, "%s: nothing to slide sideways (%d > %d)" % [where, int(body.get_combined_minimum_size().x), int(room)])
			if key == "settings":   # every page, not just the one Settings remembers from last time
				for i in p.tabs.get_tab_count():
					p.show_page(i)
					await frames(3)
					check(body.get_combined_minimum_size().x <= room + 0.5, "%s, %s: nothing to slide sideways (%d > %d)" % [where, p.tabs.get_tab_title(i), int(body.get_combined_minimum_size().x), int(room)])
			p.queue_free()
			await frames(1)
		await _done()


## The main loops with taps only (and the phone's keyboard for words).
func test_the_main_loops_by_touch_alone() -> void:
	var g: Node = await _phone()
	GameState.settings["reduce_motion"] = true
	# Walk: tap the floor.
	var from: Vector2i = g.player.cell()
	var target := from + Vector2i(-2, 0)
	if not g.room.nav.walkable(target):
		target = g.room.nav.nearest_walkable(from + Vector2i(2, 1))
	var screen: Vector2 = g.cam.camera.unproject_position(g.room.cell_center(target))
	_tap(screen)
	var t0 := Time.get_ticks_msec()
	while g.player.cell() == from and Time.get_ticks_msec() - t0 < 6000:
		await frames(2)
	check(g.player.cell() != from, "walk: a tap on the floor")
	# Talk: tap a friend.
	var ids: Array = g.actors.keys()
	if not ids.is_empty():
		for _i in 10:
			g.cam._process(0.1)
		var a: Node3D = g.actors[ids[0]]
		_tap(g.cam.camera.unproject_position(a.global_position + Vector3(0, 0.7, 0)))
		t0 = Time.get_ticks_msec()
		while g.talk.talking_to == "" and Time.get_ticks_msec() - t0 < 8000:
			await frames(2)
		check(g.talk.talking_to != "", "talk: a tap on a friend")
		g.dialogue.close_box()
		await frames(3)
	# Build: the Build tab.
	_tap_control(g.hud.tab_bar.get_child(2))
	await frames(3)
	check(g.build.active, "build: the Build tab")
	g.build.exit()
	await frames(2)
	# Map my home: through the way home, then LEAVE (all taps).
	var gate: Dictionary = Realms.gate_of(g.room.data)
	g.dark.use_gate(gate)
	await frames(3)
	var top := _top_panel()
	var go_home: Button = null
	for b in top.buttons:
		if (b as Button).text == "Go home":
			go_home = b
	_tap_control(go_home)
	await frames(6)
	var survey: Control = null
	for c in main.toast_layer().get_children():
		if str(c.get_script().resource_path if c.get_script() else "").ends_with("survey_screen.gd"):
			survey = c
	check(survey != null, "map my home: the Survey opens")
	if survey:
		_tap_control(survey._leave)
	t0 = Time.get_ticks_msec()
	while (not Realms.is_light(g.room.data) or g.dark.busy) and Time.get_ticks_msec() - t0 < 12000:
		await frames(2)
	check(Realms.is_light(g.room.data), "home, in the Light World")
	# Tell Polox about home: World tab -> Tell Polox -> words -> Read it -> Keep.
	HomeMapper.build_home({"home_type": "house", "floors": 1, "rooms": {"bedroom": 1, "kitchen": 1, "living": 1, "bathroom": 1}, "my_room": {"desk": true}}, {}, "")
	g.load_room(LightHome.entry_id())
	await frames(2)
	_tap_control(g.hud.tab_bar.get_child(0))
	await frames(3)
	var ws := _top_panel()
	var tell_b: Button = null
	for b in ws.find_children("*", "Button", true, false):
		if (b as Button).text == "Tell Polox about home":
			tell_b = b
	_tap_control(tell_b)
	await frames(3)
	var tp := _top_panel()
	tp.text_box.text = "We painted my room green."
	_tap_control(tp.find_child("ReadIt", true, false))
	await frames(2)
	_tap_control(tp.find_child("Keep", true, false))
	await frames(3)
	var mine := {}
	for f in HomeStore.load_home().plan.floors:
		for r in f.rooms:
			if bool(r.get("mine", false)):
				mine = r
	eq(str(mine.get("wall", "")), load("res://scripts/home/tell_polox.gd").COLORS.green, "tell Polox: by touch")
	tp.close()
	await frames(2)
	# Battle: back in the Dream World, Menu -> Battle -> start (taps).
	await g.dark.go_dark()
	for p in main.panels.duplicate():
		if is_instance_valid(p) and p.has_method("close"):
			p.close()
	await frames(3)
	_tap_control(g.hud.tab_bar.get_child(4))
	await frames(3)
	var menu := _top_panel()
	check(menu != null, "the Menu tab opens the menu")
	var battle_b: Button = null
	for b in (menu.find_children("*", "Button", true, false) if menu else []):
		if (b as Button).text == "Battle":
			battle_b = b
	for scroll in menu.find_children("*", "ScrollContainer", true, false):
		scroll.ensure_control_visible(battle_b)
	await frames(2)
	_tap_control(battle_b)
	await frames(3)
	var setup := _top_panel()
	check(setup != null and str(setup.get_script().resource_path).ends_with("battle_setup_panel.gd"), "battle: the setup opens by touch")
	var start_b: Button = null
	for b in setup.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Start") or (b as Button).text.begins_with("Fight") or (b as Button).text.begins_with("Battle"):
			start_b = b
	if start_b:
		# The catalogue is longer than one phone screen. Scroll to the selected
		# spar before tapping it, just as for the Battle entry in the menu above.
		for scroll in setup.find_children("*", "ScrollContainer", true, false):
			scroll.ensure_control_visible(start_b)
		await frames(2)
		_tap_control(start_b)
		t0 = Time.get_ticks_msec()
		while g.battles.screen == null and Time.get_ticks_msec() - t0 < 8000:
			await frames(2)
		check(g.battles.screen != null, "battle: it starts by touch")
		if g.battles.screen:
			main.panels.erase(g.battles.screen)
			g.battles.screen.queue_free()
			g.battles.screen = null
	# Sync: pull down (a stand-in for the phone's link).
	var fake := FakePhone.new()
	main.add_child(fake)
	main.set("phone", fake)
	for p in main.panels.duplicate():
		if is_instance_valid(p) and p.has_method("close"):
			p.close()
	await frames(2)
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	_drag(Vector2(view.x / 2.0, view.y * 0.05), Vector2(0, 200))
	await frames(2)
	eq(fake.syncs, 1, "sync: pull down")
	main.set("phone", null)
	await _done()


func test_explanations_stay_readable_on_a_phone() -> void:
	await _phone()
	var UiKit: Script = load("res://scripts/ui/ui_kit.gd")
	var ThemeBuilder: Script = load("res://scripts/ui/theme_builder.gd")
	var l: Label = UiKit.para("A long, quiet explanation that would take three lines on a narrow phone screen, and it goes on a bit more.", 16, ThemeBuilder.MUTED)
	main.ui.add_child(l)
	eq(l.max_lines_visible, -1, "instructions are visible without another gesture")
	l.gui_input.emit(_click_event())
	eq(l.max_lines_visible, -1, "a tap shows the rest")
	var plain: Label = UiKit.para("Short.", 16, ThemeBuilder.MUTED)
	eq(plain.max_lines_visible, -1, "short text stays as it is")
	l.queue_free()
	plain.free()
	await _done()


func _click_event() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e
