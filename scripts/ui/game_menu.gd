extends "res://scripts/ui/screen_panel.gd"
## The in-game menu (C / Tab / Menu button): a grid of big friendly buttons.
## Items are [label, callable, tooltip] and come from the game world.


var title_hint := ""


func build(items: Array) -> void:
	setup("Menu", Vector2(760, 680))
	if title_hint != "":
		body.add_child(UiKit.para(title_hint, 18, ThemeBuilder.MUTED))
	var grid := GridContainer.new()
	grid.columns = 1 if UiKit.upright_phone() else 2
	grid.add_theme_constant_override("h_separation", 8 if UiKit.upright_phone() else 14)
	grid.add_theme_constant_override("v_separation", 8 if UiKit.upright_phone() else 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(UiKit.page(grid))   # (no scroll bar, like Settings: wheel, swipe or keys; a fade says there's more)
	for it in items:
		var cb: Callable = it[1]
		var b := UiKit.button(str(it[0]), func():
			close()
			cb.call())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = maxf(64, UiKit.touch_target())
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # a long name wraps instead of pushing the grid off a phone
		if it.size() > 2:
			b.tooltip_text = str(it[2])
		grid.add_child(b)
	# (the first button gets focus once the panel is in the tree: screen_panel._auto_focus)
