extends RefCounted
## "Tell Polox about home": reads what you write in your own words and proposes changes to the house,
## offline (no helper needed): wall colours ("we painted my room green"), floors ("the kitchen has
## tiles"), things in a room ("the hallway has a blue runner and our family photos"), things that went
## ("we got rid of the piano"), what a room used to be ("my room used to be the playroom"), and anything
## else about a room as a note ("the back door sticks"). Nothing changes until you choose Keep.
## Whatever it can't place ("Which room is the rug in?") comes back as a question for you.
##
## read() -> {"changes": [edit, ...], "unsure": [{"text", "kind", "value", "model"?, "options": [room ids]}]}
## Each change is a home_edit.gd edit: wall, floor, add, remove, used_to_be, note (with "level", "room").
## Tags: [AI_HELPER]

const COLORS := {"white": "#f2efe8", "off white": "#efe9dc", "cream": "#efe6d8", "beige": "#e3d5bc", "grey": "#c9c9c4", "gray": "#c9c9c4",
	"light blue": "#bcd6ea", "sky blue": "#a9cfee", "navy": "#34456e", "blue": "#a9c4dc", "teal": "#6aaea6", "mint": "#bfe3cf", "sage": "#b8c9a8",
	"green": "#b5cfa8", "dark green": "#4f7a54", "yellow": "#f0dfa0", "orange": "#f0b57a", "peach": "#f3c9a8", "pink": "#e8bfc4", "red": "#c8645c",
	"purple": "#a68ac8", "lavender": "#c8b8e0", "lilac": "#cdb8e0", "brown": "#8b6a4a", "black": "#3a3a40", "dark": "#4a4a58"}
const FLOOR_WORDS := {"carpet": "carpet", "carpeted": "carpet", "rug floor": "carpet", "tile": "tile", "tiles": "tile", "tiled": "tile",
	"wood": "wood", "wooden": "wood", "hardwood": "wood", "laminate": "wood", "parquet": "wood", "floorboards": "wood",
	"vinyl": "vinyl", "linoleum": "vinyl", "lino": "vinyl", "concrete": "concrete", "stone": "stone"}
## Words for things -> furniture models.
const THINGS := {"runner": "runner", "rug": "rug", "piano": "piano", "sofa": "sofa", "couch": "sofa", "settee": "sofa",
	"armchair": "armchair", "recliner": "armchair", "tv": "tv", "television": "tv", "telly": "tv", "bookshelf": "bookshelf",
	"bookshelves": "bookshelf", "bookcase": "bookshelf", "books": "bookshelf", "plant": "plant", "plants": "plant",
	"lamp": "lamp", "desk": "desk", "computer": "computer", "bed": "bed", "bunk": "bed", "wardrobe": "wardrobe", "closet": "wardrobe",
	"dresser": "dresser", "drawers": "dresser", "dining table": "dining_table", "table": "coffee_table", "chair": "chair",
	"bench": "bench", "photos": "picture", "photo": "picture", "pictures": "picture", "picture": "picture", "frames": "picture",
	"paintings": "picture", "painting": "picture", "posters": "picture", "poster": "picture", "mirror": "mirror", "washing machine": "washer",
	"washer": "washer", "fridge": "fridge", "bathtub": "bathtub", "bath": "bathtub", "shower": "shower", "flowers": "flowers", "nightstand": "nightstand"}
const NUMBERS := {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "a few": 3, "some": 2, "several": 3, "lots of": 4}
## Room words -> room kinds (or "mine").
const ROOM_WORDS := [["my bedroom", "mine"], ["my room", "mine"], ["kitchen", "kitchen"], ["living room", "living"], ["lounge", "living"],
	["front room", "living"], ["sitting room", "living"], ["dining room", "dining"], ["dining", "dining"], ["bathroom", "bathroom"],
	["toilet", "bathroom"], ["hallway", "hall"], ["hall", "hall"], ["landing", "hall"], ["corridor", "hall"], ["laundry", "laundry"],
	["utility", "laundry"], ["office", "office"], ["study", "office"], ["garage", "garage"], ["spare room", "bedroom"],
	["guest room", "bedroom"], ["bedroom", "bedroom"], ["family room", "family"], ["basement", "storage"]]
