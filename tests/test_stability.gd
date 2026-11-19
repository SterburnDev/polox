extends "res://tests/test_case.gd"
## Phase 38, no more random crashes: a world reloaded because the other device's files arrived writes
## nothing back (it used to rewrite every friend, which the next sync sent straight back, so a phone and
## a PC reloaded each other every half minute); the reload waits while you're talking, fighting, crossing
## or building, and happens only for files that change what's on screen; losing focus (the notification
## shade) never zips the world, and going to the background does at most every five minutes; the flight
## recorder notices a session that just stopped, keeps its last errors and where you were, and its report
## fits the PC's report box. The soak run (scripts/core/soak_drive.gd) is the long version of all this.

const CrashLog := preload("res://scripts/core/crash_log.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")

var main: Node


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	GameState.settings["reduce_motion"] = true
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _end() -> void:
	main._close_all_panels()
	main.queue_free()
	await frames(2)


func test_opening_settings_does_not_wait_for_tailscale() -> void:
	await _boot()
	var research: Script = load("res://scripts/home/research.gd")
	var previous := int(research.sign_in_state)
	research.sign_in_state = 0   # this check concerns network discovery, not a live helper
	main.phone_link.setup(SaveManager.root)
	main.phone_link.ts.runner = func(_args, _timeout) -> Dictionary:
		OS.delay_msec(1200)
		return {"code": 0, "out": "{\"BackendState\":\"Stopped\"}"}
	GameState.settings["phone_link"]["mode"] = "auto"
	load("res://scripts/phone/web_build.gd").current_build_id()   # from source this hashes the whole project once (an export reads its baked id)
	var settings: Control = load("res://scripts/ui/settings_screen.gd").new()
	settings.main = main
	var before := Time.get_ticks_msec()
	main.open_panel(settings)
	check(Time.get_ticks_msec() - before < 600, "opening Settings never waits for Tailscale's CLI")
	var link_tab: Node = settings.find_child("Phone Link", true, false)
	var job: Dictionary = link_tab._checks_job if link_tab else {}
	settings.close()
	var until := Time.get_ticks_msec() + 20000
	while not job.is_empty() and not bool(job.done) and Time.get_ticks_msec() < until:
		await frames(2)
	check(job.is_empty() or bool(job.done), "the background discovery finishes after the screen closes")
	research.sign_in_state = previous
	await _end()


func _shas() -> Dictionary:
	var out := {}
	var dir := SaveManager.abs_path("characters")
	for id in DirAccess.get_directories_at(dir):
		out["characters/" + id] = FileAccess.get_sha256(dir.path_join(id).path_join("character.json"))
	out["world"] = FileAccess.get_sha256(SaveManager.world_path())
	return out


func test_a_reload_from_the_other_device_writes_nothing_back() -> void:
	var g := await _boot()
	await frames(5)
	main.flush_all()
	var before := _shas()
	# A friend's clock is an hour behind, as if the file came from a phone that synced an hour ago.
	var c: Dictionary = SaveManager.load_character("mochi")
	c["last_update_unix"] = Time.get_unix_time_from_system() - 3600.0
	SaveManager.save_character(c)
	var arrived := FileAccess.get_sha256(SaveManager.abs_path("characters/mochi/character.json"))
	main.reload_world_from_disk()
	await frames(3)
	eq(FileAccess.get_sha256(SaveManager.abs_path("characters/mochi/character.json")), arrived, "the friend's file is left exactly as it arrived")
	for k in before:
		if k != "characters/mochi":
			eq(FileAccess.get_sha256(SaveManager.abs_path(k + "/character.json") if k.begins_with("characters/") else SaveManager.world_path()), before[k], "%s isn't rewritten" % k)
	eq(float(GameState.get_character("mochi").get("last_update_unix", 0.0)), float(c.last_update_unix), "and the game uses it as it came")
	# Opening the world normally still catches up on the time that passed.
	GameState.load_world()
	check(float(GameState.get_character("mochi").get("last_update_unix", 0.0)) > float(c.last_update_unix) + 1000.0, "a normal start catches up")
	check(g != null, "the game ran")
	await _end()


