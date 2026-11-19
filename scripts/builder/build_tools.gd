extends RefCounted
## What each editor tool does to the room data, cell by cell. build_mode.gd
## owns the state and undo steps; this turns "tool X at cells Y" into edits.

const RoomEditor := preload("res://scripts/world/room_editor.gd")
const RoomOps := preload("res://scripts/world/room_ops.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const TileLayers := preload("res://scripts/world/tile_layers.gd")
const SmartTiles := preload("res://scripts/world/smart_tiles.gd")

var b: Node   # build_mode.gd
## What the last apply changed: tile cells only (redrawn chunk by chunk), or
## something structural (pieces, objects, the room) that needs a full rebuild.
var touched: Array = []
var structural := false


func _init(build_mode: Node) -> void:
	b = build_mode


## Call before a tool runs; apply_cells fills `touched` / `structural`.
func begin_change() -> void:
	touched = []
	structural = false


func _room() -> Dictionary:
	return b.world.room.data


## The cells one click covers (brush size, or the whole fill region).
func cells_for(center: Vector2i) -> Array:
	if b.tool == "fill":
		return RoomOps.flood_cells(_room(), center, b.layer if b.piece == "tile" and b.mode != "objects" else "")
	if b.tool in ["place", "brush", "erase"]:
		return RoomOps.brush_cells(center, b.brush_size)
	return [center]


func shape_cells(a: Vector2i, c: Vector2i) -> Array:
	match b.tool:
		"line":
			return RoomOps.line_cells(a, c)
		"rect":
			return RoomOps.rect_cells(a, c, true)
		"rect_outline", "select":
			return RoomOps.rect_cells(a, c, false)
	return [c]


## Runs the current tool on every cell. Returns true if anything changed.
func apply_cells(cells: Array, hit: Dictionary) -> bool:
	var any := false
	match b.tool:
		"eyedropper":
			return pick(cells[0] if not cells.is_empty() else b.cursor)
		"select":
			return false
		"stamp":
			structural = true
			return place_stamp(b.cursor)
		"paint":
			structural = true
			return _paint(b.cursor, hit)
		"edit":
			return _edit(b.cursor)
		"erase":
			for c in cells:
				any = erase_at(c) or any
		_:
			for c in cells:
				if RoomEditor.in_bounds(_room(), c.x, c.y):
					any = place_at(c) or any
	return any


# --- Placing --------------------------------------------------------------------------------

func can_place(c: Vector2i) -> bool:
	var data := _room()
	if not RoomEditor.in_bounds(data, c.x, c.y):
		return false
	if b.piece == "tile":
		return b.brush_set != "" or (b.random_on and not b.random_pool.is_empty())
	if not RoomEditor.object_at(data, c.x, c.y).is_empty():
		return false
	var blocking: bool = b.piece in b.world.room.BLOCKING_TILES or b.piece in b.world.room.BLOCKING_OBJECTS
	if blocking and c == b.world.player.cell():
		return false
	if blocking:
		for id in b.world.actors:
			if b.world.actors[id].cell() == c:
				return false
	var h := RoomEditor.stack_top(data, c.x, c.y)
	return h + BlockFactory.height_of(b.piece) <= RoomEditor.MAX_HEIGHT


func _pick_tile() -> Array:
	if b.random_on and not b.random_pool.is_empty():
		return b.random_pool[randi() % b.random_pool.size()]
	return [b.brush_set, b.brush_tile]


## The cell a tile brush paints right now (orientation, level, turn, flags).
func brush_flags() -> Dictionary:
	var f := {"r": b.rot, "fl": b.flip}
	var type: String = b.layer_type()
	if type != "ground":
		f["o"] = b.orient
		f["y"] = b.elevation
		if b.solid:   # ticked = solid whatever the tile says; else the tile decides
			f["solid"] = true
	if type == "foreground" and not b.fade:
		f["fade"] = false
	return f


func place_at(c: Vector2i) -> bool:
	var data := _room()
	if b.piece == "tile":
		if b.smart_group != "":
			var smart_touched := SmartTiles.paint(data, b.layer, c, b.brush_set, b.smart_group)
			if smart_touched.is_empty():
				return false
			touched.append_array(smart_touched)
			return true
		var st := _pick_tile()
		if str(st[0]) == "" or str(st[1]) == "":
			return false
		var before := RoomOps.cell_at(data, b.layer, c.x, c.y)
		var made := RoomOps.paint(data, b.layer, c.x, c.y, str(st[0]), str(st[1]), brush_flags())
		if made.is_empty() or made == before:
			return false
		touched.append(c)
		return true
	structural = true
	if not can_place(c):
		return false
	if b.piece in BlockFactory.TILE_TYPES:
		return not RoomEditor.add_tile(data, c.x, c.y, b.piece, b.color, b.texture, b.rot).is_empty()
	var made := RoomEditor.add_object(data, c.x, c.y, b.piece, b.color if b.piece != "prop" else "", b.texture, b.rot)
	if made.is_empty():
		return false
	if b.piece == "pickup":
		made["item"] = _default_pickup_item()
		made["count"] = 1
		made["respawn"] = "once"
		made["taken"] = ""
	elif b.piece in BlockFactory.PLATFORM_OBJECTS:
		made.merge(platform_defaults(b.piece), true)
		if b.color == "#8a7bc8":
			made["color"] = ""   # the palette's default colour: use the piece's own
	elif not b.snap:  # half-cell placement for props and signs
		made["pos"][0] = c.x + 0.5
	if b.piece in ["sign", "door", "pickup", "platform_pillar", "mover", "jump_pad", "shard"]:
		b.call_deferred("open_object_editor", str(made.id))
	return true


## What a freshly placed Platform Mode piece starts with.
static func platform_defaults(type: String) -> Dictionary:
	match type:
		"platform_pillar":
			return {"label": "", "repeat": "repeat", "target_room": "", "target_spawn": []}
		"jump_pad":
			return {"strength": 14.0}
		"one_way":
			return {"elev": 1}
		"mover":
			return {"elev": 1, "dx": 3, "dy": 0, "dz": 0, "speed": 1.5}
		"shard":
			return {"elev": 0, "memory": ""}
	return {}


## A new pickup holds the item last picked for one, else the first design.
func _default_pickup_item() -> String:
	const Items := preload("res://scripts/items/items.gd")
	if Items.exists(b.pickup_item):
		return b.pickup_item
	var ids := Items.ids()
	return ids[0] if not ids.is_empty() else ""


func erase_at(c: Vector2i) -> bool:
	var data := _room()
	if not RoomEditor.in_bounds(data, c.x, c.y):
		return false
	if b.mode == "objects":
		structural = true
		var obj := RoomEditor.object_at(data, c.x, c.y)
		return not obj.is_empty() and RoomEditor.remove_object(data, str(obj.id))
	if b.piece == "tile":
		if not RoomOps.cell_at(data, b.layer, c.x, c.y).is_empty() and str(RoomOps.cell_at(data, b.layer, c.x, c.y).get("smart_group", "")) != "":
			var smart_touched := SmartTiles.erase(data, b.layer, c)
			if not smart_touched.is_empty():
				touched.append_array(smart_touched)
				return true
		if RoomOps.erase(data, b.layer, c.x, c.y):
			touched.append(c)
			return true
		if b.layer_type() != "blocks":
			return false
	# The Blocks layer also clears what stands there: an object, then the top piece.
	structural = true
	var obj := RoomEditor.object_at(data, c.x, c.y)
	if not obj.is_empty():
		return RoomEditor.remove_object(data, str(obj.id))
	return _remove_top_block(data, c)


## Removes the highest thing on the Blocks layer (a block or a sprite).
func _remove_top_block(data: Dictionary, c: Vector2i) -> bool:
	var best := -1
	var best_y := -1.0
	var tiles: Array = data.get("tiles", [])
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		if int(t.get("x", -1)) == c.x and int(t.get("z", -1)) == c.y and float(t.get("y", 0)) >= best_y:
			best = i
			best_y = float(t.get("y", 0))
	if best == -1:
		return false
	tiles.remove_at(best)
	return true


# --- Eyedropper -------------------------------------------------------------------------

## Makes whatever is under the cursor the current brush.
func pick(c: Vector2i) -> bool:
	var data := _room()
	var obj := RoomEditor.object_at(data, c.x, c.y)
	if b.mode == "objects" and not obj.is_empty():
		b.set_piece(str(obj.type))
		b.set_paint(str(obj.get("color", b.color)) if str(obj.get("color", "")) != "" else b.color, str(obj.get("texture", "")))
		return true
	# The active tile layer first, then any tile layer (top to bottom), then a piece.
	var layers: Array = TileLayers.all(data).duplicate()
	layers.reverse()
	var order: Array = [TileLayers.find(data, b.layer)] + layers
	for l in order:
		if l.is_empty():
			continue
		var cell := TileLayers.get_cell(l, c.x, c.y)
		if cell.is_empty():
			continue
		if str(l.id) != b.layer:
			b.set_layer(str(l.id))
		b.set_brush_tile(str(cell.s), str(cell.t))
		b.rot = int(cell.get("r", 0))
		b.flip = bool(cell.get("fl", false))
		if str(l.type) != "ground":
			b.set_orient(TileLayers.orient_of(l, cell))
			b.set_elevation(int(cell.get("y", 0)))
			b.fade = bool(cell.get("fade", true))
		b.set_tool("place")
		return true
	var top := {}
	for t in data.get("tiles", []):
		if int(t.get("x", -1)) == c.x and int(t.get("z", -1)) == c.y and (top.is_empty() or float(t.get("y", 0)) > float(top.get("y", 0))):
			top = t
	if top.is_empty():
		return false
	if str(top.get("texture", "")).begins_with("tilesets/"):
		var parts := str(top.texture).split("/")
		b.set_brush_tile(parts[1], parts[3].get_basename())
	else:
		b.set_piece(str(top.type))
		b.set_paint(str(top.get("color", b.color)), str(top.get("texture", "")))
	b.set_tool("place")
	return true


# --- Paint / edit (blocks, objects, surfaces) ---------------------------------------------

func _paint(c: Vector2i, hit: Dictionary) -> bool:
	var kind := str(hit.collider.get_meta("kind", "")) if not hit.is_empty() else ""
	if kind == "floor":
		RoomEditor.paint_surface(_room(), "floor", b.color, b.texture)
		return true
	if kind == "wall":
		RoomEditor.paint_surface(_room(), "wall", b.color, b.texture)
		return true
	if RoomEditor.paint_piece_at(_room(), c.x, c.y, b.color, b.texture):
		return true
	RoomEditor.paint_surface(_room(), "floor", b.color, b.texture)
	return true


func _edit(c: Vector2i) -> bool:
	var obj := RoomEditor.object_at(_room(), c.x, c.y)
	if not obj.is_empty():
		b.open_object_editor(str(obj.id))
		return false
	if b.shell and b.shell.has_method("inspect_cell"):
		b.shell.inspect_cell(c)
	return false


# --- Selection / clipboard / stamps ----------------------------------------------------------

func has_selection() -> bool:
	return b.selection.size.x > 0 and b.selection.size.y > 0


func _sel_corners() -> Array:
	return [b.selection.position, b.selection.position + b.selection.size - Vector2i.ONE]


func copy_selection() -> void:
	if not has_selection():
		return
	var cr := _sel_corners()
	b.clipboard = RoomOps.copy_region(_room(), cr[0], cr[1])
	b.state_changed.emit()


func cut_selection() -> void:
	if not has_selection():
		return
	copy_selection()
	b.edit_room(func(data): RoomOps.clear_region(data, _sel_corners()[0], _sel_corners()[1]), "remove")


func delete_selection() -> void:
	if not has_selection():
		return
	b.edit_room(func(data): RoomOps.clear_region(data, _sel_corners()[0], _sel_corners()[1]), "remove")


## Makes the clipboard the stamp and switches to the stamp tool (click to drop).
func paste_clipboard() -> void:
	if b.clipboard.is_empty():
		return
	b.set_stamp(b.clipboard.duplicate(true))


func rotate_selection() -> void:
	if not has_selection():
		return
	var cr := _sel_corners()
	var turned := RoomOps.rotate_stamp(RoomOps.copy_region(_room(), cr[0], cr[1]))
	b.edit_room(func(data):
		RoomOps.clear_region(data, cr[0], cr[1])
		RoomOps.paste(data, turned, cr[0], "merge"))
	b.selection = Rect2i(cr[0], Vector2i(int(turned.w), int(turned.d)))


func flip_selection() -> void:
	if not has_selection():
		return
	var cr := _sel_corners()
	var mirrored := RoomOps.flip_stamp(RoomOps.copy_region(_room(), cr[0], cr[1]))
	b.edit_room(func(data):
		RoomOps.clear_region(data, cr[0], cr[1])
		RoomOps.paste(data, mirrored, cr[0], "merge"))


func place_stamp(at: Vector2i) -> bool:
	if b.stamp.is_empty():
		return false
	return RoomOps.paste(_room(), b.stamp, at, "merge") > 0


func selection_stamp() -> Dictionary:
	if not has_selection():
		return {}
	var cr := _sel_corners()
	return RoomOps.copy_region(_room(), cr[0], cr[1])
