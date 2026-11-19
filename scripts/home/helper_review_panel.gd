extends "res://scripts/ui/screen_panel.gd"
## The two looks before anything happens with a helper:
##   review_payload(): what leaves Polox, to whom, word for word (and which files go with it), then
##                     Send or Cancel. Nothing is sent until Send.
##   review_changes(): what an answer would change, one checkbox per change; Keep ticked, Not now (the
##                     answer waits, you can come back to it) or Set aside (closed, nothing kept).
## Tags: [AI_HELPER]

signal decided(choice: String, accepted: Array)   # "send" | "cancel" | "keep" | "later" | "dismiss"

var payload_box: TextEdit
var checks: Array = []          # [{"id", "box": CheckBox}]
var _decided := false


func review_payload(title: String, recipient: String, payload: String, attachments: PackedStringArray = PackedStringArray()) -> void:
	setup(title, Vector2(900, 700))
	body.add_child(UiKit.para("This goes to %s. Nothing is sent until you choose Send." % recipient, 18))
	if attachments.is_empty():
		body.add_child(UiKit.para("No files or photos go with it.", 16, ThemeBuilder.MUTED))
	else:
		var names := PackedStringArray()
		for f in attachments:
			names.append(f.get_file())
		body.add_child(UiKit.para("With: " + ", ".join(names) + " (a copy, only for this request).", 16, ThemeBuilder.MUTED))
	body.add_child(UiKit.para("Exactly what's sent:", 16, ThemeBuilder.MUTED))
	payload_box = UiKit.text_edit("", payload, 220)
	payload_box.name = "Payload"
	payload_box.editable = false
	body.add_child(payload_box)
	var row := UiKit.flow_row(8)
	var send := UiKit.button("Send", func(): _decide("send"), 0)
	send.name = "Send"
	row.add_child(send)
	var cancel := UiKit.button("Cancel", func(): _decide("cancel"), 0)
	cancel.name = "Cancel"
	row.add_child(cancel)
	body.add_child(row)


## `items`: [{"id", "label"}]. `grounded` false: the helper ran no web search, said first in yolk.
func review_changes(title: String, items: Array, grounded: bool = true) -> void:
	setup(title, Vector2(900, 700))
	if not grounded:
		body.add_child(UiKit.para("This helper didn't search the web this time, so these are its guesses, not looked-up facts.", 18, ThemeBuilder.YELLOW))
	body.add_child(UiKit.para("Untick anything you don't want. Undo can put it all back.", 16, ThemeBuilder.MUTED))
	var list := UiKit.vbox(4)
	for i in items.size():
		var cb := CheckBox.new()
		cb.name = "Accept_%d" % i
		cb.text = str(items[i].label)
		cb.button_pressed = true
		cb.custom_minimum_size.y = UiKit.touch_target()
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(cb)
		checks.append({"id": str(items[i].id), "box": cb})
	body.add_child(UiKit.scroll(list))
	var row := UiKit.flow_row(8)
	var keep := UiKit.button("Keep ticked", func(): _decide("keep"), 0)
	keep.name = "KeepTicked"
	row.add_child(keep)
	var later := UiKit.button("Not now", func(): _decide("later"), 0)
	later.name = "NotNow"
	row.add_child(later)
	var aside := UiKit.button("Set aside", func(): _decide("dismiss"), 0)
	aside.name = "SetAside"
	aside.tooltip_text = "Close this answer without keeping anything."
	row.add_child(aside)
	body.add_child(row)


func accepted() -> Array:
	var out: Array = []
	for c in checks:
		if (c.box as CheckBox).button_pressed:
			out.append(c.id)
	return out


func _decide(choice: String) -> void:
	if _decided:
		return
	_decided = true
	var ids := accepted()
	close()
	decided.emit(choice, ids)


## Back (or closing the sheet) is the safe answer: nothing sent, nothing kept, the answer waits.
func on_back() -> bool:
	_decide("cancel" if payload_box != null else "later")
	return true


func _exit_tree() -> void:
	if not _decided:
		_decided = true
		decided.emit("cancel" if payload_box != null else "later", [])
