extends RefCounted
## What Platform Mode remembers, in world.json (so it travels with the world,
## its snapshots and Phone Link):
##   platform = {enabled, pillars: ["room/id"], checkpoints: ["room/id"],
##               last_checkpoint: {room, id, cell}, shards: ["room/id"],
##               resume: {room, cell}}
## Nothing mid-air is ever saved: `resume` is where a save or quit during
## Platform Mode puts you back (normal mode) next time: the last checkpoint,
## else next to the pillar you started from.

static func data() -> Dictionary:
	var w: Dictionary = GameState.world
	if not w.get("platform") is Dictionary:
		w["platform"] = {}
	var p: Dictionary = w.platform
	for k in ["pillars", "checkpoints", "shards"]:
		if not p.get(k) is Array:
			p[k] = []
	if not p.has("enabled"):
		p["enabled"] = true
	return p


static func _key(room_id: String, obj_id: String) -> String:
	return "%s/%s" % [room_id, obj_id]


static func enabled() -> bool:
	return bool(data().get("enabled", true))


static func set_enabled(on: bool) -> void:
	data()["enabled"] = on
	GameState.save_world()


static func pillar_used(room_id: String, obj_id: String) -> bool:
	return _key(room_id, obj_id) in data().pillars


static func mark_pillar(room_id: String, obj_id: String) -> void:
	var p := data()
	if not _key(room_id, obj_id) in p.pillars:
		(p.pillars as Array).append(_key(room_id, obj_id))
	GameState.save_world()


static func checkpoint_lit(room_id: String, obj_id: String) -> bool:
	return _key(room_id, obj_id) in data().checkpoints


## Returns true the first time this checkpoint is reached.
static func light_checkpoint(room_id: String, obj_id: String, cell: Vector2i) -> bool:
	var p := data()
	var first: bool = not _key(room_id, obj_id) in p.checkpoints
	if first:
		(p.checkpoints as Array).append(_key(room_id, obj_id))
	p["last_checkpoint"] = {"room": room_id, "id": obj_id, "cell": [cell.x, cell.y]}
	p["resume"] = {"room": room_id, "cell": [cell.x, cell.y]}
	GameState.world["last_room"] = room_id   # a quit now comes back to this room
	GameState.save_world()
	return first


static func last_checkpoint() -> Dictionary:
	var c: Variant = data().get("last_checkpoint")
	return c if c is Dictionary else {}


static func shard_taken(room_id: String, obj_id: String) -> bool:
	return _key(room_id, obj_id) in data().shards


## Returns true if it was new.
static func take_shard(room_id: String, obj_id: String) -> bool:
	var p := data()
	if _key(room_id, obj_id) in p.shards:
		return false
	(p.shards as Array).append(_key(room_id, obj_id))
	GameState.save_world()
	return true


static func shard_count() -> int:
	return (data().shards as Array).size()


static func set_resume(room_id: String, cell: Vector2i) -> void:
	data()["resume"] = {"room": room_id, "cell": [cell.x, cell.y]}
	GameState.world["last_room"] = room_id   # the next start loads this room, then takes the spot
	GameState.save_world()


static func clear_resume() -> void:
	if data().has("resume"):
		data().erase("resume")
		GameState.save_world()


## Where to stand when this room loads after a save/quit in Platform Mode
## (Vector2i(-1, -1) = nowhere special). Used once.
static func take_resume(room_id: String) -> Vector2i:
	var r: Variant = data().get("resume")
	if not r is Dictionary or str(r.get("room", "")) != room_id:
		return Vector2i(-1, -1)
	var c: Array = r.get("cell", [-1, -1])
	data().erase("resume")
	GameState.save_world()
	return Vector2i(int(c[0]), int(c[1])) if c.size() == 2 else Vector2i(-1, -1)
