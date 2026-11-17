extends "res://scripts/ui/screen_panel.gd"
## Assigns tiles from an imported/sliced atlas to the 16 N/E/S/W masks.

const Tilesets := preload("res://scripts/world/tilesets.gd")
const SmartTiles := preload("res://scripts/world/smart_tiles.gd")

var build: Node
var _set: OptionButton
var _name: LineEdit
var _fallback: OptionButton
var _variants: Array[OptionButton] = []


func _ready() -> void:
	setup("Smart tile group", Vector2(760, 690))
	body.add_child(UiKit.para("Import and slice an atlas in Tile Sets first, then assign its 16 edge patterns. Any missing slot uses the fallback tile.", 18, ThemeBuilder.MUTED))
	var sets := Tilesets.ids()
	_set = UiKit.option(sets)
	_set.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set.tooltip_text = "Pick the tile set you sliced from the atlas"
	_set.item_selected.connect(func(_i): _fill_tiles())
	body.add_child(UiKit.field_row("Tile set", _set, 80))
	_name = UiKit.line_edit("Group name")
	_name.text = "Connected ground"
	_name.tooltip_text = "A short name shown in the palette and favorites"
	body.add_child(UiKit.field_row("Name", _name, 80))
	_fallback = UiKit.option([])
	_fallback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fallback.tooltip_text = "Used for any neighbor pattern without its own tile"
	body.add_child(UiKit.field_row("Fallback", _fallback, 80))
	var scroll := UiKit.scroll(UiKit.vbox(3))
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var grid := scroll.get_child(0) as VBoxContainer
	for mask_value in 16:
		var row := UiKit.hbox(6)
		row.add_child(UiKit.label("%02d  %s" % [mask_value, _mask_name(mask_value)], 16, ThemeBuilder.CREAM))
		var pick := UiKit.option([])
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.tooltip_text = "Tile used when these N/E/S/W neighbors are connected"
		_variants.append(pick)
		row.add_child(pick)
		grid.add_child(row)
	var save := UiKit.button("Save smart group", _save, 0)
	save.tooltip_text = "Store all 16 masks in this tile set and select the group as your brush"
	body.add_child(save)
	_fill_tiles()


func _mask_name(value: int) -> String:
	var out := PackedStringArray()
	if value & 1: out.append("N")
	if value & 2: out.append("E")
	if value & 4: out.append("S")
	if value & 8: out.append("W")
	return "connected " + ("" if out.is_empty() else "+".join(out))


func _fill_tiles() -> void:
	var ids := Tilesets.ids()
	if _set.selected < 0 or _set.selected >= ids.size():
		return
	var data := Tilesets.load_set(ids[_set.selected])
	var labels := PackedStringArray()
	for tile in data.get("tiles", []):
		labels.append("%s (%s)" % [str(tile.get("name", tile.id)), str(tile.id)])
	for pick in [_fallback] + _variants:
		pick.clear()
		for label in labels:
			pick.add_item(label)
		if pick.item_count > 0:
			pick.select(0)


func _save() -> void:
	var ids := Tilesets.ids()
	if _set.selected < 0 or _set.selected >= ids.size() or _fallback.selected < 0:
		GameState.notify("Choose a tile set with at least one tile first.")
		return
	var set_id := str(ids[_set.selected])
	var data := Tilesets.load_set(set_id)
	var tile_ids: PackedStringArray = []
	for t in data.tiles:
		tile_ids.append(str(t.id))
	var variants: Array = []
	for pick in _variants:
		variants.append(tile_ids[pick.selected] if pick.selected >= 0 and pick.selected < tile_ids.size() else "")
	var group_id := SmartTiles.assign(set_id, _name.text, variants, tile_ids[_fallback.selected])
	if group_id == "":
		GameState.notify("Couldn't save that smart tile group.")
		return
	build.brush_set = set_id
	build.set_smart_group(group_id)
	GameState.notify("Smart tile group ready. Paint it on the room.")
	close()
