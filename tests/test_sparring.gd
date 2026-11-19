extends "res://tests/test_case.gd"

const Data := preload("res://scripts/battle/battle_data.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")
const State := preload("res://scripts/battle/battle_state.gd")
const Field := preload("res://scripts/battle/bullet_field.gd")
const Motion := preload("res://scripts/battle/heart_motion.gd")
const Screen := preload("res://scripts/battle/battle_screen.gd")
const Art := preload("res://scripts/battle/bullet_art.gd")
const Music := preload("res://scripts/world/music_player.gd")


func _state(id: String) -> RefCounted:
	var battle := Data.from_template(id, {})
	var state := State.new()
	state.setup([State.member("me", "Aster")], [State.enemy(battle.enemies[0])], 73)
	return state


func test_six_original_spars_round_trip_all_authoring_fields() -> void:
	fresh_save_root()
	eq(Data.Spars.ORDER.size(), 6)
	for id in Data.Spars.ORDER:
		var b := Data.from_template(id, {})
		eq(b.music, "@original")
		eq(Music.battle_path(b), "", "the original loop never falls back to a bundled song")
		eq(b.enemies.size(), 1)
		eq(b.enemies[0].waves.size(), 3)
		check(ResourceLoader.exists(str(b.enemies[0].picture)))
		var saved := Data.save(b)
		check(saved != "")
		var loaded := Data.load_battle(saved)
		eq(loaded.enemies, b.enemies, id + " preserves waves, modes, phases and ACT routes")
		eq(loaded.music, "@original")
	var old := Data.clean({"version": 2, "enemies": [{"waves": [{"box": {"w": 240, "h": 160}}]}]})
	eq(old.enemies[0].waves[0].mode, "free")
	eq(old.enemies[0].waves[0].box.end_w, 240)
	check(Data.clean({"version": Data.VERSION + 1}).is_empty())


func test_every_new_wave_matches_the_pure_sampler_and_stays_bounded() -> void:
	var field := Field.new()
	var identities := PackedInt64Array()
	for slot in field.slots:
		identities.append(slot.get_instance_id())
	var target := func(t: float) -> Vector2: return Vector2(130 + sin(t) * 30, 100)
	var maximum := 0
	for id in Data.Spars.ORDER:
		for raw in Data.from_template(id, {}).enemies[0].waves:
			field.reset(raw)
			var prepared := field.wave
			for frame in 71:
				var t := frame / 10.0
				var box := Patterns.box_at(prepared, t)
				var reference := Patterns.bullets_at(prepared, t, target)
				field.sample(t, box, target)
				eq(field.count, reference.size(), id)
				maximum = maxi(maximum, field.count)
				for i in field.count:
					var b = field.slots[i]
					check(b.position.distance_to(Vector2(reference[i].x, reference[i].y)) < 0.0001, id + " deterministic position")
					eq(b.id, reference[i].id)
					eq(b.rule, reference[i].rule)
					check(is_finite(b.position.x) and is_finite(b.position.y))
			check(not field.overflow)
	for i in field.slots.size():
		eq(field.slots[i].get_instance_id(), identities[i], "the same 200 slots serve every wave")
	check(maximum <= 200)
	print("    (original spars: peak %d live bullets)" % maximum)


func test_dense_user_patterns_are_capped_and_consumed_bullets_stay_gone() -> void:
	var spawners: Array = []
	for i in 6:
		spawners.append({"path": "orbit", "from": "center", "count": 12, "every": 0.08, "speed": 0, "radius": 30, "seed": i})
	var field := Field.new()
	field.reset({"duration": 15, "spawners": spawners})
	field.sample(14, Vector2(240, 160), Callable())
	eq(field.count, 200)
	check(field.overflow)
	var shooter := Field.new()
	shooter.reset({"mode": "shooter", "duration": 15, "spawners": spawners})
	shooter.sample(14, Vector2(240, 160), Callable())
	eq(shooter.count + Motion.PULSE_MAX, 200, "player pulses share the total projectile budget")
	eq(Patterns.bullets_at(shooter.wave, 14).size(), shooter.count)
	var key: int = field.slots[0].key
	check(field.graze_once(field.slots[0]))
	check(not field.graze_once(field.slots[0]))
	field.remove(field.slots[0])
	field.sample(14, Vector2(240, 160), Callable())
	for i in field.count:
		check(field.slots[i].key != key)
	field.reset({"spawners": [{"speed": 80}]})
	eq(field.flags[key], 0, "a new turn resets removed/grazed flags")
	var ids := field.slots.map(func(b): return b.get_instance_id())
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var t0 := Time.get_ticks_usec()
	for i in 1800:
		field.sample((i % 900) / 120.0, Vector2(240, 160), Callable())
	var ms := (Time.get_ticks_usec() - t0) / 1800.0 / 1000.0
	eq(int(Performance.get_monitor(Performance.OBJECT_COUNT)), objects, "sampling creates no objects")
	eq(field.slots.map(func(b): return b.get_instance_id()), ids)
	check(ms < 2.0, "pooled sampler stays inside a small part of a phone frame")
	print("    (pooled sampling %.3f ms/step)" % ms)


