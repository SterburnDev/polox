# Phone Link: the check only your phone can do

> **If the phone can't connect at all, do [PHONE_TRIAGE.md](PHONE_TRIAGE.md) first** (5 minutes: `ping.bat`, the
> phone's Connection Test at `<address>/test`, and what to paste back). This page is the longer walk-through for
> when it does connect.

Everything that can be proven on the PC is proven by **`check_phone.bat`**: the real server on every address
of this PC (the home network `192.168.1.42` and Tailscale), the launcher, wrong and right PINs, the
cooldown, the worlds list with covers, starting a world, sync both ways, conflicts, the AI proxy, stress,
attacks, and a headless phone-size browser that types the PIN, taps Play and places a block that lands on
the PC. What's left needs your real phone: your Wi-Fi, Android's browser and keyboard, your router.

About 15 minutes. Do **Part A (Same Wi-Fi, no Tailscale)** first; turn Tailscale **off on the phone** for it
so you know Wi-Fi alone works. If a step fails, the last column says what it means; then run
`phone_doctor.bat` on the PC and use **Copy diagnostics** if you want to send it to me (no keys, PINs or chats).

## Part A: Same Wi-Fi

| # | On the PC / on the phone | ✅ You should see | ❌ If not, it means |
|---|---|---|---|
| 0 | PC: `check_phone.bat` | `[phone] ALL GOOD` | Something is broken on the PC itself: the output says which test. |
| 1 | PC: start Polox, Menu > Settings > **Phone Link**, switch **ON** | Big **`http://192.168.1.42:8765`** with a QR code; under it *Mode: Same Wi-Fi + Tailscale HTTPS (Auto) • listening on every address of this PC (127.0.0.1, 192.168.1.42, 100.64.0.10) on port 8765*; a big **PIN** like **482 913** with *new PIN in 9:59*; *○ Waiting for your phone... (0 s)* | Red text under the switch: it names the problem (e.g. the port is taken: close the other Polox / host.bat). |
| 2 | Phone: Wi-Fi on (same network as the PC), **Tailscale off**, mobile data can stay. Open Chrome, type `http://192.168.1.42:8765` | **Polox** • *● Connected to "EXAMPLE-PC"* • **Enter the PIN shown on your PC**, a big 6-digit box and *This phone's name: Android phone* | Spins, then "can't be reached": the phone isn't on the same network (guest Wi-Fi? mobile data?), or Windows blocks Polox (see step 2b). "not allowed": *Tailscale only* is ticked in Advanced. A page for **another** device: you typed `localhost` (that's the phone itself). |
| 2b | (only if step 2 failed) PC: after a minute the Phone Link screen | *No phone yet? Check these:* and the Doctor's findings | Follow the first ✗. Firewall: double-click `allow_phone_link.bat` (read it, type Y). Router "client/AP isolation": switch it off or use the main (not guest) Wi-Fi. |
| 3 | PC: look at the screen (even mid-game) | A banner at the top: **📱 Phone connecting: PIN 482 913** (click it: Phone Link opens); the Phone Link screen says *✓ Phone reached Polox: 23:41 from 192.168.1.40* | No banner but the phone shows the launcher: tell me (the PC didn't notice the contact). |
| 4 | Phone: type a **wrong** PIN | *That PIN isn't right. 4 tries left before a short wait.* | |
| 5 | Phone: type the PIN the PC shows | **Your worlds**: a card per world with its picture (or emoji), name, *Played ... · size*, rooms and friends, and a yellow **Play** button. The PC shows a **new** PIN and *📱 Paired: Android phone* | "PIN ran out": type the current one. "N phones are paired already": Forget one on the PC. |
| 6 | PC: Save menu > **⋯** on a world > untick **📱 Available on phone**. Phone: pull down to reload | That world is gone from the list (tick it again afterwards) | |
| 7 | Phone: tap **Play** on your main world | *Opening ...*, then the game loads (first time ~10 MB) and starts **in that world** (no title screen). The PC's Phone Link screen says *📱 Phone playing <world>* | "The game files for phones aren't built / are older": PC > Phone Link > **Build the phone version**. Black screen or an error box: send a screenshot. |
| 8 | Phone: tap the floor, pinch, slide two fingers, long-press | Walks, zooms, turns, opens/closes the menu | Tell me which gesture. |
| 9 | Phone: tap a friend, tap the text bar, type *hi from my phone*, **Send** | The keyboard opens; a reply in their usual (AI) voice | No keyboard: tap the text bar itself. "PC offline" lines: the PC's AI isn't reachable. |
| 10 | Phone: Build, place a block, Done. Wait ~20 s or tap ☁ | On the PC the block appears (the world reloads) | ☁ says *Not paired*: go back to the address and type the PIN. |
| 11 | Phone: Chrome ⋮ > **Add to Home screen** on the worlds list; open the icon | Full screen, straight to **Your worlds** (no PIN: remembered) | (iPhone: type the PIN inside the Home Screen icon once: it has its own storage.) |
| 12 | Phone: type 5 wrong PINs in a row (open the address in a private tab to get the PIN box) | *Too many wrong PINs. Try again in 60 s* counting down; then you can try again | |
| 13 | PC: Phone Link > Paired phones > **Forget**. Phone: reload | Back to **Enter the PIN** with *This phone was forgotten on the PC...*; the PIN brings the worlds back | |
| 14 | PC: switch Phone Link off. Phone: chat in the game | Gentle offline lines, *PC offline*. Switch it on again: it syncs | |
| 15 | PC: close Polox, double-click **`host.bat`** | A small window: the address, the QR code, the PIN, *○ Waiting for your phone...*; when the phone opens the address: *📱 Phone connected (192.168.1.40)* (the console window prints the same) | |

## Part B: Tailscale (away from home)

| # | On the PC / on the phone | ✅ You should see | ❌ If not, it means |
|---|---|---|---|
| 16 | Phone: Tailscale **on** (same account). PC: Phone Link screen | Under the Wi-Fi address: *Away from home (Tailscale on the phone, same account): https://example-pc.tailnet-example.ts.net:8765* | Missing: Tailscale isn't connected on the PC, or HTTPS certificates are off (Advanced shows which). |
| 17 | Phone (mobile data, Wi-Fi off): open that https address | The same launcher; the PIN once (it's a different address to the browser), then your worlds and Play | Times out: Tailscale off on the phone or the PC. "not allowed": another Tailscale account. |
| 18 | PC: Wi-Fi address still works? Phone back on Wi-Fi, open `http://192.168.1.42:8765` | Still straight to your worlds | Tell me (Tailscale must never break Same Wi-Fi). |

## Part C: New things, by touch (optional, 5 minutes)

The PC tests drive these with simulated touches; only your thumbs can say whether they *feel* right.
(First PC > Phone Link > **Build the phone version** again if the launcher says the game files are older.)

| # | On the PC / on the phone | ✅ You should see | ❌ If not, it means |
|---|---|---|---|
| 19 | Phone: in a world, go to the **Tile Playground** room and tap the tall glowing **Platform Pillar** | A flash and a ring burst; a **thumb stick** bottom-left, big **Jump** and **Run** buttons, **Leave** at the top; the camera follows behind you | Nothing happens: tap closer to the pillar's base. Tell me if the buttons are too small or in the way. |
| 20 | Phone: push the stick a little, then all the way; tap **Jump**; jump off the edge | Walk, then run (dust); a jump; falling off fades you back to the checkpoint, no penalty | Tell me if the stick drifts or the jump feels late. |
| 21 | Phone: **Leave** | Back to tap-to-walk where you were | |
| 22 | Phone: Menu > **Hang out** > pick a friend > **Tea Time** | They come and stand beside you, a teapot and two cups appear, two lines; Menu > Memory Book has *Tea time with ...* | *Nobody's in this room*: tap **Go there** next to a friend under *Elsewhere right now*. |
| 23 | Phone: Menu > **Hang out** > **Stargazing** | Green and violet light at the top of the room, a line about the stars, then **Make a wish** with the keyboard | No keyboard: tap the text box itself. |
| 24 | Phone: type a wish, **Make the wish**; wait ~20 s. PC: Menu > Dreams & Desires | The wish is on the PC's Dreams board | ☁ says *Not paired*: open the address and type the PIN. |

**Security bonus:** from another device on the same Wi-Fi, open the address + `/api/worlds`:
✅ *not paired*. `PersonalData\phone\audit.log` lists pairings, wrong PINs and refusals (never PINs or keys).
