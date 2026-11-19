extends RefCounted
## Level templates in the Library: a room (or a few linked rooms) with the
## tile sets they need bundled alongside, so applying one into any world
## just works ("copy on use"). Also Stamps: small area templates.
##
##   library/templates/<id>/template.json + thumb.png + tilesets/<set>/...
##   library/stamps/<id>/stamp.json + thumb.png + tilesets/<set>/...

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const Defaults := preload("res://scripts/core/defaults.gd")

const META := "template.json"
const STAMP_META := "stamp.json"


static func dir(kind: String = "templates") -> String:
	return SaveManager.global_path("library").path_join(kind)


static func ids(kind: String = "templates") -> PackedStringArray:
	var out := PackedStringArray()
	for d in JsonUtil.list_dirs(dir(kind)):
		if FileAccess.file_exists(dir(kind).path_join(d).path_join(META if kind == "templates" else STAMP_META)):
			out.append(d)
	return out


static func load_template(id: String, kind: String = "templates") -> Dictionary:
	var data: Variant = JsonUtil.read_json(dir(kind).path_join(id).path_join(META if kind == "templates" else STAMP_META), {})
	var t: Dictionary = data if data is Dictionary else {}
	t["id"] = id
	t["kind"] = kind
	if not t.has("tags") or not t.tags is Array:
		t["tags"] = []
	return t


static func all(kind: String = "templates") -> Array:
	var out: Array = []
	for id in ids(kind):
		out.append(load_template(id, kind))
	out.sort_custom(func(a, b): return (bool(a.get("builtin", false)) and not bool(b.get("builtin", false))) or (bool(a.get("builtin", false)) == bool(b.get("builtin", false)) and str(a.get("name", "")) < str(b.get("name", ""))))
	return out


static func thumb_path(id: String, kind: String = "templates") -> String:
	var p := dir(kind).path_join(id).path_join("thumb.png")
	return p if FileAccess.file_exists(p) else ""


static func delete(id: String, kind: String = "templates") -> void:
	if id != "" and id.find("..") == -1:
		JsonUtil.remove_tree(dir(kind).path_join(id))


## Tile sets referenced by rooms/stamps (by set id).
static func sets_used(rooms: Array) -> PackedStringArray:
	var out := PackedStringArray()
	const TileLayers := preload("res://scripts/world/tile_layers.gd")
	for r in rooms:
		for st in TileLayers.tiles_used(r):
			if not st[0] in out:
				out.append(st[0])
		for e in r.get("tiles", []):
			var tex := str(e.get("texture", ""))
			if tex.begins_with("tilesets/"):
				var sid := tex.split("/")[1]
				if not sid in out:
					out.append(sid)
		for o in r.get("objects", []):
			var tex := str(o.get("texture", ""))
			if tex.begins_with("tilesets/") and not tex.split("/")[1] in out:
				out.append(tex.split("/")[1])
	return out


## Copies the active world's tile sets a template needs into its folder.
static func _bundle_sets(folder: String, set_ids: PackedStringArray) -> void:
	for sid in set_ids:
		var src := Tilesets.set_dir(sid) if Tilesets.exists(sid) else Tilesets.set_dir(sid, true)
		if DirAccess.dir_exists_absolute(src):
			JsonUtil.copy_tree(src, folder.path_join("tilesets").path_join(sid))


## Brings a template's bundled sets into the active world (if missing).
static func _unbundle_sets(folder: String) -> void:
	for sid in JsonUtil.list_dirs(folder.path_join("tilesets")):
		if not Tilesets.exists(sid):
			JsonUtil.copy_tree(folder.path_join("tilesets").path_join(sid), Tilesets.set_dir(sid))


# --- Level templates --------------------------------------------------------------------------

## Saves rooms of the active world as a template. Returns the template id.
static func save_from_rooms(name: String, description: String, tags: Array, room_ids: PackedStringArray, thumb: Image = null, builtin: bool = false) -> String:
	var id := SaveManager.unique_id(name, ids())
	var folder := dir().path_join(id)
	JsonUtil.ensure_dir(folder)
	var rooms := {}
	for rid in room_ids:
		var r := SaveManager.load_room(rid)
		rooms[rid] = r
	return save_rooms(id, name, description, tags, rooms, str(room_ids[0]) if not room_ids.is_empty() else "", thumb, builtin)


## Saves already-built room dictionaries (used by the built-ins too).
static func save_rooms(id: String, name: String, description: String, tags: Array, rooms: Dictionary, start_room: String, thumb: Image = null, builtin: bool = false) -> String:
	var folder := dir().path_join(id)
	JsonUtil.ensure_dir(folder)
	var t := {"version": 1, "id": id, "name": name, "description": description, "tags": tags, "builtin": builtin,
		"start_room": start_room if start_room != "" else str(rooms.keys()[0]), "rooms": rooms, "created": Time.get_datetime_string_from_system(false, false)}
	JsonUtil.write_json(folder.path_join(META), t)
	_bundle_sets(folder, sets_used(rooms.values()))
	if thumb:
		thumb.save_png(folder.path_join("thumb.png"))
	return id


