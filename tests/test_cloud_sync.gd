extends "res://tests/test_case.gd"
## [CLOUD_SYNC] Cloud folder sync, proven with two "devices" (two save roots) and a "cloud" (a plain
## folder) in one process: packages and their checks, the merge rules, push and pull, edits on both
## devices, real conflicts and every answer to them, an upload that was cut off, an install that was
## interrupted, being offline, two devices syncing at the same moment, and a cloud copy that was made
## without knowing this device's changes. The rule under test throughout: nothing is ever overwritten
## without a copy kept, and nothing is overwritten silently.
## Tags: [CLOUD_SYNC]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const CloudPackage := preload("res://scripts/sync/cloud_package.gd")
const CloudMerge := preload("res://scripts/sync/cloud_merge.gd")
const CloudStore := preload("res://scripts/sync/cloud_store.gd")
const CloudSync := preload("res://scripts/sync/cloud_sync.gd")

const SLOT := "my_world"

var base_dir := ""
var cloud_dir := ""


# --- Fixtures -----------------------------------------------------------------------------------------

func _start(tag: String) -> void:
	base_dir = ProjectSettings.globalize_path("res://tests/.tmp_save").path_join("cloud_" + tag)
	JsonUtil.remove_tree(base_dir)
	cloud_dir = base_dir.path_join("Cloud Folder")   # (a space, like "My Drive")
	JsonUtil.ensure_dir(cloud_dir)


func _device(name: String) -> CloudSync:
	return CloudSync.new(base_dir.path_join(name), CloudStore.FolderStore.new(cloud_dir), name)


func _world(device: CloudSync, slot: String = SLOT) -> String:
	return device.world_dir(slot)


