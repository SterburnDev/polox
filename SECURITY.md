# Security

## Reporting a problem

Please report security problems privately, not in a public issue: use **Security > Report a
vulnerability** on the repository's GitHub page. Say what you found, how to reproduce it and which
version (the release you downloaded, or the commit you built) you used. Only the newest release gets fixes.

## What the code enforces

| Area | Rule | Where |
| --- | --- | --- |
| Secrets | No key, password or token is in the repository or in any build. API keys live only in the player's own data folder, go only to their own provider, and are scrubbed from chat logs and error text. The Android signing key and its password stay in the git-ignored `tools/android/` | `scripts/ai/ai_client.gd`, `scripts/ai/key_format.gd`, `.gitignore` |
| Release checks | Every public snapshot is scanned file by file (text and binary) for keys, personal details and the build PC's names and addresses, then by gitleaks; every artifact's pack is checked against an allow-list | `tools/release/make_public_source.py`, `tools/release/verify_pack.py` |
| Phone Link | Off every time Polox starts. Public internet addresses are always refused (a mistaken router port-forward can't reach it). Pairing needs a random 6-digit PIN shown on the PC (10 minutes, single use; 5 wrong tries from one address mean a 60-second wait, and 20 wrong tries in an hour pause pairing until you unlock it on the PC). A paired phone gets a 256-bit random token; the PC stores only its SHA-256 and compares in constant time | `scripts/phone/net_rules.gd`, `scripts/phone/pairing.gd` |
| Phone Link pairing (pair_v:1) | Current apps and browsers seal the PIN (with a fresh 256-bit secret and a nonce) to an RSA-2048 key the PC makes for the session and keeps only in memory. The PIN is never on the network readable, so a capture can't be brute-forced offline, and a seal that doesn't open counts as a wrong PIN under every limit above. The token comes back XORed with an HMAC-SHA256 keystream under a key derived from the secret and the PIN (PBKDF2-HMAC-SHA256, 10,000 to 100,000 iterations, a 16-byte salt made with each PIN), with a 128-bit tag checked in constant time before anything is kept. Both screens show three check words derived from the token and the PC key's fingerprint. A PIN that changed meanwhile is a 409, never a token. Old clients (no `pair_v`) keep the cleartext exchange, and the PC flags those pairings | `scripts/phone/pairing.gd`, `scripts/phone/launcher_page.gd`, `scripts/phone/sync_client.gd` |
| Phone Link requests | A phone that paired with pair_v:1 never sends its token again. Every request carries `Authorization: Polox-Sig` with an HMAC-SHA256, keyed by the SHA-256 of the token (exactly what the PC stores), over the method, the decoded path and every query field, the SHA-256 of the body, a time and a 128-bit nonce. The PC accepts a time within 5 minutes of its own and each nonce once. When the clocks are further apart it answers with its time, and the phone corrects itself. That phone's bare token is refused (`bearer_refused` in the audit log). Phones that paired the old way keep sending `Bearer` | `scripts/phone/request_sig.gd`, `scripts/phone/pairing.gd`, `scripts/phone/phone_api.gd` |
| Phone Link answers | Every answer to a signed request carries `X-Polox-Sig`: an HMAC-SHA256 with the same key over that request's nonce, the status and the SHA-256 of the body, so it can't be changed or moved to another request. The app, the phone game and the launcher use no successful answer from the API or `/hello.json` without a good signature ("didn't verify: possible interference") | `scripts/phone/request_sig.gd`, `scripts/phone/sync_client.gd`, `scripts/phone/launcher_page.gd` |
| Phone Link pages | DNS rebinding: requests whose `Host` is a public name (a web page pointing its own domain at this PC) are refused before anything is served. IP addresses, names without a dot (localhost, the PC's name) and names under local-only suffixes (`.local`, `.lan`, `.home.arpa`, `.box`, `.ts.net`...) are served. The launcher, `/hello` and `/app` pages carry a Content-Security-Policy that allows only their own inline code, no outside scripts, styles or connections, and no framing | `scripts/phone/phone_server.gd` |
| Phone Link files | A paired phone may read or write only the worlds you share with it, by an allow-list of folders and file kinds; absolute paths, `..`, backslashes, drive letters and hidden files are refused; no CORS headers, `X-Frame-Options: DENY`, `nosniff` | `scripts/phone/sync_files.gd`, `scripts/phone/http_util.gd` |
| Imports | World archives (`.polox`, cloud packages) are checked before anything is unpacked: no absolute or `..` paths, no executable or script extensions, file-count and entry/total size limits, every file listed and matched by SHA-256 | `scripts/core/slot_archive.gd`, `scripts/sync/cloud_package.gd` |
| Custom 3D models | Imported `.glb`, `.gltf`, and `.obj` files stay inside `models/`, and runtime parsing enforces cumulative buffer limits, cycle-free node caps, and vertex/index/triangle limits | `scripts/world/custom_models.gd` |
| Add-ons | Pictures, sounds, words and tiles only, from inside the add-on's own folder. An add-on's scripts never run until you trust them in Title > Add-ons, and that trust is tied to a hash of the scripts: any change asks again | `scripts/core/addons.gd` |
| Links | Only clean `http(s)` pages open from AI research or synced files, and external Google Maps URIs are checked against Google Maps HTTPS hosts | `scripts/home/research_prompt.gd`, `scripts/home/map_home_panel.gd`, `scripts/home/map_refs_panel.gd` |

## Known limits

- **Phone Link on Same Wi-Fi is plain HTTP.** For a current phone, someone who only watches the Wi-Fi
  gets no way in: the PIN travels sealed, the token comes back encrypted, and later requests carry
  only signatures that can't be replayed or changed (both rows above). But what is synced still
  travels unencrypted: such a listener can read the worlds, chats and files that go back and forth.
  Use Same Wi-Fi on a network you trust (your home). Away from home, or on any network you share, use
  the Tailscale modes, which are encrypted end to end.
- **Someone who can change traffic on the Wi-Fi** (ARP spoofing, a hostile access point) can still do
  harm in a browser. The launcher page and the phone game's files come over plain HTTP, so they can be
  rewritten, and a rewritten page can skip every check above or relay your PIN to the PC as you type
  it. The Android app's code isn't downloaded over the network: for the app, a changed answer is
  refused and a relay shows up as different check words (or as a key that stops working when the app
  later talks to the PC directly). They can also block or delay traffic. Always compare the words, and
  forget any phone you don't recognise. Only HTTPS (Tailscale Serve) closes the browser cases.
- **Older Polox apps and browsers without BigInt pair the old way**: the PIN and the token cross the
  network readable, and so does the token on every later request (`Bearer`). The PC shows "paired the
  old way" for those. Update the app, then forget and re-pair that phone. An app that once paired
  safely with a PC refuses the old way from that PC.
- Signed requests need the phone's clock within 5 minutes of the PC's, or the phone corrects itself
  from the PC's answer first. A nonce is remembered for 10 minutes (at most 50,000 at once; beyond that
  the PC answers 503 until old ones expire).
- `/hello.json` without a key still says that Polox runs here, its version and the PC's name (finding
  the PC needs that). The launcher page and `/hello` still show the PC's addresses, as before.
- **API keys are stored unencrypted** in your data folder, protected by your user account like your other
  files. Don't share that folder, and clear the key in Settings > AI before giving a copy of it away.
- **Builds are not code-signed** unless a release says otherwise, so Windows SmartScreen may warn. Each
  release lists SHA-256 checksums: compare them before running a download.
- An imported world archive is unpacked into memory one file at a time, so a hostile archive can make the
  game run out of memory and close. Nothing is written or run; import only worlds you trust.
