extends "res://scripts/ui/screen_panel.gd"
## Settings > Light World > Helper setup (the Advanced corner, like the AI developer settings): the keys,
## model names and endpoint for the helpers that need them, a Codex CLI sign-in check and a connection
## test. Keys live in settings.json on this computer only: never logged, synced, exported or sent to a
## phone. The copy/paste helper needs none of this.
## Tags: [AI_HELPER]

const Research := preload("res://scripts/home/research.gd")
const KeyFormat := preload("res://scripts/ai/key_format.gd")

var result_line: Label
var _testing := false
var _checking_codex := false
var _active_helper: Node = null
var _active_codex: Node = null


func _exit_tree() -> void:
	if is_instance_valid(_active_helper):
		_active_helper.cancel()
		_active_helper.queue_free()
	_active_helper = null
	if is_instance_valid(_active_codex):
		_active_codex.cancel()
		_active_codex.queue_free()
	_active_codex = null


func setup_helpers() -> void:
	setup("Helper setup", Vector2(860, 680))
	result_line = UiKit.para("", 16, ThemeBuilder.YELLOW)
	result_line.name = "SetupResult"
	var selected := Research.preferred()
	result_line.text = "%s · %s" % [Research.short_name(selected), Research.state_note(selected, Research.available())]
	body.add_child(result_line)
	var lw: Dictionary = Research.settings()
	var v := UiKit.vbox(10)
	v.add_child(UiKit.para("Copy / paste needs no key. API use is billed separately from ChatGPT or Claude plans.", 16, ThemeBuilder.MUTED))
	for spec in [["Claude API key", "claude_api_key", true, "ClaudeKey"], ["Claude model", "claude_model", false, "ClaudeModel"],
			["OpenAI API key", "openai_key", true, "OpenAIKey"], ["OpenAI model", "openai_model", false, "OpenAIModel"],
			["Compatible URL", "compatible_url", false, "CompatibleUrl"], ["Compatible model", "compatible_model", false, "CompatibleModel"],
			["Compatible key", "compatible_key", true, "CompatibleKey"], ["Codex model", "codex_model", false, "CodexModel"]]:
		var setting_key := str(spec[1])
		var input := UiKit.line_edit("", str(lw.get(setting_key, "")))
		input.secret = bool(spec[2])
		input.name = str(spec[3])
		if bool(spec[2]):
			input.text_changed.connect(func(value): _save_key(setting_key, value))
		else:
			input.text_changed.connect(func(value): _save(setting_key, value.strip_edges()))
		v.add_child(UiKit.field_row(str(spec[0]), input, 200))
	var servers: Array = load("res://scripts/home/osm.gd").MAP_SERVERS
	var current := str(lw.get("overpass_url", servers[0][1]))
	var at := 0
	for i in servers.size():
		if str(servers[i][1]) == current:
			at = i
	var pick := UiKit.option(servers.map(func(s): return str(s[0])), at)
	pick.name = "MapServer"
	pick.item_selected.connect(func(i): _save("overpass_url", str(servers[i][1])))
	v.add_child(UiKit.field_row("Map server", pick, 200))
	v.add_child(UiKit.para("Streets come from the server you pick here; only it gets your map coordinates.", 14, ThemeBuilder.MUTED))

	# --- Google Maps (Gemini / Google AI Plus / Google One) ----------------------------------------
	var GoogleMaps := preload("res://scripts/home/google_maps.gd")
	v.add_child(UiKit.label("Google Maps (Gemini / Google AI Plus)", 20, ThemeBuilder.YELLOW))
	v.add_child(UiKit.para("Opt-in: enriches your Light World's nearby public landmarks via Gemini Maps Grounding or Google Maps Places. Neighbours' private homes are never kept.", 14, ThemeBuilder.MUTED))
	var gm_enable := CheckBox.new()
	gm_enable.name = "GoogleMapsEnabled"
	gm_enable.text = "Enable Google Maps integration"
	gm_enable.button_pressed = bool(lw.get("google_maps_enabled", false))
	gm_enable.toggled.connect(func(on):
		_save("google_maps_enabled", on)
		result_line.text = "Google Maps: " + GoogleMaps.status_summary())
	v.add_child(gm_enable)
	var gm_modes: Array = Array(GoogleMaps.MODES)
	var gm_labels: Array = gm_modes.map(func(m): return str(GoogleMaps.MODE_LABELS[m]))
	var gm_pick := UiKit.option(gm_labels, maxi(0, gm_modes.find(GoogleMaps.mode())))
	gm_pick.name = "GoogleMapsMode"
	gm_pick.item_selected.connect(func(i):
		_save("google_maps_mode", str(gm_modes[i]))
		result_line.text = "Google Maps: " + GoogleMaps.status_summary())
	v.add_child(UiKit.field_row("Google Maps mode", gm_pick, 200))
	var gm_key := UiKit.line_edit("Optional (Gemini key from Settings > AI also works)", str(lw.get("google_maps_api_key", "")))
	gm_key.name = "GoogleMapsApiKey"
	gm_key.secret = true
	gm_key.text_changed.connect(func(value): _save_key("google_maps_api_key", value))
	v.add_child(UiKit.field_row("Google Maps key", gm_key, 200))

	var row := UiKit.flow_row(8)
	var codex := UiKit.button("Check Codex", func(): _check_codex(), 0)
	codex.name = "CheckCodex"
	row.add_child(codex)
	var test := UiKit.button("Test helper", func(): _test_helper(), 0)
	test.name = "TestHelper"
	row.add_child(test)
	v.add_child(row)
	body.add_child(UiKit.page(v))


