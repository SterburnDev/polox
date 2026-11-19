extends RefCounted
## While You Were Away: opening a world after 3+ hours, the time in between is
## lived (up to 7 days): residents followed their routines, moods settled, and
## 0-3 letters, diary notes or small gifts wait as pickups, in their voices,
## also kept in the Memory Book. Warm, never a guilt trip. One batched AI call
## for all of them when an AI is set up (cached); built-in templates otherwise.

const Clock := preload("res://scripts/variety/clock.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const MoodSim := preload("res://scripts/characters/mood_sim.gd")
const Items := preload("res://scripts/items/items.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const Routines := preload("res://scripts/variety/routines.gd")

const MIN_HOURS := 3.0
const MAX_DAYS := 7.0

const LETTERS := [
	"Dear {you}, I kept the kettle warm in case you came by. No rush, ever. ~{name}",
	"{you}! I found a pretty {like} today and thought of you. It's yours when you're here. ~{name}",
	"Hi {you}. The {room} was cozy today. I hope your day out there was kind to you. ~{name}",
	"Dear {you}, nothing big happened, and that was nice. Just wanted to say hello. ~{name}",
	"{you}, I practiced being brave today. Small brave, but still! Tell me about your week? ~{name}",
	"I left a little something by the door for you. Welcome back, whenever you read this. ~{name}",
]
const DIARY := [
	"{name}'s diary: Today I {activity}. It was peaceful. I wonder what {you} is up to.",
	"{name}'s diary: Watched the light move across the {room}. Counted three good things.",
	"{name}'s diary: Tried something new: {like}. Ten out of ten, would {like} again.",
	"{name}'s diary: The world felt quiet and safe today. Saving a story for {you}.",
]
const GIFTS := [["Pressed flower", "flower", "#ffb3c7"], ["Smooth pebble", "pebble", "#c9b6ff"], ["Tiny shell", "shell", "#f3e9d2"], ["Lucky star", "star", "#ffd166"]]


## Hours since you last played this world (0 if never).
static func hours_away(now_unix: float = -1.0) -> float:
	var last := float(VarietySave.data().get("last_seen", 0.0))
	if last <= 0.0:
		return 0.0
	return maxf(0.0, ((now_unix if now_unix >= 0.0 else Clock.now()) - last) / 3600.0)


static func mark_seen(now_unix: float = -1.0) -> void:
	VarietySave.data()["last_seen"] = now_unix if now_unix >= 0.0 else Clock.now()


## The notes for a stretch away: [{character, kind (letter|diary|gift), text, gift?}]. Pure and
## deterministic for (world, when you left, now).
static func notes_for(hours: float, seed_text: String, residents: Array) -> Array:
	if hours < MIN_HOURS or residents.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var days := minf(hours / 24.0, MAX_DAYS)
	var n := clampi(1 + int(days * 0.8) + (rng.randi() % 2), 1, 3) if hours >= 12.0 else rng.randi() % 2
	var out: Array = []
	var used := {}
	for i in n:
		var c: Dictionary = residents[rng.randi() % residents.size()]
		var kind: String = ["letter", "diary", "gift"][rng.randi() % 3]
		var pool: Array = LETTERS if kind == "letter" else (DIARY if kind == "diary" else LETTERS)
		var text := str(pool[rng.randi() % pool.size()])
		var tries := 0
		while used.has(text) and tries < 6:
			text = str(pool[rng.randi() % pool.size()])
			tries += 1
		used[text] = true
		var note := {"character": str(c.get("id", "")), "kind": kind, "text": _fill(text, c, rng)}
		if kind == "gift":
			var g: Array = GIFTS[rng.randi() % GIFTS.size()]
			note["gift"] = {"name": str(g[0]), "shape": str(g[1]), "color": str(g[2])}
			note["text"] = "%s left you a %s. %s" % [str(c.get("name", "A friend")), str(g[0]).to_lower(), note.text]
		out.append(note)
	return out


static func _fill(text: String, c: Dictionary, rng: RandomNumberGenerator) -> String:
	var likes := str(c.get("likes", "")).split(",", false)
	var like := likes[rng.randi() % likes.size()].strip_edges() if likes.size() > 0 else "tea"
	var activity := Routines.activity_now(c)
	var room_id := str(c.get("home_room", "home"))
	var you := GameState.player_name()
	return text.replace("{name}", str(c.get("name", "A friend"))).replace("{you}", you if you != "" else "friend") \
		.replace("{like}", like).replace("{activity}", activity if activity != "" else "had a slow, cozy day") \
		.replace("{room}", str(SaveManager.load_room(room_id).get("name", "room")).to_lower())


## Lives the time away. Returns {hours, days, notes} (notes already placed and kept).
static func run(now_unix: float = -1.0) -> Dictionary:
	var now := now_unix if now_unix >= 0.0 else Clock.now()
	var hours := hours_away(now)
	var v := VarietySave.data()
	var result := {"hours": hours, "days": minf(hours / 24.0, MAX_DAYS), "notes": []}
	if hours < MIN_HOURS:
		mark_seen(now)
		return result
	var residents: Array = GameState.characters.values().filter(func(c): return not bool(c.get("visitor", false)))
	residents.sort_custom(func(a, b): return str(a.id) < str(b.id))
	# Moods settle over the (capped) time, gently; routines put everyone where they'd be now.
	var hour := float(Clock.local(now).hour)
	for c in residents:
		MoodSim.catch_up(c, now, hour)
		GameState.save_character(c)
	var seed_text := "%s|%s|%s" % [str(GameState.world.get("created", "")), str(v.get("last_seen", 0.0)), Clock.date_of(now)]
	var notes := notes_for(hours, seed_text, residents)
	var cached: Variant = v.get("ai_letters", {}).get(seed_text) if v.get("ai_letters") is Dictionary else null
	if cached is Array and (cached as Array).size() == notes.size():
		for i in notes.size():
			notes[i]["text"] = str(cached[i])
	result["notes"] = notes
	result["seed"] = seed_text
	_place(notes)
	VarietySave.count("letters", notes.size())
	mark_seen(now)
	VarietySave.save()
	return result


## The notes wait as pickups in the room you'll start in, and go into the Memory Book.
static func _place(notes: Array) -> void:
	var room_id := GameState.current_room_id
	if room_id == "" or not SaveManager.room_exists(room_id):
		return
	var room := SaveManager.load_room(room_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room_id + str(notes.size()))
	for note in notes:
		var c := GameState.get_character(str(note.character))
		var it := Items.defaults("keepsake")
		var who := str(c.get("name", "A friend"))
		if note.has("gift"):
			it["name"] = str(note.gift.name)
			it["auto_icon"] = {"shape": str(note.gift.shape), "color": str(note.gift.color)}
		else:
			it["name"] = ("Letter from %s" if str(note.kind) == "letter" else "%s's diary page") % who
			it["auto_icon"] = {"shape": "letter" if str(note.kind) == "letter" else "book", "color": "#f3e9d2"}
		it["flavor"] = str(note.text)
		it["tags"] = ["away", str(note.kind)]
		var item_id := Items.save_item(it)
		note["item"] = item_id
		var m := GameState.add_moment(("A letter from %s" if str(note.kind) == "letter" else ("%s's diary" if str(note.kind) == "diary" else "A gift from %s")) % who, str(note.text), str(note.character), "auto", {"away": true})
		note["moment"] = str(m.get("id", ""))
		var w := int(room.get("size", {}).get("w", 12))
		var d := int(room.get("size", {}).get("d", 10))
		for attempt in 40:
			var x := rng.randi_range(1, w - 2)
			var z := rng.randi_range(1, d - 2)
			if RoomEditor.object_at(room, x, z).is_empty() and RoomEditor.stack_top(room, x, z) == 0.0:
				var o := RoomEditor.add_object(room, x, z, "pickup")
				if not o.is_empty():
					o["item"] = item_id
					o["count"] = 1
					o["respawn"] = "once"
					o["taken"] = ""
					break
	SaveManager.save_room(room)


## One batched AI call (when an AI is set up) that rewrites the notes in the residents' own
## voices. Cached per stretch away, so it never runs twice. Returns true if it worked.
static func enrich_with_ai(result: Dictionary) -> bool:
	var notes: Array = result.get("notes", [])
	if notes.is_empty() or AIClient.is_mock():
		return false
	var v := VarietySave.data()
	if v.get("ai_letters") is Dictionary and (v.ai_letters as Dictionary).has(str(result.get("seed", ""))):
		return false   # already written for this stretch away: never asked twice
	var lines: Array = []
	for i in notes.size():
		var c := GameState.get_character(str(notes[i].character))
		lines.append("%d. %s (%s) writes a %s. Their personality: %s. Likes: %s." % [i + 1, c.get("name", "?"), c.get("speech_style", ""), str(notes[i].kind), c.get("personality", ""), c.get("likes", "")])
	var msgs := [
		{"role": "system", "content": "You write tiny, warm notes from residents of a cozy world to the player, who was away for a while. Never guilt-trip, never mention being lonely or waiting. One or two sentences each. Answer JSON: {\"notes\": [\"...\", ...]} in the same order."},
		{"role": "user", "content": "The player is %s. Away about %d hours.\n%s" % [GameState.player_name(), int(result.get("hours", 0)), "\n".join(lines)]},
	]
	var r: Dictionary = await AIClient.chat(msgs, {"json": true, "max_tokens": 400})
	if not bool(r.get("ok", false)):
		return false
	var data: Variant = JSON.parse_string(str(r.get("text", "")))
	var texts: Variant = data.get("notes") if data is Dictionary else null
	if not texts is Array or (texts as Array).size() != notes.size():
		return false
	if not v.get("ai_letters") is Dictionary:
		v["ai_letters"] = {}
	v.ai_letters[str(result.get("seed", ""))] = (texts as Array).map(func(t): return str(t).substr(0, 300))
	var by_id := {}
	for i in notes.size():
		var text := str(texts[i]).substr(0, 300)
		var it := Items.load_item(str(notes[i].get("item", "")))
		if not it.is_empty():
			it["flavor"] = text
			Items.save_item(it)
		by_id[str(notes[i].get("moment", ""))] = text
	for m in GameState.journal.get("moments", []):   # the Memory Book reads the new words too
		if by_id.has(str(m.get("id", ""))):
			m["text"] = ChatLog.redact(str(by_id[str(m.id)]))
	SaveManager.save_journal(GameState.journal)
	GameState.journal_changed.emit()
	VarietySave.save()
	return true
