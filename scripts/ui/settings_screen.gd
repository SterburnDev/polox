extends "res://scripts/ui/screen_panel.gd"
## Settings, by category: Gameplay, Display (with graphics), Audio, Music (themes and every song),
## Controls, Accessibility, AI (provider, key, Test connection), the Light World, Phone Link and Cloud sync.
## The categories are chips that wrap on a narrow screen; each page scrolls by swipe, wheel or keys
## without a visible bar, and numbers use steppers, not sliders. Every change saves immediately.
## Tags: [AI_HELPER] [GLASS_UI]

const Presets := preload("res://scripts/ai/presets.gd")
const SettingsGame := preload("res://scripts/ui/settings_game_tab.gd")
const SettingsMusic := preload("res://scripts/ui/settings_music_tab.gd")
const PhoneLinkTab := preload("res://scripts/ui/phone_link_tab.gd")
const SettingsLight := preload("res://scripts/ui/settings_light_tab.gd")
const CloudSyncTab := preload("res://scripts/ui/cloud_sync_tab.gd")
const CloudService := preload("res://scripts/sync/cloud_service.gd")

var _adv_box: VBoxContainer     # AI > Advanced: server, model, limits
var _adv_btn: Button
var ai: Dictionary
var main: Node                  # for Phone Link (defaults to the running game's Main)
var start_tab := 0
var start_on := ""              # a tab by its title (e.g. Phone Link); wins over start_tab when it's there
var _preset_opt: OptionButton
var _help: Label
var _key: LineEdit
var _key_note: Label        # why a pasted key isn't kept for this provider (it is another one's)
var _key_fix: Button        # ...and one tap to the provider it belongs to
var _testing := false
var _base: LineEdit
var _model: LineEdit
var _models_opt: OptionButton
var _temp: HBoxContainer    # (a stepper)
var _max_tokens: SpinBox
var _timeout: SpinBox
var _rpm: SpinBox
var _chatter: CheckBox
var _result: Label
var _test_btn: Button
const PICK := "Pick from list..."
var _ollama_btn: Button
var _loading := false


## The categories, in order (the first six are always there; Light World, Phone Link and Cloud sync
## when they apply).
const ORDER := ["Gameplay", "Display", "Audio", "Music", "Controls", "Accessibility", "AI"]
## Older names that still open the right page (What's new, help text, saved links).
const ALIASES := {"Comfort": "Gameplay", "Sound": "Audio"}
static var last_tab := ""        # the page you were on last time (this session)

var tabs: TabContainer
var _chips: Array[Button] = []


func _ready() -> void:
	setup("Settings", Vector2(1120, 700))
	panel.theme = ThemeBuilder.info_theme()   # [GLASS_UI] iOS 7's clear, layered lists for a dense screen
	ai = GameState.settings.get("ai", {}).duplicate(true)
	# Categories as chips that wrap onto more lines on a narrow screen (a phone's tab bar would scroll
	# sideways and hide some); the pages themselves stay in a TabContainer, each keeping its own scroll.
	var nav := UiKit.flow_row(8)
	nav.name = "Categories"
	body.add_child(nav)
	tabs = TabContainer.new()
	tabs.name = "Pages"
	tabs.tabs_visible = false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	for section in SettingsGame.SECTIONS:
		var page := SettingsGame.new()
		page.section = section
		page.name = str(SettingsGame.TITLES[section])
		tabs.add_child(page)
		if section == "audio":
			if main == null:
				main = get_tree().current_scene if get_tree().current_scene and get_tree().current_scene.get("phone_link") else null
			var music := SettingsMusic.new()
			music.name = "Music"   # (also its tab's title)
			music.main = main
			tabs.add_child(music)
	var ai_tab := UiKit.vbox(10)
	ai_tab.name = "AI friend brain"
	var ai_page := UiKit.page(ai_tab)
	ai_page.name = "AI"
	tabs.add_child(ai_page)
	_build_ai(ai_tab)
	var light := SettingsLight.new()
	light.name = "Light World"
	light.world = main.game if main and main.get("game") else null
	tabs.add_child(light)
	if main and main.get("phone_link") and main.get("phone") == null and not OS.has_feature("web"):
		var pl := PhoneLinkTab.new()
		pl.name = "Phone Link"
		pl.build(main)
		tabs.add_child(pl)
	if CloudService.supported():   # [CLOUD_SYNC] PCs and the Android app (the browser plays through the PC)
		var cloud := CloudSyncTab.new()
		cloud.name = "Cloud sync"
		cloud.main = main
		cloud.open_page.connect(show_page_named)
		tabs.add_child(cloud)
	for i in tabs.get_tab_count():
		var page := tabs.get_tab_control(i)
		tabs.set_tab_title(i, str(page.name))
		if page is ScrollContainer:
			UiKit.hide_bar(page)
			UiKit.allow_swipe_over_buttons(page)
		var chip := UiKit.button(tabs.get_tab_title(i), func(): show_page(i), 0)
		chip.name = "Chip_" + tabs.get_tab_title(i).replace(" ", "")
		chip.toggle_mode = true
		chip.custom_minimum_size.x = 0 if UiKit.upright_phone() else 112
		nav.add_child(chip)
		_chips.append(chip)
	var want := str(ALIASES.get(start_on.get_slice(" ", 0), start_on))   # ("Comfort & sound" -> Comfort)
	var at := clampi(start_tab, 0, tabs.get_tab_count() - 1)
	if want == "" and last_tab != "":
		want = last_tab
	for i in tabs.get_tab_count():
		if want != "" and tabs.get_tab_title(i) == want:
			at = i
	show_page(at)
	tabs.tab_changed.connect(func(_i): show_page(tabs.current_tab))
	# Keyboard focus starts on the open page's chip (not always the first: two highlights at once).
	if at < _chips.size():
		_chips[at].call_deferred("grab_focus")


