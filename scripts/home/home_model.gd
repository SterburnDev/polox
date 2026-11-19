extends RefCounted
## What Polox knows about your home (my_home/home.json), and how answers and research become it:
##   {"version": 1, "address": {"text", "level": "full" | "street" | "city" | "none"},
##    "answers": {...the survey's...}, "facts": [{"key", "value", "source", "confidence", "note"}],
##    "sources": [{"id", "kind", "title", "url", "said"}], "conflicts": [{"key", "values": [{"value", "source"}], "chosen"}],
##    "rooms": [...research rooms...], "footprint": {...}, "timeline": [{"year", "date", "kind", "text", "source"}],
##    "open_questions": [{"id", "text", "key", "state": "open" | "answered" | "dismissed"}],
##    "blocked": [{"what", "url", "why"}], "neighbourhood": [...public places...], "plan": {...layout_builder...},
##    "edits": [...your own changes, which win over research (Phase 31)...], "helper": "", "researched": ""}
## Research is cleaned before it's kept: known fields only, and never a person's name, email or phone
## number (building facts only).

const ResearchPrompt := preload("res://scripts/home/research_prompt.gd")
const HomeLook := preload("res://scripts/home/home_look.gd")

const VERSION := 1
## Keys that name people: dropped wherever they appear in a helper's answer.
const PERSON_KEYS: PackedStringArray = ["owner", "owners", "owner_name", "seller", "sellers", "buyer", "buyers", "agent", "agents",
	"listing_agent", "broker", "realtor", "contractor", "contractors", "applicant", "applicants", "tenant", "tenants",
	"occupant", "occupants", "resident", "residents", "email", "phone", "person", "people", "price", "sale_price"]
const ROLE_WORDS := "owners? of record|owned by|sold by|bought by|owners?|sellers?|buyers?|agents?|brokers?|realtors?|contractors?|applicants?|tenants?|occupants?|residents?|listed by|listing courtesy of|courtesy of|presented by|built by|issued to|filed by"


static func empty() -> Dictionary:
	return {"version": VERSION, "address": {"text": "", "level": "none"}, "answers": {}, "facts": [], "sources": [], "conflicts": [],
		"rooms": [], "footprint": {}, "timeline": [], "open_questions": [], "blocked": [], "neighbourhood": [], "plan": {}, "edits": [],
		"helper": "", "researched": ""}


# --- Keeping people out ---------------------------------------------------------------------------

static var _re_role: RegEx
static var _re_email: RegEx
static var _re_phone: RegEx


## A line of text with any person's name after a role word ("Owner: Jane Doe", "listed by Sam Lee"),
## emails and phone numbers taken out.
static func scrub_text(s: String) -> String:
	if _re_role == null:
		# A name: capitalised words or initials ("Jane Q. Sample", "Bob Roofer & Sons"), stopping at a
		# sentence's end ("Owner: Jane Doe. Built 1962." keeps "Built 1962.").
		var tok := "(?:[A-Z][a-z'’\\-]+|[A-Z]\\.|[A-Z]{2,}|&|and)"
		_re_role = RegEx.create_from_string("(?i)\\b(" + ROLE_WORDS + ")\\b\\s*[:\\-–]?\\s*(?-i)(" + tok + "(?:[ \\t]+" + tok + "){0,4})")
		_re_email = RegEx.create_from_string("[\\w.+\\-]+@[\\w\\-]+\\.[\\w.]+")
		_re_phone = RegEx.create_from_string("\\(?\\b\\d{3}\\)?[\\s.\\-]\\d{3}[\\s.\\-]\\d{4}\\b")
	var out := _re_email.sub(s, "", true)
	out = _re_phone.sub(out, "", true)
	out = _re_role.sub(out, "$1 (name left out)", true)
	return out.strip_edges()


## A helper's answer, scrubbed: person-ish keys dropped at every level, every string scrubbed.
static func scrub(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			if str(k).to_lower() in PERSON_KEYS:
				continue
			out[k] = scrub(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x): return scrub(x))
	if v is String:
		return scrub_text(v)
	return v


# --- Cleaning a helper's answer ---------------------------------------------------------------------

static func _arr(d: Dictionary, k: String) -> Array:
	return d.get(k, []) if d.get(k) is Array else []


