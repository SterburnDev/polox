extends "res://scripts/ui/screen_panel.gd"
## Log Viewer: every chat message ever sent, filterable by character, room
## and date, with search and export to a dated .txt + .jsonl.

const DATE_RANGES := ["All time", "Today", "Last 7 days", "Last 30 days"]
const PAGE := 200

var _char_ids: Array = [""]
var _room_ids: Array = [""]
var _char_opt: OptionButton
var _room_opt: OptionButton
var _date_opt: OptionButton
var _search: LineEdit
var _list: RichTextLabel
var _count: Label
var _names: Dictionary = {}
var _entries: Array = []       # the filtered result, newest last
var _page := 0                 # 0 = newest page
var _older_btn: Button
var _newer_btn: Button


func _ready() -> void:
	setup("Chat Log", Vector2(1180, 680))
	for id in GameState.characters:
		_names[id] = str(GameState.characters[id].get("name", id))
	var char_items := ["All characters"]
	var ids := ChatLog.logged_characters()
	for id in GameState.characters:
		if not id in ids:
			ids.append(id)
	for id in ids:
		_char_ids.append(id)
		char_items.append(_names.get(id, id))
	var room_items := ["All rooms"]
	for id in SaveManager.list_rooms():
		_room_ids.append(id)
		room_items.append(str(SaveManager.load_room(id).get("name", id)))
	var filters := UiKit.flow_row(10)
	_char_opt = UiKit.option(char_items)
	_room_opt = UiKit.option(room_items)
	_date_opt = UiKit.option(DATE_RANGES)
	_search = UiKit.line_edit("Search words...")
	for o in [_char_opt, _room_opt, _date_opt]:
		o.item_selected.connect(func(_i): refresh())
		filters.add_child(o)
	_search.text_changed.connect(func(_t): refresh())
	filters.add_child(_search)
	body.add_child(filters)
	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.scroll_following = true
	_list.selection_enabled = true
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("normal_font_size", 20)
	_list.add_theme_stylebox_override("normal", ThemeBuilder.box(ThemeBuilder.BG, Color(ThemeBuilder.CREAM, 0.3), 2, 10, 10))
	body.add_child(_list)
	var actions := UiKit.flow_row(10)
	_count = UiKit.label("", 18, ThemeBuilder.MUTED)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_count)
	_older_btn = UiKit.button("◀ Older", func(): _show_page(_page + 1), 120)
	_newer_btn = UiKit.button("Newer ▶", func(): _show_page(_page - 1), 120)
	actions.add_child(_older_btn)
	actions.add_child(_newer_btn)
	actions.add_child(UiKit.button("Export these", _export, 180))
	actions.add_child(UiKit.button("Open logs folder", func(): SaveManager.open_folder("logs"), 220))
	actions.add_child(UiKit.button("Open exports", func(): SaveManager.open_folder("exports"), 190))
	body.add_child(actions)
	refresh()


func current_filters() -> Dictionary:
	var f := {
		"character": _char_ids[_char_opt.selected],
		"room": _room_ids[_room_opt.selected],
		"search": _search.text.strip_edges(),
	}
	var days: int = [0, 0, 6, 29][_date_opt.selected]
	if _date_opt.selected > 0:
		var unix: float = Time.get_unix_time_from_system() - days * 86400
		f["date_from"] = Time.get_date_string_from_unix_time(int(unix) + _utc_offset())
	return f


## Local-time offset in seconds (log timestamps are local time).
func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## Re-runs the filters (the whole log is parsed once per change, not per page).
func refresh() -> void:
	_entries = ChatLog.query(current_filters())
	_show_page(0)


## One page of PAGE messages; page 0 is the newest.
func _show_page(page: int) -> void:
	var pages := maxi(1, ceili(_entries.size() / float(PAGE)))
	_page = clampi(page, 0, pages - 1)
	var end := _entries.size() - _page * PAGE
	var shown := _entries.slice(maxi(0, end - PAGE), end)
	_older_btn.disabled = _page >= pages - 1
	_newer_btn.disabled = _page <= 0
	var lines := PackedStringArray()
	var last_day := ""
	for e in shown:
		var ts := str(e.get("ts", ""))
		var day := ts.substr(0, 10)
		if day != last_day:
			lines.append("\n[color=#ffd166][b]— %s —[/b][/color]" % day)
			last_day = day
		var who := "You" if e.get("role") == "user" else str(_names.get(e.get("character", ""), e.get("character", "?")))
		var color := "#7ad6b0" if e.get("role") == "user" else "#ffb3c7"
		if e.get("role") == "note":
			who = "✦"
			color = "#ffd166"
		var tag := ""
		if str(e.get("kind", "")) == "npc_chat":
			tag = " [color=#b8aed6](to %s)[/color]" % _names.get(e.get("with", ""), e.get("with", ""))
		if e.get("emotion", "") != "" and e.get("role") != "user":
			tag += " [color=#b8aed6](%s)[/color]" % e.get("emotion")
		if e.get("failed", false):
			tag += " [color=#ff7b7b](AI offline: fallback line)[/color]"
		var room_name := str(e.get("room", ""))
		lines.append("[color=#b8aed6]%s %s[/color]  [color=%s]%s[/color]%s: %s" % [ts.substr(11, 5), room_name, color, who, tag, _escape(str(e.get("text", "")))])
	_list.text = "\n".join(lines) if not lines.is_empty() else "[color=#b8aed6]No messages yet. Go say hi to someone![/color]"
	if _entries.size() > PAGE:
		_count.text = "%d messages • page %d of %d" % [_entries.size(), _page + 1, pages]
	else:
		_count.text = "%d messages" % _entries.size()


func _escape(t: String) -> String:
	return t.replace("[", "[lb]")


func _export() -> void:
	var files := ChatLog.export(current_filters(), _names)
	if files.is_empty():
		GameState.notify("Couldn't write the export. Is the save folder read-only?")
	else:
		var phone: Node = get_tree().current_scene.get("phone") if get_tree().current_scene else null
		if phone != null:
			var r: Dictionary = await phone.share_export(files[0])
			GameState.notify(phone.share_text("Exported " + files[0].get_file(), r).replace("\n", ": "))
			return
		GameState.notify("Exported to exports/%s" % files[0].get_file())
