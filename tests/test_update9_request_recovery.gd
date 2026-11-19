extends "res://tests/test_case.gd"

const Request := preload("res://scripts/home/helper_request.gd")
const Store := preload("res://scripts/home/home_store.gd")
const Json := preload("res://scripts/core/json_util.gd")


func test_closed_request_cannot_reopen_from_pending_backup() -> void:
	for state in ["dismissed", "applied"]:
		fresh_save_root(current + "_" + state)
		var request := Request.create("words", {"text": "Nothing changed."})
		check(not request.is_empty())
		check(Store.apply_batch(Request.closing_writes(request, state)))
		var backup: Variant = Json.parse_file(Store.path(Request.FILE) + ".bak")
		check(backup is Dictionary and backup.state == "pending", "fixture retains a pending backup")
		check(DirAccess.remove_absolute(Store.path(Request.FILE)) == OK)
		eq(Request.pending(), {}, "a missing consumed record never revives a pending backup")
		check(not Request.accept({"changes": [], "questions": []}, request).ok)
		var replacement := Request.create("words", {"text": "Try again."})
		check(not replacement.is_empty() and replacement.request_id != request.request_id, "a fresh prompt remains available")


func test_truncated_current_request_cannot_restore_a_superseded_prompt() -> void:
	fresh_save_root()
	var older := Request.create("words", {"text": "First."})
	var newer := Request.create("words", {"text": "Second."})
	check(older.request_id != newer.request_id)
	var file := FileAccess.open(Store.path(Request.FILE), FileAccess.WRITE)
	file.close()
	eq(Request.pending(), {}, "corrupt current envelope fails closed")
	check(not Request.accept({"changes": [], "questions": []}, older).ok)
	check(not Request.accept({"changes": [], "questions": []}, newer).ok)
