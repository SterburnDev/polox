extends "res://scripts/ui/screen_panel.gd"
## My home > Sources > Map and references: a look at the real thing, and what your streets are made of.
##   Links (each opens your browser with map coordinates only, when you tap it; nothing comes back):
##     OpenStreetMap at your home, Google Maps there, Street View there (Google's documented Maps URLs,
##     no key), and each named public place nearby on OpenStreetMap.
##   What came from the map and what Polox filled in (hood_builder.gd's provenance), with your own fixes
##   for the filled-in parts (your yard's edge, the driveway, sidewalks, street lamps): kept in osm.json
##   ("corrections") and applied to the streets at once, with a snapshot first.
## Tags: [LIGHT_WORLD_MAP]

const HomeStore := preload("res://scripts/home/home_store.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const KIND_WORDS := {"road": "streets", "path": "paths", "building": "buildings", "park": "parks", "water": "water", "wood": "woods",
	"landuse": "land use", "paved": "paving and parking", "sand": "sand", "barrier": "fences and hedges", "poi": "public places",
	"tree": "trees", "bench": "benches", "lamp": "street lamps", "crossing": "crossings", "bus_stop": "bus stops", "entrance": "entrances",
	"sidewalks": "sidewalks", "lights": "street lamps", "garden": "gardens", "driveway": "driveways", "yard": "your yard's edge"}
## Your fixes: [osm.json corrections key, label, [[value, choice label], ...]] ("" = as Polox guessed).
const FIXES := [["yard", "Yard edge", [["", "Hedge (a guess)"], ["fence", "Fence"], ["hedge", "Hedge"], ["open", "Open"]]],
	["driveway", "Driveway", [["", "Yes (a guess)"], ["no", "None"]]],
	["sidewalks", "Sidewalks", [["", "As mapped or guessed"], ["none", "None"]]],
	["lights", "Street lamps", [["", "As mapped or guessed"], ["none", "None"]]]]

var extract: Dictionary = {}
var status: Label
var on_changed: Callable = Callable()   # (My home refreshes the world when the streets were rebuilt)


