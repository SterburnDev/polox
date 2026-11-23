extends RefCounted
## Phone Link's /api/ endpoints (main thread). Everything but /api/pair needs
## the device token. Paths are checked against the allow-list (the synced
## slots + the Library), bodies against size limits, and the AI proxy keeps
## the API key on the PC: the phone sends the messages, the PC asks the AI.
##
##   GET  /api/pairing                               -> {paused, cooldown} for this address (no key needed)
##        ?wrap=1                                    -> + {pair_v: 1, kdf, iter, salt, seal, pub} (pairing.gd)
##   POST /api/pair            {code, device, client} -> {token}  (401 tries_left / 429 retry_after / 423 paused)
##        {pair_v: 1, salt, nonce, sealed, device, client} -> {pair_v: 1, ct, tag, phrase} (409 stale_salt: a new PIN)
##   Everything below: "Authorization: Polox-Sig ..." (request_sig.gd; a pair_v:1 phone must sign) or
##   "Authorization: Bearer <token>" (phones that paired the old way). 401 {clock, now}: the phone's time is off.
##   GET  /api/status                                -> world list, AI mode
##   GET  /api/worlds                                -> the worlds this phone may play (the launcher's cards)
##   GET  /api/cover?slot=                           -> that world's cover picture (PNG)
##   POST /api/session         {slot}                -> {play: the game's address for that world}
##   GET  /api/manifest?slots=                       -> {files: {path: {sha256, size, mtime, rev}}}
##   GET  /api/file?path=      PUT ?path=&base=      DELETE ?path=&base=
##   POST /api/sync/begin      {slots: [...]}        -> snapshot first
##   POST /api/sync/end        {changed: [...]}
##   POST /api/ai              {messages, opts}      -> {ok, text, error}
##   POST /api/unpair                                 (the phone forgets itself)
##   PUT  /api/export?name=&offset=&total=&sha256=    a file the phone exported, in chunks -> exports/ (export_inbox.gd)

