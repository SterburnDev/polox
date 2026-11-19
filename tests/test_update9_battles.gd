extends "res://tests/test_case.gd"
const State := preload("res://scripts/battle/battle_state.gd")
const Data := preload("res://scripts/battle/battle_data.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")
const Art := preload("res://scripts/battle/bullet_art.gd")
const Transaction := preload("res://scripts/battle/battle_inventory.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const Items := preload("res://scripts/items/items.gd")
const Starter := preload("res://scripts/core/starter_content.gd")
const Json := preload("res://scripts/core/json_util.gd")
var main: Node

func _state() -> RefCounted:
	var s := State.new()
	var b := Data.demonstration("lantern_lesson")
	s.setup([State.member("me", "Me"), State.member("pip", "Pip", 40, 6, 2, "guardian"), State.member("mallow", "Mallow", 40, 6, 2, "dreamer")], [State.enemy(b.enemies[0])], 91)
	return s

func test_queue_reserves_tp_and_back_restores_it() -> void:
	var s := _state()
	s.tp = 24
	eq(s.plan(0, {"cmd": "magic", "spell": "mend", "target": 1}), "")
	eq(s.preview().tp, 0)
	eq(s.tp, 24, "planning spends nothing")
	check(s.plan(2, {"cmd": "magic", "spell": "mend", "target": 1}) != "", "can't promise TP twice")
	eq(s.undo_choice(), 0)
	eq(s.preview().tp, 24)
	eq(s.plan(0, {"cmd": "defend"}), "")
	eq(s.plan(1, {"cmd": "magic", "spell": "comet", "target": 0}), "")
	eq(s.preview().tp, 0)
	s.resolve_queue()
	eq(s.tp, 0, "Defend funds another member exactly once")
	var hp: int = s.enemies[0].hp
	eq(s.resolve_queue(), [], "cannot replay committed actions")
	eq(s.enemies[0].hp, hp)
	var capped := _state()
	capped.tp = 90
	capped.plan(0, {"cmd": "magic", "spell": "mend", "target": 0})
	capped.plan(1, {"cmd": "defend"})
	var expected: int = capped.preview().tp
	capped.resolve_queue()
	eq(capped.tp, expected, "cap arithmetic matches preview even when resolution is reordered")

func test_tired_is_not_spare_and_act_precedes_pacify() -> void:
	var s := _state()
	s.enemies[0].hp = 1
	s.enemies[0].tired = true
	check(not s.can_spare(0), "low HP/tired does not replace MERCY")
	s.enemies[0].tired = false
	s.plan(0, {"cmd": "defend"})
	s.plan(1, {"cmd": "act", "target": 0, "arg": 2})
	s.plan(2, {"cmd": "magic", "spell": "hush", "target": 0})
	s.resolve_queue()
	eq(s.outcome, "spared", "same-turn lullaby then Hush")
	eq(s.tp, 0)
	var failed := _state()
	failed.tp = 16
	failed.plan(2, {"cmd": "magic", "spell": "hush", "target": 0})
	failed.resolve_queue()
	eq(failed.tp, 16, "not tired: spell does not spend TP")
	check(not failed.enemies[0].spared)

func test_cooperation_and_downed_capabilities_are_enforced() -> void:
	var s := _state()
	# Battles are one-on-one since 1.27.5 and no stock ACT needs a friend, but the engine still
	# enforces one that does (an older saved battle's).
	s.enemies[0].acts[3] = (s.enemies[0].acts[3] as Dictionary).merged({"helpers": 1}, true)
	s.tp = 16
	eq(s.plan(0, {"cmd": "act", "target": 0, "arg": 3}), "")
	eq(s.next_member(), 2, "cooperative ACT reserves a helper's turn")
	check(s.plan(1, {"cmd": "fight", "target": 0, "arg": 0.5}) != "")
	s.undo_choice()
	s.party[1].down = true
	s.party[1].hp = 0
	check(s.plan(1, {"cmd": "defend"}) != "")
	check(s.plan(1, {"cmd": "magic", "spell": "hush", "target": 0}) != "", "unknown/downed spell refused")
	s.tp = 24
	s.plan(2, {"cmd": "magic", "spell": "mend", "target": 1})
	s.resolve_queue()
	check(not s.party[1].down and int(s.party[1].hp) == 24, "Mend revives")
	eq(s.fight(-1, 0, 0.5), 0)
	eq(s.fight(0, 99, 0.5), 0)

func test_last_item_is_reserved_and_consumed_once() -> void:
	var s := _state()
	s.items = [{"id": "cookie", "name": "Cookie", "heal": 15, "count": 1}]
	var used := {"n": 0}
	s.consume_item = func(_id):
		used.n += 1
		return true
	s.party[1].hp = 2
	eq(s.plan(0, {"cmd": "item", "target": 1, "arg": 0}), "")
	check(s.plan(1, {"cmd": "item", "target": 1, "arg": 0}) != "")
	eq(used.n, 0)
	s.undo_choice()
	eq(s.preview().stock[0], 1)
	s.plan(2, {"cmd": "item", "target": 1, "arg": 0})
	s.resolve_queue()
	s.resolve_queue()
	eq(used.n, 1)
	eq(s.party[1].hp, 17)
	eq(s.items[0].count, 0)

func test_retry_resets_encounter_not_just_hp() -> void:
	var s := _state()
	s.tp = 90
	s.turn = 3
	s.enemies[0].mercy = 75
	s.enemies[0].hp = 1
	s.party[0].hp = 0
	s.party[0].down = true
	s.outcome = "knocked_down"
	s.recover()
	eq(s.tp, 0)
	eq(s.turn, 0)
	eq(s.enemies[0].mercy, 0)
	eq(s.enemies[0].hp, s.enemies[0].max_hp)
	check(s.party.all(func(m): return not m.down and m.hp == m.max_hp))

func test_malformed_data_is_bounded_and_ids_cannot_escape() -> void:
	fresh_save_root()
	Starter.create_world("Battle validation", "Tester")
	var world_before := FileAccess.get_file_as_string(SaveManager.abs_path("world.json"))
	var b := Data.demonstration("paper_parade")
	for id in ["../world", "C:/outside", "../../settings", "a\\b", "."]:
		b.id = id
		eq(Data.save(b), "")
		eq(Data.load_battle(id), {})
	eq(FileAccess.get_file_as_string(SaveManager.abs_path("world.json")), world_before)
	var bad := Data.clean({"enemies": [{"acts": {}, "waves": [{"box": 4, "spawners": [3, {"point": [1], "trace": [3], "speed": "bad", "count": 99999}]}]}, {"acts": [{"tp": -100, "helpers": 99}], "waves": false}]})
	eq(bad.enemies[0].acts, [])
	eq(bad.enemies[1].acts[0].tp, 0)
	eq(bad.enemies[1].acts[0].helpers, 2)
	check(Patterns.bullets_at(bad.enemies[0].waves[0], 10).size() <= 384)
	eq(Data.clean({"version": 999}), {}, "future schemas refused")

func test_burst_ids_and_sparse_custom_art_do_not_alias_worlds() -> void:
	var wave := Patterns.template("fan")
	var bullets := Patterns.bullets_at(wave, 0.5)
	var ids := {}
	for b in bullets: ids[b.id] = true
	eq(ids.size(), bullets.size(), "each burst projectile has its own graze identity")
	fresh_save_root("battle_art_a")
	Starter.create_world("A", "Test")
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var aid := Art.save_custom(img)
	var tex := Art.custom_texture(aid)
	fresh_save_root("battle_art_b")
	Starter.create_world("B", "Test")
	img.fill(Color.RED)
	var bid := Art.save_custom(img)
	eq(aid, bid)
	check(Art.custom_texture(bid) != tex, "same local id loads different world's art")
	eq(Art.custom_texture(bid).get_image().get_pixel(0, 0), Color.RED)

func test_inventory_refund_keeps_unrelated_changes_and_commit_is_final() -> void:
	fresh_save_root()
	Starter.create_world("Snack test", "Test")
	GameState.load_world()
	var snack := Items.defaults("consumable")
	snack.name = "Test cookie"
	var id := Items.save_item(snack)
	Inventory.add(id, 3)
	var tx := Transaction.new()
	tx.begin()
	check(tx.consume(id))
	eq(Inventory.count(id), 2)
	Inventory.add(id, 4)
	check(tx.refund())
	eq(Inventory.count(id), 7, "only spent delta refunded; later additions survive")
	tx.refund()
	eq(Inventory.count(id), 7, "refund idempotent")
	check(tx.consume(id))
	tx.commit()
	tx.refund()
	eq(Inventory.count(id), 6, "victory consumption stays")

func _press(scr: Control, prefix: String, touch: bool) -> bool:
	await frames(2)
	for button in scr.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and (button.name == prefix or str(button.text).begins_with(prefix)):
			var pos: Vector2 = button.get_global_rect().get_center()
			for down in [true, false]:
				if touch:
					var t := InputEventScreenTouch.new()
					t.position = pos
					t.pressed = down
					main.get_viewport().push_input(t, true)
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.position = pos
				e.global_position = pos
				e.pressed = down
				main.get_viewport().push_input(e, true)
			await frames(2)
			return true
	var shown := PackedStringArray()
	for button in scr.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			shown.append(str(button.text))
	check(false, "missing button: %s (phase %s; showing: %s)" % [prefix, scr.phase, ", ".join(shown)])
	return false

func _phase(scr: Control, want: String, timeout: int = 16000) -> bool:
	var start := Time.get_ticks_msec()
	while is_instance_valid(scr) and scr.phase != want and Time.get_ticks_msec() - start < timeout:
		await frames(2)
	return check(is_instance_valid(scr) and scr.phase == want, "reached " + want)

func _nonviolent(touch: bool, story: bool = true) -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	GameState.settings["reduce_motion"] = true
	GameState.settings["battle_choose_for_friends"] = true
	GameState.settings["battle_assists"] = {"story": story}
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var b := Data.demonstration("paper_parade")
	main.game.battles.start(b, [])
	var start := Time.get_ticks_msec()
	while main.game.battles.screen == null and Time.get_ticks_msec() - start < 8000:
		await frames(2)
	var scr: Control = main.game.battles.screen
	if not check(scr != null): return
	await _phase(scr, "menu")
	eq(scr.state.party.size(), 1, "the player fights alone")
	for target in ["Paper fox", "Ribbon bird"]:
		await _press(scr, "Cmd_defend", touch)
		await _press(scr, "Defend (", touch)
		await _press(scr, "Begin turn", touch)
		await _phase(scr, "menu")
		await _press(scr, "Cmd_act", touch)
		if target == "Paper fox": await _press(scr, target, touch)
		await _press(scr, "Soft lullaby", touch)
		await _press(scr, "Begin turn", touch)
		await _phase(scr, "menu")
		await _press(scr, "Cmd_magic", touch)
		await _press(scr, "Hush", touch)
		if target == "Paper fox": await _press(scr, target, touch)
		check(scr.phase == "review", "one choice awaits review")
		if target == "Paper fox":
			await _press(scr, "Back", touch)
			check(scr.phase == "menu", "review Back restores player choice")
			await _press(scr, "Cmd_magic", touch)
			await _press(scr, "Hush", touch)
			await _press(scr, target, touch)
		await _press(scr, "Begin turn", touch)
		await _phase(scr, "menu" if target == "Paper fox" else "end")

	eq(scr.state.outcome, "spared", "complete peaceful encounter through real buttons")
	await _press(scr, "Done", touch)
	check(main.game.battles.screen == null)
	main.queue_free()
	await frames(3)
	GameState.settings.erase("battle_assists")
	GameState.settings.erase("battle_choose_for_friends")
	GameState.settings["reduce_motion"] = false

func test_complete_mouse_party_encounter() -> void:
	await _nonviolent(false)

func test_complete_touch_party_encounter() -> void:
	await _nonviolent(true)


## The kind way for real: no Story mode, so a lullaby has to make them TIRED before Hush works, and
## the enemies really attack in between (the heart dodges on its own here; nobody is hurt for good).
func test_peaceful_win_without_story_mode() -> void:
	await _nonviolent(false, false)


func _three() -> RefCounted:
	var s := State.new()
	var b := Data.demonstration("paper_parade")
	s.setup([State.member("me", "Me"), State.member("pip", "Pip", 40, 6, 2, "guardian"), State.member("mallow", "Mallow", 40, 6, 2, "dreamer")],
		[State.enemy(b.enemies[0]), State.enemy(b.enemies[1])], 7)
	for i in s.enemies.size():
		s.enemies[i]["waves"] = b.enemies[i].waves
	return s


func test_fight_timing_comes_at_the_turn_and_retargets_when_its_target_left() -> void:
	var s := _three()
	eq(s.plan(0, {"cmd": "fight", "target": 0}), "", "FIGHT plans without a timing")
	eq(s.fighters(), [0])
	s.set_timing(0, 0.5)
	s.enemies[0].tired = true
	s.tp = 16
	eq(s.plan(2, {"cmd": "magic", "spell": "hush", "target": 0}), "")
	var hp1: int = s.enemies[1].hp
	var events: Array = s.resolve_queue()
	check(bool(s.enemies[0].spared), "Hush plays before FIGHT")
	var fight: Array = events.filter(func(e): return str(e.cmd) == "fight")
	check(fight.size() == 1 and bool(fight[0].retarget) and int(fight[0].target) == 1, "the FIGHT turns to the one still here")
	check(int(s.enemies[1].hp) < hp1, "and lands")


func test_every_enemy_attacks_together_and_takes_turns_leading() -> void:
	var s := _three()
	var first: Dictionary = s.turn_plan(0)
	var second: Dictionary = s.turn_plan(1)
	check((first.owners as Array).has(0) and (first.owners as Array).has(1), "both foes add bullets")
	check(int(first.lead) != int(second.lead), "the lead changes turn by turn")
	s.enemies[0].spared = true
	var alone: Dictionary = s.turn_plan(2)
	check((alone.owners as Array).all(func(o): return int(o) == 1), "a spared foe stops attacking")
	s.enemies[1].skip_wave = true
	eq(s.turn_plan(3), {}, "someone sitting it out leaves an empty turn")


func test_a_knocked_down_friend_gets_back_up_after_a_few_turns_or_when_healed() -> void:
	var s := _three()
	s.party[1].hp = 1
	var t := 0
	while not bool(s.party[1].down) and t < 50:
		s.hit(0, 1)
		t += 1
	check(bool(s.party[1].down), "knocked down")
	for i in State.DOWN_TURNS - 1:
		s.end_enemy_turn()
		check(bool(s.party[1].down), "still resting after turn %d" % (i + 1))
	s.end_enemy_turn()
	check(not bool(s.party[1].down) and int(s.party[1].hp) == int(s.party[1].max_hp) / 4, "back up with a quarter of their HP")
	s.party[2].hp = 0
	s.party[2].down = true
	s.tp = 24
	eq(s.plan(0, {"cmd": "magic", "spell": "mend", "target": 2}), "")
	s.resolve_queue()
	check(not bool(s.party[2].down), "or at once, when healed")


func test_prepared_waves_give_exactly_the_same_bullets() -> void:
	for id in ["rain", "fan", "zigzag", "spiral", "heart_hug", "bouncers", "snow", "crosswind"]:
		var w := Patterns.template(id)
		if w.is_empty():
			continue
		var p := Patterns.prepare(w)
		for t in [0.3, 1.7, 4.9]:
			eq(JSON.stringify(Patterns.bullets_at(p, t)), JSON.stringify(Patterns.bullets_at(w, t)), "%s at %.1fs" % [id, t])


## Three friends, each choosing FIGHT by hand: Begin turn runs a bar for each of them in turn.
func test_each_fighter_presses_their_own_bar_through_the_real_buttons() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	GameState.settings["reduce_motion"] = true
	GameState.settings["battle_choose_for_friends"] = true   # (you choose for each friend)
	GameState.settings["battle_assists"] = {"story": true}
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	main.game.battles.start(Data.demonstration("lantern_lesson"), [])
	var start := Time.get_ticks_msec()
	while main.game.battles.screen == null and Time.get_ticks_msec() - start < 8000:
		await frames(2)
	var scr: Control = main.game.battles.screen
	if not check(scr != null): return
	await _phase(scr, "menu")
	var n: int = scr.state.party.size()
	for i in n:
		await _press(scr, "⚔ FIGHT", false)
	check(scr.phase == "review", "everyone's FIGHT awaits the review")
	await _press(scr, "Begin turn", false)
	for i in n:
		if not check(scr.phase == "fight_bar", "a bar for fighter %d" % (i + 1)):
			break
		eq(int(scr._fighter), i, "in party order")
		scr.bar_x = 0.5
		scr.press_fight()
		await frames(1)
	check(str(scr.phase) in ["text", "telegraph", "dodge", "end"], "then the turn plays")
	main.queue_free()
	await frames(3)
	GameState.settings.erase("battle_assists")
	GameState.settings.erase("battle_choose_for_friends")
	GameState.settings["reduce_motion"] = false