## Opens a category by its title (a page asking for another one: Cloud sync -> Phone Link).
func show_page_named(title: String) -> void:
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == title:
			show_page(i)
			return


func show_page(i: int) -> void:
	if tabs.current_tab != clampi(i, 0, tabs.get_tab_count() - 1):
		tabs.current_tab = clampi(i, 0, tabs.get_tab_count() - 1)
	last_tab = tabs.get_tab_title(tabs.current_tab)
	for k in _chips.size():
		_chips[k].set_pressed_no_signal(k == tabs.current_tab)


func _build_ai(v: VBoxContainer) -> void:
	var m: Node = get_tree().current_scene if is_inside_tree() else null
	if m and m.get("phone"):
		_build_phone_ai(v, m.phone)
		return
	_loading = true
	_preset_opt = UiKit.option([])
	for id in Presets.ORDER:
		_preset_opt.add_item(Presets.label(id))
	_preset_opt.select(maxi(0, Presets.ORDER.find(str(ai.get("preset", "mock")))))
	_preset_opt.item_selected.connect(_on_preset)
	v.add_child(UiKit.field_row("Provider", _preset_opt))
	_help = UiKit.para("", 18, ThemeBuilder.MUTED)
	v.add_child(_help)
	# Each provider keeps its own key: switching provider shows (and sends) only that one's.
	_key = UiKit.line_edit("Paste your key", Presets.key_for(ai, str(ai.get("preset", "mock"))))
	_key.secret = true
	_key.context_menu_enabled = true
	_key.text_changed.connect(func(t): _save_key(Presets.KeyFormat.clean(t)))
	var key_row := UiKit.field_row("API key", _key)
	var show_btn := UiKit.button("Show", func(): _key.secret = not _key.secret, 100)
	key_row.add_child(show_btn)
	v.add_child(key_row)
	# A key that is plainly another service's is never kept for this one: say whose, and where it goes.
	var note_row := UiKit.hbox(12)
	_key_note = UiKit.para("", 16, ThemeBuilder.DANGER)
	_key_note.name = "KeyNote"
	_key_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_row.add_child(_key_note)
	_key_fix = UiKit.button("", _use_key_where_it_belongs, 0)
	_key_fix.name = "KeyFix"
	note_row.add_child(_key_fix)
	note_row.visible = false
	v.add_child(note_row)
	v.add_child(UiKit.para("Kept on this PC, never in logs.", 16, ThemeBuilder.MUTED))
	var test_row := UiKit.hbox(12)
	_test_btn = UiKit.button("Test connection", _test, 220)
	test_row.add_child(_test_btn)
	_ollama_btn = UiKit.button("Start Ollama", _start_ollama, 190)
	_ollama_btn.name = "StartOllama"
	_ollama_btn.visible = false
	test_row.add_child(_ollama_btn)
	_result = UiKit.para("", 18, ThemeBuilder.MUTED)
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_row.add_child(_result)
	v.add_child(test_row)
	_chatter = CheckBox.new()
	_chatter.text = "Friends chat together"
	_chatter.button_pressed = bool(ai.get("npc_chatter", true))
	_chatter.toggled.connect(func(on): _save_ai("npc_chatter", on))
	v.add_child(_chatter)
	# Advanced (one tap): the server, the model and the limits. Open by itself for a custom server.
	_adv_box = UiKit.vbox(10)
	_adv_box.name = "AiAdvanced"
	_adv_btn = UiKit.button("", func(): _show_advanced(not _adv_box.visible), 0)
	_adv_btn.name = "AiAdvancedToggle"
	_adv_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(_adv_btn)
	v.add_child(_adv_box)
	var av := _adv_box
	_base = UiKit.line_edit("https://...", str(ai.get("base_url", "")))
	_base.text_changed.connect(func(t): _save_ai("base_url", t.strip_edges()))
	av.add_child(UiKit.field_row("Server address", _base))
	_model = UiKit.line_edit("model name", str(ai.get("model", "")))
	_model.text_changed.connect(func(t): _save_ai("model", t.strip_edges()))
	var model_row := UiKit.field_row("Model", _model)
	_models_opt = UiKit.option([PICK])
	_models_opt.visible = false
	_models_opt.item_selected.connect(func(i):
		if i > 0:
			_model.text = _models_opt.get_item_text(i)
			_save_ai("model", _model.text))
	model_row.add_child(_models_opt)
	model_row.add_child(UiKit.button("List models", _list_models, 150))
	av.add_child(model_row)
	_temp = UiKit.stepper(0.0, 1.5, 0.05, float(ai.get("temperature", 0.85)), func(x): return "%.2f" % x)
	_temp.name = "Creativity"
	_temp.value_changed.connect(func(x): _save_ai("temperature", x))
	av.add_child(UiKit.field_row("Creativity", _temp))
	_max_tokens = _spin(50, 2000, 50, float(ai.get("max_tokens", 400)), "max_tokens")
	av.add_child(UiKit.field_row("Longest reply", _max_tokens))
	_timeout = _spin(5, 180, 5, float(Presets.resolve(ai).get("timeout_s", 20)), "timeout_s")
	av.add_child(UiKit.field_row("Wait up to (s)", _timeout))
	_rpm = _spin(1, 120, 1, float(ai.get("requests_per_minute", 20)), "requests_per_minute")
	av.add_child(UiKit.field_row("Requests a minute", _rpm))
	_show_advanced(str(ai.get("preset", "mock")) == "custom")
	_loading = false
	_refresh_help()


