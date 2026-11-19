extends RefCounted
## Runs only with --drive=mobile_creation and a disposable --save-root.
## Exercises the shipped Survey and transition code on an Android renderer.

var main: Node
var errors: Array = []

func _check(ok: bool, label: String) -> void:
	print("[mobile] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		errors.append(label)

func _press(root: Node, text: String) -> bool:
	for b in root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and (b.name == text or b.text.begins_with(text)):
			b.pressed.emit()
			return true
	return false

func _shot(label: String) -> void:
	await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := SaveManager.root.path_join(label + ".png")
	main.get_viewport().get_texture().get_image().save_png(path)
	print("[mobile] capture ", path)

func _use_door(g: Node, door: Dictionary) -> bool:
	var target := str(door.get("door_target", ""))
	g.controller.use_object(door)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if GameState.current_room_id == target and not g._transitioning:
			return true
		await main.get_tree().process_frame
	return false

func run(host: Node) -> void:
	main = host
	# Test saves are explicitly selected by the caller; never replace a player's home.
	if not Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--save-root=")):
		push_error("mobile_creation requires an isolated --save-root")
		return
	main._close_all_panels()
	GameState.settings["notifications_asked"] = true
	GameState.settings["reduce_motion"] = false
	main.begin_new_world()
	await main.get_tree().create_timer(0.5).timeout
	for n in main.ui.find_children("*", "Control", true, false):
		var s: Script = n.get_script()
		if s and s.resource_path.get_file() in ["today_card.gd", "recap_card.gd"]:
			n.queue_free()
	var g: Node = main.game
	if OS.has_feature("android"):
		_check(Engine.max_fps == 60, "phone Automatic is capped at 60 fps")
		_check(main.get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "phone Balanced avoids MSAA buffers")
		var graphics := preload("res://scripts/core/graphics.gd")
		var before := [Engine.max_fps, main.get_viewport().msaa_3d, main.get_viewport().anisotropic_filtering_level,
			g.sun.shadow_enabled, g.sun.directional_shadow_mode, g.sun.light_angular_distance,
			g.env.ssao_enabled, g.env.ssil_enabled, g.env.ssr_enabled, g.env.volumetric_fog_enabled, g.env.glow_enabled]
		for choice in ["auto", "high", "ultra", "off"]:
			GameState.settings["pc_detail"] = choice
			main._apply_performance()
			_check(graphics.pc_tier() == 0 and before == [Engine.max_fps, main.get_viewport().msaa_3d, main.get_viewport().anisotropic_filtering_level,
				g.sun.shadow_enabled, g.sun.directional_shadow_mode, g.sun.light_angular_distance,
				g.env.ssao_enabled, g.env.ssil_enabled, g.env.ssr_enabled, g.env.volumetric_fog_enabled, g.env.glow_enabled], "PC detail " + choice + " leaves phone graphics unchanged")
		GameState.settings.erase("pc_detail")
	preload("res://scripts/world/light_home.gd").ensure_entry()
	# Opt-in fixture marker exists only in an explicitly isolated QA save root.
	if FileAccess.file_exists(SaveManager.root.path_join("replay-existing-home.json")):
		await g.dark.go_light()
		_check(GameState.current_room_id.begins_with("lw_floor_"), "copied home loads")
	else:
		var complete := {"value": false}
		var go := func() -> void:
			await g.dark.go_light()
			complete.value = true
		go.call()
		await main.get_tree().process_frame
		var mapper: Node = g.dark.get_node_or_null("HomeMapper")
		_check(mapper != null, "placeholder opens Survey")
		if mapper == null:
			return
		await _shot("survey")
		var screen: Control = mapper.screen
		_check(screen._tune.playing and screen._tune.stream != null and str(screen._tune.stream.get_meta(&"path", "")) == preload("res://scripts/world/music_player.gd").theme_path("survey"), "the Survey plays the Light World creation cue")
		var survey_deadline := Time.get_ticks_msec() + 90000
		while Time.get_ticks_msec() < survey_deadline:
			var step: Dictionary = screen.step()
			if str(step.get("kind", "")) == "consent" and not screen._typing and screen._area.get_child_count() > 0:
				break
			if screen._typing or screen._waiting_tap:
				screen._tap()
			else:
				match str(step.get("kind", "")):
					"text": screen._skip_step()
					"counts": _press(screen, "THAT'S ALL")
					"choice", "picture", "color", "helper":
						var buttons: Array = screen._area.find_children("*", "Button", true, false)
						if not buttons.is_empty(): buttons[0].pressed.emit()
			await main.get_tree().process_frame
		_check(_press(screen, "JustMyAnswers"), "finish Survey with local answers")
		var until := Time.get_ticks_msec() + 60000
		var preview := false
		while not complete.value and Time.get_ticks_msec() < until:
			if is_instance_valid(screen):
				if not preview and screen.find_child("KeepHomePreview", true, false) != null:
					await _shot("preview")
					preview = true
				_press(screen, "KeepHomePreview")
				if screen._typing or screen._waiting_tap: screen._tap()
			await main.get_tree().process_frame
		_check(complete.value, "creation finishes")
		_check(g.dark.last_moment == "first_look", "home reveal played")
	if preload("res://scripts/core/graphics.gd").mobile_safe_renderer():
		_check(not g.sun.shadow_enabled, "phone house disables striped shadow pass")
	await _shot("light")
	await _music_check(g, "light", "the Light World")
	# Walk through each interior doorway with the house fully drawn.
	var door_count := 0
	for edge in g.room.data.get("edge_walls", []):
		if not bool(edge.get("door", false)) or bool(edge.get("outer", false)):
			continue
		var b := Vector2i(int(edge.x), int(edge.z))
		var a := b - (Vector2i(0, 1) if str(edge.dir) == "h" else Vector2i(1, 0))
		_check(g.room.nav.can_step(a, b), "doorway is passable %d" % door_count)
		if g.room.nav.can_step(a, b):
			for step in 16:
				var point := (Vector2(a) + Vector2(0.5, 0.5)).lerp(Vector2(b) + Vector2(0.5, 0.5), float(step) / 15.0)
				g.player.position = Vector3(point.x, g.player.position.y, point.y)
				await main.get_tree().process_frame
			door_count += 1
	_check(door_count > 0, "interior doors rendered and crossed")
	await _shot("doorways")
	# The front door was missing from the original reproduction. Exercise the
	# walking controller across it in both directions, including its arrival callback.
	# A real home can start in an upstairs bedroom; its front door is downstairs.
	var home_entry := str(GameState.current_room_id)
	if home_entry != "lw_floor_0" and SaveManager.room_exists("lw_floor_0"):
		await g.go_to_room("lw_floor_0")
	var front_count := 0
	for edge in g.room.data.get("edge_walls", []):
		if not bool(edge.get("front", false)) or not bool(edge.get("door", false)):
			continue
		var outside := Vector2i(int(edge.x), int(edge.z))
		var inside := outside - (Vector2i(0, 1) if str(edge.dir) == "h" else Vector2i(1, 0))
		g.player.position = g.room.cell_center(inside)
		for destination in [outside, inside]:
			var arrived := {"value": false}
			g.controller.walk_to(destination, func(): arrived.value = true)
			var deadline := Time.get_ticks_msec() + 10000
			while not arrived.value and Time.get_ticks_msec() < deadline:
				await main.get_tree().process_frame
			_check(arrived.value, "front door walking arrival %s" % destination)
		front_count += 1
	_check(front_count > 0, "front door exercised")
	await _shot("front-door")
	# A mapped home also has a door object that loads the neighbourhood. Walking
	# through the wall opening alone does not exercise that scene change.
	var street_checked := false
	for object in g.room.data.get("objects", []).duplicate(true):
		if str(object.get("type", "")) != "door" or not str(object.get("door_target", "")).begins_with("lw_hood_"):
			continue
		street_checked = true
		_check(await _use_door(g, object), "front door loads neighbourhood")
		await _shot("street")
		var back: Dictionary = g.room.door_to("lw_floor_0")
		_check(not back.is_empty(), "street has return door")
		if not back.is_empty():
			_check(await _use_door(g, back), "street door returns to house")
		break
	if preload("res://scripts/world/light_home.gd").street_entry() != "":
		_check(street_checked, "mapped home has usable street exit")
	if g.hud.outside_button.visible:
		await g.go_outside()
		_check(GameState.current_room_id.begins_with("lw_hood_"), "Go outside shortcut opens the saved street")
		await g.go_to_room("lw_floor_0")
	if GameState.current_room_id != home_entry:
		await g.go_to_room(home_entry)
	for i in 6:
		GameState.settings["reduce_motion"] = i % 2 == 1
		if i == 0:
			var gate: Dictionary = {}
			for object in g.room.data.get("objects", []):
				if bool(object.get("gate", false)) and str(object.get("leads", "")) == "dark":
					gate = object
			_check(not gate.is_empty(), "house has Dream World gate")
			g.controller.use_object(gate)
			var gate_deadline := Time.get_ticks_msec() + 30000
			var pressed := false
			while Time.get_ticks_msec() < gate_deadline:
				if not pressed:
					pressed = _press(main.ui, "Enter the Dream World")
				if pressed and GameState.current_room_id == "home" and not g.dark.busy:
					break
				await main.get_tree().process_frame
			_check(pressed, "walk to the Dream Gate and confirm Dream World")
		else:
			await g.dark.go_dark()
		_check(GameState.current_room_id == "home" and not g.dark.busy, "Dream World arrival %d" % i)
		if preload("res://scripts/core/graphics.gd").mobile_safe_renderer():
			_check(g.sun.shadow_enabled == (preload("res://scripts/core/graphics.gd").quality() == "high"), "outside house restores selected shadows")
		if i == 0:
			await _shot("dark")
			await _music_check(g, "dark", "the Dream World")
		await g.dark.go_light()
		_check(GameState.current_room_id.begins_with("lw_floor_") and not g.dark.busy, "Light World arrival %d" % i)
	GameState.settings["reduce_motion"] = false
	await _weather_soak(g)
	await _walking_soak(g)
	g.weather_hold = ""
	g.refresh_weather(true)
	await _furniture_soak(g)
	await _msaa_soak(g)
	_memory_guard_check()
	await _battle_soak(g)
	var spars: Dictionary = await load("res://scripts/core/battle_soak_drive.gd").new().run(main)
	for failure in spars.get("failures", []):
		_check(false, str(failure))
	await _music_page(g)
	await _helper_copy()
	await _engine_loop_check()
	_export_copy_check()
	print("[mobile] DONE failures=", errors.size())
	preload("res://scripts/core/json_util.gd").write_json(SaveManager.root.path_join("mobile_result.json"), {"failures": errors, "platform": OS.get_name(), "renderer": RenderingServer.get_current_rendering_method()})


## Streets and Dream World places rebuild their weather on every load: rebuild it again and again, the
## way the phone now draws it (CPU particles), and keep it falling through the walking soak.
func _weather_soak(g: Node) -> void:
	for i in 9:
		g.weather_hold = ["rain", "leaves", "snow"][i % 3]
		g.refresh_weather(true)
		await main.get_tree().create_timer(0.4).timeout
	var p: Node = g.weather.particles
	var phone := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_check(p != null and (not phone or p is CPUParticles3D), "phone weather runs on the CPU")
	await _shot("weather")


## Every textured Blender piece (1.27.6) drawn at once around you in the house: each loads with its
## texture, the phone draws them for a few seconds, then they go again.
func _furniture_soak(g: Node) -> void:
	var furniture := preload("res://scripts/world/furniture.gd")
	var baked: PackedStringArray = preload("res://scripts/world/licensed_props.gd").BAKED
	var tex_before := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var holder := Node3D.new()
	holder.name = "FurnitureSoak"
	g.add_child(holder)
	var textured := 0
	for i in baked.size():
		var o: Dictionary = furniture.make(baked[i], 0, 0, i % 4, "#6a8fb8" if i % 3 == 0 else "")
		o["id"] = "soak_%d" % i
		var node: Node3D = furniture.build(o)
		node.position = g.player.position + Vector3((i % 6 - 2.5) * 1.3, 0, -1.5 - (i / 6) * 1.3)
		holder.add_child(node)
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			var mi := meshes[0] as MeshInstance3D
			var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
			if mat and mat.albedo_texture:
				textured += 1
	_check(textured == baked.size(), "every Blender piece has its texture (%d/%d)" % [textured, baked.size()])
	g.cam.snap_to_target()
	await main.get_tree().create_timer(3.0).timeout
	await _shot("furniture")
	var tex_mb := (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) - tex_before) / 1048576.0
	print("[mobile] furniture textures added %.1f MB" % tex_mb)
	_check(tex_mb < 48.0, "all furniture textures fit easily on a phone (%.1f MB)" % tex_mb)
	holder.queue_free()
	await main.get_tree().process_frame


