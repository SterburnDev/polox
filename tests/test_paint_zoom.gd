extends "res://tests/test_case.gd"
## Drawing pages zoom (paint_canvas.gd): the zoom bar, wheel and pinch zoom towards the pointer, strokes
## land under the pointer at every zoom, and moving the view (Pan, two fingers) never draws.
## Tags: [DRAWING]

const PaintCanvas := preload("res://scripts/ui/paint_canvas.gd")


func _canvas() -> Control:
	var host := Control.new()
	host.size = Vector2(800, 800)
	tree.root.add_child(host)
	var c: Control = PaintCanvas.new()
	host.add_child(c)
	c.position = Vector2.ZERO
	c.size = Vector2(400, 400)
	c.color = Color("#e86a8a")
	return c


## The middle of picture pixel `px`, in the canvas's own coordinates.
func _screen(c: Control, px: Vector2i) -> Vector2:
	return c._origin() + (Vector2(px) + Vector2(0.5, 0.5)) * c._cell()


func _press(c: Control, at: Vector2, down: bool, button := MOUSE_BUTTON_LEFT, device := 0) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	e.device = device
	c._gui_input(e)


func _touch(c: Control, index: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = down
	c._gui_input(e)


func _drag(c: Control, index: int, at: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	e.relative = rel
	c._gui_input(e)


func _painted(c: Control) -> int:
	var n := 0
	for x in c.grid_size():
		for y in c.grid_size():
			if c.image.get_pixel(x, y).a > 0.0:
				n += 1
	return n


func test_zoom_bar_and_percentage() -> void:
	var c := _canvas()
	await frames(2)
	var bar := c.find_child("ZoomBar", true, false)
	check(bar != null, "a zoom bar on the canvas")
	for n in ["ZoomIn", "ZoomOut", "Fit", "ZoomLevel", "PanTool"]:
		check(c.find_child(n, true, false) != null, "zoom bar has " + n)
	var fit_pct: int = c.zoom_percent()
	(c.find_child("ZoomIn", true, false) as Button).pressed.emit()
	check(c.zoom > 1.0 and c.zoom_percent() > fit_pct, "Zoom In zooms in (%d%% -> %d%%)" % [fit_pct, c.zoom_percent()])
	eq((c.find_child("ZoomLevel", true, false) as Label).text, "%d%%" % c.zoom_percent(), "the percentage shows")
	(c.find_child("ZoomOut", true, false) as Button).pressed.emit()
	(c.find_child("ZoomOut", true, false) as Button).pressed.emit()
	check(c.zoom < 1.0, "Zoom Out zooms out")
	(c.find_child("Fit", true, false) as Button).pressed.emit()
	eq(c.zoom, 1.0, "Fit")
	eq(c.pan, Vector2.ZERO, "Fit centres the picture")
	eq(c.grid_size(), 32, "zooming never changes the picture's size")
	c.get_parent().queue_free()


func test_strokes_land_under_the_pointer_at_every_zoom() -> void:
	var c := _canvas()
	await frames(2)
	for z in [1.0, 2.5, 7.0, 0.6]:
		c.fit()
		c.zoom_by(z, Vector2(130, 260))
		var px := Vector2i(9, 21)
		var at := _screen(c, px)
		if at.x < 0 or at.y < 0 or at.x > c.size.x or at.y > c.size.y:
			c.pan += c.size / 2.0 - at   # (bring that pixel on screen first)
			c._clamp_pan()
			at = _screen(c, px)
		eq(c._to_pixel(at), px, "pixel under the pointer at zoom %.1f" % z)
		c.image.fill(Color(0, 0, 0, 0))
		_press(c, at, true)
		_press(c, at, false)
		check(c.image.get_pixelv(px).a > 0.0 and _painted(c) == 1, "a click at zoom %.1f paints exactly that pixel" % z)
	c.get_parent().queue_free()


func test_wheel_zooms_towards_the_pointer() -> void:
	var c := _canvas()
	await frames(2)
	var at := Vector2(300, 90)
	var under: Vector2i = c._to_pixel(at)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	e.position = at
	for i in 6:
		c._gui_input(e)
	check(c.zoom > 2.0, "the wheel zooms in")
	eq(c._to_pixel(at), under, "the pixel under the pointer stays under it")
	eq(_painted(c), 0, "zooming draws nothing")
	c.get_parent().queue_free()


func test_moving_the_view_never_draws() -> void:
	var c := _canvas()
	await frames(2)
	c.zoom_by(3.0)
	var before: Vector2 = c.pan
	# The middle button.
	_press(c, Vector2(200, 200), true, MOUSE_BUTTON_MIDDLE)
	var m := InputEventMouseMotion.new()
	m.position = Vector2(240, 230)
	m.relative = Vector2(40, 30)
	m.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	c._gui_input(m)
	_press(c, Vector2(240, 230), false, MOUSE_BUTTON_MIDDLE)
	check(c.pan != before, "the middle button moves the view")
	# ✋ Pan with the left button.
	(c.find_child("PanTool", true, false) as Button).pressed.emit()
	check(c.pan_tool, "Pan is on")
	before = c.pan
	_press(c, Vector2(200, 200), true)
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.relative = Vector2(-25, 10)
	c._gui_input(m)
	_press(c, Vector2(175, 210), false)
	check(c.pan != before, "Pan moves the view")
	eq(_painted(c), 0, "and draws nothing")
	c.get_parent().queue_free()


func test_a_pinch_takes_back_the_stroke_it_started() -> void:
	var c := _canvas()
	await frames(2)
	var a := Vector2(150, 200)
	# One finger lands: the touch screen sends the touch and a mouse copy of it.
	_touch(c, 0, a, true)
	_press(c, a, true, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	eq(_painted(c), 1, "one finger draws")
	# A second finger: a pinch, so the first finger's mark goes.
	var b := Vector2(250, 200)
	_touch(c, 1, b, true)
	eq(_painted(c), 0, "the stroke is taken back when a second finger lands")
	var zoom0: float = c.zoom
	_drag(c, 0, Vector2(100, 200), Vector2(-50, 0))
	_drag(c, 1, Vector2(300, 200), Vector2(50, 0))
	check(c.zoom > zoom0 * 1.8, "spreading two fingers zooms in (%.2f -> %.2f)" % [zoom0, c.zoom])
	# The mouse copy keeps moving while the fingers pinch: it must not draw.
	var m := InputEventMouseMotion.new()
	m.position = Vector2(110, 210)
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	c._gui_input(m)
	_touch(c, 1, Vector2(300, 200), false)
	_press(c, Vector2(100, 200), false, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	_touch(c, 0, Vector2(100, 200), false)
	eq(_painted(c), 0, "a pinch leaves no mark")
	check(not c.can_undo(), "and no undo step")
	# Afterwards one finger draws again.
	_touch(c, 0, a, true)
	_press(c, a, true, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	_press(c, a, false, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	_touch(c, 0, a, false)
	eq(_painted(c), 1, "drawing works again after the pinch")
	c.get_parent().queue_free()


func test_a_finger_fill_waits_for_the_finger_to_lift() -> void:
	var c := _canvas()
	await frames(2)
	c.tool = "fill"
	var a := Vector2(200, 200)
	_touch(c, 0, a, true)
	_press(c, a, true, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	eq(_painted(c), 0, "nothing yet")
	_touch(c, 1, Vector2(260, 200), true)
	_touch(c, 1, Vector2(260, 200), false)
	_press(c, a, false, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	_touch(c, 0, a, false)
	eq(_painted(c), 0, "a fill that became a pinch does nothing")
	_touch(c, 0, a, true)
	_press(c, a, true, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	_press(c, a, false, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	_touch(c, 0, a, false)
	eq(_painted(c), 32 * 32, "a tap fills")
	c.get_parent().queue_free()
