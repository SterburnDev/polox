extends "res://tests/test_case.gd"
## The accessibility audit (1.29), on a phone-sized window and on a desktop one, over every main screen:
## - touch targets: everything you can press, type in or drag is at least 44 x 44 screen pixels (48 for
##   buttons on a phone: ui_kit.gd sizes them for a finger);
## - contrast: every piece of text against what is behind it, by the WCAG 2 formula: 4.5 to 1, or 3 to 1
##   for large text (24 px and up); a see-through surface is judged against the worst the world could
##   put behind it;
## - Reduce motion: with it on, nothing on any screen keeps moving, and nothing slides or fades for longer
##   than a short fade.
## A finding names the screen, the control and the numbers, so the fix is where the control is made.

const WorldMenu := preload("res://scripts/world/world_menu.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

const MIN_TARGET := 44.0        # screen pixels, each way
const TEXT_CONTRAST := 4.5
const LARGE_TEXT_CONTRAST := 3.0
const LARGE_TEXT := 24          # px
const SETTLE_S := 0.45          # how long a screen may take to arrive with Reduce motion on

var main: Node
var _size_before := Vector2i.ZERO
var _min_before := Vector2i.ZERO


## The game at its title screen, in a window of that size.
func _boot(size: Vector2i, touch: bool, reduce_motion := false) -> void:
	fresh_save_root()
	_size_before = tree.root.size
	_min_before = tree.root.min_size
	tree.root.min_size = Vector2i.ZERO
	tree.root.size = size
	GameState.settings["touch_ui"] = "on" if touch else "off"
	GameState.settings["reduce_motion"] = reduce_motion
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)


