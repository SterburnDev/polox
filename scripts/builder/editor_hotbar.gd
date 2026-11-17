extends RefCounted
## Nine persistent editor favourites plus a short recent list.

const SLOTS_KEY := "editor_hotbar"
const RECENT_KEY := "editor_recent"


static func slots() -> Array:
	var value: Variant = GameState.settings.get(SLOTS_KEY, [])
	var out: Array = value.duplicate(true) if value is Array else []
	out.resize(9)
	return out


static func recent() -> Array:
	var value: Variant = GameState.settings.get(RECENT_KEY, [])
	return value.duplicate(true) if value is Array else []


static func capture(build: Node) -> Dictionary:
	if build.tool == "stamp" and not build.stamp.is_empty():
		return {"kind": "stamp", "stamp": build.stamp.duplicate(true), "name": "Stamp"}
	if build.piece == "tile" and build.brush_set != "" and build.brush_tile != "":
		return {"kind": "tile", "set": build.brush_set, "tile": build.brush_tile, "layer": build.layer, "smart_group": build.smart_group}
	if build.piece == "pickup":
		return {"kind": "item", "item": build.pickup_item, "name": "Pickup"}
	if build.mode == "objects" or build.piece in ["door", "sign", "prop", "pickup"]:
		return {"kind": "object", "piece": build.piece, "color": build.color, "texture": build.texture, "name": str(build.piece).capitalize()}
	return {"kind": "piece", "piece": build.piece, "color": build.color, "texture": build.texture, "name": str(build.piece).capitalize()}


static func label(entry: Dictionary, empty_text: String = "-") -> String:
	match str(entry.get("kind", "")):
		"tile":
			return str(entry.get("tile", "tile")).replace("_", " ").capitalize()
		"stamp":
			return "Stamp"
		"item":
			return str(entry.get("name", "Item"))
		_:
			return str(entry.get("name", entry.get("piece", empty_text))).capitalize()


static func pin(index: int, entry: Dictionary) -> void:
	var all := slots()
	if index < 0 or index >= all.size():
		return
	all[index] = entry.duplicate(true)
	GameState.settings[SLOTS_KEY] = all
	GameState.save_settings()


static func clear(index: int) -> void:
	var all := slots()
	if index < 0 or index >= all.size():
		return
	all[index] = {}
	GameState.settings[SLOTS_KEY] = all
	GameState.save_settings()


static func record(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var all := recent()
	var key := JSON.stringify(entry)
	all = all.filter(func(e): return JSON.stringify(e) != key)
	all.push_front(entry.duplicate(true))
	if all.size() > 9:
		all.resize(9)
	GameState.settings[RECENT_KEY] = all
	GameState.save_settings()


static func activate(build: Node, entry: Dictionary) -> bool:
	match str(entry.get("kind", "")):
		"tile":
			build.set_layer(str(entry.get("layer", build.layer)))
			build.set_brush_tile(str(entry.get("set", "")), str(entry.get("tile", "")))
			if str(entry.get("smart_group", "")) != "":
				build.set_smart_group(str(entry.smart_group))
		"stamp":
			build.set_stamp(entry.get("stamp", {}).duplicate(true))
		"item":
			build.pickup_item = str(entry.get("item", ""))
			build.set_piece("pickup")
		"piece", "object":
			build.set_piece(str(entry.get("piece", "cube")))
			build.set_paint(str(entry.get("color", "#8a7bc8")), str(entry.get("texture", "")))
		_:
			return false
	return true
