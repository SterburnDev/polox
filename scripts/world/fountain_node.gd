extends Node3D
## A Dream Gate, drawn in code: a round, orange basin brimming with deep orange liquid. The liquid looks
## like liquid, not smoke: a glossy surface with ripples running out from the middle, and while the gate
## is open a glossy jet of it rises, wobbling as it flows, and drops fall from its top back into the
## basin. Sealed: the basin with a closed, softly lit cover. New (not linked yet): the pool lies still.
## (Saves call it "dark_fountain": that name stays, so old worlds keep their gates.) Entering and using
## it are the same as ever: the same hit box, the same states, dark_director.gd.
## Animations (all skippable through Moment, all swapped for a short fade with Reduce motion):
##   play_opening(): the ground cracks, the jet rises with drops and a rising sound
##   play_sealing(): light gathers around it, the jet sinks, the cover closes
## Lighter on phones (performance mode): fewer drops. The way home (a gate leading to the Light World,
## realms.gd) is the same gate with pale liquid gold light instead of orange.

const BlockFactory := preload("res://scripts/world/block_factory.gd")
const Synth := preload("res://scripts/core/synth.gd")

const COLUMN_HEIGHT := 2.6
const APRON_LAYER := 1 << 10     # (render layer 11: the tile apron, which the gate's own light leaves out)
const BASE_Y := 0.47             # the liquid's surface: the jet rises from here
## The jet: glossy liquid flowing up, its sides swelling and wobbling as the flow passes.
const FLOW_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 deep : source_color = vec4(0.62, 0.2, 0.02, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.72, 0.38, 1.0);
uniform float speed = 0.6;
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
	ALBEDO = mix(deep.rgb, glow.rgb, smoothstep(0.6, 1.0, vein) * 0.3 + flow * 0.1);
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	EMISSION = deep.rgb * 0.55 + glow.rgb * (rim * 0.5 + smoothstep(0.88, 1.0, vein) * 0.25);
}
"""
## The basin's surface: glossy, with ripples running out from the middle (still while `calm` is 1).
const POOL_SHADER := """
shader_type spatial;
uniform vec4 deep : source_color = vec4(0.55, 0.17, 0.02, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.62, 0.3, 1.0);
uniform float calm = 0.0;
// A touch (poke()): one ring running out from the middle, `poke_age` seconds old (>= 3 = none).
uniform float poke_age = 9.0;
varying vec2 at;
void vertex() {
	at = VERTEX.xz;
}
void fragment() {
	float r = length(at) / 0.46;
	float rings = (sin(r * 24.0 - TIME * 4.0) * 0.5 + 0.5) * (1.0 - calm) * smoothstep(1.0, 0.15, r);
	float front = poke_age * 0.55;   // the ring's radius (0..1 of the basin) as it travels out
	float touch = exp(-pow((r - front) * 9.0, 2.0)) * clamp(1.0 - poke_age / 2.2, 0.0, 1.0);
	touch += exp(-pow((r - front * 0.6) * 12.0, 2.0)) * clamp(1.0 - poke_age / 1.6, 0.0, 1.0) * 0.5;
	ALBEDO = mix(deep.rgb, glow.rgb, rings * 0.22 + touch * 0.6);
	ROUGHNESS = 0.04;
	SPECULAR = 0.95;
	NORMAL = normalize(NORMAL + vec3(touch * 0.6, 0.0, 0.0));
	EMISSION = deep.rgb * 0.45 + glow.rgb * (rings * 0.3 + touch * 0.9);
}
"""

var obj: Dictionary = {}
var state := "new"
var column: MeshInstance3D
var particles: CPUParticles3D
var lid: MeshInstance3D
var pool: MeshInstance3D
var cracks: MeshInstance3D
var hum: AudioStreamPlayer3D
var light: OmniLight3D


static func make(o: Dictionary, ghost: bool = false) -> Node3D:
	var n: Node3D = load("res://scripts/world/fountain_node.gd").new()
	n.obj = o
	n.state = str(o.get("state", "new"))
	n.build(ghost)
	return n


func build(ghost: bool = false) -> void:
	# [GLASS_UI] Glazed ceramic: the bath-like basin in its red-orange glaze and a warm white glazed rim,
	# glossy enough to catch the room's light (and, on a PC at High, a clear coat and reflections).
	var stone := _glaze(Color("#c8641e"))
	var rim_mat := _glaze(Color("#f4e7d6"))
	if not ghost:
		add_to_group(&"polox_gate")
		_apron()
	# The basin: round, a little wider at the top, with a rolled rim.
	var basin := MeshInstance3D.new()
	basin.name = "Basin"
	var bm := CylinderMesh.new()
	bm.radial_segments = 24
	bm.rings = 2
	bm.top_radius = 0.52
	bm.bottom_radius = 0.42
	bm.height = 0.42
	basin.mesh = bm
	basin.material_override = stone
	basin.position = Vector3(0, 0.21, 0)
	add_child(basin)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var tm := TorusMesh.new()
	tm.rings = 28
	tm.ring_segments = 8
	tm.inner_radius = 0.44
	tm.outer_radius = 0.56
	rim.mesh = tm
	rim.material_override = rim_mat
	rim.position = Vector3(0, 0.43, 0)
	add_child(rim)
	# The liquid, brimming.
	pool = MeshInstance3D.new()
	pool.name = "Liquid"
	var pm := CylinderMesh.new()
	pm.radial_segments = 24
	pm.rings = 1
	pm.top_radius = 0.47
	pm.bottom_radius = 0.47
	pm.height = 0.02
	pool.mesh = pm
	var psh := Shader.new()
	psh.code = POOL_SHADER
	var pmat := ShaderMaterial.new()
	pmat.shader = psh
	pool.material_override = pmat
	pool.position = Vector3(0, BASE_Y, 0)
	add_child(pool)
	column = MeshInstance3D.new()
	column.name = "Jet"
	var col := CylinderMesh.new()
	col.radial_segments = 16
	col.rings = 12   # (rings for the wobble)
	col.top_radius = 0.14
	col.bottom_radius = 0.26
	col.height = COLUMN_HEIGHT
	col.cap_top = true   # (the camera looks down on it)
	col.cap_bottom = false
	column.mesh = col
	var sh := Shader.new()
	sh.code = FLOW_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = sh
	var drop_color := Color("#f07a1a")
	if _homeward():   # liquid light, gold
		for m in [smat, pmat]:
			m.set_shader_parameter("deep", Color(1.0, 0.88, 0.6))
			m.set_shader_parameter("glow", Color(1.0, 0.99, 0.93))
		drop_color = Color("#fff0c4")
	column.material_override = smat
	column.position = Vector3(0, BASE_Y + COLUMN_HEIGHT / 2.0, 0)
	add_child(column)
	# Drops thrown from the top of the jet, falling back into the basin.
	particles = CPUParticles3D.new()
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.amount = 10 if _light_mode() else 26
	particles.lifetime = 1.6
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.1
	particles.direction = Vector3.UP
	particles.spread = 22.0
	particles.gravity = Vector3(0, -3.0, 0)
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 0.95
	particles.scale_amount_min = 0.05
	particles.scale_amount_max = 0.09
	var dot := SphereMesh.new()
	dot.radial_segments = 8
	dot.rings = 4
	dot.radius = 0.5
	dot.height = 1.0
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = drop_color
	dmat.roughness = 0.05
	dmat.emission_enabled = true
	dmat.emission = drop_color
	dmat.emission_energy_multiplier = 0.35
	dot.material = dmat
	particles.mesh = dot
	particles.position = Vector3(0, BASE_Y + COLUMN_HEIGHT, 0)
	add_child(particles)
	lid = MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.radial_segments = 12
	lm.rings = 1
	lm.top_radius = 0.28
	lm.bottom_radius = 0.55
	lm.height = 0.14
	lid.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color("#f3e9d2")
	lmat.emission_enabled = true
	lmat.emission = Color("#ffe9a8")
	lmat.emission_energy_multiplier = 0.8
	lid.material_override = lmat
	lid.position = Vector3(0, 0.52, 0)
	add_child(lid)
	light = OmniLight3D.new()
	light.add_to_group("polox_lamp")
	light.light_color = Color("#ff9a3c")
	light.omni_range = 3.0
	light.position = Vector3(0, 1.2, 0)
	light.shadow_enabled = false
	light.light_cull_mask = ~APRON_LAYER
	add_child(light)
	add_child(BlockFactory.body(Vector3(1.0, 1.4, 1.0), Vector3(0, 0.7, 0), BlockFactory.LAYER_OBJECTS, {"kind": "object", "id": str(obj.get("id", ""))}))
	if not ghost and str(obj.get("label", "")) != "":
		var l := Label3D.new()
		l.text = str(obj.label)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 28
		l.pixel_size = 0.01
		l.outline_size = 8
		l.position = Vector3(0, 3.1, 0)
		# Over the gate's own jet: the jet's top is nearer the camera than the name above it, so the
		# depth test hid part of the name ("Drea  Gate"). A name is always drawn on top.
		l.no_depth_test = true
		l.render_priority = 10
		l.outline_render_priority = 9
		add_child(l)
	apply_state(state)
	if ghost:
		for m in find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).transparency = 0.6


## The way home: a gate leading to the Light World.
func _homeward() -> bool:
	return bool(obj.get("gate", false)) and str(obj.get("leads", "")) == "light"


func _light_mode() -> bool:
	return preload("res://scripts/core/graphics.gd").low_detail()   # Battery saver: fewer drops


## Shows the state with no animation.
func apply_state(s: String) -> void:
	state = s
	var open := s == "open"
	column.visible = open
	column.scale = Vector3.ONE
	particles.emitting = open
	lid.visible = s == "sealed"
	pool.visible = s != "sealed"
	(pool.material_override as ShaderMaterial).set_shader_parameter("calm", 0.0 if open else 0.9)
	light.light_energy = 1.2 if open else (0.5 if s == "sealed" else 0.25)
	light.light_color = Color("#ff9a3c") if s != "sealed" and not _homeward() else Color("#ffe9a8")
	if open and hum == null and is_inside_tree():
		_start_hum()
	elif not open and hum:
		hum.queue_free()
		hum = null


func _ready() -> void:
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
		mat.albedo_color = Color("#ffb066")
		cracks.material_override = mat
		add_child(cracks)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(obj.get("id", "f")))
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var p := Vector3(cos(a), 0.0, sin(a)) * 0.5
		var length := (1.2 + rng.randf() * 1.6) * progress
		var steps := 4
		for k in steps:
			var q := p + Vector3(cos(a + rng.randf_range(-0.6, 0.6)), 0, sin(a + rng.randf_range(-0.6, 0.6))) * (length / steps)
			im.surface_add_vertex(p + Vector3(0, 0.02, 0))
			im.surface_add_vertex(q + Vector3(0, 0.02, 0))
			p = q
	im.surface_end()
	cracks.mesh = im


## The fountain opens: cracks spread, the column rises, particles swirl, a rising sound. `m` is the
## Moment (skippable). Returns when done (or skipped: then it jumps to open).
func play_opening(m: Control, reduced: bool) -> void:
	apply_state("open")
	if reduced:
		await m.wait(0.2)
		return
	column.scale = Vector3(1, 0.02, 1)
	particles.amount = 40 if not _light_mode() else 14
	Synth.play(self, "whoosh", 0.5)
	var t := 0.0
	var total := 1.8
	var t0 := Time.get_ticks_msec()
	while t < total and is_instance_valid(m) and m.is_inside_tree():   # (a moment that left the tree no longer waits)
		if await m.wait(0.0333):
			break
		t = (Time.get_ticks_msec() - t0) / 1000.0
		var f := clampf(t / total, 0.0, 1.0)
		_crack_lines(minf(1.0, f * 1.6))
		column.scale = Vector3(1, maxf(0.02, ease(clampf((f - 0.25) / 0.75, 0.0, 1.0), 0.4)), 1)
		column.position.y = BASE_Y + COLUMN_HEIGHT * column.scale.y / 2.0
		light.light_energy = 0.3 + 1.6 * f
	column.scale = Vector3.ONE
	column.position.y = BASE_Y + COLUMN_HEIGHT / 2.0
	_crack_lines(1.0)
	light.light_energy = 1.2
	Synth.play(self, "chime", 0.35)


## The fountain is sealed: light gathers, the column sinks into the basin, the lid closes.
func play_sealing(m: Control, reduced: bool) -> void:
	if reduced:
		await m.wait(0.2)
		apply_state("sealed")
		return
	particles.initial_velocity_min = 0.1
	particles.initial_velocity_max = 0.3
	particles.gravity = Vector3(0, -5.0, 0)
	light.light_color = Color("#ffe9a8")
	Synth.play(self, "sparkle", 0.5)
	var t := 0.0
	var total := 1.6
	var t0 := Time.get_ticks_msec()
	while t < total and is_instance_valid(m) and m.is_inside_tree():   # (a moment that left the tree no longer waits)
		if await m.wait(0.0333):
			break
		t = (Time.get_ticks_msec() - t0) / 1000.0
		var f := clampf(t / total, 0.0, 1.0)
		column.scale = Vector3(1.0 - f * 0.6, maxf(0.02, 1.0 - f), 1.0 - f * 0.6)
		column.position.y = BASE_Y + COLUMN_HEIGHT * column.scale.y / 2.0
		light.light_energy = 1.2 + sin(f * PI) * 2.0
	if cracks:
		cracks.queue_free()
		cracks = null
	apply_state("sealed")
	Synth.play(self, "chime", 0.35)


## A glazed ceramic finish in colour `c`: smooth and bright, with a clear coat when the PC shows reflections.
static func _glaze(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.14 if _rich() else 0.26
	m.metallic_specular = 0.75 if _rich() else 0.55
	if _rich():
		m.clearcoat_enabled = true
		m.clearcoat = 0.9
		m.clearcoat_roughness = 0.06
	return m


## A PC showing reflections (Settings > Display > PC graphics): the richer finish.
static func _rich() -> bool:
	var PcDetail := preload("res://scripts/core/pc_detail.gd")
	var Graphics := preload("res://scripts/core/graphics.gd")
	if not PcDetail.available():
		return false
	return PcDetail.level_of("reflections", Graphics.pc_tier(GameState.settings), GameState.settings) >= 1


## The floor it stands on: a small apron of glazed white tiles (Poly Haven's long white tiles, through
## surface_materials.gd; a plain glaze on Battery saver).
func _apron() -> void:
	var pad := MeshInstance3D.new()
	pad.name = "TileApron"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.24, 0.02, 1.24)
	pad.mesh = bm
	var tile: Material = preload("res://scripts/world/surface_materials.gd").standard("ceramic", Color("#cdc4b6"))
	pad.material_override = tile if tile else _glaze(Color("#cdc4b6"))
	pad.position = Vector3(0, 0.011, 0)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lit by the room, not by the gate's own glow right above it: that light, a metre away on glossy
	# white tile, burned it out to a glowing slab (worst on phones, which have no tonemapping).
	pad.layers = APRON_LAYER
	add_child(pad)


var _poke_age := 9.0


## Touched (used, tapped, walked up to): a ring runs out across the liquid, on every preset (it's the cue
## that the gate heard you), and a soft plop.
func poke() -> void:
	_poke_age = 0.0
	set_process(true)
	if pool and pool.material_override:
		Synth.play(self, "pop", 0.25)


func poke_if(id: String) -> void:
	if str(obj.get("id", "")) == id:
		poke()


func _process(delta: float) -> void:
	if _poke_age >= 3.0:
		set_process(false)
		return
	_poke_age += delta
	if pool and pool.material_override is ShaderMaterial:
		(pool.material_override as ShaderMaterial).set_shader_parameter("poke_age", _poke_age)
