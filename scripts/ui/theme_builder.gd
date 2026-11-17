extends RefCounted
## Builds the one cozy theme used everywhere, in code so the look lives in a single readable place (the
## rules are in STYLE_GUIDE.md). Big, rounded, high-contrast and easy to click. Every widget the game uses is
## themed here, so nothing looks like a default Godot control. The surfaces follow the world you're in:
## night violet in the Dream World, tea-brown in the Light World, ink in the Deep (set_world); the accents,
## cream text and shapes stay the same, so it's always the same game. The title is night violet too.
## Making a world (the Survey and the steps after it) uses the Survey's own look: "survey" is black,
## square and typewritten.
## Tags: [GLASS_UI]

# The world's surfaces (set_world changes these; new panels pick them up, the shared theme updates in place).
static var BG := Color("#120e24")
static var PANEL := Color("#1d1736")
static var PANEL_LIGHT := Color("#2e2552")
static var HOVER := Color("#3d3270")
static var MUTED := Color("#b8aed6")
static var world := "dark"

# The same everywhere.
const CREAM := Color("#f3e9d2")
const YELLOW := Color("#ffd166")
const PINK := Color("#e86a8a")
const MINT := Color("#7ad6b0")
const DANGER := Color("#ff7b7b")
## The glass finish's one extra accent: a restrained aqua, used for glows, the selected tab's underline
## and the "more below" cue. Never for text on light surfaces.
const AQUA := Color("#7fdcf0")

## Shared shapes and spacing (STYLE_GUIDE.md "Glass"): corner radii, gaps and the glass's own strengths.
const RADIUS_S := 10      # chips, small buttons, fields
const RADIUS_M := 14      # buttons, tabs, rows
const RADIUS_L := 20      # cards, toolbars, panels
const GAP := 10
const GLASS_ALPHA := 0.78      # buttons and navigation over the world
const BAR_ALPHA := 0.86        # toolbars docked over the world
const SOLID_ALPHA := 1.0       # panels with text, editors, property lists (opaque: at 0.97 the title's bright logo ghosted through Settings)

## Reduce transparency (Settings > Accessibility): every glass surface becomes solid, without sheen.
static var solid := false

const PALETTES := {
	"dark": {"bg": "#120e24", "panel": "#1d1736", "raised": "#2e2552", "hover": "#3d3270", "muted": "#b8aed6"},
	"light": {"bg": "#1c1612", "panel": "#2a201a", "raised": "#43342a", "hover": "#5a4635", "muted": "#d4c3ad"},
	"deep": {"bg": "#0b0a14", "panel": "#15132a", "raised": "#232046", "hover": "#302c63", "muted": "#a39fc9"},
	"survey": {"bg": "#000000", "panel": "#000000", "raised": "#141414", "hover": "#2a2a2a", "muted": "#9a958c"},
}
## The Survey's typewriter: the system's monospace, drawn without smoothing (survey_screen.gd uses it too).
const SURVEY_FONTS: PackedStringArray = ["Consolas", "Lucida Console", "Courier New", "DejaVu Sans Mono", "Noto Sans Mono", "monospace"]
const ANDROID_MONO: PackedStringArray = ["/system/fonts/DroidSansMono.ttf", "/system/fonts/CutiveMono.ttf"]
static var _square := false   # the survey look: corners stay square

const FONT_SIZE := 22
## The only text sizes (STYLE_GUIDE.md): fine print, quiet notes, body, list items, buttons, titles, big
## titles, and the moments.
const TYPE_SCALE := [14, 16, 18, 20, 22, 26, 32, 46, 56, 72]


