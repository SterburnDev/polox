# Records where 1.27's assets came from (run with plain Python):
#   python -I tools/blender_scripts/record_provenance.py
# Updates assets/kenney/manifest.json (the emotes, the nature kit, and the furniture models made in Blender)
# and writes assets/materials/manifest.json + assets/sky/manifest.json for the Poly Haven files.
import hashlib
import json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def sha256(relative_path: str) -> str:
    return hashlib.sha256((PROJECT_ROOT / relative_path).read_bytes()).hexdigest()


def inventory(folder: str, extensions: tuple[str, ...]) -> list[dict[str, str]]:
    entries = []
    for path in sorted((PROJECT_ROOT / folder).iterdir(), key=lambda entry: entry.name):
        # Manifest paths travel with the repository and use forward slashes on all platforms.
        relative_path = path.relative_to(PROJECT_ROOT).as_posix()
        if path.is_dir():
            entries.extend(inventory(relative_path, extensions))
        elif path.name.lower().endswith(extensions):
            entries.append({"path": relative_path, "sha256": sha256(relative_path)})
    return entries


def read_json(relative_path: str) -> dict:
    return json.loads((PROJECT_ROOT / relative_path).read_text(encoding="utf-8"))


def write_manifest(relative_path: str, manifest: dict) -> None:
    (PROJECT_ROOT / relative_path).write_text(json.dumps(manifest, indent=1), encoding="utf-8")

CC0 = "https://creativecommons.org/publicdomain/zero/1.0/"
m = read_json("assets/kenney/manifest.json")
m["packs"] = [p for p in m["packs"] if p["pack"] not in ("emotes-pack", "nature-kit", "tiny-town")]
m["packs"].append({
    "pack": "tiny-town", "version": "1.1", "license": "CC0-1.0", "license_url": CC0, "creator": "Kenney",
    "required_attribution": "None; creator credited voluntarily", "source_url": "https://kenney.nl/assets/tiny-town",
    "download_url": "https://kenney.nl/media/pages/assets/tiny-town/a415fbeb49-1735736916/kenney_tiny-town.zip",
    "archive_sha256": "9768692dccff1d706408a5aedd6ca4f6cd1409506cbc84cb2f862919764be977",
    "changes": "Original bytes retained (Tilemap/tilemap_packed.png). scripts/world/tileset_factory.gd cuts 24 tiles "
               "from it at run time, doubles them to 32 px (nearest) and names them: the built-in \"Tiny Town\" tile set.",
    "files": inventory("assets/kenney/tiny_town", (".png", ".txt")),
})
m["packs"].append({
    "pack": "emotes-pack", "version": "not stated in the pack", "license": "CC0-1.0", "license_url": CC0, "creator": "Kenney",
    "required_attribution": "None; creator credited voluntarily", "source_url": "https://kenney.nl/assets/emotes-pack",
    "download_url": "https://kenney.nl/media/pages/assets/emotes-pack/d00a3dcb06-1677578798/kenney_emotes-pack.zip",
    "archive_sha256": "96ab3f2c92d7acd860942efca1c9f1295184b11d3db5c79c28da82036e496526",
    "changes": "Original bytes retained (PNG/Pixel/Style 1). Shown as billboards above friends by scripts/characters/actor.gd.",
    "files": inventory("assets/kenney/emotes", (".png", ".txt")),
})
m["packs"].append({
    "pack": "nature-kit", "version": "2.1", "license": "CC0-1.0", "license_url": CC0, "creator": "Kenney",
    "required_attribution": "None; creator credited voluntarily", "source_url": "https://kenney.nl/assets/nature-kit",
    "download_url": "https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip",
    "archive_sha256": "fa7974a0d342bfe63c38664ba9f8ec1a4aab8ea25f099bdc56870e33588c4d9d",
    "changes": "Used only through the derived furniture models below (bush, flowers).",
    "files": [{"path": "assets/models/furniture/License_nature-kit.txt", "sha256": sha256("assets/models/furniture/License_nature-kit.txt")}],
})
m["derived_models"] = {
    "folder": "assets/models/furniture",
    "made_by": "tools/blender_scripts/build_furniture.py with tools/blender_scripts/furniture_spec.json, Blender 5.2.3",
    "from": "furniture-kit 2.0 (archive e67652d0...) and nature-kit (archive fa7974a0...)",
    "changes": "Parts joined into one mesh per model with one slot per material; scaled to metres (x2, flowers x1.5); "
               "turned to face +z; composites placed (desk with screen, keyboard and mouse; television on its cabinet; "
               "books on the bookcase shelves; a lamp on the nightstand; five flowers); fitted to the catalogue footprint "
               "(only smaller, or stretched for rugs, runner and stairs); origin on the floor under the centre; the paintable "
               "material renamed \"paint\"; lamp shades made emissive.",
    "files": inventory("assets/models/furniture", (".glb", ".txt")),
}
m["integration"]["models"] = ("scripts/world/licensed_props.gd via Furniture.build: bench, tree, streetlamp (original files) "
    "and 30 catalogue pieces from assets/models/furniture (BAKED)")
m["integration"]["emotes"] = "scripts/characters/actor.gd emote(): eight symbols shown as pixel balloons"
write_manifest("assets/kenney/manifest.json", m)

ph = read_json("assets/materials/materials.json")
write_manifest("assets/materials/manifest.json", {
    "creator": "Poly Haven (https://polyhaven.com)", "license": "CC0-1.0", "license_url": CC0,
    "required_attribution": "None; credited voluntarily",
    "made_by": "tools/blender_scripts/prepare_materials.py, Blender 5.2.3: 1K JPGs -> 512 px; ambient occlusion (ARM red) "
               "multiplied into the colour; OpenGL normal map kept; average colour and roughness in materials.json",
    "sources": {k: {"asset": v["source"], "page": "https://polyhaven.com/a/" + v["source"],
                    "downloads": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/%s/ (diff or col_1, nor_gl, arm; 1k jpg; MD5 checked against api.polyhaven.com/files)" % v["source"]}
                for k, v in ph.items()},
    "files": inventory("assets/materials", (".jpg",)),
})
write_manifest("assets/sky/manifest.json", {
    "creator": "Poly Haven (https://polyhaven.com)", "license": "CC0-1.0", "license_url": CC0,
    "asset": "kloofendal_48d_partly_cloudy_puresky", "page": "https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky",
    "download": "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/kloofendal_48d_partly_cloudy_puresky_2k.hdr (MD5 checked)",
    "made_by": "tools/blender_scripts/prepare_sky.py, Blender 5.2.3: 2K -> 1024x512 Radiance HDR",
    "files": inventory("assets/sky", (".hdr",)),
})
print("recorded")
