extends Control
## In-world overlay: room name + AI status (top-left), Bag / Build / Menu
## (top-right), photo + camera buttons (bottom-right) and a context hint.
## On phones: a bottom tab bar (World, Bag, Build, Friends, Menu) clear of the
## gesture bar, everything in the thumb's reach; the camera turns and zooms with
## two fingers (or from the World tab). "Left hand" puts Menu on the left.

signal menu_pressed
signal camera_rotate(dir: int)
signal camera_zoom(dir: int)
signal build_pressed
signal bag_pressed
signal photo_pressed
signal sync_pressed
signal world_pressed
signal friends_pressed
signal outside_pressed

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const TouchGestures := preload("res://scripts/ui/touch_gestures.gd")
const VectorIcons := preload("res://scripts/ui/vector_icons.gd")

var room_label: Label
var status_dot: Panel
var status_label: Label
var hint_label: Label
var phone_label: Label          # "Phone Link ON · 1 device" (PC)
var sync_btn: Button            # phone build: sync state + "sync now"
var save_label: Label           # the autosave indicator ("✓ Saved")
var _save_shown := -10.0
var phone_mode := false         # thumb-zone layout
var outside_button: Button
var left_handed := false
var _top_right: HBoxContainer   # desktop: Bag, Build, Menu
var _bottom_right: HBoxContainer   # desktop: Photo + camera
var _thumb: VBoxContainer       # (unused since the tab bar)
var _other: VBoxContainer
var tab_bar: HBoxContainer      # phone: World, Bag, Build, Friends, Menu
var _buttons: Dictionary = {}   # name -> Button
var _spare: Control             # hidden: buttons the current layout doesn't use wait here (still in the tree)
var _glasses: Array = []        # the Liquid Glass capsules of the current layout

const LiquidGlass := preload("res://scripts/ui/liquid_glass.gd")


func _ready() -> void:
	UiKit.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UiKit.vbox(2)
	tl.position = Vector2(20, 14)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tl)
	room_label = UiKit.label("", 26, ThemeBuilder.CREAM)
	room_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	room_label.add_theme_constant_override("outline_size", 8)
	room_label.add_theme_color_override("font_outline_color", ThemeBuilder.BG)
	tl.add_child(room_label)
	var st := UiKit.hbox(6)
	tl.add_child(st)
	status_dot = Panel.new()
	status_dot.custom_minimum_size = Vector2(14, 14)
	status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.add_child(status_dot)
	status_label = UiKit.label("", 18, ThemeBuilder.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.add_theme_constant_override("outline_size", 6)
	status_label.add_theme_color_override("font_outline_color", ThemeBuilder.BG)
	st.add_child(status_label)
	phone_label = UiKit.label("", 18, ThemeBuilder.MINT)
	phone_label.add_theme_constant_override("outline_size", 6)
	phone_label.add_theme_color_override("font_outline_color", ThemeBuilder.BG)
	phone_label.visible = false
	tl.add_child(phone_label)
	save_label = UiKit.label("", 18, ThemeBuilder.MINT)
	save_label.add_theme_constant_override("outline_size", 6)
	save_label.add_theme_color_override("font_outline_color", ThemeBuilder.BG)
	save_label.modulate.a = 0.0
	tl.add_child(save_label)
	sync_btn = UiKit.button("☁ Sync", func(): sync_pressed.emit(), 0)
	sync_btn.tooltip_text = "Sync now"
	sync_btn.focus_mode = Control.FOCUS_NONE
	sync_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sync_btn.visible = false
	tl.add_child(sync_btn)

	_make_button("bag", "Bag", "Your items (B)", func(): bag_pressed.emit())
	_make_button("build", "Build", "Build mode", func(): build_pressed.emit())
	_make_button("menu", "☰ Menu", "Menu (C or Tab)", func(): menu_pressed.emit())
	_make_button("photo", "Photo", "Take a photo", func(): photo_pressed.emit())
	_make_button("world", "World", "Map and more", func(): world_pressed.emit())
	_make_button("friends", "Friends", "Your friends", func(): friends_pressed.emit())
	for spec in [["rot_l", "⟲", "Turn left", func(): camera_rotate.emit(-1)], ["rot_r", "⟳", "Turn right", func(): camera_rotate.emit(1)],
			["zoom_in", "+", "Zoom in", func(): camera_zoom.emit(-1)], ["zoom_out", "−", "Zoom out", func(): camera_zoom.emit(1)]]:
		var b := _make_button(spec[0], spec[1], spec[2], spec[3])
		b.add_theme_font_size_override("font_size", 26)
		b.focus_mode = Control.FOCUS_NONE

	hint_label = UiKit.para("", 20, Color(ThemeBuilder.CREAM, 0.85))
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.add_theme_constant_override("outline_size", 6)
	hint_label.add_theme_color_override("font_outline_color", ThemeBuilder.BG)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)
	AIClient.status_changed.connect(set_status)
	outside_button = UiKit.button("Go outside", func(): outside_pressed.emit(), 160)
	outside_button.name = "GoOutside"
	outside_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	outside_button.offset_left = -190
	outside_button.offset_right = -18
	outside_button.offset_top = 82
	outside_button.visible = false
	add_child(outside_button)
	set_status(AIClient.state, AIClient.status_message)
	apply_layout(TouchGestures.phone_layout(), str(GameState.settings.get("hand", "right")) == "left")


