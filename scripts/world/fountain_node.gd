extends Node3D
## A Dream Gate, drawn in code: a reddish, glazed ceramic bathtub-like basin standing on four tiny
## brass clawfeet with a vintage faucet at one end, brimming with luminous ruby-crimson dream liquid.
## While open, glossy ripples spread across the basin and an undulating jet of dream liquid rises
## with falling droplets. Sealed: a snug glazed bath cover glows warmly on top. New (not linked yet):
## the crimson pool lies calm.
##
## Saves still store its type as "dark_fountain" so existing worlds created before the rename keep
## their gates untouched. Entering, interacting, collision bounds, and states are unchanged.
##
## Animations (all skippable through Moment, swapped for a short fade with Reduce motion):
##   play_opening(): floor cracks spread, the jet rises with droplets and a whoosh
##   play_sealing(): light gathers around it, the jet sinks, the cover closes
##
## Lighter on phones (Battery saver): fewer droplets. A homeward gate (leading back to the Light
## World, realms.gd) swaps the crimson glow for warm liquid gold.
## Tags: [GRAPHICS]

const BlockFactory := preload("res://scripts/world/block_factory.gd")
const Synth := preload("res://scripts/core/synth.gd")
const Graphics := preload("res://scripts/core/graphics.gd")
const PcDetail := preload("res://scripts/core/pc_detail.gd")
const SurfaceMaterials := preload("res://scripts/world/surface_materials.gd")

const COLUMN_HEIGHT := 2.6
const APRON_LAYER := 1 << 10     # Render layer 11: the tile apron stays lit by the room, not the gate's own lamp.
const BASE_Y := 0.46             # Liquid surface height: the jet rises from here.
const TUB_LENGTH_SCALE := 1.18   # Elongated oval bathtub silhouette along X (fits inside the 1 m cell).
const TUB_WIDTH_SCALE := 0.78    # Gently narrowed waist along Z so it reads immediately as a tub.
const DUCK_POKE_THRESHOLD := 3   # Secret: poking the bathtub basin 3 times invites a tiny rubber duck.

## The rising jet: glossy crimson dream liquid wobbling as it flows upward.
const FLOW_SHADER_CODE := """
shader_type spatial;
render_mode cull_back;
uniform vec4 deep : source_color = vec4(0.56, 0.08, 0.11, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.56, 0.48, 1.0);
uniform float speed = 0.65;
void vertex() {
	float t = TIME * speed;
	float swell = sin(UV.y * 18.0 + t * 9.0) * 0.5 + 0.5;
	VERTEX.xz *= 1.0 + 0.07 * swell + 0.03 * sin(UV.x * 25.13 + t * 5.0);
}
void fragment() {
	float t = TIME * speed;
	float vein = sin(UV.x * 37.7 + sin(UV.y * 6.0 + t * 4.0) * 1.5);
	float flow = sin(UV.y * 22.0 + t * 9.0 + UV.x * 6.283) * 0.5 + 0.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep.rgb, glow.rgb, smoothstep(0.6, 1.0, vein) * 0.32 + flow * 0.12);
	ROUGHNESS = 0.05;
	SPECULAR = 0.92;
	EMISSION = deep.rgb * 0.58 + glow.rgb * (rim * 0.55 + smoothstep(0.88, 1.0, vein) * 0.28);
}
"""