## ...and in a new world, with a home mapped.
func _start(size: Vector2i, touch: bool, reduce_motion := false) -> Node:
	await _boot(size, touch, reduce_motion)
	main.begin_new_world()
	await frames(3)
	_put_cards_away()
	HomeMapper.build_home({"home_type": "house", "floors": 2, "rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1}, "my_room": {"floor": 1}}, {}, "")
	await frames(2)
	return main.game


func _put_cards_away() -> void:
	for n in main.ui.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()


func _done() -> void:
	GameState.settings["touch_ui"] = "auto"
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)
	tree.root.size = _size_before
	tree.root.min_size = _min_before


## Every main screen, by name. Each is made fresh when asked for.
func _screens(g: Node) -> Dictionary:
	return {
		"menu": func(): return WorldMenu.make(g), "bag": func(): return WorldMenu.bag(g), "friends": func(): return WorldMenu.friends(g),
		"me": func(): return WorldMenu.sheet(g, 0), "looks": func(): return WorldMenu.sheet(g, 1), "gear": func(): return WorldMenu.sheet(g, 2),
		"workshop": func(): return WorldMenu.workshop(g), "rooms": func(): return WorldMenu.room_list(g),
		"world": func():
			var s: Control = load("res://scripts/ui/world_sheet.gd").new()
			s.setup_world(g)
			return s,
		"map": func():
			var m: Control = load("res://scripts/ui/world_map_view.gd").new()
			m.setup_map(g)
			return m,
		"my home": func():
			var h: Control = load("res://scripts/home/map_home_panel.gd").new()
			h.setup_home(g)
			return h,
		"tell": func():
			var tp: Control = load("res://scripts/home/tell_polox_panel.gd").new()
			tp.setup_tell(g, "We painted my room green.")
			return tp,
		"journal": func(): return load("res://scripts/home/journal_panel.gd").new(),
		"story": func(): return load("res://scripts/ui/story_panel.gd").new(),
		"memory": func(): return load("res://scripts/ui/memory_book.gd").new(),
		"dreams": func(): return load("res://scripts/ui/dreams_board.gd").new(),
		"bible": func(): return load("res://scripts/ui/world_bible_editor.gd").new(),
		"chat log": func(): return load("res://scripts/ui/log_viewer.gd").new(),
		"help": func(): return load("res://scripts/ui/help_panel.gd").new(),
		"worlds": func(): return load("res://scripts/ui/save_menu.gd").new(),
		"quests": func(): return load("res://scripts/ui/quest_log_panel.gd").new(),
		"almanac": func(): return load("res://scripts/ui/almanac_panel.gd").new(),
		"settings": func(): return load("res://scripts/ui/settings_screen.gd").new(),
	}


## Opens one screen and waits for it to arrive. Settings is audited page by page (`page` >= 0).
func _open(g: Node, key: String, page := -1) -> Control:
	var p: Control = _screens(g)[key].call()
	if "main" in p and p.get("main") == null:
		p.set("main", main)
	if "game" in p and p.get("game") == null:
		p.set("game", g)
	main.open_panel(p)
	await frames(3)
	await tree.create_timer(SETTLE_S).timeout
	if page >= 0:
		p.show_page(page)
		await frames(3)
	return p


## Screen pixels for a length in the game's canvas units.
func _px(units: float) -> float:
	return units * float(tree.root.size.y) / main.get_viewport().get_visible_rect().size.y


func _path(c: Node, top: Node) -> String:
	var names := PackedStringArray()
	var n := c
	while n != null and n != top and names.size() < 4:
		names.insert(0, n.name if not str(n.name).begins_with("@") else n.get_class())
		n = n.get_parent()
	var words := ""
	if c is Button and str(c.text) != "":
		words = " \"%s\"" % str(c.text).left(24)
	elif c is Label:
		words = " \"%s\"" % str(c.text).left(24)
	elif c is LineEdit:
		words = " (field \"%s\")" % str(c.placeholder_text).left(20)
	return "/".join(names) + words


# --- Touch targets ----------------------------------------------------------------------------------

## Whether a control is one a finger aims at.
func _pressable(c: Control) -> bool:
	if not c.is_visible_in_tree() or c.mouse_filter == Control.MOUSE_FILTER_IGNORE or c.size.x <= 0.0 or c.size.y <= 0.0:
		return false
	if c is ScrollBar:
		return false   # (touch scrolls by dragging the list itself: the bars are hidden on phones)
	return c is BaseButton or c is LineEdit or c is TextEdit or c is Slider or c is SpinBox


## {where: "w x h"} for everything pressable under `root` that is smaller than `least` screen pixels.
func _small_targets(root: Control, screen: String, least: float) -> Dictionary:
	var out := {}
	for c in root.find_children("*", "Control", true, false) + [root]:
		if not _pressable(c):
			continue
		var w := _px((c as Control).get_global_rect().size.x)
		var h := _px((c as Control).get_global_rect().size.y)
		if w < least - 0.5 or h < least - 0.5:
			out["%s: %s" % [screen, _path(c, root)]] = "%d x %d" % [int(round(w)), int(round(h))]
	return out


func _audit_targets(size: Vector2i, touch: bool) -> Dictionary:
	var g: Node = await _start(size, touch)
	var found := {}
	found.merge(_small_targets(main.ui, "the world", MIN_TARGET))
	for key in _screens(g):
		var pages := 1
		var p: Control = await _open(g, key)
		if key == "settings":
			pages = p.tabs.get_tab_count()
		for i in pages:
			if key == "settings":
				p.show_page(i)
				await frames(3)
			found.merge(_small_targets(p, key if pages == 1 else "settings, " + str(p.tabs.get_tab_title(i)), MIN_TARGET))
		p.queue_free()
		await frames(1)
	await _done()
	return found


func test_touch_targets_on_a_phone() -> void:
	for size in [Vector2i(412, 892), Vector2i(360, 780)]:
		var found: Dictionary = await _audit_targets(size, true)
		eq(found, {}, "smaller than %d x %d screen pixels on a %s phone" % [MIN_TARGET, MIN_TARGET, size])


func test_click_targets_on_a_desktop() -> void:
	var found: Dictionary = await _audit_targets(Vector2i(1280, 720), false)
	eq(found, {}, "smaller than %d x %d pixels at 1280 x 720" % [MIN_TARGET, MIN_TARGET])


# --- Contrast ---------------------------------------------------------------------------------------

## (The formula itself is the theme's: theme_builder.gd contrast(), over(), luminance().)
static func contrast(a: Color, b: Color) -> float:
	return ThemeBuilder.contrast(a, b)


static func over(top: Color, under: Color) -> Color:
	return ThemeBuilder.over(top, under)


static func luminance(c: Color) -> float:
	return ThemeBuilder.luminance(c)


## The colour a style box fills with: a flat box's, or the glass's (glass_box.gd), else nothing.
func _fill_of(sb: StyleBox) -> Variant:
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).bg_color if (sb as StyleBoxFlat).draw_center else null
	if sb != null and sb.get("base") is Color:
		return sb.get("base")
	return null


