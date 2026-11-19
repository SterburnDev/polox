extends Control
## "Where was I?": a small card when a world opens. Where you were, the last
## thing said in a chat (and when), and one of your dreams to cheer on.
## Never in the way: it sits at the top, closes itself after a while, and a
## tap on "Got it" (or anywhere on it) closes it sooner.

signal talk_requested(character_id: String)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Slots := preload("res://scripts/core/slots.gd")

const SHOW_SECONDS := 20.0

var lines: Array = []           # [icon, text]
var friend_id := ""             # who you last talked to (if they're in this room)
var _t := 0.0


## What the card would say, from the save files ({} = nothing worth showing).
## `last_played` is the world's previous "last played" time.
static func build_recap(last_played: String) -> Dictionary:
	if last_played == "":
		return {}
	var out := {"lines": [], "friend": ""}
	var room := SaveManager.load_room(GameState.current_room_id)
	out.lines.append(["📍", "You were in %s." % str(room.get("name", GameState.current_room_id))])
	var Story: Script = load("res://scripts/variety/story.gd")
	var st: Dictionary = Story.status()
	if not (st.current as Dictionary).is_empty():
		out.lines.append(["📖", "Chapter %d, %s, is waiting whenever you like." % [int(st.chapter) + 1, str(st.current.title)]])
	var asks: Array = load("res://scripts/variety/requests.gd").open()
	if not asks.is_empty():
		out.lines.append(["💬", "%s asked you something (Menu > Story)." % str(GameState.get_character(str(asks[0].giver)).get("name", "A friend"))])
	out.lines.append(["✦", "Nothing was missed while you were away."])
	var best: Dictionary = {}
	for id in ChatLog.logged_characters():
		for e in ChatLog.recent(id, 6):
			if not str(e.get("role", "")) in ["user", "ai"] or str(e.get("kind", "")) == "npc_chat":
				continue
			if best.is_empty() or str(e.get("ts", "")) > str(best.get("ts", "")):
				best = e
	if not best.is_empty():
		var c := GameState.get_character(str(best.get("character", "")))
		var who := "You" if str(best.role) == "user" else str(c.get("name", "A friend"))
		var text := str(best.get("text", ""))
		if text.length() > 90:
			text = text.substr(0, 88).strip_edges() + "…"
		var with_name := str(c.get("name", "a friend"))
		out.lines.append(["💬", "Last chat with %s (%s): %s said “%s”" % [with_name, Slots.ago_text(str(best.ts)), who, text]])
		if str(c.get("home_room", "")) == GameState.current_room_id:
			out["friend"] = str(c.get("id", ""))
	for d in GameState.dream_list():
		if str(d.get("status", "dreaming")) != "done" and str(d.get("text", "")) != "":
			out.lines.append(["🌱", "A dream to cheer on: %s" % str(d.text)])
			break
	return out


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -380
	offset_right = 380
	offset_top = 76
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(&"polox_hud_card")   # (hidden while building: hud.gd set_building)
	# [GLASS_UI] Liquid Glass, like the Today card.
	var panel: PanelContainer = preload("res://scripts/ui/liquid_glass.gd").new()
	panel.radius = 18.0
	panel.pad = Vector4(16, 12, 16, 12)
	panel.tint = Color(ThemeBuilder.PANEL, 0.62)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(ev):
		if preload("res://scripts/ui/ui_kit.gd").tap_down(ev):
			close())
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(panel)
	var v := UiKit.vbox(6)
	panel.add_child(v)
	var head := UiKit.hbox(8)
	head.add_child(UiKit.label("Where was I?", 26, ThemeBuilder.YELLOW))
	head.add_child(UiKit.spacer())
	if friend_id != "":
		var c := GameState.get_character(friend_id)
		var talk := UiKit.button("Talk to %s" % c.get("name", ""), func():
			talk_requested.emit(friend_id)
			close(), 0)
		head.add_child(talk)
	head.add_child(UiKit.button("Got it", close, 110))
	v.add_child(head)
	for l in lines:
		v.add_child(UiKit.para("%s  %s" % [l[0], l[1]], 18, ThemeBuilder.CREAM))
	# Keep it inside narrow (phone) screens.
	var w := minf(760.0, get_viewport_rect().size.x - 24.0)
	offset_left = -w / 2.0
	offset_right = w / 2.0


func _process(delta: float) -> void:
	_t += delta
	if _t > SHOW_SECONDS:
		modulate.a = maxf(0.0, 1.0 - (_t - SHOW_SECONDS))
		if modulate.a <= 0.0:
			close()


func close() -> void:
	queue_free()