func _make_button(id: String, text: String, tip: String, on_press: Callable) -> Button:
	var b := UiKit.button(text, on_press, 0)
	b.tooltip_text = tip
	_buttons[id] = b
	return b


## Puts the buttons where they belong for a mouse (desktop) or a thumb (phone).
func apply_layout(phone: bool, left_hand: bool) -> void:
	phone_mode = phone
	left_handed = left_hand
	for b in _buttons.values():
		if b.get_parent():
			b.get_parent().remove_child(b)
	for c in [_top_right, _bottom_right, _thumb, _other, tab_bar]:
		if c:
			c.queue_free()
	for g in _glasses:
		if is_instance_valid(g):
			remove_child(g)
			g.queue_free()
	_glasses.clear()
	_top_right = null
	_bottom_right = null
	_thumb = null
	_other = null
	tab_bar = null
	var old_back := get_node_or_null("TabBack")
	if old_back:
		remove_child(old_back)
		old_back.queue_free()
	if phone:
		# [GLASS_UI] The tab bar floats: a Liquid Glass capsule a little above the bottom edge (clear of
		# the gesture bar), the world showing through it.
		var bar_h := maxf(76.0, UiKit.touch_target())
		var pad := preload("res://scripts/ui/screen_panel.gd").safe_bottom(get_viewport_rect().size.y) if is_inside_tree() else 0.0
		tab_bar = UiKit.hbox(4)
		var back: PanelContainer = LiquidGlass.wrap(tab_bar, 30.0, Vector4(6, 5, 6, 5))
		back.name = "TabBack"
		back.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		back.offset_left = 10
		back.offset_right = -10
		back.offset_bottom = -(pad + 8.0)
		back.offset_top = -(bar_h + pad + 8.0 + 10.0)
		back.mouse_filter = Control.MOUSE_FILTER_STOP
		_glasses.append(back)
		tab_bar.name = "TabBar"
		var order := ["world", "bag", "build", "friends", "menu"]
		if left_hand:
			order.reverse()
		var labels := {"world": "World", "bag": "Bag", "build": "Build", "friends": "Friends", "menu": "Menu"}
		var icons := {"world": "world", "bag": "bag", "build": "build", "friends": "heart", "menu": "menu"}
		# Drawn icons at the screen's own pixel size (phones have no emoji font; the stand-in
		# 12-pixel symbols were tiny and blocky).
		var icon_ui := 30.0
		var dev := float(DisplayServer.window_get_size().x) / maxf(1.0, get_viewport_rect().size.x) if is_inside_tree() else 1.0
		var icon_px := clampi(roundi(icon_ui * maxf(1.0, dev)), 24, 160)
		for id in order:
			var b: Button = _buttons[id]
			b.text = str(labels[id])
			b.icon = VectorIcons.texture(str(icons[id]), icon_px)
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", int(icon_ui))
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			b.custom_minimum_size = Vector2(0, bar_h)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 16)
			b.focus_mode = Control.FOCUS_NONE
			LiquidGlass.flat_button(b, 24)
			tab_bar.add_child(b)
		add_child(back)
		hint_label.offset_left = 22
		hint_label.offset_right = -22
		hint_label.offset_top = -(bar_h + pad + 80.0)
		hint_label.offset_bottom = -(bar_h + pad + 30.0)
	else:
		# [GLASS_UI] Navigation (Bag, Build, Menu) and the quick actions (Photo, turn, zoom) float on two
		# Liquid Glass capsules; the buttons are flat on the glass.
		_top_right = UiKit.hbox(2)
		var nav: PanelContainer = LiquidGlass.wrap(_top_right, 30.0, Vector4(5, 5, 5, 5))
		nav.name = "NavGlass"
		nav.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		nav.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		nav.offset_right = -16
		nav.offset_top = 12
		add_child(nav)
		_glasses.append(nav)
		for spec in [["bag", 104, "Bag"], ["build", 112, "Build"], ["menu", 140, "☰ Menu"]]:
			var b: Button = _buttons[spec[0]]
			b.text = str(spec[2])
			b.icon = null   # (the phone layout's drawn icon, if the layout just changed)
			b.expand_icon = false
			b.custom_minimum_size = Vector2(spec[1], UiKit.MIN_BUTTON.y)
			b.size_flags_horizontal = Control.SIZE_FILL
			b.remove_theme_font_size_override("font_size")
			LiquidGlass.flat_button(b, 24)
			_top_right.add_child(b)
		_bottom_right = UiKit.hbox(2)
		var quick: PanelContainer = LiquidGlass.wrap(_bottom_right, 30.0, Vector4(5, 5, 5, 5))
		quick.name = "QuickGlass"
		quick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		quick.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		quick.grow_vertical = Control.GROW_DIRECTION_BEGIN
		quick.offset_right = -16
		quick.offset_bottom = -14
		add_child(quick)
		_glasses.append(quick)
		_buttons.photo.custom_minimum_size = Vector2(104, UiKit.MIN_BUTTON.y)
		_buttons.photo.focus_mode = Control.FOCUS_NONE
		LiquidGlass.flat_button(_buttons.photo, 24)
		_bottom_right.add_child(_buttons.photo)
		for id in ["rot_l", "rot_r", "zoom_in", "zoom_out"]:
			_buttons[id].custom_minimum_size = Vector2(54, UiKit.MIN_BUTTON.y)
			LiquidGlass.flat_button(_buttons[id], 24)
			_bottom_right.add_child(_buttons[id])
		hint_label.offset_left = 22
		hint_label.offset_top = -60
		hint_label.offset_right = -400  # leaves room for the camera buttons
		hint_label.offset_bottom = -20
	if _spare == null:
		_spare = Control.new()
		_spare.name = "SpareButtons"
		_spare.visible = false
		_spare.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_spare)
	for b in _buttons.values():
		if b.get_parent() == null:
			_spare.add_child(b)


