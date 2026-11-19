extends Node
## The flight recorder: if Polox ever closes by itself (on a phone, Android just takes the app away),
## the next start knows, and what happened last is kept. It writes a small session file (the app's
## own folder, logs/polox_session.json): when it started, a heartbeat every 20 s, where you were (the
## screen, the place, what was open), memory, and the last errors (a Godot Logger catches them). A
## clean exit or the app going to the background marks it; a session that just stopped while in front
## of you was a crash, and is kept as logs/crash_<time>.json (the last 5). The phone app sends crash
## reports to your PC (Phone Link's report box, PersonalData\phone_reports) the next time it connects;
## nothing else ever leaves, and the file holds no chat, no keys and no home details.
## Tags: [PERSONAL_DATA]

const Graphics := preload("res://scripts/core/graphics.gd")
const MemoryGuard := preload("res://scripts/core/memory_guard.gd")

const VERSION := 1
const BEAT_S := 20.0
const KEEP_ERRORS := 40
const KEEP_CRASHES := 5

## Crashes from earlier sessions not yet sent to the PC: [{...session...}].
var pending: Array = []
## The session before this one, if it ended unexpectedly ({} if it didn't).
var previous_crash: Dictionary = {}
var session: Dictionary = {}
var main: Node
var _log: Recorder
var _beat_in := BEAT_S
var _dirty_in := -1.0
var dir := ""


class Recorder extends Logger:
	var mutex := Mutex.new()
	var lines: Array = []
	var count := 0
	var fresh := false
	## Anything shaped like an API key is taken out of an error line before it is kept (its own
	## pattern: errors arrive on any thread).
	var key_shapes: RegEx = preload("res://scripts/ai/key_format.gd").shapes()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var where := "%s:%d %s()" % [file.get_file(), line, function]
		var top := ""
		for b in script_backtraces:
			if b.get_frame_count() > 0:
				top = " <- %s:%d %s()" % [b.get_frame_file(0).get_file(), b.get_frame_line(0), b.get_frame_function(0)]
				break
		var text := "%s %s%s" % [where, (rationale if rationale != "" else code).left(160), top]
		mutex.lock()
		text = key_shapes.sub(text, "[redacted]", true)
		count += 1
		lines.append(Time.get_time_string_from_system() + " " + text.left(280))
		if lines.size() > KEEP_ERRORS:
			lines.pop_front()
		fresh = true
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array:
		mutex.lock()
		var out := lines.duplicate()
		fresh = false
		mutex.unlock()
		return out


func _init(log_dir: String = "") -> void:
	dir = log_dir if log_dir != "" else OS.get_user_data_dir().path_join("logs")


func setup(main_node: Node) -> void:
	main = main_node
	DirAccess.make_dir_recursive_absolute(dir)
	var android := preload("res://scripts/core/android_native.gd")
	android.install_crash_recorder()
	store_native_exits(android.recent_crash_exits())
	store_java_crashes()
	_read_previous()
	_log = Recorder.new()
	OS.add_logger(_log)
	session = {"v": VERSION, "app": "Polox", "version": str(ProjectSettings.get_setting("application/config/version", "")),
		"platform": OS.get_name(), "device": OS.get_model_name(), "started": Time.get_datetime_string_from_system(),
		"beat": "", "clean": false, "background": false, "errors": [], "error_count": 0, "where": {}, "memory_mb": 0.0}
	_write()


func _exit_tree() -> void:
	if _log:
		OS.remove_logger(_log)
		_log = null


func _session_path() -> String:
	return dir.path_join("polox_session.json")

