extends RefCounted
## Daily Moments: each real day the world draws 1-3 Moments from a weighted
## deck (moments_deck.gd + your own), never one seen in the last 14 days,
## never two of a kind in a day, always the same draw for the same day
## (seeded by the world and the date). A special day (a holiday, your
## birthday, or a date you entered) always brings a Celebration. Memory Echo
## (your own past words) only when you switch it on.

const Deck := preload("res://scripts/variety/moments_deck.gd")
const Clock := preload("res://scripts/variety/clock.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const Seasons := preload("res://scripts/world/seasons.gd")

const HISTORY_DAYS := 14


## Built-in entries plus the world's own.
static func all_entries(custom: Array = []) -> Array:
	var out := Deck.entries()
	for c in custom:
		if c is Dictionary and str(c.get("text", "")).strip_edges() != "" and str(c.get("kind", "")) in Deck.KINDS:
			out.append({"id": str(c.get("id", "")), "kind": str(c.kind), "weight": 3.0, "text": str(c.text), "extra": c.get("extra", {}), "builtin": false})
	return out


## Everything the draw needs to know about the world (tests build their own).
static func context() -> Dictionary:
	var ids: Array = GameState.characters.keys().filter(func(id): return not bool(GameState.characters[id].get("visitor", false)))
	ids.sort()
	var names := {}
	for id in ids:
		names[id] = str(GameState.characters[id].get("name", id))
	var rooms: Array = Array(SaveManager.list_rooms())
	rooms.sort()
	var room_names := {}
	for r in rooms:
		room_names[r] = str(SaveManager.load_room(r).get("name", r))
	var dreams: Array = GameState.dream_list().filter(func(d): return str(d.get("status", "")) != "done").map(func(d): return str(d.get("text", "")))
	var v := VarietySave.data()
	return {
		"characters": ids, "names": names, "rooms": rooms, "room_names": room_names, "dreams": dreams,
		"you": GameState.player_name(), "echo": bool(v.get("echo", false)), "echo_texts": echo_texts(),
		"celebration": celebration_today(), "custom": v.get("custom", []),
		"seed": "%s|%s" % [str(GameState.world.get("created", "")), str(GameState.world.get("name", ""))],
		"first_day": str(GameState.world.get("created", "")).substr(0, 10) == Clock.today(),
	}


## A special day today: a holiday or your birthday (seasons.gd), or a date you entered.
static func celebration_today(date: String = "") -> String:
	var d := date if date != "" else Clock.today()
	for c in VarietySave.data().get("celebrations", []):
		if c is Dictionary and str(c.get("date", "")) == d.substr(5):
			return str(c.get("name", "a special day"))
	var parts := d.split("-")
	var h := Seasons.holiday({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2])}) if parts.size() == 3 else {}
	return str(h.get("name", ""))


## Short lines of your own past (Memory Book moments, older than a day) for Memory Echo.
static func echo_texts() -> Array:
	var out: Array = []
	for m in GameState.journal.get("moments", []):
		var t := str(m.get("text", "")).strip_edges()
		if t.length() >= 12 and str(m.get("kind", "")) in ["manual", "auto"]:
			out.append(t.substr(0, 120))
	return out


