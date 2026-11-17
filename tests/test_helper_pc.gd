extends "res://tests/test_case.gd"
## helper_pc.gd (the phone asking its paired PC for the home helper): cancelling, failing and overlapping
## calls all end, and none leaves a request node behind. (The working round trip is in test_release12713.gd.)

const HelperPc := preload("res://scripts/home/helper_pc.gd")
const Graphics := preload("res://scripts/core/graphics.gd")


class PairedPhone extends Node:
	var token := "fixture-token"
	var origin := ""

	func paired() -> bool:
		return token != "" and origin != ""


## A local port where connections are accepted by the system but nobody ever answers.
func _silent_server() -> TCPServer:
	var server := TCPServer.new()
	if listen_on_free_port(func(p: int) -> int: return server.listen(p, "127.0.0.1"), "the silent server") > 0:
		return server
	return null


## Starts run() without waiting for it; the result lands in the returned box when it ends.
func _start(bridge: Node, phone: Node) -> Dictionary:
	var box := {"done": false, "result": {}}
	var go := func() -> void:
		box.result = await bridge.run(phone, "openai", "fixture prompt", {"type": "object"}, false)
		box.done = true
	go.call()
	return box


## Waits for a started call to end. With a server, every connection that arrives is dropped at once (a PC
## that goes away mid-request: Windows takes about 30 s to report a refused local port, a dropped one is quick).
func _wait_done(box: Dictionary, server: TCPServer = null, limit_ms: int = 8000) -> void:
	var started := Time.get_ticks_msec()
	while not bool(box.done) and Time.get_ticks_msec() - started < limit_ms:
		if server != null and server.is_connection_available():
			server.take_connection().disconnect_from_host()
		await frames(1)


func test_cancelling_a_pc_request_ends_it_and_frees_the_request_node() -> void:
	var server := _silent_server()
	if not check(server != null, "a local port to listen on"):
		return
	var phone := PairedPhone.new()
	phone.origin = "http://127.0.0.1:%d" % server.get_local_port()
	var bridge: Node = HelperPc.new()
	tree.root.add_child(bridge)
	var box := _start(bridge, phone)
	await frames(8)
	check(not bool(box.done), "the PC has not answered, so the call is still waiting")
	eq(bridge.get_child_count(), 1, "one request in flight")
	bridge.cancel()
	await _wait_done(box)
	check(bool(box.done), "cancelling ends the call (it used to wait for good)")
	eq(str(box.result.get("why", "")), "cancelled")
	check(not bool(box.result.get("ok", true)))
	await frames(2)
	eq(bridge.get_child_count(), 0, "the request node is gone")
	# The same helper can ask again afterwards.
	var again := _start(bridge, phone)
	await frames(8)
	check(not bool(again.done), "a new request after a cancel is a real one")
	bridge.cancel()
	await _wait_done(again)
	eq(str(again.result.get("why", "")), "cancelled")
	bridge.queue_free()
	phone.free()
	server.stop()
	await frames(2)


func test_a_pc_that_goes_away_mid_request_ends_the_call_and_frees_the_request_node() -> void:
	var server := _silent_server()
	if not check(server != null, "a local port to listen on"):
		return
	var phone := PairedPhone.new()
	phone.origin = "http://127.0.0.1:%d" % server.get_local_port()
	var bridge: Node = HelperPc.new()
	tree.root.add_child(bridge)
	var box := _start(bridge, phone)
	await _wait_done(box, server)
	check(bool(box.done), "a dropped connection ends the call")
	eq(str(box.result.get("why", "")), "offline")
	check(not bool(box.result.get("ok", true)))
	await frames(2)
	eq(bridge.get_child_count(), 0, "the request node is gone")
	eq(bridge._http, null, "and forgotten")
	bridge.queue_free()
	phone.free()
	server.stop()
	await frames(2)


func test_one_request_at_a_time_and_an_unpaired_phone_is_told_to_connect() -> void:
	var server := _silent_server()
	if not check(server != null, "a local port to listen on"):
		return
	var phone := PairedPhone.new()
	phone.origin = "http://127.0.0.1:%d" % server.get_local_port()
	var bridge: Node = HelperPc.new()
	tree.root.add_child(bridge)
	var first := _start(bridge, phone)
	await frames(6)
	var second: Dictionary = await bridge.run(phone, "openai", "another", {"type": "object"}, false)
	eq(str(second.get("why", "")), "busy", "a second call while one waits is refused, not mixed in")
	check(not bool(first.done), "and the first one is not disturbed")
	eq(bridge.get_child_count(), 1)
	bridge.cancel()
	await _wait_done(first)
	var unpaired: Dictionary = await bridge.run(null, "openai", "x", {}, false)
	eq(str(unpaired.get("error", "")), "Connect to your PC first.")
	phone.token = ""
	var no_token: Dictionary = await bridge.run(phone, "openai", "x", {}, false)
	eq(str(no_token.get("why", "")), "offline")
	bridge.queue_free()
	phone.free()
	server.stop()
	await frames(2)


func test_leaving_the_tree_cancels_a_waiting_request() -> void:
	var server := _silent_server()
	if not check(server != null, "a local port to listen on"):
		return
	var phone := PairedPhone.new()
	phone.origin = "http://127.0.0.1:%d" % server.get_local_port()
	var bridge: Node = HelperPc.new()
	tree.root.add_child(bridge)
	var box := _start(bridge, phone)
	await frames(6)
	tree.root.remove_child(bridge)
	check(bridge.cancelled, "leaving the tree cancels")
	await frames(3)
	check(bool(box.done), "the waiting call ends")
	eq(str(box.result.get("why", "")), "cancelled")
	bridge.free()
	phone.free()
	server.stop()
	await frames(2)


func test_high_quality_on_a_phone_is_the_phone_setting_not_the_machine_running_the_test() -> void:
	Graphics.pressure = 0
	eq(Graphics.msaa({"graphics": "high"}, true), Viewport.MSAA_2X, "a phone at High: 2x")
	eq(Graphics.msaa({"graphics": "high"}, false), Viewport.MSAA_4X, "a PC at High: 4x")
	eq(Graphics.msaa({"graphics": "balanced"}, true), Viewport.MSAA_DISABLED, "a phone at Balanced: none")
	eq(Graphics.msaa({"graphics": "saver"}, false), Viewport.MSAA_DISABLED)
