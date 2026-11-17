extends ScrollContainer
## My character > "Me": the Player Profile every friend's prompt includes
## (name, pronouns, nicknames, birthday, about me), the link to the Dreams
## board, and your own text-blip voice. Edits apply to GameState.world
## right away; the sheet saves on close.

signal edited

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Voice := preload("res://scripts/characters/voice.gd")
const DreamsBoard := preload("res://scripts/ui/dreams_board.gd")

var open_panel: Callable
var name_edit: LineEdit
var nick_edit: LineEdit
var about_edit: TextEdit
var share_dreams: CheckBox
var _dreams_label: Label


func build() -> void:
	name = "Me"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var p: Dictionary = GameState.world.player
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(v)
	v.add_child(UiKit.para("All of this is optional: leave anything blank you'd rather keep to yourself. Your friends' AI reads it so they know who you are. It stays on this device unless you use an online AI or cloud sync (like Google Drive).", 18, ThemeBuilder.MUTED))
	name_edit = _line(v, "Name", "What should friends call you?", "name")
	name_edit.max_length = 40
	_line(v, "Pronouns", "optional, e.g. she/her, he/him, they/them", "pronouns")
	nick_edit = _line(v, "Nicknames", "optional, comma separated, e.g. Sammy, Captain", "nicknames")
	_line(v, "Birthday", "optional, month-day like 07-23", "birthday")
	v.add_child(UiKit.label("About me", 20, ThemeBuilder.YELLOW))
	about_edit = UiKit.text_edit("A few lines about you: what you love, what you're working on, what makes a good day.", str(p.get("about", "")), 100)
	about_edit.text_changed.connect(func():
		GameState.world.player["about"] = about_edit.text.strip_edges().substr(0, 600)
		edited.emit())
	v.add_child(about_edit)
	v.add_child(UiKit.label("My dreams", 20, ThemeBuilder.YELLOW))
	var dr := UiKit.flow_row(8)
	_dreams_label = UiKit.label("", 18, ThemeBuilder.CREAM)
	_dreams_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dr.add_child(_dreams_label)
	dr.add_child(UiKit.button("Open Dreams board", func(): open_panel.call(DreamsBoard.new()), 230))
	v.add_child(dr)
	share_dreams = CheckBox.new()
	share_dreams.text = "Friends know my dreams and cheer me on"
	share_dreams.button_pressed = bool(p.get("share_dreams", true))
	share_dreams.toggled.connect(func(on):
		GameState.world.player["share_dreams"] = on
		edited.emit())
	v.add_child(share_dreams)
	v.add_child(UiKit.label("My voice", 20, ThemeBuilder.YELLOW))
	v.add_child(UiKit.para("The little blips your own lines make in the chat box.", 18, ThemeBuilder.MUTED))
	var voice := Voice.of_player()
	var snd := UiKit.option(Voice.SOUNDS.map(func(s): return s[1]), maxi(0, Voice.sound_ids().find(str(voice.sound))))
	snd.item_selected.connect(func(i): _set_voice("sound", str(Voice.SOUNDS[i][0])))
	var srow := UiKit.field_row("Sound", snd, 120)
	srow.add_child(UiKit.button("Hear", func(): Voice.preview(self, Voice.of_player()), 90))
	v.add_child(srow)
	var pitch := UiKit.slider(0.6, 1.8, 0.05, float(voice.pitch))
	pitch.value_changed.connect(func(x): _set_voice("pitch", snappedf(x, 0.01)))
	pitch.drag_ended.connect(func(_c): Voice.preview(self, Voice.of_player()))
	v.add_child(UiKit.field_row("Pitch", pitch, 120))
	var speed := UiKit.slider(0.5, 2.0, 0.1, float(voice.speed))
	speed.value_changed.connect(func(x): _set_voice("speed", snappedf(x, 0.01)))
	v.add_child(UiKit.field_row("Talk speed", speed, 120))
	refresh()


func _line(parent: Control, caption: String, hint: String, key: String) -> LineEdit:
	var e := UiKit.line_edit(hint, str(GameState.world.player.get(key, "")))
	e.text_changed.connect(func(t):
		GameState.world.player[key] = t.strip_edges()
		edited.emit())
	parent.add_child(UiKit.field_row(caption, e, 120))
	return e


func _set_voice(key: String, value: Variant) -> void:
	var p: Dictionary = GameState.world.player
	if not p.get("voice") is Dictionary:
		p["voice"] = {}
	p.voice[key] = value
	edited.emit()


func refresh() -> void:
	var n := GameState.dream_list().size()
	_dreams_label.text = ("%d dream%s on your board" % [n, "" if n == 1 else "s"]) if n > 0 else "No dreams on your board yet"
