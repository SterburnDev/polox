extends "res://scripts/ui/screen_panel.gd"
## Title > Add-ons: every add-on found, on or off (kept across launches), what each one changes, anything
## wrong with its files (the game's own is used instead), and its scripts, which run only once trusted.
## "Open the folder" opens where add-ons go; "Look again" finds new ones.
## Tags: [ADDONS]

const Addons := preload("res://scripts/core/addons.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")

var _list: VBoxContainer
var main: Node   # set by main.gd (music follows a change)


func _ready() -> void:
	setup("Add-ons", Vector2(980, 660))
	var v := UiKit.vbox(10)
	body.add_child(UiKit.scroll(v))
	v.add_child(UiKit.para("Add-ons change Polox's pictures, music, sounds, tiles or words. Turning one off puts the game's own back; your worlds stay as they are.", 20, ThemeBuilder.MUTED))
	var row := UiKit.flow_row(10)
	if not (OS.has_feature("web") or OS.has_feature("android")):
		var open := UiKit.button("Open the folder", func(): OS.shell_open(Addons.open_folder_path()))
		open.name = "OpenAddonsFolder"
		row.add_child(open)
	var again := UiKit.button("Look again", func():
		Addons.refresh()
		_changed())
	again.name = "LookAgain"
	row.add_child(again)
	v.add_child(row)
	var where := UiKit.para("Folder: " + Addons.open_folder_path(), 16, Color(ThemeBuilder.MUTED, 0.85))
	where.name = "AddonsFolder"
	v.add_child(where)
	var built: Dictionary = Addons.builtin()
	if not built.is_empty():   # (assets/local: always on, under every add-on)
		var b := UiKit.para("Built in: " + str(built.description), 16, Color(ThemeBuilder.MUTED, 0.85))
		b.name = "BuiltIn"
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(b)
	_list = UiKit.vbox(12)
	_list.name = "AddonList"
	v.add_child(_list)
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		_list.remove_child(c)   # (now: the new cards take the same names)
		c.queue_free()
	var found := Addons.found()
	if found.is_empty():
		_list.add_child(UiKit.para("No add-ons yet. Put an add-on's folder (with its addon.json) in the folder above, then press Look again.", 20))
		return
	for e in found:
		_list.add_child(_card(e))


func _card(e: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.name = "Addon_" + str(e.id)
	box.add_theme_stylebox_override("panel", ThemeBuilder.box(Color(ThemeBuilder.PANEL, 0.9), Color(ThemeBuilder.CREAM, 0.25), 1, 10, 12))
	var v := UiKit.vbox(6)
	box.add_child(v)
	var top := UiKit.hbox(12)
	var title := UiKit.label("%s  %s" % [e.name, ("v" + str(e.version)) if str(e.version) != "" else ""], 24, ThemeBuilder.YELLOW)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # its own name, as written
	top.add_child(title)
	var usable := not e.has("duplicate") and not (e.manifest as Dictionary).is_empty()
	var on := CheckButton.new()
	on.name = "Enabled"
	on.text = "On"
	on.button_pressed = Addons.is_enabled(e.id)
	on.disabled = not usable
	on.toggled.connect(func(p: bool): _toggle(e, p))
	top.add_child(on)
	v.add_child(top)
	if str(e.description) != "":
		var d := UiKit.para(str(e.description), 18)
		d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(d)
	var what := _summary(e)
	if what != "":
		v.add_child(UiKit.para("Changes: " + what, 16, ThemeBuilder.MUTED))
	var scripts := Addons.script_files(e.id)
	if not scripts.is_empty():
		var trusted := Addons.is_trusted(e.id)
		var srow := UiKit.flow_row(10)
		var state := "Scripts: %s. %s" % [", ".join(scripts), ("Trusted: they run while it's on." if trusted else "Not trusted: they don't run.")]
		srow.add_child(UiKit.para(state, 16, ThemeBuilder.CREAM if trusted else ThemeBuilder.MUTED))
		var tb := UiKit.button("Stop trusting" if trusted else "Trust scripts…", func(): _trust(e, not trusted))
		tb.name = "TrustScripts"
		srow.add_child(tb)
		v.add_child(srow)
	for p in Addons.problems(e.id):
		var l := UiKit.para("⚠ " + str(p), 16, Color("#ffb86b"))
		l.name = "Problem"
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(l)
	if Addons.is_enabled(e.id) and Addons.problems(e.id).is_empty():
		v.add_child(UiKit.para("✓ On, every file found.", 16, Color("#8fe3b0")))
	return box


## What an add-on changes, from its addon.json alone.
static func _summary(e: Dictionary) -> String:
	var ov: Variant = (e.manifest as Dictionary).get("overrides", {})
	if not ov is Dictionary:
		return ""
	var parts: Array = []
	if ov.get("music") is Dictionary and not ov.music.is_empty():
		var cues: Array = []
		for k in ov.music:
			cues.append(str(Addons.CUE_NAMES.get(str(k), str(k))))
		parts.append("music (%s)" % ", ".join(cues))
	if ov.get("songs") is Array and not ov.songs.is_empty():
		parts.append("%d songs" % ov.songs.size())
	if ov.get("textures") is Dictionary and not ov.textures.is_empty():
		parts.append("pictures (%s)" % ", ".join(ov.textures.keys()))
	if ov.get("sfx") is Dictionary and not ov.sfx.is_empty():
		parts.append("%d sounds" % ov.sfx.size())
	if ov.get("tiles") is Dictionary and not ov.tiles.is_empty():
		parts.append("%d tiles" % ov.tiles.size())
	if ov.get("text") is Dictionary and not ov.text.is_empty():
		parts.append("words (%s)" % ", ".join(ov.text.keys().slice(0, 4)) + ("…" if ov.text.size() > 4 else ""))
	if ov.get("scripts") is Array and not ov.scripts.is_empty():
		parts.append("scripts")
	return ", ".join(parts)


func _toggle(e: Dictionary, on: bool) -> void:
	Addons.set_enabled(e.id, on)
	GameState.notify("%s is %s." % [e.name, "on" if on else "off"])
	_changed()


func _trust(e: Dictionary, on: bool) -> void:
	if not on:
		Addons.set_trusted(e.id, false)
		_changed()
		return
	var c := ConfirmPanel.new()
	var host: Node = main if main else get_parent()
	if host.has_method("open_panel"):
		host.open_panel(c)
	else:
		get_parent().add_child(c)
	c.ask("Trust these scripts?", "%s wants to run %s. A script can do anything Polox can, including reading and changing your worlds. Trust it only if you trust where it came from. If a script changes, you'll be asked again." % [e.name, ", ".join(Addons.script_files(e.id))], "Trust and run", "Cancel")
	c.answered.connect(func(yes: bool):
		if yes:
			Addons.set_trusted(e.id, true)
		_changed())


func _changed() -> void:
	if main and main.has_method("refresh_music"):
		main.refresh_music()
	_fill()
