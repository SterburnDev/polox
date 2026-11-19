extends "res://scripts/ui/screen_panel.gd"
## Hang out: pick a friend who's here, then Tea Time, Stargazing or a Photo
## Walk. Friends elsewhere show where they are now (with a button to go there).

const Hangouts := preload("res://scripts/variety/hangouts.gd")
const Routines := preload("res://scripts/variety/routines.gd")

var world: Node
var _picked := ""
var _list: VBoxContainer


func _ready() -> void:
	setup("Hang out", Vector2(900, 620))
	body.add_child(UiKit.para("Spend a little time together. Nothing to win: just a nice moment for the Memory Book.", 18, ThemeBuilder.MUTED))
	_list = UiKit.vbox(10)
	body.add_child(UiKit.scroll(_list))
	refresh()


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var here: Array = []
	for id in world.actors:
		here.append(str(id))
	if _picked == "" and here.size() == 1:
		_picked = here[0]
	if here.is_empty():
		_list.add_child(UiKit.para("Nobody's in this room right now.", 18, ThemeBuilder.CREAM))
	else:
		_list.add_child(UiKit.label("Who?", 22, ThemeBuilder.YELLOW))
		var row := UiKit.flow_row(10)
		for id in here:
			var c := GameState.get_character(id)
			var b := UiKit.button(("✓ " if id == _picked else "") + str(c.get("name", id)), func():
				_picked = id
				refresh(), 160)
			row.add_child(b)
		_list.add_child(row)
	if _picked != "":
		_list.add_child(UiKit.label("What would you like to do?", 22, ThemeBuilder.YELLOW))
		for k in Hangouts.KINDS:
			var kind := str(k[0])
			var r := UiKit.hbox(12)
			r.add_child(UiKit.button(str(k[1]), func(): _go(kind), 200))
			r.add_child(UiKit.para(str(k[2]), 16, ThemeBuilder.MUTED))
			_list.add_child(r)
	var away: Array = []
	for c in GameState.characters.values():
		var where := str(Routines.room_now(c))
		if not world.actors.has(str(c.get("id", ""))) and where != "" and SaveManager.room_exists(where):
			away.append([c, where])
	if not away.is_empty():
		_list.add_child(UiKit.label("Elsewhere right now", 18, ThemeBuilder.MINT))
		for a in away.slice(0, 8):
			var room_id := str(a[1])
			var room_name := str(SaveManager.load_room(room_id).get("name", room_id))
			var r := UiKit.hbox(12)
			r.add_child(UiKit.para("%s is in %s." % [str(a[0].get("name", "")), room_name], 16, ThemeBuilder.CREAM))
			r.add_child(UiKit.button("Go there", func():
				close()
				world.go_to_room(room_id), 130))
			_list.add_child(r)


func _go(kind: String) -> void:
	var friend := _picked
	close()
	world.variety.hangouts.start(kind, friend)
