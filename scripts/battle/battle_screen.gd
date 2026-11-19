extends Control
## A friendly spar on screen (battle_state.gd has the rules):
## the enemies at the top (bobbing, flinching when hit, sparkling when spared), the battle box in the
## middle, your party at the bottom with HP, their plan for the turn and the TP bar, and six big
## command buttons. One hand is enough: everything is a tap or a click (the FIGHT bars: tap anywhere;
## dodging: your heart follows your finger or the mouse, at a capped speed). Keys are optional:
## arrows/WASD, Z or Enter, X or Q.
##
##   intro -> (menu -> choose a command, a target) per member -> review (Back takes a plan back)
##   -> Begin turn -> one FIGHT bar per fighter -> what happened, line by line -> the enemies' turn
##   (a warning, then dodge) -> menu ... -> the end: won / spared / ran / knocked down (Try again)

signal finished(summary: Dictionary)

const BattleState := preload("res://scripts/battle/battle_state.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")
const BattleSkin := preload("res://scripts/battle/battle_skin.gd")
const Spells := preload("res://scripts/battle/battle_spells.gd")
const BattleAudio := preload("res://scripts/battle/battle_audio.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Synth := preload("res://scripts/core/synth.gd")
const BulletArt := preload("res://scripts/battle/bullet_art.gd")
const Field := preload("res://scripts/battle/bullet_field.gd")
const Motion := preload("res://scripts/battle/heart_motion.gd")
const ArenaView := preload("res://scripts/battle/battle_arena_view.gd")
const BattleData := preload("res://scripts/battle/battle_data.gd")
const BattleLook := preload("res://scripts/battle/battle_look.gd")

const HEART_SPEED := 170.0          # px/s: the heart follows the pointer at most this fast
const HEART_R := 5.0
## Collision steps a second while dodging (every bullet is worked out again at each step). A phone takes
## half as many, and draws the battle at 60 fps at most: the fight stays smooth instead of heating up.
const STEPS_PC := 240.0
const STEPS_PHONE := 120.0
const PHONE_FPS := 60
const INVULN_S := 1.0
const FIGHT_BAR_S := 1.4            # the cursor crosses the bar in this long
const COMMAND_ICONS := {"fight": "⚔", "act": "💬", "magic": "✦", "item": "📦", "spare": "✦", "defend": "🛡"}
const COMMAND_NAMES := {"fight": "FIGHT", "act": "ACT", "magic": "MAGIC", "item": "ITEM", "spare": "SPARE", "defend": "DEFEND"}

var state: RefCounted               # battle_state.gd
var battle: Dictionary = {}
var skin: RefCounted                # battle_skin.gd
var faces: Dictionary = {}          # enemy index -> Texture2D; "party_<i>" -> Texture2D
var bag: Array = []                 # [{name, heal}] healing items you can use
var auto_friends := true            # Simple: friends choose for themselves
var phase := "intro"
var member := 0                     # whose turn it is to choose
var picks: Array = []               # [{cmd, target, arg}]
var text := ""
var text_queue: Array = []
var box := Rect2()                  # the battle box on screen
var box_target := Rect2()
var heart := Vector2.ZERO           # in box coordinates
var pointer_down := false
var pointer := Vector2.ZERO         # in screen coordinates
var wave: Dictionary = {}
var look: Dictionary = {}           # the battle's Presentation: backdrop, effect, intro line (battle_data.gd clean_look)
var wave_t := 0.0
var wave_enemy := 0
var invuln := 0.0
var grazed: Dictionary = {}         # bullet key -> true
var bar_x := 0.0
var bar_dir := 1.0
var fx: Array = []                  # [{kind, pos, t, life, ...}]
var shake := 0.0
var flash := 0.0
var turns_taken := 0
var music: AudioStreamPlayer
var buttons: GridContainer        # 5 across, or 3 + 2 on an upright phone
var sub: GridContainer             # the ACT / ITEM / DEFEND choices, inside the box
var sub_scroll: ScrollContainer     # (long lists scroll; drag or wheel)
var list_with_text := false         # the end: what happened stays above Done / Try again
var _t := 0.0
var _heart_times := PackedFloat64Array()
var _heart_points := PackedVector2Array()
var _heart_count := 0
var buttons_h := 64.0
var music_stream: AudioStream       # the battle's loop, made before the screen opens
var _arena := Vector2(240, 160)
var _arena_scale := 1.0
var field := Field.new()
var motion := Motion.new()
var _warnings: Array = []
var _mode_hint := ""
var _telegraph_hint := ""
var _rotation := 0.0
var _heart_sampler: Callable
var _finger := -1
var _using_touch := false
var _keyboard_steering := false
var _touch_origin := Vector2.ZERO
var _touch_heart := Vector2.ZERO
var _telegraph := 0.0
var _wave_owners: Array = []
var _text_generation := 0
var _finished := false
var item_transaction: RefCounted
var _pause_button: Button
var paused := false
var _fighters: Array = []           # members still to press their FIGHT bar this turn
var _fighter := -1                  # whose bar is running
var _timings: Dictionary = {}       # who -> where they pressed (0..1); given to the rules at once
var _after_text := "enemy"          # what follows the lines: "enemy" (their turn) or "round" (yours)
var _graze_sound_at := -1.0
var _world_viewport: Viewport
var _previous_disable_3d := false
var _phone := preload("res://scripts/core/device.gd").is_handheld()
var _capped_fps := false


func setup(b: Dictionary, members: Array, member_faces: Array, enemy_faces: Array, items: Array, save_root: String, assist: Dictionary = {}, seed_n: int = 1) -> void:
	battle = b
	state = BattleState.new()
	var foes: Array = []
	for i in (b.get("enemies", []) as Array).size():
		var e: Dictionary = b.enemies[i]
		var foe := BattleState.enemy(e)
		foe["waves"] = e.get("waves", [])
		foes.append(foe)
		if i < enemy_faces.size():
			faces[i] = enemy_faces[i]
	for i in member_faces.size():
		faces["party_%d" % i] = member_faces[i]
	state.setup(members, foes, seed_n, assist, BattleData.clean_rules(b.get("rules", {})))
	look = BattleData.clean_look(b.get("look", {}))
	_heart_times.resize(int(STEPS_PC * 15) + 4)
	_heart_points.resize(_heart_times.size())
	_heart_sampler = _heart_when
	bag = items.duplicate(true)
	state.items = bag
	skin = BattleSkin.load_from(save_root)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	# The opaque battle screen covers the world. Stop drawing that entire 3D
	# scene while it is hidden, and restore it even when the panel is closed.
	_world_viewport = get_viewport()
	_previous_disable_3d = _world_viewport.disable_3d
	_world_viewport.disable_3d = true
	if _phone and (Engine.max_fps == 0 or Engine.max_fps > PHONE_FPS):
		Engine.max_fps = PHONE_FPS
		_capped_fps = true
	buttons = GridContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	add_child(buttons)
	_pause_button = UiKit.button("Pause", func():
		paused = not paused
		_pause_button.text = "Resume" if paused else "Pause", 100)
	_pause_button.position = Vector2(12, 10)
	add_child(_pause_button)
	var back_button := UiKit.button("Back", func(): on_back(), 90)
	back_button.position = Vector2(120, 10)
	add_child(back_button)
	sub_scroll = ScrollContainer.new()
	sub_scroll.scroll_deadzone = preload("res://scripts/ui/ui_kit.gd").touch_deadzone()
	sub_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sub_scroll)
	sub = GridContainer.new()
	sub.add_theme_constant_override("h_separation", 6)
	sub.add_theme_constant_override("v_separation", 6)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_scroll.add_child(sub)
	music = AudioStreamPlayer.new()
	music.volume_db = linear_to_db(maxf(0.001, float(GameState.settings.get("music_volume", 0.7)) * 0.5))
	music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM   # (a song: streamed in the browser too, as in music_player.gd)
	add_child(music)
	resized.connect(_layout)
	_layout()
	_intro()


