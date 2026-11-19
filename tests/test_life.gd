extends "res://tests/test_case.gd"
## Phase 5: moods on the real clock, lighting, daily events, dreams,
## NPC chatter and the Memory Book.

const MoodSim := preload("res://scripts/characters/mood_sim.gd")
const Daylight := preload("res://scripts/world/daylight.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const Conversation := preload("res://scripts/ai/conversation.gd")

var main: Node


func test_mood_drifts_with_real_time() -> void:
	var c := Defaults.character("m", "M")
	c["last_update_unix"] = 1000.0
	c.mood = {"happiness": 0.9, "energy": 0.9, "loneliness": 0.1}
	MoodSim.catch_up(c, 1000.0 + 10 * 3600.0, 2.0)  # 10 hours later, at 2 am
	check(c.mood.loneliness > 0.1 and c.mood.loneliness <= 0.45, "after 10 hours away: gently missed you, never punished (%.2f)" % c.mood.loneliness)
	check(c.mood.energy < 0.4, "sleepy at 2 am (%.2f)" % c.mood.energy)
	check(c.mood.happiness < 0.9, "happiness settles toward baseline")
	eq(c.last_update_unix, 1000.0 + 36000.0, "timestamp advanced")
	var before: Dictionary = c.mood.duplicate()
	MoodSim.catch_up(c, 1000.0 + 36000.0, 2.0)
	eq(c.mood, before, "no time passed, no change")
	c["last_update_unix"] = 0.0
	MoodSim.catch_up(c, 3600.0 * 24 * 365, 12.0)
	check(c.mood.loneliness <= 1.0 and c.mood.energy >= 0.0, "a year away stays in range")


func test_energy_targets_follow_the_day() -> void:
	check(MoodSim.energy_target(3.0) < 0.3, "night")
	check(MoodSim.energy_target(11.0) > 0.7, "late morning")
	check(MoodSim.energy_target(19.0) > MoodSim.energy_target(23.5), "winding down")


func test_daylight_keyframes() -> void:
	var noon := Daylight.sample(12.0)
	var night := Daylight.sample(2.0)
	check(noon.sun_e > night.sun_e, "brighter at noon")
	check(Daylight.is_night(23.0) and Daylight.is_night(3.0) and not Daylight.is_night(13.0))
	check(Daylight.sample(24.0).sun.is_equal_approx(Daylight.sample(0.0).sun), "wraps around midnight")


func _boot() -> void:
	fresh_save_root()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)


func test_dream_cheer_event_mentions_dream_and_is_logged() -> void:
	await _boot()
	GameState.add_dream("open a tiny bakery")
	var g: Node = main.game
	var events: RefCounted = g.life.events
	await events.dream_cheer("mochi")
	var log := ChatLog.read_all("mochi")
	check(not log.is_empty(), "the cheer is logged")
	check(str(log.back().text).find("open a tiny bakery") != -1, "mentions the dream: " + str(log.back().text))
	eq(log.back().get("kind"), "event")
	check(GameState.journal.moments.any(func(m): return str(m.title).find("cheered on your dream") != -1), "Memory Book entry")
	main.queue_free()
	await frames(1)


func test_second_event_of_the_day_is_a_dream_cheer() -> void:
	await _boot()
	GameState.add_dream("run a 5k")
	var events: RefCounted = main.game.life.events
	events._reset_day()
	events._count = 1
	events._dream_cheers_today.clear()
	await events.run_random()
	check(ChatLog.read_all("mochi").any(func(e): return str(e.text).find("run a 5k") != -1), "dream mentioned")
	main.queue_free()
	await frames(1)


func test_npc_chatter_mock_logs_both_sides() -> void:
	await _boot()
	StarterContent.create_mochi("Bean", Color("#7ad6b0"))
	GameState.load_world()
	main.game.load_room("home")
	await frames(1)
	var chatter: RefCounted = main.game.life.chatter
	await chatter.chat("mochi", "bean")
	var a := ChatLog.read_all("mochi").filter(func(e): return e.get("kind") == "npc_chat")
	var b := ChatLog.read_all("bean").filter(func(e): return e.get("kind") == "npc_chat")
	eq(a.size(), 1, "Mochi's line logged")
	eq(b.size(), 1, "Bean's reply logged")
	eq(a[0].with, "bean")
	eq(ChatLog.recent("mochi", 10).size(), 0, "NPC chatter stays out of the player's chat history")
	main.queue_free()
	await frames(1)


