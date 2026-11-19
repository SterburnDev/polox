extends "res://scripts/ui/screen_panel.gd"
## Templates: start a new room (or linked rooms) from one, apply one onto the
## current room (replace or merge), save the current room as a template.

const Templates := preload("res://scripts/world/templates.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")

var build: Node
var _grid: GridContainer
var _search: LineEdit


func _ready() -> void:
	setup("Templates", Vector2(1200, 700))
	TemplateFactory.ensure_builtin()
	var top := UiKit.columns(8)
	_search = UiKit.line_edit("Search templates by name or tag...")
	_search.text_changed.connect(func(_t): _fill())
	top.add_child(_search)
	top.add_child(UiKit.button("Save this room" if UiKit.upright_phone() else "Save this room as a template", _save_current, 0 if UiKit.upright_phone() else 300))
	body.add_child(top)
	_grid = GridContainer.new()
	_grid.columns = 1 if UiKit.upright_phone() else 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	body.add_child(UiKit.scroll(_grid))
	_fill()


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var q := _search.text.strip_edges().to_lower()
	for t in Templates.all():
		var hay := (str(t.get("name", "")) + " " + str(t.get("description", "")) + " " + " ".join(t.get("tags", []))).to_lower()
		if q != "" and hay.find(q) == -1:
			continue
		_grid.add_child(_card(t))


func _card(t: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, Color(ThemeBuilder.CREAM, 0.35), 2, 10, 8))
	var v := UiKit.vbox(4)
	card.add_child(v)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(240 if UiKit.upright_phone() else 300, 150)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tp := Templates.thumb_path(str(t.id))
	if tp != "":
		thumb.texture = SaveManager.load_texture(tp)
	v.add_child(thumb)
	var rooms: int = t.get("rooms", {}).size()
	v.add_child(UiKit.label("%s%s" % [t.get("name", t.id), (" (%d rooms)" % rooms) if rooms > 1 else ""], 20, ThemeBuilder.YELLOW))
	var desc := UiKit.para(str(t.get("description", "")), 16, ThemeBuilder.MUTED)
	desc.max_lines_visible = 2
	v.add_child(desc)
	if not t.get("tags", []).is_empty():
		v.add_child(UiKit.label("#" + "  #".join(t.get("tags", [])), 14, ThemeBuilder.MINT))
	var row := UiKit.hbox(4)
	var new_btn := UiKit.button("New room", func(): _new_level(str(t.id)), 0)
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_btn.tooltip_text = "Make a new room (or rooms) from this and go there"
	row.add_child(new_btn)
	var apply := UiKit.button("Apply here", func(): _apply(str(t.id), str(t.get("name", ""))), 0)
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply.tooltip_text = "Put this template into the current room"
	row.add_child(apply)
	if not bool(t.get("builtin", false)):
		row.add_child(UiKit.button("✕", func():
			Templates.delete(str(t.id))
			_fill(), 44))
	v.add_child(row)
	return card


func _new_level(id: String) -> void:
	var made := Templates.new_level(id)
	if made.is_empty():
		GameState.notify("That template is empty.")
		return
	GameState.notify("Made %d room%s from the template" % [made.size(), "" if made.size() == 1 else "s"])
	close()
	build.exit()
	build.world.go_to_room(made[0])


func _apply(id: String, display: String) -> void:
	var c := ConfirmPanel.new()
	add_child(c)
	c.ask("Apply \"%s\" to this room?" % display, "Replace swaps everything in this room for the template (doors you placed stay). Merge keeps what you built and adds the template on top. Both can be undone.", "Replace", "Merge")
	c.answered.connect(func(replace):
		build.edit_room(func(data):
			var rid := str(data.get("id", ""))
			SaveManager.save_room(data)
			Templates.apply_to_room(id, rid, "replace" if replace else "merge")
			var fresh := SaveManager.load_room(rid)
			data.clear()
			data.merge(fresh))
		GameState.notify("Template applied ✓ (Undo takes it back)")
		close())


func _save_current() -> void:
	var p := preload("res://scripts/ui/save_template_panel.gd").new()
	p.build = build
	p.saved.connect(_fill)
	get_tree().current_scene.open_panel(p)
