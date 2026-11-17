extends "res://scripts/ui/screen_panel.gd"
## Everything you can do with one world: play, save, edit its card, copy,
## export, open its folder, verify, back up, restore, delete (to Trash).

signal play
signal changed

const Slots := preload("res://scripts/core/slots.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")
const SlotEditor := preload("res://scripts/ui/slot_editor.gd")
const RestorePanel := preload("res://scripts/ui/restore_panel.gd")
const VerifyPanel := preload("res://scripts/ui/verify_panel.gd")
const ConflictsPanel := preload("res://scripts/ui/conflicts_panel.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")

var slot_id := ""
var menu: Control


func _ready() -> void:
	var m := Slots.meta(slot_id)
	setup("%s %s" % [m.emoji, m.name], Vector2(820, 640))
	var active := slot_id == SaveManager.slot_id
	var playing: bool = active and _main() and _main().game != null
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(UiKit.scroll(grid))
	var items := [
		["▶ " + ("Resume" if active else "Play"), func(): play.emit(), "Load this world"],
		["Edit card", _edit, "Name, emoji, colour, notes, tags, cover, autosave"],
	]
	if playing:
		items.append(["Save now", func(): _save(false), "Write everything and keep a snapshot"])
		items.append(["Quick-save (F5)", func(): _save(true), "Same as Save, in one key press"])
	items.append_array([
		["Duplicate", _duplicate, "A full copy as a new world"],
		["Export .polox", _export, "A single file you can move to another PC"],
		["Open folder", func(): SaveManager.open_folder(Slots.dir(slot_id)), "The plain files of this world"],
		["Verify", _verify, "Check every file for damage"],
		["Back up now", _backup, "Zip this world into its backups folder"],
		["Restore...", _restore, "Go back to an earlier snapshot"],
		["Delete (to Trash)", _delete, "Kept in the Trash for 30 days"],
	])
	var n := SyncFiles.conflicts(SaveManager.root, slot_id).size()
	if n > 0:
		items.insert(2, ["⚠ Phone conflicts (%d)" % n, _conflicts, "Files changed on both the PC and the phone: pick which to keep"])
	for it in items:
		var b := UiKit.button(it[0], it[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 60
		b.tooltip_text = it[2]
		grid.add_child(b)
	if not OS.has_feature("web") and not OS.has_feature("android"):
		var phone := CheckBox.new()
		phone.text = "📱 Available on phone"
		phone.add_theme_font_size_override("font_size", 20)
		phone.tooltip_text = "A paired phone (Phone Link) sees and can play this world. Untick to keep it on the PC only."
		phone.button_pressed = Slots.on_phone(slot_id)
		phone.toggled.connect(func(on):
			Slots.set_on_phone(slot_id, on)
			changed.emit())
		body.add_child(phone)
	var st := Slots.stats(slot_id)
	body.add_child(UiKit.para("%d rooms • %d friends • %s on disk • created %s" % [st.rooms, st.characters, Slots.size_text(st.bytes), str(m.created).substr(0, 10)], 18, ThemeBuilder.MUTED))


func _main() -> Node:
	return get_tree().current_scene


func _save(quick: bool) -> void:
	var main := _main()
	if main and main.get("autosave"):
		await main.autosave.save_now(quick)
	changed.emit()
	close()


func _edit() -> void:
	var e := SlotEditor.new()
	e.slot_id = slot_id
	e.saved.connect(func():
		changed.emit()
		close())
	_main().open_panel(e)


func _conflicts() -> void:
	var c := ConflictsPanel.new()
	c.slot_id = slot_id
	c.changed.connect(func(): changed.emit())
	_main().open_panel(c)


func _duplicate() -> void:
	var id := Slots.duplicate_slot(slot_id)
	GameState.notify("Copied as \"%s\"" % Slots.meta(id).name)
	changed.emit()
	close()


func _export() -> void:
	var m := Slots.meta(slot_id)
	var stamp := Time.get_date_string_from_system()
	var dest := SaveManager.global_path("exports").path_join("%s_%s.%s" % [SaveManager.unique_id(str(m.name), PackedStringArray()), stamp, SlotArchive.BUNDLE_EXT])
	if SlotArchive.export_bundle(slot_id, dest):
		var phone: Node = _main().get("phone")
		if phone != null:
			# On a phone the exports folder is private storage: put a copy where the player can reach it.
			GameState.notify("Exported. Copying it to Downloads and your PC...")
			var r: Dictionary = await phone.share_export(dest)
			if not is_instance_valid(phone) or not is_inside_tree():
				return
			var done := ConfirmPanel.new()
			done.ask("Exported ✓", phone.share_text(dest.get_file(), r), "Done", "")
			_main().open_panel(done)
			return
		var c := ConfirmPanel.new()
		c.ask("Exported ✓", "Saved as exports\\%s. Copy it anywhere; Import .polox on the Worlds screen brings it back." % dest.get_file(), "Open exports folder", "Done")
		c.answered.connect(func(yes):
			if yes:
				SaveManager.open_folder(dest.get_base_dir()))
		_main().open_panel(c)
	else:
		GameState.notify("Export failed. Is the disk full?")


func _verify() -> void:
	var v := VerifyPanel.new()
	v.slot_id = slot_id
	_main().open_panel(v)


func _backup() -> void:
	var zip := SlotArchive.snapshot(slot_id, "manual")
	if zip == "":
		GameState.notify("Backup failed. Is the disk full?")
		changed.emit()
		return
	var phone: Node = _main().get("phone")
	if phone == null:
		GameState.notify("Backup saved: backups/" + zip.get_file())
		changed.emit()
		return
	# On a phone the backups folder is private storage: also send it to the PC and to Downloads.
	GameState.notify("Backup made. Sending it to your PC and Downloads...")
	var r: Dictionary = await phone.share_export(zip)
	changed.emit()
	if not is_instance_valid(phone) or not is_inside_tree():
		return
	var done := ConfirmPanel.new()
	done.ask("Backed up ✓", phone.share_text(zip.get_file(), r), "Done", "")
	_main().open_panel(done)


func _restore() -> void:
	var r := RestorePanel.new()
	r.slot_id = slot_id
	r.restored.connect(func():
		changed.emit()
		close())
	_main().open_panel(r)


func _delete() -> void:
	var m := Slots.meta(slot_id)
	var c := ConfirmPanel.new()
	c.ask("Move \"%s\" to the Trash?" % m.name, "Nothing is deleted right away: it waits in the Trash for 30 days, and Restore brings it back.", "Move to Trash", "Keep it")
	c.answered.connect(func(yes):
		if not yes:
			return
		var main := _main()
		if slot_id == SaveManager.slot_id:
			main.flush_all()
			SaveManager.set_slot("")
			main.show_title()
		var name := Slots.delete_to_trash(slot_id)
		GameState.notify(("Moved to the Trash (30 days to change your mind)") if name != "" else "Couldn't move it. Is the folder open somewhere?")
		changed.emit()
		close())
	_main().open_panel(c)