func test_gravity_shield_and_shooter_controls_and_collisions() -> void:
	for hz in [30, 60, 120]:
		var motion := Motion.new()
		motion.reset("gravity")
		var p := Vector2(100, 175)
		var highest := p.y
		for frame in hz:
			p = motion.step(p, Vector2.RIGHT, p, Vector2(260, 180), 1.0 / hz, frame == 0, false)
			highest = minf(highest, p.y)
		check(highest < 140, "gravity jumps at %d Hz" % hz)
		eq(p.y, 175, "lands on the floor")
	var shield := Motion.new()
	shield.reset("shield")
	var center := Vector2(130, 90)
	eq(shield.step(center, Vector2.RIGHT, center, Vector2(260, 180), 0.01, false, false), center)
	check(shield.blocks_bullet(center, center + Vector2(20, 0), 6))
	check(not shield.blocks_bullet(center, center + Vector2(-20, 0), 6))
	check(not shield.blocks_bullet(center, center + Vector2(45, 0), 6))
	var shooter := Motion.new()
	shooter.reset("shooter")
	shooter.step(center, Vector2.ZERO, center, Vector2(260, 180), 0.01, false, true)
	check(shooter.breaks_bullet(center - Vector2(0, 3), 6))
	check(not shooter.breaks_bullet(center - Vector2(0, 3), 6), "a pulse opens one pod")
	eq(shooter.breaks, 1)
	eq(shooter.pulses.size(), Motion.PULSE_MAX)


func test_each_spar_has_a_kind_act_route_phase_and_spare_ending() -> void:
	for id in Data.Spars.ORDER:
		var s := _state(id)
		var base: String = s.turn_plan().wave.name
		eq(s.phase_index(s.enemies[0]), -1)
		s.act(0, 0, 1)
		eq(s.turn_plan().wave.name, s.enemies[0].waves[2].name, "ACT changes the actual next pattern")
		eq(s.turn_plan().wave.name, s.enemies[0].waves[2].name, "previewing does not consume the ACT")
		s.end_enemy_turn()
		eq(s.turn_plan().wave.name, base, "the redirect lasts one attack")
		s.act(0, 0, 2)
		eq(s.phase_index(s.enemies[0]), 0, "mercy changes phase without hitting anyone")
		eq(s.turn_plan().wave.name, s.enemies[0].waves[1].name)
		s.act(0, 0, 2)
		check(s.spare(0, 0))
		eq(s.outcome, "spared")
		eq(s.enemies[0].hp, s.enemies[0].max_hp)
		s.recover()
		eq(s.enemies[0].next_wave, -1)
		eq(s.phase_index(s.enemies[0]), -1)
		s.enemies[0].hp = int(s.enemies[0].max_hp) / 2
		eq(s.phase_index(s.enemies[0]), 0, "tiredness also changes phase")
		s.run_away()
		eq(s.outcome, "ran")


func _screen(rule: String = "normal", mode: String = "free") -> Control:
	fresh_save_root()
	preload("res://scripts/core/input_setup.gd").register()
	var b := Data.clean({"music": "@silence", "enemies": [{"attack": 3, "waves": [{"mode": mode, "box": {"w": 240, "h": 160}, "spawners": [{"from": "point", "point": [0.5, 0.5], "speed": 0, "stop": 0, "rule": rule}]}]}]})
	var s := Screen.new()
	s.setup(b, [State.member("me", "Aster")], [], [], [], SaveManager.root)
	tree.root.add_child(s)
	s._begin_round()
	s._enemy_turn()
	s._using_touch = true
	return s


