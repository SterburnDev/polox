extends ScrollContainer
## What Polox Ping shows (ping.bat's window, and Settings > Phone Link >
## Network test): every address worth trying on the phone, best first and big,
## with a QR code; which ports listen; every device that contacted it (or "no
## device has contacted Polox Ping yet"); phone reports; and what the PC facts
## (rung R0) say is in the way. Copy puts all of it on the clipboard (no
## secrets: addresses, rule names, settings).

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const QrCode := preload("res://scripts/phone/qr_code.gd")
const NetRules := preload("res://scripts/phone/net_rules.gd")
const PingServer := preload("res://scripts/net/ping_server.gd")
const NetFacts := preload("res://scripts/net/net_facts.gd")
const BackgroundJob := preload("res://scripts/core/background_job.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")
const FixActions := preload("res://scripts/net/fix_actions.gd")

const ICONS := {"ok": "✓", "warn": "⚠", "fail": "✗", "skip": "–"}

var server: Node                 # ping_server.gd
var big_size := 34
var _best: Label
var _qr: TextureRect
var _others: Label
var _ports: Label
var _contacts: Label
var _verdict: Label
var _facts_box: VBoxContainer
var _facts: Dictionary = {}
var _findings: Array = []
var _facts_job: Dictionary = {}   # background_job.gd box
var _t := 0.0
var _seen := -1
var _urls: Array = []            # [[label, url]]


func setup(ping: Node) -> void:
	server = ping
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(v)
	v.add_child(UiKit.para("Polox Ping is a tiny test server: no game, no pairing, no files. It proves whether your phone can reach this PC at all.", 16, ThemeBuilder.MUTED))
	v.add_child(UiKit.label("On your phone (same Wi-Fi, mobile data off), open:", 18, ThemeBuilder.CREAM))
	_best = UiKit.label("", big_size, ThemeBuilder.YELLOW)
	_best.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(_best)
	_qr = TextureRect.new()
	_qr.custom_minimum_size = Vector2(180, 180)
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.add_child(_qr)
	v.add_child(UiKit.label("If that doesn't open, also try:", 18, ThemeBuilder.CREAM))
	_others = UiKit.para("", 20, ThemeBuilder.CREAM)
	v.add_child(_others)
	_ports = UiKit.para("", 16, ThemeBuilder.MUTED)
	v.add_child(_ports)
	v.add_child(UiKit.label("What reached this PC", 20, ThemeBuilder.YELLOW))
	_verdict = UiKit.para("", 18, ThemeBuilder.CREAM)
	v.add_child(_verdict)
	_contacts = UiKit.para("", 16, ThemeBuilder.CREAM)
	v.add_child(_contacts)
	var row := UiKit.flow_row(8)
	row.add_child(UiKit.button("Copy everything", func():
		DisplayServer.clipboard_set(report_text())
		GameState.notify("Copied: paste it where you ask for help (no keys, PINs or chats in it)."), 210))
	row.add_child(UiKit.button("Check this PC again", refresh_facts, 220))
	v.add_child(row)
	v.add_child(UiKit.label("This PC (firewall, network, sleep)", 20, ThemeBuilder.YELLOW))
	_facts_box = UiKit.vbox(6)
	v.add_child(_facts_box)
	_build_urls()
	refresh()
	refresh_facts()
	print_banner()




## Every address worth trying, best first: [[label, url]].
func _build_urls() -> void:
	_urls.clear()
	var ports: Array = server.ports_open
	if ports.is_empty():
		return
	var cands := NetRules.rank_addresses(IP.get_local_interfaces(), NetRules.system_routes_text())
	var best := ""
	for c in cands:
		if str(c.kind) == "private" and not bool(c.get("virtual", false)) and int(c.rank) <= 2:
			best = str(c.ip)
			break
	if best != "":
		for p in ports:
			_urls.append(["home network, port %d" % int(p), "http://%s:%d" % [best, int(p)]])
	_urls.append(["by name: works on many phones", "http://%s.local:%d" % [PingServer.pc_name(), int(ports[0])]])
	for c in cands:
		if str(c.ip) == best or bool(c.get("virtual", false)):
			continue
		var label := "Tailscale: only with Tailscale on the phone" if str(c.kind) == "tailscale" else "other adapter: %s" % str(c.label)
		_urls.append([label, "http://%s:%d" % [c.ip, int(ports[0])]])


