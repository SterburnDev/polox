extends RefCounted
## Item designs from the Item Workshop. Each one lives in items/<id>/ inside
## the world: item.json plus an optional icon.png and sprite.png. Stats are
## for show only and the effect is one tiny thing from a fixed list. In a friendly
## battle (Update 6) any Consumable is a snack that heals; battles never use one up.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const ItemArt := preload("res://scripts/items/item_art.gd")
const Defaults := preload("res://scripts/core/defaults.gd")

const CATEGORIES := [["weapon", "Weapons", "Weapon"], ["armor", "Armor", "Armor"], ["consumable", "Consumables", "Consumable"], ["keepsake", "Keepsakes", "Keepsake"]]
const ARMOR_SLOTS := [["head", "Head"], ["body", "Body"], ["accessory", "Accessory"]]
const RARITIES := [["common", "Common", "#cfc6e6"], ["uncommon", "Uncommon", "#7ad6b0"], ["rare", "Rare", "#6fb7ff"], ["epic", "Epic", "#c58cff"], ["legendary", "Legendary", "#ffd166"]]
const EFFECTS := [["none", "No effect"], ["mood", "Mood boost when gifted"], ["aura", "Tint my aura"], ["sound", "Play a sound"], ["message", "Show a message"], ["lighting", "Change the room's light"]]
const SOUNDS: PackedStringArray = ["chime", "sparkle", "pop", "munch", "fanfare", "door", "click"]
const MOOD_SIZES := [["small", "Small"], ["medium", "Medium"], ["big", "Big"]]
const MAX_STATS := 3
const ICON_MAX := 64       # drawn/imported icons are kept small
const SPRITE_MAX := 128


static func defaults(category: String = "keepsake", slot: String = "") -> Dictionary:
	if category == "armor" and slot == "":
		slot = "head"
	return {
		"version": 1,
		"id": "",
		"name": "",
		"category": category,
		"slot": slot if category == "armor" else "",
		"realm": "shared",
		"flavor": "",
		"rarity": "common",
		"icon": "",
		"auto_icon": {"shape": ItemArt.default_shape(category, slot), "color": "#e8b04a"},
		"sprite": "",
		"stats": [],
		"tags": [],
		"effect": {"type": "none", "value": ""},
		"created": Defaults.now_iso(),
	}


static func items_dir() -> String:
	return SaveManager.abs_path("items")


static func dir(id: String) -> String:
	return items_dir().path_join(id)


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for d in JsonUtil.list_dirs(items_dir()):
		if FileAccess.file_exists(dir(d).path_join("item.json")):
			out.append(d)
	return out


static func exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(dir(id).path_join("item.json"))


## The item with every field present and sane ({} if there's no such item).
static func load_item(id: String) -> Dictionary:
	if not exists(id):
		return {}
	var data: Variant = JsonUtil.read_json(dir(id).path_join("item.json"), {})
	if not data is Dictionary:
		return {}
	return sanitize(data, id)


static func sanitize(data: Dictionary, id: String = "") -> Dictionary:
	var cat := str(data.get("category", "keepsake"))
	if not cat in category_ids():
		cat = "keepsake"
	var item := JsonUtil.merge_defaults(data, defaults(cat, str(data.get("slot", ""))))
	if id != "":
		item["id"] = id
	item["category"] = cat
	if not str(item.get("realm", "shared")) in ["shared", "light", "dark"]:
		item["realm"] = "shared"
	if cat == "armor" and not str(item.slot) in ["head", "body", "accessory"]:
		item["slot"] = "head"
	if not str(item.rarity) in rarity_ids():
		item["rarity"] = "common"
	if not item.get("tags") is Array:
		item["tags"] = parse_tags(str(item.get("tags", "")))
	if not item.get("stats") is Array:
		item["stats"] = []
	item["stats"] = (item.stats as Array).filter(func(s): return s is Dictionary).slice(0, MAX_STATS)
	if not item.get("effect") is Dictionary or not str(item.effect.get("type", "")) in effect_ids():
		item["effect"] = {"type": "none", "value": ""}
	return item


