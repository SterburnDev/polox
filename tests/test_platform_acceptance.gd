extends "res://tests/test_case.gd"
## Phase 17 acceptance, with real input events: activate a pillar, run (with
## the run sprites), jump a 1-block ledge, miss a jump and come back at the
## checkpoint, collect a Memory Shard, leave through the Exit Pillar. Three
## times: left-hand keyboard, mouse only, and phone touch (thumb stick).
##
## The course (16 x 10): pillar at (2,4); a 1-block wall at x = 6; a
## checkpoint at (8,4); a soft hazard at (11,4); a Memory Shard at (13,4).
## The camera starts behind the player looking along -z, so "right" is +x.

const RoomEditor := preload("res://scripts/world/room_editor.gd")
const PlatformSave := preload("res://scripts/platform/platform_save.gd")
const Config := preload("res://scripts/platform/platform_config.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")

var main: Node
var g: Node
var pillar: Dictionary


func _start(phone: bool = false) -> void:
	fresh_save_root()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	if phone:
		GameState.settings["touch_ui"] = "on"
	main.begin_new_world()
	await frames(5)
	g = main.game
	var r: Dictionary = g.room.data
	r["size"] = {"w": 16, "d": 10, "h": 3}
	r["tiles"] = []
	r["objects"] = []
	r["tile_layers"] = TileLayers.default_layers()
	for z in 10:
		RoomEditor.add_tile(r, 6, z, "cube", "#8a7bc8")
	pillar = RoomEditor.add_object(r, 2, 4, "platform_pillar")
	pillar.merge({"label": "Test", "repeat": "repeat", "target_room": "", "target_spawn": []}, true)
	RoomEditor.add_object(r, 8, 4, "checkpoint")
	RoomEditor.add_object(r, 11, 4, "hazard")
	var shard := RoomEditor.add_object(r, 13, 4, "shard")
	shard.merge({"elev": 0, "memory": "a test memory"}, true)
	r["spawn"] = [3, 6]
	SaveManager.save_room(r)
	g.load_room(GameState.current_room_id)
	await frames(3)
	pillar = g.room.find_object(str(pillar.id))


func _stop() -> void:
	GameState.settings["touch_ui"] = "auto"
	for k in [KEY_D, KEY_W]:
		_key(k, false)
	main.queue_free()
	await frames(3)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _tap_key(code: Key) -> void:
	_key(code, true)
	await frames(2)
	_key(code, false)
	await frames(1)


func _wait_active(on: bool, max_frames: int = 400) -> void:
	for i in max_frames:
		await frames(1)
		if g.platform.active == on and not g.platform.starting:
			break
	await frames(2)


func _x() -> float:
	return g.platform.body.global_position.x


## Runs right (whatever input `hold` / `release` do) until x passes `goal` or time runs out.
var each_frame: Callable = Callable()   # mouse: keep the pointer ahead of the body, like a hand would


func _until_x(goal: float, seconds: float, jump_at: float = -1.0, jump: Callable = Callable()) -> bool:
	var jumped := false
	for i in int(seconds * 60.0):
		await tree.physics_frame
		if each_frame.is_valid():
			each_frame.call()
		if jump_at > 0.0 and not jumped and _x() >= jump_at:
			jumped = true
			await jump.call()
		if _x() >= goal:
			return true
	return false


## The shared middle part: jump the ledge, pass the checkpoint, fall into the
## hazard (back at the checkpoint), jump the hazard to the shard.
func _course(hold: Callable, release: Callable, jump: Callable, label: String) -> void:
	g.platform.body.teleport(Vector3(3.5, 0.05, 4.5))
	await tree.physics_frame
	await hold.call()
	await _until_x(4.4, 2.0)
	await frames(3)
	eq(g.player.anim.state, "run", "%s: running" % label)
	check(g.player.anim.frames.has("run") and g.player.sprite.texture != g.player.anim.base_texture, "%s: with run sprites (the doll's run cycle), not the standing picture" % label)
	var over := await _until_x(7.2, 3.0, 5.15, jump)
	check(over, "%s: jumped the 1-block ledge (x %.2f)" % [label, _x()])
	# Past the checkpoint and into the hazard: a missed jump.
	var hit := false
	for i in 240:
		await tree.physics_frame
		if each_frame.is_valid():
			each_frame.call()
		if g.platform._fading:
			hit = true
			break
	await release.call()
	check(hit, "%s: ran into the soft hazard (a missed jump)" % label)
	for i in 90:
		await frames(1)
		if not g.platform._fading:
			break
	var at: Vector3 = g.platform.body.global_position
	check(Vector2(at.x, at.z).distance_to(Vector2(8.5, 4.5)) < 0.7, "%s: back at the checkpoint (%.1f, %.1f)" % [label, at.x, at.z])
	check(g.platform.active, "%s: still playing, nothing lost" % label)
	# Over the hazard to the shard.
	var before := PlatformSave.shard_count()
	await hold.call()
	await _until_x(13.6, 3.0, 10.05, jump)
	await release.call()
	await frames(5)
	eq(PlatformSave.shard_count(), before + 1, "%s: jumped the hazard and collected the Memory Shard" % label)


