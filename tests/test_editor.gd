extends "res://tests/test_case.gd"
## The organized editor: tools, strokes as one undo step, 100+ undo steps,
## layers (lock), select/copy/paste/rotate/flip, eyedropper, stamps,
## templates from the gallery, persistence after a restart.

const RoomOps := preload("res://scripts/world/room_ops.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const TilesetFactory := preload("res://scripts/world/tileset_factory.gd")
const Templates := preload("res://scripts/world/templates.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")


func _ground_count(room: Dictionary) -> int:
	return (TileLayers.find(room, "ground").get("cells", {}) as Dictionary).size()

var main: Node


func _boot() -> Node:
	fresh_save_root()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	TilesetFactory.ensure_builtin()
	Tilesets.copy_from_library("cozy_home")
	Tilesets.copy_from_library("dream_meadow")
	var b: Node = main.game.build
	b.enter()
	await frames(1)
	return b


func _shutdown() -> void:
	if main.game and main.game.build.active:
		main.game.build.exit()
	main.queue_free()
	await frames(2)


func test_first_run_tile_flow_is_obvious() -> void:
	var b: Node = await _boot()
	eq(b.mode, "tiles", "editor opens on Tiles")
	eq(b.piece, "tile", "first tile brush is ready")
	check(b.brush_set != "" and b.brush_tile != "", "first tile is selected")
	check(b.shell.palette.tab == "tiles", "palette opens to the Tiles tab")
	check(b.shell.palette._coach.visible, "first-run coach tells the three-step flow")
	await _shutdown()


func test_palette_updates_selection_and_tileset_edits() -> void:
	var build: Node = await _boot()
	var palette: Control = build.shell.palette
	await frames(10)
	var rug: Button = palette._tile_buttons.get("cozy_home/rug")
	var old_selection: Button = palette._selected_tile_button
	if check(rug != null, "the Cozy Home rug has a button"):
		rug.pressed.emit()
		eq(build.brush_tile, "rug", "click selects the brush")
		eq(palette._tile_buttons.get("cozy_home/rug"), rug, "selecting a tile keeps its button")
		check(rug.button_pressed, "the selected brush is highlighted")
		if is_instance_valid(old_selection) and old_selection != rug:
			check(not old_selection.button_pressed, "previous brush is no longer highlighted")
		var search: LineEdit = palette._search
		search.text = "Renamed rug fixture"
		search.text_changed.emit(search.text)
		check(palette._tile_buttons.is_empty(), "search filters the tile list")
		palette._manager()
		var manager: Control = main.panels.back()
		var tile_set := Tilesets.load_set("cozy_home")
		Tilesets.find_tile(tile_set, "rug")["name"] = search.text
		Tilesets.save_set(tile_set)
		manager.changed.emit()
		var updated: Button = palette._tile_buttons.get("cozy_home/rug")
		if check(updated != null, "the edited tile matches the active search immediately"):
			check(updated.button_pressed, "rebuilding the list keeps the current selection")
	await _shutdown()


func _press(b: Node, at: Vector2i) -> void:
	b.cursor = at
	b._press({})


func _move(b: Node, at: Vector2i) -> void:
	b.cursor = at
	b._on_cursor_moved()


func test_brush_stroke_is_one_undo_step_and_undo_holds_150() -> void:
	var b: Node = await _boot()
	b.set_layer("ground")
	b.set_brush_tile("cozy_home", "rug")
	b.set_tool("brush")
	var steps_before: int = b.history.size()
	_press(b, Vector2i(1, 1))
	for x in range(2, 8):
		_move(b, Vector2i(x, 1))
	b._release()
	eq(_ground_count(main.game.room.data), 7, "seven ground tiles painted")
	eq(b.history.size(), steps_before + 1, "one stroke = one undo step")
	b.undo()
	eq(_ground_count(main.game.room.data), 0, "the whole stroke undone at once")
	b.redo()
	eq(_ground_count(main.game.room.data), 7)
	b.set_tool("place")
	b.set_piece("cube")
	for i in 160:
		_press(b, Vector2i(i % 10, 2 + (i / 10) % 5))
	eq(b.history.size(), 150, "undo keeps 150 steps")
	for i in 150:
		b.undo()
	check(not b.history.can_undo(), "150 undos possible")
	await _shutdown()


func test_shape_tools_fill_and_erase() -> void:
	var b: Node = await _boot()
	b.set_layer("ground")
	b.set_brush_tile("dream_meadow", "grass")
	b.set_tool("rect")
	_press(b, Vector2i(0, 0))
	_move(b, Vector2i(3, 3))
	b._release()
	eq(_ground_count(main.game.room.data), 16, "filled rectangle")
	b.set_tool("rect_outline")
	_press(b, Vector2i(5, 5))
	_move(b, Vector2i(8, 8))
	b._release()
	eq(_ground_count(main.game.room.data), 16 + 12, "outline rectangle")
	b.set_tool("line")
	_press(b, Vector2i(0, 9))
	_move(b, Vector2i(9, 9))
	b._release()
	eq(_ground_count(main.game.room.data), 28 + 10, "line")
	b.set_brush_tile("dream_meadow", "path")
	b.set_tool("fill")
	_press(b, Vector2i(6, 6))   # inside the outline: the untiled pocket
	eq(RoomOps.ground_at(main.game.room.data, 6, 6).t, "path", "flood filled the pocket")
	eq(RoomOps.ground_at(main.game.room.data, 5, 5).t, "grass", "but not the outline")
	b.set_tool("erase")
	b.set_brush_size(3)
	_press(b, Vector2i(1, 1))
	b._release()
	eq(RoomOps.ground_at(main.game.room.data, 0, 0).size(), 0, "3x3 erase")
	check(not RoomOps.ground_at(main.game.room.data, 3, 3).is_empty(), "outside the brush untouched")
	await _shutdown()


func test_foreground_blocks_layers_and_lock() -> void:
	var b: Node = await _boot()
	b.set_layer("foreground")
	b.set_brush_tile("dream_meadow", "canopy")
	b.set_elevation(2)
	b.set_tool("place")
	_press(b, Vector2i(4, 4))
	var f := RoomOps.fg_at(main.game.room.data, 4, 4)
	eq(int(f.get("y", 0)), 2)
	eq(f.get("fade", true), true)
	eq(TileLayers.orient_of(TileLayers.find(main.game.room.data, "foreground"), f), "standing")
	b.set_layer("blocks")
	b.set_orient("wall_n")
	b.set_brush_tile("cozy_home", "window")
	b.set_elevation(1)
	_press(b, Vector2i(2, 0))
	var blocks_layer: Dictionary = TileLayers.find(main.game.room.data, "blocks")
	var placed_picture := TileLayers.get_cell(blocks_layer, 2, 0)
	check(not placed_picture.is_empty(), "picture painted on the Blocks tile layer")
	eq(TileLayers.orient_of(blocks_layer, placed_picture), "wall_n")
	b.set_orient("floor")
	b.set_elevation(0)
	_press(b, Vector2i(5, 5))
	b.solid = true
	_press(b, Vector2i(5, 5))
	check(not main.game.room.nav.walkable(Vector2i(5, 5)), "solid picture blocks walking")
	RoomOps.set_layer_state(main.game.room.data, "blocks", "lock", true)
	var n: int = TileLayers.count(main.game.room.data)
	_press(b, Vector2i(6, 6))
	eq(TileLayers.count(main.game.room.data), n, "locked layer refuses edits")
	RoomOps.layer_state(main.game.room.data, "blocks")["visible"] = false
	main.game.rebuild_room()
	check(main.game.room.layers.get_child_count() >= 1, "hidden layer still leaves the others")
	await _shutdown()


func test_select_copy_paste_rotate_flip_and_eyedropper() -> void:
	var b: Node = await _boot()
	b.set_layer("ground")
	b.set_brush_tile("cozy_home", "rug")
	b.set_tool("place")
	_press(b, Vector2i(1, 1))
	b.set_brush_tile("cozy_home", "wood_floor")
	_press(b, Vector2i(2, 1))
	b.set_tool("select")
	_press(b, Vector2i(1, 1))
	_move(b, Vector2i(2, 1))
	b._release()
	check(b.tools.has_selection(), "selected")
	eq(b.selection.size, Vector2i(2, 1))
	b.tools.copy_selection()
	eq(b.clipboard.cells.size(), 2)
	b.tools.paste_clipboard()
	eq(b.tool, "stamp", "paste switches to the stamp tool")
	_press(b, Vector2i(5, 5))
	eq(RoomOps.ground_at(main.game.room.data, 5, 5).t, "rug", "pasted")
	eq(RoomOps.ground_at(main.game.room.data, 6, 5).t, "wood_floor")
	b.rotate_piece()
	_press(b, Vector2i(8, 1))
	check(not RoomOps.ground_at(main.game.room.data, 8, 2).is_empty(), "rotated stamp runs the other way")
	b.tools.flip_selection()
	eq(RoomOps.ground_at(main.game.room.data, 1, 1).t, "wood_floor", "flipped in place")
	b.tools.cut_selection()
	check(RoomOps.ground_at(main.game.room.data, 1, 1).is_empty(), "cut")
	b.set_tool("eyedropper")
	_press(b, Vector2i(5, 5))
	eq(b.brush_tile, "rug", "eyedropper picked the rug")
	eq(b.tool, "place", "and switched to place")
	b.set_random(true)
	b.toggle_random_tile("cozy_home", "rug")
	b.toggle_random_tile("cozy_home", "wood_floor")
	b.set_tool("rect")
	_press(b, Vector2i(0, 8))
	_move(b, Vector2i(9, 9))
	b._release()
	var names := {}
	var ground_cells: Dictionary = TileLayers.find(main.game.room.data, "ground").cells
	for k in ground_cells:
		var pos := TileLayers.parse_key(str(k))
		if pos.y >= 8:
			names[str(ground_cells[k].t)] = true
	eq(names.size(), 2, "random brush used both tiles")
	await _shutdown()


func test_stamp_template_and_persistence_after_restart() -> void:
	var b: Node = await _boot()
	b.set_layer("ground")
	b.set_brush_tile("dream_meadow", "flowers")
	b.set_tool("rect")
	_press(b, Vector2i(0, 0))
	_move(b, Vector2i(1, 1))
	b._release()
	b.set_tool("select")
	_press(b, Vector2i(0, 0))
	_move(b, Vector2i(1, 1))
	b._release()
	var sid := Templates.save_stamp("Flowers", b.tools.selection_stamp())
	b.set_stamp(Templates.stamp_for_use(sid))
	_press(b, Vector2i(6, 6))
	eq(RoomOps.ground_at(main.game.room.data, 7, 7).t, "flowers", "stamp placed")
	TemplateFactory.ensure_builtin()
	var made := Templates.new_level("night_rooftop")
	eq(made.size(), 1)
	b.set_layer("foreground")
	b.set_brush_tile("dream_meadow", "canopy")
	b.set_tool("place")
	_press(b, Vector2i(3, 3))
	b.exit()
	# Restart the whole game: everything must come back.
	main.queue_free()
	await frames(2)
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.start_game()
	await frames(3)
	var home := SaveManager.load_room("home")
	eq(RoomOps.ground_at(home, 7, 7).t, "flowers", "stamped tiles survived the restart")
	check(not RoomOps.fg_at(home, 3, 3).is_empty(), "foreground tile survived")
	check("night_rooftop" in SaveManager.list_rooms(), "template room survived")
	check(Tilesets.exists("night_sky"), "its tile set survived")
	check(main.game.room.layers.get_child_count() >= 2, "layers rendered after restart")
	await _shutdown()


func test_room_check_from_the_room_tab_and_play_test() -> void:
	var b: Node = await _boot()
	b.set_mode("room")
	b.shell.room_tab._check()
	await frames(1)
	check(b.shell.room_tab._issues.get_child_count() >= 1, "room check reports something")
	b.cursor = Vector2i(3, 6)
	b.play_test()
	check(not b.active, "left the editor")
	eq(main.game.player.cell(), Vector2i(3, 6), "playing from the cursor")
	await _shutdown()
