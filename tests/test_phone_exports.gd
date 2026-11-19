extends "res://tests/test_case.gd"
## Phone exports reach the player (1.27.17): a world exported on a phone used to stay in the app's
## private storage. Now the phone sends it to the paired PC (PUT /api/export, export_inbox.gd) in
## chunks, the PC checks it and files it under exports/, and the phone remembers what went where
## (phone_exports.gd). The real server on 127.0.0.1, the real sync client, raw requests for the rejects.

const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const SyncClient := preload("res://scripts/phone/sync_client.gd")
const PhoneExports := preload("res://scripts/phone/phone_exports.gd")
const PhoneMode := preload("res://scripts/phone/phone_mode.gd")
const ExportInbox := preload("res://scripts/phone/export_inbox.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")

var server: Node
var port := 0
var pc_root := ""
var phone_root := ""


func _start() -> void:
	pc_root = fresh_save_root()
	StarterContent.create_world("Sofa World", "Sam")
	GameState.load_world()
	var web := pc_root.path_join("_web")
	JsonUtil.ensure_dir(web)
	FileAccess.open(web.path_join("index.html"), FileAccess.WRITE).store_string("fake")
	server = PhoneServer.new()
	tree.root.add_child(server)
	server.setup(pc_root, web)
	port = listen_on_free_port(func(p: int) -> String: return server.start(p, "127.0.0.1"), "Phone Link")
	phone_root = pc_root.path_join("_phone")
	JsonUtil.ensure_dir(phone_root.path_join("exports"))


func _stop() -> void:
	PhoneExports.chunk_bytes = PhoneExports.CHUNK
	server.stop()
	server.queue_free()
	await frames(1)


func _raw(data: PackedByteArray) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", port)
	var t := Time.get_ticks_msec()
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t < 3000:
		peer.poll()
		await frames(1)
	peer.put_data(data)
	var got := PackedByteArray()
	t = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 8000:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_data(n)[1])
		await frames(1)
	var text := got.get_string_from_utf8()
	var split := text.find("\r\n\r\n")
	var head := text.substr(0, split)
	var code := head.split(" ")[1].to_int() if head.split(" ").size() > 1 else 0
	var json: Variant = JSON.parse_string(text.substr(split + 4))
	return {"code": code, "json": json if json is Dictionary else {}}


func _put(query: String, body: PackedByteArray, token: String) -> Dictionary:
	var head := "PUT /api/export?%s HTTP/1.1\r\nHost: x\r\nContent-Length: %d\r\n%s\r\n" % [query, body.size(), ("Authorization: Bearer %s\r\n" % token) if token != "" else ""]
	var bytes := head.to_utf8_buffer()
	bytes.append_array(body)
	return await _raw(bytes)


func _pair() -> String:
	var code: String = server.pairing.new_code()
	var req := JSON.stringify({"code": code, "device": "Test phone"})
	var head := "POST /api/pair HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % req.to_utf8_buffer().size()
	var bytes := head.to_utf8_buffer()
	bytes.append_array(req.to_utf8_buffer())
	var r := await _raw(bytes)
	return str(r.json.get("token", ""))


func _client(token: String) -> Node:
	var c := SyncClient.new()
	tree.root.add_child(c)
	c.base_url = "http://127.0.0.1:%d" % port
	c.token = token
	c.local_root = phone_root
	return c


## The world as a phone would export it, into the phone's own exports folder.
func _phone_export(name: String) -> String:
	var dest := phone_root.path_join("exports").path_join(name)
	check(SlotArchive.export_bundle(SaveManager.slot_id, dest), "the world exports")
	return dest


