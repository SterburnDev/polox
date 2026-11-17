extends Node3D
## Platform Mode's physical room, built from the room data when Platform Mode
## starts (and again after a room change or an edit): the floor and invisible
## walls, every block piece and solid tile merged into a few boxes per 16x16
## chunk (one StaticBody3D per chunk, never one per tile), ramps as wedges,
## one-way and moving platforms, and trigger areas (jump pads, soft hazards,
## checkpoints, Memory Shards, doors, pickups; unwalkable ground like water
## counts as a soft hazard). Touches come out as `touched(kind, obj)`.
##
## Triggers are boxes checked against the capsule's swept path every physics
## tick (sweep_triggers), not overlap areas: a body crossing a checkpoint, a
## shard or a hazard in less than a tick at launch speed still touches it,
## once per entry. Movers stop while `paused` (menus, fades, transitions).

signal touched(kind: String, obj: Dictionary)

const Config := preload("res://scripts/platform/platform_config.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const Places := preload("res://scripts/world/places.gd")

const CHUNK := 16
const SOLID_OBJECTS := {"sign": Vector3(0.9, 1.35, 0.5), "prop": Vector3(0.8, 1.2, 0.8), "platform_pillar": Vector3(0.8, 3.0, 0.8)}
const AREA_OBJECTS: PackedStringArray = ["jump_pad", "hazard", "checkpoint", "shard", "door", "pickup"]
const PLATFORM_TYPES: PackedStringArray = ["platform_pillar", "jump_pad", "one_way", "mover", "checkpoint", "shard", "hazard"]

var room: Dictionary = {}
var w := 12
var d := 10
var one_ways: Array = []          # [StaticBody3D, top y]
var movers: Array = []            # [AnimatableBody3D, from, to, speed, phase]
var slippery: Dictionary = {}     # Vector2i -> true
var box_count := 0                # merged boxes (tests and the stress check read it)
var body_count := 0
var triggers: Array = []          # [{kind, obj, box: AABB}] (pads, hazards, checkpoints, shards, doors, pickups, edges)
var paused := false               # movers hold still with the body (platform_mode.gd)
var _inside: Dictionary = {}      # trigger index -> true while the capsule overlaps it
var _trigger_generation := 0


func build(r: Dictionary) -> void:
	for c in get_children():
		c.free()
	room = r
	one_ways.clear()
	movers.clear()
	slippery.clear()
	triggers.clear()
	reset_triggers()
	box_count = 0
	body_count = 0
	var size: Dictionary = r.get("size", {})
	w = int(size.get("w", 12))
	d = int(size.get("d", 10))
	_floor_and_walls()
	_solids()
	_objects()
	_ground_cells()


## Height of the walkable surface at a cell (0 = floor), for spawning and the jump-reach overlay.
static func top_at(r: Dictionary, x: int, z: int) -> float:
	var top := 0.0
	for t in r.get("tiles", []):
		if int(t.get("x", -1)) == x and int(t.get("z", -1)) == z:
			top = maxf(top, float(t.get("y", 0)) + BlockFactory.height_of(str(t.get("type", "cube"))))
	for b in solid_tile_cells(r):
		if b.x == x and b.z == z:
			top = maxf(top, b.y + 1.0)
	return top


# --- Static geometry -----------------------------------------------------------------------------

func _body(layer: int = Config.LAYER_SOLID) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	add_child(sb)
	body_count += 1
	return sb


func _box(sb: CollisionObject3D, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	sb.add_child(cs)
	box_count += 1


func _floor_and_walls() -> void:
	var sb := _body()
	sb.name = "FloorAndWalls"
	_box(sb, Vector3(w / 2.0, -0.25, d / 2.0), Vector3(w + 2, 0.5, d + 2))
	var hgt := 40.0
	var joined := Places.edges(room)
	var walls := {
		"west": [Vector3(-0.5, hgt / 2.0, d / 2.0), Vector3(1, hgt, d + 2)],
		"east": [Vector3(w + 0.5, hgt / 2.0, d / 2.0), Vector3(1, hgt, d + 2)],
		"north": [Vector3(w / 2.0, hgt / 2.0, -0.5), Vector3(w + 2, hgt, 1)],
		"south": [Vector3(w / 2.0, hgt / 2.0, d + 0.5), Vector3(w + 2, hgt, 1)],
	}
	var bounds := _body(Config.LAYER_BOUNDS)
	bounds.name = "Bounds"
	for side in walls:
		if joined.has(side):
			_edge_area(side, walls[side][0], walls[side][1])   # walk through to the next place
		else:
			_box(bounds, walls[side][0], walls[side][1])


## Beyond a joined edge: touching it takes you to the next place (platform_mode.gd: "edge").
func _edge_area(side: String, center: Vector3, size: Vector3) -> void:
	_trigger("edge", {"side": side}, Vector3(center.x, 2.0, center.z), Vector3(size.x, 4.0, size.z))
	# A floor beyond the edge so you don't drop before the trigger catches you.
	var sb := _body()
	sb.name = "EdgeFloor_" + side
	_box(sb, Vector3(center.x, -0.25, center.z), Vector3(size.x + 1, 0.5, size.z + 1))


## Solid tile cells as [x, y (level), z] Vector3s: Blocks/Foreground pictures that block walking.
static func solid_tile_cells(r: Dictionary) -> Array:
	var out: Array = []
	for l in TileLayers.all(r):
		var type := str(l.type)
		if not type in ["blocks", "foreground"]:
			continue
		for k in l.cells:
			var c: Dictionary = l.cells[k]
			var solid: Variant = c.get("solid")
			if solid == null:
				solid = bool(Tilesets.info(str(c.s), str(c.t)).get("solid", false)) if type == "blocks" else false
			if bool(solid):
				var p := TileLayers.parse_key(str(k))
				out.append(Vector3(p.x, TileLayers.level_of(l, c), p.y))
	return out


func _solids() -> void:
	# Boxes grouped by (bottom, height) so neighbours at the same level merge.
	var groups := {}   # "y|h" -> {Vector2i: true}
	var ramps: Array = []
	var pillars: Array = []
	for t in room.get("tiles", []):
		var type := str(t.get("type", "cube"))
		var y := float(t.get("y", 0))
		var cell := Vector2i(int(t.get("x", 0)), int(t.get("z", 0)))
		match type:
			"ramp":
				ramps.append(t)
			"pillar":
				pillars.append(t)
			_:
				var key := "%s|%s" % [y, BlockFactory.height_of(type)]
				if not groups.has(key):
					groups[key] = {}
				groups[key][cell] = true
	for b in solid_tile_cells(room):
		var key := "%s|1.0" % float(b.y)
		if not groups.has(key):
			groups[key] = {}
		groups[key][Vector2i(int(b.x), int(b.z))] = true
	var chunks := {}   # Vector2i chunk -> StaticBody3D
	for key in groups:
		var y := float(str(key).get_slice("|", 0))
		var h := float(str(key).get_slice("|", 1))
		for rect in merge_cells(groups[key]):
			var r: Rect2i = rect
			var ck := Vector2i(r.position.x / CHUNK, r.position.y / CHUNK)
			if not chunks.has(ck):
				chunks[ck] = _body()
				chunks[ck].name = "Chunk_%d_%d" % [ck.x, ck.y]
			_box(chunks[ck], Vector3(r.position.x + r.size.x / 2.0, y + h / 2.0, r.position.y + r.size.y / 2.0), Vector3(r.size.x, h, r.size.y))
	for t in ramps + pillars:
		var cell := Vector2i(int(t.get("x", 0)), int(t.get("z", 0)))
		var ck := Vector2i(cell.x / CHUNK, cell.y / CHUNK)
		if not chunks.has(ck):
			chunks[ck] = _body()
		var base := Vector3(cell.x + 0.5, float(t.get("y", 0)), cell.y + 0.5)
		if str(t.get("type", "")) == "pillar":
			_box(chunks[ck], base + Vector3(0, 1.0, 0), Vector3(0.62, 2.0, 0.62))
		else:
			_wedge(chunks[ck], base, int(t.get("rot", 0)))


## A ramp: high side at local -X (like the ramp's PrismMesh), turned by its rotation.
func _wedge(sb: StaticBody3D, base: Vector3, rot: int) -> void:
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 1, -0.5), Vector3(-0.5, 1, 0.5)])
	cs.shape = shape
	cs.transform = Transform3D(Basis.from_euler(Vector3(0, rot * PI / 2.0, 0)), base)
	sb.add_child(cs)
	box_count += 1


