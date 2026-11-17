extends RefCounted
## Real-life furniture and decor for the Light World (and anywhere else you place it): beds, desks,
## sofas, kitchens, bathrooms, lamps, plants, rugs, and small outdoor things, in real-life sizes (one
## cell is a metre), in any colour. Most are Kenney's CC0 models made ready in Blender
## (licensed_props.gd); the rest, and every piece's size for picking, are simple shapes drawn here.
##
## Object: {"type": "furniture", "model": "<id>", "pos": [x, y, z] (the footprint's first cell),
##          "rot": 0-3, "color": "#hex" ("" = the model's own), "label": ""}
## A model covers size [w, d] cells (turned with rot) and blocks walking unless it's flat (rugs,
## flowers on the ground...).

## How far a light switch's rocker tips (radians): up when on, down when off.
const SWITCH_TILT := 0.3
const TYPE := "furniture"
const LAYER_OBJECTS := 4

## id: [name, [w, d], colour, blocks, where ("in" | "out" | "both"), category]
const CATALOG := {
	"bed": ["Bed", [1, 2], "#7f9cc9", true, "in", "bedroom"],
	"double_bed": ["Double bed", [2, 2], "#c98a8a", true, "in", "bedroom"],
	"nightstand": ["Nightstand", [1, 1], "#a0784e", true, "in", "bedroom"],
	"wardrobe": ["Wardrobe", [1, 1], "#8b6a4a", true, "in", "bedroom"],
	"dresser": ["Dresser", [1, 1], "#b08860", true, "in", "bedroom"],
	"desk": ["Desk", [2, 1], "#b58b5c", true, "in", "study"],
	"chair": ["Chair", [1, 1], "#8b6a4a", true, "in", "study"],
	"computer": ["Computer desk", [2, 1], "#3c3f4a", true, "in", "study"],
	"bookshelf": ["Bookshelf", [1, 1], "#7a5a3c", true, "in", "study"],
	"sofa": ["Sofa", [2, 1], "#7a8f6a", true, "in", "living"],
	"armchair": ["Armchair", [1, 1], "#a07a6a", true, "in", "living"],
	"coffee_table": ["Coffee table", [1, 1], "#a0784e", true, "in", "living"],
	"tv": ["TV", [1, 1], "#2a2a33", true, "in", "living"],
	"dining_table": ["Dining table", [2, 1], "#a0784e", true, "in", "kitchen"],
	"counter": ["Counter", [1, 1], "#e8e2d6", true, "in", "kitchen"],
	"sink": ["Sink", [1, 1], "#e8e2d6", true, "in", "kitchen"],
	"stove": ["Stove", [1, 1], "#d8d8dc", true, "in", "kitchen"],
	"fridge": ["Fridge", [1, 1], "#eef0f2", true, "in", "kitchen"],
	"toilet": ["Toilet", [1, 1], "#f4f4f4", true, "in", "bathroom"],
	"bathtub": ["Bathtub", [1, 2], "#f4f4f4", true, "in", "bathroom"],
	"shower": ["Shower", [1, 1], "#cfe3ea", true, "in", "bathroom"],
	"washbasin": ["Washbasin", [1, 1], "#f4f4f4", true, "in", "bathroom"],
	"washer": ["Washing machine", [1, 1], "#eef0f2", true, "in", "laundry"],
	"lamp": ["Floor lamp", [1, 1], "#f3d9a4", true, "in", "decor"],
	"plant": ["House plant", [1, 1], "#5f9a5a", true, "both", "decor"],
	"rug": ["Rug", [2, 2], "#c96a5a", false, "in", "decor"],
	"runner": ["Hallway runner", [1, 3], "#4a6aa8", false, "in", "decor"],
	"piano": ["Piano", [2, 1], "#2a2028", true, "in", "living"],
	"stairs": ["Stairs", [1, 3], "#a0784e", true, "in", "structure"],
	"picture": ["Picture frame", [1, 1], "#c8a882", false, "in", "decor"],
	"mirror": ["Mirror", [1, 1], "#d8c8a8", false, "in", "decor"],
	"bench": ["Bench", [2, 1], "#8b6a4a", true, "out", "outside"],
	"flowers": ["Flowers", [1, 1], "#e88aa8", false, "out", "outside"],
	"mailbox": ["Mailbox", [1, 1], "#3c5a8a", true, "out", "outside"],
	"tree": ["Tree", [1, 1], "#4f7a46", true, "out", "outside"],
	"bush": ["Bush", [1, 1], "#4f8a4a", true, "out", "outside"],
	"car": ["Car", [2, 1], "#8a9ab0", true, "out", "outside"],
	"floor_cushion": ["Floor cushion", [1, 1], "#5e8e91", true, "in", "living"],
	"bean_bag": ["Bean bag", [1, 1], "#c7684f", true, "in", "living"],
	"fish_tank": ["Fish tank", [1, 1], "#8b6a4a", true, "in", "living"],
	"coat_rack": ["Coat rack", [1, 1], "#8b6a4a", true, "in", "decor"],
	"bar_stool": ["Bar stool", [1, 1], "#3f6f8f", true, "in", "kitchen"],
	"wall_clock": ["Wall clock", [1, 1], "#7a5a3c", false, "in", "decor"],
	"light_switch": ["Light switch", [1, 1], "#f2ece0", false, "in", "decor"],
	"lantern": ["Glass lantern", [1, 1], "#c9a45c", true, "both", "decor"],
	"record_player": ["Record player", [1, 1], "#9b6f4f", true, "in", "living"],
	"shoe_rack": ["Shoe rack", [1, 1], "#a8855c", true, "in", "decor"],
	"birdbath": ["Birdbath", [1, 1], "#a5b5b0", true, "out", "outside"],
	"streetlamp": ["Street lamp", [1, 1], "#535966", true, "out", "outside"],
}


