extends RefCounted
## Transformations between the Light World and the Dream World (and into the Deep). You change between Real Me and Dream World Me;
## friends get a Dream World look generated from their own picture (darker, shifted towards violet,
## with a glowing outline) unless they have one drawn. The change itself is a short flash and a
## morph: drawn "transform in" / "transform out" frames from the Animations tab when there are any,
## else a generated one (the new picture appears pixel by pixel through a bright flash).

const AnimStore := preload("res://scripts/characters/anim_store.gd")

const FRAMES := 8
const GLOW := Color("#b48cff")
const MAX_MORPH_SIDE := 256
const MAX_VARIANT_SIDE := 512
const SOURCE_IMAGE := &"polox_source_image"


## Runtime pictures already exist on the CPU. Keep that source with the texture so
## realm transitions do not have to read it back from a mobile graphics driver.
static func texture_from_image(img: Image) -> ImageTexture:
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta(SOURCE_IMAGE, img)
	return tex


static func source_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	if tex.has_meta(SOURCE_IMAGE):
		return tex.get_meta(SOURCE_IMAGE)
	# Cosmetic effects never read a picture back from Android's GPU (an imported one may be stored
	# compressed there): without its CPU copy the effect is skipped.
	if OS.has_feature("android"):
		return null
	return tex.get_image()


static func _bounded(src: Image, limit: int) -> Image:
	if src == null or src.is_empty():
		return null
	var img := src.duplicate() as Image
	if img.is_compressed() and img.decompress() != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	var side := maxi(img.get_width(), img.get_height())
	if side > limit:
		var scale := float(limit) / side
		img.resize(maxi(1, roundi(img.get_width() * scale)), maxi(1, roundi(img.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	return img


## A friend's Dream World look, generated from their picture.
static func dark_variant(src: Image) -> Image:
	var img := _bounded(src, MAX_VARIANT_SIDE)
	if img == null:
		return null
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.1:
				var hsv_h := fposmod(c.h * 0.5 + 0.7, 1.0)
				out.set_pixel(x, y, Color.from_hsv(hsv_h, clampf(c.s * 0.6 + 0.3, 0.0, 1.0), clampf(c.v * 0.7, 0.0, 1.0), c.a))
	# The glowing outline: transparent pixels next to the figure.
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.1:
				continue
			var near := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and img.get_pixel(q.x, q.y).a > 0.1:
					near = true
					break
			if near:
				out.set_pixel(x, y, Color(GLOW, 0.9))
	return out


## The generated morph from `a` to `b` (same size or not): FRAMES pictures, the new one showing
## through more and more pixels, with a bright flash in the middle.
static func morph_frames(a: Image, b: Image) -> Array:
	a = _bounded(a, MAX_MORPH_SIDE)
	b = _bounded(b, MAX_MORPH_SIDE)
	if a == null or b == null:
		return []
	var size := Vector2i(maxi(a.get_width(), b.get_width()), maxi(a.get_height(), b.get_height()))
	var ia := _fit(a, size)
	var ib := _fit(b, size)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var order := PackedFloat32Array()
	order.resize(size.x * size.y)
	for i in order.size():
		order[i] = rng.randf()
	var out: Array = []
	for f in FRAMES:
		var t := float(f + 1) / FRAMES
		var flash := sin(t * PI) * 0.65
		var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		for y in size.y:
			for x in size.x:
				var c := ib.get_pixel(x, y) if order[y * size.x + x] < t else ia.get_pixel(x, y)
				if c.a > 0.05:
					c = c.lerp(Color(1, 1, 1, c.a), flash)
				img.set_pixel(x, y, c)
		out.append(img)
	return out


static func _fit(src: Image, size: Vector2i) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_size() == size:
		return img
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((size.x - img.get_width()) / 2, size.y - img.get_height()))
	return out


## Drawn frames for "transform_in" (Light -> Dark) or "transform_out" from the Animations tab, as
## textures; empty when none are drawn.
static func drawn_frames(target: Dictionary, state: String) -> Array:
	var a: Dictionary = AnimStore.anims_of(target).get(state, {})
	var out: Array = []
	for rel in a.get("frames", []):
		var tex: Texture2D = SaveManager.load_texture(str(rel))
		if tex:
			out.append(tex)
	return out


## Plays a transformation on an actor (its sprite shows each frame), then leaves `final` on it.
## Skippable through the Moment `m`; with Reduce motion it just swaps after a short fade.
static func play(actor: Node3D, frames: Array, final: Texture2D, m: Control, reduced: bool) -> void:
	if reduced or frames.is_empty():
		await m.wait(0.15)
		if is_instance_valid(actor):
			actor.set_texture(final)
		return
	var per := 0.6 / frames.size()
	actor.set_meta(&"polox_transforming", true)
	for f in frames:
		if not is_instance_valid(actor):
			return   # the place changed under it (the actor was replaced): nothing left to animate
		var tex: Texture2D = f if f is Texture2D else texture_from_image(f)
		actor.set_texture(tex)
		if await m.wait(per):
			break
	if is_instance_valid(actor):
		actor.set_texture(final)
		actor.remove_meta(&"polox_transforming")
