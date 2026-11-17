extends RefCounted
## Tile-only find/replace and name-based room re-skin operations. Returned
## counts let the editor report exactly what changed in one undoable action.

const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")


static func find_replace(room: Dictionary, from_set: String, from_tile: String, to_set: String, to_tile: String, layer_id: String = "") -> int:
	if from_set == "" or from_tile == "" or to_set == "" or Tilesets.info(to_set, to_tile).is_empty():
		return 0
	var changed := 0
	for layer in TileLayers.all(room):
		if layer_id != "" and str(layer.id) != layer_id:
			continue
		for key in layer.cells.keys():
			var cell: Dictionary = layer.cells[key]
			if str(cell.get("s", "")) != from_set or str(cell.get("t", "")) != from_tile:
				continue
			cell["s"] = to_set
			cell["t"] = to_tile
			cell.erase("smart_group")
			cell.erase("smart_mask")
			cell.erase("smart_tile")
			layer.cells[key] = cell
			changed += 1
	return changed


static func reskin(room: Dictionary, from_set: String, to_set: String, layer_id: String = "") -> int:
	var source := Tilesets.cached_set(from_set)
	var target := Tilesets.cached_set(to_set)
	if source.is_empty() or target.is_empty():
		return 0
	var by_name := {}
	for tile in target.get("tiles", []):
		by_name[str(tile.get("name", "")).strip_edges().to_lower()] = str(tile.get("id", ""))
	var changed := 0
	for layer in TileLayers.all(room):
		if layer_id != "" and str(layer.id) != layer_id:
			continue
		for key in layer.cells.keys():
			var cell: Dictionary = layer.cells[key]
			if str(cell.get("s", "")) != from_set:
				continue
			var old := Tilesets.info(from_set, str(cell.get("t", "")))
			var replacement := str(by_name.get(str(old.get("name", "")).strip_edges().to_lower(), ""))
			if replacement == "":
				continue
			cell["s"] = to_set
			cell["t"] = replacement
			cell.erase("smart_group")
			cell.erase("smart_mask")
			cell.erase("smart_tile")
			layer.cells[key] = cell
			changed += 1
	return changed
