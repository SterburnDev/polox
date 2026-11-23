extends "res://tests/test_case.gd"
## Phase 23, Polox for Android. Everything on 127.0.0.1 (announcements included):
## the plain-HTTP rule, the PC's "Polox is here" (only a name and a port) and the app hearing it,
## finding the PC (home network, then the last address, then Tailscale, never another PC), the
## app's QR code (no PIN in any address) and the decoder reading it from camera-like pictures,
## Reed-Solomon, /app and the APK, the adb helper's plain answers, the export preset and the
## built APK, the built-in Check connection, app mode in-process, and the whole app end to end
## as a real second Godot process (--app-mode): Connect, PIN, sync, play, offline play, the PC
## coming back, resume, and the update offer.

const AppLink := preload("res://scripts/phone/app_link.gd")
const Announcer := preload("res://scripts/phone/announcer.gd")
const QrCode := preload("res://scripts/phone/qr_code.gd")
const QrDecode := preload("res://scripts/phone/qr_decode.gd")
const AndroidApp := preload("res://scripts/phone/android_app.gd")
const AppPage := preload("res://scripts/phone/app_page.gd")
const AppCheck := preload("res://scripts/phone/app_check.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const PhoneMode := preload("res://scripts/phone/phone_mode.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const Slots := preload("res://scripts/core/slots.gd")
const AppConnectPanel := preload("res://scripts/ui/app_connect_panel.gd")

var server: Node
var port := 0
var dport := 0
var pc_root := ""


func _start_pc() -> void:
	pc_root = fresh_save_root()
	StarterContent.create_world("PC World", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	var web := pc_root.path_join("_web")
	JsonUtil.ensure_dir(web)
	server = PhoneServer.new()
	tree.root.add_child(server)
	server.setup(pc_root, web)
	server.mode = "lan"
	dport = free_udp_port()
	server.announce_port = dport
	server.apk_file = pc_root.path_join("_apk").path_join("polox.apk")
	port = listen_on_free_port(func(p: int) -> String: return server.start(p, "127.0.0.1"), "Phone Link")


func _stop_pc() -> void:
	if server:
		server.stop()
		server.queue_free()
		server = null
	await frames(1)


func _link(root: String) -> Node:
	var link: Node = AppLink.new()
	tree.root.add_child(link)
	link.listen_port = dport
	link.listen_address = "127.0.0.1"
	link.probe_timeout = 3.0
	link.load_link(root)
	return link


## GET (or HEAD) with a raw socket: {code, head, body: PackedByteArray}.
func _raw(method: String, path: String) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", port)
	var t := Time.get_ticks_msec()
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t < 3000:
		peer.poll()
		await frames(1)
	peer.put_data(("%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % [method, path]).to_utf8_buffer())
	var got := PackedByteArray()
	t = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 10000:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_data(n)[1])
		await frames(1)
	var end := HttpUtil.header_end(got)
	var head := got.slice(0, end).get_string_from_utf8() if end > 0 else got.get_string_from_utf8()
	var parts := head.split(" ")
	return {"code": parts[1].to_int() if parts.size() > 1 else 0, "head": head, "body": got.slice(end + 4) if end > 0 else PackedByteArray()}


func _fake_apk(version: String, code: int) -> Dictionary:
	var dir := pc_root.path_join("_apk")
	JsonUtil.ensure_dir(dir)
	var bytes := ("PK fake apk " + version).to_utf8_buffer()
	var f := FileAccess.open(dir.path_join("polox.apk"), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var info := {"package": "com.polox.app", "version": version, "version_code": code, "size": bytes.size(), "sha256": HttpUtil.sha256_bytes(bytes), "built": "2026-10-17T00:00:00"}
	JsonUtil.write_json(dir.path_join("polox.json"), info)
	server.refresh_page_info()
	return info


# --- The plain-HTTP rule --------------------------------------------------------------------------

func test_plain_http_only_goes_to_the_home_network_or_tailscale() -> void:
	for url in ["http://192.168.1.42:8765", "http://10.0.0.5:8765", "http://172.20.1.2", "http://100.101.102.103:8765",
			"http://127.0.0.1:8765", "http://[fd7a:115c:a1e0::1]:8765", "http://desktop-1.tailnet-example.ts.net:8765",
			"https://desktop-1.tailnet-example.ts.net:8765", "https://example.com"]:
		check(AppLink.url_allowed(url), "allowed: " + url)
	for url in ["http://8.8.8.8:8765", "http://example.com", "http://192.168.1.42.evil.com", "ftp://192.168.1.2",
			"http://user@192.168.1.2", "", "192.168.1.2:8765", "http://172.32.0.1", "http://[2001:db8::1]:80", "http://"]:
		check(not AppLink.url_allowed(url), "refused: " + url)


# --- Announcements ------------------------------------------------------------------------------

func test_the_pc_announces_only_a_name_and_a_port() -> void:
	var bytes := Announcer.payload("DESKTOP-1", 8765)
	var d: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	eq(d.keys().size(), 4, "four keys, nothing else")
	for k in ["polox", "v", "name", "port"]:
		check(d.has(k), k)
	eq(AppLink.parse_announcement(bytes), {"name": "DESKTOP-1", "port": 8765})
	for junk in ["hello", "{\"polox\":\"pc\",\"v\":2,\"name\":\"X\",\"port\":8765}", "{\"polox\":\"pc\",\"v\":1,\"name\":\"X\",\"port\":0}",
			"{\"polox\":\"pc\",\"v\":1,\"name\":\"X\",\"port\":70000}", "{\"polox\":\"pc\",\"v\":1,\"name\":\"\",\"port\":8765}", "[1,2]"]:
		eq(AppLink.parse_announcement(junk.to_utf8_buffer()), {}, "ignored: " + junk)
	eq(AppLink.parse_announcement(("{\"polox\":\"pc\",\"v\":1,\"name\":\"" + "x".repeat(600) + "\",\"port\":1}").to_utf8_buffer()), {}, "too big")
	var cands := [{"ip": "192.168.1.42", "kind": "private", "virtual": false}, {"ip": "10.5.0.2", "kind": "private", "virtual": true},
		{"ip": "100.101.1.2", "kind": "tailscale", "virtual": false}, {"ip": "8.8.8.8", "kind": "public", "virtual": false}]
	eq(Array(Announcer.targets_for("127.0.0.1", cands)), ["127.0.0.1"], "Phone Link on 127.0.0.1 announces there only")
	eq(Array(Announcer.targets_for("0.0.0.0", cands)), ["255.255.255.255", "192.168.1.255"], "home networks only: no VPN, Tailscale or public adapter")
	eq(Announcer.sources_for("0.0.0.0", cands), [["192.168.1.42", ["255.255.255.255", "192.168.1.255"]]], "sent from the home adapter itself, so it leaves on that network")
	eq(Announcer.sources_for("127.0.0.1", cands), [["127.0.0.1", ["127.0.0.1"]]])


func test_the_app_hears_the_pc() -> void:
	dport = free_udp_port()
	var ann: Node = Announcer.new()
	tree.root.add_child(ann)
	check(ann.start("TEST-PC", 8765, PackedStringArray(["127.0.0.1"]), dport), "announcing")
	var junk := PacketPeerUDP.new()
	junk.set_dest_address("127.0.0.1", dport)
	var link := _link(fresh_save_root("hear_phone"))
	var listening: Array = [true]
	var job := func() -> void:
		while listening[0]:
			junk.put_packet("{\"polox\":\"pc\",\"v\":1,\"name\":\"EVIL\",\"port\":0}".to_utf8_buffer())   # another program: ignored
			await frames(5)
	job.call()
	var heard: Array = await link.listen(2.5)
	listening[0] = false
	eq(heard.size(), 1, "one PC heard")
	if heard.size() == 1:
		eq(str(heard[0].name), "TEST-PC")
		eq(str(heard[0].url), "http://127.0.0.1:8765", "the address it came from, with the announced port")
	check(int(ann.sent) >= 1)
	ann.stop()
	ann.queue_free()
	link.queue_free()
	await frames(1)


# --- Finding the PC -----------------------------------------------------------------------------

func test_finding_the_pc_home_network_then_last_address_then_tailscale() -> void:
	await _start_pc()
	var phone_root := ProjectSettings.globalize_path("res://tests/.tmp_save/find_phone")
	JsonUtil.remove_tree(phone_root)
	var link := _link(phone_root)
	var r: Dictionary = await link.find_pc(2.5)
	check(r.ok, "found")
	eq(str(r.path), "home", "by its announcement")
	eq(str(r.url), "http://127.0.0.1:%d" % port)
	eq(str(link.link.get("last_url", "")), str(r.url), "remembered")
	eq(link.pc_name(), PhoneServer.pc_name(), "and the PC's name")
	check(FileAccess.file_exists(AppLink.link_file(phone_root)), "kept in the phone's own folder")
	# Announcements blocked (a guest network): the last address.
	server.announcer.stop()
	r = await link.find_pc(1.0)
	eq(str(r.path), "last", "the last address that worked")
	check((r.tried as Array).any(func(t): return str(t.path) == "home" and not bool(t.ok)), "and it says the home network was silent")
	# Away from home: Tailscale (here another address on this PC stands in for it).
	link.link["last_url"] = "http://127.0.0.1:9"
	link.link["ts_url"] = "http://127.0.0.1:%d" % port
	r = await link.find_pc(1.0)
	eq(str(r.path), "tailscale", "then Tailscale")
	check((r.tried as Array).any(func(t): return str(t.path) == "last" and not bool(t.ok)), "after the last address failed")
	# Paired with another PC: never this one by accident.
	link.link["pc_name"] = "SOMEONE-ELSES-PC"
	server.announcer.start(PhoneServer.pc_name(), port, PackedStringArray(["127.0.0.1"]), dport)
	r = await link.find_pc(1.5)
	check(not r.ok, "a different PC is not used")
	link.link["pc_name"] = PhoneServer.pc_name()
	# Nothing answers: every path tried, each with a reason (the same address is never tried twice).
	link.link["last_url"] = "http://127.0.0.1:9"
	await _stop_pc()
	r = await link.find_pc(1.0)
	check(not r.ok, "PC off")
	eq((r.tried as Array).map(func(t): return str(t.path)), ["home", "last", "tailscale"], "all three tried")
	check((r.tried as Array).all(func(t): return str(t.detail) != ""), "each says why")
	link.queue_free()
	await frames(1)


# --- The app's QR code and the decoder ------------------------------------------------------------

func test_the_apps_qr_code_pairs_without_the_pin_in_an_address() -> void:
	var payload := AppLink.qr_payload("DESKTOP-1", PackedStringArray(["http://192.168.1.42:8765", "https://desktop-1.tailnet-example.ts.net:8765"]), "123456")
	check(not payload.begins_with("http"), "not a web address (a phone camera won't open it in a browser)")
	var q := AppLink.parse_qr(payload)
	eq(str(q.get("name", "")), "DESKTOP-1")
	eq(Array(q.get("urls", [])), ["http://192.168.1.42:8765", "https://desktop-1.tailnet-example.ts.net:8765"])
	eq(str(q.get("pin", "")), "123456")
	for u in q.get("urls", []):
		check(not str(u).contains("123456"), "the PIN is in no address")
	eq(AppLink.parse_qr("http://192.168.1.42:8765/"), {}, "the browser QR code isn't the app's")
	eq(AppLink.parse_qr(payload.replace("p=123456", "p=12ab56")), {}, "a broken PIN")
	eq(AppLink.parse_qr(AppLink.qr_payload("X", PackedStringArray(["http://8.8.8.8:8765"]), "123456")), {}, "a public plain-HTTP address is dropped")
	# The picture the PC shows, read back.
	var img: Image = QrCode.encode(payload).to_image(6)
	eq(QrDecode.decode_image(img), payload, "decoded from the PC's own picture")


## A camera-like picture of `src` drawn into quadrilateral `quad` (perspective), with grey
## levels, optional shade from the left and noise.
func _photo(src: Image, quad: Array, w: int, h: int, shade: bool, seed_n: int) -> Image:
	var sw := src.get_width()
	var sh := src.get_height()
	var m: PackedFloat64Array = QrDecode.quad_to_quad(quad, [Vector2(0, 0), Vector2(sw, 0), Vector2(sw, sh), Vector2(0, sh)])
	var sd := src.get_data()
	var data := PackedByteArray()
	data.resize(w * h)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	for y in h:
		for x in w:
			var p: Vector2 = QrDecode.apply(m, x + 0.5, y + 0.5)
			var v := 0.75
			var ix := int(p.x)
			var iy := int(p.y)
			if ix >= 0 and iy >= 0 and ix < sw and iy < sh:
				v = 0.15 + sd[(iy * sw + ix) * 3] / 255.0 * 0.7
			if shade:
				v *= 0.55 + 0.45 * float(x) / w
			v += rng.randf_range(-0.06, 0.06)
			data[y * w + x] = clampi(int(v * 255.0), 0, 255)
	return Image.create_from_data(w, h, false, Image.FORMAT_L8, data)


func test_reading_qr_codes_from_camera_like_pictures() -> void:
	var text := AppLink.qr_payload("EXAMPLE-PC", PackedStringArray(["http://192.168.1.42:8765", "https://example-pc.tailnet-example.ts.net:8765"]), "482913")
	var q: RefCounted = QrCode.encode(text)
	check(q != null and int(q.version) >= 7, "a big code (version %d)" % int(q.version if q else 0))
	var src: Image = q.to_image(4)
	var t0 := Time.get_ticks_msec()
	eq(QrDecode.decode_image(q.to_image(6)), text, "straight on")
	var r: Image = q.to_image(5)
	for turn in 3:
		r.rotate_90(CLOCKWISE)
		eq(QrDecode.decode_image(r), text, "turned %d degrees" % (90 * (turn + 1)))
	r.flip_x()
	eq(QrDecode.decode_image(r), text, "mirrored (a front camera)")
	var framed := Image.create(640, 480, false, Image.FORMAT_RGB8)
	framed.fill(Color(0.8, 0.8, 0.75))
	var small: Image = q.to_image(4)
	framed.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(220, 90))
	eq(QrDecode.decode_image(framed), text, "inside a bigger picture")
	var screen := Image.create(1280, 800, false, Image.FORMAT_RGB8)
	screen.fill(Color("#2e2552"))
	for i in 12:
		screen.fill_rect(Rect2i(40 + i * 100, 60, 80, 40), Color("#f3e9d2"))   # buttons and text around it
	var code: Image = q.to_image(5)
	screen.blit_rect(code, Rect2i(Vector2i.ZERO, code.get_size()), Vector2i(480, 260))
	eq(QrDecode.decode_image(screen), text, "a small code on a big screen (looked at again at full size)")
	var rot: Array = []
	for k in 4:
		var a := deg_to_rad(23.0 + 90.0 * k - 135.0)
		rot.append(Vector2(240, 180) + Vector2(cos(a), sin(a)) * 150.0)
	var shots := {
		"tilted phone": [Vector2(120, 60), Vector2(400, 90), Vector2(380, 330), Vector2(140, 300)],
		"turned 23 degrees": rot,
		"far away": [Vector2(180, 120), Vector2(330, 125), Vector2(325, 270), Vector2(178, 265)],
	}
	var n := 1
	for name in shots:
		for shade in [false, true]:
			eq(QrDecode.decode_image(_photo(src, shots[name], 480, 360, shade, n)), text, "%s%s" % [name, ", shadow on one side" if shade else ""])
			n += 1
	var blurred := _photo(src, shots["tilted phone"], 480, 360, false, 99)
	blurred.resize(240, 180, Image.INTERPOLATE_BILINEAR)
	blurred.resize(480, 360, Image.INTERPOLATE_BILINEAR)
	eq(QrDecode.decode_image(blurred), text, "out of focus")
	var damaged: Image = q.to_image(4)
	damaged.fill_rect(Rect2i(70, 70, 16, 16), Color.WHITE)
	damaged.fill_rect(Rect2i(110, 120, 12, 8), Color.BLACK)
	eq(QrDecode.decode_image(damaged), text, "a smudge and a scratch (Reed-Solomon)")
	var ms := Time.get_ticks_msec() - t0
	print("    (QR: 13 pictures in %d ms)" % ms)
	# Pictures without a code: nothing, quickly.
	var noise := Image.create(480, 360, false, Image.FORMAT_L8)
	var nd := PackedByteArray()
	nd.resize(480 * 360)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in nd.size():
		nd[i] = rng.randi() % 256
	noise.set_data(480, 360, false, Image.FORMAT_L8, nd)
	eq(QrDecode.decode_image(noise), "", "noise")
	var plain := Image.create(320, 240, false, Image.FORMAT_RGB8)
	plain.fill(Color(0.4, 0.5, 0.6))
	eq(QrDecode.decode_image(plain), "", "a wall")
	eq(QrDecode.decode_image(Image.create(10, 10, false, Image.FORMAT_L8)), "", "tiny")
	# The camera's brightness plane (one red channel) reads the same.
	var y_plane: Image = q.to_image(5)
	y_plane.convert(Image.FORMAT_R8)
	eq(QrDecode.decode_image(y_plane), text, "a camera brightness plane (R8)")


func test_reed_solomon_fixes_what_it_can_and_no_more() -> void:
	var q: RefCounted = QrCode.encode("hello polox")
	eq(int(q.version), 1)
	var cw: PackedByteArray = q._add_ecc_and_interleave(q._data_codewords("hello polox".to_utf8_buffer()))
	eq(QrDecode.rs_correct(cw, 10), cw, "a clean block passes")
	var five := cw.duplicate()
	for i in [0, 4, 9, 17, 25]:
		five[i] ^= 0xA5
	eq(QrDecode.rs_correct(five, 10), cw, "5 damaged bytes (of 10 check bytes) are fixed")
	var six := cw.duplicate()
	for i in [0, 4, 9, 17, 22, 25]:
		six[i] ^= 0x3C
	check(QrDecode.rs_correct(six, 10) != cw, "6 are too many (no false repair)")


# --- /app and the APK -------------------------------------------------------------------------------

func test_phone_link_serves_the_app() -> void:
	await _start_pc()
	var page := await _raw("GET", "/app")
	eq(int(page.code), 200)
	check((page.body as PackedByteArray).get_string_from_utf8().contains("Not built yet"), "says when there's no app yet")
	eq(int((await _raw("GET", "/app/polox.apk")).code), 404, "no APK: 404 with a reason")
	var v0: Dictionary = JSON.parse_string((await _raw("GET", "/app/version.json")).body.get_string_from_utf8())
	eq(bool(v0.get("available", true)), false)
	var info := _fake_apk("1.8.0", 10800)
	page = await _raw("GET", "/app")
	var html: String = (page.body as PackedByteArray).get_string_from_utf8()
	check(html.contains("/app/polox.apk") and html.contains("1.8.0"), "a download button with the version")
	check(html.contains("Allow from this source") or html.contains("unknown apps"), "what Android will ask")
	var apk := await _raw("GET", "/app/polox.apk")
	eq(int(apk.code), 200, "no pairing needed: the APK holds no saves or keys")
	check(str(apk.head).contains("application/vnd.android.package-archive"), "Android's type")
	check(str(apk.head).contains("attachment; filename=\"polox.apk\""), "a download named polox.apk")
	check(str(apk.head).contains(str(info.sha256)), "with its SHA-256")
	eq(HttpUtil.sha256_bytes(apk.body), str(info.sha256), "byte for byte")
	var head := await _raw("HEAD", "/app/polox.apk")
	eq(int(head.code), 200)
	eq((head.body as PackedByteArray).size(), 0, "HEAD: no body")
	var v: Dictionary = JSON.parse_string((await _raw("GET", "/app/version.json")).body.get_string_from_utf8())
	check(bool(v.available))
	eq(int(v.version_code), 10800)
	var hello: Dictionary = JSON.parse_string((await _raw("GET", "/hello.json")).body.get_string_from_utf8())
	eq(str(hello.get("app_version", "")), "1.8.0", "/hello.json says which app the PC has")
	check(hello.has("ts_url"), "and its Tailscale address (empty in Same Wi-Fi mode)")
	var launcher: String = (await _raw("GET", "/")).body.get_string_from_utf8()
	check(launcher.contains("href=\"/app\""), "the Launcher links the app")
	# A half-written APK (its description doesn't match) isn't offered.
	var f := FileAccess.open(server.apk_file, FileAccess.WRITE)
	f.store_string("cut")
	f.close()
	server.refresh_page_info()
	eq(int((await _raw("GET", "/app/polox.apk")).code), 404, "a mismatched APK isn't served")
	await _stop_pc()


func test_install_helpers_answer_in_plain_words() -> void:
	var text := "List of devices attached\nEXAMPLE0001    device product:example_phone model:Example_Phone device:example transport_id:1\nemulator-5554 unauthorized\n"
	var d := AndroidApp.parse_devices(text)
	eq(d.size(), 2)
	eq(str(d[0].serial), "EXAMPLE0001")
	eq(str(d[0].state), "device")
	eq(str(d[0].model), "Example Phone", "the model, readable")
	eq(AndroidApp.explain_state("device"), "")
	check(AndroidApp.explain_state("unauthorized").contains("Allow"), "unauthorized: tap Allow")
	check(AndroidApp.explain_state("offline").contains("unplug"), "offline: replug")
	check(bool(AndroidApp.explain_install("Performing Streamed Install\nSuccess")[0]), "Success")
	for pair in [["Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.polox.app signatures do not match]", "different key"],
			["Failure [INSTALL_FAILED_VERSION_DOWNGRADE]", "newer Polox"], ["Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]", "out of space"],
			["Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]", "Install via USB"], ["adb: no devices/emulators found", "No phone found"]]:
		var r := AndroidApp.explain_install(str(pair[0]))
		check(not bool(r[0]) and str(r[1]).contains(str(pair[1])), "%s -> %s" % [pair[0], r[1]])
	eq(AndroidApp.version_code("1.8.0"), 110800)
	eq(AndroidApp.version_code("2.10.3"), 121003)
	check(AndroidApp.version_code("1.0.0") > 12900, "Public Beta 1.0 updates an installed 1.29.0 in place")
	eq(PhoneMode._my_version_code(), AndroidApp.version_code(str(ProjectSettings.get_setting("application/config/version", ""))), "the phone and the PC count the same way")
	eq(AndroidApp.version_code("bad"), 0)
	check(AndroidApp.steps_usb().size() >= 4 and AndroidApp.steps_download("http://192.168.1.42:8765").size() >= 4, "step-by-step on the PC")
	check(" ".join(AndroidApp.steps_download("http://192.168.1.42:8765")).contains("unknown apps"), "including Android's \"install unknown apps\"")
	# A stand-in adb (tests never touch a real phone): finding it, then installing.
	var dir := fresh_save_root("fake_adb")
	var bat := dir.path_join("adb.bat")
	var bf := FileAccess.open(bat, FileAccess.WRITE)
	bf.store_string("@echo off\r\nif \"%1\"==\"devices\" (\r\n  echo List of devices attached\r\n  echo EXAMPLE0001 device product:example_phone model:Example_Phone transport_id:1\r\n  exit /b 0\r\n)\r\necho Performing Streamed Install\r\necho Success\r\nexit /b 0\r\n")
	bf.close()
	var helper: Node = AndroidApp.new()
	tree.root.add_child(helper)
	helper.adb_override = bat
	var done: Array = []
	helper.finished.connect(func(job, ok, msg): done.append([job, ok, msg]))
	eq(helper.find_devices(), "", "adb runs")
	var t := Time.get_ticks_msec()
	while done.is_empty() and Time.get_ticks_msec() - t < 15000:
		await frames(2)
	check(not done.is_empty() and str(done[0][0]) == "devices" and bool(done[0][1]), "found the phone: %s" % [done])
	eq(helper.devices.size(), 1)
	helper.queue_free()
	await frames(1)


func test_the_android_export_settings() -> void:
	var cfg := ConfigFile.new()
	eq(cfg.load("res://export_presets.cfg"), OK)
	var sec := ""
	for s in cfg.get_sections():
		if str(cfg.get_value(s, "platform", "")) == "Android":
			sec = s
	check(sec != "", "an Android preset")
	var o := sec + ".options"
	eq(str(cfg.get_value(o, "package/unique_name", "")), "com.polox.app")
	eq(bool(cfg.get_value(o, "gradle_build/use_gradle_build", false)), true, "Gradle build (Polox's Android plugin)")
	eq(str(cfg.get_value(o, "gradle_build/android_source_template", "")), "res://tools/engine/android/android_source.zip", "Polox's own engine (tools/build_engine.py)")
	for k in ["custom_template/debug", "custom_template/release"]:
		eq(str(cfg.get_value(o, k, "x")), "", k + " unused by a Gradle build")
	var plugins: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	check(plugins.has("res://addons/polox_android/plugin.cfg"), "the plugin that puts PoloxAndroid.aar into the export is on")
	eq(bool(cfg.get_value(o, "architectures/arm64-v8a", false)), true, "arm64 (64-bit phones)")
	for a in ["armeabi-v7a", "x86", "x86_64"]:
		eq(bool(cfg.get_value(o, "architectures/" + a, true)), false, a + " off (export_android.ps1 -Emulator adds x86_64)")
	eq(int(cfg.get_value(o, "version/code", 0)), AndroidApp.version_code(str(ProjectSettings.get_setting("application/config/version", ""))), "the version code follows the version")
	for k in ["keystore/release", "keystore/release_user", "keystore/release_password"]:
		eq(str(cfg.get_value(o, k, "x")), "", k + " is empty: the key and its password stay in tools\\android")
	var perms := []
	for k in cfg.get_section_keys(o):
		if str(k).begins_with("permissions/") and k != "permissions/custom_permissions" and bool(cfg.get_value(o, k, false)):
			perms.append(str(k).trim_prefix("permissions/"))
	perms.sort()
	eq(perms, ["access_network_state", "access_wifi_state", "camera", "change_wifi_multicast_state", "internet", "vibrate"], "only what the app needs")
	var ex := str(cfg.get_value(sec, "exclude_filter", ""))
	check(str(cfg.get_value(sec, "include_filter", "")).contains("build_id.txt"), "the app carries its source build ID")
	for f in ["tools/*", "tests/*", "build/*", "addons/polox_android/*"]:
		check(ex.contains(f), "excludes " + f)
	eq(int(ProjectSettings.get_setting("display/window/handheld/orientation", 0)), 6, "turns with the phone")
	eq(bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)), false, "Android's back gesture goes back, not out")
	# The built APK, when there is one: the game only.
	var apk := AndroidApp.apk_path()
	if FileAccess.file_exists(apk):
		var z := ZIPReader.new()
		eq(z.open(apk), OK, "the APK opens")
		var names := Array(z.get_files())
		check(names.has("assets/build_id.txt"), "the app's build ID is packed")
		check(names.any(func(n): return str(n).begins_with("lib/arm64-v8a/")), "arm64 engine inside")
		check(not names.any(func(n): return str(n).get_file() == "settings.json" or str(n).begins_with("assets/tests/") or str(n).begins_with("assets/tools/") or str(n).begins_with("assets/build/")), "no settings, tests, tools or builds")
		var key_like := false
		for n in names:
			if str(n).begins_with("assets/") and (str(n).ends_with(".json") or str(n).ends_with(".cfg") or str(n).ends_with(".tres")):
				if z.read_file(n).get_string_from_utf8().contains("AIza"):
					key_like = true
		check(not key_like, "no API key in the game files")
		z.close()


# --- Check connection ----------------------------------------------------------------------------

func test_check_connection_inside_the_app() -> void:
	await _start_pc()
	var link := _link(fresh_save_root("check_phone"))
	SaveManager.set_root(pc_root)
	var token: String = (server.pairing.pair(server.pairing.code, "Test phone", "127.0.0.1") as Dictionary).get("token", "")
	eq(token.length(), 64, "paired for the check")
	var chk: Node = AppCheck.new()
	tree.root.add_child(chk)
	var seen: Array = []
	chk.rung.connect(func(r): seen.append(str(r.id)))
	var out: Dictionary = await chk.run("http://127.0.0.1:%d" % port, token, link, SaveManager.slot_id)
	var by := {}
	for r in chk.results:
		by[str(r.id)] = r
	eq(seen, ["network", "announce", "ping", "info", "big", "paired", "sync"], "every rung, in order")
	for id in ["announce", "ping", "info", "big", "paired", "sync"]:
		check(bool(by.get(id, {}).get("ok", false)), "%s: %s" % [id, by.get(id, {}).get("detail", "")])
	check(str(by.big.detail).contains("20.0 MB"), "the whole 20 MB")
	check(bool(out.sent), "the report reached the PC: " + str(out.message))
	var last: Array = server.reports.recent(1)
	eq(str(last[0].get("page", "")) if not last.is_empty() else "", "app-check", "the PC has it as the app's check")
	check(not JSON.stringify(out.report).contains(token), "no key in the report")
	# PC off: the first failing rung says what to do.
	await _stop_pc()
	await chk.run("http://127.0.0.1:%d" % port, token, link, "")
	var ping: Array = (chk.results as Array).filter(func(r): return str(r.id) == "ping")
	check(not ping.is_empty() and not bool(ping[0].ok), "ping fails")
	check(not chk.hints.is_empty() and " ".join(chk.hints).contains("Phone Link"), "and the hint says what to do")
	chk.queue_free()
	link.queue_free()
	await frames(1)


# --- App mode, in this process ----------------------------------------------------------------------

func _fake_main() -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar game = null\nvar panels: Array = []\nfunc flush_all() -> void:\n\tpass\nfunc reload_world_from_disk() -> void:\n\tpass\n"
	s.reload()
	var m: Node = s.new()
	tree.root.add_child(m)
	return m


func test_app_mode_pairs_offers_updates_and_retries_while_the_pc_is_away() -> void:
	await _start_pc()
	var phone_root := ProjectSettings.globalize_path("res://tests/.tmp_save/appmode_phone")
	JsonUtil.remove_tree(phone_root)
	var main := _fake_main()
	var pm: Node = PhoneMode.new()
	pm.force_app = true
	main.add_child(pm)
	pm.setup(main)
	check(pm.app, "app mode")
	check(not pm.uses_page_keyboard(), "Android's own keyboard")
	pm.link.load_link(phone_root)
	pm.link.listen_port = dport
	pm.link.listen_address = "127.0.0.1"
	pm.client.local_root = phone_root
	check(not pm.paired())
	var url := "http://127.0.0.1:%d" % port
	var bad: Dictionary = await pm.pair_with(url, "000000" if server.pairing.code != "000000" else "111111", "Test phone")
	check(not bad.ok, "a wrong PIN doesn't pair")
	check(AppConnectPanel.pin_error(str(bad.get("error", ""))) != "", "and the panel has words for it")
	var blocked: Dictionary = await pm.pair_with("http://8.8.8.8:8765", server.pairing.code, "Test phone")
	check(not blocked.ok and str(blocked.error).contains("isn't allowed"), "never plain HTTP to a public address")
	var ok: Dictionary = await pm.pair_with(url, server.pairing.code, "Test phone")
	check(ok.ok, "paired: %s" % ok)
	check(pm.paired())
	eq(int(ok.get("pair_v", 0)), 1, "pair_v:1: the PIN went sealed and the key came back encrypted")
	check(str(ok.get("phrase", "")) != "" and str(ok.phrase) == str(server.last_pair_phrase), "the app's check words are the PC's: %s" % str(ok.get("phrase", "")))
	check(str(server.pc_name()) in (pm.link.link.get("pair_v_pcs", []) as Array), "and it remembers that this PC pairs safely (no downgrade later)")
	check(pm.signs and pm.client.sign and AIClient.pc_sign and bool(pm.link.link.get("sig", false)), "from now on it signs (sync, the AI, kept across restarts)")
	eq(pm.link.token().length(), 64, "the key is kept in the app's own folder")
	check(not FileAccess.get_file_as_string(AppLink.link_file(phone_root)).is_empty())
	eq(str(pm.client.only_slots), ",".join(Slots.phone_ids()), "it syncs every world the PC lets the phone play")
	eq(str(AIClient.config.get("preset", "")), "pc", "friends talk through the PC")
	eq(str(AIClient.config.get("base_url", "")), url)
	var s: Dictionary = await pm.client.sync()
	check(s.ok, "first sync")
	check(FileAccess.file_exists(phone_root.path_join("slots").path_join(SaveManager.slot_id).path_join("world.json")), "the PC's world arrived")
	# Updates: only a newer app is offered.
	_fake_apk(str(ProjectSettings.get_setting("application/config/version", "")), PhoneMode._my_version_code())
	eq(await pm.check_update(), {}, "the same version: nothing to offer")
	_fake_apk("9.9.9", 199909)
	var offer: Dictionary = await pm.check_update()
	eq(int(offer.get("version_code", 0)), 199909, "a newer app is offered")
	check(str(offer.get("url", "")).ends_with("/app/polox.apk"))
	# The PC goes away: retry every so often; when it's back, the retry syncs.
	await _stop_pc()
	pm.retry_offline_s = 0.3
	var gone: Dictionary = await pm.connect_pc(0.6)
	check(not gone.ok, "PC away")
	eq(str(pm.client.state), "offline")
	check(pm._retry_in > 0.0, "a retry is planned")
	check(pm.connection_text().contains("not found"), "and it says so")
	server = PhoneServer.new()
	tree.root.add_child(server)
	server.setup(pc_root, pc_root.path_join("_web"))
	server.announce_port = dport
	var restart_err: String = server.start(port, "127.0.0.1")
	if restart_err != "":
		port = listen_on_free_port(func(p: int) -> String: return server.start(p, "127.0.0.1"), "Phone Link restart")
		restart_err = "" if port > 0 else restart_err
	eq(restart_err, "", "the PC is back")
	var t := Time.get_ticks_msec()
	while str(pm.client.state) == "offline" and Time.get_ticks_msec() - t < 15000:
		await frames(3)
	await frames(10)
	t = Time.get_ticks_msec()
	while pm.client.busy and Time.get_ticks_msec() - t < 15000:
		await frames(3)
	check(str(pm.client.state) in ["ok", "conflict"], "the retry found it and synced (%s)" % pm.client.state)
	check(pm.connection_text().contains("home network"), pm.connection_text())
	# Coming back to the app syncs; going to the background pushes.
	var states: Array = []
	pm.client.status_changed.connect(func(st, _d): states.append(st))
	pm.on_lifecycle(true)
	t = Time.get_ticks_msec()
	while (states.is_empty() or pm.client.busy) and Time.get_ticks_msec() - t < 10000:
		await frames(3)
	check("syncing" in states, "resume -> sync")
	AIClient.pc_token = ""
	AIClient.pc_sign = false
	AIClient.configure({"preset": "mock"})
	main.queue_free()
	await _stop_pc()


func test_typed_addresses_and_the_pin_keypad() -> void:
	eq(AppConnectPanel.normalize_address("192.168.1.20"), "http://192.168.1.20:8765", "Phone Link's port by default")
	eq(AppConnectPanel.normalize_address("192.168.1.20:8080/"), "http://192.168.1.20:8080")
	eq(AppConnectPanel.normalize_address("https://desktop-1.tailnet-example.ts.net:8765"), "https://desktop-1.tailnet-example.ts.net:8765")
	eq(AppConnectPanel.normalize_address("8.8.8.8"), "", "not to the internet")
	eq(AppConnectPanel.normalize_address(""), "")
	# The keypad, with a stand-in phone that records what it was asked to pair with.
	var s := GDScript.new()
	s.source_code = "extends Node
var calls: Array = []
var link = null
var connection := {}
func paired() -> bool:
	return false
var unpaired := 0
func unpair() -> void:
	unpaired += 1
func pair_with(url: String, pin: String, device_name: String, how: String = \"typed\") -> Dictionary:
	calls.append([url, pin, device_name, how])
	return {\"ok\": false, \"error\": \"wrong PIN (4 tries left)\"}
func connection_text() -> String:
	return \"\"
"
	eq(s.reload(), OK)
	var fake: Node = s.new()
	tree.root.add_child(fake)
	var p: Control = AppConnectPanel.new()
	tree.root.add_child(p)
	p.setup_connect(null, fake, true)
	eq(p.step, "intro", "first start explains before it looks")
	p.target = {"url": "http://127.0.0.1:1", "path": "home", "name": "PC"}
	p.show_step("pin")
	await frames(1)
	for k in ["1", "2", "3", "⌫", "OK"]:
		p.press_key(k)
	eq(p.pin, "12", "digits and backspace")
	check(p._msg.text.contains("6 digits"), "OK before six digits explains")
	for k in ["3", "4", "5", "6"]:
		p.press_key(k)
	await frames(2)
	eq(fake.calls.size(), 1, "six digits pair by themselves")
	eq(str(fake.calls[0][1]) if not fake.calls.is_empty() else "", "123456")
	eq(p.pin, "", "a wrong PIN clears the keypad")
	check(p._msg.text.contains("didn't match"), "and says so: " + p._msg.text)
	var big_buttons := p.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text in ["1", "5", "0", "OK"])
	check(big_buttons.size() == 4 and big_buttons.all(func(b): return (b as Button).custom_minimum_size.y >= 64), "thumb-sized keys")
	p.queue_free()
	fake.queue_free()
	await frames(1)


# --- The whole app, as a second process ---------------------------------------------------------

func test_the_app_end_to_end_as_a_second_process() -> void:
	await _start_pc()
	var slot := SaveManager.slot_id
	var phone_root := ProjectSettings.globalize_path("res://tests/.tmp_save/app_e2e_phone")
	JsonUtil.remove_tree(phone_root)
	var cmd := ProjectSettings.globalize_path("res://tests/.tmp_save/app_e2e_cmd.json")
	if FileAccess.file_exists(cmd):
		DirAccess.remove_absolute(cmd)
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--app-mode", "--app-discovery-port=%d" % dport,
		"--save-root=" + phone_root, "--drive=app_flow", "--app-cmd-file=" + cmd, "--shot-delay=0.3"])
	var p: Dictionary = OS.execute_with_pipe(OS.get_executable_path(), args, false)
	check(not p.is_empty(), "the app process starts")
	if p.is_empty():
		await _stop_pc()
		return
	var pid := int(p.pid)
	var pipe: FileAccess = p.stdio
	var buf := ""
	var steps: Dictionary = {}
	var pushed_tiles := -1
	var t0 := Time.get_ticks_msec()
	var finished := false
	while Time.get_ticks_msec() - t0 < 150000 and not finished:
		buf += pipe.get_buffer(65536).get_string_from_utf8()
		while buf.contains("\n"):
			var line := buf.get_slice("\n", 0).strip_edges()
			buf = buf.substr(buf.find("\n") + 1)
			if not line.begins_with("[app] "):
				continue
			var d: Variant = JSON.parse_string(line.trim_prefix("[app] "))
			if not d is Dictionary:
				continue
			var what := str(d.what)
			steps[what] = d
			JsonUtil.write_json(cmd.get_base_dir().path_join("app_e2e_steps.json"), steps)
			match what:
				"found":
					_write_cmd(cmd, {"step": 1, "pin": server.pairing.code})
				"pushed":
					pushed_tiles = int(d.tiles)
					var pc_tiles := (SaveManager.load_room(str(d.room)).get("tiles", []) as Array).size()
					eq(pc_tiles, pushed_tiles, "the block placed on the phone is on the PC")
					server.stop()
					_write_cmd(cmd, {"step": 2})
				"offline":
					# Meanwhile the PC makes a new room; then Phone Link comes back.
					SaveManager.save_room({"id": "pc_extra", "name": "Made on the PC", "tiles": []})
					eq(server.start(port, "127.0.0.1"), "", "Phone Link back on")
					_write_cmd(cmd, {"step": 3})
				"resynced":
					_fake_apk("9.9.9", 199909)
					_write_cmd(cmd, {"step": 4})
				"done", "fail":
					finished = true
		if not OS.is_process_running(pid) and not buf.contains("\n"):
			buf += pipe.get_buffer(1 << 20).get_string_from_utf8()
			if not buf.contains("[app]"):
				break
		await frames(2)
	if OS.is_process_running(pid):
		await frames(30)
		if OS.is_process_running(pid):
			OS.kill(pid)
	JsonUtil.write_json(cmd.get_base_dir().path_join("app_e2e_steps.json"), steps)
	check(not steps.has("fail"), "no failure: %s" % [steps.get("fail", {})])
	check(bool(steps.get("start", {}).get("app", false)), "--app-mode is the app")
	eq(str(steps.get("connect_panel", {}).get("step", "")), "intro", "first start: Connect to your PC, explained first")
	check(str(steps.get("found", {}).get("button", "")).contains("127.0.0.1:%d" % port), "it found the PC by itself")
	var paired: Dictionary = steps.get("paired", {})
	eq(str(paired.get("path", "")), "home", "over the home network")
	check(bool(paired.get("token_saved", false)), "the key is kept")
	check(str(paired.get("text", "")).contains("home network"), "and it says which path: " + str(paired.get("text", "")))
	var synced: Dictionary = steps.get("synced", {})
	eq(str(synced.get("state", "")), "ok", "first sync")
	check(bool(synced.get("has_world", false)), "the PC's world is on the phone")
	check(slot in Array(synced.get("worlds", [])), "the world list came from the PC")
	var pushed: Dictionary = steps.get("pushed", {})
	check(bool(pushed.get("ok", false)) and int(pushed.get("tiles", 0)) == int(pushed.get("tiles_before", 0)) + 1, "played a block and pushed it: %s" % [pushed])
	var off: Dictionary = steps.get("offline", {})
	eq(str(off.get("state", "")), "offline", "PC away: offline")
	check(bool(off.get("playing", false)), "still playing")
	eq(int(off.get("tiles", -1)), pushed_tiles + 1, "the offline block is kept on the phone")
	check(float(off.get("retry", -1)) > 0.0, "a retry is planned")
	var re: Dictionary = steps.get("resynced", {})
	eq(str(re.get("state", "")), "ok", "the PC is back: synced")
	# Automatic and reconnect syncs can both finish: the last result may be a no-op. Check the saved
	# copies, which prove the transfer regardless of which successful sync moved each file.
	check(FileAccess.file_exists(phone_root.path_join("slots/%s/rooms/pc_extra.json" % slot)), "the PC's new room came to the phone")
	var phone_room: Dictionary = JsonUtil.read_json(phone_root.path_join("slots/%s/rooms/%s.json" % [slot, str(pushed.get("room", ""))]), {})
	eq((phone_room.get("tiles", []) as Array).size(), pushed_tiles + 1, "the phone keeps its offline block after reconnect")
	eq((SaveManager.load_room(str(pushed.get("room", ""))).get("tiles", []) as Array).size(), pushed_tiles + 1, "the PC has the offline block")
	check(bool(steps.get("resumed", {}).get("synced_again", false)), "coming back to the app syncs")
	eq(int(steps.get("update", {}).get("offer", {}).get("version_code", 0)), 199909, "the newer app on the PC is offered")
	check(steps.has("done"), "the app's run finished")
	await _stop_pc()


