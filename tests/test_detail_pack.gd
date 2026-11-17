extends "res://tests/test_case.gd"
## The optional Detailed pack (detail_pack.gd): a detailed model is fitted to the original's footprint;
## without the pack (a fresh copy) "Detailed" falls back to the originals; switching never changes saves.

const DetailPack := preload("res://scripts/world/detail_pack.gd")
const Detail := preload("res://scripts/core/pc_detail.gd")
const SurfaceMaterials := preload("res://scripts/world/surface_materials.gd")
const LicensedProps := preload("res://scripts/world/licensed_props.gd")


func _box(size: Vector3, at: Vector3) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = at
	root.add_child(mi)
	return root


func test_a_detailed_model_fills_the_original_footprint() -> void:
	var original := _box(Vector3(1.0, 0.8, 0.6), Vector3(0, 0.4, 0))
	var target := DetailPack.bounds(original)
	var detailed := _box(Vector3(200, 90, 100), Vector3(30, -10, 5))   # centimetres, off-centre, below the floor
	var fitted := DetailPack.fit(detailed, target)
	var b := DetailPack.bounds(fitted)
	check(b.size.x <= target.size.x + 0.001 and b.size.z <= target.size.z + 0.001, "inside the footprint (%s)" % b.size)
	check(absf(b.position.y - target.position.y) < 0.001, "standing on the floor")
	check(b.get_center().distance_to(Vector3(target.get_center().x, b.get_center().y, target.get_center().z)) < 0.001, "centred")
	check(absf(b.size.x / b.size.y - 200.0 / 90.0) < 0.01, "not squashed")
	original.free()
	fitted.free()


func test_without_the_pack_detailed_falls_back_to_the_originals() -> void:
	DetailPack.force = 1
	if not DetailPack.installed():
		eq(DetailPack.material_path("wood", "albedo"), "", "no detailed surface without the pack")
		eq(DetailPack.model("sofa"), null, "no detailed model without the pack")
		var sofa := LicensedProps.build("sofa", "")
		check(sofa != null, "the original sofa still builds")
		if sofa:
			sofa.free()
		if SurfaceMaterials.has("wood"):
			check(SurfaceMaterials.albedo("wood") != null, "the original wood surface")
	DetailPack.force = -1


func test_detailed_is_a_texture_choice() -> void:
	var names: Array = Detail.FEATURES.textures[1]
	eq(names[3], "Detailed", "Settings offers Detailed textures")
	var settings := {"pc_detail": "high", "pc_graphics": {"textures": 3}}
	eq(Detail.level_of("textures", 1, settings), 3)
	eq(Detail.level_of("textures", 0, settings), 3, "a texture choice made on purpose holds even with PC graphics Off")


func test_the_installed_pack_swaps_furniture_without_changing_the_object() -> void:
	if not DetailPack.installed():
		return   # (a copy without assets/detail/: the fallback test covers it)
	DetailPack.force = 1
	check(DetailPack.model("sofa") != null, "the detailed sofa loads")
	check(DetailPack.material_path("wood", "albedo") != "", "the 2K wood surface is there")
	var o := preload("res://scripts/world/furniture.gd").make("sofa", 1, 1, 0, "#aa4444")
	var detailed: Node3D = preload("res://scripts/world/furniture.gd").build(o)
	DetailPack.force = 0
	var plain: Node3D = preload("res://scripts/world/furniture.gd").build(o)
	DetailPack.force = -1
	var shapes := func(n: Node) -> Array:
		return n.find_children("*", "CollisionShape3D", true, false).map(func(c): return [(c.shape as BoxShape3D).size, c.position])
	eq(shapes.call(detailed), shapes.call(plain), "the same collision either way")
	var bd := DetailPack.bounds(detailed)
	var bp := DetailPack.bounds(plain)
	check(bd.size.x <= bp.size.x + 0.05 and bd.size.z <= bp.size.z + 0.05, "inside the original footprint (%s vs %s)" % [bd.size, bp.size])
	detailed.free()
	plain.free()
