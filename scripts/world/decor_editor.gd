extends Control
## Edit my room (the Light World's building, Phase 33): one tap opens it, one tap closes it. It's limited
## on purpose, because it's a real place: walls and rooms come from your home's layout; you place, move,
## turn and recolour furniture and decor from a real-life catalogue (beds, desks, plants, posters, rugs,
## lamps...), hang pictures, and paint the walls. Outside, only small things (a bench, flowers, a mailbox).
## No terrain, blocks, pillars, platforming or battles.
##
## In your house every change is kept as an edit (home_edit.gd: your edits win, Undo puts any back); on your
## street the pieces you add are kept with the place (and survive Map my streets again).

const Furniture := preload("res://scripts/world/furniture.gd")
const HomeEdit := preload("res://scripts/home/home_edit.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const SurveyData := preload("res://scripts/home/survey_data.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")

## What you can place inside, and outside.
const INSIDE: PackedStringArray = ["bed", "double_bed", "nightstand", "wardrobe", "dresser", "desk", "computer", "chair", "bookshelf",
	"sofa", "armchair", "coffee_table", "tv", "dining_table", "lamp", "plant", "rug", "runner", "picture", "mirror", "piano", "washer", "floor_cushion", "record_player", "shoe_rack",
	"bean_bag", "fish_tank", "coat_rack", "bar_stool", "wall_clock", "light_switch", "lantern"]
const OUTSIDE: PackedStringArray = ["bench", "flowers", "mailbox", "plant", "bush", "birdbath", "lantern"]

var world: Node
var active := false
var selected_model := ""         # what a tap on the floor places
var picked: Dictionary = {}      # the piece you tapped (to move, turn, recolour, take away)
var moving := false
var batches: Array = []          # (house) the edit batches made while open, for Undo
var _bar: PanelContainer
var _catalog: HFlowContainer
var _tools: HFlowContainer
var _status: Label
var _category := "all"


func setup(game_world: Node) -> void:
	world = game_world
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func is_house() -> bool:
	return str(world.room.data.get("id", "")).begins_with("lw_floor_")


func outside() -> bool:
	return str(world.room.data.get("kind", "")) == "outdoor"


## One tap opens it.
func open() -> void:
	if active:
		return
	active = true
	visible = true
	selected_model = ""
	picked = {}
	moving = false
	batches = []
	world.hud.set_building(true)
	_build()


## One tap closes it.
func close() -> void:
	active = false
	visible = false
	if world and is_instance_valid(world.hud):
		world.hud.set_building(false)
	for c in get_children():
		c.queue_free()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_bar = PanelContainer.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_top = -230
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.minimum_size_changed.connect(func(): _fit_bar.call_deferred())
	add_child(_bar)
	var v := UiKit.vbox(6)
	_bar.add_child(v)
	var top := UiKit.hbox(8)
	var heading := UiKit.label("Edit my room" if not outside() else "Edit outside", 22, ThemeBuilder.YELLOW)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.clip_text = true
	top.add_child(heading)
	var undo := UiKit.button("Undo", func(): undo_last(), 0)
	undo.name = "DecorUndo"
	top.add_child(undo)
	var done := UiKit.button("Done", func(): close(), 0)
	done.name = "DecorDone"
	top.add_child(done)
	v.add_child(top)
	_status = UiKit.label("Pick something, tap the floor.", 16, ThemeBuilder.MUTED)
	_status.clip_text = true
	v.add_child(_status)
	_tools = UiKit.flow_row(6)
	v.add_child(_tools)
	if not outside():
		var cats := UiKit.option(["All furniture", "Bedroom", "Study", "Living", "Kitchen", "Decor", "Laundry"])
		cats.name = "DecorCategory"
		cats.item_selected.connect(func(i):
			_category = ["all", "bedroom", "study", "living", "kitchen", "decor", "laundry"][i]
			_filter_catalog())
		v.add_child(cats)
		_category = "all"
	_catalog = UiKit.flow_row(6)
	for m in (OUTSIDE if outside() else INSIDE):
		var b := UiKit.button(Furniture.name_of(m), func(): choose(m), 0)
		b.name = "Pick_" + m
		b.toggle_mode = true
		_catalog.add_child(b)
	var sc := UiKit.scroll(_catalog)
	sc.custom_minimum_size = Vector2(0, 110)
	v.add_child(sc)
	if is_house() and not outside():
		var paint := UiKit.flow_row(4)
		paint.visible = not UiKit.upright_phone()
		if UiKit.upright_phone():
			var paint_toggle := UiKit.button("Paint", func(): paint.visible = not paint.visible; _fit_bar(), 0)
			top.add_child(paint_toggle)
			top.move_child(paint_toggle, 1)
		else:
			paint.add_child(UiKit.label("Paint this room:", 16))
		for sw in SurveyData.WALL_SWATCHES:
			var pb := Button.new()
			var target := UiKit.touch_target() if UiKit.upright_phone() else 34.0
			pb.custom_minimum_size = Vector2(target, target)
			pb.tooltip_text = str(sw[1]).capitalize()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(str(sw[0]))
			sb.set_corner_radius_all(5)
			pb.add_theme_stylebox_override("normal", sb)
			pb.add_theme_stylebox_override("hover", sb)
			pb.name = "Paint_" + str(sw[1])
			pb.pressed.connect(func(): paint_here(str(sw[0])))
			paint.add_child(pb)
		v.add_child(paint)
	_fit_bar.call_deferred()


func _filter_catalog() -> void:
	for b in _catalog.get_children():
		var model := str(b.name).trim_prefix("Pick_")
		b.visible = _category == "all" or str(Furniture.CATALOG[model][5]) == _category


func _fit_bar() -> void:
	if not is_instance_valid(_bar):
		return
	_bar.offset_top = -maxf(230.0, _bar.get_combined_minimum_size().y)


func choose(model: String) -> void:
	selected_model = model
	picked = {}
	moving = false
	for b in _catalog.get_children():
		(b as Button).set_pressed_no_signal(str(b.name) == "Pick_" + model)
	_status.text = "Where does the %s go?" % Furniture.name_of(model).to_lower()
	_tools_for({})


## A tap on the floor (game_world routes it here while this is open).
func tap_cell(cell: Vector2i) -> void:
	if not active:
		return
	var there: Dictionary = RoomEditor.object_at(world.room.data, cell.x, cell.y)
	if moving and not picked.is_empty():
		move_to(cell)
		return
	if not there.is_empty() and Furniture.is_furniture(there):
		pick(there)
		return
	if selected_model != "":
		place(selected_model, cell)


func pick(o: Dictionary) -> void:
	picked = o
	selected_model = ""
	moving = false
	_status.text = Furniture.name_of(str(o.get("model", ""))) + ": change it?"
	_tools_for(o)


func _tools_for(o: Dictionary) -> void:
	for c in _tools.get_children():
		c.queue_free()
	if o.is_empty():
		_fit_bar.call_deferred()
		return
	_tools.add_child(UiKit.button("Move", func():
		moving = true
		_status.text = "Tap where it goes.", 0))
	_tools.add_child(UiKit.button("Turn", func(): turn(), 0))
	_tools.add_child(UiKit.button("Take away", func(): remove_picked(), 0))
	for col in ["#c96a5a", "#7f9cc9", "#7a8f6a", "#e8c25a", "#a07ac9", "#f2efe8", "#3a3a40"]:
		var b := Button.new()
		var target := UiKit.touch_target() if UiKit.upright_phone() else 30.0
		b.custom_minimum_size = Vector2(target, target)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col)
		sb.set_corner_radius_all(15)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.pressed.connect(func(): recolor(col))
		_tools.add_child(b)
	_fit_bar.call_deferred()


