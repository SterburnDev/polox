extends Node3D
## A house's thin walls, standing on the cell lines (place field "edge_walls", home_places.gd), with
## doors (a gap with the door standing open), windows (glass between a sill and a header) and the
## front door; plus the rooms' own floors ("floor_areas"). All walls are one mesh, coloured per wall, so a
## whole floor of a house is a couple of draw calls on a phone. Walls between the camera and you are cut
## down to a low edge (like looking into a doll's house), so you always see where you are.

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 player_pos = vec3(0.0);
uniform vec3 cam_flat = vec3(0.0, 0.0, -1.0);
uniform float cut_height = 0.45;
uniform float cut_on = 1.0;
uniform vec2 reveal_center = vec2(0.0);
uniform float reveal_r = 1000000.0;
uniform float sway = 0.0;
uniform sampler2D plaster_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D plaster_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float plaster_scale = 0.5;
uniform float plaster_strength = 0.0;
uniform float plaster_bump = 0.0;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = NORMAL;
	bool flat_face = abs(NORMAL.y) > 0.9;
	TANGENT = flat_face ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
	BINORMAL = flat_face ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	if (sway > 0.0) {
		float k = clamp((2.1 - wpos.y) / 1.25, 0.0, 1.0);
		VERTEX.x += sin(TIME * 1.3 + wpos.x * 3.0 + wpos.z * 2.0) * 0.035 * k * sway;
		VERTEX.z += cos(TIME * 1.1 + wpos.x * 2.0) * 0.02 * k * sway;
	}
}
void fragment() {
	float ahead = dot(wpos - player_pos, cam_flat);
	if (cut_on > 0.5 && wpos.y > cut_height && ahead < 0.6) {
		discard;
	}
	if (distance(wpos.xz, reveal_center) > reveal_r) {
		discard;
	}
	vec3 c = COLOR.rgb;
	vec3 lin = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	if (plaster_strength > 0.0 && FRONT_FACING) {
		// Painted plaster: the wall's own colour with the plaster's unevenness and its bumps (the outside
		// only: a cut-down wall's inside, seen edge-on, would sparkle).
		vec2 uv = (abs(wnorm.y) > 0.9 ? wpos.xz : vec2(wpos.x + wpos.z, wpos.y)) * plaster_scale;
		lin *= clamp(mix(1.0, dot(texture(plaster_tex, uv).rgb, LUMA) / max(dot(textureLod(plaster_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), plaster_strength), 0.4, 1.6);
		NORMAL_MAP = texture(plaster_nrm, uv).rgb;
		NORMAL_MAP_DEPTH = plaster_bump;
	}
	ALBEDO = lin;
	ROUGHNESS = 0.95;
}
"""
## No texture samplers, tangent reconstruction or normal-map branches on Android.
## Keep the same cutaway and reveal uniforms so creation and navigation still work.
const MOBILE_WALL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 player_pos = vec3(0.0);
uniform vec3 cam_flat = vec3(0.0, 0.0, -1.0);
uniform float cut_height = 0.45;
uniform float cut_on = 1.0;
uniform vec2 reveal_center = vec2(0.0);
uniform float reveal_r = 1000000.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (cut_on > 0.5 && wpos.y > cut_height && dot(wpos - player_pos, cam_flat) < 0.6) { discard; }
	if (distance(wpos.xz, reveal_center) > reveal_r) { discard; }
	ALBEDO = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	ROUGHNESS = 0.95;
}
"""
const MOBILE_FLOOR_SHADER := """
shader_type spatial;
uniform vec2 reveal_center = vec2(0.0);
uniform float reveal_r = 1000000.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (distance(wpos.xz, reveal_center) > reveal_r) { discard; }
	int kind = int(COLOR.a * 8.0);
	float shade = 1.0;
	if (kind == 1 || kind == 4) {
		shade -= 0.08 * step(fract(wpos.z / 0.3), 0.025);
	} else if (kind == 2 || kind == 6) {
		vec2 cell = fract(wpos.xz / 0.6);
		shade -= 0.08 * max(step(cell.x, 0.02), step(cell.y, 0.02));
	}
	ALBEDO = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2)) * shade;
	ROUGHNESS = 0.9;
}
"""
const GLASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never;
uniform vec3 player_pos = vec3(0.0);
uniform vec3 cam_flat = vec3(0.0, 0.0, -1.0);
uniform float cut_height = 0.45;
uniform float cut_on = 1.0;
uniform vec2 reveal_center = vec2(0.0);
uniform float reveal_r = 1000000.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float ahead = dot(wpos - player_pos, cam_flat);
	if (cut_on > 0.5 && wpos.y > cut_height && ahead < 0.6) {
		discard;
	}
	if (distance(wpos.xz, reveal_center) > reveal_r) {
		discard;
	}
	ALBEDO = vec3(0.62, 0.78, 0.9);
	EMISSION = vec3(0.12, 0.16, 0.2);
	ROUGHNESS = 0.1;
	ALPHA = 0.32;
}
"""
## Room floors: the colour from the plan with the material on it. With surfaces on (surface_materials.gd)
## a real texture's grain, grout or weave and its bumps: wood (and vinyl) boards, tile (and stone), carpet,
## concrete. In Battery saver a drawn pattern instead (no textures, so it costs a phone nothing): boards
## with staggered joints, tile or stone with grout, carpet weave, vinyl planks, concrete with saw cuts.
## The material rides in the vertex colour's alpha (FLOOR_CODES).
const FLOOR_SHADER := """
shader_type spatial;
uniform float cut_on = 0.0;
uniform vec2 reveal_center = vec2(0.0);
uniform float reveal_r = 1000000.0;
uniform sampler2D wood_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wood_scale = 0.5;
uniform float wood_strength = 0.0;
uniform float wood_bump = 0.0;
uniform sampler2D tile_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tile_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_scale = 1.0;
uniform float tile_strength = 0.0;
uniform float tile_bump = 0.0;
uniform sampler2D carpet_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D carpet_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float carpet_scale = 1.0;
uniform float carpet_strength = 0.0;
uniform float carpet_bump = 0.0;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float concrete_scale = 0.4;
uniform float concrete_strength = 0.0;
uniform float concrete_bump = 0.0;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}
float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}
void fragment() {
	if (distance(wpos.xz, reveal_center) > reveal_r) {
		discard;
	}
	vec3 c = COLOR.rgb;
	int m = int(COLOR.a * 8.0);
	vec2 p = wpos.xz;
	float shade = 1.0;
	float rough = m == 2 ? 0.55 : 0.92;
	bool textured = true;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float bump = 0.0;
	if ((m == 1 || m == 4) && wood_strength > 0.0) {
		vec2 uv = p * wood_scale * (m == 4 ? 1.4 : 1.0);
		shade = mix(1.0, dot(texture(wood_tex, uv).rgb, LUMA) / max(dot(textureLod(wood_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), wood_strength * (m == 4 ? 0.6 : 1.0));
		nm = texture(wood_nrm, uv).rgb;
		bump = wood_bump;
		rough = 0.55;
	} else if ((m == 2 || m == 6) && tile_strength > 0.0) {
		vec2 uv = p * tile_scale * (m == 6 ? 0.6 : 1.0);
		shade = mix(1.0, dot(texture(tile_tex, uv).rgb, LUMA) / max(dot(textureLod(tile_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), tile_strength);
		nm = texture(tile_nrm, uv).rgb;
		bump = tile_bump;
		rough = m == 2 ? 0.16 : 0.4;   // (tiles are glazed: they shine; stone stays matt)
	} else if (m == 3 && carpet_strength > 0.0) {
		vec2 uv = p * carpet_scale;
		shade = mix(1.0, dot(texture(carpet_tex, uv).rgb, LUMA) / max(dot(textureLod(carpet_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), carpet_strength);
		nm = texture(carpet_nrm, uv).rgb;
		bump = carpet_bump;
		rough = 0.97;
	} else if (m == 5 && concrete_strength > 0.0) {
		vec2 uv = p * concrete_scale;
		shade = mix(1.0, dot(texture(concrete_tex, uv).rgb, LUMA) / max(dot(textureLod(concrete_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), concrete_strength);
		nm = texture(concrete_nrm, uv).rgb;
		bump = concrete_bump;
		rough = 0.8;
	} else {
		textured = false;
	}
	if (textured) {
		vec3 lin = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
		ALBEDO = lin * clamp(shade, 0.25, 2.0);
		NORMAL_MAP = nm;
		NORMAL_MAP_DEPTH = bump;
		ROUGHNESS = rough;
	} else {
		shade = 1.0;
		if (m == 1) {
			float row = floor(p.y / 0.18);
			float off = hash(row) * 1.2;
			float seam = max(step(fract(p.y / 0.18), 0.05), step(fract((p.x + off) / 1.2), 0.012));
			float grain = sin((p.x + row * 1.7) * 19.0 + sin(p.x * 2.3 + row) * 2.5);
			shade = mix(0.95, 1.04, hash(row + 0.5)) * (0.985 + 0.015 * grain) * (1.0 - 0.14 * seam);
		} else if (m == 2 || m == 6) {
			float s = m == 2 ? 0.5 : 0.8;
			vec2 cell = floor(p / s);
			vec2 f = fract(p / s);
			float g = max(step(f.x, 0.035), step(f.y, 0.035));
			shade = mix(0.95, 1.04, hash(cell.x * 7.0 + cell.y * 13.0)) * (1.0 - 0.16 * g);
		} else if (m == 3) {
			shade = 0.97 + 0.05 * hash(floor(p.x * 40.0) + floor(p.y * 40.0) * 57.0);
		} else if (m == 4) {
			float row = floor(p.y / 0.3);
			shade = mix(0.96, 1.03, hash(row)) * (1.0 - 0.08 * step(fract(p.y / 0.3), 0.03));
		} else if (m == 5) {
			shade = 0.96 + 0.06 * hash(floor(p.x * 3.0) + floor(p.y * 3.0) * 31.0);
			shade *= 1.0 - 0.1 * max(step(fract(p.x / 2.0), 0.01), step(fract(p.y / 2.0), 0.01));
		}
		c *= shade;
		ALBEDO = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
		ROUGHNESS = rough;
	}
}
"""
## A street's ground (lawns and parks, the road, pavements and paths) with real grass, asphalt and paving
## over its colours; kept apart from the room floors so neither shader needs many textures on a phone.
## The kind rides in the vertex colour's alpha (STREET_CODES).
const STREET_SHADER := """
shader_type spatial;
uniform vec2 reveal_center = vec2(0.0);
uniform float reveal_r = 1000000.0;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_scale = 0.7;
uniform float grass_strength = 0.0;
uniform float grass_bump = 0.0;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float asphalt_scale = 0.3;
uniform float asphalt_strength = 0.0;
uniform float asphalt_bump = 0.0;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float concrete_scale = 0.4;
uniform float concrete_strength = 0.0;
uniform float concrete_bump = 0.0;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}
void fragment() {
	if (distance(wpos.xz, reveal_center) > reveal_r) {
		discard;
	}
	vec3 c = COLOR.rgb;
	vec3 lin = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	int k = int(COLOR.a * 8.0);
	float shade = 1.0;
	float rough = 0.95;
	if (k == 1 && grass_strength > 0.0) {
		vec2 uv = wpos.xz * grass_scale;
		shade = mix(1.0, dot(texture(grass_tex, uv).rgb, LUMA) / max(dot(textureLod(grass_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), grass_strength);
		NORMAL_MAP = texture(grass_nrm, uv).rgb;
		NORMAL_MAP_DEPTH = grass_bump;
	} else if (k == 2 && asphalt_strength > 0.0) {
		vec2 uv = wpos.xz * asphalt_scale;
		shade = mix(1.0, dot(texture(asphalt_tex, uv).rgb, LUMA) / max(dot(textureLod(asphalt_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), asphalt_strength);
		NORMAL_MAP = texture(asphalt_nrm, uv).rgb;
		NORMAL_MAP_DEPTH = asphalt_bump;
		rough = 0.85;
	} else if (k == 3 && concrete_strength > 0.0) {
		vec2 uv = wpos.xz * concrete_scale;
		shade = mix(1.0, dot(texture(concrete_tex, uv).rgb, LUMA) / max(dot(textureLod(concrete_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), concrete_strength);
		NORMAL_MAP = texture(concrete_nrm, uv).rgb;
		NORMAL_MAP_DEPTH = concrete_bump;
		rough = 0.8;
	}
	ALBEDO = lin * clamp(shade, 0.25, 2.0);
	ROUGHNESS = rough;
}
"""
const STREET_CODES := {"park": 1, "grass": 1, "home_lot": 1, "garden": 1, "woods": 1, "road": 2, "sidewalk": 3, "paved": 3, "path": 3}
## Neighbourhood buildings: their colours as brick walls and tiled roofs (painted brick on a pale house).
const BUILDING_SHADER := """
shader_type spatial;
uniform sampler2D brick_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float brick_scale = 1.0;
uniform float brick_strength = 0.0;
uniform float brick_bump = 0.0;
uniform sampler2D roof_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roof_scale = 1.0;
uniform float roof_strength = 0.0;
uniform float roof_bump = 0.0;
uniform float roof_min_y = 0.5;   // which faces are roof: their normal's height
uniform float roof_max_y = 1.01;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = NORMAL;
	bool flat_face = abs(NORMAL.y) > 0.9;
	TANGENT = flat_face ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
	BINORMAL = flat_face ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec3 c = COLOR.rgb;
	vec3 lin = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	if (wnorm.y > roof_min_y && wnorm.y < roof_max_y && roof_strength > 0.0) {
		vec2 uv = wpos.xz * roof_scale;
		lin *= clamp(mix(1.0, dot(texture(roof_tex, uv).rgb, LUMA) / max(dot(textureLod(roof_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), roof_strength), 0.25, 2.0);
		NORMAL_MAP = texture(roof_nrm, uv).rgb;
		NORMAL_MAP_DEPTH = roof_bump;
	} else if (wnorm.y <= 0.5 && brick_strength > 0.0) {
		vec2 uv = vec2(wpos.x + wpos.z, wpos.y) * brick_scale;
		lin *= clamp(mix(1.0, dot(texture(brick_tex, uv).rgb, LUMA) / max(dot(textureLod(brick_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01), brick_strength), 0.25, 2.0);
		NORMAL_MAP = texture(brick_nrm, uv).rgb;
		NORMAL_MAP_DEPTH = brick_bump;
	}
	ALBEDO = lin;
	ROUGHNESS = 0.9;
}
"""
const SurfaceMaterials := preload("res://scripts/world/surface_materials.gd")
const FLOOR_CODES := {"wood": 1, "tile": 2, "carpet": 3, "vinyl": 4, "concrete": 5, "stone": 6}
const HoodRender := preload("res://scripts/world/hood_render.gd")
const T := 0.1                # wall thickness (m)
const SKIRT := 0.09           # skirting board height (m)
const DOOR_H := 2.05
const SILL := 0.9
const HEAD := 2.0

static var _shader: Shader
static var _glass_shader: Shader
static var _floor_shader: Shader
static var _building_shader: Shader
static var _street_shader: Shader

var count := 0               # walls drawn (tests)
var doors := 0
var windows := 0
var walls_mat: ShaderMaterial
var glass_mat: ShaderMaterial
var curtain_mat: ShaderMaterial
var floor_mat: ShaderMaterial
var street_mat: ShaderMaterial    # a street's lawns, road and pavements
var curtains := 0             # (tests) curtain panels hung
var _walls_mesh: MeshInstance3D
var _glass: MeshInstance3D
var _floors: MeshInstance3D


func clear() -> void:
	for c in get_children():
		c.queue_free()
	count = 0
	doors = 0
	windows = 0
	buildings = 0
	curtains = 0
	curtain_mat = null
	walls_mat = null
	glass_mat = null
	floor_mat = null
	street_mat = null
	_walls_mesh = null
	_glass = null
	_floors = null


func build(room: Dictionary, h: float) -> void:
	clear()
	_build_floors(room.get("floor_areas", []))
	_build_buildings(room.get("buildings", []))
	if room.has("hood"):
		# A street's small things (curbs, crossings, fences, roofs, windows): one more mesh per block.
		var detail := HoodRender.build(room)
		if detail:
			_roof_tiles(detail)
			add_child(detail)
	var edges: Array = room.get("edge_walls", []) if room.get("edge_walls") is Array else []
	if edges.is_empty():
		return
	h = clampf(h, 2.2, 4.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_glass := false
	var cur := SurfaceTool.new()
	cur.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in edges:
		if not e is Dictionary:
			continue
		var x := float(e.get("x", 0))
		var z := float(e.get("z", 0))
		var horiz := str(e.get("dir", "h")) == "h"
		var col_a := Color.from_string(str(e.get("color_a", e.get("color", "#efe6d8"))), Color("#efe6d8"))
		var col_b := Color.from_string(str(e.get("color_b", e.get("color", "#efe6d8"))), Color("#efe6d8"))
		var center := Vector3(x + 0.5, 0.0, z) if horiz else Vector3(x, 0.0, z + 0.5)
		if bool(e.get("door", false)):
			doors += 1
			_wall(st, center, horiz, DOOR_H, h, col_a, col_b)
			# The door, standing open along the wall's normal.
			var leaf := Color("#7a4a32") if bool(e.get("front", false)) else Color("#c8a882")
			var hinge := Vector3(x + 0.08, 0, z) if horiz else Vector3(x, 0, z + 0.08)
			var normal := Vector3(0, 0, 1) if horiz else Vector3(1, 0, 0)
			_box(st, hinge + normal * 0.42 + Vector3(0, DOOR_H / 2.0 - 0.02, 0), Vector3(0.04, DOOR_H - 0.06, 0.84) if horiz else Vector3(0.84, DOOR_H - 0.06, 0.04), leaf)
		elif bool(e.get("window", false)):
			windows += 1
			_wall(st, center, horiz, 0.0, SILL, col_a, col_b)
			_wall(st, center, horiz, HEAD, h, col_a, col_b)
			_box(st, center + Vector3(0, SILL + 0.02, 0), Vector3(1.0 + T if horiz else T + 0.08, 0.04, T + 0.08 if horiz else 1.0 + T), Color("#f6f2ea"))
			_box(glass, center + Vector3(0, (SILL + HEAD) / 2.0, 0), Vector3(1.0 if horiz else 0.03, HEAD - SILL, 0.03 if horiz else 1.0), Color(0.72, 0.86, 0.95, 0.35))
			has_glass = true
			if bool(e.get("outer", false)) and e.has("inside"):
				# Curtains on the inside, either side of the window.
				var inward := -1.0 if str(e.inside) == "a" else 1.0
				var wall_in := col_a if str(e.inside) == "a" else col_b
				# Fabric that shows against the wall: a dusty rose on pale walls, a lighter weave on dark ones.
				var fabric := wall_in.lerp(Color("#b5675a"), 0.55) if wall_in.get_luminance() > 0.55 else wall_in.lightened(0.4)
				for side in [-0.38, 0.38]:
					var off := Vector3(side, 0, inward * 0.1) if horiz else Vector3(inward * 0.1, 0, side)
					_box(cur, center + off + Vector3(0, 1.48, 0), Vector3(0.22, 1.25, 0.04) if horiz else Vector3(0.04, 1.25, 0.22), fabric)
					curtains += 1
		else:
			_wall(st, center, horiz, 0.0, h, col_a, col_b)
		count += 1
	st.generate_normals()
	_walls_mesh = MeshInstance3D.new()
	_walls_mesh.name = "Walls"
	_walls_mesh.mesh = st.commit()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = MOBILE_WALL_SHADER if SurfaceMaterials.mobile_safe() else SHADER
	walls_mat = ShaderMaterial.new()
	walls_mat.shader = _shader
	SurfaceMaterials.bind(walls_mat, "plaster", "plaster")
	_walls_mesh.material_override = walls_mat
	add_child(_walls_mesh)
	if curtains > 0:
		cur.generate_normals()
		var cm := MeshInstance3D.new()
		cm.name = "Curtains"
		cm.mesh = cur.commit()
		curtain_mat = ShaderMaterial.new()
		curtain_mat.shader = _shader
		curtain_mat.set_shader_parameter("sway", 0.0 if bool(GameState.settings.get("reduce_motion", false)) else 1.0)
		cm.material_override = curtain_mat
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cm)
	if has_glass:
		glass.generate_normals()
		_glass = MeshInstance3D.new()
		_glass.name = "Glass"
		_glass.mesh = glass.commit()
		if _glass_shader == null:
			_glass_shader = Shader.new()
			_glass_shader.code = GLASS_SHADER
		glass_mat = ShaderMaterial.new()
		glass_mat.shader = _glass_shader
		_glass.material_override = glass_mat
		_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_glass)


var buildings := 0          # neighbourhood buildings drawn (tests)


## The neighbourhood's buildings (place field "buildings", hood_builder.gd): each a plain block on its cells
## with a roof that overhangs a little; yours warm. One mesh for the lot.
func _build_buildings(list: Variant) -> void:
	if not list is Array or (list as Array).is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in list:
		if not b is Dictionary:
			continue
		buildings += 1
		var hgt := float(b.get("h", 2.4))
		var wall := Color.from_string(str(b.get("wall", "#e9e1d0")), Color("#e9e1d0"))
		var roof := Color.from_string(str(b.get("roof", "#7a5a46")), Color("#7a5a46"))
		var slab := not HoodRender.pitched(b)   # (a pitched roof is hood_render.gd's)
		# Row runs, so a house is a few boxes, not one per cell.
		var rows := {}
		for c in b.get("cells", []):
			var z := int(c[1])
			if not rows.has(z):
				rows[z] = []
			(rows[z] as Array).append(int(c[0]))
		for z in rows:
			var xs: Array = rows[z]
			xs.sort()
			var start: int = xs[0]
			var prev: int = xs[0]
			for i in range(1, xs.size() + 1):
				var x: int = xs[i] if i < xs.size() else -999
				if x == prev + 1:
					prev = x
					continue
				var w := float(prev - start + 1)
				_box(st, Vector3(start + w / 2.0, hgt / 2.0, z + 0.5), Vector3(w - 0.04, hgt, 0.98), wall)
				if slab:
					_box(st, Vector3(start + w / 2.0, hgt + 0.12, z + 0.5), Vector3(w + 0.16, 0.24, 1.14), roof)
				start = x
				prev = x
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = st.commit()
	if _building_shader == null:
		_building_shader = Shader.new()
		_building_shader.code = BUILDING_SHADER
	var m := ShaderMaterial.new()
	m.shader = _building_shader
	SurfaceMaterials.bind(m, "brick", "brick")
	SurfaceMaterials.bind(m, "roof", "roof")
	mi.material_override = m
	add_child(mi)


## The street detail's pitched roofs in clay tiles (only sloped faces: curbs, crossings, sills and hedge
## tops stay their plain colours). Battery saver keeps the plain material it came with.
func _roof_tiles(detail: MeshInstance3D) -> void:
	if not SurfaceMaterials.enabled():
		return
	if _building_shader == null:
		_building_shader = Shader.new()
		_building_shader.code = BUILDING_SHADER
	var m := ShaderMaterial.new()
	m.shader = _building_shader
	SurfaceMaterials.bind(m, "roof", "roof")
	m.set_shader_parameter("roof_max_y", 0.95)
	detail.material_override = m


func _build_floors(areas: Variant) -> void:
	if not areas is Array or (areas as Array).is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var street := SurfaceTool.new()
	street.begin(Mesh.PRIMITIVE_TRIANGLES)
	var streets := 0
	for a in areas:
		if not a is Dictionary:
			continue
		var r: Array = a.get("rect", [0, 0, 1, 1])
		var c := Color.from_string(str(a.get("color", "#c9a27a")), Color("#c9a27a"))
		var at := Vector3(float(r[0]) + float(r[2]) / 2.0, 0.006, float(r[1]) + float(r[3]) / 2.0)
		var size := Vector3(float(r[2]), 0.012, float(r[3]))
		if not a.has("material") and STREET_CODES.has(str(a.get("kind", ""))):
			c.a = (float(STREET_CODES[str(a.kind)]) + 0.5) / 8.0
			_box(street, at, size, c)
			streets += 1
			continue
		c.a = (float(FLOOR_CODES.get(str(a.get("material", "")), 0)) + 0.5) / 8.0
		_box(st, at, size, c)
	if streets > 0:
		street.generate_normals()
		var ground := MeshInstance3D.new()
		ground.name = "StreetGround"
		ground.mesh = street.commit()
		if _street_shader == null:
			_street_shader = Shader.new()
			_street_shader.code = STREET_SHADER
		street_mat = ShaderMaterial.new()
		street_mat.shader = _street_shader
		for slot in ["grass", "asphalt", "concrete"]:
			SurfaceMaterials.bind(street_mat, slot, slot)
		ground.material_override = street_mat
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ground)
		if streets == (areas as Array).size():
			return
	st.generate_normals()
	_floors = MeshInstance3D.new()
	_floors.name = "RoomFloors"
	_floors.mesh = st.commit()
	if _floor_shader == null:
		_floor_shader = Shader.new()
		_floor_shader.code = MOBILE_FLOOR_SHADER if SurfaceMaterials.mobile_safe() else FLOOR_SHADER
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = _floor_shader
	# [GLASS_UI] Tiled floors (bathrooms, kitchens) are glazed ceramic: Poly Haven's long white tiles.
	for slot in ["wood", "tile", "carpet", "concrete"]:
		SurfaceMaterials.bind(floor_mat, slot, "ceramic" if slot == "tile" else slot)
	_floors.material_override = floor_mat
	_floors.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floors)


## Walls between the camera and you drop to a low edge.
func update(cam_pos: Vector3, player_pos: Vector3) -> void:
	if walls_mat == null:
		return
	var flat := player_pos - cam_pos
	flat.y = 0.0
	if flat.length() < 0.01:
		return
	for m in [walls_mat, glass_mat, curtain_mat]:
		if m:
			m.set_shader_parameter("player_pos", player_pos)
			m.set_shader_parameter("cam_flat", flat.normalized())


## Drawing in (the first look at your home): only what's within `r` of the centre shows.
func set_reveal(center: Vector2, r: float) -> void:
	for m in [walls_mat, glass_mat, curtain_mat, floor_mat, street_mat]:
		if m:
			m.set_shader_parameter("reveal_center", center)
			m.set_shader_parameter("reveal_r", r)


func set_cutaway(on: bool) -> void:
	for m in [walls_mat, glass_mat]:
		if m:
			m.set_shader_parameter("cut_on", 1.0 if on else 0.0)


## A wall from y0 to y1, in two halves: the "a" side (towards smaller x / z) and the "b" side, each in
## its own room's colour.
static func _wall(st: SurfaceTool, center: Vector3, horiz: bool, y0: float, y1: float, col_a: Color, col_b: Color) -> void:
	if y1 - y0 <= 0.01:
		return
	var half := T / 2.0
	var mid := (y0 + y1) / 2.0
	var hgt := y1 - y0
	if horiz:
		_box(st, Vector3(center.x, mid, center.z - half / 2.0), Vector3(1.0, hgt, half), col_a)
		_box(st, Vector3(center.x, mid, center.z + half / 2.0), Vector3(1.0, hgt, half), col_b)
	else:
		_box(st, Vector3(center.x - half / 2.0, mid, center.z), Vector3(half, hgt, 1.0), col_a)
		_box(st, Vector3(center.x + half / 2.0, mid, center.z), Vector3(half, hgt, 1.0), col_b)
	if y0 <= 0.0:
		# A cap just below the fragment cut plane closes the exposed wall at 0.45 m.
		# It stays inside the full wall when cutaway is off.
		_box(st, Vector3(center.x, 0.445, center.z), Vector3(1.0, 0.008, T) if horiz else Vector3(T, 0.008, 1.0), col_a.lerp(col_b, 0.5))
		# Skirting boards along the foot of each side, a pale trim a little proud of the paint.
		var proud := half + 0.012
		for side in [[-1.0, col_a], [1.0, col_b]]:
			var trim: Color = (side[1] as Color).lerp(Color("#fbf7ef"), 0.65)
			if horiz:
				_box(st, Vector3(center.x, SKIRT / 2.0, center.z + float(side[0]) * proud / 2.0), Vector3(1.0, SKIRT, proud), trim)
			else:
				_box(st, Vector3(center.x + float(side[0]) * proud / 2.0, SKIRT / 2.0, center.z), Vector3(proud, SKIRT, 1.0), trim)


## A box into the mesh: centre, size, colour.
static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	# Box corners must not blend normals across perpendicular faces or adjacent walls.
	st.set_smooth_group(-1)
	var hx := s.x / 2.0
	var hy := s.y / 2.0
	var hz := s.z / 2.0
	var p := [Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz),
		Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	# (The faces above are listed anticlockwise seen from outside; Godot's front faces are clockwise.)
	for f in faces:
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(c + p[f[i]])
