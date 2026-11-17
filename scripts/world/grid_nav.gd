extends RefCounted
## Grid pathfinding over a room's floor cells (AStarGrid2D). Rooms are small
## grids, so this is simpler and more predictable than a navmesh. Thin walls
## between cells (a house's, edge_grid.gd) stop you too: only doors go through.

const EdgeGrid := preload("res://scripts/world/edge_grid.gd")

var astar := AStarGrid2D.new()
var size := Vector2i.ZERO
var walls: Dictionary = {}     # thin walls: {"h|x|z": true, "v|x|z": true}


func setup(w: int, d: int, blocked: Array, wall_keys: Dictionary = {}) -> void:
	# A fresh grid each time: update() keeps old solid cells when the size is
	# unchanged, so removed blocks would stay "solid" after an undo.
	walls = wall_keys
	if walls.is_empty():
		astar = AStarGrid2D.new()
	else:
		var eg := EdgeGrid.new()
		eg.walls = walls
		astar = eg
	size = Vector2i(w, d)
	astar.region = Rect2i(0, 0, w, d)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for c in blocked:
		if in_bounds(c):
			astar.set_point_solid(c, true)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not astar.is_point_solid(c)


## The same clearance rule for keys, analog steering and click paths.
func can_step(a: Vector2i, b: Vector2i) -> bool:
	if not walkable(b) or not in_bounds(a) or blocked_between(a, b):
		return false
	var d := b - a
	if absi(d.x) > 1 or absi(d.y) > 1:
		return false
	if d.x != 0 and d.y != 0:
		return walkable(a + Vector2i(d.x, 0)) and walkable(a + Vector2i(0, d.y))
	return true


## True when a footprint of `radius` around `p` sits wholly on walkable cells, with no
## thin wall or blocked corner between its centre cell and the cells its corners touch.
func occupiable(p: Vector2, radius: float = 0.16) -> bool:
	var centre := Vector2i(floori(p.x), floori(p.y))
	if not walkable(centre):
		return false
	for offset in [Vector2(radius, radius), Vector2(-radius, radius), Vector2(radius, -radius), Vector2(-radius, -radius)]:
		var q: Vector2 = p + offset
		if not can_step(centre, Vector2i(floori(q.x), floori(q.y))):
			return false
	return true


## A small footprint, sampled along the segment. Each crossed edge is checked;
## continuous movement and smoothing cannot slip through a house's thin walls.
func segment_clear(a: Vector2, b: Vector2, radius: float = 0.16) -> bool:
	var count := maxi(1, ceili(a.distance_to(b) / 0.12))
	for offset in [Vector2.ZERO, Vector2(radius, radius), Vector2(-radius, radius), Vector2(radius, -radius), Vector2(-radius, -radius)]:
		var before := Vector2i(floori(a.x + offset.x), floori(a.y + offset.y))
		for i in range(1, count + 1):
			var p: Vector2 = a.lerp(b, float(i) / count) + offset
			var c := Vector2i(floori(p.x), floori(p.y))
			if not can_step(before, c):
				return false
			before = c
	return true


## A cell path as smooth straight runs: skips corners while the straight line
## (with the walker's footprint) stays clear of solid cells, corners and thin
## walls. Always ends exactly on the last cell's centre.
func smooth(start: Vector2, cells: Array[Vector2i], radius: float = 0.16) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if cells.is_empty():
		return out
	var at := start
	var i := 0
	while i < cells.size():
		# Grow the straight run while it stays clear (at most 24 cells ahead).
		var best := i
		for j in range(i + 1, mini(cells.size(), i + 25)):
			if not segment_clear(at, Vector2(cells[j]) + Vector2(0.5, 0.5), radius):
				break
			best = j
		var p := Vector2(cells[best]) + Vector2(0.5, 0.5)
		out.append(p)
		at = p
		i = best + 1
	return out


## Path length in steps from `from` to `to` (0 when already there, -1 when unreachable).
func cost(from: Vector2i, to: Vector2i) -> float:
	if from == to:
		return 0.0 if walkable(to) else -1.0
	var route := path(from, to)
	if route.is_empty():
		return -1.0
	var total := 0.0
	var before := from
	for c in route:
		total += 1.41421 if c.x != before.x and c.y != before.y else 1.0
		before = c
	return total


## Cells from `from` to `to` (excluding `from`). Empty if unreachable.
func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not walkable(to) or not in_bounds(from):
		return out
	var was_solid := astar.is_point_solid(from)
	astar.set_point_solid(from, false)  # we may be standing on a blocked edge
	var ids := astar.get_id_path(from, to)
	astar.set_point_solid(from, was_solid)
	for i in range(1, ids.size()):
		if not walls.is_empty() and blocked_between(ids[i - 1], ids[i]):
			out.clear()
			return out   # only through a wall: there's no way
		out.append(ids[i])
	return out


## True when a thin wall stands between two neighbouring cells.
func blocked_between(a: Vector2i, b: Vector2i) -> bool:
	if walls.is_empty() or not astar is EdgeGrid:
		return false
	return (astar as EdgeGrid).crosses(a, b)


## The walkable cell next to `target` that is closest to `from`
## (used to stand beside a character or sign before talking).
func best_neighbor(target: Vector2i, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var c := target + Vector2i(dx, dy)
			if not walkable(c) or blocked_between(c, target):
				continue
			var d := cost(from, c)
			if d < 0.0:
				continue
			d += 0.4 if dx != 0 and dy != 0 else 0.0
			if c == from:
				d = -1.0
			if d < best_d:
				best_d = d
				best = c
	return best


## Nearest walkable cell to `c` (spiral search), for spawning safely.
func nearest_walkable(c: Vector2i) -> Vector2i:
	if walkable(c):
		return c
	for r in range(1, max(size.x, size.y)):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if walkable(n):
					return n
	return Vector2i(0, 0)


func random_walkable(rng: RandomNumberGenerator) -> Vector2i:
	for i in 40:
		var c := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
		if walkable(c):
			return c
	return nearest_walkable(size / 2)
