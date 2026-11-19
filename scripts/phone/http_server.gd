extends Node
## A small, sturdy HTTP/1.1 server (Phone Link's engine), on its own thread.
##
## - Non-blocking accept and a state machine per connection, up to 32 at once
##   (browsers open several in parallel and keep idle "speculative" sockets).
## - Header timeout (10 s to send a request), idle timeout (30 s without a byte
##   either way), so stuck or half-open sockets are dropped.
## - Static files streamed from disk in 64 KB chunks with Content-Length,
##   ETag + 304, Cache-Control: no-cache (updates arrive, unchanged big files
##   aren't downloaded again), HEAD, OPTIONS, single Range requests (206/416),
##   and a pre-compressed `<file>.gz` when the browser accepts gzip.
## - A source allow-list (NetRules scopes): public addresses never get in.
## - Pages (`page_handler`) run on this thread and must be pure functions;
##   /api/ requests go to `api_handler` on the main thread through a job queue.
##   The thread never touches the scene tree.
## - Every request is isolated: a script error in a handler becomes a 500 for
##   that request, never a dead server. A watchdog restarts the thread if it dies.
## - A request log (time, address, method, path, status, bytes, ms; never
##   headers, bodies or tokens), in memory and in a small rotating text file.
## One request per connection (Connection: close): simple and robust.
##
## Update 5, "boringly correct before clever": every answer is HTTP/1.1 with a
## Content-Length and Connection: close, never chunked; the whole request is
## read before answering, and after answering whatever the phone still sends is
## drained before closing (closing on unread data makes Windows reset the
## connection, and the phone shows "connection reset"). ETag/304, gzip and Range
## are off unless switched on (allow_etag / allow_gzip / allow_range). The game
## lives at versioned addresses /game/<build id>/<file>, so a phone can never
## run a stale cached copy: other ids get "410 Gone" with a link to the launcher.
## Nothing redirects (some phones cache redirects for good).

const HttpUtil := preload("res://scripts/phone/http_util.gd")
const NetRules := preload("res://scripts/phone/net_rules.gd")

const MAX_CONNECTIONS := 32
const HEADER_TIMEOUT_MS := 10000
const IDLE_TIMEOUT_MS := 30000
const JOB_TIMEOUT_MS := 120000
const CHUNK := 64 * 1024
const LOG_KEEP := 300
const LOG_FILE_MAX := 256 * 1024
const LOG_FILES := 3
const LINGER_MS := 1500        # at most this long draining after the answer
const LINGER_QUIET_MS := 60    # closed once nothing more has arrived for this long
const ACCEPTS_PER_PASS := 64   # new connections taken in one pass, so a flood can't hold the loop
const MAX_RESTARTS := 5        # socket-thread restarts in a row before the server gives up
const RESTART_WAIT_MS := 500   # between restarts: this, times how many there were in a row...
const RESTART_WAIT_MAX_MS := 5000    # ...up to this
const RESTART_CALM_MS := 30000       # running this long after a restart: the count starts again

## The socket thread kept stopping and the server switched itself off (see _revive).
signal gave_up

var static_dir := ""
var static_exts: PackedStringArray = ["html", "js", "wasm", "pck", "png", "ico", "svg", "webmanifest", "json", "css", "txt"]
var source_scope := "home"
## (req: Dictionary) -> PackedByteArray, or an empty array when it isn't a page. Runs on the server thread.
var page_handler: Callable = Callable()
## (req: Dictionary, ip: String) -> PackedByteArray (may await). Runs on the main thread.
var api_handler: Callable = Callable()
var api_prefix := "/api/"
## (req: Dictionary, ip: String) -> String: "" lets the request in, anything else refuses it (403, that text).
## Runs on the server thread before anything else; must be a pure function.
var guard: Callable = Callable()
var log_path := ""
## Tests: pretend every client comes from this address.
var debug_peer_override := ""
## Tests: a path whose handling deliberately hits a script error.
var debug_fail_path := ""