func _msaa_soak(g: Node) -> void:
	var viewport := main.get_viewport()
	var aa := viewport.msaa_3d
	var scale := viewport.scaling_3d_scale
	var adjustment: bool = g.env.adjustment_enabled
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.scaling_3d_scale = 0.75
	g.env.adjustment_enabled = true
	print("[mobile] MSAA soak starts (2x + scaling + post effects)")
	await main.get_tree().create_timer(90.0).timeout
	_check(is_instance_valid(g.player), "MSAA/scaling/post-effects soak stays alive")
	viewport.msaa_3d = aa
	viewport.scaling_3d_scale = scale
	g.env.adjustment_enabled = adjustment
	print("[mobile] MSAA soak complete")


## The memory guard on a real Android runtime: the app can read its own memory from /proc, and over its
## thresholds the lighter graphics apply at once. The thresholds are lowered to just under the real reading
## for the check and put back after, as a new session would have them.
func _memory_guard_check() -> void:
	var guard: Node = main.get("memory_guard")
	if guard == null and not OS.has_feature("android"):
		return   # (the guard only runs on Android; a PC run of this drive has nothing to check)
	_check(guard != null, "the memory guard runs on the phone")
	if guard == null:
		return
	var guard_script: Script = load("res://scripts/core/memory_guard.gd")
	var graphics: Script = load("res://scripts/core/graphics.gd")
	var mb: float = guard_script.read_mb()
	print("[mobile] memory guard reads %.0f MB (level %d, pressure %d)" % [mb, guard.level, graphics.pressure])
	_check(mb > 50.0 and mb < 3000.0, "the app reads its own memory (%.0f MB)" % mb)
	_check(guard.level == 0 and graphics.pressure == 0, "a healthy app is left alone")
	var kept := [guard.warn_mb, guard.strain_mb, guard.limit_mb]
	guard.warn_mb = mb * 0.5
	guard.strain_mb = mb * 100.0
	guard.limit_mb = mb * 200.0
	guard.sample()
	_check(guard.level == 1 and graphics.pressure == 1, "over its first threshold the guard lightens the graphics")
	_check(main.get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "no anti-aliasing at pressure 1")
	guard.strain_mb = mb * 0.75
	guard.sample()
	_check(guard.level == 2 and Engine.max_fps == 30, "over its second the frame rate halves (%d fps)" % Engine.max_fps)
	guard.warn_mb = kept[0]
	guard.strain_mb = kept[1]
	guard.limit_mb = kept[2]
	guard.level = 0
	graphics.pressure = 0
	main._apply_performance()
	_check(Engine.max_fps == 60 and graphics.pressure == 0, "and everything is back as chosen (%d fps)" % Engine.max_fps)


