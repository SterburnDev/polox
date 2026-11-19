extends Control
## The editor screen, organised around what you're doing:
##   Place  put down blocks, tiles and objects (place, brush, line, rect, outline, fill, stamp, erase)
##   Paint  recolour blocks, the floor, walls and sky (paint, pick a colour)
##   Edit   select, move, duplicate, and change a thing's settings (edit, select, erase)
##   ▶ Playtest  walk (or run and jump) from the cursor; "Back to building" brings you straight back
## What you place (Tiles, Objects, or the Room's own settings) is a second, smaller choice.
## PC: a glass top bar (Done, the modes, Playtest, Undo/Redo, Save and whether everything is saved),
## the mode's tools on the left, the inspector and layers on the right (Advanced), the palette at the
## bottom with search, favourites and recents, and a status bar (the hint, camera, panels). Panels
## can be collapsed or resized; the layout is remembered (prefs). Simple mode hides the advanced parts.
## Phone: the world fills the screen; a slim top bar (Done, Undo/Redo, Playtest) and a bottom
## toolbar under the thumb (the modes, then Tools, Pieces and Properties, each opening a sheet).
## Tags: [BUILDER]

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const TouchGestures := preload("res://scripts/ui/touch_gestures.gd")
const Toolbox := preload("res://scripts/builder/editor_toolbox.gd")
const Palette := preload("res://scripts/builder/editor_palette.gd")
const Inspector := preload("res://scripts/builder/editor_inspector.gd")
const RoomTab := preload("res://scripts/builder/editor_room_tab.gd")
const Minimap := preload("res://scripts/builder/editor_minimap.gd")
const Shortcuts := preload("res://scripts/ui/shortcuts_panel.gd")

## What you place. ("room" is the room's own settings: size, sky, weather, music.)
const MODES := [["tiles", "Tiles"], ["objects", "Objects"], ["room", "Room"]]
## What you're doing, and the tools for it (the toolbox shows only these).
const GROUPS := [["place", "Place", "Put down blocks, tiles and objects"], ["paint", "Paint", "Recolour blocks, floor, walls and sky"],
	["edit", "Edit", "Select, move, duplicate and change settings"]]
const GROUP_TOOLS := {
	"place": ["place", "brush", "line", "rect", "rect_outline", "fill", "stamp", "erase"],
	"paint": ["paint", "eyedropper"],
	"edit": ["edit", "select", "erase"],
}

var build: Node
var prefs: Dictionary = {}
var phone := false
var group := "place"
var toolbox: Control
var room_tab: Control
var inspector: Control
var palette: Control
var minimap: Control
var _mode_btns: Dictionary = {}
var _group_btns: Dictionary = {}
var _undo_btn: Button
var _redo_btn: Button
var _adv_btn: Button
var _map_btn: Button
var _tools_btn: Button
var _pal_btn: Button
var _title: Label
var _saved: Label
var _status: Label
var _cursor_label: Label
var _hsplit: HSplitContainer
var _hsplit2: HSplitContainer
var _vsplit: VSplitContainer
var _left: PanelContainer
var _right: PanelContainer
var _pal_dock: PanelContainer
var _sheets: Dictionary = {}       # phone: "tools" | "pieces" | "props" -> the sheet
var _sheet_btns: Dictionary = {}
var _open_sheet := ""
var _tick := 0.0


## Split offsets are stored as Godot gives them (0 = the default position).
static func default_prefs() -> Dictionary:
	return {"advanced": false, "left_off": 0, "right_off": 0, "palette_off": 0, "show_map": false, "hide_tools": false, "hide_palette": false, "group": "place"}


static func group_of(tool: String) -> String:
	if tool in ["paint", "eyedropper"]:
		return "paint"
	if tool in ["edit", "select"]:
		return "edit"
	return "place"


func bind(build_mode: Node) -> void:
	build = build_mode
	prefs = default_prefs()
	var saved: Variant = GameState.settings.get("editor", {})
	if saved is Dictionary:
		for k in saved:
			prefs[k] = saved[k]
	group = str(prefs.get("group", "place"))
	if not GROUP_TOOLS.has(group) or not build.tool in GROUP_TOOLS[group]:
		group = group_of(build.tool)
	phone = TouchGestures.phone_layout()
	UiKit.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbox = Toolbox.new()
	toolbox.bind(build)
	room_tab = RoomTab.new()
	room_tab.bind(build)
	room_tab.visible = false
	inspector = Inspector.new()
	inspector.bind(build)
	palette = Palette.new()
	palette.bind(build)
	minimap = Minimap.new()
	minimap.bind(build)
	if phone:
		_phone_layout()
		# A phone has no room for the small map. It still gets a place here, hidden, so that it is
		# freed with the editor (a node that is in no tree is never freed by anyone).
		minimap.visible = false
		add_child(minimap)
	else:
		_pc_layout()
	build.state_changed.connect(refresh)
	if not phone:
		_apply_layout.call_deferred()
	refresh()
	build.world.hud.set_hint("")


