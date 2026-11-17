extends "res://tests/test_case.gd"
## Phase 18: the variety pack, with the AI off (Mock) and the Time Machine.
## Acceptance: a 7-day simulated run where no two days match (Moments and
## letters), two quests completed end to end by real changes in the world, 20
## Dream Doors giving valid, different rooms. Plus: the Moments deck (60+,
## deterministic, no repeats in 14 days, celebrations, Memory Echo off by
## default, your own Moments), visitors (arrive, invite, wander on), found
## objects, the Sky, routines, While You Were Away (never a guilt trip), the
## Almanac and shard memories, and the director in the real game.

const Clock := preload("res://scripts/variety/clock.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const Moments := preload("res://scripts/variety/moments.gd")
const Deck := preload("res://scripts/variety/moments_deck.gd")
const Visitors := preload("res://scripts/variety/visitors.gd")
const Quests := preload("res://scripts/variety/quests.gd")
const Away := preload("res://scripts/variety/away.gd")
const Routines := preload("res://scripts/variety/routines.gd")
const DreamDoors := preload("res://scripts/variety/dream_doors.gd")
const Almanac := preload("res://scripts/variety/almanac.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const PlatformSave := preload("res://scripts/platform/platform_save.gd")


func _world() -> void:
	Clock.reset()
	fresh_save_root()
	StarterContent.create_world("Variety", "Sam")
	StarterContent.create_mochi()
	StarterContent.create_mochi("Pip", Color("#ffd166"))
	GameState.load_world()
	GameState.add_dream("learn to play the guitar")
	AIClient.configure({"preset": "mock"})


func _day_signature(t: Dictionary, notes: Array) -> String:
	return "|".join(t.get("moments", []).map(func(m): return str(m.id) + ":" + str(m.text))) + "#" + "|".join(notes.map(func(n): return str(n.text)))


func test_seven_days_never_the_same() -> void:
	_world()
	check(AIClient.is_mock(), "the AI is off (Mock)")
	Away.mark_seen(Clock.now())
	var seen := {}
	var ids_by_day: Array = []
	for day in 7:
		Clock.advance(1.0)
		var away := Away.run()
		var t := Moments.today()
		check(t.moments.size() >= 1 and t.moments.size() <= 3, "day %d: 1-3 Moments (%d)" % [day + 1, t.moments.size()])
		check(float(away.hours) >= 23.0, "day %d: a day away" % (day + 1))
		var sig := _day_signature(t, away.notes)
		check(not seen.has(sig), "day %d differs from every other day" % (day + 1))
		seen[sig] = true
		ids_by_day.append(t.moments.map(func(m): return str(m.id)))
		for m in t.moments:
			check(not str(m.text).contains("{"), "placeholders filled: " + str(m.text))
	var all_ids := {}
	for ids in ids_by_day:
		for id in ids:
			check(not all_ids.has(id), "no Moment repeats within the week (%s)" % id)
			all_ids[id] = true
	var letters := 0
	for m in GameState.journal.get("moments", []):
		if bool(m.get("away", false)):
			letters += 1
	check(letters >= 3, "letters, diary notes and gifts waited over the week (%d), kept in the Memory Book" % letters)
	Clock.reset()


func test_moments_deck_rules() -> void:
	_world()
	check(Deck.entries().size() >= 60, "60+ built-in Moments (%d)" % Deck.entries().size())
	for k in Deck.KINDS:
		check(Deck.entries().any(func(e): return str(e.kind) == k), "the deck has %s Moments" % k)
	var ctx := Moments.context()
	var a := Moments.draw(ctx, "2026-11-03", [])
	var b := Moments.draw(ctx, "2026-11-03", [])
	eq(a.map(func(m): return m.id), b.map(func(m): return m.id), "the same day draws the same Moments")
	var kinds := a.map(func(m): return str(m.kind))
	for k in kinds:
		eq(kinds.count(k), 1, "never two of a kind in a day")
	check(not Deck.entries().filter(func(e): return str(e.kind) == "echo").any(func(e): return a.any(func(m): return str(m.id) == str(e.id))), "Memory Echo is off by default")
	check(not bool(VarietySave.data().echo), "(echo setting off)")
	# A holiday brings a Celebration.
	ctx["celebration"] = "Halloween"
	var h := Moments.draw(ctx, "2026-10-31", [])
	check(h.any(func(m): return str(m.kind) == "celebration" and str(m.text).contains("Halloween")), "a special day always has its Celebration")
	# Your own Moments join the deck (drawn when they're the only ones left of a kind).
	var mine := Moments.add_custom("rumor", "{character} says the moon winked at {you}.")
	check(not mine.is_empty() and Moments.all_entries(VarietySave.data().custom).any(func(e): return str(e.id) == str(mine.id)), "your own Moment is in the deck")
	# Memory Echo when you switch it on (and have memories).
	GameState.add_moment("Rainy tea", "We drank tea and watched the rain for an hour.", "", "manual")
	VarietySave.data()["echo"] = true
	var ectx := Moments.context()
	var found_echo := false
	for i in 40:
		var day := "2027-01-%02d" % (i % 28 + 1)
		if Moments.draw(ectx, day + str(i), []).any(func(m): return str(m.kind) == "echo"):
			found_echo = true
			break
	check(found_echo, "with Memory Echo on, your own past turns up")


func test_visitors_found_objects_and_sky() -> void:
	_world()
	var room := GameState.current_room_id
	var visitor := {"id": "v_tea_wanderer", "kind": "visitor", "extra": {"name": "Oro", "look": "cozy", "about": "Brews tea."}, "room": room}
	var vid := Visitors.arrive(visitor, Clock.today())
	check(vid != "" and bool(GameState.get_character(vid).get("visitor", false)), "a visitor arrived")
	check(GameState.characters_in_room(room).any(func(c): return str(c.id) == vid), "in the room for today")
	check(FileAccess.file_exists(SaveManager.character_dir(vid).path_join("expressions/neutral.png")), "with a face (doll maker)")
	# The next day they wander on, unless invited.
	var other := Visitors.arrive({"id": "v2", "extra": {"name": "Pim", "look": "sleepy"}, "room": room}, Clock.today())
	check(Visitors.invite(other), "inviting one to stay")
	Clock.advance(1.0)
	var gone := Visitors.farewell_old(Clock.today())
	check(gone.has(vid) and GameState.get_character(vid).is_empty(), "the uninvited visitor wandered on")
	check(not GameState.get_character(other).is_empty() and not bool(GameState.get_character(other).get("visitor", true)), "the invited one stayed")
	Clock.reset()
	# A found object waits as a pickup.
	var o := Visitors.place_found({"id": "f_moon_pebble", "extra": {"item": "Moon pebble", "color": "#c9b6ff"}, "room": room, "text": "A pebble."})
	check(not o.is_empty() and str(o.type) == "pickup", "the found object is a pickup in the room")
	check(SaveManager.load_room(room).objects.any(func(x): return str(x.get("moment", "")) == "f_moon_pebble"), "saved in the room")


func test_routines_move_residents() -> void:
	_world()
	var rooms := SaveManager.list_rooms()
	check(rooms.size() >= 2, "a world with a few rooms")
	var id: String = GameState.characters.keys()[0]
	var c := GameState.get_character(id)
	var home := str(c.home_room)
	var other := str(Array(rooms).filter(func(r): return r != home)[0])
	Routines.set_entry(c, "evening", other, "watering the plants")
	GameState.save_character(c)
	eq(Routines.room_now(c, "morning"), home, "mornings at home (no routine entry)")
	eq(Routines.room_now(c, "evening"), other, "evenings where the routine says")
	eq(Routines.activity_now(c, "evening"), "watering the plants")
	eq(Clock.part_of_day(7), "morning")
	eq(Clock.part_of_day(19), "evening")
	eq(Clock.part_of_day(23), "night")
	var part := Clock.part_of_day()
	var expected := other if part == "evening" else home
	check(GameState.characters_in_room(expected).any(func(x): return str(x.id) == id), "characters_in_room follows the routine right now (%s)" % part)


func test_away_is_warm_and_capped() -> void:
	_world()
	Away.mark_seen(Clock.now())
	Clock.advance(2.0 / 24.0)
	var short := Away.run()
	check((short.notes as Array).is_empty(), "under 3 hours: nothing special")
	Clock.advance(30.0)
	var c: Dictionary = GameState.characters.values()[0]
	c.mood["loneliness"] = 0.2
	GameState.save_character(c)
	var long := Away.run()
	check(float(long.days) <= 7.0, "a month away counts as at most 7 days (%.1f)" % float(long.days))
	check((long.notes as Array).size() >= 1 and (long.notes as Array).size() <= 3, "1-3 notes wait (%d)" % (long.notes as Array).size())
	for n in long.notes:
		var t := str(n.text).to_lower()
		check(not t.contains("lonely") and not t.contains("where were you") and not t.contains("missed you so"), "warm, no guilt: " + str(n.text))
	for c2 in GameState.characters.values():
		check(float(c2.mood.loneliness) <= 0.45, "being away never makes anyone more than gently miss you (%.2f)" % float(c2.mood.loneliness))
	var room := SaveManager.load_room(GameState.current_room_id)
	check(room.objects.filter(func(o): return str(o.get("type", "")) == "pickup").size() >= (long.notes as Array).size(), "the notes wait as pickups")
	Clock.reset()


## With an AI set up (a tiny fake one on 127.0.0.1 here), the letters are
## rewritten in one batched request, cached, and never asked for twice.
func test_away_letters_one_batched_ai_call() -> void:
	_world()
	Away.mark_seen(Clock.now())
	Clock.advance(30.0)
	var result := Away.run()
	var notes: Array = result.notes
	check(notes.size() >= 1, "notes to rewrite (%d)" % notes.size())
	var texts: Array = []
	for i in notes.size():
		texts.append("Dear Sam, the garden says hello. (%d)" % i)
	# A fake OpenAI-style endpoint on 127.0.0.1 only (Phone Link's own server engine).
	var asked := [0]
	var stub: Node = preload("res://scripts/phone/http_server.gd").new()
	tree.root.add_child(stub)
	stub.api_prefix = "/v1/"
	stub.api_handler = func(_req: Dictionary, _ip: String) -> PackedByteArray:
		asked[0] += 1
		return preload("res://scripts/phone/http_util.gd").json_response(200, {"choices": [{"message": {"role": "assistant", "content": JSON.stringify({"notes": texts})}}]})
	listen_on_free_port(func(p: int) -> String: return stub.start(p, "127.0.0.1"), "the fake AI")
	AIClient.configure({"preset": "custom", "base_url": "http://127.0.0.1:%d/v1" % stub.port, "model": "x", "timeout_s": 5})
	check(not AIClient.is_mock(), "(an AI is set up)")
	var ok: bool = await Away.enrich_with_ai(result)
	check(ok, "the AI rewrote the letters")
	eq(asked[0], 1, "in one batched request")
	for i in notes.size():
		eq(str(preload("res://scripts/items/items.gd").load_item(str(notes[i].item)).get("flavor", "")), str(texts[i]), "the pickup reads the new letter")
		var m: Array = GameState.journal.moments.filter(func(x): return str(x.get("id", "")) == str(notes[i].get("moment", "")))
		check(m.size() == 1 and str(m[0].text) == str(texts[i]), "and so does the Memory Book")
	check((VarietySave.data().ai_letters as Dictionary).has(str(result.seed)), "cached with the world")
	var again: bool = await Away.enrich_with_ai(result)
	check(not again, "asked once only")
	eq(asked[0], 1, "no second request")
	AIClient.configure({"preset": "mock"})
	stub.stop()
	stub.queue_free()
	Clock.reset()


func test_two_quests_end_to_end() -> void:
	_world()
	var room := GameState.current_room_id
	var who: String = GameState.characters.keys()[0]
	# 1. Build: add three things to a room (real edits, saved).
	var q1 := Quests.add(Quests.make("build", {"room": room, "n": 3}, who, "test"))
	eq(Quests.progress(q1), 0, "starts at 0")
	var r := SaveManager.load_room(room)
	for x in [2, 3, 4]:
		RoomEditor.add_tile(r, x, 1, "cube", "#8a7bc8")
	SaveManager.save_room(r)
	var done1 := Quests.check_all()
	check(done1.any(func(q): return str(q.id) == str(q1.id)), "adding 3 blocks finished the build quest")
	# The reward is picked by the quest's id: an item in the bag, or (1 in 9) the Dreamlight tile set.
	var rw: Dictionary = done1[0].get("reward", {})
	var in_bag := str(rw.get("item", "")) != "" and Inventory.count(str(rw.item)) == 1
	var tile_set := str(rw.get("tileset", "")) != "" and preload("res://scripts/world/tilesets.gd").exists(str(rw.tileset))
	check(in_bag or tile_set, "a cosmetic reward (%s, %s)" % [str(rw.get("name", "")), "in the bag" if in_bag else ("a tile set" if tile_set else "missing")])
	# 2. Talk: tell a friend about your dream (a real chat message, through the director's listener).
	var q2 := Quests.add(Quests.make("talk", {"character": who, "topic": "dream", "topic_text": "your dream", "words": ["guitar"]}, who, "test"))
	Quests.on_chat(who, "I had a long day")
	check(Quests.active().any(func(q): return str(q.id) == str(q2.id)), "an unrelated message doesn't count")
	var finished := Quests.on_chat(who, "I practiced the guitar for ten minutes!")
	check(finished.any(func(q): return str(q.id) == str(q2.id)), "telling them about the guitar finished it")
	eq(Quests.done().size(), 2, "two quests done")
	eq(int(VarietySave.data().almanac.get("quests_done", 0)), 2, "in the Almanac")
	# The others: visit, hidden spot, shards, item, letting go.
	var q3 := Quests.add(Quests.make("hidden", {"room": room, "x": 5, "z": 5}, who))
	check(Quests.hint(q3).begins_with("Somewhere in the"), "a hint for the hidden spot")
	check(Quests.on_step(room, Vector2i(5, 5)).size() == 1, "stepping on the hidden spot finds it")
	var q4 := Quests.add(Quests.make("shards", {"n": 1}, who))
	PlatformSave.take_shard(room, "s1")
	check(Quests.check_all().any(func(q): return str(q.id) == str(q4.id)), "a Memory Shard counts")
	var q5 := Quests.add(Quests.make("create_item", {}, who))
	var it := preload("res://scripts/items/items.gd").defaults("keepsake")
	it["name"] = "My drawing"
	preload("res://scripts/items/items.gd").save_item(it)
	check(Quests.check_all().any(func(q): return str(q.id) == str(q5.id)), "making an item counts")
	var q6 := Quests.add(Quests.make("visit", {"room": room}, who))
	Quests.let_go(str(q6.id))
	check(not Quests.active().any(func(q): return str(q.id) == str(q6.id)) and (Quests.q().let_go as Array).size() == 1, "letting a quest go: no failure, no penalty")


func test_dream_quest_offers() -> void:
	_world()
	var made := Quests.offer_dream_quests("2026-11-05")
	check(made.size() >= 1 and Quests.active().size() <= Quests.MAX_OPEN, "dream quests offered (%d), at most 3 open" % made.size())
	check(Quests.offer_dream_quests("2026-11-05").is_empty(), "once per day")
	check(made.all(func(q): return str(q.get("dream", "")).contains("guitar")), "shaped by your dream (the guitar)")
	# Real life steps: at most 1 in 4 offers, and never when switched off.
	VarietySave.data()["real_life"] = false
	GameState.current_room_id = "home"
	for d in range(6, 20):
		for q in Quests.active().duplicate():
			Quests.let_go(str(q.id))
		for q in Quests.offer_dream_quests("2026-11-%02d" % d):
			if str(q.template) == "visit":
				check(str(q.params.room) != "home", "a visit quest sends you somewhere else, not the room you're in")
	check(not Quests.active().any(func(q): return str(q.template) == "real_life"), "no real-life steps when switched off")
	var v := VarietySave.data()
	check(int(v.offers_real_life) * 4 <= int(v.offers_total) + 3, "real-life steps stay rare (%d of %d)" % [int(v.offers_real_life), int(v.offers_total)])


func test_twenty_dream_doors_valid_and_different() -> void:
	_world()
	TemplateFactory.ensure_builtin()
	var seen := {}
	var words := ["guitar", "night", "stars"]
	for i in 20:
		var r := DreamDoors.generate(1000 + i * 7919, words, i % 2 == 0, "home", "dream_t%d" % i)
		var v := DreamDoors.validate(r)
		check(bool(v.ok), "door %d: a valid room (%s)" % [i, ", ".join(v.problems)])
		var sig := JSON.stringify([r.size, r.get("tiles", []), r.get("objects", []).map(func(o): return [o.type, o.pos]), r.floor, r.dream_set])
		check(not seen.has(sig), "door %d: different from the others" % i)
		seen[sig] = true
		check(r.objects.any(func(o): return str(o.get("type", "")) == "door" and str(o.get("door_target", "")) == "home"), "door %d: a way back" % i)
	# In a world: opening files it in the archive (10 kept), Keep makes it a normal room.
	var door := RoomEditor.add_object(SaveManager.load_room("home"), 2, 2, "dream_door")
	var ids: Array = []
	for i in 12:
		ids.append(DreamDoors.open(door, "home"))
	eq((VarietySave.data().dream_archive as Array).size(), 10, "the Dream Archive keeps the last 10")
	check(not SaveManager.room_exists(str(ids[0])) and SaveManager.room_exists(str(ids[11])), "older dreams fade away")
	check(DreamDoors.keep(str(ids[11]), "My dream") and not bool(SaveManager.load_room(str(ids[11])).get("dream", true)), "Keep this room: a normal room")
	eq(str(SaveManager.load_room(str(ids[11])).name), "My dream")
	eq(int(Almanac.counts().doors), 12, "the Almanac counts the doors")


func test_almanac_and_shard_memories() -> void:
	_world()
	var c := Almanac.counts()
	check(int(c.rooms) >= 1 and int(c.friends) == 2, "rooms and friends counted (%s)" % str(c))
	check(Almanac.titles({"rooms": 3, "shards": 1}).size() >= 2, "titles at milestones")
	Almanac.wear("Room Maker")
	eq(Almanac.worn(), "Room Maker", "a title to wear")
	Almanac.on_shard({"id": "s9", "memory": "The day we built the garden."}, "home")
	check(GameState.journal.moments.any(func(m): return str(m.text) == "The day we built the garden."), "a shard's memory is in the Memory Book")
	check(Almanac.shard_memory({"id": "x"}) != "", "a suggested memory when the shard has none")


## [GOALS] "Coming up": the nearest titles, one per count; a new title is said once; an old world
## isn't greeted with everything it already had; a quest's gift is known before the work.
func test_coming_up_titles_and_quest_gifts() -> void:
	_world()
	var near := Almanac.coming_up({"rooms": 2, "quests": 9, "moments": 2, "shards": 10}, 3)
	eq(near.map(func(n): return str(n.name)), ["Dream Weaver", "Room Maker", "Door Opener"], "fewest steps left first; between equals, the one further along, then by name")
	eq([int(near[1].have), int(near[1].need)], [2, 3])
	check(str(near[1].how) != "" and str(near[1].label) == "Places made", "each says what moves it")
	check(not near.any(func(n): return str(n.name) == "Shard Seeker" or str(n.name) == "Memory Keeper"), "a title already earned is never coming up")
	var rooms_only := Almanac.coming_up({"rooms": 4}, 20).filter(func(n): return str(n.from) == "rooms")
	eq(rooms_only.map(func(n): return str(n.name)), ["Builder of Many Rooms"], "one per count: its next title, not every later one")
	var everything := {}
	for t in Almanac.TITLES:
		everything[str(t[0])] = maxi(int(everything.get(str(t[0]), 0)), int(t[1]))
	eq(Almanac.coming_up(everything).size(), 0, "nothing is coming up when every title is earned")
	# A world from before this existed (no record of seen titles) that already has some.
	VarietySave.data().almanac.erase("titles_seen")
	eq(Array(Almanac.new_titles({"rooms": 3, "quests": 1})), [], "an old world's titles aren't announced all at once")
	eq(Array(Almanac.new_titles({"rooms": 3, "quests": 1})), [], "and stay quiet")
	eq(Array(Almanac.new_titles({"rooms": 3, "quests": 1, "items": 1})), ["Maker"], "a title earned after that is said")
	eq(Array(Almanac.new_titles({"rooms": 3, "quests": 1, "items": 1})), [], "once")
	GameState.load_world()
	check("Maker" in VarietySave.data().almanac.titles_seen, "what was said is remembered in the world's save")
	# The quest card's promise is what the quest gives.
	var quest := Quests.make("visit", {"room": "home"}, "pip", "For you.")
	var promised := Quests.reward_preview(quest)
	var bag_before := Inventory.total_items()
	Quests.reward_preview(quest)
	eq(Inventory.total_items(), bag_before, "looking at the gift doesn't hand it over")
	eq(str(Quests.give_reward(quest).kind), str(promised.kind), "the gift is the one the card named")
	check(str(promised.words) != "" and str(promised.name) != "", "named in words")
	# The panels build with it (and without it).
	var almanac_panel: Control = load("res://scripts/ui/almanac_panel.gd").new()
	tree.root.add_child(almanac_panel)
	await frames(2)
	check(almanac_panel.find_children("ComingUp_*", "", true, false).size() >= 1, "the Almanac shows what is coming up")
	almanac_panel.queue_free()
	await frames(1)


func test_director_in_the_game() -> void:
	_world()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	VarietySave.data()["last_seen"] = Clock.now() - 26 * 3600.0
	GameState.save_world()
	main.start_game()
	await frames(8)
	var g: Node = main.game
	check(g.variety != null and not g.variety.today.is_empty(), "today's Moments are drawn on opening the world")
	check(bool(g.variety.today.applied) and bool(g.variety.today.shown), "applied and shown")
	check(g.variety.card != null and is_instance_valid(g.variety.card), "the Today card is on screen")
	check(float(g.variety.away.get("hours", 0)) >= 25.0, "While You Were Away ran (%.0f h)" % float(g.variety.away.get("hours", 0)))
	check(Quests.active().size() >= 1, "quests are offered")
	# The Sky moment (if any) decides the weather.
	var sky: String = g.variety.sky_today()
	if sky != "" and sky != "clear":
		eq(g.weather.current, sky, "the Sky Moment's weather")
	main.queue_free()
	await frames(3)


func test_tile_set_reward_and_sky_light() -> void:
	_world()
	var id := Quests.dreamlight_set()
	check(id != "" and preload("res://scripts/world/tilesets.gd").exists(id), "a reward tile set appears in the world")
	eq((preload("res://scripts/world/tilesets.gd").load_set(id).tiles as Array).size(), 4, "with four tiles")
	eq(Quests.dreamlight_set(), id, "made once")
	check(bool(preload("res://scripts/world/tilesets.gd").info(id, preload("res://scripts/world/tilesets.gd").load_set(id).tiles[3].id).get("slippery", false)), "its moon dust is slippery (Platform Mode)")

