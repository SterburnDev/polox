extends "res://tests/test_case.gd"
## Phase 26, battles: the rules (FIGHT timing, ACT and mercy, SPARE, DEFEND, TP from grazing, ITEM,
## Rally, kind outcomes: win, spare, run, knocked down with nothing lost), patterns (seeded, every
## path), battle data (templates, saving), encounters (rare, Dream Worlds by default, Not now costs
## nothing, "I want to fight"), the local HUD skin (never synced or exported), and whole battles in
## the game with the mouse and with touch only.

const BattleState := preload("res://scripts/battle/battle_state.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")
const BattleData := preload("res://scripts/battle/battle_data.gd")
const Encounters := preload("res://scripts/battle/encounters.gd")
const BattleSkin := preload("res://scripts/battle/battle_skin.gd")
const BulletArt := preload("res://scripts/battle/bullet_art.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const ChoicePanel := preload("res://scripts/ui/choice_panel.gd")
const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const Inventory := preload("res://scripts/items/inventory.gd")

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
	GameState.settings.erase("battle_assists")
	GameState.settings.erase("encounters")
	main.queue_free()
	await frames(2)


func _state(assists: Dictionary = {}) -> RefCounted:
	var s: RefCounted = BattleState.new()
	var foe := BattleState.enemy({"name": "Mochi", "hp": 50, "attack": 6, "defense": 1, "mercy_max": 100,
		"acts": [{"name": "Check", "text": "", "mercy": 0}, {"name": "Compliment", "text": "You compliment Mochi.", "mercy": 40}, {"name": "Hum", "text": "Humming.", "mercy": 60, "tp": 16}]})
	s.setup([BattleState.member("player", "Sam"), BattleState.member("pip", "Pip", 30)], [foe], 3, assists)
	return s


func test_fight_timing_and_winning_kindly() -> void:
	var s := _state()
	eq(s.timing_quality(0.5), 1.0, "the middle is perfect")
	check(s.timing_quality(0.0) <= 0.31 and s.timing_quality(1.0) <= 0.31, "the ends still land a little")
	check(s.timing_quality(0.62) < 1.0, "a bit off is weaker")
	var wide := _state({"wide_timing": true})
	eq(wide.timing_quality(0.62), 1.0, "Wider timing makes the sweet spot bigger")
	var a: int = s.fight(0, 0, 0.5)
	var b: int = s.fight(0, 0, 0.05)
	check(a > b, "a perfect press hits harder (%d vs %d)" % [a, b])
	while s.outcome == "":
		s.fight(0, 0, 0.5)
	eq(s.outcome, "won")
	check(bool(s.enemies[0].tired_out) and not bool(s.enemies[0].spared), "tired out, never hurt for real")
	check(s.said.any(func(l): return str(l).contains("tired")), "and the words say so")


func test_act_mercy_spare_defend_tp_items() -> void:
	var s := _state()
	check(not s.can_spare(0), "not ready at first")
	check(not s.spare(0, 0), "SPARE too early just says so")
	eq(s.outcome, "")
	s.act(0, 0, 1)
	eq(int(s.enemies[0].mercy), 40)
	eq(s.act(0, 0, 2), "Not enough TP (16 needed).", "a TP ACT needs TP")
	s.defend(0)
	eq(s.tp, BattleState.DEFEND_TP, "DEFEND gives TP")
	s.act(0, 0, 2)
	eq(s.tp, 0, "and the ACT spent it")
	eq(int(s.enemies[0].mercy), 100)
	check(s.can_spare(0), "mercy full")
	check(s.spare(1, 0), "spared")
	eq(s.outcome, "spared")
	var t := _state()
	t.defend(0)
	var hit_def: int = t.hit(0, 0)
	t.end_enemy_turn()
	var hit_plain: int = t.hit(0, 0)
	check(hit_def <= hit_plain and hit_def >= 1, "DEFEND halves damage (%d vs %d)" % [hit_def, hit_plain])
	for _i in 10:
		t.graze()
	eq(t.tp, 10 * BattleState.GRAZE_TP + BattleState.DEFEND_TP, "grazes fill TP")
	t.party[0].hp = 5
	t.use_item(0, 15, "Cookie")
	eq(int(t.party[0].hp), 20, "ITEM heals")
	t.tp = 40
	check(t.rally(), "Rally with enough TP")
	eq(t.tp, 8)
	eq(_state().check_text(0).contains("HP 50/50"), true, "Check shows the stats")


func test_knocked_down_costs_nothing_and_run_is_free() -> void:
	var s := _state()
	var safety := 0
	while s.outcome == "" and safety < 200:
		s.hit(0)
		safety += 1
	eq(s.outcome, "knocked_down", "everyone down")
	check(s.said.any(func(l): return str(l).contains("Nothing is lost")), "said kindly")
	s.recover()
	eq(s.outcome, "", "back up")
	check(s.party.all(func(m): return int(m.hp) > 0 and not bool(m.down)), "everyone on their feet")
	var story := _state({"story": true})
	eq(story.hit(0), 0, "Story mode: bullets can't hurt")
	check(story.can_spare(0), "and anyone can be spared")
	var r := _state()
	r.run_away()
	eq(r.outcome, "ran")
	var sum: Dictionary = s.summary("Test")
	eq(str(sum.battle), "Test")
	check(sum.has("enemies") and sum.has("party") and sum.has("turns"), "what the Battle Log keeps")


func test_patterns_are_seeded_and_every_path_works() -> void:
	check(Patterns.TEMPLATE_ORDER.size() >= 15, "15+ pattern templates (%d)" % Patterns.TEMPLATE_ORDER.size())
	for id in Patterns.TEMPLATE_ORDER:
		var w := Patterns.template(id)
		var a := Patterns.bullets_at(w, 2.5)
		var b := Patterns.bullets_at(w, 2.5)
		eq(JSON.stringify(a), JSON.stringify(b), id + ": the same every time (seeded)")
		check(not a.is_empty(), id + ": bullets at 2.5 s")
	for path in Patterns.PATHS:
		var sp := Patterns.spawner_defaults()
		sp["path"] = path
		sp["from"] = "center" if path in ["spiral", "orbit"] else "top"
		if path == "traced":
			sp["trace"] = [[0.0, 0.0], [1.0, 1.0]]
			sp["from"] = "point"
		var w2 := {"duration": 6.0, "box": {"w": 240, "h": 160}, "spawners": [sp]}
		var bl := Patterns.bullets_at(w2, 1.2)
		check(not bl.is_empty(), path + ": bullets")
	# Aimed bullets go where the heart was.
	var aim := {"duration": 6.0, "box": {"w": 240, "h": 160}, "spawners": [{"path": "aimed", "from": "point", "point": [0.5, 0.0], "every": 5.0, "speed": 100}]}
	var to_left := Patterns.bullets_at(aim, 1.0, func(_t): return Vector2(0, 160))
	var to_right := Patterns.bullets_at(aim, 1.0, func(_t): return Vector2(240, 160))
	check(float(to_left[0].x) < 120.0 and float(to_right[0].x) > 120.0, "aimed at the heart")
	# Bouncing bullets stay inside the box.
	var bounce := Patterns.template("bouncers")
	for k in 20:
		for b2 in Patterns.bullets_at(bounce, 0.2 * k):
			check(float(b2.x) >= -0.1 and float(b2.x) <= 240.1 and float(b2.y) >= -0.1 and float(b2.y) <= 160.1, "bounce stays in")
	var slow := Patterns.scaled(Patterns.template("rain"), 0.5, 0.5)
	eq(float(slow.spawners[0].speed), 55.0, "slower")
	# Cheap enough for 60 frames a second: the busiest pattern, 100 frames.
	var busy := Patterns.template("double_spiral")
	var t0 := Time.get_ticks_usec()
	for k in 100:
		Patterns.bullets_at(busy, 6.0 + k * 0.016)
	var per_frame_ms := (Time.get_ticks_usec() - t0) / 100000.0
	print("    (busiest pattern: %.2f ms a frame)" % per_frame_ms)
	check(per_frame_ms < 8.0, "well under a 60 fps frame (%.2f ms)" % per_frame_ms)


func test_battle_data_templates_and_saving() -> void:
	fresh_save_root()
	StarterContent.create_world("Battle World", "Sam")
	var mochi_id := StarterContent.create_mochi()
	GameState.load_world()
	var mochi := GameState.get_character(mochi_id)
	mochi["likes"] = "stargazing, soup"
	check(BattleData.TEMPLATE_ORDER.size() >= 5, "5+ battle templates")
	var b := BattleData.from_template("star_shower", mochi)
	eq((b.enemies as Array).size(), 1)
	eq(str(b.enemies[0].character), mochi_id)
	eq((b.enemies[0].waves as Array).size(), 3)
	check((b.enemies[0].acts as Array).any(func(a): return str(a.name).contains("stargazing")), "an ACT from what they like")
	var id := BattleData.save(b)
	check(id != "", "saved")
	var back := BattleData.load_battle(id)
	eq(str(back.name), str(b.name))
	eq(BattleData.list().size(), 1)
	var junk := BattleData.clean({"name": "x".repeat(200), "enemies": [{"hp": -5, "attack": 900, "waves": []}, 3]})
	eq(str(junk.name).length(), 60)
	eq(int(junk.enemies[0].hp), 1)
	eq(int(junk.enemies[0].attack), 99)
	eq((junk.enemies[0].waves as Array).size(), 1, "never without a pattern")
	check(SyncFiles.allowed("slots/%s/battles/%s.json" % [SaveManager.slot_id, id], PackedStringArray([SaveManager.slot_id])), "saved battles travel with the world (Phone Link)")
	BattleData.delete(id)
	eq(BattleData.list().size(), 0)


func test_encounters_rare_dark_by_default_and_asking() -> void:
	var s := {"encounters": "rare"}
	check(Encounters.should_start(s, true, 9999.0, 0.0), "rare: can happen in a Dream World")
	check(not Encounters.should_start(s, true, 9999.0, 0.5), "but rarely")
	check(not Encounters.should_start(s, false, 9999.0, 0.0), "not in the Light World by default")
	check(Encounters.should_start({"encounters": "rare", "encounters_light_world": true}, false, 9999.0, 0.0), "unless you allow it")
	check(not Encounters.should_start(s, true, 30.0, 0.0), "never twice in a row")
	check(not Encounters.should_start({"encounters": "off"}, true, 9999.0, 0.0), "off is off")
	for yes in ["I want to fight", "i wanna fight you", "let's battle!", "Fight me", "can we spar?", "how about a duel"]:
		check(Encounters.asks_to_fight(yes), "asks: " + yes)
	for no in ["I don't want to fight", "we had a fight at work", "battle of the bands was fun", "hello"]:
		check(not Encounters.asks_to_fight(no), "doesn't: " + no)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var r := Encounters.reason_for({"memory_notes": ["Has a cat named Biscuit"]}, rng)
	check(r.contains("you have a cat named Biscuit"), "a reason from a memory: " + r)
	check(Encounters.reason_for({"likes": "soup"}, rng).contains("soup"), "or from what they like")
	check(Encounters.reason_for({}, rng) != "", "or a plain one")


func test_the_hud_skin_stays_on_this_pc() -> void:
	var root := fresh_save_root("skin")
	var dir := BattleSkin.folder_path(root)
	JsonUtil.ensure_dir(dir)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color("#ffd166"))
	img.save_png(dir.path_join("fight.png"))
	img.save_png(dir.path_join("heart.png"))
	var skin: RefCounted = BattleSkin.load_from(root)
	eq(skin.count(), 2, "your own pictures are used")
	check(skin.has("fight") and not skin.has("act"), "only the ones that are there")
	check(not SyncFiles.allowed("skins/battle_hud/fight.png", PackedStringArray(["any"])), "never synced to a phone")
	eq(BattleSkin.load_from(fresh_save_root("noskin")).count(), 0, "without any: the built-in HUD")
	var gi := FileAccess.get_file_as_string("res://.gitignore")
	check(not FileAccess.file_exists("res://skins"), "no skin in the project")


