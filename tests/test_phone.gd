extends "res://tests/test_case.gd"
## Phase 11, Phone Link at the HTTP level: the real server on 127.0.0.1,
## raw sockets for the attacks, and the real sync client with its own
## "phone" folder. Pairing (right/wrong/expired/reused codes, rate limit,
## one device), auth (no/wrong/rotated token), path tricks, big bodies, no
## CORS, no listings, static MIME types, sync both ways, conflicts kept,
## chat logs merged by id, snapshots first, and the AI proxy.

const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const SyncClient := preload("res://scripts/phone/sync_client.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")

var server: Node
var port := 0
var pc_root := ""


func _start() -> void:
	pc_root = fresh_save_root()
	StarterContent.create_world("PC World", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	var web := pc_root.path_join("_web")
	JsonUtil.ensure_dir(web)
	for f in ["index.html", "polox.js", "polox.wasm", "polox.pck"]:
		var fa := FileAccess.open(web.path_join(f), FileAccess.WRITE)
		fa.store_string("fake " + f)
		fa.close()
	JsonUtil.ensure_dir(web.path_join("secret"))
	FileAccess.open(web.path_join("secret/hidden.html"), FileAccess.WRITE).store_string("no")
	server = PhoneServer.new()
	tree.root.add_child(server)
	server.setup(pc_root, web)
	port = listen_on_free_port(func(p: int) -> String: return server.start(p, "127.0.0.1"), "Phone Link")


func _stop() -> void:
	server.stop()
	server.queue_free()
	await frames(1)


## Sends raw bytes, returns {code, headers (text), body (String)}.
func _raw(data: PackedByteArray) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", port)
	var t := Time.get_ticks_msec()
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t < 3000:
		peer.poll()
		await frames(1)
	peer.put_data(data)
	var got := PackedByteArray()
	t = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 8000:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_data(n)[1])
		await frames(1)
	var text := got.get_string_from_utf8()
	var split := text.find("\r\n\r\n")
	var head := text.substr(0, split)
	var code := head.split(" ")[1].to_int() if head.split(" ").size() > 1 else 0
	return {"code": code, "headers": head, "body": text.substr(split + 4)}


func _http_get(path: String, token: String = "") -> Dictionary:
	var req := "GET %s HTTP/1.1\r\nHost: x\r\n%s\r\n" % [path, ("Authorization: Bearer %s\r\n" % token) if token != "" else ""]
	return await _raw(req.to_utf8_buffer())


func _post(path: String, body: String, token: String = "") -> Dictionary:
	var req := "POST %s HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: %d\r\n%s\r\n" % [path, body.to_utf8_buffer().size(), ("Authorization: Bearer %s\r\n" % token) if token != "" else ""]
	var bytes := req.to_utf8_buffer()
	bytes.append_array(body.to_utf8_buffer())
	return await _raw(bytes)


func _pair() -> String:
	var code: String = server.pairing.new_code()
	var r := await _post("/api/pair", JSON.stringify({"code": code, "device": "Test phone"}))
	return str(JSON.parse_string(r.body).get("token", ""))


func _client(token: String) -> Node:
	var c := SyncClient.new()
	tree.root.add_child(c)
	c.base_url = "http://127.0.0.1:%d" % port
	c.token = token
	c.local_root = pc_root.path_join("_phone")
	JsonUtil.ensure_dir(c.local_root)
	return c


func _wrong_pin() -> String:
	var c: String = server.pairing.code
	return "000000" if c != "000000" else "111111"


