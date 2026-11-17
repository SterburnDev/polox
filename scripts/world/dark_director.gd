extends Node
## The fountains in play (game_world.dark). A gate (realms.gd) crosses between the Light World (your
## real home) and the Dream World: going home is the rise into the light (you become Real Me), going
## back is the fall into the dark (Dream World Me). Inside the Dream World, a Dream Gate offers what
## fits: make the Deep version of this place or link one you have, enter it, go back, seal it, or
## reopen it. Every big moment is animated and skippable (Moment), and a short fade with Reduce
## motion: the fountain opening (cracks, the rising column, the place's colours draining), the fall
## into the Dream World, transforming (you into Dream World Me, friends into their Dream World look),
## the rise back into the light, and sealing (light gathering, the sky clearing, a Memory Book page).

const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const Places := preload("res://scripts/world/places.gd")
const Moment := preload("res://scripts/ui/moment.gd")
const FallOverlay := preload("res://scripts/ui/fall_overlay.gd")
const TransformFx := preload("res://scripts/characters/transform_fx.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const ChoicePanel := preload("res://scripts/ui/choice_panel.gd")
const Synth := preload("res://scripts/core/synth.gd")
const Realms := preload("res://scripts/world/realms.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")

var world: Node
var busy := false
var last_moment := ""            # (tests) the last animation that ran: "opening", "entering", ...
const DARK_LOOK := &"polox_dark_look"   # a friend's picture -> its Dream World look (metadata on the picture)


func setup(game_world: Node) -> void:
	world = game_world


func _node_of(o: Dictionary) -> Node:
	return world.room.object_nodes.get(str(o.get("id", "")))


func _save_here() -> void:
	SaveManager.save_room(world.room.data)


## Tapping or walking up to a fountain.
func use_fountain(o: Dictionary) -> void:
	# The liquid answers the touch with a ring (fountain_node.gd poke), even while the gate is busy.
	if world and world.is_inside_tree():
		world.get_tree().call_group(&"polox_gate", "poke_if", str(o.get("id", "")))
	if busy:
		return
	if Realms.is_gate(o):
		use_gate(o)
		return
	var dark_here := DarkWorlds.is_dark(world.room.data)
	var st := DarkWorlds.state(o)
	var options: Array = []
	if dark_here:
		var back_name := _name_of(DarkWorlds.target(o), "where you came from")
		options = [["Go back to %s" % back_name, func(): go_back(o)], ["Seal the Dream Gate (and go back)", func(): seal_from_dark(o)]]
	elif st == "new":
		options = [["Make the Deep version of this place", func(): make_dark(o)]]
		var have := DarkWorlds.dark_worlds(_all_rooms())
		for id in have.open + have.archive:
			options.append(["Link to %s" % str(SaveManager.load_room(id).get("name", id)), func(): link_existing(o, str(id))])
	elif st == "open":
		options = [["Enter the Deep", func(): enter(o)], ["Seal the Dream Gate", func(): seal(o)]]
	else:
		options = [["Reopen the Dream Gate", func(): reopen(o)]]
	options.append(["Not now", func(): pass])
	var p: Control = ChoicePanel.new()
	world.main.open_panel(p)
	p.ask("Dream Gate", _describe(o, dark_here), options)


func _describe(o: Dictionary, dark_here: bool) -> String:
	var name := _name_of(DarkWorlds.target(o), "")
	if dark_here:
		return "The way back to %s." % (name if name != "" else "where you came from")
	match DarkWorlds.state(o):
		"new":
			return "A Dream Gate, waiting. Make the Deep version of this place (the same layout, turned strange), or link one you already have."
		"open":
			return "It leads down to %s. In the Deep you're Dream World Me." % name
	return "Sealed. %s waits in the archive; nothing was deleted." % name


func _name_of(id: String, fallback: String) -> String:
	return str(SaveManager.load_room(id).get("name", id)) if id != "" and SaveManager.room_exists(id) else fallback


# --- Between the worlds (gates) --------------------------------------------------------------------

## A gate: the way home from the Dream World, or the Dream Gate in your room.
func use_gate(o: Dictionary) -> void:
	var p: Control = ChoicePanel.new()
	world.main.open_panel(p)
	if str(o.get("leads", "")) == Realms.LIGHT:
		var known := not LightHome.needs_survey()
		p.ask("The way home", "Light pours up from it. It leads home, to the Light World: your real home, quiet and ordinary. There you're %s." % PlayerLook.label("real")
				+ ("" if known else " (The first time, it will ask you about home.)"),
			[["Go home", func(): go_light(o)], ["Not now", func(): pass]])
	else:
		p.ask("Dream Gate", "A basin brimming with deep orange liquid, rippling in the corner of your room. It leads down into the Dream World, home of the Bramins, to %s. There you're %s." % [_name_of(dark_return(), "your world"), PlayerLook.label("dark")],
			[["Enter the Dream World", func(): go_dark(o)], ["Not now", func(): pass]])


## Where the Dream World picks up again: the place you last left it from, else its start place.
func dark_return() -> String:
	var r := str(GameState.world.get("dark_return", ""))
	if r != "" and not Realms.is_light_id(r) and SaveManager.room_exists(r):
		return r
	return str(GameState.world.get("start_room", "home"))


## Home: the rise into the light, then you're Real Me in your room. The very first time, the screen
## goes black first: the Survey asks about your home (home_mapper.gd), and the house is built from it.
func go_light(_o: Dictionary = {}) -> void:
	if busy:
		return
	if not Realms.is_light(world.room.data):
		GameState.world["dark_return"] = GameState.current_room_id
		GameState.save_world()
	var dest := LightHome.entry_id()
	var phone: Node = world.main.get("phone")
	if LightHome.needs_survey() and phone and phone.paired():
		# Prefer an existing shared house, but pairing must not disable creating one here.
		busy = true
		if str(phone.client.home_state) != "private":
			GameState.notify("Bringing your home over from your PC...")
			await phone.sync_now()
		busy = false
		dest = LightHome.entry_id()
	if LightHome.needs_survey():
		busy = true
		dest = await _survey()
		busy = false
	if dest == "":
		dest = LightHome.ensure_entry()
	await _cross(dest, "up", "dark", "real")
	await first_look()


## The first time you arrive in the house Polox built, it draws itself in (once; remembered in my_home).
func first_look() -> void:
	var HomeStore: Script = load("res://scripts/home/home_store.gd")
	if not HomeStore.exists() or not Realms.is_light(world.room.data):
		return
	var home: Dictionary = HomeStore.load_home()
	if str(home.get("first_look", "")) != "":
		return
	busy = true
	last_moment = "first_look"
	await world.reveal_home()
	# An interrupted reveal must be offered again on the next visit.
	home = HomeStore.load_home()
	home["first_look"] = Time.get_datetime_string_from_system(false, false)
	HomeStore.save_home(home)
	busy = false


## The Survey and the house built from it. Returns the place to arrive in.
func _survey() -> String:
	var mapper: Node = HomeMapper.new()
	mapper.name = "HomeMapper"
	add_child(mapper)
	var entry: String = await mapper.run(world.main)
	mapper.queue_free()
	return entry if entry != "" else LightHome.ensure_entry()


## Settings > Light World > Map my home: the Survey again (your own edits are kept on top). In the
## Light World you land in the new house; in the Dream World you stay where you are.
func map_home() -> void:
	if busy:
		return
	busy = true
	var entry := await _survey()
	busy = false
	if Realms.is_light(world.room.data) or GameState.current_room_id.begins_with(Realms.PREFIX):
		world.load_room(entry)
	GameState.notify("✦ Your home is mapped. (Menu > My home shows the sketch and where everything came from.)")


## Down into the Dream World, where you left it, as Dream World Me.
func go_dark(_o: Dictionary = {}) -> void:
	if busy:
		return
	await _cross(dark_return(), "down", "light", "dark")
	if world.get("signatures"):
		await world.signatures.first_fountain()


## The World Map's Go there across the worlds: the same journey, straight to that place.
func travel_to(id: String) -> void:
	if busy or not SaveManager.room_exists(id):
		return
	var to_light := Realms.is_light_id(id)
	if to_light == Realms.is_light(world.room.data):
		await world.go_to_room(id)
		return
	if to_light:
		GameState.world["dark_return"] = GameState.current_room_id
		GameState.save_world()
	await _cross(id, "up" if to_light else "down", "dark" if to_light else "light", "real" if to_light else "dark")


func _all_rooms() -> Dictionary:
	var out := {}
	for id in SaveManager.list_rooms():
		out[id] = world.room.data if id == GameState.current_room_id else SaveManager.load_room(id)
	return out


## Makes a Dream World from this place and opens the fountain to it.
func make_dark(o: Dictionary) -> void:
	var dark := DarkWorlds.make_from(world.room.data, SaveManager.list_rooms())
	if not DarkWorlds.link(world.room.data, o, dark):
		GameState.notify("There's no room in that Dream World for a Dream Gate back.")
		return
	SaveManager.save_room(dark)
	_save_here()
	await opening(o)
	GameState.notify("✦ %s is open. Step into the Dream Gate to go there." % str(dark.name))


func link_existing(o: Dictionary, dark_id: String) -> void:
	var dark := SaveManager.load_room(dark_id)
	if not DarkWorlds.link(world.room.data, o, dark):
		return
	SaveManager.save_room(dark)
	_save_here()
	await opening(o)


## The opening: cracks, the rising column, the colours draining (and coming back).
func opening(o: Dictionary) -> void:
	busy = true
	last_moment = "opening"
	var node: Node = _node_of(o)
	var m: Control = Moment.begin(world.main)
	var reduced := Moment.reduced()
	var env: Environment = world.env
	var amb := env.ambient_light_color
	var sun_e: float = world.sun.light_energy
	var tw: Tween
	if not reduced:
		tw = world.create_tween().set_parallel(true)
		tw.tween_property(env, "ambient_light_color", DarkWorlds.dark_color(amb), 0.9)
		tw.tween_property(world.sun, "light_energy", sun_e * 0.45, 0.9)
	if node and node.has_method("play_opening"):
		await node.play_opening(m, reduced)
	else:
		await m.wait(0.2)
	if tw:
		tw.kill()
	var back := world.create_tween().set_parallel(true)
	back.tween_property(env, "ambient_light_color", amb, 0.05 if m.was_skipped or reduced else 0.6)
	back.tween_property(world.sun, "light_energy", sun_e, 0.05 if m.was_skipped or reduced else 0.6)
	m.finish()
	busy = false


## Into the Dream World: the fall, the landing, the transformation.
func enter(o: Dictionary) -> void:
	var t := DarkWorlds.target(o)
	if t == "" or not SaveManager.room_exists(t) or busy:
		return
	await _cross(t, "down", "light")


func go_back(o: Dictionary) -> void:
	var t := DarkWorlds.target(o)
	if t == "" or not SaveManager.room_exists(t) or busy:
		return
	await _cross(t, "up", "dark")


## The fall (or rise), the place changing under it, then everyone transforming. `to_form` (between the
## worlds): the form you take on arriving ("" = whatever the place asks for).
func _cross(target: String, direction: String, from_side: String, to_form: String = "") -> void:
	busy = true
	_checkpoint("cross_begin_" + direction)
	last_moment = "entering" if direction == "down" else "returning"
	world.flush_room()
	world._transitioning = true
	var m: Control = Moment.begin(world.main)
	var reduced := Moment.reduced()
	# Use the form's source picture, not a transient blink/idle frame on the GPU.
	var before_tex: Texture2D = PlayerLook.texture(PlayerLook.current(), "neutral")
	var overlay: Control = FallOverlay.new()
	overlay.direction = direction
	overlay.faces = [before_tex]
	world.main.toast_layer().add_child(overlay)
	world.main.toast_layer().move_child(overlay, m.get_index())   # under the skip catcher
	Synth.play(world, "whoosh", 0.6)
	if reduced:
		overlay.progress = 0.5
		overlay.queue_redraw()
		await m.wait(Moment.FADE_S)
	else:
		await overlay.play(m, 1.2, 0.0, 0.6)
	if not is_instance_valid(world) or not world.is_inside_tree():
		if is_instance_valid(overlay):
			overlay.queue_free()
		m.finish()
		busy = false
		return
	# Land beside the fountain that leads back where you came from.
	var dest := SaveManager.load_room(target)
	var arrive := _beside_fountain_to(dest, GameState.current_room_id)
	_checkpoint("cross_load_room")
	world.load_room(target, "", arrive)
	_checkpoint("cross_room_ready")
	# load_room selects the destination realm before creating the arriving player.
	# Returning from the Deep is still Dream World travel, so its outfit stays on.
	if not reduced and not m.was_skipped:
		await overlay.play(m, 0.9, 0.6, 1.0)   # the rest of the fall; its end shows the new place
	if is_instance_valid(overlay):
		overlay.queue_free()
	if not is_instance_valid(world) or not world.is_inside_tree():
		m.finish()
		busy = false
		return
	# Transforming: you (and friends here) into the new side's forms.
	last_moment = "transforming"
	_checkpoint("cross_transform")
	await _transform_everyone(before_tex, direction == "down", m, reduced or m.was_skipped)
	if not is_instance_valid(world) or not world.is_inside_tree():
		m.finish()
		busy = false
		return
	last_moment = "entering" if direction == "down" else "returning"
	if direction == "down" and DarkWorlds.is_dark(world.room.data):
		load("res://scripts/variety/story.gd").bump("dark_visits")
		_place_crystals()
	elif to_form == "real":
		load("res://scripts/variety/story.gd").bump("light_visits")
	m.finish()
	world._transitioning = false
	busy = false
	_checkpoint("cross_complete")


func _checkpoint(phase: String) -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.main):
		return
	var log: Node = world.main.get("crash_log")
	if log:
		log.checkpoint(phase)


