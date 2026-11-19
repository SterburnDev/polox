extends "res://scripts/ui/screen_panel.gd"
## Verify: checks every file of a world (JSON parses, pictures open, nothing
## missing or changed since the last manifest) and offers the fixes.

const Slots := preload("res://scripts/core/slots.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const RestorePanel := preload("res://scripts/ui/restore_panel.gd")

var slot_id := ""
var _list: VBoxContainer
var _summary: Label


func _ready() -> void:
	setup("Verify \"%s\"" % Slots.meta(slot_id).name, Vector2(980, 640))
	_summary = UiKit.para("", 20)
	body.add_child(_summary)
	_list = UiKit.vbox(6)
	body.add_child(UiKit.scroll(_list))
	var row := UiKit.hbox(8)
	row.add_child(UiKit.button("Check again", _run, 150))
	row.add_child(UiKit.button("Restore from a snapshot...", func():
		var r := RestorePanel.new()
		r.slot_id = slot_id
		get_tree().current_scene.open_panel(r), 290))
	var accept := UiKit.button("Accept changes", func():
		SlotArchive.write_manifest(slot_id)
		_run(), 190)
	accept.tooltip_text = "If you edited files by hand on purpose: record them as the new known-good state"
	row.add_child(accept)
	body.add_child(row)
	_run()


func _run() -> void:
	for c in _list.get_children():
		c.queue_free()
	var r := SlotArchive.verify(slot_id)
	var colors := {"broken": ThemeBuilder.DANGER, "changed": ThemeBuilder.YELLOW, "note": ThemeBuilder.MUTED}
	if r.issues.is_empty():
		_summary.text = "All good: %d files (%s) checked, nothing wrong." % [r.files, Slots.size_text(int(r.bytes))]
		_summary.add_theme_color_override("font_color", ThemeBuilder.MINT)
	else:
		var broken: int = r.issues.filter(func(i): return i.severity == "broken").size()
		_summary.text = ("%d problem%s found in %d files." % [r.issues.size(), "" if r.issues.size() == 1 else "s", r.files]) + (" Some data can't be read: restore from a snapshot, or let the game rebuild missing bits." if broken > 0 else " Nothing is lost; some files just changed since the last manifest.")
		_summary.add_theme_color_override("font_color", ThemeBuilder.DANGER if broken > 0 else ThemeBuilder.YELLOW)
	for i in r.issues:
		_list.add_child(UiKit.para("•  %s: %s" % [i.file, i.problem], 18, colors.get(i.severity, ThemeBuilder.CREAM)))
