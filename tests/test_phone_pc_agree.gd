extends "res://tests/test_case.gd"
## Phase 39, the phone and the PC agree: a JSON file both sides changed merges field by field (only a value both
## changed differently keeps the PC's, and then the phone's whole file is kept in conflicts/ too); your Light
## World reaches a paired phone (the house, the streets) without your address, survey answers or journal, and
## not at all when you turn it off; a paired phone never starts a second Survey; a home place that isn't there
## (the phone's old placeholder room) leads to your home's entry, not the Dream World; pairing again replaces
## the same phone instead of filling the list; a full list makes room by dropping that phone's stale entries.

const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const SyncClient := preload("res://scripts/phone/sync_client.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const JsonMerge := preload("res://scripts/sync/json_merge.gd")
const Pairing := preload("res://scripts/phone/pairing.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const Realms := preload("res://scripts/world/realms.gd")

const ADDRESS := "12 Example Lane, Testville"

var server: Node
var port := 0
var pc_root := ""


func _answers() -> Dictionary:
	return {"address": ADDRESS, "home_type": "house", "floors": 2, "basement": false,
		"rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1}, "memory": "Pancakes every Sunday",
		"my_room": {"floor": 1, "where": "front", "bed": "single", "desk": true}, "radius": 250}


func _start() -> void:
	pc_root = fresh_save_root()
	StarterContent.create_world("PC World", "Sam")
	StarterContent.create_mochi()
	GameState.load_world()
	GameState.settings["light_world"] = {}
	AIClient.configure({"preset": "mock"})
	var web := pc_root.path_join("_web")
	JsonUtil.ensure_dir(web)
	server = PhoneServer.new()
	tree.root.add_child(server)
	server.setup(pc_root, web)
	listen_on_free_port(func(p: int) -> String: return server.start_on_safe_port(p, "127.0.0.1"), "Phone Link")
	port = server.port


func _stop() -> void:
	server.stop()
	server.queue_free()
	SyncFiles.home_shared = false
	await frames(1)


func _phone(client_id: String = "") -> Node:
	var c := SyncClient.new()
	tree.root.add_child(c)
	c.base_url = "http://127.0.0.1:%d" % port
	c.local_root = pc_root.path_join("_phone")
	JsonUtil.ensure_dir(c.local_root)
	var r: Dictionary = await c.pair(server.pairing.new_code(), "Test phone", client_id)
	check(bool(r.ok), "paired: %s" % str(r.get("error", "")))
	return c


func test_merging_field_by_field() -> void:
	var base := {"last_room": "lw_floor_0", "variety": {"last_seen": 100.0, "almanac": {"chats": 7.0}}, "gifts": [{"id": "a", "n": 1}]}
	var pc := {"last_room": "lw_floor_0", "variety": {"last_seen": 150.0, "almanac": {"chats": 8.0}}, "gifts": [{"id": "a", "n": 2}]}
	var phone := {"last_room": "garden", "variety": {"last_seen": 140.0, "almanac": {"chats": 9.0}}, "gifts": [{"id": "a", "n": 1}, {"id": "b", "n": 1}]}
	var r := JsonMerge.merge3(base, pc, phone)
	eq(str(r.merged.last_room), "garden", "the phone's change")
	eq(float(r.merged.variety.last_seen), 150.0, "the later time")
	eq(float(r.merged.variety.almanac.chats), 10.0, "both sides' counts added")
	eq((r.merged.gifts as Array).size(), 2, "lists by id: the phone's new one")
	eq(int(r.merged.gifts[0].n), 2, "and the PC's change to the old one")
	eq((r.conflicts as Array).size(), 0, "nothing really conflicting")
	r = JsonMerge.merge3({"name": "A"}, {"name": "B"}, {"name": "C"})
	eq(str(r.merged.name), "B", "a value both changed: the PC's")
	eq(r.conflicts, ["/name"], "reported")
	r = JsonMerge.merge3({"tags": ["x", "y"]}, {"tags": ["x", "y", "pc"]}, {"tags": ["y", "phone"]})
	eq(r.merged.tags, ["y", "pc", "phone"], "plain lists as sets")


func test_both_sides_changed_merges_on_the_pc() -> void:
	_start()
	var phone := await _phone()
	var slot := SaveManager.slot_id
	var first: Dictionary = await phone.sync()
	check(first.ok, "first sync")
	var rel := "slots/%s/world.json" % slot
	# The PC notes the time (as it does every few seconds); the phone renames the player.
	var w: Dictionary = JsonUtil.read_json(pc_root.path_join(rel), {})
	w["variety"] = w.get("variety", {})
	w.variety["last_seen"] = 2000000000.0
	JsonUtil.write_json(pc_root.path_join(rel), w)
	var pw: Dictionary = JsonUtil.read_json(phone.local_root.path_join(rel), {})
	pw["player"]["nicknames"] = "Sammy"
	JsonUtil.write_json(phone.local_root.path_join(rel), pw)
	var r: Dictionary = await phone.sync()
	check(rel in r.merged, "merged, not set aside: %s" % str(r))
	eq(int(r.conflicts), 0, "no conflict")
	for root in [pc_root, phone.local_root]:
		var got: Dictionary = JsonUtil.read_json(root.path_join(rel), {})
		eq(str(got.player.nicknames), "Sammy", "the phone's change is kept (%s)" % root.get_file())
		eq(float(got.variety.last_seen), 2000000000.0, "and the PC's (%s)" % root.get_file())
	eq(SyncFiles.conflicts(pc_root, slot).size(), 0, "nothing in conflicts/")
	# A value both changed differently: the PC's stays, the phone's whole file is kept, the phone says so.
	w = JsonUtil.read_json(pc_root.path_join(rel), {})
	w["player"]["nicknames"] = "PC name"
	JsonUtil.write_json(pc_root.path_join(rel), w)
	pw = JsonUtil.read_json(phone.local_root.path_join(rel), {})
	pw["player"]["nicknames"] = "Phone name"
	pw["player"]["about"] = "written on the phone"
	JsonUtil.write_json(phone.local_root.path_join(rel), pw)
	r = await phone.sync()
	eq(int(r.conflicts), 1, "one real conflict")
	check(rel in r.merged, "independent fields in a conflicting file notify the running PC")
	var pc_w: Dictionary = JsonUtil.read_json(pc_root.path_join(rel), {})
	eq(str(pc_w.player.nicknames), "PC name", "the PC's value stays")
	eq(str(pc_w.player.about), "written on the phone", "the phone's other change still came through")
	eq(str(JsonUtil.read_json(phone.local_root.path_join(rel), {}).player.nicknames), "PC name", "and the phone has the result")
	eq(SyncFiles.conflicts(pc_root, slot).size(), 1, "the phone's whole file is kept")
	var again: Dictionary = await phone.sync()
	eq(again.pushed.size() + again.pulled.size() + again.merged.size(), 0, "in sync afterwards")
	phone.queue_free()
	await _stop()


func test_positions_and_large_timestamps_are_not_treated_as_sets_or_rounded() -> void:
	var r := JsonMerge.merge3({"spawn": [1, 2], "last_seen": 2000000000.0},
		{"spawn": [3, 2], "last_seen": 2000000010.0}, {"spawn": [1, 4], "last_seen": 2000000020.0})
	eq(r.merged.spawn, [3, 2], "a conflicting position stays a valid coordinate pair")
	eq(r.conflicts, ["/spawn"], "the phone's position is reported as a conflict")
	check(float(r.merged.last_seen) == 2000000020.0, "seconds at modern epoch times stay distinct")
	r = JsonMerge.merge3({"stats": {"hp": 20}}, {"stats": {"hp": 15}}, {"stats": {"hp": 12}})
	eq(r.merged.stats.hp, 15, "health is not an additive activity counter")
	eq(r.conflicts, ["/stats/hp"], "different health changes are a real conflict")


func test_your_home_reaches_the_phone_without_your_address() -> void:
	_start()
	var fixture := ProjectSettings.globalize_path("res://tests/fixtures/home_research_madeup.json")
	HomeMapper.build_home(_answers(), HomeModel.clean_research(JSON.parse_string(FileAccess.get_file_as_string(fixture))), "claude_code")
	JournalWrite.write(HomeStore.path("journal.json"))
	check(not FileAccess.get_file_as_string(HomeStore.path("home.json")).contains(ADDRESS), "home.json holds no address")
	check(not FileAccess.get_file_as_string(HomeStore.path("home.json")).contains("Pancakes"), "nor your answers")
	eq(str(HomeStore.load_home().get("address", {}).get("text", "")), ADDRESS, "the PC still knows it (private.json)")
	var shared_home: Dictionary = JsonUtil.read_json(HomeStore.path("home.json"), {})
	var rebuilt: Dictionary = load("res://scripts/home/home_edit.gd").rebuild(shared_home)
	eq(rebuilt, shared_home.plan, "the phone rebuilds the same home without private Survey answers")
	var phone := await _phone()
	JsonUtil.write_json(phone.local_root.path_join("my_home/places/lw_my_room.json"), LightHome.placeholder())
	var r: Dictionary = await phone.sync()
	check(r.ok, "synced")
	check(not FileAccess.file_exists(pc_root.path_join("my_home/places/lw_my_room.json")), "an old phone's placeholder never goes back to the PC")
	check(not FileAccess.file_exists(phone.local_root.path_join("my_home/places/lw_my_room.json")), "the mapped house replaces the phone's placeholder")
	eq(phone.home_state, "shared", "the PC shares the home")
	var ph: String = phone.local_root.path_join("my_home")
	check(FileAccess.file_exists(ph.path_join("home.json")), "the phone has the house")
	check(not Array(DirAccess.get_files_at(ph.path_join("places"))).filter(func(f): return str(f).begins_with("lw_floor_")).is_empty(), "and its floors")
	for f in ["private.json", "journal.json"]:
		check(not FileAccess.file_exists(ph.path_join(f)), "never %s" % f)
	var everything := ""
	for f in DirAccess.get_files_at(ph):
		everything += FileAccess.get_file_as_string(ph.path_join(f))
	check(not everything.contains(ADDRESS) and not everything.contains("Pancakes"), "no address or answers anywhere on the phone")
	# Use the real home editor against the phone's save, then send its changes back.
	var phone_home: Dictionary = JsonUtil.read_json(ph.path_join("home.json"), {})
	var room_id := ""
	for floor in phone_home.plan.floors:
		for room in floor.rooms:
			if bool(room.get("mine", false)):
				room_id = str(room.id)
	var floor_count: int = phone_home.plan.floors.size()
	SaveManager.set_root(phone.local_root)
	var edit: Dictionary = load("res://scripts/home/home_edit.gd").commit([{"type": "wall", "level": 1, "room": room_id, "color": "#e8bfc4"}], "room")
	check(not edit.is_empty(), "a real phone home edit is kept")
	eq(HomeStore.load_home().plan.floors.size(), floor_count, "editing without the Survey preserves every floor")
	SaveManager.set_root(pc_root)
	r = await phone.sync()
	check(r.ok, "the phone's home edit synced")
	check((HomeStore.load_home().edits as Array).any(func(e): return str(e.get("color", "")) == "#e8bfc4"), "the PC keeps the phone's actual edit")
	# A room edited on the phone comes back to the PC.
	var floor_file := ""
	for f in DirAccess.get_files_at(ph.path_join("places")):
		if str(f).begins_with("lw_floor_1") and str(f).ends_with(".json"):
			floor_file = "my_home/places/" + str(f)
	var pf: Dictionary = JsonUtil.read_json(phone.local_root.path_join(floor_file), {})
	pf["name"] = "Upstairs (edited on the phone)"
	JsonUtil.write_json(phone.local_root.path_join(floor_file), pf)
	r = await phone.sync()
	check(floor_file in r.pushed, "the phone's edit goes to the PC")
	eq(str(JsonUtil.read_json(pc_root.path_join(floor_file), {}).name), "Upstairs (edited on the phone)", "and is there")
	eq(str(HomeStore.load_home().get("address", {}).get("text", "")), ADDRESS, "the address is untouched")
	# Turned off: nothing of the home is listed any more.
	GameState.settings["light_world"] = {"on_phone": false}
	var denied: Dictionary = await phone.request("GET", "/api/file?path=my_home%2Fhome.json")
	eq(int(denied.code), 403, "turning sharing off takes effect before the next manifest")
	r = await phone.sync()
	eq(phone.home_state, "private", "the PC keeps it to itself")
	var m: Dictionary = await phone.request("GET", "/api/manifest")
	check(not (m.json.get("files", {}) as Dictionary).keys().any(func(p): return str(p).begins_with("my_home")), "not listed")
	GameState.settings["light_world"] = {}
	phone.queue_free()
	await _stop()


class JournalWrite:
	static func write(path: String) -> void:
		JsonUtil.write_json(path, {"version": 1, "entries": [{"text": "a private day", "when": "2026-10-21"}]})


func test_a_paired_phone_uses_an_existing_shared_home_without_a_second_survey() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	GameState.settings["reduce_motion"] = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var fake := FakePhone.new()
	main.add_child(fake)
	main.phone = fake
	var g: Node = main.game
	await g.dark.go_light()
	await frames(3)
	check(fake.synced, "it asked the PC for the home first")
	var survey: Array = main.toast_layer().find_children("*", "Control", true, false).filter(func(n): return n.get_script() == load("res://scripts/home/survey_screen.gd"))
	check(survey.is_empty(), "no duplicate Survey for a house supplied by the PC")
	check(GameState.current_room_id.begins_with("lw_floor_"), "arrives in the shared mapped house (%s)" % GameState.current_room_id)
	main.phone = null
	main.queue_free()
	await frames(2)


class FakePhone extends Node:
	var synced := false
	var client := FakeClient.new()

	func paired() -> bool:
		return true

	func sync_now() -> Dictionary:
		synced = true
		await get_tree().process_frame
		HomeMapper.build_home({"home_type": "house", "floors": 1}, {}, "")
		return {"ok": true}

	func on_lifecycle(_resumed: bool) -> void:
		pass


class FakeClient:
	var home_state := "none"


func test_a_queued_push_waits_for_an_existing_sync() -> void:
	var mode: Node = load("res://scripts/phone/phone_mode.gd").new()
	var client := DeferredSync.new()
	mode.client = client
	mode._push_in = 0.01
	mode._process(0.02)
	eq(client.calls, 0, "the existing sync is left to finish")
	check(float(mode._push_in) >= 0.0, "the queued push remains scheduled")
	client.busy = false
	mode._process(0.02)
	eq(client.calls, 1, "the queued edits sync next")
	mode.free()
	client.free()


class DeferredSync extends Node:
	var busy := true
	var calls := 0

	func sync() -> Dictionary:
		calls += 1
		return {"ok": true}


func test_a_home_place_that_isnt_there_leads_home() -> void:
	fresh_save_root()
	StarterContent.create_world("Mine", "Sam")
	HomeMapper.build_home(_answers(), {}, "")
	var entry := LightHome.entry_id()
	check(entry != "" and entry != Realms.ENTRY, "a mapped home (%s)" % entry)
	var w := SaveManager.load_world()
	w["last_room"] = Realms.ENTRY   # the phone's old placeholder room, which this PC doesn't have
	SaveManager.save_world(w)
	GameState.load_world()
	eq(GameState.current_room_id, entry, "you wake up at home, not in the Dream World")
	for id in SaveManager.list_light_rooms():
		SaveManager.delete_room(id)
	GameState.load_world()
	eq(GameState.current_room_id, entry, "missing generated floors are rebuilt from the saved home")
	check(SaveManager.room_exists(entry), "the recovered floor is on disk")


func test_pairing_again_replaces_the_same_phone() -> void:
	var root := fresh_save_root()
	var p := Pairing.new(root)
	for i in 2:
		var r: Dictionary = p.pair(p.new_code(), "Android phone", "192.168.1.40", "", "abcdef0123456789")
		check(bool(r.ok), "pairing %d" % (i + 1))
	eq(p.devices().size(), 1, "the same phone twice is one entry")
	# A full list: the same phone's entries from before (no id, not seen for two weeks) make room.
	var list := p.devices()
	var old := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system() - 14 * 86400))
	for i in 3:
		list.append({"id": "dold%d" % i, "name": "Android phone", "token_sha256": "x", "paired": old, "last_seen": old, "host": "", "client": ""})
	p._save_devices(list)
	eq(p.devices().size(), 4, "full")
	var r2: Dictionary = p.pair(p.new_code(), "Android phone", "192.168.1.40", "", "ffffeeeeddddcccc")
	check(bool(r2.ok), "a new pairing still works: %s" % str(r2.get("error", "")))
	eq(p.devices().size(), 4, "by dropping one stale entry of the same phone")
	# Phones seen recently are never dropped.
	var fresh := p.devices().map(func(d): d["last_seen"] = Time.get_datetime_string_from_system(); return d)
	p._save_devices(fresh)
	var r3: Dictionary = p.pair(p.new_code(), "Android phone", "192.168.1.40", "", "0000111122223333")
	check(not bool(r3.ok), "a full list of phones in use still says so")


func test_your_answers_stay_on_the_pc_even_in_snapshots() -> void:
	fresh_save_root()
	HomeMapper.build_home(_answers(), {}, "")
	check(FileAccess.file_exists(HomeStore.path("private.json")), "private.json")
	var zip := HomeStore.snapshot("test")
	var h := HomeStore.load_home()
	h["address"] = {"text": "somewhere else"}
	HomeStore.save_home(h)
	HomeStore.restore(zip)
	eq(str(HomeStore.load_home().get("address", {}).get("text", "")), ADDRESS, "undo brings the address back too")
	# An older home.json with the address inside is split the first time it's shared.
	var old := HomeStore.load_home()
	JsonUtil.write_json(HomeStore.path("home.json"), old)
	DirAccess.remove_absolute(HomeStore.path("private.json"))
	check(FileAccess.get_file_as_string(HomeStore.path("home.json")).contains(ADDRESS), "(an old-style home.json)")
	HomeStore.split_private()
	check(not FileAccess.get_file_as_string(HomeStore.path("home.json")).contains(ADDRESS), "split: home.json without it")
	eq(str(HomeStore.load_home().get("address", {}).get("text", "")), ADDRESS, "and nothing lost")
