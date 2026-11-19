extends BoxContainer
## The layered doll maker: a big preview (cycle through the faces), one tab
## per part (skin, hair, eyes, outfit, accessory) with a picture button for
## every style, hue/saturation/brightness sliders plus quick swatches,
## Randomize, and presets (built-in ones and your own, shared by all worlds).

signal changed

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Doll := preload("res://scripts/characters/doll.gd")
const Defaults := preload("res://scripts/core/defaults.gd")

var recipe: Dictionary = {}
var part := "hair"
var emotion_idx := 0
var _preview: TextureRect
var _emotion_label: Label
var _part_btns: Dictionary = {}
var _styles: HFlowContainer
var _h: HSlider
var _s: HSlider
var _v: HSlider
var _swatches: HFlowContainer
var _presets: OptionButton
var _preset_ids: Array = []
var _preset_name: LineEdit
var _delete_btn: Button
var _syncing := false
var _rng := RandomNumberGenerator.new()


func setup(r: Variant) -> void:
	recipe = Doll.normalize(r)
	_rng.randomize()
	vertical = UiKit.upright_phone()   # the preview above the controls on a phone
	add_theme_constant_override("separation", 14)
	var left := UiKit.vbox(8)
	left.custom_minimum_size.x = 220
	add_child(left)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, Color(ThemeBuilder.CREAM, 0.3), 2, 10, 6))
	left.add_child(frame)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(200, 200)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(_preview)
	var er := UiKit.hbox(4)
	er.add_child(UiKit.button("◀", func(): _step_emotion(-1), 52))
	_emotion_label = UiKit.label("", 18, ThemeBuilder.MUTED)
	_emotion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emotion_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	er.add_child(_emotion_label)
	er.add_child(UiKit.button("▶", func(): _step_emotion(1), 52))
	left.add_child(er)
	left.add_child(UiKit.button("🎲 Randomize", func(): randomize_all(), 0))
	left.add_child(UiKit.button("Random colours", func(): randomize_colors(), 0))
	var right := UiKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var parts := HFlowContainer.new()
	parts.add_theme_constant_override("h_separation", 6)
	for p in Doll.PARTS:
		var b := UiKit.button(str(Doll.PART_NAMES[p]), func(): set_part(p), 0)
		b.toggle_mode = true
		_part_btns[p] = b
		parts.add_child(b)
	right.add_child(parts)
	_styles = HFlowContainer.new()
	_styles.add_theme_constant_override("h_separation", 6)
	_styles.add_theme_constant_override("v_separation", 6)
	right.add_child(_styles)
	right.add_child(UiKit.label("Colour", 18, ThemeBuilder.YELLOW))
	_h = _slider(right, "Hue")
	_s = _slider(right, "Strength")
	_v = _slider(right, "Brightness")
	_swatches = HFlowContainer.new()
	_swatches.add_theme_constant_override("h_separation", 4)
	right.add_child(_swatches)
	right.add_child(UiKit.label("Presets", 18, ThemeBuilder.YELLOW))
	var pr := UiKit.hbox(6)
	_presets = UiKit.option([])
	_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(_presets)
	pr.add_child(UiKit.button("Use", func(): apply_preset(_presets.selected), 80))
	_delete_btn = UiKit.button("✕", _delete_preset, 52)
	_delete_btn.tooltip_text = "Delete this saved preset"
	pr.add_child(_delete_btn)
	right.add_child(pr)
	var sv := UiKit.hbox(6)
	_preset_name = UiKit.line_edit("Name this look, e.g. Rainy day me")
	_preset_name.max_length = 30
	sv.add_child(_preset_name)
	sv.add_child(UiKit.button("Save preset", func(): save_preset(_preset_name.text), 150))
	right.add_child(sv)
	_presets.item_selected.connect(func(_i): _delete_btn.disabled = not str(_preset_ids[_presets.selected]).begins_with("saved:"))
	_fill_presets()
	set_part(part)


func _slider(parent: Control, caption: String) -> HSlider:
	var s := UiKit.slider(0.0, 1.0, 0.01, 0.5)
	s.value_changed.connect(func(_x): _on_color_slider())
	s.drag_ended.connect(func(_c): _fill_styles())
	parent.add_child(UiKit.field_row(caption, s, 120))
	return s


func set_part(p: String) -> void:
	part = p
	for k in _part_btns:
		_part_btns[k].set_pressed_no_signal(k == p)
	_sync_sliders()
	_fill_styles()
	_fill_swatches()
	_refresh_preview()