func _walking_soak(g: Node) -> void:
	var until := Time.get_ticks_msec() + 130000
	var walks := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12705
	while Time.get_ticks_msec() < until:
		var cell := Vector2i(rng.randi_range(0, g.room.w - 1), rng.randi_range(0, g.room.d - 1))
		if not g.room.nav.walkable(cell):
			await main.get_tree().process_frame
			continue
		g.controller.walk_to(cell)
		await main.get_tree().create_timer(0.8).timeout
		walks += 1
		if walks % 30 == 0: print("[mobile] walking ", walks)
	g.player.stop()
	_check(walks >= 60 and GameState.current_room_id.begins_with("lw_"), "Light World walking soak across cover timer")


func _battle_phase(s: Control, wanted: String) -> bool:
	var until := Time.get_ticks_msec() + 25000
	while is_instance_valid(s) and Time.get_ticks_msec() < until:
		if s.phase == wanted: return true
		if s.phase in ["text", "intro"]: s._tap()
		await main.get_tree().process_frame
	return false


func _battle_soak(g: Node) -> void:
	await g.dark.go_dark()
	if g.actors.is_empty():
		_check(false, "battle fixture has opponent")
		return
	var foe := str(g.actors.keys()[0])
	var data: Dictionary = preload("res://scripts/battle/battle_data.gd").from_template("friendly_spar", GameState.get_character(foe))
	g.battles.start(data, [foe])
	var deadline := Time.get_ticks_msec() + 15000
	while g.battles.screen == null and Time.get_ticks_msec() < deadline:
		await main.get_tree().process_frame
	var s: Control = g.battles.screen
	if s == null:
		_check(false, "battle opens")
		return
	_check(await _battle_phase(s, "menu"), "battle menu ready")
	_check(s.state.party.size() == 1, "battle has one player")
	_check(s.faces.get(0) != null, "enemy uses character sprite")
	await _shot("battle")
	_check(g.music.held(), "the world's song waits during the battle")
	_check(s.music_stream != null and (preload("res://scripts/world/music_player.gd").theme_path("battle") == "" or str(s.music_stream.get_meta(&"path", "")) == preload("res://scripts/world/music_player.gd").theme_path("battle")), "the battle plays the battle cue")
	_check(s.music.playing, "out loud")
	for turn in 3:
		_check(_press(s, "Cmd_act"), "ACT touch target")
		await main.get_tree().process_frame
		_check(_press(s, "Compliment"), "choose ACT")
		await main.get_tree().process_frame
		_check(_press(s, "Begin turn"), "confirm solo turn")
		_check(await _battle_phase(s, "menu"), "battle turn completes %d" % turn)
	_check(_press(s, "Cmd_spare"), "SPARE touch target")
	await main.get_tree().process_frame
	_check(_press(s, "Begin turn"), "confirm spare")
	_check(await _battle_phase(s, "end"), "battle ends peacefully")
	_check(s.state.outcome == "spared", "battle outcome")
	_press(s, "Done")
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	_check(not main.get_viewport().disable_3d, "world rendering restored after battle")
	await _music_check(g, "dark", "after the battle, the Dream World")


