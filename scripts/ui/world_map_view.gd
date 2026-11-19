extends "res://scripts/ui/screen_panel.gd"
## Menu > World Map: your places laid out like a land, in layers: the Light World (your real home),
## the Dream World (everything else), the Deep (reached through a Dream Gate, marked 🌀) and the
## Archive (Deep places whose fountain is sealed: nothing deleted, Reopen any time). Going to a place in
## the other world is the real journey through the fountain. Places joined at their edges sit side by side (east to
## the right, south below) with a bar across each join; doors are dotted lines; the place you're in
## glows. Tap a place, then Go there. (Build mode's World Map is for arranging and linking.)
## Tags: [LIGHT_WORLD_MAP]

const Places := preload("res://scripts/world/places.gd")
const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const Realms := preload("res://scripts/world/realms.gd")

const CARD := Vector2(150, 92)
const GAP := 34.0


class MapCanvas extends Control:
	signal picked(id: String)
	const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
	const Places := preload("res://scripts/world/places.gd")
	const Realms := preload("res://scripts/world/realms.gd")
	var rooms: Dictionary = {}
	var pos: Dictionary = {}
	var here := ""
	var selected := ""
	var card := Vector2(150, 92)
	var gap := 34.0

	func rect_of(id: String) -> Rect2:
		var p: Vector2i = pos.get(id, Vector2i.ZERO)
		return Rect2(Vector2(16, 16) + Vector2(p) * (card + Vector2(gap, gap)), card)

	func layout_size() -> Vector2:
		var hi := Vector2i.ZERO
		for id in pos:
			hi.x = maxi(hi.x, (pos[id] as Vector2i).x)
			hi.y = maxi(hi.y, (pos[id] as Vector2i).y)
		return Vector2(32, 32) + Vector2(hi + Vector2i.ONE) * (card + Vector2(gap, gap))

	func _draw() -> void:
		# Doors: dotted lines between the cards they join.
		for id in rooms:
			for o in rooms[id].get("objects", []):
				var t := str(o.get("door_target", "")) if str(o.get("type", "")) == "door" else ""
				if t != "" and rooms.has(t) and str(id) < t:
					_dotted(rect_of(id).get_center(), rect_of(t).get_center())
		# Joins: a bar across the gap.
		for id in rooms:
			var e := Places.edges(rooms[id])
			for side in e:
				var other := str(e[side])
				if not rooms.has(other):
					continue
				var a := rect_of(id)
				var b := rect_of(other)
				var mid := (a.get_center() + b.get_center()) / 2.0
				var horizontal: bool = side in ["east", "west"]
				var bar := Rect2(mid - (Vector2(gap + 4, 26) if horizontal else Vector2(26, gap + 4)) / 2.0, Vector2(gap + 4, 26) if horizontal else Vector2(26, gap + 4))
				draw_rect(bar, Color(ThemeBuilder.MINT, 0.85))
		for id in rooms:
			var r := rect_of(id)
			var room: Dictionary = rooms[id]
			var k := Places.kind(room)
			var fill := Color.from_string(str(room.get("floor", {}).get("color", "#5b4b8a")), Color("#5b4b8a")).darkened(0.35)
			var border := ThemeBuilder.YELLOW if id == here else (ThemeBuilder.CREAM if id == selected else Color(ThemeBuilder.CREAM, 0.4))
			draw_style_box(ThemeBuilder.box(fill, border, 4 if id == here or id == selected else 2, 10, 6), r)
			draw_string(ThemeDB.fallback_font, r.position + Vector2(10, 30), tr(str(room.get("name", id))), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 18, ThemeBuilder.CREAM)
			draw_string(ThemeDB.fallback_font, r.position + Vector2(10, 56), str(Places.KIND_LABELS.get(k, k)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 14, ThemeBuilder.MUTED)
			if id == here:
				draw_string(ThemeDB.fallback_font, r.position + Vector2(10, 80), "● You're here", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 14, ThemeBuilder.YELLOW)
			elif not Realms.gates(room).is_empty():
				var home := str(Realms.gate_of(room).get("leads", "")) == Realms.LIGHT
				draw_string(ThemeDB.fallback_font, r.position + Vector2(10, 80), tr("☀ the way home" if home else "🌙 to the Dream World"), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 14, Color("#ffe9a8") if home else Color("#c9a0ff"))
			elif not DarkWorlds.fountains(room).is_empty():
				draw_string(ThemeDB.fallback_font, r.position + Vector2(10, 80), tr("🌀 Dream Gate"), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 14, Color("#c9a0ff"))

	func _dotted(a: Vector2, b: Vector2) -> void:
		var n := int(a.distance_to(b) / 12.0)
		for i in n:
			if i % 2 == 0:
				draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), Color(ThemeBuilder.MUTED, 0.9), 3.0)

	func _gui_input(event: InputEvent) -> void:
		var pressed: bool = preload("res://scripts/ui/ui_kit.gd").tap_down(event)
		if not pressed:
			return
		for id in rooms:
			if rect_of(id).has_point(event.position):
				selected = id
				picked.emit(id)
				queue_redraw()
				accept_event()
				return