func best_url() -> String:
	return str(_urls[0][1]) if not _urls.is_empty() else ""


func refresh() -> void:
	if server == null or _best == null:
		return
	var best := best_url()
	_best.text = best if best != "" else "(this PC has no network address right now)"
	if best != "" and _qr.texture == null:
		var q: RefCounted = QrCode.encode(best)
		_qr.texture = ImageTexture.create_from_image(q.to_image(5)) if q else null
	var lines := PackedStringArray()
	for u in _urls.slice(1):
		lines.append("%s   (%s)" % [str(u[1]), str(u[0])])
	_others.text = "\n".join(lines)
	var where := "every address (0.0.0.0)" if str(server.bind_address) == "0.0.0.0" else "%s only" % str(server.bind_address)
	var ptxt := "Listening on %s, ports %s." % [where, ", ".join(PackedStringArray(server.ports_open.map(func(p): return str(p))))]
	for p in server.ports_failed:
		ptxt += "  Port %d: %s." % [int(p), str(server.ports_failed[p])]
	_ports.text = ptxt
	var phones: Array = server.phone_contacts(12)
	var reports: Array = server.sink.recent(3) if server.sink else []
	if phones.is_empty():
		_verdict.text = "No device has contacted Polox Ping yet.\nIf the phone shows an error (or spins), nothing got through: the checks under \"This PC\" say what's in the way (firewall, network type, VPN), and if they're all fine, it's the network or router (guest Wi-Fi, \"client isolation\", or the phone isn't on the same Wi-Fi)."
	else:
		var real := phones.filter(func(c): return str(c.outcome) == "request")
		if real.is_empty():
			_verdict.text = "Something from your network reached this PC, but no full request came through (see below). %s" % ("Type the address with http:// in front." if phones.any(func(c): return str(c.outcome) == "https") else "The browser may have given up: try again, or another browser.")
		else:
			_verdict.text = "✓ Your phone reached this PC (%s). If Polox's Phone Link still doesn't open on the phone, the problem is inside Polox: run the Connection Test (the button on the phone's page) and send the report." % str(real[-1].ip)
	var cl := PackedStringArray()
	for c in phones.slice(-8):
		cl.append("%s  %s (port %d): %s" % [Time.get_datetime_string_from_unix_time(int(c.t)).substr(11), str(c.ip), int(c.port), PingServer.outcome_text(c)])
	for r in reports:
		cl.append("Report: " + ReportSink.summary(r))
	_contacts.text = "\n".join(cl)


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5 or server == null:
		return
	_t = 0.0
	var n: int = server.contact_total() + (server.sink.count() if server.sink else 0)
	if n != _seen:
		_seen = n
		refresh()
	if not _facts_job.is_empty() and bool(_facts_job.done):
		_facts = _facts_job.result if _facts_job.result is Dictionary else {}
		_facts_job = {}
		_findings = NetFacts.analyze(_facts, {"ports": server.ports_open, "programs": NetFacts.polox_programs(), "server": "ping", "keep_awake": true})
		_show_findings()


func refresh_facts() -> void:
	if not _facts_job.is_empty() and not bool(_facts_job.done):
		return
	for c in _facts_box.get_children():
		c.queue_free()
	_facts_box.add_child(UiKit.para("Checking this PC (a few seconds)...", 16, ThemeBuilder.MUTED))
	var ports: Array = server.ports_open.duplicate()
	var progs := NetFacts.polox_programs()
	_facts_job = BackgroundJob.run(func() -> Dictionary: return NetFacts.collect(ports, progs))


