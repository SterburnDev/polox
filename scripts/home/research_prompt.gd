extends RefCounted
## What Polox asks a helper (Claude through Claude Code or the API, Gemini, OpenAI, Codex, or any AI you
## paste it into) when it looks up your home. The prompt says, in this order: how the game works, how the
## house gets built from the answer, which tools to use, what to find out (when it was built, its colours,
## its street, what listing sites such as Zillow say), the rules (building facts only, no people, respect
## every site's terms) and the one JSON shape to answer in (SCHEMA). The same question for every helper,
## so the answers mix.
## Tags: [AI_HELPER]

const FACT_KEYS: PackedStringArray = ["year_built", "sqft", "floors", "bedrooms", "bathrooms", "lot_sqft", "construction",
	"footprint_w_m", "footprint_d_m", "basement", "garage", "style", "roof", "exterior",
	"exterior_color", "roof_color", "door_color"]
## The listing sites the prompt names (their pages are read like any other: no logins, no getting round blocks).
const LISTING_SITES: PackedStringArray = ["Zillow", "Redfin", "Realtor.com", "Trulia", "Homes.com"]
const SOURCE_KINDS: PackedStringArray = ["assessor", "permit", "plat", "listing", "archive", "historic", "street", "other"]
## What each fact is called in front of the player, and its unit (a raw key such as "sqft" is never shown).
const FACT_NAMES := {"year_built": "Built", "sqft": "Size", "floors": "Floors", "bedrooms": "Bedrooms", "bathrooms": "Bathrooms",
	"lot_sqft": "Lot", "construction": "Built from", "footprint_w_m": "Outline width", "footprint_d_m": "Outline depth",
	"basement": "Basement", "garage": "Garage", "style": "Style", "roof": "Roof", "exterior": "Outside walls",
	"exterior_color": "Outside colour", "roof_color": "Roof colour", "door_color": "Front door colour"}
const FACT_UNITS := {"sqft": "sq ft", "lot_sqft": "sq ft", "footprint_w_m": "m", "footprint_d_m": "m"}


## "sqft" -> "Size", "exterior_color" -> "Outside colour"; a key the game doesn't know is spelled out as words.
static func fact_name(key: Variant) -> String:
	return str(FACT_NAMES.get(str(key), str(key).replace("_", " ").capitalize()))


## A fact's value the way a person writes it: 2163.0 -> "2,163 sq ft", 8.4 -> "8.4 m", true -> "yes",
## and a year stays "1889".
static func fact_value(key: Variant, value: Variant) -> String:
	if value is bool:
		return "yes" if value else "no"
	if not (value is float or value is int):
		return str(value)
	var unit := str(FACT_UNITS.get(str(key), ""))
	var number := float(value)
	var text := str(snappedf(number, 0.1))
	if is_equal_approx(number, round(number)):
		text = str(int(round(number)))
		if unit == "sq ft":
			# (thousands in groups of three, for areas only: a year or a count never needs them)
			var grouped := ""
			while text.length() > 3:
				grouped = "," + text.right(3) + grouped
				text = text.left(text.length() - 3)
			text += grouped
	return text if unit == "" else "%s %s" % [text, unit]

