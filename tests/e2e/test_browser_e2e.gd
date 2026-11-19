extends "res://tests/test_case.gd"
## check_phone.bat, part 2: a real (headless) browser does what your phone
## does over Wi-Fi, against this PC's network address: phone size (390x844,
## 2x, touch, a phone user agent), plain HTTP (not a secure context). It opens
## the address, gets the Polox Launcher, types a wrong PIN and then the PIN
## shown on the PC, sees the worlds (with a cover fetched with its key), taps
## Play, the game starts straight in that world after the first sync, places
## a block, syncs, and the block lands in the PC's files. No console errors.
## Skipped (not failed) when neither Edge nor Chrome is installed.

const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const WebBuild := preload("res://scripts/phone/web_build.gd")
const Cdp := preload("res://tests/e2e/cdp.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Slots := preload("res://scripts/core/slots.gd")

const PHONE_UA := "Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36"


func _state(cdp: Cdp) -> Dictionary:
	var s: Variant = await cdp.eval_js("window.poloxTestState || ''")
	var d: Variant = JSON.parse_string(str(s)) if str(s).begins_with("{") else null
	return d if d is Dictionary else {}


func _wait_for(cdp: Cdp, what: Callable, timeout_s: float) -> Dictionary:
	var t := Time.get_ticks_msec()
	var s := {}
	while Time.get_ticks_msec() - t < int(timeout_s * 1000.0):
		s = await _state(cdp)
		if not s.is_empty() and what.call(s):
			return s
		await tree.create_timer(0.5).timeout
	return s


## Polls a JavaScript expression until it's truthy (or the time runs out); returns its last value.
func _wait_js(cdp: Cdp, expr: String, timeout_s: float) -> Variant:
	var t := Time.get_ticks_msec()
	var v: Variant = null
	while Time.get_ticks_msec() - t < int(timeout_s * 1000.0):
		v = await cdp.eval_js(expr)
		var truthy := false
		if v is bool:
			truthy = v
		elif v is String:
			truthy = v != ""
		elif v is float or v is int:
			truthy = v != 0
		else:
			truthy = v != null
		if truthy:
			return v
		await tree.create_timer(0.3).timeout
	return v


## Types like a keyboard into the focused field (CDP inserts the text, the page's input events fire).
func _type(cdp: Cdp, selector: String, text: String) -> void:
	await cdp.eval_js("(function () { var e = document.querySelector('%s'); e.value = ''; e.focus(); return 1; })()" % selector)
	await cdp.send("Input.insertText", {"text": text})


func test_phone_size_browser_launcher_pin_worlds_and_play() -> void:
	var browser := Cdp.find_browser()
	if browser == "":
		print("    SKIPPED: neither Edge nor Chrome is installed (the network suite still ran)")
		return
	var wb := WebBuild.inspect()
	if not check(bool(wb.present) and bool(wb.patched), "the phone version is built and patched (tools\\export_web.bat)"):
		return
	var root := fresh_save_root("e2e_browser")
	StarterContent.create_world("Browser World", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	var slot := SaveManager.slot_id
	var cover := Image.create(64, 40, false, Image.FORMAT_RGBA8)
	cover.fill(Color("#7ad6b0"))
	cover.save_png(Slots.dir(slot).path_join("cover.png"))
	var room_file := root.path_join("slots").path_join(slot).path_join("rooms").path_join(GameState.current_room_id + ".json")
	var tiles_before := (JsonUtil.read_json(room_file, {}).get("tiles", []) as Array).size()
	var srv: Node = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, WebBuild.default_dir())
	srv.mode = PhoneServer.auto_mode({})   # no Tailscale: Same Wi-Fi
	var port := listen_on_free_port(func(p: int) -> String: return srv.start(p), "Phone Link (Same Wi-Fi)", "*")
	var base: String = srv.lan_url()
	print("    browser: %s -> %s" % [browser.get_file(), base])
	if not check(base != "", "this PC has a home-network address to test, like a phone would use"):
		srv.stop()
		srv.queue_free()
		return
	var cdp := Cdp.new(tree)
	var ok: bool = await cdp.launch(browser, root.path_join("_browser_profile"))
	if not check(ok, "headless browser started and connected"):
		cdp.close()
		srv.stop()
		srv.queue_free()
		return
	await cdp.send("Emulation.setDeviceMetricsOverride", {"width": 390, "height": 844, "deviceScaleFactor": 2, "mobile": true})
	await cdp.send("Emulation.setTouchEmulationEnabled", {"enabled": true, "maxTouchPoints": 5})
	await cdp.send("Emulation.setUserAgentOverride", {"userAgent": PHONE_UA, "platform": "Android"})
	# /hello first: the network path on its own.
	await cdp.navigate(base + "/hello")
	await tree.create_timer(1.0).timeout
	check(str(await cdp.eval_js("document.body.innerText")).contains("Polox host reachable"), "/hello loads in the browser")
	eq(await cdp.eval_js("window.isSecureContext"), false, "plain HTTP: not a secure context (like the phone)")
	# The launcher at the PC's address: asks for the PIN.
	cdp.console_errors.clear()
	await cdp.navigate(base + "/")
	var pin_shown: Variant = await _wait_js(cdp, "!document.getElementById('s-pin').classList.contains('hide')", 10.0)
	check(pin_shown == true, "the launcher asks for the PIN")
	check(str(await cdp.eval_js("document.body.innerText")).contains("Enter the PIN shown on your PC"), "in plain words")
	check(str(await cdp.eval_js("document.getElementById('pc').textContent")).contains(PhoneServer.pc_name()), "and says which PC it's connected to")
	await cdp.screenshot(root.path_join("launcher_pin.png"))
	# A wrong PIN first.
	var bad := "000000" if srv.pairing.code != "000000" else "111111"
	await _type(cdp, "#pin", bad)
	var msg: Variant = await _wait_js(cdp, "(document.getElementById('pinmsg').textContent.indexOf('isn') >= 0) ? document.getElementById('pinmsg').textContent : ''", 10.0)
	check(str(msg).contains("PIN isn't right") and str(msg).contains("tries left"), "a wrong PIN: %s" % str(msg))
	# The PIN from the PC: typing the 6th digit sends it.
	var pin_before: String = srv.pairing.code
	await _type(cdp, "#pin", pin_before)
	var worlds: Variant = await _wait_js(cdp, "document.querySelectorAll('.world').length", 15.0)
	check(int(worlds) >= 1, "the right PIN shows the worlds (%s)" % str(worlds))
	eq(int(await cdp.eval_js("(localStorage.getItem('polox_token') || '').length")), 64, "the phone keeps its 64-character key")
	check(srv.pairing.code != pin_before, "the PC shows a new PIN after the pairing")
	eq(srv.pairing.devices().size(), 1, "the PC lists the phone")
	# The PIN travels only inside the request body: never in the page's address or any address it asked for.
	var urls := str(await cdp.eval_js("[location.href].concat(performance.getEntriesByType('resource').map(function (e) { return e.name; })).join(' ')"))
	check(urls.contains("/api/pair"), "(the PIN went in a POST to /api/pair)")
	check(not urls.contains(pin_before) and not urls.contains(bad), "the PIN never appears in an address")
	check(not JSON.stringify(srv.http.recent(200)).contains(pin_before), "nor in the PC's request log")
	check(str(await cdp.eval_js("document.getElementById('worlds').innerText")).contains("Browser World"), "the world's card")
	var img: Variant = await _wait_js(cdp, "(document.querySelector('.cover img') || {}).src || ''", 10.0)
	check(str(img).begins_with("blob:"), "its cover, fetched with the key (%s)" % str(img).substr(0, 20))
	await cdp.screenshot(root.path_join("launcher_worlds.png"))
	# Play: the game starts straight in that world after the first sync.
	await cdp.eval_js("sessionStorage.setItem('polox_test', 'polox-test'); 1")
	await cdp.eval_js("document.querySelector('.world button').click(); 1")
	var t0 := Time.get_ticks_msec()
	var s := await _wait_for(cdp, func(st): return str(st.screen) == "game" and not bool(st.busy), 120.0)
	print("    in the game after %.1f s: %s" % [(Time.get_ticks_msec() - t0) / 1000.0, JSON.stringify(s)])
	eq(str(s.get("screen", "")), "game", "tapping the world starts the game (no title screen in between)")
	# Start-up diagnostics (R6): the game reported itself up, and every check passed.
	var boot: Variant = await _wait_js(cdp, "(window.poloxBoot && window.poloxBoot.stage === 'running') ? 'running' : ''", 30.0)
	eq(str(boot), "running", "start-up diagnostics saw the game come up (window.poloxBooted)")
	eq(str(await cdp.eval_js("window.poloxBoot ? window.poloxBoot.fatal : 'missing'")), "", "no start-up problem")
	check(str(await cdp.eval_js("window.poloxBoot.checks.map(function(c){return (c.ok?'ok ':'BAD ')+c.name+': '+c.detail;}).join(' | ')")).count("BAD") == 0, "every start-up check passed: %s" % str(await cdp.eval_js("window.poloxBoot.checks.map(function(c){return (c.ok?'ok ':'BAD ')+c.name+': '+c.detail;}).join(' | ')")))
	var where := str(await cdp.eval_js("location.pathname + location.hash"))
	check(where.begins_with(str(srv.http.game_prefix()) + "index.html#slot="), "at /game/<build id>/index.html#slot=... (%s)" % where)
	eq(str(srv.phone_session.get("name", "")), "Browser World", "the PC knows what the phone plays")
	eq(str(s.get("sync", "")), "ok", "first sync ok")
	await tree.create_timer(1.0).timeout
	await cdp.eval_js("window.poloxTest.run('place_block')")
	await tree.create_timer(1.0).timeout
	await cdp.eval_js("window.poloxTest.run('sync')")
	# The state the page shows can lag half a second: watch the PC's own file instead.
	var tiles_after := tiles_before
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 30000 and tiles_after <= tiles_before:
		await tree.create_timer(0.5).timeout
		tiles_after = (JsonUtil.read_json(room_file, {}).get("tiles", []) as Array).size()
	print("    the PC had the block after %.1f s" % ((Time.get_ticks_msec() - t1) / 1000.0))
	check(tiles_after > tiles_before, "the block placed in the browser is in the PC's file (%d -> %d tiles)" % [tiles_before, tiles_after])
	await cdp.screenshot(root.path_join("phone_game.png"))
	# Back at the launcher, the phone is remembered: straight to the worlds.
	await cdp.navigate(base + "/")
	var again: Variant = await _wait_js(cdp, "document.querySelectorAll('.world').length", 10.0)
	check(int(again) >= 1 and str(await cdp.eval_js("document.getElementById('s-pin').className")).contains("hide"), "remembered: no PIN the second time")
	# No console errors along the way (warnings like ScriptProcessorNode's deprecation are fine).
	cdp.pump()
	# (The browser logs the deliberate wrong PIN's 401 answer as a failed resource: expected.)
	var errs := Array(cdp.console_errors).filter(func(e): return not str(e).contains("status of 401"))
	eq(errs, [], "no console errors in the launcher or the phone build")
	if not errs.is_empty():
		print("    console: ", "\n    ".join(cdp.console_all.slice(maxi(0, cdp.console_all.size() - 30))))
	print("    screenshots: %s, %s, %s" % [root.path_join("launcher_pin.png"), root.path_join("launcher_worlds.png"), root.path_join("phone_game.png")])
	cdp.close()
	srv.stop()
	srv.queue_free()
	await frames(2)


## The ladder in a real browser engine, at phone size, over this PC's
## home-network address: Polox Ping's "Polox OK" page, then the Connection
## Test (/test) against Polox Ping and against the real Phone Link. Every rung
## must come back green, including the 20 MB download checked by the page's
## own SHA-256, and the page's report must reach the PC.
func test_connection_test_page_in_a_phone_browser() -> void:
	var browser := Cdp.find_browser()
	if browser == "":
		print("    SKIPPED: neither Edge nor Chrome is installed")
		return
	var root := fresh_save_root("e2e_ladder")
	var ping: Node = load("res://scripts/net/ping_server.gd").new()
	tree.root.add_child(ping)
	var pport := listen_on_free_port(func(p: int) -> String: return ping.start(root, [p], "0.0.0.0"), "Polox Ping", "*")
	var srv: Node = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, WebBuild.default_dir())
	srv.mode = PhoneServer.auto_mode({})
	var hport := listen_on_free_port(func(p: int) -> String: return srv.start(p), "Phone Link", "*")
	var ip := PhoneServer.pick_lan(srv.candidates())
	if not check(ip != "", "this PC has a home-network address"):
		ping.stop()
		srv.stop()
		return
	var cdp := Cdp.new(tree)
	var ok: bool = await cdp.launch(browser, root.path_join("_browser_profile"))
	if not check(ok, "headless browser started"):
		cdp.close()
		ping.stop()
		srv.stop()
		return
	await cdp.send("Emulation.setDeviceMetricsOverride", {"width": 390, "height": 844, "deviceScaleFactor": 2, "mobile": true})
	await cdp.send("Emulation.setTouchEmulationEnabled", {"enabled": true, "maxTouchPoints": 5})
	await cdp.send("Emulation.setUserAgentOverride", {"userAgent": PHONE_UA, "platform": "Android"})
	var pbase := "http://%s:%d" % [ip, pport]
	print("    browser: %s -> %s and http://%s:%d" % [browser.get_file(), pbase, ip, hport])
	await cdp.navigate(pbase + "/anything")
	await tree.create_timer(1.0).timeout
	var okpage := str(await cdp.eval_js("document.body.innerText"))
	check(okpage.contains("Polox OK") and okpage.contains(ip), "Polox Ping's page in the browser: %s" % okpage.substr(0, 80))
	for target in [[pbase, "Polox Ping", ping.sink], ["http://%s:%d" % [ip, hport], "Phone Link", srv.reports]]:
		var before: int = target[2].count()
		cdp.console_errors.clear()
		await cdp.navigate(str(target[0]) + "/test")
		var status: Variant = await _wait_js(cdp, "(function(){var s=document.getElementById('status').textContent;return (s.indexOf('All good')>=0||s.indexOf('problem')>=0)?s:'';})()", 120.0)
		var rows := str(await cdp.eval_js("Array.prototype.map.call(document.querySelectorAll('.row'),function(r){return r.className+' | '+r.textContent;}).join(String.fromCharCode(10))"))
		print("    %s /test: %s" % [str(target[1]), str(status)])
		check(str(status).contains("All good"), "every rung green on %s:\n%s" % [str(target[1]), rows])
		check(rows.contains("arrived intact"), "%s: 20 MB arrived and the page's SHA-256 matched" % str(target[1]))
		var sent: Variant = await _wait_js(cdp, "document.getElementById('sent').textContent.indexOf('Sent to the PC')>=0", 15.0)
		check(sent == true, "%s: the page says the report was sent" % str(target[1]))
		var t := Time.get_ticks_msec()
		while target[2].count() <= before and Time.get_ticks_msec() - t < 10000:
			await tree.create_timer(0.2).timeout
		check(target[2].count() > before, "%s: the PC has the report" % str(target[1]))
		await cdp.screenshot(root.path_join("test_page_%s.png" % str(target[1]).replace(" ", "_").to_lower()))
		cdp.pump()
		eq(Array(cdp.console_errors), [], "%s: no console errors on the test page" % str(target[1]))
	var rep: Array = srv.reports.recent(1)
	check(not rep.is_empty() and rows_ok(rep[0]), "the host's report lists every rung as OK, with the launcher's")
	print("    screenshots: %s" % root.path_join("test_page_*.png"))
	cdp.close()
	ping.stop()
	ping.queue_free()
	srv.stop()
	srv.queue_free()
	await frames(2)