# --- Changes ----------------------------------------------------------------------------------------

func _level() -> int:
	return int(world.room.data.get("house", {}).get("level", 0))


func _margin() -> Vector2i:
	var h: Dictionary = world.room.data.get("house", {})
	return Vector2i(int(h.get("x", 0)), int(h.get("z", 0)))


## In your house: an edit (kept, undoable, winning over research). On the street: straight into the place.
func _commit(edit: Dictionary) -> bool:
	if is_house():
		edit["level"] = _level()
		var res := HomeEdit.commit([edit], "room")
		if res.is_empty():
			_status.text = "That doesn't fit there."
			return false
		preload("res://scripts/ui/haptics.gd").place()
		batches.append(str(res.batch))
		_reload()
		return true
	return false


func _reload() -> void:
	var cell: Vector2i = world.player.cell()
	world.load_room(GameState.current_room_id, "", cell)
	if world.has_method("flourish"):
		world.flourish(false)   # (placing already gave its own small buzz)


func place(model: String, cell: Vector2i) -> bool:
	if outside() and not model in OUTSIDE:
		return false
	if not outside() and not model in INSIDE:
		return false
	if is_house():
		var m := _margin()
		return _commit({"type": "place", "model": model, "x": cell.x - m.x, "z": cell.y - m.y, "rot": 0, "color": ""})
	var data: Dictionary = world.room.data
	var o := Furniture.make(model, cell.x, cell.y)
	for c in Furniture.cells(o):
		if not RoomEditor.object_at(data, c.x, c.y).is_empty() or not world.room.nav.walkable(c):
			_status.text = "That doesn't fit there."
			return false
	o["id"] = RoomEditor.next_object_id(data, model)
	o["user"] = true
	(data.objects as Array).append(o)
	SaveManager.save_room(data)
	world.rebuild_room()
	return true


