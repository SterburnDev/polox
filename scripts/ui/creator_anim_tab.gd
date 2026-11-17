extends ScrollContainer
## Character Creator > Animations: how this character moves (Platform Mode,
## and walking around). Pick a state (idle, walk, run, jump, fall, land),
## then draw its frames in the paint tool (the previous frame shows faintly
## underneath; "Copy previous" starts from it), import a sprite strip (cut
## into square frames), or "Generate from base sprite". Set the speed, loop,
## watch the preview (both directions), Save. Without frames a state still
## looks different: running leans and kicks up dust, jumps stretch, landings
## squash (generated motion).

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const AnimStore := preload("res://scripts/characters/anim_store.gd")
const AnimBake := preload("res://scripts/characters/anim_bake.gd")
const PixelPaintPanel := preload("res://scripts/ui/pixel_paint_panel.gd")

const STATES := [["idle", "Idle"], ["walk", "Walk"], ["run", "Run"], ["jump", "Jump"], ["fall", "Fall"], ["land", "Land"],
	["transform_in", "Transform in"], ["transform_out", "Transform out"],   # (into and out of the Dream World)
	["battle_idle", "Battle idle"], ["battle_hurt", "Battle hurt"]]          # (as an enemy in a friendly battle)

var target: Dictionary = {}          # {kind: character, id} | {kind: player, form}
var base: Callable = Callable()      # () -> Image: the character's main picture
var state := "run"
var frames: Array = []               # Images of the selected state (unsaved edits here)
var selected := -1
var dirty := false
var _v: VBoxContainer
var _strip: HFlowContainer
var _status: Label
var _fps: HSlider
var _fps_label: Label
var _loop: CheckBox
var _mirror: CheckBox
var _preview: TextureRect
var _state_btns: Dictionary = {}
var _textures: Array = []
var _t := 0.0


func build(t: Dictionary, base_picture: Callable) -> void:
	target = t
	base = base_picture
	name = "Animations"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_v = UiKit.vbox(8)
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_v)
	if str(target.get("kind", "")) == "character" and str(target.get("id", "")) == "":
		_v.add_child(UiKit.para("Save your new friend first, then come back here to give them run, jump and walk frames.", 18, ThemeBuilder.MUTED))
		return
	_v.add_child(UiKit.para("How this character moves in Platform Mode (and when walking). Leave a state empty and it still moves differently (generated motion).", 16, ThemeBuilder.MUTED))
	var row := UiKit.flow_row(4)
	for s in STATES:
		var b := UiKit.button(s[1], func(): select_state(str(s[0])), 0)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(64, 40)
		_state_btns[s[0]] = b
		row.add_child(b)
	_v.add_child(row)
	_status = UiKit.para("", 16, ThemeBuilder.CREAM)
	_v.add_child(_status)
	_strip = HFlowContainer.new()
	_strip.add_theme_constant_override("h_separation", 4)
	_strip.add_theme_constant_override("v_separation", 4)
	_v.add_child(_strip)
	var tools := UiKit.flow_row(6)
	tools.add_child(_tool("+ Draw a frame", draw_frame, "Opens the paint tool; the previous frame shows faintly underneath"))
	tools.add_child(_tool("Copy previous", copy_previous, "Adds a copy of the selected frame to change a little"))
	tools.add_child(_tool("Edit", edit_frame, "Paint over the selected frame"))
	tools.add_child(_tool("◀", func(): move_frame(-1), "Move earlier"))
	tools.add_child(_tool("▶", func(): move_frame(1), "Move later"))
	tools.add_child(_tool("Delete", delete_frame, "Remove the selected frame"))
	_v.add_child(tools)
	var more := UiKit.flow_row(6)
	more.add_child(_tool("Import sprite strip...", _import_strip, "A row of square frames in one picture (PNG): cut automatically"))
	more.add_child(_tool("Generate from base sprite", generate, "Makes frames from the main picture: lean and stride for run, stretch for jump..."))
	_v.add_child(more)
	_fps = UiKit.slider(1.0, 24.0, 1.0, 8.0)
	_fps_label = UiKit.label("", 16, ThemeBuilder.MUTED)
	_fps.value_changed.connect(func(v):
		_fps_label.text = "%d frames per second" % int(v)
		dirty = true)
	_v.add_child(UiKit.field_row("Speed", _fps, 80))
	_v.add_child(_fps_label)
	_loop = CheckBox.new()
	_loop.text = "Loop"
	_loop.toggled.connect(func(_on): dirty = true)
	_v.add_child(_loop)
	var prow := UiKit.hbox(10)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(96, 96)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prow.add_child(_preview)
	_mirror = CheckBox.new()
	_mirror.text = "Facing left"
	_mirror.tooltip_text = "Frames are mirrored automatically when the character turns"
	prow.add_child(_mirror)
	_v.add_child(prow)
	var save_row := UiKit.flow_row(8)
	save_row.add_child(UiKit.button("Save animation", save_state, 180))
	save_row.add_child(_tool("Remove frames", func():
		frames.clear()
		selected = -1
		dirty = true
		_refresh(), "Back to generated motion for this state"))
	_v.add_child(save_row)
	select_state(state)


