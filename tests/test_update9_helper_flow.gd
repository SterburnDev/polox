extends "res://tests/test_case.gd"
## Update 9, the helper workflows end to end with no key and no network: a request is closed in the same
## save as Keep (so an answer can never be applied twice, even when Undo puts the house back as it was);
## one tick per change (Tell Polox and research); Undo for kept research; the exact payload shown before
## an automatic helper is asked, and Cancel sends nothing; late answers after closing or adjusting are
## ignored; malformed and stale imports never touch the home; a failed save leaves the request open; the
## prompt and the answer through the file dialogs; public links and plausible facts only.

const Request := preload("res://scripts/home/helper_request.gd")
const HelperJson := preload("res://scripts/home/helper_json.gd")
const ResearchPrompt := preload("res://scripts/home/research_prompt.gd")
const TellPolox := preload("res://scripts/home/tell_polox.gd")
const LookAgain := preload("res://scripts/home/look_again.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const ReviewPanel := preload("res://scripts/home/helper_review_panel.gd")

const FIXTURE := "res://tests/fixtures/home_research_madeup.json"
const LATER := "res://tests/fixtures/home_research_madeup_later.json"

var main: Node


func _answers() -> Dictionary:
	return {"address": "12 Example Lane, Testville", "home_type": "house", "floors": 2,
		"rooms": {"bedroom": 3, "bathroom": 2, "kitchen": 1, "living": 1, "dining": 1, "laundry": 1},
		"entry_room": "hall", "my_room": {"floor": 1, "where": "front", "desk": true}}


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	HomeMapper.build_home(_answers(), {}, "")
	return main.game


func _shutdown() -> void:
	main.queue_free()
	await frames(2)


func _plan() -> Dictionary:
	return HomeStore.load_home().get("plan", {})


func _my_wall() -> String:
	for f in _plan().floors:
		for r in f.rooms:
			if bool(r.get("mine", false)):
				return str(r.wall)
	return ""


func _tell(start: String = "") -> Control:
	var panel: Control = load("res://scripts/home/tell_polox_panel.gd").new()
	main.open_panel(panel)
	panel.setup_tell(main.game, start)
	return panel


func _words_envelope(request: Dictionary, changes: Array) -> String:
	return JSON.stringify({"schema_version": 1, "request_id": request.request_id, "base_revision": request.base_revision,
		"task": "words", "result": {"changes": changes, "questions": []}})


func _open_manual(panel: Control) -> Control:
	panel._manual_helper()
	await frames(2)
	return main.panels[-1]


func _review() -> Control:
	for p in main.panels:
		if is_instance_valid(p) and p.get_script() == ReviewPanel:
			return p
	return null


func _research_raw(path: String) -> Dictionary:
	return HelperJson.project(JSON.parse_string(FileAccess.get_file_as_string(path)), ResearchPrompt.response_schema())


func test_an_applied_answer_never_applies_again_even_after_undo() -> void:
	await _boot()
	var before := JSON.stringify(_plan())
	var panel := _tell("We painted my room blue.")
	var manual := await _open_manual(panel)
	var request: Dictionary = manual.request
	var text := _words_envelope(request, [{"type": "wall", "room": "my room", "color": "blue"}])
	manual.response_box.text = text
	manual.preview_response()
	await frames(2)
	panel.keep()
	eq(_my_wall(), TellPolox.COLORS.blue, "kept")
	eq(str(Request.pending().get("state", "")), "applied", "the request is closed in the same save as Keep")
	check(not Request.pending().has("context") and not Request.pending().has("response"), "your words and the answer aren't kept afterwards")
	panel.undo()
	eq(JSON.stringify(_plan()), before, "Undo: the house exactly as before (the same revision as the prompt)")
	var again := Request.prepare(text, request)
	check(not bool(again.ok), "the same answer can't be imported again")
	check(str(again.error).contains("already used"), "and it says why: " + str(again.error))
	await _shutdown()


func test_ticks_keep_only_the_changes_you_chose() -> void:
	await _boot()
	var panel := _tell("We painted my room green. The hallway has a blue runner.")
	await frames(2)
	var changes: Array = panel.proposal.changes
	var ticks: Array = panel.preview.find_children("Accept_*", "CheckBox", true, false)
	eq(ticks.size(), changes.size(), "a tick for every change")
	var runner := -1
	for i in changes.size():
		if str(changes[i].type) == "add":
			runner = i
	check(runner >= 0, "the runner is proposed")
	(panel.preview.find_child("Accept_%d" % runner, true, false) as CheckBox).button_pressed = false
	panel.keep()
	eq(_my_wall(), TellPolox.COLORS.green, "the ticked paint is kept")
	var has_runner := false
	for f in _plan().floors:
		if (f.furniture as Array).any(func(p): return str(p.model) == "runner" and bool(p.get("user", false))):
			has_runner = true   # (a told piece is marked user; generated hallways may have their own)
	check(not has_runner, "the unticked runner is not")
	eq((HomeStore.load_home().edits as Array).size(), 1, "one edit kept, not two")
	await _shutdown()


func test_noop_apply_closes_the_request_without_changing_home() -> void:
	await _boot()
	var before := JSON.stringify(HomeStore.load_home())
	var request := Request.create("words", {"text": "Nothing to change."})
	var result := preload("res://scripts/home/home_edit.gd").commit([], "words", Request.closing_writes(request))
	eq(result.get("applied", -1), 0, "a successful no-op apply is explicit")
	eq(str(Request.pending().state), "applied", "even a no-op is durably consumed")
	check(not bool(Request.accept({"changes": [], "questions": []}, request).ok), "the consumed no-op cannot be imported again")
	eq(JSON.stringify(HomeStore.load_home()), before, "no-op leaves the home untouched")
	Request.dismiss(request)
	eq(str(Request.pending().state), "applied", "a late dismissal cannot rewrite an applied request")
	await _shutdown()


func test_research_review_keeps_ticked_items_and_undo_puts_it_all_back() -> void:
	await _boot()
	var first := HomeModel.clean_research(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))
	HomeMapper.build_home(_answers(), first, "recorded")
	HomeStore.save_research(first)
	var before := JSON.stringify(HomeStore.load_home())
	var hp: Control = load("res://scripts/home/map_home_panel.gd").new()
	main.open_panel(hp)
	hp.setup_home(main.game)
	before = JSON.stringify(HomeStore.load_home())   # (opening My home settles its open questions)
	hp.recorded_look = LATER
	hp.look_again()
	var t := Time.get_ticks_msec()
	while _review() == null and Time.get_ticks_msec() - t < 5000:
		await frames(2)
	var review := _review()
	if not check(review != null, "the changes are shown for review"):
		await _shutdown()
		return
	var cafe := -1
	for i in review.checks.size():
		if str(review.checks[i].id).begins_with("near:"):
			cafe = i
	check(cafe >= 0, "the new place nearby is one of them")
	(review.checks[cafe].box as CheckBox).button_pressed = false
	eq(JSON.stringify(HomeStore.load_home()), before, "nothing changes while you look")
	review._decide("keep")
	await frames(2)
	var home := HomeStore.load_home()
	check((home.timeline as Array).any(func(e): return str(e.kind) == "permit" and int(e.year) == 2024), "the ticked permit is kept")
	check(not (home.neighbourhood as Array).any(func(n): return str(n.name) == "Corner Cafe"), "the unticked cafe is not")
	var later := HomeModel.clean_research(JSON.parse_string(FileAccess.get_file_as_string(LATER)))
	var remaining := LookAgain.diff(HomeStore.last_research(), later)
	eq(remaining.neighbourhood.size(), 1, "the rejected cafe remains available for a later review")
	eq(remaining.permits.size(), 0, "the accepted permit is not proposed again")
	check(hp.find_child("UndoResearch", true, false) != null, "Undo is offered right away")
	check(hp.undo_research(), "Undo")
	eq(JSON.stringify(HomeStore.load_home()), before, "the whole home is back as it was")
	eq(LookAgain.diff(HomeStore.last_research(), later).permits.size(), 1, "Undo also restores the research comparison baseline")
	await _shutdown()


