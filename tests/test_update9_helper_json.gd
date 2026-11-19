extends "res://tests/test_case.gd"
const HelperJson := preload("res://scripts/home/helper_json.gd")
const Request := preload("res://scripts/home/helper_request.gd")
const Store := preload("res://scripts/home/home_store.gd")


func test_only_one_json_object_is_accepted() -> void:
	for input in ['{"a":1}', '```json\n{"a":1}\n```', '```\n{"a":1}\n```']:
		check(bool(HelperJson.parse(input).ok), "plain or singly fenced object")
	for input in ['[]', 'Here it is: {"a":1}', '{} {}', '```python\n{}\n```', '```json\n{}\n```\nmore']:
		check(not bool(HelperJson.parse(input).ok), "commentary, code and multiple documents rejected")
	check(not bool(HelperJson.parse("x".repeat(HelperJson.MAX_BYTES + 1)).ok), "bounded import")


func test_schema_rejects_coercion_nonfinite_unknown_fields_and_limits() -> void:
	var schema := {"type": "object", "properties": {"count": {"type": "integer", "minimum": 0, "maximum": 8}, "kind": {"type": "string", "enum": ["note"]}}, "required": ["count"]}
	eq(HelperJson.validate({"count": 2.0, "kind": "note"}, schema), "", "JSON integer representation")
	for bad in [{}, {"count": "2"}, {"count": true}, {"count": 2.5}, {"count": INF}, {"count": -1}, {"count": 9}, {"count": 1, "kind": "command"}, {"count": 1, "private address": "secret"}]:
		var error := HelperJson.validate(bad, schema)
		check(error != "", "invalid value rejected")
		check(not error.contains("private address") and not error.contains("secret"), "diagnostics do not echo payload")
	check(HelperJson.validate([1, 2], {"type": "array", "maxItems": 1, "items": {"type": "integer"}}) != "", "count bound")
	check(HelperJson.validate("long", {"type": "string", "maxLength": 3}) != "", "length bound")


func test_private_pending_request_round_trip_and_stale_rejection() -> void:
	fresh_save_root()
	var request := Request.create("words", {"text": "The kitchen has blue walls.", "plan": {}})
	check(not request.is_empty(), "private pending request saved")
	eq(Request.pending().request_id, request.request_id, "request resumes")
	check(Request.prompt(request).contains(request.request_id), "prompt identifies its request")
	var response := {"schema_version": 1, "request_id": request.request_id, "base_revision": request.base_revision, "task": "words", "result": {"changes": [], "questions": ["Which kitchen?"]}}
	var prepared := Request.prepare(JSON.stringify(response))
	check(prepared.ok, "valid response prepares a preview: " + str(prepared.error))
	check(not Store.exists(), "preview cannot create a home")
	response.request_id = "another request"
	check(not Request.prepare(JSON.stringify(response)).ok, "wrong request rejected")
	response.request_id = request.request_id
	response.schema_version = 2
	check(not Request.prepare(JSON.stringify(response)).ok, "unsupported version rejected")
	response.schema_version = 1
	check(Store.save_home({"plan": {}, "answers": {"floors": 1}}), "newer home saved")
	check(not Request.prepare(JSON.stringify(response)).ok, "older home revision rejected")


func test_replaced_prompt_cannot_overwrite_latest_pending_request() -> void:
	fresh_save_root()
	var old_request := Request.create("words", {"text": "Old edit"})
	var latest := Request.create("words", {"text": "New edit"})
	var response := {"schema_version": 1, "request_id": old_request.request_id,
		"base_revision": old_request.base_revision, "task": "words",
		"result": {"changes": [], "questions": []}}
	check(not Request.prepare(JSON.stringify(response), old_request).ok, "superseded open screen rejected")
	eq(Request.pending().request_id, latest.request_id, "latest request remains intact")
	check(not Request.pending().has("response"), "old response is not persisted")
