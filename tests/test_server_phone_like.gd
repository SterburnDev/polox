extends "res://tests/test_case.gd"
## Phase 20: the server tested the way phones actually behave, not the way a
## well-behaved test client does (127.0.0.1 here; check_phone repeats the
## important ones over this PC's home-network address):
##   requests split into pieces and sent slowly, headers one byte at a time,
##   a body that stops half-way, extra bytes after a request (the server must
##   drain them, or Windows resets the connection and the phone loses the
##   answer), six big downloads at once with idle half-open sockets, an aborted
##   download, HEAD, odd Host headers, a refused address, the exact Web export
##   file set byte for byte, address choice with WSL / Hyper-V / VPN / VirtualBox
##   adapters present, port safety, and stale build ids never served as current.

const Probe := preload("res://tests/http_probe.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const PingServer := preload("res://scripts/net/ping_server.gd")
const NetRules := preload("res://scripts/phone/net_rules.gd")
const WebBuild := preload("res://scripts/phone/web_build.gd")
const BigFile := preload("res://scripts/net/big_file.gd")
const Firewall := preload("res://scripts/phone/firewall.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")

var srv: Node
var port := 0


func _start(web_dir: String = "") -> String:
	var root := fresh_save_root()
	srv = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, web_dir if web_dir != "" else root.path_join("no_web"))
	port = listen_on_free_port(func(p: int) -> String: return srv.start(p, "127.0.0.1"), "Phone Link")
	srv.http.header_timeout_ms = 2500
	srv.http.idle_timeout_ms = 4000
	return root


func _stop() -> void:
	srv.stop()
	srv.queue_free()
	await frames(2)


func _send_pieces(peer: StreamPeerTCP, bytes: PackedByteArray, pieces: int, delay_s: float) -> void:
	var step := ceili(bytes.size() / float(pieces))
	var i := 0
	while i < bytes.size():
		peer.put_data(bytes.slice(i, mini(i + step, bytes.size())))
		i += step
		await tree.create_timer(delay_s).timeout


func test_split_slow_and_byte_by_byte() -> void:
	_start()
	var p := Probe.new(tree)
	# A GET in five pieces, 300 ms apart.
	var peer := await p.connect_peer("127.0.0.1", port)
	await _send_pieces(peer, Probe.get_req("/ping").to_utf8_buffer(), 5, 0.3)
	var r := Probe.parse_response(await p.read_all(peer))
	check(r.code == 200 and r.body.get_string_from_utf8().contains("Polox OK"), "a request in five slow pieces is answered")
	# Headers one byte at a time.
	peer = await p.connect_peer("127.0.0.1", port)
	for b in Probe.get_req("/test/info.json").to_utf8_buffer():
		peer.put_data(PackedByteArray([b]))
		await frames(1)
	r = Probe.parse_response(await p.read_all(peer))
	eq(r.code, 200, "headers one byte at a time")
	# A POST whose body arrives in pieces after the headers.
	var body := JSON.stringify({"v": 1, "results": [{"id": "ping", "ok": true}], "hints": ["x".repeat(3000)]}).to_utf8_buffer()
	peer = await p.connect_peer("127.0.0.1", port)
	await _send_pieces(peer, Probe.with_body("POST", "/api/report", body), 6, 0.2)
	r = Probe.parse_response(await p.read_all(peer))
	eq(r.code, 200, "a POST body that trickles in is read in full before answering")
	await _stop()


