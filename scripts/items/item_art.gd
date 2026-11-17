extends RefCounted
## Auto-generated item icons (32x32), drawn in code from a shape name and a
## main colour. Every item can use one of these until (or instead of) a
## drawn or imported picture.

const PixelArt := preload("res://scripts/characters/pixel_art.gd")

const SIZE := 32
const INK := Color("#22183d")
const WOOD := Color("#a8703f")
const STEEL := Color("#dfe6f0")
const GOLD := Color("#ffd166")
const CREAM := Color("#fffaf0")
const LEAF := Color("#7ad6b0")

## Shapes offered per category (the first is the default).
const SHAPES := {
	"weapon": ["sword", "wand", "hammer", "bow", "spoon"],
	"armor": ["helmet", "hat", "shirt", "robe", "ring", "amulet", "scarf"],
	"consumable": ["cookie", "potion", "apple", "candy", "cup", "cake"],
	"keepsake": ["star", "shell", "letter", "gem", "flower", "book", "pebble", "music_box"],
}
const ARMOR_DEFAULTS := {"head": "helmet", "body": "shirt", "accessory": "amulet"}

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func default_shape(category: String, slot: String = "") -> String:
	if category == "armor":
		return str(ARMOR_DEFAULTS.get(slot, "helmet"))
	return str(SHAPES.get(category, SHAPES.keepsake)[0])


static func all_shapes() -> PackedStringArray:
	var out := PackedStringArray()
	for k in SHAPES:
		for s in SHAPES[k]:
			out.append(str(s))
	return out


static func texture(shape: String, color: String) -> Texture2D:
	var key := shape + "|" + color
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(icon(shape, color))
	return _cache[key]


