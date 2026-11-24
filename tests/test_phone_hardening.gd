extends "res://tests/test_case.gd"
## [PAIRING] Phone Link hardening around the pages: DNS rebinding (a web page pointing its own name at
## this PC is refused before anything is served, while every way a phone really reaches the PC still
## works) and the headers on the pages Polox writes itself (a Content-Security-Policy that allows only
## their own inline code and this address, no framing).
## Tags: [PAIRING]

const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const Probe := preload("res://tests/http_probe.gd")

var server: Node
var port := 0


func _start() -> void:
	var root := fresh_save_root()
	StarterContent.create_world("Hardened World", "Sam")
	GameState.load_world()
	JsonUtil.ensure_dir(root.path_join("_web"))
	server = PhoneServer.new()
	tree.root.add_child(server)
	server.setup(root, root.path_join("_web"))
	server.mode = "lan"
	port = listen_on_free_port(func(p: int) -> String: return server.start(p, "127.0.0.1"), "Phone Link")


func _stop() -> void:
	server.stop()
	server.queue_free()
	await frames(1)


func test_which_names_are_this_pcs() -> void:
	for ok in ["", "192.168.1.20:8765", "127.0.0.1:8765", "[::1]:8765", "[fd7a:115c:a1e0::1]:8765", "localhost:8765", "x",
			"DESKTOP-TEST:8765", "desktop-test.local", "desktop-test.fritz.box", "polox.lan:8765", "pc.home.arpa",
			"desktop-test.tail000.ts.net:8765", "phone-link.internal"]:
		check(PhoneServer.host_allowed(ok), "%s: served" % ok)
	for bad in ["evil.example.com", "evil.example.com:8765", "127.0.0.1.nip.io", "rebind.attacker.net:8765", "desktop-test.evil.org", "localhost.attacker.com", "desktop-test.local.evil.org"]:
		check(not PhoneServer.host_allowed(bad), "%s: refused (a public name could point anywhere, even one with the PC's name in it)" % bad)


func test_a_rebinding_page_gets_nothing() -> void:
	await _start()
	var probe := Probe.new(tree)
	for path in ["/hello.json", "/", "/api/pairing?wrap=1", "/hello"]:
		var r: Dictionary = await probe.request("127.0.0.1", port, Probe.get_req(path, {}, "rebind.attacker.example:%d" % port))
		eq(int(r.code), 403, "%s through a public name: refused" % path)
		check(not (r.body as PackedByteArray).get_string_from_utf8().contains("canonical"), "%s: nothing about the PC in the refusal" % path)
	var mine: Dictionary = await probe.request("127.0.0.1", port, Probe.get_req("/hello.json", {}, "127.0.0.1:%d" % port))
	eq(int(mine.code), 200, "the same request by address works")
	await _stop()


func test_polox_pages_carry_a_strict_content_security_policy() -> void:
	await _start()
	var probe := Probe.new(tree)
	for path in ["/", "/hello", "/app"]:
		var r: Dictionary = await probe.request("127.0.0.1", port, Probe.get_req(path))
		eq(int(r.code), 200, path)
		var csp := str(r.headers.get("content-security-policy", ""))
		for part in ["default-src 'none'", "script-src 'unsafe-inline'", "connect-src 'self'", "frame-ancestors 'none'", "base-uri 'none'", "form-action 'self'"]:
			check(csp.contains(part), "%s: %s" % [path, part])
		check(not csp.contains("http:") and not csp.contains("https:") and not csp.contains("*"), "%s: nothing from elsewhere" % path)
		eq(str(r.headers.get("x-frame-options", "")), "DENY", "%s: no framing (older browsers)" % path)
		check(not (r.body as PackedByteArray).get_string_from_utf8().contains("<script src"), "%s: every script is inline (what the policy allows)" % path)
	await _stop()
