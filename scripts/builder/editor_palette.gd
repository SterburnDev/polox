extends VBoxContainer
## The bottom palette strip: one tab per tile set, plus Pieces (blocks,
## doors, signs, plants) and Colours (swatches, any colour, pictures). A
## search box filters tiles by name or tag. "Tile sets..." opens the manager.
## Tags: [BUILDER]

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const EditorHotbar := preload("res://scripts/builder/editor_hotbar.gd")

const PIECES := [["cube", "Cube"], ["slab", "Slab"], ["ramp", "Ramp"], ["pillar", "Column"], ["door", "Door"], ["sign", "Sign"], ["prop", "Plant"], ["pickup", "Pickup"],
	["platform_pillar", "Platform Pillar"], ["jump_pad", "Jump pad"], ["one_way", "One-way ledge"], ["mover", "Moving platform"],
	["checkpoint", "Checkpoint"], ["shard", "Memory Shard"], ["hazard", "Soft hazard"], ["dream_door", "Dream Door"], ["dark_fountain", "Dream Gate"], ["battle_spot", "Battle Spot"]]
## Platformer pieces stay behind Advanced (the Platform Pillar itself is always there).
const ADVANCED_PIECES: PackedStringArray = ["jump_pad", "one_way", "mover", "checkpoint", "shard", "hazard"]
const PIECE_TIPS := {
	"platform_pillar": "Activate it in play to start Platform Mode (run and jump). Set a label, colour and an optional destination.",
	"jump_pad": "Platform Mode: throws you up (set how high)", "one_way": "Platform Mode: a ledge you can jump up through",
	"mover": "Platform Mode: a platform that glides back and forth and carries you", "checkpoint": "Platform Mode: where you come back after a fall",
	"shard": "Platform Mode: a Memory Shard to collect", "hazard": "Platform Mode: touching it gently puts you back at the checkpoint",
	"dream_door": "Opens onto a freshly dreamed little room each time (keep the ones you love)",
	"dark_fountain": "A way into the Deep: tap it in play to make the Deep version of this place (or link one), then step in",
	"battle_spot": "Step on it in play to start a friendly battle (with the friend set in its options, or whoever is nearest)",
}
const COLORS := ["#8a7bc8", "#5b4b8a", "#2e2552", "#c9b6ff", "#e86a8a", "#ffb3c7", "#ffd166", "#ff9f43",
	"#7ad6b0", "#3f7a5a", "#8fd3ff", "#2e86de", "#8b5e3c", "#c08a5a", "#e8d3b0", "#f3e9d2"]
const ORIENT_NAMES := [["standing", "Standing"], ["floor", "Flat"], ["wall_n", "North wall"], ["wall_e", "East wall"], ["wall_s", "South wall"], ["wall_w", "West wall"]]

var build: Node
var tab := "tiles"               # "tiles" | "pieces" | "colors"
var _tabs_row: HBoxContainer
var _search: LineEdit
var _flow: HFlowContainer
var _layer_btns: Dictionary = {}
var _layer_ids := PackedStringArray()
var _layer_box: Control
var _hotbar: HFlowContainer
var _coach: Control
var _advanced_row: HBoxContainer
var _orient_opt: OptionButton
var _fade_cb: CheckBox
var _solid_cb: CheckBox
var _extras: HBoxContainer
var _last_brush_state := ""
var _filled_tab := ""
var _tile_tooltip_layer_type := ""
var _tile_buttons: Dictionary = {}
var _selected_tile_button: Button
var _adv := false                # the editor's Advanced toggle (platformer pieces)
var _fill_gen := 0               # a newer fill stops the rest of an older one
## Tile pictures for the palette, kept across editor visits ({path: [mtime, texture]}). The worlds
## ship ~500 tiles; the shared texture cache holds 96, so without this every Build entry decoded
## them all again. Tile pictures are small; the cap keeps it bounded.
static var _thumbs: Dictionary = {}
const THUMBS_MAX := 1024
const FIRST_BATCH := 48          # tile buttons made at once; the rest follow, a batch a frame
const BATCH := 64


