extends "res://tests/test_case.gd"
## The Battle Maker's sections and what they change in a fight: rules (damage, how you win, Soul speed),
## the lineup (one after another), wave order, hazard zones, phase lines, rewards, the look; problems
## that link to their control; Test returns to the Maker as you left it; older battles still load.
## Tags: [BATTLE_MAKER]

const BattleData := preload("res://scripts/battle/battle_data.gd")
const BattleState := preload("res://scripts/battle/battle_state.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")
const Items := preload("res://scripts/items/items.gd")
const Inventory := preload("res://scripts/items/inventory.gd")

var main: Node


func _state(battle: Dictionary) -> RefCounted:
	var b := BattleData.clean(battle)
	var s: RefCounted = BattleState.new()
	var foes: Array = []
	for e in b.enemies:
		var f: Dictionary = BattleState.enemy(e)
		f["waves"] = e.waves
		foes.append(f)
	s.setup([BattleState.member("me", "Me", 40, 6, 2)], foes, 3, {}, b.rules)
	return s


func _two() -> Dictionary:
	var a := BattleData.from_template("friendly_spar", {"name": "Ana"})
	var second: Dictionary = (a.enemies[0] as Dictionary).duplicate(true)
	second["name"] = "Bo"
	a.enemies.append(second)
	return a


func test_battles_made_before_still_load_with_the_old_behaviour() -> void:
	var old := {"version": 3, "name": "Old spar", "enemies": [{"name": "Kit", "waves": [Patterns.template("rain")]}]}
	var c := BattleData.clean(old)
	check(not c.is_empty(), "an older battle still loads")
	eq(c.rules, {"win": "any", "survive_turns": 5, "damage": 1.0, "soul_speed": 1.0, "lineup": "together"}, "rules default to how it always played")
	eq(c.look.backdrop, "black", "the black backdrop")
	eq(c.enemies[0].order, "cycle", "waves in order, then again")
	eq(c.enemies[0].waves[0].hazards, [], "no hazards")


func test_everything_round_trips_through_saving() -> void:
	fresh_save_root()
	var b := _two()
	b["name"] = "Full"
	b["rules"] = {"win": "survive", "survive_turns": 3, "damage": 2.0, "soul_speed": 1.5, "lineup": "one_by_one"}
	b["rewards"] = {"item": "", "count": 2, "note": "Well played!"}
	b["look"] = {"backdrop": "sea", "effect": "bubbles", "intro": "Splash!"}
	b.enemies[0]["order"] = "shuffle"
	b.enemies[0].waves[0]["hazards"] = [{"kind": "slow", "x": 0.2, "y": 0.0, "w": 0.3, "h": 1.0}]
	b.enemies[0]["phases"] = [{"name": "Warm", "mercy": 0.5, "hp": 0.5, "wave": 1, "line": "Okay, for real now!"}]
	var id := BattleData.save(b)
	check(id != "", "saved")
	var l := BattleData.load_battle(id)
	eq(l.rules.win, "survive")
	eq(l.rules.survive_turns, 3)
	eq(l.rules.lineup, "one_by_one")
	eq(l.look.effect, "bubbles")
	eq(l.look.intro, "Splash!")
	eq(l.rewards.note, "Well played!")
	eq(l.enemies[0].order, "shuffle")
	eq(l.enemies[0].waves[0].hazards[0].kind, "slow")
	eq(l.enemies[0].phases[0].line, "Okay, for real now!")


func test_damage_and_spare_only_and_survive() -> void:
	var b := BattleData.from_template("friendly_spar", {"name": "Ana"})
	var base := _state(b)
	var d1: int = base.hit(0, 0)
	b["rules"] = {"damage": 2.0}
	var double := _state(b)
	var d2: int = double.hit(0, 0)
	eq(d2, d1 * 2, "Damage ×2 doubles each hit (%d -> %d)" % [d1, d2])
	b["rules"] = {"win": "spare"}
	var spare := _state(b)
	spare.enemies[0].hp = 3
	for i in 5:
		spare.fight(0, 0, 0.5)
	check(int(spare.enemies[0].hp) >= 1 and not bool(spare.enemies[0].tired_out), "Spare everyone: FIGHT can't tire them out")
	eq(spare.outcome, "", "and the battle goes on")
	b["rules"] = {"win": "survive", "survive_turns": 2}
	var last := _state(b)
	last.end_enemy_turn()
	eq(last.outcome, "", "one turn isn't enough")
	last.end_enemy_turn()
	eq(last.outcome, "spared", "two turns: a draw, everyone spared")


