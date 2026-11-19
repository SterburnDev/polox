extends RefCounted
## Strict data boundary before an external map can replace the last good extract.
## Tags: [LIGHT_WORLD_MAP]
const MAX_ELEMENTS := 6000
const MAX_POINTS := 100000
const MAX_FEATURES := 12000
const KINDS: PackedStringArray = ["road", "path", "building", "park", "water", "wood", "poi", "tree", "bench", "landuse", "paved", "sand",
	"barrier", "lamp", "crossing", "bus_stop", "entrance"]
## Your own fixes to the streets (osm.json "corrections", hood_builder.gd): allowed values.
const CORRECTIONS := {"yard": ["", "fence", "hedge", "open"], "driveway": ["", "yes", "no"], "front": ["", "n", "e", "s", "w"],
	"sidewalks": ["", "none"], "lights": ["", "none"]}


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func coordinates(value: Variant) -> bool:
	return value is Dictionary and number(value.get("lat")) and number(value.get("lon")) and absf(float(value.lat)) <= 90.0 and absf(float(value.lon)) <= 180.0


static func fail(stage: String, code: String, message: String) -> Dictionary:
	return {"ok": false, "state": "failed", "stage": stage, "code": code, "error": message, "extract": {}}


static func overpass(raw: Variant, lat: float, lon: float, radius: int) -> Dictionary:
	if not coordinates({"lat": lat, "lon": lon}) or radius < 25 or radius > 1000:
		return fail("location", "bounds", "Choose valid coordinates and a radius from 25 to 1,000 metres.")
	if not raw is Dictionary or not raw.get("elements") is Array:
		return fail("validation", "schema", "The map service returned an invalid map. Your saved streets are unchanged.")
	if raw.has("remark") or raw.has("error") or raw.elements.size() >= MAX_ELEMENTS:
		return fail("validation", "partial", "The map may be incomplete. Try a smaller area; your saved streets are unchanged.")
	var points := 0
	var near := 0
	for el in raw.elements:
		if not el is Dictionary or not str(el.get("type", "")) in ["node", "way", "relation"] or not number(el.get("id")):
			return fail("validation", "element", "The map contains an invalid feature. Try refreshing later.")
		if float(el.id) <= 0 or float(el.id) != floor(float(el.id)):
			return fail("validation", "element", "The map contains an invalid feature identifier.")
		if el.has("tags") and not el.tags is Dictionary:
			return fail("validation", "tags", "The map contains invalid feature details.")
		var lines: Array = []   # each a list of points; segments only within one list
		if str(el.type) == "node":
			lines = [[el]]
		elif str(el.type) == "way":
			if not el.get("geometry") is Array or el.geometry.size() < 2:
				return fail("validation", "geometry", "A street or outline is incomplete. Your saved streets are unchanged.")
			lines = [el.geometry]
		else:
			if not el.get("members") is Array:
				return fail("validation", "relation", "A map boundary is incomplete.")
			for member in el.members:
				if not member is Dictionary or not str(member.get("type", "")) in ["node", "way", "relation"]:
					return fail("validation", "relation", "A map boundary is malformed.")
				if member.has("role") and not member.role is String:
					return fail("validation", "relation", "A map boundary is malformed.")
				match str(member.type):
					"way":
						if not member.get("geometry") is Array or member.geometry.size() < 2:
							return fail("validation", "partial", "A map boundary is missing its outline.")
						lines.append(member.geometry)
					"node":
						if member.has("lat"):
							lines.append([member])
					# Nested relations carry no geometry here: they're skipped, not guessed.
		for line in lines:
			var previous := Vector2.INF
			for p in line:
				if not coordinates(p):
					return fail("validation", "coordinates", "A map point is invalid. Your saved streets are unchanged.")
				points += 1
				if points > MAX_POINTS:
					return fail("validation", "extent", "The map has too many points. Try a smaller area.")
				var local := Vector2((float(p.lon) - lon) * 111320.0 * cos(deg_to_rad(lat)), (float(p.lat) - lat) * 110574.0)
				# A long road or river can cross the circle with every vertex far outside it (and a
				# big park or lake relation can reach far away): the segment, not the vertex, counts.
				var distance := local.length()
				if previous != Vector2.INF:
					distance = minf(distance, Geometry2D.get_closest_point_to_segment(Vector2.ZERO, previous, local).length())
				if distance <= float(radius) + 150.0:
					near += 1
				previous = local
	if points > 0 and near == 0:
		return fail("validation", "wrong_location", "The map does not match this location. Check the coordinates.")
	return {"ok": true, "state": "sparse" if raw.elements.size() < 3 else "ready", "error": ""}


