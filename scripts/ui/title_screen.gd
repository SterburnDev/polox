extends Control
## Title screen: Continue / New world / Worlds / Add-ons / Settings / Quit, over the starfield.
## The glass finish (STYLE_GUIDE.md "Glass"): the buttons sit on one glass card, Continue (or Begin) is
## the glossy primary, the logo keeps its picture and gets a faint watery reflection, and an aqua
## horizon glows under the stars with a few slow bubbles (still with Reduce motion).
## Layout: a column on PCs and upright phones (the buttons low, under the thumb); two columns when the
## screen is wide but short (a phone on its side), so every button stays on screen.
## Tags: [EASTER_EGG] [GLASS_UI]

signal continue_pressed
signal new_pressed
signal worlds_pressed
signal settings_pressed
signal addons_pressed
signal connect_pressed   # Polox for Android, not paired yet: Connect to your PC

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Starfield := preload("res://scripts/ui/starfield.gd")
const TouchGestures := preload("res://scripts/ui/touch_gestures.gd")
const HeartIcon := preload("res://scripts/ui/heart_icon.gd")
const LiquidGlass := preload("res://scripts/ui/liquid_glass.gd")
const Whimsy := preload("res://scripts/variety/whimsy.gd")
const Synth := preload("res://scripts/core/synth.gd")

## Where the lake begins (0..1 from the top): lower on a PC, higher on a tall phone (its buttons sit low).
const HORIZON := 0.7
const HORIZON_TALL := 0.6
## The reflection's height, as a share of the logo's.
const REFLECTION_SPAN := 0.34
## The primary key's sea-green glass.
const PRIMARY := Color("#1f9e9a")

## The Music secret's mark (settings_music_tab.gd): the Settings button reads 👀 until the game restarts.
const EYES := "👀"
static var eyes := false

var show_connect := false   # set by main.gd before the screen opens
var _heart: Control
var _wide := false
var _built := false
var _version_clicks := 0
var _secret_buffer := ""


func _ready() -> void:
	Synth.play(self, "motif_title", 0.45)
	UiKit.fill(self)
	_build()
	resized.connect(func():
		if _built and _is_wide() != _wide:
			_build())


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if key.unicode > 0:
		_feed_title_letter(key.unicode)


## Feeds typed letters into the title screen's playful secrets (mochi / bramin / yams / tub).
func feed_title_secret(text: String) -> String:
	var matched := ""
	for i in text.length():
		var hit := _feed_title_letter(text.unicode_at(i))
		if hit != "":
			matched = hit
	return matched


func _feed_title_letter(unicode_char: int) -> String:
	var next := Whimsy.push_letter(_secret_buffer, unicode_char)
	if next == _secret_buffer:
		return ""
	_secret_buffer = next
	var matched := Whimsy.match_suffix(_secret_buffer, Whimsy.TITLE_SECRET_WORDS)
	if matched == "":
		return ""
	_secret_buffer = ""
	var msg := Whimsy.title_secret_message(matched)
	if msg != "":
		GameState.notify(msg)
	Synth.play(self, "sparkle" if matched == "mochi" else "pop", 0.35)
	if _heart and is_instance_valid(_heart) and not bool(GameState.settings.get("reduce_motion", false)):
		var tw := create_tween()
		tw.tween_property(_heart, "scale", Vector2(1.22, 0.84), 0.1)
		tw.tween_property(_heart, "scale", Vector2(0.92, 1.14), 0.12)
		tw.tween_property(_heart, "scale", Vector2.ONE, 0.12)
	return matched


func _on_version_clicked(event: InputEvent) -> void:
	if UiKit.tap_down(event):
		_version_clicks += 1
		var quip := Whimsy.version_quip(_version_clicks)
		if quip != "":
			GameState.notify(quip)
		Synth.play(self, "sparkle" if _version_clicks == 5 else "tick", 0.35)