const REMOVE_WORDS := ["got rid of", "no longer", "removed", "don't have", "dont have", "gave away", "sold the", "threw out", "is gone", "are gone", "took out"]
const PAINT_WORDS := ["paint", "painted", "walls", "wall is", "wall's", "colour", "color", "repainted", "wallpaper"]


## {"changes", "unsure"} for what you wrote, against the current plan.
static func read(text: String, plan: Dictionary) -> Dictionary:
	var changes: Array = []
	var unsure: Array = []
	var last_room := {}
	for clause in _clauses(text):
		var low := " " + clause.to_lower().strip_edges() + " "
		if low.strip_edges() == "":
			continue
		var room := find_room(low, plan)
		if room.is_empty() and not last_room.is_empty() and (low.begins_with(" and ") or low.begins_with(" it ") or low.contains(" it ") or low.contains(" its ")):
			room = last_room   # "...the hallway has a blue runner and our family photos"
		if not room.is_empty():
			last_room = room
		# What a room used to be.
		var ub := low.find("used to be")
		if ub >= 0:
			var was := clause.strip_edges().substr(ub + 9).strip_edges().trim_suffix(".")   # as you wrote it ("the playroom")
			if room.is_empty():
				unsure.append({"text": "Which room used to be %s?" % was, "kind": "used_to_be", "value": was, "options": room_ids(plan)})
			else:
				changes.append(_edit("used_to_be", room, {"was": was, "text": clause.strip_edges()}))
			continue
		var removing := REMOVE_WORDS.any(func(w): return low.contains(" " + w + " ") or low.contains(w))
		var color := _color_in(low)
		var floor_kind := _floor_in(low)
		var things := _things_in(low)
		var painted := PAINT_WORDS.any(func(w): return low.contains(w))
		var did := false
		if color != "" and (painted or (things.is_empty() and floor_kind == "")):
			if room.is_empty():
				unsure.append({"text": "Which room is %s?" % _color_name(color), "kind": "wall", "value": color, "options": room_ids(plan)})
			else:
				changes.append(_edit("wall", room, {"color": color}))
			did = true
		if floor_kind != "" and (low.contains("floor") or low.contains(" has ") or low.contains(" have ") or things.is_empty()):
			if room.is_empty():
				unsure.append({"text": "Which room has the %s floor?" % floor_kind, "kind": "floor", "value": floor_kind, "options": room_ids(plan)})
			else:
				changes.append(_edit("floor", room, {"floor": floor_kind}))
			did = true
		for t in things:
			if t.model == "runner" and not room.is_empty() and str(room.kind) != "hall":
				t.model = "rug"
			if room.is_empty():
				unsure.append({"text": "Which room is the %s in?" % str(t.word), "kind": "remove" if removing else "add", "value": t.color, "model": t.model, "count": t.count, "options": room_ids(plan)})
			elif removing:
				changes.append(_edit("remove", room, {"model": t.model}))
			else:
				changes.append(_edit("add", room, {"model": t.model, "color": t.color if t.model != "picture" or t.color != "" else "", "count": t.count}))
			did = true
		if not did and not room.is_empty():
			changes.append(_edit("note", room, {"text": clause.strip_edges().trim_suffix(".")}))
	return {"changes": changes, "unsure": unsure}


static func _edit(type: String, room: Dictionary, extra: Dictionary) -> Dictionary:
	var e := {"type": type, "level": int(room.level), "room": str(room.id), "room_name": str(room.name)}
	e.merge(extra, true)
	return e


