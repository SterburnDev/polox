extends RefCounted
## The Worlds screen remembers how you like it: layout, sort, tag filter,
## and a look (colour theme, frame style, font size). Stored in settings.json
## under "worlds_menu".

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const ScreenPanel := preload("res://scripts/ui/screen_panel.gd")

## id -> [label, panel colour, border colour, title colour]
const THEMES := {
	"night": ["Night", Color("#1d1736"), Color("#f3e9d2"), Color("#ffd166")],
	"mint": ["Mint", Color("#152a23"), Color("#7ad6b0"), Color("#7ad6b0")],
	"rose": ["Rose", Color("#301626"), Color("#ffb3c7"), Color("#ffb3c7")],
	"sky": ["Sky", Color("#14243a"), Color("#8fd3ff"), Color("#8fd3ff")],
	"ember": ["Ember", Color("#2c1a12"), Color("#ff9f43"), Color("#ffd166")],
}
const FRAMES := [["round", "Rounded"], ["square", "Square"], ["double", "Thick"]]
const FONTS := [[18, "Small"], [22, "Normal"], [26, "Large"]]


static func defaults() -> Dictionary:
	return {"layout": "grid", "sort": "played", "tag": "", "theme": "night", "frame": "round", "font": 22}


static func prefs() -> Dictionary:
	var p: Variant = GameState.settings.get("worlds_menu", {})
	var out := defaults()
	if p is Dictionary:
		for k in p:
			out[k] = p[k]
	return out


static func save_prefs(p: Dictionary) -> void:
	GameState.settings["worlds_menu"] = p.duplicate()
	GameState.save_settings()


## Restyles a Worlds screen panel in place.
static func apply(screen: Control, p: Dictionary) -> void:
	var t: Array = THEMES.get(str(p.get("theme", "night")), THEMES["night"])
	var frame := str(p.get("frame", "round"))
	var radius: int = {"round": 14, "square": 2, "double": 12}.get(frame, 14)
	var border := 6 if frame == "double" else 3
	screen.panel.add_theme_stylebox_override("panel", ThemeBuilder.box(Color(t[1], 0.97), t[2], border, radius, 12))
	screen.title_label.add_theme_color_override("font_color", t[3])
	screen.title_label.add_theme_font_size_override("font_size", int(p.get("font", 22)) + 8)
	var theme := ThemeBuilder.build()
	theme.default_font_size = int(p.get("font", 22))
	screen.panel.theme = theme


## The "Look" chooser panel. Emits changed(prefs).
static func panel(p: Dictionary) -> Control:
	var s := LookPanel.new()
	s.prefs = p.duplicate()
	return s


class LookPanel extends ScreenPanel:
	signal changed(prefs: Dictionary)
	var prefs: Dictionary = {}

	func _ready() -> void:
		setup("Look of the Worlds screen", Vector2(760, 520))
		body.add_child(UiKit.label("Colours", 22, ThemeBuilder.YELLOW))
		var row := UiKit.hbox(8)
		for id in THEMES:
			var b := UiKit.button(THEMES[id][0], func(): _pick("theme", id), 110)
			b.add_theme_stylebox_override("normal", ThemeBuilder.box(THEMES[id][1], THEMES[id][2], 2, 10, 8))
			b.toggle_mode = true
			b.set_pressed_no_signal(str(prefs.get("theme", "night")) == id)
			row.add_child(b)
		body.add_child(row)
		body.add_child(UiKit.label("Frame", 22, ThemeBuilder.YELLOW))
		var fr := UiKit.hbox(8)
		for f in FRAMES:
			var b := UiKit.button(f[1], func(): _pick("frame", f[0]), 130)
			b.toggle_mode = true
			b.set_pressed_no_signal(str(prefs.get("frame", "round")) == f[0])
			fr.add_child(b)
		body.add_child(fr)
		body.add_child(UiKit.label("Text size", 22, ThemeBuilder.YELLOW))
		var fs := UiKit.hbox(8)
		for f in FONTS:
			var b := UiKit.button(f[1], func(): _pick("font", f[0]), 130)
			b.toggle_mode = true
			b.set_pressed_no_signal(int(prefs.get("font", 22)) == f[0])
			fs.add_child(b)
		body.add_child(fs)
		body.add_child(UiKit.para("Changes apply right away and are remembered.", 18, ThemeBuilder.MUTED))

	func _pick(key: String, value: Variant) -> void:
		prefs[key] = value
		# Same as save_prefs(); a preload of this very file would be a cycle
		# that keeps scripts alive at quit.
		GameState.settings["worlds_menu"] = prefs.duplicate()
		GameState.save_settings()
		changed.emit(prefs)
		close()