func _layout() -> void:
	var sz := size if size.x > 0 else get_viewport_rect().size
	var narrow := sz.x < 600.0   # (an upright phone: the TP bar moves above the party, the box can be wider)
	var bw := minf(sz.x - (24.0 if narrow else 68.0), 560.0)
	var bh := clampf(sz.y * 0.26, 120.0, 200.0)
	if phase == "review":
		bh = maxf(bh, 142.0 + _button_height(52.0))
	box_target = Rect2(maxf((sz.x - bw) / 2.0, 12.0 if narrow else 48.0), sz.y * 0.36, bw, bh)
	if box.size == Vector2.ZERO:
		box = box_target
	var bwide := minf(sz.x - 24.0, 760.0)
	buttons.columns = 6 if sz.x >= 720.0 else 3
	var rows := 1 if buttons.columns == 6 else 2
	buttons_h = _button_height(64.0) * rows + 8.0 * (rows - 1)
	buttons.position = Vector2((sz.x - bwide) / 2.0, sz.y - buttons_h - 16.0)
	buttons.size = Vector2(bwide, buttons_h)
	if phase in ["dodge", "telegraph"]:
		_fit_arena()
	_place_sub()


func _place_sub() -> void:
	if list_with_text:   # a row along the bottom of the box, under the words
		var height := _button_height(52.0)
		sub_scroll.position = Vector2(box_target.position.x + 10, box_target.end.y - height - 10)
		sub_scroll.size = Vector2(box_target.size.x - 20, height)
	else:
		sub_scroll.position = Vector2(box_target.position.x + 10, box_target.position.y + 10)
		sub_scroll.size = Vector2(box_target.size.x - 20, box_target.size.y - 20)


# --- Flow -----------------------------------------------------------------------------------------

func _intro() -> void:
	phase = "intro"
	flash = 1.0
	Synth.play(self, "fanfare", 0.45)
	var foe: Dictionary = state.enemies[0] if not state.enemies.is_empty() else {}
	var opening := str(look.get("intro", ""))   # (Presentation: the battle's own opening line wins)
	_say(opening if opening != "" else str(foe.get("lines", {}).get("intro", "%s wants a friendly fight!" % str(foe.get("name", "Someone")))))
	if music_stream:
		_start_music(music_stream)   # (made during the encounter flash: battle_director.gd)
	await get_tree().create_timer(0.9 if not _fast() else 0.3).timeout   # (a tap skips it: _tap)
	if phase == "intro":
		_begin_round()


func _say(t: String) -> void:
	text = t


func _start_music(stream: AudioStream) -> void:
	if is_instance_valid(music) and is_inside_tree():
		music.stream = stream
		# An add-on's song can ask to sit louder or quieter (its gain_db, music_player.gd).
		music.volume_db += preload("res://scripts/world/music_player.gd").gain_db(str(stream.get_meta(&"path", "")))
		music.play()


func _begin_round() -> void:
	picks = []
	state.queue.clear()
	member = 0
	_next_member()


func _next_member() -> void:
	member = state.next_member()
	if member < 0:
		_review()
		return
	if member > 0 and auto_friends:
		var picked := _auto_pick(member)
		if state.plan(member, picked) == "":
			picks = state.queue.duplicate(true)
			_next_member()
			return
	phase = "menu"
	_build_commands()


func _review() -> void:
	phase = "review"
	_layout()
	var lines := PackedStringArray()
	for i in state.party.size():
		var label := _plan_label(i)
		if label != "":
			lines.append("%s: %s" % [state.party[i].name, label])
	text = "\n".join(lines) + "\nTP after choices: %d" % int(state.preview().get("tp", state.tp))
	_list([["Begin turn", func(): _resolve()], ["Back", func(): revise()]], true)


## What a member will do this turn, in a few words ("" if nothing: down, or not chosen yet).
func _plan_label(i: int) -> String:
	var a: Dictionary = state.planned(i)
	match str(a.get("cmd", "")):
		"":
			return ""
		"help":
			return "helps %s" % str(state.party[int(a.with)].name)
		"magic":
			return str(Spells.BOOK.get(str(a.spell), {}).get("name", "MAGIC"))
		"act":
			var act: Dictionary = state.enemies[int(a.target)].acts[int(a.arg)]
			return str(act.get("name", "ACT"))
		"item":
			return "%s for %s" % [str(bag[int(a.arg)].get("name", "a snack")), str(state.party[int(a.target)].name)]
		"fight", "spare":
			return "%s %s" % [str(a.cmd).to_upper(), str(state.enemies[int(a.target)].name)]
	return str(a.cmd).to_upper()


## Back: the last plan is taken back (its TP, snack and helpers are free again) and that member chooses again.
func revise() -> void:
	var who: int = state.undo_choice()
	if who < 0:
		_build_commands()
		return
	BattleAudio.sfx(self, "back")
	member = who
	picks = state.queue.duplicate(true)
	phase = "menu"
	_build_commands()


## A friend choosing for themselves (Simple): kind first, a FIGHT when you're fighting.
func _auto_pick(i: int) -> Dictionary:
	var t := _first_enemy()
	if t < 0:
		return {"cmd": "defend"}
	if state.can_spare(t):
		return {"cmd": "spare", "target": t}
	var mine: Dictionary = picks[0] if not picks.is_empty() else {}
	if str(mine.get("cmd", "")) == "fight":
		return {"cmd": "fight", "target": t, "arg": 0.45 + state.rng.randf() * 0.1}
	var acts: Array = state.enemies[t].acts
	for k in acts.size():
		if int(acts[k].get("mercy", 0)) > 0 and int(acts[k].get("helpers", 0)) == 0 and int(acts[k].get("tp", 0)) <= int(state.preview().get("tp", 0)):
			return {"cmd": "act", "target": t, "arg": k}
	return {"cmd": "defend"}


