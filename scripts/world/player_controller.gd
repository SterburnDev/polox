extends Node
## Turns clicks and keys into the player's actions: walking (camera-relative
## steering or click-to-walk), talking to friends, using signs and doors,
## picking things up, and the camera wheel. Build mode gets the input instead
## while it's active.
##
## Steering (keys, the gamepad stick, IJKL for left hands) is continuous and
## runs in physics ticks: camera-relative, analog (a half-pushed stick walks
## slower), the same speed diagonally, a gentle start and stop, sliding along
## whatever blocks one axis, a small nudge into doorways, and the same
## clearance rule as click paths (grid_nav.gd: solid cells, corners, thin
## walls). Clicked destinations stay exact; clicked routes are smoothed into
## straight runs where the way is clear, and any steering cancels them.
## Ordinary walking stays walking: Platform Mode has its own body and rules.

const InputSetup := preload("res://scripts/core/input_setup.gd")
const Synth := preload("res://scripts/core/synth.gd")
const Pickups := preload("res://scripts/items/pickups.gd")
const TileEvents := preload("res://scripts/world/tile_events.gd")
const Places := preload("res://scripts/world/places.gd")

const FOOT := 0.16                 # footprint radius (blocks) for steering and smoothed routes
const ACCEL := 16.0                # blocks/s² to walking speed (0.21 s at 3.4)
const DECEL := 22.0                # blocks/s² to a stop (about a quarter block)
const REVERSE := 34.0              # turning back is prompt
const DOOR_REACH := 0.38           # how near a door cell's centre steering must come to use it
const NOWHERE := Vector2i(-99999, -99999)

var world: Node              # game_world.gd
var velocity := Vector3.ZERO       # steering velocity (blocks/s, flat)
var touch_input := Vector2.ZERO    # the phone's thumb stick, like Input.get_vector (x right, y back)
var unreachable_count := 0         # (tests) how often a destination was out of reach
var _pending: Callable = Callable()
var _marker: MeshInstance3D
var _wait_neutral := false
var _suspended := false
var _was_blocked := false
var _edge_carry := false           # this controller started an edge crossing: keep walking after it
var _player_id := 0
var _cell := NOWHERE               # the cell steering last stood in (cell-entry events)
var _door_used := NOWHERE          # a door cell already used until you step out of it
var _last_pos := Vector3.INF


func setup(game_world: Node) -> void:
	world = game_world
	_marker = _make_marker()
	world.add_child(_marker)


## Who owns movement right now ("" = the player). Anything else consumes it.
func block_reason() -> String:
	if _suspended:
		return "suspended"
	if InputSetup.typing(get_viewport()):
		return "typing"
	if world._transitioning:
		return "transition"
	if world.talk.is_open():
		return "dialogue"
	if not world.main.panels.is_empty():
		return "panel"
	if world.platform != null and world.platform.busy():
		return "platform"
	if world.battles and world.battles.screen != null:
		return "battle"
	return ""


func _blocked() -> bool:
	return block_reason() != ""


## Steering is also off while building, editing your room or dragging something.
func steer_block() -> String:
	var r := block_reason()
	if r != "":
		return r
	if world.build and world.build.active:
		return "build"
	if world.get("decor") != null and is_instance_valid(world.decor) and world.decor.active:
		return "decor"
	if get_viewport().gui_is_dragging():
		return "drag"
	return ""


## Something else took the controls: forget the route and its callback, stop,
## and wait for the direction keys to be let go before steering again.
func cancel_input() -> void:
	_wait_neutral = true
	_pending = Callable()
	velocity = Vector3.ZERO
	if is_instance_valid(_marker):
		_marker.visible = false
	if world and is_instance_valid(world.player):
		world.player.stop()
	if world and world.cam:
		world.cam.walk_hint = Vector3.ZERO


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_suspended = true
		cancel_input()
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		_suspended = false


func hide_marker() -> void:
	_marker.visible = false
	_pending = Callable()


