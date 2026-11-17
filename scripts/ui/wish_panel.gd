extends "res://scripts/ui/screen_panel.gd"
## Stargazing: make a wish. It goes onto your Dreams board (or not: "Just look").

signal wished(text: String)

var _edit: LineEdit
var _sent := false


func _ready() -> void:
	setup("Make a wish", Vector2(720, 320))
	body.add_child(UiKit.para("Under the stars, a wish. It joins your Dreams board, where friends can cheer you on.", 18, ThemeBuilder.MUTED))
	_edit = UiKit.line_edit("I wish...")
	_edit.text_submitted.connect(func(_t): _send(_edit.text))
	body.add_child(_edit)
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button("Make the wish", func(): _send(_edit.text), 200))
	row.add_child(UiKit.button("Just look at the stars", func(): _send(""), 240))
	body.add_child(row)
	_edit.call_deferred("grab_focus")


func _send(text: String) -> void:
	if _sent:
		return
	_sent = true
	wished.emit(text.strip_edges().substr(0, 140))
	close()


func on_back() -> bool:
	_send("")
	return true


func _exit_tree() -> void:
	if not _sent:   # closed some other way: no wish, and the stargazing goes on
		_sent = true
		wished.emit("")