func _tool(text: String, cb: Callable, tip: String) -> Button:
	var b := UiKit.button(text, cb, 0)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	return b


func select_state(s: String) -> void:
	if dirty and frames.size() > 0 and s != state:
		save_state()   # never lose drawn frames by switching state
	state = s
	frames = AnimStore.images(target, s)
	var st := AnimStore.settings_of(target, s)
	if _fps:
		_fps.set_value_no_signal(float(st.get("fps", AnimBake.FPS.get(s, 8.0))))
		_fps_label.text = "%d frames per second" % int(_fps.value)
		_loop.set_pressed_no_signal(bool(st.get("loop", s in ["idle", "walk", "run", "fall"])))
	selected = frames.size() - 1
	dirty = false
	_refresh()


func _refresh() -> void:
	if _strip == null:
		return
	for k in _state_btns:
		_state_btns[k].set_pressed_no_signal(k == state)
		var n := (AnimStore.settings_of(target, k).get("frames", []) as Array).size()
		_state_btns[k].text = "%s%s" % [_label_of(k), (" (%d)" % n) if n > 0 else ""]
	for c in _strip.get_children():
		c.free()
	_textures.clear()
	for i in frames.size():
		var tex := ImageTexture.create_from_image(frames[i])
		_textures.append(tex)
		var b := Button.new()
		b.icon = tex
		b.expand_icon = true
		b.custom_minimum_size = Vector2(56, 56)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_pressed_no_signal(i == selected)
		b.tooltip_text = "Frame %d" % (i + 1)
		b.pressed.connect(func():
			selected = i
			_refresh())
		_strip.add_child(b)
	if frames.is_empty():
		_status.text = "No frames for %s: it uses generated motion. Draw, import or generate some." % _label_of(state)
	else:
		_status.text = "%s: %d frame%s%s" % [_label_of(state), frames.size(), "" if frames.size() == 1 else "s", " (not saved yet)" if dirty else ""]


func _label_of(s: String) -> String:
	for x in STATES:
		if x[0] == s:
			return str(x[1])
	return s


func _process(delta: float) -> void:
	if _preview == null:
		return
	_t += delta
	var tex: Texture2D
	if _textures.is_empty():
		var b: Variant = base.call() if base.is_valid() else null
		if b is Image:
			if _preview.texture == null or _preview.get_meta("base", false) == false:
				_preview.texture = ImageTexture.create_from_image(b)
				_preview.set_meta("base", true)
		_preview.flip_h = _mirror.button_pressed
		return
	_preview.set_meta("base", false)
	var i := int(_t * _fps.value) % _textures.size()
	if not _loop.button_pressed:
		i = mini(int(_t * _fps.value), _textures.size() - 1)
		if int(_t * _fps.value) > _textures.size() + 4:
			_t = 0.0
	tex = _textures[i]
	_preview.texture = tex
	_preview.flip_h = _mirror.button_pressed