func _pc_layout() -> void:
	var v := VBoxContainer.new()
	UiKit.fill(v)
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A PC has a mouse: the editor's panels use a denser text size than menus, so the world gets the room.
	var dense := Theme.new()
	dense.default_font_size = 18
	v.theme = dense
	add_child(v)
	v.add_child(_top_bar())
	_vsplit = VSplitContainer.new()
	_vsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vsplit.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_vsplit)
	_hsplit = HSplitContainer.new()
	_hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hsplit.mouse_filter = Control.MOUSE_FILTER_PASS
	_vsplit.add_child(_hsplit)
	_left = _dock()
	_left.name = "ToolsDock"
	_left.custom_minimum_size.x = 215
	_hsplit.add_child(_left)
	var lv := VBoxContainer.new()
	_left.add_child(lv)
	lv.add_child(_what_row())
	lv.add_child(toolbox)
	toolbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(room_tab)
	room_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hsplit2 = HSplitContainer.new()
	_hsplit2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hsplit2.mouse_filter = Control.MOUSE_FILTER_PASS
	_hsplit.add_child(_hsplit2)
	var center := Control.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hsplit2.add_child(center)
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -232
	minimap.offset_top = -192
	minimap.offset_right = -8
	minimap.offset_bottom = -8
	center.add_child(minimap)
	_right = _dock(true)
	_right.name = "PropertiesDock"
	_right.custom_minimum_size.x = 330
	_hsplit2.add_child(_right)
	_right.add_child(inspector)
	_pal_dock = _dock(true)
	_pal_dock.name = "PaletteDock"
	_pal_dock.custom_minimum_size.y = 205
	_vsplit.add_child(_pal_dock)
	_pal_dock.add_child(palette)
	v.add_child(_status_bar())


## Phone: the world in the middle, a slim bar on top and the toolbar under the thumb; tools, pieces and
## properties open as sheets above the toolbar (one at a time; tap again to close).
func _phone_layout() -> void:
	var v := VBoxContainer.new()
	UiKit.fill(v)
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", ThemeBuilder.aero_bar(ThemeBuilder.RADIUS_L, 6))   # [GLASS_UI] Frutiger Aero
	v.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 6)
	top.add_child(th)
	var done := _bar_button("Done", build.exit, "Back to the world (saves first)")
	done.name = "Done"
	th.add_child(done)
	_title = UiKit.label("", 18, ThemeBuilder.YELLOW)
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(_title)
	_undo_btn = _bar_button("↶", build.undo, "Undo")
	_undo_btn.name = "Undo"
	th.add_child(_undo_btn)
	_redo_btn = _bar_button("↷", build.redo, "Redo")
	_redo_btn.name = "Redo"
	th.add_child(_redo_btn)
	var play := _bar_button("▶", build.play_test, "Playtest from the cursor")
	play.name = "Playtest"
	th.add_child(play)
	_saved = UiKit.label("", 14, ThemeBuilder.MUTED)
	_saved.name = "SaveState"
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	for id in ["tools", "pieces", "props"]:
		var sheet := PanelContainer.new()
		sheet.name = "Sheet_" + id
		var sb: StyleBox = ThemeBuilder.solid_panel(ThemeBuilder.RADIUS_L, 10)
		sheet.add_theme_stylebox_override("panel", sb)
		sheet.visible = false
		sheet.custom_minimum_size.y = 300
		sheet.mouse_filter = Control.MOUSE_FILTER_STOP
		v.add_child(sheet)
		_sheets[id] = sheet
	var tools_box := VBoxContainer.new()
	tools_box.add_child(toolbox)
	toolbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools_box.add_child(room_tab)
	room_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheets.tools.add_child(tools_box)
	_sheets.pieces.add_child(palette)
	var props := VBoxContainer.new()
	props.add_child(inspector)
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var what := HBoxContainer.new()
	for m in MODES:
		var b := _toggle(m[1], func(): build.set_mode(m[0]), "")
		_mode_btns[m[0]] = b
		what.add_child(b)
	props.add_child(what)
	props.add_child(_saved)
	_sheets.props.add_child(props)
	var bottom := PanelContainer.new()
	bottom.name = "BottomToolbar"
	bottom.add_theme_stylebox_override("panel", ThemeBuilder.aero_bar(ThemeBuilder.RADIUS_L, 6))
	v.add_child(bottom)
	var bh := GridContainer.new()   # two rows of three: what you're doing, then what to open
	bh.columns = 3
	bh.add_theme_constant_override("h_separation", 4)
	bh.add_theme_constant_override("v_separation", 4)
	bottom.add_child(bh)
	for g in GROUPS:
		var b := _toggle(g[1], func(): set_group(g[0]), g[2])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeBuilder.aero_toggle(b)
		_group_btns[g[0]] = b
		bh.add_child(b)
	for spec in [["tools", "Tools"], ["pieces", "Pieces"], ["props", "More"]]:
		var id := str(spec[0])
		var b := _toggle(str(spec[1]) + " ▴", func(): _toggle_sheet(id), "")
		b.name = "Open_" + id
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sheet_btns[id] = b
		bh.add_child(b)
	var pad := Control.new()   # clear of the phone's gesture bar
	pad.custom_minimum_size.y = 6
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pad)


