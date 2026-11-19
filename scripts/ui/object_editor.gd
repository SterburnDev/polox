extends "res://scripts/ui/screen_panel.gd"
## Edits one placed object: what a sign says, where a door leads (including
## "a brand-new room", which also gets a door back), which item a pickup
## holds and whether it comes back daily; Platform Mode pieces (pillar label,
## once or every time, where it leads; pad strength; heights; mover path and
## speed; a shard's memory; colours); rotate or delete.

signal applied(before: Dictionary)

const RoomEditor := preload("res://scripts/world/room_editor.gd")
const Items := preload("res://scripts/items/items.gd")
const Pickups := preload("res://scripts/items/pickups.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const PlatformObjects := preload("res://scripts/platform/platform_objects.gd")
const Config := preload("res://scripts/platform/platform_config.gd")
const CustomModels := preload("res://scripts/world/custom_models.gd")

var room: Dictionary          # the live room data (edited in place)
var obj_id := ""
var _before: Dictionary
var _text: TextEdit
var _target: OptionButton
var _target_ids: Array = []
var _new_name: LineEdit
var _item_opt: OptionButton
var _item_ids: Array = []
var _count: SpinBox
var _respawn: OptionButton
var _fields: Dictionary = {}   # Platform Mode piece fields: key -> Control
var _pillar_rooms: Array = []
var _model_opt: OptionButton
var _model_names: PackedStringArray = []


func edit(room_data: Dictionary, id: String) -> void:
	room = room_data
	obj_id = id
	_before = room.duplicate(true)


func _obj() -> Dictionary:
	for o in room.get("objects", []):
		if str(o.get("id", "")) == obj_id:
			return o
	return {}


func _ready() -> void:
	var o := _obj()
	var type := str(o.get("type", "prop"))
	var titles := {"sign": "Sign", "door": "Door", "prop": "Plant / picture", "pickup": "Pickup", "platform_pillar": "Platform Pillar",
		"jump_pad": "Jump pad", "one_way": "One-way ledge", "mover": "Moving platform", "checkpoint": "Checkpoint", "shard": "Memory Shard", "hazard": "Soft hazard"}
	setup(titles.get(type, "Object"), Vector2(820, 600))
	var prompts := {
		"sign": "What does the sign say? Something about your life, a reminder, a wish...",
		"door": "Label (optional), e.g. To the cafe",
		"prop": "What do you notice when you look at it? (optional)",
		"shard": "The memory this shard holds (optional): a moment, a quote, a wish...",
	}
	_text = UiKit.text_edit(prompts.get(type, ""), str(o.get("memory" if type == "shard" else "interaction_text", "")), 150 if type == "sign" else 90)
	_text.visible = type != "pickup" and (not type in BlockFactory.PLATFORM_OBJECTS or type == "shard")
	if type in BlockFactory.PLATFORM_OBJECTS:
		_platform_fields(o, type)
	body.add_child(_text)
	if type == "pickup":
		_pickup_fields(o)
	if type == "prop":
		_custom_model_fields(o)
	if type == "door":
		body.add_child(UiKit.label("Leads to", 22, ThemeBuilder.YELLOW))
		_target = UiKit.option(["(nowhere yet)"])
		_target_ids.append("")
		for id in SaveManager.list_rooms():
			if id != str(room.get("id", "")):
				_target_ids.append(id)
				_target.add_item(str(SaveManager.load_room(id).get("name", id)))
		_target.add_item("+ A brand-new room")
		_target_ids.append("__new__")
		_target.select(maxi(0, _target_ids.find(str(o.get("door_target", "")))))
		body.add_child(_target)
		_new_name = UiKit.line_edit("Name the new room, e.g. Cafe")
		_new_name.visible = false
		body.add_child(_new_name)
		_target.item_selected.connect(func(i): _new_name.visible = _target_ids[i] == "__new__")
	body.add_child(UiKit.spacer(true))
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button("⟳ Rotate", _rotate, 140))
	row.add_child(UiKit.button("Delete", _delete, 120))
	row.add_child(UiKit.spacer())
	row.add_child(UiKit.button("Done", func(): _done(), 140))
	body.add_child(row)
	_text.call_deferred("grab_focus")


## Which item, how many, once or every day, and "put it back".
func _pickup_fields(o: Dictionary) -> void:
	body.add_child(UiKit.para("Walk onto a pickup to put it in your bag.", 18, ThemeBuilder.MUTED))
	_item_opt = UiKit.option([])
	for it in Items.all():
		_item_ids.append(str(it.id))
		_item_opt.add_icon_item(Items.icon_texture(it), str(it.name))
	if _item_ids.is_empty():
		_item_opt.add_item("(no items yet: make one in the Item Workshop)")
		_item_opt.disabled = true
	_item_opt.select(maxi(0, _item_ids.find(str(o.get("item", "")))))
	body.add_child(UiKit.field_row("Item", _item_opt, 120))
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 9
	_count.value = clampi(int(o.get("count", 1)), 1, 9)
	_count.custom_minimum_size = Vector2(120, 52)
	body.add_child(UiKit.field_row("How many", _count, 120))
	_respawn = UiKit.option(Pickups.RESPAWNS.map(func(r): return r[1]))
	_respawn.select(1 if str(o.get("respawn", "once")) == "daily" else 0)
	body.add_child(UiKit.field_row("Comes back", _respawn, 120))
	if str(o.get("taken", "")) != "":
		var back := UiKit.button("Put it back (it was picked up)", func():
			Pickups.reset(_obj())
			applied.emit(_before)
			_before = room.duplicate(true)
			GameState.notify("The pickup is back."), 360)
		body.add_child(back)


