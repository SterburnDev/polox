extends RefCounted
## Cardinal autotiling. A bit mask is N=1, E=2, S=4, W=8; absent variants
## always fall back to the group's plain tile, so partial atlases stay usable.

const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const BITS := [1, 2, 4, 8]


static func mask_from_neighbors(north: bool, east: bool, south: bool, west: bool) -> int:
	return (1 if north else 0) | (2 if east else 0) | (4 if south else 0) | (8 if west else 0)


static func mask(room: Dictionary, layer_id: String, pos: Vector2i, set_id: String, group_id: String) -> int:
	var layer := TileLayers.find(room, layer_id)
	var out := 0
	for i in DIRS.size():
		var neighbor := TileLayers.get_cell(layer, pos.x + DIRS[i].x, pos.y + DIRS[i].y)
		if str(neighbor.get("s", "")) == set_id and str(neighbor.get("smart_group", "")) == group_id:
			out |= BITS[i]
	return out


static func group(set_id: String, group_id: String) -> Dictionary:
	var set_data := Tilesets.cached_set(set_id)
	for raw in set_data.get("smart_groups", []):
		if raw is Dictionary and str(raw.get("id", "")) == group_id:
			return raw
	return {}


## Makes an autotile group from up to 16 atlas-sliced tiles, in mask order.
static func assign(set_id: String, name: String, variants: Array, fallback: String) -> String:
	var data := Tilesets.load_set(set_id)
	if data.is_empty() or Tilesets.find_tile(data, fallback).is_empty():
		return ""
	var choices := PackedStringArray()
	for i in 16:
		var tile_id := str(variants[i]) if i < variants.size() else ""
		choices.append(tile_id if not Tilesets.find_tile(data, tile_id).is_empty() else fallback)
	var id := SaveManager.unique_id(name.strip_edges() if name.strip_edges() != "" else fallback, PackedStringArray())
	var groups: Array = data.get("smart_groups", [])
	groups = groups.filter(func(g): return str(g.get("id", "")) != id)
	groups.append({"id": id, "name": name.strip_edges().substr(0, 40), "fallback": fallback, "variants": Array(choices)})
	data["version"] = maxi(2, int(data.get("version", 1)))
	data["smart_groups"] = groups
	return id if Tilesets.save_set(data) else ""


static func tile_for(set_id: String, group_id: String, mask_value: int) -> String:
	var g := group(set_id, group_id)
	if g.is_empty():
		return ""
	var variants: Array = g.get("variants", [])
	if mask_value >= 0 and mask_value < variants.size() and str(variants[mask_value]) != "":
		return str(variants[mask_value])
	return str(g.get("fallback", ""))


## Paints the center and reevaluates its N/E/S/W neighbors; returns touched cells.
static func paint(room: Dictionary, layer_id: String, pos: Vector2i, set_id: String, group_id: String) -> Array:
	var g := group(set_id, group_id)
	if g.is_empty():
		return []
	var touched: Array = []
	var positions: Array = [pos]
	for direction in DIRS:
		positions.append(pos + direction)
	for index in positions.size():
		var p: Vector2i = positions[index]
		if not TileLayers.get_cell(TileLayers.find(room, layer_id), p.x, p.y).is_empty() or p == pos:
			if p == pos:
				var fallback := str(g.get("fallback", ""))
				var made := TileLayers.make_cell(set_id, fallback, "", {"smart_group": group_id})
				TileLayers.put(TileLayers.find(room, layer_id), p.x, p.y, made)
			var cell := TileLayers.get_cell(TileLayers.find(room, layer_id), p.x, p.y)
			if str(cell.get("smart_group", "")) == group_id and str(cell.get("s", "")) == set_id:
				var mask_value := mask(room, layer_id, p, set_id, group_id)
				cell["smart_mask"] = mask_value
				cell["smart_tile"] = tile_for(set_id, group_id, mask_value)
				cell["t"] = str(cell.smart_tile)
				TileLayers.put(TileLayers.find(room, layer_id), p.x, p.y, cell)
				touched.append(p)
	return touched


static func erase(room: Dictionary, layer_id: String, pos: Vector2i) -> Array:
	var layer := TileLayers.find(room, layer_id)
	var before := TileLayers.get_cell(layer, pos.x, pos.y)
	if before.is_empty():
		return []
	TileLayers.erase(layer, pos.x, pos.y)
	var touched: Array = [pos]
	var set_id := str(before.get("s", ""))
	var group_id := str(before.get("smart_group", ""))
	if group_id == "":
		return touched
	for d in DIRS:
		var p: Vector2i = pos + d
		var cell := TileLayers.get_cell(layer, p.x, p.y)
		if str(cell.get("s", "")) == set_id and str(cell.get("smart_group", "")) == group_id:
			var m := mask(room, layer_id, p, set_id, group_id)
			cell["smart_mask"] = m
			cell["smart_tile"] = tile_for(set_id, group_id, m)
			cell["t"] = str(cell.smart_tile)
			TileLayers.put(layer, p.x, p.y, cell)
			touched.append(p)
	return touched
