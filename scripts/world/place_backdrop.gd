extends Node3D
## What surrounds a place (places.gd): outdoors the ground goes on to the horizon; beyond a joined
## edge the next place's own ground carries on, with a soft glowing strip and its name, so two
## places read as one land; up to three silhouette layers stand around it at different distances
## (they drift past each other as the camera moves: parallax); and the sky (a gradient that can
## follow the time of day). Indoors with the plain background, nothing is added.

const Places := preload("res://scripts/world/places.gd")
const SilhouettePainter := preload("res://scripts/world/silhouette_painter.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")

const LAYER_RADIUS := {1: 26.0, 2: 40.0, 3: 56.0}
const GROUND_REACH := 70.0
const SKY_PRESETS := {
	"day": ["#5d9ad8", "#cfe6f5", "#8fb3c9"],
	"dusk": ["#3b2f6b", "#f2a07b", "#6b4a6e"],
	"night": ["#0b1030", "#2b2f5c", "#141632"],
	"dream": ["#2a1a5e", "#c9a0e8", "#3a2a6e"],
	"void": ["#05030c", "#1a1033", "#05030c"],
}

var room: Dictionary = {}
var layers_built := 0            # (tests read these)
var strips_built: Array = []     # sides with a carried-on neighbour ground
var has_ground := false
var _labels: Array = []


## Builds everything for `r`. `neighbours` maps side -> that place's data (for joined edges).
func build(r: Dictionary, neighbours: Dictionary = {}) -> void:
	for c in get_children():
		c.free()
	room = r
	layers_built = 0
	strips_built = []
	has_ground = false
	_labels.clear()
	var bg := Places.background(r)
	var w := float(r.get("size", {}).get("w", 12))
	var d := float(r.get("size", {}).get("d", 10))
	var center := Vector3(w / 2.0, 0, d / 2.0)
	var floor_color := Color.from_string(str(r.get("floor", {}).get("color", "#5b4b8a")), Color("#5b4b8a"))
	if bool(bg.ground):
		var gc := Color.from_string(str(bg.ground_color), floor_color.darkened(0.12)) if str(bg.ground_color) != "" else floor_color.darkened(0.12)
		var ground := _plane(center + Vector3(0, -0.04, 0), Vector2(w + GROUND_REACH * 2.0, d + GROUND_REACH * 2.0), gc, "Ground")
		_give_land_detail(ground)
		has_ground = true
	for side in Places.edges(r):
		var other: Dictionary = neighbours.get(side, {})
		_edge(side, other, w, d)
	var sky_col: Color = _sky_colors(str(bg.sky), 12.0)[1] if str(bg.sky) != "room" else Color.from_string(str(r.get("sky", {}).get("color", "#120e24")), Color("#120e24"))
	for l in bg.layers:
		var dist := int(l.distance)
		var col := Color.from_string(str(l.color), Color("#4f7a5c"))
		col = col.lerp(sky_col, 0.12 * (dist - 1))   # farther = a little hazier
		_ring(center, float(LAYER_RADIUS.get(dist, 40.0)), SilhouettePainter.texture(str(l.kind), col, int(l.seed)), str(l.kind))
		layers_built += 1


## A flat coloured plane (unshaded edges would look cut out; it takes the light like the floor).
func _plane(pos: Vector3, size: Vector2, color: Color, node_name: String) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Open land instead of a flat sheet of colour: soft patches and tufts in the ground's own colour
## (surface_detail.gd "ground"), laid out in the world so it lines up across planes.
func _give_land_detail(plane: MeshInstance3D) -> void:
	var mat := plane.material_override as StandardMaterial3D
	var tex: Texture2D = preload("res://scripts/world/surface_detail.gd").texture("ground")
	if mat == null or tex == null:
		return
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.25   # the picture covers four metres
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS


## Beyond a joined edge: the next place's ground (its floor colour, as wide as it is), a glow along
## the join and its name, so you can see where it leads.
func _edge(side: String, other: Dictionary, w: float, d: float) -> void:
	var oc := Color.from_string(str(other.get("floor", {}).get("color", "#6a9a5b")), Color("#6a9a5b"))
	var ow := float(other.get("size", {}).get("w", w))
	var od := float(other.get("size", {}).get("d", d))
	var reach := 9.0
	var pos := Vector3.ZERO
	var size := Vector2.ZERO
	var glow_pos := Vector3.ZERO
	var glow_size := Vector2.ZERO
	match side:
		"east":
			size = Vector2(minf(ow, reach), od)
			pos = Vector3(w + size.x / 2.0, -0.02, d / 2.0)
			glow_pos = Vector3(w - 0.15, 0.02, d / 2.0)
			glow_size = Vector2(0.3, d)
		"west":
			size = Vector2(minf(ow, reach), od)
			pos = Vector3(-size.x / 2.0, -0.02, d / 2.0)
			glow_pos = Vector3(0.15, 0.02, d / 2.0)
			glow_size = Vector2(0.3, d)
		"north":
			size = Vector2(ow, minf(od, reach))
			pos = Vector3(w / 2.0, -0.02, -size.y / 2.0)
			glow_pos = Vector3(w / 2.0, 0.02, 0.15)
			glow_size = Vector2(w, 0.3)
		"south":
			size = Vector2(ow, minf(od, reach))
			pos = Vector3(w / 2.0, -0.02, d + size.y / 2.0)
			glow_pos = Vector3(w / 2.0, 0.02, d - 0.15)
			glow_size = Vector2(w, 0.3)
	var strip := _plane(pos, size, oc, "Beyond_" + side)
	_give_land_detail(strip)
	strip.set_meta("side", side)
	strips_built.append(side)
	# Clicking or tapping the ground beyond the join walks you there (player_controller.gd: "edge").
	var hit := BlockFactory.body(Vector3(size.x, 0.1, size.y), pos + Vector3(0, -0.03, 0), BlockFactory.LAYER_WORLD, {"kind": "edge", "side": side})
	hit.name = "EdgeHit_" + side
	add_child(hit)
	var glow := _plane(glow_pos, glow_size, Color("#ffd166"), "Join_" + side)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color("#ffd166", 0.55)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material_override = gm
	var label := Label3D.new()
	label.text = {"east": "%s  →", "west": "←  %s", "north": "↑  %s", "south": "↓  %s"}[side] % str(other.get("name", "Next place"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.01
	label.modulate = Color("#fff3d6")
	label.outline_modulate = Color("#120e24")
	label.outline_size = 10
	label.no_depth_test = false
	label.position = glow_pos + Vector3(0, 1.4, 0) + {"east": Vector3(0.6, 0, 0), "west": Vector3(-0.6, 0, 0), "north": Vector3(0, 0, -0.6), "south": Vector3(0, 0, 0.6)}[side]
	label.name = "JoinLabel_" + side
	add_child(label)
	_labels.append(label)


## One silhouette layer: an open cylinder around the place, picture on the inside.
func _ring(center: Vector3, radius: float, tex: Texture2D, kind: String) -> void:
	var height := radius * 0.42
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 48
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	var repeats := maxf(1.0, roundf(TAU * radius / 70.0))
	mat.uv1_scale = Vector3(repeats, 1, 1)
	mat.texture_repeat = true
	var mi := MeshInstance3D.new()
	mi.name = "Layer_" + kind
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = center + Vector3(0, height / 2.0 - 1.5, 0)
	add_child(mi)


## [top, horizon, ground] colours for a sky preset; "auto" follows the hour.
static func _sky_colors(preset: String, hour: float) -> Array:
	var key := preset
	if preset == "auto":
		var h := fposmod(hour, 24.0)
		key = "night" if (h < 5.5 or h >= 21.0) else ("dusk" if (h < 7.5 or h >= 18.0) else "day")
	var p: Array = SKY_PRESETS.get(key, SKY_PRESETS.day)
	return [Color(p[0]), Color(p[1]), Color(p[2])]


## The Environment's sky for a place (null = keep the plain colour or picture).
## The place's sky gradient at this hour: [top, horizon, ground], or [] for a plain-colour ("room") sky.
static func sky_colors(r: Dictionary, hour: float) -> Array:
	var preset := str(Places.background(r).sky)
	if preset == "room":
		return []
	return _sky_colors(preset, hour)


## Puts a gradient on a sky material (game_world.gd keeps one and reuses it: see apply_backdrop).
static func paint_sky(mat: ProceduralSkyMaterial, c: Array) -> void:
	mat.sky_top_color = c[0]
	mat.sky_horizon_color = c[1]
	mat.ground_horizon_color = c[1]
	mat.ground_bottom_color = c[2]
	mat.sun_angle_max = 0.0
