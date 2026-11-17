extends Control
## First-run welcome: three gentle steps (your world, about you, your first
## friend), then straight into the world next to that friend. Everything is
## optional except a name for the friend; typical time well under 5 minutes.

## choices: {world_name, player_name, life, dream, look, friend_name, color, personality, speech_style, draw_own}
signal finished(choices: Dictionary)
signal cancelled

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Starfield := preload("res://scripts/ui/starfield.gd")
const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const Doll := preload("res://scripts/characters/doll.gd")
const LOOKS: PackedStringArray = ["cozy", "gardener", "mage", "sleepy", "night"]

const COLORS := ["#c9b6ff", "#ffb3c7", "#7ad6b0", "#8fd3ff", "#ffd166", "#ff9f43"]
const VIBES := [
	["Gentle & curious", "Gentle, curious and a little dramatic about snacks. Thinks every small win deserves a celebration.", "soft and playful, short sentences, sometimes ends with ~"],
	["Bubbly & silly", "Bubbly, silly and endlessly enthusiastic. Loves puns, terrible jokes and hyping you up.", "excitable, lots of exclamation marks, makes up nicknames"],
	["Calm & wise", "Calm, thoughtful and kind. Notices small things and asks good questions.", "slow and warm, gentle metaphors, never rushes"],
	["Grumpy but sweet", "A little grumpy on the outside, secretly the most caring friend you'll ever have.", "dry humor, short replies, softens when you're sad"],
]

var step := 0
var _pages: Array[Control] = []
var _world_name: LineEdit
var _player_name: LineEdit
var _life: TextEdit
var _dream: LineEdit
var _friend_name: LineEdit
var _color := COLORS[0]
var _vibe := 0
var _preview: TextureRect
var _vibe_btns: Array[Button] = []
var _dots: Label
var _look := "cozy"
var _look_btns: Dictionary = {}


func _ready() -> void:
	UiKit.fill(self)
	var bg := Starfield.new()
	UiKit.fill(bg)
	add_child(bg)
	var center := CenterContainer.new()
	UiKit.fill(center)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(900, get_viewport_rect().size.x - 40), 0)
	center.add_child(panel)
	var v := UiKit.vbox(14)
	panel.add_child(v)
	_dots = UiKit.label("", 22, ThemeBuilder.YELLOW)
	_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_dots)
	_pages = [_page_world(), _page_life(), _page_friend()]
	for p in _pages:
		v.add_child(p)
	_show(0)


func _page_world() -> Control:
	var p := UiKit.vbox(12)
	p.add_child(_title("Welcome! Let's make your pocket world."))
	p.add_child(UiKit.para("A little place that's all yours: friends who remember you, rooms you build, and your real dreams on the wall. About two minutes to set up.", 22, ThemeBuilder.MUTED))
	_world_name = UiKit.line_edit("My Pocket World")
	p.add_child(UiKit.field_row("World name", _world_name, 200))
	_player_name = UiKit.line_edit("What should friends call you?")
	_player_name.text_submitted.connect(func(_t): _show(1))
	p.add_child(UiKit.field_row("Your name", _player_name, 200))
	p.add_child(_nav([["Back", func(): cancelled.emit()], ["Next", func(): _show(1)]]))
	return p


func _page_life() -> Control:
	var p := UiKit.vbox(12)
	p.add_child(_title("A little about you (optional)"))
	p.add_child(UiKit.para("Your friends read this, so they can ask about your real day. Share only what you like; it stays on this PC.", 20, ThemeBuilder.MUTED))
	_life = UiKit.text_edit("e.g. I'm a student and work weekends at a bakery. Lately I've been stressed about exams. I have a cat named Pudding.", "", 110)
	p.add_child(_life)
	_dream = UiKit.line_edit("One dream you'd love to chase, e.g. learn guitar, see the ocean")
	p.add_child(UiKit.field_row("A dream", _dream, 150))
	var looks := UiKit.hbox(8)
	var cap := UiKit.label("You look like", 20)
	cap.custom_minimum_size.x = 150
	looks.add_child(cap)
	for id in LOOKS:
		var b := Button.new()
		b.icon = ImageTexture.create_from_image(Doll.compose(Doll.preset(id), "happy"))
		b.expand_icon = true
		b.custom_minimum_size = Vector2(64, 64)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.toggle_mode = true
		b.tooltip_text = str(Doll.PRESETS[id][0])
		b.pressed.connect(func(): _pick_look(id))
		_look_btns[id] = b
		looks.add_child(b)
	p.add_child(looks)
	p.add_child(UiKit.para("Change everything later in Menu > My character (you also get a Dream World Me).", 18, ThemeBuilder.MUTED))
	_pick_look("cozy")
	p.add_child(_nav([["Back", func(): _show(0)], ["Next", func(): _show(2)]]))
	return p


