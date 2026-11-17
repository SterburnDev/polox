extends RefCounted
## The clock the variety pack lives by: the real local date and time, plus the
## debug Time Machine (tests, or `--time-machine=3` on the command line, move
## "now" forward by days). Nothing here ever punishes time passing.

static var offset_days := 0.0
static var _args_read := false


static func _args() -> void:
	if _args_read:
		return
	_args_read = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time-machine="):
			offset_days = a.trim_prefix("--time-machine=").to_float()


## Unix seconds "now" (Time Machine included).
static func now() -> float:
	_args()
	return Time.get_unix_time_from_system() + offset_days * 86400.0


## Local date/time dictionary for a unix time (default: now).
static func local(unix: float = -1.0) -> Dictionary:
	var t := now() if unix < 0.0 else unix
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_dict_from_unix_time(int(t) + bias * 60)


static func date_of(unix: float) -> String:
	var d := local(unix)
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


static func today() -> String:
	return date_of(now())


## morning (5-12) | afternoon (12-17) | evening (17-21) | night
static func part_of_day(hour: int = -1) -> String:
	var h := hour if hour >= 0 else int(local().hour)
	if h >= 5 and h < 12:
		return "morning"
	if h >= 12 and h < 17:
		return "afternoon"
	if h >= 17 and h < 21:
		return "evening"
	return "night"


## The Time Machine: move "now" forward (tests, the debug panel).
static func advance(days: float) -> void:
	_args()
	offset_days += days


static func reset() -> void:
	offset_days = 0.0
	_args_read = true
