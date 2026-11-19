extends RefCounted
## The soak run (`--drive=soak`, dev only): plays for a while the way a person on a phone does, at random,
## and watches for what makes a game die on a phone: errors, memory or nodes that only grow, and frames that
## freeze. Walks and taps on the world, opens every kind of screen and presses its buttons (never ones that
## leave the game or touch the network: see SKIP), talks to friends, travels between places and between the
## worlds, reloads the world the way a phone sync does, pauses and resumes like Android, turns the screen
## sideways and back, builds, takes photos, fights a battle.
##   --soak-minutes=N (default 10)   --soak-seed=S   --soak-out=<summary .json>
## Prints "[soak] t=..." every 15 s and "[soak] done ..." at the end; the summary has every error seen.

const WorldMenu := preload("res://scripts/world/world_menu.gd")

## Buttons a random press must never touch: they leave the game, open other programs or the browser, touch
## the network or the PC's settings, or end the session.
const SKIP := ["sign in", "street view", "folder", "browser", "quit", "install", "build the app", "firewall", "export",
	"open in", "website", "tailscale", "serve", "allow", "download", "phone link", "turn on", "start phone", "pair",
	"share", "title screen", "look it up", "look again", "map my streets", "check now", "test connection", "doctor",
	"plan b", "fetch", "restore", "import", "update", "ask claude", "ask gemini", "sync", "send report", "copy",
	"map my home", "forget"]   # (the Survey is a full-screen flow the drive can't leave; forgetting deletes the home)

var main: Node
var minutes := 10.0
var only: PackedStringArray = []   # --soak-only=travel,screen: just these actions (to find what a leak comes from)
var rng := RandomNumberGenerator.new()
var errlog: ErrLog
var actions := 0
var counts := {}
var samples: Array = []
var worst_frame_ms := 0.0
var _frames := 0
var _slow_frames := 0
var _t0 := 0
var _last_frame := 0
var _doing := "start"
var slow_log: Array = []       # [{ms, during, room, t}] for frames over 100 ms
var stuck := ""                # what held the game when a transition never ended ("" = nothing did)
var _busy_since := 0           # since when the game has been in a transition (msec; 0 = not in one)
const STUCK_MS := 20000        # a transition longer than this is a hang, not a slow animation


class ErrLog extends Logger:
	var mutex := Mutex.new()
	var errors: Array = []
	var warnings := 0
	var total := 0
	var seen := {}

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		mutex.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			total += 1
			var key := "%s:%d" % [file, line]
			seen[key] = int(seen.get(key, 0)) + 1
			if int(seen[key]) <= 2 and errors.size() < 80:
				var bt := ""
				for b in script_backtraces:
					bt += b.format(0, 2)
				errors.append({"where": key, "function": function, "what": (rationale if rationale != "" else code).left(300), "trace": bt.left(800)})
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func run(main_node: Node) -> void:
	main = main_node
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--soak-minutes="):
			minutes = maxf(0.2, a.trim_prefix("--soak-minutes=").to_float())
		elif a.begins_with("--soak-seed="):
			rng.seed = a.trim_prefix("--soak-seed=").to_int()
		elif a.begins_with("--soak-only="):
			only = a.trim_prefix("--soak-only=").split(",", false)
	if rng.seed == 0:
		rng.randomize()
	errlog = ErrLog.new()
	OS.add_logger(errlog)
	print("[soak] seed=%d minutes=%.1f window=%s renderer=%s" % [rng.seed, minutes, str(DisplayServer.window_get_size()), RenderingServer.get_current_rendering_method()])
	_start_world()
	await _wait(1.0)
	_make_home()
	_t0 = Time.get_ticks_msec()
	_last_frame = _t0
	main.get_tree().process_frame.connect(_on_frame)
	var next_sample := 0.0
	_sample()
	while _elapsed() < minutes * 60.0:
		if main.game == null:
			_start_world()
			await _wait(1.0)
		await _act()
		actions += 1
		if _busy_since > 0 and Time.get_ticks_msec() - _busy_since > STUCK_MS:
			# A transition that never finishes freezes the player for good: say what holds the game, then stop.
			stuck = _stuck_report()
			print("[soak] STUCK for %d s: %s" % [int(STUCK_MS * 0.001), stuck])
			break
		if _elapsed() >= next_sample:
			next_sample = _elapsed() + 15.0
			_sample()
	_sample()
	main.get_tree().process_frame.disconnect(_on_frame)
	OS.remove_logger(errlog)
	_report()


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _wait(s: float) -> void:
	await main.get_tree().create_timer(s).timeout