## Platform Mode pieces: what each one needs, all optional with sensible defaults.
func _platform_fields(o: Dictionary, type: String) -> void:
	var scroll := UiKit.vbox(8)
	body.add_child(scroll)
	match type:
		"platform_pillar":
			scroll.add_child(UiKit.para("Activate it (click, tap, or E next to it) to start Platform Mode: run and jump. An Exit Pillar appears where you start, and Leave is always on screen.", 18, ThemeBuilder.MUTED))
			var label := UiKit.line_edit("Label (optional), e.g. Sky Steps")
			label.text = str(o.get("label", ""))
			_fields["label"] = label
			scroll.add_child(UiKit.field_row("Label", label, 150))
			var rep := UiKit.option(["Every time", "Only once"], 1 if str(o.get("repeat", "repeat")) == "once" else 0)
			rep.tooltip_text = "Only once: after it has woken, it stays quiet"
			_fields["repeat"] = rep
			scroll.add_child(UiKit.field_row("Works", rep, 150))
			var dest := UiKit.option(["Right here (this room)"])
			_pillar_rooms = [""]
			for id in SaveManager.list_rooms():
				if id != str(room.get("id", "")):
					_pillar_rooms.append(id)
					dest.add_item(str(SaveManager.load_room(id).get("name", id)))
			dest.select(maxi(0, _pillar_rooms.find(str(o.get("target_room", "")))))
			dest.tooltip_text = "Leads to a course in another room (you land on its start spot, or the cell below)"
			_fields["target_room"] = dest
			scroll.add_child(UiKit.field_row("Leads to", dest, 150))
			var spot: Array = o.get("target_spawn", []) if o.get("target_spawn") is Array else []
			var own := CheckBox.new()
			own.text = "Land on a chosen cell instead of the start spot"
			own.button_pressed = spot.size() == 2
			_fields["spawn_on"] = own
			scroll.add_child(own)
			var xz := UiKit.hbox(8)
			_fields["spawn_x"] = _spin(0, 99, int(spot[0]) if spot.size() == 2 else 1)
			_fields["spawn_z"] = _spin(0, 99, int(spot[1]) if spot.size() == 2 else 1)
			xz.add_child(UiKit.field_row("X", _fields.spawn_x, 30))
			xz.add_child(UiKit.field_row("Z", _fields.spawn_z, 30))
			scroll.add_child(xz)
		"jump_pad":
			var strength := UiKit.slider(8.0, 24.0, 1.0, float(o.get("strength", Config.JUMP_PAD_STRENGTH)))
			var hint := UiKit.label("", 16, ThemeBuilder.MUTED)
			var show := func(v: float): hint.text = "about %.1f blocks high" % (v * v / (2.0 * Config.GRAVITY))
			strength.value_changed.connect(show)
			show.call(strength.value)
			_fields["strength"] = strength
			scroll.add_child(UiKit.field_row("Strength", strength, 150))
			scroll.add_child(hint)
		"mover":
			_fields["elev"] = _spin(0, 5, int(o.get("elev", 1)))
			scroll.add_child(UiKit.field_row("Height", _fields.elev, 150))
			scroll.add_child(UiKit.para("Glides from here to here + this many blocks, and back:", 16, ThemeBuilder.MUTED))
			var d := UiKit.hbox(8)
			for k in ["dx", "dy", "dz"]:
				_fields[k] = _spin(-8, 8, int(o.get(k, 3 if k == "dx" else 0)))
				d.add_child(UiKit.field_row(str(k).substr(1).to_upper(), _fields[k], 30))
			scroll.add_child(d)
			var spd := UiKit.slider(0.5, 4.0, 0.25, float(o.get("speed", Config.MOVER_SPEED)))
			_fields["speed"] = spd
			scroll.add_child(UiKit.field_row("Speed", spd, 150))
		"one_way", "shard":
			_fields["elev"] = _spin(0, 5, int(o.get("elev", 1 if type == "one_way" else 0)))
			scroll.add_child(UiKit.field_row("Height", _fields.elev, 150))
		"checkpoint":
			scroll.add_child(UiKit.para("Touch it in Platform Mode: after a fall you come back here (it lights up and is remembered).", 18, ThemeBuilder.MUTED))
		"hazard":
			scroll.add_child(UiKit.para("Touching it in Platform Mode gently puts you back at the last checkpoint. No lives, no timers.", 18, ThemeBuilder.MUTED))
	var col := ColorPickerButton.new()
	col.text = "Colour"
	col.custom_minimum_size = Vector2(140, 48)
	col.color = PlatformObjects.color_of({"type": "pillar" if type == "platform_pillar" else type, "color": str(o.get("color", ""))})
	col.edit_alpha = false
	_fields["color"] = col
	scroll.add_child(UiKit.field_row("Colour", col, 150))


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.custom_minimum_size = Vector2(110, 48)
	return s


