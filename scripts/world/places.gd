extends RefCounted
## Places: what the game used to call rooms (the files still live in rooms/). A place is
## indoor, outdoor or abstract; walls are optional, side by side; its background is a sky
## (or a colour or picture) with up to three silhouette layers that move with the camera
## (parallax: hills, trees, a city, clouds...), and outdoors the ground goes on to the horizon.
## Places join at their edges: walk off the east edge of one and you're at the west edge of the
## next, and the ground and background carry on across the join so they feel like one land.
## Doors still work for everything else. The World Map lays places out by their edges.
##
## Room data gains (world v5, places.gd: upgrade_room):
##   "kind": "indoor" | "outdoor" | "abstract"
##   "walls": {"north": bool, "east": bool, "south": bool, "west": bool}
##   "background": {"sky": "room" | "auto" | "day" | "dusk" | "night" | "dream" | "void",
##                  "layers": [{"kind", "color", "distance" (1-3), "seed"}], "ground": bool, "ground_color": ""}
##   "edges": {"east": "<place id>", ...}

const Defaults := preload("res://scripts/core/defaults.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const KINDS: PackedStringArray = ["indoor", "outdoor", "abstract"]
const KIND_LABELS := {"indoor": "Indoors", "outdoor": "Outdoors", "abstract": "Somewhere strange"}
const SIDES: PackedStringArray = ["north", "east", "south", "west"]
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
const STEP := {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "east": Vector2i(1, 0), "west": Vector2i(-1, 0)}
const SKIES: PackedStringArray = ["room", "auto", "day", "dusk", "night", "dream", "void"]
const SKY_LABELS := {"room": "Plain colour or picture", "auto": "Follows the time of day", "day": "Day", "dusk": "Dusk", "night": "Night", "dream": "Dream", "void": "The void"}
const SILHOUETTES: PackedStringArray = ["hills", "trees", "mountains", "city", "clouds", "dunes", "shapes", "stars"]
const MAX_LAYERS := 3
## Indoors still sits in the world: ground under it and a sky above (following the time of day), with
## far hills, instead of a box in a void.
const INDOOR_SCENERY := {"sky": "auto", "ground": true, "ground_color": "#6a9a5b", "layers": [
	{"kind": "hills", "color": "#4f7a5c", "distance": 3, "seed": 1}]}
## The look rooms had before places (the v5 upgrade kept it): what open_up() replaces.
const OLD_ROOM_LOOK := {"sky": "room", "ground": false, "ground_color": "", "layers": []}
## Words in a place's name or id that say it's outside (open_up).
const OUTDOOR_WORDS: PackedStringArray = ["garden", "yard", "park", "meadow", "field", "forest", "woods", "beach",
	"lake", "river", "street", "road", "plaza", "square", "playground", "orchard", "farm", "camp", "roof", "terrace",
	"patio", "balcony", "outside", "outdoor", "hill", "mountain", "island", "shore", "pond", "village", "town"]


static func kind(room: Dictionary) -> String:
	var k := str(room.get("kind", "indoor"))
	return k if k in KINDS else "indoor"


static func default_walls(k: String) -> Dictionary:
	var on := k == "indoor"
	return {"north": on, "east": on, "south": on, "west": on}


static func walls(room: Dictionary) -> Dictionary:
	var out := default_walls(kind(room))
	var w: Variant = room.get("walls")
	if w is Dictionary:
		for s in SIDES:
			if (w as Dictionary).has(s):
				out[s] = bool(w[s])
	return out


static func has_wall(room: Dictionary, side: String) -> bool:
	return bool(walls(room).get(side, false))


static func default_background(k: String) -> Dictionary:
	match k:
		"outdoor":
			return {"sky": "auto", "ground": true, "ground_color": "", "layers": [
				{"kind": "hills", "color": "#4f7a5c", "distance": 3, "seed": 1},
				{"kind": "trees", "color": "#2f5240", "distance": 2, "seed": 2}]}
		"abstract":
			return {"sky": "dream", "ground": false, "ground_color": "", "layers": [
				{"kind": "shapes", "color": "#7a5cc8", "distance": 3, "seed": 3},
				{"kind": "clouds", "color": "#c9b6ff", "distance": 2, "seed": 4}]}
	return INDOOR_SCENERY.duplicate(true)


static func background(room: Dictionary) -> Dictionary:
	var out := default_background(kind(room))
	var b: Variant = room.get("background")
	if b is Dictionary:
		for k in ["sky", "ground", "ground_color", "layers"]:
			if (b as Dictionary).has(k):
				out[k] = b[k]
	if not str(out.sky) in SKIES:
		out.sky = "room"
	var layers: Array = []
	for l in (out.layers as Array if out.layers is Array else []):
		if l is Dictionary and str(l.get("kind", "")) in SILHOUETTES and layers.size() < MAX_LAYERS:
			layers.append({"kind": str(l.kind), "color": str(l.get("color", "#4f7a5c")), "distance": clampi(int(l.get("distance", 2)), 1, 3), "seed": int(l.get("seed", 1))})
	out.layers = layers
	return out


static func edges(room: Dictionary) -> Dictionary:
	var out := {}
	var e: Variant = room.get("edges")
	if e is Dictionary:
		for s in SIDES:
			if str((e as Dictionary).get(s, "")) != "":
				out[s] = str(e[s])
	return out


static func edge(room: Dictionary, side: String) -> String:
	return str(edges(room).get(side, ""))


## Joins two places: `a`'s `side` leads to `b`, and `b`'s opposite side back to `a`.
## A joined side has no wall (you walk through it). Both must then be saved.
static func link(a: Dictionary, side: String, b: Dictionary) -> bool:
	if not side in SIDES or str(a.get("id", "")) == "" or str(a.get("id", "")) == str(b.get("id", "")):
		return false
	var ea := edges(a)
	var eb := edges(b)
	ea[side] = str(b.id)
	eb[OPPOSITE[side]] = str(a.id)
	a["edges"] = ea
	b["edges"] = eb
	var wa := walls(a)
	wa[side] = false
	a["walls"] = wa
	var wb := walls(b)
	wb[OPPOSITE[side]] = false
	b["walls"] = wb
	return true


## Undoes link() on both sides (walls stay open; put them back in the Place tab if wanted).
static func unlink(a: Dictionary, side: String, b: Dictionary) -> void:
	var ea := edges(a)
	if str(ea.get(side, "")) == str(b.get("id", "")):
		ea.erase(side)
	a["edges"] = ea
	var eb := edges(b)
	if str(eb.get(OPPOSITE[side], "")) == str(a.get("id", "")):
		eb.erase(OPPOSITE[side])
	b["edges"] = eb


## A new place of a kind, optionally matching another one's size and look (so a join lines up).
static func make_place(id: String, place_name: String, k: String, like: Dictionary = {}) -> Dictionary:
	var room := Defaults.room(id, place_name)
	room["kind"] = k if k in KINDS else "indoor"
	room["walls"] = default_walls(room.kind)
	room["background"] = default_background(room.kind)
	room["edges"] = {}
	match room.kind:
		"outdoor":
			room["floor"] = {"color": "#6a9a5b", "texture": ""}
			room["sky"] = {"color": "#8fc4e8", "texture": ""}
			room["ambiance"] = {"music": "", "lighting": "cozy", "weather": "auto"}
		"abstract":
			room["floor"] = {"color": "#3a2d66", "texture": ""}
			room["sky"] = {"color": "#120e24", "texture": ""}
	if not like.is_empty():
		room["size"] = (like.get("size", room.size) as Dictionary).duplicate(true)
		for k2 in ["floor", "sky", "ambiance"]:
			if like.has(k2):
				room[k2] = (like[k2] as Dictionary).duplicate(true)
		if like.has("background") or like.has("kind"):
			room["background"] = background(like).duplicate(true)
	var sz: Dictionary = room.size
	room["spawn"] = [int(sz.get("w", 12)) / 2, int(sz.get("d", 10)) / 2]
	return room


static func unique_id(base: String, taken: PackedStringArray) -> String:
	var clean := base.to_lower().strip_edges().replace(" ", "_")
	var out := ""
	for ch in clean:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
	if out == "":
		out = "place"
	var id := out
	var n := 2
	while id in taken:
		id = "%s_%d" % [out, n]
		n += 1
	return id


## "Add a place to the east": a new place just like `room`, joined at `side`. Returns it (unsaved).
static func add_beside(room: Dictionary, side: String, taken: PackedStringArray, place_name: String = "") -> Dictionary:
	if not side in SIDES or edge(room, side) != "":
		return {}
	var nice := place_name if place_name != "" else "%s, %s" % [str(room.get("name", "Place")), {"north": "north", "east": "east", "south": "south", "west": "west"}[side]]
	var fresh := make_place(unique_id(str(room.get("id", "place")) + "_" + side, taken), nice, kind(room), room)
	link(room, side, fresh)
	# Arrive at the join, not in the middle.
	var w := int(fresh.size.get("w", 12))
	var d := int(fresh.size.get("d", 10))
	var back: String = OPPOSITE[side]
	fresh["spawn"] = [{"west": 1, "east": w - 2}.get(back, w / 2), {"north": 1, "south": d - 2}.get(back, d / 2)]
	return fresh


# --- Templates ----------------------------------------------------------------------------------

## Starting points for a new place: kind, floor, sky colour and background. (Everything can be
## changed afterwards in Build mode's Place tab.)
const TEMPLATES := {
	"cozy_room": {"name": "Cozy room", "kind": "indoor", "floor": "#8a6a4f", "wall": "#4a3a6a", "sky": "#120e24", "background": {"sky": "auto", "ground": true, "layers": [
		{"kind": "hills", "color": "#4f7a5c", "distance": 3, "seed": 1}]}},
	"meadow": {"name": "Meadow", "kind": "outdoor", "floor": "#6a9a5b", "sky": "#8fc4e8", "background": {"sky": "auto", "ground": true, "layers": [
		{"kind": "hills", "color": "#4f7a5c", "distance": 3, "seed": 1}, {"kind": "trees", "color": "#2f5240", "distance": 2, "seed": 2}]}},
	"beach": {"name": "Beach", "kind": "outdoor", "floor": "#e2c98f", "sky": "#9fd6f0", "background": {"sky": "day", "ground": true, "ground_color": "#d8bd80", "layers": [
		{"kind": "dunes", "color": "#c9a86a", "distance": 2, "seed": 5}, {"kind": "clouds", "color": "#ffffff", "distance": 3, "seed": 6}]}},
	"forest": {"name": "Forest clearing", "kind": "outdoor", "floor": "#4f7a46", "sky": "#7fb0c8", "background": {"sky": "auto", "ground": true, "layers": [
		{"kind": "trees", "color": "#2a4a34", "distance": 1, "seed": 7}, {"kind": "trees", "color": "#3d6249", "distance": 2, "seed": 8}, {"kind": "mountains", "color": "#6f8aa0", "distance": 3, "seed": 9}]}},
	"city": {"name": "City street", "kind": "outdoor", "floor": "#6b6b78", "sky": "#2b2f5c", "background": {"sky": "dusk", "ground": true, "ground_color": "#55556a", "layers": [
		{"kind": "city", "color": "#3a3456", "distance": 1, "seed": 10}, {"kind": "city", "color": "#5a4f7a", "distance": 2, "seed": 11}]}},
	"cave": {"name": "Cave", "kind": "indoor", "floor": "#4a4458", "wall": "#2a2638", "sky": "#0b0a12", "background": {"sky": "room", "layers": []}},
	"cloud_tops": {"name": "Cloud tops", "kind": "abstract", "floor": "#e8e0ff", "sky": "#2a1a5e", "background": {"sky": "dream", "ground": false, "layers": [
		{"kind": "clouds", "color": "#ffffff", "distance": 2, "seed": 12}, {"kind": "clouds", "color": "#d6c8ff", "distance": 3, "seed": 13}]}},
	"starfield": {"name": "Starfield", "kind": "abstract", "floor": "#2a2250", "sky": "#05030c", "background": {"sky": "void", "ground": false, "layers": [
		{"kind": "stars", "color": "#ffffff", "distance": 3, "seed": 14}, {"kind": "shapes", "color": "#7a5cc8", "distance": 2, "seed": 15}]}},
}
const TEMPLATE_ORDER: PackedStringArray = ["cozy_room", "meadow", "beach", "forest", "city", "cave", "cloud_tops", "starfield"]


## A new place from a template (its look; the layout is empty).
static func from_template(template_id: String, id: String, place_name: String, w: int = 12, d: int = 10) -> Dictionary:
	var t: Dictionary = TEMPLATES.get(template_id, TEMPLATES.cozy_room)
	var room := make_place(id, place_name, str(t.kind))
	room["size"] = {"w": w, "d": d, "h": 3}
	room["spawn"] = [w / 2, d / 2]
	room["floor"] = {"color": str(t.floor), "texture": ""}
	if t.has("wall"):
		room["wall"] = {"color": str(t.wall), "texture": ""}
	room["sky"] = {"color": str(t.sky), "texture": ""}
	var bg := default_background(str(t.kind))
	for k in t.background:
		bg[k] = (t.background[k] as Array).duplicate(true) if t.background[k] is Array else t.background[k]
	room["background"] = bg
	room["template"] = template_id
	return room


# --- Crossing an edge ---------------------------------------------------------------------------

## The side of `room` a cell is on (its outermost row or column), or "".
static func side_of(room: Dictionary, cell: Vector2i) -> String:
	var w := int(room.get("size", {}).get("w", 12))
	var d := int(room.get("size", {}).get("d", 10))
	if cell.x <= 0:
		return "west"
	if cell.x >= w - 1:
		return "east"
	if cell.y <= 0:
		return "north"
	if cell.y >= d - 1:
		return "south"
	return ""


## Where you come out in `to` after leaving `from` by `side` at `cell`: on `to`'s opposite edge,
## at the same place along it (scaled when the two differ in size).
static func arrival(from_room: Dictionary, side: String, cell: Vector2i, to_room: Dictionary) -> Vector2i:
	var fw := int(from_room.get("size", {}).get("w", 12))
	var fd := int(from_room.get("size", {}).get("d", 10))
	var tw := int(to_room.get("size", {}).get("w", 12))
	var td := int(to_room.get("size", {}).get("d", 10))
	var along_x := roundi(float(cell.x) * float(tw - 1) / maxf(1.0, fw - 1))
	var along_z := roundi(float(cell.y) * float(td - 1) / maxf(1.0, fd - 1))
	match side:
		"east":
			return Vector2i(0, clampi(along_z, 0, td - 1))
		"west":
			return Vector2i(tw - 1, clampi(along_z, 0, td - 1))
		"north":
			return Vector2i(clampi(along_x, 0, tw - 1), td - 1)
		"south":
			return Vector2i(clampi(along_x, 0, tw - 1), 0)
	return Vector2i(tw / 2, td / 2)


# --- The World Map ------------------------------------------------------------------------------

## Grid positions for the map: places joined by edges sit side by side (east = +x, south = +y),
## starting from `start`; everything else (joined only by doors, or not at all) goes in free
## spots to the right. {id: Vector2i}.
static func map_layout(rooms: Dictionary, start: String) -> Dictionary:
	var pos := {}
	var taken := {}
	var order: Array = []
	if rooms.has(start):
		order.append(start)
	for id in rooms:
		if not id in order:
			order.append(id)
	var next_col := 0
	for root in order:
		if pos.has(root):
			continue
		var origin := Vector2i(next_col, 0)
		while taken.has(origin):
			origin.x += 1
		pos[root] = origin
		taken[origin] = root
		var queue: Array = [root]
		while not queue.is_empty():
			var id: String = queue.pop_front()
			var e := edges(rooms[id])
			for s in SIDES:
				var other := str(e.get(s, ""))
				if other == "" or not rooms.has(other) or pos.has(other):
					continue
				var want: Vector2i = pos[id] + STEP[s]
				while taken.has(want):
					want += STEP[s]   # a loop that doesn't close neatly: keep going that way
				pos[other] = want
				taken[want] = other
				queue.append(other)
		var max_x := 0
		for id2 in pos:
			max_x = maxi(max_x, (pos[id2] as Vector2i).x)
		next_col = max_x + 2
	# Shift so the smallest x and y are 0.
	var lo := Vector2i(1 << 20, 1 << 20)
	for id3 in pos:
		lo.x = mini(lo.x, (pos[id3] as Vector2i).x)
		lo.y = mini(lo.y, (pos[id3] as Vector2i).y)
	for id4 in pos:
		pos[id4] = (pos[id4] as Vector2i) - lo
	return pos


# --- Upgrading old rooms (world v5) -----------------------------------------------------------------

## Does this place's name (or id) say it's outside? ("Garden", "Tile Playground", "Rooftop"...)
static func looks_outdoor(room: Dictionary) -> bool:
	var text := (str(room.get("name", "")) + " " + str(room.get("id", ""))).to_lower().replace("_", " ")
	for w in OUTDOOR_WORDS:
		if text.contains(w):
			return true
	return false


## A place that still looks like a room from before places (indoors, an untouched backdrop) opens up:
## an outdoorsy name makes it an outdoor place (no walls, the sky, the ground, hills and trees); any
## other keeps its walls but sits in the world (ground and sky around it). Places whose backdrop was
## changed in Build mode, Dream World places and caves stay as they are. Returns true when it changed.
static func open_up(room: Dictionary) -> bool:
	if kind(room) != "indoor" or str(room.get("side", "light")) != "light" or str(room.get("template", "")) == "cave":
		return false
	var b: Variant = room.get("background")
	var now := background(room)
	var untouched := not b is Dictionary or _same_look(now, OLD_ROOM_LOOK) or _same_look(now, INDOOR_SCENERY)
	if not untouched:
		return false
	if looks_outdoor(room):
		room["kind"] = "outdoor"
		room["walls"] = default_walls("outdoor")
		room["background"] = default_background("outdoor")
		return true
	if _same_look(now, INDOOR_SCENERY) and b is Dictionary:
		return false   # already sits in the world
	room["background"] = default_background("indoor")
	return true


static func _same_look(a: Dictionary, b: Dictionary) -> bool:
	return (str(a.get("sky", "")) == str(b.get("sky", "")) and bool(a.get("ground", false)) == bool(b.get("ground", false))
		and str(a.get("ground_color", "")) == str(b.get("ground_color", ""))
		and JSON.stringify(a.get("layers", [])) == JSON.stringify(b.get("layers", [])))


## open_up() for every place, then the starter Garden and Tile Playground are joined edge to edge
## (when both are outdoors and those sides are free), so new and upgraded worlds feel like one
## world. `rooms` is {id: room}; returns the ids that changed (the caller saves them).
static func open_up_all(rooms: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	for id in rooms:
		if open_up(rooms[id]):
			changed.append(str(id))
	var g: Variant = rooms.get("garden")
	var p: Variant = rooms.get("tile_playground")
	if g is Dictionary and p is Dictionary and kind(g) == "outdoor" and kind(p) == "outdoor" and edge(g, "east") == "" and edge(p, "west") == "":
		link(g, "east", p)
		for id in ["garden", "tile_playground"]:
			if not id in changed:
				changed.append(id)
	return changed


## Gives an old room the place fields without changing how it looks: indoor, all four walls, its own
## sky colour or picture, no edges. Returns true when it changed.
static func upgrade_room(room: Dictionary) -> bool:
	var changed := false
	if not room.has("kind"):
		room["kind"] = "indoor"
		changed = true
	if not room.get("walls") is Dictionary:
		room["walls"] = default_walls(kind(room))
		changed = true
	if not room.get("background") is Dictionary:
		room["background"] = default_background(kind(room))
		changed = true
	if not room.get("edges") is Dictionary:
		room["edges"] = {}
		changed = true
	return changed
