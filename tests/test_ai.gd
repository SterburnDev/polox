extends "res://tests/test_case.gd"
## AI layer: reply parsing/validation, emotion fallback, Mock brain, rate
## limiter, prompt budget, HTTP error mapping and offline fallback.

const ReplyParser := preload("res://scripts/ai/reply_parser.gd")
const MockBrain := preload("res://scripts/ai/mock_brain.gd")
const RateLimiter := preload("res://scripts/ai/rate_limiter.gd")
const PromptBuilder := preload("res://scripts/ai/prompt_builder.gd")
const Presets := preload("res://scripts/ai/presets.gd")
const Crisis := preload("res://scripts/ai/crisis.gd")
const Conversation := preload("res://scripts/ai/conversation.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")

const EMO := ["neutral", "happy", "sad", "angry", "surprised", "embarrassed", "thinking", "sleepy"]


func test_parse_valid_json() -> void:
	var r := ReplyParser.parse('{"segments":[{"emotion":"happy","text":"Hi!"},{"emotion":"sad","text":"But..."}],"memory_note":"Likes tea"}', EMO)
	eq(r.segments.size(), 2)
	eq(r.segments[0].emotion, "happy")
	eq(r.segments[1].text, "But...")
	eq(r.memory_note, "Likes tea")


func test_parse_code_fence_and_think_tags() -> void:
	var r := ReplyParser.parse('<think>hmm, be nice</think>\n```json\n{"segments":[{"emotion":"thinking","text":"Let me see."}],"memory_note":""}\n```', EMO)
	eq(r.segments.size(), 1)
	eq(r.segments[0].emotion, "thinking")
	eq(r.segments[0].text, "Let me see.")


func test_parse_json_embedded_in_prose() -> void:
	var r := ReplyParser.parse('Sure! Here you go: {"segments":[{"emotion":"happy","text":"Yay"}]} hope that helps', EMO)
	eq(r.segments[0].text, "Yay")
	eq(r.memory_note, "")


func test_parse_plain_text_becomes_neutral() -> void:
	var r := ReplyParser.parse("Just some words, no JSON at all.", EMO)
	eq(r.segments.size(), 1)
	eq(r.segments[0].emotion, "neutral")
	eq(r.segments[0].text, "Just some words, no JSON at all.")


func test_parse_garbage_never_crashes() -> void:
	for raw in ["", "{", "}{", "[]", "null", "{\"segments\": 5}", "{\"segments\":[{\"emotion\":3}]}", "{\"segments\":[\"just a string\"]}", "💥"]:
		var r := ReplyParser.parse(raw, EMO)
		check(r.segments.size() >= 1, "at least one segment for <%s>" % raw)
		check(str(r.segments[0].emotion) in EMO, "valid emotion for <%s>" % raw)
	eq(ReplyParser.parse('{"segments":["just a string"]}', EMO).segments[0].text, "just a string")


func test_parse_caps_segments_at_three() -> void:
	var r := ReplyParser.parse('{"segments":[{"emotion":"happy","text":"a"},{"emotion":"sad","text":"b"},{"emotion":"angry","text":"c"},{"emotion":"happy","text":"d"}]}', EMO)
	eq(r.segments.size(), 3)
	eq(r.segments[2].text, "c d", "overflow merged into the last segment")


func test_parse_single_object_form() -> void:
	var r := ReplyParser.parse('{"emotion":"surprised","text":"Whoa"}', EMO)
	eq(r.segments[0].emotion, "surprised")


func test_memory_note_cleanup() -> void:
	eq(ReplyParser.parse('{"segments":[{"emotion":"happy","text":"x"}],"memory_note":"none"}', EMO).memory_note, "")
	var long_note := "a".repeat(400)
	check(ReplyParser.parse('{"segments":[{"emotion":"happy","text":"x"}],"memory_note":"%s"}' % long_note, EMO).memory_note.length() <= 202, "long notes capped")


