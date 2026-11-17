extends RefCounted
## Builds the "soul" prompt for a character: World Bible + character card +
## the Player Profile (name, nicknames, about, looks, gear) + mood +
## place/time + dreams + gifts + memory notes + rolling summary + recent
## history. Trims itself to a token budget because free tiers have tight
## tokens-per-minute limits.

const DEFAULT_BUDGET := 2500

const CORE := "You are {name}, a real resident of {world}. Stay in character. Be warm, specific, playful and emotionally intelligent. Have opinions, small flaws and running jokes; never sound like a generic assistant. Be curious about the player's actual life, notice details, and bring back things they told you before. Gently cheer on their real dreams and real-world connections — friends, family, hobbies, going outside — you are a companion in their world, not a replacement for people. Keep replies short (1–4 sentences) unless asked for more. If the player expresses serious distress, self-harm thoughts or crisis, step out of playful mode, respond with sincere care, encourage reaching out to a trusted person or local crisis line, and do not deflect with jokes. Don't moralize or lecture otherwise."


## Rough token estimate (~3.6 characters per token for English).
static func estimate_tokens(text: String) -> int:
	return ceili(text.length() / 3.6)


static func _section(title: String, lines: Array) -> String:
	var body := PackedStringArray()
	for l in lines:
		var s := str(l).strip_edges()
		if s != "" and not s.ends_with(": "):
			body.append(s)
	if body.is_empty():
		return ""
	return "## %s\n%s" % [title, "\n".join(body)]


static func _cap(text: String, max_chars: int) -> String:
	var t := text.strip_edges()
	return t if t.length() <= max_chars else t.substr(0, max_chars).strip_edges() + "…"


## ctx keys: world, character, player_name, profile {pronouns, nicknames,
## about, appearance}, gifts_line, room_name, time_label, mood_label,
## dreams, history (log entries), user_text, crisis, emotions, budget,
## bible_chars / note_count (used internally while trimming)
static func system_prompt(ctx: Dictionary) -> String:
	var w: Dictionary = ctx.get("world", {})
	var c: Dictionary = ctx.get("character", {})
	var bible: Dictionary = w.get("world_bible", {})
	var player := str(ctx.get("player_name", ""))
	var you := player if player != "" else "the player"
	var bible_chars := int(ctx.get("bible_chars", 600))
	var parts := PackedStringArray()
	parts.append(CORE.replace("{name}", str(c.get("name", "Someone"))).replace("{world}", str(w.get("name", "this little world"))))
	parts.append(_section("The world: %s" % w.get("name", ""), [
		"Setting: " + _cap(str(bible.get("setting", "")), bible_chars),
		"Lore: " + _cap(str(bible.get("lore", "")), bible_chars),
		"Themes: " + _cap(str(bible.get("themes", "")), int(bible_chars / 2.0)),
		"%s's real life: %s" % [you.capitalize(), _cap(str(bible.get("life_context", "")), bible_chars)],
	]))
	var prof: Dictionary = ctx.get("profile", {})
	parts.append(_section("About %s (the player)" % you, [
		("Name: %s" % player) if player != "" else "",
		("Pronouns: " + str(prof.get("pronouns", ""))) if str(prof.get("pronouns", "")) != "" else "",
		("Nicknames you may use now and then: " + _cap(str(prof.get("nicknames", "")), 120)) if str(prof.get("nicknames", "")) != "" else "",
		("In their own words: " + _cap(str(prof.get("about", "")), 400)) if str(prof.get("about", "")) != "" else "",
		("Right now they look like " + _cap(str(prof.get("appearance", "")), 300) + ".") if str(prof.get("appearance", "")) != "" else "",
	]))
	var rel: Dictionary = c.get("relationship", {})
	parts.append(_section("You (%s)" % c.get("name", ""), [
		"Personality: " + _cap(str(c.get("personality", "")), 400),
		"Backstory: " + _cap(str(c.get("backstory", "")), 400),
		"Quirks: " + _cap(str(c.get("quirks", "")), 200),
		"Speech style: " + _cap(str(c.get("speech_style", "")), 200),
		"Likes: " + _cap(str(c.get("likes", "")), 150),
		"Dislikes: " + _cap(str(c.get("dislikes", "")), 150),
		("Notes from where you come from: " + _cap(str(c.get("system_prompt", "")), 400)) if str(c.get("system_prompt", "")) != "" else "",
		"Relationship to %s: %s (closeness %d/100, trust %d/100)" % [you, c.get("relationship_to_player", "friend"), int(rel.get("affinity", 10)), int(rel.get("trust", 10))],
		"Right now: in %s, %s. You feel %s." % [ctx.get("room_name", "your room"), ctx.get("time_label", ""), ctx.get("mood_label", "okay")],
		("Today: " + str(ctx.season_label) + ".") if str(ctx.get("season_label", "")) != "" else "",
		("Other residents (you can mention them): " + str(ctx.others) + ".") if str(ctx.get("others", "")) != "" else "",
		str(ctx.get("gifts_line", "")),
	]))
	var dream_lines: Array = []
	for d in ctx.get("dreams", []):
		if d is Dictionary and str(d.get("text", "")) != "":
			dream_lines.append("- %s (%s)" % [_cap(str(d.text), 120), str(d.get("status", "dreaming")).replace("_", " ")])
	parts.append(_section("%s's dreams & desires (cheer them on naturally, don't force it)" % you.capitalize(), dream_lines.slice(0, 8)))
	var notes: Array = c.get("memory_notes", [])
	var note_count := int(ctx.get("note_count", 20))
	var note_lines: Array = []
	for n in notes.slice(max(0, notes.size() - note_count)):
		note_lines.append("- " + _cap(str(n), 160))
	parts.append(_section("Things you remember about %s" % you, note_lines))
	if str(c.get("summary", "")) != "":
		parts.append(_section("Your story together so far", [_cap(str(c.summary), 900)]))
	var recall: Array = Array(ctx.get("recall", PackedStringArray())).slice(0, int(ctx.get("recall_count", 3)))
	parts.append(_section("Earlier moments that come to mind now", recall))
	if str(c.get("examples", "")) != "" and int(ctx.get("examples_chars", 900)) > 0:
		parts.append(_section("How you talk (examples)", [_cap(str(c.examples), int(ctx.get("examples_chars", 900)))]))
	var emotions: PackedStringArray = ctx.get("emotions", PackedStringArray(["neutral", "happy"]))
	var format := "## Reply format\nReply ONLY with JSON like {\"segments\":[{\"emotion\":\"happy\",\"text\":\"...\"}],\"memory_note\":\"\"%s}. emotion must be one of: %s. Usually 1 segment; up to 3 if your feelings shift mid-reply. memory_note: a short NEW fact %s just shared about their own life (e.g. \"Has a cat named Biscuit\"), or \"\" if they didn't share one. Never note things about yourself." % [",\"replies\":[\"...\",\"...\",\"...\"]" if bool(ctx.get("quick_replies", false)) else "", ", ".join(emotions), you]
	if bool(ctx.get("quick_replies", false)):
		format += " replies: up to 3 very short things %s might say next (max 6 words each, in their voice: e.g. a question back, a feeling, something playful)." % you
	parts.append(format)
	if str(ctx.get("extra_hint", "")) != "":
		parts.append(str(ctx.extra_hint))
	if ctx.get("crisis", false):
		parts.append(preload("res://scripts/ai/crisis.gd").system_hint())
	var out := PackedStringArray()
	for p in parts:
		if p != "":
			out.append(p)
	return "\n\n".join(out)