func _first_enemy() -> int:
	return state.first_active()


func _clear_sub() -> void:
	for c in sub.get_children():
		sub.remove_child(c)   # (gone at once, so the new list's buttons keep their places and names)
		c.queue_free()
	sub_scroll.visible = false   # (never in the way of the heart or the FIGHT tap)
	list_with_text = false


func _build_commands() -> void:
	phase = "menu"
	for c in buttons.get_children():
		buttons.remove_child(c)
		c.queue_free()
	_clear_sub()
	_say("Your turn. What will you do?" if member == 0 else "%s's turn. What will they do?" % str(state.party[member].name))
	for cmd in BattleState.COMMANDS:
		var b := Button.new()
		b.text = "%s %s" % [COMMAND_ICONS[cmd], COMMAND_NAMES[cmd]]
		b.custom_minimum_size = Vector2(0, _button_height(64.0))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20 if buttons.columns == 6 else 18)
		if skin and skin.has(cmd):
			b.icon = skin.get_tex(cmd)
			b.expand_icon = true
			b.text = ""
		b.name = "Cmd_" + cmd
		b.pressed.connect(func(): choose(cmd))
		buttons.add_child(b)
	buttons.visible = true


## A command button (also what tests and keys call).
func choose(cmd: String) -> void:
	if phase != "menu":
		return
	BattleAudio.sfx(self, "select")
	match cmd:
		"fight":
			# Who to hit now; the timing press comes when the turn begins (one bar per fighter).
			_targets(false, func(t): _pick({"cmd": "fight", "target": t}))
		"act":
			_targets(false, func(t): _list(_act_options(t)))
		"magic":
			_list(_magic_options())
		"item":
			_list(_item_options())
		"spare":
			_targets(false, func(t): _pick({"cmd": "spare", "target": t}))
		"defend":
			var opts: Array = [["Defend (half damage, +TP)", func(): _pick({"cmd": "defend"})]]
			if int(state.preview().get("tp", 0)) >= BattleState.RALLY_COST:
				opts.append(["Rally: heal everyone (%d TP)" % BattleState.RALLY_COST, func(): _pick({"cmd": "rally"})])
			opts.append(["Run away (no harm done)", func(): _pick({"cmd": "run"})])
			if not state.queue.is_empty():
				opts.append(["Revise last friend", func(): revise()])
			opts.append(["Back", func(): _build_commands()])
			_list(opts)


func _targets(ally: bool, picked: Callable) -> void:
	var opts: Array = []
	var targets: Array = state.party if ally else state.enemies
	for i in targets.size():
		if not ally and not state.valid_enemy(i):
			continue
		var t: Dictionary = targets[i]
		var suffix := (" (down)" if bool(t.down) else " %d/%d HP" % [t.hp, t.max_hp]) if ally else (" [SPARE]" if state.can_spare(i) else (" [TIRED]" if bool(t.get("tired", false)) else ""))
		opts.append([str(t.name) + suffix, func(): picked.call(i)])
	if opts.size() == 1:
		opts[0][1].call()
		return
	opts.append(["Back", func(): _build_commands()])
	_list(opts)


func _magic_options() -> Array:
	var out: Array = []
	for id in state.party[member].get("spells", []):
		var s: Dictionary = Spells.BOOK[id]
		out.append(["%s (%d TP)" % [s.name, s.tp], func():
			if str(s.target) == "party":
				_pick({"cmd": "magic", "spell": id, "target": member})
			else:
				_targets(str(s.target) == "ally", func(t): _pick({"cmd": "magic", "spell": id, "target": t}))])
	out.append(["Back", func(): _build_commands()])
	return out


func _act_options(t: int = -1) -> Array:
	if t < 0:
		t = _first_enemy()
	var out: Array = []
	if t < 0:
		return [["Back", func(): _build_commands()]]
	var acts: Array = state.enemies[t].acts
	for k in acts.size():
		var a: Dictionary = acts[k]
		if int(a.get("helpers", 0)) >= state.party.size():
			continue
		var cost := int(a.get("tp", 0))
		var team := " +%d friend" % int(a.helpers) if int(a.get("helpers", 0)) > 0 else ""
		out.append(["%s%s%s" % [str(a.get("name", "Act")), (" (%d TP)" % cost) if cost > 0 else "", team], func(): _pick({"cmd": "act", "target": t, "arg": k})])
	out.append(["Back", func(): _build_commands()])
	return out


func _item_options() -> Array:
	var out: Array = []
	for i in bag.size():
		var it: Dictionary = bag[i]
		var count := int(state.preview().get("stock", {}).get(i, 0))
		if count > 0:
			out.append(["%s x%d (+%d HP)" % [str(it.get("name", "Snack")), count, int(it.get("heal", 10))], func(): _targets(true, func(t): _pick({"cmd": "item", "arg": i, "target": t}))])
	if bag.is_empty():
		out.append(["(Nothing to eat in your bag)", func(): pass])
	out.append(["Back", func(): _build_commands()])
	return out


func _list(options: Array, keep_text := false) -> void:
	_clear_sub()
	list_with_text = keep_text
	if not keep_text:
		text = ""
	_place_sub()
	if keep_text:
		sub.columns = maxi(1, options.size())
	else:
		sub.columns = 2 if options.size() > 3 and sub_scroll.size.x >= 320.0 else 1
	for o in options:
		var b := Button.new()
		b.text = str(o[0])
		if o.size() > 2: b.tooltip_text = str(o[2])
		b.custom_minimum_size = Vector2(0, _button_height(52.0))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(o[1])
		sub.add_child(b)
	sub_scroll.scroll_vertical = 0
	sub_scroll.visible = true
	buttons.visible = false


func _button_height(base: float) -> float:
	if not is_inside_tree() or not preload("res://scripts/ui/touch_gestures.gd").phone_layout():
		return base
	return maxf(base, ceilf(48.0 / maxf(0.1, get_viewport().get_screen_transform().get_scale().y)))


func _pick(p: Dictionary) -> void:
	var err: String = state.plan(member, p)
	if err != "":
		GameState.notify(err)
		return
	picks = state.queue.duplicate(true)
	_clear_sub()
	_next_member()


