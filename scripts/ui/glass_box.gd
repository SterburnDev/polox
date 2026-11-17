extends StyleBox
## Polox's glass: a rounded surface with a glossy top (Frutiger Aero), a thin light rim along the top
## edge, optionally a soft glow rising from the bottom (aqua by default), and, for things you press, a
## physical edge under it (`depth`): a pressed button drops onto that edge and gets an inner shadow, so
## a press is something you see, not only a colour change (early iOS).
## The gloss and glow are true gradients drawn as triangle strips that follow the rounded corners (they
## used to be three stacked flat bands, which showed as hard stripes, and a glow rectangle with a hard top
## edge), so they stay smooth and crisp at every size and cost no textures. theme_builder.gd uses it for
## buttons, tabs, toolbars and the title's card; dense text and editors keep solid surfaces
## (STYLE_GUIDE.md). With Reduce transparency on, theme_builder.gd passes opaque colours and no sheen.
## Tags: [GLASS_UI]

var base := Color(0.2, 0.16, 0.36, 0.8)
var border := Color(1, 1, 1, 0.3)
var border_w := 1
var radius := 14
var sheen := 0.13                  # how bright the glossy top is (0 = none)
var glow := Color(0, 0, 0, 0)      # the bottom glow's colour (alpha 0 = none)
var rim := 0.35                    # the light line along the top edge
var shadow := 0                    # a soft drop shadow, for floating controls
var round_bottom := true           # false: square bottom corners (a bottom sheet, a docked bar)
var round_top := true
var depth := 0                     # px of the edge under the surface (a key you can press); 0 = flat
var pressed := false               # sitting down on that edge, with an inner shadow
var inner := 0.0                   # an inner shadow's strength without pressing (a recessed slot, a well)

var _body: StyleBoxFlat
var _lip: StyleBoxFlat
var _rim: StyleBoxFlat


static func make(base_c: Color, border_c: Color, r: int = 14, pad: int = 10, sheen_a: float = 0.13, glow_c: Color = Color(0, 0, 0, 0), bw: int = 1) -> StyleBox:
	var g: StyleBox = load("res://scripts/ui/glass_box.gd").new()
	g.base = base_c
	g.border = border_c
	g.radius = r
	g.sheen = sheen_a
	g.glow = glow_c
	g.border_w = bw
	g.content_margin_left = pad + 4
	g.content_margin_right = pad + 4
	g.content_margin_top = pad
	g.content_margin_bottom = pad
	return g


## A key with an edge under it: `depth` px of side, and the content sits higher by as much (a pressed
## copy, `as_pressed()`, drops it, so the label visibly goes down with the key).
func with_depth(px: int) -> StyleBox:
	depth = px
	content_margin_bottom += px
	changed_look()
	return self


func as_pressed() -> StyleBox:
	var p: StyleBox = copy()
	p.pressed = true
	if depth > 0:
		p.content_margin_top += depth
		p.content_margin_bottom -= depth
	p.changed_look()
	return p


