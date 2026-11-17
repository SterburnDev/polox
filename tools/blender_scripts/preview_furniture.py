# Blender (background): a contact sheet of furniture models, for checking textures by eye.
#   blender -b --factory-startup --python tools/blender_scripts/preview_furniture.py -- <out.png> <tile_px> <model.glb>...
# Each model sits on a pale floor, seen from the front-left and a little above (the way the game's camera
# looks into a room), lit by a warm key light and a soft sky. Cycles, 48 samples, denoised.
import bpy, math, os, sys
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out_path, tile, files = os.path.abspath(argv[0]), int(argv[1]), [os.path.abspath(p) for p in argv[2:]]
tiles = []
for path in files:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = tile
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in scene.objects if o.type == "MESH"]
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 0.3)
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    floor = bpy.context.active_object
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.62, 0.58, 0.52, 1)
    floor.data.materials.append(fm)
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.7, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(-35)))
    sun = bpy.context.active_object
    sun.data.energy = 3.2
    sun.data.color = (1.0, 0.93, 0.82)
    sun.data.angle = math.radians(8)
    # Godot's -z (the model's back) is Blender's +y, so the camera stands at -y (in front).
    direction = Vector((-0.55, -1.0, 0.75)).normalized()
    bpy.ops.object.camera_add(location=centre + direction * radius * 3.4)
    cam = bpy.context.active_object
    cam.data.lens = 50
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    shot = os.path.splitext(out_path)[0] + "_" + os.path.splitext(os.path.basename(path))[0] + ".png"
    scene.render.filepath = shot
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(shot)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(tile, tile, 4)
    tiles.append(px)
    os.remove(shot)
cols = min(4, len(tiles))
rows = (len(tiles) + cols - 1) // cols
sheet = np.ones((rows * tile, cols * tile, 4), dtype=np.float32)
for i, t in enumerate(tiles):
    r, c = divmod(i, cols)
    y0 = (rows - 1 - r) * tile   # Blender images start at the bottom row
    sheet[y0:y0 + tile, c * tile:(c + 1) * tile] = t
out = bpy.data.images.new("sheet", cols * tile, rows * tile, alpha=True)
out.pixels.foreach_set(sheet.ravel())
out.filepath_raw = out_path
out.file_format = "PNG"
out.save()
print("sheet", out_path, len(tiles))
