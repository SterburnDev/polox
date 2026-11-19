extends RefCounted
## Tiny helpers for building UI in code. Every screen is made of these, which
## keeps layout code short and buttons consistently big (>= 48 px).
## Tags: [PAIRING] [PLATFORM]

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

const MIN_BUTTON := Vector2(48, 52)


## Canvas scaling on narrow phones must not shrink a 52-unit button below a 48-pixel touch target.
static func touch_target() -> float:
	if not preload("res://scripts/ui/touch_gestures.gd").phone_layout():
		return MIN_BUTTON.y
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.size.x <= 0:
		return MIN_BUTTON.y
	return maxf(MIN_BUTTON.y, 48.0 * tree.root.get_visible_rect().size.x / float(tree.root.size.x))


## The least anything you press, type in or drag may measure, each way: 44 px under a mouse pointer, 48
## screen pixels under a finger (a phone's canvas is scaled, so that is more than 48 canvas units there).
const MIN_POINTER := 44.0
static func least_target() -> float:
	return touch_target() if preload("res://scripts/ui/touch_gestures.gd").phone_layout() else MIN_POINTER


## Makes a control big enough to hit, whatever size its screen asked for: buttons, switches, text fields
## and sliders (main.gd calls this for every control as it joins the tree, so a screen can't forget).
## The engine's own compound widgets (the colour picker, the file dialog, a number box) lay out their
## inner parts themselves and are left alone; so is anything marked `small_on_purpose`.
static func give_room(c: Control) -> void:
	if not (c is BaseButton or c is LineEdit or c is TextEdit or c is Slider) or c.has_meta(&"small_on_purpose"):
		return
	var parent := c.get_parent()
	while parent != null and not parent is Window:
		if parent is ColorPicker or parent is FileDialog or parent is SpinBox or parent is PopupMenu:
			return
		parent = parent.get_parent()
	var least := least_target()
	var room := Vector2(maxf(c.custom_minimum_size.x, least), maxf(c.custom_minimum_size.y, least))
	if c is VSlider:
		room.y = c.custom_minimum_size.y
	if room != c.custom_minimum_size:
		c.custom_minimum_size = room


## Scrolls `scroll` to show `target` once this frame's layout is done. A deferred call that carries a
## control carries a dangling one if that control is freed first (a list rebuilt, a panel closed in the
## same frame), and the engine reports it; so both go by instance id and are looked up again when the
## call runs. Nothing happens if either is gone or no longer in the tree.
static func show_later(scroll: ScrollContainer, target: Control) -> void:
	if scroll == null or target == null or not is_instance_valid(scroll) or not is_instance_valid(target):
		return
	_show_now.call_deferred(scroll.get_instance_id(), target.get_instance_id())


static func _show_now(scroll_id: int, target_id: int) -> void:
	var scroll := instance_from_id(scroll_id) as ScrollContainer
	var target := instance_from_id(target_id) as Control
	if scroll and target and scroll.is_inside_tree() and target.is_inside_tree() and scroll.is_ancestor_of(target):
		scroll.ensure_control_visible(target)


