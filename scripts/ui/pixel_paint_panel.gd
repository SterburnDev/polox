extends "res://scripts/ui/screen_panel.gd"
## Draw (or import) a small picture with the Creator's pixel canvas: item
## icons and world sprites. "Use it" hands the picture back.
## Tags: [DRAWING]

signal done(img: Image)

const PaintCanvas := preload("res://scripts/ui/paint_canvas.gd")
const CreatorTools := preload("res://scripts/ui/creator_tools.gd")
const SIZES: Array[int] = [16, 32, 64]

var title_text := "Draw"
var start: Image = null
var onion_image: Image = null      # animation: the previous frame shows faintly underneath
var canvas: Control
var _preview: TextureRect


func _ready() -> void:
	setup(title_text, Vector2(1060, 660))
	# A phone held upright: the canvas on top, full width; the tools under it (they scroll, the canvas stays).
	var upright := UiKit.upright_phone()
	var row: BoxContainer = UiKit.columns(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	canvas = PaintCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(340, 340)
	canvas.set_image(_square(start))
	if onion_image:
		canvas.onion = ImageTexture.create_from_image(onion_image)
	canvas.changed.connect(_refresh)
	row.add_child(canvas)
	var rest: Container = row
	if upright:
		canvas.custom_minimum_size = Vector2(0, 360)
		var under := UiKit.vbox(10)
		var page := UiKit.page(under)
		page.custom_minimum_size.y = 220
		row.add_child(page)
		rest = under
	var tools := CreatorTools.new()
	rest.add_child(tools)
	tools.bind(canvas)
	var right := UiKit.vbox(10)
	right.custom_minimum_size.x = 0 if upright else 240
	rest.add_child(right)
	right.add_child(UiKit.label("Preview", 18, ThemeBuilder.MUTED))
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(128, 128)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_preview)
	var sizes := UiKit.option(SIZES.map(func(n): return "%dx%d" % [n, n]), maxi(0, SIZES.find(canvas.grid_size())))
	sizes.item_selected.connect(func(i): canvas.resize_grid(SIZES[i]))
	right.add_child(UiKit.field_row("Size", sizes, 60))
	right.add_child(UiKit.button("Import a picture", func(): UiKit.pick_picture(self, "Pick a picture", import_file), 0))
	right.add_child(UiKit.spacer(true))
	right.add_child(UiKit.button("Use it", func(): finish(), 0))
	_refresh()


## Any picture becomes a square canvas the paint tools understand.
func _square(img: Image) -> Image:
	if img == null or img.is_empty():
		var b := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		b.fill(Color(0, 0, 0, 0))
		return b
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var n := 16
	for s in SIZES:
		if maxi(src.get_width(), src.get_height()) >= s:
			n = s
	var out := Image.create(n, n, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var scale := float(n) / maxi(src.get_width(), src.get_height())
	src.resize(maxi(1, int(src.get_width() * scale)), maxi(1, int(src.get_height() * scale)), Image.INTERPOLATE_NEAREST)
	out.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), (Vector2i(n, n) - src.get_size()) / 2)
	return out


func import_file(path: String) -> bool:
	var img: Image = SaveManager.load_picture(path)
	if img == null:
		GameState.notify("Couldn't open that picture. Try a PNG or JPG under 40 MB.")
		return false
	canvas.import_image(img)
	return true


func _refresh() -> void:
	_preview.texture = ImageTexture.create_from_image(canvas.image)


func finish() -> void:
	done.emit(canvas.image.duplicate())
	close()
