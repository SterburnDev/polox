extends RefCounted
## The Phone Link Doctor: checks everything between "Polox on the PC" and
## "the game on the phone", explains each failure in plain language with the
## fix, and builds a diagnostics text (no tokens, codes, keys or chat).
##
## Checks: the phone version (built, complete, current, plain-HTTP patches,
## templates, preset), Phone Link on, every address answering (a real HTTP
## request to /hello.json and the game files, including the Tailscale Serve
## HTTPS address), Windows Firewall (block rules, allow rule, network type),
## Tailscale (installed, connected, MagicDNS, HTTPS, Polox's Serve mapping,
## Funnel), pairing, the last phone contact, keep-awake.
##
## run() is blocking (a few seconds: PowerShell, the Tailscale CLI, network
## round trips), so the Doctor screen calls it on a thread. Nothing here
## touches the scene tree; it reads a snapshot of the server's state.

const NetRules := preload("res://scripts/phone/net_rules.gd")
const Tailscale := preload("res://scripts/phone/tailscale.gd")
const Firewall := preload("res://scripts/phone/firewall.gd")
const WebBuild := preload("res://scripts/phone/web_build.gd")
const NetFacts := preload("res://scripts/net/net_facts.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")

const ICONS := {"ok": "✓", "warn": "⚠", "fail": "✗", "skip": "–"}
## A reply that keeps arriving may run this many times its timeout; one that stalls ends at the timeout.
const BODY_TIME_FACTOR := 5


## What the Doctor needs to know about the running Phone Link (main thread fills it in).
static func snapshot(server: Node) -> Dictionary:
	var s := {
		"running": false, "mode": "lan", "port": 8737, "serve_port": 8737, "bind": "", "scope": "",
		"canonical": "", "urls": [], "candidates": [], "web_dir": WebBuild.default_dir(), "devices": [],
		"last_contact": {}, "keep_awake": false, "recent": [], "ts_status": {}, "serve_result": {}, "last_error": "",
		"tailscale_only": false, "require_login": true, "lan_url": "", "ts_url": "", "pin_active": false, "paused": false,
		"contacts": [], "root": "", "facts": {}, "game_path": "",
		"engine_choice": "builtin", "engine_in_use": "built-in", "engine_error": "",
	}
	if server == null:
		return s
	s.running = bool(server.running)
	s.mode = str(server.mode)
	s.port = int(server.port)
	s.serve_port = int(server.serve_port)
	s.web_dir = str(server.web_dir)
	s.canonical = server.canonical_url()
	s.urls = Array(server.urls())
	s.candidates = server.candidates()
	s.last_contact = (server.last_contact as Dictionary).duplicate()
	s.keep_awake = bool(server.keep_awake)
	s.ts_status = (server.ts_status as Dictionary).duplicate(true)
	s.serve_result = (server.serve_result as Dictionary).duplicate(true)
	s.last_error = str(server.last_error)
	s.tailscale_only = bool(server.tailscale_only)
	s.require_login = bool(server.require_login)
	s.lan_url = server.lan_url()
	s.ts_url = server.ts_url()
	s.root = str(server.root)
	s.engine_choice = str(server.get("engine_choice") if server.get("engine_choice") != null else "builtin")
	s.engine_in_use = str(server.get("engine_in_use") if server.get("engine_in_use") != null else "built-in")
	s.engine_error = str(server.get("engine_error") if server.get("engine_error") != null else "")
	if server.pairing:
		s.pin_active = server.pairing.code_seconds_left() > 0
		s.paused = bool(server.pairing.paused)
		for d in server.pairing.devices():
			s.devices.append({"name": str(d.get("name", "")), "paired": str(d.get("paired", "")), "last_seen": str(d.get("last_seen", "")), "host": str(d.get("host", ""))})
	if server.http:
		s.bind = str(server.http.bind_address)
		s.scope = str(server.http.source_scope)
		s.recent = server.http.recent(50)
		s.contacts = server.http.contacts(100)
		s.game_path = server.http.game_prefix()
	return s


static func _r(id: String, title: String, status: String, detail: String, fix: String = "") -> Dictionary:
	return {"id": id, "title": title, "status": status, "detail": detail, "fix": fix}


