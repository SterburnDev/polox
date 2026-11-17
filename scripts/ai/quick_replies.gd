extends RefCounted
## Quick-reply chips: up to three short things you might say next, so a
## conversation can go on with one tap. Real AIs suggest them in the same
## JSON reply; Mock mode, offline lines and greetings use these canned ones.

const MAX := 3
const MAX_LEN := 48

const CANNED := {
	"greeting": [["Hi!", "How are you?", "I have news!"], ["Hey you", "What's new?", "I missed you"], ["Hello!", "How's your day?", "Guess what?"]],
	"sad": [["Thanks, that helps", "Can we talk about something else?", "Tell me something nice"], ["I'll be okay", "Can you distract me?", "Thanks for listening"]],
	"happy": [["Thank you!!", "I'm so proud", "Let's celebrate!"], ["Haha yes!", "It felt amazing", "What about you?"]],
	"question": [["Good point", "Tell me more", "What would you do?"], ["Hmm, maybe", "I'll think about it", "You're right"]],
	"gift": [["I'm glad you like it!", "I made it myself", "You deserve it"], ["It reminded me of you", "Happy to!", "What's your favorite thing?"]],
	"bye": [["See you soon!", "Wait, one more thing", "Sleep well"]],
	"crisis": [["Thanks for caring", "I'll reach out to someone", "Can you stay with me?"]],
	"default": [["Tell me more!", "What are you up to?", "That's so you"], ["Haha", "How was your day?", "I love that"], ["Really?", "What do you think?", "Let's do something fun"]],
}


## Cleans whatever the AI suggested: strings only, short, no duplicates, max 3.
static func clean(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for r in raw:
		if not r is String:
			continue
		var s := str(r).strip_edges().trim_prefix("\"").trim_suffix("\"").strip_edges()
		if s == "" or s.length() > MAX_LEN or s.begins_with("{"):
			continue
		var dup := false
		for o in out:
			dup = dup or str(o).to_lower() == s.to_lower()
		if not dup:
			out.append(s)
		if out.size() >= MAX:
			break
	return out


static func canned(kind: String, rng: RandomNumberGenerator = null) -> Array:
	var sets: Array = CANNED.get(kind, CANNED.default)
	var i := rng.randi_range(0, sets.size() - 1) if rng else randi() % sets.size()
	return (sets[i] as Array).duplicate()


## Which canned set fits what the player just said.
static func kind_for(said: String, gift: bool = false, crisis: bool = false) -> String:
	if crisis:
		return "crisis"
	if gift:
		return "gift"
	var low := " " + said.to_lower() + " "
	const MockBrain := preload("res://scripts/ai/mock_brain.gd")
	for w in MockBrain.BYE_WORDS:
		if low.contains(w):
			return "bye"
	for w in MockBrain.SAD_WORDS:
		if low.contains(w):
			return "sad"
	for w in MockBrain.HAPPY_WORDS:
		if low.contains(w):
			return "happy"
	if said.strip_edges().ends_with("?"):
		return "question"
	return "default"


static func enabled() -> bool:
	return bool(GameState.settings.get("quick_replies", true))