func test_pin_cooldown_pause_and_device_limit() -> void:
	_start()
	var code: String = server.pairing.code
	eq(code.length(), 6, "a PIN is ready the moment Phone Link is on")
	check(server.pairing.code_seconds_left() > 590, "for ten minutes")
	server.pairing.cancel_code()
	var none := await _post("/api/pair", JSON.stringify({"code": "123456"}))
	eq(none.code, 401, "no active PIN")
	code = server.pairing.new_code()
	var wrong := await _post("/api/pair", JSON.stringify({"code": _wrong_pin()}))
	eq(wrong.code, 401, "wrong PIN refused")
	eq(int(JSON.parse_string(wrong.body).get("tries_left", -1)), 4, "and says how many tries are left")
	var ok := await _post("/api/pair", JSON.stringify({"code": code, "device": "Sam's phone", "client": "browser1"}))
	eq(ok.code, 200, "right PIN pairs")
	var token := str(JSON.parse_string(ok.body).token)
	eq(token.length(), 64, "a long random token")
	check(server.pairing.code != code and server.pairing.code.length() == 6, "a new PIN after each pairing")
	var reused := await _post("/api/pair", JSON.stringify({"code": code}))
	eq(reused.code, 401, "a PIN works once")
	check(not FileAccess.get_file_as_string(server.pairing.devices_path()).contains(token), "only a hash of the token is stored")
	# The same browser pairing again replaces its own entry; a limit still applies.
	server.pairing.max_devices = 1
	var again := await _post("/api/pair", JSON.stringify({"code": server.pairing.code, "device": "Sam's phone", "client": "browser1"}))
	eq(again.code, 200, "the same phone pairing again doesn't count twice")
	eq(server.pairing.devices().size(), 1)
	var second := await _post("/api/pair", JSON.stringify({"code": server.pairing.code, "device": "Other", "client": "browser2"}))
	eq(second.code, 409, "past the limit a new phone is refused")
	server.pairing.max_devices = 4
	# Expired PIN.
	var code3: String = server.pairing.new_code()
	server.pairing.code_expires = Time.get_unix_time_from_system() - 1.0
	eq((await _post("/api/pair", JSON.stringify({"code": code3}))).code, 401, "expired PIN refused")
	server.pairing.ensure_code()   # (the server's own _process may have done it already)
	check(server.pairing.code != code3 and server.pairing.code_seconds_left() > 590, "and a fresh one replaces it")
	# 5 wrong from one address: that address waits 60 s (the phone shows the countdown).
	server.pairing._wrong.clear()
	var last := {}
	for i in 5:
		last = await _post("/api/pair", JSON.stringify({"code": _wrong_pin()}))
	eq(last.code, 429, "5 wrong PINs: a cooldown")
	eq(int(JSON.parse_string(last.body).get("retry_after", 0)), 60, "of 60 seconds")
	var right := await _post("/api/pair", JSON.stringify({"code": server.pairing.code}))
	eq(right.code, 429, "even the right PIN waits")
	var st: Dictionary = JSON.parse_string((await _http_get("/api/pairing")).body)
	check(int(st.cooldown) > 50 and not bool(st.paused), "the launcher can show the countdown: %s" % str(st))
	# 20 wrong in an hour from anywhere: paused until unlocked on the PC (kept across restarts).
	server.pairing._cooldown.clear()
	for i in 15:
		server.pairing._cooldown.clear()
		last = await _post("/api/pair", JSON.stringify({"code": _wrong_pin()}))
	eq(last.code, 423, "20 wrong in an hour: pairing pauses")
	check(server.pairing.paused, "paused")
	server.pairing._cooldown.clear()
	eq((await _post("/api/pair", JSON.stringify({"code": server.pairing.code}))).code, 423, "even for the right PIN")
	var Pairing: GDScript = load("res://scripts/phone/pairing.gd")
	check(Pairing.new(pc_root).paused, "still paused after a restart")
	server.pairing.unlock()
	var after := await _post("/api/pair", JSON.stringify({"code": server.pairing.code, "client": "browser3"}))
	eq(after.code, 200, "Unlock pairing on the PC: the right PIN works again")
	var audit := "\n".join(server.pairing.audit_tail(80))
	check(audit.contains("pair_ok") and audit.contains("pair_wrong_code") and audit.contains("pair_cooldown") and audit.contains("pairing_paused") and audit.contains("pairing_unlocked"), "pairing is audited")
	check(not audit.contains(token) and not audit.contains(code), "no tokens or PINs in the audit log")
	server.http.call("_flush_log_file")
	var log_text := FileAccess.get_file_as_string(pc_root.path_join("phone/phone_link.log"))
	check(not log_text.contains(code) and not log_text.contains(server.pairing.code), "no PIN in the request log")
	await _stop()


