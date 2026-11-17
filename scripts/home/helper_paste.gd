extends RefCounted
## Tidying a reply pasted from an AI chat, before the strict check (helper_request.gd prepare()). Chat AIs
## wrap the JSON in a sentence or a code block, add a field of their own, write a number as text, change
## an option's capitals, leave a comma before a bracket or skip the outer envelope. A reply like that used to
## be refused outright, so copy/paste rarely worked. tidy() finds the one JSON object in the reply, fixes only
## those slips and lists what it did (as counts: it never repeats the reply's words), and the result still goes
## through the same strict check as any helper. The player sees the list and taps to use it.
##   Never fixed: a reply for another prompt, another Polox version, a fact without its source, a value out of
##   bounds. Fields Polox doesn't use are left out unread (a person's name, say, never gets stored).
## Tags: [AI_HELPER]

const Json := preload("res://scripts/home/helper_json.gd")
const Request := preload("res://scripts/home/helper_request.gd")
const NUMERIC_FACTS: PackedStringArray = ["year_built", "sqft", "floors", "bedrooms", "bathrooms", "lot_sqft", "footprint_w_m", "footprint_d_m"]

## {ok, text (the tidied envelope as JSON), notes: [plain lines], error}. `reuse`: the player chose to use a
## house lookup made for an earlier prompt with this one (the old prompt's identity is set aside).
static func tidy(text: String, request: Dictionary, reuse: bool = false) -> Dictionary:
	if text.strip_edges() == "":
		return _fail("Paste the AI's reply first.")
	if text.to_utf8_buffer().size() > Json.MAX_BYTES:
		return _fail("That reply is over 512 KiB.")
	var notes: Array = []
	var found := find_object(text)
	if not bool(found.ok):
		return found
	if bool(found.trimmed):
		notes.append("took the JSON out of the AI's message")
	if bool(found.repaired):
		notes.append("fixed quote marks or commas")
	var value: Dictionary = found.value
	var envelope := {}
	if value.has("result"):
		envelope = value
		if value.has("schema_version") and not _same_number(value.schema_version, Request.VERSION):
			return _fail("This reply was made for a different Polox version. Make a new prompt and ask again.")
		if value.has("task") and str(value.task) != str(request.get("task", "")):
			return _fail("This reply answers a different kind of request. Paste it where it belongs, or ask again.")
		if not reuse and value.has("request_id") and str(value.request_id).strip_edges().to_lower() != str(request.get("request_id", "")):
			return _fail("This reply is for an older prompt. Use the latest prompt, or ask again.")
		if not value.has("request_id") or not value.has("base_revision") or not value.has("schema_version") or not value.has("task"):
			notes.append("filled in this prompt's details")
	elif _looks_like_result(value, str(request.get("task", ""))):
		envelope = {"result": value}
		notes.append("added this prompt's details around the AI's answer")
	else:
		return _fail("Polox couldn't find its answer in that reply. Copy the AI's whole reply, or use Copy repair prompt.")
	if not envelope.get("result") is Dictionary:
		return _fail("The reply's result isn't a JSON object.")
	var schema: Dictionary = Request.schema(request)
	var result_schema: Dictionary = schema.properties.result
	var counts := {"dropped": 0, "coerced": 0, "nulls": 0}
	var result: Variant = _fit(envelope.result, result_schema, counts)
	if str(request.get("task", "")) == "research":
		result = _research_defaults(result, notes)
	if int(counts.dropped) > 0:
		notes.append("left out %d field%s Polox doesn't use (not stored)" % [counts.dropped, "" if int(counts.dropped) == 1 else "s"])
	if int(counts.coerced) > 0:
		notes.append("read %d value%s written as text (numbers, yes/no, capitals)" % [counts.coerced, "" if int(counts.coerced) == 1 else "s"])
	if int(counts.nulls) > 0:
		notes.append("skipped %d empty value%s" % [counts.nulls, "" if int(counts.nulls) == 1 else "s"])
	var tidy_envelope := {"schema_version": Request.VERSION, "request_id": str(request.get("request_id", "")),
		"base_revision": str(request.get("base_revision", "")), "task": str(request.get("task", "")), "result": result}
	return {"ok": true, "text": JSON.stringify(tidy_envelope), "notes": notes, "error": "", "result": result}


## The one JSON object in a reply: the whole text, a fenced block among the words, or the outermost {...}.
## {ok, value, trimmed, repaired, error}. More than one candidate object is refused (which would it be?).
static func find_object(text: String) -> Dictionary:
	var body := text.strip_edges()
	var candidates: Array = []
	var direct := _parse_loose(body)
	if direct.value is Dictionary:
		return {"ok": true, "value": direct.value, "trimmed": false, "repaired": bool(direct.repaired), "error": ""}
	# Fenced blocks (```json ... ``` or ``` ... ```) anywhere in the message.
	var re := RegEx.create_from_string("```[a-zA-Z]*[ \\t]*\\r?\\n([\\s\\S]*?)```")
	for m in re.search_all(body):
		var p := _parse_loose(m.get_string(1).strip_edges())
		if p.value is Dictionary:
			candidates.append(p)
	if candidates.is_empty():
		# Balanced {...} objects in the text, outside strings.
		for span in _object_spans(body):
			var p := _parse_loose(body.substr(span.x, span.y - span.x))
			if p.value is Dictionary and not (p.value as Dictionary).is_empty():
				candidates.append(p)
	if candidates.is_empty():
		return _fail("No JSON object was found in that reply. Copy the AI's whole reply, or use Copy repair prompt.")
	if candidates.size() > 1:
		return _fail("That reply holds more than one JSON object. Paste just the one with the answer.")
	return {"ok": true, "value": candidates[0].value, "trimmed": true, "repaired": bool(candidates[0].repaired), "error": ""}