func test_a_phone_export_lands_in_the_pcs_exports_folder_in_chunks() -> void:
	_start()
	var token := await _pair()
	var phone := _client(token)
	var dest := _phone_export("Sofa_World_2026-11-05.polox")
	var size := FileAccess.get_file_as_bytes(dest).size()
	PhoneExports.chunk_bytes = maxi(4096, size / 5)   # five or six chunks
	eq(PhoneExports.exported(phone_root), PackedStringArray(["exports/Sofa_World_2026-11-05.polox"]), "the phone lists its export")
	check(not PhoneExports.done(phone_root, "exports/Sofa_World_2026-11-05.polox", "pc"), "not sent yet")
	var r: Dictionary = await PhoneExports.send_to_pc(phone, phone_root, dest)
	check(bool(r.ok), "sent: " + str(r.error))
	eq(str(r.saved), "exports/Sofa_World_2026-11-05.polox", "the PC says where it keeps it")
	var on_pc := pc_root.path_join("exports/Sofa_World_2026-11-05.polox")
	check(FileAccess.file_exists(on_pc), "the file is in the PC's exports folder")
	eq(FileAccess.get_sha256(on_pc), FileAccess.get_sha256(dest), "byte for byte")
	check("world.json" in SlotArchive.inspect_zip(on_pc).get("files", []), "and it is the world")
	eq(DirAccess.get_files_at(pc_root.path_join("exports/.incoming")).size(), 0, "nothing left half-sent")
	check(PhoneExports.done(phone_root, "exports/Sofa_World_2026-11-05.polox", "pc"), "the phone remembers it went")
	eq(await PhoneExports.send_missing_to_pc(phone, phone_root), 0, "nothing is sent twice")
	check(FileAccess.get_file_as_string(pc_root.path_join("phone/audit.log")).contains("export_received file=exports/Sofa_World_2026-11-05.polox"), "the PC's audit log notes it")
	# The same name exported again later (the world changed): kept beside the first, not over it.
	JsonUtil.write_json(SaveManager.slot_dir().path_join("dreams.json"), {"changed": Time.get_ticks_usec()})
	_phone_export("Sofa_World_2026-11-05.polox")
	await frames(2)
	eq(await PhoneExports.send_missing_to_pc(phone, phone_root), 1, "the changed export goes again")
	check(FileAccess.file_exists(pc_root.path_join("exports/Sofa_World_2026-11-05 (2).polox")), "beside the first one")
	check(FileAccess.file_exists(on_pc), "the first one stays")
	phone.queue_free()
	await _stop()


func test_the_pc_takes_only_whole_checked_worlds_from_paired_phones() -> void:
	_start()
	var token := await _pair()
	var dest := _phone_export("w.polox")
	var bytes := FileAccess.get_file_as_bytes(dest)
	var sha := FileAccess.get_sha256(dest)
	var q := "name=w.polox&offset=0&total=%d&sha256=%s" % [bytes.size(), sha]
	eq(int((await _put(q, bytes, "")).code), 401, "no key, no upload")
	eq(int((await _put(q, bytes, "f".repeat(64))).code), 401, "a wrong key neither")
	for bad in ["..%2Fw.polox", "w.exe", ".hidden.polox", "a%2Fb.polox", ""]:
		eq(int((await _put(q.replace("name=w.polox", "name=" + bad), bytes, token)).code), 400, "refuses the name '%s'" % bad)
	eq(int((await _put(q.replace(sha, "0".repeat(64)), bytes, token)).code), 422, "a file that doesn't match its checksum is dropped")
	var junk := "not a zip at all".to_utf8_buffer()
	eq(int((await _put("name=j.polox&offset=0&total=%d&sha256=%s" % [junk.size(), _sha(junk)], junk, token)).code), 415, "a .polox that isn't a world is refused")
	# Resuming: half the file, then a chunk at the wrong place -> 409 with how much the PC has.
	var half := bytes.slice(0, bytes.size() / 2)
	var r1 := await _put(q, half, token)
	eq(int(r1.code), 200, "the first half arrives")
	eq(int(r1.json.get("have", -1)), half.size(), "the PC says how much it has")
	var r2 := await _put(q.replace("offset=0", "offset=7"), bytes.slice(7, 20), token)
	eq(int(r2.code), 409, "a chunk at the wrong place is refused")
	eq(int(r2.json.get("have", -1)), half.size(), "with where to carry on")
	var r3 := await _put(q.replace("offset=0", "offset=%d" % half.size()), bytes.slice(half.size()), token)
	eq(int(r3.code), 200, "the rest arrives")
	check(bool(r3.json.get("done", false)), "done")
	eq(FileAccess.get_sha256(pc_root.path_join("exports/w.polox")), sha, "whole and unchanged")
	eq(int((await _put(q, bytes, token)).code), 200, "sending the same file again is fine")
	eq(JsonUtil.list_files(pc_root.path_join("exports"), ["polox"]).size(), 1, "and keeps one copy")
	await _stop()


