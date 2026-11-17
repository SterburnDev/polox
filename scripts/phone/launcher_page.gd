extends RefCounted
## The Polox Launcher: what a phone sees at the PC's address. Plain HTML and
## JavaScript (no game files, no outside scripts or fonts), so the PIN and the
## worlds list work even when the phone version of the game isn't built.
##
##   Connected to "<PC>"  ->  Enter the PIN shown on your PC (6 digits)
##   ->  Your worlds (cover, name, last played, size)  ->  Play
##   + Forget this phone, Having trouble? (/hello)
##
## The device key goes to localStorage "polox_token" (the game reads it from
## there); covers are fetched with the key and shown as blob: URLs (an <img>
## can't send it). The PIN only ever travels in a POST body, never a URL.
## Built with replace(), not "%": the CSS and JS are full of percent signs.
## No backslashes in the JS either (GDScript would eat them).
## Tags: [PAIRING]

const STYLE := """
:root { color-scheme: dark; --bg: #120e24; --panel: #1d1736; --cream: #f3e9d2; --muted: #b8aed6; --yellow: #ffd166; --mint: #7ad6b0; --rose: #e86a8a; }
* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; background: var(--bg); color: var(--cream);
  font: 18px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif;
  padding: max(16px, env(safe-area-inset-top)) 16px max(24px, env(safe-area-inset-bottom)); }
main { width: 100%; max-width: 460px; margin: 0 auto; }
.card { background: var(--panel); border: 3px solid var(--cream); border-radius: 18px; padding: 20px; margin: 0 0 16px; }
h1 { color: var(--yellow); font-size: 30px; margin: 4px 0 2px; letter-spacing: 1px; }
h2 { color: var(--yellow); font-size: 24px; margin: 0 0 8px; }
p { color: var(--muted); margin: 8px 0 12px; }
.conn { color: var(--mint); font-size: 16px; margin: 0 0 14px; }
.conn b { color: var(--cream); }
label { display: block; margin: 12px 0 6px; color: var(--cream); }
input { width: 100%; font-size: 34px; letter-spacing: 10px; text-align: center; padding: 12px 6px; border-radius: 14px;
  border: 3px solid var(--muted); background: var(--bg); color: var(--cream); font-variant-numeric: tabular-nums; }
input:focus { outline: none; border-color: var(--yellow); }
input.name { font-size: 18px; letter-spacing: 0; text-align: left; padding: 10px 12px; }
input:disabled { opacity: 0.5; }
button, a.btn { display: block; width: 100%; min-height: 58px; margin-top: 14px; font-size: 21px; font-weight: 600; border-radius: 16px;
  border: 3px solid var(--cream); background: #2e2552; color: var(--cream); text-align: center; line-height: 52px;
  text-decoration: none; cursor: pointer; font-family: inherit; padding: 0 12px; }
button.main, a.main { background: var(--yellow); color: var(--bg); border-color: var(--yellow); }
button:disabled { opacity: 0.45; }
button.small, a.small { min-height: 46px; line-height: 40px; font-size: 17px; font-weight: 500; }
.msg { min-height: 1.4em; color: var(--yellow); margin: 12px 0 0; }
.bad { color: var(--rose); }
.hide { display: none !important; }
.world { display: grid; grid-template-columns: 96px 1fr; gap: 10px 14px; align-items: center; background: #261f45;
  border: 3px solid var(--accent, var(--muted)); border-radius: 16px; padding: 12px; margin: 12px 0; }
.cover { width: 96px; height: 72px; border-radius: 10px; background: var(--accent, #2e2552); display: flex;
  align-items: center; justify-content: center; font-size: 36px; overflow: hidden; }
.cover img { width: 100%; height: 100%; object-fit: cover; image-rendering: pixelated; }
.winfo { flex: 1; min-width: 0; }
.wname { font-size: 21px; font-weight: 700; color: var(--cream); overflow-wrap: anywhere; line-height: 1.2; margin-bottom: 4px; }
.wmeta { font-size: 15px; color: var(--muted); }
.world button { grid-column: 1 / -1; width: 100%; margin: 2px 0 0; }
.pcnote { background: var(--yellow); color: var(--bg); border-radius: 14px; padding: 14px 16px; margin: 0 0 16px; font-size: 19px; }
.pcnote b { word-break: break-all; }
.foot { display: flex; gap: 10px; }
.foot > * { flex: 1; }
.big { font-size: 64px; text-align: center; margin: 4px 0; }
"""

