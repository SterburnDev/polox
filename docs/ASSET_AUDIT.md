# Asset audit: sources and distribution rights

Every picture, model, sound and data file that ships in a build or sits in the repository, where it
came from, and whether it may be redistributed. Audited on 10 November 2026 against the files on disk,
the import records and the manifests beside each asset; the pack check
(`tools/release/verify_pack.py`) enforces the result on every build.

**The rule:** a public build and the public repository contain only rows marked *Cleared*. Rows marked
*Private* exist only in the owner's git-ignored `assets/local/` and reach private builds through that
pack's manifests ([RELEASES.md](RELEASES.md)).

## Cleared: in the repository and in every build

| Asset | Where | Source | Licence | Evidence |
| --- | --- | --- | --- | --- |
| Furniture models (36) and their baked textures | `assets/models/furniture/` | Built in Blender from Kenney's Furniture Kit and Nature Kit parts (`tools/blender_scripts/build_furniture.py`, `texture_furniture.py`); six pieces modelled from scratch (`model_props.py`: bar stool, bean bag, coat rack, fish tank, piano, wall clock) | CC0 parts; Polox's own work | `assets/kenney/manifest.json` (archive hashes), `License_furniture-kit.txt`, `License_nature-kit.txt` |
| Bench, tree, street lamp, emote balloons, Tiny Town tiles, footsteps, UI clicks | `assets/kenney/` | Kenney (kenney.nl): City Kit Suburban 2.0, City Kit Roads 2.2, Furniture Kit 2.0, Emotes Pack, Tiny Town 1.1, Impact Sounds 1.0, UI Audio | CC0 1.0 | `manifest.json`, a `License.txt` in each folder |
| Ten surface scans | `assets/materials/` | Poly Haven; resized and prepared by `tools/blender_scripts/prepare_materials.py` | CC0 1.0 | `assets/materials/manifest.json` (asset pages, MD5 checked against Poly Haven's API) |
| Long White Tiles | `assets/materials/ceramic/` | Poly Haven: Sergej Majboroda, Jenelle van Heerden | CC0 1.0 | manifest entry `ceramic` |
| Lantern 01 | `assets/polyhaven/lantern_01/` | Poly Haven: Rajil Jose Macatangay; the published 1K glTF | CC0 1.0 | [ASSET_CREDITS.md](ASSET_CREDITS.md) |
| Partly cloudy sky | `assets/sky/` | Poly Haven `kloofendal_48d_partly_cloudy_puresky`; reduced by `prepare_sky.py` | CC0 1.0 | `assets/sky/manifest.json` |
| Battle sprites (bullets and six opponents) | `assets/battles/*.svg` | Drawn for Polox as SVG | Polox's own | First committed with the battles they belong to; shapes and gradients only, no embedded images |
| Music-secret pictures (8) | `assets/secret/yam_*.svg` | Drawn by `tools/art/make_secret_yams.py` | Polox's own | The script regenerates them byte for byte (`--check`); `tests/test_secret.gd` checks they embed no outside picture |
| Polox Originals | `bundled-addons/polox-originals/` | A manifest only: the tunes and the Dream Drop are made in code (`scripts/core/synth.gd`, `scripts/ui/soul.gd`) | Polox's own | No media files in the folder |
| Every other sound | none (made at run time) | Synthesized by `scripts/core/synth.gd` and the battle audio scripts | Polox's own | No recorded audio besides the Kenney rows |
| Shaders, the scene, the web page shell | `shaders/`, `scenes/`, `export_presets.cfg` | Written for Polox | Polox's own | |
| Fonts | none bundled | The engine's built-in font and the system's fonts and emoji | Covered by the engine's notices | No `.ttf`, `.otf` or `.woff` in the repository |
| Test fixtures | `tests/fixtures/` | Written for the tests: made-up towns, made-up replies, a synthetic add-on pack | Polox's own | File names say `madeup`; `make_public_source.py` finds no personal details in them |
| Pixel icon | `icon.svg` | Drawn for Polox (rectangles) | Polox's own | |

Metadata inside these files was checked by `make_public_source.py`: three of the Lantern 01 textures
carry Poly Haven's own EXIF block (the authoring tool's name, no location, no person). Nothing else has
EXIF, XMP or PNG text chunks.