const SCHEMA := {
	"type": "object",
	"properties": {
		"address_found": {"type": "boolean"},
		"summary": {"type": "string"},
		"facts": {"type": "array", "items": {"type": "object", "properties": {
			"key": {"type": "string"}, "value": {"type": ["string", "number", "boolean"]}, "source": {"type": "string"},
			"confidence": {"type": "number"}, "note": {"type": "string"}}, "required": ["key", "value", "source", "confidence"]}},
		"footprint": {"type": "object", "properties": {"width_m": {"type": "number"}, "depth_m": {"type": "number"},
			"shape_note": {"type": "string"}, "source": {"type": "string"}}},
		"rooms": {"type": "array", "items": {"type": "object", "properties": {
			"kind": {"type": "string"}, "name": {"type": "string"}, "floor": {"type": "integer"}, "width_m": {"type": "number"},
			"depth_m": {"type": "number"}, "position": {"type": "string"}, "wall_color": {"type": "string"},
			"floor_material": {"type": "string"}, "source": {"type": "string"}}, "required": ["kind", "floor"]}},
		"permits": {"type": "array", "items": {"type": "object", "properties": {
			"year": {"type": "integer"}, "date": {"type": "string"}, "work": {"type": "string"}, "source": {"type": "string"}}, "required": ["work"]}},
		"history": {"type": "array", "items": {"type": "object", "properties": {
			"year": {"type": "integer"}, "text": {"type": "string"}, "source": {"type": "string"}}, "required": ["text"]}},
		"conflicts": {"type": "array", "items": {"type": "object", "properties": {
			"key": {"type": "string"}, "values": {"type": "array", "items": {"type": "object", "properties": {
				"value": {"type": ["string", "number"]}, "source": {"type": "string"}}}}}}},
		"sources": {"type": "array", "items": {"type": "object", "properties": {
			"id": {"type": "string"}, "kind": {"type": "string"}, "title": {"type": "string"}, "url": {"type": "string"},
			"said": {"type": "string"}}, "required": ["id", "kind", "title"]}},
		"blocked": {"type": "array", "items": {"type": "object", "properties": {
			"what": {"type": "string"}, "url": {"type": "string"}, "why": {"type": "string"}}}},
		"open_questions": {"type": "array", "items": {"type": "string"}},
		"location": {"type": "object", "properties": {"lat": {"type": "number"}, "lon": {"type": "number"}, "source": {"type": "string"}}},
		"neighbourhood": {"type": "array", "items": {"type": "object", "properties": {
			"name": {"type": "string"}, "kind": {"type": "string"}, "note": {"type": "string"}, "source": {"type": "string"}}}},
	},
	"required": ["address_found", "facts", "sources"],
}


static func response_schema() -> Dictionary:
	var schema := SCHEMA.duplicate(true)
	var p: Dictionary = schema.properties
	p.facts.items.properties.key["enum"] = Array(FACT_KEYS)
	p.facts.items.properties.confidence.merge({"minimum": 0, "maximum": 1})
	p.sources.items.properties.kind["enum"] = Array(SOURCE_KINDS)
	p.sources.items.properties.id.merge({"minLength": 1, "maxLength": 80})
	p.rooms.items.properties.kind["enum"] = ["living", "kitchen", "dining", "bedroom", "bathroom", "office", "laundry", "garage", "family", "storage", "hall"]
	p.rooms.items.properties.floor.merge({"minimum": -1, "maximum": 3})
	for field in ["wall_color", "floor_material"]:
		p.rooms.items.properties[field].merge({"maxLength": 40})
	for field in ["width_m", "depth_m"]:
		p.footprint.properties[field].merge({"minimum": 3, "maximum": 60})
		p.rooms.items.properties[field].merge({"minimum": 0.1, "maximum": 30})
	p.location.properties.lat.merge({"minimum": -90, "maximum": 90})
	p.location.properties.lon.merge({"minimum": -180, "maximum": 180})
	return schema


## Plausible ranges for numeric facts (a value outside one is a mistake, not a discovery).
const FACT_BOUNDS := {"year_built": [1600, 2100], "sqft": [100, 100000], "floors": [1, 10], "bedrooms": [0, 30],
	"bathrooms": [0, 30], "lot_sqft": [100, 10000000], "footprint_w_m": [3, 60], "footprint_d_m": [3, 60]}


static func validate_response(raw: Dictionary) -> String:
	var error := preload("res://scripts/home/helper_json.gd").validate(raw, response_schema())
	if error != "":
		return error
	var sources := {}
	for i in raw.sources.size():
		var source: Dictionary = raw.sources[i]
		if sources.has(source.id):
			return "$.sources[%d].id: duplicate source identifier." % i
		sources[source.id] = true
		if str(source.get("url", "")) != "" and not public_url(str(source.url)):
			return "$.sources[%d].url: use a public web address (http or https, no login, no local or private address)." % i
	for i in raw.get("blocked", []).size():
		if str(raw.blocked[i].get("url", "")) != "" and not public_url(str(raw.blocked[i].url)):
			return "$.blocked[%d].url: use a public web address." % i
	var this_year := int(Time.get_date_dict_from_system().year)
	for i in raw.facts.size():
		var fact: Dictionary = raw.facts[i]
		# A researched fact always says where it came from (one of the sources listed).
		if str(fact.source).strip_edges() == "":
			return "$.facts[%d].source: every fact needs the id of its source." % i
		if FACT_BOUNDS.has(fact.key):
			var v: Variant = fact.value
			var n := float(v) if (v is int or v is float) else (str(v).to_float() if str(v).is_valid_float() else NAN)
			var lo: float = FACT_BOUNDS[fact.key][0]
			var hi: float = minf(FACT_BOUNDS[fact.key][1], this_year + 1) if fact.key == "year_built" else FACT_BOUNDS[fact.key][1]
			if is_nan(n) or n < lo or n > hi:
				return "$.facts[%d].value: outside the plausible range for %s." % [i, fact.key]
	for list in ["permits", "history"]:
		for i in raw.get(list, []).size():
			var year := int(raw[list][i].get("year", 0))
			if raw[list][i].has("year") and year != 0 and (year < 1600 or year > this_year + 1):
				return "$.%s[%d].year: not a plausible year." % [list, i]
	if raw.has("location") and not raw.location.is_empty() and not (raw.location.has("lat") and raw.location.has("lon")):
		return "$.location: latitude and longitude must be supplied together."
	return _source_references(raw, sources, "$")


