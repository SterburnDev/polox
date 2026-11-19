extends "res://tests/test_case.gd"
const Nav := preload("res://scripts/world/grid_nav.gd")
const Actor := preload("res://scripts/characters/actor.gd")
const Controller := preload("res://scripts/world/player_controller.gd")

class SteeringRoom extends Node:
	var nav := Nav.new()
	var w := 40
	var d := 40
	var data := {"objects": [], "tile_layers": []}
	func cell_center(c: Vector2i) -> Vector3:
		return Vector3(c.x + 0.5, 0, c.y + 0.5)

class SteeringWorld extends Node:
	var room := SteeringRoom.new()
	var player := Actor.new()
	func _init() -> void:
		add_child(room)
		add_child(player)
		room.nav.setup(40, 40, [])
		player.position = Vector3(5.5, 0, 5.5)
		player.speed = 3.4


func test_continuous_steering_is_analog_and_consistent_across_tick_rates() -> void:
	var distances: Array = []
	for hz in [30, 60, 120]:
		var world := SteeringWorld.new()
		var controller := Controller.new()
		controller.world = world
		world.add_child(controller)
		for tick in hz:
			controller.steer(Vector3.RIGHT, 1.0 / hz)
		distances.append(world.player.position.x - 5.5)
		check(world.player.position.x > 8.4, "continuous travel at %d Hz" % hz)
		world.free()
	check(absf(distances.max() - distances.min()) < 0.05, "30/60/120 Hz travel agrees within five centimetres")
	var world := SteeringWorld.new()
	var controller := Controller.new()
	controller.world = world
	world.add_child(controller)
	for tick in 120:
		controller.steer(Vector3.RIGHT * 0.5, 1.0 / 60)
	check(is_equal_approx(controller.velocity.length(), 1.7), "half stick retains half walking speed")
	var before := world.player.position
	for tick in 30:
		controller.steer(Vector3.ZERO, 1.0 / 60)
	check(controller.velocity == Vector3.ZERO and not world.player.is_moving(), "release decelerates to idle")
	check(world.player.position.distance_to(before) < 0.15, "release stops promptly")
	world.free()


func test_continuous_steering_stops_at_thin_walls_and_slides_along_them() -> void:
	var world := SteeringWorld.new()
	var walls := {}
	for z in 40:
		walls["v|7|%d" % z] = true
	world.room.nav.setup(40, 40, [], walls)
	var controller := Controller.new()
	controller.world = world
	world.add_child(controller)
	for tick in 120:
		controller.steer(Vector3(1, 0, 1).normalized(), 1.0 / 60)
	check(world.player.position.x <= 7.0 - Controller.FOOT + 0.001, "capsule clearance stops before the wall")
	check(world.player.position.z > 9.0, "unblocked axis keeps moving along the wall")
	check(world.room.nav.occupiable(Vector2(world.player.position.x, world.player.position.z)), "ending footprint stays clear")
	world.free()


func test_smoothed_routes_keep_corner_clearance_and_exact_destination() -> void:
	var nav := Nav.new()
	nav.setup(10, 10, [Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5)], {"v|5|6": true})
	var start := Vector2(1.5, 4.5)
	var cells := nav.path(Vector2i(1, 4), Vector2i(7, 4))
	var points := nav.smooth(start, cells)
	check(not points.is_empty(), "route exists around obstacles")
	for p in points:
		check(nav.segment_clear(start, p), "every smoothed segment preserves clearance")
		start = p
	eq(start, Vector2(7.5, 4.5), "destination remains the requested cell centre")


func test_held_and_segment_navigation_respect_thin_walls_and_corners() -> void:
	var nav := Nav.new()
	nav.setup(5, 5, [], {"v|2|1": true})
	check(not nav.can_step(Vector2i(1, 1), Vector2i(2, 1)), "held movement cannot cross a thin wall")
	check(not nav.can_step(Vector2i(1, 1), Vector2i(2, 2)), "diagonal cannot cut the wall end")
	check(not nav.segment_clear(Vector2(1.5, 1.5), Vector2(3.5, 1.5)), "long segment checks every crossed edge")
	check(nav.segment_clear(Vector2(0.5, 3.5), Vector2(3.5, 3.5)), "clear route remains traversable")
	nav.setup(5, 5, [Vector2i(2, 1)])
	check(not nav.can_step(Vector2i(1, 1), Vector2i(2, 2)), "solid corner clearance")


func test_actor_spends_remaining_distance_across_waypoints() -> void:
	var actor := Actor.new()
	actor.speed = 4.0
	actor.walk([Vector3(0.2, 0, 0), Vector3(0.4, 0, 0), Vector3(1.0, 0, 0)])
	actor.advance_path(0.25)
	check(actor.position.distance_to(Vector3(1, 0, 0)) < 0.0001, "one-second distance budget is not lost at waypoints")
	check(not actor.is_moving(), "final arrival stops")
	actor.free()


func test_render_interpolation_never_moves_collision_or_changes_cell() -> void:
	var actor := Actor.new()
	actor._visual = Node3D.new()
	actor.add_child(actor._visual)
	actor.position = Vector3(2.02, 0, 1.5)
	actor._logic = actor.position
	actor._prev = Vector3(1.96, 0, 1.5)
	var position := actor.position
	for i in 10:
		actor._smooth_position()
	eq(actor.position, position, "rendering leaves the authoritative position unchanged")
	eq(actor.cell(), Vector2i(2, 1), "rendering cannot move the player back into the previous cell")
	actor.position = Vector3(9, 0, 9)
	actor._smooth_position()
	eq(actor._visual.position, Vector3.ZERO, "teleport resets visual interpolation")
	actor.free()


func test_opening_panel_cancels_walk_and_requires_direction_release() -> void:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var controller: Node = main.game.controller
	var player: Node3D = main.game.player
	var path: Array[Vector3] = [player.position + Vector3(2, 0, 0)]
	player.walk(path)
	var panel: Control = load("res://scripts/ui/screen_panel.gd").new()
	main.open_panel(panel)
	panel.setup("Input test")
	check(not player.is_moving(), "opening a panel cancels the old path")
	var late := {"calls": 0}
	controller._pending = func(): late.calls += 1
	controller.on_player_arrived()
	eq(late.calls, 0, "a late arrival cannot execute an interaction behind a panel")
	var old_player := Actor.new()
	controller._pending = func(): late.calls += 1
	controller.on_player_arrived(old_player)
	eq(late.calls, 0, "a replaced actor cannot complete the current actor's action")
	check(controller._pending.is_valid(), "a replaced actor cannot discard the current actor's action either")
	controller._pending = Callable()
	old_player.free()
	Input.action_press("move_right")
	panel.close()
	await frames(2)
	var before := player.position
	controller._physics_process(1.0 / 60)
	eq(player.position, before, "held key does not leak from a closed panel")
	check(controller._wait_neutral, "neutral input required")
	Input.action_release("move_right")
	controller._physics_process(1.0 / 60)
	check(not controller._wait_neutral, "release restores ownership")
	main.queue_free()
	await frames(2)