## All checks, in the order a person would fix them. `ts` and `firewall_runner`
## can be swapped by tests.
static func run(snap: Dictionary, ts: Tailscale = null, firewall_text: String = "") -> Array:
	var out: Array = []
	var mode := str(snap.mode)
	var port := int(snap.port)
	# 1. The phone version.
	var wb := WebBuild.inspect(str(snap.web_dir))
	if not bool(wb.present):
		var how := "In Polox: Settings > Phone Link > step 1, Build the phone version." if WebBuild.templates_present() else "First build Polox's web engine (tools\\build_engine.py web), then Settings > Phone Link > Build the phone version."
		out.append(_r("web_build", "Phone version of the game", "fail", "Not built yet (no %s)." % str(snap.web_dir).path_join("index.html"), how))
	elif not bool(wb.complete):
		out.append(_r("web_build", "Phone version of the game", "fail", "Incomplete: missing %s." % ", ".join(wb.missing), "Build it again (Settings > Phone Link > step 1)."))
	elif not bool(wb.current):
		out.append(_r("web_build", "Phone version of the game", "warn", "Built %s, but this PC's Polox has changed since (build %s vs %s)." % [str(wb.built), str(wb.build_id).substr(0, 8), WebBuild.current_build_id().substr(0, 8)], "Build it again so the phone gets the same version (step 1)."))
	else:
		out.append(_r("web_build", "Phone version of the game", "ok", "%.1f MB, built %s, matches this PC (build %s)%s." % [float(wb.mb), str(wb.built), str(wb.build_id).substr(0, 8), ", gzip copies ready" if bool(wb.gzip) else ""]))
	if bool(wb.present) and not WebBuild.patched_on_disk(str(snap.web_dir)):
		out.append(_r("web_http", "Plain-HTTP start-up fix", "fail", "Same Wi-Fi is plain HTTP, and this build still has Godot's HTTPS-only start-up check: the phone would show \"Secure Context... (use HTTPS)\".", "Build the phone version again (it applies the fix), or use Tailscale Serve (HTTPS)."))
	var problems := WebBuild.preset_problems()
	if not problems.is_empty():
		out.append(_r("web_preset", "Web export settings", "fail", "; ".join(problems), "Restore export_presets.cfg from Polox's files."))
	# 2. Phone Link itself.
	if not bool(snap.running):
		var why := str(snap.last_error)
		out.append(_r("running", "Phone Link", "fail", "Off." + ((" Last try: " + why) if why != "" else ""), "Settings > Phone Link: switch it on (or run host.bat)."))
	else:
		if str(snap.bind) == "?":
			out.append(_r("running", "Phone Link", "ok", "On in another Polox window: %s, port %d." % [_mode_label(mode), port]))
		else:
			out.append(_r("running", "Phone Link", "ok", "On: %s, listening on %s:%d (allowed: %s)." % [_mode_label(mode), "this PC only" if str(snap.bind) == "127.0.0.1" else "all addresses", port, _scope_label(str(snap.scope))]))
		if str(snap.get("engine_choice", "builtin")) == "bundled":
			if str(snap.get("engine_in_use", "")) == "bundled":
				out.append(_r("engine", "Server engine", "ok", "The bundled web server (Caddy) answers phones; Polox's own server sits behind it on this PC only."))
			else:
				out.append(_r("engine", "Server engine", "warn", "The bundled web server was chosen but isn't running, so the built-in engine answers: %s" % str(snap.get("engine_error", "")), "Run tools\\fetch_server.bat once, then switch Phone Link off and on."))
		if bool(snap.tailscale_only) and mode != "lan":
			out.append(_r("same_wifi", "Same Wi-Fi", "warn", "\"Tailscale only\" is on: phones on your home Wi-Fi are refused (they see \"not allowed\").", "Settings > Phone Link > Advanced: untick Tailscale only."))
		elif str(snap.lan_url) == "":
			out.append(_r("same_wifi", "Same Wi-Fi", "warn", "This PC has no home-network address right now (Wi-Fi or Ethernet not connected?).", "Connect the PC to your home network, then switch Phone Link off and on."))
		else:
			out.append(_r("same_wifi", "Same Wi-Fi", "ok", "Phones on your Wi-Fi open %s (no app or account needed)." % str(snap.lan_url)))
	# 3. Every address answers, with the game files.
	if bool(snap.running):
		out.append_array(_address_checks(snap, wb))
	# 4. This PC (rung R0): listening, adapter, network type, firewall, VPN, sleep.
	#    Tests pass `firewall_text` and get the older firewall-only check.
	if OS.get_name() == "Windows" and firewall_text == "" and NetFacts.available():
		if (snap.facts as Dictionary).is_empty():
			snap.facts = NetFacts.collect([port] if bool(snap.running) else [])
		for f in NetFacts.analyze(snap.facts, {"ports": [port] if bool(snap.running) else [], "programs": NetFacts.polox_programs(), "server": "host", "keep_awake": bool(snap.keep_awake)}):
			if mode == "tailscale_serve" and str(f.id) == "firewall" and str(f.status) == "fail":
				f["status"] = "warn"   # Serve still works through Tailscale
			out.append(f)
	elif OS.get_name() == "Windows":
		var fw := Firewall.parse_check(firewall_text) if firewall_text != "" else Firewall.check(port)
		var bad := "warn" if mode == "tailscale_serve" else "fail"   # Serve still works through Tailscale
		if not bool(fw.known):
			out.append(_r("firewall", "Windows Firewall", "warn", str(fw.error), "Run allow_phone_link.bat %d check to see the rules." % port))
		elif int(fw.blocking) > 0:
			out.append(_r("firewall", "Windows Firewall", bad, "%d block rule(s) for Polox's Godot stop phones on your Wi-Fi (Windows made them when its \"allow access?\" prompt was dismissed)." % int(fw.blocking), "Double-click allow_phone_link.bat once (it explains, asks for admin, and can be undone)."))
		elif not bool(fw.allowed):
			out.append(_r("firewall", "Windows Firewall", bad, "No rule lets port %d in for Polox on your %s network(s), so phones on your Wi-Fi may be stopped." % [port, "/".join(fw.profiles)], "Double-click allow_phone_link.bat once, or click Allow when Windows asks."))
		else:
			out.append(_r("firewall", "Windows Firewall", "ok", "Port %d is allowed for Polox on %s." % [port, "/".join(fw.profiles)]))
		for n in fw.networks:
			if n is Dictionary and str(n.get("category", "")) == "Public" and not str(n.get("alias", "")).to_lower().contains("tailscale"):
				out.append(_r("network_type", "Network type", "warn", "\"%s\" is set to Public in Windows." % str(n.get("alias", "")), "If it's your home network: Windows Settings > Network & internet > %s > Network profile type: Private." % str(n.get("alias", ""))))
	# 5. Tailscale.
	out.append_array(_tailscale_checks(snap, ts))
	# 6. Pairing and the phone.
	if bool(snap.running):
		if bool(snap.paused):
			out.append(_r("pin", "PIN", "fail", "Pairing is paused after too many wrong PINs this hour.", "Settings > Phone Link: Unlock pairing."))
		else:
			out.append(_r("pin", "PIN", "ok" if bool(snap.pin_active) else "warn", "A PIN is on the Phone Link screen (a new one every 10 minutes and after each pairing)." if bool(snap.pin_active) else "No PIN right now.", "" if bool(snap.pin_active) else "Switch Phone Link off and on."))
	var devices: Array = snap.devices
	if devices.is_empty():
		out.append(_r("pairing", "Pairing", "warn" if bool(snap.running) else "skip", "No phone is paired yet.", "Open the address on the phone and type the PIN shown on the PC."))
	else:
		var d: Dictionary = devices[0]
		var where := " at %s" % str(d.host) if str(d.host) != "" else ""
		out.append(_r("pairing", "Pairing", "ok", "%s paired%s on %s, last seen %s." % [str(d.name), where, str(d.paired).replace("T", " ").substr(0, 16), str(d.last_seen).replace("T", " ").substr(0, 16)]))
		var canon_host := str(snap.canonical).get_slice("://", 1)
		if canon_host != "" and str(d.host) != "" and str(d.host) != canon_host:
			out.append(_r("address", "Same address", "warn", "The phone paired at %s, but the main address is now %s. The browser keeps pairing and saves per address." % [str(d.host), canon_host], "Open %s on the phone (pair again there if asked)." % str(snap.canonical)))
	var lc: Dictionary = snap.last_contact
	if bool(snap.running):
		var odd := (snap.contacts as Array).filter(func(c): return str(c.get("outcome", "")) != "request" and NetRules.kind(str(c.ip)) != "loopback" and not NetRules.own_addresses().has(str(c.ip)))
		if lc.is_empty() and odd.is_empty():
			out.append(_r("contact", "Phone reached Polox", "warn", "No device has contacted the host yet (not even a refused or broken attempt).", "Open %s on the phone. If it doesn't load, nothing is getting through to this PC: run the Network test (Polox Ping) and the checks above." % str(snap.canonical)))
		elif lc.is_empty():
			var o: Dictionary = odd[-1]
			out.append(_r("contact", "Phone reached Polox", "fail", "%s connected but never finished a request (%s)." % [str(o.ip), {"nothing": "it sent nothing", "https": "it spoke HTTPS to this HTTP port", "bad": "it sent something that isn't a web request"}.get(str(o.outcome), str(o.outcome))], "Type the address with http:// in front, try another browser, or run the Connection Test at <address>/test on the phone."))
		else:
			out.append(_r("contact", "Phone reached Polox", "ok", "%s from %s%s (%s, %d)." % [Time.get_datetime_string_from_unix_time(int(lc.t)).replace("T", " "), str(lc.ip), (" " + str(lc.via)) if str(lc.get("via", "")) != "" else "", str(lc.path), int(lc.status)]))
	var reports := ReportSink.load_saved(str(snap.get("root", "")), 3) if str(snap.get("root", "")) != "" else []
	for rep in reports:
		var bad := (rep.get("results", []) as Array).filter(func(x): return x is Dictionary and not bool(x.get("ok", false)) and str(x.get("level", "")) != "warn")
		out.append(_r("report", "Phone report", "ok" if bad.is_empty() else "fail", ReportSink.summary(rep), "" if bad.is_empty() else _report_fix(rep)))
	out.append(_r("awake", "Keep this PC awake", "ok" if bool(snap.keep_awake) else "skip", "On while Phone Link is on." if bool(snap.keep_awake) else "Off: if the PC sleeps, the phone can't reach it.", "" if bool(snap.keep_awake) else "Settings > Phone Link > Keep this PC awake."))
	return out


