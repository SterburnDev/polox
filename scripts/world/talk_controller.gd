extends Node
## Tags: [AI_HELPER]
const Encounters := preload("res://scripts/battle/encounters.gd")
## Runs conversations for the game world: opens the dialogue box for a
## character or sign, sends the player's lines through Conversation, and
## swaps the character's world sprite along with the portrait.

const Conversation := preload("res://scripts/ai/conversation.gd")
const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const ReplyParser := preload("res://scripts/ai/reply_parser.gd")
const InventoryPanel := preload("res://scripts/ui/inventory_panel.gd")
const GiftRules := preload("res://scripts/items/gift_rules.gd")
const Items := preload("res://scripts/items/items.gd")
const ItemEffects := preload("res://scripts/items/item_effects.gd")
const Voice := preload("res://scripts/characters/voice.gd")
const Feelings := preload("res://scripts/characters/feelings.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const QuickReplies := preload("res://scripts/ai/quick_replies.gd")

var world: Node              # game_world.gd
var dialogue: Control        # dialogue_box.gd
var convo := Conversation.new()
var talking_to := ""
var _last_exchange: Array = []  # [player text, reply text] for "Save moment"
var _fallback_tex: Texture2D


func setup(game_world: Node, box: Control) -> void:
	world = game_world
	dialogue = box
	dialogue.sent.connect(_on_sent)
	dialogue.closed.connect(_on_closed)
	dialogue.save_moment.connect(_on_save_moment)
	dialogue.segment_started.connect(_on_segment)
	dialogue.gift_pressed.connect(_on_gift_pressed)
	dialogue.live_pressed.connect(_on_live_pressed)


func is_open() -> bool:
	return dialogue.visible


## emotion -> Texture2D for every expression the character has.
func textures_for(c: Dictionary) -> Dictionary:
	var out := {}
	for e in c.get("expressions", {}):
		var tex := SaveManager.load_texture(SaveManager.expression_path(c, str(e)))
		if tex:
			out[str(e)] = tex
	if not out.has("neutral"):
		out["neutral"] = out.values()[0] if not out.is_empty() else _placeholder()
	return out


func _placeholder() -> Texture2D:
	if _fallback_tex == null:
		_fallback_tex = ImageTexture.create_from_image(SpriteFactory.blob("neutral", Color("#9a94b0")))
	return _fallback_tex


func talk_to(id: String) -> void:
	var c := GameState.get_character(id)
	if c.is_empty():
		return
	talking_to = id
	_last_exchange = []
	_prepare_player_side()
	dialogue.open(str(c.get("name", "")), textures_for(c), Voice.of_character(c))
	var segs := convo.greeting(c)
	ChatLog.append(id, GameState.current_room_id, "ai", ReplyParser.joined_text(segs), str(segs[0].emotion), {"kind": "greeting"})
	dialogue.set_replies(QuickReplies.canned("greeting") if QuickReplies.enabled() else [])
	dialogue.show_segments(segs)
	world.on_talk_started(id)


## Your faces and voice for your own lines in the box.
func _prepare_player_side() -> void:
	dialogue.player_textures = PlayerLook.textures()
	dialogue.player_voice = Voice.of_player()


## Signs, props and doors: read-only text in the same box.
func show_text(title: String, text: String) -> void:
	talking_to = ""
	world.hud.visible = false
	_prepare_player_side()
	dialogue.open(title, {}, {"sound": "blip", "pitch": 0.8, "speed": 1.0}, false)
	dialogue.show_segments([{"emotion": "neutral", "text": text}])


func _on_sent(text: String) -> void:
	var id := talking_to
	if id == "":
		return
	dialogue.set_thinking()
	world.set_actor_emotion(id, "thinking")
	world.set_player_emotion(Feelings.guess(text), 3.0)
	load("res://scripts/variety/story.gd").bump("chats")
	var reply: Dictionary = await convo.player_says(id, text)
	_last_exchange = [text, ReplyParser.joined_text(reply.get("segments", []))]
	if reply.get("failed", false) and str(reply.get("error", "")) != "":
		GameState.notify(str(reply.error))
	if talking_to != id or not dialogue.visible:
		return  # player left mid-reply; it's still in the log
	dialogue.set_replies(reply.get("replies", []))
	dialogue.show_segments(reply.get("segments", []))
	world.on_reply(id, reply)
	if Encounters.asks_to_fight(text) and world.get("battles"):
		world.battles.chat_asked(id)   # "I want to fight": offer a friendly battle with them


func _on_gift_pressed() -> void:
	var c := GameState.get_character(talking_to)
	if c.is_empty():
		return
	if not GiftRules.can_gift(c):
		var line := "That's so many presents today! Save the next one for tomorrow~"
		ChatLog.append(talking_to, GameState.current_room_id, "ai", line, "happy", {"kind": "event"})
		dialogue.show_segments([{"emotion": "happy", "text": line}])
		return
	var bag := InventoryPanel.new()
	bag.world = world
	bag.gift_for = talking_to
	bag.gift_chosen.connect(give_gift)
	world.main.open_panel(bag)


func _on_live_pressed() -> void:
	if talking_to == "":
		return
	var c := GameState.get_character(talking_to)
	if c.is_empty():
		return
	var panel: Control = load("res://scripts/ui/live_convo_panel.gd").new()
	panel.setup_session(self, talking_to, str(c.get("name", "Friend")))
	world.main.open_panel(panel)


func live_exchange(player_text: String) -> Dictionary:
	var id := talking_to
	if id == "":
		return {"text": "", "emotion": "neutral"}
	var reply: Dictionary = await convo.player_says(id, player_text)
	var segs: Array = reply.get("segments", [])
	var emo := str((segs[0] as Dictionary).get("emotion", "neutral")) if not segs.is_empty() and segs[0] is Dictionary else "neutral"
	var text := ReplyParser.joined_text(segs)
	if reply.get("failed", false) and str(reply.get("error", "")) != "" and text == "":
		text = str(reply.get("error", ""))
	return {"text": text, "emotion": emo}


## Gives an item from the bag to whoever you're talking to.
func give_gift(item_id: String) -> void:
	var id := talking_to
	var item := Items.load_item(item_id)
	if id == "" or item.is_empty():
		return
	dialogue.show_player_line("*gives %s*" % item.name, "happy")
	world.set_player_emotion("happy", 3.0)
	dialogue.set_thinking()
	var reply: Dictionary = await convo.give_item(id, item_id)
	if reply.is_empty() or talking_to != id or not dialogue.visible:
		return
	var how := str(reply.get("reaction", "nice"))
	if world.actors.has(id):
		world.actors[id].emote("♥" if how in ["love", "like"] else "!", Color("#ff8fab"))
	ItemEffects.play(world, item, "gift")
	var c := GameState.get_character(id)
	GameState.notify("%s %s ♥ happiness %d%% → %d%%, closeness +%.1f" % [c.get("name", ""), GiftRules.HOW_WORDS.get(how, "kept"),
		roundi(float(reply.get("mood_before", 0)) * 100.0), roundi(float(reply.get("mood_after", 0)) * 100.0), float(reply.get("affinity_gain", 0))])
	dialogue.set_replies(reply.get("replies", []))
	dialogue.show_segments(reply.get("segments", []))


func _on_segment(emotion: String) -> void:
	if talking_to != "":
		world.set_actor_emotion(talking_to, emotion)


func _on_closed() -> void:
	var id := talking_to
	talking_to = ""
	if id != "":
		world.on_talk_ended(id)
	else:
		world.hud.visible = true


func _on_save_moment() -> void:
	var c := GameState.get_character(talking_to)
	var text := ""
	if _last_exchange.size() == 2:
		text = "You: %s\n%s: %s" % [_last_exchange[0], c.get("name", ""), _last_exchange[1]]
	else:
		text = "A quiet moment with %s." % c.get("name", "")
	GameState.add_moment("A moment with %s" % c.get("name", ""), text, talking_to, "manual")
	GameState.notify("★ Saved to your Memory Book")
