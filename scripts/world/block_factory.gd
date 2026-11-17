extends RefCounted
## Makes the 3D pieces a room is built from: materials (color or PNG,
## tiled once per meter), tiles (cube/slab/ramp/pillar) and objects
## (door/sign/prop). Shared by the room view and build-mode previews.

const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const SurfaceDetail := preload("res://scripts/world/surface_detail.gd")

const TILE_TYPES: PackedStringArray = ["cube", "slab", "ramp", "pillar"]
const OBJECT_TYPES: PackedStringArray = ["door", "dream_door", "dark_fountain", "furniture", "battle_spot", "sign", "prop", "pickup", "platform_pillar", "jump_pad", "one_way", "mover", "checkpoint", "shard", "hazard"]
## Platform Mode's objects (platform_objects.gd draws them). "platform_pillar" is the
## Platform Pillar's piece id (the block piece "pillar" is a column).
const PLATFORM_OBJECTS: PackedStringArray = ["platform_pillar", "jump_pad", "one_way", "mover", "checkpoint", "shard", "hazard"]
const HEIGHTS := {"cube": 1.0, "slab": 0.5, "ramp": 1.0, "pillar": 2.0, "door": 2.0, "sign": 1.3, "prop": 1.2, "pickup": 0.8,
	"dream_door": 2.0, "dark_fountain": 1.4, "furniture": 0.8, "battle_spot": 0.1, "platform_pillar": 3.0, "jump_pad": 0.2, "one_way": 0.15, "mover": 0.3, "checkpoint": 1.6, "shard": 1.0, "hazard": 0.1}
const LAYER_WORLD := 1
const LAYER_ACTORS := 2
const LAYER_OBJECTS := 4

static var _mat_cache: Dictionary = {}
static var _plant_tex: Texture2D
static var _sign_face_tex: Texture2D
static var _parts_cache: Dictionary = {}   # type -> [[Mesh, local Transform3D], ...]


static func height_of(type: String) -> float:
	return float(HEIGHTS.get(type, 1.0))


## Matte material from a {color, texture} spec. Textures use world-space
## triplanar mapping so they tile once per meter on every face. `detail` ("floor", "wall", "block")
## gives a plain colour fine surface detail (surface_detail.gd); a chosen picture is used as it is.
static func material(color: String, texture: String = "", transparent: bool = false, detail: String = "") -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color, texture, transparent, detail]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	m.albedo_color = Color.from_string(color, Color("#8a7bc8")) if color != "" else Color.WHITE
	var tex: Texture2D = SaveManager.load_texture(texture) if texture != "" else null
	if tex == null and detail != "":
		tex = SurfaceDetail.texture(detail)
	if tex:
		m.albedo_texture = tex
		if color == "":
			m.albedo_color = Color.WHITE
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		if detail == "ground":
			m.uv1_scale = Vector3.ONE * 0.25
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
	return m


static func clear_cache() -> void:
	_mat_cache.clear()


static func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Static body with one box shape, tagged so clicks know what was hit.
static func body(size: Vector3, center: Vector3, layer: int, meta: Dictionary) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	sb.add_child(cs)
	for k in meta:
		sb.set_meta(k, meta[k])
	return sb


## The meshes a tile type is made of, as [mesh, local offset] pairs (shared,
## so a room full of cubes shares one BoxMesh).
static func tile_parts(type: String) -> Array:
	if _parts_cache.has(type):
		return _parts_cache[type]
	var parts: Array = []
	match type:
		"slab":
			parts.append([_box(Vector3(1, 0.5, 1)), Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0))])
		"ramp":
			var p := PrismMesh.new()
			p.left_to_right = 0.0
			p.size = Vector3(1, 1, 1)
			parts.append([p, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))])
		"pillar":
			var c := CylinderMesh.new()
			c.top_radius = 0.28
			c.bottom_radius = 0.32
			c.height = 2.0
			c.radial_segments = 12
			parts.append([c, Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0))])
			parts.append([_box(Vector3(0.8, 0.15, 0.8)), Transform3D(Basis.IDENTITY, Vector3(0, 0.075, 0))])
			parts.append([_box(Vector3(0.8, 0.15, 0.8)), Transform3D(Basis.IDENTITY, Vector3(0, 1.925, 0))])
		_:
			parts.append([_box(Vector3(1, 1, 1)), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))])
	_parts_cache[type] = parts
	return parts


## Where a tile sits in the room: its cell's floor center, turned by rot.
static func tile_transform(tile: Dictionary) -> Transform3D:
	var pos := Vector3(float(tile.get("x", 0)) + 0.5, float(tile.get("y", 0)), float(tile.get("z", 0)) + 0.5)
	return Transform3D(Basis.from_euler(Vector3(0, int(tile.get("rot", 0)) * PI / 2.0, 0)), pos)


