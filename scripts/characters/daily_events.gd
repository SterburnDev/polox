extends RefCounted
## Small random happenings: a resident finds something shiny, hums, naps,
## admires the light, or comes over to cheer on one of your dreams.
## Notable ones go into the Memory Book.

const PromptBuilder := preload("res://scripts/ai/prompt_builder.gd")
const ReplyParser := preload("res://scripts/ai/reply_parser.gd")
const MoodSim := preload("res://scripts/characters/mood_sim.gd")
const Seasons := preload("res://scripts/world/seasons.gd")
const WEATHER_LINES := {
	"snow": ["Snow! Let's catch some on our tongues!", "Everything's so quiet when it snows..."],
	"rain": ["Listen to the rain... perfect blanket weather.", "Rainy days are for tea and stories."],
	"leaves": ["The leaves are dancing today!", "Crunchy leaf season is the best season."],
	"petals": ["Petals everywhere! It's like the sky is celebrating.", "Spring smells like hope, doesn't it?"],
	"fireflies": ["Look, fireflies! Make a wish!", "The fireflies came out to say goodnight."],
}

const ITEMS := ["shiny pebble", "tiny button", "four-leaf clover", "lost marble", "pretty feather", "star-shaped leaf", "smooth sea glass"]
const MAX_PER_DAY := 24
const MAX_DREAM_CHEERS_PER_DAY := 2

var director: Node
var _today := ""
var _count := 0
var _dream_cheers_today: Dictionary = {}   # dream id -> times cheered today
var _cheers_today := 0
var _last_template := -1


func _init(d: Node) -> void:
	director = d


func _reset_day() -> void:
	var day := Time.get_date_string_from_system()
	if day != _today:
		_today = day
		_count = 0
		_cheers_today = 0
		_dream_cheers_today.clear()


func open_dreams() -> Array:
	return GameState.dream_list().filter(func(d): return str(d.get("status", "")) != "done" and str(d.get("text", "")) != "")


## Picks a fitting event. Dream cheers are favoured until one has happened
## today, so friends reliably notice your dreams within the first minutes.
func pick(rng: RandomNumberGenerator, has_sleepy: bool) -> String:
	var options := {"found_item": 3.0, "hum": 2.0, "admire_light": 2.0, "stretch": 1.0}
	if Seasons.enabled() and WEATHER_LINES.has(Seasons.weather()):
		options["weather_talk"] = 2.5
	if has_sleepy:
		options["nap"] = 3.0
	if not open_dreams().is_empty() and _cheers_today < MAX_DREAM_CHEERS_PER_DAY:
		options["dream_cheer"] = 8.0 if _cheers_today == 0 else 1.0
	var total := 0.0
	for k in options:
		total += options[k]
	var r := rng.randf() * total
	for k in options:
		r -= options[k]
		if r <= 0.0:
			return k
	return "hum"


func run_random() -> void:
	_reset_day()
	if not bool(GameState.world.get("settings", {}).get("daily_events", true)) or _count >= MAX_PER_DAY:
		return
	var ids: Array = director.world.actors.keys().filter(func(i): return not director.busy.has(i) and i != director.world.talk.talking_to)
	if ids.is_empty():
		return
	var has_sleepy := ids.any(func(i): return MoodSim.is_sleepy(GameState.get_character(i)))
	var kind := pick(director.rng, has_sleepy)
	# Guarantee: by the second event of the day, someone brings up a dream.
	if _count >= 1 and _cheers_today == 0 and not open_dreams().is_empty():
		kind = "dream_cheer"
	await run(kind, ids.pick_random())


