extends Node3D
## Gently angled diorama camera that follows the player. Zoom and rotation
## move in small, eased steps (scroll wheel or the big on-screen buttons);
## the pitch comes from the "camera angle" preset in Settings.
##
## Platform Mode switches it to `follow` mode: a closer third-person camera
## behind the player that pulls in when a wall is in the way, swings behind
## your movement by itself (Camera assist), and can also be turned in steps
## (Q/E, the buttons), orbited (right-drag, two fingers) and zoomed; or a
## first-person view.

const PRESETS := {"low": 34.0, "cozy": 48.0, "high": 62.0, "top": 78.0}
## Platform Mode's chase camera: [pitch in degrees, distance, how far ahead it looks]. High (the
## default since Phase 24) looks down at about 55 degrees from further back, so you see the
## ground ahead and the next ledge; Classic is the old over-the-shoulder view.
const PLATFORM_PRESETS := {"high": [55.0, 8.5, 1.6], "classic": [22.0, 5.5, 0.0], "low": [12.0, 4.5, 0.0]}
const ZOOM_MIN := 6.0
const ZOOM_MAX := 22.0
const ZOOM_STEP := 1.5

var camera: Camera3D
var target: Node3D
var pitch_deg := 48.0
var yaw_steps := 0            # multiples of 45 degrees
var distance := 12.0
var _yaw := 0.0
var _dist := 12.0
var _focus := Vector3.ZERO
## While talking, the camera centers between the two speakers and nudges them
## up the screen so the dialogue box doesn't cover them.
var talk_focus: Variant = null
## Sideways view shift (world units): build mode slides the room right so
## the tool dock doesn't hide it.
var side_offset := 0.0
var v_offset := 0.0           # same, vertically (the editor's palette sits at the bottom)
var _talk_blend := 0.0

const Config := preload("res://scripts/platform/platform_config.gd")
var follow := false            # Platform Mode's chase camera
var first_person := false
var assist := true             # Camera assist: swing behind the movement
var follow_yaw := 0.0          # degrees, continuous
var follow_pitch := 22.0
var follow_dist := 5.5
var move_hint := Vector3.ZERO  # the player's flat velocity (assist follows it)
var look_ahead := 0.0          # blocks the follow camera looks ahead of you (the High preset)
var _assist_pause := 0.0
var _swoop := 0.0              # 1 -> 0 while the start cinematic swoops in
## Classic Momentum's side view: the course axis (Vector3.ZERO = free 3D camera).
var side_axis := Vector3.ZERO
var _speed_dist := 0.0         # extra distance at speed (eased)
var _speed_lead := Vector3.ZERO
## Exploration: the walking velocity, so the view leads a little where you're going.
var walk_hint := Vector3.ZERO
var _walk_lead := Vector3.ZERO

const SENSITIVITY_MIN := 0.25
const SENSITIVITY_MAX := 2.5


## Saved camera turn sensitivity (Settings > Controls), for mouse drags and two-finger turns alike.
static func sensitivity() -> float:
	return clampf(float(GameState.settings.get("camera_sensitivity", 1.0)), SENSITIVITY_MIN, SENSITIVITY_MAX)


static func _reduced() -> bool:
	return bool(GameState.settings.get("reduce_motion", false))


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	camera.make_current()


static func platform_preset() -> String:
	var p := str(GameState.settings.get("platform_camera", "high"))
	return p if PLATFORM_PRESETS.has(p) else "high"


func apply_preset(name_id: String) -> void:
	pitch_deg = float(PRESETS.get(name_id, 48.0))


