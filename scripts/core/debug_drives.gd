extends RefCounted
## Scripted scenarios for automated visual checks (see debug_capture.gd).
## Only used when the game is started with --drive=<name>; never in play.

var main: Node


func run(drive_name: String, main_node: Node) -> void:
	main = main_node
	if drive_name == "battle_spars":
		await load("res://scripts/core/battle_soak_drive.gd").new().run(main)
		return
	if drive_name == "perf_scenes":
		await load("res://scripts/core/perf_drive.gd").new().run(main)
		return
	if drive_name == "mobile_creation":
		await load("res://scripts/core/mobile_creation_drive.gd").new().run(main)
		return
	if drive_name == "leak_cycles":
		await load("res://scripts/core/leak_drive.gd").new().run(main)
		return
	if drive_name == "hitch_probe":
		await load("res://scripts/core/hitch_drive.gd").new().run(main)
		return
	if drive_name in ["cloud_sync", "cloud_sync_empty", "cloud_sync_conflict"]:
		await load("res://scripts/core/cloud_sync_drive.gd").new().run(main, drive_name)   # [CLOUD_SYNC]
		return
	if drive_name == "notes_check":
		await _notes_check()
		return
	if drive_name in ["paste_prompt", "paste_offer", "paste_review", "paste_house", "paste_street"]:
		await _paste_round_trip(drive_name)
		return
	if drive_name.begins_with("tpl_"):
		# Any built-in template as a new place (`--drive=tpl_snowy_village`).
		main.begin_new_world()
		await _wait(0.5)
		for card in main.ui.find_children("*", "Control", true, false):
			var script: Script = card.get_script()
			if script and script.resource_path.get_file() in ["today_card.gd", "recap_card.gd"]:
				card.queue_free()
		load("res://scripts/world/template_factory.gd").ensure_builtin()
		var rooms: PackedStringArray = load("res://scripts/world/templates.gd").new_level(drive_name.trim_prefix("tpl_"))
		if not rooms.is_empty():
			main.game.daylight.hour_override = 13.0
			main.game.load_room(rooms[0])
		await _wait(0.8)
		return
	match drive_name:
		# One line per feature: each group of drives lives in its own function below.
		"movement_review", "lab_slopes", "lab_corners", "lab_speed":
			await _movement_drives(drive_name)
		"osm_landmark", "codex_check", "codex_landmark", "home_manual":
			await _helper_check_drives(drive_name)
		"begin", "talk", "chat5", "log", "idle10", "dreams", "memory", "night", "life_ai", "gift", "gift_ai":
			await _chat_drives(drive_name)
		"menu", "settings_speed", "keys", "wrong_key", "ollama", "settings", "bible", "friends", "testconn", "onboard", "create_survey", "onboard_first", "onboard_life", "perf", "scale", "scalemenu", "photo", "snow", "leaves", "petals", "rain", "fireflies", "music_settings", "settings_first_tab", "continue", "recap", "whats_new", "worlds":
			await _menu_drives(drive_name)
		"creative_pier", "creative_gallery", "creator", "create3", "build4", "persist", "buildview", "rooms", "web", "door", "place_outdoor", "world_map_places", "build_place", "fountain_strips", "editor", "editor_simple", "turn_and_resize":
			await _making_drives(drive_name)
		"battle_targets", "battle_magic", "battle_review", "battle_fightbar", "battle_telegraph", "battle_party_end", "battle_menu", "battle_dodge", "battle_act", "battle_end", "battle_maker", "battle_maker_advanced", "story", "story_log", "story_requests", "story_found":
			await _battle_drives(drive_name)
		"secret", "secret_by_hand":
			await _secret_drives(drive_name)
		"app_connect", "app_pin", "app_qr", "phone_link_android", "ping_window":
			await _phone_app_drives(drive_name)
		"smoke":
			await scenarios().smoke()
		"soak":
			await load("res://scripts/core/soak_drive.gd").new().run(main)
		"app_flow":
			await load("res://scripts/core/app_drive.gd").new().run(main)
		"sheet_me", "sheet_looks", "sheet_gear", "bag", "workshop", "gear_world", "gift_chat":
			await _phase10(drive_name)
		"platform", "platform_jump", "jump_reach", "anim_tab":
			await _platform(drive_name)
		"variety_today", "quest_log", "almanac", "dream_room":
			await _variety(drive_name)
		"hangout_tea", "hangout_stars", "hangout_wish", "hangout_walk", "hangout_panel", "decor_halloween", "decor_winter":
			await _hangout(drive_name)
		"way_home", "way_home_choice", "light_room", "light_map", "dark_map", "world_sheet", "friends_sheet":
			await _light_world(drive_name)
		"survey_hello", "survey_address", "survey_rooms", "survey_floor", "survey_consent", "survey_build", "survey_streets", "survey_streets_preview", "survey_streets_fail", "survey_streets_cancel", "home_mine", "home_ground", "home_sketch", "home_sources", "home_settings", "home_tell", "home_unsure", "home_timeline", "home_look_again", "hood_street", "hood_detail", "hood_refs", "hood_park", "hood_map", "hood_wide", "hood_wide_map", "decor_open", "things_to_do", "journal", "anim_reveal", "anim_street", "anim_sheet", "moment_fountain", "moment_back":
			await _home(drive_name)
		"phone_hud", "phone_chat", "phone_bag", "phone_link", "phone_link_tailscale", "phone_banner", "host_window":
			await _phone(drive_name)


## Walking, running and the Movement Lab courses.
func _movement_drives(drive_name: String) -> void:
	match drive_name:
		"movement_review":
			main.begin_new_world()
			await _wait(0.5)
			var g: Node = main.game
			var before: Vector3 = g.player.position
			Input.action_press("move_right", 0.5)
			await _wait(1.0)
			Input.action_release("move_right")
			await _wait(0.3)
			print("[drive] analog movement distance: ", before.distance_to(g.player.position), "; stopped: ", not g.player.is_moving())
			g.controller.walk_to(g.room.spawn_cell())
			await _wait(2.0)
			print("[drive] click arrival error: ", g.player.position.distance_to(g.room.cell_center(g.room.spawn_cell())))
		"lab_slopes", "lab_corners", "lab_speed":
			# The Movement Lab: a course with your chosen profile (Classic on the straight ones), running.
			main.begin_new_world()
			await _wait(0.5)
			var g: Node = main.game
			for card in main.ui.find_children("*", "Control", true, false):
				var card_script: Script = card.get_script()
				if card_script and card_script.resource_path.get_file() in ["today_card.gd", "recap_card.gd"]:
					card.queue_free()
			GameState.settings["platform_profile"] = "classic" if drive_name != "lab_corners" else "adventure"
			# Added the way the editor adds a template (new room ids, doors re-joined).
			var course := ""
			var want: String = {"lab_slopes": "Lab: Slopes", "lab_corners": "Lab: Corners", "lab_speed": "Lab: Speed"}[drive_name]
			for rid in load("res://scripts/world/templates.gd").new_level("movement_lab"):
				if str(SaveManager.load_room(rid).get("name", "")) == want:
					course = rid
			g.load_room(course)
			await _wait(0.4)
			for o in g.room.data.objects:
				if str(o.type) == "platform_pillar":
					g.platform.activate(o)
			await _wait(1.6)
			g.platform.test_input = Vector2(1, 0) if drive_name != "lab_corners" else Vector2(0.7, 0.7)
			g.platform.run_toggle = true
			await _wait(1.4 if drive_name != "lab_speed" else 2.2)
			print("[drive] %s: room %s (%s), profile %s, at %s, speed %.2f, side axis %s, camera at %s" % [drive_name, GameState.current_room_id, str(g.room.data.get("name", "")),
				g.platform.body.profile, str(g.platform.body.global_position), Vector2(g.platform.body.velocity.x, g.platform.body.velocity.z).length(), str(g.cam.side_axis), str(g.cam.camera.global_position)])
			# Stop there, so the screenshot shows this moment whenever it's taken.
			g.platform.test_input = Vector2.ZERO
			g.platform.run_toggle = false
			g.platform.body.velocity = Vector3.ZERO


## The home helpers asked for real (a public landmark, never a home).
func _helper_check_drives(drive_name: String) -> void:
	match drive_name:
		"osm_landmark":
			# Explicit developer verification of a public library, never the player's address.
			if not Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--save-root=")):
				print("[drive] osm_landmark requires an explicit disposable --save-root")
				return
			var osm: Node = preload("res://scripts/home/osm.gd").new()
			main.add_child(osm)
			osm.progress.connect(func(line): print("[drive] map: ", line))
			var located: Dictionary = await osm.locate("Seattle Central Library, Seattle, Washington, USA")
			print("[drive] public landmark location: ", JSON.stringify(located))
			if not bool(located.get("ok", false)) or located.get("candidates", []).is_empty():
				osm.queue_free()
				return
			var point: Dictionary = located.candidates[0]
			osm.fetch(float(point.lat), float(point.lon), 150)
			var result: Dictionary = await osm.finished
			var extract: Dictionary = result.get("extract", {})
			print("[drive] public landmark map: ", JSON.stringify({"ok": result.get("ok"), "state": result.get("state"), "error": result.get("error", ""), "features": extract.get("features", []).size()}))
			if bool(result.get("ok", false)):
				preload("res://scripts/core/json_util.gd").write_json(SaveManager.global_path("public_landmark_extract.json"), extract)
			osm.queue_free()
		"codex_check":
			var cli := preload("res://scripts/home/helper_codex.gd").new()
			main.add_child(cli)
			var result: Dictionary = await cli.check()
			print("[drive] Codex installed/sign-in check: ", JSON.stringify(result))
			cli.queue_free()
		"codex_landmark":
			# A live end-to-end lookup through Polox's own research code, of a PUBLIC, nonresidential
			# landmark only (never a home). Run with an explicit disposable --save-root.
			var r: Node = preload("res://scripts/home/research.gd").new()
			main.add_child(r)
			r.progress.connect(func(l): print("[drive] progress: ", l))
			r.start("codex", "Seattle Central Library, 1000 4th Ave, Seattle, WA 98104 (a public library building)", {"home_type": "public building"})
			var res: Dictionary = await r.finished
			var research: Dictionary = res.get("research", {})
			print("[drive] Codex landmark research: ", JSON.stringify({"ok": res.get("ok"), "why": res.get("why"), "error": str(res.get("error", "")).left(200),
				"searched": res.get("searched", 0), "grounded": research.get("grounded"), "facts": (research.get("facts", []) as Array).size(),
				"sources": (research.get("sources", []) as Array).map(func(s): return str(s.get("url", "")).left(80))}))
			r.queue_free()
		"home_manual":
			main.begin_new_world()
			await _wait(0.5)
			load("res://scripts/home/home_mapper.gd").build_home({"home_type": "house", "floors": 1, "rooms": {"bedroom": 1, "kitchen": 1}, "my_room": {"floor": 0}}, {}, "")
			var manual: Control = load("res://scripts/home/helper_manual_panel.gd").new()
			main.open_panel(manual)
			manual.setup_manual("words", {"text": "We painted my room blue."})
			await _wait(0.6)