## The surface a control paints behind itself, if any: the style box of the state it is in.
func _own_surface(c: Control) -> Variant:
	if c is ColorRect:
		return (c as ColorRect).color
	var slot := ""
	if c is BaseButton:
		slot = "disabled" if (c as BaseButton).disabled else ("pressed" if (c as BaseButton).button_pressed else "normal")
	elif c is LineEdit or c is TextEdit:
		slot = "normal" if bool(c.get("editable")) else "read_only"
	elif c is PanelContainer or c is Panel or c is TabContainer:
		slot = "panel"
	if slot == "" or not c.has_theme_stylebox(slot):
		return null
	return _fill_of(c.get_theme_stylebox(slot))


## How much of its tint Liquid Glass lays over a world of brightness `lum` (0 to 1): the shader's own rule
## (shaders/liquid_glass.gdshader), which thickens the tint over a bright world and thins it over a dark one.
static func liquid_strength(tint_alpha: float, lum: float) -> float:
	return clampf(tint_alpha + smoothstep(0.32, 0.85, lum) * 0.36 - smoothstep(0.18, 0.0, lum) * 0.12, 0.0, 0.94)


## The surfaces behind a control's text, nearest first, down to the first solid one: each [colour] for a
## flat or glass box, or [tint, "liquid"] for Liquid Glass (liquid_glass.gd), which reads what is behind it.
func _layers(c: Control) -> Array:
	var layers: Array = []
	var n: Node = c
	while n != null and n is Control:
		var surface: Variant = _own_surface(n)
		if surface != null:
			var col: Color = surface
			col.a *= (n as Control).modulate.a
			layers.append([col])
			if col.a >= 0.995:
				break
		elif n.get("tint") is Color and n.has_method("solid_style"):
			layers.append([n.get("tint"), "liquid"])
		n = n.get_parent()
	return layers


## Every backdrop this text could have: the one solid surface behind it, or, where the world shows
## through, the surfaces laid over a world from black to white in ten steps (the worst of them counts).
func _backdrops(c: Control) -> Array:
	var layers := _layers(c)
	var worlds: Array = []
	if not layers.is_empty() and (layers[-1] as Array).size() == 1 and (layers[-1][0] as Color).a >= 0.995:
		var base: Color = layers.pop_back()[0]
		worlds = [Color(base.r, base.g, base.b, 1.0)]
	else:
		for step in 11:
			worlds.append(Color(step / 10.0, step / 10.0, step / 10.0, 1.0))
	var out: Array = []
	for world in worlds:
		var under: Color = world
		for i in range(layers.size() - 1, -1, -1):
			var layer: Array = layers[i]
			var col: Color = layer[0]
			if layer.size() > 1:
				col.a = liquid_strength(col.a, under.r * 0.299 + under.g * 0.587 + under.b * 0.114)
			under = over(col, under)
		out.append(under)
	return out


