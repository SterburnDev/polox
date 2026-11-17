# Blender (background): models Polox's own furniture pieces (the ones no Kenney kit has).
#   blender -b --factory-startup --python tools/blender_scripts/model_props.py -- <out_dir> [model ...]
#
# Same conventions as build_furniture.py's output, so texture_furniture.py and licensed_props.gd treat
# them alike: real metres, one mesh with one slot per material, facing south (Godot +z, Blender -y) with
# its back to the north, the origin on the floor under the footprint's centre, Kenney-style material
# names (texture_furniture.py reads what each is made of from furniture_surfaces.json), the material the
# player's paint tints called "paint" in the catalogue's default colour, and glow as emission.
#   bean_bag   a slouchy bean bag with a raised back and a seat dent (1x1)
#   fish_tank  a cabinet with a lit tank: sand, weed, three fish and bubbles (1x1)
#   coat_rack  a standing rack with a felt hat, a striped scarf and a canvas tote (1x1)
#   bar_stool  a cushioned stool on splayed legs with a foot ring (1x1)
#   wall_clock a round clock hung on the wall behind its cell at 1.6 m, showing ten past ten (1x1, flat)
#   piano      an upright piano with 52 white and 36 black keys and three pedals (2x1)
import bmesh, bpy, math, os, sys
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out_dir = argv[0]
only = set(argv[1:])


def lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


class Model:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []        # [name, hex, emission strength]
        self.smooth = set()

    def mat(self, name, hex_colour, glow=0.0):
        for i, m in enumerate(self.mats):
            if m[0] == name:
                return i
        self.mats.append([name, hex_colour, glow])
        return len(self.mats) - 1

    def _tag(self, verts, mat, smooth=False):
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = mat
            f.smooth = smooth
        return verts

    def box(self, size, at, mat, rot=None):
        m = Matrix.Translation(Vector(at)) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1.0))
        return self._tag(bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"], mat)

    def cyl(self, r1, depth, at, mat, r2=None, segments=16, rot=None, smooth=False):
        m = Matrix.Translation(Vector(at)) @ (rot or Matrix.Identity(4))
        v = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r1,
                                  radius2=r1 if r2 is None else r2, depth=depth, matrix=m)["verts"]
        return self._tag(v, mat, smooth)

    def ball(self, r, at, mat, scale=(1, 1, 1), u=12, v=8, rot=None, smooth=True):
        m = Matrix.Translation(Vector(at)) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal((*scale, 1.0))
        verts = bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=r, matrix=m)["verts"]
        return self._tag(verts, mat, smooth)

    def torus(self, major, minor, at, mat, seg=24, ring=8):
        vs = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            for j in range(ring):
                b = 2 * math.pi * j / ring
                rr = major + minor * math.cos(b)
                vs.append(self.bm.verts.new((at[0] + rr * math.cos(a), at[1] + rr * math.sin(a), at[2] + minor * math.sin(b))))
        for i in range(seg):
            for j in range(ring):
                a, b = i * ring + j, i * ring + (j + 1) % ring
                c, d = ((i + 1) % seg) * ring + (j + 1) % ring, ((i + 1) % seg) * ring + j
                f = self.bm.faces.new((vs[a], vs[d], vs[c], vs[b]))
                f.material_index = mat
                f.smooth = True
        return vs

    def rod(self, a, b, r, mat, segments=8):
        """A cylinder from point a to point b."""
        a, b = Vector(a), Vector(b)
        d = b - a
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        return self.cyl(r, d.length, (a + b) / 2, mat, segments=segments, rot=rot)

    def build(self):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for name, hex_colour, glow in self.mats:
            m = bpy.data.materials.new(name)
            m.use_nodes = True
            b = m.node_tree.nodes["Principled BSDF"]
            b.inputs["Base Color"].default_value = (*lin(hex_colour), 1.0)
            b.inputs["Roughness"].default_value = 1.0
            if glow > 0.0:
                b.inputs["Emission Color"].default_value = (*lin(hex_colour), 1.0)
                b.inputs["Emission Strength"].default_value = glow
            me.materials.append(m)
        obj = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")


def rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ---------- the pieces ----------
def bean_bag():
    m = Model("bean_bag")
    paint = m.mat("paint", "#c7684f")
    verts = m.ball(0.43, (0, 0, 0), paint, u=28, v=16)
    for v in verts:
        x, y, z = v.co
        z *= 0.62
        if z > -0.05:
            up = smoothstep(-0.05, 0.25, z)
            z += 0.17 * smoothstep(-0.12, 0.38, y) * up                                      # the raised back
            z -= 0.13 * math.exp(-((x / 0.21) ** 2 + ((y + 0.06) / 0.2) ** 2)) * up       # where you sit
        y -= 0.04 * smoothstep(0.1, -0.4, y) * smoothstep(-0.25, 0.05, z)                   # slumps forward
        z = max(z, -0.2)                                                                    # rests flat
        v.co = (x * 0.98, y * 0.96, z + 0.2)
    return m


def fish_tank():
    m = Model("fish_tank")
    paint = m.mat("paint", "#8b6a4a")
    dark = m.mat("woodDark", "#5f4632")
    frame = m.mat("metalDark", "#2b3036")
    metal = m.mat("metal", "#bcc4c8")
    water = m.mat("water", "#4fa9c4", glow=0.45)
    sand = m.mat("sand", "#d8c08a")
    weed = m.mat("plant", "#3f9a5a")
    orange = m.mat("colorOrange", "#f08a3c")
    yellow = m.mat("colorYellow", "#f2c84a")
    white = m.mat("colorWhite", "#eef6f8")
    m.box((0.84, 0.40, 0.60), (0, 0, 0.30), paint)                       # cabinet
    m.box((0.86, 0.42, 0.03), (0, 0, 0.615), dark)                        # its top
    m.box((0.004, 0.006, 0.50), (0, -0.2, 0.31), dark)                    # between the doors
    for x in (-0.05, 0.05):
        m.cyl(0.012, 0.02, (x, -0.205, 0.42), metal, segments=10, rot=rot_x(90))
    m.box((0.82, 0.38, 0.025), (0, 0, 0.6425), frame)                    # tank base
    m.box((0.78, 0.34, 0.40), (0, 0, 0.855), water)                      # water (z 0.655-1.055)
    m.box((0.82, 0.38, 0.04), (0, 0, 1.075), frame)                      # lid with its lamp
    for x in (-0.4, 0.4):
        for y in (-0.18, 0.18):
            m.box((0.02, 0.02, 0.40), (x, y, 0.855), frame)                # glass edges
    m.box((0.78, 0.344, 0.05), (0, 0, 0.68), sand)                       # sand, a hair in front of the water
    fy = -0.175                                                          # just inside the front glass (y -0.19)
    flat = Matrix.Diagonal((1.0, 0.35, 1.0, 1.0))
    for x, h, lean in ((-0.3, 0.2, 8), (-0.24, 0.14, -10), (0.27, 0.24, -6), (0.32, 0.16, 12), (0.06, 0.1, 4)):
        m.cyl(0.022, h, (x, fy, 0.705 + h / 2), weed, r2=0.004, segments=6, rot=flat @ rot_y(lean))
    for x, z, col, face in ((-0.08, 0.93, orange, 1), (0.14, 0.82, orange, -1), (-0.16, 0.78, yellow, -1)):
        m.ball(0.035, (x, fy, z), col, scale=(1.6, 0.25, 1.0), u=10, v=6)
        m.cyl(0.03, 0.04, (x - face * 0.07, fy, z), col, r2=0.0, segments=4, rot=flat @ rot_y(90 * face) @ rot_z(45))
        m.ball(0.006, (x + face * 0.03, fy - 0.008, z + 0.008), frame, u=6, v=4)
    for i, z in enumerate((0.8, 0.88, 0.95, 1.01)):
        m.ball(0.006 + 0.002 * i, (0.2 + 0.01 * (i % 2), fy, z), white, u=8, v=5)
    return m