## The tub's brimming liquid: glossy oval surface with concentric ripples and touch rings (`poke()`).
const POOL_SHADER_CODE := """
shader_type spatial;
uniform vec4 deep : source_color = vec4(0.46, 0.06, 0.10, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.48, 0.42, 1.0);
uniform float calm = 0.0;
// A touch (poke()): concentric ripple ring traveling outward (`poke_age` >= 3.0 = inactive).
uniform float poke_age = 9.0;
varying vec2 at;
void vertex() {
	at = VERTEX.xz;
}
void fragment() {
	float r = length(at) / 0.44;
	float rings = (sin(r * 24.0 - TIME * 4.0) * 0.5 + 0.5) * (1.0 - calm) * smoothstep(1.0, 0.12, r);
	float front = poke_age * 0.55;
	float touch = exp(-pow((r - front) * 9.0, 2.0)) * clamp(1.0 - poke_age / 2.2, 0.0, 1.0);
	touch += exp(-pow((r - front * 0.6) * 12.0, 2.0)) * clamp(1.0 - poke_age / 1.6, 0.0, 1.0) * 0.5;
	ALBEDO = mix(deep.rgb, glow.rgb, rings * 0.24 + touch * 0.62);
	ROUGHNESS = 0.04;
	SPECULAR = 0.95;
	NORMAL = normalize(NORMAL + vec3(touch * 0.6, 0.0, 0.0));
	EMISSION = deep.rgb * 0.48 + glow.rgb * (rings * 0.34 + touch * 0.92);
}
"""

## Shared compiled shaders across every Dream Gate instance (avoids recompiling per gate).
static var _flow_shader: Shader
static var _pool_shader: Shader

var obj: Dictionary = {}
var state := "new"
var column: MeshInstance3D
var particles: CPUParticles3D
var lid: MeshInstance3D
var pool: MeshInstance3D
var cracks: MeshInstance3D
var hum: AudioStreamPlayer3D
var light: OmniLight3D

var _poke_age := 9.0
var _poke_count := 0
var _duck: Node3D
var _duck_time := 0.0


static func make(gate_obj: Dictionary, ghost: bool = false) -> Node3D:
	var node: Node3D = load("res://scripts/world/fountain_node.gd").new()
	node.obj = gate_obj
	node.state = str(gate_obj.get("state", "new"))
	node.build(ghost)
	return node


func build(ghost: bool = false) -> void:
	# [GLASS_UI] Glazed crimson-terracotta porcelain tub with warm blush-ivory rolled rim and brass hardware.
	var tub_glaze := _glaze(Color("#a82c2c"))
	var inner_glaze := _glaze(Color("#7a1b1f"))
	var rim_glaze := _glaze(Color("#f7e7e0"))
	var brass_mat := _metal(Color("#d4a84e"))

	if not ghost:
		add_to_group(&"polox_gate")
		_build_apron()

	_build_tub_body(tub_glaze, inner_glaze, rim_glaze)
	_build_clawfeet_and_faucet(brass_mat)
	_build_liquid_and_jet()
	_build_particles()
	_build_sealed_cover()
	_build_lighting_and_collision(ghost)

	apply_state(state)
	if ghost:
		for mesh_node in find_children("*", "MeshInstance3D", true, false):
			(mesh_node as MeshInstance3D).transparency = 0.6


