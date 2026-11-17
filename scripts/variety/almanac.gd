extends RefCounted
## The Almanac: a gentle log of what your world has grown into (rooms built,
## tile sets used, items made, friends met, Moments seen, quests done, shards
## found, Dream Doors opened, letters received), with cosmetic titles you can
## wear. No goals, no streaks, nothing to lose. Memory Shards also unlock a
## memory in the Memory Book (the shard's own words, or a suggested one).

const VarietySave := preload("res://scripts/variety/variety_save.gd")
const PlatformSave := preload("res://scripts/platform/platform_save.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Items := preload("res://scripts/items/items.gd")

const ROWS := [["rooms", "Places made"], ["dark_visits", "Visits to the Deep"], ["light_visits", "Trips home"], ["battles", "Friendly battles"], ["spared", "Spared in battle"],
	["crystals", "Dark Crystals found"], ["discoveries", "Discoveries"], ["tile_sets", "Tile sets used"], ["items", "Items made"], ["friends", "Friends met"],
	["moments", "Moments seen"], ["quests", "Quests done"], ["shards", "Memory Shards found"], ["doors", "Dream Doors opened"],
	["letters", "Letters received"], ["hangouts", "Hangouts"]]
const TITLES := [
	["rooms", 3, "Room Maker"], ["rooms", 10, "Builder of Many Rooms"], ["tile_sets", 3, "Tile Painter"],
	["items", 1, "Maker"], ["items", 10, "Workshop Wizard"], ["friends", 3, "Good Neighbor"],
	["moments", 7, "Collector of Days"], ["moments", 30, "Keeper of Stories"], ["quests", 1, "Helpful Heart"],
	["quests", 10, "Dream Weaver"], ["shards", 1, "Shard Seeker"], ["shards", 10, "Memory Keeper"],
	["doors", 1, "Door Opener"], ["doors", 10, "Dream Walker"], ["letters", 3, "Pen Pal"], ["hangouts", 3, "Good Company"],
	["crystals", 5, "Crystal Finder"], ["crystals", 20, "Crystal Keeper"], ["discoveries", 5, "Explorer"], ["battles", 10, "Sparring Partner"],
]
const SUGGESTED := [
	"A morning when everything felt possible.", "Someone once laughed at your joke until they cried.",
	"The smell of rain on a warm day.", "A time you were braver than you felt.", "A song that found you at the right moment.",
	"A kind thing a stranger said.", "The first time this world felt like home.", "A small promise you kept to yourself.",
]


## Every count, from the world itself (and the variety counters).
static func counts() -> Dictionary:
	var v := VarietySave.data()
	var a: Dictionary = v.almanac
	var rooms := 0
	var sets := {}
	for id in SaveManager.list_rooms():
		var r := SaveManager.load_room(id)
		if bool(r.get("dream", false)):
			continue
		rooms += 1
		for st in TileLayers.tiles_used(r):
			sets[str(st[0])] = true
	var made := 0
	for it in Items.all():
		var tags: Array = it.get("tags", [])
		if not bool(it.get("starter", false)) and not tags.any(func(t): return str(t) in ["found", "away", "reward", "quest", "dream_gift", "starter"]):
			made += 1
	var friends := GameState.characters.values().filter(func(c): return not bool(c.get("visitor", false))).size() + int(a.get("visitors_met", 0))
	return {
		"rooms": rooms, "tile_sets": sets.size(), "items": made, "friends": friends,
		"moments": int(a.get("moments_seen", 0)), "quests": int(a.get("quests_done", 0)),
		"shards": PlatformSave.shard_count(), "doors": int(a.get("dream_doors", 0)), "letters": int(a.get("letters", 0)),
		"hangouts": int(a.get("hangouts", 0)),
		"dark_visits": int(a.get("dark_visits", 0)), "light_visits": int(a.get("light_visits", 0)), "crystals": int(a.get("crystals", 0)), "discoveries": int(a.get("discoveries", 0)),
		"battles": (GameState.world.get("battle_log", []) as Array).size() if GameState.world.get("battle_log") is Array else 0,
		"spared": (GameState.world.get("battle_log", []) as Array).filter(func(b): return str(b.get("outcome", "")) == "spared").size() if GameState.world.get("battle_log") is Array else 0,
	}


## Titles you've earned: [{id, name, from}]
static func titles(c: Dictionary = {}) -> Array:
	var have := c if not c.is_empty() else counts()
	var out: Array = []
	for t in TITLES:
		if int(have.get(str(t[0]), 0)) >= int(t[1]):
			out.append({"id": "%s_%d" % [t[0], t[1]], "name": str(t[2]), "from": str(t[0])})
	out.append_array(load("res://scripts/variety/story.gd").titles())
	return out


## What makes each count grow, in a line a player can act on (shown under a title that is coming up).
const HOW := {
	"rooms": "Make a new place: Build, then Place.", "tile_sets": "Paint a floor with a tile set you haven't used.",
	"items": "Make something in the Item Workshop (Bag).", "friends": "Invite a visitor to stay, or make a new friend.",
	"moments": "Each day you come by has its own Moments.", "quests": "Finish a quest (Quests on the Today card).",
	"shards": "Find a Memory Shard on a Platform course.", "doors": "Open a Dream Door with a Dream Door key.",
	"letters": "Letters arrive while you are away.", "hangouts": "Hang out with a friend (click them, then Hang out).",
	"crystals": "Look for Dark Crystals in the Deep.", "discoveries": "Explore the Deep.", "battles": "Have a friendly battle.",
}


## [GOALS] The titles nearest to being earned, nearest first, at most one per count (its next one):
## [{name, from, label, have, need, how}]. Nothing here expires and nothing is lost by ignoring it.
static func coming_up(c: Dictionary = {}, limit: int = 3) -> Array:
	var have := c if not c.is_empty() else counts()
	var labels := {}
	for r in ROWS:
		labels[str(r[0])] = str(r[1])
	var next_for := {}
	for t in TITLES:
		var from := str(t[0])
		var need := int(t[1])
		var got := int(have.get(from, 0))
		if got < need and (not next_for.has(from) or need < int(next_for[from].need)):
			next_for[from] = {"name": str(t[2]), "from": from, "label": str(labels.get(from, from)), "have": got, "need": need, "how": str(HOW.get(from, ""))}
	var out: Array = next_for.values()
	# Fewest steps left first; between equals, the one that is further along.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left_a := int(a.need) - int(a.have)
		var left_b := int(b.need) - int(b.have)
		if left_a != left_b:
			return left_a < left_b
		if int(a.have) * int(b.need) != int(b.have) * int(a.need):
			return int(a.have) * int(b.need) > int(b.have) * int(a.need)
		return str(a.name) < str(b.name))
	return out.slice(0, maxi(0, limit))


