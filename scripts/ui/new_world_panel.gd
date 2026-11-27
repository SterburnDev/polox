extends "res://scripts/ui/screen_panel.gd"
## "+ New world": start guided (the three-step welcome with a first friend)
## or blank (one empty room, no one home yet).

signal chosen(blank: bool, world_name: String)

var _name: LineEdit


func _ready() -> void:
	setup("New world", Vector2(760, 420))
	_name = UiKit.line_edit("World name (you can change it later)")
	_name.max_length = 60
	body.add_child(UiKit.field_row("Name", _name, 120))
	body.add_child(UiKit.para("Guided: set up your world and first friend (the Light World sequence is completely optional — skip it anytime to use a template). Blank: an empty room to build from scratch. Everything stays on your device unless you use a cloud service or online AI.", 18, ThemeBuilder.MUTED))
	body.add_child(UiKit.spacer(true))
	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UiKit.button("Blank world", func(): _pick(true), 180))
	row.add_child(UiKit.button("Guided (recommended)", func(): _pick(false), 260))
	body.add_child(row)
	_name.call_deferred("grab_focus")


func _pick(blank: bool) -> void:
	var n := _name.text.strip_edges()
	close()
	chosen.emit(blank, n if n != "" else ("Blank World" if blank else "My World"))
