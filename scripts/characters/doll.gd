extends RefCounted
## The layered doll maker's art: a 32x32 person drawn in code from a small
## recipe (skin, hair, eyes, outfit, accessory; each a style + a colour).
## Expressions only change the face, so one recipe gives a whole set of
## faces. Everything is procedural: no image files ship with the game.

const PixelArt := preload("res://scripts/characters/pixel_art.gd")

const SIZE := 32
const INK := Color("#22183d")
const WHITE := Color("#fffaf0")
const BLUSH := Color("#ff8fab")
const TEAR := Color("#8fd3ff")
const LEGS := Color("#2e2552")
const MOUTH := Color("#b5655a")

const PARTS: PackedStringArray = ["skin", "hair", "eyes", "outfit", "accessory"]
const PART_NAMES := {"skin": "Skin", "hair": "Hair", "eyes": "Eyes", "outfit": "Outfit", "accessory": "Accessory"}
const STYLES := {
	"skin": [["plain", "Plain"], ["freckles", "Freckles"], ["rosy", "Rosy cheeks"], ["stars", "Star marks"]],
	"hair": [["short", "Short"], ["bob", "Bob"], ["long", "Long"], ["ponytail", "Ponytail"], ["spiky", "Spiky"], ["curly", "Curly"], ["buns", "Buns"], ["none", "None"]],
	"eyes": [["dot", "Dots"], ["round", "Round"], ["sparkle", "Sparkly"], ["sleepy", "Sleepy"], ["cat", "Cat"], ["visor", "Glow visor"]],
	"outfit": [["hoodie", "Hoodie"], ["dress", "Dress"], ["overalls", "Overalls"], ["cloak", "Cloak"], ["sweater", "Striped sweater"], ["tunic", "Tunic"]],
	"accessory": [["none", "None"], ["glasses", "Glasses"], ["bow", "Bow"], ["horns", "Horns"], ["halo", "Halo"], ["flower", "Flower"], ["headphones", "Headphones"], ["crown", "Crown"]],
}
## Randomize picks colours from these so random looks stay pretty.
const PALETTES := {
	"skin": ["#ffe0c2", "#f2c9a0", "#e0a882", "#c68863", "#9a6748", "#6e4631", "#b8d8f0", "#c9b6ff"],
	"hair": ["#4a3426", "#1f1a2e", "#e8c36a", "#c0562f", "#f3e9d2", "#8f6bd8", "#e86a8a", "#5fb8a8", "#2b1d4f"],
	"eyes": ["#22183d", "#3a2a6e", "#2f5d4f", "#5a3b22", "#7af0ff", "#ff7b7b"],
	"outfit": ["#e86a8a", "#7ad6b0", "#6fb7ff", "#ffd166", "#c58cff", "#3a2a6e", "#f08a4b", "#4a7a5a"],
	"accessory": ["#ffd166", "#ff8fab", "#f3e9d2", "#7af0ff", "#c58cff", "#e86a8a"],
}
## Built-in presets: [display name, recipe].
const PRESETS := {
	"cozy": ["Cozy hoodie", {"skin": {"style": "plain", "color": "#f2c9a0"}, "hair": {"style": "short", "color": "#4a3426"}, "eyes": {"style": "dot", "color": "#22183d"}, "outfit": {"style": "hoodie", "color": "#e86a8a"}, "accessory": {"style": "none", "color": "#ffd166"}}],
	"night": ["Night wanderer", {"skin": {"style": "stars", "color": "#c9b6ff"}, "hair": {"style": "spiky", "color": "#2b1d4f"}, "eyes": {"style": "visor", "color": "#7af0ff"}, "outfit": {"style": "cloak", "color": "#3a2a6e"}, "accessory": {"style": "horns", "color": "#f3e9d2"}}],
	"gardener": ["Gardener", {"skin": {"style": "freckles", "color": "#e0a882"}, "hair": {"style": "bob", "color": "#c0562f"}, "eyes": {"style": "round", "color": "#2f5d4f"}, "outfit": {"style": "overalls", "color": "#4a7a5a"}, "accessory": {"style": "flower", "color": "#ff8fab"}}],
	"mage": ["Starry mage", {"skin": {"style": "plain", "color": "#c68863"}, "hair": {"style": "long", "color": "#f3e9d2"}, "eyes": {"style": "sparkle", "color": "#3a2a6e"}, "outfit": {"style": "cloak", "color": "#6fb7ff"}, "accessory": {"style": "crown", "color": "#ffd166"}}],
	"sleepy": ["Sleepy cat", {"skin": {"style": "rosy", "color": "#ffe0c2"}, "hair": {"style": "buns", "color": "#8f6bd8"}, "eyes": {"style": "cat", "color": "#22183d"}, "outfit": {"style": "sweater", "color": "#ffd166"}, "accessory": {"style": "headphones", "color": "#e86a8a"}}],
}
const LIBRARY_DIR := "library/dolls"


