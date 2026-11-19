extends Node
## The variety pack, live in the game world: on opening a world, While You Were
## Away (if it's been 3+ hours) and today's Moments (sky, found objects,
## visitors, requests, rumors, celebrations, echoes) with the day's card; Dream
## Quest offers; residents following their routines as the day turns;
## quests checked against the world as you play; "Keep this dream room" in a
## Dream Door's room. Works fully offline; an AI only rewrites letters.

signal day_started(today: Dictionary)
signal quest_done(quest: Dictionary)

const Clock := preload("res://scripts/variety/clock.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const Moments := preload("res://scripts/variety/moments.gd")
const Visitors := preload("res://scripts/variety/visitors.gd")
const Quests := preload("res://scripts/variety/quests.gd")
const Away := preload("res://scripts/variety/away.gd")
const Routines := preload("res://scripts/variety/routines.gd")
const DreamDoors := preload("res://scripts/variety/dream_doors.gd")
const Synth := preload("res://scripts/core/synth.gd")

var world: Node                    # game_world.gd
var today: Dictionary = {}
var away: Dictionary = {}          # the last While You Were Away result
var card: Control                  # today_card.gd
var keep_button: Control
var hangouts: Node                 # hangouts.gd (Tea Time, Stargazing, Photo Walk)
var _date := ""
var _part := ""
var _t := 0.0
var _quest_t := 0.0
var _last_cell := Vector2i(-99, -99)
var _rumors_said: Dictionary = {}
var _started := false


func setup(game_world: Node) -> void:
	world = game_world
	ChatLog.logged.connect(_on_logged)
	hangouts = load("res://scripts/variety/hangouts.gd").new()
	hangouts.name = "Hangouts"
	add_child(hangouts)
	hangouts.setup(world)


func enabled() -> bool:
	return bool(GameState.world.get("settings", {}).get("daily_events", true))


## Opening the world: time away first, then the day.
func on_room_loaded(room_id: String) -> void:
	if not _started:
		_started = true
		_part = Clock.part_of_day()
		if enabled():
			away = Away.run()
			if not (away.get("notes", []) as Array).is_empty():
				_enrich_letters.call_deferred(away)
		begin_day()
	for q in Quests.on_visit(room_id):
		_celebrate(q)
	_announce_titles()
	for r in load("res://scripts/variety/requests.gd").check_all():
		GameState.notify("💬 %s: \"Thank you!\"" % str(GameState.get_character(str(r.giver)).get("name", "")))
	_say_rumors_and_activities()
	_update_keep_button(room_id)


func _enrich_letters(result: Dictionary) -> void:
	await Away.enrich_with_ai(result)


## Today's Moments, applied once per day (also after midnight while playing).
func begin_day() -> void:
	_date = Clock.today()
	if not enabled():
		return
	for gone in Visitors.farewell_old(_date):
		if world.actors.has(gone):
			world.actors[gone].queue_free()
			world.actors.erase(gone)
	today = Moments.today()
	if not bool(today.get("applied", false)):
		_apply(today)
	Quests.offer_dream_quests(_date)
	var Requests: Script = load("res://scripts/variety/requests.gd")
	var residents: Array = GameState.characters.keys().filter(func(id): return not bool(GameState.characters[id].get("visitor", false)))
	if not residents.is_empty() and str(VarietySave.data().get("request_day", "")) != _date:
		VarietySave.data()["request_day"] = _date
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_date)
		if rng.randf() < 0.5:
			Requests.offer(str(residents[rng.randi() % residents.size()]), rng)
	day_started.emit(today)
	if not bool(today.get("shown", false)):
		show_card.call_deferred()   # after the "Where was I?" card exists, so it can wait its turn


func _apply(t: Dictionary) -> void:
	var date := str(t.get("date", ""))
	for m in t.get("moments", []):
		match str(m.kind):
			"visitor":
				m["visitor_id"] = Visitors.arrive(m, date)
				VarietySave.count("visitors_met")
			"found":
				var o := Visitors.place_found(m)
				m["placed"] = not o.is_empty()
			"request":
				var q := Quests.from_request(m)
				m["quest"] = str(q.get("id", ""))
	t["applied"] = true
	VarietySave.save()
	# Arrivals and found things in the room you're in show up right away.
	if world.room and not world.room.data.is_empty():
		var room_id := GameState.current_room_id
		if t.get("moments", []).any(func(m): return str(m.get("room", "")) == room_id and str(m.kind) in ["found", "visitor"]):
			world.room.data = SaveManager.load_room(room_id)
			world.rebuild_room()
			for m in t.get("moments", []):
				if str(m.kind) == "visitor" and str(m.get("visitor_id", "")) != "":
					world.refresh_character(str(m.visitor_id))
	world.refresh_weather(true)


## The sky a Sky Moment asks for today ("" = the season decides).
func sky_today() -> String:
	if today.is_empty() or str(today.get("date", "")) != Clock.today():
		return ""
	for m in today.get("moments", []):
		if str(m.kind) == "sky":
			return str(m.extra.get("sky", ""))
	return ""