## Limits (tests shorten the timeouts). Set before start().
var max_connections := MAX_CONNECTIONS
var header_timeout_ms := HEADER_TIMEOUT_MS
var idle_timeout_ms := IDLE_TIMEOUT_MS
var job_timeout_ms := JOB_TIMEOUT_MS
var log_file_max := LOG_FILE_MAX
var linger_ms := LINGER_MS
## Optional extras, OFF until the connection ladder passes on the real phone.
var allow_etag := false
var allow_gzip := false
var allow_range := false
## Plan B: the bundled web server (Caddy) in front sends this secret; only then is its
## X-Forwarded-For (the phone's address) believed.
var proxy_secret := ""

var running := false
var port := 0
var bind_address := ""

var _server: TCPServer
var _thread: Thread
var _quit := false
var _mutex := Mutex.new()
var _jobs: Array = []          # waiting for the main thread
var _log: Array = []           # recent requests (newest last)
var _contacts: Array = []      # every TCP connection, even ones that sent nothing (newest last)
var _contact_total := 0
var _log_lines: PackedStringArray = []   # waiting to be written to the log file
var _open := 0
var _served := 0
var _restarts := 0
var _restart_run := 0           # restarts in a row (see _revive)
var _restart_at := 0            # when the last one was (ticks, ms)
var _thread_died := false       # the socket thread ended on its own and waits to be restarted
var _game_prefix := ""          # "/game/<build id>/" (set from the main thread, read by the socket thread)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # a paused game still answers the phone


## Where the game files live: "/game/<build id>/" ("" = no Web build yet).
func set_game_prefix(prefix: String) -> void:
	_mutex.lock()
	_game_prefix = prefix
	_mutex.unlock()


func game_prefix() -> String:
	_mutex.lock()
	var p := _game_prefix
	_mutex.unlock()
	return p


## Starts listening. Returns "" or a plain-language error.
func start(listen_port: int, bind: String = "*") -> String:
	if running:
		return ""
	_server = TCPServer.new()
	var err := _server.listen(listen_port, bind)
	if err != OK:
		_server = null
		return "Port %d is already in use (is another copy of Polox running?)." % listen_port if err == ERR_ALREADY_IN_USE or err == ERR_CANT_CREATE else "Couldn't listen on port %d (error %d)." % [listen_port, err]
	port = _server.get_local_port() if listen_port == 0 else listen_port
	bind_address = bind
	_quit = false
	_thread_died = false
	_restart_run = 0
	_start_thread()
	running = true
	return ""


func stop() -> void:
	if not running:
		return
	_quit = true
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_thread_died = false
	if _server:
		_server.stop()
	_server = null
	running = false
	_mutex.lock()
	for j in _jobs:
		j["response"] = HttpUtil.error_response(503, "Phone Link is switching off")
		j["done"] = true
	_jobs.clear()
	_mutex.unlock()
	_flush_log_file()


func _exit_tree() -> void:
	stop()


func _start_thread() -> void:
	_thread = Thread.new()
	_thread.start(_loop)


## Main thread: hands queued /api/ jobs to the handler, writes the log file,
## and restarts the socket thread if it ever died.
func _process(_delta: float) -> void:
	if not running:
		return
	_mutex.lock()
	var jobs := _jobs.duplicate()
	_jobs.clear()
	_mutex.unlock()
	for j in jobs:
		_run_job(j)
	_flush_log_file()
	if _thread and not _thread.is_alive() and not _quit:
		_thread.wait_to_finish()
		_thread = null
		_thread_died = true
	if _thread_died and not _quit:
		_revive()


