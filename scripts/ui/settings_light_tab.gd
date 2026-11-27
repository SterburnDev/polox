extends ScrollContainer
## Settings > Light World: your real home. My home (the sketch and its sources), Map my home (the
## Survey), Forget my home; who looks things up when you say so (Claude on this computer through Claude
## Code, Claude with your API key, Gemini with your chat key, or nobody), and an optional Google Maps key
## (references only). Keys are saved in settings.json on this computer and never logged, synced or sent
## to a phone.
## Tags: [LIGHT_WORLD_MAP]

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Research := preload("res://scripts/home/research.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")

var world: Node            # the running game world (for My home, Map my home)
var _status: Label
var _pick: OptionButton
var _cc_state: Label


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_deadzone = UiKit.touch_deadzone()
	var v := UiKit.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(v)
	v.add_child(UiKit.label("My home", 22, ThemeBuilder.YELLOW))
	_status = UiKit.para(_home_line(), 18)
	_status.name = "HomeStatus"
	v.add_child(_status)
	var row := UiKit.flow_row(8)
	var see := UiKit.button("Open My home", func(): _open_home(), 0)
	see.name = "OpenHome"
	see.disabled = world == null or not HomeStore.exists()
	row.add_child(see)
	var map := UiKit.button("Map my home", func(): _map(), 0)
	map.name = "MapHome"
	map.disabled = world == null
	row.add_child(map)
	var tpl := UiKit.button("Templates", func(): _pick_template(), 0)
	tpl.name = "TemplateHome"
	tpl.disabled = world == null
	row.add_child(tpl)
	var tell := UiKit.button("Tell Polox about home", func(): _tell(), 0)
	tell.name = "TellHome"
	tell.disabled = world == null or not HomeStore.exists()
	row.add_child(tell)
	var forget := UiKit.button("Forget my home", func(): _forget(), 0)
	forget.name = "ForgetHome"
	forget.disabled = not DirAccess.dir_exists_absolute(HomeStore.dir())
	row.add_child(forget)
	v.add_child(row)
	v.add_child(UiKit.para("Stays on device; paired phones share house and streets.", 16, ThemeBuilder.MUTED))
	var on_phone := CheckBox.new()
	on_phone.text = "Share with phones"
	on_phone.name = "HomeOnPhone"
	on_phone.button_pressed = bool(Research.settings().get("on_phone", true))
	on_phone.toggled.connect(func(on): _save("on_phone", on))
	v.add_child(on_phone)
	var remind := CheckBox.new()
	remind.text = "Gentle reminders"
	remind.name = "Reminders"
	remind.button_pressed = bool(Research.settings().get("question_reminders", false))
	remind.toggled.connect(func(on): _save("question_reminders", on))
	v.add_child(remind)

	v.add_child(UiKit.label("Who looks things up", 22, ThemeBuilder.YELLOW))
	var av := Research.available()
	var lw: Dictionary = Research.settings()
	_pick = UiKit.option(_helper_labels(av), maxi(0, Array(Research.HELPERS).find(Research.preferred() if str(lw.get("helper", "")) == "" else str(lw.helper))))
	_pick.name = "Helper"
	_pick.item_selected.connect(func(i): _save("helper", Research.HELPERS[i]))
	v.add_child(UiKit.field_row("Helper", _pick, 200))
	var cc := UiKit.flow_row(8)
	_cc_state = UiKit.para("", 16, ThemeBuilder.MUTED)
	_cc_state.name = "ClaudeCodeState"
	cc.add_child(_cc_state)
	var sign := UiKit.button("Sign in to Claude", func(): _sign_in(), 0)
	sign.name = "SignInClaude"
	sign.disabled = not bool(av.claude_code)
	cc.add_child(sign)
	var again := UiKit.button("Check", func(): _check_sign_in(), 0)
	again.name = "CheckClaude"
	again.disabled = not bool(av.claude_code)
	cc.add_child(again)
	v.add_child(cc)
	_show_claude_state()
	if bool(av.claude_code) and Research.sign_in_state == -1:
		_check_sign_in()
	# Keys, models, the endpoint, Codex's check and a test: Advanced, in their own screen.
	var setup := UiKit.button("Helper setup", func(): _helper_setup(), 0)
	setup.name = "HelperSetup"
	v.add_child(setup)


func _helper_setup() -> void:
	var p: Control = load("res://scripts/ui/settings_helpers_panel.gd").new()
	if world and world.main:
		world.main.open_panel(p)
	else:
		get_tree().root.add_child(p)
	p.setup_helpers()