func _build_tub_body(tub_glaze: StandardMaterial3D, inner_glaze: StandardMaterial3D, rim_glaze: StandardMaterial3D) -> void:
	# Flared outer bathtub shell (oval footprint: longer along X, cozy tub waist along Z).
	var basin := MeshInstance3D.new()
	basin.name = "Basin"
	var basin_mesh := CylinderMesh.new()
	basin_mesh.radial_segments = 28
	basin_mesh.rings = 3
	basin_mesh.top_radius = 0.45
	basin_mesh.bottom_radius = 0.35
	basin_mesh.height = 0.36
	basin.mesh = basin_mesh
	basin.material_override = tub_glaze
	basin.scale = Vector3(TUB_LENGTH_SCALE, 1.0, TUB_WIDTH_SCALE)
	basin.position = Vector3(0.0, 0.25, 0.0)
	add_child(basin)

	# Curved underside belly so the tub sits gracefully above its four clawfeet.
	var belly := MeshInstance3D.new()
	belly.name = "BasinBelly"
	var belly_mesh := SphereMesh.new()
	belly_mesh.radial_segments = 24
	belly_mesh.rings = 10
	belly_mesh.radius = 0.36
	belly_mesh.height = 0.22
	belly.mesh = belly_mesh
	belly.material_override = tub_glaze
	belly.scale = Vector3(TUB_LENGTH_SCALE, 1.0, TUB_WIDTH_SCALE)
	belly.position = Vector3(0.0, 0.11, 0.0)
	add_child(belly)

	# Slightly raised curved backrest lip on the -X end (classic slipper bathtub touch).
	var backrest := MeshInstance3D.new()
	backrest.name = "Backrest"
	var back_mesh := CylinderMesh.new()
	back_mesh.radial_segments = 16
	back_mesh.rings = 1
	back_mesh.top_radius = 0.24
	back_mesh.bottom_radius = 0.28
	back_mesh.height = 0.14
	backrest.mesh = back_mesh
	backrest.material_override = tub_glaze
	backrest.scale = Vector3(0.75, 1.0, 1.05)
	backrest.position = Vector3(-0.36, 0.45, 0.0)
	backrest.rotation.z = 0.18
	add_child(backrest)

	# Recessed dark-crimson inner wall visible right below the rolled rim.
	var inner_wall := MeshInstance3D.new()
	inner_wall.name = "InnerWall"
	var inner_mesh := CylinderMesh.new()
	inner_mesh.radial_segments = 24
	inner_mesh.rings = 1
	inner_mesh.top_radius = 0.41
	inner_mesh.bottom_radius = 0.39
	inner_mesh.height = 0.06
	inner_wall.mesh = inner_mesh
	inner_wall.material_override = inner_glaze
	inner_wall.scale = Vector3(TUB_LENGTH_SCALE, 1.0, TUB_WIDTH_SCALE)
	inner_wall.position = Vector3(0.0, 0.43, 0.0)
	add_child(inner_wall)

	# Rolled porcelain bathtub rim (kept named "Rim" with glossy glaze for tactile look checks).
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var rim_mesh := TorusMesh.new()
	rim_mesh.rings = 32
	rim_mesh.ring_segments = 10
	rim_mesh.inner_radius = 0.38
	rim_mesh.outer_radius = 0.49
	rim.mesh = rim_mesh
	rim.material_override = rim_glaze
	rim.scale = Vector3(TUB_LENGTH_SCALE, 1.0, TUB_WIDTH_SCALE)
	rim.position = Vector3(0.0, 0.435, 0.0)
	add_child(rim)


func _build_clawfeet_and_faucet(brass_mat: StandardMaterial3D) -> void:
	# Four sculpted antique brass clawfeet supporting the reddish tub over the tile apron.
	var foot_mesh := SphereMesh.new()
	foot_mesh.radial_segments = 10
	foot_mesh.rings = 6
	foot_mesh.radius = 0.065
	foot_mesh.height = 0.11
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot := MeshInstance3D.new()
			foot.name = "Clawfoot"
			foot.mesh = foot_mesh
			foot.material_override = brass_mat
			foot.position = Vector3(sx * 0.32, 0.065, sz * 0.21)
			add_child(foot)

	# Vintage curved brass faucet + hot/cold tap handles at the +X end of the bathtub.
	var faucet_group := Node3D.new()
	faucet_group.name = "Faucet"
	faucet_group.position = Vector3(0.49, 0.45, 0.0)
	add_child(faucet_group)

	var riser := MeshInstance3D.new()
	var riser_mesh := CylinderMesh.new()
	riser_mesh.radial_segments = 10
	riser_mesh.top_radius = 0.022
	riser_mesh.bottom_radius = 0.028
	riser_mesh.height = 0.18
	riser.mesh = riser_mesh
	riser.material_override = brass_mat
	riser.position = Vector3(0.0, 0.09, 0.0)
	faucet_group.add_child(riser)

	var spout := MeshInstance3D.new()
	var spout_mesh := CylinderMesh.new()
	spout_mesh.radial_segments = 10
	spout_mesh.top_radius = 0.018
	spout_mesh.bottom_radius = 0.022
	spout_mesh.height = 0.14
	spout.mesh = spout_mesh
	spout.material_override = brass_mat
	spout.position = Vector3(-0.06, 0.17, 0.0)
	spout.rotation.z = PI * 0.42
	faucet_group.add_child(spout)

	var knob_mesh := CylinderMesh.new()
	knob_mesh.radial_segments = 8
	knob_mesh.top_radius = 0.026
	knob_mesh.bottom_radius = 0.018
	knob_mesh.height = 0.055
	for side_z in [-0.085, 0.085]:
		var knob := MeshInstance3D.new()
		knob.mesh = knob_mesh
		knob.material_override = brass_mat
		knob.position = Vector3(0.0, 0.035, side_z)
		faucet_group.add_child(knob)


