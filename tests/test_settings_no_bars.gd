extends "res://tests/test_case.gd"
## [GLASS_UI] [PLATFORM] Settings has no sliders and no scroll bars on any version: values use − / + steppers,
## and every page (and the screen around it on a small window or a phone) scrolls by swipe, wheel or keys
## with its bar hidden. Checked from the title and from a world, at PC, phone-portrait and phone-on-its-side
## sizes, on every Settings page.
## Tags: [GLASS_UI] [PLATFORM]

const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const TouchGestures := preload("res://scripts/ui/touch_gestures.gd")

var main: Node


func _bars(root: Node, where: String) -> void:
	for n in root.find_children("*", "", true, false):
		check(not (n is Slider), "%s: no slider (%s)" % [where, n.get_path()])
		if n is ScrollContainer:
			var s := n as ScrollContainer
			for mode in [s.vertical_scroll_mode, s.horizontal_scroll_mode]:
				check(mode in [ScrollContainer.SCROLL_MODE_DISABLED, ScrollContainer.SCROLL_MODE_SHOW_NEVER], "%s: a scroller with a bar (%s)" % [where, s.get_path()])
		if n is ScrollBar and (n as ScrollBar).is_visible_in_tree() and not (n.get_parent() is ScrollContainer):
			check(false, "%s: a scroll bar (%s)" % [where, n.get_path()])


func _check_all_pages(where: String) -> void:
	var s: Control = SettingsScreen.new()
	s.main = main
	main.open_panel(s)
	await frames(3)
	for i in s.tabs.get_tab_count():
		s.show_page(i)
		await frames(2)
		_bars(s, "%s, %s" % [where, s.tabs.get_tab_title(i)])
	main.go_back()
	await frames(2)


func test_no_sliders_or_bars_anywhere_in_settings() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	var before := tree.root.size
	var min_before := tree.root.min_size
	var touch_mode_before: Variant = GameState.settings.get("touch_ui", "auto")
	tree.root.min_size = Vector2i.ZERO
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)
	tree.root.min_size = Vector2i.ZERO
	for size in [Vector2i(1280, 720), Vector2i(412, 892), Vector2i(892, 412)]:
		GameState.settings["touch_ui"] = "off" if size.x == 1280 else "on"
		tree.root.size = size
		await frames(2)
		eq(tree.root.size, size, "Settings is checked at the requested size")
		await _check_all_pages("title %dx%d" % [size.x, size.y])
	main.begin_new_world()
	await frames(3)
	for size in [Vector2i(1280, 720), Vector2i(412, 892)]:
		GameState.settings["touch_ui"] = "off" if size.x == 1280 else "on"
		tree.root.size = size
		await frames(2)
		eq(tree.root.size, size, "Settings is checked at the requested size")
		await _check_all_pages("world %dx%d" % [size.x, size.y])
		# The world's Menu (where its Settings is) has no bar either.
		main.game.open_menu()
		await frames(3)
		var menu: Control = main.panels.back()
		_bars(menu, "world Menu %dx%d" % [size.x, size.y])
		# It opens at the top (Resume in sight), and keyboard focus moving down still scrolls it along.
		var page: ScrollContainer = null
		for sc in menu.find_children("*", "ScrollContainer", true, false):
			if (sc as ScrollContainer).vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER:
				page = sc
		check(page != null and page.scroll_vertical == 0, "world Menu %dx%d opens at the top (%d)" % [size.x, size.y, page.scroll_vertical if page else -1])
		if page and page.get_v_scroll_bar().max_value > page.size.y + 4.0:
			var buttons := page.find_children("*", "Button", true, false)
			(buttons.back() as Button).grab_focus()
			await frames(3)
			check(page.scroll_vertical > 0, "world Menu %dx%d follows the keyboard down" % [size.x, size.y])
		main.go_back()
		await frames(2)
	main.queue_free()
	await frames(2)
	tree.root.size = before
	tree.root.min_size = min_before
	GameState.settings["touch_ui"] = touch_mode_before


