extends "res://tests/test_case.gd"
## Phase 16: Phone Link on plain home Wi-Fi with the launcher and the PIN.
## Mode choice (no Tailscale -> Same Wi-Fi; Tailscale -> Serve, Same Wi-Fi
## still on), the settings upgrade, the launcher page (and "This is the PC"
## when the PC itself opens localhost), the worlds list / covers / session
## start / per-world sync, the PIN kept fresh, the banner on the PC when a
## phone first reaches it, host.bat's window, and the checklist after a
## minute without a phone. Everything on 127.0.0.1 (a phone address is
## simulated with the server's debug peer override); Tailscale is a fake.

const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const LauncherPage := preload("res://scripts/phone/launcher_page.gd")
const Pairing := preload("res://scripts/phone/pairing.gd")
const Slots := preload("res://scripts/core/slots.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Probe := preload("res://tests/http_probe.gd")
const HostWindow := preload("res://scripts/ui/host_window.gd")
const PhoneLinkTab := preload("res://scripts/ui/phone_link_tab.gd")

var srv: Node
var port := 0
var root := ""
var probe: Probe


func _web(dir: String) -> String:
	var web := dir.path_join("_web")
	JsonUtil.ensure_dir(web)
	for f in ["index.html", "index.js", "index.wasm", "index.pck"]:
		var fa := FileAccess.open(web.path_join(f), FileAccess.WRITE)
		fa.store_string("fake " + f)
		fa.close()
	return web


## Three worlds: two shared with the phone, one switched off in the Save menu.
func _worlds() -> Dictionary:
	root = fresh_save_root()
	StarterContent.create_world("Moon Garden", "Sam")
	var a: String = SaveManager.slot_id
	var img := Image.create(8, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color("#ffd166"))
	img.save_png(Slots.dir(a).path_join("cover.png"))
	SaveManager.new_slot("Second World")
	StarterContent.create_world("Second World", "Sam")
	var b: String = SaveManager.slot_id
	SaveManager.new_slot("Secret World")
	StarterContent.create_world("Secret World", "Sam")
	var h: String = SaveManager.slot_id
	Slots.set_on_phone(h, false)
	SaveManager.set_slot(a)
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	return {"a": a, "b": b, "hidden": h}


func _listen(s: Node) -> String:
	port = listen_on_free_port(func(p: int) -> String: return s.start(p, "127.0.0.1"), "Phone Link")
	return "" if port > 0 else "couldn't listen"


func _start(mode: String = "lan") -> void:
	srv = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, _web(root))
	srv.mode = mode
	eq(_listen(srv), "", "Phone Link starts (tests stay on 127.0.0.1)")
	probe = Probe.new(tree)


func _stop() -> void:
	srv.http.debug_peer_override = ""
	srv.stop()
	srv.queue_free()
	await frames(2)


func _fetch(path: String, token: String = "", host: String = "x", extra: Dictionary = {}) -> Dictionary:
	var h := extra.duplicate()
	if token != "":
		h["Authorization"] = "Bearer " + token
	var r: Dictionary = await probe.request("127.0.0.1", port, Probe.get_req(path, h, host))
	var content_type := str(r.headers.get("content-type", ""))
	r["text"] = (r.body as PackedByteArray).get_string_from_utf8() if content_type.begins_with("text/") or content_type.contains("json") else ""
	return r


func _post(path: String, body: Dictionary, token: String = "") -> Dictionary:
	var r: Dictionary = await probe.request("127.0.0.1", port, Probe.with_body("POST", path, JSON.stringify(body).to_utf8_buffer(), token))
	r["text"] = (r.body as PackedByteArray).get_string_from_utf8()
	var j: Variant = JSON.parse_string(r.text)
	r["json"] = j if j is Dictionary else {}
	return r


func _pair() -> String:
	var r := await _post("/api/pair", {"code": srv.pairing.code, "device": "Test phone", "client": "c1"})
	return str(r.json.get("token", ""))