func zoom(dir: int) -> void:
	if follow:
		follow_dist = clampf(follow_dist + dir * 0.75, Config.CAMERA_MIN, Config.CAMERA_MAX)
		return
	distance = clampf(distance + dir * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


func rotate_step(dir: int) -> void:
	if follow:
		if side_axis != Vector3.ZERO:
			return   # Classic Momentum keeps its side view square to the course
		follow_yaw += dir * 45.0
		_assist_pause = Config.CAMERA_ASSIST_PAUSE
		return
	yaw_steps += dir


## Free orbit (right-drag, two fingers): pixels -> degrees.
func orbit(dx: float, dy: float = 0.0) -> void:
	if not follow:
		return
	var s := sensitivity()
	if side_axis != Vector3.ZERO:
		# The side view stays readable: a little tilt, never turned off the course plane.
		follow_pitch = clampf(follow_pitch + dy * 0.2 * s, 4.0, 40.0)
		return
	follow_yaw -= dx * 0.3 * s
	follow_pitch = clampf(follow_pitch + dy * 0.2 * s, 5.0, 75.0)
	_assist_pause = Config.CAMERA_ASSIST_PAUSE


## Classic Momentum: a side camera square to the course axis (ZERO = back to the free chase camera).
func set_side_view(axis: Vector3) -> void:
	side_axis = Vector3(axis.x, 0, axis.z).normalized() if axis != Vector3.ZERO else Vector3.ZERO
	if side_axis != Vector3.ZERO:
		# Looking along -Z for an X course (right = +X), along +X for a Z course (right = +Z).
		follow_yaw = 0.0 if absf(side_axis.x) > 0.5 else -90.0
		follow_pitch = 12.0
		follow_dist = maxf(follow_dist, 8.0)
		first_person = false


## Platform Mode on/off. `swoop` plays the start cinematic's camera move.
func set_follow(on: bool, swoop: bool = false) -> void:
	follow = on
	first_person = false
	side_axis = Vector3.ZERO
	_speed_dist = 0.0
	_speed_lead = Vector3.ZERO
	if on:
		var p: Array = PLATFORM_PRESETS[platform_preset()]
		follow_yaw = _yaw
		follow_pitch = float(p[0])
		follow_dist = float(p[1])
		look_ahead = float(p[2])
		_swoop = 1.0 if swoop else 0.0
	else:
		yaw_steps = roundi(follow_yaw / 45.0)
		_yaw = yaw_steps * 45.0


## Camera-relative directions on the floor for free movement (Platform Mode).
func flat_forward() -> Vector3:
	var b := camera.global_transform.basis
	var f := -b.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3(0, 0, -1)


func flat_right() -> Vector3:
	var f := flat_forward()
	return Vector3(-f.z, 0, f.x)


## Camera-relative movement directions snapped to the grid, so "W" always
## means "away from the camera" whatever the rotation.
func forward_cell_dir() -> Vector2i:
	var f := -Vector3(sin(deg_to_rad(yaw_steps * 45.0)), 0, cos(deg_to_rad(yaw_steps * 45.0)))
	return Vector2i(roundi(f.x), roundi(f.z))


func right_cell_dir() -> Vector2i:
	var r := Vector3(cos(deg_to_rad(yaw_steps * 45.0)), 0, -sin(deg_to_rad(yaw_steps * 45.0)))
	return Vector2i(roundi(r.x), roundi(r.z))


func snap_to_target() -> void:
	if target:
		_focus = target.global_position
	_walk_lead = Vector3.ZERO
	_yaw = yaw_steps * 45.0
	_dist = distance
	_update_transform()


func _process(delta: float) -> void:
	if follow:
		_follow(delta)
		return
	var want: Vector3 = talk_focus if talk_focus != null else (target.global_position if target else _focus)
	# A little lead toward where you're walking, eased in and out with your speed (none under Reduce motion).
	var lead := Vector3.ZERO if (talk_focus != null or _reduced()) else (walk_hint * 0.16).limit_length(0.6)
	_walk_lead = _walk_lead.lerp(lead, 1.0 - exp(-3.0 * delta))
	want += _walk_lead
	_focus = _focus.lerp(want, 1.0 - exp(-6.0 * delta))
	_talk_blend = lerpf(_talk_blend, 1.0 if talk_focus != null else 0.0, 1.0 - exp(-6.0 * delta))
	_yaw = lerpf(_yaw, yaw_steps * 45.0, 1.0 - exp(-8.0 * delta))
	_dist = lerpf(_dist, lerpf(distance, minf(distance, 8.5), _talk_blend), 1.0 - exp(-8.0 * delta))
	camera.h_offset = lerpf(camera.h_offset, side_offset, 1.0 - exp(-6.0 * delta))
	camera.v_offset = lerpf(camera.v_offset, v_offset, 1.0 - exp(-6.0 * delta))
	_update_transform()


func _follow(delta: float) -> void:
	if target == null:
		return
	var head := target.global_position + Vector3(0, 1.0, 0)
	var speed := move_hint.length()
	var reduced := _reduced()
	if look_ahead > 0.0 and not first_person and side_axis == Vector3.ZERO:
		head += Vector3(-sin(deg_to_rad(follow_yaw)), 0, -cos(deg_to_rad(follow_yaw))) * look_ahead
	# Faster than a Polox run (the momentum profiles): look a bounded way ahead along the
	# movement and back off a little, eased so a launch doesn't jerk the view.
	var over := maxf(0.0, speed - Config.RUN_SPEED)
	var lead := Vector3.ZERO
	var extra := 0.0
	if not first_person and not reduced:
		var cap := 2.5 if side_axis != Vector3.ZERO else 1.8
		lead = (move_hint * 0.12).limit_length(cap) if speed > 0.5 else Vector3.ZERO
		if side_axis != Vector3.ZERO:
			lead = side_axis * lead.dot(side_axis)
		extra = minf(2.0, over * 0.15)
	_speed_lead = _speed_lead.lerp(lead, 1.0 - exp(-2.5 * delta))
	_speed_dist = lerpf(_speed_dist, extra, 1.0 - exp(-1.5 * delta))
	head += _speed_lead
	_focus = _focus.lerp(head, 1.0 - exp(-10.0 * delta))
	_assist_pause = maxf(0.0, _assist_pause - delta)
	# Camera assist follows movement that goes roughly away from the camera; going
	# sideways or toward it never turns the camera (that would make you circle).
	# At speed it keeps up a little faster; it always waits after you turn it yourself.
	if assist and side_axis == Vector3.ZERO and _assist_pause <= 0.0 and speed > 1.0:
		var fwd := Vector3(-sin(deg_to_rad(follow_yaw)), 0, -cos(deg_to_rad(follow_yaw)))
		if move_hint.normalized().dot(fwd) > 0.55:
			var behind := rad_to_deg(atan2(-move_hint.x, -move_hint.z))
			var rate := Config.CAMERA_ASSIST_RATE * (1.0 + minf(1.5, over / 8.0))
			follow_yaw += wrapf(behind - follow_yaw, -180.0, 180.0) * minf(1.0, rate * delta)
	_swoop = maxf(0.0, _swoop - delta * 1.2)
	var s := _swoop * _swoop
	var dist := 0.05 if first_person else lerpf(follow_dist + _speed_dist, distance, s)
	var pitch := deg_to_rad(lerpf(follow_pitch if not first_person else 0.0, pitch_deg, s))
	var yaw := deg_to_rad(follow_yaw)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var want := _focus + offset
	if not first_person:
		# Pull in when a wall or block is between the player and the camera.
		var space := get_world_3d().direct_space_state if is_inside_tree() else null
		if space:
			var q := PhysicsRayQueryParameters3D.create(_focus, want, Config.LAYER_SOLID)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				want = hit.position + (_focus - want).normalized() * 0.25
	camera.global_position = want
	if first_person:
		camera.look_at(_focus + Vector3(-sin(yaw), 0, -cos(yaw)), Vector3.UP)
	else:
		camera.look_at(_focus, Vector3.UP)
	camera.h_offset = 0.0
	camera.v_offset = 0.0


func _update_transform() -> void:
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(_yaw)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * _dist
	var toward_cam := Vector3(sin(yaw), 0, cos(yaw))
	var look_at_point := _focus + Vector3(0, 0.6, 0) + toward_cam * 1.7 * _talk_blend
	camera.global_position = look_at_point + offset
	camera.look_at(look_at_point, Vector3.UP)
