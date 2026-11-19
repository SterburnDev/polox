extends "res://tests/test_case.gd"
## Phase 35, more animation everywhere: screens slide up and lists arrive one by one, buttons press in, toasts
## glide; placed pieces pop in, a picked-up thing flies to the bag, doors swing; the light fades between
## times of day and weather drifts in; curtains sway and the street has a passing car and birds; friends
## blink, turn to look at you, hop when happy and jump when surprised; the first look at your real home draws
## itself in. Every motion is short, interruptible, and a fade or nothing under Reduce motion.

const AnimFx := preload("res://scripts/ui/anim_fx.gd")
const StreetLife := preload("res://scripts/world/street_life.gd")
const Blink := preload("res://scripts/characters/blink.gd")
const EmoteMotion := preload("res://scripts/characters/emote_motion.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const Moment := preload("res://scripts/ui/moment.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

var main: Node


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	GameState.settings["reduce_motion"] = false
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _boot_home(reduced: bool = true) -> Node:
	var g: Node = await _boot()
	HomeMapper.build_home({"address": "12 Example Lane, Testville", "home_type": "house", "floors": 2,
		"rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1}, "my_room": {"floor": 1, "where": "front", "desk": true, "view": "trees"},
		"used_to_be": "", "renovations": ""}, {}, "")
	GameState.settings["reduce_motion"] = reduced
	await g.dark.go_light()
	await frames(2)
	return g


func _shutdown() -> void:
	GameState.settings["reduce_motion"] = false
	main._close_all_panels()
	main.queue_free()
	await frames(2)


func _wait(s: float) -> void:
	await tree.create_timer(s).timeout


func test_screens_buttons_and_toasts_move_and_reduce_motion_fades() -> void:
	var g: Node = await _boot()
	var before := AnimFx.played
	g.open_bag()
	await frames(2)
	var p: Control = main.panels.back()
	check(AnimFx.played > before, "the bag arrives with a motion")
	check(p.panel.modulate.a < 1.0, "it fades in rather than popping on")
	await _wait(0.45)
	check(is_equal_approx(p.panel.modulate.a, 1.0) and p.panel.scale.is_equal_approx(Vector2.ONE), "and settles")
	var b: Button = UiKit.button("Try", Callable(), 120)
	p.body.add_child(b)
	await frames(1)
	b.button_down.emit()
	await _wait(0.12)
	check(b.scale.x < 1.0, "a button presses in under your finger")
	b.button_up.emit()
	await _wait(0.2)
	check(b.scale.is_equal_approx(Vector2.ONE), "and comes back out")
	p.close()
	await frames(1)
	before = AnimFx.played
	main.show_toast("Hello")
	check(AnimFx.played > before, "a toast glides in")
	# Reduce motion: no movement, just a quick fade.
	GameState.settings["reduce_motion"] = true
	var faded := AnimFx.faded
	before = AnimFx.played
	g.open_bag()
	await frames(2)
	p = main.panels.back()
	eq(AnimFx.played, before, "nothing moves under Reduce motion")
	check(AnimFx.faded > faded, "a short fade instead")
	check(p.panel.scale.is_equal_approx(Vector2.ONE), "no growing")
	await _wait(0.2)
	check(is_equal_approx(p.panel.modulate.a, 1.0), "the fade is quick")
	var b2: Button = UiKit.button("Try", Callable(), 120)
	p.body.add_child(b2)
	await frames(1)
	b2.button_down.emit()
	await _wait(0.1)
	check(b2.scale.is_equal_approx(Vector2.ONE), "buttons don't press in under Reduce motion")
	await _shutdown()


func test_motions_are_interruptible() -> void:
	var g: Node = await _boot()
	var n := Node3D.new()
	g.add_child(n)
	AnimFx.pop_in(n)
	var first: Tween = n.get_meta("anim_tw")
	await frames(2)
	AnimFx.pop_in(n)
	var second: Tween = n.get_meta("anim_tw")
	check(not first.is_valid(), "a new motion stops the one before it")
	check(second.is_valid())
	await _wait(0.4)
	check(n.scale.is_equal_approx(Vector3.ONE), "and ends where it should (no growing from a half-finished pop)")
	# A screen closed mid-arrival is simply gone.
	g.open_bag()
	await frames(1)
	main.panels.back().close()
	await _wait(0.3)
	check(main.panels.is_empty(), "closing mid-motion works")
	n.queue_free()
	await _shutdown()


func test_placing_pops_in_and_pickups_fly_to_the_bag_and_doors_swing() -> void:
	var g: Node = await _boot()
	var free := Vector2i(-1, -1)
	for z in range(1, g.room.d - 1):
		for x in range(1, g.room.w - 1):
			if free.x < 0 and g.room.nav.walkable(Vector2i(x, z)) and RoomEditor.object_at(g.room.data, x, z).is_empty() and Vector2i(x, z) != g.player.cell():
				free = Vector2i(x, z)
	check(free.x >= 0, "a free spot")
	var o := RoomEditor.add_object(g.room.data, free.x, free.y, "prop")
	var before := AnimFx.popped
	g.rebuild_room()
	var node: Node3D = g.room.object_nodes[str(o.id)]
	eq(AnimFx.popped - before, 1, "the new piece pops in (only it)")
	check(node.scale.x < 1.0, "starting small")
	var others := 0
	for id in g.room.object_nodes:
		if id != str(o.id) and (g.room.object_nodes[id] as Node3D).scale.x < 0.99:
			others += 1
	eq(others, 0, "pieces that were already there don't pop again")
	await _wait(0.4)
	check(node.scale.is_equal_approx(Vector3.ONE), "and settles at full size")
	# Arriving somewhere new doesn't pop everything.
	before = AnimFx.popped
	g.load_room("garden", "home")
	await frames(2)
	eq(AnimFx.popped, before, "walking into a place doesn't pop its pieces")
	# Something picked up flies to the bag.
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	AnimFx.fly_to(main.fly_layer(), tex, Vector2(100, 300), Vector2(380, 820))
	await frames(1)
	check(main.fly_layer().find_child("FlyingToBag", true, false) != null, "the picked-up thing flies")
	await _wait(0.7)
	check(main.fly_layer().find_child("FlyingToBag", true, false) == null, "and is gone when it reaches the bag")
	# A door swings as you go through it.
	g.load_room("home", "garden")
	await frames(2)
	var door: Dictionary = {}
	for d in g.room.data.get("objects", []):
		if str(d.get("type", "")) == "door" and str(d.get("door_target", "")) != "":
			door = d
	check(not door.is_empty(), "a door at home")
	before = AnimFx.played
	g.controller.go_through(door)
	check(AnimFx.played > before, "the door swings")
	await frames(2)
	await _shutdown()


func test_daylight_fades_and_weather_drifts_in() -> void:
	var g: Node = await _boot()
	g.daylight.hour_override = 12.0
	g.daylight.apply()
	var noon: float = g.sun.light_energy
	g.daylight.hour_override = 21.5
	g.daylight.apply(true)
	await frames(2)
	check(absf(g.sun.light_energy - noon) < 0.2, "the clock moving on doesn't jump the light...")
	await _wait(2.3)
	check(absf(g.sun.light_energy - noon) > 0.05, "...it fades to the evening")
	var evening: float = g.sun.light_energy
	GameState.settings["reduce_motion"] = true
	g.daylight.hour_override = 12.0
	g.daylight.apply(true)
	check(is_equal_approx(g.sun.light_energy, noon), "Reduce motion: straight to the new light")
	check(evening != noon)
	GameState.settings["reduce_motion"] = false
	var fx: Node = g.weather
	check(fx != null, "the weather effect")
	fx.show_weather("rain", 10, 10, 4.0, true)
	if fx.get("particles"):
		check(fx.particles.amount_ratio < 0.5, "rain drifts in rather than switching on")
		await _wait(3.2)
		check(fx.particles.amount_ratio > 0.95, "and is falling properly after a few seconds")
	await _shutdown()


func test_street_life_and_curtains() -> void:
	var g: Node = await _boot()
	var sl: Node3D = g.street_life
	check(sl != null, "street life is part of the world")
	sl.on_room_loaded({"id": "lw_hood_1_1", "floor_areas": [{"kind": "road", "rect": [0, 20, 60, 3]}, {"kind": "road", "rect": [30, 0, 3, 60]}, {"kind": "grass", "rect": [0, 0, 10, 10]}]})
	eq(sl.strips.size(), 2, "both roads carry traffic")
	var car: Node3D = sl.spawn_car()
	check(car != null and car.is_inside_tree(), "a car comes along the road")
	var start := car.position
	await _wait(0.5)
	check(is_instance_valid(car) and car.position.distance_to(start) > 0.3, "and rolls along it")
	check(is_equal_approx(car.position.y, 0.0), "on the ground")
	sl.spawn_birds()
	eq(sl.find_children("*", "Label3D", true, false).size(), 3, "a few birds cross the sky")
	GameState.settings["reduce_motion"] = true
	var cars: int = sl.cars
	for i in 40:
		sl._process(1.0)
	eq(sl.cars, cars, "no cars or birds under Reduce motion")
	GameState.settings["reduce_motion"] = false
	sl.on_room_loaded({"id": "home", "floor_areas": [{"kind": "road", "rect": [0, 20, 60, 3]}]})
	await frames(1)
	eq(sl.strips.size(), 0, "only in the Light World's streets")
	await _shutdown()
	# Curtains on the inside of your home's windows, swaying a little (still under Reduce motion).
	g = await _boot_home(false)
	var ew: Node3D = g.room.edge_walls
	check(ew.curtains > 0, "curtains at the windows")
	eq(float(ew.curtain_mat.get_shader_parameter("sway")), 1.0, "swaying")
	GameState.settings["reduce_motion"] = true
	g.rebuild_room()
	eq(float(g.room.edge_walls.curtain_mat.get_shader_parameter("sway")), 0.0, "still under Reduce motion")
	await _shutdown()


func _face() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(6, 4, 20, 26), Color("#f2c9a0"))
	img.fill_rect(Rect2i(11, 11, 2, 3), Color("#1a1420"))
	img.fill_rect(Rect2i(19, 11, 2, 3), Color("#1a1420"))
	return img


