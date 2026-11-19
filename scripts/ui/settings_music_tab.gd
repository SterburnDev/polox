extends ScrollContainer
## Settings > Music: the five music cues (title menu, Light World creation, Light World, Dream World,
## battles) plus every song to preview. A cue left on Automatic plays an add-on's override or Polox's
## own tune. Previewing a song keeps playing while Settings is open and restores your previous music
## when stopped or closed.
##
## [EASTER_EGG] HTML-tab bottom secret:
## Scrolling all the way to the bottom of this tab reveals the `yams👀` button (with a tall scroll
## runway so it feels like scrolling past the footer of an old HTML page). Typing `aero`, `frutiger`,
## `code`, or `rot` before clicking `yams👀` arms the built-in secret image vault. After the full-screen
## flash, the Settings button turns into `👀` until the game restarts.
## Tags: [EASTER_EGG] [GLASS_UI]

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const MusicPlayer := preload("res://scripts/world/music_player.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")
const SecretPictures := preload("res://scripts/ui/secret_pictures.gd")
const Whimsy := preload("res://scripts/variety/whimsy.gd")
const Synth := preload("res://scripts/core/synth.gd")
const AnimFx := preload("res://scripts/ui/anim_fx.gd")

const CUE_TAGS := {
	"menu": "title menu",
	"light": "Light World",
	"dark": "Dream World",
	"battle": "battles",
	"survey": "Light World creation",
}
## First three picker entries before individual song titles: Automatic, Polox's own, Quiet.
const OWN_CUE_LABELS := {"survey": "Its own hum"}
const FIXED_CHOICE_COUNT := 3

const SECRET_LABEL := "yams👀"
const SECRET_SHOW_SECONDS := 5.0
## Extra runway above `yams👀` so the Music tab always scrolls like a tall HTML tab even with few songs.
const HTML_TAB_RUNWAY_PX := 180.0

var main: Node                 # main.gd: controls live music and refreshes themes
var _songs: Array = []         # Cached MusicPlayer.songs()
var _play_buttons: Array[Button] = []
var _title_labels: Array[Label] = []
var _notes: Array[Label] = []
var _playing_index := -1       # Currently previewed index in _songs (-1 = none)
var _music_player: Node        # Active MusicPlayer node (menu or world)
var _stereo: Control           # Skeuomorphic Stereo deck at the top
var _cued_index := 0           # Track cued for the stereo's Play key

var _secret_btn: Button
var _typed_buffer := ""
var _armed_keyword := ""


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_deadzone = UiKit.touch_deadzone()

	var content := UiKit.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)

	_songs = MusicPlayer.songs()
	var song_titles: Array = _songs.map(func(song): return str(song.title))
	if not _songs.is_empty():
		_stereo = Stereo.new()
		_stereo.name = "Stereo"
		_stereo.tab = self
		content.add_child(_stereo)

	_build_theme_pickers(content, song_titles)
	_build_song_list(content)
	_build_html_footer_secret(content)

	get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	_refresh()


func _build_theme_pickers(content: VBoxContainer, song_titles: Array) -> void:
	content.add_child(UiKit.label("Themes", 22, ThemeBuilder.YELLOW))
	for cue_kind in MusicPlayer.THEMES:
		var own_label := str(OWN_CUE_LABELS.get(cue_kind, "Polox's own tune"))
		var options := ["Automatic", own_label, "Quiet"] + song_titles
		var picker := UiKit.option(options, _theme_index(cue_kind, song_titles))
		picker.name = "Theme_" + cue_kind
		picker.item_selected.connect(func(selected_idx: int):
			var chosen_value: String = ["", MusicPlayer.OWN_TUNE, MusicPlayer.QUIET][selected_idx] \
				if selected_idx < FIXED_CHOICE_COUNT else str(song_titles[selected_idx - FIXED_CHOICE_COUNT])
			_set_theme(cue_kind, chosen_value))
		content.add_child(UiKit.field_row(str(MusicPlayer.THEME_NAMES[cue_kind]), picker, 200))
	content.add_child(UiKit.para("A place can have its own song: Build mode > Room.", 16, ThemeBuilder.MUTED))


func _build_song_list(content: VBoxContainer) -> void:
	content.add_child(UiKit.label("Songs", 22, ThemeBuilder.YELLOW))
	for index in _songs.size():
		content.add_child(_build_song_row(index))
	if not (OS.has_feature("android") or OS.has_feature("web")):
		content.add_child(UiKit.para("Your own songs (.ogg, .mp3, .wav) go in %s." % MusicPlayer.folders()[0], 16, ThemeBuilder.MUTED))