func test_done_dream_gets_celebrated_once_per_friend() -> void:
	await _boot()
	var d := GameState.add_dream("learn to juggle")
	d["status"] = "done"
	GameState.save_dreams()
	var events: RefCounted = main.game.life.events
	var c := GameState.get_character("mochi")
	eq(events.uncelebrated_dream(c), "learn to juggle", "first time: celebrate")
	eq(events.uncelebrated_dream(c), "", "only once")
	check(str(main.game.life.greeting_line(c)) != "", "normal greeting afterwards")
	main.queue_free()
	await frames(1)


func test_first_chat_and_affinity_milestone_moments() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	var c := GameState.get_character(id)
	c.relationship.affinity = 24.5
	GameState.save_character(c)
	await Conversation.new().player_says(id, "hello!")
	var titles: Array = GameState.journal.moments.map(func(m): return str(m.title))
	check(titles.has("First chat with Mochi"), "first chat saved: %s" % str(titles))
	check(titles.any(func(t): return t.find("warming up") != -1), "25 closeness milestone saved")


func test_seasons_holidays_and_weather() -> void:
	const Seasons := preload("res://scripts/world/seasons.gd")
	GameState.world = Defaults.world()
	eq(Seasons.season({"month": 1, "day": 10}), "winter")
	eq(Seasons.season({"month": 4, "day": 10}), "spring")
	eq(Seasons.season({"month": 7, "day": 10}), "summer")
	eq(Seasons.season({"month": 10, "day": 5}), "autumn")
	GameState.world.settings.hemisphere = "south"
	eq(Seasons.season({"month": 7, "day": 10}), "winter", "southern hemisphere flips")
	GameState.world.settings.hemisphere = "north"
	eq(Seasons.holiday({"month": 10, "day": 31}).id, "halloween")
	check(Seasons.holiday({"month": 10, "day": 30}).is_empty(), "ordinary day")
	GameState.world.player.birthday = "07-23"
	GameState.world.player.name = "Sam"
	var bday := Seasons.holiday({"month": 7, "day": 23})
	eq(bday.id, "birthday")
	check(str(bday.greeting).find("Sam") != -1, "birthday greeting uses your name")
	var day := {"year": 2026, "month": 12, "day": 3, "hour": 12}
	eq(Seasons.weather(day), Seasons.weather(day), "same weather all day")
	for m in range(1, 13):
		var w := Seasons.weather({"year": 2026, "month": m, "day": 9, "hour": 12})
		check(w in ["clear", "rain", "snow", "leaves", "petals", "fireflies"], "valid weather %s" % w)
		if m in [1, 2, 12]:
			check(w in ["snow", "clear"], "winter weather is snow or clear")
	check(Seasons.describe({"year": 2026, "month": 10, "day": 31, "hour": 12}).find("Halloween") != -1, "prompt line mentions the holiday")
	GameState.world.settings.seasons = false
	eq(Seasons.describe(), "", "can be switched off")


func test_holiday_greeting_once_per_day() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	var today := Time.get_datetime_dict_from_system()
	GameState.world.player.birthday = "%02d-%02d" % [today.month, today.day]
	var c := GameState.get_character(id)
	check(Conversation.holiday_greeting(c).find("BIRTHDAY") != -1, "birthday greeting today")
	eq(Conversation.holiday_greeting(c), "", "only once per day")
	var ctx := Conversation.new().base_context(c)
	ctx["user_text"] = "hi"
	check(str(preload("res://scripts/ai/prompt_builder.gd").build_messages(ctx)[0].content).find("Today:") != -1, "season/holiday line in the prompt")


## Meeting comes first: on a holiday, a new friend still says their own first hello; the holiday's
## line waits for the next one (it used to take the first hello, and a card's greeting was lost).
func test_a_first_hello_is_never_lost_to_a_holiday() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	var today := Time.get_datetime_dict_from_system()
	GameState.world.player.birthday = "%02d-%02d" % [today.month, today.day]
	var c := GameState.get_character(id)
	c["last_talked"] = ""
	c["greeting"] = "*waves a floury hand* You came!"
	eq(str(Conversation.new().greeting(c)[0].text), "*waves a floury hand* You came!", "their own first hello, birthday or not")
	c["last_talked"] = "2026-10-30T10:00:00"
	check(str(Conversation.new().greeting(c)[0].text).find("BIRTHDAY") != -1, "the birthday hello comes the next time")