func test_friends_blink_look_at_you_and_hop() -> void:
	# Blinking is made from the picture's own eyes; pictures without clear eyes don't blink.
	var shut := Blink.closed_eyes(_face())
	check(shut != null, "eyes found")
	check(shut.get_pixel(11, 11).is_equal_approx(Color("#f2c9a0")), "the eye painted shut")
	check(_face().get_pixel(11, 11).is_equal_approx(Color("#1a1420")), "the original untouched")
	var plain := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	plain.fill(Color("#f2c9a0"))
	eq(Blink.closed_eyes(plain), null, "no eyes, no blink")
	var g: Node = await _boot()
	var a: Node3D = g.actors.values()[0]
	var open_tex := ImageTexture.create_from_image(_face())
	a.set_texture(open_tex)
	a._blink_t = 0.0
	a._blink(0.016)
	check(a.sprite.texture != open_tex, "a friend blinks")
	await _wait(0.25)
	eq(a.sprite.texture, open_tex, "and opens their eyes again")
	GameState.settings["reduce_motion"] = true
	a._blink_t = 0.0
	a._blink(0.016)
	eq(a.sprite.texture, open_tex, "no blinking under Reduce motion")
	GameState.settings["reduce_motion"] = false
	# Friends near you turn to look at you; ones far away don't.
	var cam: Camera3D = g.get_viewport().get_camera_3d()
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	a.position = g.player.position + right * 2.0
	a.sprite.flip_h = false
	g.look_at_player()
	check(a.sprite.flip_h, "a friend on your right turns left to look at you")
	a.position = g.player.position - right * 2.0
	g.look_at_player()
	check(not a.sprite.flip_h, "and the other way from your left")
	a.position = g.player.position + right * 8.0
	g.look_at_player()
	check(not a.sprite.flip_h, "a friend across the room carries on")
	# A real hop for happy, a real jump for surprised.
	var hop := 0.0
	for s in EmoteMotion.steps("happy"):
		hop = maxf(hop, (s[0] as Vector2).y)
	check(hop >= 8.0, "happy hops (%d px)" % hop)
	var jump := 0.0
	for s in EmoteMotion.steps("surprised"):
		jump = maxf(jump, (s[0] as Vector2).y)
	check(jump >= 10.0 and jump > hop, "surprised jumps higher (%d px)" % jump)
	a.react("happy")
	await frames(2)
	await _shutdown()


