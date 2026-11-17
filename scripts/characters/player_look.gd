extends RefCounted
## The player's two forms, Real Me and Dream World Me: which one is showing,
## each form's faces (drawn by the doll maker or painted by hand, saved as
## player/<form>/<emotion>.png), rooms that switch you automatically, and
## the equipped-gear overlay drawn onto the sprite.

const Doll := preload("res://scripts/characters/doll.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const Items := preload("res://scripts/items/items.gd")
const Inventory := preload("res://scripts/items/inventory.gd")

const FORMS: PackedStringArray = ["real", "dark"]
const FORM_NAMES := {"real": "Real Me", "dark": "Dream World Me"}
## Where each gear slot is drawn, as fractions of the sprite (square boxes).
const GEAR_BOXES := {
	"body": Rect2(0.31, 0.5, 0.38, 0.38),
	"accessory": Rect2(0.04, 0.52, 0.28, 0.28),
	"weapon": Rect2(0.58, 0.38, 0.42, 0.42),
	"head": Rect2(0.29, 0.0, 0.42, 0.42),
}
const GEAR_ORDER: PackedStringArray = ["body", "accessory", "weapon", "head"]

static var _cache: Dictionary = {}


static func form_defaults(form: String) -> Dictionary:
	return {"mode": "doll", "doll": Doll.preset("cozy" if form == "real" else "night"), "expressions": {}, "label": FORM_NAMES.get(form, form), "looks": ""}


static func _player() -> Dictionary:
	if not GameState.world.get("player") is Dictionary:
		GameState.world["player"] = Defaults.world().player
	return GameState.world.player


static func current() -> String:
	return "real" if Inventory.active_realm() == "light" else "dark"


## Repair stale/manual/synced active-form state without touching either editable look.
## Read-only sync reloads call this in memory; ordinary saves persist the repair.
static func normalize() -> bool:
	var p := _player()
	var f := current()
	var changed := str(p.get("form", "")) != f
	p["form"] = f
	p["avatar"] = face_rel(f, "neutral")
	return changed


## A form's settings with every field present. An old world whose painted
## avatar hasn't been upgraded yet shows that avatar as Real Me.
static func form_data(form: String) -> Dictionary:
	var forms: Variant = _player().get("forms", {})
	var raw: Variant = forms.get(form) if forms is Dictionary else null
	if not raw is Dictionary:
		var d := form_defaults(form)
		var avatar := str(_player().get("avatar", ""))
		if form == "real" and avatar != "" and FileAccess.file_exists(SaveManager.abs_path(avatar)):
			d["mode"] = "custom"
			d["expressions"] = {"neutral": avatar}
		return d
	var out := JsonUtil.merge_defaults(raw, form_defaults(form))
	out["doll"] = Doll.normalize(out.get("doll"))
	if not out.get("expressions") is Dictionary:
		out["expressions"] = {}
	if not str(out.get("mode", "")) in ["doll", "custom"]:
		out["mode"] = "doll"
	return out


static func label(form: String) -> String:
	var l := str(form_data(form).get("label", "")).strip_edges()
	return l if l != "" else str(FORM_NAMES.get(form, form))


static func _store(form: String, data: Dictionary) -> void:
	var p := _player()
	if not p.get("forms") is Dictionary:
		p["forms"] = {}
	p.forms[form] = data


## Switches the visible form. Saves the world and refreshes the sprite.
static func set_form(form: String) -> bool:
	if not form in FORMS or form != current():
		normalize()
		return false
	var p := _player()
	p["form"] = form
	p["avatar"] = face_rel(form, "neutral")
	GameState.save_world()
	invalidate()
	GameState.character_changed.emit("player")
	return true


static func other(form: String) -> String:
	return "dark" if form == "real" else "real"


## The form a room asks for ("" = no preference).
static func room_form(room: Dictionary) -> String:
	return "real" if preload("res://scripts/world/realms.gd").is_light(room) else "dark"


## On entering a room: switch if the room asks for a form. True if it changed.
static func apply_room(room: Dictionary, persist: bool = true) -> bool:
	GameState.current_realm = "light" if room_form(room) == "real" else "dark"
	var changed := normalize()
	Inventory.normalize()
	invalidate()
	if changed and persist:
		GameState.save_world()
	return changed


# --- Faces --------------------------------------------------------------------------------------

static func face_rel(form: String, emotion: String) -> String:
	var ex: Dictionary = form_data(form).expressions
	return str(ex.get(emotion, ex.get("neutral", "")))


static func emotions(form: String) -> PackedStringArray:
	var out := PackedStringArray()
	for k in form_data(form).expressions:
		out.append(str(k))
	if not "neutral" in out:
		out.insert(0, "neutral")
	return out


static func base_image(form: String, emotion: String) -> Image:
	var rel := face_rel(form, emotion)
	if rel != "":
		var img := SaveManager.load_picture(SaveManager.abs_path(rel))
		if img:
			return img
	var d := form_data(form)
	if str(d.mode) == "doll":
		return Doll.compose(d.doll, emotion)
	return SpriteFactory.player()


## emotion -> Texture2D for a form (gear drawn on when "show gear" is on).
static func textures(form: String = "") -> Dictionary:
	if form == "":
		form = current()
	var out := {}
	for e in emotions(form):
		out[e] = texture(form, e)
	return out


static func texture(form: String, emotion: String) -> Texture2D:
	var gear := _gear_key(form)
	var key := "%s|%s|%s" % [form, emotion, gear]
	if not _cache.has(key):
		var img := base_image(form, emotion)
		if gear != "":
			img = with_gear(img, Inventory.equipped("light" if form == "real" else "dark"))
		var tex := ImageTexture.create_from_image(img)
		tex.set_meta(&"polox_source_image", img)
		_cache[key] = tex
	return _cache[key]


static func invalidate() -> void:
	_cache.clear()


static func _gear_key(form: String) -> String:
	if not bool(_player().get("show_gear", true)):
		return ""
	var eq := Inventory.equipped("light" if form == "real" else "dark")
	var bits := PackedStringArray()
	for slot in Inventory.SLOTS:
		bits.append(str(eq.get(slot, "")))
	var key := ",".join(bits)
	return "" if key.replace(",", "") == "" else key


## Draws equipped items onto the sprite. Small sprites are doubled first so
## a 32 px icon still reads as a sword and not a smudge.
static func with_gear(base: Image, equipped: Dictionary) -> Image:
	var out := base.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	if out.get_width() <= 48:
		out.resize(out.get_width() * 2, out.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var w := out.get_width()
	var h := out.get_height()
	for slot in GEAR_ORDER:
		var id := str(equipped.get(slot, ""))
		if id == "":
			continue
		var it := Items.load_item(id)
		if it.is_empty():
			continue
		var pic := Items.world_image(it)
		var box: Rect2 = GEAR_BOXES[slot]
		var side := maxi(4, int(box.size.x * w))
		pic.resize(side, side, Image.INTERPOLATE_NEAREST)
		out.blend_rect(pic, Rect2i(0, 0, side, side), Vector2i(int(box.position.x * w), int(box.position.y * h)))
	return out


# --- Saving ---------------------------------------------------------------------------------------

## Draws every expression of a doll into player/<form>/ and returns the
## {emotion: path} map. Only touches files (safe before a world is loaded).
static func write_doll_files(form: String, recipe: Dictionary) -> Dictionary:
	var dir := "player/%s" % form
	JsonUtil.ensure_dir(SaveManager.abs_path(dir))
	var map := {}
	for e in Defaults.DEFAULT_EXPRESSIONS:
		var rel := "%s/%s.png" % [dir, e]
		Doll.compose(recipe, e).save_png(SaveManager.abs_path(rel))
		SaveManager.forget_texture(rel)
		map[e] = rel
	return map


## The doll maker's Save: the recipe plus freshly drawn faces.
static func save_doll(form: String, recipe: Dictionary) -> void:
	var d := form_data(form)
	d["mode"] = "doll"
	d["doll"] = Doll.normalize(recipe)
	d["expressions"] = write_doll_files(form, d.doll)
	_store(form, d)
	_saved(form)


## The Creator's Save for a hand-drawn form: every painted face.
static func save_custom(form: String, order: Array, slots: Dictionary, removed: Array) -> void:
	var dir := "player/%s" % form
	JsonUtil.ensure_dir(SaveManager.abs_path(dir))
	var map := {}
	for n in order:
		var img: Image = slots.get(n)
		if img != null and not img.is_invisible():
			var rel := "%s/%s.png" % [dir, n]
			img.save_png(SaveManager.abs_path(rel))
			SaveManager.forget_texture(rel)
			map[n] = rel
	for n in removed:
		if not slots.has(n):
			DirAccess.remove_absolute(SaveManager.abs_path("%s/%s.png" % [dir, n]))
	var d := form_data(form)
	d["mode"] = "custom"
	d["expressions"] = map
	_store(form, d)
	_saved(form)


## Back to the doll maker's look for a form that was hand-drawn.
static func use_doll(form: String) -> void:
	save_doll(form, form_data(form).doll)


static func set_field(form: String, key: String, value: Variant) -> void:
	var d := form_data(form)
	d[key] = value
	_store(form, d)
	GameState.save_world()


static func _saved(form: String) -> void:
	if form == current():
		_player()["avatar"] = face_rel(form, "neutral")
	GameState.save_world()
	invalidate()
	GameState.character_changed.emit("player")


# --- Words for the AI -------------------------------------------------------------------------------

static func describe(form: String) -> String:
	var d := form_data(form)
	var looks := str(d.get("looks", "")).strip_edges()
	if looks != "":
		return looks
	if str(d.mode) == "doll":
		return Doll.describe(d.doll)
	return ""


## "their Dream World Me form (spiky black hair, a glowing visor...), wearing X and holding Y"
static func appearance_line() -> String:
	var f := current()
	var desc := describe(f)
	var line := "their %s form" % label(f)
	if desc != "":
		line += " (%s)" % desc
	var gear := Inventory.gear_line()
	if gear != "":
		line += ", " + gear
	return line
