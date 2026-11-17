extends "res://tests/test_case.gd"
## Phase 13: the rebuilt Phone Link core. Address rules and ranking (from a
## recorded `route print`), Tailscale parsing and Serve commands (recorded
## JSON + a fake CLI: Polox's real Tailscale is never changed by tests), the
## HTTP engine (ETag/304, HEAD, OPTIONS, Range, gzip, MIME, timeouts, many
## connections at once, idle and slow clients, aborted downloads, a crashing
## handler, the source allow-list), the three modes, the Tailscale login
## guard, /hello and the request log, and the Web build post-process.

const NetRules := preload("res://scripts/phone/net_rules.gd")
const Tailscale := preload("res://scripts/phone/tailscale.gd")
const HttpServer := preload("res://scripts/phone/http_server.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const WebBuild := preload("res://scripts/phone/web_build.gd")
const Firewall := preload("res://scripts/phone/firewall.gd")
const Probe := preload("res://tests/http_probe.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")

const ROUTES := """Interface List
  9...........................Tailscale Tunnel
 17...0a 00 27 00 00 11 ......VirtualBox Host-Only Ethernet Adapter
 12...30 c5 99 d7 b1 81 ......Realtek PCIe GbE Family Controller #2
  1...........................Software Loopback Interface 1
===========================================================================
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.42     25
===========================================================================
Persistent Routes:
  None
"""
const INTERFACES := [
	{"index": "9", "name": "Tailscale", "friendly": "Tailscale", "addresses": ["100.64.0.10", "fd7a:115c:a1e0::1"]},
	{"index": "17", "name": "Ethernet 2", "friendly": "Ethernet 2", "addresses": ["192.168.56.1", "fe80::1"]},
	{"index": "12", "name": "Ethernet 4", "friendly": "Ethernet 4", "addresses": ["192.168.1.42"]},
	{"index": "20", "name": "Wi-Fi", "friendly": "Wi-Fi", "addresses": ["169.254.10.2"]},
	{"index": "1", "name": "Loopback", "friendly": "Loopback Pseudo-Interface 1", "addresses": ["127.0.0.1", "::1"]},
]
const STATUS_JSON := """{"Version":"1.102.2","BackendState":"Running","TailscaleIPs":["100.64.0.10"],
 "Self":{"ID":"n1","UserID":123456789012,"HostName":"DESKTOP-TEST","DNSName":"desktop-test.tail000.ts.net.","OS":"windows","TailscaleIPs":["100.64.0.10","fd7a:115c:a1e0::1"],"Online":true},
 "MagicDNSSuffix":"tail000.ts.net","CurrentTailnet":{"Name":"me@example.com","MagicDNSSuffix":"tail000.ts.net","MagicDNSEnabled":true},
 "CertDomains":["desktop-test.tail000.ts.net"],
 "User":{"123456789012":{"ID":123456789012,"LoginName":"me@example.com","DisplayName":"Me"}},
 "Peer":{"nodekey:abc":{"HostName":"Phone","OS":"android","Online":false,"TailscaleIPs":["100.73.1.2"]}}}"""


## A stand-in for the tailscale CLI: answers like the real one and remembers Serve mappings.
class FakeTs:
	extends RefCounted
	var calls: Array = []
	var mappings := {"443": "http://127.0.0.1:3000", "8443": "http://127.0.0.1:3200"}
	var funnel := {"8443": true}
	var status_json := ""
	var needs_https := false

	func run(args: PackedStringArray, _timeout: float) -> Dictionary:
		calls.append(" ".join(args))
		if args.size() >= 2 and args[0] == "status":
			return {"code": 0, "out": status_json}
		if args.size() >= 2 and args[0] == "serve" and args[1] == "status":
			var web := {}
			var tcp := {}
			var fun := {}
			for p in mappings:
				tcp[p] = {"HTTPS": true}
				web["desktop-test.tail000.ts.net:%s" % p] = {"Handlers": {"/": {"Proxy": mappings[p]}}}
				if funnel.has(p):
					fun["desktop-test.tail000.ts.net:%s" % p] = true
			return {"code": 0, "out": JSON.stringify({"TCP": tcp, "Web": web, "AllowFunnel": fun})}
		if args.size() >= 3 and args[0] == "serve" and args[1] == "--bg":
			if needs_https:
				return {"code": 1, "out": "Serve is not enabled on your tailnet.\nTo enable, visit:\n\n         https://login.tailscale.com/f/serve?node=abc123\n"}
			mappings[args[2].trim_prefix("--https=")] = args[3]
			return {"code": 0, "out": "Available within your tailnet:\n"}
		if args.size() == 3 and args[0] == "serve" and args[2] == "off":
			mappings.erase(args[1].trim_prefix("--https="))
			return {"code": 0, "out": ""}
		return {"code": 1, "out": "unknown command"}


func test_address_kinds_and_scopes() -> void:
	eq(NetRules.normalize_ip("::ffff:192.168.1.5"), "192.168.1.5", "IPv4-mapped IPv6 is the IPv4 address")
	eq(NetRules.normalize_ip("[FE80::1%12]"), "fe80::1")
	var kinds := {
		"127.0.0.1": "loopback", "::1": "loopback", "192.168.1.42": "private", "10.1.2.3": "private",
		"172.20.1.1": "private", "172.32.0.1": "public", "169.254.3.4": "link_local", "100.64.0.10": "tailscale",
		"100.128.0.1": "public", "8.8.8.8": "public", "fd7a:115c:a1e0::5": "tailscale", "fe80::abcd": "link_local",
		"fd00::1": "private", "2001:4860::8888": "public", "nonsense": "invalid", "999.1.1.1": "invalid",
	}
	for ip in kinds:
		eq(NetRules.kind(ip), kinds[ip], "kind of " + ip)
	for ip in ["8.8.8.8", "2001:4860::8888", "100.128.0.1", "nonsense"]:
		for scope in NetRules.SCOPES:
			check(not NetRules.source_allowed(ip, scope), "%s never allowed (%s)" % [ip, scope])
	check(NetRules.source_allowed("127.0.0.1", "local") and not NetRules.source_allowed("192.168.1.42", "local"), "local: this PC only")
	check(NetRules.source_allowed("100.73.1.2", "tailscale") and not NetRules.source_allowed("192.168.1.50", "tailscale"), "tailscale-only refuses the home network")
	check(NetRules.source_allowed("192.168.1.50", "home") and NetRules.source_allowed("100.73.1.2", "home") and NetRules.source_allowed("169.254.1.1", "home"), "home: home networks + Tailscale")


func test_address_ranking_skips_virtual_and_loopback() -> void:
	var routes := NetRules.parse_default_routes(ROUTES)
	eq(routes.size(), 1)
	eq(str(routes[0].interface_ip), "192.168.1.42")
	eq(str(NetRules.parse_interface_list(ROUTES).get(17, "")), "VirtualBox Host-Only Ethernet Adapter")
	var ranked := NetRules.rank_addresses(INTERFACES, ROUTES)
	eq(ranked.map(func(c): return c.ip), ["100.64.0.10", "192.168.1.42", "192.168.56.1"], "Tailscale, then the gateway adapter, then virtual; no 127/169.254/IPv6")
	check(bool(ranked[2].virtual) and str(ranked[2].reason).contains("can't reach"), "VirtualBox is marked unreachable")
	# Without the route table: VirtualBox is still recognised by its address.
	var blind := NetRules.rank_addresses(INTERFACES, "")
	eq(blind.map(func(c): return c.ip), ["100.64.0.10", "192.168.1.42", "192.168.56.1"])
	check(bool(blind[2].virtual))


func test_tailscale_status_and_serve_parsing() -> void:
	var s := Tailscale.parse_status(STATUS_JSON)
	check(s.running and s.logged_in and s.magicdns and s.https, "running, MagicDNS, HTTPS certs")
	eq(str(s.dns_name), "desktop-test.tail000.ts.net", "name without the trailing dot")
	eq(str(s.ipv4), "100.64.0.10")
	eq(str(s.login), "me@example.com", "your login (numeric user ids handled)")
	eq((s.peers as Array).size(), 1)
	eq(str(s.peers[0].os), "android")
	var off := Tailscale.parse_status('{"BackendState":"NeedsLogin","Self":{}}')
	check(not off.running and str(off.error).contains("not logged in"))
	check(not Tailscale.parse_status("", false).installed)
	check(str(Tailscale.parse_status("").error).contains("didn't answer"))
	check(not Tailscale.parse_status(STATUS_JSON.replace('"CertDomains":["desktop-test.tail000.ts.net"],', "")).https, "no certificates: no HTTPS")
	var fake := FakeTs.new()
	fake.status_json = STATUS_JSON
	var ts := Tailscale.new("x")
	ts.runner = fake.run
	var sv := ts.serve_status("desktop-test.tail000.ts.net")
	eq(str(sv.ports["443"].proxy), "http://127.0.0.1:3000", "your own mappings are read...")
	check(sv.funnel.has("8443"), "...including which one Funnel exposes")
	eq(Tailscale.find_consent_url("To enable, visit:\n  https://login.tailscale.com/f/serve?node=abc123\n"), "https://login.tailscale.com/f/serve?node=abc123")


func test_serve_mapping_is_polox_only() -> void:
	var fake := FakeTs.new()
	fake.status_json = STATUS_JSON
	var ts := Tailscale.new("x")
	ts.runner = fake.run
	var name := "desktop-test.tail000.ts.net"
	# A port someone else uses is never taken over.
	var clash := ts.serve_on(8443, 8737, name)
	check(not clash.ok and str(clash.error).contains("already used"), "refuses another app's port")
	eq(fake.mappings["8443"], "http://127.0.0.1:3200", "and leaves it alone")
	var on := ts.serve_on(8737, 8737, name)
	check(on.ok, "Polox's own port: " + str(on.error))
	check("serve --bg --https=8737 http://127.0.0.1:8737" in fake.calls, "the current Serve command form")
	check(not on.funnel, "not on Funnel")
	var off := ts.serve_off(8737, 8737, name)
	check(off.ok and not fake.mappings.has("8737"), "removed again")
	check("serve --https=8737 off" in fake.calls, "removes only its own port (never `serve reset`)")
	eq(fake.mappings.size(), 2, "your other mappings are untouched")
	for c in fake.calls:
		check(not str(c).contains("reset") and not str(c).contains("funnel"), "never resets, never touches Funnel: " + str(c))
	# Someone replaced Polox's mapping meanwhile: hands off.
	fake.mappings["8737"] = "http://127.0.0.1:9999"
	check(not ts.serve_off(8737, 8737, name).ok and fake.mappings["8737"] == "http://127.0.0.1:9999", "another mapping on that port is left alone")
	# The tailnet hasn't enabled HTTPS: the consent page is passed on.
	fake.mappings.erase("8737")
	fake.needs_https = true
	var consent := ts.serve_on(8737, 8737, name)
	check(not consent.ok and str(consent.consent_url).begins_with("https://login.tailscale.com/"), "consent URL shown to you")


func _static_dir(root: String = "") -> String:
	var dir := (root if root != "" else fresh_save_root()).path_join("_web")
	JsonUtil.ensure_dir(dir)
	var big := PackedByteArray()
	big.resize(1_500_000)
	for i in big.size():
		big[i] = (i * 7 + i / 300) % 251
	var f := FileAccess.open(dir.path_join("index.wasm"), FileAccess.WRITE)
	f.store_buffer(big)
	f.close()
	var gz := FileAccess.open(dir.path_join("index.wasm.gz"), FileAccess.WRITE)
	gz.store_buffer(big.compress(FileAccess.COMPRESSION_GZIP))
	gz.close()
	var h := FileAccess.open(dir.path_join("index.html"), FileAccess.WRITE)
	h.store_string("<!doctype html><title>t</title>")
	h.close()
	return dir


func _http(dir: String, extras: bool = false) -> Node:
	var s: Node = HttpServer.new()
	tree.root.add_child(s)
	s.static_dir = dir
	s.allow_etag = extras   # the optional extras (off by default since Update 5)
	s.allow_gzip = extras
	s.allow_range = extras
	s.header_timeout_ms = 800
	s.idle_timeout_ms = 1500
	listen_on_free_port(func(p: int) -> String: return s.start(p, "127.0.0.1"), "the engine")
	return s


## Update 5: by default every file goes out plain and whole: no ETag/304, no
## Range, no gzip, never cached, always Content-Length and Connection: close.
func test_static_files_are_plain_by_default() -> void:
	var dir := _static_dir()
	var s := _http(dir)
	var p := Probe.new(tree)
	var want := FileAccess.get_file_as_bytes(dir.path_join("index.wasm"))
	var r: Dictionary = await p.request("127.0.0.1", s.port, Probe.get_req("/index.wasm", {"Accept-Encoding": "gzip, deflate", "Range": "bytes=0-99", "If-None-Match": "*"}))
	eq(r.code, 200, "a Range or If-None-Match header still gets the whole file")
	eq(Probe.sha(r.body), Probe.sha(want), "every byte, not gzipped")
	eq(int(r.headers.get("content-length", "-1")), want.size(), "Content-Length")
	eq(str(r.headers.get("connection", "")), "close", "Connection: close")
	eq(str(r.headers.get("cache-control", "")), "no-store", "never cached (a phone can't keep a broken copy)")
	check(not r.headers.has("etag") and not r.headers.has("content-encoding") and not r.headers.has("transfer-encoding"), "no ETag, no gzip, never chunked")
	eq(str(r.headers.get("accept-ranges", "")), "none", "says it doesn't do ranges")
	s.stop()
	s.queue_free()


func test_static_files_etag_head_range_gzip() -> void:
	var dir := _static_dir()
	var s := _http(dir, true)
	var p := Probe.new(tree)
	var want := FileAccess.get_file_as_bytes(dir.path_join("index.wasm"))
	var full: Dictionary = await p.request("127.0.0.1", s.port, Probe.get_req("/index.wasm"))
	eq(full.code, 200)
	eq(str(full.headers.get("content-type", "")), "application/wasm", ".wasm is application/wasm")
	eq(int(full.headers.get("content-length", "0")), want.size(), "Content-Length")
	eq(Probe.sha(full.body), Probe.sha(want), "every byte, in order")
	eq(str(full.headers.get("cache-control", "")), "no-cache", "re-checked each time...")
	var etag := str(full.headers.get("etag", ""))
	check(etag != "", "...with an ETag")
	var cached: Dictionary = await p.request("127.0.0.1", s.port, Probe.get_req("/index.wasm", {"If-None-Match": etag}))
	eq(cached.code, 304, "unchanged: 304, nothing downloaded again")
	eq(cached.body.size(), 0)
	var head: Dictionary = await p.request("127.0.0.1", s.port, "HEAD /index.wasm HTTP/1.1\r\nHost: x\r\n\r\n")
	eq(head.code, 200)
	eq(head.body.size(), 0, "HEAD: headers only")
	eq(int(head.headers.get("content-length", "0")), want.size())
	var part: Dictionary = await p.request("127.0.0.1", s.port, Probe.get_req("/index.wasm", {"Range": "bytes=1000-1999"}))
	eq(part.code, 206)
	eq(str(part.headers.get("content-range", "")), "bytes 1000-1999/%d" % want.size())
	eq(Probe.sha(part.body), Probe.sha(want.slice(1000, 2000)), "the right 1000 bytes")
	var tail: Dictionary = await p.request("127.0.0.1", s.port, Probe.get_req("/index.wasm", {"Range": "bytes=-500"}))
	eq(Probe.sha(tail.body), Probe.sha(want.slice(want.size() - 500)), "suffix range")
	var bad: Dictionary = await p.request("127.0.0.1", s.port, Probe.get_req("/index.wasm", {"Range": "bytes=99999999-"}))
	eq(bad.code, 416, "impossible range")
	var zipped: Dictionary = await p.request("127.0.0.1", s.port, Probe.get_req("/index.wasm", {"Accept-Encoding": "gzip, deflate, br"}))
	eq(str(zipped.headers.get("content-encoding", "")), "gzip", "gzip when the browser takes it")
	check(zipped.body.size() < want.size(), "smaller on the wire")
	eq(Probe.sha(zipped.body.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)), Probe.sha(want), "and unzips to the same file")
	var opt: Dictionary = await p.request("127.0.0.1", s.port, "OPTIONS /index.wasm HTTP/1.1\r\nHost: x\r\n\r\n")
	eq(opt.code, 204)
	check(str(opt.headers.get("allow", "")).contains("HEAD"))
	for path in ["/../secret", "/.git", "/folder/x.html", "/index.exe", "/%2e%2e/x.html"]:
		eq((await p.request("127.0.0.1", s.port, Probe.get_req(path))).code, 404, "no files outside the build: " + path)
	s.stop()
	s.queue_free()


