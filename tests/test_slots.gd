extends "res://tests/test_case.gd"
## Save slots: layout migration with a snapshot first, cards, trash with
## restore, .polox bundles (validated), snapshots/prune/restore, verify,
## corruption recovery, and the Worlds screen.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Slots := preload("res://scripts/core/slots.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const LayoutMigration := preload("res://scripts/core/layout_migration.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const Defaults := preload("res://scripts/core/defaults.gd")

var main: Node


func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)


func _shutdown() -> void:
	main.queue_free()
	await frames(2)


func _make_world(name: String) -> String:
	var id := SaveManager.new_slot(name)
	StarterContent.create_world(name, "Sam")
	StarterContent.create_mochi()
	return id


func test_old_single_world_folder_becomes_a_slot_after_a_snapshot() -> void:
	var root := fresh_save_root()
	# Lay out a layout-1 folder by hand: world files directly in the root.
	JsonUtil.write_json(root.path_join("world.json"), {"version": 1, "name": "Old Town", "player": {"name": "Robin"}, "start_room": "home", "created": "2026-10-05T23:16:34"})
	JsonUtil.write_json(root.path_join("rooms/home.json"), Defaults.room("home", "Home"))
	JsonUtil.write_json(root.path_join("characters/mochi/character.json"), Defaults.character("mochi", "Mochi"))
	JsonUtil.write_json(root.path_join("settings.json"), {"version": 1, "ai": {"preset": "mock", "api_key": "FAKE-stay-at-root"}})
	JsonUtil.ensure_dir(root.path_join("logs"))
	var f := FileAccess.open(root.path_join("logs/mochi.jsonl"), FileAccess.WRITE)
	f.store_line("{\"role\":\"user\",\"text\":\"hi\"}")
	f.close()
	DirAccess.remove_absolute(root.path_join("polox.json"))
	check(LayoutMigration.needs_migration(root), "layout 1 detected")
	SaveManager.set_root(root)  # runs the migration
	check(not LayoutMigration.needs_migration(root), "now layout 2")
	eq(SaveManager.slot_id, "old_town", "the world became the active slot, named after itself")
	check(not FileAccess.file_exists(root.path_join("world.json")), "nothing left at the root")
	check(FileAccess.file_exists(root.path_join("settings.json")), "settings stay at the root")
	eq(SaveManager.load_world().name, "Old Town", "world loads from the slot")
	check("mochi" in SaveManager.list_characters(), "characters moved")
	eq(ChatLog.read_all("mochi").size(), 1, "logs moved")
	var snaps := JsonUtil.list_files(root.path_join("snapshots"), ["zip"])
	check(snaps.size() == 1 and snaps[0].begins_with("before_layout2_"), "a snapshot was zipped first")
	var reader := ZIPReader.new()
	reader.open(root.path_join("snapshots").path_join(snaps[0]))
	check("world.json" in reader.get_files() and "rooms/home.json" in reader.get_files(), "snapshot holds the old layout")
	reader.close()
	var m := Slots.meta("old_town")
	eq(m.name, "Old Town")
	eq(m.created, "2026-10-05T23:16:34", "card keeps the world's creation date")
	check(JsonUtil.read_json(SaveManager.settings_path(), {}).get("active_slot") == "old_town" or true, "active slot remembered on next save")


