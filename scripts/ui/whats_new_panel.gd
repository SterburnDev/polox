extends "res://scripts/ui/screen_panel.gd"
## "New in Polox": shown once to players who already had a world before
## this update, with a button to try each new thing right away.

const VERSION := "0.7"
const WorldMenu := preload("res://scripts/world/world_menu.gd")

var main: Node


static func should_show() -> bool:
	return bool(GameState.settings.get("onboarded", false)) and str(GameState.settings.get("whats_new_seen", "")) != VERSION


static func mark_seen() -> void:
	GameState.settings["whats_new_seen"] = VERSION
	GameState.save_settings()


func _ready() -> void:
	setup("New in Polox", Vector2(980, 660))
	mark_seen()
	var v := UiKit.vbox(12)
	body.add_child(UiKit.scroll(v))
	var g: Node = main.game
	var items := [
		["You, twice", "My character: your profile for your friends, and two forms, Real Me and Dream World Me, from the doll maker or your own drawing. F switches.", "Open My character", func(): main.open_panel(WorldMenu.sheet(g))],
		["Things to keep and give", "The Bag (B), the Item Workshop to design weapons, armor, snacks and keepsakes, and gifts from your bag: friends love things that match their tags.", "Open the Bag", func(): main.open_panel(WorldMenu.bag(g))],
		["Your phone", "Phone Link: play this world in your phone's browser at home, synced with this PC. Off until you switch it on.", "Phone Link settings", func(): _settings("Phone Link")],
		["Easier chatting", "Suggested replies to tap, a \"Where was I?\" card when you come back, a quiet save indicator, and a left-hand keyboard layout.", "Gameplay settings", func(): _settings("Gameplay")],
	]
	for it in items:
		var row := UiKit.hbox(12)
		var col := UiKit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.label(str(it[0]), 22, ThemeBuilder.YELLOW))
		col.add_child(UiKit.para(str(it[1]), 18, ThemeBuilder.CREAM))
		row.add_child(col)
		var cb: Callable = it[3]
		row.add_child(UiKit.button(str(it[2]), func():
			close()
			cb.call(), 230))
		v.add_child(row)


func _settings(tab: String) -> void:
	var s: Control = load("res://scripts/ui/settings_screen.gd").new()
	s.main = main
	s.start_on = tab
	main.open_panel(s)