func test_many_connections_idle_slow_and_aborted() -> void:
	var dir := _static_dir()
	var s := _http(dir)
	var p := Probe.new(tree)
	var want := Probe.sha(FileAccess.get_file_as_bytes(dir.path_join("index.wasm")))
	# Idle "speculative" sockets that never send anything...
	var idle: Array = []
	for i in 10:
		idle.append(await p.connect_peer("127.0.0.1", s.port))
	# ...don't stop 8 downloads at once.
	var reqs: Array = []
	for i in 8:
		reqs.append(Probe.get_req("/index.wasm"))
	var all: Array = await p.parallel("127.0.0.1", s.port, reqs)
	var good := 0
	for r in all:
		if int(r.code) == 200 and Probe.sha(r.body) == want:
			good += 1
	eq(good, 8, "8 parallel downloads complete and identical")
	# The idle ones are dropped after the header timeout.
	var t := Time.get_ticks_msec()
	while s.open_connections() > 0 and Time.get_ticks_msec() - t < 4000:
		await frames(5)
	eq(s.open_connections(), 0, "idle sockets closed by the server")
	for peer in idle:
		(peer as StreamPeerTCP).poll()
		check((peer as StreamPeerTCP).get_status() != StreamPeerTCP.STATUS_CONNECTED or (peer as StreamPeerTCP).get_available_bytes() == 0, "idle socket got nothing")
	# A slow client that sends its request in pieces (within the timeout) is served.
	var slow := await p.connect_peer("127.0.0.1", s.port)
	for piece in ["GET /index.h", "tml HTTP/1.1\r\n", "Host: x\r\n", "\r\n"]:
		slow.put_data(piece.to_utf8_buffer())
		await frames(3)
	var slow_r := Probe.parse_response(await p.read_all(slow))
	eq(slow_r.code, 200, "slow sender served")
	# A download dropped half-way frees its connection.
	var quitter := await p.connect_peer("127.0.0.1", s.port)
	quitter.put_data(Probe.get_req("/index.wasm").to_utf8_buffer())
	await frames(3)
	quitter.poll()
	quitter.disconnect_from_host()
	t = Time.get_ticks_msec()
	while s.open_connections() > 0 and Time.get_ticks_msec() - t < 4000:
		await frames(5)
	eq(s.open_connections(), 0, "aborted download cleaned up")
	# Too many at once: the extra ones get a quick 503, the server stays up.
	s.max_connections = 2
	var hogs := [await p.connect_peer("127.0.0.1", s.port), await p.connect_peer("127.0.0.1", s.port)]
	await frames(3)
	eq((await p.request("127.0.0.1", s.port, Probe.get_req("/index.html"))).code, 503, "over the cap: a quick 503 (and it arrives)")
	for h in hogs:
		(h as StreamPeerTCP).disconnect_from_host()
	t = Time.get_ticks_msec()
	while s.open_connections() > 0 and Time.get_ticks_msec() - t < 4000:
		await frames(5)
	eq((await p.request("127.0.0.1", s.port, Probe.get_req("/index.html"))).code, 200, "served again once there's room")
	s.stop()
	s.queue_free()


