extends RefCounted
## "Look again" (only when you press it, after the same "Look it up?" question): the research runs
## again, and only what's different from last time is shown (a new permit, a new listing, a fact that
## changed, a new public place nearby) for you to keep or leave, one by one. Keeping merges what you
## ticked into your home: new sources, facts and history, the house rebuilt with your own edits still on
## top. A snapshot comes first, so Undo can put the whole home back.

const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const HomeEdit := preload("res://scripts/home/home_edit.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const ResearchPrompt := preload("res://scripts/home/research_prompt.gd")

## Whole fields of the answer that replace the home's own when kept (each one a single choice).
const FIELDS: PackedStringArray = ["footprint", "location", "rooms", "conflicts"]


static func _key_source(s: Dictionary) -> String:
	return str(s.get("url", "")) if str(s.get("url", "")) != "" else str(s.get("title", "")).to_lower()


## The stable id of one proposed change (what the review's checkboxes and keep() agree on).
static func item_id(kind: String, v: Variant) -> String:
	match kind:
		"sources": return "source:" + _key_source(v)
		"facts": return "fact:%s|%s" % [str(v.key), str(v.value)]
		"permits": return "permit:%d|%s" % [int(v.get("year", 0)), str(v.get("work", "")).to_lower()]
		"history": return "history:" + str(v.get("text", "")).to_lower()
		"neighbourhood": return "near:" + str(v.get("name", "")).to_lower()
		"questions": return "question:" + str(v).sha256_text().left(16)
	return "field:" + kind


## What's new in `fresh` (a cleaned research answer) compared with `old` (the last one kept).
## {"sources": [...], "facts": [...], "permits": [...], "history": [...], "neighbourhood": [...],
##  "questions": [...], "fields": [...], "items": [{id, kind, label}], "lines": ["..."]}
static func diff(old: Dictionary, fresh: Dictionary) -> Dictionary:
	var out := {"sources": [], "facts": [], "permits": [], "history": [], "neighbourhood": [], "questions": [], "fields": [], "items": [], "lines": []}
	var seen := {}
	for s in old.get("sources", []):
		seen[_key_source(s)] = true
	for s in fresh.get("sources", []):
		if not seen.has(_key_source(s)):
			_add(out, "sources", s, "A new source: %s" % str(s.get("title", "")))
	var old_facts := {}
	for f in old.get("facts", []):
		old_facts["%s|%s" % [str(f.key), str(f.value)]] = true
	var old_keys := {}
	var old_values := {}
	for f in old.get("facts", []):
		old_keys[str(f.key)] = str(f.value)
		old_values[str(f.key)] = f.value
	for f in fresh.get("facts", []):
		if not old_facts.has("%s|%s" % [str(f.key), str(f.value)]):
			var label := "%s: %s" % [ResearchPrompt.fact_name(f.key), ResearchPrompt.fact_value(f.key, f.value)]
			if old_keys.has(str(f.key)):
				label = "%s: now %s (it was %s)" % [ResearchPrompt.fact_name(f.key), ResearchPrompt.fact_value(f.key, f.value), ResearchPrompt.fact_value(f.key, old_values[str(f.key)])]
			_add(out, "facts", f, label)
	var old_permits := {}
	for p in old.get("permits", []):
		old_permits[item_id("permits", p)] = true
	for p in fresh.get("permits", []):
		if not old_permits.has(item_id("permits", p)):
			_add(out, "permits", p, "A permit%s: %s" % [(" (%d)" % int(p.year)) if int(p.get("year", 0)) > 0 else "", str(p.work)])
	var old_hist := {}
	for h in old.get("history", []):
		old_hist[str(h.get("text", "")).to_lower()] = true
	for h in fresh.get("history", []):
		if not old_hist.has(str(h.get("text", "")).to_lower()):
			_add(out, "history", h, "History: %s" % str(h.text))
	var old_places := {}
	for n in old.get("neighbourhood", []):
		old_places[str(n.get("name", "")).to_lower()] = true
	for n in fresh.get("neighbourhood", []):
		if not old_places.has(str(n.get("name", "")).to_lower()):
			_add(out, "neighbourhood", n, "Nearby: %s%s" % [str(n.name), (" (%s)" % str(n.note)) if str(n.get("note", "")) != "" else ""])
	var old_questions := {}
	for q in old.get("open_questions", []):
		old_questions[str(q)] = true
	for q in fresh.get("open_questions", []):
		if not old_questions.has(str(q)):
			_add(out, "questions", q, "A question for you: %s" % str(q))
	for field in FIELDS:
		if fresh.has(field) and not fresh[field].is_empty() and _canonical(fresh[field]) != _canonical(old.get(field, null)):
			_add(out, "fields", field, _field_label(field, fresh[field]), field)
	return out


static func _add(out: Dictionary, kind: String, value: Variant, label: String, id_kind: String = "") -> void:
	(out[kind] as Array).append(value)
	var id := item_id(id_kind if id_kind != "" else kind, value)
	(out.items as Array).append({"id": id, "kind": kind, "label": label})
	(out.lines as Array).append(label)


## Plain words for a whole-field change (never raw JSON in front of the player).
static func _field_label(field: String, v: Variant) -> String:
	match field:
		"footprint":
			return "The house's outline: %s x %s m" % [_fmt(v.get("width_m", "?")), _fmt(v.get("depth_m", "?"))]
		"location":
			return "Its place on the map (%.5f, %.5f)" % [float(v.get("lat", 0.0)), float(v.get("lon", 0.0))]
		"rooms":
			var kinds := PackedStringArray()
			for r in v:
				if r is Dictionary and str(r.get("kind", "")) != "" and kinds.size() < 6:
					kinds.append(str(r.kind))
			return "The rooms: %d (%s)" % [(v as Array).size(), ", ".join(kinds)]
		"conflicts":
			return "%d thing%s the sources disagree about" % [(v as Array).size(), "" if (v as Array).size() == 1 else "s"]
	return field.replace("_", " ").capitalize()


static func _canonical(value: Variant) -> String:
	# JSON reload represents integers as floats; that is not a new observation.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)


static func _fmt(v: Variant) -> String:
	if v is float and is_equal_approx(v, round(v)):
		return str(int(v))
	return str(v)


static func is_empty(d: Dictionary) -> bool:
	return (d.get("lines", []) as Array).is_empty()


## Keeps what's new: into the home (sources, facts, conflicts, timeline, nearby places), the house rebuilt
## with your edits on top, the answer saved as the newest research. Snapshot first (HomeStore.last_snapshot
## names it, for Undo). `accepted`: the item ids you ticked (null = all of them). `extra`: more files for
## the same transaction (the helper request's closing record).
static func keep(fresh: Dictionary, d: Dictionary, accepted: Variant = null, extra: Dictionary = {}) -> bool:
	var home := HomeStore.load_home()
	if home.is_empty():
		return false
	var take := func(kind: String, v: Variant) -> bool: return accepted == null or item_id(kind, v) in accepted
	var source_ids := {}
	for source in home.get("sources", []):
		source_ids[str(source.get("id", ""))] = _key_source(source)
	for source in fresh.get("sources", []):
		var id := str(source.get("id", ""))
		if source_ids.has(id) and source_ids[id] != _key_source(source):
			HomeStore.last_error = "A source identifier now names a different source. Repair the response with unique source identifiers."
			return false
	for source in d.get("sources", []):
		if take.call("sources", source):
			source_ids[str(source.get("id", ""))] = _key_source(source)
	var chosen := {}
	for kind in ["facts", "permits", "history", "neighbourhood"]:
		chosen[kind] = d.get(kind, []).filter(func(v): return take.call(kind, v))
	for field in d.get("fields", []):
		if take.call(field, field):
			chosen[field] = fresh[field]
	if ResearchPrompt._source_references(chosen, source_ids, "$") != "":
		HomeStore.last_error = "Keep the source for each selected change too, or untick the change."
		return false
	if HomeStore.snapshot("before_look_again") == "":
		return false
	(home.sources as Array).append_array(d.get("sources", []).filter(func(s): return take.call("sources", s)))
	(home.facts as Array).append_array(d.get("facts", []).filter(func(f): return take.call("facts", f)))
	(home.neighbourhood as Array).append_array(d.get("neighbourhood", []).filter(func(n): return take.call("neighbourhood", n)))
	var tl: Array = home.get("timeline", [])
	for p in d.get("permits", []):
		if take.call("permits", p):
			tl.append({"year": int(p.get("year", 0)), "date": str(p.get("date", "")), "kind": "permit", "text": str(p.work), "source": str(p.get("source", "")), "new": true})
	for h in d.get("history", []):
		if take.call("history", h):
			tl.append({"year": int(h.get("year", 0)), "date": "", "kind": "history", "text": str(h.text), "source": str(h.get("source", "")), "new": true})
	tl.sort_custom(func(x, y): return (int(x.year) if int(x.year) > 0 else 9999) < (int(y.year) if int(y.year) > 0 else 9999))
	home["timeline"] = tl
	if fresh.get("footprint") is Dictionary and not (fresh.footprint as Dictionary).is_empty() and take.call("footprint", "footprint"):
		home["footprint"] = fresh.footprint
	if fresh.get("location") is Dictionary and not fresh.location.is_empty() and take.call("location", "location"):
		home["location"] = fresh.location
	if fresh.get("rooms") is Array and not fresh.rooms.is_empty() and take.call("rooms", "rooms"):
		home["rooms"] = fresh.rooms.duplicate(true)
	for question in fresh.get("open_questions", []):
		if take.call("questions", question) and not (home.open_questions as Array).any(func(q): return str(q.get("text", "")) == str(question)):
			home.open_questions.append({"id": "research_" + str(question).sha256_text().left(16), "text": str(question), "key": "", "kind": "free", "state": "open", "source": "research"})
	if take.call("conflicts", "conflicts"):
		home["conflicts"] = fresh.get("conflicts", []).duplicate(true)
	else:
		# Kept as they were, minus the answer-vs-records ones, which are worked out again just below.
		home["conflicts"] = (home.get("conflicts", []) as Array).filter(func(c): return not (c is Dictionary and str(c.get("chosen", "")) == "you"))
	HomeModel._source_conflicts(home)
	HomeModel._answer_conflicts(home)
	home["researched"] = Time.get_datetime_string_from_system(false, false)
	home["plan"] = HomeEdit.rebuild(home)
	var batch := HomePlaces.batch_files(HomePlaces.build(home.plan))
	var writes := HomeStore.home_writes(home)
	writes.merge(batch.writes, true)
	writes.merge(extra, true)
	# Only accepted observations become the comparison baseline. Rejected items must
	# remain available next time, and Undo must restore this baseline with the home.
	var baseline := HomeStore.last_research().duplicate(true)
	for kind in ["sources", "facts", "permits", "history", "neighbourhood", "questions"]:
		var key: String = "open_questions" if kind == "questions" else kind
		var values: Array = baseline.get(key, []).duplicate(true)
		for value in d.get(kind, []):
			if take.call(kind, value):
				values.append(value)
		baseline[key] = values
	for field in d.get("fields", []):
		if take.call(field, field):
			baseline[field] = fresh[field].duplicate(true)
	writes[HomeStore.RESEARCH_FILE] = baseline
	if str(batch.entry) == "" or not HomeStore.apply_batch(writes, batch.removals):
		return false
	return true
