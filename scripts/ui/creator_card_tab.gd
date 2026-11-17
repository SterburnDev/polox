extends ScrollContainer
## Creator > "Personality": the character card the AI reads (name,
## personality, backstory, quirks, speech style, likes/dislikes, relationship,
## home room), gift tags, and their text-blip voice (sound, pitch, speed).

signal edited

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Synth := preload("res://scripts/core/synth.gd")
const MusicPlayer := preload("res://scripts/world/music_player.gd")
const Voice := preload("res://scripts/characters/voice.gd")
const Items := preload("res://scripts/items/items.gd")
const GiftRules := preload("res://scripts/items/gift_rules.gd")

const TEXT_FIELDS := [
	["personality", "Personality", "e.g. Gentle, curious, secretly competitive at board games.", true],
	["backstory", "Backstory", "Where do they come from? What do they care about?", true],
	["quirks", "Quirks", "e.g. hums when thinking, collects bottle caps", false],
	["speech_style", "Speech style", "e.g. short sentences, lots of puns, says 'indeed'", false],
	["likes", "Likes", "e.g. tea, rainy days, your stories", false],
	["dislikes", "Dislikes", "e.g. loud alarms, cold toast", false],
	["relationship_to_player", "To you they are...", "e.g. your oldest friend, a nosy neighbor, your little sibling", false],
]

var name_edit: LineEdit
var fields: Dictionary = {}
var room_opt: OptionButton
var pitch: HSlider
var speed: HSlider
var sound_opt: OptionButton
var liked_edit: LineEdit
var disliked_edit: LineEdit
var theme_opt: OptionButton
var _themes: PackedStringArray = []
var _room_ids: Array = []
var _blip: AudioStreamPlayer
var _routine_rows: Dictionary = {}   # part -> [OptionButton room, LineEdit activity]


func build(c: Dictionary) -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(v)
	name_edit = UiKit.line_edit("Their name", str(c.get("name", "")))
	name_edit.max_length = 40
	name_edit.text_changed.connect(func(_t): edited.emit())
	v.add_child(UiKit.field_row("Name", name_edit, 120))
	for f in TEXT_FIELDS:
		v.add_child(UiKit.label(f[1], 20, ThemeBuilder.YELLOW))
		var e: Control
		if f[3]:
			e = UiKit.text_edit(f[2], str(c.get(f[0], "")), 84)
			e.text_changed.connect(func(): edited.emit())
		else:
			e = UiKit.line_edit(f[2], str(c.get(f[0], "")))
			e.text_changed.connect(func(_t): edited.emit())
		fields[f[0]] = e
		v.add_child(e)
	v.add_child(UiKit.label("Gift tags", 20, ThemeBuilder.YELLOW))
	v.add_child(UiKit.para("Items tagged with these make them happy (or not). Matches \"book\" with \"books\" too.", 16, ThemeBuilder.MUTED))
	liked_edit = UiKit.line_edit("e.g. tea, sweet, books", ", ".join(GiftRules.tags(c, "liked_tags")))
	liked_edit.text_changed.connect(func(_t): edited.emit())
	v.add_child(UiKit.field_row("Loves", liked_edit, 120))
	disliked_edit = UiKit.line_edit("e.g. loud, spicy", ", ".join(GiftRules.tags(c, "disliked_tags")))
	disliked_edit.text_changed.connect(func(_t): edited.emit())
	v.add_child(UiKit.field_row("Not a fan", disliked_edit, 120))
	room_opt = UiKit.option([])
	for id in SaveManager.list_rooms():
		_room_ids.append(id)
		room_opt.add_item(str(SaveManager.load_room(id).get("name", id)))
	var home := str(c.get("home_room", GameState.current_room_id))
	room_opt.select(maxi(0, _room_ids.find(home)))
	room_opt.item_selected.connect(func(_i): edited.emit())
	v.add_child(UiKit.field_row("Lives in", room_opt, 120))
	sound_opt = UiKit.option(Voice.SOUNDS.map(func(s): return s[1]), maxi(0, Voice.sound_ids().find(str(c.get("voice_sound", "blip")))))
	sound_opt.item_selected.connect(func(_i):
		edited.emit()
		_play_blip())
	var srow := UiKit.field_row("Voice", sound_opt, 120)
	srow.add_child(UiKit.button("Hear", _play_blip, 90))
	v.add_child(srow)
	pitch = UiKit.slider(0.6, 1.6, 0.05, float(c.get("voice_pitch", 1.0)))
	pitch.value_changed.connect(func(_x):
		edited.emit()
		_play_blip())
	v.add_child(UiKit.field_row("Pitch", pitch, 120))
	speed = UiKit.slider(0.5, 2.0, 0.1, float(c.get("voice_speed", 1.0)))
	speed.value_changed.connect(func(_x): edited.emit())
	v.add_child(UiKit.field_row("Talk speed", speed, 120))
	_themes = MusicPlayer.track_names()
	theme_opt = UiKit.option(["(none)"])
	for t in _themes:
		theme_opt.add_item(t)
	theme_opt.select(maxi(0, _themes.find(str(c.get("theme", ""))) + 1))
	theme_opt.item_selected.connect(func(_i): edited.emit())
	theme_opt.tooltip_text = "Plays while you chat. Add music files to PersonalData/audio/music/"
	v.add_child(UiKit.field_row("Theme music", theme_opt, 120))
	_build_routine(v, c)
	_blip = AudioStreamPlayer.new()
	_blip.stream = Synth.get_sound("blip")
	add_child(_blip)