## Greedy rectangles covering a set of cells (rows first, then grown down).
static func merge_cells(cells: Dictionary) -> Array:
	var left := cells.duplicate()
	var keys: Array = left.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array = []
	for c in keys:
		if not left.has(c):
			continue
		var cx: int = c.x
		var cz: int = c.y
		var ex := cx
		while left.has(Vector2i(ex + 1, cz)) and (ex + 1) / CHUNK == cx / CHUNK:
			ex += 1
		var ez := cz
		var grow := true
		while grow and (ez + 1) / CHUNK == cz / CHUNK:
			for x in range(cx, ex + 1):
				if not left.has(Vector2i(x, ez + 1)):
					grow = false
					break
			if grow:
				ez += 1
		for z in range(cz, ez + 1):
			for x in range(cx, ex + 1):
				left.erase(Vector2i(x, z))
		out.append(Rect2i(cx, cz, ex - cx + 1, ez - cz + 1))
	return out


# --- Objects -------------------------------------------------------------------------------------

static func object_base(o: Dictionary) -> Vector3:
	var p: Array = o.get("pos", [0, 0, 0])
	return Vector3(floorf(float(p[0])) + 0.5, float(p[1]) + float(o.get("elev", 0)), floorf(float(p[2])) + 0.5)


func _objects() -> void:
	var solid := _body()
	solid.name = "Objects"
	for o in room.get("objects", []):
		var type := str(o.get("type", ""))
		var base := object_base(o)
		if SOLID_OBJECTS.has(type):
			var s: Vector3 = SOLID_OBJECTS[type]
			_box(solid, base + Vector3(0, s.y / 2.0, 0), s)
		match type:
			"one_way":
				var sb := _body(Config.LAYER_ONE_WAY)
				_box(sb, base + Vector3(0, -0.1, 0), Vector3(1.0, 0.2, 1.0))
				one_ways.append([sb, base.y])
			"mover":
				_mover(o, base)
		if type in AREA_OBJECTS:
			_area(type, o, base)