## Realm restrictions are explicit author choices, never inferred from names or tags.
static func allowed_in_realm(item: Dictionary, realm: String) -> bool:
	var bound := str(item.get("realm", "shared"))
	return bound == "shared" or bound == realm


static func save_item(item: Dictionary) -> String:
	if str(item.get("id", "")) == "":
		item["id"] = unique_id(str(item.get("name", "item")))
	JsonUtil.ensure_dir(dir(str(item.id)))
	JsonUtil.write_json(dir(str(item.id)).path_join("item.json"), item)
	return str(item.id)


static func unique_id(item_name: String) -> String:
	var base := JsonUtil.slugify(item_name if item_name.strip_edges() != "" else "item")
	var id := base
	var n := 2
	while DirAccess.dir_exists_absolute(dir(id)):
		id = "%s_%d" % [base, n]
		n += 1
	return id


static func delete_item(id: String) -> void:
	if id != "" and exists(id):
		JsonUtil.remove_tree(dir(id))


## A copy with a new id (pictures included).
static func duplicate_item(id: String) -> String:
	var src := load_item(id)
	if src.is_empty():
		return ""
	var copy := src.duplicate(true)
	copy["name"] = str(src.name) + " (copy)"
	copy["id"] = unique_id(str(copy.name))
	JsonUtil.copy_tree(dir(id), dir(str(copy.id)))
	save_item(copy)
	return str(copy.id)


static func all() -> Array:
	var out: Array = []
	for id in ids():
		var it := load_item(id)
		if not it.is_empty():
			out.append(it)
	out.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


# --- Lookups -------------------------------------------------------------------------------

static func category_ids() -> PackedStringArray:
	return PackedStringArray(CATEGORIES.map(func(c): return str(c[0])))


static func rarity_ids() -> PackedStringArray:
	return PackedStringArray(RARITIES.map(func(r): return str(r[0])))


static func effect_ids() -> PackedStringArray:
	return PackedStringArray(EFFECTS.map(func(e): return str(e[0])))


static func category_name(cat: String, plural: bool = false) -> String:
	for c in CATEGORIES:
		if c[0] == cat:
			return str(c[1] if plural else c[2])
	return cat.capitalize()


static func rarity_color(rarity: String) -> Color:
	for r in RARITIES:
		if r[0] == rarity:
			return Color(str(r[2]))
	return Color(str(RARITIES[0][2]))


static func rarity_name(rarity: String) -> String:
	for r in RARITIES:
		if r[0] == rarity:
			return str(r[1])
	return "Common"


static func rarity_rank(rarity: String) -> int:
	return maxi(0, rarity_ids().find(rarity))


## Where it goes when equipped: weapon / head / body / accessory, or "".
static func equip_slot(item: Dictionary) -> String:
	match str(item.get("category", "")):
		"weapon":
			return "weapon"
		"armor":
			return str(item.get("slot", "head"))
	return ""


static func parse_tags(text: String) -> Array:
	var out: Array = []
	for t in text.replace(";", ",").split(","):
		var s := t.strip_edges().to_lower()
		if s != "" and not s in out:
			out.append(s)
	return out


## One line for the tooltip/details: what the effect does.
static func effect_text(item: Dictionary) -> String:
	var e: Dictionary = item.get("effect", {})
	var v := str(e.get("value", ""))
	match str(e.get("type", "none")):
		"mood":
			return "Gift effect: a %s mood boost" % (v if v != "" else "small")
		"aura":
			return "Tints your aura when used or worn"
		"sound":
			return "Plays a %s sound" % (v if v != "" else "chime")
		"message":
			return "Shows: \"%s\"" % v.substr(0, 60)
		"lighting":
			return "Briefly changes the room's light"
	return ""


