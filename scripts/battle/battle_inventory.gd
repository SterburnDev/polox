extends RefCounted
## A battle spends real snacks. Refund only its own deltas on retry, retreat or cancellation.
## No whole-bag restoration: edits/sync additions made meanwhile remain intact.
const Inventory := preload("res://scripts/items/inventory.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
var path := ""
var spent: Dictionary = {}
var committed := false

func begin() -> void:
	path = SaveManager.abs_path("inventory.json")
	spent.clear()
	committed = false

func items() -> Array:
	var out: Array = []
	for st in Inventory.stacks():
		var it: Dictionary = st.item
		if str(it.get("category", "")) != "consumable":
			continue
		var heal := 15
		for stat in it.get("stats", []):
			if stat is Dictionary and str(stat.get("name", "")).to_lower() in ["hp", "heal", "heals"]:
				heal = clampi(int(stat.get("value", 15)), 1, 99)
		out.append({"id": str(it.id), "name": str(it.name), "heal": heal, "count": int(st.count)})
	return out

func consume(id: String) -> bool:
	if committed or path != SaveManager.abs_path("inventory.json") or id == "":
		return false
	if not Inventory.consume(id, 1):
		return false
	spent[id] = int(spent.get(id, 0)) + 1
	return true

func refund() -> bool:
	if committed or spent.is_empty():
		return true
	var current := path == SaveManager.abs_path("inventory.json")
	var raw: Variant = JsonUtil.read_json(path, {})
	if not raw is Dictionary or not raw.get("stacks") is Array:
		return false
	for id in spent:
		var found := false
		for s in raw.stacks:
			if s is Dictionary and str(s.get("item", "")) == id:
				s.count = int(s.get("count", 0)) + int(spent[id])
				found = true
				break
		if not found:
			raw.stacks.append({"item": id, "count": int(spent[id]), "added": Time.get_unix_time_from_system()})
	# A refund may briefly exceed MAX_STACK if a player replenished their bag mid-battle.
	# Keeping the owed snack is preferable to silently discarding it.
	if not JsonUtil.write_json(path, raw):
		return false
	spent.clear()
	if current:
		SaveManager.forget_baselines(path)
		GameState.inventory = raw
		GameState.inventory_changed.emit()
		SaveManager.saved.emit(path)
	return true

func commit() -> void:
	committed = true
	spent.clear()
