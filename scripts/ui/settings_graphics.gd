extends VBoxContainer
## Settings > Display > Graphics: the quality everyone has (Automatic, High, Balanced, Battery saver) and,
## on a PC, the PC preset (settings_pc_detail.gd) with a Fine-tune section for each feature
## (pc_detail.gd FEATURES), the render resolution, and a Measure button that times the scene behind
## Settings. A resolution change is previewed: it reverts by itself after 10 seconds unless you keep it.
## Tags: [GRAPHICS]

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Graphics := preload("res://scripts/core/graphics.gd")
const Detail := preload("res://scripts/core/pc_detail.gd")
const KEEP_SECONDS := 10

var _open := false
var _keep_bar: Control
var _keep_label: Label
var _keep_left := 0.0
var _keep_old := 100.0
var _measure_label: Label


static func add_rows(parent: Control) -> void:
	var g: VBoxContainer = load("res://scripts/ui/settings_graphics.gd").new()
	g.name = "Graphics"
	parent.add_child(g)


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var s := GameState.settings
	var quals: Array = Graphics.QUALITIES
	var qual := UiKit.option(quals.map(func(m): return m[1]), maxi(0, quals.map(func(m): return m[0]).find(str(s.get("graphics", "auto")))))
	qual.name = "GraphicsQuality"
	qual.tooltip_text = "Saver: no shadows"
	qual.item_selected.connect(func(i):
		_save("graphics", str(quals[i][0]))
		_build.call_deferred())
	add_child(UiKit.field_row("Graphics", qual, 230))
	if not Detail.available():
		return
	preload("res://scripts/ui/settings_pc_detail.gd").add_row(self)
	var preset := find_child("PCDetail", true, false) as OptionButton
	if preset:
		preset.item_selected.connect(func(_i):
			var o: Dictionary = Detail.overrides().duplicate()
			for k in Detail.FEATURES:
				o.erase(k)   # a preset sets every feature (the resolution stays as chosen)
			_save("pc_graphics", o)
			_build.call_deferred())
	if str(s.get("graphics", "auto")) in ["balanced", "saver"]:
		add_child(UiKit.para("PC graphics need Graphics on High or Automatic.", 16, ThemeBuilder.MUTED))
	var toggle := UiKit.button(("▼ " if _open else "▶ ") + "Fine-tune: lighting, shadows, reflections..." + ("  (custom)" if Detail.custom() else ""), func():
		_open = not _open
		_build.call_deferred(), 0)
	toggle.name = "FineTune"
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(toggle)
	if _open:
		_fine_tune()
	var mrow := UiKit.flow_row(10)
	var measure := UiKit.button("Measure this scene", _measure, 230)
	measure.name = "Measure"
	measure.tooltip_text = "Times the world behind Settings for 4 seconds"
	measure.disabled = not _world_running()
	mrow.add_child(measure)
	_measure_label = UiKit.label("" if _world_running() else "Open a world to measure", 16, ThemeBuilder.MUTED)
	_measure_label.name = "MeasureResult"
	_measure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_measure_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(_measure_label)
	add_child(mrow)


