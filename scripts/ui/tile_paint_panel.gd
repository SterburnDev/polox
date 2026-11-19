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
	right.add_child(UiKit.label("Quick texture patterns", 16, ThemeBuilder.MUTED))
	var presets_row := UiKit.flow_row(6)
	for preset in [["aero_tile", "Aero"], ["dream_brick", "Brick"], ["checkered", "Check"], ["floor", "Wood"]]:
		var preset_id := str(preset[0])
		presets_row.add_child(UiKit.button(str(preset[1]), func(): _apply_texture_preset(preset_id), 0))
	right.add_child(presets_row)
	var wrap_btn := UiKit.button("Offset wrap (check seams)", _offset_wrap, 0)
	wrap_btn.name = "OffsetWrap"
	right.add_child(wrap_btn)
	right.add_child(UiKit.spacer(true))
	right.add_child(UiKit.button("Save tile", _save, 0))
	_refresh_preview()


## Fills the tile canvas with a crisp procedural texture preset tinted with the active brush colour.
func _apply_texture_preset(kind: String) -> void:
	var SurfaceDetail := preload("res://scripts/world/surface_detail.gd")
	var base_tex: Texture2D = SurfaceDetail.texture(kind)
	if base_tex == null:
		return
	var img := base_tex.get_image()
	if img == null or img.is_empty():
		return
	var current_img: Image = canvas.image
	var target_size: int = current_img.get_width() if current_img else 32
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != target_size or img.get_height() != target_size:
		img.resize(target_size, target_size, Image.INTERPOLATE_NEAREST)
	var brush_col: Color = canvas.color if canvas.get("color") is Color else Color("#7fdcf0")
	var tint: Color = brush_col if brush_col.a > 0.1 else Color("#7fdcf0")
	for y in target_size:
		for x in target_size:
			var g := img.get_pixel(x, y).r
			img.set_pixel(x, y, Color(tint.r * g, tint.g * g, tint.b * g, 1.0))
	canvas.import_image(img)


## Rolls the tile image by half its width & height so artists can paint directly over tile seams.
func _offset_wrap() -> void:
	var src: Image = canvas.image
	if src == null or src.is_empty():
		return
	var w := src.get_width()
	var h := src.get_height()
	var hx := w / 2
	var hy := h / 2
	var wrapped := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			wrapped.set_pixel((x + hx) % w, (y + hy) % h, src.get_pixel(x, y))
	canvas.import_image(wrapped)


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
