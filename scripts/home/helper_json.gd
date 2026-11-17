extends RefCounted
## Data-only boundary shared by manual imports and provider adapters. Error paths never echo values.
## Tags: [AI_HELPER]
const MAX_BYTES := 524288
const MAX_ITEMS := 256
const MAX_TEXT := 8192


static func parse(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return failure("Response exceeds 512 KiB.")
	var body := text.strip_edges()
	if body.begins_with("```"):
		var newline := body.find("\n")
		if newline < 0 or not body.ends_with("```") or not body.left(newline).strip_edges() in ["```", "```json"]:
			return failure("Use plain JSON or one enclosing JSON fence.")
		body = body.substr(newline + 1, body.length() - newline - 4).strip_edges()
	var parser := JSON.new()
	if parser.parse(body) != OK:
		return failure("Invalid JSON near line %d. Return one JSON object without commentary." % parser.get_error_line())
	if not parser.data is Dictionary:
		return failure("Response must be one JSON object.")
	return {"ok": true, "value": parser.data, "error": ""}


static func failure(message: String) -> Dictionary:
	return {"ok": false, "value": {}, "error": message}


## The same schema with every object closed (no fields beyond its properties), for a helper whose own
## structured-output check can enforce it: what it returns then fits validate() above.
static func closed(schema: Dictionary) -> Dictionary:
	var out := schema.duplicate(true)
	if out.get("properties") is Dictionary:
		out["additionalProperties"] = false
		for key in out.properties:
			out.properties[key] = closed(out.properties[key])
	if out.get("items") is Dictionary:
		out["items"] = closed(out.items)
	return out


## Only the fields the schema knows, recursively (an automatic helper's extra field, like a person's
## name, is dropped unread). Nothing is converted: the strict validate() still runs on the result. A
## pasted answer is never projected; it must match exactly (the player can copy a repair prompt).
static func project(value: Variant, schema: Dictionary) -> Variant:
	if value is Dictionary and schema.get("properties") is Dictionary:
		var out := {}
		for key in value:
			if schema.properties.has(key):
				out[key] = project(value[key], schema.properties[key])
		return out
	if value is Array and schema.get("items") is Dictionary:
		return value.map(func(item): return project(item, schema.items))
	return value


static func validate(value: Variant, schema: Dictionary, path: String = "$", depth: int = 0) -> String:
	if depth > 16:
		return path + ": nesting exceeds 16 levels."
	var types: Variant = schema.get("type", [])
	if types is String:
		types = [types]
	var matches: bool = types.is_empty()
	for type in types:
		match str(type):
			"object": matches = matches or value is Dictionary
			"array": matches = matches or value is Array
			"string": matches = matches or value is String
			"boolean": matches = matches or value is bool
			"number": matches = matches or ((value is int or value is float) and is_finite(float(value)))
			"integer": matches = matches or ((value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)))
			"null": matches = matches or value == null
	if not matches:
		return path + ": incorrect value type."
	if schema.has("enum"):
		var allowed := false
		for option in schema.enum:
			if (value is int or value is float) and (option is int or option is float):
				allowed = allowed or float(value) == float(option)
			elif typeof(value) == typeof(option):
				allowed = allowed or value == option
		if not allowed:
			return path + ": unsupported choice."
	if value is int or value is float:
		if not is_finite(float(value)):
			return path + ": number must be finite."
		if float(value) < float(schema.get("minimum", -1.0e12)) or float(value) > float(schema.get("maximum", 1.0e12)):
			return path + ": number is outside the supported bounds."
	elif value is String:
		if value.length() > int(schema.get("maxLength", MAX_TEXT)) or value.length() < int(schema.get("minLength", 0)):
			return path + ": text length is outside the supported bounds."
	elif value is Array:
		if value.size() > int(schema.get("maxItems", MAX_ITEMS)):
			return path + ": too many entries."
		for i in value.size():
			var error := validate(value[i], schema.get("items", {}), "%s[%d]" % [path, i], depth + 1)
			if error != "":
				return error
	elif value is Dictionary:
		var properties: Dictionary = schema.get("properties", {})
		for required in schema.get("required", []):
			if not value.has(required):
				return path + "." + str(required) + ": required field is missing."
		if value.size() > MAX_ITEMS:
			return path + ": too many fields."
		for key in value:
			# Never put an unrecognized, potentially private key in an error/log.
			if not properties.has(key):
				return path + ": unsupported field."
			var error := validate(value[key], properties[key], path + "." + str(key), depth + 1)
			if error != "":
				return error
	return ""