func test_emotion_fallback_chain() -> void:
	eq(ReplyParser.match_emotion("HAPPY", EMO), "happy", "case-insensitive")
	eq(ReplyParser.match_emotion("joyful", EMO), "happy", "synonym")
	eq(ReplyParser.match_emotion("surprise", EMO), "surprised", "synonym/near")
	eq(ReplyParser.match_emotion("embarassed", EMO), "embarrassed", "typo -> closest")
	eq(ReplyParser.match_emotion("sleepyy", EMO), "sleepy", "closest name")
	eq(ReplyParser.match_emotion("quantum", EMO), "neutral", "unknown -> neutral")
	eq(ReplyParser.match_emotion("happy", PackedStringArray(["neutral"])), "neutral", "missing expression -> neutral")
	eq(ReplyParser.match_emotion("weird", PackedStringArray(["smug", "grin"])), "smug", "no neutral -> first available")
	eq(ReplyParser.match_emotion("smug", PackedStringArray(["neutral", "smug"])), "smug", "custom expression")


func test_mock_brain_valid_and_varied() -> void:
	var brain := MockBrain.new(42)
	var seen := {}
	for i in 30:
		var raw := brain.respond({"mode": "chat", "character": {"name": "Mochi", "likes": "tea, rain"}, "user_text": "tell me something %d" % i, "emotions": PackedStringArray(EMO), "dreams": [{"text": "learn guitar", "status": "dreaming"}]})
		var r := ReplyParser.parse(raw, EMO)
		check(r.segments.size() >= 1 and r.segments.size() <= 3, "mock segment count")
		for s in r.segments:
			check(str(s.emotion) in EMO, "mock emotion valid")
			seen[str(s.text)] = true
	check(seen.size() >= 6, "mock replies vary (%d distinct)" % seen.size())


func test_mock_word_matching() -> void:
	var brain := MockBrain.new(1)
	var r := ReplyParser.parse(brain.respond({"mode": "chat", "character": {"name": "M"}, "user_text": "how are you?", "emotions": PackedStringArray(EMO)}), EMO)
	eq(r.segments[0].emotion, "thinking", "'you' is not the greeting 'yo'")


func test_mock_extracts_memory_notes() -> void:
	eq(MockBrain.extract_note("my favorite food is ramen."), "Favorite food is ramen")
	eq(MockBrain.extract_note("I love painting and cats"), "Loves painting and cats")
	eq(MockBrain.extract_note("ok"), "")


func test_crisis_detection_and_mock_care() -> void:
	check(Crisis.detect("sometimes I want to die"), "detects")
	check(Crisis.detect("I've been thinking about SUICIDE"), "case-insensitive")
	check(not Crisis.detect("this game is killer, I'm dying of laughter"), "no false alarm on idioms")
	var raw := MockBrain.new(3).respond({"mode": "chat", "character": {"name": "Mochi"}, "user_text": "I want to kill myself", "emotions": PackedStringArray(EMO)})
	var text := ReplyParser.joined_text(ReplyParser.parse(raw, EMO).segments).to_lower()
	check(text.find("crisis line") != -1 or text.find("988") != -1, "mock crisis reply points to help")


func test_rate_limiter() -> void:
	var rl := RateLimiter.new(3)
	for i in 3:
		eq(rl.wait_time(100.0), 0.0)
		rl.record(100.0 + i)
	check(rl.wait_time(103.0) > 0.0, "4th request waits")
	eq(rl.remaining(103.0), 0)
	eq(rl.wait_time(161.0), 0.0, "window slides")
	rl.block_for(10.0, 200.0)
	check(is_equal_approx(rl.wait_time(200.0), 10.0), "retry-after block respected")


