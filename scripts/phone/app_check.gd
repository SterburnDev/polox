extends Node
## "Check connection" inside Polox for Android: the Connection Test ladder, rung by rung, from the
## phone's side, then the report goes to the PC (keyless /api/report, the same shape as the
## browser test's, page "app-check") so the PC's Doctor can show it.
##
##   network   this phone has a home-network or Tailscale address
##   announce  the PC's "Polox is here" was heard (a warning only: the last address can still work)
##   ping      GET /ping answers "Polox OK"
##   info      /test/info.json: which PC, which engine, what address the PC sees for this phone
##   big       a 20 MB download arrives whole (SHA-256 checked), like a big sync
##   paired    this phone's key is accepted (/api/status), and what the PC's AI is
##   sync      the PC's file list for this phone's worlds
## Nothing in the report is secret: no key, PIN, chat or world content.

signal rung(result: Dictionary)

const NetRules := preload("res://scripts/phone/net_rules.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")
const RequestSig := preload("res://scripts/phone/request_sig.gd")

var sign := false            # the phone paired with pair_v:1: requests carry a signature, never the key
var results: Array = []
var hints := PackedStringArray()
var info: Dictionary = {}
var big_path := "/test/big"
var timeout_s := 20.0
var _cancel_epoch := 0
var _active_http: Array = []


## Cancels any active HTTP check requests cleanly.
func cancel() -> void:
	_cancel_epoch += 1
	var pending := _active_http.duplicate()
	_active_http.clear()
	for h in pending:
		if is_instance_valid(h):
			h.cancel_request()
			h.queue_free()


func _exit_tree() -> void:
	cancel()


