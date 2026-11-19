extends RefCounted
## Selected CC0 models; provenance and original notices: assets/kenney/manifest.json.
## Tags: [GRAPHICS]
const MODELS := {
	"bench": preload("res://assets/kenney/furniture/bench.glb"),
	"tree": preload("res://assets/kenney/suburban/tree-small.glb"),
	"streetlamp": preload("res://assets/kenney/roads/light-square.glb"),
	# Poly Haven's Lantern 01 (CC0, Rajil Jose Macatangay): brass and textured glass; docs/ASSET_CREDITS.md.
	"lantern": preload("res://assets/polyhaven/lantern_01/Lantern_01_1k.gltf"),
}
const SIZES := {"bench": Vector3(1.7, 0.9, 0.65), "tree": Vector3(0.95, 2.6, 0.95), "streetlamp": Vector3(0.8, 2.8, 0.8), "lantern": Vector3(0.34, 0.52, 0.34)}
## Furniture made in Blender, from Kenney's Furniture and Nature kits (tools/blender_scripts/build_furniture.py)
## and modelled for Polox (model_props.py: the bean bag, fish tank, coat rack, bar stool, wall clock and
## piano), then textured with baked soft shading (texture_furniture.py): already in metres, facing south,
## centred on the floor of their footprint, one mesh and one texture each. The material the player's paint
## tints is called "paint" (its texture is grey, so the tint shows true); lamp shades and the fish tank glow.
## Loaded the first time they're needed.
const BAKED_DIR := "res://assets/models/furniture/"
const BAKED: PackedStringArray = ["bed", "double_bed", "nightstand", "wardrobe", "dresser", "desk", "chair", "computer",
	"bookshelf", "sofa", "armchair", "coffee_table", "tv", "dining_table", "counter", "sink", "stove", "fridge", "toilet",
	"bathtub", "shower", "washbasin", "washer", "lamp", "plant", "rug", "runner", "stairs", "bush", "flowers",
	"bean_bag", "fish_tank", "coat_rack", "bar_stool", "wall_clock", "piano"]

const SHADE_GLOW := 0.38
static var _baked: Dictionary = {}       # model -> PackedScene
static var _paints: Dictionary = {}
static var _bounds: Dictionary = {}      # model -> the original's bounds (for fitting a detailed one)
const DetailPack := preload("res://scripts/world/detail_pack.gd")      # "material id|colour" -> the tinted copy


static func has_model(model: String) -> bool:
	return MODELS.has(model) or model in BAKED


static func build(model: String, paint: String) -> Node3D:
	if model in BAKED:
		return _build_baked(model, paint)
	if not MODELS.has(model):
		return null
	var root := Node3D.new()
	var scene: Node3D = MODELS[model].instantiate()
	root.add_child(scene)
	var bounds := AABB()
	var first := true
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var transform := mesh.transform
		var parent := mesh.get_parent()
		while parent != root:
			transform = (parent as Node3D).transform * transform
			parent = parent.get_parent()
		var box: AABB = transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		if model == "lantern":
			for i in mesh.mesh.get_surface_count():
				var surf_mat := mesh.mesh.surface_get_material(i)
				var is_glass := mesh.name.to_lower().contains("glass") or (surf_mat != null and surf_mat.resource_name.to_lower().contains("glass"))
				if is_glass:
					mesh.set_surface_override_material(i, _lantern_glass(paint))
				elif paint != "" and surf_mat is BaseMaterial3D:
					var tinted := (surf_mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					tinted.albedo_color = Color.from_string(paint, Color.WHITE)
					mesh.set_surface_override_material(i, tinted)
		elif paint != "":
			var material := StandardMaterial3D.new()
			material.albedo_color = Color.from_string(paint, Color.WHITE)
			material.roughness = 0.9
			mesh.material_override = material
	if not first:
		var target: Vector3 = SIZES[model]
		var scale_factor := minf(target.x / maxf(bounds.size.x, 0.001), minf(target.y / maxf(bounds.size.y, 0.001), target.z / maxf(bounds.size.z, 0.001)))
		scene.scale *= scale_factor
		scene.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * scale_factor
	return root


## Translucent glowing glass panes for Poly Haven's PBR lantern (kept shared per paint colour).
static func _lantern_glass(paint: String) -> StandardMaterial3D:
	var key := "lantern_glass|" + paint
	if _paints.has(key):
		return _paints[key]
	if _paints.size() >= 256:
		_paints.clear()
	var gm := StandardMaterial3D.new()
	var tint := Color.from_string(paint, Color("#ffd591")) if paint != "" else Color("#ffd591")
	gm.resource_name = "Lantern_01_glass_pbr"
	gm.albedo_color = Color(tint.r, tint.g, tint.b, 0.36) if paint != "" else Color(1.0, 0.95, 0.82, 0.32)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.12
	gm.metallic = 0.0
	gm.metallic_specular = 0.75
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.emission_enabled = true
	gm.emission = tint
	gm.emission_energy_multiplier = SHADE_GLOW
	_paints[key] = gm
	return gm


static func _build_baked(model: String, paint: String) -> Node3D:
	if not _baked.has(model):
		var res: Resource = load(BAKED_DIR + model + ".glb") if ResourceLoader.exists(BAKED_DIR + model + ".glb") else null
		_baked[model] = res
	var packed: PackedScene = _baked[model]
	if packed == null:
		return null
	var root := Node3D.new()
	var detailed := DetailPack.model(model) if DetailPack.active() else null
	if detailed:
		# The Detailed pack: its model, fitted to the original's bounds (same footprint, same floor).
		if not _bounds.has(model):
			var probe: Node3D = packed.instantiate()
			_bounds[model] = DetailPack.bounds(probe)
			probe.free()
		root.add_child(DetailPack.fit(detailed.instantiate(), _bounds[model]))
		return root
	root.add_child(packed.instantiate())
	if paint != "":
		var tint := Color.from_string(paint, Color.WHITE)
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m is BaseMaterial3D and m.resource_name == "paint":
					mi.set_surface_override_material(i, _painted(m, tint))
	elif model == "lamp":
		# Its own colour too: the shade's glow capped the same way (an unpainted lamp burned out to white).
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled:
					mi.set_surface_override_material(i, _painted(m, (m as BaseMaterial3D).albedo_color))
	return root


## The model's own paint material in the player's colour (its roughness, and its glow for a lamp, kept).
static func _painted(m: BaseMaterial3D, tint: Color) -> BaseMaterial3D:
	var key := "%d|%s" % [m.get_instance_id(), tint.to_html()]
	if _paints.has(key):
		return _paints[key]
	if _paints.size() >= 256:
		_paints.clear()   # pieces already drawn keep their own copy
	var p := m.duplicate() as BaseMaterial3D
	p.albedo_color = tint
	if p.emission_enabled:
		# A lit shade glows in its own colour, at about a third of full strength: at full strength
		# (plus the room's glow pass) a cream shade burned out to a flat white shape with no form.
		p.emission = tint
		p.emission_energy_multiplier = minf(p.emission_energy_multiplier, SHADE_GLOW)
	_paints[key] = p
	return p
