extends "res://tests/test_case.gd"
## 1.27: friends brought over from Character.AI, Chai or another app (character cards, PNG cards,
## pasted text), long-term recall of earlier moments, chat backups that merge back without doubling,
## and a friend's own AI model. Made-up characters only.

const CharacterImport := preload("res://scripts/ai/character_import.gd")
const MemoryRecall := preload("res://scripts/ai/memory_recall.gd")
const ChatBackup := preload("res://scripts/ai/chat_backup.gd")
const PromptBuilder := preload("res://scripts/ai/prompt_builder.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")

const CARD_V2 := {"spec": "chara_card_v2", "spec_version": "2.0", "data": {
	"name": "Ava", "description": "{{char}} runs a tiny bakery and worries about {{user}}'s sleep.",
	"personality": "warm, teasing, bakes when nervous", "scenario": "A rainy bakery after closing.",
	"first_mes": "*dusts flour off her hands* Oh! {{user}}, you came back!", "mes_example": "<START>\n{{user}}: hi\n{{char}}: Hiii! Cookie?",
	"creator": "someone", "tags": ["cozy", "baker"], "system_prompt": "Keep it gentle."}}


func _world() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	StarterContent.create_world("Memory World", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	check(not GameState.characters.is_empty(), "(a friend to talk with)")


func test_cards_and_text_become_friends() -> void:
	var v2 := CharacterImport.from_text(JSON.stringify(CARD_V2), "Character.AI")
	check(v2.ok, str(v2.get("error", "")))
	eq(v2.card.name, "Ava")
	check(str(v2.card.personality).contains("bakes when nervous"), "personality from the card")
	check(str(v2.card.backstory).contains("tiny bakery") and str(v2.card.backstory).contains("rainy bakery"), "description and scenario kept as backstory")
	check(str(v2.card.greeting).begins_with("*dusts flour"), "their greeting")
	var v1 := CharacterImport.from_text(JSON.stringify({"name": "Old", "description": "an old flat card", "first_mes": "hey"}))
	check(v1.ok and v1.card.name == "Old" and str(v1.card.personality) == "an old flat card", "the older flat card format")
	var pasted := CharacterImport.from_text("Name: Kiko\nGreeting: yo!\nDescription: a sleepy fox who loves noodles\nand long walks", "Chai")
	check(pasted.ok and pasted.card.name == "Kiko", str(pasted))
	check(str(pasted.card.personality).contains("noodles") and str(pasted.card.personality).contains("long walks"), "a line without a label continues the one before")
	var plain := CharacterImport.from_text("A shy robot who collects bottle caps.")
	check(plain.ok and str(plain.card.name) == "", "plain text works, the name comes from the player")
	check(not CharacterImport.from_text("").ok and not CharacterImport.from_text("{broken").ok, "empty or broken input says so")
	var long := CharacterImport.from_text(JSON.stringify({"name": "Big", "description": "x".repeat(20000)}))
	check(str(long.card.personality).length() <= CharacterImport.MAX_FIELD + 1, "long cards are kept to a size a small model can carry")


func test_a_png_card_brings_its_picture() -> void:
	_world()
	var img := Image.create(40, 60, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.5, 0.6))
	var png := _with_text_chunk(img.save_png_to_buffer(), "chara", Marshalls.utf8_to_base64(JSON.stringify(CARD_V2)))
	eq(CharacterImport.png_card_text(png).left(1), "{", "the card is found inside the picture")
	var path := SaveManager.global_path("ava_card.png")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(png)
	f.close()
	var r := CharacterImport.from_file(path)
	check(r.ok and r.card.name == "Ava" and r.card.has("picture"), str(r.get("error", "")))
	var id := CharacterImport.create_friend(r.card)
	check(id != "", "the friend was made")
	var c := GameState.get_character(id)
	eq(str(c.name), "Ava")
	check(str(c.greeting).contains("Sam"), "{{user}} became the player's name: " + str(c.greeting))
	check(not str(c.backstory).contains("{{char}}"), "{{char}} became her name")
	var pic := Image.load_from_file(SaveManager.expression_path(c, "neutral"))
	check(pic != null and pic.get_width() == 40, "her picture is her look")
	eq(c.expressions.happy, c.expressions.neutral, "one picture for every feeling")
	var plain := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var p2 := SaveManager.global_path("no_card.png")
	plain.save_png(p2)
	var none := CharacterImport.from_file(p2)
	check(not none.ok and bool(none.get("picture_only", false)), "a picture with no card inside says so")