static func _clauses(text: String) -> PackedStringArray:
	var t := text.replace("\n", ". ").replace(";", ". ").replace("!", ". ").replace("?", ". ")
	var out := PackedStringArray()
	for sentence in t.split(".", false):
		# "X but Y" and ", and then" start new thoughts; "and" alone stays (a list of things).
		for part in sentence.replace(" but ", "|").replace(", and then ", "|").replace(" also ", "|").split("|", false):
			if part.strip_edges() != "":
				out.append(part.strip_edges())
	return out


## The room a clause talks about: by its own name first (yours, if you renamed it), then by kind.
static func find_room(low: String, plan: Dictionary) -> Dictionary:
	var all: Array = []
	for f in plan.get("floors", []):
		for r in f.get("rooms", []):
			all.append({"id": str(r.id), "name": str(r.name), "kind": str(r.kind), "mine": bool(r.get("mine", false)), "level": int(f.level)})
	var best := {}
	var best_len := 0
	for r in all:
		var n := " " + str(r.name).to_lower() + " "
		if str(r.name).length() > best_len and low.contains(n.strip_edges()) and str(r.name).length() >= 3:
			best = r
			best_len = str(r.name).length()
	if not best.is_empty() and not (str(best.kind) == "bedroom" and not bool(best.mine) and low.contains("my room")):
		return best
	for w in ROOM_WORDS:
		if low.contains(str(w[0])):
			for r in all:
				if (str(w[1]) == "mine" and bool(r.mine)) or (str(w[1]) != "mine" and str(r.kind) == str(w[1]) and not (str(w[1]) == "bedroom" and bool(r.mine))):
					return r
	return {}


static func room_ids(plan: Dictionary) -> Array:
	var out: Array = []
	var count := {}
	for f in plan.get("floors", []):
		for r in f.get("rooms", []):
			count[str(r.name)] = int(count.get(str(r.name), 0)) + 1
	for f in plan.get("floors", []):
		for r in f.get("rooms", []):
			var nm := str(r.name)
			if int(count[nm]) > 1:
				nm = "%s (%s)" % [nm, str(f.get("name", "")).to_lower()]   # two hallways: say which floor
			out.append({"id": str(r.id), "name": nm, "level": int(f.level)})
	return out


static func _color_in(low: String) -> String:
	var best := ""
	var best_len := 0
	for c in COLORS:
		if low.contains(" " + str(c) + " ") or low.contains(" " + str(c) + ",") or low.contains(" " + str(c) + "-"):
			if str(c).length() > best_len:
				best = COLORS[c]
				best_len = str(c).length()
	return best


static func _color_name(hex: String) -> String:
	for c in COLORS:
		if COLORS[c] == hex:
			return str(c)
	return "that colour"


static func _floor_in(low: String) -> String:
	for w in FLOOR_WORDS:
		if low.contains(" " + str(w) + " ") or low.contains(" " + str(w) + "s "):
			if str(w) == "carpet" and low.contains("runner"):
				continue
			return str(FLOOR_WORDS[w])
	return ""


## Things mentioned, each with a colour right before it and a count ("a blue rug", "3 picture frames").
static func _things_in(low: String) -> Array:
	var out: Array = []
	var seen := {}
	var words := low.split(" ", false)
	var keys: Array = THINGS.keys()
	keys.sort_custom(func(a, b): return str(a).length() > str(b).length())
	for k in keys:
		var at := low.find(" " + str(k) + " ")
		if at < 0:
			at = low.find(" " + str(k) + ",")
		if at < 0:
			continue
		var model := str(THINGS[k])
		if seen.has(model):
			continue
		# Words just before it: colour and count.
		var before := low.substr(maxi(0, at - 24), mini(24, at)).strip_edges()
		var color := ""
		for c in COLORS:
			if before.ends_with(str(c)) or before.contains(str(c) + " "):
				color = COLORS[c]
		var count := 1
		var parts := before.split(" ", false)
		for p in parts:
			if p.is_valid_int():
				count = clampi(int(p), 1, 8)
			elif NUMBERS.has(p) and int(NUMBERS[p]) > 1:
				count = int(NUMBERS[p])
		if model == "picture" and count == 1 and (str(k).ends_with("s")):
			count = 3
		seen[model] = true
		out.append({"model": model, "word": str(k), "color": color, "count": count})
	return out


