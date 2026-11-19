extends "res://tests/test_case.gd"
## Phase 25, Dream Gates and the Deep (called "Dream Worlds" until world v8): a Deep place made from a place (same layout, Dark
## World palette, void sky, doors left behind), fountains linked both ways, sealing and reopening
## (nothing deleted, the archive), old saves (Dream World Me places become Dream World places behind a
## new fountain at their door), and in the game with the mouse and then touch only: place a
## fountain, open it, enter, transform, go back, seal, reopen. Each animation plays, can be skipped,
## and Reduce motion swaps it for a short fade.

const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const TransformFx := preload("res://scripts/characters/transform_fx.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const WorldMigration := preload("res://scripts/core/world_migration.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const Realms := preload("res://scripts/world/realms.gd")
const Moment := preload("res://scripts/ui/moment.gd")
const ChoicePanel := preload("res://scripts/ui/choice_panel.gd")

var main: Node


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


func _choice() -> Control:
	for p in main.panels:
		if is_instance_valid(p) and p.get_script() == ChoicePanel:
			return p
	return null


func _press(label_start: String) -> bool:
	var p := _choice()
	if p == null:
		return false
	for b in p.buttons:
		if (b as Button).text.begins_with(label_start):
			(b as Button).pressed.emit()
			return true
	return false


func test_making_a_dark_world_from_a_place() -> void:
	var light := Defaults.room("cafe", "Cafe")
	light["tiles"] = [{"x": 2, "y": 0, "z": 3, "type": "cube", "color": "#e8d3b0"}, {"x": 5, "y": 0, "z": 5, "type": "slab", "color": "#7ad6b0"}]
	RoomEditor.add_object(light, 1, 1, "door")
	RoomEditor.add_object(light, 4, 4, "prop", "#7ad6b0")
	RoomEditor.add_object(light, 6, 2, "sign")
	var dark := DarkWorlds.make_from(light, PackedStringArray(["cafe"]))
	eq(str(dark.id), "cafe_dark")
	eq(str(dark.name), "Cafe (the Deep)")
	eq(DarkWorlds.side(dark), "dark")
	eq(str(dark.player_form), "dark", "you're Dream World Me there")
	eq(str(dark.dark_of), "cafe")
	eq((dark.tiles as Array).size(), 2, "the same layout")
	eq(int(dark.tiles[0].x), 2)
	check(str(dark.tiles[0].color) != "#e8d3b0", "in the Dream World palette")
	check(DarkWorlds.dark_color(Color("#e8d3b0")).v < Color("#e8d3b0").v, "darker")
	eq((dark.objects as Array).map(func(o): return str(o.type)), ["prop", "sign"], "doors stay behind")
	eq(str(dark.background.sky), "void", "a void sky")
	check((dark.background.layers as Array).any(func(l): return str(l.kind) == "shapes"), "with slow shapes")
	eq(str(light.tiles[0].color), "#e8d3b0", "the original is untouched")


func test_fountains_link_both_ways_and_seal_without_deleting() -> void:
	var light := Defaults.room("garden", "Garden")
	var f := DarkWorlds.place_fountain(light, Vector2i(5, 5))
	check(not f.is_empty(), "a fountain placed")
	eq(DarkWorlds.state(f), "new")
	var dark := DarkWorlds.make_from(light, PackedStringArray(["garden"]))
	check(DarkWorlds.link(light, f, dark), "linked")
	eq(DarkWorlds.target(f), str(dark.id))
	eq(DarkWorlds.state(f), "open")
	var back: Array = DarkWorlds.fountains(dark)
	eq(back.size(), 1, "the Dream World has a fountain back")
	eq(DarkWorlds.target(back[0]), "garden")
	eq(str(back[0].leads), "light")
	var rooms := {"garden": light, str(dark.id): dark}
	eq(DarkWorlds.dark_worlds(rooms).open, [str(dark.id)])
	DarkWorlds.seal(f)
	eq(DarkWorlds.state(f), "sealed")
	eq(DarkWorlds.dark_worlds(rooms).archive, [str(dark.id)], "sealed: in the archive, not deleted")
	DarkWorlds.reopen(f)
	eq(DarkWorlds.state(f), "open", "reopened any time")
	eq(DarkWorlds.fountain_to(rooms, str(dark.id)).place, "garden")
	check(not DarkWorlds.link(dark, back[0], light), "a Dream World can't lead into a Dream World")


func test_old_saves_dark_world_me_places_become_dark_worlds() -> void:
	fresh_save_root()
	StarterContent.create_world("Old World", "Sam")
	GameState.load_world()
	var start := str(GameState.world.get("start_room", "home"))
	var night := RoomEditor.create_room("Night Garden", 10, 8)
	var nr := SaveManager.load_room(night)
	nr["player_form"] = "dark"
	SaveManager.save_room(nr)
	var home := SaveManager.load_room(start)
	var door := RoomEditor.add_object(home, 3, 3, "door")
	door["door_target"] = night
	SaveManager.save_room(home)
	for id in SaveManager.list_rooms():
		var r := SaveManager.load_room(id)
		r.erase("side")
		SaveManager.save_room(r)
	var raw: Dictionary = JsonUtil.read_json(SaveManager.world_path(), {})
	raw["version"] = 5
	JsonUtil.write_json(SaveManager.world_path(), raw)
	var res := WorldMigration.run()
	check(bool(res.get("migrated", false)) and str(res.get("snapshot", "")) != "", "upgraded after a snapshot")
	var n2 := SaveManager.load_room(night)
	eq(DarkWorlds.side(n2), "dark", "the Dream World Me place is a Dream World place")
	var h2 := SaveManager.load_room(start)
	eq(DarkWorlds.side(h2), "light", "the rest stays ordinary")
	var fs := DarkWorlds.fountains(h2)
	eq(fs.size(), 1, "a new fountain...")
	var fp: Array = fs[0].pos if not fs.is_empty() else [0, 0, 0]
	check(absi(int(fp[0]) - 3) + absi(int(fp[2]) - 3) <= 2, "...at its door")
	eq(DarkWorlds.target(fs[0]) if not fs.is_empty() else "", night, "leading there")
	eq(DarkWorlds.target(DarkWorlds.fountains(n2)[0]) if not DarkWorlds.fountains(n2).is_empty() else "", start, "and back")
	check(h2.objects.any(func(o): return str(o.get("type", "")) == "door" and str(o.get("door_target", "")) == night), "the door stays")


func test_friends_dark_look_and_the_morph() -> void:
	var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(3, 3, 6, 10), Color("#ffd166"))
	var d := TransformFx.dark_variant(img)
	check(d.get_pixel(5, 5).v < Color("#ffd166").v, "darker")
	check(d.get_pixel(2, 6).is_equal_approx(Color(TransformFx.GLOW, 0.9)) or d.get_pixel(2, 6).to_html() == Color(TransformFx.GLOW, 0.898).to_html(), "a glowing outline around the figure")
	eq(d.get_pixel(0, 0).a, 0.0, "the rest stays clear")
	var frames := TransformFx.morph_frames(img, d)
	eq(frames.size(), TransformFx.FRAMES)
	eq((frames[-1] as Image).get_pixel(5, 5), d.get_pixel(5, 5), "it ends as the new look (the flash is gone by the last frame)")


