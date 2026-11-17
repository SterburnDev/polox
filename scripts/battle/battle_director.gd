extends Node
## Battles in play (game_world.battles). Starting one: a friend walks up with a reason (rare, in
## the Deep by default; Accept or Not now), you say "I want to fight" in a chat, Menu > Battle,
## or a Battle Spot. Then: a template, a battle you saved, or a new one (the Battle Maker), and up
## to two friends to fight beside you. Afterwards a line in the Battle Log, a Memory Book page for a
## spare, and never a loss of anything (knocked down: you get back up).

const Encounters := preload("res://scripts/battle/encounters.gd")
const BattleData := preload("res://scripts/battle/battle_data.gd")
const BattleScreen := preload("res://scripts/battle/battle_screen.gd")
const BattleState := preload("res://scripts/battle/battle_state.gd")
const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const ChoicePanel := preload("res://scripts/ui/choice_panel.gd")
const Moment := preload("res://scripts/ui/moment.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const BattleInventory := preload("res://scripts/battle/battle_inventory.gd")
const Spells := preload("res://scripts/battle/battle_spells.gd")
const MusicPlayer := preload("res://scripts/world/music_player.gd")

const CHECK_EVERY_S := 120.0
const LOG_MAX := 200

var world: Node
var screen: Control                 # the battle on screen
var last_encounter := -1e9
var _check_t := 0.0
var rng := RandomNumberGenerator.new()
var forced_roll := -1.0             # tests: the next encounter roll
var starting := false
var _encounter_pending := false
var _music_task := -1


func setup(game_world: Node) -> void:
	world = game_world
	rng.randomize()
	last_encounter = Time.get_unix_time_from_system()


func _process(delta: float) -> void:
	if screen or starting or _encounter_pending or world == null or world.player == null:
		return
	_check_t += delta
	if _check_t < CHECK_EVERY_S:
		return
	_check_t = 0.0
	try_encounter()


## A friend may walk up now (rare, never while you're busy).
func try_encounter() -> bool:
	if screen or starting or _encounter_pending or world.build.active or world._transitioning or not world.main.panels.is_empty() or world.talk.talking_to != "":
		return false
	var roll := forced_roll if forced_roll >= 0.0 else rng.randf()
	forced_roll = -1.0
	var since := Time.get_unix_time_from_system() - last_encounter
	if load("res://scripts/world/realms.gd").is_light(world.room.data):
		return false   # never in the Light World (your real home)
	if not Encounters.should_start(GameState.settings, DarkWorlds.is_dark(world.room.data), since, roll):
		return false
	var ids: Array = world.actors.keys()
	if ids.is_empty():
		return false
	var id := str(ids[rng.randi() % ids.size()])
	last_encounter = Time.get_unix_time_from_system()
	await walk_up(id)
	return true


## A friend walks up to you with a reason, then asks.
func walk_up(id: String) -> void:
	var c := GameState.get_character(id)
	if c.is_empty() or not world.actors.has(id):
		return
	_encounter_pending = true
	var room_id := GameState.current_room_id
	var reason := Encounters.reason_for(c, rng)
	if not AIClient.is_mock():
		var notes: Array = c.get("memory_notes", [])
		if not notes.is_empty():
			var r: Dictionary = await AIClient.chat(Encounters.ai_messages(c, str(notes[rng.randi() % notes.size()])), {"max_tokens": 60})
			if bool(r.get("ok", false)) and str(r.get("text", "")).strip_edges() != "" and not bool(r.get("offline", false)):
				reason = str(r.text).strip_edges().substr(0, 200)
	if not is_inside_tree() or not is_instance_valid(world) or room_id != GameState.current_room_id or not world.actors.has(id):
		_encounter_pending = false
		return
	var actor: Node3D = world.actors[id]
	var to: Vector2i = world.room.nav.best_neighbor(world.player.cell(), actor.cell())
	if to.x >= 0:
		var path: Array[Vector2i] = world.room.nav.path(actor.cell(), to)
		var pts: Array[Vector3] = []
		for p in path:
			pts.append(world.room.cell_center(p))
		if not pts.is_empty():
			actor.walk(pts)
			var t0 := Time.get_ticks_msec()
			while is_instance_valid(actor) and actor.is_inside_tree() and actor.is_moving() and Time.get_ticks_msec() - t0 < 6000:
				await get_tree().process_frame
	_encounter_pending = false
	if not is_instance_valid(actor) or not actor.is_inside_tree() or room_id != GameState.current_room_id or not world.main.panels.is_empty():
		return
	actor.emote("!", Color("#ffd166"))
	var p: Control = ChoicePanel.new()
	world.main.open_panel(p)
	p.ask("%s wants to battle" % str(c.get("name", "")), "\"%s\"" % reason, [
		["Accept", func(): open_setup(id)],
		["Not now", func():
			if is_instance_valid(actor): actor.emote("♪")],
	])


## You asked for it (a chat, the menu, a Battle Spot): choose how to fight.
## Battles are a Dream World thing: in your real home they gently say no.
func _not_here() -> bool:
	if load("res://scripts/world/realms.gd").is_light(world.room.data):
		GameState.notify("No battles at home. They happen in the Dream World.")
		return true
	return false


func open_setup(foe_id: String = "") -> void:
	if _not_here():
		return
	var p: Control = load("res://scripts/battle/battle_setup_panel.gd").new()
	world.main.open_panel(p)
	p.setup_battle(self, foe_id)


## "I want to fight" in a chat with `id`: offer a battle with them (Not now costs nothing).
func chat_asked(id: String) -> void:
	var c := GameState.get_character(id)
	if c.is_empty() or screen:
		return
	var p: Control = ChoicePanel.new()
	world.main.open_panel(p)
	p.ask("A friendly battle?", "%s grins. \"You're on!\"" % str(c.get("name", "")), [
		["Let's go", func():
			world.dialogue.close_box()
			open_setup(id)],
		["Not now", func(): pass],
	])


## The Battle Maker on its own (Menu > Battle Maker), starting from a friendly spar against `foe_id`.
func open_maker(foe_id: String = "") -> void:
	var ids: Array = world.actors.keys() if not world.actors.is_empty() else Array(SaveManager.list_characters())
	var fid := foe_id if foe_id != "" else (str(ids[0]) if not ids.is_empty() else "")
	var foe := GameState.get_character(fid)
	var m: Control = load("res://scripts/battle/battle_maker.gd").new()
	world.main.open_panel(m)
	m.setup_maker(self, BattleData.from_template("friendly_spar", foe if not foe.is_empty() else {"name": "Someone"}))


## The Maker's Test: the whole battle, then back to the Maker.
func test_from_maker(b: Dictionary, keep: Dictionary) -> void:
	await start(b, [])
	reopen_maker(b, keep)


## Back to the Maker after a Test, as it was (its section, enemy and wave).
func reopen_maker(b: Dictionary, keep: Dictionary) -> void:
	if not is_inside_tree() or not is_instance_valid(world):
		return
	var m: Control = load("res://scripts/battle/battle_maker.gd").new()
	world.main.open_panel(m)
	m.setup_maker(self, b)
	for k in keep:
		m.set(k, keep[k])
	m.refresh()


## A Battle Spot: the friend it names, else the nearest friend here.
func use_spot(o: Dictionary) -> void:
	var foe := str(o.get("foe", ""))
	if foe == "" or not world.actors.has(foe):
		var best := 1e9
		for id in world.actors:
			var d: float = world.actors[id].position.distance_to(world.player.position)
			if d < best:
				best = d
				foe = str(id)
	if foe == "":
		GameState.notify("Nobody here to battle. Bring a friend!")
		return
	open_setup(foe)


## Solo by default; an invitation adds up to two friends with their own moves.
func party_for(friend_ids: Array, battle: Dictionary = {}) -> Array:
	var me := GameState.player_name()
	var out: Array = [BattleState.member("player", me if me.strip_edges() != "" else "You", 40, 6, 2)]
	if bool(battle.get("allow_party", false)):
		var candidates: Array = friend_ids if not friend_ids.is_empty() else world.actors.keys()
		for id in candidates:
			if out.size() >= 3:
				break
			var cid := str(id)
			if battle.get("enemies", []).any(func(e): return str(e.get("character", "")) == cid) or out.any(func(m): return str(m.id) == cid):
				continue
			var c := GameState.get_character(cid)
			if not c.is_empty():
				out.append(BattleState.member(cid, str(c.get("name", "Friend")), 40, 6, 2))
	var roles: Array = battle.get("party_roles", Spells.ROLES)
	var spells: Array = battle.get("party_spells", [])
	for i in out.size():
		var role := str(roles[i]) if i < roles.size() else str(Spells.ROLES[i])
		out[i].role = role
		out[i].spells = Spells.clean_ids(spells[i] if i < spells.size() else null, role)
	return out


## Snacks from your bag that heal: every Consumable (15 HP, or its "HP" stat). Battles never take
## anything from your bag: using one in a fight is pretend, so the bag stays as it is.
func healing_items() -> Array:
	return BattleInventory.new().items()


## Use the same sprite as the encountered actor, including their current form.
## An explicit Battle Maker picture takes priority; a missing file falls back.
func enemy_texture(enemy: Dictionary) -> Texture2D:
	var picture := str(enemy.get("picture", ""))
	if picture != "":
		if picture.begins_with("res://assets/battles/") and picture.ends_with(".svg") and ResourceLoader.exists(picture):
			return load(picture) as Texture2D
		var custom: Texture2D = SaveManager.load_texture(picture)
		if custom:
			return custom
	var id := str(enemy.get("character", ""))
	var actor: Node = world.actors.get(id)
	if is_instance_valid(actor) and actor.sprite and actor.sprite.texture:
		return actor.anim.base_texture if actor.anim and actor.anim.base_texture else actor.sprite.texture
	var c := GameState.get_character(id)
	return world.dark.look_for(world.talk.textures_for(c).get("neutral")) if not c.is_empty() else null


## Starts a battle on screen. Returns the summary when it ends.
func start(battle: Dictionary, friend_ids: Array = []) -> Dictionary:
	if screen or starting or _not_here():
		return {}
	battle = BattleData.clean(battle)
	if battle.is_empty() or battle.enemies.is_empty():
		GameState.notify("This battle needs an enemy.")
		return {}
	starting = true
	var room_id := GameState.current_room_id
	world.music.hold()   # the battle brings its own music: the world's waits where it is
	var m: Control = Moment.begin(world.main)   # the encounter flash: skippable
	preload("res://scripts/core/synth.gd").play(world, "motif_battle", 0.4)
	# The battle's song (its own, else the battle theme: Settings > Music), or Polox's own tune, made
	# meanwhile (a second or so on a phone) off the main thread.
	var song := MusicPlayer.battle_path(battle)
	var holder := {"stream": MusicPlayer.load_stream(song) if song != "" else null}
	var task := -1
	if holder.stream == null and str(battle.get("music", "")) != "@silence":
		task = WorkerThreadPool.add_task(func() -> void: holder["stream"] = load("res://scripts/battle/battle_audio.gd").loop(hash(str(battle.get("name", "battle")))))
		_music_task = task
	await m.wait(0.15 if Moment.reduced() else 0.45)
	if task >= 0:
		var t0 := Time.get_ticks_msec()
		while not WorkerThreadPool.is_task_completed(task) and Time.get_ticks_msec() - t0 < 4000:
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		_music_task = -1
	if is_instance_valid(m): m.finish()
	starting = false
	if not is_inside_tree() or not is_instance_valid(world) or room_id != GameState.current_room_id:
		if is_instance_valid(world):
			world.music.release()
		return {}
	screen = BattleScreen.new()
	var foes_faces: Array = []
	for e in battle.get("enemies", []):
		foes_faces.append(enemy_texture(e))
	# Your own picture as the world shows it (its resting frame, not a passing blink or step).
	var me: Node = world.player
	var party_faces: Array = [me.anim.base_texture if me.anim and me.anim.base_texture else me.sprite.texture]
	var members := party_for(friend_ids, battle)
	for member in members.slice(1):
		var c := GameState.get_character(str(member.id))
		party_faces.append(world.dark.look_for(world.talk.textures_for(c).get("neutral")) if not c.is_empty() else null)
	var assists: Dictionary = GameState.settings.get("battle_assists", {}) if GameState.settings.get("battle_assists") is Dictionary else {}
	var transaction := BattleInventory.new()
	transaction.begin()
	screen.setup(battle, members, party_faces, foes_faces, transaction.items(), SaveManager.root, assists, hash(str(battle.get("name", ""))))
	screen.item_transaction = transaction
	screen.state.consume_item = transaction.consume
	screen.auto_friends = not bool(GameState.settings.get("battle_choose_for_friends", false))
	screen.music_stream = holder.stream
	world.main.open_panel(screen)
	world.hud.visible = false
	# The end of the battle, or the screen going away without one (the world closing under it): either way
	# the HUD comes back and nothing waits on a screen that's gone.
	var ended := {"summary": null}
	var s: Control = screen
	s.finished.connect(func(sum: Dictionary): ended.summary = sum, CONNECT_ONE_SHOT)
	while ended.summary == null and is_instance_valid(s) and s.is_inside_tree():
		await get_tree().process_frame
	screen = null
	if is_instance_valid(world) and world.hud:
		world.hud.visible = true
	if is_instance_valid(world):
		world.music.release()   # the world's song carries on from where it paused
	if not ended.summary is Dictionary:
		return {}
	var summary: Dictionary = ended.summary
	after(battle, summary)
	if world.get("signatures"):
		world.signatures.home_after_battle.call_deferred(summary)
	return summary


func _exit_tree() -> void:
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1


## The kind aftermath: the Battle Log, a Memory Book page for a spare, a little closeness. Nothing
## is ever lost (a knock-down costs nothing, and snacks eaten in battle are pretend: the bag stays as it was).
## The battle's reward (Battle Maker > Rules), given once per win or spare.
func _reward(battle: Dictionary) -> void:
	var rw: Dictionary = BattleData.clean_rewards(battle.get("rewards", {}))
	var item := str(rw.item)
	if item != "" and preload("res://scripts/items/items.gd").exists(item):
		preload("res://scripts/items/inventory.gd").add(item, int(rw.count))
		var item_name := str(preload("res://scripts/items/items.gd").load_item(item).get("name", item))
		GameState.notify("🎁 %s%s%s" % [item_name, " x%d" % int(rw.count) if int(rw.count) > 1 else "", ("  " + str(rw.note)) if str(rw.note) != "" else ""])
	elif str(rw.note) != "":
		GameState.notify(str(rw.note))


func after(battle: Dictionary, summary: Dictionary) -> void:
	var logbook: Array = GameState.world.get("battle_log", []) if GameState.world.get("battle_log") is Array else []
	logbook.append(summary)
	while logbook.size() > LOG_MAX:
		logbook.pop_front()
	GameState.world["battle_log"] = logbook
	GameState.save_world()
	var outcome := str(summary.get("outcome", ""))
	if outcome in ["won", "spared"]:
		_reward(battle)
	for e in battle.get("enemies", []):
		var cid := str(e.get("character", ""))
		var c := GameState.get_character(cid)
		if c.is_empty():
			continue
		if outcome == "spared":
			c["affinity"] = clampf(float(c.get("affinity", 0.0)) + 0.03, -1.0, 1.0)
			GameState.save_character(c)
			GameState.add_moment("A friendly battle", "You and %s fought for fun, and you spared each other. \"%s\"" % [str(c.get("name", "")), str(e.get("lines", {}).get("spared", "That was fun."))], cid, "battle")
		elif outcome == "won":
			c["affinity"] = clampf(float(c.get("affinity", 0.0)) + 0.01, -1.0, 1.0)
			GameState.save_character(c)