## Talking with a friend: chats, gifts, memories, a friend's own life.
func _chat_drives(drive_name: String) -> void:
	match drive_name:
		"begin":
			main.begin_new_world()
			await _wait(1.0)
		"talk":
			await _talk(["hi!", "I had a rough day at work", "my favorite food is ramen"])
		"chat5":
			await _talk(["hello", "I love painting", "how are you?", "I passed my exam!", "bye for now"])
		"log":
			await _talk(["hi there", "I like rainy days"])
			main.game.dialogue.close_box()
			await _wait(0.3)
			main.game.open_menu()
			await _wait(0.3)
			main.open_panel(preload("res://scripts/ui/log_viewer.gd").new())
			await _wait(0.5)
		"idle10":
			main.begin_new_world()
			await _wait(0.5)
			preload("res://scripts/core/starter_content.gd").create_mochi("Bean", Color("#7ad6b0"))
			GameState.add_dream("play guitar at an open mic night")
			GameState.load_world()
			main.start_game()
			await _wait(0.5)
			# 10 game-minutes of idling, 10x faster.
			Engine.time_scale = 10.0
			await main.get_tree().create_timer(600.0).timeout
			Engine.time_scale = 1.0
			print("[drive] journal: ", GameState.journal.moments.map(func(m): return m.title))
			for id in ["mochi", "bean"]:
				for e in ChatLog.read_all(id):
					print("[drive] %s %s: %s" % [id, e.get("kind", "chat"), e.text])
		"dreams", "memory":
			main.start_game()
			await _wait(0.4)
			var scr := {"dreams": "res://scripts/ui/dreams_board.gd", "memory": "res://scripts/ui/memory_book.gd"}
			main.open_panel(load(scr[drive_name]).new())
			await _wait(0.5)
		"night":
			main.start_game()
			await _wait(0.4)
			main.game.daylight.hour_override = 23.0
			main.game.daylight.apply()
			await _wait(0.6)
		"life_ai":
			main.start_game()
			await _wait(0.4)
			GameState.settings["ai"] = {"preset": "ollama", "base_url": "http://127.0.0.1:11434/v1", "model": "qwen2.5:7b-instruct", "timeout_s": 60, "requests_per_minute": 20, "npc_chatter": true}
			GameState.save_settings()
			var g: Node = main.game
			await g.life.chatter.chat("mochi", "bean")
			await _wait(5.0)
			await g.life.events.dream_cheer("bean")
			for id in ["mochi", "bean"]:
				var e: Dictionary = ChatLog.read_all(id).back()
				print("[drive] %s (%s): %s" % [id, e.get("kind", ""), e.text])
		"gift":
			await _talk([])
			main.game.dialogue.advance()
			main.game.dialogue.advance()
			main.game.talk._on_gift_pressed()
			await _wait(0.5)
		"gift_ai":
			main.begin_new_world()
			await _wait(0.5)
			GameState.settings["ai"] = {"preset": "ollama", "base_url": "http://127.0.0.1:11434/v1", "model": "qwen2.5:7b-instruct", "timeout_s": 60}
			GameState.save_settings()
			var g: Node = main.game
			g.approach_character("mochi")
			await _wait(3.0)
			g.dialogue.advance()
			g.dialogue.advance()
			await g.talk.give_gift("cup_of_tea")
			await _wait(4.0)
			print("[drive] gift reply: ", ChatLog.recent("mochi", 1)[0].text)


## The title, Settings, onboarding, worlds and the other screens around play.
func _menu_drives(drive_name: String) -> void:
	match drive_name:
		"menu":
			main.begin_new_world()
			await _wait(0.8)
			main.game.open_menu()
			await _wait(0.5)
		"settings_speed":
			main.begin_new_world()
			await _wait(0.5)
			var settings: Control = load("res://scripts/ui/settings_screen.gd").new()
			settings.main = main
			var before := Time.get_ticks_msec()
			main.open_panel(settings)
			print("[drive] settings_open_ms=%d" % (Time.get_ticks_msec() - before))
			await _wait(0.5)
		"keys":
			main.begin_new_world()
			await _wait(0.8)
			var g: Node = main.game
			var start: Vector2i = g.player.cell()
			Input.action_press("move_left")
			await _wait(0.9)
			Input.action_release("move_left")
			await _wait(0.4)
			var after_left: Vector2i = g.player.cell()
			g.cam.rotate_step(2)  # camera now looks along -X: "up" should move the player toward -X
			await _wait(0.6)
			Input.action_press("move_up")
			await _wait(0.6)
			Input.action_release("move_up")
			await _wait(0.4)
			print("[drive] keys start=%s after_left=%s after_up_rotated=%s" % [start, after_left, g.player.cell()])
		"ollama":
			await scenarios().real_ai_chat({"preset": "ollama", "base_url": "http://localhost:11434/v1", "model": "qwen2.5:7b-instruct", "timeout_s": 120})
		"settings", "bible", "friends":
			await _talk(["my favorite food is ramen", "I love painting"])
			main.game.dialogue.close_box()
			await _wait(0.3)
			var screens := {"settings": "res://scripts/ui/settings_screen.gd", "bible": "res://scripts/ui/world_bible_editor.gd", "friends": "res://scripts/ui/friends_panel.gd"}
			main.open_panel(load(screens[drive_name]).new())
			await _wait(0.6)
		"wrong_key":
			# Settings > AI with Groq chosen and a (made-up) Google key pasted: the note says whose it is
			# and offers its provider; nothing is kept for Groq.
			GameState.settings["ai"] = {"preset": "groq", "keys": {}}
			var ai_page: Control = load("res://scripts/ui/settings_screen.gd").new()
			ai_page.start_on = "AI"
			main.open_panel(ai_page)
			await _wait(0.6)
			ai_page._key.text = "AQ." + "FAKEfake".repeat(6)
			ai_page._key.text_changed.emit(ai_page._key.text)
			await _wait(0.4)
			print("[drive] wrong_key: note=%s | button=%s | kept for Groq=%s" % [ai_page._key_note.text, ai_page._key_fix.text, str(GameState.settings.ai.keys.get("groq", "")) != ""])
		"testconn":
			GameState.settings["ai"] = {"preset": "ollama", "base_url": "http://localhost:11434/v1", "model": "qwen2.5:7b-instruct", "timeout_s": 60}
			GameState.save_settings()
			var r: Dictionary = await AIClient.test_connection()
			print("[drive] test_connection: ", r)
			print("[drive] models: ", await AIClient.list_models())
			GameState.settings["ai"] = {"preset": "ollama", "base_url": "http://localhost:11434/v1", "model": "no-such-model", "timeout_s": 30}
			GameState.save_settings()
			print("[drive] bad model: ", await AIClient.test_connection())
			GameState.settings["ai"] = {"preset": "groq", "api_key": "FAKE-not-a-real-key", "base_url": "", "model": ""}
			GameState.save_settings()
			print("[drive] bad groq key: ", await AIClient.test_connection())
		"onboard":
			main.show_onboarding()
			await _wait(0.3)
			main.get_node("NewWorldHomeMapper").screen._finish("skipped")
			await _until_screen()
			main.screen._world_name.text = "Lumen Hollow"
			main.screen._player_name.text = "Sam"
			main.screen._show(2)
			main.screen._pick_vibe(1)
			main.screen._color = "#7ad6b0"
			main.screen._refresh_preview()
			await _wait(0.4)
		"create_survey":   # a new world opens on the Survey
			main.show_onboarding()
			await _wait(3.0)
		"onboard_first", "onboard_life":   # the first steps after the Survey
			main.show_onboarding()
			await _wait(0.3)
			main.get_node("NewWorldHomeMapper").screen._finish("skipped")
			await _until_screen()
			if drive_name == "onboard_life":
				main.screen._show(1)
			await _wait(0.6)
		"perf":
			await scenarios().perf()
		"scale":
			GameState.settings["ui_scale"] = 1.5
			GameState.save_settings()
			await _talk(["hi there!"])
			await _wait(0.5)
		"scalemenu":
			GameState.settings["ui_scale"] = 1.5
			GameState.save_settings()
			main.begin_new_world()
			await _wait(0.5)
			main.game.open_menu()
			await _wait(0.5)
		"photo":
			main.begin_new_world()
			await _wait(0.8)
			var rel: String = await main.game.take_photo()
			print("[drive] photo: ", rel, " exists=", FileAccess.file_exists(SaveManager.abs_path(rel)))
			await _wait(0.5)
			main.open_panel(preload("res://scripts/ui/memory_book.gd").new())
			await _wait(0.5)
		"snow", "leaves", "petals", "rain", "fireflies":
			main.begin_new_world()
			await _wait(0.5)
			var g: Node = main.game
			if drive_name == "fireflies":
				g.daylight.hour_override = 23.0
				g.daylight.apply()
			g.weather.show_weather(drive_name, g.room.w, g.room.d, g.room.h)
			await _wait(2.5)
		"music_settings", "settings_first_tab":
			# Settings > Music from the title, Festival playing (or Settings as it opens, for its tab bar).
			var ms: Control = load("res://scripts/ui/settings_screen.gd").new()
			ms.main = main
			ms.start_on = "Music" if drive_name == "music_settings" else ""
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--settings-tab="):   # (settings_first_tab: open this tab instead)
					ms.start_on = a.trim_prefix("--settings-tab=")
			main.open_panel(ms)
			await _wait(0.4)
			var page: Node = ms.find_child("Music", true, false)
			var songs: Array = load("res://scripts/world/music_player.gd").songs()
			if page and not songs.is_empty() and drive_name == "music_settings":
				page.toggle(0)
			await _wait(0.6)
			print("[drive] music: ", main.music.current_track(), " previewing=", main.music.previewing())
		"continue":
			# Opens the active world as it is (old saves: the upgrade runs here).
			main.start_game()
			await _wait(2.0)
			for a in OS.get_cmdline_user_args():   # --place=<id>: walk into another place first
				if a.begins_with("--place=") and main.game:
					main.game.go_to_room(a.trim_prefix("--place="))
					for i in 40:
						await _wait(0.15)
						if not main.game._transitioning:
							break
					await _wait(1.0)
			var PlayerLook := preload("res://scripts/characters/player_look.gd")
			print("[drive] world version=%s real=%s dark=%s bag=%d friends=%d room=%s" % [SaveManager.load_world().get("version"), PlayerLook.form_data("real").mode, PlayerLook.form_data("dark").mode, GameState.inventory.get("stacks", []).size(), GameState.characters.size(), GameState.current_room_id])
		"recap", "whats_new":
			main.begin_new_world()
			await _wait(0.5)
			GameState.add_dream("Learn to bake bread")
			await load("res://scripts/ai/conversation.gd").new().player_says("mochi", "I painted the whole afternoon!")
			if drive_name == "recap":
				main.show_recap("2026-01-01T10:00:00")
			else:
				var wn: Control = load("res://scripts/ui/whats_new_panel.gd").new()
				wn.main = main
				main.open_panel(wn)
		"worlds":
			main.begin_new_world()
			await _wait(0.5)
			var Starter := preload("res://scripts/core/starter_content.gd")
			var Slots := preload("res://scripts/core/slots.gd")
			var first: String = SaveManager.slot_id
			var m := Slots.meta(first)
			m["tags"] = ["cozy", "first"]
			m["notes"] = "The one I started with."
			Slots.save_meta(first, m)
			await main.autosave.capture_cover()
			for spec in [["Moon Cafe", "🍵", "#7ad6b0"], ["Dark Castle", "🗝", "#ff9f43"]]:
				SaveManager.new_slot(spec[0], spec[1], spec[2])
				Starter.create_world(spec[0], "Sam")
				Starter.create_mochi()
			main.play_slot(first)
			await _wait(0.4)
			main.open_worlds()
			await _wait(0.6)


