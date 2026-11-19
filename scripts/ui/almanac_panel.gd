extends "res://scripts/ui/screen_panel.gd"
## The Almanac: what your world has grown into, and titles you can wear.
## Just a gentle log: nothing to keep up, nothing to lose.

const Almanac := preload("res://scripts/variety/almanac.gd")
const DreamDoors := preload("res://scripts/variety/dream_doors.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")

var _v: VBoxContainer


func _ready() -> void:
	setup("Almanac", Vector2(900, 640))
	_v = UiKit.vbox(8)
	body.add_child(UiKit.scroll(_v))
	refresh()


func refresh() -> void:
	for c in _v.get_children():
		c.queue_free()
	var c := Almanac.counts()
	_add_coming_up(c)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for r in Almanac.ROWS:
		grid.add_child(UiKit.label(str(r[1]), 18, ThemeBuilder.CREAM))
		grid.add_child(UiKit.label(str(c.get(str(r[0]), 0)), 18, ThemeBuilder.YELLOW))
	_v.add_child(grid)
	_v.add_child(UiKit.label("Titles", 22, ThemeBuilder.YELLOW))
	var titles := Almanac.titles(c)
	if titles.is_empty():
		_v.add_child(UiKit.para("Titles appear here as your world grows. There's no hurry.", 16, ThemeBuilder.MUTED))
	var row := UiKit.flow_row(8)
	for t in titles:
		var b := UiKit.button(str(t.name), func():
			Almanac.wear(str(t.name))
			GameState.notify("You're %s now." % str(t.name))
			refresh(), 0)
		b.toggle_mode = true
		b.set_pressed_no_signal(Almanac.worn() == str(t.name))
		row.add_child(b)
	if Almanac.worn() != "":
		row.add_child(UiKit.button("No title", func():
			Almanac.wear("")
			refresh(), 120))
	_v.add_child(row)
	var archive: Array = VarietySave.data().dream_archive
	if not archive.is_empty():
		_v.add_child(UiKit.label("Dream Archive (last %d)" % DreamDoors.ARCHIVE_MAX, 22, ThemeBuilder.YELLOW))
		var rev := archive.duplicate()
		rev.reverse()
		for a in rev:
			var r := UiKit.flow_row(8)
			r.add_child(UiKit.label("%s  •  %s" % [str(a.get("name", "")), str(a.get("date", ""))], 16, ThemeBuilder.CREAM))
			var id := str(a.get("id", ""))
			r.add_child(UiKit.button("Visit", func():
				var main := get_tree().current_scene
				close()
				if main and main.get("game"):
					main.game.go_to_room(id), 90))
			r.add_child(UiKit.button("Keep", func():
				DreamDoors.keep(id)
				GameState.notify("Kept: it's a normal room now (Rooms list).")
				refresh(), 90))
			_v.add_child(r)


## [GOALS] "Coming up": the titles nearest to being earned, how far along each is and what moves it.
## A suggestion, never a chore: it says so, and it disappears when every title is earned.
func _add_coming_up(c: Dictionary) -> void:
	var near := Almanac.coming_up(c, 3)
	if near.is_empty():
		return
	_v.add_child(UiKit.label("Coming up", 22, ThemeBuilder.YELLOW))
	for n in near:
		var card := UiKit.vbox(2)
		card.name = "ComingUp_" + str(n.from)
		var head := UiKit.flow_row(10)
		head.add_child(UiKit.label(str(n.name), 18, ThemeBuilder.CREAM))
		var bar := ProgressBar.new()
		bar.max_value = maxi(1, int(n.need))
		bar.value = int(n.have)
		bar.custom_minimum_size = Vector2(180, 18)
		bar.show_percentage = false
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(bar)
		head.add_child(UiKit.label("%d of %d  •  %s" % [int(n.have), int(n.need), str(n.label)], 16, ThemeBuilder.MUTED))
		card.add_child(head)
		if str(n.how) != "":
			card.add_child(UiKit.para(str(n.how), 16, ThemeBuilder.MUTED))
		_v.add_child(card)
	_v.add_child(UiKit.para("Only if you feel like it. Nothing here runs out, and what you've earned stays earned.", 16, ThemeBuilder.MUTED))
	_v.add_child(UiKit.label("Your world so far", 22, ThemeBuilder.YELLOW))
