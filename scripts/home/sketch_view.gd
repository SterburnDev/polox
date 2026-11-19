extends Control
## A top-down sketch of your home's floor plan (layout_builder.gd's floors): rooms with their names,
## walls, doors (gaps with a swing), windows (thin double lines), stairs, the furniture as soft shapes,
## and a star on your room. `reveal` (0 to 1) draws it in room by room, for the Survey's build and
## the first look at your home. `style`: "night" (white lines on black, the Survey) or "paper"
## (ink on cream, the Map my home panel).

signal room_picked(level: int, room_index: int)
signal room_long_pressed(level: int, room_index: int)

const Furniture := preload("res://scripts/world/furniture.gd")

var plan: Dictionary = {}
var level := 0                 # which floor is shown
var reveal := 1.0
var style := "night"
var selected := -1             # a room index (the editor)
var show_furniture := true
var _scale := 24.0
var _origin := Vector2.ZERO
var zoom := 1.0                # pinch (phones) or the wheel
var pan := Vector2.ZERO
var _touches := {}             # index -> position
var _pinch_ref := 0.0
var _press_at := Vector2.ZERO
var _press_t := -1.0
var _long_sent := false
const LONG_S := 0.5


func set_plan(p: Dictionary, lvl: int = -99) -> void:
	plan = p
	if lvl != -99:
		level = lvl
	elif not floors().is_empty():
		level = int(plan.get("mine_level", int(floors()[0].level)))
	queue_redraw()


func floors() -> Array:
	return plan.get("floors", []) if plan.get("floors") is Array else []


func current() -> Dictionary:
	for f in floors():
		if int(f.level) == level:
			return f
	return floors()[0] if not floors().is_empty() else {}


func _colors() -> Dictionary:
	if style == "paper":
		return {"bg": Color("#f4ecd8"), "ink": Color("#3a3226"), "soft": Color("#3a3226", 0.18), "fill": Color("#e9dcc0"), "mine": Color("#d9534f"), "label": Color("#3a3226")}
	return {"bg": Color(0, 0, 0, 0), "ink": Color("#f4f0e8"), "soft": Color("#f4f0e8", 0.22), "fill": Color("#f4f0e8", 0.06), "mine": Color("#ff4060"), "label": Color("#f4f0e8", 0.85)}


func _layout(f: Dictionary) -> void:
	var w := float(f.get("w", 10))
	var d := float(f.get("d", 8))
	_scale = minf((size.x - 24.0) / maxf(1.0, w), (size.y - 24.0) / maxf(1.0, d))
	_scale = clampf(_scale, 6.0, 64.0) * zoom
	_origin = (size - Vector2(w, d) * _scale) / 2.0 + pan


func cell_to_px(x: float, z: float) -> Vector2:
	return _origin + Vector2(x, z) * _scale


func px_to_cell(p: Vector2) -> Vector2:
	return (p - _origin) / _scale


