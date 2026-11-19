extends Node
## Builds the phone version from inside Polox (the wizard's step 1): runs the
## same two steps as tools\export_web.bat in the background, the Web export
## and the plain-HTTP post-process, and reports progress and plain-language
## errors (missing templates, missing preset, export failures).

signal progress(text: String)
signal finished(ok: bool, message: String)

const WebBuild := preload("res://scripts/phone/web_build.gd")

var busy := false
var log_text := ""
var _pid := -1
var _pipe: FileAccess
var _err: FileAccess
var _t0 := 0
var _stage := ""


## "" when a build can start, else what to do first.
static func blocker() -> String:
	if OS.has_feature("web") or OS.has_feature("android"):
		return "The phone version is built on the PC."
	if WebBuild.godot_console() == "":
		return "Polox's Godot isn't in tools\\godot (run tools\\get_godot.bat)."
	if not WebBuild.templates_present():
		return "Polox's web engine isn't built yet: run tools\\pyenv\\Scripts\\python tools\\build_engine.py web once."
	var p := WebBuild.preset_problems()
	if not p.is_empty():
		return "Web export settings: " + "; ".join(p)
	return ""


func start() -> String:
	if busy:
		return ""
	var why := blocker()
	if why != "":
		return why
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/web"))
	var ignore := ProjectSettings.globalize_path("res://build/.gdignore")
	if not FileAccess.file_exists(ignore):
		FileAccess.open(ignore, FileAccess.WRITE).close()   # Godot must not import the build output
	var p: Dictionary = OS.execute_with_pipe(WebBuild.godot_console(), WebBuild.export_args(), false)
	if p.is_empty():
		return "Couldn't start the export."
	_pid = int(p.pid)
	_pipe = p.stdio
	_err = p.stderr
	_t0 = Time.get_ticks_msec()
	_stage = "export"
	log_text = ""
	busy = true
	progress.emit("Building the phone version... (about a minute)")
	return ""


func _process(_delta: float) -> void:
	if not busy:
		return
	log_text += _pipe.get_buffer(65536).get_string_from_utf8() + _err.get_buffer(65536).get_string_from_utf8()
	var secs := (Time.get_ticks_msec() - _t0) / 1000
	if OS.is_process_running(_pid):
		progress.emit("Building the phone version... %d:%02d" % [secs / 60, secs % 60])
		if secs > 600:
			OS.kill(_pid)
			_done(false, "The export took over 10 minutes and was stopped.")
		return
	log_text += _pipe.get_buffer(1 << 20).get_string_from_utf8() + _err.get_buffer(1 << 20).get_string_from_utf8()
	var code := OS.get_process_exit_code(_pid)
	if code != 0 or not FileAccess.file_exists(ProjectSettings.globalize_path("res://build/web/index.wasm")):
		var tail := log_text.strip_edges().right(400)
		_done(false, "The export failed (code %d). %s" % [code, tail])
		return
	progress.emit("Making it work over plain HTTP too...")
	var r := WebBuild.postprocess()
	if not r.ok:
		_done(false, "Built, but: " + str(r.error))
		return
	_done(true, "Phone version ready (%d s): %.1f MB, build %s." % [secs, float(WebBuild.inspect().mb), WebBuild.current_build_id().substr(0, 8)])


func _done(ok: bool, msg: String) -> void:
	busy = false
	_pid = -1
	finished.emit(ok, msg)
