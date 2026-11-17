extends ScrollContainer
## Settings > Music: the five cues (the title menu, the Light World's creation, the Light World, the Dream
## World, battles) and every song to listen to. A cue left on Automatic plays an add-on's song for it, or
## Polox's own tune. A song you play keeps going while Settings is open; the music you had comes
## back when you stop it or close Settings.
## Tags: [EASTER_EGG]

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const MusicPlayer := preload("res://scripts/world/music_player.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")

const TAGS := {"menu": "title menu", "light": "Light World", "dark": "Dream World", "battle": "battles", "survey": "Light World creation"}
## A cue's first choices before the songs: Automatic (an add-on's song, or Polox's own), Polox's own sound, quiet.
const OWN := {"survey": "Its own hum"}
const FIRST := 3   # Automatic, own, Quiet

var main: Node                 # main.gd: the music that's on, and themes taking effect
var _songs: Array = []         # MusicPlayer.songs()
var _buttons: Array[Button] = []
var _titles: Array[Label] = []
var _notes: Array[Label] = []
var _playing := -1             # the song playing from here (in _songs), -1 = none
var _player: Node              # the player it plays on (the menu's or the world's)
var _stereo: Control           # the stereo at the top (Stereo, below)
var _cued := 0                 # the song the stereo's play key plays

## [EASTER_EGG] Scrolling to the bottom of Music reveals the button.
## The picture fills the screen for five seconds. The menu you came from then shows 👀 for Settings
## until the game restarts.
const SECRET_LABEL := "yams👀"
const SECRET_SHOW := 5.0
var _secret_btn: Button


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_deadzone = UiKit.touch_deadzone()
	var v := UiKit.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(v)
	_songs = MusicPlayer.songs()
	var titles: Array = _songs.map(func(s): return str(s.title))
	if not _songs.is_empty():
		_stereo = Stereo.new()
		_stereo.name = "Stereo"
		_stereo.tab = self
		v.add_child(_stereo)
	v.add_child(UiKit.label("Themes", 22, ThemeBuilder.YELLOW))
	for kind in MusicPlayer.THEMES:
		var opt := UiKit.option(["Automatic", str(OWN.get(kind, "Polox's own tune")), "Quiet"] + titles, _theme_index(kind, titles))
		opt.name = "Theme_" + kind
		opt.item_selected.connect(func(i: int): _set_theme(kind, ["", MusicPlayer.OWN_TUNE, MusicPlayer.QUIET][i] if i < FIRST else str(titles[i - FIRST])))
		v.add_child(UiKit.field_row(str(MusicPlayer.THEME_NAMES[kind]), opt, 200))
	v.add_child(UiKit.para("A place can have its own song: Build mode > Room.", 16, ThemeBuilder.MUTED))
	v.add_child(UiKit.label("Songs", 22, ThemeBuilder.YELLOW))
	for i in _songs.size():
		v.add_child(_song_row(i))
	if not (OS.has_feature("android") or OS.has_feature("web")):   # (a phone's or a browser's save folder is out of reach, and Sync carries no songs)
		v.add_child(UiKit.para("Your own songs (.ogg, .mp3, .wav) go in %s." % MusicPlayer.folders()[0], 16, ThemeBuilder.MUTED))
	_secret_btn = UiKit.button(SECRET_LABEL, _secret, 0)
	_secret_btn.name = "Yams"
	_secret_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(_secret_btn)
	_hide_secret(true)
	get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	_refresh()


## The picker's line for a cue: Automatic (nothing chosen, or a chosen song that's gone), own, quiet, a song.
static func _theme_index(kind: String, titles: Array) -> int:
	var now := MusicPlayer.chosen(kind)
	if now == "":
		return 0
	if now == MusicPlayer.OWN_TUNE:
		return 1
	if now == MusicPlayer.QUIET:
		return 2
	var at := titles.find(now)
	return at + FIRST if at >= 0 else 0


func _set_theme(kind: String, song: String) -> void:
	MusicPlayer.set_theme(kind, song)
	if main and main.has_method("refresh_music"):
		main.refresh_music()
	_refresh()