# --- Mode choice ---------------------------------------------------------------------------------------

func test_mode_choice_and_settings_upgrade() -> void:
	eq(PhoneServer.auto_mode({}), "lan", "no Tailscale: Same Wi-Fi")
	eq(PhoneServer.auto_mode({"installed": true, "running": false}), "lan", "Tailscale installed but off: Same Wi-Fi")
	eq(PhoneServer.auto_mode({"installed": true, "running": true, "dns_name": "pc.tail.ts.net", "https": false}), "tailscale_direct", "Tailscale without HTTPS certificates: + Tailscale HTTP")
	eq(PhoneServer.auto_mode({"installed": true, "running": true, "dns_name": "pc.tail.ts.net", "https": true}), "tailscale_serve", "Tailscale with HTTPS: + Serve (recommended)")
	for m in PhoneServer.MODES:
		eq(PhoneServer.listen_plan(m), {"bind": "0.0.0.0", "scope": "home"}, "%s listens everywhere and lets home networks in" % m)
	eq(PhoneServer.listen_plan("tailscale_serve", true), {"bind": "0.0.0.0", "scope": "tailscale"}, "only Tailscale only narrows it")
	eq(PhoneServer.listen_plan("lan", true), {"bind": "0.0.0.0", "scope": "home"}, "and never in Same Wi-Fi mode")
	# The user's old settings: Tailscale direct + "Tailscale only" refused every Wi-Fi phone.
	var old := {"port": 8737, "max_devices": 1, "sync_slots": [], "mode": "tailscale_direct", "tailscale_only": true}
	check(PhoneServer.upgrade_settings(old), "old Phone Link settings are upgraded once")
	eq(bool(old.tailscale_only), false, "Tailscale only switched off (Same Wi-Fi works)")
	eq(int(old.max_devices), 4, "four phones")
	eq(str(old.mode), "tailscale_direct", "the chosen mode is kept (it serves Same Wi-Fi now)")
	check(str(old.get("upgraded_note", "")) != "" and not old.has("sync_slots"), "with a note, per-world sharing instead")
	check(not PhoneServer.upgrade_settings(old), "only once")
	# Address choice: the home network adapter, never VirtualBox or link-local.
	var cands := [
		{"ip": "100.64.0.10", "kind": "tailscale", "rank": 0, "virtual": false},
		{"ip": "192.168.56.1", "kind": "private", "rank": 3, "virtual": true},
		{"ip": "192.168.1.42", "kind": "private", "rank": 1, "virtual": false},
	]
	eq(PhoneServer.pick_lan(cands), "192.168.1.42", "the Same Wi-Fi address")
	eq(PhoneServer.pick_lan([cands[0], cands[1]]), "", "none when only Tailscale and virtual adapters exist")


# --- The launcher page ----------------------------------------------------------------------------------

