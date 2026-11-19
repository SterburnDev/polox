extends RefCounted
## Desktop lighting and a session-only step down for sustained slow frames.
##
## The PC preset (Auto, High, Ultra, Off) is a tier: 0 (Off), 1 (High), 2 (Ultra). Each feature can also
## be set on its own in Settings > Display > PC graphics > Fine-tune ("pc_graphics" in the settings);
## a feature left on "Same as preset" (-1) follows the tier, so the presets behave as they always have.
##   lighting      0 basic, 1 soft (ambient occlusion and bounce light), 2 global (SDFGI: light bounces
##                 off whatever you place, updated live, nothing baked)
##   shadows       0 low, 1 medium, 2 high (4 sun splits, sharper atlas, softer edges), 3 ultra (lamps
##                 cast shadows too, the nearest few within a budget)
##   reflections   0 off, 1 streets and glass under the sky, 2 everywhere (screen-space)
##   atmosphere    0 clear, 1 Dream World mist outdoors, 2 light shafts (volumetric fog everywhere)
##   textures      0 standard, 1 sharp, 2 sharpest (anisotropic filtering), 3 detailed (also the
##                 Detailed surfaces pack, surface_materials.gd)
##   model_detail  0 light, 1 normal, 2 full (how soon distant models use simpler versions)
##   render_scale  50..100 (% of the screen's pixels for the 3D world; FSR 2 sharpens below 100)
## Phones and the browser never use any of this (available()).
## Tags: [PLATFORM] [GRAPHICS]

const Device := preload("res://scripts/core/device.gd")
const CHOICES := [["auto", "Auto"], ["high", "High"], ["ultra", "Ultra"], ["off", "Off"]]
const FRAME_BUDGET_MS := 20.0
const SAMPLE_SECONDS := 2.0
const SETTLE_SECONDS := 4.0

## feature: [the label, the levels' names]. Order is the Fine-tune list's order.
const FEATURES := {
	"lighting": ["Lighting", ["Basic", "Soft", "Global"]],
	"shadows": ["Shadows", ["Low", "Medium", "High", "Ultra"]],
	"reflections": ["Reflections", ["Off", "Under the sky", "Everywhere"]],
	"atmosphere": ["Atmosphere", ["Clear", "Mist outdoors", "Light shafts"]],
	"textures": ["Textures", ["Standard", "Sharp", "Sharpest", "Detailed"]],
	"model_detail": ["Model detail", ["Light", "Normal", "Full"]],
}
## What each one does, in a line (Settings shows it under the choice).
const EXPLAIN := {
	"lighting": "Soft adds contact shadows and bounce light. Global lets light bounce off what you place, live.",
	"shadows": "High: crisper sun shadows. Ultra: the nearest lamps cast shadows too.",
	"reflections": "Glass, water and wet streets reflect what's around them.",
	"atmosphere": "Mist in the Dream World; light shafts make lamp and sun light visible in the air.",
	"textures": "Sharper surfaces at an angle. Detailed uses the high-resolution surface pack.",
	"model_detail": "Full keeps distant models detailed; Light simplifies them sooner.",
	"render_scale": "Below 100% the world is drawn smaller and sharpened up: faster, a little softer. Menus stay sharp.",
}
const LAMP_SHADOW_BUDGET := 4     # lamps casting shadows at once (the nearest to the camera)
const LAMP_GROUP := "polox_lamp"

static var limit := 2
static var _settle := SETTLE_SECONDS
static var _elapsed := 0.0
static var _cost := 0.0


static func available(handheld: bool = Device.is_handheld(), web: bool = Device.is_web()) -> bool:
	return not handheld and not web


static func tier(settings: Dictionary, handheld: bool = Device.is_handheld(), web: bool = Device.is_web(), server: bool = false, pressure: int = 0) -> int:
	if not available(handheld, web) or server or pressure > 0 or str(settings.get("graphics", "auto")) in ["balanced", "saver"]:
		return 0
	match str(settings.get("pc_detail", "auto")):
		"off":
			return 0
		"ultra":
			return mini(2, limit)
	return mini(1, limit)


## The fine-tune choices saved in `settings` (feature -> level, -1 or missing = the preset's).
static func overrides(settings: Dictionary = {}) -> Dictionary:
	var s: Dictionary = settings if not settings.is_empty() else _game_settings()
	return s.get("pc_graphics", {}) if s.get("pc_graphics") is Dictionary else {}


static func _game_settings() -> Dictionary:
	var gs: Variant = Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() is SceneTree else null
	return gs.settings if gs and gs.get("settings") is Dictionary else {}


## A feature's level for the preset tier alone.
static func preset_level(feature: String, level: int) -> int:
	match feature:
		"lighting", "textures":
			return clampi(level, 0, 2)
		"shadows":
			return [0, 1, 2][clampi(level, 0, 2)]
		"reflections", "atmosphere":
			return 1 if level == 2 else 0
		"model_detail":
			return 2 if level == 2 else 1
	return 0


## A feature's level now: the fine-tune choice, or the preset's. Off (tier 0) turns everything off,
## except a texture or model choice made on purpose (they cost little).
static func level_of(feature: String, level: int, settings: Dictionary = {}) -> int:
	var o: Variant = overrides(settings).get(feature, -1)
	var chosen := int(o) if (o is int or o is float) else -1
	if chosen < 0:
		return preset_level(feature, level)
	if level == 0 and not feature in ["textures", "model_detail"]:
		return 0
	var names: Array = FEATURES[feature][1]
	return clampi(chosen, 0, names.size() - 1)