## Making things: the character creator, building, the editor, places and doors.
func _making_drives(drive_name: String) -> void:
	match drive_name:
		"creative_pier", "creative_gallery":
			main.begin_new_world()
			await _wait(0.5)
			for card in main.ui.find_children("*", "Control", true, false):
				var script: Script = card.get_script()
				if script and script.resource_path.get_file() in ["today_card.gd", "recap_card.gd"]:
					card.queue_free()
			if drive_name == "creative_pier":
				var rooms: PackedStringArray = load("res://scripts/world/templates.gd").new_level("seaside_pier")
				main.game.load_room(rooms[0])
			else:
				var gallery: Control = load("res://scripts/ui/template_gallery.gd").new()
				gallery.build = main.game.build
				main.open_panel(gallery)
			await _wait(0.6)
		"creator":
			main.begin_new_world()
			await _wait(0.6)
			var cc: Control = preload("res://scripts/world/world_menu.gd").creator("")
			main.open_panel(cc)
			await _wait(0.4)
			cc.card.name_edit.text = "Biscuit"
			cc.canvas.color = Color("#ffb3c7")
			cc._apply_template()
			cc.select_slot("happy")
			await _wait(0.6)
		"create3":
			main.begin_new_world()
			await _wait(0.6)
			var cc: Control = preload("res://scripts/world/world_menu.gd").creator("")
			main.open_panel(cc)
			await _wait(0.3)
			cc.card.name_edit.text = "Biscuit"
			cc.card.fields["personality"].text = "A sleepy cat spirit who loves warm laundry."
			var faces := {"neutral": Color("#ffd166"), "happy": Color("#7ad6b0"), "sad": Color("#8fd3ff")}
			for face in faces:
				cc.select_slot(face)
				cc.canvas.color = faces[face]
				for y in range(6, 28):
					for x in range(6, 26):
						cc.canvas.image.set_pixel(x, y, faces[face])
				cc.canvas.image.set_pixel(12, 14, Color.BLACK)
				cc.canvas.image.set_pixel(19, 14, Color.BLACK)
				cc.canvas._commit()
			cc.save()
			cc.close()
			await _wait(0.6)
			var g: Node = main.game
			g.approach_character("biscuit")
			await _wait(3.5)
			g.dialogue.advance()
			g.dialogue.advance()
			g.dialogue.input.text = "I'm really happy you're here!"
			g.dialogue._send()
			await _wait(3.0)
		"build4":
			await scenarios().build_two_rooms()
		"persist":
			main.start_game()
			await _wait(0.8)
			var g: Node = main.game
			var sign: Dictionary = g.room.find_object("sign_1")
			print("[drive] after restart: room=%s sign=%s" % [GameState.current_room_id, sign.get("interaction_text", "<missing>")])
			var door: Dictionary = g.room.find_object("door_1")
			print("[drive] door_1 leads to: ", door.get("door_target", "<missing>"))
			g.use_object(door)
			await _wait(4.0)
			print("[drive] walked through to: ", GameState.current_room_id, " rooms=", SaveManager.list_rooms())
		"buildview":
			main.start_game()
			await _wait(0.6)
			var g: Node = main.game
			g.build.enter()
			g.build.set_piece("pillar")
			g.build.set_paint("#ffd166", "")
			g.build.cursor = Vector2i(6, 5)
			g.build._place_ghost()
			await _wait(0.8)
		"rooms":
			main.start_game()
			await _wait(0.5)
			main.open_panel(preload("res://scripts/world/world_menu.gd").room_list(main.game))
			await _wait(0.5)
		"web":
			main.begin_new_world()
			await _wait(0.3)
			var Starter := preload("res://scripts/core/starter_content.gd")
			Starter.create_mochi("Bean", Color("#7ad6b0"))
			Starter.create_mochi("Pip", Color("#ffd166"))
			Starter.create_mochi("Lulu", Color("#ffb3c7"))
			GameState.load_world()
			var Bonds := preload("res://scripts/characters/bonds.gd")
			Bonds.add("mochi", "bean", 60.0)
			Bonds.add("bean", "pip", 25.0)
			Bonds.add("pip", "lulu", 85.0)
			var m := GameState.get_character("mochi")
			m.relationship.affinity = 70.0
			main.start_game()
			await _wait(0.4)
			main.open_panel(preload("res://scripts/ui/friendship_web.gd").new())
			await _wait(0.5)
		"door":
			main.begin_new_world()
			await _wait(0.8)
			var g: Node = main.game
			g.use_object(g.room.find_object("door_garden"))
			await _wait(5.0)
		"place_outdoor", "world_map_places", "build_place":
			# Phase 24 screenshots: an outdoor place joined to another, the World Map, the Place tab.
			main.begin_new_world()
			await _wait(0.5)
			var Places := preload("res://scripts/world/places.gd")
			var g: Node = main.game
			var data: Dictionary = g.room.data
			var t := Places.from_template("meadow", str(data.id), str(data.name), int(data.size.w), int(data.size.d))
			for k in ["kind", "walls", "background", "floor", "sky"]:
				data[k] = t[k]
			var east := Places.add_beside(data, "east", SaveManager.list_rooms(), "Orchard")
			east["floor"] = {"color": "#8bbf6a", "texture": ""}
			SaveManager.save_room(east)
			var north := Places.add_beside(data, "north", SaveManager.list_rooms(), "Beach")
			var beach := Places.from_template("beach", str(north.id), "Beach", int(north.size.w), int(north.size.d))
			for k in ["floor", "sky", "background"]:
				north[k] = beach[k]
			SaveManager.save_room(north)
			SaveManager.save_room(data)
			g.daylight.hour_override = 16.0
			g.load_room(str(data.id))
			await _wait(0.6)
			match drive_name:
				"world_map_places":
					var m: Control = load("res://scripts/ui/world_map_view.gd").new()
					main.open_panel(m)
					m.setup_map(g)
				"build_place":
					g.build.enter()
					g.build.set_mode("room")
					await _wait(0.3)
				_:
					g.cam.rotate_step(1)
					g.cam.zoom(1)
					g.cam.zoom(1)
			await _wait(0.8)
		"fountain_strips":
			await load("res://scripts/core/strip_drive.gd").new().run(main)
		"editor":
			main.begin_new_world()
			await _wait(0.5)
			var TemplateFactory := preload("res://scripts/world/template_factory.gd")
			var Templates := preload("res://scripts/world/templates.gd")
			TemplateFactory.ensure_builtin()
			Templates.apply_to_room("garden", "home", "replace")
			main.game.load_room("home")
			await _wait(0.3)
			var g: Node = main.game
			g.build.enter()
			GameState.settings["editor"] = {"advanced": true, "show_map": true}
			g.build.shell.prefs["advanced"] = true
			g.build.shell.prefs["show_map"] = true
			g.build.shell._apply_layout()
			g.build.set_layer("foreground")
			g.build.set_brush_tile("dream_meadow", "canopy")
			g.build.set_tool("brush")
			g.build.cursor = Vector2i(8, 8)
			g.build._place_ghost()
			g.build.shell.palette.tab = "dream_meadow"
			g.build.shell.palette._rebuild_tabs()
			g.build.shell.palette._fill()
			await _wait(0.8)
		"editor_simple":
			main.begin_new_world()
			await _wait(0.5)
			var g: Node = main.game
			g.build.enter()
			g.build.shell.prefs["advanced"] = false
			g.build.shell._apply_layout()
			g.build.shell.refresh()
			await _wait(0.8)
		"turn_and_resize":
			# [GLASS_UI] [PLATFORM] The window turned (a phone upright <-> on its side) and resized, on the title
			# and in a world: every Liquid Glass still copies the screen where it really is, and nothing
			# leaves the screen. Screenshots: --shot-dir=<folder>.
			var dir := ""
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--shot-dir="):
					dir = a.trim_prefix("--shot-dir=")
			var LG := preload("res://scripts/ui/liquid_glass.gd")
			var check := func(where: String) -> void:
				await _wait(0.8)
				var vp := main.get_viewport()
				var view: Rect2 = vp.get_visible_rect()
				var bad := 0
				var glasses := 0
				for n in main.find_children("*", "PanelContainer", true, false):
					if n.get_script() == LG and n.is_visible_in_tree():
						glasses += 1
						if n.is_live():
							var copy: BackBufferCopy = null
							for c in n.get_children(true):
								if c is BackBufferCopy:
									copy = c
							var want: Rect2 = vp.get_final_transform() * (n.get_global_transform_with_canvas() * Rect2(Vector2(-24, -24), n.size + Vector2(48, 48)))
							if copy == null or not copy.rect.is_equal_approx(want):
								bad += 1
								print("[drive] turn: %s glass %s copies %s, is at %s" % [where, n.name, copy.rect if copy else "nothing", want])
				var off := 0
				for b in main.find_children("*", "Button", true, false):
					if b.is_visible_in_tree() and b.get_global_rect().size.x > 0:
						var r: Rect2 = b.get_global_rect()
						if r.end.x > view.end.x + 1 or r.end.y > view.end.y + 1 or r.position.x < -1 or r.position.y < -1:
							off += 1
				print("[drive] turn: %s %s: %d glass, %d copying the wrong place, %d buttons off screen" % [where, DisplayServer.window_get_size(), glasses, bad, off])
				if dir != "":
					await RenderingServer.frame_post_draw
					vp.get_texture().get_image().save_png(dir.path_join("turn_%s_%dx%d.png" % [where, DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]))
			for s in [Vector2i(412, 892), Vector2i(892, 412), Vector2i(412, 892)]:
				DisplayServer.window_set_size(s)
				await check.call("title")
			main.begin_new_world()
			await _wait(1.0)
			for s in [Vector2i(412, 892), Vector2i(892, 412), Vector2i(1600, 900), Vector2i(1280, 720)]:
				DisplayServer.window_set_size(s)
				await check.call("world")


