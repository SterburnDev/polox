extends "res://tests/test_case.gd"


func test_mobile_quality_preserves_the_world_background_sky() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	preload("res://scripts/core/graphics.gd").apply_env(env, {"graphics": "balanced"}, false)
	eq(env.sky, sky, "quality settings retain the visible world sky")
	eq(env.background_mode, Environment.BG_SKY, "background never points at a cleared sky")
## 1.27's assets: furniture made in Blender from Kenney's kits, Poly Haven surfaces for the Light World,
## the reflection sky and the pixel emote balloons.

const Furniture := preload("res://scripts/world/furniture.gd")
const LicensedProps := preload("res://scripts/world/licensed_props.gd")
const SurfaceMaterials := preload("res://scripts/world/surface_materials.gd")
const EdgeWalls := preload("res://scripts/world/edge_walls.gd")
const Actor := preload("res://scripts/characters/actor.gd")
const Graphics := preload("res://scripts/core/graphics.gd")


func test_blender_furniture_fits_its_footprint_and_keeps_picking() -> void:
	fresh_save_root()
	for model in LicensedProps.BAKED:
		check(Furniture.exists(model), model + " is in the catalogue")
		for rot in [0, 1]:
			var node := Furniture.build({"id": "asset_check", "model": model, "rot": rot}, true)
			tree.root.add_child(node)
			var meshes := node.find_children("*", "MeshInstance3D", true, false)
			check(meshes.size() == 1, "%s is one mesh (got %d)" % [model, meshes.size()])
			var size := Furniture.base_size(model)
			var foot := Vector2(size.y, size.x) if rot == 1 else Vector2(size.x, size.y)
			for mesh in meshes:
				var box: AABB = mesh.global_transform * mesh.get_aabb()
				check(box.position.y >= -0.01, model + " rests on the floor")
				check(box.size.x <= foot.x + 0.01 and box.size.z <= foot.y + 0.01, "%s fits its footprint turned %d (%s in %s)" % [model, rot, box.size, foot])
				check(is_equal_approx(mesh.transparency, 0.6), model + ": the placement ghost covers the model")
			var bodies := node.find_children("*", "StaticBody3D", true, false)
			eq(bodies.size(), 1, model + ": one pick body")
			node.free()


## 1.27.6: every Blender piece carries its texture (pattern and baked soft shading). The paint material
## keeps the model's own colour as its albedo colour over a grey texture, so a tint replaces the colour
## and keeps the grain; every other material has its colour in the texture (albedo white).
func test_blender_furniture_is_textured_and_paint_stays_true() -> void:
	fresh_save_root()
	var textures := {}
	for model in LicensedProps.BAKED:
		var node := LicensedProps.build(model, "")
		check(node != null, model + " loads")
		if node == null:
			continue
		var mi: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
		var has_paint := false
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			check(m != null and m.albedo_texture != null, "%s: %s is textured" % [model, m.resource_name if m else "?"])
			if m == null or m.albedo_texture == null:
				continue
			textures[m.albedo_texture.resource_path if m.albedo_texture.resource_path != "" else str(m.albedo_texture.get_instance_id())] = m.albedo_texture
			if m.resource_name == "paint":
				has_paint = true
				check(not m.albedo_color.is_equal_approx(Color.WHITE) or model in ["washbasin"], "%s: the paint keeps the model's own colour (%s)" % [model, m.albedo_color])
			else:
				check(m.albedo_color.is_equal_approx(Color.WHITE), "%s: %s has its colour in the texture" % [model, m.resource_name])
			check(m.metallic == 0.0, "%s: %s isn't metallic (no reflections to show indoors)" % [model, m.resource_name])
		check(has_paint, model + " has a paint material")
		node.free()
	var px := 0
	for t in textures.values():
		var side := maxi((t as Texture2D).get_width(), (t as Texture2D).get_height())
		check(side == 512 or side == 1024, "a 512 or 1024 px texture (%d)" % side)
		px += (t as Texture2D).get_width() * (t as Texture2D).get_height()
	eq(textures.size(), LicensedProps.BAKED.size(), "one texture per model")
	# VRAM-compressed at 4 bits a pixel (+1/3 for mipmaps): what every piece at once would take on a phone.
	check(px * 0.5 * 1.34 < 24.0 * 1024 * 1024, "all furniture textures together stay small (%.1f MB)" % (px * 0.5 * 1.34 / 1048576.0))


