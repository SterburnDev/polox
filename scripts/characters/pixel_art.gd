extends RefCounted
## Small pixel-drawing helpers shared by the doll maker and the item icons:
## rectangles, ellipses, lines, polygons and a dark outline pass. All of them
## clip to the image, so shapes can poke past the edge safely.


static func blank(n: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func px(img: Image, pts: Array, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for p in pts:
		if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h:
			img.set_pixel(p.x, p.y, c)


static func rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, y0), mini(h - 1, y1) + 1):
		for x in range(maxi(0, x0), mini(w - 1, x1) + 1):
			img.set_pixel(x, y, c)


static func ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, floori(cy - ry - 1)), mini(h, ceili(cy + ry + 1))):
		for x in range(maxi(0, floori(cx - rx - 1)), mini(w, ceili(cx + rx + 1))):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)


## A ring: the ellipse minus a smaller one.
static func ring(img: Image, cx: float, cy: float, r_out: float, r_in: float, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, floori(cy - r_out - 1)), mini(h, ceili(cy + r_out + 1))):
		for x in range(maxi(0, floori(cx - r_out - 1)), mini(w, ceili(cx + r_out + 1))):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d <= r_out and d >= r_in:
				img.set_pixel(x, y, c)


## A line `width` pixels thick from a to b.
static func line(img: Image, a: Vector2, b: Vector2, c: Color, width: int = 1) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		rect(img, floori(p.x - (width - 1) / 2.0), floori(p.y - (width - 1) / 2.0), floori(p.x - (width - 1) / 2.0) + width - 1, floori(p.y - (width - 1) / 2.0) + width - 1, c)


## Fills every pixel whose centre lies inside the polygon.
static func polygon(img: Image, pts: PackedVector2Array, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, c)


## Darkens the edge of every opaque shape: crisp, readable sprites.
static func outline(img: Image, c: Color) -> void:
	var src := img.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a < 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or src.get_pixel(n.x, n.y).a < 0.5:
					img.set_pixel(x, y, c)
					break