func test_launcher_page_and_localhost_helper() -> void:
	_worlds()
	_start()
	var page := await _fetch("/")
	eq(page.code, 200, "/ answers")
	check(page.text.contains("Enter the PIN shown on your PC") and page.text.contains("Your worlds") and page.text.contains("Having trouble?"), "it's the launcher: PIN, worlds, help")
	check(page.text.contains("Forget this phone"), "with Forget this phone")
	check(not page.text.contains("<script src") and not page.text.contains("https://fonts"), "no outside scripts or fonts")
	check(not page.text.contains(srv.pairing.code), "the PIN is never in the page")
	check(page.text.contains("polox_token") and page.text.contains("/api/cover?slot="), "keeps the key for the game, fetches covers with it")
	check(page.text.contains(PhoneServer.pc_name()), "names the PC: " + PhoneServer.pc_name())
	check(not page.text.contains("This is the PC"), "a phone's request gets no PC note (Host: x)")
	var pc := await _fetch("/", "", "localhost:%d" % port)
	check(pc.text.contains("This is the PC. On your phone open"), "the PC opening localhost is told where the phone should go")
	if srv.lan_url() != "":
		check(pc.text.contains(srv.lan_url()), "with the Same Wi-Fi address " + srv.lan_url())
	var pc2 := await _fetch("/", "", "127.0.0.1:%d" % port)
	check(pc2.text.contains("This is the PC"), "same for 127.0.0.1")
	var serve := await _fetch("/", "", "localhost:%d" % port, {"X-Forwarded-For": "100.73.1.2"})
	check(not serve.text.contains("This is the PC"), "a phone through Tailscale Serve isn't the PC")
	check(PhoneServer.is_pc_itself({"ip": "127.0.0.1", "headers": {"host": "[::1]:8737"}}), "[::1] too")
	check(not PhoneServer.is_pc_itself({"ip": "192.168.1.40", "headers": {"host": "localhost:8737"}}), "a request from another device never is")
	# /hello lists every address that works (the phone warns only about others).
	var hj: Dictionary = JSON.parse_string((await _fetch("/hello.json")).text)
	check(hj.urls is Array and (hj.urls as Array).has(srv.canonical_url()), "/hello.json lists the addresses")
	eq(str(hj.pc_name), PhoneServer.pc_name())
	# Without the game files the launcher still works and Play explains.
	await _stop()


func test_worlds_covers_session_and_per_world_sync() -> void:
	var w := _worlds()
	_start()
	eq((await _fetch("/api/worlds")).code, 401, "worlds need the key")
	eq((await _fetch("/api/cover?slot=" + str(w.a))).code, 401, "covers too (that's why the page fetches them)")
	var token := await _pair()
	eq(token.length(), 64, "paired")
	var list: Dictionary = JSON.parse_string((await _fetch("/api/worlds", token)).text)
	var ids: Array = (list.worlds as Array).map(func(x): return str(x.id))
	check(ids.has(w.a) and ids.has(w.b), "both shared worlds are listed")
	check(not ids.has(w.hidden), "the world switched off in the Save menu isn't")
	var card: Dictionary = (list.worlds as Array).filter(func(x): return str(x.id) == str(w.a))[0]
	check(str(card.name) == "Moon Garden" and str(card.size) != "" and str(card.ago) != "" and bool(card.cover), "a card: name, size, last played, cover: %s" % str(card))
	var cover := await _fetch("/api/cover?slot=" + str(w.a), token)
	eq(cover.code, 200, "the cover")
	check(str(cover.headers.get("content-type", "")).begins_with("image/png") and (cover.body as PackedByteArray).slice(1, 4).get_string_from_ascii() == "PNG", "is a PNG")
	eq((await _fetch("/api/cover?slot=" + str(w.hidden), token)).code, 404, "no cover for a world the phone may not see")
	eq((await _fetch("/api/cover?slot=" + str(w.b), token)).code, 404, "a world without a cover: 404 (the card shows its emoji)")
	# Session start: the address of the game for that world.
	var s := await _post("/api/session", {"slot": w.b}, token)
	eq(s.code, 200)
	check(str(s.json.play).begins_with("/game/") and str(s.json.play).ends_with("/index.html#slot=" + str(w.b)), "Play opens the game on that world, at its versioned address: " + str(s.json.play))
	eq(str(srv.phone_session.get("name", "")), "Second World", "the PC knows what the phone plays")
	eq((await _post("/api/session", {"slot": w.hidden}, token)).code, 404, "a hidden world can't be started")
	# The game files: complete-looking fake build here; with none, Play explains (the PIN and worlds still work).
	DirAccess.remove_absolute(srv.web_dir.path_join("index.html"))
	srv.refresh_page_info()
	var s2 := await _post("/api/session", {"slot": w.a}, token)
	check(not bool(s2.json.game_ok) and str(s2.json.why).contains("phone_doctor.bat"), "no game build: Play says why and points to the Doctor")
	eq((await _fetch("/", "", "x")).code, 200, "the launcher still answers without the game files")
	# Per-world sync: the manifest covers only the world being played.
	var m: Dictionary = JSON.parse_string((await _fetch("/api/manifest?slots=" + str(w.b), token)).text)
	eq(Array(m.slots), [str(w.b)], "only the world asked for")
	var paths: Array = (m.files as Dictionary).keys()
	check(not paths.is_empty() and paths.all(func(p): return not str(p).begins_with("slots/" + str(w.a) + "/")), "no files of the other world")
	var m2: Dictionary = JSON.parse_string((await _fetch("/api/manifest?slots=" + str(w.hidden), token)).text)
	eq(Array(m2.slots), [], "a hidden world never syncs")
	var m3: Dictionary = JSON.parse_string((await _fetch("/api/manifest", token)).text)
	eq(Array(m3.slots), [str(w.a)], "older phones (no ?slots=): the PC's active world")
	# Toggling a world off on the PC hides it at once.
	Slots.set_on_phone(str(w.b), false)
	var list2: Dictionary = JSON.parse_string((await _fetch("/api/worlds", token)).text)
	check(not (list2.worlds as Array).any(func(x): return str(x.id) == str(w.b)), "switched off: gone from the phone's list")
	await _stop()