func _course_panel() -> void:
	var panel := preload("res://scripts/ui/screen_panel.gd").new()
	build.world.main.open_panel(panel)
	panel.setup("Course physics")
	var ids := ["polox", "classic", "adventure", "player"]
	var profiles := preload("res://scripts/platform/platform_profiles.gd")
	var selected := UiKit.option(profiles.NAMES + ["Player's choice"], maxi(0, ids.find(str(build.world.room.data.get("physics_profile", "polox")))))
	selected.name = "CourseProfile"
	panel.body.add_child(UiKit.field_row("Physics", selected, 150))
	var planes := ["", "x", "z"]
	var axis := UiKit.option(["Free 3D", "X axis", "Z axis"], maxi(0, planes.find(profiles.plane(build.world.room.data))))
	axis.name = "CoursePlane"
	panel.body.add_child(UiKit.field_row("Classic plane", axis, 150))
	panel.body.add_child(UiKit.para("Classic moves left/right along one axis. Other profiles use the full room. Player's choice uses the setting in Settings > Controls.", 16))
	var status := UiKit.para("", 16, ThemeBuilder.YELLOW)
	panel.body.add_child(status)
	panel.body.add_child(UiKit.button("Keep", func():
		var id: String = ids[selected.selected]
		var plane: String = planes[axis.selected]
		if id == "classic" and plane == "":
			status.text = "Choose an X or Z plane for Classic."
			return
		build.edit_room(func(room: Dictionary):
			room["physics_profile"] = id
			room["platform_plane"] = plane)
		panel.close(), 120))


func bind(build_mode: Node) -> void:
	build = build_mode
	add_theme_constant_override("separation", 4)
	var top := UiKit.flow_row(6)   # wraps on a phone instead of widening the whole dock
	add_child(top)
	var layer_box := UiKit.hbox(2)
	_layer_box = layer_box
	_refresh_layer_buttons(layer_box)
	top.add_child(layer_box)
	# The tile-set tabs sit in the wrapping row as they are: inside a scroller, a flow row gave them almost
	# no width, so "Tiles | Pieces" was cut off under the search field behind a little scroll bar.
	_tabs_row = UiKit.hbox(2)
	_tabs_row.custom_minimum_size.y = 44
	top.add_child(_tabs_row)
	_search = UiKit.line_edit("Search tiles...")
	_search.custom_minimum_size = Vector2(170, 40)
	_search.size_flags_horizontal = Control.SIZE_FILL
	_search.text_changed.connect(func(_t): _fill())
	top.add_child(_search)
	var manage := UiKit.button("+ New tile set / manage...", _manager, 190)
	manage.tooltip_text = "Import an atlas or pictures, draw tiles, or manage reusable tile sets"
	top.add_child(manage)
	_advanced_row = UiKit.hbox(4)
	var smart := UiKit.button("Smart tiles...", _smart_wizard, 130)
	smart.tooltip_text = "Assign the 16 N/E/S/W neighbor patterns from a sliced atlas"
	_advanced_row.add_child(smart)
	var search := UiKit.button("Find / replace...", _search_panel, 150)
	search.tooltip_text = "Replace a tile or re-skin this room by matching tile names"
	_advanced_row.add_child(search)
	var reach := UiKit.button("Jump reach", func(): build.set_jump_reach(not build.jump_reach), 130)
	reach.toggle_mode = true
	reach.focus_mode = Control.FOCUS_NONE
	reach.tooltip_text = "Estimated running jump reach for this course's physics profile; momentum, obstacles and slopes change actual reach."
	_advanced_row.add_child(reach)
	top.add_child(_advanced_row)
	top.add_child(UiKit.button("Course physics...", _course_panel, 150))
	_coach = UiKit.hbox(6)
	_coach.add_child(UiKit.para("Pick a tile below, then click or drag in the room. Choose Foreground to paint a leafy tile that fades over friends.", 16, ThemeBuilder.MUTED))
	_coach.add_child(UiKit.button("Got it", _dismiss_coach, 76))
	add_child(_coach)
	_extras = UiKit.hbox(6)
	_orient_opt = UiKit.option(ORIENT_NAMES.map(func(o): return o[1]))
	_orient_opt.custom_minimum_size = Vector2(150, 40)
	_orient_opt.item_selected.connect(func(i): build.set_orient(ORIENT_NAMES[i][0]))
	_orient_opt.tooltip_text = "How the picture stands: flat on the floor (a textured cube on the Blocks layer), standing up, or on a wall"
	_extras.add_child(UiKit.field_row("As", _orient_opt, 40))
	_fade_cb = CheckBox.new()
	_fade_cb.text = "Fades when hiding someone"
	_fade_cb.toggled.connect(func(on): build.fade = on)
	_extras.add_child(_fade_cb)
	_solid_cb = CheckBox.new()
	_solid_cb.text = "Solid"
	_solid_cb.toggled.connect(func(on): build.solid = on)
	_extras.add_child(_solid_cb)
	add_child(_extras)
	var scroll := ScrollContainer.new()
	scroll.scroll_deadzone = preload("res://scripts/ui/ui_kit.gd").touch_deadzone()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Always at least one row of tiles: the rows above (coach mark, As/Fade/Solid,
	# hotbar) must never squeeze the tiles away; the dock grows instead.
	scroll.custom_minimum_size.y = 64
	add_child(scroll)
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 4)
	_flow.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_flow)
	_hotbar = HFlowContainer.new()
	_hotbar.add_theme_constant_override("h_separation", 3)
	_hotbar.add_theme_constant_override("v_separation", 3)
	add_child(_hotbar)
	_rebuild_tabs()
	_fill()
	_refresh_coach()
	_refresh_hotbar()


