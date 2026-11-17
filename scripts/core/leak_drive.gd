extends RefCounted
## Dev only (--drive=leak_cycles): each kind of action done many times over, coming back to the same
## place every time, and what stays behind measured. A leak grows with the count; a cache stops
## growing after the warm-up. Run it on the phone's renderer (--rendering-driver opengl3) so video
## memory counts. One "[leak] {json}" line per action (growth per cycle); --leak-out=<file.json>.
##   --leak-cycles=N (default 12)   --leak-only=travel,street,...
## Uses soak_drive.gd's actions and its made-up home (fixtures only).

const PlayerLook := preload("res://scripts/characters/player_look.gd")
const ItemArt := preload("res://scripts/items/item_art.gd")
const SilhouettePainter := preload("res://scripts/world/silhouette_painter.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")

var main: Node
var soak: RefCounted
var cycles := 12
var settle_s := 4.0                 # long enough for toasts and fades to be gone before measuring
var only: PackedStringArray = []
var results: Array = []


func run(main_node: Node) -> void:
	main = main_node
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--leak-out="):
			out_path = a.trim_prefix("--leak-out=")
		elif a.begins_with("--leak-cycles="):
			cycles = maxi(2, a.trim_prefix("--leak-cycles=").to_int())
		elif a.begins_with("--leak-only="):
			only = a.trim_prefix("--leak-only=").split(",", false)
		elif a.begins_with("--leak-settle="):
			settle_s = maxf(0.5, a.trim_prefix("--leak-settle=").to_float())
	soak = load("res://scripts/core/soak_drive.gd").new()
	soak.main = main
	soak.rng.seed = 7
	main.begin_new_world()
	await _wait(1.0)
	soak._make_home()
	GameState.settings["reduce_motion"] = true   # quick journeys; the same nodes either way
	var g: Node = main.game
	g.daylight.hour_override = 11.0
	g.daylight.apply()
	_close_cards()
	var home := str(GameState.current_room_id)
	var dark_rooms: Array = Array(SaveManager.list_rooms()).filter(func(id): return str(id) != home)
	var other := str(dark_rooms[0]) if not dark_rooms.is_empty() else home
	var kinds := {
		"travel": func() -> void:
			await main.game.go_to_room(other)
			await _wait(0.4)
			await main.game.go_to_room(home)
			await _wait(0.4),
		"light_dark": func() -> void:
			await main.game.dark.go_light({})
			await _wait(0.4)
			await main.game.dark.go_dark({})
			await _wait(0.4),
		"light_rooms": func() -> void:
			await main.game.dark.go_light({})
			await _wait(0.3)
			await main.game.go_to_room("lw_floor_0")
			await _wait(0.3)
			await _street()
			await main.game.dark.go_dark({})
			await _wait(0.4),
		"screens": func() -> void:
			for maker in soak._screens():
				var p: Control = maker.call()
				main.open_panel(p)
				await _wait(0.15)
				soak._close_all()
				await _wait(0.1),
		"world_map": func() -> void:
			var m: Control = load("res://scripts/ui/world_map_view.gd").new()
			main.open_panel(m)
			m.setup_map(main.game)
			await _wait(0.3)
			soak._close_all()
			await _wait(0.2),
		"talk": func() -> void:
			var w: Node = main.game
			if w.actors.is_empty():
				return
			w.approach_character(str(w.actors.keys()[0]))
			await _wait(1.6)
			if w.dialogue and w.dialogue.visible:
				for i in 8:
					if w.dialogue.state == "input":
						break
					w.dialogue.advance()
				if w.dialogue.state == "input":
					w.dialogue.input.text = "hi!"
					w.dialogue._send()
					await _wait(1.0)
				w.dialogue.close_box()
			await _wait(0.3),
		"build": func() -> void:
			var w: Node = main.game
			w.build.enter()
			await _wait(0.2)
			w.build.set_piece("cube")
			w.build.cursor = Vector2i(2, 2)
			w.build.apply({})
			await _wait(0.2)
			w.build.undo()   # (the room ends as it started: only what building itself leaves counts)
			w.build.exit()
			await _wait(0.2),
		"sync_reload": func() -> void:
			await soak._sync_reload()
			await _wait(0.3),
		"lifecycle": func() -> void:
			await soak._lifecycle(),
		"photo": func() -> void:
			main.game.take_photo()
			await _wait(0.4),
		"battle": func() -> void:
			await soak._battle(),
		"weather_time": func() -> void:
			main.game.daylight.hour_override = soak.rng.randf_range(0.0, 24.0)
			main.game.daylight.apply(true)
			main.game.refresh_weather(true)
			await _wait(0.3),
	}
	for kind in kinds:
		if not only.is_empty() and not kind in only:
			continue
		await _measure(kind, kinds[kind])
		_close_cards()
	GameState.settings.erase("reduce_motion")
	var leaks: Array = results.filter(func(r): return bool(r.suspect))
	print("[leak] done %d actions, %d suspect: %s" % [results.size(), leaks.size(), ", ".join(leaks.map(func(r): return str(r.action)))])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(results, "\t"))
			f.close()