## A link Polox may show and open: http(s) only, a real public host name, no login details, no
## local or private network address (a helper can't point the player at their own router or PC).
static func public_url(url: String) -> bool:
	if url.length() > 2048 or not (url.begins_with("https://") or url.begins_with("http://")):
		return false
	for ch in url:
		if ch.unicode_at(0) <= 32 or ch == "\\":
			return false
	var rest := url.substr(url.find("://") + 3)
	var host := rest
	for stop in ["/", "?", "#"]:
		if host.contains(stop):
			host = host.left(host.find(stop))
	if host.contains("@") or host.begins_with("["):
		return false   # login details in the link, or a raw IPv6 address
	if host.contains(":"):
		var port := host.get_slice(":", 1)
		if not port.is_valid_int() or host.get_slice_count(":") != 2:
			return false
		host = host.get_slice(":", 0)
	host = host.to_lower().trim_suffix(".")
	if host == "" or not host.contains(".") or host.begins_with(".") or host.begins_with("-") or host.ends_with("-"):
		return false
	if host == "localhost" or host.ends_with(".localhost") or host.ends_with(".local") or host.ends_with(".internal") or host.ends_with(".lan") or host.ends_with(".home.arpa"):
		return false
	var parts := host.split(".")
	if parts.size() == 4 and Array(parts).all(func(p): return p.is_valid_int()):
		var a := int(parts[0])
		var b := int(parts[1])
		if a in [0, 10, 127] or (a == 169 and b == 254) or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 100 and b >= 64 and b <= 127) or a >= 224:
			return false
	return true


static func _source_references(value: Variant, sources: Dictionary, path: String) -> String:
	if value is Dictionary:
		if value.has("source") and str(value.source) != "" and not sources.has(value.source):
			return path + ".source: reference does not match a source identifier."
		for key in value:
			var error := _source_references(value[key], sources, path + "." + str(key))
			if error != "":
				return error
	elif value is Array:
		for i in value.size():
			var error := _source_references(value[i], sources, "%s[%d]" % [path, i])
			if error != "":
				return error
	return ""


