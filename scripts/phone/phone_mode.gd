extends Node
## Runs only in the phone builds: the browser version and Polox for Android.
## Points the AI at the PC ("Your PC" provider: the key stays on the PC) and
## keeps the local copy in sync: a pull when the game starts, a push a little
## after each save, and one more whenever the page or app is hidden (switching
## apps, locking the phone). "Sync now" in the HUD runs one by hand.
##
## The browser version reads the device token the pairing page left in this
## browser and hosts the HTML text bar for typing on phones.
## The app (app == true) finds the PC by itself (app_link.gd: home network,
## last address, Tailscale), pairs inside the app, plays offline with its own
## copy, retries every minute while the PC is away, syncs again whenever it
## comes back to the front, and offers the PC's newer app version.
##
## For testing on a PC: --phone-mode=http://127.0.0.1:8737 --phone-token=...
## or --app-mode (the app; --app-discovery-port=N listens on 127.0.0.1:N).
## Tags: [PAIRING]

signal sync_state_changed(state: String, detail: String)

const SyncClient := preload("res://scripts/phone/sync_client.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const AppLink := preload("res://scripts/phone/app_link.gd")
const Device := preload("res://scripts/core/device.gd")
const PhoneExports := preload("res://scripts/phone/phone_exports.gd")

const PUSH_DELAY_S := 15.0
const RETRY_OFFLINE_S := 60.0   # the app: look for the PC again this often while it's away

var main: Node
var origin := ""
var token := ""
var signs := false              # paired with pair_v:1: requests are signed (request_sig.gd), the key never sent
var client: Node                # sync_client.gd
var _push_in := -1.0
var _js_callbacks: Array = []   # JavaScriptObjects must stay referenced
var _keyboard_cb: Callable = Callable()
var canonical := ""             # the PC's main address for Polox (from /hello.json)
var slot := ""                  # the world picked in the launcher (#slot= or localStorage)
var has_launcher := false       # the PC serves the launcher at / (Polox 1.1+; older PCs only have /pair)
var address_ok := true          # this page was opened at that address
var storage_ok := true          # the browser keeps our files (not a private tab)
var _test_hooks := false
var _test_t := 0.0
var _kb_wanted := false         # it's your turn in a chat
var _kb_shown := false          # the page's bar is on screen
var _kb_placeholder := ""
var app := false                # Polox for Android (or --app-mode)
var link: Node                  # app_link.gd (the app only)
var connection: Dictionary = {} # the app: the latest find_pc() result ({ok, url, path, name, tried})
var update_offer: Dictionary = {}   # the app: the PC's newer app ({version, version_code, url}) or {}
var retry_offline_s := RETRY_OFFLINE_S
var force_app := false          # tests: be the app without --app-mode
var _retry_in := -1.0
var _connecting := false
var _sending_crash_reports := false
var _sending_exports := false


## True in the browser build, or when a PC run asks to pretend.
static func wanted() -> bool:
	if OS.has_feature("web") or Device.is_app():
		return true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phone-mode="):
			return true
	return false


func setup(main_node: Node) -> void:
	main = main_node
	origin = _arg("--phone-mode=")
	token = _arg("--phone-token=")
	app = (force_app or Device.is_app()) and not OS.has_feature("web")
	if app:
		link = AppLink.new()
		add_child(link)
		link.load_link(SaveManager.root)
		var lp := _arg("--app-discovery-port=")
		if lp != "":
			link.listen_port = lp.to_int()
			link.listen_address = "127.0.0.1"
		origin = str(link.link.get("last_url", "")) if origin == "" else origin
		token = link.token() if token == "" else token
		signs = bool(link.link.get("sig", false))
	if OS.has_feature("web"):
		origin = str(JavaScriptBridge.eval("location.origin", true))
		token = str(JavaScriptBridge.eval("localStorage.getItem('polox_token') || ''", true))
		signs = str(JavaScriptBridge.eval("localStorage.getItem('polox_sig') || ''", true)) == "1"   # the launcher's pair_v:1
		slot = str(JavaScriptBridge.eval("(function () { var m = /[#&]slot=([^&]+)/.exec(location.hash); return m ? decodeURIComponent(m[1]) : (localStorage.getItem('polox_slot') || ''); })()", true))
		storage_ok = OS.is_userfs_persistent()
		JavaScriptBridge.eval("window.poloxBooted = Date.now(); 1", true)   # the start-up diagnostics (boot_diag.gd) stop waiting
		_hook_page()
		if str(JavaScriptBridge.eval("location.hash + '|' + (sessionStorage.getItem('polox_test') || '')", true)).contains("polox-test"):
			_expose_test_hooks()
	client = SyncClient.new()
	add_child(client)
	client.base_url = origin
	client.token = token
	client.sign = signs
	client.only_slots = slot if slot != "" else _arg("--phone-slot=")
	if app:
		client.only_slots = ",".join(PackedStringArray(link.link.get("worlds", [])))
	slot = client.only_slots if not app else ""
	client.local_root = SaveManager.root
	client.on_pulled = _on_pulled
	client.status_changed.connect(func(s, d): sync_state_changed.emit(s, d))
	# Friends talk through the PC; nothing about the PC's AI settings is stored here.
	var ai: Dictionary = GameState.settings.get("ai", {})
	ai["preset"] = "pc"
	ai["base_url"] = origin
	GameState.settings["ai"] = ai
	AIClient.pc_token = token
	AIClient.pc_sign = signs
	AIClient.configure(ai)
	SaveManager.saved.connect(_schedule_push)
	ChatLog.logged.connect(func(_e): _schedule_push(""))
	if app:
		# Exports used to stay in the app's private storage: every one not in Downloads yet goes there now.
		PhoneExports.copy_missing_to_downloads(SaveManager.root)


static func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func paired() -> bool:
	return token.length() == 64


## The browser version types through the page's own text bar; the app uses Android's keyboard.
func uses_page_keyboard() -> bool:
	return not app


## Sends the browser to the launcher (PIN, then the worlds; same address, so storage is shared).
## The app opens its own Connect screen instead.
func open_pairing_page() -> void:
	if app:
		if main and main.has_method("open_app_connect"):
			main.open_app_connect(false, true)
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.href = '%s'" % ("/" if has_launcher else "/pair"), true)


## Asks the PC for its main address (no pairing needed) and compares it with
## the one this page was opened at: the browser keeps pairing and saves per
## address, so a different one looks "unpaired" and starts empty.
func check_address() -> void:
	var r: Dictionary = await client.request("GET", "/hello.json")
	if r.ok and r.json is Dictionary:
		canonical = str(r.json.get("canonical", ""))
		var urls: Variant = r.json.get("urls", [])
		has_launcher = r.json.has("lan_url")
		address_ok = canonical == "" or canonical == origin or (urls is Array and origin in urls)
	else:
		address_ok = true


## A short, plain warning for the title screen ("" when all is well).
func startup_warning() -> String:
	if not storage_ok:
		return "This browser won't keep Polox's saves (a private tab?). Use a normal tab or the Home Screen icon."
	if not address_ok:
		return "Different address: this is %s, but Polox's main address is %s. Open that one: pairing and saves are kept per address." % [origin, canonical]
	return ""


## The first sync, before the title screen offers "Continue".
func startup_sync() -> void:
	if not paired():
		return
	var r: Dictionary = await client.sync()
	if r.ok:
		SaveManager.set_root(SaveManager.root)   # pick up worlds that just arrived
		GameState.reload_settings()
		_reassert_ai()


func sync_now() -> Dictionary:
	if not paired():
		return {"ok": false, "error": "not paired"}
	main.flush_all()
	var r: Dictionary = await client.sync()
	if r.ok:
		await send_crash_reports()
		await send_exports()
	return r


func _schedule_push(_path: String) -> void:
	if paired() and _push_in < 0.0:
		_push_in = PUSH_DELAY_S


# --- The app: finding the PC, pairing, updates -----------------------------------------------------

## Finds the PC (home network, then the last address, then Tailscale) and uses whatever answered.
func connect_pc(seconds: float = 3.0) -> Dictionary:
	if _connecting:
		return {"ok": false, "error": "busy"}
	_connecting = true
	var r: Dictionary = await link.find_pc(seconds)
	_connecting = false
	connection = r
	if r.ok:
		use_origin(str(r.url))
		if paired():
			var full := await _hello_with_key({})
			if not full.is_empty():
				link.remember(full, str(r.url))   # the PC's other addresses may have changed
			await refresh_worlds()
		await check_update()
		await send_crash_reports()
		await send_exports()
		_retry_in = -1.0
	elif paired():
		_retry_in = retry_offline_s
		client.state = "offline"
		client.detail = "PC not found: playing your own copy (it syncs when the PC is back)"
		sync_state_changed.emit(client.state, client.detail)
	return r


func use_origin(url: String) -> void:
	origin = url
	client.base_url = url
	_reassert_ai()


## "Connected over the home network (192.168.1.42:8765)" and the like.
func connection_text() -> String:
	if not app:
		return origin
	if not bool(connection.get("ok", false)):
		return "PC not found" if not connection.is_empty() else ("Last address: " + origin if origin != "" else "Not connected yet")
	return "Connected over the %s (%s)" % [AppLink.path_label(str(connection.path)), str(connection.url).trim_prefix("http://").trim_prefix("https://")]


## The worlds this phone may play: asked each time it connects, kept for starting offline.
func refresh_worlds() -> Array:
	var status: Dictionary = await client.request("GET", "/api/status")
	var Research := preload("res://scripts/home/research.gd")
	Research.pc_helper = status.get("json", {}).get("home_helper", {}) if bool(status.get("ok", false)) else {}
	var provider := str(Research.pc_helper.get("provider", ""))
	Research.HELPER_LABELS["pc"] = "PC · " + str(Research.HELPER_LABELS.get(provider, "helper"))
	Research.WHO["pc"] = "your paired PC, then " + str(Research.WHO.get(provider, "its configured helper"))
	var r: Dictionary = await client.request("GET", "/api/worlds")
	var worlds: Array = []
	if r.ok and r.json is Dictionary:
		worlds = r.json.get("worlds", [])
		var ids := PackedStringArray()
		for w in worlds:
			if w is Dictionary:
				ids.append(str(w.get("id", "")))
		link.link["worlds"] = Array(ids)
		link.save_link()
		client.only_slots = ",".join(ids)
	return worlds


## Pairs with the PC at `url` using the PIN (typed, or read from the PC's QR code).
func pair_with(url: String, pin: String, device_name: String, how: String = "typed") -> Dictionary:
	if not AppLink.url_allowed(url):
		return {"ok": false, "error": "That address isn't allowed: plain HTTP only goes to your home network or Tailscale."}
	var hello: Dictionary = await link.probe(url)
	if not hello.ok:
		return {"ok": false, "error": "No Polox at %s (%s)." % [url, hello.error]}
	use_origin(url)
	# A PC that paired with pair_v:1 once never gets the PIN as is again (an answer without it is a downgrade).
	var safe_pcs: Array = link.link.get("pair_v_pcs", []) if link.link.get("pair_v_pcs", []) is Array else []
	var r: Dictionary = await client.pair(pin, device_name, link.client_id(), str(hello.name) in safe_pcs)
	if not r.ok:
		return r
	token = str(r.token)
	signs = bool(r.get("sig", false))
	AIClient.pc_token = token
	AIClient.pc_sign = signs
	link.link["token"] = token
	link.link["sig"] = signs
	link.link["paired_at"] = Time.get_datetime_string_from_system()
	if int(r.get("pair_v", 0)) == 1 and not str(hello.name) in safe_pcs:
		safe_pcs.append(str(hello.name))
		link.link["pair_v_pcs"] = safe_pcs
	link.remember(await _hello_with_key(hello.hello), url)
	connection = {"ok": true, "url": url, "path": how if how in ["qr", "typed"] else "home", "name": hello.name, "tried": []}
	await refresh_worlds()
	return {"ok": true, "phrase": str(r.get("phrase", "")), "pair_v": int(r.get("pair_v", 0))}


## /hello.json again with the key: a stranger only gets the PC's name, a paired phone also gets its
## other addresses (Tailscale, home network), which finding the PC away from home needs.
func _hello_with_key(fallback: Dictionary) -> Dictionary:
	if not paired():
		return fallback
	var r: Dictionary = await client.request("GET", "/hello.json")
	if r.ok and r.json is Dictionary and (r.json as Dictionary).has("pc_name"):
		return r.json
	return fallback


## Forget the PC's key (the worlds on this phone stay; pair again to sync).
func unpair() -> void:
	if paired():
		await client.request("POST", "/api/unpair")
	token = ""
	client.token = ""
	client.sign = false
	signs = false
	AIClient.pc_sign = false
	link.forget()


## The PC has a newer Polox for Android: remember it so the title screen and Settings can offer it.
func check_update() -> Dictionary:
	update_offer = {}
	var r: Dictionary = await client.request("GET", "/app/version.json")
	if r.ok and r.json is Dictionary and bool(r.json.get("available", false)):
		if int(r.json.get("version_code", 0)) > _my_version_code():
			update_offer = {"version": str(r.json.version), "version_code": int(r.json.version_code), "url": origin.trim_suffix("/") + "/app/polox.apk", "size": int(r.json.get("size", 0))}
	return update_offer


static func _my_version_code() -> int:
	var p := str(ProjectSettings.get_setting("application/config/version", "0.0.0")).split(".")
	# The same formula as AndroidApp.version_code, CODE_BASE (100000) included.
	return (100000 + p[0].to_int() * 10000 + p[1].to_int() * 100 + p[2].to_int()) if p.size() >= 3 else 0


## Opens the PC's APK in the phone's browser: it downloads, and Android's installer updates
## Polox in place (same key, so the worlds on the phone stay).
func open_update() -> void:
	if not update_offer.is_empty():
		OS.shell_open(str(update_offer.url))


## The app went to the background or came back (main.gd forwards Android's notifications).
func on_lifecycle(resumed: bool) -> void:
	if not app or not paired():
		return
	if resumed:
		if origin == "" or client.state == "offline":
			connect_pc(2.0)
		elif not client.busy:
			client.sync()
	elif origin != "" and not client.busy:
		client.sync()   # best effort: Android may pause us before it finishes (the next start syncs)


func _process(delta: float) -> void:
	_update_keyboard()
	if app and _retry_in >= 0.0:
		_retry_in -= delta
		if _retry_in < 0.0 and not _connecting:
			_retry_offline()
	if _test_hooks:
		_test_t += delta
		if _test_t > 0.5:
			_test_t = 0.0
			JavaScriptBridge.eval("window.poloxTestState = %s;" % JSON.stringify(JSON.stringify(test_state())), true)
	if _push_in >= 0.0:
		_push_in -= delta
		if _push_in < 0.0:
			if client.busy:
				_push_in = 0.0   # edits made during a long sync still get a turn afterwards
			else:
				client.sync()


## The app, while the PC is away: look again; when it's back, sync.
func _retry_offline() -> void:
	var r: Dictionary = await connect_pc(2.0)
	if not is_inside_tree():
		return
	if r.ok and paired():
		# A sync that started while the PC was still away fails as "offline": wait for it, then sync again
		# (skipping it left the phone saying offline, with nothing synced, until something else saved).
		var deadline := Time.get_ticks_msec() + int(client.TIMEOUT_S * 4.0 * 1000.0)
		while is_instance_valid(client) and client.busy and is_inside_tree() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if not is_inside_tree() or not is_instance_valid(client):
			return
		var s: Dictionary = await client.sync()
		if not is_inside_tree():
			return
		if s.ok and (main == null or main.game == null):
			SaveManager.set_root(SaveManager.root)   # worlds that just arrived show on the title screen


## After a pull while playing: reload so the game shows (and keeps) the PC's version (only when something
## on screen changed; the reload waits while you're busy).
func _on_pulled(slots: Array, paths: Array = []) -> void:
	if main.game and SaveManager.slot_id in slots and (paths.is_empty() or SyncFiles.needs_reload(paths)):
		main.reload_world_from_disk()


## Crash reports this phone kept (crash_log.gd) go to the PC's report box once it's reachable.
func send_crash_reports() -> void:
	var cl: Node = main.get("crash_log") if main else null
	if cl == null or origin == "" or _sending_crash_reports:
		return
	_sending_crash_reports = true
	for crash in (cl.pending as Array).duplicate():
		var r: Dictionary = await client.request("POST", "/api/report", JSON.stringify(cl.as_report(crash)).to_utf8_buffer())
		if r.ok:
			cl.mark_sent(crash)
	_sending_crash_reports = false


## Exported worlds and chat logs the PC doesn't have yet go to its exports folder (phone_exports.gd).
## Returns how many went.
func send_exports() -> int:
	if not paired() or origin == "" or _sending_exports:
		return 0
	_sending_exports = true
	var n: int = await PhoneExports.send_missing_to_pc(client, SaveManager.root)
	_sending_exports = false
	return n


## A file just exported here: a copy in Downloads, and one on the PC when it's in reach.
## Returns {downloads: where on this phone ("" if nowhere), pc: "exports/<name>" or "", paired}.
func share_export(path: String) -> Dictionary:
	var out := {"downloads": PhoneExports.save_to_downloads(SaveManager.root, path), "pc": "", "paired": paired()}
	if paired() and origin != "" and not _sending_exports:
		_sending_exports = true
		var r: Dictionary = await PhoneExports.send_to_pc(client, SaveManager.root, path)
		_sending_exports = false
		out["pc"] = str(r.saved) if bool(r.ok) else ""
	return out


## Plain words for share_export()'s result.
static func share_text(file: String, r: Dictionary) -> String:
	var parts := PackedStringArray()
	if str(r.get("downloads", "")) != "":
		parts.append("A copy is in %s on this phone." % ("your browser's downloads" if str(r.downloads) == "your browser's downloads" else str(r.downloads).get_base_dir()))
	else:
		parts.append("This phone couldn't put a copy in Downloads.")
	if str(r.get("pc", "")) != "":
		parts.append("Your PC has it too (PersonalData/%s)." % ("phone_backups" if str(r.pc).begins_with("phone_backups") else "exports"))
	elif bool(r.get("paired", false)):
		parts.append("It goes to your PC the next time they're connected.")
	return "%s\n%s" % [file, " ".join(parts)]


## reload_settings() re-reads the phone's settings.json; keep the PC provider.
func _reassert_ai() -> void:
	var ai: Dictionary = GameState.settings.get("ai", {})
	if str(ai.get("preset", "")) != "pc" or str(ai.get("base_url", "")) != origin:
		ai["preset"] = "pc"
		ai["base_url"] = origin
		GameState.settings["ai"] = ai
		AIClient.configure(ai)


# --- The page ----------------------------------------------------------------------------------

## Page hidden (app switch, lock): save everything and push it to the PC.
func _hook_page() -> void:
	var cb := JavaScriptBridge.create_callback(_on_visibility)
	_js_callbacks.append(cb)
	var window = JavaScriptBridge.get_interface("window")  # a JavaScriptObject: dynamic on purpose
	window.poloxOnHidden = cb
	JavaScriptBridge.eval("document.addEventListener('visibilitychange', function () { if (document.hidden && window.poloxOnHidden) window.poloxOnHidden(); });", true)
	var send := JavaScriptBridge.create_callback(_on_keyboard_send)
	_js_callbacks.append(send)
	window.poloxOnSend = send


func _on_visibility(_args: Array) -> void:
	main.flush_all()
	if paired() and not client.busy:
		client.sync()


## The HTML text bar (see the Web export's head include): phones open their
## keyboard reliably for a real page input, so chat typing goes through it.
func show_keyboard(placeholder: String, on_send: Callable) -> void:
	_keyboard_cb = on_send
	_kb_wanted = true
	_kb_placeholder = placeholder
	_update_keyboard()


## The bar shows only while it's your turn and nothing covers the chat box
## (it sits on top of the whole page, so it would hide a panel's buttons).
func keyboard_visible() -> bool:
	return _kb_shown


func _update_keyboard() -> void:
	var want := _kb_wanted and main != null and (main.get("panels") as Array).is_empty()
	if want == _kb_shown:
		return
	_kb_shown = want
	if OS.has_feature("web"):
		if want:
			JavaScriptBridge.eval("window.poloxKeyboard && window.poloxKeyboard.show(%s)" % JSON.stringify(_kb_placeholder), true)
		else:
			JavaScriptBridge.eval("window.poloxKeyboard && window.poloxKeyboard.hide()", true)


## How much of the page's height the text bar covers (0 when it's hidden or
## off the web), so the chat box can sit above it instead of under it.
func keyboard_cover() -> float:
	if not OS.has_feature("web"):
		return 0.0
	var v: Variant = JavaScriptBridge.eval("(function () { var b = document.getElementById('polox-kb'); return b && b.style.display !== 'none' && window.innerHeight > 0 ? b.offsetHeight / window.innerHeight : 0; })()", true)
	return clampf(float(v), 0.0, 0.5) if v is float or v is int else 0.0


func hide_keyboard() -> void:
	_keyboard_cb = Callable()
	_kb_wanted = false
	_update_keyboard()


func _on_keyboard_send(args: Array) -> void:
	_kb_wanted = false
	_kb_shown = false   # the page hid its bar itself
	if _keyboard_cb.is_valid() and not args.is_empty():
		_keyboard_cb.call(str(args[0]))


# --- Test hooks (only with #polox-test in the address; used by tools/dev/browser_check.gd) ---------

## window.poloxTest.run(action) starts an action; window.poloxTestState holds the
## game's state as JSON, refreshed twice a second (callbacks can't return values to JS).
func _expose_test_hooks() -> void:
	var run_cb := JavaScriptBridge.create_callback(func(a: Array) -> void: test_run(str(a[0]) if not a.is_empty() else ""))
	_js_callbacks.append(run_cb)
	JavaScriptBridge.eval("window.poloxTest = {};", true)
	var hooks = JavaScriptBridge.get_interface("poloxTest")  # a JavaScriptObject: dynamic on purpose
	hooks.run = run_cb
	_test_hooks = true


func test_state() -> Dictionary:
	var screen := "loading"
	if main.game != null:
		screen = "game"
	elif main.screen != null:
		screen = str(main.screen.get_script().resource_path.get_file().get_basename())
	var tiles := 0
	if main.game != null:
		tiles = (SaveManager.load_room(GameState.current_room_id).get("tiles", []) as Array).size()
	return {
		"screen": screen, "paired": paired(), "sync": client.state, "detail": client.detail, "busy": client.busy,
		"has_world": GameState.has_world(), "room": GameState.current_room_id, "tiles": tiles,
		"address_ok": address_ok, "storage_ok": storage_ok, "panels": (main.get("panels") as Array).size(),
	}


func test_run(action: String) -> String:
	match action:
		"continue":
			main.start_game()
		"place_block":
			if main.game == null:
				return "no game"
			var b: Node = main.game.build
			b.enter()
			b.set_piece("cube")
			b.cursor = Vector2i(1, 4)
			b.apply({})
			b.exit()
		"sync":
			sync_now()
		_:
			return "unknown"
	return "ok"
