# Releases: public and private

Polox is released two ways from the same source. This page says what differs, how each is built and
checked, and where an installed copy keeps things.

## The two flavours

| | Public | Private |
| --- | --- | --- |
| Who it is for | Anyone; published from the public repository | Its owner and the devices on their own private Hub |
| Built from | A tree **without** `assets/local/`: the public source snapshot | The owner's checkout, **with** `assets/local/` |
| Title, Light World, Dream World and battle music | Polox's own tunes, made in code | The owner's soundtrack (`assets/local/music/`) |
| The Soul you steer in battles | The Dream Drop | The owner's picture (`assets/local/pictures/`) |
| Music secret (`yams👀`) | Eight original drawings (`assets/secret/`) | The owner's pictures (`assets/local/secret/`) |
| Optional add-ons | Polox Originals (already what you hear) | Polox Originals, and the owner's own theme packs (`assets/local/addons/`) |
| Everything else | Identical: gameplay, saves, add-on system, Phone Link, sync, platforms | |

Nothing in the game's code knows which flavour it is. A copy that has the private pack uses it; a copy
without it falls back to what the repository carries. That is the whole mechanism:

- `scripts/core/addons.gd` treats `res://assets/local/` as a built-in add-on that is always on, and
  uses Polox's own tunes and the Dream Drop when it isn't there.
- `scripts/ui/secret_pictures.gd` shows the pictures the pack lists under `"secret_images"`, or the
  public set when there is no pack or the list is empty.
- `assets/local/`, `local-addons/` and `assets/music/` are git-ignored, so they can't be committed by
  accident, and the public snapshot is made from what Git tracks (the last commit, or with
  `--worktree` the tracked and untracked files as they are now), never from ignored files.

### Keeping your own customisation

A private build is one way. The other needs no build at all: put an add-on folder in
`PersonalData/addons/` (Title > Add-ons > Open add-ons folder) and it changes music, the Soul, sounds,
tiles and words in any copy of the game, public ones included ([ADDONS.md](ADDONS.md)).

## Building and checking each flavour

```bat
rem Private (from this checkout)
python tools\release\build_windows.py   --flavor private --out build\release\private\windows
python tools\release\build_installer.py --source build\release\private\windows --out build\release\private --label Private

rem Public (from the snapshot)
python tools\release\make_public_source.py ..\polox-public --private-words <file> --report ..\polox-public-check.md
python tools\release\build_windows.py   --flavor public --root ..\polox-public --out build\release\public\windows
python tools\release\build_installer.py --root ..\polox-public --source build\release\public\windows --out build\release\public
```

`build_windows.py` refuses to make a public build from a tree that has `assets/local/`, and a private
one from a tree that doesn't. Every build then passes through `tools/release/verify_pack.py`, which
reads the pack inside the finished `.exe`, web pack or APK:

| Rule | Public | Private |
| --- | --- | --- |
| Nothing from `PersonalData/`, `.polox-local/`, `local-addons/`, `tests/`, `tools/`, `build/`, `docs/`, `assets/music/` | required | required |
| Polox Originals and the eight public secret pictures are inside | required | required |
| Files from `assets/local/` | **none**, by path or as imported copies | **exactly** what the pack's manifests list |

The private Hub keeps working as before: it serves whatever is copied into its download folders, and the
private artifacts are the same files with the content check added in front.

## Windows layout

| | Setup program | Portable zip | From source |
| --- | --- | --- | --- |
| Program files | `%LOCALAPPDATA%\Programs\Polox` ("just me", no administrator), or `C:\Program Files\Polox` ("all users") | Wherever you unzip it | The project folder |
| Your data (worlds, settings, keys, add-ons, logs) | `%LOCALAPPDATA%\Polox\PersonalData` | `PersonalData` beside `Polox.exe` | `PersonalData` in the project folder |
| Start menu, uninstaller | Yes; a desktop shortcut if you tick it | No | No |
| Needs Godot, Python or anything else | No | No | The Godot editor |

`scripts/core/personal_data.gd` decides the data folder in one place. The setup program writes a small
file, `polox-install.json`, beside `Polox.exe`; with it the game is an *installed* copy and keeps its data
outside the program folder. Without it the game is *portable*. If the usual folder can't be written, the
game falls back to `Documents\Polox` and Settings says why.

**Upgrading** an installed copy: run the newer setup. It finds the installed copy by its fixed id,
closes a running Polox, replaces the program files and leaves the data folder alone.

**Coming from a portable copy:** the setup's *Bring your worlds along* step takes the old Polox folder
(or pass `/IMPORTFROM="C:\Old Polox"` to a silent install). The first start of the installed game copies
that copy's PersonalData in, checks every file by SHA-256, and never changes the old folder. Naming
another copy during a later upgrade adds only the worlds that aren't there yet; nothing is ever replaced
or merged. Installing over a portable copy's own folder is detected and handled the same way.

**Uninstalling** removes the program files, the shortcuts and the marker. It asks whether to keep your
worlds, with "keep" as the default; a silent uninstall keeps them unless `/REMOVEDATA` is given.
Reinstalling finds them again.

**Setup switches**, besides Inno Setup's own (`/SILENT`, `/VERYSILENT`, `/DIR=`, `/CURRENTUSER`,
`/ALLUSERS`, `/TASKS=desktopicon`, `/LOG=file`): `/IMPORTFROM="folder"`; the uninstaller takes
`/REMOVEDATA`.

**Signing.** No code-signing certificate is used unless `build_installer.py --sign` is given, so the
published setup programs are unsigned unless their release notes say otherwise. Each release carries a
`...-SHA256.txt`; compare it before running a download:
`Get-FileHash .\Polox-<version>-Setup.exe -Algorithm SHA256`.

## History, and why the public repository starts fresh

The private repository has 160 commits on 17 branches, all made under the owner's own name and e-mail. Before the privacy pass of November 2026 the
tests, logs and notes in it contained the build PC's network addresses, machine name, tailnet name and
user folder (about eight commits each), and a later commit holds private pictures. Rewriting that
history would not remove what older clones and branches already hold, and would break the owner's local
branches.

So the public repository is a **snapshot**: `tools/release/make_public_source.py` copies the committed
files of the current commit into a new folder, leaves out `docs/history/` and `storefront/`, makes one
commit by a neutral author, and then checks every file (text and binary) for personal details, including
the build PC's own names and addresses read from the system at that moment. The private checkout and
its history are not modified. Later public releases are made the same way: a new snapshot, compared with
the public repository and committed on top of it.
