extends RefCounted
## /hello: a tiny page any browser can open (no Godot, no game files) that
## says "Polox host reachable", the address you used, the mode, whether the
## phone version is there, and buttons back to the launcher or the game. It
## separates network problems ("can't reach the PC") from game problems
## ("reached it, but the game won't start"). /hello.json is the same for
## scripts and the Doctor: in full (addresses, Tailscale name, app version)
## only for this PC itself or a paired phone's key; anyone else on the network
## gets {ok, app, version, build_id, pc_name, mode, pair_v?}, which finding the
## PC needs. Nothing secret is on either.

const LauncherPage := preload("res://scripts/phone/launcher_page.gd")

const SCRIPT := """
const info = JSON.parse(document.getElementById('info').textContent);
const here = location.protocol + '//' + location.host;
document.getElementById('addr').textContent = here;
document.getElementById('sec').textContent = window.isSecureContext ? 'yes (HTTPS or this PC)' : 'no (plain HTTP: fine, Polox handles it)';
const warn = document.getElementById('warn');
if (info.canonical && info.canonical !== here && (info.urls || []).indexOf(here) < 0) {
  warn.textContent = 'Heads up: the main address of your PC for Polox is ' + info.canonical + '. Use that one every time: the phone keeps its pairing and saves separately for each address.';
  warn.classList.remove('hide');
}
const t0 = performance.now();
fetch('/hello.json', { cache: 'no-store' }).then(r => r.json()).then(j => {
  document.getElementById('ping').textContent = Math.round(performance.now() - t0) + ' ms';
}).catch(() => { document.getElementById('ping').textContent = 'failed'; });
const tok = localStorage.getItem('polox_token');
document.getElementById('paired').textContent = tok ? 'this browser has a pairing key for this address' : 'not paired at this address yet';
"""


## info: {version, build_id, mode, mode_label, canonical, has_game, game_current, game_mb}
static func html(info: Dictionary) -> String:
	var game := "missing: build the phone version on the PC (Settings > Phone Link, step 1)"
	if bool(info.get("has_game", false)):
		game = "ready (%.1f MB)" % float(info.get("game_mb", 0.0)) + ("" if bool(info.get("game_current", true)) else ", but older than the PC's Polox: rebuild it on the PC")
	var buttons := '<a class="btn main" href="/">Back to Polox (PIN and worlds)</a><a class="btn" href="/test">Run the connection test</a><a class="btn" href="/reset">Start fresh on this phone</a>'
	if bool(info.get("has_game", false)):
		buttons += '<a class="btn" href="' + str(info.get("game_path", "/")) + 'index.html">Load the game directly</a>'
	var safe := JSON.stringify({"canonical": str(info.get("canonical", "")), "urls": info.get("urls", [])}).replace("<", "\\u003c")
	return """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="referrer" content="no-referrer"><title>Polox host</title><style>%s
main { background: #1d1736; border: 3px solid #f3e9d2; border-radius: 18px; padding: 20px; }
dl { margin: 10px 0; } dt { color: #b8aed6; font-size: 15px; margin-top: 8px; } dd { margin: 0; word-break: break-all; }
.ok { color: #7ee0a7; font-size: 24px; margin: 4px 0 10px; } #warn { color: #ffd166; }</style></head><body><main>
<h1>Polox</h1><p class="ok">&#10003; Polox host reachable</p>
<dl><dt>Address you used</dt><dd id="addr"></dd>
<dt>Mode</dt><dd>%s</dd>
<dt>Secure page</dt><dd id="sec"></dd>
<dt>Round trip</dt><dd id="ping">...</dd>
<dt>Phone version of the game</dt><dd>%s</dd>
<dt>Pairing</dt><dd id="paired"></dd>
<dt>Polox</dt><dd>%s (build %s)</dd></dl>
<p id="warn" class="hide"></p>%s
<script type="application/json" id="info">%s</script><script>%s</script></main></body></html>""" % [
		LauncherPage.STYLE, _esc(str(info.get("mode_label", ""))), _esc(game), _esc(str(info.get("version", ""))),
		_esc(str(info.get("build_id", "")).substr(0, 8)), buttons, safe, SCRIPT]


static func json(info: Dictionary, full: bool = false) -> String:
	var brief := {
		"ok": true, "app": "Polox", "version": str(info.get("version", "")), "build_id": str(info.get("build_id", "")),
		"pc_name": str(info.get("pc_name", "")), "mode": str(info.get("mode", "")),
	}
	if int(info.get("pair_v", 0)) == 1:
		brief["pair_v"] = 1
	if not full:
		return JSON.stringify(brief)
	brief.merge({
		"canonical": str(info.get("canonical", "")), "urls": info.get("urls", []),
		"lan_url": str(info.get("lan_url", "")), "ts_url": str(info.get("ts_url", "")),
		"app_version": str(info.get("apk", {}).get("version", "")), "app_code": int(info.get("apk", {}).get("version_code", 0)),
		"web_build": bool(info.get("has_game", false)), "web_build_current": bool(info.get("game_current", true)),
	}, true)
	return JSON.stringify(brief)


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
