extends "res://scripts/ui/screen_panel.gd"
## The editor's "?" cheat sheet. Every shortcut is a single key and every
## one of them also has a button, so none of this is required.

const ROWS := [
	["1 … 9", "Use the matching hotbar favourite (click a slot to pin the current brush)"],
	["R / F", "Rotate / flip what you're placing (or the stamp)"],
	["[ / ]", "Brush size down / up"],
	["- / =", "Elevation down / up (standing and wall pictures)"],
	["T", "Next tile layer in this room"],
	["G", "Grid snap on / off (half-cell signs and plants)"],
	["V", "Paste the clipboard as a stamp"],
	["Backspace", "Undo (the Undo button does the same; 150 steps)"],
	["W A S D", "Move the build cursor"],
	["E / Z", "Use the tool at the cursor"],
	["Q / X / right-click", "Leave the editor"],
	["Mouse wheel", "Zoom (or rotate, see Settings)"],
]


func _ready() -> void:
	setup("Editor shortcuts", Vector2(820, 640))
	body.add_child(UiKit.para("All optional: everything has a button too. Keys are single presses, nothing to hold.", 18, ThemeBuilder.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(UiKit.scroll(grid))
	for r in ROWS:
		grid.add_child(UiKit.label(r[0], 20, ThemeBuilder.YELLOW))
		grid.add_child(UiKit.para(r[1], 18))