static func render_scale(settings: Dictionary = {}) -> float:
	var o: Variant = overrides(settings).get("render_scale", 100)
	return clampf(float(o) if (o is int or o is float) else 100.0, 50.0, 100.0) / 100.0


static func custom(settings: Dictionary = {}) -> bool:
	for k in overrides(settings):
		var v: Variant = overrides(settings)[k]
		if (k == "render_scale" and float(v) < 100.0) or (k != "render_scale" and int(v) >= 0):
			return true
	return false


static func reset() -> void:
	limit = 2
	settle()


static func settle() -> void:
	_settle = SETTLE_SECONDS
	_elapsed = 0.0
	_cost = 0.0


## Ignore loading, focus throttling and intentionally slow caps. A slow GPU can lower
## detail twice; raising it again needs an explicit selection in Settings.
static func observe(frame_ms: float, seconds: float, active: bool, current_tier: int) -> bool:
	if not active or current_tier == 0 or seconds <= 0.0 or frame_ms > 250.0:
		settle()
		return false
	if _settle > 0.0:
		_settle -= seconds
		return false
	_elapsed += seconds
	_cost += frame_ms * seconds
	if _elapsed < SAMPLE_SECONDS:
		return false
	var slow := _cost / _elapsed > FRAME_BUDGET_MS
	_elapsed = 0.0
	_cost = 0.0
	if slow:
		limit = current_tier - 1
		settle()
		return true
	return false


static func apply_viewport(viewport: Viewport, level: int) -> void:
	# MSAA keeps the little sprite faces sharp when the camera moves.
	var tex := level_of("textures", level)
	viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_16X if tex >= 2 else (Viewport.ANISOTROPY_8X if tex == 1 else Viewport.ANISOTROPY_4X)
	viewport.mesh_lod_threshold = [4.0, 1.0, 0.0][level_of("model_detail", level)]
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	var scale := render_scale()
	if not is_equal_approx(viewport.scaling_3d_scale, scale):
		viewport.scaling_3d_scale = scale
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if forward and scale < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
	var sh := level_of("shadows", level)
	viewport.positional_shadow_atlas_size = 8192 if sh >= 3 else 4096
	RenderingServer.directional_shadow_atlas_set_size(8192 if sh >= 3 else 4096, true)
	var q: int = [RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sh]
	RenderingServer.directional_soft_shadow_filter_set_quality(q)
	RenderingServer.positional_soft_shadow_filter_set_quality(q)


static func apply_env(env: Environment, level: int, open_sky: bool, dark_outdoors: bool) -> void:
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	var light := level_of("lighting", level)
	var refl := level_of("reflections", level)
	var air := level_of("atmosphere", level)
	env.ssao_enabled = forward and light > 0
	env.ssil_enabled = forward and light > 0
	env.sdfgi_enabled = forward and light >= 2
	env.ssr_enabled = forward and ((refl == 1 and open_sky) or refl >= 2)
	env.volumetric_fog_enabled = forward and ((air == 1 and dark_outdoors) or air >= 2)
	env.ssao_radius = 0.65
	env.ssao_intensity = 0.9
	env.ssao_power = 1.2
	env.ssao_detail = 0.35
	env.ssil_radius = 2.0
	env.ssil_intensity = 0.45
	env.ssr_max_steps = 48 if refl >= 2 else 32
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	# Global light: short cascades fit a room or a street; it follows the camera and updates as you build.
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = open_sky
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.1
	env.sdfgi_energy = 0.8
	env.sdfgi_bounce_feedback = 0.4
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	if air >= 2 and not dark_outdoors:
		# Light shafts: a faint, clean haze the lamps and the sun light up (the Dream World keeps its mist).
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_albedo = Color("#ffffff")
		env.volumetric_fog_ambient_inject = 0.05
		env.volumetric_fog_anisotropy = 0.55
		env.volumetric_fog_length = 24.0
	else:
		env.volumetric_fog_density = 0.008
		env.volumetric_fog_length = 36.0
		env.volumetric_fog_albedo = Color("#aaa0d4")
		env.volumetric_fog_ambient_inject = 0.3
		env.volumetric_fog_anisotropy = 0.2


static func apply_sun(sun: DirectionalLight3D, level: int) -> void:
	var sh := level_of("shadows", level)
	sun.light_angular_distance = 0.35 if level > 0 and sh >= 1 else 0.0
	if sh >= 2 and level > 0 and sun.shadow_enabled:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_volumetric_fog_energy = 1.5 if level > 0 and level_of("atmosphere", level) >= 2 else 1.0


## Lamps (furniture.gd, the Dream Gate): at Ultra shadows the nearest few cast soft shadows; with light
## shafts they light up the haze. Called when a room is shown and every second or so while you move.
static func apply_lamps(tree: SceneTree, level: int, near: Vector3) -> int:
	if tree == null:
		return 0
	var lamps: Array = tree.get_nodes_in_group(LAMP_GROUP)
	var shadows := level > 0 and level_of("shadows", level) >= 3
	var shafts := level > 0 and level_of("atmosphere", level) >= 2
	lamps.sort_custom(func(a, b): return a.global_position.distance_squared_to(near) < b.global_position.distance_squared_to(near))
	var lit := 0
	for l in lamps:
		var light := l as Light3D
		if light == null or not light.is_inside_tree():
			continue
		var on := shadows and lit < LAMP_SHADOW_BUDGET
		light.shadow_enabled = on
		light.light_size = 0.12 if on else 0.0
		light.shadow_blur = 1.5
		light.light_volumetric_fog_energy = 2.0 if shafts else 1.0
		if on:
			lit += 1
	return lit
