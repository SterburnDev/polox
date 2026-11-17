extends RefCounted
## Reads a QR code from a camera picture, for Polox for Android's "Scan the QR code" (pairing).
## The partner of qr_code.gd: byte mode, error correction level M, versions 1-10 (what the PC
## shows), but read from a real photo: any rotation, a tilted phone (perspective), uneven light,
## blur and a few damaged modules (Reed-Solomon fixes them), and mirror images.
##
##   1. Light/dark per pixel against the brightness around it (8x8 blocks, 5x5 neighbourhood)
##   2. The three finder squares (runs of dark-light-dark-light-dark in 1:1:3:1:1, checked
##      across and down), the best right-angled trio, which corner is which
##   3. The grid size from their distance; the bottom-right alignment square found near where
##      it should be, for the tilt (a perspective transform from four points)
##   4. Each module sampled, format bits (both copies), mask, codewords, de-interleaving,
##      Reed-Solomon over GF(256), then the byte segments as UTF-8.
## decode_image() returns "" when there's no readable code (most camera frames).

const QrCode := preload("res://scripts/phone/qr_code.gd")

const MAX_SIDE := 640
const BLOCK := 8

static var _exp := PackedInt32Array()
static var _log := PackedInt32Array()


# --- Entry points -------------------------------------------------------------------------------

## The text in the picture's QR code, or "".
static func decode_image(src: Image) -> String:
	if src == null or src.is_empty():
		return ""
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	if img.get_format() in [Image.FORMAT_R8, Image.FORMAT_RG8]:
		# A camera's brightness plane: take its first channel as is (a conversion would dim it).
		var raw := img.get_data()
		var lum := raw   # R8 is laid out like L8
		if img.get_format() == Image.FORMAT_RG8:
			lum = PackedByteArray()
			lum.resize(img.get_width() * img.get_height())
			for i in lum.size():
				lum[i] = raw[i * 2]
		img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_L8, lum)
	img.convert(Image.FORMAT_L8)
	var full := img
	var small := img.duplicate() as Image
	while maxi(small.get_width(), small.get_height()) > MAX_SIDE * 2:
		small.shrink_x2()
	if maxi(small.get_width(), small.get_height()) > MAX_SIDE:
		var s := float(MAX_SIDE) / maxi(small.get_width(), small.get_height())
		small.resize(maxi(1, int(small.get_width() * s)), maxi(1, int(small.get_height() * s)), Image.INTERPOLATE_BILINEAR)
	var seen := {}
	var text := decode_luma(small.get_data(), small.get_width(), small.get_height(), seen)
	if text != "" or not seen.has("box") or small.get_width() >= full.get_width():
		return text
	# A small code in a big picture: its modules got too small to read when the picture was
	# shrunk. Look again at full size, only around where its finders were.
	var k := float(full.get_width()) / small.get_width()
	var box: Rect2 = seen.box
	var grow := maxf(box.size.x, box.size.y) * 0.45
	var area := Rect2i(Rect2(box.position * k - Vector2(grow, grow) * k, box.size * k + Vector2(grow, grow) * 2.0 * k)).intersection(Rect2i(Vector2i.ZERO, full.get_size()))
	if area.size.x < 21 or area.size.y < 21:
		return ""
	var crop := full.get_region(area)
	if maxi(crop.get_width(), crop.get_height()) > MAX_SIDE:
		var s2 := float(MAX_SIDE) / maxi(crop.get_width(), crop.get_height())
		crop.resize(maxi(1, int(crop.get_width() * s2)), maxi(1, int(crop.get_height() * s2)), Image.INTERPOLATE_BILINEAR)
	return decode_luma(crop.get_data(), crop.get_width(), crop.get_height())


## The same from raw 8-bit brightness, `w` x `h` (row by row). `seen` (optional) gets the
## best trio's bounding box ("box") and module size ("m") when a code was found but not read.
static func decode_luma(lum: PackedByteArray, w: int, h: int, seen: Dictionary = {}) -> String:
	if w < 21 or h < 21 or lum.size() < w * h:
		return ""
	var dark := binarize(lum, w, h)
	var finders := find_finders(dark, w, h)
	if finders.size() < 3:
		return ""
	var trios := best_trios(finders)
	for trio in trios:
		var text := _decode_trio(dark, w, h, trio)
		if text != "":
			return text
	if not trios.is_empty():
		var t: Array = trios[0]
		var r := Rect2(Vector2(float(t[0].x), float(t[0].y)), Vector2.ZERO)
		var br := Vector2(float(t[1].x), float(t[1].y)) + Vector2(float(t[2].x), float(t[2].y)) - Vector2(float(t[0].x), float(t[0].y))
		for p in [Vector2(float(t[1].x), float(t[1].y)), Vector2(float(t[2].x), float(t[2].y)), br]:
			r = r.expand(p)
		seen["box"] = r
		seen["m"] = (float(t[0].m) + float(t[1].m) + float(t[2].m)) / 3.0
	return ""