static func _num(v: Variant, lo: float, hi: float) -> float:
	var f := float(v) if (v is float or v is int or (v is String and str(v).is_valid_float())) else 0.0
	return clampf(f, lo, hi)


## Known fields only, sensible ranges, people taken out. `raw` is the helper's JSON.
static func clean_research(raw: Dictionary) -> Dictionary:
	var r: Dictionary = scrub(raw)
	var out := {"address_found": bool(r.get("address_found", false)), "summary": str(r.get("summary", "")).left(600),
		"facts": [], "footprint": {}, "rooms": [], "permits": [], "history": [], "conflicts": [], "sources": [], "blocked": [],
		"open_questions": [], "neighbourhood": []}
	var ids := {}
	for s in _arr(r, "sources"):
		if s is Dictionary and str(s.get("id", "")) != "":
			var kind := str(s.get("kind", "other"))
			out.sources.append({"id": str(s.id).left(40), "kind": kind if kind in ResearchPrompt.SOURCE_KINDS else "other",
				"title": str(s.get("title", "")).left(160), "url": _url(str(s.get("url", ""))), "said": str(s.get("said", "")).left(500)})
			ids[str(s.id)] = true
	for f in _arr(r, "facts"):
		if f is Dictionary and str(f.get("key", "")) != "":
			out.facts.append({"key": str(f.key).to_lower().left(40), "value": f.get("value", ""), "source": str(f.get("source", "")),
				"confidence": _num(f.get("confidence", 0.5), 0.0, 1.0), "note": str(f.get("note", "")).left(300)})
	var fp: Variant = r.get("footprint")
	if fp is Dictionary and _num(fp.get("width_m", 0), 0, 200) > 0.0:
		out.footprint = {"width_m": _num(fp.width_m, 3.0, 60.0), "depth_m": _num(fp.get("depth_m", fp.width_m), 3.0, 60.0),
			"shape_note": str(fp.get("shape_note", "")).left(200), "source": str(fp.get("source", ""))}
	for rm in _arr(r, "rooms"):
		if rm is Dictionary and str(rm.get("kind", "")) != "":
			var room := {"kind": str(rm.kind).to_lower(), "name": str(rm.get("name", "")).left(60), "floor": clampi(int(_num(rm.get("floor", 0), -1, 3)), -1, 3),
				"width_m": _num(rm.get("width_m", 0), 0, 30), "depth_m": _num(rm.get("depth_m", 0), 0, 30), "position": str(rm.get("position", "")), "source": str(rm.get("source", ""))}
			# What a listing's photos or words say of the room itself (kept only when Polox can read it).
			if HomeLook.colour(rm.get("wall_color", "")) != "":
				room["wall_color"] = str(rm.wall_color).left(40)
			if HomeLook.floor_material(rm.get("floor_material", "")) != "":
				room["floor_material"] = HomeLook.floor_material(rm.floor_material)
			out.rooms.append(room)
	for p in _arr(r, "permits"):
		if p is Dictionary and str(p.get("work", "")) != "":
			out.permits.append({"year": int(_num(p.get("year", 0), 0, 2100)), "date": str(p.get("date", "")).left(20), "work": str(p.work).left(240), "source": str(p.get("source", ""))})
	for h in _arr(r, "history"):
		if h is Dictionary and str(h.get("text", "")) != "":
			out.history.append({"year": int(_num(h.get("year", 0), 0, 2100)), "text": str(h.text).left(300), "source": str(h.get("source", ""))})
	for c in _arr(r, "conflicts"):
		if c is Dictionary and _arr(c, "values").size() >= 2:
			out.conflicts.append({"key": str(c.get("key", "")), "values": _arr(c, "values").filter(func(v): return v is Dictionary).map(func(v): return {"value": v.get("value", ""), "source": str(v.get("source", ""))})})
	for b in _arr(r, "blocked"):
		if b is Dictionary and str(b.get("what", "")) != "":
			out.blocked.append({"what": str(b.what).left(200), "url": _url(str(b.get("url", ""))), "why": str(b.get("why", "")).left(200)})
	for q in _arr(r, "open_questions"):
		if str(q).strip_edges() != "":
			out.open_questions.append(str(q).left(160))
	var loc: Variant = r.get("location")
	if preload("res://scripts/home/map_validation.gd").coordinates(loc):
		out["location"] = {"lat": float(loc.lat), "lon": float(loc.get("lon", 0.0)), "source": str(loc.get("source", ""))}
	for n in _arr(r, "neighbourhood"):
		if n is Dictionary and str(n.get("name", "")) != "":
			out.neighbourhood.append({"name": str(n.name).left(80), "kind": str(n.get("kind", "other")), "note": str(n.get("note", "")).left(200), "source": str(n.get("source", ""))})
	return out


