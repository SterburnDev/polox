# Asset credits and licences

Every outside asset Polox uses or can use, where it came from, its licence, what was changed and where
it may go. Three questions are answered separately for each: may it be **used in Godot**, **shipped
inside the finished game**, and **published in a public source repository**.

## In the repository (public)

| Asset | Author / source | Licence | Changes | Used for | Godot | Game | Public repo |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ten surface scans (`assets/materials/`) | Poly Haven, see `assets/materials/manifest.json` | CC0 1.0 | 1K JPG to 512 px, ambient occlusion multiplied into the colour | Light World floors, walls, roofs, streets | Yes | Yes | Yes |
| "Partly cloudy" sky (`assets/sky/`) | Poly Haven, see `assets/sky/manifest.json` | CC0 1.0 | None | Reflections under an open sky (PC, High) | Yes | Yes | Yes |
| Kenney kits (`assets/kenney/`, `assets/models/furniture/`) | Kenney (kenney.nl), see `assets/kenney/manifest.json` | CC0 1.0 | Rebuilt in Blender, baked shading, fitted to footprints | Furniture, bench, tree, street lamp, footsteps | Yes | Yes | Yes |
| Polox Originals (`bundled-addons/polox-originals/`) | Polox (made in code) | Polox's own | n/a | The original tunes and Dream Drop Soul | Yes | Yes | Yes |
| "Long White Tiles" (`assets/materials/ceramic/`) | Poly Haven ([long_white_tiles](https://polyhaven.com/a/long_white_tiles)): photography Sergej Majboroda, processing Jenelle van Heerden | CC0 1.0 | 1K JPGs (colour, OpenGL normal, AO, roughness) to 512 px; AO multiplied into the colour; roughness drawn lower (0.24 to 0.14) for a glaze; colour tinted per room by the surface shader | Glazed tiled floors in the Light World, the Dream Gate's tile apron | Yes | Yes | Yes |
| "Lantern 01" (`assets/polyhaven/lantern_01/`) | Poly Haven ([Lantern_01](https://polyhaven.com/a/Lantern_01)): Rajil Jose Macatangay | CC0 1.0 | 1K glTF (brass and glass) with camera/EXIF metadata stripped from textures; fitted to a 0.34 x 0.52 m footprint in game; translucent glass and a warm light inside | The glass lantern (Decorate, and the starter room) | Yes | Yes | Yes |
| "UI Audio" (`assets/kenney/ui_audio/`, 7 of its 50 sounds) | Kenney ([kenney.nl/assets/ui-audio](https://kenney.nl/assets/ui-audio)), its `License.txt` kept beside them | CC0 1.0 | None (click3, click5, mouserelease1, switch2, switch7, switch19, switch33 picked) | Button clicks, switches flipping, the wall light switch | Yes | Yes | Yes |

The three sets above were downloaded on 8 November 2026 with the owner's approval (about 4 MB). CC0 waives
copyright worldwide, so they may be adapted, shipped and committed to a public repository; the credits
are voluntary. The paper journal, the stereo, the switches, the glass, the title's hills and lake and
the light switch are drawn in code for Polox (Apple's interfaces were references only; no Apple artwork
or screenshots are in the game).

## The optional Detailed pack (`assets/detail/`, git-ignored; downloaded on this PC 7 November 2026)

Turned on with **Settings > Display > PC graphics > Fine-tune > Textures: Detailed** (PC only). It
swaps in 2K surfaces with separate roughness and ambient-occlusion maps and more detailed furniture,
fitted to each piece's existing footprint. Object ids, collisions, saved worlds and gameplay don't change.
`tools/get_detail_pack.py` lists the exact files and sizes and, with `--download`, fetches them and
writes `assets/detail/manifest.json` (URL, size and MD5 of every file).

| Polox piece | Poly Haven asset | Size (1K glTF) | Licence |
| --- | --- | --- | --- |
| armchair | [ArmChair_01](https://polyhaven.com/a/ArmChair_01) | 0.8 MB | CC0 |
| sofa | [Sofa_01](https://polyhaven.com/a/Sofa_01) | 0.5 MB | CC0 |
| coffee_table | [CoffeeTable_01](https://polyhaven.com/a/CoffeeTable_01) | 1.0 MB | CC0 |
| nightstand | [ClassicNightstand_01](https://polyhaven.com/a/ClassicNightstand_01) | 0.4 MB | CC0 |
| chair | [painted_wooden_chair_01](https://polyhaven.com/a/painted_wooden_chair_01) | 0.5 MB | CC0 |
| dining_table | [dining_table](https://polyhaven.com/a/dining_table) (Aron Łyczek) | 2.3 MB | CC0 |
| bookshelf | [painted_wooden_shelves](https://polyhaven.com/a/painted_wooden_shelves) | 2.1 MB | CC0 |
| dresser | [painted_wooden_cabinet](https://polyhaven.com/a/painted_wooden_cabinet) | 1.9 MB | CC0 |
| bar_stool | [metal_stool_01](https://polyhaven.com/a/metal_stool_01) | 2.3 MB | CC0 |
| plant | [potted_plant_01](https://polyhaven.com/a/potted_plant_01) | 6.3 MB | CC0 |
| Ten surfaces, 2K colour, normal, roughness, AO | the same scans as `assets/materials/` | about 95 MB | CC0 |

All CC0, so all three answers are yes; it's git-ignored only for its size (113.5 MB, 92 files; every size and MD5
checked against Poly Haven's API, listed in `assets/detail/manifest.json`). Changes: none to the files; Godot
imports the 2K surface maps as GPU-compressed textures with mipmaps (normal maps as normal maps), and each
model is uniformly scaled into the original piece's bounds at runtime. To publish it,
remove `/assets/detail/` from `.gitignore` (or use Git LFS).

**Material and scale fit:** Poly Haven's furniture is photographic wood, fabric and metal at real-world
scale. Each model is uniformly scaled into the original piece's bounds, so it never squashes and never
outgrows its footprint. The player's paint colour doesn't tint detailed models yet; they keep their scanned colours.

### Marketplaces looked at

- **Fab (fab.com), including Unreal listings.** Free and paid listings use either CC-BY or the Fab
  Standard License. The Standard License covers free items too, and it allows assets inside a shipped game.
  Per Epic's own summary, it doesn't allow redistributing the source assets, so they can't sit in a
  public repository. Fab assets could go in a git-ignored pack like this one, used in local builds only,
  after reading the licence on the listing itself ([Fab EULA](https://www.fab.com/eula),
  [licences in Fab](https://dev.epicgames.com/documentation/fab/licenses-and-pricing-in-fab)).
  Nothing was taken from Fab: signing in and buying need you, and Poly Haven covers the first selection under CC0.
(WoodenTable_02 was tried first for the dining table and replaced: it is a small round table, which looked like a
stool squeezed into a dining table's footprint.)
- **Unity Asset Store.** The standard EULA allows use in a game but not redistribution of the source
  files, and Unity-specific materials need rebuilding for Godot. Not used.
- **Godot Asset Library / Kenney / Poly Haven.** CC0 and MIT assets fit all three uses; Polox already relies on them.

No purchases were made. If a paid pack is wanted later, list the product link, price, intended use and a
CC0 alternative here before buying.

## Private media

The owner's soundtrack, Soul picture, Music-secret pictures and the UTDR Theme are not cleared for
distribution. They live only in the git-ignored `assets/local/` and reach private builds through that
pack's manifests. What each one is, why it is private and what public builds use instead is in
[ASSET_AUDIT.md](ASSET_AUDIT.md); how the two kinds of build are made and checked is in
[RELEASES.md](RELEASES.md).