func test_one_after_another_and_wave_order() -> void:
	var b := _two()
	b["rules"] = {"lineup": "one_by_one"}
	var s := _state(b)
	check(s.valid_enemy(0) and not s.valid_enemy(1), "the second waits off stage")
	eq(s.active_enemies().size(), 1)
	s.enemies[0].spared = true
	s._check_end()
	eq(s.outcome, "", "the battle isn't over")
	check(s.valid_enemy(1), "the next steps in")
	check(s.said.any(func(t): return str(t).contains("steps in")), "and says so")
	var e: Dictionary = s.enemies[1]
	e["phases"] = []   # (phases, when there are any, choose the wave themselves)
	e["order"] = "once"
	e["next_wave"] = -1
	var n: int = (e.waves as Array).size()
	eq(s._wave_index(e, 0), 0)
	eq(s._wave_index(e, n + 3), n - 1, "In order, then keep the last")
	e["order"] = "shuffle"
	var seen := {}
	for t in 30:
		seen[s._wave_index(e, t)] = true
	check(seen.size() > 1, "Shuffled uses more than one wave")
	eq(s._wave_index(e, 7), s._wave_index(e, 7), "and is the same every time (seeded)")


func test_phase_lines_are_said_once() -> void:
	var b := BattleData.from_template("friendly_spar", {"name": "Ana"})
	b.enemies[0]["phases"] = [{"name": "Warm", "mercy": 0.1, "hp": 0.0, "wave": 0, "line": "Here I come!"}]
	var s := _state(b)
	s.enemies[0].mercy = int(s.enemies[0].mercy_max)
	s.end_enemy_turn()
	s.end_enemy_turn()
	eq(s.said.filter(func(t): return str(t).contains("Here I come!")).size(), 1, "the phase line, once")


func test_hazards_are_cleaned_and_bounded() -> void:
	var w := Patterns.clean_wave({"hazards": [{"kind": "lava", "x": 5, "y": -1, "w": 0, "h": 9}, {}, {}, {}, {}, {}]})
	eq(w.hazards.size(), 4, "at most four")
	eq(w.hazards[0].kind, "hurt", "unknown kinds sting")
	check(float(w.hazards[0].x) <= 0.95 and float(w.hazards[0].y) >= 0.0 and float(w.hazards[0].w) >= 0.05 and float(w.hazards[0].h) <= 1.0, "inside the box")


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _maker(g: Node) -> Control:
	g.battles.open_maker("")
	await frames(3)
	for p in main.panels:
		if is_instance_valid(p) and p.has_method("setup_maker"):
			return p
	return null


func test_sections_problems_and_test_returns_to_the_maker() -> void:
	var g: Node = await _boot()
	var m: Control = await _maker(g)
	check(m.find_child("Summary", true, false) != null and str(m.find_child("Summary", true, false).text).contains("wave"), "a summary under the preview")
	m.advanced = true
	m.refresh()
	await frames(2)
	for sec in ["encounter", "enemies", "waves", "arena", "rules", "presentation"]:
		check(m.find_child("Section_" + sec, true, false) != null, "section " + sec)
	m.section = "arena"
	m._show_section()
	check((m.find_child("Box_arena", true, false) as Control).visible and not (m.find_child("Box_rules", true, false) as Control).visible, "one section at a time")
	check(m.find_children("*", "HSlider", true, false).size() <= 1, "steppers, not sliders (only the preview's timeline)")
	# A problem links to its control.
	m.battle["name"] = ""
	m.refresh()
	await frames(2)
	var link: Button = null
	for b in (m.find_child("Problems", true, false) as Control).find_children("*", "Button", true, false):
		if str(b.text).contains("name"):
			link = b
	check(link != null, "a missing name is listed")
	link.pressed.emit()
	await frames(3)
	eq(m.section, "encounter", "the link opens its section")
	eq(m.get_viewport().gui_get_focus_owner(), m.find_child("f_name", true, false), "and focuses the field")
	m.battle["name"] = "Round trip"
	m.section = "rules"
	m.enemy = 0
	m.wave_i = 1
	m.refresh()
	# A reward item.
	var item := Items.defaults("snack")
	item["name"] = "Test Cookie"
	var item_id := Items.save_item(item)
	m.battle["rewards"] = {"item": item_id, "count": 2, "note": ""}
	m.battle["rules"] = {"win": "survive", "survive_turns": 1}
	m.test_battle()
	var t := Time.get_ticks_msec()
	while g.battles.screen == null and Time.get_ticks_msec() - t < 6000:
		await frames(2)
	check(g.battles.screen != null, "Test starts the battle")
	var before := Inventory.count(item_id)
	g.battles.screen.state.end_enemy_turn()
	eq(g.battles.screen.state.outcome, "spared", "lasting the turns wins")
	g.battles.screen.finish()
	t = Time.get_ticks_msec()
	var back: Control = null
	while back == null and Time.get_ticks_msec() - t < 6000:
		await frames(2)
		for p in main.panels:
			if is_instance_valid(p) and p.has_method("setup_maker"):
				back = p
	check(back != null, "Test comes back to the Maker")
	if back:
		eq(back.section, "rules", "on the same section")
		eq(back.wave_i, 1, "and the same wave")
		check(back.advanced, "in Advanced")
		eq(str(back.battle.name), "Round trip")
	eq(Inventory.count(item_id), before + 2, "the reward was given")
	main.queue_free()
	await frames(2)