# --- 1. Light and dark --------------------------------------------------------------------------

## 1 = dark, 0 = light, one byte per pixel. Each 8x8 block gets a threshold from the 5x5
## blocks around it; flat blocks (no contrast) lean towards their darker neighbours' level,
## so a big white margin stays white and a big black square stays black.
static func binarize(lum: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var bw := (w + BLOCK - 1) / BLOCK
	var bh := (h + BLOCK - 1) / BLOCK
	var black := PackedInt32Array()
	black.resize(bw * bh)
	for by in bh:
		var y0 := mini(by * BLOCK, h - BLOCK) if h >= BLOCK else 0
		for bx in bw:
			var x0 := mini(bx * BLOCK, w - BLOCK) if w >= BLOCK else 0
			var total := 0
			var lo := 255
			var hi := 0
			for yy in range(y0, mini(y0 + BLOCK, h)):
				var row := yy * w
				for xx in range(x0, mini(x0 + BLOCK, w)):
					var v := lum[row + xx]
					total += v
					if v < lo:
						lo = v
					if v > hi:
						hi = v
			var avg := total >> 6
			if hi - lo <= 24:
				avg = lo >> 1
				if by > 0 and bx > 0:
					var nb := (black[(by - 1) * bw + bx] + 2 * black[by * bw + bx - 1] + black[(by - 1) * bw + bx - 1]) >> 2
					if lo < nb:
						avg = nb
			black[by * bw + bx] = avg
	var out := PackedByteArray()
	out.resize(w * h)
	for by in bh:
		var cy := clampi(by, 2, bh - 3) if bh >= 5 else by
		for bx in bw:
			var cx := clampi(bx, 2, bw - 3) if bw >= 5 else bx
			var sum := 0
			var n := 0
			for dy in range(-2, 3):
				var yy := cy + dy
				if yy < 0 or yy >= bh:
					continue
				for dx in range(-2, 3):
					var xx := cx + dx
					if xx < 0 or xx >= bw:
						continue
					sum += black[yy * bw + xx]
					n += 1
			var thr := sum / maxi(1, n)
			var y0 := by * BLOCK
			var x0 := bx * BLOCK
			for yy in range(y0, mini(y0 + BLOCK, h)):
				var row := yy * w
				for xx in range(x0, mini(x0 + BLOCK, w)):
					out[row + xx] = 1 if lum[row + xx] <= thr else 0
	return out


# --- 2. Finder squares --------------------------------------------------------------------------

static func _ratio_ok(c: Array) -> bool:
	var total := 0
	for v in c:
		if int(v) == 0:
			return false
		total += int(v)
	if total < 7:
		return false
	var m := total / 7.0
	var tol := m * 0.7
	return absf(c[0] - m) < tol and absf(c[1] - m) < tol and absf(c[2] - 3.0 * m) < 3.0 * tol and absf(c[3] - m) < tol and absf(c[4] - m) < tol


## Measures the 1:1:3:1:1 runs through (cx, cy) along (dx, dy); returns [center offset, total] or [].
static func _cross(dark: PackedByteArray, w: int, h: int, cx: int, cy: int, dx: int, dy: int, max_count: int) -> Array:
	if cx < 0 or cy < 0 or cx >= w or cy >= h or dark[cy * w + cx] != 1:
		return []
	var c := [0, 0, 0, 0, 0]
	var x := cx
	var y := cy
	# Up/left from the centre: dark core, light ring, dark ring.
	while x >= 0 and y >= 0 and x < w and y < h and dark[y * w + x] == 1:
		c[2] += 1
		x -= dx
		y -= dy
	var back_core: int = c[2]
	if x < 0 or y < 0 or x >= w or y >= h:
		return []
	while x >= 0 and y >= 0 and x < w and y < h and dark[y * w + x] == 0 and c[1] <= max_count:
		c[1] += 1
		x -= dx
		y -= dy
	if x < 0 or y < 0 or x >= w or y >= h or c[1] > max_count:
		return []
	while x >= 0 and y >= 0 and x < w and y < h and dark[y * w + x] == 1 and c[0] <= max_count:
		c[0] += 1
		x -= dx
		y -= dy
	if c[0] > max_count:
		return []
	x = cx + dx
	y = cy + dy
	while x >= 0 and y >= 0 and x < w and y < h and dark[y * w + x] == 1:
		c[2] += 1
		x += dx
		y += dy
	if x < 0 or y < 0 or x >= w or y >= h:
		return []
	while x >= 0 and y >= 0 and x < w and y < h and dark[y * w + x] == 0 and c[3] < max_count:
		c[3] += 1
		x += dx
		y += dy
	if x < 0 or y < 0 or x >= w or y >= h or c[3] >= max_count:
		return []
	while x >= 0 and y >= 0 and x < w and y < h and dark[y * w + x] == 1 and c[4] < max_count:
		c[4] += 1
		x += dx
		y += dy
	if c[4] >= max_count or not _ratio_ok(c):
		return []
	var total: int = c[0] + c[1] + c[2] + c[3] + c[4]
	# How far the middle of the core is from (cx, cy), so the caller can move there.
	var fwd_core: int = c[2] - back_core
	return [(fwd_core - back_core + 1) / 2.0, total]


## Finder square centres: [{x, y, m (module size), n (how many rows saw it)}], most seen first.
static func find_finders(dark: PackedByteArray, w: int, h: int) -> Array:
	var found: Array = []
	var skip := maxi(1, h / 240)
	var y := skip - 1
	while y < h:
		var c := [0, 0, 0, 0, 0]
		var s := 0
		var row := y * w
		var x := 0
		while x < w:
			if dark[row + x] == 1:
				if s % 2 == 1:
					s += 1
				c[s] += 1
			elif s % 2 == 1:
				c[s] += 1
			elif s == 0 and c[0] == 0:
				pass   # still before the first dark run
			elif s == 4:
				if _ratio_ok(c):
					_try_candidate(dark, w, h, c, x, y, found)
				c = [c[2], c[3], c[4], 1, 0]   # the last three runs may start the next pattern
				s = 3
			else:
				s += 1
				c[s] += 1
			x += 1
		if s == 4 and _ratio_ok(c):
			_try_candidate(dark, w, h, c, w, y, found)
		y += skip
	# Specks of noise can look like tiny finders: a module under 1.5 pixels can't be read anyway,
	# and a real finder is crossed by several rows.
	found = found.filter(func(f): return float(f.m) >= 1.5)
	var seen_twice := found.filter(func(f): return int(f.n) >= 2)
	if seen_twice.size() >= 3:
		found = seen_twice
	found.sort_custom(func(a, b): return int(a.n) > int(b.n))
	return found


static func _try_candidate(dark: PackedByteArray, w: int, h: int, c: Array, end_x: int, y: int, found: Array) -> void:
	var total: int = c[0] + c[1] + c[2] + c[3] + c[4]
	var cx := int(end_x - c[4] - c[3] - c[2] / 2.0)
	var v := _cross(dark, w, h, cx, y, 0, 1, c[2] * 2)
	if v.is_empty():
		return
	var cy := int(round(y + float(v[0])))
	var hz := _cross(dark, w, h, cx, cy, 1, 0, c[2] * 2)
	if hz.is_empty():
		return
	var fx := cx + float(hz[0])
	var m := (float(hz[1]) + float(v[1]) + total) / 21.0
	# The diagonal must look like a finder too (rules out stripes and text).
	if _cross(dark, w, h, int(round(fx)), cy, 1, 1, int(m * 6)).is_empty():
		return
	for f in found:
		if absf(float(f.x) - fx) <= m and absf(float(f.y) - cy) <= m and absf(float(f.m) - m) <= maxf(1.0, m * 0.5):
			var n := int(f.n)
			f.x = (float(f.x) * n + fx) / (n + 1)
			f.y = (float(f.y) * n + cy) / (n + 1)
			f.m = (float(f.m) * n + m) / (n + 1)
			f.n = n + 1
			return
	found.append({"x": fx, "y": float(cy), "m": m, "n": 1})


## Trios of finders that make a right-angled corner, best first: [[top-left, top-right, bottom-left]].
static func best_trios(finders: Array) -> Array:
	var pool := finders.slice(0, 10)
	var top_n := 1
	for f in pool:
		top_n = maxi(top_n, int(f.n))
	var scored: Array = []
	for i in pool.size():
		for j in range(i + 1, pool.size()):
			for k in range(j + 1, pool.size()):
				var t := _order([pool[i], pool[j], pool[k]])
				if t.is_empty():
					continue
				# Finders crossed by many rows are more likely real.
				var least := mini(int(pool[i].n), mini(int(pool[j].n), int(pool[k].n)))
				t[3] = float(t[3]) + 0.6 * (1.0 - float(least) / top_n)
				scored.append(t)
	scored.sort_custom(func(a, b): return float(a[3]) < float(b[3]))
	return scored.slice(0, 4).map(func(t): return [t[0], t[1], t[2]])


## [top-left, top-right, bottom-left, badness] or [] when they can't be a QR code's corners.
static func _order(p: Array) -> Array:
	var ms := [float(p[0].m), float(p[1].m), float(p[2].m)]
	if ms.max() > ms.min() * 2.2:   # a tilted phone makes the far finders smaller
		return []
	var pts: Array = p.map(func(f): return Vector2(float(f.x), float(f.y)))
	var d01: float = pts[0].distance_to(pts[1])
	var d02: float = pts[0].distance_to(pts[2])
	var d12: float = pts[1].distance_to(pts[2])
	var tl := 0
	var a := 1
	var b := 2
	if d01 >= d02 and d01 >= d12:
		tl = 2; a = 0; b = 1
	elif d02 >= d01 and d02 >= d12:
		tl = 1; a = 0; b = 2
	var va: Vector2 = pts[a] - pts[tl]
	var vb: Vector2 = pts[b] - pts[tl]
	var la := va.length()
	var lb := vb.length()
	var m: float = (ms[0] + ms[1] + ms[2]) / 3.0
	if la < m * 10.0 or lb < m * 10.0:   # finders of a version-1 code are 14 modules apart
		return []
	var legs := la / lb
	if legs < 0.5 or legs > 2.0:
		return []
	var cosang := va.dot(vb) / (la * lb)
	if absf(cosang) > 0.5:
		return []
	if va.cross(vb) < 0.0:   # (y points down) top-right must be clockwise from bottom-left
		var tmp := a
		a = b
		b = tmp
	return [p[tl], p[a], p[b], absf(cosang) + absf(1.0 - legs)]


# --- 3. The grid --------------------------------------------------------------------------------

static func _decode_trio(dark: PackedByteArray, w: int, h: int, trio: Array) -> String:
	var tl := Vector2(float(trio[0].x), float(trio[0].y))
	var tr := Vector2(float(trio[1].x), float(trio[1].y))
	var bl := Vector2(float(trio[2].x), float(trio[2].y))
	# The grid size from each edge, with module sizes measured along that edge (a tilted phone
	# makes modules narrower one way than the other, and smaller on the far side).
	var m_top := _module_along(dark, w, h, tl, tr, (float(trio[0].m) + float(trio[1].m)) / 2.0)
	var m_left := _module_along(dark, w, h, tl, bl, (float(trio[0].m) + float(trio[2].m)) / 2.0)
	var dim := int(round((tl.distance_to(tr) / m_top + tl.distance_to(bl) / m_left) / 2.0)) + 7
	match dim & 3:
		0:
			dim += 1
		2:
			dim -= 1
		3:
			dim -= 2
	var tries: Array = [dim, dim + 4, dim - 4]
	for d in tries:
		var size := int(d)
		var version := (size - 17) / 4
		if version < 1 or version > 10:
			continue
		var hmat := _grid_transform(dark, w, h, tl, tr, bl, size)
		var bits := _sample(dark, w, h, hmat, size)
		if bits.is_empty():
			continue
		for mirrored in [false, true]:
			var text := decode_bits(bits if not mirrored else _transpose(bits, size), size)
			if text != "":
				return text
	return ""


## From a finder's centre along `dir` to the outer edge of its dark ring (3.5 modules), or -1.
static func _edge_dist(dark: PackedByteArray, w: int, h: int, from: Vector2, dir: Vector2) -> float:
	var state := 0   # 0: the dark core, 1: the light ring, 2: the dark ring
	var p := from
	var dist := 0.0
	while dist < 400.0:
		var x := int(p.x)
		var y := int(p.y)
		if x < 0 or y < 0 or x >= w or y >= h:
			return -1.0
		var d := dark[y * w + x] == 1
		if state == 0 and not d:
			state = 1
		elif state == 1 and d:
			state = 2
		elif state == 2 and not d:
			return dist
		p += dir
		dist += 1.0
	return -1.0


## The module size along the line between two finders (both finders, both ways: 7 modules each).
static func _module_along(dark: PackedByteArray, w: int, h: int, a: Vector2, b: Vector2, fallback: float) -> float:
	var dir := (b - a).normalized()
	var sizes: Array = []
	for pair in [[a, dir], [b, -dir]]:
		var f := _edge_dist(dark, w, h, pair[0], pair[1])
		var g := _edge_dist(dark, w, h, pair[0], -(pair[1] as Vector2))
		if f > 0.0 and g > 0.0:
			sizes.append((f + g) / 7.0)
	if sizes.is_empty():
		return fallback
	var s := 0.0
	for v in sizes:
		s += float(v)
	return s / sizes.size()


## Image position of module coordinates, from four corners (perspective) or three (affine).
static func _grid_transform(dark: PackedByteArray, w: int, h: int, tl: Vector2, tr: Vector2, bl: Vector2, size: int) -> PackedFloat64Array:
	var span := float(size - 7)
	var br_guess := tr + bl - tl
	var src_br := Vector2(size - 3.5, size - 3.5)
	var dst_br := br_guess
	if size > 21:
		var u := (tr - tl) / span
		var v := (bl - tl) / span
		var k := (size - 6.5 - 3.5)
		var guess := tl + u * k + v * k
		var found := _find_alignment(dark, w, h, guess, u, v)
		if found != Vector2.INF:
			src_br = Vector2(size - 6.5, size - 6.5)
			dst_br = found
		else:
			src_br = Vector2(size - 6.5, size - 6.5)
			dst_br = guess
	return quad_to_quad(
		[Vector2(3.5, 3.5), Vector2(size - 3.5, 3.5), src_br, Vector2(3.5, size - 3.5)],
		[tl, tr, dst_br, bl])


## The bottom-right alignment square (a 5x5-module ring with a dark centre) near `guess`.
## First a close look with the expected module size; then, because a tilted phone moves it
## away from where three finders predict and shrinks it, a scan of rows and columns up to 12
## modules around for its dark-light-dark-light-dark runs of equal length.
static func _find_alignment(dark: PackedByteArray, w: int, h: int, guess: Vector2, u: Vector2, v: Vector2) -> Vector2:
	var m := (u.length() + v.length()) * 0.5
	var near := _search_alignment(dark, w, h, guess, u, v, m * 5.0, 22)
	if near != Vector2.INF:
		return near
	var best := Vector2.INF
	var reach := m * 12.0
	var y0 := maxi(0, int(guess.y - reach))
	var y1 := mini(h - 1, int(guess.y + reach))
	var x0 := maxi(0, int(guess.x - reach))
	var x1 := mini(w - 1, int(guess.x + reach))
	for y in range(y0, y1 + 1):
		var runs: Array = []   # [start, length, dark]
		var x := x0
		while x <= x1:
			var d := dark[y * w + x]
			var start := x
			while x <= x1 and dark[y * w + x] == d:
				x += 1
			runs.append([start, x - start, d])
		for i in range(0, runs.size() - 4):
			if int(runs[i][2]) != 1:
				continue
			var lens: Array = [runs[i][1], runs[i + 1][1], runs[i + 2][1], runs[i + 3][1], runs[i + 4][1]]
			var mean: float = (int(lens[0]) + int(lens[1]) + int(lens[2]) + int(lens[3]) + int(lens[4])) / 5.0
			if mean < m * 0.35 or mean > m * 1.4 or lens.any(func(l): return absf(float(l) - mean) > mean * 0.6):
				continue
			var c := Vector2(int(runs[i + 2][0]) + int(runs[i + 2][1]) / 2.0, y + 0.5)
			var cy := _cross_alignment(dark, w, h, int(c.x), y, mean)
			if cy < 0.0:
				continue
			c.y = cy
			if best != Vector2.INF and c.distance_to(guess) >= best.distance_to(guess):
				continue
			# Data modules can line up like that by chance: the whole 5x5 ring must be there.
			var fine := _search_alignment(dark, w, h, c, u.normalized() * mean, v.normalized() * mean, mean * 0.7, 22)
			if fine != Vector2.INF:
				best = fine
	return best


## Down and up from (x, y): the same five equal runs vertically? Their middle, or -1.
static func _cross_alignment(dark: PackedByteArray, w: int, h: int, x: int, y: int, mean: float) -> float:
	if dark[y * w + x] != 1:
		return -1.0
	var top := y
	while top > 0 and dark[(top - 1) * w + x] == 1:
		top -= 1
	var bottom := y
	while bottom < h - 1 and dark[(bottom + 1) * w + x] == 1:
		bottom += 1
	var core := bottom - top + 1
	if absf(core - mean) > mean * 0.7:
		return -1.0
	# light ring then dark ring on both sides
	for dir in [-1, 1]:
		var yy := top - 1 if dir < 0 else bottom + 1
		var light := 0
		while yy >= 0 and yy < h and dark[yy * w + x] == 0 and light <= mean * 2.0:
			light += 1
			yy += dir
		if light == 0 or absf(light - mean) > mean * 0.7 or yy < 0 or yy >= h:
			return -1.0
		var ring := 0
		while yy >= 0 and yy < h and dark[yy * w + x] == 1 and ring <= mean * 2.0:
			ring += 1
			yy += dir
		if ring == 0 or absf(ring - mean) > mean * 0.7:
			return -1.0
	return (top + bottom + 1) / 2.0


static func _search_alignment(dark: PackedByteArray, w: int, h: int, guess: Vector2, u: Vector2, v: Vector2, reach: float, need: int) -> Vector2:
	var best := -1
	var best_p := Vector2.INF
	var step := maxf(1.0, minf(u.length(), v.length()) / 3.0)
	var oy := -reach
	while oy <= reach:
		var ox := -reach
		while ox <= reach:
			var c := guess + Vector2(ox, oy)
			var score := 0
			for j in range(-2, 3):
				for i in range(-2, 3):
					var p := c + u * i + v * j
					var px := int(round(p.x))
					var py := int(round(p.y))
					if px < 0 or py < 0 or px >= w or py >= h:
						continue
					var want := 1 if maxi(absi(i), absi(j)) != 1 else 0
					if dark[py * w + px] == want:
						score += 1
			if score > best or (score == best and c.distance_to(guess) < best_p.distance_to(guess)):
				best = score
				best_p = c
			ox += step
		oy += step
	return best_p if best >= need else Vector2.INF


static func _sample(dark: PackedByteArray, w: int, h: int, hm: PackedFloat64Array, size: int) -> PackedByteArray:
	var bits := PackedByteArray()
	bits.resize(size * size)
	for y in size:
		for x in size:
			var p := apply(hm, x + 0.5, y + 0.5)
			var px := int(p.x)
			var py := int(p.y)
			if px < 0 or py < 0 or px >= w or py >= h:
				if px < -2 or py < -2 or px >= w + 2 or py >= h + 2:
					return PackedByteArray()
				px = clampi(px, 0, w - 1)
				py = clampi(py, 0, h - 1)
			bits[y * size + x] = dark[py * w + px]
	return bits


static func _transpose(bits: PackedByteArray, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(bits.size())
	for y in size:
		for x in size:
			out[x * size + y] = bits[y * size + x]
	return out


# --- Perspective (as in ZXing's PerspectiveTransform) -------------------------------------------

## Maps the unit square's corners (0,0),(1,0),(1,1),(0,1) to p[0..3]: [h0..h8] for
## u = (h0 x + h1 y + h2) / w, v = (h3 x + h4 y + h5) / w, w = h6 x + h7 y + h8.
static func square_to_quad(p: Array) -> PackedFloat64Array:
	var x0: float = p[0].x; var y0: float = p[0].y
	var x1: float = p[1].x; var y1: float = p[1].y
	var x2: float = p[2].x; var y2: float = p[2].y
	var x3: float = p[3].x; var y3: float = p[3].y
	var dx3 := x0 - x1 + x2 - x3
	var dy3 := y0 - y1 + y2 - y3
	if absf(dx3) < 1e-9 and absf(dy3) < 1e-9:
		return PackedFloat64Array([x1 - x0, x2 - x1, x0, y1 - y0, y2 - y1, y0, 0.0, 0.0, 1.0])
	var dx1 := x1 - x2
	var dx2 := x3 - x2
	var dy1 := y1 - y2
	var dy2 := y3 - y2
	var den := dx1 * dy2 - dx2 * dy1
	var a13 := (dx3 * dy2 - dx2 * dy3) / den
	var a23 := (dx1 * dy3 - dx3 * dy1) / den
	return PackedFloat64Array([x1 - x0 + a13 * x1, x3 - x0 + a23 * x3, x0, y1 - y0 + a13 * y1, y3 - y0 + a23 * y3, y0, a13, a23, 1.0])


static func _adjugate(m: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		m[4] * m[8] - m[5] * m[7], m[2] * m[7] - m[1] * m[8], m[1] * m[5] - m[2] * m[4],
		m[5] * m[6] - m[3] * m[8], m[0] * m[8] - m[2] * m[6], m[2] * m[3] - m[0] * m[5],
		m[3] * m[7] - m[4] * m[6], m[1] * m[6] - m[0] * m[7], m[0] * m[4] - m[1] * m[3]])


static func _mul(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(9)
	for r in 3:
		for c in 3:
			out[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c]
	return out


## The transform taking quadrilateral `src` to `dst` (corners in the same order).
static func quad_to_quad(src: Array, dst: Array) -> PackedFloat64Array:
	return _mul(square_to_quad(dst), _adjugate(square_to_quad(src)))


static func apply(m: PackedFloat64Array, x: float, y: float) -> Vector2:
	var d := m[6] * x + m[7] * y + m[8]
	if absf(d) < 1e-12:
		return Vector2(-1e9, -1e9)
	return Vector2((m[0] * x + m[1] * y + m[2]) / d, (m[3] * x + m[4] * y + m[5]) / d)


# --- 4. From modules to text --------------------------------------------------------------------

## The text in a `size` x `size` grid of modules (1 = dark), or "" when it doesn't decode.
static func decode_bits(bits: PackedByteArray, size: int) -> String:
	var version := (size - 17) / 4
	if version < 1 or version > 10 or bits.size() != size * size:
		return ""
	var fmt := _read_format(bits, size)
	if fmt < 0 or (fmt >> 3) != QrCode.FORMAT_BITS_M:
		return ""
	var mask := fmt & 7
	var q: RefCounted = QrCode.new()
	q.version = version
	q.size = size
	q.modules = []
	q._function = []
	for y in size:
		var row: Array = []
		row.resize(size)
		row.fill(false)
		q.modules.append(row)
		q._function.append(row.duplicate())
	q._draw_function_patterns()
	var fn: Array = q._function
	var total: int = QrCode.TOTAL_CODEWORDS[version - 1]
	var codewords := PackedByteArray()
	codewords.resize(total)
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if fn[y][x] or i >= total * 8:
					continue
				var bit := bits[y * size + x] == 1
				if _masked(mask, x, y):
					bit = not bit
				if bit:
					codewords[i >> 3] |= 1 << (7 - (i & 7))
				i += 1
		right -= 2
	var data := _correct(codewords, version)
	if data.is_empty():
		return ""
	return _parse(data, version)


static func _masked(mask: int, x: int, y: int) -> bool:
	match mask:
		0:
			return (x + y) % 2 == 0
		1:
			return y % 2 == 0
		2:
			return x % 3 == 0
		3:
			return (x + y) % 3 == 0
		4:
			return (x / 3 + y / 2) % 2 == 0
		5:
			return x * y % 2 + x * y % 3 == 0
		6:
			return (x * y % 2 + x * y % 3) % 2 == 0
		7:
			return ((x + y) % 2 + x * y % 3) % 2 == 0
	return false


## The 5 format bits (level << 3 | mask) from the closer of both copies, or -1.
static func _read_format(bits: PackedByteArray, size: int) -> int:
	var a := 0
	var b := 0
	var at := func(x: int, y: int) -> int: return bits[y * size + x]
	for k in range(0, 6):
		a |= at.call(8, k) << k
	a |= at.call(8, 7) << 6
	a |= at.call(8, 8) << 7
	a |= at.call(7, 8) << 8
	for k in range(9, 15):
		a |= at.call(14 - k, 8) << k
	for k in range(0, 8):
		b |= at.call(size - 1 - k, 8) << k
	for k in range(8, 15):
		b |= at.call(8, size - 15 + k) << k
	var best := -1
	var best_d := 99
	for data in 32:
		var rem := data
		for _k in 10:
			rem = (rem << 1) ^ ((rem >> 9) * 0x537)
		var code := ((data << 10) | rem) ^ 0x5412
		var d := mini(_popcount(code ^ a), _popcount(code ^ b))
		if d < best_d:
			best_d = d
			best = data
	return best if best_d <= 3 else -1


static func _popcount(v: int) -> int:
	var n := 0
	while v != 0:
		n += v & 1
		v >>= 1
	return n


## Data codewords after de-interleaving and Reed-Solomon correction (empty if too damaged).
static func _correct(codewords: PackedByteArray, version: int) -> PackedByteArray:
	var num_blocks: int = QrCode.BLOCKS[version - 1]
	var ecc_len: int = QrCode.EC_PER_BLOCK[version - 1]
	var raw: int = QrCode.TOTAL_CODEWORDS[version - 1]
	var num_short := num_blocks - raw % num_blocks
	var short_len := raw / num_blocks
	var blocks: Array = []   # Arrays (shared), not PackedByteArrays (copied on write)
	for j in num_blocks:
		var b: Array = []
		b.resize(short_len + 1)
		b.fill(0)
		blocks.append(b)
	var k := 0
	for i in short_len + 1:
		for j in num_blocks:
			if i == short_len - ecc_len and j < num_short:
				continue
			if k >= codewords.size():
				return PackedByteArray()
			blocks[j][i] = codewords[k]
			k += 1
	var out := PackedByteArray()
	for j in num_blocks:
		var b := PackedByteArray(blocks[j])
		if j < num_short:
			b.remove_at(short_len - ecc_len)   # the placeholder the encoder added
		var fixed := rs_correct(b, ecc_len)
		if fixed.is_empty():
			return PackedByteArray()
		out.append_array(fixed.slice(0, fixed.size() - ecc_len))
	return out


static func _bits(data: PackedByteArray, pos: int, n: int) -> int:
	var v := 0
	for i in n:
		var p := pos + i
		v = (v << 1) | ((data[p >> 3] >> (7 - (p & 7))) & 1)
	return v


static func _parse(data: PackedByteArray, version: int) -> String:
	var pos := 0
	var out := PackedByteArray()
	var total_bits := data.size() * 8
	while total_bits - pos >= 4:
		var mode := _bits(data, pos, 4)
		pos += 4
		if mode == 0:
			break
		if mode != 0b0100:
			return ""   # Polox's codes are all byte mode
		var count_bits := 8 if version < 10 else 16
		if total_bits - pos < count_bits:
			return ""
		var count := _bits(data, pos, count_bits)
		pos += count_bits
		if total_bits - pos < count * 8:
			return ""
		for _c in count:
			out.append(_bits(data, pos, 8))
			pos += 8
	return out.get_string_from_utf8()


# --- Reed-Solomon over GF(256), as in ZXing's ReedSolomonDecoder (generator base 0) --------------

static func _tables() -> void:
	if not _exp.is_empty():
		return
	_exp.resize(512)
	_log.resize(256)
	var x := 1
	for i in 255:
		_exp[i] = x
		_log[x] = i
		x <<= 1
		if x >= 256:
			x ^= 0x11D
	for i in range(255, 512):
		_exp[i] = _exp[i - 255]


static func _gmul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _exp[_log[a] + _log[b]]


static func _ginv(a: int) -> int:
	return _exp[255 - _log[a]]


## Polynomials: coefficients, highest degree first, no leading zeros (zero is [0]).
static func _poly(c: PackedInt32Array) -> PackedInt32Array:
	var first := 0
	while first < c.size() - 1 and c[first] == 0:
		first += 1
	return c.slice(first) if c.size() > 0 else PackedInt32Array([0])


static func _deg(p: PackedInt32Array) -> int:
	return p.size() - 1


static func _coef(p: PackedInt32Array, degree: int) -> int:
	return p[p.size() - 1 - degree]


static func _is_zero(p: PackedInt32Array) -> bool:
	return p[0] == 0


static func _eval(p: PackedInt32Array, a: int) -> int:
	if a == 0:
		return _coef(p, 0)
	var r := p[0]
	for i in range(1, p.size()):
		r = _gmul(a, r) ^ p[i]
	return r


static func _add(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	if _is_zero(a):
		return b
	if _is_zero(b):
		return a
	var small := a
	var big := b
	if a.size() > b.size():
		small = b
		big = a
	var out := big.duplicate()
	var diff := big.size() - small.size()
	for i in small.size():
		out[diff + i] ^= small[i]
	return _poly(out)


static func _pmul(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	if _is_zero(a) or _is_zero(b):
		return PackedInt32Array([0])
	var out := PackedInt32Array()
	out.resize(a.size() + b.size() - 1)
	for i in a.size():
		for j in b.size():
			out[i + j] ^= _gmul(a[i], b[j])
	return _poly(out)


static func _scale(a: PackedInt32Array, s: int) -> PackedInt32Array:
	if s == 0:
		return PackedInt32Array([0])
	var out := a.duplicate()
	for i in out.size():
		out[i] = _gmul(out[i], s)
	return out


static func _monomial(degree: int, c: int) -> PackedInt32Array:
	if c == 0:
		return PackedInt32Array([0])
	var out := PackedInt32Array()
	out.resize(degree + 1)
	out[0] = c
	return out


static func _times_monomial(a: PackedInt32Array, degree: int, c: int) -> PackedInt32Array:
	if c == 0:
		return PackedInt32Array([0])
	var out := _scale(a, c)
	out.resize(out.size() + degree)
	return out


## One block (data + `ecc_len` check bytes), corrected; empty when it has too many errors.
static func rs_correct(block: PackedByteArray, ecc_len: int) -> PackedByteArray:
	_tables()
	var received := PackedInt32Array()
	for b in block:
		received.append(b)
	var syn := PackedInt32Array()
	syn.resize(ecc_len)
	var clean := true
	var rp := _poly(received)
	for i in ecc_len:
		var e := _eval(rp, _exp[i])
		syn[ecc_len - 1 - i] = e
		if e != 0:
			clean = false
	if clean:
		return block
	# Euclid: sigma (where the errors are) and omega (how big).
	var a := _monomial(ecc_len, 1)
	var b := _poly(syn)
	if _deg(a) < _deg(b):
		var t0 := a
		a = b
		b = t0
	var r_last := a
	var r := b
	var t_last := PackedInt32Array([0])
	var t := PackedInt32Array([1])
	while 2 * _deg(r) >= ecc_len:
		var r_ll := r_last
		var t_ll := t_last
		r_last = r
		t_last = t
		if _is_zero(r_last):
			return PackedByteArray()
		r = r_ll
		var q := PackedInt32Array([0])
		var dlt_inv := _ginv(_coef(r_last, _deg(r_last)))
		while _deg(r) >= _deg(r_last) and not _is_zero(r):
			var dd := _deg(r) - _deg(r_last)
			var sc := _gmul(_coef(r, _deg(r)), dlt_inv)
			q = _add(q, _monomial(dd, sc))
			r = _add(r, _times_monomial(r_last, dd, sc))
		t = _add(_pmul(q, t_last), t_ll)
		if _deg(r) >= _deg(r_last):
			return PackedByteArray()
	var s0 := _coef(t, 0)
	if s0 == 0:
		return PackedByteArray()
	var inv := _ginv(s0)
	var sigma := _scale(t, inv)
	var omega := _scale(r, inv)
	# Where: the roots of sigma (Chien search).
	var n_err := _deg(sigma)
	var locs := PackedInt32Array()
	if n_err == 1:
		locs.append(_coef(sigma, 1))
	else:
		for i in range(1, 256):
			if locs.size() >= n_err:
				break
			if _eval(sigma, i) == 0:
				locs.append(_ginv(i))
	if locs.size() != n_err:
		return PackedByteArray()
	# How big (Forney).
	var out := block.duplicate()
	for i in locs.size():
		var xi_inv := _ginv(locs[i])
		var den := 1
		for j in locs.size():
			if i != j:
				var term := _gmul(locs[j], xi_inv)
				den = _gmul(den, (term | 1) if (term & 1) == 0 else (term & ~1))
		var mag := _gmul(_eval(omega, xi_inv), _ginv(den))
		var pos := out.size() - 1 - _log[locs[i]]
		if pos < 0:
			return PackedByteArray()
		out[pos] ^= mag
	return out
