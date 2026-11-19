extends ScrollContainer
## Settings > Phone Link. Simple by default:
##   the big switch; once on, the address to open on the phone (big, QR, Copy,
##   Test), where Polox listens and how; the PIN (big, countdown, New PIN /
##   Unlock pairing); "Waiting for your phone..." -> "Phone reached Polox" ->
##   "Phone playing ..."; after a minute with no phone, a checklist and the
##   Doctor's findings; paired phones (Forget, Always ask for PIN); the phone
##   version of the game.
## Advanced (one click): the mode (Auto / Same Wi-Fi / + Tailscale HTTPS /
## + Tailscale HTTP), the firewall helper, Tailscale only, idle switch-off,
## keep the PC awake, ports, Tailscale login check, the request log, security
## events and the Doctor. Off every time Polox starts.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const BackgroundJob := preload("res://scripts/core/background_job.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const QrCode := preload("res://scripts/phone/qr_code.gd")
const WebBuild := preload("res://scripts/phone/web_build.gd")
const WebBuilder := preload("res://scripts/phone/web_builder.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const PhoneDoctor := preload("res://scripts/phone/phone_doctor.gd")
const Pairing := preload("res://scripts/phone/pairing.gd")
const Tailscale := preload("res://scripts/phone/tailscale.gd")
const Firewall := preload("res://scripts/phone/firewall.gd")
const DoctorPanel := preload("res://scripts/ui/phone_doctor_panel.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")
const NetRules := preload("res://scripts/phone/net_rules.gd")
const TailscaleSteps := preload("res://scripts/phone/tailscale_steps.gd")
const BundledEngine := preload("res://scripts/phone/bundled_engine.gd")
const AndroidApp := preload("res://scripts/phone/android_app.gd")
const AppLink := preload("res://scripts/phone/app_link.gd")

const NO_CONTACT_S := 60.0
const AUTO_OFF := [[0, "Never"], [1, "After 1 idle hour"], [2, "After 2 idle hours"], [6, "After 6 idle hours"], [12, "After 12 idle hours"]]
const MODE_CHOICES := [
	["auto", "Auto (recommended)", "Same Wi-Fi always; adds Tailscale HTTPS when this PC has Tailscale with HTTPS certificates."],
	["lan", "Same Wi-Fi only", "Phones on your home Wi-Fi open the PC's address. Nothing to install. Plain HTTP: home networks only."],
	["tailscale_serve", "Same Wi-Fi + Tailscale HTTPS", "Also a private https:// address that works away from home (Tailscale on the phone, same account)."],
	["tailscale_direct", "Same Wi-Fi + Tailscale (HTTP)", "Also this PC's Tailscale address over HTTP (encrypted by Tailscale)."],
]

var main: Node
var _v: VBoxContainer
var _builder: Node
var _build_label: Label
var _checks: Dictionary = {}          # live: {ts: {...}, fw: {...}}
var _checks_job: Dictionary = {}       # background_job.gd box (Tailscale + firewall)
var _pin_label: Label
var _pin_timer: Label
var _contact_label: Label
var _help_box: VBoxContainer
var _log_label: Label
var _qr: TextureRect
var _advanced := false
var _t := 0.0
var _doctor_job: Dictionary = {}
var _doctor_results: Array = []
var _tips := false                    # "My phone can't open it" is open
var _ts_open := false                 # the Tailscale three steps are open
var _doctor_ran_for := 0.0            # started_at of the run the Doctor checked
var _android: Node                    # android_app.gd: build the APK, install over USB
var _app_label: Label
var _app_steps := false               # the install steps are open
var _app_pair := false                # the app's pairing code is showing
var _app_qr: TextureRect
var _app_qr_pin := ""
## Runs the Doctor on a snapshot (tests swap in a stand-in: the real one asks Tailscale and the firewall).
var doctor_runner: Callable = func(snap: Dictionary) -> Array: return PhoneDoctor.run(snap)


func build(main_node: Node) -> void:
	main = main_node
	name = "Phone Link"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_v = UiKit.vbox(12)
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_v)
	_builder = WebBuilder.new()
	add_child(_builder)
	_builder.progress.connect(_on_build_progress)
	_builder.finished.connect(func(ok, msg):
		GameState.notify(msg)
		refresh())
	_android = AndroidApp.new()
	add_child(_android)
	_android.progress.connect(func(t):
		if _app_label and is_instance_valid(_app_label):
			_app_label.text = t)
	_android.finished.connect(func(job, ok, msg):
		if job == "devices" and ok:
			var e: String = _android.install(str(_android.devices.filter(func(d): return str(d.state) == "device")[0].serial))
			if e != "":
				GameState.notify(e)
			return
		if job == "install":
			_android.stop_adb()
		GameState.notify(("✓ " if ok else "⚠ ") + str(msg))
		refresh())
	if not main.phone_link.running:
		main.configure_phone_link(false)   # mode discovery belongs to the background check, not opening Settings
	main.phone_link.state_changed.connect(refresh)
	_start_checks()
	refresh()


func _ready() -> void:
	refresh()


func _on_build_progress(text: String) -> void:
	if _build_label and is_instance_valid(_build_label):
		_build_label.text = text


