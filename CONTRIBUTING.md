# Contributing to Polox

Thanks for wanting to help. Polox is a small project with a few firm habits; this page is the short
version of them.

## Set up

1. Get the source and run `tools\get_godot.bat` once (Windows). It downloads the Godot 4.7.2 editor and
   checks it against the published SHA-512. On macOS or Linux install Godot 4.7.2 yourself.
2. `run.bat` (or `./run.sh`) plays from source. Your saves go to `PersonalData/`, which Git ignores.
3. `check.bat` imports the project, parse-checks every script, runs the test suite and a smoke run. It
   must end with `ALL GOOD` before you send a change. `check.bat test_battles` runs one suite.

Nothing else is needed to work on the game. Exports and the engine build are described in
[docs/BUILDING.md](docs/BUILDING.md); you only need them to change how Polox is packaged.

## Finding your way

[docs/DIRECTORY_GUIDE.md](docs/DIRECTORY_GUIDE.md) lists the entry points, the folders by feature and the
searchable tags. Every script starts with a `##` comment that says what it is for and ends its header
with `## Tags: [BATTLE] ...`; search for a tag to find every part of a feature.

## What a change needs

- **One thing per change.** Keep a file move, a rename, a behaviour change and an optimisation in
  separate commits so each can be reviewed and undone on its own.
- **A test** for behaviour that can break quietly: anything that reads or writes saved files, the sync
  rules, the add-on loader, pairing. Tests live in `tests/test_<area>.gd`, use `tests/test_case.gd`, and
  never touch the network or a real save folder (`fresh_save_root()` gives each test its own).
- **Old saves keep working.** A world made by an earlier version must load and play. If a file's format
  changes, add a migration and a test that loads the old shape. Ids that are stored in saves
  (`dark_fountain`, room and item ids) are never renamed.
- **Checked by using it.** Besides the tests, open the screen you changed and use it with the mouse and,
  for anything a phone shows, at a phone size
  (`--resolution 412x892 -- --touch-ui --save-root=<a scratch folder>`). Always pass `--save-root` when
  you launch the game for a check, so it never opens your real worlds.
- **A changelog line** in `CHANGELOG.md` under "Unreleased", written for a player.

## Style

- GDScript only, tabs, typed variables and return types (`var count := 0`, `func f() -> bool:`).
- Names say what a thing is: `selected_tile`, not `st`; `_on_send_pressed`, not `_cb2`.
- Small functions that do one thing. If a function needs a comment for each paragraph, split it.
- Comments explain *why*, the order things must happen in, units, and what a caller may rely on. They
  don't repeat the code.
- Keep UI, rules, storage and network apart: a screen asks a rules script, which asks a storage script.
  `scripts/battle/battle_state.gd` (rules) and `battle_screen.gd` (UI) show the split.
- Bundled files are `res://` paths; anything personal is a path under `SaveManager.root`. Never build a
  path from the working directory.
- User-visible text is plain and kind, in sentences a ten-year-old can read. The UI rules (sizes,
  colours, the glass finish, touch targets) are in [docs/STYLE_GUIDE.md](docs/STYLE_GUIDE.md).

## Privacy and assets

- No personal details in the repository: no real names, addresses, network addresses, machine names,
  phone models or serials, user folders, e-mail addresses or keys, including in tests, docs and
  screenshots. Use these placeholders:
  - people and devices: `Robin`, `Example Phone`, `EXAMPLE0001`, `example-pc`
  - e-mail and web: `robin@example.com`, `https://example.com`
  - folders: `C:\Users\Player`
  - keys: `test-key-not-real`, or a fake key built at run time (`"sk-" + "x".repeat(40)`), never one literal
  - addresses: `192.0.2.x` (RFC 5737) where the kind of address doesn't matter. Phone Link and the
    report sink refuse public addresses (`scripts/phone/net_rules.gd`), so a test of a home network or
    Tailscale needs `192.168.1.x` / `10.5.0.x` / `100.64.0.x`, and Tailscale names `desktop-test.tail000.ts.net`.
  `check.bat` runs `python tools/release/make_public_source.py --check-checkout` over every file Git
  sees (with your own words list too, if you keep one: `POLOX_PRIVATE_WORDS`).
- Only add assets you made yourself or that are CC0, and record where each came from in
  [docs/ASSET_AUDIT.md](docs/ASSET_AUDIT.md). Songs, fonts and pictures "found online" can't be accepted.
- Keys and tokens belong in the player's `settings.json`, which is never committed, exported or synced.

## Licence

By sending a change you agree that it may be distributed under the repository's licence
([LICENSE](LICENSE), explained in [docs/LICENSING.md](docs/LICENSING.md)).
