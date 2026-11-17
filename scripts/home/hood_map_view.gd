extends Control
## The neighbourhood as a soft, hand-drawn map (the World Map's Light World layer once Polox has your
## streets): roads in wobbly pencil, parks and water in watercolour blobs, houses as small soft shapes,
## yours with a star, the public places by name, and the credit "© OpenStreetMap contributors". Tap a spot
## to go there (the block it's in). The credit is the label under it (world_map_view.gd).
## [LIGHT_WORLD_MAP] Pan and zoom: drag to move; the wheel, a trackpad pinch or two fingers to zoom
## (towards the pointer); zoom_by / fit for the − + Fit buttons. A tap (no drag) picks the block on
## release, so moving the map never travels. [PLATFORM] On a phone each tap arrives as a touch and as
## its mouse copy; only the touch is used, so one tap is one pick. Offline: the map is drawn from the
## streets saved when they were mapped (my_home/osm.json); no map service is asked here.
## Tags: [LIGHT_WORLD_MAP]

signal picked(chunk_id: String)

const HoodBuilder := preload("res://scripts/home/hood_builder.gd")

var extract: Dictionary = {}
var here_chunk := ""
var _scale := 1.0
var _center := Vector2.ZERO
const MIN_ZOOM := 1.0
const MAX_ZOOM := 8.0
const TAP_SLOP := 10.0          # px a press may move and still be a tap
## What the World Map says when this map can't show (world_map_view.gd), and its zoom row.
const NOT_MAPPED := "No street map yet: Settings > Light World > Map my home."
const UNREADABLE := "The street map can't be read: Map my home again."
const HINT := "Drag to move"
const ZOOM_TIPS := {"−": "Zoom out", "+": "Zoom in", "Fit": "Fit"}
var zoom := 1.0                 # 1 = the whole neighbourhood fits
var pan := Vector2.ZERO
var _down_at := Vector2.ZERO
var _down := false
var _dragged := false
var _touches: Dictionary = {}   # index -> position
var _pinch_from := 0.0
var _zoom_from := 1.0


## Control clips its children, not its own drawing commands. Keep the paper's drawing inside a
## clipping parent so roads continuing beyond the map cannot paint over nearby buttons.
func clipped_container() -> MarginContainer:
	var frame := MarginContainer.new()
	frame.clip_contents = true
	frame.size_flags_horizontal = size_flags_horizontal
	frame.size_flags_vertical = size_flags_vertical
	frame.add_child(self)
	return frame


func set_extract(e: Dictionary) -> void:
	extract = e
	queue_redraw()


func _metres_to_px(p: Vector2) -> Vector2:
	return _center + p * _scale


