extends "res://tests/test_case.gd"
## Failure injection uses disposable roots only; no real home, keys or network.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeEdit := preload("res://scripts/home/home_edit.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const Starter := preload("res://scripts/core/starter_content.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const Items := preload("res://scripts/items/items.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const Pairing := preload("res://scripts/phone/pairing.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const HttpUtil := preload("res://scripts/phone/http_util.gd")

class DelayedClient extends "res://scripts/phone/sync_client.gd":
	var response: Dictionary = {}
	var during_get: Callable
	func request(_method: String, _path: String, _body: PackedByteArray = PackedByteArray()) -> Dictionary:
		await get_tree().process_frame
		if during_get.is_valid():
			during_get.call()
			during_get = Callable()
		return response


func _world() -> void:
	fresh_save_root()
	Starter.create_world("Storage test", "Sam")
	GameState.load_world()


func _item(id: String, realm: String = "shared") -> void:
	var item := Items.defaults("armor", "head")
	item.id = id
	item.name = id
	item.realm = realm
	item.effect = {"type": "aura", "value": "#55cc88"}
	Items.save_item(item)
	Inventory.add(id, 1)


func test_failed_byte_replacement_preserves_original_and_reports_failure() -> void:
	var root := fresh_save_root()
	var file := root.path_join("file.json")
	check(JsonUtil.write_json(file, {"value": "old"}))
	JsonUtil.ensure_dir(file + ".tmp")
	check(not SyncFiles.write_atomic(file, '{"value":"new"}'.to_utf8_buffer()), "an unwritable stage is rejected")
	eq(JsonUtil.read_json(file, {}).value, "old", "old file is intact")
	DirAccess.remove_absolute(file + ".tmp")
	check(SyncFiles.write_atomic(file, '{"value":"new"}'.to_utf8_buffer()))
	eq(JsonUtil.read_json(file, {}).value, "new")
	check(JsonUtil.remove_file(file))
	eq(JsonUtil.read_json(file, {}), {}, "intentional deletion does not recover an old .bak")


func test_pairing_failure_keeps_pin_and_existing_devices() -> void:
	var root := fresh_save_root()
	var pairing := Pairing.new(root)
	var code := pairing.new_code()
	var first: Dictionary = pairing.pair(code, "First", "127.0.0.1", "", "first")
	check(first.ok)
	code = pairing.code
	JsonUtil.ensure_dir(pairing.devices_path() + ".tmp")
	var failed: Dictionary = pairing.pair(code, "Second", "127.0.0.1", "", "second")
	check(not failed.ok and int(failed.status) == 507, "failure identifies PC storage")
	eq(pairing.code, code, "same PIN remains usable")
	eq(pairing.devices().size(), 1, "previous pairing is retained")
	check(not pairing.check_token(str(first.token)).is_empty())


func test_home_batch_rolls_back_failed_commit_and_recovers_after_interruption() -> void:
	fresh_save_root()
	var old := {"home.json": {"tag": "old"}, "places/lw_floor_0.json": {"id": "lw_floor_0", "tag": "old"}, "osm.json": {"tag": "old"}}
	check(HomeStore.apply_batch(old))
	JsonUtil.ensure_dir(HomeStore.path("places/lw_floor_0.json.tmp"))
	var next := {"home.json": {"tag": "new"}, "places/lw_floor_0.json": {"id": "lw_floor_0", "tag": "new"}, "osm.json": {"tag": "new"}}
	check(not HomeStore.apply_batch(next), "failed second file aborts the whole batch")
	eq(HomeStore.load_home().tag, "old", "model rollback")
	eq(JsonUtil.read_json(HomeStore.path("osm.json"), {}).tag, "old", "map rollback")
	DirAccess.remove_absolute(HomeStore.path("places/lw_floor_0.json.tmp"))
	var tx := HomeStore.path(".transaction")
	JsonUtil.write_json(tx.path_join("old/home.json"), {"tag": "old"})
	JsonUtil.write_json(tx.path_join("journal.json"), {"version": 1, "state": "prepared", "original": {"home.json": true, "places/lw_new.json": false}})
	JsonUtil.write_json(HomeStore.path("home.json"), {"tag": "partial"})
	JsonUtil.write_json(HomeStore.path("places/lw_new.json"), {"id": "lw_new"})
	eq(HomeStore.load_home().tag, "old", "next read rolls back interrupted commit")
	check(not FileAccess.file_exists(HomeStore.path("places/lw_new.json")))
	check(not DirAccess.dir_exists_absolute(tx))