func _write_json(path: String, data: Variant) -> void:
	JsonUtil.ensure_dir(path.get_base_dir())
	JsonUtil.write_json(path, data)
	DirAccess.remove_absolute(path + ".bak")   # (keep fixtures free of recovery files unless a test adds one)


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	JsonUtil.ensure_dir(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _picture(colour: Color) -> PackedByteArray:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return image.save_png_to_buffer()


## A small made-up world with one of everything that syncs, and things that must not.
func _make_world(device: CloudSync, slot: String = SLOT) -> void:
	var dir := _world(device, slot)
	_write_json(dir.path_join("slot.json"), {"version": 1, "name": "Robin's World", "emoji": "🌙", "last_played": "2026-11-01T10:00:00", "playtime_s": 60})
	_write_json(dir.path_join("world.json"), {"version": 1, "name": "Robin's World", "player": {"name": "Robin"}, "start_room": "home"})
	_write_json(dir.path_join("rooms/home.json"), {"id": "home", "name": "Home", "wall": "cream", "tiles": [{"id": "t1", "x": 1, "y": 1}]})
	_write_json(dir.path_join("rooms/garden.json"), {"id": "garden", "name": "Garden", "wall": "green", "tiles": []})
	_write_json(dir.path_join("characters/pip/character.json"), {"id": "pip", "name": "Pip", "mood": "happy"})
	_write_bytes(dir.path_join("characters/pip/expressions/smile.png"), _picture(Color.YELLOW))
	_write_bytes(dir.path_join("logs/pip.jsonl"), '{"id":"m1","ts":"2026-11-01T10:00:00","role":"user","text":"hi"}\n'.to_utf8_buffer())
	# Never synced:
	_write_bytes(dir.path_join("backups/manual_2026-11-01_100000.zip"), "not really a zip".to_utf8_buffer())
	_write_bytes(dir.path_join("photos/holiday.png"), _picture(Color.BLUE))
	_write_json(dir.path_join("manifest.json"), {"version": 1, "files": {}})
	_write_bytes(dir.path_join("rooms/home.json.bak"), "{}".to_utf8_buffer())


func _edit_json(path: String, key: String, value: Variant) -> void:
	var data: Dictionary = JsonUtil.read_json(path, {})
	data[key] = value
	_write_json(path, data)


func _read(path: String, key: String) -> Variant:
	return (JsonUtil.read_json(path, {}) as Dictionary).get(key)


func _content(device: CloudSync, slot: String = SLOT) -> String:
	return CloudPackage.content_hash(CloudPackage.tracked_files(_world(device, slot)))


func _cloud_file(device: CloudSync, slot: String = SLOT) -> String:
	return cloud_dir.path_join(str(device.world_state(slot).ref))


## Two devices that both hold the world and agree with the cloud. Returns [pc, phone].
func _two_synced_devices() -> Array:
	var pc := _device("pc")
	_make_world(pc)
	check(pc.enable(SLOT).ok, "the PC switches sync on")
	var first := pc.sync(SLOT)
	check(first.ok and first.action == "pushed", "the PC's first sync sends the world: " + str(first.error))
	var phone := _device("phone")
	var added := phone.add_from_cloud(str(pc.world_state(SLOT).ref))
	check(added.ok and added.slot_id == "robin_s_world", "the phone brings it in from the cloud: " + str(added))
	return [pc, phone]


const PHONE_SLOT := "robin_s_world"


# --- The package ---------------------------------------------------------------------------------------

func test_only_a_worlds_plain_files_are_packed() -> void:
	_start("allowlist")
	for path in ["world.json", "rooms/home.json", "logs/pip.jsonl", "characters/pip/expressions/smile.png", "textures/wall.webp", "slot.json"]:
		check(CloudPackage.allowed(path), path + " may sync")
	for path in ["backups/manual.zip", "backups/notes.json", "conflicts/2026/rooms/home.json", "photos/holiday.png", "exports/chat.json",
			"manifest.json", "rooms/home.json.bak", "rooms/home.json.tmp", "rooms/.hidden.json", "../settings.json", "/settings.json",
			"C:/Users/Player/secret.json", "rooms\\home.json", "notes.txt", "music/song.ogg", "polox-sync.json", "scripts/run.gd", ""]:
		check(not CloudPackage.allowed(path), "'%s' never syncs" % path)
	var pc := _device("pc")
	_make_world(pc)
	var files := CloudPackage.tracked_files(_world(pc))
	eq(files.size(), 7, "the seven world files: " + str(files.keys()))
	check(not files.has("backups/manual_2026-11-01_100000.zip") and not files.has("photos/holiday.png") and not files.has("manifest.json") and not files.has("rooms/home.json.bak"), "nothing private or leftover")
	var before := CloudPackage.content_hash(files)
	_edit_json(_world(pc).path_join("slot.json"), "last_played", "2026-11-09T09:00:00")
	_edit_json(_world(pc).path_join("slot.json"), "playtime_s", 5000)
	eq(_content(pc), before, "just opening a world (last played, play time) isn't a change")
	_edit_json(_world(pc).path_join("slot.json"), "name", "Robin's Other World")
	check(_content(pc) != before, "renaming it is")
	# A file over the size limit stays on the device and is reported, not packed.
	var huge := PackedByteArray()
	huge.resize(preload("res://scripts/phone/sync_files.gd").MAX_FILE_BYTES + 1)
	_write_bytes(_world(pc).path_join("textures/huge.png"), huge)
	var skipped: Array = []
	check(not CloudPackage.tracked_files(_world(pc), skipped).has("textures/huge.png"), "a file over the limit isn't packed")
	eq(skipped, ["textures/huge.png"], "and the screen is told which one")


func test_a_package_is_checked_before_it_is_trusted() -> void:
	_start("package")
	var pc := _device("pc")
	_make_world(pc)
	var good := base_dir.path_join("good.poloxsync")
	var built := CloudPackage.build(_world(pc), good, {"world_uid": "w1", "world_name": "Robin's World", "revision_id": "r1", "revision": 1, "history": ["r1"], "device_id": "d1", "device_name": "pc"})
	check(built.ok and not FileAccess.file_exists(good + ".part"), "built, and the half-written name is gone")
	var checked := CloudPackage.validate(good)
	check(checked.ok, "a whole package passes: " + str(checked.error))
	eq(int(checked.meta.format), CloudPackage.FORMAT, "it says its format")
	eq(str(checked.meta.content_hash), _content(pc), "and its content hash is the world's")
	eq((checked.meta.files as Dictionary).size(), 7, "with every file listed")
	check(not str(checked.meta).contains(base_dir), "nothing in it says where it was on this PC")
	# Cut off while uploading: half the bytes.
	var whole := FileAccess.get_file_as_bytes(good)
	var cut := base_dir.path_join("cut.poloxsync")
	_write_bytes(cut, whole.slice(0, whole.size() / 2))
	var cut_check := CloudPackage.validate(cut)
	check(not cut_check.ok and cut_check.code == "unreadable", "half a file is refused: " + str(cut_check.error))
	# Not a package at all.
	_write_bytes(base_dir.path_join("text.poloxsync"), "hello".to_utf8_buffer())
	check(not CloudPackage.validate(base_dir.path_join("text.poloxsync")).ok, "a text file is refused")
	check(not CloudPackage.validate(base_dir.path_join("missing.poloxsync")).ok, "a missing file is refused")
	# Repacked by hand with one file changed, one missing, one extra, a path that escapes, a newer format.
	var meta: Dictionary = checked.meta
	var entries := {}
	for path in meta.files:
		entries[path] = CloudPackage.read_file(good, path)
	var changed := entries.duplicate()
	changed["rooms/home.json"] = '{"id":"home","name":"Someone else\'s home"}'.to_utf8_buffer()
	check(_validate_repacked("changed", meta, changed).code == "damaged", "a changed file inside is noticed")
	var missing := entries.duplicate()
	missing.erase("rooms/garden.json")
	check(_validate_repacked("missing", meta, missing).code == "damaged", "a missing file is noticed")
	var extra := entries.duplicate()
	extra["rooms/extra.json"] = "{}".to_utf8_buffer()
	check(_validate_repacked("extra", meta, extra).code == "damaged", "a file that isn't listed is refused")
	var settings := entries.duplicate()
	settings["settings.json"] = '{"ai":{"keys":{}}}'.to_utf8_buffer()
	var settings_meta := meta.duplicate(true)
	settings_meta.files["settings.json"] = preload("res://scripts/phone/http_util.gd").sha256_bytes(settings["settings.json"])
	settings_meta["content_hash"] = CloudPackage.content_hash(settings_meta.files)
	check(_validate_repacked("settings", settings_meta, settings).ok, "(a root .json file is an ordinary world file)")
	var script_meta := meta.duplicate(true)
	var with_script := entries.duplicate()
	with_script["scripts/run.gd"] = "extends Node".to_utf8_buffer()
	script_meta.files["scripts/run.gd"] = preload("res://scripts/phone/http_util.gd").sha256_bytes(with_script["scripts/run.gd"])
	script_meta["content_hash"] = CloudPackage.content_hash(script_meta.files)
	check(not _validate_repacked("script", script_meta, with_script).ok, "a script inside is refused even when listed")
	var escape := entries.duplicate()
	escape["../outside.json"] = "{}".to_utf8_buffer()
	check(not _validate_repacked("escape", meta, escape).ok, "a path that leaves the world is refused")
	var newer := meta.duplicate(true)
	newer["format"] = CloudPackage.FORMAT + 1
	var newer_check := _validate_repacked("newer", newer, entries)
	check(not newer_check.ok and newer_check.code == "newer_format" and str(newer_check.error).contains("newer Polox"), "a newer format says so, plainly")
	var broken_picture := entries.duplicate()
	broken_picture["characters/pip/expressions/smile.png"] = "not a picture".to_utf8_buffer()
	var picture_meta := meta.duplicate(true)
	picture_meta.files["characters/pip/expressions/smile.png"] = preload("res://scripts/phone/http_util.gd").sha256_bytes(broken_picture["characters/pip/expressions/smile.png"])
	picture_meta["content_hash"] = CloudPackage.content_hash(picture_meta.files)
	check(not _validate_repacked("picture", picture_meta, broken_picture).ok, "a picture that isn't one is refused")
	eq(CloudPackage.file_name("Robin's World!", "abcdef1234567890"), "robin_s_world-abcdef12.poloxsync", "a tidy file name")


func _validate_repacked(tag: String, meta: Dictionary, entries: Dictionary) -> Dictionary:
	var path := base_dir.path_join(tag + ".poloxsync")
	var packer := ZIPPacker.new()
	packer.open(path)
	packer.start_file(CloudPackage.META_FILE)
	packer.write_file(JSON.stringify(meta).to_utf8_buffer())
	packer.close_file()
	for name in entries:
		packer.start_file(name)
		packer.write_file(entries[name])
		packer.close_file()
	packer.close()
	return CloudPackage.validate(path)


# --- The merge rules -----------------------------------------------------------------------------------

func test_each_file_lands_in_one_bucket() -> void:
	var base := {"same": "a", "cloud_changed": "a", "local_changed": "a", "both": "a", "cloud_removed": "a", "local_removed": "a", "edit_vs_remove": "a", "both_same_edit": "a"}
	var local := {"same": "a", "cloud_changed": "a", "local_changed": "L", "both": "L", "cloud_removed": "a", "edit_vs_remove": "L", "local_added": "L", "both_same_edit": "X", "both_added_same": "S"}
	var remote := {"same": "a", "cloud_changed": "R", "local_changed": "a", "both": "R", "local_removed": "a", "cloud_added": "R", "both_same_edit": "X", "both_added_same": "S"}
	var plan := CloudMerge.plan(base, local, remote)
	eq(plan.take_remote, ["cloud_added", "cloud_changed"], "only the cloud changed or added: take the cloud's")
	eq(plan.delete_local, ["cloud_removed"], "only the cloud removed it: remove it here")
	eq(plan.keep_local, ["local_added", "local_changed", "local_removed"], "only this device touched it: it goes up as it is")
	eq(plan.both_changed, ["both", "edit_vs_remove"], "changed on both sides, differently")
	eq(int(plan.same), 3, "already the same (including the same edit made twice)")
	# No common ancestor: nothing is deleted or replaced by rule.
	var blind := CloudMerge.plan({}, {"only_here": "L", "differs": "L", "same": "a"}, {"only_there": "R", "differs": "R", "same": "a"})
	eq(blind.delete_local, [], "without a common ancestor nothing is ever deleted")
	eq(blind.keep_local, ["only_here"], "what only this device has stays")
	eq(blind.take_remote, ["only_there"], "what only the cloud has arrives")
	eq(blind.both_changed, ["differs"], "and a file that differs is a question")


func test_files_combine_by_rule_or_not_at_all() -> void:
	var base := '{"id":"home","name":"Home","wall":"cream","floor":"wood"}'.to_utf8_buffer()
	var mine := '{"id":"home","name":"Home","wall":"blue","floor":"wood"}'.to_utf8_buffer()
	var theirs := '{"id":"home","name":"Home","wall":"cream","floor":"tile"}'.to_utf8_buffer()
	var merged := CloudMerge.merge_file("rooms/home.json", base, mine, theirs)
	check(merged.ok, "different fields of one file combine")
	var result: Dictionary = JsonUtil.parse((merged.bytes as PackedByteArray).get_string_from_utf8())
	check(result.wall == "blue" and result.floor == "tile", "with both changes: " + str(result))
	var clash := CloudMerge.merge_file("rooms/home.json", base, mine, '{"id":"home","name":"Home","wall":"red","floor":"wood"}'.to_utf8_buffer())
	check(not clash.ok and str(clash.why).contains("same thing"), "the same field set two ways is a real conflict: " + str(clash.why))
	check(not CloudMerge.merge_file("rooms/home.json", PackedByteArray(), mine, theirs).ok, "no earlier copy: can't tell who changed what")
	check(not CloudMerge.merge_file("rooms/home.json", base, PackedByteArray(), theirs).ok, "removed here, edited there: a conflict")
	check(not CloudMerge.merge_file("characters/pip/expressions/smile.png", _picture(Color.RED), _picture(Color.GREEN), _picture(Color.BLUE)).ok, "a picture both repainted: a conflict")
	var chat_here := '{"id":"m1","ts":"1","text":"hi"}\n{"id":"m2","ts":"2","text":"from here"}\n'.to_utf8_buffer()
	var chat_there := '{"id":"m1","ts":"1","text":"hi"}\n{"id":"m3","ts":"3","text":"from there"}\n'.to_utf8_buffer()
	var chat := CloudMerge.merge_file("logs/pip.jsonl", PackedByteArray(), chat_here, chat_there)
	check(chat.ok, "chats always combine")
	eq((chat.bytes as PackedByteArray).get_string_from_utf8().count("\n"), 3, "every message once, none lost")
	check(CloudMerge.describe("rooms/kitchen.json").contains("kitchen") and CloudMerge.describe("logs/pip.jsonl").contains("chat"), "conflicts are named in plain words")


# --- Two devices ----------------------------------------------------------------------------------------

func test_a_world_travels_from_one_device_to_the_other_and_back() -> void:
	_start("travel")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	eq(_content(phone, PHONE_SLOT), _content(pc), "the phone has the same world")
	eq(phone.check(PHONE_SLOT).state, "synced", "and knows it")
	check(not FileAccess.file_exists(cloud_dir.path_join(str(pc.world_state(SLOT).ref)) + ".uploading"), "no half-uploaded file is left in the cloud folder")
	eq(DirAccess.get_files_at(cloud_dir).size(), 1, "one file in the cloud folder per world")
	check(not DirAccess.dir_exists_absolute(_world(phone, PHONE_SLOT).path_join("backups")) or DirAccess.get_files_at(_world(phone, PHONE_SLOT).path_join("backups")).is_empty(), "the PC's backups didn't come along")
	check(not FileAccess.file_exists(_world(phone, PHONE_SLOT).path_join("photos/holiday.png")), "nor its photos")
	# The phone builds something; the PC gets it.
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall", "blue")
	_write_json(_world(phone, PHONE_SLOT).path_join("rooms/attic.json"), {"id": "attic", "name": "Attic", "tiles": []})
	eq(phone.check(PHONE_SLOT).state, "local_changes", "the phone sees its own changes")
	eq(pc.check(SLOT).state, "synced", "the PC sees nothing new yet")
	var up := phone.sync(PHONE_SLOT)
	check(up.ok and up.action == "pushed", "the phone sends them: " + str(up.error))
	eq(pc.check(SLOT).state, "cloud_changes", "now the PC sees the cloud is ahead")
	_write_bytes(_world(pc).path_join("photos/another.png"), _picture(Color.RED))   # (private to the PC)
	var down := pc.sync(SLOT)
	check(down.ok and down.action == "pulled", "the PC takes them: " + str(down.error))
	eq(_read(_world(pc).path_join("rooms/home.json"), "wall"), "blue", "the wall is blue on the PC")
	check(FileAccess.file_exists(_world(pc).path_join("rooms/attic.json")), "the new room is there")
	check("rooms/home.json" in down.changed_paths and "rooms/attic.json" in down.changed_paths, "and the game is told what to reload: " + str(down.changed_paths))
	check(FileAccess.file_exists(_world(pc).path_join("photos/holiday.png")) and FileAccess.file_exists(_world(pc).path_join("photos/another.png")), "the PC's own photos weren't touched")
	var zips := Array(DirAccess.get_files_at(_world(pc).path_join("backups"))).filter(func(name): return str(name).begins_with("before_cloud_"))
	eq(zips.size(), 1, "the PC's world was zipped before it changed")
	eq(_content(pc), _content(phone, PHONE_SLOT), "both the same again")
	eq(pc.sync(SLOT).action, "none", "a second sync has nothing to do")
	# The PC removes a room; it goes away on the phone too.
	JsonUtil.remove_file(_world(pc).path_join("rooms/garden.json"))
	check(pc.sync(SLOT).ok and phone.sync(PHONE_SLOT).ok, "both sync")
	check(not FileAccess.file_exists(_world(phone, PHONE_SLOT).path_join("rooms/garden.json")), "a room removed on one is removed on the other")
	# Switching sync off forgets the link and nothing else.
	phone.disable(PHONE_SLOT)
	eq(phone.check(PHONE_SLOT).state, "off", "sync off")
	check(FileAccess.file_exists(_world(phone, PHONE_SLOT).path_join("world.json")) and FileAccess.file_exists(_cloud_file(pc)), "the world and the cloud copy both stay")


func test_changes_on_both_devices_are_combined() -> void:
	_start("combine")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	# Offline, each device does something different.
	_edit_json(_world(pc).path_join("rooms/home.json"), "wall", "blue")
	_write_json(_world(pc).path_join("rooms/cellar.json"), {"id": "cellar", "name": "Cellar", "tiles": []})
	_write_bytes(_world(pc).path_join("logs/pip.jsonl"), '{"id":"m1","ts":"2026-11-01T10:00:00","role":"user","text":"hi"}\n{"id":"m2","ts":"2026-11-02T10:00:00","role":"user","text":"from the PC"}\n'.to_utf8_buffer())
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "name", "Our Home")
	_edit_json(_world(phone, PHONE_SLOT).path_join("characters/pip/character.json"), "mood", "sleepy")
	_write_bytes(_world(phone, PHONE_SLOT).path_join("logs/pip.jsonl"), '{"id":"m1","ts":"2026-11-01T10:00:00","role":"user","text":"hi"}\n{"id":"m3","ts":"2026-11-03T10:00:00","role":"user","text":"from the phone"}\n'.to_utf8_buffer())
	check(pc.sync(SLOT).action == "pushed", "the PC syncs first")
	eq(phone.check(PHONE_SLOT).state, "both_changed", "the phone sees both changed")
	var merged := phone.sync(PHONE_SLOT)
	check(merged.ok and merged.action == "merged", "and combines them without asking: " + str(merged.error) + str(merged.conflicts))
	var home: Dictionary = JsonUtil.read_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), {})
	check(home.wall == "blue" and home.name == "Our Home", "one room, both edits: " + str(home))
	check(FileAccess.file_exists(_world(phone, PHONE_SLOT).path_join("rooms/cellar.json")), "the PC's new room")
	eq(_read(_world(phone, PHONE_SLOT).path_join("characters/pip/character.json"), "mood"), "sleepy", "the phone's own change kept")
	var chat := FileAccess.get_file_as_string(_world(phone, PHONE_SLOT).path_join("logs/pip.jsonl"))
	check(chat.contains("from the PC") and chat.contains("from the phone") and chat.count("\n") == 3, "every chat message, once")
	var back := pc.sync(SLOT)
	check(back.ok and back.action == "pulled", "the PC takes the combined world as a plain update: " + str(back.error))
	eq(_content(pc), _content(phone, PHONE_SLOT), "both the same")
	eq(_read(_world(pc).path_join("characters/pip/character.json"), "mood"), "sleepy", "with the phone's change on the PC")


