extends RefCounted
## Registers the one-handed control scheme at startup. Every action is a
## single press: no held combos, no chords, no timing.
##   Move: WASD / arrows      Confirm/talk: E or Z (Enter, Space)
##   Back: Q or X (Esc)       Menu: C or Tab      Rotate (build): R
##   Bag: B                   Switch form: F
## Left hand (Settings > I play with my left hand) adds the same keys on the
## right side of the keyboard: I J K L walk, O talk/use, U back, P menu,
## H bag, Y switch form. Arrow keys, Enter and Esc always work.
## Mouse: left click everything, right click = back, wheel = zoom/rotate.
## Gamepad: stick/D-pad move, A talk, B back, Start/Y menu, X rotate (build),
## shoulders rotate the camera, triggers zoom.
## Platform Mode (plat_*): Space jump, R run, Shift or G roll/charge, F use,
## X/Esc leave, Tab menu, Q/E turn, V first person. Left hand adds Space jump,
## H run, N roll/charge, O use, U leave, P menu, [ ] turn, M first person.
## Gamepad: A jump, X run, B roll/charge, Y use, Back leave, Start menu,
## shoulders turn, right stick orbits, right stick click first person.

const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"confirm": [KEY_E, KEY_Z, KEY_ENTER, KEY_SPACE],
	"back": [KEY_Q, KEY_X, KEY_ESCAPE],
	"menu": [KEY_C, KEY_TAB],
	"rotate": [KEY_R],
	"bag": [KEY_B],
	"switch_form": [KEY_F],
	"cam_left": [],
	"cam_right": [],
	"zoom_in": [],
	"zoom_out": [],
	"plat_jump": [KEY_SPACE],
	"plat_run": [KEY_R],
	"plat_roll": [KEY_SHIFT, KEY_G],
	"plat_interact": [KEY_F],
	"plat_leave": [KEY_X, KEY_ESCAPE],
	"plat_menu": [KEY_TAB],
	"plat_cam_left": [KEY_Q],
	"plat_cam_right": [KEY_E],
	"plat_first_person": [KEY_V],
}

## Extra keys for left-handed mouse users (their right hand is on the keyboard).
const RIGHT_SIDE := {
	"move_up": [KEY_I],
	"move_down": [KEY_K],
	"move_left": [KEY_J],
	"move_right": [KEY_L],
	"confirm": [KEY_O],
	"back": [KEY_U],
	"menu": [KEY_P],
	"bag": [KEY_H],
	"switch_form": [KEY_Y],
	"plat_run": [KEY_H],
	"plat_roll": [KEY_N],
	"plat_interact": [KEY_O],
	"plat_leave": [KEY_U],
	"plat_menu": [KEY_P],
	"plat_cam_left": [KEY_BRACKETLEFT],
	"plat_cam_right": [KEY_BRACKETRIGHT],
	"plat_first_person": [KEY_M],
}

const PAD := {
	"confirm": [JOY_BUTTON_A],
	"back": [JOY_BUTTON_B],
	"menu": [JOY_BUTTON_START, JOY_BUTTON_Y],
	"rotate": [JOY_BUTTON_X],
	"move_up": [JOY_BUTTON_DPAD_UP],
	"move_down": [JOY_BUTTON_DPAD_DOWN],
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"cam_left": [JOY_BUTTON_LEFT_SHOULDER],
	"cam_right": [JOY_BUTTON_RIGHT_SHOULDER],
	"plat_jump": [JOY_BUTTON_A],
	"plat_run": [JOY_BUTTON_X],
	"plat_roll": [JOY_BUTTON_B],
	"plat_interact": [JOY_BUTTON_Y],
	"plat_leave": [JOY_BUTTON_BACK],
	"plat_menu": [JOY_BUTTON_START],
	"plat_cam_left": [JOY_BUTTON_LEFT_SHOULDER],
	"plat_cam_right": [JOY_BUTTON_RIGHT_SHOULDER],
	"plat_first_person": [JOY_BUTTON_RIGHT_STICK],
}


static func register(left_hand: bool = false) -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.3)
		InputMap.action_erase_events(action)
		var keys: Array = ACTIONS[action].duplicate()
		if left_hand:
			keys.append_array(RIGHT_SIDE.get(action, []))
		for key in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for btn in PAD.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			InputMap.action_add_event(action, jb)
	_add_stick("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_stick("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_stick("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_stick("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_stick("zoom_in", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_stick("zoom_out", JOY_AXIS_TRIGGER_LEFT, 1.0)
	# Menus: let WASD move focus and E/Z press buttons, like the arrows/Enter do.
	_add_keys("ui_up", [KEY_W])
	_add_keys("ui_down", [KEY_S])
	_add_keys("ui_left", [KEY_A])
	_add_keys("ui_right", [KEY_D])
	_add_keys("ui_accept", [KEY_E, KEY_Z])
	if left_hand:
		_add_keys("ui_up", [KEY_I])
		_add_keys("ui_down", [KEY_K])
		_add_keys("ui_left", [KEY_J])
		_add_keys("ui_right", [KEY_L])
		_add_keys("ui_accept", [KEY_O])
	# Tab opens the game menu instead of cycling focus.
	for ev in InputMap.action_get_events("ui_focus_next"):
		if ev is InputEventKey and (ev.keycode == KEY_TAB or ev.physical_keycode == KEY_TAB):
			InputMap.action_erase_event("ui_focus_next", ev)


static func _add_keys(action: String, keys: Array) -> void:
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):  # register() runs again when settings change
			InputMap.action_add_event(action, ev)


static func _add_stick(action: String, axis: int, dir: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = dir
	InputMap.action_add_event(action, ev)


## True while the player is typing, so letter keys don't trigger actions.
static func typing(viewport: Viewport) -> bool:
	var f := viewport.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
