extends RefCounted
## Pickups placed from the editor: an object {type: "pickup", item, count,
## respawn: "once" | "daily", taken: "" | "yes" | "<date>"}. Walking onto
## one puts the item in your bag; a daily one comes back tomorrow.

const Items := preload("res://scripts/items/items.gd")
const Inventory := preload("res://scripts/items/inventory.gd")

const RESPAWNS := [["once", "Just once"], ["daily", "Every day"]]


static func is_pickup(o: Dictionary) -> bool:
	return str(o.get("type", "")) == "pickup"


## True if it's there to be picked up right now.
static func available(o: Dictionary) -> bool:
	var taken := str(o.get("taken", ""))
	if taken == "":
		return true
	if str(o.get("respawn", "once")) == "daily":
		return taken != Time.get_date_string_from_system()
	return false


## Puts the item in the bag and marks the pickup taken (the caller saves the
## room). Returns the item, or {} if nothing was there.
static func collect(o: Dictionary) -> Dictionary:
	if not is_pickup(o) or not available(o):
		return {}
	var it := Items.load_item(str(o.get("item", "")))
	if it.is_empty():
		return {}
	Inventory.add(str(it.id), maxi(1, int(o.get("count", 1))))
	o["taken"] = Time.get_date_string_from_system() if str(o.get("respawn", "once")) == "daily" else "yes"
	return it


## "Put it back" in the editor.
static func reset(o: Dictionary) -> void:
	o["taken"] = ""
