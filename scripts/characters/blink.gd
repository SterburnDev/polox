extends RefCounted
## Blinking, made from a character's own picture: it finds the eyes (one or two small dark spots in the
## upper middle of the face, inside the figure) and paints them shut with a thin eyelid line. Pictures where
## it can't find a clear pair of eyes simply don't blink (nothing is guessed). Cached per picture.

const SHUT := &"polox_eyes_shut"   # the picture with its eyes closed (metadata on the picture)


## Kept on the picture itself, so it lives exactly as long as the picture does. (Until 1.27 a list keyed
## by the picture's id held up to 128 closed-eye pictures, and every rebuilt friend added new ones.)
static func texture_for(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	# Eye detection is a cosmetic pixel scan, not a reason to stall an Android
	# frame on a full-resolution photo. Keep large custom pictures unchanged.
	if maxi(tex.get_width(), tex.get_height()) > 512:
		return null
	if tex.has_meta(SHUT):
		var kept: Variant = tex.get_meta(SHUT)
		return kept if kept is Texture2D else null
	var img: Image = preload("res://scripts/characters/transform_fx.gd").source_image(tex)
	var out: Texture2D = null
	if img and not img.is_empty():
		var shut := closed_eyes(img)
		if shut:
			out = ImageTexture.create_from_image(shut)
	tex.set_meta(SHUT, out if out else false)   # (false: looked, no clear eyes)
	return out


static func _luma(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.59 + c.b * 0.11


## The picture with its eyes closed, or null when no clear eyes were found.
static func closed_eyes(src: Image) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w < 8 or h < 8:
		return null
	var y0 := int(h * 0.15)
	var y1 := int(h * 0.58)
	var x0 := int(w * 0.18)
	var x1 := int(w * 0.82)
	var dark := {}
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			if c.a < 0.6 or _luma(c) > 0.28:
				continue
			# Inside the figure: an eye has the face all round it (outlines touch the transparent outside).
			var inside := true
			for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
				var p: Vector2i = Vector2i(x, y) + d
				if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or img.get_pixelv(p).a < 0.6:
					inside = false
			if inside:
				dark[Vector2i(x, y)] = true
	# Small dark spots (4-connected).
	var seen := {}
	var spots: Array = []
	for p in dark:
		if seen.has(p):
			continue
		var comp: Array = []
		var q: Array = [p]
		seen[p] = true
		while not q.is_empty():
			var c: Vector2i = q.pop_back()
			comp.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if dark.has(n) and not seen.has(n):
					seen[n] = true
					q.append(n)
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-1, -1)
		for c in comp:
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		var size := hi - lo + Vector2i.ONE
		if comp.size() <= maxi(4, w * h / 120) and size.x <= maxi(3, w / 6) and size.y <= maxi(3, h / 6):
			spots.append({"cells": comp, "lo": lo, "hi": hi})
	if spots.is_empty() or spots.size() > 3:
		return null
	if spots.size() >= 2:
		# A pair: about level with each other.
		spots.sort_custom(func(a, b): return (a.cells as Array).size() > (b.cells as Array).size())
		spots = spots.slice(0, 2)
		var ca: float = (spots[0].lo.y + spots[0].hi.y) / 2.0
		var cb: float = (spots[1].lo.y + spots[1].hi.y) / 2.0
		if absf(ca - cb) > maxf(2.0, h / 24.0):
			return null
	for s in spots:
		var lo: Vector2i = s.lo
		var hi: Vector2i = s.hi
		var skin := img.get_pixel(clampi((lo.x + hi.x) / 2, 0, w - 1), clampi(lo.y - 2, 0, h - 1))
		if skin.a < 0.6 or _luma(skin) < 0.3:
			skin = img.get_pixel(clampi(hi.x + 2, 0, w - 1), clampi((lo.y + hi.y) / 2, 0, h - 1))
		var lid := Color(0.18, 0.14, 0.2, 1.0)
		for c in s.cells:
			img.set_pixelv(c, skin)
		for x in range(lo.x, hi.x + 1):
			img.set_pixel(x, hi.y, lid)
	return img
