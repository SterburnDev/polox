extends Node3D
## Life on your street (the Light World's blocks): now and then a car rolls along the road, and a few birds
## cross the sky. Quiet and occasional, never in your way (cars keep to the road), and none under Reduce motion.

const Furniture := preload("res://scripts/world/furniture.gd")

const CAR_COLORS := ["#c8645c", "#5a7ab0", "#e8e2d6", "#3a3a40", "#8aa66a", "#d8b45a"]

var strips: Array = []          # [{"from": Vector3, "to": Vector3}]
var follow: Node3D              # you (cars and birds pass near enough to be seen)
var cars := 0                   # (tests) cars sent along
var birds := 0
var _car_t := 0.0
var _bird_t := 0.0
var _rng := RandomNumberGenerator.new()
var _on := false


func on_room_loaded(data: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	strips.clear()
	_on = str(data.get("id", "")).begins_with("lw_hood_")
	if not _on:
		return
	_rng.seed = hash(str(data.get("id", ""))) ^ Time.get_ticks_msec()
	for a in data.get("floor_areas", []):
		if str(a.get("kind", "")) != "road":
			continue
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x := float(r[0])
		var z := float(r[1])
		var w := float(r[2])
		var d := float(r[3])
		if w >= 6.0 and d >= 1.0 and w >= d:
			strips.append({"from": Vector3(x, 0.0, z + d / 2.0), "to": Vector3(x + w, 0.0, z + d / 2.0), "rot": 0})
		elif d >= 6.0 and w >= 1.0:
			strips.append({"from": Vector3(x + w / 2.0, 0.0, z), "to": Vector3(x + w / 2.0, 0.0, z + d), "rot": 1})
	_car_t = _rng.randf_range(4.0, 10.0)
	_bird_t = _rng.randf_range(6.0, 14.0)


func _process(delta: float) -> void:
	if not _on or bool(GameState.settings.get("reduce_motion", false)):
		return
	_car_t -= delta
	_bird_t -= delta
	var near: Vector3 = follow.position if is_instance_valid(follow) else Vector3.INF
	if _car_t <= 0.0:
		_car_t = _rng.randf_range(14.0, 30.0)
		spawn_car(near)
	if _bird_t <= 0.0:
		_bird_t = _rng.randf_range(18.0, 40.0)
		spawn_birds(near)


## A car along the longest road here (either way). Returns it (or null when there's no road). `near`: it
## comes along the road past that spot (screenshots).
func spawn_car(near: Vector3 = Vector3.INF) -> Node3D:
	if strips.is_empty():
		return null
	if near != Vector3.INF:
		strips.sort_custom(func(a, b): return _dist_to(a, near) < _dist_to(b, near))
	else:
		strips.sort_custom(func(a, b): return (a.from as Vector3).distance_to(a.to) > (b.from as Vector3).distance_to(b.to))
	var s: Dictionary = strips[0 if near != Vector3.INF else _rng.randi_range(0, mini(1, strips.size() - 1))]
	var forward := _rng.randf() < 0.5
	var a: Vector3 = s.from if forward else s.to
	var b: Vector3 = s.to if forward else s.from
	if near != Vector3.INF:
		# Never through you: if you're standing on this road, it waits for another time.
		var dir0: Vector3 = (b - a).normalized()
		var off: Vector3 = (near - a) - dir0 * (near - a).dot(dir0)
		if off.length() < 1.6:
			return null
		# Start a few metres before the point of the road closest to `near`.
		var dir: Vector3 = (b - a).normalized()
		var along := clampf((near - a).dot(dir) - 5.0, 0.0, a.distance_to(b) - 1.0)
		a = a + dir * along
	var car := Furniture.build({"model": "car", "color": CAR_COLORS[_rng.randi_range(0, CAR_COLORS.size() - 1)], "rot": int(s.rot) + (0 if forward else 2), "id": ""})
	car.name = "PassingCar"
	car.scale = Vector3.ONE * 0.8
	add_child(car)
	car.position = a
	var tw := car.create_tween()
	tw.tween_property(car, "position", b, a.distance_to(b) * 0.35)
	tw.tween_callback(car.queue_free)
	cars += 1
	return car


static func _dist_to(strip: Dictionary, p: Vector3) -> float:
	var a: Vector3 = strip.from
	var b: Vector3 = strip.to
	var t := clampf((p - a).dot(b - a) / maxf(0.001, a.distance_squared_to(b)), 0.0, 1.0)
	return a.lerp(b, t).distance_to(Vector3(p.x, 0.0, p.z))


## A few birds crossing the sky (over `near` when given).
func spawn_birds(near: Vector3 = Vector3.INF) -> void:
	var w := 60.0
	var z := _rng.randf_range(10.0, 50.0)
	var x0 := -4.0
	if near != Vector3.INF:
		z = near.z - 1.5
		x0 = near.x - 7.0
	for i in 3:
		var bird := Label3D.new()
		bird.text = "v"
		bird.font_size = 48
		bird.modulate = Color("#3a3a46")
		bird.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bird.no_depth_test = false
		bird.name = "Bird"
		add_child(bird)
		bird.position = Vector3(x0 - i * 1.4, 3.2 + i * 0.35, z + i * 0.8)
		var tw := bird.create_tween()
		tw.tween_property(bird, "position:x", maxf(w, x0 + 40.0) + 4.0, 10.0 + i * 0.6)
		tw.tween_callback(bird.queue_free)
	birds += 1
