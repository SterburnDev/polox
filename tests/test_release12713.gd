extends "res://tests/test_case.gd"
const Mapper := preload("res://scripts/home/home_mapper.gd")
const Light := preload("res://scripts/world/light_home.gd")
const Store := preload("res://scripts/home/home_store.gd")
const Graphics := preload("res://scripts/core/graphics.gd")

class PairedPhone extends Node:
	var token := ""
	var origin := ""
	func paired() -> bool:
		return token != ""

func test_helper_buttons_explain_missing_input_and_do_not_send() -> void:
	fresh_save_root()
	var map := preload("res://scripts/home/map_home_panel.gd").new()
	tree.root.add_child(map)
	map.setup_home(null)
	var look := map.find_child("LookAgain", true, false) as Button
	check(not look.disabled, "button can explain what is missing")
	look.pressed.emit()
	eq(map._status.text, "Map your home first.")
	var tell := preload("res://scripts/home/tell_polox_panel.gd").new()
	tree.root.add_child(tell)
	tell.setup_tell(null)
	tell.ask_helper("pc")
	eq(tell._status.text, tell.NEED_WORDS)
	check(tell._status.get_parent() == tell.body, "helper feedback is above the preview, outside the action row")
	check(tell._research == null, "blank input sends nothing")
	map.queue_free()
	tell.queue_free()
	await frames(2)
	var research := preload("res://scripts/home/research.gd").new()
	tree.root.add_child(research)
	research.available_override = {"pc": true}
	research.start_words("pc", "A photo", {}, "res://tests/fixtures/photo.png")
	var result: Dictionary = await research.finished
	check(not bool(result.ok))
	eq(result.why, "capability", "unsupported attachments cannot be silently dropped")
	research.queue_free()
	await frames(2)

func test_old_house_and_rebuild_keep_the_street_exit() -> void:
	fresh_save_root()
	preload("res://scripts/core/starter_content.gd").create_world("Exit test", "Test")
	var answers := {"home_type": "house", "floors": 2, "rooms": {"bedroom": 2, "kitchen": 1}, "my_room": {"floor": 1}}
	Mapper.build_home(answers, {}, "")
	var street := Light.base_place("lw_hood_3_3", "Street", 12, 12, "outdoor")
	street.objects = [{"id": "home_door", "type": "door", "pos": [5, 0, 5], "door_target": "lw_floor_0"}]
	SaveManager.save_room(street)
	var ground := SaveManager.load_room("lw_floor_0")
	check((ground.objects as Array).filter(func(o): return str(o.get("type", "")) == "door").is_empty(), "old home lacks street exit")
	var count: int = ground.objects.size()
	Light.sanitize(ground)
	eq(ground.objects.size(), count + 1, "restore exit without removing furniture")
	Light.sanitize(ground)
	eq(ground.objects.size(), count + 1, "restoring again does not duplicate the door")
	var door: Dictionary = (ground.objects as Array).filter(func(o): return bool(o.get("street_gate", false)))[0]
	eq(door.door_target, "lw_hood_3_3")
	SaveManager.save_room(ground)
	check(Mapper.build_home(answers, {}, "") != "")
	ground = SaveManager.load_room("lw_floor_0")
	eq((ground.objects as Array).filter(func(o): return bool(o.get("street_gate", false))).size(), 1, "remapping keeps the street connected")

func test_mobile_automatic_has_a_battery_budget() -> void:
	eq(Graphics.frame_cap({"frame_rate": "auto"}, true), 60)
	eq(Graphics.frame_cap({"frame_rate": "auto"}, false), 0)
	eq(Graphics.frame_cap({"frame_rate": "120"}, true), 120, "explicit player choice still applies")
	eq(Graphics.msaa({"graphics": "balanced"}, true), Viewport.MSAA_DISABLED)
	eq(Graphics.msaa({"graphics": "balanced"}, false), Viewport.MSAA_2X)

func test_simple_lawn_rendering_does_not_use_floorboards() -> void:
	fresh_save_root()
	GameState.settings["graphics"] = "saver"
	var view := preload("res://scripts/world/room_view.gd").new()
	tree.root.add_child(view)
	view.build(Light.base_place("lw_lawn", "Lawn", 6, 6, "outdoor"))
	var floor_mesh := view._content.get_child(0) as MeshInstance3D
	var material := floor_mesh.material_override as StandardMaterial3D
	check(material != null)
	check(material.albedo_texture != preload("res://scripts/world/surface_detail.gd").texture("floor"), "lawn has no floorboard seams")
	GameState.settings.erase("graphics")
	view.queue_free()
	await frames(2)

func test_paired_helper_uses_pc_credentials_and_rejects_changed_provider() -> void:
	var root := fresh_save_root()
	var old := GameState.settings.duplicate(true)
	GameState.settings["light_world"] = {"helper": "openai", "openai_key": "fixture-key", "openai_model": "fixture-model"}
	var server := preload("res://scripts/phone/phone_server.gd").new()
	tree.root.add_child(server)
	server.setup(root)
	var paired: Dictionary = server.pairing.pair(server.pairing.new_code(), "Fixture phone", "127.0.0.1", "localhost")
	check(bool(paired.ok))
	var calls := {"count": 0}
	server.api.helper_transport = func(request):
		calls.count += 1
		check("Authorization: Bearer fixture-key" in request.headers, "only PC supplies credentials")
		var reply := {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": JSON.stringify({"changes": [], "questions": []})}]}]}
		return [HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify(reply).to_utf8_buffer()]

	var body := {"provider": "openai", "prompt": "Fixture only", "schema": preload("res://scripts/home/tell_polox.gd").WORDS_SCHEMA, "web": false}
	var req := {"path": "/api/home-helper", "method": "POST", "headers": {"authorization": "Bearer " + str(paired.token)}, "query": {}, "body": JSON.stringify(body).to_utf8_buffer()}
	var result: PackedByteArray = await server.api.handle(req, "127.0.0.1")
	var reply: Dictionary = JSON.parse_string(result.get_string_from_utf8().get_slice("\r\n\r\n", 1))
	check(bool(reply.get("ok", false)), "phone receives structured reply: " + str(reply.get("error", "")))
	check(not result.get_string_from_utf8().contains("fixture-key"), "key never returned to phone")
	eq(calls.count, 1)
	var port := listen_on_free_port(func(p: int) -> String: return server.start_on_safe_port(p, "127.0.0.1"), "Phone Link")
	port = server.port
	var phone := PairedPhone.new()
	phone.token = str(paired.token)
	phone.origin = "http://127.0.0.1:%d" % port
	var bridge := preload("res://scripts/home/helper_pc.gd").new()
	tree.root.add_child(bridge)
	var received: Dictionary = await bridge.run(phone, "openai", str(body.prompt), body.schema, false)
	check(bool(received.get("ok", false)), "actual phone HTTP bridge: " + str(received.get("error", "")))
	eq(calls.count, 2)
	bridge.queue_free()
	phone.free()
	GameState.settings.light_world.helper = "none"
	result = await server.api.handle(req, "127.0.0.1")
	check(result.get_string_from_utf8().contains("409"), "stale provider selection rejected")
	eq(calls.count, 2, "provider change cannot silently bill another lookup")
	GameState.settings = old
	server.stop()
	server.queue_free()
	await frames(2)
