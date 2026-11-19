extends "res://scripts/ui/screen_panel.gd"
## A short question with a column of big buttons (one thumb, one click). ask(title, text,
## [[label, callable], ...]): pressing a button closes the panel, then runs its action.

signal chosen(index: int)

var buttons: Array = []


func ask(title: String, text: String, options: Array) -> void:
	compact = true   # on a phone: a short sheet, as tall as the question
	setup(title, Vector2(720, 520))
	var msg := UiKit.para(text, 22)
	body.add_child(msg)
	var col := UiKit.vbox(10)
	for i in options.size():
		var opt: Array = options[i]
		var b := UiKit.button(str(opt[0]), func(): _pick(i, opt[1]), 0)
		b.custom_minimum_size.y = 60
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(b)
		buttons.append(b)
	body.add_child(col)
	if not buttons.is_empty():
		(buttons[0] as Button).call_deferred("grab_focus")


func _pick(i: int, action: Callable) -> void:
	chosen.emit(i)
	close()
	if action.is_valid():
		action.call()


func on_back() -> bool:
	close()
	return true
