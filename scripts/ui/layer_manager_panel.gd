extends "res://scripts/ui/screen_panel.gd"
## Advanced tile-layer controls. Edits run through build.edit_room so every
## change participates in undo, autosave and renderer rebuilds.

const TileLayers := preload("res://scripts/world/tile_layers.gd")

var build: Node
var _pick: OptionButton
var _name: LineEdit
var _type: OptionButton
var _elevation: SpinBox
var _opacity: HSlider
var _visible: CheckBox
var _locked: CheckBox
var _target: OptionButton
var _loading := false


func _ready() -> void:
	setup("Tile Layers", Vector2(720, 620))
	body.add_child(UiKit.para("Advanced layers draw from bottom to top. Locked layers stay safe while you paint.", 18, ThemeBuilder.MUTED))
	var pick_row := UiKit.hbox(8)
	_pick = UiKit.option([])
	_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick.item_selected.connect(_load_selected)
	pick_row.add_child(UiKit.field_row("Layer", _pick, 80))
	var up := UiKit.button("Up", func(): _move(-1), 70)
	up.tooltip_text = "Move this layer one step toward the backdrop"
	pick_row.add_child(up)
	var down := UiKit.button("Down", func(): _move(1), 80)
	down.tooltip_text = "Move this layer one step toward the foreground"
	pick_row.add_child(down)
	var delete := UiKit.button("Delete", _delete, 90)
	delete.tooltip_text = "Remove this layer and its tiles; Undo restores it"
	pick_row.add_child(delete)
	body.add_child(pick_row)
	_name = UiKit.line_edit("Layer name")
	_name.tooltip_text = "Displayed name for this room layer"
	body.add_child(UiKit.field_row("Name", _name, 100))
	_type = UiKit.option(Array(TileLayers.TYPES).map(func(t): return str(TileLayers.TYPE_NAMES[t])))
	_type.tooltip_text = "Choose whether the layer sits behind the room, on the floor, among blocks or in front"
	body.add_child(UiKit.field_row("Kind", _type, 100))
	_elevation = SpinBox.new()
	_elevation.min_value = -TileLayers.MAX_LEVEL
	_elevation.max_value = TileLayers.MAX_LEVEL
	_elevation.custom_minimum_size = Vector2(110, 44)
	_elevation.tooltip_text = "Raise or lower all tiles in this layer"
	body.add_child(UiKit.field_row("Elevation", _elevation, 100))
	_opacity = UiKit.slider(0.1, 1.0, 0.05, 1.0)
	_opacity.tooltip_text = "Set the whole layer's opacity"
	body.add_child(UiKit.field_row("Opacity", _opacity, 100))
	var flags := UiKit.hbox(14)
	_visible = CheckBox.new()
	_visible.text = "Visible"
	_visible.tooltip_text = "Show or hide the whole layer"
	_locked = CheckBox.new()
	_locked.text = "Locked"
	_locked.tooltip_text = "Protect this layer from painting and erasing"
	flags.add_child(_visible)
	flags.add_child(_locked)
	body.add_child(flags)
	var apply := UiKit.button("Apply layer settings", _apply, 0)
	apply.tooltip_text = "Apply name, type, elevation, opacity, visibility and lock"
	body.add_child(apply)
	body.add_child(UiKit.label("New layer", 18, ThemeBuilder.YELLOW))
	var new_row := UiKit.hbox(6)
	var new_name := UiKit.line_edit("Name (optional)")
	new_name.tooltip_text = "Optional name for the new layer"
	new_row.add_child(new_name)
	var new_type := UiKit.option(Array(TileLayers.TYPES).map(func(t): return str(TileLayers.TYPE_NAMES[t])))
	new_type.tooltip_text = "Layer kind controls where and how its pictures render"
	new_row.add_child(new_type)
	var add_button := UiKit.button("Add", func():
		var t := str(TileLayers.TYPES[new_type.selected])
		build.edit_room(func(data): TileLayers.add(data, new_name.text, t))
		_refresh_options()
	, 70)
	add_button.tooltip_text = "Add an empty layer of the selected kind"
	new_row.add_child(add_button)
	body.add_child(new_row)
	body.add_child(UiKit.label("Move selected tiles", 18, ThemeBuilder.YELLOW))
	var move_row := UiKit.hbox(6)
	_target = UiKit.option([])
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_row.add_child(_target)
	var move_selection := UiKit.button("Move selection here", _move_selection, 180)
	move_selection.tooltip_text = "Move cells in the active box selection into this layer"
	move_row.add_child(move_selection)
	body.add_child(move_row)
	_refresh_options()


