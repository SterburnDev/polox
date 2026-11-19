extends ScrollContainer
## One page of Settings, by `section`:
##   gameplay       text speed, suggested replies, the "Where was I?" card, battles, this world, your files
##   display        UI size, cameras, the touch layout, frame rate and graphics (settings_graphics.gd)
##   audio          music and sound volume, voice blips, button clicks
##   controls       which hand, the scroll wheel, platform physics, vibration
##   accessibility  reduce motion, reduce transparency, battle assists
## Numbers use steppers (stepper.gd), not sliders; the page scrolls without a visible bar (ui_kit.gd page).
## Every change saves at once.
## Tags: [PERSONAL_DATA]

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Graphics := preload("res://scripts/core/graphics.gd")
const MissYou := preload("res://scripts/variety/miss_you.gd")

const SECTIONS := ["gameplay", "display", "audio", "controls", "accessibility"]
const TITLES := {"gameplay": "Gameplay", "display": "Display", "audio": "Audio", "controls": "Controls", "accessibility": "Accessibility"}
const CAMERA_IDS: PackedStringArray = ["low", "cozy", "high", "top"]
const CAMERA_NAMES := ["Low and close", "Cozy", "High", "Top-down"]
const CAPTION := 230

var section := "gameplay"
var _ui_timer: Timer


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_deadzone = UiKit.touch_deadzone()
	var v := UiKit.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(v)
	UiKit.hide_bar(self)
	match section:
		"display":
			_display(v)
		"audio":
			_audio(v)
		"controls":
			_controls(v)
		"accessibility":
			_accessibility(v)
		_:
			_gameplay(v)


func _gameplay(v: VBoxContainer) -> void:
	var s := GameState.settings
	var speed := _stepper_row(v, "Text speed", 10, 120, 5, float(s.get("text_speed", 45)), func(x): return "Instant" if x >= 120 else "%d letters/s" % x)
	speed.value_changed.connect(func(x): _apply("text_speed", int(x)))
	_check(v, "Suggested replies", "quick_replies", true)
	_check(v, "\"Where was I?\" card", "recap", true)
	_heading(v, "Battles")
	var enc_ids := ["off", "rare", "sometimes"]
	var enc := UiKit.option(["Off", "Rarely", "Sometimes"], maxi(0, enc_ids.find(str(s.get("encounters", "rare")))))
	enc.tooltip_text = "Not now is always fine"
	enc.item_selected.connect(func(i): _apply("encounters", enc_ids[i]))
	v.add_child(UiKit.field_row("Battle invites", enc, CAPTION))
	_check(v, "Outside the Deep too", "encounters_light_world", false)
	_check(v, "I choose for my friends", "battle_choose_for_friends", false)
	if MissYou.supported():
		var notes_row := UiKit.flow_row(10)
		var nb := CheckBox.new()
		nb.text = "Missing-you notes"
		nb.name = "MissYouNotes"
		nb.button_pressed = MissYou.enabled()
		nb.toggled.connect(func(on):
			var n: Dictionary = s.get("notifications", {}) if s.get("notifications") is Dictionary else {}
			n["miss_you"] = on
			n["asked"] = true
			_apply("notifications", n.duplicate())
			if on:
				MissYou.ask_permission())
		notes_row.add_child(nb)
		notes_row.add_child(UiKit.button("Test", func(): GameState.notify(MissYou.test_note()), 190))
		v.add_child(notes_row)
	if not GameState.world.is_empty():
		_heading(v, "This world")
		for opt in [["real_time_lighting", "Real-time light"], ["seasons", "Seasons and weather"], ["daily_events", "Little daily events"], ["seasonal_decor", "Seasonal decorations"]]:
			var cb := CheckBox.new()
			cb.text = opt[1]
			cb.button_pressed = bool(GameState.world.get("settings", {}).get(opt[0], true))
			cb.toggled.connect(func(on):
				GameState.world["settings"][opt[0]] = on
				GameState.save_world())
			v.add_child(cb)
	_heading(v, "Your files")
	var files := UiKit.flow_row(10)
	var open := UiKit.button("Open Personal Data Folder", func(): SaveManager.open_personal_data(), 230)   # [PERSONAL_DATA]
	open.name = "OpenPersonalData"
	files.add_child(open)
	files.add_child(UiKit.button("Back up now", func():
		var zip := SaveManager.backup()
		GameState.notify("Backed up: backups/%s" % zip.get_file() if zip != "" else "Couldn't back up."), 200))
	v.add_child(files)
	v.add_child(UiKit.para(SaveManager.root, 16, ThemeBuilder.MUTED))
	if SaveManager.PersonalData.fallback_reason != "":
		v.add_child(UiKit.para(SaveManager.PersonalData.fallback_reason, 16, ThemeBuilder.YELLOW))


