extends RefCounted
## Moods and needs that drift with the REAL clock, even while the game is
## closed: sleepy late at night, and everyone settles back toward their
## usual, calm self. Absence is never punished: being away only ever lets
## loneliness settle to a gentle "glad you're back" (never higher).

const LONELY_PER_HOUR := 0.025   # how fast loneliness settles toward CALM_LONELY
const CALM_LONELY := 0.35         # missing you a little, never more (away time can't push past ABSENCE_MAX)
const ABSENCE_MAX := 0.45
const ENERGY_RATE := 0.2       # how fast energy follows the time of day, per hour
const HAPPY_RATE := 0.04
const MAX_CATCH_UP_H := 72.0   # a long absence shouldn't flatten everyone completely


## Energy a person "should" have at this hour.
static func energy_target(hour: float) -> float:
	if hour < 6.0 or hour >= 23.0:
		return 0.15
	if hour < 9.0:
		return lerpf(0.4, 0.85, (hour - 6.0) / 3.0)
	if hour < 14.0:
		return 0.85
	if hour < 17.0:
		return 0.7
	if hour < 21.0:
		return 0.6
	return lerpf(0.6, 0.15, (hour - 21.0) / 2.0)


## Applies the time since c.last_update (unix seconds) and stamps a new one.
## `now_unix` / `hour` are injectable for tests.
static func catch_up(c: Dictionary, now_unix: float, hour: float) -> void:
	var last := float(c.get("last_update_unix", now_unix))
	var hours := clampf((now_unix - last) / 3600.0, 0.0, MAX_CATCH_UP_H)
	c["last_update_unix"] = now_unix
	if hours <= 0.0:
		return
	var m: Dictionary = c.get("mood", {})
	var was := float(m.get("loneliness", 0.3))
	var lonely := move_toward(was, CALM_LONELY, LONELY_PER_HOUR * hours)
	lonely = clampf(minf(lonely, maxf(was, ABSENCE_MAX)), 0.0, 1.0)
	var energy := float(m.get("energy", 0.7))
	energy = lerpf(energy, energy_target(hour), 1.0 - exp(-ENERGY_RATE * hours))
	var happy_target := 0.65 - 0.25 * maxf(0.0, lonely - 0.6)
	var happy := lerpf(float(m.get("happiness", 0.7)), happy_target, 1.0 - exp(-HAPPY_RATE * hours))
	m["loneliness"] = snappedf(lonely, 0.001)
	m["energy"] = snappedf(clampf(energy, 0.0, 1.0), 0.001)
	m["happiness"] = snappedf(clampf(happy, 0.0, 1.0), 0.001)
	c["mood"] = m


static func now_hour() -> float:
	var t := Time.get_datetime_dict_from_system()
	return float(t.hour) + float(t.minute) / 60.0


## A friend's company lifts loneliness a little (being near the player,
## a chat with another resident).
static func company(c: Dictionary, amount: float) -> void:
	var m: Dictionary = c.get("mood", {})
	m["loneliness"] = clampf(float(m.get("loneliness", 0.3)) - amount, 0.0, 1.0)
	m["happiness"] = clampf(float(m.get("happiness", 0.7)) + amount * 0.3, 0.0, 1.0)
	c["mood"] = m


static func is_sleepy(c: Dictionary) -> bool:
	return float(c.get("mood", {}).get("energy", 1.0)) < 0.3