func _refresh_options() -> void:
	_loading = true
	var layers := TileLayers.all(build.world.room.data)
	var selected_id := str(_selected_layer().get("id", ""))
	var target_id := str(layers[_target.selected].get("id", "")) if _target.selected >= 0 and _target.selected < layers.size() else ""
	_pick.clear()
	_target.clear()
	for l in layers:
		var text := "%s — %s" % [str(l.name), str(TileLayers.TYPE_NAMES.get(str(l.type), ""))]
		_pick.add_item(text)
		_target.add_item(text)
	var room: Dictionary = build.world.room.data
	var selected_index := TileLayers.index_of(room, selected_id)
	var target_index := TileLayers.index_of(room, target_id)
	_pick.select(clampi(selected_index, 0, maxi(0, layers.size() - 1)))
	_target.select(clampi(target_index, 0, maxi(0, layers.size() - 1)))
	_loading = false
	_load_selected(_pick.selected)


func _selected_layer() -> Dictionary:
	var layers := TileLayers.all(build.world.room.data)
	return layers[_pick.selected] if _pick.selected >= 0 and _pick.selected < layers.size() else {}


func _load_selected(_index: int) -> void:
	if _loading:
		return
	var l := _selected_layer()
	if l.is_empty():
		return
	_loading = true
	_name.text = str(l.get("name", ""))
	_type.select(maxi(0, TileLayers.TYPES.find(str(l.get("type", "ground")))))
	_elevation.value = int(l.get("elevation", 0))
	_opacity.value = float(l.get("opacity", 1.0))
	_visible.button_pressed = bool(l.get("visible", true))
	_locked.button_pressed = bool(l.get("locked", false))
	_loading = false


func _apply() -> void:
	var id := str(_selected_layer().get("id", ""))
	if id == "":
		return
	var name_text := _name.text.strip_edges().substr(0, 40)
	var type_text := str(TileLayers.TYPES[_type.selected])
	var elevation_value := int(_elevation.value)
	var opacity_value := _opacity.value
	var visible_value := _visible.button_pressed
	var locked_value := _locked.button_pressed
	build.edit_room(func(data):
		var l := TileLayers.find(data, id)
		if not l.is_empty():
			l["name"] = name_text if name_text != "" else str(TileLayers.TYPE_NAMES[type_text])
			l["type"] = type_text
			l["elevation"] = elevation_value
			l["opacity"] = opacity_value
			l["visible"] = visible_value
			l["locked"] = locked_value)
	_refresh_options()


func _move(delta: int) -> void:
	var id := str(_selected_layer().get("id", ""))
	if id != "":
		build.edit_room(func(data): TileLayers.move(data, id, delta))
		_refresh_options()


func _delete() -> void:
	var l := _selected_layer()
	if l.is_empty():
		return
	var id := str(l.id)
	var confirm := preload("res://scripts/ui/confirm_panel.gd").new()
	add_child(confirm)
	confirm.ask("Delete this layer?", "Its tiles will be removed from the room. You can undo immediately.", "Delete", "Keep")
	confirm.answered.connect(func(yes: bool):
		if yes:
			build.edit_room(func(data): TileLayers.remove(data, id), "remove")
			_refresh_options())


func _move_selection() -> void:
	if not build.tools.has_selection():
		GameState.notify("Select an area in the room first.")
		return
	var layers := TileLayers.all(build.world.room.data)
	if _target.selected < 0 or _target.selected >= layers.size():
		return
	var from_id := str(_selected_layer().get("id", ""))
	var to_id := str(layers[_target.selected].id)
	var selection: Rect2i = build.selection
	build.edit_room(func(data):
		var from := TileLayers.find(data, from_id)
		var to := TileLayers.find(data, to_id)
		if from.is_empty() or to.is_empty() or from_id == to_id:
			return
		for z in range(selection.position.y, selection.end.y):
			for x in range(selection.position.x, selection.end.x):
				var c := TileLayers.get_cell(from, x, z)
				if not c.is_empty():
					TileLayers.put(to, x, z, c.duplicate(true))
					TileLayers.erase(from, x, z))