func test_body_stops_halfway_and_extra_bytes_are_drained() -> void:
	_start()
	var p := Probe.new(tree)
	# Says 5000 bytes, sends 100, hangs up.
	var peer := await p.connect_peer("127.0.0.1", port)
	peer.put_data("POST /api/report HTTP/1.1\r\nHost: x\r\nContent-Length: 5000\r\n\r\n".to_utf8_buffer())
	peer.put_data("x".repeat(100).to_utf8_buffer())
	await frames(3)
	peer.disconnect_from_host()
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and not srv.http.contacts(10).any(func(c): return str(c.outcome) == "cut"):
		await tree.create_timer(0.05).timeout
	check(srv.http.contacts(10).any(func(c): return str(c.outcome) == "cut" and str(c.path).contains("hung up")), "a body that stops half-way is recorded as cut, not a crash")
	var r: Dictionary = await p.request("127.0.0.1", port, Probe.get_req("/ping"))
	eq(r.code, 200, "and the next request is fine")
	# Extra bytes after a complete request (a second pipelined request, stray CRLFs):
	# the answer must arrive whole (closing on unread data would reset the connection).
	for round in 3:
		peer = await p.connect_peer("127.0.0.1", port)
		var junk := Probe.get_req("/test/info.json").to_utf8_buffer()
		junk.append_array(("GET /ping HTTP/1.1\r\nHost: x\r\n\r\n" + "\r\n".repeat(2000)).to_utf8_buffer())
		peer.put_data(junk)
		var got := await p.read_all(peer)
		var resp := Probe.parse_response(got)
		check(resp.code == 200 and resp.body.size() == int(resp.headers.get("content-length", "-1")), "round %d: the whole answer arrives even with unread bytes behind the request" % round)
	await _stop()


func test_six_big_downloads_with_idle_half_open_sockets_and_an_abort() -> void:
	_start()
	var p := Probe.new(tree)
	var meta := BigFile.meta()
	# Five idle sockets that sent half a request and then nothing (a phone's speculative connections).
	var idle: Array = []
	for i in 5:
		var s := await p.connect_peer("127.0.0.1", port)
		s.put_data("GET /ping HTTP/1.1\r\nHo".to_utf8_buffer())
		idle.append(s)
	# An aborted download: read 1 MB of the big file, then hang up.
	var quitter := await p.connect_peer("127.0.0.1", port)
	quitter.put_data(Probe.get_req("/test/big").to_utf8_buffer())
	var got := 0
	var t := Time.get_ticks_msec()
	while got < 1048576 and Time.get_ticks_msec() - t < 10000:
		quitter.poll()
		var n := quitter.get_available_bytes()
		if n > 0:
			got += (quitter.get_data(n)[1] as PackedByteArray).size()
		else:
			await frames(1)
	quitter.disconnect_from_host()
	# Six full downloads at once.
	var raws: Array = []
	for i in 6:
		raws.append(Probe.get_req("/test/big"))
	var res: Array = await p.parallel("127.0.0.1", port, raws, 120000)
	var all_ok := true
	for r in res:
		all_ok = all_ok and int(r.code) == 200 and Probe.sha(r.body) == str(meta.sha256)
	check(all_ok, "six 20 MB downloads at once, every byte right")
	await tree.create_timer(3.0).timeout
	for s in idle:
		(s as StreamPeerTCP).poll()
	check(idle.all(func(s): return (s as StreamPeerTCP).get_status() != StreamPeerTCP.STATUS_CONNECTED), "the half-open idle sockets were dropped by the header timeout")
	check(srv.http.contacts(40).any(func(c): return str(c.path).contains("/test/big") and str(c.outcome) == "request"), "the aborted download is in the contact log")
	var r2: Dictionary = await p.request("127.0.0.1", port, Probe.get_req("/ping"))
	eq(r2.code, 200, "still answering afterwards")
	await _stop()


func test_head_odd_hosts_and_refused_address() -> void:
	_start()
	var p := Probe.new(tree)
	var r: Dictionary = await p.request("127.0.0.1", port, "HEAD /ping HTTP/1.1\r\nHost: x\r\n\r\n")
	check(r.code == 200 and r.body.is_empty() and int(r.headers.get("content-length", "0")) > 0, "HEAD: the length, no body")
	for host in ["", "192.168.1.42:8765", "EXAMPLE-PC.local:8765", "x".repeat(3000), "[::1]:8765", "évil.example"]:
		var req: String = "GET /ping HTTP/1.1\r\n" +(("Host: " + host + "\r\n") if host != "" else "") + "\r\n"
		r = await p.request("127.0.0.1", port, req)
		eq(r.code, 200, "Host %s: answered" % (host.substr(0, 30) if host != "" else "(missing)"))
	r = await p.request("127.0.0.1", port, "GET http://192.168.1.42:8765/ping HTTP/1.1\r\nHost: x\r\n\r\n")
	check(r.code in [200, 400, 404], "an absolute URL doesn't crash anything (%d)" % r.code)
	srv.http.debug_peer_override = "8.8.8.8"
	r = await p.request("127.0.0.1", port, Probe.get_req("/ping"))
	eq(r.code, 403, "a public address is refused (after its request was read, so the refusal arrives)")
	srv.http.debug_peer_override = ""
	await _stop()