## Begin turn: first a FIGHT bar for each member who chose FIGHT (friends who chose for themselves
## already have their timing), then everything plays.
func _resolve() -> void:
	if phase != "review":
		return
	_timings.clear()
	_fighters.clear()
	for a in state.queue:
		if str(a.cmd) == "fight" and not a.has("arg"):
			_fighters.append(int(a.who))
	_fighters.sort()
	_fight_next()


func _fight_next() -> void:
	if _fighters.is_empty():
		_fighter = -1
		for who in _timings:
			state.set_timing(int(who), float(_timings[who]))
		_play_turn()
		return
	_fighter = int(_fighters.pop_front())
	phase = "fight_bar"
	bar_x = 0.0
	bar_dir = 1.0
	buttons.visible = false
	_clear_sub()
	text = "%s: tap when the line is in the middle!" % str(state.party[_fighter].name)


## FIGHT: the press on the timing bar (tap anywhere, Z, Space).
func press_fight() -> void:
	if phase != "fight_bar" or _fighter < 0:
		return
	_timings[_fighter] = bar_x
	BattleAudio.sfx(self, "press")
	_fight_next()


## Everyone's plans happen, one line at a time; then the enemies' turn (or the end).
func _play_turn() -> void:
	phase = "text"
	buttons.visible = false
	_clear_sub()
	var lines: Array = []
	for event in state.resolve_queue():
		lines.append_array(event.lines)
		_feedback(event)
	text_queue = lines
	_after_text = "enemy"
	_text_generation += 1
	_advance_text()


## What a played plan looks and sounds like: a slash and the damage, a heal over a friend, MERCY
## rising, a sparkle for SPARE / Hush.
func _feedback(event: Dictionary) -> void:
	if bool(event.get("cancelled", false)):
		return
	var target := int(event.target)
	var amount := int(event.get("amount", 0))
	match str(event.get("kind", "")):
		"damage":
			if target >= 0 and target < state.enemies.size():
				_fx("slash", _enemy_pos(target), 0.35)
				_fx("number", _enemy_pos(target) + Vector2(0, -50), 0.9, {"text": str(amount)})
				_hurt_enemy(target)
			BattleAudio.sfx(self, "spell" if str(event.cmd) == "magic" else "hit")
		"heal":
			for healed in event.get("healed", []):
				_fx("number", _member_pos(int(healed.who)) + Vector2(0, -40), 0.9, {"text": "+%d" % int(healed.amount), "color": Color("#7ad6b0")})
			BattleAudio.sfx(self, "heal")
		"mercy":
			if target >= 0 and target < state.enemies.size():
				_fx("hearts", _enemy_pos(target), 0.8)
				if amount > 0:
					_fx("number", _enemy_pos(target) + Vector2(0, -50), 0.9, {"text": "+%d%%" % roundi(100.0 * amount / maxf(1.0, float(state.enemies[target].mercy_max))), "color": ThemeBuilder.YELLOW})
			BattleAudio.sfx(self, "act")
		"spare":
			if target >= 0 and target < state.enemies.size():
				_fx("sparkles", _enemy_pos(target), 1.2)
			BattleAudio.sfx(self, "spare")


func _advance_text() -> void:
	if text_queue.is_empty():
		if state.outcome != "":
			_end()
		elif phase == "text" and _after_text == "round":
			_begin_round()
		elif phase == "text":
			_enemy_turn()
		return
	text = str(text_queue.pop_front())
	var generation := _text_generation
	await get_tree().create_timer(0.9 if not _fast() else 0.25).timeout
	if is_inside_tree() and phase == "text" and generation == _text_generation:
		_advance_text()


func _fast() -> bool:
	return bool(GameState.settings.get("reduce_motion", false))


func _enemy_turn() -> void:
	if _first_enemy() < 0:
		_end()
		return
	# The rules plan the turn: every enemy still here attacks together, taking turns in the lead.
	var plan: Dictionary = state.turn_plan(turns_taken)
	if plan.is_empty():
		_end_wave()   # (everyone is sitting this one out)
		return
	wave = plan.wave
	_wave_owners = plan.owners
	wave_enemy = int(plan.lead)
	BattleAudio.sfx(self, "telegraph")
	var bw := float(wave.get("box", {}).get("w", 240))
	var bh := float(wave.get("box", {}).get("h", 160))
	_arena = Vector2(bw, bh)
	_fit_arena()
	heart = Vector2(bw, bh) / 2.0
	pointer = box_target.position + heart * _arena_scale
	pointer_down = false
	wave_t = 0.0
	grazed.clear()
	_heart_count = 1
	_heart_times[0] = 0.0
	_heart_points[0] = heart
	invuln = 0.0
	_rotation = 0.0
	_finger = -1
	phase = "telegraph"
	_telegraph = float(wave.get("telegraph", 0.8))
	field.reset(wave)
	motion.reset(str(wave.get("mode", "free")))
	_warnings = Patterns.origins(wave)
	_mode_hint = str(wave.get("hint", ""))
	if _mode_hint == "":
		_mode_hint = ArenaView.HINTS.get(motion.mode, ArenaView.HINTS.free)
	_telegraph_hint = "Ready: " + _mode_hint
	BulletArt.prepare_wave(wave)
	var idle: Array = state.enemies[wave_enemy].get("lines", {}).get("idle", [])
	text = str(idle[turns_taken % idle.size()]) if not idle.is_empty() else ""


func _fit_arena() -> void:
	# As big as fits between the enemies' names and the party (up to 1.6x on a tall phone screen, so
	# bullets stay readable under a thumb).
	var c := Vector2(size.x * (0.5 if size.x < 600.0 else 0.52), size.y * 0.49)   # (clear of a tall TP bar)
	var room_y := 2.0 * (c.y - size.y * 0.34)
	var dimensions: Dictionary = wave.box
	var maximum := Vector2(maxf(float(dimensions.w), float(dimensions.get("end_w", dimensions.w))), maxf(float(dimensions.h), float(dimensions.get("end_h", dimensions.h))))
	var a := absf(deg_to_rad(float(wave.get("rotation", 0))))
	var rotated := Vector2(maximum.x * cos(a) + maximum.y * sin(a), maximum.y * cos(a) + maximum.x * sin(a))
	_arena_scale = minf(1.6, minf((size.x - 70.0) / rotated.x, room_y / rotated.y))
	_arena_scale = maxf(0.25, _arena_scale)
	box_target = Rect2(c - _arena * _arena_scale / 2.0, _arena * _arena_scale)


func _end_wave() -> void:
	var before: int = state.said.size()
	state.end_enemy_turn()
	turns_taken += 1
	phase = "menu"   # (before the layout: in the dodge phase it would keep the arena's box size)
	_layout()
	if state.outcome != "":
		_end()
		return
	# Anyone getting back up says so before your turn.
	var lines: Array = state.said.slice(before)
	if lines.is_empty():
		phase = "menu"
		_begin_round()
		return
	BattleAudio.sfx(self, "up")
	phase = "text"
	text_queue = lines
	_after_text = "round"
	_text_generation += 1
	_advance_text()