static func tooltip(item: Dictionary, count: int = -1) -> String:
	var lines := PackedStringArray()
	lines.append("%s%s" % [item.get("name", "?"), (" ×%d" % count) if count > 1 else ""])
	var kind := category_name(str(item.category))
	if str(item.category) == "armor":
		kind += " (%s)" % str(item.slot)
	lines.append("%s %s" % [rarity_name(str(item.rarity)), kind.to_lower()])
	if str(item.get("flavor", "")) != "":
		lines.append("\"%s\"" % item.flavor)
	for s in item.get("stats", []):
		lines.append("%s: %s" % [s.get("name", ""), stat_text(s.get("value", ""))])
	var eff := effect_text(item)
	if eff != "":
		lines.append(eff)
	return "\n".join(lines)


## JSON turns 9 into 9.0; stats read better as whole numbers.
static func stat_text(v: Variant) -> String:
	if (v is float or v is int) and is_equal_approx(float(v), roundf(float(v))):
		return str(int(roundf(float(v))))
	return str(v)


# --- Pictures --------------------------------------------------------------------------------

static func icon_texture(item: Dictionary) -> Texture2D:
	var rel := str(item.get("icon", ""))
	if rel != "":
		var tex := SaveManager.load_texture("items/%s/%s" % [item.get("id", ""), rel])
		if tex:
			return tex
	var auto: Dictionary = item.get("auto_icon", {})
	return ItemArt.texture(str(auto.get("shape", ItemArt.default_shape(str(item.get("category", "")), str(item.get("slot", ""))))), str(auto.get("color", "#e8b04a")))


static func icon_image(item: Dictionary) -> Image:
	var rel := str(item.get("icon", ""))
	if rel != "":
		var img := Image.load_from_file(dir(str(item.get("id", ""))).path_join(rel))
		if img and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			return img
	var auto: Dictionary = item.get("auto_icon", {})
	return ItemArt.icon(str(auto.get("shape", ItemArt.default_shape(str(item.get("category", "")), str(item.get("slot", ""))))), str(auto.get("color", "#e8b04a")))


## The picture used in the world (pickups, gear on the player): the world
## sprite if there is one, else the icon.
static func world_image(item: Dictionary) -> Image:
	var rel := str(item.get("sprite", ""))
	if rel != "":
		var img := Image.load_from_file(dir(str(item.get("id", ""))).path_join(rel))
		if img and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			return img
	return icon_image(item)


static func world_texture(item: Dictionary) -> Texture2D:
	var rel := str(item.get("sprite", ""))
	if rel != "":
		var tex := SaveManager.load_texture("items/%s/%s" % [item.get("id", ""), rel])
		if tex:
			return tex
	return icon_texture(item)


## Saves a drawn/imported picture as the item's icon or world sprite
## (kind: "icon" | "sprite"), shrunk if it's huge. The item must be saved.
static func set_picture(item: Dictionary, kind: String, img: Image) -> void:
	if img == null or img.is_empty():
		return
	if str(item.get("id", "")) == "":
		save_item(item)
	var limit := ICON_MAX if kind == "icon" else SPRITE_MAX
	var pic := img.duplicate() as Image
	pic.convert(Image.FORMAT_RGBA8)
	if maxi(pic.get_width(), pic.get_height()) > limit:
		var s := float(limit) / maxi(pic.get_width(), pic.get_height())
		pic.resize(maxi(1, int(pic.get_width() * s)), maxi(1, int(pic.get_height() * s)), Image.INTERPOLATE_NEAREST)
	var file := kind + ".png"
	JsonUtil.ensure_dir(dir(str(item.id)))
	pic.save_png(dir(str(item.id)).path_join(file))
	SaveManager.forget_texture("items/%s/%s" % [item.id, file])
	item[kind] = file


static func clear_picture(item: Dictionary, kind: String) -> void:
	var file := str(item.get(kind, ""))
	if file != "" and str(item.get("id", "")) != "":
		DirAccess.remove_absolute(dir(str(item.id)).path_join(file))
		SaveManager.forget_texture("items/%s/%s" % [item.id, file])
	item[kind] = ""
