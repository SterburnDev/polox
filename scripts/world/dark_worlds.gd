extends RefCounted
## The Deep: inside the Dream World (since world v8 everything the game had is the Dream World; the Light
## World is your real home, realms.gd), a Dream Gate can turn a place into its Deep version: the same
## layout, stranger skies, glowing outlines, Dream World Me forms, where battles happen. The fountain
## stands in an ordinary place and leads to the Deep place, which has a fountain of its own leading
## back. Sealing a fountain closes it for now: nothing is deleted, the Deep place waits in the archive
## and the fountain can be reopened any time. (Fountains that cross between the Light World and the
## Dream World are gates, realms.gd; fountains() leaves them out.)
##
## Place fields (world v6): "side": "light" (ordinary) | "dark" (the Deep); a Deep place also has
## "dark_of" (the place it was made from, if any), "player_form": "dark" and "look": "dark".
## Fountain objects: {"type": "dark_fountain", "target": "<place id>", "leads": "dark" | "light",
##                    "state": "open" | "sealed" | "new"}  ("new": placed, not yet linked)

const Places := preload("res://scripts/world/places.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")

const TYPE := "dark_fountain"
## Objects that don't come along into a Dream World copy (they lead somewhere else, or are yours).
const LEFT_BEHIND: PackedStringArray = ["door", "dream_door", "platform_pillar", "pickup", "dark_fountain"]


static func side(room: Dictionary) -> String:
	return "dark" if str(room.get("side", "light")) == "dark" else "light"


static func is_dark(room: Dictionary) -> bool:
	return side(room) == "dark"


static func fountains(room: Dictionary) -> Array:
	return (room.get("objects", []) as Array).filter(func(o): return o is Dictionary and str(o.get("type", "")) == TYPE and not bool(o.get("gate", false)))


static func state(o: Dictionary) -> String:
	var s := str(o.get("state", "new"))
	return s if s in ["open", "sealed", "new"] else "new"


static func target(o: Dictionary) -> String:
	return str(o.get("target", ""))


## The Dream World palette: darker, shifted towards violet and teal, a little more saturated.
static func dark_color(c: Color) -> Color:
	var h := fposmod(c.h + wrapf(0.72 - c.h, -0.5, 0.5) * 0.6, 1.0)   # pulled towards violet (0.72), the short way round
	var s := clampf(c.s * 0.7 + 0.35, 0.0, 1.0)
	var v := clampf(c.v * 0.55 + 0.08, 0.0, 1.0)
	return Color.from_hsv(h, s, v, c.a)


static func dark_hex(hex: String, fallback: String = "#2e2552") -> String:
	return "#" + dark_color(Color.from_string(hex, Color(fallback))).to_html(false)


## "Make a Dream World from this place": the same layout in the Dream World palette, a void sky with
## slow shapes and stars, everyone in Dream World Me forms. Doors, Dream Doors, pillars, pickups and
## fountains stay behind (the copy gets its own fountain back). Returns the new place (unsaved).
static func make_from(light: Dictionary, taken: PackedStringArray) -> Dictionary:
	var dark := light.duplicate(true)
	dark["id"] = Places.unique_id(str(light.get("id", "place")) + "_dark", taken)
	dark["name"] = "%s (the Deep)" % str(light.get("name", "Place"))
	dark["side"] = "dark"
	dark["dark_of"] = str(light.get("id", ""))
	dark["player_form"] = "dark"
	dark["look"] = "dark"
	dark["edges"] = {}
	for k in ["floor", "wall", "sky"]:
		var surf: Dictionary = (dark.get(k, {}) as Dictionary).duplicate(true)
		surf["color"] = dark_hex(str(surf.get("color", "#5b4b8a")))
		dark[k] = surf
	dark["sky"]["color"] = "#07040f"
	var w := Places.walls(light)
	for s in Places.SIDES:
		if Places.edge(light, s) != "":
			w[s] = true   # the copy has no neighbour there: close it
	dark["walls"] = w
	dark["background"] = {"sky": "void", "ground": false, "ground_color": "", "layers": [
		{"kind": "shapes", "color": "#7a5cc8", "distance": 3, "seed": hash(str(dark.id)) % 1000},
		{"kind": "stars", "color": "#c9b6ff", "distance": 2, "seed": (hash(str(dark.id)) / 7) % 1000}]}
	for t in dark.get("tiles", []):
		if t is Dictionary and str(t.get("color", "")) != "":
			t["color"] = dark_hex(str(t.color))
	var kept: Array = []
	for o in dark.get("objects", []):
		if o is Dictionary and not str(o.get("type", "")) in LEFT_BEHIND:
			if str(o.get("color", "")) != "":
				o["color"] = dark_hex(str(o.color))
			kept.append(o)
	dark["objects"] = kept
	dark["ambiance"] = {"music": "", "lighting": "dark", "weather": "off"}
	return dark