func test_large_avatar_transforms_have_a_fixed_memory_budget() -> void:
	var large := Image.create(2048, 1536, false, Image.FORMAT_RGBA8)
	large.fill(Color("#ffd166"))
	var other := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	other.fill(Color("#7048cc"))
	var frames := TransformFx.morph_frames(large, other)
	eq(frames.size(), TransformFx.FRAMES)
	var bytes := 0
	for frame: Image in frames:
		check(maxi(frame.get_width(), frame.get_height()) <= TransformFx.MAX_MORPH_SIDE, "large pictures do not create full-resolution morphs")
		bytes += frame.get_data().size()
	check(bytes <= 2 * 1024 * 1024, "all morph frames together fit in 2 MiB")
	eq(large.get_size(), Vector2i(2048, 1536), "the player's original picture is untouched")
	eq(TransformFx.morph_frames(null, other), [], "missing source falls back without an error")
	var tex := TransformFx.texture_from_image(other)
	eq(TransformFx.source_image(tex), other, "the transition uses the original CPU image")


func _fountain_in_game(g: Node) -> Dictionary:
	var data: Dictionary = g.room.data
	var f := DarkWorlds.place_fountain(data, Vector2i(5, 5))
	SaveManager.save_room(data)
	g.rebuild_room()
	await frames(2)
	return g.room.find_object(str(f.id))


