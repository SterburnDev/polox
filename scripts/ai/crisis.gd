extends RefCounted
## A small local safety net. Real AI providers get the crisis-care instruction
## in every system prompt; this catches clear crisis wording so that Mock mode
## (which can't understand anything) and AI failures still answer with care
## instead of a random joke.

const PHRASES: PackedStringArray = [
	"kill myself", "killing myself", "suicide", "suicidal", "end my life", "end it all",
	"want to die", "wanna die", "wish i was dead", "wish i were dead", "better off dead",
	"self harm", "self-harm", "selfharm", "hurt myself", "hurting myself", "cut myself",
	"cutting myself", "no reason to live", "nothing to live for", "don't want to be here anymore",
	"dont want to be here anymore", "can't go on", "cant go on", "overdose", "take my own life",
	"don't want to live", "dont want to live", "not want to exist", "disappear forever",
]


static func detect(text: String) -> bool:
	var t := " " + text.to_lower().replace("’", "'") + " "
	for p in PHRASES:
		if t.find(p) != -1:
			return true
	return t.find(" kms ") != -1


## A sincere, non-playful reply used whenever we can't rely on the AI.
static func caring_segments(character_name: String, player_name: String) -> Array:
	var you := player_name if player_name != "" else "friend"
	return [
		{"emotion": "sad", "text": "Hey, %s. I'm putting the silly stuff down for a second, because what you just said really matters to me, and I'm glad you told me." % you},
		{"emotion": "neutral", "text": "Please reach out to someone you trust, or a crisis line where you live. findahelpline.com lists free ones, and in the US you can call or text 988. If you might act on these thoughts, please call your local emergency number now."},
		{"emotion": "neutral", "text": "You don't have to carry this alone. %s is right here with you while you reach out." % character_name},
	]


## Extra system line added when the latest message looks like a crisis.
static func system_hint() -> String:
	return "IMPORTANT: The player's latest message may signal serious distress or self-harm thoughts. Step out of playful mode now. Respond with sincere care, no jokes; encourage them to contact a trusted person or a local crisis line (e.g. findahelpline.com, or 988 in the US) or emergency services if in danger."
