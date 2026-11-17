extends "res://tests/test_case.gd"
## [CLOUD_SYNC] Settings > Cloud sync, used the way a player uses it: choose the folder, switch a world
## on, Sync now, a second device's change arriving, a conflict asked about and answered with a button,
## a world brought over from the cloud, and the automatic sync at the title screen. The "second device"
## is an engine on another save folder sharing the same cloud folder.
## Tags: [CLOUD_SYNC]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Slots := preload("res://scripts/core/slots.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const CloudService := preload("res://scripts/sync/cloud_service.gd")
const CloudSync := preload("res://scripts/sync/cloud_sync.gd")
const CloudStore := preload("res://scripts/sync/cloud_store.gd")
const CloudPackage := preload("res://scripts/sync/cloud_package.gd")

var main: Node
var cloud_dir := ""
var other_root := ""


func _boot() -> void:
	var root := fresh_save_root()
	cloud_dir = root + "_cloud"
	other_root = root + "_other_device"
	JsonUtil.remove_tree(cloud_dir)
	JsonUtil.remove_tree(other_root)
	GameState.settings.erase("cloud")
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)
	main.begin_new_world()
	await frames(3)


func _shutdown() -> void:
	main._close_all_panels()
	main.queue_free()
	GameState.settings.erase("cloud")
	await frames(2)


func _open_page() -> Control:
	main._close_all_panels()
	var settings: Control = SettingsScreen.new()
	settings.main = main
	settings.start_on = "Cloud sync"
	main.open_panel(settings)
	await frames(3)
	eq(settings.tabs.get_tab_title(settings.tabs.current_tab), "Cloud sync", "Settings has a Cloud sync page")
	return settings.tabs.get_tab_control(settings.tabs.current_tab)


func _find(page: Control, node_name: String) -> Node:
	return page.find_child(node_name, true, false)


func _texts(page: Control) -> String:
	var all := PackedStringArray()
	for label in page.find_children("*", "Label", true, false):
		all.append((label as Label).text)
	return "\n".join(all)


func _other_device() -> CloudSync:
	return CloudSync.new(other_root, CloudStore.FolderStore.new(cloud_dir), "Android phone")


func _edit_room(root: String, slot: String, key: String, value: Variant) -> void:
	var path := root.path_join("slots/%s/rooms/home.json" % slot)
	var room: Dictionary = JsonUtil.read_json(path, {})
	room[key] = value
	JsonUtil.write_json(path, room)