func test_the_first_look_at_your_home_draws_itself_in_once() -> void:
	var g: Node = await _boot_home(true)
	eq(g.dark.last_moment, "first_look", "arriving in your home the first time draws it in")
	check(str(HomeStore.load_home().get("first_look", "")) != "", "remembered (in your private home folder)")
	await g.dark.go_dark()
	await frames(2)
	await g.dark.go_light()
	await frames(2)
	check(g.dark.last_moment != "first_look", "only the first time")
	# Without Reduce motion it takes a couple of seconds and a tap skips it.
	GameState.settings["reduce_motion"] = false
	var t0 := Time.get_ticks_msec()
	var done := [false]
	var run := func():
		await g.reveal_home()
		done[0] = true
	run.call()
	await frames(3)
	var shrunk := 0
	for id in g.room.object_nodes:
		if (g.room.object_nodes[id] as Node3D).scale.x < 0.05:
			shrunk += 1
	check(shrunk > 0, "the furniture isn't there yet...")
	var m: Control = null
	for c in main.find_children("*", "Control", true, false):
		if c.get_script() == Moment:
			m = c
	check(m != null, "a skippable moment")
	m.skip()
	for i in 20:
		if done[0]:
			break
		await frames(1)
	check(done[0] and Time.get_ticks_msec() - t0 < 1500, "a tap skips to the end")
	await _wait(0.4)
	var small := 0
	for id in g.room.object_nodes:
		if (g.room.object_nodes[id] as Node3D).scale.x < 0.9:
			small += 1
	eq(small, 0, "everything in its place after skipping")
	eq(float(g.room.edge_walls.walls_mat.get_shader_parameter("reveal_r")), 1e6, "all the walls showing")
	await _shutdown()