def coat_rack():
    m = Model("coat_rack")
    paint = m.mat("paint", "#8b6a4a")
    felt = m.mat("carpetDarker", "#5a4a6a")
    scarf = m.mat("carpet", "#d65a4a")
    stripe = m.mat("carpetWhite", "#efe6d4")
    canvas = m.mat("canvas", "#d9c9a3")
    m.cyl(0.2, 0.035, (0, 0, 0.0175), paint, r2=0.17, segments=20)       # base
    m.cyl(0.023, 1.7, (0, 0, 0.885), paint, segments=12)                 # pole
    m.ball(0.035, (0, 0, 1.75), paint, u=10, v=6)                        # knob
    hooks = {}
    for i in range(8):
        a = math.radians(45 * i + (22.5 if i % 2 else 0))
        z = 1.6 if i % 2 == 0 else 1.38
        base = Vector((0.02 * math.cos(a), 0.02 * math.sin(a), z))
        tip = Vector((0.15 * math.cos(a), 0.15 * math.sin(a), z + 0.1))
        m.rod(base, tip, 0.01, paint)
        m.ball(0.016, tip, paint, u=8, v=5)
        hooks[i] = (a, tip)
    # A felt hat on the knob.
    m.cyl(0.13, 0.012, (0, 0, 1.79), felt, segments=20)
    m.cyl(0.08, 0.1, (0, 0, 1.845), felt, r2=0.07, segments=20)
    m.cyl(0.081, 0.02, (0, 0, 1.815), stripe, r2=0.078, segments=20)
    # A striped scarf over the front-right hook (hook 7: 315 degrees + 22.5, the lower ring).
    a, tip = hooks[7]
    out = Vector((math.cos(a), math.sin(a), 0))
    for k, (drop, side) in enumerate(((0.52, -0.025), (0.62, 0.03))):
        top = tip + out * 0.005 + Vector((0, 0, -0.01))
        cx = top + Vector((-out.y, out.x, 0)) * side
        m.box((0.07, 0.012, drop), (cx.x, cx.y, top.z - drop / 2), scarf, rot=rot_z(math.degrees(a) + 90))
        for s in range(3):
            z = top.z - drop + 0.05 + s * 0.04
            m.box((0.072, 0.014, 0.012), (cx.x, cx.y, z), stripe, rot=rot_z(math.degrees(a) + 90))
    m.box((0.075, 0.03, 0.03), (tip.x, tip.y, tip.z + 0.005), scarf, rot=rot_z(math.degrees(a) + 90))
    # A canvas tote on the back-left hook (hook 3: 157.5 degrees, the lower ring).
    a, tip = hooks[3]
    out = Vector((math.cos(a), math.sin(a), 0))
    centre = tip + out * 0.02 + Vector((0, 0, -0.26))
    turn = rot_z(math.degrees(a) + 90)
    m.box((0.26, 0.06, 0.28), centre, canvas, rot=turn)
    for side in (-0.07, 0.07):
        p = centre + Vector((-out.y, out.x, 0)) * side
        m.rod(p + Vector((0, 0, 0.14)), tip + Vector((0, 0, -0.01)), 0.006, canvas, segments=6)
    return m


def bar_stool():
    m = Model("bar_stool")
    paint = m.mat("paint", "#3f6f8f")
    wood = m.mat("wood", "#c89466")
    metal = m.mat("metalDark", "#3a3f46")
    m.cyl(0.19, 0.07, (0, 0, 0.735), paint, r2=0.175, segments=24, smooth=True)   # cushion
    m.cyl(0.2, 0.03, (0, 0, 0.685), wood, segments=24)                            # seat board
    for i in range(4):
        a = math.radians(45 + 90 * i)
        m.rod((0.12 * math.cos(a), 0.12 * math.sin(a), 0.67), (0.205 * math.cos(a), 0.205 * math.sin(a), 0.003), 0.014, metal)
    m.torus(0.172, 0.011, (0, 0, 0.27), metal)
    return m


