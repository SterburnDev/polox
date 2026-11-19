extends RefCounted
## The connection-test routes, answered the same way by Polox Ping and by the
## real Phone Link (pure functions, safe on a socket thread):
##   GET /ping            plain text "Polox OK"
##   GET /test            the phone-side Connection Test page (test_page.gd)
##   GET /test/info.json  a small JSON: which server, which PC, the caller's address
##   GET /test/big.json   {size, sha256} of /test/big
##   GET /test/big        ~20 MB of random bytes (streamed, never copied per request)
##   GET /reset           clears this site's saved state on the phone (after saying what goes)
##   (Polox Ping only) anything else: the plain "Polox OK" page with a link to /test
## Every answer: HTTP/1.1, Content-Length, Connection: close, Cache-Control: no-store.
## Results are {bytes, status} or {bytes, status, blob} (blob streamed after the
## header), or {} when the path isn't one of these.

const HttpUtil := preload("res://scripts/phone/http_util.gd")
const TestPage := preload("res://scripts/net/test_page.gd")
const BigFile := preload("res://scripts/net/big_file.gd")
const ResetPage := preload("res://scripts/net/reset_page.gd")

## ctx: {server: "ping"|"host", server_name, engine, pc, build_id, port}
static func handle(req: Dictionary, ctx: Dictionary, any_path: bool = false) -> Dictionary:
	var method := str(req.get("method", "GET"))
	if not method in ["GET", "HEAD"]:
		return {}
	var path := str(req.get("path", "/"))
	var head := method == "HEAD"
	match path:
		"/ping":
			return _plain(200, "Polox OK\n", "text/plain; charset=utf-8", head)
		"/favicon.ico":   # every browser asks for it; a 404 would show up as an error
			var icon := HttpUtil.response(200, favicon(), "image/png")
			return {"bytes": icon.slice(0, HttpUtil.header_end(icon) + 4) if head else icon, "status": 200}
		"/reset":
			return _plain(200, ResetPage.html(), "text/html; charset=utf-8", head)
		"/test", "/test/", "/test.html":
			return _plain(200, TestPage.html(), "text/html; charset=utf-8", head)
		"/test/info.json":
			return _plain(200, JSON.stringify(info(req, ctx)), "application/json", head)
		"/test/big.json":
			return _plain(200, JSON.stringify(BigFile.meta()), "application/json", head)
		"/test/big":
			var f := BigFile.get_file()
			var hdr := HttpUtil.response(200, PackedByteArray(), "application/octet-stream", {"Content-Length": str(int(f.size)), "X-Polox-Sha256": str(f.sha256)})
			if head:
				return {"bytes": hdr, "status": 200}
			return {"bytes": hdr, "status": 200, "blob": f.bytes}
	if any_path:
		return _plain(200, ok_page(req, ctx), "text/html; charset=utf-8", head)
	return {}


static var _icon := PackedByteArray()
static var _icon_mutex := Mutex.new()


## A small Polox-yellow dot (made once; any thread).
static func favicon() -> PackedByteArray:
	_icon_mutex.lock()
	if _icon.is_empty():
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				img.set_pixel(x, y, Color("#ffd166") if Vector2(x - 7.5, y - 7.5).length() < 7.0 else Color(0, 0, 0, 0))
		_icon = img.save_png_to_buffer()
	var out := _icon
	_icon_mutex.unlock()
	return out


static func info(req: Dictionary, ctx: Dictionary) -> Dictionary:
	return {
		"app": "Polox", "server": str(ctx.get("server", "")), "server_name": str(ctx.get("server_name", "")),
		"engine": str(ctx.get("engine", "built-in")), "pc": str(ctx.get("pc", "")), "build_id": str(ctx.get("build_id", "")),
		"port": int(ctx.get("port", 0)), "your_ip": str(req.get("ip", "")), "host_header": str(req.get("headers", {}).get("host", "")).substr(0, 120),
		"time": Time.get_datetime_string_from_system(true),
	}


static func _plain(code: int, text: String, ctype: String, head: bool) -> Dictionary:
	var resp := HttpUtil.response(code, text.to_utf8_buffer(), ctype)
	if head:
		var end := HttpUtil.header_end(resp)
		resp = resp.slice(0, end + 4)
	return {"bytes": resp, "status": code}


static func esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


## Polox Ping's answer to anything: proof the phone got here, and where to go next.
static func ok_page(req: Dictionary, ctx: Dictionary) -> String:
	var host := esc(str(req.get("headers", {}).get("host", "?")).substr(0, 120))
	var ip := esc(str(req.get("ip", "?")))
	var pc := esc(str(ctx.get("pc", "your PC")))
	return "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Polox OK</title><style>" \
		+ "body{margin:0;padding:24px 18px;font:24px/1.4 -apple-system,system-ui,Roboto,sans-serif;background:#fff;color:#111}" \
		+ "h1{font-size:56px;margin:0 0 8px;color:#1a7f37}.b{font-weight:700}a.btn{display:inline-block;margin:18px 0;padding:18px 22px;background:#1565c0;color:#fff;border-radius:14px;text-decoration:none;font-size:26px;font-weight:700}.s{font-size:18px;color:#555}" \
		+ "</style></head><body><h1>&#10003; Polox OK</h1>" \
		+ "<p>This phone reached <span class=\"b\">" + pc + "</span> at <span class=\"b\">" + host + "</span>.</p>" \
		+ "<p>This phone's address: <span class=\"b\">" + ip + "</span></p>" \
		+ "<p><a class=\"btn\" href=\"/test\">Run the full connection test</a></p>" \
		+ "<p class=\"s\">This is " + esc(str(ctx.get("server_name", "Polox Ping"))) + ", a tiny test server: no game, no pairing, no files. If this page opens but Polox's Phone Link doesn't, the problem is inside Polox. If this page doesn't open, the PC's firewall, the network or the router is in the way.</p>" \
		+ "</body></html>"