func test_setting_up_and_syncing_a_world_from_the_page() -> void:
	await _boot()
	var slot := SaveManager.slot_id
	var page := await _open_page()
	var said := _texts(page)
	check(said.contains("Phone Link") and said.contains("Your PC is on"), "it says what Phone Link is for")
	check(said.contains("Cloud folder") and said.contains("Your PC can be off"), "and what the cloud folder is for")
	check(_find(page, "OpenPhoneLink") != null, "with a way over to Phone Link")
	check(_find(page, "ChooseFolder") != null and _find(page, "WorldsCard") == null, "no folder yet: choose one first, no worlds listed")
	check(str((_find(page, "NeverSent") as Label).text).contains("AI keys") and str((_find(page, "NeverSent") as Label).text).contains("Light World"), "it says what is never sent")
	eq(page.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_SHOW_NEVER, "no scroll bar, like every Settings page")
	# Choose the folder (what the folder dialog's answer does).
	page._use_folder(cloud_dir)
	await frames(2)
	eq(CloudService.folder(), cloud_dir, "the folder is remembered in settings")
	check(str((_find(page, "FolderStatus") as Label).text).contains("Ready"), "and it can be reached")
	var keep := _find(page, "World_" + slot).find_child("Keep", true, false) as CheckButton
	check(keep != null and not keep.button_pressed, "the world is listed, not in the cloud yet")
	eq(DirAccess.get_files_at(cloud_dir).size(), 0, "nothing is sent just by choosing a folder")
	# Switch the world on: it is sent.
	keep.button_pressed = true
	await frames(4)
	eq(Array(DirAccess.get_files_at(cloud_dir)).filter(func(n): return str(n).ends_with(".poloxsync")).size(), 1, "the world's file is in the cloud folder")
	check(str((_find(page, "CloudMessage") as Label).text).contains("Sent to the cloud"), "and the page says so")
	eq(str((_find(page, "World_" + slot).find_child("State", true, false) as Label).text), "In step with the cloud", "its state in plain words")
	var package := cloud_dir.path_join(str(CloudService.engine().world_state(slot).ref))
	check(CloudPackage.validate(package).ok, "a whole, valid package")
	var packed: Dictionary = CloudPackage.read_meta(package).files
	check(packed.has("world.json") and not packed.keys().any(func(path): return str(path).begins_with("backups/") or str(path).contains("settings")), "with the world's files and no settings or backups")
	check(not FileAccess.get_file_as_string(package).contains(SaveManager.root), "and nothing in it names this PC's folders")
	# The second device takes it, changes it and sends it back; Sync now brings the change into the open game.
	var phone := _other_device()
	var added := phone.add_from_cloud(str(CloudService.engine().world_state(slot).ref))
	check(added.ok, "the other device brings the world over")
	_edit_room(other_root, str(added.slot_id), "name", "Renamed on the phone")
	check(phone.sync(str(added.slot_id)).ok, "and sends a change")
	(_find(page, "World_" + slot).find_child("SyncNow", true, false) as Button).pressed.emit()
	await frames(6)
	check(str((_find(page, "CloudMessage") as Label).text).contains("Updated from the cloud"), "Sync now takes it: " + str((_find(page, "CloudMessage") as Label).text))
	eq(JsonUtil.read_json(SaveManager.root.path_join("slots/%s/rooms/home.json" % slot), {}).get("name"), "Renamed on the phone", "the change is on this device")
	eq(str(SaveManager.load_room("home").get("name")), "Renamed on the phone", "and the running game has it")
	# Switching it off keeps both copies.
	(_find(page, "World_" + slot).find_child("Keep", true, false) as CheckButton).button_pressed = false
	await frames(3)
	check(CloudService.engine().world_state(slot).is_empty() and FileAccess.file_exists(package), "off: the link is forgotten, the cloud file stays")
	check(Slots.exists(slot), "and so does the world")
	await _shutdown()


func test_a_conflict_is_asked_about_on_the_page_and_answered_with_a_button() -> void:
	await _boot()
	var slot := SaveManager.slot_id
	var page := await _open_page()
	page._use_folder(cloud_dir)
	await frames(2)
	(_find(page, "World_" + slot).find_child("Keep", true, false) as CheckButton).button_pressed = true
	await frames(4)
	var phone := _other_device()
	var added := phone.add_from_cloud(str(CloudService.engine().world_state(slot).ref))
	# Both rename the same room.
	_edit_room(other_root, str(added.slot_id), "name", "The phone's name")
	check(phone.sync(str(added.slot_id)).ok, "the other device syncs first")
	main.flush_all()
	_edit_room(SaveManager.root, slot, "name", "The PC's name")
	SaveManager.forget_baselines_under(SaveManager.root.path_join("slots").path_join(slot))
	main.reload_world_from_disk()
	await frames(2)
	var worlds_before := Slots.ids().size()
	(_find(page, "World_" + slot).find_child("SyncNow", true, false) as Button).pressed.emit()
	await frames(6)
	var question := _find(page, "Question_" + slot)
	check(question != null, "the page asks")
	check(_texts(page).contains("Nothing has been changed yet"), "and says nothing was changed")
	check(_texts(page).contains("the place \"The PC's name\""), "naming the place in question as the player knows it")
	eq(JsonUtil.read_json(SaveManager.root.path_join("slots/%s/rooms/home.json" % slot), {}).get("name"), "The PC's name", "this device's version is untouched")
	for answer in ["KeepBoth", "UseThisDevice", "UseCloud"]:
		check(_find(page, answer) != null, "an answer: " + answer)
	(_find(page, "KeepBoth") as Button).pressed.emit()
	await frames(6)
	check(_find(page, "Question_" + slot) == null, "answered: the question is gone")
	eq(Slots.ids().size(), worlds_before + 1, "the other version is a second world now")
	eq(JsonUtil.read_json(SaveManager.root.path_join("slots/%s/rooms/home.json" % slot), {}).get("name"), "The PC's name", "this world keeps this device's version")
	var names := Slots.list().map(func(card): return str(card.name))
	check(names.any(func(n): return n.contains("(from Android phone)")), "the second world says where it came from: " + str(names))
	check(str((_find(page, "CloudMessage") as Label).text).contains("second world"), "and the page says what happened")
	await _shutdown()