func _toggle_sheet(id: String) -> void:
	_open_sheet = "" if _open_sheet == id else id
	for k in _sheets:
		_sheets[k].visible = k == _open_sheet
		_sheet_btns[k].set_pressed_no_signal(k == _open_sheet)
	var h := get_viewport_rect().size.y
	if _open_sheet != "":
		_sheets[_open_sheet].custom_minimum_size.y = clampf(h * 0.42, 220.0, 520.0)


func _dock(solid: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ThemeBuilder.solid_panel(ThemeBuilder.RADIUS_M, 6) if solid else ThemeBuilder.bar(ThemeBuilder.RADIUS_M, 6))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


## A compact bar button: 44 px on a PC (the bars stay slim), finger-sized on a phone.
func _bar_button(text: String, on_press: Callable, tip: String) -> Button:
	var b := UiKit.button(text, on_press, 0)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	if not phone:
		b.custom_minimum_size = Vector2(44, 44)
		b.add_theme_font_size_override("font_size", 18)
	return b


func _toggle(text: String, on_press: Callable, tip: String) -> Button:
	var b := _bar_button(text, on_press, tip)
	b.toggle_mode = true
	return b


func _top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.add_theme_stylebox_override("panel", ThemeBuilder.aero_bar(ThemeBuilder.RADIUS_L, 6))   # [GLASS_UI] Frutiger Aero
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 4)
	bar.add_child(h)
	var done := _bar_button("← Done", build.exit, "Back to the world (saves first) • right-click or Q")
	done.name = "Done"
	h.add_child(done)
	_title = UiKit.label("", 20, ThemeBuilder.YELLOW)
	_title.clip_text = true
	_title.custom_minimum_size.x = 150
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_title)
	h.add_child(_divider())
	for g in GROUPS:
		var b := _toggle(g[1], func(): set_group(g[0]), g[2])
		b.name = "Mode_" + g[0]
		b.custom_minimum_size.x = 84
		ThemeBuilder.aero_toggle(b)
		_group_btns[g[0]] = b
		h.add_child(b)
	var play := _bar_button("▶ Playtest", build.play_test, "Walk from the cursor; Back to building returns here. Your edits are saved first.")
	play.name = "Playtest"
	play.add_theme_stylebox_override("normal", ThemeBuilder.key(Color("#2f8f5e"), Color("#c8ffe0", 0.7), ThemeBuilder.RADIUS_M, 10, 0.95, Color("#9dffb8", 0.35), 1, 0.32))
	h.add_child(play)
	var plat := CheckBox.new()
	plat.text = "Platform"
	plat.name = "PlaytestPlatform"
	plat.tooltip_text = "Playtest running and jumping (Platform Mode)"
	plat.focus_mode = Control.FOCUS_NONE
	plat.add_theme_font_size_override("font_size", 16)
	plat.button_pressed = build.play_platform
	plat.toggled.connect(func(on): build.play_platform = on)
	h.add_child(plat)
	h.add_child(_divider())
	_undo_btn = _bar_button("↶ Undo", build.undo, "Undo (Backspace). Up to 150 steps.")
	_undo_btn.name = "Undo"
	_redo_btn = _bar_button("↷ Redo", build.redo, "Redo")
	_redo_btn.name = "Redo"
	h.add_child(_undo_btn)
	h.add_child(_redo_btn)
	var save := _bar_button("Save", func():
		build.flush_save()
		GameState.notify("Room saved ✓"), "Saves now (edits also save by themselves a moment later)")
	save.name = "Save"
	h.add_child(save)
	_saved = UiKit.label("", 16, ThemeBuilder.MUTED)
	_saved.name = "SaveState"
	_saved.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_saved.custom_minimum_size.x = 120
	h.add_child(_saved)
	return bar