func _on_frame() -> void:
	var now := Time.get_ticks_msec()
	var ms := float(now - _last_frame)
	_last_frame = now
	_frames += 1
	if ms > 250.0:
		_slow_frames += 1
	# Hitches from 100 ms: on a phone the same work takes two to three times as long, so a
	# tenth of a second here is a visible stall there.
	if ms > 100.0 and slow_log.size() < 300:
		slow_log.append({"ms": int(ms), "during": _doing, "room": GameState.current_room_id, "t": snappedf(_elapsed(), 0.1)})
		print("[soak] slow frame %d ms during %s in %s" % [int(ms), _doing, GameState.current_room_id])
	worst_frame_ms = maxf(worst_frame_ms, ms)


func _start_world() -> void:
	if SaveManager.has_world():
		main.start_game()   # the world in the save folder (a copy of a real one, for a realistic run)
	else:
		main.begin_new_world()


## A made-up home (the tests' recorded lookup and town), so the Light World is there to walk through.
func _make_home() -> void:
	if load("res://scripts/home/home_store.gd").exists():
		return
	var answers := {"address": "12 Example Lane, Testville", "home_type": "house", "floors": 2, "basement": true,
		"rooms": {"bedroom": 3, "bathroom": 2, "kitchen": 1, "living": 1, "dining": 1, "laundry": 1},
		"my_room": {"floor": 1, "where": "front", "bed": "single", "desk": true, "view": "street"}, "radius": 250}
	var fixture := ProjectSettings.globalize_path("res://tests/fixtures/home_research_madeup.json")
	var found: Dictionary = load("res://scripts/home/home_model.gd").clean_research(JSON.parse_string(FileAccess.get_file_as_string(fixture)))
	load("res://scripts/home/home_mapper.gd").build_home(answers, found, "claude_code")
	var osm: Variant = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://tests/fixtures/osm_madeup_town.json")))
	var extract: Dictionary = load("res://scripts/home/osm.gd").clean(osm if osm is Dictionary else {}, 10.0, 10.0, 250)
	load("res://scripts/home/home_mapper.gd").build_streets(extract, answers)


func _g() -> Node:
	return main.game


func _count(k: String) -> void:
	counts[k] = int(counts.get(k, 0)) + 1
	_doing = k


# --- Actions --------------------------------------------------------------------------------------

func _act() -> void:
	var g := _g()
	if g == null:
		return
	if g.get("_transitioning") or (g.dark and g.dark.busy):
		if _busy_since == 0:
			_busy_since = Time.get_ticks_msec()
		await _wait(0.3)
		return
	_busy_since = 0
	var r := rng.randf()
	if not only.is_empty():
		var pick := only[rng.randi() % only.size()]
		r = float({"tap": 0.1, "screen": 0.3, "talk": 0.45, "travel": 0.52, "sync_reload": 0.6, "lifecycle": 0.68, "rotate": 0.74,
			"build": 0.8, "photo": 0.84, "battle": 0.88, "hud": 0.93, "time": 0.97}.get(pick, 0.1))
	if r < 0.22:
		await _tap_world()
	elif r < 0.40:
		await _screen()
	elif r < 0.48:
		await _talk()
	elif r < 0.56:
		await _travel()
	elif r < 0.64:
		await _sync_reload()
	elif r < 0.71:
		await _lifecycle()
	elif r < 0.76:
		await _rotate()
	elif r < 0.82:
		await _build()
	elif r < 0.86:
		_count("photo")
		g.take_photo()
		await _wait(0.4)
	elif r < 0.90:
		await _battle()
	elif r < 0.95:
		await _press_hud()
	else:
		_count("time")
		g.daylight.hour_override = rng.randf_range(0.0, 24.0)
		g.daylight.apply(true)
		g.refresh_weather(true)
		await _wait(0.5)