## What a phone report's first failure means.
static func _report_fix(rep: Dictionary) -> String:
	for x in rep.get("results", []):
		if not x is Dictionary or bool(x.get("ok", false)):
			continue
		match str(x.get("id", "")):
			"ping", "info":
				return "The page loaded but later requests failed: the connection is flaky. Keep the phone near the router and try again."
			"env":
				return "This browser can't run the game: update it, switch off battery saver, or use Chrome (Android) / Safari (iPhone)."
			"storage":
				return "The browser won't keep data (private tab?): use a normal tab."
			"big":
				return "Big downloads break: keep the screen on, stay near the router, switch off Wi-Fi power saving; or use Tailscale."
			"launcher":
				return "The launcher's API failed: switch Phone Link off and on, then reload the page."
			"boot":
				return "The game didn't start on the phone: see the report's log lines in Copy diagnostics."
	return ""


static func _mode_label(m: String) -> String:
	return {"tailscale_serve": "Same Wi-Fi + Tailscale HTTPS", "tailscale_direct": "Same Wi-Fi + Tailscale (HTTP)", "lan": "Same Wi-Fi"}.get(m, m)


static func _scope_label(s: String) -> String:
	return {"local": "this PC (Tailscale brings the phone)", "tailscale": "this PC + Tailscale", "home": "this PC + home network + Tailscale"}.get(s, s)


