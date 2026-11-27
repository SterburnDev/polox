extends RefCounted
## Custom 3D Model Library: lets players import and place their own `.glb`, `.gltf`, or `.obj`
## 3D models inside any room (stored in `SaveManager.root/models/`).
##
## Models are size-checked, confined strictly to the save folder's `models/` directory, parsed at
## runtime in pure GDScript (zero dependency on stripped engine modules, so custom models work
## identically on Windows, Android, and Phone Link web builds), centered on XZ, grounded flush on
## `y = 0`, and normalized to fit cleanly onto a 1 m room cell.
## Tags: [GRAPHICS] [BUILDER]

const EXTS: PackedStringArray = ["glb", "gltf", "obj"]
const MAX_MODEL_BYTES := 24 * 1024 * 1024
const MAX_GLTF_NODES := 512
const MAX_VERTICES := 200000
const MAX_INDICES := 600000
const MAX_OBJ_TRIANGLES := 200000
const MAX_ACCESSOR_STRIDE := 256
const TARGET_SPAN := 0.92   # Fits neatly inside a 1.0 m cell without clipping neighbouring walls.

const GLB_MAGIC := 0x46546C67        # "glTF"
const GLB_CHUNK_JSON := 0x4E4F534A   # "JSON"
const GLB_CHUNK_BIN := 0x004E4942    # "BIN\0"
const COMP_U8 := 5121
const COMP_U16 := 5123
const COMP_U32 := 5125
const COMP_F32 := 5126

static var _mesh_cache: Dictionary = {}    # path -> {mtime, mesh} for .obj
static var _scene_cache: Dictionary = {}   # path -> {mtime, packed} for .glb/.gltf


static func clear_cache() -> void:
	_mesh_cache.clear()
	_scene_cache.clear()


static func models_dir() -> String:
	var dir := SaveManager.global_path("models")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## Lists all valid imported custom 3D model filenames in `SaveManager.root/models/`.
static func list_models() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := models_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for file_name in files:
		if str(file_name).get_extension().to_lower() in EXTS:
			out.append(str(file_name))
	return out


## Safely copies a user-selected `.glb`, `.gltf`, or `.obj` into `models/` and returns its filename ("" on error).
static func import_model(source_path: String) -> String:
	var clean := source_path.strip_edges()
	if clean == "" or not FileAccess.file_exists(clean):
		return ""
	var ext := clean.get_extension().to_lower()
	if not ext in EXTS:
		return ""
	var reader := FileAccess.open(clean, FileAccess.READ)
	if reader == null:
		return ""
	var byte_len := reader.get_length()
	if byte_len == 0 or byte_len > MAX_MODEL_BYTES:
		return ""
	var bytes := reader.get_buffer(byte_len)
	reader.close()

	var stem := _sanitize_stem(clean.get_file().get_basename())
	var file_name := stem + "." + ext
	var dest_dir := models_dir()
	var dest_path := dest_dir.path_join(file_name)
	var suffix := 2
	while FileAccess.file_exists(dest_path):
		file_name = "%s_%d.%s" % [stem, suffix, ext]
		dest_path = dest_dir.path_join(file_name)
		suffix += 1
	var writer := FileAccess.open(dest_path, FileAccess.WRITE)
	if writer == null:
		return ""
	writer.store_buffer(bytes)
	writer.close()
	return file_name


## Resolves a saved filename inside `models/` (rejecting any path traversal). Returns "" if missing.
static func resolve_path(model_name: String) -> String:
	var clean := model_name.strip_edges().replace("\\", "/")
	if clean == "" or clean.contains("/") or clean.contains("..") or clean.contains(":"):
		return ""
	if not clean.get_extension().to_lower() in EXTS:
		return ""
	var full := models_dir().path_join(clean)
	return full if FileAccess.file_exists(full) else ""


## Instantiates a custom 3D model, centered in XZ, grounded at y = 0, normalized to `target_size` metres.
static func instantiate(model_name: String, tint_hex: String = "", target_size: float = TARGET_SPAN) -> Node3D:
	var full_path := resolve_path(model_name)
	if full_path == "":
		return null
	var ext := full_path.get_extension().to_lower()
	var content: Node3D = null
	if ext == "obj":
		var mesh := load_obj_mesh(full_path)
		if mesh == null:
			return null
		var mi := MeshInstance3D.new()
		mi.name = "ObjMesh"
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_string(tint_hex, Color("#e8e2d6")) if tint_hex != "" else Color("#e8e2d6")
		mat.roughness = 0.55
		mat.metallic_specular = 0.45
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		content = mi
	else:
		content = _load_gltf_scene(full_path)
		if content == null:
			return null
		if tint_hex != "":
			_apply_tint(content, Color.from_string(tint_hex, Color.WHITE))

	var root := Node3D.new()
	root.name = "CustomModel"
	root.add_child(content)
	_normalize_to_cell(root, content, target_size)
	return root


