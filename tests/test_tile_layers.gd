extends "res://tests/test_case.gd"
## Phase 14: old-room upgrade, PNG-atlas slicing, sparse-layer persistence,
## collision/nav refresh, incremental chunk rendering and the 100x100 budget.

const Defaults := preload("res://scripts/core/defaults.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const RoomView := preload("res://scripts/world/room_view.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const TilesetFactory := preload("res://scripts/world/tileset_factory.gd")
const WorldMigration := preload("res://scripts/core/world_migration.gd")


func _world() -> void:
	fresh_save_root()
	StarterContent.create_world("Tile Test", "Sam")
	GameState.load_world()
	for id in TilesetFactory.BUILTIN:
		Tilesets.copy_from_library(id)


func test_v2_migration_snapshots_then_converts_old_rooms() -> void:
	_world()
	var w := SaveManager.load_world()
	w["version"] = 2
	SaveManager.save_world(w)
	var old := {"version": 1, "id": "old", "name": "Old", "size": {"w": 5, "d": 5, "h": 3},
		"ground": [{"x": 1, "z": 2, "set": "dream_meadow", "tile": "grass", "rot": 1}],
		"foreground": [{"x": 2, "y": 1, "z": 2, "set": "dream_meadow", "tile": "canopy", "fade": true}],
		"tiles": [{"x": 3, "y": 0, "z": 3, "type": "sprite", "set": "dream_meadow", "tile": "bush", "solid": true}], "objects": []}
	SaveManager.save_room(old)
	var result := WorldMigration.run()
	check(result.migrated and result.snapshot != "", "snapshot exists before v3 conversion")
	var migrated := SaveManager.load_room("old")
	eq(TileLayers.get_cell(TileLayers.find(migrated, "ground"), 1, 2).r, 1)
	check(not TileLayers.get_cell(TileLayers.find(migrated, "foreground"), 2, 2).is_empty(), "foreground converted")
	check(not TileLayers.get_cell(TileLayers.find(migrated, "blocks"), 3, 3).is_empty(), "sprite converted")
	eq(int(SaveManager.load_world().version), Defaults.WORLD_VERSION)


func test_atlas_import_and_tile_flags_are_round_trip_data() -> void:
	_world()
	var atlas := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	atlas.fill_rect(Rect2i(0, 0, 32, 32), Color("#ef718b"))
	atlas.fill_rect(Rect2i(32, 0, 32, 32), Color("#73c9a6"))
	var cells := Tilesets.slice_atlas(atlas, 32)
	eq(cells.size(), 2)
	var s := Tilesets.create("Generated atlas", 32)
	for i in cells.size():
		Tilesets.add_tile(s, "atlas %d" % i, cells[i].image, {"walkable": i == 0, "solid": i == 1, "step": "grass"})
	var flags := Tilesets.info(str(s.id), str(s.tiles[1].id))
	check(bool(flags.solid) and not bool(flags.walkable) and str(flags.step) == "grass", "flags remain attached to imported tile")
	eq(Tilesets.tile_image(str(s.id), str(s.tiles[0].id)).get_size(), Vector2i(32, 32))


func test_thousands_of_tiles_save_reload_and_rebuild_within_budget() -> void:
	_world()
	var room := Defaults.room("stress", "100 square")
	room["size"] = {"w": 100, "d": 100, "h": 3}
	for z in 100:
		for x in 100:
			RoomOps.set_ground(room, x, z, "dream_meadow", "grass")
	for z in range(0, 100, 5):
		for x in range(0, 100, 5):
			RoomOps.paint(room, "blocks", x, z, "dream_meadow", "bush", {"o": "standing", "solid": true})
	for z in range(1, 100, 4):
		for x in range(1, 100, 4):
			RoomOps.paint(room, "foreground", x, z, "dream_meadow", "canopy", {"o": "standing", "fade": false})
	eq(TileLayers.count(room), 11025, "10,000 ground + 400 blocks + 625 foreground")
	check(SaveManager.save_room(room), "large room saved")
	var loaded := SaveManager.load_room("stress")
	eq(loaded.tile_layers, room.tile_layers, "sparse layers reload identically")
	var view := RoomView.new()
	tree.root.add_child(view)
	view.build(loaded)
	await frames(2)
	check(not view.nav.walkable(Vector2i(0, 0)), "solid tile set flag drives navigation")
	check(view.nav.walkable(Vector2i(99, 99)), "ordinary floor remains walkable")
	var before: int = view.layers.call("draw_calls")
	check(before <= 160, "100x100 room uses <=160 chunk draw calls (got %d)" % before)
	check(float(view.layers.get("build_ms")) < 8000.0, "mesh build under 8 seconds (%.1f ms)" % float(view.layers.get("build_ms")))
	# A ground edit updates collision and only the dirty visual chunks.
	RoomOps.set_ground(loaded, 99, 99, "dream_meadow", "water")
	view.cells_changed("ground", [Vector2i(99, 99)])
	view.layers.call("flush")
	check(not view.nav.walkable(Vector2i(99, 99)), "unwalkable flag reaches nav immediately")
	RoomOps.set_ground(loaded, 99, 99, "dream_meadow", "grass")
	view.cells_changed("ground", [Vector2i(99, 99)])
	view.layers.call("flush")
	check(view.nav.walkable(Vector2i(99, 99)), "nav refreshes when the blocking flag is removed")
	eq(int(view.layers.call("draw_calls")), before, "editing preserves chunk draw-call count")
	view.free()
