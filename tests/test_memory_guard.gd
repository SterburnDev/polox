extends "res://tests/test_case.gd"
## memory_guard.gd (the app's own memory, watched while it runs), the graphics pressure it applies, the
## flight recorder's memory numbers, and the two small phone fixes that shipped with it (a forgotten
## finger, the title screen's redraw rate).

const Guard := preload("res://scripts/core/memory_guard.gd")
const Graphics := preload("res://scripts/core/graphics.gd")
const MemoryRelief := preload("res://scripts/core/memory_relief.gd")
const CrashLog := preload("res://scripts/core/crash_log.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")
const AndroidNative := preload("res://scripts/core/android_native.gd")


## A memory reading the test controls (0.0 = "nothing to read here").
class Reading extends RefCounted:
	var mb := 0.0

	func read() -> float:
		return mb


func _guard(reading: Reading) -> Node:
	var g: Node = Guard.new()
	g.reader = Callable(reading, "read")
	g.set_process(false)   # the test decides when it looks
	tree.root.add_child(g)
	return g


func test_the_vmrss_line_is_read_in_any_unit_and_junk_is_zero() -> void:
	eq(Guard.parse_vmrss("VmRSS:\t  412345 kB"), 412345.0 / 1024.0, "the usual line")
	eq(Guard.parse_vmrss("VmRSS:   2048 kB"), 2.0)
	eq(Guard.parse_vmrss("VmRSS: 7 mB"), 7.0, "a megabyte unit")
	eq(Guard.parse_vmrss("VmRSS: 524288 B"), 0.5, "a byte unit")
	for junk in ["", "VmRSS:", "VmRSS: abc kB", "VmSize: 100 kB", "VmRSS: -5 kB", "RSS 100"]:
		eq(Guard.parse_vmrss(junk), 0.0, "junk '%s' is nothing" % junk)
	check(Guard.read_mb() >= 0.0, "reading the real file never fails (0.0 where /proc is missing)")


func test_the_android_plugin_call_is_a_safe_zero_off_a_phone() -> void:
	# On a phone the plugin reads /proc/self/status (Godot's own file access refuses it there); off one
	# there is no plugin, and the answer is a plain 0, never an error.
	eq(AndroidNative.resident_kb(), 0, "no plugin, no reading")
	if not OS.has_feature("android"):
		check(Guard.read_mb() >= 0.0)


func test_levels_follow_size_and_a_leaks_pace() -> void:
	eq(Guard.level_for(350.0, 0.0), 0, "a normal scene")
	eq(Guard.level_for(1250.0, 0.0), 1)
	eq(Guard.level_for(1850.0, 0.0), 2)
	eq(Guard.level_for(2550.0, 0.0), 3)
	eq(Guard.level_for(800.0, 400.0), 1, "a leak's pace once the app is big")
	eq(Guard.level_for(500.0, 400.0), 0, "loading a world is not a leak")
	eq(Guard.level_for(800.0, 100.0), 0, "slow growth is fine")


func test_the_guard_only_goes_up_and_applies_the_lighter_graphics() -> void:
	Graphics.pressure = 0
	var reading := Reading.new()
	var g := _guard(reading)
	var limits := [0]
	g.on_limit = func(): limits[0] += 1
	var applied: Array = []
	g.on_level = func(level: int, _mb: float): applied.append(level)
	var seen: Array = []
	g.level_changed.connect(func(level: int, _mb: float): seen.append(level))
	var released := MemoryRelief.releases
	eq(g.observe(350.0, 0.0), 0)
	eq(Graphics.pressure, 0)
	eq(Graphics.msaa({"graphics": "balanced"}, false), Viewport.MSAA_2X, "as chosen while all is well")
	eq(g.observe(1300.0, 5.0), 1)
	eq(Graphics.pressure, 1)
	eq(Graphics.msaa({"graphics": "balanced"}, false), Viewport.MSAA_DISABLED, "no anti-aliasing under pressure")
	eq(Graphics.msaa({"graphics": "high"}, true), Viewport.MSAA_DISABLED, "not even when High was chosen")
	eq(Graphics.frame_cap({"frame_rate": "120"}, true), 120, "the frame rate waits for the next step")
	eq(MemoryRelief.releases, released + 1, "the caches were let go")
	eq(g.observe(1900.0, 10.0), 2)
	eq(Graphics.pressure, 2)
	eq(Graphics.frame_cap({"frame_rate": "120"}, true), 30)
	eq(Graphics.frame_cap({"frame_rate": "auto"}, false), 30, "even where there was no cap")
	eq(Graphics.frame_cap({"frame_rate": "30"}, true), 30)
	check(not Graphics.shadows({"graphics": "high"}), "no sun shadows")
	eq(limits[0], 0, "the world is not flushed before the limit")
	eq(g.observe(2600.0, 15.0), 3)
	eq(limits[0], 1, "at the limit it is written to disk")
	eq(Graphics.pressure, 2, "pressure stops at 2")
	eq(g.observe(300.0, 40.0), 3, "memory coming back down does not undo it")
	eq(g.observe(2700.0, 45.0), 3)
	eq(limits[0], 1, "and it is flushed once")
	eq(seen, [1, 2, 3], "one signal per step")
	eq(applied, [1, 2, 3], "the main script is told at each step")
	check(g.peak_mb >= 2700.0, "the peak is kept")
	Graphics.pressure = 0
	g.queue_free()


