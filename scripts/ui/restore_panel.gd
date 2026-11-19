extends "res://scripts/ui/screen_panel.gd"
## Restore: a timeline of this world's snapshots (automatic, manual, quick,
## before-restore). Restoring snapshots the current state first, so a wrong
## pick is itself undoable.

signal restored

const Slots := preload("res://scripts/core/slots.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")

const KIND_NAMES := {"auto": "automatic", "manual": "backup", "quick": "quick-save", "before_restore": "before a restore", "pre_migration": "before an update"}

var slot_id := ""
var _rows: VBoxContainer


func _ready() -> void:
	setup("Restore \"%s\"" % Slots.meta(slot_id).name, Vector2(980, 640))
	body.add_child(UiKit.para("Pick a moment to go back to. The world as it is right now is zipped first, so you can always come back.", 18, ThemeBuilder.MUTED))
	_rows = UiKit.vbox(8)
	body.add_child(UiKit.scroll(_rows))
	var row := UiKit.hbox(8)
	row.add_child(UiKit.button("Back up now", func():
		SlotArchive.snapshot(slot_id, "manual")
		_fill(), 160))
	row.add_child(UiKit.button("Open backups folder", func(): SaveManager.open_folder(SlotArchive.backups_dir(slot_id)), 230))
	body.add_child(row)
	_fill()


func _fill() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var items := SlotArchive.backups(slot_id)
	if items.is_empty():
		_rows.add_child(UiKit.label("No snapshots yet. They appear as you play (see the card's autosave settings).", 20, ThemeBuilder.MUTED))
	for b in items:
		var row := UiKit.hbox(8)
		var when := str(b.stamp)
		if when.length() >= 17:
			when = "%s %s:%s" % [when.substr(0, 10), when.substr(11, 2), when.substr(13, 2)]
		var l := UiKit.label("%s  •  %s  •  %s" % [when, KIND_NAMES.get(b.kind, b.kind), Slots.size_text(int(b.bytes))], 20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		row.add_child(UiKit.button("Restore", func(): _confirm(str(b.path), when), 130))
		_rows.add_child(row)


func _confirm(path: String, when: String) -> void:
	var c := ConfirmPanel.new()
	add_child(c)
	c.ask("Go back to %s?" % when, "Everything in this world is replaced by that snapshot. A snapshot of right now is made first.", "Restore", "Cancel")
	c.answered.connect(func(yes):
		if not yes:
			return
		var main := get_tree().current_scene
		var was_playing: bool = slot_id == SaveManager.slot_id and main.game != null
		if was_playing:
			main.flush_all()
			main.show_title()
		var r := SlotArchive.restore_backup(slot_id, path)
		if r.ok:
			GameState.notify("Restored ✓")
			restored.emit()
			if was_playing:
				main.play_slot(slot_id)
			close()
		else:
			GameState.notify("Couldn't restore: " + str(r.error)))
