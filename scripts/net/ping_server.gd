extends Node
## Polox Ping: the smallest possible web server, separate from Phone Link, to
## prove a phone can reach this PC at all. No pairing, no game files, no game.
## Listens on 0.0.0.0 (IPv4, every adapter) on 8765, 8080 and 8888 at once
## (whichever are free: some networks and browsers treat ports differently)
## and answers any request: /ping, the Connection Test (/test, /test/big, ...),
## reports (/api/report), and a plain "Polox OK" page for anything else.
##
## Every TCP contact is recorded, even one that sends nothing (the phone got
## through but the browser gave up) or that speaks HTTPS to this HTTP port, so
## "nobody ever reached the PC" and "reached it, then failed" look different.
##
## Plain and careful: one thread, one request per connection, the whole request
## (headers and body, however it's split up) is read before answering, every
## answer has Content-Length and Connection: close, big answers go out in
## chunks, and after answering it drains whatever the phone still sends before
## closing (closing on unread data makes Windows send a reset that can wipe the
## answer). Never touches the scene tree from its thread.

const HttpUtil := preload("res://scripts/phone/http_util.gd")
const NetRules := preload("res://scripts/phone/net_rules.gd")
const DiagRoutes := preload("res://scripts/net/diag_routes.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")

const PORTS: Array = [8765, 8080, 8888]
const CHUNK := 64 * 1024
const HEADER_TIMEOUT_MS := 10000
const IDLE_TIMEOUT_MS := 20000
const LINGER_MS := 1500
const MAX_CONNECTIONS := 48
const REFUSALS_HELD := 16         # connections past the limit still told "busy"; any more are dropped
const ACCEPTS_PER_PASS := 64      # new connections taken from one port in one pass of the loop
const KEEP_CONTACTS := 300

var sink: ReportSink
var ports_open: Array = []           # ports actually listening
var ports_failed: Dictionary = {}    # port -> why
var bind_address := "0.0.0.0"
var server_name := "Polox Ping"
var log_path := ""
var running := false

var _servers: Array = []             # [port, TCPServer]
var _thread: Thread
var _quit := false
var _mutex := Mutex.new()
var _contacts: Array = []            # newest last
var _contact_total := 0
var _log_lines: PackedStringArray = []
var _ctx := {}


## Starts listening on whichever of `ports` are free. Returns "" or why nothing could listen.
func start(save_root: String, ports: Array = PORTS, bind: String = "0.0.0.0") -> String:
	if running:
		return ""
	sink = ReportSink.new(save_root)
	log_path = save_root.path_join("phone").path_join("ping.log")
	bind_address = bind
	ports_open.clear()
	ports_failed.clear()
	_servers.clear()
	for p in ports:
		var s := TCPServer.new()
		var requested := int(p)
		var err := s.listen(requested, bind)
		if err == OK:
			var bound := s.get_local_port() if requested == 0 else requested
			_servers.append([bound, s])
			ports_open.append(bound)
		else:
			ports_failed[requested] = "in use by another program" if err == ERR_ALREADY_IN_USE or err == ERR_CANT_CREATE else "error %d" % err
	if _servers.is_empty():
		return "Polox Ping couldn't listen on any of ports %s (%s)." % [", ".join(PackedStringArray(ports.map(func(x): return str(x)))), ", ".join(PackedStringArray(ports_failed.values()))]
	_ctx = {"server": "ping", "server_name": server_name, "engine": "Polox Ping", "pc": pc_name(), "build_id": "", "port": int(ports_open[0])}
	_quit = false
	_thread = Thread.new()
	_thread.start(_loop)
	running = true
	_log("started on %s ports %s" % [bind, ", ".join(PackedStringArray(ports_open.map(func(x): return str(x))))])
	return ""


func stop() -> void:
	if not running:
		return
	_quit = true
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	for s in _servers:
		(s[1] as TCPServer).stop()
	_servers.clear()
	running = false
	_log("stopped")
	_flush_log()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	_flush_log()


static func pc_name() -> String:
	var n := OS.get_environment("COMPUTERNAME")
	return n if n != "" else "your PC"


# --- What the window shows (main thread) ---------------------------------------------------------

## The last `n` contacts, oldest first: {t, ip, port, outcome, method, path, status, bytes, ms}.
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


## Contacts from somewhere other than this PC (its own checks don't count).
func phone_contacts(n: int = 50) -> Array:
	var own := NetRules.own_addresses()
	return contacts(KEEP_CONTACTS).filter(func(c): return not own.has(str(c.ip)) and NetRules.kind(str(c.ip)) != "loopback").slice(-n)


