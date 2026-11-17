extends "res://tests/test_case.gd"
## Phase 22: Tailscale as the sure path (three steps that say plainly what's
## missing) and Plan B, the bundled web server engine (its Caddyfile, trusting
## its forwarded phone address only with the per-start secret, falling back to
## the built-in engine, starting/stopping/cleaning up with stand-in programs).
## The real Caddy isn't downloaded by tests (tools/fetch_server.bat does that,
## after asking), and nothing here touches the real Tailscale.

const TailscaleSteps := preload("res://scripts/phone/tailscale_steps.gd")
const BundledEngine := preload("res://scripts/phone/bundled_engine.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const Probe := preload("res://tests/http_probe.gd")
const Firewall := preload("res://scripts/phone/firewall.gd")

const RUNNING := {"installed": true, "running": true, "backend": "Running", "login": "me@example.com", "dns_name": "pc.tail0.ts.net", "https": true, "magicdns": true,
	"peers": [{"name": "my-phone", "os": "android", "online": true, "ip": "100.64.0.11"}]}


func _st(steps: Array, n: int) -> Dictionary:
	return steps[n - 1]


func test_tailscale_three_steps_say_what_is_missing() -> void:
	var s := TailscaleSteps.steps({"installed": false}, {}, "", "")
	eq(str(_st(s, 1).state), "todo", "not installed: step 1 to do")
	eq(str(_st(s, 1).button.arg), TailscaleSteps.DOWNLOAD, "with the download link")
	eq(str(_st(s, 2).state), "waiting", "step 2 waits")
	s = TailscaleSteps.steps({"installed": true, "running": false, "backend": "NeedsLogin"}, {}, "", "")
	check(str(_st(s, 1).state) == "problem" and str(_st(s, 1).lines[0]).contains("NeedsLogin"), "not signed in: said so")
	var no_phone := RUNNING.duplicate(true)
	no_phone.peers = [{"name": "laptop", "os": "windows", "online": true}]
	s = TailscaleSteps.steps(no_phone, {}, "", "")
	check(str(_st(s, 1).state) == "todo" and str(_st(s, 1).lines[1]).contains("No phone on your tailnet"), "no phone on the tailnet: said so")
	var offline := RUNNING.duplicate(true)
	offline.peers[0].online = false
	s = TailscaleSteps.steps(offline, {}, "", "")
	check(str(_st(s, 1).state) == "done" and str(_st(s, 1).lines[1]).contains("offline right now"), "the phone offline: step 1 done, with a note")
	var no_https := RUNNING.duplicate(true)
	no_https.https = false
	s = TailscaleSteps.steps(no_https, {}, "", "")
	check(str(_st(s, 2).state) == "problem" and str(_st(s, 2).lines[0]).contains("HTTPS certificates") and str(_st(s, 2).button.arg) == TailscaleSteps.ADMIN_DNS, "HTTPS certificates off: the admin page")
	s = TailscaleSteps.steps(RUNNING, {"ok": false, "consent_url": "https://login.tailscale.com/f/serve?node=abc"}, "tailscale_serve", "")
	check(str(_st(s, 2).state) == "problem" and str(_st(s, 2).button.arg).contains("f/serve"), "Tailscale's consent needed: the consent page")
	s = TailscaleSteps.steps(RUNNING, {}, "", "")
	check(str(_st(s, 2).state) == "todo" and str(_st(s, 2).button.kind) == "enable", "ready: an Enable button")
	s = TailscaleSteps.steps(RUNNING, {"ok": true}, "tailscale_serve", "https://pc.tail0.ts.net:8765")
	eq(str(_st(s, 2).state), "done", "Serve on: step 2 done")
	check(str(_st(s, 3).state) == "done" and str(_st(s, 3).qr) == "https://pc.tail0.ts.net:8765", "step 3: the https address with a QR code")
	for st in s:
		for line in st.lines:
			check(not str(line).to_lower().contains("funnel on"), "never suggests Funnel")


func test_caddyfile_for_the_bundled_engine() -> void:
	var cf := BundledEngine.caddyfile(8765, 9765, "C:\\Users\\Player\\pocket-dark-world\\build\\web", "/game/abc123/", "s3cret", "C:\\Users\\Player\\Documents\\Polox\\phone")
	for needle in ["admin off", "auto_https off", "http://:8765 {", "bind 0.0.0.0", "handle_path /game/abc123/* {", "root * \"C:/Users/Player/pocket-dark-world/build/web\"", "header Cache-Control \"no-store\"", "file_server", "reverse_proxy 127.0.0.1:9765", "header_up X-Polox-Proxy s3cret", "respond @outside"]:
		check(cf.contains(needle), "the Caddyfile has: " + needle)
	for net in ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "100.64.0.0/10", "127.0.0.0/8"]:
		check(cf.contains(net), "home networks and Tailscale allowed: " + net)
	check(not cf.contains("\\"), "forward slashes only in paths")
	check(not cf.contains("encode"), "no compression (plain, like the built-in engine)")
	check(BundledEngine.caddyfile(8765, 9765, "w", "", "s", "l").find("handle_path") < 0, "no Web build yet: everything goes to Polox")
	check(int(BundledEngine.caddyfile(8765, 9765, "w", "/game/x/", "s", "l").count("{")) == int(BundledEngine.caddyfile(8765, 9765, "w", "/game/x/", "s", "l").count("}")), "braces balance")


