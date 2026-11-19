extends "res://tests/test_case.gd"
## [LIGHT_WORLD_MAP] The World Map's Light World layer (hood_map_view.gd): pan and zoom by mouse, wheel,
## trackpad and fingers; a tap travels once, a drag never does; clear messages when the streets
## aren't mapped or the saved map can't be read. Nothing here needs a map service: the map is drawn
## from the streets saved when they were mapped.
## Tags: [LIGHT_WORLD_MAP]

const HoodMapView := preload("res://scripts/home/hood_map_view.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")


func _view() -> Control:
	var view: Control = HoodMapView.new()
	view.size = Vector2(400, 300)
	var feats: Array = []
	for i in 6:
		feats.append({"kind": "building", "sub": "home", "pts": [[i * 12 - 30, 10], [i * 12 - 22, 10], [i * 12 - 22, 18], [i * 12 - 30, 18]]})
	feats.append({"kind": "road", "name": "Long Road", "pts": [[-240, 0], [240, 0]]})
	view.extract = {"radius": 250, "features": feats}
	tree.root.add_child(view)
	view.set_meta("picks", 0)
	view.picked.connect(func(_id): view.set_meta("picks", int(view.get_meta("picks")) + 1))
	return view


func _mouse(view: Control, at: Vector2, down: bool, device := 0, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	e.device = device
	view._gui_input(e)


func _touch(view: Control, index: int, at: Vector2, down: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = at
	t.pressed = down
	view._gui_input(t)


func test_zoom_keeps_the_spot_under_the_pointer_and_fit_resets() -> void:
	var view := _view()
	await frames(2)
	var fit_scale: float = view._scale
	var at := Vector2(250, 120)
	var metres: Vector2 = view._px_to_metres(at)
	for i in 3:
		_mouse(view, at, true, 0, MOUSE_BUTTON_WHEEL_UP)
	await frames(1)
	check(view._scale > fit_scale * 1.5, "the wheel zooms in (%.2f -> %.2f px/m)" % [fit_scale, view._scale])
	check(view._px_to_metres(at).distance_to(metres) < 0.5, "the spot under the pointer stays put")
	view.zoom_by(0.5)
	view.fit()
	await frames(1)
	check(is_equal_approx(view._scale, fit_scale) and view.pan == Vector2.ZERO, "Fit shows the whole neighbourhood again")
	view.queue_free()


func test_a_drag_pans_and_a_tap_travels_once() -> void:
	var view := _view()
	await frames(2)
	view.zoom_by(2.0)
	await frames(1)
	var before: Vector2 = view.pan
	_mouse(view, Vector2(200, 150), true)
	var m := InputEventMouseMotion.new()
	m.position = Vector2(260, 170)
	m.relative = Vector2(60, 20)
	view._gui_input(m)
	_mouse(view, Vector2(260, 170), false)
	check(view.pan != before, "a drag moves the map")
	eq(int(view.get_meta("picks")), 0, "and doesn't travel")
	_mouse(view, Vector2(200, 150), true)
	_mouse(view, Vector2(201, 151), false)
	eq(int(view.get_meta("picks")), 1, "a click travels")
	# A phone tap: the touch, then its mouse copy.
	_touch(view, 0, Vector2(200, 150), true)
	_mouse(view, Vector2(200, 150), true, InputEvent.DEVICE_ID_EMULATION)
	_touch(view, 0, Vector2(200, 150), false)
	_mouse(view, Vector2(200, 150), false, InputEvent.DEVICE_ID_EMULATION)
	eq(int(view.get_meta("picks")), 2, "one phone tap, one trip (not two)")
	view.queue_free()


func test_two_fingers_pinch_without_travelling() -> void:
	var view := _view()
	await frames(2)
	var z: float = view.zoom
	_touch(view, 0, Vector2(180, 150), true)
	_touch(view, 1, Vector2(220, 150), true)
	for d in [[0, Vector2(140, 150)], [1, Vector2(260, 150)]]:
		var e := InputEventScreenDrag.new()
		e.index = d[0]
		e.position = d[1]
		view._gui_input(e)
	_touch(view, 1, Vector2(260, 150), false)
	_touch(view, 0, Vector2(140, 150), false)
	check(view.zoom > z * 2.0, "spreading two fingers zooms in (%.2f)" % view.zoom)
	eq(int(view.get_meta("picks")), 0, "a pinch never travels")
	view.queue_free()


func test_missing_or_unreadable_streets_say_how_to_fix_it() -> void:
	fresh_save_root()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var osm := HomeStore.path("osm.json")
	DirAccess.remove_absolute(osm)
	var map: Control = load("res://scripts/ui/world_map_view.gd").new()
	main.open_panel(map)
	map.setup_map(main.game)
	map.show_layer("light")
	await frames(1)
	check(str(map.map_note).contains("Map my home"), "not mapped: where to map it (%s)" % map.map_note)
	JsonUtil.ensure_dir(osm.get_base_dir())
	var f := FileAccess.open(osm, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	map.show_layer("light")
	await frames(1)
	check(str(map.map_note).contains("can't be read"), "unreadable: says so, and how to make it again (%s)" % map.map_note)
	JsonUtil.write_json(osm, {"radius": 250, "features": [{"kind": "road", "name": "Test Road", "pts": [[-100, 0], [100, 0]]}]})
	map.show_layer("light")
	await frames(2)
	eq(map.map_note, "", "mapped: the hand-drawn map")
	check(map.hood_view != null and map.find_child("MapZoom", true, false) != null, "with − + Fit")
	main.queue_free()
	await frames(2)


func test_an_unavailable_map_service_says_so_and_keeps_the_saved_map() -> void:
	# A real request to a server that isn't there (nothing listens on this port): the failure must be
	# plain, retryable and harmless. (No request leaves this PC.)
	fresh_save_root()
	var Osm: GDScript = load("res://scripts/home/osm.gd")
	var osm: Node = Osm.new()
	tree.root.add_child(osm)
	GameState.settings["light_world"] = {"overpass_url": "https://127.0.0.1:9/api/interpreter"}
	var got := {}
	osm.finished.connect(func(r): got.merge(r))
	osm.fetch(10.0, 10.0, 150, true)
	var t := Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t < 120000:
		await frames(5)
	check(not got.is_empty(), "the lookup finishes (in %.0f s)" % ((Time.get_ticks_msec() - t) / 1000.0))
	print("    (unavailable map service: answered in %.0f s: %s)" % [(Time.get_ticks_msec() - t) / 1000.0, got.get("error", "")])
	check(not bool(got.get("ok", true)), "and fails")
	check(str(got.get("error", "")).contains("unchanged") or str(got.get("error", "")).contains("still work"), "saying the saved streets are safe: " + str(got.get("error", "")))
	check(bool(got.get("retry", false)) or str(got.get("state", "")) in ["offline", "failed"], "with a way to try again (%s)" % got.get("state", ""))
	GameState.settings.erase("light_world")
	osm.queue_free()
