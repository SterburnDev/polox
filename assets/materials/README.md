# Surfaces (Poly Haven, CC0)

Eleven surfaces for the Light World, from **Poly Haven** (https://polyhaven.com), **CC0 1.0**
(no attribution required; credited voluntarily). `manifest.json` lists each source asset, its
page, the download location and the SHA-256 of every file here; `materials.json` holds each
surface's average colour and roughness.

| Folder | Poly Haven asset | Used for |
|---|---|---|
| wood | laminate_floor_02 | Wooden and vinyl floors in your home |
| tile | floor_tiles_06 | Tiled and stone floors |
| carpet | fabric_pattern_07 | Carpeted floors (its weave, lightly) |
| concrete | concrete_floor_02 | Concrete floors, pavements and paths |
| plaster | painted_plaster_wall | House walls |
| brick | red_brick_03 | The street's houses (painted brick in their colours) |
| roof | clay_roof_tiles_02 | The street's roofs |
| asphalt | asphalt_02 | Roads |
| grass | leafy_grass | Lawns, parks and yards |
| planks | wood_planks | (ready for decks and fences; not drawn yet) |
| ceramic | long_white_tiles | Glazed tiled floors (bathrooms, kitchens) and the Dream Gate's tile apron (added 2026-11-08; prepared by a Godot image script, same steps) |

Made by `tools/blender_scripts/prepare_materials.py` (Blender 5.2.3) from Poly Haven's 1K JPGs
(MD5-checked on download): 512 px, the ambient occlusion map multiplied into the colour (one
texture less for a phone to read), the OpenGL normal map kept. In the game a shader takes only
each texture's pattern (its brightness against its own average), so a room keeps the colour
your home has. Battery saver draws plain colours.

`assets/sky/partly_cloudy.hdr` is Poly Haven's **kloofendal_48d_partly_cloudy_puresky** (CC0),
reduced to 1024 x 512 by `tools/blender_scripts/prepare_sky.py`: what the Light World's streets
reflect on a PC at High (`assets/sky/manifest.json`).