func _area(kind: String, o: Dictionary, base: Vector3) -> void:
	var size := Vector3(0.9, 0.5, 0.9)
	var center := base + Vector3(0, 0.25, 0)
	match kind:
		"checkpoint", "door":
			size = Vector3(0.9, 2.0, 0.9)
			center = base + Vector3(0, 1.0, 0)
		"shard":
			size = Vector3(0.7, 0.9, 0.7)
			center = base + Vector3(0, 0.75, 0)
		"pickup":
			size = Vector3(0.8, 1.0, 0.8)
			center = base + Vector3(0, 0.5, 0)
		"jump_pad":
			size = Vector3(0.9, 0.35, 0.9)
			center = base + Vector3(0, 0.15, 0)
	_trigger(kind, o, center, size)


## A trigger box (centre, size) that `touched` reports when the capsule's path enters it.
func _trigger(kind: String, o: Dictionary, center: Vector3, size: Vector3) -> void:
	triggers.append({"kind": kind, "obj": o, "box": AABB(center - size / 2.0, size)})


func _mover(o: Dictionary, base: Vector3) -> void:
	var ab := AnimatableBody3D.new()
	ab.collision_layer = Config.LAYER_SOLID
	ab.collision_mask = 0
	ab.sync_to_physics = true
	_box(ab, Vector3(0, -0.15, 0), Vector3(1.0, 0.3, 1.0))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.3, 1.0)
	mi.mesh = bm
	mi.position.y = -0.15
	mi.material_override = BlockFactory.material(str(o.get("color", "")) if str(o.get("color", "")) != "" else "#8fd3ff")
	ab.add_child(mi)
	ab.position = base
	add_child(ab)
	body_count += 1
	var to := base + Vector3(float(o.get("dx", 3)), float(o.get("dy", 0)), float(o.get("dz", 0)))
	movers.append([ab, base, to, maxf(0.2, float(o.get("speed", Config.MOVER_SPEED))), 0.0, str(o.get("id", ""))])