## [colour, size] of a control's text, or [] when it shows none.
func _text_of(c: Control) -> Array:
	if c is Label:
		if str(c.text).strip_edges() == "":
			return []
		var settings: LabelSettings = (c as Label).label_settings
		if settings:
			return [settings.font_color, settings.font_size]
		return [c.get_theme_color("font_color"), c.get_theme_font_size("font_size")]
	if c is Button:
		if str(c.text).strip_edges() == "" or (c as Button).disabled:
			return []   # (a control you can't use is outside the rule; it is dimmed on purpose)
		var slot := "font_pressed_color" if (c as Button).button_pressed else "font_color"
		return [c.get_theme_color(slot), c.get_theme_font_size("font_size")]
	if c is LineEdit:
		if not (c as LineEdit).editable:
			return []   # (a field you can't use is outside the rule, like a disabled button)
		if str(c.text) == "" and str(c.placeholder_text) != "":
			return [c.get_theme_color("font_placeholder_color"), c.get_theme_font_size("font_size")]
		if str(c.text) != "":
			return [c.get_theme_color("font_color"), c.get_theme_font_size("font_size")]
	return []


## The outline (or the drop shadow) drawn round a control's letters, when it has one strong enough to read
## the letters against: that is what text laid straight over the world relies on.
func _halo(c: Control) -> Variant:
	if c is Label and (c as Label).label_settings:
		var ls: LabelSettings = (c as Label).label_settings
		if ls.outline_size >= 2 and ls.outline_color.a >= 0.5:
			return ls.outline_color
		if ls.shadow_size >= 1 and ls.shadow_color.a >= 0.5:
			return ls.shadow_color
		return null
	if c.get_theme_constant("outline_size") >= 2 and c.get_theme_color("font_outline_color").a >= 0.5:
		return c.get_theme_color("font_outline_color")
	if c is Label and c.get_theme_color("font_shadow_color").a >= 0.5:
		return c.get_theme_color("font_shadow_color")
	return null


## {where: "ratio (needs n)"} for the text under `root` that is too faint against what is behind it.
func _faint_text(root: Control, screen: String) -> Dictionary:
	var out := {}
	for c in root.find_children("*", "Control", true, false):
		if not (c as Control).is_visible_in_tree() or (c as Control).size.x <= 0.0:
			continue
		var text: Array = _text_of(c)
		if text.is_empty():
			continue
		var colour: Color = text[0]
		var alpha := colour.a
		var n: Node = c
		while n != null and n is CanvasItem:
			alpha *= (n as CanvasItem).modulate.a
			n = n.get_parent()
		var halo: Variant = _halo(c)
		var ratio := 99.0
		var seen := colour
		var behind := Color.BLACK
		for backdrop in _backdrops(c):
			var under: Color = over(halo, backdrop) if halo != null else backdrop
			var ink := over(Color(colour.r, colour.g, colour.b, clampf(alpha, 0.0, 1.0)), under)
			if contrast(ink, under) < ratio:
				ratio = contrast(ink, under)
				seen = ink
				behind = under
		var needs := LARGE_TEXT_CONTRAST if int(text[1]) >= LARGE_TEXT else TEXT_CONTRAST
		if ratio < needs - 0.05:
			out["%s: %s" % [screen, _path(c, root)]] = "%.1f (needs %.1f; %s on %s, %d px)" % [ratio, needs, seen.to_html(false), behind.to_html(false), int(text[1])]
	return out


func test_the_formula() -> void:
	check(is_equal_approx(contrast(Color.WHITE, Color.BLACK), 21.0), "white on black is 21 to 1")
	check(is_equal_approx(contrast(Color.WHITE, Color.WHITE), 1.0))
	check(absf(contrast(Color("#777777"), Color.WHITE) - 4.48) < 0.02, "#777 on white: the well-known near miss, " + str(contrast(Color("#777777"), Color.WHITE)))
	eq(over(Color(1, 1, 1, 0.5), Color.BLACK).to_html(false), "808080")
	check(is_equal_approx(liquid_strength(0.5, 1.0), 0.86), "Liquid Glass thickens its tint over a bright world")
	check(is_equal_approx(liquid_strength(0.5, 0.25), 0.5) and liquid_strength(0.5, 0.0) < 0.5, "and thins it over a dark one")