static func rows_ok(rep: Dictionary) -> bool:
	var ids: Array = []
	for r in rep.get("results", []):
		if not bool(r.get("ok", false)):
			return false
		ids.append(str(r.get("id", "")))
	return "launcher" in ids and "big" in ids and "env" in ids


## Rung R6 when things go wrong, in a real browser at phone size over the home
## address: a phone version with a cut-off file (the start-up check catches it
## before the engine shows a black screen, says what to do and sends a report
## to the PC), a browser without WebGL 2 (the same, naming it), and /reset
## clearing what the site kept on the phone.
func test_start_up_failures_are_shown_and_reported_and_reset_works() -> void:
	var browser := Cdp.find_browser()
	if browser == "":
		print("    SKIPPED: neither Edge nor Chrome is installed")
		return
	var wb := WebBuild.inspect()
	if not check(bool(wb.present), "the phone version is built"):
		return
	var root := fresh_save_root("e2e_boot")
	var web := root.path_join("web")
	DirAccess.make_dir_recursive_absolute(web)
	for f in Array(WebBuild.REQUIRED) + ["build_info.json"]:
		DirAccess.copy_absolute(WebBuild.default_dir().path_join(f), web.path_join(f))
	var pck := FileAccess.get_file_as_bytes(web.path_join("index.pck"))
	var cut := FileAccess.open(web.path_join("index.pck"), FileAccess.WRITE)
	cut.store_buffer(pck.slice(0, pck.size() / 2))   # a download that stopped half-way on the PC
	cut.close()
	var srv: Node = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, web)
	srv.mode = PhoneServer.auto_mode({})
	var port := listen_on_free_port(func(p: int) -> String: return srv.start(p), "Phone Link", "*")
	var ip := PhoneServer.pick_lan(srv.candidates())
	var base := "http://%s:%d" % [ip, port]
	var game: String = base + str(srv.http.game_prefix()) + "index.html"
	var cdp := Cdp.new(tree)
	if not check(await cdp.launch(browser, root.path_join("_browser_profile")), "headless browser started"):
		cdp.close()
		srv.stop()
		return
	await cdp.send("Emulation.setDeviceMetricsOverride", {"width": 390, "height": 844, "deviceScaleFactor": 2, "mobile": true})
	await cdp.send("Emulation.setUserAgentOverride", {"userAgent": PHONE_UA, "platform": "Android"})
	print("    browser: %s -> %s" % [browser.get_file(), game])
	# 1. A cut-off index.pck.
	await cdp.navigate(game)
	var fatal: Variant = await _wait_js(cdp, "(window.poloxBoot && window.poloxBoot.fatal) || ''", 30.0)
	check(str(fatal).contains("don't match") and str(fatal).contains("index.pck"), "a cut-off file is caught and named: %s" % str(fatal))
	eq(str(await cdp.eval_js("getComputedStyle(document.getElementById('pxb-panel')).display")), "block", "the start-up card is on screen")
	check(str(await cdp.eval_js("document.getElementById('pxb-panel').innerText")).contains("Build the phone version"), "with what to do")
	var t := Time.get_ticks_msec()
	while srv.reports.count() == 0 and Time.get_ticks_msec() - t < 15000:
		await tree.create_timer(0.2).timeout
	var rep: Array = srv.reports.recent(1)
	check(not rep.is_empty() and str(rep[0].get("page", "")) == "game" and not bool(rep[0].results[0].ok), "the PC got the start-up report by itself")
	await cdp.screenshot(root.path_join("boot_files.png"))
	# 2. A browser without WebGL 2 (the real files are back).
	DirAccess.copy_absolute(WebBuild.default_dir().path_join("index.pck"), web.path_join("index.pck"))
	var hook: Dictionary = await cdp.send("Page.addScriptToEvaluateOnNewDocument", {"source": "HTMLCanvasElement.prototype.getContext=(function(g){return function(t,o){return t==='webgl2'?null:g.call(this,t,o);};})(HTMLCanvasElement.prototype.getContext);"})
	await cdp.navigate(game)
	fatal = await _wait_js(cdp, "(window.poloxBoot && window.poloxBoot.fatal) || ''", 30.0)
	check(str(fatal).contains("WebGL 2"), "no WebGL 2 is caught and named: %s" % str(fatal))
	check(str(await cdp.eval_js("document.getElementById('pxb-panel').innerText")).contains("Chrome"), "with what to do")
	await cdp.screenshot(root.path_join("boot_webgl.png"))
	await cdp.send("Page.removeScriptToEvaluateOnNewDocument", {"identifier": str(hook.get("identifier", ""))})
	# 3. /reset clears what the site kept on this phone.
	await cdp.navigate(base + "/")
	await tree.create_timer(1.0).timeout
	await cdp.eval_js("localStorage.setItem('polox_token','x'.repeat(64)); localStorage.setItem('polox_slot','w'); 1")
	eq(int(await cdp.eval_js("localStorage.length")), 2, "(the phone remembers a pairing)")
	await cdp.navigate(base + "/reset")
	await tree.create_timer(1.0).timeout
	check(str(await cdp.eval_js("document.body.innerText")).contains("pairing key"), "/reset says what it removes")
	eq(int(await cdp.eval_js("localStorage.length")), 2, "nothing goes before the tap")
	await cdp.eval_js("document.getElementById('go').click(); 1")
	var done: Variant = await _wait_js(cdp, "document.getElementById('done').textContent", 10.0)
	check(str(done).contains("Done"), "it finishes: %s" % str(done))
	eq(int(await cdp.eval_js("localStorage.length")), 0, "the pairing key and choices are gone")
	print("    screenshots: %s, %s" % [root.path_join("boot_files.png"), root.path_join("boot_webgl.png")])
	cdp.close()
	srv.stop()
	srv.queue_free()
	await frames(2)
