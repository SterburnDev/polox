extends "res://scripts/ui/screen_panel.gd"
## The Item Workshop: every item design in this world on the left (with
## "new weapon / armor / snack / keepsake" buttons), the selected design's
## form on the right, and Save / "Make one" (adds it to your bag) /
## Duplicate / Delete underneath.

const Items := preload("res://scripts/items/items.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const ItemEditor := preload("res://scripts/ui/item_editor.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")

const NEW_NAMES := {"weapon": "New weapon", "armor": "New armor", "consumable": "New snack", "keepsake": "New keepsake"}

var world: Node
var start_item := ""
var item: Dictionary = {}          # the design being edited (a working copy)
var editor: VBoxContainer          # item_editor.gd
var _list: VBoxContainer
var _dirty := false
var _status: Label
var _confirm: Control


func _ready() -> void:
	setup("Item Workshop", Vector2(1260, 700))
	var row := UiKit.columns(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UiKit.vbox(8)
	left.custom_minimum_size.x = 300
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var news := GridContainer.new()
	news.columns = 2
	news.add_theme_constant_override("h_separation", 6)
	news.add_theme_constant_override("v_separation", 6)
	for c in Items.CATEGORIES:
		var b := UiKit.button("+ " + str(c[2]) if c[0] != "consumable" else "+ Snack", func(): new_item(str(c[0])), 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		news.add_child(b)
	left.add_child(news)
	_list = UiKit.vbox(4)
	left.add_child(UiKit.scroll(_list))
	var right := UiKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.0   # stacked on a phone: the editor gets most of the height
	row.add_child(right)
	editor = ItemEditor.new()
	editor.open_panel = func(p: Control): _main().open_panel(p)
	editor.edited.connect(func():
		_dirty = true
		_status.text = "Not saved yet")
	var scroll := UiKit.scroll(editor)
	right.add_child(scroll)
	var actions := UiKit.flow_row(8)
	actions.add_child(UiKit.button("Save", func(): save(), 110))
	var make := UiKit.button("Make one ✦", func(): make_one(), 170)
	make.tooltip_text = "Save, then put one in your bag"
	actions.add_child(make)
	actions.add_child(UiKit.button("Duplicate", _duplicate, 140))
	actions.add_child(UiKit.button("Delete", _ask_delete, 120))
	_status = UiKit.label("", 18, ThemeBuilder.MUTED)
	actions.add_child(_status)
	right.add_child(actions)
	if start_item != "" and Items.exists(start_item):
		select(start_item)
	else:
		var all := Items.all()
		if all.is_empty():
			new_item("keepsake")
		else:
			select(str(all[0].id))


func _main() -> Node:
	return world.main if world else get_tree().current_scene


func refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var by_cat := {}
	for it in Items.all():
		var k := str(it.category)
		if not by_cat.has(k):
			by_cat[k] = []
		by_cat[k].append(it)
	for c in Items.CATEGORIES:
		if not by_cat.has(c[0]):
			continue
		_list.add_child(UiKit.label(str(c[1]), 18, ThemeBuilder.YELLOW))
		for it in by_cat[c[0]]:
			var b := UiKit.button(str(it.name), func(): _switch_to(str(it.id)), 0)
			b.icon = Items.icon_texture(it)
			b.add_theme_constant_override("icon_max_width", 32)
			b.clip_text = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.set_pressed_no_signal(str(it.id) == str(item.get("id", "")))
			b.add_theme_color_override("font_color", Items.rarity_color(str(it.rarity)))
			var n := Inventory.count(str(it.id))
			b.tooltip_text = Items.tooltip(it) + ("\n(%d in your bag)" % n if n > 0 else "")
			_list.add_child(b)


func select(id: String) -> void:
	item = Items.load_item(id)
	editor.edit(item)
	_dirty = false
	_status.text = "%d in your bag" % Inventory.count(id)
	refresh_list()


## Switching away from unsaved changes keeps them: the form saves first.
func _switch_to(id: String) -> void:
	if _dirty:
		save()
	select(id)


func new_item(category: String) -> void:
	if _dirty:
		save()
	item = Items.defaults(category)
	item["name"] = NEW_NAMES.get(category, "New item")
	item["flavor"] = ""
	editor.edit(item)
	_dirty = true
	_status.text = "New design (not saved yet)"
	refresh_list()
	editor.name_edit.call_deferred("grab_focus")
	editor.name_edit.call_deferred("select_all")


func save() -> String:
	if str(item.get("name", "")).strip_edges() == "":
		item["name"] = NEW_NAMES.get(str(item.category), "New item")
	var id := Items.save_item(item)
	_dirty = false
	_status.text = "Saved ✓"
	refresh_list()
	return id


## Save, then one into the bag: that's crafting.
func make_one() -> String:
	var id := save()
	var n := Inventory.add(id, 1)
	_status.text = "Made one! (%d in your bag)" % n
	GameState.notify("✦ Made %s. It's in your bag." % item.get("name", ""))
	refresh_list()
	return id


func _duplicate() -> void:
	var id := save()
	select(Items.duplicate_item(id))


func _ask_delete() -> void:
	var id := str(item.get("id", ""))
	if id == "":
		new_item("keepsake")  # an unsaved new design: just drop it
		return
	_confirm = ConfirmPanel.new()
	add_child(_confirm)
	var n := Inventory.count(id)
	_confirm.ask("Delete %s?" % item.get("name", ""), "This removes the design%s. Pickups that hold it will be empty." % ((" and the %d in your bag" % n) if n > 0 else ""), "Delete", "Keep")
	_confirm.answered.connect(func(ok):
		_confirm = null
		if ok:
			if n > 0:
				Inventory.remove(id, n)
			Items.delete_item(id)
			var rest := Items.all()
			if rest.is_empty():
				new_item("keepsake")
			else:
				select(str(rest[0].id)))


func on_back() -> bool:
	if _confirm and is_instance_valid(_confirm):
		_confirm.queue_free()
		_confirm = null
		return true
	if _dirty:
		save()  # the Workshop never throws work away
	close()
	return true
