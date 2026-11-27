# Changelog

## Polox Public Beta 1.02 (1.0.2) — Skip-to-Template, Local-Only Clarity, Mochi Soul & Built-in Soundtrack (2026-11-26)

- **Light World creation is clearly optional (skip & use a template):** Added a prominent **SKIP & USE A TEMPLATE** banner at the top of the Light World creation sequence (`survey_screen.gd`), four ready-made Light World templates in `light_home.gd` (*Cozy Bedroom*, *Sunlit Studio*, *Cozy Apartment*, *Garden Cottage*), and a **Use template** picker in *Settings > Light World*.
- **Device-local privacy made unmistakable:** Title screen, *New world*, onboarding, *Settings > Light World*, and the Survey all state clearly that everything stays on your device unless you choose to use a cloud service or online AI/map service.
- **Mochi Soul everywhere & 5 built-in music overrides:** `Mochi.png` now renders as the Soul across the title screen, battles / Battle Maker, and the Survey cursor (`survey_screen.gd` `Heart`). Shipped the five distinct built-in tracks in `assets/local/` covering *Light World creation*, *Title menu*, *Dream World*, *Battle*, and *Light World* as separate slots (*Polox Originals* in *Title > Add-ons* still restores Polox's procedural tunes and Dream Drop anytime).
- **Google Drive & Cloud folder sync on mobile (Android):**
  - Fixed Android `CloudDocuments` persistable URI permission handling, output stream truncation/flush for Google Drive, and 0-byte newly created `ACTION_CREATE_DOCUMENT` placeholders so first-time Android uploads to Google Drive succeed cleanly instead of reporting a damaged package.
  - Added Android **Cloud Folder** (`ACTION_OPEN_DOCUMENT_TREE` + `CloudStore.TreeStore`) support alongside direct **Google Drive / OneDrive / Dropbox** file picking, plus **Relink file…**, mobile `AutoSync`, `Worlds` quick `.poloxsync` import & **☁ Cloud** shortcut, and a **☁ Google Drive / Cloud** option on the mobile connect screen.
- **Cross-platform update detection (Windows PC & Android):** Added `UpdateChecker` (`scripts/core/update_checker.gd`) and *Settings > Gameplay > Updates* + Title screen **⬆ Update available** badge (`settings_updates.gd`) checking public GitHub Releases (`SterburnDev/polox`) at most every 12 hours (toggleable, offline-safe, strict GitHub HTTPS link validation) with Android APK direct download and Windows release links.
- **Cybersecurity touch-ups:**
  - `custom_models.gd`: added cycle detection and node-count caps (`MAX_GLTF_NODES`) on glTF node hierarchies, cumulative buffer size limits, and stride/vertex/index/triangle caps on `.glb`/`.gltf`/`.obj` imports.
  - `slot_archive.gd`: blocked executable/script extensions (`FORBIDDEN_EXTS`) and oversized single entries (`MAX_ENTRY_BYTES`) when inspecting `.polox` and backup zip bundles.
  - `map_refs_panel.gd` & `map_home_panel.gd`: added `safe_maps_url()` HTTPS + Google Maps host validation and rejected whitespace/control characters before `OS.shell_open`.
  - `key_format.gd` & `make_public_source.py` & `.github/workflows/ci.yml`: expanded token/key scrubbing patterns (`gh*`, `github_pat_`, `hf_`, `xai-`, `pplx-`, `AKIA`, `gsk_`, `AQ.`, `VENICE-`) and hardened CI workflow (`timeout-minutes`, `persist-credentials: false`).

## Polox Public Beta 1.01 (1.0.1) — Phone Link security release (2026-11-23)

Phone Link on Same Wi-Fi no longer hands anything that opens your worlds to someone watching the network, and it checks more of what it receives. Phones that paired with an earlier Polox keep working; pair them again to get the new protection.

- **Pairing on Same Wi-Fi no longer shows the PIN or the phone's key to anyone listening (pair_v:1).** The launcher and the Android app seal the PIN to an RSA-2048 key the PC makes for the session (memory only), and the key comes back encrypted and authenticated. A changed answer ends at "Response didn't verify: possible interference" with nothing kept. Both screens then show three **check words**: compare them, and tap *They don't match* if they differ (the new key is forgotten on both sides). Every old limit still applies (cooldowns, the hourly pause, the PIN changing after 10 wrong tries), and a seal that doesn't open counts as a wrong PIN. Older apps keep pairing the old way, and the PC warns "paired the old way" for them. An app that paired safely with a PC refuses the old way from that PC.
- **And the key never travels again.** After a pair_v:1 pairing the launcher, the phone game, the Android app, its AI chats and home lookups through the PC, and Check connection all sign every request (`Authorization: Polox-Sig`: HMAC-SHA256 over the method, the address, the body, a time and a one-use nonce) instead of sending the key. The PC refuses that phone's bare key. A phone whose clock is far off gets the PC's time back and corrects itself. Phones that paired the old way keep working as before. What is synced still travels unencrypted on Same Wi-Fi (`SECURITY.md`, Known limits).
- **The PC signs its answers too.** Every answer to a signed request carries `X-Polox-Sig`, tied to that request. The Android app, the phone game and the launcher use no answer that was changed on the way: they say "didn't verify: possible interference" instead.
- **No DNS rebinding.** A web page that points its own domain at your PC (to read Phone Link as if it were that page) is refused before anything is served. Phones reaching the PC by address, by its name, through `.local`/`.lan` names or Tailscale are unaffected.
- **Stricter pages.** The launcher, `/hello` and `/app` pages carry a Content-Security-Policy: only their own inline code runs, they talk only to the PC, and nothing can frame them.
- **`/hello.json` tells strangers less.** Without a paired key it says only that Polox is there, its version and the PC's name. The addresses, the Tailscale name and the app version go to this PC itself and to paired phones (the app now asks again with its key after pairing, so it still learns the Tailscale address).
- **Housekeeping:** upload chunks a phone abandoned (`.part`) are removed after a day, the wrong-PIN flood guard forgets addresses after an hour, a phone report that arrived in a GET address (anyone can make such a link) is marked ⚠ on the PC, and `audit.log` notes how each phone paired and the check words, never a key or a PIN.

## Polox Public Beta 1.0 (1.0.0) — Public GitHub Release (2026-11-18)

- **Version & public GitHub polish:** Set release label to **Polox Public Beta 1.0** (`1.0.0`, Android version code `110000`: codes now start at 100000, so the app still installs over 1.29.0 (12900) as an update), added `.github/` CI hygiene checks and issue/PR templates, added `docs/INDEX.md`, `docs/GOOGLE_MAPS.md`, and `tools/setup_local_pack.py`, and renamed the last legacy player-facing `"Dark World layout"` folder shortcut/guide text to `"Dream World layout"` while preserving all save compatibility.
- **Redesigned Dream Gate (`scripts/world/fountain_node.gd`):** Rebuilt the Dream Gate as a sculpted, reddish glazed-ceramic bathtub-like basin with curved slipper backrest, blush-ivory rolled rim, antique brass clawfeet and curved faucet, luminous ruby-crimson liquid & flowing jet (golden for homeward gates), shared compiled shaders, and a secret floating rubber ducky if you poke the tub three times.
- **Settings > Music HTML-tab secret & keyword vault (`settings_music_tab.gd`, `secret_pictures.gd`, `tools/art/make_secret_yams.py`):** Added a dedicated bottom scroll runway so the Music tab scrolls all the way down like an HTML tab to reveal `yams👀`. Typing `aero`, `frutiger`, `code`, or `rot` arms the built-in secret vault (pulling built-in local secret pack images when present, or four new original public Frutiger Aero / code / rot SVG artworks otherwise).
- **Google Maps integration for Gemini & Google AI Plus users (`scripts/home/google_maps.gd`):** Added opt-in Gemini Maps Grounding (`google_maps` + `google_search` tools), optional Google Maps Places API (New) nearby public-landmark enrichment, and offline Google Maps URL coordinate parsing (`@lat,lon`, `?q=lat,lon`, `!3d...!4d...`), with explicit consent prompts, key scrubbing, and local caching.
- **Custom 3D models, procedural PBR textures & style:**
  - Added runtime `.glb` / `.gltf` / `.obj` custom 3D model importing and auto-normalized placement (`scripts/world/custom_models.gd`, `block_factory.gd`, `object_editor.gd`).
  - Added 6 sculpted 3D props in `furniture.gd` (`lava_lamp`, `arcade_cabinet`, `crystal_cluster`, `yam_plush`, `aquarium_orb`, `crt_tv`) with PBR clearcoat/metallic/emissive materials.
  - Upgraded `surface_detail.gd` to fast `PackedByteArray` generation with Sobel normal maps (`normal_texture()`) and 4 new surface styles (`aero_tile`, `dream_brick`, `checkered`, `tatami`), plus one-click texture pattern presets and seam-wrap offset in `tile_paint_panel.gd`.
  - Refined `shaders/aero_backdrop.gdshader` twilight aurora sheen and `dark_look.gd` Deep Dream World rendering.
- **Performance & readability optimizations:** Eliminated per-frame `load()` calls in `light_life.gd` `_process`, eliminated per-frame actor array allocations in `game_world.gd`, skipped wasted procedural mesh construction/destruction in `furniture.gd` when Blender/Kenney `.glb` models are used, shared compiled shaders in `fountain_node.gd`, sped up `soul.gd` via `PackedByteArray`, and refactored core scripts for readability.
- **Playful human charm (`scripts/variety/whimsy.gd`):** Added rotating multi-inspect furniture jokes, clickable version-badge gags and typed word secrets on the title screen, quirky practice battle idle lines, and fresh uniquely-voiced Bramin flavour lines in `voices.gd`.

## Unreleased (pre-Beta 1.0 hardening)

- **Privacy, said plainly.** The first-run screen and *My character* now say that everything about you is optional and stays on this device unless you connect cloud sync (like Google Drive) or an online AI yourself. New `PRIVACY.md` lists every feature that can send anything, what it sends and to whom, and ships with the setup program and the portable zip; `SECURITY.md` says how to report a problem and what the code enforces. The README has both in short, and a step-by-step "Build it yourself".
- **Only web pages open from a home lookup.** A source or "look it up yourself" link from research or a synced home file opens only if it is an `http(s)` address.
- **A key only ever goes to its own service.** Polox reads the mark at the front of an API key (Groq `gsk_`, Google `AIza` and the newer `AQ.`, Anthropic `sk-ant-`, OpenAI `sk-proj-` / `sk-`, OpenRouter `sk-or-`, Venice's own) and never keeps one for another provider: Settings says whose it is and where it goes, with one tap to the right provider, and a settings file with a key filed in the wrong place is put right when it loads. A key with no known mark stays where you put it. A pasted key is tidied first (quotes, spaces, line breaks, `Bearer`, a `NAME=` copied from a terminal).
- **Four different answers, said as four.** A refused or expired key, an account with no credit left, a provider refusing your network or region, and a real rate limit are told apart the same way in chats and in the home helpers. Only a rate limit is waited out: for as long as the provider asked (1 to 60 seconds), counting down. **Test connection** becomes **Stop** while it runs, changing the provider or key ends a wait at once, and **List models** says why it found none.
- **Keys stay in `settings.json`.** The home helpers' keys are kept out of chat logs like the chat keys, anything shaped like a key is taken out of logs, chat exports and crash reports even if it was never saved, and `docs/API_VERIFICATION.md` lists the rules.
- **Closing Polox lets go of everything.** Work on other threads (the Claude Code sign-in check, a Codex run that can take minutes) is told to stop before the game waits for it, so closing no longer hangs on it, and Codex's prompt file is removed even when its screen closes mid-run. Streamed songs (the world's, a battle's, the Survey's) are stopped and dropped as their players leave, the textures, meshes, materials and shaders scripts keep are emptied last, and the QR reader hands its picture-reading task back. The Build editor's small map, never shown on a phone, was left in memory every time the editor closed there: fixed.
- **A stopped lookup stays stopped.** Stopping a home lookup now cancels the request in flight (nothing more is sent or paid for) and a Claude Code that was still starting; starting another lookup right away can no longer get the stopped one's answer.
- **Nothing waits for good.** Phone Link's socket thread is restarted with a growing wait and gives up, saying so, after five tries in a row instead of once a frame; it and Polox Ping take at most 64 new connections per pass; sending a file to the PC stops after a fixed number of rounds; the Doctor's downloads have an end time; a reveal, a Dream Gate animation and the test drives all stop waiting by themselves. The bundled web server takes its local port directly (no check-then-take).
- **Calls put off to the end of a frame name their node by id** (`UiKit.show_later`, `UiKit.focus_later`, the "miss you" question), so a panel freed in between is skipped instead of being an engine error.
- **For developers:** tests get their ports from the system (`free_port`, `free_udp_port`, `listen_on_free_port` in `tests/test_case.gd`) instead of a random number in a fixed range, the test run fails if any node is left in no tree, `check.bat` fails on "ObjectDB instances were leaked" or "resources still in use at exit" in the tests or the smoke run, and `tests/test_clean_exit.gd` covers the above.
- **For developers:** `check.bat` now looks for personal details and keys in every file Git sees (`tools/release/make_public_source.py --check-checkout`, plus your own words list if you keep one). Tests and notes use placeholders for phones, names and addresses; CONTRIBUTING.md lists them.

## 1.29.0 — Ready to share: a setup program, cloud sync, clearer goals (2026-11-15)

- **A setup program for Windows.** `Polox-1.29.0-Setup.exe` installs for you alone (no administrator), adds a Start menu entry and an optional desktop shortcut, and removes itself cleanly. An installed Polox keeps your worlds in `%LOCALAPPDATA%\Polox\PersonalData`, so updating, uninstalling and reinstalling leave them alone (the uninstaller asks before deleting anything). It can bring the worlds of a portable copy along. The portable zip is still there.
- **The same worlds with the PC switched off.** Settings > Cloud sync keeps a world as one file in a folder your own cloud app syncs (Google Drive, OneDrive, Dropbox, Syncthing...). Polox signs in nowhere and holds no key. Two devices that both changed a world are combined when the changes are in different places, and you are asked when they are not; nothing is overwritten silently. See `docs/SYNC.md`.
- **Coming up.** The Almanac opens with the three titles nearest to being earned, how far along each is and what moves it. A quest card names its gift before the work. A new title is announced once. All of it is optional: no timers, no streaks.
- **Info-folder home lookups and layout.** Facts show player-friendly names and units; AI-found rooms keep their own names with generic aliases preserved; hallways dress the floor instead of crowding rooms out; the player's own bedroom floor wins; and street houses match the home's storey count when map data omits height (`scripts/home/layout_builder.gd`, `home_look.gd`).
- **Accessibility audit.** Audited 23 screens for minimum 44 x 44 px click / 48 screen-pixel touch targets (`ui_kit.gd`), WCAG 2 text contrast across muted fields and translucent/Liquid Glass surfaces (`theme_builder.gd`), and `Reduce motion` behaviour (`tests/test_accessibility.gd`, 8 of 8 tests passing).
- **AI and map requests say what really happened**: a provider that refuses your network isn't called a wrong key; an account without credit isn't called a rate limit; Ollama switched off isn't called "no models"; a map server that never answers is called busy, with where to pick another. Google's newer `AQ.` keys are recognised as Gemini keys. `docs/API_VERIFICATION.md` lists what was proven with real requests and what was not.
- **Art**: signs are framed boards with writing on both sides; open ground has soft patches and tufts instead of one flat colour.
- **Public and private builds are separate by construction.** The soundtrack, the custom Mochi and the Music secret's pictures live in a private pack that a public build cannot contain (`tools/release/verify_pack.py` reads every build's contents and refuses otherwise); public builds ship Polox Originals and eight original drawings for the secret.
- For people reading the code: the GPL-2.0-or-later licence, a README, building and contributing guides, third-party notices, and `tools/release/make_public_source.py`, which makes a clean one-commit copy of the source and scans it for personal details and keys before anyone publishes it.

## 1.28.4 (BETA 1.3) — Music, touch and builder corrections (2026-11-09)

- The Music secret appears as soon as you scroll to the end of the list.
- Holding a Settings stepper on touch keeps the panel open while the value repeats.
- Renaming a room layer updates its name in the builder palette.

## 1.28.3 (BETA 1.3) — Private Hub media parity (2026-11-09)

- Windows, Android and Phone Link use the same custom Mochi and soundtrack by default.
- Polox Originals and the UTDR Theme are available as optional add-ons. Existing add-on choices stay with each device.

## 1.28.2 (BETA 1.3) — Builder and Settings maintenance (2026-11-09)

