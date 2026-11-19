extends "res://scripts/ui/screen_panel.gd"
## Stamps: saved areas you can drop anywhere (rotate/flip while placing).
## Opened from the Room tab to pick one, or from the toolbox to save one.

const Templates := preload("res://scripts/world/templates.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")

var build: Node
var _pending: Dictionary = {}
var _name: LineEdit
var _list: HFlowContainer


func _ready() -> void:
	setup("Stamps", Vector2(1000, 640))
	if not _pending.is_empty():
		var row := UiKit.hbox(8)
		_name = UiKit.line_edit("Name this stamp", "")
		row.add_child(_name)
		row.add_child(UiKit.button("Save stamp", func():
			var id := Templates.save_stamp(_name.text, _pending, _thumb(_pending))
			GameState.notify("Stamp \"%s\" saved ✓" % Templates.load_template(id, "stamps").name)
			_pending = {}
			row.queue_free()
			_fill(), 160))
		body.add_child(row)
	_list = HFlowContainer.new()
	_list.add_theme_constant_override("h_separation", 10)
	_list.add_theme_constant_override("v_separation", 10)
	body.add_child(UiKit.scroll(_list))
	_fill()


## Called before opening to save a selection (see editor_toolbox.gd).
func save_stamp(stamp: Dictionary) -> void:
	_pending = stamp


func _thumb(stamp: Dictionary) -> Image:
	var fake := preload("res://scripts/world/tile_layers.gd").room_from_stamp(preload("res://scripts/world/room_ops.gd").upgrade_stamp(stamp))
	fake["floor"] = {"color": "#2e2552"}
	return TemplateFactory.thumb(fake, 16)


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var stamps := Templates.all("stamps")
	if stamps.is_empty():
		_list.add_child(UiKit.para("No stamps yet. Select an area with the Select tool, then \"Save as stamp\".", 18, ThemeBuilder.MUTED))
	for s in stamps:
		var card := UiKit.vbox(4)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(120, 120)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var tp := Templates.thumb_path(str(s.id), "stamps")
		if tp != "":
			pic.texture = SaveManager.load_texture(tp)
		card.add_child(pic)
		card.add_child(UiKit.label("%s (%d×%d)" % [s.get("name", s.id), int(s.get("w", 1)), int(s.get("d", 1))], 18))
		var row := UiKit.hbox(4)
		row.add_child(UiKit.button("Use", func():
			build.set_stamp(Templates.stamp_for_use(str(s.id)))
			GameState.notify("Click in the room to drop it; R rotates, F flips.")
			close(), 80))
		row.add_child(UiKit.button("✕", func():
			Templates.delete(str(s.id), "stamps")
			_fill(), 44))
		card.add_child(row)
		_list.add_child(card)
