extends Node3D
## The see-through preview under the build cursor: the piece or picture
## about to be placed (green = fits, red = blocked), highlighted cells for
## brushes and shapes, and the selection outline.
## [BUILDER] [GLASS_UI] Grounded and easy to read: a soft shadow under the piece (it sits on the floor,
## not floating), a crisp footprint frame in the fit colour, and the selection as a thick frame with
## corner marks. Frames are two-tone (a dark edge round a bright line), drawn over everything, so they
## read on a pale floor and a dark one alike.

const BlockFactory := preload("res://scripts/world/block_factory.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const TileRender := preload("res://scripts/world/tile_render.gd")

var _shape: Node3D
var _cells: MultiMeshInstance3D
var _sel: MeshInstance3D
var _room_origin := Vector3.ZERO
var _shadow: MeshInstance3D       # the soft shadow under the piece
var _foot: MeshInstance3D         # the footprint frame
var _foot_mat: StandardMaterial3D


func _ready() -> void:
	_cells = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.96, 0.05, 0.96)
	mm.mesh = box
	_cells.multimesh = mm
	_cells.material_override = _flat(Color(1, 0.82, 0.4, 0.4))
	_cells.top_level = true
	add_child(_cells)
	_sel = MeshInstance3D.new()
	_sel.material_override = _frame_material(Color.WHITE)
	_sel.top_level = true
	add_child(_sel)
	_shadow = MeshInstance3D.new()
	_shadow.name = "GhostShadow"
	var q := QuadMesh.new()
	q.size = Vector2(1.15, 1.15)
	q.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = q
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = _soft_dot()
	sm.albedo_color = Color(0, 0, 0, 0.5)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = sm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	_foot = MeshInstance3D.new()
	_foot.name = "Footprint"
	_foot.mesh = frame_mesh(Vector2(-0.5, -0.5), Vector2(0.5, 0.5), 0.05, Color(0.5, 1.0, 0.6))
	_foot_mat = _frame_material(Color.WHITE)
	_foot.material_override = _foot_mat
	_foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_foot)


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Rebuilds the preview from the editor's state.
func show_for(b: Node) -> void:
	if _shape:
		_shape.queue_free()
		_shape = null
	if b.tool in ["place", "brush", "line", "rect", "rect_outline", "fill", "stamp"]:
		if b.piece == "tile" and b.brush_set != "":
			_shape = _tile_quad(b)
		elif b.piece != "tile":
			var spec := {"type": b.piece, "color": b.color, "texture": b.texture, "rot": b.rot}
			_shape = BlockFactory.make_tile(spec) if b.piece in BlockFactory.TILE_TYPES else BlockFactory.make_object(spec)
	if _shape == null:
		_shape = BlockFactory.make_tile({"type": "slab", "color": "#ffffff"})
		_shape.scale = Vector3(1.02, 0.08, 1.02)
	_strip_bodies(_shape)
	add_child(_shape)
	if _shadow:
		_shadow.visible = b.piece != "tile"   # (a flat picture tile lies on the floor: no shadow)


## A picture tile preview, flat or standing like it will be placed.
func _tile_quad(b: Node) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = TileRender._quad(b.flip)
	var m := StandardMaterial3D.new()
	m.albedo_texture = SaveManager.load_texture(Tilesets.tile_path(b.brush_set, b.brush_tile))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	var flat: bool = b.layer_type() == "ground" or b.orient == "floor"
	if flat:
		mi.rotation = Vector3(-PI / 2.0, b.rot * PI / 2.0, 0)
		mi.position.y = 0.01
	else:
		mi.position.y = 0.5
		mi.rotation.z = b.rot * PI / 2.0
		match b.orient:
			"wall_s":
				mi.rotation.y = PI
			"wall_e":
				mi.rotation.y = -PI / 2.0
			"wall_w":
				mi.rotation.y = PI / 2.0
	root.add_child(mi)
	return root