func _unhandled_input(event: InputEvent) -> void:
	if _blocked():
		return
	if world.build.active:
		world.build.handle_input(event)
		var wheel_event: bool = event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		var cam_event := event.is_action_pressed("cam_left") or event.is_action_pressed("cam_right") or event.is_action_pressed("zoom_in") or event.is_action_pressed("zoom_out")
		if not wheel_event and not cam_event:
			return  # the wheel still zooms/rotates the camera while building
	if event is InputEventMouseButton and event.pressed:
		var step := 0
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				click(event.position)
			MOUSE_BUTTON_WHEEL_UP:
				step = -1
			MOUSE_BUTTON_WHEEL_DOWN:
				step = 1
		if step != 0:
			if str(GameState.settings.get("wheel_mode", "zoom")) == "rotate":
				world.cam.rotate_step(step)
			else:
				world.cam.zoom(step)
	elif event.is_action_pressed("cam_left") or event.is_action_pressed("cam_right"):
		world.cam.rotate_step(-1 if event.is_action_pressed("cam_left") else 1)
	elif event.is_action_pressed("zoom_in") or event.is_action_pressed("zoom_out"):
		world.cam.zoom(-1 if event.is_action_pressed("zoom_in") else 1)
	elif event.is_action_pressed("menu") and not InputSetup.typing(get_viewport()):
		world.open_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm") and not InputSetup.typing(get_viewport()):
		interact_nearest()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("bag") and not InputSetup.typing(get_viewport()):
		world.open_bag()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("switch_form") and not InputSetup.typing(get_viewport()):
		world.switch_form()
		get_viewport().set_input_as_handled()


# --- Steering ----------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if world == null or not is_instance_valid(world.player):
		return
	var player: Node3D = world.player
	_track_player()
	var reason := steer_block()
	if reason != "":
		if not _was_blocked:
			_lose_ownership(reason)
		_was_blocked = true
		velocity = Vector3.ZERO
		world.cam.walk_hint = Vector3.ZERO
		if player.steering:
			player.set_steering_motion(Vector3.ZERO)
		_last_pos = Vector3.INF
		return
	_was_blocked = false
	_edge_carry = false
	player.physics_sync()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if touch_input.length() > input.length():
		input = touch_input.limit_length(1.0)   # the phone's thumb stick (touch_stick.gd)
	if _wait_neutral:
		if input.length() < 0.01:
			_wait_neutral = false
		input = Vector2.ZERO
	var dir := camera_dir(input)
	if player.is_moving() and not player.steering:
		if dir.length() < 0.01:
			_hint_from_motion(player, delta)
			return   # a clicked route is walking itself (actor.gd)
		_cancel_route()   # your own steering wins over a clicked route, at once
	steer(dir, delta)
	player.physics_commit()
	_hint_from_motion(player, delta)