## Battles, the Battle Maker and stories.
func _battle_drives(drive_name: String) -> void:
	match drive_name:
		"battle_targets", "battle_magic", "battle_review", "battle_fightbar", "battle_telegraph", "battle_party_end":
			# The three-enemy original demo, you choosing for each friend (Update 9 screens).
			main.begin_new_world()
			await _wait(0.5)
			GameState.settings["battle_choose_for_friends"] = true
			var dg: Node = main.game
			dg.battles.start(preload("res://scripts/battle/battle_data.gd").demonstration("clockwork_picnic"), [])
			for i in 60:
				await _wait(0.15)
				if dg.battles.screen and str(dg.battles.screen.phase) == "menu":
					break
			await _wait(0.4)
			var ds: Control = dg.battles.screen
			if ds == null:
				return
			match drive_name:
				"battle_targets":
					ds.choose("fight")
				"battle_magic":
					ds._pick({"cmd": "defend"})
					ds.choose("magic")
				"battle_review", "battle_fightbar":
					ds._pick({"cmd": "fight", "target": 1})
					ds._pick({"cmd": "act", "target": 0, "arg": 1})
					ds._pick({"cmd": "fight", "target": 2})
					if drive_name == "battle_fightbar":
						ds._resolve()
						await _wait(0.5)
				"battle_telegraph":
					for k in 3:
						ds._pick({"cmd": "defend"})
					ds._resolve()
					for i in 60:
						await _wait(0.1)
						if str(ds.phase) == "telegraph":
							break
				"battle_party_end":
					for e in ds.state.enemies:
						e.mercy = int(e.mercy_max)
					for k in 3:
						ds._pick({"cmd": "spare", "target": k})
					ds._resolve()
					for i in 80:
						await _wait(0.15)
						if str(ds.phase) == "end":
							break
			await _wait(0.6)
		"battle_menu", "battle_dodge", "battle_act", "battle_end":
			main.begin_new_world()
			await _wait(0.5)
			var bg: Node = main.game
			var bfoe := str(bg.actors.keys()[0])
			var BattleData := preload("res://scripts/battle/battle_data.gd")
			bg.battles.start(BattleData.from_template("star_shower", GameState.get_character(bfoe)), [])
			for i in 40:   # until the menu is up (slow capture runs draw a few frames a second)
				await _wait(0.15)
				if bg.battles.screen and str(bg.battles.screen.phase) == "menu":
					break
			await _wait(0.6)
			var scr: Control = bg.battles.screen
			if scr and drive_name == "battle_act":
				scr.choose("act")
			elif scr and drive_name == "battle_end":
				scr.state.enemies[0].mercy = int(scr.state.enemies[0].mercy_max)
				scr.choose("spare")
				for i in 40:
					await _wait(0.15)
					if str(scr.phase) == "review":
						scr._resolve()
					if str(scr.phase) == "end":
						break
				await _wait(0.8)
			elif scr and drive_name == "battle_dodge":
				scr._pick({"cmd": "defend"})
				if str(scr.phase) == "review":
					scr._resolve()
				await _wait(2.6)
				var mm := InputEventMouseMotion.new()
				mm.position = scr.box.position + scr.box.size * Vector2(0.3, 0.7)
				scr._gui_input(mm)
				await _wait(1.2)
			await _wait(0.3)
		"battle_maker", "battle_maker_advanced":
			main.begin_new_world()
			await _wait(0.5)
			main.game.battles.open_maker("")
			await _wait(0.4)
			for p in main.panels:
				if is_instance_valid(p) and p.has_method("setup_maker"):
					p.wave_i = 1
					p.advanced = drive_name == "battle_maker_advanced"
					p.refresh()
			await _wait(1.4)
		"story", "story_log", "story_requests", "story_found":
			main.begin_new_world()
			await _wait(0.5)
			for n in main.ui.get_children():   # the start-up cards ("Got it")
				var sc: Script = n.get_script()
				if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
					n.queue_free()
			var sp: Control = load("res://scripts/ui/story_panel.gd").new()
			if drive_name == "story_found":
				sp.tab = "found"
				var vs := preload("res://scripts/variety/visitors.gd")
				var vid := vs.arrive({"extra": {"name": "Wren", "look": "cozy", "about": "Collects maps of places that don't exist."}, "room": GameState.current_room_id}, "2026-10-01")
				vs.farewell_old("2026-10-02")
				print("[drive] traveler ", vid, " passed: ", vs.passed().size())
			if drive_name == "story_requests":
				sp.tab = "requests"
				var rq := preload("res://scripts/variety/requests.gd")
				var rr := RandomNumberGenerator.new()
				rr.seed = 5
				rq.offer(str(main.game.actors.keys()[0]), rr)
			if drive_name == "story_log":
				sp.tab = "log"
				GameState.world["battle_log"] = [{"battle": "Star shower vs. Mochi", "outcome": "spared", "party": ["Sam"], "enemies": [{"name": "Mochi"}], "when": "2026-10-17T15:00:00"}]
			main.open_panel(sp)
			await _wait(0.8)


## The Music tab's secret, by the drive and by hand.
func _secret_drives(drive_name: String) -> void:
	match drive_name:
		"secret":
			# The title's Music secret: reach the bottom, press the button, then show the picture
			# (a mid-way screenshot with --secret-shot=<png>), then the title with Settings reading 👀.
			var ss: Control = load("res://scripts/ui/settings_screen.gd").new()
			ss.main = main
			ss.start_on = "Music"
			main.open_panel(ss)
			await _wait(0.6)
			var mp: ScrollContainer = ss.find_child("Music", true, false)
			mp.scroll_vertical = int(mp.get_v_scroll_bar().max_value)
			var yams: Button = mp.find_child("Yams", true, false)
			print("[drive] secret: at bottom=%s, shown=%s, label=%s" % [mp.at_bottom(), mp.secret_shown(), yams.text])
			yams.pressed.emit()
			await _wait(2.5)
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--secret-shot="):
					await RenderingServer.frame_post_draw
					main.get_viewport().get_texture().get_image().save_png(a.trim_prefix("--secret-shot="))
			var shown := main.get_node_or_null("Secret")
			var pic: TextureRect = shown.find_child("Picture", true, false) if shown else null
			print("[drive] secret: picture %s, size %s, of %d available" % ["shown" if pic and pic.texture else "none", pic.texture.get_size() if pic and pic.texture else Vector2.ZERO, preload("res://scripts/ui/secret_pictures.gd").all().size()])
			await _wait(3.0)
			var sb: Button = main.screen.find_child("SettingsButton", true, false) if main.screen else null
			print("[drive] secret: after 5 s overlay=%s panels=%d settings label=%s" % [is_instance_valid(shown) and shown.is_inside_tree(), main.panels.size(), sb.text if sb else "?"])
		"secret_by_hand":
			# The same secret the way a person finds it: click Settings on the title, click Music, wheel down
			# and click the button that appears at the end of the list.
			var vp := main.get_viewport()
			var click := func(c: Control) -> void:
				var sc: Node = c.get_parent()   # (scrolled into view first, as a person would)
				while sc and not sc is ScrollContainer:
					sc = sc.get_parent()
				if sc:
					(sc as ScrollContainer).ensure_control_visible(c)
					await _wait(0.2)
				var at: Vector2 = c.get_global_rect().get_center()
				for down in [true, false]:
					var e := InputEventMouseButton.new()
					e.button_index = MOUSE_BUTTON_LEFT
					e.pressed = down
					e.position = at
					e.global_position = at
					vp.push_input(e, true)
					await _wait(0.1)
			await _wait(1.0)
			# --secret-in-world: the same from a new world's Menu (what C / Tab / the Menu button opens).
			var in_world := "--secret-in-world" in OS.get_cmdline_user_args()
			var sbtn: Button = main.screen.find_child("SettingsButton", true, false) if main.screen else null
			if in_world:
				if "--secret-continue" in OS.get_cmdline_user_args():
					main.start_game()   # (the save's own world, as Continue / Begin opens it)
					await _wait(4.0)
				else:
					main.begin_new_world()
					await _wait(1.5)
				for n in main.ui.find_children("*", "", true, false):   # the start-up cards
					var sc: Script = n.get_script()
					if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
						n.queue_free()
				await _wait(0.3)
				main.game.open_menu()
				await _wait(0.8)
				sbtn = null
				for b in (main.panels.back() as Node).find_children("*", "Button", true, false) if not main.panels.is_empty() else []:
					if (b as Button).text == "Settings":
						sbtn = b
			print("[drive] secret_by_hand: %s Settings button=%s" % ["world Menu" if in_world else "title", sbtn.text if sbtn else "MISSING"])
			await click.call(sbtn)
			await _wait(0.8)
			var chip: Button = main.find_child("Chip_Music", true, false)
			print("[drive] secret_by_hand: Music chip=%s" % [chip != null])
			if chip == null:
				var chips: Array = main.find_children("Chip_*", "Button", true, false).map(func(c): return str(c.name))
				print("[drive] secret_by_hand: panels=%d chips=%s, under the Settings button: %s" % [main.panels.size(), chips, vp.gui_get_hovered_control().get_path() if vp.gui_get_hovered_control() else "nothing"])
				return
			await click.call(chip)
			await _wait(0.6)
			var mp: ScrollContainer = main.find_child("Music", true, false)
			var bar := mp.get_v_scroll_bar()
			print("[drive] secret_by_hand: page visible=%s height=%.0f content max=%.0f page=%.0f" % [mp.is_visible_in_tree(), mp.size.y, bar.max_value, bar.page])
			var mid: Vector2 = mp.get_global_rect().get_center()
			var notch := func() -> void:   # (a real wheel notch: pressed, then released; UI coordinates, which a phone scales)
				for down in [true, false]:
					var w := InputEventMouseButton.new()
					w.button_index = MOUSE_BUTTON_WHEEL_DOWN
					w.pressed = down
					w.factor = 1.0
					w.position = mid
					w.global_position = mid
					vp.push_input(w, true)
			var slow := "--secret-style=slow" in OS.get_cmdline_user_args()
			var n := 0
			var revealed_on_last_scroll := false
			while not mp.at_bottom() and n < 400:
				notch.call()
				n += 1
				if mp.at_bottom():
					revealed_on_last_scroll = mp.secret_shown()
					break
				await _wait(0.75 if slow else 0.03)
			print("[drive] secret_by_hand: %d notches, scrolled to %d of %.0f, at bottom=%s, revealed on last scroll=%s" % [n, mp.scroll_vertical, bar.max_value - bar.page, mp.at_bottom(), revealed_on_last_scroll])
			await main.get_tree().process_frame
			var yams: Button = mp.find_child("Yams", true, false)
			print("[drive] secret_by_hand: button shown=%s on screen=%s label=%s" % [mp.secret_shown(), mp.get_global_rect().encloses(yams.get_global_rect()), yams.text])
			if mp.secret_shown():
				yams.pressed.connect(func(): print("[drive] secret_by_hand: the button heard the click"))
				var hover := InputEventMouseMotion.new()
				hover.position = yams.get_global_rect().get_center()
				hover.global_position = hover.position
				vp.push_input(hover, true)
				await _wait(0.2)
				var under := vp.gui_get_hovered_control()
				print("[drive] secret_by_hand: under the pointer: %s (disabled=%s, filter=%d)" % [under.get_path() if under else "nothing", yams.disabled, yams.mouse_filter])
				await click.call(yams)
				await _wait(2.0)
				var shown := main.get_node_or_null("Secret")
				print("[drive] secret_by_hand: picture shown=%s" % [shown != null])
				await _wait(4.0)
				if in_world:
					var top: Node = main.panels.back() if not main.panels.is_empty() else null
					var labels: Array = top.find_children("*", "Button", true, false).map(func(x): return str(x.text)) if top else []
					print("[drive] secret_by_hand: still in the world=%s, panels=%d, top=%s, 👀 there=%s, Settings there=%s" % [main.game != null, main.panels.size(), top.get_script().resource_path.get_file() if top else "none", "👀" in labels, "Settings" in labels])
				else:
					var sb2: Button = main.screen.find_child("SettingsButton", true, false) if main.screen else null
					print("[drive] secret_by_hand: back on title, Settings reads %s" % [sb2.text if sb2 else "?"])
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--after-shot="):
						await RenderingServer.frame_post_draw
						main.get_viewport().get_texture().get_image().save_png(a.trim_prefix("--after-shot="))