func _start_battle(g: Node, foe: String, assists: Dictionary = {}) -> Control:
	GameState.settings["battle_assists"] = assists
	var b := BattleData.from_template("friendly_spar", GameState.get_character(foe))
	g.battles.start(b, [])
	var t := Time.get_ticks_msec()
	while g.battles.screen == null and Time.get_ticks_msec() - t < 4000:
		await frames(2)
	return g.battles.screen


func _wait_phase(scr: Control, phases: Array, ms: int = 15000) -> bool:
	var t := Time.get_ticks_msec()
	while is_instance_valid(scr) and not str(scr.phase) in phases and Time.get_ticks_msec() - t < ms:
		if str(scr.phase) == "review":
			await frames(2)
			_click((scr.sub.get_child(0) as Button).get_global_rect().get_center()) # Update 9: explicit turn confirmation
		await frames(2)
	return is_instance_valid(scr) and str(scr.phase) in phases


func test_a_whole_battle_with_the_mouse() -> void:
	var g: Node = await _boot()
	var foe := str(g.actors.keys()[0])
	var before_aff := float(GameState.get_character(foe).get("affinity", 0.0))
	var bag_before := Inventory.total_items()
	var scr: Control = await _start_battle(g, foe)
	check(scr != null, "the battle is on screen")
	check(await _wait_phase(scr, ["menu"]), "your turn")
	await frames(3)   # (the buttons are laid out on the next frame)
	# Click ACT (the real button), then the Compliment.
	var act_btn: Button = scr.buttons.get_node_or_null("Cmd_act")
	check(act_btn != null and act_btn.custom_minimum_size.y >= 60, "big command buttons")
	_click(act_btn.get_global_rect().get_center())
	await frames(3)
	var compl: Button = null
	for b in scr.sub.get_children():
		if (b as Button).text.begins_with("Compliment"):
			compl = b
	check(compl != null, "the ACT list")
	await frames(2)
	for b in scr.sub.get_children():
		var rect: Rect2 = (b as Button).get_global_rect()
		check(rect.position.x >= scr.box.position.x and rect.end.x <= scr.box.end.x, "choices fit horizontally; long ACT lists scroll: " + (b as Button).text)
		check(b.custom_minimum_size.y >= 48, "a reachable touch target")
	_click(compl.get_global_rect().get_center())
	check(await _wait_phase(scr, ["dodge"]), "then their turn")
	# Dodge with the mouse: move the pointer; the heart follows at a capped speed.
	var start: Vector2 = scr.heart
	var target: Vector2 = scr.box.position + Vector2(10, 10)
	var mm := InputEventMouseMotion.new()
	mm.position = target
	scr._gui_input(mm)
	await frames(6)
	var moved: float = (scr.heart - start).length()
	check(moved > 2.0, "the heart follows the mouse")
	check(moved <= scr.HEART_SPEED * 0.3, "at a capped speed (%.1f px in 6 frames)" % moved)
	check(await _wait_phase(scr, ["menu", "end"], 20000), "the turn ends")
	# Fight: tap anywhere on the timing bar.
	if scr.phase == "menu":
		await frames(3)
		_click(scr.buttons.get_node("Cmd_fight").get_global_rect().get_center())
		await frames(2)
		# Update 9 (the turn order): FIGHT only picks who; the timing press comes when the turn begins.
		eq(scr.phase, "review", "FIGHT picks the target; the plan waits in the review")
		_click((scr.sub.get_child(0) as Button).get_global_rect().get_center())
		await frames(2)
		eq(scr.phase, "fight_bar", "Begin turn shows the timing bar")
		_click(scr.size / 2.0)
		await frames(2)
		check(str(scr.phase) in ["text", "telegraph", "dodge", "end"], "a tap plays the turn (%s)" % scr.phase)
	# Spare when ready: mercy to full by hand, then SPARE.
	await _wait_phase(scr, ["menu", "end"], 20000)
	if scr.phase == "menu":
		await frames(3)
		scr.state.enemies[0].mercy = int(scr.state.enemies[0].mercy_max)
		_click(scr.buttons.get_node("Cmd_spare").get_global_rect().get_center())
	check(await _wait_phase(scr, ["end"], 20000), "it ends")
	eq(scr.state.outcome, "spared", "spared")
	await frames(3)
	var done_btn: Button = scr.sub.get_child(0) if scr.sub.get_child_count() > 0 else null
	check(done_btn != null and done_btn.text == "Done")
	check(scr.list_with_text and scr.text.length() > 8, "what happened stays on screen above Done: " + scr.text)
	check(scr.box.encloses(done_btn.get_global_rect()), "Done sits inside the box")
	_click(done_btn.get_global_rect().get_center())
	await frames(4)
	check(g.battles.screen == null, "back to the world")
	var logbook: Array = GameState.world.get("battle_log", [])
	eq(str(logbook[-1].outcome) if not logbook.is_empty() else "", "spared", "in the Battle Log")
	check(float(GameState.get_character(foe).get("affinity", 0.0)) > before_aff, "a little closer")
	check((GameState.journal.moments as Array).any(func(m): return str(m.get("kind", "")) == "battle"), "a Memory Book page")
	eq(Inventory.total_items(), bag_before, "your bag is as it was")
	await _shutdown()


