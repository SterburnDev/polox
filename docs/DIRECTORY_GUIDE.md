# Where things are

Start with the entry points below or search for a feature tag in the script headers.

## Start here

| What | Where |
| --- | --- |
| The game starts | `project.godot` → `scenes/main.tscn` → `scripts/core/main.gd` (`_ready`, then the title) |
| Before anything else (autoloads, in order) | `SaveManager` (the data folder, worlds, files), `ChatLog`, `AIClient`, `GameState` (settings and the open world) |
| The title screen | `scripts/ui/title_screen.gd` (built by `main.gd show_title`) |
| A world | `scripts/world/game_world.gd` (made by `main.gd start_game`; loaded in the background while the title shows) |
| Every menu screen | built on `scripts/ui/screen_panel.gd`; opened with `main.open_panel(...)` |
| The look of every control | `scripts/ui/theme_builder.gd` (+ `glass_box.gd`); rules in `docs/STYLE_GUIDE.md` |
| Run it | `run.bat` (Windows), `run.sh`; tests: `check.bat` or `godot --headless --path . --script res://tests/run_tests.gd` |
| Build it | `tools/export_windows.bat`, `tools/export_web.bat`, `tools/export_android.ps1` |

## Folders

| Folder | Responsibility |
| --- | --- |
| `scripts/core/` | Start-up, saving and loading, settings, migrations, the data folder, graphics, logs, debug drives |
| `scripts/ui/` | Screens and widgets: title, Settings, menus, editors' panels, the theme |
| `scripts/world/` | The 3D world and room data shared with play mode, including furniture, the camera, music and the Dream Gate |
| `scripts/builder/` | The in-world editor, including tool routing, room edits, placement previews, the palette and saved shortcuts |
| `scripts/characters/` | Friends and the player: looks, animation, daily life |
| `scripts/ai/` | Talking with friends: the AI client, providers, prompts, replies |
| `scripts/home/` | The Light World: mapping your real home and street (`osm.gd`, `google_maps.gd`), and the helpers that look it up |
| `scripts/battle/` | Battles and the Battle Maker |
| `scripts/platform/` | Platform Mode gameplay (running and jumping) |
| `scripts/phone/`, `scripts/net/` | Phone Link (the PC serving the phone), the Android app's link, network checks |
| `scripts/items/`, `scripts/variety/` | Items and the bag; stories, quests, daily events, the Almanac, and playful charm/secrets (`whimsy.gd`) |
| `scripts/sync/` | Cloud folder sync (one package file per world), and the field-by-field JSON merge it shares with Phone Link |
| `assets/` | Pictures, models, materials, sounds. `assets/local/` (git-ignored) holds your local soundtrack, Soul, and secret vault pack |
| `bundled-addons/`, `local-addons/` | Add-ons that ship with the game; your own local add-ons (git-ignored). Format: `docs/ADDONS.md` |
| `.github/` | GitHub Actions hygiene workflow, issue templates, and PR checklist |
| `tests/` | Feature suites (`test_<area>.gd`), fixtures, and Phone Link browser and network checks under `tests/e2e/` |
| `tools/` | Export entry points, engine setup, `setup_local_pack.py`, and firewall/network utilities. `tools/release/` builds and checks releases. Asset preparation lives in `tools/blender_scripts/` and `tools/art/`. |
| `native/`, `addons/polox_android/` | Custom engine patches and Android plugin source under `native/`, plus the editor plugin that registers the Android build dependency |
| `docs/` | For players: `PLAYER_GUIDE.md`, `PHONE_SETUP.md`, `PHONE_TRIAGE.md`, `PHONE_TEST.md`, `SYNC.md`, `ADDONS.md`, `GRAPHICS.md`. For developers: `BUILDING.md`, `RELEASES.md`, `STYLE_GUIDE.md`, `API_VERIFICATION.md`, this one. Rights: `ASSET_AUDIT.md`, `ASSET_CREDITS.md`, `LICENSING.md`. `docs/history/` keeps old plans, reports and verification notes (private; not in the public snapshot) |
| `PersonalData/` | Your data when run from source (git-ignored, never exported): see below |

## Feature map (tags)

