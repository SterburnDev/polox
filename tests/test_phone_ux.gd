extends "res://tests/test_case.gd"
## Phase 11 on the phone side: touch gestures (long press, pinch, two-finger
## turn), the thumb-zone HUD and its left-hand mirror, left-hand keys,
## performance mode, phone mode (AI through the PC, pushes after saves, the
## HTML text bar hook) and resolving a phone conflict on the PC.

const StarterContent := preload("res://scripts/core/starter_content.gd")
const PhoneMode := preload("res://scripts/phone/phone_mode.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const ConflictsPanel := preload("res://scripts/ui/conflicts_panel.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const InputSetup := preload("res://scripts/core/input_setup.gd")

var main: Node


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _shutdown() -> void:
	GameState.settings["touch_ui"] = "auto"
	GameState.settings["hand"] = "right"
	GameState.settings.erase("frame_rate")
	GameState.settings.erase("graphics")
	main.queue_free()
	await frames(2)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	main.gestures._input(e)


func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	main.gestures._input(e)


func test_gestures_long_press_pinch_and_turn() -> void:
	var g: Node = await _boot()
	var gs: Node = main.gestures
	# Long press with nothing open: the menu.
	_touch(0, Vector2(300, 300), true)
	gs._touches[0]["t"] = gs._now() - 1.0
	gs._process(0.0)
	_touch(0, Vector2(300, 300), false)
	eq(gs.long_presses, 1)
	eq(main.panels.size(), 1, "long press opened the menu")
	# Long press again: back (closes it).
	_touch(0, Vector2(300, 300), true)
	gs._touches[0]["t"] = gs._now() - 1.0
	gs._process(0.0)
	_touch(0, Vector2(300, 300), false)
	await frames(1)
	eq(main.panels.size(), 0, "long press = back")
	# A finger that moves is not a long press.
	_touch(0, Vector2(300, 300), true)
	_drag(0, Vector2(360, 300))
	gs._touches[0]["t"] = gs._now() - 1.0
	gs._process(0.0)
	_touch(0, Vector2(360, 300), false)
	eq(gs.long_presses, 2, "dragging isn't a long press")
	# Pinch out = zoom in; two fingers sliding = turn.
	var dist_before: float = g.cam.distance
	var yaw_before: int = g.cam.yaw_steps
	_touch(0, Vector2(200, 300), true)
	_touch(1, Vector2(300, 300), true)
	_drag(1, Vector2(400, 300))   # spread grows 100 -> 200: zoom in
	check(g.cam.distance < dist_before, "pinch out zooms in")
	_drag(0, Vector2(400, 300))
	_drag(1, Vector2(560, 300))   # both slide right: turn
	check(g.cam.yaw_steps != yaw_before, "two fingers sliding turn the camera")
	_touch(0, Vector2(400, 300), false)
	_touch(1, Vector2(560, 300), false)
	eq(gs.long_presses, 2, "two fingers never long-press")
	await _shutdown()


func test_thumb_layout_mirror_and_left_hand_keys() -> void:
	var g: Node = await _boot()
	var hud: Control = g.hud
	check(not hud.phone_mode, "desktop layout on a PC")
	GameState.settings["touch_ui"] = "on"
	GameState.settings_changed.emit()
	await frames(2)
	check(hud.phone_mode, "phone layout when switched on")
	var bag: Button = hud.button("bag")
	var menu: Button = hud.button("menu")
	check(bag.is_visible_in_tree() and menu.is_visible_in_tree(), "Bag and Menu are on screen")
	check(bag.size.y >= 76 and menu.size.y >= 76, "thumb-sized buttons")
	var view := hud.get_viewport_rect().size
	# The tab bar (Phase 34): along the bottom, Menu at the right thumb's end.
	check(menu.global_position.x > view.x / 2.0 and bag.global_position.y > view.y / 2.0, "Menu bottom-right for a right thumb")
	check(not hud.button("photo").is_visible_in_tree(), "fewer buttons on a phone (Photo is in the World tab)")
	GameState.settings["hand"] = "left"
	GameState.settings_changed.emit()
	await frames(2)
	check(hud.button("menu").global_position.x < view.x / 2.0, "left hand: mirrored, Menu bottom-left")
	# Left-hand keyboard: the right side of the keyboard works too.
	main.apply_display_settings()
	var k := InputEventKey.new()
	k.physical_keycode = KEY_I
	check(InputMap.event_is_action(k, "move_up"), "I walks up for a left-handed player")
	k.physical_keycode = KEY_O
	check(InputMap.event_is_action(k, "confirm"), "O talks")
	k.physical_keycode = KEY_W
	check(InputMap.event_is_action(k, "move_up"), "W still works")
	GameState.settings["hand"] = "right"
	main.apply_display_settings()
	k.physical_keycode = KEY_I
	check(not InputMap.event_is_action(k, "move_up"), "right hand: I is free for typing")
	await _shutdown()


func test_frame_rate_and_graphics() -> void:
	var g: Node = await _boot()
	# Nothing chosen: no frame cap (the screen's own rate) and shadows on, phone or not.
	GameState.settings.erase("frame_rate")
	GameState.settings.erase("graphics")
	main.apply_display_settings()
	eq(Engine.max_fps, 0, "no frame cap by default (a 120 Hz phone runs at 120)")
	check(g.sun.shadow_enabled, "real-time shadows by default")
	check(g.sun.directional_shadow_mode != DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "no four-cascade shadow (four extra passes)")
	# Battery saver at 30.
	GameState.settings["graphics"] = "saver"
	GameState.settings["frame_rate"] = "30"
	main.apply_display_settings()
	eq(Engine.max_fps, 30, "30 fps when chosen")
	check(not g.sun.shadow_enabled, "Battery saver: no real-time shadows")
	eq(SaveManager.max_texture_side, 1024, "Battery saver: smaller pictures")
	eq(main.get_viewport().msaa_3d, Viewport.MSAA_DISABLED, "Battery saver: no anti-aliasing")
	GameState.settings["frame_rate"] = "60"
	GameState.settings["graphics"] = "high"
	main.apply_display_settings()
	eq(Engine.max_fps, 60)
	check(g.sun.shadow_enabled)
	check(main.get_viewport().msaa_3d != Viewport.MSAA_DISABLED, "High: anti-aliasing")
	# Windows doesn't pace a covered window: on a PC the game draws at most 30 fps while another window has
	# the focus, and back at its own rate after.
	var graphics := preload("res://scripts/core/graphics.gd")
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	eq(Engine.max_fps, 30, "in the background on a PC: 30 fps")
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	eq(Engine.max_fps, 60, "back to the chosen 60")
	GameState.settings.erase("frame_rate")
	graphics.server_window = true   # (Phone Link's and Ping's windows)
	main.apply_display_settings()
	eq(Engine.max_fps, 30, "a server window: 30 fps even with no cap chosen")
	graphics.server_window = false
	GameState.settings.erase("graphics")
	main.apply_display_settings()
	eq(Engine.max_fps, 0, "no cap again")
	await _shutdown()


func test_old_performance_mode_migrates() -> void:
	var Graphics := preload("res://scripts/core/graphics.gd")
	var on := {"performance_mode": "on"}
	check(Graphics.migrate(on), "an old setting is migrated")
	eq(on, {"graphics": "saver", "frame_rate": "30"}, "an explicit On keeps its 30 fps and no shadows")
	var auto := {"performance_mode": "auto"}
	check(Graphics.migrate(auto))
	eq(auto, {}, "Automatic (the old 30 fps on phones) becomes unlocked")
	var off := {"performance_mode": "off"}
	check(Graphics.migrate(off))
	eq(off, {"graphics": "high"})
	check(not Graphics.migrate({"graphics": "high"}), "nothing to migrate twice")
	eq(Graphics.frame_cap({"frame_rate": "auto"}), 0)
	eq(Graphics.frame_cap({"frame_rate": "120"}), 120)
	eq(Graphics.quality({"graphics": "nonsense"}), "high" if not OS.has_feature("android") else "balanced", "unknown values fall back to Automatic")


func test_phone_mode_talks_through_the_pc_and_pushes_after_saves() -> void:
	var g: Node = await _boot()
	var saved_ai: Dictionary = GameState.settings.get("ai", {}).duplicate(true)
	var pm: Node = PhoneMode.new()
	main.add_child(pm)
	pm.setup(main)
	pm.origin = "http://127.0.0.1:9"
	pm.token = "a".repeat(64)
	pm.client.token = pm.token
	pm.client.base_url = pm.origin
	pm._reassert_ai()
	eq(str(AIClient.config.get("preset", "")), "pc", "friends talk through the PC")
	check(pm.paired())
	GameState.save_world()
	check(pm._push_in > 0.0, "a save schedules a push")
	# The HTML text bar hands typed text to the chat.
	var got := [""]
	pm.show_keyboard("Say something", func(t: String): got[0] = t)
	check(pm.keyboard_visible(), "the bar shows when it's your turn")
	var cover := Control.new()
	main.open_panel(cover)
	pm._update_keyboard()
	check(not pm.keyboard_visible(), "and hides while a panel covers the chat (it would hide the panel's buttons)")
	cover.queue_free()
	await frames(1)
	pm._update_keyboard()
	check(pm.keyboard_visible(), "back when the panel closes")
	pm._on_keyboard_send(["hello"])
	eq(got[0], "hello", "the page's text bar reaches the game")
	check(not pm.keyboard_visible(), "sending hides it until your next turn")
	# Offline PC: chat still answers (offline lines) and says so.
	AIClient.pc_token = pm.token
	AIClient.configure({"preset": "pc", "base_url": "http://127.0.0.1:9"})
	var r: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {"mock": {"mode": "test"}})
	check(r.ok and r.get("offline", false), "offline lines when the PC is away")
	AIClient.pc_token = ""
	GameState.settings["ai"] = saved_ai
	AIClient.configure(saved_ai)
	pm.queue_free()
	await _shutdown()