## Input (x right, y down/back as Input.get_vector gives it) -> a flat world direction from the
## camera's settled yaw, length = how far the stick is pushed (keys = 1, diagonals too).
func camera_dir(input: Vector2) -> Vector3:
	if input.length_squared() < 0.0001:
		return Vector3.ZERO
	var yaw := deg_to_rad(world.cam.yaw_steps * 45.0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	return (right * input.x - fwd * input.y).limit_length(1.0)


## One physics tick of steering toward `dir` (length 0..1).
func steer(dir: Vector3, delta: float) -> void:
	var player: Node3D = world.player
	var target := dir * float(player.speed)
	var rate := ACCEL
	if target.length_squared() < 0.0001:
		rate = DECEL
	elif velocity.dot(target) < 0.0:
		rate = REVERSE
	velocity = velocity.move_toward(target, rate * delta)
	if velocity.length_squared() < 0.000001:
		velocity = Vector3.ZERO
		if player.steering:
			player.set_steering_motion(Vector3.ZERO)
		return
	var from := Vector2(player.position.x, player.position.z)
	var motion := Vector2(velocity.x, velocity.z) * delta
	var side := _edge_push(from, motion)
	if side != "":
		_edge_carry = true
		world.cross_edge(side, player.cell())   # walked into a joined edge: the next place
		return
	var to := _slide(from, motion)
	player.position = Vector3(to.x, player.position.y, to.y)
	var moved := Vector3(to.x - from.x, 0, to.y - from.y)
	player.set_steering_motion(moved / maxf(delta, 0.0001) if moved.length() > 0.00001 else Vector3.ZERO)
	_entered(player)


## The motion if it's clear; otherwise each axis on its own (the larger first), as far as it goes;
## stuck against a doorway's frame: a nudge toward the lane it opens from.
func _slide(from: Vector2, motion: Vector2) -> Vector2:
	var nav: RefCounted = world.room.nav
	var r := FOOT if nav.occupiable(from, FOOT) else 0.0   # (squeezed in by something else: let it step out)
	if nav.segment_clear(from, from + motion, r):
		return from + motion
	var parts := [Vector2(motion.x, 0), Vector2(0, motion.y)]
	if absf(motion.y) > absf(motion.x):
		parts.reverse()
	var at := from
	for part in parts:
		if part.length_squared() < 1e-12:
			continue
		var ok := _clear_fraction(nav, at, part, r)
		at += part * ok
		if ok < 1.0:
			if absf(part.x) > 0.0:
				velocity.x = 0.0
			else:
				velocity.z = 0.0
	if at.distance_squared_to(from) < 1e-10:
		at = _corner_assist(nav, from, motion, r)
	return at


## How much of `part` (0..1) can be walked from `at` (bisected, so you stop right at the obstacle).
func _clear_fraction(nav: RefCounted, at: Vector2, part: Vector2, r: float) -> float:
	if nav.segment_clear(at, at + part, r):
		return 1.0
	var lo := 0.0
	var hi := 1.0
	for i in 5:
		var mid := (lo + hi) * 0.5
		if nav.segment_clear(at, at + part * mid, r):
			lo = mid
		else:
			hi = mid
	return lo


func _corner_assist(nav: RefCounted, from: Vector2, motion: Vector2, r: float) -> Vector2:
	var along_x := absf(motion.x) >= absf(motion.y)
	var main := motion.x if along_x else motion.y
	if absf(main) < 1e-6 or absf(main) < motion.length() * 0.9:
		return from   # only for (nearly) straight pushes
	var cell := Vector2i(floori(from.x), floori(from.y))
	var s := 1 if main > 0.0 else -1
	var ahead := cell + (Vector2i(s, 0) if along_x else Vector2i(0, s))
	if not nav.can_step(cell, ahead):
		return from
	var lane := (cell.y + 0.5) if along_x else (cell.x + 0.5)
	var off := lane - (from.y if along_x else from.x)
	if absf(off) < 0.002:
		return from
	var amount := signf(off) * minf(absf(off), absf(main))
	var nudge := Vector2(0, amount) if along_x else Vector2(amount, 0)
	return from + nudge if nav.segment_clear(from, from + nudge, r) else from


## The side of a joined edge this motion pushes through ("" = none).
func _edge_push(from: Vector2, motion: Vector2) -> String:
	if motion.length_squared() < 1e-12:
		return ""
	var data: Dictionary = world.room.data
	var w: int = world.room.w
	var d: int = world.room.d
	var cell := Vector2i(floori(from.x), floori(from.y))
	var to := from + motion
	var length := motion.length()
	for side in ["east", "west", "north", "south"]:
		if Places.edge(data, side) == "":
			continue
		var out := false
		match side:
			"east":
				out = cell.x == w - 1 and motion.x > length * 0.38 and to.x + FOOT >= w
			"west":
				out = cell.x == 0 and motion.x < -length * 0.38 and to.x - FOOT <= 0.0
			"north":
				out = cell.y == 0 and motion.y < -length * 0.38 and to.y - FOOT <= 0.0
			"south":
				out = cell.y == d - 1 and motion.y > length * 0.38 and to.y + FOOT >= d
		if out and Places.side_of(data, cell) != "":
			return side
	return ""


## Steering into a cell: its step events and pickups; near a door cell's centre: through the door.
func _entered(player: Node3D) -> void:
	var c: Vector2i = player.cell()
	if c != _cell:
		_cell = c
		_door_used = NOWHERE
		if TileEvents.fire(world, c, "step"):
			if not is_instance_valid(player) or player != world.player or _blocked():
				return # A tile event can open dialogue or start a room transition.
		var here := _pickup_at(c)
		if not here.is_empty():
			collect_pickup(here)
	if _door_used == c:
		return
	var door := _door_at(c)
	if door.is_empty():
		return
	var centre: Vector3 = world.room.cell_center(c)
	if Vector2(player.position.x - centre.x, player.position.z - centre.z).length() <= DOOR_REACH:
		_door_used = c
		velocity = Vector3.ZERO
		go_through(door)


func _lose_ownership(reason: String) -> void:
	_pending = Callable()
	if is_instance_valid(_marker):
		_marker.visible = false
	if is_instance_valid(world.player):
		world.player.stop()
	if reason == "transition" and _edge_carry:
		return   # across a joined edge you keep walking where you were going
	_wait_neutral = true


func _cancel_route() -> void:
	_pending = Callable()
	_marker.visible = false
	world.player.stop()
	velocity = Vector3.ZERO


## A new player node (a room loaded): nothing pending from the old place carries over.
func _track_player() -> void:
	var p: Node3D = world.player
	var id := p.get_instance_id() if is_instance_valid(p) else 0
	if id == _player_id:
		return
	_player_id = id
	_pending = Callable()
	if is_instance_valid(_marker):
		_marker.visible = false
	if not _edge_carry:
		velocity = Vector3.ZERO
	if is_instance_valid(p):
		_cell = p.cell()
		_door_used = _cell   # arriving on a door cell never sends you straight back
	_last_pos = Vector3.INF


func _hint_from_motion(player: Node3D, delta: float) -> void:
	var p: Vector3 = player.position
	var v := Vector3.ZERO
	if _last_pos != Vector3.INF and delta > 0.0:
		v = (p - _last_pos) / delta
		v.y = 0.0
		if v.length() > 8.0:
			v = Vector3.ZERO   # a jump (teleport, new room), not walking
	_last_pos = p
	world.cam.walk_hint = v


# --- Clicks, routes and interactions ---------------------------------------------------------------

func raycast(screen_pos: Vector2) -> Dictionary:
	var camera: Camera3D = world.cam.camera
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


func click(screen_pos: Vector2) -> void:
	var hit := raycast(screen_pos)
	if hit.is_empty():
		return
	var col: Object = hit.collider
	# Edit my room: taps place, pick and move pieces instead of walking.
	if world.get("decor") and world.decor.active:
		var obj: Dictionary = world.room.find_object(str(col.get_meta("id", ""))) if str(col.get_meta("kind", "")) == "object" else {}
		if not obj.is_empty() and str(obj.get("type", "")) == "furniture":
			world.decor.pick(obj)
		else:
			world.decor.tap_cell(world.room.world_to_cell(hit.position - hit.normal * 0.05))
		return
	# The Light World: tapping yourself shows what there is to do here.
	if load("res://scripts/world/realms.gd").is_light(world.room.data) and str(col.get_meta("kind", "")) != "object" and str(col.get_meta("kind", "")) != "character":
		var at: Vector3 = hit.position
		if Vector2(at.x - world.player.position.x, at.z - world.player.position.z).length() < 0.55:
			world.light_life.open_things_to_do()
			return
	match str(col.get_meta("kind", "")):
		"character":
			approach_character(str(col.get_meta("id", "")))
		"object":
			use_object(world.room.find_object(str(col.get_meta("id", ""))))
		"edge":
			cross_toward(str(col.get_meta("side", "")), hit.position)
		_:
			var cell: Vector2i = world.room.world_to_cell(hit.position - hit.normal * 0.05)
			if world.room.nav.walkable(cell):
				walk_to(cell, func(): TileEvents.fire(world, cell, "interact"))
			else:
				walk_beside(cell, Callable())


## A click on the ground beyond a joined edge: walk to the nearest edge spot, then cross.
func cross_toward(side: String, point: Vector3) -> void:
	if Places.edge(world.room.data, side) == "":
		return
	var w: int = world.room.w
	var d: int = world.room.d
	var want := Vector2i(clampi(floori(point.x), 0, w - 1), clampi(floori(point.z), 0, d - 1))
	match side:
		"east":
			want.x = w - 1
		"west":
			want.x = 0
		"north":
			want.y = 0
		"south":
			want.y = d - 1
	var cell: Vector2i = want if world.room.nav.walkable(want) else world.room.nav.nearest_walkable(want)
	if Places.side_of(world.room.data, cell) != side:
		world.player.emote("?", Color("#b8aed6"))
		return
	walk_to(cell, func(): world.cross_edge(side, cell))


## Walks to the centre of `cell` (exactly), then runs `then`. Unreachable: a "?" and nothing pending.
func walk_to(cell: Vector2i, then: Callable = Callable()) -> void:
	_track_player()
	var player: Node3D = world.player
	var nav: RefCounted = world.room.nav
	_pending = then
	velocity = Vector3.ZERO
	var centre: Vector3 = world.room.cell_center(cell)
	if cell == player.cell():
		if Vector2(player.position.x - centre.x, player.position.z - centre.z).length() > 0.02:
			var settle: Array[Vector3] = [Vector3(centre.x, player.position.y, centre.z)]
			player.walk(settle)   # steered off-centre: settle on the exact spot first
			return
		on_player_arrived()
		return
	var cells: Array[Vector2i] = nav.path(player.cell(), cell)
	if cells.is_empty():
		_unreachable("Can't get there from here.")
		return
	_marker.position = centre + Vector3(0, 0.02, 0)
	_marker.visible = true
	var start := Vector2(player.position.x, player.position.z)
	var pts: Array[Vector3] = []
	var flat: Array[Vector2] = nav.smooth(start, cells, FOOT)
	if not flat.is_empty() and not nav.segment_clear(start, flat[0], FOOT):
		# Steered close to a corner: back to this cell's centre first, then on.
		var home: Vector3 = world.room.cell_center(player.cell())
		pts.append(home)
		flat = nav.smooth(Vector2(home.x, home.z), cells, FOOT)
	for p in flat:
		pts.append(Vector3(p.x, 0.0, p.y))
	player.walk(pts)


func _unreachable(message: String) -> void:
	_pending = Callable()
	unreachable_count += 1
	if is_instance_valid(_marker):
		_marker.visible = false
	if is_instance_valid(world.player):
		world.player.emote("?", Color("#b8aed6"))
	if world.hud:
		world.hud.set_hint(message)


## Next to (8 neighbours) with no thin wall between.
func _next_to(a: Vector2i, b: Vector2i) -> bool:
	var d := (a - b).abs()
	if d.x > 1 or d.y > 1:
		return false
	return a == b or not world.room.nav.blocked_between(a, b)


## Walks to stand side by side with a friend (as seen by the camera), then talks. The side is
## chosen by the real route's length (a nearer side behind a wall loses to a reachable one);
## on arrival the friend must still be there and next to you (a wandering friend gets one retry).
func approach_character(id: String, retry: bool = true) -> void:
	if not world.actors.has(id) or not is_instance_valid(world.actors[id]):
		return
	var friend: Node3D = world.actors[id]
	var target: Vector2i = friend.cell()
	var me: Vector2i = world.player.cell()
	if me != target and _next_to(me, target) and world.room.nav.walkable(me):
		_pending = Callable()
		world.talk.talk_to(id)
		return
	var nav: RefCounted = world.room.nav
	var right: Vector2i = world.cam.right_cell_dir()
	var best := Vector2i(-1, -1)
	var best_cost := INF
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var c: Vector2i = target + Vector2i(dx, dy)
			if c == target or not nav.walkable(c) or nav.blocked_between(c, target):
				continue
			var cost: float = nav.cost(me, c)
			if cost < 0.0:
				continue
			if c != target - right and c != target + right:
				cost += 1.5   # side by side reads best on screen
			if cost < best_cost:
				best_cost = cost
				best = c
	if best.x < 0:
		_unreachable("Can't reach them from here.")
		return
	walk_to(best, func(): _talk_when_close(id, retry))


func _talk_when_close(id: String, retry: bool) -> void:
	if not world.actors.has(id) or not is_instance_valid(world.actors[id]):
		_unreachable("They've wandered off.")
		return
	if _next_to(world.player.cell(), world.actors[id].cell()):
		world.talk.talk_to(id)
	elif retry:
		approach_character(id, false)
	else:
		_unreachable("They moved away.")


## Walks to the reachable free cell next to `target` with the shortest route, then runs `then`
## if you're still next to it (and, for an object, it's still there).
func walk_beside(target: Vector2i, then: Callable, object_id: String = "") -> void:
	var dest: Vector2i = world.room.nav.best_neighbor(target, world.player.cell())
	if dest.x < 0:
		_unreachable("Can't get there from here.")
		return
	walk_to(dest, func():
		if object_id != "" and world.room.find_object(object_id).is_empty():
			_unreachable("That's gone now.")
			return
		if object_id != "" and world.room.obj_cell(world.room.find_object(object_id)) != target:
			_unreachable("That moved. Choose it again.")
			return
		if not _next_to(world.player.cell(), target):
			_unreachable("Can't reach that from here.")
			return
		if then.is_valid():
			then.call())


func on_player_arrived(source: Node = null) -> void:
	if source != null and source != world.player:
		return # A replaced actor must never complete the new room's pending action.
	_marker.visible = false
	if _blocked():
		_pending = Callable()
		return
	var here_cell: Vector2i = world.player.cell()
	_cell = here_cell
	_door_used = here_cell
	TileEvents.fire(world, here_cell, "step")
	var cb := _pending
	_pending = Callable()
	var here := _pickup_at(here_cell)
	if not here.is_empty():
		collect_pickup(here)
	if cb.is_valid():
		cb.call()
		return
	var door := _door_at(here_cell)
	if not door.is_empty():
		go_through(door)


func use_object(o: Dictionary) -> void:
	if o.is_empty():
		return
	var cell: Vector2i = world.room.obj_cell(o)
	var type := str(o.get("type", ""))
	var oid := str(o.get("id", ""))
	if type == "platform_pillar":
		walk_beside(cell, func(): world.platform.activate(o), oid)
		return
	if type in ["jump_pad", "one_way", "mover", "checkpoint", "shard", "hazard"]:
		world.hud.set_hint("That works in Platform Mode: find a Platform Pillar and activate it.")
		return
	if type == "dream_door":
		walk_beside(cell, func(): world.variety.open_dream_door(o), oid)
		return
	if type == "dark_fountain":
		walk_beside(cell, func(): world.dark.use_fountain(o), oid)
		return
	if type == "battle_spot":
		walk_to(cell, func(): world.battles.use_spot(o))
		return
	if type == "furniture":
		walk_beside(cell, func(): world.light_life.use(o), oid)
		return
	if type == "door":
		walk_to(cell, func(): go_through(o))
	elif Pickups.is_pickup(o):
		walk_to(cell)   # arriving on the cell picks it up
	else:
		walk_beside(cell, func():
			var text := str(o.get("interaction_text", "")).strip_edges()
			if text != "":
				world.talk.show_text("", text)
			else:
				world.player.emote("♪"), oid)


## E / Z: talk to the closest friend, or use the closest object.
func interact_nearest() -> void:
	var near := nearest_target()
	if near.is_empty():
		world.hud.set_hint("Nothing to use here. Walk next to a friend or a sign and press E.")
	elif str(near.kind) == "friend":
		approach_character(str(near.id))
	else:
		use_object(near.object)


## What E (or the phone's action button) would use now, without using it: {kind: "friend", id} or
## {kind: "object", object}; {} when nothing is within reach. A friend nearby comes first.
func nearest_target(reach: float = 1.8) -> Dictionary:
	if world == null or not is_instance_valid(world.player) or world.room == null:
		return {}
	var pos: Vector3 = world.player.position
	var best_id := ""
	var best_d := reach
	for id in world.actors:
		var dd: float = world.actors[id].position.distance_to(pos)
		if dd < best_d:
			best_d = dd
			best_id = id
	if best_id != "":
		return {"kind": "friend", "id": best_id}
	var best_obj := {}
	best_d = reach
	for o in world.room.data.get("objects", []):
		var dd: float = world.room.obj_position(o).distance_to(pos)
		if dd < best_d:
			best_d = dd
			best_obj = o
	return {} if best_obj.is_empty() else {"kind": "object", "object": best_obj}


func _pickup_at(cell: Vector2i) -> Dictionary:
	for o in world.room.data.get("objects", []):
		if Pickups.is_pickup(o) and Pickups.available(o) and world.room.obj_cell(o) == cell:
			return o
	return {}


## Into the bag it goes: the pickup disappears (until tomorrow, if it's daily).
func collect_pickup(o: Dictionary) -> Dictionary:
	if bool(o.get("crystal", false)) and Pickups.available(o):
		load("res://scripts/variety/story.gd").bump("crystals")
	var it := Pickups.collect(o)
	if it.is_empty():
		return {}
	SaveManager.save_room(world.room.data)
	var node: Node = world.room.object_nodes.get(str(o.get("id", "")))
	if node and is_instance_valid(node):
		# It flies to your bag.
		var from: Vector2 = world.cam.camera.unproject_position((node as Node3D).global_position + Vector3(0, 0.4, 0))
		var bag: Button = world.hud.button("bag")
		if bag and bag.is_visible_in_tree():
			preload("res://scripts/ui/anim_fx.gd").fly_to(world.main.fly_layer(), load("res://scripts/items/items.gd").icon_texture(it), from, bag.get_global_rect().get_center())
		node.queue_free()
	world.room.object_nodes.erase(str(o.get("id", "")))
	Synth.play(self, "pop")
	world.player.emote("♪", Color("#ffd166"))
	var n := maxi(1, int(o.get("count", 1)))
	GameState.notify("Got %s%s! It's in your bag." % [it.name, (" ×%d" % n) if n > 1 else ""])
	return it


func _door_at(cell: Vector2i) -> Dictionary:
	for o in world.room.data.get("objects", []):
		if str(o.get("type", "")) == "door" and world.room.obj_cell(o) == cell:
			return o
	return {}


func go_through(door: Dictionary) -> void:
	var target := str(door.get("door_target", ""))
	if target == "" or not SaveManager.room_exists(target):
		world.talk.show_text("", "This door doesn't lead anywhere yet. (Link it in Build mode.)")
		return
	Synth.play(self, "door")
	var dn: Node = world.room.object_nodes.get(str(door.get("id", "")))
	if dn is Node3D:
		preload("res://scripts/ui/anim_fx.gd").swing(dn)
	world.go_to_room(target)


## A soft ring on the floor where you clicked.
func _make_marker() -> MeshInstance3D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var r := Vector2(x - 15.5, y - 15.5).length()
			img.set_pixel(x, y, Color(1, 0.82, 0.4, 0.9) if r > 11.0 and r < 15.0 else Color(0, 0, 0, 0))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.rotation.x = -PI / 2.0
	mi.visible = false
	return mi