func test_worlds_in_the_cloud_and_the_sync_at_the_title() -> void:
	await _boot()
	var slot := SaveManager.slot_id
	# Another device already put a different world in the folder.
	JsonUtil.ensure_dir(cloud_dir)
	var phone := _other_device()
	var theirs := other_root.path_join("slots/beach")
	JsonUtil.write_json(theirs.path_join("slot.json"), {"version": 1, "name": "Beach House", "emoji": "🌊"})
	JsonUtil.write_json(theirs.path_join("world.json"), {"version": 1, "name": "Beach House", "player": {"name": "Robin"}, "start_room": "home"})
	JsonUtil.write_json(theirs.path_join("rooms/home.json"), {"id": "home", "name": "Shore", "tiles": []})
	check(phone.enable("beach").ok and phone.sync("beach").ok, "the other device has a world in the cloud")
	var page := await _open_page()
	page._use_folder(cloud_dir)
	await frames(2)
	var found := _find(page, "CloudOnlyCard")
	check(found != null and _texts(page).contains("Beach House") and _texts(page).contains("Android phone"), "the page lists the world that is only in the cloud, and who put it there")
	(found.find_child("Bring", true, false) as Button).pressed.emit()
	await frames(4)
	check(Slots.exists("beach_house") and str(Slots.meta("beach_house").name) == "Beach House", "Bring it here: it is on this device")
	check(_find(page, "CloudOnlyCard") == null, "and no longer listed as elsewhere")
	eq(str(CloudService.engine().check("beach_house").state), "synced", "linked and in step")
	# The other device changes it; going back to the title syncs by itself.
	JsonUtil.write_json(theirs.path_join("rooms/dock.json"), {"id": "dock", "name": "Dock", "tiles": []})
	check(phone.sync("beach").ok, "the other device adds a place")
	check(CloudService.automatic(), "automatic sync is on by default")
	main.show_title()
	await tree.create_timer(0.9).timeout
	await frames(3)
	check(FileAccess.file_exists(SaveManager.root.path_join("slots/beach_house/rooms/dock.json")), "the title screen's sync brought the new place")
	check(Slots.exists(slot), "and the world that isn't in the cloud is simply left alone")
	# With automatic sync off, the title leaves things alone.
	CloudService.set_automatic(false)
	JsonUtil.write_json(theirs.path_join("rooms/pier.json"), {"id": "pier", "name": "Pier", "tiles": []})
	check(phone.sync("beach").ok, "another place from the other device")
	main.show_title()
	await tree.create_timer(0.9).timeout
	check(not FileAccess.file_exists(SaveManager.root.path_join("slots/beach_house/rooms/pier.json")), "automatic sync off: nothing happens by itself")
	# Closing the window sends changes (send only).
	CloudService.set_automatic(true)
	JsonUtil.write_json(SaveManager.root.path_join("slots/beach_house/rooms/cabin.json"), {"id": "cabin", "name": "Cabin", "tiles": []})
	eq(CloudService.send_changes(main), 0, "a world that also has cloud changes isn't sent blindly (it waits for a full sync)")
	check(CloudService.sync_all(main).combined == 1, "the full sync combines both")
	JsonUtil.write_json(SaveManager.root.path_join("slots/beach_house/rooms/shed.json"), {"id": "shed", "name": "Shed", "tiles": []})
	eq(CloudService.send_changes(main), 1, "a world with only local changes is sent on closing")
	check(phone.sync("beach").ok and FileAccess.file_exists(theirs.path_join("rooms/shed.json")), "and the other device gets it")
	await _shutdown()
