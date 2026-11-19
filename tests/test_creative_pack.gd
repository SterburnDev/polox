extends "res://tests/test_case.gd"

const StarterContent := preload("res://scripts/core/starter_content.gd")
const Templates := preload("res://scripts/world/templates.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const RoomView := preload("res://scripts/world/room_view.gd")


func test_new_templates_bundle_their_tiles_and_have_walkable_spawns() -> void:
	fresh_save_root()
	StarterContent.create_world("Creative pack", "Sam")
	TemplateFactory.ensure_builtin()
	for id in ["seaside_pier", "tea_room", "glasshouse", "reading_nook"]:
		var made := Templates.new_level(id)
		eq(made.size(), 1, "%s makes a room" % id)
		var room := SaveManager.load_room(made[0])
		for ref in TileLayers.tiles_used(room):
			check(Tilesets.tile_path(str(ref[0]), str(ref[1])) != "", "%s: every tile reference resolves" % id)
		var view := RoomView.new()
		tree.root.add_child(view)
		view.build(room)
		var spawn := Vector2i(int(room.spawn[0]), int(room.spawn[1]))
		check(view.nav.walkable(spawn), "%s: spawn is clear" % id)
		check(not view.nav.path(spawn, Vector2i(6, 6)).is_empty(), "%s: you can walk into the room" % id)
		if id == "seaside_pier":
			check(not view.nav.walkable(Vector2i(1, 1)), "water blocks walking")
			check(not view.nav.path(spawn, Vector2i(7, 1)).is_empty(), "the pier reaches the bench")
		view.queue_free()
		await frames(1)


func test_new_furniture_is_modelled_and_restricted_to_its_setting() -> void:
	fresh_save_root()
	var decor: Script = load("res://scripts/world/decor_editor.gd")
	for model in ["floor_cushion", "record_player", "shoe_rack", "birdbath"]:
		var object := Furniture.make(model, 2, 3)
		var node := Furniture.build(object)
		check(node.get_node("Model").get_child_count() >= 2, "%s has its own geometry" % model)
		check(float(node.get_meta("top")) > 0.0, "clickable height")
		eq(Furniture.cells(object), [Vector2i(2, 3)], "one-cell footprint")
		check(model in (decor.OUTSIDE if model == "birdbath" else decor.INSIDE), "in the appropriate catalog")
		check(not model in (decor.INSIDE if model == "birdbath" else decor.OUTSIDE), "kept out of the other catalog")
		node.free()
	# 1.27.6's pieces, modelled in Blender: in the indoor catalogue, with a line when used.
	var LightLife: Script = load("res://scripts/world/light_life.gd")
	for model in ["bean_bag", "fish_tank", "coat_rack", "bar_stool", "wall_clock"]:
		check(Furniture.exists(model) and model in decor.INSIDE and not model in decor.OUTSIDE, model + " is in the indoor catalogue")
		check(LightLife.LINES.has(model), model + " says something when used")
		var node := Furniture.build(Furniture.make(model, 2, 3))
		check(float(node.get_meta("top")) > 0.0, model + ": clickable height")
		node.free()
	check(not Furniture.blocks("wall_clock"), "the wall clock hangs on the wall: you can walk under it")