func test_an_imported_friend_talks_like_their_card() -> void:
	_world()
	var card: Dictionary = CharacterImport.from_text(JSON.stringify(CARD_V2), "Character.AI").card
	var id := CharacterImport.create_friend(card)
	var c := GameState.get_character(id)
	var greet: Array = load("res://scripts/ai/conversation.gd").new().greeting(c)
	check(str(greet[0].text).begins_with("*dusts flour"), "the first hello is their own greeting")
	var ctx := {"character": c, "world": GameState.world, "player_name": "Sam", "emotions": PackedStringArray(["neutral", "happy"])}
	var system := PromptBuilder.system_prompt(ctx)
	check(system.contains("How you talk") and system.contains("Cookie?"), "their example lines are in the prompt")
	check(system.contains("Keep it gentle."), "their card's own notes too")


func test_earlier_moments_come_back_to_mind() -> void:
	var entries: Array = []
	var day := 1
	for line in ["My cat Biscuit has a cold", "I painted the kitchen blue", "Work was long today", "The bus was late again"]:
		entries.append({"role": "user", "text": line, "ts": "2026-10-%02dT10:00:00" % day})
		entries.append({"role": "ai", "text": "Oh! Tell me more about that.", "ts": "2026-10-%02dT10:00:05" % day})
		day += 1
	for i in 30:   # lots of recent small talk that is already in the prompt
		entries.append({"role": "user", "text": "hello %d" % i, "ts": "2026-10-20T10:%02d:00" % (i % 60)})
		entries.append({"role": "ai", "text": "hi!", "ts": "2026-10-20T10:%02d:05" % (i % 60)})
	var got := MemoryRecall.recall(entries, "Biscuit is better now, the vet said", 12, 3, "Sam")
	check(not got.is_empty() and got[0].contains("Biscuit") and got[0].contains("Oct 1"), "the moment about Biscuit comes back, with its date: " + str(got))
	check(got.size() <= 3)
	check(MemoryRecall.recall(entries, "hello", 12, 3).is_empty() or not MemoryRecall.recall(entries, "zzz qqq", 12, 3).size(), "nothing in common: nothing recalled")
	var short_log := entries.slice(0, 6)
	check(MemoryRecall.recall(short_log, "Biscuit", 12, 3).is_empty(), "everything is still in the recent messages: nothing extra")


func test_chat_backups_merge_back_without_doubling() -> void:
	_world()
	var id := str(GameState.characters.keys()[0])
	ChatLog.append(id, "home", "user", "I adopted a turtle named Sprout")
	ChatLog.append(id, "home", "ai", "A turtle! I love Sprout already.")
	var c := GameState.get_character(id)
	c["memory_notes"] = ["Has a turtle named Sprout"]
	GameState.save_character(c)
	var path := ChatBackup.backup("manual")
	check(path != "" and FileAccess.file_exists(path), "a backup was made")
	var m := ChatBackup.manifest(path)
	eq((m.friends as Array).size(), GameState.characters.size(), "every friend is in it")
	# The chats are lost here (a new phone, a mistake), and a newer message arrives.
	DirAccess.remove_absolute(ChatLog.log_path(id))
	ChatLog.append(id, "home", "user", "New day, new me")
	c = GameState.get_character(id)
	c["memory_notes"] = []
	GameState.save_character(c)
	var r := ChatBackup.restore(path)
	check(r.ok, str(r.get("error", "")))
	eq(int(r.added), 2, "the two lost messages came back")
	var texts: Array = ChatLog.read_all(id).map(func(e): return str(e.text))
	eq(texts, ["I adopted a turtle named Sprout", "A turtle! I love Sprout already.", "New day, new me"], "in time order, nothing lost")
	check(GameState.get_character(id).memory_notes.has("Has a turtle named Sprout"), "the memory came back too")
	var again := ChatBackup.restore(path)
	eq(int(again.added), 0, "restoring twice doubles nothing")
	check(ChatBackup.list_backups().any(func(b): return str(b.kind) == "before"), "a backup of the present was made before restoring")
	var bogus := SaveManager.global_path("not_a_backup.zip")
	var zip := ZIPPacker.new()
	zip.open(bogus)
	zip.start_file("hello.txt")
	zip.write_file("hi".to_utf8_buffer())
	zip.close_file()
	zip.close()
	check(not ChatBackup.restore(bogus).ok, "something that isn't a chat backup is refused")


