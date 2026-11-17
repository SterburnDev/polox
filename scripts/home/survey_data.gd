extends RefCounted
## The Survey's script: what the voice says and asks, in order. Polox's own words (a cold, curious
## voice in the dark, kind underneath). Every question can be skipped.
##
## Step: {"id", "kind": "say" | "text" | "choice" | "counts" | "color" | "picture" | "helper" | "consent",
##        "lines": [...], "key": "answers key (a.b for nested)", "options": [[value, label], ...],
##        "when": {"key", "is" | "not" | "gt": value}, "hint": ""}

const WALL_SWATCHES := [["#f2efe8", "WHITE"], ["#efe6d8", "CREAM"], ["#c9c9c4", "GREY"], ["#a9c4dc", "BLUE"], ["#b5cfa8", "GREEN"],
	["#e8bfc4", "PINK"], ["#f0dfa0", "YELLOW"], ["#c8b8e0", "LAVENDER"], ["#4a4a58", "DARK"]]
const FLOORS := [["wood", "WOOD"], ["carpet", "CARPET"], ["tile", "TILE"], ["vinyl", "VINYL"]]

const STEPS := [
	{"id": "hello", "kind": "say", "lines": ["...", "HELLO.", "SOMETHING HERE HAS BEEN LISTENING FOR YOU.", "THERE IS A HOUSE THAT KNOWS YOUR FOOTSTEPS.", "HELP IT REMEMBER ITSELF.", "ANSWER WHAT YOU LIKE. SKIP WHAT YOU DON'T."]},
	{"id": "address", "kind": "text", "key": "address", "lines": ["WHERE DOES YOUR LIGHT WORLD BEGIN?"],
		"hint": "A full address, a street, a city, or coordinates pasted from a map app. It stays on this computer unless you say otherwise.", "placeholder": "123 Example Street, Town"},
	{"id": "home_type", "kind": "choice", "key": "home_type", "lines": ["WHAT KIND OF HOME IS IT?"],
		"options": [["house", "A HOUSE"], ["apartment", "AN APARTMENT"], ["townhouse", "A TOWNHOUSE"], ["other", "SOMETHING ELSE"]]},
	{"id": "floors", "kind": "choice", "key": "floors", "lines": ["HOW MANY FLOORS?"],
		"options": [[1, "ONE"], [2, "TWO"], [3, "THREE"]]},
	{"id": "basement", "kind": "choice", "key": "basement", "lines": ["AND BENEATH IT. A BASEMENT?"],
		"options": [[true, "YES"], [false, "NO"]], "when": {"key": "home_type", "not": "apartment"}},
	{"id": "rooms", "kind": "counts", "key": "rooms", "lines": ["WHICH ROOMS ARE THERE?"],
		"options": [["bedroom", "BEDROOMS", 2], ["bathroom", "BATHROOMS", 1], ["kitchen", "KITCHEN", 1], ["living", "LIVING ROOM", 1],
			["dining", "DINING ROOM", 1], ["office", "OFFICE", 0], ["laundry", "LAUNDRY", 1], ["garage", "GARAGE", 0]]},
	{"id": "entry", "kind": "choice", "key": "entry_room", "lines": ["YOU OPEN THE FRONT DOOR.", "WHAT IS THERE?"],
		"options": [["hall", "A HALLWAY"], ["living", "THE LIVING ROOM"], ["kitchen", "THE KITCHEN"], ["hall", "STAIRS"]]},
	{"id": "my_floor", "kind": "choice", "key": "my_room.floor", "lines": ["WHERE DO YOU SLEEP?"],
		"options": [[0, "DOWNSTAIRS"], [1, "UPSTAIRS"], [-1, "IN THE BASEMENT"]], "when": {"key": "floors", "gt": 1}},
	{"id": "my_where", "kind": "choice", "key": "my_room.where", "lines": ["STANDING IN THE STREET, LOOKING AT THE HOUSE.", "WHERE IS YOUR ROOM?"],
		"options": [["front", "AT THE FRONT"], ["back", "AT THE BACK"], ["left", "ON THE LEFT"], ["right", "ON THE RIGHT"]]},
	{"id": "my_wall", "kind": "color", "key": "my_room.wall", "lines": ["WHAT COLOUR ARE YOUR WALLS?"]},
	{"id": "my_floor_kind", "kind": "picture", "key": "my_room.floor_kind", "lines": ["WHAT IS UNDER YOUR FEET?"], "options": FLOORS},
	{"id": "my_bed", "kind": "choice", "key": "my_room.bed", "lines": ["YOUR BED."], "options": [["single", "SMALL"], ["double", "BIG"]]},
	{"id": "my_desk", "kind": "choice", "key": "my_room.desk", "lines": ["IS THERE A DESK?"], "options": [[true, "YES"], [false, "NO"]]},
	{"id": "my_view", "kind": "choice", "key": "my_room.view", "lines": ["YOU LOOK OUT OF YOUR WINDOW.", "WHAT DO YOU SEE?"],
		"options": [["street", "THE STREET"], ["yard", "A YARD"], ["trees", "TREES"], ["house", "ANOTHER HOUSE"], ["sky", "ONLY SKY"]]},
	{"id": "kitchen_floor", "kind": "picture", "key": "floor_kinds.kitchen", "lines": ["WHICH LOOKS MOST LIKE YOUR KITCHEN FLOOR?"], "options": FLOORS},
	{"id": "living_floor", "kind": "picture", "key": "floor_kinds.living", "lines": ["AND THE LIVING ROOM?"], "options": FLOORS},
	{"id": "built", "kind": "text", "key": "year_built", "lines": ["HOW OLD IS IT?"], "hint": "The year it was built, if you know.", "placeholder": "1965", "number": true},
	{"id": "years", "kind": "choice", "key": "years_here", "lines": ["HOW LONG HAVE YOU LIVED THERE?"],
		"options": [[0, "LESS THAN A YEAR"], [3, "A FEW YEARS"], [10, "A LONG TIME"], [99, "ALL MY LIFE"]]},
	{"id": "renovations", "kind": "text", "key": "renovations", "lines": ["HAS IT CHANGED?", "A NEW ROOM. A WALL TAKEN DOWN. A NEW FLOOR."], "placeholder": "We added a deck in 2014", "long": true},
	{"id": "used_to_be", "kind": "text", "key": "used_to_be", "lines": ["DID ANY ROOM USED TO BE SOMETHING ELSE?"], "placeholder": "My room used to be the playroom", "long": true},
	{"id": "memory", "kind": "text", "key": "memory", "lines": ["IS THERE A MEMORY THE HOUSE SHOULD KEEP?"], "hint": "It becomes a page in your Memory Book. It stays on this computer.", "long": true},
	{"id": "radius", "kind": "choice", "key": "radius", "lines": ["HOW FAR SHOULD THE LIGHT WORLD GO?"],
		"options": [[80, "JUST MY STREET"], [250, "A FEW BLOCKS"], [500, "A LITTLE FURTHER"]]},
	{"id": "places", "kind": "text", "key": "places", "lines": ["ARE THERE PLACES NEARBY THAT MATTER?"], "hint": "A park, a school, the corner shop, a friend's street.", "placeholder": "the park, the corner shop", "long": true},
	{"id": "helper", "kind": "helper", "key": "helper", "lines": ["THE REST CAN BE LOOKED UP.", "WHO SHOULD LOOK?"]},
	{"id": "consent", "kind": "consent", "lines": ["BEFORE ANYTHING LEAVES THIS COMPUTER."]},
]