func _end() -> void:
	phase = "end"
	_text_generation += 1
	if state.outcome in ["knocked_down", "ran"] and item_transaction:
		item_transaction.refund()
	buttons.visible = false
	_clear_sub()
	var foe: Dictionary = state.enemies[0] if not state.enemies.is_empty() else {}
	match state.outcome:
		"won":
			text = str(foe.get("lines", {}).get("won", "%s is tired out. You win!" % foe.get("name", "")))
			BattleAudio.sfx(self, "victory")
		"spared":
			text = str(foe.get("lines", {}).get("spared", "You spared %s. Friends again!" % foe.get("name", "")))
			for i in state.enemies.size():
				_fx("sparkles", _enemy_pos(i), 1.5)
			BattleAudio.sfx(self, "victory")
		"ran":
			text = "You got away. No harm done."
		"knocked_down":
			text = "Everyone's knocked down... Try again starts the battle over. Nothing is lost."
			_fx("recover", size / 2.0, 1.6)
			BattleAudio.sfx(self, "defeat")
	var opts: Array = [["Done", func(): finish()]]
	if state.outcome == "knocked_down":
		opts.push_front(["Try again", func(): retry()])
	_list(opts, true)


func retry() -> void:
	if item_transaction:
		item_transaction.refund()
		bag = item_transaction.items()
	state.recover()
	state.items = bag
	turns_taken = 0
	_timings.clear()
	_fighters.clear()
	phase = "menu"
	_layout()
	_begin_round()


func finish() -> void:
	if _finished:
		return
	_finished = true
	if item_transaction:
		if state.outcome in ["won", "spared"]:
			item_transaction.commit()
		else:
			item_transaction.refund()
	if music:
		music.stop()
	finished.emit(state.summary(str(battle.get("name", "Battle"))))
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_world_viewport):
		_world_viewport.disable_3d = _previous_disable_3d
	if _capped_fps:
		Engine.max_fps = preload("res://scripts/core/graphics.gd").frame_cap()
		_capped_fps = false
	_text_generation += 1
	if item_transaction:
		item_transaction.refund() # no-op after a committed victory; also covers panel/world closure
	# The battle's song is let go here, not left to the player being freed: a game that closes
	# mid-battle would otherwise shut down with the song's file still in use (audio_exit.gd).
	preload("res://scripts/core/audio_exit.gd").release(music)


# --- The enemy's turn: your heart and the bullets ---------------------------------------------------

func _process(delta: float) -> void:
	if paused:
		return
	_t += delta
	box.position = box.position.lerp(box_target.position, minf(1.0, delta * 10.0))
	box.size = box.size.lerp(box_target.size, minf(1.0, delta * 10.0))
	flash = maxf(0.0, flash - delta * 2.5)
	shake = maxf(0.0, shake - delta * 3.0)
	for f in fx:
		f.t = float(f.t) + delta
	var i := fx.size() - 1
	while i >= 0:
		if float(fx[i].t) >= float(fx[i].life):
			fx.remove_at(i)
		i -= 1
	if phase == "fight_bar":
		bar_x += bar_dir * delta / FIGHT_BAR_S
		if bar_x >= 1.0:
			bar_x = 1.0
			press_fight()   # (a miss still lands softly: the ends of the bar give 30%)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if paused:
		return
	if phase == "telegraph":
		_telegraph -= delta
		if _telegraph <= 0.0:
			box = box_target
			phase = "dodge"
	elif phase == "dodge":
		var left := minf(delta, 0.1) * float(battle.get("speed", 1.0))
		var most := 1.0 / (STEPS_PHONE if _phone else STEPS_PC)
		while left > 0.00001 and phase == "dodge":
			var step := minf(left, most)
			_dodge(step)
			left -= step


func _dodge(delta: float) -> void:
	wave_t += delta
	_arena = Patterns.box_at(wave, wave_t)
	_rotation = Patterns.rotation_at(wave, wave_t)
	_fit_arena()
	box = box_target
	var aim := screen_to_arena(pointer)
	var direction := Vector2.ZERO
	var key := Input.get_vector("move_left", "move_right", "move_up", "move_down") if InputMap.has_action("move_left") else Vector2.ZERO
	if key != Vector2.ZERO:
		_keyboard_steering = true
		direction = key.rotated(-_rotation)
	var pointer_active := pointer_down or (not _using_touch and not _keyboard_steering and not DisplayServer.is_touchscreen_available())
	if key == Vector2.ZERO and pointer_active:
		if _using_touch:
			aim = _touch_heart + ((pointer - _touch_origin) / _arena_scale + Vector2(0, -42.0 / _arena_scale)).rotated(-_rotation)
		direction = ((aim - heart) / maxf(0.001, HEART_SPEED * motion.speed_scale * delta)).limit_length(1.0)
	var confirm := Input.is_action_pressed("confirm") or Input.is_action_pressed("ui_accept")
	var jumping := Input.is_action_pressed("move_up") or confirm or (pointer_down and aim.y < heart.y - 12)
	var firing := pointer_down or confirm or Input.is_physical_key_pressed(KEY_Z)
	var previous := heart
	var hazard := hazard_at(heart)
	motion.speed_scale = float(state.rules.get("soul_speed", 1.0)) * (0.5 if hazard == "slow" else 1.0)
	heart = motion.step(heart, direction, aim if pointer_active else heart, _arena, delta, jumping, firing)
	if hazard_at(heart) == "hurt" and invuln <= 0.0:
		var hz_dmg: int = state.hit(wave_enemy)
		invuln = INVULN_S
		shake = 0.0 if _fast() else 1.0
		_fx("number", arena_to_screen(heart) + Vector2(0, -20), 0.8, {"text": "-%d" % hz_dmg, "color": Color("#e86a8a")})
		BattleAudio.sfx(self, "hurt")
		if state.outcome != "":
			_end()
			return
	var moving := heart.distance_squared_to(previous) > delta * delta
	if _heart_count < _heart_times.size():
		_heart_times[_heart_count] = wave_t
		_heart_points[_heart_count] = heart
		_heart_count += 1
	invuln = maxf(0.0, invuln - delta)
	var big := bool(state.assists.get("big_graze", false))
	field.sample(wave_t, _arena, _heart_sampler)
	for i in field.count:
		var b := field.slots[i]
		if field.removed(b):
			continue
		if motion.blocks_bullet(heart, b.position, 6 * b.scale):
			field.remove(b)
			motion.blocks += 1
			state.graze()
			continue
		if b.fragile and motion.breaks_bullet(b.position, 6 * b.scale):
			field.remove(b)
			state.graze()
			continue
		if not Motion.hurts(b.rule, moving):
			continue
		var d := BulletArt.distance(b.kind, b.position, b.scale, heart)
		if d < HEART_R - 1.0:
			if invuln <= 0.0:
				var owner: int = _wave_owners[b.spawner] if b.spawner < _wave_owners.size() else wave_enemy
				var dmg: int = state.hit(owner)
				invuln = INVULN_S
				shake = 0.0 if _fast() else 1.0   # (Reduce motion: no shaking)
				_fx("number", arena_to_screen(heart) + Vector2(0, -20), 0.8, {"text": "-%d" % dmg, "color": Color("#e86a8a")})
				var hit_who: int = state.last_hit
				if hit_who >= 0:
					set_meta("hurt_party_%d" % hit_who, _t)   # (their card flinches: who took it)
					_fx("number", _member_pos(hit_who) + Vector2(0, -40), 0.8, {"text": "-%d" % dmg, "color": Color("#e86a8a")})
				BattleAudio.sfx(self, "down" if hit_who >= 0 and bool(state.party[hit_who].down) else "hurt")
				if state.outcome != "":
					_end()
					return
		elif d < HEART_R + (26.0 if big else 14.0) and field.graze_once(b):
			state.graze()
			_fx("graze", arena_to_screen(heart), 0.3)
			if _t - _graze_sound_at > 0.09:   # (a fan of grazes is one sparkle of sound, not a buzz)
				_graze_sound_at = _t
				BattleAudio.sfx(self, "graze")
	if wave_t >= float(wave.get("duration", 6.0)):
		_end_wave()


