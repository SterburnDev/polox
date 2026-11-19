extends "res://tests/test_case.gd"
## Phase 29, the worlds swap places (world v8): everything the game had is the Dream World, the Light
## World is your real home (private, outside every world slot), every place knows which world it's in,
## old worlds upgrade after a snapshot with nothing moved or lost (only the labels and the way home),
## and the journey between the worlds both ways with the mouse: the rise home as Real Me, the fall back
## as Dream World Me, each skippable, a short fade with Reduce motion. The Light World looks and sounds
## like itself: true daylight, its own music cue over its own quiet sounds, no outlines or void
## skies, no battles.

const Realms := preload("res://scripts/world/realms.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const WorldMigration := preload("res://scripts/core/world_migration.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const ChoicePanel := preload("res://scripts/ui/choice_panel.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const Daylight := preload("res://scripts/world/daylight.gd")

var main: Node


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	LightHome.ensure_entry()   # (the Survey before the first trip home is test_map_my_home's)
	LightHome.defer_survey()
	for n in main.ui.find_children("*", "", true, false):   # the start-up cards (a player taps Got it)
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()
	await frames(2)
	return main.game


func _shutdown() -> void:
	GameState.settings["reduce_motion"] = false
	main.queue_free()
	await frames(2)


func _choice() -> Control:
	for p in main.panels:
		if is_instance_valid(p) and p.get_script() == ChoicePanel:
			return p
	return null


func _press(label_start: String) -> bool:
	var p := _choice()
	if p == null:
		return false
	for b in p.buttons:
		if (b as Button).text.begins_with(label_start):
			(b as Button).pressed.emit()
			return true
	return false


func _wait_idle(g: Node, ms: int = 15000) -> int:
	var t0 := Time.get_ticks_msec()
	await frames(2)
	while g.dark.busy and Time.get_ticks_msec() - t0 < ms:
		await frames(2)
	return Time.get_ticks_msec() - t0


func test_every_place_knows_its_world() -> void:
	fresh_save_root()
	StarterContent.create_world("Mine", "Sam")
	GameState.load_world()
	var ids := SaveManager.list_rooms()
	check(ids.size() >= 3, "a new world has its places")
	for id in ids:
		eq(Realms.realm(SaveManager.load_room(id)), Realms.DARK, "%s is in the Dream World" % id)
	var room := LightHome.placeholder()
	eq(Realms.realm(room), Realms.LIGHT, "your room is in the Light World")
	eq(str(room.player_form), "real", "you're Real Me there")
	check(not Realms.gate_of(room).is_empty() and str(Realms.gate_of(room).leads) == Realms.DARK, "with the Dream Gate down to the Dream World")
	check((room.objects as Array).any(func(o): return Furniture.is_furniture(o) and str(o.model) == "bed"), "and a real bed")
	var deep := DarkWorlds.make_from(SaveManager.load_room("home"), ids)
	eq(Realms.realm(deep), Realms.DARK, "the Deep is part of the Dream World")
	check(DarkWorlds.is_dark(deep), "(and it's the Deep)")
	# The start place has the way home.
	var gate := Realms.dark_gate(_rooms(), "home")
	eq(str(gate.get("place", "")), "home", "the way home stands in Home")
	eq(str(gate.get("gate", {}).get("target", "")), Realms.ENTRY, "leading to your room")


func _rooms() -> Dictionary:
	var out := {}
	for id in SaveManager.list_rooms():
		out[id] = SaveManager.load_room(id)
	return out


func test_old_worlds_upgrade_with_nothing_moved() -> void:
	fresh_save_root()
	StarterContent.create_world("Old World", "Sam")
	GameState.load_world()
	# Make it look like a v7 world: no realm labels, no way home, and a Deep place from Phase 25.
	var home := SaveManager.load_room("home")
	home["objects"] = (home.objects as Array).filter(func(o): return not Realms.is_gate(o))
	var f := DarkWorlds.place_fountain(home, Vector2i(3, 6))
	var deep := DarkWorlds.make_from(home, SaveManager.list_rooms())
	DarkWorlds.link(home, f, deep)
	for fb in DarkWorlds.fountains(deep):
		fb["label"] = "Back to the Light World"
	SaveManager.save_room(home)
	SaveManager.save_room(deep)
	var before := {}
	for id in SaveManager.list_rooms():
		var r := SaveManager.load_room(id)
		r.erase("realm")
		SaveManager.save_room(r)
		before[id] = JSON.stringify(r)
	var raw: Dictionary = JsonUtil.read_json(SaveManager.world_path(), {})
	raw["version"] = 7
	JsonUtil.write_json(SaveManager.world_path(), raw)
	var res := WorldMigration.run()
	check(bool(res.get("migrated", false)) and str(res.get("snapshot", "")) != "", "upgraded after a snapshot")
	check(FileAccess.file_exists(str(res.get("snapshot", ""))), "the snapshot zip exists")
	eq(int(JsonUtil.read_json(SaveManager.world_path(), {}).get("version", 0)), 8)
	for id in before:
		var r := SaveManager.load_room(id)
		eq(str(r.get("realm", "")), "dark", "%s labelled Dream World" % id)
		var gates := Realms.gates(r)
		var cmp := r.duplicate(true)
		cmp.erase("realm")
		cmp["objects"] = (cmp.objects as Array).filter(func(o): return not Realms.is_gate(o))
		for o in cmp.objects:
			if str(o.get("label", "")).begins_with("Back to "):
				o["label"] = "Back to the Light World"
		var old: Dictionary = JSON.parse_string(before[id])
		eq(JSON.stringify(JSON.parse_string(JSON.stringify(cmp))), JSON.stringify(old), "%s: nothing else changed" % id)
		if id == "home":
			eq(gates.size(), 1, "Home got the way home")
			var gp: Array = gates[0].pos if not gates.is_empty() else [0, 0, 0]
			check(absi(int(gp[0]) - 6) + absi(int(gp[2]) - 7) <= 3, "near where you start")
		else:
			eq(gates.size(), 0, "%s: no gate" % id)
	var back: Array = DarkWorlds.fountains(SaveManager.load_room(str(deep.id)))
	eq(str(back[0].label) if not back.is_empty() else "", "Back to Home", "the Deep's fountain names where it leads")
	check(not WorldMigration.run().get("migrated", false), "and it runs once")


func test_your_home_is_private() -> void:
	fresh_save_root()
	StarterContent.create_world("Mine", "Sam")
	GameState.load_world()
	LightHome.ensure_entry()
	var path := SaveManager.room_path(Realms.ENTRY)
	check(path.begins_with(SaveManager.home_dir()), "your room lives in my_home")
	check(FileAccess.file_exists(path), "and is saved there")
	check(not Realms.ENTRY in SaveManager.list_rooms(), "not among this world's places")
	eq(Array(SaveManager.list_light_rooms()), [Realms.ENTRY], "but among the Light World's")
	SyncFiles.home_shared = false
	var synced := SyncFiles.scan(SaveManager.root, PackedStringArray([SaveManager.slot_id]))
	check(not synced.keys().any(func(p): return str(p).contains("my_home") or str(p).contains(Realms.PREFIX)), "not synced unless the PC shares it")
	check(not SyncFiles.allowed("my_home/places/%s.json" % Realms.ENTRY, PackedStringArray([SaveManager.slot_id])), "a phone can't ask for it then")
	SyncFiles.home_shared = true
	check(SyncFiles.allowed("my_home/places/%s.json" % Realms.ENTRY, PackedStringArray([SaveManager.slot_id])), "shared: the places")
	for private in ["my_home/private.json", "my_home/journal.json", "my_home/files/permits.json", "my_home/research/research_1.json", "my_home/snapshots/a.json", "my_home/places/x.json"]:
		check(not SyncFiles.allowed(private, PackedStringArray([SaveManager.slot_id])), "never %s" % private)
	SyncFiles.home_shared = false
	var snap := SlotArchive.snapshot(SaveManager.slot_id, "manual")
	var zr := ZIPReader.new()
	check(zr.open(snap) == OK, "a world snapshot")
	check(not Array(zr.get_files()).any(func(p): return str(p).contains(Realms.PREFIX)), "doesn't carry your home")
	zr.close()


func test_the_journey_both_ways_with_the_mouse() -> void:
	var g: Node = await _boot()
	var start := str(GameState.current_room_id)
	var gate: Dictionary = Realms.gate_of(g.room.data)
	check(not gate.is_empty(), "the way home is in the start place")
	check(g.room.object_nodes.has(str(gate.get("id", ""))), "and you can see it")
	# Click it (the real click path), then Go home.
	var gp: Array = gate.pos
	g.player.position = g.room.cell_center(Vector2i(int(gp[0]), mini(int(gp[2]) + 2, g.room.d - 1)))
	for _i in 10:
		g.cam._process(0.1)
	var screen: Vector2 = g.cam.camera.unproject_position(g.room.obj_position(gate) + Vector3(0, 0.7, 0))
	g.controller.click(screen)
	var t := Time.get_ticks_msec()
	while _choice() == null and Time.get_ticks_msec() - t < 8000:
		await frames(2)
	check(_choice() != null, "walking up to it offers the way home")
	check(_press("Go home"), "Go home")
	var up_ms := await _wait_idle(g)
	eq(GameState.current_room_id, Realms.ENTRY, "in your room, in the Light World")
	eq(PlayerLook.current(), "real", "as Real Me")
	check(up_ms > 1800, "the rise home takes a moment (%d ms)" % up_ms)
	var lg: Dictionary = Realms.gate_of(g.room.data)
	var lgp: Array = lg.get("pos", [0, 0, 0])
	check(Vector2(g.player.cell() - Vector2i(int(lgp[0]), int(lgp[2]))).length() <= 2.0, "beside the fountain in your room")
	# It looks and sounds like the Light World.
	eq(g.dark_look.lines_built, 0, "no glowing outlines")
	check(str(g.room.data.background.sky) != "void", "a real sky")
	eq(g.music.current_track(), preload("res://scripts/world/music_player.gd").theme_path("light"), "the Light World's cue")
	check(str(g.ambience.current).begins_with("home_"), "its own quiet sounds under it (%s)" % g.ambience.current)
	g.daylight.hour_override = 12.0   # (the test may run at night: the Light World's nights are blue, rightly)
	g.daylight.apply()
	var amb: Color = g.env.ambient_light_color
	check(amb.b <= amb.r + 0.02, "true daylight at noon, not violet (%s)" % amb.to_html(false))
	g.daylight.hour_override = -1.0
	check(g.hud.room_label.text.begins_with("☀"), "a little sun by the name")
	g.battles.forced_roll = 0.0
	g.battles.last_encounter = -1e9
	check(not await g.battles.try_encounter(), "no battles in the Light World")
	# Back down, as Dream World Me.
	g.dark.use_fountain(lg)
	await frames(2)
	check(_press("Enter the Dream World"), "Enter the Dream World")
	var down_ms := await _wait_idle(g)
	eq(GameState.current_room_id, start, "back where you left the Dream World")
	eq(PlayerLook.current(), "dark", "as Dream World Me")
	check(down_ms > 1800, "the fall takes a moment (%d ms)" % down_ms)
	check(Vector2(g.player.cell() - Vector2i(int(gp[0]), int(gp[2]))).length() <= 2.0, "beside the way home")
	eq(g.ambience.current, "", "the Light World's sounds stop")
	eq(g.music.current_track(), preload("res://scripts/world/music_player.gd").theme_path("dark"), "the Dream World's cue")
	var trips: int = int(load("res://scripts/variety/variety_save.gd").data().get("almanac", {}).get("light_visits", 0))
	eq(trips, 1, "the Almanac counts the trip home")
	await _shutdown()


func test_crossing_skips_and_reduce_motion() -> void:
	var g: Node = await _boot()
	var times := {}
	for mode in ["full", "skipped", "reduced"]:
		GameState.settings["reduce_motion"] = mode == "reduced"
		if mode == "skipped":
			var job := func() -> void:
				await frames(4)
				for m in main.toast_layer().get_children():
					if m.has_method("skip"):
						m.skip()
			job.call()
		var t0 := Time.get_ticks_msec()
		await g.dark.go_light()
		times[mode] = Time.get_ticks_msec() - t0
		eq(GameState.current_room_id, Realms.ENTRY, "%s: home" % mode)
		eq(PlayerLook.current(), "real", "%s: Real Me" % mode)
		await g.dark.go_dark()
		eq(PlayerLook.current(), "dark", "%s: Dream World Me again" % mode)
	check(times.full > 1800, "the journey plays (%d ms)" % times.full)
	check(times.skipped < times.full * 0.6, "a tap skips it (%d ms)" % times.skipped)
	check(times.reduced < 900, "Reduce motion: a short fade (%d ms)" % times.reduced)
	await _shutdown()


func test_the_world_map_shows_both_worlds() -> void:
	var g: Node = await _boot()
	SaveManager.delete_room(Realms.ENTRY)   # no Light World yet
	var map: Control = load("res://scripts/ui/world_map_view.gd").new()
	main.open_panel(map)
	map.setup_map(g)
	await frames(2)
	map.show_layer("light")
	check(map._archive.visible, "before you've been home: a note instead of an empty map")
	map.close()
	LightHome.ensure_entry()
	await g.dark.go_light()
	map = load("res://scripts/ui/world_map_view.gd").new()
	main.open_panel(map)
	map.setup_map(g)
	await frames(2)
	eq(map.layer, "light", "it opens on the world you're in")
	check(map.canvas.rooms.has(Realms.ENTRY), "your room is on the Light World layer")
	map.show_layer("dark")
	check(map.canvas.rooms.has("home") and not map.canvas.rooms.has(Realms.ENTRY), "the Dream World layer has the rest")
	map.go("home")
	await _wait_idle(g)
	eq(GameState.current_room_id, "home", "Go there across the worlds")
	eq(PlayerLook.current(), "dark", "by the real journey (Dream World Me)")
	await _shutdown()


func test_daylight_and_sounds_differ_by_world() -> void:
	var day_dark: Dictionary = Daylight.sample(12.0)
	var day_light: Dictionary = Daylight.sample(12.0, true)
	check((day_dark.amb as Color).b > (day_dark.amb as Color).r, "the Dream World's day is violet")
	check((day_light.amb as Color).b <= (day_light.amb as Color).r, "the Light World's day is warm white")
	var room := LightHome.placeholder()
	eq(load("res://scripts/world/ambience.gd").kind_for(room, false), "home_day")
	eq(load("res://scripts/world/ambience.gd").kind_for(room, true), "home_night")
	eq(load("res://scripts/world/ambience.gd").kind_for({"id": "garden"}, false), "", "silent in the Dream World")
	var s: AudioStreamWAV = load("res://scripts/world/ambience.gd").loop("street_day")
	check(s.data.size() > 22050 * 2 * 4 and s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "a looping street")
