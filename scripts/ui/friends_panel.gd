extends "res://scripts/ui/screen_panel.gd"
## Friends: pick a character to see how close you are, what they remember
## about you (editable memory notes) and their running summary of your story;
## their own AI model, chat backups, and friends brought over from other apps.

signal edit_character(id: String)
signal new_character

const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")
const GiftRules := preload("res://scripts/items/gift_rules.gd")
const ChatBackup := preload("res://scripts/ai/chat_backup.gd")
const ChoicePanel := preload("res://scripts/ui/choice_panel.gd")

var _list: VBoxContainer
var _detail: VBoxContainer
var _current := ""
var _notes_box: VBoxContainer
var _new_note: LineEdit
var _summary: TextEdit


func _ready() -> void:
	setup("Friends", Vector2(1160, 680))
	var row := UiKit.columns(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	_list = UiKit.vbox(8)
	var left := UiKit.scroll(_list)
	left.custom_minimum_size.x = 280
	left.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(left)
	_detail = UiKit.vbox(10)
	var right := UiKit.scroll(_detail)
	right.size_flags_stretch_ratio = 2.0   # stacked on a phone: the details get most of the height
	row.add_child(right)
	_fill_list()


func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for id in GameState.characters:
		var c: Dictionary = GameState.characters[id]
		var b := UiKit.button(str(c.get("name", id)), func(): show_character(id))
		var tex := SaveManager.load_texture(SaveManager.expression_path(c, "neutral"))
		if tex:
			b.icon = tex
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_list.add_child(b)
	_list.add_child(UiKit.button("+ New friend", func():
		close()
		new_character.emit()))
	var bring := UiKit.button("+ Bring a friend", func():
		var shell := get_tree().current_scene
		if shell and shell.has_method("open_panel"):
			var p: Control = preload("res://scripts/ui/character_import_panel.gd").new()
			p.imported.connect(func(new_id: String):
				_fill_list()
				show_character(new_id))
			shell.open_panel(p))
	bring.name = "BringFriend"
	bring.tooltip_text = "From Character.AI, Chai or another app"
	_list.add_child(bring)
	_list.add_child(UiKit.button("Friendship web", func():
		var shell := get_tree().current_scene
		if shell and shell.has_method("open_panel"):
			shell.open_panel(preload("res://scripts/ui/friendship_web.gd").new())))
	if _current == "" and not GameState.characters.is_empty():
		show_character(GameState.characters.keys()[0])


func show_character(id: String) -> void:
	_save_summary()
	_current = id
	for c in _detail.get_children():
		c.queue_free()
	var c := GameState.get_character(id)
	var head := UiKit.hbox(12)
	head.add_child(UiKit.label(str(c.get("name", id)), 32, ThemeBuilder.YELLOW))
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.button("Edit look & personality", func():
		close()
		edit_character.emit(id), 280))
	_detail.add_child(head)
	var rel: Dictionary = c.get("relationship", {})
	var mood: Dictionary = c.get("mood", {})
	_detail.add_child(UiKit.para("Closeness %d/100  •  Trust %d/100  •  Happy %d%%  •  Energy %d%%  •  Lonely %d%%" % [
		int(rel.get("affinity", 0)), int(rel.get("trust", 0)), int(float(mood.get("happiness", 0)) * 100),
		int(float(mood.get("energy", 0)) * 100), int(float(mood.get("loneliness", 0)) * 100)], 19, ThemeBuilder.MUTED))
	var liked := GiftRules.tags(c, "liked_tags")
	var disliked := GiftRules.tags(c, "disliked_tags")
	_detail.add_child(UiKit.para("Loves gifts tagged: %s%s" % [", ".join(liked) if not liked.is_empty() else "(nothing set yet)", ("  •  not a fan of: " + ", ".join(disliked)) if not disliked.is_empty() else ""], 18, ThemeBuilder.MUTED))
	var got: Array = c.get("gifts_received", []) if c.get("gifts_received") is Array else []
	if not got.is_empty():
		var bits := PackedStringArray()
		for g in got.slice(maxi(0, got.size() - 5)):
			bits.append("%s (%s)" % [g.get("name", "?"), GiftRules.HOW_WORDS.get(str(g.get("how", "")), "kept it")])
		_detail.add_child(UiKit.para("Recent gifts from you: " + ", ".join(bits), 18, ThemeBuilder.MUTED))
	_detail.add_child(UiKit.label("Things %s remembers about you" % c.get("name", ""), 22, ThemeBuilder.YELLOW))
	_notes_box = UiKit.vbox(6)
	_detail.add_child(_notes_box)
	_fill_notes()
	var add_row := UiKit.hbox(8)
	_new_note = UiKit.line_edit("Add something they should remember...")
	_new_note.text_submitted.connect(func(_t): _add_note())
	add_row.add_child(_new_note)
	add_row.add_child(UiKit.button("Add", _add_note, 100))
	_detail.add_child(add_row)
	_detail.add_child(UiKit.label("Your story so far (their running summary)", 22, ThemeBuilder.YELLOW))
	_summary = UiKit.text_edit("Nothing yet. After ~20 messages your friend starts a summary here.", str(c.get("summary", "")), 120)
	_detail.add_child(_summary)
	# Their own AI model (on a PC: a phone's friends use whatever its PC chose for them).
	if not str(AIClient.config.get("preset", "mock")) in ["mock", "pc"]:
		var model_opt := UiKit.option(["Same as Settings"])
		model_opt.name = "FriendModel"
		var own := str(c.get("ai_model", ""))
		if own != "":
			model_opt.add_item(own)
			model_opt.select(1)
		model_opt.item_selected.connect(func(i: int):
			var ch := GameState.get_character(id)
			ch["ai_model"] = "" if i == 0 else model_opt.get_item_text(i)
			GameState.save_character(ch))
		_detail.add_child(UiKit.field_row("Their AI model", model_opt, 220))
		_fill_models(model_opt, own)
	var keep := UiKit.flow_row(10)
	keep.add_child(UiKit.button("Back up chats", func():
		var p := ChatBackup.backup("manual")
		GameState.notify("Chats backed up." if p != "" else "Couldn't back up the chats."), 220))
	keep.add_child(UiKit.button("Restore chats", _restore_chats, 220))
	_detail.add_child(keep)