## The socket thread ended on its own (it never should): it is started again, at once the first time.
## One that keeps ending is not restarted every frame for good: a wait between tries, longer each
## time, and after MAX_RESTARTS in a row the server stops and says so (`gave_up`).
func _revive() -> void:
	var now := Time.get_ticks_msec()
	if _restart_run > 0 and now - _restart_at > RESTART_CALM_MS:
		_restart_run = 0   # it had run fine for a while: a new problem, not the same one again
	if _restart_run >= MAX_RESTARTS:
		_thread_died = false
		push_warning("Phone Link: the socket thread stopped %d times in a row; the server is off." % _restart_run)
		stop()
		gave_up.emit()
		return
	if _restart_run > 0 and now < _restart_at + mini(RESTART_WAIT_MS * _restart_run, RESTART_WAIT_MAX_MS):
		return   # not yet: the wait after the last try
	_thread_died = false
	_restarts += 1
	_restart_run += 1
	_restart_at = now
	push_warning("Phone Link: the socket thread stopped; restarting it.")
	_start_thread()


func _run_job(job: Dictionary) -> void:
	var resp: Variant = null
	if api_handler.is_valid():
		resp = await api_handler.call(job.req, str(job.ip))
	if not resp is PackedByteArray or (resp as PackedByteArray).is_empty():
		resp = HttpUtil.error_response(500, "internal error (the rest of Polox is fine)")
	_mutex.lock()
	job["response"] = resp
	job["done"] = true
	_mutex.unlock()


# --- Stats and log (any thread) ---------------------------------------------------------------

func open_connections() -> int:
	_mutex.lock()
	var n := _open
	_mutex.unlock()
	return n


func served_count() -> int:
	_mutex.lock()
	var n := _served
	_mutex.unlock()
	return n


func thread_restarts() -> int:
	return _restarts


## The last `n` connections, oldest first: {t, ip, outcome, path, status}. Every
## connection counts, even one that sent nothing or spoke HTTPS to this port, so
## "no device ever reached the PC" and "reached it, then failed" look different.
func contacts(n: int = 50) -> Array:
	_mutex.lock()
	var out := _contacts.slice(maxi(0, _contacts.size() - n)).duplicate(true)
	_mutex.unlock()
	return out


func contact_total() -> int:
	_mutex.lock()
	var n := _contact_total
	_mutex.unlock()
	return n


func _contact(c: Dictionary) -> void:
	var outcome := str(c.get("outcome", ""))
	if outcome == "":
		if c.has("method"):
			outcome = "request"
		elif (c.get("buf", PackedByteArray()) as PackedByteArray).is_empty():
			outcome = "nothing"
		else:
			outcome = "bad"
	var e := {"t": Time.get_unix_time_from_system(), "ip": str(c.ip), "outcome": outcome, "path": str(c.get("logpath", "")), "status": int(c.get("status", 0)), "bytes": int(c.get("bytes_out", 0))}
	_mutex.lock()
	_contacts.append(e)
	if _contacts.size() > LOG_KEEP:
		_contacts = _contacts.slice(_contacts.size() - LOG_KEEP)
	_contact_total += 1
	if outcome in ["nothing", "https", "bad"] and log_path != "":
		var why: String = {"nothing": "(connected, sent no request)", "https": "(HTTPS sent to this HTTP port)", "bad": "(not a web request)"}[outcome]
		_log_lines.append("%s %s - %s 0 0B %dms" % [Time.get_datetime_string_from_unix_time(int(e.t)), e.ip, why, Time.get_ticks_msec() - int(c.t0)])
	_mutex.unlock()


## The last `n` requests, oldest first (copies).
func recent(n: int = 50) -> Array:
	_mutex.lock()
	var out := _log.slice(maxi(0, _log.size() - n)).duplicate(true)
	_mutex.unlock()
	return out


