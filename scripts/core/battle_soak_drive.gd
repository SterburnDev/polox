extends RefCounted
## Disposable-save QA: each original spar stays playable for two minutes,
## then ends through ACT and SPARE. The same drive runs on Windows and Android.

const Data := preload("res://scripts/battle/battle_data.gd")
const Json := preload("res://scripts/core/json_util.gd")

var main: Node
var errors: Array = []
var rows: Array = []


func check(ok: bool, label: String) -> void:
	print("[spars] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		errors.append(label)


func run(host: Node, duration: float = 120.0) -> Dictionary:
	main = host
	if not Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--save-root=")):
		return {"failures": ["spar QA requires a disposable save root"], "encounters": []}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spar-seconds="):
			duration = clampf(arg.trim_prefix("--spar-seconds=").to_float(), 2.0, 180.0)
	main._close_all_panels()
	GameState.settings["reduce_motion"] = true
	GameState.settings["encounters"] = "off"
	if main.game == null:
		main.begin_new_world()
		await main.get_tree().process_frame
	var game: Node = main.game
	await game.dark.go_dark()
	for card in main.ui.find_children("*", "Control", true, false):
		var script: Script = card.get_script()
		if script and script.resource_path.get_file() in ["today_card.gd", "recap_card.gd"]:
			card.queue_free()
	for id in Data.Spars.ORDER:
		await encounter(game, id, duration)
	var result := {"failures": errors, "encounters": rows, "platform": OS.get_name(), "renderer": RenderingServer.get_current_rendering_method()}
	Json.write_json(SaveManager.root.path_join("sparring_result.json"), result)
	print("[spars] DONE ", JSON.stringify(result))
	return result


func encounter(game: Node, id: String, duration: float) -> void:
	var battle := Data.from_template(id, {})
	if id == "seed_post":
		battle.allow_party = true
	game.battles.start(battle)
	var deadline := Time.get_ticks_msec() + 20000
	while game.battles.screen == null and Time.get_ticks_msec() < deadline:
		await main.get_tree().process_frame
	var screen: Control = game.battles.screen
	if screen == null:
		check(false, id + " opens")
		return
	screen.auto_friends = false
	check(screen.faces.get(0) != null, id + " has its original portrait")
	check(screen.music_stream != null and screen.music_stream.resource_path == "", id + " uses an original loop")
	Engine.max_fps = 60
	var began := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	var frames := 0
	var sum_ms := 0.0
	var worst := 0.0
	var peak := 0
	var screenshot := false
	var route_seen := false
	var phase_seen := false
	var modes := {}
	var restarts := 0
	var blocks := 0
	var pods := 0
	var previous_blocks := 0
	var previous_pods := 0
	var old_turn := -1
	var finishing := false
	deadline = began + int((duration + 90) * 1000)
	while is_instance_valid(screen) and screen.is_inside_tree() and Time.get_ticks_msec() < deadline:
		Engine.max_fps = 60
		var now := Time.get_ticks_usec()
		var elapsed := (Time.get_ticks_msec() - began) / 1000.0
		var frame_ms := (now - last) / 1000.0
		last = now
		frames += 1
		sum_ms += frame_ms
		worst = maxf(worst, frame_ms)
		finishing = elapsed >= duration
		match str(screen.phase):
			"intro", "text":
				screen._tap()
			"menu":
				var who: int = screen.member
				var target: int = screen.state.first_active()
				if finishing and who == 0:
					if screen.state.can_spare(target):
						screen._pick({"cmd": "spare", "target": target})
					else:
						screen._pick({"cmd": "act", "target": target, "arg": 2})
				elif who == 0 and int(screen.state.party[0].hp) < 24 and screen.state.tp >= 24:
					screen._pick({"cmd": "magic", "spell": "mend", "target": 0})
				elif who == 0 and screen.turns_taken == 2:
					screen._pick({"cmd": "act", "target": target, "arg": 1})
				elif who == 0 and screen.turns_taken == 3:
					screen._pick({"cmd": "act", "target": target, "arg": 2})
				else:
					screen._pick({"cmd": "defend"})
			"review":
				screen._resolve()
			"telegraph", "dodge":
				if screen.turns_taken != old_turn:
					old_turn = screen.turns_taken
					previous_blocks = 0
					previous_pods = 0
				blocks += maxi(0, int(screen.motion.blocks) - previous_blocks)
				pods += maxi(0, int(screen.motion.breaks) - previous_pods)
				previous_blocks = screen.motion.blocks
				previous_pods = screen.motion.breaks
				modes[screen.motion.mode] = true
				var live: int = screen.field.count
				for active in screen.motion.pulse_live:
					live += int(active)
				peak = maxi(peak, live)
				route_seen = route_seen or str(screen.wave.name) == str(battle.enemies[0].waves[2].name)
				phase_seen = phase_seen or screen.state.phase_index(screen.state.enemies[0]) >= 0
				steer(screen, elapsed, id)
				if not screenshot and screen.phase == "dodge" and screen.wave_t >= 1.5:
					await RenderingServer.frame_post_draw
					main.get_viewport().get_texture().get_image().save_png(SaveManager.root.path_join(id + ".png"))
					screenshot = true
			"end":
				if not finishing:
					screen.retry()
					restarts += 1
					old_turn = -1
				else:
					break
		await main.get_tree().process_frame
	var seconds := (Time.get_ticks_msec() - began) / 1000.0
	check(seconds >= duration, id + " ran for the requested time")
	check(screenshot, id + " screenshot")
	check(peak <= 200, id + " stays within 200 bullets")
	check(is_instance_valid(screen) and screen.state.outcome == "spared", id + " ends with SPARE")
	if duration >= 100:
		check(route_seen and phase_seen, id + " exercises ACT routing and its second phase")
		if id == "copper_vane": check(blocks > 0, id + " blocks incoming dots")
		if id == "seed_post": check(pods > 0 and screen.state.party.size() > 1, id + " opens pods with a party")
	rows.append({"id": id, "seconds": snappedf(seconds, 0.01), "frames": frames,
		"fps": snappedf(1000.0 * frames / maxf(1, sum_ms), 0.1), "worst_ms": snappedf(worst, 0.1), "peak_bullets": peak,
		"modes": modes.keys(), "phase_seen": phase_seen, "act_route_seen": route_seen, "blocks": blocks, "pods": pods, "restarts": restarts})
	if is_instance_valid(screen):
		screen.finish()
	for i in 3:
		await main.get_tree().process_frame
	print("[spars] encounter ", JSON.stringify(rows.back()))


func steer(screen: Control, seconds: float, id: String) -> void:
	if screen.phase != "dodge":
		return
	var target: Vector2 = screen._arena / 2 + Vector2(sin(seconds * 1.2) * 55, cos(seconds * 0.9) * 32)
	if screen.motion.mode == "gravity":
		target.y = 60 if fmod(seconds, 1.2) < 0.65 else screen._arena.y
	if screen.motion.mode == "shield":
		var closest := INF
		for i in screen.field.count:
			var b = screen.field.slots[i]
			if not screen.field.removed(b) and b.position.distance_squared_to(screen.heart) < closest:
				closest = b.position.distance_squared_to(screen.heart)
				target = b.position
	if id == "stillwater_lantern" and screen.state.phase_index(screen.state.enemies[0]) < 0 and int(screen.state.enemies[0].next_wave) < 0:
		if screen._finger >= 0:
			var up := InputEventScreenTouch.new()
			up.index = 0
			up.pressed = false
			screen._gui_input(up)
		return
	if screen._finger < 0:
		var down := InputEventScreenTouch.new()
		down.index = 0
		down.pressed = true
		down.position = screen.arena_to_screen(screen.heart) + Vector2(0, 70)
		screen._gui_input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = screen._touch_origin + (target - screen._touch_heart).rotated(screen._rotation) * screen._arena_scale + Vector2(0, 42)
	screen._gui_input(drag)
