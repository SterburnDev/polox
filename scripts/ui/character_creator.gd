extends "res://scripts/ui/screen_panel.gd"
## Character Creator: paint each expression on a pixel canvas (or import a
## PNG), fill in the personality card, preview it live, and save. Also used
## in "avatar mode" to paint one of the player's forms (all eight faces).

signal saved(id: String)

const PaintCanvas := preload("res://scripts/ui/paint_canvas.gd")
const CreatorTools := preload("res://scripts/ui/creator_tools.gd")
const CardTab := preload("res://scripts/ui/creator_card_tab.gd")
const Preview := preload("res://scripts/ui/creator_preview.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Store := preload("res://scripts/ui/creator_store.gd")
const FacesTab := preload("res://scripts/ui/creator_faces_tab.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const Doll := preload("res://scripts/characters/doll.gd")
const AnimTab := preload("res://scripts/ui/creator_anim_tab.gd")

var char_id := ""
var avatar_mode := false
var player_form := "real"         # avatar mode: which form is being painted
var data: Dictionary = {}
var slots: Dictionary = {}        # expression name -> Image
var order: Array = []
var current := "neutral"
var _removed: Array = []
var _history: Dictionary = {}     # expression name -> canvas undo history
var _dirty := false
var canvas: Control
var tools: VBoxContainer
var card: ScrollContainer
var preview: PanelContainer
var faces: VBoxContainer          # creator_faces_tab.gd
var _confirm: Control


## Call one of these before adding the panel to the tree.
func edit_character(id: String) -> void:
	char_id = id
	data = GameState.get_character(id).duplicate(true)


func new_character() -> void:
	char_id = ""
	data = Defaults.character("", "")
	data["home_room"] = GameState.current_room_id


func edit_avatar() -> void:
	edit_player_form(PlayerLook.current())


## Paints one of your forms; starts from its current faces (doll or drawing).
func edit_player_form(form: String) -> void:
	avatar_mode = true
	player_form = form
	data = {"name": GameState.player_name(), "form": form}


func _ready() -> void:
	setup(("Draw: " + PlayerLook.label(player_form)) if avatar_mode else ("Edit " + str(data.get("name", "")) if char_id != "" else "New friend"), Vector2(1250, 700))
	_load_slots()
	var row := UiKit.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	canvas = PaintCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(360, 360)
	row.add_child(canvas)
	canvas.set_image(slots[current])
	canvas.changed.connect(_on_canvas_changed)
	tools = CreatorTools.new()
	row.add_child(tools)
	tools.bind(canvas)
	var right := UiKit.vbox(10)
	right.custom_minimum_size.x = 430
	row.add_child(right)
	preview = Preview.new()
	right.add_child(preview)
	preview.faces = func(): return order.filter(func(n): return Store.has_pixels(slots[n]))
	preview.show_face = select_slot
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tabs)
	faces = FacesTab.new()
	faces.build(canvas.grid_size(), avatar_mode)
	faces.slot_selected.connect(select_slot)
	faces.import_pressed.connect(_import)
	faces.clear_pressed.connect(func(): canvas.clear_all())
	faces.template_pressed.connect(_template)
	faces.grid_changed.connect(_on_grid_changed)
	faces.add_requested.connect(add_slot)
	faces.copy_requested.connect(_copy_from)
	faces.remove_requested.connect(_remove_slot)
	tabs.add_child(faces)
	tabs.set_tab_title(0, "Faces")
	if not avatar_mode:
		card = CardTab.new()
		card.build(data)
		card.edited.connect(func():
			_dirty = true
			_refresh_preview())
		tabs.add_child(card)
		tabs.set_tab_title(1, "Personality")
	var anim := AnimTab.new()
	var anim_target := {"kind": "player", "form": player_form} if avatar_mode else {"kind": "character", "id": char_id}
	anim.build(anim_target, func(): return slots.get("neutral") if slots.has("neutral") else null)
	tabs.add_child(anim)
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Animations")
	# Save lives in the header so it's always visible, even on small screens.
	var save_btn := UiKit.button("Save", func(): save(), 120)
	var save_close := UiKit.button("Save & close", func():
		if save():
			close(), 180)
	header.add_child(save_btn)
	header.add_child(save_close)
	header.move_child(save_btn, header.get_child_count() - 3)
	header.move_child(save_close, header.get_child_count() - 3)
	_rebuild_slots()
	_refresh_preview()


func _load_slots() -> void:
	var loaded := Store.load_slots(data, avatar_mode)
	order = loaded.order
	slots = loaded.slots


func _rebuild_slots() -> void:
	faces.rebuild(order, slots, current)


func select_slot(n: String) -> void:
	if not slots.has(n):
		return
	_history[current] = canvas.get_history()
	current = n
	canvas.set_image(slots[n])
	canvas.set_history(_history.get(n, []))
	faces.set_current(n)
	_refresh_preview()


func _on_canvas_changed() -> void:
	_dirty = true
	slots[current] = canvas.image
	faces.update_icon(current, canvas.image)
	_refresh_preview()


func _refresh_preview() -> void:
	if preview == null or (not avatar_mode and card == null):
		return
	var img: Image = slots[current] if Store.has_pixels(slots[current]) else slots["neutral"]
	var who: String = GameState.player_name() if avatar_mode else card.name_edit.text.strip_edges()
	preview.set_face(ImageTexture.create_from_image(img), who, current)


func _on_grid_changed(n: int) -> void:
	for k in slots:
		if k != current:
			var img: Image = slots[k]
			img.resize(n, n, Image.INTERPOLATE_NEAREST)
	_history.clear()
	canvas.resize_grid(n)
	slots[current] = canvas.image
	_rebuild_slots()


func _copy_from(src: String) -> void:
	if src != current and slots.has(src):
		canvas.paste_image(slots[src])


func add_slot(face_name: String) -> void:
	var n := JsonUtil.slugify(face_name)
	if face_name.strip_edges() == "" or slots.has(n):
		GameState.notify("Pick a new, unused face name.")
		return
	var start: Image = (slots["neutral"].duplicate() as Image) if Store.has_pixels(slots["neutral"]) else Store.blank(canvas.grid_size())
	slots[n] = start
	order.append(n)
	_removed.erase(n)
	_dirty = true
	_rebuild_slots()
	select_slot(n)


func _remove_slot() -> void:
	if current == "neutral":
		GameState.notify("Neutral is the default face, so it can't be removed.")
		return
	_removed.append(current)
	slots.erase(current)
	order.erase(current)
	_history.erase(current)
	current = "neutral"
	_dirty = true
	_rebuild_slots()
	select_slot("neutral")


func _import() -> void:
	UiKit.pick_picture(self, "Pick a picture for the '%s' face" % current, import_file)


func import_file(path: String) -> bool:
	var img: Image = SaveManager.load_picture(path)
	if img == null:
		GameState.notify("Couldn't open that picture. Try a PNG or JPG under 40 MB.")
		return false
	canvas.import_image(img)
	return true


func _template() -> void:
	var any := false
	for n in slots:
		any = any or Store.has_pixels(slots[n])
	if not any:
		_apply_template()
		return
	_ask("Use the blob template?", "This repaints the 8 standard faces as a blob friend in your current color.", "Repaint", _apply_template)


func _apply_template() -> void:
	var n: int = canvas.grid_size()
	for e in Defaults.DEFAULT_EXPRESSIONS:
		# Your own forms start from your doll; friends from the blob.
		var img := Doll.compose(PlayerLook.form_data(player_form).doll, e) if avatar_mode else SpriteFactory.blob(e, canvas.color)
		img.resize(n, n, Image.INTERPOLATE_NEAREST)
		slots[e] = img
	_history.clear()
	canvas.set_image(slots[current])
	_dirty = true
	_rebuild_slots()
	_refresh_preview()


## Saves PNGs + the character card. Returns false if something's missing.
func save() -> bool:
	if not Store.has_pixels(slots.get("neutral")):
		GameState.notify("Draw the neutral face first. It's the default look.")
		select_slot("neutral")
		return false
	if avatar_mode:
		PlayerLook.save_custom(player_form, order, slots, _removed)
	else:
		card.apply_to(data)
		if str(data.get("name", "")) == "":
			data["name"] = "New Friend"
		if char_id == "":
			char_id = SaveManager.unique_id(data.name, SaveManager.list_characters())
			data["id"] = char_id
			data["pos"] = []
			GameState.add_moment("%s moved in!" % data.name, "You made a new friend: %s." % data.name, char_id)
		var exprs := Store.save_faces(char_id, order, slots, _removed)
		data["expressions"] = exprs
		GameState.save_character(data)
	_dirty = false
	GameState.notify("Saved %s ✓" % ("your look" if avatar_mode else str(data.get("name", ""))))
	saved.emit(char_id)
	return true


func _ask(title: String, msg: String, yes: String, on_yes: Callable, on_no: Callable = Callable(), no_text: String = "Cancel") -> void:
	_confirm = ConfirmPanel.new()
	add_child(_confirm)
	_confirm.ask(title, msg, yes, no_text)
	_confirm.answered.connect(func(ok):
		_confirm = null
		if ok:
			on_yes.call()
		elif on_no.is_valid():
			on_no.call())


func on_back() -> bool:
	if _confirm and is_instance_valid(_confirm):
		_confirm.queue_free()  # back on a question = keep editing
		_confirm = null
		return true
	if not _dirty:
		close()
		return true
	_ask("Save your changes?", "You changed things since the last save. (Right-click to keep editing.)", "Save", func():
		if save():
			close(), func(): close(), "Don't save")
	return true
