extends "res://tests/test_case.gd"
## [PAIRING] Signed requests (scripts/phone/request_sig.gd): a phone that paired with pair_v:1 signs
## every request and never sends its key. The signature covers the method, the path, every query field,
## the body and the time; each nonce opens one request; a clock far off gets the PC's time back and the
## phone corrects itself; that phone's bare key is refused while old-way phones keep their Bearer key;
## a proxy writing the address differently doesn't matter; /hello.json takes a signature too.
## Tags: [PAIRING]

const Pairing := preload("res://scripts/phone/pairing.gd")
const RequestSig := preload("res://scripts/phone/request_sig.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const SyncClient := preload("res://scripts/phone/sync_client.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const Probe := preload("res://tests/http_probe.gd")

var server: Node
var port := 0


func _start() -> void:
	var root := fresh_save_root()
	StarterContent.create_world("Signed World", "Sam")
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	JsonUtil.ensure_dir(root.path_join("_web"))
	server = PhoneServer.new()
	tree.root.add_child(server)
	server.setup(root, root.path_join("_web"))
	server.mode = "lan"
	port = listen_on_free_port(func(p: int) -> String: return server.start(p, "127.0.0.1"), "Phone Link")


func _stop() -> void:
	RequestSig.clock_offset = 0
	if server:
		server.stop()
		server.queue_free()
		server = null
	await frames(1)


## A request as the PC's parser sees it.
func _req(method: String, url: String, auth: String, body: String = "") -> Dictionary:
	var b := body.to_utf8_buffer()
	var bytes := ("%s %s HTTP/1.1\r\nHost: x\r\nAuthorization: %s\r\nContent-Length: %d\r\n\r\n" % [method, url, auth, b.size()]).to_utf8_buffer()
	bytes.append_array(b)
	return HttpUtil.parse(bytes)


func _auth(token: String, method: String, url: String, body: String = "") -> String:
	return RequestSig.header(token, method, url, body.to_utf8_buffer()).trim_prefix("Authorization: ")


## A phone paired the new way on `p`: its token.
func _signing_phone(p: RefCounted) -> String:
	var pin: String = p.new_code()
	var sealed := Pairing.seal_request(p.wrap_info(), pin)
	var answer: Dictionary = p.pair("", "Signing phone", "192.168.1.40", "", "sig1", sealed.body)
	return str(Pairing.open_answer(answer, pin, sealed.open).get("token", ""))


func test_the_signature_covers_every_part_of_the_request() -> void:
	var p := Pairing.new(fresh_save_root())
	var token := _signing_phone(p)
	check(token.length() == 64, "(a phone paired the new way)")
	var url := "/api/file?path=" + "slots/a/world.json".uri_encode() + "&base=" + "0".repeat(64)
	var body := "{\"tiles\":[1,2]}"
	var auth := _auth(token, "PUT", url, body)
	check(p.authenticate(_req("PUT", url, auth, body)).has("device"), "the signed request is the phone's")
	var changed := {
		"the method": _req("POST", url, _auth(token, "PUT", url, body), body),
		"the path": _req("PUT", url.replace("/api/file", "/api/files"), _auth(token, "PUT", url, body), body),
		"a query value": _req("PUT", url.replace("world.json", "other.json"), _auth(token, "PUT", url, body), body),
		"an added field": _req("PUT", url + "&slot=x", _auth(token, "PUT", url, body), body),
		"the body": _req("PUT", url, _auth(token, "PUT", url, body), body.replace("2", "3")),
		"another key": _req("PUT", url, _auth("ab".repeat(32), "PUT", url, body), body),
	}
	for what in changed:
		check(not p.authenticate(changed[what]).has("device"), "%s changed: refused" % what)
	var fields := RequestSig.parse(_auth(token, "GET", "/api/worlds"))
	for bad in ["v=2,ts=%d,nonce=%s,sig=%s" % [fields.ts, fields.nonce, fields.sig], "v=1,ts=%d,nonce=%s,sig=%s" % [fields.ts, "zz".repeat(16), fields.sig], "v=1,ts=x,nonce=%s,sig=%s" % [fields.nonce, fields.sig], "v=1"]:
		check(not p.authenticate(_req("GET", "/api/worlds", "Polox-Sig " + bad)).has("device"), "malformed: " + bad.left(30))
	var again := _req("GET", "/api/worlds", _auth(token, "GET", "/api/worlds"))
	check(p.authenticate(again).has("device"), "a fresh request")
	check(bool(p.authenticate(again).get("replayed", false)), "the same one again: a replay, refused")
	check(FileAccess.get_file_as_string(p.root.path_join("phone/audit.log")).contains("sig_replayed"), "and noted in audit.log")


func test_a_proxy_writing_the_address_differently_doesnt_matter() -> void:
	var a := RequestSig.target("/api/file?path=slots%2Fa%20b%2Fworld.json&base=1")
	eq(RequestSig.target("/api/file?base=1&path=slots/a+b/world.json"), a, "encoded or not, + or %20, any field order")
	eq(RequestSig.target("http://192.168.1.20:8765/api/file?path=slots/a%20b/world.json&base=1"), a, "a full address signs its path")
	check(RequestSig.target("/api/file?path=slots/a%20b/world.json&base=2") != a, "a different value is a different target")


func test_a_phone_that_signs_never_opens_anything_with_its_bare_key() -> void:
	var p := Pairing.new(fresh_save_root())
	var token := _signing_phone(p)
	check(not p.authenticate(_req("GET", "/api/worlds", "Bearer " + token)).has("device"), "its key as a Bearer header: refused")
	check(FileAccess.get_file_as_string(p.root.path_join("phone/audit.log")).contains("bearer_refused"), "noted in audit.log")
	var old_token := str(p.pair(p.new_code(), "Old phone", "192.168.1.41").token)
	check(p.authenticate(_req("GET", "/api/worlds", "Bearer " + old_token)).has("device"), "an old-way phone's Bearer key still works")
	check(p.authenticate(_req("GET", "/api/worlds", _auth(old_token, "GET", "/api/worlds"))).has("device"), "and it may sign too")


func test_a_clock_far_off_gets_the_pcs_time_and_corrects_itself() -> void:
	var p := Pairing.new(fresh_save_root())
	var token := _signing_phone(p)
	RequestSig.clock_offset = -3600
	var r: Dictionary = p.authenticate(_req("GET", "/api/worlds", _auth(token, "GET", "/api/worlds")))
	check(bool(r.get("clock", false)), "an hour behind: refused for the clock")
	check(absi(int(r.get("now", 0)) - int(Time.get_unix_time_from_system())) <= 2, "with the PC's time")
	check(RequestSig.learn_clock(r), "the phone takes it")
	check(absi(RequestSig.clock_offset) <= 2, "and is back in step (%d s)" % RequestSig.clock_offset)
	check(p.authenticate(_req("GET", "/api/worlds", _auth(token, "GET", "/api/worlds"))).has("device"), "then it's accepted")
	for bad in [{"now": "soon"}, {"now": 5}, {}, "x"]:
		RequestSig.clock_offset = 7
		check(not RequestSig.learn_clock(bad) and RequestSig.clock_offset == 7, "a nonsense time is ignored: %s" % str(bad))
	RequestSig.clock_offset = 0


func test_the_replay_memory_forgets_old_nonces() -> void:
	var p := Pairing.new(fresh_save_root())
	var token := _signing_phone(p)
	var now := Time.get_unix_time_from_system()
	for i in 1000:
		p._sig_nonces["%032x" % i] = now - 1.0
	p._sig_nonces_pruned = 0.0
	check(p.authenticate(_req("GET", "/api/worlds", _auth(token, "GET", "/api/worlds"))).has("device"), "a fresh request")
	eq(p._sig_nonces.size(), 1, "the expired nonces went, the fresh one stays")


func test_the_apps_client_signs_everything_over_http() -> void:
	await _start()
	var c := SyncClient.new()
	tree.root.add_child(c)
	c.base_url = "http://127.0.0.1:%d" % port
	c.local_root = server.root.path_join("_phone")
	JsonUtil.ensure_dir(c.local_root)
	var paired: Dictionary = await c.pair(server.pairing.code, "App phone", "app1")
	check(bool(paired.ok) and bool(paired.get("sig", false)) and c.sign, "paired the new way: it signs from now on")
	RequestSig.clock_offset = -3600   # its clock is an hour off: the first refusal brings the PC's time
	var s: Dictionary = await c.sync()
	check(bool(s.ok), "a whole sync, signed: %s" % str(s.get("error", "")))
	check(absi(RequestSig.clock_offset) <= 2, "the clock was corrected on the way (%d s)" % RequestSig.clock_offset)
	var hello: Dictionary = await c.request("GET", "/hello.json")
	check(hello.ok and (hello.json as Dictionary).has("urls"), "/hello.json in full for a signed request")
	var probe := Probe.new(tree)
	eq(int((await probe.request("127.0.0.1", port, Probe.get_req("/api/status", {"Authorization": "Bearer " + str(paired.token)}))).code), 401, "its bare key opens nothing")
	var raw := Probe.get_req("/api/status", {"Authorization": _auth(str(paired.token), "GET", "/api/status")})
	eq(int((await probe.request("127.0.0.1", port, raw)).code), 200, "a signed request does")
	eq(int((await probe.request("127.0.0.1", port, raw)).code), 401, "the same bytes again don't")
	var audit := FileAccess.get_file_as_string(server.root.path_join("phone/audit.log"))
	eq(audit.count("bearer_refused"), 1, "only the test's own bare-key request was refused")
	check(not audit.contains("auth_failed path=/api/manifest") and not audit.contains("auth_failed path=/api/file"), "the sync itself never failed to sign")
	c.queue_free()
	await _stop()
