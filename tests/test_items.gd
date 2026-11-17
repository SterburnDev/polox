extends "res://tests/test_case.gd"
## Phase 10, the Item Workshop: designs, icons, the bag (sort/filter,
## equip, use), effects, pickups placed in the editor, flavor text with an
## offline fallback, and the acceptance run (both forms, craft three things,
## equip two, gift the snack, see the reaction in chat, mood and the log).

const Items := preload("res://scripts/items/items.gd")
const ItemArt := preload("res://scripts/items/item_art.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const ItemEffects := preload("res://scripts/items/item_effects.gd")
const Pickups := preload("res://scripts/items/pickups.gd")
const FlavorText := preload("res://scripts/items/flavor_text.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const Doll := preload("res://scripts/characters/doll.gd")
const ReplyParser := preload("res://scripts/ai/reply_parser.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")

var main: Node


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _shutdown() -> void:
	main.queue_free()
	await frames(2)


func test_designs_round_trip_and_icons() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	GameState.load_world()
	var it := Items.defaults("weapon")
	it["name"] = "Star Ladle"
	it["rarity"] = "legendary"
	it["tags"] = ["kitchen", "star"]
	it["stats"] = [{"name": "Sparkle", "value": 9}]
	it["effect"] = {"type": "sound", "value": "fanfare"}
	var id := Items.save_item(it)
	eq(id, "star_ladle")
	var back := Items.load_item(id)
	eq(back.name, "Star Ladle")
	eq(back.rarity, "legendary")
	eq(Items.equip_slot(back), "weapon")
	check(Items.tooltip(back).contains("Sparkle: 9") and Items.tooltip(back).contains("Legendary"), "tooltip shows rarity and stats")
	for shape in ItemArt.all_shapes():
		check(not ItemArt.icon(shape, "#cc8844").is_invisible(), "auto icon '%s' draws" % shape)
	var drawn := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	drawn.fill(Color.RED)
	Items.set_picture(back, "icon", drawn)
	Items.save_item(back)
	var icon := Items.icon_image(Items.load_item(id))
	check(icon.get_width() <= Items.ICON_MAX, "big drawings are shrunk")
	eq(icon.get_pixel(0, 0), Color.RED, "drawn icon used")
	eq(Items.world_image(Items.load_item(id)).get_pixel(0, 0), Color.RED, "no sprite: the world uses the icon")
	var bad := Items.sanitize({"category": "laser", "rarity": "mythic", "tags": "a, b", "stats": "x", "effect": {"type": "explode"}})
	eq(bad.category, "keepsake", "unknown types become keepsakes")
	eq(bad.rarity, "common")
	eq(bad.tags, ["a", "b"])
	eq(bad.effect.type, "none", "only effects from the list")
	var copy := Items.duplicate_item(id)
	check(Items.exists(copy) and copy != id, "duplicate")
	Items.delete_item(copy)
	check(not Items.exists(copy), "delete")
	check(Items.ids().size() >= 15, "starter designs exist")


func test_bag_sort_filter_equip_and_stack_limits() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	GameState.load_world()
	check(Inventory.total_items() > 0, "starter bag")
	eq(Inventory.add("moon_cookie", 200), Inventory.MAX_STACK, "stacks stop at 99")
	eq(Inventory.view("consumable").all(func(s): return s.item.category == "consumable"), true, "filter by type")
	var by_rarity := Inventory.view("all", "", "rarity")
	eq(str(by_rarity[0].item.id), "moon_cookie", "epic first when sorted by rarity")
	eq(Inventory.view("all", "pebble").size(), 1, "search")
	eq(Inventory.equip("wooden_spoon"), "weapon")
	eq(Inventory.equip("tea_cozy_helmet"), "head")
	eq(Inventory.equip("fresh_cookies"), "", "snacks can't be worn")
	check(Inventory.gear_line().contains("Tea-cozy helmet") and Inventory.gear_line().contains("holding Wooden spoon"), Inventory.gear_line())
	Inventory.remove("wooden_spoon", 1)
	eq(Inventory.equipped().weapon, "", "giving away the last one takes it off")
	var saved := SaveManager.load_inventory()
	eq(str(saved.equipped.head), "tea_cozy_helmet", "equipment is saved")


func test_effects_use_equip_and_gear_overlay() -> void:
	var g: Node = await _boot()
	var plain: Texture2D = g.player.sprite.texture
	var plain_size := plain.get_size()
	var wand := Items.load_item("bubble_wand")
	Inventory.add("bubble_wand")
	eq(ItemEffects.equip(g, wand), "weapon")
	check(g.player.aura_on(), "the wand's aura glows while held")
	check(g.player.sprite.texture.get_size() != plain_size, "gear is drawn onto the sprite")
	GameState.world.player["show_gear"] = false
	g.refresh_gear()
	eq(g.player.sprite.texture.get_size(), plain_size, "gear overlay can be turned off")
	GameState.world.player["show_gear"] = true
	ItemEffects.unequip(g, "weapon")
	check(not g.player.aura_on(), "aura gone with the wand")
	var cookies := Inventory.count("fresh_cookies")
	ItemEffects.use(g, Items.load_item("fresh_cookies"))
	eq(Inventory.count("fresh_cookies"), cookies - 1, "snacks are eaten")
	var pebbles := Inventory.count("shiny_pebble")
	ItemEffects.use(g, Items.load_item("shiny_pebble"))
	eq(Inventory.count("shiny_pebble"), pebbles, "keepsakes are kept")
	Inventory.add("moon_cookie")
	eq(ItemEffects.use(g, Items.load_item("moon_cookie")), "message", "message effect")
	check(g.talk.is_open(), "the message shows in the text box")
	g.dialogue.close_box()
	Inventory.add("moth_wing_cloak")
	eq(ItemEffects.play(g, Items.load_item("moth_wing_cloak"), "use"), "lighting")
	check(g.light_flashing, "the room's light changes for a moment")
	await _shutdown()


func test_pickups_from_the_editor() -> void:
	var g: Node = await _boot()
	var b: Node = g.build
	b.enter()
	await frames(1)
	b.set_piece("pickup")
	b.cursor = Vector2i(3, 3)
	b._press({})
	b._release()
	await frames(1)
	var objs: Array = g.room.data.objects.filter(func(o): return o.type == "pickup")
	eq(objs.size(), 1, "pickup placed")
	check(Items.exists(str(objs[0].item)), "it holds an item")
	for p in main.panels.duplicate():
		p.queue_free()   # the pickup editor popped up
	await frames(1)
	b.exit()
	await frames(1)
	var o: Dictionary = g.room.data.objects.filter(func(x): return x.type == "pickup")[0]
	o["item"] = "moon_cookie"
	o["respawn"] = "daily"
	check(g.room.object_nodes.has(str(o.id)), "the pickup is in the room")
	check(g.room.nav.walkable(Vector2i(3, 3)), "pickups don't block the way")
	var before := Inventory.count("moon_cookie")
	g.controller.walk_to(Vector2i(3, 3))
	var t0 := Time.get_ticks_msec()
	while g.player.is_moving() and Time.get_ticks_msec() - t0 < 8000:
		await frames(1)
	await frames(2)
	eq(Inventory.count("moon_cookie"), before + 1, "walking onto it picked it up")
	check(not Pickups.available(o), "gone for today")
	var saved := SaveManager.load_room(g.room.data.id)
	var again: Array = saved.objects.filter(func(x): return x.type == "pickup")
	eq(str(again[0].taken), Time.get_date_string_from_system(), "remembered after saving")
	again[0]["taken"] = "2000-01-01"
	check(Pickups.available(again[0]), "a daily pickup comes back the next day")
	o["respawn"] = "once"
	o["taken"] = "yes"
	check(not Pickups.available(o), "a one-time pickup stays gone")
	Pickups.reset(o)
	check(Pickups.available(o), "until you put it back in the editor")
	await _shutdown()


func test_flavor_text_suggestions_work_offline() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	GameState.load_world()
	var it := Items.defaults("consumable")
	it["name"] = "Moss muffin"
	it["tags"] = ["moss", "breakfast"]
	var a := FlavorText.offline(it, 0)
	check(a != "" and a != FlavorText.offline(it, 1), "offline ideas vary")
	AIClient.configure({"preset": "mock"})
	var r: Dictionary = await FlavorText.suggest(it)
	check(str(r.text) != "", "Mock suggests something")
	# A provider that can't be reached falls back to the offline idea.
	AIClient.configure({"preset": "custom", "base_url": "http://127.0.0.1:9/v1", "model": "x", "timeout_s": 2})
	AIClient.backoff_base_s = 0.05
	var off: Dictionary = await FlavorText.suggest(it)
	check(bool(off.offline) and str(off.text) != "", "offline fallback when the AI is unreachable")
	AIClient.backoff_base_s = 1.5
	AIClient.configure({"preset": "mock"})
	eq(FlavorText.clean("\"Tastes like rain.\"\nSecond line"), "Tastes like rain.")


## The Phase 10 acceptance, start to finish, through the same calls the UI makes.
func test_acceptance_both_forms_craft_equip_and_gift() -> void:
	var g: Node = await _boot()
	# 1. Build the player in both forms.
	PlayerLook.save_doll("real", Doll.preset("gardener"))
	var dark := Doll.preset("night")
	dark.hair.color = "#e86a8a"
	PlayerLook.save_doll("dark", dark)
	check(PlayerLook.texture("real", "neutral") != PlayerLook.texture("dark", "neutral"))
	# 2. Craft a weapon, an armor piece and a snack in the Workshop.
	var ws: Control = load("res://scripts/ui/item_workshop.gd").new()
	ws.world = g
	main.open_panel(ws)
	await frames(1)
	var made: Array = []
	for spec in [["weapon", "Comet Whisk"], ["armor", "Star Beanie"], ["consumable", "Honey Bun"]]:
		ws.new_item(spec[0])
		ws.item["name"] = spec[1]
		if spec[0] == "consumable":
			ws.item["tags"] = ["sweet", "cozy", "snack"]
		made.append(ws.make_one())
	ws.close()
	await frames(1)
	eq(made, ["comet_whisk", "star_beanie", "honey_bun"])
	for id in made:
		eq(Inventory.count(id), 1, "%s is in the bag" % id)
	eq(Items.load_item("star_beanie").slot, "head")
	# 3. Equip two from the Bag.
	var bag: Control = load("res://scripts/ui/inventory_panel.gd").new()
	bag.world = g
	main.open_panel(bag)
	await frames(1)
	bag.select("comet_whisk")
	eq(bag.equip_selected(), "weapon")
	bag.select("star_beanie")
	eq(bag.equip_selected(), "head")
	bag.close()
	await frames(1)
	check(Inventory.is_equipped("comet_whisk") and Inventory.is_equipped("star_beanie"), "two things equipped")
	# 4. Gift the snack to Mochi and see the reaction in chat, mood and the log.
	var id: String = GameState.characters.keys()[0]
	var mood_before := float(GameState.get_character(id).mood.happiness)
	g.talk.talk_to(id)
	await frames(1)
	await g.talk.give_gift("honey_bun")
	await frames(1)
	var c := GameState.get_character(id)
	var lines := ChatLog.read_all(id)
	var reply: Dictionary = lines.filter(func(e): return e.role == "ai").back()
	check(str(reply.text).to_lower().contains("honey bun"), "the reply is about the gift: " + str(reply.text))
	check(float(c.mood.happiness) > mood_before, "happier than before")
	check(lines.any(func(e): return e.get("kind") == "gift" and e.get("item") == "honey_bun"), "gift in the log")
	check(lines.any(func(e): return e.get("role") == "note" and str(e.text).contains("happiness")), "mood change in the log")
	eq(Inventory.count("honey_bun"), 0, "the snack left the bag")
	var ctx: Dictionary = preload("res://scripts/ai/conversation.gd").new().base_context(c)
	check(str(ctx.gifts_line).contains("Honey Bun"), "and it's in their AI context")
	check(str(ctx.profile.appearance).contains("Star Beanie"), "your gear is too")
	g.dialogue.close_box()
	await _shutdown()