static func _address_checks(snap: Dictionary, wb: Dictionary) -> Array:
	var out: Array = []
	var port := int(snap.port)
	var targets: Array = [["This PC (127.0.0.1)", "http://127.0.0.1:%d" % port, true]]
	if str(snap.mode) == "tailscale_serve" and str(snap.ts_url) != "":
		targets.append(["Tailscale Serve (away from home)", str(snap.ts_url), true])
	if str(snap.bind) != "127.0.0.1":
		for c in snap.candidates:
			if bool(c.virtual):
				continue
			var reach := not (str(snap.scope) == "tailscale" and str(c.kind) != "tailscale")
			targets.append(["%s (%s)" % [str(c.ip), str(c.reason)], "http://%s:%d" % [c.ip, port], reach])
	for t in targets:
		var label := str(t[0])
		var base := str(t[1])
		var r := fetch(base + "/hello.json", "GET", 6.0)
		if not bool(t[2]):
			var refused := int(r.code) == 403
			out.append(_r("addr", "Address " + label, "ok" if refused or int(r.code) == 0 else "warn", "Refused, as set (Tailscale only)." if refused else "Answered %d (expected a refusal: Tailscale only)." % int(r.code)))
			continue
		if int(r.code) != 200:
			var why := str(r.error) if str(r.error) != "" else "HTTP %d" % int(r.code)
			out.append(_r("addr", "Address " + label, "fail", "No answer from %s/hello.json (%s)." % [base, why], _address_fix(base)))
			continue
		var j: Variant = JSON.parse_string(r.body.get_string_from_utf8())
		if not j is Dictionary or str(j.get("app", "")) != "Polox":
			out.append(_r("addr", "Address " + label, "fail", "Something answered at %s, but it isn't Polox." % base, "Another program uses this port: pick another Phone Link port."))
			continue
		var files := ""
		if bool(wb.present):
			var w := fetch(base + (str(snap.get("game_path", "")) if str(snap.get("game_path", "")) != "" else "/") + "index.wasm", "HEAD", 6.0)
			var ctype := str(w.headers.get("content-type", ""))
			var size := int(str(w.headers.get("content-length", "-1")))
			if int(w.code) != 200 or ctype != "application/wasm" or size != int(wb.files.get("index.wasm", -2)):
				out.append(_r("addr", "Address " + label, "fail", "Polox answers, but the game file looks wrong (HTTP %d, %s, %d bytes)." % [int(w.code), ctype, size], "Build the phone version again (step 1)."))
				continue
			files = ", game files OK (%.1f MB wasm, application/wasm)" % (size / 1048576.0)
		out.append(_r("addr", "Address " + label, "ok", "Answers in %d ms%s." % [int(r.ms), files]))
	return out


