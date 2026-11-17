extends "res://scripts/ui/screen_panel.gd"
## World Bible: what this world is, and what the player's real life is like.
## Every character reads it, so this is what makes them feel "of" this world.

const PromptBuilder := preload("res://scripts/ai/prompt_builder.gd")

const FIELDS := [
	["setting", "The setting", "Where is this little world? e.g. A moonlit valley of tiny houses where it's always almost autumn."],
	["lore", "Lore & rules", "Anything magical or special? e.g. Lanterns glow brighter when someone is proud of you."],
	["themes", "Themes & vibes", "e.g. Cozy, gentle humor, small brave steps, found family."],
	["life_context", "About your real life", "Whatever you'd like your friends here to know: work, school, people you love, what's hard lately, what you're proud of."],
]

var _name: LineEdit
var _player: LineEdit
var _pronouns: LineEdit
var _birthday: LineEdit
var _edits: Dictionary = {}
var _tokens: Label


func _ready() -> void:
	setup("World Bible", Vector2(1100, 680))
	var v := UiKit.vbox(10)
	body.add_child(UiKit.scroll(v))
	v.add_child(UiKit.para("Your friends read this before every chat. Write as much or as little as you like.", 18, ThemeBuilder.MUTED))
	var w := GameState.world
	_name = UiKit.line_edit("My Pocket World", str(w.get("name", "")))
	v.add_child(UiKit.field_row("World name", _name))
	var p: Dictionary = w.get("player", {})
	_player = UiKit.line_edit("What should friends call you?", str(p.get("name", "")))
	v.add_child(UiKit.field_row("Your name", _player))
	_pronouns = UiKit.line_edit("optional, e.g. she/her, he/him, they/them", str(p.get("pronouns", "")))
	v.add_child(UiKit.field_row("Your pronouns", _pronouns))
	_birthday = UiKit.line_edit("optional, month-day like 07-23 (friends will celebrate)", str(p.get("birthday", "")))
	_birthday.max_length = 5
	v.add_child(UiKit.field_row("Your birthday", _birthday))
	var bible: Dictionary = w.get("world_bible", {})
	for f in FIELDS:
		v.add_child(UiKit.label(f[1], 22, ThemeBuilder.YELLOW))
		var e := UiKit.text_edit(f[2], str(bible.get(f[0], "")), 96)
		e.text_changed.connect(_update_tokens)
		_edits[f[0]] = e
		v.add_child(e)
	var plat := CheckBox.new()
	plat.text = "Platform Mode in this world (Platform Pillars start run-and-jump)"
	plat.button_pressed = preload("res://scripts/platform/platform_save.gd").enabled()
	plat.toggled.connect(func(on): preload("res://scripts/platform/platform_save.gd").set_enabled(on))
	v.add_child(plat)
	var row := UiKit.hbox(12)
	_tokens = UiKit.para("", 18, ThemeBuilder.MUTED)
	_tokens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_tokens)
	row.add_child(UiKit.button("Save", save, 160))
	body.add_child(row)
	_update_tokens()


func _update_tokens() -> void:
	var n := 0
	for k in _edits:
		n += PromptBuilder.estimate_tokens(_edits[k].text)
	_tokens.text = "About %d tokens. Under ~600 keeps free AI tiers happy (longer text is trimmed automatically)." % n


func save() -> void:
	var w := GameState.world
	w["name"] = _name.text.strip_edges() if _name.text.strip_edges() != "" else "My Pocket World"
	w["player"]["name"] = _player.text.strip_edges()
	w["player"]["pronouns"] = _pronouns.text.strip_edges()
	w["player"]["birthday"] = _birthday.text.strip_edges()
	for k in _edits:
		w["world_bible"][k] = _edits[k].text.strip_edges()
	GameState.save_world()
	GameState.notify("World Bible saved ✓")


## Closing also saves, so nothing typed is ever lost.
func on_back() -> bool:
	save()
	close()
	return true
