extends Control
## Platform Mode's on-screen controls, so one hand (mouse or thumb) is enough:
## Leave Platform Mode (always visible), a big Jump button, Run (a toggle),
## camera turn buttons and first-person, Assists (Auto-run, Auto-jump,
## Slow-fall, Camera assist). On a phone a virtual joystick sits under the
## free thumb (push it all the way to run); left-handed mirrors everything.
## Tags: [PLATFORM]

signal jump_pressed
signal jump_released
signal roll_pressed
signal leave_pressed
signal run_toggled(on: bool)
signal camera_step(dir: int)
signal first_person_toggled
signal assists_changed(assists: Dictionary)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Config := preload("res://scripts/platform/platform_config.gd")

const ASSISTS := [["auto_run", "Auto-run", "Keeps you moving forward; steer with the camera or sideways keys"],
	["auto_jump", "Auto-jump", "Hops 1-block ledges by itself"],
	["slow_fall", "Slow-fall", "Falls gently, so landings are easy to aim"],
	["camera_assist", "Camera assist", "The camera swings behind you by itself (no camera control needed)"]]

var phone := false
var left_handed := false
var run_on := false
var assists: Dictionary = {}
var stick: Control                  # the virtual joystick (phone)
var _jump: Button
var _run: Button
var _roll: Button
var _profile: Label
var _leave: Button
var _assist_box: VBoxContainer
var _shards: Label
var _status: VBoxContainer


func setup(phone_layout: bool, left_hand: bool, saved_assists: Dictionary) -> void:
	phone = phone_layout
	left_handed = left_hand
	assists = {"auto_run": false, "auto_jump": false, "slow_fall": false, "camera_assist": true}
	for k in saved_assists:
		assists[k] = bool(saved_assists[k])
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leave = UiKit.button("Leave Platform Mode" if phone else "Leave Platform Mode (X)", func(): leave_pressed.emit(), 0)
	_leave.add_theme_font_size_override("font_size", 20)
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.tooltip_text = "Back to normal walking, right where you are"
	add_child(_leave)
	_status = UiKit.vbox(6)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)
	_profile = UiKit.label("", 16, ThemeBuilder.CREAM)
	_profile.name = "PhysicsProfile"
	_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_child(_profile)
	_shards = UiKit.label("", 18, ThemeBuilder.CREAM)
	_status.add_child(_shards)
	var size := 150 if phone else 120
	_jump = _big_button("Jump", size, func(): jump_pressed.emit())
	_jump.tooltip_text = "Jump (Space)"
	add_child(_jump)
	_jump.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_jump.button_up.connect(func(): jump_released.emit())
	_run = _big_button("Run", int(size * 0.7), func():
		run_on = not run_on
		set_run(run_on)
		run_toggled.emit(run_on))
	_run.toggle_mode = true
	_run.tooltip_text = "Run on/off (R)"
	add_child(_run)
	_roll = _big_button("Roll", int(size * 0.7), func(): roll_pressed.emit())
	_roll.name = "RollCharge"
	_roll.tooltip_text = "Tap at rest to charge; tap again to launch. While moving, toggle rolling."
	_roll.visible = false
	add_child(_roll)
	var cam := UiKit.hbox(6)
	cam.name = "Camera"
	for spec in [["⟲", -1, "Turn the camera (Q)"], ["⟳", 1, "Turn the camera (E)"]]:
		var b := UiKit.button(spec[0], func(): camera_step.emit(int(spec[1])), 64)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = spec[2]
		cam.add_child(b)
	var fp := UiKit.button("👁", func(): first_person_toggled.emit(), 64)
	fp.focus_mode = Control.FOCUS_NONE
	fp.tooltip_text = "First person on/off (V)"
	cam.add_child(fp)
	var more := UiKit.button("Assists", func():
		var panel: Control = get_node("AssistPanel")
		panel.visible = not panel.visible
		_layout(), 120)
	more.focus_mode = Control.FOCUS_NONE
	cam.add_child(more)
	add_child(cam)
	_assist_box = UiKit.vbox(4)
	var panel := PanelContainer.new()
	panel.name = "AssistPanel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", ThemeBuilder.box(Color(ThemeBuilder.PANEL, 0.95), ThemeBuilder.CREAM, 2, 10, 10))
	panel.add_child(_assist_box)
	for a in ASSISTS:
		var cb := CheckBox.new()
		cb.text = a[1]
		cb.tooltip_text = a[2]
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = bool(assists.get(a[0], false))
		cb.toggled.connect(func(on):
			assists[a[0]] = on
			assists_changed.emit(assists))
		_assist_box.add_child(cb)
	add_child(panel)
	if phone:
		stick = load("res://scripts/platform/joystick.gd").new()
		add_child(stick)
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func _big_button(text: String, size: int, cb: Callable) -> Button:
	var b := UiKit.button(text, cb, size)
	b.custom_minimum_size = Vector2(size, size * 0.62)
	b.add_theme_font_size_override("font_size", 26 if size > 100 else 20)
	b.focus_mode = Control.FOCUS_NONE
	return b