func test_swipe_over_a_stepper_scrolls_without_changing_the_setting() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	var before := tree.root.size
	var min_before := tree.root.min_size
	var touch_emulation_before := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true  # Enable the engine's native touch scrolling in headless mode.
	tree.root.min_size = Vector2i.ZERO
	tree.root.size = Vector2i(760, 360)
	GameState.settings["touch_ui"] = "on"
	GameState.settings["reduce_motion"] = true
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)
	main.begin_new_world()
	await frames(3)
	main._close_all_panels()
	await frames(2)
	var settings := SettingsScreen.new()
	settings.main = main
	settings.start_on = "Gameplay"
	main.open_panel(settings)
	await frames(5)
	var page := settings.tabs.get_current_tab_control() as ScrollContainer
	var plus := page.find_child("Plus", true, false) as Button
	var before_speed := int(GameState.settings.get("text_speed", 45))
	var start := plus.get_global_rect().get_center()
	var movement := Vector2(0.0, -120.0)
	_send_touch(start, true)
	for step in range(1, 5):
		var drag := InputEventScreenDrag.new()
		drag.position = start + movement * (step / 4.0)
		drag.relative = movement / 4.0
		tree.root.push_input(drag, true)
		var copy := InputEventMouseMotion.new()
		copy.device = InputEvent.DEVICE_ID_EMULATION
		copy.position = drag.position
		copy.global_position = drag.position
		copy.relative = drag.relative
		copy.button_mask = MOUSE_BUTTON_MASK_LEFT
		tree.root.push_input(copy, true)
		await frames(1)
	_send_touch(start + movement, false)
	await frames(2)
	check(page.scroll_vertical > 0, "a finger swipes the hidden-bar Settings page")
	eq(GameState.settings.get("text_speed"), before_speed, "a swipe does not press the stepper")
	page.scroll_vertical = 0
	await frames(3)
	start = plus.get_global_rect().get_center()
	_send_touch(start, true)
	_send_touch(start, false)
	await frames(2)
	eq(GameState.settings.get("text_speed"), before_speed + 5, "a tap changes the setting once")
	plus.grab_focus()
	for down in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.pressed = down
		tree.root.push_input(key)
	await frames(2)
	eq(GameState.settings.get("text_speed"), before_speed + 10, "keyboard activation also changes the setting once")
	var back_count: int = main.gestures.long_presses
	await _hold_touch(plus.get_global_rect().get_center())
	check(is_instance_valid(settings) and main.panels.has(settings), "holding the stepper keeps Settings open")
	check(int(GameState.settings.get("text_speed")) >= before_speed + 20, "holding the stepper repeats more than once")
	eq(main.gestures.long_presses, back_count, "the stepper owns its hold gesture")
	if is_instance_valid(settings):
		await _hold_touch(settings.title_label.get_global_rect().get_center())
		check(not is_instance_valid(settings), "a long press outside the stepper still goes Back")
		eq(main.gestures.long_presses, back_count + 1, "ordinary long press remains available")
	GameState.settings["touch_ui"] = "auto"
	GameState.settings["reduce_motion"] = false
	Input.emulate_touch_from_mouse = touch_emulation_before
	main.queue_free()
	await frames(2)
	tree.root.size = before
	tree.root.min_size = min_before


func _hold_touch(position: Vector2) -> void:
	_send_touch(position, true)
	await tree.create_timer(TouchGestures.LONG_PRESS_S + 0.25, true, false, true).timeout
	_send_touch(position, false)
	await frames(2)


func _send_touch(position: Vector2, down: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = position
	touch.pressed = down
	tree.root.push_input(touch, true)
	var copy := InputEventMouseButton.new()
	copy.device = InputEvent.DEVICE_ID_EMULATION
	copy.button_index = MOUSE_BUTTON_LEFT
	copy.position = position
	copy.global_position = position
	copy.pressed = down
	copy.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	tree.root.push_input(copy, true)
