extends AStarGrid2D
## Grid pathfinding with thin walls between cells (the Light World's houses: walls stand on the cell
## lines, not in cells). A step across a wall costs so much that A* only takes it when there's no other
## way, and grid_nav.gd then refuses such a path. Diagonal steps can't cut round a wall's end.
##
## `walls`: {"h|x|z": true} for a wall from (x, z) to (x + 1, z), {"v|x|z": true} from (x, z) to (x, z + 1).

const WALL_COST := 100000.0

var walls: Dictionary = {}


static func key(dir: String, x: int, z: int) -> String:
	return "%s|%d|%d" % [dir, x, z]


## True when a single step from a to b (neighbours, diagonals included) crosses a wall.
func crosses(a: Vector2i, b: Vector2i) -> bool:
	if walls.is_empty():
		return false
	var d := b - a
	if d.x != 0 and d.y != 0:
		var via_x := a + Vector2i(d.x, 0)
		var via_z := a + Vector2i(0, d.y)
		return crosses(a, via_x) or crosses(via_x, b) or crosses(a, via_z) or crosses(via_z, b)
	if d.x == 1:
		return walls.has(key("v", a.x + 1, a.y))
	if d.x == -1:
		return walls.has(key("v", a.x, a.y))
	if d.y == 1:
		return walls.has(key("h", a.x, a.y + 1))
	if d.y == -1:
		return walls.has(key("h", a.x, a.y))
	return false


func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
	var base := Vector2(to_id - from_id).length()
	return base + (WALL_COST if crosses(from_id, to_id) else 0.0)


func _estimate_cost(from_id: Vector2i, end_id: Vector2i) -> float:
	var d := (end_id - from_id).abs()
	return float(maxi(d.x, d.y)) + 0.41421 * float(mini(d.x, d.y))