func test_restore_validates_before_deleting_and_restores_map_together() -> void:
	var root := fresh_save_root()
	check(HomeStore.apply_batch({"home.json": {"tag": "one"}, "osm.json": {"tag": "one"}, "places/lw_floor_0.json": {"id": "lw_floor_0", "tag": "one"}}))
	var snapshot := HomeStore.snapshot("test")
	check(snapshot != "")
	check(HomeStore.apply_batch({"home.json": {"tag": "two"}, "osm.json": {"tag": "two"}, "places/lw_floor_0.json": {"id": "lw_floor_0", "tag": "two"}}))
	var zip := ZIPPacker.new()
	var unsafe := root.path_join("unsafe.zip")
	eq(zip.open(unsafe), OK)
	zip.start_file("../escaped.json")
	zip.write_file("{}".to_utf8_buffer())
	zip.close_file()
	zip.close()
	check(not HomeStore.restore(unsafe))
	eq(HomeStore.load_home().tag, "two", "invalid archive never touches live state")
	check(FileAccess.file_exists(HomeStore.path("places/lw_floor_0.json")))
	check(not FileAccess.file_exists(root.path_join("escaped.json")))
	check(HomeStore.restore(snapshot))
	eq(HomeStore.load_home().tag, "one")
	eq(JsonUtil.read_json(HomeStore.path("osm.json"), {}).tag, "one")


func test_stale_editor_does_not_resurrect_a_remote_deletion() -> void:
	_world()
	var room := SaveManager.load_room("home")
	var file := SaveManager.room_path("home")
	check(JsonUtil.remove_file(file), "simulate remote deletion without clearing this editor's baseline")
	room.name = "Unsaved local work"
	check(not SaveManager.save_room(room), "the stale editor is refused")
	check(not FileAccess.file_exists(file), "deleted room stays deleted")
	var copies := DirAccess.get_files_at(SaveManager.global_path("conflicts/local_save"))
	check(not copies.is_empty(), "local work is retained in a conflict copy")
	SaveManager.forget_baselines(file)
	check(SaveManager.save_room(room), "an explicit new save after forgetting the deleted baseline is allowed")


func test_stale_editor_and_focus_flush_merge_remote_fields_without_losing_local_edits() -> void:
	_world()
	var room := SaveManager.load_room("home")
	var old_name := str(room.name)
	var remote := room.duplicate(true)
	remote.name = "From phone"
	JsonUtil.write_json(SaveManager.room_path("home"), remote)
	# An inspector may read the new file before the original editor saves.
	SaveManager.load_room("home")
	room.floor.color = "#112233"
	check(SaveManager.save_room(room))
	eq(room.name, "From phone", "caller adopts remote nonconflicting field")
	eq(SaveManager.load_room("home").floor.color, "#112233", "local editor field retained")
	var player := GameState.world.duplicate(true)
	var remote_world := player.duplicate(true)
	remote_world.name = "Remote world"
	JsonUtil.write_json(SaveManager.world_path(), remote_world)
	player.name = old_name + " local conflict"
	check(SaveManager.save_world(player))
	eq(player.name, "Remote world", "incoming authoritative conflict value retained")
	check(not DirAccess.get_files_at(SaveManager.global_path("conflicts/local_save")).is_empty(), "local original preserved")


## Regression (found in the Update 9 review): a deleted room kept its write baseline, so saving a new
## room with that id was refused as a "conflict" (the Light World entry was never made again and the
## game fell into the Survey); and its .bak brought the deleted room back on the next read.
func test_deleted_room_stays_deleted_and_its_id_saves_again() -> void:
	_world()
	var room := Defaults.room("lw_again", "Again")
	check(SaveManager.save_room(room))
	room.name = "Again, twice"
	check(SaveManager.save_room(room), "a second save leaves a .bak behind")
	SaveManager.load_room("lw_again")
	SaveManager.delete_room("lw_again")
	check(not SaveManager.room_exists("lw_again"))
	eq(str(SaveManager.load_room("lw_again").name), "Lw Again", "nothing resurrected from the old .bak")
	check(not SaveManager.room_exists("lw_again"), "reading it did not write it back")
	var fresh := Defaults.room("lw_again", "New")
	check(SaveManager.save_room(fresh), "a new room with the same id saves")
	eq(str(SaveManager.load_room("lw_again").name), "New")
	check(not DirAccess.dir_exists_absolute(SaveManager.global_path("conflicts/local_save")), "no conflict copy")


## Regression: a home change this game made itself (Tell Polox's Keep, a mapping) is not a sync; a room
## edit made afterwards must save as it is, not be "merged" against the older version and lost.
func test_in_process_home_change_is_not_a_sync_conflict() -> void:
	_world()
	var v1 := Defaults.room("lw_floor_0", "Ground floor")
	v1.floor.color = "#111111"
	check(HomeStore.apply_batch({"places/lw_floor_0.json": v1}))
	var editor_copy := SaveManager.load_room("lw_floor_0")   # baseline v1
	var v2 := v1.duplicate(true)
	v2.floor.color = "#222222"
	check(HomeStore.apply_batch({"places/lw_floor_0.json": v2}), "Keep writes v2 in this process")
	editor_copy = SaveManager.load_room("lw_floor_0")      # the room reloads after Keep
	eq(str(editor_copy.floor.color), "#222222")
	editor_copy.floor.color = "#333333"
	check(SaveManager.save_room(editor_copy))
	eq(str(SaveManager.load_room("lw_floor_0").floor.color), "#333333", "the later edit is kept")
	check(not DirAccess.dir_exists_absolute(SaveManager.global_path("conflicts/local_save")), "not treated as a conflict")


