# The same worlds on your PC and your phone

There are two different things here, and they solve different problems.

| | **Phone Link** | **Cloud folder sync** |
| --- | --- | --- |
| In one sentence | Your phone plays *through* your PC | Each device has its own copy, kept in step through a folder in your cloud storage |
| Your PC must be | **On**, with Phone Link switched on | **Off is fine** |
| Where | Same Wi-Fi; anywhere with Tailscale | Anywhere each device can reach your cloud storage |
| Changes arrive | As you play (every save) | When a device syncs: when Polox starts, when you leave a world, or when you press Sync now |
| Chats with AI friends on the phone | Go through the PC (your key never leaves it) | Use whatever the phone itself is set up with |
| Set up in | Settings > Phone Link | Settings > Cloud sync |

Playing never needs either. Without them each device simply has its own worlds.

---

## 1. Phone Link (your PC is on)

Full guide: [PHONE_SETUP.md](PHONE_SETUP.md). In short: Settings > Phone Link > switch it on, open the
address it shows on your phone (or use the Android app), type the PIN once.

**Away from home: Tailscale.** [Tailscale](https://tailscale.com) joins your own devices into a private
network. With it on the PC and the phone, signed in to the same account, Phone Link shows a second
address (`https://<pc>.<tailnet>.ts.net:8765`) that works from anywhere. Polox uses *Tailscale Serve*,
which is reachable only from your own tailnet; it never uses Funnel (the public option) and refuses
public internet addresses. Tailscale's free Personal plan is enough. HTTPS must be enabled for the
tailnet once (the Tailscale card in Settings > Phone Link checks this and says what is missing).

**Your devices, and taking one away.**

- Settings > Phone Link lists every paired phone with when it was last seen. **Forget** removes that
  phone's key at once; it has to pair again with a new PIN. Pairing the same phone again replaces its
  old entry instead of adding one.
- **New PIN** changes the PIN; **Always ask for PIN** makes keys last one evening instead of
  indefinitely. Too many wrong PINs pause pairing until you press **Unlock pairing** on the PC.
- The phone shows its state in words: *Synced 14:32*, *PC offline* (it keeps playing its own copy and
  tries again every minute and whenever you come back to it), *Not paired: pair this phone again (it
  keeps your saves)*, or the reason the PC refused it.
- `PersonalData/phone/audit.log` lists pairings, wrong PINs and refusals (never a PIN or a key).

**What a paired phone can read and write:** the worlds you allow (Save menu > ⋯ > Available on phone),
the Library, and your Light World's house and streets when "Share with phones" is on. Never
`settings.json`, your AI keys, backups, or other worlds. When both sides changed the same file, the PC
merges it field by field and keeps the phone's whole file in the world's `conflicts/` folder if a real
clash remains.

---

## 2. Cloud folder sync (your PC can be off)

### How it works

Each world you switch on is kept as **one file** (`<world>-<id>.poloxsync`) in a folder that your own
cloud app copies between your devices. Polox only reads and writes that file. Signing in, uploading and
downloading are done by the cloud app you already use, so **Polox holds no account, password, API key or
client secret** for any cloud service, in any build.

### Set it up

**On the PC**

1. Have a cloud app that keeps a folder in step: Google Drive for desktop, OneDrive, Dropbox, iCloud
   Drive, Syncthing... With Google Drive for desktop, either mode works: *Mirror files* keeps a full copy
   on the PC (best: it also works offline); *Stream files* shows My Drive as a drive letter that is only
   there while Drive for desktop is running.
2. Settings > Cloud sync > choose the folder. Polox suggests a `Polox` folder inside the cloud folders
   it finds; any folder will do.
3. Switch on **Keep in the cloud** for each world you want on your other devices. It is sent at once.

**On an Android phone (the Polox app)**

There are two ways on Android (use whichever fits your setup — Polox never asks for a password):

1. **Google Drive / OneDrive / Dropbox (direct files — zero extra apps needed):**
   - Switch on **Keep in the cloud** for any world; Android's picker lets you save its `.poloxsync` file right into **Google Drive** (for example `My Drive/Polox`).
   - To bring a world from your PC onto Android: Settings > Cloud sync > **Add a world from Google Drive / Cloud…** (or Worlds > **Import .polox**) and pick its `.poloxsync` file in Drive.
   - If Android revokes access or you move a file in Drive, tap **Relink file…** on the world's prompt to reconnect it without losing sync history.
2. **Synced Cloud Folder (`Choose a cloud folder…`, optional):**
   - Uses Android's `ACTION_OPEN_DOCUMENT_TREE` so players using **DriveSync / Autosync for Google Drive**, **Syncthing**, **Nextcloud**, or a local/SD `Polox` folder can pick one folder and get automatic multi-world discovery and 1-tap **Keep in the cloud**.

Android gives Polox persistent access to only the specific document or folder you pick. No broad storage permission is requested, and no Google OAuth client secret or API token is bundled.

**In a browser:** the browser version plays through Phone Link and has no cloud sync of its own.

### What is sent, and what never is

Per world, and only for the worlds you switch on: its places, friends, chats, items, your character and
its pictures (`.json`, `.jsonl`, `.png`, `.jpg`, `.webp` files under 8 MB, chat logs under 16 MB).

Never: `settings.json` and your AI keys, Phone Link pairing keys, add-ons, backups, photos, exports,
your Light World home (your real address and floor plan), and any world left switched off. The list is
an allowlist in `scripts/sync/cloud_package.gd`: a file that isn't on it can't be packed, and a package
that contains anything else is refused when it arrives.

### When two devices both changed a world

A sync compares three things: this device's world, the version both devices last agreed on, and the
cloud's file.

| What changed | What happens |
| --- | --- |
| Only this device | Its version is sent |
| Only the cloud's (another device synced) | This device takes it, after zipping its own world into the world's Backups |
| Both, in different places (another room, another friend, new chat messages) | Combined automatically, file by file and field by field, and the result is sent |
| Both, the same thing (the same room's name, the same picture) | **Nothing is changed.** Settings > Cloud sync shows what clashed and asks: *Keep both* (the other version arrives as a second world), *Use this device's*, or *Use the cloud's* |

Whichever you choose, the version that wasn't chosen is kept: in the world's Backups
(`before_cloud_*.zip`) or in `PersonalData/cloud/kept/`.

### What keeps it safe

- **A cut-off upload is never used.** Every package lists a SHA-256 for each file inside and for the
  whole. A package that fails the check (still uploading, damaged, half a file) is reported and left
  alone; sync again when the upload has finished.
- **Simultaneous edits can't silently overwrite.** A package names the revisions it descends from. If the
  cloud's file was made without knowing this device's last upload (a slow cloud app, two devices at
  once), it is never treated as a plain update: it is combined, or you are asked. Just before an upload
  replaces the cloud's file, the file is read again; if it changed in that moment the upload stops.
- **An interrupted install is finished later.** If the app closes or the battery dies while another
  device's version is coming in, the next sync completes it from the copy kept for that purpose.
- **Offline is normal.** If the folder can't be reached the page says so and you keep playing your own
  copy; everything you did offline goes up at the next sync.
- **Your cloud app made a "conflicted copy"?** The page lists it as a second file for the same world
  and can bring it in as a separate world to look at.

### Limits to know

- Sync is per world and happens at sync time, not continuously. Two devices that play the same world at
  the same moment both keep working; the second one to sync combines or asks.
- A cloud app needs time to upload. If you switch the PC off the second Polox closes, the file may not
  have left yet; the phone then still sees the older version, and nothing is lost when the PC comes back.
- On Android a sync copies the world's file to or from your cloud app, which can take a few seconds on a
  slow connection; the screen says "Syncing…" while it does.
- Files over the size limits stay on the device that has them; the page says how many.

---

## 3. The options that were considered

Checked against each service's own documentation in November 2026. "Runtime role" means the game talks
to it while you play or sync.

| Option | Setup effort | Privacy | Cost | Reliability | Offline | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| **Phone Link, same Wi-Fi** | A PIN | Nothing leaves your home network | Free | Good at home; needs the PC on | The Android app keeps playing its own copy | **Built in** |
| **Phone Link over Tailscale** | Install Tailscale on both, same account, enable HTTPS once | Encrypted between your own devices; Tailscale sees connection metadata, not your worlds | Free Personal plan (up to 6 users, unlimited personal devices) | Good anywhere; needs the PC on | As above | **Built in** |
| **Cloud folder (your own Google Drive, OneDrive, Dropbox, Syncthing...)** | Choose a folder on the PC; pick a file on the phone | Your worlds sit in your own cloud storage, readable by that provider; Polox holds no credentials | Free within your storage quota (a world is a few MB) | As good as your cloud app; every file is checked before use | Full play offline; syncs later | **Built in** (this page) |
| Google Drive API inside Polox | You would create a Google Cloud project and OAuth client | Polox would hold a token for your Drive | Free | Poor for a hobby app: a project left in "Testing" issues refresh tokens that expire after 7 days, and the sign-in flow that suits a game (the device flow) requires a client secret embedded in the app | Yes | **Not used.** Embedding a client secret is ruled out, and the cloud folder gives the same result with no credentials |
| GitHub as the sync store (a private repository, written through the API) | A token on every device | Tokens on phones; worlds in a repository | Free | GitHub's own guidance: Git "is not designed to serve as a backup tool", repositories should stay small | Yes | **Not suitable** as storage for player data |
| Your own always-on server (a mini PC or NAS running `host.bat`, or a WebDAV server) | Hardware or hosting, and upkeep | Entirely yours | Hardware or a hosting fee | As good as the server | As Phone Link | Works today with `host.bat` on any always-on Windows PC; no hosted variant is built |

**What GitHub is good for here** (none of it at runtime):

- **Source**: the public repository made by `tools/release/make_public_source.py`.
- **Builds**: GitHub Actions is free on standard runners for public repositories. The plain game can be
  checked there (`check.bat`); the release exports need Polox's own engine build, which is practical
  to cache but not yet set up.
- **Distribution**: Releases take files up to 2 GiB each with no bandwidth limit: the right place for
  the setup program, the portable zip and the APK, each with its SHA-256.
- **A hosted copy of the web version**: GitHub Pages can serve it (sites up to 1 GB, a soft 100 GB per
  month), but a page served from there can't talk to a PC on your home network (browsers block an HTTPS
  page from calling a plain-HTTP address, and Phone Link sends no cross-origin headers on purpose), so it
  would be a stand-alone demo, not a way to reach your worlds.

---

## 4. What has been verified

| Claim | How it was checked | Status |
| --- | --- | --- |
| Packages: allowlist, hashes, refusal of damaged, cut-off, tampered, unsafe and newer-format files | `tests/test_cloud_sync.gd` | Tested |
| Two devices: send, receive, deletions, combining edits, real conflicts and all three answers | `tests/test_cloud_sync.gd` (two save folders and a folder as the cloud, one process) | Tested |
| Interrupted upload, interrupted install, restart, offline and back, two devices at the same moment, a cloud copy made without knowing this device's changes | `tests/test_cloud_sync.gd` | Tested |
| The Settings page: choosing a folder, switching a world on, Sync now, a conflict answered with a button, bringing a world over, syncing at the title, sending on close | `tests/test_cloud_sync_ui.gd`, and looked at on screen at PC and phone sizes (`--drive=cloud_sync_conflict`) | Tested |
| A real cloud app carrying the file between this PC and a phone (Google Drive for desktop to the Drive app) | Needs your cloud account on both devices | **Not verified** |
| The Android file picker and reading and writing a picked document on a real device | The plugin code compiles with the project's Gradle build; it has not been run on a phone or emulator | **Not verified** |
| Phone Link pairing, sync and conflict handling | `check_phone.bat` and the Phone Link suites (existing) | Tested (see [API_VERIFICATION.md](API_VERIFICATION.md)) |