## What you place: Tiles, Objects, or the Room's own settings (top of the tools panel).
func _what_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "Placing"
	row.add_theme_constant_override("separation", 3)
	for m in MODES:
		var b := _toggle(m[1], func(): build.set_mode(m[0]), {"tiles": "Floors, walls, blocks and pictures", "objects": "Doors, signs, plants, lamps...", "room": "The room itself: size, sky, weather, music"}[m[0]])
		b.name = "What_" + m[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(0, 40)
		_mode_btns[m[0]] = b
		row.add_child(b)
	return row


func _divider() -> Control:
	var s := VSeparator.new()
	s.custom_minimum_size = Vector2(6, 36)
	return s


## Status bar: the hint on the left; camera, panels and layout on the right.
func _status_bar() -> Control:
	var bar := PanelContainer.new()
	bar.name = "StatusBar"
	bar.add_theme_stylebox_override("panel", ThemeBuilder.bar(ThemeBuilder.RADIUS_M, 4))
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 4)
	bar.add_child(h)
	_status = UiKit.label("", 16, ThemeBuilder.MUTED)
	_status.clip_text = true
	_status.custom_minimum_size.x = 300
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_status)
	_cursor_label = UiKit.label("", 16, ThemeBuilder.MUTED)
	_cursor_label.custom_minimum_size.x = 120
	_cursor_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_cursor_label)
	for spec in [["⟲", "Turn the camera left", func(): build.world.cam.rotate_step(-1)], ["⟳", "Turn the camera right", func(): build.world.cam.rotate_step(1)],
			["+", "Zoom in", func(): build.world.cam.zoom(-1)], ["−", "Zoom out", func(): build.world.cam.zoom(1)]]:
		h.add_child(_bar_button(spec[0], spec[2], spec[1]))
	_tools_btn = _toggle("Tools", func(): _set_pref("hide_tools", not bool(prefs.get("hide_tools", false))), "Show or hide the tools panel (more room to build)")
	_tools_btn.name = "PanelTools"
	h.add_child(_tools_btn)
	_pal_btn = _toggle("Palette", func(): _set_pref("hide_palette", not bool(prefs.get("hide_palette", false))), "Show or hide the palette")
	_pal_btn.name = "PanelPalette"
	h.add_child(_pal_btn)
	_map_btn = _toggle("Map", func(): _set_pref("show_map", not bool(prefs.get("show_map", false))), "Minimap and room list")
	h.add_child(_map_btn)
	_adv_btn = _toggle("Advanced", func(): _set_pref("advanced", not bool(prefs.get("advanced", false))), "Simple shows the essentials; Advanced shows every tool, the inspector and layers")
	_adv_btn.name = "Advanced"
	h.add_child(_adv_btn)
	h.add_child(_bar_button("Reset layout", _reset_layout, "Panels back to where they started"))
	h.add_child(_bar_button("?", func(): build.world.main.open_panel(Shortcuts.new()), "Keyboard shortcuts (all optional)"))
	return bar


## Switches what you're doing; keeps the tool if it belongs, otherwise takes the mode's first.
func set_group(g: String) -> void:
	if not GROUP_TOOLS.has(g):
		return
	group = g
	prefs["group"] = g
	_save_prefs()
	if build.mode == "room":
		build.set_mode("tiles")
	if not build.tool in GROUP_TOOLS[g]:
		build.set_tool(str(GROUP_TOOLS[g][0]))
	else:
		refresh()


func _set_pref(key: String, value: Variant) -> void:
	prefs[key] = value
	_save_prefs()
	_apply_layout()
	refresh()


func _save_prefs() -> void:
	GameState.settings["editor"] = prefs.duplicate()
	GameState.save_settings()


func _reset_layout() -> void:
	prefs = default_prefs()
	_save_prefs()
	_apply_layout()
	refresh()


func _apply_layout() -> void:
	if not is_inside_tree() or phone:
		return
	var adv := bool(prefs.get("advanced", false))
	_right.visible = adv
	_left.visible = not bool(prefs.get("hide_tools", false))
	_pal_dock.visible = not bool(prefs.get("hide_palette", false))
	minimap.visible = bool(prefs.get("show_map", false))
	_hsplit.split_offset = int(prefs.get("left_off", 0))
	_hsplit2.split_offset = int(prefs.get("right_off", 0))
	_vsplit.split_offset = int(prefs.get("palette_off", 0))
	if not _hsplit.dragged.is_connected(_on_drag):
		_hsplit.dragged.connect(_on_drag)
		_hsplit2.dragged.connect(_on_drag)
		_vsplit.dragged.connect(_on_drag)


