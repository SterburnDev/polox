extends "res://scripts/ui/screen_panel.gd"
## Edit a world's card: name, emoji, colour, notes, tags, cover picture and
## its autosave settings.

signal saved

const Slots := preload("res://scripts/core/slots.gd")

var slot_id := ""
var _m: Dictionary
var _name: LineEdit
var _emoji: LineEdit
var _notes: TextEdit
var _tags: LineEdit
var _accent := ""
var _swatch: ColorRect
var _cover_label: Label
var _auto_on: CheckBox
var _interval: SpinBox
var _on_room: CheckBox
var _on_quit: CheckBox
var _keep: SpinBox


func _ready() -> void:
	_m = Slots.meta(slot_id)
	_accent = str(_m.accent)
	setup("Edit card", Vector2(960, 700))
	var v := UiKit.vbox(10)
	body.add_child(UiKit.scroll(v))
	_name = UiKit.line_edit("World name", str(_m.name))
	_name.max_length = 60
	v.add_child(UiKit.field_row("Name", _name, 150))
	var erow := UiKit.hbox(4)
	_emoji = UiKit.line_edit("", str(_m.emoji))
	_emoji.max_length = 4
	_emoji.custom_minimum_size.x = 90
	_emoji.size_flags_horizontal = Control.SIZE_FILL
	erow.add_child(_emoji)
	var eg := GridContainer.new()
	eg.columns = 12
	eg.add_theme_constant_override("h_separation", 2)
	for e in Slots.EMOJIS:
		var b := UiKit.button(e, func(): _emoji.text = e, 48)
		b.custom_minimum_size = Vector2(48, 48)
		b.focus_mode = Control.FOCUS_NONE
		eg.add_child(b)
	erow.add_child(eg)
	v.add_child(UiKit.field_row("Emoji", erow, 150))
	var crow := UiKit.hbox(6)
	_swatch = UiKit.color_swatch(Color(_accent), 48)
	crow.add_child(_swatch)
	for hex in Slots.ACCENTS:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(48, 48)
		sw.focus_mode = Control.FOCUS_NONE
		sw.add_theme_stylebox_override("normal", ThemeBuilder.box(Color(hex), Color(ThemeBuilder.CREAM, 0.3), 1, 4, 0))
		sw.add_theme_stylebox_override("hover", ThemeBuilder.box(Color(hex), ThemeBuilder.YELLOW, 2, 4, 0))
		sw.pressed.connect(func(): _set_accent(hex))
		crow.add_child(sw)
	var picker := ColorPickerButton.new()
	picker.text = "More"
	picker.custom_minimum_size = Vector2(100, 48)
	picker.edit_alpha = false
	picker.color = Color(_accent)
	picker.color_changed.connect(func(c): _set_accent("#" + c.to_html(false)))
	crow.add_child(picker)
	v.add_child(UiKit.field_row("Colour", crow, 150))
	_notes = UiKit.text_edit("Notes to yourself about this world...", str(_m.notes), 90)
	v.add_child(UiKit.field_row("Notes", _notes, 150))
	_tags = UiKit.line_edit("tags, separated by commas (e.g. cozy, 2026, test)", ", ".join(_m.get("tags", [])))
	v.add_child(UiKit.field_row("Tags", _tags, 150))
	var cov := UiKit.hbox(8)
	_cover_label = UiKit.label("", 18, ThemeBuilder.MUTED)
	_cover_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cov.add_child(_cover_label)
	cov.add_child(UiKit.button("Auto screenshot", func(): _set_cover("auto"), 190))
	cov.add_child(UiKit.button("Pick a picture...", _pick_cover, 190))
	v.add_child(UiKit.field_row("Cover", cov, 150))
	_refresh_cover_label()
	v.add_child(UiKit.label("Autosave (snapshots you can restore)", 22, ThemeBuilder.YELLOW))
	var a: Dictionary = _m.get("autosave", {})
	_auto_on = _check(v, "Snapshot every few minutes while playing", bool(a.get("enabled", true)))
	_interval = _spin(1, 120, int(a.get("interval_min", 10)))
	v.add_child(UiKit.field_row("Minutes between snapshots", _interval, 300))
	_on_room = _check(v, "Also when you change rooms", bool(a.get("on_room_change", true)))
	_on_quit = _check(v, "Also when you quit", bool(a.get("on_quit", true)))
	_keep = _spin(1, 100, int(a.get("keep", 10)))
	v.add_child(UiKit.field_row("Automatic snapshots to keep", _keep, 300))
	v.add_child(UiKit.para("Manual backups and chat logs are never deleted automatically.", 18, ThemeBuilder.MUTED))
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UiKit.button("Save", _save, 160))
	body.add_child(row)


func _check(parent: Control, text: String, on: bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = on
	parent.add_child(cb)
	return cb


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.custom_minimum_size = Vector2(140, 52)
	return s


func _set_accent(hex: String) -> void:
	_accent = hex
	_swatch.color = Color(hex)


func _set_cover(mode: String) -> void:
	_m["cover"] = mode
	_refresh_cover_label()


func _refresh_cover_label() -> void:
	var mode := str(_m.get("cover", "auto"))
	_cover_label.text = "A screenshot of the room, refreshed while you play" if mode == "auto" else "Your own picture"


func _pick_cover() -> void:
	UiKit.pick_picture(self, "Pick a cover picture", func(path):
		var img: Image = SaveManager.load_picture(path)
		if img == null:
			GameState.notify("Couldn't open that picture.")
			return
		var scale := minf(minf(960.0 / img.get_width(), 540.0 / img.get_height()), 1.0)
		if scale < 1.0:
			img.resize(roundi(img.get_width() * scale), roundi(img.get_height() * scale), Image.INTERPOLATE_LANCZOS)
		img.save_png(Slots.dir(slot_id).path_join("cover_custom.png"))
		SaveManager.forget_texture(Slots.dir(slot_id).path_join("cover_custom.png"))
		_set_cover("custom"))


func _save() -> void:
	_m["name"] = _name.text.strip_edges() if _name.text.strip_edges() != "" else _m.name
	_m["emoji"] = _emoji.text.strip_edges() if _emoji.text.strip_edges() != "" else "🌙"
	_m["accent"] = _accent
	_m["notes"] = _notes.text.strip_edges()
	var tags: Array = []
	for t in _tags.text.split(","):
		var tag := t.strip_edges().to_lower().trim_prefix("#")
		if tag != "" and not tag in tags:
			tags.append(tag)
	_m["tags"] = tags
	_m["autosave"] = {"enabled": _auto_on.button_pressed, "interval_min": int(_interval.value), "on_room_change": _on_room.button_pressed, "on_quit": _on_quit.button_pressed, "keep": int(_keep.value)}
	Slots.save_meta(slot_id, _m)
	GameState.notify("Card saved ✓")
	saved.emit()
	close()


## Closing with back also keeps what you typed.
func on_back() -> bool:
	_save()
	return true
