extends RefCounted
## Bullet patterns: what flies at your heart during the enemy's turn. Pure maths, so the battle,
## the Battle Maker's play-test and the tests all agree, and seeded, so a pattern plays the same
## way every time (scrubbing the play-test to 2.5 s always shows the same thing).
##
## A wave: {"duration": s, "box": {"w": px, "h": px}, "spawners": [spawner...]}
## A spawner: {"bullet": "<bullet id>", "path": "straight"|"aimed"|"arc"|"wave"|"spiral"|"orbit"|
##   "bounce"|"traced", "from": "top"|"bottom"|"left"|"right"|"center"|"point", "point": [x, y]
##   (0..1 of the box), "every": s, "count": n per burst, "speed": px/s, "spread": degrees,
##   "start": s, "stop": s, "angle": degrees, "turn": degrees/s, "amp": px, "freq": Hz,
##   "radius": px, "trace": [[x, y], ...] (0..1 of the box, for "traced"), "size": scale}
## Positions are in box pixels, (0, 0) = the box's top-left. Bullets that leave the box (plus a
## margin) are gone.

const PATHS: PackedStringArray = ["straight", "aimed", "arc", "wave", "spiral", "orbit", "bounce", "traced"]
const FROMS: PackedStringArray = ["top", "bottom", "left", "right", "center", "point"]
const MARGIN := 40.0
const GRAVITY := 260.0    # "arc" bullets fall like a thrown ball
const MAX_BULLETS := 200
const PULSE_RESERVE := 24
const MODES := ["free", "gravity", "shield", "shooter"]
const RULES := ["normal", "still", "move"]
const HAZARDS := ["hurt", "slow"]


static func spawner_defaults() -> Dictionary:
	return {"bullet": "dot", "path": "straight", "from": "top", "point": [0.5, 0.0], "every": 0.6, "count": 1, "speed": 120.0,
		"spread": 0.0, "start": 0.0, "stop": -1.0, "angle": 90.0, "turn": 90.0, "amp": 40.0, "freq": 1.0, "radius": 60.0,
		"trace": [], "size": 1.0, "seed": 1, "rule": "normal", "fragile": false}


static func clean_spawner(s: Dictionary) -> Dictionary:
	var out := spawner_defaults()
	for k in out:
		if s.has(k):
			out[k] = s[k]
	if not str(out.path) in PATHS:
		out.path = "straight"
	if not str(out.from) in FROMS:
		out.from = "top"
	for f in [["every", 0.08, 10.0], ["count", 1, 12], ["speed", -400, 500], ["size", 0.3, 3.0], ["spread", 0, 360], ["angle", -360, 360], ["start", 0, 15], ["stop", -1, 15], ["turn", -360, 360], ["amp", 0, 120], ["freq", 0.1, 4], ["radius", 0, 160], ["seed", 0, 999999]]:
		out[f[0]] = number(out[f[0]], float(spawner_defaults()[f[0]]), float(f[1]), float(f[2]))
	out.count = int(out.count)
	out.seed = int(out.seed)
	if not str(out.rule) in RULES:
		out.rule = "normal"
	out.fragile = bool(out.fragile)
	out.point = point(out.point, [0.5, 0.0])
	var trace: Array = []
	if out.trace is Array:
		for p in (out.trace as Array).slice(0, 64):
			if p is Array and p.size() == 2:
				trace.append(point(p, [0, 0]))
	out.trace = trace
	var bullet := str(out.bullet)
	if bullet.begins_with("custom:"):
		var id := bullet.trim_prefix("custom:")
		if id == "" or id.contains("/") or id.contains("\\") or id.contains(":") or id.contains("."):
			bullet = "dot"
	out.bullet = bullet.left(64)
	return out


static func number(v: Variant, fallback: float, lo: float, hi: float) -> float:
	return clampf(float(v), lo, hi) if (v is float or v is int) and is_finite(float(v)) else fallback


static func point(v: Variant, fallback: Array) -> Array:
	if not v is Array or v.size() != 2:
		return fallback.duplicate()
	return [number(v[0], float(fallback[0]), 0, 1), number(v[1], float(fallback[1]), 0, 1)]