func _page_friend() -> Control:
	var p := UiKit.vbox(12)
	p.add_child(_title("Meet your first friend"))
	var row := UiKit.columns(18)   # (an upright phone: the friend above the choices, so nothing runs off the side)
	p.add_child(row)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(110, 110) if UiKit.upright_phone() else Vector2(150, 150)
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_preview)
	var col := UiKit.vbox(10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_friend_name = UiKit.line_edit("Their name", "Mochi")
	_friend_name.max_length = 40
	col.add_child(UiKit.field_row("Name", _friend_name, 110))
	var sw := UiKit.hbox(6)
	for hex in COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.add_theme_stylebox_override("normal", ThemeBuilder.box(Color(hex), Color(ThemeBuilder.CREAM, 0.4), 2, 10, 0))
		b.add_theme_stylebox_override("hover", ThemeBuilder.box(Color(hex), ThemeBuilder.YELLOW, 3, 10, 0))
		b.add_theme_stylebox_override("focus", ThemeBuilder.box(Color(hex), ThemeBuilder.YELLOW, 3, 10, 0))
		b.tooltip_text = "Color"
		b.pressed.connect(func():
			_color = hex
			_refresh_preview())
		sw.add_child(b)
	col.add_child(sw)
	var vibes := GridContainer.new()
	vibes.columns = 2
	vibes.add_theme_constant_override("h_separation", 8)
	vibes.add_theme_constant_override("v_separation", 8)
	for i in VIBES.size():
		var b := UiKit.button(VIBES[i][0], func(): _pick_vibe(i))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_vibe_btns.append(b)
		vibes.add_child(b)
	col.add_child(vibes)
	p.add_child(_nav([["Back", func(): _show(1)], ["I'll draw my own", func(): _finish(true)], ["Start!", func(): _finish(false)]]))
	_pick_vibe(0)
	return p


func _title(text: String) -> Label:
	var l := UiKit.para(text, 32, ThemeBuilder.CREAM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A row of [label, callable] buttons; the last one is the main action. On an upright phone they share
## the width and long labels wrap (the Survey's typewriter letters are wide).
func _nav(buttons: Array) -> HBoxContainer:
	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	var upright := UiKit.upright_phone()
	if not upright:
		row.add_child(UiKit.spacer())
	for b in buttons:
		var btn := UiKit.button(b[0], b[1], 0.0 if upright else 170.0)
		if upright:
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(btn)
	return row


func _show(i: int) -> void:
	step = i
	for j in _pages.size():
		_pages[j].visible = j == i
	var dots := PackedStringArray()
	for j in _pages.size():
		dots.append("●" if j == i else "○")
	_dots.text = "  ".join(dots)
	var focus: Control = [_world_name, _life, _friend_name][i]
	focus.call_deferred("grab_focus")


func _pick_look(id: String) -> void:
	_look = id
	for k in _look_btns:
		_look_btns[k].set_pressed_no_signal(k == id)


func _pick_vibe(i: int) -> void:
	_vibe = i
	for j in _vibe_btns.size():
		_vibe_btns[j].set_pressed_no_signal(j == i)
	_refresh_preview()


func _refresh_preview() -> void:
	_preview.texture = ImageTexture.create_from_image(SpriteFactory.blob("happy", Color(_color)))


## Right-click / Q goes back a step (and from the first step, to the title).
func go_back() -> void:
	if step == 0:
		cancelled.emit()
	else:
		_show(step - 1)


## Nothing is written here: Main creates the world from these choices, so
## backing out of onboarding never touches an existing world.
func _finish(draw_own: bool) -> void:
	finished.emit({
		"world_name": _world_name.text.strip_edges(),
		"player_name": _player_name.text.strip_edges(),
		"life": _life.text.strip_edges(),
		"dream": _dream.text.strip_edges(),
		"look": _look,
		"friend_name": _friend_name.text.strip_edges() if _friend_name.text.strip_edges() != "" else "Mochi",
		"color": _color,
		"personality": VIBES[_vibe][1],
		"speech_style": VIBES[_vibe][2],
		"draw_own": draw_own,
	})
