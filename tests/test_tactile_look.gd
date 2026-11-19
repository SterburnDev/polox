extends "res://tests/test_case.gd"
## [GLASS_UI] The Frutiger Aero / skeuomorphic / iOS 7 / Liquid Glass pass and the rendering fixes under it:
## glass that keeps its colours when pressed, Liquid Glass reading the right part of the screen, the paper
## journal's tabs, the stereo, the wall light switch, the Dream Gate's touch ripple, the builder's grounded
## preview, Settings' switches, the title's logo and its reflection, and the sun's shadow fade.
## Tags: [GLASS_UI] [BUILDER] [GRAPHICS]

const GlassBox := preload("res://scripts/ui/glass_box.gd")
const LiquidGlass := preload("res://scripts/ui/liquid_glass.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Synth := preload("res://scripts/core/synth.gd")
const Furniture := preload("res://scripts/world/furniture.gd")

var main: Node


func _boot() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)


func _done() -> void:
	main.queue_free()
	await frames(2)


func test_a_pressed_key_keeps_its_colour_and_goes_down() -> void:
	var k: StyleBox = ThemeBuilder.key(ThemeBuilder.YELLOW, ThemeBuilder.CREAM)
	var down: StyleBox = ThemeBuilder.key(ThemeBuilder.YELLOW, ThemeBuilder.CREAM, ThemeBuilder.RADIUS_M, 10, 1.0, Color(0, 0, 0, 0), 1, 0.2, ThemeBuilder.KEY_DEPTH, true)
	check(k is GlassBox and down is GlassBox, "keys are glass")
	check(Color(down.base, 1.0).is_equal_approx(Color(k.base, 1.0)), "pressed, it keeps its colour (Resource.duplicate() had lost it: pressed keys came out dark)")
	check(down.pressed and not k.pressed, "and sits down")
	check(down.get_content_margin(SIDE_TOP) > k.get_content_margin(SIDE_TOP), "so its label goes down with it")
	eq(down.get_content_margin(SIDE_TOP) + down.get_content_margin(SIDE_BOTTOM), k.get_content_margin(SIDE_TOP) + k.get_content_margin(SIDE_BOTTOM), "the same height either way")
	# The gloss is one smooth gradient: colours between its stops are blended, not banded.
	var mid: Color = GlassBox._colour_at([[0.0, Color(1, 1, 1, 0.4)], [0.5, Color(1, 1, 1, 0.0)]], 0.25)
	check(absf(mid.a - 0.2) < 0.001, "the gloss fades smoothly (%.3f halfway)" % mid.a)


func test_liquid_glass_reads_the_screen_under_it() -> void:
	await _boot()
	var g: PanelContainer = LiquidGlass.new()
	var host := Control.new()
	host.position = Vector2(300, 200)
	main.ui.add_child(host)
	host.add_child(g)
	g.add_child(preload("res://scripts/ui/ui_kit.gd").button("Hi"))
	await frames(3)
	if LiquidGlass.available():
		check(g.is_live(), "glass over the world")
		var copy: BackBufferCopy = null
		for c in g.get_children(true):
			if c is BackBufferCopy:
				copy = c
		check(copy != null and copy.copy_mode == BackBufferCopy.COPY_MODE_RECT, "a screen copy just before it")
		var on_screen: Rect2 = g.get_viewport().get_final_transform() * (g.get_global_transform_with_canvas() * Rect2(Vector2(-24, -24), g.size + Vector2(48, 48)))
		check(copy.rect.is_equal_approx(on_screen), "copying where it really is on screen (Godot 4.7.2 copies BackBufferCopy.rect as screen pixels)")
	ThemeBuilder.solid = true
	g.refresh()
	check(not g.is_live() and g.get_theme_stylebox("panel") is StyleBoxFlat, "Reduce transparency: solid, no screen reading")
	ThemeBuilder.solid = false
	g.refresh()
	host.queue_free()
	await _done()


func test_the_journal_is_a_notebook_with_tabs() -> void:
	await _boot()
	var j: Control = load("res://scripts/home/journal_panel.gd").new()
	main.open_panel(j)
	await frames(3)
	check(j.find_child("Paper", true, false) != null, "a paper page")
	eq(j.showing, "write", "it opens on Write")
	Synth.history.clear()
	(j.find_child("Tab_pages", true, false) as Button).pressed.emit()
	await frames(1)
	eq(j.showing, "pages", "the Pages tab turns the page")
	check(Synth.history.has("page"), "with a page-turn sound")
	j.show_tab("write")
	j.text_box.text = "A quiet morning."
	(j.find_child("KeepEntry", true, false) as Button).pressed.emit()
	await frames(1)
	eq(j.showing, "pages", "keeping a line shows it on Pages")
	main.go_back()
	await _done()


func test_the_music_page_has_a_stereo_and_keeps_its_secret() -> void:
	await _boot()
	var s: Control = load("res://scripts/ui/settings_screen.gd").new()
	s.main = main
	s.start_on = "Music"
	main.open_panel(s)
	await frames(3)
	var page: ScrollContainer = s.find_child("Music", true, false)
	var stereo: Control = page.find_child("Stereo", true, false)
	if page._songs.is_empty():
		check(stereo == null, "no songs: no stereo")
	else:
		check(stereo != null, "a stereo at the top")
		(stereo.find_child("StereoPlay", true, false) as Button).pressed.emit()
		await frames(1)
		check(page.playing() >= 0 and stereo.playing, "its play key plays")
		check(str((stereo.find_child("NowPlaying", true, false) as Label).text).contains(page.song_title(page.playing())), "and the display shows the song")
		(stereo.find_child("StereoPlay", true, false) as Button).pressed.emit()
		await frames(1)
		eq(page.playing(), -1, "and stops")
	check(page.find_child("Yams", true, false) != null and not page.secret_shown(), "the secret is still there, hidden")
	main.go_back()
	await _done()


