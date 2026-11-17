extends "res://tests/test_case.gd"
## World Builder data operations and room management.

const RoomEditor := preload("res://scripts/world/room_editor.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const RoomView := preload("res://scripts/world/room_view.gd")


func test_stacking_and_height_limit() -> void:
	var r := Defaults.room("r", "R")
	var a := RoomEditor.add_tile(r, 2, 2, "cube", "#fff")
	eq(a.y, 0.0)
	var b := RoomEditor.add_tile(r, 2, 2, "slab", "#fff")
	eq(b.y, 1.0, "slab sits on the cube")
	var c := RoomEditor.add_tile(r, 2, 2, "cube", "#fff")
	eq(c.y, 1.5, "cube sits on the slab")
	eq(RoomEditor.stack_top(r, 2, 2), 2.5)
	RoomEditor.add_tile(r, 2, 2, "pillar", "#fff")
	RoomEditor.add_tile(r, 2, 2, "cube", "#fff")
	check(RoomEditor.add_tile(r, 2, 2, "cube", "#fff").is_empty(), "can't exceed max height")
	check(RoomEditor.add_tile(r, 99, 2, "cube", "#fff").is_empty(), "out of bounds refused")


func test_remove_top_tile() -> void:
	var r := Defaults.room("r", "R")
	RoomEditor.add_tile(r, 1, 1, "cube", "#111")
	RoomEditor.add_tile(r, 1, 1, "cube", "#222")
	check(RoomEditor.remove_top_tile(r, 1, 1))
	eq(r.tiles.size(), 1)
	eq(r.tiles[0].color, "#111", "the top one went, the bottom one stayed")
	check(RoomEditor.remove_top_tile(r, 1, 1))
	check(not RoomEditor.remove_top_tile(r, 1, 1), "nothing left")


func test_objects_ids_and_blocking() -> void:
	var r := Defaults.room("r", "R")
	var s1 := RoomEditor.add_object(r, 3, 3, "sign")
	var s2 := RoomEditor.add_object(r, 4, 3, "sign")
	eq(s1.id, "sign_1")
	eq(s2.id, "sign_2")
	check(RoomEditor.add_object(r, 3, 3, "prop").is_empty(), "one object per cell")
	check(RoomEditor.add_tile(r, 3, 3, "cube", "#fff").is_empty(), "no tiles on top of objects")
	RoomEditor.add_tile(r, 5, 5, "cube", "#fff")
	eq(RoomEditor.add_object(r, 5, 5, "sign").pos[1], 1.0, "signs can sit on blocks")
	check(RoomEditor.remove_object(r, "sign_1"))
	eq(r.objects.size(), 2)


func test_paint_and_resize() -> void:
	var r := Defaults.room("r", "R")
	RoomEditor.paint_surface(r, "floor", "#123456", "textures/wood.png")
	eq(r.floor.texture, "textures/wood.png")
	RoomEditor.add_tile(r, 11, 9, "cube", "#fff")
	RoomEditor.add_object(r, 10, 9, "sign")
	RoomEditor.add_tile(r, 1, 1, "cube", "#fff")
	RoomEditor.resize(r, 6, 6)
	eq(r.tiles.size(), 1, "out-of-bounds tiles dropped")
	eq(r.objects.size(), 0, "out-of-bounds objects dropped")
	check(int(r.spawn[0]) < 6 and int(r.spawn[1]) < 6, "spawn kept inside")


func test_walkability_follows_pieces() -> void:
	var r := Defaults.room("r", "R")
	RoomEditor.add_tile(r, 2, 2, "cube", "#fff")
	RoomEditor.add_tile(r, 3, 2, "slab", "#fff")
	RoomEditor.add_object(r, 4, 2, "sign")
	RoomEditor.add_object(r, 5, 2, "door")
	var view := RoomView.new()
	tree.root.add_child(view)
	view.build(r)
	check(not view.nav.walkable(Vector2i(2, 2)), "cube blocks")
	check(view.nav.walkable(Vector2i(3, 2)), "slab is walkable")
	check(not view.nav.walkable(Vector2i(4, 2)), "sign blocks")
	check(view.nav.walkable(Vector2i(5, 2)), "doors are walk-in")
	view.queue_free()


func test_room_management_and_door_linking() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	var cafe := RoomEditor.create_room("Cozy Cafe", 8, 8)
	eq(cafe, "cozy_cafe")
	eq(SaveManager.load_room(cafe).size.w, 8)
	RoomEditor.rename_room(cafe, "Moon Cafe")
	eq(SaveManager.load_room(cafe).name, "Moon Cafe")
	var home := SaveManager.load_room("home")
	var door := RoomEditor.add_object(home, 6, 0, "door")
	SaveManager.save_room(home)
	RoomEditor.link_door("home", door.id, cafe)
	var linked := SaveManager.load_room("home")
	var d: Dictionary = {}
	for o in linked.objects:
		if o.id == door.id:
			d = o
	eq(d.door_target, cafe, "door points at the cafe")
	var back := SaveManager.load_room(cafe)
	var has_back := false
	for o in back.objects:
		if o.type == "door" and o.door_target == "home":
			has_back = true
	check(has_back, "a door back home was created automatically")
	RoomEditor.link_door("home", door.id, cafe)
	var doors_back: int = back.objects.filter(func(o): return o.type == "door").size()
	eq(SaveManager.load_room(cafe).objects.filter(func(o): return o.type == "door").size(), doors_back, "no duplicate return doors")
	var copy := RoomEditor.duplicate_room(cafe)
	check(copy in SaveManager.list_rooms(), "duplicated")
	eq(SaveManager.load_room(copy).name, "Moon Cafe (copy)")
	# Move Mochi to the cafe, then delete it: Mochi goes home, the door unlinks.
	var mochi := GameState.get_character("mochi")
	mochi.home_room = cafe
	GameState.save_character(mochi)
	check(RoomEditor.delete_room(cafe), "deleted")
	check(not cafe in SaveManager.list_rooms())
	eq(GameState.get_character("mochi").home_room, "home", "resident rehomed")
	for o in SaveManager.load_room("home").objects:
		check(str(o.door_target) != cafe, "no door points at a deleted room")
	for id in SaveManager.list_rooms():
		if id != "home":
			RoomEditor.delete_room(id)
	check(not RoomEditor.delete_room("home"), "the last room can't be deleted")


func test_paint_and_rotate_pieces() -> void:
	var r := Defaults.room("r", "R")
	RoomEditor.add_tile(r, 1, 1, "cube", "#111111")
	RoomEditor.add_tile(r, 1, 1, "ramp", "#222222")
	check(RoomEditor.paint_piece_at(r, 1, 1, "#ff0000"), "painted")
	eq(r.tiles[1].color, "#ff0000", "top tile painted")
	eq(r.tiles[0].color, "#111111", "lower tile untouched")
	check(not RoomEditor.paint_piece_at(r, 5, 5, "#ff0000"), "empty cell: nothing to paint")
	RoomEditor.add_object(r, 3, 3, "sign")
	RoomEditor.paint_piece_at(r, 3, 3, "#00ff00", "textures/wood.png")
	eq(r.objects[0].texture, "textures/wood.png", "objects can be painted too")
	check(RoomEditor.rotate_tiles_at(r, 1, 1), "rotated")
	eq(int(r.tiles[1].rot), 1)
	check(not RoomEditor.rotate_tiles_at(r, 6, 6), "nothing to rotate")


func test_undo_stack() -> void:
	var u := preload("res://scripts/core/undo_stack.gd").new(3)
	check(not u.can_undo())
	for i in 5:
		u.push(i)
	eq(u.size(), 3, "keeps only the newest 3")
	eq(u.undo(5), 4)
	eq(u.redo(4), 5, "redo returns what undo replaced")
	u.push(9)
	check(not u.can_redo(), "a new change clears redo")
	u.drop_last()
	eq(u.undo(0), 4)
