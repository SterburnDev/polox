extends "res://scripts/ui/screen_panel.gd"
## Memory Book: little moments worth keeping, saved automatically (first
## chats, dreams, finds) or by hand ("★ Save" in a chat, or write one here).
## "Your home's story" (the Light World) is read from my_home on this PC: when the house was built,
## its permits, what rooms used to be, the memories you gave the Survey. It's never copied into a
## world, so it never syncs or exports with one.

var _list: VBoxContainer
var _title: LineEdit
var _text: LineEdit


func _ready() -> void:
	setup("Memory Book", Vector2(1080, 660))
	var add := UiKit.flow_row(8)
	_title = UiKit.line_edit("Title, e.g. Rainy day tea")
	_title.custom_minimum_size.x = 260
	_title.size_flags_horizontal = Control.SIZE_FILL
	add.add_child(_title)
	_text = UiKit.line_edit("What happened?")
	_text.text_submitted.connect(func(_t): _write())
	add.add_child(_text)
	add.add_child(UiKit.button("Save moment", _write, 170))
	body.add_child(add)
	_list = UiKit.vbox(10)
	body.add_child(UiKit.scroll(_list))
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var moments: Array = GameState.journal.get("moments", []).duplicate()
	moments.reverse()
	if moments.is_empty():
		_list.add_child(UiKit.label("Empty, for now.", 20, ThemeBuilder.MUTED))
	_home_story()
	var last_day := ""
	for m in moments:
		var day := str(m.get("ts", "")).substr(0, 10)
		if day != last_day:
			_list.add_child(UiKit.label("— %s —" % day, 20, ThemeBuilder.YELLOW))
			last_day = day
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, Color(ThemeBuilder.CREAM, 0.35), 2, 10, 8))
		var row := UiKit.hbox(10)
		card.add_child(row)
		var c := GameState.get_character(str(m.get("character", "")))
		var tex := SaveManager.load_texture(SaveManager.expression_path(c, "happy")) if not c.is_empty() else null
		if tex == null and not c.is_empty():
			tex = SaveManager.load_texture(SaveManager.expression_path(c, "neutral"))
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = tex
		row.add_child(icon)
		var col := UiKit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tag := " ★" if str(m.get("kind", "")) == "manual" else ""
		col.add_child(UiKit.label(str(m.get("title", "")) + tag, 22, ThemeBuilder.CREAM))
		col.add_child(UiKit.para(str(m.get("text", "")), 18, ThemeBuilder.MUTED))
		row.add_child(col)
		if str(m.get("photo", "")) != "":
			var pic := TextureRect.new()
			pic.custom_minimum_size = Vector2(192, 108)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			pic.texture = SaveManager.load_texture(str(m.photo))
			pic.tooltip_text = str(m.photo)
			row.add_child(pic)
		var id := str(m.get("id", ""))
		row.add_child(UiKit.button("✕", func(): _remove(id), 56))
		_list.add_child(card)


## Pages from your real home's history (kept in my_home, shown here, never copied).
func _home_story() -> void:
	var home: Dictionary = load("res://scripts/home/home_store.gd").load_home()
	var t: Array = (home.get("timeline", []) as Array).filter(func(e): return str(e.get("kind", "")) in ["built", "permit", "history", "renovation", "used_to_be", "memory"])
	if t.is_empty():
		return
	_list.add_child(UiKit.label("— Your home's story —", 20, ThemeBuilder.YELLOW))
	for i in t.size():
		var e: Dictionary = t[i]
		var card := PanelContainer.new()
		card.name = "HomePage_%d" % i
		card.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, Color("#ffe9a8", 0.45), 2, 10, 8))
		var col := UiKit.vbox(2)
		card.add_child(col)
		var when := str(int(e.year)) if int(e.get("year", 0)) > 0 else ""
		var title: String = {"built": "Built", "permit": "Changed", "history": "Long ago", "renovation": "Changed", "used_to_be": "It used to be...", "memory": "A memory"}.get(str(e.kind), "")
		col.add_child(UiKit.label(("☀ %s %s" % [title, when]).strip_edges(), 20, ThemeBuilder.CREAM))
		col.add_child(UiKit.para(str(e.get("text", "")), 18, ThemeBuilder.MUTED))
		_list.add_child(card)


func _write() -> void:
	var t := _title.text.strip_edges()
	var body_text := _text.text.strip_edges()
	if t == "" and body_text == "":
		return
	GameState.add_moment(t if t != "" else "A moment", body_text, "", "manual")
	_title.text = ""
	_text.text = ""
	_fill()


func _remove(id: String) -> void:
	var moments: Array = GameState.journal.get("moments", [])
	for i in moments.size():
		if str(moments[i].get("id", "")) == id:
			moments.remove_at(i)
			break
	SaveManager.save_journal(GameState.journal)
	_fill()