## The hazard zone under a point in the box ("hurt", "slow" or "" for none).
func hazard_at(at: Vector2) -> String:
	for h in wave.get("hazards", []):
		var r := Rect2(Vector2(float(h.x), float(h.y)) * _arena, Vector2(float(h.w), float(h.h)) * _arena)
		if r.has_point(at):
			return str(h.kind)
	return ""


func screen_to_arena(at: Vector2) -> Vector2:
	return (at - box.get_center()).rotated(-_rotation) / _arena_scale + _arena / 2


func arena_to_screen(at: Vector2) -> Vector2:
	return box.get_center() + (at - _arena / 2).rotated(_rotation) * _arena_scale


func _heart_when(t: float) -> Variant:
	# Aimed bullets repeatedly ask about old samples. Binary search avoids
	# rescanning thousands of physics samples for every bullet, every substep.
	var lo := 0
	var hi := _heart_count - 1
	var found := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if _heart_times[mid] <= t:
			found = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return _heart_points[found] if found >= 0 else heart



# --- Input -----------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# A touch also produces a synthetic mouse event. It must not submit the next fighter's bar.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton:
		_using_touch = false
		_keyboard_steering = false
		pointer = event.position
		pointer_down = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_tap()
	elif event is InputEventMouseMotion:
		if event.relative != Vector2.ZERO:
			_keyboard_steering = false
		pointer = event.position
	elif event is InputEventScreenTouch:
		if event.pressed:
			if _finger >= 0:
				return
			_finger = event.index
			_touch_origin = event.position
			_touch_heart = heart
		elif event.index != _finger:
			return
		else:
			_finger = -1
		_using_touch = true
		_keyboard_steering = false
		pointer = event.position
		pointer_down = event.pressed
		if event.pressed:
			_tap()
	elif event is InputEventScreenDrag:
		if event.index == _finger:
			pointer = event.position


func _tap() -> void:
	if paused:
		return
	match phase:
		"fight_bar":
			press_fight()
		"intro":
			_begin_round()
		"text":
			_text_generation += 1
			_advance_text()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	if phase == "fight_bar" and (event.keycode in [KEY_Z, KEY_SPACE, KEY_ENTER]):
		press_fight()
		accept_event()


func on_back() -> bool:
	if phase == "review":
		revise()
	elif phase == "fight_bar":
		# Nothing has played yet: back to the review, every timing to press again.
		_timings.clear()
		_fighters.clear()
		_fighter = -1
		_review()
	elif phase == "menu" and sub_scroll.visible:
		_build_commands()
	elif phase == "menu" and not state.queue.is_empty():
		revise()
	elif phase == "menu":
		choose("defend")
	return true


# --- Drawing ---------------------------------------------------------------------------------------

func _enemy_pos(i: int) -> Vector2:
	var sz := size if size.x > 0 else get_viewport_rect().size
	var n := maxi(1, state.enemies.size())
	return Vector2(sz.x * (i + 1) / (n + 1), sz.y * 0.19)


func _hurt_enemy(i: int) -> void:
	set_meta("hurt_%d" % i, _t)


## A party member's card at the bottom (one per member, side by side, as wide as fits).
func _member_rect(i: int) -> Rect2:
	var sz := size if size.x > 0 else get_viewport_rect().size
	var n: int = maxi(1, state.party.size())
	var w := minf(240.0, (sz.x - 24.0 - (n - 1) * 8.0) / n)
	var command_space := buttons_h if phase == "menu" else 0.0
	return Rect2(Vector2((sz.x - (w * n + (n - 1) * 8)) / 2 + i * (w + 8), sz.y - command_space - 128.0), Vector2(w, 100))


func _member_pos(i: int) -> Vector2:
	return _member_rect(clampi(i, 0, maxi(0, state.party.size() - 1))).get_center()


func _fx(kind: String, pos: Vector2, life: float, extra: Dictionary = {}) -> void:
	var f := {"kind": kind, "pos": pos, "t": 0.0, "life": minf(life, 0.4) if _fast() else life}   # (Reduce motion: short fades)
	f.merge(extra)
	fx.append(f)


## One frame, back to front: the backdrop, the enemies, the box (or the arena while you dodge), your party,
## the TP bar, then the effects and anything that covers the whole screen.
func _draw() -> void:
	var sz := size if size.x > 0 else get_viewport_rect().size
	var off := Vector2(randf_range(-4, 4), randf_range(-4, 4)) * shake
	_draw_backdrop(sz)
	_draw_enemies(sz, off)
	_draw_box(sz, off)
	_draw_party(sz)
	_draw_tp(sz)
	_draw_effects()
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, flash))
	if paused:
		draw_string(ThemeDB.fallback_font, Vector2(0, sz.y * 0.5), "Paused", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 32, ThemeBuilder.YELLOW)


func _draw_backdrop(sz: Vector2) -> void:
	if skin and skin.has("background"):
		draw_texture_rect(skin.get_tex("background"), Rect2(Vector2.ZERO, sz), false)
	else:
		BattleLook.backdrop(self, sz, str(look.get("backdrop", "black")), _t, _fast())
	BattleLook.effect(self, sz, str(look.get("effect", "none")), _t, _fast())


