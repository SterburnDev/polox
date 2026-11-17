extends "res://tests/test_case.gd"
## Phase 28, reasons to come back without guilt: story chapters that open by playing (never by the
## clock), the Battle Log, Dark Crystals, Almanac rows and titles, discoveries, friend requests, the
## "Since you were last here" lines, and the proof that the banned mechanics don't exist: no
## streaks, login rewards, timers, energy gates, loss aversion or FOMO, in the code and in what
## happens after a month away. (By the user's choice after 1.13.0, happiness drifts down to calm while
## you're away and gifts are limited to three per friend a day: decisions 232-233.)

const Story := preload("res://scripts/variety/story.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const MoodSim := preload("res://scripts/characters/mood_sim.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const Quests := preload("res://scripts/variety/quests.gd")
const Away := preload("res://scripts/variety/away.gd")
const RecapCard := preload("res://scripts/ui/recap_card.gd")
const Places := preload("res://scripts/world/places.gd")
const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const Almanac := preload("res://scripts/variety/almanac.gd")
const Requests := preload("res://scripts/variety/requests.gd")
const StoryPanel := preload("res://scripts/ui/story_panel.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

var main: Node

## Words that mean a banned mechanic when they show up in what the game says or does.
const BANNED := ["streak", "login reward", "login bonus", "daily reward", "daily bonus", "come back tomorrow or",
	"don't lose your", "you'll lose", "you will lose", "last chance", "limited time", "expires in", "expiring",
	"before it's gone", "miss out", "energy refill", "out of energy", "stamina", "refill in", "wait to play",
	"decays", "decay rate", "countdown", "hurry up"]


func _world() -> String:
	fresh_save_root()
	StarterContent.create_world("Story World", "Sam")
	var m := StarterContent.create_mochi()
	GameState.load_world()
	return m


func test_chapters_open_by_playing_never_by_the_clock() -> void:
	_world()
	var st := Story.status()
	eq(int(st.chapter), 0, "the first chapter")
	eq(str(st.current.id), "home")
	var c := Story.counts()
	c["places"] = 2
	c["chats"] = 1
	st = Story.status(c)
	eq(int(st.chapter), 1, "doing its things opens the next")
	eq(Story.titles(c).map(func(t): return str(t.name)), ["Homemaker"], "and a title to wear")
	# Time passing alone changes nothing.
	var before := JSON.stringify(Story.status())
	MoodSim.catch_up(GameState.get_character(GameState.characters.keys()[0]), Time.get_unix_time_from_system() + 30 * 86400.0, 12.0)
	eq(JSON.stringify(Story.status()), before, "a month away: the story waits exactly where it was")
	check(Story.CHAPTERS.size() >= 6, "a real arc (%d chapters)" % Story.CHAPTERS.size())


func test_the_last_chapter_works_with_one_on_one_battles() -> void:
	_world()
	for n in ["Pip", "Juno"]:
		GameState.save_character({"id": n.to_lower(), "name": n})
	var foe := func(n: String) -> Dictionary:
		return {"battle": "Spar", "outcome": "spared", "party": ["Sam"], "enemies": [{"name": n}]}
	GameState.world["battle_log"] = [foe.call("Mochi"), foe.call("Mochi"), foe.call("Pip"), foe.call("Star Rehearsal")]
	eq(int(Story.counts().friends_battled), 2, "two different friends so far (the same friend twice and a stranger don't add)")
	GameState.world["battle_log"].append(foe.call("Juno"))
	eq(int(Story.counts().friends_battled), 3, "a third friend finishes the goal, all on your own")
	GameState.world["battle_log"] = [{"battle": "Old", "outcome": "won", "party": ["Sam", "Mochi"], "enemies": [{"name": "Nova"}]}]
	eq(int(Story.counts().friends_battled), 3, "a battle fought with a friend at your side before 1.27.5 keeps the goal done")
	for ch in Story.CHAPTERS:
		for g in ch.goals:
			check(Story.counts().has(str(g[0])), "the story counts '%s'" % g[0])


func test_a_month_away_keeps_everything_yours() -> void:
	var mochi := _world()
	var c := GameState.get_character(mochi)
	c["affinity"] = 0.6
	c["mood"] = {"happiness": 0.9, "loneliness": 0.1, "energy": 0.7}
	c["last_update_unix"] = Time.get_unix_time_from_system()
	Inventory.add("bubble_wand", 2)
	var bag := Inventory.total_items()
	var quests_before := Quests.active().size()
	MoodSim.catch_up(c, Time.get_unix_time_from_system() + 30 * 86400.0, 12.0)
	eq(float(c.affinity), 0.6, "friendship doesn't fade")
	var h := float(c.mood.happiness)
	check(h < 0.9 and h >= 0.6, "happiness drains while you're away, down to calm and no lower (%.2f)" % h)
	check(float(c.mood.loneliness) <= 0.45, "missing you a little at most (%.2f)" % float(c.mood.loneliness))
	eq(Inventory.total_items(), bag, "nothing leaves your bag")
	eq(Quests.active().size(), quests_before, "no quest expired")


func test_no_banned_mechanics_anywhere_in_the_game() -> void:
	var files := PackedStringArray()
	_scripts("res://scripts", files)
	check(files.size() > 150, "scanned the game (%d scripts)" % files.size())
	var found: Array = []
	for f in files:
		for line in FileAccess.get_file_as_string(f).split("\n"):
			var l := line.to_lower()
			if l.strip_edges().begins_with("#"):
				continue   # comments may explain what we don't do
			for w in BANNED:
				if l.contains(w):
					found.append("%s: %s" % [f.get_file(), line.strip_edges().substr(0, 90)])
	eq(found, [], "no streaks, login rewards, timers, decay, energy, loss aversion or FOMO in anything the game says")
	# Nothing in play is gated by an energy bar or a timer. (The one daily limit, three gifts per friend,
	# is kept at the user's request: decision 232.)
	for f in files:
		var s := FileAccess.get_file_as_string(f)
		check(not s.contains("max_daily") and not s.contains("daily_limit") and not s.contains("plays_left"), f.get_file() + ": no daily limits")


func _scripts(dir: String, out: PackedStringArray) -> void:
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))


