extends RefCounted
## Turns the OpenStreetMap extract (osm.gd) into the Light World's streets: square places ("blocks" of
## 60 x 60 cells, a cell here is 2.5 m so a street feels walkable) joined at their edges, with the roads
## and paths, parks, water, woods, sand and parking as ground, buildings as plain, nicely made houses
## (yours warm, with your front door; everyone else's a shape with a roof, windows and a door, nothing
## more; shops with a storefront), trees, benches, street lamps, fences and hedges, crossings, bus stops
## and a sign with a name for the public places (a park, the school, the corner shop). The block with
## your home has the door into your ground floor; your ground floor's front gate leads back out.
##
## What the map says is used as it is ("map"). What it doesn't say but streets have is filled in, and
## each place says which is which ("provenance": "map" and "filled" kinds; filled-in objects carry
## "inferred"): sidewalks and curbs along streets that the map doesn't give separately, lamps every 30 m
## where the map has none, gardens round houses, driveways, your front path and your yard's hedge. Your
## own fixes ("corrections" in osm.json: yard fence/hedge/open, driveway, sidewalks, lights) win, and
## they're kept when the map is fetched again.
## Tags: [LIGHT_WORLD_MAP]

const Realms := preload("res://scripts/world/realms.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const Places := preload("res://scripts/world/places.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const HomeLook := preload("res://scripts/home/home_look.gd")

const CELL_M := 2.5
const CHUNK := 60
const COLORS := {"road": "#8a8a90", "path": "#d8cdb4", "park": "#86b672", "water": "#7fb4d8", "woods": "#5f9054", "grass": "#9cc283", "home_lot": "#a6cc8a",
	"sand": "#e3d3a0", "paved": "#b7b3ab", "garden": "#93c47c", "sidewalk": "#cdc6b8"}
const HOUSE_WALLS := ["#e9e1d0", "#e3d6c3", "#d9d2c8", "#ece6da", "#d6dccf", "#e7d8cf", "#d2d9e0"]
const HOUSE_ROOFS := ["#8a5a4a", "#6a6a74", "#7a5a46", "#5a6470", "#9a6a52", "#5f5a64"]
## Ground kinds by priority (a higher one is drawn over a lower one where they meet).
const PRIORITY := {"grass": 0, "park": 1, "wood": 2, "sand": 3, "paved": 4, "garden": 5, "sidewalk": 6, "path": 7, "road": 8, "building": 9, "water": 10}
const GROUND := {1: "park", 2: "woods", 3: "sand", 4: "paved", 5: "garden", 6: "sidewalk", 7: "path", 8: "road", 10: "water"}
## Streets that get sidewalks when the map doesn't draw them (not lanes, tracks or motorways).
const SIDEWALK_ROADS: PackedStringArray = ["primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "primary_link", "secondary_link", "tertiary_link"]
const LAMP_EVERY := 12          # cells (30 m) between filled-in street lamps
const NAMED_COLOURS := {"white": "#eeeae2", "red": "#a8574a", "brown": "#7a5a46", "grey": "#8e8e92", "gray": "#8e8e92", "black": "#4a4a50",
	"beige": "#e2d4b8", "yellow": "#e8d48a", "green": "#7f9f78", "blue": "#7f95b8", "orange": "#d8945a", "darkgrey": "#6a6a70", "lightgrey": "#c4c4c8"}


static func chunk_id(ci: int, cj: int) -> String:
	return "lw_hood_%d_%d" % [ci, cj]


## What `build` works out on the way from the map to the places: the whole neighbourhood as one grid of
## cells, and the things the map (or the filling-in) put on it. One is made per build and handed from
## phase to phase.
class Plot:
	var size := 0                       # cells along one side of the whole grid
	var chunks := 1                     # blocks along one side
	var off := 0.0                      # metres from the grid's corner to your home
	var cls := PackedByteArray()        # ground kind per cell (a PRIORITY)
	var owner := PackedInt32Array()     # building index per cell (-1 none)
	var corr := {}                      # your own fixes (osm.json "corrections")
	var feats: Array = []               # the map's features
	var buildings: Array = []
	var pois: Array = []
	var trees: Array = []
	var benches: Array = []
	var lamps: Array = []               # [cell, inferred]
	var crossings: Array = []           # cells
	var barriers: Array = []            # {kind, pts (cells), inferred}
	var stops: Array = []               # {cell, name}
	var map_kinds := {}                 # kinds of thing the map gave
	var filled := {}                    # kinds of thing Polox filled in
	var mid := Vector2i.ZERO            # the middle cell: your home
	var home_bi := -1                   # your home's index in `buildings`
	var door := Vector2i.ZERO           # your front door's cell
	var away := Vector2i(0, 1)          # the way out of it


## {place id: place} for the whole neighbourhood, plus "home_chunk". `places_cared` are names you gave the
## Survey (matched against public places for a little more care); `notes` are the helper's public notes;
## `look` is how your own house looks from the street when a helper found out (home_look.gd: wall, roof
## and door colours, the roof's shape), else it keeps Polox's warm default.
static func build(extract: Dictionary, places_cared: String = "", notes: Array = [], look: Dictionary = {}) -> Dictionary:
	var plot := _new_plot(extract)
	_read_map(plot)
	var walks_filled := _lay_streets(plot)
	_claim_home(plot)
	_fill_gardens_and_driveways(plot)
	_lay_front_path(plot)
	_edge_yard(plot)
	_fill_lamps(plot)
	if walks_filled:
		plot.filled["sidewalks"] = true
	var road_names := _street_names(plot)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(extract.get("center", {})))
	var out := _make_places(plot, road_names, rng)
	_place_street_things(out, plot, places_cared, notes)
	_scatter_greenery(out, rng)
	out["home_chunk"] = _open_front_door(out, plot)
	if not look.is_empty():
		for id in out:
			if out[id] is Dictionary:
				HomeLook.apply_to_street(out[id], look)
	return out


## An empty grid big enough for the extract's radius.
static func _new_plot(extract: Dictionary) -> Plot:
	var plot := Plot.new()
	var radius := float(extract.get("radius", 250))
	var g := int(ceil(radius * 2.0 / CELL_M))
	plot.chunks = maxi(1, int(ceil(float(g) / CHUNK)))
	if plot.chunks % 2 == 0:
		plot.chunks += 1   # an odd number of blocks puts your home in the middle of one, not on a corner
	plot.size = plot.chunks * CHUNK
	plot.off = plot.size * CELL_M / 2.0
	plot.cls.resize(plot.size * plot.size)
	plot.cls.fill(0)
	plot.owner.resize(plot.size * plot.size)
	plot.owner.fill(-1)
	plot.corr = extract.get("corrections", {}) if extract.get("corrections") is Dictionary else {}
	plot.feats = extract.get("features", [])
	plot.mid = Vector2i(plot.size / 2, plot.size / 2)
	return plot


## The map's areas onto the grid (the priority decides what's on top: buildings, water last) and its
## single things (trees, benches, lamps, crossings, bus stops, fences) into their lists.
static func _read_map(plot: Plot) -> void:
	var size := plot.size
	for f in plot.feats:
		var kind := str(f.get("kind", ""))
		var pts := _cells(f.get("pts", []), plot.off)
		var holes: Array = (f.get("holes", []) as Array).map(func(h): return _cells(h, plot.off)) if f.get("holes") is Array else []
		plot.map_kinds[kind] = true
		match kind:
			"park", "wood", "sand", "paved":
				_fill_poly(plot.cls, size, pts, PRIORITY[kind], holes)
			"water":
				if bool(f.get("closed", false)):
					_fill_poly(plot.cls, size, pts, PRIORITY.water, holes)
				else:
					_stroke(plot.cls, size, pts, float(f.get("width", 3.0)) / CELL_M, PRIORITY.water)
			"building":
				var bi := plot.buildings.size()
				plot.buildings.append(_building(f, bi))
				_fill_building(plot.cls, plot.owner, size, pts, bi, holes)
			"poi":
				plot.pois.append({"cell": pts[0], "sub": str(f.get("sub", "")), "name": str(f.get("name", ""))})
			"tree":
				if str(f.get("sub", "")) == "tree_row":
					for i in range(pts.size() - 1):
						var steps := maxi(1, int((pts[i] as Vector2).distance_to(pts[i + 1]) / 3.0))
						for k in steps:
							plot.trees.append((pts[i] as Vector2).lerp(pts[i + 1], float(k) / steps))
				else:
					plot.trees.append(pts[0])
			"bench":
				plot.benches.append(pts[0])
			"lamp":
				plot.lamps.append([pts[0], false])
			"crossing":
				plot.crossings.append(pts[0])
			"bus_stop":
				plot.stops.append({"cell": pts[0], "name": str(f.get("name", ""))})
			"barrier":
				plot.barriers.append({"kind": str(f.get("sub", "fence")), "pts": pts, "inferred": false})


## Sidewalks, then the streets and paths over them. Sidewalks are a cell-wide strip each side of a street,
## unless the map draws them separately (then those footways are the sidewalks) or you said there are
## none. Returns true when any sidewalk was filled in rather than read from the map.
static func _lay_streets(plot: Plot) -> bool:
	var size := plot.size
	var sidewalk_ways := plot.feats.any(func(f): return str(f.get("footway", "")) == "sidewalk")
	var walks_filled := false
	if str(plot.corr.get("sidewalks", "")) != "none" and not sidewalk_ways:
		for f in plot.feats:
			if str(f.get("kind", "")) == "road" and str(f.get("sub", "")) in SIDEWALK_ROADS and str(f.get("sidewalk", "")) != "no":
				_stroke(plot.cls, size, _cells(f.pts, plot.off), float(f.get("width", 6.0)) / CELL_M + 2.2, PRIORITY.sidewalk)
				walks_filled = walks_filled or not f.has("sidewalk")
	for f in plot.feats:
		var kind := str(f.get("kind", ""))
		if kind == "path" and str(f.get("footway", "")) == "sidewalk":
			# The map's own sidewalks: paved like the inferred ones, a cell wider so they meet the kerb
			# instead of leaving a strip of grass between the footway and the street.
			_stroke(plot.cls, size, _cells(f.get("pts", []), plot.off), float(f.get("width", 2.0)) / CELL_M + 1.0, PRIORITY.sidewalk)
		elif kind in ["road", "path"]:
			_stroke(plot.cls, size, _cells(f.get("pts", []), plot.off), float(f.get("width", 6.0)) / CELL_M, PRIORITY[kind])
	return walks_filled


## Your home: the building at the middle (or a small one put there). Then every building learns its cells.
static func _claim_home(plot: Plot) -> void:
	var size := plot.size
	var mid := plot.mid
	plot.home_bi = plot.owner[mid.y * size + mid.x]
	if plot.home_bi < 0:
		plot.home_bi = plot.buildings.size()
		plot.buildings.append({"sub": "home", "name": "", "levels": 2, "cells": [], "roof": "gabled", "inferred_shape": true})
		for z in range(mid.y - 2, mid.y + 2):
			for x in range(mid.x - 2, mid.x + 2):
				plot.cls[z * size + x] = PRIORITY.building
				plot.owner[z * size + x] = plot.home_bi
	plot.buildings[plot.home_bi]["mine"] = true
	for z in size:
		for x in size:
			var b := plot.owner[z * size + x]
			if b >= 0 and plot.cls[z * size + x] == PRIORITY.building:
				(plot.buildings[b].cells as Array).append(Vector2i(x, z))


## Gardens round homes (a little lawn and beds, filled in), and driveways out to their street.
static func _fill_gardens_and_driveways(plot: Plot) -> void:
	var size := plot.size
	for bi in plot.buildings.size():
		var b: Dictionary = plot.buildings[bi]
		if str(b.sub) != "home" or (b.cells as Array).is_empty():
			continue
		for c in b.cells:
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var n: Vector2i = c + Vector2i(dx, dz)
					if n.x >= 0 and n.y >= 0 and n.x < size and n.y < size and int(plot.cls[n.y * size + n.x]) == PRIORITY.grass:
						plot.cls[n.y * size + n.x] = PRIORITY.garden
						plot.filled["garden"] = true
		if bi == plot.home_bi and str(plot.corr.get("driveway", "")) == "no":
			continue
		if _driveway(plot.cls, size, b.cells, bi == plot.home_bi):
			plot.filled["driveway"] = true


## Your front door on the street side of your house, and a path from it to the street.
static func _lay_front_path(plot: Plot) -> void:
	var size := plot.size
	var home_cells: Array = plot.buildings[plot.home_bi].cells
	plot.door = _front_door(home_cells, plot.cls, size)
	plot.away = Vector2i(0, 1)
	for dv in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if home_cells.has(plot.door - dv):
			plot.away = dv
	var walk := plot.door
	for k in 14:
		if walk.x < 0 or walk.y < 0 or walk.x >= size or walk.y >= size:
			break
		var here := int(plot.cls[walk.y * size + walk.x])
		if here in [PRIORITY.building, PRIORITY.water] or (here >= PRIORITY.sidewalk and walk != plot.door):
			break
		if here < PRIORITY.path:
			plot.cls[walk.y * size + walk.x] = PRIORITY.path
		walk += plot.away


## Your yard's edge: a hedge (or the fence you said, or nothing), open where your path and drive go.
static func _edge_yard(plot: Plot) -> void:
	var yard := str(plot.corr.get("yard", ""))
	if yard == "open":
		return
	var lot := _yard(plot.cls, plot.size, plot.buildings[plot.home_bi].cells)
	if lot.size() >= 2:
		plot.barriers.append({"kind": "fence" if yard == "fence" else "hedge", "pts": lot, "inferred": yard == "", "yard": true})
		plot.filled["yard"] = true


## Street lamps every 30 m along streets, on a sidewalk (or verge), when the map has none.
static func _fill_lamps(plot: Plot) -> void:
	if not plot.lamps.is_empty() or str(plot.corr.get("lights", "")) == "none":
		return
	for f in plot.feats:
		if str(f.get("kind", "")) != "road" or str(f.get("sub", "")) in ["service", "track", "motorway", "trunk"]:
			continue
		var pts := _cells(f.pts, plot.off)
		var along := 0.0
		var side := 1.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg := a.distance_to(b)
			if seg < 0.01:
				continue
			var dir := (b - a) / seg
			var t := fposmod(-along, float(LAMP_EVERY))
			while t < seg:
				var p := a + dir * t + Vector2(-dir.y, dir.x) * side * (float(f.get("width", 6.0)) / CELL_M / 2.0 + 0.9)
				plot.lamps.append([p, true])
				side = -side
				t += LAMP_EVERY
			along += seg
	plot.filled["lights"] = not plot.lamps.is_empty()


## {block id: {street name: how much of it runs through the block}} (public names: each block is called
## after its main street).
static func _street_names(plot: Plot) -> Dictionary:
	var size := plot.size
	var road_names := {}
	for f in plot.feats:
		if str(f.get("kind", "")) != "road" or str(f.get("name", "")) == "":
			continue
		var pts := _cells(f.get("pts", []), plot.off)
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var steps := maxi(1, int(a.distance_to(b) / 4.0))
			for k in steps + 1:
				var c: Vector2 = a.lerp(b, float(k) / steps)
				if c.x < 0 or c.y < 0 or c.x >= size or c.y >= size:
					continue
				var cid := chunk_id(int(c.x) / CHUNK, int(c.y) / CHUNK)
				if not road_names.has(cid):
					road_names[cid] = {}
				road_names[cid][str(f.name)] = int(road_names[cid].get(str(f.name), 0)) + 1
	return road_names


## The places themselves, one per block, named after their main street and joined to their east and south
## neighbours.
static func _make_places(plot: Plot, road_names: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var chunks := plot.chunks
	var provenance := {"map": plot.map_kinds.keys().filter(func(k): return str(k) != ""), "filled": plot.filled.keys()}
	provenance.map.sort()
	provenance.filled.sort()
	for cj in chunks:
		for ci in chunks:
			var p := _chunk(ci, cj, plot.cls, plot.size, plot.buildings, rng)
			var names: Dictionary = road_names.get(chunk_id(ci, cj), {})
			var best := ""
			for nm in names:
				if best == "" or int(names[nm]) > int(names[best]):
					best = str(nm)
			p["name"] = best if best != "" else "Nearby"
			p["provenance"] = provenance.duplicate(true)
			out[chunk_id(ci, cj)] = p
	for cj in chunks:
		for ci in chunks:
			if ci + 1 < chunks:
				Places.link(out[chunk_id(ci, cj)], "east", out[chunk_id(ci + 1, cj)])
			if cj + 1 < chunks:
				Places.link(out[chunk_id(ci, cj)], "south", out[chunk_id(ci, cj + 1)])
	return out


## What stands on the streets: fences and hedges (cut at block edges), crossings painted on the street,
## trees, benches, lamps, bus stops, and a sign for each public place and named park.
static func _place_street_things(out: Dictionary, plot: Plot, places_cared: String, notes: Array) -> void:
	var cls := plot.cls
	var size := plot.size
	for b in plot.barriers:
		_place_barrier(out, b, cls, size)
	for c in plot.crossings:
		_place_crossing(out, Vector2i(c), cls, size)
	var cared := places_cared.to_lower()
	for t in plot.trees:
		_put(out, t, "tree", "")
	for b in plot.benches:
		_put(out, b, "bench", "")
	for l in plot.lamps:
		var lo := _put(out, l[0], "streetlamp", "", cls, size, [PRIORITY.sidewalk, PRIORITY.grass, PRIORITY.garden, PRIORITY.park, PRIORITY.paved])
		if not lo.is_empty() and bool(l[1]):
			lo["inferred"] = true
	for s in plot.stops:
		var so := _put(out, s.cell, "sign", ("Bus stop: %s" % str(s.name)) if str(s.name) != "" else "Bus stop")
		_put(out, Vector2i(s.cell) + Vector2i(1, 0), "bench", "")
		if not so.is_empty():
			so["color"] = "#5a7aa8"
	for p in plot.pois:
		var o := _put(out, p.cell, "sign", _with_note(str(p.name), notes))
		if not o.is_empty() and cared != "" and cared.contains(str(p.name).to_lower()):
			o["cared"] = true
	# Named parks get a bench and a sign.
	for f in plot.feats:
		if str(f.get("kind", "")) == "park" and str(f.get("name", "")) != "":
			var c := _centroid(_cells(f.get("pts", []), plot.off))
			_put(out, c, "sign", _with_note(str(f.name), notes))
			_put(out, c + Vector2i(2, 0), "bench", "")


## A public place's name, with the helper's public note about it when there is one ("Maple Park: a pond").
static func _with_note(place_name: String, notes: Array) -> String:
	var text := place_name
	for n in notes:
		if n is Dictionary and str(n.get("name", "")).to_lower() == place_name.to_lower() and str(n.get("note", "")) != "":
			text = "%s: %s" % [place_name, str(n.note)]
	return text


## Parks get trees here and there (a few, not a forest); gardens a flower bed or a bush (filled in: the map
## doesn't know your neighbours' beds).
static func _scatter_greenery(out: Dictionary, rng: RandomNumberGenerator) -> void:
	for id in out:
		var p: Dictionary = out[id]
		var placed := 0
		var beds := 0
		for a in p.get("floor_areas", []):
			var r: Array = a.rect
			if str(a.get("kind", "")) == "park" and placed < 6 and rng.randf() < 0.25:
				var cell := Vector2i(int(r[0]) + rng.randi_range(0, maxi(0, int(r[2]) - 1)), int(r[1]))
				if RoomEditor.object_at(p, cell.x, cell.y).is_empty():
					var o2 := LightHome.add(p, "tree", cell.x, cell.y)
					o2["hood"] = true
					o2["inferred"] = true
					placed += 1
			elif str(a.get("kind", "")) == "garden" and beds < 14 and int(r[2]) * int(r[3]) >= 3 and rng.randf() < 0.35:
				var cell2 := Vector2i(int(r[0]) + rng.randi_range(0, maxi(0, int(r[2]) - 1)), int(r[1]) + rng.randi_range(0, maxi(0, int(r[3]) - 1)))
				if RoomEditor.object_at(p, cell2.x, cell2.y).is_empty() and not _barrier_at(p, cell2):
					var o3 := LightHome.add(p, "flowers" if rng.randf() < 0.6 else "bush", cell2.x, cell2.y)
					o3["hood"] = true
					o3["inferred"] = true
					beds += 1


## Your front door into your ground floor, a mailbox beside it, and the spot you arrive on. Returns the id
## of the block your home is in.
static func _open_front_door(out: Dictionary, plot: Plot) -> String:
	var mid := plot.mid
	var away := plot.away
	var home_chunk := chunk_id(mid.x / CHUNK, mid.y / CHUNK)
	var hp: Dictionary = out[home_chunk]
	if str(hp.name) == "Nearby":
		hp["name"] = "Your street"
	var local := plot.door - Vector2i((mid.x / CHUNK) * CHUNK, (mid.y / CHUNK) * CHUNK)
	var d := RoomEditor.add_object(hp, local.x, local.y, "door")
	if not d.is_empty():
		d["door_target"] = HomePlaces.place_id(0)
		d["interaction_text"] = "Home"
		d["label"] = "Home"
		LightHome.fit_front_door(hp)   # (in your house's wall, facing out)
	# Arrive on the path in front of the door, not in it.
	hp["spawn"] = [clampi(local.x + away.x, 0, CHUNK - 1), clampi(local.y + away.y, 0, CHUNK - 1)]
	var mailbox := mailbox_cell(hp, local, away)
	if mailbox.x >= 0:
		LightHome.add(hp, "mailbox", mailbox.x, mailbox.y, int(d.get("rot", 0)))
	# Nothing filled in may stand in your way out: the cells of your front path stay clear.
	for b in hp.get("barriers", []):
		b["cells"] = (b.cells as Array).filter(func(c): return Vector2i(int(c[0]), int(c[1])) != local + away)
	return home_chunk


## A pitched roof only over a house-sized building whose whole footprint nearly fills its rectangle
## (decided once for the building, not per block: a big L-shaped block of flats spanning several blocks
## would otherwise get a gable slab over each piece). The map's own roof:shape is kept.
const PITCHED_MAX_SIDE := 14   # cells (35 m)
static func _roof_shape(b: Dictionary) -> String:
	var shape := str(b.get("roof", "flat"))
	if shape in ["flat", "dome", "round", "skillion"] or not bool(b.get("inferred_shape", false)):
		return shape
	var cells: Array = b.get("cells", [])
	if cells.is_empty():
		return shape
	var lo := Vector2i(cells[0])
	var hi := lo
	for c in cells:
		lo = Vector2i(mini(lo.x, int(c.x)), mini(lo.y, int(c.y)))
		hi = Vector2i(maxi(hi.x, int(c.x)), maxi(hi.y, int(c.y)))
	var w := hi.x - lo.x + 1
	var d := hi.y - lo.y + 1
	if w > PITCHED_MAX_SIDE or d > PITCHED_MAX_SIDE or cells.size() < 0.85 * w * d:
		return "flat"
	return shape


## What the map says about a building (shape, size, look); homes keep nothing personal.
static func _building(f: Dictionary, bi: int) -> Dictionary:
	var sub := str(f.get("sub", "home"))
	var b := {"sub": sub, "name": str(f.get("name", "")), "levels": int(f.get("levels", 1)), "cells": []}
	if f.has("height"):
		b["height"] = float(f.height)
	b["roof"] = str(f.get("roof", ""))
	if b.roof == "":
		b["roof"] = "gabled" if sub == "home" else "flat"
		b["inferred_shape"] = true
	for k in ["roof_colour", "colour"]:
		if f.has(k):
			b[k] = _colour(str(f[k]))
	if f.get("holes") is Array and not (f.holes as Array).is_empty():
		b["courtyard"] = true
	return b


static func _colour(c: String) -> String:
	if Color.html_is_valid(c):
		return "#" + Color.html(c).to_html(false)
	return str(NAMED_COLOURS.get(c.to_lower(), ""))


static func _chunk(ci: int, cj: int, cls: PackedByteArray, size: int, buildings: Array, rng: RandomNumberGenerator) -> Dictionary:
	var id := chunk_id(ci, cj)
	var p := LightHome.base_place(id, "Nearby", CHUNK, CHUNK, "outdoor")
	p["floor"] = {"color": COLORS.grass, "texture": ""}
	p["scale_m"] = CELL_M
	p["hood"] = {"ci": ci, "cj": cj}
	p["background"] = {"sky": "auto", "ground": true, "ground_color": COLORS.grass, "layers": [
		{"kind": "trees", "color": "#6f9a62", "distance": 2, "seed": 31 + ci}, {"kind": "hills", "color": "#9ab894", "distance": 3, "seed": 33 + cj}]}
	p["ambiance"] = {"music": "", "lighting": "real", "weather": "auto"}
	var x0 := ci * CHUNK
	var z0 := cj * CHUNK
	var areas: Array = []
	# Ground: row runs of each kind, merged down into rectangles.
	var open := {}   # "x|len|kind" -> rect index (the run continuing from the row above)
	for z in CHUNK:
		var next := {}
		var x := 0
		while x < CHUNK:
			var c := int(cls[(z0 + z) * size + x0 + x])
			if not GROUND.has(c):
				x += 1
				continue
			var start := x
			while x < CHUNK and int(cls[(z0 + z) * size + x0 + x]) == c:
				x += 1
			var key := "%d|%d|%d" % [start, x - start, c]
			if open.has(key):
				var ri: int = open[key]
				areas[ri].rect[3] = int(areas[ri].rect[3]) + 1
				next[key] = ri
			else:
				next[key] = areas.size()
				areas.append({"rect": [start, z, x - start, 1], "color": COLORS[GROUND[c]], "kind": GROUND[c]})
		open = next
	p["floor_areas"] = areas
	# Buildings in this block (the cells of each one that fall here).
	var bl: Array = []
	for bi in buildings.size():
		var b: Dictionary = buildings[bi]
		var cells: Array = []
		for c in b.cells:
			if c.x >= x0 and c.x < x0 + CHUNK and c.y >= z0 and c.y < z0 + CHUNK:
				cells.append([c.x - x0, c.y - z0])
		if cells.is_empty():
			continue
		var mine := bool(b.get("mine", false))
		var public: bool = str(b.sub) != "home"
		var h := 1.6 + 0.9 * clampi(int(b.levels), 1, 4) + (0.3 if public else 0.0)
		if b.has("height"):
			h = clampf(float(b.height) / CELL_M, 1.6, 6.0)   # (the map's own height, in cells)
		var entry := {"cells": cells, "h": h, "wall": HomeLook.DEFAULT_WALL if mine else str(b.get("colour", "")) if str(b.get("colour", "")) != "" else (("#e4e0ea" if public else HOUSE_WALLS[bi % HOUSE_WALLS.size()])),
			"roof": HomeLook.DEFAULT_ROOF if mine else (str(b.get("roof_colour", "")) if str(b.get("roof_colour", "")) != "" else HOUSE_ROOFS[bi % HOUSE_ROOFS.size()]),
			"kind": "mine" if mine else ("public" if public else "home"), "name": str(b.name) if public else "",
			"roof_shape": _roof_shape(b), "levels": clampi(int(b.levels), 1, 6)}
		if public and str(b.name) != "":
			entry["storefront"] = true
		if bool(b.get("inferred_shape", false)):
			entry["inferred"] = true
		bl.append(entry)
	p["buildings"] = bl
	p["objects"] = []
	p["barriers"] = []
	p["decals"] = []
	return p


## A point's cell on the grid.
static func _cells(pts: Array, off: float) -> Array:
	var out: Array = []
	for q in pts:
		out.append(Vector2((float(q[0]) + off) / CELL_M, (float(q[1]) + off) / CELL_M))
	return out


static func _in_holes(p: Vector2, holes: Array) -> bool:
	for h in holes:
		if (h as Array).size() >= 3 and Geometry2D.is_point_in_polygon(p, PackedVector2Array(h)):
			return true
	return false


static func _fill_poly(cls: PackedByteArray, size: int, pts: Array, value: int, holes: Array = []) -> void:
	if pts.size() < 3:
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var poly := PackedVector2Array(pts)
	for z in range(maxi(0, int(floor(lo.y))), mini(size, int(ceil(hi.y)) + 1)):
		for x in range(maxi(0, int(floor(lo.x))), mini(size, int(ceil(hi.x)) + 1)):
			var c := Vector2(x + 0.5, z + 0.5)
			if Geometry2D.is_point_in_polygon(c, poly) and int(cls[z * size + x]) <= value and not _in_holes(c, holes):
				cls[z * size + x] = value


static func _fill_building(cls: PackedByteArray, owner: PackedInt32Array, size: int, pts: Array, bi: int, holes: Array = []) -> void:
	if pts.size() < 3:
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var poly := PackedVector2Array(pts)
	var any := false
	for z in range(maxi(0, int(floor(lo.y))), mini(size, int(ceil(hi.y)) + 1)):
		for x in range(maxi(0, int(floor(lo.x))), mini(size, int(ceil(hi.x)) + 1)):
			var c := Vector2(x + 0.5, z + 0.5)
			if Geometry2D.is_point_in_polygon(c, poly) and not _in_holes(c, holes):   # (a courtyard stays open)
				cls[z * size + x] = maxi(int(cls[z * size + x]), PRIORITY.building)
				owner[z * size + x] = bi
				any = true
	if not any:
		# A building smaller than a cell: its middle cell.
		var c := Vector2i((lo + hi) / 2.0)
		if c.x >= 0 and c.y >= 0 and c.x < size and c.y < size:
			cls[c.y * size + c.x] = maxi(int(cls[c.y * size + c.x]), PRIORITY.building)
			owner[c.y * size + c.x] = bi


## A line `width` cells wide.
static func _stroke(cls: PackedByteArray, size: int, pts: Array, width: float, value: int) -> void:
	var r := maxf(0.5, width / 2.0)
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var lo := a.min(b) - Vector2(r, r)
		var hi := a.max(b) + Vector2(r, r)
		for z in range(maxi(0, int(floor(lo.y))), mini(size, int(ceil(hi.y)) + 1)):
			for x in range(maxi(0, int(floor(lo.x))), mini(size, int(ceil(hi.x)) + 1)):
				var c := Vector2(x + 0.5, z + 0.5)
				if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) <= r and int(cls[z * size + x]) < value and int(cls[z * size + x]) != PRIORITY.building:
					cls[z * size + x] = value


## A one-cell paved strip from a house to its nearest street (up to 8 cells away), on the side facing it.
static func _driveway(cls: PackedByteArray, size: int, cells: Array, mine: bool) -> bool:
	var own := {}
	for c in cells:
		own[c] = true
	var best: Array = []
	for c in cells:
		for dv in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var run: Array = []
			var m: Vector2i = c + dv
			var ok := false
			for k in 8:
				if m.x < 0 or m.y < 0 or m.x >= size or m.y >= size or own.has(m):
					break
				var here := int(cls[m.y * size + m.x])
				if here in [PRIORITY.road, PRIORITY.sidewalk]:
					ok = true
					break
				if here in [PRIORITY.building, PRIORITY.water, PRIORITY.path]:
					break
				run.append(m)
				m += dv
			if ok and not run.is_empty() and (best.is_empty() or run.size() < best.size()):
				best = run
	if best.is_empty():
		return false
	# (Your own front path goes elsewhere: the driveway is beside it, one cell over when they'd meet.)
	for m in best:
		cls[m.y * size + m.x] = PRIORITY.paved
	return true


## Your yard: a rectangle round your house (three cells out, never over a street, a building or water),
## as a closed outline of cell corners.
static func _yard(cls: PackedByteArray, size: int, cells: Array) -> Array:
	if cells.is_empty():
		return []
	var lo := Vector2i(cells[0])
	var hi := Vector2i(cells[0])
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var r := Rect2i(lo - Vector2i(3, 3), hi - lo + Vector2i(7, 7))
	# Shrink a side until it stops crossing streets, paths, water or someone else's house.
	var own := {}
	for c in cells:
		own[c] = true
	for _pass in 4:
		for side in 4:
			for _k in 3:
				if not _edge_blocked(cls, size, r, side, own):
					break
				match side:
					0: r = Rect2i(r.position + Vector2i(0, 1), r.size - Vector2i(0, 1))
					1: r = Rect2i(r.position, r.size - Vector2i(1, 0))
					2: r = Rect2i(r.position, r.size - Vector2i(0, 1))
					3: r = Rect2i(r.position + Vector2i(1, 0), r.size - Vector2i(1, 0))
	if r.size.x < hi.x - lo.x + 3 or r.size.y < hi.y - lo.y + 3:
		return []
	var a := Vector2(r.position)
	var b := Vector2(r.end)
	return [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]


static func _edge_blocked(cls: PackedByteArray, size: int, r: Rect2i, side: int, own: Dictionary) -> bool:
	var cells: Array = []
	match side:
		0: for x in range(r.position.x, r.end.x): cells.append(Vector2i(x, r.position.y))
		1: for z in range(r.position.y, r.end.y): cells.append(Vector2i(r.end.x - 1, z))
		2: for x in range(r.position.x, r.end.x): cells.append(Vector2i(x, r.end.y - 1))
		3: for z in range(r.position.y, r.end.y): cells.append(Vector2i(r.position.x, z))
	for c in cells:
		if c.x < 0 or c.y < 0 or c.x >= size or c.y >= size:
			return true
		var here := int(cls[c.y * size + c.x])
		if (here == PRIORITY.building and not own.has(c)) or here in [PRIORITY.road, PRIORITY.sidewalk, PRIORITY.water]:
			return true
	return false


## A fence/hedge/wall into the blocks it passes through: the line (drawn) and the cells it stands on
## (not walkable), except where it would cross a street, path, sidewalk, paving or water: gates.
static func _place_barrier(out: Dictionary, b: Dictionary, cls: PackedByteArray, size: int) -> void:
	var pts: Array = b.pts
	var per_chunk := {}
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var e: Vector2 = pts[i + 1]
		var steps := maxi(1, int(ceil(a.distance_to(e) / 0.5)))
		for k in steps + 1:
			var p := a.lerp(e, float(k) / steps)
			var c := Vector2i(int(floor(p.x - 0.001 if k == steps and e.x > a.x else p.x)), int(floor(p.y - 0.001 if k == steps and e.y > a.y else p.y)))
			if c.x < 0 or c.y < 0 or c.x >= size or c.y >= size:
				continue
			var here := int(cls[c.y * size + c.x])
			if here in [PRIORITY.road, PRIORITY.path, PRIORITY.sidewalk, PRIORITY.paved, PRIORITY.water, PRIORITY.building]:
				continue
			var id := chunk_id(c.x / CHUNK, c.y / CHUNK)
			if not per_chunk.has(id):
				per_chunk[id] = {"cells": {}, "ci": c.x / CHUNK, "cj": c.y / CHUNK}
			per_chunk[id].cells[c] = true
	for id in per_chunk:
		if not out.has(id):
			continue
		var ci: int = per_chunk[id].ci
		var cj: int = per_chunk[id].cj
		var o := Vector2(ci * CHUNK, cj * CHUNK)
		var local_pts: Array = []
		for q in pts:
			local_pts.append([snappedf((q as Vector2).x - o.x, 0.01), snappedf((q as Vector2).y - o.y, 0.01)])
		var cells: Array = []
		for c in per_chunk[id].cells:
			cells.append([c.x - ci * CHUNK, c.y - cj * CHUNK])
		(out[id].barriers as Array).append({"kind": str(b.kind), "pts": local_pts, "cells": cells, "inferred": bool(b.get("inferred", false))})


static func _barrier_at(p: Dictionary, cell: Vector2i) -> bool:
	for b in p.get("barriers", []):
		for c in b.cells:
			if int(c[0]) == cell.x and int(c[1]) == cell.y:
				return true
	return false


static func _building_at(p: Dictionary, cell: Vector2i) -> bool:
	for b in p.get("buildings", []):
		for c in b.cells:
			if int(c[0]) == cell.x and int(c[1]) == cell.y:
				return true
	return false


## Where the mailbox goes: beside your front door (at `door`, the house behind it, `away` out), along the
## house's front; never in a house, on a fence or on your path. (-1, -1) if both sides are taken.
static func mailbox_cell(p: Dictionary, door: Vector2i, away: Vector2i) -> Vector2i:
	var along := Vector2i(absi(away.y), absi(away.x))
	for c in [door + along, door - along]:
		if RoomEditor.in_bounds(p, c.x, c.y) and RoomEditor.object_at(p, c.x, c.y).is_empty() and not _building_at(p, c) and not _barrier_at(p, c):
			return c
	return Vector2i(-1, -1)


## A zebra crossing across the street at `cell` (the street's direction there decides the stripes).
static func _place_crossing(out: Dictionary, cell: Vector2i, cls: PackedByteArray, size: int) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size:
		return
	# Find the nearest road cell, then whether the road runs along x or z there.
	var road := Vector2i(-1, -1)
	for r in 3:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := cell + Vector2i(dx, dz)
				if road.x < 0 and c.x >= 0 and c.y >= 0 and c.x < size and c.y < size and int(cls[c.y * size + c.x]) == PRIORITY.road:
					road = c
	if road.x < 0:
		return
	var run_x := 0
	var run_z := 0
	for k in range(-3, 4):
		if road.x + k >= 0 and road.x + k < size and int(cls[road.y * size + road.x + k]) == PRIORITY.road:
			run_x += 1
		if road.y + k >= 0 and road.y + k < size and int(cls[(road.y + k) * size + road.x]) == PRIORITY.road:
			run_z += 1
	# The street runs along the longer run; the crossing goes across it, over every road cell there.
	var across := Vector2i(0, 1) if run_x >= run_z else Vector2i(1, 0)
	var start := road
	while start.x - across.x >= 0 and start.y - across.y >= 0 and int(cls[(start.y - across.y) * size + start.x - across.x]) == PRIORITY.road:
		start -= across
	var cells: Array = []
	var c2 := start
	while c2.x < size and c2.y < size and int(cls[c2.y * size + c2.x]) == PRIORITY.road and cells.size() < 12:
		cells.append(c2)
		c2 += across
	var id := chunk_id(road.x / CHUNK, road.y / CHUNK)
	if not out.has(id):
		return
	var o := Vector2i((road.x / CHUNK) * CHUNK, (road.y / CHUNK) * CHUNK)
	(out[id].decals as Array).append({"kind": "zebra", "axis": "z" if across.y != 0 else "x",
		"cells": cells.filter(func(c): return chunk_id(c.x / CHUNK, c.y / CHUNK) == id).map(func(c): return [c.x - o.x, c.y - o.y])})


static func _centroid(pts: Array) -> Vector2i:
	if pts.is_empty():
		return Vector2i.ZERO
	var s := Vector2.ZERO
	for p in pts:
		s += p
	return Vector2i(s / pts.size())


## A thing on the grid, into the block it falls in (skipping cells that are taken or not walkable ground;
## with `grounds`, only on those ground kinds).
static func _put(out: Dictionary, cell: Variant, what: String, text: String, cls: PackedByteArray = PackedByteArray(), size: int = 0, grounds: Array = []) -> Dictionary:
	var c := Vector2i(cell) if cell is Vector2 else (cell as Vector2i)
	if c.x < 0 or c.y < 0:
		return {}
	if not grounds.is_empty() and (c.x >= size or c.y >= size or not int(cls[c.y * size + c.x]) in grounds):
		return {}
	var ci := c.x / CHUNK
	var cj := c.y / CHUNK
	var id := chunk_id(ci, cj)
	if not out.has(id):
		return {}
	var p: Dictionary = out[id]
	var l := c - Vector2i(ci * CHUNK, cj * CHUNK)
	for b in p.get("buildings", []):
		for bc in b.cells:
			if int(bc[0]) == l.x and int(bc[1]) == l.y:
				return {}
	if not RoomEditor.object_at(p, l.x, l.y).is_empty() or _barrier_at(p, l):
		return {}
	var o: Dictionary
	if what == "sign":
		o = RoomEditor.add_object(p, l.x, l.y, "sign")
		if not o.is_empty():
			o["interaction_text"] = text
			o["color"] = "#7a9a6a"
	else:
		o = LightHome.add(p, what, l.x, l.y)
		o["hood"] = true
	return o


## The cell just outside your house on the side nearest a road (your front door).
static func _front_door(cells: Array, cls: PackedByteArray, size: int) -> Vector2i:
	var best := Vector2i(size / 2, size / 2 + 3)
	var best_d := 1e9
	var mine := {}
	for c in cells:
		mine[c] = true
	for c in cells:
		for dv in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = c + dv
			if mine.has(n) or n.x < 0 or n.y < 0 or n.x >= size or n.y >= size:
				continue
			if int(cls[n.y * size + n.x]) >= PRIORITY.building:
				continue
			# Distance to the nearest road cell along that direction (a few steps out).
			var d := 99.0
			for k in range(1, 12):
				var m: Vector2i = n + dv * k
				if m.x < 0 or m.y < 0 or m.x >= size or m.y >= size:
					break
				if int(cls[m.y * size + m.x]) == PRIORITY.road:
					d = k
					break
			if d < best_d:
				best_d = d
				best = n
	return best


## Writes the neighbourhood (replacing an older one) and links your ground floor's front gate to it.
static func save_all(places: Dictionary) -> String:
	var removals := PackedStringArray()
	for id in SaveManager.list_light_rooms():
		if str(id).begins_with("lw_hood_") and not places.has(id):
			removals.append("places/" + str(id) + ".json")
	if not preload("res://scripts/home/home_store.gd").apply_batch(prepare_writes(places), removals):
		return ""
	return str(places.get("home_chunk", ""))


static func prepare_writes(places: Dictionary) -> Dictionary:
	var writes := {}
	var home_chunk := str(places.get("home_chunk", ""))
	for id in places:
		if id == "home_chunk":
			continue
		if SaveManager.room_exists(id):
			# Pieces you put on your street stay (where they still fit).
			var old := SaveManager.load_room(id)
			for o in old.get("objects", []):
				if bool(o.get("user", false)) and RoomEditor.object_at(places[id], int(o.pos[0]), int(o.pos[2])).is_empty() and not _barrier_at(places[id], Vector2i(int(o.pos[0]), int(o.pos[2]))):
					(places[id].objects as Array).append(o)
		writes["places/" + str(id) + ".json"] = places[id]
	var ground := front_gate(home_chunk)
	if not ground.is_empty():
		writes["places/" + str(ground.id) + ".json"] = ground
	return writes


## Your ground floor's front gate (at the lawn's street side) leads out to your street.
static func link_front_gate(home_chunk: String) -> void:
	var g := front_gate(home_chunk)
	if not g.is_empty():
		SaveManager.save_room(g)


static func front_gate(home_chunk: String) -> Dictionary:
	var gid := HomePlaces.place_id(0)
	if home_chunk == "" or not SaveManager.room_exists(gid):
		return {}
	var g := SaveManager.load_room(gid)
	g["objects"] = (g.get("objects", []) as Array).filter(func(o): return not bool(o.get("street_gate", false)))
	var w := int(g.size.w)
	var d := int(g.size.d)
	var o := RoomEditor.add_object(g, w / 2, d - 1, "door")
	if o.is_empty():
		o = RoomEditor.add_object(g, w / 2 + 1, d - 1, "door")
	if not o.is_empty():
		o["door_target"] = home_chunk
		o["interaction_text"] = "Out to the street"
		o["street_gate"] = true
	return g
