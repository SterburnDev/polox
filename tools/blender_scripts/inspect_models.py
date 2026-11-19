# Blender (background): reports each model's size, triangles, materials and which side is taller.
#   blender -b --factory-startup --python tools/blender_scripts/inspect_models.py -- <out.json> <model.glb>...
# Sizes are in glTF axes (x right, y up, z towards the viewer).
import bpy, bmesh, json, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out_path, files = argv[0], argv[1:]
report = {}
for path in files:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    deps = bpy.context.evaluated_depsgraph_get()
    pts, tris, mats = [], 0, {}
    for o in meshes:
        ev = o.evaluated_get(deps)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        mw = o.matrix_world
        tris += len(me.loop_triangles)
        for t in me.loop_triangles:
            name = me.materials[t.material_index].name if me.materials and t.material_index < len(me.materials) and me.materials[t.material_index] else "none"
            mats[name] = mats.get(name, 0.0) + t.area
        pts += [mw @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    if not pts:
        report[path] = {"error": "no mesh"}
        continue
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = hi - lo
    mid = (lo + hi) / 2
    # Blender -Y is glTF +Z (front). Tallest point in the front half vs the back half.
    front = max([p.z for p in pts if p.y < mid.y] or [lo.z]) - lo.z
    back = max([p.z for p in pts if p.y >= mid.y] or [lo.z]) - lo.z
    left = max([p.z for p in pts if p.x < mid.x] or [lo.z]) - lo.z
    right = max([p.z for p in pts if p.x >= mid.x] or [lo.z]) - lo.z
    report[path.replace("\\", "/").split("/")[-1]] = {
        "size_gltf": [round(size.x, 3), round(size.z, 3), round(size.y, 3)],
        "tris": tris, "objects": len(meshes),
        "materials": {k: round(v, 3) for k, v in sorted(mats.items(), key=lambda kv: -kv[1])},
        "tall_front_back_left_right": [round(front, 3), round(back, 3), round(left, 3), round(right, 3)],
    }
json.dump(report, open(out_path, "w"), indent=1)
print("inspected", len(report))
