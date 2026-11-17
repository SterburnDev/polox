extends Node
## A tiny helper you add as a child of a Node3D to make it drift: turn around
## Y and/or bob up and down. Used by pillar rings, shards and jump pads.

var spin_speed := 0.0             # radians per second
var bob_height := 0.0
var bob_speed := 1.0
var _t := randf() * 6.0
var _base_y := 0.0
var _started := false


static func bob(height: float, speed: float) -> Node:
	var m: Node = load("res://scripts/platform/idle_motion.gd").new()
	m.bob_height = height
	m.bob_speed = speed
	return m


static func spin_bob(spin: float, height: float, speed: float) -> Node:
	var m: Node = load("res://scripts/platform/idle_motion.gd").new()
	m.spin_speed = spin
	m.bob_height = height
	m.bob_speed = speed
	return m


func _process(delta: float) -> void:
	var p := get_parent() as Node3D
	if p == null:
		return
	if not _started:
		_started = true
		_base_y = p.position.y
	_t += delta
	if spin_speed != 0.0:
		p.rotate_y(spin_speed * delta)
	if bob_height != 0.0:
		p.position.y = _base_y + sin(_t * bob_speed) * bob_height
