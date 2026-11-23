extends "res://tests/test_case.gd"
## check_phone.bat, part 1: the real Phone Link (Home Wi-Fi mode, every
## interface, a random port) with the real phone build, reached the way a
## phone does: on 127.0.0.1 AND on every network address of this PC (home
## network, Tailscale). On each: /hello, every game file (bytes, SHA-256,
## MIME, gzip, HEAD, Range), pairing, the device key, sync both ways with
## binary files checked by hash, a deliberate conflict, the AI proxy (Mock).
## Then browser-like stress and the security cases on the network address.
## Listens on this PC's real addresses: check.bat never runs it.

const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const SyncClient := preload("res://scripts/phone/sync_client.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const WebBuild := preload("res://scripts/phone/web_build.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const Probe := preload("res://tests/http_probe.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const RequestSig := preload("res://scripts/phone/request_sig.gd")

var srv: Node
var port := 0
var pc_root := ""
var slot := ""
var probe: Probe


func _start() -> bool:
	pc_root = fresh_save_root("e2e_phone")
	StarterContent.create_world("E2E World", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	slot = SaveManager.slot_id
	AIClient.configure({"preset": "mock"})
	srv = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(pc_root, WebBuild.default_dir())
	srv.mode = "lan"
	port = listen_on_free_port(func(p: int) -> String: return srv.start(p), "Phone Link (Home Wi-Fi mode)", "*")
	probe = Probe.new(tree)
	return port > 0


func _stop() -> void:
	srv.stop()
	srv.queue_free()
	await frames(2)


## 127.0.0.1 plus every address a phone could use (no virtual adapters).
func _addresses() -> PackedStringArray:
	var out := PackedStringArray(["127.0.0.1"])
	for c in srv.candidates():
		if not bool(c.virtual):
			out.append(str(c.ip))
	return out


func test_every_address_serves_the_real_phone_build() -> void:
	if not await _start():
		return
	var wb := WebBuild.inspect()
	check(bool(wb.present) and bool(wb.complete), "the phone version is built (run tools\\export_web.bat)")
	if not bool(wb.present):
		await _stop()
		return
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(WebBuild.default_dir().path_join("build_info.json")))
	check(info is Dictionary, "build_info.json exists (the post-process ran)")
	var addrs := _addresses()
	print("    addresses: ", ", ".join(addrs))
	check(addrs.size() >= 2, "at least one real network address besides 127.0.0.1")
	var mimes := {"index.html": "text/html", "index.js": "text/javascript", "index.wasm": "application/wasm", "index.pck": "application/octet-stream"}
	var gp: String = srv.http.game_prefix()
	check(gp.begins_with("/game/"), "the game's versioned address: " + gp)
	for a in addrs:
		var hello: Dictionary = await probe.request(a, port, Probe.get_req("/hello"))
		check(int(hello.code) == 200 and hello.body.get_string_from_utf8().contains("Polox host reachable"), "%s: /hello" % a)
		for f in mimes:
			var r: Dictionary = await probe.request(a, port, Probe.get_req(gp + f), 60000)
			eq(int(r.code), 200, "%s: %s" % [a, f])
			check(str(r.headers.get("content-type", "")).begins_with(mimes[f]), "%s: %s MIME %s" % [a, f, r.headers.get("content-type", "")])
			if info is Dictionary and info.files.has(f):
				eq(r.body.size(), int(info.files[f].size), "%s: %s byte count" % [a, f])
				eq(Probe.sha(r.body), str(info.files[f].sha256), "%s: %s SHA-256" % [a, f])
		# Plain by default (Update 5): no gzip and no partial answers, even when asked.
		var gz: Dictionary = await probe.request(a, port, Probe.get_req(gp + "index.wasm", {"Accept-Encoding": "gzip", "Range": "bytes=0-1023"}), 60000)
		check(str(gz.headers.get("content-encoding", "")) == "" and int(gz.code) == 200 and gz.body.size() == int(gz.headers.get("content-length", "-1")) and gz.body.size() > 30_000_000, "%s: wasm sent whole and plain (%d bytes)" % [a, gz.body.size()])
		var head: Dictionary = await probe.request(a, port, "HEAD %sindex.wasm HTTP/1.1\r\nHost: x\r\n\r\n" % gp)
		check(int(head.code) == 200 and head.body.is_empty(), "%s: HEAD" % a)
		eq(int((await probe.request(a, port, Probe.get_req("/index.wasm"))).code), 404, "%s: no game files outside the versioned address" % a)
	await _stop()


func _client(addr: String) -> Node:
	var phone: Node = SyncClient.new()
	tree.root.add_child(phone)
	phone.base_url = "http://%s:%d" % [addr, port]
	phone.local_root = pc_root.path_join("_phone_" + addr.replace(".", "_"))
	return phone


func _room_path(root: String) -> String:
	return root.path_join("slots").path_join(slot).path_join("rooms").path_join(GameState.current_room_id + ".json")


func _rename(path: String, name: String) -> void:
	var d: Dictionary = JsonUtil.read_json(path, {})
	d["name"] = name
	JsonUtil.write_json(path, d)


func test_pair_sync_conflict_and_ai_on_every_address() -> void:
	if not await _start():
		return
	for a in _addresses():
		var phone := _client(a)
		# Pairing from this address, then the key works and nothing else does.
		var paired: Dictionary = await phone.pair(srv.pairing.new_code(), "e2e " + a)
		check(paired.ok, "%s: paired (%s)" % [a, str(paired.get("error", ""))])
		if not paired.ok:
			phone.queue_free()
			continue
		var signed := RequestSig.header(str(paired.token), "GET", "/api/status").trim_prefix("Authorization: ")
		eq(int((await probe.request(a, port, Probe.get_req("/api/status", {"Authorization": signed}))).code), 200, "%s: a request signed with the key opens the API" % a)
		eq(int((await probe.request(a, port, Probe.get_req("/api/status", {"Authorization": "Bearer " + str(paired.token)}))).code), 401, "%s: the bare key of a phone that signs doesn't" % a)
		eq(int((await probe.request(a, port, Probe.get_req("/api/status"))).code), 401, "%s: no key: 401" % a)
		eq(int((await probe.request(a, port, Probe.get_req("/api/status", {"Authorization": "Bearer " + "0".repeat(64)}))).code), 401, "%s: wrong key: 401" % a)
		# First sync: the phone gets everything, byte for byte (PNGs included).
		var s1: Dictionary = await phone.sync()
		check(s1.ok and (s1.pulled as Array).size() > 10, "%s: first sync pulled %d files (%s)" % [a, (s1.pulled as Array).size(), str(s1.error)])
		var slots := PackedStringArray([slot])
		var pc_files := SyncFiles.scan(pc_root, slots)
		var ph_files := SyncFiles.scan(phone.local_root, slots)
		var same := 0
		var pngs := 0
		for p in pc_files:
			if ph_files.has(p) and str(ph_files[p].sha256) == str(pc_files[p].sha256):
				same += 1
				if str(p).ends_with(".png"):
					pngs += 1
		eq(same, pc_files.size(), "%s: every synced file identical on the phone" % a)
		check(pngs > 0, "%s: binary files (%d PNGs) arrived intact" % [a, pngs])
		# Phone -> PC.
		_rename(_room_path(phone.local_root), "Renamed on the phone " + a)
		var s2: Dictionary = await phone.sync()
		check(s2.ok and (s2.pushed as Array).size() >= 1, "%s: pushed" % a)
		eq(str(JsonUtil.read_json(_room_path(pc_root), {}).get("name", "")), "Renamed on the phone " + a, "%s: phone edit is on the PC" % a)
		# PC -> phone.
		_rename(_room_path(pc_root), "Renamed on the PC " + a)
		var s3: Dictionary = await phone.sync()
		check(s3.ok and (s3.pulled as Array).size() >= 1, "%s: pulled" % a)
		eq(str(JsonUtil.read_json(_room_path(phone.local_root), {}).get("name", "")), "Renamed on the PC " + a, "%s: PC edit is on the phone" % a)
		# Both: the PC keeps its version, the phone's is kept aside.
		_rename(_room_path(phone.local_root), "Phone side " + a)
		_rename(_room_path(pc_root), "PC side " + a)
		var s4: Dictionary = await phone.sync()
		eq(int(s4.get("conflicts", 0)), 1, "%s: one conflict" % a)
		eq(str(JsonUtil.read_json(_room_path(phone.local_root), {}).get("name", "")), "PC side " + a, "%s: the PC version wins on both" % a)
		check(not SyncFiles.conflicts(pc_root, slot).is_empty(), "%s: the phone's version is stashed on the PC" % a)
		# Chats through the PC (Mock here: no key, nothing leaves this PC).
		var ai: Dictionary = await phone.request("POST", "/api/ai", JSON.stringify({"messages": [{"role": "user", "content": "hello"}]}).to_utf8_buffer())
		check(ai.ok and str(ai.json.get("text", "")) != "", "%s: AI proxy answers" % a)
		srv.pairing.unpair(str(srv.pairing.devices()[0].id))
		phone.queue_free()
		await frames(1)
	await _stop()


func test_stress_and_attacks_on_the_network_address() -> void:
	if not await _start():
		return
	var addrs := _addresses()
	var a := addrs[1] if addrs.size() > 1 else "127.0.0.1"
	print("    stress + attacks on ", a)
	# Browser-like: idle speculative sockets + 8 downloads at once + a slow sender + a dropped download.
	var idle: Array = []
	for i in 8:
		idle.append(await probe.connect_peer(a, port))
	var reqs: Array = []
	var gp: String = srv.http.game_prefix()
	for i in 6:
		reqs.append(Probe.get_req(gp + "index.pck"))
	reqs.append(Probe.get_req(gp + "index.wasm", {"Accept-Encoding": "gzip"}))
	reqs.append(Probe.get_req(gp + "index.wasm", {"Accept-Encoding": "gzip"}))
	var all: Array = await probe.parallel(a, port, reqs, 90000)
	eq(all.filter(func(r): return int(r.code) == 200).size(), 8, "8 parallel downloads while 8 sockets sit idle")
	var pck_sha := Probe.sha(FileAccess.get_file_as_bytes(WebBuild.default_dir().path_join("index.pck")))
	eq(all.slice(0, 6).filter(func(r): return Probe.sha(r.body) == pck_sha).size(), 6, "all identical")
	var slow := await probe.connect_peer(a, port)
	for piece in ["GET /hel", "lo.json HTTP/1.1\r\nHo", "st: x\r\n", "\r\n"]:
		slow.put_data(piece.to_utf8_buffer())
		await frames(4)
	eq(int(Probe.parse_response(await probe.read_all(slow)).code), 200, "slow sender served")
	var quitter := await probe.connect_peer(a, port)
	quitter.put_data(Probe.get_req(gp + "index.wasm").to_utf8_buffer())
	await frames(4)
	quitter.disconnect_from_host()
	for p in idle:
		(p as StreamPeerTCP).disconnect_from_host()
	var t := Time.get_ticks_msec()
	while srv.http.open_connections() > 0 and Time.get_ticks_msec() - t < 15000:
		await frames(5)
	eq(srv.http.open_connections(), 0, "every connection cleaned up")
	# Attacks.
	var code: String = srv.pairing.new_code()
	var first: Dictionary = await probe.request(a, port, Probe.with_body("POST", "/api/pair", JSON.stringify({"code": code, "device": "x"}).to_utf8_buffer()))
	eq(int(first.code), 200, "pairing works once...")
	var again: Dictionary = await probe.request(a, port, Probe.with_body("POST", "/api/pair", JSON.stringify({"code": code, "device": "y"}).to_utf8_buffer()))
	check(int(again.code) in [401, 409], "...a reused code doesn't (%d)" % int(again.code))
	srv.pairing.unpair(str(srv.pairing.devices()[0].id))
	var old: String = srv.pairing.new_code()
	srv.pairing.code_expires = Time.get_unix_time_from_system() - 1.0
	eq(int((await probe.request(a, port, Probe.with_body("POST", "/api/pair", JSON.stringify({"code": old}).to_utf8_buffer()))).code), 401, "an expired code doesn't")
	var token := str(JSON.parse_string((await probe.request(a, port, Probe.with_body("POST", "/api/pair", JSON.stringify({"code": srv.pairing.new_code()}).to_utf8_buffer()))).body.get_string_from_utf8()).token)
	for bad in ["../settings.json", "slots/%s/../../settings.json" % slot, "slots/%s/..%%2f..%%2fsettings.json" % slot, "C:/Windows/win.ini", "phone/devices.json", "settings.json"]:
		eq(int((await probe.request(a, port, Probe.get_req("/api/file?path=" + bad, {"Authorization": "Bearer " + token}))).code), 403, "path refused: " + bad)
	var huge := "PUT /api/file?path=slots/%s/world.json HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer %s\r\nContent-Length: %d\r\n\r\n" % [slot, token, HttpUtil.MAX_BODY_BYTES + 1]
	eq(int((await probe.request(a, port, huge)).code), 413, "oversized body refused")
	srv.http.debug_peer_override = "8.8.8.8"
	eq(int((await probe.request(a, port, Probe.get_req("/hello"))).code), 403, "a public internet address is refused")
	srv.http.debug_peer_override = ""
	check(srv.running and srv.http.thread_restarts() == 0, "the server never fell over")
	await _stop()


## Phase 16: plain home Wi-Fi with no Tailscale, the way the user's phone does it:
## the launcher, a wrong PIN, the right PIN, the worlds with a cover, starting a
## session, the PIN changing after pairing, and the cooldown, all on the LAN
## address. Then Auto with a (fake) Tailscale that can do HTTPS: Serve is
## chosen and Same Wi-Fi still answers on the LAN address.
func test_same_wifi_launcher_flow_on_the_home_network_address() -> void:
	pc_root = fresh_save_root("e2e_launcher")
	StarterContent.create_world("Wi-Fi World", "Sam")
	GameState.load_world()
	slot = SaveManager.slot_id
	var img := Image.create(16, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color("#c9b6ff"))
	img.save_png(pc_root.path_join("slots").path_join(slot).path_join("cover.png"))
	AIClient.configure({"preset": "mock"})
	srv = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(pc_root, WebBuild.default_dir())
	srv.mode = PhoneServer.auto_mode({})
	eq(srv.mode, "lan", "no Tailscale: Same Wi-Fi")
	port = listen_on_free_port(func(p: int) -> String: return srv.start(p), "Phone Link on", "*")
	probe = Probe.new(tree)
	eq(str(srv.http.bind_address), "0.0.0.0", "listening on every address (IPv4)")
	var a: String = PhoneServer.pick_lan(srv.candidates())
	if not check(a != "", "this PC has a home-network address"):
		await _stop()
		return
	print("    Same Wi-Fi address: http://%s:%d (%s)" % [a, port, srv.bind_text()])
	eq(srv.canonical_url(), "http://%s:%d" % [a, port], "the big address is the Wi-Fi one")
	var home: Dictionary = await probe.request(a, port, Probe.get_req("/"))
	eq(int(home.code), 200, "/ answers on the Wi-Fi address")
	check(home.body.get_string_from_utf8().contains("Enter the PIN shown on your PC"), "with the launcher")
	check(not home.body.get_string_from_utf8().contains("This is the PC"), "(a phone isn't told it's the PC)")
	var st: Dictionary = JSON.parse_string((await probe.request(a, port, Probe.get_req("/api/pairing"))).body.get_string_from_utf8())
	check(not bool(st.paused) and int(st.cooldown) == 0, "pairing open")
	var bad := "000000" if srv.pairing.code != "000000" else "111111"
	var wrong: Dictionary = await probe.request(a, port, Probe.with_body("POST", "/api/pair", JSON.stringify({"code": bad}).to_utf8_buffer()))
	eq(int(wrong.code), 401, "wrong PIN")
	var pin: String = srv.pairing.code
	var right: Dictionary = await probe.request(a, port, Probe.with_body("POST", "/api/pair", JSON.stringify({"code": pin, "device": "Wi-Fi phone", "client": "wifi1"}).to_utf8_buffer()))
	eq(int(right.code), 200, "right PIN")
	var token := str(JSON.parse_string(right.body.get_string_from_utf8()).get("token", ""))
	eq(token.length(), 64, "a key")
	check(srv.pairing.code != pin, "a new PIN on the PC")
	var auth := {"Authorization": "Bearer " + token}
	var worlds: Dictionary = JSON.parse_string((await probe.request(a, port, Probe.get_req("/api/worlds", auth))).body.get_string_from_utf8())
	check((worlds.worlds as Array).any(func(w): return str(w.id) == slot and bool(w.cover)), "the worlds list has this world with a cover")
	var cover: Dictionary = await probe.request(a, port, Probe.get_req("/api/cover?slot=" + slot, auth))
	check(int(cover.code) == 200 and (cover.body as PackedByteArray).size() > 20, "the cover arrives")
	var sess: Dictionary = await probe.request(a, port, Probe.with_body("POST", "/api/session", JSON.stringify({"slot": slot}).to_utf8_buffer(), token))
	var sj: Dictionary = JSON.parse_string(sess.body.get_string_from_utf8())
	check(int(sess.code) == 200 and str(sj.play) == str(srv.http.game_prefix()) + "index.html#slot=" + slot and bool(sj.game_ok), "session start: %s" % str(sj))
	var game: Dictionary = await probe.request(a, port, Probe.get_req(str(sj.play).get_slice("#", 0)))
	eq(int(game.code), 200, "the game page is there")
	var last := 0
	for i in 5:
		last = int((await probe.request(a, port, Probe.with_body("POST", "/api/pair", JSON.stringify({"code": bad}).to_utf8_buffer()))).code)
	eq(last, 429, "5 wrong PINs from the phone: a cooldown")
	var st2: Dictionary = JSON.parse_string((await probe.request(a, port, Probe.get_req("/api/pairing"))).body.get_string_from_utf8())
	check(int(st2.cooldown) > 50, "the phone can show the countdown (%d s)" % int(st2.cooldown))
	await _stop()
	# Auto with Tailscale that can do HTTPS: Serve, and Same Wi-Fi still works.
	var Links := preload("res://tests/test_phone_link.gd")
	var fake = Links.FakeTs.new()
	fake.status_json = Links.STATUS_JSON
	srv = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(pc_root, WebBuild.default_dir())
	srv.ts.runner = fake.run
	srv.ts.cli = "x"
	srv.mode = PhoneServer.auto_mode(srv.ts.status())
	eq(srv.mode, "tailscale_serve", "Tailscale with HTTPS: Serve is picked")
	port = listen_on_free_port(func(p: int) -> String: return srv.start(p), "Phone Link Serve", "*")
	check(fake.mappings.has(str(srv.serve_port)), "published through the (fake) Tailscale Serve")
	var wifi: Dictionary = await probe.request(a, port, Probe.get_req("/"))
	eq(int(wifi.code), 200, "and the Wi-Fi address still answers (Tailscale never breaks Same Wi-Fi)")
	check(srv.urls().has("http://%s:%d" % [a, port]) and srv.ts_url().begins_with("https://"), "both addresses are offered")
	var published := str(srv.serve_port)
	await _stop()
	check(not fake.mappings.has(published) and fake.mappings.size() == 2, "only Polox's mapping removed")


## Phase 20: the way phones really behave, over this PC's home-network address:
## the listener really is on 0.0.0.0 (this PC's own socket table, R0), a request
## in slow pieces and one byte at a time, a body that stops half-way, extra bytes
## after a request (drained, so the answer isn't reset), six downloads of the
## real 39 MB wasm at once while idle half-open sockets wait, an aborted
## download, HEAD, odd Host headers, and the exact Web export file set byte for
## byte, with index.html's fileSizes.
func test_phone_like_clients_on_the_home_network_address() -> void:
	if not await _start():
		return
	eq(str(srv.http.bind_address), "0.0.0.0", "listening on IPv4, every adapter")
	var facts := preload("res://scripts/net/net_facts.gd").collect([port])
	var socks: Array = (facts.get("listening", []) as Array).filter(func(l): return int(l.port) == port)
	check(socks.any(func(l): return str(l.address) == "0.0.0.0" and str(l.get("process", "")).to_lower().begins_with("godot")), "this PC's socket table: 0.0.0.0:%d owned by Polox's Godot (%s)" % [port, str(socks)])
	var ip := PhoneServer.pick_lan(srv.candidates())
	if not check(ip != "", "this PC has a home-network address"):
		await _stop()
		return
	print("    phone-like clients on ", ip)
	srv.http.header_timeout_ms = 3000
	var gp: String = srv.http.game_prefix()
	var dir := WebBuild.default_dir()
	# Slow pieces and one byte at a time.
	var peer := await probe.connect_peer(ip, port)
	var req := Probe.get_req("/ping").to_utf8_buffer()
	for i in range(0, req.size(), 7):
		peer.put_data(req.slice(i, mini(i + 7, req.size())))
		await tree.create_timer(0.15).timeout
	check(Probe.parse_response(await probe.read_all(peer)).body.get_string_from_utf8().contains("Polox OK"), "a request in slow pieces")
	peer = await probe.connect_peer(ip, port)
	for b in Probe.get_req("/hello.json").to_utf8_buffer():
		peer.put_data(PackedByteArray([b]))
		await frames(1)
	eq(int(Probe.parse_response(await probe.read_all(peer)).code), 200, "headers one byte at a time")
	# A body that stops half-way.
	peer = await probe.connect_peer(ip, port)
	peer.put_data("POST /api/report HTTP/1.1\r\nHost: x\r\nContent-Length: 4000\r\n\r\n{".to_utf8_buffer())
	await frames(3)
	peer.disconnect_from_host()
	# Extra bytes after a full request: the answer must still arrive whole.
	peer = await probe.connect_peer(ip, port)
	var extra := Probe.get_req(gp + "index.pck").to_utf8_buffer()
	extra.append_array(("GET /ping HTTP/1.1\r\nHost: x\r\n\r\n" + "\r\n".repeat(3000)).to_utf8_buffer())
	peer.put_data(extra)
	var whole := Probe.parse_response(await probe.read_all(peer, 30000))
	eq(Probe.sha(whole.body), Probe.sha(FileAccess.get_file_as_bytes(dir.path_join("index.pck"))), "the whole pck arrives though bytes were left unread behind the request")
	# Six real wasm downloads at once, with half-open idle sockets and an abort.
	var idle: Array = []
	for i in 5:
		var s := await probe.connect_peer(ip, port)
		s.put_data("GET /ping HTTP/1.1\r\nHo".to_utf8_buffer())
		idle.append(s)
	var quitter := await probe.connect_peer(ip, port)
	quitter.put_data(Probe.get_req(gp + "index.wasm").to_utf8_buffer())
	await tree.create_timer(0.3).timeout
	quitter.disconnect_from_host()
	var want := Probe.sha(FileAccess.get_file_as_bytes(dir.path_join("index.wasm")))
	var raws: Array = []
	for i in 6:
		raws.append(Probe.get_req(gp + "index.wasm"))
	var res: Array = await probe.parallel(ip, port, raws, 180000)
	eq(res.filter(func(r): return int(r.code) == 200 and Probe.sha(r.body) == want).size(), 6, "six 39 MB wasm downloads at once, every byte right, while idle sockets wait")
	for s in idle:
		(s as StreamPeerTCP).poll()
	check(idle.all(func(s): return (s as StreamPeerTCP).get_status() != StreamPeerTCP.STATUS_CONNECTED), "the half-open sockets were dropped")
	# HEAD and odd Host headers.
	var head: Dictionary = await probe.request(ip, port, "HEAD %sindex.wasm HTTP/1.1\r\nHost: x\r\n\r\n" % gp)
	check(int(head.code) == 200 and head.body.is_empty(), "HEAD")
	for host in ["", "%s:%d" % [ip, port], "%s.local:%d" % [PhoneServer.pc_name(), port], "x".repeat(2000)]:
		var r: Dictionary = await probe.request(ip, port, "GET /ping HTTP/1.1\r\n" + (("Host: " + host + "\r\n") if host != "" else "") + "\r\n")
		eq(int(r.code), 200, "Host %s" % (host.substr(0, 30) if host != "" else "(missing)"))
	# The exact export file set, byte for byte, with index.html's fileSizes.
	var html := FileAccess.get_file_as_string(dir.path_join("index.html"))
	var at := html.find("GODOT_CONFIG = ")
	var cfg: Variant = JSON.parse_string(html.substr(at + 15, html.find("};", at) - at - 14))
	for n in Array(DirAccess.get_files_at(dir)).filter(func(n): return str(n).get_extension().to_lower() in srv.http.static_exts and not str(n).ends_with(".gz")):
		var r: Dictionary = await probe.request(ip, port, Probe.get_req(gp + str(n)), 120000)
		check(int(r.code) == 200 and Probe.sha(r.body) == Probe.sha(FileAccess.get_file_as_bytes(dir.path_join(str(n)))), "%s byte for byte" % n)
		if cfg is Dictionary and (cfg.fileSizes as Dictionary).has(str(n)):
			eq(int(r.headers.get("content-length", "-1")), int(cfg.fileSizes[n]), "%s = fileSizes" % n)
	check(srv.running and srv.http.thread_restarts() == 0, "the server never fell over")
	await _stop()


## Phase 23: the PC's "Polox is here" goes out on the home network for real (broadcasts from
## Phone Link on every interface), and an app listening on every interface hears it, picks the
## home-network address it came from, and reaches Phone Link there. (A PC hearing its own
## broadcast proves it is sent on the network adapter; the phone's side is in PHONE_TEST.md.)
func test_the_app_finds_the_pc_by_its_announcement_on_the_home_network() -> void:
	pc_root = fresh_save_root("e2e_announce")
	StarterContent.create_world("E2E World", "Sam")
	GameState.load_world()
	srv = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(pc_root, WebBuild.default_dir())
	srv.mode = "lan"
	srv.announce_port = free_udp_port("*")
	port = listen_on_free_port(func(p: int) -> String: return srv.start(p), "Phone Link on every interface", "*")
	var targets := Array(srv.announcer.targets)
	print("    announcing to: ", ", ".join(PackedStringArray(targets)))
	check("255.255.255.255" in targets, "the whole home network")
	check(targets.size() >= 2, "and the home adapter's own broadcast address")
	var link: Node = load("res://scripts/phone/app_link.gd").new()
	tree.root.add_child(link)
	link.listen_port = srv.announce_port
	link.listen_address = "*"
	link.load_link(pc_root.path_join("_app_phone"))
	var heard: Array = await link.listen(4.5)
	print("    heard: ", heard.map(func(h): return "%s at %s" % [h.name, h.url]))
	var home_ip := PhoneServer.pick_lan(srv.candidates())
	check(home_ip != "", "this PC has a home-network address")
	check(heard.any(func(h): return str(h.ip) == home_ip), "heard from the home network adapter itself (%s), not a virtual one" % home_ip)
	check(heard.all(func(h): return str(h.name) == PhoneServer.pc_name()), "with this PC's name")
	var r: Dictionary = await link.find_pc(4.5)
	check(bool(r.ok), "found: %s" % r)
	eq(str(r.get("path", "")), "home", "by the home network")
	check(heard.size() >= 1 and not str(r.get("url", "")).contains("127.0.0.1"), "at a home-network address: " + str(r.get("url", "")))
	link.queue_free()
	await _stop()
