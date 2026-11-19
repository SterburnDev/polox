extends "res://tests/test_case.gd"
## Update 9: the Movement Lab courses and measured platform physics. Each course is complete and
## finishable with a Polox jump, they're joined door to door, and they play with your chosen profile.
## The three profiles measured on real physics frames at 30, 60 and 120 Hz: speeding up, coasting to a
## stop, jump height (and Classic's jump cut), jump length; a launch at speed never passes a thin
## wall; and in the game, a course pauses with a panel open and nothing carries over on leaving.

const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const PlatformWorld := preload("res://scripts/platform/platform_world.gd")
const PlatformBody := preload("res://scripts/platform/platform_body.gd")
const Profiles := preload("res://scripts/platform/platform_profiles.gd")
const JumpReach := preload("res://scripts/platform/jump_reach.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const TilesetFactory := preload("res://scripts/world/tileset_factory.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")

var main: Node


func _objs(r: Dictionary, type: String) -> Array:
	return (r.get("objects", []) as Array).filter(func(o): return str(o.get("type", "")) == type)


func _reach(r: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	return JumpReach.reachable(r, a).any(func(e): return e[0] == b)


func test_movement_lab_courses_are_linked_and_finishable() -> void:
	fresh_save_root()
	StarterContent.create_world("Lab", "Sam")
	GameState.settings["platform_profile"] = "polox"
	var lab := TemplateFactory.movement_lab()
	eq(lab.size(), 7, "seven courses")
	for i in TemplateFactory.LAB.size():
		var id: String = TemplateFactory.LAB[i]
		var r: Dictionary = lab[id]
		eq(_objs(r, "platform_pillar").size(), 1, "%s has a pillar" % id)
		eq(str(r.get("physics_profile", "")), "player", "%s plays with your chosen profile" % id)
		eq(Profiles.plane(r), "" if id == "lab_corners" else "x", "%s course plane" % id)
		var targets: Array = _objs(r, "door").map(func(o): return str(o.door_target))
		if i + 1 < TemplateFactory.LAB.size():
			check(TemplateFactory.LAB[i + 1] in targets, "%s has a door on to %s" % [id, TemplateFactory.LAB[i + 1]])
		if i > 0:
			check(TemplateFactory.LAB[i - 1] in targets, "%s has a door back" % id)
		check(not r.has("lab_exit") and not r.has("lab_entry"), "no build notes left in %s" % id)
	# Jumps: gaps 1, 2 and 3 wide, then one block up.
	var jumps: Dictionary = lab.lab_jumps
	for hop in [[5, 7], [9, 12], [14, 18], [20, 21]]:
		check(_reach(jumps, Vector2i(hop[0], 2), Vector2i(hop[1], 2)), "jumps: %d -> %d is one Polox jump" % hop)
	check(not _reach(jumps, Vector2i(14, 2), Vector2i(20, 2)), "but not two gaps at once")
	# Landing: post to post, each 1 up at most.
	var landing: Dictionary = lab.lab_landing
	var route := [2, 5, 8, 11, 14, 17, 21]
	for k in range(1, route.size()):
		check(_reach(landing, Vector2i(route[k - 1], 2), Vector2i(route[k], 2)), "landing: %d -> %d" % [route[k - 1], route[k]])
	eq(PlatformWorld.top_at(landing, 11, 2), 2.0, "the middle posts are 2 high")
	# Ledges: up through the ledges, along the mover, onto the deck.
	var ledges: Dictionary = lab.lab_ledges
	var steps: Array = [[3, 0]]
	for o in _objs(ledges, "one_way"):
		steps.append([int(o.pos[0]), int(o.elev)])
	var mover: Dictionary = _objs(ledges, "mover")[0]
	steps.append([int(mover.pos[0]), int(mover.elev)])
	steps.append([int(mover.pos[0]) + int(mover.dx), int(mover.elev)])
	steps.append([17, int(PlatformWorld.top_at(ledges, 17, 2))])
	var reach := Profiles.jump_reach("polox")
	var ok := true
	for k in range(1, steps.size()):
		if k == steps.size() - 2:
			continue   # riding the mover
		if int(steps[k][1]) - int(steps[k - 1][1]) > int(reach.x) or absi(int(steps[k][0]) - int(steps[k - 1][0])) > int(reach.y):
			ok = false
	check(ok, "every ledge step is a Polox jump: %s" % str(steps))
	# Slopes: ramps up and down, no wall to jump.
	var slopes: Dictionary = lab.lab_slopes
	eq(PlatformWorld.top_at(slopes, 16, 2), 2.0, "the second hill is 2 high")
	# Corners: walls two high, a three-wide corridor through each gap.
	var corners: Dictionary = lab.lab_corners
	eq(PlatformWorld.top_at(corners, 5, 3), 2.0, "a corner wall")
	eq(PlatformWorld.top_at(corners, 12, 3), 0.0, "and the gap round it")
	GameState.settings["platform_profile"] = "classic"
	eq(str(Profiles.resolve(jumps).id), "classic", "Classic plays on the straight courses")
	var free := Profiles.resolve(corners)
	check(str(free.id) == "polox" and str(free.note) != "", "the 3D corners play as Polox and say why")
	# The Library has it.
	TilesetFactory.ensure_builtin()
	TemplateFactory.ensure_builtin()
	var Templates := preload("res://scripts/world/templates.gd")
	check(Templates.ids().has("movement_lab"), "the Movement Lab is in the Library")
	# Added to a world the way the editor adds it: new ids, doors re-joined, the course settings kept.
	var ids := Templates.new_level("movement_lab")
	eq(ids.size(), 7, "seven new places")
	var joined := true
	for rid in ids:
		var room := SaveManager.load_room(rid)
		for d in _objs(room, "door"):
			joined = joined and str(d.door_target) in ids
		if str(room.get("physics_profile", "")) != "player":
			joined = false
	check(joined, "every door leads to another course in this world, and each keeps its profile setting")
	GameState.settings["platform_profile"] = "polox"


## A long, empty floor (w blocks along x), plus `tiles`.
func _floor(w: int, tiles: Array = []) -> Dictionary:
	return {"size": {"w": w, "d": 5, "h": 4}, "tiles": tiles, "objects": [], "tile_layers": TileLayers.default_layers()}


func _ticks(n: int) -> void:
	for i in n:
		await tree.physics_frame


## Measures one profile at one tick rate on a long flat floor.
func _measure(profile: String, hz: int) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var pw: Node3D = PlatformWorld.new()
	tree.root.add_child(pw)
	pw.build(_floor(160))
	var body: CharacterBody3D = PlatformBody.new()
	body.world = pw
	tree.root.add_child(body)
	body.teleport(Vector3(4.5, 0.05, 2.5))
	body.set_profile(profile, Vector3.RIGHT)
	await _ticks(hz / 4)
	var out := {}
	var top := float(Profiles.values(profile).speed)
	# Speeding up from rest (running) for two seconds.
	var x0 := body.global_position.x
	body.run = true
	body.move_dir = Vector3.RIGHT
	var t90 := -1.0
	for i in 2 * hz:
		await tree.physics_frame
		if t90 < 0.0 and absf(body.velocity.x) >= 0.9 * top:
			t90 = float(i + 1) / hz
	out["t90"] = t90
	out["run2"] = body.global_position.x - x0
	# Letting go: coasting to a stop.
	body.move_dir = Vector3.ZERO
	var x1 := body.global_position.x
	for i in 6 * hz:
		await tree.physics_frame
		if absf(body.velocity.x) < 0.05:
			break
	out["coast"] = body.global_position.x - x1
	# A standing jump held all the way, then one let go early.
	for held in [true, false]:
		body.velocity = Vector3.ZERO
		await _ticks(hz / 6)
		var y0 := body.global_position.y
		body.press_jump()
		var apex := y0
		for i in 2 * hz:
			await tree.physics_frame
			apex = maxf(apex, body.global_position.y)
			if not held and i == int(hz * 0.05):
				body.release_jump()   # a tap
			if i > 3 and body.is_on_floor():
				break
		out["apex" if held else "cut"] = apex - y0
	# A running jump's length.
	body.move_dir = Vector3.RIGHT
	await _ticks(int(1.5 * hz))
	var jx := body.global_position.x
	body.press_jump()
	for i in 3 * hz:
		await tree.physics_frame
		if i > 3 and body.is_on_floor():
			break
	out["length"] = body.global_position.x - jx
	body.queue_free()
	pw.queue_free()
	await frames(2)
	return out


func test_profiles_measured_at_30_60_and_120_hz() -> void:
	var rates := [30, 60, 120]
	var all := {}
	for profile in Profiles.IDS:
		all[profile] = {}
		for hz in rates:
			var m: Dictionary = await _measure(profile, hz)
			all[profile][hz] = m
			print("    %s @%d Hz: 90%% speed %.2f s, 2 s run %.2f, coast %.2f, jump %.2f (let go early %.2f), running jump %.2f" % [profile, hz, m.t90, m.run2, m.coast, m.apex, m.cut, m.length])
	Engine.physics_ticks_per_second = 60
	for profile in Profiles.IDS:
		var a: Dictionary = all[profile][30]
		var c: Dictionary = all[profile][120]
		for key in ["run2", "coast", "apex", "length"]:
			var tol := 0.06 * maxf(1.0, absf(float(c[key]))) + 0.1
			check(absf(float(a[key]) - float(c[key])) <= tol, "%s %s agrees at 30 and 120 Hz (%.2f vs %.2f)" % [profile, key, a[key], c[key]])
		check(absf(float(a.t90) - float(c.t90)) <= 1.0 / 30.0 + 0.02, "%s reaches speed at the same time at 30 and 120 Hz" % profile)
	var p: Dictionary = all.polox[60]
	var k: Dictionary = all.classic[60]
	var v: Dictionary = all.adventure[60]
	# Different rules, not different names.
	check(k.t90 > p.t90 * 3.0, "Classic builds speed slowly (%.2f s vs Polox %.2f s)" % [k.t90, p.t90])
	check(k.coast > p.coast * 5.0 and v.coast > p.coast * 3.0, "the momentum profiles coast on (Classic %.2f, Adventure %.2f, Polox %.2f)" % [k.coast, v.coast, p.coast])
	check(absf(p.cut - p.apex) < 0.05, "Polox jumps are always full height")
	check(k.cut < k.apex * 0.6 and v.cut < v.apex * 0.6, "a tap cuts a momentum jump short (Classic %.2f of %.2f, Adventure %.2f of %.2f)" % [k.cut, k.apex, v.cut, v.apex])
	check(k.cut > 0.25 and v.cut > 0.25, "but still hops")
	# The exact jump height (v^2 / 2g) at every rate, not a frame-rate-dependent overshoot.
	for profile in Profiles.IDS:
		var pv := Profiles.values(profile)
		var exact := float(pv.jump) * float(pv.jump) / (2.0 * float(pv.gravity))
		for hz in rates:
			check(absf(float(all[profile][hz].apex) - exact) < 0.03, "%s jump height at %d Hz is %.3f (exact %.3f)" % [profile, hz, all[profile][hz].apex, exact])
	check(v.t90 > p.t90 and v.t90 < k.t90, "Adventure accelerates between the two")
	check(k.length > p.length and v.length > p.length, "momentum running jumps carry further")


func test_a_launch_at_speed_never_passes_a_thin_wall() -> void:
	var tiles: Array = []
	for z in 5:
		for y in 3:
			tiles.append({"x": 40, "z": z, "y": y, "type": "cube", "color": "#5b4b8a"})
	for profile in Profiles.IDS:
		for hz in [30, 60, 120]:
			Engine.physics_ticks_per_second = hz
			var pw: Node3D = PlatformWorld.new()
			tree.root.add_child(pw)
			pw.build(_floor(60, tiles))
			var body: CharacterBody3D = PlatformBody.new()
			body.world = pw
			tree.root.add_child(body)
			body.teleport(Vector3(4.5, 0.05, 2.5))
			body.set_profile(profile, Vector3.RIGHT)
			await _ticks(hz / 4)
			if profile != "polox":
				body.move_dir = Vector3.RIGHT
				body.roll_or_charge()   # standing: charge...
				await _ticks(hz)
				body.release_charge()   # ...and launch
			body.velocity.x = 45.0          # and then far faster than any profile's top speed
			body.run = true
			body.move_dir = Vector3.RIGHT
			var furthest := 0.0
			for i in 3 * hz:
				await tree.physics_frame
				furthest = maxf(furthest, body.global_position.x)
			check(furthest < 40.0, "%s @%d Hz: stopped by the wall (furthest x %.2f)" % [profile, hz, furthest])
			body.queue_free()
			pw.queue_free()
			await frames(2)
	Engine.physics_ticks_per_second = 60


func test_a_course_in_the_game_pauses_resumes_and_leaves_cleanly() -> void:
	fresh_save_root()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(5)
	var g: Node = main.game
	GameState.settings["platform_profile"] = "classic"
	var lab := TemplateFactory.movement_lab()
	for id in lab:
		SaveManager.save_room(lab[id])
	g.load_room("lab_ledges")
	await frames(3)
	var pillar: Dictionary = _objs(g.room.data, "platform_pillar")[0]
	g.platform.activate(pillar)
	for i in 120:
		await frames(1)
		if g.platform.active and not g.platform.starting:
			break
	await frames(3)
	check(g.platform.active, "the pillar starts the course")
	eq(g.platform.body.profile, "classic", "with your chosen profile (the course has a plane)")
	var ab: Node3D = g.platform.pw.movers[0][0]
	var at := ab.position
	await _ticks(20)
	check(ab.position.distance_to(at) > 0.05, "the moving platform moves")
	# A panel opens: everything holds still.
	var panel := Control.new()
	main.open_panel(panel)
	g.platform.test_input = Vector2(1, 0)   # holding a direction behind the panel
	await _ticks(2)
	var held_at := ab.position
	var body_at: Vector3 = g.platform.body.global_position
	await _ticks(30)
	check(g.platform.body.frozen and g.platform.pw.paused, "paused while the panel is open")
	check(ab.position.distance_to(held_at) < 0.001 and g.platform.body.global_position.distance_to(body_at) < 0.001, "nothing moves")
	g.platform.test_input = Vector2.ZERO
	panel.queue_free()
	await _ticks(30)
	check(not g.platform.body.frozen and not g.platform.pw.paused, "unpaused when it closes (frozen %s, panels %d)" % [g.platform.body.frozen, main.panels.size()])
	check(ab.position.distance_to(held_at) > 0.02, "the platform carries on (moved %.3f)" % ab.position.distance_to(held_at))
	# Leaving and coming back: no speed carried over.
	g.platform.body.velocity = Vector3(9, 0, 0)
	g.platform.leave()
	await frames(3)
	check(not g.platform.active, "left the course")
	g.platform.begin_here()
	await frames(2)
	var v: Vector3 = g.platform.body.velocity
	check(Vector2(v.x, v.z).length() < 0.01 and v.y > -1.0, "a fresh start, no leftover speed (%s)" % str(v))
	g.platform.leave()
	GameState.settings["platform_profile"] = "polox"
	main.queue_free()
	await frames(3)