## The theme's own pairs, in every world's palette: the text colours the game uses on the surfaces it
## puts them on.
func test_the_theme_colours_have_contrast() -> void:
	var low := {}
	for world in ThemeBuilder.PALETTES:
		var pal: Dictionary = ThemeBuilder.PALETTES[world]
		for surface in ["bg", "panel", "raised", "hover"]:
			var inks := [["cream", ThemeBuilder.CREAM], ["white", Color.WHITE]]
			if surface != "hover":   # (a hovered key carries only its own label, cream or white)
				inks += [["muted", Color(str(pal.muted))], ["yellow", ThemeBuilder.YELLOW], ["mint", ThemeBuilder.MINT], ["aqua", ThemeBuilder.AQUA], ["danger", ThemeBuilder.DANGER]]
			for ink in inks:
				var ratio := contrast(ink[1], Color(str(pal[surface])))
				if ratio < TEXT_CONTRAST:
					low["%s: %s on %s" % [world, ink[0], surface]] = "%.1f" % ratio
		# A selected key is the yolk with the world's darkest colour on it; a hint in an empty field is faded.
		if contrast(Color(str(pal.bg)), ThemeBuilder.YELLOW) < TEXT_CONTRAST:
			low["%s: selected key" % world] = "%.1f" % contrast(Color(str(pal.bg)), ThemeBuilder.YELLOW)
		var hint := ThemeBuilder.faded(Color(str(pal.muted)), Color(str(pal.bg)), 0.6)
		if contrast(over(hint, Color(str(pal.bg))), Color(str(pal.bg))) < TEXT_CONTRAST:
			low["%s: field hint" % world] = "%.1f" % contrast(over(hint, Color(str(pal.bg))), Color(str(pal.bg)))
	eq(low, {}, "text colours under 4.5 to 1 on the theme's surfaces")
	eq(ThemeBuilder.faded(Color.WHITE, Color.BLACK, 0.6).a, 0.6, "a fade that is already readable is left as asked")
	check(ThemeBuilder.faded(Color("#777777"), Color.BLACK, 0.3).a > 0.3, "one that isn't is made stronger")


func test_text_contrast_on_every_screen() -> void:
	for setup in [[Vector2i(412, 892), true], [Vector2i(1280, 720), false]]:
		var g: Node = await _start(setup[0], setup[1])
		var found := {}
		found.merge(_faint_text(main.ui, "the world"))
		for key in _screens(g):
			var pages := 1
			var p: Control = await _open(g, key)
			if key == "settings":
				pages = p.tabs.get_tab_count()
			for i in pages:
				if key == "settings":
					p.show_page(i)
					await frames(3)
				found.merge(_faint_text(p, key if pages == 1 else "settings, " + str(p.tabs.get_tab_title(i))))
			p.queue_free()
			await frames(1)
		await _done()
		eq(found, {}, "text too faint against what is behind it at %s" % setup[0])


## The places that are not panels: the title screen, a chat with a friend and a battle's commands.
func test_the_title_a_chat_and_a_battle() -> void:
	var BattleData: Script = load("res://scripts/battle/battle_data.gd")
	for setup in [[Vector2i(412, 892), true], [Vector2i(1280, 720), false]]:
		var small := {}
		var faint := {}
		await _boot(setup[0], setup[1])
		await tree.create_timer(0.8).timeout
		small.merge(_small_targets(main.ui, "title", MIN_TARGET))
		faint.merge(_faint_text(main.ui, "title"))
		main.begin_new_world()
		await frames(3)
		_put_cards_away()
		var g: Node = main.game
		var friend := str(g.actors.keys()[0])
		g.approach_character(friend)
		var t := Time.get_ticks_msec()
		while not (g.dialogue as Control).is_visible_in_tree() and Time.get_ticks_msec() - t < 8000:
			await frames(2)
		check((g.dialogue as Control).is_visible_in_tree(), "the chat opened at %s" % setup[0])
		await tree.create_timer(0.6).timeout
		small.merge(_small_targets(g.dialogue, "chat", MIN_TARGET))
		faint.merge(_faint_text(g.dialogue, "chat"))
		g.dialogue.close_box()
		await frames(3)
		g.battles.start(BattleData.from_template("friendly_spar", GameState.get_character(friend)), [])
		t = Time.get_ticks_msec()
		while g.battles.screen == null and Time.get_ticks_msec() - t < 4000:
			await frames(2)
		var battle: Control = g.battles.screen
		check(battle != null, "the battle opened at %s" % setup[0])
		if battle:
			t = Time.get_ticks_msec()
			while str(battle.phase) != "menu" and Time.get_ticks_msec() - t < 8000:
				await frames(2)
			small.merge(_small_targets(battle, "battle", MIN_TARGET))
			faint.merge(_faint_text(battle, "battle"))
		await _done()
		eq(small, {}, "too small to hit at %s" % setup[0])
		eq(faint, {}, "too faint at %s" % setup[0])


