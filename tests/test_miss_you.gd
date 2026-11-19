extends "res://tests/test_case.gd"
## 1.27 "missing you" notes: when, what they say (a friend's name and a kind line, nothing private),
## Windows' Task Scheduler commands (dry run: tests never touch the PC's scheduler), taking them back,
## switching them off, and the one-time question after a chat.

const MissYou := preload("res://scripts/variety/miss_you.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")


func _world() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	StarterContent.create_world("Notes World", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	MissYou.dry_run = true
	MissYou.last_commands.clear()


func _end() -> void:
	MissYou.dry_run = false
	MissYou.force_ask = false
	MissYou.last_commands.clear()
	GameState.settings.erase("notifications")


func test_notes_come_a_day_three_days_and_a_week_later_never_at_night() -> void:
	var now := 1_800_000_000.0   # any moment
	for hour in [0, 3, 8, 12, 18, 23]:
		var notes := MissYou.plan(now, hour, "Mochi")
		eq(notes.size(), 3)
		var last := now
		for i in notes.size():
			var n: Dictionary = notes[i]
			eq(int(n.id), MissYou.IDS[i])
			check(float(n.at_unix) - now >= 20.0 * 3600.0, "never sooner than 20 hours")
			check(float(n.at_unix) > last, "in order")
			last = float(n.at_unix)
			var local := Time.get_datetime_dict_from_unix_time(int(float(n.at_unix) + MissYou._tz_seconds()))
			check(int(local.hour) >= MissYou.EARLIEST_HOUR and int(local.hour) <= MissYou.LATEST_HOUR, "at a waking hour (left at %d -> %d)" % [hour, int(local.hour)])
			check(str(n.text).contains("Mochi"), "the friend's name: " + str(n.text))
	check((float(MissYou.plan(now, 18, "Mochi")[2].at_unix) - now) / 86400.0 > 6.0, "the last one about a week later")
	check(MissYou.plan(now, 18, "").is_empty(), "no friend, no notes")


func test_leaving_sets_the_notes_and_coming_back_takes_them_back() -> void:
	_world()
	MissYou.on_leave()
	eq(MissYou.last_schedule.size(), 3, "three notes")
	if OS.get_name() == "Windows":
		var cmd := " ".join(MissYou.last_commands)
		check(cmd.contains("Register-ScheduledTask") and cmd.contains("\\Polox\\"), "per-user tasks in their own folder")
		check(cmd.contains("conhost.exe") and cmd.contains("--headless"), "run hidden: no window flashes up")
		check(cmd.contains("-DeleteExpiredTaskAfter") and cmd.contains("EndBoundary"), "they delete themselves after firing")
		check(FileAccess.file_exists(SaveManager.global_path("notes/polox_note.ps1")), "the toast script is there")
		var notes_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.global_path("notes/notes.json")))
		check(notes_json is Array and (notes_json as Array).size() == 3, "the notes' words are read from a file, not passed on a command line")
		check(FileAccess.file_exists(SaveManager.global_path("notes/scheduled.json")), "a marker says notes are set")
		MissYou.last_commands.clear()
		MissYou.cancel_all()
		check(" ".join(MissYou.last_commands).contains("Unregister-ScheduledTask"), "coming back takes them back")
		check(not FileAccess.file_exists(SaveManager.global_path("notes/scheduled.json")), "and the marker goes")
		MissYou.last_commands.clear()
		MissYou.cancel_all()
		eq(MissYou.last_commands.size(), 0, "nothing set: starting runs nothing")
	_end()


func test_switched_off_means_no_notes() -> void:
	_world()
	GameState.settings["notifications"] = {"miss_you": false, "asked": true}
	check(not MissYou.enabled())
	MissYou.on_leave()
	eq(MissYou.last_schedule, [], "no notes when switched off")
	for c in MissYou.last_commands:
		check(not str(c).contains("Register-ScheduledTask"), "and nothing registered")
	_end()


func test_notes_say_nothing_private() -> void:
	_world()
	var id := str(GameState.characters.keys()[0])
	var c := GameState.get_character(id)
	c["memory_notes"] = ["Lives at 12 Example Lane"]
	GameState.save_character(c)
	ChatLog.append(id, "home", "user", "my secret is pancakes")
	MissYou.on_leave()
	for n in MissYou.last_schedule:
		check(not str(n.text).contains("Example Lane") and not str(n.text).contains("pancakes"), "only a name and a kind line: " + str(n.text))
	_end()


func test_a_friend_asks_once_after_a_chat() -> void:
	_world()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.start_game()
	await frames(3)
	main._close_all_panels()   # (the start-up cards)
	await frames(2)
	MissYou.force_ask = true
	var id := str(GameState.characters.keys()[0])
	MissYou.maybe_ask(main, id)
	eq(main.panels.size(), 0, "no question before a real chat")
	ChatLog.append(id, "home", "user", "hi")
	ChatLog.append(id, "home", "ai", "hello!")
	MissYou.maybe_ask(main, id)
	if MissYou.supported():
		check(main.panels.any(func(p): return str(p.name) == "MissYouAsk"), "after a chat, the friend asks")
		var ask: Node = main.panels.filter(func(p): return str(p.name) == "MissYouAsk")[0]
		ask.answered.emit(false)
		await frames(2)
		check(not MissYou.enabled(), "Not now switches notes off")
		var before: int = main.panels.size()
		MissYou.maybe_ask(main, id)
		eq(main.panels.size(), before, "asked once only")
	main.queue_free()
	await frames(2)
	_end()
