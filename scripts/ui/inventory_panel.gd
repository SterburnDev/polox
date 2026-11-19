extends "res://scripts/ui/screen_panel.gd"
## The bag: everything you carry in a grid, with type tabs, sort, search and
## tooltips. The details pane can Use, Equip / Take off, open the item in the
## Workshop or throw one away. Opened from a chat's Gift button, it becomes a
## gift picker instead ("Give to Mochi").

signal gift_chosen(item_id: String)

const Items := preload("res://scripts/items/items.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const ItemEffects := preload("res://scripts/items/item_effects.gd")
const ItemButton := preload("res://scripts/ui/item_button.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")
const GiftRules := preload("res://scripts/items/gift_rules.gd")

var world: Node                 # game_world.gd (Use/Equip act on it)
var gift_for := ""              # a character id: picking a gift for them
var selected := ""
var _filter := "all"
var _sort := "newest"
var _search: LineEdit
var _grid: HFlowContainer
var _detail: VBoxContainer
var _filter_btns: Dictionary = {}
var _count: Label
var _confirm: Control


func _ready() -> void:
	var c := GameState.get_character(gift_for)
	setup(("A gift for %s" % c.get("name", "a friend")) if gift_for != "" else "Bag", Vector2(1180, 680))
	var ws := UiKit.button("Item Workshop", open_workshop, 190)
	ws.tooltip_text = "Design new items, then add them to your bag"
	header.add_child(ws)
	header.move_child(ws, header.get_child_count() - 2)
	if gift_for != "":
		var liked := GiftRules.tags(c, "liked_tags")
		body.add_child(UiKit.para("%s likes: %s" % [c.get("name", ""), ", ".join(liked) if not liked.is_empty() else "(a mystery: try things and see!)"], 18, ThemeBuilder.MUTED))
	var top := HFlowContainer.new()   # wraps on narrow screens
	top.add_theme_constant_override("h_separation", 6)
	top.add_theme_constant_override("v_separation", 6)
	body.add_child(top)
	for f in [["all", "All"]] + Items.CATEGORIES.map(func(x): return [x[0], x[1]]):
		var b := UiKit.button(str(f[1]), func(): set_filter(str(f[0])), 0)
		b.toggle_mode = true
		_filter_btns[f[0]] = b
		top.add_child(b)
	var sort := UiKit.option(Inventory.SORTS.map(func(s): return "Sort: " + str(s[1])))
	sort.item_selected.connect(func(i):
		_sort = str(Inventory.SORTS[i][0])
		refresh())
	top.add_child(sort)
	_search = UiKit.line_edit("Search...")
	_search.custom_minimum_size.x = 160
	_search.size_flags_horizontal = Control.SIZE_SHRINK_END
	_search.text_changed.connect(func(_t): refresh())
	top.add_child(_search)
	# Side by side on wide screens; grid above the details on a portrait phone.
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.vertical = get_viewport_rect().size.x < 860.0
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UiKit.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.y = 220 if row.vertical else 0
	row.add_child(left)
	_grid = HFlowContainer.new()
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	# [GLASS_UI] The items sit in a tray: a recessed surface with each slot sunk into it.
	var tray := PanelContainer.new()
	tray.name = "Tray"
	tray.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tray.add_theme_stylebox_override("panel", ThemeBuilder.well(ThemeBuilder.BG.lerp(ThemeBuilder.PANEL_LIGHT, 0.35), Color(ThemeBuilder.CREAM, 0.18), ThemeBuilder.RADIUS_L, 1, 0.55, 12))
	tray.add_child(UiKit.scroll(_grid))
	left.add_child(tray)
	_count = UiKit.label("", 18, ThemeBuilder.MUTED)
	left.add_child(_count)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, Color(ThemeBuilder.CREAM, 0.3), 2, 10, 12))
	right.custom_minimum_size = Vector2(0, 300) if row.vertical else Vector2(380, 0)
	if row.vertical:
		# Tall phone: share the height, the details (and their buttons) need more than the grid.
		right.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right.size_flags_stretch_ratio = 1.6
	row.add_child(right)
	_detail = UiKit.vbox(8)
	right.add_child(UiKit.scroll(_detail))
	refresh()


func set_filter(f: String) -> void:
	_filter = f
	refresh()


func refresh() -> void:
	for k in _filter_btns:
		_filter_btns[k].set_pressed_no_signal(k == _filter)
	for c in _grid.get_children():
		c.queue_free()
	var list := Inventory.view(_filter, _search.text if _search else "", _sort)
	var ids: Array = []
	var worn: Array = Inventory.equipped().values()   # once: each lookup reads the worn items' files
	for s in list:
		var id := str(s.item.id)
		ids.append(id)
		var b := ItemButton.make(s.item, int(s.count), id in worn)
		b.pressed.connect(func(): select(id))
		_grid.add_child(b)
	if list.is_empty():
		var empty := UiKit.vbox(8)
		empty.add_child(UiKit.para("Nothing here yet. Make something in the Item Workshop, or find pickups around your rooms." if Inventory.total_items() == 0 else "Nothing matches.", 20, ThemeBuilder.MUTED))
		_grid.add_child(empty)
	_count.text = "%d things in your bag" % Inventory.total_items()
	if not selected in ids:
		selected = str(ids[0]) if not ids.is_empty() else ""
	_show_detail()


