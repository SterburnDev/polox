extends Node
## Optional Google Maps integration for players with Google Gemini, Google AI Plus / Google One AI,
## or Google Maps Platform keys. Off by default: nothing is ever sent to Google unless the player
## explicitly turns it on in Settings > Light World > Helper setup and confirms the lookup.
##
## Three ways it works:
##   1. Gemini Maps Grounding (recommended for Gemini / Google AI Plus / Google One users):
##      Uses the player's Gemini key with Google's `google_maps` grounding tool to enrich nearby
##      public landmarks, parks, shops, and neighborhood atmosphere around the mapped Light World.
##   2. Google Maps Places API (New):
##      Optional direct nearby public-place search using a Google Maps API key, with a strict field
##      mask requesting only public place names, coordinates, types, and Google Maps links.
##   3. Offline Google Maps link parser (always available, zero network):
##      Paste any Google Maps URL (`@lat,lon`, `?q=lat,lon`, `!3dLAT!4dLON`) into address or
##      coordinate fields and Polox extracts coordinates locally without contacting any server.
##
## Privacy rule (matching osm.gd): neighbours' private homes and personal details are never kept;
## only public landmarks, parks, transit, and shops are merged, and API keys are never logged.
## Tags: [LIGHT_WORLD_MAP] [AI_HELPER]

signal progress(line: String)
signal finished(result: Dictionary)

