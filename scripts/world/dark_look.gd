extends Node3D
## What makes a Deep place look like one, on top of its darker palette and void sky: glowing
## outlines along the floor's border and the top edges of every block, and props turned strange
## (tinted, slowly bobbing and turning). Built by game_world after the place (room_view.gd).

const BlockFactory := preload("res://scripts/world/block_factory.gd")

const LINE := Color("#b48cff")
const PROP_TINT := Color("#c9a0ff")

var lines_built := 0            # (tests) outline segments
var strange := 0                # (tests) props turned strange
var _bobbers: Array = []        # [node, base y, phase]
var _t := 0.0


func build(room_view: Node3D, data: Dictionary) -> void:
	for c in get_children():
		c.free()
	_bobbers.clear()
	lines_built = 0
	strange = 0
	if str(data.get("look", "")) != "dark":
		return
	var w := float(room_view.w)
	var d := float(room_view.d)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var y0 := 0.012
	for seg in [[Vector3(0, y0, 0), Vector3(w, y0, 0)], [Vector3(w, y0, 0), Vector3(w, y0, d)], [Vector3(w, y0, d), Vector3(0, y0, d)], [Vector3(0, y0, d), Vector3(0, y0, 0)]]:
		im.surface_add_vertex(seg[0])
		im.surface_add_vertex(seg[1])
		lines_built += 1
	for t in data.get("tiles", []):
		if not t is Dictionary:
			continue
		var x := float(t.get("x", 0))
		var z := float(t.get("z", 0))
		var top := float(t.get("y", 0)) + BlockFactory.height_of(str(t.get("type", "cube"))) + 0.01
		var corners := [Vector3(x, top, z), Vector3(x + 1, top, z), Vector3(x + 1, top, z + 1), Vector3(x, top, z + 1)]
		for k in 4:
			im.surface_add_vertex(corners[k])
			im.surface_add_vertex(corners[(k + 1) % 4])
			lines_built += 1
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = "Outlines"
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = LINE
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Props turned strange.
	for id in room_view.object_nodes:
		var node: Node3D = room_view.object_nodes[id]
		var o: Dictionary = room_view.find_object(str(id))
		if not is_instance_valid(node) or not str(o.get("type", "")) in ["prop", "sign"]:
			continue
		for s in node.find_children("*", "Sprite3D", true, false):
			(s as Sprite3D).modulate = (s as Sprite3D).modulate * PROP_TINT
		_bobbers.append([node, node.position.y, float(strange) * 1.3])
		strange += 1


func _process(delta: float) -> void:
	if _bobbers.is_empty():
		return
	_t += delta
	for b in _bobbers:
		var node: Node3D = b[0]
		if is_instance_valid(node):
			node.position.y = float(b[1]) + 0.08 + sin(_t * 1.4 + float(b[2])) * 0.08
			node.rotation.y += delta * 0.25