func _display(v: VBoxContainer) -> void:
	var s := GameState.settings
	# UI size waits a moment after the last tap, so the page doesn't jump while you're still stepping.
	_ui_timer = Timer.new()
	_ui_timer.one_shot = true
	_ui_timer.wait_time = 0.6
	add_child(_ui_timer)
	var ui_size := _stepper_row(v, "UI size", 0.8, 1.6, 0.05, float(s.get("ui_scale", 1.0)), func(x): return "%d%%" % roundi(x * 100), 100.0)
	ui_size.name = "UiSize"
	_ui_timer.timeout.connect(func(): _apply("ui_scale", ui_size.value))
	ui_size.value_changed.connect(func(_x): _ui_timer.start())
	var cam := UiKit.option(CAMERA_NAMES, maxi(0, CAMERA_IDS.find(str(s.get("camera_preset", "cozy")))))
	cam.item_selected.connect(func(i): _apply("camera_preset", CAMERA_IDS[i]))
	v.add_child(UiKit.field_row("Camera angle", cam, CAPTION))
	var pcam_ids := ["high", "classic", "low"]
	var pcam := UiKit.option(["High", "Over the shoulder", "Low and close"], maxi(0, pcam_ids.find(str(s.get("platform_camera", "high")))))
	pcam.item_selected.connect(func(i): _apply("platform_camera", pcam_ids[i]))
	v.add_child(UiKit.field_row("Platform camera", pcam, CAPTION))
	var modes := [["auto", "Automatic"], ["on", "On"], ["off", "Off"]]
	var touch := UiKit.option(modes.map(func(m): return m[1]), maxi(0, modes.map(func(m): return m[0]).find(str(s.get("touch_ui", "auto")))))
	touch.tooltip_text = "The phone's tab bar"
	touch.item_selected.connect(func(i): _apply("touch_ui", str(modes[i][0])))
	v.add_child(UiKit.field_row("Touch layout", touch, CAPTION))
	var rates: Array = Graphics.FRAME_RATES
	var rate := UiKit.option(rates.map(func(m): return m[1]), maxi(0, rates.map(func(m): return m[0]).find(str(s.get("frame_rate", "auto")))))
	rate.tooltip_text = "Matches the screen"
	rate.item_selected.connect(func(i): _apply("frame_rate", str(rates[i][0])))
	v.add_child(UiKit.field_row("Frame rate", rate, CAPTION))
	preload("res://scripts/ui/settings_graphics.gd").add_rows(v)
	preload("res://scripts/ui/settings_android_power.gd").add_rows(v)


func _audio(v: VBoxContainer) -> void:
	var s := GameState.settings
	var pct := func(x): return "%d%%" % roundi(x * 100)
	var music := _stepper_row(v, "Music volume", 0.0, 1.0, 0.05, float(s.get("music_volume", 0.7)), pct, 100.0)
	music.name = "MusicVolume"
	music.value_changed.connect(func(x): _apply("music_volume", x))
	var sfx := _stepper_row(v, "Sound volume", 0.0, 1.0, 0.05, float(s.get("sfx_volume", 0.8)), pct, 100.0)
	sfx.name = "SoundVolume"
	sfx.value_changed.connect(func(x): _apply("sfx_volume", x))
	_check(v, "Voice blips", "text_blips", true)
	_check(v, "Button clicks", "ui_sounds", true, "UiSounds")


func _controls(v: VBoxContainer) -> void:
	var s := GameState.settings
	var hand := UiKit.option(["Right hand", "Left hand"], 1 if str(s.get("hand", "right")) == "left" else 0)
	hand.tooltip_text = "Left: IJKL walk"
	hand.item_selected.connect(func(i): _apply("hand", "left" if i == 1 else "right"))
	v.add_child(UiKit.field_row("I play with my", hand, CAPTION))
	var wheel := UiKit.option(["Zooms", "Turns"], 1 if str(s.get("wheel_mode", "zoom")) == "rotate" else 0)
	wheel.item_selected.connect(func(i): _apply("wheel_mode", "rotate" if i == 1 else "zoom"))
	v.add_child(UiKit.field_row("Scroll wheel", wheel, CAPTION))
	var profiles := preload("res://scripts/platform/platform_profiles.gd")
	var physics := UiKit.option(profiles.NAMES, profiles.IDS.find(profiles.normalize(str(s.get("platform_profile", "polox")))))
	physics.name = "PlatformProfile"
	physics.item_selected.connect(func(i): _apply("platform_profile", profiles.IDS[i]))
	v.add_child(UiKit.field_row("Platform physics", physics, CAPTION))
	_check(v, "Vibration (phones)", "haptics", true, "Haptics")


func _accessibility(v: VBoxContainer) -> void:
	_check(v, "Reduce motion", "reduce_motion", false, "ReduceMotion")
	_check(v, "Reduce transparency", "reduce_transparency", false, "ReduceTransparency", "Solid, not glass")
	_heading(v, "Battles")
	var assists: Dictionary = (GameState.settings.get("battle_assists", {}) as Dictionary).duplicate() if GameState.settings.get("battle_assists") is Dictionary else {}
	for opt in [["story", "Story mode"], ["slow_bullets", "Slower bullets"], ["wide_timing", "Wider FIGHT timing"], ["big_graze", "Bigger graze area"]]:
		var cb := CheckBox.new()
		cb.text = str(opt[1])
		var key := str(opt[0])
		cb.button_pressed = bool(assists.get(key, false))
		cb.toggled.connect(func(on):
			assists[key] = on
			_apply("battle_assists", assists.duplicate()))
		v.add_child(cb)


func _heading(v: Control, text: String) -> void:
	var l := UiKit.label(text, 22, ThemeBuilder.YELLOW)
	l.add_theme_constant_override("line_spacing", 0)
	v.add_child(l)


func _check(v: Control, text: String, key: String, default: bool, node_name: String = "", tip: String = "") -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	if node_name != "":
		cb.name = node_name
	if tip != "":
		cb.tooltip_text = tip
	cb.button_pressed = bool(GameState.settings.get(key, default))
	cb.toggled.connect(func(on): _apply(key, on))
	v.add_child(cb)
	return cb


func _stepper_row(parent: Control, caption: String, lo: float, hi: float, step: float, value: float, fmt: Callable, display_scale: float = 1.0) -> HBoxContainer:
	var st := UiKit.stepper(lo, hi, step, value, fmt, display_scale)
	parent.add_child(UiKit.field_row(caption, st, CAPTION))
	return st


func _apply(key: String, value: Variant) -> void:
	GameState.settings[key] = value
	GameState.save_settings()