func test_since_you_were_last_here() -> void:
	_world()
	var r := RecapCard.build_recap("2026-10-01T10:00:00")
	var text := " ".join(r.get("lines", []).map(func(l): return str(l[1])))
	check(text.contains("Chapter"), "it says where the story is: " + text)
	check(text.contains("Nothing was missed"), "and that nothing was missed")
	for w in BANNED:
		check(not text.to_lower().contains(w), "no guilt: " + w)


func test_friend_requests_are_kind_and_never_expire() -> void:
	var mochi := _world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var c := Story.counts()
	var a := Requests.offer(mochi, rng, c)
	var b := Requests.offer(mochi, rng, c)
	check(not a.is_empty() and not b.is_empty(), "a friend asks")
	check(str(a.kind) != str(b.kind), "two different wishes")
	eq(Requests.offer(mochi, rng, c), {}, "never more than two at once")
	var friend := GameState.get_character(mochi)
	friend["last_update_unix"] = Time.get_unix_time_from_system()
	MoodSim.catch_up(friend, Time.get_unix_time_from_system() + 30 * 86400.0, 12.0)
	eq(Requests.open().size(), 2, "no deadline: both still there a month later")
	eq(Requests.check_all(c), [], "and nothing happens by itself")
	# Doing one (counted from when it was asked): a thank-you, a Memory Book page, a little closeness.
	var done := c.duplicate()
	var key := str(Requests.KINDS[str(a.kind)].key)
	done[key] = int(done.get(key, 0)) + 1
	var aff := float(GameState.get_character(mochi).get("affinity", 0.0))
	var pages := (GameState.journal.moments as Array).size()
	var finished := Requests.check_all(done)
	eq(finished.map(func(r): return str(r.id)), [str(a.id)], "the one you did is thanked")
	check(float(GameState.get_character(mochi).affinity) > aff, "a little closeness")
	eq((GameState.journal.moments as Array).size(), pages + 1, "a Memory Book page")
	# Letting one go costs nothing.
	aff = float(GameState.get_character(mochi).affinity)
	Requests.let_go(str(b.id))
	eq(Requests.open().size(), 0, "letting one go is fine")
	eq(float(GameState.get_character(mochi).affinity), aff, "no hard feelings")


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _shutdown() -> void:
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func _almanac(key: String) -> int:
	return int((VarietySave.data().get("almanac", {}) as Dictionary).get(key, 0))


