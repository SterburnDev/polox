extends "res://tests/test_case.gd"
## Phase 7 audit: things that could lose data, crash, soft-lock or break
## one-handed control, each pinned down by a test.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const RoomView := preload("res://scripts/world/room_view.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")

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


# --- Saves -------------------------------------------------------------------------

func test_write_keeps_a_bak_and_recovers_a_broken_file() -> void:
	var root := fresh_save_root()
	var p := root.path_join("thing.json")
	JsonUtil.write_json(p, {"v": 1})
	JsonUtil.write_json(p, {"v": 2})
	check(FileAccess.file_exists(p + ".bak"), "previous version kept as .bak")
	eq(JsonUtil.read_json(p + ".bak", {}).get("v"), 1, ".bak holds the older version")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{\"v\": 2, \"oops")  # crash / disk full / bad hand edit
	f.close()
	JsonUtil.recoveries.clear()
	eq(JsonUtil.read_json(p, {}).get("v"), 1, "broken file falls back to the .bak")
	check(FileAccess.file_exists(p + ".broken"), "the broken file is kept for inspection")
	eq(JsonUtil.read_json(p, {}).get("v"), 1, "and the rescued version is back in place")
	check(JsonUtil.recoveries.size() == 1, "recovery reported once")
	JsonUtil.recoveries.clear()


func test_finished_tmp_write_is_picked_up() -> void:
	var root := fresh_save_root()
	var p := root.path_join("world.json")
	JsonUtil.write_json(p, {"v": 1})
	# Simulate a crash between "old -> .bak" and ".tmp -> file": only .tmp and .bak exist.
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	f.store_string(JSON.stringify({"v": 3}))
	f.close()
	DirAccess.rename_absolute(p, p + ".bak")
	eq(JsonUtil.read_json(p, {}).get("v"), 3, "the newest finished write wins")
	JsonUtil.recoveries.clear()


func test_room_with_junk_entries_loads() -> void:
	fresh_save_root()
	var r := Defaults.room("junk", "Junk")
	r["tiles"] = [{"x": 1, "y": 0, "z": 1, "type": "cube", "color": "#fff"}, "not a tile", {"x": "a", "z": 2}, {"x": 99, "y": 0, "z": 99, "type": "cube"}]
	r["objects"] = [{"id": "s", "type": "sign", "pos": [2, 0]}, {"id": "ok", "type": "sign", "pos": [3, 0, 3]}, 42]
	r["spawn"] = "nope"
	SaveManager.save_room(r)
	var loaded := SaveManager.load_room("junk")
	eq(loaded.tiles.size(), 1, "malformed tiles dropped")
	eq(loaded.objects.size(), 1, "malformed objects dropped")
	check(loaded.spawn is Array and loaded.spawn.size() == 2, "spawn repaired")
	var view := RoomView.new()
	tree.root.add_child(view)
	view.build(loaded)
	check(not view.nav.walkable(Vector2i(1, 1)), "the good tile still blocks")
	view.queue_free()


func test_big_pictures_are_shrunk_and_junk_refused() -> void:
	var root := fresh_save_root()
	var big := Image.create(4096, 1024, false, Image.FORMAT_RGB8)
	big.fill(Color.RED)
	var src := root.path_join("huge.png")
	big.save_png(src)
	var rel := SaveManager.import_texture(src)
	check(rel.begins_with("textures/") and rel.ends_with(".png"), "imported as png")
	var img := Image.load_from_file(SaveManager.abs_path(rel))
	eq(img.get_width(), 2048, "shrunk to the limit")
	eq(img.get_height(), 512, "aspect kept")
	var junk := root.path_join("junk.png")
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("definitely not a picture")
	f.close()
	eq(SaveManager.import_texture(junk), "", "junk refused")
	check(SaveManager.load_texture("missing/nothing.png") == null, "missing file gives null, not a crash")


# --- Logs -----------------------------------------------------------------------------

func test_recent_reads_only_the_tail_of_a_big_log() -> void:
	fresh_save_root()
	for i in 3000:
		ChatLog.append("bo", "home", "user" if i % 2 == 0 else "ai", "message number %d with some padding text to make lines longer" % i)
	ChatLog.append("bo", "home", "ai", "chatter", "", {"kind": "npc_chat", "with": "x"})
	var t0 := Time.get_ticks_usec()
	var r := ChatLog.recent("bo", 12)
	var took := (Time.get_ticks_usec() - t0) / 1000.0
	eq(r.size(), 12)
	eq(r.back().text, "message number 2999 with some padding text to make lines longer", "newest conversation line last (chatter skipped)")
	eq(r[0].text, "message number 2988 with some padding text to make lines longer")
	check(took < 50.0, "tail read is fast (%.1f ms)" % took)
	eq(ChatLog.recent("bo", 5000).size(), 3000, "asking for more than exists returns everything")


