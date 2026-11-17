extends RefCounted
## Heart movement in arena coordinates. Gravity, shield and pulses share the
## same touch, keyboard and gamepad direction as free movement.

const SPEED := 170.0
var speed_scale := 1.0   # the battle's Soul speed (Rules), halved inside a "slow" hazard
const GRAVITY := 460.0
const JUMP := 205.0
const SHIELD_R := 22.0
const PULSE_MAX := preload("res://scripts/battle/patterns.gd").PULSE_RESERVE

var mode := "free"
var velocity := 0.0
var shield := Vector2.UP
var pulses := PackedVector2Array()
var pulse_live := PackedByteArray()
var cooldown := 0.0
var blocks := 0
var breaks := 0


func _init() -> void:
	pulses.resize(PULSE_MAX)
	pulse_live.resize(PULSE_MAX)


func reset(kind: String) -> void:
	mode = kind
	velocity = 0.0
	shield = Vector2.UP
	pulse_live.fill(0)
	cooldown = 0.0
	blocks = 0
	breaks = 0


func step(heart: Vector2, direction: Vector2, aim: Vector2, box: Vector2, dt: float, jump: bool, fire: bool) -> Vector2:
	if mode == "shield":
		var toward := direction if direction.length_squared() > 0.01 else aim - heart
		if toward.length_squared() > 0.01:
			shield = toward.normalized()
		return box / 2.0
	var next := heart + direction.limit_length(1.0) * SPEED * speed_scale * dt
	if mode == "gravity":
		var floor_y := box.y - 5.0
		if heart.y >= floor_y - 0.5 and jump:
			velocity = -JUMP
		velocity += GRAVITY * dt
		next.y = minf(floor_y, heart.y + velocity * dt)
		if next.y >= floor_y:
			velocity = 0.0
	if mode == "shooter":
		cooldown = maxf(0.0, cooldown - dt)
		if fire and cooldown <= 0.0:
			for i in PULSE_MAX:
				if pulse_live[i] == 0:
					pulse_live[i] = 1
					pulses[i] = heart
					cooldown = 0.22
					break
		for i in PULSE_MAX:
			if pulse_live[i]:
				pulses[i].y -= 260.0 * dt
				if pulses[i].y < 0:
					pulse_live[i] = 0
	return next.clamp(Vector2(5, 5), box - Vector2(5, 5))


static func hurts(rule: String, moving: bool) -> bool:
	return (rule != "still" or moving) and (rule != "move" or not moving)


func blocks_bullet(heart: Vector2, bullet: Vector2, radius: float) -> bool:
	var offset := bullet - heart
	return mode == "shield" and offset.length() <= SHIELD_R + radius and offset.length() > 0.01 and offset.normalized().dot(shield) >= 0.65


func breaks_bullet(bullet: Vector2, radius: float) -> bool:
	if mode != "shooter":
		return false
	for i in PULSE_MAX:
		if pulse_live[i] and pulses[i].distance_squared_to(bullet) <= (radius + 3.0) * (radius + 3.0):
			pulse_live[i] = 0
			breaks += 1
			return true
	return false
