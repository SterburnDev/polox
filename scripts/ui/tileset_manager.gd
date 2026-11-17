extends "res://scripts/ui/screen_panel.gd"
## Tile Set Manager: this world's sets on the left, the chosen set's tiles on
## the right. Make sets from an atlas, single PNGs or your own drawing;
## rename, reorder, tag, duplicate and delete tiles; export/import
## .polox-tiles; save sets to the Library and add Library sets here.

signal changed

const Tilesets := preload("res://scripts/world/tilesets.gd")
const TilesetFactory := preload("res://scripts/world/tileset_factory.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")
const TileEditor := preload("res://scripts/ui/tile_editor_panel.gd")

var current := ""
var library := false
var _sets_box: VBoxContainer
var _detail: VBoxContainer
var _name_edit: LineEdit
var _new_name: LineEdit
var _new_size: OptionButton


func _ready() -> void:
	setup("Tile sets", Vector2(1200, 700))
	var row := UiKit.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UiKit.vbox(6)
	left.custom_minimum_size.x = 300
	row.add_child(left)
	var toggle := UiKit.hbox(4)
	for spec in [[false, "This world"], [true, "Library"]]:
		var b := UiKit.button(spec[1], func():
			library = spec[0]
			current = ""
			_fill_sets(), 0)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("lib", spec[0])
		toggle.add_child(b)
	left.add_child(toggle)
	_sets_box = UiKit.vbox(4)
	left.add_child(UiKit.scroll(_sets_box))
	var make := UiKit.hbox(4)
	_new_name = UiKit.line_edit("New set name")
	make.add_child(_new_name)
	_new_size = UiKit.option(["16 px", "32 px", "64 px"], 1)
	_new_size.custom_minimum_size.x = 100
	make.add_child(_new_size)
	left.add_child(make)
	left.add_child(UiKit.button("+ New empty set", _create, 0))
	left.add_child(UiKit.button("Import PNG atlas...", _import_atlas, 0))
	left.add_child(UiKit.button("Import .polox-tiles", _import_bundle, 0))
	var starters := UiKit.button("Add starter sets", func():
		TilesetFactory.ensure_builtin()
		for id in TilesetFactory.BUILTIN:
			Tilesets.copy_from_library(id)
		_fill_sets()
		changed.emit(), 0)
	starters.tooltip_text = "All six starter sets, including Seaside and Town House"
	left.add_child(starters)
	_detail = UiKit.vbox(6)
	row.add_child(UiKit.scroll(_detail))
	_fill_sets()


func _fill_sets() -> void:
	for c in _sets_box.get_children():
		c.queue_free()
	for b in _sets_box.get_parent().get_parent().get_child(0).get_children():
		b.set_pressed_no_signal(bool(b.get_meta("lib")) == library)
	var sets := Tilesets.all(library)
	if sets.is_empty():
		_sets_box.add_child(UiKit.para("No sets here yet." if not library else "The Library is empty. Save a set to it, or add the starter sets.", 18, ThemeBuilder.MUTED))
	for s in sets:
		var b := UiKit.button("%s (%d)" % [s.name, s.tiles.size()], func(): _show(str(s.id)), 0)
		b.toggle_mode = true
		b.set_pressed_no_signal(str(s.id) == current)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not s.tiles.is_empty():
			b.icon = SaveManager.load_texture(Tilesets.set_dir(str(s.id), library).path_join(str(s.tiles[0].image)))
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 36)
		_sets_box.add_child(b)
	if current == "" and not sets.is_empty():
		_show(str(sets[0].id))
	elif current == "":
		for c in _detail.get_children():
			c.queue_free()


