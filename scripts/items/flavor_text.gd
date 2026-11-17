extends RefCounted
## Flavor text for items: an offline idea generator (always works, also
## used by Mock mode) and an optional AI suggestion that falls back to it.

const Items := preload("res://scripts/items/items.gd")

const LINES := {
	"weapon": [
		"Sharp enough to cut birthday cake, gentle enough to never need to.",
		"{name} hums a tiny fanfare whenever you're brave.",
		"Forged on a rainy afternoon, mostly out of good intentions.",
		"It has never won a fight. It has never needed to.",
		"Swing it once and somewhere, a dust bunny surrenders.",
	],
	"armor": [
		"Stops worries at a range of about three feet.",
		"{name}: rated cozy against all known weather.",
		"Smells faintly of laundry day and courage.",
		"Fits perfectly, as if it had been waiting for you.",
		"Worn by heroes, nappers, and heroes who nap.",
	],
	"consumable": [
		"Tastes like {tag} and a slow Saturday morning.",
		"Best shared. Second best: eaten very slowly.",
		"One bite and the room gets a little warmer.",
		"Made with love and, honestly, too much sugar.",
		"{name}: a snack with a suspiciously good attitude.",
	],
	"keepsake": [
		"Holds exactly one good memory. Yours, probably.",
		"It doesn't do anything. It just makes you smile.",
		"Found where the sunlight pools in the afternoon.",
		"Somebody kept this safe for a very long time.",
		"{name} glows a little when someone thinks of you.",
	],
}


## A whimsical line for the item. `variant` picks another one ("Suggest again").
static func offline(item: Dictionary, variant: int = 0) -> String:
	var pool: Array = LINES.get(str(item.get("category", "keepsake")), LINES.keepsake)
	var idx := posmod(hash(str(item.get("name", ""))) + variant, pool.size())
	var tag_list: Array = item.get("tags", [])
	var tag := str(tag_list[0]) if not tag_list.is_empty() else "cinnamon"
	var item_name := str(item.get("name", "")).strip_edges()
	if item_name == "":
		item_name = "This"
	return str(pool[idx]).replace("{name}", item_name).replace("{tag}", tag)


## Asks the AI (or Mock) for one line; falls back to the offline idea on any
## failure. Returns {text, offline: bool}.
static func suggest(item: Dictionary, variant: int = 0) -> Dictionary:
	var desc := "%s (a %s %s%s)" % [item.get("name", "an item"), Items.rarity_name(str(item.get("rarity", "common"))).to_lower(),
		Items.category_name(str(item.get("category", ""))).to_lower(), (", tags: " + ", ".join(item.get("tags", []))) if not (item.get("tags", []) as Array).is_empty() else ""]
	var msgs := [
		{"role": "system", "content": "You write flavor text for items in a cozy, whimsical life-sim with no combat. One sentence, at most 20 words, gentle humor, no quotes, no emoji. Plain text only."},
		{"role": "user", "content": "Write flavor text for: %s" % desc},
	]
	var r: Dictionary = await AIClient.chat(msgs, {"json": false, "max_tokens": 60, "mock": {"mode": "flavor", "item": item, "variant": variant}})
	var text := clean(str(r.get("text", ""))) if r.get("ok", false) else ""
	if text == "":
		return {"text": offline(item, variant), "offline": true}
	return {"text": text, "offline": AIClient.is_mock()}


## First line, no wrapping quotes, at most 160 characters.
static func clean(raw: String) -> String:
	var t := raw.strip_edges()
	if t.begins_with("{"):
		return ""  # a model that answered in JSON anyway
	t = t.split("\n", false)[0] if t != "" else ""
	t = t.strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("“").trim_suffix("”").strip_edges()
	return t.substr(0, 160)
