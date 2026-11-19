extends RefCounted
## Reports from phones (/api/report): the Connection Test page and the game's
## start-up diagnostics send what they saw so the PC can show it. No token is
## needed (a phone that can't pair must still be able to report), so it is
## strictly limited: home-network and Tailscale addresses only, 24 KB per
## report, 6 a minute and 40 an hour per address, 200 an hour in all. The
## content is untrusted text: only known keys are kept, strings are cut short
## and stripped of control characters, nothing in it is ever run or rendered
## as markup. Saved under <save root>/phone_reports/ (the last 100).
## Thread-safe: Polox Ping and Phone Link call it from their socket threads.

const NetRules := preload("res://scripts/phone/net_rules.gd")

const MAX_BYTES := 192 * 1024
const MAX_GET := 4096
const PER_IP_MINUTE := 6
const PER_IP_HOUR := 40
const ALL_HOUR := 200
const KEEP_FILES := 100
const TOP_KEYS: PackedStringArray = ["v", "app", "page", "when", "server", "server_name", "engine", "pc", "build_id", "your_ip", "address", "results", "env", "hints", "log", "stage", "files"]

var dir := ""
var _mutex := Mutex.new()
var _hits: Dictionary = {}      # ip -> [unix seconds]
var _all: Array = []
var _recent: Array = []         # this run's reports (newest last)


func _init(save_root: String) -> void:
	dir = save_root.path_join("phone_reports")


## A report arrived (any thread). `body` is the POST body or the decoded GET
## parameter. Returns [http status, message].
func accept(ip: String, body: PackedByteArray, transport: String, server: String, engine: String = "") -> Array:
	if not NetRules.source_allowed(ip, "home"):
		return [403, "This address isn't allowed to send reports."]
	if body.size() > MAX_BYTES:
		return [413, "Report too big."]
	var now := Time.get_unix_time_from_system()
	_mutex.lock()
	var mine: Array = (_hits.get(ip, []) as Array).filter(func(t): return now - float(t) < 3600.0)
	_all = _all.filter(func(t): return now - float(t) < 3600.0)
	var last_minute := mine.filter(func(t): return now - float(t) < 60.0).size()
	if last_minute >= PER_IP_MINUTE or mine.size() >= PER_IP_HOUR or _all.size() >= ALL_HOUR:
		_hits[ip] = mine
		_mutex.unlock()
		return [429, "Too many reports; wait a minute."]
	mine.append(now)
	_hits[ip] = mine
	_all.append(now)
	_mutex.unlock()
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return [400, "That isn't a report."]
	var data: Dictionary = parser.data
	var rep: Dictionary = expand_compact(data) if int((data as Dictionary).get("c", 0)) == 1 else sanitize_report(data)
	rep["received"] = Time.get_datetime_string_from_unix_time(int(now))
	rep["from_ip"] = ip
	rep["transport"] = transport
	rep["via"] = server
	if engine != "":
		rep["server_engine"] = engine   # which engine answered (built-in, or the bundled web server)
	var file := _save(rep)
	rep["file"] = file
	_mutex.lock()
	_recent.append(rep)
	if _recent.size() > 20:
		_recent = _recent.slice(_recent.size() - 20)
	_mutex.unlock()
	return [200, "Thanks: the PC has it."]


## Reports received this run, newest last (copies).
func recent(n: int = 10) -> Array:
	_mutex.lock()
	var out := _recent.slice(maxi(0, _recent.size() - n)).duplicate(true)
	_mutex.unlock()
	return out


func count() -> int:
	_mutex.lock()
	var n := _recent.size()
	_mutex.unlock()
	return n