func _record(c: Dictionary) -> void:
	var e := {
		"t": Time.get_unix_time_from_system(), "ip": str(c.ip), "via": str(c.get("via", "")),
		"method": str(c.get("method", "-")), "path": str(c.get("logpath", "-")), "status": int(c.get("status", 0)),
		"bytes": int(c.get("bytes_out", 0)), "ms": Time.get_ticks_msec() - int(c.t0), "host": str(c.get("host", "")),
	}
	var line := "%s %s%s %s %s %d %dB %dms" % [Time.get_datetime_string_from_unix_time(int(e.t)), e.ip, (" via " + e.via) if e.via != "" else "", e.method, e.path, e.status, e.bytes, e.ms]
	_mutex.lock()
	_log.append(e)
	if _log.size() > LOG_KEEP:
		_log = _log.slice(_log.size() - LOG_KEEP)
	_served += 1
	if log_path != "":
		_log_lines.append(line)
	_mutex.unlock()


func _flush_log_file() -> void:
	_mutex.lock()
	var lines := _log_lines
	_log_lines = PackedStringArray()
	_mutex.unlock()
	if lines.is_empty() or log_path == "":
		return
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var rf := FileAccess.open(log_path, FileAccess.READ) if FileAccess.file_exists(log_path) else null
	var log_len := rf.get_length() if rf != null else 0
	if rf != null:
		rf.close()
	if log_len > log_file_max:
		for i in range(LOG_FILES - 1, 0, -1):
			var older := "%s.%d" % [log_path, i]
			var newer := log_path if i == 1 else "%s.%d" % [log_path, i - 1]
			if FileAccess.file_exists(older):
				DirAccess.remove_absolute(older)
			if FileAccess.file_exists(newer):
				DirAccess.rename_absolute(newer, older)
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	for l in lines:
		f.store_line(l)
	f.close()


# --- The socket thread ---------------------------------------------------------------------------

func _loop() -> void:
	var conns: Array = []
	while not _quit:
		var moved := false
		var accepted := 0
		# (At most ACCEPTS_PER_PASS at a time: under a flood the connections already open still get
		# their turn below, and switching Phone Link off is seen within one pass.)
		while _server and _server.is_connection_available() and accepted < ACCEPTS_PER_PASS and not _quit:
			var peer := _server.take_connection()
			if peer == null:
				break
			accepted += 1
			moved = true
			var raw_ip := debug_peer_override if debug_peer_override != "" else peer.get_connected_host()
			var c := {"peer": peer, "ip": NetRules.normalize_ip(raw_ip), "buf": PackedByteArray(), "t0": Time.get_ticks_msec(), "last": Time.get_ticks_msec(), "state": "read", "bytes_out": 0}
			# Refusals still read the request first: closing a socket with unread data
			# makes Windows send a reset that wipes the answer before the client sees it.
			if conns.size() >= max_connections + 16:
				peer.disconnect_from_host()   # flooded: drop without a word
				continue
			if conns.size() >= max_connections:
				c["refuse"] = [503, "busy, try again"]
			elif not NetRules.source_allowed(str(c.ip), source_scope):
				c["refuse"] = [403, "This address isn't allowed to reach Polox."]
			conns.append(c)
		for c in conns:
			var r: Variant = _step(c)
			if typeof(r) != TYPE_BOOL:
				# The step hit a script error: answer 500 if nothing was sent yet, then drop it.
				_fail(c)
			elif r:
				moved = true
		conns = conns.filter(func(c): return c.state != "done")
		_mutex.lock()
		_open = conns.size()
		_mutex.unlock()
		OS.delay_msec(1 if moved else 4)
	for c in conns:
		_close(c)


func _fail(c: Dictionary) -> void:
	if str(c.state) != "write" or int(c.get("bytes_out", 0)) == 0:
		c["status"] = 500
		var bytes := HttpUtil.error_response(500, "internal error (the rest of Polox is fine)")
		(c.peer as StreamPeerTCP).put_partial_data(bytes)
	_close(c)


