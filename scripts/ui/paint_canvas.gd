extends Control
## A pixel-art canvas: pencil, eraser, flood fill and color picker, brush
## sizes 1-4, horizontal mirror, and 100 steps of undo/redo. One mouse
## stroke = one undo step. Drawn scaled-up with crisp nearest filtering.
## Zoom: the bar in the corner (−, the zoom, +, Fit, ✋ Pan), the mouse wheel or a trackpad pinch
## (towards the pointer), +/− and 0 on the keyboard, two fingers on a touch screen (pinch to zoom,
## drag to move). Moving the view never draws: the middle button, Space + drag, ✋ Pan or two fingers
## move it, and a stroke a second finger interrupts is taken back. The picture keeps its size in
## pixels; strokes land under the pointer at every zoom.
## Tags: [DRAWING]

signal changed
signal color_picked(color: Color)

const MAX_UNDO := 100

var image: Image
var tool := "pencil"          # pencil | eraser | fill | picker
var color := Color("#22183d")
var brush := 1
var mirror := false
var show_grid := true
var onion: Texture2D               # the previous animation frame, faint, under the picture
var _tex: ImageTexture
var _undo: Array[Image] = []
var _redo: Array[Image] = []
var _painting := false
var _last_px := Vector2i(-1, -1)
var _checker: ImageTexture

const MAX_ZOOM := 12.0          # times the fitted size
const MIN_ZOOM := 0.5
var zoom := 1.0                 # 1 = the whole picture fits
var pan := Vector2.ZERO         # how far the picture is moved from the centre (px)
var pan_tool := false           # ✋ Pan: one finger or the left button moves the view
var _panning := false
var _space := false
var _touches: Dictionary = {}   # touch index -> position
var _gesture := false           # two fingers down: zoom/move only, until every finger lifts
var _pinch_from := 0.0
var _zoom_from := 1.0
var _mid_from := Vector2.ZERO
var _pan_from := Vector2.ZERO
var _zoom_label: Label
var _pan_btn: Button
var _gesture_seen := false      # this touch (first finger down to last up) became a pinch
var _tap_px := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	custom_minimum_size = Vector2(320, 320)
	_zoom_bar()
	var c := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	c.set_pixel(0, 0, Color("#3a3352"))
	c.set_pixel(1, 1, Color("#3a3352"))
	c.set_pixel(1, 0, Color("#2b2540"))
	c.set_pixel(0, 1, Color("#2b2540"))
	_checker = ImageTexture.create_from_image(c)
	if image == null:
		set_image(_blank(32))