## Confirmed by the owner

| Asset | Where | What is known |
| --- | --- | --- |
| The app icon artwork, and everything made from it (the logo, the splash screen, every icon size, the Android adaptive icon) | `assets/icon/` | The owner's own artwork (confirmed 10 November 2026). `tools/make_icons.gd` derives the other sizes from `polox_icon_source.png`. Cleared for public builds; the name, logo and icon are not licensed for reuse (see [LICENSING.md](LICENSING.md)) |

## Drawn by code for 1.29.0

| Asset | Where | Notes |
| --- | --- | --- |
| The eight Music-secret drawings in public builds | `assets/secret/yam_*.svg`, made by `tools/art/make_secret_yams.py` | Original |
| The written face of a sign | `scripts/characters/sprite_factory.gd` (`sign_face`) | Original, no file |
| The open-ground texture | `scripts/world/surface_detail.gd` (`_ground`) | Original, no file |

## Private: never in the repository, never in a public build

| Asset | Where | Why it is private | In private builds |
| --- | --- | --- | --- |
| The owner's soundtrack: five MP3s from commercial games and artists | `assets/local/music/` | Commercial recordings; fine for the owner's own copy, not redistributable | Yes: the default music |
| Mochi, the Soul picture | `assets/local/pictures/mochi.png` | Source and rights unconfirmed | Yes: the default Soul |
| The owner's Music-secret pictures (8 JPEGs) | `assets/local/secret/` | Collected from elsewhere; authors unknown | Yes: listed under `secret_images` |
| UTDR Theme: 24 songs from UNDERTALE and DELTARUNE, and their names for things | `assets/local/addons/utdr-theme/` (the editable copy is `local-addons/utdr-theme/`) | Commercial soundtrack recordings and another game's names | Yes, as an optional add-on, off by default |
| An older song folder | `assets/music/` | Commercial recordings from before add-ons existed | No: excluded by every export preset |
| Screenshots on the private Hub's page | `storefront/images/` | May show the owner's real home and street as mapped in the Light World | Not in any build; left out of the public snapshot |
| Everything a player makes | `PersonalData/` | It is the player's | Never: no export includes it |

How the split is enforced:

1. `.gitignore` lists `assets/local/`, `local-addons/`, `assets/music/` and `PersonalData/`, so they
   can't be committed.
2. The public snapshot is made from committed files only, and `build_windows.py --flavor public`
   refuses a tree that contains `assets/local/`.
3. `verify_pack.py --flavor public` fails if the finished build contains any path under `assets/local/`
   or the imported copy of any file from it; `--flavor private` fails unless the build contains exactly
   the files the pack's manifests list.

## Optional and fetched by the player

| Asset | Where | Source | Licence |
| --- | --- | --- | --- |
| The Detailed pack: 2K surfaces and ten furniture models | `assets/detail/` (git-ignored, PC only, left out of Android and web builds) | Poly Haven, fetched by `tools/get_detail_pack.py`; every URL, size and MD5 is in the manifest it writes | CC0 1.0 |

It may be redistributed; it is kept out of the repository only for its size (about 113 MB). A Windows
build made on a PC that has fetched it includes it.

## Replacements made for the public flavour

| Private asset | Public replacement | Notes |
| --- | --- | --- |
| The owner's soundtrack | Polox's own tunes, synthesized per cue | Already the fallback whenever the pack is absent |
| Mochi | The Dream Drop | Same size, hit area and flash; drawn in code |
| The owner's secret pictures | Eight yam drawings in the game's glossy aqua style | New in this release; the secret behaves the same |
| UTDR Theme | None needed | It was optional; the Dream World's own names are the default |
| Private Hub screenshots | Not replaced yet | The public README has no screenshots until new ones are taken from a fresh, made-up world |

## Keeping this true

- Adding an asset: record its row here and, for outside work, in
  [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and the manifest beside it.
- Before every release: `make_public_source.py` (repository contents) and `verify_pack.py` (build
  contents). Both exit non-zero on a problem.