func _build_html_footer_secret(content: VBoxContainer) -> void:
	# Acts like an old HTML tab: you have to scroll all the way down past the quiet space to find `yams👀`.
	var runway := Control.new()
	runway.name = "HtmlScrollRunway"
	runway.custom_minimum_size = Vector2(0.0, HTML_TAB_RUNWAY_PX)
	runway.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(runway)

	_secret_btn = UiKit.button(SECRET_LABEL, _trigger_secret, 0)
	_secret_btn.name = "Yams"
	_secret_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(_secret_btn)
	_hide_secret(true)


## Returns the picker index for a music cue: Automatic (0), own tune (1), Quiet (2), or song title index.
static func _theme_index(cue_kind: String, song_titles: Array) -> int:
	var chosen_song := MusicPlayer.chosen(cue_kind)
	if chosen_song == "":
		return 0
	if chosen_song == MusicPlayer.OWN_TUNE:
		return 1
	if chosen_song == MusicPlayer.QUIET:
		return 2
	var found_idx := song_titles.find(chosen_song)
	return found_idx + FIXED_CHOICE_COUNT if found_idx >= 0 else 0


func _set_theme(cue_kind: String, song: String) -> void:
	MusicPlayer.set_theme(cue_kind, song)
	if main and main.has_method("refresh_music"):
		main.refresh_music()
	_refresh()


func _build_song_row(index: int) -> Control:
	var row := UiKit.hbox(12)
	var play_btn := UiKit.button("▶", func(): toggle(index), 0)
	play_btn.name = "Play%d" % index
	row.add_child(play_btn)

	var text_col := UiKit.vbox(2)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var title_lbl := UiKit.label(str(_songs[index].title), 20)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_child(title_lbl)

	var note_lbl := UiKit.label("", 16, ThemeBuilder.MUTED)
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_child(note_lbl)

	row.add_child(text_col)
	_play_buttons.append(play_btn)
	_title_labels.append(title_lbl)
	_notes.append(note_lbl)
	return row


## Plays song `index`, or stops it if it is already previewing (restoring previous music).
func toggle(index: int) -> void:
	if _playing_index == index:
		stop()
		return
	if _music_player == null or not is_instance_valid(_music_player):
		_music_player = main.music_now() if main and main.has_method("music_now") else null
	if _music_player == null:
		return
	_playing_index = index
	_music_player.preview(str(_songs[index].path))
	_refresh()


func stop() -> void:
	if _playing_index >= 0 and is_instance_valid(_music_player):
		_music_player.preview("")
	_playing_index = -1
	_music_player = null
	_refresh()


func playing() -> int:
	return _playing_index


## Stereo skip keys: moves forward/backward across songs (playing immediately if already playing).
func step_song(step_by: int) -> void:
	if _songs.is_empty():
		return
	var was_playing := _playing_index >= 0
	_cued_index = posmod((_playing_index if was_playing else _cued_index) + step_by, _songs.size())
	if was_playing:
		toggle(_cued_index)
	else:
		_refresh()


func play_or_stop() -> void:
	if _playing_index >= 0:
		stop()
	elif not _songs.is_empty():
		toggle(_cued_index)


func song_title(index: int) -> String:
	return str(_songs[index].title) if index >= 0 and index < _songs.size() else ""


func _refresh() -> void:
	if _playing_index >= 0:
		_cued_index = _playing_index
	if _stereo:
		_stereo.show_state(_playing_index >= 0, song_title(_cued_index), _cued_index, _songs.size())
	var active_themes := {}
	for cue_kind in MusicPlayer.THEMES:
		active_themes[cue_kind] = MusicPlayer.theme_path(cue_kind)
	for index in _play_buttons.size():
		var is_playing := index == _playing_index
		_play_buttons[index].text = "■" if is_playing else "▶"
		_play_buttons[index].tooltip_text = "Stop" if is_playing else "Play"
		_title_labels[index].add_theme_color_override("font_color", ThemeBuilder.YELLOW if is_playing else ThemeBuilder.CREAM)
		_notes[index].text = note(_songs[index], active_themes)


## Formats subtitle metadata: "Source • 2:00 • Light World".
static func note(song: Dictionary, themes: Dictionary) -> String:
	var parts: Array = []
	if str(song.get("from", "")) != "":
		parts.append(str(song.from))
	var seconds := int(song.get("seconds", 0))
	if seconds > 0:
		parts.append("%d:%02d" % [seconds / 60, seconds % 60])
	for cue_kind in MusicPlayer.THEMES:
		if str(themes.get(cue_kind, "")) != "" and str(themes[cue_kind]) == str(song.get("path", "")):
			parts.append(str(CUE_TAGS[cue_kind]))
	return " • ".join(parts)


func _exit_tree() -> void:
	if _playing_index >= 0 and is_instance_valid(_music_player):
		_music_player.preview("")