## [GOALS] Titles earned since this was last asked (their names), remembered in the world so each is
## announced once. A world from before this existed starts with everything it already has as "seen":
## an old save isn't greeted with a dozen announcements.
static func new_titles(c: Dictionary = {}) -> PackedStringArray:
	var a: Dictionary = VarietySave.data().almanac
	var names := PackedStringArray()
	for t in titles(c):
		names.append(str(t.name))
	if not a.get("titles_seen") is Array:
		a["titles_seen"] = Array(names)
		VarietySave.save()
		return PackedStringArray()
	var fresh := PackedStringArray()
	for n in names:
		if not n in a.titles_seen:
			fresh.append(n)
			(a.titles_seen as Array).append(n)
	if not fresh.is_empty():
		VarietySave.save()
	return fresh


static func wear(title: String) -> void:
	VarietySave.data()["title"] = title
	VarietySave.save()


static func worn() -> String:
	return str(VarietySave.data().get("title", ""))


## A shard's memory for the Memory Book: its own words, else a suggested one.
static func shard_memory(o: Dictionary) -> String:
	var own := str(o.get("memory", "")).strip_edges()
	if own != "":
		return own
	return str(SUGGESTED[absi(hash(str(o.get("id", "")))) % SUGGESTED.size()])


static func on_shard(o: Dictionary, room_id: String) -> void:
	GameState.add_moment("A Memory Shard", shard_memory(o), "", "auto", {"shard": "%s/%s" % [room_id, str(o.get("id", ""))]})
