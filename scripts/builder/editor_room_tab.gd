extends VBoxContainer
## Editor > Place: what kind of place (editor_place_section.gd: kind, sky, add a place on any
## side; walls, ground and background layers), name, size, start spot, floor/wall/sky, backdrop
## picture, weather, music, your form in here, Place check, templates and stamps, other places.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const MusicPlayer := preload("res://scripts/world/music_player.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const PlaceSection := preload("res://scripts/builder/editor_place_section.gd")

var build: Node
var _name: LineEdit
var _w: SpinBox
var _d: SpinBox
var _weather: CheckBox
var _music: OptionButton
var _form: OptionButton
var _tracks: PackedStringArray = []
var _issues: VBoxContainer
var _advanced_tools: HBoxContainer
var _loading := false
var place_section: VBoxContainer


func bind(build_mode: Node) -> void:
	build = build_mode
	add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.scroll_deadzone = preload("res://scripts/ui/ui_kit.gd").touch_deadzone()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var v := UiKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	place_section = PlaceSection.new()
	v.add_child(place_section)
	place_section.bind(build)
	v.add_child(UiKit.label("Name and size", 18, ThemeBuilder.MUTED))
	_name = UiKit.line_edit("Place name")
	_name.max_length = 40
	_name.text_submitted.connect(func(_t): _rename())
	_name.focus_exited.connect(_rename)
	v.add_child(_name)
	var size_row := UiKit.hbox(4)
	_w = _spin()
	_d = _spin()
	size_row.add_child(_w)
	size_row.add_child(UiKit.label("×", 18))
	size_row.add_child(_d)
	size_row.add_child(UiKit.button("Set", func(): build.resize_room(int(_w.value), int(_d.value)), 56))
	v.add_child(size_row)
	var spawn_btn := UiKit.button("Start spot = cursor", func():
		build.edit_room(func(data): data["spawn"] = [build.cursor.x, build.cursor.y]), 0)
	spawn_btn.tooltip_text = "Where you appear in this place"
	v.add_child(spawn_btn)
	v.add_child(UiKit.label("Paint the whole...", 18, ThemeBuilder.MUTED))
	var whole := UiKit.hbox(4)
	for s in [["floor", "Floor"], ["wall", "Walls"], ["sky", "Sky"]]:
		var b := UiKit.button(s[1], func(): build.paint_surface(s[0]), 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		whole.add_child(b)
	v.add_child(whole)
	v.add_child(UiKit.para("(uses the current colour / picture from the Colours tab)", 14, ThemeBuilder.MUTED))
	v.add_child(UiKit.label("Backdrop", 18, ThemeBuilder.MUTED))
	var back := UiKit.hbox(4)
	back.add_child(UiKit.button("Picture...", _pick_backdrop, 0))
	back.add_child(UiKit.button("Plain", func(): build.edit_room(func(data): data["sky"]["texture"] = ""), 0))
	v.add_child(back)
	_weather = CheckBox.new()
	_weather.text = "Weather here"
	_weather.toggled.connect(func(on):
		if not _loading:
			build.set_room_weather(on))
	v.add_child(_weather)
	_tracks = MusicPlayer.track_names()
	_music = UiKit.option(["Music: the world's theme", "Music: quiet"])
	for t in _tracks:
		_music.add_item("Music: " + t)
	_music.custom_minimum_size.x = 0
	_music.tooltip_text = "Themes: Settings > Music"
	_music.item_selected.connect(func(i):
		if not _loading:
			build.edit_room(func(data): data["ambiance"]["music"] = _tracks[i - 2] if i > 1 else (MusicPlayer.QUIET if i == 1 else "")))
	v.add_child(_music)
	_form = UiKit.option(["You: either form"] + Array(PlayerLook.FORMS).map(func(f): return "You: " + PlayerLook.label(f)))
	_form.custom_minimum_size.x = 0
	_form.tooltip_text = "Entering this place switches you into this form"
	_form.item_selected.connect(func(i):
		if not _loading:
			build.edit_room(func(data): data["player_form"] = "" if i == 0 else PlayerLook.FORMS[i - 1]))
	v.add_child(_form)
	v.add_child(UiKit.label("Check & templates", 18, ThemeBuilder.MUTED))
	var _b1 := UiKit.button("Place check", _check, 0)
	_b1.tooltip_text = "Warns about unreachable doors, missing pictures, a blocked start spot"
	v.add_child(_b1)
	_issues = UiKit.vbox(2)
	v.add_child(_issues)
	var _b2 := UiKit.button("Templates...", _templates, 0)
	_b2.tooltip_text = "New place from a template, or apply one here"
	v.add_child(_b2)
	v.add_child(UiKit.button("Stamps...", _stamps, 0))
	v.add_child(UiKit.button("Places...", func(): build.world.main.open_panel(preload("res://scripts/world/world_menu.gd").room_list(build.world)), 0))
	_advanced_tools = UiKit.hbox(4)
	var map_button := UiKit.button("World Map...", _world_map, 0)
	map_button.tooltip_text = "Arrange places and drag a link handle to make two-way doors"
	_advanced_tools.add_child(map_button)
	v.add_child(_advanced_tools)
	refresh()


func _spin() -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 3
	s.max_value = 40
	s.custom_minimum_size = Vector2(70, 44)
	return s


func _rename() -> void:
	var n := _name.text.strip_edges()
	if n == "" or n == str(build.world.room.data.get("name", "")):
		return
	build.edit_room(func(data): data["name"] = n)
	build.world.hud.set_room(n)


func _pick_backdrop() -> void:
	UiKit.pick_picture(self, "Pick a backdrop picture (a wide panorama looks best)", func(path):
		var rel := SaveManager.import_texture(path)
		if rel == "":
			GameState.notify("Couldn't use that picture.")
			return
		build.edit_room(func(data): data["sky"]["texture"] = rel))


func _check() -> void:
	for c in _issues.get_children():
		c.free()
	var issues := RoomOps.room_check(build.world.room.data)
	if issues.is_empty():
		_issues.add_child(UiKit.para("All good: every door is reachable, every picture is here.", 16, ThemeBuilder.MINT))
		return
	for i in issues:
		var where: Vector2i = i.where
		var b := UiKit.button("%s (%d,%d)" % [i.problem, where.x, where.y], func():
			build.cursor = where
			build._place_ghost()
			build.world.cam.target = build._cursor_node
			build._cursor_node.position = build.world.room.cell_center(where), 0)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", ThemeBuilder.DANGER if i.severity == "warn" else ThemeBuilder.MUTED)
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_issues.add_child(b)


func _templates() -> void:
	var g := preload("res://scripts/ui/template_gallery.gd").new()
	g.build = build
	build.world.main.open_panel(g)


func _stamps() -> void:
	var p := preload("res://scripts/ui/stamp_panel.gd").new()
	p.build = build
	build.world.main.open_panel(p)


func _world_map() -> void:
	var p := preload("res://scripts/ui/world_map_panel.gd").new()
	p.build = build
	build.world.main.open_panel(p)


func refresh(advanced: bool = false) -> void:
	if build == null or _name == null:
		return
	_advanced_tools.visible = advanced
	_loading = true
	var data: Dictionary = build.world.room.data
	if not _name.has_focus():
		_name.text = str(data.get("name", ""))
	_w.value = build.world.room.w
	_d.value = build.world.room.d
	_weather.set_pressed_no_signal(str(data.get("ambiance", {}).get("weather", "auto")) != "none")
	var song := str(data.get("ambiance", {}).get("music", ""))
	_music.select(1 if song == MusicPlayer.QUIET else (_tracks.find(song) + 2 if _tracks.has(song) else 0))
	_form.select(PlayerLook.FORMS.find(PlayerLook.room_form(data)) + 1)
	_loading = false
