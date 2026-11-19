extends CharacterBody3D
## The player's body in Platform Mode: a capsule that walks, runs and jumps
## over the room (platform_world.gd). Feel constants live in platform_config.gd.
## Air control, coyote time, a jump buffer, step-up for half-block lips,
## ramps, moving platforms (Godot carries a body standing on them), jump pads,
## slippery ground, and the assists: Auto-run, Auto-jump (hop 1-block ledges),
## Slow-fall. No fall damage, ever.
##
## Input comes in as plain values (move direction in world space, run, jump
## pressed), so keyboard, mouse, touch and tests all drive it the same way.

signal jumped
signal landed(fall_speed: float)
signal fell_out

const Config := preload("res://scripts/platform/platform_config.gd")
const Profiles := preload("res://scripts/platform/platform_profiles.gd")

var move_dir := Vector3.ZERO      # wanted direction (world, flat), length 0..1
var run := false                  # run speed (or Auto-run)
var auto_jump := false
var slow_fall := false
var world: Node                   # platform_world.gd (slippery cells, one-way platforms)
var kill_y := -Config.KILL_DEPTH
var frozen := false               # during the start cinematic and respawn fades
var profile := "polox"
var plane_axis := Vector3.RIGHT
var plane_origin := Vector3.ZERO
var rolling := false
var charging := false
var charge := 0.0
var skidding := false
var heading := Vector3.RIGHT
var _jump_held := true

var _since_floor := 0.0
var _jump_buffer := 0.0
var _jumped := false              # this jump used up the coyote time
var _was_on_floor := true
var _fall_speed := 0.0


func _init() -> void:
	collision_layer = Config.LAYER_PLAYER
	collision_mask = Config.LAYER_SOLID | Config.LAYER_ONE_WAY | Config.LAYER_BOUNDS
	floor_max_angle = deg_to_rad(Config.FLOOR_MAX_ANGLE_DEG)
	floor_snap_length = Config.FLOOR_SNAP
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	safe_margin = 0.02
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Config.CAPSULE_RADIUS
	cap.height = Config.CAPSULE_HEIGHT
	cs.shape = cap
	cs.position.y = Config.CAPSULE_HEIGHT / 2.0
	add_child(cs)


## Ask for a jump: it happens now if allowed, or within the buffer time after landing.
func press_jump() -> void:
	_jump_buffer = Config.JUMP_BUFFER
	_jump_held = true
	if charging:
		release_charge()


func release_jump() -> void:
	_jump_held = false
	if profile != "polox" and velocity.y > float(Profiles.values(profile).cut):
		velocity.y = float(Profiles.values(profile).cut)


func set_profile(id: String, axis: Vector3 = Vector3.RIGHT) -> void:
	profile = Profiles.normalize(id)
	plane_axis = axis.normalized()
	plane_origin = global_position
	heading = plane_axis if profile == "classic" else Vector3.RIGHT
	velocity = Vector3.ZERO
	rolling = false
	charging = false
	charge = 0.0
	_jump_buffer = 0.0
	floor_stop_on_slope = profile == "polox"


## One-button accessible roll/charge: while stopped, tap once to charge and
## once to launch. While moving, tap to roll. Keyboard can also hold/release.
func roll_or_charge() -> void:
	if profile == "polox" or not is_on_floor():
		return
	if charging:
		release_charge()
	elif Vector2(velocity.x, velocity.z).length() < 1.0:
		charging = true
		charge = 0.0
		rolling = true
	else:
		rolling = not rolling


func release_charge() -> void:
	if not charging:
		return
	charging = false
	var speed := lerpf(8.0, float(Profiles.values(profile).launch), clampf(charge, 0.0, 1.0))
	velocity.x = heading.x * speed
	velocity.z = heading.z * speed
	rolling = true
	charge = 0.0


## A jump pad (or anything else) throws you up.
func launch(speed: float) -> void:
	velocity.y = speed
	_jumped = true
	_since_floor = Config.COYOTE_TIME + 1.0
	jumped.emit()


func teleport(pos: Vector3) -> void:
	global_position = pos
	if world and world.has_method("reset_triggers"):
		world.reset_triggers()   # a jump across the course isn't a path through it
	velocity = Vector3.ZERO
	_jump_buffer = 0.0
	_since_floor = 0.0
	_jumped = false
	_was_on_floor = false
	_fall_speed = 0.0
	_since_floor = Config.COYOTE_TIME + 1.0
	rolling = false
	charging = false
	charge = 0.0
	move_dir = Vector3.ZERO
	_jump_held = true
	plane_origin = pos


