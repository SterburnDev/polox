extends Node
## Hangouts with a friend (Menu > Hang out):
##   Tea Time     a teapot and two cups appear between you, they chat; you both feel better
##   Stargazing   the sky turns to an aurora; they point out a star; "make a wish" goes to your Dreams board
##   Photo Walk   a little stroll to a few spots together, then a photo (into the Memory Book)
## Each one leaves a Memory Book moment. Built-in lines (works with the AI off).
## Nothing to win or lose; walk away any time.

signal finished(kind: String)

const MoodSim := preload("res://scripts/characters/mood_sim.gd")
const PlatformObjects := preload("res://scripts/platform/platform_objects.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const Synth := preload("res://scripts/core/synth.gd")

const KINDS := [["tea", "Tea Time", "Sit together over tea"], ["stars", "Stargazing", "Look up together and make a wish"], ["walk", "Photo Walk", "A little stroll and a photo"]]
const TEA_LINES := ["This tea tastes a bit like {like}. Is that weird? I like it.", "I'm glad we're doing nothing together. It's my favorite kind of something.",
	"Tell me one good thing from today. I'll go first: this.", "Careful, it's hot. ...I always say that, don't I?"]
const STAR_LINES := ["See that one? I named it after you. Don't tell the other stars.", "Some of those stars are older than every story. Ours is still new.",
	"If you squint, they make a teapot. Okay, maybe I just want more tea."]
const WALK_LINES := ["Let's take the long way. The long way is the best way.", "Oh! Stand right there. The light is perfect.", "I'm keeping this one forever."]

var world: Node
var running := ""                   # the hangout in progress ("" = none)
var wish_text := ""                 # tests fill this instead of typing
var last_photo := ""                # the Photo Walk's picture (photos/...png)
var _props: Array = []


func setup(game_world: Node) -> void:
	world = game_world


## Why a hangout can't start right now ("" = it can).
func blocked_reason(friend_id: String) -> String:
	if running != "":
		return "You're already hanging out."
	if world.platform and world.platform.active:
		return "Hangouts happen on foot: leave Platform Mode first."
	if not world.actors.has(friend_id):
		return "They're not in this room right now."
	return ""


func start(kind: String, friend_id: String) -> void:
	var why := blocked_reason(friend_id)
	if why != "":
		GameState.notify(why)
		return
	running = kind
	var room_at := GameState.current_room_id
	var friend: Variant = world.actors[friend_id]   # may leave (or you may) mid-hangout
	if world.life:
		world.life.busy[friend_id] = true
	var c := GameState.get_character(friend_id)
	var who := str(c.get("name", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(friend_id + kind + str(Time.get_ticks_msec()))
	match kind:
		"tea":
			await _together(friend)
			if _still(friend, room_at):
				_props.append(_tea_set(_tea_spot(friend)))
				Synth.play(world, "chime", 0.4)
				await _say(friend, _line(TEA_LINES, c, rng), 2.0)
				await _say(friend, _line(TEA_LINES, c, rng), 2.0)
			if _still(friend, room_at):
				GameState.add_moment("Tea time with %s" % who, "We sat together over tea in %s." % _room_name(), friend_id, "auto", {"hangout": "tea"})
		"stars":
			await _together(friend)
			if _still(friend, room_at):
				world.weather_hold = "aurora"
				world.refresh_weather(true)
				world.flash_light(Color("#7a72c0"), 9.0)   # the room takes on the aurora's glow
				await _say(friend, _line(STAR_LINES, c, rng), 2.5)
				var wish := (await _ask_wish()) if _still(friend, room_at) else ""
				if is_inside_tree() and wish != "":
					GameState.add_dream(wish)
					GameState.add_moment("A wish under the stars", "With %s, I wished: %s" % [who, wish], friend_id, "auto", {"hangout": "stars"})
					if is_instance_valid(friend):
						friend.emote("★", Color("#ffd166"))
					GameState.notify("★ Your wish is on your Dreams board")
				elif is_inside_tree():
					GameState.add_moment("Stargazing with %s" % who, "We looked at the stars for a while.", friend_id, "auto", {"hangout": "stars"})
			if is_inside_tree() and world.weather_hold != "":
				world.weather_hold = ""   # back to the day's own sky
				world.refresh_weather(true)
		"walk":
			last_photo = ""
			for i in 3:
				if not _still(friend, room_at):
					break
				var to := _stroll_spot(rng)
				world.controller.walk_to(to)
				_follow(friend, to)
				await _pause(1.6)
				if i == 1 and _still(friend, room_at):
					await _say(friend, _line(WALK_LINES, c, rng), 1.5)
			if _still(friend, room_at):
				await _say(friend, "Smile!", 0.8)
				last_photo = await world.take_photo()
				if is_inside_tree():
					GameState.add_moment("Photo walk with %s" % who, "We took the long way around %s%s." % [_room_name(), " and took a photo" if last_photo != "" else ""],
						friend_id, "auto", {"hangout": "walk"})   # the photo itself is its own page (photo_mode.gd)
	if not is_inside_tree():   # the world closed mid-hangout
		running = ""
		return
	c = GameState.get_character(friend_id)
	if not c.is_empty():
		MoodSim.company(c, 0.2)
		GameState.save_character(c)
	VarietySave.count("hangouts")
	VarietySave.save()
	await _pause(1.5)
	for p in _props:
		if is_instance_valid(p):
			p.queue_free()
	_props.clear()
	if is_instance_valid(world) and world.life:
		world.life.busy.erase(friend_id)
	running = ""
	finished.emit(kind)


## A short wait that's safe even if the game is closing (the world may be gone after it).
func _pause(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout


## Still in the same room with them (you can walk off any time).
func _still(friend: Variant, room_at: String) -> bool:
	return is_inside_tree() and is_instance_valid(friend) and GameState.current_room_id == room_at


## Somewhere to stroll to: a free cell a few steps away, never a door or another object.
func _stroll_spot(rng: RandomNumberGenerator) -> Vector2i:
	var taken := {}
	for o in world.room.data.get("objects", []):
		taken[world.room.obj_cell(o)] = true
	var me: Vector2i = world.player.cell()
	var best: Vector2i = me
	for i in 30:
		var c: Vector2i = world.room.nav.random_walkable(rng)
		if taken.has(c) or world.room.nav.path(me, c).is_empty():
			continue
		best = c
		if Vector2(c - me).length() >= 2.5:
			break
	return best


func _room_name() -> String:
	return str(world.room.data.get("name", "the room"))


func _line(lines: Array, c: Dictionary, rng: RandomNumberGenerator) -> String:
	var likes := str(c.get("likes", "")).split(",", false)
	var like := likes[rng.randi() % likes.size()].strip_edges() if likes.size() > 0 else "honey"
	return str(lines[rng.randi() % lines.size()]).replace("{like}", like)


## The friend walks to a free cell next to `to`.
func _follow(friend: Variant, to: Vector2i) -> void:
	if not is_instance_valid(friend):
		return
	var near: Vector2i = world.room.nav.best_neighbor(to, friend.cell())
	if near.x < 0:
		return
	var path: Array[Vector2i] = world.room.nav.path(friend.cell(), near)
	var pts: Array[Vector3] = []
	for p in path:
		pts.append(world.room.cell_center(p))
	if not pts.is_empty():
		friend.walk(pts)


## The friend comes and stands beside you (to your left or right on screen, so
## nobody hides behind anybody).
func _together(friend: Variant) -> void:
	if not is_instance_valid(friend):
		return
	var me: Vector2i = world.player.cell()
	var spot := Vector2i(-1, -1)
	var cam := world.get_viewport().get_camera_3d()
	if cam:
		var right := cam.global_transform.basis.x * Vector3(1, 0, 1)
		var step := Vector2i(roundi(right.normalized().x), roundi(right.normalized().z))
		var best := INF
		for c in [me + step, me - step]:
			if world.room.nav.walkable(c) and (c == friend.cell() or not world.room.nav.path(friend.cell(), c).is_empty()):
				var d := Vector2(c - friend.cell()).length()
				if d < best:
					best = d
					spot = c
	if spot.x < 0:
		_follow(friend, me)
	elif spot != friend.cell():
		var path: Array[Vector2i] = world.room.nav.path(friend.cell(), spot)
		var pts: Array[Vector3] = []
		for p in path:
			pts.append(world.room.cell_center(p))
		friend.walk(pts)
	for i in 60:
		if not is_instance_valid(friend) or not friend.is_moving():
			break
		await _pause(0.1)


func _say(friend: Variant, text: String, hold: float) -> void:
	if is_instance_valid(friend):
		friend.say(text, hold + 1.5)
	await _pause(hold)


## Between you, nudged toward the camera so neither of you hides it.
func _tea_spot(friend: Variant) -> Vector3:
	var mid: Vector3 = world.player.position.lerp(friend.position, 0.5)
	var cam := world.get_viewport().get_camera_3d()
	if cam:
		var to_cam := (cam.global_position - mid) * Vector3(1, 0, 1)
		if to_cam.length() > 0.01:
			mid += to_cam.normalized() * 0.7
	return mid


## A little teapot and two cups between you.
func _tea_set(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "TeaSet"
	var pot := SphereMesh.new()
	pot.radial_segments = 12
	pot.rings = 6
	pot.radius = 0.16
	pot.height = 0.26
	var p := MeshInstance3D.new()
	p.mesh = pot
	p.material_override = PlatformObjects.glow(Color("#e8d3b0"), 0.2)
	p.position = Vector3(0, 0.15, 0)
	root.add_child(p)
	var spout := CylinderMesh.new()
	spout.radial_segments = 12
	spout.rings = 1
	spout.top_radius = 0.02
	spout.bottom_radius = 0.035
	spout.height = 0.14
	var s := MeshInstance3D.new()
	s.mesh = spout
	s.material_override = p.material_override
	s.position = Vector3(0.17, 0.2, 0)
	s.rotation_degrees = Vector3(0, 0, -50)
	root.add_child(s)
	for dx in [-0.3, 0.3]:
		var cup := CylinderMesh.new()
		cup.radial_segments = 12
		cup.rings = 1
		cup.top_radius = 0.07
		cup.bottom_radius = 0.05
		cup.height = 0.09
		var m := MeshInstance3D.new()
		m.mesh = cup
		m.material_override = PlatformObjects.glow(Color("#ffb3c7"), 0.2)
		m.position = Vector3(dx, 0.05, 0.12)
		root.add_child(m)
	root.position = Vector3(at.x, 0.0, at.z)
	world.room.get("_content").add_child(root)   # part of this room: it goes if you leave
	return root


## "Make a wish": a little panel (tests set `wish_text` instead).
func _ask_wish() -> String:
	if wish_text != "" or world.main == null or DisplayServer.get_name() == "headless":
		var w := wish_text
		wish_text = ""
		return w
	var panel: Control = load("res://scripts/ui/wish_panel.gd").new()
	world.main.open_panel(panel)
	var result: String = await panel.wished
	return result
