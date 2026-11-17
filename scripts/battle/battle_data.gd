extends RefCounted
## Battles as data. A battle: {"id", "name", "enemies": [enemy...], "music": "", "made": iso}.
## An enemy: {"character": "<friend id>" or "", "name", "picture": "<path>" (else the friend's face),
##   "preset": "gentle"|"normal"|"tough", "hp", "attack", "defense", "mercy_max",
##   "acts": [{"name", "text", "mercy", "tp"}], "lines": {"intro", "check", "hurt", "spared", "won",
##   "idle": [...]}, "waves": [wave...]  (patterns.gd)}
## Saved battles live in the world's battles/ folder (they sync with Phone Link like the rest of
## the world). Templates are built in. Stats come from presets, so nothing needs numbers.
## Tags: [BATTLE_MAKER]

const Patterns := preload("res://scripts/battle/patterns.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Spells := preload("res://scripts/battle/battle_spells.gd")
const Spars := preload("res://scripts/battle/sparring_catalog.gd")
const VERSION := 3
static var last_error := ""

const PRESETS := {
	"gentle": {"hp": 40, "attack": 3, "defense": 0, "mercy_max": 60},
	"normal": {"hp": 70, "attack": 5, "defense": 1, "mercy_max": 100},
	"tough": {"hp": 120, "attack": 8, "defense": 3, "mercy_max": 140},
}
const PRESET_LABELS := {"gentle": "Gentle", "normal": "Normal", "tough": "Tough"}

## Acts everyone has, plus ones made from what you know about each other.
const COMMON_ACTS := [
	{"name": "Check", "text": "", "mercy": 0},
	{"name": "Compliment", "text": "You tell them something you really like about them. They blush.", "mercy": 25},
	{"name": "Joke", "text": "You tell your worst joke. They try very hard not to laugh.", "mercy": 20},
	{"name": "Hum together", "text": "You hum a tune together. The next wave slows down.", "mercy": 30, "tp": 16, "slow": 1},
	{"name": "Soft lullaby", "text": "A quiet tune. Their eyelids grow heavy.", "mercy": 10, "tp": 0, "tired": true},
	{"name": "Friendly bow", "text": "You bow with a little flourish. They bow back, beaming.", "mercy": 30, "tp": 8},
]


static func battles_dir() -> String:
	return SaveManager.abs_path("battles")


static func enemy_from_friend(c: Dictionary, preset: String = "normal") -> Dictionary:
	var p: Dictionary = PRESETS.get(preset, PRESETS.normal)
	var name := str(c.get("name", "Friend"))
	var acts: Array = COMMON_ACTS.duplicate(true)
	var likes := str(c.get("likes", "")).split(",", false)
	if not likes.is_empty() and str(likes[0]).strip_edges() != "":
		var like := str(likes[0]).strip_edges()
		acts.append({"name": "Talk about %s" % like, "text": "You bring up %s. %s lights up and sits this turn out." % [like, name], "mercy": 40, "skip_wave": true})
	return {
		"character": str(c.get("id", "")), "name": name, "picture": "", "preset": preset,
		"hp": int(p.hp), "attack": int(p.attack), "defense": int(p.defense), "mercy_max": int(p.mercy_max),
		"acts": acts,
		"lines": {"intro": "%s squares up, grinning." % name, "check": str(c.get("personality", "A friend, ready for a friendly fight.")).substr(0, 120),
			"hurt": "Hey! Nice one!", "spared": "That was fun. Again sometime?", "won": "Okay, okay, you win! I'm tired.",
			"idle": ["%s bounces on their heels." % name, "%s is having fun." % name, "%s hums a battle theme." % name]},
		"waves": [Patterns.template("rain"), Patterns.template("aimed_trio"), Patterns.template("crosswind")],
	}


## Built-in battles (5+): a pattern set and a preset, used with whoever you're fighting.
const TEMPLATES := {
	"friendly_spar": {"name": "Friendly spar", "preset": "gentle", "waves": ["rain", "crosswind", "heart_hug"]},
	"rainy_day": {"name": "Rainy day duel", "preset": "normal", "waves": ["rain", "downpour", "from_below"]},
	"star_shower": {"name": "Star shower", "preset": "normal", "waves": ["aimed_trio", "fan", "meteor"]},
	"spiral_dance": {"name": "Spiral dance", "preset": "normal", "waves": ["spiral", "orbit", "double_spiral"]},
	"winter_showdown": {"name": "Winter showdown", "preset": "tough", "waves": ["snow", "pincer", "crossfire"]},
	"bouncy_castle": {"name": "Bouncy castle", "preset": "gentle", "waves": ["bouncers", "fountain", "zigzag"]},
}
const TEMPLATE_ORDER: PackedStringArray = ["friendly_spar", "rainy_day", "star_shower", "spiral_dance", "winter_showdown", "bouncy_castle"]
const DEMOS := {"lantern_lesson": "Lantern lesson", "paper_parade": "Paper parade", "clockwork_picnic": "Clockwork picnic"}


## Original encounters. Demonstration companions are temporary; they do not create saved friends.
static func demonstration(id: String) -> Dictionary:
	if not DEMOS.has(id):
		return {}
	var names: Array = ["Lantern moth"] if id == "lantern_lesson" else (["Paper fox", "Ribbon bird"] if id == "paper_parade" else ["Teacup knight", "Clockwork snail", "Dandelion"])
	var foes: Array = []
	for i in names.size():
		var e := enemy_from_friend({"name": names[i]}, "gentle" if id != "clockwork_picnic" else "normal")
		e["hp"] = 55 + i * 10
		e["attack"] = 3 + i
		e["mercy_max"] = 100
		e["acts"] = [
			{"name": "Check", "text": "", "mercy": 0},
			{"name": "Share a story", "text": "Your little story brings a warm smile.", "mercy": 40},
			{"name": "Soft lullaby", "text": "They lean back, sleepy and content.", "mercy": 10, "tired": true},
			{"name": "Curtain call", "text": "You take a deep bow. Applause, then a peaceful hush.", "mercy": 60, "tp": 16},
		]
		e["waves"] = [Patterns.template(["rain", "crosswind", "fan"][i]), Patterns.template(["heart_hug", "snow", "zigzag"][i])]
		e.lines["intro"] = "A little rehearsal beneath the stars. Everyone has a part."
		e.lines["check"] = "A lullaby makes them TIRED; Hush helps them rest. Stories fill MERCY."
		e.lines["spared"] = "The rehearsal ends in a round of warm applause."
		foes.append(e)
	return clean({"name": DEMOS[id], "demo": id, "enemies": foes, "party_roles": ["guide", "guardian", "dreamer"]})


## A battle from a template against `foe` (a friend's character data).
static func from_template(template_id: String, foe: Dictionary) -> Dictionary:
	if template_id in Spars.ORDER:
		return clean(Spars.raw(template_id))
	var t: Dictionary = TEMPLATES.get(template_id, TEMPLATES.friendly_spar)
	var e := enemy_from_friend(foe, str(t.preset))
	e["waves"] = (t.waves as Array).map(func(w): return Patterns.template(str(w)))
	return {"id": "", "name": "%s vs. %s" % [str(t.name), str(foe.get("name", "?"))], "template": template_id, "enemies": [e], "music": ""}


## Rules, rewards and presentation (Battle Maker > Rules / Presentation). Missing in battles made before
## them: the defaults below are exactly how those battles always played.
const WINS := ["any", "spare", "survive"]
const WIN_NAMES := ["Spare or tire everyone out", "Spare everyone (FIGHT can't tire them)", "Last a number of turns"]
const LINEUPS := ["together", "one_by_one"]
const LINEUP_NAMES := ["All at once", "One after another"]
const ORDERS := ["cycle", "shuffle", "once"]
const ORDER_NAMES := ["In order, then again", "Shuffled", "In order, then keep the last"]
const BACKDROPS := ["black", "night", "dusk", "forest", "sea", "candy"]
const BACKDROP_NAMES := ["Black", "Starry night", "Dusk", "Forest", "Under the sea", "Candy"]
const EFFECTS := ["none", "stars", "rain", "snow", "petals", "bubbles"]
const EFFECT_NAMES := ["None", "Falling stars", "Rain", "Snow", "Petals", "Bubbles"]


static func clean_rules(r: Variant) -> Dictionary:
	var d: Dictionary = r if r is Dictionary else {}
	var win := str(d.get("win", "any"))
	var lineup := str(d.get("lineup", "together"))
	return {"win": win if win in WINS else "any", "survive_turns": int(Patterns.number(d.get("survive_turns"), 5, 1, 20)),
		"damage": Patterns.number(d.get("damage"), 1.0, 0.25, 3.0), "soul_speed": Patterns.number(d.get("soul_speed"), 1.0, 0.5, 2.0),
		"lineup": lineup if lineup in LINEUPS else "together"}


static func clean_rewards(r: Variant) -> Dictionary:
	var d: Dictionary = r if r is Dictionary else {}
	return {"item": str(d.get("item", "")).left(64), "count": int(Patterns.number(d.get("count"), 1, 1, 9)), "note": str(d.get("note", "")).left(160)}


static func clean_look(r: Variant) -> Dictionary:
	var d: Dictionary = r if r is Dictionary else {}
	var bg := str(d.get("backdrop", "black"))
	var fx := str(d.get("effect", "none"))
	return {"backdrop": bg if bg in BACKDROPS else "black", "effect": fx if fx in EFFECTS else "none", "intro": str(d.get("intro", "")).left(160)}


## What a battle still needs before it can be saved: [{field, what to do}] (the Maker links each to its control).
static func problems(b: Dictionary) -> Array:
	var out: Array = []
	if str(b.get("name", "")).strip_edges() == "":
		out.append({"field": "name", "section": "encounter", "text": "Give the battle a name."})
	var enemies: Array = b.get("enemies", []) if b.get("enemies") is Array else []
	if enemies.is_empty():
		out.append({"field": "enemies", "section": "enemies", "text": "Add someone to face."})
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		if str(e.get("name", "")).strip_edges() == "":
			out.append({"field": "enemy_name", "section": "enemies", "enemy": i, "text": "Enemy %d needs a name." % (i + 1)})
		var waves: Array = e.get("waves", []) if e.get("waves") is Array else []
		if waves.is_empty():
			out.append({"field": "waves", "section": "waves", "enemy": i, "text": "%s needs at least one wave." % str(e.get("name", "Enemy %d" % (i + 1)))})
		for w in waves.size():
			if (waves[w].get("spawners", []) as Array).is_empty():
				out.append({"field": "spawners", "section": "waves", "enemy": i, "wave": w, "text": "Wave %d of %s has nothing in it: add a pattern." % [w + 1, str(e.get("name", ""))]})
	var rw: Dictionary = clean_rewards(b.get("rewards", {}))
	if str(rw.item) != "" and not preload("res://scripts/items/items.gd").exists(str(rw.item)):
		out.append({"field": "reward", "section": "rules", "text": "The reward item is gone: choose another, or none."})
	return out


static func clean(b: Dictionary) -> Dictionary:
	if int(Patterns.number(b.get("version"), 1, 1, 9999)) > VERSION:
		return {}
	var out := {"version": VERSION, "id": str(b.get("id", "")), "name": str(b.get("name", "Battle")).substr(0, 60), "template": str(b.get("template", "")), "music": str(b.get("music", "")), "enemies": [],
		"party_roles": [], "party_spells": [], "allow_party": bool(b.get("allow_party", false)), "speed": Patterns.number(b.get("speed"), 1, 0.5, 1.5), "demo": str(b.get("demo", "")),
		"rules": clean_rules(b.get("rules")), "rewards": clean_rewards(b.get("rewards")), "look": clean_look(b.get("look"))}
	var roles: Array = b.get("party_roles", []) if b.get("party_roles") is Array else []
	var spells: Array = b.get("party_spells", []) if b.get("party_spells") is Array else []
	for i in 3:
		var role := str(roles[i]) if i < roles.size() and str(roles[i]) in Spells.ROLES else str(Spells.ROLES[i])
		out.party_roles.append(role)
		out.party_spells.append(Spells.clean_ids(spells[i] if i < spells.size() else null, role))
	var raw_enemies: Array = b.get("enemies", []) if b.get("enemies") is Array else []
	for e in raw_enemies:
		if not e is Dictionary:
			continue
		var p: Dictionary = PRESETS.get(str(e.get("preset", "normal")), PRESETS.normal)
		var ce := {
			"character": str(e.get("character", "")), "name": str(e.get("name", "Someone")).substr(0, 40), "picture": str(e.get("picture", "")),
			"preset": str(e.get("preset", "normal")),
			"hp": int(Patterns.number(e.get("hp"), p.hp, 1, 9999)), "attack": int(Patterns.number(e.get("attack"), p.attack, 0, 99)),
			"defense": int(Patterns.number(e.get("defense"), p.defense, 0, 99)), "mercy_max": int(Patterns.number(e.get("mercy_max"), p.mercy_max, 1, 1000)),
			"acts": [], "lines": {}, "waves": [], "phases": [], "tired": bool(e.get("tired", false)), "tired_at": Patterns.number(e.get("tired_at"), 0.25, 0, 1),
			"order": str(e.get("order", "cycle")) if str(e.get("order", "cycle")) in ORDERS else "cycle",
		}
		var acts: Array = e.get("acts", []) if e.get("acts") is Array else []
		for a in acts.slice(0, 12):
			if a is Dictionary:
				ce.acts.append({"name": str(a.get("name", "Act")).left(40), "text": str(a.get("text", "You share a quiet moment.")).left(240),
					"mercy": int(Patterns.number(a.get("mercy"), 20, 0, 1000)), "tp": int(Patterns.number(a.get("tp"), 0, 0, 100)),
					"helpers": int(Patterns.number(a.get("helpers"), 0, 0, 2)), "next_wave": int(Patterns.number(a.get("next_wave"), -1, -1, 19)), "tired": bool(a.get("tired", false)), "slow": int(Patterns.number(a.get("slow"), 0, 0, 3)), "skip_wave": bool(a.get("skip_wave", false))})
		var lines: Dictionary = e.get("lines", {}) if e.get("lines") is Dictionary else {}
		for key in ["intro", "check", "hurt", "spared", "won"]:
			if lines.get(key) is String:
				ce.lines[key] = str(lines[key]).left(240)
		ce.lines["idle"] = []
		if lines.get("idle") is Array:
			for line in lines.idle.slice(0, 12):
				if line is String:
					ce.lines.idle.append(line.left(160))
		var waves: Array = e.get("waves", []) if e.get("waves") is Array else []
		for w in waves.slice(0, 20):
			if w is Dictionary:
				ce.waves.append(Patterns.clean_wave(w))
		if (ce.waves as Array).is_empty():
			ce.waves = [Patterns.template("rain")]
		if e.get("phases") is Array:
			for pdef in e.phases.slice(0, 4):
				if pdef is Dictionary:
					ce.phases.append({"name": str(pdef.get("name", "Next phase")).left(48),
						"mercy": Patterns.number(pdef.get("mercy"), 1, 0.05, 1), "hp": Patterns.number(pdef.get("hp"), 0, 0, 0.95),
						"wave": int(Patterns.number(pdef.get("wave"), 0, 0, ce.waves.size() - 1)), "line": str(pdef.get("line", "")).left(160)})
		out.enemies.append(ce)
		if (out.enemies as Array).size() >= 3:
			break
	return out


static func save(b: Dictionary) -> String:
	last_error = ""
	var c := clean(b)
	if c.is_empty() or (c.enemies as Array).is_empty():
		last_error = "This battle needs an enemy and a supported version."
		return ""
	if str(c.id) != "" and not safe_id(str(c.id)):
		last_error = "That battle ID isn't safe. Save a new copy."
		return ""
	if str(c.id) == "":
		var taken := PackedStringArray(list().map(func(x): return str(x.id)))
		var base := str(c.name).to_lower().replace(" ", "_").left(24)
		var id := ""
		for ch in base:
			if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
				id += ch
		if id == "":
			id = "battle"
		var n := 2
		var cand := id
		while cand in taken:
			cand = "%s_%d" % [id, n]
			n += 1
		c.id = cand
	c["made"] = Time.get_datetime_string_from_system()
	JsonUtil.ensure_dir(battles_dir())
	if not JsonUtil.write_json(battles_dir().path_join(str(c.id) + ".json"), c):
		last_error = "Couldn't save the battle. Check the save folder and free space."
		return ""
	return str(c.id)


static func load_battle(id: String) -> Dictionary:
	if not safe_id(id):
		return {}
	var d: Variant = JsonUtil.read_json(battles_dir().path_join(id + ".json"), {})
	if not d is Dictionary or d.is_empty():
		return {}
	d["id"] = id # The filename owns identity; data cannot redirect a later save.
	return clean(d)


static func list() -> Array:
	var out: Array = []
	for f in JsonUtil.list_files(battles_dir(), ["json"]):
		var b := load_battle(str(f).get_basename())
		if not b.is_empty():
			out.append(b)
	return out


static func delete(id: String) -> void:
	if safe_id(id):
		DirAccess.remove_absolute(battles_dir().path_join(id + ".json"))


static func safe_id(id: String) -> bool:
	if id.is_empty() or id.length() > 80:
		return false
	for ch in id:
		if not ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in ["_", "-"]):
			return false
	return true
