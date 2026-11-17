extends "res://tests/test_case.gd"
## Phase 19 (Update 5, Connection Rescue): the honest reset and the ladder tools.
##   - the Phone Link settings upgrade through the REAL path (settings.json on
##     disk -> load with defaults -> configure), which Update 4's test skipped
##   - Polox Ping: every route, every kind of contact (nothing sent, HTTPS on the
##     HTTP port, garbage, a request trickled in byte by byte), a busy port, reports
##   - the report sink's limits and cleaning
##   - R0 PC facts: what each fact means (block rules, user-limited rules,
##     missing ports, Public, "block all incoming", VPN, loopback-only, sleep)
##   - the real host's contact log, /ping, /test, /api/report without a key
##   - the Doctor's "no device has contacted the host yet"
## Everything listens on 127.0.0.1 only.

const Probe := preload("res://tests/http_probe.gd")
const PingServer := preload("res://scripts/net/ping_server.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")
const NetFacts := preload("res://scripts/net/net_facts.gd")
const DiagRoutes := preload("res://scripts/net/diag_routes.gd")
const TestPage := preload("res://scripts/net/test_page.gd")
const BigFile := preload("res://scripts/net/big_file.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const PhoneDoctor := preload("res://scripts/phone/phone_doctor.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const PingView := preload("res://scripts/ui/ping_view.gd")
const Tailscale := preload("res://scripts/phone/tailscale.gd")


func _port() -> int:
	return free_port()


func _main() -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	return main


# --- The upgrade that never ran ------------------------------------------------------------------------

func _settings_on_disk() -> Dictionary:
	return JsonUtil.read_json(SaveManager.settings_path(), {})


func test_settings_upgrade_through_the_real_load_path() -> void:
	var root := fresh_save_root()
	check(not (Defaults.settings().phone_link as Dictionary).has("version"), "the defaults carry no version (loading merges them in)")
	# The user's real file (2026-10-08): Tailscale only, one phone, no version.
	JsonUtil.write_json(root.path_join("settings.json"), {"ai": {"preset": "mock"}, "phone_link": {"mode": "tailscale_direct", "tailscale_only": true, "max_devices": 1, "sync_slots": [], "port": 8737, "auto_off_hours": 6}})
	GameState.settings = SaveManager.load_settings()
	var main: Node = await _main()
	main.configure_phone_link()
	var pl: Dictionary = _settings_on_disk().get("phone_link", {})
	eq(bool(pl.get("tailscale_only", true)), false, "Tailscale only is off on disk")
	check(int(pl.get("max_devices", 0)) >= 4, "four phones allowed (%d)" % int(pl.get("max_devices", 0)))
	eq(int(pl.get("version", 0)), 4, "version 4 saved")
	eq(int(pl.get("port", 0)), 8765, "the old port 8737 moved to 8765")
	check(str(pl.get("upgraded_note", "")) != "", "with a note on the Phone Link screen")
	eq(bool(main.phone_link.tailscale_only), false, "and the running server isn't Tailscale-only")
	# A file Update 4 saved with version 2 from the defaults, Tailscale only still on.
	JsonUtil.write_json(root.path_join("settings.json"), {"phone_link": {"version": 2, "mode": "tailscale_direct", "tailscale_only": true, "max_devices": 1}})
	GameState.settings = SaveManager.load_settings()
	main.configure_phone_link()
	pl = _settings_on_disk().get("phone_link", {})
	eq(bool(pl.get("tailscale_only", true)), false, "version 2 from the defaults: fixed too")
	check(int(pl.get("max_devices", 0)) >= 2, "more than one phone")
	# Your own choice stays.
	JsonUtil.write_json(root.path_join("settings.json"), {"phone_link": {"version": 2, "mode": "tailscale_direct", "tailscale_only": true, "tailscale_only_chosen": true, "max_devices": 4}})
	GameState.settings = SaveManager.load_settings()
	main.configure_phone_link()
	eq(bool(_settings_on_disk().phone_link.get("tailscale_only", false)), true, "ticked by you: left alone")
	# Upgraded once: nothing changes the second time.
	check(not PhoneServer.upgrade_settings({"version": 4, "tailscale_only": true}), "already at version 4: untouched")
	var custom := {"version": 3, "port": 9123}
	PhoneServer.upgrade_settings(custom)
	eq(int(custom.port), 9123, "a port you chose yourself stays")
	main.queue_free()
	await frames(3)


# --- Polox Ping ---------------------------------------------------------------------------------------

func _ping(root: String, ports: Array) -> Node:
	var ping: Node = PingServer.new()
	tree.root.add_child(ping)
	eq(ping.start(root, ports, "127.0.0.1"), "", "Polox Ping starts")
	return ping


func _wait_contacts(ping: Node, n: int) -> void:
	var until := Time.get_ticks_msec() + 15000
	while ping.contact_total() < n and Time.get_ticks_msec() < until:
		await tree.create_timer(0.05).timeout


func test_ping_answers_everything_and_records_every_contact() -> void:
	var root := fresh_save_root()
	var busy := TCPServer.new()
	var busy_port := listen_on_free_port(func(p: int) -> int: return busy.listen(p, "127.0.0.1"), "busy port blocker")
	var a := 0
	var b := 0
	var ping: Node = null
	for _i in LISTEN_TRIES:
		a = _port()
		b = _port()
		var candidate: Node = PingServer.new()
		tree.root.add_child(candidate)
		if candidate.start(root, [a, busy_port, b], "127.0.0.1") == "" and candidate.ports_open == [a, b]:
			ping = candidate
			break
		candidate.stop()
		candidate.queue_free()
	if ping == null:
		ping = _ping(root, [a, busy_port, b])
	eq(ping.ports_open, [a, b], "listens on the free ports")
	check(ping.ports_failed.has(busy_port), "and says which port is taken")
	var p := Probe.new(tree)
	var r: Dictionary = await p.request("127.0.0.1", a, Probe.get_req("/ping"))
	eq(r.code, 200, "/ping")
	eq(r.body.get_string_from_utf8().strip_edges(), "Polox OK", "plain text Polox OK")
	eq(str(r.headers.get("connection", "")), "close", "Connection: close")
	eq(int(r.headers.get("content-length", "-1")), r.body.size(), "Content-Length matches")
	eq(str(r.headers.get("cache-control", "")), "no-store", "never cached")
	r = await p.request("127.0.0.1", b, Probe.get_req("/anything/at/all", {}, "192.168.1.42:8080"))
	eq(r.code, 200, "any other path answers too")
	var page: String = r.body.get_string_from_utf8()
	check(page.contains("Polox OK") and page.contains("/test") and page.contains("192.168.1.42:8080"), "the Polox OK page: where it was reached, and the test link")
	r = await p.request("127.0.0.1", a, Probe.get_req("/anything", {}, "<script>x</script>"))
	check(not r.body.get_string_from_utf8().contains("<script>x"), "a hostile Host header is escaped")
	r = await p.request("127.0.0.1", a, Probe.get_req("/test"))
	check(r.code == 200 and r.body.get_string_from_utf8().contains("Polox Connection Test"), "/test is the Connection Test page")
	r = await p.request("127.0.0.1", a, Probe.get_req("/favicon.ico"))
	check(r.code == 200 and str(r.headers.get("content-type", "")) == "image/png" and r.body.size() > 50, "a real favicon (browsers always ask; a 404 shows as an error)")
	r = await p.request("127.0.0.1", a, Probe.get_req("/test/info.json"))
	var info: Dictionary = JSON.parse_string(r.body.get_string_from_utf8())
	eq(str(info.server), "ping", "info: which server")
	eq(str(info.your_ip), "127.0.0.1", "info: the caller's address")
	r = await p.request("127.0.0.1", a, Probe.get_req("/test/big.json"))
	var meta: Dictionary = JSON.parse_string(r.body.get_string_from_utf8())
	eq(int(meta.size), BigFile.SIZE, "big file size")
	r = await p.request("127.0.0.1", a, Probe.get_req("/test/big"), 60000)
	eq(r.body.size(), BigFile.SIZE, "20 MB arrive")
	eq(Probe.sha(r.body), str(meta.sha256), "byte for byte (SHA-256)")
	r = await p.request("127.0.0.1", a, "HEAD /test/big HTTP/1.1\r\nHost: x\r\n\r\n")
	check(r.code == 200 and r.body.is_empty() and int(r.headers.get("content-length", "0")) == BigFile.SIZE, "HEAD: the size, no body")
	# A request that trickles in one byte at a time (phones split requests across packets).
	var slow := await p.connect_peer("127.0.0.1", a)
	for ch in Probe.get_req("/ping"):
		slow.put_data(ch.to_utf8_buffer())
		await frames(1)
	var sr := Probe.parse_response(await p.read_all(slow))
	check(sr.code == 200 and sr.body.get_string_from_utf8().contains("Polox OK"), "a request sent byte by byte is answered")
	var before: int = ping.contact_total()
	# Connected, sent nothing, hung up.
	var mute := await p.connect_peer("127.0.0.1", a)
	await frames(3)
	mute.disconnect_from_host()
	# A browser trying https:// on this http:// port (a TLS ClientHello starts with 0x16 0x03).
	var tls := await p.connect_peer("127.0.0.1", b)
	tls.put_data(PackedByteArray([0x16, 0x03, 0x01, 0x02, 0x00, 0x01, 0x00, 0x01, 0xfc, 0x03, 0x03]))
	await p.read_all(tls, 3000)
	# Garbage.
	var junk := await p.connect_peer("127.0.0.1", a)
	junk.put_data("HELLO THERE\r\n\r\n".to_utf8_buffer())
	await p.read_all(junk, 3000)
	await _wait_contacts(ping, before + 3)
	var outcomes: Array = ping.contacts(10).map(func(c): return str(c.outcome))
	check("nothing" in outcomes, "a contact that sent nothing is recorded (%s)" % str(outcomes))
	check("https" in outcomes, "HTTPS on the HTTP port is recognised")
	check("bad" in outcomes, "garbage is recorded as not a web request")
	check(PingServer.outcome_text({"outcome": "https"}).contains("http://"), "and explained in plain words")
	ping._flush_log()
	var log_text := FileAccess.get_file_as_string(root.path_join("phone/ping.log"))
	check(log_text.contains("sent no request") and log_text.contains("HTTPS"), "every contact is in ping.log")
	eq(ping.phone_contacts().size(), 0, "this PC's own checks aren't counted as a phone")
	ping.stop()
	busy.stop()
	ping.queue_free()


func test_reports_reach_the_pc_by_post_and_by_get() -> void:
	var root := fresh_save_root()
	var a := _port()
	var ping := _ping(root, [a])
	var p := Probe.new(tree)
	var rep := {"v": 1, "app": "Polox", "page": "test", "results": [{"id": "ping", "name": "GET /ping", "ok": true, "ms": 12, "detail": "ok"}, {"id": "big", "name": "Big download", "ok": false, "ms": 9000, "detail": "Stalled after 3.2 MB"}], "env": {"ua": "Mozilla/5.0 (Linux; Android 15) Chrome/140", "webgl2": true}, "hints": ["Keep the screen on."], "evil": "<b>x</b>"}
	var r: Dictionary = await p.request("127.0.0.1", a, Probe.with_body("POST", "/api/report", JSON.stringify(rep).to_utf8_buffer()))
	eq(r.code, 200, "POST /api/report without any key")
	var saved := ReportSink.load_saved(root, 5)
	eq(saved.size(), 1, "saved under phone_reports/")
	check(not saved[0].has("evil"), "unknown keys are dropped")
	eq(str(saved[0].from_ip), "127.0.0.1", "with the sender's address")
	check(ReportSink.summary(saved[0]).contains("Big download: Stalled after 3.2 MB"), "the summary names the failing rung: " + ReportSink.summary(saved[0]))
	# The short GET form, for when POST fails but GET works.
	var compact := {"v": 1, "c": 1, "s": "page:1:0,ping:1:20,big:0:15000", "d": "big=Failed after 0.0 MB: TypeError: Failed to fetch", "ua": "Mozilla/5.0 (iPhone) Safari", "a": "192.168.1.42:8765", "w": 1, "m": 1, "t": 4096}
	var enc := Marshalls.raw_to_base64(JSON.stringify(compact).to_utf8_buffer()).replace("+", "-").replace("/", "_").replace("=", "")
	r = await p.request("127.0.0.1", a, Probe.get_req("/api/report?r=" + enc))
	eq(r.code, 200, "GET /api/report?r=... works too")
	saved = ReportSink.load_saved(root, 5)
	eq(saved.size(), 2, "both saved")
	var short: Dictionary = saved[0] if str(saved[0].get("transport", "")) == "get" else saved[1]
	check(ReportSink.text(short).contains("Failed to fetch"), "the short form keeps the failing rung's error")
	eq(ping.sink.count(), 2, "Polox Ping shows them")
	ping.stop()
	ping.queue_free()


func test_report_sink_limits() -> void:
	var root := fresh_save_root()
	var sink := ReportSink.new(root)
	var ok := JSON.stringify({"v": 1, "results": []}).to_utf8_buffer()
	eq(int(sink.accept("8.8.8.8", ok, "post", "host")[0]), 403, "public addresses can't report")
	var big := PackedByteArray()
	big.resize(ReportSink.MAX_BYTES + 1)
	eq(int(sink.accept("192.168.1.40", big, "post", "host")[0]), 413, "too big")
	eq(int(sink.accept("192.168.1.40", "not json".to_utf8_buffer(), "post", "host")[0]), 400, "not a report")
	var codes: Array = []
	for i in 8:
		codes.append(int(sink.accept("192.168.1.41", ok, "post", "host")[0]))
	eq(codes.count(429), 2, "6 a minute per address, then 429 (%s)" % str(codes))
	eq(int(sink.accept("192.168.1.42", ok, "post", "host")[0]), 200, "another address isn't held up")
	var clean := ReportSink.sanitize_report({"hints": ["a\u0001b\u001bc"], "env": {"ua": "x".repeat(1000)}, "results": range(200)})
	eq(str(clean.hints[0]), "a b c", "control characters stripped")
	check(str(clean.env.ua).length() <= 300, "long text cut")
	check((clean.results as Array).size() <= 60, "long lists cut")
	eq(ReportSink.decode_get("").size(), 0, "empty GET form refused")
	eq(ReportSink.decode_get("x".repeat(ReportSink.MAX_GET + 1)).size(), 0, "oversized GET form refused")


func test_test_page_is_self_contained() -> void:
	var html := TestPage.html()
	check(not html.contains("<script src") and not html.contains("<link "), "no outside files")
	check(html.contains("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"), "the SHA-256 self-test vector is in the page")
	check(not TestPage.SCRIPT.contains("\\"), "no backslashes in the JavaScript")
	for needle in ["/ping", "/test/info.json", "/test/big.json", "/test/big", "/api/report", "webgl2", "WebAssembly", "indexedDB", "isSecureContext", "Local Network", "Copy report", "Send to PC", "Run again"]:
		check(html.contains(needle), "the page checks/offers " + needle)
	var r := DiagRoutes.handle({"method": "GET", "path": "/nope", "headers": {}}, {"server": "host"})
	check(r.is_empty(), "the host only answers its own test paths (the rest is Phone Link's)")
	r = DiagRoutes.handle({"method": "POST", "path": "/ping", "headers": {}}, {"server": "host"})
	check(r.is_empty(), "GET/HEAD only")


# --- R0: PC facts ----------------------------------------------------------------------------------------

const GODOT := "C:\\Users\\Player\\pocket-dark-world\\tools\\godot\\Godot_v4.7.2-stable_win64.exe"
const ME := "S-1-5-21-1-2-3-1001"


func _facts(extra: Dictionary = {}) -> Dictionary:
	var f := {
		"ok": true, "user_sid": ME, "computer": "DESKTOP-TEST",
		"listening": [{"address": "0.0.0.0", "port": 8765, "pid": 10, "process": "Godot_v4.7.2-stable_win64", "path": GODOT}],
		"adapters": [
			{"name": "Ethernet 4", "description": "Realtek PCIe GbE", "status": "Up", "ipv4": ["192.168.1.42/22"], "default_route": true, "gateway": "192.168.1.1", "metric": 25, "profile": "Private", "network": "Dog House", "power_off_allowed": ""},
			{"name": "Ethernet 2", "description": "VirtualBox Host-Only Ethernet Adapter", "status": "Up", "ipv4": ["192.168.56.1/24"], "default_route": false, "profile": "", "network": ""},
			{"name": "Tailscale", "description": "Tailscale Tunnel", "status": "Up", "ipv4": ["100.64.0.10/32"], "default_route": false, "profile": "Private"},
		],
		"firewall_profiles": [{"name": "Private", "enabled": true, "default_inbound": "Block", "allow_inbound_rules": true, "allow_local_rules": true}, {"name": "Public", "enabled": true, "default_inbound": "Block", "allow_inbound_rules": true, "allow_local_rules": true}],
		"rules": [
			{"name": "Polox Phone Link (Godot)", "action": "Allow", "enabled": true, "profile": "Private, Public", "protocol": "TCP", "port": "8765,8080,8888", "program": GODOT, "local_user": "", "for_this_program": true},
			{"name": "codex_sandbox_offline_block_inbound", "action": "Block", "enabled": true, "profile": "Any", "protocol": "Any", "port": "Any", "program": "Any", "local_user": "O:LSD:(A;;CC;;;S-1-5-21-1-2-3-1005)"},
		],
		"security_products": [{"kind": "AntiVirusProduct", "name": "Windows Defender", "state": 397568}],
		"vpn_connections": [], "sleep_ac_seconds": 0, "sleep_dc_seconds": 600, "errors": [],
	}
	f.merge(extra, true)
	return f


func _status(findings: Array, id: String) -> String:
	for f in findings:
		if str(f.id) == id:
			return str(f.status)
	return "(none)"


func _detail(findings: Array, id: String) -> String:
	for f in findings:
		if str(f.id) == id:
			return str(f.detail)
	return ""


func test_pc_facts_say_what_is_in_the_way() -> void:
	var ctx := {"ports": [8765], "programs": [GODOT]}
	var good := NetFacts.analyze(_facts(), ctx)
	eq(_status(good, "listen_8765"), "ok", "listening on 0.0.0.0 by Polox's Godot")
	eq(_status(good, "adapter"), "ok", "the home adapter is the one with the router")
	check(_detail(good, "adapter").contains("192.168.1.42") and not _detail(good, "adapter").contains("192.168.56"), "not VirtualBox")
	eq(_status(good, "firewall"), "ok", "allowed on 8765")
	eq(_status(good, "rule_other_user"), "ok", "a block rule for another Windows account (Codex's sandbox) doesn't count")
	eq(_status(good, "sleep"), "ok", "never sleeps on AC")
	# A Block rule for Polox's own program beats the allow rule.
	var f := _facts()
	f.rules.append({"name": "godot_v4.7.2-stable_win64.exe", "action": "Block", "enabled": true, "profile": "Public", "protocol": "TCP", "port": "Any", "program": GODOT, "local_user": ""})
	f.adapters[0].profile = "Public"
	var res := NetFacts.analyze(f, ctx)
	eq(_status(res, "firewall"), "fail", "a Block rule for Polox's Godot fails")
	check(_detail(res, "firewall").contains("godot_v4.7.2-stable_win64.exe"), "naming the rule")
	eq(_status(res, "profile"), "warn", "Public network type is pointed out")
	# The same block rule for every program (not limited to an account) blocks Polox too.
	f = _facts({"rules": [_facts().rules[0], {"name": "Block everything", "action": "Block", "enabled": true, "profile": "Any", "protocol": "Any", "port": "Any", "program": "Any", "local_user": ""}]})
	res = NetFacts.analyze(f, ctx)
	check(_status(res, "firewall") == "fail" and _detail(res, "firewall").contains("every program"), "a block-everything rule fails")
	# Only the old port is allowed (Update 4's 8737 rule) while Polox now uses 8765.
	f = _facts({"rules": [{"name": "Polox Phone Link (Godot)", "action": "Allow", "enabled": true, "profile": "Private, Public", "protocol": "TCP", "port": "8737", "program": GODOT, "local_user": ""}]})
	res = NetFacts.analyze(f, ctx)
	check(_status(res, "firewall") == "fail" and _detail(res, "firewall").contains("8765"), "a rule for another port doesn't cover 8765")
	# "Block all incoming connections" ignores every allow rule.
	f = _facts()
	f.firewall_profiles[0].allow_inbound_rules = false
	eq(_status(NetFacts.analyze(f, ctx), "shields_up"), "fail", "Block all incoming connections is caught")
	# Listening on loopback only, or the port belongs to someone else.
	f = _facts({"listening": [{"address": "127.0.0.1", "port": 8765, "pid": 10, "process": "Godot", "path": GODOT}]})
	eq(_status(NetFacts.analyze(f, ctx), "listen_8765"), "fail", "loopback only: a phone can't reach it")
	f = _facts({"listening": [{"address": "0.0.0.0", "port": 8765, "pid": 11, "process": "node", "path": "C:\\Program Files\\nodejs\\node.exe"}]})
	check(_detail(NetFacts.analyze(f, ctx), "listen_8765").contains("another program"), "another program has the port")
	f = _facts({"listening": []})
	eq(_status(NetFacts.analyze(f, ctx), "listen_8765"), "fail", "nothing listening")
	# VPN, sleep, other security software, adapter power saving.
	f = _facts({"sleep_ac_seconds": 600})
	f.adapters.append({"name": "NordLynx", "description": "NordLynx Tunnel", "status": "Up", "ipv4": ["10.5.0.2/16"], "default_route": false})
	f.security_products.append({"kind": "FirewallProduct", "name": "Norton Firewall", "state": 266240})
	f.adapters[0].power_off_allowed = "True"
	res = NetFacts.analyze(f, ctx)
	eq(_status(res, "vpn"), "warn", "a VPN on the PC is pointed out")
	check(_status(res, "sleep") == "warn" and _detail(res, "sleep").contains("10 minutes"), "sleep after 10 minutes is pointed out")
	eq(_status(res, "security"), "warn", "another firewall product is pointed out")
	eq(_status(res, "adapter_power"), "warn", "adapter power saving is pointed out")
	# No home adapter at all (the PC isn't on the network).
	f = _facts({"adapters": [_facts().adapters[1]]})
	eq(_status(NetFacts.analyze(f, ctx), "adapter"), "fail", "no home network adapter")
	# Helpers.
	check(NetFacts.port_covered("Any", 8765) and NetFacts.port_covered("8765,8080", 8080) and NetFacts.port_covered("8000-9000", 8765), "port lists, ranges, Any")
	check(not NetFacts.port_covered("8737", 8765), "another port isn't covered")
	eq(NetFacts.rule_users("O:LSD:(A;;CC;;;S-1-5-21-1-2-3-1005)"), PackedStringArray(["S-1-5-21-1-2-3-1005"]), "a rule's account from its SDDL")
	var parsed := NetFacts.parse('{"ok":true,"listening":{"address":"0.0.0.0","port":8765},"adapters":{"name":"Ethernet","ipv4":"192.168.1.5/24"},"rules":null}')
	check(parsed.listening is Array and parsed.adapters is Array and parsed.adapters[0].ipv4 is Array and parsed.rules is Array, "PowerShell's one-item lists are read as lists")
	check(not NetFacts.parse("oops", 1).get("ok", true), "a failed run says so")
	check(NetFacts.text(_facts()).contains("users S-1-5-21-1-2-3-1005"), "the text version shows which account a rule is for")


# --- The real host --------------------------------------------------------------------------------------

func test_host_records_every_contact_and_takes_reports() -> void:
	var root := fresh_save_root()
	var srv: Node = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, root.path_join("no_web"))
	var port := listen_on_free_port(func(p: int) -> String: return srv.start(p, "127.0.0.1"), "Phone Link")
	var got := [0]
	srv.report_received.connect(func(): got[0] += 1)
	var p := Probe.new(tree)
	var r: Dictionary = await p.request("127.0.0.1", port, Probe.get_req("/ping"))
	check(r.code == 200 and r.body.get_string_from_utf8().contains("Polox OK"), "the host answers /ping too")
	r = await p.request("127.0.0.1", port, Probe.get_req("/test/info.json"))
	eq(str(JSON.parse_string(r.body.get_string_from_utf8()).server), "host", "/test/info.json says it's the real host")
	r = await p.request("127.0.0.1", port, Probe.with_body("POST", "/api/report", JSON.stringify({"v": 1, "results": [{"id": "ping", "ok": true}]}).to_utf8_buffer()))
	eq(r.code, 200, "a report needs no key")
	for i in 20:
		await frames(1)
	eq(got[0], 1, "the PC hears about it")
	eq(ReportSink.load_saved(root, 3).size(), 1, "and keeps it")
	var mute := await p.connect_peer("127.0.0.1", port)
	await frames(3)
	mute.disconnect_from_host()
	var tls := await p.connect_peer("127.0.0.1", port)
	tls.put_data(PackedByteArray([0x16, 0x03, 0x01, 0x00, 0x05]))
	await p.read_all(tls, 3000)
	var until := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < until and not srv.http.contacts(20).any(func(c): return str(c.outcome) == "nothing"):
		await tree.create_timer(0.05).timeout
	var outcomes: Array = srv.http.contacts(20).map(func(c): return str(c.outcome))
	check("nothing" in outcomes and "https" in outcomes and "request" in outcomes, "every connection is a contact (%s)" % str(outcomes))
	await frames(5)
	var log_text := FileAccess.get_file_as_string(root.path_join("phone/phone_link.log"))
	check(log_text.contains("(connected, sent no request)") and log_text.contains("(HTTPS sent to this HTTP port)"), "and in phone_link.log")
	srv.stop()
	srv.queue_free()