func test_the_whole_journey_with_the_mouse() -> void:
	var g: Node = await _boot()
	var here := str(GameState.current_room_id)
	var f := await _fountain_in_game(g)
	check(g.room.object_nodes.has(str(f.id)), "the fountain is in the place")
	# Click it (the real click path), then the choices.
	g.player.position = g.room.cell_center(Vector2i(5, 7))
	var cam: Camera3D = g.cam.camera
	for _i in 10:
		g.cam._process(0.1)
	var screen: Vector2 = cam.unproject_position(g.room.obj_position(f) + Vector3(0, 0.7, 0))
	g.controller.click(screen)
	var t := Time.get_ticks_msec()
	while _choice() == null and Time.get_ticks_msec() - t < 8000:
		await frames(2)
	check(_choice() != null, "walking up to it offers the choices")
	var t0 := Time.get_ticks_msec()
	check(_press("Make the Deep version"), "Make the Deep version of this place")
	await frames(2)
	eq(g.dark.last_moment, "opening")
	while g.dark.busy and Time.get_ticks_msec() - t0 < 10000:
		await frames(2)
	var opening_ms := Time.get_ticks_msec() - t0
	check(opening_ms > 1200, "the opening is an animation (%d ms)" % opening_ms)
	var node: Node = g.room.object_nodes.get(str(f.id))
	check(node and node.column.visible and node.particles.emitting, "the column flows, particles drift")
	f = g.room.find_object(str(f.id))
	var dark_id := DarkWorlds.target(f)
	check(SaveManager.room_exists(dark_id), "the Dream World exists")
	# Enter.
	t0 = Time.get_ticks_msec()
	g.dark.use_fountain(f)
	await frames(2)
	check(_press("Enter the Deep"), "Enter")
	await frames(2)
	while g.dark.busy and Time.get_ticks_msec() - t0 < 15000:
		await frames(2)
	var enter_ms := Time.get_ticks_msec() - t0
	eq(GameState.current_room_id, dark_id, "in the Dream World")
	eq(PlayerLook.current(), "dark", "as Dream World Me")
	check(enter_ms > 1800, "falling and transforming take a moment (%d ms)" % enter_ms)
	check(g.dark_look.lines_built > 4, "glowing outlines")
	eq(str(g.room.data.background.sky), "void")
	# Go back.
	var back: Dictionary = DarkWorlds.fountains(g.room.data)[0]
	g.dark.use_fountain(back)
	await frames(2)
	check(_press("Go back to "), "Go back to the place it was made from")
	t0 = Time.get_ticks_msec()
	await frames(2)
	while g.dark.busy and Time.get_ticks_msec() - t0 < 15000:
		await frames(2)
	eq(GameState.current_room_id, here, "back where you came from")
	# Update 9: the place a Deep was made from is still the Dream World, so its outfit stays on
	# (Real Me is worn only in the Light World; before, leaving the Deep wrongly switched to it).
	check(not Realms.is_light(g.room.data), "the place it was made from is in the Dream World")
	eq(PlayerLook.current(), "dark", "still Dream World Me")
	check(Vector2(g.player.cell() - Vector2i(int(f.pos[0]), int(f.pos[2]))).length() <= 2.0, "beside the fountain")
	# Seal, then reopen.
	f = g.room.find_object(str(f.id))
	g.dark.use_fountain(f)
	await frames(2)
	var moments_before: int = (GameState.journal.get("moments", []) as Array).size()
	check(_press("Seal"), "Seal the fountain")
	t0 = Time.get_ticks_msec()
	await frames(2)
	while g.dark.busy and Time.get_ticks_msec() - t0 < 10000:
		await frames(2)
	f = g.room.find_object(str(f.id))
	eq(DarkWorlds.state(f), "sealed")
	check(SaveManager.room_exists(dark_id), "nothing deleted")
	node = g.room.object_nodes.get(str(f.id))
	check(node and node.lid.visible and not node.column.visible, "closed, with its lid")
	eq((GameState.journal.get("moments", []) as Array).size(), moments_before + 1, "a Memory Book page")
	g.dark.use_fountain(f)
	await frames(2)
	check(_press("Reopen"), "Reopen")
	t0 = Time.get_ticks_msec()
	await frames(2)
	while g.dark.busy and Time.get_ticks_msec() - t0 < 10000:
		await frames(2)
	eq(DarkWorlds.state(g.room.find_object(str(f.id))), "open", "open again")
	await _shutdown()