func _fit_name(text: String, max_width: float) -> String:
	var font := ThemeDB.fallback_font
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= max_width:
		return text
	while not text.is_empty() and font.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > max_width:
		text = text.left(text.length() - 1)
	return text + "…" if max_width >= font.get_string_size("…", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x else ""


func _px_to_metres(p: Vector2) -> Vector2:
	return (p - _center) / _scale


func _wobble(p: Vector2, seed_i: int) -> Vector2:
	return p + Vector2(sin(seed_i * 1.7 + p.y * 0.05), cos(seed_i * 2.3 + p.x * 0.05)) * 1.6


## A shape's outline, closed and wobbled like a pencil going round it.
func _outline(pts: PackedVector2Array, seed_i: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in pts.size() + 1:
		out.append(_wobble(pts[k % pts.size()], seed_i + 7))
	return out


## Watercolour: a pale wash a little off the line, the colour, and a darker edge where it dried.
func _wash(pts: PackedVector2Array, col: Color, seed_i: int) -> void:
	var off := PackedVector2Array()
	for q in pts:
		off.append(q + Vector2(1.5, 1.2))
	draw_colored_polygon(off, Color(col, col.a * 0.45))
	draw_colored_polygon(pts, col)
	draw_polyline(_outline(pts, seed_i), col.darkened(0.25), 1.4, true)


## The part of the map worth looking at: your home, the buildings and the places with names (roads run
## on past the edge), with a margin; at least 60 m round your home.
func _bounds(feats: Array) -> Rect2:
	var lo := Vector2(-60, -60)
	var hi := Vector2(60, 60)
	for f in feats:
		var k := str(f.get("kind", ""))
		if k in ["road", "path", "barrier", "landuse"]:
			continue
		for q in f.get("pts", []):
			var m := Vector2(float(q[0]), float(q[1]))
			lo = lo.min(m)
			hi = hi.max(m)
	var r := float(extract.get("radius", 250))
	lo = lo.max(Vector2(-r, -r)) - Vector2(25, 25)
	hi = hi.min(Vector2(r, r)) + Vector2(25, 25)
	return Rect2(lo, hi - lo)


func _draw() -> void:
	# Paper: warm, with a little grain and a soft darker edge.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#f4ecd8"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for _g in int(size.x * size.y / 900.0):
		draw_rect(Rect2(Vector2(rng.randf() * size.x, rng.randf() * size.y), Vector2(1.5, 1.5)), Color("#c9b892", 0.18))
	for e in 6:
		draw_rect(Rect2(Vector2(e, e), size - Vector2(e, e) * 2.0), Color("#b9a27a", 0.05), false, 1.0)
	if extract.is_empty():
		return
	var feats: Array = extract.get("features", [])
	# Fit the interesting part, centred on its middle; your home stays on the map.
	var view := _bounds(feats)
	_scale = minf(size.x / maxf(1.0, view.size.x), size.y / maxf(1.0, view.size.y)) * zoom
	_center = size / 2.0 - view.get_center() * _scale + pan
	var i := 0
	for f in feats:
		i += 1
		var kind := str(f.get("kind", ""))
		var pts := PackedVector2Array()
		for q in f.get("pts", []):
			pts.append(_wobble(_metres_to_px(Vector2(float(q[0]), float(q[1]))), i))
		match kind:
			"park", "wood", "garden":
				if pts.size() >= 3:
					_wash(pts, Color("#a8cf8e", 0.7) if kind != "wood" else Color("#7fa870", 0.66), i)
			"water":
				if bool(f.get("closed", false)) and pts.size() >= 3:
					_wash(pts, Color("#9cc8e6", 0.8), i)
				elif pts.size() >= 2:
					draw_polyline(pts, Color("#7fb4d8"), maxf(2.0, 3.0 * _scale), true)
	i = 0
	for f in feats:
		i += 1
		var kind2 := str(f.get("kind", ""))
		if kind2 != "road" and kind2 != "path":
			continue
		var pts2 := PackedVector2Array()
		for q in f.get("pts", []):
			pts2.append(_wobble(_metres_to_px(Vector2(float(q[0]), float(q[1]))), i))
		if pts2.size() >= 2:
			var w := maxf(1.5, float(f.get("width", 6.0)) * _scale)
			draw_polyline(pts2, Color("#e3dccd") if kind2 == "road" else Color("#e8dcc0"), w + 2.0, true)
			# Pencil edges, drawn twice and not quite on top of each other.
			for pass_i in 2:
				var edge := PackedVector2Array()
				for q in pts2:
					edge.append(_wobble(q, i * 3 + pass_i))
				draw_polyline(edge, Color("#7d776c", 0.35 - pass_i * 0.12) if kind2 == "road" else Color("#b8a888", 0.5), maxf(1.0, w * 0.14), true)
	var font := ThemeDB.fallback_font
	i = 0
	for f in feats:
		i += 1
		if str(f.get("kind", "")) != "building":
			continue
		var pts3 := PackedVector2Array()
		for q in f.get("pts", []):
			pts3.append(_metres_to_px(Vector2(float(q[0]), float(q[1]))))
		if pts3.size() >= 3:
			var public: bool = str(f.get("sub", "home")) != "home"
			draw_colored_polygon(pts3, Color("#d6c8e6", 0.92) if public else Color("#e6d6bc", 0.95))
			draw_polyline(_outline(pts3, i), Color("#6e5e4c", 0.7), 1.2, true)
	# Names of public places (one where another would overlap is left off).
	var used: Array = []
	for f in feats:
		var nm := str(f.get("name", ""))
		var k := str(f.get("kind", ""))
		if nm == "" or k == "road":
			continue
		nm = _fit_name(nm, maxf(0.0, size.x - 12.0))
		if nm == "":
			continue
		var c := Vector2.ZERO
		var n := 0
		for q in f.get("pts", []):
			c += Vector2(float(q[0]), float(q[1]))
			n += 1
		if n == 0:
			continue
		var at := _metres_to_px(c / n)
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var box := Rect2(at + Vector2(-w / 2.0, -10), Vector2(w, 14))
		# Kept on the paper: a name near the edge slides inward rather than being cut off (phones).
		box.position.x = clampf(box.position.x, 4.0, maxf(4.0, size.x - w - 4.0))
		box.position.y = clampf(box.position.y, 4.0, maxf(4.0, size.y - 18.0))
		if used.any(func(u): return (u as Rect2).intersects(box)):
			continue
		used.append(box)
		draw_string_outline(font, box.position + Vector2(0, 11), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color("#f4ecd8", 0.9))
		draw_string(font, box.position + Vector2(0, 11), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#4a3e30"))
	# Your home.
	var home := _metres_to_px(Vector2.ZERO)
	draw_circle(home, 9.0, Color("#ffe9a8"))
	draw_string(font, home + Vector2(-6, 5), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#d9534f"))
	# (OpenStreetMap's credit is the label right under the map.)


## The block a tap lands in.
func chunk_at(px: Vector2) -> String:
	var m := _px_to_metres(px)
	var r := float(extract.get("radius", 250))
	var g := int(ceil(r * 2.0 / HoodBuilder.CELL_M))
	var chunks := maxi(1, int(ceil(float(g) / HoodBuilder.CHUNK)))
	if chunks % 2 == 0:
		chunks += 1
	var size_m := chunks * HoodBuilder.CHUNK * HoodBuilder.CELL_M
	var cx := int(floor((m.x + size_m / 2.0) / (HoodBuilder.CHUNK * HoodBuilder.CELL_M)))
	var cz := int(floor((m.y + size_m / 2.0) / (HoodBuilder.CHUNK * HoodBuilder.CELL_M)))
	if cx < 0 or cz < 0 or cx >= chunks or cz >= chunks:
		return ""
	return HoodBuilder.chunk_id(cx, cz)


## Zoom by `factor`, keeping the point under `at` (default: the middle) where it is.
func zoom_by(factor: float, at: Variant = null) -> void:
	var anchor: Vector2 = at if at is Vector2 else size / 2.0
	var new_zoom := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var k := new_zoom / zoom
	# The map's centre moves with the anchor: centre' = anchor + (centre - anchor) * k.
	pan = anchor + (size / 2.0 + pan - anchor) * k - size / 2.0
	zoom = new_zoom
	_clamp_pan()


func fit() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	queue_redraw()


## Some of the map always stays in view.
func _clamp_pan() -> void:
	var room := size * (zoom - 1.0) / 2.0 + size * 0.35
	pan = pan.clamp(-room, room)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Fingers: the real touches only (their mouse copies are skipped below), two of them pinch.
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			_pinch_from = maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
			_zoom_from = zoom
			_dragged = true   # (a pinch is never a tap)
		_press(event.position, event.pressed)
		accept_event()
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var pts2: Array = _touches.values()
			var mid: Vector2 = (pts2[0] + pts2[1]) / 2.0
			zoom_by(_zoom_from * maxf((pts2[0] as Vector2).distance_to(pts2[1]), 1.0) / _pinch_from / zoom, mid)
		else:
			_move(event.relative, event.position)
		accept_event()
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return   # (a touch's mouse copy: the touch above already counted)
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2, event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_press(event.position, event.pressed)
			accept_event()
	elif event is InputEventMouseMotion and _down:
		_move(event.relative, event.position)
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_by(event.factor, event.position)
		accept_event()
	elif event is InputEventPanGesture:
		pan -= event.delta * 12.0
		_clamp_pan()
		accept_event()


func _press(at: Vector2, down: bool) -> void:
	if down:
		if not _down:
			_down = true
			_dragged = _touches.size() >= 2
			_down_at = at
		return
	if not _touches.is_empty():
		return   # a finger is still down: the gesture isn't over
	var was_tap := _down and not _dragged
	_down = false
	_dragged = false
	if was_tap:
		var id := chunk_at(at)
		if id != "":
			picked.emit(id)


func _move(rel: Vector2, at: Vector2) -> void:
	if not _down:
		return
	if not _dragged and at.distance_to(_down_at) > TAP_SLOP:
		_dragged = true
	if _dragged:
		pan += rel
		_clamp_pan()