const Osm := preload("res://scripts/home/osm.gd")
const Validation := preload("res://scripts/home/map_validation.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const KeyFormat := preload("res://scripts/ai/key_format.gd")
const Research := preload("res://scripts/home/research.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")

const CACHE_FILE := "google_maps.json"
const CREDIT := "Google Maps"
const GEMINI_ENDPOINT_FMT := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
const PLACES_NEARBY_URL := "https://places.googleapis.com/v1/places:searchNearby"
const GEOCODE_URL := "https://maps.googleapis.com/maps/api/geocode/json"

const MODES: PackedStringArray = ["gemini_grounding", "places_api", "links_only"]
const MODE_LABELS := {
	"gemini_grounding": "Gemini Maps Grounding (Gemini / Google AI Plus)",
	"places_api": "Google Maps Places API (Maps API key)",
	"links_only": "Google Maps links & URL paste only (no key)",
}

## Public place categories requested from Places API (New): strictly public places, never residences.
const PUBLIC_PLACE_TYPES: PackedStringArray = [
	"park", "library", "cafe", "bakery", "restaurant", "book_store",
	"museum", "school", "community_center", "transit_station", "bus_stop", "grocery_store",
]

## Injectable HTTP transport for offline unit tests: func(url, headers, method, body) -> [res, code, hdrs, bytes].
var transport: Callable = Callable()
var calls := 0
var _generation := 0
var _http: HTTPRequest


# --- Settings & availability -----------------------------------------------------------------------

static func _lw() -> Dictionary:
	var raw: Variant = GameState.settings.get("light_world", {})
	return raw if raw is Dictionary else {}


static func is_enabled() -> bool:
	return bool(_lw().get("google_maps_enabled", false))


static func mode() -> String:
	var chosen := str(_lw().get("google_maps_mode", "gemini_grounding"))
	return chosen if chosen in MODES else "gemini_grounding"


static func maps_api_key() -> String:
	var raw := str(_lw().get("google_maps_api_key", "")).strip_edges()
	return raw if KeyFormat.fits(raw, "gemini") else ""


## Active key for the selected Google Maps mode ("" if none configured or links_only).
static func active_key() -> String:
	match mode():
		"places_api":
			var explicit := maps_api_key()
			return explicit if explicit != "" else Research.gemini_key()
		"gemini_grounding":
			var gem := Research.gemini_key()
			return gem if gem != "" else maps_api_key()
		_:
			return ""


static func can_fetch() -> bool:
	return is_enabled() and mode() != "links_only" and active_key() != ""


static func status_summary() -> String:
	if not is_enabled():
		return "Off (opt-in in Helper setup)"
	if mode() == "links_only":
		return "Links & URL paste only (offline)"
	if active_key() == "":
		if mode() == "gemini_grounding":
			return "Add your Gemini key in Settings > AI (or paste a Maps key below)"
		return "Add a Google Maps API key below"
	return "Ready (%s)" % str(MODE_LABELS.get(mode(), mode()))


static func cache_path() -> String:
	return HomeStore.path(CACHE_FILE)


static func load_cached() -> Dictionary:
	if not FileAccess.file_exists(cache_path()):
		return {}
	var data: Variant = JsonUtil.read_json(cache_path(), {})
	return data if data is Dictionary else {}


static func save_cached(payload: Dictionary) -> bool:
	return JsonUtil.write_json(cache_path(), payload)


# --- Offline Google Maps URL / coordinate parser ---------------------------------------------------

## Extracts {"lat": float, "lon": float} from a Google Maps URL or coordinate snippet, or {}.
## Recognizes:
##   - https://www.google.com/maps/@37.4220,-122.0841,17z
##   - https://www.google.com/maps/place/Name/@37.4220,-122.0841,16z/data=!3d37.422!4d-122.084
##   - https://www.google.com/maps/search/?api=1&query=37.4220%2C-122.0841
##   - https://maps.google.com/?q=37.4220,-122.0841
##   - https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=37.4220,-122.0841
static func parse_link(text: String) -> Dictionary:
	var trimmed := text.strip_edges()
	if trimmed == "" or not (trimmed.contains("google.") or trimmed.contains("goo.gl") or trimmed.contains("@") or trimmed.contains("!3d")):
		return {}
	var decoded := trimmed.uri_decode()
	# Prefer exact pin coordinates (!3dLAT!4dLON) when present in a place URL.
	var pin_re := RegEx.create_from_string("!3d(-?\\d+(?:\\.\\d+)?)!4d(-?\\d+(?:\\.\\d+)?)")
	var pin_match := pin_re.search(decoded)
	if pin_match:
		return _valid_lat_lon(pin_match.get_string(1).to_float(), pin_match.get_string(2).to_float())
	# Camera center (@lat,lon) in Maps URLs.
	var at_re := RegEx.create_from_string("@(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)")
	var at_match := at_re.search(decoded)
	if at_match:
		return _valid_lat_lon(at_match.get_string(1).to_float(), at_match.get_string(2).to_float())
	# Query / viewpoint parameters (?q=lat,lon, &query=lat,lon, &viewpoint=lat,lon, &ll=lat,lon).
	var q_re := RegEx.create_from_string("(?:[?&](?:q|query|viewpoint|ll)=)(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)")
	var q_match := q_re.search(decoded)
	if q_match:
		return _valid_lat_lon(q_match.get_string(1).to_float(), q_match.get_string(2).to_float())
	return {}


static func _valid_lat_lon(lat: float, lon: float) -> Dictionary:
	if not is_finite(lat) or not is_finite(lon) or absf(lat) > 90.0 or absf(lon) > 180.0:
		return {}
	return {"lat": snappedf(lat, 0.000001), "lon": snappedf(lon, 0.000001)}


## Safe Google Maps web URL for a place or coordinate pair (only https:// links are ever emitted).
static func place_url(lat: float, lon: float, place_id: String = "") -> String:
	var base := "https://www.google.com/maps/search/?api=1&query=%.6f%%2C%.6f" % [lat, lon]
	if place_id != "" and _safe_place_id(place_id):
		return base + "&query_place_id=" + place_id.uri_encode()
	return base


static func _safe_place_id(pid: String) -> bool:
	if pid.length() < 4 or pid.length() > 160:
		return false
	for ch in pid:
		if not (ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"):
			return false
	return true


static func _safe_google_maps_uri(uri: String) -> String:
	var clean := uri.strip_edges()
	var lower := clean.to_lower()
	if lower.begins_with("https://maps.google.com/") or lower.begins_with("https://www.google.com/maps/") or lower.begins_with("https://maps.app.goo.gl/"):
		return clean
	return ""


# --- Gemini Google Maps Grounding payload & parser -------------------------------------------------

## Builds the Gemini `generateContent` request body with Google Maps + Google Search grounding.
static func build_grounding_body(prompt: String, lat: float, lon: float, include_maps_tool: bool = true) -> Dictionary:
	var tools: Array = []
	if include_maps_tool:
		tools.append({"google_maps": {}})
	tools.append({"google_search": {}})
	var body := {
		"contents": [{"role": "user", "parts": [{"text": prompt}]}],
		"tools": tools,
	}
	if include_maps_tool and is_finite(lat) and is_finite(lon) and (absf(lat) > 0.0001 or absf(lon) > 0.0001):
		body["toolConfig"] = {
			"retrievalConfig": {
				"latLng": {"latitude": lat, "longitude": lon}
			}
		}
	return body


## Copy-paste prompt for Gemini / Google AI Plus web subscribers who don't use an API key.
static func manual_grounding_prompt(lat: float, lon: float, radius: int) -> String:
	return (
		"Use Google Maps to list up to 12 notable public places (parks, cafes, libraries, schools, "
		+ "shops, transit stops) within %d metres of coordinates %.6f, %.6f. " % [clampi(radius, 50, 1500), lat, lon]
		+ "Do NOT include any private residences or people's names. "
		+ "Return strictly JSON: {\"atmosphere\": \"short cozy description\", \"places\": "
		+ "[{\"name\": \"...\", \"kind\": \"park|cafe|library|shop|school|transit|landmark\", "
		+ "\"lat\": 0.0, \"lon\": 0.0, \"note\": \"short public note\"}]}"
	)


## Extracts verified Google Maps grounding sources from a Gemini API candidate's groundingMetadata.
static func parse_grounding_chunks(reply: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for cand in reply.get("candidates", []):
		if not cand is Dictionary or not cand.get("groundingMetadata") is Dictionary:
			break
		var meta: Dictionary = cand.groundingMetadata
		for chunk in meta.get("groundingChunks", []):
			if not chunk is Dictionary or not chunk.get("maps") is Dictionary:
				continue
			var maps_data: Dictionary = chunk.maps
			var title := str(maps_data.get("title", "")).strip_edges().left(60)
			var uri := _safe_google_maps_uri(str(maps_data.get("uri", "")))
			var place_id := str(maps_data.get("placeId", "")).strip_edges()
			if title == "" or seen.has(title.to_lower()):
				continue
			seen[title.to_lower()] = true
			out.append({
				"name": title,
				"uri": uri,
				"place_id": place_id if _safe_place_id(place_id) else "",
				"source": "google_maps",
			})
		break
	return out


## Parses Gemini's JSON + Google Maps groundingChunks into clean public Polox POI entries.
static func parse_gemini_places(reply: Dictionary, lat0: float, lon0: float, radius: int) -> Dictionary:
	var grounded_chunks := parse_grounding_chunks(reply)
	var chunk_by_name := {}
	for ch in grounded_chunks:
		chunk_by_name[str(ch.name).to_lower()] = ch

	var text := Research.gemini_text(reply)
	var parsed: Variant = Research._json_in(text)
	var atmosphere := ""
	var places: Array = []
	var seen := {}
	var max_dist := float(maxi(radius, 100)) * 1.4

	if parsed is Dictionary:
		atmosphere = str((parsed as Dictionary).get("atmosphere", "")).strip_edges().left(220)
		var raw_places: Variant = (parsed as Dictionary).get("places", [])
		if raw_places is Array:
			for item in raw_places:
				if not item is Dictionary:
					continue
				var name := str(item.get("name", "")).strip_edges().left(60)
				if name == "" or seen.has(name.to_lower()):
					continue
				var kind := _clean_kind(str(item.get("kind", "landmark")))
				var plat := float(item.get("lat", 0.0))
				var plon := float(item.get("lon", 0.0))
				var entry := {
					"name": name,
					"sub": kind,
					"note": str(item.get("note", "")).strip_edges().left(120),
					"source": "google_maps",
				}
				if absf(plat) > 0.0001 or absf(plon) > 0.0001:
					var projected := Osm.project(plat, plon, lat0, lon0)
					if projected.length() <= max_dist:
						entry["ll"] = [snappedf(plat, 0.000001), snappedf(plon, 0.000001)]
						entry["pts"] = [[snappedf(projected.x, 0.1), snappedf(projected.y, 0.1)]]
				if chunk_by_name.has(name.to_lower()):
					var matched: Dictionary = chunk_by_name[name.to_lower()]
					if str(matched.uri) != "":
						entry["maps_uri"] = str(matched.uri)
					if str(matched.place_id) != "":
						entry["place_id"] = str(matched.place_id)
				elif entry.has("ll"):
					entry["maps_uri"] = place_url(float(entry.ll[0]), float(entry.ll[1]))
				seen[name.to_lower()] = true
				places.append(entry)

	# Include any grounded Google Maps chunks not already listed in the JSON array.
	for ch in grounded_chunks:
		var lower := str(ch.name).to_lower()
		if not seen.has(lower):
			seen[lower] = true
			places.append({
				"name": str(ch.name),
				"sub": "landmark",
				"note": "",
				"maps_uri": str(ch.uri),
				"place_id": str(ch.place_id),
				"source": "google_maps",
			})

	return {
		"atmosphere": atmosphere,
		"places": places,
		"grounded": not grounded_chunks.is_empty(),
		"credit": CREDIT,
	}


## Parses Google Maps Places API (New) `searchNearby` JSON into clean public Polox POI entries.
static func parse_places_api(raw: Variant, lat0: float, lon0: float, radius: int) -> Dictionary:
	var places: Array = []
	if not raw is Dictionary:
		return {"atmosphere": "", "places": places, "grounded": false, "credit": CREDIT}
	var max_dist := float(maxi(radius, 100)) * 1.4
	var seen := {}
	for entry in (raw as Dictionary).get("places", []):
		if not entry is Dictionary:
			continue
		var display: Variant = entry.get("displayName", {})
		var name := str(display.get("text", "") if display is Dictionary else display).strip_edges().left(60)
		if name == "" or seen.has(name.to_lower()):
			continue
		var loc: Variant = entry.get("location", {})
		if not loc is Dictionary:
			continue
		var plat := float(loc.get("latitude", 0.0))
		var plon := float(loc.get("longitude", 0.0))
		var projected := Osm.project(plat, plon, lat0, lon0)
		if projected.length() > max_dist:
			continue
		var types: Array = entry.get("types", []) if entry.get("types") is Array else []
		var sub := _clean_kind(str(types[0]) if not types.is_empty() else "landmark")
		var uri := _safe_google_maps_uri(str(entry.get("googleMapsUri", "")))
		if uri == "":
			uri = place_url(plat, plon)
		seen[name.to_lower()] = true
		places.append({
			"name": name,
			"sub": sub,
			"note": "",
			"ll": [snappedf(plat, 0.000001), snappedf(plon, 0.000001)],
			"pts": [[snappedf(projected.x, 0.1), snappedf(projected.y, 0.1)]],
			"maps_uri": uri,
			"source": "google_maps",
		})
	return {"atmosphere": "", "places": places, "grounded": not places.is_empty(), "credit": CREDIT}


static func _clean_kind(raw_kind: String) -> String:
	var k := raw_kind.strip_edges().to_lower().replace(" ", "_")
	if k in ["park", "cafe", "bakery", "restaurant", "library", "school", "shop", "book_store", "museum", "transit", "transit_station", "bus_stop", "grocery_store", "community_center", "landmark"]:
		return k
	return "landmark"


## Merges public Google Maps POIs into an existing OpenStreetMap extract without touching OSM geometry
## or user corrections. Deduplicates by normalized name. Returns a new extract dictionary.
static func merge_into_extract(extract: Dictionary, google_places: Array) -> Dictionary:
	var out := extract.duplicate(true)
	var features: Array = out.get("features", []) if out.get("features") is Array else []
	var existing_names := {}
	for f in features:
		if f is Dictionary and str(f.get("name", "")) != "":
			existing_names[str(f.name).strip_edges().to_lower()] = true
	var added := 0
	for p in google_places:
		if not p is Dictionary:
			continue
		var name := str(p.get("name", "")).strip_edges().left(60)
		if name == "" or existing_names.has(name.to_lower()):
			continue
		if not p.get("pts") is Array or (p.pts as Array).is_empty():
			continue
		existing_names[name.to_lower()] = true
		var feat := {
			"kind": "poi",
			"sub": _clean_kind(str(p.get("sub", "landmark"))),
			"name": name,
			"pts": p.pts,
			"closed": false,
			"source": "google_maps",
		}
		if p.get("ll") is Array:
			feat["ll"] = p.ll
		if str(p.get("maps_uri", "")) != "":
			feat["maps_uri"] = str(p.maps_uri)
		features.append(feat)
		added += 1
	out["features"] = features
	if added > 0:
		var credit := str(out.get("credit", Osm.CREDIT))
		if not credit.contains(CREDIT):
			out["credit"] = credit + " • " + CREDIT
	return out


# --- Live opt-in requests --------------------------------------------------------------------------

## Enriches nearby public places around (lat, lon) using the chosen Google Maps mode.
## Emits `finished({"ok", "places", "atmosphere", "grounded", "mode", "error"})`.
func fetch_nearby(lat: float, lon: float, radius: int = 300) -> Dictionary:
	_generation += 1
	var ticket := _generation
	_cancel_http()
	if not is_enabled():
		return _emit_done({"ok": false, "error": "Google Maps integration is off (Settings > Light World > Helper setup)."}, ticket)
	var selected_mode := mode()
	if selected_mode == "links_only":
		return _emit_done({"ok": false, "error": "Google Maps is set to links only. Switch to Gemini Maps Grounding or Places API in Helper setup."}, ticket)
	var key := active_key()
	if key == "":
		return _emit_done({"ok": false, "error": "Add your Gemini key (Settings > AI) or a Google Maps API key (Helper setup) first."}, ticket)

	var res: Dictionary
	if selected_mode == "places_api":
		res = await _fetch_places_api(key, lat, lon, radius, ticket)
	else:
		res = await _fetch_gemini_grounding(key, lat, lon, radius, ticket)
	if ticket != _generation:
		return {"ok": false, "error": "Cancelled."}
	if bool(res.get("ok", false)):
		res["center"] = {"lat": lat, "lon": lon}
		res["radius"] = radius
		res["fetched"] = Time.get_datetime_string_from_system(false, false)
		res["mode"] = selected_mode
		save_cached(res)
	return _emit_done(res, ticket)


func _fetch_gemini_grounding(key: String, lat: float, lon: float, radius: int, ticket: int) -> Dictionary:
	progress.emit("Asking Gemini + Google Maps about public places nearby...")
	var model := str(_lw().get("gemini_model", "")).strip_edges()
	if model == "":
		model = Research.GEMINI_MODEL
	var url := GEMINI_ENDPOINT_FMT % model
	var headers := PackedStringArray(["Content-Type: application/json", "x-goog-api-key: " + key])
	var prompt := manual_grounding_prompt(lat, lon, radius)

	# Try with google_maps grounding first; fall back to google_search if the key tier refuses google_maps.
	for include_maps in [true, false]:
		var body := JSON.stringify(build_grounding_body(prompt, lat, lon, include_maps))
		var resp := await _request(url, headers, HTTPClient.METHOD_POST, body, ticket)
		if ticket != _generation:
			return {"ok": false, "error": "Cancelled."}
		if int(resp[0]) != HTTPRequest.RESULT_SUCCESS:
			return {"ok": false, "error": "Couldn't reach Google Maps via Gemini. Your saved streets still work offline."}
		var code := int(resp[1])
		var text := (resp[3] as PackedByteArray).get_string_from_utf8()
		var reply: Variant = JSON.parse_string(text)
		if code == 400 and include_maps and text.to_lower().contains("google_maps"):
			progress.emit("Falling back to Gemini Search grounding for this key...")
			continue
		if code == 401 or code == 403:
			return {"ok": false, "error": "Google didn't accept the key (check Settings > AI or Helper setup)."}
		if code == 429:
			return {"ok": false, "error": "Google's rate limit was reached for now. Try again shortly."}
		if code != 200 or not reply is Dictionary:
			return {"ok": false, "error": "Gemini Maps returned HTTP %d." % code}
		var parsed := parse_gemini_places(reply, lat, lon, radius)
		parsed["ok"] = true
		parsed["error"] = ""
		return parsed
	return {"ok": false, "error": "Google Maps grounding wasn't available on this key."}


func _fetch_places_api(key: String, lat: float, lon: float, radius: int, ticket: int) -> Dictionary:
	progress.emit("Asking Google Maps Places about public spots nearby...")
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Goog-Api-Key: " + key,
		"X-Goog-FieldMask: places.displayName,places.location,places.types,places.googleMapsUri",
	])
	var payload := {
		"includedTypes": Array(PUBLIC_PLACE_TYPES),
		"maxResultCount": 15,
		"locationRestriction": {
			"circle": {
				"center": {"latitude": lat, "longitude": lon},
				"radius": float(clampi(radius, 50, 1500)),
			}
		}
	}
	var resp := await _request(PLACES_NEARBY_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload), ticket)
	if ticket != _generation:
		return {"ok": false, "error": "Cancelled."}
	if int(resp[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Couldn't reach Google Maps Places API. Your saved streets still work offline."}
	var code := int(resp[1])
	var body_text := (resp[3] as PackedByteArray).get_string_from_utf8()
	if code == 401 or code == 403:
		return {"ok": false, "error": "Google Maps rejected that key (ensure Places API (New) is enabled on your key)."}
	if code == 429:
		return {"ok": false, "error": "Google Maps quota limit reached for now."}
	if code != 200:
		return {"ok": false, "error": "Google Maps Places returned HTTP %d." % code}
	var parsed := parse_places_api(JSON.parse_string(body_text), lat, lon, radius)
	parsed["ok"] = true
	parsed["error"] = ""
	return parsed


func _request(url: String, headers: PackedStringArray, method: int, body: String, ticket: int) -> Array:
	calls += 1
	if transport.is_valid():
		return await transport.call(url, headers, method, body)
	if not is_inside_tree():
		return [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]
	var http := HTTPRequest.new()
	_http = http
	http.timeout = 30.0
	http.body_size_limit = 4 * 1024 * 1024
	add_child(http)
	var box := {"done": false, "response": []}
	http.request_completed.connect(func(a, b, c, d):
		box.response = [a, b, c, d]
		box.done = true, CONNECT_ONE_SHOT)
	if http.request(url, headers, method, body) != OK:
		box.response = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
		box.done = true
	var deadline := Time.get_ticks_msec() + 35000
	while not bool(box.done) and ticket == _generation and is_inside_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if _http == http:
		_http = null
	if is_instance_valid(http):
		if not bool(box.done):
			http.cancel_request()
		http.queue_free()
	if not bool(box.done):
		return [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
	return box.response


func _emit_done(result: Dictionary, ticket: int) -> Dictionary:
	if ticket == _generation:
		finished.emit(result)
	return result


func cancel() -> void:
	_generation += 1
	_cancel_http()


func _cancel_http() -> void:
	if is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
	_http = null


func _exit_tree() -> void:
	cancel()
