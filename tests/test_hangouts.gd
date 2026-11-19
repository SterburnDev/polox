extends "res://tests/test_case.gd"
## Phase 18 stretch: Hangouts (Tea Time, Stargazing with a wish for the Dreams
## board, Photo Walk) in the real game with the AI off, and seasonal
## decorations from real dates (the Time Machine stands in for the calendar):
## right themes on the right days, purely visual (never in the room's file,
## nothing blocks walking), switched off in Settings.

const Clock := preload("res://scripts/variety/clock.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const SeasonalDecor := preload("res://scripts/variety/seasonal_decor.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")


func _world() -> void:
	Clock.reset()
	fresh_save_root()
	StarterContent.create_world("Hangouts", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	AIClient.configure({"preset": "mock"})


func _game() -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.start_game()
	await frames(8)
	var card: Node = main.game.variety.card
	if card and is_instance_valid(card):
		card.queue_free()
	return main


## Puts the Time Machine on `date` (YYYY-MM-DD), at local noon.
func _to_date(date: String) -> void:
	Clock.reset()
	var target := Time.get_unix_time_from_datetime_string(date + "T12:00:00") - int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	Clock.advance((target - Clock.now()) / 86400.0)


func _friend(g: Node) -> String:
	for id in g.actors:
		return str(id)
	return ""


func _moment(title_start: String) -> Dictionary:
	for m in GameState.journal.get("moments", []):
		if str(m.get("title", "")).begins_with(title_start):
			return m
	return {}


func test_tea_time_and_stargazing_wish() -> void:
	_world()
	var main: Node = await _game()
	var g: Node = main.game
	var h: Node = g.variety.hangouts
	var id := _friend(g)
	check(id != "", "a friend is in the room")
	var c := GameState.get_character(id)
	c["mood"]["loneliness"] = 0.6
	GameState.save_character(c)
	await h.start("tea", id)
	var tea := _moment("Tea time with")
	check(not tea.is_empty(), "Tea Time leaves a Memory Book moment")
	check(float(GameState.get_character(id).mood.loneliness) < 0.6, "your friend feels less lonely (%.2f)" % float(GameState.get_character(id).mood.loneliness))
	check(g.find_children("TeaSet", "", true, false).all(func(n): return n.is_queued_for_deletion()), "the tea set is cleared away afterwards")
	check(not g.life.busy.has(id), "they're free to wander again")
	eq(h.running, "", "the hangout is over")
	var dreams_before := (GameState.dreams.dreams as Array).size()
	var sky_before: String = g.weather.current
	h.wish_text = "see the northern lights for real"
	await h.start("stars", id)
	eq((GameState.dreams.dreams as Array).size(), dreams_before + 1, "the wish joins the Dreams board")
	check((GameState.dreams.dreams as Array).any(func(d): return str(d.text) == "see the northern lights for real"), "with your words")
	check(not _moment("A wish under the stars").is_empty(), "and the Memory Book")
	eq(g.weather.current, sky_before, "the sky goes back to the day's own weather")
	await h.start("stars", id)   # "Just look at the stars": no wish, still a nice moment
	eq((GameState.dreams.dreams as Array).size(), dreams_before + 1, "no wish, no new dream")
	check(not _moment("Stargazing with").is_empty(), "just looking is a moment too")
	eq(int(VarietySave.data().almanac.get("hangouts", 0)), 3, "the Almanac counts hangouts")
	main.queue_free()
	await frames(3)


func test_photo_walk_and_guards() -> void:
	_world()
	var main: Node = await _game()
	var g: Node = main.game
	var h: Node = g.variety.hangouts
	var id := _friend(g)
	eq(h.blocked_reason("nobody"), "They're not in this room right now.", "only friends who are here")
	var done := [false]
	h.finished.connect(func(_k): done[0] = true, CONNECT_ONE_SHOT)
	h.start.call_deferred("walk", id)
	var mine := {}
	var theirs := {}
	var until := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until:
		await tree.create_timer(0.05).timeout
		mine[g.player.cell()] = true
		if g.actors.has(id):
			theirs[g.actors[id].cell()] = true
		if done[0]:
			break
	check(done[0], "the walk ends by itself")
	check(not _moment("Photo walk with").is_empty(), "the walk is in the Memory Book")
	check(mine.size() >= 3, "you walked around (%d cells)" % mine.size())
	check(theirs.size() >= 3, "and your friend came along (%d cells)" % theirs.size())
	if DisplayServer.get_name() != "headless":
		check(h.last_photo != "" and FileAccess.file_exists(SaveManager.abs_path(h.last_photo)), "the photo is saved")
	g.platform.active = true
	check(h.blocked_reason(id).contains("Platform Mode"), "not in Platform Mode")
	g.platform.active = false
	# Walking off mid-hangout (another room) is fine: it just ends.
	var other := ""
	for r in SaveManager.list_rooms():
		if r != GameState.current_room_id:
			other = r
	check(other != "", "(the world has a second room)")
	done[0] = false
	h.finished.connect(func(_k): done[0] = true, CONNECT_ONE_SHOT)
	var tea_before: int = GameState.journal.get("moments", []).filter(func(m): return str(m.get("title", "")).begins_with("Tea time")).size()
	h.start.call_deferred("tea", id)
	await tree.create_timer(0.3).timeout
	g.go_to_room(other)
	var wait := Time.get_ticks_msec() + 20000
	while not done[0] and Time.get_ticks_msec() < wait:
		await tree.create_timer(0.05).timeout
	check(done[0], "the hangout ends when you leave")
	eq(h.running, "", "and nothing is left running")
	eq(GameState.journal.get("moments", []).filter(func(m): return str(m.get("title", "")).begins_with("Tea time")).size(), tea_before, "no tea moment for a tea you walked away from")
	check(not g.life.busy.has(id), "your friend is free again")
	main.queue_free()
	await frames(3)


func test_decor_themes_from_real_dates() -> void:
	_world()
	var t := SeasonalDecor.today("2026-10-20")
	check(t.themes.has("halloween"), "Halloween week")
	eq(t.accent, "leaves", "autumn leaves")
	t = SeasonalDecor.today("2026-12-31")
	check(t.themes.has("new_year") and t.themes.has("winter"), "New Year's Eve and the winter holidays")
	check(SeasonalDecor.today("2027-01-01").themes.has("new_year"), "the New Year window wraps past midnight")
	t = SeasonalDecor.today("2026-08-05")
	check(t.themes.is_empty(), "an ordinary summer day: no holiday decor")
	eq(t.accent, "sunflower", "just the season's touch")
	eq(SeasonalDecor.today("2026-02-12").accent, "snow", "winter in February")
	check(SeasonalDecor.today("2026-02-12").themes.has("valentine"), "Valentine's week")
	GameState.world["player"]["birthday"] = "1999-05-14"
	t = SeasonalDecor.today("2026-05-14")
	eq(str(t.themes[0]), "party", "your birthday is a party")
	VarietySave.data()["celebrations"] = [{"date": "07-09", "name": "Pip's day"}]
	t = SeasonalDecor.today("2026-07-09")
	check(t.themes.has("party") and t.names.has("Pip's day"), "dates you celebrate get decorated too")
	GameState.world["settings"]["hemisphere"] = "south"
	eq(SeasonalDecor.today("2026-08-05").accent, "snow", "southern hemisphere: August is winter")


func test_decor_in_the_room_is_visual_only() -> void:
	_world()
	_to_date("2026-10-24")
	var room_file := FileAccess.get_file_as_string(SaveManager.abs_path("rooms/home.json"))
	var main: Node = await _game()
	var g: Node = main.game
	var content: Node = g.room.get("_content")
	var root: Node = content.get_node_or_null("SeasonalDecor")
	check(root != null, "decorations in the room")
	check((root.get_meta("themes", []) as Array).has("halloween"), "Halloween ones")
	check(int(root.get_meta("bulbs", 0)) > 8, "string lights along the walls (%d)" % int(root.get_meta("bulbs", 0)))
	check(root.get_child_count() >= 3, "and things in the corners (%d)" % root.get_child_count())
	check(root.find_children("*", "CollisionObject3D", true, false).is_empty(), "nothing solid: walking is unchanged")
	g.flush_all()
	var saved := FileAccess.get_file_as_string(SaveManager.abs_path("rooms/home.json"))
	check(not saved.contains("halloween") and not saved.contains("SeasonalDecor") and not saved.contains("seasonal"), "never written into the room's file")
	check(room_file != "", "(the room file exists)")
	# The calendar moves on (Time Machine): the decor follows.
	_to_date("2026-12-20")
	g.refresh_weather()
	root = content.get_node_or_null("SeasonalDecor")
	check(root != null and (root.get_meta("themes", []) as Array).has("winter"), "winter holiday decor in December")
	_to_date("2026-08-05")
	g.refresh_weather()
	root = content.get_node_or_null("SeasonalDecor")
	eq(int(root.get_meta("bulbs", 0)), 0, "no string lights on an ordinary day")
	eq(root.get_child_count(), 1, "just the season's touch")
	# Switched off in Settings.
	_to_date("2026-10-24")
	GameState.world["settings"]["seasonal_decor"] = false
	g.refresh_weather()
	root = content.get_node_or_null("SeasonalDecor")
	eq(root.get_child_count(), 0, "switched off: nothing")
	var bulbs := 0
	for side in g.room.get("_walls"):
		for b in (g.room.get("_walls")[side][0] as Node).get_children():
			if b.has_meta("seasonal"):
				bulbs += 1
	eq(bulbs, 0, "and no lights")
	# Rebuilding the room (Build mode) brings it back once on again.
	GameState.world["settings"]["seasonal_decor"] = true
	g.rebuild_room()
	content = g.room.get("_content")
	root = content.get_node_or_null("SeasonalDecor")
	check(root != null and int(root.get_meta("bulbs", 0)) > 8, "rebuilt with the room")
	Clock.reset()
	main.queue_free()
	await frames(3)
