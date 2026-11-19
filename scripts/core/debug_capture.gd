extends Node
## Developer helper for automated visual checks (never active in normal play):
##   Godot --path . -- --shot=C:/tmp/a.png --shot-delay=2.5 [--drive=name]
## Saves a screenshot after the delay and quits (--stay: keeps running). "--drive" runs a scripted
## scenario from scripts/core/debug_drives.gd first (walk, talk, open menus).

var shot_path := ""
var delay := 2.0
var drive := ""


static func wanted() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot=") or arg.begins_with("--drive="):
			return true
	return false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot-delay="):
			delay = arg.trim_prefix("--shot-delay=").to_float()
		elif arg.begins_with("--drive="):
			drive = arg.trim_prefix("--drive=")
	_run()


func _run() -> void:
	if drive != "":
		var drives: Script = load("res://scripts/core/debug_drives.gd")
		if drives:
			await drives.new().run(drive, get_parent())
	await get_tree().create_timer(delay).timeout
	if shot_path != "":
		# Draw a fresh frame right now: a capture window that's hidden or behind others may not be
		# drawn for a while, and reading back then gives an old frame (seen: the world without its UI).
		await RenderingServer.frame_post_draw
		RenderingServer.force_draw(false)
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("[debug] saved screenshot ", shot_path)
	if "--stay" in OS.get_cmdline_user_args():
		return   # keep running (e.g. to test Phone Link with the window minimized)
	get_tree().quit()