static func _blank(n: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


## Replaces the picture (e.g. switching expression slot). Clears history.
func set_image(img: Image) -> void:
	image = img
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(image)
	_undo.clear()
	_redo.clear()
	queue_redraw()


func grid_size() -> int:
	return image.get_width()


func _fit_cell() -> float:
	return floorf(minf(size.x, size.y) / grid_size() * 100.0) / 100.0


func _cell() -> float:
	return _fit_cell() * zoom


func _origin() -> Vector2:
	var side := _cell() * grid_size()
	return ((size - Vector2(side, side)) / 2.0 + pan).floor()


## The zoom bar: glass, in the top-right corner, finger-sized.
func _zoom_bar() -> void:
	var UiKit := preload("res://scripts/ui/ui_kit.gd")
	var ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
	var bar := PanelContainer.new()
	bar.name = "ZoomBar"
	bar.add_theme_stylebox_override("panel", ThemeBuilder.bar(ThemeBuilder.RADIUS_M, 4))
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.offset_left = -8
	bar.offset_right = -8
	bar.offset_top = 8
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	bar.add_child(h)
	var specs := [["ZoomOut", "−", "Zoom out (wheel down, −)", func(): zoom_by(1.0 / 1.25)],
		["ZoomIn", "+", "Zoom in (wheel up, +)", func(): zoom_by(1.25)],
		["Fit", "Fit", "Fit the canvas (0)", fit]]
	for i in specs.size():
		var spec: Array = specs[i]
		var b: Button = UiKit.button(str(spec[1]), spec[3], 44)
		b.name = str(spec[0])
		b.tooltip_text = str(spec[2])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 44
		h.add_child(b)
		if i == 0:
			_zoom_label = UiKit.label("", 16)
			_zoom_label.name = "ZoomLevel"
			_zoom_label.custom_minimum_size.x = 64
			_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.add_child(_zoom_label)
	_pan_btn = UiKit.button("✋", func():
		pan_tool = not pan_tool
		_pan_btn.set_pressed_no_signal(pan_tool), 44)
	_pan_btn.name = "PanTool"
	_pan_btn.toggle_mode = true
	_pan_btn.focus_mode = Control.FOCUS_NONE
	_pan_btn.custom_minimum_size.y = 44
	_pan_btn.tooltip_text = "Move the view without drawing (or hold Space, or the middle button)"
	h.add_child(_pan_btn)
	resized.connect(_clamp_pan)


## Zoom by `factor`, keeping the point under `at` (default: the middle) where it is.
func zoom_by(factor: float, at: Variant = null) -> void:
	var anchor: Vector2 = at if at is Vector2 else size / 2.0
	var before := (anchor - _origin()) / maxf(_cell(), 0.0001)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var side := _cell() * grid_size()
	# The pan that puts the same picture point back under the anchor.
	pan = anchor - before * _cell() - (size - Vector2(side, side)) / 2.0
	_clamp_pan()


func fit() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	_clamp_pan()


## Keeps some of the picture on screen however far it's moved.
func _clamp_pan() -> void:
	var side := _cell() * grid_size()
	var keep := minf(48.0, side / 2.0)
	var lim := ((size + Vector2(side, side)) / 2.0 - Vector2(keep, keep)).max(Vector2.ZERO)
	pan = pan.clamp(-lim, lim)
	if _zoom_label:
		_zoom_label.text = "%d%%" % zoom_percent()
		_zoom_label.visible = size.x >= 330.0   # (a narrow canvas: the buttons fit without it)
	queue_redraw()


## The zoom as screen pixels per picture pixel (×100): "1200%" draws each pixel 12 px wide.
func zoom_percent() -> int:
	return roundi(_cell() * 100.0)


func _draw() -> void:
	var cell := _cell()
	var n := grid_size()
	var o := _origin()
	var rect := Rect2(o, Vector2(cell * n, cell * n))
	draw_texture_rect(_checker, rect, true, Color.WHITE)
	if onion:
		draw_texture_rect(onion, rect, false, Color(1, 1, 1, 0.3))
	draw_texture_rect(_tex, rect, false)
	if show_grid and cell >= 6.0:
		var line := Color(1, 1, 1, 0.07)
		for i in range(1, n):
			draw_line(o + Vector2(i * cell, 0), o + Vector2(i * cell, n * cell), line)
			draw_line(o + Vector2(0, i * cell), o + Vector2(n * cell, i * cell), line)
	if mirror:
		draw_line(o + Vector2(n * cell / 2.0, 0), o + Vector2(n * cell / 2.0, n * cell), Color(1, 0.82, 0.4, 0.5), 2.0)
	draw_rect(rect, Color(0.95, 0.91, 0.82, 0.6), false, 2.0)


func _to_pixel(pos: Vector2) -> Vector2i:
	var p := (pos - _origin()) / _cell()
	return Vector2i(floori(p.x), floori(p.y))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch(event)
		accept_event()
		return
	if _gesture:
		accept_event()   # (the touch screen's mouse copy of a two-finger gesture)
		return
	if event is InputEventMagnifyGesture:
		zoom_by(event.factor, event.position)
		accept_event()
		return
	if event is InputEventPanGesture:
		pan -= event.delta * 12.0
		_clamp_pan()
		accept_event()
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15, event.position)
			accept_event()
			return
		var move_view: bool = event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and (pan_tool or _space))
		if move_view or (_panning and not event.pressed):
			_panning = event.pressed
			accept_event()
			return
	if event is InputEventMouseMotion and _panning:
		pan += event.relative
		_clamp_pan()
		accept_event()
		return
	if event is InputEventKey:
		if event.keycode == KEY_SPACE:
			_space = event.pressed
			if not event.pressed:
				_panning = false
			accept_event()
			return
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
					zoom_by(1.25)
				KEY_MINUS, KEY_KP_SUBTRACT:
					zoom_by(1.0 / 1.25)
				KEY_0, KEY_KP_0:
					fit()
				_:
					return
			accept_event()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# A finger's fill or colour pick waits for the finger to lift: if it turns into a pinch, nothing happens.
		var finger: bool = event.device == InputEvent.DEVICE_ID_EMULATION
		if finger and tool in ["fill", "picker"]:
			if event.pressed:
				_tap_px = _to_pixel(event.position)
			elif not _gesture_seen and _tap_px.x >= 0:
				_begin_stroke(_tap_px)
				_tap_px = Vector2i(-1, -1)
		elif event.pressed:
			_begin_stroke(_to_pixel(event.position))
		else:
			_painting = false
		accept_event()
	elif event is InputEventMouseMotion and _painting:
		var px := _to_pixel(event.position)
		_line_to(px)
		accept_event()