## Daily routine: where they are and what they're doing at each part of the day.
func _build_routine(v: VBoxContainer, c: Dictionary) -> void:
	const Routines := preload("res://scripts/variety/routines.gd")
	v.add_child(UiKit.label("Daily routine", 20, ThemeBuilder.YELLOW))
	v.add_child(UiKit.para("Where they are and what they do through the day (real time). Leave a room on Home to stay in the room they live in.", 16, ThemeBuilder.MUTED))
	for part in Routines.PARTS:
		var e := Routines.entry(c, part)
		var room := UiKit.option(["Home"] + _room_ids.map(func(id): return str(SaveManager.load_room(id).get("name", id))))
		room.select(maxi(0, _room_ids.find(str(e.get("room", ""))) + 1))
		room.item_selected.connect(func(_i): edited.emit())
		room.custom_minimum_size.x = 150
		var act := UiKit.line_edit("e.g. reading by the window", str(e.get("activity", "")))
		act.text_changed.connect(func(_t): edited.emit())
		var row := UiKit.flow_row(6)
		row.add_child(UiKit.label(str(Routines.PART_NAMES[part]), 16, ThemeBuilder.CREAM))
		row.add_child(room)
		row.add_child(act)
		v.add_child(row)
		_routine_rows[part] = [room, act]


func _play_blip() -> void:
	_blip.stream = Voice.stream(str(Voice.SOUNDS[maxi(0, sound_opt.selected)][0]))
	_blip.pitch_scale = pitch.value
	_blip.play()


## Writes the edited fields into `c`.
func apply_to(c: Dictionary) -> void:
	c["name"] = name_edit.text.strip_edges()
	for k in fields:
		c[k] = fields[k].text.strip_edges()
	if room_opt.selected >= 0 and room_opt.selected < _room_ids.size():
		c["home_room"] = _room_ids[room_opt.selected]
	c["voice_pitch"] = snappedf(pitch.value, 0.01)
	c["voice_speed"] = snappedf(speed.value, 0.01)
	c["voice_sound"] = str(Voice.SOUNDS[maxi(0, sound_opt.selected)][0])
	c["liked_tags"] = Items.parse_tags(liked_edit.text)
	c["disliked_tags"] = Items.parse_tags(disliked_edit.text)
	c["theme"] = _themes[theme_opt.selected - 1] if theme_opt.selected > 0 else ""
	const Routines := preload("res://scripts/variety/routines.gd")
	for part in _routine_rows:
		var r: Array = _routine_rows[part]
		var sel: int = (r[0] as OptionButton).selected
		Routines.set_entry(c, part, str(_room_ids[sel - 1]) if sel > 0 and sel - 1 < _room_ids.size() else "", (r[1] as LineEdit).text)