func _save(rep: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := str(rep.received).replace(":", "").replace("-", "").replace("T", "_")
	var ip := str(rep.from_ip).replace(":", "-").replace(".", "-")
	# Two reports in the same second from one phone (POST, then the GET fallback) must not share a file.
	var n := Time.get_ticks_usec() % 1000000
	var path := dir.path_join("%s_%s_%06d.json" % [stamp, ip, n])
	while FileAccess.file_exists(path):
		n = (n + 1) % 1000000
		path = dir.path_join("%s_%s_%06d.json" % [stamp, ip, n])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rep, "\t"))
		f.close()
	var files := Array(DirAccess.get_files_at(dir)).filter(func(x): return str(x).ends_with(".json"))
	files.sort()
	while files.size() > KEEP_FILES:
		DirAccess.remove_absolute(dir.path_join(str(files.pop_front())))
	return path


# --- Cleaning up what a phone sent ----------------------------------------------------------------

## Text without control characters, cut to `n` characters.
static func clean_text(v: Variant, n: int = 300) -> String:
	var s := str(v)
	var out := ""
	for ch in s.substr(0, n):
		var code := ch.unicode_at(0)
		out += ch if code >= 32 and code != 127 else " "
	# (A report never needs an API key: anything shaped like one is taken out before it is stored.)
	return preload("res://scripts/ai/key_format.gd").scrub(out)


static func _clean(v: Variant, depth: int) -> Variant:
	if v is Dictionary:
		if depth > 3:
			return {}
		var out := {}
		for k in (v as Dictionary).keys().slice(0, 60):
			out[clean_text(k, 40)] = _clean(v[k], depth + 1)
		return out
	if v is Array:
		if depth > 3:
			return []
		var arr: Array = []
		for x in (v as Array).slice(0, 60):
			arr.append(_clean(x, depth + 1))
		return arr
	if v is bool or v is int or v is float:
		return v
	return clean_text(v, 300 if depth > 0 else 120)


## Only the keys a report has, each cleaned.
static func sanitize_report(d: Dictionary) -> Dictionary:
	var out := {}
	for k in TOP_KEYS:
		if d.has(k):
			out[k] = _clean(d[k], 1)
	# Only this bounded binary diagnostic bypasses the ordinary short-text cap.
	# Store it as data, never render it or interpret it as a command.
	if d.get("env") is Dictionary and d.env.get("native_exit") is Dictionary:
		var trace := str(d.env.native_exit.get("trace_base64", ""))
		if trace.length() > 0 and trace.length() <= 174764:
			var allowed := RegEx.new()
			allowed.compile("^[A-Za-z0-9+/]*={0,2}$")
			if allowed.search(trace) and trace.length() % 4 == 0:
				out.env.native_exit["trace_base64"] = trace
		# The phone's own summary of a native or Java crash: a stack, one line per frame.
		for k in ["trace_text", "java_stack"]:
			if d.env.native_exit.has(k):
				out.env.native_exit[k] = clean_lines(d.env.native_exit[k], 12000)
	return out


## Multi-line text: the lines kept, every other control character a space, cut to `n` characters.
static func clean_lines(v: Variant, n: int) -> String:
	var lines := PackedStringArray()
	for line in str(v).substr(0, n).split("\n"):
		lines.append(clean_text(line, n))
	return "\n".join(lines)


## The short GET form ({c:1, s:"ping:1:23,...", d, ua, a, w, m, t}) as a normal report.
static func expand_compact(d: Dictionary) -> Dictionary:
	var results: Array = []
	for part in clean_text(d.get("s", ""), 600).split(",", false):
		var bits := part.split(":")
		if bits.size() >= 2:
			results.append({"id": bits[0], "name": bits[0], "ok": bits[1] == "1", "ms": bits[2].to_int() if bits.size() > 2 else 0, "detail": ""})
	var details := clean_text(d.get("d", ""), 700)
	for piece in details.split(" | ", false):
		var id := piece.get_slice("=", 0)
		for r in results:
			if str(r.id) == id:
				r["detail"] = piece.substr(id.length() + 1)
	return {
		"v": 1, "app": "Polox", "page": "test (short form)", "address": clean_text(d.get("a", ""), 80), "results": results,
		"env": {"ua": clean_text(d.get("ua", ""), 160), "webgl2": int(d.get("w", 0)) == 1, "wasm": int(d.get("m", 0)) == 1, "max_texture": int(d.get("t", 0))},
		"hints": [],
	}