func test_auth_paths_bodies_and_headers() -> void:
	_start()
	var token := await _pair()
	eq((await _http_get("/api/status")).code, 401, "no token")
	eq((await _http_get("/api/status", "f".repeat(64))).code, 401, "wrong token")
	eq((await _http_get("/api/status", token.substr(0, 63))).code, 401, "short token")
	var st := await _http_get("/api/status", token)
	eq(st.code, 200, "paired phone gets in")
	check(not st.headers.to_lower().contains("access-control-allow-origin"), "no CORS headers")
	check(st.headers.contains("X-Content-Type-Options: nosniff"), "nosniff")
	check(not st.body.contains(str(GameState.settings.get("ai", {}).get("api_key", "@@none@@"))) or str(GameState.settings.ai.get("api_key", "")) == "", "no key in status")
	var slot: String = SaveManager.slot_id
	for bad in ["settings.json", "../settings.json", "slots/%s/../../settings.json" % slot, "slots/%s/%%2e%%2e/x.json" % slot,
			"/etc/passwd", "C:/Windows/win.ini", "slots/%s\\world.json" % slot, "slots/other/world.json",
			"slots/%s/backups/x.json" % slot, "phone/devices.json", "slots/%s/world.exe" % slot]:
		var r := await _http_get("/api/file?path=" + bad.uri_encode(), token)
		check(r.code == 403 or r.code == 404, "refused: %s (got %d)" % [bad, r.code])
	var ok := await _http_get("/api/file?path=" + ("slots/%s/world.json" % slot).uri_encode(), token)
	eq(ok.code, 200, "allowed file")
	# Oversized body: refused before reading it.
	var big := "PUT /api/file?path=slots/%s/world.json HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer %s\r\nContent-Length: %d\r\n\r\n" % [slot, token, HttpUtil.MAX_BODY_BYTES + 1]
	eq((await _raw(big.to_utf8_buffer())).code, 413, "huge body refused")
	eq((await _raw("GARBAGE\r\n\r\n".to_utf8_buffer())).code, 400, "garbage refused")
	eq((await _raw(("OPTIONS /api/status HTTP/1.1\r\nHost: x\r\nOrigin: http://evil\r\nAccess-Control-Request-Method: GET\r\n\r\n").to_utf8_buffer())).code, 204, "OPTIONS answers (it's plain HTTP)")
	var pre := await _raw(("OPTIONS /api/status HTTP/1.1\r\nHost: x\r\nOrigin: http://evil\r\n\r\n").to_utf8_buffer())
	check(not str(pre.headers).to_lower().contains("access-control-"), "but grants no other website anything (no CORS headers)")
	# Static files: at the versioned game address only, right MIME types, no folders, no listing, no dot tricks.
	var gp: String = server.http.game_prefix()
	check(gp.begins_with("/game/") and gp.ends_with("/"), "the game lives at a versioned address (%s)" % gp)
	var wasm := await _http_get(gp + "polox.wasm")
	eq(wasm.code, 200)
	check(wasm.headers.contains("Content-Type: application/wasm"), "wasm MIME type")
	check((await _http_get(gp + "polox.pck")).headers.contains("application/octet-stream"), "pck MIME type")
	check((await _http_get(gp + "polox.js")).headers.contains("Content-Type: text/javascript"), "js MIME type (text/javascript)")
	check((await _http_get("/")).body.contains("Enter the PIN shown on your PC"), "home page is the launcher")
	check((await _http_get(gp + "index.html")).body == "fake index.html", "the game is at /game/<id>/index.html")
	var old_page := await _http_get("/index.html")
	check(old_page.code == 410 and old_page.body.contains("Open the Polox Launcher") and not old_page.headers.contains("Location:"), "the old /index.html: gone, with a link (no redirect)")
	eq((await _http_get("/polox.wasm")).code, 404, "no game files outside the versioned address")
	eq((await _http_get("/game/0123456789abcdef/polox.wasm")).code, 410, "an old build id is never served as current")
	eq((await _http_get(gp + "secret/hidden.html")).code, 404, "no sub-folders")
	eq((await _http_get("/secret/")).code, 404, "no directory listing")
	eq((await _http_get("/..%2F..%2Fsettings.json")).code, 404, "no escaping the web folder")
	check((await _http_get("/pair")).body.contains("Enter the PIN shown on your PC"), "the old pairing address shows the launcher too (no token needed)")
	# Unpair / rotate: the old token stops working at once.
	server.pairing.rotate(str(server.pairing.devices()[0].id))
	eq((await _http_get("/api/status", token)).code, 401, "rotated token refused")
	var audit := "\n".join(server.pairing.audit_tail(80))
	check(audit.contains("auth_failed") and audit.contains("path_refused"), "auth and path failures are audited")
	await _stop()


