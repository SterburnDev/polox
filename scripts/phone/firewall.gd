extends RefCounted
## Windows Firewall, read-only from Polox: are there "block" rules for
## Polox's programs (Windows makes those when its "allow access?" prompt is
## dismissed), and do rules let Polox's ports in on the network types in use?
## Changing anything is the user's call: allow_phone_link.bat (shows exactly
## what it will do, asks Windows for admin rights, asks Y/N, has an Undo that
## also puts back the block rules it removed). Tailscale Serve needs no rule.

const SCRIPT := "res://tools/phone_link_firewall.ps1"
const HELPER := "res://allow_phone_link.bat"
## Phone Link's safe ports and Polox Ping's (the helper allows all of them).
const PORTS: Array = [8765, 8766, 8767, 8080, 8888]


static func available() -> bool:
	return OS.get_name() == "Windows" and FileAccess.file_exists(ProjectSettings.globalize_path(SCRIPT))


## {ok, known, blocking, allowed, profiles[], networks[], rules[], missing[], error}. Takes ~2 s (PowerShell).
static func check(port: int = 0) -> Dictionary:
	var out := {"ok": false, "known": false, "blocking": 0, "allowed": false, "profiles": [], "networks": [], "rules": [], "missing": [], "error": ""}
	if not available():
		out.error = "Firewall check is only available on Windows."
		return out
	var ports: Array = PORTS.duplicate()
	if port > 0 and not port in ports:
		ports.push_front(port)
	var res: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path(SCRIPT), "-Action", "check", "-Ports", ",".join(PackedStringArray(ports.map(func(p): return str(p)))), "-Json"], res, true)
	var text := str(res[0]) if not res.is_empty() else ""
	return parse_check(text, code)


static func parse_check(text: String, code: int = 0) -> Dictionary:
	var out := {"ok": false, "known": false, "blocking": 0, "allowed": false, "profiles": [], "networks": [], "rules": [], "missing": [], "error": ""}
	var start := text.find("{")
	var data: Variant = JSON.parse_string(text.substr(start)) if start >= 0 else null
	if code != 0 or not data is Dictionary:
		out.error = "Couldn't read the firewall (%s)." % text.strip_edges().substr(0, 160)
		return out
	out.known = true
	out.ok = bool(data.get("ok", false))
	out.blocking = int(data.get("blocking", 0))
	out.allowed = bool(data.get("allowed", false))
	out.profiles = _list(data.get("profiles_in_use"))
	out.networks = _list(data.get("networks"))
	out.rules = _list(data.get("rules"))
	out.missing = _list(data.get("missing"))
	return out


static func _list(v: Variant) -> Array:
	if v is Array:
		return v
	return [] if v == null else [v]


## Opens the helper in its own window (it shows its plan; Windows then asks for admin rights). Never silent.
static func open_helper(_port: int = 0, action: String = "allow") -> void:
	var bat := ProjectSettings.globalize_path(HELPER)
	OS.create_process("cmd.exe", ["/c", "start", "Polox firewall helper", bat, action])