func _helper_labels(av: Dictionary) -> Array:
	var labels: Array = []
	for h in Research.HELPERS:
		var note := Research.state_note(h, av)
		labels.append(str(Research.HELPER_LABELS[h]) + ("  (%s)" % note if note != "" else ""))
	return labels


## Claude Code's sign-in, as last checked (it uses your own Claude sign-in, up to $5 a lookup).
func _show_claude_state() -> void:
	var av := Research.available()
	if not bool(av.claude_code):
		_cc_state.text = "Claude Code: not here."
	else:
		_cc_state.text = str({1: "Claude Code: signed in.",
			0: "Claude Code: sign in first."}.get(Research.sign_in_state, "Claude Code: checking..."))
	var labels := _helper_labels(av)
	for i in labels.size():
		_pick.set_item_text(i, str(labels[i]))


func _check_sign_in() -> void:
	var r: Node = Research.new()
	add_child(r)
	_cc_state.text = "Claude Code: checking..."
	await r.check_sign_in()
	r.queue_free()
	if is_inside_tree():
		_show_claude_state()


## Claude Code's own sign-in window (your browser opens); Polox checks every few seconds until it's done.
func _sign_in() -> void:
	if not Research.open_sign_in():
		_cc_state.text = "In a terminal: claude auth login"
		return
	_cc_state.text = "Waiting for the sign-in..."
	var r: Node = Research.new()
	add_child(r)
	await r.wait_for_sign_in(5.0)
	r.queue_free()
	if is_inside_tree():
		_show_claude_state()


func _home_line() -> String:
	if not HomeStore.exists():
		return "Polox hasn't met your home yet."
	var h := HomeStore.load_home()
	var plan: Dictionary = h.get("plan", {})
	var floors: Array = plan.get("floors", [])
	var rooms := 0
	for f in floors:
		rooms += (f.get("rooms", []) as Array).size()
	var from := "your answers and %s" % ("Claude" if str(h.get("helper", "")).begins_with("claude") else str(h.get("helper", "a helper"))) if str(h.get("helper", "")) != "" else "your answers"
	return "%d floor%s, %d rooms, from %s." % [floors.size(), "" if floors.size() == 1 else "s", rooms, from]


func _save(k: String, value: Variant) -> void:
	var lw: Dictionary = (GameState.settings.get("light_world", {}) as Dictionary).duplicate() if GameState.settings.get("light_world") is Dictionary else {}
	lw[k] = value
	GameState.settings["light_world"] = lw
	GameState.save_settings()


func _close_settings() -> void:
	var n: Node = get_parent()
	while n and not n.has_method("close"):
		n = n.get_parent()
	if n:
		n.close()


func _open_home() -> void:
	if world == null:
		return
	_close_settings()
	var p: Control = load("res://scripts/home/map_home_panel.gd").new()
	world.main.open_panel(p)
	p.setup_home(world)


func _tell() -> void:
	if world == null:
		return
	_close_settings()
	var p: Control = load("res://scripts/home/tell_polox_panel.gd").new()
	world.main.open_panel(p)
	p.setup_tell(world)


func _map() -> void:
	if world == null:
		return
	_close_settings()
	await world.dark.map_home()


func _pick_template() -> void:
	if world == null:
		return
	var LightHome := preload("res://scripts/world/light_home.gd")
	var Realms := preload("res://scripts/world/realms.gd")
	var p: Control = load("res://scripts/ui/choice_panel.gd").new()
	var opts: Array = []
	for tpl in LightHome.TEMPLATES:
		var tid := str(tpl.id)
		opts.append(["%s — %s" % [str(tpl.name), str(tpl.desc)], func():
			var entry := LightHome.apply_template(tid)
			if Realms.is_light(world.room.data) or GameState.current_room_id.begins_with(Realms.PREFIX):
				world.load_room(entry)
			_status.text = _home_line()
			GameState.notify("Done")
		])
	opts.append(["Cancel", func(): pass])
	world.main.open_panel(p)
	p.ask("Templates", "Skip sequence; stays on device.", opts)


func _forget() -> void:
	if world == null:
		HomeStore.forget_all()
		_status.text = _home_line()
		return
	var p: Control = load("res://scripts/home/map_home_panel.gd").new()
	world.main.open_panel(p)
	p.setup_home(world)
	p._confirm_forget()