func set_shards(n: int) -> void:
	_shards.text = ("✦ %d Memory Shard%s" % [n, "" if n == 1 else "s"]) if n > 0 else ""


func set_profile(id: String, note: String = "") -> void:
	var profiles := preload("res://scripts/platform/platform_profiles.gd")
	_profile.text = profiles.label(id) + "\n" + profiles.hint(id)
	_profile.tooltip_text = note
	_roll.visible = id != "polox"
	_layout()


func set_roll_state(charging: bool, rolling: bool) -> void:
	_roll.text = "Launch" if charging else ("Unroll" if rolling else "Roll")


func set_run(on: bool) -> void:
	run_on = on
	_run.text = "Run: on" if on else "Run"
	_run.set_pressed_no_signal(on)
	_layout()


func _layout() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	var m := 18.0
	_leave.reset_size()
	_leave.position = Vector2((vp.x - _leave.size.x) / 2.0, m)
	var right := not left_handed   # the action buttons go under the dominant thumb
	_jump.reset_size()
	_run.reset_size()
	var jx := vp.x - _jump.size.x - m if right else m
	_jump.position = Vector2(jx, vp.y - _jump.size.y - m - 60.0)
	_run.position = Vector2(jx + (_jump.size.x - _run.size.x) / 2.0, _jump.position.y - _run.size.y - 12.0)
	_roll.reset_size()
	_roll.position = Vector2(jx + (_jump.size.x - _roll.size.x) / 2.0, _run.position.y - _roll.size.y - 10.0)
	var cam: Control = get_node("Camera")
	cam.reset_size()
	if phone:
		# Phones: the thumb stick owns the bottom corner, so camera buttons go up top.
		cam.position = Vector2(vp.x - cam.size.x - m if right else m, m + 70.0)
	else:
		cam.position = Vector2(vp.x - cam.size.x - m if not right else m, vp.y - cam.size.y - m)
	# Profile hints can wrap to several lines. Stack the shard count below them, away from the
	# camera controls, instead of giving both labels fixed positions that overlap.
	_status.position = Vector2(m, cam.position.y + cam.size.y + 10.0 if phone else _leave.position.y + _leave.size.y + 10.0)
	_status.size = Vector2(maxf(1.0, vp.x - 2.0 * m), 0)
	var panel: Control = get_node("AssistPanel")
	panel.reset_size()
	panel.position = Vector2(cam.position.x, cam.position.y + cam.size.y + 10.0) if phone else Vector2(cam.position.x, cam.position.y - panel.size.y - 10.0)
	if stick:
		stick.place(Vector2(m + 110.0 if right else vp.x - m - 110.0, vp.y - 170.0))