func test_animation_stays_cheap() -> void:
	var g: Node = await _boot()
	var nodes: Array[Node3D] = []
	for i in 300:
		var n := Node3D.new()
		g.add_child(n)
		nodes.append(n)
	var t0 := Time.get_ticks_usec()
	for n in nodes:
		AnimFx.pop_in(n)
	var took := (Time.get_ticks_usec() - t0) / 1000.0
	check(took < 60.0, "300 pops started in %.1f ms" % took)
	var big := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	big.fill(Color(0, 0, 0, 0))
	big.fill_rect(Rect2i(20, 10, 88, 110), Color("#f2c9a0"))
	big.fill_rect(Rect2i(44, 44, 5, 6), Color("#1a1420"))
	big.fill_rect(Rect2i(78, 44, 5, 6), Color("#1a1420"))
	var tex := ImageTexture.create_from_image(big)
	t0 = Time.get_ticks_usec()
	var shut := Blink.texture_for(tex)
	var first := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	Blink.texture_for(tex)
	var again := (Time.get_ticks_usec() - t0) / 1000.0
	check(shut != null, "a big picture's eyes found")
	check(first < 150.0, "finding the eyes once: %.1f ms" % first)
	check(again < 1.0, "then cached: %.2f ms" % again)
	for n in nodes:
		n.queue_free()
	await frames(2)
	# A busy moment (a car, birds, friends blinking and looking, every piece popping) stays well inside a
	# frame: the game's own work per frame, measured over 60 frames (the GPU side needs a real device).
	g.street_life.on_room_loaded({"id": "lw_hood_1_1", "floor_areas": [{"kind": "road", "rect": [0, 20, 60, 3]}]})
	g.street_life.spawn_car()
	g.street_life.spawn_birds()
	for id in g.room.object_nodes:
		AnimFx.pop_in(g.room.object_nodes[id])
	await frames(2)
	# Headless frames run back to back (no vsync, no GPU), so the time between them is the game's own work.
	var worst := 0.0
	var t_all := Time.get_ticks_usec()
	for i in 60:
		var t := Time.get_ticks_usec()
		await frames(1)
		worst = maxf(worst, (Time.get_ticks_usec() - t) / 1000.0)
	var avg := (Time.get_ticks_usec() - t_all) / 1000.0 / 60.0
	print("    (busy frame: %.2f ms on average, %.2f ms at worst)" % [avg, worst])
	check(avg < 14.0, "inside a 60 fps frame (16.7 ms) with room to spare (%.2f ms)" % avg)
	check(worst < 33.0, "never longer than a 30 fps phone frame (%.2f ms)" % worst)
	await _shutdown()
