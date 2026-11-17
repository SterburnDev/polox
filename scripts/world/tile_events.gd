extends RefCounted
## Small opt-in tile triggers. The cell claims its once flag before applying
## an effect so a room transition or quit cannot fire a one-shot twice.

const TileLayers := preload("res://scripts/world/tile_layers.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const Synth := preload("res://scripts/core/synth.gd")


static func claim(room: Dictionary, layer_id: String, cell: Vector2i, trigger: String) -> Dictionary:
	var layer := TileLayers.find(room, layer_id)
	var data := TileLayers.get_cell(layer, cell.x, cell.y)
	var event: Variant = data.get("event", {})
	if not event is Dictionary or str(event.get("trigger", "")) != trigger:
		return {}
	if bool(event.get("once", true)) and bool(data.get("event_done", false)):
		return {}
	if bool(event.get("once", true)):
		data["event_done"] = true
		TileLayers.put(layer, cell.x, cell.y, data)
	return event


static func fire(world: Node, cell: Vector2i, trigger: String) -> bool:
	for layer in TileLayers.all(world.room.data):
		var event := claim(world.room.data, str(layer.id), cell, trigger)
		if event.is_empty():
			continue
		if bool(event.get("once", true)):
			SaveManager.save_room(world.room.data)
		var value := str(event.get("value", ""))
		match str(event.get("action", "text")):
			"text":
				world.talk.show_text("", value if value != "" else "A little memory stirs here.")
			"sound":
				Synth.play(world, value if value != "" else "chime")
			"teleport":
				var room_id := value.split("|", false)[0].strip_edges()
				if SaveManager.room_exists(room_id):
					world.go_to_room(room_id)
			"lighting":
				world.flash_light(Color.from_string(value, Color("#ffd166")), 1.5)
			"layer":
				var bits := value.split("|", false)
				if bits.size() >= 2:
					RoomOps.set_layer_state(world.room.data, bits[0], "visible", bits[1].to_lower() in ["1", "true", "show"])
					SaveManager.save_room(world.room.data)
					world.rebuild_room()
		return true
	return false