func test_presets_resolve() -> void:
	var g := Presets.resolve({"preset": "groq", "api_key": "k"})
	eq(g.base_url, "https://api.groq.com/openai/v1")
	eq(g.model, "openai/gpt-oss-20b")
	eq(Presets.endpoint("https://generativelanguage.googleapis.com/v1beta/openai/"), "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
	eq(Presets.endpoint("http://localhost:11434/v1", "models"), "http://127.0.0.1:11434/v1/models", "localhost -> IPv4")
	var custom := Presets.resolve({"preset": "ollama", "model": "llama3.2:3b"})
	eq(custom.model, "llama3.2:3b", "user model wins over preset")


func test_mock_is_default_until_key() -> void:
	AIClient.configure({"preset": "groq", "api_key": ""})
	check(AIClient.is_mock(), "groq without key -> mock")
	AIClient.configure({"preset": "groq", "api_key": "FAKE-test-key"})
	check(not AIClient.is_mock(), "groq with key -> real")
	AIClient.configure({"preset": "ollama"})
	check(not AIClient.is_mock(), "ollama needs no key")
	AIClient.configure({"preset": "mock"})
	check(AIClient.is_mock())


func test_http_error_mapping() -> void:
	AIClient.configure({"preset": "groq", "api_key": "FAKE-test-secret-value"})
	var ok := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"choices":[{"message":{"content":"{\\"segments\\":[]}"}}]}'.to_utf8_buffer())
	check(ok.ok, "200 ok")
	var limited := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(["Retry-After: 7"]), PackedByteArray())
	check(not limited.ok and limited.retry, "429 retries")
	eq(limited.retry_after, 7.0, "Retry-After parsed")
	check(AIClient.limiter.wait_time(AIClient._now()) > 5.0, "limiter blocked after 429")
	AIClient.limiter.blocked_until = 0.0
	var denied := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), '{"error":{"message":"bad key FAKE-test-secret-value"}}'.to_utf8_buffer())
	check(not denied.ok and not denied.retry, "401 doesn't retry")
	check(str(denied.error).find("API key") != -1, "401 message is friendly")
	var bad := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 400, PackedStringArray(), '{"error":{"message":"oops FAKE-test-secret-value"}}'.to_utf8_buffer())
	check(str(bad.error).find("FAKE-test-secret-value") == -1, "key redacted from provider messages")
	var gemini := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 400, PackedStringArray(), '[{"error":{"code":400,"message":"Please pass a valid API key","status":"INVALID_ARGUMENT"}}]'.to_utf8_buffer())
	check(str(gemini.error).find("didn't accept the API key") != -1, "Gemini's 400 bad-key is friendly")
	var timeout := AIClient._interpret(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	check(timeout.retry and str(timeout.error).find("too long") != -1, "timeout retries, friendly")
	# A provider that refuses the network (Groq's real answer, whatever the key) isn't called a bad key.
	var blocked := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 403, PackedStringArray(), '{"error":{"message":"Access denied. Please check your network settings."}}'.to_utf8_buffer())
	check(not blocked.ok and not blocked.retry and str(blocked.error).contains("this network") and not str(blocked.error).contains("API key"), "a network refusal says so")
	var block_page := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 403, PackedStringArray(), "<!DOCTYPE html><title>Attention Required!</title>".to_utf8_buffer())
	check(str(block_page.error).contains("this network"), "a block page instead of JSON is a network refusal too")
	var broke := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(), '{"error":{"type":"insufficient_quota","code":"credit_balance_exhausted","message":"You have no credits remaining."}}'.to_utf8_buffer())
	check(not broke.retry and str(broke.error).contains("no credit left"), "an empty balance isn't retried or called a rate limit")
	var google_limit := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(), '[{"error":{"code":429,"message":"You exceeded your current quota, please check your plan and billing details.","status":"RESOURCE_EXHAUSTED"}}]'.to_utf8_buffer())
	check(google_limit.retry, "Gemini's per-minute limit (which also says quota and billing) is still waited out")
	AIClient.limiter.blocked_until = 0.0
	var no_permission := AIClient._interpret(HTTPRequest.RESULT_SUCCESS, 403, PackedStringArray(), '{"error":{"message":"This key lacks permission for the model."}}'.to_utf8_buffer())
	check(str(no_permission.error).contains("API key"), "a key without permission is still a key problem")
	AIClient.configure({"preset": "mock"})