# --- Reduce motion ----------------------------------------------------------------------------------

## Where everything on the UI is and how big, right now: {control: [position, size, scale, rotation]}.
func _places(roots: Array) -> Dictionary:
	var out := {}
	for root in roots:
		if not is_instance_valid(root):
			continue
		for c in (root as Node).find_children("*", "Control", true, false) + [root]:
			if c is Control and (c as Control).is_visible_in_tree():
				var t: Transform2D = (c as Control).get_global_transform()
				out[c] = [t.origin, (c as Control).size, t.get_scale(), t.get_rotation()]
	return out


## What moved, grew or turned between two looks: {name: "from -> to"}. Text that changes (a clock) is not motion.
func _moved(before: Dictionary, after: Dictionary, top: Node) -> Dictionary:
	var out := {}
	for c in before:
		if not is_instance_valid(c) or not after.has(c):
			continue
		var a: Array = before[c]
		var b: Array = after[c]
		if (a[0] as Vector2).distance_to(b[0]) > 0.5 or (a[2] as Vector2).distance_to(b[2]) > 0.005 or absf(float(a[3]) - float(b[3])) > 0.002:
			out[_path(c, top)] = "%s x%s -> %s x%s" % [a[0], a[2], b[0], b[2]]
	return out


## Tweens that never end (a pulse, a bob, a shimmer).
func _endless() -> int:
	var n := 0
	for t in tree.get_processed_tweens():
		if t.is_valid() and t.is_running() and t.get_loops_left() == -1:
			n += 1
	return n


## With Reduce motion on: a screen is where it will stay from its first frames (no slide, no pop, no
## bounce), nothing on it keeps moving, and nothing loops for ever. Fades are allowed: they don't move.
func test_reduce_motion_stills_every_screen() -> void:
	for setup in [[Vector2i(412, 892), true], [Vector2i(1280, 720), false]]:
		var g: Node = await _start(setup[0], setup[1], true)
		await tree.create_timer(0.6).timeout
		var found := {}
		var hud_before := _places([main.ui])
		await tree.create_timer(0.4).timeout
		for k in _moved(hud_before, _places([main.ui]), main.ui):
			found["the world: " + str(k)] = "moving"
		if _endless() > 0:
			found["the world"] = "%d endless animation(s)" % _endless()
		for key in _screens(g):
			var p: Control = _screens(g)[key].call()
			if "main" in p and p.get("main") == null:
				p.set("main", main)
			main.open_panel(p)
			await frames(3)
			var early := _places([p])
			await tree.create_timer(0.5).timeout
			var moved := _moved(early, _places([p]), p)
			for k in moved:
				found["%s: %s" % [key, k]] = str(moved[k])
			if _endless() > 0:
				found[key] = "%d endless animation(s)" % _endless()
			p.queue_free()
			await frames(2)
		await _done()
		eq(found, {}, "still moving with Reduce motion on, at %s" % setup[0])


## And with it off the same screens do arrive with a movement: the check above can tell the difference.
func test_the_motion_check_sees_motion() -> void:
	var g: Node = await _start(Vector2i(412, 892), true, false)
	var p: Control = _screens(g)["bag"].call()
	main.open_panel(p)
	await frames(2)
	var early := _places([p])
	await tree.create_timer(0.5).timeout
	check(not _moved(early, _places([p]), p).is_empty(), "a sheet slides up when motion is allowed")
	p.queue_free()
	await frames(1)
	await _done()