func _fine_tune() -> void:
	var box := PanelContainer.new()
	box.name = "FineTuneBox"
	box.add_theme_stylebox_override("panel", ThemeBuilder.solid_panel(ThemeBuilder.RADIUS_M, 10))
	add_child(box)
	var v := UiKit.vbox(8)
	box.add_child(v)
	var tier := Graphics.pc_tier()
	var o: Dictionary = Detail.overrides()
	for feature in Detail.FEATURES:
		var spec: Array = Detail.FEATURES[feature]
		var names: Array = spec[1]
		var now_preset := str(names[Detail.preset_level(feature, maxi(tier, 1))])
		var items: Array = ["Same as preset (%s)" % now_preset] + names
		var chosen := int(o.get(feature, -1))
		var opt := UiKit.option(items, chosen + 1 if chosen >= 0 else 0)
		opt.name = "Fine_" + feature
		opt.item_selected.connect(func(i):
			var ov: Dictionary = Detail.overrides().duplicate()
			if i == 0:
				ov.erase(feature)
			else:
				ov[feature] = i - 1
			_save("pc_graphics", ov)
			_build.call_deferred())
		v.add_child(UiKit.field_row(str(spec[0]), opt, 200))
		v.add_child(UiKit.para(str(Detail.EXPLAIN[feature]), 16, ThemeBuilder.MUTED))
	var res := UiKit.stepper(50, 100, 5, Detail.render_scale() * 100.0, func(x): return "%d%%" % roundi(x))
	res.name = "RenderScale"
	res.value_changed.connect(_preview_scale)
	v.add_child(UiKit.field_row("Render resolution", res, 200))
	v.add_child(UiKit.para(str(Detail.EXPLAIN.render_scale), 16, ThemeBuilder.MUTED))
	_keep_bar = UiKit.flow_row(8)
	_keep_bar.name = "KeepBar"
	_keep_bar.visible = false
	_keep_label = UiKit.label("", 18, ThemeBuilder.YELLOW)
	_keep_bar.add_child(_keep_label)
	_keep_bar.add_child(UiKit.button("Keep", func():
		_keep_left = 0.0
		_keep_bar.visible = false, 110))
	_keep_bar.add_child(UiKit.button("Go back", _revert_scale, 130))
	v.add_child(_keep_bar)
	v.add_child(UiKit.para("All of these apply at once; none needs a restart. Worlds look the same to every device.", 16, ThemeBuilder.MUTED))


## A new resolution shows at once and goes back by itself unless you keep it.
func _preview_scale(x: float) -> void:
	if not _keep_bar.visible:
		_keep_old = Detail.render_scale() * 100.0
	var ov: Dictionary = Detail.overrides().duplicate()
	ov["render_scale"] = int(x)
	_save("pc_graphics", ov)
	_keep_left = KEEP_SECONDS
	_keep_bar.visible = true
	set_process(true)


func _revert_scale() -> void:
	var ov: Dictionary = Detail.overrides().duplicate()
	ov["render_scale"] = int(_keep_old)
	_save("pc_graphics", ov)
	_keep_left = 0.0
	_build.call_deferred()


func _process(delta: float) -> void:
	if _keep_bar == null or not is_instance_valid(_keep_bar) or not _keep_bar.visible:
		set_process(false)
		return
	_keep_left -= delta
	_keep_label.text = "Keep %d%%? Going back in %d s" % [roundi(Detail.render_scale() * 100.0), ceili(maxf(_keep_left, 0.0))]
	if _keep_left <= 0.0:
		_revert_scale()


func _exit_tree() -> void:
	if _keep_bar and is_instance_valid(_keep_bar) and _keep_bar.visible and _keep_left > 0.0:
		_revert_scale()   # closing Settings mid-preview: back to what worked


func _world_running() -> bool:
	var m: Node = get_tree().current_scene if is_inside_tree() else null
	return m != null and m.get("game") != null


## Frame time and memory of the world behind Settings, for 4 seconds.
func _measure() -> void:
	if not _world_running():
		return
	_measure_label.text = "Measuring..."
	var r: Dictionary = await measure(get_tree(), 4.0)
	if is_instance_valid(_measure_label):
		_measure_label.text = summary(r)


static func measure(tree: SceneTree, seconds: float) -> Dictionary:
	var vp := tree.root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var times: Array[float] = []
	var gpu := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	while (Time.get_ticks_usec() - start) / 1000000.0 < seconds:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	RenderingServer.viewport_set_measure_render_time(vp, false)
	times.remove_at(0)   # (the first frame includes the click)
	if times.is_empty():
		return {}
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in times:
		total += t
	var avg := total / times.size()
	return {"fps": 1000.0 / avg, "ms": avg, "p95": sorted[int(sorted.size() * 0.95)], "gpu_ms": gpu / maxf(times.size(), 1.0),
		"frames": times.size(), "ram_mb": OS.get_static_memory_usage() / 1048576.0,
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}


static func summary(r: Dictionary) -> String:
	if r.is_empty():
		return "Couldn't measure."
	return "%d fps · %.1f ms a frame (slowest 5%%: %.1f ms) · GPU %.1f ms · %d MB memory, %d MB video" % [
		roundi(r.fps), r.ms, r.p95, r.gpu_ms, roundi(r.ram_mb), roundi(r.vram_mb)]


func _save(key: String, value: Variant) -> void:
	GameState.settings[key] = value
	GameState.save_settings()