func test_nothing_new_closes_the_request() -> void:
	await _boot()
	var raw := _research_raw(FIXTURE)
	var first := HomeModel.clean_research(raw)
	HomeStore.save_research(first)
	var request := Request.create("research", {"location": "12 Example Lane, Testville", "known": {}}, "claude_code")
	check(bool(Request.accept(raw, request).ok), "an automatic answer passes the same checks")
	var hp: Control = load("res://scripts/home/map_home_panel.gd").new()
	main.open_panel(hp)
	hp.setup_home(main.game)
	request = Request.pending()
	hp._research_request = request
	hp._research_revision = Request.revision(HomeStore.load_home())
	hp._preview_research(HomeModel.clean_research(raw))
	eq(str(Request.pending().state), "dismissed", "looked at, nothing new: closed")
	check(not bool(Request.accept(raw, request).ok), "and it can't be used later")
	await _shutdown()


func test_research_cannot_keep_orphaned_or_reidentified_sources() -> void:
	await _boot()
	var first := HomeModel.clean_research(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))
	HomeMapper.build_home(_answers(), first, "recorded")
	var later := HomeModel.clean_research(JSON.parse_string(FileAccess.get_file_as_string(LATER)))
	var d := LookAgain.diff(HomeStore.last_research(), later)
	var before := JSON.stringify(HomeStore.load_home())
	var selected: Array = []
	for item in d.items:
		if str(item.kind) != "sources":
			selected.append(item.id)
	check(not LookAgain.keep(later, d, selected), "a nearby place cannot be kept without its new source")
	check(HomeStore.last_error.contains("source"), "the missing source is explained")
	eq(JSON.stringify(HomeStore.load_home()), before, "rejected selection changes nothing")
	later.sources[0].url = "https://different.example.org/record"
	check(not LookAgain.keep(later, LookAgain.diff(first, later)), "a source ID cannot silently change identity")
	eq(JSON.stringify(HomeStore.load_home()), before, "source identity rejection changes nothing")
	await _shutdown()


