extends RefCounted
## Longer scripted scenarios for automated checks (see debug_drives.gd):
## the Phase 4 build acceptance, a performance run and a real-AI chat.

var drives: RefCounted   # debug_drives.gd (gives main + _wait)


## Phase 4 acceptance: build, sign, door to a brand-new room, walk through.
func build_two_rooms() -> void:
	drives.main.begin_new_world()
	await drives._wait(0.6)
	var g: Node = drives.main.game
	var b: Node = g.build
	b.enter()
	await drives._wait(0.3)
	b.set_piece("cube")
	b.set_paint("#e86a8a", "")
	for c in [Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7)]:
		b.cursor = c
		b.apply({})
	b.set_piece("slab")
	b.cursor = Vector2i(2, 6)
	b.apply({})
	b.set_piece("sign")
	b.cursor = Vector2i(4, 7)
	b.apply({})
	await drives._wait(0.3)
	var ed: Control = drives.main.panels.back()
	ed._text.text = "I'm teaching myself guitar. One song a week, even after night shifts."
	ed._done()
	await drives._wait(0.2)
	b.set_piece("door")
	b.cursor = Vector2i(0, 3)
	b.rot = 1
	b.apply({})
	await drives._wait(0.3)
	ed = drives.main.panels.back()
	ed._target.select(ed._target_ids.find("__new__"))
	ed._new_name.text = "Moon Cafe"
	ed._done()
	await drives._wait(0.2)
	b.set_tool("paint")
	b.set_paint("#3a5f8f", "")
	b.paint_surface("floor")
	await drives._wait(1.6)  # let autosave fire
	print("[drive] home tiles=%d objects=%d" % [g.room.data.tiles.size(), g.room.data.objects.size()])
	b.exit()
	await drives._wait(0.3)
	g.use_object(g.room.find_object("door_1"))
	await drives._wait(4.5)
	print("[drive] now in: ", GameState.current_room_id)