func test_doctor_says_when_nothing_reached_the_host() -> void:
	var root := fresh_save_root()
	var snap := PhoneDoctor.snapshot(null)
	snap.running = true
	snap.bind = "127.0.0.1"
	snap.root = root
	var fw := '{"ok":true,"blocking":0,"allowed":true,"profiles_in_use":["Private"],"networks":[],"rules":[]}'
	var tailscale := Tailscale.new("fixture")
	tailscale.runner = func(_args: PackedStringArray, _timeout: float) -> Dictionary:
		return {"code": 0, "out": '{"BackendState":"Stopped"}'}
	var res := PhoneDoctor.run(snap, tailscale, fw)
	var contact: Array = res.filter(func(x): return str(x.id) == "contact")
	check(not contact.is_empty() and str(contact[0].detail).contains("No device has contacted the host yet"), "nothing at all: said plainly")
	snap.contacts = [{"t": Time.get_unix_time_from_system(), "ip": simulated_phone_ip(), "outcome": "https", "path": "", "status": 0}]
	res = PhoneDoctor.run(snap, tailscale, fw)
	contact = res.filter(func(x): return str(x.id) == "contact")
	check(str(contact[0].status) == "fail" and str(contact[0].detail).contains("HTTPS"), "reached, then failed: said differently")
	var sink := ReportSink.new(root)
	sink.accept("192.168.1.40", JSON.stringify({"v": 1, "results": [{"id": "env", "name": "What this browser can do", "ok": false, "detail": "Problems: no WebGL 2"}]}).to_utf8_buffer(), "post", "ping")
	res = PhoneDoctor.run(snap, tailscale, fw)
	var rep: Array = res.filter(func(x): return str(x.id) == "report")
	check(not rep.is_empty() and str(rep[0].status) == "fail" and str(rep[0].fix).contains("browser"), "a phone report shows in the Doctor with what to do")
	check(PhoneDoctor.diagnostics(snap, res).contains("Phone report:"), "and in Copy diagnostics")


func test_ping_banner_block_letters() -> void:
	var rows := PingView.big_text("192.168.1.42:8765")
	eq(rows.size(), 5, "five rows")
	check(rows[0].length() > 40 and not rows[0].contains("?"), "every character drawn")