static func exists(model: String) -> bool:
	return CATALOG.has(model)


static func name_of(model: String) -> String:
	return str(CATALOG.get(model, ["Furniture"])[0])


static func base_size(model: String) -> Vector2i:
	var s: Array = CATALOG.get(model, ["", [1, 1]])[1]
	return Vector2i(int(s[0]), int(s[1]))


static func default_color(model: String) -> String:
	return str(CATALOG.get(model, ["", [1, 1], "#a0784e"])[2])


static func blocks(model: String) -> bool:
	return bool(CATALOG.get(model, ["", [1, 1], "", true])[3])


static func where(model: String) -> String:
	return str(CATALOG.get(model, ["", [1, 1], "", true, "both"])[4])


static func is_furniture(o: Dictionary) -> bool:
	return str(o.get("type", "")) == TYPE


## The cells a piece covers: its size turned by rot, from its first cell.
static func footprint(o: Dictionary) -> Rect2i:
	var p: Array = o.get("pos", [0, 0, 0])
	var s := base_size(str(o.get("model", "")))
	if posmod(int(o.get("rot", 0)), 2) == 1:
		s = Vector2i(s.y, s.x)
	return Rect2i(Vector2i(int(p[0]), int(p[2])), s)


static func cells(o: Dictionary) -> Array:
	var out: Array = []
	var r := footprint(o)
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, z))
	return out


## Where the model's centre sits in the room (the middle of its footprint).
static func center(o: Dictionary) -> Vector3:
	var r := footprint(o)
	var p: Array = o.get("pos", [0, 0, 0])
	return Vector3(r.position.x + r.size.x / 2.0, float(p[1]), r.position.y + r.size.y / 2.0)


static func make(model: String, x: int, z: int, rot: int = 0, color: String = "") -> Dictionary:
	return {"id": "", "type": TYPE, "model": model, "pos": [x, 0, z], "rot": posmod(rot, 4), "scale": 1.0,
		"color": color, "texture": "", "interaction_text": "", "door_target": "", "label": ""}


# --- Drawing ------------------------------------------------------------------------------------

