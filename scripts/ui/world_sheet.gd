extends "res://scripts/ui/screen_panel.gd"
## The World tab on a phone (the bottom tab bar's first button): where you are and what you can do with
## the view. The World Map, Things to do (in your real home), a photo, your places, and the camera (turn
## and zoom, for when two fingers are busy). The camera buttons don't close it.

const Realms := preload("res://scripts/world/realms.gd")

var world: Node


func setup_world(game_world: Node) -> void:
	world = game_world
	compact = true
	setup(world.room_title(world.room.data), Vector2(720, 560))
	var light := Realms.is_light(world.room.data)
	var col := UiKit.vbox(10)
	var actions: Array = [["World Map", func():
			close()
			var m: Control = load("res://scripts/ui/world_map_view.gd").new()
			world.main.open_panel(m)
			m.setup_map(world)]]
	if light:
		actions.append(["Things to do here", func():
			close()
			world.light_life.open_things_to_do()])
		actions.append(["Tell Polox about home", func():
			close()
			var tp: Control = load("res://scripts/home/tell_polox_panel.gd").new()
			world.main.open_panel(tp)
			tp.setup_tell(world)])
	actions.append(["Take a photo", func():
		close()
		world.take_photo()])
	if not light:
		actions.append(["Places", func():
			close()
			world.main.open_panel(load("res://scripts/world/world_menu.gd").room_list(world))])
	for a in actions:
		var b := UiKit.button(str(a[0]), a[1], 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 60
		col.add_child(b)
	body.add_child(col)
	var cam := UiKit.hbox(8)
	for spec in [["⟲", func(): world.cam.rotate_step(-1)], ["⟳", func(): world.cam.rotate_step(1)], ["+", func(): world.cam.zoom(-1)], ["−", func(): world.cam.zoom(1)]]:
		var cb := UiKit.button(str(spec[0]), spec[1], 0)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.custom_minimum_size.y = 60
		cb.add_theme_font_size_override("font_size", 26)
		cam.add_child(cb)
	body.add_child(UiKit.label("Camera", 18, ThemeBuilder.MUTED))
	body.add_child(cam)
