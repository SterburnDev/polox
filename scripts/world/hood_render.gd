extends RefCounted
## The neighbourhood's small things (a place made by hood_builder.gd), as ONE flat-shaded, vertex-coloured
## mesh per block, so a whole street of detail is a single draw call on a phone (mesh_batch.gd):
##   curbs where a sidewalk meets the street; zebra crossings ("decals"); fences, hedges and walls
##   ("barriers"); pitched roofs on houses that have them (gabled, hipped, pyramidal; flat ones stay
##   edge_walls.gd's slab); windows on the outside walls, floor by floor; a front door on the side facing
##   the street (yours is the real door object, in the wall: no window there); shops' big windows and an
##   awning over the sidewalk.
## Only drawing: what's walkable is decided by hood_builder.gd (and room_view.gd).
## Tags: [LIGHT_WORLD_MAP]

const MeshBatch := preload("res://scripts/world/mesh_batch.gd")
const LightHome := preload("res://scripts/world/light_home.gd")

const CURB := Color("#e0dcd4")
const ZEBRA := Color("#f2f0ea")
const GLASS := Color("#5d7891")
const FRAME := Color("#f4efe4")
const DOOR := Color("#6e4a36")
const FENCE := Color("#d9ccb0")
const HEDGE := Color("#4c8446")
const WALL := Color("#b4ab9c")
const AWNINGS := [Color("#c8604a"), Color("#4f7fa8"), Color("#5f9a6a"), Color("#d8a24a")]
const PITCHED: PackedStringArray = ["gabled", "hipped", "pyramidal", "half-hipped", "gambrel", "mansard"]
const STREET_KINDS: PackedStringArray = ["road", "sidewalk", "path", "paved"]

static var last_vertices := 0      # (tests, performance notes) the last block's vertex count


## Whether a building gets a pitched roof here (then edge_walls.gd leaves out its flat slab): its roof
## says so and its cells nearly fill their rectangle (an L-shaped or courtyard house keeps a flat top).
static func pitched(b: Dictionary) -> bool:
	if not str(b.get("roof_shape", "")) in PITCHED:
		return false
	var r := _bounds(b.get("cells", []))
	return r.size.x >= 1 and r.size.y >= 1 and float((b.get("cells", []) as Array).size()) >= 0.85 * r.size.x * r.size.y


