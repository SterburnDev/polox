extends "res://tests/test_case.gd"
## Integration smoke tests: boots the real main scene headless and drives
## the game world (walking, talking, build mode, doors, persistence).

var main: Node


func _boot() -> void:
	fresh_save_root()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)


func _shutdown() -> void:
	main.queue_free()
	await frames(2)


func test_world_boots_with_player_and_mochi() -> void:
	await _boot()
	var g: Node = main.game
	check(g != null, "game world exists")
	eq(GameState.current_room_id, "home")
	check(g.actors.has("mochi"), "Mochi lives at home")
	check(g.room.nav.walkable(g.player.cell()), "player stands on a walkable cell")
	await _shutdown()


func test_build_place_undo_redo_and_autosave() -> void:
	await _boot()
	var g: Node = main.game
	var b: Node = g.build
	b.enter()
	var before: int = g.room.data.tiles.size()
	b.set_piece("cube")
	b.cursor = Vector2i(1, 4)
	b.apply({})
	eq(g.room.data.tiles.size(), before + 1, "placed")
	check(not g.room.nav.walkable(Vector2i(1, 4)), "nav updated after placing")
	b.undo()
	eq(g.room.data.tiles.size(), before, "undo removes it")
	check(g.room.nav.walkable(Vector2i(1, 4)), "nav updated after undo")
	b.redo()
	eq(g.room.data.tiles.size(), before + 1, "redo puts it back")
	b.cursor = g.player.cell()
	b.apply({})
	eq(g.room.data.tiles.size(), before + 1, "can't build on top of the player")
	b.set_tool("erase")
	b.cursor = Vector2i(1, 4)
	b.apply({})
	eq(g.room.data.tiles.size(), before, "erased")
	b.set_tool("paint")
	b.set_paint("#123456", "")
	b.paint_surface("sky")
	b.exit()  # flushes the autosave
	var saved := SaveManager.load_room("home")
	eq(saved.tiles.size(), before, "saved to disk on exit")
	eq(saved.sky.color, "#123456", "sky paint saved")
	await _shutdown()


func test_sign_text_and_door_to_new_room() -> void:
	await _boot()
	var g: Node = main.game
	var b: Node = g.build
	b.enter()
	b.set_piece("sign")
	b.cursor = Vector2i(4, 7)
	b.apply({})
	await frames(1)
	var ed: Control = main.panels.back()
	ed._text.text = "Proud of finishing my first painting!"
	ed._done()
	await frames(1)
	b.set_piece("door")
	b.cursor = Vector2i(0, 3)
	b.apply({})
	await frames(1)
	ed = main.panels.back()
	ed._target.select(ed._target_ids.find("__new__"))
	ed._new_name.text = "Studio"
	ed._done()
	await frames(1)
	b.exit()
	check("studio" in SaveManager.list_rooms(), "new room created")
	var home := SaveManager.load_room("home")
	var sign_text := ""
	var door_target := ""
	for o in home.objects:
		if o.type == "sign" and str(o.interaction_text).begins_with("Proud"):
			sign_text = o.interaction_text
		if o.type == "door" and o.door_target == "studio":
			door_target = o.door_target
	eq(sign_text, "Proud of finishing my first painting!", "sign text saved")
	eq(door_target, "studio", "door linked")
	g.load_room("studio", "home")
	eq(GameState.current_room_id, "studio")
	check(not g.room.door_to("home").is_empty(), "studio has a door back home")
	check(g.room.nav.walkable(g.player.cell()), "arrived on a walkable cell")
	await _shutdown()


func test_talk_flow_logs_through_dialogue_box() -> void:
	await _boot()
	var g: Node = main.game
	g.talk.talk_to("mochi")
	check(g.dialogue.visible, "dialogue opened")
	g.dialogue.advance()
	g.dialogue.advance()
	eq(g.dialogue.state, "input", "chat row ready")
	g.dialogue.input.text = "hello Mochi"
	g.dialogue._send()
	var t0 := Time.get_ticks_msec()   # (the reply takes a few frames; more on a busy test machine)
	while ChatLog.read_all("mochi").size() < 3 and Time.get_ticks_msec() - t0 < 3000:
		await frames(1)
	var log := ChatLog.read_all("mochi")
	eq(log.size(), 3, "greeting + user + reply logged")
	eq(log[1].text, "hello Mochi")
	main.go_back()
	check(not g.dialogue.visible, "back closes the dialogue")
	await _shutdown()


func test_panels_auto_focus_for_gamepad() -> void:
	await _boot()
	main.open_panel(preload("res://scripts/ui/settings_screen.gd").new())
	await frames(3)
	var f: Control = main.get_viewport().gui_get_focus_owner()
	check(f != null and main.panels.back().is_ancestor_of(f), "a control inside the panel has focus")
	check(InputMap.has_action("cam_left") and InputMap.has_action("zoom_in"), "gamepad camera actions exist")
	await _shutdown()