const BODY := """<main>
{{PCNOTE}}
<div class="card">
  <h1>Polox</h1>
  <p class="conn">● Connected to <b id="pc"></b></p>
  <section id="s-pin" class="hide">
    <h2>Enter the PIN shown on your PC</h2>
    <p>It's on the PC's Phone Link screen (and in the little Polox host window).</p>
    <form id="pinform" autocomplete="off">
      <input id="pin" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="one-time-code" aria-label="PIN" placeholder="------">
      <label for="name">This phone's name</label>
      <input id="name" class="name" maxlength="40">
      <button id="pinbtn" class="main" type="submit">Continue</button>
    </form>
    <p id="pinmsg" class="msg" role="status"></p>
  </section>
  <section id="s-worlds" class="hide">
    <h2>Your worlds</h2>
    <div id="worlds"><p>Loading...</p></div>
    <p id="playmsg" class="msg" role="status"></p>
  </section>
  <section id="s-down" class="hide">
    <div class="big">🌙</div>
    <h2>Can't reach your PC</h2>
    <p>Is Phone Link still on, and is this phone on the same Wi-Fi?</p>
    <button id="retry" class="main" type="button">Try again</button>
  </section>
</div>
<div class="foot">
  <button id="forget" class="small hide" type="button">Forget this phone</button>
  <a class="btn small" href="/app">Android app</a> <a class="btn small" href="/test">Having trouble? Connection test</a> <a class="btn small" href="/hello">PC details</a> <a class="btn small" href="/reset">Start fresh</a>
</div>
<p id="addr" class="msg hide"></p>
</main>"""

const SCRIPT := """
const info = JSON.parse(document.getElementById("info").textContent);
const $ = (id) => document.getElementById(id);
const store = { get: (k) => { try { return localStorage.getItem(k) || ""; } catch (e) { return ""; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch (e) {} },
  del: (k) => { try { localStorage.removeItem(k); } catch (e) {} } };
$("pc").textContent = '"' + (info.pc_name || "your PC") + '"';
const here = location.protocol + "//" + location.host;
if (info.canonical && info.canonical !== here && (info.urls || []).indexOf(here) < 0 && !info.pc) {
  $("addr").textContent = "Polox's main address is " + info.canonical + ". This one works too, but the phone keeps its pairing and saves separately for each address.";
  $("addr").classList.remove("hide");
}
function clientId() {
  let id = store.get("polox_client");
  if (!id) {
    const a = new Uint8Array(8); crypto.getRandomValues(a);
    id = Array.from(a, (b) => (b + 256).toString(16).slice(1)).join("");
    store.set("polox_client", id);
  }
  return id;
}
const ua = navigator.userAgent || "";
$("name").value = store.get("polox_name") || (/iPhone|iPad/.test(ua) ? "iPhone" : /Android/i.test(ua) ? "Android phone" : "My phone");
function show(which) {
  for (const s of ["s-pin", "s-worlds", "s-down"]) $(s).classList.toggle("hide", s !== which);
  $("forget").classList.toggle("hide", which !== "s-worlds");
}
function token() { return store.get("polox_token"); }
async function api(path, opts) {
  opts = opts || {};
  const h = opts.headers || {};
  if (token()) h["Authorization"] = "Bearer " + token();
  if (opts.body) h["Content-Type"] = "application/json";
  opts.headers = h; opts.cache = "no-store";
  return fetch(path, opts);
}
let cooldownTimer = 0;
function cooldown(seconds) {
  clearInterval(cooldownTimer);
  let left = seconds;
  const tick = () => {
    if (left <= 0) { clearInterval(cooldownTimer); $("pin").disabled = false; $("pinbtn").disabled = false;
      $("pinmsg").textContent = "You can try again now."; $("pin").focus(); return; }
    $("pin").disabled = true; $("pinbtn").disabled = true;
    $("pinmsg").textContent = "Too many wrong PINs. Try again in " + left + " s.";
    left -= 1;
  };
  tick(); cooldownTimer = setInterval(tick, 1000);
}
async function showPin(note) {
  show("s-pin");
  $("pinmsg").textContent = note || "";
  $("pinmsg").classList.remove("bad");
  try {
    const r = await (await api("/api/pairing")).json();
    if (r.paused) { $("pin").disabled = true; $("pinbtn").disabled = true;
      $("pinmsg").textContent = "Pairing is paused after too many wrong PINs. On the PC press Unlock pairing, then reload this page."; return; }
    if (r.cooldown > 0) { cooldown(r.cooldown); return; }
  } catch (e) {}
  $("pin").disabled = false; $("pinbtn").disabled = false;
  setTimeout(() => $("pin").focus(), 50);
}
let sending = false;
async function sendPin() {
  const pin = $("pin").value.replace(/[^0-9]/g, "");
  if (pin.length !== 6 || sending) { $("pinmsg").textContent = "The PIN has 6 digits."; return; }
  sending = true;
  $("pinmsg").textContent = "Checking...";
  store.set("polox_name", $("name").value);
  try {
    const r = await api("/api/pair", { method: "POST", body: JSON.stringify({ code: pin, device: $("name").value, client: clientId() }) });
    const j = await r.json();
    $("pin").value = "";
    if (j.ok) { store.set("polox_token", j.token); store.set("polox_token_at", here); await showWorlds(); }
    else if (r.status === 429) { cooldown(j.retry_after || 60); }
    else if (r.status === 423) { $("pin").disabled = true; $("pinbtn").disabled = true; $("pinmsg").textContent = j.error; }
    else { $("pinmsg").textContent = j.error + (j.tries_left ? " " + j.tries_left + (j.tries_left === 1 ? " try" : " tries") + " left before a short wait." : ""); }
  } catch (e) { $("pinmsg").textContent = "Couldn't reach your PC. Is Phone Link still on?"; }
  sending = false;
}
$("pinform").onsubmit = (e) => { e.preventDefault(); sendPin(); };
$("pin").oninput = () => { const v = $("pin").value.replace(/[^0-9]/g, "").slice(0, 6); $("pin").value = v; if (v.length === 6) sendPin(); };
function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text) e.textContent = text; return e; }
async function cover(box, id) {
  try {
    const r = await api("/api/cover?slot=" + encodeURIComponent(id));
    if (!r.ok) return;
    const img = el("img"); img.alt = "";
    img.src = URL.createObjectURL(await r.blob());
    box.textContent = ""; box.appendChild(img);
  } catch (e) {}
}
let game = { ok: true, present: true };
async function showWorlds() {
  show("s-worlds");
  let r;
  try { r = await api("/api/worlds"); } catch (e) { show("s-down"); return; }
  if (r.status === 401) { store.del("polox_token"); showPin("This phone was forgotten on the PC (or its key ran out). Type the PIN to pair again: your saves stay."); return; }
  const j = await r.json();
  game = j.game || game;
  const box = $("worlds"); box.textContent = "";
  if (!j.worlds || j.worlds.length === 0) { box.appendChild(el("p", "", "No worlds are shared with phones yet. On the PC: Save menu, tick Available on phone on a world.")); return; }
  for (const w of j.worlds) {
    const card = el("div", "world"); card.style.setProperty("--accent", w.accent || "#c9b6ff");
    const c = el("div", "cover", w.emoji || "🌙"); card.appendChild(c);
    const i = el("div", "winfo");
    i.appendChild(el("div", "wname", w.name));
    i.appendChild(el("div", "wmeta", (w.last_played ? "Played " + w.ago : "New: not played yet") + " · " + w.size));
    i.appendChild(el("div", "wmeta", w.rooms + (w.rooms === 1 ? " room" : " rooms") + " · " + w.characters + (w.characters === 1 ? " friend" : " friends")));
    card.appendChild(i);
    const b = el("button", "main", "▶ Play"); b.type = "button"; b.dataset.slot = w.id;
    b.onclick = () => play(w.id, w.name);
    card.appendChild(b);
    box.appendChild(card);
    if (w.cover) cover(c, w.id);
  }
}
async function play(id, name) {
  $("playmsg").classList.remove("bad");
  $("playmsg").textContent = "Opening " + name + "...";
  try {
    const r = await api("/api/session", { method: "POST", body: JSON.stringify({ slot: id }) });
    if (r.status === 401) { store.del("polox_token"); showPin("Type the PIN to pair again."); return; }
    const j = await r.json();
    if (!j.ok) { $("playmsg").textContent = j.error || "That world isn't available."; return; }
    if (!j.game_ok) { $("playmsg").classList.add("bad"); $("playmsg").textContent = j.why + " Your worlds are safe."; return; }
    store.set("polox_slot", id);
    location.href = j.play;
  } catch (e) { show("s-down"); }
}
$("forget").onclick = async () => {
  if (!confirm("Forget this phone? You can pair it again any time with the PIN. Your worlds stay on the PC.")) return;
  try { await api("/api/unpair", { method: "POST", body: "{}" }); } catch (e) {}
  store.del("polox_token"); store.del("polox_slot");
  showPin("This phone is forgotten. Type the PIN to pair again.");
};
$("retry").onclick = () => start();
async function start() {
  if (info.always_ask) store.del("polox_token");   // "Always ask for PIN": a fresh key every visit
  if (token()) { await showWorlds(); } else { await showPin(""); }
}
start();
"""


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


