# Third-party notices

Polox builds on the work listed here. Everything else in the repository was made for Polox and is
covered by [LICENSE](LICENSE). Source, licence and distribution rights of every asset, file by file, are
in [docs/ASSET_AUDIT.md](docs/ASSET_AUDIT.md).

## Inside every build

### Godot Engine 4.7.2 (MIT)

<https://godotengine.org>. Copyright (c) 2014-present Godot Engine contributors; copyright (c) 2007-2014
Juan Linietsky, Ariel Manzur.

Polox's Windows, Android and web builds run Polox's own build of the official Godot 4.7.2 source with
the small fixes in `native/godot/patches/` and with the engine modules the game doesn't use left out
(`native/godot/polox_profile.py`). The engine itself contains third-party software (FreeType, HarfBuzz,
zlib, zstd, libpng, libwebp, mbedTLS, PCRE2, ThorVG, minimp3, libogg, libvorbis and others). The complete
list with every copyright line and licence text ships with the Windows setup program and the portable
zip as `licenses/GODOT_ENGINE_NOTICES.txt`; `tools/release/write_engine_notices.gd` writes it from the
engine binary itself.

### Kenney (CC0 1.0)

<https://kenney.nl>. CC0 asks for no credit; these are credited anyway. Pack versions, download addresses
and file hashes are in `assets/kenney/manifest.json`.

| Pack | Version | Used for |
| --- | --- | --- |
| City Kit Suburban | 2.0 | Trees |
| City Kit Roads | 2.2 | The street lamp |
| Furniture Kit | 2.0 | The bench, and the furniture models in `assets/models/furniture/` built from its parts |
| Nature Kit | 2.1 | The bush and the flowers |
| Emotes Pack | not stated in the pack | The feeling balloons above friends |
| Tiny Town | 1.1 | The built-in "Tiny Town" tile set |
| Impact Sounds | 1.0 | Three footsteps |
| UI Audio | not stated in the pack | Seven clicks and switches |

### Poly Haven (CC0 1.0)

<https://polyhaven.com>. Sources and hashes are in `assets/materials/manifest.json` and
`assets/sky/manifest.json`.

| Asset | Authors, where Poly Haven names them | Used for |
| --- | --- | --- |
| laminate_floor_02, wood_planks, floor_tiles_06, fabric_pattern_07, concrete_floor_02, painted_plaster_wall, red_brick_03, clay_roof_tiles_02, asphalt_02, leafy_grass | Poly Haven | Light World floors, walls, roofs, streets and lawns (`assets/materials/`) |
| long_white_tiles | Sergej Majboroda (photography), Jenelle van Heerden (processing) | Glazed tile floors (`assets/materials/ceramic/`) |
| Lantern_01 | Rajil Jose Macatangay | The glass lantern (`assets/polyhaven/lantern_01/`) |
| kloofendal_48d_partly_cloudy_puresky | Poly Haven | Reflections under an open sky (`assets/sky/`) |

## Optional, fetched on the player's PC (not in the repository or the builds)

- **The Detailed pack** (`assets/detail/`, git-ignored): higher-resolution Poly Haven surfaces and ten
  Poly Haven furniture models, all CC0, fetched by `tools/get_detail_pack.py`. The models and their
  authors are listed in [docs/ASSET_CREDITS.md](docs/ASSET_CREDITS.md).

## Used to build Polox (not redistributed by this repository)

Downloaded by the scripts in `tools/` into git-ignored folders: the Godot editor and source (MIT), Eclipse
Temurin JDK 17 (GPL-2.0 with the Classpath Exception), the Android SDK and NDK (Android Software
Development Kit License Agreement), Gradle (Apache-2.0), Emscripten (MIT and University of
Illinois/NCSA), LLVM-MinGW (Apache-2.0 with LLVM Exception, plus mingw-w64's licences), SCons (MIT) and,
for the optional "Plan B" web server, Caddy (Apache-2.0). The Android plugin compiles against Godot's own
classes and the Kotlin standard library (Apache-2.0) without packaging them. The furniture models and
textures were made with Blender (GPL; its licence doesn't cover what is made with it). The Windows setup
program is made with Inno Setup (<https://jrsoftware.org/isinfo.php>, Inno Setup License), and the public
source snapshot is checked with gitleaks (<https://github.com/gitleaks/gitleaks>, MIT).

## Services Polox can talk to

Only when you set them up, with your own account or key: the AI provider you choose (Settings > AI),
OpenStreetMap's Nominatim and Overpass services for mapping your street (data (c) OpenStreetMap
contributors, ODbL), and Tailscale for Phone Link away from home. Polox ships no key of its own for any
of them.
