extends Node
## Watches the app's own resident memory and answers a runaway while there is still room to answer it.
##
## 1.27.12 on an Adreno phone grew to about 3.5 GB within two or three minutes of starting (a driver
## allocating around multisampled buffers, fixed in the engine since 1.27.13) and was ended by the
## allocator or by Android's low-memory killer. A Polox scene needs a few hundred MB, so a number like
## that is never the game itself. Whatever allocates, the answer is the same and costs the player nothing
## they would notice: let go of the caches, then stop asking the GPU for the expensive extras.
##
##   level 1  more than WARN_MB, or a leak's pace (GROWTH_MB within WINDOW_S while already big):
##            caches released, no anti-aliasing (Graphics.pressure 1)
##   level 2  more than STRAIN_MB: also at most 30 fps, no sun shadows, no glow or colour pass (pressure 2)
##   level 3  more than LIMIT_MB: the world is written to disk now, in case Android ends the app next
##
## The level only goes up in a session. Memory is VmRSS from /proc/self/status (kB whatever the page size),
## read by the Android plugin on a phone (android_native.gd) or directly on Linux; anywhere else there is no
## reading and the guard stays quiet.
## Each step is printed ("[memory_guard]") and lands in the flight recorder's heartbeat (crash_log.gd),
## so the next report says how big the app was and what it did.

const Graphics := preload("res://scripts/core/graphics.gd")
const MemoryRelief := preload("res://scripts/core/memory_relief.gd")
const AndroidNative := preload("res://scripts/core/android_native.gd")

const CHECK_S := 2.0
const WARN_MB := 1200.0
const STRAIN_MB := 1800.0
const LIMIT_MB := 2500.0
const GROWTH_MB := 350.0         # climbing this much within WINDOW_S counts as a leak...
const GROWTH_FLOOR_MB := 700.0   # ...but only once the app is this big (loading a world is not a leak)
const WINDOW_S := 20.0
const STATUS_FILE := "/proc/self/status"

signal level_changed(new_level: int, mb: float)

var level := 0
var peak_mb := 0.0
var last_mb := 0.0
## Tests give a fake reading (megabytes); null Callable = read /proc/self/status.
var reader: Callable = Callable()
## main.gd: re-applies the graphics settings (and flushes at the last level). Called with (level, mb).
var on_level: Callable = Callable()
## Called once at the last level to write the world to disk (main.gd: flush_all).
var on_limit: Callable = Callable()
var warn_mb := WARN_MB
var strain_mb := STRAIN_MB
var limit_mb := LIMIT_MB
var _samples: Array = []   # [seconds, megabytes]
var _clock := 0.0
var _acc := 0.0


## main.gd starts the guard on Android, and anywhere with --memory-guard (or --memory-guard-warn=<MB>).
static func wanted() -> bool:
	if OS.has_feature("android"):
		return true
	for a in OS.get_cmdline_user_args():
		if a == "--memory-guard" or a.begins_with("--memory-guard-warn="):
			return true
	return false


func _ready() -> void:
	# Debug builds and the phone test drive can lower the thresholds to watch the guard act on real memory.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--memory-guard-warn="):
			warn_mb = maxf(50.0, a.trim_prefix("--memory-guard-warn=").to_float())
			strain_mb = maxf(strain_mb, warn_mb * 1.5)
			limit_mb = maxf(limit_mb, strain_mb * 1.4)


func _process(delta: float) -> void:
	_clock += delta
	_acc += delta
	if _acc < CHECK_S:
		return
	_acc = 0.0
	sample()


## One reading: updates the level if memory warrants it. Returns the level after it.
func sample(now: float = -1.0) -> int:
	var mb := _read_mb()
	if mb <= 0.0:
		return level   # nothing to read here (a PC, the browser): stay quiet
	return observe(mb, _clock if now < 0.0 else now)


## The decision, separate from the reading so tests can feed it numbers.
func observe(mb: float, now_s: float) -> int:
	last_mb = mb
	peak_mb = maxf(peak_mb, mb)
	_samples.append([now_s, mb])
	while _samples.size() > 1 and now_s - float(_samples[0][0]) > WINDOW_S:
		_samples.pop_front()
	var growth := mb - float(_samples[0][1])
	var wanted := level_for(mb, growth, warn_mb, strain_mb, limit_mb)
	if wanted > level:
		_raise(wanted, mb)
	return level


## 0 normal, 1 relieved, 2 strained, 3 at the limit.
static func level_for(mb: float, growth_mb: float, warn: float = WARN_MB, strain: float = STRAIN_MB, limit: float = LIMIT_MB) -> int:
	if mb >= limit:
		return 3
	if mb >= strain:
		return 2
	if mb >= warn or (growth_mb >= GROWTH_MB and mb >= GROWTH_FLOOR_MB):
		return 1
	return 0


func _raise(new_level: int, mb: float) -> void:
	var before := level
	level = new_level
	Graphics.pressure = mini(level, 2)
	MemoryRelief.release()
	print("[memory_guard] level %d -> %d at %.0f MB (peak %.0f MB): caches released, pressure %d" % [before, level, mb, peak_mb, Graphics.pressure])
	if on_level.is_valid():
		on_level.call(level, mb)
	if level >= 3 and before < 3 and on_limit.is_valid():
		on_limit.call()
	level_changed.emit(level, mb)


func _read_mb() -> float:
	if reader.is_valid():
		return float(reader.call())
	return read_mb()


## This process's resident memory in MB; 0.0 where it can't be read. On Android the plugin reads it (Godot's
## own file access refuses /proc there: the first phone run of this guard found that); on Linux the file is
## read directly; elsewhere there is no reading and the guard stays quiet.
static func read_mb() -> float:
	if OS.has_feature("android"):
		var kb := AndroidNative.resident_kb()
		return kb / 1024.0 if kb > 0 else 0.0
	if not FileAccess.file_exists(STATUS_FILE):
		return 0.0
	var f := FileAccess.open(STATUS_FILE, FileAccess.READ)
	if f == null:
		return 0.0
	# (A /proc file reports a length of 0, so it is read line by line, never as one string.)
	var lines := 0
	while not f.eof_reached() and lines < 80:
		var line := f.get_line()
		lines += 1
		if line.begins_with("VmRSS:"):
			return parse_vmrss(line)
	return 0.0


## "VmRSS:\t  412345 kB" -> megabytes; 0.0 for anything else.
static func parse_vmrss(line: String) -> float:
	var text := line.replace("\t", " ").strip_edges()
	if not text.begins_with("VmRSS:"):
		return 0.0
	var parts := text.trim_prefix("VmRSS:").strip_edges().split(" ", false)
	if parts.is_empty() or not parts[0].is_valid_int():
		return 0.0
	var kb := parts[0].to_int()
	if kb < 0:
		return 0.0
	var unit := str(parts[1]).to_lower() if parts.size() > 1 else "kb"
	var mb := kb / 1024.0
	if unit == "mb":
		mb = float(kb)
	elif unit == "b":
		mb = kb / 1048576.0
	return mb
