extends "res://scripts/ui/screen_panel.gd"
## Find/replace and re-skin operate on the open room and use one editor
## snapshot, so Undo restores every affected tile together.

const Tilesets := preload("res://scripts/world/tilesets.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const RoomSearch := preload("res://scripts/world/room_search.gd")

var build: Node
var _from_set: OptionButton
var _from_tile: OptionButton
var _to_set: OptionButton
var _to_tile: OptionButton
var _layer: OptionButton
var _sets := PackedStringArray()
var _layers: Array = []


func _ready() -> void:
	setup("Find and replace tiles", Vector2(700, 560))
	body.add_child(UiKit.para("Changes only the open room. The whole operation is one Undo step.", 18, ThemeBuilder.MUTED))
	_sets = Tilesets.ids()
	_from_set = UiKit.option(_sets)
	_to_set = UiKit.option(_sets)
	_from_tile = UiKit.option([])
	_to_tile = UiKit.option([])
	_from_set.tooltip_text = "Tile set containing the tile to find"
	_from_tile.tooltip_text = "Exact tile to find"
	_to_set.tooltip_text = "Tile set that contains the replacement"
	_to_tile.tooltip_text = "Tile that replaces every match"
	_from_set.item_selected.connect(func(_i): _fill_tiles())
	_to_set.item_selected.connect(func(_i): _fill_tiles())
	body.add_child(UiKit.field_row("Find set", _from_set, 100))
	body.add_child(UiKit.field_row("Find tile", _from_tile, 100))
	body.add_child(UiKit.field_row("Replace set", _to_set, 100))
	body.add_child(UiKit.field_row("Replace tile", _to_tile, 100))
	_layers = TileLayers.all(build.world.room.data)
	_layer = UiKit.option(["All tile layers"] + _layers.map(func(l): return str(l.name)))
	_layer.tooltip_text = "Limit the operation to one room layer"
	body.add_child(UiKit.field_row("Scope", _layer, 100))
	var replace := UiKit.button("Replace matching tiles", _replace, 0)
	replace.tooltip_text = "Change exact set/tile matches in this room (Undo restores them)"
	body.add_child(replace)
	body.add_child(UiKit.label("Re-skin by matching tile names", 20, ThemeBuilder.YELLOW))
	body.add_child(UiKit.para("Maps tiles in one set to tiles with the same name in another set. Unmatched tiles stay as they are.", 16, ThemeBuilder.MUTED))
	var reskin := UiKit.button("Re-skin source set to target set", _reskin, 0)
	reskin.tooltip_text = "Swap to same-named tiles in the target set; unmatched tiles are left alone"
	body.add_child(reskin)
	_fill_tiles()


func _fill_tiles() -> void:
	_fill_one(_from_tile, _from_set)
	_fill_one(_to_tile, _to_set)


func _fill_one(tile_pick: OptionButton, set_pick: OptionButton) -> void:
	tile_pick.clear()
	if set_pick.selected < 0 or set_pick.selected >= _sets.size():
		return
	for tile in Tilesets.load_set(_sets[set_pick.selected]).get("tiles", []):
		tile_pick.add_item("%s (%s)" % [tile.name, tile.id])


func _scope() -> String:
	return "" if _layer.selected <= 0 or _layer.selected > _layers.size() else str(_layers[_layer.selected - 1].id)


func _replace() -> void:
	if _from_set.selected < 0 or _to_set.selected < 0 or _from_tile.selected < 0 or _to_tile.selected < 0:
		return
	var fs := str(_sets[_from_set.selected])
	var ts := str(_sets[_to_set.selected])
	var ft := str(Tilesets.load_set(fs).tiles[_from_tile.selected].id)
	var tt := str(Tilesets.load_set(ts).tiles[_to_tile.selected].id)
	var changed: int = int(build.edit_room(func(room): return RoomSearch.find_replace(room, fs, ft, ts, tt, _scope())))
	GameState.notify("Replaced %d tile(s)." % changed)


func _reskin() -> void:
	if _from_set.selected < 0 or _to_set.selected < 0:
		return
	var fs := str(_sets[_from_set.selected])
	var ts := str(_sets[_to_set.selected])
	var changed: int = int(build.edit_room(func(room): return RoomSearch.reskin(room, fs, ts, _scope())))
	GameState.notify("Re-skinned %d tile(s) by name." % changed)