## The first visit to a Dream World place hides three Dark Crystals in it (once; collect them any time).
func _place_crystals() -> void:
	var data: Dictionary = world.room.data
	if bool(data.get("crystals_placed", false)) or not DarkWorlds.is_dark(data):
		return
	var item_id := _crystal_item()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(data.get("id", "")))
	var placed := 0
	for _i in 60:
		if placed >= 3:
			break
		var c := Vector2i(rng.randi_range(1, world.room.w - 2), rng.randi_range(1, world.room.d - 2))
		if not world.room.nav.walkable(c):
			continue
		var o: Dictionary = load("res://scripts/world/room_editor.gd").add_object(data, c.x, c.y, "pickup")
		if o.is_empty():
			continue
		o.merge({"item": item_id, "count": 1, "respawn": "once", "taken": "", "crystal": true}, true)
		placed += 1
	data["crystals_placed"] = true
	SaveManager.save_room(data)
	world.rebuild_room()


static func _crystal_item() -> String:
	var Items: Script = load("res://scripts/items/items.gd")
	if Items.exists("dark_crystal"):
		return "dark_crystal"
	var it: Dictionary = Items.defaults("keepsake")
	it["id"] = "dark_crystal"
	it["name"] = "Dark Crystal"
	it["flavor"] = "It hums softly, like a Dream Gate."
	it["rarity"] = "rare"
	it["auto_icon"] = {"shape": "gem", "color": "#9a6bff"}
	it["tags"] = ["found", "crystal"]
	return Items.save_item(it)


