extends RefCounted
## When battles happen. A friend you made walks up with a reason from your past conversations
## ("You told me you can't stand losing at cards. Let's see how you do against me!") and you choose
## Accept or Not now; rare by default (Settings: Off / Rare / Sometimes), in the Deep only unless
## you allow the Light World too. You can always start one yourself: say "I want to fight" in a
## chat, Menu > Battle, or a Battle Spot object. Saying Not now has no cost, ever.
##
## Reasons: the AI writes one from a memory when there's a real AI; otherwise (Mock mode, or the AI
## is away) one of the built-in lines below uses a memory note, a like, or nothing.

const RATES := {"off": 0.0, "rare": 0.03, "sometimes": 0.09}   # chance per check (a check every ~2 minutes of play)
const RATE_LABELS := {"off": "Off", "rare": "Rare (default)", "sometimes": "Sometimes"}
const COOLDOWN_S := 600.0

const WITH_MEMORY := [
	"You told me %s. Ever since, I've wanted to see how you handle a friendly fight!",
	"Remember when you said %s? That's been on my mind. Spar with me?",
	"I keep thinking about how %s. Okay, enough thinking: battle me!",
]
const WITH_LIKE := [
	"I've been practising my %s moves. Want to see? (It's a battle.)",
	"Loser has to talk about %s for an hour. Fight?",
]
const PLAIN := [
	"I'm bored and full of energy. Friendly fight?",
	"Let's see who's faster: you or my bullets!",
	"I made up a new dodge-dance. Will you try it with me?",
]
const FIGHT_WORDS := ["fight", "battle", "spar", "duel", "brawl"]
const WANT_WORDS := ["want", "wanna", "let's", "lets", "can we", "could we", "how about", "i'd like", "ready to", "challenge"]


static func rate_of(settings: Dictionary) -> float:
	return float(RATES.get(str(settings.get("encounters", "rare")), RATES.rare))


## Should a friend walk up now? Only in the Deep unless everyday places are allowed, never in the Light
## World (your real home: no battles there), never in the
## first minute, never twice within the cooldown, never while something else is going on.
static func should_start(settings: Dictionary, place_is_dark: bool, since_last_s: float, roll: float) -> bool:
	var rate := rate_of(settings)
	if rate <= 0.0 or since_last_s < COOLDOWN_S:
		return false
	if not place_is_dark and not bool(settings.get("encounters_light_world", false)):
		return false
	return roll < rate


## "I want to fight" (and friends of that sentence) in something you typed.
static func asks_to_fight(text: String) -> bool:
	var t := text.to_lower()
	var fight := FIGHT_WORDS.any(func(w): return t.contains(w))
	if not fight:
		return false
	if t.contains("don't want to fight") or t.contains("dont want to fight") or t.contains("no fight") or t.contains("stop fighting"):
		return false
	return WANT_WORDS.any(func(w): return t.contains(w)) or t.strip_edges().begins_with("fight") or t.contains("fight me") or t.contains("battle me")


## A reason built from what a friend knows about you (no AI needed).
static func reason_for(c: Dictionary, rng: RandomNumberGenerator) -> String:
	var notes: Array = (c.get("memory_notes", []) as Array).filter(func(n): return str(n).strip_edges() != "")
	if not notes.is_empty():
		var note := str(notes[rng.randi() % notes.size()]).strip_edges().trim_suffix(".")
		var line := str(WITH_MEMORY[rng.randi() % WITH_MEMORY.size()])
		return line % _as_clause(note)
	var likes := str(c.get("likes", "")).split(",", false)
	if not likes.is_empty() and str(likes[0]).strip_edges() != "":
		return str(WITH_LIKE[rng.randi() % WITH_LIKE.size()]) % str(likes[0]).strip_edges()
	return str(PLAIN[rng.randi() % PLAIN.size()])


## "Has a cat named Biscuit" -> "you have a cat named Biscuit"; anything else lower-cased in front.
static func _as_clause(note: String) -> String:
	var n := note.strip_edges()
	var swaps := [["Has ", "you have "], ["Is ", "you're "], ["Loves ", "you love "], ["Likes ", "you like "], ["Hates ", "you can't stand "],
		["Works ", "you work "], ["Lives ", "you live "], ["Wants ", "you want "], ["Was ", "you were "], ["Can't ", "you can't "]]
	for s in swaps:
		if n.begins_with(str(s[0])):
			return str(s[1]) + n.substr(str(s[0]).length())
	return n.left(1).to_lower() + n.substr(1)


## The prompt that asks a real AI for the reason (one short line, in character, from one memory).
static func ai_messages(c: Dictionary, note: String) -> Array:
	return [
		{"role": "system", "content": "You are %s, a friend in a cozy game. Write ONE short, playful line (under 25 words) inviting the player to a friendly, harmless battle, mentioning this thing you remember about them: \"%s\". No violence beyond a playful spar. Reply with the line only." % [str(c.get("name", "a friend")), note]},
		{"role": "user", "content": "Invite me to a friendly fight."},
	]