static func defaults() -> Dictionary:
	return preset("cozy")


static func preset(id: String) -> Dictionary:
	return (PRESETS.get(id, PRESETS.cozy)[1] as Dictionary).duplicate(true)


static func style_ids(part: String) -> PackedStringArray:
	var out := PackedStringArray()
	for s in STYLES.get(part, []):
		out.append(str(s[0]))
	return out


## Fills in missing parts and replaces unknown styles/colours, so hand-edited
## or older recipes always draw.
static func normalize(recipe: Variant) -> Dictionary:
	var base := defaults()
	if not recipe is Dictionary:
		return base
	for part in PARTS:
		var p: Variant = recipe.get(part)
		if not p is Dictionary:
			continue
		if str(p.get("style", "")) in style_ids(part):
			base[part]["style"] = str(p.style)
		var c := str(p.get("color", ""))
		if c != "" and Color.html_is_valid(c):
			base[part]["color"] = c
	return base


static func randomize(rng: RandomNumberGenerator) -> Dictionary:
	var r := {}
	for part in PARTS:
		var ids := style_ids(part)
		var pal: Array = PALETTES[part]
		var style := ids[rng.randi_range(0, ids.size() - 1)]
		if part == "accessory" and rng.randf() < 0.35:
			style = "none"
		r[part] = {"style": style, "color": str(pal[rng.randi_range(0, pal.size() - 1)])}
	return r


# --- Saved presets (shared by every world, in the Library) --------------------------------

static func saved_presets() -> Array:
	var out: Array = []
	var dir := SaveManager.global_path(LIBRARY_DIR)
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		if f.get_extension() != "json":
			continue
		var data: Variant = preload("res://scripts/core/json_util.gd").read_json(dir.path_join(f), null)
		if data is Dictionary:
			out.append({"id": f.get_basename(), "name": str(data.get("name", f.get_basename())), "recipe": normalize(data.get("recipe"))})
	out.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


static func save_preset(preset_name: String, recipe: Dictionary) -> String:
	const JsonUtil := preload("res://scripts/core/json_util.gd")
	var dir := SaveManager.global_path(LIBRARY_DIR)
	JsonUtil.ensure_dir(dir)
	var id := JsonUtil.slugify(preset_name)
	JsonUtil.write_json(dir.path_join(id + ".json"), {"version": 1, "name": preset_name.strip_edges(), "recipe": normalize(recipe)})
	return id


static func delete_preset(id: String) -> void:
	DirAccess.remove_absolute(SaveManager.global_path(LIBRARY_DIR).path_join(preload("res://scripts/core/json_util.gd").slugify(id) + ".json"))


# --- Drawing --------------------------------------------------------------------------------

static func _col(r: Dictionary, part: String) -> Color:
	return Color.from_string(str(r[part].color), Color.WHITE)


## One expression of the doll as a 32x32 image.
static func compose(recipe: Variant, emotion: String = "neutral") -> Image:
	var r := normalize(recipe)
	var img := PixelArt.blank(SIZE)
	var skin := _col(r, "skin")
	var hair := _col(r, "hair")
	var cloth := _col(r, "outfit")
	var acc := _col(r, "accessory")
	var hair_style := str(r.hair.style)
	var outfit := str(r.outfit.style)
	var accessory := str(r.accessory.style)
	_hair_back(img, hair_style, hair)
	_body(img, outfit, cloth, skin)
	PixelArt.ellipse(img, 16, 11, 7, 6.5, skin)  # head
	_hair_front(img, hair_style, hair)
	if accessory == "headphones":
		_accessory(img, accessory, acc)
	PixelArt.outline(img, INK)
	_outfit_details(img, outfit, cloth)
	_skin_marks(img, str(r.skin.style), skin, acc)
	_face(img, str(r.eyes.style), _col(r, "eyes"), emotion)
	# Small accessories go on after the outline, or it would swallow them.
	if accessory != "headphones" and accessory != "none":
		_accessory(img, accessory, acc)
	return img