## Polox for Android finding the PC, and the ping window.
func _phone_app_drives(drive_name: String) -> void:
	match drive_name:
		"app_connect", "app_pin", "app_qr":
			# Screenshots of Polox for Android's Connect screen (run with --app-mode).
			await _wait(1.2)
			var panel: Control = null
			for p in main.panels:
				if is_instance_valid(p) and p.has_method("setup_connect"):
					panel = p
			if panel and drive_name == "app_pin":
				panel.target = {"url": "http://192.168.1.42:8765", "path": "home", "name": "EXAMPLE-PC"}
				panel.show_step("pin")
				await _wait(0.2)
				for k in ["4", "8", "2"]:
					panel.press_key(k)
			elif panel and drive_name == "app_qr":
				panel.show_step("qr")
			await _wait(0.6)
		"phone_link_android":
			main.begin_new_world()
			await _wait(0.5)
			main.configure_phone_link()
			main.phone_link.mode = "lan"
			main.phone_link.start(8790, "127.0.0.1")
			main.open_phone_link_settings()
			await _wait(0.8)
			for t in main.ui.find_children("*", "", true, false):
				if t.get_script() == load("res://scripts/ui/phone_link_tab.gd"):
					t._app_steps = false
					t._app_pair = true
					t.refresh()
					await _wait(0.3)
					var up: Node = t
					while up and not up is ScrollContainer:
						up = up.get_parent()
					if up:
						for c in t.find_children("*", "Label", true, false):
							if (c as Label).text.begins_with("Polox for Android"):
								(up as ScrollContainer).scroll_vertical = int(c.global_position.y - 120)
					break
			await _wait(0.6)
		"ping_window":
			main._start_ping_mode("127.0.0.1")   # (screenshots stay on 127.0.0.1)
			await _wait(8.0)


## Phase 29 screens: the way home in the Dream World (and its choice), your room in the Light World,
## and the World Map's two worlds. (The journey itself runs with Reduce motion so captures are quick.)
func _light_world(drive_name: String) -> void:
	main.begin_new_world()
	await _wait(0.8)
	var g: Node = main.game
	g.daylight.hour_override = 11.0
	g.daylight.apply()
	var Realms := preload("res://scripts/world/realms.gd")
	for n in main.ui.find_children("*", "", true, false):   # the start-up cards
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()
	match drive_name:
		"way_home", "way_home_choice":
			var gate: Dictionary = Realms.gate_of(g.room.data)
			var gp: Array = gate.get("pos", [6, 0, 6])
			g.player.position = g.room.cell_center(Vector2i(int(gp[0]) - 1, int(gp[2]) + 1))
			g.cam.snap_to_target()
			await _wait(0.6)
			if drive_name == "way_home_choice":
				g.dark.use_gate(gate)
				await _wait(0.5)
		"light_room", "light_map":
			preload("res://scripts/world/light_home.gd").ensure_entry()
			preload("res://scripts/world/light_home.gd").defer_survey()
			GameState.settings["reduce_motion"] = true
			await g.dark.go_light()
			GameState.settings["reduce_motion"] = false
			g.daylight.apply()
			await _wait(1.0)
			await _light_view_options(g)
			if drive_name == "light_map":
				var map: Control = load("res://scripts/ui/world_map_view.gd").new()
				main.open_panel(map)
				map.setup_map(g)
				await _wait(0.6)
		"world_sheet":
			g.open_world_sheet()
			await _wait(0.5)
		"friends_sheet":
			main.open_panel(load("res://scripts/world/world_menu.gd").friends(g))
			await _wait(0.5)
		"dark_map":
			var map2: Control = load("res://scripts/ui/world_map_view.gd").new()
			main.open_panel(map2)
			map2.setup_map(g)
			await _wait(0.6)


## The whole Light World flow on the real screens, with a made-up town: an old map and a piece of your own
## on the street first, then the Survey through LOOK IT UP, the house preview, the map preview and Apply
## (survey_streets: ends on the new street; survey_streets_preview: stops at the map preview). The other two
## prove a bad answer (survey_streets_fail: an HTML page instead of map data) and Cancel at the preview
## leave the old streets and your piece exactly as they were. Prints [drive] lines a log can be checked for.
func _survey_streets(drive_name: String, g: Node, answers: Dictionary, fixture: String) -> void:
	var Osm := load("res://scripts/home/osm.gd")
	var HomeStore := load("res://scripts/home/home_store.gd")
	var RoomEditor := load("res://scripts/world/room_editor.gd")
	var HoodBuilder := load("res://scripts/home/hood_builder.gd")
	var Mapper := load("res://scripts/home/home_mapper.gd")
	# The old map: the plain town, with a birdbath you placed yourself.
	var town: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/osm_madeup_town.json"))
	var old_extract: Dictionary = Osm.clean(town, 10.0, 10.0, 250)
	HomeStore.save_home({"plan": {}, "answers": {}})
	Mapper.build_streets(old_extract, {"radius": 250})
	var home_chunk := str(HoodBuilder.build(old_extract).home_chunk)
	var p: Dictionary = SaveManager.load_room(home_chunk)
	var placed := false
	for z in range(5, 55):
		for x in range(5, 55):
			if not placed and RoomEditor.object_at(p, x, z).is_empty() and not (p.buildings as Array).any(func(b): return (b.cells as Array).any(func(c): return int(c[0]) == x and int(c[1]) == z)) and not HoodBuilder._barrier_at(p, Vector2i(x, z)):
				var mine: Dictionary = RoomEditor.add_object(p, x, z, "birdbath")
				mine["user"] = true
				SaveManager.save_room(p)
				placed = true
	var old_map := FileAccess.get_sha256(HomeStore.path("osm.json"))
	var old_rooms := Array(SaveManager.list_light_rooms()).filter(func(id): return str(id).begins_with("lw_hood_"))
	print("[drive] old map: %d features, %d street blocks, birdbath placed" % [old_extract.features.size(), old_rooms.size()])
	# The Survey, for real: answers typed, LOOK IT UP, the house kept from its preview.
	var mapper: Node = Mapper.new()
	main.add_child(mapper)
	mapper.available_override = {"claude_code": true, "none": true}
	mapper.recorded = fixture
	mapper.recorded_coords = {"lat": 10.0, "lon": 10.0}
	mapper.recorded_osm = ProjectSettings.globalize_path("res://tests/fixtures/osm_error_page.html" if drive_name == "survey_streets_fail" else "res://tests/fixtures/osm_madeup_town_detail.json")
	var lines: Array = []
	mapper.say_to = func(l): lines.append(l); print("[drive] survey says: ", l)
	var result := {"entry": ""}
	var run := func() -> void: result.entry = await mapper.run(main)
	run.call()
	await _wait(0.3)
	var sc: Control = mapper.screen
	for _i in 400:
		var st: Dictionary = sc.step()
		if str(st.get("kind", "")) == "consent" and sc._area.get_child_count() > 0 and not sc._typing:
			break
		if sc._typing or sc._waiting_tap:
			sc._tap()
		elif str(st.get("kind", "")) == "text":
			if str(st.key) == "address":
				sc.field.text = str(answers.address)
				sc._submit_text(str(answers.address))
			else:
				sc._skip_step()
		elif str(st.get("kind", "")) == "counts":
			for b in sc._area.find_children("*", "Button", true, false):
				if (b as Button).text.begins_with("THAT'S"):
					(b as Button).pressed.emit()
					break
		else:
			var bs: Array = sc._area.find_children("*", "Button", true, false)
			if not bs.is_empty():
				(bs[0] as Button).pressed.emit()
		await _wait(0.03)
	print("[drive] consent screen reached; map still old: ", FileAccess.get_sha256(HomeStore.path("osm.json")) == old_map)
	for b in sc.find_children("LookItUp", "Button", true, false):
		(b as Button).pressed.emit()
	var t0 := Time.get_ticks_msec()
	var decided := false
	while str(result.entry) == "" and Time.get_ticks_msec() - t0 < 30000:
		if is_instance_valid(sc):
			for b in sc.find_children("KeepHomePreview", "Button", true, false):
				(b as Button).pressed.emit()
		var preview = mapper._map_preview   # (untyped: the mapper keeps the reference after the panel is freed)
		if not decided and is_instance_valid(preview) and not preview.is_queued_for_deletion() and not (preview.buttons as Array).is_empty():
			print("[drive] map preview open with %d choice(s)" % (preview.buttons as Array).size())
			if drive_name == "survey_streets_preview":
				return   # (the capture shows the preview)
			await _wait(0.4)
			decided = true
			if drive_name == "survey_streets_cancel":
				preview.on_back()   # the panel's Back / Cancel
			else:
				(preview.buttons[0] as Button).pressed.emit()
		await _wait(0.1)
	var new_rooms := Array(SaveManager.list_light_rooms()).filter(func(id): return str(id).begins_with("lw_hood_"))
	var same_map := FileAccess.get_sha256(HomeStore.path("osm.json")) == old_map
	var kept := new_rooms.any(func(id): return (SaveManager.load_room(id).objects as Array).any(func(o): return bool(o.get("user", false))))
	var same_rooms := new_rooms.size() == old_rooms.size() and old_rooms.all(func(id): return new_rooms.has(id))
	print("[drive] survey done: entry=%s home=%s map_unchanged=%s blocks=%d->%d same_blocks=%s birdbath_kept=%s snapshots=%s" % [str(result.entry) != "", str(HomeStore.exists()), str(same_map), old_rooms.size(), new_rooms.size(), str(same_rooms), str(kept), str(HomeStore.snapshots().map(func(s): return s.kind))])
	if str(result.entry) == "":
		print("[drive] survey did not finish in time")
	# Show where you ended up: the street outside your door.
	GameState.settings["reduce_motion"] = true
	await g.dark.go_light()
	GameState.settings["reduce_motion"] = false
	var gid: String = load("res://scripts/home/home_places.gd").place_id(0)
	for o in SaveManager.load_room(gid).objects:
		if bool(o.get("street_gate", false)):
			g.load_room(str(o.door_target), gid)
	g.daylight.apply()
	g.cam.distance = g.cam.ZOOM_MAX
	g.cam.snap_to_target()
	await _wait(0.8)


