extends RefCounted
## [LIGHT_WORLD_MAP] How your home looks from the street, from what a helper found out: the facts
## "exterior_color", "roof_color", "door_color" and "roof" (a listing's words, a street-level photo).
## Colour words become the game's own soft, lived-in colours (light_home.gd); a hex colour is used as it
## is. Without a fact your house keeps Polox's warm default. The same reading gives a room its wall
## colour when a listing describes one.
##   of(home)                 -> {"wall", "roof", "door", "roof_shape", "levels"}: only what is known
##   apply_to_street(place)   -> your house in a street place takes those (hood_builder.gd made it)
## Tags: [LIGHT_WORLD_MAP] [AI_HELPER]

const DEFAULT_WALL := "#f0dcc0"
const DEFAULT_ROOF := "#b0603e"
## Research fact -> the part of the house it colours.
const COLOUR_FACTS := {"exterior_color": "wall", "roof_color": "roof", "door_color": "door"}
## The words people and listings use for a house, as colours that sit well in the Light World. Longer
## names are matched first ("dark green" before "green", "off white" before "white").
const NAMES := {
	"white": "#f2efe8", "off white": "#efe9dc", "off-white": "#efe9dc", "ivory": "#f0ead8", "cream": "#efe6d8", "eggshell": "#eee8d8",
	"beige": "#e3d5bc", "tan": "#d4bc96", "sand": "#e0d0b0", "khaki": "#c9b98c", "taupe": "#b8a894", "greige": "#cfc8ba",
	"brown": "#8b6a4a", "dark brown": "#5e4634", "light brown": "#b08d68", "chocolate": "#5e4634", "wood": "#a8784e", "cedar": "#a8684a",
	"redwood": "#9a5a44", "brick": "#a8584a", "red brick": "#a8584a", "terracotta": "#c87a5a", "red": "#c8645c", "dark red": "#8f3f3c",
	"burgundy": "#7a3840", "maroon": "#7a3840", "barn red": "#9c4038", "orange": "#f0b57a", "peach": "#f3c9a8", "salmon": "#e8a08c",
	"pink": "#e8bfc4", "yellow": "#f0dfa0", "pale yellow": "#f3e6b0", "butter": "#f3e6b0", "gold": "#d8b860", "mustard": "#d0a850",
	"green": "#b5cfa8", "light green": "#cfe0c0", "sage": "#b8c9a8", "olive": "#8a9060", "dark green": "#4f7a54", "forest green": "#4f7a54",
	"mint": "#bfe3cf", "teal": "#6aaea6", "turquoise": "#7cc8c0", "blue": "#a9c4dc", "light blue": "#bcd6ea", "sky blue": "#a9cfee",
	"pale blue": "#c8dcec", "dark blue": "#3f5680", "navy": "#34456e", "slate": "#6f8098", "slate blue": "#6f8098", "blue grey": "#8a9cae",
	"blue gray": "#8a9cae", "grey": "#c9c9c4", "gray": "#c9c9c4", "light grey": "#dcdcd8", "light gray": "#dcdcd8", "dark grey": "#6a6c74",
	"dark gray": "#6a6c74", "charcoal": "#55575e", "silver": "#c8ccd0", "stone": "#b8b0a4", "black": "#3a3a40", "purple": "#a68ac8",
	"lavender": "#c8b8e0", "lilac": "#cdb8e0", "plum": "#7a5078",
}
## A listing's word for a roof -> the shapes hood_render.gd can draw.
const ROOF_SHAPES := {"gabled": "gabled", "gable": "gabled", "hipped": "hipped", "hip": "hipped", "pyramidal": "pyramidal",
	"pyramid": "pyramidal", "gambrel": "gambrel", "mansard": "mansard", "flat": "flat", "skillion": "skillion", "shed": "skillion"}
const FLOOR_MATERIALS: PackedStringArray = ["wood", "carpet", "tile", "vinyl", "concrete", "stone"]


## The colour in a few words ("light grey vinyl siding, white trim" -> light grey), or a hex colour as it
## is. "" when no colour is named. The first colour mentioned wins; at the same spot, the longer name.
static func colour(text: Variant) -> String:
	var raw := str(text).strip_edges()
	if raw == "":
		return ""
	if raw.begins_with("#") and raw.length() in [4, 7] and Color.html_is_valid(raw):
		return "#" + Color.html(raw).to_html(false)
	var low := " " + raw.to_lower().replace("-", " ").replace(",", " ").replace(".", " ").replace("/", " ").replace("(", " ").replace(")", " ") + " "
	var best := ""
	var best_at := -1
	var best_len := 0
	for name in NAMES:
		var at := low.find(" " + str(name).replace("-", " ") + " ")
		if at < 0:
			continue
		var n := str(name).length()
		# The colour named first; where two start at the same word, the longer ("blue grey", not "blue").
		# ("dark green" starts before the "green" inside it, so it wins by being first.)
		if best_at < 0 or at < best_at or (at == best_at and n > best_len):
			best = str(NAMES[name])
			best_at = at
			best_len = n
	return best