func test_paint_tints_only_the_paint_material_and_a_lamp_still_glows() -> void:
	fresh_save_root()
	var sofa := LicensedProps.build("sofa", "#ff0000")
	tree.root.add_child(sofa)
	var mi: MeshInstance3D = sofa.find_children("*", "MeshInstance3D", true, false)[0]
	var painted := 0
	for i in mi.mesh.get_surface_count():
		var own := mi.mesh.surface_get_material(i)
		var shown := mi.get_surface_override_material(i)
		if own.resource_name == "paint":
			check(shown is BaseMaterial3D and (shown as BaseMaterial3D).albedo_color.is_equal_approx(Color("#ff0000")), "the cushions take the paint")
			painted += 1
		else:
			check(shown == null, "the %s stays as it is" % own.resource_name)
	eq(painted, 1, "one paint material")
	sofa.free()
	var plain := LicensedProps.build("sofa", "")
	tree.root.add_child(plain)
	var pm: MeshInstance3D = plain.find_children("*", "MeshInstance3D", true, false)[0]
	for i in pm.mesh.get_surface_count():
		check(pm.get_surface_override_material(i) == null, "unpainted: the model's own colours")
	plain.free()
	var lamp := LicensedProps.build("lamp", "#88ccff")
	tree.root.add_child(lamp)
	var lm: MeshInstance3D = lamp.find_children("*", "MeshInstance3D", true, false)[0]
	var glows := false
	for i in lm.mesh.get_surface_count():
		var shown := lm.get_surface_override_material(i)
		if shown is BaseMaterial3D and (shown as BaseMaterial3D).emission_enabled:
			glows = (shown as BaseMaterial3D).emission.is_equal_approx(Color("#88ccff"))
	check(glows, "a painted lamp shade glows in its new colour")
	lamp.free()
	var built := Furniture.build({"id": "l", "model": "lamp"})
	check(built.find_children("Glow", "OmniLight3D", true, false).size() == 1, "the floor lamp still lights the room")
	built.free()


func test_light_world_surfaces_and_battery_saver() -> void:
	fresh_save_root()
	eq(SurfaceMaterials.info().size(), 11, "eleven surfaces (the glazed ceramic tiles joined on 2026-11-08)")
	for name in SurfaceMaterials.LOOK:
		check(SurfaceMaterials.has(name), name + " has its numbers")
		check(SurfaceMaterials.albedo(name) != null and SurfaceMaterials.normal(name) != null, name + " pictures load")
	var m := SurfaceMaterials.standard("wood", Color("#c9a27a"))
	check(m != null and m.get_shader_parameter("surface_tex") != null and m.get_shader_parameter("surface_nrm") != null, "a textured wood floor")
	check(float(m.get_shader_parameter("surface_strength")) > 0.0, "with its grain showing")
	eq(m.get_shader_parameter("color"), Color("#c9a27a"), "in the room's own colour")
	check(SurfaceMaterials.standard("wood", Color("#c9a27a")) == m, "shared per surface and colour")
	var walls := EdgeWalls.new()
	tree.root.add_child(walls)
	walls.build({"floor_areas": [{"rect": [0, 0, 3, 3], "color": "#c9a27a", "material": "wood"}],
		"edge_walls": [{"x": 0, "z": 0, "dir": "h", "color": "#efe6d8"}],
		"buildings": [{"cells": [[5, 5], [6, 5]], "h": 2.4, "wall": "#e9e1d0", "roof": "#7a5a46"}]}, 2.6)
	check(float(walls.floor_mat.get_shader_parameter("wood_strength")) > 0.0, "room floors use the wood texture")
	check(float(walls.walls_mat.get_shader_parameter("plaster_strength")) > 0.0, "walls are plaster")
	walls.free()
	GameState.settings["graphics"] = "saver"
	check(SurfaceMaterials.standard("wood", Color("#c9a27a")) == null, "Battery saver: plain colours")
	var saver := EdgeWalls.new()
	tree.root.add_child(saver)
	saver.build({"floor_areas": [{"rect": [0, 0, 3, 3], "color": "#c9a27a", "material": "wood"}]}, 2.6)
	eq(float(saver.floor_mat.get_shader_parameter("wood_strength")), 0.0, "Battery saver: the drawn floor pattern")
	saver.free()
	GameState.settings.erase("graphics")