static func box(bg: Color, border: Color = CREAM, border_w: int = 3, radius: int = 12, pad: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(mini(radius, 2) if _square else radius)
	sb.content_margin_left = pad + 4
	sb.content_margin_right = pad + 4
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.anti_aliasing = true
	return sb


## A glass surface (glass_box.gd): `alpha` is how much of the world shows through; Reduce transparency
## makes it opaque and drops the sheen. The Survey's square look keeps flat boxes.
static func glass(bg: Color, border: Color = Color(CREAM, 0.32), radius: int = RADIUS_M, pad: int = 10, alpha: float = GLASS_ALPHA, glow: Color = Color(0, 0, 0, 0), border_w: int = 1, sheen: float = 0.12) -> StyleBox:
	if _square:
		return box(Color(bg, 1.0), border, maxi(border_w, 2), radius, pad)
	var a := 1.0 if solid else alpha
	return preload("res://scripts/ui/glass_box.gd").make(Color(bg, a), border, radius, pad, 0.0 if solid else sheen, Color(0, 0, 0, 0) if solid else glow, border_w)


## A key: glass with a physical edge `depth` px deep under it (glass_box.gd), raised, or pressed down onto
## that edge with an inner shadow (`down`). The Survey's square look keeps its flat boxes.
static func key(bg: Color, border: Color, radius: int = RADIUS_M, pad: int = 10, alpha: float = GLASS_ALPHA, glow: Color = Color(0, 0, 0, 0), border_w: int = 1, sheen: float = 0.12, depth: int = KEY_DEPTH, down: bool = false) -> StyleBox:
	var s: StyleBox = glass(bg, border, radius, pad, alpha, glow, border_w, sheen)
	if s.has_method("with_depth"):
		s.with_depth(depth)
		if down:
			s = s.as_pressed()
	return s


## A recessed surface (early iOS): sunk into what's around it, with an inner shadow under its top edge
## and a light lower lip. An inventory slot, a tray, a display window. `inner` is the shadow's strength.
static func well(bg: Color, border: Color, radius: int = RADIUS_S, border_w: int = 2, inner: float = 0.45, pad: int = 6) -> StyleBox:
	var s: StyleBox = glass(bg, border, radius, pad, 1.0, Color(1, 1, 1, 0.05), border_w, 0.0)
	if s.get("inner") != null:
		s.inner = inner
		s.rim = 0.0
	return s


## How deep a key's edge is (px); a pressed key sits that much lower.
const KEY_DEPTH := 3


## A solid surface for text and editors: opaque enough to read over anything, with only a hint of rim.
static func solid_panel(radius: int = RADIUS_L, pad: int = 12) -> StyleBox:
	return box(Color(PANEL, SOLID_ALPHA), Color(CREAM, 0.3), 1, mini(radius, 2) if _square else radius, pad)


## A docked toolbar or a floating control bar over the world.
static func bar(radius: int = RADIUS_L, pad: int = 8) -> StyleBox:
	return glass(PANEL, Color(CREAM, 0.28), radius, pad, BAR_ALPHA)


## [GLASS_UI] Frutiger Aero's toolbar for the creator: aqua-tinted glass over Polox's night, a bright
## gloss across its top half, a light rim and a sea-green glow rising along its bottom.
const AERO := Color("#1d5f78")
const AERO_LIT := Color("#2fb6c9")
static func aero_bar(radius: int = RADIUS_L, pad: int = 6) -> StyleBox:
	return glass(AERO.darkened(0.12), Color("#9fe9f5", 0.65), radius, pad, 0.92, Color("#7dffc4", 0.28), 1, 0.36)


## A creator mode on the Aero bar: clear glass when it's not the open one; the open one lights up aqua
## and sits down in the bar (a pressed key), so where you are reads at a glance.
static func aero_toggle(b: Button) -> void:
	b.add_theme_stylebox_override("normal", key(PANEL.lerp(AERO, 0.35), Color("#9fe9f5", 0.35), RADIUS_M, 10, 0.55, Color(0, 0, 0, 0), 1, 0.16))
	b.add_theme_stylebox_override("hover", key(PANEL.lerp(AERO_LIT, 0.35), Color("#c8f6ff", 0.7), RADIUS_M, 10, 0.75, Color(AQUA, 0.3), 1, 0.22))
	for s in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(s, key(AERO_LIT, Color("#e6fdff"), RADIUS_M, 10, 1.0, Color("#7dffc4", 0.45), 1, 0.36, KEY_DEPTH, true))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_color_override("font_outline_color", Color("#0b3c4c", 0.6))


# --- Contrast (WCAG 2) ----------------------------------------------------------------------------------

static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


static func luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


## The contrast of two opaque colours, 1 (the same) to 21 (black on white). Text needs 4.5; large text
## (24 px and up) and the edges of controls need 3.
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## `top` drawn over an opaque `under`.
static func over(top: Color, under: Color) -> Color:
	return Color(top.r * top.a + under.r * (1.0 - top.a), top.g * top.a + under.g * (1.0 - top.a), top.b * top.a + under.b * (1.0 - top.a), 1.0)


## `ink` faded to `alpha` for quieter text on `surface` (a hint in an empty field), or as much stronger as
## it takes to stay readable there: at least `least` to 1.
static func faded(ink: Color, surface: Color, alpha: float, least: float = 4.5) -> Color:
	var a := alpha
	while a < 1.0 and contrast(over(Color(ink, a), surface), surface) < least:
		a = minf(1.0, a + 0.05)
	return Color(ink, a)


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	fill(t)
	return t


static var _survey_font: Font


static func survey_font() -> Font:
	if _survey_font == null:
		var sf := SystemFont.new()
		sf.font_names = SURVEY_FONTS
		sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_survey_font = sf
		# Android has a monospace font, but the system-font lookup doesn't find it there (seen on Android
		# 11: the Survey came out in the phone's ordinary sans-serif). Read Android's own file instead.
		if OS.has_feature("android"):
			for path in ANDROID_MONO:
				var ff := FontFile.new()
				if FileAccess.file_exists(path) and ff.load_dynamic_font(path) == OK:
					ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
					_survey_font = ff
					break
	return _survey_font


## Switches the surfaces to a world's palette ("dark", "light", "deep", or "survey" while a world is being
## made) and re-themes `t` in place, so every open screen changes with it.
static func set_world(w: String, t: Theme = null) -> void:
	var p: Dictionary = PALETTES.get(w, PALETTES.dark)
	world = w if PALETTES.has(w) else "dark"
	BG = Color(p.bg)
	PANEL = Color(p.panel)
	PANEL_LIGHT = Color(p.raised)
	HOVER = Color(p.hover)
	MUTED = Color(p.muted)
	_square = world == "survey"
	if t:
		t.default_font = survey_font() if _square else null
		fill(t)


static func fill(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", solid_panel())
	t.set_stylebox("panel", "Panel", solid_panel())

	# Buttons: ~52 px tall with the default font, comfortably over 48 px. Keys of glass with a glossy top
	# and an edge under them; hover brightens and adds a soft aqua glow; pressed (or selected) is the
	# yolk, sitting down on its edge with an inner shadow, so the label visibly goes down; disabled is
	# flat and faded (no gloss, no edge), so every state reads differently, not only by colour.
	for kind in ["Button", "MenuButton", "ColorPickerButton"]:
		t.set_stylebox("normal", kind, key(PANEL_LIGHT, Color(CREAM, 0.4), RADIUS_M, 10, 0.84))
		t.set_stylebox("hover", kind, key(HOVER, Color(CREAM, 0.85), RADIUS_M, 10, 0.92, Color(AQUA, 0.2)))
		t.set_stylebox("pressed", kind, key(YELLOW, CREAM, RADIUS_M, 10, 1.0, Color(0, 0, 0, 0), 1, 0.22, KEY_DEPTH, true))
		t.set_stylebox("hover_pressed", kind, key(YELLOW, Color.WHITE, RADIUS_M, 10, 1.0, Color(1, 1, 1, 0.12), 1, 0.26, KEY_DEPTH, true))
		var off := box(Color(PANEL_LIGHT, 0.35), Color(CREAM, 0.16), 1, RADIUS_M, 10)
		off.content_margin_top += KEY_DEPTH   # (level with a pressed key: no edge to stand on)
		t.set_stylebox("disabled", kind, off)
		t.set_stylebox("focus", kind, box(Color(0, 0, 0, 0), YELLOW, 3, RADIUS_M, 10))
		t.set_color("font_color", kind, CREAM)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_pressed_color", kind, BG)
		t.set_color("font_hover_pressed_color", kind, BG)
		t.set_color("font_focus_color", kind, Color.WHITE)
		t.set_color("font_disabled_color", kind, Color(CREAM, 0.35))

	for kind in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", kind, box(BG, Color(CREAM, 0.5), 2, 10, 10))
		t.set_stylebox("focus", kind, box(BG, YELLOW, 3, 10, 10))
		t.set_stylebox("read_only", kind, box(Color(BG, 0.6), Color(CREAM, 0.25), 2, 10, 10))
		t.set_color("font_color", kind, CREAM)
		t.set_color("font_placeholder_color", kind, faded(MUTED, BG, 0.6))
		t.set_color("caret_color", kind, YELLOW)
		t.set_color("selection_color", kind, Color(PINK, 0.45))

	t.set_color("font_color", "Label", CREAM)
	t.set_color("default_color", "RichTextLabel", CREAM)
	t.set_color("font_color", "LinkButton", YELLOW)
	t.set_color("font_hover_color", "LinkButton", Color.WHITE)
	t.set_color("font_pressed_color", "LinkButton", MINT)

	t.set_stylebox("normal", "OptionButton", key(PANEL_LIGHT, Color(CREAM, 0.4), RADIUS_M, 10, 0.84))
	t.set_stylebox("hover", "OptionButton", key(HOVER, Color(CREAM, 0.85), RADIUS_M, 10, 0.92, Color(AQUA, 0.2)))
	t.set_stylebox("pressed", "OptionButton", key(HOVER, YELLOW, RADIUS_M, 10, 0.95, Color(0, 0, 0, 0), 1, 0.12, KEY_DEPTH, true))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), YELLOW, 3, RADIUS_M, 10))
	t.set_stylebox("disabled", "OptionButton", box(Color(PANEL_LIGHT, 0.35), Color(CREAM, 0.16), 1, RADIUS_M, 10))
	t.set_color("font_color", "OptionButton", CREAM)
	t.set_icon("arrow", "OptionButton", _arrow_icon())

	t.set_stylebox("panel", "PopupMenu", box(PANEL, Color(CREAM, 0.6), 1, RADIUS_M, 8))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", BG)
	t.set_stylebox("hover", "PopupMenu", box(YELLOW, YELLOW, 0, RADIUS_S, 6))
	t.set_constant("v_separation", "PopupMenu", 12)
	t.set_stylebox("panel", "PopupPanel", box(PANEL, Color(CREAM, 0.6), 1, RADIUS_M, 8))

	t.set_stylebox("panel", "TooltipPanel", box(PANEL, Color(CREAM, 0.7), 1, RADIUS_S, 6))
	t.set_color("font_color", "TooltipLabel", CREAM)

	# Windows (the browser's file picker, any dialog): a panel like every other, with a cream title.
	t.set_stylebox("embedded_border", "Window", box(PANEL, CREAM, 3, 12, 12))
	t.set_stylebox("embedded_unfocused_border", "Window", box(PANEL, Color(CREAM, 0.5), 3, 12, 12))
	t.set_color("title_color", "Window", CREAM)
	t.set_stylebox("panel", "AcceptDialog", box(PANEL, Color(0, 0, 0, 0), 0, 0, 12))

	# Thick, easy-to-grab sliders and scrollbars, with a round yolk knob.
	t.set_stylebox("slider", "HSlider", box(PANEL_LIGHT, Color(CREAM, 0.4), 1, 6, 4))
	t.set_stylebox("grabber_area", "HSlider", box(YELLOW, YELLOW, 0, 6, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(YELLOW, YELLOW, 0, 6, 4))
	t.set_icon("grabber", "HSlider", _knob(false))
	t.set_icon("grabber_highlight", "HSlider", _knob(true))
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, box(Color(BG, 0.35), Color(0, 0, 0, 0), 0, 8, 6))
		t.set_stylebox("grabber", bar, box(Color(CREAM, 0.38), Color(0, 0, 0, 0), 0, 8, 6))
		t.set_stylebox("grabber_highlight", bar, box(YELLOW, Color(0, 0, 0, 0), 0, 8, 6))
		t.set_stylebox("grabber_pressed", bar, box(YELLOW, Color(0, 0, 0, 0), 0, 8, 6))

	t.set_stylebox("background", "ProgressBar", box(PANEL_LIGHT, Color(CREAM, 0.4), 2, 10, 2))
	t.set_stylebox("fill", "ProgressBar", box(MINT, Color(0, 0, 0, 0), 0, 10, 2))
	t.set_color("font_color", "ProgressBar", CREAM)

	for sep in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = Color(CREAM, 0.2)
		line.thickness = 2
		line.vertical = sep == "VSeparator"
		t.set_stylebox("separator", sep, line)

	for tabs in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", tabs, glass(PANEL_LIGHT, YELLOW, RADIUS_M, 10, 0.95, Color(AQUA, 0.16), 2))
		t.set_stylebox("tab_unselected", tabs, glass(PANEL, Color(CREAM, 0.26), RADIUS_M, 10, 0.7))
		t.set_stylebox("tab_hovered", tabs, glass(HOVER, Color(CREAM, 0.7), RADIUS_M, 10, 0.9, Color(AQUA, 0.16)))
		t.set_stylebox("tab_focus", tabs, box(Color(0, 0, 0, 0), YELLOW, 3, RADIUS_M, 10))
		t.set_color("font_selected_color", tabs, YELLOW)
		t.set_color("font_unselected_color", tabs, MUTED)
		t.set_color("font_hovered_color", tabs, Color.WHITE)
	t.set_stylebox("panel", "TabContainer", solid_panel(RADIUS_L, 12))

	t.set_stylebox("panel", "ItemList", box(BG, Color(CREAM, 0.4), 2, 10, 8))
	t.set_stylebox("selected", "ItemList", box(Color(YELLOW, 0.3), YELLOW, 1, 6, 4))
	t.set_stylebox("selected_focus", "ItemList", box(Color(YELLOW, 0.3), YELLOW, 1, 6, 4))
	t.set_constant("v_separation", "ItemList", 10)
	t.set_color("font_color", "ItemList", CREAM)

	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	for kind in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", kind, CREAM)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_pressed_color", kind, CREAM)
		t.set_color("font_hover_pressed_color", kind, Color.WHITE)
		t.set_color("font_focus_color", kind, Color.WHITE)
		t.set_stylebox("focus", kind, box(Color(0, 0, 0, 0), YELLOW, 2, 10, 4))
		# Their own calm rows: borrowing the button's yellow "pressed" look turned a ticked row yellow, which hid
		# the tick and made the cream text hard to read. Ticked or not shows in the box, not the row.
		var calm := glass(PANEL_LIGHT, Color(CREAM, 0.2), RADIUS_S + 2, 6, 0.55, Color(0, 0, 0, 0), 1, 0.06)
		var over := glass(HOVER, Color(CREAM, 0.45), RADIUS_S + 2, 6, 0.8, Color(AQUA, 0.14), 1, 0.08)
		for state in ["normal", "pressed", "disabled"]:
			t.set_stylebox(state, kind, calm)
		for state in ["hover", "hover_pressed"]:
			t.set_stylebox(state, kind, over)
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("radio_checked", "CheckBox", _radio_icon(true))
	t.set_icon("radio_unchecked", "CheckBox", _radio_icon(false))
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))

	# Number boxes: big arrows (the field itself is a themed LineEdit).
	for name in ["updown", "up", "up_hover", "up_pressed"]:
		t.set_icon(name, "SpinBox", _spin_icon(name == "updown", true))
	for name in ["down", "down_hover", "down_pressed"]:
		t.set_icon(name, "SpinBox", _spin_icon(false, false))


