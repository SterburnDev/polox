extends RefCounted
## Three-way merge of a JSON file the PC and the phone both changed since they last agreed (`base`).
## Field by field: what only one side changed is taken from that side; what both changed the same way
## is kept; lists of things with an "id" merge thing by thing; named sets (tags, discoveries...) merge
## additions and removals; ordered lists conflict as a whole. Timestamps take the later one, counters add both
## sides' steps. Only a value both changed differently is a real conflict: the PC's value stays (as it
## always did) and the path is reported, and the phone's whole file is still kept in conflicts/.
## Before this, any file both sides touched kept the PC's version whole, so a phone's progress could
## be set aside just because the PC had noted the time.

## Leaf keys that are moments in time: the later one wins.
const TIME_KEYS: PackedStringArray = ["last_seen", "last_update_unix", "beat", "updated", "last_played", "seen", "modified", "last_sync"]
## Leaf keys (or parents) that count things: both sides' steps are added.
const COUNT_PARENTS: PackedStringArray = ["almanac", "counts"]
const COUNT_KEYS: PackedStringArray = ["playtime", "playtime_s", "played_s", "visits", "times", "count_total"]
## Only named collections are sets. Positions, colours, tile grids and animation frames are ordered.
const SET_KEYS: PackedStringArray = ["tags", "likes", "dislikes", "discoveries", "unlocked", "completed"]


## {"merged": Variant, "conflicts": [path strings]}.
static func merge3(base: Variant, mine: Variant, theirs: Variant) -> Dictionary:
	var conflicts: Array = []
	var merged: Variant = _merge(base, mine, theirs, "", conflicts)
	return {"merged": merged, "conflicts": conflicts}


static func _merge(b: Variant, m: Variant, t: Variant, path: String, conflicts: Array) -> Variant:
	if _same(m, t):
		return m
	if _same(b, m):
		return t
	if _same(b, t):
		return m
	# Both changed, differently.
	if m is Dictionary and t is Dictionary:
		return _merge_dict(b if b is Dictionary else {}, m, t, path, conflicts)
	if m is Array and t is Array:
		return _merge_array(b if b is Array else [], m, t, path, conflicts)
	var key := path.get_slice("/", path.get_slice_count("/") - 1)
	if key in TIME_KEYS or key.ends_with("_unix") or key.ends_with("_at"):
		return _later(m, t)
	if (m is int or m is float) and (t is int or t is float) and (b is int or b is float) and _is_count(path):
		return float(m) + float(t) - float(b) if (m is float or t is float or b is float) else int(m) + int(t) - int(b)
	conflicts.append(path if path != "" else "/")
	return m


static func _merge_dict(b: Dictionary, m: Dictionary, t: Dictionary, path: String, conflicts: Array) -> Dictionary:
	var out := {}
	var keys: Array = m.keys()
	for k in t.keys():
		if not k in keys:
			keys.append(k)
	for k in keys:
		var p := path + "/" + str(k)
		var in_m := m.has(k)
		var in_t := t.has(k)
		if in_m and in_t:
			out[k] = _merge(b.get(k), m[k], t[k], p, conflicts)
		elif in_m:
			# The phone removed it: gone, unless the PC changed it meanwhile.
			if b.has(k) and _same(b[k], m[k]):
				continue
			if b.has(k):
				conflicts.append(p)
			out[k] = m[k]
		else:
			if b.has(k) and _same(b[k], t[k]):
				continue   # the PC removed it and the phone didn't touch it
			if b.has(k):
				conflicts.append(p)
				continue   # the PC removed it, the phone changed it: the PC's way stays
			out[k] = t[k]
	return out


static func _merge_array(b: Array, m: Array, t: Array, path: String, conflicts: Array) -> Array:
	if _ids(m) and _ids(t) and (b.is_empty() or _ids(b)):
		return _merge_by_id(b, m, t, path, conflicts)
	if not path.get_slice("/", path.get_slice_count("/") - 1) in SET_KEYS:
		conflicts.append(path)
		return m
	# As sets: start from the PC's list, add what only the phone added, drop what only the phone removed.
	var out: Array = m.duplicate()
	for x in t:
		if not _has(b, x) and not _has(out, x):
			out.append(x)
	for x in b:
		if not _has(t, x) and _has(out, x) and _has(m, x):
			out.remove_at(_index(out, x))
	return out


static func _merge_by_id(b: Array, m: Array, t: Array, path: String, conflicts: Array) -> Array:
	var bi := _by_id(b)
	var ti := _by_id(t)
	var mi := _by_id(m)
	var out: Array = []
	for x in m:
		var id := str(x.get("id"))
		if ti.has(id):
			out.append(_merge(bi.get(id), x, ti[id], path + "[" + id + "]", conflicts))
		elif bi.has(id) and _same(bi[id], x):
			continue   # the phone removed it, the PC didn't change it
		else:
			if bi.has(id):
				conflicts.append(path + "[" + id + "]")
			out.append(x)
	for x in t:
		var id := str(x.get("id"))
		if mi.has(id):
			continue
		if bi.has(id):
			if not _same(bi[id], x):
				conflicts.append(path + "[" + id + "]")
			continue   # the PC removed it
		out.append(x)
	return out


static func _is_count(path: String) -> bool:
	var parts := path.split("/", false)
	if parts.is_empty():
		return false
	if parts[parts.size() - 1] in COUNT_KEYS:
		return true
	for p in parts:
		if p in COUNT_PARENTS:
			return true
	return false


static func _later(a: Variant, b: Variant) -> Variant:
	if (a is int or a is float) and (b is int or b is float):
		return a if float(a) >= float(b) else b
	return a if str(a) >= str(b) else b


static func _ids(a: Array) -> bool:
	if a.is_empty():
		return true
	var seen := {}
	for x in a:
		if not x is Dictionary or not (x as Dictionary).has("id") or seen.has(str(x.id)):
			return false
		seen[str(x.id)] = true
	return true


static func _by_id(a: Array) -> Dictionary:
	var out := {}
	for x in a:
		if x is Dictionary and (x as Dictionary).has("id"):
			out[str(x.id)] = x
	return out


static func _has(a: Array, x: Variant) -> bool:
	return _index(a, x) >= 0


static func _index(a: Array, x: Variant) -> int:
	for i in a.size():
		if _same(a[i], x):
			return i
	return -1


## Equal as JSON (1 and 1.0 are the same: a JSON round trip turns ints into floats).
static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in a:
			if not (b as Dictionary).has(k) or not _same(a[k], b[k]):
				return false
		return true
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same(a[i], b[i]):
				return false
		return true
	return a == b