func _write_cmd(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	DirAccess.rename_absolute(path + ".tmp", path)


func test_polox_exe_carries_its_build_id_and_finds_the_app_beside_it() -> void:
	const WebBuild := preload("res://scripts/phone/web_build.gd")
	fresh_save_root()
	# The id written at export time is this source's id, read back exactly.
	var tmp := SaveManager.global_path("build_id_test.txt")
	var id := WebBuild.write_baked_id(tmp)
	check(id.length() == 16, "an id was written (%s)" % id)
	eq(id, WebBuild.current_build_id(), "the source's own id")
	eq(WebBuild.baked_id(tmp), id, "and read back as it was")
	eq(WebBuild.baked_id(tmp + ".missing"), "", "no file, no id")
	# Running from the project (not an export), the app is build/android/polox.apk, its details beside it.
	eq(AndroidApp.apk_path(), ProjectSettings.globalize_path("res://build/android/polox.apk"))
	var dir := SaveManager.global_path("exe_folder")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("polox.apk"), FileAccess.WRITE)
	f.store_string("not really an apk")
	f.close()
	JsonUtil.write_json(dir.path_join("polox.json"), {"version": "9.9.9", "version_code": 199909, "size": "not really an apk".length()})
	var info := AndroidApp.apk_info(dir.path_join("polox.apk"))
	check(bool(info.present) and str(info.version) == "9.9.9", "an APK beside Polox.exe is found with its details: %s" % str(info))