## The Moments for `date`: [{id, kind, text, extra, character, other, room}]. Pure:
## same world + date + history = same Moments.
static func draw(ctx: Dictionary, date: String, history: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s" % [str(ctx.get("seed", "")), date])
	var recent := {}
	for h in history:
		if h is Dictionary and str(h.get("date", "")) != date:
			for id in h.get("ids", []):
				recent[str(id)] = true
	var chars: Array = ctx.get("characters", [])
	var pool: Array = []
	for e in all_entries(ctx.get("custom", [])):
		if recent.has(str(e.id)):
			continue
		# A brand-new world's first day is just yours: no strangers, finds or asks yet.
		if bool(ctx.get("first_day", false)) and str(e.kind) in ["visitor", "found", "request"]:
			continue
		match str(e.kind):
			"echo":
				if not bool(ctx.get("echo", false)):
					continue
				if str(e.extra.get("source", "")) == "dream" and (ctx.get("dreams", []) as Array).is_empty():
					continue
				if str(e.extra.get("source", "")) != "dream" and (ctx.get("echo_texts", []) as Array).is_empty():
					continue
			"rumor":
				if chars.size() < 2:
					continue
			"request":
				if chars.is_empty():
					continue
		if str(e.text).contains("{dream}") and (ctx.get("dreams", []) as Array).is_empty() and str(e.kind) != "echo":
			continue
		if (str(e.text).contains("{character}") or str(e.text).contains("{other}")) and chars.is_empty():
			continue
		pool.append(e)
	var roll := rng.randf()
	var n := 1 if roll < 0.5 else (2 if roll < 0.85 else 3)
	var picked: Array = []
	var kinds := {}
	var special := str(ctx.get("celebration", ""))
	if special != "":
		var c := pool.filter(func(e): return str(e.kind) == "celebration" and str(e.text).contains("{celebration}"))
		if not c.is_empty():
			picked.append(c[rng.randi() % c.size()])
			kinds["celebration"] = true
	while picked.size() < n:
		var choices := pool.filter(func(e): return not kinds.has(str(e.kind)) and not picked.has(e))
		if choices.is_empty():
			break
		var total := 0.0
		for e in choices:
			total += float(e.weight)
		var r := rng.randf() * total
		var chosen: Dictionary = choices[0]
		for e in choices:
			r -= float(e.weight)
			if r <= 0.0:
				chosen = e
				break
		picked.append(chosen)
		kinds[str(chosen.kind)] = true
	var out: Array = []
	for e in picked:
		out.append(_fill(e, ctx, rng, date))
	return out


static func _fill(e: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator, date: String) -> Dictionary:
	var chars: Array = ctx.get("characters", [])
	var names: Dictionary = ctx.get("names", {})
	var rooms: Array = ctx.get("rooms", [])
	var room_names: Dictionary = ctx.get("room_names", {})
	var who := str(chars[rng.randi() % chars.size()]) if not chars.is_empty() else ""
	var other := ""
	if chars.size() >= 2:
		var rest := chars.filter(func(c): return str(c) != who)
		other = str(rest[rng.randi() % rest.size()])
	var room := str(rooms[rng.randi() % rooms.size()]) if not rooms.is_empty() else ""
	var dreams: Array = ctx.get("dreams", [])
	var dream := str(dreams[rng.randi() % dreams.size()]) if not dreams.is_empty() else "your dream"
	var echoes: Array = ctx.get("echo_texts", [])
	var echo := str(echoes[rng.randi() % echoes.size()]) if not echoes.is_empty() else ""
	var you := str(ctx.get("you", ""))
	var celebration := str(ctx.get("celebration", ""))
	if celebration == "":
		var parts := date.split("-")
		celebration = "a lovely %s day" % Seasons.season({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2])}) if parts.size() == 3 else "a lovely day"
	var text := str(e.text)
	text = text.replace("{character}", str(names.get(who, "A friend"))).replace("{other}", str(names.get(other, "someone")))
	text = text.replace("{room}", str(room_names.get(room, "your room"))).replace("{dream}", dream)
	text = text.replace("{you}", you if you != "" else "you").replace("{celebration}", celebration).replace("{echo}", echo)
	return {"id": str(e.id), "kind": str(e.kind), "text": text, "extra": (e.extra as Dictionary).duplicate(true), "character": who, "other": other, "room": room}


## Today's Moments for the active world, drawn once per day and remembered.
static func today(force: bool = false) -> Dictionary:
	var v := VarietySave.data()
	var date := Clock.today()
	var t: Dictionary = v.today
	if not force and str(t.get("date", "")) == date:
		return t
	var history: Array = v.history
	var moments := draw(context(), date, history)
	t = {"date": date, "moments": moments, "applied": false, "shown": false}
	v["today"] = t
	history = history.filter(func(h): return h is Dictionary and str(h.get("date", "")) != date)
	history.append({"date": date, "ids": moments.map(func(m): return str(m.id))})
	while history.size() > HISTORY_DAYS:
		history.pop_front()
	v["history"] = history
	VarietySave.count("moments_seen", moments.size())
	VarietySave.save()
	return t


static func add_custom(kind: String, text: String) -> Dictionary:
	if not kind in Deck.KINDS or text.strip_edges() == "":
		return {}
	var c := {"id": "u%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 1000], "kind": kind, "text": text.strip_edges().substr(0, 240)}
	(VarietySave.data().custom as Array).append(c)
	VarietySave.save()
	return c


static func remove_custom(id: String) -> void:
	var v := VarietySave.data()
	v["custom"] = (v.custom as Array).filter(func(c): return str(c.get("id", "")) != id)
	VarietySave.save()