## Makes new rooms from a template (ids made unique, doors re-linked, tile
## sets copied in). Returns the new room ids, start room first.
static func new_level(id: String) -> PackedStringArray:
	var t := load_template(id)
	var rooms: Dictionary = t.get("rooms", {})
	if rooms.is_empty():
		return PackedStringArray()
	_unbundle_sets(dir().path_join(id))
	var taken := SaveManager.list_rooms()
	var map := {}
	var order: Array = rooms.keys()
	var start := str(t.get("start_room", order[0]))
	order.erase(start)
	order.insert(0, start)
	for old in order:
		var new_id := SaveManager.unique_id(str(rooms[old].get("name", old)), taken)
		taken.append(new_id)
		map[old] = new_id
	var out := PackedStringArray()
	for old in order:
		var r: Dictionary = rooms[old].duplicate(true)
		r["id"] = map[old]
		for o in r.get("objects", []):
			var target := str(o.get("door_target", ""))
			if target != "":
				o["door_target"] = str(map.get(target, ""))  # doors to rooms outside the template are unlinked
		SaveManager.save_room(r)
		out.append(map[old])
	return out


## Applies a template's start room onto an existing room. mode "replace"
## swaps everything (size too); "merge" keeps the room's own tiles where the
## template has none and keeps its doors.
static func apply_to_room(id: String, room_id: String, mode: String = "replace") -> bool:
	var t := load_template(id)
	var rooms: Dictionary = t.get("rooms", {})
	if rooms.is_empty() or not SaveManager.room_exists(room_id):
		return false
	_unbundle_sets(dir().path_join(id))
	var src: Dictionary = rooms[str(t.get("start_room", rooms.keys()[0]))].duplicate(true)
	var dst := SaveManager.load_room(room_id)
	if mode == "replace":
		var keep_name := str(dst.get("name", room_id))
		var doors: Array = dst.get("objects", []).filter(func(o): return str(o.get("type", "")) == "door")
		dst = src
		dst["id"] = room_id
		dst["name"] = keep_name
		for o in dst.get("objects", []):
			if str(o.get("type", "")) == "door":
				o["door_target"] = ""
		for door in doors:  # the room's existing doors still lead where they led
			var kept: Dictionary = door.duplicate(true)
			var x := int(kept.pos[0])
			var z := int(kept.pos[2])
			if not RoomEditor.in_bounds(dst, x, z) or not RoomEditor.object_at(dst, x, z).is_empty():
				var found := false
				for radius in maxi(int(dst.size.w), int(dst.size.d)):
					for dz in range(-radius, radius + 1):
						for dx in range(-radius, radius + 1):
							var nx := clampi(x + dx, 0, int(dst.size.w) - 1)
							var nz := clampi(z + dz, 0, int(dst.size.d) - 1)
							if RoomEditor.object_at(dst, nx, nz).is_empty():
								x = nx
								z = nz
								found = true
								break
						if found:
							break
					if found:
						break
				if not found:
					continue
				kept["pos"] = [x, RoomEditor.stack_top(dst, x, z), z]
			dst["objects"].append(kept)
	else:
		var w := maxi(int(dst.size.w), int(src.size.w))
		var d := maxi(int(dst.size.d), int(src.size.d))
		RoomEditor.resize(dst, w, d)
		var stamp := RoomOps.copy_region(src, Vector2i.ZERO, Vector2i(int(src.size.w) - 1, int(src.size.d) - 1))
		stamp["objects"] = stamp.objects.filter(func(o): return str(o.get("type", "")) != "door")
		RoomOps.paste(dst, stamp, Vector2i.ZERO, "merge")
		for surface in ["floor", "wall", "sky"]:
			dst[surface] = src.get(surface, dst[surface])
	return SaveManager.save_room(dst)


# --- Stamps (area templates) ------------------------------------------------------------------

static func save_stamp(name: String, stamp: Dictionary, thumb: Image = null) -> String:
	var id := SaveManager.unique_id(name, ids("stamps"))
	var folder := dir("stamps").path_join(id)
	JsonUtil.ensure_dir(folder)
	var s: Dictionary = stamp.duplicate(true)
	s["id"] = id
	s["name"] = name.strip_edges() if name.strip_edges() != "" else "Stamp"
	JsonUtil.write_json(folder.path_join(STAMP_META), s)
	_bundle_sets(folder, sets_used([s]))
	if thumb:
		thumb.save_png(folder.path_join("thumb.png"))
	return id


## Loads a stamp and makes sure its tile sets exist in the active world.
static func stamp_for_use(id: String) -> Dictionary:
	_unbundle_sets(dir("stamps").path_join(id))
	return load_template(id, "stamps")
