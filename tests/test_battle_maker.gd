extends "res://tests/test_case.gd"
## Phase 27, the Battle Maker: an enemy from a friend with a toughness preset, patterns from 15+
## templates, spawners with every path (a traced one drawn on the preview), the preview scrubbed to
## any time (the same bullets every time), a drawn bullet whose pixels are its hitbox, Simple and
## Advanced views, Save and Fight now.

const BattleData := preload("res://scripts/battle/battle_data.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")
const BulletArt := preload("res://scripts/battle/bullet_art.gd")

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
	main.queue_free()
	await frames(2)


func _maker(g: Node) -> Control:
	g.battles.open_maker("")
	await frames(3)
	for p in main.panels:
		if is_instance_valid(p) and p.has_method("setup_maker"):
			return p
	return null


func test_simple_view_patterns_preview_and_save() -> void:
	var g: Node = await _boot()
	var m: Control = await _maker(g)
	check(m != null, "the Battle Maker opens")
	check(not m.advanced, "Simple by default")
	eq((m.battle.enemies[0].waves as Array).size(), 3, "a friendly spar to start from")
	# Add a pattern from the templates.
	var add: OptionButton = null
	for o in m.find_children("*", "OptionButton", true, false):
		if (o as OptionButton).get_item_text(0).begins_with("+ Add a pattern"):
			add = o
	check(add != null and add.item_count >= 16, "15+ pattern templates to add")
	add.select(5)
	add.item_selected.emit(5)
	await frames(2)
	eq((m.battle.enemies[0].waves as Array).size(), 4, "added")
	eq(m.wave_i, 3, "and selected")
	# The preview plays and can be scrubbed: the same time shows the same bullets.
	m.playing = false
	m.t = 2.0
	await frames(2)
	var n1: int = m.preview.count
	m.t = 4.0
	await frames(2)
	m.t = 2.0
	await frames(2)
	eq(m.preview.count, n1, "scrubbing back shows the same bullets")
	check(n1 > 0, "bullets in the preview")
	var id: String = m.save()
	check(id != "", "saved")
	eq(BattleData.load_battle(id).enemies[0].waves.size(), 4, "with its patterns")
	await _shutdown()


func test_advanced_spawners_traced_paths_and_drawn_bullets() -> void:
	var g: Node = await _boot()
	var m: Control = await _maker(g)
	m.advanced = true
	m.refresh()
	await frames(2)
	var labels := m.find_children("*", "Label", true, false).map(func(l): return str(l.text))
	for want in ["Path", "From", "Every (s)", "Speed", "Spread (°)", "Seed", "Box width", "Their ACTs", "Their lines"]:
		check(labels.has(want), "Advanced shows " + want)
	# A traced path: drawn on the preview with the pointer.
	var s: Dictionary = m._spawner()
	s["path"] = "traced"
	m.refresh()
	await frames(2)
	m.preview.tracing = true
	var b: Rect2 = m.preview._box()
	var pts := [Vector2(0.1, 0.1), Vector2(0.5, 0.5), Vector2(0.9, 0.2)]
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = b.position + pts[0] * b.size
	m.preview._gui_input(down)
	for p in pts:
		var mv := InputEventMouseMotion.new()
		mv.position = b.position + p * b.size
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.preview._gui_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b.position + pts[-1] * b.size
	m.preview._gui_input(up)
	check((m._spawner().get("trace", []) as Array).size() >= 3, "the path was drawn")
	var w: Dictionary = m._wave()
	var bl := Patterns.bullets_at(w, 0.5)
	check(not bl.is_empty(), "bullets follow it")
	# A drawn bullet: a thin bar. Its pixels are its hitbox (pixel-exact).
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(0, 7, 16, 2), Color.WHITE)
	var bid := BulletArt.save_custom(img)
	check(bid != "", "saved as a bullet")
	var kind := "custom:" + bid
	check(BulletArt.kinds().has(kind), "it's in the bullet list")
	var near := BulletArt.distance(kind, Vector2(100, 100), 1.0, Vector2(110, 100))   # along the bar
	var far := BulletArt.distance(kind, Vector2(100, 100), 1.0, Vector2(100, 110))    # above its middle
	check(near < 2.0, "touching along the bar (%.1f)" % near)
	check(far > 5.0, "but not above it, where nothing is drawn (%.1f)" % far)
	await _shutdown()


func test_save_and_fight_now() -> void:
	var g: Node = await _boot()
	var m: Control = await _maker(g)
	m.battle["name"] = "My spar"
	m.fight_now()
	var t := Time.get_ticks_msec()
	while g.battles.screen == null and Time.get_ticks_msec() - t < 5000:
		await frames(2)
	check(g.battles.screen != null, "it starts right away")
	eq(str(g.battles.screen.battle.name), "My spar")
	check(BattleData.list().any(func(x): return str(x.name) == "My spar"), "and it's saved")
	g.battles.screen.finish()
	await frames(3)
	await _shutdown()


func test_new_before_a_battle_opens_the_maker() -> void:
	var g: Node = await _boot()
	g.battles.open_setup("")
	await frames(3)
	var setup: Control = g.main.panels.back()
	var new_btn: Button = setup.find_child("Mode_new", true, false)
	check(new_btn != null, "New... is there before a battle")
	new_btn.pressed.emit()
	await frames(3)
	check(g.main.panels.any(func(p): return is_instance_valid(p) and p.has_method("setup_maker")), "and opens the Battle Maker")
	check(not is_instance_valid(setup) or setup.is_queued_for_deletion() or not g.main.panels.has(setup), "in place of the setup")
	await _shutdown()
