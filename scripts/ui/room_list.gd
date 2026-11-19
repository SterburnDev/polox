extends "res://scripts/ui/screen_panel.gd"
## Places (once called rooms): create from a template (indoors, outdoors, somewhere strange),
## rename, duplicate, delete, pick the start place, and go.

const RoomEditor := preload("res://scripts/world/room_editor.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")
const Places := preload("res://scripts/world/places.gd")

const SIZES := [["Small (8 x 6)", 8, 6], ["Medium (12 x 10)", 12, 10], ["Large (20 x 20)", 20, 20]]

var world: Node
var _rows: VBoxContainer
var _new_name: LineEdit
var _size: OptionButton
var _template: OptionButton


func _ready() -> void:
	setup("Places", Vector2(1080, 660))
	_rows = UiKit.vbox(8)
	body.add_child(UiKit.scroll(_rows))
	body.add_child(UiKit.label("New place", 22, ThemeBuilder.YELLOW))
	var add := UiKit.flow_row(8)
	_new_name = UiKit.line_edit("Name, e.g. Cafe, Beach, Moon Garden")
	_new_name.custom_minimum_size.x = 300
	_new_name.text_submitted.connect(func(_t): _create())
	add.add_child(_new_name)
	_template = UiKit.option(Array(Places.TEMPLATE_ORDER).map(func(t): return "%s (%s)" % [Places.TEMPLATES[t].name, str(Places.KIND_LABELS[Places.TEMPLATES[t].kind]).to_lower()]), 0)
	_template.tooltip_text = "Its kind and look: walls or open sky, ground, background (change it later in Build mode)"
	add.add_child(_template)
	_size = UiKit.option(SIZES.map(func(s): return s[0]), 1)
	add.add_child(_size)
	add.add_child(UiKit.button("Create", _create, 130))
	body.add_child(add)
	_fill()


func _fill() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var start := str(GameState.world.get("start_room", "home"))
	for id in SaveManager.list_rooms():
		var r := SaveManager.load_room(id)
		var row := UiKit.hbox(6)
		var tags := ""
		if id == start:
			tags += "  ★ start"
		if id == GameState.current_room_id:
			tags += "  (you're here)"
		var l := UiKit.label(str(r.get("name", id)) + tags, 22)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		row.add_child(UiKit.button("Go", func(): _go(id), 70))
		row.add_child(UiKit.button("Rename", func(): _rename(row, id, str(r.get("name", id))), 110))
		row.add_child(UiKit.button("Copy", func():
			RoomEditor.duplicate_room(id)
			_fill(), 90))
		var star := UiKit.button("★", func(): _make_start(id), 56)
		star.tooltip_text = "Make this the place you start in"
		row.add_child(star)
		row.add_child(UiKit.button("Delete", func(): _delete(id, str(r.get("name", id))), 100))
		_rows.add_child(row)


func _go(id: String) -> void:
	close()
	world.go_to_room(id)


func _rename(row: HBoxContainer, id: String, current: String) -> void:
	for c in row.get_children():
		c.queue_free()
	var e := UiKit.line_edit("New name", current)
	row.add_child(e)
	var ok := func():
		if e.text.strip_edges() != "":
			RoomEditor.rename_room(id, e.text)
			if id == GameState.current_room_id:
				world.room.data["name"] = e.text.strip_edges()
				world.hud.set_room(e.text.strip_edges())
		_fill()
	e.text_submitted.connect(func(_t): ok.call())
	row.add_child(UiKit.button("Save", ok, 100))
	e.call_deferred("grab_focus")


func _make_start(id: String) -> void:
	GameState.world["start_room"] = id
	GameState.save_world()
	_fill()


func _delete(id: String, display: String) -> void:
	if SaveManager.list_rooms().size() <= 1:
		GameState.notify("This is your only place, so it stays.")
		return
	var c := ConfirmPanel.new()
	add_child(c)
	c.ask("Delete %s?" % display, "Doors and joins that led here will lead nowhere, and anyone living here moves to the start place. (Tip: Back up first from Settings.)", "Delete", "Keep it")
	c.answered.connect(func(yes):
		if not yes:
			return
		var here := id == GameState.current_room_id
		if here:
			world.flush_room()
		RoomEditor.delete_room(id)
		if here:
			close()
			world.go_to_room(str(GameState.world.get("start_room", "home")))
		else:
			_fill())


func _create() -> void:
	var n := _new_name.text.strip_edges()
	if n == "":
		GameState.notify("Give the place a name first.")
		return
	var s: Array = SIZES[_size.selected]
	var id: String = RoomEditor.create_room(n, int(s[1]), int(s[2]))
	var made := SaveManager.load_room(id) if id != "" else {}
	if not made.is_empty():
		var t := Places.from_template(Places.TEMPLATE_ORDER[_template.selected], id, n, int(s[1]), int(s[2]))
		for k in ["kind", "walls", "background", "edges", "floor", "wall", "sky", "template"]:
			if t.has(k):
				made[k] = t[k]
		SaveManager.save_room(made)
	_new_name.text = ""
	_fill()
	GameState.notify("Made %s. Press Go to visit, link a door, or join it to a place in Build mode." % n)
