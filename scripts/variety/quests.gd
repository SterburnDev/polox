extends RefCounted
## Dream Quests and small Requests: optional, cosy goals offered by your
## residents, shaped by your Dreams board and World Bible. No timers, no
## failure: let one go any time. Each template is checked against the real
## world (not just a checkbox):
##   build        add N tiles / pieces / objects to a room
##   decorate     add N plants or things matching a word (a tile's name or tags, or plants)
##   visit        go to a room
##   hidden       find the hidden spot in a room (step on its cell)
##   shards       collect N Memory Shards (Platform Mode)
##   ledge        reach a checkpoint on a Platform course
##   talk         tell a resident about something (a chat message to them with the word)
##   gift         give a resident a gift
##   create_item  make a new item in the Item Workshop
##   create_tile  draw a new tile in a tile set
##   real_life    a tiny real-life step you tick yourself (opt-in, at most 1 in 4 offers)
## Rewards are cosmetic: keepsakes, a little outfit piece, a tile set, a Dream Door key.

const VarietySave := preload("res://scripts/variety/variety_save.gd")
const Clock := preload("res://scripts/variety/clock.gd")
const Items := preload("res://scripts/items/items.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const PlatformSave := preload("res://scripts/platform/platform_save.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")

const TEMPLATES: PackedStringArray = ["build", "decorate", "visit", "hidden", "shards", "ledge", "talk", "gift", "create_item", "create_tile", "real_life"]
const MAX_OPEN := 3
const REWARDS := [
	["keepsake", "Little trophy", "star", "#ffd166"], ["keepsake", "Wish lantern", "pebble", "#ffb3c7"],
	["keepsake", "Dream journal", "book", "#c9b6ff"], ["outfit", "Starlit scarf", "", "#8fd3ff"],
	["keepsake", "Moon charm", "gem", "#f3e9d2"], ["key", "Dream Door key", "gem", "#7af0ff"],
	["keepsake", "Kindness ribbon", "flower", "#e86a8a"], ["outfit", "Cloud hat", "", "#f3e9d2"],
	["tileset", "Dreamlight tiles", "", "#c58cff"],
]


static func q() -> Dictionary:
	return VarietySave.data().quests


static func active() -> Array:
	return q().active


static func done() -> Array:
	return q().done


# --- Making quests ------------------------------------------------------------------------------------

## A quest from a template. `params`: room, n, word, character, topic, step, dream...
static func make(template: String, params: Dictionary, giver: String = "", why: String = "") -> Dictionary:
	var p := params.duplicate()
	var title := ""
	var goal := int(p.get("n", 1))
	var cname := str(GameState.get_character(str(p.get("character", giver))).get("name", "a friend"))
	var room_name := str(SaveManager.load_room(str(p.get("room", ""))).get("name", p.get("room", ""))) if str(p.get("room", "")) != "" else "a room"
	match template:
		"build":
			goal = maxi(1, int(p.get("n", 3)))
			title = "Add %d things to %s" % [goal, room_name]
		"decorate":
			goal = maxi(1, int(p.get("n", 2)))
			title = "Decorate %s with %d %s" % [room_name, goal, str(p.get("word", "plant")) + ("s" if goal > 1 else "")]
		"visit":
			goal = 1
			title = "Visit %s" % room_name
		"hidden":
			goal = 1
			title = "Find the hidden spot in %s" % room_name
		"shards":
			goal = maxi(1, int(p.get("n", 1)))
			title = "Find %d Memory Shard%s" % [goal, "" if goal == 1 else "s"]
		"ledge":
			goal = 1
			title = "Reach a checkpoint on a Platform course"
		"talk":
			goal = 1
			title = "Tell %s about %s" % [cname, str(p.get("topic_text", p.get("topic", "your day")))]
		"gift":
			goal = 1
			title = "Give %s a gift" % cname
		"create_item":
			goal = 1
			title = "Make a new item in the Item Workshop"
		"create_tile":
			goal = 1
			title = "Draw a new tile"
		"real_life":
			goal = 1
			title = str(p.get("step", "Take one tiny step toward your dream"))
	var quest := {
		"id": "q%d_%d" % [int(Clock.now()), randi() % 10000], "template": template, "title": title, "why": why,
		"giver": giver, "params": p, "goal": goal, "progress": 0, "status": "active",
		"created": Clock.today(), "created_unix": Clock.now(), "baseline": baseline(template, p), "reward": {},
	}
	return quest


## What the world looks like when a quest starts (so only new progress counts).
static func baseline(template: String, p: Dictionary) -> Dictionary:
	match template:
		"build":
			return {"count": room_things(str(p.get("room", "")))}
		"decorate":
			return {"count": matching_things(str(p.get("room", "")), str(p.get("word", "plant")))}
		"shards":
			return {"count": PlatformSave.shard_count()}
		"ledge":
			return {"count": (PlatformSave.data().checkpoints as Array).size()}
		"gift":
			return {"count": (GameState.get_character(str(p.get("character", ""))).get("gifts_received", []) as Array).size()}
		"create_item":
			return {"count": Items.ids().size()}
		"create_tile":
			return {"count": tile_total()}
	return {}


static func room_things(room_id: String) -> int:
	if room_id == "" or not SaveManager.room_exists(room_id):
		return 0
	var r := SaveManager.load_room(room_id)
	return (r.get("tiles", []) as Array).size() + (r.get("objects", []) as Array).size() + TileLayers.count(r)


## Plants (prop objects) and tiles whose name or tags mention the word.
static func matching_things(room_id: String, word: String) -> int:
	if room_id == "" or not SaveManager.room_exists(room_id):
		return 0
	var r := SaveManager.load_room(room_id)
	var w := word.to_lower()
	var n := 0
	if w in ["plant", "flower", "green"]:
		n += (r.get("objects", []) as Array).filter(func(o): return str(o.get("type", "")) == "prop").size()
	for l in TileLayers.all(r):
		for c in (l.cells as Dictionary).values():
			var t := Tilesets.info(str(c.s), str(c.t))
			var hay := (str(t.get("name", c.t)) + " " + " ".join(t.get("tags", []))).to_lower()
			if hay.contains(w) or (w == "plant" and (hay.contains("flower") or hay.contains("bush") or hay.contains("grass") or hay.contains("mushroom"))):
				n += 1
	return n


static func tile_total() -> int:
	var n := 0
	for s in Tilesets.all():
		n += (s.get("tiles", []) as Array).size()
	return n


static func add(quest: Dictionary) -> Dictionary:
	(active() as Array).append(quest)
	VarietySave.save()
	return quest


# --- Checking ------------------------------------------------------------------------------------

## Re-checks every active quest against the world; returns the ones that just finished.
static func check_all() -> Array:
	var finished: Array = []
	for quest in active().duplicate():
		var p := progress(quest)
		quest["progress"] = mini(p, int(quest.goal))
		if p >= int(quest.goal):
			finished.append(complete(quest))
	if not finished.is_empty():
		VarietySave.save()
	return finished


static func progress(quest: Dictionary) -> int:
	var p: Dictionary = quest.get("params", {})
	var b: Dictionary = quest.get("baseline", {})
	match str(quest.template):
		"build":
			return maxi(0, room_things(str(p.get("room", ""))) - int(b.get("count", 0)))
		"decorate":
			return maxi(0, matching_things(str(p.get("room", "")), str(p.get("word", "plant"))) - int(b.get("count", 0)))
		"shards":
			return maxi(0, PlatformSave.shard_count() - int(b.get("count", 0)))
		"ledge":
			return maxi(0, (PlatformSave.data().checkpoints as Array).size() - int(b.get("count", 0)))
		"gift":
			return maxi(0, (GameState.get_character(str(p.get("character", ""))).get("gifts_received", []) as Array).size() - int(b.get("count", 0)))
		"create_item":
			return maxi(0, Items.ids().size() - int(b.get("count", 0)))
		"create_tile":
			return maxi(0, tile_total() - int(b.get("count", 0)))
	return int(quest.get("hits", 0))   # visit, hidden, talk, real_life: events below


## Events from the world (rooms entered, cells stepped on, chat messages, "I did it").
static func on_visit(room_id: String) -> Array:
	return _hit(func(quest): return str(quest.template) == "visit" and str(quest.params.get("room", "")) == room_id)


static func on_step(room_id: String, cell: Vector2i) -> Array:
	return _hit(func(quest): return str(quest.template) == "hidden" and str(quest.params.get("room", "")) == room_id and Vector2i(int(quest.params.get("x", -1)), int(quest.params.get("z", -1))) == cell)


static func on_chat(character_id: String, text: String) -> Array:
	var t := text.to_lower()
	return _hit(func(quest):
		if str(quest.template) != "talk" or str(quest.params.get("character", "")) != character_id:
			return false
		var words: Array = quest.params.get("words", [])
		if words.is_empty():
			return t.strip_edges().length() >= 3
		return words.any(func(w): return t.contains(str(w).to_lower())))


static func did_it(quest_id: String) -> Array:
	return _hit(func(quest): return str(quest.id) == quest_id and str(quest.template) == "real_life")


static func _hit(match_fn: Callable) -> Array:
	var finished: Array = []
	for quest in active().duplicate():
		if match_fn.call(quest):
			quest["hits"] = int(quest.get("hits", 0)) + 1
			quest["progress"] = mini(int(quest.hits), int(quest.goal))
			if int(quest.hits) >= int(quest.goal):
				finished.append(complete(quest))
	if not finished.is_empty():
		VarietySave.save()
	return finished


## Done: a cosmetic reward, into the done list (and the Almanac).
static func complete(quest: Dictionary) -> Dictionary:
	(active() as Array).erase(quest)
	quest["status"] = "done"
	quest["done"] = Clock.today()
	quest["reward"] = give_reward(quest)
	(done() as Array).append(quest)
	VarietySave.count("quests_done")
	return quest


static func let_go(quest_id: String) -> void:
	for quest in active().duplicate():
		if str(quest.id) == quest_id:
			(active() as Array).erase(quest)
			quest["status"] = "let_go"
			(q().let_go as Array).append(quest)
	VarietySave.save()


## [GOALS] What finishing this quest will give, without giving it: {name, kind, words}. The same draw
## as give_reward (a quest's reward is fixed by its id), so the card can say it up front.
static func reward_preview(quest: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(quest.id))
	var r: Array = REWARDS[rng.randi() % REWARDS.size()]
	var words: String = {"keepsake": "a keepsake", "outfit": "something to wear", "key": "it opens a Dream Door", "tileset": "tiles to build with"}.get(str(r[0]), "a keepsake")
	return {"name": str(r[1]), "kind": str(r[0]), "words": words}


static func give_reward(quest: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(quest.id))
	var r: Array = REWARDS[rng.randi() % REWARDS.size()]
	if str(r[0]) == "tileset":
		var set_id := dreamlight_set()
		if set_id != "":
			return {"tileset": set_id, "name": str(r[1]), "kind": "tileset"}
		r = REWARDS[0]
	var it := Items.defaults("armor" if str(r[0]) == "outfit" else "keepsake", "head" if str(r[0]) == "outfit" else "")
	it["name"] = str(r[1])
	it["flavor"] = "For \"%s\"%s." % [str(quest.title), (" (from %s)" % GameState.get_character(str(quest.giver)).get("name", "")) if str(quest.giver) != "" else ""]
	it["tags"] = ["reward", "quest"] + (["dream_door_key"] if str(r[0]) == "key" else [])
	if str(r[2]) != "":
		it["auto_icon"] = {"shape": str(r[2]), "color": str(r[3])}
	else:
		it["auto_icon"]["color"] = str(r[3])
	var id := Items.save_item(it)
	var Inventory: GDScript = load("res://scripts/items/inventory.gd")
	Inventory.add(id, 1)
	return {"item": id, "name": str(r[1]), "kind": str(r[0])}


## A reward tile set (made once per world): starry floor, cloud, nebula, moon dust.
static func dreamlight_set() -> String:
	if Tilesets.exists("dreamlight"):
		return "dreamlight"
	const F := preload("res://scripts/world/tileset_factory.gd")
	var s := Tilesets.create("Dreamlight", 32)
	if str(s.get("id", "")) == "":
		return ""
	Tilesets.add_tile(s, "Dream floor", F._stars(Color("#2a2445"), 10))
	Tilesets.add_tile(s, "Soft cloud", F._cloud())
	Tilesets.add_tile(s, "Nebula", F._nebula())
	Tilesets.add_tile(s, "Moon dust", F._speckle(Color("#c9b6ff"), Color("#f3e9d2"), 50), {"slippery": true})
	return str(s.id)


# --- Offers --------------------------------------------------------------------------------------

## A Request Moment becomes a small quest from that resident.
static func from_request(m: Dictionary) -> Dictionary:
	var ex: Dictionary = m.get("extra", {})
	var who := str(m.get("character", ""))
	var room := str(m.get("room", ""))
	var params := {"character": who, "room": room}
	var template := str(ex.get("quest", "talk"))
	match template:
		"talk":
			params["topic"] = str(ex.get("topic", "day"))
			params["topic_text"] = {"day": "your day", "dream": "your dream", "hello": "anything"}.get(str(ex.get("topic", "day")), "your day")
			params["words"] = [] if str(ex.get("topic", "")) in ["hello", "day"] else ["dream"] + _dream_words()
		"build":
			template = "decorate"
			params["word"] = str(ex.get("tag", "plant"))
			params["n"] = 1
		"platform_ledge":
			template = "ledge"
		"platform_shards":
			template = "shards"
			params["n"] = 1
	return add(make(template, params, who, str(m.get("text", ""))))


static func _dream_words() -> Array:
	var out: Array = []
	for d in GameState.dream_list():
		for w in str(d.get("text", "")).to_lower().split(" ", false):
			if w.length() >= 4 and out.size() < 6:
				out.append(w)
	return out


## Today's Dream Quests: keeps up to MAX_OPEN open quests, new ones shaped by a
## dream (or the World Bible), deterministic for the day. Real-life steps only
## when switched on, and at most one in four offers.
static func offer_dream_quests(date: String = "") -> Array:
	var v := VarietySave.data()
	var day := date if date != "" else Clock.today()
	if str(v.get("dream_offer_day", "")) == day:
		return []
	v["dream_offer_day"] = day
	var made: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("quests|%s|%s" % [str(GameState.world.get("created", "")), day])
	var residents: Array = GameState.characters.keys().filter(func(id): return not bool(GameState.characters[id].get("visitor", false)))
	residents.sort()
	var rooms: Array = Array(SaveManager.list_rooms())
	rooms.sort()
	var dreams: Array = GameState.dream_list().filter(func(d): return str(d.get("status", "")) != "done")
	var offers_so_far := int(v.get("offers_total", 0))
	var real_life_so_far := int(v.get("offers_real_life", 0))
	while active().size() < MAX_OPEN and made.size() < 2:
		var giver := str(residents[rng.randi() % residents.size()]) if not residents.is_empty() else ""
		var dream := str(dreams[rng.randi() % dreams.size()].get("text", "")) if not dreams.is_empty() else str(GameState.world.get("world_bible", {}).get("themes", ""))
		var room := str(rooms[rng.randi() % rooms.size()]) if not rooms.is_empty() else ""
		var allow_real := bool(v.get("real_life", true)) and dream != "" and (real_life_so_far + 1) * 4 <= offers_so_far + 1
		var choices := ["build", "decorate", "visit", "hidden", "shards", "talk", "gift", "create_item", "create_tile", "ledge"]
		if allow_real:
			choices.append("real_life")
		if giver == "":
			choices = choices.filter(func(t): return not t in ["talk", "gift"])
		var elsewhere: Array = rooms.filter(func(r): return str(r) != GameState.current_room_id)
		if elsewhere.is_empty():   # a visit means going somewhere: not the room you're in
			choices = choices.filter(func(t): return t != "visit")
		var open_templates: Array = active().map(func(x): return str(x.template))
		choices = choices.filter(func(t): return not t in open_templates)
		if choices.is_empty():
			break
		var t := str(choices[rng.randi() % choices.size()])
		var params := {"character": giver, "room": room, "dream": dream}
		var why := _why(t, dream, giver)
		match t:
			"visit":
				params["room"] = str(elsewhere[rng.randi() % elsewhere.size()])
			"build":
				params["n"] = 3
			"decorate":
				params["n"] = 2
				params["word"] = "plant"
			"hidden":
				var cell := _hidden_cell(room, rng)
				params["x"] = cell.x
				params["z"] = cell.y
			"shards":
				params["n"] = 1
			"talk":
				params["topic"] = "dream"
				params["topic_text"] = ("your dream: " + dream) if dream != "" else "your dream"
				params["words"] = ["dream"] + _dream_words()
			"real_life":
				params["step"] = "A tiny real step toward \"%s\" (even five minutes counts). Tick it when you've done it." % dream
				real_life_so_far += 1
		var quest := add(make(t, params, giver, why))
		quest["dream"] = dream
		made.append(quest)
		offers_so_far += 1
	v["offers_total"] = offers_so_far
	v["offers_real_life"] = real_life_so_far
	VarietySave.save()
	return made


static func _why(t: String, dream: String, giver: String) -> String:
	var who := str(GameState.get_character(giver).get("name", "A friend"))
	var d := "your dream (%s)" % dream if dream != "" else "your dream"
	match t:
		"build", "decorate":
			return "%s: \"For %s, a little corner to dream in would help.\"" % [who, d]
		"visit", "hidden":
			return "%s: \"I hid something for you. It's for %s.\"" % [who, d]
		"shards", "ledge":
			return "%s: \"Climbing makes dreams feel closer. Even %s.\"" % [who, d]
		"talk":
			return "%s: \"Tell me about %s?\"" % [who, d]
		"gift":
			return "%s: \"Small gifts are good luck for big dreams.\"" % who
		"create_item", "create_tile":
			return "%s: \"Make something new. Big dreams start with small makes.\"" % who
		"real_life":
			return "%s: \"Only if you feel like it.\"" % who
	return ""


static func _hidden_cell(room_id: String, rng: RandomNumberGenerator) -> Vector2i:
	var r := SaveManager.load_room(room_id) if room_id != "" else {}
	var w := int(r.get("size", {}).get("w", 10))
	var d := int(r.get("size", {}).get("d", 10))
	for i in 30:
		var c := Vector2i(rng.randi_range(1, w - 2), rng.randi_range(1, d - 2))
		if RoomEditor.object_at(r, c.x, c.y).is_empty() and RoomEditor.stack_top(r, c.x, c.y) == 0.0:
			return c
	return Vector2i(1, 1)


## A hint for a hidden spot: which part of the room.
static func hint(quest: Dictionary) -> String:
	if str(quest.template) != "hidden":
		return ""
	var r := SaveManager.load_room(str(quest.params.get("room", "")))
	var w := float(r.get("size", {}).get("w", 10))
	var d := float(r.get("size", {}).get("d", 10))
	var x := float(quest.params.get("x", 0))
	var z := float(quest.params.get("z", 0))
	var side := "left" if x < w / 3.0 else ("right" if x > w * 2.0 / 3.0 else "middle")
	var depth := "back" if z < d / 3.0 else ("front" if z > d * 2.0 / 3.0 else "centre")
	return "Somewhere in the %s %s of the room." % [depth, side]