func can_jump() -> bool:
	return is_on_floor() or (_since_floor < Config.COYOTE_TIME and not _jumped)


func _physics_process(delta: float) -> void:
	step(delta)


## One physics step (tests call it directly too).
func step(delta: float) -> void:
	if frozen:
		return
	if world and world.has_method("update_one_ways"):
		world.update_one_ways(self)
	var from := global_position
	var on_floor := is_on_floor()
	if on_floor:
		_since_floor = 0.0
		_jumped = false
	else:
		_since_floor += delta
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	# Horizontal: accelerate toward the wanted velocity.
	var p := Profiles.values(profile)
	var speed := float(p.speed if run else p.walk)
	var want := Vector3(move_dir.x, 0, move_dir.z).limit_length(1.0) * speed
	if profile == "classic":
		want = plane_axis * want.dot(plane_axis)
	var slip: bool = on_floor and world != null and world.has_method("is_slippery") and world.is_slippery(Vector2i(floori(global_position.x), floori(global_position.z)))
	var accel := Config.AIR_ACCEL
	if on_floor:
		if want.length() > 0.01:
			accel = Config.SLIPPERY_ACCEL if slip else Config.GROUND_ACCEL
		else:
			accel = Config.SLIPPERY_DECEL if slip else Config.GROUND_DECEL
	var flat := Vector3(velocity.x, 0, velocity.z)
	if profile == "polox":
		flat = flat.move_toward(want, accel * delta)
	else:
		flat = _momentum(flat, want, on_floor, slip, delta, p)
	velocity.x = flat.x
	velocity.z = flat.z
	# Vertical: a jump first, then gravity over the tick. The body moves with the tick's mean vertical
	# speed (exact for constant gravity), so jump height and airtime don't depend on the frame rate.
	if _jump_buffer > 0.0 and can_jump():
		_do_jump()
	elif auto_jump and on_floor and _ledge_ahead():
		_do_jump()
	var vy0 := velocity.y
	if not on_floor or vy0 > 0.01:
		velocity.y = maxf(vy0 - float(p.gravity) * delta, -(Config.SLOW_FALL_SPEED if slow_fall else Config.MAX_FALL_SPEED))
	var vy1 := velocity.y
	velocity.y = (vy0 + vy1) * 0.5
	# Half-block lips: step up instead of stopping.
	if on_floor and velocity.y <= 0.01:
		_try_step_up(delta)
	_fall_speed = maxf(_fall_speed, -vy1) if not on_floor else 0.0
	var falling_speed := -vy1
	var mean := velocity.y
	move_and_slide()
	if absf(velocity.y - mean) < 0.0001:
		velocity.y = vy1   # (a floor, ceiling or slope that changed it keeps its say)
	if profile == "classic":
		var offset := global_position - plane_origin
		global_position -= Vector3(offset.x, 0, offset.z) - plane_axis * offset.dot(plane_axis)
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		landed.emit(maxf(0.0, falling_speed))
	_was_on_floor = now_floor
	# Pads, hazards, checkpoints and shards along this tick's whole path (none skipped at launch speed).
	if world and world.has_method("sweep_triggers"):
		world.sweep_triggers(self, from, global_position)
	if global_position.y < kill_y:
		fell_out.emit()


func _do_jump() -> void:
	velocity.y = float(Profiles.values(profile).jump)
	if not _jump_held and profile != "polox":
		velocity.y = float(Profiles.values(profile).cut)
	_jump_buffer = 0.0
	_jumped = true
	_since_floor = Config.COYOTE_TIME + 1.0
	jumped.emit()


