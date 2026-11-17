extends RefCounted
## Residents' daily routines, so the world isn't static: for morning,
## afternoon, evening and night, a room (empty = their home room) and an
## activity ("reading by the window"). Edited in the Character Creator's
## Personality tab. Uses the real clock (and the Time Machine in tests).
##   character.routine = {morning: {room, activity}, afternoon: ..., evening: ..., night: ...}

const Clock := preload("res://scripts/variety/clock.gd")

const PARTS: PackedStringArray = ["morning", "afternoon", "evening", "night"]
const PART_NAMES := {"morning": "Morning", "afternoon": "Afternoon", "evening": "Evening", "night": "Night"}


static func entry(c: Dictionary, part: String) -> Dictionary:
	var r: Variant = c.get("routine", {})
	var e: Variant = r.get(part, {}) if r is Dictionary else {}
	return e if e is Dictionary else {}


## Where the character is right now (their routine room, else home).
static func room_now(c: Dictionary, part: String = "") -> String:
	var p := part if part != "" else Clock.part_of_day()
	var room := str(entry(c, p).get("room", ""))
	if room != "" and SaveManager.room_exists(room):
		return room
	return str(c.get("home_room", "home"))


static func activity_now(c: Dictionary, part: String = "") -> String:
	return str(entry(c, part if part != "" else Clock.part_of_day()).get("activity", "")).strip_edges()


static func set_entry(c: Dictionary, part: String, room: String, activity: String) -> void:
	if not c.get("routine") is Dictionary:
		c["routine"] = {}
	c.routine[part] = {"room": room, "activity": activity.strip_edges().substr(0, 60)}
