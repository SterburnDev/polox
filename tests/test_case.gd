extends RefCounted
## Base class for test suites. Any method named test_* is run by
## tests/run_tests.gd; methods may `await`. Use check/eq to assert.

var tree: SceneTree
var failures: PackedStringArray = []
var current := ""


func check(cond: bool, msg: String = "check failed") -> bool:
	if not cond:
		failures.append("%s: %s" % [current, msg])
	return cond


func eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	var same: bool = typeof(actual) == typeof(expected) and actual == expected
	# JSON round-trips turn ints into floats; compare numbers by value.
	if not same and (actual is int or actual is float) and (expected is int or expected is float):
		same = is_equal_approx(float(actual), float(expected))
	if not same:
		failures.append("%s: %s expected <%s> but got <%s>" % [current, msg, str(expected), str(actual)])
	return same


## Points SaveManager at an empty scratch folder for this test.
func fresh_save_root(tag: String = "") -> String:
	var root := ProjectSettings.globalize_path("res://tests/.tmp_save").path_join(tag if tag != "" else current)
	preload("res://scripts/core/json_util.gd").remove_tree(root)
	SaveManager.set_root(root)
	return root


## A simulated remote peer for loopback-only network tests.
func simulated_phone_ip() -> String:
	# Never let a fixture's phone accidentally be this computer's current LAN IP.
	var own := IP.get_local_addresses()
	for i in range(1, 255):
		var candidate := "10.254.254.%d" % i
		if not candidate in own:
			return candidate
	return "192.168.254.254"


const PORT_TRIES := 24     # how often free_port asks the system before it gives up
const LISTEN_TRIES := 8    # how many different ports listen_on_free_port tries

static var _ports_given: Dictionary = {}   # every port handed out in this run (never handed out twice)


## A TCP port nobody listens on, on `address`. The system picks it (that is what listening on port
## 0 means), so a second test run, the game or any other program on this PC never gets the same
## one, which a number picked at random from a fixed range can't promise. 0 when there is none.
func free_port(address: String = "127.0.0.1") -> int:
	for _i in PORT_TRIES:
		var probe := TCPServer.new()
		if probe.listen(0, address) != OK:
			continue
		var p := probe.get_local_port()
		probe.stop()
		if p > 0 and not _ports_given.has(p):
			_ports_given[p] = true
			return p
	failures.append("%s: the system has no free TCP port on %s" % [current, address])
	return 0


## The same for UDP (the PC's announcements).
func free_udp_port(address: String = "127.0.0.1") -> int:
	for _i in PORT_TRIES:
		var probe := PacketPeerUDP.new()
		if probe.bind(0, address) != OK:
			continue
		var p := probe.get_local_port()
		probe.close()
		if p > 0 and not _ports_given.has(p):
			_ports_given[p] = true
			return p
	failures.append("%s: the system has no free UDP port on %s" % [current, address])
	return 0


## `count` free TCP ports in a row (for a server that also listens on the next one): the first.
func free_port_run(count: int, address: String = "127.0.0.1") -> int:
	for _i in PORT_TRIES:
		var first := free_port(address)
		if first == 0:
			return 0
		var all_free := true
		for k in range(1, count):
			var probe := TCPServer.new()
			all_free = all_free and not _ports_given.has(first + k) and probe.listen(first + k, address) == OK
			probe.stop()
		if all_free:
			for k in range(1, count):
				_ports_given[first + k] = true
			return first
	failures.append("%s: no %d free TCP ports in a row on %s" % [current, count, address])
	return 0


## Starts a server on a free port: `start` gets the port and returns "" (or OK) when it listens. A
## port that was taken in the meantime is not a failure: the next one is tried. Returns the port
## the server listens on; 0, with a failure noted, when LISTEN_TRIES ports all refused.
func listen_on_free_port(start: Callable, what: String = "the server", address: String = "127.0.0.1") -> int:
	var said: Variant = "no free port"
	for _i in LISTEN_TRIES:
		var p := free_port(address)
		if p == 0:
			return 0   # (free_port has noted why)
		said = start.call(p)
		if (said is String and said == "") or (said is int and said == OK) or (said is bool and said):
			return p
	failures.append("%s: %s could not listen on any free port: %s" % [current, what, str(said)])
	return 0


## Starts a UDP listener on a free port: `start` gets the port and returns "" (or OK / true).
func listen_udp_on_free_port(start: Callable, what: String = "the UDP listener", address: String = "127.0.0.1") -> int:
	var said: Variant = "no free UDP port"
	for _i in LISTEN_TRIES:
		var p := free_udp_port(address)
		if p == 0:
			return 0
		said = start.call(p)
		if (said is String and said == "") or (said is int and said == OK) or (said is bool and said):
			return p
	failures.append("%s: %s could not bind any free UDP port: %s" % [current, what, str(said)])
	return 0


## Starts a server needing `count` contiguous TCP ports: `start` gets the first port and returns "" (or OK / true).
func listen_on_free_port_run(count: int, start: Callable, what: String = "the server", address: String = "127.0.0.1") -> int:
	var said: Variant = "no free port run"
	for _i in LISTEN_TRIES:
		var p := free_port_run(count, address)
		if p == 0:
			return 0
		said = start.call(p)
		if (said is String and said == "") or (said is int and said == OK) or (said is bool and said):
			return p
	failures.append("%s: %s could not listen on any %d-port run: %s" % [current, what, count, str(said)])
	return 0


## Waits n frames (for scene nodes to settle).
func frames(n: int = 1) -> void:
	for i in n:
		await tree.process_frame