static func _hair_back(img: Image, style: String, c: Color) -> void:
	match style:
		"long":
			PixelArt.rect(img, 8, 7, 23, 24, c)
		"ponytail":
			PixelArt.rect(img, 21, 6, 25, 9, c)
			PixelArt.rect(img, 23, 9, 25, 19, c)
			PixelArt.rect(img, 22, 19, 24, 20, c)
		"buns":
			PixelArt.ellipse(img, 9, 4.5, 3.2, 3.2, c)
			PixelArt.ellipse(img, 23, 4.5, 3.2, 3.2, c)


static func _hair_front(img: Image, style: String, c: Color) -> void:
	match style:
		"short":
			PixelArt.rect(img, 9, 4, 22, 8, c)
			PixelArt.rect(img, 9, 8, 10, 12, c)
			PixelArt.rect(img, 21, 8, 22, 12, c)
			PixelArt.rect(img, 12, 8, 14, 9, c)
		"bob":
			PixelArt.rect(img, 9, 3, 22, 7, c)
			PixelArt.rect(img, 8, 6, 10, 15, c)
			PixelArt.rect(img, 21, 6, 23, 15, c)
			PixelArt.rect(img, 10, 7, 21, 8, c)
		"long":
			PixelArt.rect(img, 9, 4, 22, 7, c)
			PixelArt.rect(img, 8, 7, 10, 20, c)
			PixelArt.rect(img, 21, 7, 23, 20, c)
			PixelArt.rect(img, 11, 7, 15, 8, c)
		"ponytail":
			PixelArt.rect(img, 9, 4, 22, 8, c)
			PixelArt.rect(img, 9, 8, 10, 11, c)
			PixelArt.rect(img, 18, 8, 22, 9, c)
		"spiky":
			PixelArt.rect(img, 9, 5, 22, 8, c)
			for x in [9, 12, 15, 18, 21]:
				PixelArt.rect(img, x, 3, x + 1, 4, c)
				PixelArt.px(img, [Vector2i(x, 2), Vector2i(x, 1)], c)
			PixelArt.rect(img, 9, 8, 10, 11, c)
			PixelArt.rect(img, 21, 8, 22, 11, c)
		"curly":
			for p in [Vector2(10, 6), Vector2(13, 4), Vector2(16, 3.5), Vector2(19, 4), Vector2(22, 6), Vector2(9, 9.5), Vector2(23, 9.5), Vector2(9, 12.5), Vector2(23, 12.5)]:
				PixelArt.ellipse(img, p.x, p.y, 2.6, 2.6, c)
		"buns":
			PixelArt.rect(img, 9, 4, 22, 7, c)
			PixelArt.rect(img, 9, 7, 10, 10, c)
			PixelArt.rect(img, 21, 7, 22, 10, c)


static func _body(img: Image, style: String, c: Color, skin: Color) -> void:
	match style:
		"dress":
			PixelArt.rect(img, 11, 17, 20, 22, c)
			for y in range(23, 29):
				var grow := (y - 23) / 2
				PixelArt.rect(img, 10 - grow, y, 21 + grow, y, c)
			PixelArt.rect(img, 8, 18, 9, 20, c)
			PixelArt.rect(img, 22, 18, 23, 20, c)
			PixelArt.rect(img, 8, 21, 9, 25, skin)
			PixelArt.rect(img, 22, 21, 23, 25, skin)
			PixelArt.rect(img, 12, 29, 14, 30, LEGS)
			PixelArt.rect(img, 17, 29, 19, 30, LEGS)
		"overalls":
			var shirt := c.lightened(0.55)
			PixelArt.rect(img, 12, 27, 14, 30, c)
			PixelArt.rect(img, 17, 27, 19, 30, c)
			PixelArt.rect(img, 10, 17, 21, 27, shirt)
			PixelArt.rect(img, 8, 18, 9, 21, shirt)
			PixelArt.rect(img, 22, 18, 23, 21, shirt)
			PixelArt.rect(img, 8, 22, 9, 25, skin)
			PixelArt.rect(img, 22, 22, 23, 25, skin)
			PixelArt.rect(img, 12, 20, 19, 27, c)
		"cloak":
			PixelArt.rect(img, 12, 30, 14, 30, LEGS)
			PixelArt.rect(img, 17, 30, 19, 30, LEGS)
			for y in range(16, 30):
				var grow := (y - 16) / 4
				PixelArt.rect(img, 9 - grow, y, 22 + grow, y, c)
			PixelArt.rect(img, 15, 20, 16, 29, c.darkened(0.35))
		"tunic":
			PixelArt.rect(img, 12, 27, 14, 30, LEGS)
			PixelArt.rect(img, 17, 27, 19, 30, LEGS)
			PixelArt.rect(img, 10, 17, 21, 26, c)
			PixelArt.rect(img, 8, 18, 9, 20, c)
			PixelArt.rect(img, 22, 18, 23, 20, c)
			PixelArt.rect(img, 8, 21, 9, 24, skin)
			PixelArt.rect(img, 22, 21, 23, 24, skin)
		_:  # hoodie, sweater
			PixelArt.rect(img, 12, 27, 14, 30, LEGS)
			PixelArt.rect(img, 17, 27, 19, 30, LEGS)
			PixelArt.rect(img, 10, 17, 21, 27, c)
			PixelArt.rect(img, 8, 18, 9, 25, c)
			PixelArt.rect(img, 22, 18, 23, 25, c)