static func clean_wave(raw: Dictionary) -> Dictionary:
	var box: Dictionary = raw.get("box", {}) if raw.get("box") is Dictionary else {}
	var out := {"name": str(raw.get("name", "Wave")).left(48), "duration": number(raw.get("duration"), 6, 2, 15),
		"box": {"w": number(box.get("w"), 240, 120, 420), "h": number(box.get("h"), 160, 80, 300)}, "spawners": [],
		"telegraph": number(raw.get("telegraph"), 0.8, 0.5, 3),
		"mode": str(raw.get("mode", "free")), "rotation": number(raw.get("rotation"), 0, -30, 30),
		"hint": str(raw.get("hint", "")).left(140), "hazards": []}
	# Hazard zones inside the box (0..1 of it): "hurt" stings like a bullet, "slow" halves your speed.
	if raw.get("hazards") is Array:
		for h in (raw.hazards as Array).slice(0, 4):
			if h is Dictionary:
				var kind := str(h.get("kind", "hurt"))
				out.hazards.append({"kind": kind if kind in HAZARDS else "hurt", "x": number(h.get("x"), 0.0, 0, 0.95), "y": number(h.get("y"), 0.8, 0, 0.95),
					"w": number(h.get("w"), 1.0, 0.05, 1), "h": number(h.get("h"), 0.2, 0.05, 1)})
	if not out.mode in MODES:
		out.mode = "free"
	out.box["end_w"] = number(box.get("end_w"), float(out.box.w), 120, 420)
	out.box["end_h"] = number(box.get("end_h"), float(out.box.h), 80, 300)
	if raw.get("spawners") is Array:
		for s in (raw.spawners as Array).slice(0, 6):
			if s is Dictionary:
				out.spawners.append(clean_spawner(s))
	return out


## A cleaned wave, ready to be sampled many times a second: its spawners are cleaned once and each
## knows how long its bullets can possibly stay near the box (`_life`), so bursts that are long gone
## are skipped instead of recomputed. bullets_at takes a raw wave or a prepared one; the bullets are
## the same either way (tests compare them).
static func prepare(raw: Dictionary) -> Dictionary:
	if bool(raw.get("_ready", false)):
		return raw
	var w := clean_wave(raw)
	var box := Vector2(float(w.box.w), float(w.box.h))
	for si in w.spawners.size():
		var s: Dictionary = w.spawners[si]
		s["_life"] = _lifetime(s, box.max(Vector2(float(w.box.end_w), float(w.box.end_h))))
		var origins_cache := PackedVector2Array()
		var ids: Array = []
		var end := float(s.stop) if float(s.stop) >= 0 else float(w.duration)
		var bursts := mini(400, maxi(0, int(ceil((end - float(s.start)) / float(s.every))) + 1))
		var rng := RandomNumberGenerator.new()
		for n in bursts:
			rng.seed = hash("%d-%d" % [int(s.seed), n])
			origins_cache.append(_origin(s, box, n, rng) / box)
			for k in int(s.count):
				ids.append("%d:%d:%d" % [si, n, k])
		s["_origins"] = origins_cache
		s["_ids"] = ids
	w["_ready"] = true
	return w


