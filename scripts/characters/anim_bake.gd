extends RefCounted
## Makes animation frames from one base picture (pixel operations, no AI):
## "Generate from base sprite" in the Animations tab, and the doll maker's
## built-in run cycle. Each state gets frames that read differently from the
## others: walk = a gentle bob and stride, run = a forward lean with a longer
## stride, jump = stretched up, fall = leaning back, land = squashed.

const FPS := {"idle": 3.0, "walk": 8.0, "run": 12.0, "jump": 1.0, "fall": 1.0, "land": 1.0}


## The frames for one state, from `base` (any size, transparent background).
static func frames_for(state: String, base: Image) -> Array:
	var b := base.duplicate() as Image
	b.convert(Image.FORMAT_RGBA8)
	match state:
		"idle":
			return [b, shift(b, Vector2i(0, 1))]
		"walk":
			return [stride(b, 1), shift(b, Vector2i(0, -1)), stride(b, -1), shift(b, Vector2i(0, -1))]
		"run":
			var lean := shear(b, 0.14)
			return [stride(lean, 2), shift(lean, Vector2i(0, -2)), stride(lean, -2), shift(lean, Vector2i(0, -2))]
		"jump":
			return [scale_bottom(b, Vector2(0.88, 1.12))]
		"fall":
			return [shear(b, -0.12)]
		"land":
			return [scale_bottom(b, Vector2(1.14, 0.84))]
	return [b]


## Moves the whole picture (empty pixels come in).
static func shift(img: Image, by: Vector2i) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), by)
	return out


## A lean: each row slides sideways in proportion to its height above the feet.
static func shear(img: Image, amount: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var dx := roundi((h - 1 - y) * amount)
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and x + dx >= 0 and x + dx < w:
				out.set_pixel(x + dx, y, c)
	return out


## A stride: the left and right halves of the lowest fifth (the legs) move
## apart by `step` px (negative = the other leg forward), one lifted a pixel.
static func stride(img: Image, step: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var top := h - maxi(3, h / 5)
	var out := img.duplicate() as Image
	for y in range(top, h):
		for x in w:
			out.set_pixel(x, y, Color(0, 0, 0, 0))
	var mid := w / 2
	for y in range(top, h):
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var left := x < mid
			var dx := -step if left else step
			var dy := -1 if (left == (step > 0)) else 0
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and nx < w and ny >= 0 and ny < h:
				out.set_pixel(nx, ny, c)
	return out


## Squash or stretch, keeping the feet on the bottom row and the middle centred.
static func scale_bottom(img: Image, s: Vector2) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var nw := maxi(1, roundi(w * s.x))
	var nh := maxi(1, roundi(h * s.y))
	var scaled := img.duplicate() as Image
	scaled.resize(nw, nh, Image.INTERPOLATE_NEAREST)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var at := Vector2i((w - nw) / 2, h - nh)
	var src := Rect2i(Vector2i.ZERO, scaled.get_size())
	# Crop what doesn't fit.
	if at.x < 0:
		src.position.x = -at.x
		src.size.x = w
		at.x = 0
	if at.y < 0:
		src.position.y = -at.y
		src.size.y = h
		at.y = 0
	out.blit_rect(scaled, src, at)
	return out


## The doll maker's run cycle (built in for doll players): 4 frames from the doll's own picture.
static func doll_run(base: Image) -> Array:
	return frames_for("run", base)


static func textures(images: Array) -> Array:
	var out: Array = []
	for img in images:
		out.append(ImageTexture.create_from_image(img))
	return out