func setup_refs() -> void:
	setup("Map and references", Vector2(820, 680))
	var raw: Variant = JsonUtil.read_json(HomeStore.path("osm.json"), {}) if FileAccess.file_exists(HomeStore.path("osm.json")) else {}
	extract = raw if raw is Dictionary else {}
	var v := UiKit.vbox(10)
	if not extract.get("center") is Dictionary:
		v.add_child(UiKit.para("Map your streets first (My home > Map my streets).", 18))
		body.add_child(v)
		return
	var lat := float(extract.center.get("lat", 0.0))
	var lon := float(extract.center.get("lon", 0.0))
	v.add_child(UiKit.para("These open your browser with map coordinates only.", 16, ThemeBuilder.MUTED))
	var GoogleMaps := preload("res://scripts/home/google_maps.gd")
	var row := UiKit.flow_row(8)
	for link in [["OpenStreetMap", "OpenStreetMap", osm_url(lat, lon)], ["Google Maps", "GoogleMaps", maps_url(lat, lon)], ["Street View", "StreetView", street_view_url(lat, lon)]]:
		var url := str(link[2])
		var b := UiKit.button(str(link[0]), func(): OS.shell_open(url), 0)
		b.name = str(link[1])
		row.add_child(b)
	var enrich_btn := UiKit.button("Enrich with Google Maps", func(): _confirm_google_maps(lat, lon), 0)
	enrich_btn.name = "EnrichGoogleMaps"
	enrich_btn.disabled = OS.has_feature("web")
	row.add_child(enrich_btn)
	v.add_child(row)
	var cached_gm := GoogleMaps.load_cached()
	if not cached_gm.is_empty():
		var vibe := str(cached_gm.get("atmosphere", "")).strip_edges()
		if vibe != "":
			v.add_child(UiKit.para("Google Maps note: " + vibe, 16, ThemeBuilder.MINT))
	var nearby: Array = (extract.get("features", []) as Array).filter(func(f): return f is Dictionary and str(f.get("name", "")) != "" and (f.get("ll") is Array or str(f.get("maps_uri", "")) != ""))
	if not nearby.is_empty():
		v.add_child(UiKit.label("Nearby", 20, ThemeBuilder.YELLOW))
		var seen := {}
		for f in nearby.slice(0, 24):
			if seen.has(str(f.name)):
				continue
			seen[str(f.name)] = true
			var r := UiKit.hbox(8)
			var source_tag := "  (Google Maps)" if str(f.get("source", "")) == "google_maps" else ""
			var l := UiKit.para(str(f.name) + source_tag, 16)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(l)
			var gm_uri := safe_maps_url(str(f.get("maps_uri", "")))
			var ll: Variant = f.get("ll")
			var url := gm_uri
			if url == "" and ll is Array and (ll as Array).size() >= 2:
				url = osm_url(float(ll[0]), float(ll[1]))
			if url != "":
				r.add_child(UiKit.button("Google Maps" if gm_uri != "" else "Map", func(): OS.shell_open(url), 0))
				v.add_child(r)
	var prov := provenance()
	v.add_child(UiKit.label("What your streets are made of", 20, ThemeBuilder.YELLOW))
	v.add_child(UiKit.para("From the map: " + _words(prov.get("map", [])), 16))
	var filled := _words(prov.get("filled", []))
	if filled != "":
		v.add_child(UiKit.para("Filled in by Polox (guesses you can change): " + filled, 16))
	var corr: Dictionary = extract.get("corrections", {}) if extract.get("corrections") is Dictionary else {}
	for fix in FIXES:
		var key := str(fix[0])
		var values: Array = (fix[2] as Array).map(func(o): return str(o[0]))
		var pick := UiKit.option((fix[2] as Array).map(func(o): return str(o[1])), maxi(0, values.find(str(corr.get(key, "")))))
		pick.name = "Fix_" + key
		pick.item_selected.connect(func(i): correct(key, str(values[i])))
		v.add_child(UiKit.field_row(str(fix[1]), pick, 150))
	status = UiKit.para("", 16, ThemeBuilder.MUTED)
	status.name = "RefsStatus"
	v.add_child(status)
	var credit_line := str(extract.get("credit", "Map data © OpenStreetMap contributors"))
	v.add_child(UiKit.para("Map data " + credit_line, 14, ThemeBuilder.MUTED))
	body.add_child(UiKit.scroll(v))


func _confirm_google_maps(lat: float, lon: float) -> void:
	var GoogleMaps := preload("res://scripts/home/google_maps.gd")
	if not GoogleMaps.is_enabled():
		if status:
			status.text = "Turn on Google Maps first: Settings > Light World > Helper setup."
		return
	if GoogleMaps.mode() == "links_only":
		var prompt_text: String = GoogleMaps.manual_grounding_prompt(lat, lon, int(extract.get("radius", 300)))
		DisplayServer.clipboard_set(prompt_text)
		if status:
			status.text = "Copied a Google Maps prompt for Gemini / Google AI Plus to your clipboard."
		return
	if not GoogleMaps.can_fetch():
		if status:
			status.text = GoogleMaps.status_summary()
		return
	var choice_panel: Control = load("res://scripts/ui/choice_panel.gd").new()
	var host := get_tree().current_scene
	if host and host.has_method("open_panel"):
		host.open_panel(choice_panel)
	else:
		add_child(choice_panel)
	choice_panel.ask(
		"Enrich with Google Maps?",
		"Sends your map coordinates and a %d m radius to Google (%s) to find public parks, cafes, and landmarks nearby. Private homes are excluded." % [int(extract.get("radius", 300)), str(GoogleMaps.MODE_LABELS[GoogleMaps.mode()])],
		[["Enrich nearby places", func(): _run_google_maps(lat, lon)], ["Not now", func(): pass]]
	)