func _fill_styles() -> void:
	for c in _styles.get_children():
		c.queue_free()
	for s in Doll.STYLES[part]:
		var r2 := recipe.duplicate(true)
		r2[part]["style"] = str(s[0])
		var b := UiKit.button(str(s[1]), func(): set_style(str(s[0])), 0)
		b.icon = ImageTexture.create_from_image(Doll.compose(r2, "neutral"))
		b.add_theme_constant_override("icon_max_width", 32)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.toggle_mode = true
		b.set_pressed_no_signal(str(recipe[part].style) == str(s[0]))
		_styles.add_child(b)


func _fill_swatches() -> void:
	for c in _swatches.get_children():
		c.queue_free()
	for hex in Doll.PALETTES[part]:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(44, 44)
		sw.tooltip_text = hex
		sw.add_theme_stylebox_override("normal", ThemeBuilder.box(Color(hex), Color(ThemeBuilder.CREAM, 0.3), 1, 6, 0))
		sw.add_theme_stylebox_override("hover", ThemeBuilder.box(Color(hex), ThemeBuilder.YELLOW, 2, 6, 0))
		sw.pressed.connect(func(): set_color(str(hex)))
		_swatches.add_child(sw)


func _sync_sliders() -> void:
	var c := Color.from_string(str(recipe[part].color), Color.WHITE)
	_syncing = true
	_h.value = c.h
	_s.value = c.s
	_v.value = c.v
	_syncing = false


func _on_color_slider() -> void:
	if _syncing:
		return
	recipe[part]["color"] = "#" + Color.from_hsv(_h.value, _s.value, _v.value).to_html(false)
	_refresh_preview()
	changed.emit()


func set_style(id: String) -> void:
	recipe[part]["style"] = id
	_fill_styles()
	_refresh_preview()
	changed.emit()


func set_color(hex: String) -> void:
	recipe[part]["color"] = hex
	_sync_sliders()
	_fill_styles()
	_refresh_preview()
	changed.emit()


func set_recipe(r: Variant) -> void:
	recipe = Doll.normalize(r)
	set_part(part)
	changed.emit()


func randomize_all() -> void:
	set_recipe(Doll.randomize(_rng))


func randomize_colors() -> void:
	var r := recipe.duplicate(true)
	for p in Doll.PARTS:
		var pal: Array = Doll.PALETTES[p]
		r[p]["color"] = str(pal[_rng.randi_range(0, pal.size() - 1)])
	set_recipe(r)


func _step_emotion(d: int) -> void:
	emotion_idx = posmod(emotion_idx + d, Defaults.DEFAULT_EXPRESSIONS.size())
	_refresh_preview()


func _refresh_preview() -> void:
	var e := Defaults.DEFAULT_EXPRESSIONS[emotion_idx]
	_preview.texture = ImageTexture.create_from_image(Doll.compose(recipe, e))
	_emotion_label.text = e.capitalize()


# --- Presets -------------------------------------------------------------------------------------

func _fill_presets() -> void:
	_presets.clear()
	_preset_ids.clear()
	for id in Doll.PRESETS:
		_preset_ids.append("builtin:" + str(id))
		_presets.add_item(str(Doll.PRESETS[id][0]))
	for p in Doll.saved_presets():
		_preset_ids.append("saved:" + str(p.id))
		_presets.add_item("★ " + str(p.name))
	_delete_btn.disabled = true


func apply_preset(index: int) -> void:
	if index < 0 or index >= _preset_ids.size():
		return
	var key := str(_preset_ids[index])
	if key.begins_with("builtin:"):
		set_recipe(Doll.preset(key.trim_prefix("builtin:")))
		return
	for p in Doll.saved_presets():
		if "saved:" + str(p.id) == key:
			set_recipe(p.recipe)


func save_preset(preset_name: String) -> void:
	if preset_name.strip_edges() == "":
		GameState.notify("Give the preset a name first.")
		return
	var id := Doll.save_preset(preset_name, recipe)
	_preset_name.text = ""
	_fill_presets()
	_presets.select(maxi(0, _preset_ids.find("saved:" + id)))
	_delete_btn.disabled = false
	GameState.notify("Saved the look \"%s\" (usable in every world)." % preset_name.strip_edges())


func _delete_preset() -> void:
	var key := str(_preset_ids[_presets.selected]) if _presets.selected >= 0 else ""
	if key.begins_with("saved:"):
		Doll.delete_preset(key.trim_prefix("saved:"))
		_fill_presets()
