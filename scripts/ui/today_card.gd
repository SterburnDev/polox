extends Control
## "Today in your world": the day's Moments (and, after a while away, what
## happened meanwhile), in a small card at the bottom of the screen. Never
## blocks play; click Got it (or anywhere on it) to put it away. A visitor
## can be invited to stay from here.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Visitors := preload("res://scripts/variety/visitors.gd")
const Almanac := preload("res://scripts/variety/almanac.gd")

const HUD_CARDS := &"polox_hud_card"
const ICONS := {"visitor": "●", "sky": "☁", "found": "✦", "request": "♥", "rumor": "♪", "celebration": "★", "echo": "○"}

var director: Node


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	# Inside narrow (phone) screens too.
	var w := minf(840.0, get_viewport_rect().size.x - 24.0)
	offset_left = -w / 2.0
	offset_right = w / 2.0
	offset_top = 76
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(HUD_CARDS)   # (hidden while building: hud.gd set_building)
	# [GLASS_UI] A temporary card over the world: Liquid Glass, so the world's own labels (a place's
	# name floating behind it) blur away under the text instead of showing through it.
	var panel: PanelContainer = preload("res://scripts/ui/liquid_glass.gd").new()
	panel.radius = 18.0
	panel.pad = Vector4(16, 12, 16, 12)
	panel.tint = Color(ThemeBuilder.PANEL, 0.62)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(panel)
	var v := UiKit.vbox(6)
	panel.add_child(v)
	var head := UiKit.hbox(8)
	var title := Almanac.worn()
	head.add_child(UiKit.label("Today in your world" + ((", " + title) if title != "" else ""), 22, ThemeBuilder.MINT))
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.button("Quests", func(): _open("res://scripts/ui/quest_log_panel.gd"), 110))
	head.add_child(UiKit.button("Got it", queue_free, 100))
	v.add_child(head)
	var away: Dictionary = director.away if director else {}
	var notes: Array = away.get("notes", [])
	if float(away.get("hours", 0.0)) >= 3.0:
		var days := float(away.get("days", 0.0))
		var when := ("about %d day%s" % [roundi(days), "" if roundi(days) == 1 else "s"]) if days >= 1.0 else "a few hours"
		v.add_child(UiKit.para("○  While you were away (%s), everyone went about their days.%s" % [when, (" %d note%s waiting for you here." % [notes.size(), "" if notes.size() == 1 else "s"]) if not notes.is_empty() else ""], 18, ThemeBuilder.CREAM))
	var t: Dictionary = director.today if director else {}
	for m in t.get("moments", []):
		var row := UiKit.hbox(8)
		var p := UiKit.para("%s  %s" % [ICONS.get(str(m.kind), "•"), str(m.text)], 18, ThemeBuilder.CREAM)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(p)
		if str(m.kind) == "visitor" and str(m.get("visitor_id", "")) != "" and bool(GameState.get_character(str(m.visitor_id)).get("visitor", false)):
			var vid := str(m.visitor_id)
			row.add_child(UiKit.button("Invite to stay", func():
				if Visitors.invite(vid):
					GameState.notify("%s is staying. Welcome, neighbor!" % GameState.get_character(vid).get("name", ""))
				queue_free(), 150))
		v.add_child(row)
	_add_almost_there(v)


## [GOALS] One quiet line when a title is a single step away (and only then): what the step is, and
## the Almanac one tap away. No line, no button, on any other day.
func _add_almost_there(v: VBoxContainer) -> void:
	var near := Almanac.coming_up({}, 1)
	if near.is_empty() or int(near[0].need) - int(near[0].have) != 1:
		return
	var row := UiKit.hbox(8)
	row.name = "AlmostThere"
	var p := UiKit.para("★  One more and you're \"%s\". %s" % [str(near[0].name), str(near[0].how)], 18, ThemeBuilder.CREAM)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(p)
	row.add_child(UiKit.button("Almanac", func(): _open("res://scripts/ui/almanac_panel.gd"), 120))
	v.add_child(row)


func _open(path: String) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("open_panel"):
		main.open_panel(load(path).new())
	queue_free()