## Phase 30 screens: the Survey (its voice, a question, the rooms, a floor to pick, the consent screen,
## the house drawing itself in), the house in the Light World, and My home's sketch and sources. A
## made-up house only (tests/fixtures), never anyone's real one.
func _home(drive_name: String) -> void:
	main.begin_new_world()
	await _wait(0.8)
	var g: Node = main.game
	g.daylight.hour_override = 11.0
	g.daylight.apply()
	for n in main.ui.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()
	var answers := {"address": "12 Example Lane, Testville", "address_level": "full", "home_type": "house", "floors": 2,
		"rooms": {"bedroom": 3, "bathroom": 2, "kitchen": 1, "living": 1, "dining": 1, "office": 0, "laundry": 1, "garage": 0},
		"entry_room": "hall", "my_room": {"floor": 1, "where": "front", "wall": "#a9c4dc", "floor_kind": "carpet", "bed": "single", "desk": true},
		"floor_kinds": {"kitchen": "tile", "living": "wood"}, "memory": "Pancakes every Sunday"}
	var fixture := ProjectSettings.globalize_path("res://tests/fixtures/home_research_madeup.json")
	if drive_name.begins_with("survey_streets"):
		await _survey_streets(drive_name, g, answers, fixture)
		return
	if drive_name.begins_with("survey"):
		var mapper: Node = load("res://scripts/home/home_mapper.gd").new()
		main.add_child(mapper)
		mapper.available_override = {"claude_code": true, "none": true}
		mapper.recorded = fixture
		mapper.run(main)
		await _wait(0.3)
		var sc: Control = mapper.screen
		var stop: String = {"survey_hello": "hello", "survey_address": "address", "survey_rooms": "rooms", "survey_floor": "my_floor_kind", "survey_consent": "consent", "survey_build": "consent"}[drive_name]
		for _i in 300:
			var st: Dictionary = sc.step()
			if str(st.get("id", "")) == stop and (stop == "hello" or sc._area.get_child_count() > 0) and not sc._typing:
				if stop != "hello" or sc._line_i >= 2:
					break
			if sc._typing or sc._waiting_tap:
				sc._tap()
			elif str(st.get("kind", "")) == "text":
				if str(st.key) == "address":
					sc.field.text = str(answers.address)
					sc._submit_text(str(answers.address))
				else:
					sc._skip_step()
			elif str(st.get("kind", "")) == "counts":
				for b in sc._area.find_children("*", "Button", true, false):
					if (b as Button).text.begins_with("THAT'S"):
						(b as Button).pressed.emit()
						break
			else:
				var bs: Array = sc._area.find_children("*", "Button", true, false)
				if not bs.is_empty():
					(bs[0] as Button).pressed.emit()
			await _wait(0.05)
		if drive_name == "survey_build":
			for b in sc.find_children("LookItUp", "Button", true, false):
				(b as Button).pressed.emit()
			await _wait(1.6)
		else:
			await _wait(0.6)
		return
	load("res://scripts/home/home_mapper.gd").build_home(answers, load("res://scripts/home/home_model.gd").clean_research(JSON.parse_string(FileAccess.get_file_as_string(fixture))), "claude_code")
	match drive_name:
		"home_mine", "home_ground":
			GameState.settings["reduce_motion"] = true
			await g.dark.go_light()
			GameState.settings["reduce_motion"] = false
			if drive_name == "home_ground":
				g.load_room("lw_floor_0")
			g.daylight.apply()
			await _wait(1.0)
		"home_sketch", "home_sources":
			var p: Control = load("res://scripts/home/map_home_panel.gd").new()
			main.open_panel(p)
			p.setup_home(g)
			if drive_name == "home_sources":
				p.show_tab("sources")
			await _wait(0.6)
		"home_tell":
			GameState.settings["reduce_motion"] = true
			await g.dark.go_light()
			GameState.settings["reduce_motion"] = false
			var tp: Control = load("res://scripts/home/tell_polox_panel.gd").new()
			main.open_panel(tp)
			tp.setup_tell(g, "We painted my room green last summer. The hallway has a blue runner and our family photos. My room used to be the playroom. There's a piano somewhere.")
			await _wait(0.6)
		"home_unsure", "home_timeline":
			var hp: Control = load("res://scripts/home/map_home_panel.gd").new()
			main.open_panel(hp)
			hp.setup_home(g)
			if drive_name == "home_timeline":
				var mine_id := ""
				for f in load("res://scripts/home/home_store.gd").load_home().plan.floors:
					for r in f.rooms:
						if bool(r.get("mine", false)):
							mine_id = str(r.id)
				load("res://scripts/home/home_edit.gd").commit([{"type": "wall", "level": 1, "room": mine_id, "color": "#b5cfa8"}], "words")
				hp.home = load("res://scripts/home/home_store.gd").load_home()
			hp.show_tab("unsure" if drive_name == "home_unsure" else "timeline")
			await _wait(0.6)
		"home_look_again":
			load("res://scripts/home/home_store.gd").save_research(load("res://scripts/home/home_model.gd").clean_research(JSON.parse_string(FileAccess.get_file_as_string(fixture))))
			var hp2: Control = load("res://scripts/home/map_home_panel.gd").new()
			main.open_panel(hp2)
			hp2.setup_home(g)
			hp2.recorded_look = ProjectSettings.globalize_path("res://tests/fixtures/home_research_madeup_later.json")
			hp2._run_look_again("claude_code")
			await _wait(1.2)
		"hood_street", "hood_detail", "hood_refs", "hood_park", "hood_map", "anim_street", "hood_wide", "hood_wide_map":
			var Osm := load("res://scripts/home/osm.gd")
			# hood_detail / hood_refs: the same made-up town with sidewalks, lamps, fences, roofs and a courtyard.
			# hood_wide: the same, zoomed right out from the sidewalk; --town=<extract.json> swaps in another
			# extract (e.g. the public-landmark one the osm_landmark drive saved), never a private one.
			var town_file := "osm_madeup_town_detail.json" if drive_name in ["hood_detail", "hood_refs", "hood_wide", "hood_wide_map"] else "osm_madeup_town.json"
			var town_path := "res://tests/fixtures/" + town_file
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--town=") and drive_name.begins_with("hood_wide"):
					town_path = a.trim_prefix("--town=")
			var town: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(town_path))
			if town.get("format", 0) is float and town.has("features"):
				town = {"elements": [], "extract": town}   # an already-cleaned extract: used as it is below
			answers["radius"] = 250
			answers["places"] = "Maple Park"
			var extract: Dictionary = town.extract if town.has("extract") else Osm.clean(town, 10.0, 10.0, 250)
			if town.has("extract"):
				answers["radius"] = int(extract.get("radius", 250))
			load("res://scripts/home/home_mapper.gd").build_streets(extract, answers)
			GameState.settings["reduce_motion"] = true
			await g.dark.go_light()
			var gid: String = load("res://scripts/home/home_places.gd").place_id(0)
			var street := ""
			for o in SaveManager.load_room(gid).objects:
				if bool(o.get("street_gate", false)):
					street = str(o.door_target)
			if drive_name == "hood_park":
				street = load("res://scripts/world/light_life.gd").park_place() if load("res://scripts/world/light_life.gd").has_method("park_place") else street
			g.load_room(street, gid if drive_name in ["hood_street", "hood_detail", "hood_refs", "anim_street", "hood_wide"] else "")
			GameState.settings["reduce_motion"] = false
			g.daylight.apply()
			await _wait(1.0)
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--cam-turn="):   # (the same spot seen from another side: 45-degree steps)
					g.cam.rotate_step(int(a.trim_prefix("--cam-turn=")))
					g.cam.snap_to_target()
					await _wait(1.0)
			if drive_name == "hood_wide":
				# Out on the sidewalk, camera as far out as the + / - buttons allow, so the whole block shows.
				g.cam.distance = g.cam.ZOOM_MAX
				var sl0: Node3D = g.street_life
				if sl0 and not sl0.strips.is_empty():
					sl0.strips.sort_custom(func(a, b): return sl0._dist_to(a, g.player.position) < sl0._dist_to(b, g.player.position))
					var s1: Dictionary = sl0.strips[0]
					var side1 := Vector3(0, 0, -2.2) if int(s1.rot) == 0 else Vector3(-2.2, 0, 0)
					g.player.position = (s1.from as Vector3).lerp(s1.to, 0.5) + side1
				g.cam.snap_to_target()
				await _wait(0.8)
			if drive_name == "hood_wide_map":
				var map0: Control = load("res://scripts/ui/world_map_view.gd").new()
				main.open_panel(map0)
				map0.setup_map(g)
				await _wait(0.6)
			if drive_name == "hood_refs":
				var refs: Control = load("res://scripts/home/map_refs_panel.gd").new()
				main.open_panel(refs)
				refs.setup_refs()
				await _wait(0.6)
			if drive_name == "hood_map":
				var map: Control = load("res://scripts/ui/world_map_view.gd").new()
				main.open_panel(map)
				map.setup_map(g)
				await _wait(0.6)
			if drive_name == "anim_street":
				# A car coming along the road past you, birds overhead (the shot catches them moving).
				var sl: Node3D = g.street_life
				if not sl.strips.is_empty():
					sl.strips.sort_custom(func(a, b): return sl._dist_to(a, g.player.position) < sl._dist_to(b, g.player.position))
					var s0: Dictionary = sl.strips[0]
					var a0: Vector3 = s0.from
					var b0: Vector3 = s0.to
					var t0 := clampf((g.player.position - a0).dot(b0 - a0) / maxf(0.001, a0.distance_squared_to(b0)), 0.1, 0.9)
					var side := Vector3(0, 0, -2.2) if int(s0.rot) == 0 else Vector3(-2.2, 0, 0)
					g.player.position = a0.lerp(b0, t0) + side
					g.cam.snap_to_target()
				sl.spawn_car(g.player.position)
				sl.spawn_birds(g.player.position)
				await _wait(1.2)
		"anim_reveal", "anim_sheet":
			GameState.settings["reduce_motion"] = true
			await g.dark.go_light()
			GameState.settings["reduce_motion"] = false
			g.daylight.apply()
			var mr2: Rect2i = load("res://scripts/home/home_places.gd").mine_rect(g.room.data)
			g.player.position = g.room.cell_center(mr2.get_center())
			g.cam.snap_to_target()
			await _wait(0.6)
			# Left running: a short --shot-delay catches it partway.
			if drive_name == "anim_reveal":
				g.reveal_home.call_deferred()
			else:
				g.open_bag()
		"moment_fountain", "moment_back":
			if drive_name == "moment_fountain":
				GameState.settings["reduce_motion"] = true
				await g.dark.go_light()
				GameState.settings["reduce_motion"] = false
				g.dark.go_dark.call_deferred()
				var t0 := Time.get_ticks_msec()
				while g.signatures.last != "first_fountain" and Time.get_ticks_msec() - t0 < 8000:
					await _wait(0.1)
				await _wait(0.9)
			else:
				g.daylight.apply()
				await _wait(0.6)
				g.signatures.home_after_battle.call_deferred({"outcome": "spared"})
				await _wait(0.7)
		"decor_open", "things_to_do", "journal":
			GameState.settings["reduce_motion"] = true
			await g.dark.go_light()
			GameState.settings["reduce_motion"] = false
			g.daylight.apply()
			var mr: Rect2i = load("res://scripts/home/home_places.gd").mine_rect(g.room.data)
			g.player.position = g.room.cell_center(mr.get_center())
			g.cam.snap_to_target()
			await _wait(0.4)
			match drive_name:
				"decor_open":
					g.build.enter()
					await _wait(0.2)
					g.decor.choose("plant")
				"things_to_do":
					g.light_life.open_things_to_do()
				"journal":
					load("res://scripts/home/journal_panel.gd").write("Rain all afternoon. Made tea and finally fixed the wobbly shelf.")
					g.light_life.journal()
			await _wait(0.5)
		"home_settings":
			var s2: Control = load("res://scripts/ui/settings_screen.gd").new()
			main.open_panel(s2)
			await _wait(0.3)
			var tabs: TabContainer = s2.find_children("*", "TabContainer", true, false)[0]
			for i in tabs.get_tab_count():
				if tabs.get_tab_title(i) == "Light World":
					tabs.current_tab = i
			await _wait(0.5)


