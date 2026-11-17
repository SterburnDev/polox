extends "res://scripts/ui/screen_panel.gd"
## Build mode's World Map: place cards can be repositioned, double-clicked to visit, or linked by
## dragging the mint handle from one card to another (two-way doors). Auto arrange lays places that
## join at their edges side by side (places.gd). Menu > World Map (world_map_view.gd) is for travel.

const RoomGraph := preload("res://scripts/world/room_graph.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const Places := preload("res://scripts/world/places.gd")


class MapCanvas extends Control:
	signal open_room(id: String)
	signal connect_rooms(a: String, b: String)
	signal moved(id: String, normalized: Vector2)
	const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
	const RoomGraph := preload("res://scripts/world/room_graph.gd")
	var ids := PackedStringArray()
	var rooms: Dictionary = {}
	var positions: Dictionary = {}
	var drag_id := ""
	var link_from := ""
	var drag_offset := Vector2.ZERO
	var pointer := Vector2.ZERO

	func configure(room_ids: PackedStringArray, room_data: Dictionary, saved: Dictionary) -> void:
		ids = room_ids
		rooms = room_data
		positions = saved.duplicate(true)
		var layout := RoomGraph.auto_layout(ids)
		for i in ids.size():
			var id := str(ids[i])
			if not positions.get(id) is Dictionary and not positions.get(id) is Vector2:
				var cell: Dictionary = layout[id]
				positions[id] = Vector2(0.04 + float(cell.x) * 0.31, 0.08 + float(cell.y) * 0.44)
		custom_minimum_size = Vector2(720, 390)
		queue_redraw()

	func _rect(id: String) -> Rect2:
		var raw: Variant = positions.get(id, Vector2(0.04, 0.05))
		var norm := raw as Vector2 if raw is Vector2 else Vector2(float(raw.get("x", 0.04)), float(raw.get("y", 0.05)))
		var card := Vector2(190, 82)
		var max_pos := Vector2(maxf(0.0, size.x - card.x), maxf(0.0, size.y - card.y))
		return Rect2(Vector2(clampf(norm.x, 0.0, 1.0) * max_pos.x, clampf(norm.y, 0.0, 1.0) * max_pos.y), card)

	func _draw() -> void:
		for id in ids:
			var room: Dictionary = rooms.get(id, {})
			for target in RoomGraph.links(room):
				if ids.has(target) and ids.find(id) < ids.find(target):
					draw_line(_rect(id).get_center(), _rect(target).get_center(), ThemeBuilder.MUTED, 3.0, true)
		if link_from != "":
			draw_line(_rect(link_from).get_center(), pointer, ThemeBuilder.YELLOW, 3.0, true)
		for id in ids:
			var r := _rect(id)
			var fill := Color(ThemeBuilder.PANEL_LIGHT) if id == drag_id else Color(ThemeBuilder.PANEL)
			draw_style_box(ThemeBuilder.box(fill, ThemeBuilder.CREAM, 2, 8, 6), r)
			var room: Dictionary = rooms.get(id, {})
			draw_string(ThemeDB.fallback_font, r.position + Vector2(12, 28), str(room.get("name", id)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 42, 17, ThemeBuilder.YELLOW)
			draw_string(ThemeDB.fallback_font, r.position + Vector2(12, 54), "%d doors  ·  %s" % [RoomGraph.links(room).size(), id], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 34, 13, ThemeBuilder.MUTED)
			draw_circle(r.position + Vector2(r.size.x - 17, r.size.y * 0.5), 9.0, ThemeBuilder.MINT)
			draw_string(ThemeDB.fallback_font, r.position + Vector2(r.size.x - 22, r.size.y * 0.5 + 5), "+", HORIZONTAL_ALIGNMENT_CENTER, 10, 14, ThemeBuilder.BG)

	func _node_at(pos: Vector2) -> String:
		for i in range(ids.size() - 1, -1, -1):
			if _rect(ids[i]).has_point(pos):
				return str(ids[i])
		return ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var hit := _node_at(event.position)
			if event.pressed:
				if hit == "": return
				var r := _rect(hit)
				if event.double_click:
					open_room.emit(hit)
					return
				if event.position.x >= r.end.x - 34:
					link_from = hit
				else:
					drag_id = hit
					drag_offset = event.position - r.position
				pointer = event.position
				queue_redraw()
			else:
				if link_from != "" and hit != "" and hit != link_from:
					connect_rooms.emit(link_from, hit)
				elif drag_id != "":
					var p: Vector2 = Vector2(clampf(event.position.x - drag_offset.x, 0.0, maxf(0.0, size.x - 190.0)), clampf(event.position.y - drag_offset.y, 0.0, maxf(0.0, size.y - 82.0)))
					var normalized := Vector2(p.x / maxf(1.0, size.x - 190.0), p.y / maxf(1.0, size.y - 82.0))
					positions[drag_id] = normalized
					moved.emit(drag_id, normalized)
				link_from = ""
				drag_id = ""
				queue_redraw()
		elif event is InputEventMouseMotion:
			pointer = event.position
			if link_from != "":
				queue_redraw()
			elif drag_id != "" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				var p: Vector2 = event.position - drag_offset
				positions[drag_id] = Vector2(p.x / maxf(1.0, size.x - 190.0), p.y / maxf(1.0, size.y - 82.0))
				queue_redraw()


var build: Node
var _canvas: MapCanvas


func _ready() -> void:
	setup("World map", Vector2(940, 700))
	body.add_child(UiKit.para("Drag place cards to arrange them. Drag the mint handle onto another place to connect both ways with doors. Double-click a place to open it. (Join places edge to edge with Add a place in the Place tab.)", 16, ThemeBuilder.MUTED))
	_canvas = MapCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.open_room.connect(_open_room)
	_canvas.connect_rooms.connect(_connect)
	_canvas.moved.connect(_save_position)
	body.add_child(UiKit.scroll(_canvas))
	var row := UiKit.hbox(8)
	var arrange := UiKit.button("Auto arrange", _auto_layout, 150)
	arrange.tooltip_text = "Lay place cards out: joined places side by side, the rest in a grid; saved with this world"
	row.add_child(arrange)
	var manage := UiKit.button("Create / manage places...", _manage_rooms, 240)
	manage.tooltip_text = "Create, duplicate, rename or delete places"
	row.add_child(manage)
	body.add_child(row)
	_refresh()


func _refresh() -> void:
	var ids := SaveManager.list_rooms()
	var data := {}
	for id in ids:
		data[id] = build.world.room.data.duplicate(true) if id == GameState.current_room_id else SaveManager.load_room(id)
	_canvas.configure(ids, data, GameState.world.get("map_positions", {}))


func _save_position(id: String, pos: Vector2) -> void:
	var map: Dictionary = GameState.world.get("map_positions", {})
	map[id] = {"x": pos.x, "y": pos.y}
	GameState.world["map_positions"] = map
	SaveManager.save_world(GameState.world)


func _auto_layout() -> void:
	var rooms := {}
	for id in SaveManager.list_rooms():
		rooms[id] = build.world.room.data if id == GameState.current_room_id else SaveManager.load_room(id)
	var grid := Places.map_layout(rooms, str(GameState.world.get("start_room", "home")))
	var hi := Vector2i.ONE
	for id in grid:
		hi.x = maxi(hi.x, (grid[id] as Vector2i).x)
		hi.y = maxi(hi.y, (grid[id] as Vector2i).y)
	var normalized := {}
	for id in grid:
		var p: Vector2i = grid[id]
		normalized[id] = {"x": float(p.x) / maxf(1.0, hi.x), "y": float(p.y) / maxf(1.0, hi.y)}
	GameState.world["map_positions"] = normalized
	SaveManager.save_world(GameState.world)
	_refresh()


func _open_room(id: String) -> void:
	close()
	build.exit()
	build.world.go_to_room(id)


func _connect(from_id: String, to_id: String) -> void:
	if not SaveManager.room_exists(from_id) or not SaveManager.room_exists(to_id):
		return
	var a: Dictionary = build.world.room.data if from_id == GameState.current_room_id else SaveManager.load_room(from_id)
	var b: Dictionary = build.world.room.data if to_id == GameState.current_room_id else SaveManager.load_room(to_id)
	if not RoomGraph.connect_rooms(a, b):
		GameState.notify("Couldn't connect those places: there may be no free cell for a door.")
		return
	SaveManager.save_room(a)
	SaveManager.save_room(b)
	if from_id == GameState.current_room_id or to_id == GameState.current_room_id:
		build.world.rebuild_room()
	_refresh()
	GameState.notify("Two-way doors added.")


func _manage_rooms() -> void:
	build.world.main.open_panel(preload("res://scripts/world/world_menu.gd").room_list(build.world))