func _refresh_coach() -> void:
	_coach.visible = not bool(GameState.world.get("tile_coach_seen", false))


func _dismiss_coach() -> void:
	GameState.world["tile_coach_seen"] = true
	GameState.save_world()
	_refresh_coach()


func _manager() -> void:
	var m := preload("res://scripts/ui/tileset_manager.gd").new()
	m.changed.connect(func():
		# A picture can be replaced within the same filesystem timestamp tick.
		_thumbs.clear()
		_rebuild_tabs()
		_fill())
	build.world.main.open_panel(m)


func _rebuild_tabs() -> void:
	for c in _tabs_row.get_children():
		c.queue_free()
	var items: Array = [["tiles", "Tiles"], ["pieces", "Pieces"], ["colors", "Colours"]]
	if build.mode == "objects":
		tab = "pieces"
	elif not items.any(func(i): return i[0] == tab):
		tab = "tiles"
	for it in items:
		var b := UiKit.button(it[1], func():
			tab = it[0]
			_rebuild_tabs()
			_fill(), 0)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(0, 40)
		b.set_pressed_no_signal(it[0] == tab)
		_tabs_row.add_child(b)


func refresh(advanced: bool = false) -> void:
	_advanced_row.visible = advanced
	_hotbar.visible = advanced
	_refresh_layer_buttons(_layer_box)
	for k in _layer_btns:
		_layer_btns[k].set_pressed_no_signal(k == build.layer)
		_layer_btns[k].visible = build.mode == "tiles"
	_extras.visible = build.mode == "tiles" and build.piece == "tile" and build.layer_type() != "ground"
	_orient_opt.select(maxi(0, ORIENT_NAMES.map(func(o): return o[0]).find(build.orient)))
	_fade_cb.visible = build.layer == "foreground"
	_fade_cb.set_pressed_no_signal(build.fade)
	_solid_cb.set_pressed_no_signal(build.solid)
	var advanced_changed := advanced != _adv
	_adv = advanced
	var brush_state := _brush_state()
	var brush_changed := brush_state != _last_brush_state
	if brush_changed or advanced_changed:
		EditorHotbar.record(EditorHotbar.capture(build))
		if build.mode == "objects" and tab != "pieces":
			_rebuild_tabs()
		_refresh_hotbar()
	if tab == "tiles" and _filled_tab == "tiles" and _tile_tooltip_layer_type == build.layer_type():
		_update_selected_tile()
		_last_brush_state = brush_state
	elif brush_changed or advanced_changed or tab == "tiles":
		_fill()


