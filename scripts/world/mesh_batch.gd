extends RefCounted
## A batch of flat-shaded, vertex-coloured triangles that becomes one ArrayMesh: one draw call however
## many lamps, fences, roofs or kerbs it holds (the Light World's streets, hood_render.gd). Normals are
## given per face, so winding is fixed up here (Godot's front faces are clockwise seen from outside).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()


func is_empty() -> bool:
	return verts.is_empty()


func vertex_count() -> int:
	return verts.size()


## One triangle facing `n` (the order of a, b, c doesn't matter).
func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	verts.append(a)
	verts.append(b)
	verts.append(c)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	colors.append(col)
	colors.append(col)
	colors.append(col)


## A flat quad a-b-c-d (in order around it), facing `n` (computed when zero).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n: Vector3 = Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = (b - a).cross(d - a)
		if n.length_squared() < 1e-12:
			return
		n = n.normalized()
	tri(a, b, c, n, col)
	tri(a, c, d, n, col)


## An upward-facing quad lying on the ground at height y.
func flat(a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, col: Color) -> void:
	quad(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3(d.x, y, d.y), col, Vector3.UP)


## A box (centre, size), turned by `yaw` radians about the vertical; `top_col` tints its top.
func box(c: Vector3, s: Vector3, col: Color, yaw: float = 0.0, top_col: Variant = null, bottom: bool = false) -> void:
	var hx := s.x / 2.0
	var hy := s.y / 2.0
	var hz := s.z / 2.0
	var ax := Vector3(cos(yaw), 0.0, -sin(yaw))
	var az := Vector3(sin(yaw), 0.0, cos(yaw))
	var p := [c - ax * hx - az * hz, c + ax * hx - az * hz, c + ax * hx + az * hz, c - ax * hx + az * hz]
	var up := Vector3(0, hy, 0)
	var t: Color = top_col if top_col is Color else col
	quad(p[0] + up, p[1] + up, p[2] + up, p[3] + up, t, Vector3.UP)
	if bottom:
		quad(p[0] - up, p[1] - up, p[2] - up, p[3] - up, col.darkened(0.2), Vector3.DOWN)
	var sides := [[0, 1, -az], [1, 2, ax], [2, 3, az], [3, 0, -ax]]
	for sd in sides:
		var a: Vector3 = p[sd[0]]
		var b: Vector3 = p[sd[1]]
		quad(a - up, b - up, b + up, a + up, col, sd[2])


## A vertical post-like prism with `sides` faces (a cheap cylinder or cone when top_r differs).
func prism(base: Vector3, r: float, h: float, col: Color, sides: int = 6, top_r: float = -1.0, top_col: Variant = null) -> void:
	if top_r < 0.0:
		top_r = r
	var ring_b: Array = []
	var ring_t: Array = []
	for i in sides:
		var a := TAU * (float(i) + 0.5) / sides
		var dir := Vector3(cos(a), 0.0, sin(a))
		ring_b.append(base + dir * r)
		ring_t.append(base + dir * top_r + Vector3(0, h, 0))
	for i in sides:
		var j := (i + 1) % sides
		var mid: Vector3 = (ring_b[i] + ring_b[j]) / 2.0 - base
		mid.y = 0.0
		var n: Vector3 = mid.normalized() if top_r == r else ((ring_t[i] - ring_b[i]).cross(ring_b[j] - ring_b[i])).normalized()
		if n.dot(mid) < 0.0:
			n = -n
		if top_r <= 0.001:
			tri(ring_b[i], ring_b[j], base + Vector3(0, h, 0), n, col)
		else:
			quad(ring_b[i], ring_b[j], ring_t[j], ring_t[i], col, n)
	if top_r > 0.001:
		var t: Color = top_col if top_col is Color else col
		var top := base + Vector3(0, h, 0)
		for i in sides:
			tri(top, ring_t[i], ring_t[(i + 1) % sides], Vector3.UP, t)


## A soft low-poly blob (tree canopies, bushes, hedges' rounded tops): an octahedron-ish ball.
func blob(c: Vector3, r: Vector3, col: Color, shade: float = 0.12) -> void:
	var top := c + Vector3(0, r.y, 0)
	var bot := c - Vector3(0, r.y * 0.55, 0)
	var ring: Array = []
	for i in 6:
		var a := TAU * float(i) / 6.0
		ring.append(c + Vector3(cos(a) * r.x, r.y * 0.1, sin(a) * r.z))
	for i in 6:
		var j := (i + 1) % 6
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[j]
		var nt := (a - top).cross(b - top).normalized()
		if nt.y < 0.0:
			nt = -nt
		tri(top, a, b, nt, col.lightened(shade * 0.5) if i % 2 == 0 else col)
		var nb := (a - bot).cross(b - bot).normalized()
		if nb.y > 0.0:
			nb = -nb
		tri(bot, a, b, nb, col.darkened(shade))


## A ribbon along a polyline on the ground: width w, at height y, shifted sideways by `offset` (left is
## positive, looking along the line). Joints get a small fan so bends have no gaps.
func ribbon(pts: Array, w: float, y: float, col: Color, offset: float = 0.0, round_joints: bool = true) -> void:
	if pts.size() < 2:
		return
	var hw := w / 2.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d := b - a
		if d.length() < 0.001:
			continue
		var nrm := Vector2(-d.y, d.x).normalized()
		var o := nrm * offset
		flat(a + o + nrm * hw, b + o + nrm * hw, b + o - nrm * hw, a + o - nrm * hw, y, col)
	if round_joints:
		for i in range(0 if offset == 0.0 else 1, pts.size() if offset == 0.0 else pts.size() - 1):
			var c2: Vector2 = pts[i]
			if offset != 0.0:
				var d0: Vector2 = (pts[i] as Vector2) - (pts[i - 1] as Vector2)
				var d1: Vector2 = (pts[i + 1] as Vector2) - (pts[i] as Vector2)
				var n0 := Vector2(-d0.y, d0.x).normalized()
				var n1 := Vector2(-d1.y, d1.x).normalized()
				c2 = c2 + (n0 + n1).normalized() * offset if (n0 + n1).length() > 0.01 else c2 + n0 * offset
			disc(c2, hw, y, col, 8)


## A flat disc (joints, manhole covers, round flower beds).
func disc(c: Vector2, r: float, y: float, col: Color, sides: int = 8) -> void:
	var cc := Vector3(c.x, y, c.y)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		tri(cc, cc + Vector3(cos(a0) * r, 0, sin(a0) * r), cc + Vector3(cos(a1) * r, 0, sin(a1) * r), Vector3.UP, col)


func commit(existing: ArrayMesh = null) -> ArrayMesh:
	var mesh := existing if existing else ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