## Gives `target` the keyboard focus after this frame, if it is still there to take it (by instance
## id, like show_later).
static func focus_later(target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	_focus_now.call_deferred(target.get_instance_id())


static func _focus_now(target_id: int) -> void:
	var target := instance_from_id(target_id) as Control
	if target and target.is_inside_tree() and target.focus_mode != Control.FOCUS_NONE:
		target.grab_focus()


## (Phones: every button gives a small buzz under the finger, haptics.gd; off in Settings.)
static func button(text: String, on_press: Callable = Callable(), min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	var target := touch_target()
	b.custom_minimum_size = Vector2(maxf(MIN_BUTTON.x if target == MIN_BUTTON.y else target, min_width), target)
	b.focus_mode = Control.FOCUS_ALL
	if on_press.is_valid():
		b.pressed.connect(func():
			if not first_press_this_frame(b):
				return
			on_press.call())
	b.pressed.connect(func():
		if int(b.get_meta(&"_tick_frame", -1)) == Engine.get_process_frames():
			return
		b.set_meta(&"_tick_frame", Engine.get_process_frames())
		preload("res://scripts/ui/haptics.gd").tap()
		if bool(GameState.settings.get("ui_sounds", true)) and b.is_inside_tree():
			preload("res://scripts/core/synth.gd").play(b.get_tree().root, "tick", 0.3))
	b.button_down.connect(func(): preload("res://scripts/ui/anim_fx.gd").press(b))
	b.button_up.connect(func(): preload("res://scripts/ui/anim_fx.gd").release(b))
	return b


## [PAIRING] [PLATFORM] One tap, one press. A button that acts when the finger lands
## (ACTION_MODE_BUTTON_PRESS: the PIN keypad, the platform Jump) hears a phone tap twice in Godot 4.7:
## BaseButton.gui_input takes the real InputEventScreenTouch *and* the mouse copy Godot makes of it
## (emulate_mouse_from_touch), in the same frame, and fires `pressed` for each, so every digit was typed
## twice on a phone (never with a mouse). The copy always lands in the same frame as the touch and two
## real taps never do, so the second press of a frame is dropped. Release-mode buttons (the default)
## aren't affected: the touch's release clears the press before the copy's release arrives.
static func first_press_this_frame(b: BaseButton) -> bool:
	return _first_press(b)


## [PLATFORM] A tap going down (or up) in a Control's own _gui_input: the left mouse button or a finger.
## On a touch screen Godot sends each finger as an InputEventScreenTouch and then, for the first finger,
## an emulated mouse copy of it (emulate_mouse_from_touch); code that accepted both acted twice per tap
## (a sheet's dimmed backdrop went back twice and closed the screen under it too; a wall in Map my home
## changed two states). The emulated copy is never a tap here: the touch already was.
static func tap_down(e: InputEvent) -> bool:
	return _tap(e, true)


static func tap_up(e: InputEvent) -> bool:
	return _tap(e, false)


static func _tap(e: InputEvent, down: bool) -> bool:
	if e is InputEventScreenTouch:
		return e.pressed == down
	if e is InputEventMouseButton:
		return e.button_index == MOUSE_BUTTON_LEFT and e.pressed == down and e.device != InputEvent.DEVICE_ID_EMULATION
	return false


static func _first_press(b: BaseButton) -> bool:
	if b.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		return true
	var frame := Engine.get_process_frames()
	if int(b.get_meta(&"_press_frame", -1)) == frame:
		return false
	b.set_meta(&"_press_frame", frame)
	return true


static func label(text: String, size: int = 0, color: Color = ThemeBuilder.CREAM) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A wrapping paragraph that takes the full available width.
## (Wrapping labels collapse to one letter per line inside HBoxes unless they expand.)
static func para(text: String, size: int = 0, color: Color = ThemeBuilder.CREAM) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 120
	return l


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(vertical: bool = false) -> Control:
	var c := Control.new()
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func line_edit(placeholder: String = "", text: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(120, touch_target())
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


static func text_edit(placeholder: String = "", text: String = "", height: float = 110.0) -> TextEdit:
	var e := TextEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	e.custom_minimum_size = Vector2(200, height)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


## "Label: [field]" row; returns the row (field is added as given).
static func field_row(caption: String, field: Control, caption_width: float = 190.0) -> HBoxContainer:
	var row := hbox()
	var l := label(caption)
	l.custom_minimum_size.x = caption_width
	# The captions make one column: a long one wraps inside it instead of pushing its field out of line
	# with the others (Settings > Music: "Light World creation").
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if upright_phone():
		# A phone held upright: the caption wraps so the field keeps its room.
		l.custom_minimum_size.x = minf(caption_width, 150.0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row


static func slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(150 if upright_phone() else 220, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


static func option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.custom_minimum_size = Vector2(160, touch_target())
	if upright_phone():
		# Long choices ("Google Gemini (free tier)...") shouldn't widen the row past the screen.
		o.fit_to_longest_item = false
		o.clip_text = true
		o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if selected >= 0 and selected < items.size():
		o.select(selected)
	# [GLASS_UI] A long list (Music's song pickers) scrolls by swipe or wheel, without a bar of its own.
	for s in o.get_popup().find_children("*", "ScrollContainer", true, false):
		(s as ScrollContainer).vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		(s as ScrollContainer).horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	return o


## A phone held upright (touch UI, taller than wide): rows give way.
## Screens are laid out when they open; turning the phone re-flows the next one.
static func upright_phone() -> bool:
	if not preload("res://scripts/ui/touch_gestures.gd").phone_layout():
		return false
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.root.size.y > tree.root.size.x


## Touch screens: a finger that wobbles a few pixels is still tapping, not scrolling (Godot's default of 0
## turns the smallest slide into a scroll, and the button under the finger never gets its press).
static func touch_deadzone() -> int:
	return 16 if preload("res://scripts/ui/touch_gestures.gd").phone_layout() or DisplayServer.is_touchscreen_available() else 0


## A row whose items wrap onto more lines when the screen is too narrow.
static func flow_row(sep: int = 8) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	return f


## Columns side by side, stacked instead when a phone is held upright.
static func columns(sep: int = 14) -> BoxContainer:
	var b := BoxContainer.new()
	b.vertical = upright_phone()
	b.add_theme_constant_override("separation", sep)
	return b


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.scroll_deadzone = touch_deadzone()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## A page that scrolls without a visible scroll bar (Settings): swipe on a phone; wheel, trackpad or
## keyboard (focus follows, plus Page Up/Down, Home and End) on a PC. A soft fade and a small chevron at
## the bottom edge say there's more below; they go once you reach the end.
static func page(child: Control) -> ScrollContainer:
	var s := scroll(child)
	hide_bar(s)
	return s


## Hides the draggable bar of a scroll container that already exists, keeping every way to scroll.
static func hide_bar(s: ScrollContainer) -> void:
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	# Keyboard focus moving down the page scrolls it along, but only once the page has been laid out:
	# a panel that focuses its first button as it opens (the world's Menu) did it while the page had no
	# height yet, and opened scrolled one row down (Resume and Bag out of sight).
	_follow_focus_soon(s)
	if s.get_node_or_null("MoreBelow") == null:
		var cue: Control = load("res://scripts/ui/more_below.gd").new()
		cue.name = "MoreBelow"
		s.add_child(cue, false, Node.INTERNAL_MODE_BACK)
		cue.watch(s)


## Let a Settings swipe start on a button. The native scroller cancels its press once a drag starts.
static func allow_swipe_over_buttons(page: ScrollContainer) -> void:
	var deadzone := touch_deadzone()
	if deadzone == 0:
		return
	page.scroll_deadzone = deadzone
	for button: BaseButton in page.find_children("*", "BaseButton", true, false):
		if button.mouse_filter == Control.MOUSE_FILTER_STOP:
			button.mouse_filter = Control.MOUSE_FILTER_PASS
		# OptionButton opens on finger down by default, before the drag can start.
		if button is OptionButton:
			button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE


static func _follow_focus_soon(s: ScrollContainer) -> void:
	if not s.is_inside_tree():
		await s.tree_entered
	for i in 2:   # (the first focus and the first layout happen in the frame it arrives)
		if not is_instance_valid(s) or not s.is_inside_tree():
			return
		await s.get_tree().process_frame
	if is_instance_valid(s):
		s.follow_focus = true


## A value with − / + buttons and a typed field, in place of a slider (stepper.gd).
static func stepper(min_v: float, max_v: float, step: float, value: float, fmt: Callable = Callable(), display_scale: float = 1.0) -> HBoxContainer:
	return preload("res://scripts/ui/stepper.gd").make(min_v, max_v, step, value, fmt, display_scale)


static func color_swatch(color: Color, size: float = 40.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(size, size)
	return r


## Opens the system file picker for a PNG/JPG/WebP and calls on_pick(path).
static func pick_picture(parent: Node, title: String, on_pick: Callable) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	fd.use_native_dialog = not OS.has_feature("web")  # browsers have no native picker
	fd.title = title
	fd.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	fd.file_selected.connect(func(path):
		on_pick.call(path)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	parent.add_child(fd)
	fd.popup_centered(Vector2i(900, 600))


## Full-rect anchor helper.
static func fill(c: Control, margin: float = 0.0) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = margin
	c.offset_top = margin
	c.offset_right = -margin
	c.offset_bottom = -margin
	return c