func _physics_process(delta: float) -> void:
	if paused:
		return
	for m in movers:
		var ab: AnimatableBody3D = m[0]
		var from: Vector3 = m[1]
		var to: Vector3 = m[2]
		var length := maxf(0.01, from.distance_to(to))
		m[4] = float(m[4]) + delta * float(m[3]) / length
		var t := 0.5 - 0.5 * cos(float(m[4]) * PI)   # eased ping-pong
		ab.position = from.lerp(to, t)


# --- Ground ---------------------------------------------------------------------------------------

## Unwalkable ground (water, gaps) = soft hazards; slippery ground tiles remembered.
func _ground_cells() -> void:
	var wet := {}
	for l in TileLayers.all(room):
		if str(l.type) != "ground":
			continue
		for k in l.cells:
			var c: Dictionary = l.cells[k]
			if TileLayers.level_of(l, c) != 0:
				continue
			var info := Tilesets.info(str(c.s), str(c.t))
			var p := TileLayers.parse_key(str(k))
			if not bool(info.get("walkable", true)):
				wet[p] = true
			if bool(info.get("slippery", false)) or bool(c.get("slip", false)):
				slippery[p] = true
	for rect in merge_cells(wet):
		var r: Rect2i = rect
		_trigger("hazard", {"id": "ground", "type": "hazard"}, Vector3(r.position.x + r.size.x / 2.0, 0.2, r.position.y + r.size.y / 2.0), Vector3(r.size.x - 0.2, 0.4, r.size.y - 0.2))


func is_slippery(cell: Vector2i) -> bool:
	return slippery.has(cell)


## One-way platforms only stop you from above: each frame, collide with the
## ones whose top is under your feet and you're not rising through.
func update_one_ways(body: CharacterBody3D) -> void:
	var feet := body.global_position.y
	for ow in one_ways:
		var sb: StaticBody3D = ow[0]
		var solid := feet >= float(ow[1]) - 0.05 and body.velocity.y <= 0.5
		if solid:
			body.remove_collision_exception_with(sb)
		else:
			body.add_collision_exception_with(sb)


# --- Swept triggers -------------------------------------------------------------------------------

## The capsule (feet at `from` -> `to` this tick) against every trigger box: each box the path
## enters fires `touched` once, in the order they're met; leaving it re-arms it. A respawn or a
## room change calls reset_triggers() first, so a teleport never "sweeps" across the course.
func sweep_triggers(_body: Node, from: Vector3, to: Vector3) -> void:
	var generation := _trigger_generation
	var r := Config.CAPSULE_RADIUS
	var h := Config.CAPSULE_HEIGHT
	var hits: Array = []
	for i in triggers.size():
		var box: AABB = triggers[i].box
		# The capsule as a box around its feet point: grow the trigger by the capsule's extent.
		var grown := AABB(box.position - Vector3(r, h, r), box.size + Vector3(2.0 * r, h, 2.0 * r))
		var t := _segment_enters(grown, from, to)
		var now_in := grown.has_point(to)
		if t >= 0.0 and not _inside.has(i):
			hits.append([t, i])
		if now_in:
			_inside[i] = true
		elif t < 0.0 or not now_in:
			_inside.erase(i)
	hits.sort_custom(func(a, b): return a[0] < b[0])
	for hit in hits:
		if generation != _trigger_generation:
			return # A callback teleported the player or rebuilt the room.
		var tr: Dictionary = triggers[int(hit[1])]
		touched.emit(str(tr.kind), tr.obj)


func reset_triggers() -> void:
	_trigger_generation += 1
	_inside.clear()


## Where along from -> to (0..1) the segment first touches the box; -1 if it never does.
static func _segment_enters(box: AABB, from: Vector3, to: Vector3) -> float:
	if box.has_point(from):
		return 0.0
	var d := to - from
	var t0 := 0.0
	var t1 := 1.0
	for axis in 3:
		var lo := box.position[axis]
		var hi := box.position[axis] + box.size[axis]
		if absf(d[axis]) < 1e-9:
			if from[axis] < lo or from[axis] > hi:
				return -1.0
			continue
		var a := (lo - from[axis]) / d[axis]
		var b := (hi - from[axis]) / d[axis]
		if a > b:
			var tmp := a
			a = b
			b = tmp
		t0 = maxf(t0, a)
		t1 = minf(t1, b)
		if t0 > t1:
			return -1.0
	return t0