## A short line for the preview ("Add: a blue rug in Hallway").
static func describe(e: Dictionary) -> String:
	var where := str(e.get("room_name", "a room"))
	match str(e.get("type", "")):
		"wall":
			return "Change: %s's walls to %s" % [where, _color_name(str(e.get("color", "")))]
		"floor":
			return "Change: %s's floor to %s" % [where, str(e.get("floor", ""))]
		"add":
			var n := int(e.get("count", 1))
			var name := str(load("res://scripts/world/furniture.gd").name_of(str(e.get("model", "")))).to_lower()
			var col := _color_name(str(e.get("color", ""))) if str(e.get("color", "")) != "" else ""
			return "Add: %s%s%s in %s" % [("%d " % n) if n > 1 else "a ", (col + " ") if col != "" and col != "that colour" else "", name + ("s" if n > 1 else ""), where]
		"remove":
			return "Take away: the %s in %s" % [str(load("res://scripts/world/furniture.gd").name_of(str(e.get("model", "")))).to_lower(), where]
		"used_to_be":
			return "Remember: %s used to be %s" % [where, str(e.get("was", ""))]
		"note":
			return "Note in %s: \"%s\"" % [where, str(e.get("text", ""))]
	return "Change something"


# --- With a helper (only when you tap "Ask Claude to read it") ----------------------------------------

const WORDS_SCHEMA := {
	"type": "object",
	"properties": {
		"changes": {"type": "array", "maxItems": 64, "items": {"type": "object", "properties": {
			"type": {"type": "string", "enum": ["wall", "floor", "add", "remove", "used_to_be", "note", "rename"]}, "room": {"type": "string", "minLength": 1, "maxLength": 120}, "color": {"type": "string", "maxLength": 40}, "floor": {"type": "string", "enum": ["wood", "carpet", "tile", "vinyl", "concrete", "stone"]},
			"model": {"type": "string", "maxLength": 80}, "count": {"type": "integer", "minimum": 1, "maximum": 8}, "was": {"type": "string", "maxLength": 80}, "text": {"type": "string", "maxLength": 200}},
			"required": ["type", "room"]}},
		"questions": {"type": "array", "maxItems": 32, "items": {"type": "string", "maxLength": 160}},
	},
	"required": ["changes"],
}


static func validate_helper(raw: Dictionary) -> String:
	var error := preload("res://scripts/home/helper_json.gd").validate(raw, WORDS_SCHEMA)
	if error != "":
		return error
	for i in raw.changes.size():
		var change: Dictionary = raw.changes[i]
		var required := str({"wall": "color", "floor": "floor", "add": "model", "remove": "model", "used_to_be": "was", "note": "text", "rename": "text"}.get(change.type, ""))
		if not change.has(required) or str(change[required]).strip_edges() == "":
			return "$.changes[%d].%s: required field is missing or empty." % [i, required]
		if str(change.type) in ["add", "remove"] and not load("res://scripts/world/furniture.gd").exists(str(change.model)):
			return "$.changes[%d].model: unsupported furniture." % i
		if str(change.type) == "wall" and _color_in(" " + str(change.color).to_lower() + " ") == "" and not (str(change.color).begins_with("#") and Color.html_is_valid(str(change.color))):
			return "$.changes[%d].color: use a supported color name or #hex." % i
		if str(change.type) == "rename" and str(change.text).length() > 40:
			return "$.changes[%d].text: room names must be at most 40 characters." % i
	return ""