func test_the_exact_payload_first_cancel_sends_nothing_and_late_answers_are_ignored() -> void:
	await _boot()
	var before := JSON.stringify(HomeStore.load_home())
	var words := "My room's walls are green now."
	var panel := _tell()
	panel.text_box.text = words
	panel.ask_helper("claude_code")
	await frames(2)
	var review := _review()
	if not check(review != null, "a look at what would be sent comes first"):
		await _shutdown()
		return
	eq(review.payload_box.text, TellPolox.words_prompt(words, _plan(), false), "word for word")
	check(not review.payload_box.text.contains("Example Lane"), "never the address")
	review._decide("cancel")
	await frames(2)
	eq(str(panel._status.text), "Nothing was sent.")
	check(Request.pending().is_empty(), "no request was even made")
	# Send, then change your mind (Adjust) before the helper answers: whatever comes back is ignored.
	panel.ask_helper("claude_code")
	await frames(2)
	_review()._decide("send")
	panel.adjust()
	await frames(10)
	check(panel.proposal.is_empty(), "no proposal from the abandoned request")
	# Send, then close Tell Polox while it works.
	panel.ask_helper("claude_code")
	await frames(2)
	_review()._decide("send")
	panel.close()
	await frames(10)
	eq(JSON.stringify(HomeStore.load_home()), before, "nothing changed in the home")
	await _shutdown()