func _brush_state() -> String:
	return "%s|%s|%s|%s|%s|%s|%s" % [tab, build.mode, build.piece, build.brush_set, build.brush_tile, build.color, build.random_pool.size()]


func _update_selected_tile() -> void:
	var selected: Button = _tile_buttons.get(str(build.brush_set).path_join(str(build.brush_tile)))
	if selected != _selected_tile_button:
		if _selected_tile_button:
			_selected_tile_button.set_pressed_no_signal(false)
		_selected_tile_button = selected
	if selected:
		selected.set_pressed_no_signal(true)


func _smart_wizard() -> void:
	var panel := preload("res://scripts/ui/smart_tile_wizard.gd").new()
	panel.build = build
	build.world.main.open_panel(panel)


func _search_panel() -> void:
	var panel := preload("res://scripts/ui/room_search_panel.gd").new()
	panel.build = build
	build.world.main.open_panel(panel)


func _refresh_hotbar() -> void:
	if _hotbar == null:
		return
	for child in _hotbar.get_children():
		child.queue_free()
	var favs := EditorHotbar.slots()
	_hotbar.add_child(UiKit.label("Hotbar", 16, ThemeBuilder.MUTED))
	for i in favs.size():
		var entry: Dictionary = favs[i] if favs[i] is Dictionary else {}
		var label := "%d -" % (i + 1) if entry.is_empty() else "%d %s" % [i + 1, EditorHotbar.label(entry).substr(0, 8)]
		var slot := UiKit.button(label, func():
			if entry.is_empty():
				EditorHotbar.pin(i, EditorHotbar.capture(build))
				_refresh_hotbar()
				GameState.notify("Pinned in hotbar slot %d" % (i + 1))
			else:
				EditorHotbar.activate(build, entry), 0)
		slot.custom_minimum_size = Vector2(56, 44)
		slot.tooltip_text = "Empty: pin current brush • Filled: use %s • key %d" % [EditorHotbar.label(entry, "current brush"), i + 1]
		_hotbar.add_child(slot)
		if not entry.is_empty():
			var clear := UiKit.button("×", func():
				EditorHotbar.clear(i)
				_refresh_hotbar(), 38)
			clear.tooltip_text = "Clear favourite %d" % (i + 1)
			_hotbar.add_child(clear)
	var recents := EditorHotbar.recent()
	if not recents.is_empty():
		_hotbar.add_child(UiKit.label("Recent", 16, ThemeBuilder.MUTED))
		for entry in recents.slice(0, 3):
			var recent_btn := UiKit.button(EditorHotbar.label(entry), func(): EditorHotbar.activate(build, entry), 88)
			recent_btn.tooltip_text = "Use recent brush"
			_hotbar.add_child(recent_btn)


func _fill() -> void:
	_last_brush_state = _brush_state()
	_filled_tab = tab
	_fill_gen += 1
	_tile_buttons.clear()
	_selected_tile_button = null
	# A control can trigger a fill while its own signal is still being emitted.
	for child in _flow.get_children():
		_flow.remove_child(child)
		child.queue_free()
	match tab:
		"tiles":
			_fill_tile_sets()
		"pieces":
			_fill_pieces()
		"colors":
			_fill_colors()
		_:
			_fill_tiles(tab)


