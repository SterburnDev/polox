extends Node
## App shell: owns the UI layer, switches between title / onboarding / game,
## and runs the "back" stack (right-click, Q, X, Esc close the top screen).

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const PingServer := preload("res://scripts/net/ping_server.gd")
const InputSetup := preload("res://scripts/core/input_setup.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")
const DebugCapture := preload("res://scripts/core/debug_capture.gd")
## The world (game_world.gd and everything it pulls in: menus, build mode, battles, talk) is loaded when
## it's needed, not when Polox starts: compiling it took ~3.4 s of a ~4.2 s start from source, all before
## the title could show. The title starts a background load (_warm_world), so Continue doesn't wait.
const GAME_WORLD_PATH := "res://scripts/world/game_world.gd"
const REVEAL_WAIT_MS := 30000   # the longest the first steps wait for the house reveal
const StarterContent := preload("res://scripts/core/starter_content.gd")
const ConfirmPanel := preload("res://scripts/ui/confirm_panel.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const Addons := preload("res://scripts/core/addons.gd")
const AddonsPanel := preload("res://scripts/ui/addons_panel.gd")
const Onboarding := preload("res://scripts/ui/onboarding.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Migration := preload("res://scripts/core/migration.gd")
const Slots := preload("res://scripts/core/slots.gd")
const SaveMenu := preload("res://scripts/ui/save_menu.gd")
const Autosave := preload("res://scripts/core/autosave.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const PhoneMode := preload("res://scripts/phone/phone_mode.gd")
const TouchGestures := preload("res://scripts/ui/touch_gestures.gd")
const RecapCard := preload("res://scripts/ui/recap_card.gd")
const SymbolFont := preload("res://scripts/ui/symbol_font.gd")
const PhoneBanner := preload("res://scripts/ui/phone_banner.gd")
const HostWindow := preload("res://scripts/ui/host_window.gd")
const Pairing := preload("res://scripts/phone/pairing.gd")
const Device := preload("res://scripts/core/device.gd")
const AppConnectPanel := preload("res://scripts/ui/app_connect_panel.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const CloudService := preload("res://scripts/sync/cloud_service.gd")
const Moment := preload("res://scripts/ui/moment.gd")
const Graphics := preload("res://scripts/core/graphics.gd")
const AndroidIdle := preload("res://scripts/core/android_idle.gd")
const MissYou := preload("res://scripts/variety/miss_you.gd")
const MusicPlayer := preload("res://scripts/world/music_player.gd")
const MemoryRelief := preload("res://scripts/core/memory_relief.gd")

var ui_theme: Theme             # the one shared theme (its surfaces follow the world: set_ui_world)
var ui: Control              # themed root for all UI (CanvasLayers break theme inheritance)
var screen: Control          # title or onboarding
var game: Node               # the world, while playing
var panels: Array[Control] = []
var _toast_box: VBoxContainer
var _toast_root: Control
var autosave: Node                 # autosave.gd: snapshots, covers, playtime
var phone_link: Node               # phone_server.gd (off until switched on)
var phone: Node                    # phone_mode.gd, only in the phone (web) build
var gestures: Node                 # touch_gestures.gd: long-press, pinch, two-finger turn
var host_mode := false             # host.bat: only the Phone Link server, no game window needed
var ping_mode := false             # ping.bat: only Polox Ping (the tiny test server)
var _reload_after_build := false
var _reload_pending := false        # another device's changes arrived while you were busy (see reload_world_from_disk)
var _phone_toast_at := -1.0e9
var crash_log: Node                 # crash_log.gd: the flight recorder (not in the browser version)
var memory_guard: Node              # memory_guard.gd: answers a runaway memory use (Android)
var phone_banner: Button          # "Phone connecting: PIN ..." over everything (phone_banner.gd)
var host_window: Control          # host.bat's little window (host_window.gd)
var music: Node                   # music_player.gd: the menu theme (a world has its own: game.music)
var _creating_world := false
var _world_load_started := false
var _android_idle: AndroidIdle


## Start-up, in the order things depend on each other: the window and theme, the layers everything is
## drawn on, what keeps your data safe, Phone Link, the game's content, the first screen, and last any
## command-line mode (--doctor, --host, --ping, --write-build-id).
func _ready() -> void:
	_set_up_window()
	_set_up_layers()
	MissYou.cancel_all()   # you're here: no "missing you" notes are waiting any more
	_start_safety_nets()
	_start_phone_link()
	_load_content()
	_show_first_screen()
	if DebugCapture.wanted():
		add_child(DebugCapture.new())
	_run_command_line_mode()


func _set_up_window() -> void:
	InputSetup.register(str(GameState.settings.get("hand", "right")) == "left")
	get_window().title = "Polox"  # (the engine would append "(DEBUG)")
	if SymbolFont.wanted():
		SymbolFont.install()   # the browser has no fonts with ♥ ✓ 📱..., so draw our own
	if not Device.is_handheld() and not TouchGestures.phone_layout():
		get_window().min_size = Vector2i(960, 600)  # the dialogue box and panels need this much
	ThemeBuilder.solid = bool(GameState.settings.get("reduce_transparency", false))
	get_tree().node_added.connect(_tactile)


## The theme, the UI and toast layers, and the settings that change how they look.
func _set_up_layers() -> void:
	var theme := ThemeBuilder.build()
	ui_theme = theme
	RenderingServer.set_default_clear_color(ThemeBuilder.BG)
	ui = _themed_layer(10, theme)
	_toast_root = _themed_layer(50, theme)
	_toast_box = VBoxContainer.new()
	_toast_box.position.y = 16
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_root.add_child(_toast_box)
	GameState.toast.connect(show_toast)
	GameState.settings_changed.connect(apply_display_settings)
	apply_display_settings()


## Autosave, the crash log (not in a browser) and, where memory is tight, the memory guard.
func _start_safety_nets() -> void:
	autosave = Autosave.new()
	add_child(autosave)
	autosave.setup(self)
	if not OS.has_feature("web"):
		crash_log = load("res://scripts/core/crash_log.gd").new(SaveManager.root.path_join("logs"))
		add_child(crash_log)
		crash_log.setup(self)
	var guard_script: Script = load("res://scripts/core/memory_guard.gd")
	if guard_script.wanted():
		memory_guard = guard_script.new()
		memory_guard.name = "MemoryGuard"
		memory_guard.on_level = _on_memory_level
		memory_guard.on_limit = flush_all
		add_child(memory_guard)


func _start_phone_link() -> void:
	phone_link = PhoneServer.new()
	add_child(phone_link)
	phone_link.setup(SaveManager.root)
	phone_link.api.on_world_changed = _on_phone_changed_world
	phone_link.phone_reached.connect(_on_phone_reached)
	phone_link.phone_paired.connect(_on_phone_paired)
	phone_link.cleanup_stale_serve()   # a Serve mapping left by a crash or a closed window
	SaveManager.root_changed.connect(_on_save_root_changed)


func _on_save_root_changed(r: String) -> void:
	if is_instance_valid(phone_link) and not phone_link.running:
		phone_link.setup(r)


## Starter tile sets and templates, touch gestures, add-ons, the menu music and (on a phone) phone mode.
func _load_content() -> void:
	Slots.purge_trash()
	preload("res://scripts/world/template_factory.gd").ensure_builtin()  # starter tile sets + templates in the Library
	gestures = TouchGestures.new()
	add_child(gestures)
	gestures.setup(self)
	Addons.refresh(self)   # add-ons: words, pictures, music, sounds, tiles and trusted scripts
	music = MusicPlayer.new()
	music.name = "MenuMusic"
	add_child(music)
	if PhoneMode.wanted():
		phone = PhoneMode.new()
		add_child(phone)
		phone.setup(self)


func _show_first_screen() -> void:
	show_title()
	_show_migration_note()
	_show_layout_note()
	if phone:
		_phone_startup()


func _run_command_line_mode() -> void:
	if "--doctor" in OS.get_cmdline_user_args():
		_run_doctor_cli()
	elif "--host" in OS.get_cmdline_user_args():
		_start_host_mode()
	elif "--ping" in OS.get_cmdline_user_args():
		_start_ping_mode()
	elif "--write-build-id" in OS.get_cmdline_user_args():
		# tools\export_windows.bat: Polox.exe carries this source's build id, so it and its phone version agree.
		var id: String = load("res://scripts/phone/web_build.gd").write_baked_id("res://build_id.txt")
		print("[build-id] ", id)
		get_tree().quit(0 if id != "" else 1)


## Once, after the save folder was copied from the old PocketDarkWorld name.
## Once, after the single-world folder became slots/ (layout 2).
func _show_layout_note() -> void:
	var r: Dictionary = SaveManager.layout_result
	if r.is_empty() or str(r.get("slot_id", "")) == "":
		return
	SaveManager.layout_result = {}
	show_toast("Your world is now a save slot (Worlds menu). A snapshot was zipped into snapshots/ first.")


func _show_migration_note() -> void:
	var moved := preload("res://scripts/core/personal_data_migration.gd").pending_note(SaveManager.root)   # [MIGRATION]
	if moved != "":
		var pd := ConfirmPanel.new()
		pd.inform("Your data has one home", moved, "Got it")
		pd.answered.connect(func(_yes): preload("res://scripts/core/personal_data_migration.gd").mark_noted(SaveManager.root))
		open_panel(pd)
		return
	var note := Migration.pending_note(SaveManager.root)
	if note == "":
		if not SaveManager.migration_result.is_empty() and not SaveManager.migration_result.ok:
			show_toast("Couldn't copy your saves into PersonalData (%s). Still using the old folder." % SaveManager.migration_result.error)
		return
	var c := ConfirmPanel.new()
	c.inform("Welcome to Polox", note, "Got it")
	c.answered.connect(func(_yes): Migration.mark_noted(SaveManager.root))
	open_panel(c)


func toast_layer() -> CanvasLayer:
	return _toast_root.get_parent()


## A CanvasLayer with a full-screen, click-through Control carrying the theme.
func _themed_layer(layer: int, theme: Theme) -> Control:
	var cl := CanvasLayer.new()
	cl.layer = layer
	add_child(cl)
	var root := Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(root)
	return root


func apply_display_settings() -> void:
	InputSetup.register(str(GameState.settings.get("hand", "right")) == "left")
	var scale := clampf(float(GameState.settings.get("ui_scale", 1.0)), 0.75, 2.0)
	if TouchGestures.phone_layout():
		# Phones: the short side shows ~600 game pixels, so 52 px buttons stay
		# finger-sized (about 48 px on the screen) in portrait and landscape.
		var win := get_tree().root.size
		var base := minf(win.x / 1280.0, win.y / 720.0)
		if base > 0.0:
			scale *= maxf(1.0, minf(win.x, win.y) / base / 600.0)
		if not get_tree().root.size_changed.is_connected(apply_display_settings):
			get_tree().root.size_changed.connect(apply_display_settings)
	get_tree().root.content_scale_factor = scale
	var solid := bool(GameState.settings.get("reduce_transparency", false))
	if solid != ThemeBuilder.solid and ui_theme:
		ThemeBuilder.solid = solid   # Reduce transparency: every glass surface turns solid at once
		ThemeBuilder.fill(ui_theme)
	_apply_performance()


## memory_guard.gd found the app far bigger than it should be: the lighter graphics apply at once, and
## the heartbeat (crash_log.gd) records the size and what was done about it.
func _on_memory_level(_level: int, _mb: float) -> void:
	_apply_performance()
	if crash_log:
		crash_log.beat()


## Frame rate and graphics quality: phones default to 60 fps, desktop detail adapts,
## and Battery saver uses smaller pictures.
func _apply_performance() -> void:
	if OS.has_feature("android") and bool(GameState.settings.get(Graphics.ANDROID_IDLE_FPS_KEY, false)):
		if _android_idle == null:
			_android_idle = AndroidIdle.new()
		_android_idle.wake()
	else:
		_android_idle = null
	Graphics.apply(get_viewport())
	SaveManager.max_texture_side = 1024 if Graphics.low_detail() else SaveManager.MAX_TEXTURE_SIDE
	if game and game.sun:
		Graphics.apply_to_world(game.sun)
		var data: Dictionary = game.room.data if game.room else {}
		Graphics.apply_env(game.env, {}, game.open_sky(data), not preload("res://scripts/world/realms.gd").is_light(data) and str(data.get("kind", "")) == "outdoor")
		var detailed := preload("res://scripts/world/detail_pack.gd").active()
		if detailed != _detailed_was:
			_detailed_was = detailed
			game.rebuild_room()   # the Detailed pack on or off: the room's surfaces and furniture swap now
		_lamps_now()


## PC Ultra shadows / light shafts: which lamps cast shadows follows the camera (pc_detail.gd budget).
func _lamps_now() -> void:
	if game and Graphics.PcDetail.available() and game.cam and game.cam.is_inside_tree():
		Graphics.PcDetail.apply_lamps(get_tree(), Graphics.pc_tier(), game.cam.global_position)


## Battery saver: no real-time shadows, fewer particles, smaller pictures.
static func performance_mode() -> bool:
	return Graphics.low_detail()


func _clear_screen() -> void:
	if _android_idle:
		_android_idle.wake()
	if screen:
		screen.queue_free()
		screen = null


## The world's script: from the background load if it finished, else loaded now.
func _game_world_script() -> GDScript:
	if _world_load_started and ResourceLoader.load_threaded_get_status(GAME_WORLD_PATH) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_world_load_started = false
		return ResourceLoader.load_threaded_get(GAME_WORLD_PATH) as GDScript   # (waits if it's still loading)
	_world_load_started = false
	return load(GAME_WORLD_PATH) as GDScript


## Starts compiling the world in the background while the title is up.
func _warm_world() -> void:
	if Addons._testing():
		return
	if not _world_load_started and not ResourceLoader.has_cached(GAME_WORLD_PATH):
		_world_load_started = ResourceLoader.load_threaded_request(GAME_WORLD_PATH, "", true) == OK


func show_title() -> void:
	_close_all_panels()
	_end_game()
	_clear_screen()
	set_ui_world("dark")   # the title keeps the night violet (making a world is black, like the Survey)
	var t := TitleScreen.new()
	t.continue_pressed.connect(start_game)
	t.new_pressed.connect(_on_new_world)
	t.worlds_pressed.connect(open_worlds)
	t.settings_pressed.connect(func(): open_panel(SettingsScreen.new()))
	t.addons_pressed.connect(open_addons)
	t.show_connect = phone != null and bool(phone.get("app")) and not phone.paired()
	t.connect_pressed.connect(func(): open_app_connect(false, false))
	screen = t
	ui.add_child(t)
	_warm_world.call_deferred()
	_cloud_sync_at_title.call_deferred()
	if not service_only(OS.get_cmdline_user_args()):
		music.make_way("motif_title")   # the title's chime first, then the menu theme
		music.play_menu()


## [CLOUD_SYNC] The title screen is where worlds sync by themselves: no world is open, so files can
## change underneath safely, and it is both "Polox just started" (take what another device sent) and
## "I just left a world" (send what I did). Questions wait on Settings > Cloud sync.
func _cloud_sync_at_title() -> void:
	if not CloudService.is_set_up() or not CloudService.automatic() or service_only(OS.get_cmdline_user_args()):
		return
	await get_tree().create_timer(0.5).timeout   # (the title draws first)
	if game != null or not is_inside_tree():
		return   # (a world was opened meanwhile: it syncs when it is left)
	var said := CloudService.summary_text(CloudService.sync_all(self))
	if said != "":
		show_toast(said)


## host.bat, ping.bat, phone_doctor.bat and the build id: no game here, so no menu theme either.
static func service_only(args: PackedStringArray) -> bool:
	return "--host" in args or "--ping" in args or "--doctor" in args or "--write-build-id" in args


## The music that's on now: the world's, or the menu's.
func music_now() -> Node:
	return game.music if game and is_instance_valid(game) and game.get("music") else music


## Settings > Music changed a theme: what's on now follows it.
func refresh_music() -> void:
	if game and is_instance_valid(game) and game.has_method("refresh_music"):
		game.refresh_music()
	elif screen is TitleScreen:
		music.play_menu()


## Title > Add-ons.
func open_addons() -> Control:
	var p := AddonsPanel.new()
	p.main = self
	return open_panel(p)


## A new world is a new slot; the one you were playing keeps its own.
func _on_new_world() -> void:
	show_onboarding()


## The Worlds screen (save slots). Loading another slot switches worlds.
func open_worlds() -> void:
	var m := SaveMenu.new()
	m.load_requested.connect(play_slot)
	m.new_requested.connect(func(blank: bool, world_name: String):
		if blank:
			create_blank_world(world_name)
		else:
			show_onboarding())
	open_panel(m)


## Switches to a slot and starts playing it (saving the current one first).
func play_slot(id: String) -> void:
	if game:
		flush_all()
	_close_all_panels()
	if not Slots.exists(id):
		show_toast("That world isn't there any more.")
		return
	SaveManager.set_slot(id)
	GameState.reload_settings()
	start_game()


func create_blank_world(world_name: String) -> void:
	_close_all_panels()
	SaveManager.new_slot(world_name)
	StarterContent.create_blank(world_name, GameState.player_name())
	GameState.settings["onboarded"] = true
	GameState.save_settings()
	start_game()
	show_toast("An empty world. Press Build to shape it, or Menu > New friend.")


func show_onboarding() -> void:
	if _creating_world:
		return
	_creating_world = true
	if game:
		flush_all()
	_close_all_panels()
	_end_game()
	_clear_screen()
	music.silence()   # the Survey plays its own song (its theme) or hum
	set_ui_world("survey")
	# The home creation sequence is the first screen, before names or friends.
	var mapper := preload("res://scripts/home/home_mapper.gd").new()
	mapper.name = "NewWorldHomeMapper"
	add_child(mapper)
	await mapper.run(self)
	mapper.queue_free()
	_creating_world = false
	var o := Onboarding.new()
	o.cancelled.connect(show_title)
	o.finished.connect(_on_onboarded)
	screen = o
	ui.add_child(o)


func _on_onboarded(choices: Dictionary) -> void:
	var friend_id := create_world_from(choices)
	GameState.load_world()
	GameState.world["last_room"] = preload("res://scripts/world/light_home.gd").ensure_entry()
	GameState.save_world()
	start_game()
	# Let the house reveal finish before opening another editor over it.
	await get_tree().process_frame
	var reveal_end := Time.get_ticks_msec() + REVEAL_WAIT_MS   # (a reveal takes seconds; never wait for good)
	while is_instance_valid(game) and game.dark.busy and Time.get_ticks_msec() < reveal_end:
		await get_tree().process_frame
	if game and bool(choices.get("draw_own", false)):
		open_panel(preload("res://scripts/world/world_menu.gd").creator(friend_id))


## Builds a fresh world (its own slot) from onboarding choices. Returns the friend's id.
func create_world_from(choices: Dictionary) -> String:
	if game:
		flush_all()
	SaveManager.new_slot(str(choices.get("world_name", "")))
	StarterContent.create_world(str(choices.get("world_name", "")), str(choices.get("player_name", "")), {"life_context": str(choices.get("life", ""))}, str(choices.get("look", "cozy")))
	var id := StarterContent.create_mochi(str(choices.get("friend_name", "Mochi")), Color(str(choices.get("color", "#c9b6ff"))))
	var c := SaveManager.load_character(id)
	c["personality"] = str(choices.get("personality", c.personality))
	c["speech_style"] = str(choices.get("speech_style", c.speech_style))
	SaveManager.save_character(c)
	if str(choices.get("dream", "")) != "":
		var d := {"id": "d1", "text": str(choices.dream), "status": "dreaming", "created": Time.get_datetime_string_from_system()}
		SaveManager.save_dreams({"version": 1, "dreams": [d]})
	GameState.settings["onboarded"] = true
	GameState.settings["whats_new_seen"] = preload("res://scripts/ui/whats_new_panel.gd").VERSION  # new players get onboarding instead
	GameState.save_settings()
	return id


## "Where was I?" (only for a world you've played before).
func show_recap(last_played: String) -> Control:
	var r := RecapCard.build_recap(last_played)
	if r.is_empty() or (r.lines as Array).size() < 2:
		return null
	var card := RecapCard.new()
	card.lines = r.lines
	card.friend_id = str(r.friend)
	card.talk_requested.connect(func(id):
		if game:
			game.approach_character(id))
	ui.add_child(card)
	return card


# --- Phone Link ------------------------------------------------------------------------

## Phone build: not paired yet -> show how; paired -> pull from the PC first.
func _phone_startup() -> void:
	if phone.app:
		await _app_startup()
		return
	await phone.check_address()
	var warning: String = phone.startup_warning()
	if warning != "":
		show_toast("⚠ " + warning)
	if not phone.paired():
		if OS.has_feature("web") and phone.has_launcher:
			phone.open_pairing_page()   # the launcher asks for the PIN, then shows the worlds
			return
		var c := ConfirmPanel.new()
		open_panel(c)
		c.ask("Pair this phone", "This phone isn't paired with your PC yet. Open the PC's address and type the PIN shown on the PC.", "Pair now", "Later")
		c.answered.connect(func(ok):
			if ok:
				phone.open_pairing_page())
		return
	show_toast("Syncing with your PC...")
	await phone.startup_sync()
	# Picked in the launcher: open that world straight away.
	if game == null and phone.slot != "" and Slots.exists(phone.slot):
		SaveManager.set_slot(phone.slot)
		if SaveManager.has_world():
			start_game()
	if game == null:
		show_title()
	show_toast("📱 " + str(phone.client.detail))


## Polox for Android: plays from its own copy straight away; finds the PC and syncs when it can.
func _app_startup() -> void:
	if not phone.paired():
		open_app_connect(true)
		return
	show_toast("Looking for your PC...")
	var r: Dictionary = await phone.connect_pc()
	if not r.ok:
		show_toast("📱 PC not found: playing your own copy. It syncs by itself when the PC is back.")
		return
	await phone.startup_sync()
	if game == null:
		show_title()
	show_toast("📱 %s  •  %s" % [phone.connection_text(), str(phone.client.detail)])
	if not phone.update_offer.is_empty():
		offer_app_update()


## The app's "Connect to your PC" screen (first start, Settings, or "Pair again").
func open_app_connect(first: bool = false, pair_again: bool = false) -> Control:
	var p := AppConnectPanel.new()
	open_panel(p)
	p.setup_connect(self, phone, first, pair_again)
	p.connected.connect(func():
		show_toast("Syncing with your PC...")
		await phone.startup_sync()
		if game == null:
			show_title()
		show_toast("📱 %s  •  %s" % [phone.connection_text(), str(phone.client.detail)])
		if not phone.update_offer.is_empty():
			offer_app_update())
	return p


## The PC has a newer Polox for Android: Android installs it over this one (same key: the worlds stay).
func offer_app_update() -> void:
	var o: Dictionary = phone.update_offer
	var c := ConfirmPanel.new()
	open_panel(c)
	c.ask("Update Polox", "Your PC has Polox %s for this phone (this one is %s). Update now? The download opens in your browser and Android asks to install it; your worlds stay." % [str(o.version), str(ProjectSettings.get_setting("application/config/version", ""))], "Update", "Later")
	c.answered.connect(func(yes):
		if yes:
			phone.open_update())


## Applies the saved Phone Link settings (mode, ports, limits) without starting it.
func configure_phone_link(resolve_mode: bool = true) -> void:
	var cfg: Dictionary = GameState.settings.get("phone_link", {})
	if PhoneServer.upgrade_settings(cfg):
		GameState.settings["phone_link"] = cfg
		GameState.save_settings()
	phone_link.setup(SaveManager.root)
	phone_link.api.on_world_changed = _on_phone_changed_world
	phone_link.auto_off_hours = float(cfg.get("auto_off_hours", 6))
	phone_link.pairing.max_devices = maxi(1, int(cfg.get("max_devices", 4)))
	phone_link.pairing.always_ask = bool(cfg.get("always_ask", false))
	phone_link.chosen_mode = str(cfg.get("mode", "auto")) if str(cfg.get("mode", "auto")) in PhoneServer.MODES else "auto"
	phone_link.mode = resolve_phone_mode(phone_link.chosen_mode) if resolve_mode or phone_link.chosen_mode != "auto" else PhoneServer.auto_mode(phone_link.ts_status)
	phone_link.serve_port = int(cfg.get("serve_port", PhoneServer.DEFAULT_SERVE_PORT))
	phone_link.tailscale_only = bool(cfg.get("tailscale_only", false))
	phone_link.require_login = bool(cfg.get("require_login", true))
	phone_link.keep_awake = bool(cfg.get("keep_awake", true))   # on by default: an asleep PC can't answer the phone
	phone_link.server_extras = bool(cfg.get("server_extras", false))
	phone_link.engine_choice = "bundled" if str(cfg.get("engine", "builtin")) == "bundled" else "builtin"
	phone_link.port = int(cfg.get("port", PhoneServer.DEFAULT_PORT))


## "auto": Same Wi-Fi plus Tailscale Serve when this PC can do it (see PhoneServer.auto_mode).
func resolve_phone_mode(wanted: String) -> String:
	if wanted in PhoneServer.MODES:
		return wanted
	return PhoneServer.auto_mode(phone_link.ts.status() if phone_link.ts.installed() else {})


## A new phone reached Phone Link: a banner over whatever is on screen. A moment
## later we know whether it's a paired phone (it used its key) or one that needs the PIN.
func _on_phone_reached(contact: Dictionary) -> void:
	if host_mode:
		return
	var who := str(contact.get("via", "")).get_slice(" ", 1) if str(contact.get("via", "")) != "" else str(contact.get("ip", ""))
	await get_tree().create_timer(1.5).timeout
	if not phone_link.running:
		return
	var known: String = str(phone_link.api.authed.get(who, ""))
	if known != "":
		show_phone_banner("📱 Phone connected: %s" % known, "")
	elif phone_link.pairing.paused:
		show_phone_banner("📱 A phone is trying to pair, but pairing is paused", "Click to open Phone Link and unlock it")
	else:
		show_phone_banner("📱 Phone connecting: PIN %s" % Pairing.grouped(str(phone_link.pairing.code)))


func _on_phone_paired(device_name: String) -> void:
	var phrase := str(phone_link.last_pair_phrase)
	if host_mode:
		print("[host] Paired: %s%s" % [device_name, ("  (check words: %s)" % phrase) if phrase != "" else "  (an older phone: no check words)"])
		return
	if phrase != "":
		show_phone_banner("📱 Paired: %s" % device_name, "Check these words match your phone: " + phrase)
	else:
		show_phone_banner("📱 Paired: %s" % device_name)


func show_phone_banner(text: String, hint: String = "Click to open Phone Link") -> void:
	if phone_banner == null:
		phone_banner = PhoneBanner.new()
		phone_banner.on_open = open_phone_link_settings
		_toast_root.add_child(phone_banner)
	phone_banner.show_text(text, hint)


func open_phone_link_settings() -> void:
	var s := SettingsScreen.new()
	s.main = self
	s.start_on = "Phone Link"
	open_panel(s)


func open_cloud_sync_settings() -> void:
	var s := SettingsScreen.new()
	s.main = self
	s.start_on = "Cloud sync"
	open_panel(s)


## Switches the server on with the saved settings. Returns "" or an error.
func start_phone_link() -> String:
	configure_phone_link()
	var err: String = phone_link.start_on_safe_port(phone_link.port)
	var cfg: Dictionary = GameState.settings.get("phone_link", {})
	if err == "" and int(cfg.get("port", 0)) != int(phone_link.port):
		cfg["port"] = int(phone_link.port)   # remembered, so the phone's address stays the same next time
		GameState.settings["phone_link"] = cfg
		GameState.save_settings()
	return err


## The phone changed files in a world: if that's the one being played, load
## it again so the PC doesn't write its older copy back over the phone's edits.
func _on_phone_changed_world(slot: String, paths: Array = []) -> void:
	if game == null or slot != SaveManager.slot_id:
		return
	if not paths.is_empty() and not SyncFiles.needs_reload(paths):
		return   # only the cover picture, playtime or a chat log: nothing on screen changes
	reload_world_from_disk()
	var now := Time.get_ticks_msec() / 1000.0
	if now - _phone_toast_at > 60.0:
		_phone_toast_at = now
		show_toast("📱 Updated with changes from your phone")


## Another device's changes arrived (a phone sync pulled the PC's, or the phone pushed to this PC): the
## world reloads so the game shows and keeps them. Never under your hands: while you're talking, in a
## battle, crossing between places, building or in a moment, it waits until you're done.
func reload_world_from_disk() -> void:
	if game == null:
		return
	if _busy_for_reload():
		_reload_pending = true
		return
	_reload_pending = false
	_reload_after_build = false
	var room := GameState.current_room_id
	GameState.load_world(true)
	game.keep_disk_positions = true
	game.load_room(room if SaveManager.room_exists(room) else GameState.current_room_id)
	game.keep_disk_positions = false


func _busy_for_reload() -> bool:
	if game == null:
		return false
	if (game.build and game.build.active) or game._transitioning or (game.dark and game.dark.busy):
		return true
	if game.battles and game.battles.get("screen") != null:
		return true
	if game.dialogue and game.dialogue.visible:
		return true
	if game.decor and is_instance_valid(game.decor) and game.decor.is_visible_in_tree():
		return true
	if game.platform and bool(game.platform.get("active")):
		return true
	for c in toast_layer().get_children():
		if c.get_script() == Moment:
			return true
	return false


## A server window (host, ping) redraws only when something on it changes, at most 30 times a second.
func _quiet_server_window() -> void:
	OS.low_processor_usage_mode = true
	Graphics.server_window = true
	Graphics.apply(get_viewport())


## host.bat: no game, just the server, in a small window that shows the
## address, the PIN and the phone (the console gets the same lines).
func _start_host_mode() -> void:
	host_mode = true
	_quiet_server_window()
	get_window().title = "Polox Phone Link"
	if DisplayServer.get_name() != "headless":
		get_window().min_size = Vector2i(420, 560)
		get_window().size = Vector2i(560, 760)
		get_window().content_scale_size = Vector2i(560, 760)   # 1:1 text in the small window
	var err := start_phone_link()
	if err != "":
		print("[host] ", err)
		get_tree().quit(1)
		return
	phone_link.auto_off_hours = 0.0  # a host is meant to stay up
	print("[host] Polox Phone Link is on: %s, listening on %s." % [phone_link.mode_text(), phone_link.bind_text()])
	for u in phone_link.urls():
		print("[host]   ", u)
	print("[host] Check the connection with <address>/hello. Doctor: phone_doctor.bat")
	phone_link.phone_reached.connect(func(c): print("[host] Phone connected: %s" % (str(c.get("via", "")) if str(c.get("via", "")) != "" else str(c.get("ip", "")))))
	_clear_screen()
	host_window = HostWindow.new()
	ui.add_child(host_window)
	host_window.setup(phone_link)


## ping.bat: only Polox Ping (a tiny test server: no game, no pairing, no
## files) in a window with every address to try, big, and what reached the PC.
func _start_ping_mode(bind: String = "0.0.0.0") -> void:
	ping_mode = true
	_quiet_server_window()
	get_window().title = "Polox Ping"
	if DisplayServer.get_name() != "headless":
		get_window().min_size = Vector2i(460, 600)
		get_window().size = Vector2i(660, 880)
		get_window().content_scale_size = Vector2i(660, 880)
	var ping: Node = PingServer.new()
	ping.name = "PoloxPing"
	add_child(ping)
	var err: String = ping.start(SaveManager.root, PingServer.PORTS, bind)
	if err != "":
		print("[ping] ", err)
		get_tree().quit(1)
		return
	_clear_screen()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.BG, ThemeBuilder.BG, 0, 0, 18))
	ui.add_child(panel)
	var v := UiKit.vbox(8)
	panel.add_child(v)
	v.add_child(UiKit.label("Polox Ping", 32, ThemeBuilder.YELLOW))
	var view: Control = preload("res://scripts/ui/ping_view.gd").new()
	v.add_child(view)
	view.setup(ping)
	if DisplayServer.get_name() != "headless":
		DisplayServer.screen_set_keep_on(true)   # an asleep PC can't answer the phone


## phone_doctor.bat: start Phone Link the way the settings say (or check the
## copy that's already running), run every check, print them, save the report.
func _run_doctor_cli() -> void:
	var Doctor := preload("res://scripts/phone/phone_doctor.gd")
	configure_phone_link()
	print("[doctor] Polox Phone Link Doctor: %s, port %d" % [str(PhoneServer.MODE_LABELS.get(phone_link.mode, phone_link.mode)), phone_link.port])
	var err: String = phone_link.start(phone_link.port)
	var mine := err == ""
	if not mine:
		print("[doctor] Phone Link didn't start here: %s" % err)
	await get_tree().process_frame
	var snap: Dictionary = Doctor.snapshot(phone_link)
	if not mine and int(Doctor.fetch("http://127.0.0.1:%d/hello.json" % phone_link.port).code) == 200:
		print("[doctor] Polox is already running with Phone Link on: checking that copy.")
		snap.running = true
		snap.bind = "?"
		var log_path := SaveManager.root.path_join("phone").path_join("phone_link.log")
		snap.last_contact = Doctor.last_contact_from_log(log_path)
		snap.recent = Doctor.log_tail(log_path, 50)
	var results: Array = Doctor.run(snap)
	for r in results:
		print("[doctor] %s %s: %s" % [Doctor.ICONS.get(r.status, "?"), r.title, r.detail])
		if str(r.fix) != "" and str(r.status) in ["fail", "warn"]:
			print("[doctor]     fix: %s" % r.fix)
	var path := SaveManager.root.path_join("phone").path_join("diagnostics.txt")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(Doctor.diagnostics(snap, results))
		f.close()
	var fails := results.filter(func(r): return r.status == "fail").size()
	var warns := results.filter(func(r): return r.status == "warn").size()
	var verdict := "All green" if fails + warns == 0 else ("No problems (%d note(s))" % warns if fails == 0 else "%d problem(s), %d note(s)" % [fails, warns])
	print("[doctor] %s. Report for pasting: %s" % [verdict, path])
	if mine:
		phone_link.stop()
	get_tree().quit(1 if fails > 0 else 0)


var _lamp_t := 0.0
var _detailed_was := false


func _process(delta: float) -> void:
	if _android_idle:
		_android_idle.update(self)
	if Graphics.PcDetail.available() and game:
		var cap := Graphics.frame_cap()
		var active := not Graphics.server_window and not Graphics.in_background and not get_tree().paused and (cap == 0 or cap >= 60) and RenderingServer.get_current_rendering_method() == "forward_plus"
		if Graphics.PcDetail.observe(delta * 1000.0, delta, active, Graphics.pc_tier()):
			_apply_performance()
		_lamp_t += delta
		if _lamp_t > 1.0:
			_lamp_t = 0.0
			_lamps_now()
	if (_reload_after_build or _reload_pending) and game and not _busy_for_reload():
		reload_world_from_disk()


## Quick start without onboarding (used by scripted checks): a new slot with
## the starter world + Mochi.
func begin_new_world() -> void:
	if game:
		flush_all()
	SaveManager.new_slot("My World")
	StarterContent.create_world()
	StarterContent.create_mochi()
	start_game()


func start_game() -> void:
	_close_all_panels()
	_end_game()
	if not SaveManager.has_world():
		show_title()
		show_toast("Pick a world first (Worlds), or begin a new one.")
		return
	# read_json already rescues .tmp/.bak copies; if the world still can't be
	# read, offer the snapshot timeline instead of starting on an empty world.
	if not JsonUtil.read_json(SaveManager.world_path(), null) is Dictionary:
		show_title()
		var v := preload("res://scripts/ui/verify_panel.gd").new()
		v.slot_id = SaveManager.slot_id
		open_panel(v)
		show_toast("This world's main file is damaged. Restore a snapshot to get it back.")
		return
	GameState.load_world()
	var last_played := str(Slots.meta(SaveManager.slot_id).get("last_played", ""))
	_clear_screen()
	music.silence()   # the world plays its own
	game = _game_world_script().new()
	game.setup(self)
	add_child(game)
	autosave.on_game_started()
	if GameState.current_room_id.begins_with("lw_"):
		if preload("res://scripts/world/light_home.gd").needs_survey():
			# Upgrading while saved in the old phone placeholder must offer creation
			# immediately, without requiring another round trip through the fountain.
			game.dark.go_light.call_deferred()
			return
		game.dark.first_look.call_deferred()
	var WhatsNew := preload("res://scripts/ui/whats_new_panel.gd")
	if WhatsNew.should_show() and not DebugCapture.wanted():
		var wn := WhatsNew.new()
		wn.main = self
		open_panel(wn)
	elif bool(GameState.settings.get("recap", true)):
		show_recap(last_played)


func _end_game() -> void:
	if game:
		autosave.on_game_ending()
		game.queue_free()
		game = null


func _close_all_panels() -> void:
	for p in panels.duplicate():
		if is_instance_valid(p):
			p.queue_free()
	panels.clear()


# --- Panels & back stack -----------------------------------------------------------

func open_panel(p: Control) -> Control:
	if _android_idle:
		_android_idle.wake()
	if game:
		for key in ["controller", "platform"]:
			var owner: Variant = game.get(key)
			if owner is Node and owner.has_method("cancel_input"):
				owner.cancel_input()
	ui.add_child(p)
	panels.append(p)
	p.tree_exited.connect(func(): panels.erase(p))
	return p


## Closes the top-most panel. Returns true if something handled "back".
func go_back() -> bool:
	# [EASTER_EGG] Keep the fullscreen picture up for its full five seconds.
	if has_node("Secret"):
		return true
	# The Survey sits above panels on the toast layer, including during a cancellable lookup.
	var overlays := get_tree().get_nodes_in_group("survey_flow")
	overlays.reverse()
	for wizard in overlays:
		if is_instance_valid(wizard) and not wizard.is_queued_for_deletion() and wizard.is_visible_in_tree() and wizard.has_method("on_back"):
			wizard.on_back()
			return true
	if panels.is_empty() and is_instance_valid(screen) and not screen.is_queued_for_deletion() and screen.has_method("go_back"):
		screen.go_back()
		return true
	while not panels.is_empty():
		var top: Control = panels.back()
		if is_instance_valid(top) and top.is_inside_tree():
			if top.has_method("on_back"):
				top.on_back()
			else:
				top.queue_free()
			return true
		panels.pop_back()
	if game and game.has_method("on_back"):
		return game.on_back()
	return false


func _notification(what: int) -> void:
	if _android_idle and what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED,
			NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_GO_BACK_REQUEST]:
		_android_idle.wake()
	# Closing the window (or the app going to the background on a phone): make sure the last build edits
	# and positions hit the disk. Losing focus (the notification shade, another window) saves the files only.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and game and game.has_method("flush_all"):
		game.flush_all()
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN] and not OS.has_feature("mobile") and not OS.has_feature("web"):
		Graphics.in_background = what == NOTIFICATION_APPLICATION_FOCUS_OUT   # a PC window behind others: 30 fps
		Graphics.apply(get_viewport())
	if OS.has_feature("android") and what == NOTIFICATION_APPLICATION_PAUSED:
		Graphics.in_background = true
		Graphics.apply(get_viewport())
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED]:
		flush_all(what == NOTIFICATION_WM_CLOSE_REQUEST)
	# [CLOUD_SYNC] A PC's window closing with a world still open: send what changed, so the phone can
	# pick it up while the PC is off. Send only (nothing here is touched while closing), after the
	# flush above so the files are current. A phone going to the background doesn't do this: reaching
	# a cloud document can take seconds, and the title screen's sync covers it.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and CloudService.is_set_up() and CloudService.automatic() and not service_only(OS.get_cmdline_user_args()):
		CloudService.send_changes(self)
	if crash_log:
		if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_RESUMED:
			crash_log.on_background(what == NOTIFICATION_APPLICATION_PAUSED)
		elif what == NOTIFICATION_WM_CLOSE_REQUEST:
			crash_log.on_clean_exit()
	if what == NOTIFICATION_OS_MEMORY_WARNING:
		MemoryRelief.release()   # the phone is short of memory: let go of what's only kept to be quick
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android's back gesture: the same as right-click or Q; on the title screen with nothing open it leaves.
		if not go_back() and game == null:
			get_tree().quit()
	if phone and what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		phone.on_lifecycle(what == NOTIFICATION_APPLICATION_RESUMED)   # the app syncs when it leaves and comes back
	if what == NOTIFICATION_APPLICATION_RESUMED:
		Graphics.in_background = false
		# Android makes a new drawing surface after the app was in the background, and a surface's
		# frame-rate request goes with it: ask again.
		Graphics.apply(get_viewport())
		MissYou.cancel_all()
	# Leaving: a phone going to the background, a PC's window closing. Notes for a day, three and seven.
	if what == NOTIFICATION_APPLICATION_PAUSED and OS.has_feature("android"):
		MissYou.on_leave()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST and not OS.has_feature("android") and not OS.has_feature("web"):
		MissYou.on_leave()


