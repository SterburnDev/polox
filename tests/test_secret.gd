extends "res://tests/test_case.gd"
## The Music secret reveals "yams👀" when the player reaches the bottom.
## The picture appears full screen for five seconds, then the menu shows 👀 for Settings.
## Tags: [EASTER_EGG]

const Addons := preload("res://scripts/core/addons.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")
const MusicTab := preload("res://scripts/ui/settings_music_tab.gd")

var main: Node


func _boot() -> void:
	fresh_save_root()
	TitleScreen.eyes = false
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)


func _music(s: Control) -> ScrollContainer:
	return s.tabs.get_tab_control(s.tabs.current_tab) as ScrollContainer


func _open_music() -> Control:
	var s: Control = SettingsScreen.new()
	s.main = main
	s.start_on = "Music"
	main.open_panel(s)
	await frames(3)
	return s


func _settings_button() -> Button:
	return main.screen.find_child("SettingsButton", true, false) as Button


func test_the_secret_appears_at_bottom_and_shows_a_picture() -> void:
	await _boot()
	var s := await _open_music()
	var page := _music(s)
	var yams := page.find_child("Yams", true, false) as Button
	check(yams != null and not page.secret_shown(), "hidden at first")
	eq(yams.text, "yams👀", "its label")
	page.scroll_vertical = ceili(page.get_v_scroll_bar().max_value)
	check(page.at_bottom(), "at the bottom")
	check(page.secret_shown(), "the scroll reveals it immediately")
	# Pressing it: one picture, alone and full screen, for 5 seconds.
	yams.pressed.emit()
	await frames(2)
	var layer := main.get_node_or_null("Secret") as CanvasLayer
	check(layer != null, "the picture shows")
	if layer:
		check(main.go_back() and main.panels.back() == s, "Back keeps the picture up")
		yams.pressed.emit()
		eq(main.find_children("Secret", "CanvasLayer", false, false).size(), 1, "only one picture")
		var pic := layer.find_child("Picture", true, false) as TextureRect
		check(pic != null and pic.texture != null, "a picture")
		eq(pic.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "its shape kept")
		check(pic.get_rect().size.x >= main.get_viewport().get_visible_rect().size.x - 1.0, "full screen")
	await tree.create_timer(4.5).timeout
	check(is_instance_valid(layer) and layer.is_inside_tree(), "still showing at 4.5 s")
	await tree.create_timer(0.8).timeout
	await frames(2)
	check(not is_instance_valid(layer) or not layer.is_inside_tree(), "gone after 5 s")
	check(main.panels.is_empty(), "straight back to the title: Settings closed")
	var b := _settings_button()
	check(b != null and b.text == "👀", "Settings reads 👀")
	b.pressed.emit()
	await frames(2)
	check(not main.panels.is_empty() and main.panels.back().get_script() == SettingsScreen, "and still opens Settings")
	main.go_back()
	await frames(1)
	main.show_title()
	await frames(2)
	eq(_settings_button().text, "👀", "for the rest of the session")
	TitleScreen.eyes = false   # (what a restart does)
	main.show_title()
	await frames(2)
	eq(_settings_button().text, "Settings", "a restart brings Settings back")
	main.queue_free()
	await frames(2)


func test_only_reaching_the_bottom_reveals_the_secret() -> void:
	await _boot()
	var settings := await _open_music()
	var page := _music(settings)
	var bar := page.get_v_scroll_bar()
	var bottom := int(bar.max_value - bar.page)
	check(bottom > 1, "the Music page scrolls")
	page.scroll_vertical = bottom / 2
	await frames(2)
	check(not page.secret_shown(), "hidden partway down")
	page.scroll_vertical = bottom - 1
	check(not page.secret_shown(), "hidden just before the bottom")
	page.scroll_vertical = ceili(bar.max_value)
	check(page.secret_shown(), "visible on reaching the bottom")
	main.queue_free()
	await frames(2)