func test_reflection_sky_only_where_it_pays() -> void:
	fresh_save_root()
	var env := Environment.new()
	Graphics.apply_env(env, {"graphics": "high"}, true)
	if RenderingServer.get_current_rendering_method() in ["forward_plus", "mobile"]:
		check(env.sky != null and env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY, "a PC at High: a street reflects the sky")
	else:
		check(env.sky == null, "no sky on the phone renderer (or headless)")
	Graphics.apply_env(env, {"graphics": "high"}, false)
	check(env.sky == null and env.reflected_light_source == Environment.REFLECTION_SOURCE_BG, "indoors and the Dream World: no daylight sky")
	var GameWorld := load("res://scripts/world/game_world.gd")
	check(GameWorld.open_sky({"id": "lw_hood_1", "kind": "outdoor"}), "a Light World street is under the sky")
	check(not GameWorld.open_sky({"id": "lw_floor_0", "kind": "indoor"}), "a room is not")
	check(not GameWorld.open_sky({"id": "garden", "kind": "outdoor"}), "nor the Dream World")
	Graphics.apply_env(env, {"graphics": "balanced"}, true)
	check(env.sky == null and not env.ssao_enabled, "Balanced: no sky, no occlusion")
	check(ResourceLoader.exists(Graphics.SKY), "the sky picture ships")


func test_pixel_emote_balloons() -> void:
	fresh_save_root()
	for symbol in Actor.EMOTES:
		check(Actor.emote_texture(symbol) != null, "a balloon for " + symbol)
	check(Actor.emote_texture("☂") == null, "other symbols stay text")
	var a := Actor.new()
	a.setup("t", "T", ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8)))
	tree.root.add_child(a)
	a.emote("♥")
	check(a.find_children("*", "Sprite3D", true, false).any(func(s): return (s as Sprite3D).texture == Actor.emote_texture("♥")), "a heart balloon floats up")
	a.emote("☂")
	check(a.find_children("*", "Label3D", true, false).any(func(l): return (l as Label3D).text == "☂"), "and a text one for the rest")
	a.free()


static func _has_bytes(haystack: PackedByteArray, needle: PackedByteArray) -> bool:
	if needle.is_empty():
		return false
	var first := needle[0]
	var limit := haystack.size() - needle.size()
	var pos := haystack.find(first, 0)
	while pos >= 0 and pos <= limit:
		var matched := true
		for j in range(1, needle.size()):
			if haystack[pos + j] != needle[j]:
				matched = false
				break
		if matched:
			return true
		pos = haystack.find(first, pos + 1)
	return false


static func _collect_images(dir_path: String, out: PackedStringArray) -> void:
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if da.current_is_dir():
				_collect_images(full, out)
			elif entry.get_extension().to_lower() in ["jpg", "jpeg", "png"]:
				out.append(full)
		entry = da.get_next()


