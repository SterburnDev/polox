extends RefCounted
## The one tiny effect an item can have, played in the world: tint the
## player's aura, play a sound, show a message, or briefly change the
## room's light. The mood boost only matters when the item is a gift.
## Also the bag's "Use" and "Equip" actions, which trigger them.

const Items := preload("res://scripts/items/items.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const Synth := preload("res://scripts/core/synth.gd")

const AURA_SECONDS := 60.0
const LIGHT_SECONDS := 6.0


## context: "use" | "equip" | "gift". Returns the effect type that played ("" = none).
static func play(world: Node, item: Dictionary, context: String) -> String:
	var e: Dictionary = item.get("effect", {})
	var v := str(e.get("value", ""))
	match str(e.get("type", "none")):
		"aura":
			if context == "gift":
				return ""
			world.set_aura(Color.from_string(v, Color("#ffd166")), 0.0 if context == "equip" else AURA_SECONDS)
			return "aura"
		"sound":
			Synth.play(world, v if v in Items.SOUNDS else "chime")
			return "sound"
		"message":
			if v.strip_edges() == "":
				return ""
			if context == "gift" or world.talk.is_open():
				GameState.notify(v)
			else:
				world.talk.show_text(str(item.get("name", "")), v)
			return "message"
		"lighting":
			world.flash_light(Color.from_string(v, Color("#ffd166")), LIGHT_SECONDS)
			return "lighting"
		"mood":
			if context == "gift":
				return "mood"
	return ""


## The bag's Use button: snacks are eaten (one fewer), keepsakes admired.
static func use(world: Node, item: Dictionary) -> String:
	var id := str(item.get("id", ""))
	if Inventory.count(id) <= 0:
		return ""
	var what := play(world, item, "use")
	if str(item.get("category", "")) == "consumable":
		Inventory.remove(id, 1)
		if what != "sound":
			Synth.play(world, "munch")
		world.player.emote("♪", Color("#ffd166"))
		if what != "message":
			GameState.notify("Mm, %s. Lovely." % str(item.get("name", "")).to_lower())
	else:
		world.player.emote("✦", Items.rarity_color(str(item.get("rarity", "common"))))
		if what == "" or what == "sound":
			GameState.notify("You admire the %s for a while." % str(item.get("name", "")).to_lower())
	return what


## Wear or hold it (replacing whatever was in that slot). Returns the slot.
static func equip(world: Node, item: Dictionary) -> String:
	var slot := Inventory.equip(str(item.get("id", "")))
	if slot == "":
		return ""
	play(world, item, "equip")
	world.refresh_gear()
	return slot


static func unequip(world: Node, slot: String) -> void:
	Inventory.unequip(slot)
	world.refresh_gear()
