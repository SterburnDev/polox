extends "res://scripts/ui/screen_panel.gd"
## A simple "Are you sure?" box with two big buttons.

signal answered(yes: bool)


func ask(title: String, message: String, yes_text: String = "Yes", no_text: String = "Cancel") -> void:
	setup(title, Vector2(720, 360))
	var msg := UiKit.para(message, 26)
	msg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(msg)
	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_END
	var yes := UiKit.button(yes_text, func(): _answer(true), 220)
	if no_text == "":   # a notice with one button
		row.add_child(yes)
		body.add_child(row)
		yes.call_deferred("grab_focus")
		return
	var no := UiKit.button(no_text, func(): _answer(false), 180)
	row.add_child(no)
	row.add_child(yes)
	body.add_child(row)
	no.call_deferred("grab_focus")


## A message with a single button (right-click / Q also dismiss it).
func inform(title: String, message: String, button_text: String = "OK") -> void:
	setup(title, Vector2(760, 380))
	var msg := UiKit.para(message, 22)
	msg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(msg)
	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_END
	var ok := UiKit.button(button_text, func(): _answer(true), 200)
	row.add_child(ok)
	body.add_child(row)
	ok.call_deferred("grab_focus")


func _answer(yes: bool) -> void:
	answered.emit(yes)
	close()


func on_back() -> bool:
	_answer(false)
	return true
