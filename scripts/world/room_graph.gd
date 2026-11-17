extends RefCounted
## World-map graph operations. Connecting two nodes creates one reachable
## door in each room; positions are presentation-only world metadata.

const RoomEditor := preload("res://scripts/world/room_editor.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")


static func auto_layout(ids: PackedStringArray) -> Dictionary:
	var out := {}
	for i in ids.size():
		out[ids[i]] = {"x": i % 3, "y": floori(float(i) / 3.0)}
	return out


static func links(room: Dictionary) -> Array:
	var out: Array = []
	for obj in room.get("objects", []):
		if str(obj.get("type", "")) == "door" and str(obj.get("door_target", "")) != "":
			out.append(str(obj.door_target))
	return out


static func connect_rooms(a: Dictionary, b: Dictionary) -> bool:
	var aid := str(a.get("id", ""))
	var bid := str(b.get("id", ""))
	if aid == "" or bid == "" or aid == bid:
		return false
	# Work on copies so a failure to find the second door cannot leave a one-way
	# link in the caller's room data.
	var next_a := a.duplicate(true)
	var next_b := b.duplicate(true)
	if not links(next_a).has(bid):
		var pa := _free_cell(next_a)
		var da := RoomEditor.add_object(next_a, pa.x, pa.y, "door")
		if da.is_empty():
			return false
		da["door_target"] = bid
	if not links(next_b).has(aid):
		var pb := _free_cell(next_b)
		var db := RoomEditor.add_object(next_b, pb.x, pb.y, "door")
		if db.is_empty():
			return false
		db["door_target"] = aid
	a.clear()
	a.merge(next_a, true)
	b.clear()
	b.merge(next_b, true)
	return true


static func valid_links(ids: PackedStringArray, room_by_id: Dictionary) -> bool:
	var allowed := {}
	for id in ids:
		allowed[id] = true
	for id in ids:
		var room: Dictionary = room_by_id.get(id, {})
		if room.is_empty():
			return false
		for target in links(room):
			if not allowed.has(target):
				return false
	return true


static func _free_cell(room: Dictionary) -> Vector2i:
	var w := int(room.get("size", {}).get("w", 12))
	var d := int(room.get("size", {}).get("d", 10))
	var spawn: Array = room.get("spawn", [w / 2, d / 2])
	var center := Vector2i(int(spawn[0]), int(spawn[1]))
	for radius in maxi(w, d):
		for z in range(maxi(0, center.y - radius), mini(d, center.y + radius + 1)):
			for x in range(maxi(0, center.x - radius), mini(w, center.x + radius + 1)):
				if RoomEditor.object_at(room, x, z).is_empty() and not RoomOps.blocks_walk(room, x, z):
					return Vector2i(x, z)
	return Vector2i(clampi(center.x, 0, w - 1), clampi(center.y, 0, d - 1))