func test_malformed_and_stale_imports_never_touch_the_home() -> void:
	await _boot()
	var before := JSON.stringify(HomeStore.load_home())
	var request := Request.create("words", {"text": "Blue walls."})
	var good := _words_envelope(request, [{"type": "wall", "room": "my room", "color": "blue"}])
	var envelope: Dictionary = JSON.parse_string(good)
	var bad: Array = ["<html><body>502 Bad Gateway</body></html>", good + " " + good, "Sure! Here it is: " + good,
		"```json\n" + good + "\n```\nHope that helps", "```python\n" + good + "\n```"]
	for change in [{"type": "explode", "room": "my room"}, {"type": "add", "room": "my room", "model": "rocket"},
			{"type": "add", "room": "my room", "model": "plant", "count": 99}, {"type": "wall", "room": "my room", "color": "url(http://x)"}]:
		var e: Dictionary = envelope.duplicate(true)
		e.result.changes = [change]
		bad.append(JSON.stringify(e))
	var extra: Dictionary = envelope.duplicate(true)
	extra["note"] = "an extra field"
	bad.append(JSON.stringify(extra))
	var wrong_version: Dictionary = envelope.duplicate(true)
	wrong_version.schema_version = 2
	bad.append(JSON.stringify(wrong_version))
	for b in bad:
		var r := Request.prepare(str(b), request)
		check(not bool(r.ok), "rejected: " + str(b).left(40))
		check(not str(r.error).contains("explode") and not str(r.error).contains("rocket"), "the error never repeats the data")
	eq(JSON.stringify(HomeStore.load_home()), before, "the home is untouched")
	check(bool(Request.prepare("```json\n" + good + "\n```", request).ok), "one enclosing fence is fine")
	check(bool(Request.prepare(good, request).ok), "importing again while it's still open is fine (resumable)")
	# A newer home: the old answer no longer fits.
	HomeEdit_note()
	check(not bool(Request.prepare(good, request).ok), "an answer for an older home is refused")
	await _shutdown()


## A real change to the house (a room renamed), so an answer prepared for the house before it no longer fits.
## (The first-look marker no longer counts as one: it changes nothing in the house.)
func HomeEdit_note() -> void:
	var home := HomeStore.load_home()
	home.plan.floors[0].rooms[0]["name"] = "Renamed since the prompt"
	HomeStore.save_home(home)


func test_a_failed_save_leaves_the_request_open_and_the_home_as_it_was() -> void:
	await _boot()
	var before := JSON.stringify(HomeStore.load_home())
	var panel := _tell("We painted my room blue.")
	var manual := await _open_manual(panel)
	manual.response_box.text = _words_envelope(manual.request, [{"type": "wall", "room": "my room", "color": "blue"}])
	manual.preview_response()
	await frames(2)
	JsonUtil.ensure_dir(HomeStore.path("home.json.tmp"))   # the disk refuses the new home.json
	panel.keep()
	eq(JSON.stringify(HomeStore.load_home()), before, "rolled back: the home as it was")
	eq(str(Request.pending().state), "pending", "the request is still open (its closing record rolled back too)")
	DirAccess.remove_absolute(HomeStore.path("home.json.tmp"))
	panel.keep()
	eq(_my_wall(), TellPolox.COLORS.blue, "with room on the disk again, Keep works")
	eq(str(Request.pending().state), "applied")
	await _shutdown()