static func _url(u: String) -> String:
	return u.left(400) if u.begins_with("https://") or u.begins_with("http://") else ""


# --- Putting it together ----------------------------------------------------------------------------

## The facts the floor plan needs, by key (research only; your answers are read separately and win).
static func facts_by_key(home: Dictionary) -> Dictionary:
	var out := {}
	var best := {}
	for f in _arr(home, "facts"):
		var k := str(f.get("key", ""))
		if float(f.get("confidence", 0.0)) >= float(best.get(k, -1.0)):
			best[k] = float(f.get("confidence", 0.0))
			out[k] = f.get("value")
	var mapped := {}
	if out.has("floors"):
		mapped["floors"] = int(_num(out.floors, 0, 4))
	if out.has("sqft"):
		mapped["sqft"] = _num(out.sqft, 0, 20000)
	if out.has("bedrooms"):
		mapped["bedrooms"] = int(_num(out.bedrooms, 0, 12))
	if out.has("bathrooms"):
		mapped["bathrooms"] = int(ceil(_num(out.bathrooms, 0, 12)))
	if out.has("basement"):
		mapped["basement"] = str(out.basement).to_lower() in ["true", "yes", "1", "finished", "unfinished", "full", "partial"]
	var fp: Dictionary = home.get("footprint", {}) if home.get("footprint") is Dictionary else {}
	if float(fp.get("width_m", 0.0)) > 0.0:
		mapped["footprint_w"] = float(fp.width_m)
		mapped["footprint_d"] = float(fp.get("depth_m", fp.width_m))
	elif out.has("footprint_w_m") and out.has("footprint_d_m"):
		mapped["footprint_w"] = _num(out.footprint_w_m, 0, 60)
		mapped["footprint_d"] = _num(out.footprint_d_m, 0, 60)
	var rooms: Array = []
	for rm in _arr(home, "rooms"):
		var found := {"kind": str(rm.kind), "floor": int(rm.get("floor", 0)), "area": float(rm.get("width_m", 0)) * float(rm.get("depth_m", 0))}
		if HomeLook.colour(rm.get("wall_color", "")) != "":
			found["wall"] = HomeLook.colour(rm.wall_color)
		if HomeLook.floor_material(rm.get("floor_material", "")) != "":
			found["floor_material"] = HomeLook.floor_material(rm.floor_material)
		if room_name(rm.get("name", "")) != "":
			found["name"] = room_name(rm.name)
		rooms.append(found)
	if not rooms.is_empty():
		mapped["rooms"] = rooms
	return mapped


## A home from the survey answers and (optionally) a cleaned research answer. Conflicts between your
## answers and the records are shown (your answers are used); so are conflicts between sources.
static func make(answers: Dictionary, research: Dictionary = {}, helper: String = "") -> Dictionary:
	var home := empty()
	var addr := str(answers.get("address", "")).strip_edges()
	home.address = {"text": addr, "level": str(answers.get("address_level", "full" if addr != "" else "none"))}
	home.answers = answers.duplicate(true)
	home.erase("address_text")
	home.helper = helper
	if not research.is_empty():
		home.facts = research.get("facts", []).duplicate(true)
		home.sources = research.get("sources", []).duplicate(true)
		home.conflicts = research.get("conflicts", []).duplicate(true)
		home.rooms = research.get("rooms", []).duplicate(true)
		home.footprint = (research.get("footprint", {}) as Dictionary).duplicate(true)
		if research.get("location") is Dictionary:
			home["location"] = (research.location as Dictionary).duplicate()
		home.blocked = research.get("blocked", []).duplicate(true)
		home.neighbourhood = research.get("neighbourhood", []).duplicate(true)
		home.researched = Time.get_datetime_string_from_system(false, false)
		var n := 0
		for q in research.get("open_questions", []):
			n += 1
			home.open_questions.append({"id": "q%d" % n, "text": str(q), "key": "", "kind": "free", "state": "open", "source": "research"})
		_source_conflicts(home)
		_answer_conflicts(home)
	home.timeline = timeline(home, research)
	home.sources.append({"id": "you", "kind": "user", "title": "Your answers (the survey)", "url": "", "said": ""})
	return home