## Fingers: one draws (or moves the view with ✋ Pan); two pinch and move it. A stroke the first finger
## began is taken back the moment a second finger lands, so a pinch never leaves a mark.
func _touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touches.is_empty():
				_gesture_seen = false   # a new touch: nothing pinched yet
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() >= 2 and not _gesture:
			_gesture = true
			_gesture_seen = true
			_cancel_stroke()
			_start_pinch()
		elif _gesture and _touches.size() >= 2:
			_start_pinch()   # a third finger, or one lifted of three: carry on from here
		if _touches.is_empty():
			_gesture = false   # every finger is up: drawing works again
			_panning = false
		elif pan_tool and _touches.size() == 1 and event.pressed:
			_panning = true
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index] = event.position
		if _gesture and _touches.size() >= 2:
			var pts: Array = _touches.values().slice(0, 2)
			var mid: Vector2 = (pts[0] + pts[1]) / 2.0
			var dist: float = maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
			zoom = _zoom_from
			pan = _pan_from
			zoom_by(dist / _pinch_from, _mid_from)
			pan += mid - _mid_from
			_clamp_pan()
		elif pan_tool and _panning:
			pan += event.relative
			_clamp_pan()


func _start_pinch() -> void:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return
	_mid_from = (pts[0] + pts[1]) / 2.0
	_pinch_from = maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
	_zoom_from = zoom
	_pan_from = pan


## Takes back the stroke in progress (a second finger landed): the picture as it was before it.
func _cancel_stroke() -> void:
	if _painting and not _undo.is_empty():
		var before: Image = _undo.pop_back()
		image.copy_from(before)
		_commit()
	_painting = false


func _begin_stroke(px: Vector2i) -> void:
	if not _in(px):
		return
	match tool:
		"picker":
			var c := image.get_pixelv(px)
			if c.a > 0.01:
				color = Color(c, 1.0)
				color_picked.emit(color)
			return
		"fill":
			_push_undo()
			flood_fill(px, color)
			if mirror:
				flood_fill(_mirror(px), color)
			_commit()
			return
	_push_undo()
	_painting = true
	_last_px = px
	_stamp(px)
	_commit()


## Bresenham line from the last sample, so fast strokes have no gaps.
func _line_to(px: Vector2i) -> void:
	var a := _last_px
	var dx := absi(px.x - a.x)
	var dy := -absi(px.y - a.y)
	var sx := 1 if a.x < px.x else -1
	var sy := 1 if a.y < px.y else -1
	var err := dx + dy
	while true:
		_stamp(a)
		if a == px:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			a.x += sx
		if e2 <= dx:
			err += dx
			a.y += sy
	_last_px = px
	_commit()


