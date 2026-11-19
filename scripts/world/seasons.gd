extends RefCounted
## Seasons, daily weather and special days from the REAL date, so the world
## (and your friends' small talk) follows the calendar. Weather is picked
## deterministically per day: the same all day, different tomorrow.
## Seasons assume the northern hemisphere unless world settings say "south".

const HOLIDAYS := {
	"01-01": ["new_year", "New Year's Day", "Happy New Year! Any little wishes for this year?"],
	"02-14": ["valentine", "Valentine's Day", "Happy Valentine's Day! A good day to tell someone you love them."],
	"03-20": ["spring_equinox", "the first day of spring", "It's the first day of spring! Everything feels new."],
	"06-21": ["midsummer", "midsummer", "It's midsummer, the longest day of the year!"],
	"10-31": ["halloween", "Halloween", "Happy Halloween! Boo! ...Did I scare you?"],
	"12-21": ["winter_solstice", "the winter solstice", "It's the longest night of the year. Let's make it cozy."],
	"12-24": ["winter_eve", "a winter holiday eve", "It's a cozy winter holiday eve! Warm drinks for everyone."],
	"12-25": ["winter_holiday", "a winter holiday", "Happy winter holidays! I hope today is gentle and warm."],
	"12-31": ["new_years_eve", "New Year's Eve", "It's the last day of the year! What are you proud of this year?"],
}

const WEATHER_WORDS := {
	"clear": "a clear sky", "rain": "soft rain", "snow": "gentle snow", "leaves": "falling leaves",
	"petals": "drifting blossom petals", "fireflies": "fireflies glowing",
}


static func _date(dt: Dictionary) -> Dictionary:
	return dt if not dt.is_empty() else Time.get_datetime_dict_from_system()


static func season(dt: Dictionary = {}) -> String:
	var d := _date(dt)
	var m := int(d.get("month", 1))
	var names := ["winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn", "autumn", "winter"]
	var s: String = names[(m - 1) % 12]
	if str(GameState.world.get("settings", {}).get("hemisphere", "north")) == "south":
		s = {"winter": "summer", "summer": "winter", "spring": "autumn", "autumn": "spring"}[s]
	return s


## A special day today, or {} : {id, name, greeting}.
static func holiday(dt: Dictionary = {}) -> Dictionary:
	var d := _date(dt)
	var key := "%02d-%02d" % [int(d.get("month", 1)), int(d.get("day", 1))]
	var birthday := str(GameState.world.get("player", {}).get("birthday", "")).strip_edges()
	if birthday != "" and birthday.right(5) == key:
		var you := GameState.player_name()
		return {"id": "birthday", "name": "your birthday", "greeting": "HAPPY BIRTHDAY%s!! Today is all about you!" % (", " + you if you != "" else "")}
	if HOLIDAYS.has(key):
		var h: Array = HOLIDAYS[key]
		return {"id": h[0], "name": h[1], "greeting": h[2]}
	return {}


## Today's weather: stable for the whole day, chosen by season.
static func weather(dt: Dictionary = {}) -> String:
	var d := _date(dt)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%04d-%02d-%02d" % [int(d.get("year", 2026)), int(d.get("month", 1)), int(d.get("day", 1))])
	var roll := rng.randf()
	var night := int(d.get("hour", 12)) >= 21 or int(d.get("hour", 12)) < 5
	match season(d):
		"winter":
			return "snow" if roll < 0.5 else "clear"
		"spring":
			return "petals" if roll < 0.4 else ("rain" if roll < 0.65 else "clear")
		"summer":
			if night and roll < 0.7:
				return "fireflies"
			return "rain" if roll < 0.2 else "clear"
		_:
			return "leaves" if roll < 0.45 else ("rain" if roll < 0.7 else "clear")


static func enabled() -> bool:
	return bool(GameState.world.get("settings", {}).get("seasons", true))


## One line for prompts, e.g. "autumn, falling leaves outside, and it's Halloween".
static func describe(dt: Dictionary = {}) -> String:
	if not enabled():
		return ""
	var d := _date(dt)
	var parts := PackedStringArray([season(d)])
	var w := weather(d)
	if w != "clear":
		parts.append(str(WEATHER_WORDS[w]))
	var h := holiday(d)
	if not h.is_empty():
		parts.append("and today is " + str(h.name))
	return ", ".join(parts)