func _show(id: String) -> void:
	current = id
	for c in _detail.get_children():
		c.queue_free()
	for b in _sets_box.get_children():
		if b is Button:
			b.set_pressed_no_signal(b.text.begins_with(str(Tilesets.load_set(id, library).name) + " ("))
	var s := Tilesets.load_set(id, library)
	var head := UiKit.hbox(6)
	_name_edit = UiKit.line_edit("Set name", str(s.name))
	_name_edit.text_submitted.connect(func(_t): _rename(id))
	head.add_child(_name_edit)
	head.add_child(UiKit.button("Rename", func(): _rename(id), 110))
	head.add_child(UiKit.label("%d px" % int(s.tile_size), 18, ThemeBuilder.MUTED))
	_detail.add_child(head)
	var actions := UiKit.hbox(6)
	if library:
		actions.add_child(UiKit.button("Add to this world", func():
			Tilesets.copy_from_library(id)
			GameState.notify("Added \"%s\" to this world ✓" % s.name)
			changed.emit(), 0))
	else:
		actions.add_child(UiKit.button("Save to Library", func():
			Tilesets.copy_to_library(id)
			GameState.notify("Saved to the Library ✓"), 0))
		actions.add_child(UiKit.button("Export .polox-tiles", func(): _export(id), 0))
		actions.add_child(UiKit.button("Draw a tile", func(): _draw_tile(id, ""), 0))
		actions.add_child(UiKit.button("Import PNGs", func(): _import_pngs(id), 0))
	actions.add_child(UiKit.button("Delete set", func(): _delete_set(id), 0))
	_detail.add_child(actions)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_detail.add_child(grid)
	for t in s.tiles:
		var b := UiKit.button(str(t.name), func(): _edit_tile(id, str(t.id)), 0)
		b.icon = SaveManager.load_texture(Tilesets.set_dir(id, library).path_join(str(t.image)))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 40)
		b.add_theme_font_size_override("font_size", 16)
		b.tooltip_text = ("solid • " if bool(t.get("solid", false)) else "") + ("animated • " if not t.get("frames", []).is_empty() else "") + "tags: " + ", ".join(t.get("tags", []))
		grid.add_child(b)
	if s.tiles.is_empty():
		_detail.add_child(UiKit.para("No tiles yet: draw one, import PNGs, or import an atlas.", 18, ThemeBuilder.MUTED))


func _rename(id: String) -> void:
	var s := Tilesets.load_set(id, library)
	s["name"] = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else s.name
	Tilesets.save_set(s, library)
	_fill_sets()
	changed.emit()


func _create() -> void:
	var s := Tilesets.create(_new_name.text, [16, 32, 64][_new_size.selected], library)
	_new_name.text = ""
	current = str(s.id)
	_fill_sets()
	changed.emit()


func _edit_tile(set_id: String, tile_id: String) -> void:
	var e := TileEditor.new()
	e.set_id = set_id
	e.tile_id = tile_id
	e.library = library
	e.changed.connect(func():
		_show(set_id)
		_fill_sets()
		changed.emit())
	get_tree().current_scene.open_panel(e)


func _draw_tile(set_id: String, tile_id: String) -> void:
	var p := preload("res://scripts/ui/tile_paint_panel.gd").new()
	p.set_id = set_id
	p.tile_id = tile_id
	p.saved.connect(func():
		_show(set_id)
		_fill_sets()
		changed.emit())
	get_tree().current_scene.open_panel(p)


func _import_atlas() -> void:
	UiKit.pick_picture(self, "Pick a PNG atlas (a grid of tiles)", func(path):
		var p := preload("res://scripts/ui/atlas_import_panel.gd").new()
		p.path = path
		p.library = library
		p.done.connect(func(id):
			current = id
			_fill_sets()
			changed.emit())
		get_tree().current_scene.open_panel(p))


func _import_pngs(set_id: String) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	fd.use_native_dialog = not OS.has_feature("web")
	fd.title = "Pick one picture per tile"
	fd.files_selected.connect(func(paths):
		var s := Tilesets.load_set(set_id, library)
		var n := 0
		for p in paths:
			var img: Image = SaveManager.load_picture(p)
			if img:
				Tilesets.add_tile(s, p.get_file().get_basename().replace("_", " "), img, {}, library)
				n += 1
		GameState.notify("Added %d tile%s" % [n, "" if n == 1 else "s"])
		_show(set_id)
		_fill_sets()
		changed.emit()
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))


func _import_bundle() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.polox-tiles, *.zip ; Polox tile sets"])
	fd.use_native_dialog = not OS.has_feature("web")
	fd.current_dir = SaveManager.global_path("exports")
	fd.file_selected.connect(func(path):
		var r := Tilesets.import_set(path)
		GameState.notify(("Imported \"%s\" ✓" % Tilesets.load_set(r.id).name) if r.ok else ("Couldn't import: " + str(r.error)))
		library = false
		current = str(r.id) if r.ok else current
		_fill_sets()
		changed.emit()
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))


func _export(id: String) -> void:
	var dest := SaveManager.global_path("exports").path_join("%s.polox-tiles" % id)
	if Tilesets.export_set(id, dest):
		GameState.notify("Exported to exports\\%s" % dest.get_file())
	else:
		GameState.notify("Export failed.")


func _delete_set(id: String) -> void:
	var used := Tilesets.rooms_using(id) if not library else PackedStringArray()
	var c := ConfirmPanel.new()
	add_child(c)
	var warn := ("It is used in: %s. Those tiles will show as missing." % ", ".join(used)) if not used.is_empty() else "It isn't used by any room."
	c.ask("Delete this tile set?", warn + " (Export it first if you might want it back.)", "Delete", "Keep it")
	c.answered.connect(func(yes):
		if yes:
			Tilesets.delete_set(id, library)
			current = ""
			_fill_sets()
			changed.emit())