## 28 px chunky checkbox icons (the default ones are tiny).
## A box with a cream edge; ticked, a yolk square with a dark tick in it (readable on any row colour).
static func _check_icon(on: bool) -> Texture2D:
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 28:
		for y in 28:
			var edge := x < 3 or y < 3 or x > 24 or y > 24
			if edge:
				img.set_pixel(x, y, CREAM)
			elif on:
				img.set_pixel(x, y, YELLOW)
	if on:
		var ink := Color("#1d1736")
		for i in 6:   # the short stroke, down to the right
			for w in 3:
				img.set_pixel(7 + i, 13 + i + w - 1, ink)
		for i in 10:   # the long stroke, up to the right
			for w in 3:
				img.set_pixel(12 + i, 18 - i + w - 1, ink)
	return ImageTexture.create_from_image(img)


static func _radio_icon(on: bool) -> Texture2D:
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 28:
		for y in 28:
			var d := Vector2(x - 13.5, y - 13.5).length()
			if d <= 13.0 and d >= 10.5:
				img.set_pixel(x, y, CREAM)
			elif on and d <= 6.5:
				img.set_pixel(x, y, YELLOW)
	return ImageTexture.create_from_image(img)


## An on/off switch you could flick (early iOS): on, a glossy sea-green track with a "|" mark and the
## knob at the right; off, a dark, recessed track with an "O" mark and the knob at the left. The knob is a
## glossy pearl with a little shadow. Its state reads from the knob's side, the colour and the mark, so
## it never depends on colour alone. Drawn with soft (anti-aliased) edges.
static func _switch_icon(on: bool) -> Texture2D:
	const W := 60
	const H := 32
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := H / 2.0 - 1.0
	var cy := H / 2.0
	var kx := W - 1.0 - r if on else 1.0 + r
	for x in W:
		for y in H:
			var p := Vector2(x + 0.5, y + 0.5)
			# The track: a capsule.
			var cx := clampf(p.x, 1.0 + r, W - 1.0 - r)
			var d := Vector2(p.x - cx, p.y - cy).length()
			var cover := clampf(r - d + 0.5, 0.0, 1.0)
			if cover <= 0.0:
				continue
			var t := (p.y - 1.0) / (H - 2.0)   # 0 at the top
			var c: Color
			if on:
				c = Color("#3fd3a8").lerp(Color("#1c8f86"), t)
				if t < 0.45:
					c = c.lerp(Color.WHITE, 0.28 * (1.0 - t / 0.45))   # the gloss
			else:
				c = Color("#1a1530").lerp(Color("#3a3360"), t)   # darker at the top: recessed
			if d > r - 1.5:
				c = c.darkened(0.35) if not on else c.darkened(0.15)   # its rim
			# The marks: "|" on the left when on, "O" on the right when off.
			if on and absf(p.x - (1.0 + r)) < 1.1 and absf(p.y - cy) < 6.0:
				c = Color(1, 1, 1, 0.95)
			if not on and absf(Vector2(p.x - (W - 1.0 - r), p.y - cy).length() - 5.0) < 1.0:
				c = Color(CREAM, 0.7)
			# The knob, with a soft shadow under it.
			var kd := Vector2(p.x - kx, p.y - cy).length()
			var shade := clampf((r + 1.5 - Vector2(p.x - kx, p.y - cy - 1.5).length()) / 3.0, 0.0, 1.0)
			c = c.lerp(Color(0, 0, 0), shade * 0.35)
			var kr := r - 2.5
			var kcover := clampf(kr - kd + 0.5, 0.0, 1.0)
			if kcover > 0.0:
				var kt := (p.y - (cy - kr)) / (kr * 2.0)
				var kc := Color("#ffffff").lerp(Color("#d9d3e6"), kt)
				if kt > 0.55:
					kc = kc.darkened(0.08 * (kt - 0.55) / 0.45)
				c = c.lerp(kc, kcover)
			img.set_pixel(x, y, Color(c, c.a * cover))
	return ImageTexture.create_from_image(img)


