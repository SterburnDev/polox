extends VBoxContainer
## The editor's right column: what's under the cursor (and the settings of
## an inspected tile: solid, fade, tint, orientation, rotation, flip), plus
## the Layers panel: the room's tile layers (top first), the 3D pieces and
## the backdrop picture, each with visible / lock / opacity.
## Tags: [BUILDER]

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")

const ORIENT_LABELS := {"floor": "Flat", "wall_n": "North wall", "wall_e": "East wall", "wall_s": "South wall", "wall_w": "West wall", "standing": "Standing"}

var build: Node
var _sel_box: VBoxContainer
var _layers_box: VBoxContainer
var _layers_sig := ""
var _inspected := Vector2i(-1, -1)
var _inspected_layer := ""
var _layer_rows: Dictionary = {}


func _ready() -> void:
	theme = ThemeBuilder.info_theme()   # [GLASS_UI] iOS 7's clear, layered lists for the inspector


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
	v.add_child(UiKit.label("Inspector", 18, ThemeBuilder.MUTED))
	_sel_box = UiKit.vbox(4)
	v.add_child(_sel_box)
	v.add_child(UiKit.label("Layers", 18, ThemeBuilder.MUTED))
	_layers_box = UiKit.vbox(4)
	v.add_child(_layers_box)
	v.add_child(UiKit.para("Click a layer to paint on it. Eye = shown, lock = no edits, slider = see-through. Top of the list = drawn on top.", 16, ThemeBuilder.MUTED))
	var manager := UiKit.button("Advanced: manage layers...", func():
		var panel := preload("res://scripts/ui/layer_manager_panel.gd").new()
		panel.build = build
		build.world.main.open_panel(panel), 0)
	manager.tooltip_text = "Add, rename, reorder, delete and tune custom layers"
	v.add_child(manager)


## The rows to show: tile layers top first, then the 3D pieces and the backdrop.
func _layer_specs(data: Dictionary) -> Array:
	var out: Array = []
	var tl: Array = TileLayers.all(data).duplicate()
	tl.reverse()
	for l in tl:
		out.append([str(l.id), str(l.name), str(TileLayers.TYPE_NAMES.get(str(l.type), ""))])
	out.append(["pieces", "Pieces (3D blocks)", ""])
	out.append(["backdrop", "Backdrop picture", ""])
	return out


func _rebuild_layers(data: Dictionary) -> void:
	var specs := _layer_specs(data)
	var sig := str(specs)
	if sig == _layers_sig:
		return
	_layers_sig = sig
	for c in _layers_box.get_children():
		c.free()
	_layer_rows.clear()
	for spec in specs:
		_layers_box.add_child(_layer_row(spec[0], spec[1], spec[2]))


func _layer_row(id: String, label: String, type_name: String) -> Control:
	var row := UiKit.vbox(2)
	var top := UiKit.hbox(4)
	var pick := UiKit.button(label, func(): _pick_layer(id), 0)
	pick.toggle_mode = true
	pick.focus_mode = Control.FOCUS_NONE
	pick.add_theme_font_size_override("font_size", 18)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.clip_text = true
	pick.disabled = id == "backdrop"
	pick.tooltip_text = ("%s layer: click to paint on it" % type_name) if type_name != "" else ("Blocks, ramps and objects" if id == "pieces" else "The picture behind the room (Room tab)")
	top.add_child(pick)
	var eye := UiKit.button("👁", func(): _toggle(id, "visible"), 44)
	eye.toggle_mode = true
	eye.focus_mode = Control.FOCUS_NONE
	eye.tooltip_text = "Show / hide this layer"
	top.add_child(eye)
	var lock := UiKit.button("🔒", func(): _toggle(id, "lock"), 44)
	lock.toggle_mode = true
	lock.focus_mode = Control.FOCUS_NONE
	lock.tooltip_text = "Lock: no edits on this layer"
	top.add_child(lock)
	row.add_child(top)
	var op := UiKit.slider(0.1, 1.0, 0.05, 1.0)
	op.custom_minimum_size = Vector2(100, 28)
	op.tooltip_text = "How solid the layer looks (lower = see-through)"
	op.value_changed.connect(func(x): _set_opacity(id, x))
	row.add_child(op)
	_layer_rows[id] = [pick, eye, lock, op]
	return row


func _pick_layer(id: String) -> void:
	if id == "pieces":
		if build.piece == "tile":
			build.set_piece("cube")
		return
	if build.piece != "tile" and build.brush_set != "":
		build.set_brush_tile(build.brush_set, build.brush_tile)
	if build.mode != "tiles":
		build.set_mode("tiles")
	build.set_layer(id)