static func roof_shape(text: Variant) -> String:
	var low := " " + str(text).to_lower().replace("-", " ").replace(",", " ").replace(".", " ").replace("/", " ").replace("(", " ").replace(")", " ") + " "
	for word in ROOF_SHAPES:
		if low.contains(" " + str(word) + " "):
			return str(ROOF_SHAPES[word])
	return ""


static func floor_material(text: Variant) -> String:
	var low := str(text).strip_edges().to_lower()
	if low in FLOOR_MATERIALS:
		return low
	for word in ["hardwood", "laminate", "parquet"]:
		if low.contains(word):
			return "wood"
	for material in FLOOR_MATERIALS:
		if low.contains(material):
			return material
	if low.contains("lino"):
		return "vinyl"
	return ""


## What is known of the house's look: for each part, the surest fact that names a colour.
static func of(home: Dictionary) -> Dictionary:
	var out := {}
	var surest := {}
	# As many storeys on its street as the house itself has (your answer first, then the records).
	var storeys := 0
	var plan: Variant = home.get("plan")
	if plan is Dictionary and plan.get("floors") is Array:
		for f in plan.floors:
			if f is Dictionary and int(f.get("level", 0)) >= 0:
				storeys += 1
	if storeys > 0:
		out["levels"] = storeys
	var facts: Variant = home.get("facts", [])
	if not facts is Array:
		return out
	for f in facts:
		if not f is Dictionary:
			continue
		var key := str(f.get("key", ""))
		var confidence := float(f.get("confidence", 0.0))
		if COLOUR_FACTS.has(key):
			var c := colour(f.get("value", ""))
			var part := str(COLOUR_FACTS[key])
			if c != "" and confidence >= float(surest.get(part, -1.0)):
				surest[part] = confidence
				out[part] = c
		elif key == "roof":
			var shape := roof_shape(f.get("value", ""))
			if shape != "" and confidence >= float(surest.get("roof_shape", -1.0)):
				surest["roof_shape"] = confidence
				out["roof_shape"] = shape
			# "red tile roof": a roof fact can name its colour too, when no roof_color fact does better.
			var rc := colour(f.get("value", ""))
			if rc != "" and not surest.has("roof"):
				out["roof"] = rc
	return out


## Your house in a street place (its "mine" building, your front door) takes the look. Returns whether
## anything changed. Other buildings are never touched.
static func apply_to_street(place: Dictionary, look: Dictionary) -> bool:
	if look.is_empty() or not place.get("buildings") is Array:
		return false
	var changed := false
	for b in place.buildings:
		if not b is Dictionary or str(b.get("kind", "")) != "mine":
			continue
		for part in ["wall", "roof"]:
			if look.has(part) and str(b.get(part, "")) != str(look[part]):
				b[part] = str(look[part])
				changed = true
		# Its storeys, and with them its height, unless the map gave the building's own height (then the
		# stored height is not the one hood_builder.gd works out from the storeys, and it is left alone).
		var from_storeys := 1.6 + 0.9 * clampi(int(b.get("levels", 1)), 1, 4)
		if look.has("levels") and int(b.get("levels", 1)) != int(look.levels) and is_equal_approx(float(b.get("h", from_storeys)), from_storeys):
			b["levels"] = clampi(int(look.levels), 1, 6)
			b["h"] = 1.6 + 0.9 * clampi(int(look.levels), 1, 4)
			changed = true
		# The roof's shape only where the map itself didn't say (hood_builder.gd marks those "inferred").
		if look.has("roof_shape") and bool(b.get("inferred", false)) and str(b.get("roof_shape", "")) != str(look.roof_shape):
			b["roof_shape"] = str(look.roof_shape)
			changed = true
	if look.has("door") and place.get("objects") is Array:
		for o in place.objects:
			if o is Dictionary and bool(o.get("front_door", false)) and not bool(o.get("user", false)) and str(o.get("color", "")) != str(look.door):
				o["color"] = str(look.door)
				changed = true
	return changed
