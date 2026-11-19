# Blender (background): Poly Haven CC0 textures -> Polox's surface materials.
#   blender -b --factory-startup --python tools/blender_scripts/prepare_materials.py -- <src_dir> <out_dir> <size>
# For each material: the colour map with its ambient occlusion multiplied in (one texture less to sample
# on a phone), the OpenGL normal map, both at <size> px; plus materials.json with each material's average
# colour (linear; the shaders divide by it so a texture adds detail, not a colour) and its roughness.
import bpy, json, os, sys
import numpy as np

src, out, size = sys.argv[sys.argv.index("--") + 1:]
size = int(size)
MATERIALS = {
    "wood": "laminate_floor_02", "planks": "wood_planks", "tile": "floor_tiles_06", "carpet": "fabric_pattern_07",
    "concrete": "concrete_floor_02", "plaster": "painted_plaster_wall", "brick": "red_brick_03",
    "roof": "clay_roof_tiles_02", "asphalt": "asphalt_02", "grass": "leafy_grass",
}


def load(path, colour):
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    img.scale(size, size)
    px = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(size, size, 4)


def to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def save(px, path, colour):
    img = bpy.data.images.new(os.path.basename(path), size, size, alpha=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    img.pixels.foreach_set(px.astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "JPEG"
    try:
        img.save(filepath=path, quality=90)
    except TypeError:
        img.save()
    bpy.data.images.remove(img)


def find(folder, asset, kind):
    for f in os.listdir(folder):
        if f.startswith(asset + "_") and kind in f and f.endswith(".jpg"):
            return os.path.join(folder, f)
    raise FileNotFoundError(asset + " " + kind)


info = {}
for name, asset in MATERIALS.items():
    diff = find(src, asset, "_diff_") if any("_diff_" in f and f.startswith(asset) for f in os.listdir(src)) else find(src, asset, "_col_")
    col = load(diff, True)
    arm = load(find(src, asset, "_arm_"), False)
    nor = load(find(src, asset, "_nor_gl_"), False)
    lin = to_linear(col[..., :3]) * arm[..., 0:1]            # ambient occlusion in the colour
    avg = lin.reshape(-1, 3).mean(axis=0)
    rough = float(arm[..., 1].mean())
    os.makedirs(os.path.join(out, name), exist_ok=True)
    srgb = np.concatenate([to_srgb(lin), np.ones((size, size, 1), np.float32)], axis=2)
    save(srgb, os.path.join(out, name, "albedo.jpg"), True)
    save(nor, os.path.join(out, name, "normal.jpg"), False)
    info[name] = {"source": asset, "average_linear": [round(float(v), 4) for v in avg], "roughness": round(rough, 3)}
json.dump(info, open(os.path.join(out, "materials.json"), "w"), indent=1)
print("prepared", len(info))
