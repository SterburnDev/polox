extends "res://tests/test_case.gd"

const PlatformWorld := preload("res://scripts/platform/platform_world.gd")


func test_reset_in_touch_callback_invalidates_remaining_hits() -> void:
	var pw := PlatformWorld.new()
	var seen: Array = []
	pw._trigger("door", {}, Vector3(2, 1, 0), Vector3.ONE)
	pw._trigger("checkpoint", {}, Vector3(4, 1, 0), Vector3.ONE)
	pw.touched.connect(func(kind, _obj):
		seen.append(kind)
		pw.reset_triggers())
	pw.sweep_triggers(null, Vector3.ZERO, Vector3(6, 0, 0))
	eq(seen, ["door"], "a teleport invalidates hits from the old path")
	pw.free()


func test_rebuild_in_touch_callback_invalidates_old_indices() -> void:
	var pw := PlatformWorld.new()
	var seen: Array = []
	pw._trigger("door", {}, Vector3(2, 1, 0), Vector3.ONE)
	pw._trigger("checkpoint", {}, Vector3(4, 1, 0), Vector3.ONE)
	pw.touched.connect(func(kind, _obj):
		seen.append(kind)
		pw.reset_triggers()
		pw.triggers.clear())
	pw.sweep_triggers(null, Vector3.ZERO, Vector3(6, 0, 0))
	eq(seen, ["door"], "a rebuilt room cannot index the old trigger array")
	pw.free()


func test_transition_blocks_old_room_checkpoint() -> void:
	fresh_save_root()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(5)
	var g: Node = main.game
	g.platform.begin_here()
	var before: Dictionary = g.platform.checkpoint.duplicate(true)
	g._transitioning = true
	g.platform._on_touched("checkpoint", {"id": "stale_checkpoint", "type": "checkpoint", "pos": [8, 0, 4]})
	eq(g.platform.checkpoint, before, "a transition owns input and ignores old-room touches")
	g._transitioning = false
	g.platform.leave()
	main.queue_free()
	await frames(3)
