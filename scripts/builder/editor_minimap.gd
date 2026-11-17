extends PanelContainer
## A small top-down map of the room: ground tiles, blocks, foreground,
## objects, the start spot, people and the cursor. Click to move the cursor
## (and the camera) there. A button opens the room list.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")

const SET_COLORS := {"cozy_home": Color("#b7865c"), "dream_meadow": Color("#4e9a5a"), "dark_castle": Color("#5a5670"), "night_sky": Color("#2a2250")}

var build: Node
var _map: Control


func bind(build_mode: Node) -> void:
	build = build_mode
	add_theme_stylebox_override("panel", ThemeBuilder.box(Color(ThemeBuilder.PANEL, 0.92), Color(ThemeBuilder.CREAM, 0.5), 2, 8, 4))
	var v := UiKit.vbox(4)
	add_child(v)
	_map = Control.new()
	_map.custom_minimum_size = Vector2(216, 130)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	v.add_child(_map)
	var rooms := UiKit.button("Rooms...", func(): build.world.main.open_panel(preload("res://scripts/world/world_menu.gd").room_list(build.world)), 0)
	rooms.custom_minimum_size.y = 36
	rooms.add_theme_font_size_override("font_size", 16)
	v.add_child(rooms)


func _cell_px() -> float:
	var w: int = build.world.room.w
	var d: int = build.world.room.d
	return minf(_map.size.x / w, _map.size.y / d)


func _origin() -> Vector2:
	var px := _cell_px()
	return (_map.size - Vector2(build.world.room.w * px, build.world.room.d * px)) / 2.0


func _draw_map() -> void:
	var data: Dictionary = build.world.room.data
	var px := _cell_px()
	var o := _origin()
	var w: int = build.world.room.w
	var d: int = build.world.room.d
	_map.draw_rect(Rect2(o, Vector2(w * px, d * px)), Color.from_string(str(data.get("floor", {}).get("color", "#5b4b8a")), Color("#5b4b8a")))
	for l in TileLayers.all(data):
		if not bool(l.get("visible", true)):
			continue
		var type := str(l.type)
		for k in l.cells:
			var p := Vector2(TileLayers.parse_key(str(k)))
			match type:
				"ground", "backdrop":
					_map.draw_rect(Rect2(o + p * px, Vector2(px, px)), SET_COLORS.get(str(l.cells[k].s), Color("#8a7bc8")))
				"blocks":
					_map.draw_rect(Rect2(o + p * px + Vector2(1, 1), Vector2(px - 2, px - 2)), Color("#ffd166"))
				_:
					_map.draw_rect(Rect2(o + p * px + Vector2(px * 0.3, px * 0.3), Vector2(px * 0.4, px * 0.4)), Color("#7ad6b0"))
	for t in data.get("tiles", []):
		_map.draw_rect(Rect2(o + Vector2(int(t.x), int(t.z)) * px + Vector2(1, 1), Vector2(px - 2, px - 2)), Color.from_string(str(t.get("color", "")), Color("#c9b6ff")).darkened(0.15))
	for ob in data.get("objects", []):
		var c := Color("#e86a8a") if str(ob.get("type", "")) == "door" else Color("#f3e9d2")
		_map.draw_rect(Rect2(o + Vector2(int(ob.pos[0]), int(ob.pos[2])) * px + Vector2(2, 2), Vector2(px - 4, px - 4)), c)
	var sp: Array = data.get("spawn", [0, 0])
	_map.draw_circle(o + (Vector2(int(sp[0]), int(sp[1])) + Vector2(0.5, 0.5)) * px, px * 0.3, Color("#8fd3ff"))
	for a in [build.world.player] + build.world.actors.values():
		if is_instance_valid(a):
			_map.draw_circle(o + (Vector2(a.cell()) + Vector2(0.5, 0.5)) * px, px * 0.35, Color("#ffffff"))
	_map.draw_rect(Rect2(o + Vector2(build.cursor) * px, Vector2(px, px)), ThemeBuilder.YELLOW, false, 2.0)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (event.position - _origin()) / _cell_px()
		var c := Vector2i(clampi(floori(p.x), 0, build.world.room.w - 1), clampi(floori(p.y), 0, build.world.room.d - 1))
		build.cursor = c
		build._cursor_node.position = build.world.room.cell_center(c)
		build.world.cam.target = build._cursor_node
		build._place_ghost()
		queue_redraw()
		_map.accept_event()
