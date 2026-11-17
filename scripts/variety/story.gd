extends RefCounted
## The story: chapters that open as your world grows, never by the clock. Each has a short scene
## and a few things to do (any order, any day; nothing expires and nothing is ever lost); finishing
## one opens the next and gives a cosmetic reward (a title to wear, a colour, a little keepsake).
## Progress is read from the world itself (places, joins, fountains, battles), so it's always true.

const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const Places := preload("res://scripts/world/places.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")

const CHAPTERS := [
	{"id": "home", "title": "A place of your own", "scene": "The world is small and quiet. It could use another place, and a friend to show it to.",
		"goals": [["places", 2, "Make a second place"], ["chats", 1, "Talk with a friend"]], "reward": {"title": "Homemaker"}},
	{"id": "edge", "title": "Beyond the edge", "scene": "Past the edge of the garden the grass keeps going. Where does it lead?",
		"goals": [["joins", 1, "Add a place beside another (Build mode > Place)"], ["crossings", 1, "Walk across the join"]], "reward": {"title": "Wanderer"}},
	{"id": "fountain", "title": "The Dream Gate", "scene": "Somewhere a basin of orange liquid ripples. A Dream Gate could open a way to the other side.",
		"goals": [["fountains", 1, "Open a Dream Gate"], ["dark_visits", 1, "Step into the Deep"]], "reward": {"title": "Gate Keeper"}},
	{"id": "spar", "title": "A friendly fight", "scene": "Down in the Deep, even the Bramins seem a little braver. A friend wants to test their moves.",
		"goals": [["battles", 1, "Have a friendly battle"]], "reward": {"title": "Good Sport"}},
	{"id": "mercy", "title": "Mercy", "scene": "Not every battle needs a winner.",
		"goals": [["spared", 1, "Spare someone in a battle"]], "reward": {"title": "Gentle Heart"}},
	{"id": "maker", "title": "Makers", "scene": "What if the next battle were yours, bullet by bullet?",
		"goals": [["made_battles", 1, "Save a battle from the Battle Maker"], ["drawn_bullets", 1, "Draw a bullet"]], "reward": {"title": "Battle Maker"}},
	{"id": "light", "title": "Light returns", "scene": "The Dream Gate can rest. Nothing on the other side will be lost.",
		"goals": [["sealed", 1, "Seal a Dream Gate (you can reopen it any time)"]], "reward": {"title": "Keeper of Light"}},
	{"id": "together", "title": "Together", "scene": "Some things are easier with company.",
		"goals": [["friends_battled", 3, "Have friendly battles with 3 different friends"], ["crystals", 3, "Find 3 Dark Crystals"]], "reward": {"title": "Together"}},
]


## The world as numbers the chapters ask about.
static func counts() -> Dictionary:
	var rooms := {}
	for id in SaveManager.list_rooms():
		rooms[id] = SaveManager.load_room(id)
	var joins := 0
	var fountains_open := 0
	var sealed := 0
	for id in rooms:
		joins += Places.edges(rooms[id]).size()
		for f in DarkWorlds.fountains(rooms[id]):
			if str(f.get("leads", "")) == "dark":
				if DarkWorlds.state(f) == "open":
					fountains_open += 1
				elif DarkWorlds.state(f) == "sealed":
					sealed += 1
	var logbook: Array = GameState.world.get("battle_log", []) if GameState.world.get("battle_log") is Array else []
	var a: Dictionary = VarietySave.data().get("almanac", {})
	var made := 0
	var bullets := 0
	var bd := SaveManager.abs_path("battles")
	for f in DirAccess.get_files_at(bd) if DirAccess.dir_exists_absolute(bd) else PackedStringArray():
		if str(f).ends_with(".json"):
			made += 1
	var bulls := bd.path_join("bullets")
	for f in DirAccess.get_files_at(bulls) if DirAccess.dir_exists_absolute(bulls) else PackedStringArray():
		if str(f).ends_with(".png"):
			bullets += 1
	return {
		"places": rooms.size(), "chats": int(a.get("chats", 0)) + (1 if GameState.characters.values().any(func(c): return not (c.get("memory_notes", []) as Array).is_empty() or float(c.get("affinity", 0.0)) > 0.0) else 0),
		"joins": joins / 2, "crossings": int(a.get("crossings", 0)), "fountains": fountains_open + sealed, "dark_visits": int(a.get("dark_visits", 0)),
		"battles": logbook.size(), "spared": logbook.filter(func(b): return str(b.get("outcome", "")) == "spared").size(),
		"made_battles": made, "drawn_bullets": bullets, "sealed": sealed,
		"friends_battled": _friends_battled(logbook),
		"crystals": int(a.get("crystals", 0)),
	}


## How many different friends you've had a battle with (the Battle Log keeps foes by name). Battles
## are one-on-one since 1.27.5; a battle fought with a friend at your side before that already
## finished this goal, and nothing is ever taken back.
static func _friends_battled(logbook: Array) -> int:
	var names := {}
	for c in GameState.characters.values():
		names[str(c.get("name", ""))] = true
	var met := {}
	for b in logbook:
		if not b is Dictionary:
			continue
		if b.get("party") is Array and (b.party as Array).size() >= 2:
			return 3
		for e in b.get("enemies", []):
			var n := str(e.get("name", "")) if e is Dictionary else ""
			if n != "" and names.has(n):
				met[n] = true
	return met.size()


## Where the story is: {chapter (index of the current one), done: [ids], current: {...}, progress: [[have, need, label]]}.
static func status(c: Dictionary = {}) -> Dictionary:
	var have := c if not c.is_empty() else counts()
	var done: Array = []
	for ch in CHAPTERS:
		var complete := true
		for g in ch.goals:
			if int(have.get(str(g[0]), 0)) < int(g[1]):
				complete = false
		if not complete:
			var prog: Array = []
			for g in ch.goals:
				prog.append([mini(int(have.get(str(g[0]), 0)), int(g[1])), int(g[1]), str(g[2])])
			return {"chapter": done.size(), "done": done, "current": ch, "progress": prog}
		done.append(str(ch.id))
	return {"chapter": CHAPTERS.size(), "done": done, "current": {}, "progress": []}


## Titles from finished chapters (worn like the Almanac's).
static func titles(c: Dictionary = {}) -> Array:
	var st := status(c)
	var out: Array = []
	for ch in CHAPTERS:
		if str(ch.id) in st.done:
			out.append({"id": "story_" + str(ch.id), "name": str(ch.reward.title), "from": "story"})
	return out


## Counts the game adds to as you play (crossing a join, visiting the Deep, going home, crystals...).
static func bump(key: String, n: int = 1) -> void:
	var v := VarietySave.data()
	var a: Dictionary = v.get("almanac", {})
	a[key] = int(a.get(key, 0)) + n
	v["almanac"] = a
	VarietySave.save()
