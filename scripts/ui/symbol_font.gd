extends RefCounted
## Pixel-art symbols and emoji for systems without fallback fonts. In the
## browser (the phone build) the game font has no ♥ ✓ ☁ 📱 ... and there are
## no system fonts to borrow them from, so they'd show as hex boxes. This
## draws each one in code (12 x 12, white, so text colour tints it) and adds
## them to the default font as a fallback. On a PC the system's own emoji
## are used instead; --pixel-symbols forces these for testing.
## Tags: [EASTER_EGG]

const PixelArt := preload("res://scripts/characters/pixel_art.gd")

const SIZE := 16          # the font's design size; glyphs scale with the text
const CELL := 12
const ASCENT := 13
const DESCENT := 3
const W := Color(1, 1, 1, 1)
const H := Color(1, 1, 1, 0.5)   # half-tone shading
const CLEAR := Color(0, 0, 0, 0)

## Every symbol the game's own text uses (tests check none is missing).
const SYMBOLS := "✓✗✕★⭐✦✨▶◀▼■●○▦♥💜♪⟳⟲↶↷→⇋⚠☁☰⋯📱🌙📦🍵🗝🌸🍄🏠🌊🔥🎸🐱🦊🐸🌵🍰🎀👾🕯☂🪐🎈📚🧸🎲👁🔒📍💬🌱←↑↓⌫💻🛠⚔🛡🗺🌀☀📖⏯👀🎁⧉▴✋"

static var _font: FontFile = null


static func wanted() -> bool:
	return OS.has_feature("web") or OS.has_feature("android") or "--pixel-symbols" in OS.get_cmdline_user_args()


static func active() -> bool:
	return _font != null and _font in ThemeDB.fallback_font.fallbacks


## Adds the symbols behind the default font (once).
static func install() -> void:
	if active():
		return
	var base: Font = ThemeDB.fallback_font
	var fb: Array[Font] = []
	fb.assign(base.fallbacks)
	fb.append(font())
	base.fallbacks = fb


static func font() -> FontFile:
	if _font:
		return _font
	var chars := SYMBOLS
	var cols := 16
	var rows := ceili(chars.length() / float(cols))
	var pitch := CELL + 2
	var atlas := Image.create(cols * pitch, rows * pitch, false, Image.FORMAT_RGBA8)
	atlas.fill(CLEAR)
	var f := FontFile.new()
	f.font_name = "Polox Symbols"
	f.fixed_size = SIZE
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	f.allow_system_fallback = false
	f.modulate_color_glyphs = true
	var sz := Vector2i(SIZE, 0)
	f.set_cache_ascent(0, SIZE, ASCENT)
	f.set_cache_descent(0, SIZE, DESCENT)
	for i in chars.length():
		var cp := chars.unicode_at(i)
		var cell := Vector2i((i % cols) * pitch + 1, (i / cols) * pitch + 1)
		atlas.blit_rect(glyph(chars[i]), Rect2i(0, 0, CELL, CELL), cell)
		f.set_glyph_texture_idx(0, sz, cp, 0)
		f.set_glyph_uv_rect(0, sz, cp, Rect2(Vector2(cell), Vector2(CELL, CELL)))
		f.set_glyph_size(0, sz, cp, Vector2(CELL, CELL))
		f.set_glyph_offset(0, sz, cp, Vector2(1, -11))
		f.set_glyph_advance(0, SIZE, cp, Vector2(CELL + 2, 0))
	f.set_texture_image(0, sz, 0, atlas)
	_font = f
	return f


## Emoji the game can't draw (an AI's 🥺, say) are dropped rather than shown
## as boxes, but only where the pixel symbols stand in for system fonts.
static func displayable(text: String) -> String:
	if not active():
		return text
	var out := ""
	for i in text.length():
		var cp := text.unicode_at(i)
		var emoji := (cp >= 0x1F000 and cp <= 0x1FAFF) or (cp >= 0x2600 and cp <= 0x27BF) or (cp >= 0x2B00 and cp <= 0x2BFF) or cp == 0xFE0F or cp == 0x200D
		if emoji and not SYMBOLS.contains(text[i]):
			continue
		out += text[i]
	return out


static func _poly(img: Image, pts: Array, c: Color = W) -> void:
	PixelArt.polygon(img, PackedVector2Array(pts), c)