static func geocoding(raw: Variant) -> Dictionary:
	if not raw is Array or raw.size() > 10:
		return fail("locating", "schema", "The location service returned an invalid answer.")
	var candidates: Array = []
	for item in raw:
		if not item is Dictionary:
			return fail("locating", "schema", "The location service returned an invalid candidate.")
		var point := {}
		for k in ["lat", "lon"]:
			var value: Variant = item.get(k)
			if number(value):
				point[k] = float(value)
			elif value is String and value.is_valid_float():
				point[k] = value.to_float()
		if not coordinates(point):
			return fail("locating", "coordinates", "The location service returned invalid coordinates.")
		point["label"] = str(item.get("display_name", "Map location")).left(240)
		candidates.append(point)
	return {"ok": not candidates.is_empty(), "state": "ambiguous" if candidates.size() > 1 else ("ready" if candidates.size() == 1 else "sparse"),
		"candidates": candidates, "error": "No matching location. Try coordinates copied from a map." if candidates.is_empty() else ""}


static func _ring(pts: Variant, min_points: int) -> int:
	if not pts is Array or (pts as Array).size() < min_points:
		return -1
	for p in pts:
		if not p is Array or p.size() != 2 or not number(p[0]) or not number(p[1]) or absf(float(p[0])) > 200000 or absf(float(p[1])) > 200000:
			return -1
	return (pts as Array).size()


static func extract_valid(extract: Dictionary) -> bool:
	if not coordinates(extract.get("center")) or not number(extract.get("radius")) or float(extract.radius) < 25 or float(extract.radius) > 1000:
		return false
	if not extract.get("features") is Array or extract.features.size() > MAX_FEATURES:
		return false
	if extract.has("corrections") and not corrections_valid(extract.corrections):
		return false
	if extract.has("format") and (not number(extract.format) or float(extract.format) < 1 or float(extract.format) > 99):
		return false
	var points := 0
	for feature in extract.features:
		if not feature is Dictionary or not str(feature.get("kind", "")) in KINDS:
			return false
		var kind := str(feature.kind)
		var need := 2 if kind in ["road", "path", "barrier"] else (3 if kind in ["building", "park", "wood", "landuse", "paved", "sand"] else 1)
		var n := _ring(feature.get("pts"), need)
		if n < 0:
			return false
		points += n
		if feature.has("holes"):
			if not feature.holes is Array or feature.holes.size() > 200:
				return false
			for h in feature.holes:
				var hn := _ring(h, 3)
				if hn < 0:
					return false
				points += hn
		if feature.has("width") and (not number(feature.width) or float(feature.width) <= 0 or float(feature.width) > 100):
			return false
		if feature.has("levels") and (not number(feature.levels) or float(feature.levels) != floor(float(feature.levels)) or float(feature.levels) < 1 or float(feature.levels) > 100):
			return false
		if feature.has("height") and (not number(feature.height) or float(feature.height) <= 0 or float(feature.height) > 500):
			return false
		if feature.has("lanes") and (not number(feature.lanes) or float(feature.lanes) < 1 or float(feature.lanes) > 12):
			return false
		if feature.has("ll") and (not feature.ll is Array or feature.ll.size() != 2 or not coordinates({"lat": feature.ll[0], "lon": feature.ll[1]})):
			return false
		for key in ["closed", "oneway", "bridge", "levels_known"]:
			if feature.has(key) and not feature[key] is bool:
				return false
		for key in ["name", "sub", "roof", "roof_colour", "colour", "sidewalk", "footway"]:
			if feature.has(key) and (not feature[key] is String or feature[key].length() > 512):
				return false
		if points > MAX_POINTS:
			return false
	return true


static func corrections_valid(c: Variant) -> bool:
	if not c is Dictionary or (c as Dictionary).size() > 16:
		return false
	for k in c:
		if not CORRECTIONS.has(str(k)) or not c[k] is String or not str(c[k]) in CORRECTIONS[str(k)]:
			return false
	return true