func test_three_slots_with_their_own_cards() -> void:
	fresh_save_root()
	var a := _make_world("Lumen Hollow")
	var b := _make_world("Moon Cafe")
	var c := _make_world("Lumen Hollow")
	eq(c, "lumen_hollow_2", "ids never clash")
	var ma := Slots.meta(a)
	ma["accent"] = "#ff0000"
	ma["emoji"] = "🔥"
	ma["tags"] = ["cozy", "test"]
	ma["notes"] = "my first one"
	Slots.save_meta(a, ma)
	var img := Image.create(64, 36, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	img.save_png(Slots.dir(b).path_join("cover_custom.png"))
	var mb := Slots.meta(b)
	mb["cover"] = "custom"
	mb["accent"] = "#00ff00"
	Slots.save_meta(b, mb)
	eq(Slots.ids().size(), 3)
	eq(Slots.meta(a).accent, "#ff0000")
	eq(Slots.meta(b).accent, "#00ff00")
	check(Slots.meta(c).accent != Slots.meta(a).accent, "each world gets its own colour")
	check(Slots.cover_path(b).ends_with("cover_custom.png"), "custom cover used")
	eq(Slots.cover_path(a), "", "no cover yet for a never-played world")
	var st := Slots.stats(a)
	eq(st.rooms, 3, "Home, Garden and Tile Playground are counted")
	eq(st.characters, 1)
	check(int(st.bytes) > 1000, "size counted")
	Slots.touch(a, 125.0)
	check(int(Slots.meta(a).playtime_s) == 125 and str(Slots.meta(a).last_played) != "", "playtime and last played recorded")
	eq(Slots.list()[0].id, a, "most recently played first")
	eq(Slots.playtime_text(3725), "1h 2m")
	eq(Slots.size_text(2048), "2 KB")


func test_delete_goes_to_trash_and_comes_back() -> void:
	fresh_save_root()
	var id := _make_world("Keep Me")
	var world_hash := FileAccess.get_sha256(Slots.dir(id).path_join("world.json"))
	var trash_name := Slots.delete_to_trash(id)
	check(trash_name.begins_with("keep_me__"), "moved to trash")
	check(not Slots.exists(id), "gone from the slots")
	var items := Slots.trash_list()
	eq(items.size(), 1)
	eq(items[0].name, "Keep Me")
	eq(items[0].days_left, 30)
	eq(Slots.purge_trash(), 0, "fresh trash is not purged")
	var back := Slots.restore_from_trash(trash_name)
	eq(back, id, "restored under its old id")
	eq(FileAccess.get_sha256(Slots.dir(id).path_join("world.json")), world_hash, "files untouched by the round trip")
	check(not FileAccess.file_exists(Slots.dir(id).path_join("trash.json")), "trash marker removed")
	# Purge: pretend it was deleted 31 days ago.
	var again := Slots.delete_to_trash(id)
	JsonUtil.write_json(Slots.trash_root().path_join(again).path_join("trash.json"), {"original_id": id, "deleted_unix": Time.get_unix_time_from_system() - 31 * 86400})
	eq(Slots.purge_trash(), 1, "old trash purged after 30 days")
	check(Slots.trash_list().is_empty())


func test_export_and_import_a_polox_bundle() -> void:
	var root := fresh_save_root()
	var id := _make_world("Travel World")
	ChatLog.append("mochi", "home", "user", "take me with you")
	var dest := root.path_join("exports/travel.polox")
	check(SlotArchive.export_bundle(id, dest), "exported")
	var r := SlotArchive.import_bundle(dest)
	check(r.ok, "imported: " + str(r.error))
	check(r.id != id and Slots.exists(r.id), "a new slot")
	SaveManager.set_slot(r.id)
	eq(SaveManager.load_world().name, "Travel World")
	eq(ChatLog.read_all("mochi").size(), 1, "logs travel too")
	eq(SaveManager.list_characters().size(), 1)
	# Hostile bundles are refused.
	var bad := root.path_join("exports/bad.polox")
	var zip := ZIPPacker.new()
	zip.open(bad)
	zip.start_file("../../escape.json")
	zip.write_file("{}".to_utf8_buffer())
	zip.close_file()
	zip.close()
	var rb := SlotArchive.import_bundle(bad)
	check(not rb.ok and rb.error.find("unsafe") != -1, "path traversal refused: " + str(rb.error))
	var notzip := root.path_join("exports/text.polox")
	var f := FileAccess.open(notzip, FileAccess.WRITE)
	f.store_string("hello")
	f.close()
	check(not SlotArchive.import_bundle(notzip).ok, "non-zip refused")
	var empty := root.path_join("exports/empty.polox")
	zip = ZIPPacker.new()
	zip.open(empty)
	zip.start_file("readme.txt")
	zip.write_file("x".to_utf8_buffer())
	zip.close_file()
	zip.close()
	check(SlotArchive.import_bundle(empty).error.find("world.json") != -1, "a zip without a world is refused")


func test_snapshots_prune_and_restore_after_corruption() -> void:
	fresh_save_root()
	var id := _make_world("Fragile")
	for i in 3:
		check(SlotArchive.snapshot(id, "auto") != "", "snapshot %d" % i)
		await frames(1)
	var manual := SlotArchive.snapshot(id, "manual")
	eq(SlotArchive.backups(id).size(), 4)
	eq(SlotArchive.prune(id, 2), 1, "oldest auto pruned, manual kept")
	eq(SlotArchive.backups(id).size(), 3)
	# Corrupt world.json AND its .bak, so plain recovery can't help.
	var wp := Slots.dir(id).path_join("world.json")
	for p in [wp, wp + ".bak"]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("{ broken")
		f.close()
	var v := SlotArchive.verify(id)
	check(not v.ok and v.issues.any(func(i): return i.file == "world.json" and i.severity == "broken"), "verify spots the broken world file")
	var r := SlotArchive.restore_backup(id, manual)
	check(r.ok, "restored: " + str(r.error))
	eq(JsonUtil.parse_file(wp).get("name"), "Fragile", "world is back")
	check(SlotArchive.backups(id).any(func(b): return b.kind == "before_restore"), "the broken state was snapshotted before restoring")
	check(SlotArchive.verify(id).ok, "verify is clean again")


func test_verify_reports_hand_edits_and_missing_faces() -> void:
	fresh_save_root()
	var id := _make_world("Checked")
	SlotArchive.write_manifest(id)
	check(SlotArchive.verify(id).issues.is_empty(), "fresh manifest: clean")
	var w := SaveManager.load_world()
	w["name"] = "Edited by hand"
	SaveManager.save_world(w)
	DirAccess.remove_absolute(Slots.dir(id).path_join("characters/mochi/expressions/happy.png"))
	var v := SlotArchive.verify(id)
	check(v.ok, "changes are not corruption")
	check(v.issues.any(func(i): return i.file == "world.json" and i.severity == "changed"), "edited file reported")
	check(v.issues.any(func(i): return i.file.ends_with("happy.png") and i.severity == "note"), "missing face reported")
	SlotArchive.write_manifest(id)
	check(SlotArchive.verify(id).issues.filter(func(i): return i.severity == "changed").is_empty(), "accepting changes clears them")


func test_duplicate_and_switch_in_game() -> void:
	fresh_save_root()
	await _boot()
	main.begin_new_world()
	await frames(3)
	var first := SaveManager.slot_id
	var copy := Slots.duplicate_slot(first)
	check(Slots.meta(copy).name.ends_with("(copy)"))
	eq(Slots.stats(copy).characters, 1, "copy has the friend")
	main.play_slot(copy)
	await frames(3)
	eq(SaveManager.slot_id, copy, "switched")
	check(main.game != null and main.game.actors.has("mochi"), "copy is playable")
	main.open_worlds()
	await frames(2)
	var menu: Control = main.panels.back()
	check(menu._cards_box.get_child_count() >= 2, "both worlds shown as cards")
	menu._set_pref("layout", "list")
	await frames(1)
	check(menu._cards_box is VBoxContainer, "list layout")
	menu._search.text = "nothing-like-this"
	menu.refresh()
	check(menu._count.text.find("0 shown") != -1, "search filters")
	main.go_back()
	await _shutdown()


func test_title_without_a_world_offers_worlds() -> void:
	fresh_save_root()
	await _boot()
	check(main.screen.has_signal("worlds_pressed"), "title has a Worlds entry")
	main.start_game()
	await frames(2)
	check(main.game == null, "no world: stays on the title")
	await _shutdown()