func test_sync_both_ways_with_snapshot_conflict_and_log_merge() -> void:
	_start()
	var token := await _pair()
	var slot: String = SaveManager.slot_id
	var phone := _client(token)
	# First sync: the phone gets the whole world and the Library.
	var first: Dictionary = await phone.sync()
	check(first.ok, "first sync: " + str(first.error))
	check(FileAccess.file_exists(phone.local_root.path_join("slots/%s/world.json" % slot)), "world copied to the phone")
	check(FileAccess.file_exists(phone.local_root.path_join("library/tilesets/cozy_home/tileset.json")), "Library copied")
	check(not FileAccess.file_exists(phone.local_root.path_join("settings.json")), "settings (and the API key) never leave the PC")
	# Phone edit -> PC.
	var room_rel := "slots/%s/rooms/home.json" % slot
	var proom: Dictionary = JsonUtil.read_json(phone.local_root.path_join(room_rel), {})
	proom["name"] = "Phone Home"
	JsonUtil.write_json(phone.local_root.path_join(room_rel), proom)
	var r2: Dictionary = await phone.sync()
	check(room_rel in r2.pushed, "pushed the phone's edit")
	eq(str(JsonUtil.read_json(pc_root.path_join(room_rel), {}).name), "Phone Home", "the PC has the phone's edit")
	check(SlotArchive.backups(slot).any(func(b): return str(b.kind) == "before_sync"), "the PC took a snapshot before applying it")
	# PC edit -> phone.
	var garden_rel := "slots/%s/rooms/garden.json" % slot
	var groom: Dictionary = JsonUtil.read_json(pc_root.path_join(garden_rel), {})
	groom["name"] = "PC Garden"
	JsonUtil.write_json(pc_root.path_join(garden_rel), groom)
	var r3: Dictionary = await phone.sync()
	check(garden_rel in r3.pulled, "pulled the PC's edit")
	eq(str(JsonUtil.read_json(phone.local_root.path_join(garden_rel), {}).name), "PC Garden", "the phone has the PC's edit")
	# A deliberate conflict: both change the same file.
	groom["name"] = "PC wins"
	JsonUtil.write_json(pc_root.path_join(garden_rel), groom)
	var pg: Dictionary = JsonUtil.read_json(phone.local_root.path_join(garden_rel), {})
	pg["name"] = "Phone version"
	JsonUtil.write_json(phone.local_root.path_join(garden_rel), pg)
	var r4: Dictionary = await phone.sync()
	eq(int(r4.conflicts), 1, "one conflict")
	eq(str(JsonUtil.read_json(pc_root.path_join(garden_rel), {}).name), "PC wins", "the PC keeps its version")
	eq(str(JsonUtil.read_json(phone.local_root.path_join(garden_rel), {}).name), "PC wins", "and the phone takes it")
	var stashed := SyncFiles.conflicts(pc_root, slot)
	eq(stashed.size(), 1, "the phone's version is kept in conflicts/")
	eq(str(JsonUtil.read_json(pc_root.path_join(str(stashed[0].stash)), {}).name), "Phone version", "nothing lost")
	eq(phone.state, "conflict", "the phone shows it")
	# Chat logs merge by message id instead of conflicting.
	var log_rel := "slots/%s/logs/mochi.jsonl" % slot
	ChatLog.append("mochi", "home", "user", "from the PC")
	await phone.sync()
	var f := FileAccess.open(phone.local_root.path_join(log_rel), FileAccess.READ_WRITE)
	f.seek_end()
	f.store_line(JSON.stringify({"id": "w1", "ts": "2099-01-01T00:00:00", "role": "user", "character": "mochi", "text": "from the phone"}))
	f.close()
	ChatLog.append("mochi", "home", "user", "PC again")
	var r5: Dictionary = await phone.sync()
	check(log_rel in r5.merged, "log merged, not conflicted")
	for root in [pc_root, phone.local_root]:
		var text := FileAccess.get_file_as_string(root.path_join(log_rel))
		check(text.contains("from the phone") and text.contains("PC again") and text.contains("from the PC"), "both sides have every line (%s)" % root.get_file())
	eq(FileAccess.get_file_as_string(pc_root.path_join(log_rel)), FileAccess.get_file_as_string(phone.local_root.path_join(log_rel)), "identical logs")
	# Nothing left to do on a second pass.
	var r6: Dictionary = await phone.sync()
	eq(r6.pushed.size() + r6.pulled.size() + r6.merged.size(), 0, "in sync")
	phone.queue_free()
	await _stop()


