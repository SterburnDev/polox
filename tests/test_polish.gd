extends "res://tests/test_case.gd"
## Phase 12: quick-reply chips (from the AI's JSON, canned offline), the
## "Where was I?" card and resuming in the last room, the autosave
## indicator, "New in Polox" for returning players, and picking a look
## during onboarding.

const ReplyParser := preload("res://scripts/ai/reply_parser.gd")
const PromptBuilder := preload("res://scripts/ai/prompt_builder.gd")
const QuickReplies := preload("res://scripts/ai/quick_replies.gd")
const Conversation := preload("res://scripts/ai/conversation.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const RecapCard := preload("res://scripts/ui/recap_card.gd")
const WhatsNew := preload("res://scripts/ui/whats_new_panel.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const Doll := preload("res://scripts/characters/doll.gd")

var main: Node


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _shutdown() -> void:
	main.queue_free()
	await frames(2)


func test_replies_parsed_cleaned_and_asked_for() -> void:
	var r := ReplyParser.parse('{"segments":[{"emotion":"happy","text":"Yay!"}],"memory_note":"","replies":["Tell me more", "tell me more", "", 5, "%s", "Bye!", "Extra one"]}' % "x".repeat(80), PackedStringArray(["neutral", "happy"]))
	eq(r.replies, ["Tell me more", "Bye!", "Extra one"], "strings only, short, no duplicates, max 3")
	eq(ReplyParser.parse("just text", PackedStringArray(["neutral"])).replies, [], "plain text: none")
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	var ctx := Conversation.new().base_context(GameState.get_character(id))
	ctx["user_text"] = "hi"
	check(str(PromptBuilder.build_messages(ctx)[0].content).contains("\"replies\""), "the AI is asked for up to 3 replies")
	GameState.settings["quick_replies"] = false
	ctx = Conversation.new().base_context(GameState.get_character(id))
	ctx["user_text"] = "hi"
	check(not str(PromptBuilder.build_messages(ctx)[0].content).contains("\"replies\""), "not when they're switched off")
	GameState.settings["quick_replies"] = true
	# Mock / offline: a canned set that fits.
	AIClient.configure({"preset": "mock"})
	var reply: Dictionary = await Conversation.new().player_says(id, "I had a rough day")
	eq((reply.replies as Array).size(), 3, "three chips offline too")
	check(reply.replies in QuickReplies.CANNED.sad, "sad things get gentle replies")
	eq(QuickReplies.kind_for("what do you think?"), "question")
	eq(QuickReplies.kind_for("bye!"), "bye")


func test_chips_in_the_chat_box() -> void:
	var g: Node = await _boot()
	var id: String = g.actors.keys()[0]
	g.talk.talk_to(id)
	await frames(1)
	check(g.dialogue.chips.get_child_count() > 0, "greeting chips")
	for i in 8:
		if g.dialogue.state == "input":
			break
		g.dialogue.advance()
	check(g.dialogue.chips.visible, "chips show when it's your turn")
	var first: Button = g.dialogue.chips.get_child(0)
	var chip_text := first.text
	var said := [""]
	g.dialogue.sent.connect(func(t): said[0] = t)
	first.pressed.emit()
	eq(said[0], chip_text, "a tap says it")
	check(not g.dialogue.chips.visible, "chips hide while waiting")
	await frames(2)
	var last: Dictionary = ChatLog.read_all(id).filter(func(e): return e.role == "user").back()
	eq(str(last.text), chip_text, "and it's in the log")
	g.dialogue.close_box()
	await _shutdown()


func test_where_was_i_and_resume_in_the_last_room() -> void:
	var g: Node = await _boot()
	var id: String = g.actors.keys()[0]
	GameState.add_dream("Learn to bake bread")
	await Conversation.new().player_says(id, "I painted all day")
	g.go_to_room("garden")
	await frames(30)
	while g._transitioning:
		await frames(1)
	eq(str(GameState.world.last_room), "garden")
	# Restart the game: it opens in the garden, and the card says where you were.
	main.queue_free()
	await frames(2)
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.start_game()
	await frames(2)
	eq(GameState.current_room_id, "garden", "picked up where you left off")
	var r := RecapCard.build_recap("2026-01-01T10:00:00")
	var text := str(r.lines)
	check(text.contains("Garden"), "where you were: " + text)
	check(text.contains("Last chat with") and text.contains("just now"), "the last chat and when: " + text)
	check(text.contains("Learn to bake bread"), "a dream to cheer on")
	check(RecapCard.build_recap("").is_empty(), "nothing for a world you've never played")
	var card: Control = main.show_recap("2026-01-01T10:00:00")
	check(card != null and card.is_inside_tree(), "the card shows")
	card._t = RecapCard.SHOW_SECONDS + 2.0
	card._process(0.0)
	await frames(1)
	check(not is_instance_valid(card), "and goes away by itself")
	await _shutdown()


func test_autosave_indicator_and_whats_new() -> void:
	var g: Node = await _boot()
	g.hud._save_shown = -10.0
	GameState.save_world()
	eq(g.hud.save_label.text, "✓ Saved", "the save indicator says so")
	main.autosave.snapshot("auto")
	check(g.hud.save_label.text.to_lower().contains("snapshot"), "snapshots too")
	# A returning player sees "New in Polox" once.
	GameState.settings["onboarded"] = true
	GameState.settings["whats_new_seen"] = ""
	check(WhatsNew.should_show())
	var wn: Control = WhatsNew.new()
	wn.main = main
	main.open_panel(wn)
	await frames(1)
	check(not WhatsNew.should_show(), "only once")
	wn.close()
	await _shutdown()


func test_onboarding_look_choice() -> void:
	fresh_save_root()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	var id: String = main.create_world_from({"world_name": "Look", "player_name": "Sam", "look": "mage", "friend_name": "Pip"})
	GameState.load_world()
	eq(PlayerLook.form_data("real").doll, Doll.preset("mage"), "the chosen look is Real Me")
	eq(PlayerLook.form_data("dark").doll, Doll.preset("night"), "Dream World Me is waiting too")
	check(id != "")
	await _shutdown()
