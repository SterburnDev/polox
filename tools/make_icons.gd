extends SceneTree
## Makes every app icon from the artwork in assets/icon/polox_icon_source.png:
##   godot --headless --path . --script res://tools/make_icons.gd
## Writes into assets/icon/: polox.ico (Windows: 16-256 px), icon_{192,256,512}.png, pwa_{144,180,512}.png,
## android_foreground_432.png (the art inside the 72 dp safe area the launcher's mask shows),
## android_background_432.png (its blue), android_monochrome_432.png (a white silhouette: themed icons
## and the notification bar). export_presets.cfg and project.godot point at these.

const SRC := "res://assets/icon/polox_icon_source.png"
const OUT := "res://assets/icon/"


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if src == null or src.is_empty():
		print("[icons] FAILED: no artwork at ", SRC)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	var made := PackedStringArray()
	for n in [192, 256, 512]:
		_save(_scaled(src, n), "icon_%d.png" % n)
		made.append("icon_%d.png" % n)
	for n in [144, 180, 512]:
		_save(_scaled(src, n), "pwa_%d.png" % n)
	# Android adaptive icon: 108 dp layers, of which the mask shows about the middle 72 dp.
	var fg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	fg.fill(Color(0, 0, 0, 0))
	fg.blit_rect(_scaled(src, 288), Rect2i(0, 0, 288, 288), Vector2i(72, 72))
	_save(fg, "android_foreground_432.png")
	var bg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	bg.fill(_background_blue(src))
	_save(bg, "android_background_432.png")
	var mono := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	mono.fill(Color(0, 0, 0, 0))
	mono.blit_rect(_silhouette(_scaled(src, 288)), Rect2i(0, 0, 288, 288), Vector2i(72, 72))
	_save(mono, "android_monochrome_432.png")
	# Windows .ico: PNG-compressed entries (Windows Vista and later read them).
	var sizes := [16, 24, 32, 48, 64, 128, 256]
	var pngs: Array = sizes.map(func(n): return _scaled(src, n).save_png_to_buffer())
	var ico := PackedByteArray()
	ico.append_array(_u16(0) + _u16(1) + _u16(sizes.size()))
	var offset := 6 + 16 * sizes.size()
	for i in sizes.size():
		var n: int = sizes[i]
		var data: PackedByteArray = pngs[i]
		ico.append_array(PackedByteArray([n % 256, n % 256, 0, 0]) + _u16(1) + _u16(32) + _u32(data.size()) + _u32(offset))
		offset += data.size()
	for data in pngs:
		ico.append_array(data)
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT + "polox.ico"), FileAccess.WRITE)
	f.store_buffer(ico)
	f.close()
	print("[icons] ok: polox.ico (%s), icon_*, pwa_*, android_* in %s" % [", ".join(PackedStringArray(sizes.map(func(n): return str(n)))), OUT])
	quit(0)


static func _scaled(src: Image, n: int) -> Image:
	var img := src.duplicate() as Image
	img.resize(n, n, Image.INTERPOLATE_LANCZOS)
	return img


## The art's own blue, from its border (the sunburst behind the character).
static func _background_blue(src: Image) -> Color:
	var sum := Color(0, 0, 0, 0)
	var count := 0
	for i in 64:
		for p in [Vector2i(i * src.get_width() / 64, 2), Vector2i(src.get_width() - 3, i * src.get_height() / 64)]:
			var c := src.get_pixelv(p)
			if c.b > c.r and c.b > c.g:
				sum += c
				count += 1
	return Color(sum.r / count, sum.g / count, sum.b / count, 1.0) if count > 0 else Color("#5aa0ff")


## White where the character is (anything not the blue background), its dark eyes and mouth left out.
static func _silhouette(img: Image) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var blue_bg := c.h > 0.53 and c.h < 0.68 and c.s > 0.3
			var dark := c.v < 0.25
			out.set_pixel(x, y, Color(1, 1, 1, 0.0 if blue_bg or dark else 1.0))
	return out


static func _save(img: Image, name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUT + name))


static func _u16(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF])


static func _u32(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF])
