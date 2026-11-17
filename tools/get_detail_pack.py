"""Fetches Polox's optional Detailed pack from Poly Haven (every asset CC0) into assets/detail/.

    python tools/get_detail_pack.py            # list what it would download, with sizes (no download)
    python tools/get_detail_pack.py --download # download, check sizes, write assets/detail/manifest.json
    python tools/get_detail_pack.py --download --only=dining_table   # just these pieces (comma-separated)

Surfaces: the 2K versions of the ten scans Polox already uses (assets/materials/manifest.json): colour,
OpenGL normal, roughness and ambient occlusion, as JPGs. Models: glTF at 1K textures, one folder each,
named after the Polox piece they replace (licensed_props.gd BAKED). Godot imports both when the editor
or an export next runs. Nothing outside assets/detail/ is touched.
"""
import json
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "detail")
API = "https://api.polyhaven.com"
UA = {"User-Agent": "Polox-detail-pack"}

# Polox piece -> Poly Haven model. Chosen for a cosy, slightly stylised home: wood and fabric, low poly.
MODELS = {
    "armchair": "ArmChair_01", "sofa": "Sofa_01", "coffee_table": "CoffeeTable_01", "nightstand": "ClassicNightstand_01",
    "chair": "painted_wooden_chair_01", "dining_table": "dining_table", "bookshelf": "painted_wooden_shelves",
    "dresser": "painted_wooden_cabinet", "bar_stool": "metal_stool_01", "plant": "potted_plant_01",
}
MAP_NAMES = {"albedo": "Diffuse", "normal": "nor_gl", "rough": "Rough", "ao": "AO"}


def get_json(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA)))


def strip_jpeg_metadata(data):
    """Removes JPEG APP1 (EXIF/XMP) and COM segments without re-encoding image data."""
    if not data.startswith(b"\xff\xd8"):
        return data
    import struct
    out = bytearray(b"\xff\xd8")
    i, n = 2, len(data)
    while i < n:
        if data[i] != 0xFF:
            out.extend(data[i:])
            break
        j = i + 1
        while j < n and data[j] == 0xFF:
            j += 1
        if j >= n:
            break
        marker = data[j]
        i = j + 1
        if marker == 0x00 or marker == 0xD8 or (0xD0 <= marker <= 0xD7):
            out.extend([0xFF, marker])
            continue
        if marker == 0xD9:
            out.extend(b"\xff\xd9")
            break
        if marker == 0xDA:
            out.extend([0xFF, marker])
            out.extend(data[i:])
            break
        if i + 2 > n:
            break
        seg_end = i + struct.unpack(">H", data[i:i + 2])[0]
        if marker in (0xE1, 0xFE):
            i = seg_end
            continue
        out.extend([0xFF, marker])
        out.extend(data[i:seg_end])
        i = seg_end
    return bytes(out)


def plan():
    files = []
    mats = json.load(open(os.path.join(ROOT, "assets", "materials", "manifest.json"), encoding="utf-8"))["sources"]
    for polox, src in mats.items():
        info = get_json(f"{API}/files/{src['asset']}")
        for kind, key in MAP_NAMES.items():
            e = info.get(key, {}).get("2k", {}).get("jpg")
            if e:
                files.append({"url": e["url"], "size": e["size"], "md5": e.get("md5", ""), "to": f"materials/{polox}/{kind}.jpg",
                              "asset": src["asset"], "page": f"https://polyhaven.com/a/{src['asset']}"})
    for polox, asset in MODELS.items():
        g = get_json(f"{API}/files/{asset}")["gltf"]["1k"]["gltf"]
        files.append({"url": g["url"], "size": g["size"], "md5": g.get("md5", ""), "to": f"models/{polox}/{polox}.gltf", "asset": asset,
                      "page": f"https://polyhaven.com/a/{asset}"})
        for rel, inc in g.get("include", {}).items():
            files.append({"url": inc["url"], "size": inc["size"], "md5": inc.get("md5", ""), "to": f"models/{polox}/{rel}", "asset": asset,
                          "page": f"https://polyhaven.com/a/{asset}"})
    return files


def main():
    files = plan()
    only = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), None)
    total = sum(f["size"] for f in files)
    for f in files:
        print(f"{f['size'] / 1e6:6.2f} MB  {f['to']}  <- {f['url']}")
    print(f"{len(files)} files, {total / 1e6:.1f} MB, all CC0 from Poly Haven")
    if "--download" not in sys.argv:
        return
    import hashlib
    for f in files:
        if only and not any(f["to"].startswith(f"models/{o}/") or f["to"].startswith(f"materials/{o}/") for o in only):
            continue
        dest = os.path.join(OUT, f["to"])
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        data = urllib.request.urlopen(urllib.request.Request(f["url"], headers=UA)).read()
        if len(data) != f["size"] or (f["md5"] and hashlib.md5(data).hexdigest() != f["md5"]):
            raise SystemExit(f"size or checksum mismatch: {f['url']}")
        if dest.lower().endswith((".jpg", ".jpeg")):
            data = strip_jpeg_metadata(data)
        open(dest, "wb").write(data)
    manifest = {"creator": "Poly Haven (https://polyhaven.com)", "license": "CC0-1.0",
                "license_url": "https://creativecommons.org/publicdomain/zero/1.0/", "required_attribution": "None; credited voluntarily",
                "made_by": "tools/get_detail_pack.py: downloaded, sizes and MD5 checked against api.polyhaven.com/files, JPEG EXIF/XMP stripped",
                "files": [{k: f[k] for k in ("to", "asset", "page", "url", "size")} for f in files]}
    json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8"), indent=1)
    print("done:", OUT)


if __name__ == "__main__":
    main()
