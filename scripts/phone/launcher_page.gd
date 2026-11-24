extends RefCounted
## The Polox Launcher: what a phone sees at the PC's address. Plain HTML and
## JavaScript (no game files, no outside scripts or fonts), so the PIN and the
## worlds list work even when the phone version of the game isn't built.
##
##   Connected to "<PC>"  ->  Enter the PIN shown on your PC (6 digits)
##   ->  Check these words match your PC  ->  Your worlds (cover, name, last played, size)  ->  Play
##   + Forget this phone, Having trouble? (/hello)
##
## The device key goes to localStorage "polox_token" (the game reads it from
## there) once the words were checked, with "polox_sig" = "1": from then on every
## request is signed (sigHeader, request_sig.gd) and the key itself never travels.
## Covers are fetched that way and shown as blob: URLs (an <img> can't sign).
## The PIN never travels readable: it is sealed to the PC's key (pair_v:1,
## pairing.gd) and the key comes back encrypted. Only a browser without BigInt
## pairs the old way (the PIN in the POST body, the key as a Bearer header).
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
.words { font-size: 30px; font-weight: 700; color: var(--yellow); text-align: center; margin: 14px 0; overflow-wrap: anywhere; }
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
  <section id="s-verify" class="hide">
    <h2>Check these words match your PC</h2>
    <p id="words" class="words"></p>
    <p>Your PC's Phone Link screen shows three words now. If they are different, something on the network may be in between: tap They don't match.</p>
    <button id="vyes" class="main" type="button">They match</button>
    <button id="vno" type="button">They don't match</button>
  </section>
  <section id="s-worlds" class="hide">
    <h2>Your worlds</h2>
    <div id="worlds"><p>Loading...</p></div>
    <p id="playmsg" class="msg" role="status"></p>
  </section>
  <section id="s-down" class="hide">
    <div class="big">🌙</div>
    <h2>Can't reach your PC</h2>
    <p id="downmsg">Is Phone Link still on, and is this phone on the same Wi-Fi?</p>
    <button id="retry" class="main" type="button">Try again</button>
  </section>
</div>
<div class="foot">
  <button id="forget" class="small hide" type="button">Forget this phone</button>
  <a class="btn small" href="/app">Android app</a> <a class="btn small" href="/test">Having trouble? Connection test</a> <a class="btn small" href="/hello">PC details</a> <a class="btn small" href="/reset">Start fresh</a>
