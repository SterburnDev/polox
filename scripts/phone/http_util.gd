extends RefCounted
## Tiny HTTP/1.1 helpers for Phone Link: parse one request from raw bytes,
## build responses with safe headers, MIME types, URL decoding and strict
## path checks. One request per connection (Connection: close) keeps it simple.

const MAX_HEADER_BYTES := 16 * 1024
const MAX_BODY_BYTES := 16 * 1024 * 1024
const REASONS := {
	200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
	405: "Method Not Allowed", 409: "Conflict", 411: "Length Required", 413: "Payload Too Large",
	415: "Unsupported Media Type", 422: "Unprocessable Content", 429: "Too Many Requests", 500: "Internal Server Error", 503: "Service Unavailable", 507: "Insufficient Storage",
}
const MIME := {
	"html": "text/html; charset=utf-8", "js": "text/javascript", "wasm": "application/wasm",
	"pck": "application/octet-stream", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
	"webp": "image/webp", "svg": "image/svg+xml", "ico": "image/x-icon", "json": "application/json",
	"jsonl": "application/x-ndjson", "css": "text/css", "txt": "text/plain; charset=utf-8",
	"webmanifest": "application/manifest+json", "zip": "application/zip",
}


static func mime_for(path: String) -> String:
	return str(MIME.get(path.get_extension().to_lower(), "application/octet-stream"))


## Parses what has arrived so far. Returns {} while incomplete, or
## {method, path, query, headers, body} when done, or {error: code} for a bad request.
static func parse(buf: PackedByteArray) -> Dictionary:
	var end := _find_header_end(buf)
	if end < 0:
		return {"error": 413} if buf.size() > MAX_HEADER_BYTES else {}
	if end > MAX_HEADER_BYTES:
		return {"error": 413}
	var head := buf.slice(0, end).get_string_from_ascii()
	var lines := head.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() != 3 or not first[2].begins_with("HTTP/1."):
		return {"error": 400}
	var headers := {}
	for i in range(1, lines.size()):
		var c := lines[i].find(":")
		if c <= 0:
			return {"error": 400}
		headers[lines[i].substr(0, c).strip_edges().to_lower()] = lines[i].substr(c + 1).strip_edges()
	if headers.has("transfer-encoding"):
		return {"error": 411}  # no chunked uploads: a length is required
	var length := 0
	if headers.has("content-length"):
		var cl := str(headers["content-length"])
		if not cl.is_valid_int() or cl.to_int() < 0:
			return {"error": 400}
		length = cl.to_int()
	if length > MAX_BODY_BYTES:
		return {"error": 413}
	var body_start := end + 4
	if buf.size() - body_start < length:
		return {}
	var target := first[1]
	var q := target.find("?")
	var raw_path := target.substr(0, q) if q >= 0 else target
	var query := parse_query(target.substr(q + 1)) if q >= 0 else {}
	var path := url_decode(raw_path)
	if path == "" or path.to_utf8_buffer().has(0):
		return {"error": 400}
	return {
		"method": first[0].to_upper(),
		"path": path,
		"query": query,
		"headers": headers,
		"body": buf.slice(body_start, body_start + length),
	}


## Where the headers end (the blank line after them), or -1 while they're still arriving.
static func header_end(buf: PackedByteArray) -> int:
	return _find_header_end(buf)


static func _find_header_end(buf: PackedByteArray) -> int:
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


static func parse_query(q: String) -> Dictionary:
	var out := {}
	for pair in q.split("&", false):
		var eq := pair.find("=")
		var k := url_decode(pair.substr(0, eq) if eq >= 0 else pair)
		out[k] = url_decode(pair.substr(eq + 1)) if eq >= 0 else ""
	return out


## Percent-decoding (and "+" as space in queries). Invalid escapes stay as they are.
static func url_decode(s: String) -> String:
	var bytes := PackedByteArray()
	var src := s.to_utf8_buffer()
	var i := 0
	while i < src.size():
		var ch := src[i]
		if ch == 37 and i + 2 < src.size() and _hex(src[i + 1]) >= 0 and _hex(src[i + 2]) >= 0:  # %
			bytes.append(_hex(src[i + 1]) * 16 + _hex(src[i + 2]))
			i += 3
		elif ch == 43:  # +
			bytes.append(32)
			i += 1
		else:
			bytes.append(ch)
			i += 1
	return bytes.get_string_from_utf8()


static func _hex(c: int) -> int:
	if c >= 48 and c <= 57:
		return c - 48
	if c >= 65 and c <= 70:
		return c - 55
	if c >= 97 and c <= 102:
		return c - 87
	return -1


## A relative path inside the save root that is safe to touch: forward
## slashes only, no "..", no "." parts, no drive letters, no leading slash.
static func safe_rel_path(p: String) -> bool:
	if p == "" or p.length() > 400 or p.begins_with("/") or p.contains("\\") or p.contains(":") or p.to_utf8_buffer().has(0):
		return false
	for part in p.split("/"):
		if part == "" or part == "." or part == ".." or part.begins_with("."):
			return false
	return true


## A full response. Never sends CORS headers: other web pages can't read anything.
static func response(code: int, body: PackedByteArray, content_type: String = "application/json", extra: Dictionary = {}) -> PackedByteArray:
	var head := "HTTP/1.1 %d %s\r\n" % [code, REASONS.get(code, "OK")]
	var h := {
		"Content-Type": content_type,
		"Content-Length": str(body.size()),
		"Connection": "close",
		"Cache-Control": "no-store",
		"X-Content-Type-Options": "nosniff",
		"Referrer-Policy": "no-referrer",
		"X-Frame-Options": "DENY",
	}
	for k in extra:
		h[k] = extra[k]
	for k in h:
		head += "%s: %s\r\n" % [k, h[k]]
	head += "\r\n"
	var out := head.to_utf8_buffer()
	out.append_array(body)
	return out


static func json_response(code: int, data: Variant) -> PackedByteArray:
	return response(code, JSON.stringify(data).to_utf8_buffer(), "application/json")


static func error_response(code: int, message: String) -> PackedByteArray:
	return json_response(code, {"ok": false, "error": message})


## The bearer token from "Authorization: Bearer <token>" ("" if missing).
static func bearer(headers: Dictionary) -> String:
	var a := str(headers.get("authorization", ""))
	return a.substr(7).strip_edges() if a.to_lower().begins_with("bearer ") else ""


static func sha256_bytes(b: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not b.is_empty():   # (update() refuses an empty buffer with an engine error; the hash of nothing is the same)
		ctx.update(b)
	return ctx.finish().hex_encode()


## Same-length comparison that takes the same time wherever the strings differ.
static func constant_time_equals(a: String, b: String) -> bool:
	var ab := a.to_utf8_buffer()
	var bb := b.to_utf8_buffer()
	var diff := ab.size() ^ bb.size()
	for i in maxi(ab.size(), bb.size()):
		var x := ab[i] if i < ab.size() else 0
		var y := bb[i] if i < bb.size() else 0
		diff |= x ^ y
	return diff == 0
