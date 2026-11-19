# Blender (background) model audit: geometry health, UV health, draw-call proxies, rigs and textures.
#
#   blender -b --factory-startup --python audit_models.py -- <out.json> <model.glb>...
#
# Read-only: every model is imported into a fresh empty scene and nothing is written back.
# Sizes are reported in glTF axes (x right, y up, z towards the viewer). Blender is z-up, so
# glTF y == Blender z and glTF z == -Blender y.
import json
import math
import sys
import traceback

import bmesh
import bpy
import numpy as np

# Budgets for a phone-class (Adreno 7xx) renderer: one furniture piece is drawn many times a frame.
TRIS_BUDGET = 6000
SURFACES_BUDGET = 3
TEXTURE_BUDGET_PX = 1024
ZFIGHT_PLANE_TOL = 0.0005   # metres: coplanar closer than this fights in a 24-bit depth buffer at room distances
ZFIGHT_NORMAL_TOL = 0.01
MIN_TRI_AREA = 1e-9


def tri_overlap_2d(a, b, eps=1e-7):
    """Separating-axis test for two 2D triangles. True when their interiors overlap by more than eps."""
    for tri in (a, b):
        for i in range(3):
            p, q = tri[i], tri[(i + 1) % 3]
            ax = (-(q[1] - p[1]), q[0] - p[0])
            length = math.hypot(ax[0], ax[1])
            if length < 1e-12:
                continue
            ax = (ax[0] / length, ax[1] / length)
            a_proj = [v[0] * ax[0] + v[1] * ax[1] for v in a]
            b_proj = [v[0] * ax[0] + v[1] * ax[1] for v in b]
            if max(a_proj) <= min(b_proj) + eps or max(b_proj) <= min(a_proj) + eps:
                return False
    return True


