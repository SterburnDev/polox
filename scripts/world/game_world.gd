extends Node3D
## The playable world: builds the current room, places the player and the
## residents, and wires together the pieces that bring it to life (input,
## talking, building, daylight, life, music).

const RoomView := preload("res://scripts/world/room_view.gd")
const CameraRig := preload("res://scripts/world/camera_rig.gd")
const Actor := preload("res://scripts/characters/actor.gd")
const TalkController := preload("res://scripts/world/talk_controller.gd")
const PlayerController := preload("res://scripts/world/player_controller.gd")
const DialogueBox := preload("res://scripts/ui/dialogue_box.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const WorldMenu := preload("res://scripts/world/world_menu.gd")
const BuildMode := preload("res://scripts/builder/build_mode.gd")
const Daylight := preload("res://scripts/world/daylight.gd")
const LifeDirector := preload("res://scripts/characters/life_director.gd")
const MusicPlayer := preload("res://scripts/world/music_player.gd")
const PhotoMode := preload("res://scripts/world/photo_mode.gd")
const SeasonalDecor := preload("res://scripts/variety/seasonal_decor.gd")
const WeatherFx := preload("res://scripts/world/weather_fx.gd")
const Seasons := preload("res://scripts/world/seasons.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const Items := preload("res://scripts/items/items.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const Synth := preload("res://scripts/core/synth.gd")
const PlatformMode := preload("res://scripts/platform/platform_mode.gd")
const AnimBake := preload("res://scripts/characters/anim_bake.gd")
const Places := preload("res://scripts/world/places.gd")
const PlaceBackdrop := preload("res://scripts/world/place_backdrop.gd")
const Moment := preload("res://scripts/ui/moment.gd")
const DarkDirector := preload("res://scripts/world/dark_director.gd")
const DarkLook := preload("res://scripts/world/dark_look.gd")
const BattleDirector := preload("res://scripts/battle/battle_director.gd")
const Story := preload("res://scripts/variety/story.gd")
const Realms := preload("res://scripts/world/realms.gd")
const Ambience := preload("res://scripts/world/ambience.gd")
const LightLife := preload("res://scripts/world/light_life.gd")
const StreetLife := preload("res://scripts/world/street_life.gd")
const AnimFx := preload("res://scripts/ui/anim_fx.gd")

var main: Node
var room: Node3D             # room_view.gd
var backdrop: Node3D         # place_backdrop.gd: ground, the joins, background layers
var dark: Node               # dark_director.gd: fountains, the way home and the Deep
var dark_look: Node3D        # dark_look.gd: glowing outlines and strange props in a Deep place
var battles: Node            # battle_director.gd: encounters, starting battles, the Battle Log
var cam: Node3D              # camera_rig.gd
var player: Node3D           # actor.gd
var actors: Dictionary = {}  # character id -> actor
var hud: Control
var touch_stick: Control     # touch_stick.gd: the phone's thumb stick (under the HUD)
var dialogue: Control
var talk: Node               # talk_controller.gd
var controller: Node         # player_controller.gd
var build: Node              # build_mode.gd
var platform: Node           # platform_mode.gd (run and jump; started by a Platform Pillar)
var variety: Node            # variety_director.gd (Daily Moments, routines, While You Were Away, quests)
var daylight: Node
var life: Node
var music: Node
var ambience: Node          # ambience.gd: the Light World's own sounds (room tone, birds, crickets)
var light_life: Node        # light_life.gd: using furniture (the stairs, small everyday moments)
var decor: Control          # decor_editor.gd: Edit my room (the Light World's limited building)
var street_life: Node3D     # street_life.gd: a passing car, birds over your street
var signatures: Node        # signatures.gd: the crafted moments (your street, the fountain, home after a battle)
var _look_t := 0.0
var weather: Node3D          # weather_fx.gd
var weather_hold := ""       # a hangout's sky (Stargazing) while it lasts
var env: Environment
var sun: DirectionalLight3D
var _actors_root: Node3D
var _fade: ColorRect
var _transitioning := false
## A reload of files that came from the other device (main.reload_world_from_disk): where friends stand is
## taken from those files, not written over them (that changed them again, and the sync sent them back).
var keep_disk_positions := false
var _sky: Sky                              # (apply_backdrop: one sky, reused)
var _sky_gradient: ProceduralSkyMaterial
var _sky_picture: PanoramaSkyMaterial
var _aura_token := 0
var _light_token := 0
var _face_token := 0
var light_flashing := false      # an item is tinting the room's light right now


func setup(main_node: Node) -> void:
	main = main_node


func _ready() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b9a8ff")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	preload("res://scripts/core/graphics.gd").apply_env(env)   # occlusion, glow by graphics quality
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("#fff1d6")
	preload("res://scripts/core/graphics.gd").apply_to_world(sun)   # shadows by graphics quality
	add_child(sun)
	room = RoomView.new()
	add_child(room)
	backdrop = PlaceBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	dark_look = DarkLook.new()
	dark_look.name = "DarkLook"
	add_child(dark_look)
	dark = DarkDirector.new()
	dark.name = "Dark"
	add_child(dark)
	dark.setup(self)
	battles = BattleDirector.new()
	battles.name = "Battles"
	add_child(battles)
	battles.setup(self)
	_actors_root = Node3D.new()
	add_child(_actors_root)
	cam = CameraRig.new()
	add_child(cam)
	cam.apply_preset(str(GameState.settings.get("camera_preset", "cozy")))
	# The phone's thumb stick goes under the HUD, so every button and panel gets its touches first.
	touch_stick = preload("res://scripts/ui/touch_stick.gd").new()
	touch_stick.setup(self)
	main.ui.add_child(touch_stick)
	hud = Hud.new()
	main.ui.add_child(hud)
	hud.menu_pressed.connect(open_menu)
	hud.camera_rotate.connect(func(d): cam.rotate_step(d))
	hud.camera_zoom.connect(func(d): cam.zoom(d))
	hud.build_pressed.connect(func(): build.enter())
	hud.bag_pressed.connect(open_bag)
	hud.world_pressed.connect(open_world_sheet)
	hud.outside_pressed.connect(go_outside)
	hud.friends_pressed.connect(func():
		if main.panels.is_empty():
			main.open_panel(WorldMenu.friends(self)))
	if main.get("phone_link"):
		main.phone_link.state_changed.connect(_refresh_phone_indicator)
		_refresh_phone_indicator()
	SaveManager.saved.connect(func(_p):
		if is_instance_valid(hud):
			hud.note_saved())
	if main.get("autosave"):
		main.autosave.saved.connect(hud.note_snapshot)
	if main.get("phone"):
		hud.sync_pressed.connect(func(): main.phone.sync_now())
		main.phone.sync_state_changed.connect(hud.set_sync)
		hud.set_sync(main.phone.client.state, main.phone.client.detail)
	hud.photo_pressed.connect(take_photo)
	dialogue = DialogueBox.new()
	main.ui.add_child(dialogue)
	talk = TalkController.new()
	add_child(talk)
	talk.setup(self, dialogue)
	controller = PlayerController.new()
	add_child(controller)
	controller.setup(self)
	build = BuildMode.new()
	add_child(build)
	build.setup(self)
	platform = PlatformMode.new()
	platform.name = "Platform"
	add_child(platform)
	platform.setup(self)
	variety = load("res://scripts/variety/variety_director.gd").new()
	variety.name = "Variety"
	add_child(variety)
	variety.setup(self)
	daylight = Daylight.new()
	add_child(daylight)
	life = LifeDirector.new()
	add_child(life)
	music = MusicPlayer.new()
	add_child(music)
	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	light_life = LightLife.new()
	light_life.name = "LightLife"
	add_child(light_life)
	light_life.setup(self)
	street_life = StreetLife.new()
	street_life.name = "StreetLife"
	add_child(street_life)
	signatures = load("res://scripts/world/signatures.gd").new()
	signatures.name = "Signatures"
	signatures.world = self
	add_child(signatures)
	decor = load("res://scripts/world/decor_editor.gd").new()
	decor.name = "Decor"
	main.ui.add_child(decor)
	decor.setup(self)
	weather = WeatherFx.new()
	add_child(weather)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.01, 0.05, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.ui.add_child(_fade)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	GameState.settings_changed.connect(_on_settings_changed)
	GameState.character_changed.connect(refresh_character)
	GameState.inventory_changed.connect(refresh_gear)
	load_room(GameState.current_room_id)
	daylight.setup(self)
	life.setup(self)


func _on_settings_changed() -> void:
	cam.apply_preset(str(GameState.settings.get("camera_preset", "cozy")))
	var left := str(GameState.settings.get("hand", "right")) == "left"
	var phone := preload("res://scripts/ui/touch_gestures.gd").phone_layout()
	if hud.phone_mode != phone or hud.left_handed != left:
		hud.apply_layout(phone, left)


func _exit_tree() -> void:
	if platform:
		platform.shutdown()   # never saved mid-air: next time you're back at the checkpoint, walking
	save_positions()
	flush_room()
	if build and build.active:
		build.exit()
	for n in [hud, touch_stick, dialogue, _fade, decor]:
		if is_instance_valid(n):
			n.queue_free()


func _process(delta: float) -> void:
	room.update_walls(cam.camera.global_position)
	if player:
		room.update_edge_walls(cam.camera.global_position, player.global_position)
	# Friends nearby turn to look at you.
	_look_t += delta
	if _look_t >= 0.4 and player:
		_look_t = 0.0
		look_at_player()
	if room.layers:
		room.layers.update_fade([player] + actors.values(), cam.camera, delta)


# --- Rooms ---------------------------------------------------------------------------

func load_room(id: String, from_room: String = "", start_cell: Vector2i = Vector2i(-1, -1)) -> void:
	if not SaveManager.room_exists(id) and id.begins_with("lw_"):
		id = preload("res://scripts/world/light_home.gd").recover_entry()
	if not SaveManager.room_exists(id):
		id = str(GameState.world.get("start_room", "home"))
	if not keep_disk_positions:
		save_positions()
	var was := GameState.current_room_id
	GameState.current_room_id = id
	var data := SaveManager.load_room(id)
	PlayerLook.apply_room(data, false)
	if str(GameState.world.get("last_room", "")) != id:
		GameState.world["last_room"] = id   # "Where was I?" and resuming here next time
		GameState.save_world()
	preload("res://scripts/world/light_home.gd").sanitize(data)
	room.pop_new = id == was   # the same place again (a change was made): new pieces pop in
	room.build(data)
	room.pop_new = false
	if main.has_method("set_ui_world"):
		main.set_ui_world("light" if Realms.is_light(data) else ("deep" if str(data.get("side", "")) == "dark" else "dark"))
	backdrop.build(data, neighbours_of(data))
	dark_look.build(room, data)
	env.background_color = Color.from_string(str(data.get("sky", {}).get("color", "#120e24")), Color("#120e24"))
	apply_backdrop(data)
	preload("res://scripts/core/graphics.gd").apply_env(env, {}, open_sky(data), not Realms.is_light(data) and str(data.get("kind", "")) == "outdoor")
	preload("res://scripts/core/graphics.gd").apply_to_world(sun)
	for c in _actors_root.get_children():
		c.queue_free()
	actors.clear()
	player = Actor.new()
	player.setup("player", GameState.player_name(), PlayerLook.texture(PlayerLook.current(), "neutral"), true)
	_actors_root.add_child(player)
	load_player_anims()
	player.arrived.connect(controller.on_player_arrived.bind(player))
	var start: Vector2i = room.spawn_cell()
	var door: Dictionary = room.door_to(from_room) if from_room != "" else {}
	if not door.is_empty():
		start = room.nav.best_neighbor(room.obj_cell(door), Vector2i(floori(room.w / 2.0), floori(room.d / 2.0)))
		if start.x < 0:  # the door is walled in: land on the nearest free cell instead
			start = room.nav.nearest_walkable(room.obj_cell(door))
	if start_cell.x >= 0:   # across a joined edge: the matching spot of this place's edge
		start = start_cell if room.nav.walkable(start_cell) else room.nav.nearest_walkable(start_cell)
	player.position = room.cell_center(start)
	for c in GameState.characters_in_room(id):
		spawn_character(c)
	refresh_gear()
	cam.target = player
	cam.snap_to_target()
	hud.set_room(room_title(data))
	hud.outside_button.visible = Realms.is_light(data) and str(data.get("kind", "")) == "indoor" and preload("res://scripts/world/light_home.gd").street_entry() != ""
	var verb := "Tap" if preload("res://scripts/ui/touch_gestures.gd").phone_layout() else "Click"
	hud.set_hint(("%s the floor to walk • %s a friend to talk" % [verb, verb.to_lower()]) if not actors.is_empty() else "%s the floor to walk" % verb)
	if Realms.is_light(data):
		hud.set_hint("%s to walk • %s yourself for actions" % [verb, verb.to_lower()])
	if decor and decor.active and was != id:
		decor.close()   # (a change you just made reloads this place: the editor stays open)
	if daylight.world:
		daylight.apply()
	music.play_for_room(data)
	ambience.play_for(data, Daylight.is_night(daylight.current_hour() if daylight.world else 12.0))
	refresh_weather(true)
	if platform:
		platform.on_room_loaded(id, from_room)
	if variety:
		variety.on_room_loaded(id)
	if light_life:
		light_life.on_room_loaded(data)
	if street_life:
		street_life.follow = player
		street_life.on_room_loaded(data)
	if signatures and id.begins_with("lw_hood_"):
		signatures.first_street.call_deferred(data)
	_discover(id, data)


## Friends standing near you (not walking, not mid-chat) turn to face you.
func look_at_player() -> void:
	for id in actors:
		var a: Node3D = actors[id]
		if not is_instance_valid(a) or a.is_moving() or talk.talking_to == str(id):
			continue
		var to: Vector3 = player.position - a.position
		if to.length() < 3.5:
			a._face_screen_dir(to)


## The place again, after a change made here (Tell Polox, an answer): pieces that are new pop in.
func reload_here() -> void:
	var cell: Vector2i = player.cell() if player else Vector2i(-1, -1)
	load_room(GameState.current_room_id, "", cell)


## The first look at your real home: it draws itself in, room by room, out from your room (walls rise,
## floors spread, the furniture pops in). A tap skips it; Reduce motion makes it a short fade.
func reveal_home() -> void:
	if room.edge_walls == null or player == null:
		return
	var m: Control = Moment.begin(main)
	var reduced := Moment.reduced()
	var center := Vector2(player.position.x, player.position.z)
	var far := Vector2(room.w, room.d).length()
	var nodes: Array = []
	for id in room.object_nodes:
		var n: Node3D = room.object_nodes[id]
		if is_instance_valid(n):
			nodes.append([n, Vector2(n.position.x, n.position.z).distance_to(center), n.scale])
			if not reduced:
				n.scale = Vector3.ONE * 0.01
	var card: Control = signatures.first_look_begins() if signatures else null
	var dur := 0.25 if reduced else 2.4
	var t := 0.0
	while t < dur and not m.was_skipped and is_inside_tree():
		t += get_process_delta_time()
		var r := far * clampf(t / dur, 0.0, 1.0)
		if is_instance_valid(room) and room.edge_walls != null:
			room.edge_walls.set_reveal(center, r if not reduced else far)
		for item in nodes:
			if is_instance_valid(item[0]) and item[1] <= r and (item[0] as Node3D).scale.x < 0.02:
				(item[0] as Node3D).scale = item[2]
				AnimFx.pop_in(item[0])
		await get_tree().process_frame
	if is_instance_valid(room) and room.edge_walls != null:
		room.edge_walls.set_reveal(center, 1e6)
	for item in nodes:
		if is_instance_valid(item[0]):
			(item[0] as Node3D).scale = item[2]
	if (m.was_skipped or not is_inside_tree()) and is_instance_valid(card):
		card.dismiss()
	m.finish()


## The place's name for the HUD (the Light World's places carry a little sun).
func room_title(data: Dictionary) -> String:
	var n := str(data.get("name", data.get("id", "")))
	return ("☀ " + n) if Realms.is_light(data) else n


## The first visit to a place is a discovery (the Almanac counts them).
func _discover(id: String, data: Dictionary) -> void:
	var v: Dictionary = load("res://scripts/variety/variety_save.gd").data()
	var seen: Dictionary = v.get("visited", {}) if v.get("visited") is Dictionary else {}
	if seen.has(id):
		return
	seen[id] = Time.get_datetime_string_from_system()
	v["visited"] = seen
	if seen.size() > 1:
		Story.bump("discoveries")
		GameState.notify("✦ Discovered: %s" % str(data.get("name", id)))
	else:
		load("res://scripts/variety/variety_save.gd").save()


## The Backdrop layer: a plain colour, a picture wrapped around the sky, or (places.gd) a sky
## gradient that can follow the time of day.
## One sky, reused: its colours (or picture) change in place. A new Sky each time leaked its memory on the
## phone's renderer (OpenGL, also the browser version's): about a third of a megabyte per sky, two per place
## you entered and one every 20 seconds outdoors (the daylight), until Android ended the app.
func apply_backdrop(data: Dictionary) -> void:
	var sky: Dictionary = data.get("sky", {})
	var visible := bool(data.get("layers", {}).get("backdrop", {}).get("visible", true))
	var colors: Array = PlaceBackdrop.sky_colors(data, daylight.current_hour() if daylight else 12.0) if visible else []
	if not colors.is_empty():
		if _sky_gradient == null:
			_sky_gradient = ProceduralSkyMaterial.new()
		PlaceBackdrop.paint_sky(_sky_gradient, colors)
		_use_sky(_sky_gradient)
		return
	var tex: Texture2D = SaveManager.load_texture(str(sky.get("texture", ""))) if visible else null
	if tex:
		if _sky_picture == null:
			_sky_picture = PanoramaSkyMaterial.new()
			_sky_picture.filter = false
		if _sky_picture.panorama != tex:
			_sky_picture.panorama = tex
		_use_sky(_sky_picture)
	else:
		env.background_mode = Environment.BG_COLOR   # (the sky stays assigned, unused: no new one next time)
		if not visible:
			env.background_color = Color.BLACK


func _use_sky(mat: Material) -> void:
	if _sky == null:
		_sky = Sky.new()
	if _sky.sky_material != mat:
		_sky.sky_material = mat
	if env.sky != _sky:
		env.sky = _sky
	env.background_mode = Environment.BG_SKY


## Re-creates the room's 3D scene from its (edited) data and nudges anyone
## who is now standing inside a block onto a free cell.
func rebuild_room() -> void:
	BlockFactory.clear_cache()
	room.pop_new = true
	room.build(room.data)
	room.pop_new = false
	backdrop.build(room.data, neighbours_of(room.data))
	dark_look.build(room, room.data)
	apply_backdrop(room.data)
	hud.set_room(room_title(room.data))
	daylight.apply()
	refresh_weather(true)
	refresh_music()   # (Build mode > Room: a new song plays at once)
	for a in [player] + actors.values():
		if not a.is_player:
			a.stop()  # their old path may now cross a block; they'll wander again
		if not room.nav.walkable(a.cell()):
			a.stop()
			a.position = room.cell_center(room.nav.nearest_walkable(a.cell()))


## Remembers where residents were standing, for next time.
func save_positions() -> void:
	for id in actors:
		var c := GameState.get_character(id)
		if not c.is_empty() and is_instance_valid(actors[id]):
			var cell: Vector2i = actors[id].cell()
			c["pos"] = [cell.x, cell.y]
			SaveManager.save_character(c)


## Saves build-mode edits right now (before quitting or switching rooms).
func flush_room() -> void:
	if build and room and not room.data.is_empty():
		build.flush_save()


## Everything that only lives in memory, written out (quit, window close,
## page hidden on the web).
func flush_all() -> void:
	flush_room()
	save_positions()


## The places joined to this one, by side (for the ground beyond each join).
func neighbours_of(data: Dictionary) -> Dictionary:
	var out := {}
	for side in Places.edges(data):
		var id := Places.edge(data, side)
		if SaveManager.room_exists(id):
			out[side] = SaveManager.load_room(id)
	return out


## An "auto" sky follows the hour (Daylight calls this as time passes).
func refresh_sky() -> void:
	if str(Places.background(room.data).sky) == "auto":
		apply_backdrop(room.data)


## Walking off a joined edge: the next place, at the matching spot of its edge. Animated (the view
## slides the way you're going while it fades), skippable with a tap; Reduce motion: a short fade.
func cross_edge(side: String, cell: Vector2i) -> void:
	var target := Places.edge(room.data, side)
	if _transitioning or target == "" or not SaveManager.room_exists(target):
		return
	if build.active:
		build.exit()
	flush_room()
	_transitioning = true
	var arrive := Places.arrival(room.data, side, cell, SaveManager.load_room(target))
	var m: Control = Moment.begin(main)
	var reduced := Moment.reduced()
	var step: Vector2i = Places.STEP[side]
	var dir := Vector3(step.x, 0, step.y)
	var half := Moment.FADE_S if reduced else 0.35
	# Out: a step over the edge while the view fades.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_fade, "color:a", 1.0, half)
	if not reduced:
		tw.tween_property(player, "position", player.position + dir * 0.9, half)
	if await m.wait(half):
		tw.kill()
	load_room(target, "", arrive)
	# In: the last step into the new place, the camera following from the side you crossed.
	var land: Vector3 = player.position
	var tw2 := create_tween().set_parallel(true)
	var back := half if not m.was_skipped else 0.05
	tw2.tween_property(_fade, "color:a", 0.0, back)
	if not reduced and not m.was_skipped:
		player.position = land - dir * 0.9
		cam._focus = land - dir * 3.0
		tw2.tween_property(player, "position", land, back)
	if await m.wait(back):
		tw2.kill()
		player.position = land
	_fade.color.a = 0.0
	m.finish()
	_transitioning = false
	Story.bump("crossings")
	if main.get("autosave"):
		main.autosave.on_room_changed()


## A Light World place under the open sky (a street, a park): its glossy things reflect the sky.
static func open_sky(data: Dictionary) -> bool:
	return Realms.is_light(data) and str(data.get("kind", "")) != "indoor"


func go_outside() -> void:
	if _transitioning or dark.busy or not main.panels.is_empty():
		return
	var target := preload("res://scripts/world/light_home.gd").street_entry()
	if target != "":
		controller.cancel_input()
		await go_to_room(target)


func go_to_room(id: String) -> void:
	if not is_inside_tree():
		return
	if build.active:
		build.exit()
	flush_room()
	_transitioning = true
	var from := GameState.current_room_id
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	var until := Time.get_ticks_msec() + 500
	while is_instance_valid(tw) and tw.is_running() and is_inside_tree() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	if not is_inside_tree():
		_transitioning = false
		return
	load_room(id, from)
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.35)
	var until2 := Time.get_ticks_msec() + 550
	while is_instance_valid(tw2) and tw2.is_running() and is_inside_tree() and Time.get_ticks_msec() < until2:
		await get_tree().process_frame
	_transitioning = false
	if is_inside_tree() and is_instance_valid(main) and main.get("autosave"):
		main.autosave.on_room_changed()


# --- Residents -------------------------------------------------------------------------

func spawn_character(c: Dictionary) -> void:
	var id := str(c.get("id", ""))
	var a := Actor.new()
	a.setup(id, str(c.get("name", "")), dark.look_for(talk.textures_for(c).get("neutral")))
	_actors_root.add_child(a)
	a.anim.load_frames(c.get("anims", {}))
	var pos: Array = c.get("pos", [])
	var cell: Vector2i = Vector2i(int(pos[0]), int(pos[1])) if pos.size() >= 2 else room.nav.random_walkable(RandomNumberGenerator.new())
	a.position = room.cell_center(room.nav.nearest_walkable(cell))
	actors[id] = a


## Keeps the room in sync after the Creator saves (new face, new friend, moved house).
## The player's animation frames: the form's own, and for a doll the built-in run cycle.
func load_player_anims() -> void:
	if player == null or player.anim == null:
		return
	var form := PlayerLook.current()
	var d := PlayerLook.form_data(form)
	player.anim.load_frames(d.get("anims", {}))
	if str(d.get("mode", "")) == "doll" and not player.anim.has_custom("run"):
		player.anim.add_generated("run", AnimBake.textures(AnimBake.doll_run(PlayerLook.base_image(form, "neutral"))), AnimBake.FPS.run)


func refresh_character(id: String) -> void:
	if id == "player":
		refresh_gear()
		load_player_anims()
		return
	var c := GameState.get_character(id)
	var here := not c.is_empty() and str(load("res://scripts/variety/routines.gd").room_now(c)) == GameState.current_room_id
	if here and not actors.has(id):
		c["pos"] = []
		spawn_character(c)
		var cell: Vector2i = room.nav.best_neighbor(player.cell(), player.cell())
		if cell.x >= 0:
			actors[id].position = room.cell_center(cell)
		actors[id].emote("♥", Color("#ff8fab"))
	elif here:
		actors[id].set_texture(talk.textures_for(c).get("neutral"))
		actors[id].anim.load_frames(c.get("anims", {}))
		actors[id].display_name = str(c.get("name", ""))
		actors[id].name_label.text = str(c.get("name", ""))
	elif actors.has(id):
		actors[id].queue_free()
		actors.erase(id)


func set_actor_emotion(id: String, emotion: String, revert_after: float = 0.0) -> void:
	if not actors.has(id) or not is_instance_valid(actors[id]):
		return
	var tex: Texture2D = dark.look_for(talk.textures_for(GameState.get_character(id)).get(emotion))
	if tex:
		actors[id].set_texture(tex)
	actors[id].react(emotion)
	if revert_after > 0.0 and is_inside_tree():
		var until := Time.get_ticks_msec() + int(revert_after * 1000.0)
		while Time.get_ticks_msec() < until and is_inside_tree():
			await get_tree().process_frame
		if is_inside_tree() and actors.has(id) and is_instance_valid(actors[id]) and talk.talking_to != id:
			set_actor_emotion(id, "neutral")


# --- The player: forms, gear, aura, expressions -----------------------------------------

## Redraws the player's sprite (current form + equipped gear) and the aura
## from worn items. Called on room load, equip changes and form changes.
func refresh_gear() -> void:
	PlayerLook.invalidate()
	if player == null or not is_instance_valid(player):
		return
	player.set_texture(PlayerLook.texture(PlayerLook.current(), "neutral"))
	_aura_token += 1
	var eq := Inventory.equipped()
	for slot in Inventory.SLOTS:
		var it := Items.load_item(str(eq[slot])) if str(eq[slot]) != "" else {}
		if not it.is_empty() and str(it.effect.get("type", "")) == "aura":
			player.set_aura(Color.from_string(str(it.effect.get("value", "")), Color("#ffd166")))
			return
	player.set_aura(Color.WHITE, false)


## A coloured glow under the player; seconds > 0 fades back to the gear's aura.
func set_aura(color: Color, seconds: float = 0.0) -> void:
	if not is_instance_valid(player):
		return
	player.set_aura(color)
	_aura_token += 1
	if seconds <= 0.0 or not is_inside_tree():
		return
	var token := _aura_token
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and is_inside_tree() and token == _aura_token:
		await get_tree().process_frame
	if is_inside_tree() and token == _aura_token and is_instance_valid(player):
		refresh_gear()


## Tints the room's light for a few seconds, then the real clock takes over again.
func flash_light(color: Color, seconds: float) -> void:
	if not is_inside_tree() or not is_instance_valid(env) or not is_instance_valid(sun):
		return
	_light_token += 1
	var token := _light_token
	light_flashing = true
	var tw := create_tween()
	tw.tween_property(env, "ambient_light_color", color, 0.5)
	tw.parallel().tween_property(sun, "light_color", color.lerp(Color.WHITE, 0.35), 0.5)
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and is_inside_tree() and token == _light_token:
		await get_tree().process_frame
	if is_inside_tree() and token == _light_token:
		light_flashing = false
		daylight.apply()


## Shows one of the player's faces for a moment (and does the matching wiggle).
func set_player_emotion(emotion: String, revert_after: float = 2.5) -> void:
	if not is_instance_valid(player):
		return
	player.set_texture(PlayerLook.texture(PlayerLook.current(), emotion))
	player.react(emotion)
	_face_token += 1
	if revert_after > 0.0 and is_inside_tree():
		var token := _face_token
		var until := Time.get_ticks_msec() + int(revert_after * 1000.0)
		while Time.get_ticks_msec() < until and is_inside_tree() and token == _face_token:
			await get_tree().process_frame
		if is_inside_tree() and is_instance_valid(player) and token == _face_token:
			player.set_texture(PlayerLook.texture(PlayerLook.current(), "neutral"))


## A small flourish when your home changes in front of you (Tell Polox about home, an answered question).
func flourish(buzz: bool = true) -> void:
	if player == null:
		return
	if buzz:
		preload("res://scripts/ui/haptics.gd").confirm()
	player.emote("✦", Color("#ffe9a8"))
	Synth.play(self, "chime", 0.45)
	if not Moment.reduced():
		flash_light(Color("#fff4d6"), 0.7)


## Real Me <-> Dream World Me, with a little sparkle.
func switch_form() -> void:
	PlayerLook.normalize()
	GameState.notify("Your look follows this world. Edit both looks in My character.")


## Today's weather, unless seasons are off or this room has weather "none".
func refresh_weather(force: bool = false) -> void:
	var kind := ""
	if Seasons.enabled() and str(room.data.get("ambiance", {}).get("weather", "auto")) != "none":
		kind = Seasons.weather()
		if variety and variety.sky_today() != "":
			kind = variety.sky_today()   # a Sky Moment decides today's weather
			if kind == "clear":
				kind = ""
	if weather_hold != "":
		kind = weather_hold
	if force or kind != weather.current:
		weather.show_weather(kind, room.w, room.d, room.h, not force)
	if Realms.is_light(room.data):
		SeasonalDecor.clear(room)   # your real home only has what you put there
	else:
		SeasonalDecor.build(room)   # holiday lights and the season's touch (only rebuilds when the day changes)


func take_photo() -> String:
	return await PhotoMode.take(self)


## Shortcuts used by scripted checks and other systems.
func approach_character(id: String) -> void:
	controller.approach_character(id)


func use_object(o: Dictionary) -> void:
	controller.use_object(o)


# --- Talk hooks ----------------------------------------------------------------------

func on_talk_started(id: String) -> void:
	if actors.has(id):
		actors[id].stop()
		actors[id].emote("!")
		cam.talk_focus = (actors[id].position + player.position) / 2.0
		# Flip the two sprites so they face each other on screen.
		var side: float = (actors[id].position - player.position).dot(cam.camera.global_transform.basis.x)
		player.sprite.flip_h = side < 0.0
		actors[id].sprite.flip_h = side > 0.0
	music.play_theme(str(GameState.get_character(id).get("theme", "")))
	hud.visible = false


func on_reply(_id: String, _reply: Dictionary) -> void:
	pass


## A theme changed (Settings > Music) or the place's own song (Build mode): the music follows.
func refresh_music() -> void:
	if room and talk.talking_to == "":   # (a friend's theme keeps going while you talk)
		music.play_for_room(room.data)


func on_talk_ended(id: String) -> void:
	hud.visible = true
	cam.talk_focus = null
	music.back_to_room()
	set_actor_emotion(id, "neutral")
	# Once ever: may they send notes? (After this frame, and by id: the game can be gone by then.)
	if is_instance_valid(main):
		preload("res://scripts/variety/miss_you.gd").maybe_ask_later.call_deferred(main.get_instance_id(), id)


func _refresh_phone_indicator() -> void:
	if is_instance_valid(hud):
		hud.set_phone_link(main.phone_link.running, main.phone_link.pairing.devices().size())


func open_bag() -> void:
	if main.panels.is_empty():
		main.open_panel(WorldMenu.bag(self))


## The World tab (phones): the World Map, things to do, a photo, the camera.
func open_world_sheet() -> void:
	if main.panels.is_empty():
		var s: Control = load("res://scripts/ui/world_sheet.gd").new()
		main.open_panel(s)
		s.setup_world(self)


func open_menu() -> void:
	if main.panels.is_empty():
		main.open_panel(WorldMenu.make(self))


## Called by Main on "back" when no panel is open.
func on_back() -> bool:
	if talk.is_open():
		dialogue.close_box()
		return true
	if platform and platform.active:
		platform.leave(false)
		return true
	if build.active:
		build.exit()
		return true
	return false
