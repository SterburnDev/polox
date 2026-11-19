extends RefCounted
## Rung R0 of the connection ladder: facts about this PC (tools/net_facts.ps1,
## read-only) and what they mean for a phone trying to reach Polox.
##   listening sockets and the program that owns each; the adapter with the
##   default route (the one the phone's address should be on) and the others
##   (virtual, VPN, link-local); the network profile (Public / Private); the
##   firewall profiles ("block all incoming" ignores every allow rule); rules
##   for the exact programs (a Block rule beats an Allow rule), rules that block
##   every program (unless they're limited to another Windows account); other
##   security products; how soon the PC sleeps.
## collect() blocks for a few seconds (PowerShell): call it on a thread.
## analyze() is pure (tests feed it sample facts).

const NetRules := preload("res://scripts/phone/net_rules.gd")

const SCRIPT := "res://tools/net_facts.ps1"
const VPN_WORDS: PackedStringArray = ["vpn", "wireguard", "openvpn", "tap-windows", "wintun", "nordlynx", "proton", "cisco", "anyconnect", "fortinet", "forticlient", "globalprotect", "pangp", "zerotier", "hamachi", "mullvad", "expressvpn", "surfshark", "warp", "cloudflare"]
const VIRTUAL_WORDS: PackedStringArray = ["virtualbox", "vmware", "hyper-v", "vethernet", "wsl", "docker", "loopback", "npcap", "wi-fi direct", "bluetooth", "kernel debug", "teredo", "6to4", "isatap"]


static func available() -> bool:
	return OS.get_name() == "Windows" and FileAccess.file_exists(ProjectSettings.globalize_path(SCRIPT))


## The Godot programs Polox runs as (and later the bundled web server).
static func polox_programs() -> PackedStringArray:
	var dir := ProjectSettings.globalize_path("res://tools/godot")
	var out := PackedStringArray()
	for n in ["Godot_v4.7.2-stable_win64.exe", "Godot_v4.7.2-stable_win64_console.exe"]:
		var p := dir.path_join(n).replace("/", "\\")
		if FileAccess.file_exists(p):
			out.append(p)
	var me := OS.get_executable_path().replace("/", "\\")
	if me != "" and not me in out:
		out.append(me)
	return out


## Runs the facts script (a few seconds). {} plus "error" if it couldn't.
static func collect(ports: Array, programs: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not available():
		return {"ok": false, "error": "PC facts are only available on Windows."}
	var progs := programs if not programs.is_empty() else polox_programs()
	var res: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path(SCRIPT),
		"-Ports", ",".join(PackedStringArray(ports.map(func(p): return str(p)))), "-Exes", ";".join(progs)], res, true)
	return parse(str(res[0]) if not res.is_empty() else "", code)


static func parse(text: String, code: int = 0) -> Dictionary:
	var start := text.find("{")
	var data: Variant = JSON.parse_string(text.substr(start)) if start >= 0 else null
	if code != 0 or not data is Dictionary:
		return {"ok": false, "error": "Couldn't read this PC's network facts (%s)." % text.strip_edges().substr(0, 160)}
	var d: Dictionary = data
	for k in ["listening", "adapters", "rules", "firewall_profiles", "security_products", "vpn_connections", "errors"]:
		d[k] = _as_array(d.get(k))
	for a in d.adapters:
		if a is Dictionary:
			a["ipv4"] = _as_array(a.get("ipv4"))
	return d


## PowerShell's JSON turns a one-item list into the item itself.
static func _as_array(v: Variant) -> Array:
	if v is Array:
		return v
	if v == null:
		return []
	return [v]


# --- Reading the facts --------------------------------------------------------------------------------

## Does a rule's LocalPort ("Any", "8737", "8765,8080", "8000-9000") include `port`?
static func port_covered(spec: String, port: int) -> bool:
	var s := spec.strip_edges()
	if s == "" or s.to_lower() == "any":
		return true
	for part in s.split(",", false):
		var p := part.strip_edges()
		if p.contains("-"):
			var a := p.get_slice("-", 0).strip_edges()
			var b := p.get_slice("-", 1).strip_edges()
			if a.is_valid_int() and b.is_valid_int() and port >= a.to_int() and port <= b.to_int():
				return true
		elif p.is_valid_int() and p.to_int() == port:
			return true
	return false


static func profile_covered(spec: String, profile: String) -> bool:
	var s := spec.to_lower()
	return s == "" or s == "any" or s.contains(profile.to_lower())


## The Windows accounts a rule is limited to (SIDs from its LocalUser SDDL); [] = everyone.
static func rule_users(sddl: String) -> PackedStringArray:
	var out := PackedStringArray()
	if sddl == "" or sddl.to_lower() == "any":
		return out
	var re := RegEx.create_from_string("S-1-[0-9-]+")
	for m in re.search_all(sddl):
		out.append(m.get_string())
	return out


