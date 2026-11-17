# Blender (background): gives Polox's furniture surface textures and baked soft shading.
#   blender -b --factory-startup --python tools/blender_scripts/texture_furniture.py -- <surfaces.json> <in_dir> <out_dir> <report.json> [model ...]
#
# Input: the plain models build_furniture.py / model_props.py make (one mesh, flat Kenney colours).
# For each model it lays out new UVs, bakes what the texture needs to know about every texel (where it is
# on the model, which way it faces, which material and which loose part it belongs to, which way that
# part's grain runs) plus ambient occlusion with a floor under the model (soft shadows in corners, under
# cushions and where it meets the floor), then paints the surfaces in numpy: wood grain, fabric, linen,
# brushed metal, enamel, ceramic, glass, screens, leaves, petals, lamp shades, woven rugs, books in many
# colours. One texture per model (512 or 1024 px by surface area), shared by its materials.
#
# The paint material (the one the player's colour tints, see licensed_props.gd) gets a grey texture
# (pattern and shading only) with the model's own colour as the glTF base colour factor, so Godot's
# albedo_color (the tint) times the texture keeps any colour the player picks. Every other material's
# colour is baked into the texture. Material names, slots and lamp glow stay as they were.
import bpy, bmesh, json, math, os, sys
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
surfaces_path, in_dir, out_dir, report_path = argv[:4]
only = set(argv[4:])
spec = json.load(open(surfaces_path))
os.makedirs(os.path.join(out_dir, "png"), exist_ok=True)

ROUGHNESS = {"wood": 0.72, "fabric": 0.95, "linen": 0.9, "metal": 0.42, "enamel": 0.32, "ceramic": 0.22,
             "glass": 0.08, "screen": 0.18, "leaf": 0.8, "petal": 0.75, "shade": 0.9, "rug": 1.0,
             "books": 0.8, "paper": 0.92, "plain": 0.6, "water": 0.1, "sand": 1.0, "keys": 0.35, "clockface": 0.5}