func _song_row(i: int) -> Control:
	var row := UiKit.hbox(12)
	var b := UiKit.button("▶", func(): toggle(i), 0)
	b.name = "Play%d" % i
	row.add_child(b)
	var col := UiKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := UiKit.label(str(_songs[i].title), 20)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(t)
	var n := UiKit.label("", 16, ThemeBuilder.MUTED)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(n)
	row.add_child(col)
	_buttons.append(b)
	_titles.append(t)
	_notes.append(n)
	return row


## Plays song `i`, or stops it if it's the one playing (the music you had comes back).
func toggle(i: int) -> void:
	if _playing == i:
		stop()
		return
	if _player == null or not is_instance_valid(_player):
		_player = main.music_now() if main and main.has_method("music_now") else null
	if _player == null:
		return
	_playing = i
	_player.preview(str(_songs[i].path))
	_refresh()


func stop() -> void:
	if _playing >= 0 and is_instance_valid(_player):
		_player.preview("")
	_playing = -1
	_player = null
	_refresh()


func playing() -> int:
	return _playing


## The stereo's keys: back and next move along the songs (playing the new one if one was playing).
func step_song(by: int) -> void:
	if _songs.is_empty():
		return
	var was_playing := _playing >= 0
	_cued = posmod((_playing if was_playing else _cued) + by, _songs.size())
	if was_playing:
		toggle(_cued)
	else:
		_refresh()


func play_or_stop() -> void:
	if _playing >= 0:
		stop()
	elif not _songs.is_empty():
		toggle(_cued)


func song_title(i: int) -> String:
	return str(_songs[i].title) if i >= 0 and i < _songs.size() else ""


func _refresh() -> void:
	if _playing >= 0:
		_cued = _playing
	if _stereo:
		_stereo.show_state(_playing >= 0, song_title(_cued), _cued, _songs.size())
	var themes := {}
	for kind in MusicPlayer.THEMES:
		themes[kind] = MusicPlayer.theme_path(kind)
	for i in _buttons.size():
		var on := i == _playing
		_buttons[i].text = "■" if on else "▶"
		_buttons[i].tooltip_text = "Stop" if on else "Play"
		_titles[i].add_theme_color_override("font_color", ThemeBuilder.YELLOW if on else ThemeBuilder.CREAM)
		_notes[i].text = note(_songs[i], themes)


## "An album • 2:00 • Light World" (`themes`: each theme's song, MusicPlayer.theme_path).
static func note(song: Dictionary, themes: Dictionary) -> String:
	var bits: Array = []
	if str(song.get("from", "")) != "":
		bits.append(str(song.from))
	var s := int(song.get("seconds", 0))
	if s > 0:
		bits.append("%d:%02d" % [s / 60, s % 60])
	for kind in MusicPlayer.THEMES:
		if str(themes.get(kind, "")) != "" and str(themes[kind]) == str(song.get("path", "")):
			bits.append(str(TAGS[kind]))
	return " • ".join(bits)


func _exit_tree() -> void:
	if _playing >= 0 and is_instance_valid(_player):
		_player.preview("")   # Settings closed: back to what was playing


func _main() -> Node:
	if main:
		return main
	var cs: Node = get_tree().current_scene if is_inside_tree() else null
	return cs if cs and cs.has_method("show_title") else null


func at_bottom() -> bool:
	var bar := get_v_scroll_bar()
	return is_equal_approx(bar.value, maxf(bar.min_value, bar.max_value - bar.page))


## The button keeps its place at the bottom from the start, just unseen and untouchable, so when it
## appears it's right where you're looking: no page growing under you, nothing to scroll to.
func _hide_secret(hidden: bool) -> void:
	_secret_btn.modulate.a = 0.0 if hidden else 1.0
	_secret_btn.disabled = hidden
	_secret_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if hidden else Control.MOUSE_FILTER_PASS
	_secret_btn.focus_mode = Control.FOCUS_NONE if hidden else Control.FOCUS_ALL


## True once the button has appeared (tests, drives).
func secret_shown() -> bool:
	return _secret_btn != null and not _secret_btn.disabled


