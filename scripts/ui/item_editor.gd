extends VBoxContainer
## The Item Workshop's form for one item: name, type (and armor slot),
## rarity, flavor text with an optional AI suggestion, gift tags, icon
## (auto / drawn / imported), an optional world sprite, show-only stats and
## one tiny effect. Edits the dictionary it was given; emits `edited`.

signal edited

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Items := preload("res://scripts/items/items.gd")
const ItemArt := preload("res://scripts/items/item_art.gd")
const FlavorText := preload("res://scripts/items/flavor_text.gd")
const PixelPaint := preload("res://scripts/ui/pixel_paint_panel.gd")
const Synth := preload("res://scripts/core/synth.gd")

var item: Dictionary = {}
var open_panel: Callable          # main.open_panel, for the Draw screens
var name_edit: LineEdit
var flavor_edit: TextEdit
var tags_edit: LineEdit
var _cat_opt: OptionButton
var _slot_opt: OptionButton
var _slot_row: Control
var _rarity_btns: Dictionary = {}
var _icon_preview: TextureRect
var _sprite_preview: TextureRect
var _shape_opt: OptionButton
var _shapes: PackedStringArray = []
var _color_btn: ColorPickerButton
var _stats_box: VBoxContainer
var _effect_opt: OptionButton
var _effect_value: HBoxContainer
var _suggest_btn: Button
var _suggest_note: Label
var _variant := 0


func edit(it: Dictionary) -> void:
	item = it
	for c in get_children():
		c.queue_free()
	add_theme_constant_override("separation", 8)
	name_edit = UiKit.line_edit("Name, e.g. Moon cookie", str(item.get("name", "")))
	name_edit.max_length = 40
	name_edit.text_changed.connect(func(t):
		item["name"] = t.strip_edges()
		edited.emit())
	add_child(UiKit.field_row("Name", name_edit, 120))
	var kind := UiKit.flow_row(8)
	_cat_opt = UiKit.option(Items.CATEGORIES.map(func(c): return c[2]), maxi(0, Items.category_ids().find(str(item.category))))
	_cat_opt.item_selected.connect(_on_category)
	kind.add_child(UiKit.field_row("Type", _cat_opt, 120))
	_slot_opt = UiKit.option(Items.ARMOR_SLOTS.map(func(s): return s[1]), maxi(0, ["head", "body", "accessory"].find(str(item.get("slot", "head")))))
	_slot_opt.item_selected.connect(func(i):
		item["slot"] = str(Items.ARMOR_SLOTS[i][0])
		edited.emit())
	_slot_row = UiKit.field_row("Worn on", _slot_opt, 90)
	kind.add_child(_slot_row)
	add_child(kind)
	var realms := ["shared", "light", "dark"]
	var realm_choice := UiKit.option(["Shared between worlds", "Light World only", "Dream World only"], maxi(0, realms.find(str(item.get("realm", "shared")))))
	realm_choice.item_selected.connect(func(i):
		item["realm"] = realms[i]
		edited.emit())
	add_child(UiKit.field_row("Worn in", realm_choice, 120))
	var rar := UiKit.flow_row(6)
	var rl := UiKit.label("Rarity")
	rl.custom_minimum_size.x = 120
	rar.add_child(rl)
	for r in Items.RARITIES:
		var b := UiKit.button(str(r[1]), func(): _set_rarity(str(r[0])), 0)
		b.toggle_mode = true
		b.add_theme_color_override("font_color", Color(str(r[2])))
		b.add_theme_color_override("font_pressed_color", ThemeBuilder.BG)
		b.add_theme_stylebox_override("pressed", ThemeBuilder.box(Color(str(r[2])), ThemeBuilder.CREAM, 2, 10, 8))
		_rarity_btns[r[0]] = b
		rar.add_child(b)
	add_child(rar)
	add_child(UiKit.label("Flavor text", 20, ThemeBuilder.YELLOW))
	flavor_edit = UiKit.text_edit("A line of whimsy, e.g. 'Baked by moonlight. The crumbs float upward.'", str(item.get("flavor", "")), 70)
	flavor_edit.text_changed.connect(func():
		item["flavor"] = flavor_edit.text.strip_edges()
		edited.emit())
	add_child(flavor_edit)
	var sug := UiKit.hbox(8)
	_suggest_btn = UiKit.button("✨ Suggest", func(): suggest(), 150)
	_suggest_btn.tooltip_text = "Ask your AI for an idea (works offline too)"
	sug.add_child(_suggest_btn)
	_suggest_note = UiKit.label("", 16, ThemeBuilder.MUTED)
	sug.add_child(_suggest_note)
	add_child(sug)
	tags_edit = UiKit.line_edit("e.g. sweet, snack, moon", ", ".join(item.get("tags", [])))
	tags_edit.tooltip_text = "Friends whose liked tags match these love this gift (dislikes work the other way)"
	tags_edit.text_changed.connect(func(t):
		item["tags"] = Items.parse_tags(t)
		edited.emit())
	add_child(UiKit.field_row("Gift tags", tags_edit, 120))
	add_child(_pictures())
	add_child(UiKit.label("Stats (just for show)", 20, ThemeBuilder.YELLOW))
	_stats_box = UiKit.vbox(6)
	add_child(_stats_box)
	_fill_stats()
	add_child(UiKit.label("Effect", 20, ThemeBuilder.YELLOW))
	var eff := UiKit.hbox(8)
	_effect_opt = UiKit.option(Items.EFFECTS.map(func(e): return e[1]), maxi(0, Items.effect_ids().find(str(item.effect.get("type", "none")))))
	_effect_opt.item_selected.connect(func(i):
		item["effect"] = {"type": str(Items.EFFECTS[i][0]), "value": _default_effect_value(str(Items.EFFECTS[i][0]))}
		_fill_effect_value()
		edited.emit())
	eff.add_child(_effect_opt)
	_effect_value = UiKit.hbox(6)
	_effect_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eff.add_child(_effect_value)
	add_child(eff)
	_fill_effect_value()
	_sync()