# --- The PIN, the PC banner and host.bat's window ---------------------------------------------------------

func test_pin_stays_fresh_and_first_contact_raises_the_pc_banner() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	_worlds()
	main.phone_link.setup(root, _web(root))
	main.phone_link.mode = "lan"
	srv = main.phone_link
	eq(_listen(srv), "", "Phone Link on")
	probe = Probe.new(tree)
	var first: String = srv.pairing.code
	eq(first.length(), 6, "a PIN right away")
	# It runs out: the PC makes a new one by itself.
	srv.pairing.code_expires = Time.get_unix_time_from_system() - 1.0
	srv._process(0.6)
	check(srv.pairing.code != first and srv.pairing.code_seconds_left() > 590, "an expired PIN is replaced")
	# A phone on the Wi-Fi opens the launcher: a banner over the game with the PIN.
	srv.http.debug_peer_override = simulated_phone_ip()
	eq((await _fetch("/")).code, 200, "phone opens the launcher")
	for i in 20:
		srv._process(0.05)
		await frames(1)
	await tree.create_timer(1.7).timeout
	var banner: Button = main.phone_banner
	check(banner != null and banner.visible, "a banner appeared on the PC")
	if banner:
		check(banner.text.contains("Phone connecting: PIN " + Pairing.grouped(srv.pairing.code)), "with the PIN: " + banner.text)
		banner.pressed.emit()
		await frames(2)
		check(main.panels.size() >= 1, "clicking it opens Phone Link")
	# Pairing: the banner says so, and a new PIN is ready for the next phone.
	var before: String = srv.pairing.code
	var tok := await _pair()
	check(tok != "" and srv.pairing.code != before, "paired; the PIN changed")
	await frames(2)
	check(main.phone_banner.text.contains("Paired: Test phone"), "the banner says it: " + main.phone_banner.text)
	srv.http.debug_peer_override = ""
	srv.stop()
	main.queue_free()
	await frames(2)