func _on_scroll_changed(value: float) -> void:
	if secret_shown() or not is_visible_in_tree() or value <= get_v_scroll_bar().min_value or not at_bottom():
		return
	var host := _main()
	if host == null or not host.has_method("show_title") or host.panels.is_empty() or not host.panels.back().is_ancestor_of(self):
		return
	_hide_secret(false)


## The picture alone, full screen, keeping its shape; then straight back to the title, or in a world to
## its Menu (Settings and anything under it closed; the world keeps going, nothing lost).
func _secret() -> void:
	var m := _main()
	if m == null or not secret_shown() or m.has_node("Secret"):
		return
	var tex: Texture2D = preload("res://scripts/ui/secret_pictures.gd").pick()
	if tex == null:
		return
	stop()
	var layer := CanvasLayer.new()
	layer.name = "Secret"
	layer.layer = 120
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	black.mouse_force_pass_scroll_events = false
	black.focus_mode = Control.FOCUS_ALL
	black.gui_input.connect(func(_event: InputEvent): black.accept_event())
	UiKit.fill(black)
	layer.add_child(black)
	var pic := TextureRect.new()
	pic.name = "Picture"
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill(pic)
	layer.add_child(pic)
	m.add_child(layer)
	black.grab_focus()
	TitleScreen.eyes = true
	m.get_tree().create_timer(SECRET_SHOW, true, false, true).timeout.connect(func():
		if is_instance_valid(layer):
			layer.queue_free()
		if not is_instance_valid(m):
			return
		var world: Node = m.get("game")
		if world == null or not world.has_method("open_menu"):
			m.show_title()
			return
		for p in m.panels.duplicate():
			if is_instance_valid(p):
				p.queue_free()
		m.panels.clear()
		world.open_menu()
		if not m.panels.is_empty():
			_show_eyes(m.panels.back()))


## The world's Menu right after the picture: its 👀 (where Settings was) scrolled into sight and picked,
## so you see the mark at once, as on the title.
static func _show_eyes(menu: Control) -> void:
	for i in 3:   # (after the Menu has arrived and been laid out)
		if not is_instance_valid(menu) or not menu.is_inside_tree():
			return
		await menu.get_tree().process_frame
	if not is_instance_valid(menu):
		return
	for b in menu.find_children("*", "Button", true, false):
		if (b as Button).text == TitleScreen.EYES:
			(b as Button).grab_focus()
			var sc: Node = b.get_parent()
			while sc and not sc is ScrollContainer:
				sc = sc.get_parent()
			if sc:
				(sc as ScrollContainer).ensure_control_visible(b)
			return


