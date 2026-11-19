extends "res://tests/test_case.gd"
## Tile sets (built-in, from an atlas, from a drawing, library, bundles),
## layer data operations, picture-layer rendering with fading foreground,
## templates and stamps.

const Tilesets := preload("res://scripts/world/tilesets.gd")
const TilesetFactory := preload("res://scripts/world/tileset_factory.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const RoomView := preload("res://scripts/world/room_view.gd")
const Templates := preload("res://scripts/world/templates.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")


func _count_layer(room: Dictionary, layer_id: String) -> int:
	var layer := TileLayers.find(room, layer_id)
	return (layer.get("cells", {}) as Dictionary).size()


func _find_layer_cell(room: Dictionary, layer_id: String, x: int, z: int) -> Dictionary:
	return TileLayers.get_cell(TileLayers.find(room, layer_id), x, z)


func _world() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	GameState.load_world()
	check(SaveManager.room_exists("tile_playground"), "a new world includes the connected Tile Playground")


func test_builtin_sets_generate_into_the_library() -> void:
	_world()
	TilesetFactory.ensure_builtin()
	eq(Tilesets.ids(true).size(), 14, "fourteen starter sets (Tiny Town is Kenney's)")
	for id in TilesetFactory.BUILTIN:
		var s := Tilesets.load_set(id, true)
		check(s.tiles.size() >= 8, "%s has %d tiles" % [id, s.tiles.size()])
		for t in s.tiles:
			check(FileAccess.file_exists(Tilesets.set_dir(id, true).path_join(str(t.image))), "%s/%s picture exists" % [id, t.id])
	var torch := Tilesets.find_tile(Tilesets.load_set("dark_castle", true), "torch")
	eq(torch.frames.size(), 1, "the torch animates (2 frames)")
	check(Tilesets.copy_from_library("cozy_home"), "copied into the world")
	check(Tilesets.exists("cozy_home"), "world has it now")
	check(Tilesets.tile_path("cozy_home", "rug").ends_with("tiles/rug.png"))
	eq(Tilesets.tile_path("cozy_home", "nope"), "", "unknown tile")
	check(SaveManager.load_texture(Tilesets.tile_path("cozy_home", "rug")) != null, "tile loads as a texture")


func test_set_from_an_atlas_and_from_a_drawing() -> void:
	_world()
	var atlas := Image.create(96, 32, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	atlas.fill_rect(Rect2i(0, 0, 32, 32), Color.RED)
	atlas.fill_rect(Rect2i(64, 0, 32, 32), Color.BLUE)
	var cells := Tilesets.slice_atlas(atlas, 32)
	eq(cells.size(), 2, "empty atlas cells are skipped")
	var s := Tilesets.create("My Atlas", 32)
	for c in cells:
		Tilesets.add_tile(s, "cell %d" % c.x, c.image, {"solid": c.x == 2})
	var loaded := Tilesets.load_set(s.id)
	eq(loaded.tiles.size(), 2)
	eq(loaded.tiles[0].id, "cell_0")
	eq(loaded.tiles[1].solid, true, "flags kept")
	var img := Image.load_from_file(Tilesets.set_dir(s.id).path_join(str(loaded.tiles[1].image)))
	check(img.get_pixel(5, 5).is_equal_approx(Color.BLUE), "the right cell was cut out")
	# A drawn tile, resized to the set's size, with an animation frame.
	var drawing := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	drawing.fill(Color.GREEN)
	var t := Tilesets.add_tile(s, "Drawn", drawing)
	eq(Image.load_from_file(Tilesets.set_dir(s.id).path_join(str(t.image))).get_width(), 32, "resized to the set size")
	Tilesets.set_tile_image(s, str(t.id), drawing, 1)
	eq(Tilesets.find_tile(Tilesets.load_set(s.id), str(t.id)).frames.size(), 1, "frame added")
	check(Tilesets.tile_path(s.id, str(t.id), 1).ends_with("_f1.png"))
	Tilesets.move_tile(s, str(t.id), -5)
	eq(Tilesets.load_set(s.id).tiles[0].id, t.id, "reordered to the front")
	Tilesets.remove_tile(s, "cell_0")
	eq(Tilesets.load_set(s.id).tiles.size(), 2)
	check(not FileAccess.file_exists(Tilesets.set_dir(s.id).path_join("tiles/cell_0.png")), "picture removed with the tile")


func test_usage_library_and_bundles() -> void:
	var root := fresh_save_root()
	StarterContent.create_world("T", "Sam")
	GameState.load_world()
	var s := Tilesets.create("Rugs")
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.PURPLE)
	Tilesets.add_tile(s, "rug", img)
	var home := SaveManager.load_room("home")
	RoomOps.set_ground(home, 2, 2, "rugs", "rug")
	SaveManager.save_room(home)
	eq(Tilesets.rooms_using("rugs"), PackedStringArray(["home"]), "in use by home")
	eq(Tilesets.rooms_using("rugs", "other").size(), 0)
	check(Tilesets.copy_to_library("rugs"), "saved to the library")
	check(Tilesets.exists("rugs", true))
	var dest := root.path_join("rugs.polox-tiles")
	check(Tilesets.export_set("rugs", dest), "exported")
	var r := Tilesets.import_set(dest)
	check(r.ok and r.id == "rugs_2", "imported as a new set: " + str(r))
	eq(Tilesets.load_set("rugs_2").tiles.size(), 1)
	Tilesets.delete_set("rugs")
	check(not Tilesets.exists("rugs"))


func test_layer_data_operations() -> void:
	var r := Defaults.room("r", "R")
	check(not RoomOps.set_ground(r, 1, 1, "s", "a").is_empty())
	RoomOps.set_ground(r, 1, 1, "s", "b")
	eq(_count_layer(r, "ground"), 1, "one ground tile per cell")
	eq(RoomOps.ground_at(r, 1, 1).t, "b")
	check(RoomOps.remove_ground(r, 1, 1) and not RoomOps.remove_ground(r, 1, 1))
	var fg1 := RoomOps.add_fg(r, 2, 0, 2, "s", "c", "standing")
	var fg2 := RoomOps.add_fg(r, 2, 1, 2, "s", "c", "wall_n", {"fade": false})
	check(not fg1.is_empty() and not fg2.is_empty(), "stacked foreground tiles are preserved in separate sparse layers")
	eq(int(RoomOps.fg_at(r, 2, 2).get("y", 0)), 1, "topmost foreground tile")
	check(RoomOps.remove_fg_top(r, 2, 2))
	eq(RoomOps.fg_at(r, 2, 2).get("fade", true), true)
	RoomOps.add_sprite(r, 3, 0, 3, "s", "bush", "standing", true)
	check(RoomOps.blocks_walk(r, 3, 3), "a solid sprite blocks")
	check(not RoomOps.blocks_walk(r, 2, 2), "a non-solid foreground doesn't")
	eq(RoomOps.line_cells(Vector2i(0, 0), Vector2i(3, 1)).size(), 4)
	eq(RoomOps.rect_cells(Vector2i(0, 0), Vector2i(2, 2), true).size(), 9)
	eq(RoomOps.rect_cells(Vector2i(0, 0), Vector2i(2, 2), false).size(), 8)
	eq(RoomOps.brush_cells(Vector2i(5, 5), 3).size(), 9)
	for x in 4:
		for z in 4:
			RoomOps.set_ground(r, x, z, "s", "g")
	RoomOps.set_ground(r, 1, 1, "s", "other")
	eq(RoomOps.flood_cells(r, Vector2i(0, 0)).size(), 15, "flood stops at a different tile")
	var stamp := RoomOps.copy_region(r, Vector2i(0, 0), Vector2i(3, 3))
	eq(stamp.cells.size(), 18, "all tile types are stored in the sparse layers")
	eq(stamp.tiles.size(), 0)
	var rotated := RoomOps.rotate_stamp(stamp)
	eq(rotated.w, 4)
	var spot: Dictionary = rotated.cells.filter(func(e): return e.type == "blocks")[0]
	eq(Vector2i(int(spot.x), int(spot.z)), Vector2i(0, 3), "standing tile at (3,3) turns to (0,3)")
	var flipped := RoomOps.flip_stamp(stamp)
	var flipped_spot: Dictionary = flipped.cells.filter(func(e): return e.type == "blocks")[0]
	eq(Vector2i(int(flipped_spot.x), int(flipped_spot.z)), Vector2i(0, 3))
	eq(flipped_spot.cell.fl, true)
	var r2 := Defaults.room("r2", "R2")
	var placed := RoomOps.paste(r2, stamp, Vector2i(5, 4), "merge")
	eq(placed, 18, "16 ground + 1 sprite + 1 foreground")
	eq(RoomOps.ground_at(r2, 5, 4).t, "g")
	RoomOps.clear_region(r2, Vector2i(5, 4), Vector2i(8, 7))
	eq(_count_layer(r2, "ground"), 0, "cleared")
	eq(r2.tiles.size(), 0)


func test_room_check_finds_real_problems() -> void:
	_world()
	var r := SaveManager.load_room("garden")
	check(RoomOps.room_check(r).filter(func(i): return i.severity == "warn").is_empty(), "the starter garden is fine")
	var door: Dictionary = r.objects.filter(func(o): return o.type == "door")[0]
	var dc := Vector2i(int(door.pos[0]), int(door.pos[2]))
	r["spawn"] = [8, 8]
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx != 0 or dz != 0:
				RoomEditor.add_tile(r, dc.x + dx, dc.y + dz, "cube", "#fff")
	RoomOps.set_ground(r, 1, 1, "ghost_set", "nope")
	door["door_target"] = "nowhere"
	var issues := RoomOps.room_check(r)
	check(issues.any(func(i): return i.problem.find("can't be reached") != -1), "unreachable door reported")
	check(issues.any(func(i): return i.problem.find("doesn't exist") != -1), "bad door target reported")
	check(issues.any(func(i): return i.problem.find("doesn't have") != -1), "missing tile picture reported")


func test_layers_render_and_foreground_fades_behind_people() -> void:
	_world()
	Tilesets.copy_from_library("dream_meadow") if Tilesets.exists("dream_meadow", true) else TilesetFactory.make("dream_meadow", false)
	var r := Defaults.room("r", "R")
	for x in 6:
		for z in 6:
			RoomOps.set_ground(r, x, z, "dream_meadow", "grass")
	RoomOps.add_sprite(r, 1, 0, 1, "dream_meadow", "bush", "standing", true)
	RoomOps.add_fg(r, 3, 0, 3, "dream_meadow", "canopy", "standing")
	var view := RoomView.new()
	tree.root.add_child(view)
	view.build(r)
	await frames(1)
	check(view.layers.get_child_count() == 3, "one ground batch + sprite + foreground (%d)" % view.layers.get_child_count())
	check(not view.nav.walkable(Vector2i(1, 1)), "solid sprite blocks walking")
	check(view.nav.walkable(Vector2i(3, 3)), "foreground doesn't block")
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	cam.global_position = Vector3(3.5, 2.0, 12.0)
	cam.look_at(Vector3(3.5, 0.5, 3.5))
	var person := Node3D.new()
	tree.root.add_child(person)
	person.global_position = Vector3(3.5, 0, 1.5)  # behind the canopy, seen from the camera
	await frames(1)
	for i in 30:
		view.layers.update_fade([person], cam, 0.1)
	eq(view.layers.faded_count(), 1, "the canopy fades while it hides someone")
	person.global_position = Vector3(0.5, 0, 5.5)
	for i in 30:
		view.layers.update_fade([person], cam, 0.1)
	eq(view.layers.faded_count(), 0, "and comes back when they step out")
	view.queue_free()
	cam.queue_free()
	person.queue_free()
	await frames(1)


func test_layers_persist_through_save_and_load() -> void:
	_world()
	var r := SaveManager.load_room("home")
	RoomOps.set_ground(r, 0, 0, "cozy_home", "rug", 2, true, "#ff0000")
	RoomOps.add_fg(r, 4, 2, 4, "cozy_home", "curtain", "wall_e", {"fade": false, "tint": "#00ff00"})
	RoomOps.add_sprite(r, 5, 0, 5, "cozy_home", "lamp", "standing", true)
	RoomOps.set_layer_state(r, "foreground", "opacity", 0.5)
	SaveManager.save_room(r)
	var back := SaveManager.load_room("home")
	var ground := _find_layer_cell(back, "ground", 0, 0)
	eq(ground.r, 2)
	eq(ground.fl, true)
	eq(ground.tint, "#ff0000")
	var fg := _find_layer_cell(back, "foreground", 4, 4)
	eq(TileLayers.orient_of(TileLayers.find(back, "foreground"), fg), "wall_e")
	eq(fg.fade, false)
	eq(_find_layer_cell(back, "blocks", 5, 5).s, "cozy_home")
	eq(float(TileLayers.find(back, "foreground").opacity), 0.5)


func test_templates_builtin_new_level_apply_and_stamps() -> void:
	_world()
	TemplateFactory.ensure_builtin()
	eq(Templates.ids().size(), 25, "twenty-five built-in templates")
	check(Templates.ids().has("sky_steps") and Templates.ids().has("moon_ledges"), "the two Platform Mode courses")
	check(Templates.ids().has("movement_lab"), "and the Movement Lab")
	for id in Templates.ids():
		check(Templates.thumb_path(id) != "", id + " has a thumbnail")
	var made := Templates.new_level("cozy_apartment")
	eq(made.size(), 3, "three linked rooms")
	eq(made[0], "living_room", "start room first")
	var living := SaveManager.load_room(made[0])
	var to_hall: Array = living.objects.filter(func(o): return o.type == "door" and o.door_target == made[1])
	eq(to_hall.size(), 1, "doors re-linked to the new ids")
	check(Tilesets.exists("cozy_home"), "the tile set came along")
	check(_count_layer(living, "ground") > 0 and _count_layer(living, "foreground") > 0, "layers filled")
	# Apply onto the starter home: replace keeps the home's own doors.
	var doors_before: Array = SaveManager.load_room("home").objects.filter(func(o): return o.type == "door")
	check(Templates.apply_to_room("garden", "home", "replace"))
	var home := SaveManager.load_room("home")
	eq(home.name, "Home", "name kept")
	eq(home.objects.filter(func(o): return o.type == "door").size(), doors_before.size(), "all existing doors kept")
	check(home.objects.any(func(o): return o.type == "door" and o.door_target == "garden"), "garden door kept")
	check(TileLayers.tiles_used(home).any(func(st): return st[0] == "dream_meadow"), "garden tiles applied")
	check(Templates.apply_to_room("cave", "home", "merge"))
	home = SaveManager.load_room("home")
	var used_sets := TileLayers.tiles_used(home).map(func(st): return st[0])
	check("dark_castle" in used_sets and "dream_meadow" in used_sets, "merge keeps both")
	# Save as template from the world, then a stamp.
	var tid := Templates.save_from_rooms("My Place", "mine", ["custom"], PackedStringArray(["home"]), TemplateFactory.thumb(home))
	check(Templates.load_template(tid).rooms.has("home") and Templates.thumb_path(tid) != "", "saved with a thumbnail")
	check(DirAccess.dir_exists_absolute(Templates.dir().path_join(tid).path_join("tilesets/dream_meadow")), "tile sets bundled")
	var stamp := RoomOps.copy_region(home, Vector2i(0, 0), Vector2i(2, 2))
	var sid := Templates.save_stamp("Corner", stamp)
	SaveManager.new_slot("Other")  # another world in the same save root shares the Library
	StarterContent.create_world("Other", "Sam")
	GameState.load_world()
	for id in TilesetFactory.BUILTIN:
		Tilesets.delete_set(id)  # a world that lost its sets (e.g. an older save)
	check(not Tilesets.exists("dark_castle") and not Tilesets.exists("dream_meadow"), "this world has none of those sets")
	var s := Templates.stamp_for_use(sid)
	eq(int(s.w), 3)
	check(Tilesets.exists("dark_castle") or Tilesets.exists("dream_meadow"), "a stamp brings its tile sets into a fresh world")
	var other := SaveManager.load_room("home")
	check(RoomOps.paste(other, s, Vector2i(3, 3)) > 0, "stamp placed")