## Wide but short: a phone on its side, or a very flat window.
func _is_wide() -> bool:
	var s := get_viewport_rect().size
	return s.x > s.y * 1.45 and s.y < 640.0


## Quiet text laid straight on the painted scene (hills, water, glints) gets a dark edge round its
## letters, so it reads whatever is behind it: on the bright water it had fallen under 4.5 to 1.
static func _halo(l: Label) -> void:
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(ThemeBuilder.BG, 0.94))


func _build() -> void:
	for c in get_children():
		if c is AudioStreamPlayer:
			continue
		remove_child(c)
		c.queue_free()
	_wide = _is_wide()
	_built = true
	var short := get_viewport_rect().size.y < 800.0   # a PC window (720 units tall) or a short screen
	var bg := Starfield.new()
	bg.name = "Starfield"
	UiKit.fill(bg)
	add_child(bg)
	# [GLASS_UI] Frutiger Aero, in Polox's night: glossy hills on the horizon and a rippling lake.
	var scene := ColorRect.new()
	scene.name = "AeroScene"
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill(scene)
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/aero_backdrop.gdshader")
	sm.set_shader_parameter("still", 1.0 if bool(GameState.settings.get("reduce_motion", false)) else 0.0)
	scene.material = sm
	add_child(scene)
	var fit_scene := func():
		var s := get_viewport_rect().size
		sm.set_shader_parameter("aspect", s.x / maxf(s.y, 1.0))
		sm.set_shader_parameter("horizon", HORIZON_TALL if s.y > s.x else HORIZON)
	fit_scene.call()
	resized.connect(fit_scene)
	var horizon := AeroHorizon.new()
	horizon.name = "Bubbles"
	UiKit.fill(horizon)
	horizon.horizon = HORIZON_TALL if get_viewport_rect().size.y > get_viewport_rect().size.x else HORIZON
	add_child(horizon)
	var margin := MarginContainer.new()
	UiKit.fill(margin)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var outer: BoxContainer = HBoxContainer.new() if _wide else VBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 28 if _wide else 8)
	margin.add_child(outer)

	var brand := UiKit.vbox(4)
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.size_flags_vertical = Control.SIZE_EXPAND_FILL if _wide else Control.SIZE_SHRINK_CENTER
	outer.add_child(brand)
	# The Soul (soul.gd), beating gently.
	_heart = HeartIcon.new(64.0 if (_wide or short) else 84.0, ThemeBuilder.PINK)
	_heart.name = "TitleHeart"
	_heart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	brand.add_child(_heart)
	var logo_tex: Texture2D = preload("res://scripts/core/addons.gd").texture("logo")
	if logo_tex == null:
		logo_tex = preload("res://assets/icon/polox_logo.png")
	var title := TextureRect.new()
	title.name = "PoloxLogo"
	title.texture = logo_tex
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The logo is a big drawing shown small: smooth, from its mipmaps (the game's default nearest filter,
	# right for pixel art, left its edges stair-stepped).
	title.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	title.custom_minimum_size = Vector2(300, 95) if _wide else (Vector2(330, 100) if short else Vector2(360, 114))
	brand.add_child(title)
	# The logo's reflection, as on still water: the bottom of the same picture, upside down and at the
	# same size, fading out under it (the logo itself is never changed). A window onto a full-size copy:
	# squeezing the whole logo into the short strip had drawn a squashed dark smudge.
	var clip := Control.new()
	clip.name = "LogoReflection"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.custom_minimum_size = Vector2(title.custom_minimum_size.x, roundf(title.custom_minimum_size.y * REFLECTION_SPAN))
	clip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	clip.visible = not ThemeBuilder.solid
	var reflection := TextureRect.new()
	reflection.texture = logo_tex
	reflection.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reflection.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reflection.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	reflection.size = title.custom_minimum_size
	reflection.material = _reflection_material()
	reflection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(reflection)
	brand.add_child(clip)
	var release_label := str(ProjectSettings.get_setting("application/config/release_label", "Polox Public Beta 1.01"))
	var sub := UiKit.label(release_label, 22 if short else 26, ThemeBuilder.MUTED)
	sub.name = "VersionLabel"
	sub.mouse_filter = Control.MOUSE_FILTER_STOP
	sub.gui_input.connect(_on_version_clicked)
	_halo(sub)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(sub)
	if not _wide:
		# Upright phones: the buttons sit low, where the thumb is. PCs: the column stays centred.
		var gap := Control.new()
		gap.custom_minimum_size.y = 8
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL if UiKit.upright_phone() else Control.SIZE_SHRINK_CENTER
		outer.add_child(gap)

	# [GLASS_UI] The buttons float on Liquid Glass over the hills and the lake.
	var p := 8.0 if short else 14.0
	var card: PanelContainer = LiquidGlass.new()
	card.radius = ThemeBuilder.RADIUS_L + 6
	card.pad = Vector4(p + 4.0, p, p + 4.0, p)
	card.tint = Color(0.13, 0.1, 0.27, 0.42)
	card.name = "TitleCard"
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(card)
	var buttons := UiKit.vbox(8 if (_wide or short) else 12)
	buttons.name = "TitleButtons"
	buttons.custom_minimum_size.x = 320 if _wide else 360
	card.add_child(buttons)
	var has_world := GameState.has_world()
	var first: Button
	if has_world:
		first = UiKit.button("Continue", func(): continue_pressed.emit())
		buttons.add_child(first)
	var fresh := UiKit.button("New world" if has_world else "Begin", func(): new_pressed.emit())
	buttons.add_child(fresh)
	if first == null:
		first = fresh
	_primary(first)
	first.call_deferred("grab_focus")
	var n := preload("res://scripts/core/slots.gd").ids().size()
	buttons.add_child(UiKit.button("Worlds" + (" (%d)" % n if n > 1 else ""), func(): worlds_pressed.emit()))
	var addons := UiKit.button("Add-ons", func(): addons_pressed.emit())
	addons.name = "AddonsButton"
	buttons.add_child(addons)
	var settings := UiKit.button(EYES if eyes else "Settings", func(): settings_pressed.emit())
	settings.name = "SettingsButton"
	settings.tooltip_text = "Settings"
	buttons.add_child(settings)
	if show_connect:
		var c := UiKit.button("📱 Connect to your PC", func(): connect_pressed.emit())
		c.name = "ConnectToPC"
		buttons.add_child(c)
	if not OS.has_feature("web"):   # a browser tab can't quit itself
		buttons.add_child(UiKit.button("Quit", func(): get_tree().quit()))
	if _wide or short:
		for b in buttons.get_children():
			(b as Control).custom_minimum_size.y = 46 if _wide else 48

	var how := "Tap to walk or talk" if TouchGestures.phone_layout() else "Click to walk  •  WASD, E talk, C menu"
	var hint := UiKit.label(how, 18, Color(ThemeBuilder.MUTED, 0.8))
	_halo(hint)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _wide:
		brand.add_child(hint)
	else:
		outer.add_child(hint)


## The glossy primary action, Frutiger Aero: an aqua-to-sea-green key with a bright glassy top and a
## green glow rising in it, so the first step is obvious (and the same place every time: the top).
static func _primary(b: Button) -> void:
	var T := ThemeBuilder
	b.add_theme_stylebox_override("normal", T.key(PRIMARY, Color("#c8fff4"), T.RADIUS_M, 10, 1.0, Color("#7dffc4", 0.45), 1, 0.34))
	b.add_theme_stylebox_override("hover", T.key(PRIMARY.lightened(0.1), Color.WHITE, T.RADIUS_M, 10, 1.0, Color("#9dffd6", 0.55), 1, 0.4))
	b.add_theme_stylebox_override("pressed", T.key(PRIMARY.darkened(0.1), Color.WHITE, T.RADIUS_M, 10, 1.0, Color("#7dffc4", 0.3), 1, 0.2, T.KEY_DEPTH, true))
	b.add_theme_stylebox_override("focus", T.box(Color(0, 0, 0, 0), T.YELLOW, 3, T.RADIUS_M, 10))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("font_outline_color", Color("#0b4f5c", 0.7))


static func _reflection_material() -> ShaderMaterial:
	var sh: Shader = preload("res://shaders/logo_reflection.gdshader")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("still", 1.0 if bool(GameState.settings.get("reduce_motion", false)) else 0.0)
	m.set_shader_parameter("span", REFLECTION_SPAN)
	return m


## Glossy bubbles rising out of the lake and drifting up past the hills (Frutiger Aero's orbs): each
## with a glassy rim, a bright highlight and a faint aqua body. Still with Reduce motion.
class AeroHorizon extends Control:
	const AQUA := Color("#7fdcf0")
	var horizon := 0.7
	var _t := 0.0
	var _bubbles: Array = []   # [x 0..1, start 0..1, radius, speed]
	var _still := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # (the bubble picture, scaled smoothly)
		_still = bool(GameState.settings.get("reduce_motion", false))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 14:
			_bubbles.append([rng.randf(), rng.randf(), rng.randf_range(5.0, 20.0), rng.randf_range(0.01, 0.026)])
		set_process(not _still)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		for b in _bubbles:
			var y := fposmod(float(b[1]) - _t * float(b[3]), 1.0)
			var top := horizon - 0.42
			var p := Vector2(float(b[0]) * s.x + sin(_t * 0.7 + float(b[0]) * 9.0) * 12.0, s.y * (top + (1.0 - top) * y))
			var r := float(b[2])
			var a := 0.45 * clampf((1.0 - y) * 3.0, 0.0, 1.0) * clampf(y * 4.0, 0.0, 1.0)
			# One picture per bubble (drawn once, below): the same image in every draw batches into a
			# single call. Drawing each as five anti-aliased circles and arcs had cost about 6 ms a frame
			# on the phone renderer (some 125 draw calls), more than the whole rest of the title.
			draw_texture_rect(_bubble(), Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, a / 0.45))

	static var _bubble_tex: Texture2D

	## A glass bubble, 64 px: a faint aqua body, a light rim, a curved glint and a bright highlight.
	static func _bubble() -> Texture2D:
		if _bubble_tex:
			return _bubble_tex
		const N := 64
		var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
		var c := Vector2(N, N) / 2.0
		var r := N / 2.0 - 1.0
		for x in N:
			for y in N:
				var p := Vector2(x + 0.5, y + 0.5)
				var d := p.distance_to(c)
				var cover := clampf(r - d + 0.5, 0.0, 1.0)
				if cover <= 0.0:
					continue
				var col := Color(AQUA, 0.16 * 0.45)
				var rim := clampf(1.0 - absf(d - (r - 1.2)) / 1.6, 0.0, 1.0)
				col = col.blend(Color(1, 1, 1, 0.75 * 0.45 * rim))
				var ang := atan2(p.y - c.y, p.x - c.x)
				if ang < -PI * 0.55 and ang > -PI * 0.95:
					var g := clampf(1.0 - absf(d - r * 0.72) / 1.8, 0.0, 1.0)
					col = col.blend(Color(1, 1, 1, 0.6 * 0.45 * g))
				var hi := clampf((r * 0.2 - p.distance_to(c + Vector2(-r * 0.34, -r * 0.42))) / 1.5, 0.0, 1.0)
				col = col.blend(Color(1, 1, 1, 0.9 * 0.45 * hi))
				var lo := clampf((r * 0.12 - p.distance_to(c + Vector2(r * 0.3, r * 0.38))) / 1.5, 0.0, 1.0)
				col = col.blend(Color(AQUA, 0.5 * 0.45 * lo))
				img.set_pixel(x, y, Color(col, col.a * cover))
		img.generate_mipmaps()
		_bubble_tex = ImageTexture.create_from_image(img)
		return _bubble_tex