- The builder keeps its palette in place when you change tiles. Median selection time went from 29.2 ms to 10.6 ms in the maintenance benchmark.
- Swipe through Settings on a phone without changing a stepper along the way. Values use − and + controls, and scrollbars stay hidden.
- The Music secret appears after 30 uninterrupted seconds at the bottom and shows a bundled picture for five seconds before returning to the menu.
- Builder code now lives together under `scripts/builder/`. Phone Link keeps its private file handling separate from pairing rules, and battle turns have named stages.

## 1.28.1 (BETA 1.3) — Glossier, more touchable: Frutiger Aero, early iOS, iOS 7, Liquid Glass (2026-11-08)

- **Rendering fixes first.** The glass's gloss and glow were stacked flat bands (hard stripes on every button, a hard line across the title's card): now true gradients. The logo was shrunk with the pixel-art filter (stair-stepped edges): now smooth, from mipmaps; its "reflection" was the whole logo squashed into a strip (a dark smudge): now a true reflection. The Today card stayed over the builder's tools; the builder's tile-set tabs were cut off under the search field; Settings' Music labels pushed one picker out of line; the Dream Gate's jet hid part of its name; a floor lamp's shade burned out to flat white; the Light World's lawn had a hard line where the sun's shadows stopped; text panels let the title's logo ghost through.
- **Liquid Glass** (original, after iOS 26) for what floats: the world's navigation and quick actions, the phone's tab bar (now floating), the title's card, the Today card and phone sheets. It blurs and bends what's behind it, tints to keep labels readable on bright and dark rooms, and works around a Godot 4.7.2 bug (BackBufferCopy's rect is copied as screen pixels). Solid with Reduce transparency or Battery saver.
- **Frutiger Aero**: the title has glossy aqua-green hills, a rippling lake with glints and rising glass bubbles; the primary button is a glossy sea-green key; the builder's toolbars are aqua glass with the open mode lit.
- **Things you can touch** (early iOS): keys with an edge that press down (and click), switches that flip (and click), the journal as a ruled paper notebook with Write and Pages tabs (a page turns), the bag as a tray of sunken slots, Settings > Music as a small stereo with a display and chrome keys (the secret is untouched).
- **iOS 7 for dense screens**: Settings and the builder's inspector use flat rows with hairlines and switches, more room and opaque layers.
- **In the world**: warmer Light World daylight; glazed ceramic tile floors (Poly Haven's long white tiles); a wall **light switch** that flips the room's lamps (in the starter room and in Decorate); a **glass lantern** (Poly Haven's Lantern 01); the Dream Gate glazed (a clear coat and reflections on a PC at High), on a tile apron, its liquid rippling when you touch it; battle meters with depth; the builder's preview grounded with a shadow and a clear footprint frame, and selections framed boldly.
- New assets (CC0, about 4 MB, credited in docs/ASSET_CREDITS.md): Poly Haven's Long White Tiles and Lantern 01, seven sounds from Kenney's UI Audio.

## 1.28.0 (BETA 1.3) — Your data in one place, phone taps, the map (2026-11-08)

- **Your data has one home: PersonalData.** Saves, settings, AI keys, Phone Link pairing, logs, backups and your own pictures now live in a `PersonalData` folder beside Polox (beside `Polox.exe`, or the project folder when run from source), found from Polox's own location so a shortcut finds it too. Phones and the browser keep the app's private storage. The first start copies your older folders in (the `POLOX_SAVE_ROOT` folder, `.polox-local\player`, `Documents\Polox`), checking every file, and never deletes them; it doesn't run twice and never replaces newer data. **Settings > Gameplay > Open Personal Data Folder.** The folder is git-ignored and left out of every export. Godot's own log file is off on PCs (Polox's own log is in PersonalData).
- **Fixed: one phone tap typed every PIN digit twice.** Godot delivers a phone tap to a button twice (the touch and a mouse copy of it) and the keypad acts on press, so each digit was added twice (and the platform Jump fired twice). One tap is one press now; repeated digits, Backspace, paste and leading zeros all work. The same double tap is fixed where screens read taps themselves: a tap outside a phone's sheet closed the screen under it too, a wall in Map my home changed two steps, the World Map's places and the Survey reacted twice.
- **The World Map's neighbourhood map pans and zooms:** drag, the wheel, a trackpad pinch, two fingers, or − + Fit; a tap (not a drag) goes there. When your streets aren't mapped, or the saved map can't be read, it says how to fix it.
- **A missing Ollama model falls back to a small chat model** (it picked the biggest installed model, a 35B coding model, and every chat timed out).
- **The Music secret's pictures are built into the game** (all eight, in every copy, offline), and its button now appears right where you're looking: it used to appear just below the bottom of the page, out of sight.
- **Starts faster:** the world loads in the background while the title shows (from source: ~5 s to the title before, ~2.7 s now).
- **Privacy pass:** this PC's network addresses, machine and tailnet names, and user folder are gone from the code, tests and docs (neutral examples instead). Old plans, reports and verification notes moved to `docs/history/`; `docs/DIRECTORY_GUIDE.md` maps the project, and feature tags (`[PERSONAL_DATA]`, `[PAIRING]`, ...) mark every part of a feature.
- Web and Android exports leave out the PC-only Detailed pack (the web package was 372 MB, now 62 MB).

## 1.28.0 (BETA 1.3) — Glass, easier making, and PC graphics (2026-11-08)

- **A glass finish.** Buttons, tabs, the title's card and toolbars are translucent with a soft glossy sheen and a light rim; panels with text stay solid. Hover glows aqua, pressed is yolk, disabled is flat and faded. The palette, the logo and the icon are unchanged. **Settings > Accessibility > Reduce transparency** makes every surface solid. See STYLE_GUIDE.md "Glass".
- **The title screen** sits on one glass card with a glossy Continue, a faint watery reflection under the logo and a few slow bubbles on an aqua horizon (still with Reduce motion). On a phone held sideways it's two columns, so Settings and Quit are no longer cut off; on an upright phone the buttons sit low, under the thumb.
- **Settings by category:** Gameplay, Display, Audio, Music, Controls, Accessibility, AI, Light World and Phone Link, as chips that wrap on a narrow screen. No sliders: numbers have − and + (hold to repeat) and you can type a value. No scroll bar: swipe, wheel, trackpad, or Page Up/Down, Home and End; a soft fade and chevron show there's more below.
- **PC graphics:** besides Auto, High, Ultra and Off, **Fine-tune** sets lighting (Soft, or Global: light bounces off what you place, live), shadows (Ultra: the nearest lamps cast shadows too), reflections, atmosphere (light shafts), textures (up to Detailed), model detail and render resolution (previewed, and it goes back by itself unless you keep it). **Measure this scene** shows frame rate, frame time and memory. Phones and the browser keep their own settings. Results: docs/GRAPHICS.md.
- **The Detailed pack (optional, PC):** higher-resolution CC0 surfaces and furniture from Poly Haven, fetched by `tools/get_detail_pack.py` into the git-ignored `assets/detail/`, on with Textures: Detailed. Saved worlds, ids and collisions don't change. Credits and licences: docs/ASSET_CREDITS.md.
- **Drawing zoom:** every drawing page has −, the zoom, +, Fit and ✋ Pan in its corner. The wheel and a trackpad pinch zoom towards the pointer; two fingers pinch and move on a touch screen. Moving the view never draws (a stroke a second finger interrupts is taken back), and strokes land under the pointer at every zoom.
- **Building:** Place, Paint and Edit modes (each shows its own tools), ▶ Playtest with **Back to building**, Undo and Redo always in the top bar, a Saved ✓ indicator, the tool you have and its shortcut, Duplicate for a selection, and panels you can hide for more room. On a phone the world fills the screen with a toolbar under the thumb; Tools, Pieces and More open as sheets.
- **Battle Maker in sections:** Encounter, Enemies, Waves, Arena, Rules and Presentation, with a quick setup for simple battles. New: enemies one after another, wave order (in order, shuffled, or keep the last), reorder and duplicate waves and enemies, preview a phase, phase lines, hazard zones in the box (sting or slow), how you win (spare or tire, spare only, last N turns), damage and Soul speed, a reward item, backdrops, effects and an opening line. Problems are listed with links to the control that needs them, and **▶ Test** plays the whole battle and comes back to the Maker as you left it. Battles made before load and play as they always did.
- **A secret**, somewhere on the title screen.

## 1.28.0 (BETA 1.3) — Add-ons and the Dream World (2026-11-08)

- **Title > Add-ons.** See the add-ons Polox found, turn each one on or off (Polox remembers your choices across launches), open the add-ons folder and see problems with an add-on's files. An add-on is a folder with an `addon.json` file. It can change music cues, add songs, and change pictures (the Soul and the logo), sound effects, tiles and on-screen words. It can also run scripts, but only after you trust exactly that version of them. Polox reads only `addon.json` when it looks for add-ons. When a file is missing, unreadable, the wrong type or outside the add-on's folder, the add-on's card says so and Polox uses its own instead. See [docs/ADDONS.md](docs/ADDONS.md).
- **The Dark World is now the Dream World, the Dark Fountain is now the Dream Gate, and the Dream World's people are the Bramins (one Bramin).** Saves, places and chats from before the rename read with the new names on screen. Nothing saved is rewritten, and internal ids such as `dark_fountain` are unchanged, so every existing world loads as before.
- **The Dream Gate is an orange basin brimming with liquid.** The liquid looks and moves like liquid, not smoke: its surface is glossy and ripples, an open gate pushes up a glossy jet that wobbles as it flows, and drops fall from its top back into the basin. You enter and use it as before.
- **The Soul** on the title screen and in battles (the cursor you steer) is a picture now: the built-in one, an add-on's, or Polox's own Dream Drop. Its movement, its hit area and its flashing when hit are unchanged.
- **Music cues:** Title menu, Light World creation, Light World, Dream World and Battles. Each cue plays your choice in Settings > Music, an add-on's song, the built-in song or Polox's own tune. Settings > Music offers Automatic, Polox's own tune and Quiet before the songs.
- **Built in on this PC:** the soundtrack and Mochi as the Soul come from `assets/local/`, which Git ignores; exports from this PC include them. **Polox Originals**, an add-on that comes with the game, switches to Polox's own tunes and the Dream Drop Soul instead. A copy without `assets/local/` uses those originals.
- Exports leave out `local-addons/` and `assets/music/`.

## 1.27.18 (BETA 1.01) — Backups made on the phone reach the PC (2026-11-05)

- **The Backup button on a phone now sends the backup to your PC.** Phone backups stay in the app's private storage and Phone Link never syncs them, so none reached the PC. Now each one is also copied to the phone's Download/Polox folder and sent to the PC, which keeps it in Documents\Polox\phone_backups\<world>. The newest three manual backups already on the phone go the next time it connects.
- The PC checks that a backup arrived whole and really holds a Polox world.

## 1.27.17 (BETA 1.01) — Exports you can actually reach on a phone (2026-11-05)

- **Exporting a world (or a chat log) on a phone now puts the file where you can get it.** It used to land in Polox's private storage, which no file manager or PC can open. Now the app also copies it to your phone's **Download/Polox** folder (the browser version downloads it), and sends it to your paired PC, which keeps it in Polox's **exports** folder (Documents\Polox\exports). If the PC isn't in reach, it goes the next time they connect.
- Exports made on the phone before this update are copied to Download/Polox when the app starts, and sent to the PC when it connects.
- The PC checks every file it receives: it must arrive whole (checksum), a world must really be a Polox world, and only paired phones can send. Big worlds go in 4 MB pieces and carry on after a dropped connection.

## 1.27.15 — The PC helper's cancel, and a last full check of 1.27.13 and 1.27.14 (2026-11-03)

- **Cancelling a request to your PC's home helper now ends it and cleans up after itself.** The phone waited for the PC's answer on a signal that `HTTPRequest.cancel_request()` never sends, so a cancelled call stayed suspended for good and left its request node in the scene (one more with every cancel). The wait is a frame loop now, like the direct helpers': cancelling (or leaving the screen) ends the call at once as "Cancelled."; a PC that goes away mid-request ends it as offline; a second request while one is waiting is refused instead of mixed in; an answer that never arrived is no longer logged as a JSON parse error. Every way out of the call frees its request node (`helper_pc.gd`, `tests/test_helper_pc.gd`).
- High quality now picks its anti-aliasing from the device the setting is for (2x on a phone, 4x on a PC), not from the machine that happens to run the check. On real devices nothing changes.
- Checked end to end against a real local Ollama model through the real Phone Link server: the phone-side bridge got a schema-valid answer back in 19 s, with nothing paid and nothing sent off this PC.
- Development: the random-play soak (`--drive=soak`) no longer wanders into the Survey (a full-screen flow it cannot leave, which made the run look stuck) or "Forget my home", and it reports what is holding the game if a transition ever lasts more than 20 seconds.

## 1.27.14 — Clearer helper setup and a memory watchdog (2026-11-03)

- Show the selected helper and its readiness immediately in setup.
- Explain PC connection/Sync requirements and manual/offline modes.
- Disable connection-check buttons while working to prevent overlapping checks.
- **A memory watchdog on Android** (`memory_guard.gd`). 1.27.12's phone logs show the app growing to about 3.5 GB within a few minutes of starting before the allocator or Android's low-memory killer ended it. 1.27.13 fixes that cause in the engine; this guards against the same kind of runaway whatever allocates. Past 1.2 GB (or a leak's pace of 350 MB in 20 seconds once the app is over 700 MB) it lets go of its caches and stops anti-aliasing; past 1.8 GB it also halves the frame rate and drops the sun's shadow, glow and colour pass; past 2.5 GB it writes the world to disk. Each step is printed and recorded.
- The flight recorder's heartbeat and the crash reports now carry the app's whole resident memory, the graphics memory and what the watchdog did (`rss_mb`, `rss_peak_mb`, `video_mb`, `pressure`), so the next report shows how big the app was and what it did before it stopped.
- Phones and the browser start with no 3D anti-aliasing (the project default) instead of switching it off a moment after start.
- A "finger up" lost to the notification shade or another app no longer leaves the touch controls believing a finger is still down (two of those stop the stick). The title screen's stars redraw 30 times a second instead of 60.
- Blender tools: `tools/blender_scripts/audit_models.py` audits every model in headless Blender (geometry, UVs, draw surfaces, z-fighting, textures) and `repair_models.py` writes repaired copies (zero-area triangles, coplanar overlaps). No model was changed in this version: the audit found all 36 furniture models light (13,593 triangles in all) with clean UVs, and no z-fighting that shows in the game's own render.

## 1.27.13 — Mobile stability and leaving home (2026-11-03)

- Restore a missing house-to-street door when loading older homes and keep it when rebuilding or editing the house. Add a visible Go outside action.
- Phone Automatic runs at 60 fps. Balanced uses no MSAA or sun shadow pass; backgrounding also lowers the frame cap.
- Paired phones can explicitly select the PC's configured OpenAI/compatible home helper. Keys stay on the PC; changed providers are rejected and paid requests are not retried automatically.
- Helper progress/errors stay visible, missing setup is explained, and unsupported PC-helper photos are refused explicitly. Fix plain mobile grass/concrete using a floorboard texture.
- Portrait menus use one column and instructions remain expanded. Keep 1.27.12's Android audio-loop bounds fix.
- Backport Godot’s merged fix for repeated MSAA framebuffer allocation. New 1.27.12 phone logs show Adreno rendering-thread failures, native out-of-memory aborts and low-memory kills. Physical-phone confirmation remains pending.


## 1.27.12 — Polox's own engine

- **Polox runs its own build of Godot now.** The Android app, the phone (web) version and Polox.exe are
  built from Godot 4.7.2's official source (checked against Godot's SHA-512) by `tools/build_engine.py`,
  with Polox's engine fixes (`native/godot/patches`) and only the parts of the engine the game uses
  (`native/godot/polox_profile.py`). Left out: CSG, GridMap, glTF/FBX loading at run time, visual
  shaders, video, XR, navigation meshes, multiplayer, WebSocket/WebRTC/UPnP, Jolt, MSDF fonts and the
  fallback text server, and on Android the Vulkan renderer (phones draw with OpenGL). A test fails if the
  game ever names a class that was left out.
- **The phone crash is fixed inside the engine as well.** Godot's WAV mixer could read one frame past a
  loop that ends on its last frame, which killed the app on Android; the engine now keeps every loop
  inside its data (1.27.11's fix in the game stays). The phone test plays loops built exactly the way
  that crashed, and the app checks it runs Polox's engine (4.7.2.stable.polox).
- **Built with Android's own build system.** The APK is a Gradle build (Android Gradle Plugin 8.6.1,
  API 36), and Polox's Java helpers are a proper Godot Android plugin (`native/android`,
  `addons/polox_android`) instead of code patched into the APK's binary manifest by a script, which is
  gone.
- **Low memory:** Godot doesn't pass Android's memory warnings on; Polox's plugin does, and the game
  lets go of the sounds and pictures it only keeps to be quick next time (`memory_relief.gd`).
- **Phone Link no longer keeps a CPU core busy.** Windows doesn't pace a window that another one covers,
  and Godot then draws as fast as it can: the Phone Link host had used 11 hours of CPU time in 11.5 hours.
  Server windows (Phone Link, Ping) now redraw only when something on them changes, at most 30 times a
  second, and the game's own window on a PC draws at most 30 fps while another window has the focus.
- **Quieter logs:** no "resources still in use at exit" (sounds playing when the game quit were never
  freed: an engine fix), and a shader cache the driver rejects after an update is recompiled without a
  warning.
- **Smaller engines:** the phone's 52.9 MB instead of 71.1 MB, the web version's 8.7 MB to download
  instead of 10.1 MB, Polox.exe's 70 MB instead of 109 MB. The APK is bigger to download (104 MB instead
  of 74.5 MB) because the engine and the textures are now stored uncompressed: Android reads them
  straight from the APK instead of unpacking a second, 71 MB copy of the engine on the phone.

## 1.27.11 — The phone crash, and never boxed in

- **The phone crash is fixed: the game closing a few seconds after it starts.** The phone's crash reports
  carried the stack this time: Godot's audio thread read past the end of a looping sound. Godot 4.7 reads
  the frame AT a loop's end before it wraps and keeps nothing after a sound's data, and every looping sound
  Polox makes (the Light World's room tone and birds, the pillars' hum, Polox's own battle tune, the
  Survey's hum) ended its loop exactly at the end of its data, so the mixer read past the buffer. A PC never
  notices; Android puts a big buffer right against a protected page, so the game was killed the first time
  the 8-second room tone looped. Loops now repeat their first frames after their end (`Synth.looping`), and
  WAV files you add are checked the same way (`Synth.safe_wav`). The Light World crash since 1.27.3 was
  this too.
- **Furniture can't box you in any more.** The house builder could wall off a corner of a room (a desk, its
  chair and a lamp boxed you into the corner you start in). It now never places a piece that shuts any
  part of a floor off (`floor_paths.gd`); homes built before are opened when they load (the smallest piece
  in the way moves aside, or goes if it fits nowhere); you start where you can walk away from; and Edit my
  room refuses a spot that would shut part of the floor off ("That doesn't fit there."). A chair goes at its
  table or desk, or not at all.
- **Copy prompt works in the phone's browser version (Phone Link):** plain HTTP has no clipboard API, so the
  browser's own copy command does it.
- **Quieter on Android:** no "not accessible" warnings at start (the phone looked for the PC's web folder)
  and no "xr/shaders/enabled" warning.
- **Crash reports name the build that crashed.** Android keeps its record of how the app ended across
  updates, so a new version's first start reported the old version's last crash as its own. The app now
  tags that record with its version (Android's process state summary), a crash from before this install
  without a tag says "older than 1.27.11", and report times are local like the rest of the session file.
- **Filling with an almost identical color no longer freezes the game.** The paint canvas's fill compared
  colors as floats, but the picture keeps 8 bits a channel: a color stored as the same bits as the area
  (0.2015 is kept as 0.2) refilled the same pixels forever while memory climbed. Each pixel is filled once now.
  (Found checking every open-ended loop: the others all end, and every wait on a background job has a time
  limit under it.)
- Settings' slider labels are smaller on an upright phone, so they no longer run into the scroll bar.
- The phone test drive also checks the AI helper's Copy prompt and Paste reply on the phone.

## 1.27.10 — Your front door, and nine more songs

- **Your front door is set into your house's wall.** On your street (Map my home) the door into your house
  stood in the middle of the first cell of your front path, as tall as the house. It's now in the house's
  front wall, facing the street, a little taller than you and as wide as the neighbours' doors, with no
  window drawn on that bit of wall. Streets made before get it when they load (nothing to redo); moved or
  turned away from the house in Build mode, the door stands in its own cell like any other.
- **The mailbox goes beside the door, along the house's front,** whichever way the house faces (new
  streets). It went one cell east of the door, which put it inside the house or on your path when the
  house faced east or west.
- **Nine more songs** (24 in all, about 20 MB): ANOTHER HIM, Dog Balloon, Dogcheck, Dogroom, Inukuma (WIP),
  Meeting Flower Orange, Mr. Generosity, Mysterious Shrine and Waiting Room (cover), levelled to the same
  loudness and looping like the others. They're in Settings > Music.
- **The Survey plays ANOTHER HIM:** a fifth theme in Settings > Music, next to the menu, the two worlds and
  battles ("Its own hum" brings back the Survey's low hum). The world's song waits and carries on after.
- A neighbour's painted door no longer gets a ground-floor window drawn over it.
- The street capture drives take `--cam-turn=<45-degree steps>` (dev only).

## 1.27.9 — Music fixes for phones and the PC

- **Songs stream in your phone's browser** (Phone Link's web version). Godot played each one as a Web Audio
  "sample", which first decodes the whole song into memory: the game froze while it did (0.7 to 0.9 s for the
  one-minute menu theme on a phone-speed CPU, longer for longer songs) and a three-minute song took about
  66 MB. Battles' songs stream too. On Windows and Android songs already streamed.
- **Phone Link's PC window no longer uses the PC's sound** (`host.bat`, and `ping.bat`'s window, start Godot
  with no audio driver): it never plays anything, and the host had stopped on its own right after Windows
  invalidated its audio device (another program taking the device, headphones).
- **Closing the game while Settings > Music plays a song** no longer logs "Playback can only happen when a
  node is inside the scene tree": nothing starts once the music player is leaving.
- **Settings > Music on a phone or in the browser** no longer says "Your own songs go in" a folder: there
  it's inside Polox's private storage, out of reach, and Sync doesn't carry songs. The PC still shows it.
- **The Android app stopped looking for a folder it can't have** (`assets/audio/music`, which only exists
  when Polox runs from its source): every place's song lookup logged a "not accessible" warning.
- **A music volume change made while a song fades in now holds**: the end of the fade used to put the old
  volume back until the next change.
- **Two of your own files with one name** (`song.ogg` and `song.mp3`): Settings > Music now lists the one
  that plays.
- **Map my home > "Open my_home files" on a phone** says to use the PC instead of doing nothing.
- The phone test drive (`--drive=mobile_creation`) now checks the music on the phone itself: Festival in
  the Light World, Underwater Town in the Dark World, Wrong Enemy !? in a battle with the world's song
  waiting and coming back after, and Settings > Music.

## 1.27.8 — Music

- **Fifteen songs come with Polox** (`assets/music`, about 15 MB), on phones too: Abandoned Town,
  Ballchime - Mystery, Doghole, Egg Room, Festival, Field of Hopes and Dreams, Happy Town, Snowdrift,
  Strongerer Monsters, The Diner Song of Best Friends, The place where it rained, The Sunset of 7 Suns
  (Sketch), Underwater Town, Waterfall and Wrong Enemy !?. Each is levelled to the same loudness and loops
  without a gap (the silence at the end of seven of them is trimmed).
- **Four themes:** the title menu plays **Abandoned Town** (after the title's chime), the Light World
  **Festival** (its birds and room tone stay softly underneath), the Dark World **Underwater Town** and
  battles **Wrong Enemy !?**. Settings and Worlds opened from the title keep the menu theme; making a world
  keeps the Survey's own hum; Phone Link's host window stays quiet.
- **Settings > Music:** every song with a play button (it plays while Settings is open, then your music
  comes back), where it's from, how long it is and what it's the theme of, and a picker for each theme
  (Quiet for the menu and the worlds, Polox's own made-up tune for battles). Your own .ogg, .mp3 or .wav
  files in the save folder's `audio/music` join the list, and one named like a game song replaces it.
- **The world's song waits for a battle** and carries on from where it paused afterwards, and steps aside
  for a moment's motif (the first look at your home, the first street, the first trip to the Dark World,
  coming back from a battle) and for the Survey's hum when you map your home.
- **Build mode > Room:** a place plays its world's theme, a song of its own, or nothing ("Music: quiet");
  the change plays at once.
- Fix: Phone Link's banner and What's New opened Settings on the wrong tab (the Light World tab took Phone
  Link's place in 1.27.x); Settings now opens tabs by name.

## 1.27.7 — The purple title is back

- **The title menu is night violet again**, with its twinkling stars and the purple glow at the bottom
  (1.27.5 had turned it black), so the new logo sits on purple. Settings and Worlds opened from the title
  are violet too, even when you come back to the title from the Light World. Making a world (the Survey
  and the steps after it) stays black and typewritten, like the Survey; in-game menus keep their world's
  colours.

## 1.27.6 — Textured furniture, soft shading, six new pieces

- **Furniture has real surfaces now**, made in Blender (`tools/blender_scripts/texture_furniture.py`):
  wood grain that follows each board, fabric on sofas, chairs and cushions, creased bed linen, brushed metal,
  enamel, glazed ceramic, glass, screens, leaves, petals, pleated lamp shades, woven rugs with a border and a
  medallion, and a bookshelf of books in many colours. Paint still works on everything: the part you paint
  keeps its grain or weave in whatever colour you pick. On phones too.
- **Baked soft shading:** every piece carries its own ambient occlusion, baked with a floor under it, so
  cushions sink into sofas, drawers have depth and furniture sits on the floor instead of floating. It costs
  no extra lights or shadow passes. Shiny things (ceramic, enamel, metal, glass, screens) catch the light;
  fabric and wood stay soft.
- **Six pieces modelled in Blender** (`tools/blender_scripts/model_props.py`): a bean bag, a fish tank with
  three fish and a soft glow, a coat rack with a hat, a scarf and a tote, a bar stool, a wall clock that
  hangs on the wall (always ten past ten), and a proper upright piano with 88 keys in place of the old box.
  The first five are in Build mode's furniture list, and each has its own line when you use it.
- The Kenney nature bush and flowers no longer render as metal (their kit marked them fully metallic).
- **Fixes:** the story's last chapter asked for "a battle with a friend at your side", which one-on-one
  battles made impossible; it now asks for friendly battles with 3 different friends (if you already fought
  beside a friend, it stays done). The Battle Maker no longer offers "+ one friend" ACTs or magic for party
  members 2 and 3; an older battle's friend ACT says it's hidden and offers "Make it solo". The stock
  "Team greeting" ACT, hidden since 1.27.5, is a solo "Friendly bow" again, and the rehearsal's "Curtain
  call" works on your own. On a holiday or your birthday, a friend you've just made (or brought from another
  app) says their own first hello; the holiday's line waits for the next one (it used to take the first
  hello, and a card's greeting was never heard).

## 1.27.5 — Phone stability, one-on-one battles, the Survey first, a new logo

- **Your logo** on the title screen and as the start-up splash (on black).
- **A new world opens on the Survey** (the Light World creation sequence), before the world's name and
  your first friend. The title and those steps share the Survey's look: black, typewriter letters, square
  boxes. On an upright phone the friend step stacks so nothing runs off the side. A world's own menus keep
  their colours (violet in the Dark World, tea-brown at home). On Android the Survey and these screens now
  really are typewritten (Android's own monospace font; before, the phone fell back to its usual font).
- The Android export refuses to build a downloadable APK that carries a test command line, and two
  exports can no longer overlap.
- **You fight on your own.** Battles have one party member, you; practice encounters no longer add helpers
  and ACTs that need helpers are hidden. The friend you face looks the way the world shows them (their
  current form), and your own card uses your resting picture.
- **Lighter battles on phones.** The 3D world stops drawing behind the battle screen; on a phone the battle
  draws at up to 60 fps and checks bullets 120 times a second (240 on a PC). Aimed bullets find where you
  were with a binary search.
- **Phone crash mitigations for walking in the Light World** (the phone's last report: a native SIGSEGV, no
  script errors; none of these is confirmed as the cause yet):
  - Weather (rain, leaves, snow) runs on the CPU under the phone/browser renderer. It used GPU particles
    (transform feedback) and re-simulated their whole lifetime on the GPU each time a street or place loaded.
  - No automatic cover screenshots on Android (a GPU readback every two minutes and after room changes).
  - Picture effects (blinking, Dark World looks, transformations) never read a picture back from a phone's
    GPU; character-sized pictures keep their pixels on the CPU instead.
  - Scanned furniture surfaces stay off on Android, like the house walls and floors since 1.27.3.
- **The next crash says where.** On Android 12 and later the phone reads Android's crash dump itself and
  sends the crashing thread's stack and the last log lines with the crash report; an uncaught Java exception
  is saved with its stack. Phone Link keeps those lines whole.
- Indoor Light World rooms get a warmer fill light at night, without extra lights or shadow passes; floor
  cushions show a fabric texture on a PC. A Sky Moment no longer undoes the indoor fill.

## 1.27.4 — Android crash diagnostics

- Successful manual Sync retries unsent crash reports; reconnect waits for report delivery.
- Android 11+ collects recent OS termination reasons, signal/exit status and memory samples
  on next launch. Normal exits, user force-stops and app updates are excluded. Reports deduplicate
  accepted records and use the existing PC connection.
- Mobile QA now covers front-door walking, mapped street entry/return, upstairs home entry,
  fountain interaction and repeated Light/Dark transitions on BlueStacks ARM64.
- The affected phone's 1.27.3 report confirms a closure after `cross_complete` in the Light World
  without script errors. This diagnostic update does not claim that crash is fixed.

## 1.27.3 — Android house rendering follow-up

- Android uses simple house wall/floor shaders without scanned surface textures or normal maps,
  retaining the creation reveal, cutaway walls and floor patterns. This is a compatibility mitigation
  for the reported crash before the house door appears; confirmation on the affected phone is pending.
- Wall segments no longer overlap along their length, and box faces retain flat normals.
- Rebuilding a room releases old wall, glass and floor material references.
- The rendered creation check now also crosses interior doorways before repeated world changes.

## 1.27.2 — Mobile home creation and world transitions

- Paired phones can run the Light World Survey. Old placeholder rooms no longer suppress creation,
  including when resuming a save inside one. Explicitly leaving the Survey is remembered on that device.
- The home reveal is marked complete after it plays, so an interruption does not permanently skip it.
- Generated avatar transformations have a fixed image budget, skip image generation under Reduce motion,
  and use the original form pictures instead of reading animation textures back from the graphics driver.
- Idle animations and blinking no longer overwrite transformation frames; very large photos skip the
  expensive automatic eye-detection scan.
- Changing graphics quality preserves the world's active sky. Transition crash reports record the last
  completed scene phase to help diagnose native Android failures.
- Added paired-phone creation, old-save resume, large-avatar memory, and sky-preservation regression checks.

## 1.27.1 — Backup completion checks and small usability fixes

- A missing or inaccessible source folder now fails the archive operation instead of replacing an
  existing backup with an empty zip. Incomplete file reads also fail before the archive is published.
- The developer smoke check now rejects a nonzero process exit even if the success message was printed.
- Smoke checks use a fresh scratch save, and the scripted flow respects an already-answered notification
  question when deliberately rerun on an existing save.
- Roads stay inside the map paper in the street preview and World Map, instead of drawing over nearby buttons.
- Platform control hints wrap above the shard counter and below the camera controls, so they remain
  readable on portrait phones and wide screens.
- Long map names use an ellipsis instead of being cut off at the edge. Platform Run shows when it is on,
  and the phone's Leave button no longer shows a keyboard shortcut.
- Added regression coverage for preserving an existing archive when the source is missing, and for
  excluding an archive's own output when saving inside its source folder.

## 1.27.0 — A phone game that feels good; real furniture and surfaces; more AIs; friends that remember

### Fixed
- **No more 30 fps on phones.** "Performance mode" switched itself on for every phone and capped the game at
  30 fps with no shadows. It is replaced by two plain choices in Comfort & sound: *Frame rate* (match the
  screen, or 120, 60, 30) and *Graphics* (Auto, High, Balanced, Battery saver). Phones run uncapped and Polox
  asks Android for the screen's full refresh rate (Android 15 and later otherwise hold games at 60 Hz).
- **Lighter scenes.** Round things (fountain drops, lamps, plants) used Godot's default 64-segment spheres:
  the Dark home was 378,000 triangles, now about 6,300. Fountain particles no longer cast shadows. Furniture
  is now one mesh per piece: a third to a half fewer draw calls in a furnished home or a street.
- **Stalls cut.** Walking through a door zipped the whole world on the main thread (a quarter second on a
  fast PC); that snapshot now runs in the background. Entering Build re-read about 500 tile pictures every
  time; it now keeps them and fills the palette over a few frames (230 ms to 65 ms after the first time).
- **Memory leaks:** blinking and Dark World looks no longer leave pictures behind; a leak drive checks
  repeated play, Build, photos, talks and travel.
- **The title heart** is drawn as a shape (it was a font glyph that broke on some phones); tab icons too.
- **AI errors:** each provider keeps its own key (one shared key was sent to the wrong service); Ollama uses
  its own API with the models you have installed (a missing model switches to an installed one and says so);
  "max tokens" and temperature refusals retry the right way; every helper error is explained in plain words
  without showing the provider's raw text. A phone talking through its PC now waits for the PC's answer
  instead of giving up after 4 seconds.

### Added
- **Real furniture:** 30 catalogue pieces (beds, desks, the computer desk, sofas, armchairs, the TV, the
  kitchen and bathroom, lamps, plants, rugs, stairs, bushes, flowers) are Kenney's CC0 models, made ready in
  Blender: joined into one mesh, in metres, fitted to their footprints. Paint tints the fabric or wood and
  keeps metal and glass; a painted lamp shade still glows.
- **Real surfaces in the Light World:** wood, tile, carpet and concrete floors, plaster walls, painted brick
  and clay-tile roofs on the street's houses, grass lawns, asphalt roads and paved paths, from Poly Haven's
  CC0 scans, always in your home's own colours. On a PC at High, streets reflect a real sky.
- **Finer Dark World surfaces:** plain floors read as boards, walls as plaster, blocks as blocks (in their
  own colours, crisp like the sprites), with soft shade where floor meets wall and a skirting board.
- **Glow** on lamps, magic and the fountain (High; Balanced on a PC) and a touch more colour.
- **Pixel emote balloons** (Kenney's Emotes) over friends: hearts, music, sparkles, sleep, stars, ?, !, ~.
- **Tiny Town**, a fourteenth starter tile set cut from Kenney's CC0 pixel sheet (24 tiles).
- **Touch controls:** a floating thumb stick to walk and a Talk/Use button for whoever is nearest.
- **Venice.ai** as an AI provider, and **custom Ollama models** (pick from the installed list, or per friend:
  *Their AI model*).
- **Friends from Character.AI and Chai:** neither has an API Polox could call, so you bring the character
  over: a character card (.json, or .png from SillyTavern, chub or a Character.AI export tool) or pasted text.
- **Chat memory:** friends recall earlier moments that fit what you say; chats are backed up daily (zip, ten
  kept) and can be backed up or restored by hand in Friends.
- **Missing-you notes:** away for 1, 3 or 7 days, a friend sends a gentle note (Android notification or
  Windows toast; asked once after your first chat; a switch and *Send a test* in Comfort & sound).
- **Your app icon** on Windows, Android (adaptive, with a monochrome layer) and the web app.

### Tests
- New: `test_update10_assets` (5), `test_ai_providers`, `test_helper_errors`, `test_friends_memory`,
  `test_miss_you`; more in `test_phone_ux` and `test_stability`. `test_tilesets` now expects fourteen starter
  sets. Android version code 12700.
- Credits and provenance: `assets/kenney/README.md` + `manifest.json`, `assets/materials/README.md` +
  `manifest.json`, `assets/sky/manifest.json`; the Blender scripts are in `tools/blender_scripts/`.

## 1.26.1 — Final AI reply import fixes

- Repair trailing commas and smart quote delimiters without changing punctuation inside quoted text.
- Malformed research facts now reach validation and are rejected instead of interrupting the paste flow.
- Added regression coverage for both cases; Android version code is 12601.

## 1.26.0 — Mapping with any AI, for real; more to build with

### Fixed
- **Copy prompt / paste reply now works with ordinary AI chats.** A chat reply puts its JSON in a code block
  between sentences, writes some numbers as text, capitalises an option, adds a field of its own or a person's
  name, leaves a trailing comma or skips the outer envelope; any of that was refused outright. Polox now tidies
  such a reply, lists what it changed (never repeating the reply's words), leaves unknown fields out unread,
  and the result still goes through the same strict check. You tap *Use it*.
- **Coming back later works.** Opening My home re-saved your home with a new time, which made every waiting
  prompt "stale": make a prompt, close the screen, come back with the AI's answer, refused. The home's
  fingerprint now ignores the save time and the one-time first-look and first-street marks, and My home saves
  only when something changed. A house lookup made for a prompt that really is stale can be used with a fresh
  prompt (*Use with a fresh prompt*).
- **A clearer prompt:** one answer shape (the old prompt showed two), the fields in plain words, an empty
  example to fill in and the exact schema for reference; it asks for web search and never to guess a fact.
- Tell Polox no longer sends a prompt about nothing: it asks you to write what changed first.
- Ticked boxes no longer turn their row yellow and hide the tick (review lists, Settings).
- On phones and in the browser, bright Dark World colours washed out to white (a pink floor showed white): the
  light there is gentler, as the Light World's already was.

### Added
- **Map server** in Settings > Light World > Helper setup: OpenStreetMap's main server or OpenStreetMap France's.
  Only the one you choose gets your coordinates; a busy server's message points to the choice. After you keep a
  house lookup in My home, *Map my streets* is offered right there.
- **Seven tile sets** (an everyday home, town streets, a snowy village, a farm, a crystal cave, an old library,
  candy land: 58 tiles, three animated) and **eight templates** (kitchen, bathroom, town street, snowy village,
  farm, crystal cave, old library, candy land), drafted for Update 8 and ported now.
- Platform Mode shows one line of controls under the physics profile's name (ported from the movement branch).
- Developer drives: `tpl_<template>` and the `paste_*` copy/paste round trip (public buildings only).

### Tests
- `test_copy_paste_mapping` (8, new) and `test_more_to_create` (2, new). Two Update 9 helper tests now type words
  before opening the copy/paste screen, and use a real house change (a renamed room) for "an answer for an older
  home is refused"; two tile-set counts follow the new content.

## 1.25.0 — Update 9: a detailed Light World, better movement, party battles

Full account, root causes and verification: `UPDATE_9_REPORT.md`.

### Light World
- The OpenStreetMap pipeline has distinct states (consent, locating, ambiguous, requesting, validating,
  ready, sparse, offline, cancelled, failed), location candidates, bounded and throttled requests, strict
  validation (an HTML or malformed HTTP-200 body never replaces a good map), a last-good cache with explicit
  Refresh, and redacted diagnostics. A failed, sparse or cancelled lookup leaves the old streets and your own
  pieces exactly as they were; applying goes through a preview and a snapshot.
- Streets have sidewalks and curbs, gardens, driveways and front paths, hedges or fences with gates, lamps,
  zebra crossings, bus stops, pitched roofs on houses (flat on large or L-shaped buildings), windows, doors
  and shop fronts, built as one batched mesh per block. Every block records what came from the map and what
  Polox filled in; **My home > Sources > Map and references** opens OpenStreetMap, Google Maps and Street View
  at the home's coordinates only, lists nearby public places, and lets you correct the guesses.
- Interiors draw room floors in their material, walls get skirting boards, and furniture is placed by what it
  goes with; each room records whether it came from your answers, the records or a guess. A hallway plant can
  no longer cut off rooms (present since 1.24.0).
- The World Map's Light World layer is a fitted hand-drawn sheet: grained paper, washes, pencil outlines, and
  place names that stay on the paper on a phone.
- Survey Back on every step restores earlier inputs; a private draft resumes; editing answers never re-runs a
  lookup or overwrites the home by itself. Light and Dark outfits are worn in their own world.

### Saves and helpers
- Byte replacement with `.bak` recovery, one-transaction home changes with a journal recovered after a crash,
  validated and staged backup restores that roll back and leave a recovery record on failure, and
  compare-and-swap sync. A stale editor can no longer resurrect a deleted file.
- One helper selector (Claude Code, Anthropic API, Gemini, OpenAI, an OpenAI-compatible endpoint, local Codex
  CLI, Copy prompt / Paste reply), one closed JSON schema for every route, an exact payload review before
  sending, a per-change review, a snapshot and Undo. Late or duplicate replies cannot apply twice.

### Movement and battles
- Exploration: continuous camera-relative steering with acceleration, braking, wall sliding and footprint
  clearance; click paths use clear straight segments and exact destinations.
- Platform Mode profiles: Polox (default), Classic Momentum and Adventure Momentum (independently written
  presets, not ports). Triggers are swept along each tick's path, jump height is exact at any frame rate, and
  the Movement Lab template has seven linked courses.
- Party battles: up to three members with FIGHT timing bars, ACT (incl. cooperative), MAGIC with TP, ITEM with
  reservation, SPARE/pacify, DEFEND; joint enemy turns telegraphed from their real origins; knocked-down
  friends get back up. Three demonstration encounters.

### Assets
- Selected CC0 Kenney models and footstep sounds, with a manifest of sources, versions, hashes and changes.

## 1.24.0 — Phase 39: home on both devices, a clearer phone, more to create

- Paired phones receive the house and streets; private Survey answers, memories, address and journal
  stay local. A shared base plan keeps phone furniture edits from rebuilding a different house.
- Missing home room references recover at home; missing generated floors rebuild from the saved plan.
- JSON sync merges independent fields, keeps ordered coordinates intact, preserves conflicting originals,
  checks the merged checksum and reloads both running games. Homes are backed up before remote changes.
- Re-pairing identifies the same phone and avoids duplicate device entries.
- A queued push survives a busy sync. Old phone placeholder rooms give way to the mapped home.
- Settings no longer waits for Tailscale discovery; Reduce motion avoids an empty fountain animation.
- Phone controls retain 48 screen pixels after scaling; tighter sheet/menu spacing, furniture categories,
  optional paint controls, wrapping edit tools and a portrait template gallery.
- Two tile sets (16 tiles), four templates, and four Light World furniture models. See docs/history/UPDATE_8_REPORT.md.
- Regression coverage: `test_phone_pc_agree`, `test_creative_pack` and the compact phone editor checks.
- Android and Windows carry matching source build IDs; Android's batch export verifies its hash without
  depending on the availability of PowerShell's `Get-FileHash` command.
- A refused external Claude Code API key is distinguished from an expired account sign-in and can hand
  over to another helper. The credential itself must be fixed outside Polox.

## 1.23.0 — Phase 38: no more random crashes on the phone

### Fixed
- **The phone ran out of video memory.** Every place you entered, every reload and every 20 seconds outdoors
  made a new sky, and the phone's renderer (OpenGL, also the browser version's) never gave its memory back:
  about a third of a megabyte each time, until Android ended the app. Polox now keeps one sky and repaints it.
- **A phone and a PC reloaded each other every half minute** while both were open: a reload rewrote every
  friend (their mood clock, where they stood), which the next sync sent straight back. A reload now writes
  nothing, and happens only when something on screen changed (not for a cover picture, playtime or a chat log).
- **Reloads wait while you're busy:** never mid-conversation, mid-battle, mid-crossing, while building or in a
  moment.
- **No more zipping the whole world** each time the app lost focus (the notification shade, the keyboard, a
  call): going to the background takes a snapshot at most every five minutes; closing still always does.
- **Freezes:** closing Settings while its Phone Link checks ran froze the game for up to ten seconds (it waited
  for the firewall check); opening Settings > Light World took a second and a half (starting Claude Code).
  Both happen in the background now.
- A battle whose screen went away without an end left the HUD hidden; the picture cache has a limit (96).
- Coming back online, the app could skip its sync (one had just failed while the PC was away) and stay "offline".

### Added
- **The flight recorder:** if Polox ever closes by itself, the next start knows, with the last errors and where
  you were; the phone app sends that report to your PC (Documents\Polox\phone_reports) when it connects. No
  chats, keys or home details in it.
- `--drive=soak` (for development): plays at random for a while and reports errors, memory, nodes and freezes.

### Tests
- `test_stability` (9, new): reloads write nothing back and wait while you're busy, only what shows makes a
  reload, no zip on focus loss, the flight recorder, one sky reused, screens never wait for their checks, a
  battle screen gone without an end, the picture cache limit.

## 1.22.0 — Phase 37: the Light World's helper works

### Fixed
- **The lookup could never reach Claude Code.** Windows dropped every quote mark from what Polox handed it, so
  Claude Code refused the answer format ("--json-schema is not valid JSON") before it looked at anything, and
  Polox said "Claude Code didn't answer". Everything now arrives exactly as written (and an empty tool list too,
  which Tell Polox's reading needs).
- Gemini's thinking no longer spoils reading its answer; a last line without a newline is still read.
- The Story screen says "never a deadline" again when no requests are open.

### Added
- **Claude Code's sign-in, checked first.** The Survey and Settings > Light World say whether Claude Code is signed
  in; **Sign in to Claude** opens Claude Code's own sign-in (your browser) and Polox notices when you're done.
- **The next helper steps in** when one can't answer for a reason another wouldn't share (not signed in, no key, a
  plan's limit, no connection), with a line saying so; your answers build the house only when none can.
- An older Claude Code that doesn't know the newest Opus by name is asked again with its alias.

### Tests
- `test_helper` (8, new), with a stand-in Claude Code (`tests/fixtures/fake_claude`): an address full of quotes,
  backslashes and a tab reaches it exactly; the signed-out check and the hand-over; the alias; the empty tool list;
  the sign-in window; the Survey and Settings; Gemini's thinking left out.

## 1.21.0 — Phase 36: less "made by a machine", more soul

### Changed
- **One look, written down** (`STYLE_GUIDE.md`): the panels follow the world you're in (violet in the Dark World,
  tea-brown in your home, ink in the Deep); every widget has the game's own look; one set of text sizes.
- **Half the words** on the main screens; explanations became short lines, and the screens show the rest.
- **A shorter menu** (22 buttons); makers, logs and help are under More. Settings > AI keeps the server, model and
  limits under Advanced.
- The Google Maps key field is gone (nothing used it); My home > Sources has a Street View link instead.

### Added
- **Friends sound like themselves** offline: five voices (gentle, bubbly, calm, grumpy, travellers').
- **Sound:** a soft click under buttons (Settings > Comfort & sound > Button clicks), footsteps in the Dark World,
  and four short motifs (the title, home, the Dark World, battles).
- **Moments:** the first walk down your street, the first trip through the fountain, coming home after a battle,
  and a title and music for the first look at your home.

### Tests
- `test_soul` (8, new): palettes per world, themed widgets, the type scale, the word count, the voices, the sound
  palette, the shorter menu and Advanced, the moments.

## 1.20.0 — Phase 35: more animation, everywhere

### Added
- **Things move:** pieces pop in where you put them, buttons press in, screens slide up and lists arrive one by
  one, toasts glide, something you pick up flies to your bag, doors swing as you go through.
- **The light fades** from one time of day to the next, and rain drifts in.
- **Your street has a little life:** a passing car now and then, birds overhead; curtains sway at your windows.
- **Friends blink** (using their own picture's eyes), turn to look at you when you're near, hop when they're happy
  and jump when they're surprised.
- **The first look at your real home draws itself in**, room by room, out from your room (a tap skips it).

### Changed
- Reduce motion now turns all of this into quick fades or nothing (daylight changes at once).

### Tests
- `test_animation` (8, new): the motions and their Reduce motion versions, interrupting, pops for new pieces only,
  flying to the bag, door swings, the fading light, weather, street life, curtains, blinking, friends looking at you,
  the hop and the jump, the first look at your home, and a cost budget.

## 1.19.0 — Phase 34: a phone UI made for phones

### Changed
- **A bottom tab bar on phones:** World, Bag, Build, Friends, Menu, where your thumb is, above the gesture bar. The
  World tab has the World Map, things to do at home, a photo and the camera.
- **Screens are bottom sheets on an upright phone:** they rise from the bottom; swipe them down, tap above them or
  Close. Short questions are short sheets.
- Quiet explanations are one line on a phone; a tap shows the rest.

### Added
- **A small buzz** on taps, placing and confirming (Settings > Comfort & sound > Vibration).
- **Pull down from the top to sync** in the phone app and the browser version.
- **The home sketch by touch:** pinch to zoom, two fingers to pan, a long press on a room for its options (including
  swapping two rooms).

### Fixed
- The Today card fits a narrow screen; placing something buzzed twice; a transformation could trip over a player that
  a room change had already replaced.

### Tests
- `test_phone_ui` (8, new): the tab bar, bottom sheets and swiping, the buzz, pull to sync, the sketch by touch, every
  main screen at 412x892 and 360x780 with nothing to slide sideways, the main loops by touch alone, one-line
  explanations.

## 1.18.0 — Phase 33: living in the Light World

### Added
- **Edit my room:** in your real home the Build button opens it (one tap; Done closes it). Put in, move, turn,
  recolour and take away real-life furniture and decor, hang pictures, paint the room you're standing in. Outside,
  only small things: a bench, flowers, a mailbox. Everything you change at home is kept as your own edit (Undo puts it
  back, and Map my home again keeps it).
- **Things to do** (tap yourself): water the plant, sit at your desk, rest a while, open or close the curtains, look
  out of the window, write in your journal, walk to the park. No streaks, no timers.
- **Your journal**, private, on this computer only.
- **The house remembers:** "This used to be the playroom." when you walk in (once a day).
- **Footsteps** that sound like the floor: wood, tiles, carpet, grass, the pavement.

### Changed
- The Light World never has Dark World things: no blocks or terrain, Platform Mode pieces, battle spots, Dream Doors
  or battles.

### Tests
- `test_light_living` (6, new): Edit my room (limited, kept, undone, surviving a re-map), outside only small things,
  nothing Dark World-only at home, daily life and the private journal, "used to be" once a day, footsteps by floor.

## 1.17.0 — Phase 32: your neighbourhood

### Added
- **Your streets, from OpenStreetMap.** After LOOK IT UP (the last Survey screen now says exactly what goes to
  OpenStreetMap), the roads, paths, building outlines, parks, water, trees and named public places within the
  distance you chose become walkable Light World places joined at their edges, kept on your PC and offline after.
  Your front door opens onto your street (with a mailbox), your ground floor's gate leads out, and each block is
  named after its main street. You can paste coordinates from a map app instead of an address.
- **Neighbours stay private:** other homes are plain, nicely made shapes from their outlines; names, house numbers
  and everything else about them are dropped. Public places (the park, the school, the corner shop) get a sign with
  what's public about them.
- **The World Map** shows your streets as a soft hand-drawn map (tap a spot to go there), with
  "© OpenStreetMap contributors".
- **Map my streets** in My home, if you skipped it or want it again (it asks first).

### Fixed
- The World Map's layer tabs wrap on a phone instead of sliding sideways; the longer consent text scrolls.

### Tests
- `test_neighbourhood` (7, new): a made-up town's extract (in the repository) becomes joined places with its
  streets, buildings, park, pond and signs and no neighbour's details; the walk from your door to the park; your
  gate, your door and the join between blocks in the game; the hand-drawn map with the credit; nothing sent before
  LOOK IT UP; coordinates and the Overpass question.

## 1.16.0 — Phase 31: your home keeps growing

### Added
- **Tell Polox about home** (Menu, My home, Settings > Light World): write something about your home in your own
  words, or add a photo. Polox shows what it would change ("Change: My room's walls to green. Add: 3 picture
  frames in Hallway.") and changes nothing until you choose **Keep**; **Adjust** lets you rewrite it, **Undo** puts
  the house back exactly. It reads offline; **Ask Claude to read it** (only when you tap it) sends what you wrote
  and the photo, never your address. Anything it can't place comes back as a question.
- **Things Polox isn't sure about** (My home > Not sure): questions from the research and from the house itself.
  Answer any (the house changes right away), skip any. No counts, no badges, and no reminders unless you turn them
  on in Settings > Light World (once a day at most, when you arrive home).
- **The home's timeline** has Undo beside every change you made: it's taken out and the house rebuilt as if it
  never happened. Your own changes always win over research, and Map my home again keeps them.
- **Look again** (My home): after asking first, the lookup runs again and only what's new is shown (a new
  permit, a new listing, a changed fact, a new place nearby) for you to keep or leave.
- Picture frames and mirrors; a small flourish when your home changes in front of you.

### Tests
- `test_home_grows` (10, new): reading your words offline; Keep, Undo, and your earlier edits kept (also through
  Map my home again); undoing an older change; open questions changing the house and never asking unprompted;
  Look again showing only the difference; a helper's reading kept to your rooms and Polox's pieces, never the
  address; reminders only when on; pictures and house notes.

## 1.15.0 — Phase 30: the Survey, and Map my home

### Added
- **The Survey.** The first time you go home, the screen goes black and a quiet voice asks about your home:
  where it is, what kind of home, floors, rooms, your room (walls, floor, bed, desk, the view), the kitchen and
  living room floors (pictures to pick from), how old it is, what's changed, what rooms used to be, a memory to
  keep, how far your world should go and the places that matter. Typed text, a low hum, a heart for a cursor;
  SKIP passes any question, LEAVE ends it. Polox's own words and sounds (inspired by DELTARUNE's opening, nothing
  copied).
- **"Look it up?"** The last screen says exactly what would be sent (the address and what you said about the
  building, never your memories) and to whom, and nothing leaves your PC unless you choose LOOK IT UP.
- **Map my home, like a detective.** With your OK, Claude (through Claude Code on this PC with your own sign-in,
  or with an API key) or Gemini works through the public record: the county assessor's record and building
  sketch, building permits, the parcel map, current, past and archived listings, historic maps. Every fact keeps
  its source and how sure it is; disagreements are shown; guesses are marked; names of people, emails and phone
  numbers are never kept; things behind a login are listed for you to save yourself (into my_homeiles).
  Without a helper, your answers alone build the house.
- **Your house in the Light World:** one place per floor with its rooms, real-life furniture, thin walls painted
  per room, doors, windows, stairs between floors, a lawn around it, and the Dark Fountain in your room. Walls
  between you and the camera drop low so you always see where you are. While the helper works, the house draws
  itself in on the black screen.
- **My home** (Menu, and Settings > Light World): the sketch of each floor beside where every fact came from,
  the conflicts and guesses, the home's timeline, what Polox isn't sure about, and what to save by hand. Tap a room
  to rename it, paint it, change its floor; drag a room onto another to swap them; turn walls into doors or
  windows; Undo puts any change back exactly. Map my home again keeps your changes; Forget my home deletes it all.
- **The Memory Book** shows "Your home's story" (built, permits, what rooms used to be, your memories) from
  my_home, without copying it into a world.
- **Settings > Light World:** who looks things up, an optional Claude API key and model, an optional Google
  Maps key (references only).

### Tests
- `test_map_my_home` (14, new): the questionnaire alone makes a correct layout (every cell in one room, every
  room reachable through doors, stairs lined up, a front door, your room where you said with your colours, no
  furniture in a doorway, the same answers making the same house); an apartment and an empty survey still make
  homes; a recorded answer (a made-up house) becomes a layout with sources, conflicts and a history timeline,
  with no names, emails or phone numbers kept; scrubbing text; the house as places you can walk through (walls
  stop you, doors don't); no helper, still a house; nothing sent before LOOK IT UP (and going back sends
  nothing); LEAVE keeps nothing; no key or address in any file outside settings.json and my_home; helpers found
  without calling anything; the first trip home starts the Survey; the Memory Book's home story isn't copied;
  editing and three undos back to exactly the same house; Claude Code's stream read (progress, the answer) and an
  expired sign-in said plainly.

## 1.14.0 — Phase 29: the worlds swap places

### Changed
- **Everything Polox had is the Dark World now:** your places, Lancer and your other friends, Build mode, Platform
  Mode, battles and fountains. Nothing moved and nothing was removed (world v8, after a snapshot: Worlds >
  Restore); only the labels and the way between the worlds changed.
- **The Light World is your real home.** A golden fountain in your start place, **the way home**, leads up into
  it: the rise into the light, and you're Real Me in your room. The Dark Fountain in your room leads back down,
  to wherever you left the Dark World, as Dark World Me. Both journeys can be skipped with a tap, and Reduce
  motion makes them a short fade. Until Polox knows your home (Phase 30's survey), your room is a plain,
  comfortable one.
- **The Light World looks and sounds like itself:** true daylight by your clock (warm whites, honest blue
  evenings, no violet), real-life colours and sizes (a cell is a metre), no music, its own quiet sounds (a room's
  hush, birds outside by day, crickets at night), no glowing outlines, no void skies, no holiday decorations
  you didn't put there, and no battles.
- **What used to be called "Dark Worlds" (the strange copies a fountain makes of a place) is the Deep**, inside
  the Dark World: "Make the Deep version of this place", "Enter the Deep", fountains back name the place they
  lead to. Battles still walk up in the Deep by default (Settings: "Also in everyday Dark World places").
- **The World Map** has four layers: ☀ Light World, 🌙 Dark World, 🌀 The Deep and the Archive. Going to a place
  in the other world from the map is the real journey through the fountain.

### Added
- **Real-life furniture:** beds, desks, sofas, a kitchen, a bathroom, lamps, plants, rugs, stairs, and outdoor
  benches, flowers, mailboxes, trees and cars (35 pieces, drawn in code, real sizes).
- **Your home is private:** Light World places live in `Documents\Polox\my_home\`, outside every world, so
  they're never in a world's snapshots, exports, templates, phone sync or the chat AI's context. Every world
  on this PC shares the one real home.

### Tests
- `test_light_world` (7, new): every place knows its world; an old world upgrades after a snapshot with nothing
  else changed (only the realm labels, the way home near where you start, and "Back to <place>" on Deep
  fountains); your home lives outside the world (not in its places, phone sync or snapshots); the journey both
  ways with the mouse (Real Me at home beside the fountain, true daylight, no music, its own sounds, the sun by
  the name, no battles; Dark World Me back down beside the way home; the Almanac counts trips home); skipping and
  Reduce motion; the World Map's layers and Go there across the worlds; daylight and sounds differ by world.
- `test_dark_worlds`: the Deep's new wording.

## 1.13.3 — the PIN on your phone, and places that aren't boxes

### Fixed
- **Pairing Polox for Android:** your phone's logs showed it reaching the PC (the connection test passed) but no
  PIN ever arrived. On a phone that isn't paired, Settings now has **Connect to your PC (PIN or QR code)** (the
  button used to say "Pair again"), and **Look for my PC** leads to the PIN instead of quietly trying to sync
  without a key; the title screen offers **Connect to your PC** too. One PC found goes straight to its PIN.
- **The keypad on a real touch screen:** keys count the moment your finger lands, and lists that scroll ignore a
  finger that wobbles a few pixels (Godot's default turned the smallest slide into a scroll and swallowed the
  tap). The PIN can also be typed with the phone's own number keyboard (the field under the keypad).
- **Places no longer look like boxes in a void.** The 1.9.0 upgrade had kept every old room exactly as it was. Now
  (world v7, after a snapshot) outdoor places are outdoors: the Garden and the Tile Playground lose their walls,
  get the sky, the ground and hills, and are joined edge to edge so you can walk from one into the other. Indoor
  places keep their walls but stand on grass under the sky. Places you changed in Build mode stay as they were.
  New worlds start this way, and new indoor places too.

### Tests
- `test_places` (+2, now 11): rooms from before open up (outdoorsy names outdoors, Home in the world, the starter
  pair joined) while places changed by hand stay; new worlds start as one world.
- `test_android_app` (+1, now 16): one PC goes straight to its PIN; a wobbly tap still types; the keyboard field
  pairs with only the digits; Settings on an unpaired phone offers Connect to your PC and never syncs without a
  key; the title screen offers it too.

## 1.13.2 — Polox.exe

### Added
- **`build\windows\` is Polox for Windows in one folder:** `Polox.exe` (the whole game in one file, Polox's icon
  and version; no engine to install), with the phone version (`web\`) and Polox for Android (`polox.apk`) beside
  it so Phone Link works from there too. Copy the folder anywhere. `tools\export_windows.bat` rebuilds it
  (`tools\get_windows_templates.bat` first, once: Godot's official templates, SHA-512 checked, only the Windows
  one kept).
- Polox.exe carries the build id of the source it was made from, so Phone Link doesn't call its phone version
  out of date.

### Tests
- `test_android_app` (+1, now 15): the build id written for an export is the source's own and reads back exactly;
  an APK beside Polox.exe is found with its details.

## 1.13.1 — your answers after 1.13.0

### Changed
- **The gift limit is back:** up to three gifts per friend a day (the 2nd and 3rd bring half the closeness); a
  fourth is kindly put off until tomorrow, as before 1.13.0.
- **Happiness drains while you're away again:** a friend's happiness drifts down to calm (65%) while you're gone,
  as before 1.13.0. Friendship, your bag, quests and requests still never fade or expire.

### Tests
- `test_life`: the old gift-limit and happiness-drift checks are back; `test_reasons`: a month away brings
  happiness down to calm and no lower, and nothing else changes.

## 1.13.0 — Phase 28: reasons to come back (without guilt)

### Added
- **Menu > Story:** eight chapters that open as your world grows (a place of your own, beyond the edge, the
  fountain, a friendly fight, mercy, makers, light returns, together), each a short scene and a few things to do in
  any order; finishing one gives a title to wear. Nothing is tied to the clock and nothing expires.
- **Friend requests:** now and then a friend asks for something small (see what's past an edge, peek into a Dark
  World, a spar...). At most two at a time, no deadline, "Let it go" any time; doing one brings a thank-you, a Memory
  Book page and a little closeness.
- **Dark Crystals:** the first visit to a Dark World place hides three to find. **Discoveries:** the first visit to
  each place. Both in the Almanac (with new titles) and Story > Collection. **Battle Log:** Story > Battle Log.
- **"Since you were last here":** the "Where was I?" card now mentions the chapter that's waiting, a request if
  there is one, and that nothing was missed while you were away.

### Changed
- Being away never drains a friend's happiness anymore (it only settles up towards calm); friendship never fades.
- Battle Log lines are worded kindly ("you spared each other", "knocked down, got right back up").
- **Nobody is missed:** a visitor you didn't invite still wanders on the next day, but who they were is kept;
  Story > Collection > **Invite back** brings them home to stay, any time.
- **Battles and Reduce motion:** with Reduce motion on, the battle intro is a short fade, the screen never shakes,
  enemies stay still and effects are short fades (a tap still skips the intro either way).
- **No daily gift cap:** a friend never turns a gift away with "save the next one for tomorrow"; after the first
  gift of the day, each one brings half as much closeness as the one before.

### Fixed (developer tools)
- Screenshots taken with `--shot` sometimes saved an old frame (the world without its UI) when the capture window
  wasn't being drawn; a fresh frame is now drawn right before the capture.

### Tests
- `test_reasons` (8): chapters open by playing and a month of time alone changes nothing; a month away costs nothing
  (friendship, happiness, your bag, quests); no streaks, login rewards, timers, decay, energy gates, loss aversion or
  FOMO in any script; the "Since you were last here" lines; friend requests (two at most, still there a month later,
  a thank-you with a Memory Book page and closeness, Let it go costing nothing); discoveries and Dark Crystals in
  play (one discovery per new place, three crystals on the first Dark World visit, each counted once); the Story
  panel by clicks alone (every tab, Let it go); a traveler who wandered on, invited back a month later.
- `test_battles` (+1, now 11): a tap skips the intro; Reduce motion makes it short, effects short fades and a real
  hit doesn't shake the screen.

## 1.12.0 — Phase 27: the Battle Maker

### Added
- **Menu > Battle Maker** (and New... before a battle): who you face (a friend, Gentle / Normal / Tough), their turns
  from 17 pattern templates, **Draw a bullet** (the pixel canvas; its exact shape is its hitbox), a live preview you
  can pause and scrub (the same moment always shows the same bullets), **Save** and **Save and fight**. Advanced (one
  click): every spawner (straight, aimed, arc, wave, spiral, orbit, bounce, or traced along a line you draw on the
  preview; where from, how often, how many, speed, spread, angle, turn, wave size, orbit radius, size, start and
  stop, the seed), each turn's length and box size, the enemy's ACTs and lines. Saved battles live in the world.

### Tests
- `test_battle_maker` (4): Simple by default, adding a pattern, the preview scrubbed back to the same bullets, saving;
  Advanced with every control, a traced path drawn with the pointer that bullets follow, a drawn bullet hitting only
  where it's drawn; Save and fight starting the battle; New... before a battle opening the maker.

### Changed
- On a phone held upright the Battle Maker stacks: the preview on top, the controls scrolling under it.

## 1.11.0 — Phase 26: battles

### Added
- **Friendly battles, DELTARUNE-style, in Polox's own look.** Your party (you and up to two friends) faces a friend:
  **FIGHT** (a timing bar: tap when the line is in the middle), **ACT** (Compliment, Joke, Talk about what they like,
  Hum together... fills their mercy), **ITEM** (any Consumable in your bag heals; battles never use one up),
  **SPARE** (when their mercy is full or they're tired out) and **DEFEND** (half damage, TP; Rally heals everyone for
  TP; Run away is here too). On their turn your heart dodges inside the box: it follows the mouse or your finger
  (at a capped speed) or the keys; brushing past bullets (grazing) fills TP. Outcomes are always kind: they're tired
  out, you spare each other, you run off, or you're knocked down and get back up ("Try again"); nothing is lost.
- **Starting one:** a friend may walk up in a Dark World with a reason from your chats (rare; Accept or Not now),
  say "I want to fight" in a chat, Menu > **Battle**, or a **Battle Spot** (a new piece). Then a template (6), a
  battle you saved, or a new one, and who fights beside you.
- Every battle is written to the world's **Battle Log** (to read in Menu > Story from 1.13.0), a Memory Book page
  when you spare a friend, a little closeness.
- **Settings > Comfort > Battles:** how often friends ask (Off / Rare / Sometimes), the Light World too, Story mode,
  slower bullets, wider timing, bigger graze, choose for your friends.
- **Your own HUD pictures:** drop fight/act/item/spare/defend/heart/box/tp/background .png into
  `Documents\Polox\skins\battle_hud\`; they're used on this PC only (never synced, exported or committed).
- Enemies bob, flinch and sparkle; slashes, numbers, graze sparks, spare sparkles, the encounter flash and the
  knocked-down recovery are all animated; battle music is made in code. The Animations tab has Battle idle / hurt.

### Tests
- `test_battles` (10): FIGHT timing (wider timing), winning kindly; ACT, mercy, SPARE, DEFEND, TP from grazing, ITEM,
  Rally, Check; knocked down costs nothing, Story mode, Run; patterns seeded with every path working, aimed bullets
  aimed, bouncers inside the box, 17 templates, the busiest pattern 0.8 ms a frame; battle data (templates, saving,
  cleaning, syncing with the world); encounters (rare, Dark Worlds by default, cooldown, "I want to fight" and its
  look-alikes, reasons from memories); the HUD skin stays on this PC; a whole battle with the mouse (the real
  buttons, the heart following the mouse at a capped speed, FIGHT by a tap anywhere, SPARE, Done, the Battle Log,
  closeness, a Memory Book page, the bag unchanged); touch only with a knock-down and Try again; a friend walking
  up in a Dark World (Not now costs nothing; none in the Light World).

## 1.10.0 — Phase 25: the Light World and Dark Fountains

### Added
- **Dark Fountains** (a new piece in Build mode). Tap one in play: **Make a Dark World from this place** (the same
  layout in the Dark World palette, a void sky with slow shapes and stars, glowing outlines, props turned strange)
  or **Link** a Dark World you already have; then **Enter the Dark World**. Inside, you're Dark World Me and your
  friends wear a Dark World look made from their own pictures. The fountain there takes you **back to the Light
  World** (Real Me again), beside the fountain you came through.
- **Seal the fountain**: it closes for now (with its lid); nothing is deleted: the Dark World waits in the World
  Map's **Archive**, and **Reopen** opens it again (from the fountain or the Archive). A Memory Book page.
- **World Map layers:** the Light World, the Dark Worlds and the Archive; fountains marked 🌀.
- **Six animations, all drawn in code**, each skippable with a tap (Reduce motion: short fades): opening (cracks,
  the rising column, swirling particles, the colours draining), idle (flowing liquid, drifting particles, a hum),
  entering (a fall through darkness), transforming (drawn "transform in / out" frames from the Animations tab, or a
  generated morph), returning (rising into light) and sealing (light gathering, the column sinking). Lighter on
  phones.

### Changed
- Old saves (world v6, after a snapshot): every place is in the Light World, except places set to Dark World Me,
  which become Dark World places behind a new fountain beside the door that led there. The doors stay.
- The Animations tab has Transform in / Transform out.

### Tests
- `test_dark_worlds` (7): a Dark World made from a place (same layout, darker, doors left behind, void sky); fountains
  linked both ways, sealed into the archive and reopened, nothing deleted; old saves; friends' Dark World look and
  the morph; the whole journey with the mouse (open, enter, Dark World Me, outlines, back as Real Me beside the
  fountain, seal with a Memory Book page, reopen); every animation plays, a tap skips it, Reduce motion shortens
  it; a touch-only run. Frame strips of each animation captured at PC and phone size.

## 1.9.0 — Phase 24: places, not rooms, and a higher Platform camera

### Added
- **Places:** what the game called rooms are now places, **indoors**, **outdoors** or **somewhere strange**.
  Walls are optional, side by side. Outdoors the ground goes on to the horizon under a sky that can follow the
  time of day; somewhere strange floats in a dream sky. Up to three background layers (hills, trees, mountains,
  a city, dunes, clouds, shapes, stars) stand around a place at different distances and drift past each other as
  the camera moves. Build mode > **Place** (kind, sky, add a place; Advanced: walls, ground, layers).
- **Joined places:** **Add a place to the north / east / south / west** makes a place just like this one, joined
  at that edge. Walk off the edge (click, tap, the keys, or in Platform Mode) and you're at the matching spot of
  the next place; the next place's ground carries on beyond the join, with a glowing strip and its name.
- **Menu > World Map:** your places laid out like a land (joins side by side, doors as dotted lines); tap a place
  and Go there. Build mode's World Map arranges by joins too.
- **Templates for new places:** Cozy room, Meadow, Beach, Forest clearing, City street, Cave, Cloud tops, Starfield.
- **Reduce motion** (Settings > Comfort): every big moment in Update 6 is animated and skippable with a tap; this
  swaps the animations for short fades. Moving between places is the first of them.

### Changed
- **Platform Mode's camera is higher** by default (about 55 degrees, a little further back, looking ahead of you),
  so you see the ground ahead and the next ledge. Settings > Comfort > **Platform camera**: High, Classic (the old
  view) or Low.
- Your old rooms became places without changing: indoors, four walls, their own sky (world v5, after a snapshot).
- "Rooms" is "Places" everywhere you read it (the files are still in `rooms/`).

### Tests
- `test_places` (8): kinds, walls and backgrounds (junk in a file never breaks a place; the same layer paints the
  same picture); old rooms upgraded with every field unchanged after a snapshot; Add a place beside (both ways, the
  same size and look, ids unique, one per side) and crossing to the matching spot (scaled sizes); the World Map
  layout by joins; in the game: no walls outdoors, the ground, two layers, the next place's ground beyond a join, a
  time-of-day sky, walking across both ways; the crossing animated (over 0.5 s), skipped by a tap (much quicker),
  and a short fade with Reduce motion; the High / Classic / Low Platform camera keeping you and a ledge ahead in
  view; Places and the new settings on screen.

## 1.8.0 — Phase 23: the phone for real, and Polox for Android

### Fixed
- **A fresh phone's first sync no longer files "phone conflicts" on the PC.** On 2026-10-15 your phone paired,
  loaded the game and synced both ways over Same Wi-Fi (its requests are in `phone\phone_link.log`); the one thing
  left wrong was the four built-in tile sets a new phone makes on its first start, which the PC then kept as
  conflicts. A file that was never synced but exists on both sides now takes the PC's copy, and the phone keeps
  its own in `phone\first_sync_backup\`. Changes made on both sides later are still conflicts, as before.

### Added
- **Polox for Android (the app):** the same game as an APK you install yourself (arm64, made for 64-bit
  phones; iPhones keep the browser version). Settings > Phone Link > **Polox for Android**: **Build the app** (about a
  minute; signed with this PC's own key in `tools\android\`, never committed), **Install on my phone** over USB
  (adb, with plain answers for every usual problem), the steps Android will show, and **Pair the app**.
  Phone Link serves it at **`/app`** (a page with the steps for "install unknown apps") and the Launcher links it.
  `tools\export_android.bat` builds it from a terminal.
- **The app finds the PC by itself:** while Phone Link is on, the PC tells the home network "Polox is here" every
  two seconds (its name and port, nothing else); then the last address that worked; then Tailscale. It shows which
  path it's using.
- **Pairing in the app:** the PIN on a big keypad (one thumb), or **Scan the QR code** with the camera (asked for
  only then), reading the PC's new app pairing code with Polox's own QR decoder (tilted, turned, small, shadowed,
  blurred or smudged codes; about 0.1 s on a PC).
- **Offline play and automatic sync:** the app plays from its own copy without the PC, looks again every minute,
  syncs when it finds it, when you come back to the app, and a little after each save (same sync rules and
  conflicts as the browser version). It keeps every world the PC lets phones play.
- **Check connection inside the app** (Settings > AI): this phone's network, hearing the PC, reaching it, a 20 MB
  download, pairing and sync, step by step, and the report goes to the PC's Doctor.
- **Updates:** when the PC has a newer app, the app offers it (the download opens in the browser; your worlds stay).
  `/hello.json` and `/app/version.json` say which app the PC has.

### Changed
- The app turns with the phone; Android's back gesture is Polox's back. Performance mode and the pixel symbols are
  on automatically there, as in the browser.
- README, PHONE_SETUP.md: Polox for Android.

### Not included
- Invitation notifications: Android shows a later notification only through a part of the app that needs a Gradle
  build (extra downloads that weren't approved). See docs/history/PROGRESS.md, decision 181.

### Tests
- `test_android_app` (14): the plain-HTTP rule; the PC's announcement (four keys only) and the app hearing it
  (other programs' packets ignored); finding the PC by the home network, then the last address, then Tailscale,
  never another PC, each failure with a reason; the app QR code (no PIN in any address) and the decoder on 15
  pictures (turned, mirrored, tilted, far, shadowed, blurred, smudged, a small code on a big screen, a camera's
  brightness plane) plus pictures without a code; Reed-Solomon limits; `/app`, the APK download (type, name,
  SHA-256, HEAD, no pairing, a half-written APK not offered); the adb helper with a stand-in adb; the export
  preset and the built APK (arm64, five permissions, nothing but the game); Check connection end to end with the
  report reaching the PC; app mode in-process (wrong PIN, public address refused, pairing, worlds, sync, update
  offer, the PC away and back, resume); the PIN keypad; and **the whole app as a second Godot process
  (`--app-mode`)**: Connect, the PC found, PIN, sync, a block placed and pushed, offline play kept, the PC back with
  its own change, both synced, resume, the update offer.

## 1.7.0 — Phase 22: Connection Rescue, part 4 (Tailscale as the sure path, Plan B, triage)

### Added
- **Tailscale in three steps** on the Phone Link screen: install and sign in (it says if Tailscale isn't installed,
  isn't signed in, or no phone is on your tailnet or it's offline), **Enable** (it opens the admin page if HTTPS
  certificates are off, or Tailscale's one-time consent page), then the https address with a QR code. Through
  Tailscale the firewall and Wi-Fi client isolation don't matter; Same Wi-Fi keeps working alongside; never Funnel.
- **Plan B: Server engine: Bundled web server** (Advanced). `tools\fetch_server.bat` fetches Caddy 2.11.4 (official
  release, 17,559,418 bytes, SHA-256 `1708333f...2ebf` checked, Apache-2.0) after asking; Polox then runs it in
  front on the same port (game files served by Caddy, everything else proxied to Polox on 127.0.0.1 with a
  per-start secret), starts and stops it with Phone Link, stops a leftover one after a crash (only if it's really
  Caddy), falls back to the built-in engine if it can't start, and every report records which engine answered.
- **PHONE_TRIAGE.md:** a 5-minute procedure (PC and phone steps, what each result means, what to paste back).

### Changed
- PHONE_SETUP.md: the triage, Tailscale's three steps, Plan B; PHONE_TEST.md points to the triage first.

### Tests
- `test_plan_b_and_tailscale` (4): the three Tailscale steps for every situation, the Caddyfile, the forwarded phone
  address believed only with the secret (reports and contacts show the phone and the engine), the fallback to the
  built-in engine with Caddy missing, a stand-in that never listens is stopped, one that quits is reported, a
  leftover process id that isn't Caddy is never killed. Tailscale Serve was re-verified end to end on this PC
  (Polox's own mapping https:8765 -> 127.0.0.1:8765 answered /ping, /test/info.json and the 39.5 MB wasm, then was
  removed; your 443/8443 mappings untouched).

## 1.6.0 — Phase 21: Connection Rescue, part 3 (fixes you can click, and the game's start-up made visible)

### Added
- **Start-up diagnostics on the phone (rung R6):** the phone version's page now keeps the console and every error,
  checks WebAssembly, WebGL 2, storage and every game file's size (against index.html's `fileSizes`) before the
  engine needs them, and watches the start (loading that stops for 30 s, Godot's own error, a lost graphics
  context, the engine up but the game never appearing). Any failure shows a big card with what to try and sends a
  report to the PC by itself; triple-tap the top-left corner for the full panel (Send to PC, Copy, Connection test,
  Reload). A failure never looks like a blank page or an endless spinner.
- **One-click fixes** next to the Doctor's and Polox Ping's findings: open Windows network settings (for a Public
  network), run the firewall helper, open firewall settings (block all incoming), keep this PC awake, open Device
  Manager (adapter power saving). Nothing is changed silently.
- **`/reset`** on the phone: clears what Polox keeps in that browser for that address (pairing key, the phone's copy
  of your worlds, remembered choices, caches), after saying exactly what goes; plus a private-tab tip.
- The launcher's "Having trouble?" now opens the **Connection test**, with links to the PC details and Start fresh;
  the Phone Link screen has **My phone can't open it** with the steps (Network test, /test, phone tips).

### Changed
- **Keep this PC awake while Phone Link (or Polox Ping) is on** is now on by default (this PC slept after 10 minutes).
- The phone version is rebuilt with the start-up diagnostics; the Doctor asks for a rebuild when they're missing.

### Fixed
- A flaky variety test: a finished quest's reward can be the Dreamlight tile set (1 in 9), not only an item.

### Tests
- `test_boot_and_fixes` (5) and, in check_phone, in a phone-size browser over the home address: a healthy start
  (every start-up check green, the game reports itself up), a phone version with a cut-off file (caught and named,
  card shown, report sent), a browser without WebGL 2 (caught and named), and /reset clearing the pairing.

## 1.5.0 — Phase 20: Connection Rescue, part 2 (a boringly correct server)

### Changed
- **Plain answers by default:** every answer is HTTP/1.1 with a Content-Length and `Connection: close`, never
  chunked; gzip, ETag/304 and Range are **off** (Settings > Phone Link > Advanced > *Faster game downloads*
  switches them on once the phone's Connection Test passes).
- **The whole request is read before answering, and leftover bytes are drained before closing** (closing a
  socket with unread data makes Windows reset the connection, and the phone then shows "connection reset").
- **The game moved to a versioned address, `/game/<build id>/`.** HTML and game files are never cached
  (`no-store`); an old build's address answers "410 Gone" with a link to the launcher; nothing redirects.
- **Fixed, browser-safe port 8765** (was 8737), with 8766, 8767, 8080, 8888 as fallbacks; the port that worked is
  remembered. Existing settings move from 8737 to 8765 once, with a note. IPv4 on every adapter (`0.0.0.0`).
- `.js` files are served as `text/javascript`.
- **`allow_phone_link.bat` rewritten:** it shows exactly what it will change, asks Windows for admin rights
  itself, allows Polox's own programs on ports 8765, 8766, 8767, 8080 and 8888 on the network types in use,
  removes only block rules for Polox's programs (backed up first), and **Undo** (`allow_phone_link.bat remove`)
  also puts those block rules back.

### Fixed
- A full-tunnel VPN adapter with a default route could be offered as the "home network" address (found by
  the new address tests); virtual and VPN adapters now always rank below the real home network.

### Added
- Tests that behave like phones: `test_server_phone_like` (8: split/slow requests and byte-at-a-time headers, a
  body that stops half-way, unread bytes after a request, six 20 MB downloads with half-open idle sockets and an
  abort, HEAD, odd Host headers, a refused address, the exact Web export file set with `fileSizes`, stale build
  ids, address choice with WSL / Hyper-V / VPN / VirtualBox, port safety and fallback) and, in check_phone, the
  same against this PC's home-network address with six 39 MB wasm downloads, plus a check of this PC's real
  socket table that Phone Link listens on 0.0.0.0 as Polox's Godot.

## 1.4.0 — Phase 19: Connection Rescue, part 1 (the honest reset and the ladder tools)

### Fixed
- **Update 4's Phone Link settings upgrade never ran on existing setups**: the defaults carried a version number,
  so an old `settings.json` looked already upgraded and stayed on *Tailscale only* (every phone on the home Wi-Fi
  got "not allowed") with a one-phone limit. Upgrade 3 fixes such files (your own *Tailscale only* choice is
  kept), tested through the real loading path.

### Added
- **Polox Ping** (`ping.bat`, and Settings > Phone Link > **Network test**): a tiny separate test server on every
  address (ports 8765, 8080, 8888, whichever are free) that answers "Polox OK" to anything, shows every address
  worth trying in big text with a QR code, and lists every device that contacts it (or says "No device has
  contacted Polox Ping yet"), plus what this PC's facts say is in the way.
- **The phone-side Connection Test** at `<address>/test`: big readable checks with timings and exact errors
  (/ping, a small JSON fetch, WebAssembly, WebGL 2, storage, cookies, a 20 MB download checked by SHA-256 with its
  speed, the launcher's API), plain-language tips, **Copy report**, **Send to PC** (it also sends by itself).
- **Phone reports** (`/api/report`, no pairing needed, tightly limited) saved in `phone_reports/` and shown in the
  Doctor, the Phone Link screen and Polox Ping.
- **PC facts** (`tools/net_facts.ps1`, read-only): listening sockets and their program, the home adapter and the
  others, network type, firewall profiles, rules for Polox's exact programs (including rules limited to another
  Windows account and rules that block every program), other security software, VPNs, sleep settings.
- Every connection is recorded, even one that sends nothing or speaks HTTPS to the HTTP port; the Phone Link
  screen and the Doctor say "No device has contacted Phone Link yet" when that's the case.
- Tests: `test_rescue` (9) and, in check_phone, the Connection Test in a phone-size browser over the home address.

## 1.3.0 — Phase 18: Variety pack (so it never feels the same twice)

### Added
- **Daily Moments:** 1-3 a day from a weighted deck of 70 built-in entries (visitor, sky, found object,
  request, rumor, celebration, Memory Echo) plus your own; deterministic per world and date, no repeats within
  14 days, never two of a kind in a day; special days (holidays, your birthday, dates you add) always bring a
  Celebration; Memory Echo is opt-in (off). Visitors stay for the day (invite them to stay), found objects wait
  as pickups, requests become small quests, rumors are said by the residents, Sky Moments set the day's
  weather and colour the light (new aurora effect). A **Today in your world** card; **Today & Moments** panel
  (your own Moments, celebration dates, Memory Echo, and an Advanced Time Machine for testing).
- **Routines:** morning / afternoon / evening / night room and activity per resident (Personality tab);
  residents move as the day turns and say what they're up to.
- **While You Were Away:** after 3+ hours (counted up to 7 days) moods settle, routines are followed, and 0-3
  letters, diary pages or small gifts wait as pickups and in the Memory Book. One batched, cached AI request
  rewrites them in the residents' voices when an AI is set up; built-in templates otherwise.
- **Dream Quests and Requests:** 11 templates checked against the real world (build, decorate, visit, hidden
  spot, shards, checkpoint, talk about a topic, gift, make an item, draw a tile, opt-in real-life step), up to
  3 open, shaped by your Dreams board and World Bible, no failure state, Let it go any time; cosmetic rewards
  (keepsakes, outfit pieces, a Dream Door key, the Dreamlight tile set). **Quests** panel.
- **Dream Doors:** a door object that opens onto a seeded, freshly generated small room (a tile set chosen by
  your words, a vignette cut from a built-in template, maybe one of your stamps, palette, weather), with one
  surprise (a dream friend, a riddle sign, a Memory Shard or a gift) and a climb when Platform Mode is on.
  Every room is checked (flood fill + Room check). Keep it, or it waits in the Dream Archive (last 10).
- **Almanac** with titles to wear; Memory Shards add memories to the Memory Book.
- **Hangouts** (Menu > Hang out): Tea Time, Stargazing with "make a wish" (to your Dreams board) and a Photo
  Walk (a stroll with your friend, then a photo into the Memory Book); a moment each, an Almanac row and title.
- **Seasonal decorations** from the real date (Halloween, winter holidays, New Year, Valentine's, spring
  equinox, midsummer, your birthday, your own celebration dates) plus a season accent; visual only, never saved
  in rooms, rebuilt with the room and when the day changes; Settings > Game switch.
- Tests: `test_hangouts` (4): the three hangouts in the real game, and the decorations (right themes on the
  right dates, both hemispheres, nothing solid, never written to the room file, switched off, rebuilt).
- Tests: `test_variety` (12), including the acceptance: a 7-day simulated run where no two days match, two
  quests completed end to end by real changes, 20 Dream Doors valid and different, all with the AI off.

### Changed
- Absence is never punished: time away now lets loneliness settle to a gentle "glad you're back" (at most
  0.45) instead of rising.
- A brand-new world's first day has no visitors, found objects or requests (just yours).
- The aurora is soft, glowing ribbons of green and violet light above the room (it was big pixel dots).
- A Visit quest always names a room other than the one you're in.
- Taking a photo in a headless run (tests) returns at once instead of waiting for a frame that never comes.
- While You Were Away with an AI: its letters now also rewrite their Memory Book pages, and a stretch away is
  never sent to the AI twice (tested with a fake AI on 127.0.0.1).

## 1.2.0 — Phase 17: Platform Mode (activated by a Pillar; run and jump)

### Added
- **Platform Mode:** free third-person running and jumping over your own tiles and blocks, started only by a
  **Platform Pillar** (glowing column, rune rings, a soft hum, idle bob; label, colour, once or every time, an
  optional destination room and landing cell). A ~1 s start (flash, ring burst, camera swoop), an **Exit
  Pillar** where you began (it takes you home if a pillar sent you elsewhere), an always-visible **Leave**
  button and X / Esc. Per-world on/off in the World Bible; the editor's Play-test can start in it.
- **Movement** (all constants in `platform_config.gd`, 1 unit = 1 block): walk 4, run 7, a jump that clears
  1 block but not 2, air control, coyote time and a jump buffer (0.12 s), half-block step-up, ramps, moving
  platforms that carry you, jump pads, one-way ledges, slippery tiles, no fall damage. The kill plane and soft
  hazards fade you back to the last checkpoint. Assists: Auto-run, Auto-jump, Slow-fall, Camera assist.
- **One-handed controls** for keyboard (left hand), mouse alone (hold to run toward the pointer, on-screen
  Jump/Run/Leave) and phones (thumb stick, Jump, tap, two-finger orbit, handedness mirror).
- **Camera:** chase camera with wall collision, Camera assist on by default (follows forward movement only, so
  sideways never circles), Q/E steps, orbit, zoom, first person (V).
- **Run sprites:** animation states idle/walk/run/jump/fall/land (1-8 frames, fps, loop, mirrored). Character
  Creator > **Animations**: draw frames with onion skin, copy previous, import a sprite strip, Generate from
  base sprite, live preview. Without frames: generated motion (run lean, quicker bob, dust puffs,
  afterimages; jump stretch, fall lean-back, landing squash + dust). The doll maker's players get a built-in
  run cycle. Footsteps use each tile's step sound (now synthesized: soft, wood, stone, grass, water, metal).
- **Platformer pieces** (Advanced): jump pad, one-way ledge, moving platform, checkpoint, Memory Shard, soft
  hazard; Slippery tile flag; **Jump reach** overlay. Collision is merged per 16x16 chunk (a 32x32 block field
  is 9 boxes in 6 bodies).
- **Courses:** Sky Steps and Moon Ledges templates; a Platform Pillar and a tiny course in the Tile
  Playground (new worlds; older worlds get the pillar through world upgrade v4, snapshot first).
- Checkpoints, shards and woken pillars are saved in the world (and sync to the phone); nothing mid-air is
  ever saved: a save or quit in Platform Mode resumes at the checkpoint (or the start), walking.
- Tests: `test_platform_physics` (9), `test_platform_mode` (6), `test_platform_content` (4),
  `test_platform_acceptance` (3: keyboard, mouse only, phone thumb stick, each: pillar, run sprites, 1-block
  jump, missed jump -> checkpoint, Memory Shard, Exit Pillar).

### Changed
- Built-in templates carry a version: improved built-ins reach existing Libraries (your own templates never change).
- The block piece "Pillar" is now called "Column" in the palette (the Platform Pillar is something else).

## 1.1.0 — Phase 16: Phone Link on plain home Wi-Fi, the PIN and your worlds on the phone

Root causes (PROGRESS.md, *Phone Link postmortem 2*): your saved mode was Tailscale direct with *Tailscale
only*, which refuses every Wi-Fi phone; Auto picked Tailscale Serve, which listened on the PC itself only; the
screen showed only the Tailscale name; and a pairing code existed only for two minutes after pressing *Pair a
phone*, so your phone's pairing page (it got there at 23:17 and 00:09) had nothing to accept.

### Added
- **Same Wi-Fi with nothing to set up:** every mode listens on every address of the PC (plus 127.0.0.1) with the
  home allow-list (this PC, 192.168/10/172.16, link-local, Tailscale). Tailscale only ever adds an address;
  if Serve can't start, Same Wi-Fi keeps running. Auto picks Tailscale HTTPS when the PC can, else Same Wi-Fi,
  and the screen shows the mode in effect and exactly where it listens.
- **The Polox Launcher** at the PC's address (plain HTML, works without the game build): *Connected to
  "<PC>"* → *Enter the PIN shown on your PC* → **Your worlds** (cover, name, last played, size) → **Play**,
  plus **Forget this phone** and **Having trouble?**. Covers are fetched with the phone's key.
- **A PIN you can't miss:** shown big (482 913) with a countdown as soon as Phone Link is on; new every 10
  minutes and after each pairing; **New PIN**. 5 wrong tries from a phone = a 60 s countdown on the phone; 20
  wrong in an hour = pairing paused until **Unlock pairing** on the PC. Never logged, never in an address.
- **A banner on the PC, even mid-game,** when a phone first reaches it: *📱 Phone connecting: PIN 482 913*
  (click: Phone Link opens), then *Paired* / *Phone connected*.
- **`host.bat` opens a small window** with the address, QR code, PIN and *Phone connected* (the console
  prints the same).
- **No phone after a minute?** A checklist (same Wi-Fi, exact address, not localhost, firewall prompt,
  guest-network isolation, sleep) and the Doctor's findings, on the Phone Link screen.
- **"This is the PC"**: opening localhost on the PC itself says which address to open on the phone.
- **Save menu > ⋯ > 📱 Available on phone** per world (default: every world not in the Trash). A phone
  syncs only the world it plays.
- Paired phones list with **Forget**, and **Always ask for the PIN**. Up to four phones.
- Tests: `tests/test_phone_launcher.gd` (mode choice, settings upgrade, launcher, localhost helper, worlds,
  covers, session, per-world sync, PIN renewal, PC banner, host window, checklist, Save menu switch), the PIN
  rules in `test_phone.gd`, and in `check_phone.bat` the launcher flow on the real home-network address plus a
  headless phone-size browser that types the PIN, taps Play and syncs a block back.

### Changed
- Your Phone Link settings are upgraded once: *Tailscale only* off (a note says so), four phones allowed,
  per-world sharing instead of the old list. The Doctor checks the firewall in every mode and names
  *Tailscale only*, the PIN and paused pairing.
- PHONE_SETUP.md and PHONE_TEST.md now start with Same Wi-Fi.

## 1.0.0 — Phase 15: editor depth
- Added 16-pattern cardinal smart tiles, an atlas-variant wizard, and neighbor refresh when painting or erasing.
- Added Advanced custom layers, cell events, find/replace and re-skin, a draggable World Map with reciprocal doors, and a nine-slot favorites/recents hotbar.
- Made map connections transactional: failed two-room links leave both rooms untouched.
- Added tests for the wizard, all masks, events, undo/redo, replacement, re-skin and room graph integrity.
- Fixed (found in the final screenshot review): in the Advanced layout at 1280×720 the coach mark, the As/Fade/Solid row and the hotbar squeezed the tile grid to nothing. The grid now always keeps one row of tiles and the bottom dock grows instead.

## 0.9.0 — Phase 14: first-class tile layers

- Replaced split room tile arrays with versioned sparse tile layers and a snapshot-first world migration.
- Added 16×16 atlas-batched chunk meshes, nearest-filtered tiles, animated frames and incremental redraw/navigation updates.
- Kept the Phase 9 tile-set workflow and made it the editor's first view: Tiles palette, import/draw entry point and first-use coach mark.
- New worlds include a linked Tile Playground. The 100×100 stress test covers 11,025 cells, save/reload, draw-call budget and collision/nav updates.
- Phase 9 gap analysis and click paths are documented in docs/history/PROGRESS.md.
- Phone-side PC proxy timeout is capped at 4 seconds so offline chat reaches Mock fallback promptly.


## 0.8.0 — Phase 13: Phone Link that actually works (with Tailscale)

Diagnosed on this PC with the real server, the real phone version and real browsers (the full postmortem is in
docs/history/PROGRESS.md). Two things stopped every phone: **Windows Firewall block rules** for Polox's Godot (made when its
"allow access?" prompt was dismissed), and **Godot's web page refusing to start over plain HTTP** on a network
address (it wants HTTPS), plus an audio start-up crash right behind it.

### Added
- **Three ways in** (Settings > Phone Link): **Tailscale Serve (HTTPS)**, recommended and the default when
  available: a private `https://<pc>.<tailnet>.ts.net:8737` address, no firewall change, only your Tailscale
  login, never Funnel, Polox's own Serve port and mapping only. **Tailscale direct (HTTP)** with an optional
  *Tailscale only*. **Home Wi-Fi only (HTTP)**. Public internet addresses are always refused.
- **A guided setup** in that tab: 1 build the phone version (in-app, with progress), 2 pick a mode (live
  green/red checks: Tailscale, MagicDNS, HTTPS certificates, firewall, the phone on your tailnet), 3 switch
  on (the address, QR, Copy, Test; *Waiting for your phone...* turns into *Phone reached Polox*), 4 pair,
  5 first sync. Advanced: worlds, idle switch-off, keep this PC awake, ports, login check, a live request
  log, security events, the Doctor.
- **Phone Link Doctor** (in the tab, or `phone_doctor.bat`): checks the phone version, Phone Link, every
  address with real requests (including the https one), the firewall and network type, Tailscale, Serve,
  Funnel, pairing and the last phone contact, and explains each problem with its fix. **Copy diagnostics**
  (no keys, tokens, codes or chats).
- **`/hello`**: a tiny page any browser can open (no game needed) that says *Polox host reachable*, the
  address, mode and whether the phone version is ready: network problems vs game problems.
- **`allow_phone_link.bat`**: the optional, explained, removable firewall helper (asks for admin, Y/N).
- **`check_phone.bat`**: proves Phone Link on this PC (suites, every real address, stress, attacks, and a
  headless phone-size Edge playing the real phone version).
- `phone_link.log` (rotating; time, address, path, status: never keys, codes or chats).

### Changed
- **A new web server** (`http_server.gd`): up to 32 connections at once, header and idle timeouts, files
  streamed in 64 KB chunks, ETag/304, Cache-Control no-cache, HEAD, OPTIONS, Range, gzip copies (the 39.5 MB
  wasm travels as 10.1 MB), size limits, a source allow-list, a request guard, every request isolated (an
  error becomes a 500, never a dead server), a watchdog, and it keeps answering with the window minimized.
- **The phone version build** now also patches it for plain HTTP, writes gzip copies and a build id; the PC
  says when the phone version is older than its own Polox. `build/` is no longer imported into the game.
- **Phone side:** retries with backoff, every downloaded file checked by SHA-256, clear states (*PC offline*,
  *Not paired*, *Different address*), a warning in private tabs; the pairing page checks its key with the PC
  and warns about a different address; addresses ranked Tailscale > home network, virtual adapters hidden.

### Fixed
- Refused connections lost their error page (Windows reset); a crashing handler looped; a stalled download
  held its slot forever; a Serve mapping of another running Polox could be removed at start-up; the smoke run
  touched real Tailscale; Godot imported the build output.

### Tests
- `test_phone_link` (13), e2e: `test_phone_e2e` (3, real addresses) and `test_browser_e2e` (1, headless Edge),
  run by `check_phone.bat`. `check.bat`: 157 tests.


## 0.7.1 — The phone build, tried for real

The Web export was built (templates downloaded with your OK) and played through Phone Link in a browser at
phone size (390×844, touch): pair, first sync, Continue, walk, chat through the PC, quick replies, gift,
Bag, Build (a block placed and pushed to the PC), a PC-side rename pulled to the phone, PC offline. That
turned up the fixes below; none of them showed on the PC build or in the tests before.

### Fixed
- **Saves on the phone vanished on reload:** in a browser "Documents" is an in-memory folder; the phone's
  saves now live in the browser's own storage (`user://`, IndexedDB).
- **Every first sync stashed 9 false "conflicts"** (and again on every page load): each copy of the game writes
  the built-in templates with its own "created" time. Built-in templates no longer sync; yours still do.
- **A fresh start made an empty "My World"** (building the templates asked the active world about its tile
  sets and created one), so a new phone opened that instead of your world (*Begin* instead of *Continue*),
  and a new PC install showed a stray empty world. Fixed; a leftover empty folder can't hide a real world.
- **Symbols and emoji showed as boxes on the phone** (♥ ✓ ☁ ⚠ ⟳ 📱 📦, world icons...): the browser has no
  fallback fonts. The game now draws its own 57 pixel-art symbols there (procedural, no download); emoji an AI
  sends that the game can't draw are left out instead of boxed. The PC keeps your system's emoji.
- **Gift, ★ Save and Bye were hidden under the phone's text bar**, and the bar stayed on top of the gift picker.
  The chat box now sits above the bar, the bar shows only when it's your turn and nothing covers the chat, and
  the duplicate in-game text field is hidden on the phone.
- **Screens wider than a phone** (My character's Looks and Gear, Item Workshop, Friends, Chat Log, Settings,
  Memory Book, Worlds, Build mode) pushed Close off the edge. Rows of buttons now wrap, side-by-side columns
  stack on an upright phone, long captions and check boxes wrap, and as a safety net anything that still
  can't fit slides sideways under a header that keeps Close on screen. A phone on its side scrolls down.
- **The first sync took ~18 s for 90 files** (a request waits a few frames and the phone runs at 30 fps); it
  now fetches 6 files at a time: **2.8 s**.
- Phone wording: the title says *Tap to walk or talk • Long-press for the menu* and has no Quit; hints say
  Tap; Build mode points at the ⟳ R / ⇋ F buttons instead of keys; "Open save folder" is hidden in the browser
  (and every other "Open folder" button explains instead of opening a broken tab).
- The Bag gives the item details more of a tall screen, so *Give* / *Use* show without scrolling.
- Exporting needed ETC2/ASTC texture import switched on (`project.godot`); the Web export failed without it.

### Tests
- `test_web_build` (4): every symbol the game uses has a glyph; a fresh start leaves no empty world; built-in
  templates stay off the sync; every screen (and Build mode, and Worlds in grid and list) fits a phone upright
  and on its side. `test_phone_ux` checks the text bar hides under panels. 144 tests.

## 0.7.0 — Phase 12: Polish and delight

### Added
- **Quick-reply chips:** after each reply, up to three short things you might say next; tap one to say it.
  Real AIs suggest them in the same JSON reply (cleaned: strings only, ≤ 48 characters, no repeats); Mock,
  offline lines and greetings use canned sets that fit the moment (sad, happy, question, gift, bye...).
  Settings > Comfort can switch them off.
- **"Where was I?"** card when a world opens: where you were, the last thing said in a chat (and when), and a
  dream to cheer on, with *Talk to <friend>* when they're in the room. It fades by itself. Worlds now open in
  the room you were last in.
- **Autosave indicator:** a quiet *✓ Saved* under the room name whenever something is written (at most every
  3 s), and *📦 ... snapshot* when a snapshot zip is made.
- **Onboarding for the new features:** new players pick how they look (5 doll presets) in the welcome flow and
  get a hint about the Bag and My character; returning players see **New in Polox** once, with a button to
  try each new thing.
- (Landed with Phase 11: the left/right-hand setting for keys and phone buttons.)

### Fixed
- A key pasted into a chat was redacted in the chat log but could reach the Memory Book, memory notes or the
  summary (and from there snapshots and exports). All of those are redacted now.

### Tests
- `test_polish` (5) and `test_privacy` (1: a full session with a fake key, including Phone Link sync and the
  proxy; every file and zip searched, the key is only in `settings.json`). 140 tests.

## 0.6.0 — Phase 11: Phone Link

### Added
- **Phone Link** (Settings > Phone Link, off by default and off at every start): a small web server inside
  Polox (TCPServer with its own socket thread; API work on the main thread) that serves the phone (Web)
  build, a pairing page, a token-protected sync API and an AI proxy. Address list (home network first,
  Tailscale next, virtual adapters last), a QR code (built-in encoder), a 6-digit pairing code with a 2-minute
  countdown, the paired phone with **Unpair** / **Rotate token**, worlds to sync, idle auto-off (6 h default),
  recent security events. HUD indicator *📱 Phone Link ON · n devices*.
- **`host.bat`**: only the server, no game window; prints the addresses and a fresh pairing code until a phone
  is paired.
- **Pairing & security:** codes from the system's secure random generator, single use, 5 tries a minute,
  burnt after 10 wrong tries; 256-bit device tokens, only their SHA-256 stored, constant-time comparisons;
  one device by default; path allow-list (Library + chosen worlds), no `..`, no folders or listings, no CORS
  headers, 16 MB body and 16 KB header limits, `phone/audit.log`.
- **Sync** (PC is the master): manifest with SHA-256, size, time and revision; three-way comparison with the
  last common state; changed on one side → copied; on both → the PC keeps its version and the phone's goes to
  `slots/<id>/conflicts/`; chat logs merge by message id (every log line now has an `id`); deletions sync;
  snapshot zips before applying changes on both sides; per-file limits (8 MB, logs 16 MB).
- **Conflicts on the PC:** world cards show *⚠ n phone conflicts*; ⋯ > Phone conflicts → keep the PC version
  or use the phone's (snapshot first). A world changed from the phone reloads on the PC.
- **Phone side** (Web build): reads the pairing key, friends talk through the PC ("Your PC" provider, with
  offline lines and a *PC offline* badge when it's away), syncs on start, ~15 s after changes and when the
  page is hidden, ☁ sync chip in the HUD (tap = sync now). Settings > AI shows the PC link instead of keys.
- **Phone UX:** thumb-zone HUD (big Bag/Menu in the bottom corner, camera + Build in the other), long-press =
  back (or the menu), pinch = zoom, two-finger slide = turn, phone-sized scaling (≥ 48 px buttons), portrait
  and landscape layouts for the chat box, Bag and big panels, an HTML text bar so the phone keyboard always
  opens, page zoom/scroll/pull-to-refresh blocked, sound unlocked on the first tap, Performance mode (auto on
  phones: 30 fps, no real-time shadows, pictures ≤ 1024 px).
- **Left-hand setting:** I J K L / O / U / P / H / Y on the right side of the keyboard; phone buttons swap
  corners.
- `tools\get_web_templates.bat` (download + SHA-512 check, keeps only the Web templates) and
  `tools\export_web.bat`. `PHONE_SETUP.md` (setup, Tailscale, privacy, troubleshooting, `.polox` and APK
  fallbacks) and `PHONE_TEST.md` (a 10-step check on the phone).

### Tests
- `test_phone` (6, real sockets on 127.0.0.1): pairing (no/wrong/right/reused/expired code, device limit,
  rate limit, audit without secrets), auth (no/wrong/short/rotated token), 11 path-traversal and allow-list
  attacks, oversized body, garbage, no CORS, MIME types, no folders/listings, sync both ways with snapshot,
  a deliberate conflict preserved, chat logs merged by id, unpaired/offline phone, AI proxy (key never
  leaves), idle auto-off. `test_phone_ux` (5): gestures, thumb layout + mirror, left-hand keys, performance
  mode, phone mode, resolving a conflict (134 tests in all). The QR encoder was checked by decoding its output with jsQR
  (versions 1, 2, 3, 9); the pairing page and the chat text bar were checked in a browser at phone size.

## 0.5.0 — Phase 10: My character and the Item Workshop

### Added
- **My character** (Menu): the **Player Profile** (name, pronouns, nicknames, birthday, about me, "friends
  know my dreams" with a link to the Dreams board, your own text-blip voice). It goes into every friend's
  prompt together with how you look right now and what you're wearing.
- **Two forms, Real Me and Dark World Me**: each from the **doll maker** (skin with marks, 8 hair styles,
  6 eye styles incl. a glow visor, 6 outfits, 8 accessories; hue/strength/brightness sliders and swatches;
  Randomize; 5 built-in presets and your own presets saved to the Library) or **drawn by hand** in the
  Character Creator (all eight faces). Rename forms, describe them for your friends, switch any time
  (Menu, or F), and tie rooms to a form (Build > Room, or My character > Looks).
- Your own faces: your sprite reacts to what you type (happy, sad, thinking...), and your lines type out
  above the chat box in your voice next to a little portrait.
- Walking now squashes a little on each landing. Every friend has a voice: 6 blip sounds, pitch, speed.
- **Item Workshop**: weapons, armor (head/body/accessory), snacks and keepsakes with name, rarity colour,
  flavor text (**✨ Suggest** via the AI, offline ideas when it can't), gift tags, an icon (25 auto-drawn
  shapes in any colour, your drawing, or an imported picture), an optional world picture, show-only stats
  and one tiny effect (mood boost when gifted, aura colour, sound, message, a moment of coloured light).
  **Make one** puts it in your bag. 16 whimsical starter items.
- **Bag** (HUD button or B): grid with type tabs, sort (newest, name, rarity, type), search, tooltips and a
  details pane: use / eat, equip / take off, edit in the Workshop, throw one away. Equipped items are drawn
  on your character (switchable) and an item's aura glows under you.
- **Pickups** (Build > Objects > Pickup): put an item somewhere; walk onto it to pick it up; once or daily;
  "Put it back" in the editor.
- **Gifting from the bag**: friends have editable liked/disliked tags; matches decide the reaction, mood and
  closeness change by simple rules, the gift and its effect are in the Chat Log, and friends remember your
  recent gifts (shown in Menu > Friends and given to the AI). Up to three gifts per friend a day.

### Changed
- `world.json` is now version 2. The first load of an older world saves a `pre_migration` snapshot, then:
  a hand-painted avatar becomes Real Me (same file, untouched), the untouched default avatar becomes the
  matching doll, Dark World Me starts as the "Night wanderer" doll, friends get tags from their Likes and
  Dislikes text, and the bag gets the starter items.
- The old fixed gift list is gone; its gifts are now starter items with the same tags.
- Menu: "My look" became **My character**; new **Bag**, **Item Workshop** and **Switch to ...** entries.

### Fixed
- A self-referencing preload in the Worlds look panel kept scripts alive at quit (leak errors at exit).
- The smoke run no longer depends on how many segments a Mock reply has.

### Tests
- `test_player` (8): doll styles/expressions/tints/randomize/presets, forms + room ties, faces and walk
  squash in the world, profile/looks/dreams/nicknames in the prompt, voices, the v1 -> v2 upgrade with its
  snapshot (painted avatar kept byte-for-byte; default avatar -> doll). `test_items` (6): designs and icons,
  bag sort/filter/equip/stacks, effects and the gear overlay, editor pickups (once/daily), flavor text
  offline fallback, and the Phase 10 acceptance run. Gift tests in `test_life` rewritten. 123 total.

## 0.4.0 — Phase 9: Organized editor, tile sets, foreground, templates

### Added
- **Editor layout:** top bar (room, Tiles | Objects | Room tabs, Undo/Redo, Save, Play-test from the
  cursor, Done), left toolbox, right inspector + Layers (Advanced), bottom palette strip with a tab per tile
  set + Pieces + Colours and a search box, status bar with hints, a collapsible minimap/room list.
  Simple/Advanced toggle, draggable dividers, "Reset layout", remembered layout. "?" cheat sheet.
- **Tools:** place, brush (a drag is one undo step), line, rectangle (filled/outline), flood fill, erase,
  eyedropper, box-select with copy/cut/paste/rotate/flip/delete/"Save as stamp", stamp, random-variant
  brush, brush size 1-5, elevation 0-5, grid snap (half-cell signs and plants). Undo/redo keeps 150 steps.
- **Layers:** Backdrop (colour or panorama picture) | Ground (flat tiles, batched) | Blocks (blocks, textured
  cubes, standing/wall pictures) | Foreground (overlay pictures that fade when they hide someone). Each has
  visibility, lock and opacity. Per-tile settings in the inspector: solid, fade, tint, orientation
  (flat, standing, N/E/S/W wall), rotation, mirror, elevation.
- **Tile sets:** saved with the world (`tilesets/<set>/`), shared through the Library (copy on use). Make
  them from a PNG atlas (auto-slice with preview and naming), single PNGs, or the pixel paint tool with a
  seamless 3×3 preview; rename, reorder, tag, duplicate, delete (warns when in use), 2-4 frame animations,
  export/import `.polox-tiles`, Save to Library. Four starter sets drawn in code: Cozy Home, Dream Meadow,
  Dark Castle, Night Sky. New worlds start with all four.
- **Templates:** nine built-in levels (Cozy Room, Hallway, Garden, Cave, Castle Hall, Night Rooftop, Dream
  Island, Empty, 3-room Cozy Apartment) plus "Save this room as a template" (name, description, tags,
  automatic thumbnail, optionally the rooms its doors lead to). Gallery with "New room" and "Apply here"
  (replace keeps your doors; merge keeps your tiles). Templates bundle the tile sets they need.
- **Stamps:** select an area → Save as stamp; drop anywhere with rotate/flip.
- **Room check:** unreachable doors, doors to missing rooms, missing pictures, blocked start spot,
  overlapping tiles; click an issue to jump the cursor there.

### Changed
- The old build dock is gone; the HUD hides while the editor is open (the editor has its own bars).
- Rooms gained `ground`, `foreground` and `layers` fields; old rooms load unchanged.

### Tests
- `test_tilesets` (8) and `test_editor` (6): built-in sets, atlas and drawn tiles, library/bundles, layer
  operations, room check, rendering + foreground fade, persistence, templates/stamps, strokes as one undo
  step, 150 undo steps, shape tools, lock, select/copy/paste/rotate/flip, eyedropper, random brush,
  restart persistence, play-test. 109 total.

## 0.3.0 — Phase 8: Worlds (customizable save menu)

### Added
- **Worlds screen** (title screen and in-game Menu > Worlds): every save is a card with cover
  (auto screenshot or your own picture), emoji, colour, notes, tags, last played, playtime, rooms/friends
  counts and size. Grid or list, search, sort (last played / name / playtime / newest), tag filter.
  Layout and look (5 colour themes, 3 frame styles, 3 text sizes) are remembered.
- **Actions per world:** Play, Save now, Quick-save (F5), Edit card, Duplicate, Export `.polox`,
  Open folder, Verify, Back up now, Restore (timeline), Delete to Trash.
- **Trash:** deleted worlds wait 30 days; Restore or Delete forever. Never instant.
- **Bundles:** `.polox` export/import (validated: no path tricks, size and file limits, must hold a world).
- **Snapshots:** per-world autosave zips on a timer, on room change and on quit (card settings; default 10
  kept, manual backups never pruned). Restore makes a "before restore" snapshot first.
- **Verify:** every JSON parses, pictures open, nothing missing; a manifest (SHA-256 per file) written
  with each snapshot/export flags hand edits as "changed" (not corruption). "Accept changes" re-baselines.
- A damaged world file that even its backup copies can't rescue opens the Verify/Restore screen instead
  of an empty world.
- New world: guided (welcome flow) or blank. Each new world is its own slot; nothing is replaced any more.

### Changed
- **Save folder layout 2:** worlds live in `Documents\Polox\slots\<id>\`; `settings.json` (with the API key)
  and `audio\` are shared at the root; `trash\`, `snapshots\`, `exports\` beside them. The first start
  zips the whole folder into `snapshots\before_layout2_<date>.zip`, then moves the old single world into
  its slot (same drive: nothing is copied or deleted).
- Backups never contain `settings.json` any more (it isn't inside a world).

### Tests
- `test_slots` (8): layout migration with snapshot, cards/stats/playtime, trash round trip + purge, bundle
  export/import + hostile bundles refused, snapshot/prune/restore after corruption, verify, duplicate and
  switch in game, title without a world. 95 total.

## 0.2.0 — Phase 7: Polox (rename, audit, foundation)

### Changed
- The game is now **Polox**: window title, title screen, project name, docs and scripts.
- Saves live in `Documents\Polox\`. On first start an existing `Documents\PocketDarkWorld\` is **copied**
  (never moved), every file is checked (SHA-256), and a one-time note explains what happened.
  The old folder is left as it was.
- `PDW_SAVE_ROOT` is now `POLOX_SAVE_ROOT`; backup zips are `Polox_backup_<date>.zip`.
- Rendering: desktop keeps the Mobile renderer; web and phone builds use Compatibility (WebGL 2).

### Fixed (see docs/history/AUDIT.md for the full table)
- Saves are atomic with a `.bak` of the previous version; broken files are restored automatically.
- Hand-edited or corrupt room files load instead of crashing.
- Chat history reads only the tail of big logs; the Log Viewer is paginated.
- Typing in the build dock can no longer trigger build hotkeys.
- Arriving through a walled-in door no longer strands the player outside the room.
- Imported pictures are validated and shrunk to 2048 px; junk files are refused.
- Rooms with many blocks are batched (MultiMesh) and build ~10× faster with far fewer nodes.
- Residents' positions are saved on quit along with pending build edits.
- Dialogue box fits small windows and big UI scales; window minimum size 960×600.

### Added
- `check.bat` runs a headless smoke session after the tests.
- `export_presets.cfg` (Web + Windows presets), `AUDIT.md`, this changelog.
- Tests: `test_rename` (no old name left, migration copy/verify), `test_audit` (12 audit tests). 87 total.