static func _address_fix(base: String) -> String:
	if base.begins_with("https://"):
		return "Check Tailscale is connected on this PC, and that this PC can resolve its own .ts.net name (MagicDNS)."
	if base.contains("127.0.0.1"):
		return "Phone Link isn't really listening: switch it off and on, or restart Polox."
	return "This PC can't reach itself at that address: the adapter may be down. Try the next address, or Tailscale Serve."


static func _tailscale_checks(snap: Dictionary, ts_in: Tailscale) -> Array:
	var out: Array = []
	var ts := ts_in if ts_in != null else Tailscale.new()
	var needed := str(snap.mode) in ["tailscale_serve", "tailscale_direct"]
	if not ts.installed():
		out.append(_r("tailscale", "Tailscale", "fail" if needed else "skip", "Not installed on this PC.", "Install Tailscale on the PC and the phone (tailscale.com/download), log in to the same account on both."))
		return out
	var s := ts.status()
	if not bool(s.running):
		out.append(_r("tailscale", "Tailscale", "fail" if needed else "warn", "Installed, but not connected (%s). %s" % [str(s.backend), str(s.error)], "Open Tailscale on the PC and log in / connect."))
		return out
	var phone := ""
	for p in s.peers:
		if str(p.os) in ["android", "iOS", "ios"]:
			phone += "%s%s (%s)" % [", " if phone != "" else "", str(p.name), "online" if bool(p.online) else "offline"]
	out.append(_r("tailscale", "Tailscale", "ok", "Connected as %s: %s (%s). %s" % [str(s.login) if str(s.login) != "" else "you", str(s.dns_name), str(s.ipv4), ("Phones on your tailnet: " + phone + ".") if phone != "" else "No phone on your tailnet yet."],
		"" if phone != "" else "Install Tailscale on the phone and log in with the same account."))
	if not bool(s.magicdns):
		out.append(_r("magicdns", "MagicDNS", "fail" if needed else "warn", "Off: the phone can't use this PC's name.", "Tailscale admin page > DNS > enable MagicDNS."))
	if not bool(s.https):
		out.append(_r("https", "HTTPS certificates", "fail" if str(snap.mode) == "tailscale_serve" else "skip", "Off for your tailnet: Tailscale Serve can't give Polox an https:// address.", "Tailscale admin page > DNS > HTTPS Certificates: enable."))
	var sv := ts.serve_status(str(s.dns_name))
	var sp := str(int(snap.serve_port))
	var mine := "http://127.0.0.1:%d" % int(snap.port)
	if str(snap.mode) == "tailscale_serve":
		var m: Dictionary = sv.ports.get(sp, {})
		if not bool(snap.running):
			out.append(_r("serve", "Tailscale Serve", "skip", "Phone Link is off, so Polox has no Serve mapping (as it should)."))
		elif str(m.get("proxy", "")) == mine:
			out.append(_r("serve", "Tailscale Serve", "ok", "https://%s:%s -> %s (tailnet only)." % [str(s.dns_name), sp, mine]))
		else:
			var consent := str((snap.serve_result as Dictionary).get("consent_url", ""))
			out.append(_r("serve", "Tailscale Serve", "fail", "Polox's mapping isn't there%s." % ((": " + str(m.get("proxy", ""))) if not m.is_empty() else ""), ("Open this page to allow it: " + consent) if consent != "" else "Switch Phone Link off and on again (Polox sets the mapping up)."))
	if sv.funnel.has(sp):
		out.append(_r("funnel", "Tailscale Funnel", "fail", "Port %s is on Funnel: anyone on the internet could reach it." % sp, "Run: tailscale funnel --https=%s off   (Polox never uses Funnel)" % sp))
	elif not sv.funnel.is_empty():
		out.append(_r("funnel", "Tailscale Funnel", "ok", "Polox's port isn't on Funnel (port(s) %s of yours are, which Polox leaves alone)." % ", ".join(PackedStringArray(sv.funnel.keys()))))
	else:
		out.append(_r("funnel", "Tailscale Funnel", "ok", "Nothing is on Funnel (Polox never uses it)."))
	return out


