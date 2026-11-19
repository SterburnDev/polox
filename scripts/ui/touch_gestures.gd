extends Node
## Touch controls on top of "a tap is a click": a long press is the
## secondary action (back, or the menu when nothing is open), pinching zooms
## the camera and sliding two fingers sideways turns it. Harmless with a mouse.
## Tags: [PLATFORM]

const LONG_PRESS_S := 0.55
const MOVE_SLOP := 14.0          # px a finger may wander and still count as "held still"
const PINCH_STEP := 0.2          # 20 % change in finger distance = one zoom step
const TURN_STEP := 110.0         # px of two-finger slide = one camera step

const INPUT_GROUP := &"polox_touch_gestures"

var main: Node
var long_presses := 0            # (tests count these)
var _touches: Dictionary = {}    # index -> {start, pos, t}
var _long_done := false
var _pinch_ref := 0.0
var _turn_ref := 0.0
var pulls := 0                   # (tests) syncs started by pulling down
var _pull: Label                 # "Release to sync" while you pull
const PULL_START := 0.14         # the top 14 % of the screen
const PULL_SYNC := 120.0         # px down that syncs
## A control handling its own long press (the home sketch) claims the finger, so the press isn't "back".
static var claimed := false


## Phone-sized layout and controls: on in the phone build with a touch
## screen, or forced in Settings (or with --touch-ui for testing on a PC).
static func phone_layout() -> bool:
	match str(GameState.settings.get("touch_ui", "auto")):
		"on":
			return true
		"off":
			return false
	if "--touch-ui" in OS.get_cmdline_user_args():
		return true
	return (OS.has_feature("web") and DisplayServer.is_touchscreen_available()) or OS.has_feature("android")


func setup(main_node: Node) -> void:
	main = main_node
	add_to_group(INPUT_GROUP)


## A control receives its GUI event after we track the touch. Its claim ends with that finger.
func claim_hold(viewport: Viewport, touch_index: int) -> void:
	if viewport == get_viewport() and _touches.has(touch_index):
		_touches[touch_index]["hold_claimed"] = true


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = {"start": event.position, "pos": event.position, "t": _now()}
			_long_done = false
			if _touches.size() == 2:
				_pinch_ref = _spread()
				_turn_ref = _center().x
		else:
			if _touches.has(event.index) and _touches.size() == 1:
				_end_pull(_touches[event.index])
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index]["pos"] = event.position
			if _touches.size() == 1:
				_show_pull(_touches[event.index])
		if _touches.size() == 2:
			_two_fingers()
	elif event is InputEventMagnifyGesture:
		_zoom(-1 if event.factor > 1.0 else 1)


## Fingers on the screen right now (touch_stick.gd lets go when a second one lands).
func finger_count() -> int:
	return _touches.size()


## A finger can be down when the app is taken away (the notification shade, another app, the system's own
## gestures) and its "finger up" never arrives. Forgotten fingers would count for ever: the stick
## (touch_stick.gd) lets go for two, and a long press needs exactly one. So everything is forgotten when the
## app is paused or loses the focus; a finger that lands again counts again.
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		reset_touches()


func reset_touches() -> void:
	_touches.clear()
	_long_done = true   # (no long press can start from a finger that is no longer known)
	if _pull and is_instance_valid(_pull):
		_pull.queue_free()
	_pull = null


func _process(_delta: float) -> void:
	if _touches.size() != 1 or _long_done:
		return
	var stick: Variant = main.game.get("touch_stick") if main and main.game else null
	if stick and stick.active:
		return   # a thumb held on the stick is steering, not a long press
	var t: Dictionary = _touches.values()[0]
	if bool(t.get("hold_claimed", false)):
		return
	if _now() - float(t.t) >= LONG_PRESS_S and (t.pos as Vector2).distance_to(t.start) < MOVE_SLOP:
		_long_done = true
		long_press()


## Pull to refresh (phones syncing with a PC): a finger that starts near the top of the world and slides
## down far enough syncs on release; a hint shows while you pull.
func _can_pull(t: Dictionary) -> bool:
	if main == null or main.get("phone") == null or not main.panels.is_empty() or main.game == null:
		return false
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	return (t.start as Vector2).y < view.y * PULL_START


func _show_pull(t: Dictionary) -> void:
	if not _can_pull(t):
		return
	var dy := (t.pos as Vector2).y - (t.start as Vector2).y
	if dy < 20.0:
		return
	_long_done = true
	if _pull == null:
		_pull = Label.new()
		_pull.add_theme_font_size_override("font_size", 20)
		_pull.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pull.set_anchors_preset(Control.PRESET_TOP_WIDE)
		main.toast_layer().add_child(_pull)
	_pull.position.y = minf(dy, PULL_SYNC + 20.0) * 0.5
	_pull.text = "↑ Release to sync" if dy >= PULL_SYNC else "↓ Pull to sync"


func _end_pull(t: Dictionary) -> void:
	if _pull:
		_pull.queue_free()
		_pull = null
	if not _can_pull(t):
		return
	if (t.pos as Vector2).y - (t.start as Vector2).y >= PULL_SYNC:
		pulls += 1
		preload("res://scripts/ui/haptics.gd").confirm()
		main.phone.sync_now()


## Back out of whatever is open; with nothing open in the world, the menu.
func long_press() -> void:
	if claimed:
		return   # the control under the finger has its own long press
	if main.game and main.game.get("platform") and main.game.platform.busy():
		return   # Platform Mode: a held thumb is steering (Leave is on screen)
	long_presses += 1
	if main.go_back():
		return
	if main.game and main.panels.is_empty():
		main.game.open_menu()


func _spread() -> float:
	var p: Array = _touches.values()
	return (p[0].pos as Vector2).distance_to(p[1].pos)


func _center() -> Vector2:
	var p: Array = _touches.values()
	return ((p[0].pos as Vector2) + (p[1].pos as Vector2)) / 2.0


func _two_fingers() -> void:
	_long_done = true  # two fingers never count as a long press
	var spread := _spread()
	if _pinch_ref > 0.0 and absf(spread - _pinch_ref) / _pinch_ref >= PINCH_STEP:
		_zoom(-1 if spread > _pinch_ref else 1)
		_pinch_ref = spread
	var cx := _center().x
	if main.game and main.game.get("platform") and main.game.platform.active and main.panels.is_empty():
		main.game.cam.orbit(cx - _turn_ref)   # Platform Mode: two fingers orbit smoothly
		_turn_ref = cx
		return
	if absf(cx - _turn_ref) >= TURN_STEP:
		_turn(1 if cx > _turn_ref else -1)
		_turn_ref = cx


func _zoom(step: int) -> void:
	if main.game and main.panels.is_empty():
		main.game.cam.zoom(step)


func _turn(step: int) -> void:
	if main.game and main.panels.is_empty():
		main.game.cam.rotate_step(step)
