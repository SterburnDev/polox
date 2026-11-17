extends VBoxContainer
## The editor's left column: the current mode's tools (editor_shell.gd: Place, Paint or Edit), which tool
## is selected and its shortcut, brush size, elevation, snap, random brush, rotate/flip, and the selection
## actions (Copy, Duplicate, Cut, Paste...). Simple mode shows only the first few tools. Every tooltip
## names its keyboard shortcut; every action is a button too.
## Tags: [BUILDER]

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

const TOOLS := [
	["place", "Place", "Put one thing down", false], ["brush", "Brush", "Drag to paint", false],
	["erase", "Erase", "Remove the top thing", false], ["eyedropper", "Pick", "Copy what's under the cursor", false],
	["line", "Line", "Drag a straight line", true], ["rect", "Rect", "Drag a filled rectangle", true],
	["rect_outline", "Outline", "Drag a hollow rectangle", true], ["fill", "Fill", "Flood connected cells", true],
	["select", "Select", "Box-select to move, copy, rotate, flip", true], ["stamp", "Stamp", "Drop a saved stamp", true],
	["paint", "Paint", "Recolour blocks, floor, walls, sky", false], ["edit", "Edit", "Settings of a tile or object", false],
]

var build: Node
var _tool_btns: Dictionary = {}
var _size_btns: Array[Button] = []
var _elev_label: Label
var _snap_btn: Button
var _random_btn: Button
var _sel_box: VBoxContainer
var _advanced_rows: Array[Control] = []
var _current: Label
## Tool -> its key (build_mode.gd KEY_TOOLS), for the tooltips and the "selected" line.
const KEYS := {"place": "1", "brush": "2", "line": "3", "rect": "4", "fill": "5", "erase": "6", "eyedropper": "7", "select": "8", "stamp": "9"}


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
	_current = UiKit.label("", 16, ThemeBuilder.YELLOW)
	_current.name = "CurrentTool"
	_current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_current)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for t in TOOLS:
		var b := UiKit.button(t[1], func(): build.set_tool(t[0]), 0)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = str(t[2]) + (" (%s)" % KEYS[t[0]] if KEYS.has(t[0]) else "")
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("advanced", t[3])
		_tool_btns[t[0]] = b
		grid.add_child(b)
	var rf := UiKit.hbox(4)
	var _b1 := UiKit.button("⟳ R", build.rotate_piece, 0)
	_b1.tooltip_text = "Rotate (R)" if false else ""
	rf.add_child(_b1)
	v.add_child(rf)
	var rot := rf.get_child(0) as Button
	rot.tooltip_text = "Rotate what you're placing (R)"
	rot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var flipb := UiKit.button("⇋ F", build.flip_piece, 0)
	flipb.tooltip_text = "Mirror what you're placing (F)"
	flipb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rf.add_child(flipb)
	var size_label := UiKit.label("Brush size", 18, ThemeBuilder.MUTED)
	v.add_child(size_label)
	var sizes := UiKit.hbox(3)
	for n in [1, 2, 3, 4, 5]:
		var b := UiKit.button(str(n), func(): build.set_brush_size(n), 0)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_size_btns.append(b)
		sizes.add_child(b)
	v.add_child(sizes)
	var elev_title := UiKit.label("Elevation", 18, ThemeBuilder.MUTED)
	v.add_child(elev_title)
	var elev := UiKit.hbox(4)
	elev.add_child(UiKit.button("−", func(): build.set_elevation(build.elevation - 1), 48))
	_elev_label = UiKit.label("0", 22)
	_elev_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elev_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elev.add_child(_elev_label)
	elev.add_child(UiKit.button("+", func(): build.set_elevation(build.elevation + 1), 48))
	v.add_child(elev)
	_snap_btn = UiKit.button("Snap: on", func(): build.set_snap(not build.snap), 0)
	_snap_btn.tooltip_text = "Off lets signs and plants sit between cells (G)"
	v.add_child(_snap_btn)
	_random_btn = UiKit.button("Random: off", func(): build.set_random(not build.random_on), 0)
	_random_btn.tooltip_text = "Paint a random tile from the ones you tick in the palette"
	v.add_child(_random_btn)
	_sel_box = UiKit.vbox(4)
	_sel_box.add_child(UiKit.label("Selection", 18, ThemeBuilder.MUTED))
	for spec in [["Copy", func(): build.tools.copy_selection()], ["Duplicate", _duplicate], ["Cut", func(): build.tools.cut_selection()], ["Paste (V)", func(): build.tools.paste_clipboard()],
			["Rotate", func(): build.tools.rotate_selection()], ["Flip", func(): build.tools.flip_selection()], ["Delete", func(): build.tools.delete_selection()],
			["Save as stamp", _save_stamp], ["Clear selection", func():
				build.selection = Rect2i()
				build.state_changed.emit()]]:
		var b := UiKit.button(spec[0], spec[1], 0)
		b.add_theme_font_size_override("font_size", 18)
		_sel_box.add_child(b)
	v.add_child(_sel_box)
	_advanced_rows = [size_label, sizes, elev_title, elev, _snap_btn, _random_btn, _sel_box]


## Duplicate: a copy of the selection, dropped at the cursor (move the cursor first to choose where).
func _duplicate() -> void:
	if not build.tools.has_selection():
		GameState.notify("Select an area first (Select tool).")
		return
	build.tools.copy_selection()
	build.tools.paste_clipboard()


func _save_stamp() -> void:
	var s: Dictionary = build.tools.selection_stamp()
	if s.is_empty():
		GameState.notify("Select an area first (Select tool).")
		return
	var p := preload("res://scripts/ui/stamp_panel.gd").new()
	p.build = build
	p.save_stamp(s)
	build.world.main.open_panel(p)


func refresh(advanced: bool, only: Array = []) -> void:
	for k in _tool_btns:
		_tool_btns[k].set_pressed_no_signal(k == build.tool)
		_tool_btns[k].visible = (advanced or not bool(_tool_btns[k].get_meta("advanced", false))) and (only.is_empty() or k in only or k == build.tool)
	for t in TOOLS:
		if t[0] == build.tool:
			_current.text = "Tool: %s%s\n%s" % [t[1], "  (%s)" % KEYS[t[0]] if KEYS.has(t[0]) else "", t[2]]
	for r in _advanced_rows:
		r.visible = advanced
	for i in _size_btns.size():
		_size_btns[i].set_pressed_no_signal(i + 1 == build.brush_size)
	_elev_label.text = str(build.elevation)
	_snap_btn.text = "Snap: on" if build.snap else "Snap: off"
	_random_btn.text = "Random: on (%d)" % build.random_pool.size() if build.random_on else "Random: off"
	_sel_box.visible = advanced and (build.tool == "select" or build.tools.has_selection())