func _build_liquid_and_jet() -> void:
	pool = MeshInstance3D.new()
	pool.name = "Liquid"
	var pool_mesh := CylinderMesh.new()
	pool_mesh.radial_segments = 28
	pool_mesh.rings = 1
	pool_mesh.top_radius = 0.415
	pool_mesh.bottom_radius = 0.415
	pool_mesh.height = 0.02
	pool.mesh = pool_mesh
	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = _shared_pool_shader()
	pool.material_override = pool_mat
	pool.scale = Vector3(TUB_LENGTH_SCALE, 1.0, TUB_WIDTH_SCALE)
	pool.position = Vector3(0.0, BASE_Y, 0.0)
	add_child(pool)

	column = MeshInstance3D.new()
	column.name = "Jet"
	var col_mesh := CylinderMesh.new()
	col_mesh.radial_segments = 16
	col_mesh.rings = 12   # Rings allow the vertex shader's flow wobble.
	col_mesh.top_radius = 0.13
	col_mesh.bottom_radius = 0.24
	col_mesh.height = COLUMN_HEIGHT
	col_mesh.cap_top = true   # The camera looks down onto the jet.
	col_mesh.cap_bottom = false
	column.mesh = col_mesh
	var flow_mat := ShaderMaterial.new()
	flow_mat.shader = _shared_flow_shader()
	if _homeward():
		for shader_mat in [flow_mat, pool_mat]:
			shader_mat.set_shader_parameter("deep", Color(1.0, 0.88, 0.6))
			shader_mat.set_shader_parameter("glow", Color(1.0, 0.99, 0.93))
	column.material_override = flow_mat
	column.position = Vector3(0.0, BASE_Y + COLUMN_HEIGHT / 2.0, 0.0)
	add_child(column)


func _build_particles() -> void:
	var drop_color := Color("#fff0c4") if _homeward() else Color("#ff5b57")
	particles = CPUParticles3D.new()
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.amount = 10 if _light_mode() else 26
	particles.lifetime = 1.6
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.1
	particles.direction = Vector3.UP
	particles.spread = 22.0
	particles.gravity = Vector3(0.0, -3.0, 0.0)
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 0.95
	particles.scale_amount_min = 0.048
	particles.scale_amount_max = 0.085
	var dot := SphereMesh.new()
	dot.radial_segments = 8
	dot.rings = 4
	dot.radius = 0.5
	dot.height = 1.0
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = drop_color
	drop_mat.roughness = 0.05
	drop_mat.emission_enabled = true
	drop_mat.emission = drop_color
	drop_mat.emission_energy_multiplier = 0.4
	dot.material = drop_mat
	particles.mesh = dot
	particles.position = Vector3(0.0, BASE_Y + COLUMN_HEIGHT, 0.0)
	add_child(particles)


