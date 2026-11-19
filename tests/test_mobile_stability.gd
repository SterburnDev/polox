extends "res://tests/test_case.gd"

const Screen := preload("res://scripts/battle/battle_screen.gd")
const Data := preload("res://scripts/battle/battle_data.gd")
const Director := preload("res://scripts/battle/battle_director.gd")

class BattleWorld extends Node:
	var actors: Dictionary = {}

func test_enemy_matches_the_encountered_actor() -> void:
	fresh_save_root()
	var actor := preload("res://scripts/characters/actor.gd").new()
	var picture := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	picture.fill(Color.CORNFLOWER_BLUE)
	var texture := ImageTexture.create_from_image(picture)
	actor.setup("foe", "Friend", texture)
	var world := BattleWorld.new()
	world.actors["foe"] = actor
	var director := Director.new()
	director.world = world
	check(director.enemy_texture({"character": "foe"}) == texture, "battle uses the existing actor's sprite")
	director.free()
	actor.free()
	world.free()

func test_single_party_including_old_saved_friend_selection() -> void:
	fresh_save_root()
	preload("res://scripts/core/starter_content.gd").create_world("Solo", "Sam")
	preload("res://scripts/core/starter_content.gd").create_mochi()
	GameState.load_world()
	var director := Director.new()
	for demo in Data.DEMOS:
		var party: Array = director.party_for(["mochi", "mochi"], Data.demonstration(demo))
		eq(party.size(), 1, "only player, including practice encounters")
		eq(party[0].id, "player")
	director.free()

func test_battle_restores_world_and_aim_history() -> void:
	fresh_save_root()
	var screen := Screen.new()
	var director := Director.new()
	screen.setup(Data.demonstration("lantern_lesson"), director.party_for([]), [], [], [], SaveManager.root)
	var viewport := tree.root
	var before := viewport.disable_3d
	viewport.add_child(screen)
	check(viewport.disable_3d, "covered world does not render during battle")
	screen.heart = Vector2(9, 9)
	screen._heart_count = 3
	for i in 3:
		screen._heart_times[i] = float(i + 1) / 10.0
		screen._heart_points[i] = Vector2(i + 1, i + 1)
	eq(screen._heart_when(0.05), screen.heart)
	eq(screen._heart_when(0.2), Vector2(2, 2))
	eq(screen._heart_when(0.29), Vector2(2, 2))
	eq(screen._heart_when(4), Vector2(3, 3))
	screen.queue_free()
	await frames(2)
	eq(viewport.disable_3d, before, "world rendering returns even on abrupt panel close")
	director.free()

func test_phone_weather_runs_on_the_cpu() -> void:
	var Weather := preload("res://scripts/world/weather_fx.gd")
	var fx: Node3D = Weather.new()
	tree.root.add_child(fx)
	Weather.force_cpu = true
	fx.show_weather("leaves", 10, 8, 3.0)
	check(fx.particles is CPUParticles3D, "no GPU transform-feedback particles under the phone renderer")
	eq(fx.particles.amount, 50, "the same amount of leaves")
	check(fx.particles.preprocess > 0.0, "already falling when you arrive")
	check(fx.particles.mesh is QuadMesh, "the same leaf picture")
	fx.show_weather("rain", 10, 8, 3.0, true)
	check(fx.particles is CPUParticles3D and is_zero_approx(fx.particles.preprocess), "changing weather drifts in from the top")
	eq(fx.get_child_count(), 2, "the old weather is on its way out (queue_free), the new one in")
	Weather.force_cpu = false
	if not Weather.use_cpu():
		fx.show_weather("snow", 10, 8, 3.0)
		check(fx.particles is GPUParticles3D, "a PC keeps GPU particles")
	fx.queue_free()
	await frames(1)

func test_making_a_world_uses_the_survey_look_and_worlds_keep_theirs() -> void:
	var TB := preload("res://scripts/ui/theme_builder.gd")
	var t := TB.build()
	TB.set_world("survey", t)
	eq(TB.BG, Color.BLACK, "black, like the Survey")
	check(t.default_font is SystemFont, "the Survey's typewriter font")
	eq((t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).corner_radius_top_left, 2, "square corners")
	TB.set_world("light", t)
	check(t.default_font == null, "a world's own font returns")
	eq((t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).corner_radius_top_left, 20, "and its rounded panels (the glass refresh: 20 px cards and panels)")
	check(TB.PANEL.r > TB.PANEL.b, "tea-brown in the Light World again")
	TB.set_world("dark", t)


func test_a_memory_warning_lets_go_of_kept_sounds_and_pictures() -> void:
	var synth := preload("res://scripts/core/synth.gd")
	var relief := preload("res://scripts/core/memory_relief.gd")
	var native := preload("res://scripts/core/android_native.gd")
	check(synth.get_sound("blip") != null and synth._cache.has("blip"), "a sound is kept once made")
	# Android's warning, as the plugin's signal brings it, reaches the whole scene tree as the OS notification.
	var s := GDScript.new()
	s.source_code = "extends Node\nvar heard := 0\nfunc _notification(what: int) -> void:\n\tif what == NOTIFICATION_OS_MEMORY_WARNING:\n\t\theard += 1\n"
	s.reload()
	var probe: Node = s.new()
	tree.root.add_child(probe)
	native._on_memory_warning(80)
	eq(probe.heard, 1, "the scene tree hears NOTIFICATION_OS_MEMORY_WARNING")
	probe.queue_free()
	var before: int = relief.releases
	relief.release()
	eq(relief.releases, before + 1, "the warning is answered")
	check(not synth._cache.has("blip"), "kept sounds are let go")
	check(synth.get_sound("blip") != null, "and made again when next played")
	await frames(1)