# --- HTML-tab scroll secret & keyword-armed Secret Vault (`aero`, `frutiger`, `code`, `rot`) -----------

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if key_event.unicode > 0:
		_on_secret_letter(key_event.unicode)


## Feeds a typed string into the secret vault listener (used by keyboard input and automated tests).
func feed_secret_text(text: String) -> String:
	for i in text.length():
		_on_secret_letter(text.unicode_at(i))
	return _armed_keyword


## Returns the currently armed secret vault keyword ("aero", "frutiger", "code", "rot"), or "".
func secret_keyword_armed() -> String:
	return _armed_keyword


func _on_secret_letter(unicode_char: int) -> void:
	var next_buffer := Whimsy.push_letter(_typed_buffer, unicode_char)
	if next_buffer == _typed_buffer:
		return
	_typed_buffer = next_buffer
	var matched := Whimsy.match_suffix(_typed_buffer, SecretPictures.SECRET_KEYWORDS)
	if matched == "":
		return
	_armed_keyword = matched
	if _secret_btn:
		_secret_btn.tooltip_text = "yams👀  [%s vault armed]" % matched
	if is_inside_tree():
		Synth.play(self, "sparkle", 0.3)


func _host_main() -> Node:
	if main:
		return main
	var current_scene: Node = get_tree().current_scene if is_inside_tree() else null
	return current_scene if current_scene and current_scene.has_method("show_title") else null


func at_bottom() -> bool:
	var bar := get_v_scroll_bar()
	return is_equal_approx(bar.value, maxf(bar.min_value, bar.max_value - bar.page))


## Keeps the button's slot reserved at the bottom (invisible and non-interactive) until revealed,
## so reaching the bottom shows it right where you're looking without shifting scroll height.
func _hide_secret(hidden: bool) -> void:
	_secret_btn.modulate.a = 0.0 if hidden else 1.0
	_secret_btn.disabled = hidden
	_secret_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if hidden else Control.MOUSE_FILTER_PASS
	_secret_btn.focus_mode = Control.FOCUS_NONE if hidden else Control.FOCUS_ALL


## True once the bottom `yams👀` button has been revealed.
func secret_shown() -> bool:
	return _secret_btn != null and not _secret_btn.disabled


func _on_scroll_changed(value: float) -> void:
	if secret_shown() or not is_visible_in_tree() or value <= get_v_scroll_bar().min_value or not at_bottom():
		return
	var host := _host_main()
	if host == null or not host.has_method("show_title") or host.panels.is_empty() or not host.panels.back().is_ancestor_of(self):
		return
	_hide_secret(false)


## Shows the full-screen secret image for 5 seconds, then returns cleanly to the title or world Menu
## with Settings replaced by `👀` for the rest of the session.
func _trigger_secret() -> void:
	var host := _host_main()
	if host == null or not secret_shown() or host.has_node("Secret"):
		return
	var active_keyword := _armed_keyword
	var tex: Texture2D = SecretPictures.pick_for_secret(active_keyword)
	if tex == null:
		return
	_armed_keyword = ""
	_typed_buffer = ""
	if _secret_btn:
		_secret_btn.tooltip_text = ""
	stop()

	var layer := CanvasLayer.new()
	layer.name = "Secret"
	layer.layer = 120

	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.mouse_force_pass_scroll_events = false
	backdrop.focus_mode = Control.FOCUS_ALL
	backdrop.gui_input.connect(func(_event: InputEvent): backdrop.accept_event())
	UiKit.fill(backdrop)
	layer.add_child(backdrop)

	var pic := TextureRect.new()
	pic.name = "Picture"
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill(pic)
	layer.add_child(pic)

	if active_keyword != "":
		var stamp := UiKit.label(Whimsy.secret_vault_caption(active_keyword), 16, Color(ThemeBuilder.AQUA, 0.9))
		stamp.name = "VaultCaption"
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stamp.add_theme_constant_override("outline_size", 4)
		stamp.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
		stamp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		stamp.offset_left = 18
		stamp.offset_bottom = -14
		stamp.offset_top = -42
		stamp.offset_right = 560
		layer.add_child(stamp)

	host.add_child(layer)
	backdrop.grab_focus()
	var already_watched := TitleScreen.eyes
	TitleScreen.eyes = true

	var layer_id := layer.get_instance_id()
	var host_id := host.get_instance_id()
	host.get_tree().create_timer(SECRET_SHOW_SECONDS, true, false, true).timeout.connect(func():
		var live_layer: Object = instance_from_id(layer_id)
		if live_layer is Node and is_instance_valid(live_layer):
			(live_layer as Node).queue_free()
		var live_host_obj: Object = instance_from_id(host_id)
		if not (live_host_obj is Node and is_instance_valid(live_host_obj)):
			return
		var live_host := live_host_obj as Node
		var world: Node = live_host.get("game")
		if world == null or not world.has_method("open_menu"):
			live_host.show_title()
			if already_watched:
				GameState.notify("* 👀 noticed you came back for more yams.")
			return
		for panel_node in live_host.panels.duplicate():
			if is_instance_valid(panel_node):
				panel_node.queue_free()
		live_host.panels.clear()
		world.open_menu()
		if not live_host.panels.is_empty():
			_focus_eyes_in_menu(live_host.panels.back()))


