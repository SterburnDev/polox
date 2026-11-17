extends "res://tests/test_case.gd"
## [PAIRING] [PLATFORM] The phone's PIN keypad, driven the way a phone drives it: each tap arrives as a real
## InputEventScreenTouch and, in the same frame, the mouse copy Godot makes of it. Before the fix
## (ui_kit.gd first_press_this_frame) a press-mode key fired for both, so every digit was typed twice.
## Tags: [PAIRING]

const AppConnectPanel := preload("res://scripts/ui/app_connect_panel.gd")

var fake: Node
var panel: Control


func _setup() -> void:
	var s := GDScript.new()
	s.source_code = "extends Node
var calls: Array = []
var link = null
var connection := {}
func paired() -> bool:
	return false
func pair_with(url: String, pin: String, device_name: String, how: String = \"typed\") -> Dictionary:
	calls.append(pin)
	return {\"ok\": false, \"error\": \"wrong PIN (4 tries left)\"}
func connection_text() -> String:
	return \"\"
"
	s.reload()
	fake = s.new()
	tree.root.add_child(fake)
	panel = AppConnectPanel.new()
	tree.root.add_child(panel)
	panel.setup_connect(null, fake, true)
	panel.target = {"url": "http://127.0.0.1:1", "path": "home", "name": "PC"}
	panel.show_step("pin")
	await frames(3)


func _teardown() -> void:
	panel.queue_free()
	fake.queue_free()
	await frames(1)


func _key(text: String) -> Button:
	for b in panel.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


## A phone tap on a key: the touch and its mouse copy in one frame, then both releases.
func _tap(text: String) -> void:
	var b := _key(text)
	var at: Vector2 = b.get_global_rect().get_center()
	var vp := b.get_viewport()
	var at_screen: Vector2 = vp.get_final_transform() * (b.get_global_transform_with_canvas().origin + b.size / 2.0)
	for down in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = at_screen
		t.pressed = down
		vp.push_input(t)
		var m := InputEventMouseButton.new()
		m.device = InputEvent.DEVICE_ID_EMULATION
		m.button_index = MOUSE_BUTTON_LEFT
		m.position = at_screen
		m.global_position = at_screen
		m.pressed = down
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		vp.push_input(m)
	await frames(1)


func test_one_tap_types_one_digit() -> void:
	await _setup()
	await _tap("1")
	eq(panel.pin, "1", "one tap, one digit (it was \"11\")")
	await _tap("1")
	eq(panel.pin, "11", "the same digit again is a second digit")
	await _tap("⌫")
	eq(panel.pin, "1", "Backspace removes one")
	await _tap("⌫")
	await _tap("⌫")
	eq(panel.pin, "", "and stops at empty")
	await _teardown()


func test_fast_taps_leading_zero_and_retry() -> void:
	await _setup()
	for d in ["0", "0", "7", "0", "4", "2"]:   # one frame apart: as fast as fingers go
		await _tap(d)
	eq(fake.calls, ["007042"], "six fast taps pair once, leading zeros kept as text")
	eq(panel.pin, "", "a wrong PIN clears the keypad for another try")
	for d in ["1", "2", "3", "4", "5", "6"]:
		await _tap(d)
	eq(fake.calls.size(), 2, "and the retry pairs again")
	eq(str(fake.calls[1]), "123456")
	await _teardown()


func test_keyboard_and_paste_still_work() -> void:
	await _setup()
	var field: LineEdit = panel._pin_field
	field.text = "12-34 5"   # pasted with stray characters
	field.text_changed.emit(field.text)
	eq(panel.pin, "12345", "a paste keeps only the digits")
	field.text = "0123456789"
	field.text_changed.emit(field.text)
	eq(fake.calls, ["012345"], "the first six digits pair, leading zero kept")
	await _teardown()


func test_the_platform_jump_button_jumps_once_per_tap() -> void:
	var b: Button = preload("res://scripts/ui/ui_kit.gd").button("Jump", func(): set_meta("jumps", int(get_meta("jumps", 0)) + 1))
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	tree.root.add_child(b)
	b.pressed.emit()
	b.pressed.emit()   # (the touch's mouse copy, same frame)
	eq(int(get_meta("jumps", 0)), 1, "one tap, one jump")
	await frames(1)
	b.pressed.emit()
	eq(int(get_meta("jumps", 0)), 2, "the next tap jumps again")
	b.queue_free()


func test_a_phone_tap_is_one_tap_everywhere_else_too() -> void:
	# [PLATFORM] The same double delivery hit hand-written handlers: one tap on a sheet's dimmed backdrop
	# went back twice (closing the screen under it too). UiKit.tap_down counts the touch, not its copy.
	var UiKit := preload("res://scripts/ui/ui_kit.gd")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	var copy := InputEventMouseButton.new()
	copy.button_index = MOUSE_BUTTON_LEFT
	copy.pressed = true
	copy.device = InputEvent.DEVICE_ID_EMULATION
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	check(UiKit.tap_down(touch) and not UiKit.tap_down(copy) and UiKit.tap_down(mouse), "a finger and a real mouse tap; the copy doesn't")
	# Every hand-written tap handler that also hears fingers now asks tap_down/tap_up (a phone's sheets,
	# Map my home's walls, the World Map, the Survey, the home sketch, big moments).
	for f in ["res://scripts/ui/screen_panel.gd", "res://scripts/home/map_home_panel.gd", "res://scripts/ui/world_map_view.gd", "res://scripts/home/survey_screen.gd"]:
		var src := FileAccess.get_file_as_string(f)
		check(src.contains("tap_down(") and not src.contains("or (e is InputEventScreenTouch and e.pressed)") and not src.contains("or (event is InputEventScreenTouch and event.pressed)"), f + " counts a tap once")