# --- Live checks (Tailscale + firewall take a moment: done on a thread) -------------------------------

func _start_checks() -> void:
	if not _checks_job.is_empty() and not bool(_checks_job.done):
		return
	var port := int(_cfg().get("port", PhoneServer.DEFAULT_PORT))
	var ts: Tailscale = main.phone_link.ts
	_checks_job = BackgroundJob.run(func() -> Dictionary:
		var s := ts.status() if ts.installed() else Tailscale.parse_status("", false)
		var fw := Firewall.check(port) if Firewall.available() else {"known": false}
		return {"ts": s, "fw": fw})


func _process(delta: float) -> void:
	if not _checks_job.is_empty() and bool(_checks_job.done):
		_checks = _checks_job.result if _checks_job.result is Dictionary else {}
		if _checks.get("ts") is Dictionary:
			main.phone_link.ts_status = _checks.ts
			if not main.phone_link.running and main.phone_link.chosen_mode == "auto":
				main.phone_link.mode = PhoneServer.auto_mode(_checks.ts)
		_checks_job = {}
		refresh()
	if not _doctor_job.is_empty() and bool(_doctor_job.done):
		_doctor_results = _doctor_job.result if _doctor_job.result is Array else []
		_doctor_job = {}
		refresh()
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		_update_pin()
		_update_live()


func _cfg() -> Dictionary:
	return GameState.settings.get("phone_link", {})


func _save(key: String, value: Variant) -> void:
	var cfg := _cfg()
	cfg[key] = value
	GameState.settings["phone_link"] = cfg
	GameState.save_settings()


func _card(border: Color = Color(ThemeBuilder.CREAM, 0.35)) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, border, 2, 12, 14))
	var col := UiKit.vbox(6)
	p.add_child(col)
	_v.add_child(p)
	return col


# --- Layout -----------------------------------------------------------------------------------------

func refresh() -> void:
	if not is_inside_tree() or _v == null:
		return
	for c in _v.get_children():
		c.queue_free()
	_pin_label = null
	_contact_label = null
	_help_box = null
	_log_label = null
	_qr = null
	_app_qr = null
	_app_label = null
	var srv: Node = main.phone_link
	_v.add_child(UiKit.para("Play your worlds on your own phone, in its web browser. Same Wi-Fi works with nothing to install; Tailscale (optional) adds a private address that works away from home. The PC keeps the master copy, and chats go through this PC so your API key never leaves it.", 18, ThemeBuilder.MUTED))
	_switch(srv)
	if srv.running:
		_address(srv)
		_status(srv)
		_phones(srv)
	_game_files()
	_android_card(srv)
	_tailscale_card(srv)
	_advanced_section(srv)
	UiKit.allow_swipe_over_buttons(self)


func _switch(srv: Node) -> void:
	var toggle := CheckButton.new()
	toggle.text = "Phone Link is ON" if srv.running else "Phone Link is off"
	toggle.add_theme_font_size_override("font_size", 26)
	toggle.button_pressed = srv.running
	toggle.tooltip_text = "On: phones you pair can play your worlds. Off: nothing on this PC can be reached."
	toggle.toggled.connect(func(on):
		if on:
			var err: String = main.start_phone_link()
			if err != "":
				GameState.notify(err)
		else:
			srv.stop()
		refresh())
	var top := UiKit.flow_row(10)
	top.add_child(toggle)
	var ping := UiKit.button("Network test (Polox Ping)", func():
		main.open_panel(load("res://scripts/ui/ping_panel.gd").new()), 290)
	ping.tooltip_text = "A tiny test server (no game, no pairing) that proves whether your phone can reach this PC at all, and shows what's in the way."
	top.add_child(ping)
	_v.add_child(top)
	var note := str(_cfg().get("upgraded_note", ""))
	if note != "":
		var row := UiKit.flow_row(8)
		row.add_child(UiKit.para("Note: " + note, 16, ThemeBuilder.YELLOW))
		row.add_child(UiKit.button("OK", func():
			var cfg := _cfg()
			cfg.erase("upgraded_note")
			_save("version", int(cfg.get("version", 2)))
			refresh(), 70))
		_v.add_child(row)
	if not srv.running:
		if str(srv.last_error) != "":
			_v.add_child(UiKit.para(str(srv.last_error), 18, ThemeBuilder.DANGER))
		else:
			_v.add_child(UiKit.para("Off: nothing on this PC can be reached from your phone.", 18, ThemeBuilder.MUTED))


