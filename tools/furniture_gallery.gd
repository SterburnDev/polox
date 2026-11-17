extends SceneTree
## Every Blender furniture piece lined up in a room lit like a Light World room at 10:00 (the game's sun,
## flat ambient with the indoor fill, filmic on a PC), with a few painted copies, for checking textures and
## baked shading in the game's own renderer. Writes a screenshot and quits.
##   godot --path . --resolution 1600x1000 [--rendering-method gl_compatibility] --script res://tools/furniture_gallery.gd -- --save-root=tests/.tmp_save/gallery --out=build/furniture_tex/godot.png [--models=a,b]

const PAINTED := [["sofa", "#4f7fb8"], ["armchair", "#7a9a5a"], ["bean_bag", "#6a5aa8"], ["desk", "#5a4a40"], ["rug", "#3f8f8a"], ["bar_stool", "#c95a4a"]]

var _started := false


func _process(_delta: float) -> bool:
	# Autoloads join the tree before the first frame; the furniture scripts use them, so they're loaded then
	# (this script compiles before they exist).
	if not _started:
		_started = true
		_show()
	return false


func _show() -> void:
	var Furniture: Script = load("res://scripts/world/furniture.gd")
	var LicensedProps: Script = load("res://scripts/world/licensed_props.gd")
	var out := "build/furniture_tex/godot.png"
	var models: Array = Array(LicensedProps.BAKED)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--models="):
			models = Array(a.trim_prefix("--models=").split(","))
	var phone := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var scene := Node3D.new()
	root.add_child(scene)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#d9cfc2")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ddd6cc").lerp(Color("#eee0cc"), 0.28)
	env.ambient_light_energy = maxf(0.44 * (0.62 if phone else 1.0), 0.32)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#fff3e2")
	sun.light_energy = 0.78 * (0.55 if phone else 1.0)
	sun.rotation_degrees = Vector3(-60.0, -47.0, 0)
	sun.shadow_enabled = not phone
	scene.add_child(sun)
	var items: Array = []
	for m in models:
		items.append([str(m), ""])
	if models.size() == LicensedProps.BAKED.size():
		items.append_array(PAINTED)
	var cols := mini(7, maxi(3, ceili(sqrt(items.size() * 1.6))))
	var rows := ceili(items.size() / float(cols))
	var cell := 2.4
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(cols * cell + 2.0, rows * cell + 2.0)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#c9b49a")
	fm.roughness = 0.9
	floor_mesh.material_override = fm
	floor_mesh.position = Vector3(0, 0, 0)
	scene.add_child(floor_mesh)
	for i in items.size():
		var o: Dictionary = Furniture.make(str(items[i][0]), 0, 0, 0, str(items[i][1]))
		o["id"] = "gallery_%d" % i
		var node: Node3D = Furniture.build(o)
		var c := i % cols
		var r := i / cols
		node.position = Vector3((c - (cols - 1) / 2.0) * cell, 0, (r - (rows - 1) / 2.0) * cell)
		scene.add_child(node)
		var label := Label3D.new()
		label.text = str(items[i][0]) + (" (painted)" if str(items[i][1]) != "" else "")
		label.font_size = 40
		label.pixel_size = 0.004
		label.modulate = Color("#3a2f28")
		label.outline_size = 0
		label.rotation_degrees.x = -90
		label.position = node.position + Vector3(0, 0.01, 0.95)
		scene.add_child(label)
	var cam := Camera3D.new()
	cam.fov = 32
	var span := maxf(cols * cell, rows * cell * 1.5) * 0.8
	cam.position = Vector3(0, span * 0.95, span * 1.05)
	scene.add_child(cam)
	cam.look_at(Vector3(0, 0.3, 0.2))
	cam.make_current()
	for _f in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out.get_base_dir()))
	img.save_png(ProjectSettings.globalize_path("res://" + out))
	print("gallery ", out, " ", items.size(), " pieces, ", RenderingServer.get_current_rendering_method())
	quit(0)
