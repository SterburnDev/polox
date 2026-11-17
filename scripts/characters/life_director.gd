extends Node
## Makes the room feel lived-in while you're just hanging out: residents
## wander, notice and greet you, chat with each other, and small events
## happen every few minutes. Moods tick along with the real clock.

const MoodSim := preload("res://scripts/characters/mood_sim.gd")
const DailyEvents := preload("res://scripts/characters/daily_events.gd")
const NpcChatter := preload("res://scripts/characters/npc_chatter.gd")
const Conversation := preload("res://scripts/ai/conversation.gd")
const Bonds := preload("res://scripts/characters/bonds.gd")

const GREET_RADIUS := 2.3
const GREET_COOLDOWN := 120.0

var world: Node
var rng := RandomNumberGenerator.new()
var events: RefCounted
var chatter: RefCounted
var busy: Dictionary = {}          # character id -> true while scripted (events, chatter)
var _wander_in: Dictionary = {}    # character id -> seconds until next stroll
var _greet_cd: Dictionary = {}     # character id -> seconds until they may greet again
var _event_in := 0.0
var _chatter_in := 0.0
var _mood_in := 60.0


func setup(game_world: Node) -> void:
	world = game_world
	rng.randomize()
	events = DailyEvents.new(self)
	chatter = NpcChatter.new(self)
	_event_in = rng.randf_range(60.0, 110.0)
	_chatter_in = rng.randf_range(120.0, 200.0)


func _paused() -> bool:
	return world == null or world._transitioning or world.build.active or not world.main.panels.is_empty()


func _process(delta: float) -> void:
	if _paused():
		return
	var talking: String = world.talk.talking_to
	for id in world.actors:
		if id == talking or busy.has(id):
			continue
		_tick_wander(id, delta)
		_tick_greet(id, delta)
	if world.talk.is_open():
		return
	_event_in -= delta
	if _event_in <= 0.0:
		_event_in = rng.randf_range(120.0, 230.0)
		events.run_random()
	_chatter_in -= delta
	if _chatter_in <= 0.0:
		_chatter_in = rng.randf_range(180.0, 330.0)
		chatter.try_start()
	_mood_in -= delta
	if _mood_in <= 0.0:
		_mood_in = 60.0
		_tick_moods()


func _tick_wander(id: String, delta: float) -> void:
	var a: Node3D = world.actors[id]
	if a.is_moving():
		return
	_wander_in[id] = float(_wander_in.get(id, rng.randf_range(2.0, 8.0))) - delta
	if _wander_in[id] > 0.0:
		return
	var sleepy := MoodSim.is_sleepy(GameState.get_character(id))
	_wander_in[id] = rng.randf_range(7.0, 16.0) * (2.5 if sleepy else 1.0)
	if sleepy and rng.randf() < 0.5:
		a.emote("z", Color("#b8aed6"))
		return
	var from: Vector2i = a.cell()
	for attempt in 6:
		var to := from + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
		if to == from or not world.room.nav.walkable(to) or to == world.player.cell():
			continue
		var cells: Array[Vector2i] = world.room.nav.path(from, to)
		if cells.is_empty() or cells.size() > 7:
			continue
		walk_actor(id, cells, 1.5)
		return


## Walks a resident along cells at a given speed.
func walk_actor(id: String, cells: Array[Vector2i], speed: float) -> void:
	var a: Node3D = world.actors[id]
	var pts: Array[Vector3] = []
	for c in cells:
		pts.append(world.room.cell_center(c))
	a.speed = speed
	a.walk(pts)


## Walks a resident next to the player (or another resident). Awaitable.
func approach(id: String, target_cell: Vector2i, speed: float = 2.6) -> bool:
	if not is_inside_tree() or world == null or not world.actors.has(id):
		return false
	var a: Node3D = world.actors[id]
	if not is_instance_valid(a) or not a.is_inside_tree():
		return false
	var dest: Vector2i = world.room.nav.best_neighbor(target_cell, a.cell())
	if dest.x < 0:
		return false
	if dest == a.cell():
		return true
	var cells: Array[Vector2i] = world.room.nav.path(a.cell(), dest)
	if cells.is_empty():
		return false
	var box := {"done": false}
	var cb := func(): box.done = true
	a.arrived.connect(cb, CONNECT_ONE_SHOT)
	walk_actor(id, cells, speed)
	var max_ms := maxi(4000, int((float(cells.size()) / maxf(0.1, speed) + 5.0) * 1000.0))
	var deadline := Time.get_ticks_msec() + max_ms
	while not bool(box.done) and is_instance_valid(a) and a.is_moving() and is_inside_tree() and a.is_inside_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if is_instance_valid(a) and a.arrived.is_connected(cb):
		a.arrived.disconnect(cb)
	return bool(box.done) and is_instance_valid(a) and is_inside_tree()


func _tick_greet(id: String, delta: float) -> void:
	_greet_cd[id] = float(_greet_cd.get(id, 0.0)) - delta
	if _greet_cd[id] > 0.0:
		return
	var a: Node3D = world.actors[id]
	if a.position.distance_to(world.player.position) > GREET_RADIUS:
		return
	_greet_cd[id] = GREET_COOLDOWN
	var c := GameState.get_character(id)
	a.stop()
	a.say(greeting_line(c), 3.5)
	a.emote("♥" if float(c.get("relationship", {}).get("affinity", 0)) >= 40.0 else "!", Color("#ff8fab"))
	MoodSim.company(c, 0.04)
	SaveManager.save_character(c)


## A short hello shown in a speech bubble (no AI call).
func greeting_line(c: Dictionary) -> String:
	var you := GameState.player_name()
	var hi := ("Hi, %s!" % you) if you != "" else "Hi!"
	var special := Conversation.holiday_greeting(c)
	if special != "":
		return special
	var celebrated: String = events.uncelebrated_dream(c)
	if celebrated != "":
		return "You did it!! \"%s\"! I'm so proud of you!" % celebrated
	var m: Dictionary = c.get("mood", {})
	if float(m.get("loneliness", 0)) > 0.6:
		return ["You're back! I missed you!", "%s I was hoping you'd come by." % hi].pick_random()
	if MoodSim.is_sleepy(c):
		return ["*yawn* oh... hi...", "Mm, hi. So sleepy..."].pick_random()
	return [hi, "Oh! It's you!", "Hey hey!", "%s Come say hi!" % hi, "Oh, perfect timing!"].pick_random()


## Real-clock mood drift for everyone, plus a little company bonus for
## residents near the player. Saved quietly (no UI refresh).
func _tick_moods() -> void:
	var now := Time.get_unix_time_from_system()
	var hour := MoodSim.now_hour()
	for id in GameState.characters:
		var c: Dictionary = GameState.characters[id]
		MoodSim.catch_up(c, now, hour)
		if world.actors.has(id) and world.actors[id].position.distance_to(world.player.position) < 4.0:
			MoodSim.company(c, 0.01)
		SaveManager.save_character(c)
	# Residents hanging out near each other slowly become friends.
	var ids: Array = world.actors.keys()
	var grew := false
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if world.actors[ids[i]].position.distance_to(world.actors[ids[j]].position) < 3.0:
				Bonds.add(ids[i], ids[j], 0.3, false)
				grew = true
	if grew:
		GameState.save_world()