# --- Pure-GDScript glTF 2.0 / GLB 2.0 Loader ----------------------------------------------------------

static func _load_gltf_scene(full_path: String) -> Node3D:
	var mtime := FileAccess.get_modified_time(full_path)
	if _scene_cache.has(full_path) and int(_scene_cache[full_path].mtime) == mtime:
		var cached_pack: PackedScene = _scene_cache[full_path].packed
		if cached_pack:
			return cached_pack.instantiate() as Node3D

	var reader := FileAccess.open(full_path, FileAccess.READ)
	if reader == null:
		return null
	var byte_len := reader.get_length()
	if byte_len == 0 or byte_len > MAX_MODEL_BYTES:
		reader.close()
		return null
	var raw := reader.get_buffer(byte_len)
	reader.close()

	var generated: Node3D = null
	if full_path.get_extension().to_lower() == "glb":
		generated = parse_glb_bytes(raw, full_path.get_base_dir())
	else:
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			generated = parse_gltf_dict(parsed as Dictionary, PackedByteArray(), full_path.get_base_dir())
	if generated == null:
		return null

	_assign_owner(generated, generated)
	var packed := PackedScene.new()
	if packed.pack(generated) == OK:
		if _scene_cache.size() >= 32:
			_scene_cache.clear()
		_scene_cache[full_path] = {"mtime": mtime, "packed": packed}
	return generated


## Parses a binary `.glb` (glTF 2.0) buffer in pure GDScript and returns a Node3D scene (null on error).
static func parse_glb_bytes(bytes: PackedByteArray, base_dir: String = "") -> Node3D:
	if bytes.size() < 20:
		return null
	if bytes.decode_u32(0) != GLB_MAGIC or bytes.decode_u32(4) != 2:
		return null
	var total_len := mini(bytes.size(), bytes.decode_u32(8))
	var json_dict: Dictionary = {}
	var bin_chunk := PackedByteArray()
	var pos := 12
	while pos + 8 <= total_len:
		var chunk_len := bytes.decode_u32(pos)
		var chunk_type := bytes.decode_u32(pos + 4)
		pos += 8
		if pos + chunk_len > total_len:
			break
		var chunk := bytes.slice(pos, pos + chunk_len)
		if chunk_type == GLB_CHUNK_JSON and json_dict.is_empty():
			var parsed: Variant = JSON.parse_string(chunk.get_string_from_utf8())
			if parsed is Dictionary:
				json_dict = parsed as Dictionary
		elif chunk_type == GLB_CHUNK_BIN and bin_chunk.is_empty():
			bin_chunk = chunk
		pos += chunk_len
	if json_dict.is_empty():
		return null
	return parse_gltf_dict(json_dict, bin_chunk, base_dir)


## Builds a Node3D hierarchy from a parsed glTF 2.0 JSON dictionary and optional embedded BIN buffer.
static func parse_gltf_dict(doc: Dictionary, bin_chunk: PackedByteArray, base_dir: String = "") -> Node3D:
	var buffers := _resolve_gltf_buffers(doc.get("buffers", []), bin_chunk, base_dir)
	var buffer_views: Array = doc.get("bufferViews", []) if doc.get("bufferViews") is Array else []
	var accessors: Array = doc.get("accessors", []) if doc.get("accessors") is Array else []
	var materials := _build_gltf_materials(doc.get("materials", []))
	var meshes_def: Array = doc.get("meshes", []) if doc.get("meshes") is Array else []
	var built_meshes: Array = []
	for mesh_entry in meshes_def:
		built_meshes.append(_build_gltf_mesh(mesh_entry, accessors, buffer_views, buffers, materials) if mesh_entry is Dictionary else null)

	var root := Node3D.new()
	root.name = "GltfModel"
	var nodes_def: Array = doc.get("nodes", []) if doc.get("nodes") is Array else []
	var added_any := false

	if not nodes_def.is_empty():
		var root_indices: Array = []
		var scenes_def: Array = doc.get("scenes", []) if doc.get("scenes") is Array else []
		var active_scene := int(doc.get("scene", 0))
		if active_scene >= 0 and active_scene < scenes_def.size() and scenes_def[active_scene] is Dictionary:
			var snodes: Variant = (scenes_def[active_scene] as Dictionary).get("nodes", [])
			if snodes is Array:
				root_indices = snodes
		if root_indices.is_empty():
			for idx in nodes_def.size():
				root_indices.append(idx)
		for idx in root_indices:
			var child := _build_gltf_node(int(idx), nodes_def, built_meshes, 0, {"nodes": 0}, {})
			if child:
				root.add_child(child)
				added_any = true
	else:
		for i in built_meshes.size():
			var m: ArrayMesh = built_meshes[i]
			if m != null:
				var mi := MeshInstance3D.new()
				mi.name = "Mesh_%d" % i
				mi.mesh = m
				root.add_child(mi)
				added_any = true

	if not added_any or root.find_children("*", "MeshInstance3D", true, false).is_empty():
		root.free()
		return null
	return root