func test_log_viewer_pages() -> void:
	await _boot()
	for i in 450:
		ChatLog.append("mochi", "home", "user", "line %d" % i)
	var lv: Control = preload("res://scripts/ui/log_viewer.gd").new()
	main.open_panel(lv)
	await frames(2)
	check(lv._entries.size() >= 450, "all entries counted")
	check(lv._count.text.find("page 1 of") != -1, "page indicator: " + lv._count.text)
	check(lv._list.text.find("line 449") != -1, "newest page first")
	check(lv._newer_btn.disabled and not lv._older_btn.disabled, "only Older is available on the newest page")
	lv._show_page(1)
	check(lv._list.text.find("line 449") == -1 and lv._list.text.find("line 249") != -1, "older page shows older lines")
	await _shutdown()


# --- Input ---------------------------------------------------------------------------

func _key(code: Key, unicode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.unicode = unicode
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(1)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await frames(1)


func test_typing_in_chat_never_triggers_hotkeys() -> void:
	await _boot()
	var g: Node = main.game
	g.talk.talk_to("mochi")
	g.dialogue.advance()
	g.dialogue.advance()
	eq(g.dialogue.state, "input")
	g.dialogue.input.grab_focus()
	await frames(1)
	var cell: Vector2i = g.player.cell()
	await _key(KEY_E, 101)
	await _key(KEY_Q, 113)
	await _key(KEY_W, 119)
	await _key(KEY_C, 99)
	eq(g.dialogue.input.text, "eqwc", "letters went into the text field")
	check(g.dialogue.visible, "Q did not close the chat")
	eq(g.talk.talking_to, "mochi", "still talking")
	check(main.panels.is_empty(), "C did not open the menu")
	eq(g.player.cell(), cell, "W did not move the player")
	await _shutdown()


func test_typing_in_build_panel_never_builds() -> void:
	await _boot()
	var g: Node = main.game
	g.build.enter()
	await frames(1)
	var before: int = g.room.data.tiles.size()
	g.build.set_mode("room")
	g.build.shell.room_tab._w.get_line_edit().grab_focus()
	await frames(1)
	await _key(KEY_E, 101)
	await _key(KEY_R, 114)
	eq(g.room.data.tiles.size(), before, "E did not place a block while typing a size")
	eq(g.build.rot, 0, "R did not rotate while typing")
	g.build.exit()
	await _shutdown()


# --- World -------------------------------------------------------------------------------

func test_arriving_through_a_walled_in_door_never_strands_the_player() -> void:
	await _boot()
	var g: Node = main.game
	var garden := SaveManager.load_room("garden")
	var door: Dictionary = {}
	for o in garden.objects:
		if o.type == "door":
			door = o
	var dc := Vector2i(int(door.pos[0]), int(door.pos[2]))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx != 0 or dz != 0:
				RoomEditor.add_tile(garden, dc.x + dx, dc.y + dz, "cube", "#fff")
	SaveManager.save_room(garden)
	g.load_room("garden", "home")
	check(g.room.nav.walkable(g.player.cell()), "player landed on a walkable cell: %s" % g.player.cell())
	check(g.player.cell().x >= 0 and g.player.cell().y >= 0, "inside the room")
	await _shutdown()


func test_room_change_does_not_leak_nodes() -> void:
	await _boot()
	var g: Node = main.game
	g.load_room("garden", "home")
	g.load_room("home", "garden")
	await frames(3)
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in 6:
		g.load_room("garden", "home")
		g.load_room("home", "garden")
	await frames(3)
	var nodes_after := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	check(nodes_after <= nodes_before + 4, "node count stable across room changes (%d -> %d)" % [nodes_before, nodes_after])
	eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), 0, "no orphan nodes")
	await _shutdown()


func test_big_room_builds_fast_with_few_nodes() -> void:
	fresh_save_root()
	var r := Defaults.room("big", "Big")
	RoomEditor.resize(r, 40, 40)
	for x in 40:
		for z in 40:
			if (x + z) % 2 == 0:
				RoomEditor.add_tile(r, x, z, ["cube", "slab", "pillar", "ramp"][(x * 7 + z) % 4], ["#111", "#222", "#333"][x % 3])
	eq(r.tiles.size(), 800)
	var view := RoomView.new()
	tree.root.add_child(view)
	var t0 := Time.get_ticks_usec()
	view.build(r)
	var took := (Time.get_ticks_usec() - t0) / 1000.0
	var count := view._content.get_child_count()
	check(count < 60, "tiles are batched (%d top-level nodes for 800 tiles)" % count)
	check(took < 800.0, "800 tiles build in %.0f ms" % took)
	check(not view.nav.walkable(Vector2i(0, 0)) and view.nav.walkable(Vector2i(1, 0)), "walkability intact")
	view.queue_free()
	await frames(1)


func test_quit_flushes_room_and_positions() -> void:
	await _boot()
	var g: Node = main.game
	g.build.enter()
	g.build.set_piece("cube")
	g.build.cursor = Vector2i(2, 2)
	g.build.apply({})   # autosave is pending (1 s), not written yet
	g.actors["mochi"].position = g.room.cell_center(Vector2i(9, 8))
	main.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var saved := SaveManager.load_room("home")
	check(saved.tiles.any(func(t): return int(t.x) == 2 and int(t.z) == 2), "pending build edit written on close")
	var pos: Array = SaveManager.load_character("mochi").pos
	check(pos.size() == 2 and int(pos[0]) == 9 and int(pos[1]) == 8, "positions written on close: %s" % str(pos))
	g.build.exit()
	await _shutdown()