func test_exact_web_export_file_set() -> void:
	var dir := WebBuild.default_dir()
	var wb := WebBuild.inspect(dir)
	if not bool(wb.present):
		print("    SKIPPED: no phone version built (tools\\export_web.bat)")
		return
	_start(dir)
	var p := Probe.new(tree)
	var gp: String = srv.http.game_prefix()
	check(gp != "", "a versioned game address")
	var html := FileAccess.get_file_as_string(dir.path_join("index.html"))
	var cfg_start := html.find("GODOT_CONFIG = ")
	var cfg: Variant = JSON.parse_string(html.substr(cfg_start + 15, html.find("};", cfg_start) - cfg_start - 14)) if cfg_start >= 0 else null
	check(cfg is Dictionary and (cfg as Dictionary).has("fileSizes"), "index.html's GODOT_CONFIG (with fileSizes) is readable")
	var names: Array = Array(DirAccess.get_files_at(dir)).filter(func(n): return str(n).get_extension().to_lower() in srv.http.static_exts and not str(n).ends_with(".gz"))
	check(names.has("index.html") and names.has("index.wasm") and names.has("index.pck") and names.has("index.js"), "the export's files: %s" % str(names))
	for n in names:
		var want := FileAccess.get_file_as_bytes(dir.path_join(str(n)))
		var r: Dictionary = await p.request("127.0.0.1", port, Probe.get_req(gp + str(n)), 120000)
		check(r.code == 200 and Probe.sha(r.body) == Probe.sha(want), "%s served byte for byte under its exported name" % n)
		eq(str(r.headers.get("content-type", "")), HttpUtil.mime_for(str(n)), "%s MIME" % n)
		if cfg is Dictionary and (cfg.fileSizes as Dictionary).has(str(n)):
			eq(int(r.headers.get("content-length", "-1")), int(cfg.fileSizes[n]), "%s matches index.html's fileSizes" % n)
	await _stop()


func test_stale_build_ids_are_never_served_as_current() -> void:
	var root := fresh_save_root()
	var web := root.path_join("web")
	DirAccess.make_dir_recursive_absolute(web)
	for f in ["index.html", "index.js", "index.wasm", "index.pck"]:
		FileAccess.open(web.path_join(f), FileAccess.WRITE).store_string("v1 " + f)
	FileAccess.open(web.path_join("build_info.json"), FileAccess.WRITE).store_string(JSON.stringify({"build_id": "aaaaaaaaaaaaaaaa", "built": "x"}))
	srv = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, web)
	port = listen_on_free_port(func(p: int) -> String: return srv.start(p, "127.0.0.1"), "Phone Link")
	var p := Probe.new(tree)
	var r: Dictionary = await p.request("127.0.0.1", port, Probe.get_req("/game/aaaaaaaaaaaaaaaa/index.wasm"))
	eq(r.body.get_string_from_utf8(), "v1 index.wasm", "the current build is served")
	# The phone version is rebuilt while Phone Link is on.
	for f in ["index.html", "index.js", "index.wasm", "index.pck"]:
		FileAccess.open(web.path_join(f), FileAccess.WRITE).store_string("v2 " + f)
	FileAccess.open(web.path_join("build_info.json"), FileAccess.WRITE).store_string(JSON.stringify({"build_id": "bbbbbbbbbbbbbbbb", "built": "y"}))
	srv.refresh_page_info()
	r = await p.request("127.0.0.1", port, Probe.get_req("/game/aaaaaaaaaaaaaaaa/index.html"))
	check(r.code == 410 and not r.headers.has("location"), "the old build's address: 410 Gone, no redirect")
	r = await p.request("127.0.0.1", port, Probe.get_req("/game/bbbbbbbbbbbbbbbb/index.wasm"))
	eq(r.body.get_string_from_utf8(), "v2 index.wasm", "the new one is served at its own address")
	eq(str(r.headers.get("cache-control", "")), "no-store", "never cached")
	r = await p.request("127.0.0.1", port, Probe.get_req("/"))
	eq(str(r.headers.get("cache-control", "")), "no-store", "the launcher page is never cached either")
	await _stop()