func test_offline_unpaired_and_ai_proxy() -> void:
	_start()
	var token := await _pair()
	var phone := _client("0".repeat(64))
	var r: Dictionary = await phone.sync()
	check(not r.ok and phone.state == "unpaired", "an unpaired phone is refused")
	phone.token = token
	# The AI proxy answers with the PC's provider (Mock here) and never reveals the key.
	GameState.settings["ai"] = {"preset": "mock", "api_key": "sk-test-SECRET"}
	var ai := await _post("/api/ai", JSON.stringify({"messages": [{"role": "system", "content": "x"}, {"role": "user", "content": "hi"}], "opts": {"mock": {"mode": "test"}}}), token)
	eq(ai.code, 200)
	check(JSON.parse_string(ai.body).text.contains("Mock mode is working"), "proxied reply")
	check(not ai.body.contains("SECRET"), "the key never leaves the PC")
	eq((await _post("/api/ai", JSON.stringify({"messages": [{"role": "root", "content": 1}]}), token)).code, 400, "bad messages refused")
	eq((await _post("/api/ai", "{}")).code, 401, "the proxy needs the token")
	# The phone's AI client: through the PC, then Mock lines when the PC is gone.
	AIClient.configure({"preset": "pc", "base_url": "http://127.0.0.1:%d" % port})
	AIClient.pc_token = token
	var via: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {"mock": {"mode": "test"}})
	check(via.ok and not via.get("offline", false), "chat through the PC")
	await _stop()
	var off: Dictionary = await AIClient.chat([{"role": "user", "content": "hi"}], {"mock": {"mode": "test"}})
	check(off.ok and off.get("offline", false), "PC offline: offline lines")
	eq(AIClient.state, "offline", "with a visible PC offline badge")
	var r2: Dictionary = await phone.sync()
	check(not r2.ok and phone.state == "offline", "sync says PC offline")
	AIClient.pc_token = ""
	AIClient.configure({"preset": "mock"})
	phone.queue_free()


func test_idle_auto_off_and_addresses() -> void:
	_start()
	server.auto_off_hours = 1.0
	server.last_active = Time.get_unix_time_from_system() - 3601.0
	await frames(2)
	check(not server.running, "idle auto-off")
	for a in PhoneServer.addresses():
		check(not a.begins_with("127.") and not a.contains(":"), "LAN/Tailscale IPv4 only: " + a)
	server.queue_free()
	await frames(1)


func test_jsonl_merge_and_path_rules_unit() -> void:
	var a := (JSON.stringify({"id": "1", "ts": "2026-01-01T10:00:00", "text": "a"}) + "\n" + JSON.stringify({"ts": "2026-01-01T09:00:00", "text": "old, no id"}) + "\n").to_utf8_buffer()
	var b := (JSON.stringify({"id": "1", "ts": "2026-01-01T10:00:00", "text": "a"}) + "\n" + JSON.stringify({"id": "2", "ts": "2026-01-01T11:00:00", "text": "b"}) + "\n" + JSON.stringify({"ts": "2026-01-01T09:00:00", "text": "old, no id"}) + "\n").to_utf8_buffer()
	var m := SyncFiles.merge_jsonl(a, b).get_string_from_utf8().strip_edges().split("\n")
	eq(m.size(), 3, "duplicates removed (with and without ids)")
	check(m[0].contains("old, no id") and m[2].contains("\"b\""), "time order")
	var slots := PackedStringArray(["w1"])
	check(SyncFiles.allowed("slots/w1/rooms/home.json", slots))
	check(SyncFiles.allowed("library/tilesets/x/tileset.json", slots))
	for bad in ["slots/w2/world.json", "settings.json", "slots/w1/backups/a.json", "slots/w1/manifest.json", "slots/w1/.hidden.json", "slots/w1/a/../b.json", "slots/w1/run.gd"]:
		check(not SyncFiles.allowed(bad, slots), "not allowed: " + bad)
	eq(HttpUtil.url_decode("a%2Fb+c%zz"), "a/b c%zz")
	check(HttpUtil.constant_time_equals("abc", "abc") and not HttpUtil.constant_time_equals("abc", "abd") and not HttpUtil.constant_time_equals("abc", "abcd"))