# --- A tiny blocking HTTP(S) client (Doctor thread only) ---------------------------------------------

## {code, headers (lowercase), body, error, ms}. Follows no redirects.
static func fetch(url: String, method: String = "GET", timeout_s: float = 6.0) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var out := {"code": 0, "headers": {}, "body": PackedByteArray(), "error": "", "ms": 0}
	var https := url.begins_with("https://")
	var rest := url.get_slice("://", 1)
	var hostport := rest.get_slice("/", 0)
	var path := rest.substr(hostport.length())
	if path == "":
		path = "/"
	var host := hostport
	var port := 443 if https else 80
	if hostport.contains(":"):
		host = hostport.get_slice(":", 0)
		port = hostport.get_slice(":", 1).to_int()
	var c := HTTPClient.new()
	var err := c.connect_to_host(host, port, TLSOptions.client() if https else null)
	if err != OK:
		out.error = "can't connect (%d)" % err
		return out
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while c.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		c.poll()
		if Time.get_ticks_msec() > deadline:
			c.close()
			out.error = "timed out connecting"
			return out
		OS.delay_msec(10)
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		c.close()
		out.error = {HTTPClient.STATUS_CANT_RESOLVE: "name not found", HTTPClient.STATUS_CANT_CONNECT: "connection refused or blocked", HTTPClient.STATUS_TLS_HANDSHAKE_ERROR: "HTTPS handshake failed"}.get(c.get_status(), "can't connect (status %d)" % c.get_status())
		return out
	var m := HTTPClient.METHOD_HEAD if method == "HEAD" else HTTPClient.METHOD_GET
	var req_err := c.request(m, path, PackedStringArray(["User-Agent: Polox-Doctor", "Accept-Encoding: identity"]))
	if req_err != OK:
		c.close()
		out.error = "couldn't send request (%d)" % req_err
		return out
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		c.poll()
		if Time.get_ticks_msec() > deadline:
			c.close()
			out.error = "timed out waiting for an answer"
			return out
		OS.delay_msec(5)
	if not c.has_response():
		c.close()
		out.error = "no answer"
		return out
	out.code = c.get_response_code()
	for h in c.get_response_headers():
		var i := str(h).find(":")
		if i > 0:
			out.headers[str(h).substr(0, i).strip_edges().to_lower()] = str(h).substr(i + 1).strip_edges()
	var body := PackedByteArray()
	# A body that stalls ends at the deadline; one that keeps arriving gets longer, but not for ever
	# (a trickle of a byte now and then used to be read until two megabytes had come).
	var body_deadline := t0 + int(timeout_s * 1000.0) * BODY_TIME_FACTOR
	while c.get_status() == HTTPClient.STATUS_BODY and method != "HEAD":
		c.poll()
		var chunk := c.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() > deadline:
				out.error = "timed out reading answer"
				break
			OS.delay_msec(2)
		else:
			body.append_array(chunk)
		if body.size() > 2_000_000:
			break
		if Time.get_ticks_msec() > body_deadline:
			out.error = "timed out reading answer"
			break
	out.body = body
	out.ms = Time.get_ticks_msec() - t0
	c.close()
	return out