func _show_findings() -> void:
	for c in _facts_box.get_children():
		c.queue_free()
	for f in _findings:
		var color: Color = ThemeBuilder.MINT if str(f.status) == "ok" else (ThemeBuilder.YELLOW if str(f.status) == "warn" else (Color("#ff8a8a") if str(f.status) == "fail" else ThemeBuilder.MUTED))
		_facts_box.add_child(UiKit.para("%s %s: %s" % [ICONS.get(str(f.status), "?"), str(f.title), str(f.detail)], 16, color))
		if str(f.fix) != "" and str(f.status) in ["warn", "fail"]:
			_facts_box.add_child(UiKit.para("    → " + str(f.fix), 16, ThemeBuilder.CREAM))
		if f.has("action") and str(f.status) in ["warn", "fail"]:
			var act := str(f.action)
			var arg := str(f.get("arg", ""))
			_facts_box.add_child(UiKit.button(FixActions.label(act), func(): FixActions.run(act, arg, get_tree().current_scene), 260))
	for f in _findings:
		if str(f.status) in ["warn", "fail"]:
			print("[ping] %s %s: %s" % [ICONS.get(str(f.status), "?"), str(f.title), str(f.detail)])


## Everything on the screen as text (Copy, and what ping.bat prints).
func report_text() -> String:
	var lines := PackedStringArray(["Polox Ping report, %s" % Time.get_datetime_string_from_system(false, true)])
	lines.append("Ports: %s (failed: %s)" % [str(server.ports_open), str(server.ports_failed)])
	for u in _urls:
		lines.append("  %s  (%s)" % [str(u[1]), str(u[0])])
	var phones: Array = server.phone_contacts(40)
	lines.append("Contacts from other devices:" if not phones.is_empty() else "No device has contacted Polox Ping yet.")
	for c in phones:
		lines.append("  %s %s port %d: %s" % [Time.get_datetime_string_from_unix_time(int(c.t)), str(c.ip), int(c.port), PingServer.outcome_text(c)])
	for r in (server.sink.recent(5) if server.sink else []):
		lines.append(ReportSink.text(r))
	lines.append("This PC:")
	for f in _findings:
		lines.append("  %s %s: %s%s" % [ICONS.get(str(f.status), "?"), str(f.title), str(f.detail), ("  fix: " + str(f.fix)) if str(f.fix) != "" and str(f.status) in ["warn", "fail"] else ""])
	if not _facts.is_empty():
		lines.append(NetFacts.text(_facts))
	return "\n".join(lines)


## ping.bat's console: the addresses in big block letters (plain ASCII, any console).
func print_banner() -> void:
	print("[ping] ================= POLOX PING =================")
	print("[ping] On your phone (same Wi-Fi, mobile data off), open:")
	var best := best_url()
	if best != "":
		for l in big_text(best.trim_prefix("http://")):
			print("[ping]   " + l)
		print("[ping]   " + best)
	for u in _urls.slice(1):
		print("[ping]   also: %s  (%s)" % [str(u[1]), str(u[0])])
	print("[ping] Every contact is listed below as it happens. Close this window to stop.")


const GLYPHS := {
	"0": ["###", "# #", "# #", "# #", "###"], "1": [" # ", "## ", " # ", " # ", "###"], "2": ["###", "  #", "###", "#  ", "###"],
	"3": ["###", "  #", "###", "  #", "###"], "4": ["# #", "# #", "###", "  #", "  #"], "5": ["###", "#  ", "###", "  #", "###"],
	"6": ["###", "#  ", "###", "# #", "###"], "7": ["###", "  #", "  #", "  #", "  #"], "8": ["###", "# #", "###", "# #", "###"],
	"9": ["###", "# #", "###", "  #", "###"], ".": ["   ", "   ", "   ", "   ", " # "], ":": ["   ", " # ", "   ", " # ", "   "],
}


## Digits, dots and colons as 5-line block letters (other characters are skipped).
static func big_text(s: String) -> PackedStringArray:
	var rows := PackedStringArray(["", "", "", "", ""])
	for ch in s:
		if not GLYPHS.has(ch):
			continue
		for i in 5:
			rows[i] += str(GLYPHS[ch][i]) + " "
	return rows
