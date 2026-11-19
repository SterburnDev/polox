extends Node
## Animation states for an actor (actor.gd): idle, walk, run, jump, fall,
## land. Each state can have its own frames (1-8 pictures + fps + loop,
## mirrored automatically for left/right). Without frames, generated motion
## makes every state look different from the base picture: running leans
## forward with a quicker bob, dust puffs and a faint afterimage; a jump
## stretches, a fall leans back, a landing squashes with a puff of dust.
## Footsteps call `on_step` (Platform Mode plays the tile's step sound).
##
## Free movement (Platform Mode) sets `manual`: the sprite then faces the
## camera by itself so it can lean (a normal billboard can't tilt).

const STATES: PackedStringArray = ["idle", "walk", "run", "jump", "fall", "land"]

var actor: Node3D                 # actor.gd
var frames: Dictionary = {}       # state -> {tex: [Texture2D], fps, loop}
var state := "idle"
var facing := 1.0                 # +1 right, -1 left (on screen)
var manual := false               # Platform Mode: lean + generated motion drive the sprite
var on_step: Callable = Callable()
var base_texture: Texture2D
var _t := 0.0
var _state_t := 0.0
var _frame := 0
var _frame_t := 0.0
var _last_hop := 0
var _after_t := 0.0
var _after_pool: Array = []
var _run_dust: CPUParticles3D
var _land_dust: CPUParticles3D
var _lean := 0.0
var _scale := Vector2.ONE


func setup(owner_actor: Node3D) -> void:
	actor = owner_actor
	base_texture = actor.sprite.texture if actor.sprite else null
	_run_dust = _dust(false)
	_land_dust = _dust(true)
	actor.add_child(_run_dust)
	actor.add_child(_land_dust)


## {state: {frames: [res paths], fps, loop}} as stored in the character / form data.
func load_frames(anims: Variant) -> void:
	frames.clear()
	if not anims is Dictionary:
		return
	for s in anims:
		var a: Variant = anims[s]
		if not a is Dictionary or not str(s) in STATES:
			continue
		var tex: Array = []
		for p in a.get("frames", []):
			var t: Texture2D = SaveManager.load_texture(str(p)) if str(p) != "" else null
			if t:
				tex.append(t)
		if not tex.is_empty():
			frames[str(s)] = {"tex": tex, "fps": clampf(float(a.get("fps", 8)), 1.0, 24.0), "loop": bool(a.get("loop", str(s) in ["idle", "walk", "run", "fall"]))}


## Ready-made frames (e.g. the doll maker's built-in run cycle) for states without custom ones.
func add_generated(state_id: String, textures: Array, fps: float, loop: bool = true) -> void:
	if not frames.has(state_id) and not textures.is_empty():
		frames[state_id] = {"tex": textures, "fps": fps, "loop": loop, "generated": true}


func has_custom(state_id: String) -> bool:
	return frames.has(state_id) and not bool(frames[state_id].get("generated", false))


func set_state(s: String, face: float = 0.0) -> void:
	if face != 0.0:
		facing = signf(face)
	if s == state:
		return
	if s == "land":
		_land_dust.restart()
		_land_dust.emitting = true
	state = s
	_state_t = 0.0
	_frame = 0
	_frame_t = 0.0


## The picture this state shows right now ("" texture = the base picture).
func current_texture() -> Texture2D:
	var f: Variant = frames.get(state)
	if f == null and state == "land":
		f = frames.get("idle")   # no landing frames: the idle ones (or the base picture)
	if f == null:
		return base_texture
	var tex: Array = f.tex
	return tex[clampi(_frame, 0, tex.size() - 1)]


func _process(delta: float) -> void:
	if actor == null or actor.sprite == null:
		return
	if actor.has_meta(&"polox_transforming"):
		return
	_t += delta
	_state_t += delta
	var f: Variant = frames.get(state)
	if f == null and state == "land":
		f = frames.get("idle")
	if f != null:
		_frame_t += delta
		var step := 1.0 / float(f.fps)
		while _frame_t >= step:
			_frame_t -= step
			_frame += 1
			if _frame >= (f.tex as Array).size():
				_frame = 0 if bool(f.loop) else (f.tex as Array).size() - 1
	# Outside free movement only states with frames touch the picture (faces and
	# the talk pose stay the actor's own).
	if manual or f != null:
		var tex := current_texture()
		if tex and actor.sprite.texture != tex:
			actor.set_texture(tex)
	if manual:
		actor.sprite.flip_h = facing < 0.0
	_run_dust.emitting = manual and state == "run"
	if not manual:
		return
	_generated_motion(delta)
	_footsteps()
	_afterimages(delta)