func _momentum(flat: Vector3, want: Vector3, grounded: bool, slip: bool, delta: float, p: Dictionary) -> Vector3:
	if profile == "classic":
		flat = plane_axis * flat.dot(plane_axis)
	var speed := flat.length()
	var steering := want.length() > 0.01
	var opposite := steering and speed > 0.5 and flat.dot(want) < 0.0
	skidding = grounded and opposite and speed > 3.0 and not rolling
	if charging and grounded:
		charge = minf(1.0, charge + delta * 0.9)
		if steering:
			heading = want.normalized()
		return Vector3.ZERO
	if speed > 0.2:
		heading = flat.normalized()
	elif steering:
		heading = want.normalized()
	if grounded:
		if rolling:
			flat = flat.move_toward(Vector3.ZERO, float(p.roll_friction) * delta)
			if opposite:
				flat = flat.move_toward(Vector3.ZERO, float(p.brake) * 0.4 * delta)
			if flat.length() < 0.5:
				rolling = false
		elif opposite:
			flat = flat.move_toward(want, float(p.brake) * delta)
		elif steering:
			if profile == "adventure" and speed > 0.1:
				# Steering changes direction with traction, without deleting the
				# forward momentum as a vector-to-target lerp would.
				var turn := float(p.turn) / maxf(2.0, speed)
				var direction := flat.normalized().slerp(want.normalized(), minf(1.0, turn * delta))
				flat = direction * move_toward(speed, want.length(), float(p.accel) * delta)
			else:
				# Above normal top speed, holding forward does not destroy a
				# slope/launch boost. Friction and braking can still slow it.
				if speed < want.length():
					flat = flat.move_toward(want, float(p.accel) * delta)
		else:
			flat = flat.move_toward(Vector3.ZERO, (Config.SLIPPERY_DECEL if slip else float(p.friction)) * delta)
		var normal := get_floor_normal()
		var downhill := Vector3.DOWN.slide(normal)
		downhill.y = 0.0
		if profile == "classic":
			downhill = plane_axis * downhill.dot(plane_axis)
		var slope_factor := 1.0
		if rolling:
			slope_factor = 1.5 if flat.dot(downhill) >= 0.0 else 0.5
		flat += downhill * float(p.slope) * slope_factor * delta
	elif steering:
		# No input means no automatic air braking in either momentum preset.
		var desired := want.normalized() * maxf(speed, want.length())
		flat = flat.move_toward(desired, float(p.air) * delta)
	return flat.limit_length(float(p.max))


func _probe() -> Vector3:
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() < 0.2:
		flat = Vector3(move_dir.x, 0, move_dir.z)
	if flat.length() < 0.05:
		return Vector3.ZERO
	return flat.normalized() * (Config.CAPSULE_RADIUS * 0.5 + 0.08)


## Blocked ahead by something no higher than STEP_HEIGHT: lift onto it.
func _try_step_up(delta: float) -> void:
	var probe := Vector3(velocity.x, 0, velocity.z) * delta
	if probe == Vector3.ZERO or not test_move(global_transform, probe):
		return
	var up := Vector3(0, Config.STEP_HEIGHT, 0)
	if test_move(global_transform, up):
		return   # a ceiling
	var raised := global_transform.translated(up)
	if test_move(raised, probe):
		return   # taller than a step: a wall (or a jump)
	# Find the real landing height, then sweep the upward and forward parts.
	# Never add an arbitrary per-frame horizontal boost.
	# A capsule's downward sweep first touches the rounded lip of a step,
	# whose normal points sideways. Probe the top under the forward footprint
	# instead; the upward and forward capsule sweeps above still guard clearance.
	var ahead := global_position + probe + probe.normalized() * Config.CAPSULE_RADIUS
	var query := PhysicsRayQueryParameters3D.create(ahead + up + Vector3.UP * 0.02, ahead - Vector3.UP * 0.08, collision_mask, [get_rid()])
	var landing := get_world_3d().direct_space_state.intersect_ray(query)
	if landing.is_empty():
		return
	if (landing.normal as Vector3).dot(Vector3.UP) < cos(floor_max_angle):
		return
	var rise := float(landing.position.y) - global_position.y + safe_margin
	if rise > 0.01 and rise <= Config.STEP_HEIGHT:
		move_and_collide(Vector3.UP * rise)


## Auto-jump: a ledge ahead that a jump clears (taller than a step, at most a block).
func _ledge_ahead() -> bool:
	var probe := _probe()
	if probe == Vector3.ZERO or not test_move(global_transform, probe):
		return false
	var step_up := global_transform.translated(Vector3(0, Config.STEP_HEIGHT, 0))
	if not test_move(step_up, probe):
		return false   # a step: walked up, no jump needed
	var high := global_transform.translated(Vector3(0, Config.AUTO_JUMP_HEIGHT, 0))
	return not test_move(global_transform, Vector3(0, Config.AUTO_JUMP_HEIGHT, 0)) and not test_move(high, probe)
