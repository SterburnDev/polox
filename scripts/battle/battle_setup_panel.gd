extends "res://scripts/ui/screen_panel.gd"
## Right before a battle: who you'll face and how (a template, a battle you saved, or a new one in the
## Battle Maker), with optional friends. Simple: pick and Start.

const BattleData := preload("res://scripts/battle/battle_data.gd")

var director: Node
var foe_id := ""
var mode := "template"             # template | saved | new
var choice := ""                   # template id or saved battle id
var friends: Array = []            # friend ids fighting with you
var _foe_opt: OptionButton
var _list: VBoxContainer
var _foe_ids: Array = []


func setup_battle(battle_director: Node, foe: String = "") -> void:
	director = battle_director
	foe_id = foe
	setup("A friendly battle", Vector2(900, 660))
	var world: Node = director.world
	_foe_ids = world.actors.keys() if not world.actors.is_empty() else Array(SaveManager.list_characters())
	if foe_id == "" and not _foe_ids.is_empty():
		foe_id = str(_foe_ids[0])
	_foe_opt = UiKit.option(_foe_ids.map(func(id): return str(GameState.get_character(str(id)).get("name", id))), maxi(0, _foe_ids.find(foe_id)))
	_foe_opt.item_selected.connect(func(i):
		foe_id = str(_foe_ids[i])
		friends.erase(foe_id)
		_fill())
	body.add_child(UiKit.field_row("Against", _foe_opt, 140))
	var tabs := UiKit.hbox(8)
	for m in [["template", "Template"], ["saved", "Saved"], ["new", "New..."]]:
		var b := UiKit.button(str(m[1]), func():
			mode = str(m[0])
			if mode == "new":
				_open_maker()
			else:
				choice = ""
				_fill(), 150)
		b.name = "Mode_" + str(m[0])
		tabs.add_child(b)
	body.add_child(tabs)
	_list = UiKit.vbox(6)
	body.add_child(UiKit.scroll(_list))
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	if mode == "template":
		for id in BattleData.Spars.ORDER:
			_row(str(BattleData.Spars.NAMES[id]), str(id))
		for id in BattleData.DEMOS:
			_row(str(BattleData.DEMOS[id]) + " (practice encounter)", "demo:" + str(id))
		for id in BattleData.TEMPLATE_ORDER:
			var t: Dictionary = BattleData.TEMPLATES[id]
			_row("%s  (%s)" % [str(t.name), str(BattleData.PRESET_LABELS.get(str(t.preset), ""))], str(id))
	else:
		var saved := BattleData.list()
		if saved.is_empty():
			_list.add_child(UiKit.para("No saved battles yet: make one with New...", 18, ThemeBuilder.MUTED))
		for b in saved:
			_row(str(b.name), str(b.id))
	_list.add_child(UiKit.para("Practice solo, or invite up to two friends. Not now is always free.", 18, ThemeBuilder.MUTED))
	for id in _foe_ids:
		var friend_id := str(id)
		var invite := CheckBox.new()
		invite.text = "Bring " + str(GameState.get_character(friend_id).get("name", "a friend"))
		invite.button_pressed = friend_id in friends
		invite.toggled.connect(func(on):
			if on and friends.size() < 2 and not friend_id in friends:
				friends.append(friend_id)
			elif not on:
				friends.erase(friend_id)
			else:
				invite.set_pressed_no_signal(false))
		_list.add_child(invite)


func _row(label: String, id: String) -> void:
	var row := UiKit.hbox(8)
	var l := UiKit.label(label, 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var go := UiKit.button("Start", func(): start(id), 130)
	go.name = "Start_" + id
	row.add_child(go)
	_list.add_child(row)


## Starts the battle (the template or saved battle `id`) against the chosen friend.
func start(id: String) -> void:
	var foe := GameState.get_character(foe_id)
	var battle: Dictionary
	if id.begins_with("demo:"):
		battle = BattleData.demonstration(id.trim_prefix("demo:"))
	elif mode == "saved":
		battle = BattleData.load_battle(id)
	else:
		battle = BattleData.from_template(id, foe if not foe.is_empty() else {"name": "Someone"})
	if battle.is_empty():
		return
	if not friends.is_empty():
		battle["allow_party"] = true
	var d := director
	var party := friends.duplicate()
	close()
	d.start(battle, party)


func _open_maker() -> void:
	var m: Control = load("res://scripts/battle/battle_maker.gd").new()   # (loaded when wanted, as the director does)
	var d := director
	var foe := GameState.get_character(foe_id)
	close()
	d.world.main.open_panel(m)
	m.setup_maker(d, BattleData.from_template("friendly_spar", foe if not foe.is_empty() else {"name": "Someone"}))