func _tap_world() -> void:
	_count("tap")
	var g := _g()
	_close_all()
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	for i in rng.randi_range(1, 4):
		g.controller.click(Vector2(rng.randf_range(0.05, 0.95) * vs.x, rng.randf_range(0.15, 0.85) * vs.y))
		await _wait(rng.randf_range(0.2, 1.4))


func _screens() -> Array:
	var g := _g()
	return [
		func(): return preload("res://scripts/ui/settings_screen.gd").new(),
		func(): return WorldMenu.make(g),
		func(): return WorldMenu.friends(g),
		func(): return WorldMenu.bag(g),
		func(): return WorldMenu.sheet(g, rng.randi_range(0, 2)),
		func(): return WorldMenu.room_list(g),
		func(): return preload("res://scripts/ui/memory_book.gd").new(),
		func(): return preload("res://scripts/ui/dreams_board.gd").new(),
		func(): return preload("res://scripts/ui/friendship_web.gd").new(),
		func(): return preload("res://scripts/ui/log_viewer.gd").new(),
		func(): return preload("res://scripts/ui/world_bible_editor.gd").new(),
		func(): return WorldMenu.workshop(g),
	]


func _screen() -> void:
	_count("screen")
	_close_all()
	var g := _g()
	var which := rng.randi_range(0, 15)
	var p: Control = null
	if which < 12:
		var maker: Callable = _screens()[which]
		p = maker.call()
		main.open_panel(p)
	elif which == 12:
		g.open_world_sheet()
	elif which == 13:
		var m: Control = load("res://scripts/ui/world_map_view.gd").new()
		main.open_panel(m)
		m.setup_map(g)
	elif which == 14 and load("res://scripts/home/home_store.gd").exists():
		var h: Control = load("res://scripts/home/map_home_panel.gd").new()
		main.open_panel(h)
		h.setup_home(g)
	else:
		g.open_menu()
	_doing = "screen %d (%s)" % [which, p.get_script().resource_path.get_file() if p and p.get_script() else "menu/sheet/map"]
	await _wait(rng.randf_range(0.3, 1.0))
	for i in rng.randi_range(0, 4):
		await _press_random_button()
	await _wait(rng.randf_range(0.2, 0.8))
	_close_all()


func _press_random_button() -> void:
	var buttons: Array = []
	for b in main.ui.find_children("*", "BaseButton", true, false) + main.toast_layer().find_children("*", "BaseButton", true, false):
		if not is_instance_valid(b) or not (b as BaseButton).is_visible_in_tree() or (b as BaseButton).disabled:
			continue
		var t := (str(b.get("text")) + " " + str(b.name) + " " + str(b.tooltip_text)).to_lower()
		if SKIP.any(func(s): return t.contains(str(s))):
			continue
		buttons.append(b)
	if buttons.is_empty():
		return
	var b: BaseButton = buttons[rng.randi() % buttons.size()]
	_count("press")
	_doing = "press '%s' (%s) in %s" % [str(b.get("text")).left(40), b.name, str(b.get_parent().name) if b.get_parent() else ""]
	if b is OptionButton and (b as OptionButton).item_count > 0:
		(b as OptionButton).select(rng.randi() % (b as OptionButton).item_count)
		(b as OptionButton).item_selected.emit((b as OptionButton).selected)
	elif b.toggle_mode:
		b.button_pressed = not b.button_pressed
	else:
		b.pressed.emit()
	await _wait(rng.randf_range(0.15, 0.7))