## The models the AI can use (Ollama: what's installed, your own models too), added as they arrive.
func _fill_models(opt: OptionButton, own: String) -> void:
	var models: PackedStringArray = await AIClient.list_models()
	if not is_instance_valid(opt) or not opt.is_inside_tree():
		return
	for m in models:
		if m != own:
			opt.add_item(m)


## A backup to bring back: merged with what's here (a backup of the present comes first).
func _restore_chats() -> void:
	var backups := ChatBackup.list_backups()
	var shell := get_tree().current_scene
	if backups.is_empty():
		GameState.notify("No chat backups yet.")
		return
	if shell == null or not shell.has_method("open_panel"):
		return
	var options: Array = []
	for b in backups.slice(0, 8):
		var path := str(b.path)
		var when := Time.get_datetime_string_from_unix_time(int(b.made_unix) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60, true)
		options.append(["%s (%s)" % [when.left(16), b.kind], func():
			var r := ChatBackup.restore(path)
			if not r.ok:
				GameState.notify(str(r.error))
				return
			GameState.notify("Restored %d friend%s, %d message%s back.%s" % [r.friends, "" if int(r.friends) == 1 else "s", r.added, "" if int(r.added) == 1 else "s",
				(" Not in this world: " + ", ".join(r.skipped)) if not (r.skipped as Array).is_empty() else ""])
			if _current != "":
				show_character(_current)])
	var panel: Control = ChoicePanel.new()
	shell.open_panel(panel)
	panel.ask("Restore chats", "Merges with the chats here. Nothing is erased.", options)


func _fill_notes() -> void:
	for n in _notes_box.get_children():
		n.queue_free()
	var notes: Array = GameState.get_character(_current).get("memory_notes", [])
	if notes.is_empty():
		_notes_box.add_child(UiKit.label("(nothing yet. Tell them about your life!)", 18, ThemeBuilder.MUTED))
	for i in notes.size():
		var r := UiKit.hbox(8)
		var e := UiKit.line_edit("", str(notes[i]))
		var idx := i
		e.text_changed.connect(func(t): _edit_note(idx, t))
		r.add_child(e)
		r.add_child(UiKit.button("Forget", func(): _remove_note(idx), 120))
		_notes_box.add_child(r)


func _edit_note(i: int, text: String) -> void:
	var c := GameState.get_character(_current)
	if i < c.memory_notes.size():
		c.memory_notes[i] = text
		GameState.save_character(c)


func _remove_note(i: int) -> void:
	var c := GameState.get_character(_current)
	if i < c.memory_notes.size():
		c.memory_notes.remove_at(i)
		GameState.save_character(c)
		_fill_notes()


func _add_note() -> void:
	var t := _new_note.text.strip_edges()
	if t == "":
		return
	var c := GameState.get_character(_current)
	c.memory_notes.append(t)
	GameState.save_character(c)
	_new_note.text = ""
	_fill_notes()


func _save_summary() -> void:
	if _current == "" or _summary == null or not is_instance_valid(_summary):
		return
	var c := GameState.get_character(_current)
	if str(c.get("summary", "")) != _summary.text:
		c["summary"] = _summary.text.strip_edges()
		GameState.save_character(c)


func on_back() -> bool:
	_save_summary()
	close()
	return true