func test_keyboard_left_hand() -> void:
	await _start()
	g.player.position = g.room.cell_center(Vector2i(3, 4))
	await frames(2)
	await _tap_key(KEY_E)   # normal mode: E uses the nearest thing, the pillar
	await _wait_active(true)
	check(g.platform.active, "keyboard: E next to the pillar starts Platform Mode")
	await _tap_key(KEY_R)
	check(g.platform.run_toggle, "keyboard: R turns running on")
	await _course(func(): _key(KEY_D, true), func(): _key(KEY_D, false), func(): await _tap_key(KEY_SPACE), "keyboard")
	g.platform.body.teleport(g.platform.exit_pillar.global_position + Vector3(0.9, 0.05, 0))
	await tree.physics_frame
	await _tap_key(KEY_F)
	await frames(3)
	check(not g.platform.active, "keyboard: F at the Exit Pillar leaves Platform Mode")
	await _stop()


func test_mouse_only() -> void:
	await _start()
	var cam: Camera3D = g.cam.camera
	g.player.position = g.room.cell_center(Vector2i(4, 5))
	await frames(3)
	var px: Vector2 = cam.unproject_position(g.room.obj_position(pillar) + Vector3(0, 1.5, 0))
	g.controller.click(px)   # a click on the pillar walks over and activates it
	await _wait_active(true, 600)
	check(g.platform.active, "mouse: clicking the pillar starts Platform Mode")
	var hold := func():
		var p: Vector2 = cam.unproject_position(g.platform.body.global_position + Vector3(4, 0, 0))
		var mm := InputEventMouseMotion.new()
		mm.position = p
		main.get_viewport().push_input(mm, true)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = true
		mb.position = p
		main.get_viewport().push_input(mb, true)
		await frames(1)
		g.platform._mouse_t -= 0.3   # (a held press: past the click time)
	var release := func():
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = false
		mb.position = Vector2(-500, -500)   # far from where it started: not a click
		main.get_viewport().push_input(mb, true)
		await frames(1)
	var jump := func():
		g.platform.hud.get("_jump").pressed.emit()   # the on-screen Jump button
		await frames(1)
	# Holding the button steers at the pointer: the pointer moves along ahead of the body.
	each_frame = func():
		if g.platform.body:
			var mm := InputEventMouseMotion.new()
			mm.position = cam.unproject_position(g.platform.body.global_position + Vector3(3, 0, 0))
			main.get_viewport().push_input(mm, true)
	await _course(hold, release, jump, "mouse")
	each_frame = Callable()
	# Click the Exit Pillar when next to it.
	g.platform.body.teleport(g.platform.exit_pillar.global_position + Vector3(0.9, 0.05, 0))
	await frames(3)
	g.platform.tap_at(cam.unproject_position(g.platform.exit_pillar.global_position + Vector3(0, 1.5, 0)))
	await frames(3)
	check(not g.platform.active, "mouse: clicking the Exit Pillar (when close) leaves")
	await _stop()


func test_phone_thumb_stick() -> void:
	await _start(true)
	g.player.position = g.room.cell_center(Vector2i(3, 4))
	await frames(2)
	g.use_object(pillar)   # a tap on the pillar does this
	await _wait_active(true, 600)
	check(g.platform.active, "phone: a tap on the pillar starts Platform Mode")
	var stick: Control = g.platform.hud.stick
	check(stick != null, "phone: a thumb stick is on screen")
	print("    phone: panels %d, stick centre %s, blocked %s" % [main.panels.size(), str(stick.center), str(g.platform._blocked())])
	var hold := func():
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.pressed = true
		t.position = stick.center
		main.get_viewport().push_input(t, true)
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = stick.center + Vector2(Config.JOYSTICK_RADIUS, 0)
		main.get_viewport().push_input(d, true)
		await frames(1)
		print("    phone stick: touching %s vector %s" % [str(stick.touching()), str(stick.vector)])
	var release := func():
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.pressed = false
		t.position = stick.center
		main.get_viewport().push_input(t, true)
		await frames(1)
	var jump := func():
		g.platform.hud.get("_jump").pressed.emit()
		await frames(1)
	await _course(hold, release, jump, "phone")
	check(not stick.touching(), "phone: thumb lifted")
	g.platform.body.teleport(g.platform.exit_pillar.global_position + Vector3(0.9, 0.05, 0))
	await frames(3)
	g.platform.interact()   # a tap on the Exit Pillar does this
	await frames(3)
	check(not g.platform.active, "phone: the Exit Pillar leaves Platform Mode")
	await _stop()