## Each enemy on stage: its face (or a paper creature), its name, its mercy bar and, once hurt, its HP.
func _draw_enemies(sz: Vector2, off: Vector2) -> void:
	for i in state.enemies.size():
		var e: Dictionary = state.enemies[i]
		if bool(e.get("waiting", false)):
			continue   # (One after another: not on stage yet)
		var still := _fast()   # (Reduce motion: no bobbing or wobbling)
		var p := _enemy_pos(i) + Vector2(0, 0.0 if still else sin(_t * 2.0 + i) * 6.0) + off
		var hurt_t := _t - float(get_meta("hurt_%d" % i, -9.0))
		if hurt_t < 0.4 and not still:
			p.x += sin(hurt_t * 60.0) * 8.0 * (1.0 - hurt_t / 0.4)
		var tex: Texture2D = faces.get(i)
		var alpha := 0.35 if bool(e.spared) else (0.6 if bool(e.tired_out) else 1.0)
		var tint := Color(1, 1, 1, alpha) if hurt_t >= 0.15 else Color(3, 3, 3, alpha)
		if tex:
			var h := sz.y * 0.2
			var w := h * tex.get_width() / maxf(1.0, tex.get_height())
			draw_texture_rect(tex, Rect2(p - Vector2(w / 2.0, h / 2.0), Vector2(w, h)), false, tint)
		else:
			_draw_friend(p, i, Color("#c9b6ff", alpha))
		var name_w := minf(220.0, sz.x / (state.enemies.size() + 1) * 0.95)
		var name_size := 22 if sz.x < 600.0 else 18
		draw_multiline_string(ThemeDB.fallback_font, p + Vector2(-name_w / 2.0, sz.y * 0.12 - (name_size if name_w < 150.0 else 0)), str(e.name), HORIZONTAL_ALIGNMENT_CENTER, name_w, name_size, 2, ThemeBuilder.CREAM)
		var mercy := float(e.mercy) / maxf(1.0, float(e.mercy_max))
		var bar := Rect2(p + Vector2(-50, sz.y * 0.13), Vector2(100, 10))
		_meter(bar, mercy, Color("#ffd166"))
		if int(e.hp) < int(e.max_hp):
			var hb := Rect2(bar.position + Vector2(0, 14), Vector2(100, 8))
			_meter(hb, float(e.hp) / maxf(1.0, float(e.max_hp)), Color("#7ad6b0"))


## The box and what is in it: the arena while you dodge, the timing bar while you strike, else the words.
func _draw_box(sz: Vector2, off: Vector2) -> void:
	var bx := Rect2(box.position + off, box.size)
	if phase not in ["dodge", "telegraph"]:
		draw_rect(bx, Color(0, 0, 0, 0.85))
		if skin and skin.has("box"):
			draw_texture_rect(skin.get_tex("box"), bx.grow(6), false)
		else:
			draw_rect(bx, Color.WHITE, false, 4.0)
	if phase in ["dodge", "telegraph"]:
		ArenaView.draw(self, off)
	elif phase == "fight_bar":
		var bar := Rect2(bx.position + Vector2(20, bx.size.y / 2.0 - 18), Vector2(bx.size.x - 40, 36))
		draw_rect(bar, Color("#24124a"))
		draw_rect(Rect2(bar.get_center() - Vector2(bar.size.x * 0.075, 18), Vector2(bar.size.x * 0.15, 36)), Color("#ffd166", 0.5))
		var cx := bar.position.x + bar.size.x * bar_x
		draw_rect(Rect2(cx - 3, bar.position.y - 6, 6, 48), Color.WHITE)
	if text != "" and phase != "dodge" and (sub.get_child_count() == 0 or list_with_text):
		draw_multiline_string(ThemeDB.fallback_font, bx.position + Vector2(16, 32), "* " + text, HORIZONTAL_ALIGNMENT_LEFT, bx.size.x - 32, 20, 4 if phase == "review" else 3, ThemeBuilder.CREAM)
	elif text != "" and phase == "dodge" and _mode_hint == "":
		var line_w := minf(sz.x - 24.0, maxf(bx.size.x, 360.0))   # (under the box: above it are the enemies)
		draw_multiline_string(ThemeDB.fallback_font, Vector2((sz.x - line_w) / 2.0, bx.end.y + 24), text, HORIZONTAL_ALIGNMENT_CENTER, line_w, 22 if sz.x < 600.0 else 16, 2, ThemeBuilder.MUTED)


## Your party's cards: face, name, HP, and what each will do this turn.
func _draw_party(sz: Vector2) -> void:
	var n: int = state.party.size()
	for i in n:
		var m: Dictionary = state.party[i]
		var r := _member_rect(i)
		var w := r.size.x
		var flinch := _t - float(get_meta("hurt_party_%d" % i, -9.0))
		if flinch < 0.3 and not _fast():
			r.position.x += sin(flinch * 70.0) * 5.0 * (1.0 - flinch / 0.3)
		draw_rect(r, Color("#3a1426") if flinch < 0.2 else Color("#1d1736"))
		draw_rect(r, ThemeBuilder.YELLOW if i == member and phase == "menu" else Color(ThemeBuilder.CREAM, 0.4), false, 2.0)
		var face: Texture2D = faces.get("party_%d" % i)
		var show_face := face != null and w >= 200
		if show_face:
			draw_texture_rect(face, Rect2(r.position + Vector2(4, 4), Vector2(44, 44)), false, Color(1, 1, 1, 0.4 if bool(m.down) else 1.0))
		var inset := 54.0 if show_face else 6.0
		draw_string(ThemeDB.fallback_font, r.position + Vector2(inset, 22), str(m.name).left(12), HORIZONTAL_ALIGNMENT_LEFT, w - inset - 6, 22 if sz.x < 600.0 else 16, ThemeBuilder.CREAM)
		var hb := Rect2(r.position + Vector2(inset, 29), Vector2(w - inset - 8, 12))
		_meter(hb, float(m.hp) / maxf(1.0, float(m.max_hp)), Color("#ffd166"))
		var status := "%d/%d" % [m.hp, m.max_hp]
		if bool(m.down):
			status = "DOWN (up in %d)" % maxi(1, int(m.get("rest", 1)))
		draw_string(ThemeDB.fallback_font, r.position + Vector2(inset, 62), status, HORIZONTAL_ALIGNMENT_LEFT, w - inset - 4, 20 if sz.x < 600.0 else 14, ThemeBuilder.YELLOW if bool(m.down) else ThemeBuilder.MUTED)
		if phase in ["menu", "review"]:
			var plan: Dictionary = state.planned(i)
			var command := str(plan.get("cmd", ""))
			var label := str(COMMAND_NAMES.get(command, command.to_upper()))
			draw_string(ThemeDB.fallback_font, r.position + Vector2(6, 88), label, HORIZONTAL_ALIGNMENT_LEFT, w - 12, 20 if sz.x < 600.0 else 14, ThemeBuilder.MUTED)


