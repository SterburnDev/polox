extends RefCounted
## Frame rate and graphics quality, in one place (Settings > Game).
##
## Automatic limits phones to 60 fps; 120 fps is an explicit choice. Balanced
## on phones disables MSAA and dynamic sun shadows to reduce GPU/battery load.
## Desktop detail is separate; explicit frame-rate choices stay as chosen.
## Tags: [PLATFORM] [GRAPHICS]

const Device := preload("res://scripts/core/device.gd")
const AndroidNative := preload("res://scripts/core/android_native.gd")
const PcDetail := preload("res://scripts/core/pc_detail.gd")

const FRAME_RATES := [["auto", "Automatic (60 fps on phones)"], ["120", "120 fps"], ["60", "60 fps"], ["30", "30 fps (saves battery)"]]
const QUALITIES := [["auto", "Automatic"], ["high", "High"], ["balanced", "Balanced"], ["saver", "Battery saver"]]
const SHADOW_DISTANCE_HIGH := 42.0     # blocks: the camera's farthest zoom sees about 30 blocks
const SHADOW_DISTANCE_BALANCED := 30.0
const SHADOW_FADE_START := 0.45

static var last_refresh_request := 0.0   # (tests, the phone's report) what Android was last asked for

## How hard the app has to save memory (memory_guard.gd raises it; it never goes back down in a session):
## 0 = as chosen, 1 = no anti-aliasing at all, 2 = also at most 30 fps, no sun shadows, no glow or colour pass.
## The first step is the one that matters for a driver that keeps allocating around multisampled buffers.
static var pressure := 0


## The old Performance mode setting -> the two new ones (once). True when settings changed.
static func migrate(settings: Dictionary) -> bool:
	if not settings.has("performance_mode"):
		return false
	var old := str(settings.get("performance_mode", "auto"))
	settings.erase("performance_mode")
	if old == "on":
		if not settings.has("graphics"):
			settings["graphics"] = "saver"
		if not settings.has("frame_rate"):
			settings["frame_rate"] = "30"
	elif old == "off" and not settings.has("graphics"):
		settings["graphics"] = "high"
	return true


static func _settings() -> Dictionary:
	return GameState.settings


## "high", "balanced" or "saver" (Automatic resolved for this device).
static func quality(settings: Dictionary = {}) -> String:
	var s := settings if not settings.is_empty() else _settings()
	var q := str(s.get("graphics", "auto"))
	if q in ["high", "balanced", "saver"]:
		return q
	return "balanced" if Device.is_handheld() else "high"


## Engine.max_fps for the chosen frame rate (0 = no cap: the screen's own rate).
static func frame_cap(settings: Dictionary = {}, handheld: bool = Device.is_handheld()) -> int:
	var s := settings if not settings.is_empty() else _settings()
	var cap := 60 if handheld else 0
	match str(s.get("frame_rate", "auto")):
		"120":
			cap = 120
		"60":
			cap = 60
		"30":
			cap = 30
	if pressure >= 2 and (cap == 0 or cap > PRESSURE_FPS):
		cap = PRESSURE_FPS
	return cap


const PRESSURE_FPS := 30   # (the frame rate while the app is short of memory)


static func shadows(settings: Dictionary = {}) -> bool:
	return quality(settings) != "saver" and pressure < 2


## Fewer particles and simpler effects (Battery saver only: the rest look the same everywhere).
static func low_detail(settings: Dictionary = {}) -> bool:
	return quality(settings) == "saver"


static func msaa(settings: Dictionary = {}, handheld: bool = Device.is_handheld()) -> int:
	if pressure >= 1:
		return Viewport.MSAA_DISABLED
	match quality(settings):
		"high":
			return Viewport.MSAA_2X if handheld else Viewport.MSAA_4X
		"balanced":
			return Viewport.MSAA_DISABLED if handheld else Viewport.MSAA_2X
	return Viewport.MSAA_DISABLED


const ANDROID_IDLE_FPS_KEY := "android_idle_fps"
const ANDROID_LOW_3D_KEY := "android_low_3d"
const ANDROID_3D_SCALE := 0.85

## Windows that don't need the screen's full rate: Phone Link's and Ping's server windows always, the game's
## own window on a PC while another window has the focus. Windows doesn't pace a window that another one
## covers, so without a cap Godot draws as fast as it can (Phone Link's window kept a CPU core busy all day).
const QUIET_FPS := 30
static var server_window := false   # main.gd: host and ping modes
static var in_background := false   # main.gd: the game window lost the focus on a PC


static func active_frame_cap(settings: Dictionary = {}) -> int:
	var cap := frame_cap(settings)
	if server_window or in_background:
		cap = QUIET_FPS if cap == 0 else mini(cap, QUIET_FPS)
	return cap