func _await_http(http: HTTPRequest, limit_s: float, epoch: int) -> Array:
	_active_http.append(http)
	var box := {"done": false, "res": []}
	http.request_completed.connect(func(a, b, c, d):
		box.res = [a, b, c, d]
		box.done = true, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + int((limit_s + 5.0) * 1000.0)
	while not bool(box.done) and is_inside_tree() and epoch == _cancel_epoch and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if is_instance_valid(http):
		_active_http.erase(http)
		if not bool(box.done):
			http.cancel_request()
		http.queue_free()
	if not is_inside_tree() or epoch != _cancel_epoch:
		return [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]
	return box.res if bool(box.done) else [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]


func _add(id: String, name: String, ok: bool, ms: int, detail: String, level: String = "") -> void:
	var r := {"id": id, "name": name, "ok": ok, "ms": ms, "detail": detail.substr(0, 300), "level": level if level != "" else ("ok" if ok else "bad")}
	results.append(r)
	rung.emit(r)


## {code, body, headers: {lowercase: value}, ms, error}
func _fetch(url: String, token: String = "", epoch: int = -1) -> Dictionary:
	var active_epoch := _cancel_epoch if epoch < 0 else epoch
	if not is_inside_tree() or active_epoch != _cancel_epoch:
		return {"code": 0, "body": PackedByteArray(), "headers": {}, "ms": 0, "error": "cancelled"}
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	add_child(http)
	var headers := PackedStringArray()
	if token != "":
		headers.append(RequestSig.header(token, "GET", url) if sign else "Authorization: Bearer " + token)
	var t0 := Time.get_ticks_msec()
	if http.request(url, headers) != OK:
		http.queue_free()
		return {"code": 0, "body": PackedByteArray(), "headers": {}, "ms": 0, "error": "couldn't start the request"}
	var res: Array = await _await_http(http, timeout_s, active_epoch)
	if active_epoch != _cancel_epoch or not is_inside_tree():
		return {"code": 0, "body": PackedByteArray(), "headers": {}, "ms": Time.get_ticks_msec() - t0, "error": "cancelled"}
	var hd := {}
	for line in res[2]:
		var k := str(line).get_slice(":", 0).strip_edges().to_lower()
		hd[k] = str(line).substr(str(line).find(":") + 1).strip_edges()
	var ok := int(res[0]) == HTTPRequest.RESULT_SUCCESS
	return {"code": int(res[1]) if ok else 0, "body": res[3], "headers": hd, "ms": Time.get_ticks_msec() - t0,
		"error": "" if ok else ("no answer (timed out)" if int(res[0]) == HTTPRequest.RESULT_TIMEOUT else "couldn't connect (%d)" % int(res[0]))}


## This phone's own addresses that a PC could answer on.
static func usable_addresses(all: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for ip in all:
		if NetRules.kind(ip) in ["private", "tailscale"]:
			out.append(ip)
	return out


## Runs every rung against `url` (the PC that answered, or the last one). `link` is app_link.gd.
func run(url: String, token: String, link: Node, slots: String = "") -> Dictionary:
	var epoch := _cancel_epoch
	results = []
	hints = PackedStringArray()
	info = {}
	if not is_inside_tree():
		return {"report": {}, "sent": false, "message": "Cancelled."}
	var mine := usable_addresses(IP.get_local_addresses())
	_add("network", "This phone's network", not mine.is_empty(), 0,
		("Addresses: " + ", ".join(mine)) if not mine.is_empty() else "No home-network or Tailscale address: connect to your Wi-Fi (or switch Tailscale on).")
	var heard: Array = []
	if link:
		heard = await link.listen(4.0)
	if epoch != _cancel_epoch or not is_inside_tree():
		return {"report": {}, "sent": false, "message": "Cancelled."}
	var heard_names := heard.map(func(h): return "%s at %s" % [h.name, h.url])
	_add("announce", "Hearing the PC", not heard.is_empty(), 4000,
		("Heard: " + ", ".join(PackedStringArray(heard_names))) if not heard.is_empty() else "No announcement in 4 s. Phone Link may be off, the phone on another network, or the router blocks them (guest Wi-Fi, \"AP isolation\"): the last address can still work.",
		"ok" if not heard.is_empty() else "warn")
	if url == "" and not heard.is_empty():
		url = str(heard[0].url)
	if url == "":
		_add("ping", "Reaching the PC", false, 0, "No address to try yet: switch Phone Link on, or type the address in Connect to your PC.")
		hints.append("Switch Phone Link on (PC: Settings > Phone Link) and keep the phone on the same Wi-Fi.")
		return await finish(url)
	var base := url.trim_suffix("/")
	var p := await _fetch(base + "/ping", "", epoch)
	if epoch != _cancel_epoch or not is_inside_tree():
		return {"report": {}, "sent": false, "message": "Cancelled."}
	var ping_ok := int(p.code) == 200 and (p.body as PackedByteArray).get_string_from_utf8().contains("Polox OK")
	_add("ping", "Reaching the PC", ping_ok, int(p.ms), ("%s answered \"Polox OK\"." % base) if ping_ok else ("%s: %s" % [base, p.error if str(p.error) != "" else "HTTP %d" % int(p.code)]))
	if not ping_ok:
		hints.append("The PC didn't answer at %s. Is Phone Link on? On the PC, run allow_phone_link.bat once if Windows Firewall blocks it." % base)
		return await finish(url)
	var i := await _fetch(base + "/test/info.json", "", epoch)
	if epoch != _cancel_epoch or not is_inside_tree():
		return {"report": {}, "sent": false, "message": "Cancelled."}
	var j: Variant = JSON.parse_string((i.body as PackedByteArray).get_string_from_utf8())
	info = j if j is Dictionary else {}
	_add("info", "Which PC", int(i.code) == 200 and str(info.get("app", "")) == "Polox", int(i.ms),
		("%s on %s (%s engine); the PC sees this phone as %s." % [info.get("server_name", "?"), info.get("pc", "?"), info.get("engine", "?"), info.get("your_ip", "?")]) if not info.is_empty() else "Unexpected answer (HTTP %d)." % int(i.code))
	var b := await _fetch(base + big_path, "", epoch)
	if epoch != _cancel_epoch or not is_inside_tree():
		return {"report": {}, "sent": false, "message": "Cancelled."}
	var body: PackedByteArray = b.body
	var want := str((b.headers as Dictionary).get("x-polox-sha256", ""))
	var size_ok := str((b.headers as Dictionary).get("content-length", "")) == str(body.size())
	var sha_ok := want != "" and HttpUtil.sha256_bytes(body) == want
	var mbps := (body.size() / 1048576.0) / maxf(0.001, int(b.ms) / 1000.0)
	_add("big", "Big download", int(b.code) == 200 and size_ok and sha_ok, int(b.ms),
		("%.1f MB arrived whole (%.1f MB/s)." % [body.size() / 1048576.0, mbps]) if sha_ok and size_ok else ("Arrived damaged or cut short: %d bytes%s." % [body.size(), "" if str(b.error) == "" else ", " + str(b.error)]))
	if token.length() != 64:
		_add("paired", "Paired with the PC", false, 0, "Not paired yet: Connect to your PC and type the PIN.")
		return await finish(url)
	var s := await _fetch(base + "/api/status", token, epoch)
	if epoch != _cancel_epoch or not is_inside_tree():
		return {"report": {}, "sent": false, "message": "Cancelled."}
	var st: Variant = JSON.parse_string((s.body as PackedByteArray).get_string_from_utf8())
	var st_ok := int(s.code) == 200 and st is Dictionary
	var ai_text := str((st as Dictionary).get("ai", {}).get("status", "")) if st_ok else ""
	_add("paired", "Paired with the PC", st_ok, int(s.ms),
		("The PC knows this phone as \"%s\". Friends' AI on the PC: %s." % [st.get("device", ""), ai_text if ai_text != "" else "?"]) if st_ok else ("The PC doesn't accept this phone's key (HTTP %d): pair again." % int(s.code) if int(s.code) == 401 else "HTTP %d %s" % [int(s.code), s.error]))
	if not st_ok:
		hints.append("Pair again: Settings > Your PC > Connect to your PC (the worlds on this phone stay).")
		return await finish(url)
	var m := await _fetch(base + "/api/manifest" + (("?slots=" + slots.uri_encode()) if slots != "" else ""), token, epoch)
	if epoch != _cancel_epoch or not is_inside_tree():
		return {"report": {}, "sent": false, "message": "Cancelled."}
	var mj: Variant = JSON.parse_string((m.body as PackedByteArray).get_string_from_utf8())
	var files: int = (mj as Dictionary).get("files", {}).size() if mj is Dictionary else 0
	_add("sync", "Sync", int(m.code) == 200 and mj is Dictionary, int(m.ms),
		("The PC lists %d file(s) in %d world(s) for this phone." % [files, (mj as Dictionary).get("slots", []).size()]) if mj is Dictionary else "HTTP %d" % int(m.code))
	return await finish(url)


## Builds the report and sends it to the PC (if it's reachable). {report, sent, message}.
func finish(url: String) -> Dictionary:
	var report := {
		"v": 1, "app": "Polox", "page": "app-check", "when": Time.get_datetime_string_from_system(true),
		"server": str(info.get("server", "")), "server_name": str(info.get("server_name", "")), "engine": str(info.get("engine", "")),
		"pc": str(info.get("pc", "")), "build_id": str(info.get("build_id", "")), "your_ip": str(info.get("your_ip", "")),
		"address": url.trim_prefix("http://").trim_prefix("https://"), "results": results, "hints": hints,
		"env": {"device": OS.get_model_name(), "os": "%s %s" % [OS.get_name(), OS.get_version()], "app_version": str(ProjectSettings.get_setting("application/config/version", "")), "app": true},
	}
	var out := {"report": report, "sent": false, "message": "Not sent: the PC isn't reachable."}
	if url == "" or not is_inside_tree():
		return out
	var epoch := _cancel_epoch
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	if http.request(url.trim_suffix("/") + "/api/report", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(report)) == OK:
		var res: Array = await _await_http(http, 10.0, epoch)
		out.sent = int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200
		out.message = "Sent to the PC (its Doctor shows it)." if out.sent else "The PC didn't take the report (HTTP %d)." % int(res[1])
	else:
		http.queue_free()
	return out


## Plain text for copying: one line per rung.
static func as_text(results_list: Array) -> String:
	var lines := PackedStringArray()
	for r in results_list:
		lines.append("%s %s: %s%s" % ["OK  " if bool(r.ok) else ("WARN" if str(r.level) == "warn" else "FAIL"), r.name, r.detail, (" (%d ms)" % int(r.ms)) if int(r.ms) > 0 else ""])
	return "\n".join(lines)
