extends Node
## Build mode (the editor) for the current room. Keeps the editing state
## (mode, layer, tool, brush, selection, stamp), routes mouse/keys into
## build_tools.gd, groups a drag into one undo step, and autosaves. The
## screen layout lives in editor_shell.gd.
## Tags: [BUILDER]

const RoomEditor := preload("res://scripts/world/room_editor.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const BuildTools := preload("res://scripts/builder/build_tools.gd")
const EditorShell := preload("res://scripts/builder/editor_shell.gd")
const ObjectEditor := preload("res://scripts/ui/object_editor.gd")
const Synth := preload("res://scripts/core/synth.gd")
const BuildGhost := preload("res://scripts/builder/build_ghost.gd")
const UndoStack := preload("res://scripts/core/undo_stack.gd")
const InputSetup := preload("res://scripts/core/input_setup.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const EditorHotbar := preload("res://scripts/builder/editor_hotbar.gd")
const SmartTiles := preload("res://scripts/world/smart_tiles.gd")

const SAVE_DELAY := 1.0
const UNDO_STEPS := 150
const TOOLS: PackedStringArray = ["place", "brush", "line", "rect", "rect_outline", "fill", "erase", "eyedropper", "select", "stamp", "paint", "edit"]
const DRAG_TOOLS: PackedStringArray = ["brush", "erase"]
const SHAPE_TOOLS: PackedStringArray = ["line", "rect", "rect_outline", "select"]
const KEY_TOOLS := {KEY_1: "place", KEY_2: "brush", KEY_3: "line", KEY_4: "rect", KEY_5: "fill", KEY_6: "erase", KEY_7: "eyedropper", KEY_8: "select", KEY_9: "stamp"}

signal state_changed

var world: Node                 # game_world.gd
var active := false
var mode := "tiles"              # tiles | objects | room
var layer := "ground"            # the tile layer you paint on (its id; the type decides how)
var tool := "place"
var piece := "cube"              # a block/object type, or "tile" (picture from the palette)
var color := "#8a7bc8"
var texture := ""
var rot := 0
var flip := false
var brush_set := ""              # the palette picture: set id + tile id
var brush_tile := ""
var smart_group := ""
var orient := "standing"         # how a picture is placed on the Blocks/Foreground layer
var pickup_item := ""            # the item new pickups hold (last one chosen)
var fade := true
var solid := false
var brush_size := 1
var elevation := 0
var snap := true
var random_on := false
var random_pool: Array = []      # [[set, tile], ...]
var cursor := Vector2i.ZERO
var selection := Rect2i(0, 0, 0, 0)   # size 0 = none
var clipboard: Dictionary = {}
var stamp: Dictionary = {}       # what the stamp tool places
var shell: Control               # editor_shell.gd
var tools: RefCounted            # build_tools.gd
var history := UndoStack.new(UNDO_STEPS)
var _ghost: Node3D
var _cursor_node: Node3D
var _save_in := -1.0
var _dragging := false
var _drag_start := Vector2i.ZERO
var _stroked: Dictionary = {}


func setup(game_world: Node) -> void:
	world = game_world
	add_to_group("build_mode")
	tools = BuildTools.new(self)
	_cursor_node = Node3D.new()
	world.add_child(_cursor_node)


var panel: Control:            # old name for the dock (tests and drives use it)
	get:
		return shell


func enter() -> void:
	if active:
		return
	if load("res://scripts/world/realms.gd").is_light(world.room.data):
		# Your real home: Edit my room (furniture, decor and paint), not Build mode.
		if world.get("decor"):
			world.decor.open()
		return
	active = true
	_hide_back()
	cursor = world.player.cell()
	_pick_first_tile()
	selection = Rect2i(0, 0, 0, 0)
	shell = EditorShell.new()
	world.main.ui.add_child(shell)
	shell.bind(self)
	world.hud.set_building(true)
	_show_taken_pickups(true)
	world.cam.side_offset = -0.9
	world.cam.v_offset = -1.1
	_refresh_ghost()
	state_changed.emit()


func exit() -> void:
	if not active:
		return
	active = false
	flush_save()
	if is_instance_valid(shell):
		shell.queue_free()
	shell = null
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _reach:
		_reach.queue_free()
		_reach = null
	world.cam.target = world.player
	world.cam.side_offset = 0.0
	world.cam.v_offset = 0.0
	world.hud.set_building(false)
	world.hud.set_hint("")
	_show_taken_pickups(false)


## Taken pickups are invisible while playing but shown as ghosts in the editor.
func _show_taken_pickups(on: bool) -> void:
	world.room.editing = on
	for o in world.room.data.get("objects", []):
		if str(o.get("type", "")) == "pickup" and str(o.get("taken", "")) != "":
			world.rebuild_room()
			return


## Leaves the editor and walks from the cursor cell (Play-test from here).
var play_platform := false          # the editor's "start in Platform Mode" toggle
var jump_reach := false             # Advanced: show where a Platform Mode jump can land from the cursor
var _reach: MeshInstance3D


func set_jump_reach(on: bool) -> void:
	jump_reach = on
	if not on and _reach:
		_reach.queue_free()
		_reach = null
	_update_reach()
	state_changed.emit()


func _update_reach() -> void:
	if not jump_reach or not active:
		return
	if _reach == null:
		_reach = load("res://scripts/platform/jump_reach.gd").new()
		world.add_child(_reach)
	_reach.show_from(world.room.data, cursor)
	if shell and world.hud:
		var r: Vector2 = _reach.reach
		world.hud.set_hint("Jump reach (running): up %d block, across %d blocks. Gold = same height or higher, blue = lower." % [int(r.x), int(r.y)])


func play_test() -> void:
	var c := cursor
	exit()   # (saves first: nothing you built is lost)
	if world.room.nav.walkable(c):
		world.player.stop()
		world.player.position = world.room.cell_center(c)
	if play_platform and world.platform:
		world.platform.begin_here()
	_show_back()


## While you playtest from the editor: a glass "Back to building" pill at the top, gone once you're back.
var _back: Control


func _show_back() -> void:
	if world == null or world.main == null or world.main.get("ui") == null:
		return
	_hide_back()
	var UiKit := preload("res://scripts/ui/ui_kit.gd")
	var ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
	var holder := CenterContainer.new()
	holder.name = "BackToBuilding"
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.offset_top = 64
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", ThemeBuilder.bar(ThemeBuilder.RADIUS_L, 6))
	holder.add_child(pill)
	var b := UiKit.button("◀ Back to building", func(): enter(), 0)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Back to the editor, where you were"
	pill.add_child(b)
	world.main.ui.add_child(holder)
	_back = holder


func _hide_back() -> void:
	if _back and is_instance_valid(_back):
		_back.queue_free()
	_back = null


func _process(delta: float) -> void:
	if _save_in > 0.0:
		_save_in -= delta
		if _save_in <= 0.0:
			flush_save()


## An edit not saved yet (it saves by itself SAVE_DELAY seconds later): the editor shows "Saving...".
func has_unsaved() -> bool:
	return _save_in > 0.0


func flush_save() -> void:
	_save_in = -1.0
	SaveManager.save_room(world.room.data)


# --- Input ---------------------------------------------------------------------------

func handle_input(event: InputEvent) -> void:
	if event is InputEventKey and InputSetup.typing(world.get_viewport()):
		return  # typing a room size or name: letters are letters, not tools
	if event is InputEventMouseMotion:
		var hit: Dictionary = world.controller.raycast(event.position)
		if not hit.is_empty():
			var c := _target_cell(hit)
			if c != cursor:
				cursor = c
				_on_cursor_moved()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit: Dictionary = world.controller.raycast(event.position)
			if hit.is_empty():
				if tool == "paint":
					paint_surface("sky")
				return
			cursor = _target_cell(hit)
			_press(hit)
		else:
			_release()
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)
	elif event.is_action_pressed("rotate", true):
		rotate_piece()
	elif event.is_action_pressed("confirm"):
		apply({})
	else:
		var dir := Vector2i.ZERO
		if event.is_action_pressed("move_up", true):
			dir = world.cam.forward_cell_dir()
		elif event.is_action_pressed("move_down", true):
			dir = -world.cam.forward_cell_dir()
		elif event.is_action_pressed("move_right", true):
			dir = world.cam.right_cell_dir()
		elif event.is_action_pressed("move_left", true):
			dir = -world.cam.right_cell_dir()
		if dir != Vector2i.ZERO:
			cursor = Vector2i(clampi(cursor.x + dir.x, 0, world.room.w - 1), clampi(cursor.y + dir.y, 0, world.room.d - 1))
			_cursor_node.position = world.room.cell_center(cursor)
			world.cam.target = _cursor_node
			_on_cursor_moved()


## Single-key extras (every one of these also has a button).
func _key(event: InputEventKey) -> void:
	var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if code >= KEY_1 and code <= KEY_9:
		var favs := EditorHotbar.slots()
		var index := code - KEY_1
		if index < favs.size() and favs[index] is Dictionary and not favs[index].is_empty():
			EditorHotbar.activate(self, favs[index])
	elif KEY_TOOLS.has(code):
		set_tool(KEY_TOOLS[code])
	elif code == KEY_F:
		flip_piece()
	elif code == KEY_G:
		set_snap(not snap)
	elif code == KEY_T:
		var ids: Array = TileLayers.all(world.room.data).map(func(l): return str(l.id))
		if not ids.is_empty():
			set_layer(str(ids[(ids.find(layer) + 1) % ids.size()]))
	elif code == KEY_V:
		tools.paste_clipboard()
	elif code == KEY_BRACKETLEFT:
		set_brush_size(brush_size - 1)
	elif code == KEY_BRACKETRIGHT:
		set_brush_size(brush_size + 1)
	elif code == KEY_MINUS:
		set_elevation(elevation - 1)
	elif code == KEY_EQUAL:
		set_elevation(elevation + 1)
	elif code == KEY_BACKSPACE:
		undo()


func _press(hit: Dictionary) -> void:
	if tool in DRAG_TOOLS:
		_dragging = true
		_stroked.clear()
		_snapshot()
		tools.begin_change()
		tools.apply_cells(tools.cells_for(cursor), hit)
		_stroked[cursor] = true
	elif tool in SHAPE_TOOLS:
		_dragging = true
		_drag_start = cursor
		_on_cursor_moved()
	else:
		apply(hit)


func _release() -> void:
	if not _dragging:
		return
	_dragging = false
	if tool in SHAPE_TOOLS:
		if tool == "select":
			selection = Rect2i(Vector2i(mini(_drag_start.x, cursor.x), mini(_drag_start.y, cursor.y)), Vector2i(absi(cursor.x - _drag_start.x) + 1, absi(cursor.y - _drag_start.y) + 1))
			state_changed.emit()
		else:
			_snapshot()
			tools.begin_change()
			tools.apply_cells(tools.shape_cells(_drag_start, cursor), {})
	_finish_tool_change("remove" if tool == "erase" else "place")
	_on_cursor_moved()


func _on_cursor_moved() -> void:
	if _dragging and tool in DRAG_TOOLS and not _stroked.has(cursor):
		_stroked[cursor] = true
		tools.apply_cells(tools.cells_for(cursor), {})
		if not tools.touched.is_empty() and not tools.structural:
			world.room.cells_changed(layer, tools.touched)
			tools.touched = []
		elif tools.structural:
			world.rebuild_room()
	_place_ghost()
	_update_reach()
	if shell:
		shell.on_cursor(cursor)


## Which cell a click means: clicking the side of a block targets the cell
## next to it; clicking a top surface or the floor targets that cell.
func _target_cell(hit: Dictionary) -> Vector2i:
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var kind := str(hit.collider.get_meta("kind", ""))
	if tool == "place" and piece != "tile" and kind == "tile" and absf(n.y) < 0.5:
		p += n * 0.5
	else:
		p -= n * 0.05
	return Vector2i(clampi(floori(p.x), 0, world.room.w - 1), clampi(floori(p.z), 0, world.room.d - 1))


# --- One action at the cursor -----------------------------------------------------------------

func apply(hit: Dictionary) -> void:
	if RoomOps.layer_state(world.room.data, _active_layer()).lock and tool != "select" and tool != "eyedropper":
		world.hud.set_hint("That layer is locked (Layers panel).")
		return
	_snapshot()
	tools.begin_change()
	var did: bool = tools.apply_cells(tools.cells_for(cursor), hit)
	if did:
		_finish_tool_change("remove" if tool == "erase" else "place")
	else:
		history.drop_last()
		if tool in ["place", "stamp"]:
			_play("remove")


func _finish_tool_change(sound: String) -> void:
	if tools.structural or tools.touched.is_empty():
		_changed(sound)
	else:
		_changed_cells(tools.touched, sound)


func _active_layer() -> String:
	return "pieces" if mode == "objects" or piece != "tile" else layer


## The type of the layer you paint on (backdrop / ground / blocks / foreground).
func layer_type() -> String:
	return str(TileLayers.find(world.room.data, layer).get("type", "ground")) if world else "ground"


## Tiles first: entering the editor with nothing chosen picks the Ground layer
## and the first tile of the first set, so a click paints a tile right away.
func _pick_first_tile() -> void:
	var data: Dictionary = world.room.data
	if TileLayers.find(data, layer).is_empty():
		var g := TileLayers.of_type(data, "ground")
		layer = str(g.id) if not g.is_empty() else str(TileLayers.all(data)[0].id) if not TileLayers.all(data).is_empty() else "ground"
	if brush_set != "" and not Tilesets.info(brush_set, brush_tile).is_empty():
		return
	for sid in Tilesets.ids():
		var s := Tilesets.cached_set(sid)
		if not (s.get("tiles", []) as Array).is_empty():
			brush_set = sid
			brush_tile = str(s.tiles[0].id)
			piece = "tile"
			mode = "tiles"
			return


# --- Settings used by the panels --------------------------------------------------------------

func set_mode(m: String) -> void:
	mode = m
	if m == "objects" and not piece in BlockFactory.OBJECT_TYPES:
		piece = "door"
		tool = "place"
	elif m == "tiles" and piece in BlockFactory.OBJECT_TYPES:
		piece = "cube"
	_refresh_ghost()
	state_changed.emit()


func set_layer(l: String) -> void:
	var was := layer_type()
	layer = l
	var now := layer_type()
	if now != was:   # each layer type has its natural way to place a picture
		orient = str(TileLayers.DEFAULT_ORIENT.get(now, "standing"))
	_refresh_ghost()
	state_changed.emit()


func set_tool(t: String) -> void:
	tool = t if t in TOOLS else "place"
	_dragging = false
	_refresh_ghost()
	state_changed.emit()


func set_piece(p: String) -> void:
	piece = p
	if p in BlockFactory.OBJECT_TYPES:
		mode = "objects"
	elif mode == "objects":
		mode = "tiles"
	if tool in ["erase", "select", "eyedropper", "stamp", "edit", "paint"]:
		tool = "place"
	_refresh_ghost()
	state_changed.emit()


## Picks a picture from the palette (and makes it what you place).
func set_brush_tile(set_id: String, tile_id: String) -> void:
	brush_set = set_id
	brush_tile = tile_id
	smart_group = ""
	piece = "tile"
	if mode == "objects":
		mode = "tiles"
	if tool in ["erase", "select", "eyedropper", "stamp", "edit", "paint"]:
		tool = "place"
	_refresh_ghost()
	state_changed.emit()


func set_smart_group(group_id: String) -> void:
	smart_group = group_id
	if group_id != "":
		var groups: Array = SmartTiles.group(brush_set, group_id).get("variants", [])
		if not groups.is_empty():
			brush_tile = str(groups[0])
		piece = "tile"
		mode = "tiles"
	set_tool("place")


func set_paint(c: String, tex: String) -> void:
	color = c
	texture = tex
	_refresh_ghost()
	state_changed.emit()


func set_orient(o: String) -> void:
	orient = o if o in RoomOps.ORIENTS else "standing"
	_refresh_ghost()
	state_changed.emit()


func set_brush_size(n: int) -> void:
	brush_size = clampi(n, 1, 5)
	_place_ghost()
	state_changed.emit()


func set_elevation(y: int) -> void:
	elevation = clampi(y, 0, RoomOps.MAX_ELEVATION)
	_place_ghost()
	state_changed.emit()


func set_snap(on: bool) -> void:
	snap = on
	state_changed.emit()


func set_random(on: bool) -> void:
	random_on = on
	state_changed.emit()


func toggle_random_tile(set_id: String, tile_id: String) -> void:
	for i in random_pool.size():
		if random_pool[i][0] == set_id and random_pool[i][1] == tile_id:
			random_pool.remove_at(i)
			state_changed.emit()
			return
	random_pool.append([set_id, tile_id])
	state_changed.emit()


func set_stamp(s: Dictionary) -> void:
	stamp = s
	tool = "stamp"
	_refresh_ghost()
	state_changed.emit()


func rotate_piece() -> void:
	if tool == "stamp" and not stamp.is_empty():
		stamp = RoomOps.rotate_stamp(stamp)
	else:
		rot = posmod(rot + 1, 4)
	_refresh_ghost()
	state_changed.emit()


func flip_piece() -> void:
	if tool == "stamp" and not stamp.is_empty():
		stamp = RoomOps.flip_stamp(stamp)
	else:
		flip = not flip
	_refresh_ghost()
	state_changed.emit()


func paint_surface(surface: String) -> void:
	_snapshot()
	RoomEditor.paint_surface(world.room.data, surface, color, texture)
	_changed("place")


func set_room_weather(on: bool) -> void:
	_snapshot()
	var amb: Dictionary = world.room.data.get("ambiance", {})
	amb["weather"] = "auto" if on else "none"
	world.room.data["ambiance"] = amb
	_changed("place")


func resize_room(w: int, d: int) -> void:
	_snapshot()
	RoomEditor.resize(world.room.data, w, d)
	cursor = Vector2i(mini(cursor.x, w - 1), mini(cursor.y, d - 1))
	_changed("place")


## Any edit made by a panel (inspector, room tab): wrap it in an undo step.
func edit_room(what: Callable, sound: String = "place") -> Variant:
	_snapshot()
	var result: Variant = what.call(world.room.data)
	_changed(sound)
	return result


# --- Undo / redo / save -----------------------------------------------------------------

func _snapshot() -> void:
	history.push(world.room.data.duplicate(true))


func undo() -> void:
	var prev: Variant = history.undo(world.room.data.duplicate(true))
	if prev != null:
		world.room.data = prev
		_changed("remove")


func redo() -> void:
	var next: Variant = history.redo(world.room.data.duplicate(true))
	if next != null:
		world.room.data = next
		_changed("place")


## Only tiles changed: redraw those chunks and re-check those cells.
func _changed_cells(cells: Array, sound: String) -> void:
	world.room.cells_changed(layer, _unique_cells(cells))
	_save_in = SAVE_DELAY
	_play(sound)
	_place_ghost()
	state_changed.emit()


func _unique_cells(cells: Array) -> Array:
	var seen := {}
	var out: Array = []
	for c in cells:
		if c is Vector2i and not seen.has(c):
			seen[c] = true
			out.append(c)
	return out


func _changed(sound: String) -> void:
	world.rebuild_room()
	_save_in = SAVE_DELAY
	_play(sound)
	_place_ghost()
	state_changed.emit()


func _play(sound: String) -> void:
	Synth.play(self, sound, 0.5)


func open_object_editor(id: String) -> void:
	var ed := ObjectEditor.new()
	ed.edit(world.room.data, id)
	ed.applied.connect(func(before: Dictionary):
		history.push(before)
		_changed("place"))
	world.main.open_panel(ed)


# --- Ghost preview ---------------------------------------------------------------------

func _refresh_ghost() -> void:
	if not active:
		return
	if _ghost == null:
		_ghost = BuildGhost.new()
		world.add_child(_ghost)
	_ghost.show_for(self)
	_place_ghost()


func _place_ghost() -> void:
	if _ghost == null:
		return
	var ltype := layer_type()
	var y := RoomEditor.stack_top(world.room.data, cursor.x, cursor.y) if piece != "tile" or ltype == "blocks" and orient == "standing" else 0.0
	if piece == "tile" and ltype != "ground":
		y = float(elevation)
	var pos: Vector3 = world.room.cell_center(cursor) + Vector3(0, y + (0.0 if tool == "place" else 0.02), 0)
	var ok: bool = tools.can_place(cursor)
	var tint := Color(0.5, 1.0, 0.6, 0.55) if ok else Color(1.0, 0.4, 0.4, 0.55)
	match tool:
		"erase":
			tint = Color(1.0, 0.45, 0.45, 0.6)
		"paint":
			tint = Color(Color.from_string(color, Color.WHITE), 0.6)
		"edit", "eyedropper", "select":
			tint = Color(1.0, 0.82, 0.4, 0.6)
	var cells: Array = []
	if _dragging and tool in SHAPE_TOOLS:
		cells = tools.shape_cells(_drag_start, cursor)
	elif brush_size > 1 and tool in ["place", "brush", "erase", "fill"]:
		cells = RoomOps.brush_cells(cursor, brush_size)
	_ghost.move_to(pos, tint, cells, selection)