func test_a_crashing_handler_costs_one_request() -> void:
	var dir := _static_dir()
	var s := _http(dir)
	var p := Probe.new(tree)
	s.debug_fail_path = "/boom"
	s.api_handler = func(_req: Dictionary, _ip: String) -> Variant:
		return null   # a handler that "forgot" to answer
	print("[expect-script-error] a deliberate crash in the server thread follows")
	eq((await p.request("127.0.0.1", s.port, Probe.get_req("/boom"))).code, 500, "script error in the thread: 500")
	print("[/expect-script-error]")
	eq((await p.request("127.0.0.1", s.port, Probe.get_req("/api/whatever"))).code, 500, "bad API answer: 500")
	eq((await p.request("127.0.0.1", s.port, Probe.get_req("/index.html"))).code, 200, "and the server carries on")
	check(s.running and s.thread_restarts() == 0, "same thread, still running")
	s.stop()
	s.queue_free()


func test_source_allow_list() -> void:
	var dir := _static_dir()
	var s := _http(dir)
	var p := Probe.new(tree)
	var cases := [["8.8.8.8", "home", 403], ["203.0.113.9", "tailscale", 403], ["192.168.1.50", "home", 200],
		["192.168.1.50", "tailscale", 403], ["100.73.1.2", "tailscale", 200], ["192.168.1.50", "local", 403], ["127.0.0.1", "local", 200]]
	for c in cases:
		s.debug_peer_override = str(c[0])
		s.source_scope = str(c[1])
		eq((await p.request("127.0.0.1", s.port, Probe.get_req("/index.html"))).code, int(c[2]), "%s in scope %s" % [c[0], c[1]])
	s.debug_peer_override = ""
	var log: Array = s.recent(20)
	check(log.any(func(e): return str(e.ip) == "8.8.8.8" and int(e.status) == 403), "refusals are in the request log")
	s.stop()
	s.queue_free()