var world: Node
var canvas: MapCanvas
var layer := "dark"             # light | dark | deep | archive
var all_rooms: Dictionary = {}
var _go: Button
var _info: Label
var _archive: VBoxContainer
var _scroll: ScrollContainer
var hood_view: Control          # hood_map_view.gd: your streets, hand-drawn (Light World, once mapped)
var map_note := ""              # [LIGHT_WORLD_MAP] why the hand-drawn map isn't showing ("" when it is)
var _map_note_label: Label
var _hood_box: VBoxContainer


func setup_map(game_world: Node) -> void:
	world = game_world
	setup("World Map", Vector2(1000, 680))
	canvas = MapCanvas.new()
	canvas.card = CARD
	canvas.gap = GAP
	for id in Array(SaveManager.list_rooms()) + Array(SaveManager.list_light_rooms()):
		all_rooms[id] = world.room.data if id == GameState.current_room_id else SaveManager.load_room(id)
	canvas.here = GameState.current_room_id
	canvas.selected = canvas.here
	canvas.picked.connect(_on_pick)
	var tabs := UiKit.flow_row(8)   # (wraps on a phone instead of sliding sideways)
	for l in [["light", "☀ Light World"], ["dark", "🌙 Dream World"], ["deep", "🌀 The Deep"], ["archive", "Archive"]]:
		var b := UiKit.button(str(l[1]), func(): show_layer(str(l[0])), 0)
		b.name = "Layer_" + str(l[0])
		tabs.add_child(b)
	body.add_child(tabs)
	body.add_child(UiKit.para("Tap a place to go.", 16, ThemeBuilder.MUTED))
	_scroll = UiKit.scroll(canvas)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	_archive = UiKit.vbox(8)
	_archive.visible = false
	body.add_child(_archive)
	_hood_box = UiKit.vbox(6)
	_hood_box.visible = false
	_hood_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_hood_box)
	var row := UiKit.hbox(10)
	_info = UiKit.label("", 18, ThemeBuilder.CREAM)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_info)
	_go = UiKit.button("Go there", func(): go(canvas.selected), 200)
	row.add_child(_go)
	body.add_child(row)
	show_layer(layer_of(world.room.data))
	_on_pick(canvas.here)


## The layer a place belongs to: light (your real home), dark, deep, archive.
func layer_of(room: Dictionary) -> String:
	if Realms.is_light(room):
		return "light"
	if not DarkWorlds.is_dark(room):
		return "dark"
	return "archive" if str(room.get("id", "")) in DarkWorlds.dark_worlds(all_rooms).archive else "deep"


## One layer of the map: the Light World, the Dream World, the open Deep places, or the Archive.
func show_layer(l: String) -> void:
	layer = l
	_hood_box.visible = false
	if l == "light" and _show_hood():
		return
	var shown := {}
	for id in all_rooms:
		if layer_of(all_rooms[id]) == l:
			shown[id] = all_rooms[id]
	_scroll.visible = l != "archive"
	_archive.visible = l == "archive"
	if l == "archive":
		for c in _archive.get_children():
			c.queue_free()
		if shown.is_empty():
			_archive.add_child(UiKit.para("Nothing sealed. Sealed Deep places wait here.", 18, ThemeBuilder.MUTED))
		for id in shown:
			var r := UiKit.hbox(8)
			var lab := UiKit.label(str(all_rooms[id].get("name", id)), 20)
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(lab)
			r.add_child(UiKit.button("Reopen", func(): reopen(str(id)), 140))
			_archive.add_child(r)
		return
	if shown.is_empty() and l == "light":
		_archive.visible = true
		_scroll.visible = false
		for c in _archive.get_children():
			c.queue_free()
		_archive.add_child(UiKit.para("No real home yet. The way home is in %s." % str(all_rooms.get(str(GameState.world.get("start_room", "home")), {}).get("name", "your start place")), 18, ThemeBuilder.MUTED))
		return
	if l == "light" and map_note != "":
		if _map_note_label == null:
			_map_note_label = UiKit.para("", 16, ThemeBuilder.YELLOW)
			_map_note_label.name = "MapNote"
			body.add_child(_map_note_label)
			body.move_child(_map_note_label, 1)
		_map_note_label.text = map_note
	if _map_note_label:
		_map_note_label.visible = l == "light" and map_note != ""
	canvas.rooms = shown
	canvas.pos = Places.map_layout(shown, canvas.here if shown.has(canvas.here) else (shown.keys()[0] if not shown.is_empty() else ""))
	canvas.custom_minimum_size = canvas.layout_size()
	canvas.queue_redraw()


