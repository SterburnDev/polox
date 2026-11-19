extends RefCounted
## Which addresses Phone Link shows, and which ones may talk to it.
##
## Kinds: loopback (this PC), private (home networks: 10/8, 172.16/12,
## 192.168/16, IPv6 fc00::/7), link_local (169.254/16, fe80::/10),
## tailscale (100.64/10 and fd7a:115c:a1e0::/48), public (everything else).
## Scopes: "local" = this PC only (Tailscale Serve: tailscaled proxies from
## 127.0.0.1), "tailscale" = this PC + Tailscale, "home" = this PC + home
## networks + link-local + Tailscale. Public addresses are never allowed, so
## a router port-forward made by mistake still can't reach Polox.

const SCOPES: PackedStringArray = ["local", "tailscale", "home"]
const VIRTUAL_WORDS: PackedStringArray = ["virtualbox", "vmware", "hyper-v", "vethernet", "wsl", "docker", "virtual adapter", "loopback", "npcap", "tap-windows", "wintun", "zerotier", "hamachi", "vpn",
	"nordlynx", "wireguard", "openvpn", "proton", "mullvad", "cisco", "anyconnect", "fortinet", "forticlient", "globalprotect", "pangp", "expressvpn", "surfshark", "cloudflare warp"]


## "::ffff:192.168.1.5" -> "192.168.1.5"; IPv6 lowercased; brackets and zone ids dropped.
static func normalize_ip(ip: String) -> String:
	var s := ip.strip_edges().to_lower().trim_prefix("[").trim_suffix("]")
	var zone := s.find("%")
	if zone >= 0:
		s = s.substr(0, zone)
	if s.begins_with("::ffff:") and s.count(".") == 3:
		s = s.substr(7)
	return s


static func ipv4_int(ip: String) -> int:
	var parts := ip.split(".")
	if parts.size() != 4:
		return -1
	var n := 0
	for p in parts:
		if not p.is_valid_int() or p.to_int() < 0 or p.to_int() > 255 or p.length() > 3:
			return -1
		n = (n << 8) | p.to_int()
	return n


static func in_cidr4(ip: String, base: String, bits: int) -> bool:
	var a := ipv4_int(ip)
	var b := ipv4_int(base)
	if a < 0 or b < 0:
		return false
	var mask := 0 if bits == 0 else ((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF)
	return (a & mask) == (b & mask)


## The first 16-bit groups of an IPv6 address (expanding "::"), or [] if it isn't one.
static func _ipv6_groups(ip: String) -> PackedInt32Array:
	if not ip.contains(":"):
		return PackedInt32Array()
	var halves := ip.split("::")
	if halves.size() > 2:
		return PackedInt32Array()
	var head := halves[0].split(":", false)
	var tail := halves[1].split(":", false) if halves.size() == 2 else PackedStringArray()
	var out := PackedInt32Array()
	for g in head:
		if not g.is_valid_hex_number() or g.length() > 4:
			return PackedInt32Array()
		out.append(g.hex_to_int())
	var missing := 8 - head.size() - tail.size()
	if halves.size() == 2:
		for i in missing:
			out.append(0)
	for g in tail:
		if not g.is_valid_hex_number() or g.length() > 4:
			return PackedInt32Array()
		out.append(g.hex_to_int())
	return out if out.size() == 8 else PackedInt32Array()


static func kind(raw: String) -> String:
	var ip := normalize_ip(raw)
	if ipv4_int(ip) >= 0:
		if in_cidr4(ip, "127.0.0.0", 8):
			return "loopback"
		if in_cidr4(ip, "100.64.0.0", 10):
			return "tailscale"
		if in_cidr4(ip, "10.0.0.0", 8) or in_cidr4(ip, "172.16.0.0", 12) or in_cidr4(ip, "192.168.0.0", 16):
			return "private"
		if in_cidr4(ip, "169.254.0.0", 16):
			return "link_local"
		return "public"
	var g := _ipv6_groups(ip)
	if g.is_empty():
		return "invalid"
	if g == PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 1]):
		return "loopback"
	if g[0] == 0xfd7a and g[1] == 0x115c and g[2] == 0xa1e0:
		return "tailscale"
	if (g[0] & 0xffc0) == 0xfe80:
		return "link_local"
	if (g[0] & 0xfe00) == 0xfc00:
		return "private"
	return "public"


