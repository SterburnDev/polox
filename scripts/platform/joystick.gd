extends Control
## A virtual thumb stick for phones (Platform Mode). Touch inside its circle
## and drag: `vector` goes from (0,0) to length 1 at the rim; pushing past
## JOYSTICK_RUN_AT of the way runs. It follows one finger; others are free
## for Jump and the camera.

const Config := preload("res://scripts/platform/platform_config.gd")

var vector := Vector2.ZERO        # x right, y down (screen)
var running := false
var center := Vector2.ZERO
var _finger := -1
var _knob := Vector2.ZERO


## Screen position -> stick value (length clamped to 1). Pure, so tests use it too.
static func value_for(touch: Vector2, c: Vector2, radius: float = Config.JOYSTICK_RADIUS) -> Vector2:
	var v := (touch - c) / maxf(1.0, radius)
	return v.limit_length(1.0)


static func runs(v: Vector2) -> bool:
	return v.length() >= Config.JOYSTICK_RUN_AT


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Config.JOYSTICK_RADIUS * 2.6, Config.JOYSTICK_RADIUS * 2.6)


func place(at: Vector2) -> void:
	center = at
	position = at - size / 2.0
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0 and event.position.distance_to(center) <= Config.JOYSTICK_RADIUS * 1.3:
			_finger = event.index
			_move(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _finger:
			_finger = -1
			_move(center)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _finger:
		_move(event.position)
		get_viewport().set_input_as_handled()


func _move(p: Vector2) -> void:
	vector = value_for(p, center)
	running = runs(vector)
	_knob = vector * Config.JOYSTICK_RADIUS
	queue_redraw()


func touching() -> bool:
	return _finger >= 0


func _draw() -> void:
	var c := size / 2.0
	draw_circle(c, Config.JOYSTICK_RADIUS, Color(0.95, 0.9, 1.0, 0.12))
	draw_arc(c, Config.JOYSTICK_RADIUS, 0.0, TAU, 48, Color(0.95, 0.9, 1.0, 0.5), 3.0)
	draw_arc(c, Config.JOYSTICK_RADIUS * Config.JOYSTICK_RUN_AT, 0.0, TAU, 48, Color(1.0, 0.82, 0.4, 0.35), 2.0)
	draw_circle(c + _knob, Config.JOYSTICK_RADIUS * 0.42, Color(1.0, 0.82, 0.4, 0.75) if running else Color(0.95, 0.9, 1.0, 0.6))