## Does a rule apply to programs run by `user_sid`?
static func applies_to_user(rule: Dictionary, user_sid: String) -> bool:
	var users := rule_users(str(rule.get("local_user", "")))
	return users.is_empty() or user_sid in users


static func adapter_ips(a: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for s in a.get("ipv4", []):
		out.append(str(s).get_slice("/", 0))
	return out


static func is_vpn(a: Dictionary) -> bool:
	var l := (str(a.get("name", "")) + " " + str(a.get("description", ""))).to_lower()
	if l.contains("tailscale"):
		return false
	for w in VPN_WORDS:
		if l.contains(w):
			return true
	return false


static func is_virtual(a: Dictionary) -> bool:
	var l := (str(a.get("name", "")) + " " + str(a.get("description", ""))).to_lower()
	for w in VIRTUAL_WORDS:
		if l.contains(w):
			return true
	for ip in adapter_ips(a):
		if ip.begins_with("192.168.56."):
			return true
	return false


## The adapter a phone on the same Wi-Fi should use: up, with the default route, not virtual/VPN.
static func home_adapter(facts: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for a in facts.get("adapters", []):
		if not a is Dictionary or str(a.get("status", "")) != "Up" or not bool(a.get("default_route", false)):
			continue
		if is_vpn(a) or is_virtual(a) or adapter_ips(a).is_empty():
			continue
		if best.is_empty() or int(a.get("metric", 9999)) < int(best.get("metric", 9999)):
			best = a
	return best


static func _r(id: String, title: String, status: String, detail: String, fix: String = "", action: String = "", arg: String = "") -> Dictionary:
	var r := {"id": id, "title": title, "status": status, "detail": detail, "fix": fix}
	if action != "":   # a one-click fix (fix_actions.gd)
		r["action"] = action
		r["arg"] = arg
	return r


## What the facts mean, in the order a person would fix things. ctx:
##   ports: [ports Polox should be listening on], programs: [exe paths],
##   server: "ping" | "host" (whose listening sockets to expect)
static func analyze(facts: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	if not bool(facts.get("ok", false)) and not facts.has("adapters"):
		out.append(_r("facts", "PC facts", "warn", str(facts.get("error", "Couldn't read them.")), "Run phone_doctor.bat to try again."))
		return out
	var ports: Array = ctx.get("ports", [])
	var programs: Array = Array(ctx.get("programs", []))
	var lowered := programs.map(func(p): return str(p).to_lower())
	var user := str(facts.get("user_sid", ""))
	# 1. Listening: on every address (0.0.0.0), by Polox's own program.
	for p in ports:
		var socks: Array = facts.listening.filter(func(l): return int(l.get("port", 0)) == int(p))
		if socks.is_empty():
			out.append(_r("listen_%d" % int(p), "Listening on port %d" % int(p), "fail", "Nothing is listening on port %d right now." % int(p), "Start it (Polox Ping or Phone Link) and keep the window open."))
			continue
		var all_addrs := socks.filter(func(l): return str(l.address) in ["0.0.0.0", "::", "0:0:0:0:0:0:0:0"])
		var owner := str(socks[0].get("path", ""))
		var owner_name := str(socks[0].get("process", "?"))
		if all_addrs.is_empty():
			out.append(_r("listen_%d" % int(p), "Listening on port %d" % int(p), "fail", "Port %d only listens on %s, so a phone can't reach it." % [int(p), ", ".join(PackedStringArray(socks.map(func(l): return str(l.address))))], "Switch it off and on; if it keeps happening, tell me (it should be 0.0.0.0)."))
		elif owner != "" and not owner.to_lower() in lowered and not owner_name.to_lower().begins_with("godot"):
			out.append(_r("listen_%d" % int(p), "Listening on port %d" % int(p), "fail", "Port %d belongs to another program: %s (%s)." % [int(p), owner_name, owner], "Close that program, or let Polox use another port."))
		else:
			out.append(_r("listen_%d" % int(p), "Listening on port %d" % int(p), "ok", "Every address of this PC (0.0.0.0) on port %d, by %s." % [int(p), owner_name if owner_name != "" else "Polox"]))
			if owner != "" and not owner.to_lower() in lowered:
				programs.append(owner)
				lowered.append(owner.to_lower())
	# 2. The address for the phone: the adapter with the internet route.
	var home := home_adapter(facts)
	if home.is_empty():
		out.append(_r("adapter", "Home network adapter", "fail", "This PC has no connected Wi-Fi or Ethernet adapter with a route to your router.", "Connect the PC to your home Wi-Fi or router, then try again."))
	else:
		var ips := adapter_ips(home)
		var ip := ips[0] if not ips.is_empty() else "?"
		var kind := NetRules.kind(ip)
		out.append(_r("adapter", "Home network adapter", "ok" if kind == "private" else "warn", "%s (%s): %s, router %s." % [str(home.name), str(home.description), ip, str(home.get("gateway", "?"))],
			"" if kind == "private" else "That isn't a home-network address (%s): is this PC behind another router, or on a work/guest network?" % kind))
	var others := PackedStringArray()
	var vpns := PackedStringArray()
	for a in facts.adapters:
		if not a is Dictionary or str(a.get("status", "")) != "Up" or a == home:
			continue
		if is_vpn(a):
			vpns.append("%s (%s)" % [str(a.name), str(a.description)])
		elif not adapter_ips(a).is_empty() and not str(a.name).to_lower().contains("tailscale"):
			others.append("%s %s%s" % [str(a.name), ", ".join(adapter_ips(a)), " (virtual: a phone can't use it)" if is_virtual(a) else ""])
	for v in facts.get("vpn_connections", []):
		if v is Dictionary and str(v.get("status", "")) == "Connected":
			vpns.append("%s (Windows VPN)" % str(v.name))
	if not vpns.is_empty():
		out.append(_r("vpn", "VPN on this PC", "warn", "A VPN is on: %s. Some VPNs block devices on your home network." % ", ".join(vpns), "Disconnect the VPN while testing, or allow \"local network access\" in its settings."))
	if not others.is_empty():
		out.append(_r("other_adapters", "Other adapters", "ok", "Not for the phone: %s." % "; ".join(others)))
	# 3. Network profile of the home adapter.
	var profile := str(home.get("profile", "")) if not home.is_empty() else ""
	if profile == "Public":
		out.append(_r("profile", "Network type", "warn", "\"%s\" is set to Public: Windows refuses new incoming connections unless a rule allows them." % str(home.get("network", home.name)), "If it's your home network: Windows Settings > Network & internet > %s > Network profile type: Private. Polox never changes this itself." % ("Wi-Fi" if str(home.name).to_lower().contains("wi") else "Ethernet"), "network_settings", str(home.name)))
	elif profile != "":
		out.append(_r("profile", "Network type", "ok", "\"%s\" is %s." % [str(home.get("network", home.name)), profile]))
	# 4. Firewall profiles.
	var fw_on := false
	for fp in facts.get("firewall_profiles", []):
		if not fp is Dictionary:
			continue
		if profile != "" and str(fp.name) != profile:
			continue
		fw_on = fw_on or bool(fp.enabled)
		if bool(fp.enabled) and not bool(fp.get("allow_inbound_rules", true)):
			out.append(_r("shields_up", "Block all incoming connections", "fail", "Windows Firewall (%s) is set to block ALL incoming connections, so every allow rule is ignored." % str(fp.name), "Windows Security > Firewall & network protection > %s network: untick \"Block all incoming connections\"." % str(fp.name), "firewall_settings"))
		if bool(fp.enabled) and not bool(fp.get("allow_local_rules", true)):
			out.append(_r("gpo", "Firewall managed elsewhere", "fail", "Local firewall rules are switched off (%s profile, set by an administrator or policy), so Polox's allow rule can't work." % str(fp.name), "Ask whoever manages this PC, or use Tailscale."))
	# 5. Rules for Polox's programs, and rules that block every program.
	var blocks := PackedStringArray()
	var allow_ports := {}
	for r in facts.get("rules", []):
		if not r is Dictionary or not bool(r.get("enabled", false)):
			continue
		var prog := str(r.get("program", "Any"))
		var for_polox := prog.to_lower() in lowered
		if not for_polox and prog.to_lower() != "any":
			continue
		if not applies_to_user(r, user):
			if str(r.action) == "Block":
				out.append(_r("rule_other_user", "Block rule for another account", "ok", "\"%s\" blocks incoming connections only for another Windows account, not for Polox." % str(r.name)))
			continue
		if profile != "" and not profile_covered(str(r.profile), profile):
			continue
		if str(r.action) == "Block":
			blocks.append("\"%s\" (%s, port %s%s)" % [str(r.name), str(r.profile), str(r.port), "" if for_polox else ", every program"])
		elif for_polox and str(r.get("protocol", "")) in ["TCP", "Any", ""]:
			for p in ports:
				if port_covered(str(r.port), int(p)):
					allow_ports[int(p)] = true
	if not fw_on:
		out.append(_r("firewall", "Windows Firewall", "ok", "Off for the %s network: it doesn't stop phones." % (profile if profile != "" else "home")))
	elif not blocks.is_empty():
		out.append(_r("firewall", "Windows Firewall", "fail", "Block rule(s) stop phones: %s. A Block rule beats any Allow rule." % ", ".join(blocks), "Double-click allow_phone_link.bat: it shows what it will do, removes only block rules for Polox's programs, and can be undone.", "firewall_helper"))
	else:
		var missing := ports.filter(func(p): return not allow_ports.has(int(p)))
		if missing.is_empty():
			out.append(_r("firewall", "Windows Firewall", "ok", "Polox's program is allowed in on port%s %s (%s network)." % ["" if ports.size() == 1 else "s", ", ".join(PackedStringArray(ports.map(func(p): return str(p)))), profile]))
		else:
			out.append(_r("firewall", "Windows Firewall", "fail", "No rule lets port%s %s in for Polox on your %s network, so Windows silently drops the phone's connection." % ["" if missing.size() == 1 else "s", ", ".join(PackedStringArray(missing.map(func(p): return str(p)))), profile if profile != "" else "home"], "Double-click allow_phone_link.bat (it explains, asks for admin rights, and can be undone), or click Allow when Windows asks.", "firewall_helper"))
	# 6. Other security products.
	var others_sec := PackedStringArray()
	for s in facts.get("security_products", []):
		if s is Dictionary and not str(s.get("name", "")).to_lower().contains("windows defender") and not str(s.get("name", "")).to_lower().contains("microsoft defender"):
			others_sec.append("%s (%s)" % [str(s.name), "firewall" if str(s.kind) == "FirewallProduct" else "antivirus"])
	if not others_sec.is_empty():
		out.append(_r("security", "Other security software", "warn", "%s may have its own firewall that blocks phones." % ", ".join(others_sec), "In its settings, allow Polox (tools\\godot\\Godot_v4.7.2-stable_win64.exe) on private/home networks."))
	# 7. Sleep.
	var ac := int(facts.get("sleep_ac_seconds", -1))
	if ac > 0 and bool(ctx.get("keep_awake", false)):
		out.append(_r("sleep", "PC sleep", "ok", "Windows would sleep after %d minutes without use, but Polox keeps this PC awake while it's on." % roundi(ac / 60.0)))
	elif ac > 0:
		out.append(_r("sleep", "PC sleep", "warn", "This PC sleeps after %d minutes without use (plugged in). Asleep, it can't answer the phone." % roundi(ac / 60.0), "Phone Link > Keep this PC awake while Phone Link is on (or Windows Settings > System > Power > Screen and sleep).", "keep_awake"))
	elif ac == 0:
		out.append(_r("sleep", "PC sleep", "ok", "This PC doesn't sleep on its own when plugged in."))
	if not home.is_empty() and str(home.get("power_off_allowed", "")) == "True":
		out.append(_r("adapter_power", "Adapter power saving", "warn", "Windows may switch the %s adapter off to save power." % str(home.name), "Device Manager > Network adapters > %s > Power Management: untick \"Allow the computer to turn off this device\"." % str(home.description), "device_manager"))
	return out


## Plain text of the facts, for Copy diagnostics (no secrets in here: addresses, rule names, settings).
static func text(facts: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("PC: %s, %s" % [str(facts.get("computer", "")), str(facts.get("windows", ""))])
	for a in facts.get("adapters", []):
		if a is Dictionary and (str(a.get("status", "")) == "Up" or bool(a.get("default_route", false))):
			lines.append("  adapter %s [%s] %s %s%s%s" % [str(a.name), str(a.description), str(a.status), ", ".join(adapter_ips(a)), (" route via " + str(a.gateway)) if bool(a.get("default_route", false)) else "", (" profile " + str(a.profile)) if str(a.get("profile", "")) != "" else ""])
	for l in facts.get("listening", []):
		if l is Dictionary:
			lines.append("  listening %s:%d pid %d %s" % [str(l.address), int(l.port), int(l.pid), str(l.get("path", l.get("process", "")))])
	for f in facts.get("firewall_profiles", []):
		if f is Dictionary:
			lines.append("  firewall %s enabled=%s inbound=%s allow_rules=%s" % [str(f.name), str(f.enabled), str(f.default_inbound), str(f.allow_inbound_rules)])
	for r in facts.get("rules", []):
		if r is Dictionary:
			lines.append("  rule %s %s %s %s %s port %s program %s%s" % [str(r.action), "on" if bool(r.enabled) else "off", str(r.profile), str(r.name), str(r.protocol), str(r.port), str(r.program), (" users " + ",".join(rule_users(str(r.get("local_user", ""))))) if not rule_users(str(r.get("local_user", ""))).is_empty() else ""])
	for s in facts.get("security_products", []):
		if s is Dictionary:
			lines.append("  security %s %s" % [str(s.kind), str(s.name)])
	lines.append("  sleep after %s s (AC), %s s (battery)" % [str(facts.get("sleep_ac_seconds", "?")), str(facts.get("sleep_dc_seconds", "?"))])
	for e in facts.get("errors", []):
		lines.append("  note: " + str(e))
	return "\n".join(lines)