## The GET fallback's ?r= value (base64url) back to bytes ([] if it isn't one).
static func decode_get(r: String) -> PackedByteArray:
	if r == "" or r.length() > MAX_GET:
		return PackedByteArray()
	var s := r.replace("-", "+").replace("_", "/")
	while s.length() % 4 != 0:
		s += "="
	return Marshalls.base64_to_raw(s)


# --- Showing reports -------------------------------------------------------------------------------

## One line: "19:42 192.168.1.40 via Polox Ping: 6 OK, 1 problem (Big download: Stalled ...)".
static func summary(rep: Dictionary) -> String:
	var ok := 0
	var bad: PackedStringArray = []
	for r in rep.get("results", []):
		if r is Dictionary:
			if bool(r.get("ok", false)):
				ok += 1
			elif str(r.get("level", "")) != "warn":
				bad.append("%s: %s" % [clean_text(r.get("name", r.get("id", "?")), 40), clean_text(r.get("detail", ""), 90)])
	var when := str(rep.get("received", "")).substr(11, 5)
	var head := "%s from %s (%s, %s)" % [when, str(rep.get("from_ip", "?")), _via_label(str(rep.get("via", ""))), str(rep.get("address", "?"))]
	if bad.is_empty():
		return "%s: all %d checks OK" % [head, ok]
	return "%s: %d OK, %d problem%s: %s" % [head, ok, bad.size(), "" if bad.size() == 1 else "s", "; ".join(bad)]


static func _via_label(v: String) -> String:
	return {"ping": "Polox Ping", "host": "Phone Link", "game": "the game"}.get(v, v)


## A readable, multi-line version for the Doctor and Copy diagnostics.
static func text(rep: Dictionary) -> String:
	var lines := PackedStringArray([summary(rep)])
	var env: Dictionary = rep.get("env", {}) if rep.get("env") is Dictionary else {}
	if env.has("ua"):
		lines.append("  browser: " + clean_text(env.ua, 200))
	if not env.is_empty():
		lines.append("  secure=%s wasm=%s webgl2=%s max_texture=%s storage=%s indexeddb=%s screen=%s speed=%s MB/s" % [
			str(env.get("secure", "?")), str(env.get("wasm", "?")), str(env.get("webgl2", "?")), str(env.get("max_texture", "?")),
			str(env.get("local_storage", "?")), str(env.get("indexeddb_works", "?")), str(env.get("screen", "?")), str(env.get("big_mbps", "?"))])
	for r in rep.get("results", []):
		if r is Dictionary:
			lines.append("  %s %s: %s%s" % ["OK  " if bool(r.get("ok", false)) else ("WARN" if str(r.get("level", "")) == "warn" else "FAIL"), clean_text(r.get("name", r.get("id", "?")), 40), clean_text(r.get("detail", ""), 300), (" (%d ms)" % int(r.get("ms", 0))) if int(r.get("ms", 0)) > 0 else ""])
	for h in rep.get("hints", []):
		lines.append("  tip: " + clean_text(h, 300))
	var log_lines: Array = rep.get("log", []) if rep.get("log") is Array else []
	for l in log_lines.slice(-30):
		lines.append("  log: " + clean_text(l, 300))
	var exit: Dictionary = env.get("native_exit", {}) if env.get("native_exit") is Dictionary else {}
	for k in ["trace_text", "java_stack"]:
		for l in str(exit.get(k, "")).split("\n", false):
			lines.append("  stack: " + clean_text(l, 300))
	return "\n".join(lines)


## The newest reports saved on disk (any Polox window or Polox Ping wrote them), newest first.
static func load_saved(save_root: String, n: int = 5) -> Array:
	var d := save_root.path_join("phone_reports")
	var out: Array = []
	if not DirAccess.dir_exists_absolute(d):
		return out
	var files := Array(DirAccess.get_files_at(d)).filter(func(x): return str(x).ends_with(".json"))
	files.sort()
	files.reverse()
	for f in files.slice(0, n):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(d.path_join(str(f))))
		if data is Dictionary:
			out.append(data)
	return out