func _stamp(px: Vector2i) -> void:
	var c := Color(0, 0, 0, 0) if tool == "eraser" else color
	var r0 := -floori((brush - 1) / 2.0)
	for dy in range(r0, r0 + brush):
		for dx in range(r0, r0 + brush):
			_set_px(px + Vector2i(dx, dy), c)
			if mirror:
				_set_px(_mirror(px + Vector2i(dx, dy)), c)


func _mirror(px: Vector2i) -> Vector2i:
	return Vector2i(grid_size() - 1 - px.x, px.y)


func _in(px: Vector2i) -> bool:
	return px.x >= 0 and px.y >= 0 and px.x < grid_size() and px.y < grid_size()


func _set_px(px: Vector2i, c: Color) -> void:
	if _in(px):
		image.set_pixelv(px, c)


## 4-way flood fill of the exact color under `start`. Each pixel is filled at most once: a color the
## picture keeps as the same 8 bits as the one it replaces (0.2015 is stored as 0.2) refilled forever.
func flood_fill(start: Vector2i, c: Color) -> void:
	if not _in(start):
		return
	var target := image.get_pixelv(start)
	if target.is_equal_approx(c):
		return
	var n := grid_size()
	var filled := PackedByteArray()
	filled.resize(n * n)
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if not _in(p) or filled[p.y * n + p.x] == 1 or not image.get_pixelv(p).is_equal_approx(target):
			continue
		filled[p.y * n + p.x] = 1
		image.set_pixelv(p, c)
		stack.append(p + Vector2i.RIGHT)
		stack.append(p + Vector2i.LEFT)
		stack.append(p + Vector2i.DOWN)
		stack.append(p + Vector2i.UP)


func _commit() -> void:
	_tex.update(image)
	queue_redraw()
	changed.emit()


func _push_undo() -> void:
	_undo.append(image.duplicate() as Image)
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(image.duplicate() as Image)
	_swap_in(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(image.duplicate() as Image)
	_swap_in(_redo.pop_back())


func _swap_in(img: Image) -> void:
	if img.get_size() != image.get_size():
		image = img
		_tex = ImageTexture.create_from_image(image)
	else:
		image.copy_from(img)
	_commit()


## Per-slot history: the Creator stashes it when switching expressions.
func get_history() -> Array:
	return [_undo.duplicate(), _redo.duplicate()]


func set_history(h: Array) -> void:
	_undo.clear()
	_redo.clear()
	if h.size() == 2:
		_undo.append_array(h[0])
		_redo.append_array(h[1])


## Replaces the drawing with `img` (same grid), as one undoable step.
func paste_image(img: Image) -> void:
	_push_undo()
	var copy := img.duplicate() as Image
	copy.convert(Image.FORMAT_RGBA8)
	if copy.get_size() != image.get_size():
		copy.resize(grid_size(), grid_size(), Image.INTERPOLATE_NEAREST)
	image.copy_from(copy)
	_commit()


func clear_all() -> void:
	_push_undo()
	image.fill(Color(0, 0, 0, 0))
	_commit()


## Resizes the drawing to a new grid (crisp nearest-neighbour). Undoable.
func resize_grid(n: int) -> void:
	if n == grid_size():
		return
	_push_undo()
	var img := image.duplicate() as Image
	img.resize(n, n, Image.INTERPOLATE_NEAREST)
	image = img
	_tex = ImageTexture.create_from_image(image)
	_commit()


## Brings in any picture as pixel art at the current grid size. Undoable.
func import_image(src: Image) -> void:
	_push_undo()
	var n := grid_size()
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var big := maxi(img.get_width(), img.get_height())
	# Pad to a square first so nothing gets stretched.
	var square := Image.create(big, big, false, Image.FORMAT_RGBA8)
	square.fill(Color(0, 0, 0, 0))
	square.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(floori((big - img.get_width()) / 2.0), floori((big - img.get_height()) / 2.0)))
	square.resize(n, n, Image.INTERPOLATE_NEAREST if big <= n * 2 else Image.INTERPOLATE_LANCZOS)
	image.copy_from(square)
	_commit()