## What a helper is asked: the player's words (and photo), the rooms that exist, the pieces Polox can
## draw. Nothing else about the home (no address).
static func words_prompt(text: String, plan: Dictionary, has_photo: bool) -> String:
	var rooms: PackedStringArray = []
	for f in plan.get("floors", []):
		for r in f.get("rooms", []):
			rooms.append("%s (%s)" % [str(r.name), str(f.name)])
	var models: PackedStringArray = []
	for m in load("res://scripts/world/furniture.gd").CATALOG:
		models.append(str(m))
	var lines: PackedStringArray = []
	lines.append("A player is telling a cozy video game about their own home, so the game's copy of it can match. Turn what they wrote" + (" and the photo they added" if has_photo else "") + " into changes.")
	lines.append("Rooms in their home: " + ", ".join(rooms) + ".")
	lines.append("Change types: wall (room + color), floor (room + floor: wood, carpet, tile, vinyl, concrete, stone), add (room + model + count + optional color), remove (room + model), used_to_be (room + was), note (room + text, for anything else), rename (room + text as the new name).")
	lines.append("Models you may use: " + ", ".join(models) + ". Colors as plain words (green, light blue) or #hex.")
	lines.append("Only what they actually said or what is clearly in the photo. Never names of people. If you can't tell which room, put a short question in \"questions\".")
	lines.append("What they wrote: " + text.strip_edges())
	lines.append("Answer with one JSON object in exactly this shape and nothing else: " + JSON.stringify(WORDS_SCHEMA))
	return "\n".join(lines)


## A helper's answer, made into the same proposal read() makes (rooms matched to yours, only known pieces).
static func clean_helper(raw: Dictionary, plan: Dictionary) -> Dictionary:
	var r: Dictionary = load("res://scripts/home/home_model.gd").scrub(raw)
	var changes: Array = []
	var unsure: Array = []
	var Furniture: Script = load("res://scripts/world/furniture.gd")
	for c in (r.get("changes", []) if r.get("changes") is Array else []):
		if not c is Dictionary:
			continue
		var type := str(c.get("type", ""))
		if not type in ["wall", "floor", "add", "remove", "used_to_be", "note", "rename"]:
			continue
		var room := find_room(" " + str(c.get("room", "")).to_lower() + " ", plan)
		if room.is_empty():
			unsure.append({"text": "Which room did you mean (%s)?" % str(c.get("room", "")), "kind": type, "value": str(c.get("color", c.get("floor", c.get("was", "")))), "model": str(c.get("model", "")), "count": int(c.get("count", 1)), "options": room_ids(plan)})
			continue
		var e := _edit(type, room, {})
		match type:
			"wall":
				var col := _color_in(" " + str(c.get("color", "")).to_lower() + " ")
				if col == "" and str(c.get("color", "")).begins_with("#") and Color.html_is_valid(str(c.color)):
					col = str(c.color)
				if col == "":
					continue
				e["color"] = col
			"floor":
				var fk := str(c.get("floor", "")).to_lower()
				if not fk in ["wood", "carpet", "tile", "vinyl", "concrete", "stone"]:
					continue
				e["floor"] = fk
			"add", "remove":
				var m := str(c.get("model", ""))
				if not Furniture.exists(m):
					continue
				e["model"] = m
				e["count"] = clampi(int(c.get("count", 1)), 1, 8)
				var col2 := _color_in(" " + str(c.get("color", "")).to_lower() + " ")
				e["color"] = col2
			"used_to_be":
				e["was"] = str(c.get("was", "")).left(80)
			"note":
				e["text"] = str(c.get("text", "")).left(200)
			"rename":
				e["type"] = "rename"
				e["name"] = str(c.get("text", "")).left(40)
		changes.append(e)
	for q in (r.get("questions", []) if r.get("questions") is Array else []):
		unsure.append({"text": str(q).left(160), "kind": "free", "value": "", "options": []})
	return {"changes": changes, "unsure": unsure}