## Details drawn after the outline so they stay crisp.
static func _outfit_details(img: Image, style: String, c: Color) -> void:
	match style:
		"hoodie":
			PixelArt.rect(img, 14, 19, 17, 19, c.lightened(0.3))
		"sweater":
			for y in [20, 23, 26]:
				for x in range(9, 23):
					if img.get_pixel(x, y) == c:
						img.set_pixel(x, y, c.lightened(0.4))
		"overalls":
			PixelArt.rect(img, 12, 17, 12, 19, c)
			PixelArt.rect(img, 19, 17, 19, 19, c)
			PixelArt.px(img, [Vector2i(13, 21), Vector2i(18, 21)], Color("#ffd166"))
		"cloak":
			PixelArt.rect(img, 15, 17, 16, 17, Color("#ffd166"))
		"tunic":
			PixelArt.rect(img, 11, 23, 20, 23, c.darkened(0.4))
			PixelArt.px(img, [Vector2i(15, 23)], Color("#ffd166"))
		"dress":
			PixelArt.rect(img, 11, 22, 20, 22, c.lightened(0.35))


static func _accessory(img: Image, style: String, c: Color) -> void:
	match style:
		"glasses":
			for x0 in [11, 17]:
				PixelArt.rect(img, x0, 10, x0 + 3, 10, c)
				PixelArt.rect(img, x0, 13, x0 + 3, 13, c)
				PixelArt.rect(img, x0, 11, x0, 12, c)
				PixelArt.rect(img, x0 + 3, 11, x0 + 3, 12, c)
			PixelArt.rect(img, 15, 11, 16, 11, c)
		"bow":
			PixelArt.rect(img, 17, 2, 19, 4, c)
			PixelArt.rect(img, 21, 2, 23, 4, c)
			PixelArt.px(img, [Vector2i(20, 3)], c.darkened(0.3))
		"horns":
			PixelArt.rect(img, 9, 2, 10, 4, c)
			PixelArt.px(img, [Vector2i(9, 1), Vector2i(8, 0)], c)
			PixelArt.rect(img, 21, 2, 22, 4, c)
			PixelArt.px(img, [Vector2i(22, 1), Vector2i(23, 0)], c)
		"halo":
			PixelArt.rect(img, 12, 0, 19, 0, c)
			PixelArt.rect(img, 12, 2, 19, 2, c)
			PixelArt.px(img, [Vector2i(11, 1), Vector2i(20, 1)], c)
		"flower":
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				PixelArt.rect(img, 9 + d.x * 2 - 1, 5 + d.y * 2 - 1, 9 + d.x * 2, 5 + d.y * 2, c)
			PixelArt.rect(img, 8, 4, 9, 5, Color("#ffd166"))
		"headphones":
			PixelArt.rect(img, 11, 2, 20, 2, c.darkened(0.25))
			PixelArt.px(img, [Vector2i(10, 3), Vector2i(21, 3), Vector2i(9, 4), Vector2i(22, 4)], c.darkened(0.25))
			PixelArt.rect(img, 7, 8, 9, 13, c)
			PixelArt.rect(img, 22, 8, 24, 13, c)
		"crown":
			PixelArt.rect(img, 11, 2, 20, 3, c)
			for x in [11, 14, 17, 20]:
				PixelArt.rect(img, x, 0, x, 1, c)
			PixelArt.px(img, [Vector2i(15, 2), Vector2i(16, 2)], BLUSH)


