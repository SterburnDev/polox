extends RefCounted
## What the variety pack keeps, in world.json under "variety" (so it travels
## with snapshots, bundles and Phone Link):
##   history       [{date, ids}] the last 14 days of Moments (no repeats)
##   custom        your own Moments [{id, kind, text}]
##   today         {date, moments, applied, shown}
##   echo          Memory Echo moments (your own past) on/off (off by default)
##   real_life     gentle real-life quest steps on/off (on, at most 1 in 4)
##   quests        {active: [], done: [], let_go: []}
##   almanac       counters (moments seen, quests done, doors opened, ...)
##   dream_archive the last 10 Dream Door rooms you didn't keep
##   last_seen     when you last played (While You Were Away)

const VERSION := 1


static func data() -> Dictionary:
	var w: Dictionary = GameState.world
	if not w.get("variety") is Dictionary:
		w["variety"] = {}
	var v: Dictionary = w.variety
	var defaults := {"version": VERSION, "history": [], "custom": [], "today": {}, "echo": false, "real_life": true,
		"quests": {"active": [], "done": [], "let_go": []}, "almanac": {}, "dream_archive": [], "last_seen": 0.0,
		"celebrations": []}
	for k in defaults:
		if not v.has(k) or typeof(v[k]) != typeof(defaults[k]):
			v[k] = defaults[k]
	var q: Dictionary = v.quests
	for k in ["active", "done", "let_go"]:
		if not q.get(k) is Array:
			q[k] = []
	return v


static func save() -> void:
	GameState.save_world()


## Almanac counters: +n to one of them.
static func count(key: String, n: int = 1) -> void:
	var a: Dictionary = data().almanac
	a[key] = int(a.get(key, 0)) + n