func test_realm_forms_and_independent_outfits_survive_reload_and_bound_gear_is_filtered() -> void:
	_world()
	eq(PlayerLook.current(), "dark", "starter world is Dream World")
	check(not PlayerLook.set_form("real"), "direct setter cannot bypass realm")
	_item("shared_hat")
	_item("light_hat", "light")
	_item("dark_hat", "dark")
	# Legacy loadout remains available in both realms without duplicating inventory.
	GameState.inventory = {"version": 1, "stacks": GameState.inventory.stacks.duplicate(true), "equipped": {"head": "shared_hat"}}
	Inventory.normalize()
	eq(Inventory.equipped("light").head, "shared_hat")
	eq(Inventory.equipped("dark").head, "shared_hat")
	eq(Inventory.equip("light_hat", "light"), "head")
	eq(Inventory.equip("dark_hat", "dark"), "head")
	eq(Inventory.equip("dark_hat", "light"), "", "explicit binding enforced in data layer")
	eq(Inventory.count("shared_hat"), 1, "neutral item remains owned")
	var light := Defaults.room("lw_test", "Test home")
	light.player_form = "dark" # malicious/obsolete override
	SaveManager.save_room(light)
	GameState.current_room_id = "lw_test"
	GameState.world.last_room = "lw_test"
	PlayerLook.apply_room(light)
	GameState.save_world()
	eq(PlayerLook.current(), "real")
	eq(Inventory.equipped().head, "light_hat")
	GameState.load_world(true)
	eq(PlayerLook.current(), "real", "sync/restart derives realm before rendering")
	eq(Inventory.equipped().head, "light_hat")
	GameState.current_room_id = "home"
	PlayerLook.apply_room(SaveManager.load_room("home"))
	eq(PlayerLook.current(), "dark")
	eq(Inventory.equipped().head, "dark_hat")
	check(Inventory.remove("shared_hat"))
	eq(Inventory.count("shared_hat"), 0)


func test_consumption_uses_disk_and_rolls_back_failed_writes() -> void:
	_world()
	_item("snack")
	var old := GameState.inventory.duplicate(true)
	JsonUtil.ensure_dir(SaveManager.abs_path("inventory.json.tmp"))
	check(not Inventory.remove("snack"), "failed save cannot consume")
	eq(Inventory.count("snack"), 1)
	DirAccess.remove_absolute(SaveManager.abs_path("inventory.json.tmp"))
	var remote := SaveManager.load_inventory()
	remote.stacks = []
	JsonUtil.write_json(SaveManager.abs_path("inventory.json"), remote)
	GameState.inventory = old
	check(not Inventory.consume("snack"), "stale queue cannot consume a remotely spent item")
	eq(Inventory.count("snack"), 0)


func test_delayed_pull_and_remote_delete_preserve_new_local_edits() -> void:
	var root := fresh_save_root()
	var rel := "slots/a/world.json"
	var full := root.path_join(rel)
	JsonUtil.write_json(full, {"value": "base"})
	var original := SyncFiles.sha_of(full)
	var client := DelayedClient.new()
	client.local_root = root
	tree.root.add_child(client)
	client.response = {"ok": true, "code": 200, "body": '{"value":"remote"}'.to_utf8_buffer(), "json": {}, "error": ""}
	client.during_get = func(): JsonUtil.write_json(full, {"value": "local during GET"})
	var base := {rel: original}
	var result := {"pulled": [], "deferred": []}
	var remote := {rel: {"sha256": HttpUtil.sha256_bytes(client.response.body)}}
	var local := {rel: {"sha256": original}}
	eq(await client._pull_files([rel], base, result, remote, local), {})
	eq(JsonUtil.read_json(full, {}).value, "local during GET")
	eq(base[rel], original, "base remains available for the next merge")
	eq(result.deferred, [rel])
	original = SyncFiles.sha_of(full)
	client.response = {"ok": false, "code": 404, "body": PackedByteArray(), "json": {}, "error": "gone"}
	client.during_get = func(): JsonUtil.write_json(full, {"value": "local during delete"})
	eq(await client._pull_files([rel], base, result, {}, {rel: {"sha256": original}}), {})
	eq(JsonUtil.read_json(full, {}).value, "local during delete")
	client.queue_free()
	await frames(1)


func test_partial_sync_commit_notifies_even_on_failure() -> void:
	fresh_save_root()
	var client := DelayedClient.new()
	var notices := []
	client.on_pulled = func(slots, paths): notices.append({"slots": slots, "paths": paths})
	client._notify_committed({"ok": false, "pulled": ["slots/test/world.json"], "local_deleted": [], "error": "offline"})
	eq(notices.size(), 1)
	eq(notices[0].paths, ["slots/test/world.json"])
	client.free()