## Update 6 (Phase 23, found in the user's real session on 2026-10-15): a fresh phone
## already has its own built-in tile sets from its first start. Its first sync used to
## push them, and the PC filed four "phone conflicts". Now the phone takes the PC's
## copy of anything it had never synced (keeping its own in a local backup), and chat
## logs still merge.
func test_first_sync_takes_the_pc_copy_of_files_the_phone_never_synced() -> void:
	_start()
	var token := await _pair()
	var phone := _client(token)
	var ts_rel := "library/tilesets/cozy_home/tileset.json"
	check(FileAccess.file_exists(pc_root.path_join(ts_rel)), "(the PC has the built-in tile set)")
	var phone_ts := JsonUtil.read_json(pc_root.path_join(ts_rel), {}) as Dictionary
	phone_ts["name"] = "Cozy Home (made on the phone)"
	JsonUtil.ensure_dir(phone.local_root.path_join(ts_rel).get_base_dir())
	JsonUtil.write_json(phone.local_root.path_join(ts_rel), phone_ts)
	var r: Dictionary = await phone.sync()
	check(r.ok, "first sync: " + str(r.error))
	eq(int(r.conflicts), 0, "no conflicts on the first sync")
	check(ts_rel in r.pulled and not ts_rel in r.pushed, "the phone took the PC's copy")
	eq(str(JsonUtil.read_json(phone.local_root.path_join(ts_rel), {}).get("name", "")), str(JsonUtil.read_json(pc_root.path_join(ts_rel), {}).get("name", "")), "the phone now matches the PC")
	check(not DirAccess.dir_exists_absolute(pc_root.path_join("conflicts")) or DirAccess.get_directories_at(pc_root.path_join("conflicts")).is_empty(), "nothing filed as a phone conflict on the PC")
	eq(str(JsonUtil.read_json(phone.local_root.path_join("phone/first_sync_backup/" + ts_rel), {}).get("name", "")), "Cozy Home (made on the phone)", "the phone's own copy is kept in a local backup")
	# After that first sync, a real change on both sides is still a real conflict (unchanged rule).
	var pc_ts := JsonUtil.read_json(pc_root.path_join(ts_rel), {}) as Dictionary
	pc_ts["name"] = "PC rename"
	JsonUtil.write_json(pc_root.path_join(ts_rel), pc_ts)
	var ph := JsonUtil.read_json(phone.local_root.path_join(ts_rel), {}) as Dictionary
	ph["name"] = "Phone rename"
	JsonUtil.write_json(phone.local_root.path_join(ts_rel), ph)
	var r2: Dictionary = await phone.sync()
	eq(int(r2.conflicts), 1, "later edits on both sides: still a conflict, the PC decides")
	_stop()


## The sync rule on its own (no network): what one file needs, from its hash on the PC, here and at the
## last sync.
func test_the_sync_rule_for_one_file() -> void:
	eq(SyncClient.decide("a", "a", "a", false), "same")
	eq(SyncClient.decide("a", "a", "", false), "same", "both sides already agree: nothing to send")
	eq(SyncClient.decide("", "", "a", false), "forget", "gone on both sides")
	eq(SyncClient.decide("b", "a", "a", false), "pull", "only the PC changed it")
	eq(SyncClient.decide("", "a", "a", false), "drop_local", "the PC deleted it")
	eq(SyncClient.decide("a", "b", "a", false), "push", "only this phone changed it")
	eq(SyncClient.decide("a", "", "a", false), "drop_remote", "this phone deleted it")
	eq(SyncClient.decide("b", "", "a", false), "push", "deleted here, changed there: the PC decides, nothing is lost silently")
	eq(SyncClient.decide("b", "c", "a", false), "push", "changed on both sides: the PC merges or files a conflict")
	eq(SyncClient.decide("b", "c", "", false), "pull_first", "never synced, made on both sides: the PC's copy, the phone's backed up")
	eq(SyncClient.decide("b", "c", "", true), "push", "a log is merged by the PC instead")
	eq(SyncClient.decide("b", "", "", false), "pull", "new on the PC")
	eq(SyncClient.decide("", "c", "", false), "push", "new on this phone")
