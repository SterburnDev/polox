extends SceneTree
## Everything the builders make for fixed inputs (streets from the made-up towns, houses from a set of
## answers and research, every kind of edit, the network doctor's reading), written to one JSON file with a
## SHA-256 per part. Run it before and after tidying a builder: the same file means nothing changed.
##   godot --headless --path . --script res://tools/builder_snapshot.gd -- --save-root=<scratch> --out=<file>
##   [--real-osm=<an osm.json of a public landmark>]
## Dev only: reads fixtures, writes only --out. Always give a disposable --save-root.

var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _arg(k: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.trim_prefix("--" + k + "=")
	return ""


func _run() -> void:
	await process_frame
	var Osm: Script = load("res://scripts/home/osm.gd")
	var HoodBuilder: Script = load("res://scripts/home/hood_builder.gd")
	var LayoutBuilder: Script = load("res://scripts/home/layout_builder.gd")
	var HomeEdit: Script = load("res://scripts/home/home_edit.gd")
	var HomeModel: Script = load("res://scripts/home/home_model.gd")
	var NetFacts: Script = load("res://scripts/net/net_facts.gd")
	var out := {}
	# --- streets
	var look := {"wall": "#8a9060", "roof": "#a8684a", "door": "#c8645c", "roof_shape": "hipped"}
	var notes := [{"name": "Maple Park", "note": "A small park with a pond."}]
	for town in ["osm_madeup_town.json", "osm_madeup_town_detail.json"]:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + town))
		for radius in [150, 250]:
			var extract: Dictionary = Osm.clean(raw, 10.0, 10.0, radius)
			out["hood/%s/%d/plain" % [town, radius]] = HoodBuilder.build(extract.duplicate(true))
			out["hood/%s/%d/cared" % [town, radius]] = HoodBuilder.build(extract.duplicate(true), "Maple Park, the corner shop", notes, look)
			for corr in [{"yard": "fence", "driveway": "no"}, {"yard": "open", "sidewalks": "none", "lights": "none"}]:
				var e2: Dictionary = extract.duplicate(true)
				e2["corrections"] = corr
				out["hood/%s/%d/%s" % [town, radius, JSON.stringify(corr)]] = HoodBuilder.build(e2)
	if _arg("real-osm") != "":
		var real: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_arg("real-osm")))
		var ex: Dictionary = real.extract if real.has("extract") else real
		out["hood/real"] = HoodBuilder.build(ex.duplicate(true), "", [], look)
	# --- houses
	var found_rooms := [
		{"kind": "hall", "floor": 0, "area": 0.0, "wall": "#b5cfa8", "name": "Entrance hall"},
		{"kind": "living", "floor": 0, "area": 0.0}, {"kind": "office", "floor": 0, "area": 0.0, "name": "Study"},
		{"kind": "storage", "floor": 0, "area": 0.0, "floor_material": "wood", "name": "Pantry"},
		{"kind": "dining", "floor": 0, "area": 0.0, "wall": "#d8b860", "floor_material": "tile"},
		{"kind": "kitchen", "floor": 0, "area": 0.0}, {"kind": "bedroom", "floor": 0, "area": 0.0},
		{"kind": "office", "floor": 0, "area": 70.56, "name": "Drafting room"}, {"kind": "garage", "floor": 0, "area": 0.0},
		{"kind": "bedroom", "floor": 1, "area": 0.0}, {"kind": "bedroom", "floor": 1, "area": 12.0}, {"kind": "bathroom", "floor": 1, "area": 0.0},
		{"kind": "family", "floor": 1, "area": 0.0, "wall": "#a8584a", "name": "Playroom"}, {"kind": "storage", "floor": -1, "area": 0.0}]
	var houses := [
		[{"home_type": "apartment", "rooms": {"bedroom": 1, "bathroom": 1, "kitchen": 1, "living": 1}}, {}],
		[{"home_type": "house", "floors": 2, "rooms": {"bedroom": 3, "bathroom": 2, "kitchen": 1, "living": 1, "dining": 1, "office": 1, "garage": 1}, "my_room": {"floor": 1, "where": "left", "wall": "#aabbcc", "floor_kind": "wood"}, "floor_kinds": {"kitchen": "vinyl"}}, {}],
		[{"home_type": "house", "floors": 1, "basement": true, "entry_room": "living", "rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1, "laundry": 1, "family": 1}, "my_room": {"floor": -1, "where": "back"}}, {}],
		[{"home_type": "house", "floors": 3, "rooms": {"bedroom": 5, "bathroom": 3, "kitchen": 1, "living": 2, "dining": 1, "office": 2}}, {"sqft": 3400.0}],
		[{"home_type": "house", "floors": 2, "rooms": {"bedroom": 2, "kitchen": 1, "living": 1}, "my_room": {"floor": 1, "where": "front"}}, {"sqft": 2163.0, "floors": 2, "bedrooms": 3, "bathrooms": 1, "basement": true, "rooms": found_rooms}],
		[{}, {"footprint_w": 14.0, "footprint_d": 9.0, "floors": 2, "bedrooms": 4, "bathrooms": 2, "rooms": found_rooms}],
		[{"home_type": "house"}, {}],
	]
	var plans: Array = []
	for h in houses:
		var plan: Dictionary = LayoutBuilder.build((h[0] as Dictionary).duplicate(true), (h[1] as Dictionary).duplicate(true))
		plans.append(plan)
		out["house/%d" % plans.size()] = plan.duplicate(true)
	# --- edits, one after another on house 2 and house 5, each result kept
	for which in [1, 4]:
		var plan2: Dictionary = (plans[which] as Dictionary).duplicate(true)
		var answers: Dictionary = houses[which][0]
		var log: Array = []
		for level in [0, 1]:
			var f: Dictionary = HomeEdit.floor_of(plan2, level)
			var rooms: Array = f.rooms
			var first := str(rooms[1 % rooms.size()].id)
			var second := str(rooms[2 % rooms.size()].id)
			var inner := {}
			var outer := {}
			for e in f.edges:
				if bool(e.get("outer", false)) and outer.is_empty() and not bool(e.get("door", false)):
					outer = e
				if not bool(e.get("outer", false)) and inner.is_empty() and not bool(e.get("door", false)):
					inner = e
			var piece: Dictionary = f.furniture[0] if not (f.furniture as Array).is_empty() else {}
			var edits := [
				{"type": "rename", "level": level, "room": first, "name": "  The den  "},
				{"type": "rename", "level": level, "room": first, "name": "  "},
				{"type": "rename", "level": level, "room": "nope", "room_name": "The den", "name": "Den"},
				{"type": "wall", "level": level, "room": first, "color": "#123456"},
				{"type": "wall", "level": level, "room": "nope"},
				{"type": "floor", "level": level, "room": second, "floor": "stone"},
				{"type": "edge", "level": level, "x": int(inner.get("x", -1)), "z": int(inner.get("z", -1)), "dir": str(inner.get("dir", "")), "to": "window"},
				{"type": "edge", "level": level, "x": int(inner.get("x", -1)), "z": int(inner.get("z", -1)), "dir": str(inner.get("dir", "")), "to": "door"},
				{"type": "edge", "level": level, "x": int(outer.get("x", -1)), "z": int(outer.get("z", -1)), "dir": str(outer.get("dir", "")), "to": "door"},
				{"type": "edge", "level": level, "x": int(outer.get("x", -1)), "z": int(outer.get("z", -1)), "dir": str(outer.get("dir", "")), "to": "window"},
				{"type": "edge", "level": level, "x": 99, "z": 99, "dir": "h", "to": "door"},
				{"type": "add", "level": level, "room": first, "model": "plant", "color": "#00ff00"},
				{"type": "add", "level": level, "room": first, "model": "lamp", "count": 3},
				{"type": "add", "level": level, "room": second, "model": "no_such_model"},
				{"type": "add", "level": level, "room": "hall_%d" % level, "model": "runner", "color": "#3355aa"},
				{"type": "place", "level": level, "model": "plant", "x": 1, "z": 1, "rot": 5, "color": "#ff0000"},
				{"type": "place", "level": level, "model": "plant", "x": -3, "z": 1},
				{"type": "swap", "level": level, "room": first, "other": second},
				{"type": "swap", "level": level, "room": first, "other": first},
				{"type": "move", "level": level, "model": str(piece.get("model", "")), "from_x": int(piece.get("x", -1)), "from_z": int(piece.get("z", -1)), "x": int(piece.get("x", 0)) + 1, "z": int(piece.get("z", 0)), "rot": 1, "color": "#abcdef"},
				{"type": "move", "level": level, "model": "sofa", "from_x": 77, "from_z": 77, "x": 1, "z": 1},
				{"type": "remove", "level": level, "room": first, "model": "lamp"},
				{"type": "remove", "level": level, "room": first, "model": "no_such_model"},
				{"type": "remove_at", "level": level, "model": "plant", "x": 1, "z": 1},
				{"type": "remove_at", "level": level, "model": "plant", "x": 55, "z": 55},
				{"type": "used_to_be", "level": level, "room": second, "was": "a nursery"},
				{"type": "note", "level": level, "room": second, "text": "The window sticks."},
				{"type": "note", "level": level, "text": "The back door sticks."},
				{"type": "note", "level": level, "room": "nope", "text": "x"},
				{"type": "something_else", "level": level},
				{"type": "rename", "level": 7, "room": first, "name": "Nowhere"},
			]
			for e in edits:
				log.append([e, HomeEdit.apply(plan2, e, answers), HomeEdit.describe(e)])
		out["edits/%d" % which] = {"log": log, "plan": plan2}
	# --- the network doctor's reading of some facts
	var cases := [[{}, {}], [{"ports": []}, {"ports": [8765], "programs": [], "server": "ping"}]]
	for i in cases.size():
		out["net/%d" % i] = NetFacts.analyze((cases[i][0] as Dictionary).duplicate(true), (cases[i][1] as Dictionary).duplicate(true))
	var text := JSON.stringify(out, "\t", true)
	var f2 := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f2.store_string(text)
	f2.close()
	for k in out:
		print("%s  %s" % [JSON.stringify(out[k], "", true).sha256_text().left(12), k])
	print("ALL  ", text.sha256_text())
	quit()