func _check_codex() -> void:
	if _checking_codex or _testing:
		return
	_checking_codex = true
	_set_busy(true)
	result_line.text = "Checking Codex..."
	var cli: Node = preload("res://scripts/home/helper_codex.gd").new()
	_active_codex = cli
	add_child(cli)
	var result: Dictionary = await cli.check()
	if _active_codex == cli:
		_active_codex = null
	if is_instance_valid(cli):
		cli.queue_free()
	_checking_codex = false
	_set_busy(false)
	if is_inside_tree():
		result_line.text = ("Codex is signed in (%s). It can search the web." % str(result.get("access", "CLI"))) if bool(result.ok) else str(result.error)


## A synthetic request (no home details): does the chosen helper answer in the right shape?
func _test_helper() -> void:
	if _testing or _checking_codex:
		return
	var selected := str(Research.preferred())
	if selected in ["manual", "none"]:
		result_line.text = "Nothing to test: copy / paste needs no connection." if selected == "manual" else "Choose a helper first."
		return
	result_line.text = "Testing (no home details sent)..."
	_testing = true
	_set_busy(true)
	var helper: Node = Research.new()
	_active_helper = helper
	add_child(helper)
	var reply := {"done": false, "result": {}}
	helper.finished.connect(func(d: Dictionary):
		reply.result = d
		reply.done = true, CONNECT_ONE_SHOT)
	helper.progress.connect(func(line): result_line.text = str(line))
	helper.start_words(selected, "Connection test. Return an empty changes array and an empty questions array.", {}, "")
	while not bool(reply.done) and is_instance_valid(helper) and helper == _active_helper and is_inside_tree():
		await get_tree().process_frame
	if _active_helper == helper:
		_active_helper = null
	if is_instance_valid(helper):
		if not bool(reply.done):
			helper.cancel()
		helper.queue_free()
	_testing = false
	_set_busy(false)
	if bool(reply.done) and is_inside_tree():
		var result: Dictionary = reply.result
		result_line.text = "It answered correctly." if bool(result.ok) else Research.advice(result)


## A key box: the key tidied (no quotes, spaces or "Bearer "), and kept only if it isn't plainly
## another service's (an OpenAI key in the Claude box would be sent to Anthropic): then it says whose
## it is and where it goes.
func _save_key(k: String, pasted: String) -> void:
	var key := KeyFormat.clean(pasted)
	var why := KeyFormat.mismatch(key, str(KeyFormat.HELPER_SLOTS.get(k, "custom")))
	_save(k, key if why == "" else "")
	if why != "":
		result_line.text = why
	elif result_line.text.begins_with("That is a "):
		result_line.text = ""


func _save(k: String, value: Variant) -> void:
	var lw: Dictionary = (GameState.settings.get("light_world", {}) as Dictionary).duplicate() if GameState.settings.get("light_world") is Dictionary else {}
	lw[k] = value
	GameState.settings["light_world"] = lw
	GameState.save_settings()


func _set_busy(busy: bool) -> void:
	for name in ["TestHelper", "CheckCodex"]:
		var button := find_child(name, true, false) as Button
		if button:
			button.disabled = busy
