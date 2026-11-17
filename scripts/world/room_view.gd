extends Node3D
## Builds a room's 3D scene from its JSON data: floor, walls, block pieces,
## tile layers (tile_render.gd) and objects, plus the walkability grid. A full
## build happens on load, undo and structural edits; painting tiles only
## redraws the touched chunks and re-checks those cells' walkability.

const BlockFactory := preload("res://scripts/world/block_factory.gd")
const GridNav := preload("res://scripts/world/grid_nav.gd")
const TileRender := preload("res://scripts/world/tile_render.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const Pickups := preload("res://scripts/items/pickups.gd")
const Places := preload("res://scripts/world/places.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const EdgeWalls := preload("res://scripts/world/edge_walls.gd")
const SurfaceMaterials := preload("res://scripts/world/surface_materials.gd")
const Realms := preload("res://scripts/world/realms.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const FloorPaths := preload("res://scripts/world/floor_paths.gd")

## Tile types the player can't walk through (slabs are low enough to cross).
const BLOCKING_TILES: PackedStringArray = ["cube", "ramp", "pillar"]
const BLOCKING_OBJECTS: PackedStringArray = ["sign", "prop", "platform_pillar"]

var data: Dictionary = {}
var w := 12
var d := 10
var h := 3.0
var nav := GridNav.new()
var layers: Node3D           # tile_render.gd: every tile layer
var editing := false         # build mode shows taken pickups as ghosts
var object_nodes: Dictionary = {}   # object id -> its node
var _content: Node3D
var _walls: Dictionary = {}   # side -> [full wall node, baseboard node]
var edge_walls: Node3D        # edge_walls.gd: a house's thin walls, doors, windows and room floors
var pop_new := false          # a rebuild after a change: pieces that weren't there before pop in
var _known_ids := {}


func build(room: Dictionary) -> void:
	data = room
	var size: Dictionary = room.get("size", {})
	w = clampi(int(size.get("w", 12)), 3, RoomEditor.MAX_SIZE)
	d = clampi(int(size.get("d", 10)), 3, RoomEditor.MAX_SIZE)
	h = clampf(float(size.get("h", 3)), 1.0, 8.0)
	if _content:
		_content.free()
	_content = Node3D.new()
	add_child(_content)
	_build_floor()
	_build_walls()
	if edge_walls == null:
		edge_walls = EdgeWalls.new()
		edge_walls.name = "EdgeWalls"
		add_child(edge_walls)
	edge_walls.build(room, h)
	var blocked: Array = []
	var groups: Dictionary = {}   # "type|color|texture" -> tiles with that look
	var tiles: Array = []
	var blocks_visible := bool(RoomOps.layer_state(room, "pieces").get("visible", true))
	for t in room.get("tiles", []):
		tiles.append(t)
		var key := "%s|%s|%s" % [t.get("type", "cube"), t.get("color", ""), t.get("texture", "")]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(t)
		if str(t.get("type", "")) in BLOCKING_TILES and float(t.get("y", 0)) < 1.0:
			blocked.append(Vector2i(int(t.get("x", 0)), int(t.get("z", 0))))
	var seen := {}
	for c in blocked:
		seen[c] = true
	for l in TileLayers.all(room):
		for k in l.cells:
			var c := TileLayers.parse_key(str(k))
			if not seen.has(c) and TileLayers.blocks_walk(room, c.x, c.y, Tilesets.info):
				seen[c] = true
				blocked.append(c)
	if blocks_visible:
		for key in groups:
			var first: Dictionary = groups[key][0]
			for mmi in BlockFactory.make_tile_batch(str(first.get("type", "cube")), str(first.get("color", "#8a7bc8")), str(first.get("texture", "")), groups[key]):
				_content.add_child(mmi)
	if not tiles.is_empty():
		_content.add_child(BlockFactory.tiles_body(tiles))
	if layers == null:
		layers = TileRender.new()
		add_child(layers)
	layers.build(room)
	object_nodes.clear()
	for o in room.get("objects", []):
		var here := not Pickups.is_pickup(o) or Pickups.available(o)
		if not here and not editing:
			continue
		var node := BlockFactory.make_object(o, not here)
		node.position = obj_position(o)
		_content.add_child(node)
		object_nodes[str(o.get("id", ""))] = node
		if pop_new and not _known_ids.has(str(o.get("id", ""))) and node is Node3D:
			preload("res://scripts/ui/anim_fx.gd").pop_in(node)
		if str(o.get("type", "")) in BLOCKING_OBJECTS:
			blocked.append(obj_cell(o))
		elif Furniture.is_furniture(o) and Furniture.blocks(str(o.get("model", ""))):
			blocked.append_array(Furniture.cells(o))
	# The neighbourhood: buildings and water can't be walked through.
	for b in room.get("buildings", []) if room.get("buildings") is Array else []:
		for c in b.get("cells", []):
			blocked.append(Vector2i(int(c[0]), int(c[1])))
	# Fences, hedges and walls stand on their cells (hood_builder.gd leaves gaps at paths and drives).
	for b in room.get("barriers", []) if room.get("barriers") is Array else []:
		if b is Dictionary and b.get("cells") is Array:
			for c in b.cells:
				blocked.append(Vector2i(int(c[0]), int(c[1])))
	for a in room.get("floor_areas", []) if room.get("floor_areas") is Array else []:
		if str(a.get("kind", "")) == "water":
			var r: Array = a.rect
			for z in range(int(r[1]), int(r[1]) + int(r[3])):
				for x in range(int(r[0]), int(r[0]) + int(r[2])):
					blocked.append(Vector2i(x, z))
	nav.setup(w, d, blocked, wall_keys(room))
	_known_ids = {}
	for id in object_nodes:
		_known_ids[id] = true


func _build_floor() -> void:
	var spec: Dictionary = data.get("floor", {})
	var mat: Material = _real_surface(spec, _ground_surface(spec))
	if mat == null:
		var surface := _ground_surface(spec)
		var detail := "ground" if surface == "grass" else ("wall" if Realms.is_light(data) and surface != "wood" else "floor")
		mat = BlockFactory.material(str(spec.get("color", "#5b4b8a")), str(spec.get("texture", "")), false, detail)
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(w, 0.3, d)
	var mi := MeshInstance3D.new()
	mi.mesh = floor_mesh
	mi.material_override = mat
	mi.position = Vector3(w / 2.0, -0.15, d / 2.0)
	_content.add_child(mi)
	_content.add_child(BlockFactory.body(Vector3(w, 0.3, d), Vector3(w / 2.0, -0.15, d / 2.0), BlockFactory.LAYER_WORLD, {"kind": "floor"}))
	_add_grid_lines()


## Faint grid lines on the floor so cells read clearly (helps clicking and building).
func _add_grid_lines() -> void:
	if Realms.is_light(data):
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for x in range(1, w):
		im.surface_add_vertex(Vector3(x, 0.005, 0))
		im.surface_add_vertex(Vector3(x, 0.005, d))
	for z in range(1, d):
		im.surface_add_vertex(Vector3(0, 0.005, z))
		im.surface_add_vertex(Vector3(w, 0.005, z))
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0, 0, 0, 0.12)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_content.add_child(mi)


func _build_walls() -> void:
	_walls.clear()
	var spec: Dictionary = data.get("wall", {})
	var mat: Material = _real_surface(spec, "plaster")
	if mat == null:
		mat = BlockFactory.material(str(spec.get("color", "#2e2552")), str(spec.get("texture", "")), false, "wall")
	var t := 0.25
	# side: [size, center, outward normal]
	var sides := {
		"north": [Vector3(w + 2 * t, h, t), Vector3(w / 2.0, h / 2.0, -t / 2.0), Vector3.FORWARD],
		"south": [Vector3(w + 2 * t, h, t), Vector3(w / 2.0, h / 2.0, d + t / 2.0), Vector3.BACK],
		"west": [Vector3(t, h, d), Vector3(-t / 2.0, h / 2.0, d / 2.0), Vector3.LEFT],
		"east": [Vector3(t, h, d), Vector3(w + t / 2.0, h / 2.0, d / 2.0), Vector3.RIGHT],
	}
	for side in sides:
		if not Places.has_wall(data, side):
			continue   # outdoors, somewhere strange, or a side joined to the next place
		var size: Vector3 = sides[side][0]
		var center: Vector3 = sides[side][1]
		var full := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		full.mesh = bm
		full.material_override = mat
		full.position = center
		_content.add_child(full)
		var base := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(size.x, 0.3, size.z)
		base.mesh = bb
		base.material_override = mat
		base.position = Vector3(center.x, 0.15, center.z)
		base.visible = false
		_content.add_child(base)
		var body := BlockFactory.body(size, center, BlockFactory.LAYER_WORLD, {"kind": "wall", "side": side})
		_content.add_child(body)
		_walls[side] = [full, base, sides[side][2], body]
		_content.add_child(_wall_foot(side, spec))


## Your real home (the Light World) gets real surfaces (surface_materials.gd) in its own colour; null when
## it's the Dream World, a picture was chosen, or surfaces are off (Battery saver).
func _real_surface(spec: Dictionary, surface: String) -> Material:
	if not Realms.is_light(data) or str(spec.get("texture", "")) != "":
		return null
	return SurfaceMaterials.standard(surface, Color.from_string(str(spec.get("color", "#efe6d8")), Color("#efe6d8")))


## What a Light World place's own ground is, from its colour: green is a lawn (a house's yard counts as
## indoors), grey is concrete (an upper floor's slab), anything else wooden boards.
func _ground_surface(spec: Dictionary) -> String:
	var c := Color.from_string(str(spec.get("color", "")), Color("#c9a27a"))
	if c.h > 0.17 and c.h < 0.45 and c.s > 0.2:
		return "grass"
	if c.s < 0.12:
		return "concrete"
	return "wood" if str(data.get("kind", "")) == "indoor" else "grass"


## Where a wall meets the floor: a soft shadow on the floor (the light that can't reach a corner) and a
## skirting board a shade darker than the wall. Plain vertex colours: the same on every renderer.
func _wall_foot(side: String, spec: Dictionary) -> Node3D:
	const REACH := 0.75      # how far the shade reaches into the room
	const DARK := 0.32
	var root := Node3D.new()
	root.name = "WallFoot_" + side
	# [the wall's line start, end, the direction into the room]
	var lines := {
		"north": [Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3.BACK],
		"south": [Vector3(0, 0, d), Vector3(w, 0, d), Vector3.FORWARD],
		"west": [Vector3(0, 0, 0), Vector3(0, 0, d), Vector3.RIGHT],
		"east": [Vector3(w, 0, 0), Vector3(w, 0, d), Vector3.LEFT],
	}
	var a: Vector3 = lines[side][0]
	var b: Vector3 = lines[side][1]
	var inward: Vector3 = lines[side][2]
	var lift := Vector3(0, 0.006, 0)   # just above the floor (and its grid lines)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var near := Color(0, 0, 0, DARK)
	var far := Color(0, 0, 0, 0)
	var quad := [[a, near], [b, near], [b + inward * REACH, far], [a, near], [b + inward * REACH, far], [a + inward * REACH, far]]
	for q in quad:
		st.set_color(q[1])
		st.set_normal(Vector3.UP)
		st.add_vertex(q[0] + lift)
	var shade := MeshInstance3D.new()
	shade.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade.material_override = m
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shade)
	var wall_col := Color.from_string(str(spec.get("color", "#2e2552")), Color("#2e2552"))
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var along := (b - a)
	bm.size = Vector3(absf(along.x) + absf(inward.x) * 0.06, 0.14, absf(along.z) + absf(inward.z) * 0.06)
	board.mesh = bm
	board.material_override = BlockFactory.material(wall_col.darkened(0.25).to_html(false), "", false, "" if Realms.is_light(data) else "block")
	board.position = (a + b) / 2.0 + inward * 0.03 + Vector3(0, 0.07, 0)
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(board)
	return root


func wall_count() -> int:
	return _walls.size()


func edge_wall_count() -> int:
	return edge_walls.count if edge_walls else 0


## The thin walls that stop you (doors don't), for the pathfinding: {"h|x|z": true, ...}.
static func wall_keys(room: Dictionary) -> Dictionary:
	return FloorPaths.walls_of(room)


## A house's walls between the camera and you drop to a low edge.
func update_edge_walls(camera_pos: Vector3, player_pos: Vector3) -> void:
	if edge_walls and edge_walls.count > 0:
		edge_walls.update(camera_pos, player_pos)


## Hides walls between the camera and the room (showing a low baseboard
## instead), so the inside is always visible from any rotation.
func update_walls(camera_pos: Vector3) -> void:
	var center := Vector3(w / 2.0, 0, d / 2.0)
	var to_cam := (camera_pos - center) * Vector3(1, 0, 1)
	for side in _walls:
		var normal: Vector3 = _walls[side][2]
		var hidden_side := to_cam.normalized().dot(normal) > 0.25
		_walls[side][0].visible = not hidden_side
		_walls[side][1].visible = hidden_side
		_walls[side][3].collision_layer = 0 if hidden_side else BlockFactory.LAYER_WORLD


## Darkens/warms billboard props with the time of day (they're unshaded).
func tint_sprites(c: Color) -> void:
	if _content == null:
		return
	for s in _content.find_children("*", "Sprite3D", true, false):
		if not s.has_meta("base_modulate"):
			s.set_meta("base_modulate", s.modulate)
		s.modulate = (s.get_meta("base_modulate") as Color) * c


# --- Grid helpers ------------------------------------------------------------------

func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0.0, c.y + 0.5)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.z))


