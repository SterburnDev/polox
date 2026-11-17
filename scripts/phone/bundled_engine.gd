extends Node
## Plan B: the bundled web server engine (Caddy, pinned, fetched by
## tools/fetch_server.bat). When chosen, Caddy faces the network on Polox's
## port (0.0.0.0) as a child process: it serves the game files from the Web
## build itself (mature HTTP: partial reads, slow clients, MIME) and passes
## everything else (the launcher, /api, /test, /ping, /reset, /hello) to
## Polox's own server, which then listens on 127.0.0.1 only. Caddy refuses
## anything that isn't a home-network or Tailscale address, and tells Polox
## who the phone is with a per-start secret header (X-Polox-Proxy) so that
## nobody else can claim to be the proxy. Started and stopped with Phone Link,
## killed when Polox exits, and a leftover one (after a crash) is stopped on
## the next start, but only if that process really is Caddy.

const VERSION := "2.11.4"
const EXE := "res://tools/server/caddy.exe"
const FETCH := "res://tools/fetch_server.bat"
const ALLOWED := "127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10"

var exe_override := ""          # tests: a stand-in program
var exe_override_args := PackedStringArray()
var pid := -1
var public_port := 0
var internal_port := 0
var secret := ""
var last_error := ""
var config_path := ""
var access_log := ""
var _pid_file := ""


static func exe_path() -> String:
	return ProjectSettings.globalize_path(EXE)


static func available() -> bool:
	return OS.get_name() == "Windows" and FileAccess.file_exists(exe_path())


static func label() -> String:
	return "Bundled web server (Caddy %s)" % VERSION


## The Caddyfile: game files straight from the Web build at the versioned
## address, everything else to Polox's loopback server, strangers refused.
static func caddyfile(port: int, internal: int, web_dir: String, game_prefix: String, proxy_secret: String, log_dir: String) -> String:
	var web := web_dir.replace("\\", "/")
	var logs := log_dir.replace("\\", "/")
	var lines := PackedStringArray([
		"{",
		"\tadmin off",
		"\tauto_https off",
		"\tpersist_config off",
		"\tlog {",
		"\t\toutput file \"%s/caddy.log\"" % logs,
		"\t\tlevel WARN",
		"\t}",
		"}",
		"http://:%d {" % port,
		"\tbind 0.0.0.0",
		"\tlog {",
		"\t\toutput file \"%s/caddy_access.log\" {" % logs,
		"\t\t\troll_size 1MiB",
		"\t\t\troll_keep 2",
		"\t\t}",
		"\t}",
		"\t@outside not remote_ip %s" % ALLOWED,
		"\trespond @outside \"This address isn't allowed to reach Polox.\" 403 {",
		"\t\tclose",
		"\t}",
	])
	if game_prefix != "":
		lines.append_array(PackedStringArray([
			"\thandle_path %s* {" % game_prefix,
			"\t\troot * \"%s\"" % web,
			"\t\theader Cache-Control \"no-store\"",
			"\t\tfile_server",
			"\t}",
		]))
	lines.append_array(PackedStringArray([
		"\thandle {",
		"\t\treverse_proxy 127.0.0.1:%d {" % internal,
		"\t\t\theader_up X-Polox-Proxy %s" % proxy_secret,
		"\t\t}",
		"\t}",
		"}",
	]))
	return "\n".join(lines) + "\n"


## Starts Caddy on `port` in front of Polox's server on `internal`. Returns "" or why not.
func start(port: int, internal: int, web_dir: String, game_prefix: String, save_root: String) -> String:
	stop()
	last_error = ""
	var exe := exe_override if exe_override != "" else exe_path()
	if exe_override == "" and not available():
		last_error = "The bundled web server isn't downloaded yet: run tools\\fetch_server.bat (it shows what it downloads and asks first)."
		return last_error
	var dir := save_root.path_join("phone")
	DirAccess.make_dir_recursive_absolute(dir)
	_pid_file = dir.path_join("engine.pid")
	stop_leftover(_pid_file)
	public_port = port
	internal_port = internal
	secret = Crypto.new().generate_random_bytes(16).hex_encode()
	config_path = dir.path_join("Caddyfile")
	access_log = dir.path_join("caddy_access.log")
	var f := FileAccess.open(config_path, FileAccess.WRITE)
	f.store_string(caddyfile(port, internal, web_dir, game_prefix, secret, dir))
	f.close()
	var args := PackedStringArray(["run", "--config", ProjectSettings.globalize_path(config_path), "--adapter", "caddyfile"]) if exe_override == "" else exe_override_args
	pid = OS.create_process(exe, args)
	if pid <= 0:
		last_error = "Couldn't start %s." % exe.get_file()
		pid = -1
		return last_error
	FileAccess.open(_pid_file, FileAccess.WRITE).store_string(str(pid))
	# Ready when its port answers (a few seconds at most).
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		if not OS.is_process_running(pid):
			last_error = "The bundled web server stopped right away (see %s)." % dir.path_join("caddy.log")
			pid = -1
			return last_error
		if _port_answers(port):
			return ""
		OS.delay_msec(100)
	last_error = "The bundled web server didn't start listening on port %d." % port
	stop()
	return last_error


static func _port_answers(port: int) -> bool:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return false
	var deadline := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			return true
		if peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			return false
		OS.delay_msec(10)
	return false


func running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func stop() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
	if _pid_file != "" and FileAccess.file_exists(_pid_file):
		DirAccess.remove_absolute(_pid_file)


func _exit_tree() -> void:
	stop()


## A Caddy left running by a crash: stopped, but only if that process id still belongs to caddy.exe.
static func stop_leftover(pid_file: String) -> void:
	if not FileAccess.file_exists(pid_file):
		return
	var old := FileAccess.get_file_as_string(pid_file).strip_edges().to_int()
	DirAccess.remove_absolute(pid_file)
	if old <= 0 or not OS.is_process_running(old):
		return
	var out: Array = []
	OS.execute("tasklist", ["/FI", "PID eq %d" % old, "/FO", "CSV", "/NH"], out, true)
	if not out.is_empty() and str(out[0]).to_lower().contains("caddy.exe"):
		OS.kill(old)


## The last lines of Caddy's access log (for the Doctor).
func access_tail(n: int = 10) -> PackedStringArray:
	if access_log == "" or not FileAccess.file_exists(access_log):
		return PackedStringArray()
	var lines := FileAccess.get_file_as_string(access_log).strip_edges().split("\n")
	return lines.slice(maxi(0, lines.size() - n))
