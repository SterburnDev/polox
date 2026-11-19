extends "res://scripts/ui/screen_panel.gd"
## "My character": the Player Profile (Me), Real Me / Dream World Me (Looks)
## and equipped items (Gear). Saves the world when it closes.

const ProfileTab := preload("res://scripts/ui/player_profile_tab.gd")
const LooksTab := preload("res://scripts/ui/player_looks_tab.gd")
const GearTab := preload("res://scripts/ui/gear_tab.gd")
const InventoryPanel := preload("res://scripts/ui/inventory_panel.gd")

var world: Node
var start_tab := 0
var tabs: TabContainer
var profile: ScrollContainer     # player_profile_tab.gd
var looks: ScrollContainer       # player_looks_tab.gd
var gear: BoxContainer           # gear_tab.gd


func _ready() -> void:
	setup("My character", Vector2(1240, 700))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	var opener := func(p: Control): _main().open_panel(p)
	profile = ProfileTab.new()
	profile.open_panel = opener
	profile.build()
	tabs.add_child(profile)
	looks = LooksTab.new()
	looks.open_panel = opener
	looks.world = world
	looks.build()
	tabs.add_child(looks)
	gear = GearTab.new()
	gear.world = world
	gear.build()
	gear.open_bag.connect(func():
		var bag := InventoryPanel.new()
		bag.world = world
		bag.closed.connect(func():
			if is_inside_tree():
				gear.refresh())
		_main().open_panel(bag))
	tabs.add_child(gear)
	tabs.current_tab = clampi(start_tab, 0, 2)
	tabs.tab_changed.connect(func(_i):
		looks.save_pending()
		gear.refresh())


func _main() -> Node:
	return world.main if world else get_tree().current_scene


func save() -> void:
	looks.save_pending()
	GameState.save_world()
	GameState.character_changed.emit("player")


func on_back() -> bool:
	save()
	close()
	return true