## A stand-in phone for the Connect screen and Settings: not paired, one PC on the Wi-Fi.
func _unpaired_phone() -> Node:
	var ls := GDScript.new()
	ls.source_code = "extends Node
var link := {}
func find_pc(_s: float) -> Dictionary:
	return {'ok': true, 'url': 'http://127.0.0.1:1', 'name': 'MY-PC', 'path': 'home', 'heard': [{'url': 'http://127.0.0.1:1', 'name': 'MY-PC'}]}
func pc_name() -> String:
	return ''
func save_link() -> void:
	pass
"
	eq(ls.reload(), OK)
	var s := GDScript.new()
	s.source_code = "extends Node
var calls: Array = []
var syncs := 0
var connects := 0
var link: Node = null
var client := self
var app := true
var origin := ''
var detail := ''
var state := 'idle'
var busy := false
var connection := {}
var update_offer := {}
func paired() -> bool:
	return false
var unpaired := 0
func unpair() -> void:
	unpaired += 1
func pair_with(url: String, pin: String, device_name: String, how: String = 'typed') -> Dictionary:
	calls.append([url, pin, device_name, how])
	return {'ok': false, 'error': 'wrong PIN (4 tries left)'}
func connect_pc(_s: float = 3.0) -> Dictionary:
	connects += 1
	return {'ok': true}
