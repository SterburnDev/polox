# Polox on your phone (Phone Link)

Play the same worlds on your own phone, in its web browser. No app store, no account, nothing to install on
the phone: your PC runs a tiny private web server **only while you switch it on**, your phone types a PIN
once, picks a world and plays. The PC keeps the master copy and the two sync. Friends talk through your PC,
so your AI key never goes to the phone.

Everything below is on **Polox > Menu > Settings > Phone Link**, and **`phone_doctor.bat`** checks the whole
path and says what to fix.

> **Phone can't connect?** Follow **[PHONE_TRIAGE.md](PHONE_TRIAGE.md)** (5 minutes): `ping.bat` (a tiny test
> server that shows whether anything from the phone reaches the PC), the phone's **Connection Test**
> (`<address>/test`), and what to paste back.

---

## Polox for Android (the app)

On Android you can also install Polox as an app (an APK you install yourself: no store, no account). It finds
the PC by itself, plays **offline** with its own copy, and syncs whenever the PC is reachable. iPhones keep the
browser version below (Apple doesn't allow installing apps this way).

**Build it (once, on the PC):** Settings > Phone Link > **Polox for Android** > **Build the app** (about a minute;
needs the Android tools from `tools\get_android_tools.ps1 -AcceptLicenses`). The first build makes this PC's
signing key in `tools\android\` (never committed, never shared). Keep that folder: Android only updates an
installed app with an APK signed by the same key. `tools\export_android.bat` does the same from a terminal.

**Install it**, one of two ways:
- **USB (Install on my phone):** on the phone, Settings > About phone > Software information > tap **Build
  number** 7 times; then Settings > Developer options > **USB debugging** on. Plug the phone in, unlock it, tap
  **Allow** on "Allow USB debugging?", and click **Install on my phone** on the PC. If the phone asks "Install via
  USB?", allow it. (Some Samsung phones need *Auto Blocker* off for USB installs.)
- **Download:** with Phone Link on, open the Launcher on the phone and tap **Android app** (or open
  `<address>/app`), then **Download polox.apk**. Chrome may warn about the file: **Download anyway**. Open it;
  Android says it can't install unknown apps from Chrome: **Settings > Allow from this source**, back,
  **Install**. If Play Protect asks, **More details > Install anyway** (it's your own build).

**Connect it:** open Polox. **Connect to your PC** explains what happens, then listens on your Wi-Fi for the PC
(Phone Link must be on: the PC says "Polox is here" every two seconds, with only its name and port). One PC found
goes straight to its PIN (several: tap yours). Type the PIN on the big keypad or with the phone's own keyboard
(the field under the keypad), or tap **Scan the QR code** and point the camera at Settings > Phone Link >
Polox for Android > **Pair the app** on the PC (that code holds the address and the same PIN; the camera is asked
for only then). Can't hear the PC (guest Wi-Fi, a router that blocks broadcasts)? **Type the address** works too.
After the PIN the app shows **three check words**; the PC's Phone Link screen (or the host window) shows three
words at the same moment. Same words: tap **They match**. Different words: tap **They don't match** (the new
key is forgotten on both sides), forget any phone you don't know on the PC, and pair again.
Skipped this screen? The title screen and Settings both show **Connect to your PC** until the phone is paired.

**Playing:** the app says which path it uses: the **home network**, the **last address** that worked, or
**Tailscale** away from home (Tailscale on the phone and the PC; see below). Without the PC it keeps playing
from its own copy and looks again every minute; it also syncs when you come back to the app. Sync works the same
as in the browser (the PC is the master; conflicts are kept on the PC). **Settings > AI > Check connection**
runs the connection test from inside the app (network, hearing the PC, reaching it, a 20 MB download, pairing,
sync) and sends the result to the PC's Doctor. When the PC has a newer app, the app offers **Update** (the
download opens in the browser and Android installs it over the old one; your worlds stay).

**What the app may do:** the internet permission (to reach your PC), Wi-Fi state and Wi-Fi multicast (to hear
the PC's announcement), and the **camera**, asked for only when you tap Scan. Plain HTTP goes only to
home-network and Tailscale addresses (the app refuses anything else). No notifications (see docs/history/PROGRESS.md).

---

## Same Wi-Fi (no setup)

Your phone and the PC on the same home Wi-Fi (or the PC on a cable to the same router). Nothing else.

1. **PC:** Settings > Phone Link > switch **Phone Link ON**. It shows, big:
   - the address, e.g. **`http://192.168.1.42:8765`**, with a QR code,
   - a **PIN**, e.g. **482 913**, with a countdown (a new PIN every 10 minutes and after each pairing).
2. **Phone:** open the browser and type that address exactly (or scan the QR code). **Don't type
   `localhost`**: on a phone that means the phone itself.
3. The phone shows **Polox: Connected to "DESKTOP-..."** and **Enter the PIN shown on your PC**. On the PC a
   banner pops up over whatever you're doing: **📱 Phone connecting: PIN 482 913**.
4. Type the PIN. The phone shows **Check these words match your PC** with three words, and the PC shows
   three words too (Phone Link screen, the banner, the host window). Same words: **They match**, and the phone
   shows **Your worlds** (cover, name, last played, size). The PIN never crosses the Wi-Fi readable: the
   phone seals it to a key the PC made for this session, and the phone's new key comes back encrypted.
5. Tap **Play** on a world. The game loads (the first time ~10 MB, a few seconds), copies that world from the
   PC and starts in it.
6. Optional: Chrome ⋮ > **Add to Home screen** while you're on the worlds list, for a full-screen icon.

Next time: open the address (or the icon) and you're straight on **Your worlds**: the phone is remembered
until you press **Forget** on the PC (or **Forget this phone** on the phone). Settings > Phone Link >
*Always ask for the PIN* makes it ask every visit instead.

**Which worlds:** every world except the ones you switch off: Save menu > a world's **⋯** > untick
**📱 Available on phone**.

**Phone Link uses port 8765** (a fixed, browser-safe port; if another program has it, 8766, 8767, 8080 or 8888,
and the one that worked is remembered). Before 1.5 it was 8737: open the new address on the phone, and run
`allow_phone_link.bat` once so Windows lets the new port in.

**Windows may ask once** "Allow Polox on networks?": click **Allow**. If that prompt was dismissed earlier,
Windows silently blocks phones: double-click **`allow_phone_link.bat`** once (it shows what it changes, asks
for administrator rights, waits for you to type Y, and can be undone with `allow_phone_link.bat remove`).
Polox never changes the firewall by itself.

**No phone after a minute?** The Phone Link screen shows a checklist (same Wi-Fi? exact address? Windows
firewall? guest network / client isolation? PC asleep?) and runs the Doctor for you.

### Just the server: `host.bat`

Double-click **`host.bat`** to run Phone Link without the game: a small window shows the address, the QR
code, the PIN and *Phone connected* (the console prints the same). Close it to switch Phone Link off.

## Tailscale: away from home, and when your Wi-Fi keeps devices apart

[Tailscale](https://tailscale.com) makes a private network between your own devices (free for personal use).
The phone reaches Tailscale, and Tailscale talks to Polox **on the PC itself** (127.0.0.1), so Windows Firewall
and Wi-Fi "client isolation" don't matter: it's the sure path when Same Wi-Fi won't work. It only **adds** a way
in: Same Wi-Fi keeps working alongside.

On the Phone Link screen, open **Tailscale** and follow its three steps (each one says plainly what's missing):

1. **Install Tailscale on this PC and on your phone, and sign in with the same account.** (This PC is
   `example-pc`; your phone is on your tailnet.) The screen says if Tailscale isn't installed, isn't
   signed in, or no phone is on your tailnet (or it's offline right now).
2. **Press Enable.** Polox asks Tailscale to serve it privately. If your tailnet still needs **HTTPS
   Certificates** (admin page > DNS) or Tailscale's one-time OK, the screen opens the right page.
3. **On the phone (Tailscale on), open the https address shown** (QR code), e.g.
   `https://example-pc.tailnet-example.ts.net:8765`. Same launcher, same PIN, same worlds.

Polox uses its **own** Serve port (8765; it was 8737 before 1.5), never touches your other Serve mappings (yours on 443 and 8443 stay
as they are), removes only its own mapping when you switch Phone Link off, and **never uses Tailscale
Funnel** (the public internet). By default only **your own Tailscale login** may use the https address.
Settings > Phone Link > **Advanced** lets you pick the mode by hand (Same Wi-Fi only / + Tailscale HTTPS /
+ Tailscale HTTP) and has *Tailscale only* (refuses Wi-Fi phones: leave it off unless you mean it).

## Keep the same address

The phone's browser keeps Polox's key and saves **per address**: the Wi-Fi address and the Tailscale
address are two separate "sites" to it. Each asks for the PIN once. Moving is safe: the first sync at a new
address brings everything from the PC.

**iPhone:** an icon added to the Home Screen has its **own storage**, separate from Safari: type the PIN
inside the Home Screen icon. Safari also clears data of sites you haven't opened for about a week; Polox then
asks for the PIN again and the first sync brings everything back (the PC is the master copy).

## Playing on the phone

- **Tap** to walk, talk and press buttons. **Long-press** = back (or the menu when nothing is open).
- **Pinch** to zoom, **slide two fingers sideways** to turn the camera.
- **Bag** and **Menu** sit under your thumb (Settings > Comfort > *I play with my left hand* swaps the
  corners).
- **Chatting:** a text bar with its own **Send** button appears at the bottom, so the phone keyboard always
  opens. **Gift**, **★ Save** and **Bye** are in the chat box.
- **Performance mode** is on automatically on phones (30 fps, no real-time shadows, smaller pictures).
- The phone is intended for play, chat, inventory, gifting and light room edits. For smart tiles, layer/event setup, or large tile-painting sessions, use the PC editor; those saved room changes sync to the phone on the next sync.

### Sync (the PC is the master)

- The phone fetches the latest from the PC when Polox opens, sends its changes ~15 seconds after you do
  something, and again whenever you leave the page (switch apps, lock the phone). The first sync copies the
  whole world (a few seconds); after that only what changed moves. Every file is checked by its SHA-256.
- The **☁ chip** at the top shows the state: *Synced 10:42*, *Syncing*, *PC offline*, *Not paired*,
  *1 conflict*. Tap it to sync now.
- It syncs the **Library** (tile sets, your templates, doll presets) and **the world you picked** on the
  worlds list. **Settings and your API key never go to the phone.**
- Before the phone changes a world on the PC, the PC saves a snapshot zip of it; the phone also snapshots
  its copy before taking the PC's changes.
- **Conflicts:** if the same file changed on both, the PC's version stays and the phone's is kept in
  `slots\<world>\conflicts\`; the Worlds screen shows **⚠ phone conflicts** and lets you pick. Chat logs
  never conflict (both sides' messages are merged).
- **PC off or asleep?** You keep playing with gentle offline lines; it all syncs next time. Settings > Phone
  Link > Advanced > **Keep this PC awake** stops the PC from sleeping while Phone Link is on.

## When something doesn't work

Start with **[PHONE_TRIAGE.md](PHONE_TRIAGE.md)**. In short: **`ping.bat`** shows whether anything from the phone
reaches the PC at all (it lists every contact, or says "No device has contacted Polox Ping yet"), and the phone's
**Connection Test** (`<address>/test`) checks each step from the phone and sends its report to the PC.

Run **`phone_doctor.bat`** (or Settings > Phone Link > Advanced > **Phone Link Doctor**). It checks the phone
version, Phone Link, every address (with real requests, including the https address), the firewall,
Tailscale, Serve and Funnel, pairing and the last phone contact, and says what to fix. **Copy diagnostics**
(or `PersonalData\phone\diagnostics.txt`) is safe to paste when asking for help: no keys, tokens, codes
or chats.

| On the phone | What it means | Fix |
|---|---|---|
| A card "Polox start-up" with a red message | The game page found the problem before starting | Do what the card says (it also sent its report to the PC). Triple-tap the top-left corner any time for the details. |
| Something is stuck or odd after an update | A stale saved state in the browser | Open `<address>/reset` on the phone (it says what it clears), or try a private tab. |
| "This site can't be reached" / times out | The phone can't reach the PC | Phone Link on? Same Wi-Fi (not mobile data, not a guest network)? The exact address (not localhost)? Windows firewall: `allow_phone_link.bat`. Run the Doctor. |
| "not allowed" | The PC refused this device | *Tailscale only* is on (Advanced), or it's another Tailscale account. |
| `/hello` works, the launcher doesn't | Browser problem | Reload; try Chrome. |
| "That PIN isn't right. N tries left" | Typo or an old PIN | Type the PIN the PC shows now (it changes every 10 minutes and after each pairing). |
| "Too many wrong PINs. Try again in N s" | 5 wrong tries from this phone | Wait for the countdown. |
| "Pairing is paused" | 20 wrong PINs in an hour | On the PC: Phone Link > **Unlock pairing**, then reload. |
| "The PC has a new PIN" | The PIN changed while you typed (every 10 minutes, after each pairing, or New PIN) | Type the PIN the PC shows now. |
| "Response didn't verify: possible interference" | The PC's answer arrived changed (or from something pretending to be the PC). Nothing was kept on the phone | On the PC, **Forget** any phone you don't recognise, then pair again with the new PIN. If it keeps happening on this Wi-Fi, use Tailscale. |
| The check words differ between phone and PC | Something on the network may be in between | **They don't match**, then forget unknown phones on the PC and pair again (Tailscale if it repeats). |
| PC: "⚠ … paired the old way" | An older Polox app or a very old browser paired: its key crossed the Wi-Fi unencrypted | Update Polox on that phone, **Forget** it on the PC and pair again. |
| Play says the game files aren't built / are older | The phone version is missing or stale | On the PC: Phone Link > **Build the phone version** (or `phone_doctor.bat`). Your worlds are safe. |
| "No worlds are shared with phones yet" | Every world is switched off | Save menu > ⋯ > **Available on phone**. |
| "PC offline" (in the game) | PC asleep, Polox closed, or Phone Link off | Switch it on; Advanced: Keep this PC awake. |
| No sound | Phones only allow sound after a tap | Tap the screen once. |

## What leaves the PC (privacy)

- To your phone, only while Phone Link is on: the launcher and game files, the list of worlds you allow
  (names, covers, sizes), your Library, the world you play, and the AI's replies to your phone's chats.
- From your phone: its changes to those worlds, and the chat messages it wants answered. The PC forwards
  those to **your** AI provider exactly like chats on the PC (Mock and Ollama stay entirely local).
- Never: `settings.json`, your API key, other worlds, backups, or anything outside your PersonalData folder.
- Every request needs the phone's key, except the launcher page, typing the PIN, `/hello` and the game
  files. `/hello.json` tells a device without a key only that Polox is there, its version and the PC's name
  (what finding the PC needs); the addresses and the rest go to this PC itself and to paired phones.
- Pairing (pair_v:1): the phone seals the PIN with the PC's RSA-2048 key for this session (made when a
  phone first asks, kept only in memory, gone when Phone Link stops); the PC sends the phone's key back
  encrypted and authenticated, and both screens show three check words. After that the phone never sends
  its key again: each request carries a signature made with it (good once, within 5 minutes of the PC's
  clock), and the PC refuses that phone's bare key. Older apps and browsers without BigInt still pair the
  old way (PIN and key readable on the Wi-Fi, the key sent with every request); the PC says so. What is
  synced still travels unencrypted on Same Wi-Fi (see SECURITY.md, Known limits).
- The PIN is never written to a log or put in an address. Paths are
  checked against a list; `..` tricks, folders and listings are refused; other web pages can't read
  anything (no CORS). `PersonalData\phone\audit.log` lists pairings and refusals;
  `phone_link.log` lists requests (time, address, path, status: never keys, codes or chats).
- **Forget** removes a phone's key at once (its saves on the phone stay; the PIN pairs it again).

## Plan B: the bundled web server

If the phone's Connection Test passes with **Polox Ping** but fails with **Phone Link**, the problem is in
Polox's own server, and you can swap it in one click:

1. Double-click **`tools\fetch_server.bat`**. It shows exactly what it downloads (Caddy 2.11.4 for Windows,
   about 17 MB, from Caddy's official GitHub release, Apache-2.0 licence), checks its SHA-256 and keeps only
   `tools\server\caddy.exe` and its licence. It asks before downloading and never runs anything.
2. Settings > Phone Link > Advanced > **Server engine: Bundled web server**.

Caddy then answers phones on the same port (8765) and serves the game files; Polox's own server moves behind it,
reachable from this PC only. It starts and stops with Phone Link, refuses anything that isn't your home network
or Tailscale, and every report says which engine answered. If Caddy can't start, the built-in engine takes over
and the screen says why. `allow_phone_link.bat` covers `tools\server\caddy.exe` too.

## Plan C: no network at all

- **Move a world by file:** Worlds > ⋯ > **Export .polox**; copy it (USB, a cloud drive you already use,
  Syncthing); on the other device Worlds > **Import**.
- **Android app:** [PLAYER_GUIDE.md](PLAYER_GUIDE.md), "Polox for Android": Polox's own engine (`tools\build_engine.py android`) and a
  Gradle build with Polox's Android plugin. The app keeps its own copy of your worlds and syncs with the PC.

## For the curious: what was wrong before

**Before 1.4 (Update 5):** every earlier "it works" came from tests that ran on the PC itself, and a PC talking to
its own address skips its firewall, the Wi-Fi and the router, so they proved Polox was listening, not that a
phone could reach it. Real bug found: Update 4's settings upgrade never ran on existing setups (this PC stayed on
*Tailscale only*, which refuses Wi-Fi phones). On 2026-10-11 no request from the phone reached the PC at all.
Update 5 adds the tools that show where it breaks from the phone's side (PHONE_TRIAGE.md), a simpler server,
a fixed port, start-up diagnostics, Tailscale as the sure path and a Plan B engine (PROGRESS.md, *postmortem 3*).

**Before 1.1 (Update 4):** on this PC the mode was *Tailscale direct* with *Tailscale only* ticked, which
refuses every phone on the home Wi-Fi; *Auto* picked Tailscale Serve, which listened on the PC itself only;
the screen showed only the Tailscale name; and the pairing code existed only for two minutes after pressing
*Pair a phone*, so the phone's pairing page had nothing to accept. Now every mode serves Same Wi-Fi, the PIN
is always on screen, and the launcher shows your worlds (PROGRESS.md, *Phone Link postmortem 2*).

**Before 0.8:**

Two things stopped every phone. Windows Firewall had **block** rules for Polox's Godot (made when its
*allow access?* prompt was dismissed), so no phone could reach the PC; and Godot's web page refuses to start
over plain `http://` on a network address (it insists on HTTPS), so even a reachable PC showed an error.
Tailscale Serve avoids both; the HTTP modes now work too (see docs/history/PROGRESS.md, *Phone Link postmortem*).