func test_prompt_and_answer_through_the_file_dialogs() -> void:
	var root := fresh_save_root()
	var manual: Control = load("res://scripts/home/helper_manual_panel.gd").new()
	tree.root.add_child(manual)
	manual.setup_manual("words", {"text": "Blue walls in my room."})
	var got := {"value": {}}
	manual.prepared.connect(func(value, _request): got.value = value)
	manual._file_dialog(true)
	var save_dialog: FileDialog = manual.find_children("*", "FileDialog", true, false)[0]
	var prompt_path := root.path_join("polox-prompt.txt")
	save_dialog.file_selected.emit(prompt_path)
	eq(FileAccess.get_file_as_string(prompt_path), manual.prompt_box.text, "Save prompt writes exactly the reviewed prompt")
	var answer_path := root.path_join("answer.json")
	var f := FileAccess.open(answer_path, FileAccess.WRITE)
	f.store_string(_words_envelope(manual.request, []))
	f.close()
	await frames(1)
	manual._file_dialog(false)
	var open_dialog: FileDialog = manual.find_children("*", "FileDialog", true, false)[-1]
	open_dialog.file_selected.emit(answer_path)
	eq(manual.response_box.text, FileAccess.get_file_as_string(answer_path), "Import JSON reads the file into the box")
	manual.preview_response()
	check(got.value is Dictionary and got.value.has("changes"), "and it previews like a paste")
	var big := root.path_join("big.json")
	f = FileAccess.open(big, FileAccess.WRITE)
	f.store_string("x".repeat(HelperJson.MAX_BYTES + 10))
	f.close()
	var again: Control = load("res://scripts/home/helper_manual_panel.gd").new()
	tree.root.add_child(again)
	again.setup_manual("words", {"text": "x"})
	again._file_dialog(false)
	(again.find_children("*", "FileDialog", true, false)[0] as FileDialog).file_selected.emit(big)
	check(again.status.text.contains("512 KiB"), "a file that's too big is refused")
	manual.queue_free()
	again.queue_free()
	await frames(2)


func test_public_links_and_plausible_facts_only() -> void:
	for url in ["https://assessor.example.org/parcel/1", "http://web.archive.org/web/2019/https://x.example.com", "https://maps.example.com:8443/a?b=1#c"]:
		check(ResearchPrompt.public_url(url), "public: " + url)
	for url in ["javascript:alert(1)", "file:///C:/Users/x", "https://user:pw@example.com/", "http://localhost:8080/", "http://192.168.1.1/admin",
			"http://10.0.0.5/", "http://172.20.0.1/", "https://printer.local/", "https://[::1]/", "https://example", "https://exa mple.com/", "ftp://example.com/"]:
		check(not ResearchPrompt.public_url(url), "refused: " + url)
	var raw := _research_raw(FIXTURE)
	eq(ResearchPrompt.validate_response(raw), "", "the recorded answer (minus the owner's name) is valid")
	var future: Dictionary = raw.duplicate(true)
	future.facts[0].value = 3000
	var e := ResearchPrompt.validate_response(future)
	check(e.contains("plausible") and not e.contains("3000"), "a year in the future is refused, without echoing it")
	var unsourced: Dictionary = raw.duplicate(true)
	unsourced.facts[0].source = ""
	check(ResearchPrompt.validate_response(unsourced).contains("source"), "every fact names its source")
	var private_link: Dictionary = raw.duplicate(true)
	private_link.sources[0].url = "http://192.168.0.1/"
	check(ResearchPrompt.validate_response(private_link) != "", "a local address as a source is refused")
	var old_permit: Dictionary = raw.duplicate(true)
	if (old_permit.get("permits", []) as Array).size() > 0:
		old_permit.permits[0].year = 1200
		check(ResearchPrompt.validate_response(old_permit) != "", "an impossible permit year is refused")


func test_automatic_and_pasted_answers_both_reject_unknown_fields() -> void:
	fresh_save_root()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	check(raw.has("owner"), "(the recording names an owner)")
	var projected: Dictionary = HelperJson.project(raw, ResearchPrompt.response_schema())
	var provider := preload("res://scripts/home/research.gd").new()
	check(not bool(provider._ok(raw).ok), "automatic output with an unsupported field is refused too")
	check(bool(provider._ok(projected).ok), "schema-conforming automatic output passes")
	provider.free()
	check(not projected.has("owner"), "a person's name never gets past the boundary")
	eq(ResearchPrompt.validate_response(projected), "")
	var request := Request.create("research", {"location": "Testville", "known": {}})
	var pasted := {"schema_version": 1, "request_id": request.request_id, "base_revision": request.base_revision, "task": "research", "result": raw}
	check(not bool(Request.prepare(JSON.stringify(pasted), request).ok), "pasted with the extra field: refused (a repair prompt can fix it)")
	pasted.result = projected
	check(bool(Request.prepare(JSON.stringify(pasted), request).ok), "pasted as the schema says: accepted")
