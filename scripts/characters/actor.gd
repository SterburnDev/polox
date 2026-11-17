extends Node3D
## A paper-doll billboard person: the player or a resident. Walks along
## grid paths with a little bob and squash, breathes while idle, can glow
## with a coloured aura, and shows speech bubbles and emotes over its head.

signal arrived

const BlockFactory := preload("res://scripts/world/block_factory.gd")
const EmoteMotion := preload("res://scripts/characters/emote_motion.gd")
const ActorAnim := preload("res://scripts/characters/actor_anim.gd")
const HEIGHT := 1.3

var actor_id := ""
var display_name := ""
var is_player := false
var speed := 3.4
var sprite: Sprite3D
var name_label: Label3D
var bubble: Label3D
var _path: Array[Vector3] = []
var _t := randf() * 10.0
var _bubble_timer := 0.0
var _moving := false
var steering := false            # continuous exploration, owned by player_controller
## Movement happens in physics ticks; frames in between show the actor part-way
## between its last two tick positions, so walking is smooth on any screen rate.
var smooth_motion := true
var _logic := Vector3.ZERO        # where the last physics tick put it
var _prev := Vector3.ZERO         # where the tick before put it
var _visual: Node3D              # interpolated artwork; collision and cell position stay authoritative
var _synced_tick := -1
var tint := Color.WHITE
var react_px := Vector2.ZERO      # animated by react(), in sprite pixels
var react_scale := Vector2.ONE
var _react_tween: Tween
var _blink_t := randf_range(2.0, 5.0)
var _blinking := 0.0
var _open_tex: Texture2D             # the face a blink goes back to
var _aura: MeshInstance3D
var _aura_color := Color.WHITE
var anim: Node                    # actor_anim.gd: idle/walk/run/jump/fall/land frames + generated motion


func setup(id: String, label_text: String, texture: Texture2D, player: bool = false) -> void:
	actor_id = id
	display_name = label_text
	is_player = player
	_visual = Node3D.new()
	_visual.name = "Artwork"
	add_child(_visual)
	sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(sprite)
	set_texture(texture)
	_visual.add_child(_make_shadow())
	name_label = _label(label_text, 30, Color("#f3e9d2"))
	name_label.position.y = HEIGHT + 0.25
	name_label.visible = not player and label_text != ""
	_visual.add_child(name_label)
	bubble = _label("", 34, Color.WHITE)
	bubble.position.y = HEIGHT + 0.6
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 520.0
	bubble.visible = false
	_visual.add_child(bubble)
	if not player:
		var body := BlockFactory.body(Vector3(0.8, HEIGHT, 0.8), Vector3(0, HEIGHT / 2.0, 0), BlockFactory.LAYER_ACTORS, {"kind": "character", "id": id})
		add_child(body)
	anim = ActorAnim.new()
	anim.name = "Anim"
	add_child(anim)
	anim.setup(self)


func set_texture(tex: Texture2D) -> void:
	if tex == null:
		return
	_blinking = 0.0
	if sprite.has_meta("blink_of"):
		sprite.remove_meta("blink_of")
	sprite.texture = tex
	sprite.pixel_size = HEIGHT / maxf(1.0, tex.get_height())
	sprite.position.y = HEIGHT / 2.0


func set_tint(c: Color) -> void:
	tint = c
	if sprite:
		sprite.modulate = c


func _label(text: String, font_size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color("#120e24")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.double_sided = true
	return l


## Soft round shadow under the feet (cheaper and cozier than real shadows).
func _make_shadow() -> MeshInstance3D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var r := Vector2(x - 15.5, y - 15.5).length() / 16.0
			img.set_pixel(x, y, Color(0.05, 0.02, 0.1, clampf(1.0 - r, 0.0, 1.0) * 0.5))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.rotation.x = -PI / 2.0
	mi.position.y = 0.01
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A soft glowing disc under the feet (items can tint it). Off with enabled=false.
func set_aura(color: Color, enabled: bool = true) -> void:
	if not enabled:
		if _aura:
			_aura.visible = false
		return
	if _aura == null:
		var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
		for y in 48:
			for x in 48:
				var r := Vector2(x - 23.5, y - 23.5).length() / 24.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) * clampf(r * 2.5, 0.0, 1.0)))
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var q := QuadMesh.new()
		q.size = Vector2(1.6, 1.6)
		_aura = MeshInstance3D.new()
		_aura.mesh = q
		_aura.material_override = mat
		_aura.rotation.x = -PI / 2.0
		_aura.position.y = 0.02
		_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(_visual if _visual != null else self).add_child(_aura)
	_aura_color = color
	_aura.visible = true


