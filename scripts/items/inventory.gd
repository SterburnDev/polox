extends RefCounted
## The player's bag: stacks of item ids plus what's equipped, kept in
## GameState.inventory and saved as inventory.json in the world. Pure data;
## the effects of using or wearing things live in item_effects.gd.

const Items := preload("res://scripts/items/items.gd")

const MAX_STACK := 99
const SLOTS: PackedStringArray = ["weapon", "head", "body", "accessory"]
const SLOT_NAMES := {"weapon": "Weapon", "head": "Head", "body": "Body", "accessory": "Accessory"}
const SORTS := [["newest", "Newest"], ["name", "Name"], ["rarity", "Rarity"], ["category", "Type"]]


static func defaults() -> Dictionary:
	return {"version": 2, "stacks": [], "equipped": {"weapon": "", "head": "", "body": "", "accessory": ""}, "outfits": {}}


static func active_realm() -> String:
	return GameState.current_realm


static func _bag() -> Dictionary:
	if not GameState.inventory.get("stacks") is Array:
		GameState.inventory["stacks"] = []
	if not GameState.inventory.get("equipped") is Dictionary:
		GameState.inventory["equipped"] = defaults().equipped
	if not GameState.inventory.get("outfits") is Dictionary:
		GameState.inventory["outfits"] = {}
	# Legacy gear stays owned and is copied into both outfits. Only an explicit
	# binding can make it inactive; neutral items gain no new restriction.
	for realm in ["light", "dark"]:
		if not GameState.inventory.outfits.get(realm) is Dictionary:
			GameState.inventory.outfits[realm] = GameState.inventory.equipped.duplicate(true)
	GameState.inventory["version"] = 2
	return GameState.inventory


static func _find(id: String) -> Dictionary:
	for s in _bag().stacks:
		if s is Dictionary and str(s.get("item", "")) == id:
			return s
	return {}


static func count(id: String) -> int:
	return int(_find(id).get("count", 0))


## Adds n of an item. Returns the new count.
static func add(id: String, n: int = 1) -> int:
	if not Items.exists(id) or n <= 0:
		return count(id)
	var before := _bag().duplicate(true)
	var s := _find(id)
	if s.is_empty():
		s = {"item": id, "count": 0, "added": Time.get_unix_time_from_system()}
		_bag().stacks.append(s)
	s["count"] = mini(MAX_STACK, int(s.get("count", 0)) + n)
	if not GameState.save_inventory():
		GameState.inventory = before
	return count(id)


## Removes n. Unequips the last one if it was being worn. False if there weren't enough.
static func remove(id: String, n: int = 1) -> bool:
	var s := _find(id)
	if n <= 0 or s.is_empty() or int(s.get("count", 0)) < n:
		return false
	var before := _bag().duplicate(true)
	s["count"] = int(s.count) - n
	if int(s.count) <= 0:
		_bag().stacks.erase(s)
		for slot in SLOTS:
			if str(_bag().equipped.get(slot, "")) == id:
				_bag().equipped[slot] = ""
			for realm in ["light", "dark"]:
				if str(_bag().outfits[realm].get(slot, "")) == id:
					_bag().outfits[realm][slot] = ""
	if not GameState.save_inventory():
		GameState.inventory = before
		return false
	return true


## An action resolved after a queued turn spends the latest persisted stack.
## Refresh and commit have no awaits, so another main-thread sync cannot interleave.
static func consume(id: String, n: int = 1) -> bool:
	if n <= 0:
		return false
	var path := SaveManager.abs_path("inventory.json")
	if not FileAccess.file_exists(path):
		return false
	SaveManager.forget_baselines(path)
	GameState.inventory = SaveManager.load_inventory()
	return remove(id, n)


## [{item: Dictionary, count: int, added: float}] for every stack whose design still exists.
static func stacks() -> Array:
	var out: Array = []
	for s in _bag().stacks:
		if not s is Dictionary:
			continue
		var it := Items.load_item(str(s.get("item", "")))
		if not it.is_empty() and int(s.get("count", 0)) > 0:
			out.append({"item": it, "count": int(s.count), "added": float(s.get("added", 0))})
	return out