const HttpUtil := preload("res://scripts/phone/http_util.gd")
const ReportSink := preload("res://scripts/net/report_sink.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Slots := preload("res://scripts/core/slots.gd")
const ExportInbox := preload("res://scripts/phone/export_inbox.gd")

const SNAPSHOT_EVERY_S := 600.0     # at most one before-sync snapshot per slot per 10 minutes
const AI_OPTS: PackedStringArray = ["max_tokens", "json", "temperature", "mock", "model"]   # model: a friend's own

var _helper_busy := false
var helper_transport: Callable

var server: Node                    # phone_server.gd
var _last_snapshot: Dictionary = {} # slot -> unix time
var _last_touch := 0.0
var last_sync := 0.0                # unix time the phone last finished a sync
var authed: Dictionary = {}         # phone address -> device name, once it used its key (the PC banner)

## Raised after the phone changed files in a world, so a running game can reload it.
var on_world_changed: Callable = Callable()
const COMMIT_NOTICE_S := 3.0         # a sync that never sends /sync/end still reloads after this
var _committed: Dictionary = {}      # slot -> paths written since the last reload notice
var _committed_timer: SceneTreeTimer


func _init(owner_server: Node) -> void:
	server = owner_server


## The worlds a paired phone may see and sync: every world not in the trash,
## except the ones switched off in the Save menu ("Available on phone").
func synced_slots() -> PackedStringArray:
	return Slots.phone_ids()


## The worlds one sync covers: the ones the phone asks for (the world it
## plays), else the PC's active world (older phone versions), else the first.
func sync_scope(asked: String) -> PackedStringArray:
	var allowed := synced_slots()
	var out := PackedStringArray()
	for s in asked.split(",", false):
		if s.strip_edges() in allowed and not s.strip_edges() in out:
			out.append(s.strip_edges())
	if out.is_empty() and asked == "":
		if SaveManager.slot_id in allowed:
			out.append(SaveManager.slot_id)
		elif not allowed.is_empty():
			out.append(allowed[0])
	return out


func state_path() -> String:
	return server.root.path_join("phone").path_join("sync_state.json")


func handle(req: Dictionary, ip: String) -> PackedByteArray:
	var path := str(req.path)
	var method := str(req.method)
	if path == "/api/pairing":
		var st: Dictionary = server.pairing.state_for(ip)
		var state := {"ok": true, "paused": bool(st.paused), "cooldown": int(st.cooldown), "always_ask": bool(st.always_ask)}
		if str(req.query.get("wrap", "")) == "1":
			state.merge(server.pairing.wrap_info(), true)
		return HttpUtil.json_response(200, state)
	if path == "/api/report":
		# A phone's Connection Test or the game's start-up diagnostics: no key needed (strict limits in ReportSink).
		var body: PackedByteArray = req.body if method == "POST" else ReportSink.decode_get(str(req.query.get("r", "")))
		var res: Array = server.reports.accept(ip, body, "post" if method == "POST" else "get", "host", "bundled" if bool(req.get("proxied", false)) else "built-in")
		if int(res[0]) == 200:
			server.report_arrived()
		return HttpUtil.json_response(int(res[0]), {"ok": int(res[0]) == 200, "message": str(res[1])})
	if path == "/api/pair":
		if method != "POST":
			return HttpUtil.error_response(405, "use POST")
		var body := _json(req)
		var r: Dictionary = server.pairing.pair(str(body.get("code", "")), str(body.get("device", "")), ip, str(req.headers.get("host", "")), str(body.get("client", "")), body)
		if not r.ok:
			var extra := {}
			for k in ["retry_after", "tries_left", "stale_salt"]:
				if r.has(k):
					extra[k] = r[k]
			server.pairing_changed()
			return HttpUtil.json_response(int(r.status), {"ok": false, "error": str(r.error)}.merged(extra))
		server.mark_active()
		server.paired_device(str(body.get("device", "")), ip, str(r.get("phrase", "")))
		if r.has("ct"):   # pair_v:1: the token only ever leaves the PC encrypted
			return HttpUtil.json_response(200, {"ok": true, "pair_v": r.pair_v, "ct": r.ct, "tag": r.tag, "phrase": r.phrase, "device_id": r.device_id})
		return HttpUtil.json_response(200, {"ok": true, "token": r.token, "device_id": r.device_id})
	var auth: Dictionary = server.pairing.authenticate(req)
	if auth.has("clock"):   # a good-looking signature with a time far from the PC's: the phone corrects and retries
		return HttpUtil.json_response(401, {"ok": false, "error": "clock", "clock": true, "now": int(auth.now)})
	if auth.has("busy"):
		return HttpUtil.error_response(503, "too many requests at once: try again in a moment")
	if not auth.has("device"):
		server.pairing.audit("auth_failed path=%s ip=%s" % [path, ip])
		return HttpUtil.error_response(401, "not paired")
	var device: Dictionary = auth.device
	server.mark_active()
	authed[ip] = str(device.get("name", "My phone"))
	if Time.get_unix_time_from_system() - _last_touch > 60.0:
		_last_touch = Time.get_unix_time_from_system()
		server.pairing.touch(str(device.id))
	device["_host_now"] = str(req.headers.get("host", ""))
	match path:
		"/api/status":
			return _status(device)
		"/api/worlds":
			return _worlds()
		"/api/cover":
			return _cover(req)
		"/api/session":
			return _session(req, device)
		"/api/manifest":
			var scope := sync_scope(str(req.query.get("slots", "")))
			var home := home_state()
			return HttpUtil.json_response(200, {"ok": true, "slots": scope, "home": home, "files": SyncFiles.manifest(server.root, scope, state_path())})
		"/api/file":
			return _file(req, ip)
		"/api/sync/begin":
			return _sync_begin(req)
		"/api/sync/end":
			return _sync_end(req)
		"/api/home-helper":
			return await _home_helper(req)
		"/api/ai":
			return await _ai(req)
		"/api/export":
			return _export(req, device, ip)
		"/api/unpair":
			server.pairing.unpair(str(device.id))
			server.pairing_changed()
			return HttpUtil.json_response(200, {"ok": true})
	return HttpUtil.error_response(404, "no such endpoint")


## A file the phone exported arrives in chunks and lands in the PC's exports folder.
func _export(req: Dictionary, device: Dictionary, ip: String) -> PackedByteArray:
	if str(req.method) != "PUT":
		return HttpUtil.error_response(405, "use PUT")
	var r: Array = ExportInbox.receive(server.root, str(device.get("id", "")), req.query, req.body)
	var res: Dictionary = r[1]
	if bool(res.get("done", false)):
		server.pairing.audit("export_received file=%s bytes=%d device=%s ip=%s" % [str(res.saved).c_escape(), int(res.have), str(device.get("name", "")).c_escape(), ip])
		GameState.notify("%s sent %s to Polox on this PC (%s)." % [str(device.get("name", "Your phone")), str(res.saved).get_file(), str(res.saved).get_base_dir()])
	return HttpUtil.json_response(int(r[0]), res)


## The launcher's world cards: only worlds this phone may play.
func _worlds() -> PackedByteArray:
	var out: Array = []
	for m in Slots.list():
		var id := str(m.id)
		if not Slots.on_phone(id):
			continue
		var st: Dictionary = m.get("stats", {})
		out.append({
			"id": id, "name": str(m.get("name", id)), "emoji": str(m.get("emoji", "")), "accent": str(m.get("accent", "#c9b6ff")),
			"last_played": str(m.get("last_played", "")), "ago": Slots.ago_text(str(m.get("last_played", ""))) if str(m.get("last_played", "")) != "" else "not played yet",
			"size": Slots.size_text(int(st.get("bytes", 0))), "playtime": Slots.playtime_text(int(m.get("playtime_s", 0))),
			"rooms": int(st.get("rooms", 0)), "characters": int(st.get("characters", 0)),
			"cover": Slots.cover_path(id) != "", "active": id == SaveManager.slot_id,
		})
	var info: Dictionary = server.page_info()
	return HttpUtil.json_response(200, {"ok": true, "worlds": out, "game": {"ok": bool(info.get("has_game", false)) and bool(info.get("game_current", true)), "present": bool(info.get("has_game", false))}})


func _cover(req: Dictionary) -> PackedByteArray:
	var id := str(req.query.get("slot", ""))
	if not id in synced_slots():
		return HttpUtil.error_response(404, "no such world")
	var p := Slots.cover_path(id)
	if p == "" or not FileAccess.file_exists(p):
		return HttpUtil.error_response(404, "no cover")
	return HttpUtil.response(200, FileAccess.get_file_as_bytes(p), "image/png", {"Cache-Control": "private, max-age=300"})


## The phone picked a world: remember it (the PC shows "Phone playing ...") and
## say where the game is. The game reads the world from the address's #slot=.
func _session(req: Dictionary, device: Dictionary) -> PackedByteArray:
	var id := str(_json(req).get("slot", ""))
	if not id in synced_slots():
		return HttpUtil.error_response(404, "that world isn't available on the phone")
	var info: Dictionary = server.page_info()
	var game_ok := bool(info.get("has_game", false)) and bool(info.get("game_current", true))
	server.phone_session = {"device": str(device.get("name", "")), "slot": id, "name": str(Slots.meta(id).get("name", id)), "t": Time.get_unix_time_from_system()}
	server.state_changed.emit()
	return HttpUtil.json_response(200, {"ok": true, "slot": id, "play": (str(info.get("game_path", "")) if str(info.get("game_path", "")) != "" else "/game/none/") + "index.html#slot=" + id.uri_encode(), "game_ok": game_ok,
		"why": "" if game_ok else ("The game files for phones are older than Polox on the PC. On the PC: Settings > Phone Link > Build the phone version (or run phone_doctor.bat)." if bool(info.get("has_game", false)) else "The game files for phones aren't built on the PC yet. On the PC: Settings > Phone Link > Build the phone version (or run phone_doctor.bat).")})


func _json(req: Dictionary) -> Dictionary:
	var data: Variant = JsonUtil.parse((req.body as PackedByteArray).get_string_from_utf8())
	return data if data is Dictionary else {}


func _status(device: Dictionary) -> PackedByteArray:
	var Research := preload("res://scripts/home/research.gd")
	var provider := Research.preferred()
	var worlds: Array = []
	for s in synced_slots():
		worlds.append({"id": s, "name": str(Slots.meta(s).get("name", s))})
	return HttpUtil.json_response(200, {
		"ok": true,
		"app": "Polox",
		"home_helper": {"provider": provider, "ready": provider in ["openai", "compatible"] and bool(Research.available().get(provider, false))},
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"device": str(device.get("name", "")),
		"host": str(device.get("_host_now", "")),
		"paired_host": str(device.get("host", "")),
		"slots": worlds,
		"active_slot": SaveManager.slot_id,
		"ai": {"mock": AIClient.is_mock(), "status": AIClient.status_message},
		"time": Time.get_datetime_string_from_system(),
	})


func _file(req: Dictionary, ip: String) -> PackedByteArray:
	var rel := str(req.query.get("path", ""))
	home_state()   # honour the setting immediately, including a request without a manifest first
	if not SyncFiles.allowed(rel, synced_slots()):
		server.pairing.audit("path_refused path=%s ip=%s" % [rel.substr(0, 120).c_escape(), ip])
		return HttpUtil.error_response(403, "that file isn't shared with the phone")
	var full: String = server.root.path_join(rel)
	if rel.begins_with("my_home/") and str(req.method) in ["PUT", "DELETE"]:
		if Time.get_unix_time_from_system() - float(_last_snapshot.get("my_home", 0.0)) >= SNAPSHOT_EVERY_S:
			if SyncFiles.snapshot_home(server.root) != "":
				_last_snapshot["my_home"] = Time.get_unix_time_from_system()
			elif FileAccess.file_exists(server.root.path_join("my_home/home.json")):
				return HttpUtil.error_response(507, "Couldn't back up the PC's home. Free storage and retry.")
	match str(req.method):
		"GET":
			if not FileAccess.file_exists(full):
				return HttpUtil.error_response(404, "no such file")
			var bytes := FileAccess.get_file_as_bytes(full)
			if bytes.size() > SyncFiles.max_bytes(rel):
				return HttpUtil.error_response(413, "file too big to sync")
			SyncFiles.keep_base(server.root, rel, bytes)   # what the phone will have: the common ground for a merge
			return HttpUtil.response(200, bytes, HttpUtil.mime_for(rel), {"X-Sha256": HttpUtil.sha256_bytes(bytes)})
		"PUT":
			var body: PackedByteArray = req.body
			if body.size() > SyncFiles.max_bytes(rel):
				return HttpUtil.error_response(413, "file too big to sync")
			var before := SyncFiles.sha_of(full)
			var r := SyncFiles.put(server.root, rel, body, str(req.query.get("base", "")))
			if r.status == "rejected":
				return HttpUtil.error_response(415, str(r.get("error", "rejected")))
			if r.status == "conflict":
				server.pairing.audit("conflict kept_pc path=%s stash=%s fields=%s" % [rel, r.stash, ",".join(PackedStringArray(r.get("fields", []))).left(200)])
			if str(r.get("sha256", "")) != before:
				_notify_committed(rel)
			return HttpUtil.json_response(409 if r.status == "conflict" else 200, {"ok": r.status != "conflict", "status": r.status, "sha256": r.get("sha256", ""), "stash": r.get("stash", "")})
		"DELETE":
			var r := SyncFiles.delete(server.root, rel, str(req.query.get("base", "")))
			if r.status == "rejected":
				return HttpUtil.error_response(507, str(r.error))
			if r.status == "applied":
				_notify_committed(rel)
			return HttpUtil.json_response(409 if r.status == "conflict" else 200, {"ok": r.status != "conflict", "status": r.status, "sha256": r.get("sha256", "")})
	return HttpUtil.error_response(405, "method not allowed")


## Your Light World and phones: "shared" (paired phones get the house and streets, never the address or
## answers), "private" (you turned it off in Settings > Light World), "none" (no home yet). Sets
## SyncFiles.home_shared for this sync.
func home_state() -> String:
	var HomeStore: Script = load("res://scripts/home/home_store.gd")
	var has_home: bool = FileAccess.file_exists(server.root.path_join("my_home").path_join("home.json"))
	var lw: Variant = GameState.settings.get("light_world", {})
	var on := bool(lw.get("on_phone", true)) if lw is Dictionary else true
	SyncFiles.home_shared = on and has_home
	if not has_home:
		return "none"
	if not on:
		return "private"
	if server.root == SaveManager.root:
		if not HomeStore.split_private():
			SyncFiles.home_shared = false
			return "private"
	return "shared"


## Before the phone changes anything in a world, that world gets a snapshot zip.
func _sync_begin(req: Dictionary) -> PackedByteArray:
	var snaps: Array = []
	SyncFiles.prune_bases(server.root)
	var wanted: Variant = _json(req).get("slots", [])
	for s in (wanted if wanted is Array else []):
		var id := str(s)
		if not id in synced_slots():
			continue
		if Time.get_unix_time_from_system() - float(_last_snapshot.get(id, 0.0)) < SNAPSHOT_EVERY_S:
			continue
		var zip := SyncFiles.snapshot(server.root, id)
		if zip != "":
			_last_snapshot[id] = Time.get_unix_time_from_system()
			snaps.append(zip.get_file())
		elif FileAccess.file_exists(server.root.path_join("slots").path_join(id).path_join("world.json")):
			return HttpUtil.error_response(507, "Couldn't back up the PC world. Free storage and retry.")
	return HttpUtil.json_response(200, {"ok": true, "snapshots": snaps})


## Delivery of /sync/end is not guaranteed after a successful mutation, so each committed file is
## remembered; /sync/end (or, if it never comes, a short quiet spell) reloads the game once for all.
## One reload per pushed file would rebuild the room several times in a row on the PC.
func _notify_committed(rel: String) -> void:
	_collect_changed(_committed, rel)
	if _committed_timer == null and server and server.is_inside_tree():
		_committed_timer = server.get_tree().create_timer(COMMIT_NOTICE_S)
		_committed_timer.timeout.connect(func():
			_committed_timer = null
			_flush_changed({}))


## slot -> [paths] for a changed path ("my_home/..." belongs to the world being played).
static func _collect_changed(slots: Dictionary, rel: String) -> void:
	var parts := rel.split("/")
	var slot := SaveManager.slot_id if parts[0] == "my_home" else (str(parts[1]) if parts.size() > 2 and parts[0] == "slots" else "")
	if slot == "":
		return
	if not slots.has(slot):
		slots[slot] = []
	if not rel in slots[slot]:
		(slots[slot] as Array).append(rel)


func _flush_changed(extra: Dictionary) -> void:
	var slots := _committed
	_committed = {}
	for s in extra:
		for p in extra[s]:
			_collect_changed(slots, str(p))
	for s in slots:
		if on_world_changed.is_valid():
			on_world_changed.call(str(s), slots[s])


func _sync_end(req: Dictionary) -> PackedByteArray:
	last_sync = Time.get_unix_time_from_system()
	var changed: Variant = _json(req).get("changed", [])
	var slots := {}
	for p in (changed if changed is Array else []):
		# The Light World belongs to every world here: the one being played reloads if you're in it.
		_collect_changed(slots, str(p))
	_flush_changed(slots)
	return HttpUtil.json_response(200, {"ok": true})


## The AI proxy: same request the phone would have sent, made from the PC
## with the PC's settings (the key never leaves this computer).
func _ai(req: Dictionary) -> PackedByteArray:
	var body := _json(req)
	var msgs: Variant = body.get("messages", [])
	if not msgs is Array or (msgs as Array).is_empty() or (msgs as Array).size() > 60:
		return HttpUtil.error_response(400, "messages missing")
	for m in msgs:
		if not m is Dictionary or not str(m.get("role", "")) in ["system", "user", "assistant"] or not m.get("content") is String:
			return HttpUtil.error_response(400, "bad message")
	var opts := {}
	var given: Variant = body.get("opts", {})
	if given is Dictionary:
		for k in AI_OPTS:
			if given.has(k):
				opts[k] = given[k]
	var r: Dictionary = await AIClient.chat(msgs, opts)
	return HttpUtil.json_response(200, {"ok": bool(r.get("ok", false)), "text": str(r.get("text", "")), "error": str(r.get("error", ""))})


## Paired phones explicitly choose the PC and the configured recipient. Reject
## a changed provider; do not forward keys, arbitrary URLs, or silent fallbacks.
func _home_helper(req: Dictionary) -> PackedByteArray:
	var Http := preload("res://scripts/home/helper_http.gd")
	var Research := preload("res://scripts/home/research.gd")
	if str(req.method) != "POST":
		return HttpUtil.error_response(405, "Use POST.")
	var body := _json(req)
	var provider := str(body.get("provider", ""))
	if provider not in ["openai", "compatible"] or provider != Research.preferred() or not bool(Research.available().get(provider, false)):
		return HttpUtil.error_response(409, "PC helper changed or needs setup. Sync and choose it again.")
	if _helper_busy:
		return HttpUtil.error_response(409, "The PC helper is busy. Wait for it to finish.")
	if not body.get("prompt") is String or str(body.prompt).length() > 100000 or not body.get("schema") is Dictionary:
		return HttpUtil.error_response(400, "Invalid helper request.")
	_helper_busy = true
	var helper := Http.new()
	server.add_child(helper)
	helper.transport = helper_transport
	var result: Dictionary = await helper.run(provider, Research.settings(), str(body.prompt), body.schema, bool(body.get("web", true)))
	helper.queue_free()
	_helper_busy = false
	return HttpUtil.json_response(200, result)