static func _star(img: Image, cx: float, cy: float, r_out: float, r_in: float, points: int, c: Color = W) -> void:
	var pts: Array = []
	for k in points * 2:
		var a := -PI / 2.0 + k * PI / points
		var r := r_out if k % 2 == 0 else r_in
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	_poly(img, pts, c)


static func _heart(img: Image) -> void:
	PixelArt.ellipse(img, 3.5, 4.2, 3.0, 3.0, W)
	PixelArt.ellipse(img, 8.5, 4.2, 3.0, 3.0, W)
	_poly(img, [Vector2(0.4, 5.0), Vector2(11.6, 5.0), Vector2(6.0, 11.2)])


## A circle arrow turning clockwise (mirror it for the other way).
static func _turn(img: Image) -> void:
	PixelArt.ring(img, 5.5, 6.0, 5.0, 3.4, W)
	PixelArt.rect(img, 7, 5, 11, 8, CLEAR)
	_poly(img, [Vector2(6.8, 4.6), Vector2(12.0, 4.6), Vector2(9.4, 8.0)])


## The top half of a circle with an arrowhead on its right end (redo).
static func _arc(img: Image) -> void:
	PixelArt.ring(img, 6.0, 8.0, 5.2, 3.5, W)
	PixelArt.rect(img, 0, 8, 11, 11, CLEAR)
	_poly(img, [Vector2(7.6, 7.2), Vector2(12.0, 7.2), Vector2(9.8, 10.6)])