func _press_hud() -> void:
	_count("hud")
	_close_all()
	await _press_random_button()
	await _wait(0.5)
	_close_all()


func _talk() -> void:
	_count("talk")
	_close_all()
	var g := _g()
	if g.actors.is_empty():
		return
	var id := str(g.actors.keys()[rng.randi() % g.actors.size()])
	g.approach_character(id)
	await _wait(2.0)
	if g.dialogue and g.dialogue.visible:
		for line in ["hi!", "what's up?", "tell me a story"].slice(0, rng.randi_range(1, 3)):
			for i in 8:
				if g.dialogue.state == "input":
					break
				g.dialogue.advance()
			if g.dialogue.state != "input":
				break
			g.dialogue.input.text = line
			g.dialogue._send()
			await _wait(rng.randf_range(0.6, 1.5))
		if rng.randf() < 0.3:
			await g.talk.give_gift("fresh_cookies")
		g.dialogue.close_box()
	await _wait(0.3)


func _travel() -> void:
	_count("travel")
	_close_all()
	var g := _g()
	var light: bool = load("res://scripts/world/realms.gd").is_light(g.room.data)
	var r := rng.randf()
	if r < 0.3:
		if light:
			await g.dark.go_dark({})
		else:
			await g.dark.go_light({})
	else:
		var ids: Array = SaveManager.list_rooms() if not light else SaveManager.list_light_rooms()
		if ids.is_empty():
			return
		await g.go_to_room(str(ids[rng.randi() % ids.size()]))
	await _wait(0.5)


## What a phone does after a sync pulled the PC's changes (and the PC after the phone pushed).
func _sync_reload() -> void:
	_count("sync_reload")
	main.reload_world_from_disk()
	await _wait(rng.randf_range(0.2, 1.0))


## Android: the app goes to the background and comes back; the notification shade (focus out and in).
func _lifecycle() -> void:
	_count("lifecycle")
	var pairs := [[Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_IN],
		[Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_RESUMED]]
	var p: Array = pairs[rng.randi() % pairs.size()]
	main.propagate_notification(int(p[0]))
	await _wait(rng.randf_range(0.1, 1.5))
	main.propagate_notification(int(p[1]))
	await _wait(0.3)


func _rotate() -> void:
	_count("rotate")
	if DisplayServer.get_name() == "headless":
		return
	var s := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(s.y, s.x))
	await _wait(rng.randf_range(0.5, 2.0))
	DisplayServer.window_set_size(s)
	await _wait(0.5)


func _build() -> void:
	_count("build")
	_close_all()
	var g := _g()
	if load("res://scripts/world/realms.gd").is_light(g.room.data):
		return
	g.build.enter()
	await _wait(0.3)
	g.build.set_piece(["cube", "slab", "ramp"][rng.randi() % 3])
	g.build.cursor = Vector2i(rng.randi_range(1, maxi(1, g.room.w - 2)), rng.randi_range(1, maxi(1, g.room.d - 2)))
	g.build.apply({})
	await _wait(0.3)
	if rng.randf() < 0.6:
		g.build.undo()
	g.build.exit()
	await _wait(0.3)


