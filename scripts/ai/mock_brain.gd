extends RefCounted
## Offline "AI" for Mock mode. It can't understand language, but it reacts to
## a few keywords, uses the character card and the player's dreams, and
## always answers in the same JSON format as a real model, so the whole
## pipeline (parsing, portraits, logs, memory) is exercised without a network.

const Crisis := preload("res://scripts/ai/crisis.gd")
const Voices := preload("res://scripts/ai/voices.gd")

const SAD_WORDS: PackedStringArray = ["sad", "tired", "lonely", "alone", "bad day", "stressed", "anxious", "awful", "rough", "cry", "upset", "exhausted", "hard day", "miss"]
const HAPPY_WORDS: PackedStringArray = ["great", "good news", "yay", "finally", "happy", "awesome", "excited", "did it", "won", "passed", "love it", "amazing"]
const HELLO_WORDS: PackedStringArray = ["hi", "hello", "hey", "yo", "morning", "evening", "hiya", "sup"]
const BYE_WORDS: PackedStringArray = ["bye", "goodnight", "good night", "see you", "later", "gotta go"]

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## Returns the raw "model output" string for a request.
func respond(meta: Dictionary) -> String:
	match str(meta.get("mode", "chat")):
		"summary":
			return summarize(meta)
		"test":
			return JSON.stringify({"segments": [{"emotion": "happy", "text": "Mock mode is working!"}], "memory_note": ""})
		"npc":
			return JSON.stringify(_npc_line(meta))
		"flavor":
			return preload("res://scripts/items/flavor_text.gd").offline(meta.get("item", {}), int(meta.get("variant", 0)) + rng.randi_range(0, 4))
		_:
			return JSON.stringify(_chat(meta))


func _chat(meta: Dictionary) -> Dictionary:
	var c: Dictionary = meta.get("character", {})
	var me := str(c.get("name", "Me"))
	var you := str(meta.get("player_name", ""))
	var said := str(meta.get("user_text", ""))
	var low := " " + said.to_lower() + " "
	var emotions: PackedStringArray = meta.get("emotions", PackedStringArray(["neutral", "happy"]))
	var segments: Array = []
	var voice := Voices.of(c)
	var values := {"you": _you(you), "like": _random_item(str(c.get("likes", "")), "cozy things"), "quirk": _random_item(str(c.get("quirks", "")), "humming")}

	if meta.get("crisis", false) or Crisis.detect(said):
		return {"segments": Crisis.caring_segments(me, you), "memory_note": ""}

	var gift := str(meta.get("gift_name", ""))
	if gift != "":
		values["gift"] = gift
		match str(meta.get("gift_reaction", "nice")):
			"love":
				return {"segments": [_seg(emotions, "surprised", _line(voice, "wow", values)), _seg(emotions, "happy", _line(voice, "gift_love", values))], "memory_note": ""}
			"meh":
				return {"segments": [_seg(emotions, "embarrassed", _line(voice, "gift_meh", values))], "memory_note": ""}
			_:
				return {"segments": [_seg(emotions, "happy", _line(voice, "gift_nice", values))], "memory_note": ""}

	if _has_any(low, BYE_WORDS):
		segments.append(_seg(emotions, "happy", _line(voice, "bye", values)))
	elif _has_any(low, SAD_WORDS):
		segments.append(_seg(emotions, "sad", _line(voice, "sad", values)))
		if rng.randf() < 0.5:
			segments.append(_seg(emotions, "thinking", _line(voice, "tip", values)))
	elif _has_any(low, HAPPY_WORDS):
		segments.append(_seg(emotions, "surprised", _line(voice, "wow", values)))
		segments.append(_seg(emotions, "happy", _line(voice, "happy", values)))
	elif _has_any(low, HELLO_WORDS) and said.length() < 25:
		segments.append(_seg(emotions, "happy", _line(voice, "hello", values)))
	elif said.ends_with("?"):
		segments.append(_seg(emotions, "thinking", _line(voice, "question", values)))
	else:
		segments.append(_seg(emotions, _pick(["happy", "neutral", "thinking", "surprised", "embarrassed"]), _pick(_flavor_lines(c, you))))

	var season := str(meta.get("season_note", ""))
	if season != "" and rng.randf() < 0.2 and segments.size() < 3:
		segments.append(_seg(emotions, "happy", _pick([
			"Also, isn't it lovely? %s." % (season.substr(0, 1).to_upper() + season.substr(1)),
			"I love this time of year. %s. Feels cozy." % (season.substr(0, 1).to_upper() + season.substr(1)),
		])))
	var dream := _random_dream(meta.get("dreams", []))
	if dream != "" and rng.randf() < 0.4 and segments.size() < 3:
		segments.append(_seg(emotions, "happy", _pick([
			"Oh! How's \"%s\" going? I keep picturing you doing it." % dream,
			"Also, I haven't forgotten your dream: %s. Tiny step today?" % dream,
			"Random thought: \"%s\" suits you so much." % dream,
		])))
	return {"segments": segments, "memory_note": extract_note(said)}