func _toggle(id: String, key: String) -> void:
	build.edit_room(func(data):
		var st: Dictionary = RoomOps.layer_state(data, id)
		RoomOps.set_layer_state(data, id, key, not bool(st.get(key, key == "visible"))))


func _set_opacity(id: String, x: float) -> void:
	var st: Dictionary = RoomOps.layer_state(build.world.room.data, id)
	if is_equal_approx(float(st.get("opacity", 1.0)), x):
		return
	build.edit_room(func(data): RoomOps.set_layer_state(data, id, "opacity", snappedf(x, 0.05)))


func refresh() -> void:
	var data: Dictionary = build.world.room.data
	_rebuild_layers(data)
	var active: String = build._active_layer()
	for id in _layer_rows:
		var st: Dictionary = RoomOps.layer_state(data, id)
		var r: Array = _layer_rows[id]
		r[0].set_pressed_no_signal(active == id and build.mode == "tiles")
		r[1].set_pressed_no_signal(bool(st.get("visible", true)))
		r[2].set_pressed_no_signal(bool(st.get("lock", false)))
		r[3].set_value_no_signal(float(st.get("opacity", 1.0)))
	if _inspected.x >= 0:
		inspect(_inspected)
	else:
		_show_summary()


## Lists what sits on the cell under the cursor.
func _show_summary() -> void:
	for c in _sel_box.get_children():
		c.free()
	var data: Dictionary = build.world.room.data
	var c: Vector2i = build.cursor
	var lines := PackedStringArray()
	var tl: Array = TileLayers.all(data).duplicate()
	tl.reverse()
	for l in tl:
		var cell := TileLayers.get_cell(l, c.x, c.y)
		if not cell.is_empty():
			var t := Tilesets.info(str(cell.s), str(cell.t))
			lines.append("%s: %s" % [l.name, str(t.get("name", cell.t)) if not t.is_empty() else "%s / %s (missing)" % [cell.s, cell.t]])
	for t in data.get("tiles", []):
		if int(t.get("x", -1)) == c.x and int(t.get("z", -1)) == c.y:
			lines.append("Block: %s at %s" % [t.get("type", ""), str(t.get("y", 0))])
	var o := RoomEditor.object_at(data, c.x, c.y)
	if not o.is_empty():
		lines.append("Object: %s (%s)" % [o.type, o.id])
	_sel_box.add_child(UiKit.para(("\n".join(lines)) if not lines.is_empty() else "Nothing on cell %d, %d. Use the Edit tool on a tile to change its settings." % [c.x, c.y], 16, ThemeBuilder.CREAM))


## The layer an inspect looks at: the active tile layer if it has a tile
## there, else the top-most tile layer that does.
func _layer_with_cell(data: Dictionary, c: Vector2i) -> Dictionary:
	var own := TileLayers.find(data, build.layer)
	if not own.is_empty() and not TileLayers.get_cell(own, c.x, c.y).is_empty():
		return own
	var tl: Array = TileLayers.all(data).duplicate()
	tl.reverse()
	for l in tl:
		if not TileLayers.get_cell(l, c.x, c.y).is_empty():
			return l
	return {}