func _refresh_layer_buttons(layer_box: Control) -> void:
	if layer_box == null:
		return
	var layers := TileLayers.all(build.world.room.data)
	var layer_ids := PackedStringArray(layers.map(func(layer): return str(layer.id)))
	# The same layer can be renamed or change type while its button stays in place.
	if layer_ids != _layer_ids:
		_layer_ids = layer_ids
		for child in layer_box.get_children():
			child.queue_free()
		_layer_btns.clear()
	for spec: Dictionary in layers:
		var layer_id := str(spec.id)
		var button: Button = _layer_btns.get(layer_id)
		if button == null:
			button = UiKit.button("", func(): build.set_layer(layer_id), 0)
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_font_size_override("font_size", 16)
			button.custom_minimum_size = Vector2(0, 40)
			_layer_btns[layer_id] = button
			layer_box.add_child(button)
		var layer_name := str(spec.get("name", layer_id))
		if button.text != layer_name:
			button.text = layer_name
		button.tooltip_text = "%s layer: click or drag to paint here" % str(TileLayers.TYPE_NAMES.get(str(spec.type), "Tile"))


## Search, tile set edits and layer tooltip changes refill this view. Brush changes
## only update selection, so even an in-progress batch can finish making its buttons.
func _fill_tile_sets() -> void:
	_tile_tooltip_layer_type = build.layer_type()
	var sets: Array = Array(Tilesets.ids()).map(func(id): return Tilesets.cached_set(id)).filter(func(s): return not s.is_empty())   # read only
	var q := _search.text.strip_edges().to_lower()
	var items: Array = []        # [set, tile] for a button, or [set] for a set's heading
	for s in sets:
		var tiles: Array = s.get("tiles", [])
		var matching := tiles.filter(func(t): return q == "" or (str(t.get("name", "")) + " " + " ".join(t.get("tags", []))).to_lower().contains(q))
		if matching.is_empty():
			continue
		items.append([s])
		for t in matching:
			items.append([s, t])
	if items.is_empty():
		_flow.add_child(UiKit.para("No tiles match yet. Use “+ New tile set / manage...” to import an atlas, add pictures or draw a tile.", 18, ThemeBuilder.MUTED))
		return
	var gen := _fill_gen
	for i in mini(FIRST_BATCH, items.size()):
		_add_tile_item(items[i])
	var at := FIRST_BATCH
	var tree := Engine.get_main_loop() as SceneTree   # (the first fill runs before the palette is in the tree)
	while at < items.size():
		await tree.process_frame
		if gen != _fill_gen or not is_instance_valid(self) or is_queued_for_deletion() or _flow == null:
			return   # refilled or closed meanwhile
		for i in range(at, mini(at + BATCH, items.size())):
			_add_tile_item(items[i])
		at += BATCH