## Advances one connection. Returns true if bytes moved.
func _step(c: Dictionary) -> bool:
	var peer: StreamPeerTCP = c.peer
	peer.poll()
	var st := peer.get_status()
	if st != StreamPeerTCP.STATUS_CONNECTED:
		if str(c.state) == "read" and not (c.buf as PackedByteArray).is_empty() and not c.has("method"):
			c["outcome"] = "cut"
			c["logpath"] = "(hung up before the request was complete)"
		_close(c, true)
		return false
	var now := Time.get_ticks_msec()
	match str(c.state):
		"read":
			var n := peer.get_available_bytes()
			if n > 0:
				var got: Array = peer.get_partial_data(mini(n, CHUNK))
				if got[0] == OK:
					var buf: PackedByteArray = c.buf
					c.erase("buf")   # one owner, so appending doesn't copy the whole buffer
					buf.append_array(got[1])
					c["buf"] = buf   # packed arrays are values: store the grown one back
					c["last"] = now
					if buf[0] == 0x16:   # a TLS ClientHello: the browser tried https:// on this http:// port
						c["outcome"] = "https"
						_close(c, false)
						return true
					var req := HttpUtil.parse(buf)
					if req.has("error"):
						c["logpath"] = "(bad request)"
						_reply(c, HttpUtil.error_response(int(req.error), "bad request"), int(req.error))
					elif not req.is_empty() and c.has("refuse"):
						c["method"] = str(req.method)
						c["logpath"] = "(refused: %s) %s" % ["address not allowed" if int(c.refuse[0]) == 403 else "too many connections", str(req.path)]
						_reply(c, HttpUtil.error_response(int(c.refuse[0]), str(c.refuse[1])), int(c.refuse[0]))
					elif not req.is_empty():
						c["state"] = "dispatching"
						_dispatch(c, req)
						if str(c.state) == "dispatching":
							_fail(c)   # the handler stopped half-way (a script error): 500, not a retry loop
					return true
			if not bool(c.get("headers_done", false)):
				if HttpUtil.header_end(c.buf) >= 0:
					c["headers_done"] = true
				elif now - int(c.t0) > header_timeout_ms:
					c["logpath"] = "(no request sent in time)"
					c["status"] = 408
					_close(c, true)
					return false
			if now - int(c.last) > idle_timeout_ms:
				c["logpath"] = "(stalled while sending)"
				c["status"] = 408
				_close(c, true)
		"job":
			_mutex.lock()
			var job: Dictionary = c.job
			var done := bool(job.get("done", false))
			_mutex.unlock()
			if done:
				var resp: PackedByteArray = job.response
				_reply(c, resp, _status_of(resp))
				return true
			if now - int(c.last) > (610000 if str(job.req.get("path", "")) == "/api/home-helper" else job_timeout_ms):
				_reply(c, HttpUtil.error_response(503, "timed out"), 503)
		"write":
			return _write_some(c, now)
		"linger":
			# Drain what the phone still sends (closing on unread data resets the connection),
			# until it hangs up or a moment passes.
			var left := peer.get_available_bytes()
			if left > 0:
				peer.get_partial_data(mini(left, CHUNK))
				c["quiet_at"] = now
			if now - int(c.get("quiet_at", c.linger_at)) > LINGER_QUIET_MS or now - int(c.linger_at) > linger_ms:
				_close(c, true)
	return false