func _base_image() -> Image:
	var b: Variant = base.call() if base.is_valid() else null
	return (b as Image).duplicate() if b is Image else Image.create(32, 32, false, Image.FORMAT_RGBA8)


## Opens the paint tool on a copy of the selected frame (or the base picture),
## with the frame before it showing faintly underneath.
func draw_frame() -> void:
	var start: Image = (frames[selected] as Image).duplicate() if selected >= 0 and selected < frames.size() else _base_image()
	_paint(start, start, frames.size(), true)


func edit_frame() -> void:
	if selected < 0 or selected >= frames.size():
		return
	var onion: Image = frames[selected - 1] if selected > 0 else null
	_paint((frames[selected] as Image).duplicate(), onion, selected, false)


func _paint(start: Image, onion: Image, at: int, insert: bool) -> void:
	if frames.size() >= AnimStore.MAX_FRAMES and insert:
		GameState.notify("8 frames is the most a state can have.")
		return
	var p := PixelPaintPanel.new()
	p.title_text = "%s, frame %d" % [_label_of(state), at + 1]
	p.start = start
	p.onion_image = onion
	p.done.connect(func(img: Image):
		if insert:
			add_frame(img)
		else:
			frames[at] = img
			dirty = true
			_refresh())
	var main := get_tree().current_scene
	if main and main.has_method("open_panel"):
		main.open_panel(p)


func add_frame(img: Image) -> void:
	if frames.size() >= AnimStore.MAX_FRAMES:
		return
	var at := selected + 1 if selected >= 0 else frames.size()
	frames.insert(at, img)
	selected = at
	dirty = true
	_refresh()


func copy_previous() -> void:
	if selected < 0 or selected >= frames.size():
		if frames.is_empty():
			add_frame(_base_image())
		return
	add_frame((frames[selected] as Image).duplicate())


func move_frame(d: int) -> void:
	if selected < 0 or selected >= frames.size():
		return
	var j := clampi(selected + d, 0, frames.size() - 1)
	if j == selected:
		return
	var f: Image = frames.pop_at(selected)
	frames.insert(j, f)
	selected = j
	dirty = true
	_refresh()


func delete_frame() -> void:
	if selected < 0 or selected >= frames.size():
		return
	frames.remove_at(selected)
	selected = mini(selected, frames.size() - 1)
	dirty = true
	_refresh()


func generate() -> void:
	frames = AnimBake.frames_for(state, _base_image())
	selected = frames.size() - 1
	_fps.set_value_no_signal(float(AnimBake.FPS.get(state, 8.0)))
	_fps_label.text = "%d frames per second" % int(_fps.value)
	_loop.set_pressed_no_signal(state in ["idle", "walk", "run"])
	dirty = true
	_refresh()


func import_strip_image(img: Image) -> void:
	var cut := AnimStore.slice_strip(img)
	if cut.is_empty():
		GameState.notify("That picture had no frames in it.")
		return
	frames = cut
	selected = frames.size() - 1
	dirty = true
	_refresh()
	GameState.notify("Cut into %d frame%s." % [cut.size(), "" if cut.size() == 1 else "s"])


func _import_strip() -> void:
	UiKit.pick_picture(self, "Pick a sprite strip (frames side by side)", func(path):
		var img := SaveManager.load_picture(path)
		if img:
			import_strip_image(img))


func save_state() -> void:
	AnimStore.save_state(target, state, frames, _fps.value if _fps else 8.0, _loop.button_pressed if _loop else true)
	dirty = false
	_refresh()
	GameState.character_changed.emit("player" if str(target.get("kind", "")) == "player" else str(target.get("id", "")))
	GameState.notify("%s animation saved." % _label_of(state))
