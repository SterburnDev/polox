extends RefCounted
## The desktop-only row lives here to keep the main settings page short.
## Tags: [GRAPHICS]

const Detail := preload("res://scripts/core/pc_detail.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")


static func add_row(parent: Control) -> void:
	if not Detail.available():
		return
	var ids: Array = Detail.CHOICES.map(func(choice): return choice[0])
	var names: Array = ["Auto (High, steps down if slow)", "High", "Ultra (demanding)", "Off (fastest)"]
	var option := UiKit.option(names, maxi(0, ids.find(str(GameState.settings.get("pc_detail", "auto")))))
	option.name = "PCDetail"
	option.tooltip_text = "Uses Graphics High or Automatic. Steps down if frames stay above 20 ms. Select again to retry."
	option.item_selected.connect(func(i):
		Detail.reset()
		GameState.settings["pc_detail"] = ids[i]
		GameState.save_settings())
	parent.add_child(UiKit.field_row("PC graphics", option, 230))