## A line of this kind in this friend's voice (voices.gd), filled in.
func _line(voice: String, kind: String, values: Dictionary) -> String:
	return Voices.fill(_pick(Voices.lines(voice, kind)), values)


func _flavor_lines(c: Dictionary, you: String) -> Array:
	var values := {"you": _you(you), "like": _random_item(str(c.get("likes", "")), "cozy things"), "quirk": _random_item(str(c.get("quirks", "")), "humming")}
	var out: Array = []
	for l in Voices.lines(Voices.of(c), "flavor"):
		out.append(Voices.fill(str(l), values))
	return out


func _npc_line(meta: Dictionary) -> Dictionary:
	var emotions: PackedStringArray = meta.get("emotions", PackedStringArray(["neutral", "happy"]))
	var other := str(meta.get("other_name", "you"))
	var voice := Voices.of(meta.get("character", {}))
	var line := _line(voice, "npc", {"other": other})
	return {"segments": [_seg(emotions, _pick(["happy", "neutral", "thinking", "sleepy"]), line)], "memory_note": ""}


## Mock summary: keeps the old summary and appends what the player talked about.
func summarize(meta: Dictionary) -> String:
	var previous := str(meta.get("previous_summary", ""))
	var topics: PackedStringArray = []
	for e in meta.get("messages", []):
		if str(e.get("role", "")) == "user":
			var words := str(e.get("text", "")).split(" ", false)
			topics.append(" ".join(words.slice(0, 7)))
	var line := "They chatted about: " + "; ".join(topics.slice(max(0, topics.size() - 5)))
	var out := (previous + " " + line).strip_edges()
	return out.substr(max(0, out.length() - 700))


## Pulls one simple fact out of what the player said ("my name is X", "I love X").
static func extract_note(said: String) -> String:
	var low := said.to_lower().strip_edges()
	var patterns := [
		["my name is ", "Their name is "],
		["my favorite ", "Favorite "],
		["my favourite ", "Favourite "],
		["i really love ", "Really loves "],
		["i love ", "Loves "],
		["i really like ", "Really likes "],
		["i like ", "Likes "],
		["i enjoy ", "Enjoys "],
		["i'm learning ", "Is learning "],
		["i am learning ", "Is learning "],
		["i work as ", "Works as "],
		["i work at ", "Works at "],
		["i study ", "Studies "],
		["i have a ", "Has a "],
	]
	for p in patterns:
		var i := low.find(p[0])
		if i != -1:
			var rest := said.substr(i + p[0].length()).strip_edges()
			for stop in [".", "!", "?", ",", " but ", " and then "]:
				var j := rest.find(stop)
				if j > 0:
					rest = rest.substr(0, j)
			rest = rest.strip_edges()
			if rest.length() >= 2 and rest.length() <= 60:
				return p[1] + rest
	return ""


func _seg(emotions: PackedStringArray, wanted: String, text: String) -> Dictionary:
	var emotion := wanted if wanted in emotions else "neutral"
	return {"emotion": emotion, "text": text}


func _pick(options: Array) -> String:
	return str(options[rng.randi_range(0, options.size() - 1)])


## Whole-word / whole-phrase match ("yo" must not match "you").
func _has_any(low: String, words: PackedStringArray) -> bool:
	var clean := " "
	for ch in low:
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "'" else " "
	clean = " " + " ".join(clean.split(" ", false)) + " "
	for w in words:
		if clean.find(" " + w + " ") != -1:
			return true
	return false


func _you(you: String) -> String:
	return you if you != "" else "friend"


func _random_item(csv: String, fallback: String) -> String:
	var items := csv.split(",", false)
	if items.is_empty():
		return fallback
	return items[rng.randi_range(0, items.size() - 1)].strip_edges()


func _random_dream(dreams: Array) -> String:
	var open: Array = []
	for d in dreams:
		if d is Dictionary and str(d.get("status", "")) != "done" and str(d.get("text", "")) != "":
			open.append(str(d["text"]))
	return _pick(open) if not open.is_empty() else ""
