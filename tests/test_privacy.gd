extends "res://tests/test_case.gd"
## Definition of Done: the API key appears nowhere but settings.json. A
## fake key goes into the settings, then a whole session runs (chats with a
## failing provider whose error echoes the key, a gift, snapshots, a .polox
## export, Phone Link pairing + sync + the AI proxy + status), and every file
## under the save folder (inside zips too) is searched for it.

const StarterContent := preload("res://scripts/core/starter_content.gd")
const Conversation := preload("res://scripts/ai/conversation.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const SyncClient := preload("res://scripts/phone/sync_client.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const KEY := "FAKE-key-7f3a9c-DO-NOT-LEAK"


func _files(dir: String, out: PackedStringArray) -> void:
	for d in DirAccess.get_directories_at(dir):
		_files(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))


func _contains_key(path: String) -> bool:
	if path.get_extension() in ["zip", "polox"]:
		var z := ZIPReader.new()
		if z.open(path) != OK:
			return false
		for entry in z.get_files():
			if z.read_file(entry).get_string_from_utf8().contains(KEY):
				z.close()
				return true
		z.close()
		return false
	return FileAccess.get_file_as_bytes(path).get_string_from_utf8().contains(KEY)


func test_the_key_lives_only_in_settings_json() -> void:
	var root := fresh_save_root()
	StarterContent.create_world("Private", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	GameState.settings["ai"] = {"preset": "custom", "base_url": "http://127.0.0.1:9/v1", "model": "x", "api_key": KEY, "timeout_s": 2}
	GameState.save_settings()
	AIClient.backoff_base_s = 0.05
	var convo := Conversation.new()
	await convo.player_says(id, "my key is %s, can you keep it?" % KEY)   # even if the player types it
	await convo.give_item(id, "fresh_cookies")
	SlotArchive.snapshot(SaveManager.slot_id, "manual")
	SlotArchive.export_bundle(SaveManager.slot_id, root.path_join("exports/private.polox"))
	# Phone Link: pair, sync a phone copy, ask the proxy and the status endpoint.
	var server: Node = PhoneServer.new()
	tree.root.add_child(server)
	server.setup(root, root.path_join("_noweb"))
	var port := listen_on_free_port(func(p: int) -> String: return server.start(p, "127.0.0.1"), "Phone Link")
	var r: Dictionary = server.pairing.pair(server.pairing.new_code(), "Phone", "127.0.0.1")
	var phone: Node = SyncClient.new()
	tree.root.add_child(phone)
	phone.base_url = "http://127.0.0.1:%d" % port
	phone.token = str(r.token)
	phone.local_root = root.path_join("_phone")
	var s: Dictionary = await phone.sync()
	check(s.ok, "phone synced: " + str(s.error))
	var st: Dictionary = await phone.request("GET", "/api/status")
	check(not st.body.get_string_from_utf8().contains(KEY), "status never shows the key")
	var ai: Dictionary = await phone.request("POST", "/api/ai", JSON.stringify({"messages": [{"role": "user", "content": "hi"}]}).to_utf8_buffer())
	check(not ai.body.get_string_from_utf8().contains(KEY), "the proxy never returns the key (even in errors)")
	server.stop()
	server.queue_free()
	phone.queue_free()
	AIClient.backoff_base_s = 1.5
	AIClient.configure({"preset": "mock"})
	await frames(1)
	var all := PackedStringArray()
	_files(root, all)
	var leaks := PackedStringArray()
	for f in all:
		if f == root.path_join("settings.json") or f.begins_with(root.path_join("settings.json")):
			continue
		if _contains_key(f):
			leaks.append(f.trim_prefix(root))
	check(all.size() > 50, "a real session's worth of files (%d)" % all.size())
	eq(leaks, PackedStringArray(), "the key is in no other file")
	check(_contains_key(root.path_join("settings.json")), "(it is in settings.json, where it belongs)")
	GameState.settings["ai"] = {"preset": "mock"}
	GameState.save_settings()