func obj_cell(o: Dictionary) -> Vector2i:
	var pos: Array = o.get("pos", [0, 0, 0])
	return Vector2i(int(pos[0]), int(pos[2]))


func obj_position(o: Dictionary) -> Vector3:
	if Furniture.is_furniture(o):
		return Furniture.center(o)
	var pos: Array = o.get("pos", [0, 0, 0])
	var at := Vector3(float(pos[0]) + 0.5, float(pos[1]), float(pos[2]) + 0.5)
	var wall := LightHome.door_wall(data, o)
	if not wall.is_empty():
		var f: Vector2i = wall[1]
		at -= Vector3(f.x, 0, f.y) * 0.51   # your front door, in the face of your house's block (0.98 deep, edge_walls.gd)
	return at


func find_object(id: String) -> Dictionary:
	for o in data.get("objects", []):
		if str(o.get("id", "")) == id:
			return o
	return {}


func spawn_cell() -> Vector2i:
	var fallback := Vector2i(floori(w / 2.0), d - 2)
	var s: Array = data.get("spawn", [])
	var c := Vector2i(int(s[0]), int(s[1])) if s.size() >= 2 else fallback
	return nav.nearest_walkable(c)


## Door in this room that leads to `room_id` (to arrive next to it); stairs count too.
func door_to(room_id: String) -> Dictionary:
	for o in data.get("objects", []):
		if str(o.get("type", "")) == "door" and str(o.get("door_target", "")) == room_id:
			return o
	for o in data.get("objects", []):
		if Furniture.is_furniture(o) and (str(o.get("door_target", "")) == room_id or str(o.get("down_target", "")) == room_id):
			return o
	return {}


## After painting or erasing tiles: redraw only those chunks and re-check
## whether each touched cell can be walked on (no full rebuild).
func cells_changed(layer_id: String, cells: Array) -> void:
	if layers:
		layers.cells_changed(layer_id, cells)
	for c in cells:
		if nav.in_bounds(c):
			var there := RoomEditor.object_at(data, c.x, c.y)
			var blocked := RoomOps.blocks_walk(data, c.x, c.y) or str(there.get("type", "")) in BLOCKING_OBJECTS or (Furniture.is_furniture(there) and Furniture.blocks(str(there.get("model", ""))))
			nav.astar.set_point_solid(c, blocked)