func move_to(cell: Vector2i) -> void:
	if picked.is_empty():
		return
	var p: Array = picked.get("pos", [0, 0, 0])
	if is_house():
		var m := _margin()
		_commit({"type": "move", "model": str(picked.model), "from_x": int(p[0]) - m.x, "from_z": int(p[2]) - m.y, "x": cell.x - m.x, "z": cell.y - m.y, "rot": int(picked.get("rot", 0))})
	else:
		picked["pos"] = [cell.x, 0, cell.y]
		SaveManager.save_room(world.room.data)
		world.rebuild_room()
	moving = false
	picked = {}
	_tools_for({})


func turn() -> void:
	if picked.is_empty():
		return
	var p: Array = picked.get("pos", [0, 0, 0])
	if is_house():
		var m := _margin()
		_commit({"type": "move", "model": str(picked.model), "from_x": int(p[0]) - m.x, "from_z": int(p[2]) - m.y, "x": int(p[0]) - m.x, "z": int(p[2]) - m.y, "rot": (int(picked.get("rot", 0)) + 1) % 4})
	else:
		picked["rot"] = (int(picked.get("rot", 0)) + 1) % 4
		SaveManager.save_room(world.room.data)
		world.rebuild_room()
	picked = {}
	_tools_for({})


func recolor(col: String) -> void:
	if picked.is_empty():
		return
	var p: Array = picked.get("pos", [0, 0, 0])
	if is_house():
		var m := _margin()
		_commit({"type": "move", "model": str(picked.model), "from_x": int(p[0]) - m.x, "from_z": int(p[2]) - m.y, "x": int(p[0]) - m.x, "z": int(p[2]) - m.y, "rot": int(picked.get("rot", 0)), "color": col})
	else:
		picked["color"] = col
		SaveManager.save_room(world.room.data)
		world.rebuild_room()
	picked = {}
	_tools_for({})


func remove_picked() -> void:
	if picked.is_empty():
		return
	var p: Array = picked.get("pos", [0, 0, 0])
	if is_house():
		var m := _margin()
		_commit({"type": "remove_at", "model": str(picked.model), "x": int(p[0]) - m.x, "z": int(p[2]) - m.y})
	else:
		RoomEditor.remove_object(world.room.data, str(picked.get("id", "")))
		SaveManager.save_room(world.room.data)
		world.rebuild_room()
	picked = {}
	_tools_for({})


## Paints the room you're standing in.
func paint_here(col: String) -> void:
	if not is_house():
		return
	var cell: Vector2i = world.player.cell()
	var m := _margin()
	var local := cell - m
	for r in world.room.data.get("rooms", []):
		var rr: Array = r.rect
		if Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3])).has_point(cell):
			_commit({"type": "wall", "room": str(r.id), "room_name": str(r.name), "color": col})
			return
	_status.text = "Stand in a room to paint it (%s)." % str(local)


func undo_last() -> void:
	if batches.is_empty():
		_status.text = "Nothing to undo."
		return
	if HomeEdit.undo(str(batches.pop_back())):
		_reload()
		_status.text = "Put back."