## Lean, bob and squash per state (on top of any frames).
func _generated_motion(delta: float) -> void:
	var lean := 0.0
	var bob := 0.0
	var sc := Vector2.ONE
	match state:
		"idle":
			sc = Vector2(1.0 + sin(_t * 2.2) * 0.012, 1.0 - sin(_t * 2.2) * 0.02)
		"walk":
			var hop := absf(sin(_t * 12.0))
			bob = hop * 0.07
			var squash := (1.0 - hop) * (1.0 - hop) * 0.06
			sc = Vector2(1.0 + squash, 1.0 - squash)
			lean = 0.05
		"run":
			var hop := absf(sin(_t * 17.0))
			bob = hop * 0.11
			var squash := (1.0 - hop) * (1.0 - hop) * 0.1
			sc = Vector2(1.0 + squash, 1.0 - squash)
			lean = 0.2
		"jump":
			sc = Vector2(0.86, 1.16)
			lean = 0.08
		"fall":
			sc = Vector2(1.05, 0.97)
			lean = -0.14
		"land":
			var k := clampf(_state_t / 0.14, 0.0, 1.0)
			sc = Vector2(1.25, 0.78).lerp(Vector2.ONE, k)
	_lean = lerpf(_lean, lean * facing, 1.0 - exp(-14.0 * delta))
	_scale = _scale.lerp(sc, 1.0 - exp(-18.0 * delta))
	var s: Sprite3D = actor.sprite
	var h: float = actor.HEIGHT
	s.position = Vector3(0, h / 2.0 * _scale.y + bob, 0)
	var cam := actor.get_viewport().get_camera_3d() if actor.is_inside_tree() else null
	if cam:
		var b := cam.global_transform.basis.orthonormalized() * Basis(Vector3(0, 0, 1), -_lean)
		s.global_transform = Transform3D(b, s.global_position)
	s.scale = Vector3(_scale.x, _scale.y, 1.0)


func _footsteps() -> void:
	if not state in ["walk", "run"]:
		return
	var hop := int(floor(_t * (17.0 if state == "run" else 12.0) / PI))
	if hop != _last_hop:
		_last_hop = hop
		if on_step.is_valid():
			on_step.call(state)


## A faint copy left behind every few frames while running.
func _afterimages(delta: float) -> void:
	_after_t -= delta
	if state != "run" or _after_t > 0.0 or not actor.is_inside_tree():
		return
	_after_t = 0.07
	var ghost: Sprite3D = null
	for g in _after_pool:
		if is_instance_valid(g) and not g.visible:
			ghost = g
			break
	if ghost == null:
		if _after_pool.size() >= 5:
			return
		ghost = Sprite3D.new()
		ghost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ghost.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		ghost.shaded = false
		ghost.transparent = true
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		actor.get_parent().add_child(ghost)
		_after_pool.append(ghost)
	var s: Sprite3D = actor.sprite
	ghost.texture = s.texture
	ghost.pixel_size = s.pixel_size
	ghost.flip_h = s.flip_h
	ghost.global_position = s.global_position
	ghost.modulate = Color(1, 1, 1, 0.35)
	ghost.visible = true
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func(): ghost.visible = false)


func _dust(burst: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # see-through puffs cast no shadow
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.95, 0.9, 1.0, 0.55)
	m.albedo_texture = _puff_texture()
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	p.position.y = 0.05
	p.emitting = false
	p.one_shot = burst
	p.amount = 10 if burst else 6
	p.lifetime = 0.45
	p.explosiveness = 0.9 if burst else 0.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -1.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.7))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	return p


static var _puff: Texture2D


## A soft round puff (the dust looked like squares without it).
static func _puff_texture() -> Texture2D:
	if _puff == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				var r := Vector2(x - 7.5, y - 7.5).length() / 8.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) * clampf(1.0 - r, 0.0, 1.0)))
		_puff = ImageTexture.create_from_image(img)
	return _puff


## Free movement on: the sprite faces the camera itself (so it can lean).
func begin_manual() -> void:
	manual = true
	if actor and actor.sprite:
		base_texture = actor.sprite.texture
		actor.sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED


## Back to plain billboard (leaving Platform Mode).
func reset_sprite() -> void:
	manual = false
	_run_dust.emitting = false
	if actor and actor.sprite:
		actor.sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		actor.sprite.transform = Transform3D(Basis.IDENTITY, Vector3(0, actor.HEIGHT / 2.0, 0))
	for g in _after_pool:
		if is_instance_valid(g):
			g.queue_free()
	_after_pool.clear()
	set_state("idle")
	if base_texture:
		actor.set_texture(base_texture)
