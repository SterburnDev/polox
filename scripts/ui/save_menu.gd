extends "res://scripts/ui/screen_panel.gd"
## Worlds: every save slot as a card (grid or list), with search, sort and
## tag filters, a look of its own (theme presets), and all the slot actions.
## One-handed: everything is a big button; clicking a card plays it.

signal load_requested(id: String)
signal new_requested(blank: bool, world_name: String)

const Slots := preload("res://scripts/core/slots.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const SaveCard := preload("res://scripts/ui/save_card.gd")
const SlotActions := preload("res://scripts/ui/slot_actions.gd")
const TrashPanel := preload("res://scripts/ui/trash_panel.gd")
const MenuLook := preload("res://scripts/ui/save_menu_look.gd")

const SORTS := [["played", "Last played"], ["name", "Name"], ["playtime", "Playtime"], ["created", "Newest"]]

var prefs: Dictionary = {}
var _cards_box: Container
var _scroll: ScrollContainer
var _search: LineEdit
var _sort: OptionButton
var _tag: OptionButton
var _layout_btn: Button
var _tags: Array = [""]
var _count: Label


func _ready() -> void:
	prefs = MenuLook.prefs()
	setup("Worlds", Vector2(1200, 700))
	MenuLook.apply(self, prefs)
	var top := UiKit.flow_row(8)   # rows wrap so the panel fits a portrait phone
	_search = UiKit.line_edit("Search names, notes, tags...")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): refresh())
	top.add_child(_search)
	_sort = UiKit.option(SORTS.map(func(s): return s[1]), maxi(0, SORTS.map(func(s): return s[0]).find(str(prefs.get("sort", "played")))))
	_sort.item_selected.connect(func(i): _set_pref("sort", SORTS[i][0]))
	_sort.tooltip_text = "Sort"
	top.add_child(_sort)
	_tag = UiKit.option(["All tags"])
	_tag.item_selected.connect(func(i): _set_pref("tag", _tags[i]))
	top.add_child(_tag)
	_layout_btn = UiKit.button("", func(): _set_pref("layout", "list" if str(prefs.get("layout", "grid")) == "grid" else "grid"), 110)
	_layout_btn.tooltip_text = "Grid or list"
	top.add_child(_layout_btn)
	body.add_child(top)
	_scroll = ScrollContainer.new()
	_scroll.scroll_deadzone = preload("res://scripts/ui/ui_kit.gd").touch_deadzone()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	var bottom := UiKit.flow_row(8)
	_count = UiKit.label("", 18, ThemeBuilder.MUTED)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_count)
	bottom.add_child(UiKit.button("+ New world", _new_world, 160))
	bottom.add_child(UiKit.button("Import .polox", _import, 170))
	bottom.add_child(UiKit.button("Trash", _trash, 100))
	bottom.add_child(UiKit.button("Look", _look, 100))
	body.add_child(bottom)
	refresh()


func _set_pref(key: String, value: Variant) -> void:
	prefs[key] = value
	MenuLook.save_prefs(prefs)
	refresh()


## Rebuilds the cards from disk (cheap: slots are small folders).
func refresh() -> void:
	if _scroll == null:
		return
	for c in _scroll.get_children():
		c.free()
	var grid := str(prefs.get("layout", "grid")) == "grid"
	_layout_btn.text = "▦ Grid" if grid else "☰ List"
	if grid:
		var g := GridContainer.new()
		g.columns = 1 if UiKit.upright_phone() else 3
		g.add_theme_constant_override("h_separation", 12)
		g.add_theme_constant_override("v_separation", 12)
		_cards_box = g
	else:
		_cards_box = UiKit.vbox(8)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_cards_box)
	var all := Slots.list()
	_refresh_tags(all)
	var shown := _filtered(all)
	for m in shown:
		var card := SaveCard.new()
		card.build(m, grid, prefs, m.id == SaveManager.slot_id)
		card.play.connect(func(): load_requested.emit(str(m.id)))
		card.more.connect(func(): _actions(str(m.id)))
		_cards_box.add_child(card)
	if shown.is_empty():
		_cards_box.add_child(UiKit.para("No worlds yet. Press + New world to begin one, or Import a .polox bundle." if all.is_empty() else "Nothing matches that search.", 20, ThemeBuilder.MUTED))
	_count.text = "%d world%s" % [all.size(), "" if all.size() == 1 else "s"] + (", %d shown" % shown.size() if shown.size() != all.size() else "")


func _refresh_tags(all: Array) -> void:
	var tags: Array = [""]
	for m in all:
		for t in m.get("tags", []):
			if not str(t) in tags:
				tags.append(str(t))
	if tags != _tags:
		_tags = tags
		_tag.clear()
		_tag.add_item("All tags")
		for t in tags.slice(1):
			_tag.add_item("#" + str(t))
	_tag.select(maxi(0, _tags.find(str(prefs.get("tag", "")))))


func _filtered(all: Array) -> Array:
	var q := _search.text.strip_edges().to_lower()
	var tag := str(prefs.get("tag", ""))
	var out: Array = all.filter(func(m):
		if tag != "" and not tag in m.get("tags", []):
			return false
		if q == "":
			return true
		var hay := (str(m.name) + " " + str(m.notes) + " " + " ".join(m.get("tags", []))).to_lower()
		return hay.find(q) != -1)
	match str(prefs.get("sort", "played")):
		"name":
			out.sort_custom(func(a, b): return str(a.name).to_lower() < str(b.name).to_lower())
		"playtime":
			out.sort_custom(func(a, b): return int(a.playtime_s) > int(b.playtime_s))
		"created":
			out.sort_custom(func(a, b): return str(a.created) > str(b.created))
		_:
			out.sort_custom(func(a, b): return str(a.last_played) > str(b.last_played))
	return out


func _actions(id: String) -> void:
	var a := SlotActions.new()
	a.slot_id = id
	a.menu = self
	a.play.connect(func(): load_requested.emit(id))
	a.changed.connect(refresh)
	_open_sub(a)


func _new_world() -> void:
	var c := preload("res://scripts/ui/new_world_panel.gd").new()
	c.chosen.connect(func(blank: bool, world_name: String): new_requested.emit(blank, world_name))
	_open_sub(c)


func _trash() -> void:
	var t := TrashPanel.new()
	t.changed.connect(refresh)
	_open_sub(t)


func _look() -> void:
	var l := MenuLook.panel(prefs)
	l.changed.connect(func(p):
		prefs = p
		MenuLook.apply(self, prefs)
		refresh())
	_open_sub(l)


func _import() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.polox, *.zip ; Polox world bundles"])
	fd.use_native_dialog = not OS.has_feature("web")
	fd.title = "Pick a .polox bundle"
	fd.current_dir = SaveManager.global_path("exports")
	fd.file_selected.connect(func(path):
		var r := SlotArchive.import_bundle(path)
		GameState.notify(("Imported as \"%s\" ✓" % Slots.meta(r.id).name) if r.ok else ("Couldn't import: " + str(r.error)))
		refresh()
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))


## Sub-panels open on top of this screen (Main's back stack handles them).
func _open_sub(p: Control) -> void:
	var shell := get_tree().current_scene
	if shell and shell.has_method("open_panel"):
		shell.open_panel(p)
	else:
		add_child(p)