## Seconds after which every bullet of one burst is outside the box and its margin for good (generous).
static func _lifetime(s: Dictionary, box: Vector2) -> float:
	# How far a bullet can travel from where its path is centred and still be near the box: the
	# farthest corner of the box plus its margin, from either end of the edge (or the point) it starts on.
	var ends: Array = []
	var pt: Array = s.point
	match str(s.from):
		"top": ends = [Vector2(0, -10), Vector2(box.x, -10)]
		"bottom": ends = [Vector2(0, box.y + 10), Vector2(box.x, box.y + 10)]
		"left": ends = [Vector2(-10, 0), Vector2(-10, box.y)]
		"right": ends = [Vector2(box.x + 10, 0), Vector2(box.x + 10, box.y)]
		"center": ends = [box / 2.0]
		_: ends = [Vector2(float(pt[0]) * box.x, float(pt[1]) * box.y)]
	if str(s.path) == "orbit" and str(s.from) != "point":
		ends = [box / 2.0]
	elif str(s.path) == "traced":   # (anywhere on the drawn line, which may lie anywhere in the box)
		ends = [Vector2.ZERO, Vector2(box.x, 0), Vector2(0, box.y), box]
	var reach := 0.0
	for e in ends:
		for c in [Vector2(-MARGIN, -MARGIN), Vector2(box.x + MARGIN, -MARGIN), Vector2(-MARGIN, box.y + MARGIN), Vector2(box.x + MARGIN, box.y + MARGIN)]:
			reach = maxf(reach, (e as Vector2).distance_to(c))
	reach += 4.0
	var v := absf(float(s.speed))
	var life := INF
	match str(s.path):
		"straight", "aimed", "spiral":
			life = reach / v if v > 0.001 else INF
		"wave":
			life = (reach + float(s.amp)) / v if v > 0.001 else INF
		"arc":
			life = (v + sqrt(v * v + 2.0 * GRAVITY * reach)) / GRAVITY
		"orbit":
			life = (reach + float(s.radius)) / (v * 0.1) if v > 0.001 else INF
		"bounce":
			life = 6.0
		"traced":
			var length := 0.0
			var pts: Array = s.get("trace", [])
			for i in pts.size() - 1:
				length += Vector2(float(pts[i][0]) * box.x, float(pts[i][1]) * box.y).distance_to(Vector2(float(pts[i + 1][0]) * box.x, float(pts[i + 1][1]) * box.y))
			life = (length + reach) / v if v > 0.001 else INF
	return life * 1.02 + 0.05 if is_finite(life) else INF


## Every bullet alive at time `t` in a wave, for a heart at `heart` (aimed bullets aim where the
## heart was when they were fired: `heart_at` gives the heart's position at a time, or null).
## Returns [{x, y, bullet, size, born, spawner, shot, id}]. Deterministic for the same inputs.
static func bullets_at(wave: Dictionary, t: float, heart_at: Callable = Callable()) -> Array:
	wave = prepare(wave)
	var box := box_at(wave, t)
	var out: Array = []
	var sp_list: Array = wave.spawners
	var limit := capacity(wave)
	for si in sp_list.size():
		var s: Dictionary = sp_list[si]
		var start := float(s.start)
		var stop := float(s.stop) if float(s.stop) >= 0.0 else float(wave.get("duration", 6.0))
		var every := float(s.every)
		var life := float(s.get("_life", INF))
		var n := 0
		if is_finite(life) and t - life > start:
			n = maxi(0, int(floor((t - life - start) / every)) - 1)   # (older bursts are all gone)
		var fired := start + n * every
		while fired <= minf(t, stop) + 0.0001 and n < 400:
			var o := _burst_origin(s, box, n)
			for k in int(s.count):
				var p := _place(s, box, o, fired, t - fired, k, heart_at)
				if p.x > -MARGIN and p.y > -MARGIN and p.x < box.x + MARGIN and p.y < box.y + MARGIN:
					out.append({"x": p.x, "y": p.y, "bullet": str(s.bullet), "size": float(s.size), "born": fired, "spawner": si, "shot": k, "id": "%d:%d:%d" % [si, n, k], "rule": s.rule, "fragile": s.fragile})
					if out.size() >= limit:
						return out
			n += 1
			fired = start + n * every
	return out


static func capacity(wave: Dictionary) -> int:
	return MAX_BULLETS - PULSE_RESERVE if str(wave.get("mode", "free")) == "shooter" else MAX_BULLETS


static func box_at(wave: Dictionary, t: float) -> Vector2:
	var b: Dictionary = wave.box if wave.has("box") else {}
	var start := Vector2(float(b.get("w", 240)), float(b.get("h", 160)))
	var finish := Vector2(float(b.get("end_w", start.x)), float(b.get("end_h", start.y)))
	return start.lerp(finish, smoothstep(0.0, float(wave.get("duration", 6.0)), t))