func test_forwarded_address_is_believed_only_with_the_secret() -> void:
	var root := fresh_save_root()
	var srv: Node = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, root.path_join("no_web"))
	var port := listen_on_free_port(func(p: int) -> String: return srv.start(p, "127.0.0.1"), "Phone Link")
	srv.http.proxy_secret = "s3cret"
	var p := Probe.new(tree)
	var r: Dictionary = await p.request("127.0.0.1", port, Probe.get_req("/test/info.json", {"X-Polox-Proxy": "s3cret", "X-Forwarded-For": "192.168.1.40"}))
	var info: Dictionary = JSON.parse_string(r.body.get_string_from_utf8())
	eq(str(info.your_ip), "192.168.1.40", "with the secret: the phone's own address")
	check(str(info.engine).contains("Caddy"), "and the answer says the bundled engine handled it")
	r = await p.request("127.0.0.1", port, Probe.get_req("/test/info.json", {"X-Polox-Proxy": "guess", "X-Forwarded-For": "192.168.1.66"}))
	info = JSON.parse_string(r.body.get_string_from_utf8())
	check(str(info.your_ip) != "192.168.1.66" and str(info.engine) == "built-in", "a wrong secret: not believed")
	r = await p.request("127.0.0.1", port, Probe.with_body("POST", "/api/report", JSON.stringify({"v": 1, "results": []}).to_utf8_buffer()).get_string_from_utf8().replace("Host: x\r\n", "Host: x\r\nX-Polox-Proxy: s3cret\r\nX-Forwarded-For: 192.168.1.40\r\n"))
	eq(r.code, 200, "a report through the bundled engine")
	var rep: Array = srv.reports.recent(1)
	check(not rep.is_empty() and str(rep[0].from_ip) == "192.168.1.40" and str(rep[0].server_engine) == "bundled", "the report records the phone and the engine")
	var c: Array = srv.http.contacts(10).filter(func(x): return str(x.ip) == "192.168.1.40")
	check(not c.is_empty(), "contacts show the phone, not 127.0.0.1 (so \"no device has contacted\" stays honest)")
	srv.stop()
	srv.queue_free()
	await frames(2)


func test_bundled_engine_falls_back_and_cleans_up() -> void:
	var root := fresh_save_root()
	var srv: Node = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, root.path_join("no_web"))
	srv.engine_choice = "bundled"
	var port := listen_on_free_port_run(2, func(p: int) -> String: return srv.start(p, "127.0.0.1"), "Phone Link") if not BundledEngine.available() else free_port_run(2)   # (the engine below is given this one and the next)
	if not BundledEngine.available():
		check(port > 0, "Phone Link still starts")
		eq(str(srv.engine_in_use), "built-in", "without Caddy downloaded: the built-in engine answers")
		check(str(srv.engine_error).contains("fetch_server.bat"), "and says how to get it: " + str(srv.engine_error))
		var r: Dictionary = await Probe.new(tree).request("127.0.0.1", port, Probe.get_req("/ping"))
		eq(r.code, 200, "on the same port")
		check(srv.mode_text().contains("built-in engine"), "the screen says which engine")
		srv.stop()
	srv.queue_free()
	# Lifecycle with stand-in programs (never Caddy itself here).
	var eng: Node = BundledEngine.new()
	tree.root.add_child(eng)
	eng.exe_override = "powershell.exe"
	eng.exe_override_args = PackedStringArray(["-NoProfile", "-Command", "Start-Sleep -Seconds 40"])
	var err: String = eng.start(port, port + 1, root.path_join("w"), "", root)
	check(err.contains("didn't start listening"), "a server that never listens: %s" % err)
	check(not eng.running(), "it was stopped, not left behind")
	check(FileAccess.file_exists(root.path_join("phone/Caddyfile")), "the Caddyfile was written in the save folder")
	eng.exe_override = "cmd.exe"
	eng.exe_override_args = PackedStringArray(["/c", "exit", "0"])
	err = eng.start(port, port + 1, root.path_join("w"), "", root)
	check(err.contains("stopped right away"), "one that quits at once: %s" % err)
	# A process id left in engine.pid that isn't Caddy is never killed.
	var other := OS.create_process("powershell.exe", ["-NoProfile", "-Command", "Start-Sleep -Seconds 20"])
	var pid_file := root.path_join("phone/engine.pid")
	FileAccess.open(pid_file, FileAccess.WRITE).store_string(str(other))
	BundledEngine.stop_leftover(pid_file)
	check(OS.is_process_running(other), "a leftover pid that isn't caddy.exe is left alone")
	OS.kill(other)
	eng.queue_free()
	check(Firewall.PORTS.has(8765), "the firewall helper covers the port the engine uses")