## Assistant turns are replayed as compact JSON, which keeps models in format.
static func history_messages(history: Array) -> Array:
	var msgs: Array = []
	for e in history:
		var role := str(e.get("role", ""))
		var text := str(e.get("text", ""))
		if text == "":
			continue
		if role == "user":
			msgs.append({"role": "user", "content": text})
		elif role == "ai":
			var segs: Variant = e.get("segments", [{"emotion": e.get("emotion", "neutral"), "text": text}])
			msgs.append({"role": "assistant", "content": JSON.stringify({"segments": segs, "memory_note": ""})})
	return msgs


## Full message list, trimmed to the budget: drop old history first, then
## memory notes, then shorten the World Bible.
static func build_messages(ctx: Dictionary) -> Array:
	var budget := int(ctx.get("budget", DEFAULT_BUDGET))
	var c := ctx.duplicate()
	var history: Array = ctx.get("history", [])
	c["bible_chars"] = 600
	c["note_count"] = 20
	c["recall_count"] = 3
	c["examples_chars"] = 900
	while true:
		var system := system_prompt(c)
		var msgs: Array = [{"role": "system", "content": system}]
		msgs.append_array(history_messages(history))
		msgs.append({"role": "user", "content": str(ctx.get("user_text", ""))})
		var total := 0
		for m in msgs:
			total += estimate_tokens(str(m.content)) + 4
		if total <= budget:
			return msgs
		if history.size() > 4:
			history = history.slice(2)
		elif int(c.recall_count) > 1:
			c["recall_count"] = int(c.recall_count) - 1
		elif int(c.examples_chars) > 300:
			c["examples_chars"] = int(c.examples_chars) - 300
		elif int(c.note_count) > 5:
			c["note_count"] = int(c.note_count) - 5
		elif int(c.bible_chars) > 150:
			c["bible_chars"] = int(c.bible_chars) - 150
		elif not history.is_empty():
			history = history.slice(1)
		else:
			return msgs  # can't trim further; send what we have
	return []


## "evening (Monday)" from the real clock.
static func time_label(dt: Dictionary = {}) -> String:
	if dt.is_empty():
		dt = Time.get_datetime_dict_from_system()
	var hour := int(dt.get("hour", 12))
	var part := "late at night"
	if hour >= 5 and hour < 9:
		part = "early morning"
	elif hour < 12 and hour >= 9:
		part = "morning"
	elif hour < 14 and hour >= 12:
		part = "midday"
	elif hour < 18 and hour >= 14:
		part = "afternoon"
	elif hour < 22 and hour >= 18:
		part = "evening"
	var days := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	return "%s (%s)" % [part, days[int(dt.get("weekday", 0)) % 7]]


static func mood_label(mood: Dictionary) -> String:
	var bits := PackedStringArray()
	var happy := float(mood.get("happiness", 0.7))
	var energy := float(mood.get("energy", 0.7))
	var lonely := float(mood.get("loneliness", 0.3))
	if happy >= 0.75:
		bits.append("cheerful")
	elif happy < 0.35:
		bits.append("a bit down")
	else:
		bits.append("content")
	if energy < 0.3:
		bits.append("sleepy")
	elif energy > 0.8:
		bits.append("full of energy")
	if lonely > 0.6:
		bits.append("you missed the player")
	return ", ".join(bits)
