extends "res://scripts/ui/screen_panel.gd"
## The Battle Maker: make a battle the way you make places.
##   Quick setup: who you face (a friend, their toughness), which patterns they use (from the
##           templates), draw a bullet, watch it play, Save, Test or Fight now.
##   Advanced (one click), in sections:
##     Encounter     name, an original spar to start from, friends along, battle speed
##     Enemies       the lineup (all at once or one after another), each enemy's stats, ACTs and lines
##     Waves         the order, each wave (reorder, duplicate, preview), every spawner (path: straight,
##                   aimed, arc, wave, spiral, orbit, bounce or traced along a line you draw; where
##                   from, how often, how many, how fast, spread, angle, turn, the seed), phases
##     Arena         the box (size, how it grows, tilt), the Soul's mode, hazard zones
##     Rules         how you win (spare or tire, spare only, last N turns), damage, Soul speed, rewards
##     Presentation  music, backdrop, effect, the opening line
##   A summary under the preview; problems listed at the top, each a link to its control.
##   Test plays the whole battle and comes back to the Maker as you left it.
## The preview plays the selected wave and can be scrubbed (patterns are seeded, so the same time
## always shows the same bullets). Drawn bullets keep their exact shape as their hitbox.
## Tags: [BATTLE_MAKER]

signal saved(id: String)

const BattleData := preload("res://scripts/battle/battle_data.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")
const BulletArt := preload("res://scripts/battle/bullet_art.gd")
const PixelPaintPanel := preload("res://scripts/ui/pixel_paint_panel.gd")
const Spells := preload("res://scripts/battle/battle_spells.gd")
const Modes := preload("res://scripts/battle/battle_maker_modes.gd")

var director: Node
var battle: Dictionary = {}
var enemy := 0
var wave_i := 0
var spawner_i := 0
var advanced := false
var preview: Control
var t := 0.0
var playing := true
var _scrub: HSlider            # (the preview's timeline: a slider is right for scrubbing)
var _left: VBoxContainer
var section := "encounter"
var _section_boxes: Dictionary = {}
var _section_btns: Dictionary = {}
var _summary: Label
const SECTIONS := ["encounter", "enemies", "waves", "arena", "rules", "presentation"]
const SECTION_NAMES := {"encounter": "Encounter", "enemies": "Enemies", "waves": "Waves", "arena": "Arena", "rules": "Rules", "presentation": "Presentation"}
var _loading := false
var _preview_hash := 0


