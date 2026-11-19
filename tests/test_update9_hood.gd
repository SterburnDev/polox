extends "res://tests/test_case.gd"
## Update 9, a neighbourhood that looks like streets (a made-up town only; nothing real is fetched):
## courtyards (multipolygon holes) stay open; sidewalks, lamps, crossings, fences and hedges, gardens,
## driveways, shopfronts and pitched roofs; what came from the map vs what Polox filled in; your fixes;
## nobody walled in; your own pieces kept when the streets are rebuilt; the last good map reused until
## Refresh; a web page or a 429 never mistaken for a map; diagnostics without the address; a bounded mesh.

const Osm := preload("res://scripts/home/osm.gd")
const V := preload("res://scripts/home/map_validation.gd")
const HoodBuilder := preload("res://scripts/home/hood_builder.gd")
const HoodRender := preload("res://scripts/world/hood_render.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const DETAIL := "res://tests/fixtures/osm_madeup_town_detail.json"


func _extract(corrections: Dictionary = {}) -> Dictionary:
	var e := Osm.clean(JSON.parse_string(FileAccess.get_file_as_string(DETAIL)), 10.0, 10.0, 150)
	if not corrections.is_empty():
		e["corrections"] = corrections
	return e


func _blocks(places: Dictionary) -> Array:
	return places.keys().filter(func(k): return str(k).begins_with("lw_hood_")).map(func(k): return places[k])


func _count(places: Dictionary, pred: Callable) -> int:
	var n := 0
	for p in _blocks(places):
		n += int(pred.call(p))
	return n


func _ground_cells(places: Dictionary, kind: String) -> int:
	return _count(places, func(p): return (p.floor_areas as Array).filter(func(a): return str(a.kind) == kind).reduce(func(s, a): return s + int(a.rect[2]) * int(a.rect[3]), 0))


func test_courtyards_stay_open_and_the_detail_survives_cleaning() -> void:
	var e := _extract()
	check(V.extract_valid(e), "the cleaned map is valid")
	var market: Array = e.features.filter(func(f): return str(f.get("name", "")) == "Courtyard Market")
	if check(market.size() == 1, "the multipolygon shop is kept"):
		check((market[0].get("holes", []) as Array).size() == 1, "with its courtyard as a hole")
	for kind in ["lamp", "crossing", "barrier", "paved", "bus_stop"]:
		check(e.features.any(func(f): return str(f.kind) == kind), "%s kept" % kind)
	var lane: Array = e.features.filter(func(f): return str(f.get("name", "")) == "Example Lane")
	check(not lane.is_empty() and str(lane[0].get("sidewalk", "")) == "both", "what the map says about sidewalks")
	check(not JSON.stringify(e).contains("Somebody Private") and not JSON.stringify(e).contains("housenumber"), "still no owners or numbers")
	# The courtyard's middle is ground, not building.
	var places := HoodBuilder.build(e)
	var c := Osm.project(9.99935, 10.00075, 10.0, 10.0)
	var size := _blocks(places).size()
	var n := int(sqrt(float(size)))
	var off := n * HoodBuilder.CHUNK * HoodBuilder.CELL_M / 2.0
	var cell := Vector2i(int((c.x + off) / HoodBuilder.CELL_M), int((c.y + off) / HoodBuilder.CELL_M))
	var block: Dictionary = places[HoodBuilder.chunk_id(cell.x / HoodBuilder.CHUNK, cell.y / HoodBuilder.CHUNK)]
	var local := [cell.x % HoodBuilder.CHUNK, cell.y % HoodBuilder.CHUNK]
	check(not (block.buildings as Array).any(func(b): return (b.cells as Array).any(func(q): return int(q[0]) == local[0] and int(q[1]) == local[1])), "the courtyard is open")


func test_streets_get_sidewalks_lamps_crossings_fences_and_gardens() -> void:
	var places := HoodBuilder.build(_extract())
	check(_ground_cells(places, "sidewalk") > 40, "sidewalks (%d cells)" % _ground_cells(places, "sidewalk"))
	check(_ground_cells(places, "garden") > 10, "gardens round the houses")
	check(_ground_cells(places, "paved") > 5, "the parking lot and driveways")
	var lamps := 0
	var guessed_lamps := 0
	for p in _blocks(places):
		for o in p.objects:
			if str(o.get("model", "")) == "streetlamp":
				lamps += 1
				guessed_lamps += int(bool(o.get("inferred", false)))
	check(lamps >= 1, "the map's street lamps")
	eq(guessed_lamps, 0, "none made up when the map has lamps")
	check(_count(places, func(p): return (p.decals as Array).size()) >= 1, "a zebra crossing")
	var kinds := {}
	for p in _blocks(places):
		for b in p.barriers:
			kinds[str(b.kind)] = true
	check(kinds.has("fence") and kinds.has("hedge"), "fences and hedges (%s)" % str(kinds.keys()))
	var home: Dictionary = places[places.home_chunk]
	check((home.buildings as Array).any(func(b): return str(b.kind) == "mine" and HoodRender.pitched(b)), "your house has its pitched roof")
	check(_count(places, func(p): return (p.buildings as Array).filter(func(b): return bool(b.get("storefront", false))).size()) >= 1, "a shopfront")
	var prov: Dictionary = home.provenance
	check("road" in prov.map and "lamp" in prov.map, "from the map: %s" % str(prov.map))
	check("garden" in prov.filled and "yard" in prov.filled, "filled in: %s" % str(prov.filled))


func test_your_fixes_win() -> void:
	var fence := HoodBuilder.build(_extract({"yard": "fence"}))
	var yard_kinds := {}
	for p in _blocks(fence):
		for b in p.barriers:
			if (b.pts as Array).size() == 5:   # (the yard's closed outline)
				yard_kinds[str(b.kind)] = true
	check(yard_kinds.has("fence"), "a fence round your yard, as you said")
	var open := HoodBuilder.build(_extract({"yard": "open", "sidewalks": "none", "lights": "none"}))
	check(not "yard" in open[open.home_chunk].provenance.filled, "an open yard: no hedge")
	var plain := HoodBuilder.build(Osm.clean(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/osm_madeup_town.json")), 10.0, 10.0, 150))
	check(_count(plain, func(p): return (p.objects as Array).filter(func(o): return str(o.get("model", "")) == "streetlamp" and bool(o.get("inferred", false))).size()) > 0, "without the map's lamps, some are filled in")
	var dark := HoodBuilder.build(Osm.clean(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/osm_madeup_town.json")), 10.0, 10.0, 150).merged({"corrections": {"lights": "none", "sidewalks": "none"}}))
	eq(_count(dark, func(p): return (p.objects as Array).filter(func(o): return str(o.get("model", "")) == "streetlamp").size()), 0, "no lamps when you said none")
	eq(_ground_cells(dark, "sidewalk"), 0, "no sidewalks when you said none")


## Nobody is walled in: from your front door to the park, and to the street, with fences and hedges
## standing on their cells.
func test_fences_never_wall_you_in() -> void:
	var places := HoodBuilder.build(_extract({"yard": "fence"}))
	var blocks := _blocks(places)
	var n := int(sqrt(float(blocks.size())))
	var size := n * HoodBuilder.CHUNK
	var blocked := {}
	var park := {}
	var road := {}
	var start := Vector2i(-1, -1)
	for p in blocks:
		var o := Vector2i(int(p.hood.ci) * HoodBuilder.CHUNK, int(p.hood.cj) * HoodBuilder.CHUNK)
		for b in p.buildings:
			for c in b.cells:
				blocked[o + Vector2i(int(c[0]), int(c[1]))] = true
		for b in p.barriers:
			for c in b.cells:
				blocked[o + Vector2i(int(c[0]), int(c[1]))] = true
		for a in p.floor_areas:
			for z in range(int(a.rect[1]), int(a.rect[1]) + int(a.rect[3])):
				for x in range(int(a.rect[0]), int(a.rect[0]) + int(a.rect[2])):
					var c := o + Vector2i(x, z)
					match str(a.kind):
						"water": blocked[c] = true
						"park": park[c] = true
						"road": road[c] = true
		if p.has("spawn") and str(p.id) == str(places.home_chunk):
			start = o + Vector2i(int(p.spawn[0]), int(p.spawn[1]))
	check(start.x >= 0 and not blocked.has(start), "you arrive on open ground")
	var seen := {start: true}
	var q: Array = [start]
	var got_park := false
	var got_road := false
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var m: Vector2i = c + dv
			if m.x < 0 or m.y < 0 or m.x >= size or m.y >= size or seen.has(m) or blocked.has(m):
				continue
			seen[m] = true
			got_park = got_park or park.has(m)
			got_road = got_road or road.has(m)
			q.append(m)
	check(got_road, "out through the gap in your fence to the street")
	check(got_park, "and on to the park")


func test_rebuilding_keeps_your_own_pieces_and_snapshots_first() -> void:
	fresh_save_root()
	check(HomeStore.save_home({"plan": {}, "answers": {}}), "a home (snapshots always carry home.json)")
	var e := _extract()
	check(HomeMapper.build_streets(e, {}), "the streets built")
	var places := HoodBuilder.build(e)
	var id := str(places.home_chunk)
	var p := SaveManager.load_room(id)
	var spot := Vector2i(-1, -1)
	for z in range(5, 55):
		for x in range(5, 55):
			if spot.x < 0 and RoomEditor.object_at(p, x, z).is_empty() and not (p.buildings as Array).any(func(b): return (b.cells as Array).any(func(c): return int(c[0]) == x and int(c[1]) == z)) and not HoodBuilder._barrier_at(p, Vector2i(x, z)):
				spot = Vector2i(x, z)
	var mine := RoomEditor.add_object(p, spot.x, spot.y, "birdbath")
	mine["user"] = true
	SaveManager.save_room(p)
	check(HomeMapper.build_streets(_extract({"yard": "fence"}), {}), "rebuilt with a fix")
	var again := SaveManager.load_room(id)
	check((again.objects as Array).any(func(o): return bool(o.get("user", false))), "your birdbath is still there")
	check(HomeStore.snapshots().any(func(s): return str(s.kind) == "before_streets"), "a snapshot before the rebuild")


func test_the_last_good_map_is_reused_until_refresh() -> void:
	fresh_save_root()
	var good := _extract()
	JsonUtil.write_json(HomeStore.path("osm.json"), good)
	var osm := Osm.new()
	tree.root.add_child(osm)
	var asked := {"n": 0}
	var answer := {"done": false, "result": {}}
	osm.finished.connect(func(r): answer.done = true; answer.result = r)
	osm.transport = func(_u, _h, _m, _b):
		asked.n += 1
		return [HTTPRequest.RESULT_SUCCESS, 200, [], "<html><body>Too busy</body></html>".to_utf8_buffer()]
	Osm._next_request_at = 0
	osm.fetch(10.0, 10.0, 150)
	while not answer.done:
		await frames()
	check(bool(answer.result.ok) and bool(answer.result.get("cached", false)), "the kept map, without asking")
	eq(asked.n, 0, "nothing sent")
	answer.done = false
	osm.fetch(10.0, 10.0, 150, true)
	while not answer.done:
		await frames()
	eq(asked.n, 1, "Refresh asks")
	check(not bool(answer.result.ok) and str(answer.result.get("code", "")) == "html", "a web page is never a map")
	check(V.extract_valid(JsonUtil.read_json(HomeStore.path("osm.json"), {})), "the kept map is untouched")
	var d := Osm.diagnostic(answer.result)
	check(d.contains("html") and not d.contains("Too busy") and not d.contains("Example"), "the diagnostic names the stage, never the body: " + d)
	osm.queue_free()
	await frames(2)


func test_a_rate_limit_waits_and_says_so() -> void:
	var r := Osm.http_result([HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(["Retry-After: 30"]), PackedByteArray()])
	check(not bool(r.ok) and str(r.code) == "rate_limit" and int(r.wait_s) == 30, "429 with its Retry-After")
	check(Osm.wait_seconds() >= 28, "the next request waits")
	check(Osm.diagnostic(r).contains("Wait"), "and the panel says to wait")
	Osm._next_request_at = 0
	var off := Osm.http_result([HTTPRequest.RESULT_CANT_RESOLVE, 0, PackedStringArray(), PackedByteArray()])
	eq(str(off.state), "offline")
	check(Osm.diagnostic(off).contains("internet"), "offline says check the connection")


func test_a_block_is_one_bounded_mesh() -> void:
	var places := HoodBuilder.build(_extract())
	var worst := 0
	for p in _blocks(places):
		var mi := HoodRender.build(p)
		if mi:
			worst = maxi(worst, HoodRender.last_vertices)
			mi.free()
	check(worst > 0, "detail is drawn")
	check(worst < 60000, "a block's detail stays under 60k vertices (%d)" % worst)
	print("    (worst block detail: %d vertices)" % worst)
