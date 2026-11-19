extends RefCounted
## Tailscale, through its own command-line tool (never its files):
##   status  - `tailscale status --json`: running, logged in, this PC's name and
##             100.x address, MagicDNS, HTTPS certificates, your login
##   serve   - `tailscale serve status --json`, and Polox's own mapping:
##             on:  tailscale serve --bg --https=<port> http://127.0.0.1:<local>
##             off: tailscale serve --https=<port> off     (only that port, never a reset)
##   funnel  - read from the same status (AllowFunnel); Polox never turns it on
## (Serve's command line changed in Tailscale 1.52; these are the current forms.)
## Tests swap `runner` for a fake that returns recorded output.

const DEFAULT_PATHS: PackedStringArray = [
	"C:/Program Files/Tailscale/tailscale.exe",
	"C:/Program Files (x86)/Tailscale/tailscale.exe",
	"/usr/bin/tailscale", "/usr/local/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
]

var cli := ""
## (args: PackedStringArray, timeout_s: float) -> {code: int, out: String}
var runner: Callable = Callable()


func _init(cli_path: String = "") -> void:
	cli = cli_path if cli_path != "" else find_cli()


static func find_cli() -> String:
	for p in DEFAULT_PATHS:
		if FileAccess.file_exists(p):
			return p
	return ""


func installed() -> bool:
	return cli != "" or runner.is_valid()


## Runs the CLI with a time limit (a stuck command is killed, never waited on forever).
func run(args: PackedStringArray, timeout_s: float = 10.0) -> Dictionary:
	if runner.is_valid():
		return runner.call(args, timeout_s)
	if cli == "":
		return {"code": -1, "out": "Tailscale isn't installed."}
	var p: Dictionary = OS.execute_with_pipe(cli, args, false)
	if p.is_empty():
		return {"code": -1, "out": "Couldn't start tailscale."}
	var pid := int(p.pid)
	var io: FileAccess = p.stdio
	var err: FileAccess = p.stderr
	var buf := PackedByteArray()
	var t := Time.get_ticks_msec()
	while true:
		buf.append_array(io.get_buffer(65536))
		buf.append_array(err.get_buffer(65536))
		if not OS.is_process_running(pid):
			buf.append_array(io.get_buffer(1 << 20))
			buf.append_array(err.get_buffer(1 << 20))
			break
		if Time.get_ticks_msec() - t > int(timeout_s * 1000.0):
			OS.kill(pid)
			return {"code": -2, "out": buf.get_string_from_utf8() + "\n(timed out)"}
		OS.delay_msec(15)
	return {"code": OS.get_process_exit_code(pid), "out": buf.get_string_from_utf8()}


# --- status ------------------------------------------------------------------------------------

func status() -> Dictionary:
	if not installed():
		return parse_status("", false)
	var r := run(PackedStringArray(["status", "--json"]), 8.0)
	var s := parse_status(str(r.out), true)
	if int(r.code) != 0 and s.error == "":
		s.error = str(r.out).strip_edges().substr(0, 200)
	return s


## Summary of `tailscale status --json` (never anything secret: no keys, no auth URLs).
static func parse_status(text: String, is_installed: bool = true) -> Dictionary:
	var s := {
		"installed": is_installed, "running": false, "logged_in": false, "backend": "",
		"dns_name": "", "host": "", "ipv4": "", "ips": [], "magicdns": false, "https": false,
		"login": "", "tailnet": "", "peers": [], "error": "",
	}
	if not is_installed:
		s.error = "Tailscale isn't installed on this PC."
		return s
	var data: Variant = JSON.parse_string(text) if text.strip_edges().begins_with("{") else null
	if not data is Dictionary:
		s.error = "Tailscale didn't answer (is it running?)." if text.strip_edges() == "" else text.strip_edges().substr(0, 200)
		return s
	s.backend = str(data.get("BackendState", ""))
	s.running = s.backend == "Running"
	s.logged_in = s.backend in ["Running", "Starting"]
	var me: Dictionary = data.get("Self", {}) if data.get("Self") is Dictionary else {}
	s.dns_name = str(me.get("DNSName", "")).trim_suffix(".")
	s.host = str(me.get("HostName", ""))
	var ips: Array = me.get("TailscaleIPs", []) if me.get("TailscaleIPs") is Array else []
	s.ips = ips
	for ip in ips:
		if str(ip).count(".") == 3:
			s.ipv4 = str(ip)
			break
	var tn: Dictionary = data.get("CurrentTailnet", {}) if data.get("CurrentTailnet") is Dictionary else {}
	s.tailnet = str(tn.get("Name", ""))
	s.magicdns = bool(tn.get("MagicDNSEnabled", str(data.get("MagicDNSSuffix", "")) != ""))
	var certs: Array = data.get("CertDomains", []) if data.get("CertDomains") is Array else []
	s.https = s.dns_name != "" and s.dns_name in certs
	var users: Dictionary = data.get("User", {}) if data.get("User") is Dictionary else {}
	var uid := _id(me.get("UserID", ""))
	for k in users:
		if users[k] is Dictionary and (str(k) == uid or _id(users[k].get("ID", "")) == uid):
			s.login = str(users[k].get("LoginName", ""))
	var peers: Dictionary = data.get("Peer", {}) if data.get("Peer") is Dictionary else {}
	for k in peers:
		var p: Dictionary = peers[k]
		var pips: Array = p.get("TailscaleIPs", []) if p.get("TailscaleIPs") is Array else []
		s.peers.append({"name": str(p.get("HostName", "")), "os": str(p.get("OS", "")), "online": bool(p.get("Online", false)), "ip": str(pips[0]) if not pips.is_empty() else ""})
	if s.backend == "NeedsLogin":
		s.error = "Tailscale is installed but not logged in."
	elif s.backend == "Stopped":
		s.error = "Tailscale is switched off (open it and connect)."
	return s