func _phone_server(root: String, fake: FakeTs, mode: String) -> Node:
	var srv: Node = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, _static_dir(root))
	srv.ts.runner = fake.run
	srv.ts.cli = "x"
	srv.mode = mode
	srv.serve_port = 8737
	return srv


func test_modes_serve_guard_hello_and_log() -> void:
	var root := fresh_save_root()
	StarterContent.create_world("T", "Sam")
	GameState.load_world()
	var fake := FakeTs.new()
	fake.status_json = STATUS_JSON
	var srv := _phone_server(root, fake, "tailscale_serve")
	eq(PhoneServer.listen_plan("tailscale_serve"), {"bind": "0.0.0.0", "scope": "home"}, "Serve mode also serves Same Wi-Fi (every address, home networks)")
	var port := listen_on_free_port(func(p: int) -> String: return srv.start(p, "127.0.0.1"), "Serve mode")
	eq(str(srv.http.source_scope), "home")
	eq(fake.mappings.get("8737", ""), "http://127.0.0.1:%d" % port, "published through Tailscale Serve")
	eq(srv.ts_url(), "https://desktop-test.tail000.ts.net:8737", "the Tailscale HTTPS address")
	check(srv.urls().has("https://desktop-test.tail000.ts.net:8737"), "is one of the addresses")
	if srv.lan_url() != "":
		eq(srv.canonical_url(), srv.lan_url(), "but the big one is the Same Wi-Fi address: " + srv.lan_url())
	var p := Probe.new(tree)
	var hello: Dictionary = await p.request("127.0.0.1", port, Probe.get_req("/hello"))
	eq(hello.code, 200)
	check(hello.body.get_string_from_utf8().contains("Polox host reachable"), "/hello says so")
	var hj: Dictionary = JSON.parse_string((await p.request("127.0.0.1", port, Probe.get_req("/hello.json"))).body.get_string_from_utf8())
	eq(str(hj.mode), "tailscale_serve")
	eq(str(hj.canonical), srv.canonical_url())
	# Through Serve: only your own Tailscale login gets in.
	var mine: Dictionary = await p.request("127.0.0.1", port, Probe.get_req("/hello", {"X-Forwarded-For": "100.73.1.2", "Tailscale-User-Login": "me@example.com"}))
	eq(mine.code, 200, "your phone through Serve")
	var other: Dictionary = await p.request("127.0.0.1", port, Probe.get_req("/hello", {"X-Forwarded-For": "100.80.9.9", "Tailscale-User-Login": "someone@example.com"}))
	eq(other.code, 403, "someone else's device on the tailnet")
	var tagged: Dictionary = await p.request("127.0.0.1", port, Probe.get_req("/hello", {"X-Forwarded-For": "100.80.9.9"}))
	eq(tagged.code, 403, "a device with no login")
	await frames(3)
	check(not srv.last_contact.is_empty() and str(srv.last_contact.via).contains("100.73.1.2"), "'Phone reached Polox' noticed (through Serve)")
	srv.http.call("_flush_log_file")
	var log_text := FileAccess.get_file_as_string(root.path_join("phone/phone_link.log"))
	check(log_text.contains("/hello") and log_text.contains("via tailscale-serve"), "phone_link.log has the requests")
	srv.stop()
	check(not fake.mappings.has("8737"), "Serve mapping removed when Phone Link stops")
	eq(fake.mappings.size(), 2, "your other mappings untouched")
	# Serve can't start: Same Wi-Fi still runs, and the reason is shown.
	fake.status_json = STATUS_JSON.replace('"CertDomains":["desktop-test.tail000.ts.net"],', "")
	port = listen_on_free_port(func(p: int) -> String: return srv.start(p, "127.0.0.1"), "Serve fallback")
	check(srv.running and str(srv.serve_result.get("error", "")).contains("HTTPS certificates"), "explains HTTPS certificates")
	check(srv.mode_text().contains("Tailscale part off"), "and says the Tailscale part is off: " + srv.mode_text())
	check(not fake.mappings.has("8737"), "nothing published")
	srv.stop()
	# Direct and Home Wi-Fi modes listen everywhere, with the allow-list.
	fake.status_json = STATUS_JSON
	srv.mode = "tailscale_direct"
	srv.tailscale_only = true
	eq(PhoneServer.listen_plan("tailscale_direct", true), {"bind": "0.0.0.0", "scope": "tailscale"}, "direct: every interface, Tailscale only")
	eq(PhoneServer.listen_plan("tailscale_direct", false), {"bind": "0.0.0.0", "scope": "home"})
	eq(PhoneServer.listen_plan("lan"), {"bind": "0.0.0.0", "scope": "home"}, "Home Wi-Fi: every interface, home networks")
	port = listen_on_free_port(func(p: int) -> String: return srv.start(p, "127.0.0.1"), "Tailscale direct")
	eq(str(srv.http.source_scope), "tailscale", "Tailscale only: home network refused")
	eq(srv.canonical_url(), "http://desktop-test.tail000.ts.net:%d" % port, "Tailscale only: the MagicDNS name is the main address")
	srv.stop()
	srv.mode = "lan"
	port = listen_on_free_port(func(p: int) -> String: return srv.start(p, "127.0.0.1"), "LAN mode")
	eq(str(srv.http.source_scope), "home")
	check(srv.canonical_url().begins_with("http://") and not srv.canonical_url().contains("127.0.0.1"), "a real network address: " + srv.canonical_url())
	srv.stop()
	srv.queue_free()