static func glyph(ch: String) -> Image:
	var img := PixelArt.blank(CELL)
	match ch:
		"✓":
			PixelArt.line(img, Vector2(1.5, 6.5), Vector2(4.5, 9.5), W, 2)
			PixelArt.line(img, Vector2(4.5, 9.5), Vector2(10.5, 2.5), W, 2)
		"✗", "✕":
			PixelArt.line(img, Vector2(2, 2), Vector2(9.5, 9.5), W, 2)
			PixelArt.line(img, Vector2(9.5, 2), Vector2(2, 9.5), W, 2)
		"★", "⭐":
			_star(img, 6.0, 6.6, 6.2, 2.6, 5)
		"✦":
			_star(img, 6.0, 6.0, 6.2, 2.4, 4)
		"✨":
			_star(img, 4.6, 4.6, 4.8, 1.9, 4)
			_star(img, 9.6, 9.0, 2.8, 1.1, 4)
			PixelArt.px(img, [Vector2i(2, 10), Vector2i(10, 2)], W)
		"▶":
			_poly(img, [Vector2(2, 1), Vector2(11, 6), Vector2(2, 11)])
		"◀":
			_poly(img, [Vector2(10, 1), Vector2(1, 6), Vector2(10, 11)])
		"▼":
			_poly(img, [Vector2(1, 3), Vector2(11, 3), Vector2(6, 10)])
		"■":
			PixelArt.rect(img, 2, 2, 9, 9, W)
		"●":
			PixelArt.ellipse(img, 6.0, 6.0, 4.6, 4.6, W)
		"○":
			PixelArt.ring(img, 6.0, 6.0, 4.6, 3.2, W)
		"▦":
			for y in range(1, 11):
				for x in range(1, 11):
					if x in [1, 4, 7, 10] or y in [1, 4, 7, 10]:
						img.set_pixel(x, y, W)
		"♥":
			_heart(img)
		"💜":
			_heart(img)
			PixelArt.rect(img, 2, 3, 3, 4, H)
		"♪":
			PixelArt.rect(img, 7, 1, 8, 8, W)
			PixelArt.line(img, Vector2(8, 1), Vector2(11, 4), W, 2)
			PixelArt.ellipse(img, 5.2, 9.0, 3.0, 2.2, W)
		"⟳":
			_turn(img)
		"⟲":
			_turn(img)
			img.flip_x()
		"↷":
			_arc(img)
		"↶":
			_arc(img)
			img.flip_x()
		"→":
			PixelArt.rect(img, 0, 5, 7, 6, W)
			_poly(img, [Vector2(6, 1.5), Vector2(12, 6), Vector2(6, 10.5)])
		"←":
			img = glyph("→")
			img.flip_x()
		"↑":
			img = glyph("→")
			img.rotate_90(COUNTERCLOCKWISE)
		"↓":
			img = glyph("→")
			img.rotate_90(CLOCKWISE)
		"⌫":
			_poly(img, [Vector2(0, 6), Vector2(4, 1), Vector2(12, 1), Vector2(12, 11), Vector2(4, 11)])
			PixelArt.line(img, Vector2(6, 4), Vector2(10, 8), CLEAR, 1)
			PixelArt.line(img, Vector2(10, 4), Vector2(6, 8), CLEAR, 1)
		"💻":
			PixelArt.rect(img, 2, 1, 9, 7, W)
			PixelArt.rect(img, 3, 2, 8, 6, H)
			_poly(img, [Vector2(1, 8), Vector2(11, 8), Vector2(12, 11), Vector2(0, 11)])
		"🛠":
			PixelArt.line(img, Vector2(2, 10), Vector2(7.5, 4.5), W, 2)
			PixelArt.ring(img, 8.6, 3.4, 3.0, 1.3, W)
			PixelArt.rect(img, 9, 0, 11, 2, CLEAR)
		"⚔":
			PixelArt.line(img, Vector2(1.5, 1.5), Vector2(10, 10), W, 1)
			PixelArt.line(img, Vector2(10.5, 1.5), Vector2(2, 10), W, 1)
			PixelArt.rect(img, 7, 9, 11, 10, W)
			PixelArt.rect(img, 1, 9, 4, 10, W)
		"🛡":
			_poly(img, [Vector2(1, 1), Vector2(11, 1), Vector2(11, 6), Vector2(6, 11.5), Vector2(1, 6)])
			PixelArt.rect(img, 5, 2, 6, 9, H)
		"🗺":
			_poly(img, [Vector2(0, 2), Vector2(4, 1), Vector2(8, 2), Vector2(12, 1), Vector2(12, 10), Vector2(8, 11), Vector2(4, 10), Vector2(0, 11)])
			PixelArt.rect(img, 4, 1, 4, 10, H)
			PixelArt.rect(img, 8, 2, 8, 11, H)
		"☀":
			PixelArt.ellipse(img, 6.0, 6.0, 2.8, 2.8, W)
			for k in 8:
				var a := TAU * k / 8.0
				PixelArt.line(img, Vector2(6, 6) + Vector2.from_angle(a) * 4.0, Vector2(6, 6) + Vector2.from_angle(a) * 5.8, W, 1)
		"📖":
			_poly(img, [Vector2(0, 2), Vector2(5.5, 3), Vector2(5.5, 11), Vector2(0, 10)])
			_poly(img, [Vector2(6.5, 3), Vector2(12, 2), Vector2(12, 10), Vector2(6.5, 11)])
			PixelArt.rect(img, 1, 5, 4, 5, H)
			PixelArt.rect(img, 8, 5, 11, 5, H)
		"⏯":
			_poly(img, [Vector2(0, 2), Vector2(5.5, 6), Vector2(0, 10)])
			PixelArt.rect(img, 7, 2, 8, 10, W)
			PixelArt.rect(img, 10, 2, 11, 10, W)
		"🌀":
			PixelArt.ring(img, 6.0, 6.0, 5.4, 4.0, W)
			PixelArt.ring(img, 6.6, 6.4, 2.8, 1.6, W)
			PixelArt.rect(img, 0, 5, 3, 7, CLEAR)
		"⇋":
			PixelArt.rect(img, 1, 3, 11, 4, W)
			_poly(img, [Vector2(0, 5), Vector2(4.5, 0.5), Vector2(4.5, 5)])
			PixelArt.rect(img, 0, 7, 10, 8, W)
			_poly(img, [Vector2(12, 7), Vector2(7.5, 11.5), Vector2(7.5, 7)])
		"⚠":
			_poly(img, [Vector2(6, -0.5), Vector2(12.4, 11), Vector2(-0.4, 11)])
			PixelArt.rect(img, 5, 3, 6, 7, CLEAR)
			PixelArt.rect(img, 5, 9, 6, 9, CLEAR)
		"☁":
			PixelArt.ellipse(img, 3.8, 7.6, 3.4, 2.8, W)
			PixelArt.ellipse(img, 7.2, 5.6, 3.8, 3.8, W)
			PixelArt.ellipse(img, 9.6, 8.0, 2.4, 2.2, W)
			PixelArt.rect(img, 2, 8, 10, 10, W)
		"☰":
			for y in [2, 5, 8]:
				PixelArt.rect(img, 1, y, 10, y + 1, W)
		"⋯":
			for x in [1, 5, 9]:
				PixelArt.rect(img, x, 6, x + 1, 7, W)
		"📱":
			PixelArt.rect(img, 3, 0, 8, 11, W)
			PixelArt.rect(img, 4, 1, 7, 8, H)
			PixelArt.rect(img, 5, 10, 6, 10, CLEAR)
		"🌙":
			PixelArt.ellipse(img, 6.0, 6.0, 5.2, 5.2, W)
			PixelArt.ellipse(img, 8.8, 4.2, 4.2, 4.2, CLEAR)
		"📦":
			PixelArt.rect(img, 1, 5, 10, 11, W)
			PixelArt.rect(img, 0, 2, 11, 4, W)
			PixelArt.rect(img, 5, 2, 6, 11, H)
		"🍵":
			_poly(img, [Vector2(1, 4), Vector2(11, 4), Vector2(9.5, 11), Vector2(2.5, 11)])
			PixelArt.rect(img, 2, 4, 9, 5, H)
			PixelArt.px(img, [Vector2i(4, 0), Vector2i(4, 1), Vector2i(5, 2), Vector2i(7, 0), Vector2i(7, 1), Vector2i(8, 2)], H)
		"🗝":
			PixelArt.ring(img, 3.5, 6.0, 3.2, 1.5, W)
			PixelArt.rect(img, 6, 5, 11, 6, W)
			PixelArt.rect(img, 9, 7, 9, 8, W)
			PixelArt.rect(img, 11, 7, 11, 9, W)
		"🌸":
			for k in 5:
				var a := -PI / 2.0 + k * TAU / 5.0
				PixelArt.ellipse(img, 6.0 + cos(a) * 3.4, 6.2 + sin(a) * 3.4, 2.3, 2.3, W)
			PixelArt.ellipse(img, 6.0, 6.2, 1.6, 1.6, CLEAR)
			PixelArt.rect(img, 5, 5, 6, 6, H)
		"🍄":
			PixelArt.ellipse(img, 6.0, 6.0, 6.0, 5.0, W)
			PixelArt.rect(img, 0, 6, 11, 11, CLEAR)
			PixelArt.rect(img, 4, 6, 7, 11, W)
			PixelArt.px(img, [Vector2i(3, 3), Vector2i(7, 2), Vector2i(8, 2), Vector2i(9, 4)], CLEAR)
		"🏠":
			_poly(img, [Vector2(-0.5, 6.5), Vector2(6, 0), Vector2(12.5, 6.5)])
			PixelArt.rect(img, 2, 6, 9, 11, W)
			PixelArt.rect(img, 5, 8, 6, 11, CLEAR)
		"🌊":
			for x in CELL:
				PixelArt.rect(img, x, roundi(5.5 + 2.2 * sin(x * 0.75 + 0.5)), x, 10, W)
			for x in CELL:
				img.set_pixel(x, 11, H)
		"🔥":
			_poly(img, [Vector2(6, -0.5), Vector2(9.5, 4), Vector2(10.6, 7.5), Vector2(9, 10.6), Vector2(6, 11.8), Vector2(3, 10.6), Vector2(1.4, 7.5), Vector2(3.4, 4.2), Vector2(5, 6)])
			_poly(img, [Vector2(6, 5.5), Vector2(8, 8.6), Vector2(6, 11), Vector2(4, 8.6)], H)
		"🎸":
			PixelArt.ellipse(img, 4.0, 8.0, 3.4, 3.2, W)
			PixelArt.ellipse(img, 6.0, 6.4, 2.2, 2.0, W)
			PixelArt.px(img, [Vector2i(4, 8)], CLEAR)
			PixelArt.line(img, Vector2(6, 6), Vector2(10.5, 1.5), W, 2)
			PixelArt.rect(img, 10, 0, 11, 1, W)
		"🐱":
			PixelArt.ellipse(img, 6.0, 7.2, 5.4, 4.4, W)
			_poly(img, [Vector2(0.6, 5.5), Vector2(1.6, -0.2), Vector2(5.2, 3.6)])
			_poly(img, [Vector2(11.4, 5.5), Vector2(10.4, -0.2), Vector2(6.8, 3.6)])
			PixelArt.rect(img, 3, 6, 3, 7, CLEAR)
			PixelArt.rect(img, 8, 6, 8, 7, CLEAR)
			PixelArt.px(img, [Vector2i(5, 9), Vector2i(6, 9)], CLEAR)
		"🦊":
			_poly(img, [Vector2(-0.4, 0), Vector2(4, 3.6), Vector2(8, 3.6), Vector2(12.4, 0), Vector2(10.6, 7), Vector2(6, 11.8), Vector2(1.4, 7)])
			_poly(img, [Vector2(3, 7.4), Vector2(9, 7.4), Vector2(6, 11.4)], H)
			PixelArt.px(img, [Vector2i(3, 5), Vector2i(8, 5)], CLEAR)
		"🐸":
			PixelArt.ellipse(img, 6.0, 7.6, 5.8, 4.0, W)
			PixelArt.ellipse(img, 3.0, 3.6, 2.4, 2.4, W)
			PixelArt.ellipse(img, 9.0, 3.6, 2.4, 2.4, W)
			PixelArt.px(img, [Vector2i(2, 3), Vector2i(9, 3)], CLEAR)
			PixelArt.rect(img, 3, 9, 8, 9, CLEAR)
		"🌵":
			PixelArt.rect(img, 5, 1, 7, 11, W)
			PixelArt.rect(img, 1, 4, 2, 8, W)
			PixelArt.rect(img, 1, 7, 5, 8, W)
			PixelArt.rect(img, 10, 3, 11, 6, W)
			PixelArt.rect(img, 7, 5, 11, 6, W)
		"🍰":
			_poly(img, [Vector2(0.5, 5), Vector2(11.5, 3), Vector2(11.5, 11), Vector2(0.5, 11)])
			PixelArt.rect(img, 1, 7, 11, 7, H)
			PixelArt.ellipse(img, 9.0, 1.6, 1.6, 1.6, W)
		"🎀":
			_poly(img, [Vector2(6, 5), Vector2(-0.5, 0.5), Vector2(-0.5, 9.5)])
			_poly(img, [Vector2(6, 5), Vector2(12.5, 0.5), Vector2(12.5, 9.5)])
			PixelArt.rect(img, 5, 3, 7, 6, W)
			_poly(img, [Vector2(5, 6), Vector2(2.5, 11.5), Vector2(5, 11.5)], H)
			_poly(img, [Vector2(7, 6), Vector2(9.5, 11.5), Vector2(7, 11.5)], H)
		"👾":
			var rows := ["..#......#..", "...#....#...", "..########..", ".##.####.##.", "############", "#.########.#", "#.#......#.#", "...##..##..."]
			for y in rows.size():
				for x in CELL:
					if str(rows[y])[x] == "#":
						img.set_pixel(x, y + 2, W)
		"🕯":
			PixelArt.rect(img, 4, 5, 7, 11, W)
			_poly(img, [Vector2(5.5, -0.4), Vector2(7.2, 2.8), Vector2(5.5, 4.4), Vector2(3.8, 2.8)], W)
			PixelArt.rect(img, 4, 5, 7, 5, H)
		"☂":
			PixelArt.ellipse(img, 6.0, 5.6, 6.0, 5.0, W)
			PixelArt.rect(img, 0, 6, 11, 11, CLEAR)
			PixelArt.rect(img, 6, 5, 6, 10, W)
			PixelArt.px(img, [Vector2i(5, 11), Vector2i(4, 11), Vector2i(3, 10)], W)
		"🪐":
			PixelArt.ellipse(img, 6.0, 6.0, 3.4, 3.4, W)
			for y in CELL:
				for x in CELL:
					var dx := (x + 0.5 - 6.0) / 6.0
					var dy := (y + 0.5 - 6.6) / 2.2
					var d := dx * dx + dy * dy
					if d >= 0.62 and d <= 1.0:
						img.set_pixel(x, y, W)
					elif d > 1.0 and d <= 1.5 and y >= 6:
						img.set_pixel(x, y, CLEAR)   # a dark gap so the ring sits in front
		"🎈":
			PixelArt.ellipse(img, 6.0, 4.6, 4.2, 4.6, W)
			_poly(img, [Vector2(5, 9), Vector2(7, 9), Vector2(6, 10.5)])
			PixelArt.px(img, [Vector2i(6, 10), Vector2i(5, 11)], H)
			PixelArt.px(img, [Vector2i(4, 2), Vector2i(4, 3)], H)
		"📚":
			PixelArt.rect(img, 1, 2, 3, 11, W)
			PixelArt.rect(img, 5, 0, 7, 11, W)
			_poly(img, [Vector2(8.6, 2.6), Vector2(10.4, 2.0), Vector2(12.4, 11.0), Vector2(10.6, 11.6)])
			PixelArt.rect(img, 1, 4, 3, 4, H)
			PixelArt.rect(img, 5, 2, 7, 2, H)
		"🧸":
			PixelArt.ellipse(img, 2.8, 1.8, 1.6, 1.6, W)
			PixelArt.ellipse(img, 9.2, 1.8, 1.6, 1.6, W)
			PixelArt.ellipse(img, 6.0, 4.4, 3.4, 3.2, W)
			PixelArt.ellipse(img, 6.0, 9.2, 4.2, 2.8, W)
			PixelArt.px(img, [Vector2i(4, 4), Vector2i(7, 4)], CLEAR)
			PixelArt.px(img, [Vector2i(5, 6), Vector2i(6, 6)], H)
		"🎲":
			PixelArt.rect(img, 1, 1, 10, 10, W)
			for p in [2, 5, 8]:
				PixelArt.rect(img, p, p, p + 1, p + 1, CLEAR)
		"🎁":
			PixelArt.rect(img, 1, 5, 10, 11, W)
			PixelArt.rect(img, 0, 3, 11, 5, W)
			PixelArt.rect(img, 5, 3, 6, 11, H)
			PixelArt.px(img, [Vector2i(3, 1), Vector2i(4, 2), Vector2i(8, 1), Vector2i(7, 2)], W)
		"⧉":
			for i in range(0, 8):
				PixelArt.px(img, [Vector2i(i, 0), Vector2i(i, 7), Vector2i(0, i), Vector2i(7, i)], W)
				PixelArt.px(img, [Vector2i(i + 4, 4), Vector2i(i + 4, 11), Vector2i(4, i + 4), Vector2i(11, i + 4)], W)
		"▴":
			_poly(img, [Vector2(2, 9), Vector2(10, 9), Vector2(6, 3)])
		"✋":
			PixelArt.rect(img, 3, 6, 9, 11, W)
			for fx in [3, 5, 7, 9]:
				PixelArt.rect(img, fx, 1 if fx in [5, 7] else 2, fx + 1, 6, W)
			PixelArt.rect(img, 0, 6, 2, 7, W)
		"👀":
			for cx in [3.0, 9.0]:
				PixelArt.ellipse(img, cx, 6.0, 2.9, 4.4, W)
				PixelArt.ellipse(img, cx + 0.9, 7.0, 1.3, 1.6, CLEAR)
		"👁":
			PixelArt.ellipse(img, 6.0, 6.0, 5.9, 3.4, W)
			PixelArt.ellipse(img, 6.0, 6.0, 2.4, 2.4, CLEAR)
			PixelArt.ellipse(img, 6.0, 6.0, 1.1, 1.1, W)
		"🔒":
			PixelArt.ring(img, 6.0, 5.0, 3.8, 2.2, W)
			PixelArt.rect(img, 1, 5, 10, 11, W)
			PixelArt.rect(img, 5, 7, 6, 9, CLEAR)
		"📍":
			PixelArt.ellipse(img, 6.0, 4.2, 4.0, 4.0, W)
			_poly(img, [Vector2(2.6, 6), Vector2(9.4, 6), Vector2(6, 12)])
			PixelArt.ellipse(img, 6.0, 4.2, 1.5, 1.5, CLEAR)
		"💬":
			PixelArt.rect(img, 0, 2, 11, 8, W)
			PixelArt.rect(img, 1, 1, 10, 9, W)
			PixelArt.px(img, [Vector2i(0, 2), Vector2i(11, 2), Vector2i(0, 8), Vector2i(11, 8)], CLEAR)
			_poly(img, [Vector2(2, 9), Vector2(5.5, 9), Vector2(1.5, 12)])
		"🌱":
			PixelArt.rect(img, 5, 5, 6, 11, W)
			PixelArt.ellipse(img, 3.0, 4.6, 2.8, 1.8, W)
			PixelArt.ellipse(img, 8.6, 3.2, 3.0, 2.0, W)
	return img