func _sync() -> void:
	_slot_row.visible = str(item.category) == "armor"
	for k in _rarity_btns:
		_rarity_btns[k].set_pressed_no_signal(k == str(item.rarity))
	name_edit.add_theme_color_override("font_color", Items.rarity_color(str(item.rarity)))
	_refresh_pictures()


func _on_category(i: int) -> void:
	var cat := str(Items.CATEGORIES[i][0])
	var old_default := ItemArt.default_shape(str(item.category), str(item.get("slot", "")))
	item["category"] = cat
	if cat == "armor" and not str(item.get("slot", "")) in ["head", "body", "accessory"]:
		item["slot"] = "head"
	elif cat != "armor":
		item["slot"] = ""
	# A shape that was just the old type's default follows the new type.
	if str(item.auto_icon.get("shape", "")) == old_default:
		item.auto_icon["shape"] = ItemArt.default_shape(cat, str(item.slot))
	_fill_shapes()
	_sync()
	edited.emit()


func _set_rarity(r: String) -> void:
	item["rarity"] = r
	_sync()
	edited.emit()


# --- Pictures ------------------------------------------------------------------------------------

func _pictures() -> Control:
	var row := UiKit.columns(16)
	var icon_col := UiKit.vbox(6)
	icon_col.add_child(UiKit.label("Icon", 20, ThemeBuilder.YELLOW))
	_icon_preview = _preview_rect()
	icon_col.add_child(_icon_preview)
	var ib := UiKit.hbox(6)
	ib.add_child(UiKit.button("Auto", func():
		Items.clear_picture(item, "icon")
		_refresh_pictures()
		edited.emit(), 0))
	ib.add_child(UiKit.button("Draw", func(): _draw_picture("icon"), 0))
	ib.add_child(UiKit.button("Import", func(): _import("icon"), 0))
	icon_col.add_child(ib)
	var auto := UiKit.hbox(6)
	_shape_opt = UiKit.option([])
	_shape_opt.item_selected.connect(func(i):
		item.auto_icon["shape"] = _shapes[i]
		_refresh_pictures()
		edited.emit())
	auto.add_child(_shape_opt)
	_color_btn = ColorPickerButton.new()
	_color_btn.custom_minimum_size = Vector2(64, 52)
	_color_btn.edit_alpha = false
	_color_btn.color = Color.from_string(str(item.auto_icon.get("color", "#e8b04a")), Color("#e8b04a"))
	_color_btn.color_changed.connect(func(c):
		item.auto_icon["color"] = "#" + c.to_html(false)
		_refresh_pictures()
		edited.emit())
	auto.add_child(_color_btn)
	icon_col.add_child(auto)
	row.add_child(icon_col)
	var spr_col := UiKit.vbox(6)
	spr_col.add_child(UiKit.label("In the world (optional)", 20, ThemeBuilder.YELLOW))
	_sprite_preview = _preview_rect()
	spr_col.add_child(_sprite_preview)
	var sb := UiKit.hbox(6)
	sb.add_child(UiKit.button("Same as icon", func():
		Items.clear_picture(item, "sprite")
		_refresh_pictures()
		edited.emit(), 0))
	sb.add_child(UiKit.button("Draw", func(): _draw_picture("sprite"), 0))
	sb.add_child(UiKit.button("Import", func(): _import("sprite"), 0))
	spr_col.add_child(sb)
	spr_col.add_child(UiKit.para("Used for pickups and when you wear or hold it.", 16, ThemeBuilder.MUTED))
	row.add_child(spr_col)
	_fill_shapes()
	return row


func _preview_rect() -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(96, 96)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


func _fill_shapes() -> void:
	if _shape_opt == null:
		return
	_shape_opt.clear()
	_shapes = PackedStringArray(ItemArt.SHAPES.get(str(item.category), ItemArt.SHAPES.keepsake))
	var cur := str(item.auto_icon.get("shape", ""))
	if not cur in _shapes:
		_shapes.append(cur)
	for s in _shapes:
		_shape_opt.add_icon_item(ItemArt.texture(s, str(item.auto_icon.get("color", "#e8b04a"))), s.replace("_", " ").capitalize())
	_shape_opt.select(maxi(0, _shapes.find(cur)))