## TP: a tall bar on the left, or (an upright phone, where the box needs that width) a long one
## just above the party.
func _draw_tp(sz: Vector2) -> void:
	var fill := float(state.tp) / BattleState.TP_MAX
	var narrow := sz.x < 600.0
	var tpr := Rect2(16, sz.y * 0.36, 22, sz.y * 0.4)
	if narrow:
		tpr = Rect2(78, _member_rect(0).position.y - 26, sz.x - 94, 14)
	if skin and skin.has("tp"):
		draw_texture_rect(skin.get_tex("tp"), tpr.grow(4), false)
	_meter(tpr, fill, Color("#ff9f43"), not narrow)
	if narrow:
		draw_string(ThemeDB.fallback_font, Vector2(12, tpr.end.y - 1), "TP %d" % state.tp, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ThemeBuilder.CREAM)
	else:
		draw_string(ThemeDB.fallback_font, tpr.position + Vector2(-4, -6), "TP %d" % state.tp, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ThemeBuilder.CREAM)


## Slashes, numbers, hearts and sparkles, grazes, and the line when someone gets back up.
func _draw_effects() -> void:
	for f in fx:
		var k := float(f.t) / float(f.life)
		var p: Vector2 = f.pos
		match str(f.kind):
			"slash":
				draw_line(p + Vector2(-60, -60).lerp(Vector2(60, 60), k * 0.3), p + Vector2(-60, -60).lerp(Vector2(60, 60), minf(1.0, k * 1.6)), Color(1, 1, 1, 1.0 - k), 6.0)
			"number":
				draw_string(ThemeDB.fallback_font, p + Vector2(-40, -k * 30.0), str(f.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, 80, 28, Color(f.get("color", ThemeBuilder.YELLOW), 1.0 - k))
			"hearts", "sparkles":
				for j in 8:
					var a := TAU * j / 8.0 + k * 2.0
					var q := p + Vector2.from_angle(a) * (30.0 + 50.0 * k) + Vector2(0, -40.0 * k)
					if str(f.kind) == "hearts":
						BulletArt.draw_heart(self, q, 6.0, Color("#ff8fb8", 1.0 - k))
					else:
						draw_circle(q, 4.0 * (1.0 - k) + 1.0, Color("#fff3c4", 1.0 - k))
			"graze":
				for j in 5:
					draw_line(p, p + Vector2.from_angle(TAU * j / 5.0 + k) * (8.0 + 16.0 * k), Color("#ffffff", 1.0 - k), 2.0)
			"recover":
				var up := ease(k, 0.4)
				draw_string(ThemeDB.fallback_font, p + Vector2(-200, 40 - up * 40.0), "...and back up!", HORIZONTAL_ALIGNMENT_CENTER, 400, 30, Color(ThemeBuilder.YELLOW, minf(1.0, k * 3.0)))


## Original paper creatures for encounters without a player's portrait.
func _draw_friend(p: Vector2, index: int, tint: Color) -> void:
	var r := minf(36, size.x / maxf(8, state.enemies.size() * 5))
	var kind := index % 3
	if str(battle.get("demo", "")) == "lantern_lesson": kind = 1
	if kind == 0:
		draw_colored_polygon(PackedVector2Array([p + Vector2(-r, -r * 0.4), p + Vector2(-r * 0.8, -r * 1.5), p + Vector2(-r * 0.2, -r * 0.8), p + Vector2(r * 0.2, -r * 0.8), p + Vector2(r * 0.8, -r * 1.5), p + Vector2(r, -r * 0.4), p + Vector2(0, r)]), Color("#e9af72", tint.a))
	elif kind == 1:
		for sign in [-1, 1]:
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(sign * r * 1.4, -r), p + Vector2(sign * r * 1.2, r * 0.7), p + Vector2(sign * r * 0.4, r)]), Color("#7ad6b0", tint.a))
		draw_circle(p, r * 0.6, Color("#ffd166", tint.a))
	else:
		draw_circle(p, r, tint)
		for j in 8:
			var q := p + Vector2.from_angle(j * TAU / 8) * r * 1.3
			draw_line(p, q, Color("#ffd166", tint.a), 3)
	for side in [-1, 1]:
		draw_circle(p + Vector2(side * r * 0.25, -r * 0.15), 3, Color("#1d1736", tint.a))
	draw_arc(p + Vector2(0, r * 0.15), r * 0.2, 0.15, PI - 0.15, 8, Color("#1d1736", tint.a), 2)


## [GLASS_UI] A meter with depth: a track sunk into the screen (dark, with a shadow under its top edge
## and a light outline, so it reads on a dark battle and on a bright skin alike) and a glossy fill (a
## lighter top, a darker bottom; on a tall bar the gloss runs down its left side). `vertical` fills
## from the bottom up.
func _meter(r: Rect2, fill: float, col: Color, vertical: bool = false) -> void:
	fill = clampf(fill, 0.0, 1.0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#0d0a18")
	track.border_color = Color(ThemeBuilder.CREAM, 0.42)
	track.set_border_width_all(1)
	track.set_corner_radius_all(int(minf(r.size.x, r.size.y) / 2.0))
	track.anti_aliasing = true
	draw_style_box(track, r.grow(1.0))
	draw_rect(Rect2(r.position, Vector2(r.size.x, minf(2.0, r.size.y * 0.25))), Color(0, 0, 0, 0.45))
	if fill <= 0.0:
		return
	var f := Rect2(r.position, Vector2(r.size.x * fill, r.size.y))
	if vertical:
		f = Rect2(r.position + Vector2(0, r.size.y * (1.0 - fill)), Vector2(r.size.x, r.size.y * fill))
	draw_rect(f, col)
	if vertical:
		draw_rect(Rect2(f.position, Vector2(f.size.x * 0.38, f.size.y)), Color(1, 1, 1, 0.3))
		draw_rect(Rect2(f.position + Vector2(f.size.x * 0.75, 0), Vector2(f.size.x * 0.25, f.size.y)), Color(0, 0, 0, 0.2))
	else:
		draw_rect(Rect2(f.position, Vector2(f.size.x, f.size.y * 0.45)), Color(1, 1, 1, 0.32))
		draw_rect(Rect2(f.position + Vector2(0, f.size.y * 0.75), Vector2(f.size.x, f.size.y * 0.25)), Color(0, 0, 0, 0.22))
