extends "res://scripts/ui/screen_panel.gd"
## Draw a tile with the pixel canvas from the Character Creator, with a
## seamless preview (the tile repeated 3x3) so patterns line up. Saves as a
## new tile, replaces an existing one, or adds an animation frame.

signal saved

const Tilesets := preload("res://scripts/world/tilesets.gd")
const PaintCanvas := preload("res://scripts/ui/paint_canvas.gd")
const CreatorTools := preload("res://scripts/ui/creator_tools.gd")

var set_id := ""
var tile_id := ""           # "" = a new tile
var frame := 0              # > 0 = that animation frame
var library := false
var canvas: Control
var _preview: Control
var _name: LineEdit
var _solid: CheckBox
var _tex: ImageTexture


func _ready() -> void:
	var s := Tilesets.load_set(set_id, library)
	var n := int(s.get("tile_size", 32))
	setup(("New tile for " + str(s.name)) if tile_id == "" else ("Draw: " + tile_id + (" (frame %d)" % (frame + 1) if frame > 0 else "")), Vector2(1100, 680))
	var row := UiKit.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	canvas = PaintCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if tile_id != "":
		var t := Tilesets.find_tile(s, tile_id)
		var rel := str(t.get("image", "")) if frame == 0 else str(t.get("frames", [])[frame - 1]) if frame - 1 < t.get("frames", []).size() else str(t.get("image", ""))
		var existing := Image.load_from_file(Tilesets.set_dir(set_id, library).path_join(rel))
		if existing:
			existing.convert(Image.FORMAT_RGBA8)
			img = existing
	canvas.set_image(img)
	canvas.changed.connect(_refresh_preview)
	row.add_child(canvas)
	var tools := CreatorTools.new()
	row.add_child(tools)
	tools.bind(canvas)
	var right := UiKit.vbox(8)
	right.custom_minimum_size.x = 300
	row.add_child(right)
	right.add_child(UiKit.label("Seamless preview (3 × 3)", 18, ThemeBuilder.MUTED))
	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(288, 288)
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.draw.connect(_draw_preview)
	right.add_child(_preview)
	_name = UiKit.line_edit("Tile name", tile_id.capitalize() if tile_id != "" else "")
	_name.editable = tile_id == ""
	right.add_child(UiKit.field_row("Name", _name, 70))
	_solid = CheckBox.new()
	_solid.text = "Solid"
	_solid.visible = tile_id == ""
	right.add_child(_solid)
	right.add_child(UiKit.button("Import picture", func(): UiKit.pick_picture(self, "Pick a picture", func(path):
		var pic: Image = SaveManager.load_picture(path)
		if pic:
			canvas.import_image(pic)), 0))
	right.add_child(UiKit.spacer(true))
	right.add_child(UiKit.button("Save tile", _save, 0))
	_refresh_preview()


func _refresh_preview() -> void:
	_tex = ImageTexture.create_from_image(canvas.image)
	_preview.queue_redraw()


func _draw_preview() -> void:
	if _tex == null:
		return
	var cell := _preview.size / 3.0
	for y in 3:
		for x in 3:
			_preview.draw_texture_rect(_tex, Rect2(Vector2(x, y) * cell, cell), false)
	_preview.draw_rect(Rect2(cell, cell), ThemeBuilder.YELLOW, false, 2.0)


func _save() -> void:
	var s := Tilesets.load_set(set_id, library)
	if tile_id == "":
		if canvas.image.is_invisible():
			GameState.notify("Draw something first.")
			return
		Tilesets.add_tile(s, _name.text, canvas.image, {"solid": _solid.button_pressed}, library)
	else:
		Tilesets.set_tile_image(s, tile_id, canvas.image, frame, library)
	GameState.notify("Tile saved ✓")
	saved.emit()
	close()