func test_the_reload_waits_while_you_are_busy() -> void:
	var g := await _boot()
	g.approach_character("mochi")
	var t := Time.get_ticks_msec()
	while not g.dialogue.visible and Time.get_ticks_msec() - t < 8000:
		await frames(2)
	check(g.dialogue.visible, "talking to Mochi")
	var world_before: Dictionary = GameState.world
	main.reload_world_from_disk()
	await frames(2)
	check(is_same(world_before, GameState.world), "nothing reloads mid-conversation")
	check(main._reload_pending, "it's waiting")
	g.dialogue.close_box()
	t = Time.get_ticks_msec()
	while main._reload_pending and Time.get_ticks_msec() - t < 5000:
		await frames(2)
	check(not main._reload_pending and not is_same(world_before, GameState.world), "and happens once you're done")
	# Building waits too (as it always did), and so does a crossing.
	g.build.enter()
	world_before = GameState.world
	main.reload_world_from_disk()
	await frames(2)
	check(is_same(world_before, GameState.world), "not while building")
	g.build.exit()
	await frames(4)
	check(not is_same(world_before, GameState.world), "after building")
	await _end()


func test_only_what_shows_makes_a_reload() -> void:
	check(not SyncFiles.needs_reload(["slots/a/cover.png", "slots/a/slot.json", "slots/a/logs/mochi.jsonl", "slots/a/photos/p.png"]), "cover, playtime, chat logs, photos: no reload")
	check(SyncFiles.needs_reload(["slots/a/cover.png", "slots/a/world.json"]), "the world file: reload")
	check(SyncFiles.needs_reload(["slots/a/characters/mochi/character.json"]), "a friend: reload")
	check(SyncFiles.needs_reload(["slots/a/rooms/home.json"]), "a place: reload")
	var g := await _boot()
	var world_before: Dictionary = GameState.world
	main._on_phone_changed_world(SaveManager.slot_id, ["slots/%s/cover.png" % SaveManager.slot_id, "slots/%s/slot.json" % SaveManager.slot_id])
	await frames(2)
	check(is_same(world_before, GameState.world), "the PC doesn't reload for a new cover picture")
	main._on_phone_changed_world(SaveManager.slot_id, ["slots/%s/world.json" % SaveManager.slot_id])
	await frames(2)
	check(not is_same(world_before, GameState.world), "but does for the world")
	check(g != null, "the game ran")
	await _end()


func test_losing_focus_never_zips_the_world() -> void:
	await _boot()
	var n0 := SlotArchive.backups(SaveManager.slot_id).size()
	main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	eq(SlotArchive.backups(SaveManager.slot_id).size(), n0, "the notification shade saves files, no snapshot")
	main.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(main.autosave._bg_task >= 0, "going to the background zips on a worker thread (no stall while Android puts the app away)")
	main.autosave.finish_background()
	eq(SlotArchive.backups(SaveManager.slot_id).size(), n0 + 1, "going to the background takes one")
	check(SlotArchive.backups(SaveManager.slot_id).all(func(b): return not str(b.path).ends_with(".part")), "only finished zips count as backups")
	main.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	main.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	main.autosave.finish_background()
	eq(SlotArchive.backups(SaveManager.slot_id).size(), n0 + 1, "not again a minute later")
	main.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	main.flush_all(true)
	eq(SlotArchive.backups(SaveManager.slot_id).size(), n0 + 2, "closing always does")
	await _end()