func _dispatch(c: Dictionary, req: Dictionary) -> void:
	req["ip"] = str(c.ip)   # pages may tell this PC's own browser from a phone
	var path := str(req.path)
	var method := str(req.method)
	c["method"] = method
	c["host"] = str(req.headers.get("host", "")).substr(0, 120)
	c["logpath"] = path + (("?path=" + str(req.query.path)) if req.query.has("path") else "")
	# The bundled web server (Plan B) proxies from 127.0.0.1 with the secret; it already refused strangers.
	if proxy_secret != "" and NetRules.kind(str(c.ip)) == "loopback" and str(req.headers.get("x-polox-proxy", "")) == proxy_secret:
		var phone := NetRules.normalize_ip(str(req.headers.get("x-forwarded-for", "")).get_slice(",", 0).strip_edges())
		if NetRules.kind(phone) != "invalid":
			c["ip"] = phone
			c["via"] = "bundled " + phone
			req["ip"] = phone
		req["proxied"] = true
	# Tailscale Serve proxies from 127.0.0.1 and says who the phone is.
	elif NetRules.kind(str(c.ip)) == "loopback" and req.headers.has("x-forwarded-for"):
		c["via"] = "tailscale-serve " + str(req.headers["x-forwarded-for"]).get_slice(",", 0).strip_edges().substr(0, 60)
	if guard.is_valid():
		var why: Variant = guard.call(req, str(c.ip))
		if why is String and why != "":
			_reply(c, HttpUtil.error_response(403, why), 403)
			return
	if debug_fail_path != "" and path == debug_fail_path:
		var nothing: Object = null
		nothing.call("crash")   # deliberate script error (tests prove it only costs this request)
	if method == "OPTIONS":
		var allow := "GET, HEAD, POST, PUT, DELETE, OPTIONS" if path.begins_with(api_prefix) else "GET, HEAD, OPTIONS"
		_reply(c, HttpUtil.response(204, PackedByteArray(), "text/plain", {"Allow": allow}), 204)
		return
	if path.begins_with(api_prefix):
		var job := {"req": req, "ip": str(c.ip), "done": false, "response": PackedByteArray()}
		c["job"] = job
		c["state"] = "job"
		c["last"] = Time.get_ticks_msec()
		_mutex.lock()
		_jobs.append(job)
		_mutex.unlock()
		return
	if not method in ["GET", "HEAD"]:
		_reply(c, HttpUtil.error_response(405, "method not allowed"), 405)
		return
	if page_handler.is_valid():
		var page: Variant = page_handler.call(req)
		if page is PackedByteArray and not (page as PackedByteArray).is_empty():
			_reply(c, _head_only(page) if method == "HEAD" else page, _status_of(page))
			return
		if page is Dictionary and (page as Dictionary).has("bytes"):   # {bytes, status[, blob]}: the blob streams after the header
			_reply(c, page.bytes, int(page.get("status", _status_of(page.bytes))))
			if page.has("blob") and method != "HEAD":
				c["blob"] = page.blob
				c["blob_pos"] = 0
			return
	_serve_file(c, req)