static func _bounds(cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var lo := Vector2i(int(cells[0][0]), int(cells[0][1]))
	var hi := lo
	for c in cells:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
		hi = Vector2i(maxi(hi.x, int(c[0])), maxi(hi.y, int(c[1])))
	return Rect2i(lo, hi - lo + Vector2i(1, 1))


## The block's detail mesh, or null when it has nothing to draw.
static func build(room: Dictionary) -> MeshInstance3D:
	var mb := MeshBatch.new()
	var w := int(room.get("size", {}).get("w", 60))
	var d := int(room.get("size", {}).get("d", 60))
	var ground := _ground(room.get("floor_areas", []), w, d)
	_curbs(mb, ground, w, d)
	for dec in room.get("decals", []):
		if dec is Dictionary and str(dec.get("kind", "")) == "zebra":
			_zebra(mb, dec)
	for b in room.get("barriers", []):
		if b is Dictionary:
			_barrier(mb, b)
	var yours: Array = []   # the wall your front door stands in (light_home.gd)
	for o in room.get("objects", []):
		if o is Dictionary and yours.is_empty():
			yours = LightHome.door_wall(room, o)
	var bi := 0
	for b in room.get("buildings", []):
		if b is Dictionary:
			_building(mb, b, ground, w, d, bi, yours if str(b.get("kind", "")) == "mine" else [])
			bi += 1
	last_vertices = mb.vertex_count()
	if mb.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.name = "HoodDetail"
	mi.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	mi.material_override = m
	return mi


## The ground kind of every cell ("" = plain grass).
static func _ground(areas: Variant, w: int, d: int) -> PackedStringArray:
	var out := PackedStringArray()
	out.resize(w * d)
	if not areas is Array:
		return out
	for a in areas:
		if not a is Dictionary or not a.get("rect") is Array:
			continue
		var r: Array = a.rect
		for z in range(maxi(0, int(r[1])), mini(d, int(r[1]) + int(r[3]))):
			for x in range(maxi(0, int(r[0])), mini(w, int(r[0]) + int(r[2]))):
				out[z * w + x] = str(a.get("kind", ""))
	return out


static func _at(ground: PackedStringArray, w: int, d: int, x: int, z: int) -> String:
	return ground[z * w + x] if x >= 0 and z >= 0 and x < w and z < d else ""


## A low pale edge wherever a sidewalk cell meets the street.
static func _curbs(mb: RefCounted, ground: PackedStringArray, w: int, d: int) -> void:
	for z in d:
		for x in w:
			if ground[z * w + x] != "sidewalk":
				continue
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _at(ground, w, d, x + dv.x, z + dv.y) != "road":
					continue
				var c := Vector3(x + 0.5 + dv.x * 0.46, 0.06, z + 0.5 + dv.y * 0.46)
				mb.box(c, Vector3(0.08 if dv.x != 0 else 1.0, 0.12, 1.0 if dv.x != 0 else 0.08), CURB)


## White bars along the street's direction, across the crossing.
static func _zebra(mb: RefCounted, dec: Dictionary) -> void:
	var along_x := str(dec.get("axis", "z")) == "z"   # the crossing goes across z: the street runs along x
	for c in dec.get("cells", []):
		var cx := float(c[0]) + 0.5
		var cz := float(c[1]) + 0.5
		for k in [-0.25, 0.25]:
			if along_x:
				mb.flat(Vector2(cx - 0.4, cz + k - 0.09), Vector2(cx + 0.4, cz + k - 0.09), Vector2(cx + 0.4, cz + k + 0.09), Vector2(cx - 0.4, cz + k + 0.09), 0.02, ZEBRA)
			else:
				mb.flat(Vector2(cx + k - 0.09, cz - 0.4), Vector2(cx + k + 0.09, cz - 0.4), Vector2(cx + k + 0.09, cz + 0.4), Vector2(cx + k - 0.09, cz + 0.4), 0.02, ZEBRA)


static func _barrier(mb: RefCounted, b: Dictionary) -> void:
	var kind := str(b.get("kind", "fence"))
	var pts: Array = (b.get("pts", []) as Array).map(func(p): return Vector2(float(p[0]), float(p[1])))
	# Only the parts over its own cells are drawn (a fence passing a gate leaves the gap open).
	var cells := {}
	for c in b.get("cells", []):
		cells[Vector2i(int(c[0]), int(c[1]))] = true
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var e: Vector2 = pts[i + 1]
		var steps := maxi(1, int(ceil(a.distance_to(e))))
		for k in steps:
			var p0 := a.lerp(e, float(k) / steps)
			var p1 := a.lerp(e, float(k + 1) / steps)
			var mid := (p0 + p1) / 2.0
			if not cells.has(Vector2i(int(floor(mid.x)), int(floor(mid.y)))):
				continue
			var seg := p1 - p0
			var yaw := atan2(-seg.y, seg.x)
			var c := Vector3(mid.x, 0.0, mid.y)
			match kind:
				"hedge":
					mb.box(c + Vector3(0, 0.38, 0), Vector3(seg.length() + 0.05, 0.76, 0.5), HEDGE, yaw, HEDGE.lightened(0.12))
				"wall":
					mb.box(c + Vector3(0, 0.3, 0), Vector3(seg.length() + 0.02, 0.6, 0.22), WALL, yaw)
				_:
					mb.box(Vector3(p0.x, 0.32, p0.y), Vector3(0.07, 0.64, 0.07), FENCE, yaw)
					for rail in [0.22, 0.5]:
						mb.box(c + Vector3(0, rail, 0), Vector3(seg.length(), 0.05, 0.04), FENCE, yaw)


## Windows, a door, a shop's front and (when it has one) a pitched roof. `yours`, for your house: the bit
## of wall your front door stands in ([cell, the way out]).
static func _building(mb: RefCounted, b: Dictionary, ground: PackedStringArray, w: int, d: int, bi: int, yours: Array = []) -> void:
	var cells: Array = b.get("cells", [])
	if cells.is_empty():
		return
	var own := {}
	for c in cells:
		own[Vector2i(int(c[0]), int(c[1]))] = true
	var h := float(b.get("h", 2.4))
	var levels := clampi(int(b.get("levels", 1)), 1, 6)
	var storey := (h - 0.2) / levels
	var shop := bool(b.get("storefront", false))
	var mine := str(b.get("kind", "")) == "mine"
	var edges: Array = []    # outside edges: [cell, dv, faces the street]
	var front: Array = []    # the ones facing the street: [cell, dv]
	for c in cells:
		var cell := Vector2i(int(c[0]), int(c[1]))
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var out_cell: Vector2i = cell + dv
			if own.has(out_cell):
				continue
			var street := _at(ground, w, d, out_cell.x, out_cell.y) in STREET_KINDS
			edges.append([cell, dv, street])
			if street:
				front.append([cell, dv])
	# The door: in the middle of the side facing the street; yours is the real door object, in its wall.
	var door: Array = yours if mine else (front[front.size() / 2] if not front.is_empty() and not shop else [])
	var n := 0
	for e in edges:
		n += 1
		for lv in levels:
			if shop and lv == 0 and e[2]:
				continue   # (the shopfront below)
			if not shop and (n + lv) % 2 == 1:
				continue   # homes: a window every other cell
			if lv == 0 and not door.is_empty() and e[0] == door[0] and e[1] == door[1]:
				continue   # (the door's there)
			_window(mb, e[0], e[1], storey * lv + storey * 0.45, 0.42 if not shop else 0.6)
	if not mine and not door.is_empty():
		_panel(mb, door[0], door[1], 0.0, 1.0, 0.36, DOOR)
	if shop:
		var awning: Color = AWNINGS[bi % AWNINGS.size()]
		for f in front:
			_panel(mb, f[0], f[1], 0.12, 0.95, 0.44, GLASS.lightened(0.15), FRAME)
			var cell: Vector2i = f[0]
			var dv: Vector2i = f[1]
			var c := Vector3(cell.x + 0.5 + dv.x * 0.62, 1.3, cell.y + 0.5 + dv.y * 0.62)
			mb.box(c, Vector3(0.26 if dv.x != 0 else 1.0, 0.06, 1.0 if dv.x != 0 else 0.26), awning, 0.0, awning.lightened(0.18))
	if pitched(b):
		_roof(mb, _bounds(cells), h, str(b.get("roof_shape", "gabled")), Color.from_string(str(b.get("roof", "#7a5a46")), Color("#7a5a46")))


## A window on the outside face of `cell` towards `dv`, its middle at height `y`: a pale frame, glass in it.
static func _window(mb: RefCounted, cell: Vector2i, dv: Vector2i, y: float, half_w: float) -> void:
	_panel(mb, cell, dv, y - 0.28, y + 0.28, half_w, GLASS, FRAME)


## A flat panel standing just outside a wall face (y0..y1 high, half_w either side of the cell's middle),
## with an optional frame round it.
static func _panel(mb: RefCounted, cell: Vector2i, dv: Vector2i, y0: float, y1: float, half_w: float, col: Color, frame: Variant = null) -> void:
	var n := Vector3(dv.x, 0, dv.y)
	var along := Vector3(-dv.y, 0, dv.x)
	var base := Vector3(cell.x + 0.5, 0, cell.y + 0.5) + n * 0.5
	if frame is Color:
		var f := base + n * 0.012
		mb.quad(f + along * (half_w + 0.06) + Vector3(0, y0 - 0.06, 0), f - along * (half_w + 0.06) + Vector3(0, y0 - 0.06, 0),
			f - along * (half_w + 0.06) + Vector3(0, y1 + 0.06, 0), f + along * (half_w + 0.06) + Vector3(0, y1 + 0.06, 0), frame, n)
	var g := base + n * 0.02
	mb.quad(g + along * half_w + Vector3(0, y0, 0), g - along * half_w + Vector3(0, y0, 0), g - along * half_w + Vector3(0, y1, 0), g + along * half_w + Vector3(0, y1, 0), col, n)


## A pitched roof over the building's rectangle: two slopes and two gable ends (gabled), or four slopes to
## a ridge (hipped) or a point (pyramidal). It sits where edge_walls.gd's flat slab would.
static func _roof(mb: RefCounted, r: Rect2i, h: float, shape: String, col: Color) -> void:
	var o := 0.16   # overhang
	var x0 := r.position.x - o
	var x1 := r.end.x + o
	var z0 := r.position.y - o
	var z1 := r.end.y + o
	var along_x := r.size.x >= r.size.y   # the ridge runs along the longer side
	var rise := clampf(0.38 * minf(r.size.x, r.size.y), 0.5, 1.8)
	var y := h
	var top := y + rise
	var side := col.darkened(0.12)
	var gable := Color("#efe6d6")
	if shape == "pyramidal" or (shape != "gabled" and r.size.x == r.size.y):
		var apex := Vector3((x0 + x1) / 2.0, top, (z0 + z1) / 2.0)
		var corners := [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			var nrm := (b - a).cross(apex - a).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			mb.tri(a, b, apex, nrm, col if i % 2 == 0 else side)
		return
	var inset := 0.0 if shape == "gabled" else minf(r.size.x, r.size.y) * 0.35
	if along_x:
		var zm := (z0 + z1) / 2.0
		var r0 := Vector3(x0 + inset, top, zm)
		var r1 := Vector3(x1 - inset, top, zm)
		_slope(mb, Vector3(x0, y, z0), Vector3(x1, y, z0), r1, r0, col)
		_slope(mb, Vector3(x1, y, z1), Vector3(x0, y, z1), r0, r1, side)
		if shape == "gabled":
			mb.tri(Vector3(x0, y, z0), Vector3(x0, y, z1), r0, Vector3(-1, 0, 0), gable)
			mb.tri(Vector3(x1, y, z1), Vector3(x1, y, z0), r1, Vector3(1, 0, 0), gable)
		else:
			mb.tri(Vector3(x0, y, z1), Vector3(x0, y, z0), r0, Vector3(-1, 0.6, 0).normalized(), side)
			mb.tri(Vector3(x1, y, z0), Vector3(x1, y, z1), r1, Vector3(1, 0.6, 0).normalized(), col)
	else:
		var xm := (x0 + x1) / 2.0
		var r0 := Vector3(xm, top, z0 + inset)
		var r1 := Vector3(xm, top, z1 - inset)
		_slope(mb, Vector3(x0, y, z1), Vector3(x0, y, z0), r0, r1, col)
		_slope(mb, Vector3(x1, y, z0), Vector3(x1, y, z1), r1, r0, side)
		if shape == "gabled":
			mb.tri(Vector3(x1, y, z0), Vector3(x0, y, z0), r0, Vector3(0, 0, -1), gable)
			mb.tri(Vector3(x0, y, z1), Vector3(x1, y, z1), r1, Vector3(0, 0, 1), gable)
		else:
			mb.tri(Vector3(x0, y, z0), Vector3(x1, y, z0), r0, Vector3(0, 0.6, -1).normalized(), side)
			mb.tri(Vector3(x1, y, z1), Vector3(x0, y, z1), r1, Vector3(0, 0.6, 1).normalized(), col)


## A roof slope a-b-c-d, its normal pointing up and out (whatever order the corners come in).
static func _slope(mb: RefCounted, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.y < 0.0:
		n = -n
	mb.quad(a, b, c, d, col, n)