func _address(srv: Node) -> void:
	var url: String = srv.canonical_url()
	var col := _card(ThemeBuilder.YELLOW)
	var row := UiKit.columns(16)
	var left := UiKit.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UiKit.label("On your phone (same Wi-Fi), open:", 18, ThemeBuilder.CREAM))
	var big := UiKit.label(url if url != "" else "(no network address found: is the PC on Wi-Fi or Ethernet?)", 32, ThemeBuilder.YELLOW)
	big.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	left.add_child(big)
	var btns := UiKit.flow_row(8)
	btns.add_child(UiKit.button("Copy", func():
		DisplayServer.clipboard_set(url)
		GameState.notify("Address copied."), 100))
	var test := UiKit.button("Test", func(): _test_address(url, big), 100)
	test.tooltip_text = "Asks Polox at this address from the PC itself (proves it listens there)"
	btns.add_child(test)
	left.add_child(btns)
	left.add_child(UiKit.para("Type it in the phone's browser (or scan the code), not localhost: on a phone that means the phone itself.", 16, ThemeBuilder.MUTED))
	_pin(srv, left)
	row.add_child(left)
	_qr = TextureRect.new()
	_qr.custom_minimum_size = Vector2(180, 180)
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_qr)
	col.add_child(row)
	if url != "":
		var q: RefCounted = QrCode.encode(url)
		if q:
			_qr.texture = ImageTexture.create_from_image(q.to_image(6))
	var t: String = srv.ts_url()
	if t != "" and t != url:
		var trow := UiKit.flow_row(8)
		trow.add_child(UiKit.para("Away from home (Tailscale on the phone, same account): %s" % t, 16, ThemeBuilder.CREAM))
		trow.add_child(UiKit.button("Copy", func():
			DisplayServer.clipboard_set(t)
			GameState.notify("Tailscale address copied."), 90))
		col.add_child(trow)
	col.add_child(UiKit.para("Mode: %s  •  listening on %s" % [srv.mode_text(), srv.bind_text()], 14, ThemeBuilder.MUTED))
	if bool(srv.tailscale_only) and srv.mode != "lan":
		col.add_child(UiKit.para("⚠ Tailscale only is on (Advanced): phones on your Wi-Fi are refused.", 16, ThemeBuilder.DANGER))


func _test_address(url: String, label: Label) -> void:
	label.text = url + "   (testing...)"
	var job := BackgroundJob.run(func() -> Dictionary: return PhoneDoctor.fetch(url + "/hello.json", "GET", 6.0))
	while not bool(job.done):
		if not is_inside_tree():
			return
		await get_tree().process_frame
	var r: Dictionary = job.result
	if not is_instance_valid(label):
		return
	label.text = url + ("   ✓ %d ms" % int(r.ms) if int(r.code) == 200 else "   ✗ %s" % (str(r.error) if str(r.error) != "" else "HTTP %d" % int(r.code)))


## The PIN, big, under the address (so both fit without scrolling).
func _pin(srv: Node, col: VBoxContainer) -> void:
	col.add_child(UiKit.label("Then type this PIN on the phone:", 18, ThemeBuilder.CREAM))
	var row := UiKit.flow_row(16)
	_pin_label = UiKit.label("", 56, ThemeBuilder.YELLOW)
	row.add_child(_pin_label)
	var side := UiKit.vbox(4)
	_pin_timer = UiKit.label("", 16, ThemeBuilder.MUTED)
	side.add_child(_pin_timer)
	if srv.pairing.paused:
		var unlock := UiKit.button("Unlock pairing", func():
			srv.pairing.unlock()
			srv.pairing.new_code()
			srv.state_changed.emit(), 220)
		unlock.tooltip_text = "Someone typed 20 wrong PINs within an hour, so pairing stopped. Unlock it when you're ready."
		side.add_child(unlock)
	else:
		var fresh := UiKit.button("New PIN", func():
			srv.pairing.new_code()
			srv.state_changed.emit(), 140)
		fresh.tooltip_text = "Makes a new PIN now (the old one stops working)"
		side.add_child(fresh)
	row.add_child(side)
	col.add_child(row)
	_update_pin()


func _status(srv: Node) -> void:
	_contact_label = UiKit.para("", 18, ThemeBuilder.CREAM)
	_v.add_child(_contact_label)
	var reports: Array = ReportSink.load_saved(SaveManager.root, 1)
	if not reports.is_empty():
		_v.add_child(UiKit.para("Last phone report: " + ReportSink.summary(reports[0]), 16, ThemeBuilder.MUTED))
	var tips_btn := UiKit.button(("▼ " if _tips else "▶ ") + "My phone can't open it", func():
		_tips = not _tips
		refresh(), 0)
	_v.add_child(tips_btn)
	if _tips:
		var col := _card(ThemeBuilder.YELLOW)
		col.add_child(UiKit.para("1. Run the Network test (button at the top): it shows whether anything from your phone reaches this PC, and what's in the way on the PC.", 16, ThemeBuilder.CREAM))
		col.add_child(UiKit.para("2. On the phone, open the address, then tap \"Having trouble? Connection test\" (or open <address>/test): each step turns green or red, and the report comes back here.", 16, ThemeBuilder.CREAM))
		for line in help_checklist(srv.canonical_url()):
			col.add_child(UiKit.para("•  " + line, 16, ThemeBuilder.CREAM))
		col.add_child(UiKit.para("Still stuck? Use Tailscale (Advanced), or connect this PC to the phone's own hotspot and open the address it shows then.", 16, ThemeBuilder.MUTED))
	_help_box = UiKit.vbox(4)
	_v.add_child(_help_box)
	_update_live()


