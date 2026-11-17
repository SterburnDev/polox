extends RefCounted
## Turns whatever the AI sent back into safe {segments, memory_note, replies} data.
## Rule #1: never crash on bad output. Worst case the raw text becomes one
## neutral segment.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const QuickReplies := preload("res://scripts/ai/quick_replies.gd")

const MAX_SEGMENTS := 3
const MAX_NOTE_LEN := 200

## Common words models use instead of our expression names.
const SYNONYMS := {
	"joy": "happy", "joyful": "happy", "glad": "happy", "excited": "happy", "cheerful": "happy",
	"smile": "happy", "smiling": "happy", "laughing": "happy", "delighted": "happy", "content": "happy",
	"warm": "happy", "playful": "happy", "proud": "happy", "grateful": "happy", "love": "happy",
	"mad": "angry", "annoyed": "angry", "frustrated": "angry", "grumpy": "angry", "irritated": "angry",
	"shocked": "surprised", "surprise": "surprised", "amazed": "surprised", "astonished": "surprised",
	"blush": "embarrassed", "blushing": "embarrassed", "shy": "embarrassed", "flustered": "embarrassed",
	"tired": "sleepy", "drowsy": "sleepy", "exhausted": "sleepy", "yawn": "sleepy", "sleep": "sleepy",
	"pondering": "thinking", "curious": "thinking", "thoughtful": "thinking", "confused": "thinking",
	"hmm": "thinking", "wondering": "thinking", "upset": "sad", "unhappy": "sad", "crying": "sad",
	"worried": "sad", "concerned": "sad", "lonely": "sad", "sorry": "sad", "caring": "sad",
	"calm": "neutral", "default": "neutral", "normal": "neutral", "serious": "neutral", "sincere": "neutral",
}


## Main entry point. `emotions` = the character's expression names.
static func parse(raw: String, emotions: PackedStringArray) -> Dictionary:
	var cleaned := _strip_noise(raw)
	var data: Variant = _find_json(cleaned)
	var segments: Array = []
	var note := ""
	var replies: Array = []
	if data is Dictionary:
		segments = _segments_from(data, emotions)
		note = str(data.get("memory_note", "")).strip_edges()
		replies = QuickReplies.clean(data.get("replies", data.get("suggested_replies", [])))
	elif data is Array:
		segments = _segments_from({"segments": data}, emotions)
	if segments.is_empty():
		var text := cleaned
		if data != null:
			text = ""  # parsed JSON but nothing usable; don't show braces to the player
		text = text.strip_edges()
		if text == "":
			text = "..."
		segments = [{"emotion": match_emotion("neutral", emotions), "text": text}]
	if note.length() > MAX_NOTE_LEN:
		note = note.substr(0, MAX_NOTE_LEN).strip_edges() + "…"
	if note.to_lower() in ["none", "n/a", "null", "empty", "-"]:
		note = ""
	return {"segments": segments, "memory_note": note, "replies": replies}


## Removes reasoning tags and ``` fences some models wrap around JSON.
static func _strip_noise(raw: String) -> String:
	var s := raw.strip_edges()
	var think_end := s.rfind("</think>")
	if think_end != -1:
		s = s.substr(think_end + 8).strip_edges()
	if s.begins_with("```"):
		var first_nl := s.find("\n")
		s = s.substr(first_nl + 1) if first_nl != -1 else s.trim_prefix("```")
		s = s.trim_suffix("```").strip_edges()
	return s


## Finds the outermost {...} or [...] and parses it; null if none parses.
static func _find_json(s: String) -> Variant:
	var direct: Variant = JsonUtil.parse(s) if s.begins_with("{") or s.begins_with("[") else null
	if direct != null:
		return direct
	var start := s.find("{")
	var end := s.rfind("}")
	if start != -1 and end > start:
		var inner: Variant = JsonUtil.parse(s.substr(start, end - start + 1))
		if inner != null:
			return inner
	return null


static func _segments_from(data: Dictionary, emotions: PackedStringArray) -> Array:
	var raw_segments: Array = []
	if data.get("segments") is Array:
		raw_segments = data["segments"]
	elif data.has("text") or data.has("reply") or data.has("message"):
		raw_segments = [data]
	var out: Array = []
	for seg in raw_segments:
		var text := ""
		var emotion := "neutral"
		if seg is Dictionary:
			text = str(seg.get("text", seg.get("reply", seg.get("message", ""))))
			emotion = str(seg.get("emotion", seg.get("expression", "neutral")))
		elif seg is String:
			text = seg
		text = text.strip_edges()
		if text == "":
			continue
		out.append({"emotion": match_emotion(emotion, emotions), "text": text})
	# Merge overflow into the last allowed segment instead of dropping words.
	while out.size() > MAX_SEGMENTS:
		var extra: Dictionary = out.pop_back()
		out[out.size() - 1]["text"] += " " + str(extra["text"])
	return out


## unknown emotion -> exact/synonym/closest name -> "neutral" -> first available.
static func match_emotion(name: String, emotions: PackedStringArray) -> String:
	var n := name.to_lower().strip_edges()
	if n in emotions:
		return n
	var syn := str(SYNONYMS.get(n, ""))
	if syn != "" and syn in emotions:
		return syn
	var best := ""
	var best_score := 0.0
	for e in emotions:
		var score := n.similarity(e)
		if e.begins_with(n) or n.begins_with(e):
			score += 0.3
		if score > best_score:
			best_score = score
			best = e
	if best_score >= 0.55:
		return best
	if "neutral" in emotions or emotions.is_empty():
		return "neutral"
	return emotions[0]


## Joins segments into one plain string (for logs and history).
static func joined_text(segments: Array) -> String:
	var parts: PackedStringArray = []
	for s in segments:
		parts.append(str(s.get("text", "")))
	return " ".join(parts)