</div>
<p id="addr" class="msg hide"></p>
</main>"""

## pair_v:1 in the browser (pairing.gd has the protocol). crypto.subtle is missing on a plain-HTTP
## address, so SHA-256, HMAC, PBKDF2 and the RSA seal are here, on Uint8Arrays, in plain JavaScript.
## BigInt is only ever called (never written as 1n): a browser without it still runs the page and
## pairs the old way. Comparisons are XOR loops; keys, secrets and the PIN's bytes are zeroed after use.
const PAIR_CRYPTO := """
const pairWords = {{WORDS}};
const shaK = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
function pxText(s) { return new TextEncoder().encode(s); }
function pxCat(a, b) { const out = new Uint8Array(a.length + b.length); out.set(a); out.set(b, a.length); return out; }
function pxWipe(a) { if (a && a.fill) a.fill(0); }
function pxHex(a) { let s = ""; for (const b of a) s += (b + 256).toString(16).slice(1); return s; }
function pxUnhex(s) {
  if (s.length % 2 || !/^[0-9a-f]*$/.test(s)) throw new Error("hex");
  const out = new Uint8Array(s.length / 2); for (let i = 0; i < out.length; i++) out[i] = parseInt(s.slice(i * 2, i * 2 + 2), 16); return out;
}
function pxB64(s) { const bin = atob(String(s)); const out = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i); return out; }
function pxRandomHex(n) { const a = new Uint8Array(n); crypto.getRandomValues(a); const s = pxHex(a); pxWipe(a); return s; }
function pxSame(a, b) {
  let diff = a.length ^ b.length; const n = Math.max(a.length, b.length);
  for (let i = 0; i < n; i++) diff |= (i < a.length ? a.charCodeAt(i) : 0) ^ (i < b.length ? b.charCodeAt(i) : 0);
  return diff === 0;
}
function pxSha256(input) {
  const bits = input.length * 8, total = Math.ceil((input.length + 9) / 64) * 64, bytes = new Uint8Array(total);
  bytes.set(input); bytes[input.length] = 128; const view = new DataView(bytes.buffer);
  view.setUint32(total - 8, Math.floor(bits / 4294967296), false); view.setUint32(total - 4, bits >>> 0, false);
  const h = new Uint32Array([0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]);
  const w = new Uint32Array(64), rotr = (x, n) => (x >>> n) | (x << (32 - n));
  for (let off = 0; off < total; off += 64) {
    for (let i = 0; i < 16; i++) w[i] = view.getUint32(off + i * 4, false);
    for (let i = 16; i < 64; i++) { const x = w[i - 15], y = w[i - 2]; w[i] = (w[i - 16] + (rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3)) + w[i - 7] + (rotr(y, 17) ^ rotr(y, 19) ^ (y >>> 10))) >>> 0; }
    let a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], q = h[7];
    for (let i = 0; i < 64; i++) {
      const t1 = (q + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + shaK[i] + w[i]) >>> 0;
      const t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) >>> 0;
      q = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    h[0] = (h[0] + a) >>> 0; h[1] = (h[1] + b) >>> 0; h[2] = (h[2] + c) >>> 0; h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0; h[5] = (h[5] + f) >>> 0; h[6] = (h[6] + g) >>> 0; h[7] = (h[7] + q) >>> 0;
  }
  const out = new Uint8Array(32), result = new DataView(out.buffer); for (let i = 0; i < 8; i++) result.setUint32(i * 4, h[i], false);
  pxWipe(bytes); pxWipe(w); pxWipe(h); return out;
}
function pxHmac(key, message) {
  const k = key.length > 64 ? pxSha256(key) : key;
  const innerPad = new Uint8Array(64), outerPad = new Uint8Array(64);
  for (let i = 0; i < 64; i++) { const b = i < k.length ? k[i] : 0; innerPad[i] = b ^ 0x36; outerPad[i] = b ^ 0x5c; }
  const innerIn = pxCat(innerPad, message), inner = pxSha256(innerIn), outerIn = pxCat(outerPad, inner), out = pxSha256(outerIn);
  pxWipe(innerPad); pxWipe(outerPad); pxWipe(innerIn); pxWipe(inner); pxWipe(outerIn); if (k !== key) pxWipe(k); return out;
}
function pxPbkdf2(password, salt, iterations) {
  if (!Number.isInteger(iterations) || iterations < 10000 || iterations > 100000) throw new Error("iter");
  const first = pxCat(salt, new Uint8Array([0, 0, 0, 1]));
  let u = pxHmac(password, first); const t = u.slice(); pxWipe(first);
  for (let i = 1; i < iterations; i++) { const next = pxHmac(password, u); for (let j = 0; j < 32; j++) t[j] ^= next[j]; pxWipe(u); u = next; }
  pxWipe(u); return t;
}
function pxDer(b, at) {
  if (at + 2 > b.length) throw new Error("der");
  let len = b[at + 1], p = at + 2;
  if (len > 127) { const n = len - 128; if (n < 1 || n > 3) throw new Error("der"); len = 0; for (let i = 0; i < n; i++) len = len * 256 + b[p++]; }
  if (p + len > b.length) throw new Error("der");
  return { tag: b[at], start: p, end: p + len };
}
function pxRsaKey(spki) {
  const top = pxDer(spki, 0), alg = pxDer(spki, top.start), oid = pxDer(spki, alg.start), bits = pxDer(spki, alg.end);
  if (top.tag !== 48 || top.end !== spki.length || alg.tag !== 48 || oid.tag !== 6 || bits.tag !== 3 || spki[bits.start] !== 0) throw new Error("der");
  if (pxHex(spki.slice(oid.start, oid.end)) !== "2a864886f70d010101") throw new Error("der");
  const seq = pxDer(spki, bits.start + 1), n = pxDer(spki, seq.start), e = pxDer(spki, n.end);
  if (seq.tag !== 48 || n.tag !== 2 || e.tag !== 2) throw new Error("der");
  let nb = spki.slice(n.start, n.end); while (nb.length > 0 && nb[0] === 0) nb = nb.slice(1);
  const key = { n: BigInt("0x" + pxHex(nb)), e: BigInt("0x" + pxHex(spki.slice(e.start, e.end))), size: nb.length };
  if (key.size !== 256 || nb[0] < 128 || key.e !== BigInt(65537)) throw new Error("rsa");
  return key;
}
function pxModPow(base, exp, mod) {
  const zero = BigInt(0), one = BigInt(1), two = BigInt(2);
  let r = one, b = base % mod, e = exp;
  while (e > zero) { if (e % two === one) r = r * b % mod; e = e / two; b = b * b % mod; }
  return r;
}
function pxSeal(key, message) {
  const k = key.size, ps = k - 3 - message.length; if (ps < 8) throw new Error("long");
  const em = new Uint8Array(k), pad = new Uint8Array(ps), one = new Uint8Array(1); em[1] = 2; crypto.getRandomValues(pad);
  for (let i = 0; i < ps; i++) { while (pad[i] === 0) { crypto.getRandomValues(one); pad[i] = one[0]; } em[2 + i] = pad[i]; }
  em.set(message, 3 + ps);
  const c = pxModPow(BigInt("0x" + pxHex(em)), key.e, key.n).toString(16);
  pxWipe(em); pxWipe(pad); pxWipe(one);
  return c.padStart(k * 2, "0");
}
function pairCan(cap) {
  return !!cap && cap.pair_v === 1 && cap.kdf === "pbkdf2-sha256" && cap.seal === "rsa2048-pkcs1v15" && typeof BigInt === "function"
    && typeof TextEncoder === "function" && typeof atob === "function" && !!(window.crypto && crypto.getRandomValues);
}
function pairSeal(cap, pin) {
  const salt = String(cap.salt || "").toLowerCase(), iter = Number(cap.iter);
  if (!/^[0-9a-f]{32}$/.test(salt) || !Number.isInteger(iter) || iter < 10000 || iter > 100000 || typeof cap.pub !== "string") throw new Error("shape");
  const spki = pxB64(cap.pub), key = pxRsaKey(spki), fp = pxHex(pxSha256(spki)), nonce = pxRandomHex(16), secret = pxRandomHex(32);
  const message = pxText("pair1|" + salt + "|" + nonce + "|" + secret + "|" + pin), sealed = pxSeal(key, message);
  pxWipe(message);
  return { salt: salt, iter: iter, nonce: nonce, secret: secret, fp: fp, sealed: sealed };
}
function pairPhrase(token, fp) {
  const t = pxText(token), mac = pxHmac(t, pxText("polox verify v1|" + fp)), words = [];
  for (let i = 0; i < 3; i++) words.push(pairWords[mac[i] % 64]);
  pxWipe(t); pxWipe(mac); return words.join(" ");
}
function pairKey(pin, w) {
  const pinBytes = pxText(pin), saltBytes = pxUnhex(w.salt), stretched = pxPbkdf2(pinBytes, saltBytes, w.iter), secret = pxUnhex(w.secret), key = pxHmac(secret, stretched);
  pxWipe(pinBytes); pxWipe(saltBytes); pxWipe(stretched); pxWipe(secret); return key;
}
function pairOpen(j, pin, w) {
  const ct = String(j.ct || "").toLowerCase(), tag = String(j.tag || "").toLowerCase();
  if (j.pair_v !== 1 || j.token !== undefined || !/^[0-9a-f]{128}$/.test(ct) || !/^[0-9a-f]{32}$/.test(tag)) throw new Error("shape");
  const key = pairKey(pin, w), label = w.iter + "|" + w.salt + "|" + w.nonce + "|", mac = pxHmac(key, pxText("tag|1|" + label + ct)), expected = pxHex(mac).slice(0, 32);
  pxWipe(mac);
  if (!pxSame(expected, tag)) { pxWipe(key); throw new Error("verify"); }
  const plain = pxUnhex(ct); let offset = 0;
  for (let block = 0; offset < 64; block++) {
    const stream = pxHmac(key, pxText("enc|1|" + label + block));
    for (let i = 0; i < 32 && offset < 64; i++, offset++) plain[offset] ^= stream[i];
    pxWipe(stream);
  }
  let token = ""; for (const b of plain) token += String.fromCharCode(b);
  pxWipe(key); pxWipe(plain); w.secret = "";
  if (!/^[0-9a-f]{64}$/.test(token)) throw new Error("token");
  const phrase = pairPhrase(token, w.fp);
  if (typeof j.phrase === "string" && !pxSame(j.phrase, phrase)) throw new Error("phrase");
  return { token: token, phrase: phrase };
}
let clockOffset = 0;   // the PC's clock minus this phone's (seconds), from the PC's answers (request_sig.gd)
function sigClock(j) { if (j && typeof j.now === "number" && j.now > 1000000000) clockOffset = Math.round(j.now - Date.now() / 1000); }
function sigDecode(s) { try { return decodeURIComponent(s.split("+").join(" ")); } catch (e) { return s; } }
function sigTarget(url) {
  const q = url.indexOf("?"), map = {};
  if (q >= 0) for (const part of url.slice(q + 1).split("&")) {
    if (!part) continue;
    const e = part.indexOf("=");
    map[pxHex(pxText(sigDecode(e < 0 ? part : part.slice(0, e))))] = pxHex(pxText(sigDecode(e < 0 ? "" : part.slice(e + 1))));
  }
  return pxHex(pxText(sigDecode(q < 0 ? url : url.slice(0, q)))) + "?" + Object.keys(map).sort().map((k) => k + "=" + map[k]).join("&");
}
function sigMake(token, method, url, body) {
  const ts = Math.floor(Date.now() / 1000) + clockOffset, nonce = pxRandomHex(16), t = pxText(token), key = pxSha256(t), b = pxText(body || "");
  const mac = pxHmac(key, pxText("polox-sig|1|" + method.toUpperCase() + "|" + sigTarget(url) + "|" + ts + "|" + nonce + "|" + pxHex(pxSha256(b))));
  const sig = pxHex(mac); pxWipe(t); pxWipe(key); pxWipe(b); pxWipe(mac);
  return { header: "Polox-Sig v=1,ts=" + ts + ",nonce=" + nonce + ",sig=" + sig, nonce: nonce };
}
function sigHeader(token, method, url, body) { return sigMake(token, method, url, body).header; }
function sigRequired(url) { const p = url.split("?")[0]; return p.indexOf("/api/") === 0 && p !== "/api/pairing" && p !== "/api/pair" && p !== "/api/report"; }
function sigAnswer(token, nonce, status, header, bytes) {
  // The PC signs its answers to signed requests (X-Polox-Sig, request_sig.gd): no 2xx is used without it.
  const m = /^v=1,sig=([0-9a-f]{64})$/.exec(String(header || "").trim());
  if (!m) return status >= 400;
  const t = pxText(token), key = pxSha256(t), mac = pxHmac(key, pxText("polox-resp|1|" + nonce + "|" + status + "|" + pxHex(pxSha256(bytes))));
  const ok = pxSame(pxHex(mac), m[1]); pxWipe(t); pxWipe(key); pxWipe(mac); return ok;
}
"""


const SCRIPT := """
{{PAIR_CRYPTO}}
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
  for (const s of ["s-pin", "s-verify", "s-worlds", "s-down"]) $(s).classList.toggle("hide", s !== which);
  $("forget").classList.toggle("hide", which !== "s-worlds");
}
function token() { return store.get("polox_token"); }
function signs() { return store.get("polox_sig") === "1"; }   // paired with pair_v:1: sign, never send the key
function keep(t, signed) { store.set("polox_token", t); store.set("polox_token_at", here); if (signed) store.set("polox_sig", "1"); else store.del("polox_sig"); }
function drop() { store.del("polox_token"); store.del("polox_sig"); }
async function api(path, opts) {
  opts = opts || {};
  const method = (opts.method || "GET").toUpperCase();
  const send = async () => {
    const h = Object.assign({}, opts.headers || {}), t = token(), signed = t && signs() ? sigMake(t, method, path, opts.body) : null;
    if (signed) h["Authorization"] = signed.header; else if (t) h["Authorization"] = "Bearer " + t;
    if (opts.body) h["Content-Type"] = "application/json";
    const r = await fetch(path, { method: method, body: opts.body, headers: h, cache: "no-store" });
    if (signed && sigRequired(path) && !sigAnswer(t, signed.nonce, r.status, r.headers.get("X-Polox-Sig"), new Uint8Array(await r.clone().arrayBuffer()))) throw new Error("verify");
    return r;
  };
  let r = await send();
  if (r.status === 401 && token() && signs()) {
    // A clock refusal carries the PC's time: sign with it once more. Never forget the key over a clock.
    const j = await r.clone().json().catch(() => ({}));
    if (j.clock) {
      sigClock(j); r = await send();
      const k = await r.clone().json().catch(() => ({}));
      if (r.status === 401 && k.clock) throw new Error("clock");
    }
  }
  return r;
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
    const r = await (await api("/api/pairing?wrap=1")).json();
    pairCap = r; sigClock(r);
    if (r.paused) { $("pin").disabled = true; $("pinbtn").disabled = true;
      $("pinmsg").textContent = "Pairing is paused after too many wrong PINs. On the PC press Unlock pairing, then reload this page."; return; }
    if (r.cooldown > 0) { cooldown(r.cooldown); return; }
  } catch (e) {}
  $("pin").disabled = false; $("pinbtn").disabled = false;
  setTimeout(() => $("pin").focus(), 50);
}
let sending = false;
let pairCap = null;    // the PIN screen's /api/pairing?wrap=1 answer (salt and iter for this PIN)
let pending = null;    // a key that arrived, kept only in memory until the words are checked
const notVerified = "Response didn't verify: possible interference. Nothing was saved on this phone. On the PC, forget any phone you don't know, then type the new PIN.";
function interference() {
  $("pin").value = ""; $("pinmsg").classList.add("bad"); $("pinmsg").textContent = notVerified;
}
async function sendPin() {
  const pin = $("pin").value.replace(/[^0-9]/g, "");
  if (pin.length !== 6 || sending) { $("pinmsg").textContent = "The PIN has 6 digits."; return; }
  sending = true;
  $("pinmsg").classList.remove("bad");
  $("pinmsg").textContent = "Checking...";
  store.set("polox_name", $("name").value);
  try {
    // Asked again now: the salt belongs to the PIN on the PC's screen, which may have changed since.
    // No answer is an error, never a reason to send the PIN the old way.
    let cap = null;
    try { cap = await (await api("/api/pairing?wrap=1")).json(); } catch (e) { cap = null; }
    if (!cap || typeof cap !== "object") { $("pinmsg").textContent = "Couldn't reach your PC. Is Phone Link still on?"; sending = false; return; }
    pairCap = cap; sigClock(cap);
    const body = { device: $("name").value, client: clientId() };
    let wrap = null;
    if (pairCan(pairCap)) {
      try { wrap = pairSeal(pairCap, pin); } catch (e) { interference(); sending = false; return; }
      body.pair_v = 1; body.salt = wrap.salt; body.nonce = wrap.nonce; body.sealed = wrap.sealed;
    } else {
      body.code = pin;   // an old browser (no BigInt): the old way
    }
    const r = await api("/api/pair", { method: "POST", body: JSON.stringify(body) });
    const j = await r.json();
    $("pin").value = "";
    if (j.ok && wrap) {
      let opened = null;
      try { opened = pairOpen(j, pin, wrap); } catch (e) { opened = null; }
      if (opened) { showWords(opened); } else { interference(); }
    }
    else if (j.ok) { keep(j.token, false); await showWorlds(); }
    else if (r.status === 409 && j.stale_salt) { await showPin("The PC has a new PIN. Type the new PIN shown on your PC."); }
    else if (r.status === 429) { cooldown(j.retry_after || 60); }
    else if (r.status === 423) { $("pin").disabled = true; $("pinbtn").disabled = true; $("pinmsg").textContent = j.error; }
    else { $("pinmsg").textContent = j.error + (j.tries_left ? " " + j.tries_left + (j.tries_left === 1 ? " try" : " tries") + " left before a short wait." : ""); }
  } catch (e) { $("pinmsg").textContent = "Couldn't reach your PC. Is Phone Link still on?"; }
  sending = false;
}
function showWords(opened) {
  pending = opened;
  $("words").textContent = opened.phrase;
  show("s-verify");
  $("vyes").focus();
}
$("vyes").onclick = async () => {
  if (!pending) return;
  keep(pending.token, true); pending = null;
  await showWorlds();
};
$("vno").onclick = async () => {
  const p = pending; pending = null;
  if (p) {
    try { await fetch("/api/unpair", { method: "POST", body: "{}", cache: "no-store", headers: { "Authorization": sigHeader(p.token, "POST", "/api/unpair", "{}"), "Content-Type": "application/json" } }); } catch (e) {}
  }
  await showPin("Those words didn't match, so this pairing was removed. On the PC, forget any phone you don't know, then type the new PIN.");
  $("pinmsg").classList.add("bad");
};
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
function down(e) {
  show("s-down");
  $("downmsg").textContent = e && e.message === "verify"
    ? "The PC's answer didn't verify: something on the network may be changing it. Try again; if it keeps happening, use Tailscale."
    : "Is Phone Link still on, and is this phone on the same Wi-Fi?";
}
async function showWorlds() {
  show("s-worlds");
  let r;
  try { r = await api("/api/worlds"); } catch (e) { down(e); return; }
  if (r.status === 401) { drop(); showPin("This phone was forgotten on the PC (or its key ran out). Type the PIN to pair again: your saves stay."); return; }
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
    if (r.status === 401) { drop(); showPin("Type the PIN to pair again."); return; }
    const j = await r.json();
    if (!j.ok) { $("playmsg").textContent = j.error || "That world isn't available."; return; }
    if (!j.game_ok) { $("playmsg").classList.add("bad"); $("playmsg").textContent = j.why + " Your worlds are safe."; return; }
    store.set("polox_slot", id);
    location.href = j.play;
  } catch (e) { down(e); }
}
$("forget").onclick = async () => {
  if (!confirm("Forget this phone? You can pair it again any time with the PIN. Your worlds stay on the PC.")) return;
  try { await api("/api/unpair", { method: "POST", body: "{}" }); } catch (e) {}
  drop(); store.del("polox_slot");
  showPin("This phone is forgotten. Type the PIN to pair again.");
};
$("retry").onclick = () => start();
async function start() {
  if (info.always_ask) drop();   // "Always ask for PIN": a fresh key every visit
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
		+ "<script>" + page_script() + "</script></body></html>")


## The page's JavaScript with the pairing helpers in it (the check words come from pairing.gd,
## so both ends always use the same list).
static func page_script() -> String:
	var Pairing := preload("res://scripts/phone/pairing.gd")
	return SCRIPT.replace("{{PAIR_CRYPTO}}", PAIR_CRYPTO.replace("{{WORDS}}", JSON.stringify(Pairing.VERIFY_WORDS)))