func _phones(srv: Node) -> void:
	var devices: Array = srv.pairing.devices()
	var col := _card()
	col.add_child(UiKit.label("Paired phones (%d)" % devices.size(), 18, ThemeBuilder.CREAM))
	if devices.is_empty():
		col.add_child(UiKit.para("None yet: open the address on the phone and type the PIN.", 16, ThemeBuilder.MUTED))
	for d in devices:
		var r := UiKit.flow_row(8)
		r.add_child(UiKit.para("📱 %s  •  paired %s%s  •  last seen %s" % [d.get("name", "?"), str(d.get("paired", "")).replace("T", " ").substr(0, 16), (" at " + str(d.get("host", ""))) if str(d.get("host", "")) != "" else "", str(d.get("last_seen", "")).replace("T", " ").substr(0, 16)], 16, ThemeBuilder.CREAM))
		var id := str(d.get("id", ""))
		var forget := UiKit.button("Forget", func():
			srv.pairing.unpair(id)
			srv.state_changed.emit(), 110)
		forget.tooltip_text = "Its key stops working at once. Its saves on the phone stay; pairing again brings everything back."
		r.add_child(forget)
		col.add_child(r)
	var ask := CheckBox.new()
	ask.text = "Always ask for the PIN (the phone isn't remembered after a visit)"
	ask.button_pressed = bool(_cfg().get("always_ask", false))
	ask.toggled.connect(func(on):
		_save("always_ask", on)
		srv.pairing.always_ask = on
		srv.refresh_page_info())
	col.add_child(ask)
	col.add_child(UiKit.para("The phone sees every world except the ones you switch off in the Save menu (Available on phone).", 16, ThemeBuilder.MUTED))


func _game_files() -> void:
	var wb := WebBuild.inspect()
	var ok := bool(wb.present) and bool(wb.complete) and bool(wb.current)
	var col := _card(ThemeBuilder.MINT if ok else ThemeBuilder.YELLOW)
	col.add_child(UiKit.label("The phone version of the game", 18, ThemeBuilder.CREAM))
	if bool(wb.present) and bool(wb.complete):
		col.add_child(_check_row(bool(wb.current), "Built %s, %.1f MB%s" % [str(wb.built).replace("T", " "), float(wb.mb), "" if bool(wb.current) else ": older than this Polox, build it again"]))
	else:
		col.add_child(_check_row(false, "Not built yet. The phone can still pair and see your worlds; Play needs this."))
	var why := WebBuilder.blocker()
	if why != "":
		col.add_child(UiKit.para(why, 16, ThemeBuilder.DANGER))
	var row := UiKit.flow_row(10)
	var btn := UiKit.button("Build it again" if bool(wb.present) else "Build the phone version", func():
		var err: String = _builder.start()
		if err != "":
			GameState.notify(err)
		refresh(), 260)
	btn.disabled = why != "" or _builder.busy
	row.add_child(btn)
	_build_label = UiKit.label("Building..." if _builder.busy else "", 18, ThemeBuilder.MUTED)
	row.add_child(_build_label)
	col.add_child(row)


## Polox for Android: build the APK, install it (USB or download), pair it with its own QR code.
func _android_card(srv: Node) -> void:
	var apk := AndroidApp.apk_info()
	var ok := bool(apk.present) and bool(apk.current)
	var col := _card(ThemeBuilder.MINT if ok else Color(ThemeBuilder.CREAM, 0.35))
	col.add_child(UiKit.label("Polox for Android (the app)", 18, ThemeBuilder.CREAM))
	col.add_child(UiKit.para("Install it once: it finds this PC by itself on your Wi-Fi, plays offline with its own copy, and syncs whenever it can. iPhone: use the browser version above.", 16, ThemeBuilder.MUTED))
	if bool(apk.present):
		col.add_child(_check_row(bool(apk.current), "Built %s: version %s, %.1f MB%s" % [str(apk.built).replace("T", " "), str(apk.version), float(apk.size) / 1048576.0, "" if bool(apk.current) else ": older than this Polox, build it again (the app offers the update itself)"]))
	else:
		col.add_child(_check_row(false, "Not built yet."))
	var why := AndroidApp.build_blocker()
	if why != "":
		col.add_child(UiKit.para(why, 16, ThemeBuilder.DANGER))
	var row := UiKit.flow_row(10)
	var b := UiKit.button("Build it again" if bool(apk.present) else "Build the app", func():
		var err: String = _android.start_build()
		if err != "":
			GameState.notify(err)
		refresh(), 220)
	b.disabled = why != "" or _android.busy
	b.tooltip_text = "About a minute. The first build also makes this PC's signing key (tools\\android, never shared): keep it, updates need it."
	row.add_child(b)
	var inst := UiKit.button("Install on my phone (USB)", func():
		var err: String = _android.find_devices()
		if err != "":
			GameState.notify(err)
		_app_steps = true
		refresh(), 280)
	inst.disabled = not bool(apk.present) or _android.busy or _android.adb_path() == ""
	row.add_child(inst)
	row.add_child(UiKit.button(("▼ " if _app_steps else "▶ ") + "Steps", func():
		_app_steps = not _app_steps
		refresh(), 130))
	if srv.running:
		row.add_child(UiKit.button(("▼ " if _app_pair else "▶ ") + "Pair the app", func():
			_app_pair = not _app_pair
			refresh(), 190))
	col.add_child(row)
	_app_label = UiKit.label("Working..." if _android.busy else "", 18, ThemeBuilder.MUTED)
	col.add_child(_app_label)
	if _app_steps:
		col.add_child(UiKit.label("Over USB (Install on my phone):", 18, ThemeBuilder.YELLOW))
		var i := 1
		for s in AndroidApp.steps_usb():
			col.add_child(UiKit.para("%d. %s" % [i, s], 16, ThemeBuilder.CREAM))
			i += 1
		var addr: String = srv.lan_url() if srv.running and srv.lan_url() != "" else "this PC's address (switch Phone Link on)"
		col.add_child(UiKit.label("Or download it on the phone (Phone Link on):", 18, ThemeBuilder.YELLOW))
		i = 1
		for s in AndroidApp.steps_download(addr):
			col.add_child(UiKit.para("%d. %s" % [i, s], 16, ThemeBuilder.CREAM))
			i += 1
	if _app_pair and srv.running:
		col.add_child(UiKit.para("In the app: Connect to your PC > Scan the QR code. It holds this PC's address and today's PIN (the same PIN as above), so only show it to your own phone.", 16, ThemeBuilder.MUTED))
		_app_qr = TextureRect.new()
		_app_qr.custom_minimum_size = Vector2(220, 220)
		_app_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_app_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_app_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		col.add_child(_app_qr)
		_app_qr_pin = ""
		_update_app_qr()