| Tag | What it covers | Main entry points |
| --- | --- | --- |
| `[PERSONAL_DATA]` | Where your saves, settings, keys, logs and pictures live | `core/personal_data.gd` (the folder), `core/save_manager.gd` (`_default_root`, `open_personal_data`) |
| `[MIGRATION]` | Bringing older save folders and layouts over | `core/personal_data_migration.gd`, `core/migration.gd`, `core/layout_migration.gd`, `core/world_migration.gd` |
| `[EASTER_EGG]` | The title's Music secret | `ui/settings_music_tab.gd` (`_on_scroll_changed`, `_secret`), `ui/secret_pictures.gd`, `ui/title_screen.gd` (`eyes`) |
| `[LIGHT_WORLD_MAP]` | The World Map's hand-drawn neighbourhood, and mapping it | `ui/world_map_view.gd` (`_show_hood`), `home/hood_map_view.gd`, `home/osm.gd` (fetching), `home/map_validation.gd` |
| `[AI_HELPER]` | Friends' replies and the home helpers | `ai/ai_client.gd` (`chat`), `ai/conversation.gd`, `world/talk_controller.gd`; helpers: `home/research.gd`, `home/helper_*.gd` |
| `[PAIRING]` | Pairing a phone with the PC | `ui/app_connect_panel.gd` and `phone/sync_client.gd` on the phone, `phone/pairing.gd` for PIN and device rules, and `phone/pairing_store.gd` for private device records |
| `[PLATFORM]` | Differences between PC, Android and the browser | `core/device.gd`, `ui/touch_gestures.gd`, `core/android_native.gd`, `core/graphics.gd` |
| `[GRAPHICS]` | Quality, PC graphics, the Detailed pack | `core/graphics.gd`, `core/pc_detail.gd`, `ui/settings_graphics.gd`, `world/detail_pack.gd` |
| `[GLASS_UI]` | The glass theme and Settings controls | `ui/theme_builder.gd`, `ui/glass_box.gd`, `ui/stepper.gd`, `ui/more_below.gd` |
| `[BUILDER]` | Building in a room | `builder/build_mode.gd` routes input, `builder/build_tools.gd` applies edits, and `builder/editor_shell.gd` lays out the UI |
| `[BATTLE]`, `[BATTLE_MAKER]` | Running battles and editing battle content | `battle/battle_director.gd`, `battle/battle_state.gd` (`resolve_queue` for turn rules), `battle/battle_screen.gd`, `battle/battle_maker.gd` |
| `[DRAWING]`, `[ADDONS]` | Drawing and add-on discovery | `ui/paint_canvas.gd`, `core/addons.gd` |
| `[CLOUD_SYNC]` | The same worlds with the PC off | `sync/cloud_sync.gd` (the rules), `sync/cloud_package.gd` (what may be sent), `sync/cloud_service.gd`, `ui/cloud_sync_tab.gd` |
| `[GOALS]` | Optional goals: quests, titles, what is coming up | `variety/quests.gd`, `variety/almanac.gd` (`coming_up`, `new_titles`), `ui/almanac_panel.gd`, `ui/quest_log_panel.gd`, `ui/today_card.gd` |

## Path conventions

- Use `res://` for shipped resources and keep the `.uid` beside each script when moving it. Check loads from code, scenes, settings, and tests before reimporting and verifying exports.
- Resolve private files under `SaveManager.root`, which uses `PersonalData.folder()` at startup. Use a disposable `--save-root` for test drives.
- Build entry points derive the project root from their own location. Invoke them by full path from another folder. Relative values for Android's `-OutputDirectory` start at the project root.

## Data flow worth knowing

- **Your data folder** is resolved once, in `PersonalData.folder()`, when `SaveManager` starts (before every
  other autoload). Everything personal is a path under `SaveManager.root`: `settings.json` (settings, AI
  keys), `slots/<world>/` (each world), `my_home/` (your real home and street), `phone/` (Phone Link
  pairing), `logs/`. (The Music secret's pictures are built into the game: `assets/secret/`.) Nothing personal is written
  elsewhere, with one deliberate exception: a home helper's temporary job folder (`helper_codex.gd
  jobs_dir`) is outside any repository by design, and deleted when the job ends.
- **Settings** are a dictionary in `GameState.settings`; `GameState.save_settings()` writes them and emits
  `settings_changed`, which `main.gd apply_display_settings` follows (UI size, graphics, the theme).
- **A friend's reply:** dialogue box `sent` → `talk_controller._on_sent` → `conversation.player_says` →
  `AIClient.chat` (one request at a time, retries, friendly errors) → the reply's segments back in the box,
  and the line in `ChatLog`.
- **Pairing:** the phone's keypad → `phone_mode.pair_with` → `sync_client.pair` (POST `/api/pair`) → the PC's
  `pairing.pair` (constant-time compare, rate limits, never logs the PIN).
- **Debug drives** (`core/debug_drives.gd`, `--drive=<name>`) script the game for screenshots and checks;
  they only run when asked for on the command line.