func _refresh_pictures() -> void:
	if _icon_preview == null:
		return
	_icon_preview.texture = Items.icon_texture(item)
	_sprite_preview.texture = Items.world_texture(item)
	var auto_on := str(item.get("icon", "")) == ""
	_shape_opt.disabled = not auto_on
	_color_btn.disabled = not auto_on


func _draw_picture(kind: String) -> void:
	var p := PixelPaint.new()
	p.title_text = "Draw the %s for %s" % ["icon" if kind == "icon" else "world picture", item.get("name", "this item")]
	p.start = Items.icon_image(item) if kind == "icon" else Items.world_image(item)
	p.done.connect(func(img): set_picture(kind, img))
	open_panel.call(p)


func _import(kind: String) -> void:
	UiKit.pick_picture(self, "Pick a picture for the %s" % kind, func(path):
		var img: Image = SaveManager.load_picture(path)
		if img == null:
			GameState.notify("Couldn't open that picture. Try a PNG or JPG under 40 MB.")
			return
		set_picture(kind, img))


func set_picture(kind: String, img: Image) -> void:
	Items.set_picture(item, kind, img)
	_refresh_pictures()
	edited.emit()


# --- Stats ----------------------------------------------------------------------------------------

func _fill_stats() -> void:
	for c in _stats_box.get_children():
		c.queue_free()
	var stats: Array = item.get("stats", [])
	for i in stats.size():
		var row := UiKit.hbox(6)
		var n := UiKit.line_edit("e.g. Sparkle", str(stats[i].get("name", "")))
		n.max_length = 20
		n.text_changed.connect(func(t):
			item.stats[i]["name"] = t.strip_edges()
			edited.emit())
		row.add_child(n)
		var v := SpinBox.new()
		v.min_value = 0
		v.max_value = 999
		v.value = int(stats[i].get("value", 1))
		v.custom_minimum_size = Vector2(120, 52)
		v.value_changed.connect(func(x):
			item.stats[i]["value"] = int(x)
			edited.emit())
		row.add_child(v)
		row.add_child(UiKit.button("✕", func():
			item.stats.remove_at(i)
			_fill_stats()
			edited.emit(), 52))
		_stats_box.add_child(row)
	if stats.size() < Items.MAX_STATS:
		_stats_box.add_child(UiKit.button("+ Add a stat", func():
			item.stats.append({"name": ["Sparkle", "Coziness", "Yum", "Luck"][item.stats.size() % 4], "value": 5})
			_fill_stats()
			edited.emit(), 200))


# --- Effect ----------------------------------------------------------------------------------------

func _default_effect_value(type: String) -> String:
	match type:
		"mood":
			return "small"
		"aura":
			return "#7af0ff"
		"sound":
			return "chime"
		"message":
			return "You feel a little braver."
		"lighting":
			return "#ffb37a"
	return ""


func _fill_effect_value() -> void:
	for c in _effect_value.get_children():
		c.queue_free()
	var e: Dictionary = item.effect
	var v := str(e.get("value", ""))
	match str(e.get("type", "none")):
		"mood":
			var o := UiKit.option(Items.MOOD_SIZES.map(func(m): return m[1]), maxi(0, ["small", "medium", "big"].find(v)))
			o.item_selected.connect(func(i):
				item.effect["value"] = str(Items.MOOD_SIZES[i][0])
				edited.emit())
			_effect_value.add_child(o)
		"aura", "lighting":
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(90, 52)
			cp.edit_alpha = false
			cp.color = Color.from_string(v, Color("#ffd166"))
			cp.color_changed.connect(func(c):
				item.effect["value"] = "#" + c.to_html(false)
				edited.emit())
			_effect_value.add_child(cp)
		"sound":
			var o := UiKit.option(Array(Items.SOUNDS), maxi(0, Items.SOUNDS.find(v)))
			o.item_selected.connect(func(i):
				item.effect["value"] = Items.SOUNDS[i]
				Synth.play(self, Items.SOUNDS[i])
				edited.emit())
			_effect_value.add_child(o)
			_effect_value.add_child(UiKit.button("Hear", func(): Synth.play(self, str(item.effect.get("value", "chime"))), 90))
		"message":
			var m := UiKit.line_edit("What should it say?", v)
			m.max_length = 140
			m.text_changed.connect(func(t):
				item.effect["value"] = t
				edited.emit())
			_effect_value.add_child(m)


# --- Flavor suggestion -----------------------------------------------------------------------------

## Asks the AI (or Mock) for a line; offline ideas fill in on any failure.
func suggest() -> void:
	_suggest_btn.disabled = true
	_suggest_note.text = "Thinking..."
	var r: Dictionary = await FlavorText.suggest(item, _variant)
	_variant += 1
	if not is_inside_tree():
		return
	_suggest_btn.disabled = false
	flavor_edit.text = str(r.text)
	item["flavor"] = str(r.text)
	_suggest_note.text = "An offline idea (press again for another)" if r.get("offline", false) else "From your AI (press again for another)"
	edited.emit()
