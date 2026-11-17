# Compatibility and performance: Polox 1.29.0

What was built, what it was run on, and what happened. Builds, automated tests, Phone Link
end-to-end runs and performance were measured on 15 November 2026; the public source snapshot, the
public Windows and web builds made from it and the whole test suite (in the owner's checkout and in the
snapshot) were redone on 16 November 2026; the clean Windows 11 VM setup checks below were run on
11 November 2026 and not repeated after the later fixes. Anything that was not run says so; nothing here
is inferred.

## What was built

| Artifact | Flavour | Size | Signed | Contents checked |
| --- | --- | --- | --- | --- |
| `Polox-1.29.0-Setup.exe` | Public | 35.2 MB | No | 1,077 packed files, none from the private pack (16 November) |
| `Polox-1.29.0-Windows-Portable.zip` | Public | 44.1 MB | No | The same `Polox.exe` (16 November) |
| The web version (`build/web`, what Phone Link serves) | Public | 54.0 MB pack | n/a | 1,132 packed files, none from the private pack (16 November; the 15 November `Polox-1.29.0-Web.zip` held 1,130) |
| `Polox-1.29.0-Private-Setup.exe` | Private | 194.6 MB | No | 1,318 packed files, 40 from the private pack, as its manifest lists |
| `Polox-1.29.0-Private-Windows-Portable.zip` | Private | 216.3 MB | No | The same `Polox.exe` |
| `Polox-1.29.0-Private-Web.zip` | Private | 142.3 MB | n/a | 1,208 packed files, 40 from the private pack |
| `Polox-1.29.0-Private.apk` | Private | 118.8 MB | With this PC's own Android key | 1,157 packed files, 40 from the private pack |

Each folder has a `...-SHA256.txt`. "Contents checked" is `tools/release/verify_pack.py`, which reads the
file list inside each build and fails if a public build holds anything private or a private build holds
anything its manifest doesn't list. The public builds (build `b9c564deb73eb909`) were exported from the
public source snapshot (`tools/release/make_public_source.py --worktree`: 1,440 files in one commit by a
neutral author, 36 private files excluded, 0 findings, gitleaks clean), never from the owner's checkout.
The private builds are the 15 November ones. On 17 November the licence changed from MIT to GPL-2.0-or-later:
the public setup program and portable zip were rebuilt to carry it (sizes unchanged), and `Polox.exe` and
the web pack were kept, since no game file changed (same build id; both packs passed again).

**Signing.** The Windows files are **not code-signed**: no certificate was available. Windows shows
"The publisher could not be verified" when the setup program is started from a download (seen in the
test below), and SmartScreen may add its own warning. `build_installer.py --sign` signs the setup
program and its uninstaller when a certificate exists. **No public Android APK was built**: an APK has
to be signed with a key, and which key signs public releases is the owner's decision.

## Automated tests