def wall_clock():
    m = Model("wall_clock")
    paint = m.mat("paint", "#7a5a3c")
    face = m.mat("clockFace", "#f4ecd8")
    hand = m.mat("metalDark", "#2b2b30")
    y, z = 0.445, 1.6                                                     # hung on the wall behind the cell
    m.cyl(0.18, 0.05, (0, y, z), paint, segments=32, rot=rot_x(90))
    m.cyl(0.155, 0.004, (0, y - 0.027, z), face, segments=32, rot=rot_x(90))
    for length, width, clock_angle, dy in ((0.085, 0.014, -55.0, 0.031), (0.125, 0.009, 60.0, 0.034)):   # 10:10
        a = math.radians(clock_angle)
        cx, cz = math.sin(a) * length / 2, math.cos(a) * length / 2
        m.box((width, 0.003, length), (cx, y - dy, z + cz), hand, rot=rot_y(clock_angle))
    m.cyl(0.012, 0.006, (0, y - 0.036, z), hand, segments=12, rot=rot_x(90))
    return m


def piano():
    m = Model("piano")
    paint = m.mat("paint", "#2a2028")
    keys = m.mat("keys", "#f4f1ea")
    black = m.mat("keysBlack", "#1b1a1e")
    brass = m.mat("brass", "#c9a45c")
    felt = m.mat("carpet", "#8e2f3a")
    w = 1.5
    m.box((w, 0.34, 1.22), (0, 0.13, 0.61), paint)                        # case
    m.box((w + 0.02, 0.37, 0.03), (0, 0.125, 1.235), paint)               # lid
    for x in (-w / 2 + 0.025, w / 2 - 0.025):
        m.box((0.05, 0.6, 0.12), (x, -0.16, 0.75), paint)                 # cheeks either side of the keys
        m.box((0.06, 0.06, 0.69), (x, -0.42, 0.345), paint)               # front legs
    m.box((w - 0.1, 0.3, 0.06), (0, -0.16, 0.69), paint)                  # key bed
    m.box((w - 0.1, 0.26, 0.022), (0, -0.17, 0.731), keys)                # white keys (lines in the texture)
    white_w = (w - 0.1) / 52.0
    left = -(w - 0.1) / 2.0
    for i in range(51):                                                    # a black key after C, D, F, G, A
        if (i + 5) % 7 in (2, 6):                                          # (the keyboard starts on A)
            continue
        x = left + (i + 1) * white_w
        m.box((white_w * 0.55, 0.15, 0.018), (x, -0.105, 0.751), black)
    m.box((w - 0.1, 0.012, 0.012), (0, -0.30, 0.741), felt)               # key slip felt
    m.box((w - 0.1, 0.04, 0.14), (0, -0.01, 0.82), paint)                 # fallboard, open
    m.box((0.5, 0.02, 0.2), (0, 0.0, 0.99), paint, rot=rot_x(-12))        # music rest
    for x in (-0.07, 0.0, 0.07):
        m.box((0.03, 0.09, 0.012), (x, -0.31, 0.04), brass)
    m.box((0.3, 0.06, 0.08), (0, -0.28, 0.04), paint)                     # pedal block
    bmesh.ops.translate(m.bm, verts=m.bm.verts[:], vec=(0.0, 0.1, 0.0))   # back nearer the wall
    return m


MODELS = {"bean_bag": bean_bag, "fish_tank": fish_tank, "coat_rack": coat_rack, "bar_stool": bar_stool,
          "wall_clock": wall_clock, "piano": piano}

os.makedirs(out_dir, exist_ok=True)
for name, make in MODELS.items():
    if only and name not in only:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obj = make().build()
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    out = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
        export_apply=True, export_cameras=False, export_lights=False, export_animations=False, export_materials="EXPORT")
    obj.data.calc_loop_triangles()
    print("modelled", name, "size", [round(hi.x - lo.x, 3), round(hi.y - lo.y, 3), round(hi.z - lo.z, 3)],
          "x", [round(lo.x, 3), round(hi.x, 3)], "y", [round(lo.y, 3), round(hi.y, 3)], "z", [round(lo.z, 3), round(hi.z, 3)],
          "tris", len(obj.data.loop_triangles), "mats", [m.name for m in obj.data.materials])