## A bottom-corner column (right = true for the bottom-right corner).
func _corner(right: bool) -> VBoxContainer:
	var v := UiKit.vbox(10)
	v.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if right else Control.PRESET_BOTTOM_LEFT)
	v.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if right:
		v.offset_right = -18
		v.offset_left = -168
	else:
		v.offset_left = 18
		v.offset_right = 168
	v.offset_bottom = -18
	v.offset_top = -18
	v.alignment = BoxContainer.ALIGNMENT_END
	add_child(v)
	return v


func button(id: String) -> Button:
	return _buttons.get(id)


func set_room(room_name: String) -> void:
	room_label.text = room_name


## Shown whenever the PC's Phone Link server is on, so it's never on by surprise.
func set_phone_link(on: bool, devices: int) -> void:
	phone_label.visible = on
	phone_label.text = "📱 Phone Link ON · %d device%s" % [devices, "" if devices == 1 else "s"]


## Phone build: "☁ Synced 10:42", "PC offline", "⚠ 1 conflict"... (tap = sync now).
func set_sync(state: String, detail: String) -> void:
	sync_btn.visible = true
	var icons := {"ok": "☁", "syncing": "⟳", "offline": "⚠", "unpaired": "⚠", "conflict": "⚠", "error": "⚠"}
	sync_btn.text = "%s %s" % [icons.get(state, "☁"), detail if detail != "" else "Sync"]


## The autosave indicator: everything is saved the moment it changes, and
## this says so quietly (at most every few seconds, then it fades).
func note_saved() -> void:
	_flash("✓ Saved")


func note_snapshot(kind: String) -> void:
	_flash({"auto": "📦 Snapshot", "quick": "📦 Saved", "manual": "📦 Snapshot"}.get(kind, "📦 Saved"), true)


func _flash(text: String, force: bool = false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now - _save_shown < 3.0:
		return
	_save_shown = now
	save_label.text = text
	var tw := create_tween()
	tw.tween_property(save_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.4)
	tw.tween_property(save_label, "modulate:a", 0.0, 0.6)


## The editor has its own bars: the HUD steps aside entirely, and so do the world's cards (Today, the
## recap), which had stayed on screen over the builder's tools.
func set_building(on: bool) -> void:
	visible = not on
	if is_inside_tree():
		get_tree().call_group(&"polox_hud_card", "set_visible", not on)


func set_hint(text: String) -> void:
	hint_label.text = text


func set_status(state: String, message: String) -> void:
	var colors := {"mock": ThemeBuilder.MUTED, "ready": ThemeBuilder.MINT, "thinking": ThemeBuilder.YELLOW, "waiting": ThemeBuilder.YELLOW, "error": ThemeBuilder.DANGER, "offline": ThemeBuilder.DANGER}
	status_dot.add_theme_stylebox_override("panel", ThemeBuilder.box(colors.get(state, ThemeBuilder.MUTED), ThemeBuilder.BG, 2, 7, 0))
	status_label.text = message