static func outcome_text(c: Dictionary) -> String:
	match str(c.get("outcome", "")):
		"request":
			return "%s %s -> %d (%s)" % [str(c.method), str(c.path), int(c.status), _size(int(c.bytes))]
		"nothing":
			return "connected, but sent no request (the browser gave up, or something on the way cut it)"
		"https":
			return "spoke HTTPS to this HTTP port: type the address with http:// in front"
		"bad":
			return "sent something that isn't a web request"
		"refused":
			return "refused: not a home-network or Tailscale address"
		"busy":
			return "refused: too many connections at once"
		"cut":
			return "%s %s: the phone hung up after %s" % [str(c.method), str(c.path), _size(int(c.bytes))]
	return str(c.get("outcome", "?"))


static func _size(b: int) -> String:
	return "%d B" % b if b < 10240 else ("%.1f KB" % (b / 1024.0) if b < 1048576 else "%.1f MB" % (b / 1048576.0))


# --- The socket thread -------------------------------------------------------------------------------

func _loop() -> void:
	var conns: Array = []
	while not _quit:
		var moved := false
		for s in _servers:
			var srv: TCPServer = s[1]
			var accepted := 0
			# (At most ACCEPTS_PER_PASS at a time, so the connections already open still get their turn
			# and stop() is seen within one pass, however many arrive.)
			while srv.is_connection_available() and accepted < ACCEPTS_PER_PASS and not _quit:
				var peer := srv.take_connection()
				if peer == null:
					break
				accepted += 1
				moved = true
				if conns.size() >= MAX_CONNECTIONS + REFUSALS_HELD:
					peer.disconnect_from_host()   # flooded: dropped without a word, the list stays bounded
					continue
				var ip := NetRules.normalize_ip(peer.get_connected_host())
				var c := {"peer": peer, "ip": ip, "port": int(s[0]), "buf": PackedByteArray(), "t0": Time.get_ticks_msec(), "last": Time.get_ticks_msec(), "state": "read", "bytes": 0}
				if conns.size() >= MAX_CONNECTIONS:
					c["refuse"] = "busy"
				elif not NetRules.source_allowed(ip, "home"):
					c["refuse"] = "refused"
				conns.append(c)
		for c in conns:
			if _step(c):
				moved = true
		conns = conns.filter(func(c): return str(c.state) != "done")
		OS.delay_msec(1 if moved else 5)
	for c in conns:
		_close(c, "nothing" if not c.has("outcome") else str(c.outcome))


func _step(c: Dictionary) -> bool:
	var peer: StreamPeerTCP = c.peer
	peer.poll()
	var now := Time.get_ticks_msec()
	var connected := peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
	match str(c.state):
		"read":
			if not connected:
				_close(c, "nothing" if (c.buf as PackedByteArray).is_empty() else "bad")
				return false
			var n := peer.get_available_bytes()
			if n > 0:
				var got: Array = peer.get_partial_data(mini(n, CHUNK))
				if got[0] == OK:
					var buf: PackedByteArray = c.buf
					c.erase("buf")
					buf.append_array(got[1])
					c["buf"] = buf
					c["last"] = now
					if buf.size() >= 1 and buf[0] == 0x16:   # a TLS ClientHello: https:// on an http:// port
						c["outcome"] = "https"
						_finish(c, PackedByteArray())
						return true
					var req := HttpUtil.parse(buf)
					if req.has("error"):
						c["outcome"] = "bad"
						_answer(c, {"bytes": HttpUtil.error_response(int(req.error), "bad request"), "status": int(req.error)})
					elif not req.is_empty():
						_handle(c, req)
					return true
			if now - int(c.t0) > HEADER_TIMEOUT_MS:
				_close(c, "nothing" if (c.buf as PackedByteArray).is_empty() else "bad")
		"write":
			if not connected:
				c["outcome"] = "cut"
				_close(c, "cut")
				return false
			return _write_some(c, now)
		"linger":
			# Drain what's left (so closing doesn't reset), until the phone hangs up or a moment passes.
			if connected and peer.get_available_bytes() > 0:
				peer.get_partial_data(peer.get_available_bytes())
				c["quiet_at"] = now
			if not connected or now - int(c.get("quiet_at", c.linger_at)) > 60 or now - int(c.linger_at) > LINGER_MS:
				_close(c, str(c.get("outcome", "request")))
	return false


