extends RefCounted
## Dream Doors: a door that opens onto a freshly dreamed small room (seeded),
## put together from the Library: a starter tile set, a little vignette cut
## from a built-in template, maybe one of your stamps, all themed by your
## Dreams board and World Bible (palette, weather). Each has one surprise (a
## hidden friend, a riddle sign, a Memory Shard or a gift) and, when Platform
## Mode is on, a short climb with a pillar. Every room is checked: the way
## back and the surprise are always reachable (flood fill + Room check).
## "Keep this room" makes it a normal room; otherwise the last 10 stay in the
## Dream Archive and older ones fade away.

const Clock := preload("res://scripts/variety/clock.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Templates := preload("res://scripts/world/templates.gd")
const Doll := preload("res://scripts/characters/doll.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const ARCHIVE_MAX := 10
## Starter tile sets: [ground tiles], [standing decor], words that call for them.
const THEMES := {
	"dream_meadow": [["grass", "flowers", "path"], ["bush", "mushroom", "fence"], ["garden", "forest", "flower", "plant", "nature", "tree", "green", "grow", "walk"]],
	"night_sky": [["star_floor", "stars", "moon", "cloud"], ["lantern", "comet"], ["night", "star", "moon", "space", "sky", "dream", "fly", "astronomy", "music"]],
	"dark_castle": [["stone", "cobble", "moss", "rune"], ["torch", "banner", "gate"], ["castle", "old", "dragon", "knight", "history", "magic", "brave", "adventure"]],
	"cozy_home": [["wood_floor", "checker", "rug"], ["bookshelf", "lamp", "curtain"], ["home", "cozy", "tea", "book", "read", "cook", "family", "write", "cat"]],
}
const PALETTES := [["#2a2445", "#120e24"], ["#3f7a5a", "#15132d"], ["#5b4b8a", "#1b1538"], ["#8b5e3c", "#2e1f33"], ["#2e86de", "#0b0818"], ["#9c6b43", "#1d1736"]]
const WEATHERS: PackedStringArray = ["none", "fireflies", "petals", "snow", "rain", "aurora"]
const SURPRISES: PackedStringArray = ["friend", "riddle", "shard", "gift"]
const RIDDLES := [
	["I have keys but open no doors. What am I?", "A piano."],
	["The more you take, the more you leave behind. What are they?", "Footsteps."],
	["What has to be broken before you can use it?", "An egg."],
	["I'm light as a feather, yet the strongest can't hold me for long. What am I?", "Breath."],
	["What gets bigger the more you take away?", "A hole."],
	["What belongs to you, but others use it more than you do?", "Your name."],
]


## Words from your dreams and World Bible that steer the theme.
static func theme_words() -> Array:
	var text := ""
	for d in GameState.dream_list():
		text += " " + str(d.get("text", ""))
	var bible: Dictionary = GameState.world.get("world_bible", {})
	for k in bible:
		text += " " + str(bible[k])
	var out: Array = []
	for w in text.to_lower().replace(",", " ").replace(".", " ").split(" ", false):
		if w.length() >= 3:
			out.append(w)
	return out


## The tile set whose words match yours best (ties broken by the seed).
static func pick_set(words: Array, rng: RandomNumberGenerator) -> String:
	var best := ""
	var best_score := -1.0
	for s in THEMES:
		var score := rng.randf() * 0.5
		for w in words:
			for k in THEMES[s][2]:
				if str(w).contains(str(k)):
					score += 1.0
		if score > best_score:
			best_score = score
			best = s
	return best


## A dreamed room (pure apart from reading the Library). `back_room` = where its door leads.
static func generate(seed_value: int, words: Array, platform_on: bool, back_room: String, room_id: String = "dream") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var set_id := pick_set(words, rng)
	var theme: Array = THEMES[set_id]
	var r := Defaults.room(room_id, "A dream")
	var w := rng.randi_range(10, 14)
	var d := rng.randi_range(8, 12)
	r["size"] = {"w": w, "d": d, "h": 3}
	var pal: Array = PALETTES[rng.randi() % PALETTES.size()]
	r["floor"] = {"color": str(pal[0]), "texture": ""}
	r["sky"] = {"color": str(pal[1]), "texture": ""}
	r["ambiance"] = {"weather": WEATHERS[rng.randi() % WEATHERS.size()]}
	r["dream"] = true
	r["dream_seed"] = seed_value
	r["dream_set"] = set_id
	var grounds: Array = theme[0]
	var main_tile := str(grounds[rng.randi() % grounds.size()])
	var alt_tile := str(grounds[rng.randi() % grounds.size()])
	for x in w:
		for z in d:
			RoomOps.set_ground(r, x, z, set_id, alt_tile if rng.randf() < 0.18 else main_tile)
	var spawn := Vector2i(1, d / 2)
	r["spawn"] = [spawn.x, spawn.y]
	var door := RoomEditor.add_object(r, 0, spawn.y, "door", "", "", 1)
	door["door_target"] = back_room
	door["interaction_text"] = "Back to the waking world"
	# A vignette cut from a built-in template, then maybe one of your stamps.
	_vignette(r, rng)
	_stamp(r, rng)
	# Standing decor from the tile set.
	var decor: Array = theme[1]
	for i in rng.randi_range(3, 7):
		var c := Vector2i(rng.randi_range(2, w - 2), rng.randi_range(1, d - 2))
		if c.distance_to(spawn) > 1.5 and RoomEditor.object_at(r, c.x, c.y).is_empty():
			RoomOps.add_sprite(r, c.x, 0, c.y, set_id, str(decor[rng.randi() % decor.size()]), "standing", rng.randf() < 0.4)
	# The surprise, and a short climb when Platform Mode is on.
	var surprise := SURPRISES[rng.randi() % SURPRISES.size()]
	r["dream_surprise"] = surprise
	var spot := Vector2i(w - 2, rng.randi_range(1, d - 2))
	if platform_on:
		_climb(r, rng, spot)
	else:
		_place_surprise(r, surprise, spot, rng)
	r["name"] = "A dream of %s" % {"dream_meadow": "a meadow", "night_sky": "the night sky", "dark_castle": "an old castle", "cozy_home": "a cozy home"}.get(set_id, "somewhere")
	_ensure_reachable(r, spawn)
	return r


static func _vignette(r: Dictionary, rng: RandomNumberGenerator) -> void:
	var ids := ["garden", "cave", "cozy_room", "night_rooftop", "dream_island"]
	var t := Templates.load_template(str(ids[rng.randi() % ids.size()]))
	var rooms: Dictionary = t.get("rooms", {})
	if rooms.is_empty():
		return
	var src: Dictionary = rooms.values()[0]
	RoomEditor.sanitize(src)
	var sw := int(src.get("size", {}).get("w", 8))
	var sd := int(src.get("size", {}).get("d", 8))
	var a := Vector2i(rng.randi_range(0, maxi(0, sw - 4)), rng.randi_range(0, maxi(0, sd - 4)))
	var cut := RoomOps.copy_region(src, a, a + Vector2i(3, 3))
	cut["cells"] = (cut.cells as Array).filter(func(e): return str(e.get("type", "")) != "ground")   # keep our floor
	cut["objects"] = (cut.objects as Array).filter(func(o): return not str(o.get("type", "")) in ["door", "pickup"])
	var w := int(r.size.w)
	var d := int(r.size.d)
	RoomOps.paste(r, cut, Vector2i(rng.randi_range(3, maxi(3, w - 6)), rng.randi_range(1, maxi(1, d - 5))), "merge")


static func _stamp(r: Dictionary, rng: RandomNumberGenerator) -> void:
	var stamps := Templates.all("stamps")
	if stamps.is_empty() or rng.randf() < 0.5:
		return
	var s: Dictionary = stamps[rng.randi() % stamps.size()]
	var full := Templates.load_template(str(s.get("id", "")), "stamps")
	var st: Variant = full.get("stamp", full)
	if st is Dictionary and int(st.get("w", 99)) <= int(r.size.w) - 4 and int(st.get("d", 99)) <= int(r.size.d) - 2:
		RoomOps.paste(r, st, Vector2i(3, 1), "merge")


static func _place_surprise(r: Dictionary, surprise: String, at: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var o := {}
	match surprise:
		"friend":
			o = RoomEditor.add_object(r, at.x, at.y, "prop")
			if not o.is_empty():
				var keys := Doll.PRESETS.keys()
				var look := Doll.compose(Doll.preset(str(keys[rng.randi() % keys.size()])), "happy")
				var rel := "textures/dream_friend_%d.png" % (int(r.get("dream_seed", 0)) & 0xffff)
				JsonUtil.ensure_dir(SaveManager.abs_path("textures"))
				look.save_png(SaveManager.abs_path(rel))
				o["texture"] = rel
				o["interaction_text"] = "A dream friend smiles: \"You found me! I'll remember you.\""
		"riddle":
			o = RoomEditor.add_object(r, at.x, at.y, "sign")
			var rd: Array = RIDDLES[rng.randi() % RIDDLES.size()]
			if not o.is_empty():
				o["interaction_text"] = "%s\n\n(Answer, written small on the back: %s)" % [rd[0], rd[1]]
		"shard":
			o = RoomEditor.add_object(r, at.x, at.y, "shard")
			if not o.is_empty():
				o.merge({"elev": 0, "memory": "A dream you walked into once."}, true)
		"gift":
			o = RoomEditor.add_object(r, at.x, at.y, "pickup")
			if not o.is_empty():
				o["item"] = _dream_gift()
				o["count"] = 1
				o["respawn"] = "once"
				o["taken"] = ""
	if not o.is_empty():
		o["dream_surprise"] = true
	return o


static func _dream_gift() -> String:
	const Items := preload("res://scripts/items/items.gd")
	for it in Items.all():
		if "dream_gift" in (it.get("tags", []) as Array):
			return str(it.id)
	var it := Items.defaults("keepsake")
	it["name"] = "Dream marble"
	it["flavor"] = "It holds a tiny swirl of a room you dreamed."
	it["tags"] = ["dream_gift"]
	it["auto_icon"] = {"shape": "gem", "color": "#c58cff"}
	return Items.save_item(it)


## When Platform Mode is on: steps up to the surprise, a pillar near the start.
static func _climb(r: Dictionary, rng: RandomNumberGenerator, top: Vector2i) -> void:
	var start := Vector2i(int(r.spawn[0]) + 2, top.y)
	var colors := ["#8a7bc8", "#c9b6ff", "#7ad6b0", "#ffd166"]
	var h := 0
	var steps: Array = []
	for x in range(start.x, top.x + 1):
		_clear(r, Vector2i(x, top.y))   # the climb's own cells are free of decor
		h = mini(h + (1 if rng.randf() < 0.7 else 0), 3)
		for i in h:
			RoomEditor.add_tile(r, x, top.y, "cube", str(colors[rng.randi() % colors.size()]))
		steps.append(h)
	r["dream_climb"] = {"start": [start.x - 1, start.y], "steps": steps}
	var pillar_cell := Vector2i(int(r.spawn[0]) + 1, clampi(int(r.spawn[1]) + 2, 1, int(r.size.d) - 2))
	var p := RoomEditor.add_object(r, pillar_cell.x, pillar_cell.y, "platform_pillar")
	if not p.is_empty():
		p.merge({"label": "Climb", "color": "#c58cff", "repeat": "repeat", "target_room": "", "target_spawn": []}, true)
	var s := RoomEditor.add_object(r, top.x, top.y, "shard")
	if not s.is_empty():
		s.merge({"elev": 0, "memory": "You climbed a dream to find this.", "dream_surprise": true, "dream_climb": true}, true)


## The way back and the surprise can always be reached: anything blocking a straight
## path from the start is cleared (pieces, solid pictures, plants, signs).
static func _ensure_reachable(r: Dictionary, spawn: Vector2i) -> void:
	for target in _targets(r):
		if _reach(r, spawn).has(target):
			continue
		var c := spawn
		while c != target:
			c += Vector2i(signi(target.x - c.x), 0) if c.x != target.x else Vector2i(0, signi(target.y - c.y))
			_clear(r, c)


static func _targets(r: Dictionary) -> Array:
	var out: Array = []
	# A climb (Platform Mode): its pillar and the foot of the steps are reached on foot; the
	# top is reached by jumping (every step at most one block up, checked in validate()).
	var climb: Variant = r.get("dream_climb")
	if climb is Dictionary:
		out.append(Vector2i(int(climb.start[0]), int(climb.start[1])))
		for o in r.get("objects", []):
			if str(o.get("type", "")) == "platform_pillar":
				out.append(Vector2i(int(o.pos[0]) - 1, int(o.pos[2])))
	for o in r.get("objects", []):
		if bool(o.get("dream_climb", false)):
			continue
		if str(o.get("type", "")) == "door" or bool(o.get("dream_surprise", false)):
			var c := Vector2i(int(o.pos[0]), int(o.pos[2]))
			# A blocking surprise (sign, plant) only needs a neighbour.
			out.append(c if str(o.get("type", "")) in ["door", "pickup", "shard"] else c + Vector2i(-1, 0))
	return out


static func _clear(r: Dictionary, c: Vector2i) -> void:
	r["tiles"] = (r.get("tiles", []) as Array).filter(func(t): return Vector2i(int(t.get("x", -1)), int(t.get("z", -1))) != c)
	r["objects"] = (r.get("objects", []) as Array).filter(func(o): return Vector2i(int(o.pos[0]), int(o.pos[2])) != c or str(o.get("type", "")) == "door" or bool(o.get("dream_surprise", false)))
	for l in TileLayers.all(r):
		if str(l.type) in ["blocks", "foreground"]:
			TileLayers.erase(l, c.x, c.y)


## Cells reachable on foot from `from` (the same rules as walking).
static func _reach(r: Dictionary, from: Vector2i) -> Dictionary:
	var w := int(r.size.w)
	var d := int(r.size.d)
	var seen := {}
	var stack: Array = [from]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if seen.has(p) or p.x < 0 or p.y < 0 or p.x >= w or p.y >= d:
			continue
		if p != from and (RoomOps.blocks_walk(r, p.x, p.y) or str(RoomEditor.object_at(r, p.x, p.y).get("type", "")) in ["sign", "prop", "platform_pillar"]):
			continue
		seen[p] = true
		for dlt in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			stack.append(p + dlt)
	return seen


## Is a generated room good to walk into? {ok, problems}
static func validate(r: Dictionary) -> Dictionary:
	var problems: Array = []
	var spawn := Vector2i(int(r.spawn[0]), int(r.spawn[1]))
	var reach := _reach(r, spawn)
	for t in _targets(r):
		if not reach.has(t):
			problems.append("can't reach %s" % str(t))
	if not r.get("objects", []).any(func(o): return bool(o.get("dream_surprise", false))):
		problems.append("no surprise")
	var climb: Variant = r.get("dream_climb")
	if climb is Dictionary:
		var last := 0
		for h in climb.steps:
			if int(h) - last > 1:
				problems.append("a climb step is too high")
			last = int(h)
	for issue in RoomOps.room_check(r):
		if str(issue.get("severity", "")) == "error":
			problems.append(str(issue.problem))
	return {"ok": problems.is_empty(), "problems": problems}


# --- In a world --------------------------------------------------------------------------------------

## Opens a Dream Door: makes the room, files it in the Dream Archive, returns its id.
static func open(door: Dictionary, from_room: String) -> String:
	var v := VarietySave.data()
	var n := int(v.get("doors_opened", 0)) + 1
	v["doors_opened"] = n
	var seed_value := hash("%s|%s|%s|%d" % [str(GameState.world.get("created", "")), str(door.get("id", "")), Clock.today(), n])
	var taken := SaveManager.list_rooms()
	var id := "dream_%d" % n
	while id in taken:
		id += "b"
	const PlatformSave := preload("res://scripts/platform/platform_save.gd")
	var room := generate(seed_value, theme_words(), PlatformSave.enabled(), from_room, id)
	SaveManager.save_room(room)
	var archive: Array = v.dream_archive
	archive.append({"id": id, "name": str(room.name), "date": Clock.today()})
	while archive.size() > ARCHIVE_MAX:
		var old: Dictionary = archive.pop_front()
		var oldroom := SaveManager.load_room(str(old.id))
		if bool(oldroom.get("dream", false)) and str(old.id) != GameState.current_room_id:
			SaveManager.delete_room(str(old.id))
	VarietySave.count("dream_doors")
	VarietySave.save()
	return id


## "Keep this room": a normal room from now on (out of the archive).
static func keep(room_id: String, new_name: String = "") -> bool:
	var room := SaveManager.load_room(room_id)
	if not bool(room.get("dream", false)):
		return false
	room["dream"] = false
	if new_name.strip_edges() != "":
		room["name"] = new_name.strip_edges()
	SaveManager.save_room(room)
	var v := VarietySave.data()
	v["dream_archive"] = (v.dream_archive as Array).filter(func(a): return str(a.get("id", "")) != room_id)
	VarietySave.count("dreams_kept")
	VarietySave.save()
	return true