static var _mats: Dictionary = {}


static func _mat(c: Color, emit: bool = false) -> StandardMaterial3D:
	var key := c.to_html() + ("e" if emit else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.4
	_mats[key] = m
	return m


static func _box(root: Node3D, size: Vector3, pos: Vector3, c: Color, emit: bool = false, surface: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, emit)
	# Scanned surfaces follow the walls and floors: off in Battery saver and on Android (surface_materials.gd).
	if surface != "" and preload("res://scripts/world/surface_materials.gd").enabled():
		var key := "surface|" + surface + "|" + c.to_html()
		if not _mats.has(key):
			var material := _mat(c, emit).duplicate() as StandardMaterial3D
			material.albedo_texture = preload("res://scripts/world/surface_materials.gd").albedo(surface)
			material.albedo_color = c.lightened(0.25)
			_mats[key] = material
		mi.material_override = _mats[key]
	mi.position = pos
	root.add_child(mi)
	return mi


static func _cyl(root: Node3D, r: float, h: float, pos: Vector3, c: Color, top_r: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r
	cm.top_radius = r if top_r < 0.0 else top_r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(c)
	mi.position = pos
	root.add_child(mi)
	return mi


static func _ball(root: Node3D, r: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = _mat(c)
	mi.position = pos
	root.add_child(mi)
	return mi


static func _legs(root: Node3D, w: float, d: float, h: float, c: Color, t: float = 0.06) -> void:
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(root, Vector3(t, h, t), Vector3(sx * (w / 2.0 - t), h / 2.0, sz * (d / 2.0 - t)), c)


## The model as a node, centred on its footprint (the caller places it at center()). Models are drawn
## facing south (+z) at rot 0, at their base size; rot turns them.
static func build(o: Dictionary, ghost: bool = false) -> Node3D:
	var model := str(o.get("model", "plant"))
	var col := Color.from_string(str(o.get("color", "")) if str(o.get("color", "")) != "" else default_color(model), Color("#a0784e"))
	var dark := col.darkened(0.35)
	var light := col.lightened(0.3)
	var wood := Color("#8b6a4a")
	var white := Color("#f2f0ea")
	var s := base_size(model)
	var w := float(s.x)
	var d := float(s.y)
	var root := Node3D.new()
	var parts := Node3D.new()
	parts.name = "Model"
	root.add_child(parts)
	var top := 0.8
	match model:
		"floor_cushion":
			_box(parts, Vector3(0.8, 0.2, 0.8), Vector3(0, 0.14, 0), col, false, "carpet")
			_box(parts, Vector3(0.7, 0.03, 0.7), Vector3(0, 0.255, 0), light, false, "carpet")
			top = 0.28
		"record_player":
			_box(parts, Vector3(0.78, 0.55, 0.5), Vector3(0, 0.3, 0), wood)
			_box(parts, Vector3(0.7, 0.12, 0.46), Vector3(0, 0.64, 0), col)
			_cyl(parts, 0.18, 0.025, Vector3(-0.08, 0.715, 0), Color("#28272c"))
			_cyl(parts, 0.05, 0.028, Vector3(-0.08, 0.718, 0), Color("#d9b165"))
			_box(parts, Vector3(0.03, 0.025, 0.3), Vector3(0.23, 0.74, 0), Color("#d2ccc1"))
			top = 0.77
		"shoe_rack":
			for y in [0.15, 0.45]:
				_box(parts, Vector3(0.85, 0.04, 0.4), Vector3(0, y, 0), col)
				for x in [-0.24, 0.17]:
					_box(parts, Vector3(0.13, 0.1, 0.25), Vector3(x, y + 0.07, 0), Color("#4b555f"))
			_legs(parts, 0.85, 0.4, 0.5, dark)
			top = 0.57
		# Blender models (licensed_props.gd) replace these five; the shapes only give their sizes.
		"bean_bag":
			_ball(parts, 0.42, Vector3(0, 0.3, 0), col).scale = Vector3(1.0, 0.65, 1.0)
			top = 0.55
		"fish_tank":
			_box(parts, Vector3(0.84, 0.6, 0.4), Vector3(0, 0.3, 0), col)
			_box(parts, Vector3(0.8, 0.45, 0.36), Vector3(0, 0.86, 0), Color("#4fa9c4"), true)
			top = 1.1
		"coat_rack":
			_cyl(parts, 0.2, 0.04, Vector3(0, 0.02, 0), col)
			_cyl(parts, 0.025, 1.75, Vector3(0, 0.9, 0), col)
			top = 1.9
		"bar_stool":
			_cyl(parts, 0.19, 0.07, Vector3(0, 0.735, 0), col)
			_cyl(parts, 0.03, 0.7, Vector3(0, 0.35, 0), Color("#3a3f46"))
			top = 0.77
		"light_switch":
			# [GLASS_UI] A wall switch you flick (light_life.gd flip_switch): a ceramic plate, a rocker that
			# tips up when on and down when off, and a small pilot light that glows while it's on.
			var on := bool(o.get("on", true))
			_box(parts, Vector3(0.17, 0.25, 0.022), Vector3(0, 1.15, -0.468), col)
			_box(parts, Vector3(0.13, 0.21, 0.006), Vector3(0, 1.15, -0.455), col.lightened(0.25))
			var rocker := _box(parts, Vector3(0.07, 0.12, 0.03), Vector3(0, 1.15, -0.445), Color("#fffaf0"))
			rocker.name = "Rocker"
			rocker.rotation.x = SWITCH_TILT if on else -SWITCH_TILT
			rocker.set_meta("id", str(o.get("id", "")))
			if not ghost:
				rocker.add_to_group(&"polox_rocker")
			var pilot := _box(parts, Vector3(0.018, 0.018, 0.006), Vector3(0, 1.245, -0.452), Color("#ffb867") if on else Color("#5a5262"), on)
			pilot.name = "Pilot"
			top = 1.32   # (clickable up to the plate; it never blocks the way)
		"lantern":
			# Poly Haven's Lantern 01 (licensed_props.gd); this is only the stand-in if the model is missing.
			_cyl(parts, 0.12, 0.3, Vector3(0, 0.15, 0), col)
			var glow := OmniLight3D.new()
			glow.name = "Glow"
			glow.add_to_group("polox_lamp")
			glow.light_color = Color("#ffcf8a")
			glow.light_energy = 0.55
			glow.omni_range = 2.6
			glow.position = Vector3(0, 0.32, 0)
			root.add_child(glow)
			top = 0.5
		"wall_clock":
			# Hung on the wall behind it, like a picture, a little higher.
			_cyl(parts, 0.18, 0.05, Vector3(0, 1.6, -0.445), col).rotation.x = PI / 2.0
			top = 0.05
		"birdbath":
			_cyl(parts, 0.14, 0.65, Vector3(0, 0.325, 0), col)
			_cyl(parts, 0.4, 0.1, Vector3(0, 0.7, 0), col)
			_cyl(parts, 0.34, 0.025, Vector3(0, 0.76, 0), Color("#9ac4d0"))
			top = 0.78
		"bed", "double_bed":
			_box(parts, Vector3(w - 0.1, 0.25, d - 0.1), Vector3(0, 0.2, 0), wood)
			_box(parts, Vector3(w - 0.16, 0.18, d - 0.2), Vector3(0, 0.41, 0.02), white)
			_box(parts, Vector3(w - 0.12, 0.2, d * 0.62), Vector3(0, 0.45, d * 0.17), col)
			for i in (2 if model == "double_bed" else 1):
				var px := 0.0 if model == "bed" else (-0.45 + i * 0.9)
				_box(parts, Vector3(0.62, 0.12, 0.32), Vector3(px, 0.56, -d / 2.0 + 0.3), white)
			_box(parts, Vector3(w - 0.1, 0.7, 0.08), Vector3(0, 0.45, -d / 2.0 + 0.06), wood.darkened(0.1))
			top = 0.6
		"nightstand":
			_box(parts, Vector3(0.5, 0.5, 0.45), Vector3(0, 0.25, 0), col)
			_box(parts, Vector3(0.4, 0.04, 0.02), Vector3(0, 0.36, 0.23), dark)
			_cyl(parts, 0.06, 0.18, Vector3(0, 0.59, 0), Color("#e8d8b0"))
			_cyl(parts, 0.12, 0.14, Vector3(0, 0.74, 0), Color("#fff1c8"), 0.07)
			top = 0.8
		"wardrobe":
			_box(parts, Vector3(0.95, 2.0, 0.6), Vector3(0, 1.0, 0), col, false, "wood")
			_box(parts, Vector3(0.02, 1.8, 0.02), Vector3(0, 1.0, 0.31), dark, false, "wood")
			_box(parts, Vector3(0.04, 0.2, 0.04), Vector3(-0.08, 1.05, 0.32), Color("#d8c08a"))
			_box(parts, Vector3(0.04, 0.2, 0.04), Vector3(0.08, 1.05, 0.32), Color("#d8c08a"))
			top = 2.0
		"dresser":
			_box(parts, Vector3(0.9, 0.85, 0.5), Vector3(0, 0.425, 0), col)
			for i in 3:
				_box(parts, Vector3(0.8, 0.02, 0.02), Vector3(0, 0.2 + i * 0.25, 0.26), dark)
			top = 0.85
		"desk", "computer":
			_box(parts, Vector3(w - 0.1, 0.05, d - 0.3), Vector3(0, 0.74, -0.1), col)
			_legs(parts, w - 0.1, d - 0.3, 0.72, dark)
			parts.get_child(parts.get_child_count() - 1).position.z -= 0.1
			if model == "computer":
				_box(parts, Vector3(0.6, 0.38, 0.04), Vector3(0, 1.0, -0.3), Color("#1c1e24"))
				_box(parts, Vector3(0.54, 0.32, 0.01), Vector3(0, 1.0, -0.275), Color("#6ab0e8"), true)
				_box(parts, Vector3(0.5, 0.02, 0.16), Vector3(0, 0.78, 0.0), Color("#2a2c33"))
			else:
				_box(parts, Vector3(0.3, 0.02, 0.22), Vector3(-0.4, 0.78, -0.05), Color("#f2f0ea"))
				_cyl(parts, 0.05, 0.3, Vector3(0.55, 0.92, -0.25), Color("#e8d8b0"))
			top = 0.78
		"chair":
			_box(parts, Vector3(0.45, 0.05, 0.45), Vector3(0, 0.45, 0), col)
			_legs(parts, 0.45, 0.45, 0.44, dark, 0.04)
			_box(parts, Vector3(0.45, 0.45, 0.05), Vector3(0, 0.7, -0.2), col)
			top = 0.95
		"bookshelf":
			_box(parts, Vector3(0.9, 1.8, 0.35), Vector3(0, 0.9, -0.3), col)
			var book_cols := [Color("#c95a5a"), Color("#5a8ac9"), Color("#e8c25a"), Color("#6ab07a"), Color("#a07ac9")]
			for shelf in 4:
				var y := 0.25 + shelf * 0.42
				_box(parts, Vector3(0.84, 0.03, 0.3), Vector3(0, y - 0.15, -0.28), dark)
				for b in 5:
					_box(parts, Vector3(0.12, 0.26 - (b % 2) * 0.04, 0.22), Vector3(-0.32 + b * 0.16, y - 0.01, -0.26), book_cols[(b + shelf) % 5])
			top = 1.8
		"sofa":
			_box(parts, Vector3(w - 0.1, 0.4, 0.8), Vector3(0, 0.25, 0.05), col, false, "carpet")
			_box(parts, Vector3(w - 0.1, 0.5, 0.22), Vector3(0, 0.6, -0.3), col.darkened(0.1))
			_box(parts, Vector3(0.18, 0.55, 0.8), Vector3(-(w - 0.1) / 2.0 + 0.09, 0.4, 0.05), dark, false, "carpet")
			_box(parts, Vector3(0.18, 0.55, 0.8), Vector3((w - 0.1) / 2.0 - 0.09, 0.4, 0.05), dark, false, "carpet")
			_box(parts, Vector3(0.7, 0.1, 0.6), Vector3(-0.42, 0.5, 0.1), light, false, "carpet")
			_box(parts, Vector3(0.7, 0.1, 0.6), Vector3(0.42, 0.5, 0.1), light, false, "carpet")
			top = 0.85
		"armchair":
			_box(parts, Vector3(0.8, 0.4, 0.8), Vector3(0, 0.25, 0.05), col)
			_box(parts, Vector3(0.8, 0.5, 0.2), Vector3(0, 0.6, -0.3), col.darkened(0.1))
			_box(parts, Vector3(0.15, 0.55, 0.8), Vector3(-0.32, 0.4, 0.05), dark)
			_box(parts, Vector3(0.15, 0.55, 0.8), Vector3(0.32, 0.4, 0.05), dark)
			top = 0.85
		"coffee_table":
			_box(parts, Vector3(0.8, 0.05, 0.5), Vector3(0, 0.42, 0), col)
			_legs(parts, 0.8, 0.5, 0.4, dark, 0.05)
			_box(parts, Vector3(0.2, 0.03, 0.15), Vector3(0.15, 0.46, 0.05), Color("#e8c25a"))
			top = 0.45
		"tv":
			_box(parts, Vector3(0.95, 0.45, 0.4), Vector3(0, 0.225, -0.2), Color("#5a4a3c"))
			_box(parts, Vector3(0.9, 0.52, 0.05), Vector3(0, 0.78, -0.3), col)
			_box(parts, Vector3(0.84, 0.46, 0.01), Vector3(0, 0.78, -0.27), Color("#2a3a5a"), true)
			top = 1.05
		"dining_table":
			_box(parts, Vector3(w - 0.2, 0.06, d - 0.15), Vector3(0, 0.74, 0), col)
			_legs(parts, w - 0.2, d - 0.15, 0.72, dark)
			top = 0.78
		"counter", "sink", "stove":
			_box(parts, Vector3(0.98, 0.86, 0.6), Vector3(0, 0.43, -0.2), Color("#c8b49a") if model == "counter" else Color("#d0c4b0"))
			_box(parts, Vector3(1.0, 0.04, 0.62), Vector3(0, 0.88, -0.2), col)
			if model == "sink":
				_box(parts, Vector3(0.5, 0.02, 0.36), Vector3(0, 0.905, -0.2), Color("#9aa4b0"))
				_box(parts, Vector3(0.04, 0.22, 0.04), Vector3(0, 1.0, -0.42), Color("#b8c0c8"))
			elif model == "stove":
				for gx in [-0.22, 0.22]:
					for gz in [-0.32, -0.08]:
						_cyl(parts, 0.09, 0.02, Vector3(gx, 0.91, gz), Color("#2a2a2a"))
				_box(parts, Vector3(0.7, 0.4, 0.02), Vector3(0, 0.45, 0.11), Color("#2a2a30"))
			top = 0.9
		"fridge":
			_box(parts, Vector3(0.75, 1.8, 0.7), Vector3(0, 0.9, -0.1), col)
			_box(parts, Vector3(0.72, 0.02, 0.02), Vector3(0, 1.2, 0.26), Color("#b8c0c8"))
			_box(parts, Vector3(0.04, 0.3, 0.04), Vector3(0.3, 1.45, 0.27), Color("#b8c0c8"))
			top = 1.8
		"toilet":
			_box(parts, Vector3(0.4, 0.4, 0.5), Vector3(0, 0.2, 0.05), col)
			_box(parts, Vector3(0.44, 0.06, 0.52), Vector3(0, 0.43, 0.05), col.darkened(0.05))
			_box(parts, Vector3(0.45, 0.4, 0.18), Vector3(0, 0.6, -0.3), col)
			top = 0.8
		"bathtub":
			_box(parts, Vector3(0.8, 0.55, d - 0.2), Vector3(0, 0.275, 0), col)
			_box(parts, Vector3(0.62, 0.02, d - 0.4), Vector3(0, 0.56, 0), Color("#9ad0e8"))
			top = 0.56
		"shower":
			_box(parts, Vector3(0.9, 0.08, 0.9), Vector3(0, 0.04, 0), Color("#e8e8ec"))
			_box(parts, Vector3(0.02, 1.9, 0.9), Vector3(0.44, 0.95, 0), Color(col, 0.35))
			_box(parts, Vector3(0.9, 1.9, 0.02), Vector3(0, 0.95, 0.44), Color(col, 0.35))
			_cyl(parts, 0.08, 0.03, Vector3(0, 1.9, -0.3), Color("#b8c0c8"))
			for m in parts.get_children():
				if (m as MeshInstance3D).material_override.albedo_color.a < 1.0:
					var tm := ((m as MeshInstance3D).material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
					tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					(m as MeshInstance3D).material_override = tm
			top = 1.9
		"washbasin":
			_cyl(parts, 0.1, 0.75, Vector3(0, 0.375, -0.2), col)
			_box(parts, Vector3(0.55, 0.12, 0.42), Vector3(0, 0.8, -0.2), col)
			_box(parts, Vector3(0.5, 0.6, 0.03), Vector3(0, 1.4, -0.45), Color("#cfe3ea"))
			top = 0.86
		"washer":
			_box(parts, Vector3(0.6, 0.85, 0.6), Vector3(0, 0.425, -0.1), col)
			_cyl(parts, 0.2, 0.03, Vector3(0, 0.45, 0.21), Color("#9aa4b0")).rotation.x = PI / 2.0
			top = 0.85
		"lamp":
			_cyl(parts, 0.15, 0.04, Vector3(0, 0.02, 0), Color("#3a3a3a"))
			_cyl(parts, 0.025, 1.4, Vector3(0, 0.72, 0), Color("#3a3a3a"))
			_cyl(parts, 0.22, 0.28, Vector3(0, 1.5, 0), col, 0.13)
			var lamp := OmniLight3D.new()
			lamp.name = "Glow"
			lamp.add_to_group("polox_lamp")   # PC Ultra: the nearest lamps cast shadows (pc_detail.gd)
			lamp.light_color = Color("#ffd9a0")
			lamp.light_energy = 0.7
			lamp.omni_range = 3.0
			lamp.position = Vector3(0, 1.4, 0)
			root.add_child(lamp)
			top = 1.65
		"plant":
			_cyl(parts, 0.18, 0.32, Vector3(0, 0.16, 0), Color("#c0704a"), 0.22)
			_ball(parts, 0.3, Vector3(0, 0.6, 0), col)
			_ball(parts, 0.2, Vector3(0.12, 0.85, 0.05), col.lightened(0.15))
			top = 1.0
		"rug", "runner":
			_box(parts, Vector3(w - 0.2, 0.02, d - 0.2), Vector3(0, 0.011, 0), col)
			_box(parts, Vector3(w - 0.5, 0.022, d - 0.5), Vector3(0, 0.012, 0), light)
			top = 0.03
		"piano":
			_box(parts, Vector3(w - 0.4, 1.2, 0.55), Vector3(0, 0.6, -0.15), col)
			_box(parts, Vector3(w - 0.5, 0.05, 0.25), Vector3(0, 0.74, 0.22), Color("#f2f0ea"))
			top = 1.25
		"picture", "mirror":
			# Hung on the wall behind it (the cell's back edge), at eye height.
			var frame := col if model == "picture" else Color("#d8c8a8")
			_box(parts, Vector3(0.5, 0.42, 0.04), Vector3(0, 1.45, -0.46), frame)
			var inner := Color("#9ec8e0") if model == "mirror" else Color.from_hsv(fmod(float(hash(str(o.get("id", "")))) / 997.0, 1.0), 0.35, 0.85)
			_box(parts, Vector3(0.42, 0.34, 0.01), Vector3(0, 1.45, -0.435), inner, model == "mirror")
			top = 0.05
		"stairs":
			for i in 8:
				_box(parts, Vector3(0.9, 0.3 * (i + 1), d / 8.0), Vector3(0, 0.15 * (i + 1), d / 2.0 - (i + 0.5) * d / 8.0), col if i % 2 == 0 else col.darkened(0.08))
			top = 2.4
		"bench":
			_box(parts, Vector3(w - 0.3, 0.06, 0.45), Vector3(0, 0.45, 0), col)
			_box(parts, Vector3(w - 0.3, 0.35, 0.05), Vector3(0, 0.68, -0.2), col)
			_legs(parts, w - 0.4, 0.4, 0.44, Color("#3a3a3a"), 0.05)
			top = 0.9
		"flowers":
			for i in 5:
				var a := i * TAU / 5.0
				_cyl(parts, 0.015, 0.3, Vector3(cos(a) * 0.18, 0.15, sin(a) * 0.18), Color("#4f8a4a"))
				_ball(parts, 0.07, Vector3(cos(a) * 0.18, 0.32, sin(a) * 0.18), col if i % 2 == 0 else Color("#f2e06a"))
			top = 0.4
		"mailbox":
			_box(parts, Vector3(0.08, 1.0, 0.08), Vector3(0, 0.5, 0), Color("#5a4a3c"))
			_box(parts, Vector3(0.28, 0.25, 0.45), Vector3(0, 1.1, 0), col)
			_box(parts, Vector3(0.03, 0.15, 0.06), Vector3(0.16, 1.2, 0.1), Color("#d84a4a"))
			top = 1.25
		"tree":
			_cyl(parts, 0.12, 1.4, Vector3(0, 0.7, 0), Color("#6a4a32"))
			_ball(parts, 0.7, Vector3(0, 1.9, 0), col)
			_ball(parts, 0.5, Vector3(0.3, 2.3, 0.1), col.lightened(0.12))
			top = 2.6
		"bush":
			_ball(parts, 0.42, Vector3(0, 0.38, 0), col)
			_ball(parts, 0.3, Vector3(0.2, 0.55, 0.1), col.lightened(0.1))
			top = 0.8
		"car":
			_box(parts, Vector3(w - 0.1, 0.5, 0.85), Vector3(0, 0.45, 0), col)
			_box(parts, Vector3(w * 0.5, 0.4, 0.8), Vector3(-0.1, 0.9, 0), Color("#a8c8e0"))
			for wx in [-0.6, 0.6]:
				for wz in [-0.42, 0.42]:
					_cyl(parts, 0.2, 0.12, Vector3(wx, 0.2, wz), Color("#222222")).rotation.x = PI / 2.0
			top = 1.1
		_:
			_box(parts, Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), col)
	# Keep saved ids, footprints, picking and editor rotation; replace only the visible model.
	var licensed := preload("res://scripts/world/licensed_props.gd").build(model, str(o.get("color", "")))
	if licensed:
		for child in parts.get_children():
			child.free()
		parts.add_child(licensed)
		if model == "streetlamp":
			top = 2.8
	if ghost:
		for m in parts.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).transparency = 0.6
	# Something to click (and, when it blocks, to bump into).
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_OBJECTS
	body.collision_mask = 0
	body.set_meta("kind", "object")
	body.set_meta("id", str(o.get("id", "")))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(0.3, w - 0.1), maxf(0.1, top), maxf(0.3, d - 0.1))
	shape.shape = box
	shape.position = Vector3(0, maxf(0.1, top) / 2.0, 0)
	body.add_child(shape)
	root.add_child(body)
	root.rotation.y = -float(o.get("rot", 0)) * PI / 2.0
	root.set_meta("top", top)
	return root