func test_models_uvs_collisions_credits_and_stripped_exif() -> void:
	fresh_save_root()
	# 1. Clean UV mapping across every licensed & baked 3D prop model.
	var all_models: Array = []
	for m in LicensedProps.MODELS:
		all_models.append(str(m))
	for m in LicensedProps.BAKED:
		all_models.append(str(m))
	for model in all_models:
		var node := LicensedProps.build(model, "")
		check(node != null, model + " builds for UV audit")
		if node == null:
			continue
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), model + " has meshes")
		for mi in meshes:
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(si)
				var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
				var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
				check(verts is PackedVector3Array and (verts as PackedVector3Array).size() > 0, "%s surf %d has vertices" % [model, si])
				check(uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == (verts as PackedVector3Array).size(), "%s surf %d has clean UV mapping" % [model, si])
		node.free()

	# 2. PBR brass & translucent glowing glass lantern + collision + painted variant preserves brass PBR maps.
	var lantern := Furniture.build({"id": "lan1", "model": "lantern"})
	tree.root.add_child(lantern)
	var lmeshes := lantern.find_children("*", "MeshInstance3D", true, false)
	var has_brass := false
	var has_glass := false
	for mi in lmeshes:
		var mesh_node := mi as MeshInstance3D
		for si in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_active_material(si) as BaseMaterial3D
			var mname := (mat.resource_name if mat else "").to_lower()
			if mesh_node.name.to_lower().contains("glass") or mname.contains("glass"):
				has_glass = mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and mat.albedo_color.a < 0.9 and mat.emission_enabled
			else:
				has_brass = mat != null and mat.albedo_texture != null and mat.normal_enabled and mat.metallic > 0.5
	check(has_brass, "lantern preserves PBR brass maps")
	check(has_glass, "lantern glass panes use translucent glowing glass")
	eq(lantern.find_children("Glow", "OmniLight3D", true, false).size(), 1, "lantern has warm OmniLight3D")
	eq(lantern.find_children("*", "StaticBody3D", true, false).size(), 1, "lantern has collision body")
	lantern.free()

	var painted_lantern := LicensedProps.build("lantern", "#ffd27f")
	var pbrass_ok := false
	for mi in painted_lantern.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := mi as MeshInstance3D
		for si in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_active_material(si) as BaseMaterial3D
			if not mesh_node.name.to_lower().contains("glass"):
				pbrass_ok = mat != null and mat.albedo_texture != null and mat.normal_enabled
	check(pbrass_ok, "painted lantern keeps PBR brass maps")
	painted_lantern.free()

	# 3. Double-sided framed sign board UVs + collision, glazed ceramic shader, and layered ground planes.
	var BlockFactory := preload("res://scripts/world/block_factory.gd")
	var sign := BlockFactory.make_object({"id": "sign_uv", "type": "sign", "color": "#8b5e3c"})
	var sign_faces := sign.find_children("*", "MeshInstance3D", true, false).filter(func(m): return (m as MeshInstance3D).mesh is QuadMesh)
	eq(sign_faces.size(), 2, "framed sign board has two faces")
	for sf in sign_faces:
		var sa := (sf as MeshInstance3D).mesh.surface_get_arrays(0)
		eq((sa[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size(), (sa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "sign face has UVs")
	eq(sign.find_children("*", "StaticBody3D", true, false).size(), 1, "sign has collision body")
	sign.free()

	if SurfaceMaterials.enabled():
		var cer := SurfaceMaterials.standard("ceramic", Color("#cdc4b6"))
		check(cer != null and cer.get_shader_parameter("surface_tex") != null and cer.get_shader_parameter("surface_nrm") != null, "glazed ceramic shader loads textures")
	var PlaceBackdrop := preload("res://scripts/world/place_backdrop.gd")
	var backdrop := PlaceBackdrop.new()
	tree.root.add_child(backdrop)
	backdrop.build({"size": {"w": 10, "d": 10}, "kind": "outdoor", "floor": {"color": "#3f7a5a"}, "edges": {"east": "other"}},
		{"east": {"name": "Other", "size": {"w": 8, "d": 8}, "floor": {"color": "#6a9a5b"}}})
	var strip := backdrop.find_child("Beyond_east", true, false) as MeshInstance3D
	check(strip != null and (strip.material_override as StandardMaterial3D).albedo_texture != null, "neighbour ground strip gets layered surface detail")
	backdrop.free()

	# 4. Valid licenses recorded in docs/ASSET_CREDITS.md & ceramic manifest hashes present.
	var credits := FileAccess.get_file_as_string("res://docs/ASSET_CREDITS.md")
	check(credits.contains("CC0 1.0") and credits.contains("assets/polyhaven/lantern_01/") and credits.contains("assets/materials/ceramic/"), "docs/ASSET_CREDITS.md documents CC0 licences for new assets")
	check(credits.contains("assets/materials/") and credits.contains("assets/kenney/"), "docs/ASSET_CREDITS.md documents existing surface and Kenney kits")
	var manifest_text := FileAccess.get_file_as_string("res://assets/materials/manifest.json")
	check(manifest_text.contains("assets/materials/ceramic/albedo.jpg") and manifest_text.contains("assets/materials/ceramic/normal.jpg"), "materials manifest records ceramic file hashes")

	# 5. Stripped camera/location EXIF & XMP metadata across all shipped asset images.
	var images := PackedStringArray()
	for root_dir in ["res://assets/materials", "res://assets/polyhaven", "res://assets/models", "res://assets/kenney", "res://assets/sky"]:
		_collect_images(root_dir, images)
	check(images.size() > 10, "audited asset images (%d)" % images.size())
	var exif_sig := "Exif".to_ascii_buffer() + PackedByteArray([0, 0])
	var xmp_sig := "http://ns.adobe.com/xap/1.0/".to_ascii_buffer()
	for path in images:
		var raw := FileAccess.get_file_as_bytes(path)
		var head := raw.slice(0, mini(raw.size(), 65536))
		check(not _has_bytes(head, exif_sig), path + " has no EXIF metadata")
		check(not _has_bytes(raw.slice(0, mini(raw.size(), 262144)), xmp_sig), path + " has no XMP metadata")
