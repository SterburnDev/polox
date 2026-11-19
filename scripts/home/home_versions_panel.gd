extends "res://scripts/ui/screen_panel.gd"
## My home > Timeline > Earlier versions: every bigger change (mapping again, new streets, kept research,
## Tell Polox, an undo) made a snapshot first, and any of them can be put back whole: the house, its
## places and its streets together. Putting one back snapshots what you have now first, so it's never a
## one-way door. (Separate from My home's main screen, which stays short.)

signal restored

const HomeStore := preload("res://scripts/home/home_store.gd")

var status: Label
var main: Node


func setup_versions(main_node: Node) -> void:
	main = main_node
	setup("Earlier versions", Vector2(760, 620))
	var list := UiKit.vbox(6)
	var snaps := HomeStore.snapshots()
	if snaps.is_empty():
		list.add_child(UiKit.para("None yet.", 18))
	for s in snaps.slice(0, 12):
		var row := UiKit.hbox(8)
		var l := UiKit.para("%s  (%s)" % [label(str(s.kind)), str(s.when)], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var path := str(s.path)
		var put := UiKit.button("Put back", func(): _confirm(path, l.text), 0)
		put.name = "Restore"
		row.add_child(put)
		list.add_child(row)
	body.add_child(UiKit.scroll(list))
	status = UiKit.para("", 16, ThemeBuilder.MUTED)
	body.add_child(status)


static func label(kind: String) -> String:
	match kind:
		"before_mapping": return "Before mapping again"
		"before_streets": return "Before new streets"
		"before_look_again": return "Before research"
		"before_restore": return "Before a put-back"
		"before_undo": return "Before an undo"
	return "Before %s" % kind.trim_prefix("before_").replace("_", " ")


func _confirm(path: String, what: String) -> void:
	var p: Control = load("res://scripts/ui/choice_panel.gd").new()
	if main and main.has_method("open_panel"):
		main.open_panel(p)
	else:
		add_child(p)
	p.ask("Put this back?", "%s. What you have now is kept as a version too." % what,
		[["Put it back", func(): put_back(path)], ["Not now", func(): pass]])


func put_back(path: String) -> bool:
	# (A copy first: the new "before_restore" snapshot may prune the oldest zip, which can be this one.)
	var copy := path + ".restoring"
	if DirAccess.copy_absolute(path, copy) != OK:
		status.text = "Couldn't read it. Nothing changed."
		return false
	var ok := HomeStore.snapshot("before_restore") != "" and HomeStore.restore(copy)
	DirAccess.remove_absolute(copy)
	if not ok:
		status.text = "Couldn't put it back. Nothing changed."
		return false
	status.text = "It's back."
	restored.emit()
	return true
