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
| Phone Link files | A paired phone may read or write only the worlds you share with it, by an allow-list of folders and file kinds; absolute paths, `..`, backslashes, drive letters and hidden files are refused; no CORS headers, `X-Frame-Options: DENY`, `nosniff` | `scripts/phone/sync_files.gd`, `scripts/phone/http_util.gd` |
| Imports | World archives (`.polox`, cloud packages) are checked before anything is unpacked: no absolute or `..` paths, file-count and size limits, every file listed and matched by SHA-256 | `scripts/core/slot_archive.gd`, `scripts/sync/cloud_package.gd` |
| Add-ons | Pictures, sounds, words and tiles only, from inside the add-on's own folder. An add-on's scripts never run until you trust them in Title > Add-ons, and that trust is tied to a hash of the scripts: any change asks again | `scripts/core/addons.gd` |
| Links | Only `http(s)` pages open from AI research or synced files | `scripts/home/research_prompt.gd`, `scripts/home/map_home_panel.gd` |

## Known limits

- **Phone Link on Same Wi-Fi is plain HTTP.** Pairing no longer gives anything away to someone who only
  watches the Wi-Fi: the PIN travels sealed to the PC's session key and the token comes back encrypted
  (pair_v:1, above). But every request after pairing still carries the token in an `Authorization`
  header, and worlds, chats and files travel unencrypted, so someone who can watch that network can
  still copy the token from the first later request and read what is synced. Use Same Wi-Fi on a
  network you trust (your home). Away from home, or on any network you share, use the Tailscale modes,
  which are encrypted end to end.
- **Someone who can change traffic on the Wi-Fi** (ARP spoofing, a hostile access point) can still get
  in. They can rewrite the launcher page itself, which plain HTTP can't protect, or relay your PIN to
  the PC as you type it. The three check words make a relay show up as different words on the phone
  and the PC, or as a key that stops working when the phone later talks to the PC directly. Always
  compare the words, and forget any phone you don't recognise. The page-rewriting case is only closed
  by HTTPS (Tailscale Serve).
- **Older Polox apps and browsers without BigInt pair the old way**: the PIN and the token cross the
  network readable. The PC shows "paired the old way" for those. Update the app, then forget and
  re-pair that phone. An app that once paired safely with a PC refuses the old way from that PC.
- `/hello.json` without a key still says that Polox runs here, its version and the PC's name (finding
  the PC needs that). The launcher page and `/hello` still show the PC's addresses, as before.
- **API keys are stored unencrypted** in your data folder, protected by your user account like your other
  files. Don't share that folder, and clear the key in Settings > AI before giving a copy of it away.
- **Builds are not code-signed** unless a release says otherwise, so Windows SmartScreen may warn. Each
  release lists SHA-256 checksums: compare them before running a download.
- An imported world archive is unpacked into memory one file at a time, so a hostile archive can make the
  game run out of memory and close. Nothing is written or run; import only worlds you trust.
