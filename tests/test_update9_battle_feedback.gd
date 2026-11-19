extends "res://tests/test_case.gd"

const State := preload("res://scripts/battle/battle_state.gd")
const Screen := preload("res://scripts/battle/battle_screen.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")


func test_heal_events_report_each_actual_recipient() -> void:
	for command in [{"cmd": "rally"}, {"cmd": "magic", "spell": "chorus"}]:
		var state := State.new()
		state.setup([State.member("a", "A", 40, 6, 2, "dreamer"), State.member("b", "B"), State.member("c", "C")], [State.enemy({})])
		state.party[0].hp = 39
		state.party[1].hp = 0
		state.party[1].down = true
		state.tp = 100
		eq(state.plan(0, command), "")
		var events := state.resolve_queue()
		var gain := 12 if command.cmd == "rally" else 20
		eq(events[0].amount, gain + 1, "total respects the HP cap")
		eq(events[0].healed, [{"who": 0, "amount": 1}, {"who": 1, "amount": gain}], "feedback names only healed members")
		check(not state.party[1].down, "party healing revives a downed member")


func test_path_warnings_match_first_bullet_positions() -> void:
	for spec in [{"path": "traced", "trace": [[0, 0.1], [1, 0.8]], "count": 3}, {"path": "orbit", "from": "center", "count": 4}]:
		var wave := Patterns.prepare({"spawners": [spec]})
		var origins := Patterns.origins(wave)
		var bullets := Patterns.bullets_at(wave, 0.0)
		eq(origins.size(), bullets.size())
		for i in bullets.size():
			var actual := Vector2(float(bullets[i].x) / float(wave.box.w), float(bullets[i].y) / float(wave.box.h))
			var warned := Vector2(origins[i].at[0], origins[i].at[1])
			check(actual.distance_to(warned) < 0.0001, "warning is at the bullet's spawn")


func test_touch_and_emulated_mouse_submit_only_one_fighter() -> void:
	var screen := Screen.new()
	# Build only the timing controls; no tree or audio is needed for input dispatch.
	screen.buttons = GridContainer.new()
	screen.sub = GridContainer.new()
	screen.sub_scroll = ScrollContainer.new()
	screen.add_child(screen.buttons)
	screen.add_child(screen.sub_scroll)
	screen.sub_scroll.add_child(screen.sub)
	screen.state = State.new()
	screen.state.setup([State.member("a", "A"), State.member("b", "B"), State.member("c", "C")], [State.enemy({})])
	screen._fighters = [0, 1, 2]
	screen._fight_next()
	screen.bar_x = 0.5
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	screen._gui_input(touch)
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	screen._gui_input(mouse)
	eq(screen._fighter, 1, "one finger tap leaves the second bar waiting")
	eq(screen._timings, {0: 0.5})
	mouse.device = 0
	screen.bar_x = 0.6
	screen._gui_input(mouse)
	eq(screen._fighter, 2, "a real mouse press still works")
	screen.free()


func test_review_keeps_four_lines_buttons_and_party_separate() -> void:
	fresh_save_root()
	for dimensions in [Vector2(600, 1300), Vector2(1300, 600), Vector2(1280, 720)]:
		var screen := Screen.new()
		screen.setup({"enemies": [{}]}, [State.member("a", "A"), State.member("b", "B"), State.member("c", "C")], [], [], [], SaveManager.root)
		tree.root.add_child(screen)
		screen.set_process(false)
		screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
		screen.size = dimensions
		for i in 3:
			screen.state.plan(i, {"cmd": "defend"})
		screen._review()
		var last_baseline := screen.box_target.position.y + 32 + 3 * ThemeDB.fallback_font.get_height(20)
		check(last_baseline < screen.sub_scroll.position.y, "four review lines fit above the buttons at %s" % dimensions)
		check(screen.box_target.end.y < screen._member_rect(0).position.y, "review does not cover the party at %s" % dimensions)
		check(screen.sub_scroll.position.y + screen.sub_scroll.size.y <= screen.box_target.end.y, "buttons stay inside their box")
		screen.free()
	await frames(2)
