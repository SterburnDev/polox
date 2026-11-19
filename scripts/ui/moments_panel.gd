extends "res://scripts/ui/screen_panel.gd"
## Daily Moments: today's, your own (add a line, pick a kind: it joins the
## deck), dates you celebrate, and Memory Echo (moments from your own past;
## off unless you switch it on). Advanced: the Time Machine (testing only).

const Moments := preload("res://scripts/variety/moments.gd")
const Deck := preload("res://scripts/variety/moments_deck.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const Clock := preload("res://scripts/variety/clock.gd")

var _v: VBoxContainer
var _kind: OptionButton
var _text: LineEdit
var _date: LineEdit
var _cname: LineEdit
var _advanced := false


func _ready() -> void:
	setup("Daily Moments", Vector2(1000, 660))
	_v = UiKit.vbox(8)
	body.add_child(UiKit.scroll(_v))
	refresh()


func refresh() -> void:
	for c in _v.get_children():
		c.queue_free()
	var t := Moments.today()
	_v.add_child(UiKit.label("Today (%s)" % str(t.get("date", "")), 22, ThemeBuilder.YELLOW))
	for m in t.get("moments", []):
		_v.add_child(UiKit.para("%s: %s" % [Deck.KIND_NAMES.get(str(m.kind), str(m.kind)), str(m.text)], 18, ThemeBuilder.CREAM))
	_v.add_child(UiKit.label("Add your own", 22, ThemeBuilder.YELLOW))
	_v.add_child(UiKit.para("Write a little happening. Use {character}, {other}, {room}, {dream} or {you} and the world fills them in.", 16, ThemeBuilder.MUTED))
	var row := UiKit.flow_row(8)
	var kinds := Array(Deck.KINDS).filter(func(k): return k != "echo")
	_kind = UiKit.option(kinds.map(func(k): return Deck.KIND_NAMES[k]))
	row.add_child(_kind)
	_text = UiKit.line_edit("e.g. {character} found a song stuck in their head all day.")
	_text.custom_minimum_size.x = 460
	row.add_child(_text)
	row.add_child(UiKit.button("Add", func():
		if Moments.add_custom(str(kinds[_kind.selected]), _text.text).is_empty():
			GameState.notify("Write something first.")
		refresh(), 90))
	_v.add_child(row)
	for c in VarietySave.data().custom:
		var r := UiKit.flow_row(8)
		r.add_child(UiKit.para("%s: %s" % [Deck.KIND_NAMES.get(str(c.get("kind", "")), ""), str(c.get("text", ""))], 16, ThemeBuilder.CREAM))
		var cid := str(c.get("id", ""))
		r.add_child(UiKit.button("Remove", func():
			Moments.remove_custom(cid)
			refresh(), 100))
		_v.add_child(r)
	_v.add_child(UiKit.label("Days you celebrate", 22, ThemeBuilder.YELLOW))
	var crow := UiKit.flow_row(8)
	_date = UiKit.line_edit("MM-DD")
	_date.max_length = 5
	_date.custom_minimum_size.x = 100
	crow.add_child(_date)
	_cname = UiKit.line_edit("e.g. Mochi's birthday, Pancake Day")
	crow.add_child(_cname)
	crow.add_child(UiKit.button("Add", func():
		var d := _date.text.strip_edges()
		if d.length() == 5 and d[2] == "-" and _cname.text.strip_edges() != "":
			(VarietySave.data().celebrations as Array).append({"date": d, "name": _cname.text.strip_edges().substr(0, 40)})
			VarietySave.save()
		refresh(), 90))
	_v.add_child(crow)
	for c in VarietySave.data().celebrations:
		_v.add_child(UiKit.para("★ %s  %s" % [str(c.get("date", "")), str(c.get("name", ""))], 16, ThemeBuilder.CREAM))
	var echo := CheckBox.new()
	echo.text = "Memory Echo: sometimes bring back a line from my own Memory Book (stays on this device)"
	echo.button_pressed = bool(VarietySave.data().get("echo", false))
	echo.toggled.connect(func(on):
		VarietySave.data()["echo"] = on
		VarietySave.save())
	_v.add_child(echo)
	var more := UiKit.button(("▼ " if _advanced else "▶ ") + "Advanced: Time Machine (for testing)", func():
		_advanced = not _advanced
		refresh(), 0)
	_v.add_child(more)
	if _advanced:
		var trow := UiKit.flow_row(8)
		trow.add_child(UiKit.label("Pretend it's %d day(s) later" % int(Clock.offset_days), 16, ThemeBuilder.MUTED))
		trow.add_child(UiKit.button("+1 day", func():
			Clock.advance(1.0)
			_restart_day(), 100))
		trow.add_child(UiKit.button("Back to today", func():
			Clock.reset()
			_restart_day(), 160))
		_v.add_child(trow)


func _restart_day() -> void:
	var main := get_tree().current_scene
	if main and main.get("game") and main.game.get("variety"):
		main.game.variety.begin_day()
	refresh()
