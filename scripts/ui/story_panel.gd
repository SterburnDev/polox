extends "res://scripts/ui/screen_panel.gd"
## Menu > Story: where the story is (the chapter's scene and its few things to do, in any order,
## with no clock), the chapters you've finished and their titles, your friends' requests (let one
## go any time), the Battle Log and what you've collected.

const Story := preload("res://scripts/variety/story.gd")
const Requests := preload("res://scripts/variety/requests.gd")
const Visitors := preload("res://scripts/variety/visitors.gd")

var tab := "story"


func _ready() -> void:
	setup("Story", Vector2(980, 660))
	var tabs := UiKit.flow_row(8)   # (wraps on an upright phone)
	for t in [["story", "📖 Story"], ["requests", "💬 Requests"], ["log", "⚔ Battle Log"], ["found", "✦ Collection"]]:
		var b := UiKit.button(str(t[1]), func():
			tab = str(t[0])
			refresh(), 0)
		b.name = "Tab_" + str(t[0])
		b.toggle_mode = true   # (the open tab stays pressed)
		tabs.add_child(b)
	body.add_child(tabs)
	var content := UiKit.vbox(10)
	content.name = "Content"
	body.add_child(UiKit.scroll(content))
	refresh()


func _content() -> VBoxContainer:
	return body.find_child("Content", true, false)


func refresh() -> void:
	var v := _content()
	if v == null:
		return
	for t in ["story", "requests", "log", "found"]:
		var tb: Button = find_child("Tab_" + t, true, false)
		if tb:
			tb.set_pressed_no_signal(t == tab)
			var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
			if t == tab and (focused == null or str(focused.name).begins_with("Tab_")):
				tb.grab_focus.call_deferred()   # (the keyboard outline follows the open tab)
	for c in v.get_children():
		v.remove_child(c)   # (gone at once, so the new rows keep their places)
		c.queue_free()
	var counts := Story.counts()
	match tab:
		"story":
			var st := Story.status(counts)
			if (st.current as Dictionary).is_empty():
				v.add_child(UiKit.para("Every chapter's done. It keeps going.", 20))
			else:
				v.add_child(UiKit.label("Chapter %d: %s" % [int(st.chapter) + 1, str(st.current.title)], 26, ThemeBuilder.YELLOW))
				v.add_child(UiKit.para(str(st.current.scene), 20))
				for p in st.progress:
					v.add_child(UiKit.para("%s  %s  (%d/%d)" % ["✓" if int(p[0]) >= int(p[1]) else "○", str(p[2]), int(p[0]), int(p[1])], 18, ThemeBuilder.CREAM))
				v.add_child(UiKit.para("Any order. No rush.", 16, ThemeBuilder.MUTED))
			for ch in Story.CHAPTERS:
				if str(ch.id) in st.done:
					v.add_child(UiKit.para("✓ %s  —  title: %s" % [str(ch.title), str(ch.reward.title)], 18, ThemeBuilder.MUTED))
		"requests":
			var open := Requests.open()
			if open.is_empty():
				v.add_child(UiKit.para("None right now, and never a deadline.", 18, ThemeBuilder.MUTED))
			for r in open:
				var c := GameState.get_character(str(r.giver))
				var row := UiKit.hbox(8)
				var l := UiKit.para("%s: \"%s\"" % [str(c.get("name", "A friend")), str(r.text)], 18)
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(l)
				row.add_child(UiKit.button("Let it go", func():
					Requests.let_go(str(r.id))
					refresh(), 140))
				v.add_child(row)
		"log":
			var logbook: Array = GameState.world.get("battle_log", []) if GameState.world.get("battle_log") is Array else []
			if logbook.is_empty():
				v.add_child(UiKit.para("No battles yet.", 18, ThemeBuilder.MUTED))
			var words := {"won": "won", "spared": "spared", "ran": "ran off", "knocked_down": "got back up"}
			for i in range(logbook.size() - 1, maxi(-1, logbook.size() - 40), -1):
				var b: Dictionary = logbook[i]
				var foes := (b.get("enemies", []) as Array).map(func(e): return str(e.get("name", "?")))
				v.add_child(UiKit.para("%s  •  %s: %s vs %s, %s" % [str(b.get("when", "")).substr(0, 10), str(b.get("battle", "A battle")), ", ".join(PackedStringArray(b.get("party", []))), ", ".join(PackedStringArray(foes)), str(words.get(str(b.get("outcome", "")), b.get("outcome", "")))], 18))
		"found":
			v.add_child(UiKit.para("✦ Dark Crystals found: %d" % int(counts.crystals), 20))
			v.add_child(UiKit.para("🌀 Visits to the Deep: %d" % int(counts.dark_visits), 20))
			v.add_child(UiKit.para("⚔ Battles: %d (spared: %d)" % [int(counts.battles), int(counts.spared)], 20))
			v.add_child(UiKit.para("🗺 Places: %d" % int(counts.places), 20))
			v.add_child(UiKit.para("More in the Almanac.", 16, ThemeBuilder.MUTED))
			var travelers := Visitors.passed()
			if not travelers.is_empty():
				v.add_child(UiKit.label("Travellers", 20, ThemeBuilder.YELLOW))
				v.add_child(UiKit.para("Invite anyone back, any time.", 16, ThemeBuilder.MUTED))
			for i in range(travelers.size() - 1, -1, -1):
				var rec: Dictionary = travelers[i]
				var row := UiKit.hbox(8)
				var l := UiKit.para("%s: %s" % [str(rec.get("name", "")), str(rec.get("about", ""))], 18)
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(l)
				var b := UiKit.button("Invite back", func():
					var id := Visitors.invite_back(i, GameState.current_room_id)
					if id != "":
						GameState.notify("%s is back to stay." % str(rec.get("name", "")))
						var main := get_tree().current_scene
						if main and main.get("game") and main.game.has_method("refresh_character"):
							main.game.refresh_character(id)
					refresh(), 150)
				b.name = "InviteBack_%d" % i
				row.add_child(b)
				v.add_child(row)
