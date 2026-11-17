# Privacy

**The short version:** everything personal in Polox is optional, and everything you make or share stays
on your own device. Polox has no accounts, no servers of its own, no telemetry, no analytics and no ads.
Something leaves your device only when **you** connect a service yourself, such as cloud folder sync
(Google Drive, OneDrive, Dropbox...) or an online AI with your own key. The table below lists each one.

## Personal information is optional

Polox asks about you in a few places: your name, pronouns, nicknames, birthday, an "about me", a dream,
how you look, and (only if you choose to map it) your real home. **Every one of these can be left blank
or skipped.** The game works the same without them; your friends just know less about you. You can
change or clear any of it later in *Menu > My character*, and *My home > Forget my home* deletes
everything about your real home.

## What stays on your device

Your worlds, friends, chats, memories, drawings, settings, API keys, add-ons and logs are kept in one
folder that only you control:

| How you run Polox | Where your data is |
| --- | --- |
| Windows, setup program | `%LOCALAPPDATA%\Polox\PersonalData` |
| Windows, portable zip | `PersonalData` beside `Polox.exe` |
| From source | `PersonalData` in the project folder (Git ignores it) |
| Android app | The app's private storage (exports you make go to `Download/Polox`) |
| Phone browser (through Phone Link) | Your PC's folder above; the phone keeps only what it needs to play |

Nothing in that folder is ever part of the repository, an export, a build or a crash report. Deleting the
folder (or uninstalling and choosing to remove your worlds) deletes all of it.

## What leaves your device, and only when you turn it on

| You turn on | What is sent | To whom |
| --- | --- | --- |
| **Cloud folder sync** (Settings > Cloud sync) | The worlds you switch on: their places, friends, chats, items, your character and pictures. **Never** settings, API keys, pairing keys, add-ons, backups or your real home | Polox only writes files into a folder you choose. Your own cloud app (Google Drive, OneDrive, Dropbox, iCloud Drive, Syncthing...) uploads that folder, under your account and that provider's privacy terms. Polox holds no cloud passwords or tokens |
| **An online AI** (Settings > AI, with your own key) | What a friend needs to answer you: the world's description, that friend's card and memories, your profile and dreams (unless you turn dreams off) and the recent chat | The provider you picked (for example OpenAI, Google Gemini, Groq, Venice or a server you name). Its own privacy terms apply; some free tiers may use what you send. Your key is sent only to that provider and is scrubbed from chat logs |
| **Map my streets** | Your home's map coordinates and a radius (and, only to find the coordinates, the address you typed) | OpenStreetMap (Nominatim and Overpass). The game asks before sending and says exactly this |
| **Look up my home** (optional, in Map my home) | The address you typed and your answers about the building (floors, rooms) | The research helper you picked (an online AI or an AI tool on your PC). *Nobody: just my answers* sends nothing |
| **Phone Link** (off every time Polox starts) | Your worlds and the chat messages a paired phone asks your PC to answer | Only your own phones, over your home network or your own Tailscale. Public internet addresses are always refused, every phone needs a PIN shown on your PC, and your API key never goes to the phone |

With the default **Mock** AI, or **Ollama** running on your own PC, chatting sends nothing anywhere.
Links you press (a map, a help page) open in your own web browser.

## What Polox never does

- No account, sign-in or e-mail address.
- No telemetry, analytics, advertising IDs or tracking.
- No crash reports sent to the developers. Crash logs stay in your data folder; a phone's connection
  report goes only to your own PC.
- No selling, sharing or uploading of your data. There is no Polox server to send it to.

## Your API keys

Keys you add are stored only in your data folder (`settings.json`), sent only to the service they belong
to, never synced to phones or the cloud, and removed from logs and error messages. Anyone who can read
your user account's files can read them, so don't share that folder. *Settings > AI* can clear a key at
any time.

## Questions

The details, with the code that enforces each rule, are in [docs/SYNC.md](docs/SYNC.md) (cloud sync and
Phone Link), [docs/PLAYER_GUIDE.md](docs/PLAYER_GUIDE.md) section 6, and [SECURITY.md](SECURITY.md).
