extends "res://scripts/ui/screen_panel.gd"
## Bring a friend from Character.AI, Chai or another app: paste their card or their description (or,
## on a PC, pick a .json / .png card). They become a friend here, talking through Polox's own AI.
## Nothing is sent anywhere by bringing them in (character_import.gd).

signal imported(id: String)

const CharacterImport := preload("res://scripts/ai/character_import.gd")
const FROM := ["Character.AI", "Chai", "another app"]

var _text: TextEdit
var _name: LineEdit
var _from: OptionButton
var _note: Label
var _picked: Dictionary = {}   # a card read from a file (with its picture)


func _ready() -> void:
	setup("Bring a friend", Vector2(900, 640))
	body.add_child(UiKit.para("Paste their card, or their name, greeting and description.", 20, ThemeBuilder.CREAM))
	_from = UiKit.option(FROM, 0)
	body.add_child(UiKit.field_row("From", _from, 160))
	_name = UiKit.line_edit("Name (if the text has none)")
	body.add_child(UiKit.field_row("Name", _name, 160))
	_text = UiKit.text_edit("Name: Ava\nGreeting: Oh, hi! ...\nDescription: ...", "", 220)
	_text.text_changed.connect(func(): _picked = {})
	body.add_child(_text)
	_note = UiKit.para("", 18, ThemeBuilder.MUTED)
	body.add_child(_note)
	var row := UiKit.flow_row(10)
	if not OS.has_feature("web") and not OS.has_feature("android"):
		row.add_child(UiKit.button("Choose a card file...", _choose_file, 260))
	var go := UiKit.button("Bring them in", _bring, 220)
	go.name = "BringIn"
	row.add_child(go)
	body.add_child(row)


func _choose_file() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json, *.png ; Character cards"])
	fd.use_native_dialog = true
	fd.title = "Pick a character card"
	fd.file_selected.connect(func(path):
		var r := CharacterImport.from_file(path)
		fd.queue_free()
		if not r.ok:
			_note.text = str(r.error)
			return
		_picked = r.card
		_text.text = "Name: %s\nGreeting: %s\nDescription: %s" % [r.card.name, r.card.get("greeting", ""), r.card.get("personality", "")]
		_picked = r.card   # (the text change above cleared it)
		_note.text = "Read %s's card%s." % [r.card.name, " and picture" if r.card.has("picture") else ""])
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))


## Reads the card (or the text), makes the friend, says so.
func bring() -> String:
	var r: Dictionary = {"ok": true, "card": _picked} if not _picked.is_empty() else CharacterImport.from_text(_text.text, FROM[_from.selected])
	if not r.ok:
		_note.text = str(r.error)
		return ""
	var card: Dictionary = r.card
	card["from"] = FROM[_from.selected]
	if str(card.get("name", "")).strip_edges() == "" and _name.text.strip_edges() == "":
		_note.text = "What's their name?"
		_name.grab_focus()
		return ""
	var id := CharacterImport.create_friend(card, _name.text)
	if id == "":
		_note.text = "Couldn't save them. Is the save folder read-only?"
		return ""
	GameState.notify("%s is here, from %s." % [GameState.get_character(id).get("name", id), card.from])
	imported.emit(id)
	close()
	return id


func _bring() -> void:
	bring()
