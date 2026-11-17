extends SceneTree
## Runs after every Web export (tools\export_web.bat, or the Phone Link wizard):
## lets the phone version start over plain HTTP, writes .gz copies and
## build_info.json. See scripts/phone/web_build.gd.
##   Godot --headless --path . -s res://tools/web_postprocess.gd -- --save-root=<scratch> [<web dir>]
## Give it a scratch --save-root: the game's autoloads start with any script, and without one they open
## (and, in a second copy of the project, fill by migration) the real PersonalData folder.

const WebBuild := preload("res://scripts/phone/web_build.gd")


func _init() -> void:
	var dir := ""
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			dir = arg
			break
	var r: Dictionary = WebBuild.postprocess(dir)
	if r.ok:
		print("[web] patched for plain HTTP (page %d, engine %d change(s)); gzip: %s; build %s" % [r.patched_html, r.patched_js, ", ".join(r.gz), WebBuild.current_build_id()])
		quit(0)
	else:
		printerr("[web] " + str(r.error))
		quit(1)
