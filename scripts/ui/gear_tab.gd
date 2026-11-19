extends BoxContainer
## My character > "Gear": the four equip slots (weapon, head, body,
## accessory) with what's in them, a big preview of you wearing it, and the
## "show gear on my character" switch. Equipping happens in the Bag.

signal open_bag

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Items := preload("res://scripts/items/items.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const ItemEffects := preload("res://scripts/items/item_effects.gd")
const ItemButton := preload("res://scripts/ui/item_button.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")

var world: Node
var _slots: VBoxContainer
var _preview: TextureRect
var _show: CheckBox
var realm := ""


func build() -> void:
	name = "Gear"
	realm = Inventory.active_realm()
	vertical = UiKit.upright_phone()   # slots above the preview on a phone
	add_theme_constant_override("separation", 18)
	_slots = UiKit.vbox(8)
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_slots)
	var right := UiKit.vbox(8)
	right.custom_minimum_size.x = 260
	add_child(right)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(240, 240)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_preview)
	_show = CheckBox.new()
	_show.text = "Show gear on my character"
	_show.button_pressed = bool(GameState.world.player.get("show_gear", true))
	_show.toggled.connect(func(on):
		GameState.world.player["show_gear"] = on
		GameState.save_world()
		if world:
			world.refresh_gear()
		refresh())
	right.add_child(_show)
	right.add_child(UiKit.button("Open the bag", func(): open_bag.emit(), 0))
	refresh()


func refresh() -> void:
	for c in _slots.get_children():
		c.queue_free()
	var selector := UiKit.option(["Light World outfit", "Dream World outfit"], 0 if realm == "light" else 1)
	selector.item_selected.connect(func(i):
		realm = "light" if i == 0 else "dark"
		refresh())
	_slots.add_child(selector)
	_slots.add_child(UiKit.para("Wearing this outfit." if realm == Inventory.active_realm() else "Previewing. You'll wear it in the other world.", 18, ThemeBuilder.MUTED))
	var eq := Inventory.equipped(realm)
	for slot in Inventory.SLOTS:
		var row := UiKit.hbox(10)
		var l := UiKit.label(str(Inventory.SLOT_NAMES[slot]), 20, ThemeBuilder.YELLOW)
		l.custom_minimum_size.x = 120
		row.add_child(l)
		var id := str(eq[slot])
		if id == "":
			row.add_child(UiKit.label("(empty)", 18, ThemeBuilder.MUTED))
		else:
			var it := Items.load_item(id)
			var b := ItemButton.make(it, 1, true, 64)
			b.focus_mode = Control.FOCUS_NONE
			row.add_child(b)
			row.add_child(UiKit.label(str(it.name), 18, Items.rarity_color(str(it.rarity))))
			row.add_child(UiKit.spacer())
			row.add_child(UiKit.button("Take off", func():
				Inventory.unequip(slot, realm)
				if world and realm == Inventory.active_realm():
					world.refresh_gear()
				refresh(), 130))
		_slots.add_child(row)
		var choices: Array = [{"id": "", "name": "(choose from bag)"}]
		for stack in Inventory.stacks():
			if Items.equip_slot(stack.item) == slot and Items.allowed_in_realm(stack.item, realm):
				choices.append(stack.item)
		var choose := UiKit.option(choices.map(func(it): return str(it.name)))
		choose.item_selected.connect(func(i):
			if i > 0:
				Inventory.equip(str(choices[i].id), realm)
				if world and realm == Inventory.active_realm():
					world.refresh_gear()
				refresh())
		_slots.add_child(choose)
	PlayerLook.invalidate()
	_preview.texture = PlayerLook.texture("real" if realm == "light" else "dark", "neutral")