## Keep each OS-recorded termination once, even if Android backgrounded the app
## before killing it or the script recorder could not write its final heartbeat.
func store_native_exits(exits: Array) -> void:
	for info in exits:
		if not info is Dictionary or int(info.get("timestamp_ms", 0)) <= 0:
			continue
		var path := dir.path_join("crash_native_%d.json" % int(info.timestamp_ms))
		if FileAccess.file_exists(path):
			var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			# A newly available native stack supplements the previously sent reason.
			var old_exit: Dictionary = old.get("native_exit", {}) if old is Dictionary and old.get("native_exit") is Dictionary else {}
			var has_stack := func(d: Dictionary) -> bool: return str(d.get("trace_text", "")).contains("#00 ") or d.has("trace_base64")
			if not has_stack.call(info) or has_stack.call(old_exit):
				continue
		var report := {"v": VERSION, "app": "Polox", "platform": "Android", "device": OS.get_model_name(),
			"version": exit_version(info, str(ProjectSettings.get_setting("application/config/version", ""))),
			"beat": local_time(int(info.timestamp_ms)),
			"phase": "android_exit_history", "native_exit": info, "where": {},
			"memory_mb": float(info.get("pss_kb", 0)) / 1024.0,
			"errors": ["Android exit reason=%s status=%s: %s" % [info.get("reason", "?"), info.get("status", "?"), info.get("description", "")]]}
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(report))
			f.close()


## The build that was running when Android recorded an exit. Android keeps its exit history across
## updates, so a new version's first start also sees the old version's crashes: the version the
## process tagged itself with (PoloxAndroid.tagExitRecord) says which, and for an untagged exit, one
## from before this install was an older build.
static func exit_version(info: Dictionary, current: String) -> String:
	var tagged := str(info.get("version", ""))
	if tagged != "":
		return tagged
	if int(info.get("installed_ms", 0)) > int(info.get("timestamp_ms", 0)):
		return "older than " + current
	return current


## Android's times are UTC milliseconds; the session's own are local, and so are these.
static func local_time(ms: int) -> String:
	return Time.get_datetime_string_from_unix_time(ms / 1000 + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)


## Java stacks the Android helper saved (java_crash_<ms>.txt) become crash reports like the others.
func store_java_crashes() -> void:
	for n in DirAccess.get_files_at(dir):
		if not (n.begins_with("java_crash_") and n.ends_with(".txt")):
			continue
		var ms := n.trim_prefix("java_crash_").trim_suffix(".txt").to_int()
		var stack := FileAccess.get_file_as_string(dir.path_join(n)).left(12000)
		var lines := stack.split("\n", false)
		var report := {"v": VERSION, "app": "Polox", "platform": OS.get_name(), "device": OS.get_model_name(),
			"version": str(ProjectSettings.get_setting("application/config/version", "")),
			"beat": local_time(ms), "phase": "android_java_crash", "where": {},
			"native_exit": {"timestamp_ms": ms, "description": "uncaught Java exception", "java_stack": stack},
			"errors": Array(lines.slice(0, 6))}
		var f := FileAccess.open(dir.path_join("crash_java_%d.json" % ms), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(report))
			f.close()
			DirAccess.remove_absolute(dir.path_join(n))


func _read_previous() -> void:
	var prev: Variant = JSON.parse_string(FileAccess.get_file_as_string(_session_path())) if FileAccess.file_exists(_session_path()) else null
	if prev is Dictionary and not bool(prev.get("clean", true)) and not bool(prev.get("background", false)) and str(prev.get("beat", "")) != "":
		previous_crash = prev
		var stamp := str(prev.get("beat", "")).replace(":", "").replace("T", "_")
		var f := FileAccess.open(dir.path_join("crash_%s.json" % stamp), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(prev, "\t"))
			f.close()
	var crashes := Array(DirAccess.get_files_at(dir)).filter(func(n): return str(n).begins_with("crash_") and str(n).ends_with(".json"))
	crashes.sort()
	while crashes.size() > KEEP_CRASHES:
		DirAccess.remove_absolute(dir.path_join(str(crashes.pop_front())))
	for n in crashes:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(str(n))))
		if d is Dictionary and not bool(d.get("sent", false)):
			d["file"] = str(n)
			pending.append(d)


func _process(delta: float) -> void:
	_beat_in -= delta
	if _log and _log.fresh and _dirty_in < 0.0:
		_dirty_in = 2.0   # errors come in bursts: one write for the burst
	if _dirty_in >= 0.0:
		_dirty_in -= delta
		if _dirty_in < 0.0:
			beat()
	if _beat_in <= 0.0:
		beat()