static func _skin_marks(img: Image, style: String, skin: Color, acc: Color) -> void:
	match style:
		"freckles":
			PixelArt.px(img, [Vector2i(10, 13), Vector2i(12, 14), Vector2i(19, 14), Vector2i(21, 13)], skin.darkened(0.3))
		"rosy":
			PixelArt.rect(img, 10, 13, 11, 13, BLUSH)
			PixelArt.rect(img, 20, 13, 21, 13, BLUSH)
		"stars":
			for cx in [11, 20]:
				PixelArt.px(img, [Vector2i(cx, 13), Vector2i(cx - 1, 14), Vector2i(cx + 1, 14), Vector2i(cx, 15), Vector2i(cx, 14)], acc if acc.v > 0.6 else Color("#ffd166"))


## Eyes (by style) and mouth (by emotion). The glow visor stays on for every
## emotion, so only the mouth and blush change.
static func _face(img: Image, style: String, eye: Color, emotion: String) -> void:
	var visor := style == "visor"
	if visor:
		PixelArt.rect(img, 10, 10, 21, 12, eye)
		PixelArt.rect(img, 10, 10, 21, 10, eye.lightened(0.5))
	var blush := false
	match emotion:
		"happy":
			if not visor:
				PixelArt.px(img, [Vector2i(12, 12), Vector2i(13, 11), Vector2i(14, 12), Vector2i(17, 12), Vector2i(18, 11), Vector2i(19, 12)], eye)
			PixelArt.px(img, [Vector2i(14, 15), Vector2i(15, 16), Vector2i(16, 16), Vector2i(17, 15)], INK)
			blush = true
		"sad":
			if not visor:
				PixelArt.px(img, [Vector2i(13, 12), Vector2i(18, 12), Vector2i(12, 10), Vector2i(13, 9), Vector2i(18, 9), Vector2i(19, 10)], eye)
				PixelArt.px(img, [Vector2i(12, 13), Vector2i(12, 14)], TEAR)
			PixelArt.px(img, [Vector2i(14, 16), Vector2i(15, 15), Vector2i(16, 15), Vector2i(17, 16)], INK)
		"angry":
			if not visor:
				PixelArt.px(img, [Vector2i(13, 11), Vector2i(13, 12), Vector2i(18, 11), Vector2i(18, 12), Vector2i(11, 9), Vector2i(12, 9), Vector2i(13, 10), Vector2i(18, 10), Vector2i(19, 9), Vector2i(20, 9)], eye)
			PixelArt.rect(img, 14, 16, 17, 16, INK)
		"surprised":
			if not visor:
				PixelArt.rect(img, 12, 10, 13, 12, eye)
				PixelArt.rect(img, 18, 10, 19, 12, eye)
				PixelArt.px(img, [Vector2i(12, 10), Vector2i(18, 10)], WHITE)
			PixelArt.rect(img, 15, 15, 16, 16, INK)
		"embarrassed":
			if not visor:
				PixelArt.px(img, [Vector2i(12, 10), Vector2i(13, 11), Vector2i(12, 12), Vector2i(19, 10), Vector2i(18, 11), Vector2i(19, 12)], eye)
			PixelArt.px(img, [Vector2i(14, 16), Vector2i(15, 15), Vector2i(16, 16), Vector2i(17, 15)], INK)
			PixelArt.rect(img, 9, 13, 11, 14, BLUSH)
			PixelArt.rect(img, 20, 13, 22, 14, BLUSH)
		"thinking":
			if not visor:
				PixelArt.rect(img, 14, 10, 14, 11, eye)
				PixelArt.rect(img, 19, 10, 19, 11, eye)
			PixelArt.rect(img, 16, 15, 17, 15, INK)
			PixelArt.px(img, [Vector2i(25, 6), Vector2i(27, 5), Vector2i(29, 4)], WHITE)
		"sleepy":
			if not visor:
				PixelArt.rect(img, 12, 12, 14, 12, eye)
				PixelArt.rect(img, 17, 12, 19, 12, eye)
			PixelArt.px(img, [Vector2i(15, 16)], INK)
			PixelArt.px(img, [Vector2i(25, 2), Vector2i(26, 2), Vector2i(27, 2), Vector2i(26, 3), Vector2i(25, 4), Vector2i(26, 4), Vector2i(27, 4)], WHITE)
		_:
			if not visor:
				_eyes_neutral(img, style, eye)
			PixelArt.rect(img, 15, 15, 16, 15, MOUTH)
	if blush:
		PixelArt.rect(img, 10, 14, 11, 14, BLUSH)
		PixelArt.rect(img, 20, 14, 21, 14, BLUSH)


