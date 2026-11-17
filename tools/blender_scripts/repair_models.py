# Blender (background): repairs what audit_models.py reports and writes the repaired GLBs.
#
#   blender -b --factory-startup --python repair_models.py -- <out_dir> <report.json> <model.glb>...
#
# What it does, per model (the source files are never touched; repaired copies go to <out_dir>):
#   1. Deletes zero-area triangles (they draw nothing; deleting them changes no pixel).
#   2. Finds near-coplanar, same-facing, overlapping triangle pairs of DIFFERENT materials (they z-fight in a
#      24-bit depth buffer: two colours flicker) and lifts the smaller one of each pair out along its normal by
#      LIFT metres, so the depth test has a real gap. The lifted face is the "decal" on the bigger one (a
#      glass pane on a front panel, a keyboard on a piano's lid). The lift repeats until a fresh search finds
#      nothing left, because a lifted face can land on a plane another face already uses. Same-material
#      overlaps are left alone: two faces of one material look the same whichever wins.
#   3. Exports with the same glTF settings the furniture pipeline uses (texture_furniture.py).
# The JSON report lists, per model, what changed, so it can be compared with a second audit.
import json
import math
import os
import sys
import traceback

import bmesh
import bpy
import numpy as np
from mathutils import Vector

LIFT = 0.001              # metres of gap per lift
PLANE_TOL = 0.0005        # coplanar closer than this = z-fighting candidates (matches audit_models.py)
NORMAL_TOL = 0.01
MIN_TRI_AREA = 1e-9
MAX_ROUNDS = 6
MAX_TRIS = 25000          # beyond this the pair search is skipped (it is quadratic inside a plane bucket)