func _serve_file(c: Dictionary, req: Dictionary) -> void:
	var path := str(req.path)
	var prefix := game_prefix()
	var name := ""
	if path.begins_with("/game/"):
		var rest := path.substr(6)
		var id := rest.get_slice("/", 0)
		name = rest.substr(id.length() + 1)
		if prefix == "" or "/game/%s/" % id != prefix:
			_reply(c, HttpUtil.response(410, gone_page().to_utf8_buffer(), "text/html; charset=utf-8"), 410)
			return
	else:
		name = "index.html" if path == "/" else path.substr(1)
		if prefix != "" and name.get_extension().to_lower() == "html":
			_reply(c, HttpUtil.response(410, gone_page().to_utf8_buffer(), "text/html; charset=utf-8"), 410)
			return
		if prefix != "":   # game files only live under /game/<build id>/ (no stale copies, no redirects)
			_reply(c, HttpUtil.error_response(404, "not found (the game lives at %s)" % prefix), 404)
			return
	# Only plain file names from the Web build: no folders, no listing, no dot-files.
	if name == "" or name.contains("/") or not HttpUtil.safe_rel_path(name) or not name.get_extension().to_lower() in static_exts or static_dir == "":
		_reply(c, HttpUtil.error_response(404, "not found"), 404)
		return
	var full := static_dir.path_join(name)
	if not FileAccess.file_exists(full):
		_reply(c, HttpUtil.error_response(404, "not found"), 404)
		return
	var size := FileAccess.get_size(full)
	var mtime := FileAccess.get_modified_time(full)
	var etag := "\"%x-%x\"" % [size, mtime]
	var headers := {"Cache-Control": "no-store", "Accept-Ranges": "bytes" if allow_range else "none", "X-Polox-Size": str(size)}   # the real size, even when gzipped (the start-up check compares it)
	var range_h := str(req.headers.get("range", "")) if allow_range else ""
	var send_path := full
	var send_size := size
	# A pre-compressed copy for browsers that take gzip (not for partial requests).
	if allow_gzip and range_h == "" and str(req.headers.get("accept-encoding", "")).to_lower().contains("gzip") and FileAccess.file_exists(full + ".gz") and FileAccess.get_modified_time(full + ".gz") >= mtime:
		send_path = full + ".gz"
		send_size = FileAccess.get_size(send_path)
		etag = "\"%x-%x-gz\"" % [size, mtime]
		headers["Content-Encoding"] = "gzip"
		headers["Vary"] = "Accept-Encoding"
	if allow_etag:
		headers["ETag"] = etag
		headers["Cache-Control"] = "no-cache"
	var inm := str(req.headers.get("if-none-match", "")) if allow_etag else ""
	if inm != "" and (inm == etag or inm == "*" or etag in inm.split(",")):
		var h304 := headers.duplicate()
		h304.erase("Content-Encoding")
		_reply(c, _head_bytes(304, "", 0, h304), 304)
		return
	var start := 0
	var length := send_size
	var status := 200
	if range_h != "":
		var r := parse_range(range_h, size)
		if r.is_empty():
			_reply(c, HttpUtil.response(416, PackedByteArray(), "text/plain", {"Content-Range": "bytes */%d" % size}), 416)
			return
		start = int(r.start)
		length = int(r.end) - start + 1
		status = 206
		headers["Content-Range"] = "bytes %d-%d/%d" % [start, int(r.end), size]
	var head := _head_bytes(status, HttpUtil.mime_for(name), length, headers)
	if str(req.method) == "HEAD":
		_reply(c, head, status)
		return
	var f := FileAccess.open(send_path, FileAccess.READ)
	if f == null:
		_reply(c, HttpUtil.error_response(404, "not found"), 404)
		return
	f.seek(start)
	c["file"] = f
	c["file_left"] = length
	_reply(c, head, status)


## An old or unknown game address (a cached page from an earlier build, or a bookmark):
## no redirect, just a link back to the launcher, which knows the current address.
static func gone_page() -> String:
	return "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Polox: open the launcher</title><style>body{margin:0;padding:24px 18px;font:22px/1.4 system-ui,sans-serif;background:#fff;color:#111}a{display:inline-block;margin-top:16px;padding:16px 20px;background:#1565c0;color:#fff;border-radius:12px;text-decoration:none;font-weight:700}</style></head><body><h1>This game version is gone</h1><p>Polox on your PC has a newer phone version now (or this address is from an old bookmark). Your worlds are safe.</p><a href=\"/\">Open the Polox Launcher</a></body></html>"


## "bytes=a-b", "bytes=a-" or "bytes=-n" for a file of `size` bytes: {start, end}, or {} if unusable.
static func parse_range(h: String, size: int) -> Dictionary:
	var v := h.strip_edges().to_lower()
	if not v.begins_with("bytes=") or v.contains(",") or size <= 0:
		return {}
	var spec := v.substr(6).strip_edges()
	var dash := spec.find("-")
	if dash < 0:
		return {}
	var a := spec.substr(0, dash).strip_edges()
	var b := spec.substr(dash + 1).strip_edges()
	if a == "":
		if not b.is_valid_int() or b.to_int() <= 0:
			return {}
		return {"start": maxi(0, size - b.to_int()), "end": size - 1}
	if not a.is_valid_int() or a.to_int() < 0 or a.to_int() >= size:
		return {}
	var e := size - 1
	if b != "":
		if not b.is_valid_int() or b.to_int() < a.to_int():
			return {}
		e = mini(b.to_int(), size - 1)
	return {"start": a.to_int(), "end": e}


