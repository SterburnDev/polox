extends "res://tests/test_case.gd"
## Phase 17: Platform Mode's movement, headless, on real physics frames.
## A capsule (platform_body.gd) in a room built by platform_world.gd: the jump
## apex, clearing a 1-block ledge but not 2, coyote time and the jump buffer,
## stepping up half blocks (not full ones), a ramp, a one-way platform, a jump
## pad, a moving platform carrying you, the kill plane, and no fall damage.

const Config := preload("res://scripts/platform/platform_config.gd")
const PlatformWorld := preload("res://scripts/platform/platform_world.gd")
const PlatformBody := preload("res://scripts/platform/platform_body.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")

var pw: Node3D
var body: CharacterBody3D


func _room(tiles: Array = [], objects: Array = []) -> Dictionary:
	return {"size": {"w": 20, "d": 8, "h": 3}, "tiles": tiles, "objects": objects, "tile_layers": TileLayers.default_layers()}


func _cube(x: int, z: int, y: int = 0, type: String = "cube", rot: int = 0) -> Dictionary:
	return {"x": x, "z": z, "y": y, "type": type, "color": "#8a7bc8", "rot": rot}


## A wall of blocks across the room at column x, `height` high.
func _wall(x: int, height: int, type: String = "cube") -> Array:
	var out: Array = []
	for z in 8:
		for y in height:
			out.append(_cube(x, z, y, type))
	return out


func _setup(r: Dictionary, at: Vector3) -> void:
	pw = PlatformWorld.new()
	tree.root.add_child(pw)
	pw.build(r)
	body = PlatformBody.new()
	body.world = pw
	tree.root.add_child(body)
	body.teleport(at)
	await _phys(6)


func _teardown() -> void:
	body.queue_free()
	pw.queue_free()
	await frames(2)


func _phys(n: int) -> void:
	for i in n:
		await tree.physics_frame


## Runs for `seconds`, returns the highest feet position seen.
func _run(seconds: float) -> float:
	var top := body.global_position.y
	for i in int(seconds * 60.0):
		await tree.physics_frame
		top = maxf(top, body.global_position.y)
	return top


func test_jump_apex_and_no_fall_damage() -> void:
	await _setup(_room(), Vector3(4, 0.05, 4))
	check(body.is_on_floor(), "standing on the floor")
	var lands: Array = []
	body.landed.connect(func(s): lands.append(s))
	body.press_jump()
	var apex := await _run(1.2)
	print("    jump apex: %.2f blocks" % apex)
	check(apex > 1.15 and apex < 1.55, "the apex clears a block but not two (%.2f)" % apex)
	check(body.is_on_floor() and absf(body.global_position.y) < 0.1, "back on the floor")
	check(lands.size() >= 1, "landed")
	# A big fall: no damage, no lives, you just land.
	body.teleport(Vector3(4, 6.0, 4))
	await _run(1.5)
	check(body.is_on_floor() and not body.frozen, "a 6-block fall: you land and keep going (no fall damage)")
	check(Config.jump_reach().x == 1.0, "Jump reach: up 1 block")
	await _teardown()


func test_clears_one_block_but_not_two() -> void:
	await _setup(_room(_wall(8, 1)), Vector3(4, 0.05, 4))
	body.move_dir = Vector3(1, 0, 0)
	body.run = true
	await _run(0.3)
	body.press_jump()
	await _run(1.4)
	print("    one block: x %.2f y %.2f" % [body.global_position.x, body.global_position.y])
	check(body.global_position.x > 8.2, "ran and jumped onto/over a 1-block ledge (x %.2f)" % body.global_position.x)
	await _teardown()
	await _setup(_room(_wall(8, 2)), Vector3(4, 0.05, 4))
	body.move_dir = Vector3(1, 0, 0)
	body.run = true
	await _run(0.3)
	body.press_jump()
	await _run(1.4)
	body.press_jump()
	await _run(1.0)
	check(body.global_position.x < 8.0, "a 2-block wall stops you (x %.2f)" % body.global_position.x)
	await _teardown()