func test_the_flight_recorder() -> void:
	var dir := ProjectSettings.globalize_path("res://tests/.tmp_save").path_join("crash_log")
	preload("res://scripts/core/json_util.gd").remove_tree(dir)
	# A session that stops by itself (no clean exit, not in the background).
	var a: Node = CrashLog.new(dir)
	tree.root.add_child(a)
	a.setup(null)
	check(FileAccess.file_exists(dir.path_join("polox_session.json")), "the session file is written at the start")
	print("[expect-script-error] a deliberate error for the flight recorder follows")
	push_error("a deliberate test error 4242")
	print("[/expect-script-error]")
	await frames(2)
	a.beat()
	var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("polox_session.json")))
	check(s is Dictionary and not bool(s.clean) and str(s.errors).contains("4242"), "the error is in the session file")
	a._exit_tree()
	a.free()   # (no on_clean_exit: as if Android took the app away while it was in front of you)
	var b: Node = CrashLog.new(dir)
	tree.root.add_child(b)
	b.setup(null)
	check(not b.previous_crash.is_empty(), "the next start knows the last one ended unexpectedly")
	eq((b.pending as Array).size(), 1, "one crash report waits for the PC")
	var rep: Dictionary = CrashLog.as_report(b.pending[0])
	eq(str(rep.page), "crash report", "a crash report")
	check(str(rep.log).contains("4242"), "with the last errors")
	var sink := ReportSink.new(dir.path_join("pc"))
	var res: Array = sink.accept("192.168.1.30", JSON.stringify(rep).to_utf8_buffer(), "http", "Phone Link")
	eq(int(res[0]), 200, "the PC's report box takes it")
	var saved := Array(DirAccess.get_files_at(dir.path_join("pc").path_join("phone_reports")))
	check(saved.size() == 1 and FileAccess.get_file_as_string(dir.path_join("pc/phone_reports").path_join(str(saved[0]))).contains("4242"), "and keeps it")
	b.mark_sent(b.pending[0])
	eq((b.pending as Array).size(), 0, "sent once")
	# Leaving on purpose, or going to the background, isn't a crash.
	b.on_clean_exit()
	b._exit_tree()
	b.free()
	var c: Node = CrashLog.new(dir)
	tree.root.add_child(c)
	c.setup(null)
	check(c.previous_crash.is_empty() and (c.pending as Array).is_empty(), "a clean exit is no crash (and the sent one stays sent)")
	c.on_background(true)
	c._exit_tree()
	c.free()
	var d: Node = CrashLog.new(dir)
	tree.root.add_child(d)
	d.setup(null)
	check(d.previous_crash.is_empty(), "nor is Android ending the app in the background")
	d.on_clean_exit()
	d._exit_tree()
	d.free()
	check(not FileAccess.get_file_as_string(dir.path_join("polox_session.json")).contains("api_key"), "no keys in it")


## The leak behind the phone's crashes: every place entered and every 20 s outdoors made a new Sky, and the
## phone's renderer never gave its memory back. One sky now, reused, its colours changed in place.
func test_one_sky_reused() -> void:
	var g := await _boot()
	var data: Dictionary = g.room.data
	data["background"] = {"sky": "auto", "ground": true, "layers": []}
	g.daylight.hour_override = 9.0
	g.apply_backdrop(data)
	var first: Sky = g.env.sky
	check(first != null and g.env.background_mode == Environment.BG_SKY, "an outdoor sky")
	var morning: Color = (first.sky_material as ProceduralSkyMaterial).sky_top_color
	g.daylight.hour_override = 21.0
	g.daylight.apply()
	g.apply_backdrop(data)
	check(is_same(first, g.env.sky), "the daylight keeps the same sky")
	check((g.env.sky.sky_material as ProceduralSkyMaterial).sky_top_color != morning, "and repaints it for the evening")
	g.load_room(GameState.current_room_id)
	await frames(2)
	g.apply_backdrop(data)
	check(is_same(first, g.env.sky), "entering a place again keeps it too")
	await _end()


## Closing a screen while its slow check runs (the firewall: about ten seconds) doesn't wait for it.
func test_closing_a_screen_never_waits_for_its_check() -> void:
	var BackgroundJob: Script = load("res://scripts/core/background_job.gd")
	var job: Dictionary = BackgroundJob.run(func() -> int:
		OS.delay_msec(1200)
		return 42)
	var holder := Control.new()
	tree.root.add_child(holder)
	var t := Time.get_ticks_msec()
	holder.queue_free()
	await frames(2)
	check(Time.get_ticks_msec() - t < 600, "the screen closed at once (%d ms)" % (Time.get_ticks_msec() - t))
	check(not bool(job.done), "while the check still runs")
	t = Time.get_ticks_msec()
	while not bool(job.done) and Time.get_ticks_msec() - t < 5000:
		await frames(2)
	eq(int(job.result), 42, "and it finishes on its own")
	await frames(3)
	var keeper: Node = tree.root.get_node_or_null("BackgroundJobs")
	check(keeper != null and (keeper._jobs as Array).is_empty(), "its thread is joined by the keeper")


