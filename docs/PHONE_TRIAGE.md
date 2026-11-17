# Phone can't connect? A 5-minute check

This finds **which step fails** between your phone and the PC, so it can be fixed instead of guessed at.
You need the PC and the phone side by side. Nothing here sends your API key, PIN or chats anywhere.

**Before you start (phone):** same Wi-Fi as the PC, **mobile data off**, any VPN app off (Tailscale may stay on).

---

## The five steps

1. **PC (30 s): double-click `ping.bat`** in the Polox folder. A window called **Polox Ping** opens with a big
   address (like `http://192.168.1.42:8765`) and a QR code. Leave it open. Under **This PC**, any line with ✗ or ⚠
   says what's in the way on the PC; press the button next to it if there is one (for example **Run the firewall
   helper**, which shows what it will change and asks first).

2. **Phone (1 min): scan the QR code** with the camera (or type the address exactly, **with `http://`**).
   - You see **✓ Polox OK**: the phone reaches the PC. Go on to step 3.
   - It spins, says *can't be reached*, *timed out* or *connection reset*: nothing gets through. Look at the PC
     window: **"No device has contacted Polox Ping yet"** means the PC never heard from the phone (see the table
     below). Also try the other addresses the window lists (ports 8080 and 8888, and the `.local` name).

3. **Phone (1 min): tap "Run the full connection test".** Each row turns green or red with the exact error.
   Wait for **All good** or the red rows. The page sends its report to the PC by itself.

4. **PC + phone (1-2 min): the real thing.** Close Polox Ping. Start Polox, **Menu > Settings > Phone Link**,
   switch it **ON**. On the phone open the address shown there (port 8765): the **Polox Launcher** asks for the
   PIN shown on the PC, then shows your worlds; tap **Play**. If the game shows a red **Polox start-up** card,
   do what it says (it has already told the PC). Triple-tap the top-left corner any time for the details.

5. **PC (30 s): copy the diagnostics.** Settings > Phone Link > Advanced > **Phone Link Doctor** >
   **Copy diagnostics**, and paste it back (see *What to paste back*).

---

## What each result means

| What you saw | What it means | What to do |
|---|---|---|
| Step 2 spins / times out, and the PC says **"No device has contacted Polox Ping yet"** | The phone's request never reached this PC | Check the PC lines under **This PC** first (firewall, Public network, VPN). Then the phone: same Wi-Fi (not guest, mobile data off), no VPN, and the first three numbers of the phone's Wi-Fi address match the PC's (phone: Settings > Wi-Fi > your network; e.g. `192.168.1.x`). Different numbers = a different network (guest Wi-Fi, extender, second router). |
| Same, and everything on the PC is green | Your router keeps devices apart ("client isolation" / "AP isolation"), or the phone isn't on the same network | Turn isolation off in the router, or use **Tailscale** (Phone Link screen > Tailscale: three steps; it doesn't care about the router), or connect the PC to the **phone's hotspot** and use the address Polox Ping shows then. |
| iPhone, in Chrome / Firefox / another app, nothing loads | iOS asks those apps for "Local Network" permission | iPhone Settings > (that app) > **Local Network: on**. Or use Safari. |
| Android: Chrome asks about devices on your local network | Newer Android versions ask apps before they reach home-network devices | Allow it (Settings > Apps > Chrome > Permissions). |
| The PC window shows the phone **"spoke HTTPS to this HTTP port"** | The browser tried `https://` | Type the address with **`http://`** in front, or scan the QR code. |
| The PC shows the phone **"connected, but sent no request"** | The browser gave up, or something on the way cut the connection | Try again; try another browser; move nearer the router. |
| Step 2 shows **Polox OK**, step 3 has red rows | The connection works but something else doesn't | The red row says what: *Big download* failing = flaky Wi-Fi or power saving; *What this browser can do* failing = the browser can't run the game (update it, try Chrome/Safari). |
| Steps 2-3 all green, step 4 (Phone Link) doesn't load | The problem is **inside Polox** | Open `<Phone Link address>/test` on the phone and compare. Then Settings > Phone Link > Advanced > **Server engine: Bundled web server** (first run `tools\fetch_server.bat`, which asks before downloading) and try again. |
| Step 4: the launcher loads, the game shows a **Polox start-up** card | The game page found a problem before starting | Do what the card says. "Files don't match" = Settings > Phone Link > **Build the phone version** on the PC. "WebGL 2" = update the browser / battery saver off. |
| Step 4: odd behaviour after an update | A stale saved state in the phone's browser | Open `<address>/reset` on the phone (it says what it clears first), or try a private tab. |
| The PC went to sleep | An asleep PC can't answer | Keep this PC awake (on by default while Phone Link is on). |

---

## What to paste back

1. **The Doctor's diagnostics:** Settings > Phone Link > Advanced > Phone Link Doctor > **Copy diagnostics**
   (also saved as `PersonalData\phone\diagnostics.txt`). It includes this PC's network facts, every connection
   that reached Polox, and the phones' reports.
2. **Polox Ping's report**, if you used it: **Copy everything** in the Polox Ping window.
3. **The phone's report**, if it didn't reach the PC: **Copy report** on the phone's Connection Test page.
4. **One sentence about the phone:** which phone and browser, and what it showed (for example *"Pixel 8,
   Chrome: spins, then ERR_CONNECTION_TIMED_OUT"*).

None of these contain your API key, the PIN, pairing keys or chats.