func test_daily_backups_are_kept_to_a_few() -> void:
	_world()
	var id := str(GameState.characters.keys()[0])
	ChatLog.append(id, "home", "user", "hi")
	check(ChatBackup.auto_backup_if_due() != "", "the first automatic backup")
	eq(ChatBackup.auto_backup_if_due(), "", "not again the same day")
	for i in ChatBackup.MAX_AUTO + 3:
		ChatBackup.backup("auto")
	var autos := ChatBackup.list_backups().filter(func(b): return str(b.kind) == "auto")
	eq(autos.size(), ChatBackup.MAX_AUTO, "only the newest automatic backups are kept")


func test_a_friend_can_have_their_own_model() -> void:
	_world()
	var id := str(GameState.characters.keys()[0])
	var c := GameState.get_character(id)
	c["ai_model"] = "freehuntx/Assistant_Pepe:8b"
	GameState.save_character(c)
	var seen: Array = []
	var stub: Node = preload("res://scripts/phone/http_server.gd").new()
	tree.root.add_child(stub)
	stub.api_prefix = "/v1/"
	stub.api_handler = func(req: Dictionary, _ip: String) -> PackedByteArray:
		seen.append(JSON.parse_string((req.body as PackedByteArray).get_string_from_utf8()))
		return preload("res://scripts/phone/http_util.gd").json_response(200, {"choices": [{"message": {"content": "{\"segments\":[{\"emotion\":\"happy\",\"text\":\"Hi!\"}],\"memory_note\":\"\"}"}}]})
	listen_on_free_port(func(p: int) -> String: return stub.start(p, "127.0.0.1"), "the fake AI")
	AIClient.configure({"preset": "custom", "base_url": "http://127.0.0.1:%d/v1" % stub.port, "model": "everyone", "timeout_s": 5})
	await load("res://scripts/ai/conversation.gd").new().player_says(id, "hello!")
	eq(str(seen.back().model), "freehuntx/Assistant_Pepe:8b", "this friend talks through their own model")
	AIClient.configure({"preset": "mock"})
	stub.stop()
	stub.queue_free()
	await frames(2)


# A PNG text chunk with a proper CRC (PNG readers check it).
func _with_text_chunk(png: PackedByteArray, key: String, value: String) -> PackedByteArray:
	var data := key.to_ascii_buffer()
	data.append(0)
	data.append_array(value.to_ascii_buffer())
	var kind := "tEXt".to_ascii_buffer()
	var chunk := PackedByteArray()
	for shift in [24, 16, 8, 0]:
		chunk.append((data.size() >> shift) & 0xFF)
	chunk.append_array(kind)
	chunk.append_array(data)
	var crc := _crc32(kind + data)
	for shift in [24, 16, 8, 0]:
		chunk.append((crc >> shift) & 0xFF)
	var iend := png.size() - 12
	var out := png.slice(0, iend)
	out.append_array(chunk)
	out.append_array(png.slice(iend))
	return out


func _crc32(bytes: PackedByteArray) -> int:
	var crc := 0xFFFFFFFF
	for b in bytes:
		crc ^= b
		for i in 8:
			crc = (crc >> 1) ^ (0xEDB88320 if crc & 1 else 0)
	return crc ^ 0xFFFFFFFF