| Run | Result |
| --- | --- |
| The whole suite (`check.bat` / `tests/run_tests.gd`), 16 November | **772 of 772 passed** in the owner's checkout and **772 of 772** in the public snapshot's own folder, with only what a fresh clone has (the Godot editor from `tools/get_godot.ps1`'s checked zip). Both: every script parses, smoke run clean, no script errors outside the expected `[expect-script-error]` blocks, nothing leaked at exit; the checkout's run also passed the personal-details scan |
| The exported public `Polox.exe`, headless smoke drive | `[smoke] ok`, no errors printed |
| Phone Link end to end (`tests/e2e`: the real server on this PC's real addresses, pairing, sync both ways, a deliberate conflict, the AI proxy, attacks) | **9 of 9 passed** against the 1.29.0 public web build (`b97da8c160de5323`), including a headless phone-size browser (Edge) that opens the launcher, types the PIN, opens a world, places a block and syncs it to the PC |
| What each build contains (`verify_pack.py`) | The public Windows and web packs of 16 November pass; the three private packs of 15 November passed |
| Public snapshot scan (machine facts, private words, key shapes, file names, binaries, picture metadata, gitleaks) | 0 findings in 1,440 files; no metadata in any of the 110 pictures (JPEG, PNG, WebP, SVG); gitleaks clean on the commit and the folder. The exported `Polox.exe`, web pack and setup program hold none of the build PC's names, user folder or addresses |

The end-to-end suite was run in the public snapshot's own folder with the 1.29.0 public web files;
the owner checkout's `build/web` (served by the private Hub) was left untouched.

The 15 November 2026 refresh also verified:
- Script tidying across `hood_builder.gd`, `home_edit.gd`, `layout_builder.gd`, `battle_screen.gd`, `main.gd`, and `sync_client.gd`, checked against baseline snapshots (`6f23e608f81a8287d4e0ae892bd0a53ff2f2f5f04825bdd4783f4c7747bbe67a`) via `tools/builder_snapshot.gd`.
- Real Info-folder landmark lookup flow and room/floor/storey preservation, covered by `tests/test_light_world_info.gd` (**8 of 8 passed**).
- Accessibility audit across 23 screens (44 x 44 px click / 48 px touch targets, WCAG 2 contrast on solid, faded and Liquid Glass surfaces, and `Reduce motion`), covered by `tests/test_accessibility.gd` (**8 of 8 passed**).
- API key format detection/migration, four-way error classification, Ollama `/api/tags` probing, cold/warm timeouts, single-flight queuing/cancellation, log/report scrubbing (`test_api_keys.gd`, `test_ai_providers.gd`, `test_ai_fallback_model.gd`), and keeping UI copy within cap (`test_soul.gd`: `1,004` of `2,021` words).
- Light World terrain detail scale, translucent glowing lantern glass, UV/collision checks, credit/manifest updates, and stripped JPEG EXIF/XMP metadata (`test_update10_assets.gd`, `test_update9_assets.gd`).
- Full-suite cleanups: instance-ID guard in `main.gd` deferred sizing, `music_player.gd` stream cleanup on exit, random port retry in `test_phone_launcher.gd`, and placeholder path cleanup in `tests/test_light_world_info.gd`.

## The Windows setup program on a clean PC

Machine: a VirtualBox guest with a fresh Windows 11 Home (build 26300), a standard user (no
administrator rights used), 16 GB RAM, no Godot and no Python installed. The guest has no graphics
driver (Microsoft Basic Display Adapter), so the game was started there with `--headless`: everything
runs except drawing. See "Not verified" below.

| Step | What was done | Result |
| --- | --- | --- |
| Download check | SHA-256 of the file in the guest against `...-SHA256.txt` | Match |
| Start from a download | Double-click equivalent on a file marked as downloaded | Windows asks "The publisher could not be verified" (unsigned); Run continues |
| Clean install | The wizard, for this user only, default folder | Installed in under 40 s to `%LOCALAPPDATA%\Programs\Polox`; Start menu entry, optional desktop shortcut, one entry in Installed apps with the version; the licences in `licenses\` |
| First launch | `Polox.exe` on a PC that never had Polox | Starts, makes a world, talks, gives a gift; data appears in `%LOCALAPPDATA%\Polox\PersonalData`; nothing is written beside the program |
| Saving and reopening | Close, start again, continue | The same single world, its chat log intact |
| Update | 1.28.4 installed, then the 1.29.0 setup over it | One entry, now 1.29.0; the world made by 1.28.4 opens in 1.29.0; session log clean, no errors printed |
| Uninstall, keeping worlds (the default answer) | The uninstaller, silent and with its question on screen | Program, shortcuts and the Installed apps entry gone; worlds and settings kept |
| Reinstall into a folder with spaces | `...\My Games\Polox Test Install` | Installs and runs from there; the earlier world is still there; Start menu points at the new folder |
| Uninstall, deleting worlds | `/REMOVEDATA` (the "No" answer) | Program and `%LOCALAPPDATA%\Polox` both gone |
| Bringing a portable copy's worlds along | A fresh install told about an old `Polox` folder with a `PersonalData` in it | The first launch copies that world in; the old folder is left as it was |

Two things the clean PC showed, both fixed in this release: the wizard asked people to accept the
licence, then MIT (it no longer has that page) and showed a phone-files choice that the build didn't contain; and
the game printed an engine error at every start on a PC without the Codex command-line tool.

## Saves

| Save | Opened with 1.29.0 | Result |
| --- | --- | --- |
| A new world | Yes (tests, the clean PC, every capture) | Works |
| A world made by 1.28.4 on the clean PC | Yes | Opens; nothing migrated or lost |
| A copy of an older real save folder (three worlds, format 8.0, made over many versions) | Yes, twice | Opens with no script errors; its ten already-earned titles are recorded quietly, none announced |
| Worlds in older folder layouts (`Documents\Polox`, `.polox-local`, beside a portable `Polox.exe`) | By `tests/test_personal_data.gd` | Brought over once; the old folder is never changed |

## Platforms

| Platform | What ran | What did not |
| --- | --- | --- |
| Windows 11 (this PC, a real graphics card) | The exported 1.29.0 `Polox.exe`: the performance runs below (15 November 2026) and every release capture (11 November 2026) | |
| Windows 11 (clean VM) | Install, update, uninstall, data handling, the game without drawing (11 November 2026) | The game on screen: the VM has no graphics driver. Polox needs Vulkan or OpenGL 3.3 from a real driver |
| Web (phone browser through Phone Link) | The public 1.29.0 build (`b97da8c160de5323`), played by a headless phone-size browser through the real Phone Link server on this PC's network addresses (the end-to-end suite) | Not opened on a real phone in this pass |
| Android | The APK builds, is signed and its contents are verified; the new document-picker code compiles | Not installed on a phone or emulator in this pass |

## Performance

The exported public `Polox.exe`, 1.29.0, on the development PC, with vertical sync and the frame cap
off so the numbers show cost, not the display's rate. `--drive=perf_scenes`, four seconds a scene,
made-up scenes only (run sequentially on 15 November 2026).

| Scene | Desktop renderer, 1280 x 720: average frame | Worst frame | Draw calls | Phone-style (OpenGL, 412 x 892, touch UI): average frame | Worst frame | Draw calls |
| --- | --- | --- | --- | --- | --- | --- |
| Title | 0.32 ms | 121.3 ms (the first frame) | 42 | 0.72 ms | 123.3 ms (the first frame) | 42 |
| Dream World home | 1.12 ms | 43.2 ms | 118 | 1.22 ms | 15.1 ms | 81 |
| Dream World garden | 1.02 ms | 2.2 ms | 69 | 1.01 ms | 8.0 ms | 47 |
| Light World room | 1.25 ms | 1.8 ms | 127 | 1.32 ms | 4.1 ms | 138 |
| Light World house and street | 1.34 ms | 2.8 ms | 156 | 1.28 ms | 10.8 ms | 129 |

Video memory in use was 270.2 to 291.2 MB across 3D scenes (45.7 MB on Title) with the desktop renderer and 64.3 to 84.5 MB (43.7 MB on Title) phone-style. A 60 Hz
display allows 16.7 ms a frame, so on this PC every scene has more than ten times the room it needs.
"Phone-style" is the phone's renderer and layout on a PC graphics card: it compares versions, it does
not predict a phone. Nothing was optimised in this release, because nothing measured needed it.

The two art changes cost two extra small meshes per sign and one texture on the ground plane.

## Not verified

- The game drawn on screen on a second, clean PC (the VM has no graphics driver).
- The Web build on a real phone's browser, and the APK on a phone or emulator, for 1.29.0.
- Cloud sync through a real cloud app between two real devices, and Android's file picker on a device.
- A code-signed setup program, and SmartScreen's behaviour with one.
- The providers listed as not verified in [API_VERIFICATION.md](API_VERIFICATION.md).
