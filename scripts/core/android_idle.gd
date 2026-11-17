extends RefCounted
## Caps rendering when the player is idle. Physics and background work keep running.
## Tags: [PLATFORM]

const Graphics := preload("res://scripts/core/graphics.gd")
const GameMenu := preload("res://scripts/ui/game_menu.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")
const IDLE_MS := 5000

var _idle_since := -1
var _capped := false


func wake() -> void:
	_idle_since = -1
	if _capped:
		_capped = false
		Engine.max_fps = Graphics.active_frame_cap()


func update(main: Node) -> void:
	if not _capped and Engine.max_fps > 0 and Engine.max_fps <= Graphics.QUIET_FPS:
		return
	if not _can_idle(main):
		wake()
		return
	if _capped:
		return
	var now := Time.get_ticks_msec()
	if _idle_since < 0:
		_idle_since = now
	elif now - _idle_since >= IDLE_MS:
		_capped = true
		Engine.max_fps = Graphics.QUIET_FPS


func _can_idle(main: Node) -> bool:
	if Graphics.in_background or main.gestures.finger_count() > 0 or main.get_viewport().gui_is_dragging():
		return false
	# Other panels can be doing things like drawing, scanning or playing an animation.
	if not main.panels.is_empty() and not main.panels.back() is GameMenu:
		return false
	if main.get_tree().get_first_node_in_group("survey_flow"):
		return false
	var game: Node = main.game
	if game == null:
		return main.screen is TitleScreen
	if not is_instance_valid(game.player) or game.player.is_moving() or not game.controller.velocity.is_zero_approx():
		return false
	if not game.controller.touch_input.is_zero_approx() or Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO:
		return false
	return not (main._busy_for_reload() or (game.battles and game.battles.starting) or (game.platform and game.platform.busy()))