func test_host_window_shows_address_pin_and_phone() -> void:
	_worlds()
	_start()
	var w: Control = HostWindow.new()
	tree.root.add_child(w)
	w.setup(srv)
	await frames(2)
	eq(w.pin_text(), Pairing.grouped(srv.pairing.code), "the host window shows the PIN, grouped")
	eq(str(w.get("_pin").text), Pairing.grouped(srv.pairing.code))
	eq(str(w.get("_url").text), srv.canonical_url() if srv.canonical_url() != "" else "(no network address found)", "and the address")
	check(str(w.get("_status").text).contains("Waiting for your phone"), "waiting")
	check(str(w.get("_mode").text).contains("Same Wi-Fi") and str(w.get("_mode").text).contains("listening on"), "mode and where it listens: " + str(w.get("_mode").text))
	var phone_ip := simulated_phone_ip()
	srv.http.debug_peer_override = phone_ip
	await _fetch("/")
	for i in 10:
		srv._process(0.05)
		await frames(1)
	w.refresh()
	check(str(w.get("_status").text).contains("Phone connected (%s)" % phone_ip), "then: " + str(w.get("_status").text))
	# Paused pairing shows Unlock in the window.
	srv.pairing.paused = true
	w.refresh()
	check(str(w.get("_pin").text) == "Paused" and (w.get("_unlock") as Button).visible, "paused: Unlock pairing")
	(w.get("_unlock") as Button).pressed.emit()
	check(not srv.pairing.paused, "unlocked from the window")
	w.queue_free()
	await _stop()


func test_no_phone_after_a_minute_shows_the_checklist_and_the_doctor() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	_worlds()
	main.phone_link.setup(root, _web(root))
	main.phone_link.mode = "lan"
	srv = main.phone_link
	eq(_listen(srv), "")
	var tab: Control = PhoneLinkTab.new()
	tab.doctor_runner = func(_snap: Dictionary) -> Array:
		return [{"id": "firewall", "title": "Windows Firewall", "status": "fail", "detail": "2 block rule(s)", "fix": "allow_phone_link.bat"}]
	tab.build(main)
	tree.root.add_child(tab)
	await frames(3)
	var text := _texts(tab)
	check(text.contains(Pairing.grouped(srv.pairing.code)), "the PIN is on the Phone Link screen as soon as it's on")
	check(text.contains("Waiting for your phone"), "waiting")
	check(not text.contains("No phone yet? Check these"), "no checklist yet")
	srv.started_at = Time.get_unix_time_from_system() - 61.0
	for i in 30:
		tab._process(0.1)
		await frames(1)
	text = _texts(tab)
	check(text.contains("No phone yet? Check these") and text.contains("guest network") and text.contains("not localhost"), "after a minute: the checklist")
	check(text.contains("2 block rule(s)"), "and what the Doctor found")
	var lines := PhoneLinkTab.help_checklist("http://192.168.1.42:8737")
	check(lines.size() >= 4 and "\n".join(lines).contains("http://192.168.1.42:8737") and "\n".join(lines).contains("isolation"), "the checklist names the address, isolation, firewall")
	tab.queue_free()
	srv.stop()
	main.queue_free()
	await frames(2)


func _texts(n: Node) -> String:
	var out := PackedStringArray()
	for c in n.find_children("*", "Label", true, false):
		out.append((c as Label).text)
	for c in n.find_children("*", "Button", true, false):
		out.append((c as Button).text)
	return "\n".join(out)


func test_save_menu_switch_decides_what_the_phone_sees() -> void:
	var w := _worlds()
	var SlotActions: GDScript = load("res://scripts/ui/slot_actions.gd")
	var panel: Control = SlotActions.new()
	panel.slot_id = str(w.b)
	tree.root.add_child(panel)
	await frames(2)
	var boxes: Array = panel.find_children("*", "CheckBox", true, false).filter(func(c): return str(c.text).contains("Available on phone"))
	if not check(boxes.size() == 1, "the world's ⋯ panel has \"Available on phone\""):
		panel.queue_free()
		return
	var cb: CheckBox = boxes[0]
	check(cb.button_pressed, "on by default")
	cb.button_pressed = false
	check(not Slots.on_phone(str(w.b)), "unticking hides the world from phones")
	check(not Slots.phone_ids().has(str(w.b)) and Slots.phone_ids().has(str(w.a)), "only that one")
	cb.button_pressed = true
	check(Slots.on_phone(str(w.b)), "ticking shares it again")
	panel.queue_free()
	await frames(1)
