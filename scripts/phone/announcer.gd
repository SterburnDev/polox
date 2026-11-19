extends Node
## "Polox is here": while Phone Link is on, the PC sends a tiny UDP broadcast every two seconds so
## Polox for Android finds it by itself on the home network:
##   {"polox": "pc", "v": 1, "name": "<this PC's name>", "port": 8765}
## A name and a port, never a key, PIN, world or address list (the phone sees the address the
## packet came from). Sending needs no firewall change (Windows lets programs send); the phone
## only listens. Each home adapter gets its own socket, bound to its address, so the broadcast
## leaves on that network (a socket bound to "any" lets Windows pick one adapter, often a
## virtual one). Tests and the smoke run (Phone Link on 127.0.0.1) announce to 127.0.0.1 only.

const NetRules := preload("res://scripts/phone/net_rules.gd")

const PORT := 8769          # app_link.gd listens here
const EVERY_S := 2.0

var running := false
var targets := PackedStringArray()
var dest_port := PORT
var sent := 0
var last_error := ""
var _bytes := PackedByteArray()
var _socks: Array = []      # [PacketPeerUDP, [destinations]]
var _t := 0.0


static func payload(pc: String, port: int) -> PackedByteArray:
	return JSON.stringify({"polox": "pc", "v": 1, "name": pc.substr(0, 64), "port": port}).to_utf8_buffer()


## Where to send: everyone on this PC's home networks (the limited broadcast and each private
## adapter's /24 broadcast: most home routers use a /24), or only 127.0.0.1 when Phone Link
## itself listens only there.
static func targets_for(bind: String, cands: Array) -> PackedStringArray:
	if bind == "127.0.0.1":
		return PackedStringArray(["127.0.0.1"])
	var out := PackedStringArray(["255.255.255.255"])
	for c in cands:
		var ip := str(c.get("ip", ""))
		if str(c.get("kind", "")) != "private" or bool(c.get("virtual", false)) or NetRules.ipv4_int(ip) < 0:
			continue
		var parts := ip.split(".")
		var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not b in out:
			out.append(b)
	return out


## One socket per home adapter: [[that adapter's address, [where to send]]].
static func sources_for(bind: String, cands: Array) -> Array:
	if bind == "127.0.0.1":
		return [["127.0.0.1", ["127.0.0.1"]]]
	var out: Array = []
	for c in cands:
		var ip := str(c.get("ip", ""))
		if str(c.get("kind", "")) != "private" or bool(c.get("virtual", false)) or NetRules.ipv4_int(ip) < 0:
			continue
		var parts := ip.split(".")
		out.append([ip, ["255.255.255.255", "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]]])
	return out


## Starts announcing. `sources` (from sources_for) sends from each home adapter; without it,
## one socket sends to `to` (tests: 127.0.0.1).
func start(pc: String, port: int, to: PackedStringArray, to_port: int = PORT, sources: Array = []) -> bool:
	stop()
	var plan: Array = sources if not sources.is_empty() else [["127.0.0.1" if Array(to) == ["127.0.0.1"] else "*", Array(to)]]
	last_error = ""
	for s in plan:
		var udp := PacketPeerUDP.new()
		udp.set_broadcast_enabled(true)
		var err := udp.bind(0, str(s[0]))
		if err != OK:
			last_error = "couldn't open a UDP socket on %s (%d)" % [s[0], err]
			continue   # (an adapter that went away: the others still announce)
		_socks.append([udp, s[1]])
	if _socks.is_empty():
		return false
	_bytes = payload(pc, port)
	targets = to
	dest_port = to_port
	running = true
	sent = 0
	_t = 0.0
	return true


func stop() -> void:
	for s in _socks:
		(s[0] as PacketPeerUDP).close()
	_socks.clear()
	running = false


func _process(delta: float) -> void:
	if not running:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = EVERY_S
	send_now()


func send_now() -> void:
	for s in _socks:
		var udp: PacketPeerUDP = s[0]
		for ip in s[1]:
			udp.set_dest_address(str(ip), dest_port)
			if udp.put_packet(_bytes) == OK:
				sent += 1
			else:
				last_error = "sending to %s failed" % ip   # e.g. an adapter that went away; the others still get it


func _exit_tree() -> void:
	stop()