func _show_advanced(on: bool) -> void:
	_adv_box.visible = on
	_adv_btn.text = ("▼ " if on else "▶ ") + "Advanced: server, model, limits"


## On a paired phone the AI lives on the PC: nothing to set up here.
func _build_phone_ai(v: VBoxContainer, phone: Node) -> void:
	v.add_child(UiKit.para("Chat through PC; offline otherwise.", 20, ThemeBuilder.CREAM))
	v.add_child(UiKit.para("PC: %s  •  AI: %s" % [phone.origin, AIClient.status_message], 18, ThemeBuilder.MUTED))
	var sync_label := UiKit.para("Sync: " + str(phone.client.detail if phone.client.detail != "" else phone.client.state), 18, ThemeBuilder.MUTED)
	v.add_child(sync_label)
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button("Sync now", func():
		var r: Dictionary = await phone.sync_now()
		if is_inside_tree():
			sync_label.text = "Sync: " + str(phone.client.detail if r.get("ok", false) else r.get("error", "")), 180))
	row.add_child(UiKit.button("Pair again" if phone.paired() else "Connect to your PC", func(): phone.open_pairing_page(), 220))
	v.add_child(row)
	if phone.get("app"):
		_build_app_link(v, phone)


## Polox for Android: which path reaches the PC, finding it again, the connection check, updates.
func _build_app_link(v: VBoxContainer, phone: Node) -> void:
	var m: Node = get_tree().current_scene if is_inside_tree() else null
	v.add_child(UiKit.para("Your PC: %s  •  %s" % [phone.link.pc_name() if phone.link.pc_name() != "" else "not paired", phone.connection_text()], 18, ThemeBuilder.MUTED))
	v.add_child(UiKit.para("Polox %s · automatic PC sync." % str(ProjectSettings.get_setting("application/config/version", "")), 16, ThemeBuilder.MUTED))
	if not phone.paired():
		# Not paired yet: the one thing to do is pair (find the PC, then its PIN or QR code).
		v.add_child(UiKit.para("Not paired yet.", 20, ThemeBuilder.YELLOW))
		var go := UiKit.button("📱 Connect to your PC", func():
			if m:
				m.open_app_connect(false, false), 0)
		go.name = "ConnectToPC"
		go.custom_minimum_size.y = 64
		v.add_child(go)
	var row := UiKit.flow_row(10)
	row.add_child(UiKit.button("Look for my PC", func():
		if not phone.paired():
			if m:
				m.open_app_connect(false, false)   # finding it leads to its PIN
			return
		var r: Dictionary = await phone.connect_pc()
		GameState.notify("📱 " + (phone.connection_text() if r.ok else "PC not found. Phone Link on? Same Wi-Fi?"))
		if r.ok and phone.paired() and not phone.client.busy:
			phone.client.sync(), 220))
	row.add_child(UiKit.button("Check connection", func():
		if m:
			var p: Control = load("res://scripts/ui/app_check_panel.gd").new()
			m.open_panel(p)
			p.setup_check(phone), 220))
	if not phone.update_offer.is_empty():
		row.add_child(UiKit.button("Update to %s" % str(phone.update_offer.version), func(): phone.open_update(), 220))
	row.add_child(UiKit.button("Forget this PC", func():
		await phone.unpair()
		GameState.notify("PC forgotten. Your worlds stay."), 220))
	v.add_child(row)


