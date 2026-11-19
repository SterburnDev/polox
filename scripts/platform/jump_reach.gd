extends MeshInstance3D
## The editor's "Jump reach" overlay: from one cell, the surfaces a running
## jump in Platform Mode can land on. Gold = same height or one block up,
## blue = lower. Uses the same numbers as the real jump (platform_config.gd).

const Config := preload("res://scripts/platform/platform_config.gd")
const Profiles := preload("res://scripts/platform/platform_profiles.gd")
const PlatformWorld := preload("res://scripts/platform/platform_world.gd")

var origin := Vector2i(-1, -1)
var reach := Vector2.ZERO           # [max rise, max gap] in blocks
var cells: Array = []               # [[Vector2i, top, "up"|"down"], ...] (tests read it)


## Cells reachable from `from` in `room`: [[cell, top height, kind], ...].
static func reachable(room: Dictionary, from: Vector2i) -> Array:
	var id := Profiles.course(room)
	var r := Profiles.jump_reach(id, true)
	var size: Dictionary = room.get("size", {})
	var w := int(size.get("w", 12))
	var d := int(size.get("d", 10))
	var h0 := PlatformWorld.top_at(room, from.x, from.y)
	var out: Array = []
	var gap := int(r.y)
	for z in range(maxi(0, from.y - gap), mini(d, from.y + gap + 1)):
		for x in range(maxi(0, from.x - gap), mini(w, from.x + gap + 1)):
			var c := Vector2i(x, z)
			if id == "classic" and ((Profiles.plane(room) == "x" and z != from.y) or (Profiles.plane(room) == "z" and x != from.x)):
				continue
			if c == from or Vector2(c - from).length() > r.y + 0.5:
				continue
			var h1 := PlatformWorld.top_at(room, x, z)
			if h1 - h0 > r.x + 0.01:
				continue   # too high for a jump
			out.append([c, h1, "up" if h1 >= h0 else "down"])
	return out


func show_from(room: Dictionary, from: Vector2i) -> void:
	origin = from
	reach = Profiles.jump_reach(Profiles.course(room), true)
	cells = reachable(room, from)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in cells:
		var c: Vector2i = e[0]
		var y := float(e[1]) + 0.03
		var col := Color(1.0, 0.82, 0.4, 0.45) if str(e[2]) == "up" else Color(0.56, 0.83, 1.0, 0.35)
		var a := Vector3(c.x + 0.1, y, c.y + 0.1)
		var b := Vector3(c.x + 0.9, y, c.y + 0.1)
		var cc := Vector3(c.x + 0.9, y, c.y + 0.9)
		var dd := Vector3(c.x + 0.1, y, c.y + 0.9)
		for v in [a, b, cc, a, cc, dd]:
			im.surface_set_color(col)
			im.surface_add_vertex(v)
	im.surface_end()
	mesh = im
	if material_override == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
