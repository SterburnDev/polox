extends "res://tests/test_case.gd"
## Phase 21: game start-up diagnostics (the block web_build.gd adds to the
## exported page), one-click fixes on the PC's findings, keep-awake on by
## default, /reset. The real-browser side (a good boot, a broken build, no
## WebGL 2, /reset clearing storage) runs in check_phone (test_browser_e2e.gd).

const BootDiag := preload("res://scripts/net/boot_diag.gd")
const WebBuild := preload("res://scripts/phone/web_build.gd")
const NetFacts := preload("res://scripts/net/net_facts.gd")
const FixActions := preload("res://scripts/net/fix_actions.gd")
const DiagRoutes := preload("res://scripts/net/diag_routes.gd")
const ResetPage := preload("res://scripts/net/reset_page.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const PAGE := "<!DOCTYPE html>\n<html lang=\"en\">\n\t<head>\n\t\t<meta charset=\"utf-8\">\n\t</head>\n\t<body><canvas id=\"canvas\"></canvas><script src=\"index.js\"></script></body>\n</html>"


func test_boot_diagnostics_block_is_added_once_and_replaced_cleanly() -> void:
	var once := BootDiag.inject(PAGE)
	check(once.contains(BootDiag.START) and once.contains(BootDiag.END), "the block is in the page")
	check(once.find(BootDiag.START) < once.find("<script src=\"index.js\">"), "before the engine's own scripts (so it sees everything)")
	eq(BootDiag.inject(once), once, "adding it again changes nothing")
	var older := once.replace("polox boot diagnostics", "polox boot diagnostics OLD VERSION")
	var redone := BootDiag.inject(older)
	eq(redone.count(BootDiag.START), 1, "an older copy is replaced, never doubled")
	check(not redone.contains("OLD VERSION"), "with the current one")
	eq(BootDiag.inject("<html><body>no head</body></html>"), "", "a page without <head> is refused")
	check(not BootDiag.SCRIPT.contains("\\"), "no backslashes in the JavaScript")
	for needle in ["GODOT_CONFIG", "fileSizes", "X-Polox-Size", "poloxBooted", "webglcontextlost", "status-notice", "status-progress", "/api/report", "unhandledrejection", "WebAssembly", "webgl2", "Send to PC", "Copy", "/test"]:
		check(BootDiag.SCRIPT.contains(needle), "it handles " + needle)


func test_postprocess_puts_the_block_in_and_the_doctor_wants_it() -> void:
	var root := fresh_save_root()
	var dir := root.path_join("web")
	DirAccess.make_dir_recursive_absolute(dir)
	var html := PAGE.replace("<body>", "<body><script>\nconst missing = Engine.getMissingFeatures({\n\t\tthreads: GODOT_THREADS_ENABLED,\n\t});\n</script>")
	FileAccess.open(dir.path_join("index.html"), FileAccess.WRITE).store_string(html)
	FileAccess.open(dir.path_join("index.js"), FileAccess.WRITE).store_string("GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path);this._source.connect(this.getPositionWorklet());if(start){}")
	for f in ["index.wasm", "index.pck", "index.audio.worklet.js", "index.audio.position.worklet.js"]:
		FileAccess.open(dir.path_join(f), FileAccess.WRITE).store_string("x".repeat(100))
	var r := WebBuild.postprocess(dir)
	check(bool(r.ok), "post-process ok: %s" % str(r.error))
	var out := FileAccess.get_file_as_string(dir.path_join("index.html"))
	eq(out.count(BootDiag.START), 1, "the start-up diagnostics are in index.html once")
	check(WebBuild.patched_on_disk(dir), "and the build counts as ready")
	WebBuild.postprocess(dir)
	eq(FileAccess.get_file_as_string(dir.path_join("index.html")).count(BootDiag.START), 1, "post-processing twice still leaves one copy")
	FileAccess.open(dir.path_join("index.html"), FileAccess.WRITE).store_string(out.replace(BootDiag.block(), ""))
	check(not WebBuild.patched_on_disk(dir), "a build without them is asked to be rebuilt")


func test_findings_carry_one_click_fixes() -> void:
	var facts := {
		"ok": true, "user_sid": "S-1-5-21-1", "listening": [],
		"adapters": [{"name": "Wi-Fi", "description": "Intel Wi-Fi 6", "status": "Up", "ipv4": ["192.168.1.20/24"], "default_route": true, "gateway": "192.168.1.1", "metric": 30, "profile": "Public", "network": "Home", "power_off_allowed": "True"}],
		"firewall_profiles": [{"name": "Public", "enabled": true, "allow_inbound_rules": false, "allow_local_rules": true}],
		"rules": [{"name": "godot", "action": "Block", "enabled": true, "profile": "Public", "protocol": "TCP", "port": "Any", "program": "C:\\g.exe", "local_user": ""}],
		"security_products": [], "vpn_connections": [], "sleep_ac_seconds": 900,
	}
	var res := NetFacts.analyze(facts, {"ports": [], "programs": ["C:\\g.exe"]})
	var by := {}
	for f in res:
		by[str(f.id)] = f
	eq(str(by.profile.get("action", "")), "network_settings", "Public: a button to Windows network settings")
	eq(str(by.profile.get("arg", "")), "Wi-Fi", "for that adapter")
	eq(FixActions.settings_page("Wi-Fi"), "ms-settings:network-wifi", "the Wi-Fi page")
	eq(FixActions.settings_page("Ethernet 4"), "ms-settings:network-ethernet", "the Ethernet page")
	eq(str(by.shields_up.get("action", "")), "firewall_settings", "block-all-incoming: a button to firewall settings")
	eq(str(by.firewall.get("action", "")), "firewall_helper", "block rules: a button for the firewall helper")
	eq(str(by.sleep.get("action", "")), "keep_awake", "sleep: a Keep this PC awake button")
	eq(str(by.adapter_power.get("action", "")), "device_manager", "adapter power saving: Device Manager")
	for a in ["network_settings", "firewall_helper", "firewall_settings", "keep_awake", "device_manager"]:
		check(FixActions.label(a) != a, "%s has a button label" % a)
	var awake := NetFacts.analyze(facts, {"ports": [], "programs": [], "keep_awake": true})
	eq(str(awake.filter(func(f): return str(f.id) == "sleep")[0].status), "ok", "with keep-awake on, sleep isn't a problem")


func test_keep_awake_is_on_by_default() -> void:
	fresh_save_root()
	JsonUtil.write_json(SaveManager.settings_path(), {"phone_link": {"version": 4, "port": 8765}})
	GameState.settings = SaveManager.load_settings()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.configure_phone_link()
	check(bool(main.phone_link.keep_awake), "keep-awake is on unless switched off")
	GameState.settings.phone_link["keep_awake"] = false
	main.configure_phone_link()
	check(not bool(main.phone_link.keep_awake), "and off when you switch it off")
	main.queue_free()
	await frames(3)


func test_reset_page() -> void:
	var r := DiagRoutes.handle({"method": "GET", "path": "/reset", "headers": {}}, {"server": "host"})
	var html: String = (r.bytes as PackedByteArray).get_string_from_utf8()
	check(html.contains("Start fresh on this phone") and html.contains("pairing key") and html.contains("changes made on the phone since its last sync are lost"), "says exactly what it removes")
	check(html.contains("Clear and start fresh") and html.contains("Cancel"), "only after a tap, with a way out")
	check(html.contains("private/incognito"), "and the private-tab tip")
	check(not ResetPage.HTML.contains("\\"), "no backslashes in its JavaScript")
	check(html.contains("Cache-Control: no-store"), "never cached")