## The song a place plays (music_player.gd), out loud once its moment's motif has had the stage.
## The world plays its cue's song (an add-on's, or Polox's own tune: music_player.gd).
func _music_check(g: Node, cue: String, label: String) -> void:
	var file := preload("res://scripts/world/music_player.gd").theme_path(cue)
	var ok := func() -> bool: return g.music.is_playing() and str(g.music.current_track()) == file
	var until := Time.get_ticks_msec() + 12000
	while not ok.call() and Time.get_ticks_msec() < until:
		await main.get_tree().process_frame
	_check(ok.call(), "%s plays %s (%s)" % [label, file, g.music.current_track()])


## Settings > Music on the phone: the page, a song played from it, and no line about a folder the phone
## can't reach (1.27.9).
func _music_page(g: Node) -> void:
	var MusicPlayer := preload("res://scripts/world/music_player.gd")
	_check(MusicPlayer.folders().size() == (2 if OS.has_feature("editor") else 1), "an exported game searches only the save folder for songs")
	var s: Control = preload("res://scripts/ui/settings_screen.gd").new()
	s.main = main
	s.start_on = "Music"
	main.open_panel(s)
	await main.get_tree().create_timer(0.5).timeout
	var tabs: TabContainer = s.find_children("*", "TabContainer", true, false)[0]
	_check(tabs.get_tab_title(tabs.current_tab) == "Music", "Settings opens on Music")
	var page: Node = tabs.get_current_tab_control()
	var folder_line: bool = page.find_children("*", "Label", true, false).any(func(l): return str(l.text).begins_with("Your own songs"))
	_check(folder_line != (OS.has_feature("android") or OS.has_feature("web")), "the own-songs folder line only where you can reach the folder")
	var songs := MusicPlayer.songs()
	var play: Button = page.find_child("Play0", true, false)
	_check(songs.is_empty() or play != null, "a song has a play button (%d songs)" % songs.size())
	if play:
		play.pressed.emit()
		var until := Time.get_ticks_msec() + 8000
		while not g.music.is_playing() and Time.get_ticks_msec() < until:
			await main.get_tree().process_frame
		_check(g.music.previewing() and str(g.music.current_track()) == str(songs[0].path) and g.music.is_playing(), "a song plays from Settings > Music")
		await _shot("music")
	main.go_back()
	await main.get_tree().create_timer(0.5).timeout
	_check(not g.music.previewing(), "closing Settings ends the song")