## The cell next to the fountain in `dest` that leads to `from_id` (else its start spot).
func _beside_fountain_to(dest: Dictionary, from_id: String) -> Vector2i:
	for f in DarkWorlds.fountains(dest):
		if DarkWorlds.target(f) == from_id:
			var p: Array = f.get("pos", [0, 0, 0])
			return Vector2i(int(p[0]), int(p[2]) + 1)
	if Realms.is_light_id(from_id) != Realms.is_light(dest):
		for g in Realms.gates(dest):   # between the worlds: beside the gate
			var gp: Array = g.get("pos", [0, 0, 0])
			return Vector2i(int(gp[0]), int(gp[2]) + 1)
	var sp: Array = dest.get("spawn", [6, 7])
	return Vector2i(int(sp[0]), int(sp[1]))


func _transform_everyone(before_tex: Texture2D, to_dark: bool, m: Control, quick: bool) -> void:
	var after_tex: Texture2D = PlayerLook.texture(PlayerLook.current(), "neutral")
	if quick:
		await TransformFx.play(world.player, [], after_tex, m, true)
		return
	var target := {"kind": "player", "form": PlayerLook.current()}
	var frames: Array = TransformFx.drawn_frames(target, "transform_in" if to_dark else "transform_out")
	if frames.is_empty() and before_tex and after_tex:
		frames = TransformFx.morph_frames(TransformFx.source_image(before_tex), TransformFx.source_image(after_tex))
	Synth.play(world, "sparkle", 0.5)
	await TransformFx.play(world.player, frames, after_tex, m, quick)


