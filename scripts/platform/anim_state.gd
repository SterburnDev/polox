extends RefCounted
## Which pose a character is in while moving freely: idle -> walk -> run ->
## jump -> fall -> land (-> idle). Pure logic (tests drive it directly); the
## actor turns the state into frames or generated motion.

const Config := preload("res://scripts/platform/platform_config.gd")

const STATES: PackedStringArray = ["idle", "walk", "run", "jump", "fall", "land"]

var state := "idle"
var facing := 1.0                 # +1 right, -1 left (on screen)
var _land_left := 0.0
var _was_floor := true


## One step. velocity in world units, on_floor from the body, running = run speed wanted.
func update(velocity: Vector3, on_floor: bool, running: bool, delta: float) -> String:
	var flat := Vector2(velocity.x, velocity.z).length()
	if not on_floor:
		state = "jump" if velocity.y > 0.5 else "fall"
		_was_floor = false
		return state
	if not _was_floor:
		_was_floor = true
		_land_left = Config.LAND_TIME
		state = "land"
		return state
	if _land_left > 0.0:
		_land_left -= delta
		if _land_left > 0.0 and flat < 0.5:
			state = "land"
			return state
	if flat < 0.3:
		state = "idle"
	elif running and flat > Config.WALK_SPEED + 0.5:
		state = "run"
	else:
		state = "walk"
	return state
