extends Node3D
## What makes a Deep Dream World place look otherworldly on top of its darker palette and void sky:
## glowing violet outlines along the floor's border and block edges, plus floating strange props
## (tinted, gently bobbing and turning unless Reduce motion is on).
## Built by game_world after room_view.gd finishes building the room.

const BlockFactory := preload("res://scripts/world/block_factory.gd")

const LINE := Color("#b48cff")
const PROP_TINT := Color("#c9a0ff")

static var _line_mat: StandardMaterial3D

var lines_built := 0            # (tests) outline segments
var strange := 0                # (tests) props turned strange
var _bobbers: Array = []        # [node, base_y, phase]
var _t := 0.0


func _ready() -> void:
	set_process(false)


static func _shared_line_material() -> StandardMaterial3D:
	if _line_mat == null:
		_line_mat = StandardMaterial3D.new()
		_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_line_mat.albedo_color = LINE
	return _line_mat


func build(room_view: Node3D, data: Dictionary) -> void:
	for child in get_children():
		child.free()
	_bobbers.clear()
	lines_built = 0
	strange = 0
	if str(data.get("look", "")) != "dark":
		set_process(false)
		return

	var w := float(room_view.w)
	var d := float(room_view.d)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var y0 := 0.012
	for seg in [
		[Vector3(0.0, y0, 0.0), Vector3(w, y0, 0.0)],
		[Vector3(w, y0, 0.0), Vector3(w, y0, d)],
		[Vector3(w, y0, d), Vector3(0.0, y0, d)],
		[Vector3(0.0, y0, d), Vector3(0.0, y0, 0.0)],
	]:
		mesh.surface_add_vertex(seg[0])
		mesh.surface_add_vertex(seg[1])
		lines_built += 1

	for tile in data.get("tiles", []):
		if not tile is Dictionary:
			continue
		var x := float(tile.get("x", 0))
		var z := float(tile.get("z", 0))
		var top := float(tile.get("y", 0)) + BlockFactory.height_of(str(tile.get("type", "cube"))) + 0.01
		var corners := [
			Vector3(x, top, z),
			Vector3(x + 1.0, top, z),
			Vector3(x + 1.0, top, z + 1.0),
			Vector3(x, top, z + 1.0),
		]
		for corner_idx in 4:
			mesh.surface_add_vertex(corners[corner_idx])
			mesh.surface_add_vertex(corners[(corner_idx + 1) % 4])
			lines_built += 1
	mesh.surface_end()

	var outlines := MeshInstance3D.new()
	outlines.name = "Outlines"
	outlines.mesh = mesh
	outlines.material_override = _shared_line_material()
	outlines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outlines)

	# Props turned strange in the Deep.
	for id in room_view.object_nodes:
		var node: Node3D = room_view.object_nodes[id]
		var obj: Dictionary = room_view.find_object(str(id))
		if not is_instance_valid(node) or not str(obj.get("type", "")) in ["prop", "sign"]:
			continue
		for sprite in node.find_children("*", "Sprite3D", true, false):
			(sprite as Sprite3D).modulate = (sprite as Sprite3D).modulate * PROP_TINT
		_bobbers.append([node, node.position.y, float(strange) * 1.3])
		strange += 1

	set_process(not _bobbers.is_empty() and not bool(GameState.settings.get("reduce_motion", false)))


func _process(delta: float) -> void:
	if _bobbers.is_empty() or bool(GameState.settings.get("reduce_motion", false)):
		set_process(false)
		return
	_t += delta
	for entry in _bobbers:
		var node: Node3D = entry[0]
		if is_instance_valid(node):
			node.position.y = float(entry[1]) + 0.08 + sin(_t * 1.4 + float(entry[2])) * 0.08
			node.rotation.y += delta * 0.25