## A copy with every setting (Resource.duplicate() copies only exported properties, so a duplicated glass
## lost its colours and drew the default violet: pressed keys came out dark).
func copy() -> StyleBox:
	var g: StyleBox = load("res://scripts/ui/glass_box.gd").new()
	for prop in ["base", "border", "border_w", "radius", "sheen", "glow", "rim", "shadow", "round_bottom", "round_top", "depth", "pressed", "inner",
			"content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		g.set(prop, get(prop))
	return g


func _flat(bg: Color, rad: int) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = bg
	f.anti_aliasing = true
	f.corner_detail = 8
	f.corner_radius_top_left = rad if round_top else 0
	f.corner_radius_top_right = rad if round_top else 0
	f.corner_radius_bottom_left = rad if round_bottom else 0
	f.corner_radius_bottom_right = rad if round_bottom else 0
	return f


func _build() -> void:
	_body = _flat(base, radius)
	_body.border_color = border
	_body.set_border_width_all(border_w)
	if not round_bottom:
		_body.border_width_bottom = 0
	if shadow > 0:
		_body.shadow_size = shadow
		_body.shadow_color = Color(0, 0, 0, 0.28)
		_body.shadow_offset = Vector2(0, 2)
	_lip = null
	if depth > 0 and not pressed:
		# The key's side: the same colour, darker and more opaque, peeking out below.
		var side := Color(base.darkened(0.45), clampf(base.a + 0.15, 0.0, 1.0))
		_lip = _flat(side, radius)
		_lip.border_color = Color(0, 0, 0, 0.25)
		_lip.set_border_width_all(1)
		if shadow == 0:
			_lip.shadow_size = 3
			_lip.shadow_color = Color(0, 0, 0, 0.22)
			_lip.shadow_offset = Vector2(0, 1)
	_rim = null
	if rim > 0.0 and round_top and not pressed:
		_rim = _flat(Color(0, 0, 0, 0), radius)
		_rim.border_color = Color(1, 1, 1, rim)
		_rim.border_width_top = 1
		_rim.draw_center = false


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if _body == null:
		_build()
	var surface := rect
	if depth > 0:
		surface.size.y = maxf(rect.size.y - depth, 4.0)
		if pressed:
			surface.position.y += depth
		elif _lip:
			_lip.draw(to_canvas_item, Rect2(rect.position + Vector2(0, depth), surface.size))
	_body.draw(to_canvas_item, surface)
	var inset := float(border_w) + 1.0
	var inner_rect := surface.grow(-inset)
	if inner_rect.size.x < 4.0 or inner_rect.size.y < 4.0:
		return
	var r := maxf(float(radius) - inset, 0.0)
	if glow.a > 0.0:
		# Light rising from the bottom: nothing at the middle, the full glow at the bottom edge.
		_gradient(to_canvas_item, inner_rect, r, [[0.45, Color(glow, 0.0)], [1.0, glow]])
	if sheen > 0.0 and not pressed:
		# The gloss: brightest at the top, fading to a soft edge just below the middle, as on a glass
		# bubble (the edge is a 6 % ramp, not a hard line).
		var s := sheen * 1.15
		_gradient(to_canvas_item, inner_rect, r, [[0.0, Color(1, 1, 1, s)], [0.44, Color(1, 1, 1, s * 0.42)], [0.5, Color(1, 1, 1, 0.0)]])
	var shade := 0.32 if pressed else inner
	if shade > 0.0:
		# An inner shadow under the top edge: the surface sits below its surroundings.
		_gradient(to_canvas_item, inner_rect, r, [[0.0, Color(0, 0, 0, shade)], [0.3, Color(0, 0, 0, 0.0)]])
	if _rim:
		_rim.draw(to_canvas_item, surface.grow(-float(border_w)))


## A vertical gradient filling a rounded rectangle (corner radius `r`) between `stops`:
## [[t 0..1 from the top, colour], ...] in order; outside the stops nothing is drawn.
func _gradient(item: RID, rect: Rect2, r: float, stops: Array) -> void:
	var t0 := float(stops[0][0])
	var t1 := float(stops[-1][0])
	if t1 <= t0:
		return
	# Rows: every stop, plus extra rows through the corners so the edges follow the curve.
	var ts: Array = []
	for st in stops:
		ts.append(float(st[0]))
	r = minf(r, minf(rect.size.x, rect.size.y) / 2.0)
	if r > 0.5:
		for i in 9:
			var k := float(i) / 8.0
			ts.append(r * k / rect.size.y)
			ts.append(1.0 - r * k / rect.size.y)
	var rows: Array = []
	for t in ts:
		if t >= t0 - 0.0001 and t <= t1 + 0.0001:
			rows.append(clampf(t, t0, t1))
	rows.sort()
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var last := -1.0
	for row in rows:
		var t := float(row)
		if absf(t - last) < 0.0005:
			continue
		last = t
		var y := rect.position.y + t * rect.size.y
		var dx := _corner_inset(y - rect.position.y, rect.size.y, r)
		var c := _colour_at(stops, t)
		pts.append(Vector2(rect.position.x + dx, y))
		pts.append(Vector2(rect.end.x - dx, y))
		cols.append(c)
		cols.append(c)
	if pts.size() < 4:
		return
	var idx := PackedInt32Array()
	for i in range(0, pts.size() - 2, 2):
		idx.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
	RenderingServer.canvas_item_add_triangle_array(item, idx, pts, cols)


## How far in the rounded rectangle's edge is at height `y` (0 = its top).
func _corner_inset(y: float, h: float, r: float) -> float:
	if r <= 0.0:
		return 0.0
	var dy := -1.0
	if y < r and round_top:
		dy = r - y
	elif y > h - r and round_bottom:
		dy = y - (h - r)
	if dy < 0.0:
		return 0.0
	return r - sqrt(maxf(r * r - dy * dy, 0.0))


static func _colour_at(stops: Array, t: float) -> Color:
	for i in range(1, stops.size()):
		var a: Array = stops[i - 1]
		var b: Array = stops[i]
		if t <= float(b[0]) + 0.00001:
			var span := maxf(float(b[0]) - float(a[0]), 0.00001)
			return (a[1] as Color).lerp(b[1] as Color, clampf((t - float(a[0])) / span, 0.0, 1.0))
	return stops[-1][1]


## Rebuild after changing a property (theme_builder.gd sets them right after make()).
func changed_look() -> void:
	_body = null
	emit_changed()
