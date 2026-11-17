extends RefCounted
## Two residents in the same room have a tiny chat: one walks over, they
## trade a line each in speech bubbles, and both lines go into the logs.
## Uses the AI only when there's spare rate-limit budget; otherwise Mock.

const ReplyParser := preload("res://scripts/ai/reply_parser.gd")
const MockBrain := preload("res://scripts/ai/mock_brain.gd")
const MoodSim := preload("res://scripts/characters/mood_sim.gd")
const PromptBuilder := preload("res://scripts/ai/prompt_builder.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Bonds := preload("res://scripts/characters/bonds.gd")
const Voices := preload("res://scripts/ai/voices.gd")

const REPLIES := ["Hehe, maybe!", "Right?? Totally.", "Mmhm. Same, honestly.", "Ooh, tell me more later.",
	"You always notice the best things.", "Pfft. You're ridiculous. I love it.", "That's very you.", "Wait, really?"]

var director: Node
var mock := MockBrain.new()


func _init(d: Node) -> void:
	director = d


func try_start() -> void:
	var w: Node = director.world
	var ids: Array = w.actors.keys().filter(func(i): return not director.busy.has(i) and i != w.talk.talking_to)
	if ids.size() < 2:
		return
	ids.shuffle()
	await chat(ids[0], ids[1])


func chat(a_id: String, b_id: String) -> void:
	var w: Node = director.world
	director.busy[a_id] = true
	director.busy[b_id] = true
	var ok: bool = await director.approach(a_id, w.actors[b_id].cell(), 2.0)
	if ok and w.actors.has(a_id) and w.actors.has(b_id) and not w.talk.is_open():
		var a := GameState.get_character(a_id)
		var b := GameState.get_character(b_id)
		var lines := await _lines(a, b)
		_say(a_id, b_id, lines[0])
		await w.get_tree().create_timer(4.2).timeout
		if w.actors.has(b_id):
			_say(b_id, a_id, lines[1])
		MoodSim.company(a, 0.05)
		MoodSim.company(b, 0.05)
		Bonds.add(a_id, b_id, 3.0)
		SaveManager.save_character(a)
		SaveManager.save_character(b)
	director.busy.erase(a_id)
	director.busy.erase(b_id)


func _say(id: String, to: String, seg: Dictionary) -> void:
	var w: Node = director.world
	if not w.actors.has(id):
		return
	w.actors[id].say(str(seg.text), 4.5)
	w.set_actor_emotion(id, str(seg.emotion), 4.5)
	ChatLog.append(id, GameState.current_room_id, "ai", str(seg.text), str(seg.emotion), {"kind": "npc_chat", "with": to})


## Two segments [{emotion, text}] - from the AI if budget allows, else Mock.
func _lines(a: Dictionary, b: Dictionary) -> Array:
	var a_emo := GameState.expression_names(a)
	var b_emo := GameState.expression_names(b)
	var allowed := bool(GameState.settings.get("ai", {}).get("npc_chatter", true))
	var spare: int = AIClient.spare_capacity()
	if allowed and not AIClient.is_mock() and not AIClient.busy() and spare >= maxi(3, int(AIClient.limiter.per_minute / 2.0)):
		var r: Dictionary = await AIClient.chat(_prompt(a, b), {"max_tokens": 220})
		if r.get("ok", false):
			var parsed := _parse(str(r.text), a_emo, b_emo)
			if parsed.size() == 2:
				return parsed
	var first := ReplyParser.parse(mock.respond({"mode": "npc", "other_name": b.get("name", ""), "character": a, "emotions": a_emo}), a_emo).segments[0] as Dictionary
	var replies: Array = Voices.lines(Voices.of(b), "reply")
	return [first, {"emotion": ReplyParser.match_emotion(["happy", "neutral", "thinking"].pick_random(), b_emo), "text": str(replies.pick_random() if not replies.is_empty() else REPLIES.pick_random())}]


func _prompt(a: Dictionary, b: Dictionary) -> Array:
	var world_name := str(GameState.world.get("name", "this world"))
	var setting := str(GameState.world.get("world_bible", {}).get("setting", "")).substr(0, 300)
	var room := str(director.world.room.data.get("name", "home"))
	var sys := "Write a tiny, cozy exchange between two residents of %s. %s\nA = %s: %s Speech: %s\nB = %s: %s Speech: %s\nThey are %s. They are in %s, %s. Line 1 is A talking to B, line 2 is B answering. Each line max 20 words, specific and in character. Reply ONLY JSON: {\"lines\":[{\"speaker\":\"A\",\"emotion\":\"happy\",\"text\":\"...\"},{\"speaker\":\"B\",\"emotion\":\"happy\",\"text\":\"...\"}]}" % [
		world_name, setting, a.get("name", ""), str(a.get("personality", "")).substr(0, 200), a.get("speech_style", ""),
		b.get("name", ""), str(b.get("personality", "")).substr(0, 200), b.get("speech_style", ""),
		Bonds.label(Bonds.value(str(a.get("id", "")), str(b.get("id", "")))), room, PromptBuilder.time_label()]
	return [{"role": "system", "content": sys}, {"role": "user", "content": "Write the two lines."}]


func _parse(raw: String, a_emo: PackedStringArray, b_emo: PackedStringArray) -> Array:
	var data: Variant = JsonUtil.parse(raw.substr(maxi(0, raw.find("{")), raw.rfind("}") - maxi(0, raw.find("{")) + 1))
	if not data is Dictionary or not data.get("lines") is Array or data.lines.size() < 2:
		return []
	var out: Array = []
	for i in 2:
		var l: Variant = data.lines[i]
		if not l is Dictionary or str(l.get("text", "")).strip_edges() == "":
			return []
		out.append({"emotion": ReplyParser.match_emotion(str(l.get("emotion", "neutral")), a_emo if i == 0 else b_emo), "text": str(l.text).strip_edges().substr(0, 160)})
	return out
