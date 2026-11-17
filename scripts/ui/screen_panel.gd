extends Control
## Base for every menu screen: dims the world, centers a big panel with a
## title and a Close button. Main keeps a stack of these so right-click,
## Q, X or Esc always closes the top one ("back"). On a phone held upright it's
## a bottom sheet instead: full width, rising from the bottom edge (where the
## thumb is), clear of the gesture bar, closed by swiping it down (or Close, or a
## tap above it). `compact` sheets (a question, a few choices) are as tall as
## their contents.

signal closed

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

var body: VBoxContainer
var header: HBoxContainer
var title_label: Label
var panel: PanelContainer
var max_size := Vector2(1100, 660)
var _hscroll: ScrollContainer   # narrow screens: a too-wide body slides sideways, the header stays put
var compact := false            # a short sheet: as tall as its contents (set before setup)
var sheet := false              # a bottom sheet (a phone held upright)
var _holder: Control            # the sheet's frame (slides down as you swipe)
var _pad: Control               # room for the phone's gesture bar
var _drag := 0.0
var _drag_on := false
const SWIPE_CLOSE := 90.0       # px down that closes a sheet


func setup(title: String, max_panel_size: Vector2 = Vector2(1100, 660)) -> void:
	max_size = max_panel_size
	UiKit.fill(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.06, 0.6)
	UiKit.fill(dim)
	add_child(dim)
	sheet = UiKit.upright_phone()
	if sheet:
		# [GLASS_UI] A temporary sheet is Liquid Glass (liquid_glass.gd): the world shows through, blurred,
		# under a tint dense enough for text; solid with Reduce transparency or Battery saver.
		var g: PanelContainer = preload("res://scripts/ui/liquid_glass.gd").new()
		g.radius = 22.0
		g.round_bottom = false
		g.tint = Color(ThemeBuilder.PANEL, 0.76)
		g.pad = Vector4(18, 14, 18, 14)
		panel = g
	else:
		panel = PanelContainer.new()
	if sheet:
		dim.gui_input.connect(func(e):
			if UiKit.tap_down(e):
				on_back())
		var holder := VBoxContainer.new()
		UiKit.fill(holder)
		holder.add_theme_constant_override("separation", 0)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var above := Control.new()
		above.size_flags_vertical = Control.SIZE_EXPAND_FILL
		above.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(above)
		panel.size_flags_horizontal = Control.SIZE_FILL
		holder.add_child(panel)
		add_child(holder)
		_holder = holder
	else:
		var center := CenterContainer.new()
		UiKit.fill(center)
		add_child(center)
		center.add_child(panel)
	var v := UiKit.vbox(6 if sheet else 12)
	panel.add_child(v)
	if sheet:
		# The handle: a short bar to grab and swipe down.
		var grab := Control.new()
		grab.name = "SheetHandle"
		grab.custom_minimum_size = Vector2(0, 14)
		grab.mouse_filter = Control.MOUSE_FILTER_STOP
		var bar := Panel.new()
		var bsb := ThemeBuilder.box(Color(ThemeBuilder.CREAM, 0.45), Color(0, 0, 0, 0), 0, 3, 0)
		bar.add_theme_stylebox_override("panel", bsb)
		bar.custom_minimum_size = Vector2(56, 6)
		bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
		bar.position = Vector2(-28, 4)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grab.add_child(bar)
		grab.gui_input.connect(_sheet_drag)
		v.add_child(grab)
	header = UiKit.hbox()
	title_label = UiKit.label(title, 32, ThemeBuilder.YELLOW)
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if UiKit.upright_phone():
		# A long title gives way ("Edit Mochi...") so the header buttons stay on screen.
		title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_label.clip_text = true
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	if title_label.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
		header.add_child(UiKit.spacer())   # (a phone's title already takes the spare room)
	var close_btn := UiKit.button("Close", on_back, 90 if sheet else 120)
	close_btn.tooltip_text = "Close (right-click, Q or X also work)"
	header.add_child(close_btn)
	v.add_child(header)
	_hscroll = ScrollContainer.new()
	_hscroll.scroll_deadzone = UiKit.touch_deadzone()
	_hscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_hscroll)
	if sheet:
		header.gui_input.connect(_sheet_drag)
		_pad = Control.new()
		_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_pad)
	body = UiKit.vbox(6 if sheet else 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hscroll.add_child(body)
	if is_inside_tree():
		_watch_viewport()
	else:
		tree_entered.connect(_watch_viewport, CONNECT_ONE_SHOT)
	_fit.call_deferred()   # again once the screen has built its contents


func _watch_viewport() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()
	_auto_focus.call_deferred()
	_arrive.call_deferred()


## The screen arrives: a sheet slides up, a panel grows in a touch, the list comes in one by one
## (Reduce motion: a short fade). Interrupted by anything that moves it again.
func _arrive() -> void:
	if not is_inside_tree() or panel == null:
		return
	preload("res://scripts/ui/anim_fx.gd").panel_in(panel, sheet)
	preload("res://scripts/ui/anim_fx.gd").stagger(body)


## If nothing in the panel has focus yet, focus its first button (or Close),
## so gamepad and keyboard users can start navigating immediately.
func _auto_focus() -> void:
	if not is_inside_tree():
		return
	var owner_now := get_viewport().gui_get_focus_owner()
	if owner_now and is_ancestor_of(owner_now):
		return
	for b in body.find_children("*", "BaseButton", true, false):
		if b.is_visible_in_tree() and b.focus_mode != Control.FOCUS_NONE and not b.disabled:
			b.grab_focus()
			return
	for b in header.find_children("*", "BaseButton", true, false):
		if b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
			return


## A swipe down on the sheet's handle or header: it follows the finger, and closes past SWIPE_CLOSE.
func _sheet_drag(e: InputEvent) -> void:
	if not sheet or _holder == null:
		return
	if (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT) or e is InputEventScreenTouch:
		if e.pressed:
			_drag_on = true
			_drag = 0.0
		elif _drag_on:
			_drag_on = false
			if _drag > SWIPE_CLOSE:
				on_back()
			else:
				_holder.position.y = 0.0
	elif _drag_on and (e is InputEventMouseMotion or e is InputEventScreenDrag):
		_drag = maxf(0.0, _drag + float(e.relative.y))
		_holder.position.y = _drag


## Room for Android's gesture bar / a notch: the safe area's bottom edge, in this screen's units.
static func safe_bottom(view_h: float) -> float:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.y <= 0 or safe.size.y <= 0 or safe.end.y >= win.y:
		return 0.0
	return (win.y - safe.end.y) * view_h / float(win.y)


## Keeps the panel inside the window at any UI scale or window size.
func _fit() -> void:
	if not is_inside_tree() or panel == null:
		return
	var view := get_viewport_rect().size
	if sheet:
		_hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # (swipe; no bar)
		_hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var top_gap := 40.0
		var full := view.y - top_gap
		var hh := 0.0 if compact else (full if max_size.y >= 560.0 else minf(max_size.y, full))
		panel.custom_minimum_size = Vector2(view.x, hh)
		if _pad:
			_pad.custom_minimum_size.y = safe_bottom(view.y)
		_wrap_wide_text(view.x - 60.0)
		return
	var h := minf(max_size.y, view.y - 32)
	if view.y > view.x and max_size.y >= 560.0:
		h = view.y - 32  # a tall phone screen: big screens use the whole height
	# Phones in portrait: never wider than the screen; anything that can't
	# wrap scrolls sideways instead of pushing Close off the edge. Swipe, wheel or keys: no bars anywhere.
	_hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if view.x < 900.0 else ScrollContainer.SCROLL_MODE_DISABLED
	# A phone on its side (~600 px tall): too-tall screens scroll down instead of losing their bottom.
	_hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if view.y < 640.0 else ScrollContainer.SCROLL_MODE_DISABLED
	panel.custom_minimum_size = Vector2(minf(max_size.x, view.x - 32), h)
	if view.x < 900.0:
		_wrap_wide_text(view.x - 140.0)   # (the panel, tab and scroll margins eat ~140 px)


## Narrow screens: a single label or check box wider than the panel wraps
## its words instead (most screens were laid out for a landscape window).
func _wrap_wide_text(room: float) -> void:
	for c in body.find_children("*", "Control", true, false):
		var too_wide := (c as Control).get_minimum_size().x > room
		if c is Label and too_wide and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF:
			(c as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		elif (c is CheckBox or c is CheckButton) and too_wide:
			(c as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			continue
		# Wrapped text has no width of its own any more: give it the row.
		var ctl := c as Control
		ctl.custom_minimum_size.x = minf(room, 240.0) if ctl.custom_minimum_size.x <= 0.0 else minf(ctl.custom_minimum_size.x, room)
		ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Called by Main when "back" is pressed. Override to confirm unsaved work.
## Returns true if the screen closed.
func on_back() -> bool:
	close()
	return true


func close() -> void:
	closed.emit()
	queue_free()
