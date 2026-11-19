extends "res://tests/test_case.gd"

const Survey := preload("res://scripts/home/survey_screen.gd")
const Data := preload("res://scripts/home/survey_data.gd")
const Draft := preload("res://scripts/home/survey_draft.gd")
const Store := preload("res://scripts/home/home_store.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")


func _screen() -> Control:
	GameState.settings["reduce_motion"] = true
	var s := Survey.new()
	s.available = {"none": true}
	tree.root.add_child(s)
	return s


func _step(s: Control, id: String) -> void:
	for i in Data.STEPS.size():
		if str(Data.STEPS[i].id) == id:
			s.step_i = i
			s._show_step()
			while s._typing or s._waiting_tap:
				s._tap()
			return


func test_back_restores_text_counts_choice_and_private_draft() -> void:
	fresh_save_root()
	var s := _screen()
	await frames(2)
	_step(s, "address")
	s.field.text = "Synthetic survey text"
	s.field.text_changed.emit(s.field.text)
	s._submit_text(s.field.text)
	s._answer("house")
	s._go_back()
	eq(Data.get_answer(s.answers, "home_type"), "house")
	s._go_back()
	eq(s.field.text, "Synthetic survey text", "Back restores submitted text")
	_step(s, "rooms")
	s._counts.bedroom = 5
	s._save_draft()
	s.next_step()
	s._go_back()
	eq(s._counts.bedroom, 5, "Back retains counts instead of defaults")
	_step(s, "memory")
	s.field.text = "A private unfinished draft"
	s.field.text_changed.emit(s.field.text)
	s._save_draft()
	s.queue_free()
	await frames(2)
	s = _screen()
	await frames(2)
	eq(str(s.step().id), "memory", "reopening resumes the same question")
	eq(s.field.text, "A private unfinished draft", "unsubmitted text survives")
	eq(Data.get_answer(s.answers, "rooms.bedroom"), 5)
	check(FileAccess.file_exists(Store.path(Draft.FILE)), "draft saved inside private home boundary")
	check(not SyncFiles.allowed("my_home/survey_draft.json", PackedStringArray()), "draft excluded from sync")
	s.complete_draft()
	s.queue_free()
	await frames(2)
	check(Draft.read().is_empty(), "accepted draft does not reappear from backup")
	GameState.settings["reduce_motion"] = false


func test_changed_branch_preserves_but_does_not_apply_inactive_answers() -> void:
	var a := {"home_type": "house", "floors": 2, "basement": true, "my_room": {"floor": 1, "wall": "#a9c4dc"}, "rooms": {"bedroom": 3}}
	Data.set_answer(a, "home_type", "apartment")
	Data.set_answer(a, "floors", 1)
	var active := Data.active_answers(a)
	check(not active.has("basement"), "apartment doesn't inherit an old basement")
	check(not active.my_room.has("floor"), "one-storey branch doesn't inherit upstairs")
	eq(active.my_room.wall, "#a9c4dc", "unrelated answer remains")
	eq(active.rooms.bedroom, 3)
	check("basement" in Data.inactive_keys(a), "review can name inactive answers")
	Data.set_answer(a, "home_type", "house")
	Data.set_answer(a, "floors", 2)
	eq(Data.active_answers(a).basement, true, "returning to branch restores the answer")
	eq(Data.active_answers(a).my_room.floor, 1)


func test_back_at_start_stays_in_wizard_and_review_never_calls_helper() -> void:
	fresh_save_root()
	var s := _screen()
	await frames(2)
	s.on_back()
	eq(s.step_i, 0, "Back at start does not leave")
	_step(s, "consent")
	check(not s.finished, "an empty address still gets a review")
	var sent := {"count": 0}
	s.done.connect(func(_r): sent.count += 1)
	s._history = [1, 2]
	s.on_back()
	eq(str(s.step().id), "home_type")
	eq(sent.count, 0, "Back sends/applies nothing")
	s.queue_free()
	await frames(2)
	GameState.settings["reduce_motion"] = false
