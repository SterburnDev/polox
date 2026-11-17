extends "res://scripts/ui/screen_panel.gd"
## The Trash: worlds you deleted wait here for 30 days. Restore brings one
## back; "Delete forever" asks first.

signal changed

const Slots := preload("res://scripts/core/slots.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")

var _rows: VBoxContainer


func _ready() -> void:
	setup("Trash", Vector2(960, 620))
	body.add_child(UiKit.para("Deleted worlds stay here for %d days, then they're removed for good." % Slots.TRASH_DAYS, 18, ThemeBuilder.MUTED))
	_rows = UiKit.vbox(8)
	body.add_child(UiKit.scroll(_rows))
	_fill()


func _fill() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var items := Slots.trash_list()
	if items.is_empty():
		_rows.add_child(UiKit.label("The Trash is empty.", 20, ThemeBuilder.MUTED))
	for t in items:
		var row := UiKit.hbox(8)
		var l := UiKit.label("%s %s  •  deleted %s  •  %d day%s left" % [t.emoji, t.name, str(t.deleted).replace("T", " ").substr(0, 16), t.days_left, "" if t.days_left == 1 else "s"], 20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		row.add_child(UiKit.button("Restore", func(): _restore(str(t.trash_name)), 130))
		row.add_child(UiKit.button("Delete forever", func(): _forever(str(t.trash_name), str(t.name)), 190))
		_rows.add_child(row)


func _restore(trash_name: String) -> void:
	var id := Slots.restore_from_trash(trash_name)
	GameState.notify(("Restored \"%s\" ✓" % Slots.meta(id).name) if id != "" else "Couldn't restore that world.")
	changed.emit()
	_fill()


func _forever(trash_name: String, display: String) -> void:
	var c := ConfirmPanel.new()
	add_child(c)
	c.ask("Delete \"%s\" forever?" % display, "This can't be undone. (Export it first if you're not sure.)", "Delete forever", "Keep it")
	c.answered.connect(func(yes):
		if yes:
			Slots.delete_forever(trash_name)
			changed.emit()
			_fill())