func test_log_rotates_and_holds_no_secrets() -> void:
	var dir := _static_dir()
	var s := _http(dir)
	var p := Probe.new(tree)
	var log_path := dir.path_join("phone_link.log")
	s.log_path = log_path
	s.log_file_max = 1500
	var token := "f".repeat(64)
	for i in 40:
		await p.request("127.0.0.1", s.port, Probe.get_req("/index.html?i=%d" % i, {"Authorization": "Bearer " + token}))
		if i % 10 == 9:
			s.call("_flush_log_file")
	s.call("_flush_log_file")
	check(FileAccess.file_exists(log_path + ".1"), "the log rotates")
	check(not FileAccess.file_exists(log_path + ".3"), "and keeps 3 files at most")
	var all := FileAccess.get_file_as_string(log_path) + FileAccess.get_file_as_string(log_path + ".1")
	check(all.contains("GET /index.html 200"), "requests are logged (path, status)")
	check(not all.contains(token) and not all.contains("Bearer"), "never the key")
	check(not all.contains("i=3"), "never the query string")
	s.stop()
	s.queue_free()


func test_phone_warns_about_a_different_address() -> void:
	var root := fresh_save_root()
	var srv: Node = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, _static_dir(root))
	srv.mode = "lan"
	var port := listen_on_free_port(func(p: int) -> String: return srv.start(p, "127.0.0.1"), "Phone Link")
	var PhoneMode: GDScript = load("res://scripts/phone/phone_mode.gd")
	var SyncClient: GDScript = load("res://scripts/phone/sync_client.gd")
	var pm: Node = PhoneMode.new()
	tree.root.add_child(pm)
	pm.client = SyncClient.new()
	pm.add_child(pm.client)
	pm.client.base_url = "http://127.0.0.1:%d" % port
	pm.origin = "http://127.0.0.1:%d" % port
	await pm.check_address()
	var canon: String = srv.canonical_url()
	check(canon != pm.origin and not pm.address_ok, "opened at 127.0.0.1, the PC's main address is %s: noticed" % canon)
	check(str(pm.startup_warning()).begins_with("Different address") and str(pm.startup_warning()).contains(canon), "and said plainly: " + str(pm.startup_warning()))
	pm.origin = canon
	await pm.check_address()
	check(pm.address_ok and pm.startup_warning() == "", "at the main address: no warning")
	pm.queue_free()
	srv.stop()
	srv.queue_free()


