extends "res://scripts/ui/screen_panel.gd"
## Import a PNG atlas: pick the tile size, see the auto-sliced cells, name
## the ones you want, and make a new tile set from them.

signal done(set_id: String)

const Tilesets := preload("res://scripts/world/tilesets.gd")

var path := ""
var library := false
var _img: Image
var _size: OptionButton
var _margin: SpinBox
var _spacing: SpinBox
var _grid: HFlowContainer
var _set_name: LineEdit
var _cells: Array = []        # [{image, name_edit, check}]


func _ready() -> void:
	setup("Import atlas: " + path.get_file(), Vector2(1150, 700))
	_img = SaveManager.load_picture(path)
	if _img == null:
		body.add_child(UiKit.para("Couldn't open that picture.", 20, ThemeBuilder.DANGER))
		return
	var top := UiKit.hbox(8)
	_set_name = UiKit.line_edit("Tile set name", path.get_file().get_basename().replace("_", " ").capitalize())
	top.add_child(UiKit.field_row("Set name", _set_name, 110))
	_size = UiKit.option(["16 px", "32 px", "64 px"], 1)
	_size.item_selected.connect(func(_i): _slice())
	top.add_child(UiKit.field_row("Tile size", _size, 100))
	_margin = _spin(0, 64, 0)
	_margin.value_changed.connect(func(_x): _slice())
	top.add_child(UiKit.field_row("Margin", _margin, 80))
	_spacing = _spin(0, 64, 0)
	_spacing.value_changed.connect(func(_x): _slice())
	top.add_child(UiKit.field_row("Spacing", _spacing, 90))
	body.add_child(top)
	body.add_child(UiKit.para("%d × %d picture. Empty cells are skipped. Untick any cell you don't want; names can be changed later." % [_img.get_width(), _img.get_height()], 18, ThemeBuilder.MUTED))
	_grid = HFlowContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	body.add_child(UiKit.scroll(_grid))
	var row := UiKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UiKit.button("Create tile set", _create, 200))
	body.add_child(row)
	_slice()


func _spin(lo: int, hi: int, v: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = v
	s.custom_minimum_size = Vector2(90, 44)
	return s


func _slice() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_cells.clear()
	var n: int = [16, 32, 64][_size.selected]
	var cells := Tilesets.slice_atlas(_img, n, int(_margin.value), int(_spacing.value))
	for c in cells.slice(0, 256):
		var box := UiKit.vbox(2)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(64, 64)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.texture = ImageTexture.create_from_image(c.image)
		box.add_child(pic)
		var name_edit := UiKit.line_edit("", "tile %d %d" % [c.y, c.x])
		name_edit.custom_minimum_size = Vector2(110, 40)
		name_edit.size_flags_horizontal = Control.SIZE_FILL
		box.add_child(name_edit)
		var cb := CheckBox.new()
		cb.text = "use"
		cb.button_pressed = true
		box.add_child(cb)
		_grid.add_child(box)
		_cells.append({"image": c.image, "name": name_edit, "check": cb})
	if cells.size() > 256:
		_grid.add_child(UiKit.para("(showing the first 256 cells)", 16, ThemeBuilder.MUTED))
	if cells.is_empty():
		_grid.add_child(UiKit.para("No tiles found at this size. Try another tile size, margin or spacing.", 18, ThemeBuilder.DANGER))


func _create() -> void:
	var n: int = [16, 32, 64][_size.selected]
	var s := Tilesets.create(_set_name.text, n, library)
	var made := 0
	for c in _cells:
		if c.check.button_pressed:
			Tilesets.add_tile(s, c.name.text, c.image, {}, library)
			made += 1
	GameState.notify("Made \"%s\" with %d tiles ✓" % [s.name, made])
	done.emit(str(s.id))
	close()
