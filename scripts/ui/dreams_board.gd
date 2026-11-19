extends "res://scripts/ui/screen_panel.gd"
## Dreams & Desires: the real-life hopes your friends know about and cheer
## on. Statuses: dreaming -> working on it -> done (a celebration!).

const STATUSES := [["dreaming", "Dreaming"], ["working_on_it", "Working on it"], ["done", "Done ★"]]

var _list: VBoxContainer
var _new: LineEdit


func _ready() -> void:
	setup("Dreams & Desires", Vector2(1080, 660))
	body.add_child(UiKit.para("Big or small: learn guitar, call grandma more, see the ocean, finish the novel. Your friends will cheer you on.", 18, ThemeBuilder.MUTED))
	var add := UiKit.hbox(8)
	_new = UiKit.line_edit("I dream of...")
	_new.max_length = 160
	_new.text_submitted.connect(func(_t): _add())
	add.add_child(_new)
	add.add_child(UiKit.button("Add dream", _add, 160))
	body.add_child(add)
	_list = UiKit.vbox(8)
	body.add_child(UiKit.scroll(_list))
	_fill()
	_new.call_deferred("grab_focus")


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var dreams := GameState.dream_list()
	if dreams.is_empty():
		_list.add_child(UiKit.label("No dreams yet. What would make future-you smile?", 20, ThemeBuilder.MUTED))
	for i in dreams.size():
		var d: Dictionary = dreams[i]
		var row := UiKit.hbox(6)
		var done := str(d.get("status", "")) == "done"
		var e := UiKit.line_edit("", str(d.get("text", "")))
		if done:
			e.add_theme_color_override("font_color", ThemeBuilder.MINT)
		e.text_changed.connect(func(t):
			d["text"] = t.strip_edges()
			GameState.save_dreams())
		row.add_child(e)
		for s in STATUSES:
			var b := UiKit.button(s[1], func(): _set_status(d, s[0]), 120 if s[0] != "working_on_it" else 170)
			b.toggle_mode = true
			b.set_pressed_no_signal(str(d.get("status", "dreaming")) == s[0])
			b.focus_mode = Control.FOCUS_NONE
			row.add_child(b)
		row.add_child(UiKit.button("✕", func(): _remove(i), 56))
		_list.add_child(row)


func _add() -> void:
	var t := _new.text.strip_edges()
	if t == "":
		return
	GameState.add_dream(t)
	GameState.add_moment("A new dream", "You wrote down a dream: \"%s\"" % t)
	_new.text = ""
	_fill()


func _set_status(d: Dictionary, status: String) -> void:
	var was := str(d.get("status", ""))
	d["status"] = status
	if status == "done" and was != "done":
		d["done_at"] = Time.get_datetime_string_from_system(false, false)
		d["celebrated_by"] = []
		GameState.add_moment("Dream come true! ★", "You did it: \"%s\"" % d.get("text", ""))
		GameState.notify("★ You did it! Your friends will want to hear about this.")
	GameState.save_dreams()
	_fill()


func _remove(i: int) -> void:
	var dreams := GameState.dream_list()
	if i < dreams.size():
		dreams.remove_at(i)
		GameState.save_dreams()
	_fill()
