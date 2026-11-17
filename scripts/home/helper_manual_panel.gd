extends "res://scripts/ui/screen_panel.gd"
## Copy/paste: any AI chat, no key. The exact prompt to review and copy (or save), the AI's reply to paste
## (or import), then the caller's usual preview, Keep and Undo. A reply that fails the strict check only on
## form (a sentence round the JSON, a field Polox doesn't use, a number written as text: helper_paste.gd) is
## offered tidied, with a list of what changed, and goes through the same strict check when you tap Use it.
## A house lookup whose prompt went stale (your home changed, or a newer prompt was made) can be used with a
## fresh prompt: the building's public facts don't depend on what you changed at home.
## On a computer the house lookup's prompt is also saved as prompt.txt in your home's Info folder
## (home_store.gd), for an AI that works with files: it saves answer.json there, and this screen reads it.
## Tags: [AI_HELPER]
signal prepared(result: Dictionary, request: Dictionary)
const Request := preload("res://scripts/home/helper_request.gd")
const Json := preload("res://scripts/home/helper_json.gd")
const Paste := preload("res://scripts/home/helper_paste.gd")
const Store := preload("res://scripts/home/home_store.gd")
var request: Dictionary = {}
var prompt_box: TextEdit
var response_box: TextEdit
var status: Label
var _task := ""
var _context: Dictionary = {}
var _offer: HFlowContainer      # Use it / Use with a fresh prompt, when a reply needs one of them
var _tidied := ""
var _info_seen := ""            # the answer file already read from the Info folder (its path and time)
var _info_wait := 0.0


func setup_manual(task: String, context: Dictionary) -> void:
	_task = task
	_context = context.duplicate(true)
	setup("Use any AI · no key needed", Vector2(900, 720))
	var steps := "1. Copy prompt.  2. Paste it into an AI chat that can search the web (ChatGPT, Claude, Gemini, Copilot).  3. Copy its whole reply, Paste reply here, then Preview." if task == "research" \
		else "1. Copy prompt.  2. Paste it into any AI chat.  3. Copy its whole reply, Paste reply here, then Preview."
	body.add_child(UiKit.para(steps, 16))
	body.add_child(UiKit.para("Only what you paste into the AI leaves Polox; read the prompt first. Photos aren't included. Nothing changes until you Keep.", 14, ThemeBuilder.MUTED))
	request = Request.pending()
	if request.is_empty() or str(request.get("task", "")) != task or str(request.get("state", "")) != "pending":
		request = Request.create(task, context)
	prompt_box = UiKit.text_edit("Prompt", "", 120)
	prompt_box.editable = false
	prompt_box.name = "ManualPrompt"
	body.add_child(prompt_box)
	var actions := UiKit.flow_row(6)
	var copy := UiKit.button("Copy prompt", func():
		DisplayServer.clipboard_set(prompt_box.text)
		status.text = "Copied. Paste it into the AI chat.", 0)
	copy.name = "CopyPrompt"
	actions.add_child(copy)
	actions.add_child(UiKit.button("Save prompt", func(): _file_dialog(true), 0))
	actions.add_child(UiKit.button("New prompt", func():
		request = Request.create(_task, _context)
		_refresh_prompt()
		_clear_offer()
		response_box.text = "", 0))
	body.add_child(actions)
	response_box = UiKit.text_edit("Paste the AI's reply here (all of it is fine)", "", 120)
	response_box.name = "ManualResponse"
	body.add_child(response_box)
	var imports := UiKit.flow_row(6)
	var paste := UiKit.button("Paste reply", func():
		response_box.text = DisplayServer.clipboard_get()
		_clear_offer(), 0)
	paste.name = "PasteReply"
	imports.add_child(paste)
	imports.add_child(UiKit.button("Import JSON", func(): _file_dialog(false), 0))
	var preview := UiKit.button("Preview", preview_response, 0)
	preview.name = "PreviewReply"
	imports.add_child(preview)
	imports.add_child(UiKit.button("Copy repair prompt", func():
		DisplayServer.clipboard_set("Repair the JSON response for this request. Return only a corrected JSON object in one ```json code block. Validation issue: " + status.text + "\n" + prompt_box.text)
		status.text = "Repair prompt copied: paste it into the same AI chat.", 0))
	body.add_child(imports)
	if _uses_info():
		# [AI_HELPER] The same request as files, for an AI that reads and saves them itself.
		body.add_child(UiKit.para("An AI that works with files can do it by itself: the prompt is saved as prompt.txt in your Info folder, and its answer goes there as answer.json.", 14, ThemeBuilder.MUTED))
		var info := UiKit.flow_row(6)
		var open_info := UiKit.button("Open Info folder", func(): OS.shell_open(Store.info_dir()), 0)
		open_info.name = "OpenInfo"
		info.add_child(open_info)
		var read_info := UiKit.button("Read answer file", func(): read_info_answer(true), 0)
		read_info.name = "ReadInfoAnswer"
		info.add_child(read_info)
		body.add_child(info)
	status = UiKit.para("", 16, ThemeBuilder.YELLOW)
	status.name = "ManualStatus"
	body.add_child(status)
	_offer = UiKit.flow_row(6)
	_offer.name = "ManualOffer"
	body.add_child(_offer)
	_refresh_prompt()
	if request.get("response") is Dictionary:
		response_box.text = JSON.stringify(request.response, "\t")
	elif _uses_info():
		read_info_answer(false)   # an answer saved there while this screen was closed