func select(id: String) -> void:
	selected = id
	_show_detail()


func _show_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if selected == "":
		_detail.add_child(UiKit.para("Pick an item to look at it up close.", 18, ThemeBuilder.MUTED))
		return
	var it := Items.load_item(selected)
	var n := Inventory.count(selected)
	var icon := TextureRect.new()
	icon.texture = Items.icon_texture(it)
	icon.custom_minimum_size = Vector2(128, 128)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail.add_child(icon)
	_detail.add_child(UiKit.para(str(it.name), 26, Items.rarity_color(str(it.rarity))))
	var kind := Items.category_name(str(it.category))
	if str(it.category) == "armor":
		kind += " • " + str(it.slot)
	_detail.add_child(UiKit.para("%s %s  •  ×%d%s" % [Items.rarity_name(str(it.rarity)), kind.to_lower(), n, "  •  equipped" if Inventory.is_equipped(selected) else ""], 18, ThemeBuilder.MUTED))
	if str(it.flavor) != "":
		_detail.add_child(UiKit.para("\"%s\"" % it.flavor, 18, ThemeBuilder.CREAM))
	for s in it.stats:
		_detail.add_child(UiKit.label("%s  %s" % [s.get("name", ""), Items.stat_text(s.get("value", ""))], 18, ThemeBuilder.YELLOW))
	if Items.effect_text(it) != "":
		_detail.add_child(UiKit.para(Items.effect_text(it), 18, ThemeBuilder.MINT))
	if not (it.tags as Array).is_empty():
		_detail.add_child(UiKit.para("Tags: " + ", ".join(it.tags), 16, ThemeBuilder.MUTED))
	var actions := UiKit.vbox(8)
	_detail.add_child(actions)
	if gift_for != "":
		var give := UiKit.button("Give to %s" % GameState.get_character(gift_for).get("name", "them"), func():
			gift_chosen.emit(selected)
			close(), 240)
		actions.add_child(give)
		give.call_deferred("grab_focus")
		return
	if str(it.category) in ["consumable", "keepsake"]:
		actions.add_child(UiKit.button("Eat / use" if str(it.category) == "consumable" else "Use", func(): use_selected(), 200))
	if Items.equip_slot(it) != "":
		if Inventory.is_equipped(selected):
			actions.add_child(UiKit.button("Take off", func():
				ItemEffects.unequip(world, Items.equip_slot(it))
				refresh(), 200))
		else:
			var equip := UiKit.button("Equip (%s)" % Items.equip_slot(it), func(): equip_selected(), 200)
			equip.disabled = not Items.allowed_in_realm(it, Inventory.active_realm())
			actions.add_child(equip)
			if equip.disabled:
				actions.add_child(UiKit.para("Worn in the %s World. Edit its outfit in My character > Gear." % str(it.realm).capitalize(), 16, ThemeBuilder.MUTED))
	actions.add_child(UiKit.para("To give it to someone, talk to them and press Gift.", 16, ThemeBuilder.MUTED))
	var row := UiKit.hbox(8)
	row.add_child(UiKit.button("Edit in Workshop", func(): open_workshop(selected), 200))
	row.add_child(UiKit.button("Throw one away", _ask_discard, 180))
	actions.add_child(row)


func use_selected() -> String:
	var it := Items.load_item(selected)
	var what := ItemEffects.use(world, it)
	refresh()
	return what


func equip_selected() -> String:
	var slot := ItemEffects.equip(world, Items.load_item(selected))
	if slot != "":
		GameState.notify("Equipped: %s" % Items.load_item(selected).get("name", ""))
	refresh()
	return slot


func _ask_discard() -> void:
	var it := Items.load_item(selected)
	_confirm = ConfirmPanel.new()
	add_child(_confirm)
	_confirm.ask("Throw away one %s?" % it.get("name", ""), "The design stays in the Item Workshop, so you can always make another.", "Throw away", "Keep it")
	_confirm.answered.connect(func(ok):
		_confirm = null
		if ok:
			Inventory.remove(selected, 1)
			refresh())


func open_workshop(item_id: String = "") -> void:
	var ws: Control = load("res://scripts/ui/item_workshop.gd").new()
	ws.world = world
	ws.start_item = item_id
	ws.closed.connect(func():
		if is_inside_tree():
			refresh())
	_main().open_panel(ws)


func _main() -> Node:
	return world.main if world else get_tree().current_scene


func on_back() -> bool:
	if _confirm and is_instance_valid(_confirm):
		_confirm.queue_free()
		_confirm = null
		return true
	close()
	return true