func test_discoveries_and_dark_crystals_in_play() -> void:
	var g: Node = await _boot()
	GameState.settings["reduce_motion"] = true
	# A discovery: the first visit to another place (and only the first).
	var home := GameState.current_room_id
	var other := ""
	for id in SaveManager.list_rooms():
		if str(id) != home:
			other = str(id)
			break
	g.go_to_room(other)
	var t0 := Time.get_ticks_msec()
	while (g._transitioning or GameState.current_room_id != other) and Time.get_ticks_msec() - t0 < 8000:
		await frames(2)
	eq(_almanac("discoveries"), 1, "a new place is a discovery")
	g.go_to_room(home)
	t0 = Time.get_ticks_msec()
	while (g._transitioning or GameState.current_room_id != home) and Time.get_ticks_msec() - t0 < 8000:
		await frames(2)
	g.go_to_room(other)
	t0 = Time.get_ticks_msec()
	while (g._transitioning or GameState.current_room_id != other) and Time.get_ticks_msec() - t0 < 8000:
		await frames(2)
	eq(_almanac("discoveries"), 1, "going back isn't another")
	# A Dream World: the first visit hides three crystals; each counts once.
	var data: Dictionary = g.room.data
	var f := DarkWorlds.place_fountain(data, Vector2i(5, 5))
	var dark := DarkWorlds.make_from(data, SaveManager.list_rooms())
	DarkWorlds.link(data, f, dark)
	SaveManager.save_room(dark)
	SaveManager.save_room(data)
	g.rebuild_room()
	await frames(2)
	await g.dark.enter(g.room.find_object(str(f.id)))
	eq(GameState.current_room_id, str(dark.id), "in the Dream World")
	eq(_almanac("dark_visits"), 1, "a Dream World visit")
	var crystals: Array = (g.room.data.objects as Array).filter(func(o): return bool(o.get("crystal", false)))
	eq(crystals.size(), 3, "three Dark Crystals hidden")
	for o in crystals:
		check(g.room.nav.walkable(g.room.obj_cell(o)), "each one where you can walk")
	var it: Dictionary = g.controller.collect_pickup(crystals[0])
	eq(str(it.get("id", "")), "dark_crystal", "a Dark Crystal in your bag")
	eq(_almanac("crystals"), 1, "counted")
	g.controller.collect_pickup(crystals[0])
	eq(_almanac("crystals"), 1, "and only once")
	eq(int(Story.counts().crystals), 1, "the story sees it")
	check(Almanac.ROWS.any(func(r): return str(r[0]) == "crystals") and Almanac.ROWS.any(func(r): return str(r[0]) == "discoveries"), "Almanac rows")
	await _shutdown()


func test_the_story_panel_by_clicks_alone() -> void:
	var g: Node = await _boot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var mochi := str(g.actors.keys()[0])
	Requests.offer(mochi, rng)
	for n in main.ui.find_children("*", "", true, false):   # the start-up cards (a player taps Got it)
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()
	await frames(2)
	var p: Control = main.open_panel(StoryPanel.new())
	await frames(3)
	check(p.find_child("Tab_story", true, false) != null, "Story, Requests, Battle Log, Collection")
	check(p.find_child("Tab_story", true, false).get_parent() is HFlowContainer, "the tabs wrap on a narrow screen")
	var text := func() -> String:
		var parts: Array = []
		for n in p.find_children("*", "Label", true, false):
			parts.append((n as Label).text)
		return " ".join(parts)
	check(str(text.call()).contains("Chapter 1"), "the story so far")
	check(str(text.call()).contains("No rush"), "with no clock")
	for t in ["requests", "log", "found"]:
		await _click((p.find_child("Tab_" + t, true, false) as Button).get_global_rect().get_center())
		await frames(3)
		eq(p.tab, t, "a click opens " + t)
	await _click((p.find_child("Tab_requests", true, false) as Button).get_global_rect().get_center())
	await frames(3)
	var let_go: Button = null
	for b in p.find_children("*", "Button", true, false):
		if (b as Button).text == "Let it go":
			let_go = b
	check(let_go != null, "a request, and Let it go")
	var before := Requests.open().size()   # (the game may have offered one of its own at start-up)
	await _click(let_go.get_global_rect().get_center())
	await frames(3)
	eq(Requests.open().size(), before - 1, "let go by a click")
	if Requests.open().is_empty():
		check(str(text.call()).contains("never a deadline"), "and the friend doesn't mind")
	await _shutdown()


## A click, as a hand makes one: move there, press, a moment, release.
func _click(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	main.get_viewport().push_input(mm, true)
	for pressed in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.position = pos
		m.global_position = pos
		m.pressed = pressed
		main.get_viewport().push_input(m, true)
		await frames(1)


func test_travelers_who_wander_on_can_always_come_back() -> void:
	const Visitors := preload("res://scripts/variety/visitors.gd")
	_world()
	var id := Visitors.arrive({"extra": {"name": "Wren", "look": "cozy", "about": "Collects maps of places that don't exist."}, "room": GameState.current_room_id}, "2026-10-01")
	check(id != "" and bool(GameState.get_character(id).get("visitor", false)), "a traveler visits")
	var gone := Visitors.farewell_old("2026-10-02")
	check(id in gone, "not invited today: they wander on")
	eq(Visitors.passed().map(func(r): return str(r.name)), ["Wren"], "but who they were is kept")
	eq(str(Visitors.passed()[0].about), "Collects maps of places that don't exist.")
	# A month later, still there to invite back.
	MoodSim.catch_up(GameState.get_character(GameState.characters.keys()[0]), Time.get_unix_time_from_system() + 30 * 86400.0, 12.0)
	var back := Visitors.invite_back(0, GameState.current_room_id)
	check(back != "", "invited back")
	var c := GameState.get_character(back)
	eq(str(c.get("name", "")), "Wren", "the same traveler")
	check(not bool(c.get("visitor", true)), "staying for good now")
	eq(Visitors.passed().size(), 0, "and no longer waiting")
	check(FileAccess.file_exists(SaveManager.character_dir(back).path_join("expressions/neutral.png")), "with their look")