static func _resolve_gltf_buffers(buffers_def: Variant, bin_chunk: PackedByteArray, base_dir: String) -> Array:
	var out: Array = []
	if not buffers_def is Array:
		return out
	var total_bytes := 0
	for i in (buffers_def as Array).size():
		var entry: Variant = (buffers_def as Array)[i]
		if not entry is Dictionary:
			out.append(PackedByteArray())
			continue
		var uri := str((entry as Dictionary).get("uri", ""))
		if uri == "":
			if bin_chunk.size() <= MAX_MODEL_BYTES and total_bytes + bin_chunk.size() <= MAX_MODEL_BYTES:
				total_bytes += bin_chunk.size()
				out.append(bin_chunk if i == 0 else PackedByteArray())
			else:
				out.append(PackedByteArray())
		elif uri.begins_with("data:"):
			var comma := uri.find(",")
			if comma >= 0 and uri.length() - comma - 1 <= (MAX_MODEL_BYTES * 4) / 3 + 128:
				var decoded := Marshalls.base64_to_raw(uri.substr(comma + 1))
				if total_bytes + decoded.size() <= MAX_MODEL_BYTES:
					total_bytes += decoded.size()
					out.append(decoded)
					continue
			out.append(PackedByteArray())
		elif base_dir != "" and not uri.contains("..") and not uri.contains("/") and not uri.contains("\\") and not uri.contains(":"):
			var bin_path := base_dir.path_join(uri)
			if FileAccess.file_exists(bin_path):
				var f := FileAccess.open(bin_path, FileAccess.READ)
				if f and f.get_length() <= MAX_MODEL_BYTES and total_bytes + f.get_length() <= MAX_MODEL_BYTES:
					var buf := f.get_buffer(f.get_length())
					total_bytes += buf.size()
					out.append(buf)
					f.close()
					continue
				if f:
					f.close()
			out.append(PackedByteArray())
		else:
			out.append(PackedByteArray())
	return out


static func _build_gltf_materials(mats_def: Variant) -> Array:
	var out: Array = []
	if not mats_def is Array:
		return out
	for entry in mats_def as Array:
		var mat := StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.6
		if entry is Dictionary:
			var d := entry as Dictionary
			var pbr: Variant = d.get("pbrMetallicRoughness", {})
			if pbr is Dictionary:
				var pd := pbr as Dictionary
				var base_col: Variant = pd.get("baseColorFactor", [])
				if base_col is Array and (base_col as Array).size() >= 3:
					var a := float(base_col[3]) if (base_col as Array).size() >= 4 else 1.0
					mat.albedo_color = Color(float(base_col[0]), float(base_col[1]), float(base_col[2]), a)
					if a < 0.99:
						mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.metallic = clampf(float(pd.get("metallicFactor", 0.0)), 0.0, 1.0)
				mat.roughness = clampf(float(pd.get("roughnessFactor", 0.65)), 0.05, 1.0)
			var em: Variant = d.get("emissiveFactor", [])
			if em is Array and (em as Array).size() >= 3:
				var ec := Color(float(em[0]), float(em[1]), float(em[2]))
				if ec.r > 0.01 or ec.g > 0.01 or ec.b > 0.01:
					mat.emission_enabled = true
					mat.emission = ec
		out.append(mat)
	return out