## Walks out to the home's street and back in (the biggest generated meshes in the game).
func _street() -> void:
	var gid: String = load("res://scripts/home/home_places.gd").place_id(0)
	for o in SaveManager.load_room(gid).get("objects", []):
		if bool(o.get("street_gate", false)):
			main.game.load_room(str(o.door_target), gid)
			await _wait(0.5)
			main.game.load_room(gid)
			await _wait(0.4)
			return


func _measure(kind: String, step: Callable) -> void:
	for i in 2:   # warm-up: first-use caches fill here
		await step.call()
	await _settle()
	var a := _sample()
	var nodes_a := _node_kinds()
	for i in cycles:
		await step.call()
	await _settle()
	var b := _sample()
	var grew: Array = []
	var nodes_b := _node_kinds()
	for k in nodes_b:
		var d := int(nodes_b[k]) - int(nodes_a.get(k, 0))
		if d > 0:
			grew.append("%s +%d" % [k, d])
	var r := {"action": kind, "cycles": cycles}
	for k in a:
		if a[k] is Dictionary:
			continue
		r[k + "_per_cycle"] = snappedf((float(b[k]) - float(a[k])) / cycles, 0.001)
	r["start"] = a
	r["end"] = b
	# Growth that can't be a cache: objects or resources climbing every cycle, nodes left behind,
	# or video memory still rising after the warm-up.
	r["suspect"] = float(r.objects_per_cycle) >= 2.0 or float(r.resources_per_cycle) >= 0.5 or float(r.nodes_per_cycle) >= 0.5 \
		or float(r.orphans_per_cycle) > 0.0 or float(r.tex_mb_per_cycle) >= 0.05 or float(r.buffer_mb_per_cycle) >= 0.05
	r["nodes_grew"] = grew
	results.append(r)
	print("[leak] ", JSON.stringify({"action": kind, "suspect": r.suspect, "caches": r.end.caches, "nodes_grew": grew.slice(0, 8), "objects": r.objects_per_cycle, "resources": r.resources_per_cycle,
		"nodes": r.nodes_per_cycle, "orphans": r.orphans_per_cycle, "tex_mb": r.tex_mb_per_cycle, "buffer_mb": r.buffer_mb_per_cycle,
		"static_mb": r.static_mb_per_cycle}))


## Let freed nodes go, deferred frees run and toasts fade before measuring.
func _settle() -> void:
	soak._close_all()
	for i in 4:
		await main.get_tree().process_frame
	await _wait(settle_s)


## Nodes by kind (class and script) in the whole tree: which kind is left behind.
func _node_kinds() -> Dictionary:
	var out := {}
	for n in main.get_tree().root.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		var k := n.get_class() + ("(" + str(sc.resource_path).get_file() + ")" if sc else "")
		out[k] = int(out.get(k, 0)) + 1
	return out


func _caches() -> Dictionary:
	return {"player_look": PlayerLook._cache.size(), "item_art": ItemArt._cache.size(),
		"silhouette": SilhouettePainter._cache.size(), "materials": BlockFactory._mat_cache.size()}


func _sample() -> Dictionary:
	return {
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"tex_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.01),
		"buffer_mb": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.01),
		"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.01),
		"caches": _caches(),
	}


func _close_cards() -> void:
	for n in main.ui.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()


func _wait(s: float) -> void:
	await main.get_tree().create_timer(s).timeout