## Scrolls the world Menu's `👀` button into view and focuses it right after the secret flash.
static func _focus_eyes_in_menu(menu: Control) -> void:
	for _frame in 3:
		if not is_instance_valid(menu) or not menu.is_inside_tree():
			return
		await menu.get_tree().process_frame
	if not is_instance_valid(menu):
		return
	for btn in menu.find_children("*", "Button", true, false):
		if (btn as Button).text == TitleScreen.EYES:
			(btn as Button).grab_focus()
			var scroller: Node = btn.get_parent()
			while scroller and not scroller is ScrollContainer:
				scroller = scroller.get_parent()
			if scroller:
				(scroller as ScrollContainer).ensure_control_visible(btn)
			return


## [GLASS_UI] A compact skeuomorphic stereo deck: speaker grilles, backlit LCD with dancing level
## bars (still with Reduce motion), and tactile chrome transport keys.
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
		face.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
		face.shadow_size = 6
		face.shadow_offset = Vector2(0.0, 3.0)
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
			var step_by: int = spec[2]
			var btn := UK.button(str(spec[1]), func():
				if step_by == 0:
					tab.play_or_stop()
				else:
					tab.step_song(step_by), 64)
			btn.name = str(spec[0])
			btn.focus_mode = Control.FOCUS_ALL
			_style_chrome_key(btn)
			keys.add_child(btn)
			if step_by == 0:
				_play = btn

		row.add_child(Grille.new())

	func show_state(is_on: bool, title: String, at: int, count: int) -> void:
		playing = is_on
		if _title == null:
			return
		_title.text = "♪ " + title if title != "" else ""
		_state.text = ("▶  %d / %d" if is_on else "■  %d / %d") % [at + 1, count]
		_play.text = "■" if is_on else "▶"
		_play.tooltip_text = "Stop" if is_on else "Play"
		_bars.set("on", is_on)

	static func _style_chrome_key(btn: Button) -> void:
		var metal := Color("#d9d6e4")
		btn.add_theme_stylebox_override("normal", T.key(metal, Color("#ffffff"), 12, 8, 1.0, Color(0, 0, 0, 0), 1, 0.4))
		btn.add_theme_stylebox_override("hover", T.key(metal.lightened(0.1), Color.WHITE, 12, 8, 1.0, Color(T.AQUA, 0.3), 1, 0.45))
		btn.add_theme_stylebox_override("pressed", T.key(metal.darkened(0.15), Color.WHITE, 12, 8, 1.0, Color(0, 0, 0, 0), 1, 0.2, T.KEY_DEPTH, true))
		for color_slot in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(color_slot, Color("#2b2546"))
		btn.add_theme_font_size_override("font_size", 26)

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
			var row_idx := 0
			while y < size.y - 6.0:
				var x := 8.0 + (step / 2.0 if row_idx % 2 == 1 else 0.0)
				while x < size.x - 6.0:
					draw_circle(Vector2(x, y), 2.2, Color("#0c0a14"))
					draw_circle(Vector2(x, y + 0.8), 1.2, Color(1.0, 1.0, 1.0, 0.08))
					x += step
				y += step * 0.85
				row_idx += 1

	class Bars extends Control:
		var on := false:
			set(value):
				on = value
				set_process(on and not AnimFx.reduced())
				queue_redraw()
		var _t := 0.0

		func _ready() -> void:
			custom_minimum_size = Vector2(56, 40)
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			set_process(false)

		func _process(delta: float) -> void:
			if not on or AnimFx.reduced():
				set_process(false)
				return
			_t += delta
			queue_redraw()

		func _draw() -> void:
			for i in 7:
				var level := 0.18
				if on:
					level = 0.3 + 0.7 * absf(sin(_t * (3.0 + i * 0.7) + i * 1.3)) * (0.6 + 0.4 * sin(_t * 1.7 + i))
				var bar_h := size.y * clampf(level, 0.1, 1.0)
				draw_rect(Rect2(i * 8.0, size.y - bar_h, 5.0, bar_h), Color("#8ff5e0", 0.9 if on else 0.35))
