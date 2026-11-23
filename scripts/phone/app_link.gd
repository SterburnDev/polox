extends Node
## Polox for Android: finding the PC and remembering it.
##
## The PC announces itself on the home network while Phone Link is on (announcer.gd: a name and
## a port, nothing else), so the app listens for that first; then it tries the last address that
## worked, then the PC's Tailscale address (away from home). Whichever answers is used, and the
## app says which path that was. What it remembers lives in <save root>/phone/app_link.json
## (the app's private folder; never synced): the PC's name, the addresses, the pairing key and
## the worlds it may play.
##
## Plain HTTP only goes to private and Tailscale addresses (url_allowed). Android's own rule
## for this (the network security config) only covers Android's Java networking; Polox talks
## through Godot's own sockets, so the app enforces the same rule itself.
## Tags: [PAIRING]

signal _probes_done

const NetRules := preload("res://scripts/phone/net_rules.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const DISCOVERY_PORT := 8769
const PROBE_TIMEOUT_S := 4.0
const PATH_LABELS := {"home": "home network", "last": "last address", "tailscale": "Tailscale", "typed": "typed address", "qr": "QR code"}

var root := ""
var link: Dictionary = {}           # what's remembered (see the top)
var listen_port := DISCOVERY_PORT   # tests use their own
var listen_address := "*"           # tests listen on 127.0.0.1 only
var probe_timeout := PROBE_TIMEOUT_S
var last_find: Dictionary = {}      # the latest find_pc() result
var _cancel_epoch := 0
var _active_http: Array = []


## Cancels any active discovery listen/probe waits cleanly.
func cancel() -> void:
	_cancel_epoch += 1
	var pending := _active_http.duplicate()
	_active_http.clear()
	for h in pending:
		if is_instance_valid(h):
			h.cancel_request()
			h.queue_free()
	_probes_done.emit()


func _exit_tree() -> void:
	cancel()


static func link_file(save_root: String) -> String:
	return save_root.path_join("phone").path_join("app_link.json")


func load_link(save_root: String) -> void:
	root = save_root
	var d: Variant = JsonUtil.read_json(link_file(root), {})
	link = d if d is Dictionary else {}


func save_link() -> void:
	if root == "":
		return
	JsonUtil.ensure_dir(link_file(root).get_base_dir())
	JsonUtil.write_json(link_file(root), link)


func token() -> String:
	return str(link.get("token", ""))


func paired() -> bool:
	return token().length() == 64


func pc_name() -> String:
	return str(link.get("pc_name", ""))


## This phone's own id (made once, kept with the pairing): pairing again replaces its old entry on the PC.
func client_id() -> String:
	var id := str(link.get("client", ""))
	if id.length() != 16:
		id = Crypto.new().generate_random_bytes(8).hex_encode()
		link["client"] = id
		save_link()
	return id


## Forget the pairing key (the worlds on this phone stay).
func forget() -> void:
	for k in ["token", "device_id", "sig"]:
		link.erase(k)
	save_link()


# --- The plain-HTTP rule -------------------------------------------------------------------------

## HTTPS anywhere; plain HTTP only to this phone itself, the home network (private addresses)
## or Tailscale (100.64.0.0/10, fd7a:115c:a1e0::/48 and *.ts.net names).
static func url_allowed(url: String) -> bool:
	var u := url.strip_edges()
	var scheme := u.get_slice("://", 0).to_lower() if "://" in u else ""
	var rest := u.get_slice("://", 1) if "://" in u else ""
	var hostport := rest.get_slice("/", 0)
	if hostport == "" or "@" in hostport:
		return false
	var host := hostport
	if host.begins_with("["):
		host = host.substr(1, host.find("]") - 1)
	elif host.count(":") == 1:
		host = host.get_slice(":", 0)
	host = host.to_lower()
	if host == "":
		return false
	if scheme == "https":
		return true
	if scheme != "http":
		return false
	if host.ends_with(".ts.net"):
		return true
	return NetRules.kind(host) in ["loopback", "private", "tailscale"]


# --- Hearing the PC ------------------------------------------------------------------------------

## An announcement from announcer.gd, checked: {"polox": "pc", "v": 1, "name": ..., "port": ...}.
## Anything else (other programs on the same port, extra keys) gives {}.
static func parse_announcement(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > 512:
		return {}
	var j := JSON.new()   # (quietly: other programs' packets are often not JSON at all)
	if j.parse(bytes.get_string_from_utf8()) != OK:
		return {}
	var d: Variant = j.data
	if not d is Dictionary or str(d.get("polox", "")) != "pc" or int(d.get("v", 0)) != 1:
		return {}
	var port := int(d.get("port", 0))
	var name := str(d.get("name", "")).strip_edges().substr(0, 64)
	if port < 1 or port > 65535 or name == "":
		return {}
	return {"name": name, "port": port}


## Listens for the PC's announcements for `seconds`: [{name, port, ip, url}] (each PC once).
func listen(seconds: float) -> Array:
	var found: Array = []
	if not is_inside_tree():
		return found
	var epoch := _cancel_epoch
	var udp := PacketPeerUDP.new()
	# On Android this also takes Wi-Fi's multicast lock (some phones drop broadcasts without it).
	udp.set_broadcast_enabled(true)
	if udp.bind(listen_port, listen_address) != OK:
		return found
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0) and is_inside_tree() and epoch == _cancel_epoch:
		var drained := 0
		while udp.get_available_packet_count() > 0 and drained < 128:
			drained += 1
			var bytes := udp.get_packet()
			var ip := udp.get_packet_ip()
			var a := parse_announcement(bytes)
			if a.is_empty() or ip == "":
				continue
			var host := ("[%s]" % ip) if ":" in ip else ip
			var url := "http://%s:%d" % [host, int(a.port)]
			if not url_allowed(url) or found.any(func(f): return str(f.url) == url):
				continue
			found.append({"name": a.name, "port": a.port, "ip": ip, "url": url})
		var pause_until := Time.get_ticks_msec() + 50
		while Time.get_ticks_msec() < pause_until and is_inside_tree() and epoch == _cancel_epoch:
			await get_tree().process_frame
	udp.close()
	return found


# --- Asking an address ---------------------------------------------------------------------------

## Is Polox there? GET /hello.json (no pairing needed). {ok, url, name, ms, hello, error}.
func probe(url: String) -> Dictionary:
	return await _probe_epoch(url, _cancel_epoch)


func _probe_epoch(url: String, epoch: int) -> Dictionary:
	var out := {"ok": false, "url": url, "name": "", "ms": 0, "hello": {}, "error": ""}
	if not url_allowed(url):
		out.error = "not allowed: plain HTTP only goes to your home network or Tailscale"
		return out
	if not is_inside_tree() or epoch != _cancel_epoch:
		out.error = "cancelled"
		return out
	var http := HTTPRequest.new()
	http.timeout = probe_timeout
	add_child(http)
	_active_http.append(http)
	var box := {"done": false, "res": []}
	http.request_completed.connect(func(a, b, c, d):
		box.res = [a, b, c, d]
		box.done = true, CONNECT_ONE_SHOT)
	var t0 := Time.get_ticks_msec()
	if http.request(url.trim_suffix("/") + "/hello.json") != OK:
		_active_http.erase(http)
		http.queue_free()
		out.error = "couldn't start the request"
		return out
	var deadline := Time.get_ticks_msec() + int((probe_timeout + 5.0) * 1000.0)
	while not bool(box.done) and is_inside_tree() and epoch == _cancel_epoch and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if is_instance_valid(http):
		_active_http.erase(http)
		if not bool(box.done):
			http.cancel_request()
		http.queue_free()
	out.ms = Time.get_ticks_msec() - t0
	if not is_inside_tree() or epoch != _cancel_epoch:
		out.error = "cancelled"
		return out
	var res: Array = box.res if bool(box.done) else [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		out.error = "no answer" if int(res[0]) in [HTTPRequest.RESULT_TIMEOUT, HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE] else "connection failed (%d)" % int(res[0])
		return out
	var d: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if int(res[1]) != 200 or not d is Dictionary or not (d as Dictionary).has("pc_name"):
		out.error = "something answered, but not Polox (HTTP %d)" % int(res[1])
		return out
	out.ok = true
	out.hello = d
	out.name = str(d.get("pc_name", ""))
	return out


func _probe_into(job: Dictionary, key: String, url: String) -> void:
	job.res[key] = await _probe_epoch(url, int(job.get("epoch", _cancel_epoch)))
	job["left"] = int(job.left) - 1
	if int(job.left) == 0:
		_probes_done.emit()


## Finds the PC: the home network (announcements) first, then the last address that worked,
## then Tailscale. {ok, url, path ("home" | "last" | "tailscale"), name, tried: [{path, url, ok, detail}], heard: [...]}.
func find_pc(seconds: float = 3.0) -> Dictionary:
	var want := pc_name()
	var epoch := _cancel_epoch
	var job := {"left": 0, "res": {}, "epoch": epoch}
	var others: Array = []
	var last := str(link.get("last_url", ""))
	var ts := str(link.get("ts_url", ""))
	if last != "":
		others.append(["last", last])
	if ts != "" and ts != last:
		others.append(["tailscale", ts])
	job.left = others.size()
	for o in others:
		_probe_into(job, str(o[0]), str(o[1]))   # not awaited: they run while we listen
	var heard: Array = await listen(seconds)
	var probes_deadline := Time.get_ticks_msec() + int((seconds + probe_timeout + 5.0) * 1000.0)
	while int(job.left) > 0 and is_inside_tree() and epoch == _cancel_epoch and Time.get_ticks_msec() < probes_deadline:
		await get_tree().process_frame
	var out := {"ok": false, "url": "", "path": "", "name": "", "tried": [], "heard": heard}
	if not is_inside_tree() or epoch != _cancel_epoch:
		return out
	# Home network: the PC this phone is paired with (by name), or any Polox if not paired yet.
	for h in heard:
		if not is_inside_tree() or epoch != _cancel_epoch:
			return out
		if want != "" and str(h.name) != want:
			continue
		var r: Dictionary = await _probe_epoch(str(h.url), epoch)
		out.tried.append({"path": "home", "url": h.url, "ok": r.ok, "detail": r.error if not r.ok else "%d ms" % int(r.ms)})
		if r.ok:
			return _found(out, "home", r)
	if heard.is_empty():
		out.tried.append({"path": "home", "url": "", "ok": false, "detail": "no announcement heard in %.0f s (Phone Link off, another network, or the router blocks them)" % seconds})
	for o in others:
		var r: Dictionary = job.res.get(str(o[0]), {})
		out.tried.append({"path": o[0], "url": o[1], "ok": bool(r.get("ok", false)), "detail": str(r.get("error", "")) if not bool(r.get("ok", false)) else "%d ms" % int(r.get("ms", 0))})
		if bool(r.get("ok", false)) and (want == "" or str(r.get("name", "")) == want):
			return _found(out, str(o[0]), r)
	last_find = out
	return out


func _found(out: Dictionary, path: String, r: Dictionary) -> Dictionary:
	out.ok = true
	out.url = str(r.url)
	out.path = path
	out.name = str(r.name)
	remember(r.hello, str(r.url))
	last_find = out
	return out


## Keeps what a PC said about itself (after it answered at `url`).
func remember(hello: Dictionary, url: String) -> void:
	link["last_url"] = url
	if str(hello.get("pc_name", "")) != "":
		link["pc_name"] = str(hello.pc_name)
	var ts := str(hello.get("ts_url", ""))
	if ts != "" and url_allowed(ts):
		link["ts_url"] = ts
	var lan := str(hello.get("lan_url", ""))
	if lan != "" and url_allowed(lan):
		link["lan_url"] = lan
	if str(hello.get("version", "")) != "":
		link["pc_version"] = str(hello.version)
	link["seen"] = Time.get_datetime_string_from_system()
	save_link()


static func path_label(path: String) -> String:
	return str(PATH_LABELS.get(path, path))


# --- The app's pairing QR code -------------------------------------------------------------------

## The QR code the PC shows for the app: "POLOX-APP:1;n=<name>;u=<url>[,<url>...];p=<PIN>".
## Not a web address on purpose: the PIN must never be in one (browsers and servers log them).
static func qr_payload(pc: String, urls: PackedStringArray, pin: String) -> String:
	return "POLOX-APP:1;n=%s;u=%s;p=%s" % [pc.uri_encode(), ",".join(Array(urls).map(func(x): return str(x).uri_encode())), pin]


## {name, urls, pin} from a scanned code, or {} when it isn't Polox's.
static func parse_qr(text: String) -> Dictionary:
	if not text.begins_with("POLOX-APP:1;"):
		return {}
	var name := ""
	var urls := PackedStringArray()
	var pin := ""
	for part in text.trim_prefix("POLOX-APP:1;").split(";", false):
		var k := part.get_slice("=", 0)
		var v := part.substr(k.length() + 1)
		match k:
			"n":
				name = v.uri_decode().substr(0, 64)
			"u":
				for u in v.split(",", false):
					var url := u.uri_decode()
					if url_allowed(url) and urls.size() < 6:
						urls.append(url)
			"p":
				pin = v if v.is_valid_int() and v.length() == 6 else ""
	if urls.is_empty() or pin == "":
		return {}
	return {"name": name, "urls": urls, "pin": pin}
