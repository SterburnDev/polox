extends Node
## Phone Link on the PC: the HTTP engine (http_server.gd) plus pairing, the
## /api/ endpoints, the pages (the launcher at /, /hello) and how phones get in.
##
## Same Wi-Fi always works: every mode listens on every address of this PC
## (plus 127.0.0.1) and lets in only this PC, home networks (RFC 1918,
## link-local) and Tailscale (100.64/10). Tailscale only ever adds a way in:
##
##   lan              Same Wi-Fi only (plain HTTP on the home network).
##   tailscale_serve  Same Wi-Fi + Tailscale publishes Polox to your tailnet as
##                    https://<pc>.<tailnet>.ts.net:<serve port> (HTTPS, works
##                    away from home). If Serve can't start, Same Wi-Fi still runs.
##   tailscale_direct Same Wi-Fi + this PC's Tailscale address over HTTP.
##
## "auto" (the default) picks Serve when Tailscale can do it, else Same Wi-Fi.
## Public addresses are always refused. Off every time Polox starts; idle
## auto-off; optional "keep this PC awake while it's on". While it's on, a
## pairing PIN is always ready (pairing.gd).

signal state_changed
signal phone_reached(contact: Dictionary)   # a new phone address reached Polox this run
signal phone_paired(device_name: String)
signal report_received                      # a phone sent its Connection Test (or start-up) report