func _build_sealed_cover() -> void:
	lid = MeshInstance3D.new()
	lid.name = "SealedCover"
	var lid_mesh := CylinderMesh.new()
	lid_mesh.radial_segments = 24
	lid_mesh.rings = 1
	lid_mesh.top_radius = 0.34
	lid_mesh.bottom_radius = 0.48
	lid_mesh.height = 0.12
	lid.mesh = lid_mesh
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color("#f5e8dc")
	lid_mat.roughness = 0.22
	lid_mat.emission_enabled = true
	lid_mat.emission = Color("#ffe4a8")
	lid_mat.emission_energy_multiplier = 0.72
	lid.material_override = lid_mat
	lid.scale = Vector3(TUB_LENGTH_SCALE, 1.0, TUB_WIDTH_SCALE)
	lid.position = Vector3(0.0, 0.51, 0.0)
	add_child(lid)


func _build_lighting_and_collision(ghost: bool) -> void:
	light = OmniLight3D.new()
	light.add_to_group("polox_lamp")
	light.light_color = Color("#ff6f5c")
	light.omni_range = 3.2
	light.position = Vector3(0.0, 1.2, 0.0)
	light.shadow_enabled = false
	light.light_cull_mask = ~APRON_LAYER
	add_child(light)
	add_child(BlockFactory.body(Vector3(1.0, 1.4, 1.0), Vector3(0.0, 0.7, 0.0), BlockFactory.LAYER_OBJECTS, {"kind": "object", "id": str(obj.get("id", ""))}))
	if not ghost and str(obj.get("label", "")) != "":
		var label := Label3D.new()
		label.text = str(obj.label)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 28
		label.pixel_size = 0.01
		label.outline_size = 8
		label.position = Vector3(0.0, 3.1, 0.0)
		label.no_depth_test = true
		label.render_priority = 10
		label.outline_render_priority = 9
		add_child(label)


static func _shared_flow_shader() -> Shader:
	if _flow_shader == null:
		_flow_shader = Shader.new()
		_flow_shader.code = FLOW_SHADER_CODE
	return _flow_shader


static func _shared_pool_shader() -> Shader:
	if _pool_shader == null:
		_pool_shader = Shader.new()
		_pool_shader.code = POOL_SHADER_CODE
	return _pool_shader


## The way home: a gate leading back to the Light World.
func _homeward() -> bool:
	return bool(obj.get("gate", false)) and str(obj.get("leads", "")) == "light"


func _light_mode() -> bool:
	return Graphics.low_detail()   # Battery saver: fewer drops


## Shows the state with no animation.
func apply_state(next_state: String) -> void:
	state = next_state
	var is_open := next_state == "open"
	column.visible = is_open
	column.scale = Vector3.ONE
	particles.emitting = is_open
	lid.visible = next_state == "sealed"
	pool.visible = next_state != "sealed"
	if _duck and is_instance_valid(_duck):
		_duck.visible = next_state != "sealed"
	(pool.material_override as ShaderMaterial).set_shader_parameter("calm", 0.0 if is_open else 0.9)
	light.light_energy = 1.2 if is_open else (0.5 if next_state == "sealed" else 0.25)
	light.light_color = Color("#ff6f5c") if next_state != "sealed" and not _homeward() else Color("#ffe9a8")
	if is_open and hum == null and is_inside_tree():
		_start_hum()
	elif not is_open and hum:
		hum.queue_free()
		hum = null


func _ready() -> void:
	set_process(false)
	if state == "open":
		_start_hum()


func _start_hum() -> void:
	hum = AudioStreamPlayer3D.new()
	hum.stream = Synth.get_sound("hum")
	hum.unit_size = 2.0
	hum.max_distance = 9.0
	hum.volume_db = linear_to_db(maxf(0.001, float(GameState.settings.get("sfx_volume", 0.8)) * 0.18))
	add_child(hum)
	hum.play()


func _crack_lines(progress: float) -> void:
	if cracks == null:
		cracks = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("#ff8a7a")
		cracks.material_override = mat
		add_child(cracks)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(obj.get("id", "f")))
	for i in 9:
		var angle := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var point := Vector3(cos(angle), 0.0, sin(angle)) * 0.5
		var length := (1.2 + rng.randf() * 1.6) * progress
		var steps := 4
		for _step in steps:
			var next_pt := point + Vector3(cos(angle + rng.randf_range(-0.6, 0.6)), 0.0, sin(angle + rng.randf_range(-0.6, 0.6))) * (length / steps)
			mesh.surface_add_vertex(point + Vector3(0.0, 0.02, 0.0))
			mesh.surface_add_vertex(next_pt + Vector3(0.0, 0.02, 0.0))
			point = next_pt
	mesh.surface_end()
	cracks.mesh = mesh


