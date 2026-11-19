extends "res://scripts/ui/screen_panel.gd"
## The Quest log: small, optional goals from your residents (Requests from
## the day's Moments, and Dream Quests shaped by your dreams). Progress is
## checked in the world; "Let it go" any time, nothing is lost. Real-life
## steps are ticked by you, and can be switched off.

const Quests := preload("res://scripts/variety/quests.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")

var _list: VBoxContainer


func _ready() -> void:
	setup("Quests", Vector2(980, 640))
	var top := UiKit.flow_row(10)
	var real := CheckBox.new()
	real.text = "Real-life steps (gentle, self-ticked, at most 1 in 4)"
	real.button_pressed = bool(VarietySave.data().get("real_life", true))
	real.toggled.connect(func(on):
		VarietySave.data()["real_life"] = on
		VarietySave.save())
	top.add_child(real)
	body.add_child(top)
	_list = UiKit.vbox(10)
	body.add_child(UiKit.scroll(_list))
	refresh()


func refresh() -> void:
	Quests.check_all()
	for c in _list.get_children():
		c.queue_free()
	var act: Array = Quests.active()
	_list.add_child(UiKit.label("Open (%d)" % act.size(), 22, ThemeBuilder.YELLOW))
	if act.is_empty():
		_list.add_child(UiKit.para("Nothing open. Your friends will think of something soon: no rush.", 18, ThemeBuilder.MUTED))
	for q in act:
		_list.add_child(_card(q, true))
	var done: Array = Quests.done().duplicate()
	done.reverse()
	if not done.is_empty():
		_list.add_child(UiKit.label("Done (%d)" % done.size(), 22, ThemeBuilder.MINT))
		for q in done.slice(0, 12):
			_list.add_child(_card(q, false))


func _card(q: Dictionary, open: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, Color(ThemeBuilder.CREAM, 0.3), 2, 10, 10))
	var v := UiKit.vbox(4)
	p.add_child(v)
	v.add_child(UiKit.label(str(q.title), 18, ThemeBuilder.CREAM))
	if str(q.get("why", "")) != "":
		v.add_child(UiKit.para(str(q.why), 16, ThemeBuilder.MUTED))
	var hint := Quests.hint(q)
	if hint != "" and open:
		v.add_child(UiKit.para("Hint: " + hint, 16, ThemeBuilder.MUTED))
	if open:
		# [GOALS] What it is for, said before the work and not only after it.
		var gift := Quests.reward_preview(q)
		v.add_child(UiKit.para("For you when it's done: %s (%s)." % [str(gift.name), str(gift.words)], 16, ThemeBuilder.MINT))
	var row := UiKit.flow_row(8)
	if open:
		var bar := ProgressBar.new()
		bar.max_value = maxi(1, int(q.goal))
		bar.value = int(q.get("progress", 0))
		bar.custom_minimum_size = Vector2(200, 20)
		bar.show_percentage = false
		row.add_child(bar)
		row.add_child(UiKit.label("%d / %d" % [int(q.get("progress", 0)), int(q.goal)], 16, ThemeBuilder.MUTED))
		if str(q.template) == "real_life":
			row.add_child(UiKit.button("I did it", func():
				for d in Quests.did_it(str(q.id)):
					GameState.notify("✦ Proud of you. You got: %s" % str(d.get("reward", {}).get("name", "")))
				refresh(), 120))
		row.add_child(UiKit.button("Let it go", func():
			Quests.let_go(str(q.id))
			refresh(), 120))
	else:
		row.add_child(UiKit.label("✓ %s  •  %s" % [str(q.get("done", "")), str(q.get("reward", {}).get("name", ""))], 16, ThemeBuilder.MINT))
	v.add_child(row)
	return p
