extends PanelContainer
## One world on the Worlds screen: cover (or emoji), name, stats, tags,
## and two big buttons (Play, More). Grid cards stack vertically; list rows
## put the cover on the left.

signal play
signal more

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Slots := preload("res://scripts/core/slots.gd")


func build(m: Dictionary, grid: bool, prefs: Dictionary, active: bool) -> void:
	var accent := Color.from_string(str(m.get("accent", "#c9b6ff")), Color("#c9b6ff"))
	var radius: int = {"round": 14, "square": 2, "double": 10}.get(str(prefs.get("frame", "round")), 14)
	var border := 5 if str(prefs.get("frame", "round")) == "double" else 3
	add_theme_stylebox_override("panel", ThemeBuilder.box(Color(ThemeBuilder.PANEL_LIGHT, 0.9), accent if active else Color(accent, 0.6), border, radius, 10))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var font := int(prefs.get("font", 22))
	var stacked := grid or UiKit.upright_phone()   # a list row is too wide for a phone held upright
	var outer: BoxContainer = UiKit.vbox(6) if stacked else UiKit.hbox(12)
	add_child(outer)
	outer.add_child(_cover(m, accent, Vector2(300, 168) if stacked else Vector2(160, 90)))
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(info)
	var title := UiKit.label("%s %s%s" % [m.get("emoji", ""), m.get("name", ""), "  (playing)" if active else ""], font + 2, accent)
	title.clip_text = true
	info.add_child(title)
	var st: Dictionary = m.get("stats", {})
	var bits := PackedStringArray()
	bits.append("%d room%s" % [st.get("rooms", 0), "" if int(st.get("rooms", 0)) == 1 else "s"])
	bits.append("%d friend%s" % [st.get("characters", 0), "" if int(st.get("characters", 0)) == 1 else "s"])
	if int(st.get("items", 0)) > 0:
		bits.append("%d items" % st.get("items", 0))
	bits.append(Slots.size_text(int(st.get("bytes", 0))))
	info.add_child(UiKit.label(" • ".join(bits), font - 4, ThemeBuilder.MUTED))
	var when := Slots.ago_text(str(m.get("last_played", "")))
	if int(m.get("playtime_s", 0)) > 0:
		when += " • played " + Slots.playtime_text(int(m.get("playtime_s", 0)))
	info.add_child(UiKit.label(when, font - 4, ThemeBuilder.MUTED))
	var conflicts := preload("res://scripts/phone/sync_files.gd").conflicts(SaveManager.root, str(m.get("id", ""))).size()
	if conflicts > 0:
		var warn := UiKit.label("⚠ %d phone conflict%s (⋯ to look)" % [conflicts, "" if conflicts == 1 else "s"], font - 4, ThemeBuilder.YELLOW)
		info.add_child(warn)
	var tags: Array = m.get("tags", [])
	if not tags.is_empty():
		var tl := UiKit.label("#" + "  #".join(tags), font - 5, accent)
		tl.clip_text = true
		info.add_child(tl)
	if not grid and str(m.get("notes", "")) != "":
		var notes := UiKit.para(str(m.notes), font - 5, Color(ThemeBuilder.CREAM, 0.8))
		notes.max_lines_visible = 2
		info.add_child(notes)
	var row := UiKit.hbox(6)
	if stacked:
		outer.add_child(row)
	else:
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		outer.add_child(row)
	var play_btn := UiKit.button("▶ Play" if not active else "▶ Resume", func(): play.emit(), 150)
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL if stacked else Control.SIZE_FILL
	play_btn.tooltip_text = "Load this world"
	row.add_child(play_btn)
	var more_btn := UiKit.button("⋯", func(): more.emit(), 64)
	more_btn.tooltip_text = "Rename, copy, back up, restore, export, delete..."
	row.add_child(more_btn)


func _cover(m: Dictionary, accent: Color, size: Vector2) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = size
	frame.add_theme_stylebox_override("panel", ThemeBuilder.box(Color(accent, 0.25), Color(accent, 0.5), 1, 8, 0))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var path := Slots.cover_path(str(m.get("id", "")))
	var tex: Texture2D = SaveManager.load_texture(path) if path != "" else null
	if tex:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = size
		pic.clip_contents = true
		frame.add_child(pic)
	else:
		var e := UiKit.label(str(m.get("emoji", "🌙")), int(size.y * 0.5), accent)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(e)
	return frame
