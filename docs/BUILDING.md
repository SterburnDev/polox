# Building and testing Polox

Everything here runs on Windows 10 or 11 from a plain checkout. Every script finds the project from its
own location, so it can be started from any working directory.

## 1. Play from source

| Step | Command | Notes |
| --- | --- | --- |
| Get the editor (once) | `tools\get_godot.bat` | Godot 4.7.2 into `tools\godot\`, about 86 MB from the official GitHub release, checked against `tools\godot\SHA512-SUMS.txt` |
| Play | `run.bat` | Saves go to `PersonalData\` in the project folder |
| Only the Phone Link server | `host.bat` | A small window with the address and PIN; no game |

macOS and Linux: install Godot 4.7.2 and run `./run.sh` (`GODOT=/path/to/godot ./run.sh`).

## 2. Tests

| Command | What it does | Time |
| --- | --- | --- |
| `check.bat` | Import, parse-check every script, the whole test suite, a headless smoke run. Ends with `ALL GOOD` | about 45 minutes for the whole suite (about 770 tests); with Python it also scans every file for personal details and keys first |
| `check.bat test_secret` | One suite (the file name in `tests\` without `.gd`) | seconds to minutes |
| `check_phone.bat` | Builds the phone version, then proves Phone Link on this PC's own network addresses, including a headless phone-size browser | several minutes; listens on your network for about a minute |
| `tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd -- --only=test_ai,test_core` | The runner directly, for several suites | |

The runner prints `ALL n TESTS PASSED`. A script error inside a test aborts that test without failing
the count, so also look for `SCRIPT ERROR` in the output (`check.bat` does). Tests never use the network
or your real saves: each gets a scratch folder under `tests\.tmp_save\`.

**Launching the game for a check:** always give it a scratch save folder, or it opens your real worlds.

```bat
tools\godot\Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path . -- --save-root=tests/.tmp_save/look --drive=smoke
tools\godot\Godot_v4.7.2-stable_win64.exe --path . --resolution 412x892 --rendering-method gl_compatibility -- --touch-ui --save-root=tests/.tmp_save/phone
```

`--drive=<name>` runs a scripted scenario (`scripts\core\debug_drives.gd`), `--shot=<file.png>` saves a
screenshot and quits, `--time-machine=3` moves "now" three days ahead.

## 3. The engine Polox exports with

Exports don't use Godot's ready-made templates. They use Polox's own build of the official Godot 4.7.2
source, with the fixes in `native\godot\patches\` and without the engine modules the game doesn't need
(`native\godot\polox_profile.py`). Build it once, and again when a patch or the profile changes:

It expects these portable toolchains in `tools\` (each only for the platforms you build):

| Folder | What | How to get it |
| --- | --- | --- |
| `tools\pyenv\` | SCons 4.11.1 in a Python 3.11+ virtual environment | `python -m venv tools\pyenv`, then `tools\pyenv\Scripts\python -m pip install --require-hashes -r native\godot\build-requirements.txt` |
| `tools\downloads\godot-4.7.2-stable.tar.xz` | Godot's official source | From <https://github.com/godotengine/godot/releases/tag/4.7.2-stable>; `build_engine.py` checks it against `tools\godot\SHA512-SUMS.txt` |
| `tools\llvm-mingw\` | LLVM-MinGW (Windows) | The `llvm-mingw-<date>-ucrt-x86_64.zip` from <https://github.com/mstorsjo/llvm-mingw/releases>, unpacked so `tools\llvm-mingw\bin\clang.exe` exists |
| `tools\emsdk\` | Emscripten 4.0.11 (web) | Unpack the source zip of emsdk tag `4.0.11` (<https://github.com/emscripten-core/emsdk/archive/refs/tags/4.0.11.zip>) into `tools\emsdk\`, then `tools\emsdk\emsdk.bat install 4.0.11` and `tools\emsdk\emsdk.bat activate 4.0.11` |
| `tools\jdk17\`, `tools\android-sdk\` | Java 17, NDK 29.0.14206865, platform 36, build-tools 36.1.0 (Android) | `powershell -ExecutionPolicy Bypass -File tools\get_android_tools.ps1 -AcceptLicenses` (every download is checked by SHA-256) |

```bat
tools\pyenv\Scripts\python tools\build_engine.py windows web android
```

A missing toolchain stops the build with its folder named. The first Android build also lets Gradle
download its own libraries into `tools\gradle-home\`.
Results land in `tools\engine\<platform>\`; `tools\engine\build_info.json` records the source hash, the
patches and the hash of every file made. `tests\test_engine_profile.gd` fails if the game starts needing
an engine class the profile leaves out.

## 4. Exports

| What | Command | Result |
| --- | --- | --- |
| Windows, into any folder, checked | `python tools\release\build_windows.py --flavor private --out build\release\private\windows` | `Polox.exe` (the game in one file) |
| Windows, the classic way | `tools\export_windows.bat` | `build\windows\` with the phone version and the Android app beside `Polox.exe` when they are built |
| The phone (web) version | `tools\export_web.bat` | `build\web\`, served by Phone Link |
| Android | `tools\export_android.ps1` | `build\android\polox.apk` (arm64), signed with the key in `tools\android\` |
| Setup program and portable zip | `python tools\release\build_installer.py --source build\release\private\windows --out build\release\private --label Private` | `Polox-<version>-Private-Setup.exe`, `...-Windows-Portable.zip`, `...-SHA256.txt` |

`--flavor public` exports from a tree without `assets\local\` (section 6) and refuses a tree that has
one. Both flavours end with `tools\release\verify_pack.py`, which reads the pack inside the artifact and
fails the build if it holds anything it shouldn't ([RELEASES.md](RELEASES.md)).

**Android signing key.** The first Android export makes `tools\android\` with this PC's key. Keep that
folder and never commit it: Android only updates an installed app with an APK signed by the same key.

## 5. The Windows setup program

It is built with [Inno Setup 7](https://jrsoftware.org/isinfo.php) from
`tools\release\installer\polox.iss`.

1. Get Inno Setup: download `innosetup-7.1.1-x64.exe` from <https://jrsoftware.org/isdl.php> (it is
   signed by Pyrsys B.V.; verify it as that page describes) and install it. For a copy that lives inside
   the project and installs nothing system-wide:
   `innosetup-7.1.1-x64.exe /PORTABLE=1 /CURRENTUSER /VERYSILENT /DIR="<project>\tools\innosetup"`.
   `build_installer.py` looks in `tools\innosetup\` first, then in the usual install folders.
2. Export Windows (section 4), then run `build_installer.py`.

What the setup does, where it puts things, its command-line switches and how upgrades and uninstalling
treat your worlds are described in [RELEASES.md](RELEASES.md) "Windows layout".

**Code signing.** Without a certificate the setup program and `Polox.exe` are unsigned, and Windows
SmartScreen warns the first time they are run. `build_installer.py` prints the signing status Windows
reports for both files. To sign, pass your signtool command:
`--sign "signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a $f"`. No certificate or
password belongs in the repository.

## 6. The public source snapshot

```bat
python tools\release\make_public_source.py ..\polox-public --private-words <a file outside the repository> --gitleaks <gitleaks.exe> --report ..\polox-public-check.md
python tools\release\build_windows.py --flavor public --root ..\polox-public --out build\release\public\windows
python tools\release\build_installer.py --root ..\polox-public --source build\release\public\windows --out build\release\public
```

The first command makes a new folder with a new repository holding one commit, and checks every file
for personal details. It never pushes anything. It copies the last commit; `--worktree` copies the files
as they are now instead (uncommitted changes too, git-ignored files never). The other two build the
public Windows artifacts from that snapshot, using this checkout's editor and engine.

`python tools\release\make_public_source.py --check-checkout` runs the same checks over this checkout
without making anything (`check.bat` does this).

## 7. Other tools

| Tool | What it does |
| --- | --- |
| `python tools\art\make_secret_yams.py` | Draws the public Music-secret pictures (`--check` compares with the committed ones) |
| `tools\blender_scripts\*.py` | How the furniture models, materials and sky were made in Blender 5.2 (`blender -b --factory-startup --python <script>`) |
| `python tools\get_detail_pack.py` | Lists the optional Detailed pack (CC0, about 113 MB); `--download` fetches it into `assets\detail\` |
| `allow_phone_link.bat`, `ping.bat`, `phone_doctor.bat` | Firewall rule, a tiny reachability test server, and the Phone Link doctor |