func test_web_build_postprocess() -> void:
	var dir := fresh_save_root().path_join("web")
	JsonUtil.ensure_dir(dir)
	for f in WebBuild.REQUIRED:
		var fa := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		fa.store_string("x".repeat(3000))
		fa.close()
	var html := FileAccess.open(dir.path_join("index.html"), FileAccess.WRITE)
	html.store_string("<html><head></head><body><script>\n\t" + str(WebBuild.HTML_PATCHES[0][0]) + "\n</script></body></html>")
	html.close()
	var js := FileAccess.open(dir.path_join("index.js"), FileAccess.WRITE)
	js.store_string("a;" + str(WebBuild.JS_PATCHES[0][0]) + ";b;" + str(WebBuild.JS_PATCHES[1][0]) + "{this.start()}" + "y".repeat(5000))
	js.close()
	check(not WebBuild.patched_on_disk(dir))
	var r := WebBuild.postprocess(dir)
	check(r.ok, str(r.error))
	eq(int(r.patched_html), 2, "the plain-HTTP fix and the start-up diagnostics")
	eq(int(r.patched_js), 2)
	check(WebBuild.patched_on_disk(dir), "both plain-HTTP patches are in")
	var again := WebBuild.postprocess(dir)
	check(again.ok and int(again.patched_html) == 0 and int(again.patched_js) == 0, "running it twice changes nothing")
	check("index.js" in r.gz, "gzip copy written")
	eq(FileAccess.get_file_as_bytes(dir.path_join("index.js.gz")).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP), FileAccess.get_file_as_bytes(dir.path_join("index.js")), "the .gz unzips to the file")
	var info := WebBuild.inspect(dir)
	check(info.present and info.complete and info.current and info.patched, "build_info.json: complete, current build, patched")
	eq(str(info.build_id), WebBuild.current_build_id())
	# A Godot page Polox doesn't know: a clear error, not a silent half-patch.
	var odd := FileAccess.open(dir.path_join("index.html"), FileAccess.WRITE)
	odd.store_string("<html>different engine</html>")
	odd.close()
	var bad := WebBuild.postprocess(dir)
	check(not bad.ok and str(bad.error).contains("Tailscale Serve"), "explains the HTTPS way still works")
	eq(WebBuild.preset_problems(), PackedStringArray(), "the Web preset: single-threaded, templates set")


func test_firewall_report_parsing() -> void:
	var sample := 'noise {"admin":false,"port":8737,"profiles_in_use":["Public","Private"],"networks":[{"alias":"Ethernet 4","category":"Public"}],"rules":[{"action":"Block","enabled":true,"profile":"Private, Public","protocol":"TCP","port":"Any"}],"blocking":1,"allowed":false,"ok":false}'
	var f := Firewall.parse_check(sample, 0)
	check(f.known and not f.ok, "read")
	eq(int(f.blocking), 1, "Windows' block rule found")
	eq(f.profiles, ["Public", "Private"])
	check(not Firewall.parse_check("garbage", 1).known, "unreadable: unknown, not 'fine'")
