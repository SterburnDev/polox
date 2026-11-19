extends "res://tests/test_case.gd"
## Phase 24, places instead of rooms: kinds (indoor, outdoor, abstract) with optional walls,
## sky and silhouette backgrounds, places joined at their edges (walk off one edge, arrive at
## the matching spot of the next; the ground carries on across the join), "Add a place to the
## east", the World Map laid out by joins, old rooms upgraded without losing anything, the
## higher Platform camera (Low / Classic / High) keeping the player and the next ledge in view,
## and moving between places animated, skippable, and a short fade with Reduce motion.

const Places := preload("res://scripts/world/places.gd")
const PlaceBackdrop := preload("res://scripts/world/place_backdrop.gd")
const SilhouettePainter := preload("res://scripts/world/silhouette_painter.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const WorldMigration := preload("res://scripts/core/world_migration.gd")
const CameraRig := preload("res://scripts/world/camera_rig.gd")
const Moment := preload("res://scripts/ui/moment.gd")

var main: Node


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _shutdown() -> void:
	GameState.settings["reduce_motion"] = false
	GameState.settings.erase("platform_camera")
	main.queue_free()
	await frames(2)


func test_kinds_walls_and_backgrounds() -> void:
	var indoor := Places.make_place("a", "A", "indoor")
	var outdoor := Places.make_place("b", "B", "outdoor")
	var odd := Places.make_place("c", "C", "abstract")
	eq(Places.walls(indoor).values(), [true, true, true, true], "indoors: four walls")
	eq(Places.walls(outdoor).values(), [false, false, false, false], "outdoors: open")
	check(bool(Places.background(outdoor).ground), "the ground goes on outdoors")
	check(not bool(Places.background(odd).ground), "somewhere strange floats")
	eq(str(Places.background(outdoor).sky), "auto", "an outdoor sky follows the time of day")
	eq((Places.background(outdoor).layers as Array).size(), 2, "hills and trees")
	# Junk in the file never breaks a place.
	var junk := Defaults.room("x", "X")
	junk["kind"] = "spaceship"
	junk["background"] = {"sky": "plaid", "layers": [{"kind": "volcano"}, {"kind": "city", "distance": 9}, 3, {"kind": "stars"}, {"kind": "hills"}, {"kind": "trees"}]}
	eq(Places.kind(junk), "indoor")
	eq(str(Places.background(junk).sky), "room")
	var ls: Array = Places.background(junk).layers
	eq(ls.size(), 3, "at most three layers, unknown kinds dropped")
	eq(int(ls[0].distance), 3, "distance clamped")
	# The painter: same input, same picture; transparent sky above the silhouette.
	var a := SilhouettePainter.paint("hills", Color("#4f7a5c"), 1)
	var b := SilhouettePainter.paint("hills", Color("#4f7a5c"), 1)
	eq(a.get_data(), b.get_data(), "the same every visit")
	check(a.get_pixel(10, 2).a < 0.1 and a.get_pixel(10, SilhouettePainter.H - 2).a > 0.9, "sky above, hill below")
	for k in Places.SILHOUETTES:
		check(not SilhouettePainter.paint(k, Color.WHITE, 3).is_invisible(), k + " draws something")


func test_old_rooms_become_places_without_losing_anything() -> void:
	fresh_save_root()
	StarterContent.create_world("Old World", "Sam")
	GameState.load_world()
	var before := {}
	for id in SaveManager.list_rooms():
		var r := SaveManager.load_room(id)
		for k in ["kind", "walls", "background", "edges"]:
			r.erase(k)
		SaveManager.save_room(r)
		before[id] = JSON.stringify(r)
	var raw: Dictionary = JsonUtil.read_json(SaveManager.world_path(), {})
	raw["version"] = 4
	JsonUtil.write_json(SaveManager.world_path(), raw)
	var res := WorldMigration.run()
	check(bool(res.get("migrated", false)), "upgraded")
	eq(int(res.get("from", 0)), 4)
	check(str(res.get("snapshot", "")) != "", "a snapshot first")
	for id in before:
		var r := SaveManager.load_room(id)
		var old: Dictionary = JSON.parse_string(before[id])
		for k in old:
			if k == "version":
				continue
			eq(JSON.stringify(JSON.parse_string(JSON.stringify(r.get(k)))), JSON.stringify(old[k]), "%s: %s unchanged" % [id, k])
	# Then v7: they stop looking like boxes in a void (1.13.3).
	var home := SaveManager.load_room("home")
	eq(Places.kind(home), "indoor", "home stays indoors")
	eq(Places.walls(home).values(), [true, true, true, true], "with its walls")
	check(bool(Places.background(home).ground) and str(Places.background(home).sky) == "auto", "but sits in the world: ground and sky")
	for id in ["garden", "tile_playground"]:
		var r := SaveManager.load_room(id)
		eq(Places.kind(r), "outdoor", id + ": outdoors")
		eq(Places.walls(r).values(), [false, false, false, false], id + ": no walls")
	eq(Places.edge(SaveManager.load_room("garden"), "east"), "tile_playground", "the garden and the playground are joined")
	eq(int(JsonUtil.read_json(SaveManager.world_path(), {}).get("version", 0)), Defaults.WORLD_VERSION)


func test_rooms_from_before_open_up_and_changed_places_stay() -> void:
	fresh_save_root()
	StarterContent.create_world("Kept World", "Sam")
	GameState.load_world()
	# Exactly what the v5 upgrade left: indoors, four walls, the old plain backdrop, no joins.
	for id in SaveManager.list_rooms():
		var r := SaveManager.load_room(id)
		r["kind"] = "indoor"
		r["walls"] = Places.default_walls("indoor")
		r["background"] = Places.OLD_ROOM_LOOK.duplicate(true)
		r["edges"] = {}
		SaveManager.save_room(r)
	var mine := Places.make_place("study", "My Study", "indoor")
	mine["background"] = {"sky": "night", "ground": false, "ground_color": "", "layers": []}   # changed in Build mode
	SaveManager.save_room(mine)
	var patio := Places.make_place("patio_2", "Night Patio", "indoor")
	patio["background"] = {"sky": "night", "ground": true, "ground_color": "", "layers": []}   # an outdoorsy name, but changed by hand
	SaveManager.save_room(patio)
	var raw: Dictionary = JsonUtil.read_json(SaveManager.world_path(), {})
	raw["version"] = 6
	JsonUtil.write_json(SaveManager.world_path(), raw)
	var res := WorldMigration.run()
	check(bool(res.get("migrated", false)) and str(res.get("snapshot", "")) != "", "upgraded, after a snapshot")
	eq(Places.kind(SaveManager.load_room("garden")), "outdoor", "Garden: outdoors")
	eq(Places.kind(SaveManager.load_room("tile_playground")), "outdoor", "Tile Playground: outdoors")
	eq(Places.edge(SaveManager.load_room("tile_playground"), "west"), "garden", "joined both ways")
	var home := SaveManager.load_room("home")
	check(Places.kind(home) == "indoor" and bool(Places.background(home).ground), "Home: indoors, in the world")
	eq(str(Places.background(SaveManager.load_room("study")).sky), "night", "a place changed in Build mode stays as it was")
	eq(Places.kind(SaveManager.load_room("patio_2")), "indoor", "even with an outdoorsy name")


func test_new_worlds_start_as_one_world() -> void:
	fresh_save_root()
	StarterContent.create_world("New World", "Sam")
	var home := SaveManager.load_room("home")
	var garden := SaveManager.load_room("garden")
	check(Places.kind(home) == "indoor" and bool(Places.background(home).ground) and str(Places.background(home).sky) != "room", "home sits in the world")
	eq(Places.kind(garden), "outdoor", "the garden is outdoors")
	eq(Places.edge(garden, "east"), "tile_playground", "and joined to the playground")
	eq(Places.kind(Places.make_place("x", "Kitchen", "indoor")), "indoor")
	check(bool(Places.background(Places.make_place("x", "Kitchen", "indoor")).ground), "a new indoor place sits in the world too")


func test_add_a_place_beside_and_join_both_ways() -> void:
	var home := Places.make_place("meadow", "Meadow", "outdoor")
	home["size"] = {"w": 14, "d": 9, "h": 3}
	var east := Places.add_beside(home, "east", PackedStringArray(["meadow"]))
	check(not east.is_empty())
	eq(Places.edge(home, "east"), str(east.id), "east leads there")
	eq(Places.edge(east, "west"), "meadow", "and west leads back")
	eq(Places.kind(east), "outdoor", "the same kind")
	eq(JSON.stringify(east.size), JSON.stringify(home.size), "the same size, so the join lines up")
	eq(JSON.stringify(Places.background(east)), JSON.stringify(Places.background(home)), "the same background carries on")
	check(not Places.has_wall(home, "east") and not Places.has_wall(east, "west"), "no wall across a join")
	eq(int(east.spawn[0]), 1, "you arrive by the join")
	eq(Places.add_beside(home, "east", PackedStringArray(["meadow", str(east.id)])), {}, "one place per side")
	var north := Places.add_beside(home, "north", PackedStringArray(["meadow", str(east.id)]))
	check(str(north.id) != str(east.id), "ids stay unique")
	# Crossing: same spot along the edge, scaled when sizes differ.
	eq(Places.arrival(home, "east", Vector2i(13, 4), east), Vector2i(0, 4))
	var big := Places.make_place("big", "Big", "outdoor")
	big["size"] = {"w": 20, "d": 17, "h": 3}
	eq(Places.arrival(home, "east", Vector2i(13, 8), big), Vector2i(0, 16), "the far corner maps to the far corner")
	eq(Places.arrival(home, "north", Vector2i(7, 0), big), Vector2i(10, 16))
	eq(Places.side_of(home, Vector2i(13, 3)), "east")
	eq(Places.side_of(home, Vector2i(5, 5)), "")


func test_the_world_map_follows_the_joins() -> void:
	var a := Places.make_place("a", "A", "outdoor")
	var b := Places.make_place("b", "B", "outdoor")
	var c := Places.make_place("c", "C", "outdoor")
	var d := Places.make_place("d", "D", "indoor")   # only a door: not part of the land
	Places.link(a, "east", b)
	Places.link(b, "south", c)
	var pos := Places.map_layout({"a": a, "b": b, "c": c, "d": d}, "a")
	eq(pos.a, Vector2i(0, 0))
	eq(pos.b, Vector2i(1, 0), "east is to the right")
	eq(pos.c, Vector2i(1, 1), "south is below")
	check((pos.d as Vector2i).x >= 3, "a place joined only by doors sits apart")
	var w := Places.make_place("w", "W", "outdoor")
	Places.link(w, "east", a)
	pos = Places.map_layout({"a": a, "b": b, "w": w}, "a")
	eq(pos.w, Vector2i(0, 0), "shifted so nothing is negative")
	eq(pos.a, Vector2i(1, 0))


func test_places_in_the_game_walls_ground_and_joins() -> void:
	var g: Node = await _boot()
	var here := str(GameState.current_room_id)
	var data: Dictionary = g.room.data
	data["kind"] = "outdoor"
	data["walls"] = Places.default_walls("outdoor")
	data["background"] = Places.default_background("outdoor")
	var east := Places.add_beside(data, "east", SaveManager.list_rooms(), "Orchard")
	SaveManager.save_room(east)
	SaveManager.save_room(data)
	g.load_room(here)
	await frames(2)
	eq(g.room.wall_count(), 0, "an outdoor place has no walls")
	check(g.backdrop.has_ground, "the ground goes on")
	eq(g.backdrop.layers_built, 2, "two silhouette layers")
	eq(g.backdrop.strips_built, ["east"], "beyond the join: the orchard's ground")
	check(g.env.sky != null, "a sky that follows the time of day")
	# Walk off the east edge -> the orchard's west edge, same row.
	var row := 3
	g.player.position = g.room.cell_center(Vector2i(g.room.w - 1, row))
	GameState.settings["reduce_motion"] = true
	await g.cross_edge("east", Vector2i(g.room.w - 1, row))
	eq(GameState.current_room_id, str(east.id), "in the orchard")
	eq(g.player.cell(), Places.arrival(data, "east", Vector2i(g.room.w - 1, row), east) if g.room.nav.walkable(Vector2i(0, row)) else g.player.cell(), "at the matching spot")
	eq(g.player.cell().x, 0, "on the west edge")
	eq(g.backdrop.strips_built, ["west"], "and the meadow's ground is behind you")
	# And back again by clicking past the edge (the strip is clickable).
	var strip: Node = g.backdrop.get_node_or_null("EdgeHit_west")
	check(strip != null, "the ground beyond a join can be clicked")
	await _shutdown()


func test_moving_between_places_is_animated_skippable_and_reducible() -> void:
	var g: Node = await _boot()
	var here := str(GameState.current_room_id)
	var data: Dictionary = g.room.data
	var east := Places.add_beside(data, "east", SaveManager.list_rooms(), "Orchard")
	SaveManager.save_room(east)
	SaveManager.save_room(data)
	g.load_room(here)
	await frames(2)
	GameState.settings["reduce_motion"] = false
	var t0 := Time.get_ticks_msec()
	await g.cross_edge("east", Vector2i(g.room.w - 1, 2))
	var full := Time.get_ticks_msec() - t0
	check(full >= 500, "an animation, not a cut (%d ms)" % full)
	eq(GameState.current_room_id, str(east.id))
	# Skipped with a tap: over almost at once, same result.
	var job := func() -> void:
		await frames(3)
		for m in main.toast_layer().get_children():
			if m.has_method("skip"):
				m.skip()
	job.call()
	t0 = Time.get_ticks_msec()
	await g.cross_edge("west", Vector2i(0, 2))
	var skipped := Time.get_ticks_msec() - t0
	check(skipped < full * 0.6, "skipping ends it early (%d ms vs %d)" % [skipped, full])
	eq(GameState.current_room_id, here, "and still arrives")
	# Reduce motion: a short fade.
	GameState.settings["reduce_motion"] = true
	t0 = Time.get_ticks_msec()
	await g.cross_edge("east", Vector2i(g.room.w - 1, 2))
	var reduced := Time.get_ticks_msec() - t0
	check(reduced <= full - 250, "Reduce motion: a short fade (%d ms vs %d)" % [reduced, full])
	await _shutdown()


func test_the_platform_camera_is_higher_and_keeps_the_next_ledge_in_view() -> void:
	var g: Node = await _boot()
	eq(CameraRig.platform_preset(), "high", "High by default")
	check(float(CameraRig.PLATFORM_PRESETS.high[0]) >= 50.0 and float(CameraRig.PLATFORM_PRESETS.high[0]) <= 60.0, "about 50-60 degrees")
	# A ledge two blocks up, three cells ahead of the player.
	var data: Dictionary = g.room.data
	for z in range(1, 4):
		for y in 2:
			data["tiles"].append({"x": 6, "y": y, "z": z, "type": "cube", "color": "#8a7ab8"})
	g.rebuild_room()
	g.player.position = g.room.cell_center(Vector2i(6, 7))
	for preset in ["high", "classic", "low"]:
		GameState.settings["platform_camera"] = preset
		g.cam.set_follow(true)
		g.cam.follow_yaw = 0.0   # looking north, toward the ledge
		g.cam.move_hint = Vector3(0, 0, -2.0)
		for _i in 40:
			g.cam._process(0.05)
		var cam: Camera3D = g.cam.camera
		var vp := g.get_viewport().get_visible_rect().size
		var me: Vector2 = cam.unproject_position(g.player.global_position + Vector3(0, 0.6, 0))
		var ledge: Vector2 = cam.unproject_position(Vector3(6.5, 2.0, 3.5))
		check(Rect2(Vector2.ZERO, vp).has_point(me) and not cam.is_position_behind(g.player.global_position), "%s: the player is on screen %s" % [preset, me])
		check(Rect2(Vector2.ZERO, vp).has_point(ledge) and not cam.is_position_behind(Vector3(6.5, 2.0, 3.5)), "%s: the ledge ahead is on screen %s" % [preset, ledge])
		check(ledge.y < me.y, "%s: and it's above you on screen (ahead)" % preset)
		g.cam.set_follow(false)
	check(CameraRig.PLATFORM_PRESETS.high[0] > CameraRig.PLATFORM_PRESETS.classic[0], "High is higher than Classic")
	await _shutdown()


func test_places_wording_and_settings() -> void:
	var g: Node = await _boot()
	var rl: Control = preload("res://scripts/world/world_menu.gd").room_list(g)
	main.open_panel(rl)
	await frames(2)
	eq(rl.title_label.text, "Places", "the list says Places")
	check(rl.find_children("*", "OptionButton", true, false).size() >= 2, "new place: a kind and a size")
	rl.close()
	await frames(1)
	var s: Control = load("res://scripts/ui/settings_screen.gd").new()
	main.open_panel(s)
	await frames(2)
	var texts := s.find_children("*", "", true, false).filter(func(n): return n is CheckBox or n is Label).map(func(n): return str(n.text))
	check(texts.any(func(t): return t.contains("Reduce motion")), "Reduce motion is a setting")
	check(texts.any(func(t): return t.contains("Platform camera")), "and the Platform camera height")
	s.close()
	await _shutdown()


func test_build_mode_place_section_adds_a_place() -> void:
	var g: Node = await _boot()
	var here := str(GameState.current_room_id)
	g.build.enter()
	g.build.set_mode("room")
	await frames(3)
	var section: Node = g.build.shell.room_tab.place_section
	check(section != null, "the Place section is at the top of the Place tab")
	var kinds: OptionButton = section.get_child(1) if section.get_child_count() > 1 else null
	await frames(1)
	var east: Button = null
	for b in section.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("East"):
			east = b
	check(east != null and not east.disabled, "Add a place: East")
	east.pressed.emit()
	await frames(3)
	var joined := Places.edge(g.room.data, "east")
	check(joined != "" and SaveManager.room_exists(joined), "a new place, joined on the east")
	eq(Places.edge(SaveManager.load_room(joined), "west"), here, "and back")
	section.set_kind("outdoor")
	await frames(2)
	eq(Places.kind(g.room.data), "outdoor", "the kind changed")
	check(not Places.has_wall(g.room.data, "north"), "outdoors: open")
	g.build.undo()
	await frames(2)
	eq(Places.kind(g.room.data), "indoor", "Undo works for places too")
	g.build.exit()
	await _shutdown()


## 1.29 art: open ground has a seamless land texture in the ground's own colour, and a sign is a
## framed, written board that keeps its size, its collision and the player's own picture.
func test_land_texture_and_written_signs() -> void:
	var SurfaceDetail := preload("res://scripts/world/surface_detail.gd")
	var land: Texture2D = SurfaceDetail.texture("ground")
	check(land != null and land.get_width() == 64, "a land texture exists")
	var img := land.get_image()
	var brightest := 0.0
	var seam := 0.0
	for i in 64:
		brightest = maxf(brightest, img.get_pixel(i, 31).r)
		seam = maxf(seam, absf(img.get_pixel(0, i).r - img.get_pixel(63, i).r))
		seam = maxf(seam, absf(img.get_pixel(i, 0).r - img.get_pixel(i, 63).r))
	check(brightest <= 1.0 and seam < 0.16, "it never brightens the colour and its edges meet (largest step %.3f)" % seam)
	var BlockFactory := preload("res://scripts/world/block_factory.gd")
	var sign: Node3D = BlockFactory.make_object({"id": "s1", "type": "sign", "color": "#3c8dbc"})
	var faces := sign.find_children("*", "MeshInstance3D", true, false).filter(func(m): return (m as MeshInstance3D).mesh is QuadMesh)
	eq(faces.size(), 2, "a sign is written on both sides")
	var body: StaticBody3D = sign.find_children("*", "StaticBody3D", true, false)[0]
	var shape: BoxShape3D = (body.get_child(0) as CollisionShape3D).shape
	eq(shape.size, Vector3(0.9, 1.35, 0.5), "its collision is the size it always was")
	eq(str(body.get_meta("id", "")), "s1", "and it is still the same object")
	var face_mat := (faces[0] as MeshInstance3D).material_override as StandardMaterial3D
	check(face_mat.albedo_color.b > face_mat.albedo_color.r, "the face takes the sign's own colour")
	sign.free()
	var picture: Node3D = BlockFactory.make_object({"id": "s2", "type": "sign", "texture": "tiles/none.png"})
	eq(picture.find_children("*", "MeshInstance3D", true, false).filter(func(m): return (m as MeshInstance3D).mesh is QuadMesh).size(), 0, "a sign with the player's own picture is left as it was")
	picture.free()
