# Polox

A cozy little 3D world about **your** life. Build rooms, draw the friends who live there and talk with
them; they remember what you tell them and get on with their own small lives while you're away. Map your
real home as the Light World, step through a Dream Gate into worlds you make up, and settle things in
friendly battles you can design yourself.

Polox is a Godot 4.7.2 game written entirely in GDScript. It runs on Windows, on Android (its own app)
and in a phone's browser, and the same worlds can be played on your PC and your phone. Everything is
stored on your own devices: there are no accounts and no telemetry.

![A made-up world: an outdoor place, a friend, the day's card](docs/images/world.png)

## Privacy

- **Personal information is optional.** Your name, pronouns, birthday, "about me", dreams and your real
  home can all be left blank or skipped, and changed or deleted later.
- **Everything stays on your device.** Worlds, chats, drawings, settings and API keys live in one folder
  on your PC or phone. There are no accounts, no Polox servers, no telemetry, analytics or ads.
- **Nothing leaves unless you connect it yourself:** cloud folder sync (Google Drive, OneDrive,
  Dropbox...), an online AI with your own key, the OpenStreetMap lookup when you map your streets, or
  Phone Link between your own devices. Each is off until you turn it on.

What each of those sends, and to whom: [PRIVACY.md](PRIVACY.md). Security design and how to report a
problem: [SECURITY.md](SECURITY.md).

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

## Build it yourself

Everything runs on Windows 10 or 11 (64-bit) from a plain clone. Every tool goes into `tools\` inside
the project and is checked by hash; nothing is installed system-wide. You need
[Git](https://git-scm.com/) and, from step 3 on, [Python 3.11 or newer](https://www.python.org/).

**1. Get the code and the editor** (about 86 MB, checked against its SHA-512):

```bat
git clone https://github.com/SterburnDev/polox.git
cd polox
tools\get_godot.bat
```

**2. Play and test from source.** No build needed:

```bat
run.bat                 rem play (your data goes to PersonalData\, which Git ignores)
check.bat               rem import, parse-check every script, all ~770 tests, a smoke run: ends with ALL GOOD (about 45 minutes)
check.bat test_secret   rem a single test suite
```

**3. Build Polox's engine** (once, and again only when `native\godot\` changes). Exports use Polox's own
build of the official Godot 4.7.2 source with the fixes in `native\godot\patches\`, not Godot's
ready-made templates. Put these in `tools\` first:

| Folder | What | Where from |
| --- | --- | --- |
| `tools\pyenv\` | SCons 4.11.1 | `python -m venv tools\pyenv` then `tools\pyenv\Scripts\python -m pip install --require-hashes -r native\godot\build-requirements.txt` |
| `tools\downloads\godot-4.7.2-stable.tar.xz` | Godot's source (checked against `tools\godot\SHA512-SUMS.txt`) | [Godot 4.7.2 release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) |
| `tools\llvm-mingw\` (Windows build) | LLVM-MinGW, the `ucrt-x86_64` zip, unpacked so `tools\llvm-mingw\bin\clang.exe` exists | [llvm-mingw releases](https://github.com/mstorsjo/llvm-mingw/releases) |
| `tools\emsdk\` (phone browser build) | Emscripten 4.0.11: unpack the emsdk `4.0.11` source zip, then `tools\emsdk\emsdk.bat install 4.0.11` and `tools\emsdk\emsdk.bat activate 4.0.11` | [emsdk 4.0.11](https://github.com/emscripten-core/emsdk/releases/tag/4.0.11) |
| `tools\jdk17\`, `tools\android-sdk\` (Android build) | Java 17, NDK 29, platform 36, build-tools 36.1.0 | `powershell -ExecutionPolicy Bypass -File tools\get_android_tools.ps1 -AcceptLicenses` |

```bat
tools\pyenv\Scripts\python tools\build_engine.py windows web android
```

Leave out the platforms you don't need. Results land in `tools\engine\<platform>\`.

**4. Build the downloads:**

```bat
rem The Windows game: build\release\public\windows\Polox.exe (the game in one file, checked)
python tools\release\build_windows.py --flavor public --out build\release\public\windows

rem The setup program and the portable zip (needs Inno Setup 7, see docs\BUILDING.md section 5):
rem Polox-<version>-Setup.exe, Polox-<version>-Windows-Portable.zip, Polox-<version>-SHA256.txt
python tools\release\build_installer.py --source build\release\public\windows --out build\release\public

rem The Android app: build\android\polox.apk (arm64)
powershell -ExecutionPolicy Bypass -File tools\export_android.ps1 -NoPause

rem Check what is inside the APK
python tools\release\verify_pack.py --flavor public --apk build\android\polox.apk
```

The first Android build makes your own signing key in `tools\android\`. Keep that folder safe and never
commit it (Git ignores it): Android only updates an installed app with an APK signed by the same key.
The setup program and `Polox.exe` are unsigned unless you pass your own `--sign` command.

Every step, the phone (browser) version, code signing and the release checks are described in
[docs/BUILDING.md](docs/BUILDING.md); the public and private build flavours in
[docs/RELEASES.md](docs/RELEASES.md).

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