func flush_all(closing: bool = false) -> void:
	if game and game.has_method("flush_all"):
		game.flush_all()
	if autosave:
		autosave.on_flush(closing)


func _exit_tree() -> void:
	if crash_log:
		crash_log.on_clean_exit()   # leaving on purpose (Quit, or the window closed)
	# Quitting while the world still loads (or finished loading without being claimed) in the background
	# (_warm_world): claim it so the threaded loader releases its RefCounted task state cleanly at exit.
	if _world_load_started and ResourceLoader.load_threaded_get_status(GAME_WORLD_PATH) in [
		ResourceLoader.THREAD_LOAD_IN_PROGRESS,
		ResourceLoader.THREAD_LOAD_LOADED,
	]:
		ResourceLoader.load_threaded_get(GAME_WORLD_PATH)
	_world_load_started = false


## [GLASS_UI] Every switch and tick box in the game, wherever it's made, clicks as it flips (on and off
## sound different), like a real switch; Settings > Audio > Button clicks turns this off with the rest.
## What every control gets as it joins the tree: a switch clicks when it flips, and anything you press,
## type in or drag is big enough to hit (ui_kit.gd give_room: 44 px with a mouse, 48 under a finger).
## Once now and once after the frame, for a screen that sizes a control after adding it.
func _tactile(n: Node) -> void:
	if n is CheckBox or n is CheckButton:
		var b := n as BaseButton
		if not b.toggled.is_connected(_flipped):
			b.toggled.connect(_flipped.bind(b))
	if n is Control:
		UiKit.give_room(n)
		_give_room_later.call_deferred(n.get_instance_id())


