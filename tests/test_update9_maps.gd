extends "res://tests/test_case.gd"
const V := preload("res://scripts/home/map_validation.gd")
const Osm := preload("res://scripts/home/osm.gd")
const Model := preload("res://scripts/home/home_model.gd")
const Mapper := preload("res://scripts/home/home_mapper.gd")
const Store := preload("res://scripts/home/home_store.gd")


func test_coordinate_zero_negative_bounds_and_helper_location() -> void:
	for point in [{"lat": 0.0, "lon": 0.0}, {"lat": 0.0, "lon": -78.1}, {"lat": -33.8, "lon": 151.2}, {"lat": 90.0, "lon": -180.0}]:
		check(V.coordinates(point))
		check(Model.clean_research({"location": point}).has("location"), "helper coordinates retained")
	for bad in [{"lat": 91.0, "lon": 0.0}, {"lat": 0.0, "lon": 181.0}, {"lat": NAN, "lon": 1.0}, {"lat": 0.0}, {"lat": "bad", "lon": 0.0}]:
		check(not V.coordinates(bad))
		check(not Model.clean_research({"location": bad}).has("location"))
	eq(Osm.parse_coords("0, -78.1"), {"lat": 0.0, "lon": -78.1})


func test_invalid_partial_sparse_and_wrong_location_are_distinct() -> void:
	for raw in [null, {}, {"elements": {}}, {"elements": [1]}, {"elements": [], "remark": "runtime limit"}, {"elements": [{"type": "way", "id": 1, "geometry": [{}]}]}]:
		check(not V.overpass(raw, 0, 0, 80).ok, "invalid map refused")
	var sparse := V.overpass({"elements": []}, 0, 0, 80)
	check(sparse.ok)
	eq(sparse.state, "sparse")
	var wrong := V.overpass({"elements": [{"type": "node", "id": 1, "lat": 20.0, "lon": 20.0}]}, 0, 0, 80)
	check(not wrong.ok, "wrong-location data rejected")
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/osm_madeup_town.json"))
	check(V.overpass(fixture, 10, 10, 250).ok, "representative recorded map accepted")
	check(V.extract_valid(Osm.clean(fixture, 10, 10, 250)))


func test_location_candidates_and_http_failures() -> void:
	var ambiguous := V.geocoding([{"lat": "0", "lon": "-1", "display_name": "Public landmark A"}, {"lat": "1", "lon": "0", "display_name": "Public landmark B"}])
	eq(ambiguous.state, "ambiguous")
	eq(ambiguous.candidates.size(), 2)
	check(not V.geocoding([{"lat": "nonsense", "lon": "1"}]).ok)
	var old := Osm._next_request_at
	var limited := Osm.http_result([HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(["Retry-After: 120"]), "private provider body".to_utf8_buffer()])
	eq(limited.code, "rate_limit")
	check(not limited.retry, "no automatic retry on throttling")
	check(not JSON.stringify(limited).contains("private provider body"), "diagnostic never echoes provider body")
	Osm._next_request_at = old
	eq(Osm.http_result([HTTPRequest.RESULT_TIMEOUT, 0, [], PackedByteArray()]).code, "timeout")
	eq(Osm.http_result([HTTPRequest.RESULT_SUCCESS, 403, [], PackedByteArray()]).status, 403)


func test_extract_metadata_cannot_crash_or_expand_generation() -> void:
	var extract := {"center": {"lat": 0, "lon": 0}, "radius": 80, "features": [{"kind": "road", "pts": [[0, 0], [2, 2]], "width": 6.0}]}
	check(V.extract_valid(extract), "bounded road accepted")
	for width in ["wide", {}, NAN, INF, -1, 1000000]:
		var bad := extract.duplicate(true)
		bad.features[0].width = width
		check(not V.extract_valid(bad), "invalid width rejected before generation")
	for level in ["many", {}, 1.5, 0, 1000000]:
		var bad := extract.duplicate(true)
		bad.features[0]["levels"] = level
		check(not V.extract_valid(bad), "invalid levels rejected")
	check(not V.overpass({"elements": [{"type": "node", "id": 1.5, "lat": 0, "lon": 0}]}, 0, 0, 80).ok, "fractional feature identifier rejected")


func test_invalid_http_200_and_late_reply_do_not_replace_map() -> void:
	fresh_save_root()
	var good := {"center": {"lat": 0.0, "lon": 0.0}, "radius": 80, "features": []}
	preload("res://scripts/core/json_util.gd").write_json(Store.path("osm.json"), good)
	var bytes := FileAccess.get_file_as_bytes(Store.path("osm.json"))
	var osm := Osm.new()
	tree.root.add_child(osm)
	var answer := {"done": false, "result": {}}
	osm.finished.connect(func(r): answer.done = true; answer.result = r)
	osm.transport = func(_url, _headers, _method, _body): return [HTTPRequest.RESULT_SUCCESS, 200, [], "{}".to_utf8_buffer()]
	Osm._next_request_at = 0
	osm.fetch(0, 0, 80, true)   # (Refresh: the kept map for this spot would be reused otherwise)
	while not answer.done:
		await frames()
	check(not answer.result.ok, "HTTP 200 is insufficient without valid schema")
	check(not Mapper.build_streets({}, {}))
	eq(FileAccess.get_file_as_bytes(Store.path("osm.json")), bytes)
	answer.done = false
	osm.transport = func(_url, _headers, _method, _body):
		await tree.create_timer(0.1).timeout
		return [HTTPRequest.RESULT_SUCCESS, 200, [], "{\"elements\":[]}".to_utf8_buffer()]
	Osm._next_request_at = 0
	osm.fetch(0, 0, 80, true)   # (Refresh: the kept map for this spot would be reused otherwise)
	await frames(2)
	osm.cancel()
	await tree.create_timer(0.15).timeout
	eq(answer.result.state, "cancelled", "late success cannot replace cancellation")
	eq(FileAccess.get_file_as_bytes(Store.path("osm.json")), bytes)
	osm.queue_free()
	await frames(2)
