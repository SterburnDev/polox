extends Control
## The phone's thumb stick for walking around (exploration). Touch the world anywhere and slide: you
## walk that way, slowly near the middle and at full speed at the rim, camera-relative like a gamepad
## stick (player_controller.gd steers it). A quick tap still walks to the spot or talks to whoever is
## there; a finger that slides becomes the stick, which wins over the tapped route at once. The stick
## floats: slide past the rim and it follows your thumb, so turning round is one short slide.
##
## An action button (Talk / Use) appears by your thumb when a friend or a thing is within reach; it is
## E on a keyboard.
##
## It sits under the HUD and every panel, so it only sees touches nothing else wanted (mouse filter
## PASS: the tap still reaches the world too). Inert outside the phone layout and whenever steering is
## blocked: building, dialogue, a transition, Platform Mode, a panel.

const TouchGestures := preload("res://scripts/ui/touch_gestures.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

const RADIUS := 72.0       # UI pixels from the centre to the rim (full speed)
const SLOP := 14.0         # UI pixels a finger may slide and still be a tap (touch_gestures.gd too)
const DEAD := 0.12         # the still middle

var world: Node
var vector := Vector2.ZERO  # x right, y back (as Input.get_vector gives it)
var active := false         # steering now
var starts := 0             # (tests) how often a slide became the stick
var action: Button
var _down := false
var _origin := Vector2.ZERO
var _pos := Vector2.ZERO
var _near_t := 0.0
var _near: Dictionary = {}


func setup(game_world: Node) -> void:
	world = game_world


func _ready() -> void:
	name = "TouchStick"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	action = UiKit.button("Talk", func(): _use(), 0)
	action.name = "ActionButton"
	action.focus_mode = Control.FOCUS_NONE
	action.visible = false
	action.add_theme_font_size_override("font_size", 22)
	var round := ThemeBuilder.box(Color(ThemeBuilder.BG, 0.82), Color(ThemeBuilder.YELLOW, 0.85), 3, 56, 0)
	for st in ["normal", "hover", "focus"]:
		action.add_theme_stylebox_override(st, round)
	action.add_theme_stylebox_override("pressed", ThemeBuilder.box(Color(ThemeBuilder.YELLOW, 0.35), ThemeBuilder.YELLOW, 3, 56, 0))
	add_child(action)
	_place_action()
	get_viewport().size_changed.connect(_place_action)


## Where the action button goes: above the tab bar, on the side of the hand you play with.
func _place_action() -> void:
	if action == null:
		return
	var left := str(GameState.settings.get("hand", "right")) == "left"
	var bar := maxf(76.0, UiKit.touch_target()) + 12.0
	var pad := preload("res://scripts/ui/screen_panel.gd").safe_bottom(get_viewport_rect().size.y) if is_inside_tree() else 0.0
	var s := 112.0
	action.custom_minimum_size = Vector2(s, s)
	action.size = Vector2(s, s)
	action.set_anchors_preset(Control.PRESET_BOTTOM_LEFT if left else Control.PRESET_BOTTOM_RIGHT)
	action.offset_left = 18.0 if left else -(s + 18.0)
	action.offset_right = action.offset_left + s
	action.offset_bottom = -(bar + pad + 84.0)
	action.offset_top = action.offset_bottom - s


func enabled() -> bool:
	if not TouchGestures.phone_layout() or world == null or not is_instance_valid(world.get("controller")):
		return false
	if not world.main.panels.is_empty():
		return false
	return world.controller.steer_block() == ""


func _gui_input(event: InputEvent) -> void:
	if not enabled():
		if _down or active:
			stop()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _in_pull_zone(event.position):
				return   # the phone's pull-to-sync starts up there
			_down = true
			_origin = event.position
			_pos = event.position
		else:
			stop()
	elif event is InputEventMouseMotion and _down:
		_pos = event.position
		if not active and _pos.distance_to(_origin) > SLOP:
			active = true
			starts += 1
			preload("res://scripts/ui/haptics.gd").tap()
		if active:
			_update()


func _in_pull_zone(p: Vector2) -> bool:
	return world.main.get("phone") != null and p.y < get_viewport_rect().size.y * TouchGestures.PULL_START


func _update() -> void:
	var d := _pos - _origin
	if d.length() > RADIUS:
		_origin = _pos - d.normalized() * RADIUS   # the stick follows the thumb
		d = _pos - _origin
	var v := d / RADIUS
	var l := v.length()
	vector = Vector2.ZERO if l < DEAD else v.normalized() * minf(1.0, (l - DEAD) / (1.0 - DEAD))
	world.controller.touch_input = vector
	queue_redraw()


## Lets go: the player slows to a stop (steering's own deceleration).
func stop() -> void:
	_down = false
	active = false
	vector = Vector2.ZERO
	if world and is_instance_valid(world.get("controller")):
		world.controller.touch_input = Vector2.ZERO
	queue_redraw()


func _process(delta: float) -> void:
	if (_down or active) and (not enabled() or _fingers() >= 2):
		stop()   # something took over, or two fingers (pinch, turn)
	_near_t -= delta
	if _near_t > 0.0:
		return
	_near_t = 0.2
	var near: Dictionary = world.controller.nearest_target() if enabled() else {}
	_near = near
	action.visible = not near.is_empty()
	if action.visible:
		action.text = "Talk" if str(near.kind) == "friend" else _verb(near.object)


static func _verb(o: Dictionary) -> String:
	var t := str(o.get("type", ""))
	if t.contains("door") or o.has("door_target"):
		return "Go"
	if t.contains("sign") or t.contains("board") or t.contains("book"):
		return "Read"
	return "Use"


func _use() -> void:
	if enabled():
		world.controller.interact_nearest()


func _fingers() -> int:
	var g: Node = world.main.get("gestures") if world else null
	return g.finger_count() if g and g.has_method("finger_count") else 0


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		stop()


func _draw() -> void:
	if not active:
		return
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(_origin, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.38), 3.0, true)
	draw_circle(_origin + vector * RADIUS, 30.0, Color(1, 1, 1, 0.5))
	draw_arc(_origin + vector * RADIUS, 30.0, 0.0, TAU, 32, Color(ThemeBuilder.YELLOW, 0.8), 2.5, true)