## Remembers where the dividers were dragged to.
func _on_drag(_offset: int) -> void:
	prefs["left_off"] = _hsplit.split_offset
	prefs["right_off"] = _hsplit2.split_offset
	prefs["palette_off"] = _vsplit.split_offset
	_save_prefs()


func refresh() -> void:
	if build == null or not is_instance_valid(build):
		return
	if not build.tool in GROUP_TOOLS.get(group, []):
		group = group_of(build.tool)   # a key (1-9) or the palette picked a tool from another mode
	_title.text = ("Build: " if not phone else "") + str(build.world.room.data.get("name", ""))
	for k in _mode_btns:
		_mode_btns[k].set_pressed_no_signal(k == build.mode)
	for k in _group_btns:
		_group_btns[k].set_pressed_no_signal(k == group and build.mode != "room")
	toolbox.visible = build.mode != "room"
	room_tab.visible = build.mode == "room"
	_undo_btn.disabled = not build.history.can_undo()
	_redo_btn.disabled = not build.history.can_redo()
	var adv := bool(prefs.get("advanced", false)) or phone
	if _adv_btn:
		_adv_btn.set_pressed_no_signal(bool(prefs.get("advanced", false)))
		_map_btn.set_pressed_no_signal(bool(prefs.get("show_map", false)))
		_tools_btn.set_pressed_no_signal(not bool(prefs.get("hide_tools", false)))
		_pal_btn.set_pressed_no_signal(not bool(prefs.get("hide_palette", false)))
	toolbox.refresh(adv, GROUP_TOOLS.get(group, []))
	palette.refresh(adv)
	inspector.refresh()
	room_tab.refresh(adv)
	minimap.queue_redraw()
	if _status:
		_status.text = _hint()
	_show_saved()


func _process(delta: float) -> void:
	_tick += delta
	if _tick > 0.3:
		_tick = 0.0
		_show_saved()


## "● Unsaved edits" for the moment between an edit and its automatic save; then "Saved ✓".
func _show_saved() -> void:
	if _saved == null or build == null or not is_instance_valid(build):
		return
	var unsaved: bool = build.has_method("has_unsaved") and build.has_unsaved()
	_saved.text = "● Saving..." if unsaved else "Saved ✓"
	_saved.add_theme_color_override("font_color", ThemeBuilder.YELLOW if unsaved else ThemeBuilder.MINT)


func on_cursor(c: Vector2i) -> void:
	if _cursor_label:
		_cursor_label.text = "cell %d, %d  •  %s" % [c.x, c.y, build.layer if build.mode == "tiles" else build.mode]
	minimap.queue_redraw()


## Opens the inspector on a cell (the Edit tool).
func inspect_cell(c: Vector2i) -> void:
	if not bool(prefs.get("advanced", false)) and not phone:
		_set_pref("advanced", true)
	inspector.inspect(c)
	if phone and _open_sheet != "props":
		_toggle_sheet("props")


func _hint() -> String:
	if phone:
		# Fingers, not keys: say Tap, and point at the buttons instead of R / F / Q.
		return _hint_for_keys().replace("Click or drag", "Tap or drag").replace("Click", "Tap") \
			.replace(" • R rotates • F flips • right-click or Q when done", " • ⟳ R and ⇋ F turn it • Done when finished") \
			.replace(" • R rotates • F flips", " • ⟳ R and ⇋ F turn it").replace(" • [ ] brush size", "")
	return _hint_for_keys()


func _hint_for_keys() -> String:
	match build.tool:
		"place":
			return "Click a cell to place • R rotates • F flips • right-click or Q when done"
		"brush":
			return "Drag to paint (one undo step per stroke) • [ ] brush size"
		"line", "rect", "rect_outline":
			return "Drag from one corner to the other"
		"fill":
			return "Click to fill connected cells of the same ground tile"
		"erase":
			return "Click or drag to erase the top thing on this layer"
		"eyedropper":
			return "Click a cell to pick what's there as your brush"
		"select":
			return "Drag a rectangle, then Copy / Duplicate / Rotate / Flip / Save as stamp"
		"stamp":
			return "Click to drop the stamp • R rotates • F flips"
		"paint":
			return "Click a block, the floor or a wall to recolour it; empty space paints the sky"
		"edit":
			return "Click a block or tile for its settings; signs and doors open their editor"
	return ""