func run(kind: String, id: String) -> void:
	var w: Node = director.world
	if not w.actors.has(id):
		return
	_count += 1
	var a: Node3D = w.actors[id]
	var c := GameState.get_character(id)
	var who := str(c.get("name", ""))
	match kind:
		"found_item":
			var item: String = ITEMS.pick_random()
			a.emote("★")
			a.say("Look! I found a %s!" % item, 5.0)
			GameState.add_moment("%s found a %s" % [who, item], "%s found a %s on the floor of %s and was very proud." % [who, item, w.room.data.get("name", "the room")], id)
		"hum":
			a.emote("♪")
			a.say("♪ hm hm hmm ♪", 4.0)
		"nap":
			a.say("*snooze*", 4.0)
			for i in 3:
				a.emote("z", Color("#b8aed6"))
				await w.get_tree().create_timer(0.8).timeout
				if not is_instance_valid(a):
					return
		"admire_light":
			var part := PromptBuilder.time_label().split(" (")[0]
			a.say("The light is so soft this %s..." % part, 5.0)
		"stretch":
			a.emote("~")
			a.say("*big stretch* Mmmh.", 3.5)
		"weather_talk":
			var lines: Array = WEATHER_LINES.get(Seasons.weather(), ["What a day."])
			a.emote("♪")
			a.say(str(lines.pick_random()), 5.0)
		"dream_cheer":
			await dream_cheer(id)


## A resident walks over and brings up one of your dreams.
func dream_cheer(id: String) -> void:
	var dreams := open_dreams()
	if dreams.is_empty():
		return
	var dream: Dictionary = dreams.pick_random()
	var w: Node = director.world
	director.busy[id] = true
	var ok: bool = await director.approach(id, w.player.cell())
	director.busy.erase(id)
	if not ok or not w.actors.has(id) or w.talk.is_open():
		return
	var c := GameState.get_character(id)
	var line := await _dream_line(c, str(dream.text))
	var a: Node3D = w.actors[id]
	a.emote("♥", Color("#ff8fab"))
	a.say(line, 7.0)
	ChatLog.append(id, GameState.current_room_id, "ai", line, "happy", {"kind": "event", "event": "dream_cheer"})
	_cheers_today += 1
	var key := str(dream.get("id", ""))
	_dream_cheers_today[key] = int(_dream_cheers_today.get(key, 0)) + 1
	if _dream_cheers_today[key] == 1:  # one Memory Book entry per dream per day
		GameState.add_moment("%s cheered on your dream" % c.get("name", ""), "\"%s\"\n%s said: %s" % [dream.text, c.get("name", ""), line], id)


func _dream_line(c: Dictionary, dream: String) -> String:
	var you := GameState.player_name()
	var templates := [
		"Hey%s... I keep thinking about your dream: \"%s\". I really think you can do it." % [" " + you if you != "" else "", dream],
		"Psst! How's \"%s\" going? Even a tiny step today counts!" % dream,
		"I told the plants about your dream, \"%s\". They're rooting for you. Literally." % dream,
		"You know what would be amazing? You and \"%s\". I can totally picture it." % dream,
		"Random thought: \"%s\" suits you so much. What's one small step you could take this week?" % dream,
	]
	var pick := randi() % templates.size()
	if pick == _last_template:
		pick = (pick + 1) % templates.size()  # never the same line twice in a row
	_last_template = pick
	var fallback: String = templates[pick]
	if AIClient.is_mock() or AIClient.busy() or AIClient.spare_capacity() < 3:
		return fallback
	var msgs := [
		{"role": "system", "content": "You are %s. Personality: %s. Speech style: %s. In ONE short, warm, specific sentence (max 25 words), bring up the player's dream naturally and cheer them on. Reply only JSON: {\"segments\":[{\"emotion\":\"happy\",\"text\":\"...\"}],\"memory_note\":\"\"}" % [c.get("name", ""), c.get("personality", ""), c.get("speech_style", "")]},
		{"role": "user", "content": "%s's dream: %s" % [you if you != "" else "The player", dream]},
	]
	var r: Dictionary = await AIClient.chat(msgs, {"max_tokens": 120})
	if not r.get("ok", false):
		return fallback
	var text := ReplyParser.joined_text(ReplyParser.parse(str(r.text), PackedStringArray(["happy", "neutral"])).segments)
	return text if text.length() >= 8 and text != "..." else fallback


## A dream marked done that this friend hasn't congratulated yet ("" if none).
## Marks it as celebrated by them.
func uncelebrated_dream(c: Dictionary) -> String:
	var id := str(c.get("id", ""))
	for d in GameState.dream_list():
		if str(d.get("status", "")) != "done":
			continue
		var by: Array = d.get("celebrated_by", [])
		if not id in by:
			by.append(id)
			d["celebrated_by"] = by
			GameState.save_dreams()
			return str(d.get("text", ""))
	return ""