## Phase 10 screens: the character sheet tabs, the bag, the Workshop, the
## player wearing gear in the room, and a gift in a chat.
func _phase10(drive_name: String) -> void:
	main.begin_new_world()
	await _wait(0.6)
	var g: Node = main.game
	var WorldMenu := preload("res://scripts/world/world_menu.gd")
	var ItemEffects := preload("res://scripts/items/item_effects.gd")
	var Items := preload("res://scripts/items/items.gd")
	var Inventory := preload("res://scripts/items/inventory.gd")
	GameState.world.player["name"] = "Sam"
	GameState.world.player["nicknames"] = "Sammy"
	GameState.world.player["about"] = "I grow tomatoes on my balcony and I'm learning the cello."
	Inventory.add("bubble_wand")
	Inventory.add("moth_wing_cloak")
	match drive_name:
		"sheet_me", "sheet_looks", "sheet_gear":
			ItemEffects.equip(g, Items.load_item("bubble_wand"))
			ItemEffects.equip(g, Items.load_item("tea_cozy_helmet"))
			main.open_panel(WorldMenu.sheet(g, ["sheet_me", "sheet_looks", "sheet_gear"].find(drive_name)))
		"bag":
			ItemEffects.equip(g, Items.load_item("wooden_spoon"))
			var bag: Control = WorldMenu.bag(g)
			main.open_panel(bag)
			await _wait(0.2)
			bag.select("moth_wing_cloak")
		"workshop":
			var ws: Control = WorldMenu.workshop(g)
			ws.start_item = "bubble_wand"
			main.open_panel(ws)
		"gear_world":
			ItemEffects.equip(g, Items.load_item("bubble_wand"))
			ItemEffects.equip(g, Items.load_item("tea_cozy_helmet"))
			g.cam.zoom(-1)
			g.cam.zoom(-1)
		"gift_chat":
			var id: String = g.actors.keys()[0]
			g.approach_character(id)
			await _wait(3.0)
			for i in 8:
				if g.dialogue.state == "input":
					break
				g.dialogue.advance()
			await g.talk.give_gift("fresh_cookies")
			await _wait(1.6)
	await _wait(0.8)


## Phase 11 screens (run with --touch-ui and a phone-sized --resolution).
## Phase 17 screenshots: Platform Mode on Sky Steps (running / mid-jump), the
## editor's Jump reach overlay, the Animations tab. (--touch-ui for the phone layout.)
func _platform(drive_name: String) -> void:
	main.begin_new_world()
	await _wait(0.5)
	var TemplateFactory := preload("res://scripts/world/template_factory.gd")
	var Templates := preload("res://scripts/world/templates.gd")
	TemplateFactory.ensure_builtin()
	Templates.apply_to_room("sky_steps", "home", "replace")
	main.game.load_room("home")
	await _wait(0.4)
	var g: Node = main.game
	match drive_name:
		"platform", "platform_jump":
			var pillar: Dictionary = g.room.data.objects.filter(func(o): return str(o.type) == "platform_pillar")[0]
			g.player.position = g.room.cell_center(Vector2i(2, 4))
			g.platform.activate(pillar)
			await _wait(1.4)
			g.platform.body.teleport(Vector3(3.2, 0.05, 5.5))
			g.platform.run_toggle = true
			g.platform.test_input = Vector2(1, 0)
			await _wait(0.55 if drive_name == "platform" else 0.35)
			if drive_name == "platform_jump":
				g.platform.jump()
				await _wait(0.25)
			if "--cam-debug" in OS.get_cmdline_user_args():
				var cam: Camera3D = g.cam.camera
				var head: Vector3 = g.player.global_position + Vector3(0, 1, 0)
				var q := PhysicsRayQueryParameters3D.create(head, head + (cam.global_position - head).normalized() * 9.0, 8)
				var hit: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(q)
				print("[cam] dist=", cam.global_position.distance_to(head), " pitch=", g.cam.follow_pitch, " fdist=", g.cam.follow_dist, " hit=", (hit.collider.name if not hit.is_empty() else "none"), " at ", hit.get("position", Vector3.ZERO))
		"jump_reach":
			g.build.enter()
			GameState.settings["editor"] = {"advanced": true, "show_map": false}
			g.build.shell.prefs["advanced"] = true
			g.build.shell._apply_layout()
			g.build.shell.refresh()
			g.build.cursor = Vector2i(7, 5)
			g.build.set_jump_reach(true)
			g.build._place_ghost()
			await _wait(0.6)
		"anim_tab":
			var cc: Control = preload("res://scripts/ui/character_creator.gd").new()
			cc.edit_player_form("real")
			main.open_panel(cc)
			await _wait(0.4)
			var tabs := cc.find_children("*", "TabContainer", true, false)
			if not tabs.is_empty():
				var tc: TabContainer = tabs[0]
				tc.current_tab = tc.get_tab_count() - 1
				var tab: Node = tc.get_child(tc.current_tab)
				tab.select_state("run")
				tab.generate()
			await _wait(0.6)


## Phase 18 screenshots: the Today card after two days away, the Quest log,
## the Almanac, and a room behind a Dream Door.
func _variety(drive_name: String) -> void:
	var Clock := preload("res://scripts/variety/clock.gd")
	main.begin_new_world()
	await _wait(0.4)
	GameState.add_dream("learn to play the guitar")
	var VarietySave := preload("res://scripts/variety/variety_save.gd")
	VarietySave.data()["last_seen"] = Clock.now()
	GameState.save_world()
	Clock.advance(2.0)   # two days later (the Time Machine)
	main.start_game()
	await _wait(1.0)
	var g: Node = main.game
	for n in main.ui.get_children():   # "Got it" on the Where was I? card: the day's card follows
		if n.get_script() == load("res://scripts/ui/recap_card.gd"):
			n.queue_free()
	await _wait(0.4)
	match drive_name:
		"quest_log":
			if g.variety.card:
				g.variety.card.queue_free()
			main.open_panel(load("res://scripts/ui/quest_log_panel.gd").new())
		"almanac":
			if g.variety.card:
				g.variety.card.queue_free()
			var DreamDoors := preload("res://scripts/variety/dream_doors.gd")
			DreamDoors.open({"id": "d1"}, GameState.current_room_id)
			preload("res://scripts/variety/almanac.gd").wear("Door Opener")
			main.open_panel(load("res://scripts/ui/almanac_panel.gd").new())
		"dream_room":
			if g.variety.card:
				g.variety.card.queue_free()
			g.variety.open_dream_door({"id": "dd1"})
			await _wait(1.5)
	await _wait(0.6)


## Phase 18 stretch screenshots: Tea Time, the stargazing wish, a Photo Walk
## (prints where the photo went), and seasonal decorations on set dates.
func _hangout(drive_name: String) -> void:
	var Clock := preload("res://scripts/variety/clock.gd")
	if drive_name.begins_with("decor_"):
		var date := "2026-10-24" if drive_name == "decor_halloween" else "2026-12-20"
		var target := Time.get_unix_time_from_datetime_string(date + "T12:00:00") - int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		Clock.advance((target - Clock.now()) / 86400.0)
	main.begin_new_world()
	await _wait(0.6)
	var g: Node = main.game
	for n in main.ui.get_children():
		if n.get_script() == load("res://scripts/ui/recap_card.gd"):
			n.queue_free()
	await _wait(0.2)
	if g.variety.card:
		g.variety.card.queue_free()
	var id: String = g.actors.keys()[0] if not g.actors.is_empty() else ""
	match drive_name:
		"hangout_tea":
			g.variety.hangouts.start.call_deferred("tea", id)
			await _wait(4.2)
		"hangout_stars":
			g.variety.hangouts.start.call_deferred("stars", id)
			await _wait(1.6)
		"hangout_wish":
			g.variety.hangouts.start.call_deferred("stars", id)
			await _wait(5.5)
			for p in main.ui.find_children("*", "LineEdit", true, false):
				(p as LineEdit).text = "see the northern lights"
		"hangout_panel":
			main.open_panel(preload("res://scripts/world/world_menu.gd").hangout(g))
			await _wait(0.5)
		"hangout_walk":
			g.variety.hangouts.start.call_deferred("walk", id)
			await g.variety.hangouts.finished
			var rel: String = g.variety.hangouts.last_photo
			print("[drive] photo walk: ", rel, " exists=", rel != "" and FileAccess.file_exists(SaveManager.abs_path(rel)))
			main.open_panel(preload("res://scripts/ui/memory_book.gd").new())
			await _wait(0.8)
		_:
			var root: Node = g.room.get("_content").get_node_or_null("SeasonalDecor")
			print("[drive] decor: ", root.get_meta("themes", []) if root else "none", " bulbs=", root.get_meta("bulbs", 0) if root else 0)
			await _wait(0.6)
	await _wait(0.4)


func _phone(drive_name: String) -> void:
	main.begin_new_world()
	await _wait(0.6)
	var g: Node = main.game
	match drive_name:
		"phone_chat":
			var id: String = g.actors.keys()[0]
			g.approach_character(id)
			await _wait(3.0)
			for i in 8:
				if g.dialogue.state == "input":
					break
				g.dialogue.advance()
			g.dialogue.input.text = "I had a long day"
			g.dialogue._send()
			await _wait(2.5)
			for i in 8:
				if g.dialogue.state == "input":
					break
				g.dialogue.advance()
		"phone_bag":
			main.open_panel(preload("res://scripts/world/world_menu.gd").bag(g))
		"phone_link", "phone_link_tailscale", "phone_banner", "host_window":
			# Screenshots only: Same Wi-Fi on 127.0.0.1 (never the real Tailscale, never the network).
			main.configure_phone_link()
			main.phone_link.mode = "lan"
			main.phone_link.start(8790, "127.0.0.1")
			match drive_name:
				"phone_link":
					main.open_phone_link_settings()
				"phone_link_tailscale":
					main.open_phone_link_settings()
					await _wait(4.0)   # the Tailscale status check (read-only) finishes
					var tab: Node = null
					for t in main.ui.find_children("*", "", true, false):
						if t.get_script() == load("res://scripts/ui/phone_link_tab.gd"):
							tab = t
							break   # (refresh() frees most of these nodes: stop looking first)
					if tab:
						tab._ts_open = true
						tab.refresh()
						await _wait(0.4)
						var up: Node = tab
						while up and not up is ScrollContainer:
							up = up.get_parent()
						if up:
							(up as ScrollContainer).scroll_vertical = 100000   # down to the Tailscale card
				"phone_banner":
					main.show_phone_banner("📱 Phone connecting: PIN " + preload("res://scripts/phone/pairing.gd").grouped(str(main.phone_link.pairing.code)))
				"host_window":
					main._end_game()
					main._clear_screen()
					var hw: Control = preload("res://scripts/ui/host_window.gd").new()
					main.ui.add_child(hw)
					hw.setup(main.phone_link)
					main.get_window().min_size = Vector2i(420, 560)
					main.get_window().size = Vector2i(560, 760)
					main.get_window().content_scale_size = Vector2i(560, 760)
	await _wait(0.8)