## Parses JSON; on failure, tries again with typographic quotes made plain and trailing commas removed.
static func _parse_loose(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) == OK:
		return {"value": j.data, "repaired": false}
	# Repair syntax only. Commas and typographic quotes inside a normal JSON
	# string are the player's content, even when another part needs repair.
	var fixed := ""
	var closing_quote := ""
	var escaped := false
	for i in text.length():
		var c := text[i]
		if closing_quote != "":
			if escaped:
				fixed += c
				escaped = false
			elif c == "\\":
				fixed += c
				escaped = true
			elif c == closing_quote:
				fixed += "\""
				closing_quote = ""
			else:
				fixed += c
		elif c == "\"" or c == "“":
			closing_quote = "”" if c == "“" else "\""
			fixed += "\""
		elif c == ",":
			var next := i + 1
			while next < text.length() and text[next] in [" ", "\t", "\r", "\n"]:
				next += 1
			if next >= text.length() or not text[next] in ["}", "]"]:
				fixed += c
		else:
			fixed += c
	if fixed != text and j.parse(fixed) == OK:
		return {"value": j.data, "repaired": true}
	return {"value": null, "repaired": false}


## Top-level {...} spans (start, end) in text, skipping braces inside strings.
static func _object_spans(text: String) -> Array:
	var spans: Array = []
	var depth := 0
	var start := -1
	var closing_quote := ""
	var escaped := false
	for i in text.length():
		var c := text[i]
		if closing_quote != "":
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == closing_quote:
				closing_quote = ""
			continue
		if depth > 0 and (c == "\"" or c == "“"):
			closing_quote = "”" if c == "“" else "\""
		elif c == "{":
			if depth == 0:
				start = i
			depth += 1
		elif c == "}" and depth > 0:
			depth -= 1
			if depth == 0 and start >= 0:
				spans.append(Vector2i(start, i + 1))
				start = -1
	return spans


static func _looks_like_result(value: Dictionary, task: String) -> bool:
	if task == "words":
		return value.has("changes")
	return value.has("facts") or value.has("sources") or value.has("address_found") or value.has("rooms")


## Fits a value to its schema: unknown fields out (counted, unread), numbers and yes/no written as text
## read as such, options matched regardless of capitals, empty (null) optional values skipped. Anything
## else is left exactly as it was, for the strict check to judge.
static func _fit(value: Variant, schema: Dictionary, counts: Dictionary) -> Variant:
	var types: Variant = schema.get("type", [])
	if types is String:
		types = [types]
	if value is Dictionary and schema.get("properties") is Dictionary:
		var out := {}
		for key in value:
			if not (schema.properties as Dictionary).has(key):
				counts.dropped = int(counts.dropped) + 1
				continue
			if value[key] == null and not key in schema.get("required", []):
				counts.nulls = int(counts.nulls) + 1
				continue
			out[key] = _fit(value[key], schema.properties[key], counts)
		return out
	if value is Array and schema.get("items") is Dictionary:
		var arr: Array = []
		for item in value:
			if item == null:
				counts.nulls = int(counts.nulls) + 1
				continue
			arr.append(_fit(item, schema.items, counts))
		return arr
	if value is String and ("number" in types or "integer" in types) and not "string" in types:
		var t := (value as String).strip_edges().replace(",", "")
		if t.is_valid_float():
			counts.coerced = int(counts.coerced) + 1
			return int(t.to_float()) if "integer" in types and t.to_float() == floor(t.to_float()) else t.to_float()
	if value is String and "boolean" in types and not "string" in types:
		var b := (value as String).strip_edges().to_lower()
		if b in ["true", "yes"]:
			counts.coerced = int(counts.coerced) + 1
			return true
		if b in ["false", "no"]:
			counts.coerced = int(counts.coerced) + 1
			return false
	if value is String and schema.get("enum") is Array:
		for option in schema.enum:
			if option is String and option != value and (option as String).to_lower() == (value as String).strip_edges().to_lower():
				counts.coerced = int(counts.coerced) + 1
				return option
	return value


## A research answer missing its required lists or flag: empty lists, and "found" when it has facts. A fact
## that is a number by nature (the year built, the floor area...) written as text is read as a number.
static func _research_defaults(result: Variant, notes: Array) -> Variant:
	if not result is Dictionary:
		return result
	var r: Dictionary = result
	for f in (r.get("facts", []) if r.get("facts") is Array else []):
		if f is Dictionary and str(f.get("key", "")) in NUMERIC_FACTS and f.get("value") is String:
			var t := (f.value as String).strip_edges().replace(",", "")
			if t.is_valid_float():
				f["value"] = int(t.to_float()) if t.to_float() == floor(t.to_float()) else t.to_float()
	var filled := false
	for key in ["facts", "sources"]:
		if not r.has(key):
			r[key] = []
			filled = true
	if not r.has("address_found") and r.facts is Array:
		r["address_found"] = not (r.facts as Array).is_empty()
		filled = true
	if filled:
		notes.append("added the empty lists the answer left out")
	return r


static func _same_number(a: Variant, b: Variant) -> bool:
	return (a is int or a is float) and is_equal_approx(float(a), float(b))


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "text": "", "notes": [], "error": message}