## info: refresh_page_info()'s dictionary. `is_pc`: this PC's own browser
## opened localhost, so say where the phone should go instead.
static func html(info: Dictionary, is_pc: bool = false) -> String:
	var pcnote := ""
	var lan := str(info.get("lan_url", ""))
	if is_pc:
		pcnote = "<div class=\"pcnote\" id=\"pcnote\">This is the PC. On your phone open <b>%s</b> (typing localhost on a phone means the phone itself).</div>" % _esc(lan if lan != "" else str(info.get("canonical", "the address on the Phone Link screen")))
	var data := {
		"pc_name": str(info.get("pc_name", "")), "canonical": str(info.get("canonical", "")), "urls": info.get("urls", []),
		"always_ask": bool(info.get("always_ask", false)), "pc": is_pc,
	}
	return ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
		+ "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">"
		+ "<meta name=\"referrer\" content=\"no-referrer\"><meta name=\"theme-color\" content=\"#120e24\">"
		+ "<title>Polox</title><style>" + STYLE + "</style></head><body>"
		+ BODY.replace("{{PCNOTE}}", pcnote)
		+ "<script type=\"application/json\" id=\"info\">" + JSON.stringify(data).replace("<", "\\u003c") + "</script>"
		+ "<script>" + SCRIPT + "</script></body></html>")