func _talk(lines: Array) -> void:
	main.begin_new_world()
	await _wait(0.8)
	var g: Node = main.game
	var id: String = g.actors.keys()[0]
	g.approach_character(id)
	await _wait(3.5)
	for line in lines:
		g.dialogue.advance()
		g.dialogue.advance()
		await _wait(0.2)
		g.dialogue.input.text = line
		g.dialogue._send()
		await _wait(3.0)


func scenarios() -> RefCounted:
	var sc: RefCounted = load("res://scripts/core/debug_scenarios.gd").new()
	sc.set("drives", self)
	return sc


func _wait(seconds: float) -> void:
	await main.get_tree().create_timer(seconds).timeout


## Waits for the next screen to open (never longer than ten seconds: a drive must end by itself).
func _until_screen() -> void:
	var end := Time.get_ticks_msec() + 10000
	while main.screen == null and Time.get_ticks_msec() < end:
		await main.get_tree().process_frame


## A copy/paste round trip with a real AI's answer, on a public building only (`--paste-address=`, a museum
## or a library, never a private home): `paste_prompt` writes the exact prompt to `--paste-out=`; the next runs
## (same save root) paste `--paste-reply=` and stop at the tidy offer, the review, the rebuilt house, or the
## street after a live map lookup (`paste_street` asks the map server you chose).
func _paste_round_trip(drive_name: String) -> void:
	var arg := func(k: String) -> String:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--" + k + "="):
				return a.trim_prefix("--" + k + "=")
		return ""
	var HomeStore := load("res://scripts/home/home_store.gd")
	var Manual := load("res://scripts/home/helper_manual_panel.gd")
	if SaveManager.has_world():
		main.start_game()
	else:
		main.begin_new_world()
	await _wait(0.6)
	for card in main.ui.find_children("*", "Control", true, false):
		var script: Script = card.get_script()
		if script and script.resource_path.get_file() in ["today_card.gd", "recap_card.gd"]:
			card.queue_free()
	if not HomeStore.exists():
		load("res://scripts/home/home_mapper.gd").build_home({"address": arg.call("paste-address"), "home_type": "house", "floors": 2,
			"rooms": {"bedroom": 2, "kitchen": 1, "living": 1}, "my_room": {"floor": 1, "where": "front"}, "radius": 150}, {}, "")
	var g: Node = main.game
	var hp: Control = load("res://scripts/home/map_home_panel.gd").new()
	main.open_panel(hp)
	hp.setup_home(g)
	# paste_street again on a home whose answer is already kept (the map server was busy last time): only
	# the streets are asked for again.
	if drive_name == "paste_street" and arg.call("paste-reply") == "" and HomeStore.waiting_answer() == "" and str(HomeStore.load_home().get("researched", "")) != "":
		print("[drive] paste: the answer is already kept; mapping the streets only")
		await _map_streets_live(hp)
		await _paste_walk_outside(g, drive_name)
		return
	hp._manual_research()
	await _wait(0.4)
	var manual: Control = null
	for p in main.panels:
		if is_instance_valid(p) and (p as Node).get_script() == Manual:
			manual = p
	if manual == null:
		print("[drive] paste: the copy/paste screen didn't open")
		return
	if drive_name == "paste_prompt":
		var f := FileAccess.open(arg.call("paste-out"), FileAccess.WRITE)
		if f:   # (--paste-out=<file> is optional: a capture of the screen needs no file)
			f.store_string(manual.prompt_box.text)
			f.close()
		print("[drive] paste: prompt written (%d characters), request %s" % [manual.prompt_box.text.length(), str(manual.request.request_id).left(8)])
		await _wait(0.4)
		return
	if arg.call("paste-reply") != "":
		manual.response_box.text = FileAccess.get_file_as_string(arg.call("paste-reply"))
	else:
		# No reply given: the answer an AI saved as a file in the home's Info folder (the screen read it).
		print("[drive] paste: reply from the Info folder: %d characters (%s)" % [manual.response_box.text.length(), HomeStore.waiting_answer().get_file()])
	manual.preview_response()
	await _wait(0.3)
	# (an answer that needed no tidying goes straight to the review, and the copy/paste screen is gone)
	print("[drive] paste: status: ", manual.status.text if is_instance_valid(manual) else "accepted as it came")
	if drive_name == "paste_offer":
		await _wait(0.4)
		return
	var use: Node = manual.find_child("UseTidied", true, false) if is_instance_valid(manual) else null
	if use:
		(use as BaseButton).pressed.emit()
	await _wait(0.5)
	var review: Control = null
	for p in main.panels:
		if is_instance_valid(p) and (p as Node).get_script() == load("res://scripts/home/helper_review_panel.gd"):
			review = p
	print("[drive] paste: review open: ", review != null, "; status: ", hp._status.text)
	if drive_name == "paste_review" or review == null:
		await _wait(0.4)
		return
	review._decide("keep")
	await _wait(0.5)
	var home: Dictionary = HomeStore.load_home()
	print("[drive] paste: kept: researched=%s rooms=%d sources=%d footprint=%s location=%s" % [str(home.get("researched", "") != ""), (home.get("rooms", []) as Array).size(), (home.get("sources", []) as Array).size(), JSON.stringify(home.get("footprint", {})), str(home.get("location") is Dictionary)])
	if drive_name == "paste_street":
		await _map_streets_live(hp)
	await _paste_walk_outside(g, drive_name)


## "Map my streets" for real, from the My home screen: asks the map server you chose, and applies the map
## when it arrives (up to 90 seconds).
func _map_streets_live(hp: Control) -> void:
	var HomeStore := load("res://scripts/home/home_store.gd")
	var streets: Node = hp.find_child("MapStreetsToo", true, false)
	if streets == null:
		streets = hp.find_child("MapStreets", true, false)
	if streets == null:
		for b in hp.find_children("*", "Button", true, false):
			if (b as Button).text in ["Map my streets", "Map my streets again"]:
				streets = b
	if streets == null:
		print("[drive] paste: no button to map the streets")
		return
	(streets as BaseButton).pressed.emit()
	await _wait(0.3)
	for b in main.panels[-1].find_children("*", "Button", true, false):
		if (b as Button).text == "Map my streets":
			(b as Button).pressed.emit()
	var t := Time.get_ticks_msec()
	var applied := false
	while Time.get_ticks_msec() - t < 90000:
		for b in main.toast_layer().find_children("*", "Button", true, false):
			if (b as Button).text == "Apply this map" and (b as Button).is_visible_in_tree():
				(b as Button).pressed.emit()
				applied = true
		if applied and FileAccess.file_exists(HomeStore.path("osm.json")):
			break
		await _wait(0.3)
	print("[drive] paste: streets: ", hp._status.text, " osm=", FileAccess.file_exists(HomeStore.path("osm.json")))


## The end of a paste drive: into the Light World (out on the street for paste_street) at two in the afternoon.
func _paste_walk_outside(g: Node, drive_name: String) -> void:
	main._close_all_panels()
	await _wait(0.3)
	GameState.settings["reduce_motion"] = true
	await g.dark.go_light()
	if drive_name == "paste_street":
		var gid: String = load("res://scripts/home/home_places.gd").place_id(0)
		for o in SaveManager.load_room(gid).objects:
			if bool(o.get("street_gate", false)):
				g.load_room(str(o.door_target), gid)
	g.daylight.hour_override = 14.0
	g.daylight.apply()
	await _wait(0.8)
	await _light_view_options(g)


## What a picture of a saved Light World shows (dev only; `light_room` on a save that already has a home, and
## the end of the paste drives): `--place=street` (out of the front door) or a place's id, `--hour=<0-24>`,
## `--cam-far`, `--cam-turn=<45-degree steps>`, `--home-tab=<tab>` (the My home screen on that tab).
## Nothing covers the view: the Today and recap cards are put away first.
func _light_view_options(g: Node) -> void:
	var args := OS.get_cmdline_user_args()
	for card in main.ui.find_children("*", "Control", true, false):
		var card_script: Script = card.get_script()
		if card_script and card_script.resource_path.get_file() in ["today_card.gd", "recap_card.gd"]:
			card.queue_free()
	for a in args:
		if a.begins_with("--place="):
			var want := a.trim_prefix("--place=")
			if want == "street":
				var ground: String = load("res://scripts/home/home_places.gd").place_id(0)
				for o in SaveManager.load_room(ground).objects:
					if bool(o.get("street_gate", false)):
						g.load_room(str(o.door_target), ground)
			elif SaveManager.room_exists(want):
				g.load_room(want)
			await _wait(0.8)
		elif a.begins_with("--hour="):
			g.daylight.hour_override = float(a.trim_prefix("--hour="))
			g.daylight.apply()
	for a in args:
		if a == "--cam-far":
			g.cam.distance = g.cam.ZOOM_MAX
		elif a.begins_with("--cam-turn="):
			g.cam.rotate_step(int(a.trim_prefix("--cam-turn=")))
	g.cam.snap_to_target()
	for a in args:
		if a.begins_with("--home-tab="):
			var home_panel: Control = load("res://scripts/home/map_home_panel.gd").new()
			main.open_panel(home_panel)
			home_panel.setup_home(g)
			home_panel.show_tab(a.trim_prefix("--home-tab="))
	await _wait(0.6)


## Dev only (--drive=notes_check, Windows, a disposable --save-root): the "missing you" notes for real.
## Registers three notes a year ahead (so none can fire), lists them, takes them back and checks they
## are gone; then shows one test note now through the same toast script.
func _notes_check() -> void:
	var MissYou := preload("res://scripts/variety/miss_you.gd")
	if not Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--save-root=")):
		print("[drive] notes_check needs a disposable --save-root")
		return
	var far := Time.get_unix_time_from_system() + 365.0 * 86400.0
	var notes: Array = []
	for i in MissYou.IDS.size():
		notes.append({"id": MissYou.IDS[i], "at_unix": far + i * 86400.0, "title": "Polox", "text": "Notes check %d (a year ahead)" % i})
	MissYou._windows_schedule(notes)
	await _wait(8.0)
	var out: Array = []
	OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "Get-ScheduledTask -TaskPath '\\Polox\\' -ErrorAction SilentlyContinue | ForEach-Object { $_.TaskName + ' | ' + $_.State + ' | ' + $_.Triggers[0].StartBoundary + ' | ' + $_.Actions[0].Execute }"], out, true)
	print("[drive] registered: ", str(out).replace("\r\n", " / "))
	MissYou.cancel_all()
	await _wait(8.0)
	out.clear()
	OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "(Get-ScheduledTask -TaskPath '\\Polox\\' -ErrorAction SilentlyContinue | Measure-Object).Count"], out, true)
	print("[drive] left after taking them back: ", str(out).strip_edges())
	var script: String = MissYou._write_toast_script()
	MissYou._write_notes([{"id": 4100, "title": "Polox", "text": "A test note from Polox's notes check."}])
	out.clear()
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-Id", "4100"], out, true)
	print("[drive] toast script exit %d %s" % [code, str(out).strip_edges().left(300)])