## A single tile node (used by the build ghost), origin at the cell's floor
## center. tile = {type, color, texture, rot}
static func make_tile(tile: Dictionary) -> Node3D:
	var root := Node3D.new()
	var type := str(tile.get("type", "cube"))
	var mat := material(str(tile.get("color", "#8a7bc8")), str(tile.get("texture", "")), false, "block")
	var h := height_of(type)
	for part in tile_parts(type):
		var mi := _mesh(part[0], mat, Vector3.ZERO)
		mi.transform = part[1]
		root.add_child(mi)
	root.rotation.y = int(tile.get("rot", 0)) * PI / 2.0
	root.add_child(body(Vector3(1, h, 1), Vector3(0, h / 2.0, 0), LAYER_WORLD, {"kind": "tile"}))
	return root


## Many tiles of one type and material as MultiMesh instances: one draw call
## per part instead of one node per block, so big rooms stay fast.
static func make_tile_batch(type: String, color: String, texture: String, tiles: Array) -> Array:
	var out: Array = []
	var mat := material(color, texture, false, "block")
	for part in tile_parts(type):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = tiles.size()
		for i in tiles.size():
			mm.set_instance_transform(i, tile_transform(tiles[i]) * part[1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		out.append(mmi)
	return out


## One static body holding a box per tile (cheaper than a body per block).
static func tiles_body(tiles: Array) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = LAYER_WORLD
	sb.collision_mask = 0
	sb.set_meta("kind", "tile")
	for t in tiles:
		var h := height_of(str(t.get("type", "cube")))
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1, h, 1)
		cs.shape = shape
		cs.position = Vector3(float(t.get("x", 0)) + 0.5, float(t.get("y", 0)) + h / 2.0, float(t.get("z", 0)) + 0.5)
		sb.add_child(cs)
	return sb


## The way an object turned `rot` quarter turns faces (its front: +Z at rot 0), as a step on the grid.
static func facing(rot: int) -> Vector2i:
	return [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)][posmod(rot, 4)]