## Performance: a 20x20 room with ~120 blocks and 10 wandering residents.
func perf() -> void:
	drives.main.begin_new_world()
	await drives._wait(0.3)
	var RoomEditor := preload("res://scripts/world/room_editor.gd")
	var Starter := preload("res://scripts/core/starter_content.gd")
	var big := preload("res://scripts/core/defaults.gd").room("big", "Big Room")
	RoomEditor.resize(big, 20, 20)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 120:
		RoomEditor.add_tile(big, rng.randi_range(0, 19), rng.randi_range(0, 19), ["cube", "slab", "pillar", "ramp"][i % 4], "#8a7bc8")
	for i in 8:
		RoomEditor.add_object(big, rng.randi_range(0, 19), rng.randi_range(0, 19), "prop")
	big["spawn"] = [10, 10]
	SaveManager.save_room(big)
	var colors := ["#c9b6ff", "#ffb3c7", "#7ad6b0", "#8fd3ff", "#ffd166", "#ff9f43", "#e86a8a", "#9a94b0", "#d8a7ff"]
	for i in 9:
		Starter.create_mochi("Friend %d" % (i + 1), Color(colors[i]))
	for id in SaveManager.list_characters():
		var c := SaveManager.load_character(id)
		c["home_room"] = "big"
		c["pos"] = []
		SaveManager.save_character(c)
	GameState.load_world()
	drives.main.start_game()
	await drives._wait(0.5)
	drives.main.game.load_room("big")
	await drives._wait(1.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await drives._wait(1.0)
	var frames := [0]
	var count := func(): frames[0] += 1
	drives.main.get_tree().process_frame.connect(count)
	var t0 := Time.get_ticks_msec()
	await drives._wait(5.0)
	drives.main.get_tree().process_frame.disconnect(count)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("[drive] perf: %d actors, %d tiles, %.0f fps uncapped (%d frames / %.1fs), renderer=%s" % [drives.main.game.actors.size(), drives.main.game.room.data.tiles.size(), frames[0] / secs, frames[0], secs, RenderingServer.get_current_rendering_method()])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


## Headless smoke run (check.bat): a whole session in Mock mode, no
## rendering needed. Prints "[smoke] ok" only if every step worked.
func smoke() -> void:
	var main: Node = drives.main
	var notes: Dictionary = GameState.settings.get("notifications", {})
	var expect_notes_question: bool = load("res://scripts/variety/miss_you.gd").supported() and not bool(notes.get("asked", false))
	main.begin_new_world()
	await drives._wait(0.5)
	var g: Node = main.game
	var problems := PackedStringArray()
	if g == null or not g.actors.has("mochi"):
		problems.append("world did not start with Mochi")
	# Walk, then talk.
	g.approach_character("mochi")
	await drives._wait(2.5)
	for line in ["hi!", "I had a long day"]:
		# Click through however many segments the reply has (Mock sometimes adds one).
		for i in 8:
			if g.dialogue.state == "input":
				break
			g.dialogue.advance()
		g.dialogue.input.text = line
		g.dialogue._send()
		await drives._wait(1.2)
	if ChatLog.read_all("mochi").size() < 5:
		problems.append("chat was not logged")
	# Phase 10: gift a snack from the bag, switch form, equip something.
	await g.talk.give_gift("fresh_cookies")
	if not ChatLog.read_all("mochi").any(func(e): return e.get("kind") == "gift"):
		problems.append("gift was not logged")
	g.dialogue.close_box()
	# After the first chat a friend asks, once, about missing-you notes: answered as a player would
	# (Back = Not now), so the world is free again for the door below.
	await drives._wait(0.3)
	var ask: Node = main.panels.back() if not main.panels.is_empty() else null
	var asked := ask != null and str(ask.name) == "MissYouAsk"
	if expect_notes_question and not asked:
		problems.append("the missing-you question did not come after the first chat")
	if asked:
		main.go_back()
		await drives._wait(0.2)
		if not main.panels.is_empty():
			problems.append("the missing-you question did not close with Back")
	g.switch_form()
	preload("res://scripts/items/item_effects.gd").equip(g, preload("res://scripts/items/items.gd").load_item("tea_cozy_helmet"))
	if not preload("res://scripts/items/inventory.gd").is_equipped("tea_cozy_helmet"):
		problems.append("equip failed")
	# Phase 11: Phone Link switches on, makes a code, refuses a stranger, switches off.
	# (Home Wi-Fi mode on 127.0.0.1: the smoke run never touches Tailscale or the network.)
	main.configure_phone_link()
	main.phone_link.mode = "lan"
	var link_err: String = main.phone_link.start_on_safe_port(main.phone_link.port, "127.0.0.1")
	if link_err != "":
		link_err = main.phone_link.start(0, "127.0.0.1")
	if link_err != "":
		problems.append("Phone Link didn't start (%s)" % link_err)
	else:
		main.phone_link.pairing.new_code()
		var r: Array = await _http_status("http://127.0.0.1:%d/api/status" % main.phone_link.port)
		if int(r[1]) != 401:
			problems.append("Phone Link answered a stranger (%d)" % int(r[1]))
		main.phone_link.stop()
	# Build a block, undo it, paint the sky, autosave.
	g.build.enter()
	g.build.set_piece("cube")
	g.build.cursor = Vector2i(1, 4)
	g.build.apply({})
	g.build.undo()
	g.build.set_tool("paint")
	g.build.set_paint("#334455", "")
	g.build.paint_surface("sky")
	g.build.exit()
	if SaveManager.load_room("home").sky.color != "#334455":
		problems.append("build edit not saved")
	# Through the door and back.
	g.use_object(g.room.find_object("door_garden"))
	await drives._wait(3.5)
	if GameState.current_room_id != "garden":
		problems.append("door did not lead to the garden")
	# Every menu screen opens and closes.
	var WorldMenu := preload("res://scripts/world/world_menu.gd")
	var screens: Array = [
		preload("res://scripts/ui/settings_screen.gd").new(), preload("res://scripts/ui/log_viewer.gd").new(),
		preload("res://scripts/ui/world_bible_editor.gd").new(), WorldMenu.friends(g),
		preload("res://scripts/ui/dreams_board.gd").new(), preload("res://scripts/ui/memory_book.gd").new(),
		preload("res://scripts/ui/help_panel.gd").new(), WorldMenu.room_list(g), WorldMenu.creator(""),
		preload("res://scripts/ui/friendship_web.gd").new(), WorldMenu.make(g),
		WorldMenu.sheet(g, 0), WorldMenu.sheet(g, 1), WorldMenu.sheet(g, 2), WorldMenu.bag(g), WorldMenu.workshop(g),
	]
	for s in screens:
		main.open_panel(s)
		await drives._wait(0.15)
		main.go_back()
		await drives._wait(0.1)
	if not main.panels.is_empty():
		problems.append("a panel refused to close: " + str(main.panels.back()))
	main.flush_all()
	if problems.is_empty():
		print("[smoke] ok")
	else:
		print("[smoke] FAILED: " + "; ".join(problems))


func _http_status(url: String) -> Array:
	if not is_instance_valid(drives) or not is_instance_valid(drives.main) or not drives.main.is_inside_tree():
		return [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]
	var http := HTTPRequest.new()
	http.timeout = 10.0
	drives.main.add_child(http)
	var box := {"done": false, "res": [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]}
	http.request_completed.connect(func(a, b, c, d):
		box.res = [a, b, c, d]
		box.done = true, CONNECT_ONE_SHOT)
	if http.request(url) != OK:
		http.queue_free()
		return box.res
	var deadline := Time.get_ticks_msec() + 12000
	while not bool(box.done) and is_instance_valid(http) and drives.main.is_inside_tree() and Time.get_ticks_msec() < deadline:
		await drives.main.get_tree().process_frame
	if is_instance_valid(http):
		if not bool(box.done):
			http.cancel_request()
		http.queue_free()
	return box.res


## Real-provider check: a World Bible + dream, three turns, replies printed.
func real_ai_chat(ai: Dictionary) -> void:
	drives.main.begin_new_world()
	await drives._wait(0.5)
	GameState.world["world_bible"] = {
		"setting": "Lumen Hollow, a moonlit valley of tiny lantern-lit houses beside a slow river.",
		"lore": "Lanterns glow brighter whenever someone in the valley feels proud of themselves.",
		"themes": "cozy, gentle humor, small brave steps",
		"life_context": "Sam works night shifts as a nurse and is teaching themself guitar.",
	}
	GameState.world["player"]["name"] = "Sam"
	GameState.save_world()
	GameState.add_dream("play guitar at an open mic night")
	var merged: Dictionary = GameState.settings.get("ai", {}).duplicate()
	for k in ai:
		merged[k] = ai[k]
	GameState.settings["ai"] = merged
	GameState.save_settings()
	var g: Node = drives.main.game
	var id: String = g.actors.keys()[0]
	g.approach_character(id)
	await drives._wait(3.0)
	for line in ["Hey Mochi! What do you love most about living here?", "I'm so tired after my night shift...", "Any tips for being less nervous on stage?"]:
		g.dialogue.advance()
		g.dialogue.advance()
		g.dialogue.input.text = line
		g.dialogue._send()
		var waited := 0.0
		while g.dialogue.state != "input" and waited < 150.0:
			await drives._wait(0.5)
			waited += 0.5
			g.dialogue.advance()
		var last: Dictionary = ChatLog.recent(id, 1)[0]
		print("[drive] YOU: %s
[drive] MOCHI (%s%s): %s" % [line, last.get("emotion"), " FAILED" if last.get("failed", false) else "", last.get("text")])
	print("[drive] memory_notes=", GameState.get_character(id).get("memory_notes"))