## The question. `where`: the address (or street / city) the player typed. `known`: building answers
## from the survey (floors, rooms) to check against; nothing personal (no memories, no names).
static func question(where: String, known: Dictionary, files: PackedStringArray = PackedStringArray()) -> String:
	var lines: PackedStringArray = []
	lines.append("You are helping a video game, Polox, rebuild the player's own home, with their permission, from public information.")
	lines.append("The home: " + where.strip_edges())
	if not known.is_empty():
		lines.append("What the player said about it (check it, don't just repeat it): " + JSON.stringify(known))
	lines.append("")
	lines.append("HOW THE GAME WORKS")
	lines.append("- Polox is a cosy 3D life game. Its Light World is the player's real home and street, rebuilt so they can walk around it.")
	lines.append("- Everything sits on a grid where one cell is one metre. The house is a set of floors. Each floor is a rectangle divided into rooms, and each room has a kind, a size, a floor material and a wall colour. Doors and windows sit in the walls, and the front door faces the street.")
	lines.append("- Outside, the house stands on its street in its own colours, with its roof and its front door. The streets and the other buildings come from OpenStreetMap, not from you.")
	lines.append("")
	lines.append("HOW THE HOUSE GETS BUILT (what your answer is used for)")
	lines.append("- You don't draw anything. You report facts, the game's builder turns them into the house, and the player sees where each fact came from.")
	lines.append("- floors and basement: how many levels are built.")
	lines.append("- footprint (width and depth in metres), or else sqft: how big each floor is.")
	lines.append("- bedrooms, bathrooms and the rooms list (kind, floor, width_m, depth_m, and position such as front, back, left or right): which rooms are built, on which floor, how big and where.")
	lines.append("- exterior_color, roof_color, door_color and roof (its shape: gabled, hipped, flat): how the house looks from the street. Plain colour words are best (\"light grey\", \"red brick\", \"dark green\"); a #hex colour works too.")
	lines.append("- a room's wall_color and floor_material (wood, carpet, tile, vinyl, concrete or stone): that room's paint and floor.")
	lines.append("- year_built, permits and history: the home's timeline.")
	lines.append("- location (latitude and longitude): where the street map is centred. neighbourhood: the public places shown near the home.")
	lines.append("- What the player told the game always wins. Where the records differ, the game shows both and the player chooses.")
	lines.append("")
	lines.append("WHAT TOOLS TO USE")
	lines.append("- Your web search tool to find pages, and your page-reading tool (browse, fetch, open a link) to read them. Read the pages themselves; never answer from memory.")
	lines.append("- Listing sites: " + ", ".join(LISTING_SITES) + ", and their archived copies on the Wayback Machine (web.archive.org).")
	lines.append("- The county assessor or property appraiser site, the city or county permit portal, and the county GIS or parcel viewer.")
	lines.append("- Street-level photos (Google Street View, Bing Streetside, Mapillary) for what the house looks like from the street.")
	lines.append("- A map (OpenStreetMap, Google Maps) for the location and the public places nearby.")
	lines.append("- No search tool? Say so in the summary, set address_found to false, and use \"blocked\" to list what the player could look up by hand.")
	lines.append("")
	lines.append("WHAT TO FIND OUT")
	lines.append("Work like a careful detective through the public record, and cross-check what you find:")
	lines.append("1. When it was built. The county assessor or property appraiser record for this address: year built, square footage (per floor if listed), bedrooms, bathrooms, lot size, construction type, and especially a building sketch with measurements (the best source for the outline).")
	lines.append("2. Its colours. The outside walls, the roof and the front door, from listing photos and street-level photos; a room's wall colour and floor where listing photos show them.")
	lines.append("3. Its street. What the house looks like from the street (storeys, garage, porch, the roof's shape), and the public places nearby (parks, schools, shops, a library): name and a short public note. Public places only.")
	lines.append("4. Listing information. " + ", ".join(LISTING_SITES) + " and other listings, current and past, including archived copies: room descriptions, room sizes, floor plans.")
	lines.append("5. Building permits from the city or county permit portal: additions, remodels, decks, finished basements, moved walls. Note the year and the work.")
	lines.append("6. The parcel or plat map from the county GIS: the lot's shape and where the house sits on it.")
	lines.append("7. For older homes: historic maps (such as Sanborn fire-insurance maps), old aerial photos, historic district records.")
	lines.append("8. The home's map location (latitude and longitude) if a record gives it, in \"location\".")
	if not files.is_empty():
		lines.append("9. The player saved these files for you to read (permit lists, sketches, photos): " + ", ".join(files))
	lines.append("")
	lines.append("Rules you must follow:")
	lines.append("- Building facts only. Never include names of owners, sellers, buyers, agents, brokers, contractors, applicants, tenants or any other person, and no phone numbers or emails. Leave prices out.")
	lines.append("- Nothing about neighbours or other private homes.")
	lines.append("- Respect every site's terms: no logins, no getting around CAPTCHAs or anti-bot blocks, no bulk downloading. If something useful needs a login or is blocked, add it to \"blocked\" with its link and exactly what the player could save by hand (for example \"the permit list as a PDF\").")
	lines.append("- Every fact names its source id (from \"sources\") and how sure you are (confidence 0 to 1). Mark guesses with low confidence and say so in the note. A colour you only saw in a photo is a fact too: name the photo's page as its source.")
	lines.append("- When sources disagree, list it in \"conflicts\" with each value and source, instead of picking silently.")
	lines.append("- Fact keys to use where they fit: " + ", ".join(FACT_KEYS) + ". Footprint in metres. Room kinds: living, kitchen, dining, bedroom, bathroom, office, laundry, garage, family, storage. Floors: 0 is the ground floor, -1 a basement.")
	lines.append("- Source kinds: " + ", ".join(SOURCE_KINDS) + ".")
	lines.append("- \"open_questions\": short questions only the player can answer (\"Is the laundry upstairs?\").")
	lines.append("")
	lines.append("Answer with one JSON object in exactly this shape and nothing else:")
	lines.append(JSON.stringify(response_schema()))
	return "\n".join(lines)
