extends "res://tests/test_case.gd"
## 1.26.0, more to build with (the rest of Update 8's list, drafted then and ported now): seven tile sets
## (an everyday home, town streets, a snowy village, a farm, a crystal cave, an old library, candy land: 58
## tiles, three of them animated) and eight templates (kitchen, bathroom, town street, snowy village, farm,
## crystal cave, old library, candy land). Every tile is drawn the same way on every device; every template
## bundles its tiles, resolves every tile, starts you somewhere clear and lets you walk in; water and walls
## block where they should.

const StarterContent := preload("res://scripts/core/starter_content.gd")
const Templates := preload("res://scripts/world/templates.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const TilesetFactory := preload("res://scripts/world/tileset_factory.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const RoomView := preload("res://scripts/world/room_view.gd")

const NEW_SETS := {"everyday_home": 8, "streets": 10, "snow": 8, "farm": 8, "crystal_cave": 8, "library": 8, "candy": 8}
const NEW_TEMPLATES := ["kitchen", "bathroom", "town_street", "snowy_village", "farm", "crystal_cave", "old_library", "candy_land"]


func test_seven_new_tile_sets() -> void:
	fresh_save_root()
	TilesetFactory.ensure_builtin()
	var total := 0
	var animated := 0
	for id in NEW_SETS:
		check(id in TilesetFactory.BUILTIN, "%s is built in" % id)
		var s := Tilesets.load_set(id, true)
		check(not s.is_empty(), "%s is in the Library" % id)
		var tiles: Array = s.get("tiles", [])
		eq(tiles.size(), int(NEW_SETS[id]), "%s has its tiles" % id)
		for t in tiles:
			var path := Tilesets.set_dir(id, true).path_join(str(t.get("image", "")))
			var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
			if check(img != null and img.get_width() == 32 and img.get_height() == 32, "%s/%s is a 32 px picture" % [id, t.id]):
				check(not img.is_invisible(), "%s/%s isn't empty" % [id, t.id])
			if (t.get("frames", []) as Array).size() > 0:
				animated += 1
			total += 1
	eq(total, 58, "58 new tiles")
	eq(animated, 3, "three of them animated (crystal, glow mushroom, cave pool)")
	# Drawn the same everywhere (seeded): the same set made twice gives the same pictures.
	var wheat := func() -> String:
		for t in Tilesets.load_set("farm", true).tiles:
			if str(t.id) == "wheat":
				return FileAccess.get_sha256(Tilesets.set_dir("farm", true).path_join(str(t.image)))
		return ""
	var first: String = wheat.call()
	TilesetFactory.make("farm")
	check(first != "" and wheat.call() == first, "the same picture every time")
	var snow := Tilesets.load_set("snow", true)
	for t in snow.tiles:
		if str(t.id) == "pine":
			check(bool(t.get("solid", false)), "a pine tree is solid")
	var cave := Tilesets.load_set("crystal_cave", true)
	for t in cave.tiles:
		if str(t.id) == "cave_pool":
			check(not bool(t.get("walkable", true)), "the cave pool can't be walked on")


func test_eight_new_templates() -> void:
	fresh_save_root()
	StarterContent.create_world("More to create", "Sam")
	TemplateFactory.ensure_builtin()
	for id in NEW_TEMPLATES:
		check(id in TemplateFactory.BUILTIN and id in Templates.ids(), "%s is a built-in template" % id)
		check(Templates.thumb_path(id) != "", "%s has a picture in the gallery" % id)
		var made := Templates.new_level(id)
		if not check(made.size() == 1, "%s makes a place" % id):
			continue
		var room := SaveManager.load_room(made[0])
		var refs := TileLayers.tiles_used(room)
		check(not refs.is_empty(), "%s is made of tiles" % id)
		for ref in refs:
			check(Tilesets.tile_path(str(ref[0]), str(ref[1])) != "", "%s: %s/%s resolves in this world" % [id, ref[0], ref[1]])
		var view := RoomView.new()
		tree.root.add_child(view)
		view.build(room)
		var spawn := Vector2i(int(room.spawn[0]), int(room.spawn[1]))
		check(view.nav.walkable(spawn), "%s: the spawn is clear" % id)
		var reach := 0
		for z in int(room.size.d):
			for x in int(room.size.w):
				if view.nav.walkable(Vector2i(x, z)) and not view.nav.path(spawn, Vector2i(x, z)).is_empty():
					reach += 1
		check(reach >= 12, "%s: room to walk around (%d cells)" % [id, reach])
		if id == "crystal_cave":
			check(not view.nav.walkable(Vector2i(9, 7)), "the cave pool blocks walking")
		if id in ["town_street", "snowy_village", "farm", "candy_land"]:
			check(not bool(room.get("walls", {}).get("north", true)), "%s is outdoors" % id)
		view.queue_free()
		await frames(1)
