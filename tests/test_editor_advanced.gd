extends "res://tests/test_case.gd"
## Phase 15 core coverage: all smart masks, neighbor refresh, custom layer
## edits, event triggers, find/replace/re-skin, graph links, hotbar and undo.

const StarterContent := preload("res://scripts/core/starter_content.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const SmartTiles := preload("res://scripts/world/smart_tiles.gd")
const TileEvents := preload("res://scripts/world/tile_events.gd")
const RoomSearch := preload("res://scripts/world/room_search.gd")
const RoomGraph := preload("res://scripts/world/room_graph.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const EditorHotbar := preload("res://scripts/builder/editor_hotbar.gd")

var main: Node


func _world() -> void:
	fresh_save_root()
	StarterContent.create_world("Advanced room", "Sam")
	GameState.load_world()


func _boot() -> Node:
	fresh_save_root()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var build: Node = main.game.build
	build.enter()
	await frames(1)
	return build


func _shutdown() -> void:
	if is_instance_valid(main):
		if main.game and main.game.build.active:
			main.game.build.exit()
		main.queue_free()
		await frames(2)


func test_all_sixteen_neighbor_masks_and_group_paint_refresh() -> void:
	_world()
	var set_data := Tilesets.create("Auto patterns", 16)
	var ids := PackedStringArray()
	for i in 16:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(float(i) / 16.0, 0.4, 0.6))
		ids.append(str(Tilesets.add_tile(set_data, "mask %d" % i, img).id))
	var variants: Array = Array(ids)
	var group_id := SmartTiles.assign(str(set_data.id), "Garden edge", variants, ids[0])
	check(group_id != "", "atlas-sliced tile set accepts a mask group")
	var masks := {}
	for i in 16:
		var got := SmartTiles.mask_from_neighbors(bool(i & 1), bool(i & 2), bool(i & 4), bool(i & 8))
		eq(got, i, "all N/E/S/W combinations map to their own mask")
		eq(SmartTiles.tile_for(str(set_data.id), group_id, i), ids[i], "mask selects its assigned atlas variant")
		masks[got] = true
	eq(masks.size(), 16, "all masks are distinct")
	var room := SaveManager.load_room("home")
	SmartTiles.paint(room, "ground", Vector2i(5, 5), str(set_data.id), group_id)
	SmartTiles.paint(room, "ground", Vector2i(6, 5), str(set_data.id), group_id)
	var layer := TileLayers.find(room, "ground")
	eq(TileLayers.get_cell(layer, 5, 5).smart_mask, 2, "center sees east neighbor")
	eq(str(TileLayers.get_cell(layer, 5, 5).t), ids[2], "mask chooses the matching atlas variant")
	eq(TileLayers.get_cell(layer, 6, 5).smart_mask, 8, "neighbor sees west center")
	SmartTiles.erase(room, "ground", Vector2i(6, 5))
	eq(TileLayers.get_cell(layer, 5, 5).smart_mask, 0, "erase reevaluates neighbor")
	SaveManager.save_room(room)
	var loaded := SaveManager.load_room("home")
	var persisted := TileLayers.get_cell(TileLayers.find(loaded, "ground"), 5, 5)
	eq(str(persisted.smart_group), group_id, "smart group persists")
	eq(int(persisted.smart_mask), 0, "neighbor mask persists")
	eq(str(persisted.smart_tile), ids[0], "resolved variant persists")


func test_layer_operations_events_and_undo_redo() -> void:
	var b: Node = await _boot()
	var room: Dictionary = b.world.room.data
	b.edit_room(func(data): TileLayers.add(data, "Soft canopy", "foreground"))
	var layers := TileLayers.all(b.world.room.data)
	var new_layer: Dictionary = layers.back()
	check(str(new_layer.get("name", "")) == "Soft canopy", "custom layer created")
	b.undo()
	check(TileLayers.find(b.world.room.data, str(new_layer.id)).is_empty(), "layer add undo")
	b.redo()
	check(not TileLayers.find(b.world.room.data, str(new_layer.id)).is_empty(), "layer add redo")
	var variants: Array = []
	for i in 16:
		variants.append("rug")
	var group_id := SmartTiles.assign("cozy_home", "Editor edge", variants, "rug")
	b.set_layer("ground")
	b.set_brush_tile("cozy_home", "rug")
	b.set_smart_group(group_id)
	b.cursor = Vector2i(2, 2)
	b.apply({})
	eq(str(TileLayers.get_cell(TileLayers.find(b.world.room.data, "ground"), 2, 2).get("smart_group", "")), group_id, "smart paint stores the group")
	b.undo()
	check(TileLayers.get_cell(TileLayers.find(b.world.room.data, "ground"), 2, 2).is_empty(), "smart paint undo")
	b.redo()
	eq(str(TileLayers.get_cell(TileLayers.find(b.world.room.data, "ground"), 2, 2).get("smart_group", "")), group_id, "smart paint redo")
	var ground := TileLayers.find(b.world.room.data, "ground")
	RoomOps.set_ground(b.world.room.data, 4, 4, "cozy_home", "rug")
	TileLayers.put(ground, 4, 4, TileLayers.make_cell("cozy_home", "rug", "", {"event": {"trigger": "step", "action": "text", "value": "A small memory.", "once": true}}))
	var first := TileEvents.claim(b.world.room.data, "ground", Vector2i(4, 4), "step")
	check(not first.is_empty(), "step event claims once")
	check(TileEvents.claim(b.world.room.data, "ground", Vector2i(4, 4), "step").is_empty(), "one-shot does not repeat")
	check(TileEvents.claim(b.world.room.data, "ground", Vector2i(4, 4), "interact").is_empty(), "event ignores the other trigger")
	var ground_data := TileLayers.find(b.world.room.data, "ground")
	TileLayers.put(ground_data, 7, 7, TileLayers.make_cell("cozy_home", "rug", "", {"event": {"trigger": "interact", "action": "text", "value": "Again is okay.", "once": false}}))
	check(not TileEvents.claim(b.world.room.data, "ground", Vector2i(7, 7), "interact").is_empty(), "repeat event fires on interaction")
	check(not TileEvents.claim(b.world.room.data, "ground", Vector2i(7, 7), "interact").is_empty(), "repeat event may fire again")
	SaveManager.save_room(b.world.room.data)
	check(bool(TileLayers.get_cell(TileLayers.find(SaveManager.load_room("home"), "ground"), 4, 4).event_done), "one-shot persisted")
	var manager := preload("res://scripts/ui/layer_manager_panel.gd").new()
	manager.build = b
	main.open_panel(manager)
	await frames(2)
	manager._pick.select(TileLayers.index_of(b.world.room.data, str(new_layer.id)))
	manager._load_selected(manager._pick.selected)
	var palette: Control = b.shell.palette
	var layer_button: Button = palette._layer_btns.get(str(new_layer.id))
	manager._name.text = "Soft canopy edited"
	manager._opacity.value = 0.65
	manager._locked.button_pressed = true
	manager._apply()
	var edited_layer := TileLayers.find(b.world.room.data, str(new_layer.id))
	eq(str(edited_layer.name), "Soft canopy edited", "custom layer rename applies")
	if check(layer_button != null, "the custom layer has a palette button"):
		eq(palette._layer_btns.get(str(new_layer.id)), layer_button, "renaming keeps the palette button")
		eq(layer_button.text, "Soft canopy edited", "the palette shows the new name immediately")
	check(is_equal_approx(float(edited_layer.opacity), 0.65), "custom layer opacity applies")
	check(bool(edited_layer.locked), "custom layer lock applies")
	var previous_index := TileLayers.index_of(b.world.room.data, str(new_layer.id))
	manager._move(-1)
	eq(TileLayers.index_of(b.world.room.data, str(new_layer.id)), previous_index - 1, "custom layer reorders")
	b.edit_room(func(data): TileLayers.remove(data, str(new_layer.id)), "remove")
	check(TileLayers.find(b.world.room.data, str(new_layer.id)).is_empty(), "custom layer delete applies")
	b.undo()
	check(not TileLayers.find(b.world.room.data, str(new_layer.id)).is_empty(), "custom layer delete undo restores layer")
	b.selection = Rect2i(Vector2i(4, 4), Vector2i.ONE)
	manager._pick.select(TileLayers.index_of(b.world.room.data, "ground"))
	manager._target.select(TileLayers.index_of(b.world.room.data, str(new_layer.id)))
	manager._load_selected(manager._pick.selected)
	manager._move_selection()
	check(TileLayers.get_cell(TileLayers.find(b.world.room.data, "ground"), 4, 4).is_empty(), "moving selection clears source layer")
	check(not TileLayers.get_cell(TileLayers.find(b.world.room.data, str(new_layer.id)), 4, 4).is_empty(), "moving selection fills destination layer")
	b.undo()
	check(not TileLayers.get_cell(TileLayers.find(b.world.room.data, "ground"), 4, 4).is_empty(), "selection move undo restores source")
	manager.close()
	await frames(1)
	await _shutdown()


func test_find_replace_reskin_and_world_map_links() -> void:
	var build: Node = await _boot()
	var set_a := Tilesets.create("Old palette")
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	Tilesets.add_tile(set_a, "moss", image)
	image.fill(Color.GREEN)
	var set_b := Tilesets.create("New palette")
	Tilesets.add_tile(set_b, "moss", image)
	var room: Dictionary = build.world.room.data
	for x in 3:
		RoomOps.set_ground(room, x, 3, str(set_a.id), str(set_a.tiles[0].id))
	var replacement: int = int(build.edit_room(func(data): return RoomSearch.find_replace(data, str(set_a.id), str(set_a.tiles[0].id), str(set_b.id), str(set_b.tiles[0].id))))
	eq(replacement, 3, "find/replace counts matching cells")
	eq(str(RoomOps.ground_at(build.world.room.data, 0, 3).s), str(set_b.id), "replace applied")
	build.undo()
	eq(str(RoomOps.ground_at(build.world.room.data, 0, 3).s), str(set_a.id), "find/replace undo")
	build.redo()
	eq(str(RoomOps.ground_at(build.world.room.data, 0, 3).s), str(set_b.id), "find/replace redo")
	eq(RoomSearch.reskin(room, str(set_b.id), str(set_a.id)), 3, "re-skin maps by tile name")
	var a := Defaults.room("alpha", "Alpha")
	var b := Defaults.room("beta", "Beta")
	check(RoomGraph.connect_rooms(a, b), "connect two map nodes")
	check(RoomGraph.links(a).has("beta") and RoomGraph.links(b).has("alpha"), "reciprocal door links")
	check(RoomGraph.valid_links(PackedStringArray(["alpha", "beta"]), {"alpha": a, "beta": b}), "map link integrity")
	eq(RoomGraph.auto_layout(PackedStringArray(["alpha", "beta"])).size(), 2)
	var crowded := Defaults.room("crowded", "Crowded")
	for z in int(crowded.size.d):
		for x in int(crowded.size.w):
			RoomEditor.add_object(crowded, x, z, "prop")
	var alpha_objects_before: int = a.objects.size()
	check(not RoomGraph.connect_rooms(a, crowded), "map rejects a connection if the second room has no door cell")
	eq(a.objects.size(), alpha_objects_before, "failed map link leaves the first room unchanged")
	check(not RoomGraph.links(a).has("crowded"), "failed map link never leaves a one-way door")
	await _shutdown()


func test_hotbar_keeps_smart_tile_brush_identity() -> void:
	var b: Node = await _boot()
	var entry := {"kind": "tile", "set": "cozy_home", "tile": "rug", "layer": "ground", "smart_group": "meadow_edges"}
	EditorHotbar.pin(0, entry)
	eq(EditorHotbar.slots()[0].smart_group, "meadow_edges", "favorite stores smart group")
	EditorHotbar.activate(b, EditorHotbar.slots()[0])
	eq(b.smart_group, "meadow_edges", "favorite restores smart mode")
	await _shutdown()


func test_advanced_panels_are_reachable_and_world_map_loads() -> void:
	var b: Node = await _boot()
	b.shell._set_pref("advanced", true)
	check(b.shell.palette._advanced_row.visible and b.shell.palette._hotbar.visible, "advanced palette tools and hotbar show only in Advanced")
	check(b.shell.room_tab._advanced_tools.visible, "World Map entry appears in Advanced > Room")
	var map := preload("res://scripts/ui/world_map_panel.gd").new()
	map.build = b
	main.open_panel(map)
	await frames(2)
	check(map._canvas.ids.size() >= 3, "map shows Home, Garden and Tile Playground")
	check(map._canvas.size.x >= 700, "map canvas has room for rearranged nodes")
	map.close()
	await frames(1)
	var search := preload("res://scripts/ui/room_search_panel.gd").new()
	search.build = b
	main.open_panel(search)
	await frames(2)
	check(search._from_set.item_count >= 1, "find/replace lists the active tile sets")
	search.close()
	var wizard := preload("res://scripts/ui/smart_tile_wizard.gd").new()
	wizard.build = b
	main.open_panel(wizard)
	await frames(2)
	check(wizard._variants.size() == 16 and wizard._fallback.item_count > 0, "smart-tile wizard exposes all 16 patterns and available tiles")
	wizard._name.text = "Wizard group"
	wizard._save()
	check(b.smart_group != "", "wizard saves and activates a smart tile group")
	check(not SmartTiles.group(b.brush_set, b.smart_group).is_empty(), "wizard group is stored in the selected tile set")
	await _shutdown()