func test_a_real_conflict_asks_and_changes_nothing_until_answered() -> void:
	_start("conflict")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	_edit_json(_world(pc).path_join("rooms/home.json"), "wall", "blue")
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall", "red")
	_write_bytes(_world(pc).path_join("characters/pip/expressions/smile.png"), _picture(Color.GREEN))
	_write_bytes(_world(phone, PHONE_SLOT).path_join("characters/pip/expressions/smile.png"), _picture(Color.PURPLE))
	check(pc.sync(SLOT).ok, "the PC syncs first")
	var cloud_before := FileAccess.get_sha256(_cloud_file(pc))
	var phone_before := _content(phone, PHONE_SLOT)
	var asked := phone.sync(PHONE_SLOT)
	check(not asked.ok and asked.action == "ask", "the phone asks")
	eq((asked.conflicts as Array).size(), 2, "about both things: " + str(asked.conflicts))
	eq(str(asked.conflicts[1].what), "the place \"Home\"", "the place is called by the name the player gave it")
	check(str(asked.conflicts[0].what).contains("pip"), "and the friend's picture by the friend")
	check(str(asked.conflicts[1].why).contains("(wall)") and not str(asked.conflicts[1].why).contains("/"), "what clashed, without file paths: " + str(asked.conflicts[1].why))
	eq(_content(phone, PHONE_SLOT), phone_before, "the phone's world is exactly as it was")
	eq(FileAccess.get_sha256(_cloud_file(pc)), cloud_before, "and so is the cloud's copy")
	eq(phone.sync(PHONE_SLOT).action, "ask", "asking again changes nothing either")
	eq(_content(phone, PHONE_SLOT), phone_before, "still untouched")
	# Answer: keep both.
	var both := phone.sync(PHONE_SLOT, "keep_both")
	check(both.ok and both.new_slot != "", "keep both: " + str(both.error))
	eq(_read(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall"), "red", "the phone keeps its red wall")
	eq(_read(_world(phone, str(both.new_slot)).path_join("rooms/home.json"), "wall"), "blue", "the PC's blue wall is a second world on the phone")
	check(str(_read(_world(phone, str(both.new_slot)).path_join("slot.json"), "name")).contains("(from pc)"), "named so they can be told apart")
	check(phone.world_state(str(both.new_slot)).is_empty(), "the second world isn't synced")
	var kept_dir := base_dir.path_join("phone/cloud/kept").path_join(str(phone.world_state(PHONE_SLOT).world_uid))
	eq(DirAccess.get_files_at(kept_dir).size(), 1, "the replaced cloud copy is kept on the phone")
	check(CloudPackage.validate(kept_dir.path_join(DirAccess.get_files_at(kept_dir)[0])).ok, "whole and readable")
	var pc_after := pc.sync(SLOT)
	check(pc_after.ok and pc_after.action == "pulled", "the PC takes the phone's choice as a plain update")
	eq(_read(_world(pc).path_join("rooms/home.json"), "wall"), "red", "red on the PC")
	check(DirAccess.get_files_at(_world(pc).path_join("backups")).size() >= 1, "with the PC's blue world zipped first")


func test_the_other_answers_to_a_conflict() -> void:
	_start("answers")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	_edit_json(_world(pc).path_join("rooms/home.json"), "wall", "blue")
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall", "red")
	check(pc.sync(SLOT).ok and phone.sync(PHONE_SLOT).action == "ask", "a conflict")
	var cloud := phone.sync(PHONE_SLOT, "use_cloud")
	check(cloud.ok and cloud.action == "pulled", "use the cloud's: " + str(cloud.error))
	eq(_read(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall"), "blue", "the phone has the PC's wall")
	var zips := Array(DirAccess.get_files_at(_world(phone, PHONE_SLOT).path_join("backups")))
	check(zips.size() == 1 and str(zips[0]).begins_with("before_cloud_"), "and a zip of its own red world from before")
	eq(pc.sync(SLOT).action, "none", "nothing for the PC to do")
	# Again, answered the other way.
	_edit_json(_world(pc).path_join("rooms/home.json"), "wall", "green")
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall", "yellow")
	check(pc.sync(SLOT).ok and phone.sync(PHONE_SLOT).action == "ask", "another conflict")
	var mine := phone.sync(PHONE_SLOT, "use_this_device")
	check(mine.ok and mine.action == "pushed", "use this device's: " + str(mine.error))
	eq(DirAccess.get_files_at(base_dir.path_join("phone/cloud/kept").path_join(str(phone.world_state(PHONE_SLOT).world_uid))).size(), 1, "the PC's green copy is kept on the phone")
	check(pc.sync(SLOT).action == "pulled", "the PC follows")
	eq(_read(_world(pc).path_join("rooms/home.json"), "wall"), "yellow", "yellow on both")


func test_an_upload_that_was_cut_off_is_never_used() -> void:
	_start("cut_off")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	_edit_json(_world(pc).path_join("rooms/home.json"), "wall", "blue")
	check(pc.sync(SLOT).ok, "the PC sends a change")
	# The cloud app only got half of it up before the PC was switched off.
	var whole := FileAccess.get_file_as_bytes(_cloud_file(pc))
	_write_bytes(_cloud_file(pc), whole.slice(0, whole.size() * 2 / 3))
	var phone_before := _content(phone, PHONE_SLOT)
	var looked := phone.check(PHONE_SLOT)
	eq(looked.state, "cloud_damaged", "the phone sees a damaged cloud copy: " + str(looked.detail))
	var asked := phone.sync(PHONE_SLOT)
	check(not asked.ok and asked.action == "ask" and str(asked.error).contains("damaged"), "it says so and asks")
	eq(_content(phone, PHONE_SLOT), phone_before, "the phone's world is untouched")
	# The upload finishes later: everything is normal again.
	_write_bytes(_cloud_file(pc), whole)
	var later := phone.sync(PHONE_SLOT)
	check(later.ok and later.action == "pulled", "once the upload is whole, the phone takes it")
	# Damaged for good (and the phone has changes): the player sends the phone's copy instead.
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall", "pink")
	_write_bytes(_cloud_file(pc), "garbage".to_utf8_buffer())
	check(phone.sync(PHONE_SLOT).action == "ask", "damaged again: asks")
	var replaced := phone.sync(PHONE_SLOT, "upload")
	check(replaced.ok and replaced.action == "pushed", "send this device's copy: " + str(replaced.error))
	check(CloudPackage.validate(_cloud_file(pc)).ok, "the cloud copy is whole again")
	eq(DirAccess.get_files_at(base_dir.path_join("phone/cloud/kept").path_join(str(phone.world_state(PHONE_SLOT).world_uid))).size(), 1, "the damaged file was kept aside, not thrown away")
	# The PC, which never saw that revision, doesn't lose anything silently either.
	var pc_look := pc.check(SLOT)
	check(pc_look.state in ["cloud_changes", "both_changed"], "the PC sees a change it must look at: " + str(pc_look.state))


func test_an_interrupted_install_is_finished_after_a_restart() -> void:
	_start("interrupted")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	_edit_json(_world(pc).path_join("rooms/home.json"), "wall", "blue")
	_edit_json(_world(pc).path_join("rooms/garden.json"), "wall", "pink")
	_write_json(_world(pc).path_join("rooms/cellar.json"), {"id": "cellar", "tiles": []})
	check(pc.sync(SLOT).ok, "the PC sends three changes")
	# The phone starts taking them and dies after the first file: the package is kept, the note is
	# written, one file is in place.
	var uid := str(phone.world_state(PHONE_SLOT).world_uid)
	var incoming := base_dir.path_join("phone/cloud/incoming").path_join(uid + ".poloxsync")
	JsonUtil.ensure_dir(incoming.get_base_dir())
	DirAccess.copy_absolute(_cloud_file(pc), incoming)
	var meta := CloudPackage.read_meta(incoming)
	var state: Dictionary = JsonUtil.read_json(base_dir.path_join("phone/cloud/state.json"), {})
	state.worlds[PHONE_SLOT]["pending"] = {"base_meta": {"revision_id": meta.revision_id, "history": meta.history, "revision": meta.revision, "content_hash": meta.content_hash}}
	JsonUtil.write_json(base_dir.path_join("phone/cloud/state.json"), state)
	_write_bytes(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), CloudPackage.read_file(incoming, "rooms/home.json"))
	# The app starts again (a new engine, nothing in memory).
	var restarted := _device("phone")
	var finished := restarted.sync(PHONE_SLOT)
	check(finished.ok, "the next sync finishes the install: " + str(finished.error))
	check("rooms/garden.json" in finished.changed_paths and "rooms/cellar.json" in finished.changed_paths, "the files that were still missing arrive: " + str(finished.changed_paths))
	eq(_content(restarted, PHONE_SLOT), _content(pc), "the phone matches the PC")
	check(not restarted.world_state(PHONE_SLOT).has("pending") and not FileAccess.file_exists(incoming), "and the note and the kept package are gone")
	eq(restarted.check(PHONE_SLOT).state, "synced", "synced")
	# The same stop, but the kept package was lost too: the base is forgotten, so nothing is assumed.
	_edit_json(_world(pc).path_join("rooms/home.json"), "wall", "teal")
	check(pc.sync(SLOT).ok, "another change from the PC")
	state = JsonUtil.read_json(base_dir.path_join("phone/cloud/state.json"), {})
	state.worlds[PHONE_SLOT]["pending"] = {"base_meta": {"revision_id": "lost", "history": [], "revision": 0, "content_hash": ""}}
	JsonUtil.write_json(base_dir.path_join("phone/cloud/state.json"), state)
	var again := _device("phone")
	var recovered := again.sync(PHONE_SLOT)
	check(recovered.ok, "it still ends in step, by comparing files: " + str(recovered.error) + str(recovered.conflicts))
	eq(_read(_world(again, PHONE_SLOT).path_join("rooms/home.json"), "wall"), "teal", "with the PC's newest wall")


func test_offline_play_and_syncing_when_the_cloud_is_back() -> void:
	_start("offline")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	# The cloud folder goes away (the drive isn't connected, the cloud app isn't running).
	var parked := base_dir.path_join("parked")
	DirAccess.rename_absolute(cloud_dir, parked)
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall", "blue")
	var offline := phone.sync(PHONE_SLOT)
	check(not offline.ok and offline.state == "unreachable", "sync says the cloud can't be reached")
	check(str(offline.error).contains("isn't there right now"), "in plain words: " + str(offline.error))
	eq(_read(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall"), "blue", "and the phone keeps playing with its own copy")
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "name", "Blue Home")
	eq(phone.sync(PHONE_SLOT).state, "unreachable", "still offline, still fine")
	# Back again.
	DirAccess.rename_absolute(parked, cloud_dir)
	var back := phone.sync(PHONE_SLOT)
	check(back.ok and back.action == "pushed", "everything made offline goes up at the next sync: " + str(back.error))
	check(pc.sync(SLOT).action == "pulled", "and reaches the PC")
	eq(_read(_world(pc).path_join("rooms/home.json"), "name"), "Blue Home", "both offline edits")
	# No cloud folder chosen at all: local play is all there is, and sync says what to do.
	var nowhere := CloudSync.new(base_dir.path_join("pc"), CloudStore.FolderStore.new(""), "pc")
	check(str(nowhere.check(SLOT).detail).contains("No cloud folder is chosen"), "no folder chosen: says so")
	# The cloud's file vanished (deleted by hand): ask before sending it again.
	DirAccess.remove_absolute(_cloud_file(pc))
	var gone := pc.sync(SLOT)
	check(not gone.ok and gone.action == "ask" and gone.state == "cloud_missing", "a vanished cloud copy is asked about, not assumed")
	check(pc.sync(SLOT, "upload").ok and FileAccess.file_exists(_cloud_file(pc)), "and sent again on request")


func test_two_devices_syncing_at_the_same_moment() -> void:
	_start("race")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	_edit_json(_world(pc).path_join("rooms/garden.json"), "wall", "blue")
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall", "red")
	# The phone has looked and decided to push; the PC's push lands first.
	var phone_looked := phone.check(PHONE_SLOT)
	eq(phone_looked.state, "local_changes", "the phone sees only its own change")
	check(pc.sync(SLOT).ok, "the PC gets there first")
	var pc_revision := str(CloudPackage.read_meta(_cloud_file(pc)).revision_id)
	var out := {"ok": false, "action": "none", "state": "", "error": "", "conflicts": [], "changed_paths": [], "remote": {}, "skipped": [], "new_slot": ""}
	phone._push(PHONE_SLOT, phone_looked, out)
	check(not out.ok and str(out.error).contains("changed while syncing"), "the phone's push stops: " + str(out.error))
	eq(str(CloudPackage.read_meta(_cloud_file(pc)).revision_id), pc_revision, "the PC's revision is still the one in the cloud")
	var again := phone.sync(PHONE_SLOT)
	check(again.ok and again.action == "merged", "syncing again combines both: " + str(again.error))
	check(pc.sync(SLOT).ok, "and the PC follows")
	eq(_read(_world(pc).path_join("rooms/home.json"), "wall"), "red", "the phone's change")
	eq(_read(_world(pc).path_join("rooms/garden.json"), "wall"), "blue", "and the PC's, both on both")
	eq(_content(pc), _content(phone, PHONE_SLOT), "the same world")


func test_a_cloud_copy_made_without_knowing_ours_never_deletes_anything() -> void:
	_start("lineage")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	# The phone adds a room and syncs. Its upload never reaches the PC's cloud folder (the cloud app
	# is slow), and the PC, still on the old revision, uploads its own change over it.
	var stale_cloud := FileAccess.get_file_as_bytes(_cloud_file(pc))
	_write_json(_world(phone, PHONE_SLOT).path_join("rooms/treehouse.json"), {"id": "treehouse", "name": "Treehouse", "tiles": []})
	check(phone.sync(PHONE_SLOT).ok, "the phone sends its new room")
	_write_bytes(_cloud_file(pc), stale_cloud)   # (what the PC's folder still shows)
	_write_json(_world(pc).path_join("rooms/cellar.json"), {"id": "cellar", "name": "Cellar", "tiles": []})
	check(pc.sync(SLOT).ok, "the PC sends its own new room on top of the old revision")
	# The phone changed nothing since its sync, but the cloud's copy doesn't descend from it.
	eq(phone.check(PHONE_SLOT).state, "both_changed", "the phone doesn't treat that as a plain update")
	var result := phone.sync(PHONE_SLOT)
	check(result.ok and result.action == "merged", "it combines: " + str(result.error) + str(result.conflicts))
	check(FileAccess.file_exists(_world(phone, PHONE_SLOT).path_join("rooms/treehouse.json")), "the phone's room is NOT deleted (the cloud never had it)")
	check(FileAccess.file_exists(_world(phone, PHONE_SLOT).path_join("rooms/cellar.json")), "and the PC's room arrives")
	check(pc.sync(SLOT).ok and FileAccess.file_exists(_world(pc).path_join("rooms/treehouse.json")), "the PC gets the treehouse after all")
	# The same situation with one file edited on both: a question, never a guess.
	stale_cloud = FileAccess.get_file_as_bytes(_cloud_file(pc))
	_edit_json(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall", "red")
	check(phone.sync(PHONE_SLOT).ok, "the phone sends a wall")
	_write_bytes(_cloud_file(pc), stale_cloud)
	_edit_json(_world(pc).path_join("rooms/home.json"), "floor", "tile")
	check(pc.sync(SLOT).ok, "the PC sends a floor over it")
	var asked := phone.sync(PHONE_SLOT)
	check(not asked.ok and asked.action == "ask", "no common ancestor and the same file differs: the phone asks")
	eq(_read(_world(phone, PHONE_SLOT).path_join("rooms/home.json"), "wall"), "red", "its red wall is untouched meanwhile")


func test_finding_worlds_in_the_cloud_folder() -> void:
	_start("discover")
	var devices := _two_synced_devices()
	var pc: CloudSync = devices[0]
	var phone: CloudSync = devices[1]
	# A second world, only on the PC so far.
	_make_world(pc, "beach")
	_edit_json(_world(pc, "beach").path_join("slot.json"), "name", "Beach House")
	check(pc.enable("beach").ok and pc.sync("beach").ok, "the PC sends a second world")
	# A cloud app's "conflicted copy" of the first world, and a file that isn't a package.
	DirAccess.copy_absolute(_cloud_file(pc), cloud_dir.path_join("robin_s_world-conflicted copy.poloxsync"))
	_write_bytes(cloud_dir.path_join("notes.txt"), "hello".to_utf8_buffer())
	_write_bytes(cloud_dir.path_join("broken.poloxsync"), "junk".to_utf8_buffer())
	var found := phone.discover()
	eq(found.size(), 3, "three packages found (the broken one says nothing and is skipped): " + str(found.map(func(e): return e.ref)))
	var by_name := {}
	for entry in found:
		by_name[str(entry.ref)] = entry
	var beach: Dictionary = by_name[str(pc.world_state("beach").ref)]
	check(beach.world_name == "Beach House" and beach.slot_id == "" and not beach.duplicate and beach.device_name == "pc", "the beach world isn't on the phone yet: " + str(beach))
	check(by_name[str(pc.world_state(SLOT).ref)].slot_id == PHONE_SLOT, "the first world is the one the phone already has")
	check(by_name["robin_s_world-conflicted copy.poloxsync"].duplicate, "the conflicted copy is pointed out as a second file for the same world")
	var added := phone.add_from_cloud(str(pc.world_state("beach").ref))
	check(added.ok and added.slot_id == "beach_house", "the beach world comes onto the phone: " + str(added))
	eq(phone.check("beach_house").state, "synced", "linked and in step")
	check(not phone.add_from_cloud(str(pc.world_state("beach").ref)).ok, "adding it twice is refused")
	check(not phone.add_from_cloud("broken.poloxsync").ok and not DirAccess.dir_exists_absolute(base_dir.path_join("phone/slots/world")), "a broken package adds nothing")
	# A file for another world sitting where this world's should be.
	DirAccess.copy_absolute(cloud_dir.path_join(str(pc.world_state("beach").ref)), _cloud_file(pc))
	eq(phone.check(PHONE_SLOT).state, "wrong_world", "another world's file in this world's place is noticed")
	var before := _content(phone, PHONE_SLOT)
	check(not phone.sync(PHONE_SLOT).ok and _content(phone, PHONE_SLOT) == before, "and never applied")


func test_the_cloud_folder_store() -> void:
	_start("store")
	var store := CloudStore.FolderStore.new(cloud_dir + "\\")
	eq(store.folder, cloud_dir, "the folder is kept with forward slashes and no trailing slash")
	eq(store.reachable(), "", "reachable")
	var source := base_dir.path_join("a.poloxsync")
	_write_bytes(source, "first".to_utf8_buffer())
	eq(store.publish("world.poloxsync", source), "", "a file is published")
	_write_bytes(source, "second version".to_utf8_buffer())
	eq(store.publish("world.poloxsync", source), "", "and replaced")
	eq(FileAccess.get_file_as_string(cloud_dir.path_join("world.poloxsync")), "second version", "with the new contents")
	eq(Array(DirAccess.get_files_at(cloud_dir)), ["world.poloxsync"], "and nothing else left behind")
	var copy := base_dir.path_join("local/copy.poloxsync")
	eq(store.fetch("world.poloxsync", copy), "", "fetched")
	check(FileAccess.get_file_as_string(copy) == "second version" and not FileAccess.file_exists(copy + ".part"), "whole, under its final name")
	check(store.fetch("missing.poloxsync", copy) != "", "a missing file is an error, in words")
	eq(Array(store.list()), ["world.poloxsync"], "listing")
	var away := CloudStore.FolderStore.new(base_dir.path_join("not here"))
	check(away.reachable().contains("isn't there right now") and away.publish("x.poloxsync", source) != "" and away.list().is_empty(), "a folder that is away: plain words, nothing written")
	for suggestion in CloudStore.suggested_folders():
		check(str(suggestion.path).ends_with("/Polox") and suggestion.name != "", "suggestions are a Polox folder inside a cloud app's folder")