func test_gift_tags_and_reactions() -> void:
	const GiftRules := preload("res://scripts/items/gift_rules.gd")
	const Items := preload("res://scripts/items/items.gd")
	var c := {"id": "m", "liked_tags": ["tea", "books", "rainy days"], "disliked_tags": ["loud", "cold"]}
	var tea := Items.defaults("consumable")
	tea["name"] = "Cup of tea"
	tea["tags"] = ["tea", "warm"]
	eq(GiftRules.reaction(c, tea), "like", "one liked tag")
	var book := Items.defaults("keepsake")
	book["name"] = "Rainy storybook"
	book["tags"] = ["book", "rain"]
	eq(GiftRules.reaction(c, book), "love", "book~books and rain~rainy days")
	var alarm := Items.defaults("keepsake")
	alarm["name"] = "Alarm clock"
	alarm["tags"] = ["loud", "metal"]
	eq(GiftRules.reaction(c, alarm), "meh", "disliked")
	var gem := Items.defaults("keepsake")
	gem["name"] = "Gem"
	gem["tags"] = ["tea"]
	gem["rarity"] = "epic"
	eq(GiftRules.reaction(c, gem), "love", "one match + epic rarity")
	eq(GiftRules.reaction({"id": "x"}, tea), "nice", "no tags at all")
	eq(GiftRules.derive_tags("tea, rainy windows and your stories"), ["tea", "rainy windows", "stories"])
	check(GiftRules.tag_match("book", "books") and not GiftRules.tag_match("tea", "team"), "tag matching")


func test_give_item_with_reaction_and_daily_limit() -> void:
	const Inventory := preload("res://scripts/items/inventory.gd")
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	var before := float(GameState.get_character(id).relationship.affinity)
	var mood_before := float(GameState.get_character(id).mood.happiness)
	var convo := Conversation.new()
	eq(Inventory.count("cup_of_tea"), 2, "starter bag has tea")
	var reply: Dictionary = await convo.give_item(id, "cup_of_tea")  # Mochi likes tea and cozy things
	eq(reply.reaction, "love")
	check(str(preload("res://scripts/ai/reply_parser.gd").joined_text(reply.segments)).to_lower().find("cup of tea") != -1, "Mock reacts to the gift by name")
	var c := GameState.get_character(id)
	check(float(c.relationship.affinity) >= before + 6.0, "big closeness boost")
	check(float(c.mood.happiness) > mood_before, "happier")
	eq(Inventory.count("cup_of_tea"), 1, "one fewer in the bag")
	eq(c.gifts_received.back().item, "cup_of_tea", "remembered")
	var log := ChatLog.read_all(id)
	eq(log[0].get("kind"), "gift", "gift logged")
	eq(log[0].get("item"), "cup_of_tea")
	check(log.any(func(e): return e.get("role") == "note"), "mood change noted in the log")
	check(GameState.journal.moments.any(func(m): return str(m.title).find("loved your gift") != -1), "Memory Book entry")
	await convo.give_item(id, "fresh_cookies")
	await convo.give_item(id, "fresh_cookies")
	eq((await convo.give_item(id, "fresh_cookies")).size(), 0, "three gifts a day at most")


func test_bonds_between_residents() -> void:
	const Bonds := preload("res://scripts/characters/bonds.gd")
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	StarterContent.create_mochi()
	StarterContent.create_mochi("Bean", Color("#7ad6b0"))
	GameState.load_world()
	eq(Bonds.key("mochi", "bean"), Bonds.key("bean", "mochi"), "order doesn't matter")
	eq(Bonds.label(Bonds.value("mochi", "bean")), "just met")
	Bonds.add("mochi", "bean", 55.0)
	eq(Bonds.label(Bonds.value("bean", "mochi")), "close friends")
	eq(Bonds.add("mochi", "mochi", 10.0), 0.0, "no bond with yourself")
	eq(float(SaveManager.load_world().bonds[Bonds.key("mochi", "bean")]), 55.0, "saved in world.json")
	var ctx := Conversation.new().base_context(GameState.get_character("mochi"))
	ctx["user_text"] = "hi"
	var system: String = preload("res://scripts/ai/prompt_builder.gd").build_messages(ctx)[0].content
	check(system.find("Bean (close friends)") != -1, "friends know about each other")


func test_character_theme_music() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	StarterContent.create_mochi()
	# Two tiny generated tracks dropped into the save folder's music folder.
	for n in ["room_song", "mochi_theme"]:
		var wav: AudioStreamWAV = preload("res://scripts/core/synth.gd").get_sound("chime")
		wav.save_to_wav(SaveManager.global_path("audio/music/%s.wav" % n))
	var room := SaveManager.load_room("home")
	room.ambiance.music = "room_song"
	SaveManager.save_room(room)
	var c := SaveManager.load_character("mochi")
	c["theme"] = "mochi_theme"
	SaveManager.save_character(c)
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.start_game()
	await frames(2)
	var music: Node = main.game.music
	check(music.current_track().ends_with("room_song.wav"), "room track plays")
	main.game.talk.talk_to("mochi")
	check(music.current_track().ends_with("mochi_theme.wav"), "theme plays while talking")
	main.game.dialogue.close_box()
	check(music.current_track().ends_with("room_song.wav"), "back to the room track")
	main.queue_free()
	await frames(1)