## JSON numbers arrive as floats: 123.0 -> "123".
static func _id(v: Variant) -> String:
	if v is float or v is int:
		return str(int(v))
	return str(v)


# --- serve ---------------------------------------------------------------------------------------

func serve_status(dns_name: String) -> Dictionary:
	if not installed():
		return parse_serve_status("", dns_name)
	var r := run(PackedStringArray(["serve", "status", "--json"]), 8.0)
	return parse_serve_status(str(r.out), dns_name)


## {ports: {"443": {https, proxy}}, funnel: {"443": true}}: who uses which HTTPS port.
static func parse_serve_status(text: String, dns_name: String) -> Dictionary:
	var out := {"ports": {}, "funnel": {}}
	var data: Variant = JSON.parse_string(text) if text.strip_edges().begins_with("{") else null
	if not data is Dictionary:
		return out
	var tcp: Dictionary = data.get("TCP", {}) if data.get("TCP") is Dictionary else {}
	for p in tcp:
		out.ports[str(p)] = {"https": bool(tcp[p].get("HTTPS", false)), "proxy": str(tcp[p].get("TCPForward", ""))}
	var web: Dictionary = data.get("Web", {}) if data.get("Web") is Dictionary else {}
	for hostport in web:
		var port := str(hostport).get_slice(":", str(hostport).count(":"))
		var handlers: Dictionary = web[hostport].get("Handlers", {}) if web[hostport].get("Handlers") is Dictionary else {}
		var root: Dictionary = handlers.get("/", {}) if handlers.get("/") is Dictionary else {}
		if not out.ports.has(port):
			out.ports[port] = {"https": true, "proxy": ""}
		out.ports[port].proxy = str(root.get("Proxy", out.ports[port].proxy))
	var fun: Dictionary = data.get("AllowFunnel", {}) if data.get("AllowFunnel") is Dictionary else {}
	for hostport in fun:
		if bool(fun[hostport]):
			out.funnel[str(hostport).get_slice(":", str(hostport).count(":"))] = true
	return out


## The Serve command that publishes 127.0.0.1:<local> as https://<name>:<https_port>.
static func serve_on_args(https_port: int, local_port: int) -> PackedStringArray:
	return PackedStringArray(["serve", "--bg", "--https=%d" % https_port, "http://127.0.0.1:%d" % local_port])


static func serve_off_args(https_port: int) -> PackedStringArray:
	return PackedStringArray(["serve", "--https=%d" % https_port, "off"])


## Publishes Polox on the tailnet. Refuses to take over a port another app
## already uses. Returns {ok, error, consent_url, funnel}.
func serve_on(https_port: int, local_port: int, dns_name: String) -> Dictionary:
	var before := serve_status(dns_name)
	var mine := "http://127.0.0.1:%d" % local_port
	var used: Dictionary = before.ports.get(str(https_port), {})
	if not used.is_empty() and str(used.get("proxy", "")) != mine:
		return {"ok": false, "error": "HTTPS port %d is already used by another Tailscale Serve mapping (%s). Pick another Serve port." % [https_port, str(used.get("proxy", "?"))], "consent_url": "", "funnel": false}
	var r := run(serve_on_args(https_port, local_port), 20.0)
	var url := find_consent_url(str(r.out))
	if url != "":
		return {"ok": false, "error": "Your tailnet needs HTTPS certificates switched on first (one click in the Tailscale admin page).", "consent_url": url, "funnel": false}
	if int(r.code) != 0:
		return {"ok": false, "error": "tailscale serve failed: " + str(r.out).strip_edges().substr(0, 300), "consent_url": "", "funnel": false}
	var after := serve_status(dns_name)
	var got: Dictionary = after.ports.get(str(https_port), {})
	if str(got.get("proxy", "")) != mine:
		return {"ok": false, "error": "Tailscale didn't keep the mapping (serve status doesn't show it).", "consent_url": "", "funnel": false}
	return {"ok": true, "error": "", "consent_url": "", "funnel": after.funnel.has(str(https_port))}


## Removes only Polox's own mapping (and only if it still points at Polox).
func serve_off(https_port: int, local_port: int, dns_name: String) -> Dictionary:
	var now := serve_status(dns_name)
	var used: Dictionary = now.ports.get(str(https_port), {})
	if used.is_empty():
		return {"ok": true, "error": ""}
	if str(used.get("proxy", "")) != "http://127.0.0.1:%d" % local_port:
		return {"ok": false, "error": "Port %d now belongs to another mapping; left it alone." % https_port}
	var r := run(serve_off_args(https_port), 15.0)
	return {"ok": int(r.code) == 0, "error": "" if int(r.code) == 0 else str(r.out).strip_edges().substr(0, 300)}


## The "enable HTTPS / Serve" page Tailscale prints when the tailnet isn't set up for it.
static func find_consent_url(out: String) -> String:
	var re := RegEx.create_from_string("https://login\\.tailscale\\.com/\\S+")
	var m := re.search(out)
	return m.get_string().trim_suffix(".") if m else ""
