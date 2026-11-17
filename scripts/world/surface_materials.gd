extends RefCounted
## Real surfaces for the Light World (your real home and street): wood floors, tiles, carpet, concrete,
## plaster walls, brick, roof tiles, asphalt and grass, from Poly Haven's CC0 scans (assets/materials/,
## made by tools/blender_scripts/prepare_materials.py: 512 px, ambient occlusion in the colour). They add
## the grain, grout and weave; the colour stays the one your home has: a shader divides each texture by
## its own average (its last mipmap, read the same way as the texture, so it holds on every renderer).
## Battery saver draws plain colours instead.
## Tags: [GRAPHICS]

const Graphics := preload("res://scripts/core/graphics.gd")
const DIR := "res://assets/materials/"
const DetailPack := preload("res://scripts/world/detail_pack.gd")
## name: [metres one picture covers, how strongly its pattern shows, normal map strength]
const LOOK := {
	"wood": [2.0, 1.0, 0.6], "planks": [1.8, 1.0, 0.7], "tile": [1.2, 0.45, 0.5], "carpet": [0.6, 0.35, 0.8],
	"concrete": [2.5, 0.8, 0.5], "plaster": [2.0, 0.5, 0.25], "brick": [1.0, 0.9, 0.8], "roof": [1.0, 1.0, 0.8],
	"asphalt": [3.0, 1.0, 0.6], "grass": [1.5, 1.0, 0.7],
	"ceramic": [1.1, 0.7, 0.55],   # (Poly Haven long_white_tiles: glazed white tiles, the Dream Gate's apron and tiled floors)
}
## One surface on any face of a box: a world projection along the face's main axis, the texture's
## pattern over the colour, its bumps.
const SURFACE_SHADER := """
shader_type spatial;
uniform vec4 color : source_color = vec4(1.0);
uniform sampler2D surface_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float surface_scale = 0.5;
uniform float surface_strength = 1.0;
uniform float surface_bump = 0.5;
uniform float surface_rough = 0.9;
// The Detailed pack (detail_pack.gd) adds roughness and ambient-occlusion maps; 0 = not used.
uniform sampler2D surface_rmap : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float surface_maps = 0.0;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bool flat_face = abs(NORMAL.y) > 0.9;
	TANGENT = flat_face ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
	BINORMAL = flat_face ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec3 n = abs(wnorm);
	vec2 uv = (n.y > 0.5 ? wpos.xz : (n.x > n.z ? wpos.zy : wpos.xy)) * surface_scale;
	float avg = max(dot(textureLod(surface_tex, vec2(0.5), 12.0).rgb, LUMA), 0.01);
	float shade = mix(1.0, dot(texture(surface_tex, uv).rgb, LUMA) / avg, surface_strength);
	ALBEDO = color.rgb * clamp(shade, 0.25, 2.0);
	NORMAL_MAP = texture(surface_nrm, uv).rgb;
	NORMAL_MAP_DEPTH = surface_bump;
	ROUGHNESS = mix(surface_rough, texture(surface_rmap, uv).r, surface_maps);
	AO = mix(1.0, texture(surface_ao, uv).r, surface_maps);
	AO_LIGHT_AFFECT = 0.4 * surface_maps;
}
"""

static var _info: Dictionary = {}
static var _tex: Dictionary = {}
static var _mats: Dictionary = {}
static var _shader: Shader


## Off in Battery saver (and if the files are missing): callers draw plain colours then.
static func enabled() -> bool:
	return not mobile_safe() and Graphics.quality() != "saver" and not info().is_empty()


## Keep Android's house rendering off the scanned-surface/normal-map shaders.
## The explicit flag exercises this same path in desktop rendered checks.
static func mobile_safe() -> bool:
	return Graphics.mobile_safe_renderer()


static func info() -> Dictionary:
	if _info.is_empty():
		var f := FileAccess.open(DIR + "materials.json", FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_info = d
	return _info


static func has(name: String) -> bool:
	return info().has(name) and LOOK.has(name)


static func albedo(name: String) -> Texture2D:
	return _load(name, "albedo")


static func normal(name: String) -> Texture2D:
	return _load(name, "normal")


static func _load(name: String, kind: String) -> Texture2D:
	var hd := DetailPack.active()
	var key := ("hd:" if hd else "") + name + "/" + kind
	if not _tex.has(key):
		var path := DetailPack.material_path(name, kind) if hd else ""
		if path == "":
			path = DIR + name + "/" + kind + ".jpg"
		_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _tex[key]


static func roughness(name: String) -> float:
	return float(info().get(name, {}).get("roughness", 0.9))


## Sets a shader's "<slot>_tex", "<slot>_nrm", "<slot>_scale", "<slot>_strength" and "<slot>_bump"
## uniforms for a material (strength 0 = draw the plain colour).
static func bind(mat: ShaderMaterial, slot: String, name: String) -> void:
	var on := enabled() and has(name) and albedo(name) != null
	var look: Array = LOOK.get(name, [1.0, 0.0, 0.0])
	mat.set_shader_parameter(slot + "_strength", float(look[1]) if on else 0.0)
	mat.set_shader_parameter(slot + "_bump", float(look[2]) if on else 0.0)
	if not on:
		return
	mat.set_shader_parameter(slot + "_tex", albedo(name))
	mat.set_shader_parameter(slot + "_nrm", normal(name))
	mat.set_shader_parameter(slot + "_scale", 1.0 / float(look[0]))
	# The Detailed pack's roughness and occlusion maps, when it's on and has them.
	var rmap := DetailPack.material_path(name, "rough") if DetailPack.active() else ""
	var ao := DetailPack.material_path(name, "ao") if DetailPack.active() else ""
	mat.set_shader_parameter(slot + "_maps", 1.0 if rmap != "" and ao != "" else 0.0)
	if rmap != "" and ao != "":
		mat.set_shader_parameter(slot + "_rmap", load(rmap))
		mat.set_shader_parameter(slot + "_ao", load(ao))


## A material in `color` with this surface on it (any face of a box, by metres), or null when surfaces
## are off. Shared per surface and colour.
static func standard(name: String, color: Color) -> ShaderMaterial:
	if not enabled() or not has(name) or albedo(name) == null:
		return null
	var key := ("hd:" if DetailPack.active() else "") + name + "|" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	if _mats.size() >= 64:
		_mats.clear()   # (rooms already drawn keep theirs)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SURFACE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("color", color)
	bind(m, "surface", name)
	m.set_shader_parameter("surface_rough", roughness(name))
	_mats[key] = m
	return m