## Puts a fountain on the free cell nearest `near` (one cell around it if the cell is taken).
## Returns the object, or {} when there's no room.
static func place_fountain(room: Dictionary, near: Vector2i, leads: String = "dark") -> Dictionary:
	var w := int(room.get("size", {}).get("w", 12))
	var d := int(room.get("size", {}).get("d", 10))
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for z in d:
		for x in w:
			if not RoomEditor.object_at(room, x, z).is_empty() or RoomEditor.stack_top(room, x, z) > 0.0:
				continue
			if x == 0 or z == 0 or x == w - 1 or z == d - 1:
				continue   # not on the edge (it could sit across a join)
			var dist := absi(x - near.x) + absi(z - near.y)
			if dist > 0 and dist < best_d:
				best_d = dist
				best = Vector2i(x, z)
	if best.x < 0:
		return {}
	var o := RoomEditor.add_object(room, best.x, best.y, TYPE)
	if o.is_empty():
		return {}
	o.merge({"target": "", "leads": leads, "state": "new", "label": "Dream Gate"}, true)
	return o


## Links a Light World fountain to a Dream World place, both ways: the Dream World gets (or keeps) a
## fountain leading back. Both places must then be saved.
static func link(light: Dictionary, fountain: Dictionary, dark: Dictionary) -> bool:
	if is_dark(light) or not is_dark(dark) or str(fountain.get("type", "")) != TYPE:
		return false
	fountain["target"] = str(dark.id)
	fountain["leads"] = "dark"
	fountain["state"] = "open"
	var back: Dictionary = {}
	for f in fountains(dark):
		if str(f.get("leads", "")) == "light":
			back = f
	if back.is_empty():
		var sp: Array = dark.get("spawn", [6, 7])
		back = place_fountain(dark, Vector2i(int(sp[0]), int(sp[1])), "light")
	if back.is_empty():
		return false
	back["target"] = str(light.id)
	back["leads"] = "light"
	back["state"] = "open"
	back["label"] = "Back to %s" % str(light.get("name", "where you came from"))
	return true


## Seal / reopen. Nothing is deleted either way.
static func seal(fountain: Dictionary) -> void:
	fountain["state"] = "sealed"


static func reopen(fountain: Dictionary) -> void:
	if target(fountain) != "":
		fountain["state"] = "open"


## Dream World places by whether any open fountain still leads to them: {open: [ids], archive: [ids]}.
static func dark_worlds(rooms: Dictionary) -> Dictionary:
	var open := {}
	for id in rooms:
		for f in fountains(rooms[id]):
			if str(f.get("leads", "")) == "dark" and state(f) == "open" and rooms.has(target(f)):
				open[target(f)] = true
	var out := {"open": [], "archive": []}
	for id in rooms:
		if is_dark(rooms[id]):
			(out.open if open.has(id) else out.archive).append(id)
	return out


## The Light World fountain that leads to a Dream World place (place id + object), or {}.
static func fountain_to(rooms: Dictionary, dark_id: String) -> Dictionary:
	for id in rooms:
		if is_dark(rooms[id]):
			continue
		for f in fountains(rooms[id]):
			if target(f) == dark_id and str(f.get("leads", "")) == "dark":
				return {"place": id, "fountain": f}
	return {}


# --- Upgrading (world v6) -------------------------------------------------------------------------

## Every place gets a side. Places set to Dream World Me become Dream World places. Returns true when changed.
static func upgrade_room(room: Dictionary) -> bool:
	if room.has("side"):
		return false
	room["side"] = "dark" if str(room.get("player_form", "")) == "dark" else "light"
	if room.side == "dark":
		room["look"] = str(room.get("look", "dark"))
	return true


## After upgrade_room on every place: each Dream World place gets a fountain in the Light World,
## by the door that led to it (else in the start place), linked both ways. Returns the places
## changed ({id: data}) for the caller to save.
static func link_old_dark_places(rooms: Dictionary, start: String) -> Dictionary:
	var changed := {}
	for did in rooms:
		var dark: Dictionary = rooms[did]
		if not is_dark(dark) or not fountain_to(rooms, did).is_empty():
			continue
		var host := ""
		var near := Vector2i(-1, -1)
		for lid in rooms:
			if is_dark(rooms[lid]):
				continue
			for o in rooms[lid].get("objects", []):
				if str(o.get("type", "")) == "door" and str(o.get("door_target", "")) == did:
					host = lid
					var p: Array = o.get("pos", [0, 0, 0])
					near = Vector2i(int(p[0]), int(p[2]))
					break
			if host != "":
				break
		if host == "":
			host = start if rooms.has(start) and not is_dark(rooms[start]) else ""
			if host == "":
				for lid in rooms:
					if not is_dark(rooms[lid]):
						host = lid
						break
			if host == "":
				continue
			var sp: Array = rooms[host].get("spawn", [6, 7])
			near = Vector2i(int(sp[0]), int(sp[1]))
		var light: Dictionary = rooms[host]
		var f := place_fountain(light, near, "dark")
		if f.is_empty() or not link(light, f, dark):
			continue
		changed[host] = light
		changed[did] = dark
	return changed
