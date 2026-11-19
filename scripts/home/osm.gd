extends Node
## Your neighbourhood from OpenStreetMap (© OpenStreetMap contributors, ODbL): roads and paths, building
## outlines (with their courtyards), parks, water, land use, trees, street lamps, crossings, fences and
## named public places around your home, fetched once when you say so (the same "Look it up?" screen) and
## kept in my_home/osm.json, so the Light World works offline after. Asking again for the same spot reuses
## that map unless you tap Refresh. Finding where your home is: coordinates you pasted, or the helper's
## answer, or (only if you agreed) OpenStreetMap's own search, Nominatim. Neighbours' homes are kept as bare
## shapes: no names, numbers or anything else about them, ever (clean()).
##
## Kept extract (format 2): {"format": 2, "center": {"lat", "lon"}, "radius": m, "fetched": "", "credit",
##   "features": [{"kind": "road" | "path" | "building" | "park" | "water" | "wood" | "landuse" | "paved" | "sand"
##     | "barrier" | "poi" | "tree" | "bench" | "lamp" | "crossing" | "bus_stop" | "entrance", "sub": "...",
##     "name": "" (public places only), "pts": [[x, z], ...] (metres from your home, x east, z south),
##     "closed": bool, "holes": [[[x, z], ...], ...] (courtyards, islands), "ll": [lat, lon] (public places
##     only, for the reference links), plus what the map says about it: "width", "levels", "height",
##     "roof", "roof_colour", "colour", "lanes", "oneway", "sidewalk", "bridge"}],
##   "corrections": {...your own fixes, kept when the map is fetched again (hood_builder.gd)...}}
## Tags: [LIGHT_WORLD_MAP]

signal progress(line: String)
signal finished(result: Dictionary)   # {"ok", "state", "extract", "error", "stage", "code", "cached"}
signal state_changed(state: String)