func test_the_secret_in_a_worlds_settings() -> void:
	# Settings opened from a world's Menu: the same secret, then back to that Menu (still in the world).
	await _boot()
	main.begin_new_world()
	await frames(3)
	var s := await _open_music()
	var page := _music(s)
	page.scroll_vertical = ceili(page.get_v_scroll_bar().max_value)
	check(page.secret_shown(), "reaching the bottom reveals it in a world too")
	(page.find_child("Yams", true, false) as Button).pressed.emit()
	await frames(2)
	var layer := main.get_node_or_null("Secret") as CanvasLayer
	check(layer != null, "the picture shows")
	await tree.create_timer(5.3).timeout
	await frames(3)
	check(not is_instance_valid(layer) or not layer.is_inside_tree(), "gone after 5 s")
	check(main.game != null, "still in the world")
	eq(main.panels.size(), 1, "Settings closed, one panel open")
	var menu: Control = main.panels.back() if not main.panels.is_empty() else null
	check(menu != null and menu.get_script() == preload("res://scripts/ui/game_menu.gd"), "the world's Menu")
	var labels: Array = menu.find_children("*", "Button", true, false).map(func(b): return str(b.text)) if menu else []
	check("👀" in labels and not "Settings" in labels, "where Settings reads 👀")
	var eyes: Button = null
	for b in menu.find_children("*", "Button", true, false) if menu else []:
		if (b as Button).text == "👀":
			eyes = b
	check(eyes != null and eyes.has_focus(), "picked, so it's in sight")
	main.go_back()
	await frames(2)
	main.show_title()
	await frames(2)
	eq(_settings_button().text, "👀", "and on the title too")
	TitleScreen.eyes = false
	main.queue_free()
	await frames(2)


func test_the_pictures_are_built_into_the_game() -> void:
	# [EASTER_EGG] The public pictures are imported textures in assets/secret/, so every copy (Windows,
	# Android, the browser) has them offline; nothing is read from a folder.
	fresh_save_root()
	var Pictures := preload("res://scripts/ui/secret_pictures.gd")
	eq(Pictures.PUBLIC_PICTURES.size(), 8, "eight public pictures")
	eq(Pictures.all().size(), 8, "and every one is in the game")
	check(not Pictures.uses_private_set(), "a copy without the private pack shows the public set")
	for p in Pictures.PUBLIC_PICTURES:
		check(p.begins_with("res://assets/secret/") and load(p) is Texture2D, p + " is a built-in texture")
	var src := FileAccess.get_file_as_string("res://scripts/ui/secret_pictures.gd")
	check(not src.contains("SaveManager") and not src.contains("load_from_file") and not src.contains("DirAccess"), "never read from a folder")
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		seen[Pictures.pick(rng).resource_path] = true
	check(seen.size() >= 3, "picked at random")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(not presets.contains("assets/secret"), "no export leaves them out")
	# Cleared for redistribution: the public set is drawn by a script in the repository, and the drawings
	# on disk are exactly what that script draws (nothing pasted in from elsewhere).
	check(FileAccess.file_exists("res://tools/art/make_secret_yams.py"), "the script that draws them is in the repository")
	for p in Pictures.PUBLIC_PICTURES:
		var svg := FileAccess.get_file_as_string(p)
		check(svg.begins_with("<svg") and not svg.contains("<image") and not svg.contains("href"), p.get_file() + " embeds no outside picture")


func test_a_private_pack_swaps_in_its_own_pictures() -> void:
	# A private build lists its own pictures in assets/local/addon.json ("secret_images"). They replace the
	# public set; entries that leave the pack, are missing or aren't pictures are skipped.
	fresh_save_root()
	var Pictures := preload("res://scripts/ui/secret_pictures.gd")
	var pack := "res://tests/fixtures/secret_pack"
	var listed := Pictures.private_pictures(pack)
	eq(Array(listed), [pack + "/pictures/dot.svg"], "only the picture that is inside the pack and in the game")
	eq(Array(Pictures.private_pictures("")), [], "no pack, no private pictures")
	eq(Array(Pictures.private_pictures("res://tests/fixtures")), [], "a folder without addon.json has none")
	Addons.builtin_override = pack
	check(Pictures.uses_private_set(), "with the pack built in, its pictures are the set")
	eq(Array(Pictures.all()), [pack + "/pictures/dot.svg"], "and the public ones step aside")
	var picked := Pictures.pick()
	check(picked != null and picked.get_size() == Vector2(64, 48), "the pack's picture is what the secret shows")
	Addons.builtin_override = null
	eq(Pictures.all().size(), 8, "without it, the public set again")


func test_the_button_appears_where_you_are_looking() -> void:
	# Reserve the button's place so reaching the bottom reveals it inside the visible area.
	await _boot()
	var s := await _open_music()
	var page := _music(s)
	var yams := page.find_child("Yams", true, false) as Button
	var bar := page.get_v_scroll_bar()
	var before_max := bar.max_value
	check(yams.modulate.a == 0.0 and yams.disabled and yams.mouse_filter == Control.MOUSE_FILTER_IGNORE, "unseen and untouchable before")
	page.scroll_vertical = ceili(bar.max_value)
	var at := page.scroll_vertical
	await frames(2)
	check(page.secret_shown() and yams.modulate.a == 1.0 and not yams.disabled, "it appears")
	eq(bar.max_value, before_max, "the page didn't grow")
	eq(page.scroll_vertical, at, "and didn't move")
	check(page.get_global_rect().encloses(yams.get_global_rect()), "it's on screen")
	main.queue_free()
	await frames(2)