func _add_tile_item(item: Array) -> void:
	var s: Dictionary = item[0]
	if item.size() == 1:
		_flow.add_child(UiKit.label(str(s.get("name", s.id)), 18, ThemeBuilder.MUTED))
		return
	var t: Dictionary = item[1]
	var id := str(t.id)
	var set_id := str(s.id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(56, 56)
	b.icon = thumb(Tilesets.tile_path(set_id, id))
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.tooltip_text = "%s — %s%s" % [str(t.name), str(TileLayers.TYPE_NAMES.get(_tile_tooltip_layer_type, "Tile")), " • solid" if bool(t.get("solid", false)) else ""]
	_tile_buttons[set_id.path_join(id)] = b
	if build.brush_set == set_id and build.brush_tile == id:
		b.set_pressed_no_signal(true)
		_selected_tile_button = b
	b.pressed.connect(func(): build.set_brush_tile(set_id, id))
	_flow.add_child(b)


## A tile picture for a palette button, from _thumbs when the file hasn't changed.
static func thumb(rel: String) -> Texture2D:
	if rel == "":
		return null
	var full := SaveManager.abs_path(rel)
	var mtime := FileAccess.get_modified_time(full)
	var hit: Variant = _thumbs.get(full)
	if hit is Array and hit[0] == mtime:
		return hit[1]
	var tex := SaveManager.load_texture(rel)
	if tex == null:
		return null
	if _thumbs.size() >= THUMBS_MAX:
		_thumbs.erase(_thumbs.keys()[0])
	_thumbs[full] = [mtime, tex]
	return tex


func _fill_pieces() -> void:
	for p in PIECES:
		if build.mode == "objects" and not p[0] in BlockFactory.OBJECT_TYPES:
			continue
		if build.mode == "tiles" and p[0] in BlockFactory.OBJECT_TYPES:
			continue
		if p[0] in ADVANCED_PIECES and not _adv:
			continue
		var b := UiKit.button(p[1], func(): build.set_piece(p[0]), 96)
		b.tooltip_text = str(PIECE_TIPS.get(p[0], ""))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_pressed_no_signal(build.piece == p[0])
		_flow.add_child(b)


func _fill_colors() -> void:
	for hex in COLORS:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(48, 48)
		sw.focus_mode = Control.FOCUS_NONE
		sw.tooltip_text = hex
		sw.add_theme_stylebox_override("normal", ThemeBuilder.box(Color(hex), Color(ThemeBuilder.CREAM, 0.3), 1, 4, 0))
		sw.add_theme_stylebox_override("hover", ThemeBuilder.box(Color(hex), ThemeBuilder.YELLOW, 2, 4, 0))
		sw.pressed.connect(func(): build.set_paint(hex, build.texture))
		_flow.add_child(sw)
	var cur := UiKit.color_swatch(Color(build.color), 48)
	_flow.add_child(cur)
	var picker := ColorPickerButton.new()
	picker.text = "Any colour"
	picker.custom_minimum_size = Vector2(130, 48)
	picker.color = Color(build.color)
	picker.edit_alpha = false
	picker.color_changed.connect(func(c): build.set_paint("#" + c.to_html(false), build.texture))
	_flow.add_child(picker)
	_flow.add_child(UiKit.button("Picture...", _pick_texture, 120))
	_flow.add_child(UiKit.button("No picture", func(): build.set_paint(build.color, ""), 120))
	var files := JsonUtil.list_files(SaveManager.abs_path("textures"), ["png", "jpg", "jpeg", "webp"])
	for f in files.slice(maxi(0, files.size() - 8)):
		var rel := "textures/" + f
		var b := Button.new()
		b.custom_minimum_size = Vector2(48, 48)
		b.icon = SaveManager.load_texture(rel)
		b.expand_icon = true
		b.tooltip_text = f
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): build.set_paint(build.color, rel))
		_flow.add_child(b)


func _fill_tiles(set_id: String) -> void:
	var s := Tilesets.load_set(set_id)
	var q := _search.text.strip_edges().to_lower()
	for t in s.tiles:
		var hay := (str(t.name) + " " + " ".join(t.get("tags", []))).to_lower()
		if q != "" and hay.find(q) == -1:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 56)
		b.icon = thumb(Tilesets.tile_path(set_id, str(t.id)))
		b.expand_icon = true
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.tooltip_text = str(t.name) + ("  (solid)" if bool(t.get("solid", false)) else "") + ("  (animated)" if not t.get("frames", []).is_empty() else "")
		var in_pool: bool = build.random_pool.any(func(p): return p[0] == set_id and p[1] == str(t.id))
		b.set_pressed_no_signal((build.brush_set == set_id and build.brush_tile == str(t.id)) or in_pool)
		if in_pool:
			b.add_theme_stylebox_override("pressed", ThemeBuilder.box(ThemeBuilder.MINT, ThemeBuilder.CREAM, 2, 8, 2))
		b.pressed.connect(func():
			if build.random_on:
				build.toggle_random_tile(set_id, str(t.id))
			build.set_brush_tile(set_id, str(t.id)))
		_flow.add_child(b)
	if s.tiles.is_empty():
		_flow.add_child(UiKit.label("This set has no tiles yet. Tile sets... adds some.", 18, ThemeBuilder.MUTED))


func _pick_texture() -> void:
	UiKit.pick_picture(self, "Pick a picture to paint with", func(path):
		var rel := SaveManager.import_texture(path)
		if rel == "":
			GameState.notify("Couldn't use that picture.")
		else:
			build.set_paint(build.color, rel)
		_fill())
