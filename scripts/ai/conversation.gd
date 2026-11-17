extends RefCounted
## One player <-> character exchange, start to finish: log the player's
## message, build the prompt, ask the AI (or Mock), parse safely, log the
## reply (even failures), then update memory, mood and affinity.
## Tags: [AI_HELPER]

const PromptBuilder := preload("res://scripts/ai/prompt_builder.gd")
const ReplyParser := preload("res://scripts/ai/reply_parser.gd")
const Crisis := preload("res://scripts/ai/crisis.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const Seasons := preload("res://scripts/world/seasons.gd")
const Bonds := preload("res://scripts/characters/bonds.gd")
const Items := preload("res://scripts/items/items.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const GiftRules := preload("res://scripts/items/gift_rules.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const QuickReplies := preload("res://scripts/ai/quick_replies.gd")
const MemoryRecall := preload("res://scripts/ai/memory_recall.gd")
## Prompt size by provider: free cloud tiers have tight token limits; a local model (or Venice) can
## carry more of the friendship (more history, memories and recalled moments).
const BUDGETS := {"ollama": 6000, "venice": 4000}   # (a phone asking its PC keeps the default: it can't tell what the PC uses)

const HISTORY := 12
const MAX_NOTES := 40
const SUMMARY_EVERY := 20
const FALLBACK_LINES: PackedStringArray = [
	"…sorry, my head's all fuzzy. Say that again?",
	"Hm? I totally zoned out for a sec. One more time?",
	"Sorry, the words got tangled in my head. Say that again?",
]

var summarizing := false


func _room_name() -> String:
	return str(SaveManager.load_room(GameState.current_room_id).get("name", "home"))


func base_context(c: Dictionary) -> Dictionary:
	var p: Dictionary = GameState.world.get("player", {})
	var you := GameState.player_name() if GameState.player_name() != "" else "the player"
	return {
		"world": GameState.world,
		"character": c,
		"player_name": GameState.player_name(),
		"room_name": _room_name(),
		"time_label": PromptBuilder.time_label(),
		"mood_label": PromptBuilder.mood_label(c.get("mood", {})),
		"dreams": GameState.dream_list() if bool(p.get("share_dreams", true)) else [],
		"emotions": GameState.expression_names(c),
		"season_label": Seasons.describe(),
		"others": Bonds.others_line(c),
		"profile": {
			"pronouns": str(p.get("pronouns", "")),
			"nicknames": ", ".join(GameState.nicknames()),
			"about": str(p.get("about", "")),
			"appearance": PlayerLook.appearance_line(),
		},
		"gifts_line": GiftRules.context_line(c, you),
		"quick_replies": QuickReplies.enabled(),
	}


## Returns {segments, memory_note, failed: bool, error: String}.
## opts (optional): hint (extra system line), log_extra (fields for the
## player's log line), mock (extra Mock meta), bonus (extra closeness).
func player_says(character_id: String, text: String, opts: Dictionary = {}) -> Dictionary:
	var c := GameState.get_character(character_id)
	var room := GameState.current_room_id
	var history := ChatLog.recent(character_id, HISTORY)
	var first_chat := not history.any(func(e): return e.get("role") == "user")
	ChatLog.append(character_id, room, "user", text, "", opts.get("log_extra", {}))
	var crisis := Crisis.detect(text)
	var ctx := base_context(c)
	ctx["history"] = history
	ctx["user_text"] = text
	ctx["crisis"] = crisis
	var you_word := GameState.player_name() if GameState.player_name() != "" else "They"
	ctx["recall"] = MemoryRecall.recall(ChatLog.read_all(character_id), text, HISTORY + 1, 3, you_word)
	ctx["budget"] = int(BUDGETS.get(str(AIClient.config.get("preset", "")), PromptBuilder.DEFAULT_BUDGET))
	ctx["extra_hint"] = str(opts.get("hint", ""))
	var emotions: PackedStringArray = ctx.emotions
	var meta := {
		"mode": "chat", "character": c, "player_name": GameState.call_name(), "user_text": text,
		"emotions": emotions, "dreams": ctx.dreams, "crisis": crisis, "season_note": ctx.season_label,
	}
	meta.merge(opts.get("mock", {}), true)
	var chat_opts := {"mock": meta}
	if str(c.get("ai_model", "")).strip_edges() != "":
		chat_opts["model"] = str(c.ai_model).strip_edges()   # this friend's own model (Friends > their page)
	var r: Dictionary = await AIClient.chat(PromptBuilder.build_messages(ctx), chat_opts)
	var reply: Dictionary
	var failed: bool = not r.get("ok", false)
	if failed:
		var segs: Array = Crisis.caring_segments(str(c.get("name", "")), str(ctx.player_name)) if crisis else [{"emotion": ReplyParser.match_emotion("thinking", emotions), "text": FALLBACK_LINES[randi() % FALLBACK_LINES.size()]}]
		reply = {"segments": segs, "memory_note": "", "replies": []}
	else:
		reply = ReplyParser.parse(str(r.get("text", "")), emotions)
		if crisis and not _sounds_caring(reply):
			# The model joked through a crisis; replace with the sincere local reply.
			reply = {"segments": Crisis.caring_segments(str(c.get("name", "")), str(ctx.player_name)), "memory_note": "", "replies": []}
	# Quick replies: the AI's own if it gave some, else a canned set that fits.
	if not QuickReplies.enabled():
		reply["replies"] = []
	elif (reply.get("replies", []) as Array).is_empty():
		reply["replies"] = QuickReplies.canned(QuickReplies.kind_for(text, opts.has("hint") and str(opts.get("log_extra", {}).get("kind", "")) == "gift", crisis))
	var segments: Array = reply.segments
	var extra := {}
	if segments.size() > 1:
		extra["segments"] = segments
	if failed:
		extra["failed"] = true
		extra["error"] = str(r.get("error", ""))
	ChatLog.append(character_id, room, "ai", ReplyParser.joined_text(segments), str(segments[0].get("emotion", "neutral")), extra)
	var note := str(reply.get("memory_note", ""))
	if not note_is_grounded(note, text):
		note = ""  # small models sometimes "remember" things nobody said
	var before := float(c.get("relationship", {}).get("affinity", 0))
	apply_effects(c, note, failed)
	if float(opts.get("bonus", 0.0)) > 0.0:
		var rel: Dictionary = c.get("relationship", {})
		rel["affinity"] = minf(100.0, float(rel.get("affinity", 10)) + float(opts.bonus))
		c["relationship"] = rel
	GameState.save_character(c)
	_moments(c, first_chat, text, segments, before)
	maybe_summarize(character_id)
	reply["failed"] = failed
	reply["error"] = str(r.get("error", ""))
	return reply


## Gives an item from the bag. The friend's liked/disliked tags decide the
## reaction; mood and closeness shift, the gift is logged and remembered for
## the AI. Returns the reply plus {reaction, mood_before, mood_after,
## affinity_gain}, or {} if it can't be given (not in the bag, or 3 gifts today).
func give_item(character_id: String, item_id: String) -> Dictionary:
	var c := GameState.get_character(character_id)
	var item := Items.load_item(item_id)
	if c.is_empty() or item.is_empty() or Inventory.count(item_id) <= 0 or not GiftRules.can_gift(c):
		return {}
	var how := GiftRules.reaction(c, item)
	var mood: Dictionary = c.get("mood", {})
	var before := float(mood.get("happiness", 0.7))
	mood["happiness"] = clampf(before + GiftRules.mood_delta(how, item), 0.0, 1.0)
	c["mood"] = mood
	var nth := GiftRules.record(c, item, how)
	var gain := GiftRules.affinity_delta(how, item, nth)
	var aff_before := float(c.get("relationship", {}).get("affinity", 10))
	Inventory.remove(item_id, 1)
	var reply := await player_says(character_id, "*gives you %s*" % item.name, {
		"hint": GiftRules.hint(item, how),
		"log_extra": {"kind": "gift", "item": item_id, "item_name": str(item.name), "reaction": how},
		"mock": {"gift_reaction": how, "gift_name": str(item.name)},
		"bonus": gain,
	})
	c = GameState.get_character(character_id)
	reply["reaction"] = how
	reply["mood_before"] = before
	reply["mood_after"] = float(c.get("mood", {}).get("happiness", before))
	reply["affinity_gain"] = float(c.get("relationship", {}).get("affinity", 0)) - aff_before
	# A "note" line: shown in the Log Viewer, never replayed to the AI as speech.
	ChatLog.append(character_id, GameState.current_room_id, "note", "%s got your %s and %s (happiness %d%% → %d%%, closeness +%.1f)." % [c.get("name", ""), str(item.name).to_lower(), GiftRules.HOW_WORDS.get(how, "kept it"), roundi(before * 100.0), roundi(float(reply.mood_after) * 100.0), float(reply.affinity_gain)], "", {"kind": "gift_note", "item": item_id, "reaction": how})
	if how == "love":
		GameState.add_moment("%s loved your gift" % c.get("name", ""), "You gave %s %s. It's just their kind of thing!" % [c.get("name", ""), item.name], character_id)
	return reply


## Memory Book entries for the first chat and closeness milestones.
func _moments(c: Dictionary, first_chat: bool, said: String, segments: Array, before: float) -> void:
	var who := str(c.get("name", ""))
	if first_chat:
		GameState.add_moment("First chat with %s" % who, "You: %s\n%s: %s" % [said, who, ReplyParser.joined_text(segments)], str(c.get("id", "")))
	var after := float(c.get("relationship", {}).get("affinity", 0))
	var words := {25: "is warming up to you", 50: "feels like a real friend now", 75: "trusts you with their whole heart", 100: "is your best friend"}
	for milestone in [25, 50, 75, 100]:
		if before < milestone and after >= milestone:
			GameState.add_moment("%s %s" % [who, words[milestone]], "Closeness reached %d/100." % milestone, str(c.get("id", "")))
			GameState.notify("♥ %s %s" % [who, words[milestone]])


## A crude check that a crisis reply isn't flippant: it should mention
## reaching out or support. Real models nearly always pass this.
func _sounds_caring(reply: Dictionary) -> bool:
	var t := ReplyParser.joined_text(reply.get("segments", [])).to_lower()
	for w in ["reach out", "someone you trust", "crisis", "helpline", "988", "talk to", "support", "emergency", "not alone", "here for you", "here with you"]:
		if t.find(w) != -1:
			return true
	return false


const STOPWORDS: PackedStringArray = ["that", "this", "with", "have", "they", "their", "them", "your", "about", "really", "very", "just", "likes", "loves", "player", "from", "what", "when", "were", "been", "being", "into", "some", "also", "said", "says"]


## True if the note shares at least one meaningful word (or word stem) with
## what the player actually said this turn.
static func note_is_grounded(note: String, said: String) -> bool:
	if note == "":
		return false
	var said_words := _content_words(said)
	for w in _content_words(note):
		for s in said_words:
			if w == s or (w.length() >= 5 and s.length() >= 5 and w.substr(0, 5) == s.substr(0, 5)):
				return true
	return false


static func _content_words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var word := ""
	for ch in (text.to_lower() + " "):
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			word += ch
		else:
			if word.length() >= 4 and not word in STOPWORDS:
				out.append(word)
			word = ""
	return out


## Memory notes, mood and affinity after a chat turn.
func apply_effects(c: Dictionary, raw_note: String, failed: bool) -> void:
	var note := ChatLog.redact(raw_note)
	if note != "":
		var notes: Array = c.get("memory_notes", [])
		var dup := false
		for n in notes:
			if str(n).to_lower() == note.to_lower():
				dup = true
		if not dup:
			notes.append(note)
			while notes.size() > MAX_NOTES:
				notes.pop_front()
		c["memory_notes"] = notes
	var mood: Dictionary = c.get("mood", {})
	mood["loneliness"] = clampf(float(mood.get("loneliness", 0.3)) - 0.06, 0.0, 1.0)
	mood["happiness"] = clampf(float(mood.get("happiness", 0.7)) + (0.0 if failed else 0.02), 0.0, 1.0)
	c["mood"] = mood
	if not failed:
		var rel: Dictionary = c.get("relationship", {})
		var aff := float(rel.get("affinity", 10))
		rel["affinity"] = minf(100.0, aff + maxf(0.15, 1.2 * (1.0 - aff / 100.0)))
		rel["trust"] = minf(100.0, float(rel.get("trust", 10)) + (0.6 if note != "" else 0.1))
		c["relationship"] = rel
	c["last_talked"] = Defaults.now_iso()


## Local greeting when a conversation opens (no AI call: saves tokens).
func greeting(c: Dictionary) -> Array:
	var you := GameState.call_name()
	var who := you if you != "" else "you"
	var emotions := GameState.expression_names(c)
	var hour := int(Time.get_datetime_dict_from_system().get("hour", 12))
	var mood: Dictionary = c.get("mood", {})
	var line := ""
	var emotion := "happy"
	# Meeting someone comes first: a holiday's hello waits for the next time (else a friend brought from
	# another app on a holiday would never say their own first greeting).
	var special := holiday_greeting(c) if str(c.get("last_talked", "")) != "" else ""
	if special != "":
		line = special
	elif str(c.get("last_talked", "")) == "" and str(c.get("greeting", "")).strip_edges() != "":
		line = str(c.greeting).strip_edges()   # a friend from another app says hello the way they always did
	elif str(c.get("last_talked", "")) == "":
		line = "Oh! Hi, %s! I'm %s. I've been hoping you'd come say hello." % [who, c.get("name", "")]
	elif float(mood.get("loneliness", 0)) > 0.6:
		line = ["There you are, %s! I missed you!" % who, "%s! It's been quiet without you." % who.capitalize()].pick_random()
	elif float(mood.get("energy", 1)) < 0.3:
		line = ["*yawn* Oh, hey %s..." % who, "Mm... hi. I'm a little sleepy, but I'm glad you came."].pick_random()
		emotion = "sleepy"
	elif hour < 10 and hour >= 5:
		line = "Good morning, %s! Did you sleep okay?" % who
	elif hour >= 22 or hour < 5:
		line = "Hey, night owl. What's keeping you up?"
		emotion = "thinking"
	else:
		line = ["Hey %s! What's up?" % who, "Oh, hi! I was just thinking about you.", "Hiii! Come sit, tell me something."].pick_random()
	return [{"emotion": ReplyParser.match_emotion(emotion, emotions), "text": line}]


## The day's special greeting (holiday or birthday), once per friend per day.
static func holiday_greeting(c: Dictionary) -> String:
	if not Seasons.enabled():
		return ""
	var h := Seasons.holiday()
	var today := Time.get_date_string_from_system()
	if h.is_empty() or str(c.get("holiday_greeted", "")) == today:
		return ""
	c["holiday_greeted"] = today
	SaveManager.save_character(c)
	return str(h.greeting)


## Every ~20 new messages, folds older turns into the character's summary so
## long friendships fit in a small prompt. Runs in the background.
func maybe_summarize(character_id: String) -> void:
	if summarizing:
		return
	var c := GameState.get_character(character_id)
	var convo := ChatLog.recent(character_id, 100000)
	var upto := int(c.get("summary_upto", 0))
	var end := convo.size() - HISTORY
	if end - upto < SUMMARY_EVERY:
		return
	summarizing = true
	var chunk := convo.slice(upto, end).filter(func(e): return str(e.get("role", "")) in ["user", "ai"])
	var you := GameState.player_name() if GameState.player_name() != "" else "the player"
	var lines := PackedStringArray()
	for e in chunk:
		lines.append("%s: %s" % [you if e.get("role") == "user" else c.get("name", ""), str(e.get("text", "")).substr(0, 300)])
	var msgs := [
		{"role": "system", "content": "You keep a diary for %s. Merge the previous summary and the new conversation into one short summary (max 120 words, third person, past tense). Keep facts about %s's life, feelings, plans and running jokes. Plain text only." % [c.get("name", ""), you]},
		{"role": "user", "content": "Previous summary: %s\n\nNew conversation:\n%s" % [c.get("summary", "(none)"), "\n".join(lines)]},
	]
	var r: Dictionary = await AIClient.chat(msgs, {"json": false, "max_tokens": 260, "mock": {"mode": "summary", "previous_summary": c.get("summary", ""), "messages": chunk}})
	summarizing = false
	if not r.get("ok", false):
		return  # try again after the next message
	c = GameState.get_character(character_id)
	c["summary"] = ChatLog.redact(str(r.get("text", "")).strip_edges().substr(0, 1200))
	c["summary_upto"] = end
	GameState.save_character(c)