## A friend's look on this side: their own picture in the Light World, a generated Dream World look
## in a Dream World place (game_world applies it when they appear).
func look_for(tex: Texture2D) -> Texture2D:
	if tex == null or not DarkWorlds.is_dark(world.room.data):
		return tex
	# Kept on the picture itself, so it lives exactly as long as the picture does. (Until 1.27 a list
	# held up to 64 old pictures and their dark looks alive after the friends were rebuilt.)
	if not tex.has_meta(DARK_LOOK):
		var img := TransformFx.dark_variant(TransformFx.source_image(tex))
		if img == null:
			return tex
		tex.set_meta(DARK_LOOK, TransformFx.texture_from_image(img))
	return tex.get_meta(DARK_LOOK)


## Sealing: light gathers, the column sinks, the sky clears; a Memory Book page.
func seal(o: Dictionary) -> void:
	if busy:
		return
	busy = true
	last_moment = "sealing"
	var node: Node = _node_of(o)
	var m: Control = Moment.begin(world.main)
	var reduced := Moment.reduced()
	if node and node.has_method("play_sealing"):
		await node.play_sealing(m, reduced)
	else:
		await m.wait(0.2)
	if not is_instance_valid(world) or not world.is_inside_tree():
		m.finish()
		busy = false
		return
	DarkWorlds.seal(o)
	_save_here()
	var t := DarkWorlds.target(o)
	var dname := str(SaveManager.load_room(t).get("name", t)) if t != "" else "the Dream World"
	GameState.add_moment("Sealed a Dream Gate", "At %s, the Dream Gate to %s closed for now. Nothing is lost: it waits in the archive." % [str(world.room.data.get("name", "")), dname], "", "auto")
	m.finish()
	busy = false
	GameState.notify("✦ The Dream Gate is sealed. %s waits in the archive (World Map)." % dname)


## From inside: go back first, then seal the fountain on the Light World side.
func seal_from_dark(o: Dictionary) -> void:
	var t := DarkWorlds.target(o)
	await go_back(o)
	if not is_instance_valid(world) or not world.is_inside_tree() or GameState.current_room_id != t:
		return
	for f in DarkWorlds.fountains(world.room.data):
		if DarkWorlds.target(f) != "" and DarkWorlds.state(f) == "open":
			await seal(f)
			return


func reopen(o: Dictionary) -> void:
	if busy or DarkWorlds.target(o) == "":
		return
	DarkWorlds.reopen(o)
	_save_here()
	await opening(o)