static func _head_bytes(code: int, content_type: String, length: int, extra: Dictionary) -> PackedByteArray:
	var head := "HTTP/1.1 %d %s\r\n" % [code, HttpUtil.REASONS.get(code, "OK")]
	var h := {"Connection": "close", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY"}
	if content_type != "":
		h["Content-Type"] = content_type
	if code != 304:
		h["Content-Length"] = str(length)
	for k in extra:
		h[k] = extra[k]
	for k in h:
		head += "%s: %s\r\n" % [k, h[k]]
	return (head + "\r\n").to_utf8_buffer()


## A full response cut down to its headers (HEAD).
static func _head_only(resp: PackedByteArray) -> PackedByteArray:
	var end := HttpUtil.header_end(resp)
	return resp.slice(0, end + 4) if end >= 0 else resp


static func _status_of(resp: PackedByteArray) -> int:
	var first := resp.slice(0, mini(resp.size(), 16)).get_string_from_ascii()
	return first.get_slice(" ", 1).to_int()


func _reply(c: Dictionary, bytes: PackedByteArray, status: int) -> void:
	c["out"] = bytes
	c["sent"] = 0
	c["status"] = status
	c["state"] = "write"
	c["last"] = Time.get_ticks_msec()


func _write_some(c: Dictionary, now: int) -> bool:
	var peer: StreamPeerTCP = c.peer
	var out: PackedByteArray = c.out
	if int(c.sent) >= out.size():
		if c.has("blob"):
			var blob: PackedByteArray = c.blob
			var pos := int(c.blob_pos)
			if pos >= blob.size():
				c.erase("blob")
				_linger(c)
				return false
			c["out"] = blob.slice(pos, mini(pos + CHUNK, blob.size()))
			c["blob_pos"] = pos + (c.out as PackedByteArray).size()
			c["sent"] = 0
			out = c.out
			var rb: Array = peer.put_partial_data(out)
			if rb[0] != OK:
				_close(c, true)
				return false
			c["sent"] = int(rb[1])
			c["bytes_out"] = int(c.get("bytes_out", 0)) + int(rb[1])
			c["last"] = now
			return true
		var f: FileAccess = c.get("file")
		var left := int(c.get("file_left", 0))
		if f == null or left <= 0:
			_linger(c)
			return false
		c["out"] = f.get_buffer(mini(CHUNK, left))
		c["file_left"] = left - (c.out as PackedByteArray).size()
		c["sent"] = 0
		out = c.out
		if out.is_empty():
			_close(c, true)
			return false
	var r: Array = peer.put_partial_data(out.slice(int(c.sent), mini(out.size(), int(c.sent) + CHUNK)))
	if r[0] != OK:
		_close(c, true)
		return false
	var n := int(r[1])
	c["sent"] = int(c.sent) + n
	c["bytes_out"] = int(c.get("bytes_out", 0)) + n
	if n > 0:
		c["last"] = now
		return true
	if now - int(c.last) > idle_timeout_ms:
		c["logpath"] = str(c.get("logpath", "-")) + " (client stopped reading)"
		_close(c, true)
	return false


## Everything is sent: drain and wait for the phone to hang up before closing.
func _linger(c: Dictionary) -> void:
	var f: FileAccess = c.get("file")
	if f:
		f.close()
		c.erase("file")
	c["state"] = "linger"
	c["linger_at"] = Time.get_ticks_msec()


func _close(c: Dictionary, log_it: bool = true) -> void:
	if str(c.state) == "done":
		return
	var f: FileAccess = c.get("file")
	if f:
		f.close()
		c.erase("file")
	(c.peer as StreamPeerTCP).disconnect_from_host()
	c["state"] = "done"
	c.erase("blob")
	_contact(c)
	if log_it and (c.has("status") or c.has("method")):
		_record(c)