## The Dream Gate opens: cracks spread, the crimson jet rises, droplets scatter, a rising whoosh.
func play_opening(moment: Control, reduced: bool) -> void:
	apply_state("open")
	if reduced:
		await moment.wait(0.2)
		return
	column.scale = Vector3(1.0, 0.02, 1.0)
	particles.amount = 40 if not _light_mode() else 14
	Synth.play(self, "whoosh", 0.5)
	var elapsed := 0.0
	var total := 1.8
	var start_ms := Time.get_ticks_msec()
	while elapsed < total and is_instance_valid(moment) and moment.is_inside_tree():
		if await moment.wait(0.0333):
			break
		elapsed = (Time.get_ticks_msec() - start_ms) / 1000.0
		var frac := clampf(elapsed / total, 0.0, 1.0)
		_crack_lines(minf(1.0, frac * 1.6))
		column.scale = Vector3(1.0, maxf(0.02, ease(clampf((frac - 0.25) / 0.75, 0.0, 1.0), 0.4)), 1.0)
		column.position.y = BASE_Y + COLUMN_HEIGHT * column.scale.y / 2.0
		light.light_energy = 0.3 + 1.6 * frac
	column.scale = Vector3.ONE
	column.position.y = BASE_Y + COLUMN_HEIGHT / 2.0
	_crack_lines(1.0)
	light.light_energy = 1.2
	Synth.play(self, "chime", 0.35)


## The Dream Gate is sealed: light gathers, the jet sinks back into the bathtub, the cover closes.
func play_sealing(moment: Control, reduced: bool) -> void:
	if reduced:
		await moment.wait(0.2)
		apply_state("sealed")
		return
	particles.initial_velocity_min = 0.1
	particles.initial_velocity_max = 0.3
	particles.gravity = Vector3(0.0, -5.0, 0.0)
	light.light_color = Color("#ffe9a8")
	Synth.play(self, "sparkle", 0.5)
	var elapsed := 0.0
	var total := 1.6
	var start_ms := Time.get_ticks_msec()
	while elapsed < total and is_instance_valid(moment) and moment.is_inside_tree():
		if await moment.wait(0.0333):
			break
		elapsed = (Time.get_ticks_msec() - start_ms) / 1000.0
		var frac := clampf(elapsed / total, 0.0, 1.0)
		column.scale = Vector3(1.0 - frac * 0.6, maxf(0.02, 1.0 - frac), 1.0 - frac * 0.6)
		column.position.y = BASE_Y + COLUMN_HEIGHT * column.scale.y / 2.0
		light.light_energy = 1.2 + sin(frac * PI) * 2.0
	if cracks:
		cracks.queue_free()
		cracks = null
	apply_state("sealed")
	Synth.play(self, "chime", 0.35)


