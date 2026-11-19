extends RefCounted
## Friendships between residents (0-100), stored in world.json "bonds" under
## a "a|b" key (ids sorted). They grow when residents chat or hang out, and
## every friend knows who else lives here and how close they are.

static func key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func _all() -> Dictionary:
	if not GameState.world.has("bonds") or not GameState.world.bonds is Dictionary:
		GameState.world["bonds"] = {}
	return GameState.world.bonds


static func value(a: String, b: String) -> float:
	return float(_all().get(key(a, b), 0.0))


static func add(a: String, b: String, amount: float, save: bool = true) -> float:
	if a == b or a == "" or b == "":
		return 0.0
	var v := clampf(value(a, b) + amount, 0.0, 100.0)
	_all()[key(a, b)] = snappedf(v, 0.01)
	if save:
		GameState.save_world()
	return v


static func label(v: float) -> String:
	if v >= 80.0:
		return "best friends"
	if v >= 50.0:
		return "close friends"
	if v >= 25.0:
		return "friends"
	if v >= 5.0:
		return "getting to know each other"
	return "just met"


## Prompt line: the other residents and how this friend feels about them.
static func others_line(c: Dictionary, limit: int = 6) -> String:
	var me := str(c.get("id", ""))
	var parts := PackedStringArray()
	for id in GameState.characters:
		if id == me or parts.size() >= limit:
			continue
		var other: Dictionary = GameState.characters[id]
		parts.append("%s (%s)" % [other.get("name", id), label(value(me, id))])
	return ", ".join(parts)