## Facts that say different things for the same key.
static func _source_conflicts(home: Dictionary) -> void:
	var by := {}
	for f in home.facts:
		var k := str(f.key)
		if not by.has(k):
			by[k] = []
		by[k].append(f)
	for k in by:
		var vals := {}
		for f in by[k]:
			vals[str(f.value)] = str(f.source)
		if vals.size() >= 2 and not (home.conflicts as Array).any(func(c): return str(c.key) == k):
			var values: Array = []
			for v in vals:
				values.append({"value": v, "source": vals[v]})
			home.conflicts.append({"key": k, "values": values})


## Where your answers and the records disagree (floors, bedrooms, bathrooms): your answer is used.
static func _answer_conflicts(home: Dictionary) -> void:
	var facts := facts_by_key(home)
	var a: Dictionary = home.answers
	var rooms: Dictionary = a.get("rooms", {}) if a.get("rooms") is Dictionary else {}
	var pairs := [["floors", int(a.get("floors", 0)), int(facts.get("floors", 0))],
		["bedrooms", int(rooms.get("bedroom", 0)), int(facts.get("bedrooms", 0))],
		["bathrooms", int(rooms.get("bathroom", 0)), int(facts.get("bathrooms", 0))]]
	for p in pairs:
		if int(p[1]) > 0 and int(p[2]) > 0 and int(p[1]) != int(p[2]):
			home.conflicts.append({"key": str(p[0]), "values": [{"value": str(p[1]), "source": "you"}, {"value": str(p[2]), "source": "records"}], "chosen": "you"})


## The house's history, oldest first: built, permits, the records' history, then what you told the survey.
static func timeline(home: Dictionary, research: Dictionary) -> Array:
	var t: Array = []
	var facts := {}
	for f in home.facts:
		facts[str(f.key)] = f
	var a: Dictionary = home.answers
	var built := int(a.get("year_built", 0))
	var built_src := "you"
	if built <= 0 and facts.has("year_built"):
		built = int(_num(facts.year_built.value, 0, 2100))
		built_src = str(facts.year_built.source)
	if built > 0:
		t.append({"year": built, "date": "", "kind": "built", "text": "The house was built.", "source": built_src})
	for p in research.get("permits", []):
		t.append({"year": int(p.get("year", 0)), "date": str(p.get("date", "")), "kind": "permit", "text": str(p.work), "source": str(p.get("source", ""))})
	for h in research.get("history", []):
		t.append({"year": int(h.get("year", 0)), "date": "", "kind": "history", "text": str(h.text), "source": str(h.get("source", ""))})
	for k in [["renovations", "renovation"], ["used_to_be", "used_to_be"], ["memory", "memory"]]:
		var text := str(a.get(k[0], "")).strip_edges()
		if text != "":
			t.append({"year": 0, "date": "", "kind": str(k[1]), "text": text, "source": "you"})
	t.sort_custom(func(x, y): return (int(x.year) if int(x.year) > 0 else 9999) < (int(y.year) if int(y.year) > 0 else 9999))
	return t


## A found room's own name, short enough for a door plate: "Dining room (the first kitchen)" -> "Dining room".
static func room_name(text: Variant) -> String:
	var plain := str(text).replace("\n", " ").strip_edges()
	var note := plain.find("(")
	if note > 0:
		plain = plain.left(note).strip_edges()
	return plain.left(24).strip_edges()


## Sources by id, for the sketch panel.
static func source(home: Dictionary, id: String) -> Dictionary:
	for s in _arr(home, "sources"):
		if str(s.get("id", "")) == id:
			return s
	return {}