func test_a_leaks_pace_counts_even_below_the_size_limits() -> void:
	Graphics.pressure = 0
	var reading := Reading.new()
	var g := _guard(reading)
	eq(g.observe(750.0, 0.0), 0)
	eq(g.observe(900.0, 8.0), 0, "150 MB in 8 s is not yet a leak")
	eq(g.observe(1110.0, 16.0), 1, "360 MB in 16 s is")
	Graphics.pressure = 0
	g.queue_free()


func test_old_readings_leave_the_window() -> void:
	Graphics.pressure = 0
	var reading := Reading.new()
	var g := _guard(reading)
	eq(g.observe(750.0, 0.0), 0)
	eq(g.observe(1000.0, 60.0), 0, "250 MB in a minute is a slow climb, not a leak")
	eq(g.observe(1050.0, 61.0), 0, "the old reading no longer counts")
	Graphics.pressure = 0
	g.queue_free()


func test_the_guard_stays_quiet_where_nothing_can_be_read() -> void:
	Graphics.pressure = 0
	var reading := Reading.new()   # 0.0: no reading
	var g := _guard(reading)
	eq(g.sample(), 0)
	eq(g.sample(5.0), 0)
	eq(Graphics.pressure, 0)
	reading.mb = 3000.0
	eq(g.sample(10.0), 3, "a real reading is acted on")
	Graphics.pressure = 0
	g.queue_free()


func test_pressure_two_turns_off_glow_the_colour_pass_and_the_suns_shadow() -> void:
	Graphics.pressure = 0
	var env := Environment.new()
	Graphics.apply_env(env, {"graphics": "high"})
	check(env.glow_enabled and env.adjustment_enabled, "High has both when all is well")
	Graphics.pressure = 2
	Graphics.apply_env(env, {"graphics": "high"})
	check(not env.glow_enabled and not env.adjustment_enabled, "neither under pressure")
	var sun := DirectionalLight3D.new()
	Graphics.apply_to_world(sun, {"graphics": "high"})
	check(not sun.shadow_enabled, "no shadow pass under pressure")
	Graphics.pressure = 0
	Graphics.apply_to_world(sun, {"graphics": "high"})
	check(sun.shadow_enabled, "and the shadow is back once the pressure is lifted (a new session)")
	sun.free()


func test_the_heartbeat_and_the_report_carry_the_memory_numbers() -> void:
	var dir := ProjectSettings.globalize_path("res://tests/.tmp_save").path_join("memory_guard_log")
	preload("res://scripts/core/json_util.gd").remove_tree(dir)
	Graphics.pressure = 1
	var recorder: Node = CrashLog.new(dir)
	tree.root.add_child(recorder)
	recorder.setup(null)
	recorder.beat()
	var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("polox_session.json")))
	check(s is Dictionary and s.has("video_mb"), "the graphics memory is in the heartbeat")
	eq(int(s.get("pressure", -1)), 1, "and what the guard has done")
	var report := CrashLog.as_report({"rss_mb": 1234.5, "rss_peak_mb": 2000.0, "video_mb": 80.5, "pressure": 2, "version": "1.27.14", "where": {}, "errors": []})
	eq(float(report.env.rss_mb), 1234.5)
	eq(float(report.env.rss_peak_mb), 2000.0)
	eq(float(report.env.video_mb), 80.5)
	eq(int(report.env.pressure), 2)
	var sink := ReportSink.new(dir.path_join("pc"))
	var result: Array = sink.accept("192.168.1.30", JSON.stringify(report).to_utf8_buffer(), "http", "Phone Link")
	eq(int(result[0]), 200, "the PC's report box takes it")
	var saved := Array(DirAccess.get_files_at(dir.path_join("pc").path_join("phone_reports")))
	eq(saved.size(), 1)
	var kept: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("pc/phone_reports").path_join(str(saved[0]))))
	check(kept is Dictionary and float(kept.env.get("rss_mb", 0.0)) == 1234.5, "and keeps the memory numbers")
	Graphics.pressure = 0
	recorder.on_clean_exit()
	recorder._exit_tree()
	recorder.free()


func test_touches_are_forgotten_when_the_app_is_paused() -> void:
	var gestures: Node = preload("res://scripts/ui/touch_gestures.gd").new()
	tree.root.add_child(gestures)
	var first := InputEventScreenTouch.new()
	first.index = 0
	first.pressed = true
	first.position = Vector2(100, 100)
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.pressed = true
	second.position = Vector2(300, 100)
	gestures._input(first)
	gestures._input(second)
	eq(gestures.finger_count(), 2)
	gestures.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	eq(gestures.finger_count(), 0, "a finger-up that never came is forgotten")
	gestures._input(first)
	eq(gestures.finger_count(), 1, "the next touch counts normally")
	gestures.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	eq(gestures.finger_count(), 0, "so does losing the focus")
	gestures.queue_free()


func test_the_title_screens_stars_redraw_thirty_times_a_second() -> void:
	var stars: Control = preload("res://scripts/ui/starfield.gd").new()
	tree.root.add_child(stars)
	stars._process(0.01)
	check(stars._since_draw > 0.0, "a short frame only adds up")
	stars._process(0.03)
	eq(stars._since_draw, 0.0, "enough time has passed: drawn, counting again")
	check(stars._t > 0.039, "the stars' own clock keeps the real time")
	stars.queue_free()


func test_phones_and_the_browser_start_without_anti_aliasing() -> void:
	eq(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d.mobile", -1)), 0, "phones: off before any setting is read")
	eq(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d.web", -1)), 0, "the browser too")
