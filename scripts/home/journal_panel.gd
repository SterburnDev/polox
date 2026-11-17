extends "res://scripts/ui/screen_panel.gd"
## Your journal, written at your desk (or anywhere at home): a line or a page about your day. It's yours
## alone: kept in my_home/journal.json on this computer, never synced, sent or shown to a friend.
## [GLASS_UI] A paper notebook (early iOS): a ruled cream page with a red margin and punched holes, ink
## for your words, and coloured tabs standing out from its edge, Write and Pages. Turning to the other tab
## turns the page (a paper sound and a short slide; just a fade with Reduce motion).
## Tags: [GLASS_UI]

const HomeStore := preload("res://scripts/home/home_store.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Synth := preload("res://scripts/core/synth.gd")

const PAPER := Color("#f7f0dc")
const INK := Color("#2b2546")
const RED_INK := Color("#b8434f")
const RULE := Color("#9cc3d8")
const TABS := {"write": ["Write", Color("#ffd166")], "pages": ["Pages", Color("#7ad6b0")]}

var text_box: TextEdit
var _list: VBoxContainer
var _page: Control              # the paper
var _write: Control             # what's on the Write page
var _pages: Control             # what's on the Pages page
var _tabs: Dictionary = {}      # id -> Button
var showing := "write"


static func entries() -> Array:
	var d: Variant = JsonUtil.read_json(HomeStore.path("journal.json"), {})
	return (d.get("entries", []) if d is Dictionary and d.get("entries") is Array else [])


static func write(text: String) -> bool:
	var t := text.strip_edges()
	if t == "":
		return false
	var e := entries()
	e.append({"date": Time.get_datetime_string_from_system(false, true).left(16), "text": t.left(4000)})
	return JsonUtil.write_json(HomeStore.path("journal.json"), {"version": 1, "entries": e})


func _ready() -> void:
	setup("Journal", Vector2(900, 660))
	body.add_child(UiKit.para("Just for you. It stays on this computer.", 16, ThemeBuilder.MUTED))
	var book := UiKit.hbox(0)
	book.name = "Notebook"
	book.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(book)
	_page = Paper.new()
	_page.name = "Paper"
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	book.add_child(_page)
	var margin := MarginContainer.new()
	UiKit.fill(margin)
	margin.add_theme_constant_override("margin_left", int(Paper.MARGIN_X + 14.0))
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	_page.add_child(margin)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)
	# Write: your words in ink on the page.
	var w := UiKit.vbox(10)
	UiKit.fill(w)
	stack.add_child(w)
	_write = w
	text_box = UiKit.text_edit("Today...", "", 140)
	text_box.name = "JournalText"
	_ink(text_box)
	text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	w.add_child(text_box)
	var save := UiKit.button("Keep it", func():
		if write(text_box.text):
			text_box.text = ""
			_fill()
			show_tab("pages"), 0)
	save.name = "KeepEntry"
	save.size_flags_horizontal = Control.SIZE_SHRINK_END
	w.add_child(save)
	# Pages: what you wrote, newest first.
	_list = UiKit.vbox(8)
	var sc := UiKit.page(_list)
	UiKit.fill(sc)
	sc.visible = false
	stack.add_child(sc)
	_pages = sc
	# The tabs, standing out from the page's right edge.
	var tabs := UiKit.vbox(6)
	tabs.name = "Tabs"
	book.add_child(tabs)
	for id in TABS:
		var spec: Array = TABS[id]
		var b := UiKit.button(str(spec[0]), func(): show_tab(id), 0)
		b.name = "Tab_" + str(id)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(112, 64)
		_tab_look(b, spec[1])
		tabs.add_child(b)
		_tabs[id] = b
	_fill()
	_mark()


