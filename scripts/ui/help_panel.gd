extends "res://scripts/ui/screen_panel.gd"
## "How to play": controls and gentle tips, in plain words.

const SECTIONS := [
	["Moving & talking", [
		"Click the floor to walk. Click a friend to walk over and talk.",
		"Keyboard (left hand): W A S D or arrows to walk, E or Z to talk / use, Q or X to go back, C or Tab for the menu, B for your bag, F to switch form.",
		"While chatting: type, then press Enter or the big Send button. Click anywhere (or E) to skip to the next line.",
		"Right-click always means \"back\".",
	]],
	["Camera", [
		"Scroll wheel zooms (or rotates, if you pick that in Settings). The round buttons bottom-right rotate and zoom too.",
		"Settings > Display lets you pick a camera angle and UI size.",
	]],
	["Making things", [
		"Menu > New friend opens the Character Creator: paint faces, give them a personality, save.",
		"Build (top right) lets you place blocks, signs, doors and plants, and paint floors, walls and sky. R rotates.",
		"Doors can lead to a brand-new room; a way back is made for you.",
	]],
	["You & your things", [
		"Menu > My character: your profile (friends read it), Real Me and Dream World Me (doll maker or your own drawing), your voice and gear.",
		"The Dream Gate in your room leads to the Dream World. Its people are the Bramins (one Bramin, many Bramins).",
		"Bag (top right): use snacks, equip weapons and armor (just for fun: there's no fighting), look at keepsakes.",
		"Item Workshop: design anything, then \"Make one\" to put it in your bag. In a chat, Gift gives an item; friends love things that match their tags.",
		"Pickups (Build > Objects > Pickup) put an item somewhere to find; walk onto it to pick it up.",
	]],
	["Your life, gently", [
		"World Bible: tell your friends about your real life. Dreams & Desires: what you're hoping for.",
		"Friends remember things you tell them (Menu > Friends lets you edit what they remember).",
		"★ Save in a chat keeps a moment in your Memory Book.",
		"Your friends here are a cozy companion, not a replacement for people. If things feel heavy, please reach out to someone you trust or a local helpline (findahelpline.com).",
	]],
	["AI & privacy", [
		"Mock mode needs no internet. For real conversations pick a provider in Settings > AI.",
		"Everything is saved on this PC in Polox's PersonalData folder (Settings > Gameplay). Only your chat messages go to the AI provider you choose; Ollama keeps it all on your PC.",
	]],
]


func _ready() -> void:
	setup("How to play", Vector2(1040, 660))
	var v := UiKit.vbox(10)
	body.add_child(UiKit.scroll(v))
	for s in SECTIONS:
		v.add_child(UiKit.label(s[0], 26, ThemeBuilder.YELLOW))
		for line in s[1]:
			v.add_child(UiKit.para("•  " + line, 20))