func _run_google_maps(lat: float, lon: float) -> void:
	var GoogleMaps := preload("res://scripts/home/google_maps.gd")
	var client: Node = GoogleMaps.new()
	add_child(client)
	client.progress.connect(func(line):
		if status:
			status.text = str(line))
	var res: Dictionary = await client.fetch_nearby(lat, lon, int(extract.get("radius", 300)))
	client.queue_free()
	if not is_inside_tree():
		return
	if not bool(res.get("ok", false)):
		if status:
			status.text = str(res.get("error", "Google Maps lookup failed."))
		return
	var places: Array = res.get("places", [])
	if places.is_empty():
		if status:
			status.text = "Google Maps checked the area; no additional public spots found."
		return
	var merged: Dictionary = GoogleMaps.merge_into_extract(extract, places)
	var answers: Dictionary = HomeStore.load_home().get("answers", {})
	if load("res://scripts/home/home_mapper.gd").build_streets(merged, answers):
		extract = merged
		if status:
			status.text = "Added %d public Google Maps spots to your streets." % places.size()
		if on_changed.is_valid():
			on_changed.call()
	elif status:
		status.text = "Google Maps returned %d spots, saved in your local cache." % places.size()


static func osm_url(lat: float, lon: float) -> String:
	return "https://www.openstreetmap.org/?mlat=%.6f&mlon=%.6f#map=18/%.6f/%.6f" % [lat, lon, lat, lon]


static func maps_url(lat: float, lon: float) -> String:
	return "https://www.google.com/maps/search/?api=1&query=%.6f%%2C%.6f" % [lat, lon]


static func street_view_url(lat: float, lon: float) -> String:
	return "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=%.6f%%2C%.6f" % [lat, lon]


## {"map": [...], "filled": [...]} from your streets as built (any block carries it).
## Accepts only clean HTTPS Google Maps links (rejects whitespace, control characters, and untrusted hosts).
static func safe_maps_url(uri: String) -> String:
	var u := uri.strip_edges()
	if not u.begins_with("https://"):
		return ""
	for bad in [" ", "\t", "\r", "\n"]:
		if u.contains(bad):
			return ""
	var after := u.substr(8)
	var slash := after.find("/")
	var q := after.find("?")
	var end := after.length()
	if slash >= 0:
		end = mini(end, slash)
	if q >= 0:
		end = mini(end, q)
	var host := after.substr(0, end).to_lower()
	if host in ["maps.google.com", "www.google.com", "google.com", "maps.app.goo.gl"]:
		return u
	return ""


static func provenance() -> Dictionary:
	for id in SaveManager.list_light_rooms():
		if str(id).begins_with("lw_hood_"):
			var p := SaveManager.load_room(id)
			if p.get("provenance") is Dictionary:
				return p.provenance
	return {}


static func _words(kinds: Variant) -> String:
	var out := PackedStringArray()
	for k in (kinds if kinds is Array else []):
		var w := str(KIND_WORDS.get(str(k), ""))
		if w != "" and not w in out:
			out.append(w)
	return ", ".join(out)


## One of your fixes: saved into osm.json and the streets rebuilt with it (a snapshot first).
func correct(key: String, value: String) -> bool:
	var corr: Dictionary = (extract.get("corrections", {}) as Dictionary).duplicate() if extract.get("corrections") is Dictionary else {}
	if value == "":
		corr.erase(key)
	else:
		corr[key] = value
	var next := extract.duplicate(true)
	next["corrections"] = corr
	var answers: Dictionary = HomeStore.load_home().get("answers", {})
	if not load("res://scripts/home/home_mapper.gd").build_streets(next, answers):
		if status:
			status.text = "Couldn't change that. Nothing changed."
		return false
	extract = next
	if status:
		status.text = "Done. Your streets have it now."
	if on_changed.is_valid():
		on_changed.call()
	return true