func test_resolve_a_phone_conflict_on_the_pc() -> void:
	var g: Node = await _boot()
	var slot: String = SaveManager.slot_id
	var rel := "slots/%s/rooms/garden.json" % slot
	var phone_room: Dictionary = JsonUtil.read_json(SaveManager.root.path_join(rel), {})
	phone_room["name"] = "Phone garden"
	var put := SyncFiles.put(SaveManager.root, rel, JSON.stringify(phone_room).to_utf8_buffer(), "not-the-base")
	eq(put.status, "conflict")
	var p: Control = ConflictsPanel.new()
	p.slot_id = slot
	main.open_panel(p)
	await frames(1)
	var items := SyncFiles.conflicts(SaveManager.root, slot)
	eq(items.size(), 1)
	p.use_phone(items[0])
	eq(str(SaveManager.load_room("garden").name), "Phone garden", "the phone's version is in use")
	eq(SyncFiles.conflicts(SaveManager.root, slot).size(), 0, "and the conflict is gone")
	check(DirAccess.get_files_at(SaveManager.root.path_join("slots/%s/backups" % slot)).size() > 0, "a snapshot came first")
	# Keep-PC path.
	SyncFiles.put(SaveManager.root, rel, JSON.stringify({"name": "x"}).to_utf8_buffer(), "nope")
	p.keep_pc(SyncFiles.conflicts(SaveManager.root, slot)[0])
	eq(str(SaveManager.load_room("garden").name), "Phone garden", "keep PC: nothing changes")
	eq(SyncFiles.conflicts(SaveManager.root, slot).size(), 0)
	p.close()
	await _shutdown()