## A battle whose screen goes away without an end (the world closing under it) gives the HUD back.
func test_a_battle_screen_gone_without_an_end() -> void:
	var g := await _boot()
	var BattleData := preload("res://scripts/battle/battle_data.gd")
	g.battles.start(BattleData.from_template("star_shower", GameState.get_character("mochi")), [])
	var t := Time.get_ticks_msec()
	while g.battles.screen == null and Time.get_ticks_msec() - t < 8000:
		await frames(2)
	check(g.battles.screen != null and not g.hud.visible, "a battle, the HUD hidden")
	main._close_all_panels()
	await frames(4)
	check(g.battles.screen == null, "no pointer left to a screen that's gone")
	check(g.hud.visible, "the HUD is back")
	check(not main._busy_for_reload(), "and nothing thinks a battle is still on")
	await _end()


## The picture cache keeps the most recently used pictures only (a phone's video memory is small).
func test_the_picture_cache_has_a_limit() -> void:
	fresh_save_root()
	var dir := SaveManager.abs_path("textures") if SaveManager.slot_id != "" else SaveManager.root.path_join("pics")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for i in SaveManager.TEX_CACHE_MAX + 20:
		img.fill(Color(float(i) / 120.0, 0.5, 0.5))
		var p := dir.path_join("p%d.png" % i)
		img.save_png(p)
		check(SaveManager.load_texture(p) != null, "picture %d loads" % i)
	check(SaveManager._tex_cache.size() <= SaveManager.TEX_CACHE_MAX, "the cache holds at most %d (%d)" % [SaveManager.TEX_CACHE_MAX, SaveManager._tex_cache.size()])
	check(SaveManager._tex_cache.has(SaveManager.abs_path(dir.path_join("p%d.png" % (SaveManager.TEX_CACHE_MAX + 19)))), "the newest stays")


## 1.27 leak hunt: each kind of play done over and over leaves nothing behind (no nodes, objects or
## resources growing with the count). leak_drive.gd measures the same on the phone's renderer, video
## memory included; here, headless, the scene side.
func test_repeated_play_leaves_nothing_behind() -> void:
	await _boot()
	var drive: RefCounted = load("res://scripts/core/leak_drive.gd").new()
	drive.cycles = 4
	drive.settle_s = 1.5
	drive.only = PackedStringArray(["travel", "light_dark", "talk", "build", "photo", "screens"])
	await drive.run(main)
	eq(drive.results.size(), 6, "every action measured")
	for r in drive.results:
		check(not bool(r.suspect), "%s leaves nothing behind (objects %+.2f, resources %+.2f, nodes %+.2f a cycle; grew: %s)" % [
			r.action, r.objects_per_cycle, r.resources_per_cycle, r.nodes_per_cycle, str(r.get("nodes_grew", []))])
	GameState.settings["reduce_motion"] = true
	await _end()


## A friend's derived pictures (eyes shut for blinking, the Dream World look) live on the picture itself:
## when a rebuilt friend's old picture goes, they go too. (Until 1.27 two lists kept up to 128 and 64
## old pictures alive.)
func test_derived_pictures_live_and_die_with_their_picture() -> void:
	var Blink := preload("res://scripts/characters/blink.gd")
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0.8, 0.6))
	var tex := ImageTexture.create_from_image(img)
	var first: Variant = Blink.texture_for(tex)
	check(tex.has_meta(Blink.SHUT), "the result is kept on the picture")
	eq(Blink.texture_for(tex), first, "and reused")
	check(not "_cache" in Blink.new().get_property_list().map(func(p): return str(p.name)), "no global list of pictures")
	var weak: WeakRef = weakref(tex)
	tex = null
	await frames(1)
	check(weak.get_ref() == null, "the picture can go, and its derived picture with it")