## Ghosts must never catch clicks or raycasts.
func _strip_bodies(n: Node) -> void:
	for c in n.get_children():
		if c is StaticBody3D:
			c.free()
		else:
			_strip_bodies(c)


func move_to(pos: Vector3, tint: Color, cells: Array = [], selection: Rect2i = Rect2i()) -> void:
	position = pos
	if _shape:
		_tint(_shape, tint)
	# The frame takes the fit colour (green fits, red is blocked, yolk for edit and select).
	_foot.mesh = frame_mesh(Vector2(-0.5, -0.5), Vector2(0.5, 0.5), 0.05, Color(tint, 1.0))
	_foot.position.y = 0.03
	_shadow.position.y = 0.015
	var mm := _cells.multimesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var c: Vector2i = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(c.x + 0.5, 0.03, c.y + 0.5)))
	_cells.visible = not cells.is_empty()
	if selection.size.x > 0 and selection.size.y > 0:
		var p0 := Vector2(selection.position.x, selection.position.y)
		var p1 := p0 + Vector2(selection.size.x, selection.size.y)
		_sel.mesh = frame_mesh(p0, p1, 0.07, Color("#ffd166"), true)
		_sel.position = Vector3(0, 0.06, 0)
		_sel.visible = true
	else:
		_sel.visible = false


func _tint(n: Node, c: Color) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D and ch.material_override and ch.material_override.albedo_texture:
			ch.material_override.albedo_color = Color(1, 1, 1, c.a + 0.25)
		elif ch is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ch.material_override = m
		elif ch is Sprite3D:
			ch.modulate = c
		_tint(ch, c)


## A flat frame on the floor from `p0` to `p1` (x, z): a bright band `w` wide inside a dark edge, as
## one mesh with vertex colours; `corners` adds short marks outside each corner (the selection).
static func frame_mesh(p0: Vector2, p1: Vector2, w: float, col: Color, corners: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := Color(0.05, 0.04, 0.1, 0.85)
	_band(st, p0, p1, w * 1.9, dark)
	_band(st, p0 + Vector2(w * 0.45, w * 0.45), p1 - Vector2(w * 0.45, w * 0.45), w, Color(col, 0.95))
	if corners:
		var m := w * 3.0
		for c in [p0, Vector2(p1.x, p0.y), p1, Vector2(p0.x, p1.y)]:
			var sx := -1.0 if c.x == p0.x else 1.0
			var sy := -1.0 if c.y == p0.y else 1.0
			_quad(st, c + Vector2(sx * w, sy * w) * 0.5, c + Vector2(sx * (w + m), sy * w * 1.5), Color(col, 0.95))
			_quad(st, c + Vector2(sx * w, sy * w) * 0.5, c + Vector2(sx * w * 1.5, sy * (w + m)), Color(col, 0.95))
	return st.commit()


## The four sides of a rectangle, `w` wide, inward from its edge.
static func _band(st: SurfaceTool, p0: Vector2, p1: Vector2, w: float, c: Color) -> void:
	_quad(st, p0, Vector2(p1.x, p0.y + w), c)
	_quad(st, Vector2(p0.x, p1.y - w), p1, c)
	_quad(st, Vector2(p0.x, p0.y + w), Vector2(p0.x + w, p1.y - w), c)
	_quad(st, Vector2(p1.x - w, p0.y + w), Vector2(p1.x, p1.y - w), c)


static func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Color) -> void:
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var z0 := minf(a.y, b.y)
	var z1 := maxf(a.y, b.y)
	for v in [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]:
		st.set_color(c)
		st.add_vertex(v)


## Frames draw over everything (a piece or a wall never hides where you're aiming) in their vertex colours.
static func _frame_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 8
	return m


static var _dot: Texture2D


## A soft round shadow (dark in the middle, fading to nothing at the edge), made once.
static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_dot = t
	return _dot
