# Kenney assets used by Polox

Creator: **Kenney** (https://kenney.nl). Every pack below is **CC0 1.0**.
Attribution is optional under CC0; Polox credits Kenney voluntarily.

`manifest.json` records the source and download URLs, pack versions, archive SHA-256,
individual incorporated file hashes, changes and integration points.
The original `License.txt` notice from each pack is kept beside its assets.

| Pack | Version | Incorporated assets | Used in |
|---|---|---|---|
| City Kit Suburban | 2.0 | tree-small.glb, Textures/colormap.png | Tree furniture, including generated neighbourhood trees |
| City Kit Roads | 2.2 | light-square.glb, Textures/colormap.png | Street lamp in the outdoor furniture catalogue |
| Furniture Kit | 2.0 | bench.glb; 28 models made from it in Blender (`assets/models/furniture/`) | Bench; beds, tables, sofas, kitchen, bathroom, lamps, rugs, stairs... |
| Nature Kit | 2.1 | 2 models made from it in Blender (bush, flowers) | Bush and flowers furniture |
| Emotes Pack | (not stated) | 8 pixel balloons, `emotes/` | Feelings floating above friends |
| Tiny Town | 1.1 | Tilemap/tilemap_packed.png, `tiny_town/` | The built-in "Tiny Town" tile set (24 tiles) |
| Impact Sounds | 1.0 | footstep_wood_000.ogg, footstep_concrete_000.ogg, footstep_grass_000.ogg | Wood, stone and grass footsteps |

**Original files** (bench, tree, street lamp, the emote balloons, the Tiny Town sheet, the
footsteps) are unchanged. The bench, tree and lamp are centred, grounded and scaled at
run time to Polox's footprints; Tiny Town's tiles are cut from the sheet and doubled to
32 px at run time.

**Models made in Blender** (`assets/models/furniture/*.glb`, by
`tools/blender_scripts/build_furniture.py` from `furniture_spec.json`, Blender 5.2.3): each is
one mesh with one slot per material (few draw calls on a phone), in metres, facing south,
centred on the floor of its catalogue footprint (only ever smaller, or stretched for rugs,
the runner and stairs). Some are put together from several kit pieces: the computer desk
(desk, screen, keyboard, mouse), the TV (television on its cabinet), the bookshelf (books
on each shelf), the nightstand (with a table lamp) and the flowers (five). The material the
player's paint tints is named `paint`; lamp shades glow.

Explicit player paint tints only that material; picking, rotation and placement ghosts
keep their behaviour. Sound volume uses the player's controls, and player-provided sound
files win. Godot's `.import` metadata accompanies the incorporated resources.

The downloaded archives stay outside the game in ignored folders with `.gdignore`
(`build/update9/kenney_sources/`, `build/downloads/kenney/`). The Food Kit, City Kit
Commercial, Game Icons, 1-Bit Pack and Pixel UI Pack were downloaded with the others but
nothing from them is in the game yet.

Verification (1.27.0): `tests/test_update10_assets.gd` builds every model turned both ways
(fits its footprint, rests on the floor, one mesh, one pick body, placement ghost), checks
that paint tints only `paint` and a painted lamp still glows, and that the emote balloons
load; `tests/test_tilesets.gd` checks the fourteen starter sets, Tiny Town included.
