extends "res://tests/test_case.gd"

const Graphics := preload("res://scripts/core/graphics.gd")
const Detail := preload("res://scripts/core/pc_detail.gd")


func test_tiers_and_existing_quality_choices() -> void:
	Detail.reset()
	Graphics.pressure = 0
	Graphics.server_window = false
	for choice in ["auto", "high", "ultra", "off", "unknown"]:
		var settings := {"pc_detail": choice}
		eq(Graphics.pc_tier(settings, false, false), 2 if choice == "ultra" else (0 if choice == "off" else 1))
		for quality in ["balanced", "saver"]:
			eq(Graphics.pc_tier({"graphics": quality, "pc_detail": choice}, false, false), 0)
	Graphics.pressure = 1
	eq(Graphics.pc_tier({"pc_detail": "ultra"}, false, false), 0)
	Graphics.pressure = 0


func test_handheld_and_web_values_do_not_change() -> void:
	Detail.reset()
	Graphics.pressure = 0
	Graphics.server_window = false
	for choice in ["auto", "high", "ultra", "off"]:
		for quality in ["auto", "high", "balanced", "saver"]:
			var settings := {"graphics": quality, "pc_detail": choice}
			eq(Graphics.pc_tier(settings, true, false), 0, "Android ignores PC detail")
			eq(Graphics.pc_tier(settings, false, true), 0, "web ignores PC detail")
			eq(Graphics.pc_tier(settings, true, true), 0)
			eq(Graphics.frame_cap(settings, true), 60)
			eq(Graphics.msaa(settings, true), Viewport.MSAA_2X if quality == "high" or (quality == "auto" and Graphics.quality(settings) == "high") else Viewport.MSAA_DISABLED)
			for rate in ["30", "60", "120"]:
				settings["frame_rate"] = rate
				eq(Graphics.frame_cap(settings, true), rate.to_int())
	var config := ConfigFile.new()
	eq(config.load("res://project.godot"), OK)
	for platform in ["mobile", "web"]:
		eq(config.get_value("rendering", "renderer/rendering_method." + platform), "gl_compatibility")
		eq(config.get_value("rendering", "anti_aliasing/quality/msaa_3d." + platform), 0)
	check(not Detail.available(true, false) and not Detail.available(false, true))


func test_sustained_slow_frames_step_down_without_rewriting_settings() -> void:
	Detail.reset()
	var settings := {"pc_detail": "ultra"}
	for i in 300:
		Detail.observe(24.0, 0.024, true, Detail.tier(settings, false, false))
	eq(Detail.limit, 1, "Ultra steps down after settling and two seconds over budget")
	eq(settings.pc_detail, "ultra", "the saved choice stays intact")
	for i in 300:
		Detail.observe(24.0, 0.024, true, Detail.tier(settings, false, false))
	eq(Detail.limit, 0, "High can step down to Off")
	Detail.reset()
	for i in 1000:
		Detail.observe(16.7, 0.0167, true, 2)
	eq(Detail.limit, 2, "frames inside budget retain Ultra")
	Detail.reset()


func test_loading_background_and_intentional_caps_do_not_lower_detail() -> void:
	Detail.reset()
	for i in 200:
		Detail.observe(125.0, 0.125, false, 2)
	eq(Detail.limit, 2)
	for i in 100:
		Detail.observe(500.0, 0.5, true, 2)
	eq(Detail.limit, 2, "loading stalls are not a GPU budget measurement")
	for i in 200:
		Detail.observe(30.0, 0.03, true, 0)
	eq(Detail.limit, 2, "Off does not keep sampling")
	Detail.reset()


func test_effects_reset_on_room_and_tier_changes() -> void:
	var env := Environment.new()
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	Detail.apply_env(env, 2, true, false)
	eq(env.ssao_enabled, forward)
	eq(env.ssil_enabled, forward)
	eq(env.ssr_enabled, forward)
	check(not env.volumetric_fog_enabled, "no Dream World fog in the Light World")
	Detail.apply_env(env, 2, false, true)
	eq(env.volumetric_fog_enabled, forward)
	check(not env.ssr_enabled, "no street reflection pass indoors or in the Dream World")
	Detail.apply_env(env, 1, false, false)
	check(not env.volumetric_fog_enabled and not env.ssr_enabled)
	Detail.apply_env(env, 0, false, false)
	check(not env.ssao_enabled and not env.ssil_enabled and not env.ssr_enabled and not env.volumetric_fog_enabled)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	Detail.apply_sun(sun, 2)
	eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	check(sun.light_angular_distance > 0.0)
	Detail.apply_sun(sun, 0)
	eq(sun.light_angular_distance, 0.0)
	Graphics.apply_to_world(sun, {"pc_detail": "ultra"})
	eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	Graphics.apply_to_world(sun, {"pc_detail": "high"})
	eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "a step down restores two splits")
	Graphics.apply_to_world(sun, {"pc_detail": "off"})
	eq(sun.light_angular_distance, 0.0)
	sun.free()


func test_host_window_stays_cheap_and_setting_is_editable() -> void:
	fresh_save_root()
	Detail.reset()
	Graphics.server_window = true
	eq(Graphics.pc_tier({"pc_detail": "ultra"}, false, false), 0)
	var old_cap := Engine.max_fps
	var viewport := SubViewport.new()
	Graphics.apply(viewport, {"pc_detail": "ultra"})
	eq(Engine.max_fps, 30)
	eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	viewport.free()
	Graphics.server_window = false
	Engine.max_fps = old_cap
	var parent := VBoxContainer.new()
	preload("res://scripts/ui/settings_pc_detail.gd").add_row(parent)
	var option := parent.find_child("PCDetail", true, false) as OptionButton
	check(option != null)
	if option:
		eq(option.item_count, 4)
		Detail.limit = 0
		option.item_selected.emit(2)
		eq(GameState.settings.get("pc_detail"), "ultra")
		eq(Detail.limit, 2, "an explicit selection retries detail")
	GameState.settings.erase("pc_detail")
	parent.free()
	Detail.reset()


func test_slow_frames_apply_the_lower_tier_to_the_live_world() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	fresh_save_root()
	Detail.reset()
	GameState.settings["pc_detail"] = "ultra"
	GameState.settings["reduce_motion"] = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(2)
	var background := Graphics.in_background
	Graphics.in_background = false
	for i in 300:
		main._process(0.024)
	eq(Detail.limit, 1)
	eq(main.game.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	check(main.game.env.ssao_enabled and main.game.env.ssil_enabled)
	for i in 300:
		main._process(0.024)
	eq(Detail.limit, 0)
	check(not main.game.env.ssao_enabled and not main.game.env.ssil_enabled)
	eq(GameState.settings.pc_detail, "ultra")
	main.queue_free()
	await frames(2)
	GameState.settings.erase("pc_detail")
	GameState.settings.erase("reduce_motion")
	Graphics.in_background = background
	Detail.reset()