## Turns to a tab ("write" or "pages"): a paper sound and the page slides in (a fade with Reduce motion).
func show_tab(id: String) -> void:
	if not TABS.has(id):
		return
	var changed := id != showing
	showing = id
	_write.visible = id == "write"
	_pages.visible = id == "pages"
	_mark()
	if not changed:
		return
	if bool(GameState.settings.get("ui_sounds", true)):
		Synth.play(self, "page", 0.5)
	var shown: Control = _write if id == "write" else _pages
	shown.modulate.a = 0.0
	var tw := shown.create_tween()
	if not preload("res://scripts/ui/anim_fx.gd").reduced():
		shown.position.x = 40.0
		tw.parallel().tween_property(shown, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(shown, "modulate:a", 1.0, 0.18)


func _mark() -> void:
	for id in _tabs:
		(_tabs[id] as Button).set_pressed_no_signal(id == showing)


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var e := entries()
	e.reverse()
	for x in e:
		_list.add_child(UiKit.label(str(x.get("date", "")), 16, RED_INK))
		_list.add_child(UiKit.para(str(x.get("text", "")), 18, INK))


## A text box that's part of the page: no box of its own, ink on paper, the rules showing through.
static func _ink(t: TextEdit) -> void:
	for state in ["normal", "focus", "read_only"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 2
		sb.content_margin_top = 2
		t.add_theme_stylebox_override(state, sb)
	t.add_theme_color_override("font_color", INK)
	t.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	t.add_theme_color_override("caret_color", RED_INK)
	t.add_theme_color_override("selection_color", Color(ThemeBuilder.YELLOW, 0.5))
	t.add_theme_constant_override("line_spacing", int(Paper.RULE_STEP) - 26)


## A tab: a coloured card standing out from the page, raised when it's not the open one and pressed in
## (flush with the page) when it is.
static func _tab_look(b: Button, c: Color) -> void:
	var T := ThemeBuilder
	var up := T.box(c.darkened(0.2), c.darkened(0.45), 2, 12, 8)
	up.corner_radius_top_left = 0
	up.corner_radius_bottom_left = 0
	up.content_margin_left = 10
	up.shadow_color = Color(0, 0, 0, 0.3)
	up.shadow_size = 3
	up.shadow_offset = Vector2(2, 2)
	var on := up.duplicate() as StyleBoxFlat
	on.bg_color = c
	on.border_color = c.darkened(0.3)
	on.content_margin_left = 4
	on.expand_margin_left = 6
	on.shadow_size = 0
	var over := up.duplicate() as StyleBoxFlat
	over.bg_color = c.darkened(0.08)
	for s in ["normal", "disabled"]:
		b.add_theme_stylebox_override(s, up)
	b.add_theme_stylebox_override("hover", over)
	for s in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(s, on)
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, INK)


## The page: cream paper, darker towards the binding, blue rules, a red margin line, three punched holes
## and a soft shadow where the page meets the tabs.
class Paper extends Control:
	const MARGIN_X := 62.0
	const RULE_STEP := 34.0
	const TOP := 58.0

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s := size
		var r := Rect2(Vector2.ZERO, s)
		var sb := StyleBoxFlat.new()
		sb.bg_color = PAPER
		sb.set_corner_radius_all(10)
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_right = 2
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		# Towards the binding (left) the paper is a touch darker, as a page curving into it.
		for i in 10:
			draw_rect(Rect2(i * 3.0, 0, 3.0, s.y), Color(0.45, 0.35, 0.2, 0.06 * (1.0 - i / 10.0)))
		var y := TOP
		while y < s.y - 8.0:
			draw_line(Vector2(10, y), Vector2(s.x - 6, y), Color(RULE, 0.55), 1.0)
			y += RULE_STEP
		draw_line(Vector2(MARGIN_X, 0), Vector2(MARGIN_X, s.y), Color(RED_INK, 0.55), 1.5)
		for k in 3:
			var hy := s.y * (0.2 + 0.3 * k)
			draw_circle(Vector2(26, hy), 9.0, Color(0.16, 0.12, 0.25, 0.85))
			draw_arc(Vector2(26, hy), 9.0, PI * 0.1, PI * 0.9, 12, Color(1, 1, 1, 0.35), 1.2, true)
		# The fold by the tabs.
		for i in 6:
			draw_rect(Rect2(s.x - 6.0 + i, 0, 1.0, s.y), Color(0, 0, 0, 0.03 * i))
