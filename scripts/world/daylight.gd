extends Node
## Lighting that follows the real clock: soft dawn pinks, bright day, golden
## evening, blue night (with a little lantern glow around the player).
## Keyframes are interpolated, so the room changes slowly as time passes. The Light World (your real
## home) has its own, truer daylight: warm whites by day, honest blue evenings, no violet.
## [GLASS_UI] Its day is warm: a golden-white sun and a warm bounce from the walls, like sun through a window.

## [hour, sun color, sun energy, ambient color, ambient energy, sky tint, sprite tint]
const KEYS := [
	[0.0, "#7d8be0", 0.25, "#3b3f8f", 0.55, "#5a64b8", "#9aa3e8"],
	[5.5, "#8f8fe0", 0.3, "#4a4a9a", 0.55, "#6a6ab8", "#a8a8e8"],
	[7.0, "#ffb38a", 0.75, "#c9a0d8", 0.6, "#f0b8c8", "#ffe2d6"],
	[10.0, "#fff1d6", 1.0, "#b9a8ff", 0.6, "#ffffff", "#ffffff"],
	[16.5, "#ffe2b0", 0.95, "#c2a8f0", 0.6, "#fff0e0", "#fff8ee"],
	[19.0, "#ff9f6b", 0.6, "#a07ac8", 0.55, "#f0a0a8", "#ffd8c8"],
	[21.0, "#8f8fe0", 0.3, "#4a4a9a", 0.55, "#6a6ab8", "#b0b0ee"],
	[24.0, "#7d8be0", 0.25, "#3b3f8f", 0.55, "#5a64b8", "#9aa3e8"],
]

## The Light World: [hour, sun color, sun energy, ambient color, ambient energy, sky tint, sprite tint]
const LIGHT_KEYS := [
	[0.0, "#6f7fa8", 0.18, "#2c3550", 0.5, "#3a4870", "#a8b0c8"],
	[5.5, "#8890b8", 0.25, "#3c4562", 0.52, "#5a6890", "#b8bed4"],
	[7.0, "#ffc08e", 0.62, "#e0c6ae", 0.43, "#f6cdb8", "#fff0e4"],
	[10.0, "#ffeccc", 0.82, "#eadbc4", 0.46, "#fffaf0", "#fffcf6"],
	[16.5, "#ffdfae", 0.76, "#e8d2b6", 0.45, "#fff2e0", "#fff8ee"],
	[19.0, "#ffaa78", 0.48, "#b89c94", 0.42, "#f0b098", "#ffe0d0"],
	[21.0, "#7c88b8", 0.28, "#38425e", 0.5, "#4a5880", "#b8bed8"],
	[24.0, "#6f7fa8", 0.18, "#2c3550", 0.5, "#3a4870", "#a8b0c8"],
]

var world: Node
var lantern: OmniLight3D
var hour_override := -1.0     # tests / drives can force a time
var _t := 0.0


func setup(game_world: Node) -> void:
	world = game_world
	lantern = OmniLight3D.new()
	lantern.light_color = Color("#ffcf8a")
	lantern.omni_range = 5.0
	lantern.light_energy = 0.0
	lantern.shadow_enabled = false
	world.add_child(lantern)
	apply()


func _process(delta: float) -> void:
	_t += delta
	if world and world.player:
		lantern.global_position = world.player.global_position + Vector3(0, 1.8, 0)
	if _t >= 20.0:
		_t = 0.0
		apply(true)


func current_hour() -> float:
	if hour_override >= 0.0:
		return hour_override
	if not bool(GameState.world.get("settings", {}).get("real_time_lighting", true)):
		return 12.0
	var t := Time.get_datetime_dict_from_system()
	return float(t.hour) + float(t.minute) / 60.0


