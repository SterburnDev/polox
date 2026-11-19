extends RefCounted
## Dev only (--drive=hitch_probe): how long the things that stall a frame take (opening Settings, the
## menu, Friends, the bag, the World Map; entering Build; travelling; a sync reload), each measured
## three times (the first is the cold one). Prints "[hitch] {json}" lines. Fixtures only.

const WorldMenu := preload("res://scripts/world/world_menu.gd")

var main: Node


func run(main_node: Node) -> void:
	main = main_node
	main.begin_new_world()
	await _wait(1.0)
	_close()
	var g: Node = main.game
	var probes := {
		"settings": func() -> void: main.open_panel(preload("res://scripts/ui/settings_screen.gd").new()),
		"menu": func() -> void: g.open_menu(),
		"friends": func() -> void: main.open_panel(WorldMenu.friends(g)),
		"bag": func() -> void: g.open_bag(),
		"world_map": func() -> void:
			var m: Control = load("res://scripts/ui/world_map_view.gd").new()
			main.open_panel(m)
			m.setup_map(g),
		"build_enter": func() -> void: g.build.enter(),
		"sync_reload": func() -> void: main.reload_world_from_disk(),
		"pause_resume": func() -> void:
			main.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
			main.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED),
		"focus_out_in": func() -> void:
			main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN),
	}
	for name in probes:
		var times: Array = []
		for i in 3:
			_close()
			if g.build.active:
				g.build.exit()
			await _wait(0.4)
			var t0 := Time.get_ticks_usec()
			probes[name].call()
			await main.get_tree().process_frame   # the frame that shows it
			times.append(snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1))
			g = main.game
		print("[hitch] ", JSON.stringify({"what": name, "ms": times}))
	if g.build.active:
		g.build.exit()
	_close()
	# Build entry by part (the shell is most of it).
	var b: Node = g.build
	var parts := {}
	var t := Time.get_ticks_usec()
	var shell: Control = load("res://scripts/builder/editor_shell.gd").new()
	parts["new"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	main.ui.add_child(shell)
	parts["add_child"] = (Time.get_ticks_usec() - t) / 1000.0
	b.active = true
	b.shell = shell
	t = Time.get_ticks_usec()
	shell.bind(b)
	parts["bind"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	b.state_changed.emit()
	parts["state_changed"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	await main.get_tree().process_frame
	parts["first_frame"] = (Time.get_ticks_usec() - t) / 1000.0
	print("[hitch] ", JSON.stringify({"what": "build_parts", "ms": parts}))
	b.exit()
	await _wait(0.4)
	# load_room alone, and the frame after it (deferred work).
	var others: Array = Array(SaveManager.list_rooms()).filter(func(id): return str(id) != GameState.current_room_id)
	if not others.is_empty():
		var from := GameState.current_room_id
		for target in [str(others[0]), from]:
			var t1 := Time.get_ticks_usec()
			main.game.load_room(target, GameState.current_room_id)
			var t2 := Time.get_ticks_usec()
			await main.get_tree().process_frame
			var t3 := Time.get_ticks_usec()
			await main.get_tree().process_frame
			var t4 := Time.get_ticks_usec()
			print("[hitch] ", JSON.stringify({"what": "load_room " + target, "call_ms": (t2 - t1) / 1000.0, "next_frame_ms": (t3 - t2) / 1000.0, "frame_after_ms": (t4 - t3) / 1000.0}))
	# Travel: the longest single frame while going to another place and back.
	var rooms: Array = Array(SaveManager.list_rooms()).filter(func(id): return str(id) != GameState.current_room_id)
	if not rooms.is_empty():
		var home := GameState.current_room_id
		for target in [str(rooms[0]), home, str(rooms[0])]:
			var s := {"worst": 0.0, "last": Time.get_ticks_usec()}   # a Dictionary: lambdas copy plain locals
			var watch := func() -> void:
				var now := Time.get_ticks_usec()
				var ms: float = (now - s.last) / 1000.0
				s.worst = maxf(s.worst, ms)
				s.last = now
				if ms > 40.0:
					print("[slow] %.1f ms  process %.1f  physics %.1f  draw_calls %d  objects %d" % [ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
						Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
						Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
			main.get_tree().process_frame.connect(watch)
			await main.game.go_to_room(target)
			await _wait(0.5)
			main.get_tree().process_frame.disconnect(watch)
			print("[hitch] ", JSON.stringify({"what": "travel to " + target, "worst_frame_ms": snappedf(s.worst, 0.1)}))


func _close() -> void:
	main._close_all_panels()


func _wait(s: float) -> void:
	await main.get_tree().create_timer(s).timeout