func _click(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	main.get_viewport().push_input(down, true)
	var up := down.duplicate()
	up.pressed = false
	main.get_viewport().push_input(up, true)


## A tap: the touch, plus the left click Godot's touch-to-mouse emulation produces from it.
func _tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = pressed
		main.get_viewport().push_input(t, true)
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.position = pos
		m.global_position = pos
		m.pressed = pressed
		main.get_viewport().push_input(m, true)


func test_touch_only_and_knocked_down() -> void:
	var g: Node = await _boot()
	var foe := str(g.actors.keys()[0])
	var scr: Control = await _start_battle(g, foe)
	check(await _wait_phase(scr, ["menu"]), "your turn")
	await frames(3)
	_tap(scr.buttons.get_node("Cmd_defend").get_global_rect().get_center())
	await frames(3)
	check(scr.sub.get_child_count() >= 2, "a tap opens DEFEND's choices")
	await frames(2)
	_tap((scr.sub.get_child(0) as Button).get_global_rect().get_center())
	check(await _wait_phase(scr, ["dodge"]), "a tap chose Defend")
	# Touch drag: the heart follows the finger.
	var start: Vector2 = scr.heart
	var dn := InputEventScreenTouch.new()
	dn.position = scr.box.position + Vector2(scr.box.size.x - 8, scr.box.size.y - 8)
	dn.pressed = true
	scr._gui_input(dn)
	await frames(8)
	check((scr.heart - start).length() > 2.0, "the heart follows your finger")
	# Knock everyone down: nothing is lost, Try again works.
	for _i in 200:
		if scr.state.outcome != "":
			break
		scr.state.hit(0)
	scr._end()
	eq(scr.state.outcome, "knocked_down")
	await frames(3)
	var again: Button = scr.sub.get_child(0)
	eq(again.text, "Try again")
	check(scr.text.contains("Nothing is lost"), "and says so")
	_tap(again.get_global_rect().get_center())
	check(await _wait_phase(scr, ["menu"]), "back on your feet, your turn")
	await _shutdown()


func test_a_friend_walks_up_in_a_dark_world() -> void:
	var g: Node = await _boot()
	g.room.data["side"] = "dark"
	g.battles.last_encounter = -1e9
	g.battles.forced_roll = 0.0
	await g.battles.try_encounter()
	var t := Time.get_ticks_msec()
	var panel: Control = null
	while panel == null and Time.get_ticks_msec() - t < 8000:
		for p in main.panels:
			if is_instance_valid(p) and p.get_script() == ChoicePanel:
				panel = p
		await frames(2)
	check(panel != null, "a friend walks up and asks")
	check(panel.title_label.text.contains("wants to battle"), panel.title_label.text if panel else "")
	var aff_before := float(GameState.get_character(str(g.actors.keys()[0])).get("affinity", 0.0))
	(panel.buttons[1] as Button).pressed.emit()   # Not now
	await frames(3)
	check(g.battles.screen == null, "Not now: no battle")
	eq(float(GameState.get_character(str(g.actors.keys()[0])).get("affinity", 0.0)), aff_before, "and it costs nothing")
	# Light World: no walk-ups by default.
	g.room.data["side"] = "light"
	g.battles.last_encounter = -1e9
	g.battles.forced_roll = 0.0
	check(not await g.battles.try_encounter(), "not in the Light World")
	await _shutdown()


func test_big_moments_skip_and_reduce_motion() -> void:
	var g: Node = await _boot()
	var foe := str(g.actors.keys()[0])
	# A tap skips the intro.
	var scr: Control = await _start_battle(g, foe)
	check(str(scr.phase) == "intro", "the intro plays")
	await frames(2)
	_tap(scr.get_global_rect().get_center())
	await frames(2)
	check(str(scr.phase) == "menu", "a tap skips it")
	scr.finish()
	await frames(3)
	# Reduce motion: short, still, no shaking.
	GameState.settings["reduce_motion"] = true
	var t0 := Time.get_ticks_msec()
	scr = await _start_battle(g, foe)
	check(await _wait_phase(scr, ["menu"], 4000), "your turn")
	var ms := Time.get_ticks_msec() - t0
	check(ms < 1500, "the flash and intro are short fades (%d ms)" % ms)
	scr._fx("sparkles", Vector2(100, 100), 1.5)
	check(float(scr.fx.back().life) <= 0.4, "effects are short fades")
	scr._pick({"cmd": "defend"})
	check(await _wait_phase(scr, ["dodge"], 4000), "their turn")
	var hit := false
	for _i in 200:   # put the heart on a bullet until one lands
		var bs: Array = Patterns.bullets_at(scr.wave, scr.wave_t, scr._heart_when)
		for b in bs:
			var bp := Vector2(float(b.x), float(b.y))
			if Rect2(Vector2(10, 10), scr.box.size - Vector2(20, 20)).has_point(bp):
				scr.heart = bp
				scr.pointer = scr.box.position + bp
				break
		await frames(1)
		if float(scr.invuln) > 0.0:
			hit = true
			break
	check(hit, "a bullet landed")
	eq(float(scr.shake), 0.0, "no screen shake")
	GameState.settings["reduce_motion"] = false
	scr.finish()
	await frames(3)
	await _shutdown()