func test_colour_rules_apply_to_live_collisions_and_telegraphs_are_safe() -> void:
	for rule in ["normal", "still", "move"]:
		for moving in [false, true]:
			var s := _screen(rule)
			var hp: int = s.state.party[0].hp
			s._physics_process(0.1)
			eq(s.state.party[0].hp, hp, "warnings cannot hurt")
			s.phase = "dodge"
			s.box = s.box_target
			s.pointer = s.arena_to_screen(s.heart + Vector2(15, 0))
			s.pointer_down = moving
			s._using_touch = false
			if not moving:
				s._using_touch = true
			s._dodge(0.01)
			eq(int(s.state.party[0].hp) < hp, Motion.hurts(rule, moving), rule + " collision rule")
			s.queue_free()
			await frames(2)


func test_rotated_touch_is_relative_offset_and_single_finger() -> void:
	var s := _screen()
	s.phase = "dodge"
	s.wave.rotation = 25.0
	s.wave_t = 3.0
	s._rotation = Patterns.rotation_at(s.wave, s.wave_t)
	s.box = s.box_target
	var point := Vector2(80, 60)
	check(s.screen_to_arena(s.arena_to_screen(point)).distance_to(point) < 0.001)
	var initial: Vector2 = s.heart
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = s.arena_to_screen(s.heart)
	touch.pressed = true
	s._gui_input(touch)
	s._dodge(0.05)
	check(s.heart.y < initial.y, "heart moves above the thumb")
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.position = Vector2.ZERO
	second.pressed = true
	s._gui_input(second)
	eq(s._finger, 0, "another finger cannot take over")
	touch.pressed = false
	s._gui_input(touch)
	var released: Vector2 = s.heart
	s._dodge(0.02)
	check(s.heart.distance_to(released) < 0.001, "lifting the finger stops movement")
	s.queue_free()
	await frames(2)


func test_releasing_keyboard_or_gamepad_directions_does_not_pull_toward_the_mouse() -> void:
	for gamepad in [false, true]:
		var s := _screen("still")
		s.phase = "dodge"
		s.box = s.box_target
		s._using_touch = false
		s.pointer = s.arena_to_screen(Vector2(20, 20))
		if gamepad:
			var event := InputEventJoypadButton.new()
			event.button_index = JOY_BUTTON_DPAD_RIGHT
			event.pressed = true
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			await frames(1)
		else:
			Input.action_press("move_right")
		s._dodge(0.02)
		check(s._keyboard_steering, "direction recognised: " + ("gamepad" if gamepad else "keyboard"))
		if gamepad:
			var event := InputEventJoypadButton.new()
			event.button_index = JOY_BUTTON_DPAD_RIGHT
			event.pressed = false
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			await frames(1)
		else:
			Input.action_release("move_right")
		var resting: Vector2 = s.heart
		s._dodge(0.02)
		check(s.heart.distance_to(resting) < 0.001, "released directions mean hold still: " + ("gamepad" if gamepad else "keyboard"))
		s.queue_free()
		await frames(2)


func test_party_moves_remain_optional_and_resolve_with_mercy() -> void:
	var s := _state("seed_post")
	s.party.append(State.member("pal", "Clover", 40, 6, 2, "guardian"))
	s.party.append(State.member("bud", "Reed", 40, 6, 2, "dreamer"))
	s.enemies[0].mercy = 35
	s.tp = 16
	eq(s.plan(0, {"cmd": "act", "target": 0, "arg": 3}), "")
	eq(s.next_member(), 2, "the team ACT reserves a helper")
	eq(s.plan(2, {"cmd": "spare", "target": 0}), "")
	s.resolve_queue()
	eq(s.outcome, "spared")
	eq(s.tp, 0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(2)
	var director: Node = main.game.battles
	var b := Data.from_template("seed_post", {})
	eq(director.party_for(["mochi"], b).size(), 1)
	b.allow_party = true
	eq(director.party_for(["mochi", "mochi"], b).size(), 2, "invited friends are real party members, without duplicates")
	main.queue_free()
	await frames(2)


func test_maker_opens_all_spars_and_can_edit_new_controls() -> void:
	fresh_save_root()
	for id in Data.Spars.ORDER:
		var maker: Control = load("res://scripts/battle/battle_maker.gd").new()
		tree.root.add_child(maker)
		maker.setup_maker(null, Data.from_template(id, {}))
		maker.advanced = true
		maker.refresh()
		await frames(2)
		var mode := maker.find_child("HeartMode", true, false) as OptionButton
		check(mode != null)
		if mode:
			mode.item_selected.emit(3)
			eq(maker.battle.enemies[0].waves[0].mode, "shooter")
		var saved: String = maker.save()
		check(saved != "")
		eq(Data.load_battle(saved).enemies[0].waves[0].mode, "shooter")
		maker.queue_free()
		await frames(2)