func test_animations_skip_and_reduce_motion() -> void:
	var g: Node = await _boot()
	var f := await _fountain_in_game(g)
	var dark := DarkWorlds.make_from(g.room.data, SaveManager.list_rooms())
	DarkWorlds.link(g.room.data, g.room.find_object(str(f.id)), dark)
	SaveManager.save_room(dark)
	SaveManager.save_room(g.room.data)
	g.rebuild_room()
	await frames(2)
	f = g.room.find_object(str(f.id))
	# Full, then skipped by a tap, then Reduce motion: opening.
	var times := {}
	for mode in ["full", "skipped", "reduced"]:
		GameState.settings["reduce_motion"] = mode == "reduced"
		if mode == "skipped":
			var job := func() -> void:
				await frames(4)
				for m in main.toast_layer().get_children():
					if m.has_method("skip"):
						m.skip()
			job.call()
		var t0 := Time.get_ticks_msec()
		await g.dark.opening(f)
		times[mode] = Time.get_ticks_msec() - t0
	check(times.full > 1200, "opening plays (%d ms)" % times.full)
	check(times.skipped < times.full * 0.4, "a tap skips it (%d ms)" % times.skipped)
	check(times.reduced < 500, "Reduce motion: a short fade (%d ms)" % times.reduced)
	# Entering, skipped: still arrives, still transformed.
	GameState.settings["reduce_motion"] = false
	var job2 := func() -> void:
		await frames(4)
		for m in main.toast_layer().get_children():
			if m.has_method("skip"):
				m.skip()
	job2.call()
	var t1 := Time.get_ticks_msec()
	await g.dark.enter(f)
	var skipped_enter := Time.get_ticks_msec() - t1
	eq(GameState.current_room_id, str(dark.id), "skipped, but there")
	eq(PlayerLook.current(), "dark")
	check(skipped_enter < 1500, "skipping the fall (%d ms)" % skipped_enter)
	await _shutdown()


func test_touch_only() -> void:
	var g: Node = await _boot()
	for n in main.ui.find_children("*", "", true, false):   # the start-up cards (a player taps Got it)
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()
	await frames(2)
	var f := await _fountain_in_game(g)
	g.player.position = g.room.cell_center(Vector2i(5, 7))
	for _i in 10:
		g.cam._process(0.1)
	var screen: Vector2 = g.cam.camera.unproject_position(g.room.obj_position(f) + Vector3(0, 0.7, 0))
	# A tap: the touch, and the click Godot makes from it on a phone (emulate_mouse_from_touch).
	_tap(screen)
	var t := Time.get_ticks_msec()
	while _choice() == null and Time.get_ticks_msec() - t < 12000:
		await frames(2)
	check(_choice() != null, "a tap on the fountain offers the choices")
	if _choice():
		var b: Button = _choice().buttons[0]
		await frames(2)
		_tap(b.get_global_rect().get_center())
		var t0 := Time.get_ticks_msec()
		while (_choice() != null or g.dark.busy) and Time.get_ticks_msec() - t0 < 10000:
			await frames(2)
		check(DarkWorlds.state(g.room.find_object(str(f.id))) == "open", "a tap on Make the Deep version opened it")
	await _shutdown()


## A tap: the touch, plus the left click Godot's touch-to-mouse emulation produces from it.
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