func test_prompt_contains_soul_and_fits_budget() -> void:
	var history: Array = []
	for i in 40:
		history.append({"role": "user" if i % 2 == 0 else "ai", "text": "message number %d with some extra words to take up space in the prompt" % i, "emotion": "happy"})
	var ctx := {
		"world": {"name": "Lumen Hollow", "world_bible": {"setting": "A cozy moonlit valley. ".repeat(60), "life_context": "Works night shifts as a nurse."}},
		"character": {"name": "Mochi", "personality": "gentle", "memory_notes": ["Likes ramen", "Has a cat named Biscuit"], "summary": "They met last week."},
		"player_name": "Sam", "dreams": [{"text": "open a bakery", "status": "working_on_it"}],
		"history": history, "user_text": "hi!", "emotions": PackedStringArray(EMO), "budget": 2500,
	}
	var msgs := PromptBuilder.build_messages(ctx)
	var system: String = msgs[0].content
	check(system.find("You are Mochi, a real resident of Lumen Hollow") != -1, "core instruction")
	check(system.find("crisis line") != -1, "crisis-care instruction always present")
	check(system.find("Works night shifts") != -1, "World Bible life context")
	check(system.find("open a bakery") != -1, "dreams included")
	check(system.find("Biscuit") != -1, "memory notes included")
	check(system.find("They met last week") != -1, "summary included")
	var total := 0
	for m in msgs:
		total += PromptBuilder.estimate_tokens(str(m.content)) + 4
	check(total <= 2500, "fits budget (%d tokens)" % total)
	eq(msgs.back().content, "hi!", "latest user message last")
	check(msgs.size() > 3, "kept some history")


func test_offline_failure_logs_and_falls_back() -> void:
	fresh_save_root()
	StarterContent.create_world("Test World", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	# Port 9 on localhost: nothing listens there, so the request fails fast.
	AIClient.configure({"preset": "custom", "base_url": "http://127.0.0.1:9/v1", "model": "x", "timeout_s": 2})
	AIClient.backoff_base_s = 0.05
	var convo := Conversation.new()
	var reply: Dictionary = await convo.player_says(id, "are you there?")
	check(reply.failed, "marked failed")
	check(str(reply.segments[0].text) in Conversation.FALLBACK_LINES, "in-character fallback line")
	var log := ChatLog.read_all(id)
	eq(log.size(), 2, "user message AND fallback logged")
	eq(log[0].role, "user")
	eq(log[0].text, "are you there?")
	check(log[1].get("failed", false), "fallback flagged in log")
	var crisis: Dictionary = await convo.player_says(id, "honestly I want to end my life")
	check(ReplyParser.joined_text(crisis.segments).find("crisis line") != -1, "crisis + offline -> caring local reply")
	AIClient.backoff_base_s = 1.5
	AIClient.configure({"preset": "mock"})


func test_mock_conversation_updates_memory_and_affinity() -> void:
	fresh_save_root()
	StarterContent.create_world("Test World", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	var before := float(GameState.get_character(id).relationship.affinity)
	var convo := Conversation.new()
	await convo.player_says(id, "my favorite color is teal")
	var c := GameState.get_character(id)
	check("Favorite color is teal" in c.memory_notes, "memory note saved")
	check(float(c.relationship.affinity) > before, "affinity grew")
	var on_disk := SaveManager.load_character(id)
	check("Favorite color is teal" in on_disk.memory_notes, "persisted to character.json")


func test_memory_notes_must_be_grounded() -> void:
	check(Conversation.note_is_grounded("Works night shifts as a nurse", "I'm so tired after my night shift..."), "stem match")
	check(Conversation.note_is_grounded("Has a cat named Biscuit", "my cat Biscuit knocked over my tea"), "name match")
	check(not Conversation.note_is_grounded("Shares sunny weather photos", "What do you love most about living here?"), "invented note rejected")
	check(not Conversation.note_is_grounded("Teaches guitar lessons", "Any tips for being less nervous on stage?"), "unrelated note rejected")
	check(not Conversation.note_is_grounded("", "anything"), "empty note")


func test_rolling_summary_after_twenty_messages() -> void:
	fresh_save_root()
	StarterContent.create_world("Test World", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	var convo := Conversation.new()
	for i in 17:
		await convo.player_says(id, "story part %d about my garden" % i)
	var c := GameState.get_character(id)
	# The summary fires as soon as 20 messages sit outside the 12-message window (after 16 turns).
	eq(int(c.summary_upto), 32 - Conversation.HISTORY, "summarized everything older than the last 12 messages")
	check(str(c.summary).find("story part") != -1, "summary mentions what was said")
	var ctx := convo.base_context(c)
	ctx["history"] = ChatLog.recent(id, Conversation.HISTORY)
	ctx["user_text"] = "hi"
	check(str(preload("res://scripts/ai/prompt_builder.gd").build_messages(ctx)[0].content).find("story together so far") != -1, "summary goes into the prompt")