func aura_on() -> bool:
	return _aura != null and _aura.visible


func walk(points: Array[Vector3]) -> void:
	steering = false
	_path = points.duplicate()
	_moving = not _path.is_empty()
	if not _moving:
		arrived.emit()


func stop() -> void:
	steering = false
	_path.clear()
	_moving = false


func is_moving() -> bool:
	return _moving


func _physics_process(delta: float) -> void:
	physics_sync()
	advance_path(delta)
	physics_commit()


## Called first in a physics tick (by this actor or its controller, once per tick):
## records the starting position without moving collision bodies during rendering.
func physics_sync() -> void:
	var tick := Engine.get_physics_frames()
	if tick == _synced_tick:
		return
	_synced_tick = tick
	_logic = position
	_prev = _logic


## Called after a tick moved the actor.
func physics_commit() -> void:
	_logic = position


func _smooth_position() -> void:
	if _visual == null:
		return
	if not smooth_motion:
		_visual.position = Vector3.ZERO
		return
	if not position.is_equal_approx(_logic):
		_logic = position   # moved from outside between ticks
		_prev = position
	var p := _logic
	if _prev.distance_squared_to(_logic) < 1.0:
		p = _prev.lerp(_logic, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))
	_visual.position = p - position


## Spend the whole distance budget, including short waypoints at corners.
func advance_path(delta: float) -> void:
	var step := speed * maxf(0.0, delta)
	while _moving and not _path.is_empty() and step > 0.000001:
		var target := _path[0]
		var to := target - position
		to.y = 0.0
		if to.length() <= step + 0.000001:
			step = maxf(0.0, step - to.length())
			position = Vector3(target.x, position.y, target.z)
			_path.pop_front()
			if _path.is_empty():
				_moving = false
				arrived.emit()
				return  # callbacks may change rooms, free this actor or queue a new path
		else:
			position += to.normalized() * step
			_face_screen_dir(to)
			break


func set_steering_motion(direction: Vector3) -> void:
	steering = true
	_path.clear()
	_moving = direction.length() > 0.01
	if _moving:
		_face_screen_dir(direction)


func _process(delta: float) -> void:
	_smooth_position()
	_t += delta
	# Walking on the grid: the walk frames (if any) while moving, idle ones otherwise.
	if anim and not anim.manual and not anim.frames.is_empty():
		anim.set_state("walk" if _moving else "idle")
	# Bob while walking (squashing a little on each landing), breathe gently while idle.
	if sprite and not (anim and anim.manual):
		var base := Vector3.ONE
		if _moving:
			var hop := absf(sin(_t * 12.0))
			sprite.position.y = HEIGHT / 2.0 + hop * 0.08
			var squash := (1.0 - hop) * (1.0 - hop) * 0.08
			base = Vector3(1.0 + squash, 1.0 - squash, 1.0)
		else:
			sprite.position.y = HEIGHT / 2.0
			base = Vector3(1.0 + sin(_t * 2.2) * 0.012, 1.0 - sin(_t * 2.2) * 0.02, 1.0)
		sprite.scale = base * Vector3(react_scale.x, react_scale.y, 1.0)
		# Scale from the feet so bounces don't sink into the floor.
		var lift := (react_scale.y - 1.0) * HEIGHT / 2.0
		sprite.position.y += react_px.y * sprite.pixel_size + lift
		sprite.offset.x = react_px.x  # pixels in the sprite's own (camera-facing) frame
	if _aura and _aura.visible:
		var mat := _aura.material_override as StandardMaterial3D
		mat.albedo_color = Color(_aura_color, 0.45 + 0.2 * sin(_t * 3.0))
		_aura.scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 3.0))
	_blink(delta)
	if _bubble_timer > 0.0:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			bubble.visible = false