class Preview extends Control:
	const Patterns := preload("res://scripts/battle/patterns.gd")
	const BulletArt := preload("res://scripts/battle/bullet_art.gd")
	var wave: Dictionary = {}
	var look: Dictionary = {}
	var t := 0.0
	var count := 0          # (tests) bullets drawn last frame
	var tracing := false
	var field := preload("res://scripts/battle/bullet_field.gd").new()
	var trace: Array = []   # points being drawn for a "traced" path (0..1 of the box)
	signal traced(points: Array)

	func _box() -> Rect2:
		var dimensions := Patterns.box_at(wave, t)
		var bw := dimensions.x
		var bh := dimensions.y
		var angle := absf(deg_to_rad(float(wave.get("rotation", 0))))
		var k := minf((size.x - 20.0) / (bw * cos(angle) + bh * sin(angle)), (size.y - 20.0) / (bh * cos(angle) + bw * sin(angle)))
		k = minf(k, 1.5)
		return Rect2((size - Vector2(bw, bh) * k) / 2.0, Vector2(bw, bh) * k)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0718"))
		if not look.is_empty():
			preload("res://scripts/battle/battle_look.gd").backdrop(self, size, str(look.get("backdrop", "black")), t, false)
			preload("res://scripts/battle/battle_look.gd").effect(self, size, str(look.get("effect", "none")), t, bool(GameState.settings.get("reduce_motion", false)))
		var b := _box()
		var inner := Patterns.box_at(field.wave, t)
		var k := b.size.x / inner.x
		draw_set_transform(b.get_center(), Patterns.rotation_at(wave, t), Vector2.ONE * k)
		var local := Rect2(-inner / 2, inner)
		draw_rect(local, Color.BLACK)
		draw_rect(local, Color.WHITE, false, 3.0 / k)
		preload("res://scripts/battle/battle_arena_view.gd").draw_hazards(self, wave.get("hazards", []), inner, k)
		field.sample(t, inner, Callable())
		count = field.count
		for i in field.count:
			var bl = field.slots[i]
			var bp: Vector2 = bl.position
			if bp.x >= 0.0 and bp.y >= 0.0 and bp.x <= inner.x and bp.y <= inner.y:   # only inside the box
				BulletArt.draw(self, bl.kind, bp - inner / 2, bl.scale)
				if bl.rule != "normal":
					draw_arc(bp - inner / 2, 9, 0, TAU, 12, Color("#65c7ff") if bl.rule == "still" else Color("#ffbf69"), 2)
		preload("res://scripts/battle/battle_arena_view.gd").draw_soul(self, Vector2.ZERO, str(wave.get("mode", "free")), 8.0)
		if trace.size() >= 2:
			for i in trace.size() - 1:
				draw_line(Vector2(trace[i][0], trace[i][1]) * inner - inner / 2, Vector2(trace[i + 1][0], trace[i + 1][1]) * inner - inner / 2, Color("#ffd166"), 2.0)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		draw_string(ThemeDB.fallback_font, Vector2(8, 18), "%.1f s" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))

	func _gui_input(event: InputEvent) -> void:
		if not tracing:
			return
		var b := _box()
		if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch:
			if event.pressed:
				trace = []
			else:
				tracing = false
				traced.emit(trace.duplicate())
		if event is InputEventMouseMotion or event is InputEventScreenDrag or ((event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed):
			if event is InputEventMouseMotion and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				return
			var p: Vector2 = (((event.position - b.get_center()).rotated(-Patterns.rotation_at(wave, t)) + b.size / 2) / b.size).clamp(Vector2.ZERO, Vector2.ONE)
			if trace.is_empty() or Vector2(trace[-1][0], trace[-1][1]).distance_to(p) > 0.03:
				trace.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
			queue_redraw()


func setup_maker(battle_director: Node, start: Dictionary) -> void:
	director = battle_director
	battle = BattleData.clean(start)
	if battle.is_empty():
		battle = BattleData.clean({})
	if (battle.enemies as Array).is_empty():
		battle.enemies = [BattleData.enemy_from_friend({"name": "Someone"})]
	setup("Battle Maker", Vector2(1180, 700))
	var upright := UiKit.upright_phone()   # a phone held upright: the preview on top, the controls under it
	var row: BoxContainer = UiKit.vbox(8) if upright else UiKit.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left_scroll := ScrollContainer.new()
	left_scroll.scroll_deadzone = preload("res://scripts/ui/ui_kit.gd").touch_deadzone()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.custom_minimum_size.x = 0 if upright else 430
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left = UiKit.vbox(8)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(_left)
	var right := UiKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if upright:
		row.add_child(right)
		row.add_child(left_scroll)
	else:
		row.add_child(left_scroll)
		row.add_child(right)
	preview = Preview.new()
	preview.size_flags_vertical = Control.SIZE_FILL if upright else Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size = Vector2(0, 230) if upright else Vector2(380, 280)
	preview.traced.connect(_on_traced)
	right.add_child(preview)
	var ctl := UiKit.hbox(8)
	ctl.add_child(UiKit.button("⏯", func(): playing = not playing, 60))
	_scrub = UiKit.slider(0.0, 6.0, 0.05, 0.0)
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.value_changed.connect(func(v):
		if not _loading:
			playing = false
			t = v)
	ctl.add_child(_scrub)
	right.add_child(ctl)
	_summary = UiKit.para("", 16, ThemeBuilder.MUTED)
	_summary.name = "Summary"
	right.add_child(_summary)
	var actions := UiKit.flow_row(8)
	actions.add_child(UiKit.button("Save", func(): save(), 120))
	var test := UiKit.button("▶ Test", func(): test_battle(), 120)
	test.name = "TestBattle"
	test.tooltip_text = "Play the whole battle, then come back here as you left it"
	actions.add_child(test)
	actions.add_child(UiKit.button("Save and fight", func(): fight_now(), 190))
	right.add_child(actions)
	refresh()


func _wave() -> Dictionary:
	var waves: Array = battle.enemies[enemy].waves
	wave_i = clampi(wave_i, 0, waves.size() - 1)
	return waves[wave_i]


func _spawner() -> Dictionary:
	var sp: Array = _wave().get("spawners", [])
	if sp.is_empty():
		sp.append(Patterns.spawner_defaults())
	spawner_i = clampi(spawner_i, 0, sp.size() - 1)
	return sp[spawner_i]


func refresh() -> void:
	_loading = true
	for c in _left.get_children():
		_left.remove_child(c)
		c.queue_free()
	_check_box()
	var top := UiKit.flow_row(6)
	var more := UiKit.button(("▼ " if advanced else "▶ ") + "Advanced: every detail, in sections", func():
		advanced = not advanced
		refresh(), 0)
	more.name = "AdvancedToggle"
	more.alignment = HORIZONTAL_ALIGNMENT_LEFT
	top.add_child(more)
	_left.add_child(top)
	if advanced:
		var chips := UiKit.flow_row(6)
		chips.name = "Sections"
		for sec in SECTIONS:
			var b := UiKit.button(str(SECTION_NAMES[sec]), func():
				section = sec
				_show_section(), 0)
			b.name = "Section_" + sec
			b.toggle_mode = true
			chips.add_child(b)
			_section_btns[sec] = b
		_left.add_child(chips)
		for sec in SECTIONS:
			var box := UiKit.vbox(8)
			box.name = "Box_" + sec
			_left.add_child(box)
			_section_boxes[sec] = box
			call("_section_" + sec, box)
		_show_section()
	else:
		_quick(_left)
	var w := _wave()
	preview.wave = w
	preview.look = BattleData.clean_look(battle.get("look", {}))
	preview.field.reset(w)
	_preview_hash = hash(w)
	BulletArt.prepare_wave(w)
	_scrub.max_value = float(w.get("duration", 6.0))
	_summary.text = summary_text()
	_loading = false


func _show_section() -> void:
	for sec in _section_boxes:
		if is_instance_valid(_section_boxes[sec]):
			_section_boxes[sec].visible = sec == section
	for sec in _section_btns:
		if is_instance_valid(_section_btns[sec]):
			_section_btns[sec].set_pressed_no_signal(sec == section)


## "2 enemies, one after another • 5 waves • Win: spare everyone • Reward: Cookie"
func summary_text() -> String:
	var rules: Dictionary = BattleData.clean_rules(battle.get("rules", {}))
	var waves := 0
	for e in battle.enemies:
		waves += (e.waves as Array).size()
	var bits := ["%d enem%s%s" % [battle.enemies.size(), "y" if battle.enemies.size() == 1 else "ies", ", one after another" if rules.lineup == "one_by_one" and battle.enemies.size() > 1 else ""],
		"%d wave%s" % [waves, "" if waves == 1 else "s"]]
	match str(rules.win):
		"spare":
			bits.append("Win: spare everyone")
		"survive":
			bits.append("Win: last %d turns" % int(rules.survive_turns))
	if not is_equal_approx(float(rules.damage), 1.0):
		bits.append("Damage ×%.2f" % float(rules.damage))
	var rw: Dictionary = BattleData.clean_rewards(battle.get("rewards", {}))
	if str(rw.item) != "":
		bits.append("Reward: " + str(preload("res://scripts/items/items.gd").load_item(str(rw.item)).get("name", rw.item)))
	return " • ".join(bits)


## What still needs doing, each a link to its control.
func _check_box() -> void:
	var issues: Array = BattleData.problems(battle)
	if issues.is_empty():
		return
	var box := PanelContainer.new()
	box.name = "Problems"
	box.add_theme_stylebox_override("panel", ThemeBuilder.box(Color(ThemeBuilder.DANGER, 0.12), Color(ThemeBuilder.DANGER, 0.7), 1, ThemeBuilder.RADIUS_M, 8))
	var v := UiKit.vbox(4)
	box.add_child(v)
	for p in issues:
		var b := UiKit.button("⚠ " + str(p.text), func(): jump_to(p), 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		b.tooltip_text = "Go to it"
		v.add_child(b)
	_left.add_child(box)


## Opens the section a problem is in and puts the focus on its control.
func jump_to(p: Dictionary) -> void:
	advanced = true
	section = str(p.get("section", "encounter"))
	if p.has("enemy"):
		enemy = clampi(int(p.enemy), 0, battle.enemies.size() - 1)
	if p.has("wave"):
		wave_i = int(p.wave)
	refresh()
	var target := _left.find_child("f_" + str(p.get("field", "")), true, false) as Control
	if target:
		UiKit.focus_later(target)
		UiKit.show_later(_left.get_parent() as ScrollContainer, target)


# --- Quick setup ---------------------------------------------------------------------------------

func _quick(v: VBoxContainer) -> void:
	var e: Dictionary = battle.enemies[enemy]
	_name_row(v)
	Modes.catalogue(v, self)
	_enemy_rows(v)
	_enemy_basics(v, e)
	_num(v, "Battle speed", 0.5, 1.5, 0.1, float(battle.get("speed", 1)), func(x): battle.speed = x, func(x): return "×%.1f" % x)
	v.add_child(UiKit.label("Their turns (waves)", 18, ThemeBuilder.MUTED))
	_wave_rows(v, e)
	_bullet_row(v)


func _name_row(v: Control) -> void:
	var name_field := UiKit.line_edit("Battle name", str(battle.name))
	name_field.name = "f_name"
	name_field.text_changed.connect(func(s): battle["name"] = s)
	v.add_child(UiKit.field_row("Name", name_field, 130))


func _enemy_rows(v: Control) -> void:
	var enemy_row := UiKit.flow_row(6)
	enemy_row.name = "f_enemies"
	for i in battle.enemies.size():
		var b := UiKit.button("%d. %s" % [i + 1, battle.enemies[i].name], func():
			enemy = i
			wave_i = 0
			spawner_i = 0
			refresh(), 0)
		b.toggle_mode = true
		b.set_pressed_no_signal(i == enemy)
		enemy_row.add_child(b)
	if battle.enemies.size() < 3:
		enemy_row.add_child(UiKit.button("+ Enemy", func():
			battle.enemies.append(BattleData.enemy_from_friend({"name": "New friend"}))
			enemy = battle.enemies.size() - 1
			wave_i = 0
			refresh(), 0))
	v.add_child(enemy_row)
	var tools := UiKit.flow_row(6)
	if battle.enemies.size() > 1:
		tools.add_child(_small("↑", "Earlier in the lineup", func(): _move(battle.enemies, enemy, -1, "enemy")))
		tools.add_child(_small("↓", "Later in the lineup", func(): _move(battle.enemies, enemy, 1, "enemy")))
	if battle.enemies.size() < 3:
		tools.add_child(_small("⧉", "Duplicate this enemy", func():
			battle.enemies.insert(enemy + 1, battle.enemies[enemy].duplicate(true))
			enemy += 1
			refresh()))
	if battle.enemies.size() > 1:
		tools.add_child(_small("✕", "Remove this enemy", func():
			battle.enemies.remove_at(enemy)
			enemy = 0
			wave_i = 0
			refresh()))
	if tools.get_child_count() > 0:
		v.add_child(tools)


func _enemy_basics(v: Control, e: Dictionary) -> void:
	var enemy_name := UiKit.line_edit("Enemy name", str(e.name))
	enemy_name.name = "f_enemy_name"
	enemy_name.text_changed.connect(func(s): e.name = s.left(40))
	v.add_child(UiKit.field_row("Enemy name", enemy_name, 130))
	var ids := Array(SaveManager.list_characters())
	var who := UiKit.option(["(a picture)"] + ids.map(func(id): return str(GameState.get_character(str(id)).get("name", id))), maxi(0, ids.find(str(e.character)) + 1))
	who.item_selected.connect(func(i):
		if i > 0:
			var c := GameState.get_character(str(ids[i - 1]))
			var keep: Array = e.waves
			battle.enemies[enemy] = BattleData.enemy_from_friend(c, str(e.preset))
			battle.enemies[enemy]["waves"] = keep
		refresh())
	v.add_child(UiKit.field_row("Who you face", who, 130))
	var presets := Array(BattleData.PRESETS.keys())
	var tough := UiKit.option(presets.map(func(p): return str(BattleData.PRESET_LABELS[p])), maxi(0, presets.find(str(e.preset))))
	tough.item_selected.connect(func(i):
		var p: Dictionary = BattleData.PRESETS[presets[i]]
		e["preset"] = presets[i]
		for k in ["hp", "attack", "defense", "mercy_max"]:
			e[k] = p[k]
		refresh())
	v.add_child(UiKit.field_row("Toughness", tough, 130))


func _wave_rows(v: Control, e: Dictionary) -> void:
	var waves: Array = e.waves
	var list := UiKit.vbox(4)
	list.name = "f_waves"
	for i in waves.size():
		var wrow := UiKit.hbox(4)
		var b := UiKit.button("%d. %s (%.0f s)" % [i + 1, str(waves[i].get("name", "Wave")), float(waves[i].get("duration", 6.0))], func():
			wave_i = i
			spawner_i = 0
			t = 0.0
			playing = true
			refresh(), 0)
		b.tooltip_text = "Select and preview this wave"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.set_pressed_no_signal(i == wave_i)
		wrow.add_child(b)
		wrow.add_child(_small("↑", "Earlier", func(): _move(waves, i, -1, "wave")))
		wrow.add_child(_small("↓", "Later", func(): _move(waves, i, 1, "wave")))
		if waves.size() < 20:
			wrow.add_child(_small("⧉", "Duplicate", func():
				waves.insert(i + 1, (waves[i] as Dictionary).duplicate(true))
				wave_i = i + 1
				refresh()))
		wrow.add_child(_small("✕", "Remove (a battle keeps at least one wave)", func():
			if waves.size() > 1:
				waves.remove_at(i)
				wave_i = clampi(wave_i, 0, waves.size() - 1)
				refresh()))
		list.add_child(wrow)
	v.add_child(list)
	var add := UiKit.option(["+ Add a pattern..."] + Array(Patterns.TEMPLATE_ORDER).map(func(id): return str(Patterns.TEMPLATES[id].name)), 0)
	add.item_selected.connect(func(i):
		if i > 0:
			waves.append(Patterns.template(Patterns.TEMPLATE_ORDER[i - 1]))
			wave_i = waves.size() - 1
			refresh())
	v.add_child(add)


func _bullet_row(v: Control) -> void:
	v.add_child(UiKit.label("Bullets", 18, ThemeBuilder.MUTED))
	var brow := UiKit.flow_row(6)
	brow.add_child(UiKit.button("Draw a bullet", func(): draw_bullet(), 0))
	var kinds := BulletArt.kinds()
	var cur := str(_spawner().get("bullet", "dot"))
	var kopt := UiKit.option(kinds.map(func(k): return BulletArt.label(str(k))), maxi(0, kinds.find(cur)))
	kopt.item_selected.connect(func(i):
		_spawner()["bullet"] = kinds[i])
	brow.add_child(kopt)
	v.add_child(brow)


## Moves list[i] by `dir` (-1 earlier, +1 later) and keeps it selected.
func _move(list: Array, i: int, dir: int, what: String) -> void:
	var j := i + dir
	if j < 0 or j >= list.size():
		return
	var item: Variant = list[i]
	list[i] = list[j]
	list[j] = item
	if what == "enemy":
		enemy = j
	else:
		wave_i = j
	refresh()


func _small(text: String, tip: String, on_press: Callable) -> Button:
	var b := UiKit.button(text, on_press, 44)
	b.tooltip_text = tip
	return b


## A number with − / + (stepper.gd) in a captioned row.
func _num(v: Control, caption: String, lo: float, hi: float, step: float, value: float, on_change: Callable, fmt: Callable = Callable(), cap_w: float = 150.0) -> HBoxContainer:
	var st := UiKit.stepper(lo, hi, step, value, fmt)
	st.value_changed.connect(func(x):
		if not _loading:
			on_change.call(x))
	v.add_child(UiKit.field_row(caption, st, cap_w))
	return st


# --- Advanced: the sections ------------------------------------------------------------------------

func _section_encounter(v: VBoxContainer) -> void:
	_name_row(v)
	Modes.catalogue(v, self)
	_num(v, "Battle speed", 0.5, 1.5, 0.1, float(battle.get("speed", 1)), func(x): battle.speed = x, func(x): return "×%.1f" % x)
	v.add_child(UiKit.para("Start from an original spar, or build your own: Enemies (who and how tough), Waves (their attacks), Arena (the box and hazards), Rules (how you win, rewards) and Presentation (music and look).", 16, ThemeBuilder.MUTED))


func _section_enemies(v: VBoxContainer) -> void:
	var e: Dictionary = battle.enemies[enemy]
	var rules: Dictionary = _rules()
	var lineup := UiKit.option(BattleData.LINEUP_NAMES, maxi(0, BattleData.LINEUPS.find(str(rules.lineup))))
	lineup.tooltip_text = "One after another: the next steps in when the one before is spared or tired out"
	lineup.item_selected.connect(func(i):
		rules["lineup"] = BattleData.LINEUPS[i]
		refresh())
	v.add_child(UiKit.field_row("Lineup", lineup, 150))
	_enemy_rows(v)
	_enemy_basics(v, e)
	_num(v, "HP", 1, 9999, 10, float(e.get("hp", 60)), func(x): e.hp = int(x))
	_num(v, "Attack", 0, 99, 1, float(e.get("attack", 5)), func(x): e.attack = int(x))
	_num(v, "Defense", 0, 99, 1, float(e.get("defense", 1)), func(x): e.defense = int(x))
	_num(v, "Mercy to spare", 1, 1000, 10, float(e.get("mercy_max", 100)), func(x): e.mercy_max = int(x))
	_num(v, "Tired below HP fraction", 0, 1, 0.05, float(e.get("tired_at", 0.25)), func(x): e.tired_at = x, func(x): return "%d%%" % roundi(x * 100), 190)
	_acts(v, e)
	_lines(v, e)


func _section_waves(v: VBoxContainer) -> void:
	var e: Dictionary = battle.enemies[enemy]
	var orders := UiKit.option(BattleData.ORDER_NAMES, maxi(0, BattleData.ORDERS.find(str(e.get("order", "cycle")))))
	orders.item_selected.connect(func(i): e["order"] = BattleData.ORDERS[i])
	v.add_child(UiKit.field_row("Wave order", orders, 150))
	_wave_rows(v, e)
	var w := _wave()
	var wname := UiKit.line_edit("Wave name", str(w.get("name", "Wave")))
	wname.text_changed.connect(func(x): w["name"] = x.left(48))
	v.add_child(UiKit.field_row("Wave name", wname, 150))
	_num(v, "Length (s)", 2.0, 15.0, 0.5, float(w.get("duration", 6.0)), func(x):
		w["duration"] = x
		_scrub.max_value = x)
	_bullet_row(v)
	var sp: Array = w.get("spawners", [])
	w["spawners"] = sp
	v.add_child(UiKit.label("Spawners: where bullets come from", 18, ThemeBuilder.MUTED))
	var srow := UiKit.flow_row(4)
	srow.name = "f_spawners"
	for i in sp.size():
		var b := UiKit.button("Spawner %d" % (i + 1), func():
			spawner_i = i
			refresh(), 0)
		b.toggle_mode = true
		b.set_pressed_no_signal(i == spawner_i)
		srow.add_child(b)
	srow.add_child(_small("+", "Add a spawner", func():
		sp.append(Patterns.spawner_defaults())
		spawner_i = sp.size() - 1
		refresh()))
	srow.add_child(_small("✕", "Remove this spawner", func():
		if sp.size() > 1:
			sp.remove_at(spawner_i)
			spawner_i = 0
			refresh()))
	v.add_child(srow)
	var s := _spawner()
	Modes.spawner_controls(v, s)
	var paths := Array(Patterns.PATHS)
	var popt := UiKit.option(paths.map(func(p): return str(p).capitalize()), maxi(0, paths.find(str(s.get("path", "straight")))))
	popt.item_selected.connect(func(i):
		s["path"] = paths[i]
		refresh())
	v.add_child(UiKit.field_row("Path", popt, 150))
	if str(s.get("path", "")) == "traced":
		v.add_child(UiKit.button("Draw the path on the preview", func():
			preview.tracing = true
			playing = false
			GameState.notify("Draw the path inside the box with the mouse or your finger."), 0))
	var froms := Array(Patterns.FROMS)
	var fopt := UiKit.option(froms.map(func(f): return str(f).capitalize()), maxi(0, froms.find(str(s.get("from", "top")))))
	fopt.item_selected.connect(func(i): s["from"] = froms[i])
	v.add_child(UiKit.field_row("From", fopt, 150))
	for f in [["every", "Every (s)", 0.05, 3.0, 0.05], ["count", "How many", 1, 12, 1], ["speed", "Speed", 20, 400, 5], ["spread", "Spread (°)", 0, 360, 5],
			["angle", "Angle (°)", -180, 360, 5], ["turn", "Turn (°/s)", -360, 360, 10], ["amp", "Wave size", 0, 120, 2], ["freq", "Wave speed", 0.1, 4.0, 0.1],
			["radius", "Orbit radius", 10, 150, 5], ["size", "Bullet size", 0.5, 3.0, 0.1], ["start", "Starts at (s)", 0, 12, 0.25], ["stop", "Stops at (s, -1 = end)", -1, 15, 0.25], ["seed", "Seed", 1, 999, 1]]:
		var key := str(f[0])
		_num(v, str(f[1]), float(f[2]), float(f[3]), float(f[4]), float(s.get(key, Patterns.spawner_defaults()[key])), func(x): s[key] = int(x) if key in ["count", "seed"] else x)
	var e2: Dictionary = battle.enemies[enemy]
	Modes.phase_controls(v, e2, refresh)
	for i in (e2.get("phases", []) as Array).size():
		var p: Dictionary = e2.phases[i]
		v.add_child(UiKit.button("▶ Preview phase %d (%s)" % [i + 1, str(p.get("name", ""))], func():
			wave_i = clampi(int(p.get("wave", 0)), 0, (e2.waves as Array).size() - 1)
			t = 0.0
			playing = true
			refresh(), 0))


func _section_arena(v: VBoxContainer) -> void:
	var w := _wave()
	v.add_child(UiKit.para("The box for wave %d (%s). Each wave has its own box." % [wave_i + 1, str(w.get("name", ""))], 16, ThemeBuilder.MUTED))
	var box: Dictionary = w.get("box", {"w": 240, "h": 160})
	w["box"] = box
	_num(v, "Box width", 120, 420, 10, float(box.get("w", 240)), func(x): box["w"] = x)
	_num(v, "Box height", 80, 300, 10, float(box.get("h", 160)), func(x): box["h"] = x)
	Modes.wave_controls(v, w)
	v.add_child(UiKit.label("Hazards: zones inside the box", 18, ThemeBuilder.MUTED))
	var hz: Array = w.get("hazards", [])
	w["hazards"] = hz
	for i in hz.size():
		var h: Dictionary = hz[i]
		var head := UiKit.hbox(6)
		var kind := UiKit.option(["Stings (like a bullet)", "Slows you down"], 0 if str(h.get("kind", "hurt")) == "hurt" else 1)
		kind.item_selected.connect(func(k): h["kind"] = Patterns.HAZARDS[k])
		kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(kind)
		head.add_child(_small("✕", "Remove this hazard", func():
			hz.remove_at(i)
			refresh()))
		v.add_child(head)
		for f in [["x", "From the left"], ["y", "From the top"], ["w", "Width"], ["h", "Height"]]:
			var key := str(f[0])
			_num(v, str(f[1]), 0.0 if key in ["x", "y"] else 0.05, 0.95 if key in ["x", "y"] else 1.0, 0.05, float(h.get(key, 0.2)), func(x): h[key] = x, func(x): return "%d%%" % roundi(x * 100))
	if hz.size() < 4:
		var add := UiKit.flow_row(6)
		add.add_child(UiKit.button("+ Stinging zone", func():
			hz.append({"kind": "hurt", "x": 0.0, "y": 0.8, "w": 1.0, "h": 0.2})
			refresh(), 0))
		add.add_child(UiKit.button("+ Slow zone", func():
			hz.append({"kind": "slow", "x": 0.35, "y": 0.0, "w": 0.3, "h": 1.0})
			refresh(), 0))
		v.add_child(add)


func _section_rules(v: VBoxContainer) -> void:
	var rules: Dictionary = _rules()
	var win := UiKit.option(BattleData.WIN_NAMES, maxi(0, BattleData.WINS.find(str(rules.win))))
	win.item_selected.connect(func(i):
		rules["win"] = BattleData.WINS[i]
		refresh())
	v.add_child(UiKit.field_row("How you win", win, 170))
	if str(rules.win) == "survive":
		_num(v, "Turns to last", 1, 20, 1, float(rules.survive_turns), func(x): rules["survive_turns"] = int(x), Callable(), 170)
	_num(v, "Damage you take", 0.25, 3.0, 0.25, float(rules.damage), func(x): rules["damage"] = x, func(x): return "×%.2f" % x, 170)
	_num(v, "Soul speed", 0.5, 2.0, 0.1, float(rules.soul_speed), func(x): rules["soul_speed"] = x, func(x): return "×%.1f" % x, 170)
	v.add_child(UiKit.label("Reward for winning or sparing", 18, ThemeBuilder.MUTED))
	var rw: Dictionary = BattleData.clean_rewards(battle.get("rewards", {}))
	battle["rewards"] = rw
	var Items := preload("res://scripts/items/items.gd")
	var ids := Array(Items.ids())
	var item := UiKit.option(["Nothing"] + ids.map(func(id): return str(Items.load_item(str(id)).get("name", id))), maxi(0, ids.find(str(rw.item)) + 1))
	item.name = "f_reward"
	item.item_selected.connect(func(i):
		rw["item"] = "" if i == 0 else str(ids[i - 1])
		refresh())
	v.add_child(UiKit.field_row("Item", item, 170))
	if str(rw.item) != "":
		_num(v, "How many", 1, 9, 1, float(rw.count), func(x): rw["count"] = int(x), Callable(), 170)
	var note := UiKit.line_edit("A line when you win (optional)", str(rw.note))
	note.text_changed.connect(func(x): rw["note"] = x.left(160))
	v.add_child(UiKit.field_row("Message", note, 170))
	# Solo uses the first role; invited friends use the other two.
	v.add_child(UiKit.label("Your magic", 18, ThemeBuilder.MUTED))
	for i in (3 if bool(battle.get("allow_party", false)) else 1):
		var role := UiKit.option(Spells.ROLE_NAMES, maxi(0, Spells.ROLES.find(str(battle.party_roles[i]))))
		role.item_selected.connect(func(k):
			battle.party_roles[i] = Spells.ROLES[k]
			battle.party_spells[i] = Spells.for_role(Spells.ROLES[k])
			refresh())
		v.add_child(UiKit.field_row("Role", role, 130))
		var spell_row := UiKit.flow_row(4)
		for id in Spells.BOOK:
			var cb := CheckBox.new()
			cb.text = str(Spells.BOOK[id].name)
			cb.custom_minimum_size.y = 48
			cb.button_pressed = id in battle.party_spells[i]
			cb.toggled.connect(func(on):
				if on and not id in battle.party_spells[i]: battle.party_spells[i].append(id)
				elif not on: battle.party_spells[i].erase(id))
			spell_row.add_child(cb)
		v.add_child(spell_row)


func _section_presentation(v: VBoxContainer) -> void:
	var look: Dictionary = BattleData.clean_look(battle.get("look", {}))
	battle["look"] = look
	var music := UiKit.option(["Use battle theme", "Original loop", "Silence"], 1 if str(battle.music) == "@original" else (2 if str(battle.music) == "@silence" else 0))
	music.item_selected.connect(func(i): battle.music = ["", "@original", "@silence"][i])
	v.add_child(UiKit.field_row("Music", music, 150))
	var bg := UiKit.option(BattleData.BACKDROP_NAMES, maxi(0, BattleData.BACKDROPS.find(str(look.backdrop))))
	bg.item_selected.connect(func(i):
		look["backdrop"] = BattleData.BACKDROPS[i]
		preview.look = look)
	v.add_child(UiKit.field_row("Backdrop", bg, 150))
	var fx := UiKit.option(BattleData.EFFECT_NAMES, maxi(0, BattleData.EFFECTS.find(str(look.effect))))
	fx.item_selected.connect(func(i):
		look["effect"] = BattleData.EFFECTS[i]
		preview.look = look)
	v.add_child(UiKit.field_row("Effect", fx, 150))
	var intro := UiKit.line_edit("When the battle starts (optional)", str(look.intro))
	intro.text_changed.connect(func(x): look["intro"] = x.left(160))
	v.add_child(UiKit.field_row("Opening line", intro, 150))
	v.add_child(UiKit.para("A battle skin (Settings) still replaces the backdrop. Effects stand still with Reduce motion.", 16, ThemeBuilder.MUTED))


func _rules() -> Dictionary:
	var r: Dictionary = BattleData.clean_rules(battle.get("rules", {}))
	if not battle.get("rules") is Dictionary or battle.rules != r:
		battle["rules"] = r
	return battle.rules


func _acts(v: Control, e: Dictionary) -> void:
	v.add_child(UiKit.label("Their ACTs", 18, ThemeBuilder.MUTED))
	var acts: Array = e.get("acts", [])
	for i in acts.size():
		var a: Dictionary = acts[i]
		var arow := UiKit.hbox(4)
		var an := UiKit.line_edit("Name", str(a.get("name", "")))
		an.text_changed.connect(func(x): a["name"] = x)
		arow.add_child(an)
		arow.add_child(_small("✕", "Remove this ACT", func():
			acts.remove_at(i)
			refresh()))
		v.add_child(arow)
		var at := UiKit.line_edit("What happens", str(a.get("text", "")))
		at.text_changed.connect(func(x): a["text"] = x)
		v.add_child(at)
		_num(v, "Mercy it gives", 0, 100, 5, float(a.get("mercy", 20)), func(x): a["mercy"] = int(x))
		_num(v, "TP cost", 0, 100, 5, float(a.get("tp", 0)), func(x): a.tp = int(x))
		Modes.act_controls(v, a, e.waves)
		# A helper ACT stays hidden when the player practices solo.
		if int(a.get("helpers", 0)) > 0:
			var solo_row := UiKit.hbox(8)
			var note := UiKit.para("Needs a friend, so it's hidden in one-on-one battles.", 16, ThemeBuilder.MUTED)
			note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			solo_row.add_child(note)
			solo_row.add_child(UiKit.button("Make it solo", func():
				a["helpers"] = 0
				refresh(), 0))
			v.add_child(solo_row)
		for flag in [["tired", "Makes them tired"], ["skip_wave", "Skip their next attack"]]:
			var cb := CheckBox.new()
			cb.text = flag[1]
			cb.custom_minimum_size.y = 48
			cb.button_pressed = bool(a.get(flag[0], false))
			cb.toggled.connect(func(on): a[flag[0]] = on)
			v.add_child(cb)
	v.add_child(UiKit.button("+ ACT", func():
		acts.append({"name": "Wave hello", "text": "You wave. They wave back, a little embarrassed.", "mercy": 20})
		e["acts"] = acts
		refresh(), 0))


func _lines(v: Control, e: Dictionary) -> void:
	v.add_child(UiKit.label("Their lines", 18, ThemeBuilder.MUTED))
	var lines: Dictionary = e.get("lines", {})
	e["lines"] = lines
	for k in [["intro", "When it starts"], ["check", "When you Check them"], ["spared", "When spared"], ["won", "When tired out"]]:
		var le := UiKit.line_edit(str(k[1]), str(lines.get(k[0], "")))
		le.text_changed.connect(func(x): lines[k[0]] = x)
		v.add_child(UiKit.field_row(str(k[1]), le, 170))


func _process(delta: float) -> void:
	if preview == null:
		return
	var current_hash := hash(_wave())
	if current_hash != _preview_hash:
		_preview_hash = current_hash
		preview.field.reset(_wave())
		BulletArt.prepare_wave(_wave())
	if playing:
		t += delta
		if t > float(_wave().get("duration", 6.0)):
			t = 0.0
		_loading = true
		_scrub.value = t
		_loading = false
	preview.t = t
	preview.queue_redraw()


func _on_traced(points: Array) -> void:
	if points.size() >= 2:
		_spawner()["trace"] = points
		playing = true
		t = 0.0


## Draw a bullet with the pixel canvas; its opaque pixels are its hitbox.
func draw_bullet() -> void:
	var p: Control = PixelPaintPanel.new()
	p.title_text = "Draw a bullet"
	var blank := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	p.start = blank
	director.world.main.open_panel(p)
	p.done.connect(func(img: Image):
		var id := BulletArt.save_custom(img)
		if id != "":
			_spawner()["bullet"] = "custom:" + id
			refresh())


func save() -> String:
	var id := BattleData.save(battle)
	if id == "":
		GameState.notify(BattleData.last_error)
		return ""
	battle["id"] = id
	saved.emit(id)
	GameState.notify("Saved \"%s\". Start it from any battle: Saved." % str(battle.name))
	return id


## Plays the whole battle (saved first), then reopens the Maker on the same section, enemy and wave.
func test_battle() -> void:
	var issues: Array = BattleData.problems(battle)
	if not issues.is_empty():
		jump_to(issues[0])
		GameState.notify(str(issues[0].text))
		return
	var id := save()
	if id == "" or director == null:
		return
	var keep := {"section": section, "advanced": advanced, "enemy": enemy, "wave_i": wave_i, "spawner_i": spawner_i}
	var d := director
	var b := BattleData.load_battle(id)
	close()
	d.test_from_maker(b, keep)   # (the director waits for the battle: this panel is gone by then)


func fight_now() -> void:
	var id := save()
	if id == "":
		return
	var d := director
	close()
	d.start(BattleData.load_battle(id), [])