func test_settings_toggles_are_switches() -> void:
	await _boot()
	var s: Control = load("res://scripts/ui/settings_screen.gd").new()
	s.main = main
	s.start_on = "Gameplay"
	main.open_panel(s)
	await frames(3)
	var cb: CheckBox = null
	for c in s.find_children("*", "CheckBox", true, false):
		if (c as CheckBox).is_visible_in_tree():
			cb = c
			break
	check(cb != null, "a toggle in Settings")
	if cb:
		eq(cb.get_theme_icon("checked").get_size(), Vector2(60, 32), "drawn as a switch (iOS 7's layer for dense screens)")
		Synth.history.clear()
		cb.button_pressed = not cb.button_pressed
		check(Synth.history.has("switch_on") or Synth.history.has("switch_off"), "and it clicks as it flips")
	main.go_back()
	await _done()


func test_a_light_switch_turns_the_lamps_off_and_on() -> void:
	await _boot()
	main.begin_new_world()
	await frames(3)
	var g: Node = main.game
	GameState.settings["reduce_motion"] = true
	preload("res://scripts/world/light_home.gd").ensure_entry()
	preload("res://scripts/world/light_home.gd").defer_survey()
	await g.dark.go_light()
	await frames(3)
	var sw: Dictionary = {}
	for o in g.room.data.get("objects", []):
		if str(o.get("model", "")) == "light_switch":
			sw = o
	check(not sw.is_empty(), "your room has a light switch")
	var lamps: Array = g.get_tree().get_nodes_in_group("polox_lamp").filter(func(l): return l is OmniLight3D and l.name == "Glow")
	check(not lamps.is_empty(), "and lamps")
	Synth.history.clear()
	g.light_life.use(sw)
	check(not bool(sw.get("on", true)), "flicked off")
	check(lamps.all(func(l): return not l.visible), "the lamps go out")
	check(Synth.history.has("light_switch"), "with a clack")
	g.light_life.use(sw)
	check(lamps.all(func(l): return l.visible), "and come back on")
	GameState.settings["reduce_motion"] = false
	await _done()


func test_the_dream_gate_ripples_when_touched() -> void:
	var gate: Node3D = load("res://scripts/world/fountain_node.gd").make({"type": "dark_fountain", "id": "g1", "state": "open"})
	tree.root.add_child(gate)
	await frames(1)
	check(gate.find_child("TileApron", true, false) != null, "it stands on glazed tiles")
	var rim: MeshInstance3D = gate.find_child("Rim", true, false)
	check((rim.material_override as StandardMaterial3D).roughness < 0.3, "its rim is glazed (glossy)")
	gate.poke_if("g1")
	await frames(3)
	var age: float = (gate.pool.material_override as ShaderMaterial).get_shader_parameter("poke_age")
	check(age > 0.0 and age < 1.0, "a ring runs out across the liquid (%.2f s)" % age)
	gate.queue_free()


func test_the_build_preview_is_grounded_and_framed() -> void:
	var ghost: Node3D = load("res://scripts/builder/build_ghost.gd").new()
	tree.root.add_child(ghost)
	await frames(1)
	check(ghost.find_child("GhostShadow", true, false) != null, "a soft shadow under the piece")
	var foot: MeshInstance3D = ghost.find_child("Footprint", true, false)
	check(foot != null and (foot.material_override as StandardMaterial3D).no_depth_test, "a footprint frame, drawn over everything")
	var m: ArrayMesh = load("res://scripts/builder/build_ghost.gd").frame_mesh(Vector2.ZERO, Vector2(2, 3), 0.07, Color.YELLOW, true)
	check(m.get_surface_count() == 1 and m.surface_get_array_len(0) > 0, "the selection frame is a real band, with corner marks")
	ghost.queue_free()


func test_the_title_logo_is_smooth_and_its_reflection_true_to_size() -> void:
	await _boot()
	var logo: TextureRect = main.screen.find_child("PoloxLogo", true, false)
	eq(logo.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "the logo is drawn smooth, from mipmaps")
	var clip: Control = main.screen.find_child("LogoReflection", true, false)
	check(clip.clip_contents, "the reflection is a window onto it")
	var copy: TextureRect = clip.get_child(0)
	eq(copy.size, logo.custom_minimum_size, "on a copy at the logo's own size (not squeezed)")
	check(main.screen.find_child("AeroScene", true, false) != null, "over the Aero hills and lake")
	await _done()


func test_shadows_fade_out_instead_of_ending_in_a_line() -> void:
	var sun := DirectionalLight3D.new()
	preload("res://scripts/core/graphics.gd").apply_to_world(sun, GameState.settings)
	eq(sun.directional_shadow_fade_start, preload("res://scripts/core/graphics.gd").SHADOW_FADE_START, "the far half of the shadows fades")
	sun.free()
