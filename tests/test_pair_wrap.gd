extends "res://tests/test_case.gd"
## [PAIRING] pair_v:1, the pairing that never puts the PIN or the device key on the network readable
## (scripts/phone/pairing.gd has the protocol): the token never leaves the PC as is, the phone opens
## exactly the key the PC stored, any change on the way (tag, ciphertext, salt, nonce, iterations,
## PIN, the PC's key) fails closed, a PIN that changed meanwhile is a 409 stale_salt, every old limit
## still holds, old phones still pair the old way, the check words agree, /hello.json tells
## strangers only what finding the PC needs, abandoned upload chunks go, the flood maps stay small,
## and audit.log never holds a token or a PIN.
## Tags: [PAIRING]

const Pairing := preload("res://scripts/phone/pairing.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const HttpServer := preload("res://scripts/phone/http_server.gd")
const SyncClient := preload("res://scripts/phone/sync_client.gd")
const HelloPage := preload("res://scripts/phone/hello_page.gd")
const LauncherPage := preload("res://scripts/phone/launcher_page.gd")
const ExportInbox := preload("res://scripts/phone/export_inbox.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const Probe := preload("res://tests/http_probe.gd")

const PHONE_IP := "192.168.1.40"
const BRIEF_KEYS := ["app", "build_id", "mode", "ok", "pair_v", "pc_name", "version"]

var server: Node
var port := 0


func _pairing(tag: String) -> RefCounted:
	return Pairing.new(fresh_save_root(tag))


## One wrapped pairing on `p` with `pin`: {answer, sealed} (sealed.open is what the phone keeps).
func _wrapped(p: RefCounted, pin: String, ip: String = PHONE_IP) -> Dictionary:
	var sealed := Pairing.seal_request(p.wrap_info(), pin)
	if not check(bool(sealed.ok), "the phone sealed its request: %s" % sealed):
		return {"answer": {"ok": false}, "sealed": sealed}
	var body: Dictionary = (sealed.body as Dictionary).merged({"device": "Wrapped phone", "client": "wrap1"})
	return {"answer": p.pair("", "Wrapped phone", ip, "", "wrap1", body), "sealed": sealed}


func _start_server() -> void:
	var root := fresh_save_root()
	StarterContent.create_world("Wrap World", "Sam")
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	var web := root.path_join("_web")
	JsonUtil.ensure_dir(web)
	server = PhoneServer.new()
	tree.root.add_child(server)
	server.setup(root, web)
	server.mode = "lan"
	port = listen_on_free_port(func(p: int) -> String: return server.start(p, "127.0.0.1"), "Phone Link")


func _stop_server() -> void:
	if server:
		server.stop()
		server.queue_free()
		server = null
	await frames(1)


func _json_of(r: Dictionary) -> Dictionary:
	var d: Variant = JSON.parse_string((r.body as PackedByteArray).get_string_from_utf8())
	return d if d is Dictionary else {}


func test_a_wrapped_pairing_never_sends_the_token_and_opens_to_the_stored_key() -> void:
	var p := _pairing("wrap_round_trip")
	var pin: String = p.new_code()
	var cap: Dictionary = p.wrap_info()
	eq(int(cap.get("pair_v", 0)), 1, "the PC offers pair_v:1")
	eq(str(cap.get("kdf", "")), "pbkdf2-sha256")
	eq(str(cap.get("seal", "")), "rsa2048-pkcs1v15")
	check(Pairing.valid_wrap_iter(int(cap.get("iter", 0))), "with iterations in bounds")
	check(Pairing._valid_hex(str(cap.get("salt", "")), 16), "a 16-byte salt made with this PIN")
	var der := Marshalls.base64_to_raw(str(cap.get("pub", "")))
	check(der.size() > 280 and der.size() < 300, "an RSA-2048 public key (SubjectPublicKeyInfo, %d bytes)" % der.size())
	var w := _wrapped(p, pin)
	var answer: Dictionary = w.answer
	check(bool(answer.ok), "paired: %s" % [answer])
	check(not answer.has("token"), "no token field in a wrapped answer")
	eq(str(answer.get("ct", "")).length(), 128, "the key, encrypted (64 bytes as hex)")
	eq(str(answer.get("tag", "")).length(), 32, "and its tag")
	var body := JSON.stringify(w.sealed.body)
	check(not body.contains("\"code\""), "the request has no PIN field")
	var opened := Pairing.open_answer(answer, pin, w.sealed.open)
	check(bool(opened.ok), "the phone opens it: %s" % [opened])
	var token := str(opened.get("token", ""))
	eq(token.length(), 64, "a 64-hex key")
	check(Pairing._valid_hex(token, 32), "lowercase hex")
	check(not p.check_token(token).is_empty(), "exactly the key the PC stored (only its SHA-256)")
	check(not JSON.stringify(answer).contains(token) and not body.contains(token), "the key is in neither message")
	eq(str(opened.phrase), str(answer.phrase), "the same three words on both screens")
	eq(str(answer.phrase), Pairing.phrase_for_token(token, p.wrap_fingerprint()), "words = HMAC(token, label + the PC's key fingerprint)")
	check(p.code != pin, "single use: a new PIN after pairing")
	check(str(p.wrap_info().salt) != str(cap.salt), "and a new salt with it")
	# The same seal can't be replayed: its PIN is gone and its salt is stale.
	var again: Dictionary = p.pair("", "Replay", PHONE_IP, "", "", (w.sealed.body as Dictionary).duplicate())
	eq(int(again.get("status", 0)), 409, "a replayed request: stale salt (409)")
	check(bool(again.get("stale_salt", false)), "flagged so the phone asks for the new PIN")


func test_any_change_on_the_way_fails_closed() -> void:
	var p := _pairing("wrap_tamper")
	var pin: String = p.new_code()
	var w := _wrapped(p, pin)
	var answer: Dictionary = w.answer
	var opener: Dictionary = w.sealed.open
	check(bool(answer.ok), "paired")
	var cases := {}
	var t := str(answer.tag)
	cases["tag"] = answer.merged({"tag": ("1" if t[0] == "0" else "0") + t.substr(1)}, true)
	var c := str(answer.ct)
	cases["ct"] = answer.merged({"ct": c.substr(0, 40) + ("1" if c[40] == "0" else "0") + c.substr(41)}, true)
	cases["short ct"] = answer.merged({"ct": c.substr(0, 126)}, true)
	cases["no pair_v"] = answer.duplicate()
	(cases["no pair_v"] as Dictionary).erase("pair_v")
	cases["a token field"] = answer.merged({"token": "ab".repeat(32)}, true)
	cases["other words"] = answer.merged({"phrase": "amber apple arch"}, true) if str(answer.phrase) != "amber apple arch" else answer.merged({"phrase": "fox fox fox"}, true)
	for what in cases:
		var r := Pairing.open_answer(cases[what], pin, opener.duplicate(true))
		check(not bool(r.ok) and str(r.get("error", "")) == Pairing.PAIR_FAILED and not r.has("token"), "%s changed: refused, no key (%s)" % [what, r])
	var key_inputs := {
		"salt": opener.merged({"salt": "0".repeat(32) if str(opener.salt) != "0".repeat(32) else "1".repeat(32)}, true),
		"nonce": opener.merged({"nonce": "f".repeat(32) if str(opener.nonce) != "f".repeat(32) else "e".repeat(32)}, true),
		"iter": opener.merged({"iter": int(opener.iter) + 1}, true),
		"secret": opener.merged({"secret": Crypto.new().generate_random_bytes(32)}, true),
		"fingerprint": opener.merged({"fingerprint": "0".repeat(64)}, true),
	}
	for what in key_inputs:
		var r := Pairing.open_answer(answer, pin, (key_inputs[what] as Dictionary).duplicate(true))
		check(not bool(r.ok) and not r.has("token"), "another %s: refused (%s)" % [what, r])
	var wrong_pin := "%06d" % ((pin.to_int() + 1) % 1000000)
	check(not bool(Pairing.open_answer(answer, wrong_pin, opener.duplicate(true)).ok), "another PIN: refused")
	check(bool(Pairing.open_answer(answer, pin, opener.duplicate(true)).ok), "(and the untouched answer still opens)")


func test_the_pc_refuses_wrapped_requests_that_dont_fit() -> void:
	var p := _pairing("wrap_refusals")
	var pin: String = p.new_code()
	var sealed := Pairing.seal_request(p.wrap_info(), pin)
	var good: Dictionary = sealed.body
	var refused := {
		"pair_v 2": [good.merged({"pair_v": 2}, true), 400],
		"pair_v as text": [good.merged({"pair_v": "1"}, true), 400],
		"iter below the floor": [good.merged({"iter": 9999}, true), 400],
		"iter above the ceiling": [good.merged({"iter": 100001}, true), 400],
		"another iter": [good.merged({"iter": Pairing.PAIR_WRAP_ITER + 1}, true), 400],
		"short nonce": [good.merged({"nonce": "ab"}, true), 400],
		"signed nonce": [good.merged({"nonce": "-" + str(good.nonce).substr(1)}, true), 400],
		"no seal": [good.merged({"sealed": ""}, true), 400],
		"stale salt": [good.merged({"salt": "0".repeat(32)}, true), 409],
	}
	for what in refused:
		var r: Dictionary = p.pair("", "Phone", PHONE_IP, "", "", refused[what][0])
		eq(int(r.get("status", 0)), int(refused[what][1]), what)
		check(not bool(r.ok) and not r.has("token") and not r.has("ct"), what + ": nothing issued")
	var with_pin: Dictionary = p.pair(pin, "Phone", PHONE_IP, "", "", good.duplicate())
	eq(int(with_pin.get("status", 0)), 400, "a wrapped request that also carries the PIN as is: refused")
	eq(p.code, pin, "none of these used up the PIN")
	# Garbage that has the right shape, a seal for another nonce, and a sealed wrong PIN are wrong PINs:
	# they count toward every limit, and five from one address mean a cooldown.
	var other_nonce := good.merged({"nonce": "1".repeat(32) if str(good.nonce) != "1".repeat(32) else "2".repeat(32)}, true)
	var garbage := good.merged({"sealed": "ab".repeat(256)}, true)
	var wrong := Pairing.seal_request(p.wrap_info(), "%06d" % ((pin.to_int() + 7) % 1000000)).body as Dictionary
	var statuses: Array = []
	print("[expect-script-error] mbedTLS reports the undecryptable seals below (not script errors)")
	for body in [garbage, other_nonce, wrong, wrong, garbage]:
		var r: Dictionary = p.pair("", "Phone", PHONE_IP, "", "", (body as Dictionary).duplicate())
		statuses.append(int(r.get("status", 0)))
	print("[/expect-script-error]")
	eq(statuses, [401, 401, 401, 401, 429], "wrong, wrong, wrong, wrong, then a 60-second wait")
	var right: Dictionary = p.pair("", "Phone", PHONE_IP, "", "", Pairing.seal_request(p.wrap_info(), pin).body)
	eq(int(right.get("status", 0)), 429, "even the right PIN waits out the cooldown")
	var elsewhere := _wrapped(p, pin, "192.168.1.41")
	check(bool(elsewhere.answer.ok), "another address isn't held up by that cooldown")
	var expired_pin: String = p.new_code()
	p.code_expires = Time.get_unix_time_from_system() - 1.0
	var expired: Dictionary = p.pair("", "Phone", "192.168.1.42", "", "", Pairing.seal_request(p.wrap_info(), expired_pin).body)
	eq(int(expired.get("status", 0)), 401, "an expired PIN is refused the same way")


func test_the_hourly_pause_still_holds_for_wrapped_pins() -> void:
	var p := _pairing("wrap_pause")
	var pin: String = p.new_code()
	var last := {}
	for i in Pairing.WRONG_PER_HOUR:
		var ip := "192.168.1.%d" % (50 + i / 4)   # four wrong tries per address: never a cooldown
		var bad := "%06d" % ((p.code.to_int() + 1 + i) % 1000000)
		last = p.pair("", "Phone", ip, "", "", Pairing.seal_request(p.wrap_info(), bad).body)
	eq(int(last.get("status", 0)), 423, "20 wrong sealed PINs in an hour pause pairing")
	check(p.paused, "paused")
	var right: Dictionary = p.pair("", "Phone", "192.168.1.90", "", "", Pairing.seal_request(p.wrap_info(), p.code).body)
	eq(int(right.get("status", 0)), 423, "even for the right PIN")
	p.unlock()
	check(bool(_wrapped(p, p.code, "192.168.1.91").answer.ok), "unlocked on the PC: pairs again")
	check(pin != "", "(the first PIN was shown)")


func test_old_phones_still_pair_the_old_way_and_their_key_works() -> void:
	await _start_server()
	var probe := Probe.new(tree)
	var plain := _json_of(await probe.request("127.0.0.1", port, Probe.get_req("/api/pairing")))
	check(bool(plain.get("ok", false)) and not plain.has("pair_v") and not plain.has("pub") and not plain.has("salt"), "GET /api/pairing without wrap=1 is unchanged: %s" % [plain.keys()])
	var pin: String = server.pairing.code
	var r := await probe.request("127.0.0.1", port, Probe.with_body("POST", "/api/pair", JSON.stringify({"code": pin, "device": "Old phone", "client": "old1"}).to_utf8_buffer()))
	var j := _json_of(r)
	eq(int(r.code), 200, "an old phone (no pair_v) pairs")
	var token := str(j.get("token", ""))
	eq(token.length(), 64, "and gets its key as before")
	eq(j.keys().size(), 3, "{ok, token, device_id}, exactly as before: %s" % [j.keys()])
	check(server.last_pair_legacy and str(server.last_pair_phrase) == "", "the PC knows it was the old way")
	var path := "slots/%s/world.json" % SaveManager.slot_id
	var file := await probe.request("127.0.0.1", port, Probe.get_req("/api/file?path=" + path.uri_encode(), {"Authorization": "Bearer " + token}))
	eq(int(file.code), 200, "GET /api/file with that key works")
	check((file.body as PackedByteArray).get_string_from_utf8().contains("Wrap World"), "and returns the world")
	var audit := FileAccess.get_file_as_string(server.root.path_join("phone/audit.log"))
	check(audit.contains("pair_legacy device="), "audit.log notes an old-way pairing")
	await _stop_server()


func test_wrapped_pairing_over_http_with_the_apps_client() -> void:
	await _start_server()
	var probe := Probe.new(tree)
	# By hand, the way the launcher does it: nothing on the wire is the key.
	var pin: String = server.pairing.code
	var cap_raw := await probe.request("127.0.0.1", port, Probe.get_req("/api/pairing?wrap=1"))
	var cap := _json_of(cap_raw)
	eq(int(cap.get("pair_v", 0)), 1, "GET /api/pairing?wrap=1 offers pair_v:1")
	var sealed := Pairing.seal_request(cap, pin)
	var body: Dictionary = (sealed.body as Dictionary).merged({"device": "Wire phone", "client": "wire1"})
	var post_raw := Probe.with_body("POST", "/api/pair", JSON.stringify(body).to_utf8_buffer())
	var r := await probe.request("127.0.0.1", port, post_raw)
	eq(int(r.code), 200)
	var j := _json_of(r)
	eq(j.keys().size(), 6, "{ok, pair_v, ct, tag, phrase, device_id}: %s" % [j.keys()])
	var opened := Pairing.open_answer(j, pin, sealed.open)
	var token := str(opened.get("token", ""))
	eq(token.length(), 64, "the phone has its key")
	var wire := (cap_raw.body as PackedByteArray).get_string_from_utf8() + post_raw.get_string_from_utf8() + (r.body as PackedByteArray).get_string_from_utf8() + str(r.headers)
	check(not wire.contains(token), "the key appears nowhere on the wire")
	check(not wire.contains("\"" + pin + "\"") and not wire.contains("code"), "nor the PIN")
	eq(str(server.last_pair_phrase), str(opened.phrase), "the PC shows the phone's words")
	check(not server.last_pair_legacy, "and doesn't warn about the old way")
	check(not JSON.stringify(server.http.recent(50)).contains(token), "nor is the key in the request log")
	# The app's own client: GET ?wrap=1, sealed POST, verified answer.
	var c := SyncClient.new()
	tree.root.add_child(c)
	c.base_url = "http://127.0.0.1:%d" % port
	var paired: Dictionary = await c.pair(server.pairing.code, "App phone", "app1")
	check(bool(paired.ok), "the app pairs: %s" % [paired])
	eq(int(paired.get("pair_v", 0)), 1, "with pair_v:1")
	eq(str(paired.phrase), str(server.last_pair_phrase), "its words match the PC's")
	check(not server.pairing.check_token(str(paired.token)).is_empty(), "its key works on the PC")
	eq(c.token, str(paired.token), "and it uses it from now on")
	var stale: Dictionary = await c.pair("000000" if server.pairing.code != "000000" else "111111", "App phone", "app1")
	check(not bool(stale.ok), "a wrong PIN doesn't pair")
	eq(c.token, str(paired.token), "and leaves the key it had")
	c.queue_free()
	await _stop_server()


func test_an_app_that_paired_safely_refuses_the_old_way_from_that_pc() -> void:
	# A stand-in "old PC" (or someone stripping pair_v on the way): it never offers pair_v:1.
	var seen: Array = []
	var old: Node = HttpServer.new()
	tree.root.add_child(old)
	old.api_handler = func(req: Dictionary, _ip: String) -> PackedByteArray:
		if str(req.path) == "/api/pairing":
			return HttpUtil.json_response(200, {"ok": true, "paused": false, "cooldown": 0, "always_ask": false})
		if str(req.path) == "/api/pair":
			seen.append((req.body as PackedByteArray).get_string_from_utf8())
			return HttpUtil.json_response(200, {"ok": true, "token": "ab".repeat(32), "device_id": "dold"})
		return HttpUtil.error_response(404, "no")
	var old_port := listen_on_free_port(func(p: int) -> String: return old.start(p, "127.0.0.1"), "old PC")
	var c := SyncClient.new()
	tree.root.add_child(c)
	c.base_url = "http://127.0.0.1:%d" % old_port
	var refused: Dictionary = await c.pair("123456", "App phone", "app1", true)
	check(not bool(refused.ok) and str(refused.error) == Pairing.PAIR_FAILED, "a PC that paired safely before: the old way is refused")
	eq(seen.size(), 0, "and the PIN was never sent")
	var legacy: Dictionary = await c.pair("123456", "App phone", "app1")
	check(bool(legacy.ok) and str(legacy.token).length() == 64 and int(legacy.pair_v) == 0, "a PC it never paired with safely: the old way, as before")
	check(seen.size() == 1 and str(seen[0]).contains("\"code\":\"123456\""), "(an older Polox gets the PIN as is)")
	c.queue_free()
	old.stop()
	old.queue_free()
	await frames(1)


func test_check_words_and_the_word_list() -> void:
	eq(Pairing.VERIFY_WORDS.size(), 64, "64 words: 6 bits each")
	var unique := {}
	for w in Pairing.VERIFY_WORDS:
		unique[w] = true
		check(w == w.to_lower() and w.is_valid_identifier(), "%s: one plain lowercase word" % w)
	eq(unique.size(), 64, "all different")
	var token := "0123456789abcdef".repeat(4)
	var fp := HttpUtil.sha256_bytes("a key".to_utf8_buffer())
	var phrase := Pairing.phrase_for_token(token, fp)
	eq(phrase, Pairing.phrase_for_token(token, fp), "deterministic")
	eq(phrase.split(" ").size(), 3, "three words")
	for w in phrase.split(" "):
		check(w in Pairing.VERIFY_WORDS, w + " is from the list")
	var digest := Pairing.hmac_sha256(token.to_utf8_buffer(), ("polox verify v1|" + fp).to_ascii_buffer())
	eq(phrase, " ".join([Pairing.VERIFY_WORDS[digest[0] % 64], Pairing.VERIFY_WORDS[digest[1] % 64], Pairing.VERIFY_WORDS[digest[2] % 64]]), "bytes 0..2 of HMAC-SHA256(token, label + fingerprint), each % 64")
	var differ := 0
	for i in 8:
		if Pairing.phrase_for_token(token, HttpUtil.sha256_bytes(("key %d" % i).to_utf8_buffer())) != phrase:
			differ += 1
	check(differ >= 7, "another PC key gives other words (%d of 8)" % differ)
	var page := LauncherPage.html({"pc_name": "PC"})
	check(page.contains(JSON.stringify(Pairing.VERIFY_WORDS)), "the launcher has the same list, in the same order")


func test_pbkdf2_and_the_iteration_bounds() -> void:
	# RFC 7914 section 11: PBKDF2-HMAC-SHA256("Password", "NaCl", 80000, 64).
	eq(Pairing.pbkdf2_sha256("Password".to_utf8_buffer(), "NaCl".to_utf8_buffer(), 80000, 64).hex_encode(),
		"4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d", "the published test vector")
	for bad in [0, 1, 9999, 100001, 1000000]:
		check(not Pairing.valid_wrap_iter(bad), "%d iterations: out of bounds" % bad)
		check(Pairing.pbkdf2_sha256("1".to_utf8_buffer(), "salt".to_utf8_buffer(), bad).is_empty(), "%d: no key derived" % bad)
	for good in [10000, 100000]:
		check(Pairing.valid_wrap_iter(good), "%d: in bounds" % good)
	check(Pairing.valid_wrap_iter(Pairing.PAIR_WRAP_ITER) and Pairing.wrap_supported(), "the PC's own setting is in bounds")
	var p := _pairing("wrap_iter")
	var pin: String = p.new_code()
	var cap: Dictionary = p.wrap_info()
	for bad in [9999, 100001, 0, "10000", 10000.5]:
		check(not bool(Pairing.seal_request(cap.merged({"iter": bad}, true), pin).ok), "a PC asking for %s iterations is refused by the phone" % str(bad))
	for what in ["kdf", "seal", "pub", "salt"]:
		var broken := cap.duplicate()
		broken[what] = "x"
		check(not bool(Pairing.seal_request(broken, pin).ok), "a broken %s is refused by the phone" % what)


func test_the_salt_and_the_key_live_and_die_with_the_pin_and_phone_link() -> void:
	var p := _pairing("wrap_lifecycle")
	p.new_code()
	var a: Dictionary = p.wrap_info()
	var b: Dictionary = p.wrap_info()
	eq(str(a.salt), str(b.salt), "one salt per PIN")
	eq(str(a.pub), str(b.pub), "one key per run")
	p.new_code()
	check(str(p.wrap_info().salt) != str(a.salt), "a new PIN, a new salt")
	p.cancel_code()
	eq(str(p.wrap_info().get("salt", "?")), "", "no PIN, no salt")
	var fp: String = p.wrap_fingerprint()
	p.forget_wrap_key()
	eq(p.wrap_fingerprint(), "", "Phone Link off: the key is gone")
	p.new_code()
	var c: Dictionary = p.wrap_info()
	check(str(c.pub) != str(a.pub) and p.wrap_fingerprint() != fp, "a new key the next time")
	await _start_server()
	server.pairing.wrap_info()
	check(server.pairing.wrap_fingerprint() != "", "(the server made one)")
	server.stop()
	eq(server.pairing.wrap_fingerprint(), "", "stopping Phone Link drops it")
	await _stop_server()


func test_hello_json_tells_strangers_only_what_finding_the_pc_needs() -> void:
	await _start_server()
	var probe := Probe.new(tree)
	var mine := _json_of(await probe.request("127.0.0.1", port, Probe.get_req("/hello.json")))
	check(mine.has("urls") and mine.has("canonical") and mine.has("ts_url") and mine.has("lan_url") and mine.has("app_version"), "this PC itself: everything")
	# Through a proxy from 127.0.0.1 (Tailscale Serve), without a key: the short version.
	var stranger := _json_of(await probe.request("127.0.0.1", port, Probe.get_req("/hello.json", {"X-Forwarded-For": "192.168.1.77"})))
	var keys: Array = stranger.keys()
	keys.sort()
	eq(keys, BRIEF_KEYS, "a stranger: {ok, app, version, build_id, pc_name, mode, pair_v}")
	eq(str(stranger.app), "Polox", "enough for the app to know it's Polox")
	eq(str(stranger.pc_name), str(mine.pc_name), "and which PC")
	eq(int(stranger.pair_v), 1, "and that it pairs the safe way")
	var wrong := _json_of(await probe.request("127.0.0.1", port, Probe.get_req("/hello.json", {"X-Forwarded-For": "192.168.1.77", "Authorization": "Bearer " + "0".repeat(64)})))
	check(not wrong.has("urls"), "a made-up key: still the short version")
	var token := str(server.pairing.pair(server.pairing.code, "Paired phone", "192.168.1.77").token)
	var paired := _json_of(await probe.request("127.0.0.1", port, Probe.get_req("/hello.json", {"X-Forwarded-For": "192.168.1.77", "Authorization": "Bearer " + token})))
	check(paired.has("urls") and paired.has("ts_url") and paired.has("canonical"), "a paired phone's key: everything")
	check(not server.hello_in_full({"ip": "192.168.1.77", "headers": {}}), "a phone on the Wi-Fi without a key: short")
	check(not server.hello_in_full({"ip": "127.0.0.1", "headers": {}, "proxied": true}), "through the bundled server: short")
	check(not server.hello_in_full({"ip": "127.0.0.1", "headers": {"tailscale-user-login": "me@example.com"}}), "through Tailscale Serve: short")
	check(server.hello_in_full({"ip": "127.0.0.1", "headers": {}}), "this PC itself: full")
	var html := (await probe.request("127.0.0.1", port, Probe.get_req("/hello", {"X-Forwarded-For": "192.168.1.77"}))).body as PackedByteArray
	check(html.get_string_from_utf8().contains("Polox host reachable"), "/hello (the page) is unchanged")
	await _stop_server()


func test_the_flood_guard_forgets_addresses_after_an_hour() -> void:
	var p := _pairing("wrap_prune")
	p.new_code()
	var now := Time.get_unix_time_from_system()
	for i in 500:
		var ip := "10.0.%d.%d" % [i / 250, i % 250]
		p._attempts[ip] = [now - 7200.0]
		p._wrong[ip] = 3
		p._wrong_updated[ip] = now - 7200.0
		p._cooldown[ip] = now - 7000.0
	p._attempts["192.168.1.9"] = [now - 10.0]
	p._wrong["192.168.1.9"] = 2
	p._wrong_updated["192.168.1.9"] = now - 10.0
	p._cooldown["192.168.1.8"] = now + 30.0
	eq(p.tracked_addresses(), 501, "(501 addresses remembered)")
	var st: Dictionary = p.state_for("192.168.1.8")
	check(p.tracked_addresses() <= 2, "after an hour they're forgotten (%d left)" % p.tracked_addresses())
	check(int(st.cooldown) > 0, "a running cooldown stays")
	eq(int(p._wrong.get("192.168.1.9", 0)), 2, "recent wrong tries stay")
	eq((p._attempts.get("192.168.1.9", []) as Array).size(), 1, "and recent tries")


func test_abandoned_upload_chunks_are_swept_after_a_day() -> void:
	var root := fresh_save_root()
	var inbox := ExportInbox.folder(root).path_join(ExportInbox.INCOMING)
	JsonUtil.ensure_dir(inbox)
	for n in ["old_a.part", "old_b.part", "keep.txt"]:
		var f := FileAccess.open(inbox.path_join(n), FileAccess.WRITE)
		f.store_string("x")
		f.close()
	eq(ExportInbox.sweep(root), 0, "fresh chunks stay")
	eq(ExportInbox.sweep(root, Time.get_unix_time_from_system() + 25.0 * 3600.0), 2, "a day later the .part files go")
	check(FileAccess.file_exists(inbox.path_join("keep.txt")), "nothing else is touched")
	var src := FileAccess.get_file_as_string("res://scripts/phone/export_inbox.gd")
	check(src.contains("static func receive(") and src.get_slice("static func receive(", 1).get_slice("\n\n\n", 0).contains("sweep(root)"), "every chunk that arrives sweeps")
	check(FileAccess.get_file_as_string("res://scripts/phone/phone_server.gd").contains("ExportInbox.sweep(root)"), "and so does starting Phone Link")


func test_a_report_sent_by_address_is_flagged() -> void:
	var rep := {"received": "2026-11-22T20:15:00", "from_ip": "192.168.1.40", "via": "lan", "address": "http://192.168.1.20:8765", "results": [{"id": "ping", "ok": true}]}
	check(ReportSink.summary(rep.merged({"transport": "get"})).begins_with("⚠ "), "a report that came in a GET address (anyone can make a link like that): ⚠")
	check(not ReportSink.summary(rep.merged({"transport": "post"})).begins_with("⚠"), "a POSTed one isn't")


func test_the_launcher_page_carries_the_wrapped_flow() -> void:
	var page := LauncherPage.html({"pc_name": "PC", "canonical": "http://192.168.1.20:8765", "urls": ["http://192.168.1.20:8765"]})
	for want in ["/api/pairing?wrap=1", "pair_v", "pairSeal", "pairOpen", "Check these words match your PC", "They match", "They don't match", "Response didn't verify: possible interference", "stale_salt"]:
		check(page.contains(want), "the page has " + want)
	check(not page.contains("{{"), "every placeholder filled")
	var consts: Dictionary = (LauncherPage as GDScript).get_script_constant_map()
	for name in ["STYLE", "BODY", "PAIR_CRYPTO", "SCRIPT"]:
		check(consts.has(name) and not str(consts.get(name, "\\")).contains("\\"), name + " has no backslashes (GDScript would eat them)")
	var js := LauncherPage.page_script()
	var literal := RegEx.create_from_string("[0-9]n[^a-zA-Z0-9_]")
	check(literal.search(js.replace("\n", " ")) == null, "no BigInt literals: an old browser still parses the page and pairs the old way")
	check(not js.contains("crypto.subtle") and not js.contains("eval("), "no crypto.subtle (missing on plain HTTP) and no eval")
	check(js.contains("body.code = pin") and js.contains("pairCan(pairCap)"), "the old way only when pair_v:1 can't be used")


func test_audit_log_never_holds_a_token_or_a_pin() -> void:
	var p := _pairing("wrap_audit")
	var secrets: Array = []
	for i in 3:
		var pin: String = p.new_code()
		secrets.append(pin)
		var w := _wrapped(p, pin, "192.168.1.%d" % (60 + i))
		var opened := Pairing.open_answer(w.answer, pin, w.sealed.open)
		secrets.append(str(opened.get("token", "")))
	var legacy_pin: String = p.new_code()
	secrets.append(legacy_pin)
	secrets.append(str(p.pair(legacy_pin, "Old\nphone pair_ok device=forged", "192.168.1.70").get("token", "")))
	var bad := "%06d" % ((p.code.to_int() + 3) % 1000000)
	secrets.append(bad)
	p.pair("", "Phone", "192.168.1.71", "", "", Pairing.seal_request(p.wrap_info(), bad).body)
	p.pair(bad, "Phone", "192.168.1.72")
	var log_text := FileAccess.get_file_as_string(p.root.path_join("phone/audit.log"))
	check(log_text.contains("pair_phrase device=") and log_text.contains("pair_wrap_ok") and log_text.contains("pair_legacy") and log_text.contains("pair_wrong_code"), "the events are there")
	var words := {}
	for w in RegEx.create_from_string("[0-9A-Za-z]+").search_all(log_text):
		words[w.get_string()] = true
	for s in secrets:
		check(str(s) != "" and not words.has(str(s)), "no PIN or key in audit.log (%s...)" % str(s).left(2))
	for line in log_text.strip_edges().split("\n"):
		check(line.begins_with("20"), "one event per line, even for a name with a line break: %s" % line.left(40))