static func _eyes_neutral(img: Image, style: String, eye: Color) -> void:
	match style:
		"round":
			PixelArt.rect(img, 12, 11, 13, 12, eye)
			PixelArt.rect(img, 18, 11, 19, 12, eye)
			PixelArt.px(img, [Vector2i(12, 11), Vector2i(18, 11)], WHITE)
		"sparkle":
			PixelArt.rect(img, 12, 10, 13, 12, eye)
			PixelArt.rect(img, 18, 10, 19, 12, eye)
			PixelArt.px(img, [Vector2i(12, 10), Vector2i(18, 10), Vector2i(13, 12), Vector2i(19, 12)], WHITE)
			PixelArt.px(img, [Vector2i(11, 10), Vector2i(20, 10)], INK)
		"sleepy":
			PixelArt.rect(img, 12, 12, 13, 12, eye)
			PixelArt.rect(img, 18, 12, 19, 12, eye)
		"cat":
			PixelArt.px(img, [Vector2i(12, 12), Vector2i(13, 11), Vector2i(14, 11), Vector2i(17, 11), Vector2i(18, 11), Vector2i(19, 12)], INK)
			PixelArt.px(img, [Vector2i(13, 12), Vector2i(18, 12)], eye)
		_:  # dot
			PixelArt.rect(img, 13, 11, 13, 12, eye)
			PixelArt.rect(img, 18, 11, 18, 12, eye)


# --- Words for the AI ------------------------------------------------------------------------

## "short brown hair, a pink hoodie, glasses" — so friends know how you look.
static func describe(recipe: Variant) -> String:
	var r := normalize(recipe)
	var bits := PackedStringArray()
	var hair := str(r.hair.style)
	if hair == "none":
		bits.append("no hair")
	else:
		bits.append("%s %s hair" % [_style_name("hair", hair).to_lower(), color_word(str(r.hair.color))])
	bits.append("%s skin" % skin_word(str(r.skin.color)))
	if str(r.eyes.style) == "visor":
		bits.append("a glowing %s visor" % color_word(str(r.eyes.color)))
	bits.append("a %s %s" % [color_word(str(r.outfit.color)), _style_name("outfit", str(r.outfit.style)).to_lower()])
	if str(r.accessory.style) != "none":
		bits.append("a %s %s" % [color_word(str(r.accessory.color)), _style_name("accessory", str(r.accessory.style)).to_lower().trim_suffix("es").trim_suffix("s")])
	return ", ".join(bits)


static func _style_name(part: String, id: String) -> String:
	for s in STYLES.get(part, []):
		if str(s[0]) == id:
			return str(s[1])
	return id


## Skin tones get their own words ("orange skin" would be a strange thing to tell a friend).
static func skin_word(hex: String) -> String:
	var c := Color.from_string(hex, Color.GRAY)
	var h := c.h * 360.0
	if h >= 8.0 and h <= 50.0 and c.s < 0.65:
		if c.v > 0.88:
			return "fair"
		if c.v > 0.72:
			return "light brown"
		if c.v > 0.5:
			return "brown"
		return "dark brown"
	return color_word(hex)


## A plain colour word for a hex colour (good enough for a prompt).
static func color_word(hex: String) -> String:
	var c := Color.from_string(hex, Color.GRAY)
	if c.s < 0.18:
		if c.v > 0.85:
			return "white"
		if c.v < 0.22:
			return "black"
		return "grey"
	if c.v < 0.2:
		return "black"
	var h := c.h * 360.0
	if (h < 40.0 or h >= 345.0) and c.v < 0.65 and c.s > 0.35:
		return "brown"
	if h < 12.0 or h >= 345.0:
		return "red"
	if h < 40.0:
		return "orange" if c.v > 0.75 else "brown"
	if h < 70.0:
		return "yellow"
	if h < 160.0:
		return "green"
	if h < 200.0:
		return "teal"
	if h < 255.0:
		return "blue"
	if h < 300.0:
		return "purple"
	return "pink"
