extends RefCounted
## A square item button for grids: the icon in a rarity-coloured frame, a
## count badge, an "E" badge when equipped, and the full tooltip.

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Items := preload("res://scripts/items/items.gd")


static func make(item: Dictionary, count: int = 1, equipped: bool = false, side: float = 76.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(side, side)
	b.icon = Items.icon_texture(item)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", int(side - 18))
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.tooltip_text = Items.tooltip(item, count)
	b.focus_mode = Control.FOCUS_ALL
	# [GLASS_UI] A slot sunk into the bag's tray: an inner shadow under its top edge, its rim in the
	# item's rarity colour; hovered, the rim brightens; picked, a yolk rim and a deeper shadow.
	var col := Items.rarity_color(str(item.get("rarity", "common")))
	var slot := ThemeBuilder.BG.lerp(ThemeBuilder.PANEL, 0.5)
	b.add_theme_stylebox_override("normal", ThemeBuilder.well(slot, Color(col, 0.85), 10, 2, 0.5))
	b.add_theme_stylebox_override("hover", ThemeBuilder.well(slot.lightened(0.06), col.lightened(0.3), 10, 2, 0.4))
	b.add_theme_stylebox_override("pressed", ThemeBuilder.well(slot.darkened(0.1), ThemeBuilder.YELLOW, 10, 3, 0.65))
	b.add_theme_stylebox_override("focus", ThemeBuilder.box(Color(0, 0, 0, 0), ThemeBuilder.YELLOW, 3, 10, 0))
	if count > 1:
		_badge(b, "×%d" % count, Control.PRESET_BOTTOM_RIGHT, ThemeBuilder.CREAM)
	if equipped:
		_badge(b, "E", Control.PRESET_TOP_LEFT, ThemeBuilder.MINT)
	return b


static func _badge(b: Button, text: String, corner: int, color: Color) -> void:
	var l := UiKit.label(text, 16, color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", ThemeBuilder.BG)
	l.set_anchors_preset(corner)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if corner == Control.PRESET_BOTTOM_RIGHT:
		l.offset_left = -44
		l.offset_top = -26
		l.offset_right = -6
		l.offset_bottom = -2
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		l.offset_left = 6
		l.offset_top = 2
		l.offset_right = 30
		l.offset_bottom = 24
	b.add_child(l)