# --- phone_link.log (for a Polox that runs in another window) -------------------------------------------

## The last `n` requests from phone_link.log, parsed back into log entries.
static func log_tail(path: String, n: int = 50) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var re := RegEx.create_from_string("^(\\S+) (\\S+)(?: via (\\S+ \\S+))? (\\S+) (.+) (\\d+) (\\d+)B (\\d+)ms$")
	for line in lines.slice(maxi(0, lines.size() - n)):
		var m := re.search(str(line).strip_edges())
		if m == null:
			continue
		out.append({"t": Time.get_unix_time_from_datetime_string(m.get_string(1)), "ip": m.get_string(2), "via": m.get_string(3),
			"method": m.get_string(4), "path": m.get_string(5), "status": m.get_string(6).to_int(), "bytes": m.get_string(7).to_int(), "ms": m.get_string(8).to_int()})
	return out


## The most recent phone request in phone_link.log ({} if none).
static func last_contact_from_log(path: String) -> Dictionary:
	var entries := log_tail(path, 300)
	entries.reverse()
	for e in entries:
		var own := NetRules.own_addresses()
		var via := str(e.via)
		var phone := (via != "" and not own.has(via.get_slice(" ", 1))) or (via == "" and NetRules.kind(str(e.ip)) != "loopback" and not own.has(str(e.ip)))
		if int(e.status) != 403 and phone:
			return e
	return {}


# --- Diagnostics text ---------------------------------------------------------------------------------

## What to paste back to whoever helps: versions, addresses, results, the last
## 50 requests. Never tokens, codes, keys or chat (none of them are in here).
static func diagnostics(snap: Dictionary, results: Array) -> String:
	var lines := PackedStringArray()
	lines.append("Polox Phone Link diagnostics, %s" % Time.get_datetime_string_from_system(false, true))
	lines.append("Polox %s (build %s), Godot %s, %s %s" % [str(ProjectSettings.get_setting("application/config/version", "")), WebBuild.current_build_id().substr(0, 8), Engine.get_version_info().string, OS.get_name(), OS.get_version()])
	lines.append("Mode: %s | port %d | serve port %d | bind %s | allowed: %s | Tailscale only: %s" % [_mode_label(str(snap.mode)), int(snap.port), int(snap.serve_port), str(snap.bind), str(snap.scope), str(snap.tailscale_only)])
	lines.append("Main address: %s" % str(snap.canonical))
	lines.append("Addresses:")
	for c in snap.candidates:
		lines.append("  %-16s %-10s %s%s" % [str(c.ip), str(c.kind), str(c.label), (" [" + str(c.description) + "]") if str(c.description) != "" else ""])
	lines.append("Checks:")
	for r in results:
		lines.append("  %s %s: %s" % [ICONS.get(r.status, "?"), str(r.title), str(r.detail)])
		if str(r.fix) != "" and str(r.status) in ["fail", "warn"]:
			lines.append("      fix: " + str(r.fix))
	lines.append("Every connection (time, from, what happened):")
	var cts: Array = snap.get("contacts", [])
	for c in cts.slice(-30):
		lines.append("  %s %s %s %s %d" % [Time.get_datetime_string_from_unix_time(int(c.t)).substr(11), str(c.ip), str(c.outcome), str(c.get("path", "")), int(c.get("status", 0))])
	if cts.is_empty():
		lines.append("  (no device has contacted the host yet)")
	if not (snap.get("facts", {}) as Dictionary).is_empty():
		lines.append("This PC:")
		lines.append(NetFacts.text(snap.facts))
	for rep in (ReportSink.load_saved(str(snap.get("root", "")), 3) if str(snap.get("root", "")) != "" else []):
		lines.append("Phone report:")
		lines.append(ReportSink.text(rep))
	lines.append("Last requests (time, from, method, path, status, bytes, ms):")
	for e in snap.recent:
		lines.append("  %s %s%s %s %s %d %d %d" % [Time.get_datetime_string_from_unix_time(int(e.t)).substr(11), str(e.ip), (" " + str(e.via)) if str(e.get("via", "")) != "" else "", str(e.method), str(e.path), int(e.status), int(e.bytes), int(e.ms)])
	if (snap.recent as Array).is_empty():
		lines.append("  (none)")
	return "\n".join(lines)
