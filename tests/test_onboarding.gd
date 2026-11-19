extends "res://tests/test_case.gd"
## Onboarding: choices become a world; backing out never touches the old one;
## old chat logs are archived, not deleted.

const StarterContent := preload("res://scripts/core/starter_content.gd")

var main: Node


func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)


func test_cancel_keeps_existing_world() -> void:
	fresh_save_root()
	StarterContent.create_world("Old World", "Sam")
	StarterContent.create_mochi()
	await _boot()
	main.show_onboarding()
	await _finish_home_intro()
	main.go_back()  # back from step 1 = cancel
	await frames(1)
	check(main.screen != null and main.screen.has_signal("continue_pressed"), "back on the title screen")
	eq(SaveManager.load_world().name, "Old World", "world untouched")
	check("mochi" in SaveManager.list_characters(), "friend untouched")
	check(not SaveManager.list_rooms().is_empty(), "rooms untouched")
	main.queue_free()
	await frames(1)


func test_finish_creates_world_from_choices() -> void:
	fresh_save_root()
	StarterContent.create_world("Old", "")
	var old_id := StarterContent.create_mochi()
	ChatLog.append(old_id, "home", "user", "an old message")
	await _boot()
	main.show_onboarding()
	await _finish_home_intro()
	var o: Control = main.screen
	o._world_name.text = "Lumen Hollow"
	o._player_name.text = "Sam"
	o._life.text = "Night-shift nurse, learning guitar."
	o._dream.text = "play at an open mic"
	o._friend_name.text = "Mochi"
	o._pick_vibe(2)
	o._finish(false)
	await frames(2)
	check(main.game != null, "playing")
	eq(GameState.world.name, "Lumen Hollow")
	eq(GameState.player_name(), "Sam")
	eq(GameState.world.world_bible.life_context, "Night-shift nurse, learning guitar.")
	eq(GameState.dream_list()[0].text, "play at an open mic")
	check(str(GameState.get_character("mochi").personality).begins_with("Calm"), "vibe applied")
	eq(ChatLog.read_all("mochi").size(), 0, "the new Mochi starts with a clean history")
	var slots := preload("res://scripts/core/slots.gd").ids()
	eq(slots.size(), 2, "the old world kept its own slot")
	check(GameState.settings.onboarded, "onboarded flag set")
	main.queue_free()
	await frames(1)


## The title keeps the night violet and its twinkling stars, even coming back from the tea-brown Light
## World; making a world is black like the Survey, and backing out brings the violet back.
func test_the_title_is_violet_and_making_a_world_is_black() -> void:
	var TB := preload("res://scripts/ui/theme_builder.gd")
	var Starfield := preload("res://scripts/ui/starfield.gd")
	fresh_save_root()
	StarterContent.create_world("Old World", "Sam")
	await _boot()
	main.set_ui_world("light")
	main.show_title()
	await frames(1)
	eq(TB.world, "dark", "the title is night violet")
	check(main.ui_theme.default_font == null, "in the game's own font")
	check(not Starfield.black(), "over the purple starfield")
	main.show_onboarding()
	await frames(1)
	eq(TB.world, "survey", "making a world is black, like the Survey")
	await _finish_home_intro()
	eq(TB.world, "survey", "the steps after the Survey too")
	main.go_back()
	await frames(1)
	check(main.screen != null and main.screen.has_signal("continue_pressed"), "back on the title")
	eq(TB.world, "dark", "violet again")
	main.queue_free()
	await frames(1)


func _finish_home_intro() -> void:
	await frames(1)
	var mapper: Node = main.get_node_or_null("NewWorldHomeMapper")
	check(mapper != null, "home Survey appears before names and friends")
	check(main.screen == null and main.game == null, "no world or profile screen covers creation")
	if mapper:
		mapper.screen._finish("skipped")
	var deadline := Time.get_ticks_msec() + 8000
	while main.screen == null and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(main.screen != null, "profile follows Survey")
