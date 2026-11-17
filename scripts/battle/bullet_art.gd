extends RefCounted
## What bullets look like and where they hurt. Built-in bullets are drawn in code (round hitboxes);
## bullets you draw in the Battle Maker are pictures in the world's battles/bullets/ folder, and
## their opaque pixels are the hitbox (pixel-exact: a thin crescent only hurts where it's drawn).

const JsonUtil := preload("res://scripts/core/json_util.gd")

const BUILTIN: PackedStringArray = ["dot", "drop", "leaf", "star", "ball", "bubble", "spark", "petal", "heart", "flake", "rock"]
const LABELS := {"dot": "Dot", "drop": "Raindrop", "leaf": "Leaf", "star": "Star", "ball": "Ball", "bubble": "Bubble", "spark": "Spark", "petal": "Petal", "heart": "Heart", "flake": "Snowflake", "rock": "Rock"}

static var _tex: Dictionary = {}     # custom id -> Texture2D
static var _mask: Dictionary = {}    # custom id -> PackedVector2Array (opaque pixel centres, from the middle)
static var _stamp: Dictionary = {}
static var _checked: Dictionary = {}
const CACHE_MAX := 24
const ATLAS := preload("res://assets/battles/bullets.svg")
const CELLS := {"dot": 0, "drop": 1, "leaf": 2, "star": 3, "ball": 4, "bubble": 5, "spark": 6, "petal": 7, "heart": 8, "flake": 9, "rock": 10}
static var _active_custom: Dictionary = {}
static var _active_root := ""


static func prepare_wave(wave: Dictionary) -> void:
	_active_custom.clear()
	_active_root = SaveManager.root
	for s in wave.get("spawners", []):
		var kind := str(s.get("bullet", "dot"))
		if kind.begins_with("custom:") and not _active_custom.has(kind):
			var id := kind.trim_prefix("custom:")
			var tex := custom_texture(id)
			_active_custom[kind] = {"texture": tex, "mask": _mask.get(bullets_dir().path_join(id + ".png"), PackedVector2Array())}


static func bullets_dir() -> String:
	return SaveManager.abs_path("battles").path_join("bullets")


static func kinds() -> Array:
	var out: Array = Array(BUILTIN)
	for f in JsonUtil.list_files(bullets_dir(), ["png"]):
		out.append("custom:" + str(f).get_basename())
	return out


static func label(kind: String) -> String:
	if kind.begins_with("custom:"):
		return "Drawn: " + kind.trim_prefix("custom:")
	return str(LABELS.get(kind, kind))


## Saves a drawn bullet (trimmed to its pixels, at most 48x48). Returns its id ("" if empty).
static func save_custom(img: Image) -> String:
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var used := src.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return ""
	var cut := src.get_region(used)
	if maxi(cut.get_width(), cut.get_height()) > 48:
		var k := 48.0 / maxi(cut.get_width(), cut.get_height())
		cut.resize(maxi(1, int(cut.get_width() * k)), maxi(1, int(cut.get_height() * k)), Image.INTERPOLATE_NEAREST)
	JsonUtil.ensure_dir(bullets_dir())
	var n := 1
	while FileAccess.file_exists(bullets_dir().path_join("bullet_%d.png" % n)):
		n += 1
	var id := "bullet_%d" % n
	cut.save_png(bullets_dir().path_join(id + ".png"))
	_tex.erase(bullets_dir().path_join(id + ".png"))
	_mask.erase(bullets_dir().path_join(id + ".png"))
	return id


static func custom_texture(id: String) -> Texture2D:
	if not preload("res://scripts/battle/battle_data.gd").safe_id(id):
		return null
	var p := bullets_dir().path_join(id + ".png")
	var now := Time.get_ticks_msec()
	if _tex.has(p) and now - int(_checked.get(p, -1000)) < 1000:
		return _tex[p]
	_checked[p] = now
	var stamp := FileAccess.get_sha256(p) if FileAccess.file_exists(p) else ""
	if _tex.has(p) and str(_stamp.get(p, "")) == stamp:
		return _tex[p]
	var tex: Texture2D = null
	_mask.erase(p)
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img and not img.is_empty():
			if img.get_width() > 48 or img.get_height() > 48:
				img.resize(mini(48, img.get_width()), mini(48, img.get_height()), Image.INTERPOLATE_NEAREST)
			tex = ImageTexture.create_from_image(img)
			var pts := PackedVector2Array()
			img.convert(Image.FORMAT_RGBA8)
			var half := Vector2(img.get_width(), img.get_height()) / 2.0
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y).a > 0.4:
						pts.append(Vector2(x + 0.5, y + 0.5) - half)
			_mask[p] = pts
	while _tex.size() >= CACHE_MAX and not _tex.has(p):
		var old: String = str(_tex.keys()[0])
		_tex.erase(old)
		_mask.erase(old)
		_stamp.erase(old)
		_checked.erase(old)
	_tex[p] = tex
	_stamp[p] = stamp
	return tex


## Does a bullet at `p` (scale `s`, `px` screen pixels per art pixel) touch a heart of radius `r` at `h`?
## Returns the distance from the heart to the bullet's nearest solid part (for grazes too).
static func distance(kind: String, p: Vector2, s: float, h: Vector2, px: float = 2.0) -> float:
	if kind.begins_with("custom:"):
		if _active_root == SaveManager.root and _active_custom.has(kind):
			return _mask_distance(_active_custom[kind].mask, p, s, h, px)
		var id := kind.trim_prefix("custom:")
		custom_texture(id)
		var pts: PackedVector2Array = _mask.get(bullets_dir().path_join(id + ".png"), PackedVector2Array())
		return _mask_distance(pts, p, s, h, px)
	return maxf(0.0, p.distance_to(h) - 6.0 * s)


static func _mask_distance(pts: PackedVector2Array, p: Vector2, s: float, h: Vector2, px: float) -> float:
	if pts.is_empty():
		return p.distance_to(h)
	var best := 1e9
	var rel := (h - p) / (s * px)
	for q in pts:
		best = minf(best, q.distance_squared_to(rel))
	return sqrt(best) * s * px


static func draw(ci: CanvasItem, kind: String, p: Vector2, s: float) -> void:
	if not kind.begins_with("custom:"):
		ci.draw_texture_rect_region(ATLAS, Rect2(p - Vector2(8, 8) * s, Vector2(16, 16) * s), Rect2(float(CELLS.get(kind, 0)) * 32, 0, 32, 32), Color("#ff8fb8") if kind == "heart" else Color.WHITE)
		return
	if kind.begins_with("custom:"):
		var tex: Texture2D = _active_custom[kind].texture if _active_root == SaveManager.root and _active_custom.has(kind) else custom_texture(kind.trim_prefix("custom:"))
		if tex:
			var sz := Vector2(tex.get_width(), tex.get_height()) * s * 2.0
			ci.draw_texture_rect(tex, Rect2(p - sz / 2.0, sz), false)
			return
	ci.draw_circle(p, 6.0 * s, Color.WHITE)


static func draw_heart(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	ci.draw_texture_rect_region(ATLAS, Rect2(p - Vector2(r, r), Vector2(r, r) * 2), Rect2(256, 0, 32, 32), c)