static func total_items() -> int:
	var n := 0
	for s in _bag().stacks:
		n += int(s.get("count", 0)) if s is Dictionary else 0
	return n


## Filters by category ("all" or a category id) and a search text, then sorts.
static func view(category: String = "all", search: String = "", sort_by: String = "newest") -> Array:
	var q := search.strip_edges().to_lower()
	var list := stacks().filter(func(s):
		var it: Dictionary = s.item
		if category != "all" and str(it.category) != category:
			return false
		if q == "":
			return true
		return str(it.name).to_lower().contains(q) or str(it.get("flavor", "")).to_lower().contains(q) or q in it.get("tags", []))
	match sort_by:
		"name":
			list.sort_custom(func(a, b): return str(a.item.name).naturalnocasecmp_to(str(b.item.name)) < 0)
		"rarity":
			list.sort_custom(func(a, b):
				var ra := Items.rarity_rank(str(a.item.rarity))
				var rb := Items.rarity_rank(str(b.item.rarity))
				return ra > rb if ra != rb else str(a.item.name).naturalnocasecmp_to(str(b.item.name)) < 0)
		"category":
			list.sort_custom(func(a, b):
				var ca := Items.category_ids().find(str(a.item.category))
				var cb := Items.category_ids().find(str(b.item.category))
				return ca < cb if ca != cb else str(a.item.name).naturalnocasecmp_to(str(b.item.name)) < 0)
		_:
			list.sort_custom(func(a, b): return float(a.added) > float(b.added))
	return list


# --- Equipping ------------------------------------------------------------------------------

## slot -> item id, only for things you still have.
static func equipped(realm: String = "") -> Dictionary:
	if realm == "":
		realm = active_realm()
	if not realm in ["light", "dark"]:
		realm = active_realm()
	var outfit: Dictionary = _bag().outfits[realm]
	var out := {}
	for slot in SLOTS:
		var id := str(outfit.get(slot, ""))
		var item := Items.load_item(id) if id != "" and count(id) > 0 else {}
		out[slot] = id if not item.is_empty() and Items.equip_slot(item) == slot and Items.allowed_in_realm(item, realm) else ""
	return out


## The old field remains a compatibility mirror, never the authoritative loadout.
static func normalize() -> void:
	_bag()["equipped"] = equipped()


static func is_equipped(id: String) -> bool:
	# Most items aren't in the outfit at all: no need to read the worn items' files for them.
	if id == "" or not id in (_bag().outfits.get(active_realm(), {}) as Dictionary).values():
		return false
	return id in equipped().values()


## Puts it on (replacing whatever was in that slot). Returns the slot, or "".
static func equip(id: String, realm: String = "") -> String:
	if realm == "":
		realm = active_realm()
	var it := Items.load_item(id)
	var slot := Items.equip_slot(it)
	if not realm in ["light", "dark"] or slot == "" or count(id) <= 0 or not Items.allowed_in_realm(it, realm):
		return ""
	var before := _bag().duplicate(true)
	_bag().outfits[realm][slot] = id
	normalize()
	if not GameState.save_inventory():
		GameState.inventory = before
		return ""
	return slot


static func unequip(slot: String, realm: String = "") -> void:
	if realm == "":
		realm = active_realm()
	if slot in SLOTS and realm in ["light", "dark"]:
		_bag().outfits[realm][slot] = ""
		normalize()
		GameState.save_inventory()


static func unequip_item(id: String) -> void:
	for slot in SLOTS:
		for realm in ["light", "dark"]:
			if str(_bag().outfits[realm].get(slot, "")) == id:
				_bag().outfits[realm][slot] = ""
	normalize()
	GameState.save_inventory()


## "wearing a Tea-cozy helmet and holding a Wooden spoon" for the AI.
static func gear_line() -> String:
	var eq := equipped()
	var worn := PackedStringArray()
	for slot in ["head", "body", "accessory"]:
		if str(eq[slot]) != "":
			worn.append(str(Items.load_item(str(eq[slot])).get("name", "")))
	var bits := PackedStringArray()
	if not worn.is_empty():
		bits.append("wearing " + ", ".join(worn))
	if str(eq.weapon) != "":
		bits.append("holding " + str(Items.load_item(str(eq.weapon)).get("name", "")))
	return " and ".join(bits)