static func _build_gltf_mesh(mesh_def: Dictionary, accessors: Array, views: Array, buffers: Array, materials: Array) -> ArrayMesh:
	var prims: Variant = mesh_def.get("primitives", [])
	if not prims is Array or (prims as Array).is_empty():
		return null
	var mesh := ArrayMesh.new()
	var added_surface := false
	for prim in prims as Array:
		if not prim is Dictionary:
			continue
		var pd := prim as Dictionary
		if int(pd.get("mode", 4)) != 4:
			continue   # Only triangle primitives
		var attrs: Variant = pd.get("attributes", {})
		if not attrs is Dictionary or not (attrs as Dictionary).has("POSITION"):
			continue
		var positions := _read_vec3_accessor(int((attrs as Dictionary)["POSITION"]), accessors, views, buffers)
		if positions.is_empty():
			continue
		var normals := _read_vec3_accessor(int((attrs as Dictionary)["NORMAL"]), accessors, views, buffers) \
			if (attrs as Dictionary).has("NORMAL") else PackedVector3Array()
		var uvs := _read_vec2_accessor(int((attrs as Dictionary)["TEXCOORD_0"]), accessors, views, buffers) \
			if (attrs as Dictionary).has("TEXCOORD_0") else PackedVector2Array()
		var indices := _read_index_accessor(int(pd["indices"]), accessors, views, buffers) \
			if pd.has("indices") else PackedInt32Array()

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var has_normals := normals.size() == positions.size()
		var has_uvs := uvs.size() == positions.size()
		if not indices.is_empty():
			for idx in indices:
				if idx < 0 or idx >= positions.size():
					continue
				if has_uvs:
					st.set_uv(uvs[idx])
				if has_normals:
					st.set_normal(normals[idx])
				st.add_vertex(positions[idx])
		else:
			for idx in positions.size():
				if has_uvs:
					st.set_uv(uvs[idx])
				if has_normals:
					st.set_normal(normals[idx])
				st.add_vertex(positions[idx])
		if not has_normals:
			st.generate_normals()
		var mat_idx := int(pd.get("material", -1))
		if mat_idx >= 0 and mat_idx < materials.size():
			st.set_material(materials[mat_idx])
		else:
			var fallback_mat := StandardMaterial3D.new()
			fallback_mat.albedo_color = Color("#e8e2d6")
			fallback_mat.roughness = 0.55
			fallback_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			st.set_material(fallback_mat)
		st.commit(mesh)
		added_surface = true
	return mesh if added_surface else null


static func _build_gltf_node(idx: int, nodes_def: Array, meshes: Array, depth: int, state: Dictionary = {}, ancestors: Dictionary = {}) -> Node3D:
	if depth > 24 or idx < 0 or idx >= nodes_def.size() or not nodes_def[idx] is Dictionary:
		return null
	if ancestors.has(idx) or int(state.get("nodes", 0)) >= MAX_GLTF_NODES:
		return null
	state["nodes"] = int(state.get("nodes", 0)) + 1
	ancestors[idx] = true
	var nd := nodes_def[idx] as Dictionary
	var node: Node3D
	var mesh_idx := int(nd.get("mesh", -1))
	if mesh_idx >= 0 and mesh_idx < meshes.size() and meshes[mesh_idx] != null:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[mesh_idx]
		node = mi
	else:
		node = Node3D.new()
	node.name = _sanitize_stem(str(nd.get("name", "Node_%d" % idx)))
	node.transform = _gltf_node_transform(nd)
	var children: Variant = nd.get("children", [])
	if children is Array:
		for child_idx in children as Array:
			var child := _build_gltf_node(int(child_idx), nodes_def, meshes, depth + 1, state, ancestors)
			if child:
				node.add_child(child)
	ancestors.erase(idx)
	return node


static func _gltf_node_transform(nd: Dictionary) -> Transform3D:
	var mat_arr: Variant = nd.get("matrix", [])
	if mat_arr is Array and (mat_arr as Array).size() == 16:
		var m: Array = mat_arr
		var basis := Basis(
			Vector3(float(m[0]), float(m[1]), float(m[2])),
			Vector3(float(m[4]), float(m[5]), float(m[6])),
			Vector3(float(m[8]), float(m[9]), float(m[10]))
		)
		var origin := Vector3(float(m[12]), float(m[13]), float(m[14]))
		return Transform3D(basis, origin)
	var t := Vector3.ZERO
	var tr: Variant = nd.get("translation", [])
	if tr is Array and (tr as Array).size() >= 3:
		t = Vector3(float(tr[0]), float(tr[1]), float(tr[2]))
	var q := Quaternion.IDENTITY
	var rot: Variant = nd.get("rotation", [])
	if rot is Array and (rot as Array).size() >= 4:
		q = Quaternion(float(rot[0]), float(rot[1]), float(rot[2]), float(rot[3])).normalized()
	var s := Vector3.ONE
	var sc: Variant = nd.get("scale", [])
	if sc is Array and (sc as Array).size() >= 3:
		s = Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	return Transform3D(Basis(q).scaled(s), t)


