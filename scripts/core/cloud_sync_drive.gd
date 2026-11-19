extends RefCounted
## [CLOUD_SYNC] Scripted scenarios that put Settings > Cloud sync on screen for a look (debug_drives.gd
## runs them for --drive=cloud_sync, cloud_sync_empty and cloud_sync_conflict; never in play). The
## cloud folder is a scratch folder beside the scratch save folder, and the "other device" is an
## engine on a third scratch folder, so nothing real is touched.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const CloudService := preload("res://scripts/sync/cloud_service.gd")
const CloudSync := preload("res://scripts/sync/cloud_sync.gd")
const CloudStore := preload("res://scripts/sync/cloud_store.gd")

var main: Node


func run(main_node: Node, scenario: String) -> void:
	main = main_node
	main.begin_new_world()
	await _wait(0.6)
	var slot := SaveManager.slot_id
	var cloud_dir := SaveManager.root + "_cloud"
	var other_root := SaveManager.root + "_other_device"
	JsonUtil.remove_tree(cloud_dir)
	JsonUtil.remove_tree(other_root)
	GameState.settings.erase("cloud")
	if scenario != "cloud_sync_empty":
		JsonUtil.ensure_dir(cloud_dir)
		CloudService.set_folder(cloud_dir)
		var engine := CloudService.engine()
		engine.enable(slot)
		print("[drive] cloud: first sync ", engine.sync(slot).action)
		var phone := CloudSync.new(other_root, CloudStore.FolderStore.new(cloud_dir), "Android phone")
		var added := phone.add_from_cloud(str(engine.world_state(slot).ref))
		# A second world that is only in the cloud so far.
		var beach := other_root.path_join("slots/beach")
		JsonUtil.write_json(beach.path_join("slot.json"), {"version": 1, "name": "Beach House", "emoji": "🌊"})
		JsonUtil.write_json(beach.path_join("world.json"), {"version": 1, "name": "Beach House", "player": {"name": "Robin"}, "start_room": "home"})
		JsonUtil.write_json(beach.path_join("rooms/home.json"), {"id": "home", "name": "Shore", "tiles": []})
		phone.enable("beach")
		phone.sync("beach")
		if scenario == "cloud_sync_conflict":
			_rename_home(other_root, str(added.slot_id), "The phone's name")
			phone.sync(str(added.slot_id))
			main.flush_all()
			_rename_home(SaveManager.root, slot, "The PC's name")
			SaveManager.forget_baselines_under(SaveManager.root.path_join("slots").path_join(slot))
			main.reload_world_from_disk()
			await _wait(0.3)
	var settings: Control = SettingsScreen.new()
	settings.main = main
	settings.start_on = "Cloud sync"
	main.open_panel(settings)
	await _wait(0.6)
	var page: Control = settings.tabs.get_tab_control(settings.tabs.current_tab)
	if scenario == "cloud_sync_conflict":
		(page.find_child("World_" + slot, true, false).find_child("SyncNow", true, false) as Button).pressed.emit()
		await _wait(0.8)
		print("[drive] cloud: question shown = ", page.find_child("Question_" + slot, true, false) != null)
	for arg in OS.get_cmdline_user_args():
		if arg == "--cloud-scroll-end":
			(page as ScrollContainer).scroll_vertical = int((page as ScrollContainer).get_v_scroll_bar().max_value)
	print("[drive] cloud: page = ", settings.tabs.get_tab_title(settings.tabs.current_tab))


func _rename_home(root: String, slot: String, name: String) -> void:
	var path := root.path_join("slots/%s/rooms/home.json" % slot)
	var room: Dictionary = JsonUtil.read_json(path, {})
	room["name"] = name
	JsonUtil.write_json(path, room)


func _wait(seconds: float) -> void:
	await main.get_tree().create_timer(seconds).timeout
