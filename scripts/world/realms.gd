extends RefCounted
## The two worlds (world v8, Phase 29). **The Dream World** is everything the game had before: your
## places, Lancer and your other friends, Build mode, Platform Mode, battles, fountains, and the
## Deep (the strange copies a fountain makes of a place, dark_worlds.gd). **The Light World** is your
## real home and neighbourhood, rebuilt from what you tell Polox (light_home.gd): calmer, real-life
## colours and proportions, your real clock, building limited to furniture and decor.
##
## Light World places live outside the world slots, in <save root>/my_home/places/ (ids start with
## "lw_"), so they're private: never in a world's snapshots, exports, templates or phone sync, never in
## the chat AI's context, and every world on this PC shares the one real home.
##
## A gate is a Dream Gate that crosses between the worlds: {"type": "dark_fountain", "gate": true,
## "leads": "light" | "dark", "target": "<place id>", "state": "open"}. The Dream World's gate sits in
## its start place and leads to your room; your room's gate leads back to the Dream World (to the place
## you last came from, else the start place).

const RoomEditor := preload("res://scripts/world/room_editor.gd")

const LIGHT := "light"
const DARK := "dark"
const PREFIX := "lw_"
## Your room: where the Light World starts, and where its fountain to the Dream World stands.
const ENTRY := "lw_my_room"
const LABELS := {"light": "Light World", "dark": "Dream World"}
const ICONS := {"light": "☀", "dark": "🌙"}


static func is_light_id(id: String) -> bool:
	return id.begins_with(PREFIX)


static func realm(room: Dictionary) -> String:
	return LIGHT if is_light_id(str(room.get("id", ""))) or str(room.get("realm", "")) == LIGHT else DARK


static func is_light(room: Dictionary) -> bool:
	return realm(room) == LIGHT


static func label(r: String) -> String:
	return str(LABELS.get(r, "Dream World"))


# --- Gates ---------------------------------------------------------------------------------------

static func is_gate(o: Dictionary) -> bool:
	return str(o.get("type", "")) == "dark_fountain" and bool(o.get("gate", false))


static func gates(room: Dictionary) -> Array:
	return (room.get("objects", []) as Array).filter(func(o): return o is Dictionary and is_gate(o))


static func gate_of(room: Dictionary) -> Dictionary:
	var g := gates(room)
	return g[0] if not g.is_empty() else {}


## Puts a gate on the free cell nearest `near` (not on an edge, not on anything). {} when there's no room.
static func add_gate(room: Dictionary, near: Vector2i, leads: String, target: String) -> Dictionary:
	var w := int(room.get("size", {}).get("w", 12))
	var d := int(room.get("size", {}).get("d", 10))
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for z in range(1, d - 1):
		for x in range(1, w - 1):
			if not RoomEditor.object_at(room, x, z).is_empty() or RoomEditor.stack_top(room, x, z) > 0.0:
				continue
			# Keep the cell in front (south) free too, so you can land beside it.
			if z + 1 < d and (not RoomEditor.object_at(room, x, z + 1).is_empty() or RoomEditor.stack_top(room, x, z + 1) > 0.0):
				continue
			var dist := absi(x - near.x) + absi(z - near.y)
			if dist > 0 and dist < best_d:
				best_d = dist
				best = Vector2i(x, z)
	if best.x < 0:
		return {}
	var o := RoomEditor.add_object(room, best.x, best.y, "dark_fountain")
	if o.is_empty():
		return {}
	o.merge({"gate": true, "leads": leads, "target": target, "state": "open",
		"label": "The way home" if leads == LIGHT else "Dream Gate"}, true)
	return o


## The Dream World's gate in this world (place id + object), searching the start place first.
static func dark_gate(rooms: Dictionary, start: String) -> Dictionary:
	var order: Array = [start] if rooms.has(start) else []
	for id in rooms:
		if not id in order:
			order.append(id)
	for id in order:
		for g in gates(rooms[id]):
			if str(g.get("leads", "")) == LIGHT:
				return {"place": str(id), "gate": g}
	return {}