const HttpServer := preload("res://scripts/phone/http_server.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const NetRules := preload("res://scripts/phone/net_rules.gd")
const Tailscale := preload("res://scripts/phone/tailscale.gd")
const Pairing := preload("res://scripts/phone/pairing.gd")
const PhoneApi := preload("res://scripts/phone/phone_api.gd")
const LauncherPage := preload("res://scripts/phone/launcher_page.gd")
const HelloPage := preload("res://scripts/phone/hello_page.gd")
const WebBuild := preload("res://scripts/phone/web_build.gd")
const DiagRoutes := preload("res://scripts/net/diag_routes.gd")
const BundledEngine := preload("res://scripts/phone/bundled_engine.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")
const Announcer := preload("res://scripts/phone/announcer.gd")
const AppPage := preload("res://scripts/phone/app_page.gd")
const AndroidApp := preload("res://scripts/phone/android_app.gd")
const ExportInbox := preload("res://scripts/phone/export_inbox.gd")

## A fixed, browser-safe port (Chrome refuses some ports with ERR_UNSAFE_PORT,
## so never a random one), remembered; if it's taken, the next one on this list.
const DEFAULT_PORT := 8765
const DEFAULT_SERVE_PORT := 8765
const SAFE_PORTS: Array = [8765, 8766, 8767, 8080, 8888]
## Ports Chrome/Firefox refuse to open (net::ERR_UNSAFE_PORT); Polox's list avoids every one.
const UNSAFE_PORTS: Array = [1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77, 79, 87, 95, 101, 102, 103, 104, 109, 110, 111, 113, 115, 117, 119, 123, 135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514, 515, 526, 530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993, 995, 1719, 1720, 1723, 2049, 3659, 4045, 4190, 5060, 5061, 6000, 6566, 6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080]
const MODES: PackedStringArray = ["lan", "tailscale_serve", "tailscale_direct"]
const MODE_LABELS := {
	"lan": "Same Wi-Fi",
	"tailscale_serve": "Same Wi-Fi + Tailscale HTTPS",
	"tailscale_direct": "Same Wi-Fi + Tailscale (HTTP)",
}

var root := ""                  # save root
var web_dir := ""               # the Web build
var port := DEFAULT_PORT
var auto_off_hours := 6.0       # 0 = never
var last_active := 0.0          # unix time of the last paired request
var pairing: Pairing
var api: PhoneApi
var http: Node                  # http_server.gd
var reports: ReportSink         # phone reports (/api/report), saved under phone_reports/

var mode := "lan"
var chosen_mode := "auto"       # what the settings ask for ("auto" or a mode)
var tailscale_only := false     # refuse home-network phones (Advanced; off: Same Wi-Fi works)
var serve_port := DEFAULT_SERVE_PORT
var require_login := true       # tailscale_serve: only your own Tailscale login
var keep_awake := false
var server_extras := false      # gzip, ETag/304, Range: off until the phone's Connection Test passes (Advanced)
var engine_choice := "builtin"  # "builtin" or "bundled" (Plan B: Caddy in front, Advanced)
var engine_in_use := "built-in"
var engine_error := ""          # why the bundled engine isn't in use (it fell back to built-in)
var engine: Node                # bundled_engine.gd
var announcer: Node             # announcer.gd: "Polox is here" for the Android app, while it's on
var apk_file := ""              # the Android app Phone Link serves at /app ("" = build/android/polox.apk)
var announce_port := Announcer.PORT   # tests announce to their own port
var ts: Tailscale
var ts_status: Dictionary = {}  # last `tailscale status` summary
var serve_result: Dictionary = {}   # {ok, error, consent_url, funnel}
var last_error := ""
var last_contact: Dictionary = {}   # the last request from a phone: {t, ip, via, path, host}
var phone_session: Dictionary = {}  # the world the phone last opened: {device, slot, name, t}
var last_pair_phrase := ""          # pair_v:1 words for the person to compare on both screens
var last_pair_device := ""
var last_pair_legacy := false       # the last pairing was an older phone's (no check words)
var started_at := 0.0

var _page_info: Dictionary = {}
var _info_mutex := Mutex.new()
var _seen_requests := 0
var _routes_text := ""
var _info_timer := 0.0
var _pin_timer := 0.0
var _own: Dictionary = {}       # this PC's own addresses
var _contact_ips: Dictionary = {}   # phone addresses seen this run
var _apk_cache: Dictionary = {}     # {key, bytes}: the APK in memory while phones download it
var _apk_mutex := Mutex.new()


var running: bool:
	get:
		return http != null and http.running


func setup(save_root: String, game_files: String = "") -> void:
	root = save_root
	web_dir = game_files if game_files != "" else default_web_dir()
	pairing = Pairing.new(root)
	reports = ReportSink.new(root)
	api = PhoneApi.new(self)
	if http == null:
		http = HttpServer.new()
		http.name = "Http"
		add_child(http)
		http.gave_up.connect(_on_engine_gave_up)
	if ts == null:
		ts = Tailscale.new()
	if engine == null:
		engine = BundledEngine.new()
		engine.name = "Engine"
		add_child(engine)
	if announcer == null:
		announcer = Announcer.new()
		announcer.name = "Announcer"
		add_child(announcer)


static func default_web_dir() -> String:
	return WebBuild.default_dir()


func has_web_build() -> bool:
	return FileAccess.file_exists(web_dir.path_join("index.html"))


## The mode "auto" means here: Serve when Tailscale can do HTTPS, Tailscale
## direct when Tailscale runs without HTTPS certificates, else Same Wi-Fi.
## Every one of them also serves the home network.
static func auto_mode(s: Dictionary) -> String:
	if not bool(s.get("installed", false)) or not bool(s.get("running", false)):
		return "lan"
	return "tailscale_serve" if serve_blocker(s) == "" else "tailscale_direct"


## Starts Phone Link in the current mode. `bind_address` forces an interface
## (tests). Returns "" or a plain-language error (also kept in last_error).
## A Tailscale problem never stops Same Wi-Fi: it's kept in serve_result.
func start(listen_port: int = DEFAULT_PORT, bind_address: String = "") -> String:
	if running:
		return ""
	port = listen_port
	last_error = ""
	serve_result = {}
	var plan := listen_plan(mode, tailscale_only)
	var bind := str(plan.bind)
	if mode in ["tailscale_serve", "tailscale_direct"]:
		ts_status = ts.status() if ts.installed() else Tailscale.parse_status("", false)
	if bind_address != "":
		bind = bind_address   # tests (and the smoke run) stay on 127.0.0.1
	http.static_dir = web_dir
	http.set_game_prefix(game_prefix_for(web_dir))
	http.allow_gzip = server_extras
	http.allow_etag = server_extras
	http.allow_range = server_extras
	http.source_scope = str(plan.scope)
	http.page_handler = _page
	http.api_handler = _api
	http.guard = _guard
	http.log_path = root.path_join("phone").path_join("phone_link.log")
	engine_in_use = "built-in"
	engine_error = ""
	http.proxy_secret = ""
	var err := ""
	if engine_choice == "bundled":
		err = _start_bundled(bind)
	else:
		err = http.start(port, bind)
	if err != "":
		last_error = err
		return err
	ExportInbox.sweep(root)
	if engine_in_use != "bundled" and http.port > 0:
		port = http.port
	_routes_text = NetRules.system_routes_text()
	_own = NetRules.own_addresses()
	if mode == "tailscale_serve":
		var why := serve_blocker(ts_status)
		if why != "":
			serve_result = {"ok": false, "error": why}
		else:   # (tests give `ts` a fake CLI; only the real app reaches the real Tailscale)
			serve_result = ts.serve_on(serve_port, port, str(ts_status.dns_name))
			if bool(serve_result.ok):
				_remember_serve(true)
	started_at = Time.get_unix_time_from_system()
	last_active = started_at
	last_contact = {}
	phone_session = {}
	last_pair_phrase = ""
	last_pair_device = ""
	last_pair_legacy = false
	_contact_ips = {}
	_seen_requests = 0
	pairing.new_code()   # a PIN is ready the moment it's on
	var cands := candidates()
	announcer.start(pc_name(), port, Announcer.targets_for(bind, cands), announce_port, Announcer.sources_for(bind, cands))
	refresh_page_info()
	_apply_keep_awake()
	pairing.audit("server_started port=%d mode=%s bind=%s" % [port, mode, bind])
	state_changed.emit()
	return ""


## Plan B: Polox's server on a free loopback port, Caddy on `port` in front of it.
## If Caddy can't start (not downloaded, crashed), the built-in engine takes the
## port instead and engine_error says why. Returns "" or why nothing listens.
func _start_bundled(bind: String) -> String:
	# Polox's own server takes the first of a hundred loopback ports it can really listen on. (Listening
	# is the test: a port that only looked free a moment ago can be taken by the time it's used.)
	var internal := 0
	var err := ""
	var start_internal := port + 1000 if port > 0 else 0
	if start_internal > 0 and start_internal < 65536:
		for p in range(start_internal, mini(65536, start_internal + 100)):
			err = http.start(p, "127.0.0.1")
			if err == "":
				internal = http.port
				break
			if not err.contains("in use"):
				break   # not a busy port: trying the next one won't help
	if internal == 0 and (err == "" or err.contains("in use")):
		err = http.start(0, "127.0.0.1")
		if err == "":
			internal = http.port
	if internal == 0 and (err == "" or err.contains("in use")):
		err = "No free local port for the bundled web server."
	if err == "":
		var public_port := port
		if public_port == 0:
			var probe := TCPServer.new()
			if probe.listen(0, bind) == OK:
				public_port = probe.get_local_port()
			probe.stop()
		if public_port > 0:
			var e: String = engine.start(public_port, internal, web_dir, game_prefix_for(web_dir), root)
			if e == "":
				port = public_port
				http.proxy_secret = engine.secret
				engine_in_use = "bundled"
				return ""
			engine_error = e
		else:
			engine_error = "No free port for the bundled web server."
		http.stop()
	else:
		engine_error = err
	return http.start(port, bind)   # the built-in engine after all


## Tries `preferred`, then the rest of SAFE_PORTS, until one is free. Returns ""
## or the last error. `port` is then the one in use.
func start_on_safe_port(preferred: int = DEFAULT_PORT, bind_address: String = "") -> String:
	var tried: Array = []
	var err := ""
	for p in [preferred] + SAFE_PORTS:
		if int(p) in tried or int(p) in UNSAFE_PORTS:
			continue
		tried.append(int(p))
		err = start(int(p), bind_address)
		if err == "":
			return ""
		if not err.contains("in use"):
			return err
	return err


## Where the game files live for a Web build: "/game/<build id>/" ("" if there's none).
static func game_prefix_for(dir: String) -> String:
	var wb := WebBuild.inspect(dir)
	if not bool(wb.present):
		return ""
	var id := str(wb.build_id)
	if id == "":   # a build from before build ids: its size and time stand in
		id = "dev%x" % hash("%d-%d" % [int(wb.files.get("index.wasm", 0)), FileAccess.get_modified_time(dir.path_join("index.wasm"))])
	return "/game/%s/" % id.substr(0, 16)


## Saved Phone Link settings from older versions, brought up to date once.
##   2 (Update 4): "Tailscale only" refused every phone on the home Wi-Fi and
##     one phone filled the pairing list: switch the first off, allow four.
##   3 (Update 5): the same again for files that Update 4 saved with a version
##     2 taken from the defaults while "Tailscale only" was still on (the
##     upgrade never ran: Phase 19 postmortem), unless you ticked it yourself.
##   4 (Update 5): the old port 8737 moves to the fixed safe port 8765.
## Returns true when it changed `cfg`.
static func upgrade_settings(cfg: Dictionary) -> bool:
	var v := int(cfg.get("version", 1))
	if v >= 4:
		return false
	if v < 3:
		if bool(cfg.get("tailscale_only", false)) and not bool(cfg.get("tailscale_only_chosen", false)):
			cfg["tailscale_only"] = false
			cfg["upgraded_note"] = "Tailscale only was switched off so Same Wi-Fi works (Advanced can switch it back on)."
		if v < 2:
			cfg["max_devices"] = maxi(4, int(cfg.get("max_devices", 1)))
			cfg.erase("sync_slots")   # worlds are now picked per world: Save menu > Available on phone
		elif int(cfg.get("max_devices", 4)) < 2:
			cfg["max_devices"] = 4
	if int(cfg.get("port", 8737)) == 8737:
		cfg["port"] = DEFAULT_PORT
		var note := str(cfg.get("upgraded_note", ""))
		cfg["upgraded_note"] = (note + " " if note != "" else "") + "Phone Link now uses port 8765 (was 8737): open the new address on the phone, and run allow_phone_link.bat once if Windows Firewall needs it."
	if int(cfg.get("serve_port", 8737)) == 8737:
		cfg.erase("serve_port")
	cfg["version"] = 4
	return true


## Where a mode listens and who it lets in: {bind, scope}. Every mode listens
## everywhere so Same Wi-Fi works; "Tailscale only" (Advanced) narrows it.
## IPv4 on every adapter (0.0.0.0): phones use IPv4 on home networks, and Tailscale
## Serve talks to 127.0.0.1, which 0.0.0.0 includes.
static func listen_plan(m: String, ts_only: bool = false) -> Dictionary:
	if m in ["tailscale_serve", "tailscale_direct"] and ts_only:
		return {"bind": "0.0.0.0", "scope": "tailscale"}
	return {"bind": "0.0.0.0", "scope": "home"}


## Why Tailscale Serve can't start right now ("" = it can).
static func serve_blocker(s: Dictionary) -> String:
	if not bool(s.get("installed", false)):
		return "Tailscale isn't installed on this PC (only needed away from home)."
	if not bool(s.get("running", false)):
		return "Tailscale isn't connected on this PC (%s). Open Tailscale and log in." % str(s.get("backend", "stopped"))
	if str(s.get("dns_name", "")) == "":
		return "Tailscale doesn't give this PC a name yet. Switch on MagicDNS in the Tailscale admin page (DNS tab)."
	if not bool(s.get("https", false)):
		return "Your tailnet needs HTTPS certificates switched on (Tailscale admin page > DNS > HTTPS Certificates)."
	return ""


func stop() -> void:
	if not running:
		return
	_switch_off()


## The built-in engine's socket thread kept stopping and it switched itself off (http_server.gd):
## the rest of Phone Link goes off with it and says why, instead of announcing a server that isn't there.
func _on_engine_gave_up() -> void:
	last_error = "Phone Link's web server kept stopping, so it was switched off. Switch Phone Link on again to retry."
	_switch_off()


func _switch_off() -> void:
	if mode == "tailscale_serve" and bool(serve_result.get("ok", false)):
		var off := ts.serve_off(serve_port, port, str(ts_status.get("dns_name", "")))
		if not bool(off.ok):
			push_warning("Phone Link: " + str(off.error))
		_remember_serve(false)
	if engine:
		engine.stop()
	announcer.stop()
	http.stop()
	serve_result = {}
	pairing.cancel_code()
	pairing.forget_wrap_key()
	pairing.audit("server_stopped")
	_apply_keep_awake()
	state_changed.emit()


## The settings remember Polox's own Serve mapping, so only that one is ever removed.
func _remember_serve(on: bool) -> void:
	var cfg: Dictionary = GameState.settings.get("phone_link", {})
	if on:
		cfg["serve_owned"] = {"https_port": serve_port, "local_port": port}
	else:
		cfg.erase("serve_owned")
	GameState.settings["phone_link"] = cfg
	GameState.save_settings()


## A mapping left behind by a crash (or a closed window) is removed next start-up.
func cleanup_stale_serve() -> void:
	var cfg: Dictionary = GameState.settings.get("phone_link", {})
	var owned: Variant = cfg.get("serve_owned")
	if not owned is Dictionary or running or not ts.installed():
		return
	# Another Polox window (or host.bat, or the Doctor's subject) may still be serving it.
	var probe := TCPServer.new()
	if probe.listen(int(owned.get("local_port", port)), "127.0.0.1") != OK:
		return   # something is listening there: not left behind
	probe.stop()
	var s := ts.status()
	var off := ts.serve_off(int(owned.get("https_port", serve_port)), int(owned.get("local_port", port)), str(s.dns_name))
	if bool(off.ok):
		_remember_serve(false)


func _apply_keep_awake() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.screen_set_keep_on(keep_awake and running)


func _exit_tree() -> void:
	stop()


func mark_active() -> void:
	last_active = Time.get_unix_time_from_system()


## A phone paired (called by the API): the PIN has already changed. `phrase`: the pair_v:1 check
## words ("" when an older phone paired the old way, its key unencrypted on the network).
func paired_device(device_name: String, _ip: String, phrase: String = "") -> void:
	last_pair_phrase = phrase
	last_pair_device = device_name if device_name != "" else "My phone"
	last_pair_legacy = phrase == ""
	phone_paired.emit(last_pair_device)
	state_changed.emit()


## A phone's report arrived (main thread, from the API).
func report_arrived() -> void:
	report_received.emit()
	state_changed.emit()


## A wrong PIN, a pause or an unpair: the screens showing pairing redraw.
func pairing_changed() -> void:
	state_changed.emit()


## Idle auto-off, the PIN kept fresh, and "a phone reached Polox" (main thread).
func _process(delta: float) -> void:
	if not running:
		return
	if auto_off_hours > 0.0 and Time.get_unix_time_from_system() - last_active > auto_off_hours * 3600.0:
		stop()
		GameState.notify("Phone Link switched itself off after %d idle hours." % int(auto_off_hours))
		return
	_pin_timer += delta
	if _pin_timer > 0.5:
		_pin_timer = 0.0
		if pairing.ensure_code():
			state_changed.emit()   # the screens show the new PIN
	_info_timer += delta
	if _info_timer > 5.0:
		_info_timer = 0.0
		refresh_page_info()   # a rebuilt phone version shows up without a restart
	var served: int = http.served_count()
	if served != _seen_requests:
		var fresh: Array = http.recent(mini(50, served - _seen_requests))
		_seen_requests = served
		for e in fresh:
			if is_phone_request(e, _own):
				last_contact = e
				var who := str(e.get("via", "")) if str(e.get("via", "")) != "" else str(e.ip)
				if not _contact_ips.has(who):
					_contact_ips[who] = true
					phone_reached.emit(e)
					state_changed.emit()


## A request from a phone: from somewhere other than this PC (directly or
## brought in by Tailscale Serve), and let in (a refused stranger isn't
## "your phone"). `own` = this PC's addresses (its self-tests don't count).
static func is_phone_request(e: Dictionary, own: Dictionary = {}) -> bool:
	if int(e.get("status", 0)) == 403:
		return false
	var via := str(e.get("via", ""))
	if via != "":
		return not own.has(via.get_slice(" ", 1))
	var ip := str(e.get("ip", ""))
	return NetRules.kind(ip) != "loopback" and not own.has(ip)


# --- Addresses ---------------------------------------------------------------------------------

## Every address on this PC a phone might use, best first (see NetRules.rank_addresses).
func candidates() -> Array:
	if _routes_text == "":
		_routes_text = NetRules.system_routes_text()
	return NetRules.rank_addresses(IP.get_local_interfaces(), _routes_text)


## Old name, still used by host mode and tests: the ranked IPv4 addresses.
static func addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for c in NetRules.rank_addresses(IP.get_local_interfaces(), NetRules.system_routes_text()):
		out.append(str(c.ip))
	return out


## The home-network address for a phone on the same Wi-Fi ("" if none):
## the adapter with the default route first, never a virtual adapter.
static func pick_lan(cands: Array) -> String:
	for c in cands:
		if str(c.kind) == "private" and not bool(c.get("virtual", false)) and int(c.rank) <= 2:
			return str(c.ip)
	return ""


func lan_url() -> String:
	var ip := pick_lan(candidates())
	return "http://%s:%d" % [ip, port] if ip != "" else ""


## The Tailscale address in this mode ("" in Same Wi-Fi mode or when Tailscale can't).
func ts_url() -> String:
	match mode:
		"tailscale_serve":
			var name := str(ts_status.get("dns_name", ""))
			if name == "" or not bool(serve_result.get("ok", false)):
				return ""
			return "https://%s" % name if serve_port == 443 else "https://%s:%d" % [name, serve_port]
		"tailscale_direct":
			var host := str(ts_status.get("dns_name", ""))
			if host == "":
				host = str(ts_status.get("ipv4", ""))
			if host == "":
				for c in candidates():
					if str(c.kind) == "tailscale":
						host = str(c.ip)
						break
			return "http://%s:%d" % [host, port] if host != "" else ""
	return ""


## The address shown big on the PC: Same Wi-Fi first (it needs nothing on the
## phone), else the Tailscale one ("Tailscale only" or no home network).
func canonical_url() -> String:
	var lan := lan_url()
	if lan != "" and not (tailscale_only and mode != "lan"):
		return lan
	var t := ts_url()
	return t if t != "" else lan


## Every address that works in this mode, the main one first.
func urls() -> PackedStringArray:
	var out := PackedStringArray()
	var canon := canonical_url()
	if canon != "":
		out.append(canon)
	var t := ts_url()
	if t != "" and not t in out:
		out.append(t)
	for c in candidates():
		var k := str(c.kind)
		if bool(c.virtual) or (tailscale_only and mode != "lan" and k != "tailscale"):
			continue
		var u := "http://%s:%d" % [c.ip, port]
		if not u in out:
			out.append(u)
	return out


## Where it listens, for the screen: "every address of this PC (127.0.0.1, 192.168.1.42, ...) on port 8737".
func bind_text() -> String:
	if not running:
		return "not listening"
	var b := str(http.bind_address)
	if b != "*" and b != "0.0.0.0" and b != "":
		return "%s port %d only" % [b, port]
	var ips := PackedStringArray(["127.0.0.1"])
	for c in candidates():
		if not bool(c.virtual):
			ips.append(str(c.ip))
	return "every address of this PC (%s) on port %d" % [", ".join(ips), port]


func mode_text() -> String:
	var label := str(MODE_LABELS.get(mode, mode))
	if engine_in_use == "bundled":
		label += " (bundled web server)"
	elif engine_choice == "bundled" and engine_error != "":
		label += " (built-in engine: %s)" % engine_error
	if chosen_mode == "auto":
		label += " (Auto)"
	if mode == "tailscale_serve" and running and not bool(serve_result.get("ok", false)):
		label += ": Tailscale part off (%s)" % str(serve_result.get("error", "?"))
	return label


static func pc_name() -> String:
	var n := OS.get_environment("COMPUTERNAME")
	if n == "":
		n = OS.get_environment("HOSTNAME")
	return n if n != "" else "your PC"


# --- Pages, guard and API (pages and guard run on the server thread) -------------------------------

func refresh_page_info() -> void:
	var wb := WebBuild.inspect(web_dir)
	var info := {
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"build_id": WebBuild.current_build_id(),
		"mode": mode, "mode_label": str(MODE_LABELS.get(mode, mode)),
		"canonical": canonical_url(), "lan_url": lan_url(), "ts_url": ts_url(), "urls": Array(urls()),
		"pc_name": pc_name(),
		"has_game": bool(wb.present), "game_current": bool(wb.current) or str(wb.build_id) == "",
		"game_mb": float(wb.mb),
		"always_ask": pairing.always_ask,
		"pair_v": Pairing.PAIR_WRAP_VERSION if pairing.wrap_supported() else 0,
		"login": str(ts_status.get("login", "")) if require_login and mode == "tailscale_serve" else "",
		"game_path": game_prefix_for(web_dir),
		"apk": AndroidApp.apk_info(apk_file),
	}
	if http and http.running:
		http.set_game_prefix(str(info.game_path))   # a phone version rebuilt while Phone Link is on
	_info_mutex.lock()
	_page_info = info
	_info_mutex.unlock()


## What the pages know (thread-safe copy).
func page_info() -> Dictionary:
	_info_mutex.lock()
	var i := _page_info.duplicate()
	_info_mutex.unlock()
	return i


## Is this the PC's own browser opening localhost (not a phone, not Tailscale Serve)?
static func is_pc_itself(req: Dictionary) -> bool:
	var h: Dictionary = req.get("headers", {})
	if h.has("x-forwarded-for") or h.has("tailscale-user-login"):
		return false
	var host := str(h.get("host", "")).to_lower()
	var name := host.get_slice(":", 0) if not host.begins_with("[") else host.get_slice("]", 0) + "]"
	return NetRules.kind(str(req.get("ip", ""))) == "loopback" and name in ["localhost", "127.0.0.1", "[::1]"]


## /hello.json in full: a request from this PC itself (not through Tailscale Serve or the bundled
## server, which both arrive from 127.0.0.1 too), or one that carries a paired phone's key.
func hello_in_full(req: Dictionary) -> bool:
	var headers: Dictionary = req.get("headers", {})
	var forwarded := headers.has("x-forwarded-for") or headers.has("tailscale-user-login") or bool(req.get("proxied", false))
	if NetRules.kind(str(req.get("ip", ""))) == "loopback" and not forwarded:
		return true
	return pairing != null and pairing.token_is_valid(HttpUtil.bearer(headers))


func _page(req: Dictionary) -> Variant:
	var path := str(req.path)
	var info := page_info()
	var diag := DiagRoutes.handle(req, {"server": "host", "server_name": "Polox Phone Link", "engine": BundledEngine.label() if bool(req.get("proxied", false)) else "built-in", "pc": str(info.get("pc_name", pc_name())), "build_id": str(info.get("build_id", "")), "port": port})
	if not diag.is_empty():
		return diag
	match path:
		"/hello":
			return HttpUtil.response(200, HelloPage.html(info).to_utf8_buffer(), "text/html; charset=utf-8")
		"/hello.json":
			# The addresses (and the rest) only for this PC itself or a paired phone; anyone else on the
			# network learns that Polox is here and its name, which finding the PC needs anyway.
			return HttpUtil.response(200, HelloPage.json(info, hello_in_full(req)).to_utf8_buffer(), "application/json")
		"/", "/pair", "/pair.html", "/worlds":
			return HttpUtil.response(200, LauncherPage.html(info, is_pc_itself(req)).to_utf8_buffer(), "text/html; charset=utf-8")
		"/app", "/app/":
			return HttpUtil.response(200, AppPage.html(info, info.get("apk", {})).to_utf8_buffer(), "text/html; charset=utf-8")
		"/app/version.json":
			return HttpUtil.response(200, AppPage.version_json(info.get("apk", {})).to_utf8_buffer(), "application/json")
		"/app/polox.apk":
			return _apk_download(info.get("apk", {}))
	return PackedByteArray()


## The APK as a download (streamed after the header; kept in memory while it's unchanged).
func _apk_download(apk: Dictionary) -> Variant:
	if not bool(apk.get("present", false)):
		return HttpUtil.response(404, "Polox for Android isn't built on this PC yet (Settings > Phone Link > Polox for Android).".to_utf8_buffer(), "text/plain; charset=utf-8")
	var path := apk_file if apk_file != "" else AndroidApp.apk_path()
	var key := "%s|%d|%d" % [path, int(apk.size), FileAccess.get_modified_time(path)]
	_apk_mutex.lock()
	if str(_apk_cache.get("key", "")) != key:
		_apk_cache = {"key": key, "bytes": FileAccess.get_file_as_bytes(path)}
	var bytes: PackedByteArray = _apk_cache.bytes
	_apk_mutex.unlock()
	var hdr := HttpUtil.response(200, PackedByteArray(), "application/vnd.android.package-archive", {
		"Content-Length": str(bytes.size()), "Content-Disposition": "attachment; filename=\"polox.apk\"", "X-Polox-Sha256": str(apk.get("sha256", ""))})
	return {"bytes": hdr, "status": 200, "blob": bytes}


## Tailscale Serve brings phones in from 127.0.0.1 with the phone's Tailscale
## login in a header; only trusted because the connection is local. Your own
## login gets in; anyone else on the tailnet doesn't.
func _guard(req: Dictionary, ip: String) -> String:
	var login := str(page_info().get("login", ""))
	var h: Dictionary = req.headers
	if bool(req.get("proxied", false)) and not h.has("tailscale-user-login"):
		return ""   # a phone on the home network through the bundled web server (it refused strangers)
	if login == "" or (NetRules.kind(ip) != "loopback" and not bool(req.get("proxied", false))):
		return ""
	if not h.has("x-forwarded-for") and not h.has("tailscale-user-login"):
		return ""   # this PC itself, not a phone through Tailscale
	if str(h.get("tailscale-user-login", "")).to_lower() == login.to_lower():
		return ""
	return "This Tailscale account isn't allowed to use this Polox."


func _api(req: Dictionary, ip: String) -> PackedByteArray:
	var h: Dictionary = req.headers
	var who := ip
	if NetRules.kind(ip) == "loopback" and h.has("x-forwarded-for"):
		who = str(h["x-forwarded-for"]).get_slice(",", 0).strip_edges()
	return await api.handle(req, who)
