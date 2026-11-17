extends RefCounted
## Raw HTTP from the test side, the way browsers and phones really talk:
## plain sockets, several downloads at once, idle sockets, slow senders and
## dropped connections. Used by test_phone_link.gd and test_phone_e2e.gd.

var tree: SceneTree


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree


func _frame() -> void:
	await tree.process_frame


func connect_peer(host: String, port: int, timeout_ms: int = 3000) -> StreamPeerTCP:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host(host, port) != OK:
		return null
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < timeout_ms:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			return peer
		if peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			return null
		await _frame()
	return null


## One request; returns {code, headers (lowercase keys), body (bytes), ok, ms}.
func request(host: String, port: int, raw: Variant, timeout_ms: int = 15000) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var peer := await connect_peer(host, port)
	if peer == null:
		return {"code": 0, "headers": {}, "body": PackedByteArray(), "ok": false, "ms": 0, "error": "connect failed"}
	var bytes: PackedByteArray = raw if raw is PackedByteArray else str(raw).to_utf8_buffer()
	peer.put_data(bytes)
	var got := await read_all(peer, timeout_ms)
	peer.disconnect_from_host()   # (a reply that timed out leaves no half-open socket behind)
	var r := parse_response(got)
	r["ms"] = Time.get_ticks_msec() - t0
	return r


## Reads until the server closes the connection (it always does) or time runs out.
func read_all(peer: StreamPeerTCP, timeout_ms: int = 15000) -> PackedByteArray:
	var got := PackedByteArray()
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < timeout_ms:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_data(n)[1])
			continue
		await _frame()
	return got


static func parse_response(got: PackedByteArray) -> Dictionary:
	var end := -1
	for i in range(0, got.size() - 3):
		if got[i] == 13 and got[i + 1] == 10 and got[i + 2] == 13 and got[i + 3] == 10:
			end = i
			break
	if end < 0:
		return {"code": 0, "headers": {}, "body": PackedByteArray(), "ok": false, "error": "no response"}
	var head := got.slice(0, end).get_string_from_utf8()
	var lines := head.split("\r\n")
	var headers := {}
	for i in range(1, lines.size()):
		var c := lines[i].find(":")
		if c > 0:
			headers[lines[i].substr(0, c).strip_edges().to_lower()] = lines[i].substr(c + 1).strip_edges()
	return {"code": lines[0].get_slice(" ", 1).to_int(), "headers": headers, "body": got.slice(end + 4), "ok": true, "head": head}


static func get_req(path: String, extra: Dictionary = {}, host_header: String = "x") -> String:
	var s := "GET %s HTTP/1.1\r\nHost: %s\r\n" % [path, host_header]
	for k in extra:
		s += "%s: %s\r\n" % [k, extra[k]]
	return s + "\r\n"


static func with_body(method: String, path: String, body: PackedByteArray, token: String = "", host_header: String = "x") -> PackedByteArray:
	var s := "%s %s HTTP/1.1\r\nHost: %s\r\nContent-Length: %d\r\n" % [method, path, host_header, body.size()]
	if token != "":
		s += "Authorization: Bearer %s\r\n" % token
	var out := (s + "\r\n").to_utf8_buffer()
	out.append_array(body)
	return out


## Several GETs at the same time on separate connections (like a browser).
## Returns [{code, headers, body}] in the same order.
func parallel(host: String, port: int, raws: Array, timeout_ms: int = 30000) -> Array:
	var peers: Array = []
	for r in raws:
		var p := await connect_peer(host, port)
		if p:
			p.put_data(str(r).to_utf8_buffer())
		peers.append({"peer": p, "got": PackedByteArray(), "done": p == null})
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < timeout_ms:
		var open := 0
		for e in peers:
			if e.done:
				continue
			var p: StreamPeerTCP = e.peer
			p.poll()
			if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				e.done = true
				continue
			var n := p.get_available_bytes()
			if n > 0:
				var g: PackedByteArray = e.got
				e.erase("got")
				g.append_array(p.get_data(n)[1])
				e["got"] = g
			open += 1
		if open == 0:
			break
		await _frame()
	var out: Array = []
	for e in peers:
		if e.peer:
			(e.peer as StreamPeerTCP).disconnect_from_host()
		out.append(parse_response(e.got))
	return out


static func sha(b: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode()
