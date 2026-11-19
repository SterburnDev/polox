extends "res://scripts/ui/screen_panel.gd"
## Tell Polox about home: write something about your home in your own words (or add a photo), and Polox
## shows what it would change before changing anything ("Add: a blue rug in Hallway. Change: My room's
## walls to green."). Keep makes it so (with a little flourish when you're standing there), Adjust lets
## you change what you wrote, Undo puts the house back exactly. Anything it couldn't place comes back as
## a question you can answer or skip. It reads offline; "Ask Claude to read it" (only when you tap it,
## after a look at exactly what would be sent) sends what you wrote and the photo, never your address.
## Each proposed change has its own tick: Keep makes only the ticked ones. A helper's answer belongs to
## one request (helper_request.gd), closed in the same save as Keep, so it can't be applied twice.
## Tags: [AI_HELPER]

const TellPolox := preload("res://scripts/home/tell_polox.gd")
const HomeEdit := preload("res://scripts/home/home_edit.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const Research := preload("res://scripts/home/research.gd")
const NEED_WORDS := "Write what changed first."
const HelperRequest := preload("res://scripts/home/helper_request.gd")
const ReviewPanel := preload("res://scripts/home/helper_review_panel.gd")
const CHANGED := "Home changed. Read it again."

var world: Node
var text_box: TextEdit
var preview: VBoxContainer
var proposal: Dictionary = {}      # {"changes", "unsure"}
var last_batch := ""
var photo := ""                    # a photo you added (copied into my_home/files)
var _keep: Button
var _undo: Button
var _status: Label
var _base_revision := ""
var _request_generation := 0
var _research: Node
var _request: Dictionary = {}      # the helper request this proposal answers ({} for an offline reading)
var _rejected: Dictionary = {}     # change index -> true when its tick is off


func setup_tell(game_world: Node, start_text: String = "") -> void:
	world = game_world
	setup("Tell Polox about home", Vector2(900, 660))
	body.add_child(UiKit.para("Like \"We painted my room green.\"", 16, ThemeBuilder.MUTED))
	text_box = UiKit.text_edit("Tell Polox...", start_text, 110)
	text_box.name = "TellText"
	body.add_child(text_box)
	_status = UiKit.para("", 16, ThemeBuilder.YELLOW)
	_status.name = "HelperStatus"
	body.add_child(_status)
	var row := UiKit.flow_row(8)
	var read := UiKit.button("Read it", func(): read_it(), 0)
	read.name = "ReadIt"
	row.add_child(read)
	var pic := UiKit.button("Add a photo", func(): _pick_photo(), 0)
	pic.name = "AddPhoto"
	row.add_child(pic)
	row.add_child(UiKit.button("Use any AI", _manual_helper, 0))
	var helper := Research.preferred()
	if helper != "none":
		var ask := UiKit.button("Ask %s to read it" % Research.short_name(helper), func(): ask_helper(helper), 0)
		ask.name = "AskHelper"
		ask.tooltip_text = "Shows what's sent first."
		row.add_child(ask)
	body.add_child(row)
	preview = UiKit.vbox(6)
	preview.name = "Preview"
	body.add_child(UiKit.scroll(preview))
	var actions := UiKit.flow_row(8)
	_keep = UiKit.button("Keep", func(): keep(), 0)
	_keep.name = "Keep"
	_keep.disabled = true
	actions.add_child(_keep)
	var adjust := UiKit.button("Adjust", func(): adjust(), 0)
	adjust.name = "Adjust"
	actions.add_child(adjust)
	_undo = UiKit.button("Undo", func(): undo(), 0)
	_undo.name = "Undo"
	_undo.disabled = true
	actions.add_child(_undo)
	body.add_child(actions)
	if start_text != "":
		read_it()


## Reads what you wrote and shows what would change. Nothing changes yet.
func read_it() -> void:
	_cancel_request()
	var home := HomeStore.load_home()
	_base_revision = _revision(home)
	_request = {}
	proposal = TellPolox.read(text_box.text, home.get("plan", {}))
	_show_new()


## A fresh proposal: every change ticked.
func _show_new() -> void:
	_rejected.clear()
	_show()


func _show() -> void:
	for c in preview.get_children():
		c.queue_free()
	var changes: Array = proposal.get("changes", [])
	if changes.is_empty() and (proposal.get("unsure", []) as Array).is_empty():
		preview.add_child(UiKit.para("Name a room.", 18))
	for i in changes.size():
		var row := UiKit.hbox(8)
		var tick := CheckBox.new()
		tick.name = "Accept_%d" % i
		tick.button_pressed = not _rejected.has(i)
		tick.tooltip_text = "Leave this out."
		tick.custom_minimum_size = Vector2(UiKit.touch_target(), UiKit.touch_target())
		tick.toggled.connect(func(on: bool):
			if on:
				_rejected.erase(i)
			else:
				_rejected[i] = true
			_keep.disabled = _accepted_changes().is_empty())
		row.add_child(tick)
		var l := UiKit.para(TellPolox.describe(changes[i]), 18)
		l.name = "Change_%d" % i
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		preview.add_child(row)
	for q in proposal.get("unsure", []):
		preview.add_child(UiKit.para(str(q.text), 18, ThemeBuilder.YELLOW))
		var opts := UiKit.flow_row(6)
		for o in q.get("options", []):
			var b := UiKit.button(str(o.name), func(): _answer(q, o), 0)
			b.name = "Answer_" + str(o.id)
			opts.add_child(b)
		opts.add_child(UiKit.button("Skip", func(): _skip(q), 0))
		preview.add_child(opts)
	_keep.disabled = _accepted_changes().is_empty()


func _accepted_changes() -> Array:
	var out: Array = []
	var changes: Array = proposal.get("changes", [])
	for i in changes.size():
		if not _rejected.has(i):
			out.append(changes[i])
	return out


func _answer(q: Dictionary, room: Dictionary) -> void:
	var e := {"type": str(q.kind), "level": int(room.level), "room": str(room.id), "room_name": str(room.name)}
	match str(q.kind):
		"wall":
			e["color"] = str(q.value)
		"floor":
			e["floor"] = str(q.value)
		"add", "remove":
			e["model"] = str(q.get("model", ""))
			e["color"] = str(q.get("value", ""))
			e["count"] = int(q.get("count", 1))
		"used_to_be":
			e["was"] = str(q.value)
	(proposal.changes as Array).append(e)
	(proposal.unsure as Array).erase(q)
	_show()


func _skip(q: Dictionary) -> void:
	(proposal.unsure as Array).erase(q)
	_show()


## Makes the changes (one batch on the timeline; Undo puts them all back).
func keep() -> void:
	var changes := _accepted_changes()
	if changes.is_empty():
		if not _request.is_empty() and HelperRequest.dismiss(_request):
			_request = {}
			proposal = {}
			_keep.disabled = true
			_status.text = "Nothing ticked."
		return
	if _base_revision != _revision(HomeStore.load_home()):
		_keep.disabled = true
		_status.text = CHANGED
		return
	var extra := {}
	if not _request.is_empty():
		if not HelperRequest.is_open(_request):
			_keep.disabled = true
			_status.text = "Already used. Ask again."
			return
		extra = HelperRequest.closing_writes(_request, "applied")
	var res := HomeEdit.commit(changes, "photo" if photo != "" else "words", extra)
	if res.is_empty():
		_status.text = "Nothing to change."
		return
	last_batch = str(res.batch)
	_request = {}
	proposal = {} # A second click/callback cannot apply the same batch again.
	preload("res://scripts/ui/haptics.gd").confirm()
	_undo.disabled = last_batch == ""
	_keep.disabled = true
	_status.text = "Done: %d change%s." % [int(res.applied), "" if int(res.applied) == 1 else "s"]
	_refresh_world(true)


func adjust() -> void:
	_cancel_request()
	proposal = {}
	_show_new()
	text_box.grab_focus()


func undo() -> void:
	if last_batch == "" or not HomeEdit.undo(last_batch):
		return
	last_batch = ""
	_undo.disabled = true
	_status.text = "Put back."
	_refresh_world(false)


## If you're standing in your home, it changes in front of you (a small flourish).
func _refresh_world(flourish: bool) -> void:
	if world == null or not load("res://scripts/world/realms.gd").is_light(world.room.data):
		return
	if SaveManager.room_exists(GameState.current_room_id):
		world.reload_here()   # (new pieces pop in)
	else:
		world.load_room(load("res://scripts/world/light_home.gd").entry_id())
	if flourish and world.has_method("flourish"):
		world.flourish()


## Only when you tap it: your words (and photo) to the helper; its reading comes back as the same preview.
var recorded_words: Dictionary = {}   # tests: a recorded helper answer instead of a live call


func ask_helper(helper: String) -> void:
	if helper == "manual":
		_manual_helper()
		return
	if text_box.text.strip_edges() == "" and photo == "":
		_status.text = NEED_WORDS
		return
	_cancel_request()
	var generation := _request_generation
	var home := HomeStore.load_home()
	_base_revision = _revision(home)
	var plan: Dictionary = home.get("plan", {})
	if not recorded_words.is_empty():
		_request = {}
		proposal = TellPolox.clean_helper(recorded_words, plan)
		_show_new()
		_status.text = "Read. Keep it?"
		return
	# First, exactly what would leave Polox (your words, the room names, the photo if you added one).
	var reviewed_text := text_box.text
	var reviewed_photo := photo
	var review := ReviewPanel.new()
	if world and world.main:
		world.main.open_panel(review)
	else:
		add_child(review)
	review.review_payload("Ask %s?" % Research.short_name(helper), str(Research.WHO.get(helper, helper)),
		TellPolox.words_prompt(reviewed_text, plan, reviewed_photo != ""), PackedStringArray([reviewed_photo]) if reviewed_photo != "" else PackedStringArray())
	var answer: Array = await review.decided
	if generation != _request_generation or not is_inside_tree():
		return
	if str(answer[0]) != "send":
		_status.text = "Nothing was sent."
		return
	if _base_revision != _revision(HomeStore.load_home()):
		_status.text = CHANGED
		return
	_request = HelperRequest.create("words", {"text": reviewed_text}, helper)
	if _request.is_empty():
		_status.text = "Couldn't save."
		return
	_status.text = "Asking..."
	var r: Node = Research.new()
	_research = r
	add_child(r)
	var reply := {"done": false, "res": {}}
	r.finished.connect(func(d: Dictionary):
		reply.res = d
		reply.done = true, CONNECT_ONE_SHOT)
	r.progress.connect(func(line): _status.text = str(line))
	r.start_words(helper, reviewed_text, plan, reviewed_photo)
	while not bool(reply.done) and generation == _request_generation and is_instance_valid(r) and is_inside_tree():
		await get_tree().process_frame
	if is_instance_valid(r):
		if not bool(reply.done):
			r.cancel()
		r.queue_free()
	if _research == r:
		_research = null
	if generation != _request_generation or not is_inside_tree() or not bool(reply.done):
		return
	var res: Dictionary = reply.res
	if not bool(res.get("ok", false)):
		_status.text = Research.advice(res)
		return
	# The same boundary as a pasted answer: this request, this home, the strict check.
	var accepted := HelperRequest.accept(res.get("raw", {}), _request)
	if not bool(accepted.ok):
		_status.text = str(accepted.error)
		return
	proposal = res.research
	_show_new()
	_status.text = "Read. Keep it?"


static func _revision(home: Dictionary) -> String:
	return preload("res://scripts/home/helper_request.gd").revision(home)


func _cancel_request() -> void:
	_request_generation += 1
	if is_instance_valid(_research):
		_research.cancel()
		_research.queue_free()
	_research = null


func _manual_helper() -> void:
	if text_box.text.strip_edges() == "":
		_status.text = NEED_WORDS
		return
	_cancel_request()
	var manual := preload("res://scripts/home/helper_manual_panel.gd").new()
	if world and world.main:
		world.main.open_panel(manual)
	else:
		add_child(manual)
	manual.setup_manual("words", {"text": text_box.text, "plan": HomeStore.load_home().get("plan", {})})
	manual.prepared.connect(func(raw: Dictionary, request: Dictionary):
		_base_revision = str(request.base_revision)
		_request = request
		proposal = TellPolox.clean_helper(raw, HomeStore.load_home().get("plan", {}))
		_show_new()
		_status.text = "Read. Keep it?")


func _exit_tree() -> void:
	_cancel_request()


func _pick_photo() -> void:
	UiKit.pick_picture(self, "A photo of your home", func(path: String):
		var dest := HomeStore.files_dir().path_join("photo_%d.%s" % [Time.get_unix_time_from_system(), path.get_extension().to_lower()])
		DirAccess.copy_absolute(path, dest)
		photo = dest
		_status.text = "Photo added.")