func sync() -> Dictionary:
	syncs += 1
	return {'ok': false}
func connection_text() -> String:
	return 'Not connected yet'
func open_pairing_page() -> void:
	pass
"
	eq(s.reload(), OK)
	var fake: Node = s.new()
	fake.link = ls.new()
	fake.add_child(fake.link)
	tree.root.add_child(fake)
	return fake


func test_the_pin_can_always_be_typed_on_a_phone() -> void:
	var fake := _unpaired_phone()
	# From Settings (not the first start): straight to looking; one PC answered, so straight to its PIN.
	var p: Control = AppConnectPanel.new()
	tree.root.add_child(p)
	p.setup_connect(null, fake, false)
	await frames(2)
	eq(p.step, "pin", "one PC on the Wi-Fi and not paired: its PIN, right away")
	eq(str(p.target.get("url", "")), "http://127.0.0.1:1")
	# The keypad counts a key the moment the finger lands, even if it then slides a little.
	var keys := p.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "⌫", "OK"])
	eq(keys.size(), 12, "the whole keypad")
	check(keys.all(func(b): return (b as Button).action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS), "keys count on touch-down")
	var one: Button = keys.filter(func(b): return (b as Button).text == "1")[0]
	await frames(2)
	var at := one.get_global_rect().get_center()
	for e in [[true, Vector2.ZERO], [true, Vector2(6, 5)], [false, Vector2(9, 7)]]:
		if e[0] and e[1] != Vector2.ZERO:
			var mm := InputEventMouseMotion.new()
			mm.position = at + e[1]
			mm.global_position = mm.position
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
			p.get_viewport().push_input(mm, true)
		else:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = e[0]
			mb.position = at + e[1]
			mb.global_position = mb.position
			p.get_viewport().push_input(mb, true)
		await frames(1)
	eq(p.pin, "1", "a wobbly tap still typed the 1")
	# Android's own number keyboard works too: six digits pair by themselves.
	check(p._pin_field != null and p._pin_field.virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_NUMBER, "a number field for Android's keyboard")
	p.pin = ""
	p._pin_field.text = ""
	p._pin_field.text = "12x3456"
	p._pin_field.text_changed.emit("12x3456")   # (what Android's keyboard does as you type)
	await frames(2)
	eq(fake.calls.size(), 1, "the typed PIN was sent once")
	eq(str(fake.calls[0][1]) if not fake.calls.is_empty() else "", "123456", "only the digits")
	eq(p._pin_field.text, "", "a wrong PIN clears the field too")
	p.queue_free()
	# Settings on an unpaired phone: a clear way to pair, and Look for my PC never syncs without a key.
	var st: Control = load("res://scripts/ui/settings_screen.gd").new()
	var v := VBoxContainer.new()
	st.add_child(v)
	st._build_phone_ai(v, fake)
	var labels := v.find_children("*", "Button", true, false).map(func(b): return (b as Button).text)
	check(labels.has("Connect to your PC"), "not 'Pair again' before it was ever paired: %s" % str(labels))
	check(v.find_child("ConnectToPC", true, false) != null, "and a big Connect to your PC (PIN or QR code)")
	var look: Button = v.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text == "Look for my PC")[0]
	look.pressed.emit()
	await frames(2)
	eq(fake.syncs, 0, "no sync without a key (it used to try, and the PC said 401)")
	eq(fake.connects, 0, "it leads to the PIN instead")
	st.free()
	# The title screen offers it too.
	var t: Control = load("res://scripts/ui/title_screen.gd").new()
	t.show_connect = true
	tree.root.add_child(t)
	await frames(1)
	check(t.find_child("ConnectToPC", true, false) != null, "the title screen: Connect to your PC")
	t.queue_free()
	fake.queue_free()
	await frames(1)