## Frame cap, anti-aliasing and the display's refresh rate (main.gd calls this at start and after
## every settings change). The world's own lights follow with apply_to_world().
static func apply(viewport: Viewport, settings: Dictionary = {}) -> void:
	var cap := active_frame_cap(settings)
	Engine.max_fps = cap
	if viewport:
		viewport.msaa_3d = msaa(settings)
		if OS.has_feature("android"):
			var s := settings if not settings.is_empty() else _settings()
			var lower := bool(s.get(ANDROID_LOW_3D_KEY, false)) and quality(s) != "high"
			var scale := ANDROID_3D_SCALE if lower else 1.0
			if not is_equal_approx(viewport.scaling_3d_scale, scale):
				viewport.scaling_3d_scale = scale
		if PcDetail.available():
			PcDetail.apply_viewport(viewport, pc_tier(settings))
			if server_window:
				viewport.msaa_3d = Viewport.MSAA_DISABLED
	# Ask Android for a display mode to match: the fastest for Automatic, otherwise the cap itself
	# (a 60 fps cap on a 120 Hz screen would otherwise show each frame for an uneven count of refreshes).
	last_refresh_request = 0.0 if cap == 0 else float(cap)
	if AndroidNative.available():
		last_refresh_request = AndroidNative.request_refresh_rate(float(cap))


## The world's finish for the current quality. High: gentle glow on lamps, magic and the fountain, a
## touch more colour (and soft ambient occlusion under Forward+). Balanced: the same on a PC; on a phone
## the colour only (a full-screen glow costs a phone's frame rate). Battery saver: none of it.
## On a PC at High, the Light World's streets and parks reflect a real sky (Poly Haven's CC0 "partly
## cloudy" panorama, assets/sky/): wet-looking asphalt, glass, a car. Not indoors (a room can't see the
## sky). The daylight dims it (daylight.gd).
static func apply_env(env: Environment, settings: Dictionary = {}, open_sky: bool = false, dark_outdoors: bool = false) -> void:
	if env == null:
		return
	var q := quality(settings)
	var method := RenderingServer.get_current_rendering_method()
	# Phones and the browser keep the compatibility renderer and its existing finish.
	env.ssao_enabled = q == "high" and method == "forward_plus"
	var reflect := q == "high" and method in ["forward_plus", "mobile"] and open_sky and ResourceLoader.exists(SKY)
	if reflect:
		if _sky == null:
			var mat := PanoramaSkyMaterial.new()
			mat.panorama = load(SKY)
			_sky = Sky.new()
			_sky.sky_material = mat
			_sky.radiance_size = Sky.RADIANCE_SIZE_128
			_sky.process_mode = Sky.PROCESS_MODE_QUALITY
		env.sky = _sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
		# This helper owns only the optional reflection panorama. The world's
		# procedural/picture sky must survive a mobile quality or room change.
		if _sky != null and env.sky == _sky:
			env.sky = null
			if env.background_mode == Environment.BG_SKY:
				env.background_mode = Environment.BG_COLOR
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.glow_enabled = (q == "high" or (q == "balanced" and method != "gl_compatibility")) and pressure < 2
	env.glow_intensity = 0.55 if q == "high" else 0.4
	env.glow_strength = 0.9
	env.glow_bloom = 0.04 if q == "high" else 0.02
	env.glow_hdr_threshold = 1.15   # only what is really bright (lamps, magic), not pale walls
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = q != "saver" and pressure < 2
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	if PcDetail.available():
		PcDetail.apply_env(env, pc_tier(settings), open_sky, dark_outdoors)
		PcDetail.settle()


static func pc_tier(settings: Dictionary = {}, handheld: bool = Device.is_handheld(), web: bool = Device.is_web()) -> int:
	return PcDetail.tier(settings if not settings.is_empty() else _settings(), handheld, web, server_window, pressure)


const SKY := "res://assets/sky/partly_cloudy.hdr"
static var _sky: Sky


## The sun's shadows for the current quality: fewer cascades and a distance that fits the camera.
static func mobile_safe_renderer() -> bool:
	return OS.get_name() == "Android" or "--safe-house-render" in OS.get_cmdline_user_args()


static func apply_to_world(sun: DirectionalLight3D, settings: Dictionary = {}) -> void:
	if sun == null:
		return
	var q := quality(settings)
	# Thin, double-sided cutaway walls self-shadow badly with the phone shadow atlas.
	# Keep directional lighting indoors, without those stripes or the extra shadow pass.
	sun.shadow_enabled = q != "saver" and pressure < 2 and not (mobile_safe_renderer() and (q == "balanced" or GameState.current_room_id.begins_with("lw_floor_")))
	if q == "high":
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = SHADOW_DISTANCE_HIGH
		sun.directional_shadow_blend_splits = true
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = SHADOW_DISTANCE_BALANCED
		sun.directional_shadow_blend_splits = false
	# Shadows fade out over the far half of their reach. With Godot's default (the last 20 %) the lawn
	# around a Light World house showed a hard line across the screen where the shadows stopped.
	sun.directional_shadow_fade_start = SHADOW_FADE_START
	if PcDetail.available():
		PcDetail.apply_sun(sun, pc_tier(settings))