func _handle(c: Dictionary, req: Dictionary) -> void:
	req["ip"] = str(c.ip)
	c["method"] = str(req.method)
	c["path"] = str(req.path).substr(0, 120)
	if c.has("refuse"):
		c["outcome"] = str(c.refuse)
		_answer(c, {"bytes": HttpUtil.error_response(503 if str(c.refuse) == "busy" else 403, "not allowed" if str(c.refuse) == "refused" else "busy"), "status": 503 if str(c.refuse) == "busy" else 403})
		return
	c["outcome"] = "request"
	if str(req.path) == "/api/report":
		var body: PackedByteArray = req.body if str(req.method) == "POST" else ReportSink.decode_get(str(req.query.get("r", "")))
		var res: Array = sink.accept(str(c.ip), body, "post" if str(req.method) == "POST" else "get", "ping")
		_answer(c, {"bytes": HttpUtil.json_response(int(res[0]), {"ok": int(res[0]) == 200, "message": str(res[1])}), "status": int(res[0])})
		return
	if str(req.method) == "OPTIONS":
		_answer(c, {"bytes": HttpUtil.response(204, PackedByteArray(), "text/plain", {"Allow": "GET, HEAD, POST, OPTIONS"}), "status": 204})
		return
	var r := DiagRoutes.handle(req, _ctx, true)
	if r.is_empty():
		r = {"bytes": HttpUtil.error_response(405, "method not allowed"), "status": 405}
	_answer(c, r)


func _answer(c: Dictionary, r: Dictionary) -> void:
	c["out"] = r.bytes
	c["sent"] = 0
	c["status"] = int(r.status)
	if r.has("blob"):
		c["blob"] = r.blob
		c["blob_pos"] = 0
	c["state"] = "write"
	c["last"] = Time.get_ticks_msec()


func _write_some(c: Dictionary, now: int) -> bool:
	var peer: StreamPeerTCP = c.peer
	var out: PackedByteArray = c.out
	if int(c.sent) >= out.size():
		var blob: PackedByteArray = c.get("blob", PackedByteArray())
		var pos := int(c.get("blob_pos", 0))
		if pos >= blob.size():
			_finish(c, PackedByteArray())
			return false
		c["out"] = blob.slice(pos, mini(pos + CHUNK, blob.size()))
		c["blob_pos"] = pos + (c.out as PackedByteArray).size()
		c["sent"] = 0
		out = c.out
	var r: Array = peer.put_partial_data(out.slice(int(c.sent)))
	if r[0] != OK:
		c["outcome"] = "cut"
		_close(c, "cut")
		return false
	var n := int(r[1])
	c["sent"] = int(c.sent) + n
	c["bytes"] = int(c.bytes) + n
	if n > 0:
		c["last"] = now
		return true
	if now - int(c.last) > IDLE_TIMEOUT_MS:
		c["outcome"] = "cut"
		_close(c, "cut")
	return false


func _finish(c: Dictionary, _unused: PackedByteArray) -> void:
	c["state"] = "linger"
	c["linger_at"] = Time.get_ticks_msec()
	c.erase("blob")


func _close(c: Dictionary, outcome: String) -> void:
	if str(c.state) == "done":
		return
	(c.peer as StreamPeerTCP).disconnect_from_host()
	c["state"] = "done"
	var e := {
		"t": Time.get_unix_time_from_system(), "ip": str(c.ip), "port": int(c.port), "outcome": outcome,
		"method": str(c.get("method", "")), "path": str(c.get("path", "")), "status": int(c.get("status", 0)),
		"bytes": int(c.get("bytes", 0)), "ms": Time.get_ticks_msec() - int(c.t0),
	}
	var line := "%s %s port %d %s" % [Time.get_datetime_string_from_unix_time(int(e.t)), e.ip, e.port, outcome_text(e)]
	_mutex.lock()
	_contacts.append(e)
	if _contacts.size() > KEEP_CONTACTS:
		_contacts = _contacts.slice(_contacts.size() - KEEP_CONTACTS)
	_contact_total += 1
	_log_lines.append(line)
	_mutex.unlock()


func _log(text: String) -> void:
	_mutex.lock()
	_log_lines.append("%s %s" % [Time.get_datetime_string_from_system(true), text])
	_mutex.unlock()


func _flush_log() -> void:
	_mutex.lock()
	var lines := _log_lines
	_log_lines = PackedStringArray()
	_mutex.unlock()
	if lines.is_empty() or log_path == "":
		return
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	if FileAccess.file_exists(log_path) and FileAccess.get_size(log_path) > 512 * 1024:
		DirAccess.remove_absolute(log_path + ".1")
		DirAccess.rename_absolute(log_path, log_path + ".1")
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	for l in lines:
		f.store_line(l)
		print("[ping] ", l)
	f.close()
