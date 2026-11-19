extends RefCounted

const Graphics := preload("res://scripts/core/graphics.gd")


static func add_rows(parent: Control) -> void:
	if not OS.has_feature("android"):
		return
	for option in [
		[Graphics.ANDROID_IDLE_FPS_KEY, "Idle at 30 fps", "Lowers the frame rate after five idle seconds. Touch to wake."],
		[Graphics.ANDROID_LOW_3D_KEY, "Lower 3D resolution", "Renders 3D at 85% on Automatic, Balanced, or Battery saver."],
	]:
		var key := str(option[0])
		var check := CheckBox.new()
		check.text = str(option[1])
		check.tooltip_text = str(option[2])
		check.button_pressed = bool(GameState.settings.get(key, false))
		check.toggled.connect(func(on: bool):
			GameState.settings[key] = on
			GameState.save_settings())
		parent.add_child(check)