def plane_basis(normal):
    """Two perpendicular unit vectors spanning the plane with this normal."""
    helper = np.array([1.0, 0.0, 0.0]) if abs(normal[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    u = np.cross(normal, helper)
    u /= np.linalg.norm(u)
    v = np.cross(normal, u)
    return u, v


def zfight_pairs(tri_world, tri_normals, tri_surface, slot_names):
    """Count pairs of same-facing, near-coplanar, overlapping triangles that belong to different surfaces/polygons."""
    count = len(tri_world)
    if count < 2:
        return 0, 0, []
    offsets = np.einsum("ij,ij->i", tri_normals, tri_world[:, 0, :])
    key = np.round(tri_normals / ZFIGHT_NORMAL_TOL).astype(np.int64)
    buckets = {}
    for index in range(count):
        buckets.setdefault((key[index, 0], key[index, 1], key[index, 2]), []).append(index)
    found = 0       # two different materials fight: the colours flicker
    same = 0        # one material on both: whichever wins looks alike, so it is only reported
    samples = []

    def name_of(index):
        slot = int(tri_surface[index])
        return slot_names[slot] if slot < len(slot_names) else "?"

    for members in buckets.values():
        if len(members) < 2:
            continue
        members.sort(key=lambda i: offsets[i])
        for position, first in enumerate(members):
            for second in members[position + 1:]:
                if offsets[second] - offsets[first] > ZFIGHT_PLANE_TOL:
                    break
                if np.dot(tri_normals[first], tri_normals[second]) < 0.999:
                    continue
                u, v = plane_basis(tri_normals[first])
                a = [(float(np.dot(p, u)), float(np.dot(p, v))) for p in tri_world[first]]
                b = [(float(np.dot(p, u)), float(np.dot(p, v))) for p in tri_world[second]]
                if not tri_overlap_2d(a, b):
                    continue
                if name_of(first) == name_of(second):
                    same += 1
                    continue
                found += 1
                if len(samples) < 3:
                    samples.append({
                        "tris": [int(first), int(second)],
                        "gap_mm": round(float(abs(offsets[second] - offsets[first])) * 1000.0, 3),
                        "materials": [name_of(first), name_of(second)],
                    })
    return found, same, samples


def uv_coverage(uv_tris, size=256):
    """Rasterise UV triangles; return (union_area, summed_area) as fractions of the 0..1 square."""
    grid = np.zeros((size, size), dtype=np.uint16)
    summed = 0.0
    for tri in uv_tris:
        (x0, y0), (x1, y1), (x2, y2) = tri
        area = abs((x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)) / 2.0
        summed += area
        min_x = max(int(math.floor(min(x0, x1, x2) * size)), 0)
        max_x = min(int(math.ceil(max(x0, x1, x2) * size)), size - 1)
        min_y = max(int(math.floor(min(y0, y1, y2) * size)), 0)
        max_y = min(int(math.ceil(max(y0, y1, y2) * size)), size - 1)
        if max_x < min_x or max_y < min_y:
            continue
        xs = (np.arange(min_x, max_x + 1) + 0.5) / size
        ys = (np.arange(min_y, max_y + 1) + 0.5) / size
        gx, gy = np.meshgrid(xs, ys)
        denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(denom) < 1e-14:
            continue
        w0 = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / denom
        w1 = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / denom
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        grid[min_y:max_y + 1, min_x:max_x + 1] += inside.astype(np.uint16)
    union = float(np.count_nonzero(grid)) / (size * size)
    overlap_cells = float(np.count_nonzero(grid > 1)) / (size * size)
    return union, summed, overlap_cells


def audit_model(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    lower = path.lower()
    if lower.endswith((".glb", ".gltf")):
        bpy.ops.import_scene.gltf(filepath=path)
    elif lower.endswith(".obj"):
        bpy.ops.wm.obj_import(filepath=path)
    else:
        return {"error": "unsupported extension"}

    scene = bpy.context.scene
    objects = list(scene.objects)
    meshes = [o for o in objects if o.type == "MESH"]
    armatures = [o for o in objects if o.type == "ARMATURE"]
    depsgraph = bpy.context.evaluated_depsgraph_get()

    info = {
        "objects": len(objects),
        "mesh_objects": len(meshes),
        "armatures": len(armatures),
        "actions": len(bpy.data.actions),
        "empties": sum(1 for o in objects if o.type == "EMPTY"),
        "cameras_lights": sum(1 for o in objects if o.type in ("CAMERA", "LIGHT")),
        "max_hierarchy_depth": 0,
        "unapplied_scale_objects": 0,
        "negative_scale_objects": 0,
    }
    for obj in objects:
        depth, parent = 0, obj.parent
        while parent is not None:
            depth += 1
            parent = parent.parent
        info["max_hierarchy_depth"] = max(info["max_hierarchy_depth"], depth)
        if any(abs(s - 1.0) > 1e-4 for s in obj.scale):
            info["unapplied_scale_objects"] += 1
        if any(s < 0 for s in obj.scale):
            info["negative_scale_objects"] += 1

    verts_total = tris_total = ngons_total = 0
    surfaces = set()
    issues = []
    all_pts = []
    degenerate = loose_verts = loose_edges = boundary_edges = nonmanifold_edges = 0
    dup_verts = 0
    inverted_closed = 0
    no_uv_meshes = []
    uv_out_of_range_tris = 0
    uv_zero_area_tris = 0
    uv_union = uv_sum = uv_overlap = 0.0
    uv_tris_checked = 0
    color_attrs = {}
    nan_found = False
    zfight_total = 0
    zfight_same = 0
    zfight_samples = []
    density_values = []

    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            mesh.calc_loop_triangles()
            verts_total += len(mesh.vertices)
            tris = mesh.loop_triangles
            tri_count = len(tris)
            tris_total += tri_count
            ngons_total += sum(1 for p in mesh.polygons if len(p.vertices) > 4)

            slots = [m.name if m else "(none)" for m in mesh.materials] or ["(none)"]
            used = set(t.material_index for t in tris)
            for index in used:
                surfaces.add((obj.name, slots[index] if index < len(slots) else "(none)"))

            if len(mesh.vertices) == 0 or tri_count == 0:
                issues.append("empty mesh object %s" % obj.name)
                continue

            co = np.empty(len(mesh.vertices) * 3, dtype=np.float64)
            mesh.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)
            if not np.isfinite(co).all():
                nan_found = True
            matrix = np.array(obj.matrix_world)
            world = co @ matrix[:3, :3].T + matrix[:3, 3]
            all_pts.append(world)

            tri_verts = np.empty(tri_count * 3, dtype=np.int32)
            tris.foreach_get("vertices", tri_verts)
            tri_verts = tri_verts.reshape(-1, 3)
            tri_world = world[tri_verts]
            cross = np.cross(tri_world[:, 1] - tri_world[:, 0], tri_world[:, 2] - tri_world[:, 0])
            areas = np.linalg.norm(cross, axis=1) / 2.0
            degenerate += int(np.count_nonzero(areas < MIN_TRI_AREA))
            normals = np.zeros_like(cross)
            ok = areas > MIN_TRI_AREA
            normals[ok] = cross[ok] / (2.0 * areas[ok])[:, None]

            tri_mat = np.empty(tri_count, dtype=np.int32)
            tris.foreach_get("material_index", tri_mat)

            # Duplicate vertices (merge-by-distance candidates).
            rounded = np.round(world / 1e-5).astype(np.int64)
            dup_verts += len(rounded) - len(np.unique(rounded, axis=0))

            # Topology through bmesh.
            bm = bmesh.new()
            bm.from_mesh(mesh)
            loose_verts += sum(1 for v in bm.verts if not v.link_edges)
            loose_edges += sum(1 for e in bm.edges if not e.link_faces)
            boundary_edges += sum(1 for e in bm.edges if len(e.link_faces) == 1)
            nonmanifold_edges += sum(1 for e in bm.edges if len(e.link_faces) > 2)
            closed = bool(bm.edges) and all(len(e.link_faces) == 2 for e in bm.edges)
            bm.free()
            if closed:
                signed = float(np.einsum("ij,ij->", tri_world[:, 0], np.cross(tri_world[:, 1], tri_world[:, 2])) / 6.0)
                if signed < 0:
                    inverted_closed += 1

            # Colour attributes.
            for attr in mesh.color_attributes:
                data = np.empty(len(attr.data) * 4, dtype=np.float32)
                attr.data.foreach_get("color", data)
                data = data.reshape(-1, 4)
                if not np.isfinite(data).all():
                    nan_found = True
                color_attrs[attr.name] = {
                    "domain": attr.domain,
                    "min": [round(float(x), 3) for x in data.min(axis=0)],
                    "max": [round(float(x), 3) for x in data.max(axis=0)],
                    "mean": [round(float(x), 3) for x in data.mean(axis=0)],
                }

            # UV health.
            if not mesh.uv_layers:
                no_uv_meshes.append(obj.name)
            else:
                layer = mesh.uv_layers[0]
                uv = np.empty(len(mesh.loops) * 2, dtype=np.float64)
                layer.uv.foreach_get("vector", uv)
                uv = uv.reshape(-1, 2)
                tri_loops = np.empty(tri_count * 3, dtype=np.int32)
                tris.foreach_get("loops", tri_loops)
                tri_uv = uv[tri_loops.reshape(-1, 3)]
                inside = (tri_uv >= -1e-4).all(axis=(1, 2)) & (tri_uv <= 1.0 + 1e-4).all(axis=(1, 2))
                uv_out_of_range_tris += int(np.count_nonzero(~inside))
                uv_area = np.abs(
                    (tri_uv[:, 1, 0] - tri_uv[:, 0, 0]) * (tri_uv[:, 2, 1] - tri_uv[:, 0, 1])
                    - (tri_uv[:, 2, 0] - tri_uv[:, 0, 0]) * (tri_uv[:, 1, 1] - tri_uv[:, 0, 1])
                ) / 2.0
                uv_zero_area_tris += int(np.count_nonzero((uv_area < 1e-10) & ok))
                union, summed, overlap = uv_coverage(tri_uv)
                uv_union += union
                uv_sum += summed
                uv_overlap += overlap
                uv_tris_checked += tri_count
                valid = ok & (uv_area > 1e-10)
                if valid.any():
                    density_values.extend(np.sqrt(uv_area[valid] / areas[valid]).tolist())

            # Z-fighting candidates (cap work on very dense meshes).
            if tri_count <= 25000:
                found, same, samples = zfight_pairs(tri_world[ok], normals[ok], tri_mat[ok], slots)
                zfight_total += found
                zfight_same += same
                zfight_samples.extend(samples)
        finally:
            evaluated.to_mesh_clear()

    info.update({
        "verts": verts_total,
        "tris": tris_total,
        "ngons": ngons_total,
        "surfaces": len(surfaces),
        "material_names": sorted({s[1] for s in surfaces}),
        "degenerate_tris": degenerate,
        "duplicate_verts": dup_verts,
        "loose_verts": loose_verts,
        "loose_edges": loose_edges,
        "boundary_edges": boundary_edges,
        "nonmanifold_edges": nonmanifold_edges,
        "inverted_closed_meshes": inverted_closed,
        "meshes_without_uv": no_uv_meshes,
        "uv_out_of_range_tris": uv_out_of_range_tris,
        "uv_zero_area_tris": uv_zero_area_tris,
        "uv_union_fraction": round(uv_union, 4),
        "uv_overlap_fraction": round(uv_overlap, 4),
        "uv_sum_over_union": round(uv_sum / uv_union, 3) if uv_union > 0 else None,
        "color_attributes": color_attrs,
        "non_finite_values": nan_found,
        "zfight_pairs": zfight_total,
        "zfight_same_material_pairs": zfight_same,
        "zfight_samples": zfight_samples[:3],
    })

    if density_values:
        values = np.array(density_values)
        info["uv_density_per_metre"] = {
            "p05": round(float(np.percentile(values, 5)), 3),
            "median": round(float(np.median(values)), 3),
            "p95": round(float(np.percentile(values, 95)), 3),
        }

    if all_pts:
        pts = np.vstack(all_pts)
        lo, hi = pts.min(axis=0), pts.max(axis=0)
        # Blender (x, y, z) -> glTF (x, z, -y): width, height, depth.
        info["size_gltf"] = [round(float(hi[0] - lo[0]), 3), round(float(hi[2] - lo[2]), 3), round(float(hi[1] - lo[1]), 3)]
        info["origin_offset_from_base_centre"] = [
            round(float((hi[0] + lo[0]) / 2), 3),
            round(float(lo[2]), 3),
            round(float(-(hi[1] + lo[1]) / 2), 3),
        ]

    images = []
    vram_uncompressed = 0
    for image in bpy.data.images:
        if image.name in ("Render Result", "Viewer Node"):
            continue
        width, height = image.size
        images.append({
            "name": image.name,
            "size": [width, height],
            "packed": image.packed_file is not None,
            "colorspace": image.colorspace_settings.name,
            "alpha": image.alpha_mode,
        })
        vram_uncompressed += width * height * 4 * 4 // 3
    info["images"] = images
    info["estimated_uncompressed_vram_kb"] = vram_uncompressed // 1024

    materials = []
    for material in bpy.data.materials:
        entry = {"name": material.name, "textured": False, "double_sided": not material.use_backface_culling}
        if material.use_nodes and material.node_tree:
            entry["textured"] = any(n.type == "TEX_IMAGE" for n in material.node_tree.nodes)
            entry["blend_method"] = getattr(material, "surface_render_method", "?")
        materials.append(entry)
    info["materials"] = materials

    # Verdicts against the phone budgets.
    if tris_total > TRIS_BUDGET:
        issues.append("%d triangles exceeds the %d budget" % (tris_total, TRIS_BUDGET))
    if len(surfaces) > SURFACES_BUDGET:
        issues.append("%d draw surfaces exceeds %d" % (len(surfaces), SURFACES_BUDGET))
    for image in images:
        if max(image["size"]) > TEXTURE_BUDGET_PX:
            issues.append("texture %s is %dx%d" % (image["name"], image["size"][0], image["size"][1]))
    if degenerate:
        issues.append("%d degenerate triangles" % degenerate)
    # (Duplicate positions are not a defect in a glTF: every hard edge and UV seam needs its own vertex, so
    # "duplicate_verts" is reported as a number only and merging them would break shading and texture seams.)
    if loose_verts or loose_edges:
        issues.append("loose geometry: %d verts, %d edges" % (loose_verts, loose_edges))
    if nonmanifold_edges:
        issues.append("%d non-manifold edges" % nonmanifold_edges)
    if inverted_closed:
        issues.append("%d closed meshes have inverted normals" % inverted_closed)
    if no_uv_meshes:
        issues.append("meshes without UVs: %s" % ", ".join(no_uv_meshes))
    if uv_out_of_range_tris:
        issues.append("%d triangles with UVs outside 0..1" % uv_out_of_range_tris)
    if uv_overlap > 0.002:
        issues.append("UV islands overlap on %.1f%% of the texture" % (uv_overlap * 100))
    if uv_zero_area_tris:
        issues.append("%d triangles with zero UV area" % uv_zero_area_tris)
    if zfight_total:
        issues.append("%d z-fighting triangle pairs of different materials (coplanar within %.1f mm)" % (zfight_total, ZFIGHT_PLANE_TOL * 1000))
    if nan_found:
        issues.append("non-finite values in geometry or colours")
    if armatures:
        issues.append("%d armature(s) in a static prop" % len(armatures))
    if info["negative_scale_objects"]:
        issues.append("%d objects with negative scale" % info["negative_scale_objects"])
    info["issues"] = issues
    return info


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out_path, files = argv[0], argv[1:]
    report = {}
    for path in files:
        name = path.replace("\\", "/").split("/")[-1]
        try:
            report[name] = audit_model(path)
        except Exception as error:  # keep auditing the rest
            report[name] = {"error": "%s: %s" % (type(error).__name__, error), "trace": traceback.format_exc()[-1200:]}
        print("audited", name, flush=True)
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1)
    print("AUDIT DONE", len(report), flush=True)


main()
