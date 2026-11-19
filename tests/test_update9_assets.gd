extends "res://tests/test_case.gd"
const Furniture := preload("res://scripts/world/furniture.gd")
const Synth := preload("res://scripts/core/synth.gd")


func test_selected_models_fit_existing_footprints_and_pick_shapes() -> void:
	fresh_save_root()
	for model in ["bench", "tree", "streetlamp", "lantern"]:
		var node := Furniture.build({"id": "asset_check", "model": model, "rot": 1}, true)
		tree.root.add_child(node)
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), model + " has imported geometry")
		var footprint := Furniture.base_size(model)
		for mesh in meshes:
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			check(box.position.y >= -0.01, model + " rests on the floor")
			check(box.size.x <= footprint.y + 0.01 and box.size.z <= footprint.x + 0.01, model + " fits rotated navigation footprint")
			check(is_equal_approx(mesh.transparency, 0.6), "placement ghost includes imported meshes")
		var bodies := node.find_children("*", "StaticBody3D", true, false)
		eq(bodies.size(), 1, "one existing pick body")
		eq(str(bodies[0].get_meta("id")), "asset_check")
		node.free()


func test_recorded_footsteps_load_and_user_override_wins() -> void:
	fresh_save_root()
	Synth._cache.clear()
	for sound in ["step_wood", "step_stone", "step_grass"]:
		var stream := Synth.get_sound(sound)
		check(stream is AudioStreamOggVorbis and stream.get_length() > 0.01, "recorded footstep decodes")
	var folder := SaveManager.global_path("audio/sfx")
	DirAccess.make_dir_recursive_absolute(folder)
	var custom := Synth._tone([[440.0, 0.1]], "sine", 0.1)
	check(custom.save_to_wav(folder.path_join("step_wood.wav")) == OK)
	Synth._cache.clear()
	check(Synth.get_sound("step_wood") is AudioStreamWAV, "player sound overrides packaged recording")
	Synth._cache.clear()