## Notes where you are and writes the session file.
func beat() -> void:
	_beat_in = BEAT_S
	session["beat"] = Time.get_datetime_string_from_system()
	session["memory_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	# What the whole app holds (resident memory, where the OS says: Android, Linux), the graphics memory
	# the engine counts, and what memory_guard.gd has had to do. A native crash leaves only the last of these.
	var rss := MemoryGuard.read_mb()
	if rss > 0.0:
		session["rss_mb"] = snappedf(rss, 0.1)
		session["rss_peak_mb"] = maxf(float(session.get("rss_peak_mb", 0.0)), float(session["rss_mb"]))
	session["video_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	session["pressure"] = Graphics.pressure
	session["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	session["where"] = _where()
	if _log:
		session["errors"] = _log.take()
		session["error_count"] = _log.count
	_write()


## Persist before expensive scene/graphics work: a native crash cannot log a script error.
func checkpoint(phase: String) -> void:
	session["phase"] = phase
	beat()


func _where() -> Dictionary:
	var w := {}
	if main == null:
		return w
	w["screen"] = "game" if main.get("game") != null else "title"
	w["room"] = "light world" if GameState.current_room_id.begins_with("lw_") else GameState.current_room_id
	var open: Array = []
	for p in main.get("panels") if main.get("panels") is Array else []:
		if is_instance_valid(p):
			var s: Script = p.get_script()
			open.append(s.resource_path.get_file().get_basename() if s else p.get_class())
	w["panels"] = open
	var g: Node = main.get("game")
	if g:
		w["battle"] = g.get("battles") != null and g.battles.get("screen") != null
		w["talking"] = g.get("dialogue") != null and g.dialogue.visible
		w["moving_between"] = bool(g.get("_transitioning"))
	return w


func _write() -> void:
	var f := FileAccess.open(_session_path() + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(session))
	f.close()
	DirAccess.rename_absolute(_session_path() + ".tmp", _session_path())


## The app went to the background (Android may end it there: that's not a crash) or came back.
func on_background(away: bool) -> void:
	session["background"] = away
	beat()


## Leaving on purpose (the window closed, Quit).
func on_clean_exit() -> void:
	session["clean"] = true
	beat()


## A crash report as Phone Link's report box takes it (known keys only, short lines).
static func as_report(crash: Dictionary) -> Dictionary:
	var where: Dictionary = crash.get("where", {}) if crash.get("where") is Dictionary else {}
	var lines: Array = (crash.get("errors", []) as Array).slice(-30).map(func(l): return preload("res://scripts/ai/key_format.gd").scrub(str(l)))
	return {"v": 1, "app": "Polox", "page": "crash report", "when": str(crash.get("beat", "")),
		"stage": "closed unexpectedly in %s (%s)" % [str(where.get("room", "?")), ", ".join(PackedStringArray(where.get("panels", [])))],
		"env": {"version": str(crash.get("version", "")), "platform": str(crash.get("platform", "")), "device": str(crash.get("device", "")),
			"started": str(crash.get("started", "")), "memory_mb": float(crash.get("memory_mb", 0.0)), "nodes": int(crash.get("nodes", 0)),
			"rss_mb": float(crash.get("rss_mb", 0.0)), "rss_peak_mb": float(crash.get("rss_peak_mb", 0.0)),
			"video_mb": float(crash.get("video_mb", 0.0)), "pressure": int(crash.get("pressure", 0)),
			"errors": int(crash.get("error_count", 0)), "battle": bool(where.get("battle", false)), "talking": bool(where.get("talking", false)),
			"phase": str(crash.get("phase", "")),
			"native_exit": crash.get("native_exit", {}),
			"moving_between": bool(where.get("moving_between", false))},
		"log": lines}


## After a crash report reached the PC: marked sent, so it goes once.
func mark_sent(crash: Dictionary) -> void:
	var n := str(crash.get("file", ""))
	if n == "":
		return
	crash["sent"] = true
	var copy := crash.duplicate()
	copy.erase("file")
	var f := FileAccess.open(dir.path_join(n), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(copy, "\t"))
		f.close()
	pending.erase(crash)