static func rotation_at(wave: Dictionary, t: float) -> float:
	return deg_to_rad(float(wave.get("rotation", 0))) * sin(PI * clampf(t / float(wave.get("duration", 6.0)), 0, 1))


## Where a spawner's bursts fire from, and the warning shown before a turn: [{kind, at}] in 0..1 of
## the box ("edge" with a side, "point", "center").
static func origins(wave: Dictionary) -> Array:
	var out: Array = []
	var prepared := prepare(wave)
	var box := Vector2(float(prepared.box.w), float(prepared.box.h))
	for s in prepared.spawners:
		if str(s.path) in ["traced", "orbit"]:
			for k in int(s.count):
				var at := position(s, box, float(s.start), 0.0, k, 0) / box
				out.append({"kind": "point", "at": [at.x, at.y]})
			continue
		match str(s.from):
			"top", "bottom", "left", "right":
				out.append({"kind": "edge", "side": str(s.from), "aimed": str(s.path) == "aimed"})
			"center":
				out.append({"kind": "center", "at": [0.5, 0.5]})
			_:
				out.append({"kind": "point", "at": s.point, "aimed": str(s.path) == "aimed"})
	return out


static func _burst_origin(s: Dictionary, box: Vector2, n: int) -> Vector2:
	if s.has("_origins") and n < s._origins.size():
		return s._origins[n] * box
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d-%d" % [int(s.get("seed", 1)), n])
	return _origin(s, box, n, rng)


static func _origin(s: Dictionary, box: Vector2, burst: int, rng: RandomNumberGenerator) -> Vector2:
	match str(s.from):
		"top":
			return Vector2(rng.randf() * box.x, -10.0)
		"bottom":
			return Vector2(rng.randf() * box.x, box.y + 10.0)
		"left":
			return Vector2(-10.0, rng.randf() * box.y)
		"right":
			return Vector2(box.x + 10.0, rng.randf() * box.y)
		"center":
			return box / 2.0
	var pt: Array = s.get("point", [0.5, 0.0])
	return Vector2(float(pt[0]) * box.x, float(pt[1]) * box.y)


## Where one bullet is, `age` seconds after it was fired at `fired` (burst `n`, `k` of the burst).
static func position(s: Dictionary, box: Vector2, fired: float, age: float, k: int, n: int, heart_at: Callable = Callable()) -> Vector2:
	return _place(s, box, _burst_origin(s, box, n), fired, age, k, heart_at)


static func _place(s: Dictionary, box: Vector2, o: Vector2, fired: float, age: float, k: int, heart_at: Callable) -> Vector2:
	var count := int(s.count)
	var spread := deg_to_rad(float(s.spread))
	var fan := 0.0 if count <= 1 else (float(k) / (count - 1) - 0.5) * spread
	var base := deg_to_rad(float(s.angle))
	match str(s.from):   # straight in from the side it starts on, unless an angle is given
		"left":
			base = 0.0 if float(s.angle) == 90.0 else base
		"right":
			base = PI if float(s.angle) == 90.0 else base
		"bottom":
			base = -PI / 2.0 if float(s.angle) == 90.0 else base
	var speed := float(s.speed)
	match str(s.path):
		"straight":
			return o + Vector2.from_angle(base + fan) * speed * age
		"aimed":
			var target: Vector2 = box / 2.0
			if heart_at.is_valid():
				var h: Variant = heart_at.call(fired)
				if h is Vector2:
					target = h
			var dir := (target - o).normalized() if target != o else Vector2.DOWN
			return o + dir.rotated(fan) * speed * age
		"arc":
			var v := Vector2.from_angle(base + fan) * speed
			return o + v * age + Vector2(0, GRAVITY * 0.5 * age * age)
		"wave":
			var dir2 := Vector2.from_angle(base + fan)
			var side := dir2.orthogonal()
			return o + dir2 * speed * age + side * sin(age * TAU * float(s.freq) + k) * float(s.amp)
		"spiral":
			var c := box / 2.0 if str(s.from) == "center" else o
			var ang := base + fan + deg_to_rad(float(s.turn)) * (fired + age) + TAU * k / maxf(1.0, count)
			return c + Vector2.from_angle(ang) * speed * age
		"orbit":
			var c2 := box / 2.0 if str(s.from) in ["center", "top", "bottom", "left", "right"] else o
			var r := float(s.radius) + speed * 0.1 * age
			var ang2 := base + TAU * k / maxf(1.0, count) + deg_to_rad(float(s.turn)) * age
			return c2 + Vector2.from_angle(ang2) * r
		"bounce":
			var p := o + Vector2.from_angle(base + fan) * speed * age
			return Vector2(_fold(p.x, box.x), _fold(p.y, box.y)) if age < 6.0 else Vector2(-999, -999)
		"traced":
			var pts: Array = s.trace
			if pts.size() < 2:
				return o + Vector2.from_angle(base) * speed * age
			return _along(pts, box, speed * age) + Vector2(k * 14.0, 0)
	return o