## An object node (door / sign / prop / pickup), origin at the cell's floor center.
## `ghost` draws a taken pickup see-through (the editor still shows it).
static func make_object(obj: Dictionary, ghost: bool = false) -> Node3D:
	var type := str(obj.get("type", "prop"))
	if type in PLATFORM_OBJECTS:
		var po := obj.duplicate()
		po["type"] = "pillar" if type == "platform_pillar" else type
		var n: Node3D = load("res://scripts/platform/platform_objects.gd").make(po, ghost)  # load(): it preloads this file
		n.rotation.y = float(obj.get("rot", 0)) * PI / 2.0
		return n
	if type == "dark_fountain":
		return load("res://scripts/world/fountain_node.gd").make(obj, ghost)   # load(): it preloads this file
	if type == "furniture":
		return load("res://scripts/world/furniture.gd").build(obj, ghost)
	if type == "battle_spot":
		var spot := Node3D.new()
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.rings = 24
		tm.ring_segments = 8
		tm.inner_radius = 0.32
		tm.outer_radius = 0.46
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color("#e86a8a")
		rm.emission_enabled = true
		rm.emission = Color("#e86a8a")
		rm.emission_energy_multiplier = 1.2
		ring.material_override = rm
		ring.position = Vector3(0, 0.05, 0)
		ring.scale = Vector3(1, 0.3, 1)
		spot.add_child(ring)
		spot.add_child(body(Vector3(0.9, 0.3, 0.9), Vector3(0, 0.15, 0), LAYER_OBJECTS, {"kind": "object", "id": str(obj.get("id", ""))}))
		return spot
	if type == "dream_door":
		var dd := obj.duplicate()
		dd["type"] = "door"
		dd["color"] = str(obj.get("color", "")) if str(obj.get("color", "")) != "" else "#c58cff"
		var door_node := make_object(dd, ghost)
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color("#c58cff")
		glow.emission_enabled = true
		glow.emission = Color("#c58cff")
		glow.emission_energy_multiplier = 1.6
		var swirl := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.86, 1.9)
		swirl.mesh = q
		swirl.material_override = glow
		swirl.position = Vector3(0, 0.98, 0.06)
		door_node.add_child(swirl)
		return door_node
	if type == "pickup":
		var p: Node3D = load("res://scripts/items/pickup_node.gd").make(obj, ghost)  # load(): the pickup script uses this one
		p.rotation.y = float(obj.get("rot", 0)) * PI / 2.0
		return p
	var root := Node3D.new()
	var color := str(obj.get("color", ""))
	var meta := {"kind": "object", "id": str(obj.get("id", ""))}
	match type:
		"door":
			var frame := material(color if color != "" else "#8b5e3c")
			var panel := material("#f3e9d2" if color == "" else Color.from_string(color, Color.WHITE).lightened(0.35).to_html(false), str(obj.get("texture", "")))
			root.add_child(_mesh(_box(Vector3(0.12, 2.1, 0.25)), frame, Vector3(-0.5, 1.05, 0)))
			root.add_child(_mesh(_box(Vector3(0.12, 2.1, 0.25)), frame, Vector3(0.5, 1.05, 0)))
			root.add_child(_mesh(_box(Vector3(1.12, 0.14, 0.25)), frame, Vector3(0, 2.1, 0)))
			root.add_child(_mesh(_box(Vector3(0.88, 1.95, 0.1)), panel, Vector3(0, 0.98, 0)))
			root.add_child(_mesh(_box(Vector3(0.1, 0.1, 0.14)), material("#ffd166"), Vector3(0.28, 1.0, 0.04)))
			root.add_child(body(Vector3(1.1, 2.1, 0.4), Vector3(0, 1.05, 0), LAYER_OBJECTS, meta))
		"sign":
			var tint := color if color != "" else "#c08a5a"
			root.add_child(_mesh(_box(Vector3(0.12, 1.0, 0.12)), material("#7a5236"), Vector3(0, 0.5, 0)))
			if str(obj.get("texture", "")) != "":
				# A picture the player chose is the whole board, exactly as before.
				root.add_child(_mesh(_box(Vector3(0.9, 0.55, 0.1)), material("", str(obj.get("texture", ""))), Vector3(0, 1.05, 0)))
			else:
				# A framed board that reads as a sign from across a room: a darker rim (the old board's
				# size, so nothing moves), a written face on both sides and a little ledge on top.
				var rim := material(Color.from_string(tint, Color.WHITE).darkened(0.38).to_html(false))
				root.add_child(_mesh(_box(Vector3(0.9, 0.55, 0.1)), rim, Vector3(0, 1.05, 0)))
				root.add_child(_mesh(_box(Vector3(0.98, 0.06, 0.2)), rim, Vector3(0, 1.355, 0)))
				for side in [1.0, -1.0]:
					var face := MeshInstance3D.new()
					var quad := QuadMesh.new()
					quad.size = Vector2(0.8, 0.44)
					face.mesh = quad
					face.material_override = _sign_face_material(tint)
					face.position = Vector3(0, 1.05, 0.052 * side)
					face.rotation.y = 0.0 if side > 0.0 else PI
					root.add_child(face)
			root.add_child(body(Vector3(0.9, 1.35, 0.5), Vector3(0, 0.67, 0), LAYER_OBJECTS, meta))
		_:
			var s := Sprite3D.new()
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			s.shaded = false
			var tex: Texture2D = SaveManager.load_texture(str(obj.get("texture", ""))) if str(obj.get("texture", "")) != "" else null
			s.texture = tex if tex else _plant()
			s.pixel_size = 1.2 / maxf(1.0, s.texture.get_height())
			s.position.y = 0.6
			if color != "":
				s.modulate = Color.from_string(color, Color.WHITE)
			root.add_child(s)
			root.add_child(body(Vector3(0.8, 1.2, 0.8), Vector3(0, 0.6, 0), LAYER_OBJECTS, meta))
	root.rotation.y = float(obj.get("rot", 0)) * PI / 2.0
	var sc := float(obj.get("scale", 1.0))
	if sc > 0.0 and not is_equal_approx(sc, 1.0):
		root.scale = Vector3.ONE * sc
	return root


## The written face of a sign in the sign's colour (one material per colour, kept with the others).
static func _sign_face_material(tint: String) -> StandardMaterial3D:
	var key := "sign_face|" + tint
	if _mat_cache.has(key):
		return _mat_cache[key]
	if _sign_face_tex == null:
		_sign_face_tex = ImageTexture.create_from_image(SpriteFactory.sign_face())
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	m.albedo_texture = _sign_face_tex
	# Lighter than the rim's wood, so the face stands out from its frame.
	m.albedo_color = Color.from_string(tint, Color("#c08a5a")).lightened(0.45)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat_cache[key] = m
	return m


static func _plant() -> Texture2D:
	if _plant_tex == null:
		_plant_tex = ImageTexture.create_from_image(SpriteFactory.plant())
	return _plant_tex