func test_coyote_time_and_jump_buffer() -> void:
	# Standing on a 1-high platform (x 2..7), walking off its edge at x = 8.
	var tiles: Array = []
	for x in range(2, 8):
		for z in 8:
			tiles.append(_cube(x, z))
	await _setup(_room(tiles), Vector3(6.5, 1.05, 4))
	check(body.is_on_floor() and body.global_position.y > 0.9, "on the platform")
	body.move_dir = Vector3(1, 0, 0)
	var left_at := -1
	for i in 60:
		await tree.physics_frame
		if not body.is_on_floor():
			left_at = i
			break
	check(left_at >= 0, "walked off the edge")
	await _phys(4)   # ~0.07 s in the air
	body.press_jump()
	await _phys(2)
	check(body.velocity.y > 2.0, "coyote time: a jump just after the edge still works (vy %.1f)" % body.velocity.y)
	await _teardown()
	# A 3-high tower this time, so the fall lasts longer than coyote time + jump buffer.
	var tower: Array = []
	for x in range(2, 8):
		for z in 8:
			for y in 3:
				tower.append(_cube(x, z, y))
	await _setup(_room(tower), Vector3(6.5, 3.05, 4))
	body.move_dir = Vector3(1, 0, 0)
	for i in 60:
		await tree.physics_frame
		if not body.is_on_floor():
			break
	await _phys(14)  # ~0.23 s: too late
	body.press_jump()
	await _phys(2)
	check(body.velocity.y <= 0.0, "past the coyote time: no jump in mid-air (vy %.1f)" % body.velocity.y)
	await _teardown()
	# Buffer: falling, pressing jump just before landing.
	await _setup(_room(), Vector3(4, 3.0, 4))
	var jumped := false
	for i in 120:
		await tree.physics_frame
		if body.global_position.y < 0.45 and body.velocity.y < 0.0:
			body.press_jump()
			break
	for i in 20:
		await tree.physics_frame
		if body.velocity.y > 2.0:
			jumped = true
			break
	check(jumped, "jump buffer: pressed just before landing, it jumps on landing")
	await _teardown()


func test_steps_up_half_blocks_but_not_full_ones() -> void:
	await _setup(_room(_wall(7, 1, "slab")), Vector3(4, 0.05, 4))
	body.move_dir = Vector3(1, 0, 0)
	var top := await _run(1.4)
	check(body.global_position.x > 8.0 and top > 0.4, "walked up and over a slab without jumping (x %.2f, top %.2f)" % [body.global_position.x, top])
	await _teardown()
	await _setup(_room(_wall(7, 1)), Vector3(4, 0.05, 4))
	body.move_dir = Vector3(1, 0, 0)
	await _run(1.4)
	check(body.global_position.x < 7.0, "a full block needs a jump (x %.2f)" % body.global_position.x)
	# Auto-jump: the assist hops it.
	body.auto_jump = true
	await _run(1.4)
	check(body.global_position.x > 7.2, "Auto-jump hops the 1-block ledge (x %.2f)" % body.global_position.x)
	await _teardown()


func test_ramp_up() -> void:
	# A ramp at x=6 rising toward +x (rot 2 turns the high side to +x), then a block behind it.
	var tiles: Array = []
	for z in 8:
		tiles.append(_cube(6, z, 0, "ramp", 2))
		tiles.append(_cube(7, z))
		tiles.append(_cube(8, z))
	await _setup(_room(tiles), Vector3(4, 0.05, 4))
	body.move_dir = Vector3(1, 0, 0)
	var top := 0.0
	var on_blocks := false
	for i in 108:
		await tree.physics_frame
		top = maxf(top, body.global_position.y)
		if body.global_position.x > 7.2 and body.global_position.x < 8.8 and body.global_position.y > 0.9:
			on_blocks = true
	print("    ramp: top %.2f, now x %.2f" % [top, body.global_position.x])
	check(on_blocks and top < 1.3, "walked up the ramp onto the blocks, no jump (top %.2f)" % top)
	await _teardown()


func test_one_way_platform() -> void:
	var ow := {"id": "ow1", "type": "one_way", "pos": [4, 0, 4], "elev": 1}
	await _setup(_room([], [ow]), Vector3(4.5, 0.05, 4.5))
	check(body.is_on_floor() and body.global_position.y < 0.2, "under the one-way platform")
	body.press_jump()
	await _run(1.2)
	check(body.global_position.y > 0.9 and body.is_on_floor(), "jumped up through it and stands on it (y %.2f)" % body.global_position.y)
	await _run(0.5)
	check(body.global_position.y > 0.9, "and doesn't fall through")
	await _teardown()


func test_jump_pad_and_moving_platform() -> void:
	var pad := {"id": "pad1", "type": "jump_pad", "pos": [6, 0, 4], "strength": 14.0}
	await _setup(_room([], [pad]), Vector3(4.5, 0.05, 4.5))
	pw.touched.connect(func(kind, o): if kind == "jump_pad": body.launch(float(o.get("strength", Config.JUMP_PAD_STRENGTH))))
	body.move_dir = Vector3(1, 0, 0)
	var top := 0.0
	for i in 90:
		await tree.physics_frame
		top = maxf(top, body.global_position.y)
		if body.global_position.x > 6.2:
			body.move_dir = Vector3.ZERO
	check(top > 2.5, "the jump pad throws you high (%.2f blocks)" % top)
	await _teardown()
	var mover := {"id": "m1", "type": "mover", "pos": [3, 0, 4], "elev": 1, "dx": 6, "dy": 0, "dz": 0, "speed": 2.0}
	await _setup(_room([], [mover]), Vector3(3.5, 1.1, 4.5))
	await _phys(20)
	var start_x := body.global_position.x
	check(body.is_on_floor() and body.global_position.y > 0.9, "standing on the moving platform")
	await _run(1.5)
	print("    carried from x %.2f to %.2f" % [start_x, body.global_position.x])
	check(body.global_position.x > start_x + 1.0 and body.global_position.y > 0.9, "carried along by it (x %.2f -> %.2f)" % [start_x, body.global_position.x])
	await _teardown()