## Reflects a coordinate back into 0..size (a bullet bouncing off the box's walls).
static func _fold(v: float, size: float) -> float:
	if size <= 0.0:
		return v
	var m := fposmod(v, size * 2.0)
	return m if m <= size else size * 2.0 - m


## The point `dist` pixels along a drawn path (0..1 points of the box); past the end: gone.
static func _along(pts: Array, box: Vector2, dist: float) -> Vector2:
	var left := dist
	for i in pts.size() - 1:
		var a := Vector2(float(pts[i][0]) * box.x, float(pts[i][1]) * box.y)
		var b := Vector2(float(pts[i + 1][0]) * box.x, float(pts[i + 1][1]) * box.y)
		var seg := a.distance_to(b)
		if left <= seg:
			return a.lerp(b, left / maxf(0.001, seg))
		left -= seg
	return Vector2(-999, -999)


# --- Templates (15+) ----------------------------------------------------------------------------

## Built-in waves the Battle Maker and the battle templates start from.
const TEMPLATES := {
	"rain": {"name": "Gentle rain", "duration": 6.0, "box": {"w": 240, "h": 160}, "spawners": [{"bullet": "drop", "path": "straight", "from": "top", "every": 0.25, "speed": 110}]},
	"downpour": {"name": "Downpour", "duration": 6.0, "box": {"w": 240, "h": 160}, "spawners": [{"bullet": "drop", "path": "straight", "from": "top", "every": 0.12, "speed": 170}]},
	"crosswind": {"name": "Crosswind", "duration": 6.0, "box": {"w": 260, "h": 140}, "spawners": [{"bullet": "leaf", "path": "wave", "from": "left", "every": 0.5, "speed": 110, "amp": 30}, {"bullet": "leaf", "path": "wave", "from": "right", "every": 0.5, "start": 0.25, "speed": 110, "amp": 30}]},
	"aimed_trio": {"name": "Aimed trio", "duration": 6.0, "box": {"w": 220, "h": 160}, "spawners": [{"bullet": "star", "path": "aimed", "from": "top", "every": 0.9, "count": 3, "spread": 30, "speed": 150}]},
	"spiral": {"name": "Spiral", "duration": 7.0, "box": {"w": 220, "h": 220}, "spawners": [{"bullet": "dot", "path": "spiral", "from": "center", "every": 0.15, "count": 2, "speed": 80, "turn": 140}]},
	"double_spiral": {"name": "Double spiral", "duration": 7.0, "box": {"w": 240, "h": 240}, "spawners": [{"bullet": "dot", "path": "spiral", "from": "center", "every": 0.12, "count": 4, "speed": 70, "turn": -110}]},
	"orbit": {"name": "Orbiting ring", "duration": 6.0, "box": {"w": 220, "h": 220}, "spawners": [{"bullet": "dot", "path": "orbit", "from": "center", "every": 2.0, "count": 8, "radius": 30, "speed": 160, "turn": 70}]},
	"fountain": {"name": "Fountain", "duration": 6.0, "box": {"w": 240, "h": 180}, "spawners": [{"bullet": "drop", "path": "arc", "from": "point", "point": [0.5, 1.0], "angle": -90, "spread": 70, "count": 3, "every": 0.5, "speed": 260}]},
	"bouncers": {"name": "Bouncers", "duration": 7.0, "box": {"w": 220, "h": 160}, "spawners": [{"bullet": "ball", "path": "bounce", "from": "point", "point": [0.1, 0.1], "angle": 35, "every": 1.6, "speed": 140, "stop": 4.0}]},
	"pincer": {"name": "Pincer", "duration": 6.0, "box": {"w": 280, "h": 120}, "spawners": [{"bullet": "dot", "path": "straight", "from": "left", "every": 0.4, "speed": 150}, {"bullet": "dot", "path": "straight", "from": "right", "every": 0.4, "start": 0.2, "speed": 150}]},
	"from_below": {"name": "From below", "duration": 6.0, "box": {"w": 240, "h": 160}, "spawners": [{"bullet": "bubble", "path": "wave", "from": "bottom", "angle": -90, "every": 0.35, "speed": 90, "amp": 18, "freq": 1.5}]},
	"zigzag": {"name": "Zigzag", "duration": 6.0, "box": {"w": 240, "h": 160}, "spawners": [{"bullet": "spark", "path": "traced", "from": "point", "every": 0.45, "speed": 160, "trace": [[0.0, 0.1], [0.3, 0.5], [0.0, 0.9], [0.5, 0.95]]}]},
	"fan": {"name": "Fan", "duration": 6.0, "box": {"w": 260, "h": 170}, "spawners": [{"bullet": "petal", "path": "straight", "from": "point", "point": [0.5, 0.0], "angle": 90, "spread": 120, "count": 7, "every": 1.1, "speed": 120}]},
	"heart_hug": {"name": "Hug (gentle orbit)", "duration": 5.0, "box": {"w": 200, "h": 200}, "spawners": [{"bullet": "heart", "path": "orbit", "from": "center", "every": 2.5, "count": 6, "radius": 90, "speed": -80, "turn": 40}]},
	"snow": {"name": "Snowfall", "duration": 7.0, "box": {"w": 260, "h": 170}, "spawners": [{"bullet": "flake", "path": "wave", "from": "top", "every": 0.2, "speed": 60, "amp": 22, "freq": 0.7}]},
	"meteor": {"name": "Meteors", "duration": 6.0, "box": {"w": 260, "h": 170}, "spawners": [{"bullet": "rock", "path": "straight", "from": "top", "angle": 60, "every": 0.7, "speed": 210, "size": 1.6}]},
	"crossfire": {"name": "Crossfire", "duration": 7.0, "box": {"w": 240, "h": 240}, "spawners": [{"bullet": "dot", "path": "straight", "from": "top", "every": 0.5, "speed": 140}, {"bullet": "dot", "path": "straight", "from": "left", "every": 0.5, "start": 0.25, "speed": 140}]},
}
const TEMPLATE_ORDER: PackedStringArray = ["rain", "downpour", "crosswind", "aimed_trio", "spiral", "double_spiral", "orbit", "fountain", "bouncers", "pincer", "from_below", "zigzag", "fan", "heart_hug", "snow", "meteor", "crossfire"]


static func template(id: String) -> Dictionary:
	return (TEMPLATES.get(id, TEMPLATES.rain) as Dictionary).duplicate(true)


## A wave made gentler or harder: speeds and fire rates scaled (assists, story mode, difficulty).
static func scaled(wave: Dictionary, speed_mul: float, rate_mul: float) -> Dictionary:
	var w := wave.duplicate(true)
	w.erase("_ready")   # (a prepared wave's lifetimes no longer hold)
	for s in w.get("spawners", []):
		s.erase("_life")
		s["speed"] = float(s.get("speed", 120)) * speed_mul
		s["every"] = float(s.get("every", 0.6)) / maxf(0.05, rate_mul)
	return w