## A glazed ceramic finish in colour `color`: smooth and glossy, with clear coat when PC reflections are on.
static func _glaze(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.12 if _rich() else 0.24
	mat.metallic_specular = 0.78 if _rich() else 0.58
	if _rich():
		mat.clearcoat_enabled = true
		mat.clearcoat = 0.92
		mat.clearcoat_roughness = 0.05
	return mat


## Antique brass finish for the clawfeet and curved faucet.
static func _metal(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.82
	mat.roughness = 0.26 if _rich() else 0.38
	return mat


static func _rich() -> bool:
	if not PcDetail.available():
		return false
	return PcDetail.level_of("reflections", Graphics.pc_tier(GameState.settings), GameState.settings) >= 1


## The floor it stands on: a small apron of glazed white tiles (Poly Haven's long white tiles).
func _build_apron() -> void:
	var pad := MeshInstance3D.new()
	pad.name = "TileApron"
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(1.24, 0.02, 1.24)
	pad.mesh = pad_mesh
	var tile: Material = SurfaceMaterials.standard("ceramic", Color("#cdc4b6"))
	pad.material_override = tile if tile else _glaze(Color("#cdc4b6"))
	pad.position = Vector3(0.0, 0.011, 0.0)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.layers = APRON_LAYER
	add_child(pad)


## Touched (used, tapped, walked up to): sends a ripple ring across the crimson liquid and plays a soft plop.
## Secret: poking the bathtub basin 3 times invites a tiny floating rubber ducky!
func poke() -> void:
	_poke_age = 0.0
	_poke_count += 1
	set_process(true)
	if pool and pool.material_override:
		Synth.play(self, "pop", 0.25)
	if _poke_count == DUCK_POKE_THRESHOLD and _duck == null and state != "sealed":
		_spawn_rubber_duck()
		if is_inside_tree():
			GameState.notify("* A tiny rubber duck drifted up in the Dream Gate. Nobody can explain why.")
	elif _poke_count == 7 and _duck != null and is_inside_tree():
		Synth.play(self, "sparkle", 0.35)
		GameState.notify("* The Dream Gate duck squeaks approvingly. You feel mildly determined.")


func poke_if(id: String) -> void:
	if str(obj.get("id", "")) == id:
		poke()


func has_rubber_duck() -> bool:
	return _duck != null and is_instance_valid(_duck)


func _spawn_rubber_duck() -> void:
	_duck = Node3D.new()
	_duck.name = "RubberDuck"
	_duck.position = Vector3(-0.22, BASE_Y + 0.04, 0.08)
	_duck.rotation.y = 0.65

	var yellow := _glaze(Color("#ffe047"))
	var orange := _glaze(Color("#ff7b29"))
	var eye_mat := _glaze(Color("#1a1426"))

	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radial_segments = 10
	body_mesh.rings = 6
	body_mesh.radius = 0.055
	body_mesh.height = 0.09
	body.mesh = body_mesh
	body.material_override = yellow
	body.scale = Vector3(1.25, 0.85, 0.95)
	_duck.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radial_segments = 10
	head_mesh.rings = 6
	head_mesh.radius = 0.038
	head_mesh.height = 0.076
	head.mesh = head_mesh
	head.material_override = yellow
	head.position = Vector3(0.045, 0.045, 0.0)
	_duck.add_child(head)

	var beak := MeshInstance3D.new()
	var beak_mesh := BoxMesh.new()
	beak_mesh.size = Vector3(0.032, 0.016, 0.024)
	beak.mesh = beak_mesh
	beak.material_override = orange
	beak.position = Vector3(0.082, 0.042, 0.0)
	_duck.add_child(beak)

	var eye_mesh := SphereMesh.new()
	eye_mesh.radial_segments = 6
	eye_mesh.rings = 4
	eye_mesh.radius = 0.006
	eye_mesh.height = 0.012
	for side_z in [-0.022, 0.022]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(0.068, 0.056, side_z)
		_duck.add_child(eye)

	add_child(_duck)


func _process(delta: float) -> void:
	var keep_running := false
	if _poke_age < 3.0:
		_poke_age += delta
		if pool and pool.material_override is ShaderMaterial:
			(pool.material_override as ShaderMaterial).set_shader_parameter("poke_age", _poke_age)
		keep_running = true
	if _duck and is_instance_valid(_duck) and _duck.visible and not bool(GameState.settings.get("reduce_motion", false)):
		_duck_time += delta
		_duck.position.y = BASE_Y + 0.04 + sin(_duck_time * 2.6) * 0.012
		_duck.rotation.z = sin(_duck_time * 1.9) * 0.08
		keep_running = true
	if not keep_running:
		set_process(false)
