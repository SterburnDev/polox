extends "res://scripts/ui/screen_panel.gd"
## "Save as template": name, description, tags, which rooms (this one, or
## this one plus the rooms its doors lead to), with an automatic thumbnail.

signal saved

const Templates := preload("res://scripts/world/templates.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")

var build: Node
var _name: LineEdit
var _desc: TextEdit
var _tags: LineEdit
var _linked: CheckBox


func _ready() -> void:
	setup("Save as template", Vector2(820, 520))
	build.flush_save()
	var data: Dictionary = build.world.room.data
	_name = UiKit.line_edit("Template name", str(data.get("name", "")))
	body.add_child(UiKit.field_row("Name", _name, 130))
	_desc = UiKit.text_edit("What is it good for?", "", 80)
	body.add_child(UiKit.field_row("Description", _desc, 130))
	_tags = UiKit.line_edit("tags, comma separated", "")
	body.add_child(UiKit.field_row("Tags", _tags, 130))
	_linked = CheckBox.new()
	var linked := _linked_rooms()
	_linked.text = "Include the %d room%s its doors lead to" % [linked.size(), "" if linked.size() == 1 else "s"]
	_linked.visible = not linked.is_empty()
	body.add_child(_linked)
	body.add_child(UiKit.para("A small top-down thumbnail is drawn automatically. Templates live in the Library and work in every world.", 18, ThemeBuilder.MUTED))
	body.add_child(UiKit.spacer(true))
	var row := UiKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UiKit.button("Save template", _save, 180))
	body.add_child(row)


func _linked_rooms() -> PackedStringArray:
	var out := PackedStringArray()
	for o in build.world.room.data.get("objects", []):
		var t := str(o.get("door_target", ""))
		if t != "" and t != GameState.current_room_id and SaveManager.room_exists(t) and not t in out:
			out.append(t)
	return out


func _save() -> void:
	var rooms := PackedStringArray([GameState.current_room_id])
	if _linked.visible and _linked.button_pressed:
		rooms.append_array(_linked_rooms())
	var tags: Array = []
	for x in _tags.text.split(","):
		var tag := x.strip_edges().to_lower()
		if tag != "" and not tag in tags:
			tags.append(tag)
	var id := Templates.save_from_rooms(_name.text, _desc.text.strip_edges(), tags, rooms, TemplateFactory.thumb(build.world.room.data))
	GameState.notify("Template \"%s\" saved ✓" % Templates.load_template(id).name)
	saved.emit()
	close()
