# Blender (background): makes Polox's furniture models from Kenney's CC0 kits.
#   blender -b --factory-startup --python tools/blender_scripts/build_furniture.py -- <spec.json> <out_dir> <report.json>
#
# For each model in the spec: imports its parts (a kit model, or several placed together: a desk with a
# screen and keyboard, a bookcase with books on its shelves), scales them to real metres, joins them into
# one mesh with one slot per material (fewer draw calls on phones), turns it to face south (+z in Godot)
# with its back to the north, fits it in its footprint (only ever smaller, or stretched for rugs and
# stairs), puts the origin at the floor under its centre, renames the material the player's paint tints
# to "paint", makes lamp shades glow, and exports a GLB. The report lists each model's size and triangles.
#
# Coordinates in the spec are Godot's (x right, y up, z south); Blender's are (x, -z, y).
import bpy, json, sys, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
spec_path, out_dir, report_path = argv
spec = json.load(open(spec_path))
root_dir = spec.get("root", ".")
kits = spec["kits"]
MARGIN = spec.get("margin", 0.06)


def godot_to_blender(v):
    return Vector((v[0], -v[2], v[1]))


def import_part(path):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.context.scene.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def bounds(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def apply_matrix(obj, m):
    obj.data.transform(m)
    obj.data.update()


def shelf_heights(obj, lo, hi):
    """Heights of the upward-facing boards inside a bookcase (not its top or bottom)."""
    hs = {}
    for p in obj.data.polygons:
        if p.normal.z > 0.95 and p.area > 0.0005:
            z = round((obj.matrix_world @ p.center).z, 3)
            hs[z] = hs.get(z, 0.0) + p.area
    rows = sorted(z for z, a in hs.items() if lo.z + 0.05 < z < hi.z - 0.05)
    out = []
    for z in rows:
        if not out or z - out[-1] > 0.12:
            out.append(z)
    return out


def base_name(name):
    return name.split(".")[0]


report = {}
for item in spec["models"]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    placed = []
    for part in item["parts"]:
        kit = kits[part["kit"]]
        obj = import_part(f"{root_dir}/{kit['dir']}/{part['file']}.glb")
        s = float(part.get("scale", kit["scale"]))
        apply_matrix(obj, Matrix.Rotation(math.radians(part.get("rot", 0)), 4, "Z") @ Matrix.Scale(s, 4))
        lo, hi = bounds(obj)
        at = godot_to_blender(part.get("at", [0, 0, 0]))
        if "on" in part:   # standing on an earlier part
            at.z += bounds(placed[part["on"]])[1].z
        bottom_centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
        apply_matrix(obj, Matrix.Translation(at - bottom_centre))
        placed.append(obj)
        if part.get("books_on_shelves"):
            blo, bhi = bounds(obj)
            for i, z in enumerate(shelf_heights(obj, blo, bhi)):
                for j, x in enumerate([-0.18, 0.16]):
                    b = import_part(f"{root_dir}/{kit['dir']}/books.glb")
                    apply_matrix(b, Matrix.Rotation(math.radians(180 * ((i + j) % 2)), 4, "Z") @ Matrix.Scale(s, 4))
                    l2, h2 = bounds(b)
                    apply_matrix(b, Matrix.Translation(Vector((x, (blo.y + bhi.y) / 2, z)) - Vector(((l2.x + h2.x) / 2, (l2.y + h2.y) / 2, l2.z))))
    # One object, one slot per material.
    bpy.ops.object.select_all(action="DESELECT")
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    me = obj.data
    first = {}
    keep = []
    for i, m in enumerate(me.materials):
        key = base_name(m.name) if m else "none"
        if key not in first:
            first[key] = len(keep)
            keep.append(bpy.data.materials.get(key) or m)
    remap = [first[base_name(m.name) if m else "none"] for m in me.materials]
    idx = [remap[p.material_index] for p in me.polygons]
    me.materials.clear()
    for m in keep:
        me.materials.append(m)
    for p, k in zip(me.polygons, idx):
        p.material_index = k
    # Turn, fit and ground.
    apply_matrix(obj, Matrix.Rotation(math.radians(item.get("rot", 0)), 4, "Z"))
    lo, hi = bounds(obj)
    size = hi - lo
    w, d = item["fit"][0], item["fit"][1]
    margin = item.get("margin", MARGIN)
    if item.get("stretch"):
        h = item.get("height", size.z)
        sc = Vector(((w - margin) / size.x, (d - margin) / size.y, h / size.z))
    else:
        f = min(1.0, (w - margin) / size.x, (d - margin) / size.y)
        sc = Vector((f, f, f))
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    apply_matrix(obj, Matrix.Diagonal((sc.x, sc.y, sc.z, 1.0)) @ Matrix.Translation(-centre))
    # Paint and glow.
    for m in me.materials:
        if m and base_name(m.name) == item.get("paint"):
            m.name = "paint"
        if m and base_name(m.name) in item.get("glow", []) or (m and m.name == "paint" and item.get("paint") in item.get("glow", [])):
            bsdf = m.node_tree.nodes.get("Principled BSDF") if m.use_nodes else None
            if bsdf:
                bsdf.inputs["Emission Color"].default_value = bsdf.inputs["Base Color"].default_value
                bsdf.inputs["Emission Strength"].default_value = 1.6
    obj.name = item["id"]
    me.name = item["id"]
    lo, hi = bounds(obj)
    me.calc_loop_triangles()
    out = f"{out_dir}/{item['id']}.glb"
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_apply=True,
        export_cameras=False, export_lights=False, export_animations=False, export_materials="EXPORT")
    report[item["id"]] = {"size_m": [round(hi.x - lo.x, 3), round(hi.z - lo.z, 3), round(hi.y - lo.y, 3)],
        "tris": len(me.loop_triangles), "materials": [m.name for m in me.materials]}
json.dump(report, open(report_path, "w"), indent=1)
print("built", len(report))