def tri_overlap_2d(a, b, eps=1e-7):
    """Separating-axis test for two 2D triangles: True when their interiors overlap by more than eps."""
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
    helper = np.array([1.0, 0.0, 0.0]) if abs(normal[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    u = np.cross(normal, helper)
    u /= np.linalg.norm(u)
    return u, np.cross(normal, u)


def find_pairs(world, normals, material_of):
    """(first, second) index pairs of overlapping coplanar same-facing triangles of different materials."""
    offsets = np.einsum("ij,ij->i", normals, world[:, 0, :])
    key = np.round(normals / NORMAL_TOL).astype(np.int64)
    buckets = {}
    for index in range(len(world)):
        buckets.setdefault((key[index, 0], key[index, 1], key[index, 2]), []).append(index)
    pairs = []
    for members in buckets.values():
        if len(members) < 2:
            continue
        members.sort(key=lambda i: offsets[i])
        for position, first in enumerate(members):
            for second in members[position + 1:]:
                if offsets[second] - offsets[first] > PLANE_TOL:
                    break
                if material_of[first] == material_of[second]:
                    continue
                if np.dot(normals[first], normals[second]) < 0.999:
                    continue
                u, v = plane_basis(normals[first])
                a = [(float(np.dot(p, u)), float(np.dot(p, v))) for p in world[first]]
                b = [(float(np.dot(p, u)), float(np.dot(p, v))) for p in world[second]]
                if tri_overlap_2d(a, b):
                    pairs.append((first, second))
    return pairs


def lifted_set(pairs, areas):
    """The smaller triangle of each overlapping pair (ties: the later one) is the one that gets lifted."""
    lifted = set()
    for first, second in pairs:
        small = first if (areas[first], -first) < (areas[second], -second) else second
        lifted.add(small)
    return lifted


def snapshot(bm, rotation, translation):
    """The faces of the (triangulated) mesh in world space: faces, vertex positions, unit normals, areas."""
    bm.faces.ensure_lookup_table()
    faces = list(bm.faces)
    world = np.array([[rotation @ np.array(v.co) + translation for v in f.verts] for f in faces])
    cross = np.cross(world[:, 1] - world[:, 0], world[:, 2] - world[:, 0])
    areas = np.linalg.norm(cross, axis=1) / 2.0
    normals = cross / (2.0 * np.maximum(areas, 1e-18))[:, None]
    return faces, world, normals, areas


def repair_object(obj):
    """Repairs one mesh object in place; returns what changed."""
    mesh = obj.data
    matrix = np.array(obj.matrix_world)
    rotation, translation = matrix[:3, :3], matrix[:3, 3]
    inverse = np.linalg.inv(rotation)
    material_names = [m.name if m else "" for m in mesh.materials]

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()

    # Triangles only: quads and ngons cannot be compared plane to plane safely.
    triangulated = [f for f in bm.faces if len(f.verts) > 3]
    if triangulated:
        bmesh.ops.triangulate(bm, faces=triangulated)

    # 1. Zero-area triangles, measured in world space exactly the way the audit measures them.
    faces, world, normals, areas = snapshot(bm, rotation, translation) if len(bm.faces) else ([], None, None, None)
    dead = [faces[i] for i in np.nonzero(areas < MIN_TRI_AREA)[0]] if faces else []
    removed = len(dead)
    if dead:
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        bm.faces.ensure_lookup_table()

    # 2. Coplanar overlaps. (Adding a custom-data layer re-allocates the face blocks and invalidates every
    # BMFace already held, so the layer is made before any faces are collected again.)
    lift_key = bm.faces.layers.int.new("polox_lift")

    first_pairs = None
    total_lifted = 0
    rounds = 0
    for rounds in range(1, MAX_ROUNDS + 1):
        faces, world, normals, areas = snapshot(bm, rotation, translation)
        if not faces or len(faces) > MAX_TRIS:
            break
        material_of = [material_names[f.material_index] if f.material_index < len(material_names) else "" for f in faces]
        pairs = find_pairs(world, normals, material_of)
        if first_pairs is None:
            first_pairs = len(pairs)
        if not pairs:
            rounds -= 1
            break
        lifted = lifted_set(pairs, areas)
        for face in faces:
            face[lift_key] = 0
        for index in lifted:
            faces[index][lift_key] = 1
        # Cut the lifted faces loose from their neighbours first (a vertex they share with the base would drag
        # it along); they keep their connections to each other, so a decal stays one piece. The marker rides
        # on a face attribute because a split makes new faces.
        bmesh.ops.split(bm, geom=[faces[i] for i in lifted], use_only_faces=True)
        bm.faces.ensure_lookup_table()
        bm.verts.index_update()
        bm.normal_update()
        moved = set()
        for face in bm.faces:
            if face[lift_key] != 1:
                continue
            world_normal = np.array(rotation @ np.array(face.normal))
            length = np.linalg.norm(world_normal)
            if length < 1e-12:
                continue
            push = Vector(inverse @ (world_normal / length * LIFT))
            for vert in face.verts:
                if vert.index not in moved:     # a vertex shared by two lifted faces moves once
                    moved.add(vert.index)
                    vert.co += push
            total_lifted += 1
    bm.faces.layers.int.remove(lift_key)

    bm.normal_update()
    bm.to_mesh(mesh)
    mesh.update()
    bm.free()
    return {"removed_degenerate": removed, "pairs_found": first_pairs or 0, "lifted_triangles": total_lifted, "rounds": rounds}


def repair_model(path, out_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    changes = {}
    for obj in meshes:
        bpy.context.view_layer.objects.active = obj
        changes[obj.name] = repair_object(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    out_path = os.path.join(out_dir, os.path.basename(path))
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False, export_animations=False,
                              export_materials="EXPORT", export_image_format="AUTO", export_texcoords=True, export_normals=True)
    return {"objects": changes, "glb_bytes": os.path.getsize(out_path), "source_bytes": os.path.getsize(path)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out_dir, report_path, files = argv[0], argv[1], argv[2:]
    os.makedirs(out_dir, exist_ok=True)
    report = {}
    for path in files:
        name = os.path.basename(path)
        try:
            report[name] = repair_model(path, out_dir)
        except Exception as error:      # keep going: one bad model must not stop the batch
            report[name] = {"error": "%s: %s" % (type(error).__name__, error), "trace": traceback.format_exc()[-1500:]}
        print("repaired", name, report[name].get("objects", report[name].get("error")), flush=True)
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1)
    print("REPAIR DONE", len(report), flush=True)


main()