BOOK_COLOURS = ["#8e3b3b", "#2f4a7a", "#3d6b4a", "#c99a3c", "#2f7f86", "#6e4a7e", "#b08a62", "#3b3f47", "#d9c9a3"]
POS_SCALE = 0.25   # positions are baked as p * 0.25 + 0.5 (models fit in +-2 m)


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def hex_linear(h):
    h = h.lstrip("#")
    return srgb_to_linear([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# ---------- noise (value noise, fBm), deterministic ----------
def _hash(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h &= 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h ^= h >> 16
    return (h & 0xFFFF).astype(np.float64) / 65535.0


def vnoise(p, seed):
    pi = np.floor(p)
    f = p - pi
    u = f * f * (3.0 - 2.0 * f)
    i = pi.astype(np.int64)
    n = np.zeros(len(p))
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1.0 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1.0 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1.0 - u[:, 2]
                n += wx * wy * wz * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return n


def fbm(p, octaves=3, seed=0):
    total, amp, norm = np.zeros(len(p)), 0.5, 0.0
    for o in range(octaves):
        total += amp * vnoise(p * (2.0 ** o) + 17.31 * o, seed + 31 * o)
        norm += amp
        amp *= 0.5
    return total / norm


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------- surfaces: each returns a brightness multiplier per texel (linear) ----------
def k_wood(P, N, g, r, ctx):
    ax = np.argmax(g, axis=1)
    rows = np.arange(len(P))
    along = P[rows, ax]
    u = P[rows, (ax + 1) % 3] + ((r * 13.7) % 1.0 - 0.5) * 0.6 + 0.35
    v = P[rows, (ax + 2) % 3] + ((r * 7.1) % 1.0 - 0.5) * 0.6 + 0.25
    rad = np.sqrt(u * u + v * v)
    warp = fbm(np.stack([along * 1.5, u * 4.0, v * 4.0], 1), 3, 3) - 0.5
    t = rad / 0.022 + warp * 3.0
    ring = (0.5 + 0.5 * np.cos(2.0 * math.pi * t)) ** 3
    fibre_scale = 90.0 if ctx["texel"] < 0.004 else 45.0
    fibre = fbm(np.stack([along * 2.0, u * fibre_scale, v * fibre_scale], 1), 2, 5)
    low = fbm(P * 3.0, 2, 9)
    d = 0.93 - 0.17 * ring + 0.10 * (fibre - 0.5) + 0.08 * (low - 0.5)
    return d * (0.93 + 0.10 * r)


def _weave(P, N, period):
    ax = np.argmax(np.abs(N), axis=1)
    rows = np.arange(len(P))
    s = P[rows, (ax + 1) % 3]
    t = P[rows, (ax + 2) % 3]
    return np.sin(2.0 * math.pi * s / period) * np.sin(2.0 * math.pi * t / period)


def k_fabric(P, N, g, r, ctx):
    d = 0.90 + 0.20 * (fbm(P * 9.0, 3, 21) - 0.5) + 0.12 * (fbm(P * 38.0, 2, 23) - 0.5)
    if ctx["texel"] < 0.0032:
        d += 0.04 * _weave(P, N, 0.012)
    return d


def k_linen(P, N, g, r, ctx):
    ridge = (1.0 - np.abs(2.0 * fbm(P * np.array([4.0, 9.0, 9.0]), 3, 41) - 1.0)) ** 6
    return 0.96 + 0.08 * (fbm(P * 10.0, 2, 43) - 0.5) - 0.12 * ridge


def k_metal(P, N, g, r, ctx):
    streak = fbm(np.stack([P[:, 0] * 4.0, P[:, 1] * 220.0, P[:, 2] * 220.0], 1), 2, 51)
    return 0.92 + 0.12 * (streak - 0.5) + 0.05 * (fbm(P * 6.0, 2, 53) - 0.5)


def k_enamel(P, N, g, r, ctx):
    return 0.97 + 0.04 * (fbm(P * 6.0, 2, 61) - 0.5)


def k_ceramic(P, N, g, r, ctx):
    return 0.985 + 0.025 * (fbm(P * 4.0, 2, 71) - 0.5)


def k_glass(P, N, g, r, ctx):
    streak = 0.5 + 0.5 * np.sin((P[:, 0] - P[:, 2]) * 11.0)
    return 0.93 + 0.07 * streak


def k_screen(P, N, g, r, ctx):
    lo, hi = ctx["lo"], ctx["hi"]
    span = np.maximum(hi - lo, 1e-4)
    q = (P - lo) / span
    band = np.exp(-(((q[:, 0] * 0.6 + q[:, 2] * 0.8) - 0.85) / 0.14) ** 2)
    return 0.82 + 0.18 * band


def k_leaf(P, N, g, r, ctx):
    lo, hi = ctx["lo"], ctx["hi"]
    hz = np.clip((P[:, 2] - lo[2]) / max(hi[2] - lo[2], 1e-4), 0.0, 1.0)
    d = (0.68 + 0.32 * hz ** 0.7) * (0.90 + 0.10 * fbm(P * 14.0, 2, 81))
    return d + 0.05 * (fbm(P * 40.0, 2, 83) - 0.5)


def k_petal(P, N, g, r, ctx):
    return 0.93 + 0.07 * fbm(P * 20.0, 2, 91)


def k_shade(P, N, g, r, ctx):
    c = (ctx["lo"] + ctx["hi"]) * 0.5
    theta = np.arctan2(P[:, 1] - c[1], P[:, 0] - c[0])
    pleat = np.cos(theta * 28.0)
    return 0.96 + 0.03 * pleat + 0.03 * (fbm(P * 30.0, 2, 101) - 0.5)


def k_rug(P, N, g, r, ctx):
    lo, hi = ctx["lo"], ctx["hi"]
    x, y = P[:, 0], P[:, 1]
    e = np.minimum(np.minimum(x - lo[0], hi[0] - x), np.minimum(y - lo[1], hi[1] - y))
    band = np.where(e < 0.07, 0.68, np.where(e < 0.10, 1.0, np.where(e < 0.13, 0.78, 1.0)))
    # The field: a loose diamond trellis around an oval medallion.
    c = (lo + hi) * 0.5
    period = 0.42
    a = ((x - c[0]) / period + 0.5) % 1.0
    b = ((y - c[1]) / period + 0.5) % 1.0
    dl = np.abs(a - 0.5) + np.abs(b - 0.5)   # L1 distance from each cell's centre: diamonds
    field = np.where(np.abs(dl - 0.5) < 0.03, 0.82, np.where(dl < 0.09, 0.86, 1.0))
    qx = (x - c[0]) / max((hi[0] - lo[0]) * 0.24, 0.05)
    qy = (y - c[1]) / max((hi[1] - lo[1]) * 0.24, 0.05)
    q = np.sqrt(qx * qx + qy * qy)
    medallion = np.where(np.abs(q - 1.0) < 0.07, 0.74, np.where(q < 0.62, 0.86, np.where(q < 1.0, 1.0, field)))
    pattern = np.where(e < 0.13, band, medallion)
    return pattern * (0.95 + 0.07 * (fbm(P * 60.0, 2, 111) - 0.5)) * (0.97 + 0.06 * (fbm(P * 5.0, 2, 113) - 0.5))


def k_books(P, N, g, r, ctx):
    return 0.92 + 0.08 * fbm(P * 25.0, 2, 121)


def k_paper(P, N, g, r, ctx):
    return 0.95 + 0.05 * fbm(P * np.array([30.0, 30.0, 160.0]), 2, 131)


def k_plain(P, N, g, r, ctx):
    return np.ones(len(P))


def k_water(P, N, g, r, ctx):
    lo, hi = ctx["lo"], ctx["hi"]
    hz = np.clip((P[:, 2] - lo[2]) / max(hi[2] - lo[2], 1e-4), 0.0, 1.0)
    caustic = (1.0 - np.abs(2.0 * fbm(P * 14.0, 3, 141) - 1.0)) ** 5
    return (0.74 + 0.26 * hz) * (0.90 + 0.16 * caustic)


def k_sand(P, N, g, r, ctx):
    grains = _hash(np.floor(P[:, 0] * 900).astype(np.int64), np.floor(P[:, 1] * 900).astype(np.int64),
                   np.floor(P[:, 2] * 900).astype(np.int64), 151)
    return 0.86 + 0.10 * fbm(P * 40.0, 2, 153) + 0.06 * (grains - 0.5)


def k_keys(P, N, g, r, ctx):
    lo, hi = ctx["lo"], ctx["hi"]
    pitch = (hi[0] - lo[0]) / 52.0
    gap = ((P[:, 0] - lo[0]) / pitch) % 1.0
    return np.where((gap < 0.09) & (N[:, 2] > 0.5), 0.55, 0.98)


def k_clockface(P, N, g, r, ctx):
    """Hour marks and minute dots on a face looking along -y (the model's front)."""
    lo, hi = ctx["lo"], ctx["hi"]
    cx, cz = (lo[0] + hi[0]) * 0.5, (lo[2] + hi[2]) * 0.5
    radius = max((hi[0] - lo[0]) * 0.5, 1e-3)
    dx, dz = P[:, 0] - cx, P[:, 2] - cz
    rad = np.sqrt(dx * dx + dz * dz)
    ang = np.arctan2(dx, dz)
    hour_arc = np.abs(((ang / (2 * math.pi / 12)) + 0.5) % 1.0 - 0.5) * (2 * math.pi / 12) * rad
    minute_arc = np.abs(((ang / (2 * math.pi / 60)) + 0.5) % 1.0 - 0.5) * (2 * math.pi / 60) * rad
    q = rad / radius
    d = 0.97 + 0.03 * fbm(P * 20.0, 2, 161)
    d = np.where((q > 0.72) & (q < 0.9) & (hour_arc < 0.006), 0.12, d)
    d = np.where((q > 0.84) & (q < 0.9) & (minute_arc < 0.0022), 0.35, d)
    d = np.where((q > 0.94) & (q < 0.965), 0.6, d)
    return np.where(N[:, 1] < -0.5, d, 0.97)


KINDS = {"wood": k_wood, "fabric": k_fabric, "linen": k_linen, "metal": k_metal, "enamel": k_enamel,
         "ceramic": k_ceramic, "glass": k_glass, "screen": k_screen, "leaf": k_leaf, "petal": k_petal,
         "shade": k_shade, "rug": k_rug, "books": k_books, "paper": k_paper, "plain": k_plain,
         "water": k_water, "sand": k_sand, "keys": k_keys, "clockface": k_clockface}


# ---------- Blender helpers ----------
def kind_of(model, mat_name):
    over = spec["models"].get(model, {})
    if mat_name in over:
        return over[mat_name]
    if mat_name == "paint":
        return spec.get("default_paint", "wood")
    return spec["kinds"].get(mat_name, "plain")


def bsdf_of(m):
    if not m or not m.node_tree:
        return None
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def loose_parts(me):
    """Union of faces that share a vertex position: (part index per vertex, number of parts)."""
    parent = list(range(len(me.vertices)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    seen = {}
    for v in me.vertices:
        key = (round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))
        if key in seen:
            union(v.index, seen[key])
        else:
            seen[key] = v.index
    for p in me.polygons:
        vs = p.vertices
        for k in range(1, len(vs)):
            union(vs[0], vs[k])
    roots = {}
    part = [0] * len(me.vertices)
    for v in range(len(me.vertices)):
        part[v] = roots.setdefault(find(v), len(roots))
    return part, len(roots)


def part_attributes(me):
    part, count = loose_parts(me)
    co = np.array([v.co[:] for v in me.vertices])
    lo = np.full((count, 3), 1e9)
    hi = np.full((count, 3), -1e9)
    pid = np.array(part)
    np.minimum.at(lo, pid, co)
    np.maximum.at(hi, pid, co)
    axis = np.argmax(hi - lo, axis=1)
    rnd = _hash(np.arange(count, dtype=np.int64), np.zeros(count, np.int64), np.full(count, 7, np.int64), 1234)
    grain = me.attributes.new(name="grain", type="FLOAT_COLOR", domain="POINT")
    rand = me.attributes.new(name="part", type="FLOAT_COLOR", domain="POINT")
    for v in range(len(me.vertices)):
        a = axis[pid[v]]
        grain.data[v].color = (1.0 if a == 0 else 0.0, 1.0 if a == 1 else 0.0, 1.0 if a == 2 else 0.0, 1.0)
        x = float(rnd[pid[v]])
        rand.data[v].color = (x, x, x, 1.0)
    return count


def unwrap(obj):
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.0, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    # Undersides resting on the floor are never seen: shrink them so the visible surfaces get the texels.
    bm = bmesh.from_edit_mesh(me)
    uv = bm.loops.layers.uv.active
    for f in bm.faces:
        if is_hidden_underside(f.normal, f.calc_center_median()):
            c = sum((l[uv].uv for l in f.loops), Vector((0.0, 0.0))) / len(f.loops)
            for l in f.loops:
                l[uv].uv = c + (l[uv].uv - c) * 0.04
    bmesh.update_edit_mesh(me)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=0.008)
    bpy.ops.object.mode_set(mode="OBJECT")


def is_hidden_underside(normal, centre):
    return normal.z < -0.9 and centre.z < 0.02


def new_image(name, size, float_buffer=True):
    img = bpy.data.images.new(name, size, size, alpha=True, float_buffer=float_buffer)
    if float_buffer:
        img.colorspace_settings.name = "Non-Color"
    return img


def bake_material(name, target, build):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    sock = build(nt)
    if sock is not None:
        nt.links.new(sock, em.inputs["Color"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = target
    tex.select = True
    nt.nodes.active = tex
    return m


def _muladd(nt, sock, mul, add):
    vm = nt.nodes.new("ShaderNodeVectorMath")
    vm.operation = "MULTIPLY_ADD"
    nt.links.new(sock, vm.inputs[0])
    vm.inputs[1].default_value = (mul, mul, mul)
    vm.inputs[2].default_value = (add, add, add)
    return vm.outputs["Vector"]


def bake_pass(obj, kind, size, slots, samples=1):
    img = new_image("bake_" + kind, size)
    mats = []
    for i in range(slots):
        if kind == "pos":
            def build(nt):
                tc = nt.nodes.new("ShaderNodeTexCoord")
                return _muladd(nt, tc.outputs["Object"], POS_SCALE, 0.5)
        elif kind == "nrm":
            def build(nt):
                ge = nt.nodes.new("ShaderNodeNewGeometry")
                return _muladd(nt, ge.outputs["True Normal"], 0.5, 0.5)
        elif kind == "ids":
            def build(nt, i=i):
                at = nt.nodes.new("ShaderNodeAttribute")
                at.attribute_type = "GEOMETRY"
                at.attribute_name = "part"
                sep = nt.nodes.new("ShaderNodeSeparateColor")
                nt.links.new(at.outputs["Color"], sep.inputs["Color"])
                comb = nt.nodes.new("ShaderNodeCombineColor")
                comb.inputs["Red"].default_value = (i + 0.5) / 32.0
                nt.links.new(sep.outputs["Red"], comb.inputs["Green"])
                comb.inputs["Blue"].default_value = 1.0
                return comb.outputs["Color"]
        elif kind == "grain":
            def build(nt):
                at = nt.nodes.new("ShaderNodeAttribute")
                at.attribute_type = "GEOMETRY"
                at.attribute_name = "grain"
                return at.outputs["Color"]
        else:   # ao: the material doesn't matter, only the target image
            def build(nt):
                return None
        mats.append(bake_material("bake_%s_%d" % (kind, i), img, build))
    me = obj.data
    keep = [p.material_index for p in me.polygons]
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    for p, k in zip(me.polygons, keep):
        p.material_index = k
    scene = bpy.context.scene
    scene.cycles.samples = samples
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="AO" if kind == "ao" else "EMIT", margin=max(4, size // 128), margin_type="EXTEND",
                        use_clear=True, target="IMAGE_TEXTURES")
    px = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    for m in mats:
        bpy.data.materials.remove(m)
    bpy.data.images.remove(img)
    return px.reshape(-1, 4).astype(np.float64)


def gpu_backend():
    """Cycles on a graphics card when there is one (OptiX, CUDA, HIP, oneAPI, Metal), else None (the CPU)."""
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
    except KeyError:
        return None
    for backend in ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL"):
        try:
            prefs.compute_device_type = backend
        except TypeError:
            continue
        prefs.get_devices()
        devices = [d for d in prefs.devices if d.type == backend]
        if devices:
            for d in prefs.devices:
                d.use = d.type == backend
            return backend
    return None


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    # Each model starts from factory settings, preferences included, so the card is chosen every time.
    gpu = gpu_backend() if os.environ.get("POLOX_BAKE_CPU") != "1" else None
    print("baking on", gpu or "CPU")
    scene.cycles.device = "GPU" if gpu else "CPU"
    scene.cycles.use_denoising = False
    scene.render.bake.use_selected_to_active = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.35
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0, 0, -0.0005))
    plane = bpy.context.active_object
    plane.name = "bake_floor"
    return plane


# ---------- main ----------
report = {}
files = sorted(f for f in os.listdir(in_dir) if f.endswith(".glb"))
for f in files:
    model = f[:-4]
    if only and model not in only:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(in_dir, f))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    assert len(meshes) == 1, "%s: expected one mesh, got %d" % (model, len(meshes))
    obj = meshes[0]
    me = obj.data
    originals = list(me.materials)
    info = []
    for m in originals:
        b = bsdf_of(m)
        info.append({
            "name": m.name,
            "kind": kind_of(model, m.name),
            "base": list(b.inputs["Base Color"].default_value[:3]) if b else [1.0, 1.0, 1.0],
            "emit": list(b.inputs["Emission Color"].default_value[:3]) if b else [0.0, 0.0, 0.0],
            "emit_strength": float(b.inputs["Emission Strength"].default_value) if b else 0.0,
        })
    face_slots = [p.material_index for p in me.polygons]
    area = sum(p.area for p in me.polygons if not is_hidden_underside(p.normal, p.center))
    size = spec["sizes"][1] if area > spec["large_area_m2"] else spec["sizes"][0]
    parts = part_attributes(me)
    unwrap(obj)
    plane = setup_scene()
    slots = len(originals)
    pos = bake_pass(obj, "pos", size, slots)
    nrm = bake_pass(obj, "nrm", size, slots)
    ids = bake_pass(obj, "ids", size, slots)
    grn = bake_pass(obj, "grain", size, slots)
    ao = bake_pass(obj, "ao", size, slots, samples=96)
    bpy.data.objects.remove(plane, do_unlink=True)

    covered = ids[:, 2] > 0.5
    P = (pos[covered, :3] - 0.5) / POS_SCALE
    Nn = nrm[covered, :3] * 2.0 - 1.0
    slot = np.clip((ids[covered, 0] * 32.0).astype(int), 0, slots - 1)
    rnd = ids[covered, 1]
    G = grn[covered, :3]
    A = np.clip(ao[covered, 0], 0.0, 1.0)
    texel = math.sqrt(area / max(1, int(covered.sum())))
    colour = np.zeros((len(P), 3))
    for s, mi in enumerate(info):
        sel = slot == s
        if not sel.any():
            continue
        Ps = P[sel]
        ctx = {"texel": texel, "lo": Ps.min(axis=0), "hi": Ps.max(axis=0)}
        d = np.clip(KINDS[mi["kind"]](Ps, Nn[sel], G[sel], rnd[sel], ctx), 0.45, 1.0)
        a = A[sel]
        if mi["emit_strength"] > 0.0:
            shade = 0.85 + 0.15 * a
        elif mi["kind"] in ("leaf", "petal", "glass"):
            # Kenney's leaves, petals and window panes are paper-thin, two faces back to back: the bake sees
            # each face as buried in the other, so only a hint of it is kept (less still on bright petals).
            shade = (0.9 + 0.1 * a) if mi["kind"] == "petal" else (0.8 + 0.2 * a)
        else:
            shade = 0.30 + 0.70 * a ** 1.3
        if mi["kind"] == "books":
            pal = np.array([hex_linear(h) for h in BOOK_COLOURS])
            base = pal[np.minimum((rnd[sel] * len(pal)).astype(int), len(pal) - 1)]
        elif mi["name"] == "paint":
            base = np.ones((int(sel.sum()), 3))
        else:
            base = np.tile(np.array(mi["base"]), (int(sel.sum()), 1))
        colour[sel] = base * (d * shade)[:, None]
    srgb = linear_to_srgb(colour)
    full = np.zeros((size * size, 4))
    fill = srgb.mean(axis=0) if len(srgb) else np.array([0.5, 0.5, 0.5])
    full[:, :3] = fill
    full[covered, :3] = srgb
    full[:, 3] = 1.0
    # Packed with no file of its own, so the GLB names it "surface" (Godot extracts it as <model>_surface.png);
    # a copy is saved for looking at.
    tex_img = bpy.data.images.new("surface", size, size, alpha=False)
    tex_img.pixels.foreach_set(full.astype(np.float32).ravel())
    tex_img.pack()
    review = tex_img.copy()
    review.filepath_raw = os.path.abspath(os.path.join(out_dir, "png", model + "_surface.png"))
    review.file_format = "PNG"
    review.save()
    bpy.data.images.remove(review)

    # The model's own materials, now textured (same names and slots; the paint keeps its colour as a factor).
    me.materials.clear()
    for m in originals:
        if m:
            bpy.data.materials.remove(m)
    for mi in info:
        m = bpy.data.materials.new(mi["name"])
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = tex_img
        if mi["name"] == "paint":
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(tex.outputs["Color"], mix.inputs[6])
            mix.inputs[7].default_value = (*mi["base"], 1.0)
            nt.links.new(mix.outputs[2], b.inputs["Base Color"])
        else:
            nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = ROUGHNESS[mi["kind"]]
        b.inputs["Metallic"].default_value = 0.0
        if mi["emit_strength"] > 0.0:
            b.inputs["Emission Color"].default_value = (*mi["emit"], 1.0)
            b.inputs["Emission Strength"].default_value = mi["emit_strength"]
        me.materials.append(m)
    for p, k in zip(me.polygons, face_slots):
        p.material_index = k
    assert [m.name for m in me.materials] == [mi["name"] for mi in info], "%s: material names changed" % model
    for name in ("grain", "part"):
        if me.attributes.get(name):
            me.attributes.remove(me.attributes[name])
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    out_path = os.path.join(out_dir, model + ".glb")
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_yup=True,
        export_apply=True, export_cameras=False, export_lights=False, export_animations=False,
        export_materials="EXPORT", export_image_format="AUTO", export_texcoords=True, export_normals=True)
    me.calc_loop_triangles()
    report[model] = {"texture": size, "area_m2": round(area, 2), "texel_mm": round(texel * 1000, 2), "parts": parts,
                     "tris": len(me.loop_triangles), "glb_kb": round(os.path.getsize(out_path) / 1024),
                     "materials": {mi["name"]: mi["kind"] for mi in info}}
    print("textured", model, report[model])
json.dump(report, open(report_path, "w"), indent=1)
print("done", len(report))