## Interpolated look for an hour: {sun, sun_e, amb, amb_e, sky, sprite}. `light`: the Light World's.
static func sample(hour: float, light: bool = false) -> Dictionary:
	var h := fposmod(hour, 24.0)
	var keys: Array = LIGHT_KEYS if light else KEYS
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if h >= float(a[0]) and h <= float(b[0]):
			var f := (h - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
			return {
				"sun": Color(a[1]).lerp(Color(b[1]), f), "sun_e": lerpf(a[2], b[2], f),
				"amb": Color(a[3]).lerp(Color(b[3]), f), "amb_e": lerpf(a[4], b[4], f),
				"sky": Color(a[5]).lerp(Color(b[5]), f), "sprite": Color(a[6]).lerp(Color(b[6]), f),
			}
	return sample(12.0, light)


static func is_night(hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	return h < 6.0 or h >= 20.5


var _light_tw: Tween


## `smooth`: the clock moving on (a slow fade, not with Reduce motion); otherwise at once.
func apply(smooth: bool = false) -> void:
	if world == null or world.env == null:
		return
	var hour := current_hour()
	var light_world: bool = load("res://scripts/world/realms.gd").is_light(world.room.data)
	var s := sample(hour, light_world)
	if light_world and world.get("light_life") and str(world.room.data.get("kind", "")) == "indoor" and not world.light_life.curtains_open_here():
		s.sun_e = float(s.sun_e) * 0.45   # the curtains are drawn
		s.amb_e = float(s.amb_e) * 0.8
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# Phones (and the browser) have no filmic tonemapping: pale colours wash out to white, so the light
		# is gentler there (the Light World's pale walls most of all; the Dream World's pastels too: a pink
		# frosting floor showed as white).
		s.sun_e = float(s.sun_e) * (0.55 if light_world else 0.72)
		s.amb_e = float(s.amb_e) * (0.62 if light_world else 0.8)
	# The sun swings across the sky through the day.
	world.sun.rotation_degrees = Vector3(-35.0 - 25.0 * sin(clampf((hour - 6.0) / 14.0, 0.0, 1.0) * PI), -35.0 + (hour - 12.0) * 6.0, 0)
	var amb: Color = s.amb
	var amb_e: float = s.amb_e
	# Readable indoor fill at night without another light or shadow pass.
	# Preserve the clock's outdoor colours and the effect of closed curtains.
	if light_world and str(world.room.data.get("kind", "")) == "indoor":
		amb = amb.lerp(Color("#eee0cc"), 0.28)
		amb_e = maxf(amb_e, 0.32)
	# A Sky Moment colours the light a little: an aurora glows, rain dims.
	var sky: String = world.variety.sky_today() if world.get("variety") else ""
	if sky == "aurora":
		amb = amb.lerp(Color("#9fe8d0"), 0.35)
		amb_e = amb_e * 1.15
	elif sky in ["rain", "snow"]:
		amb_e = amb_e * 0.85
	if _light_tw and _light_tw.is_valid():
		_light_tw.kill()
	if smooth and not bool(GameState.settings.get("reduce_motion", false)):
		# The clock moving on: the light fades over two seconds instead of jumping.
		_light_tw = create_tween().set_parallel(true)
		_light_tw.tween_property(world.sun, "light_color", s.sun, 2.0)
		_light_tw.tween_property(world.sun, "light_energy", float(s.sun_e), 2.0)
		_light_tw.tween_property(world.env, "ambient_light_color", amb, 2.0)
		_light_tw.tween_property(world.env, "ambient_light_energy", amb_e, 2.0)
	else:
		world.sun.light_color = s.sun
		world.sun.light_energy = s.sun_e
		world.env.ambient_light_color = amb
		world.env.ambient_light_energy = amb_e
	var base := Color.from_string(str(world.room.data.get("sky", {}).get("color", "#120e24")), Color("#120e24"))
	world.env.background_color = base * s.sky
	if world.env.sky and world.env.sky.sky_material is PanoramaSkyMaterial:
		# The reflected sky follows the daylight (a sunny noon to a dim night).
		(world.env.sky.sky_material as PanoramaSkyMaterial).energy_multiplier = clampf(float(s.sun_e) / 2.0, 0.05, 0.6)
	lantern.light_energy = 1.2 if is_night(hour) else 0.0
	if world.has_method("refresh_sky"):
		world.refresh_sky()
	world.room.tint_sprites(s.sprite)
	if world.has_method("refresh_weather") and world.weather:
		world.refresh_weather()
	if world.get("ambience"):
		world.ambience.play_for(world.room.data, is_night(hour))
	for a in [world.player] + world.actors.values():
		if is_instance_valid(a):
			a.set_tint(s.sprite)