static func source_allowed(ip: String, scope: String) -> bool:
	var k := kind(ip)
	match scope:
		"local":
			return k == "loopback"
		"tailscale":
			return k in ["loopback", "tailscale"]
		"home":
			return k in ["loopback", "private", "link_local", "tailscale"]
	return false


# --- Address ranking ------------------------------------------------------------------------------

## Default routes from `route print -4` (numbers only, so any Windows language):
## [{gateway, interface_ip, metric}], lowest metric first.
static func parse_default_routes(text: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("(?m)^\\s*0\\.0\\.0\\.0\\s+0\\.0\\.0\\.0\\s+(\\S+)\\s+(\\d+\\.\\d+\\.\\d+\\.\\d+)\\s+(\\d+)")
	for m in re.search_all(text):
		out.append({"gateway": m.get_string(1), "interface_ip": m.get_string(2), "metric": m.get_string(3).to_int()})
	out.sort_custom(func(a, b): return int(a.metric) < int(b.metric))
	return out


## Adapter descriptions by interface index, from the same `route print` text.
static func parse_interface_list(text: String) -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("(?m)^\\s*(\\d+)\\.\\.\\.(?:[0-9a-fA-F]{2} )*\\.*(.+?)\\s*$")
	for m in re.search_all(text):
		out[m.get_string(1).to_int()] = m.get_string(2).strip_edges()
	return out


static func looks_virtual(label: String, ip: String = "") -> bool:
	var l := label.to_lower()
	for w in VIRTUAL_WORDS:
		if l.contains(w):
			return true
	return ip.begins_with("192.168.56.")   # VirtualBox host-only, even when it has a plain name


## Every IPv4 address a phone might use, best first:
##   0 Tailscale, 1 the adapter with the default gateway (your home network),
##   2 other home-network adapters, 3 virtual adapters (a phone can't reach those).
## Loopback, link-local and IPv6 are left out. `interfaces` is IP.get_local_interfaces();
## `routes_text` is `route print -4` output ("" = unknown).
static func rank_addresses(interfaces: Array, routes_text: String = "") -> Array:
	var gateways := {}
	for r in parse_default_routes(routes_text):
		gateways[str(r.interface_ip)] = int(r.metric)
	var descriptions := parse_interface_list(routes_text)
	var out: Array = []
	var seen := {}
	for itf in interfaces:
		var name := "%s" % str(itf.get("friendly", itf.get("name", "")))
		var desc := str(descriptions.get(int(str(itf.get("index", "-1"))), ""))
		for a in itf.get("addresses", []):
			var ip := normalize_ip(str(a))
			if ipv4_int(ip) < 0 or seen.has(ip):
				continue
			var k := kind(ip)
			if k in ["loopback", "link_local", "public", "invalid"] and not (k == "public" and gateways.has(ip)):
				continue
			seen[ip] = true
			var rank := 2
			var why := "home network"
			var virtual := false
			if k == "tailscale" or name.to_lower().contains("tailscale") or desc.to_lower().contains("tailscale"):
				rank = 0
				why = "Tailscale"
				k = "tailscale"
			elif looks_virtual(name + " " + desc, ip):
				# Checked before the default route: a full-tunnel VPN has one too (often the best metric).
				rank = 3
				why = "virtual or VPN adapter: a phone can't reach it"
				virtual = true
			elif gateways.has(ip):
				rank = 1
				why = "home network (has the internet route)"
			out.append({"ip": ip, "kind": k, "label": name, "description": desc, "rank": rank, "reason": why, "virtual": virtual, "metric": int(gateways.get(ip, 9999))})
	out.sort_custom(func(a, b): return int(a.rank) < int(b.rank) or (int(a.rank) == int(b.rank) and int(a.metric) < int(b.metric)))
	return out


## Every address of this PC (so its own self-tests aren't mistaken for a phone).
static func own_addresses() -> Dictionary:
	var out := {}
	for a in IP.get_local_addresses():
		out[normalize_ip(str(a))] = true
	return out


## This PC's `route print -4` (a few ms; "" if it can't be run).
static func system_routes_text() -> String:
	if OS.get_name() != "Windows":
		return ""
	var out: Array = []
	var code := OS.execute("route", ["print", "-4"], out, true)
	return str(out[0]) if code == 0 and not out.is_empty() else ""