# --- The phone's thumb stick (touch_stick.gd) -----------------------------------------------------

func _mouse(at: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = at
	mb.global_position = at
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	main.get_viewport().push_input(mb, true)


func _slide(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	main.get_viewport().push_input(mm, true)


func _wait_s(s: float) -> void:
	await tree.create_timer(s).timeout


## A point of open world: the start-up cards (Today, the recap) closed, and above the tab bar (a
## headless test window is small, so the bar is tall).
func _world_point() -> Vector2:
	for n in main.ui.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.get_parent().remove_child(n)
			n.queue_free()
	return main.get_viewport().get_visible_rect().size * Vector2(0.5, 0.15)


func test_thumb_stick_walks_and_lets_go() -> void:
	GameState.settings["touch_ui"] = "on"
	var g: Node = await _boot()
	main.apply_display_settings()
	await frames(3)
	var stick: Control = g.touch_stick
	check(stick != null and stick.enabled(), "the stick is ready in the phone layout")
	var at := _world_point()
	var p0: Vector3 = g.player.position
	_mouse(at, true)
	await frames(1)
	_slide(at + Vector2(0, -8))
	await frames(1)
	check(not stick.active, "a slide inside the slop is still a tap")
	_slide(at + Vector2(0, -200))
	await frames(1)
	check(stick.active, "a longer slide becomes the stick")
	check(g.controller.touch_input.y < -0.95, "slid past the rim: full speed ahead (%s)" % str(g.controller.touch_input))
	check(stick.vector.length() <= 1.0001, "never faster than full")
	_slide(at + Vector2(0, -200) + Vector2(0, 100))
	await frames(1)
	# The stick followed the thumb to the rim (128 px up), so 100 px back is 28 px past its middle:
	# already walking the other way, (28 / 72 - dead zone) / (1 - dead zone) = 0.31 of full speed.
	check(g.controller.touch_input.y > 0.28 and g.controller.touch_input.y < 0.34, "the stick follows the thumb: back the other way at once (%s)" % str(g.controller.touch_input))
	_slide(at + Vector2(0, -260))
	await _wait_s(0.7)
	check(g.player.position.distance_to(p0) > 0.6, "the player walked (%.2f blocks)" % g.player.position.distance_to(p0))
	_mouse(at + Vector2(0, -260), false)
	await frames(1)
	check(not stick.active, "letting go stops the stick")
	eq(g.controller.touch_input, Vector2.ZERO, "and the steering")
	await _wait_s(0.5)
	check(g.controller.velocity.length() < 0.05, "the player came to a stop")
	await _shutdown()


func test_thumb_stick_steps_aside_for_two_fingers_building_and_panels() -> void:
	GameState.settings["touch_ui"] = "on"
	var g: Node = await _boot()
	main.apply_display_settings()
	await frames(3)
	var stick: Control = g.touch_stick
	var at := _world_point()
	_mouse(at, true)
	_slide(at + Vector2(60, 0))
	await frames(1)
	check(stick.active, "steering")
	for i in 2:
		var t := InputEventScreenTouch.new()
		t.index = i
		t.pressed = true
		t.position = at + Vector2(i * 40, 0)
		main.get_viewport().push_input(t, true)
	await frames(2)
	check(not stick.active, "a second finger (pinch or turn) takes over")
	eq(g.controller.touch_input, Vector2.ZERO)
	for i in 2:
		var t := InputEventScreenTouch.new()
		t.index = i
		t.pressed = false
		t.position = at
		main.get_viewport().push_input(t, true)
	_mouse(at, false)
	await frames(1)
	g.build.enter()
	await frames(2)
	check(not stick.enabled(), "no stick while building (drags place things)")
	g.build.exit()
	await frames(2)
	check(stick.enabled(), "back after building")
	g.open_bag()
	await frames(2)
	check(not stick.enabled(), "no stick behind a panel")
	main.go_back()
	await frames(2)
	GameState.settings["touch_ui"] = "off"
	main.apply_display_settings()
	await frames(1)
	check(not stick.enabled(), "a mouse and keyboard layout has no stick")
	await _shutdown()


func test_action_button_talks_to_a_friend_nearby() -> void:
	GameState.settings["touch_ui"] = "on"
	var g: Node = await _boot()
	main.apply_display_settings()
	await frames(3)
	var stick: Control = g.touch_stick
	var mochi: Node3D = g.actors.get("mochi")
	check(mochi != null, "Mochi is here")
	if mochi == null:
		await _shutdown()
		return
	g.player.position = mochi.position + Vector3(1.0, 0, 0)
	await _wait_s(0.3)
	check(stick.action.visible, "the action button appears next to a friend")
	eq(stick.action.text, "Talk")
	stick.action.pressed.emit()
	var t0 := Time.get_ticks_msec()
	while not g.talk.is_open() and Time.get_ticks_msec() - t0 < 4000:
		await frames(2)
	check(g.talk.is_open(), "it talks to them, like E")
	await _shutdown()
