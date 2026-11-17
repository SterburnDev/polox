extends ScrollContainer
## My character > "Looks": Real Me and Dream World Me. Pick which form to
## edit, wear it, give it a name and a few words for your friends, design it
## in the doll maker or draw it yourself (all eight faces), and choose rooms
## that switch you into a form automatically.

signal edited

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const DollMaker := preload("res://scripts/ui/doll_maker.gd")
const CharacterCreator := preload("res://scripts/ui/character_creator.gd")

var open_panel: Callable
var world: Node
var form := "real"
var doll: BoxContainer             # doll_maker.gd
var doll_dirty := false
var _v: VBoxContainer
var _form_btns: Dictionary = {}
var _mode_btns: Dictionary = {}
var _wear_btn: Button
var _label_edit: LineEdit
var _looks_edit: LineEdit
var _body: VBoxContainer
var _custom_preview: HBoxContainer


func build() -> void:
	name = "Looks"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form = PlayerLook.current()
	_v = UiKit.vbox(10)
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_v)
	var top := UiKit.flow_row(8)
	for f in PlayerLook.FORMS:
		var b := UiKit.button(PlayerLook.label(f), func(): set_form(f), 200)
		b.toggle_mode = true
		_form_btns[f] = b
		top.add_child(b)
	top.add_child(UiKit.spacer())
	_wear_btn = UiKit.button("", func(): wear(), 250)
	top.add_child(_wear_btn)
	_v.add_child(top)
	_label_edit = UiKit.line_edit("Form name")
	_label_edit.max_length = 30
	_label_edit.text_changed.connect(func(t):
		PlayerLook.set_field(form, "label", t.strip_edges())
		_form_btns[form].text = PlayerLook.label(form)
		edited.emit())
	_v.add_child(UiKit.field_row("Name", _label_edit, 120))
	_looks_edit = UiKit.line_edit("")
	_looks_edit.max_length = 200
	_looks_edit.tooltip_text = "Friends hear this when they wonder what you look like. Blank = described from the doll."
	_looks_edit.text_changed.connect(func(t):
		PlayerLook.set_field(form, "looks", t.strip_edges())
		edited.emit())
	_v.add_child(UiKit.field_row("Looks like", _looks_edit, 120))
	var modes := UiKit.flow_row(8)
	for m in [["doll", "Doll maker"], ["custom", "My own drawing"]]:
		var b := UiKit.button(str(m[1]), func(): set_mode(str(m[0])), 200)
		b.toggle_mode = true
		_mode_btns[m[0]] = b
		modes.add_child(b)
	_v.add_child(modes)
	_body = UiKit.vbox(8)
	_v.add_child(_body)
	_v.add_child(UiKit.para("Real Me is worn in the Light World. Dream World Me is worn in the Dream World. You can edit either look here.", 18, ThemeBuilder.MUTED))
	set_form(form)


func set_form(f: String) -> void:
	save_pending()
	form = f
	for k in _form_btns:
		_form_btns[k].set_pressed_no_signal(k == f)
	var d := PlayerLook.form_data(f)
	_label_edit.set_block_signals(true)
	_label_edit.text = str(d.get("label", PlayerLook.label(f)))
	_label_edit.set_block_signals(false)
	_looks_edit.set_block_signals(true)
	_looks_edit.text = str(d.get("looks", ""))
	_looks_edit.set_block_signals(false)
	_rebuild_body()


func _rebuild_body() -> void:
	var d := PlayerLook.form_data(form)
	for k in _mode_btns:
		_mode_btns[k].set_pressed_no_signal(k == str(d.mode))
	for c in _body.get_children():
		c.queue_free()
	doll = null
	_looks_edit.placeholder_text = PlayerLook.describe(form) if str(d.looks) == "" else ""
	if str(d.mode) == "doll":
		doll = DollMaker.new()
		doll.setup(d.doll)
		doll.changed.connect(func():
			doll_dirty = true
			edited.emit())
		_body.add_child(doll)
		_body.add_child(UiKit.para("Changes are saved when you switch forms or close this screen.", 16, ThemeBuilder.MUTED))
	else:
		_custom_preview = UiKit.hbox(6)
		_body.add_child(_custom_preview)
		_fill_custom_preview()
		var row := UiKit.hbox(8)
		row.add_child(UiKit.button("Draw / import faces...", func(): open_creator(), 260))
		_body.add_child(row)
	_wear_btn.text = "You're wearing this form" if form == PlayerLook.current() else ("Worn in the Light World" if form == "real" else "Worn in the Dream World")
	_wear_btn.disabled = true


func _fill_custom_preview() -> void:
	for c in _custom_preview.get_children():
		c.queue_free()
	for e in PlayerLook.emotions(form):
		var t := TextureRect.new()
		t.texture = ImageTexture.create_from_image(PlayerLook.base_image(form, e))
		t.custom_minimum_size = Vector2(72, 72)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.tooltip_text = e
		_custom_preview.add_child(t)


## Doll maker <-> your own drawing. Drawing starts from the doll's faces.
func set_mode(m: String) -> void:
	var d := PlayerLook.form_data(form)
	if m == str(d.mode):
		return
	if m == "doll":
		PlayerLook.use_doll(form)
	else:
		save_pending()
		PlayerLook.set_field(form, "mode", "custom")
		PlayerLook.invalidate()
		open_creator()
	doll_dirty = false
	_rebuild_body()
	edited.emit()


func open_creator() -> void:
	var cc := CharacterCreator.new()
	cc.edit_player_form(form)
	cc.saved.connect(func(_id):
		if is_inside_tree():
			_rebuild_body())
	open_panel.call(cc)


func wear() -> void:
	save_pending()
	PlayerLook.set_form(form)
	_rebuild_body()


func save_pending() -> void:
	if doll_dirty and doll:
		PlayerLook.save_doll(form, doll.recipe)
	doll_dirty = false


func _room_ties() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	var choices := ["Either (no change)"] + Array(PlayerLook.FORMS).map(func(f): return PlayerLook.label(f))
	for id in SaveManager.list_rooms():
		var room := SaveManager.load_room(id)
		grid.add_child(UiKit.label(str(room.get("name", id)), 18, ThemeBuilder.CREAM))
		var o := UiKit.option(choices, PlayerLook.FORMS.find(PlayerLook.room_form(room)) + 1)
		o.item_selected.connect(func(i): set_room_form(id, "" if i == 0 else PlayerLook.FORMS[i - 1]))
		grid.add_child(o)
	return grid


func set_room_form(room_id: String, f: String) -> void:
	# Kept for old callers. Realm membership now controls the worn form centrally.
	var expected := PlayerLook.room_form(SaveManager.load_room(room_id))
	if f != expected:
		return
	if world and room_id == GameState.current_room_id:
		world.room.data["player_form"] = f
		SaveManager.save_room(world.room.data)
	else:
		var room := SaveManager.load_room(room_id)
		room["player_form"] = f
		SaveManager.save_room(room)
	edited.emit()
