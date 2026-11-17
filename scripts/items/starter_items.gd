extends RefCounted
## Whimsical starter items (purely flavor): the old gift list as snacks and
## keepsakes, plus a little gear. New worlds and upgraded old worlds get
## these designs and a small bag to start with.

const Items := preload("res://scripts/items/items.gd")

## id, name, category, slot, rarity, icon shape, colour, tags, flavor, stats, effect
const ITEMS := [
	["cup_of_tea", "Cup of tea", "consumable", "", "common", "cup", "#e8dcc0", ["tea", "drink", "warm", "cozy"], "Steeped for exactly as long as a good daydream.", [["Warmth", 3]], ["sound", "chime"]],
	["mug_of_cocoa", "Mug of cocoa", "consumable", "", "common", "cup", "#8b5e3c", ["cocoa", "chocolate", "warm", "sweet"], "Comes with a marshmallow that refuses to sink.", [["Warmth", 4]], ["none", ""]],
	["fresh_cookies", "Fresh cookies", "consumable", "", "common", "cookie", "#d9a066", ["cookie", "snack", "sweet", "baking", "food"], "Still warm. Somehow always still warm.", [["Yum", 5]], ["mood", "small"]],
	["slice_of_cake", "Slice of cake", "consumable", "", "uncommon", "cake", "#f4a6c0", ["cake", "dessert", "sweet", "food"], "The corner piece, with the most frosting. Obviously.", [["Yum", 7]], ["mood", "medium"]],
	["moon_cookie", "Moon cookie", "consumable", "", "epic", "cookie", "#f3e9d2", ["cookie", "moon", "night", "sweet", "snack"], "Baked by moonlight. The crumbs float upward.", [["Yum", 9], ["Glow", 4]], ["message", "You feel like the night sky is rooting for you."]],
	["little_bouquet", "Little bouquet", "keepsake", "", "common", "flower", "#ff8fab", ["flower", "flowers", "nature", "garden", "pretty"], "Picked on the way here. Mostly not from a neighbour's garden.", [], ["none", ""]],
	["storybook", "Storybook", "keepsake", "", "uncommon", "book", "#6fb7ff", ["book", "books", "story", "stories", "reading"], "The last page is blank, in case you want to finish it.", [["Pages", 48]], ["none", ""]],
	["music_box", "Music box", "keepsake", "", "rare", "music_box", "#c58cff", ["music", "song", "songs", "humming"], "Plays a tune you're sure you've heard in a dream.", [], ["sound", "sparkle"]],
	["shiny_pebble", "Shiny pebble", "keepsake", "", "common", "pebble", "#b8c4d6", ["shiny", "rock", "rocks", "pebble", "collect", "treasure"], "Perfectly round. Perfectly pocket-sized. Perfect.", [["Shine", 2]], ["none", ""]],
	["star_stickers", "Star stickers", "keepsake", "", "common", "star", "#ffd166", ["star", "stars", "cute", "sticker", "sparkle"], "For notebooks, lamps, and anyone who did their best today.", [], ["none", ""]],
	["packet_of_seeds", "Packet of seeds", "keepsake", "", "common", "letter", "#7ad6b0", ["seeds", "garden", "grow", "plant", "spring"], "The label just says 'something nice'.", [], ["none", ""]],
	["wooden_spoon", "Wooden spoon of valor", "weapon", "", "uncommon", "spoon", "#c08a5a", ["wood", "kitchen", "baking", "silly"], "Has defeated many a stubborn jar of jam.", [["Valor", 7], ["Stirring", 10]], ["sound", "fanfare"]],
	["bubble_wand", "Bubble wand", "weapon", "", "rare", "wand", "#7af0ff", ["bubbles", "magic", "sparkle", "cute"], "Each bubble holds one tiny, polite wish.", [["Sparkle", 8]], ["aura", "#7af0ff"]],
	["tea_cozy_helmet", "Tea-cozy helmet", "armor", "head", "common", "helmet", "#e86a8a", ["tea", "knit", "cozy", "warm"], "Keeps your thoughts at a pleasant 70 degrees.", [["Coziness", 8]], ["none", ""]],
	["moth_wing_cloak", "Moth-wing cloak", "armor", "body", "rare", "robe", "#8f6bd8", ["night", "moth", "soft", "dark"], "Rustles softly, like someone turning a page.", [["Softness", 9]], ["lighting", "#6a4bd8"]],
	["friendship_bracelet", "Friendship bracelet", "armor", "accessory", "uncommon", "ring", "#ffd166", ["friend", "friendship", "cute", "handmade"], "Slightly uneven. Made with a lot of concentration.", [["Loyalty", 10]], ["none", ""]],
]
const STARTER_BAG := {"cup_of_tea": 2, "fresh_cookies": 3, "shiny_pebble": 1, "little_bouquet": 1, "star_stickers": 2, "wooden_spoon": 1, "tea_cozy_helmet": 1}


static func make(spec: Array) -> Dictionary:
	var it := Items.defaults(str(spec[2]), str(spec[3]))
	it["id"] = str(spec[0])
	it["name"] = str(spec[1])
	it["rarity"] = str(spec[4])
	it["auto_icon"] = {"shape": str(spec[5]), "color": str(spec[6])}
	it["tags"] = (spec[7] as Array).duplicate()
	it["flavor"] = str(spec[8])
	var stats: Array = []
	for s in spec[9]:
		stats.append({"name": str(s[0]), "value": int(s[1])})
	it["stats"] = stats
	it["effect"] = {"type": str(spec[10][0]), "value": str(spec[10][1])}
	it["starter"] = true
	return it


## Writes any starter design the active world doesn't have yet (never
## overwrites your edits), then optionally fills an empty bag. Works on the
## files directly, so it can run before the world is loaded.
static func install(fill_bag: bool) -> void:
	for spec in ITEMS:
		if not Items.exists(str(spec[0])):
			Items.save_item(make(spec))
	if not fill_bag:
		return
	var bag := SaveManager.load_inventory()
	if not (bag.get("stacks", []) as Array).is_empty():
		return
	var now := Time.get_unix_time_from_system()
	var i := 0
	for id in STARTER_BAG:
		bag.stacks.append({"item": str(id), "count": int(STARTER_BAG[id]), "added": now - i})
		i += 1
	SaveManager.save_inventory(bag)