func _draw() -> void:
	var c := _colors()
	if c.bg.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), c.bg)
	var f := current()
	if f.is_empty():
		return
	_layout(f)
	var rooms: Array = f.get("rooms", [])
	var n := rooms.size()
	var shown := clampi(int(ceil(reveal * n)), 0, n)
	var font := ThemeDB.fallback_font
	var fs := int(clampf(_scale * 0.42, 10, 18))
	for i in shown:
		var r: Array = rooms[i].rect
		var rect := Rect2(cell_to_px(float(r[0]), float(r[1])), Vector2(float(r[2]), float(r[3])) * _scale)
		var fade := clampf(reveal * n - i, 0.0, 1.0)
		var fill: Color = c.fill
		if i == selected:
			fill = Color(c.mine, 0.18)
		draw_rect(rect, Color(fill, fill.a * fade))
		if show_furniture:
			for p in f.get("furniture", []):
				if int(p.get("room", -1)) == i:
					var fp: Rect2i = Furniture.footprint({"model": str(p.model), "pos": [int(p.x), 0, int(p.z)], "rot": int(p.rot)})
					var pr := Rect2(cell_to_px(fp.position.x + 0.12, fp.position.y + 0.12), (Vector2(fp.size) - Vector2(0.24, 0.24)) * _scale)
					draw_rect(pr, Color(c.soft, c.soft.a * fade))
		var label := str(rooms[i].get("name", ""))
		if bool(rooms[i].get("mine", false)):
			label = "★ " + label
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw >= rect.size.x - 6 and label.contains(" ") and not bool(rooms[i].get("mine", false)):
			# A long name in a narrow room: its first word still says which room it is ("Children's").
			label = label.get_slice(" ", 0)
			tw = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw < rect.size.x - 6 and rect.size.y > fs * 1.6:
			draw_string(font, rect.get_center() + Vector2(-tw / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(c.mine if bool(rooms[i].get("mine", false)) else c.label, fade))
	# Walls (only around rooms already drawn in), doors and windows.
	var th := maxf(2.0, _scale * 0.12)
	for e in f.get("edges", []):
		var a := int(e.get("a", -1))
		var b := int(e.get("b", -1))
		if (a >= shown or a < 0) and (b >= shown or b < 0):
			continue
		var p0: Vector2
		var p1: Vector2
		if str(e.dir) == "h":
			p0 = cell_to_px(float(e.x), float(e.z))
			p1 = cell_to_px(float(e.x) + 1.0, float(e.z))
		else:
			p0 = cell_to_px(float(e.x), float(e.z))
			p1 = cell_to_px(float(e.x), float(e.z) + 1.0)
		var ink: Color = c.ink
		if bool(e.get("door", false)):
			var along := (p1 - p0)
			var normal := Vector2(-along.y, along.x).normalized()
			draw_line(p0, p0 + normal * along.length() * 0.9, Color(ink, 0.5), 1.5)
			draw_arc(p0, along.length() * 0.9, along.angle(), (normal).angle(), 8, Color(ink, 0.4), 1.0)
			if bool(e.get("front", false)):
				draw_line(p0, p1, Color(c.mine, 0.9), th * 0.6)
			continue
		draw_line(p0, p1, ink, th * (1.3 if bool(e.get("outer", false)) else 0.8))
		if bool(e.get("window", false)):
			var nrm := Vector2(-(p1 - p0).y, (p1 - p0).x).normalized() * th * 0.9
			draw_line(p0.lerp(p1, 0.2) + nrm, p0.lerp(p1, 0.8) + nrm, Color(c.bg if c.bg.a > 0.0 else Color.BLACK), th * 0.5)
			draw_line(p0.lerp(p1, 0.2) - nrm * 0.0, p0.lerp(p1, 0.8), Color("#8ec8f0"), th * 0.45)
	var st: Array = f.get("stairs", [])
	if st.size() >= 2 and reveal >= 0.99:
		for i in 6:
			var x := float(st[0]) + i * 0.5
			draw_line(cell_to_px(x, float(st[1]) + 0.1), cell_to_px(x, float(st[1]) + 0.9), Color(c.ink, 0.6), 1.5)


func _process(_delta: float) -> void:
	# A long press on a room: its options (rename, paint, floor, swap).
	if _press_t >= 0.0 and not _long_sent and _touches.size() <= 1 and Time.get_ticks_msec() / 1000.0 - _press_t >= LONG_S:
		_long_sent = true
		var i := _room_at(_press_at)
		if i >= 0:
			selected = i
			queue_redraw()
			room_long_pressed.emit(level, i)


func _room_at(p: Vector2) -> int:
	var f := current()
	var cell := px_to_cell(p)
	for i in (f.get("rooms", []) as Array).size():
		var r: Array = f.rooms[i].rect
		if Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).has_point(cell):
			return i
	return -1


func set_zoom(z: float) -> void:
	zoom = clampf(z, 0.6, 3.5)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Two fingers: pinch to zoom, move together to pan (and never a long press).
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			_press_at = event.position
			_press_t = Time.get_ticks_msec() / 1000.0
			_long_sent = false
			preload("res://scripts/ui/touch_gestures.gd").claimed = true
			if _touches.size() == 2:
				_press_t = -1.0
				var p: Array = _touches.values()
				_pinch_ref = (p[0] as Vector2).distance_to(p[1])
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				_press_t = -1.0
				preload("res://scripts/ui/touch_gestures.gd").claimed = false
	elif event is InputEventScreenDrag and _touches.has(event.index):
		if (event.position - _press_at).length() > 12.0:
			_press_t = -1.0
		_touches[event.index] = event.position
		if _touches.size() == 2:
			var q: Array = _touches.values()
			var spread := (q[0] as Vector2).distance_to(q[1])
			if _pinch_ref > 0.0:
				set_zoom(zoom * spread / _pinch_ref)
			_pinch_ref = spread
			pan += event.relative / 2.0
			queue_redraw()
			accept_event()
			return
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		set_zoom(zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12))
		accept_event()
		return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_at = event.position
			_press_t = Time.get_ticks_msec() / 1000.0
			_long_sent = false
		else:
			_press_t = -1.0
	var pressed: bool = (preload("res://scripts/ui/ui_kit.gd").tap_down(event) and not event is InputEventScreenTouch) or (event is InputEventScreenTouch and event.pressed and _touches.size() == 1)
	if not pressed:
		return
	var f := current()
	var cell := px_to_cell(event.position)
	for i in (f.get("rooms", []) as Array).size():
		var r: Array = f.rooms[i].rect
		if Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).has_point(cell):
			selected = i
			room_picked.emit(level, i)
			queue_redraw()
			accept_event()
			return