## A tick box as a switch (Settings and the editors use CheckBox rows: themed to look like switches).
static func switch_icons() -> Array:
	if _switches.is_empty():
		_switches = [_switch_icon(true), _switch_icon(false)]
	return _switches


static var _switches: Array = []


## [GLASS_UI] iOS 7 for the screens that show a lot at once (Settings, the builder's inspector): a layer
## of its own over the main theme (anything not set here comes from it). Flat rows on one calm surface,
## a hairline between them, toggles drawn as switches, more room between rows and clear type,
## so there's less chrome and more to read. Buttons keep their keys (they're still things you press).
static func info_theme() -> Theme:
	var t := Theme.new()
	var sw := switch_icons()
	for kind in ["CheckBox", "CheckButton"]:
		var row := StyleBoxFlat.new()
		row.bg_color = Color(0, 0, 0, 0)
		row.border_color = Color(CREAM, 0.12)
		row.border_width_bottom = 1
		row.content_margin_left = 4
		row.content_margin_right = 6
		row.content_margin_top = 8
		row.content_margin_bottom = 8
		var over := row.duplicate() as StyleBoxFlat
		over.bg_color = Color(CREAM, 0.06)
		over.set_corner_radius_all(RADIUS_S)
		for state in ["normal", "pressed", "disabled"]:
			t.set_stylebox(state, kind, row)
		for state in ["hover", "hover_pressed"]:
			t.set_stylebox(state, kind, over)
		t.set_icon("checked", kind, sw[0])
		t.set_icon("unchecked", kind, sw[1])
		t.set_icon("checked_disabled", kind, sw[0])
		t.set_icon("unchecked_disabled", kind, sw[1])
		t.set_constant("h_separation", kind, 12)
		t.set_color("font_color", kind, CREAM)
		t.set_color("font_pressed_color", kind, CREAM)
	t.set_constant("separation", "VBoxContainer", 14)
	t.set_color("font_color", "Label", Color(CREAM, 0.96))
	t.set_stylebox("panel", "TabContainer", box(Color(PANEL_LIGHT.lerp(PANEL, 0.55), 0.98), Color(CREAM, 0.1), 1, RADIUS_L, 16))
	return t


static func _knob(hot: bool) -> Texture2D:
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 28:
		for y in 28:
			var d := Vector2(x - 13.5, y - 13.5).length()
			if d <= 12.5:
				img.set_pixel(x, y, CREAM if d > 10.0 else (Color.WHITE if hot else YELLOW))
	return ImageTexture.create_from_image(img)


static func _arrow_icon() -> Texture2D:
	var img := Image.create(20, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 10:
		for x in range(y, 20 - y):
			img.set_pixel(x, y + 2, CREAM)
	return ImageTexture.create_from_image(img)


## A number box's arrows: both (the combined icon) or just up / down.
static func _spin_icon(both: bool, up: bool) -> Texture2D:
	var img := Image.create(24, 32 if both else 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var draw := func(top: int, pointing_up: bool) -> void:
		for i in 8:
			var y := top + (7 - i if pointing_up else i)
			for x in range(4 + i, 20 - i):
				img.set_pixel(x, y, CREAM)
	if both:
		draw.call(4, true)
		draw.call(20, false)
	else:
		draw.call(4, up)
	return ImageTexture.create_from_image(img)