## The copy/paste AI helper on the phone itself: Copy prompt puts the prompt on the phone's clipboard and
## Paste reply takes what's there (the player couldn't copy the prompt, 1.27.10).
func _helper_copy() -> void:
	var manual: Control = load("res://scripts/home/helper_manual_panel.gd").new()
	main.open_panel(manual)
	manual.setup_manual("words", {"text": "We painted my room blue."})
	await main.get_tree().create_timer(0.3).timeout
	var copy: Button = manual.find_child("CopyPrompt", true, false)
	_check(copy != null and manual.prompt_box.text.length() > 100, "the helper's prompt is there")
	if copy:
		copy.pressed.emit()
		await main.get_tree().process_frame
		_check(DisplayServer.clipboard_get() == manual.prompt_box.text, "Copy prompt puts it on the phone's clipboard")
	DisplayServer.clipboard_set("{\"pasted\": true}")
	await main.get_tree().create_timer(0.3).timeout   # (Android writes the clipboard on its UI thread, a moment later)
	var paste: Button = manual.find_child("PasteReply", true, false)
	if paste:
		paste.pressed.emit()
		await main.get_tree().process_frame
	_check(paste != null and manual.response_box.text == "{\"pasted\": true}", "Paste reply takes what's on the clipboard (got: %s)" % manual.response_box.text.left(40))
	await _shot("helper")
	main._close_all_panels()
	await main.get_tree().process_frame