func show_card() -> void:
	if not is_inside_tree() or world == null or world.main == null or world.main.get("ui") == null:
		return
	# The "Where was I?" card goes first; the day's card follows when it's put away.
	for n in world.main.ui.get_children():
		if n.get_script() == load("res://scripts/ui/recap_card.gd") and is_instance_valid(n) and not n.is_queued_for_deletion():
			n.tree_exited.connect(show_card, CONNECT_ONE_SHOT)
			return
	if card and is_instance_valid(card):
		card.queue_free()
	card = load("res://scripts/ui/today_card.gd").new()
	card.director = self
	world.main.ui.add_child(card)
	today["shown"] = true
	VarietySave.save()


func _process(delta: float) -> void:
	if world == null or not _started:
		return
	_t += delta
	if _t >= 2.0:
		_t = 0.0
		if Clock.today() != _date:
			begin_day()
		var part := Clock.part_of_day()
		if part != _part:
			_part = part
			_routines_turn()
	_quest_t += delta
	if _quest_t >= 4.0:
		_quest_t = 0.0
		Away.mark_seen()   # "away" means since you last played, not since you opened the world
		for q in Quests.check_all():
			_celebrate(q)
	if world.player and is_instance_valid(world.player) and not world.player.is_moving():
		var c: Vector2i = world.player.cell()
		if c != _last_cell:
			_last_cell = c
			for q in Quests.on_step(GameState.current_room_id, c):
				_celebrate(q)


## The day moved on (morning -> afternoon...): residents go where their routine says.
func _routines_turn() -> void:
	for id in GameState.characters:
		world.refresh_character(str(id))
	_say_rumors_and_activities()


func _on_logged(e: Dictionary) -> void:
	if str(e.get("role", "")) != "user":
		return
	for q in Quests.on_chat(str(e.get("character", "")), str(e.get("text", ""))):
		_celebrate(q)


func _celebrate(q: Dictionary) -> void:
	Synth.play(world, "fanfare", 0.4)
	var giver := str(q.get("giver", ""))
	if world.actors.has(giver):
		world.actors[giver].emote("♥", Color("#ff8fab"))
	GameState.notify("✦ Quest done: %s. You got: %s" % [str(q.title), str(q.get("reward", {}).get("name", "a keepsake"))])
	quest_done.emit(q)
	_announce_titles()


## [GOALS] A title earned since the last look is said once, when you arrive somewhere or finish a
## quest (never on a timer). It waits in the Almanac; wearing it is up to you.
func _announce_titles() -> void:
	if not enabled():
		return
	for title in preload("res://scripts/variety/almanac.gd").new_titles():
		GameState.notify("★ New title: %s. It's in your Almanac whenever you'd like to wear it." % title)


## Residents here say today's rumor (once) and what they're up to.
func _say_rumors_and_activities() -> void:
	var delay := 2.0
	for m in today.get("moments", []):
		if str(m.kind) == "rumor" and world.actors.has(str(m.character)) and not _rumors_said.has(str(m.id)):
			_rumors_said[str(m.id)] = true
			_say_later(str(m.character), str(m.text), delay)
			delay += 4.0
	for id in world.actors:
		var act := Routines.activity_now(GameState.get_character(str(id)))
		if act != "":
			_say_later(str(id), "(%s)" % act, delay)
			delay += 2.5


func _say_later(id: String, text: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if world and world.actors.has(id) and is_instance_valid(world.actors[id]) and not world.talk.is_open():
		world.actors[id].say(text, 5.0)


# --- Dream Doors ------------------------------------------------------------------------------------

func open_dream_door(door: Dictionary) -> void:
	var id := DreamDoors.open(door, GameState.current_room_id)
	Synth.play(world, "sparkle", 0.5)
	world.go_to_room(id)


func _update_keep_button(room_id: String) -> void:
	if keep_button and is_instance_valid(keep_button):
		keep_button.queue_free()
	keep_button = null
	if not bool(SaveManager.load_room(room_id).get("dream", false)) or world.main == null:
		return
	var UiKit: GDScript = load("res://scripts/ui/ui_kit.gd")
	var b: Button = UiKit.button("★ Keep this dream room", func():
		if DreamDoors.keep(room_id):
			world.room.data = SaveManager.load_room(room_id)
			GameState.notify("This room is yours now (Rooms list). Rename it any time.")
			_update_keep_button(room_id), 0)
	b.tooltip_text = "Otherwise it waits in the Dream Archive (the last 10 dreams)"
	b.focus_mode = Control.FOCUS_NONE
	b.position = Vector2(20, 140)
	world.main.ui.add_child(b)
	keep_button = b


func _exit_tree() -> void:
	if _started:
		Away.mark_seen()
		VarietySave.save()
	for n in [card, keep_button]:
		if n and is_instance_valid(n):
			n.queue_free()