static func _sha(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish().hex_encode()


func test_names_lists_and_what_the_player_reads() -> void:
	eq(ExportInbox.clean_name("My World_2026-11-05.polox"), "My World_2026-11-05.polox", "a world's export name")
	eq(ExportInbox.clean_name("chat_logs_2026-11-05_201500.txt"), "chat_logs_2026-11-05_201500.txt", "a chat log")
	for bad in ["../x.polox", "x.polox.exe", "x.jsonl", "C:\\x.polox", "a/b.polox", ".polox", "x?.polox"]:
		eq(ExportInbox.clean_name(bad), "", "refuses '%s'" % bad)
	var root := fresh_save_root("exports_list")
	JsonUtil.ensure_dir(root.path_join("exports"))
	JsonUtil.ensure_dir(root.path_join("slots/a/exports"))
	for rel in ["exports/A.polox", "exports/notes.md", "slots/a/exports/chat.txt", "slots/a/exports/chat.jsonl"]:
		FileAccess.open(root.path_join(rel), FileAccess.WRITE).store_string("x")
	eq(PhoneExports.exported(root), PackedStringArray(["exports/A.polox", "slots/a/exports/chat.txt"]), "worlds and readable chat logs only")
	eq(PhoneExports.rel_of(root, root.path_join("exports/A.polox")), "exports/A.polox", "relative to the save root")
	eq(PhoneExports.save_to_downloads(root, root.path_join("exports/A.polox")), "", "a PC has no phone Downloads to copy to")
	var both := PhoneMode.share_text("A.polox", {"downloads": "Download/Polox/A.polox", "pc": "exports/A.polox", "paired": true})
	check(both.contains("Download/Polox on this phone") and both.contains("Your PC has it too"), "says both places: " + both)
	var later := PhoneMode.share_text("A.polox", {"downloads": "Download/Polox/A.polox", "pc": "", "paired": true})
	check(later.contains("next time they're connected"), "says when the PC gets it: " + later)
	var alone := PhoneMode.share_text("A.polox", {"downloads": "", "pc": "", "paired": false})
	check(alone.contains("couldn't put a copy") and not alone.contains("PC"), "no promises without a PC: " + alone)


func test_a_backup_made_on_the_phone_goes_to_the_pc() -> void:
	_start()
	var token := await _pair()
	var phone := _client(token)
	var slot: String = SaveManager.slot_id
	var folder := phone_root.path_join("slots/%s/backups" % slot)
	JsonUtil.ensure_dir(folder)
	var zip := folder.path_join("manual_2026-11-05_210000_001.zip")
	check(SlotArchive.zip_folder(SaveManager.slot_dir(), zip), "the phone's Backup button makes a zip")
	# Only its manual backups are listed (the automatic ones come every few minutes).
	var auto := folder.path_join("auto_2026-11-05_210001_001.zip")
	DirAccess.copy_absolute(zip, auto)
	var listed := PhoneExports.exported(phone_root)
	check("slots/%s/backups/manual_2026-11-05_210000_001.zip" % slot in listed, "the manual backup is listed")
	check(not ("slots/%s/backups/auto_2026-11-05_210001_001.zip" % slot in listed), "an automatic one is not")
	PhoneExports.chunk_bytes = maxi(4096, FileAccess.get_file_as_bytes(zip).size() / 3)
	var r: Dictionary = await PhoneExports.send_to_pc(phone, phone_root, zip)
	check(bool(r.ok), "sent: " + str(r.error))
	eq(str(r.saved), "phone_backups/%s/manual_2026-11-05_210000_001.zip" % slot, "kept under phone_backups, by world")
	eq(FileAccess.get_sha256(pc_root.path_join(str(r.saved))), FileAccess.get_sha256(zip), "byte for byte")
	eq(JsonUtil.list_files(pc_root.path_join("exports"), ["zip", "polox"]).size(), 0, "not mixed into exports/")
	# A zip that isn't a world is refused.
	var junk := folder.path_join("manual_junk.zip")
	var zp := ZIPPacker.new()
	zp.open(junk)
	zp.start_file("readme.txt")
	zp.write_file("x".to_utf8_buffer())
	zp.close_file()
	zp.close()
	var bad: Dictionary = await PhoneExports.send_to_pc(phone, phone_root, junk)
	check(not bool(bad.ok), "a zip with no world in it is refused")
	phone.queue_free()
	await _stop()
