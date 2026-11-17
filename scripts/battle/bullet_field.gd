extends RefCounted
## Fixed storage for a wave. Sampling only overwrites slots; no nodes or dictionaries
## are created in the dodge loop. The Maker's scrubber uses the same path maths.

const Patterns := preload("res://scripts/battle/patterns.gd")
const FLAGS_PER_SPAWNER := 400 * 12
const REMOVED := 1
const GRAZED := 2

class Bullet extends RefCounted:
	var position := Vector2.ZERO
	var kind := "dot"
	var scale := 1.0
	var born := 0.0
	var spawner := 0
	var shot := 0
	var key := 0
	var id := ""
	var rule := "normal"
	var fragile := false

var slots: Array[Bullet] = []
var count := 0
var peak := 0
var flags := PackedByteArray()
var wave: Dictionary = {}
var overflow := false
var limit := Patterns.MAX_BULLETS


func _init() -> void:
	slots.resize(Patterns.MAX_BULLETS)
	for i in slots.size():
		slots[i] = Bullet.new()
	flags.resize(FLAGS_PER_SPAWNER * 6)


func reset(raw: Dictionary) -> void:
	wave = Patterns.prepare(raw)
	limit = Patterns.capacity(wave)
	flags.fill(0)
	count = 0
	peak = 0
	overflow = false


func sample(t: float, box: Vector2, heart_at: Callable) -> void:
	count = 0
	for si in wave.spawners.size():
		var s: Dictionary = wave.spawners[si]
		var start := float(s.start)
		var stop := float(s.stop) if float(s.stop) >= 0 else float(wave.duration)
		var every := float(s.every)
		var life := float(s._life)
		var n := maxi(0, int(floor((t - life - start) / every)) - 1) if is_finite(life) and t - life > start else 0
		var fired := start + n * every
		while fired <= minf(t, stop) + 0.0001 and n < s._origins.size():
			var origin: Vector2 = s._origins[n] * box
			for k in int(s.count):
				var key: int = si * FLAGS_PER_SPAWNER + n * 12 + k
				if flags[key] & REMOVED:
					continue
				var p := Patterns._place(s, box, origin, fired, t - fired, k, heart_at)
				if p.x <= -Patterns.MARGIN or p.y <= -Patterns.MARGIN or p.x >= box.x + Patterns.MARGIN or p.y >= box.y + Patterns.MARGIN:
					continue
				if count == limit:
					overflow = true
					peak = count
					return
				var b := slots[count]
				b.position = p
				b.kind = s.bullet
				b.scale = float(s.size)
				b.born = fired
				b.spawner = si
				b.shot = k
				b.key = key
				b.id = s._ids[n * int(s.count) + k]
				b.rule = s.rule
				b.fragile = bool(s.fragile)
				count += 1
			n += 1
			fired = start + n * every
	peak = maxi(peak, count)


func remove(b: Bullet) -> void:
	flags[b.key] |= REMOVED


func removed(b: Bullet) -> bool:
	return bool(flags[b.key] & REMOVED)


func graze_once(b: Bullet) -> bool:
	if flags[b.key] & GRAZED:
		return false
	flags[b.key] |= GRAZED
	return true
