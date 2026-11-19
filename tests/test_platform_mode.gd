extends "res://tests/test_case.gd"
## Phase 17: Platform Mode in the real game scene. A Platform Pillar starts
## it (UI, camera, Exit Pillar), Leave and the Exit Pillar end it, it carries
## over a room change, checkpoints catch falls, shards and checkpoints are
## remembered (and a save during the mode resumes at the checkpoint, walking),
## the animation states, the thumb stick, and the editor's play-test toggle.

const PlatformSave := preload("res://scripts/platform/platform_save.gd")
const AnimState := preload("res://scripts/platform/anim_state.gd")
const Joystick := preload("res://scripts/platform/joystick.gd")
const Config := preload("res://scripts/platform/platform_config.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const ActorAnim := preload("res://scripts/characters/actor_anim.gd")

var main: Node


func _start() -> Node:
	fresh_save_root()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(5)
	return main.game


func _stop() -> void:
	main.queue_free()
	await frames(3)


## Puts a Platform Pillar (and anything else) in the current room and reloads it.
func _add(g: Node, objs: Array) -> Array:
	var data: Dictionary = g.room.data
	var made: Array = []
	for spec in objs:
		var o := RoomEditor.add_object(data, int(spec[1]), int(spec[2]), str(spec[0]))
		check(not o.is_empty(), "placed %s at %d,%d" % [spec[0], spec[1], spec[2]])
		if spec.size() > 3:
			o.merge(spec[3], true)
		made.append(o)
	SaveManager.save_room(data)
	g.load_room(GameState.current_room_id)
	await frames(3)
	var out: Array = []
	for o in made:
		out.append(g.room.find_object(str(o.id)))
	return out


func _activate(g: Node, pillar: Dictionary) -> void:
	g.platform.activate(pillar)
	for i in 120:
		await frames(1)
		if g.platform.active and not g.platform.starting:
			break
	await frames(3)


func test_profiles_reach_the_live_body_hud_camera_and_gamepad() -> void:
	var g := await _start()
	GameState.settings["platform_profile"] = "adventure"
	g.platform.begin_here()
	eq(g.platform.body.profile, "polox", "legacy course ignores player preference")
	g.platform.leave()
	g.room.data["physics_profile"] = "classic"
	g.room.data["platform_plane"] = "z"
	g.platform.begin_here()
	eq(g.platform.body.profile, "classic")
	eq(g.platform.body.plane_axis, Vector3.BACK, "course Z plane reaches the body")
	eq(g.cam.side_axis, Vector3.BACK, "Classic uses a side camera")
	check(g.platform.hud.find_child("RollCharge", true, false).visible, "one-handed roll control is available")
	g.platform.toggle_first_person()
	check(not g.cam.first_person, "Classic retains its readable side view")
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_X
	event.pressed = true
	g.platform._unhandled_input(event)
	check(g.platform.run_toggle, "gamepad Run reaches platform mode")
	g.platform.body.velocity.y = 9.0
	var release := InputEventAction.new()
	release.action = "plat_jump"
	release.pressed = false
	g.platform._unhandled_input(release)
	# (Vector3 holds 32-bit floats: 4.4 comes back as 4.4000001.)
	check(g.platform.body.velocity.y <= 4.4 + 0.001, "jump release cuts the Classic jump (vy %.2f, profile %s)" % [g.platform.body.velocity.y, g.platform.body.profile])
	g.platform.leave()
	g.room.data["physics_profile"] = "player"
	g.platform.begin_here()
	eq(g.platform.body.profile, "adventure", "opted-in course uses player's setting")
	eq(g.cam.side_axis, Vector3.ZERO, "Adventure restores free camera")
	g.platform.leave()
	g.room.data["physics_profile"] = "classic"
	g.room.data.erase("platform_plane")
	g.platform.begin_here()
	eq(g.platform.body.profile, "polox", "missing plane never traps the player on an arbitrary axis")
	check(not g.platform.hud.find_child("RollCharge", true, false).visible)
	await _stop()


func test_course_physics_editor_keeps_and_undoes_metadata() -> void:
	var g := await _start()
	g.build.enter()
	var palette := preload("res://scripts/builder/editor_palette.gd").new()
	palette.build = g.build
	palette._course_panel()
	var panel: Control = main.panels[-1]
	(panel.find_child("CourseProfile", true, false) as OptionButton).select(1)
	(panel.find_child("CoursePlane", true, false) as OptionButton).select(1)
	for button in panel.find_children("*", "Button", true, false):
		if button.text == "Keep":
			button.pressed.emit()
			break
	eq(str(g.room.data.get("physics_profile", "")), "classic", "course choice reaches live room")
	eq(str(g.room.data.get("platform_plane", "")), "x", "plane saved with profile")
	g.build.undo()
	check(not g.room.data.has("physics_profile"), "one Undo restores original course metadata")
	g.build.redo()
	eq(str(g.room.data.get("physics_profile", "")), "classic")
	g.build.flush_save()
	eq(str(SaveManager.load_room(GameState.current_room_id).get("platform_plane", "")), "x", "plane survives disk reload")
	palette.free()
	await _stop()


func test_pillar_starts_it_and_leave_ends_it() -> void:
	var g := await _start()
	var objs := await _add(g, [["platform_pillar", 3, 3, {"label": "Sky Steps"}]])
	var pillar: Dictionary = objs[0]
	check(not g.platform.active, "no Platform Mode without a pillar")
	await _activate(g, pillar)
	check(g.platform.active, "activating the pillar starts Platform Mode")
	check(g.platform.hud != null and g.platform.hud.visible and not g.hud.visible, "Platform controls replace the normal HUD")
	check(g.cam.follow, "the camera follows (third person)")
	check(g.platform.exit_pillar != null and is_instance_valid(g.platform.exit_pillar), "an Exit Pillar appeared where you started")
	check(PlatformSave.pillar_used(GameState.current_room_id, str(pillar.id)), "the pillar is remembered as woken")
	check(g.player.anim.manual, "the player's sprite runs on the animation states")
	# Moving with input.
	var start: Vector3 = g.platform.body.global_position
	g.platform.test_input = Vector2(0, 1)
	for i in 40:
		await tree.physics_frame
	g.platform.test_input = Vector2.ZERO
	check(g.platform.body.global_position.distance_to(start) > 0.8, "input moves the body (%.2f)" % g.platform.body.global_position.distance_to(start))
	check(g.player.position.distance_to(g.platform.body.global_position) < 0.01, "and the sprite follows it")
	# The Leave button.
	g.platform.hud.leave_pressed.emit()
	await frames(3)
	check(not g.platform.active, "Leave ends it")
	check(g.hud.visible and not g.cam.follow, "normal HUD and camera are back")
	check(g.room.nav.walkable(g.player.cell()), "standing on a walkable cell again")
	check(not g.player.anim.manual, "plain sprite again")
	check(not PlatformSave.data().has("resume"), "nothing left to resume")
	# Normal control works again: the grid controller isn't blocked.
	check(not g.controller._blocked(), "normal controls are back")
	await _stop()


func test_exit_pillar_and_once_pillars() -> void:
	var g := await _start()
	var objs := await _add(g, [["platform_pillar", 3, 3, {"repeat": "once"}]])
	await _activate(g, objs[0])
	check(g.platform.active, "on")
	g.platform.body.teleport(g.platform.exit_pillar.global_position + Vector3(0.9, 0.05, 0))
	await tree.physics_frame
	g.platform.interact()
	await frames(3)
	check(not g.platform.active, "F next to the Exit Pillar leaves Platform Mode")
	g.platform.activate(objs[0])
	await frames(5)
	check(not g.platform.active and not g.platform.starting, "a once-only pillar stays quiet the second time")
	await _stop()


func test_room_change_checkpoint_respawn_shards_and_resume() -> void:
	var g := await _start()
	var objs := await _add(g, [["platform_pillar", 3, 3], ["checkpoint", 6, 3], ["shard", 7, 5]])
	var cp: Dictionary = objs[1]
	var shard: Dictionary = objs[2]
	await _activate(g, objs[0])
	# A checkpoint, then a soft hazard: back at the checkpoint after a fade.
	g.platform.pw.touched.emit("checkpoint", cp)
	await frames(2)
	check(not PlatformSave.last_checkpoint().is_empty() and str(PlatformSave.last_checkpoint().id) == str(cp.id), "the checkpoint is remembered")
	g.platform.body.teleport(Vector3(2.5, 0.05, 6.5))
	await tree.physics_frame
	g.platform.pw.touched.emit("hazard", {"id": "x", "type": "hazard"})
	for i in 60:
		await frames(1)
		if not g.platform._fading:
			break
	var at: Vector3 = g.platform.body.global_position
	check(Vector2(at.x, at.z).distance_to(Vector2(6.5, 3.5)) < 0.6, "a hazard puts you back at the checkpoint (%s)" % str(at))
	check(g.platform.active, "still in Platform Mode (no lives, no game over)")
	# The kill plane does the same.
	g.platform.body.teleport(Vector3(2.5, -7.0, 2.5))
	for i in 60:
		await tree.physics_frame
		if not g.platform._fading and g.platform.body.global_position.y > -1.0:
			break
	check(g.platform.body.global_position.y > -1.0, "falling out of the room: back at the checkpoint")
	# A Memory Shard.
	g.platform.pw.touched.emit("shard", shard)
	await frames(2)
	eq(PlatformSave.shard_count(), 1, "a Memory Shard collected")
	g.platform.pw.touched.emit("shard", shard)
	eq(PlatformSave.shard_count(), 1, "only once")
	# Through a door: the mode carries over to the next room.
	var garden := "garden"
	check(SaveManager.room_exists(garden), "the starter garden exists")
	g.go_to_room(garden)
	for i in 200:
		await frames(1)
		if not g._transitioning and GameState.current_room_id == garden:
			break
	await frames(4)
	check(GameState.current_room_id == garden and g.platform.active, "Platform Mode survives a room change")
	check(g.platform.pw != null and g.platform.pw.room.get("id", "") == garden, "the new room's colliders were built")
	check(g.player.anim.manual, "the new room's player sprite is in Platform Mode too")
	# A save now resumes next time in normal mode at the checkpoint.
	g.platform.checkpoint = {"room": garden, "pos": g.platform.body.global_position}
	var spot: Vector2i = g.room.nav.nearest_walkable(Vector2i(2, 2))
	PlatformSave.set_resume(GameState.current_room_id, spot)
	GameState.save_world()
	main.start_game()   # what happens after a quit + start: the world loads again
	for i in 30:
		await frames(1)
	var g2: Node = main.game
	check(g2 != null and not g2.platform.active, "a fresh start is in normal mode (never mid-air)")
	eq(g2.player.cell(), spot, "on the resume spot")
	eq(PlatformSave.shard_count(), 1, "shards are still collected after reloading")
	eq((PlatformSave.data().checkpoints as Array).size(), 1, "checkpoints too")
	await _stop()


func test_animation_states_frames_and_generated_motion() -> void:
	var a := AnimState.new()
	eq(a.update(Vector3.ZERO, true, false, 0.016), "idle", "standing: idle")
	eq(a.update(Vector3(3, 0, 0), true, false, 0.016), "walk", "moving: walk")
	eq(a.update(Vector3(7, 0, 0), true, true, 0.016), "run", "fast with run on: run")
	eq(a.update(Vector3(7, 8, 0), false, true, 0.016), "jump", "going up: jump")
	eq(a.update(Vector3(7, -3, 0), false, true, 0.016), "fall", "coming down: fall")
	eq(a.update(Vector3(0, 0, 0), true, true, 0.016), "land", "touching down: land")
	for i in 20:
		a.update(Vector3.ZERO, true, false, 0.016)
	eq(a.state, "idle", "then idle again")
	# Frames: custom ones are used when present, generated motion otherwise.
	fresh_save_root()
	var Actor: GDScript = load("res://scripts/characters/actor.gd")
	var base := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	var act: Node3D = Actor.new()
	tree.root.add_child(act)
	act.setup("t", "T", base, true)
	var run_img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	run_img.fill(Color.RED)
	JsonUtil().ensure_dir(SaveManager.root.path_join("player"))
	run_img.save_png(SaveManager.root.path_join("player/run_0.png"))
	act.anim.load_frames({"run": {"frames": [SaveManager.root.path_join("player/run_0.png")], "fps": 8, "loop": true}})
	check(act.anim.has_custom("run"), "custom run frames loaded")
	act.anim.begin_manual()
	act.anim.set_state("run", 1.0)
	await frames(2)
	check(act.sprite.texture != base, "running shows the custom run frame")
	act.anim.set_state("jump", -1.0)
	await tree.create_timer(0.35).timeout
	eq(act.sprite.texture, base, "no jump frames: the base picture...")
	check(act.sprite.scale.y > 1.05 and act.sprite.flip_h, "...stretched by the generated motion, mirrored to face left")
	act.anim.set_state("walk", 1.0)
	await tree.create_timer(0.1).timeout
	check(not act.sprite.flip_h, "mirrored back when facing right")
	act.anim.reset_sprite()
	check(act.sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "leaving restores the billboard")
	act.queue_free()
	await frames(1)


func JsonUtil() -> GDScript:
	return load("res://scripts/core/json_util.gd")


func test_thumb_stick_mapping() -> void:
	var c := Vector2(200, 600)
	eq(Joystick.value_for(c, c), Vector2.ZERO, "centre: still")
	var rim := Joystick.value_for(c + Vector2(Config.JOYSTICK_RADIUS, 0), c)
	check(is_equal_approx(rim.length(), 1.0) and rim.x > 0.99, "pushed to the rim: full right")
	check(is_equal_approx(Joystick.value_for(c + Vector2(0, -Config.JOYSTICK_RADIUS * 3.0), c).length(), 1.0), "beyond the rim: clamped")
	check(not Joystick.runs(Joystick.value_for(c + Vector2(Config.JOYSTICK_RADIUS * 0.5, 0), c)), "half way: walk")
	check(Joystick.runs(Joystick.value_for(c + Vector2(Config.JOYSTICK_RADIUS * 0.95, 0), c)), "nearly all the way: run")
	# Up on the stick = forward for the body.
	var v := Joystick.value_for(c + Vector2(0, -Config.JOYSTICK_RADIUS), c)
	eq(Vector2(v.x, -v.y), Vector2(0, 1), "stick up means forward")


func test_play_test_toggle_starts_platform_mode() -> void:
	var g := await _start()
	g.build.enter()
	await frames(2)
	g.build.play_platform = true
	g.build.cursor = g.player.cell()
	g.build.play_test()
	await frames(3)
	check(g.platform.active, "Play-test with \"in Platform Mode\" starts it without a pillar")
	g.platform.leave(false)
	await frames(2)
	PlatformSave.set_enabled(false)
	var objs := await _add(g, [["platform_pillar", 3, 3]])
	g.platform.activate(objs[0])
	await frames(3)
	check(not g.platform.active, "switched off for the world: the pillar does nothing")
	PlatformSave.set_enabled(true)
	await _stop()