static func _accessor_span(acc_idx: int, accessors: Array, views: Array, buffers: Array, default_stride: int, max_count: int = MAX_VERTICES) -> Dictionary:
	if acc_idx < 0 or acc_idx >= accessors.size() or not accessors[acc_idx] is Dictionary:
		return {}
	var acc := accessors[acc_idx] as Dictionary
	var bv_idx := int(acc.get("bufferView", -1))
	if bv_idx < 0 or bv_idx >= views.size() or not views[bv_idx] is Dictionary:
		return {}
	var bv := views[bv_idx] as Dictionary
	var buf_idx := int(bv.get("buffer", 0))
	if buf_idx < 0 or buf_idx >= buffers.size():
		return {}
	var buf: PackedByteArray = buffers[buf_idx]
	var stride := int(bv.get("byteStride", 0))
	if stride <= 0:
		stride = default_stride
	if stride < default_stride or stride > MAX_ACCESSOR_STRIDE:
		return {}
	var offset := int(bv.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
	var count := int(acc.get("count", 0))
	if offset < 0 or count <= 0 or count > max_count:
		return {}
	return {
		"buf": buf,
		"offset": offset,
		"stride": stride,
		"count": count,
		"comp": int(acc.get("componentType", 0)),
	}


static func _read_vec3_accessor(acc_idx: int, accessors: Array, views: Array, buffers: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var span := _accessor_span(acc_idx, accessors, views, buffers, 12)
	if span.is_empty() or int(span.comp) != COMP_F32:
		return out
	var buf: PackedByteArray = span.buf
	var off: int = span.offset
	var stride: int = span.stride
	var count: int = span.count
	if off < 0 or count <= 0 or off + (count - 1) * stride + 12 > buf.size():
		return out
	out.resize(count)
	for i in count:
		var p := off + i * stride
		out[i] = Vector3(buf.decode_float(p), buf.decode_float(p + 4), buf.decode_float(p + 8))
	return out


static func _read_vec2_accessor(acc_idx: int, accessors: Array, views: Array, buffers: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var span := _accessor_span(acc_idx, accessors, views, buffers, 8)
	if span.is_empty() or int(span.comp) != COMP_F32:
		return out
	var buf: PackedByteArray = span.buf
	var off: int = span.offset
	var stride: int = span.stride
	var count: int = span.count
	if off < 0 or count <= 0 or off + (count - 1) * stride + 8 > buf.size():
		return out
	out.resize(count)
	for i in count:
		var p := off + i * stride
		out[i] = Vector2(buf.decode_float(p), buf.decode_float(p + 4))
	return out


static func _read_index_accessor(acc_idx: int, accessors: Array, views: Array, buffers: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if acc_idx < 0 or acc_idx >= accessors.size() or not accessors[acc_idx] is Dictionary:
		return out
	var comp := int((accessors[acc_idx] as Dictionary).get("componentType", COMP_U16))
	var elem_bytes := 1 if comp == COMP_U8 else (2 if comp == COMP_U16 else (4 if comp == COMP_U32 else 0))
	if elem_bytes == 0:
		return out
	var span := _accessor_span(acc_idx, accessors, views, buffers, elem_bytes, MAX_INDICES)
	if span.is_empty():
		return out
	var buf: PackedByteArray = span.buf
	var off: int = span.offset
	var stride: int = span.stride
	var count: int = span.count
	if off < 0 or count <= 0 or off + (count - 1) * stride + elem_bytes > buf.size():
		return out
	out.resize(count)
	for i in count:
		var p := off + i * stride
		match comp:
			COMP_U8:
				out[i] = buf.decode_u8(p)
			COMP_U16:
				out[i] = buf.decode_u16(p)
			COMP_U32:
				out[i] = buf.decode_u32(p)
	return out


static func _assign_owner(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		_assign_owner(child, owner_root)


# --- Pure-GDScript Wavefront OBJ Loader ---------------------------------------------------------------

## Pure-GDScript Wavefront `.obj` parser (vertices, UVs, normals, triangles/quads/n-gons).
static func load_obj_mesh(full_path: String) -> ArrayMesh:
	if not FileAccess.file_exists(full_path):
		return null
	var mtime := FileAccess.get_modified_time(full_path)
	if _mesh_cache.has(full_path) and int(_mesh_cache[full_path].mtime) == mtime:
		return _mesh_cache[full_path].mesh
	var text := FileAccess.get_file_as_string(full_path)
	var mesh := parse_obj_text(text)
	if mesh:
		if _mesh_cache.size() >= 32:
			_mesh_cache.clear()
		_mesh_cache[full_path] = {"mtime": mtime, "mesh": mesh}
	return mesh


## Parses Wavefront OBJ text into an ArrayMesh with normals (safe & testable without disk I/O).
static func parse_obj_text(text: String) -> ArrayMesh:
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_explicit_normals := false
	var tri_count := 0

	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		if parts.is_empty():
			continue
		match parts[0]:
			"v":
				if parts.size() >= 4:
					if positions.size() >= MAX_VERTICES:
						return null
					positions.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
			"vt":
				if parts.size() >= 3:
					if uvs.size() >= MAX_VERTICES:
						return null
					uvs.append(Vector2(parts[1].to_float(), 1.0 - parts[2].to_float()))
			"vn":
				if parts.size() >= 4:
					if normals.size() >= MAX_VERTICES:
						return null
					normals.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()).normalized())
			"f":
				if parts.size() < 4:
					continue
				var face_verts: Array = []
				for idx in range(1, parts.size()):
					var parsed := _parse_face_corner(parts[idx], positions.size(), uvs.size(), normals.size())
					if parsed[0] >= 0:
						face_verts.append(parsed)
				# Fan triangulation for triangles, quads, and convex polygons.
				for k in range(1, face_verts.size() - 1):
					if tri_count >= MAX_OBJ_TRIANGLES:
						return null
					for corner in [face_verts[0], face_verts[k], face_verts[k + 1]]:
						var vi: int = corner[0]
						var ti: int = corner[1]
						var ni: int = corner[2]
						if ti >= 0 and ti < uvs.size():
							st.set_uv(uvs[ti])
						if ni >= 0 and ni < normals.size():
							st.set_normal(normals[ni])
							has_explicit_normals = true
						st.add_vertex(positions[vi])
					tri_count += 1

	if tri_count == 0:
		return null
	if not has_explicit_normals:
		st.generate_normals()
	return st.commit()


static func _parse_face_corner(token: String, v_len: int, vt_len: int, vn_len: int) -> Array:
	var comps := token.split("/")
	var vi := _obj_index(comps[0].to_int(), v_len) if comps.size() >= 1 and comps[0] != "" else -1
	var ti := _obj_index(comps[1].to_int(), vt_len) if comps.size() >= 2 and comps[1] != "" else -1
	var ni := _obj_index(comps[2].to_int(), vn_len) if comps.size() >= 3 and comps[2] != "" else -1
	return [vi, ti, ni]


static func _obj_index(raw: int, length: int) -> int:
	if raw > 0 and raw <= length:
		return raw - 1
	if raw < 0 and length + raw >= 0:
		return length + raw
	return -1


# --- Normalization & Tinting --------------------------------------------------------------------------

static func _apply_tint(root: Node, tint: Color) -> void:
	var meshes: Array = [root] if root is MeshInstance3D else []
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for surf in mi.mesh.get_surface_count():
			var base := mi.get_active_material(surf)
			if base is BaseMaterial3D:
				var copy := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
				copy.albedo_color = copy.albedo_color * tint
				mi.set_surface_override_material(surf, copy)


static func _normalize_to_cell(root: Node3D, content: Node3D, target_span: float) -> void:
	var bounds := AABB()
	var has_bounds := false
	var meshes: Array = [content] if content is MeshInstance3D else []
	meshes.append_array(content.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xform := mi.transform
		var parent := mi.get_parent()
		while parent != null and parent != root:
			if parent is Node3D:
				xform = (parent as Node3D).transform * xform
			parent = parent.get_parent()
		var box: AABB = xform * mi.get_aabb()
		bounds = box if not has_bounds else bounds.merge(box)
		has_bounds = true
	if not has_bounds:
		return
	var max_dim := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var scale_factor := target_span / maxf(max_dim, 0.001)
	content.scale *= scale_factor
	content.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * scale_factor


static func _sanitize_stem(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges().left(48):
		if ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_":
			out += ch
		elif ch == " ":
			out += "_"
	return out if out != "" else "custom_model"