## The Info folder is for a house lookup on a computer (a phone's files aren't where an AI could reach them).
func _uses_info() -> bool:
	return _task == "research" and OS.has_feature("pc")


## The answer an AI (or you) saved in the Info folder goes into the reply box, to be previewed like a
## pasted one. `asked`: you pressed the button (say so when nothing is there); else only a new file is read.
func read_info_answer(asked: bool) -> void:
	var file := Store.waiting_answer()
	if file == "":
		if asked:
			status.text = "No answer file in the Info folder yet. An AI saves it there as answer.json."
		return
	var stamp := Store.answer_stamp(file)
	if not asked and stamp == _info_seen:
		return
	_info_seen = stamp
	var text := Store.read_answer(file)
	if text.strip_edges() == "":
		status.text = "%s in the Info folder is empty, unreadable or over 512 KiB." % file.get_file()
		return
	response_box.text = text
	_clear_offer()
	status.text = "Read %s from the Info folder. Preview checks it; nothing changes until you Keep." % file.get_file()


## While the screen is open, an answer file that appears is read (a look every two seconds).
func _process(delta: float) -> void:
	if not _uses_info() or response_box == null:
		return
	_info_wait += delta
	if _info_wait >= 2.0:
		_info_wait = 0.0
		read_info_answer(false)


func _refresh_prompt() -> void:
	prompt_box.text = Request.prompt(request) if not request.is_empty() else ""
	if _uses_info():
		Store.set_info_prompt(prompt_box.text)
	status.text = "Couldn't save the request. Free storage and try New prompt." if request.is_empty() else "The request is saved privately so you can come back to it."


func _clear_offer() -> void:
	_tidied = ""
	if _offer:
		for c in _offer.get_children():
			c.queue_free()


func preview_response() -> void:
	_clear_offer()
	if response_box.text.strip_edges() == "":
		status.text = "Paste the AI's reply first."
		return
	var result := Request.prepare(response_box.text, request)
	if bool(result.ok):
		_done(result)
		return
	var strict_error := str(result.error)
	var stale := strict_error.begins_with("Your home changed") or strict_error.begins_with("This prompt was replaced")
	var tidy := Paste.tidy(response_box.text, request, stale)
	if stale:
		if _task == "research" and bool(tidy.ok):
			status.text = strict_error + " A house lookup still fits: use it with a fresh prompt?"
			var reuse := UiKit.button("Use with a fresh prompt", func(): _reuse(), 0)
			reuse.name = "ReuseReply"
			_offer.add_child(reuse)
		else:
			status.text = strict_error
		return
	if not bool(tidy.ok):
		status.text = strict_error if strict_error.begins_with("This response was already used") else str(tidy.error)
		return
	var check := Request.prepare(str(tidy.text), request)
	if not bool(check.ok):
		status.text = str(check.error) + " (Copy repair prompt asks the AI to fix it.)"
		return
	_tidied = str(tidy.text)
	status.text = "Polox tidied the reply: " + ", ".join(PackedStringArray(tidy.notes)) + ". Use it?"
	var use := UiKit.button("Use it", func(): _use_tidied(), 0)
	use.name = "UseTidied"
	_offer.add_child(use)


func _use_tidied() -> void:
	if _tidied == "":
		return
	var result := Request.prepare(_tidied, request)
	if not bool(result.ok):
		status.text = str(result.error)
		_clear_offer()
		return
	_done(result)


## A house lookup for a prompt that went stale: a fresh prompt for the same home, the reply fitted to it,
## then the strict check as always.
func _reuse() -> void:
	request = Request.create(_task, _context)
	if request.is_empty():
		status.text = "Couldn't save a new request. Free storage and try again."
		return
	_refresh_prompt()
	var tidy := Paste.tidy(response_box.text, request, true)
	if not bool(tidy.ok):
		status.text = str(tidy.error)
		_clear_offer()
		return
	var result := Request.prepare(str(tidy.text), request)
	if not bool(result.ok):
		status.text = str(result.error)
		_clear_offer()
		return
	_done(result)


func _done(result: Dictionary) -> void:
	prepared.emit(result.value, result.request)
	close()


func _file_dialog(save: bool) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.txt ; Text prompt"]) if save else PackedStringArray(["*.json, *.txt ; JSON response"])
	dialog.title = "Save the reviewed prompt" if save else "Import an AI response"
	if save:
		dialog.current_file = "polox-prompt.txt"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		dialog.hide()
		if save:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_string(prompt_box.text)
				file.flush()
				status.text = "Prompt saved." if file.get_error() == OK else "Couldn't finish saving the prompt."
			else:
				status.text = "Couldn't open that location for writing."
		else:
			var file := FileAccess.open(path, FileAccess.READ)
			if not file or file.get_length() > Json.MAX_BYTES:
				status.text = "Choose a readable JSON response of at most 512 KiB."
			else:
				response_box.text = file.get_as_text()
				_clear_offer()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.8)