func _give_room_later(id: int) -> void:
	var n := instance_from_id(id)
	if n is Control and (n as Node).is_inside_tree():
		UiKit.give_room(n as Control)


func _flipped(on: bool, b: BaseButton) -> void:
	if bool(GameState.settings.get("ui_sounds", true)) and b.is_inside_tree() and b.is_visible_in_tree():
		preload("res://scripts/core/synth.gd").play(get_tree().root, "switch_on" if on else "switch_off", 0.35)


func _input(event: InputEvent) -> void:
	if _android_idle:
		_android_idle.wake()
	# Right-click is "back" everywhere, even over UI.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if go_back():
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back") and not InputSetup.typing(get_viewport()):
		if go_back():
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F5 and game and autosave:
		autosave.save_now(true)  # one-key quick-save
		get_viewport().set_input_as_handled()


# --- Toasts --------------------------------------------------------------------

## The surfaces follow the world you're in (night violet, tea-brown in your real home, ink in the Deep).
func set_ui_world(w: String) -> void:
	if w == ThemeBuilder.world or ui_theme == null:
		return
	ThemeBuilder.set_world(w, ui_theme)
	if game and game.get("hud") and is_instance_valid(game.hud):
		game.hud.apply_layout(game.hud.phone_mode, game.hud.left_handed)


## The layer toasts live on (things flying to your bag draw there too).
func fly_layer() -> Control:
	return _toast_root


func show_toast(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ThemeBuilder.box(Color(ThemeBuilder.PANEL, 0.95), ThemeBuilder.YELLOW, 2, 12, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	p.add_child(l)
	_toast_box.add_child(p)
	_toast_box.position.x = (get_viewport().get_visible_rect().size.x - _toast_box.size.x) / 2.0
	preload("res://scripts/ui/anim_fx.gd").glide_in(p)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
	tw.tween_callback(_center_toasts)
	_center_toasts.call_deferred()


func _center_toasts() -> void:
	_toast_box.reset_size()
	_toast_box.position.x = (get_viewport().get_visible_rect().size.x - _toast_box.size.x) / 2.0
