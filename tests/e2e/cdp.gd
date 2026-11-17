extends RefCounted
## A tiny Chrome DevTools Protocol client (dev-only, for check_phone.bat):
## starts the installed Edge or Chrome headless with a throwaway profile,
## connects to its page over a WebSocket, sends commands, collects console
## errors and exceptions. No downloads, nothing installed; the user's own
## browser profile is never touched.

const BROWSERS: PackedStringArray = [
	"C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
	"C:/Program Files/Microsoft/Edge/Application/msedge.exe",
	"C:/Program Files/Google/Chrome/Application/chrome.exe",
	"C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
]

var tree: SceneTree
var pid := -1
var debug_port := 0
var ws := WebSocketPeer.new()
var console_errors: PackedStringArray = []
var console_all: PackedStringArray = []
var _id := 0
var _replies := {}


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree


static func find_browser() -> String:
	for b in BROWSERS:
		if FileAccess.file_exists(b):
			return b
	var local := OS.get_environment("LOCALAPPDATA").path_join("Google/Chrome/Application/chrome.exe")
	return local if FileAccess.file_exists(local) else ""


func launch(browser: String, profile_dir: String) -> bool:
	var helper: RefCounted = preload("res://tests/test_case.gd").new()
	DirAccess.make_dir_recursive_absolute(profile_dir)
	for _try in 3:
		debug_port = helper.free_port()   # (the system picks it; retries on TOCTOU bind collision)
		if debug_port <= 0:
			return false
		pid = OS.create_process(browser, [
			"--headless=new", "--remote-debugging-port=%d" % debug_port, "--user-data-dir=" + profile_dir,
			# Never signed in, never synced with the user's account (Edge signs new profiles in by itself).
			"--inprivate" if browser.to_lower().ends_with("msedge.exe") else "--incognito", "--disable-sync",
			"--no-first-run", "--no-default-browser-check", "--disable-extensions", "--mute-audio",
			"--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
			"--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows",
			"--autoplay-policy=no-user-gesture-required", "--window-size=390,844", "about:blank"])
		if pid <= 0:
			continue
		# Find the page target and connect to it.
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t < 15000:
			if not OS.is_process_running(pid):
				break   # crashed or remote-debugging port collided cleanly: retry with another ephemeral port
			var list := await _json_list()
			for target in list:
				if target is Dictionary and str(target.get("type", "")) == "page" and str(target.get("url", "")) == "about:blank" and str(target.get("webSocketDebuggerUrl", "")) != "":
					ws.inbound_buffer_size = 32 * 1024 * 1024
					ws.max_queued_packets = 4096
					ws.connect_to_url(str(target.webSocketDebuggerUrl).replace("ws://127.0.0.1/", "ws://127.0.0.1:%d/" % debug_port))
					var ws_wait := Time.get_ticks_msec()
					while ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() - ws_wait < 10000:
						ws.poll()
						await tree.process_frame
					if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
						await send("Runtime.enable")
						await send("Log.enable")
						await send("Page.enable")
						return true
			await tree.create_timer(0.3).timeout
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
		pid = -1
	return false


func _json_list() -> Array:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", debug_port) != OK:
		return []
	var t := Time.get_ticks_msec()
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t < 2000:
		peer.poll()
		await tree.process_frame
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return []
	# The browser builds its WebSocket address from this Host header: it must carry the port.
	peer.put_data(("GET /json/list HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n" % debug_port).to_utf8_buffer())
	var got := PackedByteArray()
	t = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 3000:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_data(n)[1])
		else:
			await tree.process_frame
	var text := got.get_string_from_utf8()
	var body := text.substr(text.find("\r\n\r\n") + 4)
	var data: Variant = JSON.parse_string(body.substr(body.find("[")))
	return data if data is Array else []


## Sends a command and waits for its answer (the "result" part, or {error}).
func send(method: String, params: Dictionary = {}, timeout_s: float = 30.0) -> Dictionary:
	_id += 1
	var my := _id
	ws.send_text(JSON.stringify({"id": my, "method": method, "params": params}))
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(timeout_s * 1000.0):
		pump()
		if _replies.has(my):
			var r: Dictionary = _replies[my]
			_replies.erase(my)
			return r.get("result", {"error": r.get("error", {})}) if r.has("result") or r.has("error") else r
		await tree.process_frame
	return {"error": "timeout"}


## Reads whatever arrived: answers, console messages, exceptions.
func pump() -> void:
	ws.poll()
	while ws.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if not msg is Dictionary:
			continue
		if msg.has("id"):
			_replies[int(msg.id)] = msg
			continue
		var m := str(msg.get("method", ""))
		var p: Dictionary = msg.get("params", {})
		if m == "Runtime.consoleAPICalled":
			var text := ""
			for a in p.get("args", []):
				text += str(a.get("value", a.get("description", ""))) + " "
			console_all.append("%s: %s" % [p.get("type", ""), text.strip_edges()])
			if str(p.get("type", "")) == "error":
				console_errors.append(text.strip_edges())
		elif m == "Runtime.exceptionThrown":
			var d: Dictionary = p.get("exceptionDetails", {})
			console_errors.append("exception: %s %s" % [str(d.get("text", "")), str(d.get("exception", {}).get("description", ""))])
		elif m == "Log.entryAdded":
			var e: Dictionary = p.get("entry", {})
			console_all.append("log %s: %s" % [e.get("level", ""), e.get("text", "")])
			if str(e.get("level", "")) == "error":
				console_errors.append("log: " + str(e.get("text", "")))


## Evaluates JavaScript in the page; returns its value (awaiting promises).
func eval_js(expr: String) -> Variant:
	var r := await send("Runtime.evaluate", {"expression": expr, "returnByValue": true, "awaitPromise": true})
	if r.has("exceptionDetails"):
		return null
	return r.get("result", {}).get("value")


func navigate(url: String) -> void:
	await send("Page.navigate", {"url": url})


func screenshot(path: String) -> bool:
	var r := await send("Page.captureScreenshot", {"format": "png"}, 30.0)
	var data := str(r.get("data", ""))
	if data == "":
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(Marshalls.base64_to_raw(data))
	f.close()
	return true


func close() -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify({"id": 999999, "method": "Browser.close"}))
		ws.poll()
	ws.close()
	if pid > 0:
		OS.delay_msec(300)
		OS.kill(pid)
	pid = -1