func _save_platform_fields(o: Dictionary) -> void:
	if _fields.is_empty():
		return
	if _fields.has("label"):
		o["label"] = (_fields.label as LineEdit).text.strip_edges().substr(0, 40)
		o["repeat"] = "once" if (_fields.repeat as OptionButton).selected == 1 else "repeat"
		o["target_room"] = str(_pillar_rooms[(_fields.target_room as OptionButton).selected])
		o["target_spawn"] = [int(_fields.spawn_x.value), int(_fields.spawn_z.value)] if (_fields.spawn_on as CheckBox).button_pressed else []
	if _fields.has("strength"):
		o["strength"] = float(_fields.strength.value)
	if _fields.has("elev"):
		o["elev"] = int(_fields.elev.value)
	for k in ["dx", "dy", "dz"]:
		if _fields.has(k):
			o[k] = int(_fields[k].value)
	if _fields.has("speed"):
		o["speed"] = float(_fields.speed.value)
	if _fields.has("color"):
		o["color"] = "#" + (_fields.color as ColorPickerButton).color.to_html(false)


func _rotate() -> void:
	var o := _obj()
	o["rot"] = posmod(int(o.get("rot", 0)) + 1, 4)
	applied.emit(_before)
	_before = room.duplicate(true)


func _delete() -> void:
	RoomEditor.remove_object(room, obj_id)
	applied.emit(_before)
	close()


func _done() -> void:
	var o := _obj()
	if o.is_empty():
		close()
		return
	if str(o.get("type", "")) == "shard":
		o["memory"] = _text.text.strip_edges()
	else:
		o["interaction_text"] = _text.text.strip_edges()
	_save_platform_fields(o)
	if _item_opt and not _item_ids.is_empty():
		o["item"] = str(_item_ids[_item_opt.selected])
		o["count"] = int(_count.value)
		o["respawn"] = str(Pickups.RESPAWNS[_respawn.selected][0])
		var build: Node = get_tree().get_first_node_in_group("build_mode") if is_inside_tree() else null
		if build:
			build.pickup_item = str(o.item)
	if _model_opt and _model_opt.selected >= 0 and _model_opt.selected < _model_names.size():
		var chosen := str(_model_names[_model_opt.selected])
		if chosen == "":
			o.erase("custom_model")
		else:
			o["custom_model"] = chosen
	if _target:
		var target: String = _target_ids[_target.selected]
		if target == "__new__":
			var room_name := _new_name.text.strip_edges()
			target = RoomEditor.create_room(room_name if room_name != "" else "New Room")
		o["door_target"] = target
		if target != "":
			# link_door works on saved files: save, link (adds a door back), reload in place.
			SaveManager.save_room(room)
			RoomEditor.link_door(str(room.get("id", "")), obj_id, target)
			var fresh := SaveManager.load_room(str(room.get("id", "")))
			room.clear()
			room.merge(fresh)
	applied.emit(_before)
	close()


## Custom 3D model (.glb / .gltf / .obj) picker and importer for props.
func _custom_model_fields(o: Dictionary) -> void:
	body.add_child(UiKit.label("Custom 3D model (optional)", 18, ThemeBuilder.YELLOW))
	var row := UiKit.hbox(8)
	_model_opt = UiKit.option([])
	_model_opt.name = "CustomModelOption"
	_model_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_custom_model_list(str(o.get("custom_model", "")))
	row.add_child(_model_opt)
	if not OS.has_feature("web"):
		var import_btn := UiKit.button("Import .glb / .obj...", _import_custom_model, 0)
		import_btn.name = "ImportCustomModel"
		row.add_child(import_btn)
	body.add_child(row)


func _refresh_custom_model_list(selected_name: String) -> void:
	if _model_opt == null:
		return
	_model_opt.clear()
	_model_names = PackedStringArray([""])
	_model_opt.add_item("(2D sprite / default plant)")
	for model_name in CustomModels.list_models():
		_model_names.append(model_name)
		_model_opt.add_item(model_name)
	var idx := Array(_model_names).find(selected_name)
	_model_opt.select(maxi(0, idx))


func _import_custom_model() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Import a 3D model (.glb, .gltf, .obj)"
	fd.filters = PackedStringArray(["*.glb, *.gltf, *.obj ; 3D Models"])
	fd.file_selected.connect(func(path: String):
		var saved := CustomModels.import_model(path)
		if saved == "":
			GameState.notify("Couldn't import that 3D model (use .glb, .gltf, or .obj under 24 MB).")
		else:
			_refresh_custom_model_list(saved)
			GameState.notify("Imported 3D model: " + saved)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.65)


## Back / right-click also saves what was typed.
func on_back() -> bool:
	_done()
	return true
