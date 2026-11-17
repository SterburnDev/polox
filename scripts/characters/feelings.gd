extends RefCounted
## Guesses which face to show for something the player typed, so your own
## character reacts too (happy at good news, sad at a rough day...). Uses
## the same simple word lists as Mock mode: cheap, offline and predictable.

const MockBrain := preload("res://scripts/ai/mock_brain.gd")


static func guess(text: String) -> String:
	var low := " " + text.to_lower() + " "
	for w in MockBrain.SAD_WORDS:
		if low.contains(w):
			return "sad"
	for w in MockBrain.HAPPY_WORDS:
		if low.contains(w):
			return "happy"
	if low.contains("sorry") or low.contains("oops") or low.contains("blush"):
		return "embarrassed"
	if low.contains("angry") or low.contains("annoyed") or low.contains("ugh"):
		return "angry"
	if text.strip_edges().ends_with("!?") or low.contains("wow") or low.contains("what?!"):
		return "surprised"
	if text.strip_edges().ends_with("?"):
		return "thinking"
	if low.contains("sleepy") or low.contains("yawn") or low.contains("bed"):
		return "sleepy"
	if low.contains("haha") or low.contains("lol") or low.contains(":)") or low.contains("<3") or text.strip_edges().ends_with("!"):
		return "happy"
	return "neutral"