func test_address_choice_with_virtual_adapters() -> void:
	var routes := """Interface List
  5...00 15 5d 01 02 03 ......Hyper-V Virtual Ethernet Adapter
  6...00 15 5d 04 05 06 ......Hyper-V Virtual Ethernet Adapter #2
  7...........................NordLynx Tunnel
 17...0a 00 27 00 00 11 ......VirtualBox Host-Only Ethernet Adapter
 12...30 c5 99 d7 b1 81 ......Intel(R) Wi-Fi 6 AX201 160MHz
  9...........................Tailscale Tunnel
===========================================================================
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.20     35
          0.0.0.0          0.0.0.0        10.5.0.1         10.5.0.2      5
===========================================================================
"""
	var interfaces := [
		{"index": "5", "name": "vEthernet (WSL)", "friendly": "vEthernet (WSL)", "addresses": ["172.28.80.1"]},
		{"index": "6", "name": "vEthernet (Default Switch)", "friendly": "vEthernet (Default Switch)", "addresses": ["172.17.112.1"]},
		{"index": "7", "name": "NordLynx", "friendly": "NordLynx", "addresses": ["10.5.0.2"]},
		{"index": "17", "name": "Ethernet 2", "friendly": "Ethernet 2", "addresses": ["192.168.56.1"]},
		{"index": "12", "name": "Wi-Fi", "friendly": "Wi-Fi", "addresses": ["192.168.1.20", "fe80::5"]},
		{"index": "9", "name": "Tailscale", "friendly": "Tailscale", "addresses": ["100.64.0.10"]},
		{"index": "20", "name": "Bluetooth", "friendly": "Bluetooth Network Connection", "addresses": ["169.254.3.4"]},
		{"index": "1", "name": "Loopback", "friendly": "Loopback Pseudo-Interface 1", "addresses": ["127.0.0.1"]},
	]
	var ranked := NetRules.rank_addresses(interfaces, routes)
	eq(PhoneServer.pick_lan(ranked), "192.168.1.20", "the Wi-Fi with the home router wins over WSL, Hyper-V, a VPN with a lower metric, and VirtualBox")
	for c in ranked:
		if str(c.ip) in ["172.28.80.1", "172.17.112.1", "10.5.0.2", "192.168.56.1"]:
			check(bool(c.virtual), "%s (%s) is marked as not for phones" % [c.ip, c.label])
	check(not ranked.any(func(c): return str(c.ip) in ["127.0.0.1", "169.254.3.4"]), "loopback and link-local are never offered")


func test_ports_are_browser_safe_and_fall_back() -> void:
	for p in PhoneServer.SAFE_PORTS + PingServer.PORTS + Firewall.PORTS:
		check(not int(p) in PhoneServer.UNSAFE_PORTS, "port %d is one browsers will open" % int(p))
	for p in PhoneServer.SAFE_PORTS + PingServer.PORTS:
		check(int(p) in Firewall.PORTS, "the firewall helper covers port %d" % int(p))
	eq(PhoneServer.DEFAULT_PORT, 8765, "the default is the fixed port 8765")
	# 8765 taken (here on 127.0.0.1): Phone Link moves to the next safe port.
	var root := fresh_save_root()
	var block := TCPServer.new()
	var held := block.listen(8765, "127.0.0.1") == OK
	srv = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, root.path_join("no_web"))
	eq(srv.start_on_safe_port(8765, "127.0.0.1"), "", "starts anyway")
	if held:
		check(int(srv.port) != 8765, "on another safe port when 8765 is taken (got %d)" % int(srv.port))
	check(int(srv.port) in PhoneServer.SAFE_PORTS, "a port from the safe list")
	block.stop()
	await _stop()