## Opens the settings of a tile on a cell (Edit tool).
func inspect(c: Vector2i) -> void:
	_inspected = c
	for ch in _sel_box.get_children():
		ch.free()
	var data: Dictionary = build.world.room.data
	var l := TileLayers.find(data, _inspected_layer) if _inspected_layer != "" else {}
	if l.is_empty() or TileLayers.get_cell(l, c.x, c.y).is_empty():
		l = _layer_with_cell(data, c)
	if l.is_empty():
		_inspect_piece(data, c)
		return
	_inspected_layer = str(l.id)
	var lid := str(l.id)
	var cell := TileLayers.get_cell(l, c.x, c.y)
	var type := str(l.type)
	var t := Tilesets.info(str(cell.s), str(cell.t))
	_sel_box.add_child(UiKit.label("%s tile at %d, %d" % [l.name, c.x, c.y], 18, ThemeBuilder.YELLOW))
	_sel_box.add_child(UiKit.label(str(t.get("name", cell.t)) if not t.is_empty() else "%s (missing)" % cell.t, 16, ThemeBuilder.MUTED))
	_sel_box.add_child(UiKit.button("Event tile...", func():
		var panel := preload("res://scripts/ui/tile_event_panel.gd").new()
		panel.build = build
		panel.layer_id = lid
		panel.cell = c
		build.world.main.open_panel(panel), 140))
	if type != "ground":
		var orients: Array = Array(TileLayers.ORIENTS)
		var orient := UiKit.option(orients.map(func(o): return ORIENT_LABELS[o]), maxi(0, orients.find(TileLayers.orient_of(l, cell))))
		orient.tooltip_text = "How the picture sits in its cell"
		orient.item_selected.connect(func(i): _set_field(lid, c, "o", orients[i]))
		_sel_box.add_child(UiKit.field_row("As", orient, 70))
		var solid := CheckBox.new()
		solid.text = "Solid (blocks walking)"
		solid.tooltip_text = "Ticked: nobody walks through this cell. The tile set decides when this is left alone."
		solid.button_pressed = bool(cell.get("solid", t.get("solid", false) if type == "blocks" else false))
		solid.toggled.connect(func(on): _set_field(lid, c, "solid", on))
		_sel_box.add_child(solid)
	if type == "foreground":
		var fade := CheckBox.new()
		fade.text = "Fades when hiding someone"
		fade.button_pressed = bool(cell.get("fade", t.get("fade", true)))
		fade.toggled.connect(func(on): _set_field(lid, c, "fade", on))
		_sel_box.add_child(fade)
	var tint := ColorPickerButton.new()
	tint.text = "Tint"
	tint.tooltip_text = "Colour this one tile"
	tint.custom_minimum_size = Vector2(120, 44)
	tint.color = Color.from_string(str(cell.get("tint", "#ffffff")), Color.WHITE)
	tint.edit_alpha = false
	tint.color_changed.connect(func(col): _set_field(lid, c, "tint", "#" + col.to_html(false)))
	var trow := UiKit.hbox(6)
	trow.add_child(tint)
	trow.add_child(UiKit.button("No tint", func(): _set_field(lid, c, "tint", "#ffffff"), 100))
	_sel_box.add_child(trow)
	var flip := CheckBox.new()
	flip.text = "Mirrored"
	flip.button_pressed = bool(cell.get("fl", false))
	flip.toggled.connect(func(on): _set_field(lid, c, "fl", on))
	_sel_box.add_child(flip)
	var rrow := UiKit.hbox(6)
	rrow.add_child(UiKit.button("⟳ Rotate", func(): _set_field(lid, c, "r", posmod(int(cell.get("r", 0)) + 1, 4)), 120))
	if type != "ground":
		rrow.add_child(UiKit.button("Up", func(): _set_field(lid, c, "y", mini(TileLayers.MAX_LEVEL, int(cell.get("y", 0)) + 1)), 60))
		rrow.add_child(UiKit.button("Down", func(): _set_field(lid, c, "y", maxi(0, int(cell.get("y", 0)) - 1)), 80))
	_sel_box.add_child(rrow)
	_sel_box.add_child(UiKit.button("Done", _close_inspect, 100))


## A 3D piece on the cell: only turning it.
func _inspect_piece(data: Dictionary, c: Vector2i) -> void:
	var top := {}
	for t in data.get("tiles", []):
		if int(t.get("x", -1)) == c.x and int(t.get("z", -1)) == c.y and (top.is_empty() or float(t.get("y", 0)) > float(top.get("y", 0))):
			top = t
	if top.is_empty():
		_close_inspect()
		return
	var y := float(top.get("y", 0))
	_sel_box.add_child(UiKit.label("%s at %d, %d" % [str(top.get("type", "Block")).capitalize(), c.x, c.y], 18, ThemeBuilder.YELLOW))
	_sel_box.add_child(UiKit.button("⟳ Rotate", func():
		build.edit_room(func(d):
			for t in d.get("tiles", []):
				if int(t.get("x", -1)) == c.x and int(t.get("z", -1)) == c.y and is_equal_approx(float(t.get("y", 0)), y):
					t["rot"] = posmod(int(t.get("rot", 0)) + 1, 4)
					return), 120))
	_sel_box.add_child(UiKit.button("Done", _close_inspect, 100))


func _close_inspect() -> void:
	_inspected = Vector2i(-1, -1)
	_inspected_layer = ""
	_show_summary()


## Changes one field of an inspected tile as an undo step (found again by
## layer and cell after the snapshot copy). Defaults are left out of the cell.
func _set_field(layer_id: String, c: Vector2i, key: String, value: Variant) -> void:
	build.edit_room(func(data):
		var l := TileLayers.find(data, layer_id)
		var cell := TileLayers.get_cell(l, c.x, c.y)
		if cell.is_empty():
			return
		var flags := cell.duplicate()
		flags[key] = value
		var fresh := TileLayers.make_cell(str(cell.s), str(cell.t), str(flags.get("o", "")), flags)
		if str(fresh.get("o", "")) == str(TileLayers.DEFAULT_ORIENT.get(str(l.type), "")):
			fresh.erase("o")
		TileLayers.put(l, c.x, c.y, fresh))
