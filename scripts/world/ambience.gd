extends Node
## The Light World's own sounds, softly under its music (Festival, unless you choose another or quiet
## in Settings > Music): a quiet room tone indoors with birds outside by day (crickets at night), and
## outdoors birds, a far-off hum of traffic and the odd car passing. Made in code like the rest of
## Polox's sounds. The Dream World keeps its music and fountains; this stays silent there.

const Synth := preload("res://scripts/core/synth.gd")
const RATE := 22050
const LOOP_S := 8.0

static var _cache: Dictionary = {}

var player: AudioStreamPlayer
var current := ""             # "" | "home_day" | "home_night" | "street_day" | "street_night"


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -80.0
	add_child(player)


## The room tone is stopped and let go as the world closes (audio_exit.gd).
func _exit_tree() -> void:
	preload("res://scripts/core/audio_exit.gd").release(player)


## Which loop fits this place at this hour ("" in the Dream World).
static func kind_for(room: Dictionary, night: bool) -> String:
	if not load("res://scripts/world/realms.gd").is_light(room):
		return ""
	var outdoor := str(room.get("kind", "indoor")) == "outdoor"
	return ("street" if outdoor else "home") + ("_night" if night else "_day")


func play_for(room: Dictionary, night: bool) -> void:
	var k := kind_for(room, night)
	if k == current:
		return
	current = k
	var tw := create_tween()
	if k == "":
		tw.tween_property(player, "volume_db", -80.0, 1.0)
		tw.tween_callback(player.stop)
		return
	player.stream = loop(k)
	player.volume_db = -40.0
	player.play()
	tw.tween_property(player, "volume_db", _target_db(), 1.5)


func _target_db() -> float:
	return linear_to_db(maxf(0.0001, float(GameState.settings.get("sfx_volume", 0.8)) * 0.5))


## Forgets the room tones made so far (memory_relief.gd); a playing one keeps its own copy.
static func clear_cache() -> void:
	_cache.clear()


static func loop(k: String) -> AudioStreamWAV:
	if _cache.has(k):
		return _cache[k]
	var n := int(RATE * LOOP_S)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	var outdoor := k.begins_with("street")
	var night := k.ends_with("night")
	# A bed of soft noise: the room's hush indoors, the far traffic outside (low, slowly breathing).
	var y := 0.0
	var y2 := 0.0
	var bed := 0.05 if outdoor else 0.025
	var cut := 260.0 if outdoor else 160.0
	var a := TAU * cut / RATE
	for i in n:
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		y2 += a * (y - y2)
		var swell := 1.0 + (0.35 * sin(TAU * float(i) / n * 2.0) if outdoor else 0.0)   # whole cycles, so it loops cleanly
		buf[i] = y2 * 6.0 * bed * swell
	# Birds by day (muffled through the walls indoors), crickets at night.
	if night:
		var start := 0
		while start < n - RATE:
			start += int(rng.randf_range(0.5, 1.4) * RATE)
			for c in 3:
				_chirp_cricket(buf, start + c * int(RATE * 0.09), 4300.0 + rng.randf_range(-150, 150), 0.05 if outdoor else 0.02)
	else:
		var t := int(RATE * 0.4)
		while t < n - RATE:
			var f0 := rng.randf_range(2400.0, 3600.0)
			var notes := rng.randi_range(2, 4)
			for j in notes:
				_tweet(buf, t + j * int(RATE * 0.13), f0 * (1.0 + 0.12 * (j % 2)), 0.09 if outdoor else 0.035)
			t += int(rng.randf_range(1.2, 2.6) * RATE)
	# Outside by day: now and then a car passes (a slow swell of low noise).
	if outdoor and not night:
		_car(buf, int(n * 0.55), int(RATE * 2.2), rng)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := int(clampf(buf[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var w := Synth.looping(data, n, RATE)
	_cache[k] = w
	return w


static func _tweet(buf: PackedFloat32Array, at: int, f0: float, vol: float) -> void:
	var count := int(RATE * 0.08)
	var ph := 0.0
	for i in count:
		var idx := at + i
		if idx >= buf.size():
			return
		var p := float(i) / count
		var f := f0 * (1.0 + 0.35 * sin(p * PI))   # a little rise and fall
		ph += TAU * f / RATE
		buf[idx] += sin(ph) * sin(p * PI) * vol


static func _chirp_cricket(buf: PackedFloat32Array, at: int, f: float, vol: float) -> void:
	var count := int(RATE * 0.04)
	for i in count:
		var idx := at + i
		if idx >= buf.size():
			return
		var p := float(i) / count
		buf[idx] += sin(TAU * f * float(i) / RATE) * sin(p * PI) * vol * (0.6 + 0.4 * sin(TAU * 60.0 * float(i) / RATE))


static func _car(buf: PackedFloat32Array, at: int, count: int, rng: RandomNumberGenerator) -> void:
	var y := 0.0
	var a := TAU * 180.0 / RATE
	for i in count:
		var idx := at + i
		if idx >= buf.size():
			return
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		var p := float(i) / count
		buf[idx] += y * 0.5 * pow(sin(p * PI), 2.0)
