extends Node
## Platform Mode: the second way to move through the same world. Started
## ONLY by activating a Platform Pillar (or the editor's "Play-test in
## Platform Mode"); left through the Exit Pillar that appears where you
## started, the always-visible Leave button, X, or Esc.
##
## While it's on: a capsule body (platform_body.gd) moves through the room's
## merged colliders (platform_world.gd), the player's sprite follows it with
## run/jump/fall poses (actor_anim.gd), the camera chases (camera_rig.gd
## follow mode), and touches do things: jump pads launch, soft hazards and
## the kill plane put you back at the last checkpoint after a gentle fade,
## checkpoints light up, Memory Shards are collected, doors still lead on
## (the mode carries over), pickups are picked up. No lives, no timers.
##
## Controls (one hand is always enough): WASD/arrows move, Space jumps, R
## toggles run, Q/E turn the camera, V first person, F interacts, Tab menu,
## X leaves. Mouse alone: hold the left button to run toward the pointer,
## click something to use it, on-screen Jump/Run/Leave. Phone: thumb stick
## (push fully = run), Jump button, tap to use, two fingers orbit.

signal started
signal ended

const Config := preload("res://scripts/platform/platform_config.gd")
const Profiles := preload("res://scripts/platform/platform_profiles.gd")
const PlatformWorld := preload("res://scripts/platform/platform_world.gd")
const PlatformBody := preload("res://scripts/platform/platform_body.gd")
const PlatformHud := preload("res://scripts/platform/platform_hud.gd")
const PlatformObjects := preload("res://scripts/platform/platform_objects.gd")
const PlatformSave := preload("res://scripts/platform/platform_save.gd")
const AnimState := preload("res://scripts/platform/anim_state.gd")
const Synth := preload("res://scripts/core/synth.gd")
const InputSetup := preload("res://scripts/core/input_setup.gd")
const TouchGestures := preload("res://scripts/ui/touch_gestures.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const Pickups := preload("res://scripts/items/pickups.gd")

var world: Node                    # game_world.gd
var active := false
var starting := false              # the ~1 s start cinematic
var pw: Node3D                     # platform_world.gd
var body: CharacterBody3D          # platform_body.gd
var hud: Control                   # platform_hud.gd
var exit_pillar: Node3D
var origin: Dictionary = {}        # {room, cell, pillar}: where Platform Mode began
var checkpoint: Dictionary = {}    # {room, pos}: where a fall puts you back
var anim := AnimState.new()
var assists: Dictionary = {}
var run_toggle := false
var test_input := Vector2.ZERO     # tests drive movement with this (x right, y forward)
var _pending_spawn: Variant = null # Vector2i after a pillar teleport
var _fading := false
var _mouse_down := false
var _mouse_t := 0.0
var _mouse_pos := Vector2.ZERO
var _rdrag := false
var _pointer := Vector2.ZERO       # where the mouse pointer is (from its events)
var _touch_t: Dictionary = {}      # finger -> [start time, start pos]
var _door_lock := 0.0


func setup(game_world: Node) -> void:
	world = game_world
	var saved: Variant = GameState.settings.get("platform_assists", {})
	assists = saved.duplicate() if saved is Dictionary else {}


func busy() -> bool:
	return active or starting


# --- Starting and leaving --------------------------------------------------------------------------

## A Platform Pillar was used (normal mode). Plays the cinematic, then starts here or in its destination.
func activate(pillar: Dictionary) -> void:
	if busy():
		return
	var room_id := GameState.current_room_id
	var id := str(pillar.get("id", ""))
	if not PlatformSave.enabled():
		world.talk.show_text("", "Platform Mode is switched off for this world (Menu > World settings).")
		return
	if str(pillar.get("repeat", "repeat")) == "once" and PlatformSave.pillar_used(room_id, id):
		world.talk.show_text("", "The pillar is quiet now. It only wakes once.")
		return
	PlatformSave.mark_pillar(room_id, id)
	var stand: Vector2i = world.player.cell()
	origin = {"room": room_id, "cell": stand, "pillar": id}
	PlatformSave.set_resume(room_id, stand)
	starting = true
	world.player.stop()
	await _cinematic(pillar)
	var target := str(pillar.get("target_room", ""))
	if target != "" and target != room_id and SaveManager.room_exists(target):
		var sp: Variant = pillar.get("target_spawn", [])
		_pending_spawn = Vector2i(int(sp[0]), int(sp[1])) if sp is Array and (sp as Array).size() == 2 else Vector2i(-1, -1)
		_begin(world.player.position + Vector3(0, 0.05, 0), true)
		starting = false
		world.go_to_room(target)   # load_room() calls on_room_loaded(): the mode carries over
	else:
		_begin(world.player.position + Vector3(0, 0.05, 0), false)
		starting = false


## Starts at the player's spot without a pillar (the editor's play-test toggle, tests).
func begin_here() -> void:
	if busy():
		return
	origin = {"room": GameState.current_room_id, "cell": world.player.cell(), "pillar": ""}
	_begin(world.player.position + Vector3(0, 0.05, 0), false)


## Flash, a ring burst from the pillar, a whoosh; the camera swoops in as the mode starts.
func _cinematic(pillar: Dictionary) -> void:
	var at: Vector3 = world.room.obj_position(pillar)
	var c := PlatformObjects.color_of({"type": "pillar", "color": str(pillar.get("color", ""))})
	PlatformObjects.burst(world, at, c)
	Synth.play(world, "whoosh", 0.5)
	Synth.play(world, "chime", 0.5)
	var flash := ColorRect.new()
	flash.color = Color(c.lightened(0.6), 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	world.main.ui.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.75, 0.18)
	tw.tween_property(flash, "color:a", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)
	world.cam.set_follow(true, true)
	await world.get_tree().create_timer(0.45).timeout


func _begin(at: Vector3, carry_to_other_room: bool) -> void:
	active = true
	world.player.stop()
	world.controller.hide_marker()
	_build_world()
	body = PlatformBody.new()
	body.name = "PlatformBody"
	body.world = pw
	world.add_child(body)
	body.teleport(at)
	body.fell_out.connect(respawn)
	body.landed.connect(_on_landed)
	body.jumped.connect(func(): Synth.play(world, "pop", 0.25))
	_apply_assists()
	world.player.anim.begin_manual()
	world.player.anim.on_step = _on_step
	if not world.cam.follow:
		world.cam.set_follow(true, false)
	world.hud.visible = false
	hud = PlatformHud.new()
	hud.name = "PlatformHud"
	world.main.ui.add_child(hud)
	hud.setup(TouchGestures.phone_layout(), str(GameState.settings.get("hand", "right")) == "left", assists)
	hud.jump_pressed.connect(jump)
	hud.jump_released.connect(func():
		if body: body.release_jump())
	hud.roll_pressed.connect(roll)
	hud.leave_pressed.connect(func(): leave(false))
	hud.run_toggled.connect(func(on): run_toggle = on)
	hud.camera_step.connect(func(d): world.cam.rotate_step(d))
	hud.first_person_toggled.connect(toggle_first_person)
	hud.assists_changed.connect(func(a):
		assists = a.duplicate()
		GameState.settings["platform_assists"] = assists.duplicate()
		GameState.save_settings()
		_apply_assists())
	hud.set_shards(PlatformSave.shard_count())
	_apply_profile()
	checkpoint = {"room": GameState.current_room_id, "pos": at}
	if not carry_to_other_room:
		_place_exit_pillar()
	started.emit()


func _build_world() -> void:
	if pw and is_instance_valid(pw):
		pw.free()
	pw = PlatformWorld.new()
	pw.name = "PlatformWorld"
	world.add_child(pw)
	pw.build(world.room.data)
	pw.touched.connect(_on_touched)
	if body:
		body.world = pw
	_sync_object_looks(true)


## Lit checkpoints glow, taken shards are gone, moving platforms move (the
## room's still copy hides while Platform Mode draws the moving one).
func _sync_object_looks(on: bool) -> void:
	var room_id := GameState.current_room_id
	for o in world.room.data.get("objects", []):
		var node: Node3D = world.room.object_nodes.get(str(o.get("id", "")))
		if node == null or not is_instance_valid(node):
			continue
		match str(o.get("type", "")):
			"mover":
				node.visible = not on
			"shard":
				node.visible = not PlatformSave.shard_taken(room_id, str(o.id))
			"checkpoint":
				_light(node, PlatformSave.checkpoint_lit(room_id, str(o.id)))


func _light(node: Node3D, on: bool) -> void:
	var lamp := node.find_child("Lamp", true, false) as MeshInstance3D
	if lamp and lamp.material_override:
		(lamp.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if on else 0.4


## The Exit Pillar stands one cell beside where you began (only in that room).
func _place_exit_pillar() -> void:
	if exit_pillar and is_instance_valid(exit_pillar):
		exit_pillar.queue_free()
	exit_pillar = null
	if GameState.current_room_id != str(origin.get("room", "")):
		return
	var cell: Vector2i = origin.get("cell", world.player.cell())
	var spot: Vector2i = world.room.nav.best_neighbor(cell, cell)
	if spot.x < 0:
		spot = cell
	exit_pillar = PlatformObjects.make({"type": "pillar", "color": "#7ad6b0", "label": "Exit"}, true)
	exit_pillar.name = "ExitPillar"
	for b in exit_pillar.find_children("*", "StaticBody3D", true, false):
		b.set_meta("kind", "exit_pillar")
	exit_pillar.position = world.room.cell_center(spot)
	exit_pillar.position.y = PlatformWorld.top_at(world.room.data, spot.x, spot.y)
	world.add_child(exit_pillar)


## Back to normal walking. Through the Exit Pillar after a pillar sent you to
## another room, you go back to where you started.
func leave(through_exit: bool = false) -> void:
	if not active:
		return
	active = false
	var back_home := through_exit and str(origin.get("room", "")) != GameState.current_room_id and SaveManager.room_exists(str(origin.get("room", "")))
	_teardown()
	if back_home:
		var c: Vector2i = origin.get("cell", Vector2i(-1, -1))
		PlatformSave.set_resume(str(origin.room), c)
		world.go_to_room(str(origin.room))
	else:
		PlatformSave.clear_resume()
		var cell: Vector2i = world.room.world_to_cell(world.player.position)
		if not world.room.nav.walkable(cell):
			cell = world.room.nav.nearest_walkable(cell)
		world.player.position = world.room.cell_center(cell)
		GameState.world["last_room"] = GameState.current_room_id
	Synth.play(world, "door", 0.4)
	ended.emit()


## The world is closing (quit, title screen, world switch): stop quietly. The
## resume spot stays, so next time you're back at the checkpoint/start, walking.
func shutdown() -> void:
	if not active:
		return
	active = false
	for n in [pw, body, hud, exit_pillar]:
		if n and is_instance_valid(n):
			n.queue_free()
	pw = null
	body = null
	hud = null
	exit_pillar = null


func _teardown() -> void:
	_sync_object_looks(false)
	for n in [pw, body, hud, exit_pillar]:
		if n and is_instance_valid(n):
			n.queue_free()
	pw = null
	body = null
	hud = null
	exit_pillar = null
	if is_instance_valid(world.player) and world.player.anim:
		world.player.anim.reset_sprite()
		world.player.anim.on_step = Callable()
	world.cam.set_follow(false)
	world.hud.visible = true
	run_toggle = false
	_mouse_down = false


## game_world.load_room() calls this after building a room. In Platform Mode
## the mode carries over (doors, pillar destinations); otherwise a save made
## during Platform Mode puts you on its resume spot.
func on_room_loaded(room_id: String, _from_room: String) -> void:
	if not active:
		var c := PlatformSave.take_resume(room_id)
		if c.x >= 0 and world.room.nav.walkable(c):
			world.player.position = world.room.cell_center(c)
		return
	_build_world()
	var at: Vector3 = world.player.position
	if _pending_spawn is Vector2i:
		var c: Vector2i = _pending_spawn
		if c.x < 0 or not world.room.nav.in_bounds(c):
			c = world.room.spawn_cell()
		at = world.room.cell_center(c)
		at.y = PlatformWorld.top_at(world.room.data, c.x, c.y)
		_pending_spawn = null
		origin["arrival"] = room_id
	body.teleport(at + Vector3(0, 0.05, 0))
	_apply_profile()
	world.player.position = body.global_position
	world.player.anim.begin_manual()
	world.player.anim.on_step = _on_step
	checkpoint = {"room": room_id, "pos": body.global_position}
	if room_id == str(origin.get("room", "")) or room_id == str(origin.get("arrival", "")):
		if room_id != str(origin.get("room", "")):
			origin["exit_room"] = room_id
		_place_exit_pillar_here(room_id)
	# A save or quit now resumes at the last checkpoint (or the start), in normal mode.
	var r: Variant = PlatformSave.data().get("resume")
	if r is Dictionary:
		GameState.world["last_room"] = str(r.get("room", room_id))
		GameState.save_world()


func _place_exit_pillar_here(room_id: String) -> void:
	if room_id == str(origin.get("room", "")):
		_place_exit_pillar()
		return
	# Sent here by a pillar: the Exit Pillar waits at the arrival spot (and takes you home).
	if exit_pillar and is_instance_valid(exit_pillar):
		exit_pillar.queue_free()
	var cell: Vector2i = world.room.world_to_cell(body.global_position)
	var spot: Vector2i = world.room.nav.best_neighbor(cell, cell)
	if spot.x < 0:
		spot = cell
	exit_pillar = PlatformObjects.make({"type": "pillar", "color": "#7ad6b0", "label": "Exit"}, true)
	exit_pillar.name = "ExitPillar"
	for b in exit_pillar.find_children("*", "StaticBody3D", true, false):
		b.set_meta("kind", "exit_pillar")
	exit_pillar.position = world.room.cell_center(spot)
	exit_pillar.position.y = PlatformWorld.top_at(world.room.data, spot.x, spot.y)
	world.add_child(exit_pillar)


func _apply_assists() -> void:
	if body:
		body.auto_jump = bool(assists.get("auto_jump", false))
		body.slow_fall = bool(assists.get("slow_fall", false))
	world.cam.assist = bool(assists.get("camera_assist", true))


func _apply_profile() -> void:
	var selected := Profiles.resolve(world.room.data)
	var axis := Vector3.BACK if Profiles.plane(world.room.data) == "z" else Vector3.RIGHT
	body.set_profile(str(selected.id), axis)
	world.cam.set_side_view(axis if selected.id == "classic" else Vector3.ZERO)
	if hud:
		hud.set_profile(str(selected.id), str(selected.note))
	if str(selected.note) != "":
		GameState.notify(str(selected.note))


# --- Every frame ------------------------------------------------------------------------------------

func _blocked() -> bool:
	return world._transitioning or world.talk.is_open() or not world.main.panels.is_empty() or _fading or starting


func _physics_process(_delta: float) -> void:
	if not active or body == null:
		return
	body.frozen = _blocked()
	if pw:
		pw.paused = body.frozen   # moving platforms hold still with you (menus, talk, fades)
	if body.frozen:
		return
	var input := test_input
	if input == Vector2.ZERO and not InputSetup.typing(world.get_viewport()):
		input = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	var stick_run := false
	if hud and hud.stick and hud.stick.touching():
		input = Vector2(hud.stick.vector.x, -hud.stick.vector.y)
		stick_run = hud.stick.running
	var mouse_run := false
	var dir := Vector3.ZERO
	if input == Vector2.ZERO and _mouse_down and Time.get_ticks_msec() / 1000.0 - _mouse_t > 0.18:
		dir = _toward_pointer()
		mouse_run = dir != Vector3.ZERO
	if input == Vector2.ZERO and dir == Vector3.ZERO and bool(assists.get("auto_run", false)):
		if body.profile == "classic":
			input.x = 1.0
		else:
			input.y = 1.0
	if dir == Vector3.ZERO:
		dir = body.plane_axis * input.x if body.profile == "classic" else world.cam.flat_right() * input.x + world.cam.flat_forward() * input.y
	body.move_dir = dir.limit_length(1.0)
	body.run = run_toggle or stick_run or mouse_run
	_door_lock = maxf(0.0, _door_lock - _delta)


func _process(delta: float) -> void:
	if not active or body == null or not is_instance_valid(world.player):
		return
	world.player.position = body.global_position
	var vel: Vector3 = body.velocity
	var s := anim.update(vel, body.is_on_floor(), body.run, delta)
	var side := Vector3(vel.x, 0, vel.z).dot(world.cam.camera.global_transform.basis.x)
	world.player.anim.set_state(s, side if absf(side) > 0.3 else 0.0)
	world.cam.move_hint = Vector3(vel.x, 0, vel.z)
	if hud:
		hud.set_roll_state(body.charging, body.rolling)


## The point on the player's height under the mouse pointer, as a direction.
func _toward_pointer() -> Vector3:
	var cam: Camera3D = world.cam.camera
	var mp := _pointer
	var from := cam.project_ray_origin(mp)
	var n := cam.project_ray_normal(mp)
	if absf(n.y) < 0.001:
		return Vector3.ZERO
	var t := (body.global_position.y - from.y) / n.y
	if t <= 0.0:
		return Vector3.ZERO
	var d := from + n * t - body.global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.4 else Vector3.ZERO


func jump() -> void:
	if body and not _blocked():
		body.press_jump()


func roll() -> void:
	if body and not _blocked():
		body.roll_or_charge()


func toggle_first_person() -> void:
	if body and body.profile == "classic":
		return
	world.cam.first_person = not world.cam.first_person
	world.player.sprite.visible = not world.cam.first_person


# --- Input -----------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if active and body and event.is_action_released("plat_jump"):
		body.release_jump()
	if not active or _blocked():
		return
	if not InputSetup.typing(world.get_viewport()) and not event.is_echo():
		for action in ["plat_jump", "plat_run", "plat_roll", "plat_cam_left", "plat_cam_right", "plat_first_person", "plat_interact", "plat_leave", "plat_menu"]:
			if not event.is_action_pressed(action):
				continue
			match action:
				"plat_jump": jump()
				"plat_roll": roll()
				"plat_run":
					run_toggle = not run_toggle
					if hud: hud.set_run(run_toggle)
				"plat_cam_left": world.cam.rotate_step(-1)
				"plat_cam_right": world.cam.rotate_step(1)
				"plat_first_person": toggle_first_person()
				"plat_interact": interact()
				"plat_leave": leave(false)
				"plat_menu": world.open_menu()
			world.get_viewport().set_input_as_handled()
			return
	if event is InputEventMouse:
		_pointer = event.position
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION and TouchGestures.phone_layout():
			return   # phones: taps come as touches below
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_mouse_down = true
					_mouse_t = Time.get_ticks_msec() / 1000.0
					_mouse_pos = event.position
				else:
					var quick: bool = Time.get_ticks_msec() / 1000.0 - _mouse_t < 0.25 and event.position.distance_to(_mouse_pos) < 14.0
					_mouse_down = false
					if quick:
						tap_at(event.position)
			MOUSE_BUTTON_RIGHT:
				_rdrag = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					world.cam.zoom(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					world.cam.zoom(1)
		world.get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _rdrag:
		world.cam.orbit(event.relative.x, event.relative.y)
		world.get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touch_t[event.index] = [Time.get_ticks_msec() / 1000.0, event.position]
		elif _touch_t.has(event.index):
			var st: Array = _touch_t[event.index]
			_touch_t.erase(event.index)
			if Time.get_ticks_msec() / 1000.0 - float(st[0]) < 0.3 and event.position.distance_to(st[1]) < 16.0 and _touch_t.is_empty():
				tap_at(event.position)


## Click / tap: use what's under it if it's close; otherwise nothing.
func tap_at(screen_pos: Vector2) -> void:
	var hit: Dictionary = world.controller.raycast(screen_pos)
	if hit.is_empty():
		return
	var col: Object = hit.collider
	var kind := str(col.get_meta("kind", ""))
	if kind == "exit_pillar":
		if body.global_position.distance_to(exit_pillar.global_position) < 3.0:
			leave(true)
		else:
			world.hud.set_hint("Walk over to the Exit Pillar first.")
		return
	if kind in ["character", "object"] and hit.position.distance_to(body.global_position) < 3.0:
		interact()


## F / tap: the closest thing within reach.
func interact() -> void:
	var pos: Vector3 = body.global_position
	if exit_pillar and is_instance_valid(exit_pillar) and Vector2(exit_pillar.global_position.x - pos.x, exit_pillar.global_position.z - pos.z).length() < 1.8:
		leave(true)
		return
	var best_id := ""
	var best_d := 1.8
	for id in world.actors:
		var dd: float = world.actors[id].position.distance_to(pos)
		if dd < best_d:
			best_d = dd
			best_id = id
	if best_id != "":
		world.talk.talk_to(best_id)
		return
	var best_obj := {}
	best_d = 1.8
	for o in world.room.data.get("objects", []):
		var dd: float = world.room.obj_position(o).distance_to(pos)
		if dd < best_d:
			best_d = dd
			best_obj = o
	if best_obj.is_empty():
		return
	match str(best_obj.get("type", "")):
		"door":
			_through_door(best_obj)
		"pickup":
			if Pickups.available(best_obj):
				world.controller.collect_pickup(best_obj)
		"platform_pillar":
			world.hud.set_hint("You're already in Platform Mode.")
		_:
			var text := str(best_obj.get("interaction_text", "")).strip_edges()
			if text != "":
				world.talk.show_text("", text)


# --- Touches ---------------------------------------------------------------------------------------

func _on_touched(kind: String, o: Dictionary) -> void:
	if not active or _blocked():
		return
	var room_id := GameState.current_room_id
	match kind:
		"jump_pad":
			body.launch(float(o.get("strength", Config.JUMP_PAD_STRENGTH)))
			Synth.play(world, "boing", 0.5)
		"hazard":
			respawn()
		"checkpoint":
			var cell: Vector2i = world.room.obj_cell(o)
			checkpoint = {"room": room_id, "pos": PlatformWorld.object_base(o) + Vector3(0, 0.05, 0)}
			var node: Node3D = world.room.object_nodes.get(str(o.get("id", "")))
			if node:
				_light(node, true)
			if PlatformSave.light_checkpoint(room_id, str(o.get("id", "")), cell):
				Synth.play(world, "chime", 0.5)
				GameState.notify("✦ Checkpoint")
		"shard":
			if PlatformSave.take_shard(room_id, str(o.get("id", ""))):
				var node: Node3D = world.room.object_nodes.get(str(o.get("id", "")))
				if node:
					node.visible = false
				Synth.play(world, "sparkle", 0.6)
				load("res://scripts/variety/almanac.gd").on_shard(o, room_id)   # its memory goes into the Memory Book
				var n := PlatformSave.shard_count()
				var memory := str(o.get("memory", "")).strip_edges()
				GameState.notify("✦ Memory Shard found! (%d)%s" % [n, (": " + memory) if memory != "" else ""])
				if hud:
					hud.set_shards(n)
		"door":
			_through_door(o)
		"edge":
			if _door_lock <= 0.0 and not world._transitioning:
				_door_lock = 1.5
				var cell: Vector2i = world.room.world_to_cell(body.global_position)
				cell = Vector2i(clampi(cell.x, 0, world.room.w - 1), clampi(cell.y, 0, world.room.d - 1))
				world.cross_edge(str(o.get("side", "")), cell)
		"pickup":
			if Pickups.available(o):
				world.controller.collect_pickup(o)


func _through_door(o: Dictionary) -> void:
	var target := str(o.get("door_target", ""))
	if _door_lock > 0.0 or world._transitioning or target == "" or not SaveManager.room_exists(target):
		return
	_door_lock = 1.5
	Synth.play(world, "door")
	world.go_to_room(target)


## A gentle fade back to the last checkpoint (or where you started). No penalty.
func respawn() -> void:
	if _fading or body == null:
		return
	_fading = true
	body.frozen = true
	var fade: ColorRect = world._fade
	var tw := world.create_tween()
	tw.tween_property(fade, "color:a", 0.85, Config.RESPAWN_FADE)
	await tw.finished
	if body:
		var at: Vector3 = checkpoint.get("pos", body.global_position) if str(checkpoint.get("room", "")) == GameState.current_room_id else world.room.cell_center(world.room.spawn_cell())
		body.teleport(at)
		world.player.position = at
	var tw2 := world.create_tween()
	tw2.tween_property(fade, "color:a", 0.0, Config.RESPAWN_FADE)
	await tw2.finished
	_fading = false


func _on_landed(speed: float) -> void:
	if speed > 6.0:
		Synth.play(world, "land", 0.4)


## A footstep: the sound of the ground tile underfoot (its "step sound").
func _on_step(_state: String) -> void:
	if body == null or not body.is_on_floor():
		return
	var cell := Vector2i(floori(body.global_position.x), floori(body.global_position.z))
	var kind := "soft"
	var g := TileLayers.of_type(world.room.data, "ground")
	if not g.is_empty() and body.global_position.y < 0.3:
		var c := TileLayers.get_cell(g, cell.x, cell.y)
		if not c.is_empty():
			var st := str(Tilesets.info(str(c.s), str(c.t)).get("step", ""))
			if st != "":
				kind = st
	Synth.play(world, "step_" + kind, 0.18)
