extends RefCounted
## Controls for the practice catalogue, arena rules, phases and ACT routes.
## Tags: [BATTLE_MAKER]

const Ui := preload("res://scripts/ui/ui_kit.gd")
const Data := preload("res://scripts/battle/battle_data.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")


static func catalogue(parent: Control, maker: Control) -> void:
	var ids: Array = Data.Spars.ORDER
	var option := Ui.option(["Load an original spar..."] + ids.map(func(id): return Data.Spars.NAMES[id]), 0)
	option.name = "OriginalSpars"
	option.item_selected.connect(func(i):
		if i > 0:
			maker.battle = Data.from_template(ids[i - 1], {})
			maker.enemy = 0
			maker.wave_i = 0
			maker.spawner_i = 0
			maker.t = 0.0
			maker.refresh())
	parent.add_child(option)
	var party := CheckBox.new()
	party.text = "Bring nearby friends (up to two)"
	party.button_pressed = bool(maker.battle.get("allow_party", false))
	party.toggled.connect(func(on):
		maker.battle.allow_party = on
		maker.refresh())
	parent.add_child(party)
	if not maker.advanced:   # (Advanced: Presentation has the music)
		var music := Ui.option(["Use battle theme", "Original loop", "Silence"], 1 if str(maker.battle.music) == "@original" else (2 if str(maker.battle.music) == "@silence" else 0))
		music.item_selected.connect(func(i): maker.battle.music = ["", "@original", "@silence"][i])
		parent.add_child(Ui.field_row("Music", music, 130))


static func wave_controls(parent: Control, wave: Dictionary) -> void:
	var mode := Ui.option(["Free", "Gravity", "Shield", "Shooter"], maxi(0, Patterns.MODES.find(str(wave.get("mode", "free")))))
	mode.name = "HeartMode"
	mode.item_selected.connect(func(i): wave.mode = Patterns.MODES[i])
	parent.add_child(Ui.field_row("Soul", mode, 130))
	for row in [["end_w", "Final width", 120, 420, 10, float(wave.box.w)], ["end_h", "Final height", 80, 300, 10, float(wave.box.h)]]:
		var key := str(row[0])
		var slider := Ui.stepper(row[2], row[3], row[4], float(wave.box.get(key, row[5])))
		slider.value_changed.connect(func(v): wave.box[key] = v)
		parent.add_child(Ui.field_row(row[1], slider, 130))
	var rotation := Ui.stepper(-30, 30, 1, float(wave.get("rotation", 0)))
	rotation.value_changed.connect(func(v): wave.rotation = v)
	parent.add_child(Ui.field_row("Box tilt (degrees)", rotation, 170))
	var warning := Ui.stepper(0.5, 3.0, 0.1, float(wave.get("telegraph", 0.8)))
	warning.value_changed.connect(func(v): wave.telegraph = v)
	parent.add_child(Ui.field_row("Warning (seconds)", warning, 170))
	var hint := Ui.line_edit("What to watch for", str(wave.get("hint", "")))
	hint.text_changed.connect(func(v): wave.hint = v.left(140))
	parent.add_child(Ui.field_row("Wave hint", hint, 130))


static func spawner_controls(parent: Control, spawner: Dictionary) -> void:
	var rule := Ui.option(["Always dodge", "Blue rings: hold still", "Amber arrows: keep moving"], maxi(0, Patterns.RULES.find(str(spawner.get("rule", "normal")))))
	rule.item_selected.connect(func(i): spawner.rule = Patterns.RULES[i])
	parent.add_child(Ui.field_row("Colour rule", rule, 130))
	var fragile := CheckBox.new()
	fragile.text = "Pulses can open this bullet"
	fragile.button_pressed = bool(spawner.get("fragile", false))
	fragile.toggled.connect(func(on): spawner.fragile = on)
	parent.add_child(fragile)


static func act_controls(parent: Control, act: Dictionary, waves: Array) -> void:
	var names: Array = ["Follow the normal phase"] + waves.map(func(w): return str(w.get("name", "Wave")))
	var next := Ui.option(names, clampi(int(act.get("next_wave", -1)) + 1, 0, waves.size()))
	next.item_selected.connect(func(i): act.next_wave = i - 1)
	parent.add_child(Ui.field_row("Next attack", next, 130))
	var helpers := Ui.stepper(0, 2, 1, int(act.get("helpers", 0)))
	helpers.value_changed.connect(func(v): act.helpers = int(v))
	parent.add_child(Ui.field_row("Helpers needed", helpers, 150))


static func phase_controls(parent: Control, enemy: Dictionary, refresh: Callable) -> void:
	if not enemy.get("phases") is Array:
		enemy["phases"] = []
	parent.add_child(Ui.label("Phases: trust or tiredness changes the attack", 18))
	var phases: Array = enemy.phases
	var waves: Array = enemy.waves
	for i in phases.size():
		var p: Dictionary = phases[i]
		var title := Ui.line_edit("Phase name", str(p.get("name", "Next phase")))
		title.text_changed.connect(func(v): p.name = v.left(48))
		parent.add_child(title)
		var line := Ui.line_edit("What they say when it starts (optional)", str(p.get("line", "")))
		line.text_changed.connect(func(v): p["line"] = v.left(160))
		parent.add_child(Ui.field_row("Their line", line, 130))
		for row in [["mercy", "Mercy fraction", 0.05, 1.0], ["hp", "HP fraction", 0.0, 0.95]]:
			var key := str(row[0])
			var slider := Ui.stepper(row[2], row[3], 0.05, float(p.get(key, 0.5)))
			slider.value_changed.connect(func(v): p[key] = v)
			parent.add_child(Ui.field_row(row[1], slider, 150))
		var attack := Ui.option(waves.map(func(w): return str(w.get("name", "Wave"))), clampi(int(p.get("wave", 0)), 0, waves.size() - 1))
		attack.item_selected.connect(func(k): p.wave = k)
		parent.add_child(Ui.field_row("Attack", attack, 130))
		parent.add_child(Ui.button("Remove phase", func():
			phases.remove_at(i)
			refresh.call(), 0))
	if phases.size() < 4:
		parent.add_child(Ui.button("+ Phase", func():
			phases.append({"name": "A little trust", "mercy": 0.5, "hp": 0.5, "wave": 0})
			refresh.call(), 0))
