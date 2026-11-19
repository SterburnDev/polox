extends VBoxContainer
## Creator > "Faces": the list of expression slots plus Import / Clear /
## Blob template / canvas size, and Add / Copy / Remove for custom faces.
## Pure UI: it only emits signals; the Creator owns the images.

signal slot_selected(face: String)
signal import_pressed
signal clear_pressed
signal template_pressed
signal grid_changed(n: int)
signal add_requested(face_name: String)
signal copy_requested(source: String)
signal remove_requested

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Store := preload("res://scripts/ui/creator_store.gd")

var _slot_box: GridContainer
var _buttons: Dictionary = {}
var _order: Array = []
var _new_slot: LineEdit
var _copy_opt: OptionButton


func build(grid_size: int, avatar_mode: bool) -> void:
	name = "Faces"
	add_theme_constant_override("separation", 8)
	tooltip_text = "Click a face to draw it. Neutral is the default look; empty faces fall back to it."
	var quick := UiKit.hbox(6)
	var imp := UiKit.button("Import", func(): import_pressed.emit(), 96)
	imp.tooltip_text = "Bring in a PNG/JPG for this face"
	quick.add_child(imp)
	quick.add_child(UiKit.button("Clear", func(): clear_pressed.emit(), 84))
	var tmpl := UiKit.button("Blob", func(): template_pressed.emit(), 84)
	tmpl.tooltip_text = "Repaint the standard faces as a ready-made blob friend in the current color"
	quick.add_child(tmpl)
	var grid_opt := UiKit.option(["16x16", "32x32", "64x64", "128x128"], Store.GRIDS.find(grid_size))
	grid_opt.tooltip_text = "Canvas size (all faces)"
	grid_opt.custom_minimum_size.x = 130
	grid_opt.item_selected.connect(func(i): grid_changed.emit(Store.GRIDS[i]))
	quick.add_child(grid_opt)
	add_child(quick)
	_slot_box = GridContainer.new()
	_slot_box.columns = 2
	_slot_box.add_theme_constant_override("h_separation", 6)
	_slot_box.add_theme_constant_override("v_separation", 6)
	add_child(UiKit.scroll(_slot_box))
	if avatar_mode:
		return
	var add := UiKit.hbox(6)
	_new_slot = UiKit.line_edit("New face name, e.g. smug")
	_new_slot.max_length = 20
	_new_slot.text_submitted.connect(func(_t): _request_add())
	add.add_child(_new_slot)
	add.add_child(UiKit.button("Add", _request_add, 80))
	add_child(add)
	var copy := UiKit.hbox(6)
	_copy_opt = UiKit.option([])
	_copy_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(_copy_opt)
	copy.add_child(UiKit.button("Copy", func():
		if _copy_opt.selected >= 0 and _copy_opt.selected < _order.size():
			copy_requested.emit(str(_order[_copy_opt.selected])), 84))
	var rm := UiKit.button("Remove", func(): remove_requested.emit(), 104)
	rm.tooltip_text = "Remove the selected face"
	copy.add_child(rm)
	add_child(copy)


func _request_add() -> void:
	add_requested.emit(_new_slot.text)
	_new_slot.text = ""


## Recreates one button per face, with its picture as the icon.
func rebuild(order: Array, slots: Dictionary, current: String) -> void:
	_order = order
	for c in _slot_box.get_children():
		c.queue_free()
	_buttons.clear()
	for n in order:
		var b := UiKit.button(n, func(): slot_selected.emit(n))
		b.toggle_mode = true
		b.set_pressed_no_signal(n == current)
		b.icon = ImageTexture.create_from_image(slots[n])
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 36)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_buttons[n] = b
		_slot_box.add_child(b)
	if _copy_opt:
		_copy_opt.clear()
		for n in order:
			_copy_opt.add_item("From: " + n)


func set_current(face: String) -> void:
	for k in _buttons:
		_buttons[k].set_pressed_no_signal(k == face)


func update_icon(face: String, img: Image) -> void:
	if not _buttons.has(face):
		return
	var icon: ImageTexture = _buttons[face].icon
	if icon and icon.get_size() == Vector2(img.get_size()):
		icon.update(img)
	else:
		_buttons[face].icon = ImageTexture.create_from_image(img)