## Polox's engine (native/godot/patches/0001) keeps a WAV loop inside its data. Godot's own 4.7.2 read one
## frame past a loop that ends on the last frame, which killed the app on Android a few seconds in. These
## loops have no padding (unlike Synth.looping): the 8 s room tone that crashed the phone, and loops ending
## exactly on a page boundary, each played round several times, fast.
## An exported world must reach the phone's Downloads (it used to stay in private storage).
func _export_copy_check() -> void:
	var SlotArchive := preload("res://scripts/core/slot_archive.gd")
	var PhoneExports := preload("res://scripts/phone/phone_exports.gd")
	var dest := SaveManager.global_path("exports").path_join("qa_export_check.polox")
	_check(SlotArchive.export_bundle(SaveManager.slot_id, dest), "the world exports on the phone")
	if OS.has_feature("android"):
		var where := PhoneExports.save_to_downloads(SaveManager.root, dest)
		print("[mobile] export copied to ", where)
		_check(where.begins_with("Download/Polox/") or where.contains("/Download/"), "an export reaches the phone's Downloads (%s)" % where)


func _engine_loop_check() -> void:
	var info := Engine.get_version_info()
	print("[mobile] engine ", info.string)
	if OS.has_feature("android"):
		_check(str(info.build) == "polox", "the app runs Polox's engine (%s)" % info.string)
	var player := AudioStreamPlayer.new()
	player.volume_db = -80.0
	player.pitch_scale = 4.0
	main.add_child(player)
	for frames in [22050 * 8, 2048 * 64, 2048 * 129]:
		var data := PackedByteArray()
		data.resize(frames * 2)
		for i in frames:
			data.encode_s16(i * 2, int(sin(i * 0.05) * 8000.0))
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = 22050
		s.data = data
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = frames
		player.stream = s
		player.play()
		await main.get_tree().create_timer(float(frames) / 22050.0 / 4.0 * 3.2).timeout
		_check(player.playing, "a %d-frame loop ending on its last frame plays round and round" % frames)
	player.queue_free()
