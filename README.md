# Polox

A cozy little 3D world about **your** life. Build rooms, draw the friends who live there and talk with
them; they remember what you tell them and get on with their own small lives while you're away. Map your
real home as the Light World, step through a Dream Gate into worlds you make up, and settle things in
friendly battles you can design yourself.

Polox is a Godot 4.7.2 game written entirely in GDScript. It runs on Windows, on Android (its own app)
and in a phone's browser, and the same worlds can be played on your PC and your phone. Everything is
stored on your own devices: there are no accounts and no telemetry.

![A made-up world: an outdoor place, a friend, the day's card](docs/images/world.png)

## Play

| You have | Do this |
| --- | --- |
| A Windows PC | Run **`Polox-<version>-Setup.exe`** (Start menu entry, uninstaller, no administrator needed), or unzip the **portable zip** anywhere and double-click `Polox.exe` |
| An Android phone | Install the APK, or open your PC's Phone Link address in the phone's browser |
| The source | `tools\get_godot.bat` once, then `run.bat` (Windows) or `./run.sh` (macOS, Linux) |

The full manual, from controls to troubleshooting, is [docs/PLAYER_GUIDE.md](docs/PLAYER_GUIDE.md).

## Your worlds on your PC and your phone

| Way | When it works | What it needs |
| --- | --- | --- |
| **Phone Link** on the same Wi-Fi | Your PC is on and you are at home | Nothing but the PIN on the PC's screen |
| **Phone Link over Tailscale** | Your PC is on, you are anywhere | The free Tailscale app on both, same account |
| **Cloud folder sync** | Your PC is off | A folder your own cloud app keeps in step (Google Drive, OneDrive, Dropbox, Syncthing...) |

Local play never needs any of them. What is sent, how conflicts are handled and how to set each one up:
[docs/SYNC.md](docs/SYNC.md).

## Build and test

```bat
tools\get_godot.bat                 rem once: the Godot 4.7.2 editor (about 86 MB, checked against its SHA-512)
run.bat                             rem play from source
check.bat                           rem import, parse-check every script, the test suite, a smoke run
check.bat test_secret               rem one suite
```

Exports (Windows, the setup program, the phone version, the Android app), the engine build they use and
the release checks are in [docs/BUILDING.md](docs/BUILDING.md).

## Where things are

| Folder | What it holds |
| --- | --- |
| `scripts/` | The game, by feature: `core`, `ui`, `world`, `builder`, `characters`, `ai`, `home`, `battle`, `platform`, `phone`, `net`, `sync`, `items`, `variety` |
| `scenes/`, `shaders/`, `assets/` | The one scene, the shaders, and bundled pictures, models, materials and sounds |
| `bundled-addons/` | Add-ons that ship with the game (Polox Originals). The format: [docs/ADDONS.md](docs/ADDONS.md) |
| `tests/` | One suite per feature (`test_<area>.gd`), fixtures, and Phone Link end-to-end checks in `tests/e2e/` |
| `tools/` | Engine setup, export entry points, `tools/release/` (setup program, public snapshot, build checks), `tools/art/` and `tools/blender_scripts/` (how the bundled art is made) |
| `native/` | Polox's engine patches and its Android plugin |
| `docs/` | Guides. Start with [docs/DIRECTORY_GUIDE.md](docs/DIRECTORY_GUIDE.md): entry points, feature tags and data flow |

Your own data is never in the repository. From source it lives in `PersonalData/`, which Git ignores and
no export includes.

What has been proven, and what has not: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) (tests, the setup
program on a clean PC, old saves, measured performance) and
[docs/API_VERIFICATION.md](docs/API_VERIFICATION.md) (every outside service, checked with real requests).

## Public and private builds

The repository builds a complete game from assets that may be redistributed. A private build adds a
content pack that stays on its owner's PC (`assets/local/`: their own soundtrack, Soul picture and
Music-secret pictures). The two are built by the same scripts and checked by
`tools/release/verify_pack.py`; [docs/RELEASES.md](docs/RELEASES.md) explains the split and
[docs/ASSET_AUDIT.md](docs/ASSET_AUDIT.md) lists every asset's source and rights.

## Contributing, licence, credits

- [CONTRIBUTING.md](CONTRIBUTING.md): how to set up, what a change needs, the code style.
- [LICENSE](LICENSE): the GNU General Public License, version 2 or (at your option) any later
  version (GPL-2.0-or-later), for the code. Original
  art and sound made for Polox are under the same terms unless a file says otherwise. Copyright (C) 2026
  The Polox authors. See [docs/LICENSING.md](docs/LICENSING.md).
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): Godot, Kenney, Poly Haven and everything else Polox
  builds on.
- [CHANGELOG.md](CHANGELOG.md): what changed in every version.

A gentle note: the friends in Polox are meant to be a cozy companion, not a replacement for the people in
your life. If things feel heavy, please reach out to someone you trust or a local helpline
(<https://findahelpline.com> lists free ones worldwide).
