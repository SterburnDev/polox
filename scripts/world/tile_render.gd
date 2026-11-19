extends Node3D
## Draws a room's tile layers. Each layer is cut into 16x16-cell chunks and
## each chunk draws as ONE mesh per tile set it uses (that set's atlas, nearest
## filtering): a 100x100 floor is about 50 draw calls. Painting marks only the
## touched chunks, which are rebuilt on the next frame. Standing pictures turn
## to face the camera and animated tiles play in the shader (no per-frame CPU
## work). Foreground tiles that fade when hiding a person stay separate quads,
## since each needs its own see-through amount.

const TileLayers := preload("res://scripts/world/tile_layers.gd")
const TileAtlas := preload("res://scripts/world/tile_atlas.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const SHADER := preload("res://shaders/tile.gdshader")
const SHADER_ALPHA := preload("res://shaders/tile_alpha.gdshader")

const FADE_TO := 0.65           # how see-through a hiding Foreground tile becomes
const FADE_SPEED := 6.0
const CHUNK := 16
const LIFT := {"backdrop": 0.01, "ground": 0.003, "blocks": 0.0, "foreground": 0.004}
const CORNERS := [Vector3(-0.5, 0.5, 0), Vector3(0.5, 0.5, 0), Vector3(0.5, -0.5, 0), Vector3(-0.5, -0.5, 0)]

var room: Dictionary = {}
var build_ms := 0.0              # how long the last full build took
var _layer_nodes := {}           # layer id -> Node3D
var _chunks := {}                # "layer|cx,cz" -> {set id: MeshInstance3D}
var _chunk_fades := {}           # "layer|cx,cz" -> [MeshInstance3D]
var _dirty := {}                 # "layer|cx,cz" -> true
var _materials := {}             # "set|opacity" -> ShaderMaterial
var _fade_materials := {}        # "set|tile|tint|standing|opacity" -> StandardMaterial3D
var _anims: Array = []           # [StandardMaterial3D, [Texture2D], fps] for the separate quads
var _fade_quads: Array = []
var _anim_t := 0.0
var _quad_plain: ArrayMesh
var _quad_flipped: ArrayMesh


func _ready() -> void:
	_quad_plain = _quad(false)
	_quad_flipped = _quad(true)


## Draws every tile layer of a room from scratch.
func build(r: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	room = r
	for c in get_children():
		c.free()
	_layer_nodes.clear()
	_chunks.clear()
	_chunk_fades.clear()
	_dirty.clear()
	_anims.clear()
	_fade_quads.clear()
	_fade_materials.clear()
	if _quad_plain == null:
		_ready()
	for l in TileLayers.all(room):
		var node := Node3D.new()
		node.name = "Layer_%s" % str(l.id)
		node.visible = bool(l.visible)
		add_child(node)
		_layer_nodes[str(l.id)] = node
		var chunk_keys := {}
		for k in l.cells:
			chunk_keys[_chunk_of(TileLayers.parse_key(str(k)))] = true
		for ck in chunk_keys:
			_build_chunk(l, ck)
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


static func _chunk_of(c: Vector2i) -> Vector2i:
	return Vector2i(floori(c.x / float(CHUNK)), floori(c.y / float(CHUNK)))


## After an edit: only the chunks of these cells are drawn again (next frame, or now with flush()).
func cells_changed(layer_id: String, cells: Array) -> void:
	for c in cells:
		var ck := _chunk_of(c)
		_dirty["%s|%d,%d" % [layer_id, ck.x, ck.y]] = true


func flush() -> void:
	var keys := _dirty.keys()
	_dirty.clear()
	for k in keys:
		var bar := str(k).rfind("|")
		var id := str(k).substr(0, bar)
		var l := TileLayers.find(room, id)
		var ck := TileLayers.parse_key(str(k).substr(bar + 1))
		if l.is_empty() or not _layer_nodes.has(id):
			build(room)   # a layer came or went: draw everything again
			return
		_build_chunk(l, ck)


func _process(delta: float) -> void:
	if not _dirty.is_empty():
		flush()
	_anim_t += delta
	for a in _anims:
		var texs: Array = a[1]
		var frame := int(_anim_t * float(a[2])) % texs.size()
		if a[0].albedo_texture != texs[frame]:
			a[0].albedo_texture = texs[frame]


func _build_chunk(l: Dictionary, ck: Vector2i) -> void:
	var key := "%s|%d,%d" % [str(l.id), ck.x, ck.y]
	for mi in (_chunks.get(key, {}) as Dictionary).values():
		if is_instance_valid(mi):
			mi.free()
	for mi in _chunk_fades.get(key, []):
		if is_instance_valid(mi):
			_fade_quads.erase(mi)
			mi.free()
	_chunks.erase(key)
	_chunk_fades.erase(key)
	var node: Node3D = _layer_nodes[str(l.id)]
	var groups := {}
	var fades: Array = []
	var cells: Dictionary = l.cells
	var x0 := ck.x * CHUNK
	var z0 := ck.y * CHUNK
	var fg := str(l.type) == "foreground"
	for dz in CHUNK:
		for dx in CHUNK:
			var cell: Variant = cells.get(TileLayers.key(x0 + dx, z0 + dz))
			if cell == null:
				continue
			if fg and _fades(cell):
				var q := _fade_quad(l, x0 + dx, z0 + dz, cell)
				if q:
					node.add_child(q)
					fades.append(q)
				continue
			var s := str(cell.s)
			if not groups.has(s):
				groups[s] = []
			groups[s].append([x0 + dx, z0 + dz, cell])
	var made := {}
	var opacity := clampf(float(l.get("opacity", 1.0)), 0.0, 1.0)
	for set_id in groups:
		var atlas := TileAtlas.for_set(str(set_id))
		if atlas.is_empty():
			continue
		var mesh := _mesh(l, atlas, groups[set_id])
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _material(str(set_id), atlas, opacity)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
		made[set_id] = mi
	if not made.is_empty():
		_chunks[key] = made
	if not fades.is_empty():
		_chunk_fades[key] = fades


func _fades(cell: Dictionary) -> bool:
	if cell.has("fade"):
		return bool(cell.fade)
	return bool(Tilesets.info(str(cell.s), str(cell.t)).get("fade", true))


## One mesh for many tiles of one set: 4 corners per tile, the atlas UVs,
## the tint, the centre (+ "stands up") and the animation (frames, fps, step).
func _mesh(l: Dictionary, atlas: Dictionary, entries: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	var type := str(l.type)
	var lift := float(LIFT.get(type, 0.0))
	var frame_u := float(atlas.tp) / float(atlas.w)
	for e in entries:
		var cell: Dictionary = e[2]
		var uv := TileAtlas.uv_rect(atlas, str(cell.t))
		if uv.is_empty():
			continue
		var slot: Array = atlas.slots[str(cell.t)]
		var orient := TileLayers.orient_of(l, cell)
		var level := TileLayers.level_of(l, cell)
		var rot := int(cell.get("r", 0))
		var xf := orient_transform(orient, int(e[0]), level, int(e[1]), rot, lift)
		var standing := orient == "standing"
		var u0: float = uv[2] if bool(cell.get("fl", false)) else uv[0]
		var u1: float = uv[0] if bool(cell.get("fl", false)) else uv[2]
		var quad_uv := [Vector2(u0, uv[1]), Vector2(u1, uv[1]), Vector2(u1, uv[3]), Vector2(u0, uv[3])]
		var tint := Color.from_string(str(cell.get("tint", "#ffffff")), Color.WHITE)
		var n := xf.basis * Vector3(0, 0, 1)
		var base := verts.size()
		for i in 4:
			verts.append(xf * CORNERS[i])
			normals.append(n)
			uvs.append(quad_uv[i])
			cols.append(tint)
			c0.append_array([xf.origin.x, xf.origin.y, xf.origin.z, 1.0 if standing else 0.0])
			c1.append_array([float(slot[1]), float(slot[2]), frame_u, 0.0])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_INDEX] = idx
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


func _material(set_id: String, atlas: Dictionary, opacity: float) -> ShaderMaterial:
	var key := "%s|%.2f" % [set_id, opacity]
	var m: ShaderMaterial = _materials.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = SHADER if opacity >= 0.999 else SHADER_ALPHA
		_materials[key] = m
	m.set_shader_parameter("atlas", atlas.texture)
	m.set_shader_parameter("opacity", opacity)
	return m


## Where a 1x1 picture goes: flat on the floor, on one of the four wall faces of
## its cell, or standing in the middle (and turning to face the camera).
static func orient_transform(orient: String, x: int, y: int, z: int, rot: int, lift: float) -> Transform3D:
	var spin := Basis.from_euler(Vector3(0, 0, rot * PI / 2.0))   # turn the picture in its own plane
	match orient:
		"floor":
			return Transform3D(Basis.from_euler(Vector3(-PI / 2.0, rot * PI / 2.0, 0)), Vector3(x + 0.5, y + lift + 0.002, z + 0.5))
		"wall_n":
			return Transform3D(Basis.IDENTITY * spin, Vector3(x + 0.5, y + 0.5, z + 0.02 + lift))
		"wall_s":
			return Transform3D(Basis.from_euler(Vector3(0, PI, 0)) * spin, Vector3(x + 0.5, y + 0.5, z + 0.98 - lift))
		"wall_e":
			return Transform3D(Basis.from_euler(Vector3(0, -PI / 2.0, 0)) * spin, Vector3(x + 0.98 - lift, y + 0.5, z + 0.5))
		"wall_w":
			return Transform3D(Basis.from_euler(Vector3(0, PI / 2.0, 0)) * spin, Vector3(x + 0.02 + lift, y + 0.5, z + 0.5))
	return Transform3D(spin, Vector3(x + 0.5, y + 0.5, z + 0.5))


# --- Separate quads (fading Foreground tiles) --------------------------------------------------

func _fade_quad(l: Dictionary, x: int, z: int, cell: Dictionary) -> MeshInstance3D:
	var orient := TileLayers.orient_of(l, cell)
	var opacity := clampf(float(l.get("opacity", 1.0)), 0.0, 1.0)
	var mat := _fade_material(str(cell.s), str(cell.t), str(cell.get("tint", "#ffffff")), orient == "standing", opacity)
	if mat == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = _quad_flipped if bool(cell.get("fl", false)) else _quad_plain
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = orient_transform(orient, x, TileLayers.level_of(l, cell), z, int(cell.get("r", 0)), float(LIFT.foreground))
	mi.set_meta("standing", orient == "standing")
	_fade_quads.append(mi)
	return mi


func _fade_material(set_id: String, tile_id: String, tint: String, standing: bool, opacity: float) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%.2f" % [set_id, tile_id, tint, standing, opacity]
	if _fade_materials.has(key):
		return _fade_materials[key]
	var img := Tilesets.tile_image(set_id, tile_id)
	var tex: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	if tex == null:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color.from_string(tint, Color.WHITE)
	m.albedo_color.a = opacity
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if opacity >= 0.999 else BaseMaterial3D.TRANSPARENCY_ALPHA
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	if standing:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
	_fade_materials[key] = m
	var t := Tilesets.info(set_id, tile_id)
	var frames: Array = t.get("frames", [])
	if not frames.is_empty():
		var texs: Array = [tex]
		for i in frames.size():
			var frame_img := Tilesets.tile_image(set_id, tile_id, i + 1)
			if frame_img:
				texs.append(ImageTexture.create_from_image(frame_img))
		if texs.size() > 1:
			_anims.append([m, texs, maxf(1.0, float(t.get("fps", 4)))])
	return m


## Fades Foreground tiles that sit between the camera and someone.
func update_fade(people: Array, camera: Camera3D, delta: float) -> void:
	if _fade_quads.is_empty() or camera == null:
		return
	var cam_pos := camera.global_position
	for mi in _fade_quads:
		if not is_instance_valid(mi):
			continue
		var hiding := false
		var xf: Transform3D = mi.global_transform
		if bool(mi.get_meta("standing", false)):
			var to_cam := (cam_pos - xf.origin) * Vector3(1, 0, 1)
			if to_cam.length() > 0.001:
				xf = Transform3D(Basis.looking_at(-to_cam.normalized(), Vector3.UP), xf.origin)
		var inv := xf.affine_inverse()
		for p in people:
			if not is_instance_valid(p):
				continue
			var a: Vector3 = inv * cam_pos
			var b: Vector3 = inv * (p.global_position + Vector3(0, 0.65, 0))
			if (a.z > 0.0) == (b.z > 0.0):
				continue
			var t := a.z / (a.z - b.z)
			var hit := a + (b - a) * t
			if absf(hit.x) <= 0.5 and absf(hit.y) <= 0.5:
				hiding = true
				break
		var target := FADE_TO if hiding else 0.0
		mi.transparency = lerpf(mi.transparency, target, 1.0 - exp(-FADE_SPEED * delta))


## Is any Foreground tile currently faded (for tests)?
func faded_count() -> int:
	var n := 0
	for mi in _fade_quads:
		if is_instance_valid(mi) and mi.transparency > 0.3:
			n += 1
	return n


## Meshes drawn (chunk meshes + separate quads): what the stress test budgets.
func draw_calls() -> int:
	var n := _fade_quads.size()
	for k in _chunks:
		n += (_chunks[k] as Dictionary).size()
	return n


func chunk_count() -> int:
	return _chunks.size()


## A 1x1 quad facing +Z with the picture the right way up (and optionally mirrored).
static func _quad(flip: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u0 := 1.0 if flip else 0.0
	var u1 := 0.0 if flip else 1.0
	var uvs := [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(uvs[i])
		st.add_vertex(CORNERS[i])
	return st.commit()