func _spin(lo: float, hi: float, step: float, value: float, key: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(160, 52)
	s.value_changed.connect(func(x): _save_ai(key, int(x)))
	return s


## The key goes to the provider chosen now, and only to it.
func _save_key(key: String) -> void:
	if _loading:
		return
	var keys: Dictionary = ai.get("keys", {}) if ai.get("keys") is Dictionary else {}
	var id := str(ai.get("preset", "mock"))
	keys[id] = key if Presets.KeyFormat.fits(key, id) else ""
	ai["keys"] = keys
	ai.erase("api_key")
	_save_ai("keys", keys)
	_show_key_note(key)


## Says why the key in the box isn't kept for the chosen provider ("" hides the line again).
func _show_key_note(key: String) -> void:
	var id := str(ai.get("preset", "mock"))
	_key_note.text = Presets.KeyFormat.mismatch(key, id)
	var owner := Presets.KeyFormat.chat_slot(key)
	_key_fix.visible = _key_note.text != "" and owner != ""
	_key_fix.text = ("Use %s" % Presets.label(owner).get_slice(" (", 0)) if owner != "" else ""
	_key_note.get_parent().visible = _key_note.text != ""


## The pasted key's own provider is chosen, and the key goes with it.
func _use_key_where_it_belongs() -> void:
	var key := Presets.KeyFormat.clean(_key.text)
	var at := Presets.ORDER.find(Presets.KeyFormat.chat_slot(key))
	if at < 0:
		return
	_preset_opt.select(at)
	_on_preset(at)
	_key.text = key
	_save_key(key)


## Ollama chosen: list what is installed and, if the model field is empty or names one that isn't,
## take the newest installed one.
func _pick_installed_ollama() -> void:
	var installed: Array = await AIClient.ollama_models()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if installed.is_empty():
		_result.text = AIClient.ollama_empty_note()
		return
	var names: Array = installed.map(func(m): return str(m.name))
	_models_opt.clear()
	_models_opt.add_item(PICK)
	for m in installed:
		_models_opt.add_item(str(m.name))
	_models_opt.visible = true
	var matched := AIClient._installed_ollama_model(installed, _model.text)
	if matched != "":
		if matched != _model.text:
			_model.text = matched
			_save_ai("model", _model.text)
	else:
		var picked := AIClient.choose_model(installed, _model.text)
		_model.text = picked if picked != "" else str(names[0])
		_save_ai("model", _model.text)
	_result.text = "Ollama: %d. Using %s." % [names.size(), _model.text]


## Windows: the Ollama app, if it's installed in its usual place (only when you press the button).
func _start_ollama() -> void:
	var app := AIClient.ollama_app()
	if app == "":
		_result.text = "Ollama isn't installed (ollama.com)."
		return
	OS.create_process(app, [])
	_result.text = "Starting Ollama..."


func _save_ai(key: String, value: Variant) -> void:
	if _loading:
		return
	ai[key] = value
	GameState.settings["ai"] = ai.duplicate(true)
	GameState.save_settings()
	_refresh_help()


func _on_preset(index: int) -> void:
	var id := Presets.ORDER[index]
	var p := Presets.get_preset(id)
	_loading = true
	ai["preset"] = id
	_key.text = Presets.key_for(ai, id)
	_base.text = str(p.get("base_url", ""))
	_model.text = str(p.get("model", ""))
	_timeout.value = float(p.get("timeout_s", 20))
	ai["base_url"] = _base.text
	ai["model"] = _model.text
	ai["timeout_s"] = int(_timeout.value)
	_models_opt.visible = false
	if id == "custom":
		_show_advanced(true)
	_loading = false
	_save_ai("preset", id)
	_show_key_note(_key.text)
	_result.text = ""
	if id == "ollama":
		_pick_installed_ollama()   # the models really on this PC (yours included), not a guessed one


func _refresh_help() -> void:
	var id := str(ai.get("preset", "mock"))
	var p := Presets.get_preset(id)
	var lines := PackedStringArray([str(p.get("help", ""))])
	if AIClient.is_mock() and id != "mock":
		lines.append("Offline until there's a key.")
	if id == "ollama" and AIClient.last_switch != "":
		lines.append(AIClient.last_switch)
	if _ollama_btn:
		_ollama_btn.visible = id == "ollama" and OS.get_name() == "Windows"
	_help.text = "\n".join(lines)
	var real := id != "mock"
	for c in [_key, _base, _model, _test_btn]:
		c.get_parent().modulate.a = 1.0 if real else 0.7   # (quieter, still readable: at 0.45 it fell under 4.5 to 1)
	_key.editable = real
	_base.editable = real
	_model.editable = real


## While a test runs, its waits count down in the result line ("Trying again in 12s...").
func _on_ai_status(_state: String, message: String) -> void:
	if _testing and _result:
		_result.text = message


func _test() -> void:
	if _testing:
		AIClient.cancel()   # the same button, while a test waits (a rate limit can take a minute), stops it
		return
	_result.text = "Testing..."
	_result.add_theme_color_override("font_color", ThemeBuilder.YELLOW)
	_testing = true
	var label := _test_btn.text
	_test_btn.text = "Stop"
	if not AIClient.status_changed.is_connected(_on_ai_status):
		AIClient.status_changed.connect(_on_ai_status)
	var r: Dictionary = await AIClient.test_connection()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_testing = false
	_test_btn.text = label
	if str(ai.get("preset", "")) == "ollama":
		var current_model := str(GameState.settings.get("ai", {}).get("model", ""))
		if current_model != "":
			ai["model"] = current_model
			_loading = true
			_model.text = current_model
			_loading = false
		_refresh_help()
	_result.text = ("✓ " if r.ok else "✗ ") + str(r.message)
	_result.add_theme_color_override("font_color", ThemeBuilder.MINT if r.ok else ThemeBuilder.DANGER)


func _list_models() -> void:
	_result.text = "Listing models..."
	var models: PackedStringArray = await AIClient.list_models()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if models.is_empty():
		_result.text = AIClient.models_note if AIClient.models_note != "" else "No list: type the name."
		return
	_models_opt.clear()
	_models_opt.add_item(PICK)
	for m in models:
		_models_opt.add_item(m)
	_models_opt.visible = true
	_result.text = "Found %d models." % models.size()