## The Light World with your streets: the hand-drawn map (tap a spot to go there), your home's floors
## and your street as buttons, and OpenStreetMap's credit. False when the streets aren't mapped yet.
func _show_hood() -> bool:
	var osm_path: String = load("res://scripts/home/home_store.gd").path("osm.json")
	var extract: Variant = load("res://scripts/core/json_util.gd").read_json(osm_path, {})
	if not extract is Dictionary or (extract as Dictionary).get("features", []).is_empty():
		# [LIGHT_WORLD_MAP] Not mapped (or the saved map can't be read): the place cards, and how to get the map.
		var HoodMap: GDScript = load("res://scripts/home/hood_map_view.gd")
		map_note = HoodMap.NOT_MAPPED if not FileAccess.file_exists(osm_path) else HoodMap.UNREADABLE
		return false
	map_note = ""
	_scroll.visible = false
	_archive.visible = false
	_hood_box.visible = true
	for c in _hood_box.get_children():
		c.queue_free()
	hood_view = load("res://scripts/home/hood_map_view.gd").new()
	hood_view.name = "HoodMap"
	hood_view.custom_minimum_size = Vector2(0, 320)
	hood_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hood_view.set_extract(extract)
	hood_view.picked.connect(func(id): go(str(id)))
	_hood_box.add_child(hood_view.clipped_container())
	# [LIGHT_WORLD_MAP] − / + / Fit beside the drag, wheel and pinch (hood_map_view.gd).
	var zoom_row := UiKit.hbox(6)
	zoom_row.name = "MapZoom"
	for spec in [["−", func(): hood_view.zoom_by(1.0 / 1.25)], ["+", func(): hood_view.zoom_by(1.25)], ["Fit", func(): hood_view.fit()]]:
		var zb := UiKit.button(str(spec[0]), spec[1], 56)
		zb.tooltip_text = str(hood_view.ZOOM_TIPS[spec[0]])
		zoom_row.add_child(zb)
	zoom_row.add_child(UiKit.label(hood_view.HINT, 16, ThemeBuilder.MUTED))
	_hood_box.add_child(zoom_row)
	var credit := UiKit.label(str((extract as Dictionary).get("credit", "© OpenStreetMap contributors")), 14, ThemeBuilder.MUTED)
	credit.name = "OsmCredit"
	_hood_box.add_child(credit)
	var row := UiKit.flow_row(6)
	var ids: Array = all_rooms.keys().filter(func(k): return str(k).begins_with("lw_floor_"))
	ids.sort()
	for id in ids:
		row.add_child(UiKit.button(str(all_rooms[id].get("name", id)), func(): go(str(id)), 0))
	var gid := load("res://scripts/home/home_places.gd").place_id(0) as String
	if all_rooms.has(gid):
		for o in all_rooms[gid].get("objects", []):
			if bool(o.get("street_gate", false)):
				var street := str(o.get("door_target", ""))
				row.add_child(UiKit.button("Your street", func(): go(street), 0))
	_hood_box.add_child(row)
	return true


## Reopens a sealed Deep place: you go to its fountain, and it opens (animated).
func reopen(dark_id: String) -> void:
	var f := DarkWorlds.fountain_to(all_rooms, dark_id)
	if f.is_empty():
		return
	var place := str(f.place)
	var fid := str(f.fountain.get("id", ""))
	close()
	if place != GameState.current_room_id:
		await world.go_to_room(place)
	var o: Dictionary = world.room.find_object(fid)
	if not o.is_empty():
		await world.dark.reopen(o)


func _on_pick(id: String) -> void:
	var room: Dictionary = all_rooms.get(id, {})
	_info.text = "%s  •  %s" % [str(room.get("name", id)), str(Places.KIND_LABELS.get(Places.kind(room), ""))]
	_go.disabled = id == GameState.current_room_id
	_go.text = "You're here" if _go.disabled else "Go there"


func go(id: String) -> void:
	if id == "" or id == GameState.current_room_id or not SaveManager.room_exists(id):
		return
	close()
	world.dark.travel_to(id)