func test_kill_plane_and_soft_hazard_signal() -> void:
	var hz := {"id": "h1", "type": "hazard", "pos": [6, 0, 4]}
	await _setup(_room([], [hz]), Vector3(4.5, 0.05, 4.5))
	var hits: Array = []
	pw.touched.connect(func(kind, _o): hits.append(kind))
	body.move_dir = Vector3(1, 0, 0)
	await _run(1.0)
	check(hits.has("hazard"), "a soft hazard reports a touch (the mode respawns you)")
	var fell := [false]
	body.fell_out.connect(func(): fell[0] = true)
	body.teleport(Vector3(4, -7.0, 4))
	await _phys(3)
	check(fell[0], "below the kill plane: fell out (the mode puts you back at the checkpoint)")
	await _teardown()


func test_triggers_catch_a_fast_pass_once_and_movers_pause() -> void:
	var cp := {"id": "cp1", "type": "checkpoint", "pos": [8, 0, 4]}
	var mover := {"id": "m1", "type": "mover", "pos": [3, 0, 1], "elev": 1, "dx": 6, "dy": 0, "dz": 0, "speed": 2.0}
	await _setup(_room([], [cp, mover]), Vector3(2.5, 0.05, 4.5))
	var hits: Array = []
	pw.touched.connect(func(kind, _o): hits.append(kind))
	# Faster than the checkpoint is wide each tick: the swept path still meets it.
	body.velocity = Vector3(180, 0, 0)
	var before := body.global_position.x
	body.step(1.0 / 60.0)
	check(body.global_position.x - before > 1.5, "moved %.2f in one tick" % (body.global_position.x - before))
	await _phys(20)
	eq(hits.count("checkpoint"), 1, "passed straight through the checkpoint: touched once")
	# Stepping in touches it once and standing in it doesn't repeat; leaving and coming back does.
	hits.clear()
	pw.sweep_triggers(body, Vector3(8.6, 0.05, 4.5), Vector3(8.5, 0.05, 4.5))
	pw.sweep_triggers(body, Vector3(8.5, 0.05, 4.5), Vector3(8.5, 0.05, 4.5))
	pw.sweep_triggers(body, Vector3(8.5, 0.05, 4.5), Vector3(8.6, 0.05, 4.5))
	eq(hits.count("checkpoint"), 1, "standing in it: no repeats")
	pw.sweep_triggers(body, Vector3(8.6, 0.05, 4.5), Vector3(13.0, 0.05, 4.5))
	pw.sweep_triggers(body, Vector3(13.0, 0.05, 4.5), Vector3(8.5, 0.05, 4.5))
	eq(hits.count("checkpoint"), 2, "left, then came back: touched again")
	# A teleport (a respawn) isn't a path across the course.
	hits.clear()
	body.velocity = Vector3.ZERO
	body.move_dir = Vector3.ZERO
	body.teleport(Vector3(2.5, 0.05, 4.5))
	await _phys(3)
	body.teleport(Vector3(14.5, 0.05, 4.5))
	await _phys(3)
	eq(hits.size(), 0, "teleporting past it touches nothing")
	# Movers hold still while the mode is paused (menus, talking, fades).
	var ab: Node3D = pw.movers[0][0]
	pw.paused = true
	var at := ab.position
	await _phys(30)
	check(ab.position.distance_to(at) < 0.001, "paused: the moving platform waits")
	pw.paused = false
	await _phys(30)
	check(ab.position.distance_to(at) > 0.1, "unpaused: it moves again")
	await _teardown()


func test_chunk_colliders_are_merged() -> void:
	# A 32x32 field of cubes (two chunks wide): a handful of boxes, not 1024 bodies.
	var tiles: Array = []
	for x in 32:
		for z in 32:
			tiles.append(_cube(x, z))
	var r := {"size": {"w": 32, "d": 32, "h": 3}, "tiles": tiles, "objects": [], "tile_layers": TileLayers.default_layers()}
	var w: Node3D = PlatformWorld.new()
	tree.root.add_child(w)
	var t0 := Time.get_ticks_usec()
	w.build(r)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("    32x32 cubes -> %d boxes in %d bodies (%.1f ms)" % [w.box_count, w.body_count, ms])
	check(w.box_count <= 5 + 4 + 4, "merged per chunk: %d boxes" % w.box_count)
	check(w.body_count <= 8, "one body per chunk (+ floor, objects): %d" % w.body_count)
	eq(PlatformWorld.merge_cells({Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(0, 1): true}).size(), 2, "an L shape is two boxes")
	w.queue_free()
	await frames(1)
