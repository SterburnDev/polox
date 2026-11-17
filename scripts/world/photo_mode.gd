extends RefCounted
## Photo mode: hides the UI for a frame, captures the scene, saves it to
## photos/<date>.png and pins it into the Memory Book. A soft flash and a
## shutter click make it feel like a real snapshot.

const Synth := preload("res://scripts/core/synth.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")


static func take(world: Node) -> String:
	if DisplayServer.get_name() == "headless":   # nothing is drawn (and frame_post_draw never fires)
		return ""
	var main: Node = world.main
	var layers: Array = [main.ui.get_parent()]
	if main.has_method("toast_layer"):
		layers.append(main.toast_layer())
	for l in layers:
		l.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := world.get_viewport().get_texture().get_image()
	for l in layers:
		l.visible = true
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var rel := "photos/%s.png" % stamp
	JsonUtil.ensure_dir(SaveManager.abs_path("photos"))
	if img == null or img.save_png(SaveManager.abs_path(rel)) != OK:
		GameState.notify("Couldn't save the photo. Is the disk full?")
		return ""
	_flash(main)
	Synth.play(world, "click", 0.8)
	var room_name := str(world.room.data.get("name", "your world"))
	var who := PackedStringArray()
	for id in world.actors:
		who.append(str(GameState.get_character(id).get("name", "")))
	var text := ("With " + ", ".join(who) + ".") if not who.is_empty() else "A quiet moment."
	GameState.add_moment("A photo in %s" % room_name, text, "", "manual", {"photo": rel})
	GameState.notify("★ Photo saved to your Memory Book")
	return rel


static func _flash(main: Node) -> void:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.8)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.ui.add_child(r)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.45)
	tw.tween_callback(r.queue_free)