## [GLASS_UI] A small stereo (early iOS skeuomorphism): a faceplate with speaker grilles at each end, a
## backlit display showing the song (and little level bars while it plays; still with Reduce motion),
## and chrome keys you press in: back, play / stop, next.
class Stereo extends PanelContainer:
	const T := preload("res://scripts/ui/theme_builder.gd")
	const UK := preload("res://scripts/ui/ui_kit.gd")
	const LCD := Color("#0f2d33")
	const LCD_TEXT := Color("#8ff5e0")
	var tab: Node
	var _title: Label
	var _state: Label
	var _bars: Control
	var _play: Button
	var playing := false

	func _ready() -> void:
		var face := StyleBoxFlat.new()
		face.bg_color = Color("#3b3550")
		face.border_color = Color("#8c84a8")
		face.set_border_width_all(1)
		face.set_corner_radius_all(16)
		face.content_margin_left = 12
		face.content_margin_right = 12
		face.content_margin_top = 10
		face.content_margin_bottom = 10
		face.shadow_color = Color(0, 0, 0, 0.35)
		face.shadow_size = 6
		face.shadow_offset = Vector2(0, 3)
		add_theme_stylebox_override("panel", face)
		var row := UK.hbox(12)
		add_child(row)
		row.add_child(Grille.new())
		var mid := UK.vbox(8)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(mid)
		var screen := PanelContainer.new()
		screen.name = "Display"
		screen.add_theme_stylebox_override("panel", T.well(LCD, Color("#05161a"), 8, 2, 0.55, 8))
		mid.add_child(screen)
		var lcd := UK.hbox(10)
		screen.add_child(lcd)
		var words := UK.vbox(0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lcd.add_child(words)
		_state = UK.label("", 14, Color(LCD_TEXT, 0.7))
		words.add_child(_state)
		_title = UK.label("", 20, LCD_TEXT)
		_title.name = "NowPlaying"
		_title.clip_text = true
		_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		words.add_child(_title)
		_bars = Bars.new()
		lcd.add_child(_bars)
		var keys := UK.hbox(10)
		keys.alignment = BoxContainer.ALIGNMENT_CENTER
		mid.add_child(keys)
		for spec in [["StereoBack", "◀◀", -1], ["StereoPlay", "▶", 0], ["StereoNext", "▶▶", 1]]:
			var by: int = spec[2]
			var b := UK.button(str(spec[1]), func():
				if by == 0:
					tab.play_or_stop()
				else:
					tab.step_song(by), 64)
			b.name = str(spec[0])
			b.focus_mode = Control.FOCUS_ALL
			_chrome(b)
			keys.add_child(b)
			if by == 0:
				_play = b
		row.add_child(Grille.new())

	func show_state(on: bool, title: String, at: int, count: int) -> void:
		playing = on
		if _title == null:
			return
		_title.text = "♪ " + title if title != "" else ""
		_state.text = ("▶  %d / %d" if on else "■  %d / %d") % [at + 1, count]
		_play.text = "■" if on else "▶"
		_play.tooltip_text = "Stop" if on else "Play"
		_bars.set("on", on)

	## Chrome keys: a bright metal face that sits down when pressed.
	static func _chrome(b: Button) -> void:
		var metal := Color("#d9d6e4")
		b.add_theme_stylebox_override("normal", T.key(metal, Color("#ffffff"), 12, 8, 1.0, Color(0, 0, 0, 0), 1, 0.4))
		b.add_theme_stylebox_override("hover", T.key(metal.lightened(0.1), Color.WHITE, 12, 8, 1.0, Color(T.AQUA, 0.3), 1, 0.45))
		b.add_theme_stylebox_override("pressed", T.key(metal.darkened(0.15), Color.WHITE, 12, 8, 1.0, Color(0, 0, 0, 0), 1, 0.2, T.KEY_DEPTH, true))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, Color("#2b2546"))
		b.add_theme_font_size_override("font_size", 26)

	## A speaker grille: rows of little holes.
	class Grille extends Control:
		func _ready() -> void:
			custom_minimum_size = Vector2(64, 96)
			mouse_filter = Control.MOUSE_FILTER_IGNORE
		func _draw() -> void:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("#241f36")
			sb.set_corner_radius_all(10)
			draw_style_box(sb, Rect2(Vector2.ZERO, size))
			var step := 9.0
			var y := 8.0
			var k := 0
			while y < size.y - 6.0:
				var x := 8.0 + (step / 2.0 if k % 2 == 1 else 0.0)
				while x < size.x - 6.0:
					draw_circle(Vector2(x, y), 2.2, Color("#0c0a14"))
					draw_circle(Vector2(x, y + 0.8), 1.2, Color(1, 1, 1, 0.08))
					x += step
				y += step * 0.85
				k += 1

	## Level bars on the display, dancing while a song plays (still with Reduce motion).
	class Bars extends Control:
		var on := false:
			set(v):
				on = v
				queue_redraw()
		var _t := 0.0
		func _ready() -> void:
			custom_minimum_size = Vector2(56, 40)
			mouse_filter = Control.MOUSE_FILTER_IGNORE
		func _process(delta: float) -> void:
			if on and not preload("res://scripts/ui/anim_fx.gd").reduced():
				_t += delta
				queue_redraw()
		func _draw() -> void:
			for i in 7:
				var h := 0.18
				if on:
					h = 0.3 + 0.7 * absf(sin(_t * (3.0 + i * 0.7) + i * 1.3)) * (0.6 + 0.4 * sin(_t * 1.7 + i))
				var bh := size.y * clampf(h, 0.1, 1.0)
				draw_rect(Rect2(i * 8.0, size.y - bh, 5.0, bh), Color("#8ff5e0", 0.9 if on else 0.35))