## A blink every few seconds (pictures where the eyes can be found; not with Reduce motion).
func _blink(delta: float) -> void:
	if sprite == null or sprite.texture == null:
		return
	if has_meta(&"polox_transforming"):
		return
	if _blinking > 0.0:
		_blinking -= delta
		if _blinking <= 0.0 and _open_tex and sprite.texture != _open_tex and sprite.has_meta("blink_of"):
			sprite.texture = _open_tex
			sprite.remove_meta("blink_of")
		return
	_blink_t -= delta
	if _blink_t > 0.0:
		return
	_blink_t = randf_range(2.6, 5.6)
	if bool(GameState.settings.get("reduce_motion", false)) or _moving or (anim and anim.manual):
		return
	var shut: Texture2D = preload("res://scripts/characters/blink.gd").texture_for(sprite.texture)
	if shut == null:
		return
	_open_tex = sprite.texture
	sprite.texture = shut
	sprite.set_meta("blink_of", true)
	_blinking = 0.12


func _face_screen_dir(dir: Vector3) -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or sprite == null:
		return
	var side := dir.normalized().dot(cam.global_transform.basis.x)
	if side < -0.2:
		sprite.flip_h = true
	elif side > 0.2:
		sprite.flip_h = false
	if anim:
		anim.facing = -1.0 if sprite.flip_h else 1.0


## Body language for an expression: bounce, shake, droop...
func react(emotion: String) -> void:
	var steps := EmoteMotion.steps(emotion)
	if steps.is_empty():
		return
	if _react_tween:
		_react_tween.kill()
	_react_tween = create_tween()
	for s in steps:
		_react_tween.tween_property(self, "react_px", s[0], s[2]).set_trans(Tween.TRANS_SINE)
		_react_tween.parallel().tween_property(self, "react_scale", s[1], s[2]).set_trans(Tween.TRANS_SINE)


## Shows a speech bubble over the head for a few seconds.
func say(text: String, seconds: float = 4.0) -> void:
	bubble.text = text
	bubble.visible = true
	_bubble_timer = seconds


## Pops a little symbol ("!", "♥", "♪", "z") above the head.
## Pixel speech-balloon pictures for the usual feelings (Kenney's CC0 Emotes pack, assets/kenney/emotes/);
## any other symbol floats up as text.
const EMOTES := {"♥": "heart", "♪": "music", "✦": "stars", "z": "sleep", "★": "star", "?": "question", "!": "exclamation", "~": "swirl"}
static var _emote_tex: Dictionary = {}


static func emote_texture(symbol: String) -> Texture2D:
	if not EMOTES.has(symbol):
		return null
	if not _emote_tex.has(symbol):
		var path := "res://assets/kenney/emotes/emote_%s.png" % EMOTES[symbol]
		_emote_tex[symbol] = load(path) if ResourceLoader.exists(path) else null
	return _emote_tex[symbol]


func emote(symbol: String, color: Color = Color("#ffd166")) -> void:
	var l: Node3D
	var tex := emote_texture(symbol)
	if tex:
		var s := Sprite3D.new()
		s.texture = tex
		s.pixel_size = 0.03                 # 16 px: about half a metre
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.no_depth_test = true
		s.render_priority = 10
		s.shaded = false
		s.double_sided = true
		l = s
	else:
		l = _label(symbol, 64, color)
	l.position.y = HEIGHT + 0.3
	(_visual if _visual != null else self).add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", HEIGHT + 0.9, 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.5)
	tw.tween_callback(l.queue_free)


func cell() -> Vector2i:
	return Vector2i(floori(position.x), floori(position.z))
