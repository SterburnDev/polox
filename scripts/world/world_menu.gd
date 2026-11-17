extends RefCounted
## Builds the in-game menu's items. Kept apart from game_world.gd so the
## list of screens is easy to find and extend.

const GameMenu := preload("res://scripts/ui/game_menu.gd")
const LogViewer := preload("res://scripts/ui/log_viewer.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const WorldBibleEditor := preload("res://scripts/ui/world_bible_editor.gd")
const FriendsPanel := preload("res://scripts/ui/friends_panel.gd")
const CharacterCreator := preload("res://scripts/ui/character_creator.gd")
const RoomList := preload("res://scripts/ui/room_list.gd")
const DreamsBoard := preload("res://scripts/ui/dreams_board.gd")
const MemoryBook := preload("res://scripts/ui/memory_book.gd")
const HelpPanel := preload("res://scripts/ui/help_panel.gd")
const PlayerSheet := preload("res://scripts/ui/player_sheet.gd")
const InventoryPanel := preload("res://scripts/ui/inventory_panel.gd")
const ItemWorkshop := preload("res://scripts/ui/item_workshop.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")


static func make(world: Node) -> Control:
	var main: Node = world.main
	var settings: String = TitleScreen.EYES if TitleScreen.eyes else "Settings"   # ([EASTER_EGG] the Music secret's mark)
	var items: Array = [
		["Resume", func(): pass],
		["Bag", func(): main.open_panel(bag(world))],
		["Friends", func(): main.open_panel(friends(world))],
		["My character", func(): main.open_panel(sheet(world))],
		["My home", func():
			var hp: Control = load("res://scripts/home/map_home_panel.gd").new()
			main.open_panel(hp)
			hp.setup_home(world)],
		["Tell Polox about home", func():
			var tp: Control = load("res://scripts/home/tell_polox_panel.gd").new()
			main.open_panel(tp)
			tp.setup_tell(world)],
		["World Map", func():
			var m: Control = load("res://scripts/ui/world_map_view.gd").new()
			main.open_panel(m)
			m.setup_map(world)],
		["Build mode", func(): world.build.enter()],
		["Story", func(): main.open_panel(load("res://scripts/ui/story_panel.gd").new())],
		["Today & Moments", func(): main.open_panel(load("res://scripts/ui/moments_panel.gd").new())],
		["Quests", func(): main.open_panel(load("res://scripts/ui/quest_log_panel.gd").new())],
		["Dreams & Desires", func(): main.open_panel(DreamsBoard.new())],
		["Memory Book", func(): main.open_panel(MemoryBook.new())],
		["Almanac", func(): main.open_panel(load("res://scripts/ui/almanac_panel.gd").new())],
		["Hang out", func(): main.open_panel(hangout(world))],
		["Battle", func(): world.battles.open_setup("")],
		["Take a photo", func(): world.take_photo()],
		[settings, func(): main.open_panel(SettingsScreen.new())],
		["More", func(): main.open_panel(more(world))],
		["Worlds", func(): main.open_worlds()],
		["Title screen", func(): main.show_title()],
	]
	var m := GameMenu.new()
	m.title_hint = "%s • %s" % [GameState.world.get("name", ""), AIClient.status_message]
	if preload("res://scripts/ui/ui_kit.gd").upright_phone():
		var primary: Array = items.slice(0, 7)
		for label in ["Battle", settings, "Worlds"]:
			for item in items:
				if str(item[0]) == label:
					primary.append(item)
		primary.append(items.back())
		var extra: Array = items.filter(func(item): return not item in primary)
		primary.append(["More options", func():
			var more_menu := GameMenu.new()
			more_menu.build(extra)
			main.open_panel(more_menu)])
		items = primary
	m.build(items)
	return m


## Less-used things, one tap further: the makers, the logs and help (your files are in Settings).
static func more(world: Node) -> Control:
	var main: Node = world.main
	var items: Array = [
		["New friend", func(): main.open_panel(creator(""))],
		["Item Workshop", func(): main.open_panel(workshop(world))],
		["Battle Maker", func(): world.battles.open_maker("")],
		["Places", func(): main.open_panel(room_list(world))],
		["World Bible", func(): main.open_panel(WorldBibleEditor.new())],
		["Chat Log", func(): main.open_panel(LogViewer.new())],
		["How to play", func(): main.open_panel(HelpPanel.new())],
	]
	var m := GameMenu.new()
	m.build(items)
	m.title_label.text = "More"
	return m


static func hangout(world: Node) -> Control:
	var p: Control = load("res://scripts/ui/hangout_panel.gd").new()
	p.world = world
	return p


static func friends(world: Node) -> Control:
	var f := FriendsPanel.new()
	f.edit_character.connect(func(id): world.main.open_panel(creator(id)))
	f.new_character.connect(func(): world.main.open_panel(creator("")))
	return f


static func creator(id: String) -> Control:
	var c := CharacterCreator.new()
	if id == "":
		c.new_character()
	else:
		c.edit_character(id)
	return c


static func sheet(world: Node, tab: int = 0) -> Control:
	var s := PlayerSheet.new()
	s.world = world
	s.start_tab = tab
	return s


static func bag(world: Node) -> Control:
	var b := InventoryPanel.new()
	b.world = world
	return b


static func workshop(world: Node) -> Control:
	var w := ItemWorkshop.new()
	w.world = world
	return w


static func room_list(world: Node) -> Control:
	var rl := RoomList.new()
	rl.world = world
	return rl