const Validation := preload("res://scripts/home/map_validation.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const FORMAT := 2
const OVERPASS := "https://overpass-api.de/api/interpreter"
## The map servers you can choose in Settings > Light World > Helper setup > Map server: [label, address].
## Only the one you chose is asked (never another one behind your back): your coordinates go to its operator.
const MAP_SERVERS := [["OpenStreetMap main server (FOSSGIS, Germany)", "https://overpass-api.de/api/interpreter"],
	["OpenStreetMap France server", "https://overpass.openstreetmap.fr/api/interpreter"]]
const BUSY_HINT := " If it stays busy, pick another map server: Settings > Light World > Helper setup."
const NOMINATIM := "https://nominatim.openstreetmap.org/search"
const AGENT := "Polox/Update9 (personal desktop game; manual cached map requests)"
const CREDIT := "© OpenStreetMap contributors"
## The states a map lookup goes through (the panel shows them).
const STATES: PackedStringArray = ["consent_needed", "locating", "ambiguous", "requesting", "validating", "ready", "sparse", "offline", "cancelled", "failed"]
const ROADS := {"motorway": 12.0, "trunk": 11.0, "primary": 10.0, "secondary": 9.0, "tertiary": 8.0, "unclassified": 6.0,
	"residential": 6.0, "living_street": 5.0, "service": 4.0, "pedestrian": 4.0, "track": 3.0, "road": 6.0,
	"motorway_link": 7.0, "trunk_link": 7.0, "primary_link": 7.0, "secondary_link": 7.0, "tertiary_link": 6.0}
const PATHS: PackedStringArray = ["footway", "path", "cycleway", "steps", "bridleway"]
const PARKS: PackedStringArray = ["park", "garden", "playground", "pitch", "recreation_ground", "grass", "village_green", "meadow", "cemetery", "dog_park", "allotments", "orchard"]
const LANDUSE: PackedStringArray = ["residential", "commercial", "retail", "industrial", "farmland", "farmyard", "religious", "education"]
const WATERWAYS := {"river": 12.0, "canal": 8.0, "stream": 3.0, "ditch": 1.5, "drain": 1.5}
## Public places worth a name and a little care.
const PUBLIC_AMENITY: PackedStringArray = ["school", "library", "cafe", "restaurant", "pharmacy", "post_office", "place_of_worship",
	"community_centre", "kindergarten", "fast_food", "ice_cream", "bakery", "pub", "bar", "townhall", "fire_station", "clinic", "hospital",
	"police", "theatre", "cinema", "arts_centre", "marketplace", "bank", "doctors", "dentist", "university", "college"]
const MIN_STEP_M := 0.6        # points closer than this to the previous one are dropped (bounded save size)

var calls := 0      # (tests) live requests made
var state := "consent_needed"
var last_result: Dictionary = {}
var transport: Callable = Callable() # tests: return the HTTPRequest completion tuple
var _generation := 0
var _http: HTTPRequest
static var _next_request_at := 0


static func query(lat: float, lon: float, radius: int) -> String:
	var a := "(around:%d,%.6f,%.6f)" % [radius, lat, lon]
	var parts := PackedStringArray([
		"way[\"highway\"]%s;" % a,
		"way[\"building\"]%s;relation[\"building\"][\"type\"=\"multipolygon\"]%s;" % [a, a],
		"way[\"leisure\"]%s;relation[\"leisure\"][\"type\"=\"multipolygon\"]%s;" % [a, a],
		"way[\"landuse\"]%s;relation[\"landuse\"][\"type\"=\"multipolygon\"]%s;" % [a, a],
		"way[\"natural\"~\"^(water|wood|scrub|wetland|sand|beach|tree_row)$\"]%s;relation[\"natural\"~\"^(water|wood|scrub|wetland)$\"][\"type\"=\"multipolygon\"]%s;" % [a, a],
		"way[\"waterway\"]%s;relation[\"waterway\"=\"riverbank\"]%s;" % [a, a],
		"way[\"amenity\"]%s;relation[\"amenity\"][\"type\"=\"multipolygon\"]%s;node[\"amenity\"]%s;node[\"shop\"]%s;node[\"leisure\"]%s;" % [a, a, a, a, a],
		"way[\"barrier\"~\"^(fence|hedge|wall)$\"]%s;" % a,
		"node[\"natural\"=\"tree\"]%s;node[\"highway\"~\"^(street_lamp|crossing|bus_stop)$\"]%s;node[\"entrance\"]%s;" % [a, a, a],
	])
	return "[out:json][timeout:30][maxsize:33554432];(" + "".join(parts) + ");out geom qt 6000;"


## Local metres from the home point (x east, z south).
static func project(lat: float, lon: float, lat0: float, lon0: float) -> Vector2:
	return Vector2((lon - lon0) * 111320.0 * cos(deg_to_rad(lat0)), -(lat - lat0) * 110574.0)


## Back from local metres to latitude/longitude (public places' reference links).
static func unproject(p: Vector2, lat0: float, lon0: float) -> Array:
	var lat := lat0 - p.y / 110574.0
	var lon := lon0 + p.x / (111320.0 * maxf(0.01, cos(deg_to_rad(lat0))))
	return [snappedf(lat, 0.000001), snappedf(lon, 0.000001)]


## The street grid's size for a radius: an odd number of 60 x 60 blocks of 2.5 m cells (hood_builder.gd).
static func grid_chunks(radius: float) -> int:
	var g := int(ceil(radius * 2.0 / 2.5))
	var chunks := maxi(1, int(ceil(float(g) / 60.0)))
	return chunks + 1 if chunks % 2 == 0 else chunks


## Half the width of the street grid in metres: geometry beyond this (plus a margin) is cut off.
static func grid_half_m(radius: float) -> float:
	return grid_chunks(radius) * 60 * 2.5 / 2.0


## An Overpass answer -> the kept extract: only what the game draws, people left out.
static func clean(raw: Dictionary, lat0: float, lon0: float, radius: int) -> Dictionary:
	var feats: Array = []
	var half := grid_half_m(radius) + 20.0
	var box := Rect2(-half, -half, half * 2.0, half * 2.0)
	for el in raw.get("elements", []):
		if not el is Dictionary:
			continue
		var tags: Dictionary = el.get("tags", {}) if el.get("tags") is Dictionary else {}
		var type := str(el.get("type", ""))
		if type == "node":
			var p := project(float(el.get("lat", 0.0)), float(el.get("lon", 0.0)), lat0, lon0)
			if not box.has_point(p):
				continue
			var f := _classify(tags, "node", false)
			if f.is_empty():
				continue
			f["pts"] = [_pt(p)]
			f["closed"] = false
			if str(f.get("name", "")) != "":
				f["ll"] = [snappedf(float(el.get("lat", 0.0)), 0.000001), snappedf(float(el.get("lon", 0.0)), 0.000001)]
			feats.append(f)
		elif type == "way":
			var line := _project_list(el.get("geometry", []), lat0, lon0)
			if line.size() < 2:
				continue
			var closed: bool = line.size() > 3 and line[0].distance_to(line[-1]) < 0.05
			var f := _classify(tags, "way", closed)
			if f.is_empty():
				continue
			_emit(feats, f, line, [], closed, box, lat0, lon0)
		elif type == "relation":
			if str(tags.get("type", "")) != "multipolygon":
				continue
			var f := _classify(tags, "way", true)
			if f.is_empty() or str(f.kind) in ["road", "path", "barrier"]:
				continue
			var rings := _rings(el.get("members", []), lat0, lon0)
			for outer in rings.outer:
				var holes: Array = []
				for inner in rings.inner:
					if Geometry2D.is_point_in_polygon(inner[0], PackedVector2Array(outer)):
						holes.append(inner)
				_emit(feats, f.duplicate(true), outer, holes, true, box, lat0, lon0)
	return {"format": FORMAT, "center": {"lat": lat0, "lon": lon0}, "radius": radius, "fetched": Time.get_datetime_string_from_system(false, false),
		"features": feats, "credit": CREDIT}


static func _pt(p: Vector2) -> Array:
	return [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]


static func _project_list(geometry: Variant, lat0: float, lon0: float) -> Array:
	var out: Array = []
	if not geometry is Array:
		return out
	var n: int = (geometry as Array).size()
	for i in n:
		var g: Variant = geometry[i]
		if g is Dictionary and Validation.coordinates(g):
			var q := project(float(g.lat), float(g.lon), lat0, lon0)
			if out.is_empty() or (out[-1] as Vector2).distance_to(q) >= MIN_STEP_M:
				out.append(q)
			elif i == n - 1 and out.size() > 1:
				out[-1] = q   # keep the true end (a ring closes on its first point)
	return out


## A feature's geometry into the extract: lines cut to the grid (a long road or river crossing it keeps
## the part that matters), areas clipped to it (a lake or forest bigger than the neighbourhood).
static func _emit(feats: Array, f: Dictionary, pts: Array, holes: Array, closed: bool, box: Rect2, lat0: float, lon0: float) -> void:
	var area := closed and str(f.kind) in ["building", "park", "water", "wood", "landuse", "paved", "sand"]
	if not area:
		for piece in _clip_line(pts, box):
			var g := f.duplicate(true)
			g["pts"] = piece.map(func(q): return _pt(q))
			g["closed"] = closed and piece.size() == pts.size()
			feats.append(g)
		return
	var ring := pts.duplicate()
	if ring.size() > 1 and (ring[0] as Vector2).distance_to(ring[-1]) < 0.05:
		ring.pop_back()
	if ring.size() < 3:
		return
	var inside := ring.all(func(q): return box.has_point(q))
	var outers: Array = [ring]
	if not inside:
		var bp := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
		outers = []
		# A convex box can't cut a hole into an outline: every piece is an outer ring.
		for poly in Geometry2D.intersect_polygons(PackedVector2Array(ring), bp):
			outers.append(Array(poly))
	for outer in outers:
		if (outer as Array).size() < 3:
			continue
		var g := f.duplicate(true)
		var closed_ring: Array = (outer as Array).duplicate()
		closed_ring.append(outer[0])
		g["pts"] = closed_ring.map(func(q): return _pt(q))
		g["closed"] = true
		var kept: Array = []
		for h in holes:
			var hr: Array = (h as Array).duplicate()
			if hr.size() > 1 and (hr[0] as Vector2).distance_to(hr[-1]) < 0.05:
				hr.pop_back()
			if hr.size() >= 3 and Geometry2D.is_point_in_polygon(hr[0], PackedVector2Array(outer)):
				kept.append(hr.map(func(q): return _pt(q)))
		if not kept.is_empty():
			g["holes"] = kept
		if str(g.get("name", "")) != "":
			var c := Vector2.ZERO
			for q in outer:
				c += q
			g["ll"] = unproject(c / float((outer as Array).size()), lat0, lon0)
		feats.append(g)


## A polyline cut to a rectangle: the pieces inside it (Liang-Barsky per segment).
static func _clip_line(pts: Array, box: Rect2) -> Array:
	var pieces: Array = []
	var cur: Array = []
	for i in pts.size() - 1:
		var seg := _clip_segment(pts[i], pts[i + 1], box)
		if seg.is_empty():
			if cur.size() >= 2:
				pieces.append(cur)
			cur = []
			continue
		if cur.is_empty() or (cur[-1] as Vector2).distance_to(seg[0]) > 0.01:
			if cur.size() >= 2:
				pieces.append(cur)
			cur = [seg[0]]
		cur.append(seg[1])
	if cur.size() >= 2:
		pieces.append(cur)
	return pieces


static func _clip_segment(a: Vector2, b: Vector2, box: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var checks := [[-d.x, a.x - box.position.x], [d.x, box.end.x - a.x], [-d.y, a.y - box.position.y], [d.y, box.end.y - a.y]]
	for c in checks:
		var p: float = c[0]
		var q: float = c[1]
		if absf(p) < 1e-9:
			if q < 0.0:
				return []
			continue
		var r := q / p
		if p < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return []
	return [a + d * t0, a + d * t1]


## A multipolygon's members joined into closed rings: {"outer": [[Vector2...]...], "inner": [...]}. Ways
## that share end points are chained (a big lake is often drawn in several pieces); a ring that can't
## be closed is dropped rather than guessed.
static func _rings(members: Variant, lat0: float, lon0: float) -> Dictionary:
	var out := {"outer": [], "inner": []}
	if not members is Array:
		return out
	for role in ["outer", "inner"]:
		var parts: Array = []
		for m in members:
			if not m is Dictionary or str(m.get("type", "")) != "way":
				continue
			var r := str(m.get("role", ""))
			if (role == "outer" and r in ["outer", ""]) or (role == "inner" and r == "inner"):
				var line := _project_list(m.get("geometry", []), lat0, lon0)
				if line.size() >= 2:
					parts.append(line)
		while not parts.is_empty():
			var ring: Array = parts.pop_front()
			var guard := 0
			while ring[0].distance_to(ring[-1]) > 0.5 and guard < 500:
				guard += 1
				var joined := false
				for i in parts.size():
					var p: Array = parts[i]
					if (p[0] as Vector2).distance_to(ring[-1]) <= 0.5:
						ring.append_array(p.slice(1))
					elif (p[-1] as Vector2).distance_to(ring[-1]) <= 0.5:
						var rev := p.duplicate()
						rev.reverse()
						ring.append_array(rev.slice(1))
					else:
						continue
					parts.remove_at(i)
					joined = true
					break
				if not joined:
					break
			if ring.size() >= 4 and ring[0].distance_to(ring[-1]) <= 0.5:
				(out[role] as Array).append(ring)
	return out


## What a feature is, and its name only if it's a public place. Homes keep only what shapes them
## (levels, height, roof): never a name, number, owner or anything else.
static func _classify(tags: Dictionary, type: String, closed: bool) -> Dictionary:
	var name := str(tags.get("name", "")).left(60)
	var leisure := str(tags.get("leisure", ""))
	var landuse := str(tags.get("landuse", ""))
	var natural := str(tags.get("natural", ""))
	var amenity := str(tags.get("amenity", ""))
	if type == "node":
		if natural == "tree":
			return {"kind": "tree", "sub": "tree", "name": ""}
		if amenity == "bench":
			return {"kind": "bench", "sub": "bench", "name": ""}
		var hw := str(tags.get("highway", ""))
		if hw == "street_lamp":
			return {"kind": "lamp", "sub": "lamp", "name": ""}
		if hw == "crossing":
			return {"kind": "crossing", "sub": str(tags.get("crossing", "yes")).left(20), "name": ""}
		if hw == "bus_stop":
			return {"kind": "bus_stop", "sub": "bus_stop", "name": name}
		if tags.has("entrance"):
			return {"kind": "entrance", "sub": str(tags.entrance).left(20), "name": ""}
		var sh := str(tags.get("shop", ""))
		if (amenity in PUBLIC_AMENITY or sh != "" or leisure in ["playground", "park"]) and name != "":
			return {"kind": "poi", "sub": amenity if amenity != "" else (sh if sh != "" else leisure), "name": name}
		return {}
	if tags.has("highway"):
		var h := str(tags.highway)
		if str(tags.get("tunnel", "no")) in ["yes", "building_passage", "culvert"] or str(tags.get("area", "no")) == "yes":
			if str(tags.get("area", "no")) == "yes" and closed and h in ["pedestrian", "footway"]:
				return {"kind": "paved", "sub": "plaza", "name": name}
			return {}
		if ROADS.has(h):
			var f := {"kind": "road", "sub": h, "width": _width(tags, float(ROADS[h])), "name": name}
			_road_tags(f, tags)
			return f
		if h in PATHS:
			var p := {"kind": "path", "sub": h, "width": _width(tags, 2.0 if h != "cycleway" else 2.5), "name": ""}
			if str(tags.get("footway", "")) in ["sidewalk", "crossing"]:
				p["footway"] = str(tags.footway)
			return p
		return {}
	if tags.has("building") and closed:
		var shop := str(tags.get("shop", ""))
		var public := amenity in PUBLIC_AMENITY or shop != "" or str(tags.building) in ["school", "church", "public", "civic", "retail", "commercial", "library", "train_station", "hospital", "kindergarten", "townhall"]
		# Homes are shapes only: no name, number or anything else.
		var b := {"kind": "building", "sub": amenity if amenity != "" else (shop if shop != "" else ("public" if public else "home")), "name": name if public else ""}
		var lv := str(tags.get("building:levels", ""))
		b["levels"] = clampi(lv.to_int(), 1, 60) if lv.is_valid_int() and lv.to_int() >= 1 else 1
		if lv.is_valid_int() and lv.to_int() >= 1:
			b["levels_known"] = true
		var ht := str(tags.get("height", "")).trim_suffix(" m").trim_suffix("m").strip_edges()
		if ht.is_valid_float() and ht.to_float() > 1.0 and ht.to_float() < 400.0:
			b["height"] = snappedf(ht.to_float(), 0.1)
		var roof := str(tags.get("roof:shape", ""))
		if roof in ["flat", "gabled", "hipped", "pyramidal", "skillion", "half-hipped", "gambrel", "mansard", "dome", "round"]:
			b["roof"] = roof
		for k in [["roof:colour", "roof_colour"], ["building:colour", "colour"]]:
			var c := str(tags.get(k[0], "")).strip_edges().left(24)
			if c != "" and (Color.html_is_valid(c) or c.to_lower() in ["white", "red", "brown", "grey", "gray", "black", "beige", "yellow", "green", "blue", "orange", "darkgrey", "lightgrey"]):
				b[k[1]] = c
		return b
	if tags.has("barrier") and type == "way":
		var bt := str(tags.barrier)
		if bt in ["fence", "hedge", "wall"]:
			return {"kind": "barrier", "sub": bt, "name": ""}
		return {}
	if closed and (leisure in PARKS or landuse in PARKS):
		return {"kind": "park", "sub": leisure if leisure in PARKS else landuse, "name": name}
	if closed and leisure == "swimming_pool":
		return {"kind": "water", "sub": "pool", "width": 3.0, "name": ""}
	var waterway := str(tags.get("waterway", ""))
	if natural == "water" or waterway == "riverbank" or landuse in ["reservoir", "basin"]:
		if closed:
			return {"kind": "water", "sub": str(tags.get("water", "water")).left(20), "width": 3.0, "name": name}
		return {}
	if WATERWAYS.has(waterway):
		if str(tags.get("tunnel", "no")) in ["yes", "culvert"]:
			return {}
		return {"kind": "water", "sub": waterway, "width": _width(tags, float(WATERWAYS[waterway])), "name": name}
	if closed and (natural in ["wood", "scrub"] or landuse == "forest"):
		return {"kind": "wood", "sub": natural if natural != "" else "forest", "name": ""}
	if natural == "tree_row":
		return {"kind": "tree", "sub": "tree_row", "name": ""}
	if closed and natural in ["sand", "beach", "wetland"]:
		return {"kind": "sand" if natural != "wetland" else "park", "sub": natural, "name": ""}
	if closed and amenity in PUBLIC_AMENITY:
		return {"kind": "park" if amenity in ["school", "kindergarten", "university", "college"] else "building", "sub": amenity, "name": name}
	if closed and amenity == "parking":
		return {"kind": "paved", "sub": "parking", "name": ""}
	if closed and landuse in LANDUSE:
		return {"kind": "landuse", "sub": landuse, "name": ""}
	return {}


## A tagged width in metres ("7", "7 m"), else the usual one for its kind.
static func _width(tags: Dictionary, fallback: float) -> float:
	var w := str(tags.get("width", "")).trim_suffix(" m").trim_suffix("m").strip_edges()
	if w.is_valid_float() and w.to_float() >= 0.5 and w.to_float() <= 60.0:
		return snappedf(w.to_float(), 0.1)
	return fallback


## What the map says about a street's lanes and sidewalks (only what's tagged).
static func _road_tags(f: Dictionary, tags: Dictionary) -> void:
	var lanes := str(tags.get("lanes", ""))
	if lanes.is_valid_int() and lanes.to_int() >= 1 and lanes.to_int() <= 12:
		f["lanes"] = lanes.to_int()
		if not str(tags.get("width", "")).is_valid_float():
			f["width"] = maxf(float(f.width), 3.2 * lanes.to_int())
	if str(tags.get("oneway", "")) in ["yes", "1", "-1"]:
		f["oneway"] = true
	var sw := str(tags.get("sidewalk", tags.get("sidewalk:both", ""))).strip_edges()
	if sw == "" and (tags.has("sidewalk:left") or tags.has("sidewalk:right")):
		var l := str(tags.get("sidewalk:left", "no")) in ["yes", "separate"]
		var r := str(tags.get("sidewalk:right", "no")) in ["yes", "separate"]
		sw = "both" if l and r else ("left" if l else ("right" if r else "no"))
	if sw == "yes":
		sw = "both"
	if sw in ["both", "left", "right", "no", "none", "separate"]:
		f["sidewalk"] = "no" if sw == "none" else sw
	if str(tags.get("bridge", "no")) not in ["no", ""]:
		f["bridge"] = true


# --- The last good map ----------------------------------------------------------------------------

static func cache_path() -> String:
	return SaveManager.home_dir().path_join("osm.json")


## The map already kept for this very spot and radius ({} when there's none, or it's for elsewhere).
static func cached(lat: float, lon: float, radius: int) -> Dictionary:
	if not FileAccess.file_exists(cache_path()):
		return {}
	var e: Variant = JsonUtil.read_json(cache_path(), {})
	if not e is Dictionary or not Validation.extract_valid(e):
		return {}
	var c: Dictionary = e.center
	if absf(float(c.lat) - lat) > 0.00001 or absf(float(c.lon) - lon) > 0.00001 or int(e.radius) != radius:
		return {}
	return e


## Whether a map is too thin to be much of a neighbourhood (it's still kept if you say so).
static func is_sparse(extract: Dictionary) -> bool:
	var feats: Array = extract.get("features", [])
	if feats.size() < 3:
		return true
	return not feats.any(func(f): return str(f.get("kind", "")) in ["road", "building"])


# --- Fetching (only after you confirm) ------------------------------------------------------------

## The map around a point. The kept map for the same spot and radius is reused without asking anyone,
## unless `refresh` (the Refresh button).
func fetch(lat: float, lon: float, radius: int, refresh: bool = false) -> void:
	_generation += 1
	var ticket := _generation
	_cancel_http()
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if ticket != _generation or not is_inside_tree():
		return
	var valid := Validation.overpass({"elements": []}, lat, lon, radius)
	if not valid.ok:
		_finish(valid, ticket)
		return
	if not refresh:
		var kept := cached(lat, lon, radius)
		if not kept.is_empty():
			progress.emit("Using the map you already have. Refresh asks OpenStreetMap again.")
			_finish({"ok": true, "state": "sparse" if is_sparse(kept) else "ready", "extract": kept, "cached": true, "error": ""}, ticket)
			return
	_state("requesting")
	progress.emit("Asking OpenStreetMap for this area...")
	var body := "data=" + query(lat, lon, radius).uri_encode()
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded", "User-Agent: " + AGENT, "Accept: application/json"])
	var res := await _request(_endpoint("overpass_url", OVERPASS), headers, HTTPClient.METHOD_POST, body, ticket)
	if ticket != _generation:
		return
	if not res.ok:
		_finish(res, ticket)
		return
	_state("validating")
	progress.emit("Checking the map...")
	var text := str(res.body)
	if text.strip_edges().begins_with("<"):
		_finish(Validation.fail("validation", "html", "The map service sent a web page instead of map data. Your saved streets are unchanged."), ticket)
		return
	var raw: Variant = JSON.parse_string(text)
	valid = Validation.overpass(raw, lat, lon, radius)
	if valid.ok:
		var extract := clean(raw, lat, lon, radius)
		var old: Variant = JsonUtil.read_json(cache_path(), {}) if FileAccess.file_exists(cache_path()) else {}
		if old is Dictionary and old.get("corrections") is Dictionary:
			extract["corrections"] = (old.corrections as Dictionary).duplicate(true)   # your fixes stay
		if not Validation.extract_valid(extract):
			_finish(Validation.fail("validation", "extract", "The map couldn't be read safely. Your saved streets are unchanged."), ticket)
			return
		valid["extract"] = extract
		valid.state = "sparse" if is_sparse(extract) else "ready"
	_finish(valid, ticket)


## Where an address is, by OpenStreetMap's search (only when you agreed to it on the "Look it up?" screen).
func geocode(address: String) -> Dictionary:
	var result := await locate(address)
	if bool(result.get("ok", false)) and result.get("candidates", []).size() == 1:
		return {"lat": result.candidates[0].lat, "lon": result.candidates[0].lon}
	return {}


func locate(address: String) -> Dictionary:
	_generation += 1
	var ticket := _generation
	_cancel_http()
	_state("locating")
	var endpoint := _endpoint("nominatim_url", NOMINATIM)
	var cache_file := SaveManager.home_dir().path_join("location_cache.json")
	var cache: Variant = JsonUtil.read_json(cache_file, {})
	if not cache is Dictionary:
		cache = {}
	var key := (endpoint + "|" + address.strip_edges()).sha256_text()
	if cache.has(key):
		last_result = Validation.geocoding(cache[key])
		_state(str(last_result.state))
		return last_result
	var res := await _request(endpoint + "?format=jsonv2&limit=5&q=" + address.strip_edges().uri_encode(), PackedStringArray(["User-Agent: " + AGENT, "Accept: application/json"]), HTTPClient.METHOD_GET, "", ticket)
	if ticket != _generation:
		return {"ok": false, "state": "cancelled", "error": "Location lookup cancelled."}
	if not res.ok:
		last_result = res
		_state(str(res.state))
		return res
	if str(res.body).strip_edges().begins_with("<"):
		last_result = Validation.fail("locating", "html", "The location service sent a web page instead of an answer.")
		_state("failed")
		return last_result
	var raw: Variant = JSON.parse_string(str(res.body))
	last_result = Validation.geocoding(raw)
	if bool(last_result.ok):
		while cache.size() >= 32:
			cache.erase(cache.keys()[0])
		cache[key] = raw
		JsonUtil.write_json(cache_file, cache)
	_state(str(last_result.state))
	return last_result


func _endpoint(key: String, fallback: String) -> String:
	var settings: Variant = GameState.settings.get("light_world", {})
	var url := str(settings.get(key, fallback)).strip_edges() if settings is Dictionary else fallback
	return url if url.begins_with("https://") else fallback


func _state(value: String) -> void:
	state = value
	state_changed.emit(value)


func _finish(result: Dictionary, ticket: int) -> void:
	if ticket != _generation or not is_inside_tree():
		return
	last_result = result
	_state(str(result.get("state", "failed")))
	finished.emit(result)


func _cancel_http() -> void:
	if is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
	_http = null


func cancel() -> void:
	_generation += 1
	_cancel_http()
	_state("cancelled")
	last_result = {"ok": false, "state": "cancelled", "stage": "request", "code": "cancelled", "error": "Map lookup cancelled. Your saved streets are unchanged.", "extract": {}}
	finished.emit(last_result)


func _exit_tree() -> void:
	_generation += 1
	_cancel_http()


## Seconds until another request may go out (after a 429's Retry-After), 0 when free.
static func wait_seconds() -> int:
	return maxi(0, int(ceil((_next_request_at - Time.get_ticks_msec()) / 1000.0)))


## One serialized request at a time across callers, no server rotation. At most one retry, only
## for transient transport/5xx errors. A 429 is surfaced for explicit retry after its cooldown.
func _request(url: String, headers: PackedStringArray, method: int, body: String, ticket: int) -> Dictionary:
	var result := {}
	for attempt in 2:
		var said_wait := false
		while Time.get_ticks_msec() < _next_request_at and ticket == _generation and is_inside_tree():
			if not said_wait and wait_seconds() > 2:
				said_wait = true
				progress.emit("Waiting %d s before asking again (the map service asked for a pause)..." % wait_seconds())
			await get_tree().process_frame
		if ticket != _generation or not is_inside_tree():
			return {"ok": false, "state": "cancelled", "stage": "request", "code": "cancelled", "error": "Cancelled."}
		_next_request_at = Time.get_ticks_msec() + 1100
		var response: Array = []
		if transport.is_valid():
			response = await transport.call(url, headers, method, body)
		else:
			if not is_inside_tree():
				return {"ok": false, "state": "cancelled", "stage": "request", "code": "cancelled", "error": "Cancelled."}
			calls += 1
			var current := HTTPRequest.new()
			_http = current
			current.timeout = 35.0
			current.body_size_limit = 8 * 1024 * 1024
			add_child(current)
			var box := {"done": false, "response": []}
			current.request_completed.connect(func(a, b, c, d):
				box.response = [a, b, c, d]
				box.done = true, CONNECT_ONE_SHOT)
			if current.request(url, headers, method, body) != OK:
				box.response = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
				box.done = true
			var deadline := Time.get_ticks_msec() + 45000
			while not bool(box.done) and ticket == _generation and is_inside_tree() and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			if _http == current:
				_http = null
			if is_instance_valid(current):
				if not bool(box.done):
					current.cancel_request()
				current.queue_free()
			if ticket != _generation or not is_inside_tree():
				return {"ok": false, "state": "cancelled", "stage": "request", "code": "cancelled", "error": "Cancelled."}
			if not bool(box.done):
				box.response = [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
			response = box.response
		if ticket != _generation or not is_inside_tree():
			return {"ok": false, "state": "cancelled", "stage": "request", "code": "cancelled", "error": "Cancelled."}
		result = http_result(response)
		if bool(result.ok) or not bool(result.get("retry", false)) or attempt == 1:
			return result
		progress.emit("The map service didn't answer. Retrying once...")
		_next_request_at = maxi(_next_request_at, Time.get_ticks_msec() + 2500)
	return result


static func http_result(response: Array) -> Dictionary:
	if response.size() != 4:
		return Validation.fail("request", "transport", "No complete map response arrived.")
	var status := int(response[1])
	var transport_result := int(response[0])
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		if transport_result in [HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED]:
			return {"ok": false, "state": "failed", "stage": "request", "status": status, "retry": false, "code": "too_large",
				"error": "That area's map is too big to fetch at once. Choose a smaller radius; your saved streets are unchanged."}
		var code := "offline"
		match transport_result:
			HTTPRequest.RESULT_TIMEOUT:
				code = "timeout"
			HTTPRequest.RESULT_CANT_RESOLVE:
				code = "dns"
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
				code = "tls"
		# A server that is reachable but never answers is a busy server, not a broken connection (seen
		# for real with the main server while the French one answered in 4 s): say so, and where to switch.
		var said := "The map service didn't answer in time. Your saved streets still work offline." + BUSY_HINT if code == "timeout" \
			else "The map connection failed. Your saved streets still work offline."
		return {"ok": false, "state": "offline", "stage": "request", "status": status, "retry": code != "tls",
			"code": code, "error": said}
	if status == 429:
		var wait_ms := 60000
		for header in response[2]:
			if str(header).to_lower().begins_with("retry-after:"):
				var value := str(header).get_slice(":", 1).strip_edges()
				if value.is_valid_int():
					wait_ms = clampi(value.to_int(), 2, 3600) * 1000
		_next_request_at = maxi(_next_request_at, Time.get_ticks_msec() + wait_ms)
		return {"ok": false, "state": "failed", "stage": "request", "status": status, "code": "rate_limit", "retry": false, "wait_s": wait_ms / 1000,
			"error": "The map service is limiting requests. Wait before Retry; your saved map is unchanged." + BUSY_HINT}
	if status != 200:
		return {"ok": false, "state": "failed", "stage": "request", "status": status, "code": "http", "retry": status in [502, 503, 504],
			"error": ("The map service returned HTTP %d. Your saved map is unchanged." % status) + (BUSY_HINT if status >= 500 else "")}
	return {"ok": true, "state": "validating", "body": (response[3] as PackedByteArray).get_string_from_utf8(), "status": status}


## A short line for the panel: which step failed, its status, and what to do next. Never the address,
## a key, the request or the service's own words.
static func diagnostic(r: Dictionary) -> String:
	if bool(r.get("ok", false)):
		return ""
	var stage := str(r.get("stage", "request"))
	var code := str(r.get("code", r.get("state", "failed")))
	var status := int(r.get("status", 0))
	var what: String = {"request": "Asking the map service", "validation": "Checking the map", "location": "The location", "locating": "Finding the location"}.get(stage, "Mapping")
	var next := "Retry later; nothing was changed."
	match code:
		"timeout":
			next = "The service is busy. Retry in a few minutes, or pick another map server in Helper setup."
		"offline", "dns", "transport":
			next = "Check the internet connection, then Retry. Your saved streets still work."
		"tls":
			next = "The secure connection failed. Check the computer's clock and connection, then Retry."
		"rate_limit":
			next = "Wait %d s, then Retry." % maxi(wait_seconds(), int(r.get("wait_s", 0)))
		"http":
			next = "The service is busy or down. Retry in a few minutes." if status >= 500 else "The request was refused. Try a smaller radius, or Retry later."
		"html":
			next = "That's usually a busy server. Retry in a few minutes."
		"schema", "element", "tags", "geometry", "relation", "coordinates", "extract":
			next = "The answer wasn't a usable map. Retry later; nothing was changed."
		"partial", "extent", "too_large":
			next = "Choose a smaller radius, then Retry."
		"wrong_location", "bounds":
			next = "Adjust the location (paste coordinates from a map app)."
		"cancelled":
			next = "Retry whenever you like."
	var parts := PackedStringArray([what, code.replace("_", " ")])
	if status > 0:
		parts.append("HTTP %d" % status)
	return "%s • Next: %s" % [" • ".join(parts), next]


## Coordinates pasted from a map app ("40.7128, -74.0060") or a Google Maps link, or {}.
static func parse_coords(text: String) -> Dictionary:
	var from_link: Dictionary = load("res://scripts/home/google_maps.gd").parse_link(text)
	if not from_link.is_empty():
		return from_link
	var t := text.strip_edges().replace("(", "").replace(")", "").replace(";", ",")
	var parts := t.split(",", false)
	if parts.size() != 2:
		parts = t.split(" ", false)
	if parts.size() != 2 or not parts[0].strip_edges().is_valid_float() or not parts[1].strip_edges().is_valid_float():
		return {}
	var lat := parts[0].strip_edges().to_float()
	var lon := parts[1].strip_edges().to_float()
	if not is_finite(lat) or not is_finite(lon) or absf(lat) > 90.0 or absf(lon) > 180.0:
		return {}
	return {"lat": lat, "lon": lon}