func _battle() -> void:
	_count("battle")
	_close_all()
	var g := _g()
	if g.actors.is_empty() or load("res://scripts/world/realms.gd").is_light(g.room.data):
		return
	var foe := str(g.actors.keys()[0])
	var BattleData := preload("res://scripts/battle/battle_data.gd")
	g.battles.start(BattleData.from_template("star_shower", GameState.get_character(foe)), [])
	for i in 60:
		await _wait(0.2)
		var scr: Control = g.battles.screen
		if scr and str(scr.phase) == "review":
			scr._resolve()
		if scr and str(scr.phase) == "fight_bar":
			scr.press_fight()   # (FIGHT's timing press comes when the turn begins)
		if scr and str(scr.phase) == "menu":
			if rng.randf() < 0.7:
				scr.state.enemies[0].mercy = int(scr.state.enemies[0].mercy_max)
				scr.choose("spare")
			else:
				scr.choose(["fight", "act", "item", "spare"][rng.randi() % 4])
		if g.battles.screen == null:
			break
	await _wait(0.5)


func _close_all() -> void:
	if main.has_method("_close_all_panels"):
		main._close_all_panels()
	var g := _g()
	if g and g.dialogue and g.dialogue.visible:
		g.dialogue.close_box()


# --- Watching -------------------------------------------------------------------------------------

func _sample() -> void:
	var s := {
		"t": snappedf(_elapsed(), 0.1),
		"actions": actions,
		"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"tex_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"errors": errlog.total,
		"slow_frames": _slow_frames,
		"room": GameState.current_room_id,
	}
	samples.append(s)
	print("[soak] t=%ds actions=%d mem=%.1fMB objects=%d nodes=%d orphans=%d resources=%d tex=%.1fMB video=%.1fMB errors=%d slow=%d worst=%dms room=%s" % [
		int(s.t), s.actions, s.mem_mb, s.objects, s.nodes, s.orphans, s.resources, s.tex_mb, s.video_mb, s.errors, s.slow_frames, int(worst_frame_ms), s.room])


## What is holding the game while a transition never ends: the flags, the open layers and the running tweens.
func _stuck_report() -> String:
	var g := _g()
	var parts: PackedStringArray = []
	parts.append("room=%s" % GameState.current_room_id)
	parts.append("last action=%s" % _doing)
	if g == null:
		return "; ".join(parts) + "; no world"
	parts.append("_transitioning=%s" % str(g.get("_transitioning")))
	if g.dark:
		parts.append("dark.busy=%s last_moment=%s" % [str(g.dark.busy), str(g.dark.get("last_moment"))])
	parts.append("panels=%d" % main.panels.size())
	var kids: PackedStringArray = []
	for c in main.toast_layer().get_children():
		kids.append("%s(%s)" % [c.name, c.get_script().resource_path.get_file() if c.get_script() else c.get_class()])
	parts.append("toast layer: [%s]" % ", ".join(kids))
	var tweens := main.get_tree().get_processed_tweens()
	parts.append("tweens=%d" % tweens.size())
	parts.append("talking=%s battle=%s build=%s" % [str(g.talk.talking_to), str(g.battles.screen != null), str(g.build.active)])
	return "; ".join(parts)


func _report() -> void:
	var first: Dictionary = samples[1] if samples.size() > 2 else samples[0]
	var last: Dictionary = samples.back()
	var out := {"seed": rng.seed, "minutes": minutes, "actions": actions, "counts": counts, "errors_total": errlog.total, "stuck": stuck,
		"warnings": errlog.warnings, "errors": errlog.errors, "error_places": errlog.seen, "samples": samples, "slow_log": slow_log,
		"worst_frame_ms": worst_frame_ms, "slow_frames": _slow_frames, "frames": _frames}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--soak-out="):
			var f := FileAccess.open(a.trim_prefix("--soak-out="), FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(out, "  "))
				f.close()
	print("[soak] done actions=%d errors=%d (%d places) mem %.1f->%.1fMB nodes %d->%d orphans %d->%d objects %d->%d slow_frames=%d worst=%dms stuck=%s counts=%s" % [
		actions, errlog.total, errlog.seen.size(), first.mem_mb, last.mem_mb, first.nodes, last.nodes, first.orphans, last.orphans,
		first.objects, last.objects, _slow_frames, int(worst_frame_ms), "no" if stuck == "" else "YES", JSON.stringify(counts)])