## The app's pairing code follows the PIN (a new PIN, a new code).
func _update_app_qr() -> void:
	if _app_qr == null or not is_instance_valid(_app_qr):
		return
	var srv: Node = main.phone_link
	var pin: String = srv.pairing.code
	if pin == _app_qr_pin:
		return
	_app_qr_pin = pin
	var q := QrCode.encode(AppLink.qr_payload(PhoneServer.pc_name(), app_qr_urls(srv), pin))
	_app_qr.texture = ImageTexture.create_from_image(q.to_image(6)) if q else null


## The addresses the app's code carries: the home-network one first, then Tailscale.
static func app_qr_urls(srv: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for u in [srv.lan_url(), srv.ts_url()]:
		if str(u) != "" and not str(u) in out and AppLink.url_allowed(str(u)):
			out.append(str(u))
	return out


## Tailscale as the sure path: three steps, each saying plainly what's missing.
func _tailscale_card(srv: Node) -> void:
	var open: bool = _ts_open or srv.mode == "tailscale_serve"
	var ts_btn := UiKit.button(("▼ " if open else "▶ ") + "Tailscale: works away from home, and when your Wi-Fi keeps devices apart", func():
		_ts_open = not open
		refresh(), 0)
	ts_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # (a phone is narrower than this line)
	ts_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_v.add_child(ts_btn)
	if not open:
		return
	var col := _card(ThemeBuilder.MINT)
	var ts: Dictionary = _checks.get("ts", {})
	if ts.is_empty():
		col.add_child(UiKit.para("Checking Tailscale...", 16, ThemeBuilder.MUTED))
		return
	col.add_child(UiKit.para("The phone reaches Tailscale, and Tailscale talks to Polox on this PC itself: Windows Firewall and Wi-Fi \"client isolation\" don't matter. Private to your own devices; never the public internet.", 16, ThemeBuilder.MUTED))
	for st in TailscaleSteps.steps(ts, srv.serve_result, srv.mode if srv.running else "", srv.ts_url() if srv.running else ""):
		var icon: String = {"done": "✓", "todo": "○", "problem": "✗", "waiting": "…"}.get(str(st.state), "○")
		var color: Color = {"done": ThemeBuilder.MINT, "problem": ThemeBuilder.DANGER, "waiting": ThemeBuilder.MUTED}.get(str(st.state), ThemeBuilder.CREAM)
		col.add_child(UiKit.para("%s %d. %s" % [icon, int(st.n), str(st.title)], 18, color))   # (wraps on a phone)
		for line in st.lines:
			col.add_child(UiKit.para("     " + str(line), 24 if st.has("qr") else 15, ThemeBuilder.YELLOW if st.has("qr") else ThemeBuilder.CREAM))
		if st.has("qr"):
			var q: RefCounted = QrCode.encode(str(st.qr))
			if q:
				var tr := TextureRect.new()
				tr.texture = ImageTexture.create_from_image(q.to_image(4))
				tr.stretch_mode = TextureRect.STRETCH_KEEP
				tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				col.add_child(tr)
		var b: Dictionary = st.button
		if not b.is_empty():
			var kind := str(b.kind)
			var arg := str(b.arg)
			col.add_child(UiKit.button(str(b.label), func():
				if kind == "url":
					OS.shell_open(arg)
				elif kind == "enable":
					_set_mode("tailscale_serve")
					if not srv.running:
						var err: String = main.start_phone_link()
						if err != "":
							GameState.notify(err)
					_start_checks()
					refresh(), 300))


func _check_row(ok: Variant, text: String) -> Control:
	var icon := "…" if ok == null else ("✓" if ok else "✗")
	var color: Color = ThemeBuilder.MUTED if ok == null else (ThemeBuilder.MINT if ok else ThemeBuilder.DANGER)
	return UiKit.para("%s %s" % [icon, text], 18, color)


# --- Advanced ---------------------------------------------------------------------------------------

func _advanced_section(srv: Node) -> void:
	var more := UiKit.button(("▼ " if _advanced else "▶ ") + "Advanced: mode, Tailscale, firewall, log, Doctor", func():
		_advanced = not _advanced
		refresh(), 0)
	more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # (a phone: two lines, not a page that slides sideways)
	more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_v.add_child(more)
	if not _advanced:
		return
	var cfg := _cfg()
	var tools := UiKit.flow_row(10)
	tools.add_child(UiKit.button("Phone Link Doctor", func():
		var d: Control = DoctorPanel.new()
		d.main = main
		main.open_panel(d), 240))
	if Firewall.available():
		var fwb := UiKit.button("Firewall helper", func(): Firewall.open_helper(srv.port), 200)
		fwb.tooltip_text = "allow_phone_link.bat: explains what it changes, asks Windows for admin rights, can be undone"
		tools.add_child(fwb)
	_v.add_child(tools)
	_v.add_child(UiKit.label("How phones get in", 20, ThemeBuilder.YELLOW))
	var chosen := str(cfg.get("mode", "auto"))
	for m in MODE_CHOICES:
		var pick := CheckBox.new()
		pick.text = str(m[1])
		pick.button_pressed = chosen == m[0] or (m[0] == "auto" and not chosen in PhoneServer.MODES)
		pick.tooltip_text = str(m[2])
		pick.toggled.connect(func(on):
			if on:
				_set_mode(str(m[0])))
		_v.add_child(pick)
		_v.add_child(UiKit.para(str(m[2]), 16, ThemeBuilder.MUTED))
	for c in _tailscale_checks():
		_v.add_child(_check_row(c[0], str(c[1])))
	var only := CheckBox.new()
	only.text = "Tailscale only (refuse phones on the home Wi-Fi)"
	only.button_pressed = srv.tailscale_only
	only.tooltip_text = "Only for Tailscale modes. While it's on, Same Wi-Fi doesn't work."
	only.toggled.connect(func(on):
		_save("tailscale_only_chosen", on)   # your choice: upgrades never switch it back off
		_save("tailscale_only", on)
		_restart_if_running())
	_v.add_child(only)
	_v.add_child(UiKit.label("Server engine", 20, ThemeBuilder.YELLOW))
	var engines := [["builtin", "Built-in (default)"], ["bundled", BundledEngine.label()]]
	var eng := UiKit.option(engines.map(func(e): return e[1]), 1 if str(cfg.get("engine", "builtin")) == "bundled" else 0)
	eng.item_selected.connect(func(i):
		_save("engine", str(engines[i][0]))
		_restart_if_running()
		refresh())
	_v.add_child(UiKit.field_row("Answers phones with", eng, 230))
	if str(cfg.get("engine", "builtin")) == "bundled":
		if not BundledEngine.available():
			_v.add_child(UiKit.para("The bundled web server isn't downloaded yet (Caddy %s, about 17 MB, official release, checksum checked). Until then the built-in engine answers." % BundledEngine.VERSION, 16, ThemeBuilder.YELLOW))
			_v.add_child(UiKit.button("Get it (tools\\fetch_server.bat: shows what it downloads and asks first)", func():
				OS.create_process("cmd.exe", ["/c", "start", "Polox Plan B", ProjectSettings.globalize_path(BundledEngine.FETCH)]), 0))
		elif srv.running:
			_v.add_child(UiKit.para("In use: %s" % ("the bundled web server" if srv.engine_in_use == "bundled" else "the built-in engine (%s)" % str(srv.engine_error)), 16, ThemeBuilder.MINT if srv.engine_in_use == "bundled" else ThemeBuilder.YELLOW))
	_v.add_child(UiKit.para("Try the bundled web server only if the phone's Connection Test passes with Polox Ping but fails with Phone Link: then the problem is in Polox's own server, and one click swaps it.", 14, ThemeBuilder.MUTED))
	var extras := CheckBox.new()
	extras.text = "Faster game downloads (gzip, caching, resume): only once the phone's Connection Test passes"
	extras.button_pressed = bool(cfg.get("server_extras", false))
	extras.tooltip_text = "Off by default: plain, simple answers work with every phone. Switch it on later to download the game about 4x smaller."
	extras.toggled.connect(func(on):
		_save("server_extras", on)
		_restart_if_running())
	_v.add_child(extras)
	var hours := int(cfg.get("auto_off_hours", 6))
	var opt := UiKit.option(AUTO_OFF.map(func(a): return a[1]), maxi(0, AUTO_OFF.map(func(a): return a[0]).find(hours)))
	opt.item_selected.connect(func(i):
		_save("auto_off_hours", int(AUTO_OFF[i][0]))
		srv.auto_off_hours = float(AUTO_OFF[i][0]))
	_v.add_child(UiKit.field_row("Switch off", opt, 160))
	var awake := CheckBox.new()
	awake.text = "Keep this PC awake while Phone Link is on"
	awake.button_pressed = bool(cfg.get("keep_awake", false))
	awake.toggled.connect(func(on):
		_save("keep_awake", on)
		srv.keep_awake = on
		srv.call("_apply_keep_awake"))
	_v.add_child(awake)
	var login := CheckBox.new()
	login.text = "Tailscale HTTPS: only my own Tailscale account (%s)" % str(_checks.get("ts", {}).get("login", "?"))
	login.button_pressed = bool(cfg.get("require_login", true))
	login.toggled.connect(func(on):
		_save("require_login", on)
		_restart_if_running())
	_v.add_child(login)
	var port_edit := SpinBox.new()
	port_edit.min_value = 1025
	port_edit.max_value = 65000
	port_edit.value = int(cfg.get("port", PhoneServer.DEFAULT_PORT))
	port_edit.value_changed.connect(func(v):
		_save("port", int(v))
		_restart_if_running())
	_v.add_child(UiKit.field_row("Port on this PC", port_edit, 190))
	var serve_edit := SpinBox.new()
	serve_edit.min_value = 1
	serve_edit.max_value = 65000
	serve_edit.value = int(cfg.get("serve_port", PhoneServer.DEFAULT_SERVE_PORT))
	serve_edit.tooltip_text = "The https:// port Tailscale publishes. Pick one your other Serve mappings don't use."
	serve_edit.value_changed.connect(func(v):
		_save("serve_port", int(v))
		_restart_if_running())
	_v.add_child(UiKit.field_row("Tailscale HTTPS port", serve_edit, 190))
	_v.add_child(UiKit.label("Live request log", 20, ThemeBuilder.YELLOW))
	_log_label = UiKit.para("", 14, ThemeBuilder.MUTED)
	_v.add_child(_log_label)
	_v.add_child(UiKit.label("Recent security events", 20, ThemeBuilder.YELLOW))
	var events: PackedStringArray = srv.pairing.audit_tail(8)
	_v.add_child(UiKit.para("\n".join(events) if not events.is_empty() else "(none yet)", 14, ThemeBuilder.MUTED))
	_v.add_child(UiKit.para("Safety: never forward this port on your router, and never turn on Tailscale Funnel for it. Polox refuses public internet addresses and every phone needs the PIN.", 16, ThemeBuilder.MUTED))
	_update_live()


## [[ok (true/false/null = checking), text], ...] for Tailscale and the firewall.
func _tailscale_checks() -> Array:
	var out: Array = []
	var ts: Dictionary = _checks.get("ts", {})
	var fw: Dictionary = _checks.get("fw", {})
	if ts.is_empty():
		return [[null, "Checking Tailscale and the firewall..."]]
	if not bool(ts.get("installed", false)):
		out.append([null, "Tailscale isn't installed (optional: only needed away from home)."])
	else:
		out.append([bool(ts.running), "Tailscale connected as %s" % str(ts.login) if bool(ts.running) else "Tailscale isn't connected: %s" % str(ts.error)])
		if bool(ts.running):
			out.append([bool(ts.https), "HTTPS certificates on (Tailscale HTTPS works)" if bool(ts.https) else "HTTPS certificates are off (Tailscale admin page > DNS > HTTPS Certificates)"])
	if not bool(fw.get("known", false)):
		if Firewall.available():
			out.append([false, str(fw.get("error", "Firewall: unknown"))])
	elif int(fw.blocking) > 0:
		out.append([false, "Windows Firewall blocks Polox for Same Wi-Fi (%d block rule(s)): open the firewall helper" % int(fw.blocking)])
	else:
		out.append([bool(fw.allowed), "Firewall lets phones on your Wi-Fi in" if bool(fw.allowed) else "No firewall rule for Polox's port yet: open the firewall helper (or click Allow when Windows asks)"])
	return out


func _set_mode(m: String) -> void:
	_save("mode", m)
	_restart_if_running()
	refresh()


func _restart_if_running() -> void:
	if main.phone_link.running:
		main.phone_link.stop()
		var err: String = main.start_phone_link()
		if err != "":
			GameState.notify(err)
	else:
		main.configure_phone_link()


# --- Live bits ----------------------------------------------------------------------------------------

func _update_pin() -> void:
	_update_app_qr()
	if _pin_label == null or not is_instance_valid(_pin_label):
		return
	var p: Pairing = main.phone_link.pairing
	if p.paused:
		_pin_label.text = "Paused"
		_pin_timer.text = "Too many wrong PINs this hour."
		return
	var left := p.code_seconds_left()
	_pin_label.text = Pairing.grouped(p.code) if left > 0 else "..."
	_pin_timer.text = "new PIN in %d:%02d\n(and after each pairing)" % [left / 60, left % 60]


func _update_live() -> void:
	var srv: Node = main.phone_link
	if _contact_label and is_instance_valid(_contact_label):
		var lc: Dictionary = srv.last_contact
		var sess: Dictionary = srv.phone_session
		if not sess.is_empty():
			_contact_label.text = "📱 Phone playing %s (%s)" % [str(sess.get("name", "")), str(sess.get("device", ""))]
		elif lc.is_empty():
			var waited := Time.get_unix_time_from_system() - float(srv.started_at)
			var odd := odd_contacts(srv)
			if odd.is_empty():
				_contact_label.text = "○ Waiting for your phone... (%d s). No device has contacted Phone Link yet." % int(waited)
			else:
				_contact_label.text = "⚠ %s reached this PC but didn't finish: %s" % [str(odd[-1].ip), contact_text(odd[-1])]
			if waited > NO_CONTACT_S:
				_show_help(srv)
		else:
			_contact_label.text = "✓ Phone reached Polox: %s from %s%s" % [Time.get_datetime_string_from_unix_time(int(lc.t)).substr(11, 5), str(lc.ip), (" (" + str(lc.via) + ")") if str(lc.get("via", "")) != "" else ""]
	if _log_label and is_instance_valid(_log_label) and srv.http:
		var lines := PackedStringArray()
		for e in srv.http.recent(12):
			lines.append("%s  %s%s  %s %s  %d" % [Time.get_datetime_string_from_unix_time(int(e.t)).substr(11, 8), str(e.ip), (" " + str(e.via)) if str(e.get("via", "")) != "" else "", str(e.method), str(e.path).substr(0, 60), int(e.status)])
		_log_label.text = "\n".join(lines) if not lines.is_empty() else "(no requests yet)"


## A minute and no phone: what usually stops it, and what the Doctor found (run once per switch-on).
func _show_help(srv: Node) -> void:
	if _help_box == null or not is_instance_valid(_help_box):
		return
	if _doctor_ran_for != float(srv.started_at) and _doctor_job.is_empty():
		_doctor_ran_for = float(srv.started_at)
		var snap := PhoneDoctor.snapshot(srv)
		var runner := doctor_runner
		_doctor_job = BackgroundJob.run(func() -> Variant: return runner.call(snap))
	if _help_box.get_child_count() > 0:
		return
	_help_box.add_child(UiKit.label("No phone yet? Check these:", 18, ThemeBuilder.YELLOW))
	for line in help_checklist(srv.canonical_url()):
		_help_box.add_child(UiKit.para("•  " + line, 16, ThemeBuilder.CREAM))
	if not _doctor_job.is_empty():
		_help_box.add_child(UiKit.para("The Doctor is checking this PC...", 16, ThemeBuilder.MUTED))
	else:
		var bad := _doctor_results.filter(func(r): return str(r.status) in ["fail", "warn"] and str(r.id) != "contact" and str(r.id) != "awake" and str(r.id) != "pairing")
		_help_box.add_child(UiKit.para("The Doctor found nothing wrong on this PC, so look at the phone side above." if bad.is_empty() else "The Doctor found:", 16, ThemeBuilder.MUTED))
		for r in bad:
			_help_box.add_child(UiKit.para("%s %s: %s%s" % [PhoneDoctor.ICONS.get(r.status, "?"), r.title, r.detail, ("  → " + str(r.fix)) if str(r.fix) != "" else ""], 16, ThemeBuilder.DANGER if r.status == "fail" else ThemeBuilder.YELLOW))
	_help_box.add_child(UiKit.button("Open the Doctor", func():
		var d: Control = DoctorPanel.new()
		d.main = main
		main.open_panel(d), 200))


## Connections from other devices that never became a request (sent nothing,
## spoke HTTPS to this HTTP port, or sent garbage), oldest first.
static func odd_contacts(srv: Node) -> Array:
	if srv.http == null:
		return []
	var own := NetRules.own_addresses()
	return srv.http.contacts(100).filter(func(c): return str(c.outcome) != "request" and not own.has(str(c.ip)) and NetRules.kind(str(c.ip)) != "loopback")


static func contact_text(c: Dictionary) -> String:
	match str(c.get("outcome", "")):
		"nothing":
			return "it connected but sent no request (the browser gave up, or something on the way cut it). Try again, or run the Network test."
		"https":
			return "the browser tried https://. Type the address with http:// in front (or scan the QR code)."
		"bad":
			return "it sent something that isn't a web request."
	return str(c.get("outcome", ""))


## The usual reasons a phone on the same Wi-Fi doesn't get through.
static func help_checklist(url: String) -> PackedStringArray:
	return PackedStringArray([
		"Run the Network test (button at the top): it shows whether your phone can reach this PC at all, and what's in the way.",
		"The phone is on the same Wi-Fi as this PC: mobile data off while testing, not a guest network (guest Wi-Fi keeps devices apart), no VPN on the phone.",
		"The first three numbers of the phone's Wi-Fi address match this PC's (e.g. 192.168.1.x and 192.168.1.y). Different numbers mean a different network: guest Wi-Fi, an extender or a second router.",
		"You typed %s exactly, with http:// in front (not localhost: on a phone that means the phone itself)." % url,
		"iPhone with Chrome, Firefox or another app: Settings > that app > Local Network ON (Safari doesn't need it). Android: if Chrome asks about devices on your local network, allow it.",
		"Windows asked to allow Polox on the network: click Allow (or run allow_phone_link.bat once).",
		"Wi-Fi \"client isolation\" / \"AP isolation\" is off in your router (or use Tailscale, or the phone's hotspot).",
		"This PC isn't going to sleep (Advanced: Keep this PC awake).",
	])
