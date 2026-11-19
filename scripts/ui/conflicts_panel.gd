extends "res://scripts/ui/screen_panel.gd"
## Phone conflicts for one world: files that changed on the PC and on the
## phone between two syncs. The PC version stayed in use; the phone's copy
## waits here. Keep the PC version (the stash is removed) or use the phone's
## (a snapshot is taken first, then the phone's file replaces the PC's).

signal changed

const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

var slot_id := ""
var _list: VBoxContainer


func _ready() -> void:
	setup("Phone conflicts", Vector2(980, 600))
	body.add_child(UiKit.para("These files changed on both the PC and your phone before they could sync. The PC version is the one in use; your phone's version was kept safe here.", 18, ThemeBuilder.MUTED))
	_list = UiKit.vbox(8)
	body.add_child(UiKit.scroll(_list))
	var row := UiKit.hbox(8)
	row.add_child(UiKit.button("Open folder", func(): SaveManager.open_folder(SaveManager.root.path_join("slots").path_join(slot_id).path_join("conflicts")), 180))
	body.add_child(row)
	refresh()


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var items := SyncFiles.conflicts(SaveManager.root, slot_id)
	if items.is_empty():
		_list.add_child(UiKit.para("No conflicts. Everything matches.", 20, ThemeBuilder.CREAM))
		return
	for it in items:
		var r := UiKit.hbox(8)
		var rel := str(it.original).trim_prefix("slots/%s/" % slot_id)
		r.add_child(UiKit.para("%s  •  from the phone, %s" % [rel, str(it.when).replace("_", " ").substr(0, 16)], 18, ThemeBuilder.CREAM))
		r.add_child(UiKit.button("Keep PC version", func(): keep_pc(it), 190))
		r.add_child(UiKit.button("Use phone version", func(): use_phone(it), 210))
		_list.add_child(r)


func keep_pc(it: Dictionary) -> void:
	_remove_stash(str(it.stash))
	changed.emit()
	refresh()


func use_phone(it: Dictionary) -> void:
	if SyncFiles.snapshot(SaveManager.root, slot_id, "before_conflict") == "":
		GameState.notify("Couldn't back up the PC version. Free storage and retry.")
		return
	var bytes := FileAccess.get_file_as_bytes(SaveManager.root.path_join(str(it.stash)))
	if SyncFiles.validate(str(it.original), bytes) != "":
		GameState.notify("That file can't be used (it's damaged). The PC version stays.")
		return
	if not SyncFiles.write_atomic(SaveManager.root.path_join(str(it.original)), bytes):
		GameState.notify("Couldn't save the phone version. Both copies were kept.")
		return
	_remove_stash(str(it.stash))
	var main := get_tree().current_scene
	if main and main.has_method("reload_world_from_disk") and slot_id == SaveManager.slot_id:
		main.reload_world_from_disk()
	GameState.notify("Using your phone's version (a snapshot of the old one was saved first).")
	changed.emit()
	refresh()


## Deletes the stashed file and any folders it leaves empty.
func _remove_stash(rel: String) -> void:
	var full := SaveManager.root.path_join(rel)
	DirAccess.remove_absolute(full)
	var dir := full.get_base_dir()
	var stop := SaveManager.root.path_join("slots").path_join(slot_id).path_join("conflicts")
	while dir.begins_with(stop) and dir != stop and DirAccess.get_files_at(dir).is_empty() and DirAccess.get_directories_at(dir).is_empty():
		DirAccess.remove_absolute(dir)
		dir = dir.get_base_dir()