## Whether a step is asked, given the answers so far.
static func applies(step: Dictionary, answers: Dictionary) -> bool:
	var w: Variant = step.get("when")
	if not w is Dictionary:
		return true
	var v: Variant = get_answer(answers, str(w.get("key", "")))
	if (w as Dictionary).has("is"):
		return v == w.is
	if (w as Dictionary).has("not"):
		return v != w.not
	if (w as Dictionary).has("gt"):
		return v != null and float(v) > float(w.gt)
	return true


static func get_answer(answers: Dictionary, key: String) -> Variant:
	var parts := key.split(".")
	var cur: Variant = answers
	for p in parts:
		if not cur is Dictionary or not (cur as Dictionary).has(p):
			return null
		cur = cur[p]
	return cur


static func set_answer(answers: Dictionary, key: String, value: Variant) -> void:
	var parts := key.split(".")
	var cur: Dictionary = answers
	for i in parts.size() - 1:
		if not cur.get(parts[i]) is Dictionary:
			cur[parts[i]] = {}
		cur = cur[parts[i]]
	cur[parts[-1]] = value


## The building questions a helper may see (what you said about rooms and floors, nothing personal:
## no memories, no history in your own words, no places you care about).
static func building_answers(answers: Dictionary) -> Dictionary:
	answers = active_answers(answers)
	var out := {}
	for k in ["home_type", "floors", "basement", "rooms", "year_built"]:
		if answers.has(k):
			out[k] = answers[k]
	return out


## Retain answers in the draft when their question becomes irrelevant; never apply them to a
## different branch. Returning to that branch restores the original values.
static func inactive_keys(answers: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for s in STEPS:
		var key := str(s.get("key", ""))
		if key != "" and get_answer(answers, key) != null and not applies(s, answers):
			out.append(key)
	var floor: Variant = get_answer(answers, "my_room.floor")
	if floor != null and ((int(floor) == -1 and not bool(answers.get("basement", false))) or int(floor) >= int(answers.get("floors", 1))):
		if not "my_room.floor" in out:
			out.append("my_room.floor")
	return out


static func active_answers(answers: Dictionary) -> Dictionary:
	var out := answers.duplicate(true)
	for key in inactive_keys(answers):
		var parts := key.split(".")
		var target: Dictionary = out
		for i in parts.size() - 1:
			if target.get(parts[i]) is Dictionary:
				target = target[parts[i]]
		target.erase(parts[-1])
	return out


## How much of the address was given: "full" (a number and a street), "street", "city", or "none".
static func address_level(text: String) -> String:
	var t := text.strip_edges()
	if t == "":
		return "none"
	if not load("res://scripts/home/osm.gd").parse_coords(t).is_empty():
		return "coords"
	var first := t.split(" ", false)[0] if t.contains(" ") else t
	if first.is_valid_int() or (first.length() > 1 and first.left(first.length() - 1).is_valid_int()):
		return "full"
	var low := t.to_lower()
	for w in [" st", " street", " rd", " road", " ave", " avenue", " lane", " ln", " drive", " dr", " way", " court", " ct", " blvd", " place", " pl"]:
		if low.contains(w):
			return "street"
	return "city"