static func icon(shape: String, color: String) -> Image:
	var c := Color.from_string(color, Color("#e8b04a"))
	var img := PixelArt.blank(SIZE)
	match shape:
		"sword":
			PixelArt.line(img, Vector2(10, 21), Vector2(25, 6), STEEL, 3)
			PixelArt.line(img, Vector2(12, 20), Vector2(25, 7), STEEL.lightened(0.6), 1)
			PixelArt.line(img, Vector2(6, 17), Vector2(14, 25), c, 2)
			PixelArt.line(img, Vector2(9, 22), Vector2(5, 26), WOOD, 2)
			PixelArt.rect(img, 3, 27, 4, 28, c)
		"wand":
			PixelArt.line(img, Vector2(7, 26), Vector2(19, 14), WOOD, 3)
			_star(img, Vector2(22, 10), 7.0, 3.0, c)
		"hammer":
			PixelArt.rect(img, 14, 12, 17, 28, WOOD)
			PixelArt.rect(img, 8, 5, 23, 12, c)
			PixelArt.rect(img, 8, 5, 23, 6, c.lightened(0.35))
		"bow":
			for i in 23:
				var y := 4 + i
				var x := 10.0 + sin(float(i) / 22.0 * PI) * 10.0
				PixelArt.rect(img, int(x), y, int(x) + 2, y, c)
			PixelArt.line(img, Vector2(11, 4), Vector2(11, 26), CREAM, 1)
		"spoon":
			PixelArt.line(img, Vector2(8, 26), Vector2(18, 15), WOOD, 3)
			PixelArt.ellipse(img, 21.5, 10.5, 5.0, 6.0, c)
			PixelArt.ellipse(img, 20.5, 9.5, 2.0, 2.5, c.lightened(0.35))
		"helmet":
			PixelArt.ellipse(img, 16, 18, 10, 11, c)
			PixelArt.rect(img, 0, 18, 31, 31, Color(0, 0, 0, 0))
			PixelArt.rect(img, 5, 17, 26, 20, c.darkened(0.2))
			PixelArt.rect(img, 10, 12, 21, 13, INK)
			PixelArt.rect(img, 15, 3, 16, 7, GOLD)
		"hat":
			PixelArt.polygon(img, PackedVector2Array([Vector2(16, 2), Vector2(24, 22), Vector2(8, 22)]), c)
			PixelArt.rect(img, 4, 22, 27, 25, c.darkened(0.2))
			_star(img, Vector2(15, 14), 3.5, 1.5, GOLD)
		"shirt":
			PixelArt.rect(img, 10, 9, 21, 27, c)
			PixelArt.rect(img, 4, 9, 9, 16, c)
			PixelArt.rect(img, 22, 9, 27, 16, c)
			PixelArt.rect(img, 14, 9, 17, 11, Color(0, 0, 0, 0))
		"robe":
			PixelArt.polygon(img, PackedVector2Array([Vector2(11, 5), Vector2(21, 5), Vector2(26, 29), Vector2(6, 29)]), c)
			PixelArt.rect(img, 5, 8, 9, 15, c.darkened(0.15))
			PixelArt.rect(img, 22, 8, 26, 15, c.darkened(0.15))
			PixelArt.rect(img, 9, 17, 22, 18, GOLD)
		"ring":
			PixelArt.ring(img, 16, 20, 8.5, 5.0, c)
			PixelArt.polygon(img, PackedVector2Array([Vector2(16, 3), Vector2(21, 8), Vector2(16, 13), Vector2(11, 8)]), Color("#ff8fab"))
		"amulet":
			PixelArt.line(img, Vector2(7, 3), Vector2(16, 15), GOLD, 1)
			PixelArt.line(img, Vector2(25, 3), Vector2(16, 15), GOLD, 1)
			PixelArt.ellipse(img, 16, 21, 6, 7, c)
			PixelArt.rect(img, 14, 18, 15, 19, c.lightened(0.5))
		"scarf":
			PixelArt.rect(img, 5, 9, 26, 15, c)
			PixelArt.rect(img, 17, 15, 22, 28, c)
			for x in range(6, 26, 4):
				PixelArt.rect(img, x, 9, x + 1, 15, c.lightened(0.35))
		"cookie":
			PixelArt.ellipse(img, 16, 16, 12, 12, c)
			for p in [Vector2i(11, 11), Vector2i(19, 9), Vector2i(21, 18), Vector2i(13, 20), Vector2i(17, 15)]:
				PixelArt.rect(img, p.x, p.y, p.x + 1, p.y + 1, Color("#5a3b22"))
		"potion":
			PixelArt.ellipse(img, 16, 20, 9, 9, c)
			PixelArt.rect(img, 13, 6, 18, 12, CREAM.darkened(0.1))
			PixelArt.rect(img, 12, 3, 19, 6, WOOD)
			PixelArt.rect(img, 11, 15, 13, 18, CREAM)
		"apple":
			PixelArt.ellipse(img, 16, 18, 10, 10, c)
			PixelArt.rect(img, 15, 5, 16, 9, WOOD)
			PixelArt.ellipse(img, 20, 7, 3, 2, LEAF)
			PixelArt.rect(img, 11, 13, 12, 15, c.lightened(0.5))
		"candy":
			PixelArt.polygon(img, PackedVector2Array([Vector2(3, 10), Vector2(11, 16), Vector2(3, 22)]), c.lightened(0.3))
			PixelArt.polygon(img, PackedVector2Array([Vector2(29, 10), Vector2(21, 16), Vector2(29, 22)]), c.lightened(0.3))
			PixelArt.ellipse(img, 16, 16, 7.5, 6.5, c)
			PixelArt.rect(img, 13, 13, 14, 14, CREAM)
		"cup":
			PixelArt.rect(img, 7, 12, 21, 26, c)
			PixelArt.ring(img, 22, 19, 5.0, 2.5, c)
			PixelArt.rect(img, 9, 12, 19, 13, Color("#8b5e3c"))
			for x in [10, 14, 18]:
				PixelArt.px(img, [Vector2i(x, 9), Vector2i(x + 1, 7), Vector2i(x, 5)], CREAM)
		"cake":
			PixelArt.rect(img, 5, 15, 26, 26, c)
			PixelArt.rect(img, 5, 12, 26, 15, CREAM)
			PixelArt.rect(img, 5, 20, 26, 21, CREAM.darkened(0.1))
			PixelArt.ellipse(img, 16, 9, 3, 3, Color("#ff5a6e"))
		"star":
			_star(img, Vector2(16, 16), 14.0, 6.0, c)
			PixelArt.rect(img, 12, 12, 13, 13, c.lightened(0.5))
		"shell":
			for i in 7:
				var a := PI + PI * float(i) / 6.0
				PixelArt.line(img, Vector2(16, 26), Vector2(16, 26) + Vector2(cos(a), sin(a)) * 13.0, c if i % 2 == 0 else c.lightened(0.3), 3)
			PixelArt.ellipse(img, 16, 25, 4, 3, c.darkened(0.2))
		"letter":
			PixelArt.rect(img, 4, 9, 27, 24, CREAM)
			PixelArt.line(img, Vector2(4, 9), Vector2(16, 18), CREAM.darkened(0.25), 1)
			PixelArt.line(img, Vector2(27, 9), Vector2(16, 18), CREAM.darkened(0.25), 1)
			PixelArt.ellipse(img, 16, 18, 3, 3, c)
		"gem":
			PixelArt.polygon(img, PackedVector2Array([Vector2(9, 6), Vector2(23, 6), Vector2(29, 13), Vector2(16, 28), Vector2(3, 13)]), c)
			PixelArt.polygon(img, PackedVector2Array([Vector2(9, 6), Vector2(16, 6), Vector2(12, 13), Vector2(3, 13)]), c.lightened(0.4))
			PixelArt.rect(img, 3, 13, 29, 13, c.darkened(0.2))
		"flower":
			PixelArt.line(img, Vector2(16, 18), Vector2(16, 30), LEAF.darkened(0.3), 2)
			PixelArt.ellipse(img, 21, 25, 3, 2, LEAF)
			for i in 5:
				var a := TAU * float(i) / 5.0 - PI / 2.0
				PixelArt.ellipse(img, 16 + cos(a) * 6.0, 11 + sin(a) * 6.0, 4, 4, c)
			PixelArt.ellipse(img, 16, 11, 3, 3, GOLD)
		"book":
			PixelArt.rect(img, 7, 5, 24, 27, c)
			PixelArt.rect(img, 21, 6, 24, 26, CREAM)
			PixelArt.rect(img, 7, 5, 9, 27, c.darkened(0.3))
			PixelArt.rect(img, 12, 11, 18, 12, GOLD)
		"pebble":
			PixelArt.ellipse(img, 16, 18, 11, 8, c)
			PixelArt.ellipse(img, 12, 15, 3, 2, c.lightened(0.5))
		"music_box":
			PixelArt.rect(img, 6, 14, 25, 27, c)
			PixelArt.rect(img, 5, 11, 26, 14, c.lightened(0.3))
			PixelArt.rect(img, 26, 18, 29, 19, GOLD)
			PixelArt.rect(img, 13, 3, 14, 9, INK)
			PixelArt.ellipse(img, 12, 9, 2, 1.5, INK)
		_:
			PixelArt.ellipse(img, 16, 16, 10, 10, c)
	PixelArt.outline(img, INK)
	return img


static func _star(img: Image, center: Vector2, r_out: float, r_in: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		pts.append(center + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	PixelArt.polygon(img, pts, c)
