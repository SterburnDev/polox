extends Node3D
## Gentle weather particles over the room: snow, rain, falling leaves,
## blossom petals or drifting fireflies. Rooms can switch it off in Build
## mode (ambiance.weather = "none"); cheap enough for integrated GPUs.

const STYLES := {
	# [color, size (m), amount, fall speed, sway, glow]
	"snow": [Color(1, 1, 1, 0.9), 0.07, 160, 0.8, 0.4, false],
	"rain": [Color(0.6, 0.75, 1.0, 0.55), 0.05, 220, 6.0, 0.05, false],
	"leaves": [Color("#e8914a"), 0.12, 50, 0.7, 1.0, false],
	"petals": [Color("#ffb3c7"), 0.09, 70, 0.6, 0.9, false],
	"fireflies": [Color("#fff08a"), 0.11, 40, 0.0, 0.5, true],
	"aurora": [Color("#7ad6b0", 0.7), 3.2, 18, 0.0, 0.25, false],   # (a Sky Moment) soft ribbons of light up high
}

## GPUParticles3D on a PC; CPUParticles3D under the phone/browser renderer (gl_compatibility), where GPU
## particles run on transform feedback and every street or Dream World place re-simulated their whole
## lifetime on the GPU in one frame as it loaded. The phone crashes while walking were native.
var particles: GeometryInstance3D
var current := ""
static var force_cpu := false   # (tests) the phone's way on a PC


static func use_cpu() -> bool:
	return force_cpu or RenderingServer.get_current_rendering_method() == "gl_compatibility" or OS.has_feature("mobile")


## `drift`: the weather changed while you're here, so it drifts in (not with Reduce motion).
func show_weather(kind: String, room_w: int, room_d: int, room_h: float, drift: bool = false) -> void:
	current = kind
	if particles:
		particles.queue_free()
		particles = null
	if not STYLES.has(kind):
		return
	var st: Array = STYLES[kind]
	var gp := GPUParticles3D.new()
	gp.amount = int(st[2])
	gp.lifetime = 6.0 if kind != "rain" else 1.2
	gp.preprocess = gp.lifetime
	gp.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(room_w + 4, room_h + 8, room_d + 4))
	gp.position = Vector3(0, 0, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var top := room_h + 3.0
	if kind == "aurora":
		# Drifting at the top of the walls over the back half of the room (on screen from the usual camera).
		pm.emission_box_extents = Vector3(room_w / 2.0, 0.3, room_d * 0.18)
		gp.position = Vector3(room_w / 2.0, room_h - 0.1, room_d * 0.3)
		pm.gravity = Vector3(0, 0.0, 0)
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.15
		pm.direction = Vector3(1, 0, 0)
		pm.spread = 30.0
		var ramp := Gradient.new()   # fade in and out, green to violet
		ramp.set_color(0, Color(0.48, 0.84, 0.69, 0.0))
		ramp.set_color(1, Color(0.77, 0.55, 1.0, 0.0))
		ramp.add_point(0.3, Color(0.48, 0.84, 0.69, 1.0))
		ramp.add_point(0.7, Color(0.77, 0.55, 1.0, 1.0))
		var gt := GradientTexture1D.new()
		gt.gradient = ramp
		pm.color_ramp = gt
	elif kind == "fireflies":
		pm.emission_box_extents = Vector3(room_w / 2.0, 0.8, room_d / 2.0)
		gp.position = Vector3(room_w / 2.0, 1.2, room_d / 2.0)
		pm.gravity = Vector3(0, 0.05, 0)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_speed_random = 0.4
	else:
		pm.emission_box_extents = Vector3(room_w / 2.0, 0.2, room_d / 2.0)
		gp.position = Vector3(room_w / 2.0, top, room_d / 2.0)
		pm.direction = Vector3(0, -1, 0)
		pm.spread = 8.0
		pm.initial_velocity_min = float(st[3]) * 0.8
		pm.initial_velocity_max = float(st[3]) * 1.2
		pm.gravity = Vector3(0, -0.2 if kind != "rain" else -4.0, 0)
		if float(st[4]) > 0.2:
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = float(st[4]) * 0.6
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	gp.process_material = pm
	var q := QuadMesh.new()
	var size := float(st[1])
	q.size = Vector2(size * (0.35 if kind == "rain" else 1.0), size * (6.0 if kind == "rain" else (0.3 if kind == "aurora" else 1.0)))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if kind != "rain" else BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = st[0]
	mat.albedo_texture = _dot_texture(kind)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if kind == "aurora":   # soft and glowing, not pixel dots
		mat.albedo_texture = _soft_texture()
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.vertex_color_use_as_albedo = true
	if bool(st[5]):
		mat.emission_enabled = true
		mat.emission = Color(st[0])
		mat.emission_energy_multiplier = 2.0
	q.material = mat
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var drifting := drift and not bool(GameState.settings.get("reduce_motion", false))
	if use_cpu():
		# The same settings (turbulence aside), simulated on the CPU and drawn as one instanced mesh.
		var cpu := CPUParticles3D.new()
		cpu.convert_from_particles(gp)
		cpu.position = gp.position
		cpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if drifting:
			cpu.preprocess = 0.0   # starts falling from the top now: it drifts in by itself
		gp.free()
		particles = cpu
		add_child(cpu)
		return
	particles = gp
	add_child(gp)
	if drifting:
		gp.amount_ratio = 0.0
		gp.create_tween().tween_property(gp, "amount_ratio", 1.0, 3.0)


## A soft glow that fades to nothing at the edges (the aurora's ribbons).
static func _soft_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5).length()
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


## Little pixel shapes: round flakes/fireflies, leaf and petal blobs, rain streaks.
static func _dot_texture(kind: String) -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 8:
		for x in 8:
			var d := Vector2(x - 3.5, y - 3.5)
			var on := false
			match kind:
				"rain":
					on = x >= 3 and x <= 4
				"leaves":
					on = absf(d.x - d.y) < 2.2 and d.length() < 4.0
				"petals":
					on = Vector2(d.x * 0.8, d.y * 1.3).length() < 3.2
				_:
					on = d.length() < 3.0
			if on:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)
