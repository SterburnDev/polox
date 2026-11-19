extends RefCounted
## The optional Detailed pack: higher-resolution surfaces (2K colour, normal, roughness and ambient
## occlusion maps) and more detailed furniture models, used when Settings > Display > PC graphics >
## Fine-tune > Textures is "Detailed" on a PC (pc_detail.gd). Turn it back and the original look returns.
##
## The pack lives in assets/detail/ (git-ignored: about 130 MB). tools/get_detail_pack.py fetches it
## from Poly Haven (every asset CC0; sources and changes in assets/detail/manifest.json and
## docs/ASSET_CREDITS.md). Without the folder, "Detailed" simply looks like "Sharpest".
## Swapping never touches what's saved: object ids, footprints, collisions and picking come from the
## object, not the model (furniture.gd), so a world looks after itself on every device and setting.
## Tags: [GRAPHICS]

const PcDetail := preload("res://scripts/core/pc_detail.gd")
const DIR := "res://assets/detail/"
const MATERIALS := DIR + "materials/"
const MODELS := DIR + "models/"

static var force := -1   # (tests) 1 = on, 0 = off, -1 = the setting


static func active() -> bool:
	if force >= 0:
		return force == 1
	if not PcDetail.available():
		return false
	var g := preload("res://scripts/core/graphics.gd")
	return PcDetail.level_of("textures", g.pc_tier()) >= 3


static func installed() -> bool:
	return DirAccess.dir_exists_absolute(DIR) and (DirAccess.dir_exists_absolute(MATERIALS) or DirAccess.dir_exists_absolute(MODELS))


## A detailed surface map ("albedo", "normal", "rough" or "ao"), or "" when there is none.
static func material_path(name: String, kind: String) -> String:
	for ext in [".jpg", ".png"]:
		var p: String = MATERIALS + name + "/" + kind + ext
		if ResourceLoader.exists(p):
			return p
	return ""


## The detailed model for a furniture piece, or null.
static func model(name: String) -> PackedScene:
	for ext in [".glb", ".gltf"]:
		var p: String = MODELS + name + "/" + name + ext
		if ResourceLoader.exists(p):
			var r: Resource = load(p)
			if r is PackedScene:
				return r
	return null


## The bounds of every mesh under `node` (in node's space).
static func bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D()
		var p: Node = mi
		while p != null and p != node:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var box := xf * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## Scales and moves `detailed` to fill `target` (the original model's bounds): same footprint, standing
## on the floor, centred, facing the same way. Uniform scale, so nothing looks squashed.
static func fit(detailed: Node3D, target: AABB) -> Node3D:
	var holder := Node3D.new()
	holder.add_child(detailed)
	var b := bounds(detailed)
	if b.size.x <= 0.0001 or b.size.z <= 0.0001 or target.size.x <= 0.0001:
		return holder
	var k := minf(minf(target.size.x / b.size.x, target.size.z / b.size.z), target.size.y / maxf(b.size.y, 0.0001) * 1.15)
	detailed.scale = Vector3.ONE * k
	var c := b.get_center() * k
	detailed.position = Vector3(target.get_center().x - c.x, target.position.y - b.position.y * k, target.get_center().z - c.z)
	return holder
