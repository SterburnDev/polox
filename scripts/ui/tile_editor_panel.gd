extends "res://scripts/ui/screen_panel.gd"
## One tile's settings: name, solid, height, tags, order, animation frames,
## duplicate, redraw, delete (with an "in use" warning).

signal changed

const Tilesets := preload("res://scripts/world/tilesets.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")

var set_id := ""
var tile_id := ""
var library := false
var _name: LineEdit
var _solid: CheckBox
var _walkable: CheckBox
var _slippery: CheckBox
var _height: SpinBox
var _tags: LineEdit
var _fps: SpinBox
var _step: OptionButton


func _ready() -> void:
	var s := Tilesets.load_set(set_id, library)
	var t := Tilesets.find_tile(s, tile_id)
	setup("Tile: " + str(t.get("name", tile_id)), Vector2(900, 620))
	var row := UiKit.hbox(14)
	body.add_child(row)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(128, 128)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.texture = SaveManager.load_texture(Tilesets.set_dir(set_id, library).path_join(str(t.image)))
	row.add_child(pic)
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	_name = UiKit.line_edit("Tile name", str(t.name))
	v.add_child(UiKit.field_row("Name", _name, 110))
	_solid = CheckBox.new()
	_solid.text = "Solid by default (blocks walking when placed standing)"
	_solid.button_pressed = bool(t.get("solid", false))
	v.add_child(_solid)
	_walkable = CheckBox.new()
	_walkable.text = "Walkable floor (turn off for water or gaps)"
	_walkable.tooltip_text = "Ground tiles with this off stop walking. Blocks can still use Solid."
	_walkable.button_pressed = bool(t.get("walkable", true))
	v.add_child(_walkable)
	_slippery = CheckBox.new()
	_slippery.text = "Slippery (Platform Mode: slow to start and stop, like ice)"
	_slippery.button_pressed = bool(t.get("slippery", false))
	v.add_child(_slippery)
	_step = UiKit.option(["Default" , "Soft", "Wood", "Stone", "Grass", "Water", "Metal"], maxi(0, Tilesets.STEP_SOUNDS.find(str(t.get("step", "")))))
	_step.tooltip_text = "Footstep sound when walking on this Ground tile"
	v.add_child(UiKit.field_row("Step sound", _step, 110))
	_height = SpinBox.new()
	_height.min_value = 0.5
	_height.max_value = 3.0
	_height.step = 0.5
	_height.value = float(t.get("height", 1.0))
	_height.custom_minimum_size = Vector2(120, 48)
	v.add_child(UiKit.field_row("Height", _height, 110))
	_tags = UiKit.line_edit("tags, comma separated", ", ".join(t.get("tags", [])))
	v.add_child(UiKit.field_row("Tags", _tags, 110))
	var frames: Array = t.get("frames", [])
	var anim := UiKit.hbox(6)
	anim.add_child(UiKit.label("Animation: %d frame%s" % [frames.size() + 1, "" if frames.size() == 0 else "s"], 18, ThemeBuilder.MUTED))
	_fps = SpinBox.new()
	_fps.min_value = 1
	_fps.max_value = 12
	_fps.value = int(t.get("fps", 4))
	_fps.custom_minimum_size = Vector2(90, 44)
	anim.add_child(UiKit.label("fps", 16, ThemeBuilder.MUTED))
	anim.add_child(_fps)
	if frames.size() < Tilesets.MAX_FRAMES - 1:
		anim.add_child(UiKit.button("Draw next frame", func(): _draw_frame(frames.size() + 1), 170))
	if not frames.is_empty():
		anim.add_child(UiKit.button("Drop frames", func():
			var ss := Tilesets.load_set(set_id, library)
			var tt := Tilesets.find_tile(ss, tile_id)
			tt["frames"] = []
			Tilesets.save_set(ss, library)
			changed.emit()
			close(), 130))
	v.add_child(anim)
	var acts := UiKit.hbox(6)
	acts.add_child(UiKit.button("Redraw", func(): _draw_frame(0), 100))
	acts.add_child(UiKit.button("◀ Earlier", func(): _move(-1), 120))
	acts.add_child(UiKit.button("Later ▶", func(): _move(1), 120))
	acts.add_child(UiKit.button("Duplicate", _duplicate, 120))
	acts.add_child(UiKit.button("Delete", _delete, 100))
	v.add_child(acts)
	var save_row := UiKit.hbox(8)
	save_row.alignment = BoxContainer.ALIGNMENT_END
	save_row.add_child(UiKit.button("Save", _save, 140))
	body.add_child(save_row)


func _save() -> void:
	var s := Tilesets.load_set(set_id, library)
	var t := Tilesets.find_tile(s, tile_id)
	if t.is_empty():
		close()
		return
	t["name"] = _name.text.strip_edges() if _name.text.strip_edges() != "" else t.name
	t["solid"] = _solid.button_pressed
	t["walkable"] = _walkable.button_pressed
	t["slippery"] = _slippery.button_pressed
	t["step"] = Tilesets.STEP_SOUNDS[_step.selected]
	t["height"] = _height.value
	t["fps"] = int(_fps.value)
	var tags: Array = []
	for x in _tags.text.split(","):
		var tag := x.strip_edges().to_lower()
		if tag != "" and not tag in tags:
			tags.append(tag)
	t["tags"] = tags
	Tilesets.save_set(s, library)
	changed.emit()
	close()


func _move(delta: int) -> void:
	var s := Tilesets.load_set(set_id, library)
	Tilesets.move_tile(s, tile_id, delta)
	changed.emit()


func _duplicate() -> void:
	var s := Tilesets.load_set(set_id, library)
	var t := Tilesets.find_tile(s, tile_id)
	var img := Image.load_from_file(Tilesets.set_dir(set_id, library).path_join(str(t.image)))
	if img:
		Tilesets.add_tile(s, str(t.name) + " copy", img, {"solid": t.get("solid", false), "height": t.get("height", 1.0), "tags": t.get("tags", [])}, library)
		changed.emit()
		close()


func _draw_frame(frame: int) -> void:
	var p := preload("res://scripts/ui/tile_paint_panel.gd").new()
	p.set_id = set_id
	p.tile_id = tile_id
	p.frame = frame
	p.library = library
	p.saved.connect(func():
		changed.emit()
		close())
	get_tree().current_scene.open_panel(p)


func _delete() -> void:
	var used := Tilesets.rooms_using(set_id, tile_id) if not library else PackedStringArray()
	var c := ConfirmPanel.new()
	add_child(c)
	c.ask("Delete this tile?", ("It is used in: %s. Those spots will show as missing." % ", ".join(used)) if not used.is_empty() else "It isn't used by any room.", "Delete", "Keep it")
	c.answered.connect(func(yes):
		if yes:
			Tilesets.remove_tile(Tilesets.load_set(set_id, library), tile_id, library)
			changed.emit()
			close())
