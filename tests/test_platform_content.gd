extends "res://tests/test_case.gd"
## Phase 17 content: the two courses (every step within a jump, or the pad /
## the moving platform covers it; a pillar, a checkpoint and shards in each),
## the Tile Playground's pillar (new worlds, and added to old ones by the v4
## upgrade after a snapshot), slippery cells, the Jump reach overlay, and the
## animation tools (strip slicing, Generate, saving and loading frames, the
## doll maker's built-in run cycle, the Animations tab).

const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const PlatformWorld := preload("res://scripts/platform/platform_world.gd")
const JumpReach := preload("res://scripts/platform/jump_reach.gd")
const Config := preload("res://scripts/platform/platform_config.gd")
const AnimBake := preload("res://scripts/characters/anim_bake.gd")
const AnimStore := preload("res://scripts/characters/anim_store.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const WorldMigration := preload("res://scripts/core/world_migration.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Doll := preload("res://scripts/characters/doll.gd")
const AnimTab := preload("res://scripts/ui/creator_anim_tab.gd")


func _has(r: Dictionary, type: String) -> int:
	return r.get("objects", []).filter(func(o): return str(o.get("type", "")) == type).size()


func _reach(r: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	return JumpReach.reachable(r, a).any(func(e): return e[0] == b)


func test_courses_are_complete_and_jumpable() -> void:
	fresh_save_root()
	StarterContent.create_world("C", "Sam")
	var steps := TemplateFactory.sky_steps("sky_steps", "Sky Steps")
	for t in ["platform_pillar", "checkpoint", "jump_pad", "mover", "shard"]:
		check(_has(steps, t) >= 1, "Sky Steps has a %s" % t)
	eq(_has(steps, "shard"), 2, "two Memory Shards")
	# The route: start (floor) -> 5 (1 up) -> 7 (2) -> 9/10 (2) -> pad on 10 -> 12/13 (4) -> mover -> 17 (4).
	check(_reach(steps, Vector2i(3, 5), Vector2i(5, 5)), "start -> first step (1 up)")
	check(_reach(steps, Vector2i(5, 5), Vector2i(7, 5)), "-> second step (1 up)")
	check(_reach(steps, Vector2i(7, 5), Vector2i(9, 5)), "-> the checkpoint step (same height)")
	eq(PlatformWorld.top_at(steps, 12, 5) - PlatformWorld.top_at(steps, 10, 5), 2.0, "the gold deck is 2 up: too high for a jump...")
	var pad := Config.JUMP_PAD_STRENGTH
	check(pad * pad / (2.0 * Config.GRAVITY) > 2.2, "...but the jump pad throws you %.1f blocks" % (pad * pad / (2.0 * Config.GRAVITY)))
	var mover: Dictionary = steps.objects.filter(func(o): return str(o.type) == "mover")[0]
	var mover_end := Vector2i(int(mover.pos[0]) + int(mover.dx), int(mover.pos[2]) + int(mover.dz))
	check(Vector2(mover_end - Vector2i(17, 5)).length() <= Config.jump_reach().y, "the moving platform carries you within a jump of the end deck")
	var moon := TemplateFactory.moon_ledges("moon_ledges", "Moon Ledges")
	for t in ["platform_pillar", "checkpoint", "one_way", "mover", "shard", "jump_pad"]:
		check(_has(moon, t) >= 1, "Moon Ledges has a %s" % t)
	var ledges: Array = moon.objects.filter(func(o): return str(o.type) == "one_way")
	ledges.sort_custom(func(a, b): return int(a.elev) < int(b.elev))
	var ok := true
	for i in range(1, ledges.size()):
		var a: Dictionary = ledges[i - 1]
		var b: Dictionary = ledges[i]
		var rise := int(b.elev) - int(a.elev)
		var gap := Vector2(float(b.pos[0]) - float(a.pos[0]), float(b.pos[2]) - float(a.pos[2])).length()
		if rise > 1 or gap > Config.jump_reach().y:
			ok = false
	check(ok, "every ledge is at most 1 up and within a running jump of the one before")
	# Built and run through Platform Mode's builder: colliders and the slippery strip.
	var pw: Node3D = PlatformWorld.new()
	tree.root.add_child(pw)
	pw.build(moon)
	check(pw.is_slippery(Vector2i(5, 11)) and not pw.is_slippery(Vector2i(5, 9)), "the moon dust strip is slippery")
	check(pw.one_ways.size() == ledges.size() and pw.movers.size() == 1, "ledges and the drifting platform are built")
	pw.queue_free()
	await frames(1)


func test_tile_playground_pillar_new_and_old_worlds() -> void:
	fresh_save_root()
	StarterContent.create_world("P", "Sam")
	StarterContent.create_blank("P2")
	var pg := ""
	for id in SaveManager.list_rooms():
		if str(id).begins_with("tile_playground"):
			pg = id
	check(pg != "", "new worlds include the Tile Playground")
	check(_has(SaveManager.load_room(pg), "platform_pillar") == 1, "with a Platform Pillar")
	# An old (v3) world whose playground has no pillar: the upgrade adds one after a snapshot.
	var room := SaveManager.load_room(pg)
	room["objects"] = room.objects.filter(func(o): return str(o.type) != "platform_pillar")
	SaveManager.save_room(room)
	var raw: Dictionary = JsonUtil.read_json(SaveManager.world_path(), {})
	raw["version"] = 3
	JsonUtil.write_json(SaveManager.world_path(), raw)
	var r: Dictionary = WorldMigration.run()
	check(bool(r.get("migrated", false)) and str(r.get("snapshot", "")) != "", "upgraded (through v4) with a snapshot first")
	eq(_has(SaveManager.load_room(pg), "platform_pillar"), 1, "the old playground got its pillar")
	eq(int(SaveManager.load_world().version), preload("res://scripts/core/defaults.gd").WORLD_VERSION, "and on to the current version")


func test_jump_reach_overlay() -> void:
	var r := {"size": {"w": 12, "d": 12, "h": 3}, "tiles": [{"x": 6, "z": 6, "y": 0, "type": "cube"}, {"x": 7, "z": 6, "y": 0, "type": "cube"}, {"x": 7, "z": 6, "y": 1, "type": "cube"}], "objects": [], "tile_layers": preload("res://scripts/world/tile_layers.gd").default_layers()}
	var cells := JumpReach.reachable(r, Vector2i(5, 6))
	check(cells.any(func(e): return e[0] == Vector2i(6, 6) and str(e[2]) == "up"), "one block up is reachable")
	check(not cells.any(func(e): return e[0] == Vector2i(7, 6)), "two blocks up isn't")
	check(cells.any(func(e): return e[0] == Vector2i(9, 6)), "four across at the same height is")
	check(not cells.any(func(e): return e[0] == Vector2i(11, 6)), "six across isn't")
	var from_top := JumpReach.reachable(r, Vector2i(6, 6))
	check(from_top.any(func(e): return e[0] == Vector2i(7, 6)), "from the block, the next one up is")
	check(from_top.any(func(e): return e[0] == Vector2i(4, 6) and str(e[2]) == "down"), "and the floor is 'down'")
	var overlay: MeshInstance3D = JumpReach.new()
	tree.root.add_child(overlay)
	overlay.show_from(r, Vector2i(5, 6))
	check(overlay.mesh != null and overlay.cells.size() == cells.size(), "the overlay draws them")
	overlay.queue_free()
	await frames(1)


func test_animation_tools() -> void:
	fresh_save_root()
	StarterContent.create_world("A", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	var base := Doll.compose(Doll.preset("cozy"))
	# Generated frames read differently per state.
	var run := AnimBake.frames_for("run", base)
	var walk := AnimBake.frames_for("walk", base)
	eq(run.size(), 4, "run: 4 frames")
	check((run[0] as Image).get_data() != base.get_data(), "the run frames differ from the base picture (lean, stride)")
	check((run[0] as Image).get_data() != (walk[0] as Image).get_data(), "running doesn't look like walking")
	var jump: Image = AnimBake.frames_for("jump", base)[0]
	var land: Image = AnimBake.frames_for("land", base)[0]
	check(_top_row(jump) < _top_row(base) and _top_row(land) > _top_row(base), "jump stretches up, landing squashes down")
	eq(AnimBake.doll_run(base).size(), 4, "the doll maker's built-in run cycle")
	# A sprite strip is cut into square frames.
	var strip := Image.create(96, 32, false, Image.FORMAT_RGBA8)
	for i in 3:
		strip.fill_rect(Rect2i(i * 32 + 8, 8, 16, 16), Color.from_hsv(i / 3.0, 0.8, 0.9))
	eq(AnimStore.slice_strip(strip).size(), 3, "a strip of 3 becomes 3 frames")
	# Save and load a character's frames.
	var mochi: String = GameState.characters.keys()[0] if GameState.get("characters") is Dictionary else "mochi"
	var target := {"kind": "character", "id": mochi}
	AnimStore.save_state(target, "run", run, 12.0, true)
	var back := AnimStore.images(target, "run")
	eq(back.size(), 4, "saved and loaded back")
	check((back[1] as Image).get_data() == (run[1] as Image).get_data(), "byte for byte")
	eq(float(AnimStore.settings_of(target, "run").fps), 12.0)
	check(FileAccess.file_exists(SaveManager.abs_path("characters/%s/anims/run_0.png" % mochi)), "in the character's folder (travels with the world)")
	AnimStore.save_state(target, "run", [], 8.0, true)
	check(AnimStore.images(target, "run").is_empty() and not FileAccess.file_exists(SaveManager.abs_path("characters/%s/anims/run_0.png" % mochi)), "removing frames cleans up")
	# The Animations tab: generate, add a copy, save.
	var tab: ScrollContainer = AnimTab.new()
	tab.build(target, func(): return base)
	tree.root.add_child(tab)
	await frames(2)
	tab.select_state("jump")
	tab.generate()
	eq(tab.frames.size(), 1, "Generate makes the jump frame")
	tab.copy_previous()
	eq(tab.frames.size(), 2, "Copy previous adds one to change")
	tab.import_strip_image(strip)
	eq(tab.frames.size(), 3, "importing a strip replaces them with its frames")
	tab.save_state()
	eq(AnimStore.images(target, "jump").size(), 3, "Save writes them")
	tab.queue_free()
	await frames(1)


func _top_row(img: Image) -> int:
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				return y
	return img.get_height()
