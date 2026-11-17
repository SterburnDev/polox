extends RefCounted
## The rules of a battle, without any drawing (battle_screen.gd shows it; tests drive it directly).
##
## A party of up to three (you and two friends) faces up to three enemies. Each turn every standing
## member plans one command: FIGHT (a timing press while the turn plays), ACT (something kind or silly
## from that enemy's list: it fills their MERCY; some make them TIRED or slow, some need a friend's
## help), MAGIC (the member's own spells, paid with TP), ITEM (a real snack from your bag, for anyone,
## even someone who's down), SPARE (when their MERCY is full) or DEFEND (half damage, +TP). Planning
## only reserves TP, snacks and helpers; Back takes the last plan back. Then the turn plays in a fixed
## order: DEFEND, ACT, ITEM and Rally, spells, SPARE and Hush, FIGHT, and party order within each
## (so an ACT can make someone TIRED or spareable for a friend's Hush or SPARE the same turn). A FIGHT
## or a damaging spell whose target already left turns to the next enemy; an ACT, SPARE or Hush for
## someone who left is cancelled and costs nothing. Then the enemies' turn: dodge with your heart;
## grazing a bullet fills TP. Someone knocked down gets back up after a while, or at once when healed.
## Outcomes are always kind: won (they're tired out, never hurt for real), spared, ran, or knocked
## down (Try again starts the battle over; nothing is lost).

const COMMANDS: PackedStringArray = ["fight", "act", "magic", "item", "spare", "defend"]
const Spells := preload("res://scripts/battle/battle_spells.gd")
const Patterns := preload("res://scripts/battle/patterns.gd")
const TP_MAX := 100
const GRAZE_TP := 3
const DEFEND_TP := 16
const RALLY_COST := 32         # a party-wide heal, paid with TP
const TIRED_AT := 0.25         # below a quarter of their HP, an enemy gets TIRED (Hush works then)
const DOWN_TURNS := 3          # a knocked-down member is back up after this many enemy turns

var party: Array = []          # [{id, name, hp, max_hp, attack, defense, defending, down, rest, role, spells}]
var enemies: Array = []        # [{id, name, hp, max_hp, attack, defense, mercy, mercy_max, acts, lines, waves, spared, tired_out, tired, tired_at, slow, skip_wave}]
var tp := 0
var turn := 0
var outcome := ""              # "" while fighting; "won" | "spared" | "ran" | "knocked_down"
var said: Array = []            # what happened, in words (the Battle Log keeps the summary)
var assists: Dictionary = {}   # {story: bool, slow_bullets: bool, wide_timing: bool, big_graze: bool}
var rng := RandomNumberGenerator.new()
var queue: Array = []           # accepted plans, in the order they were chosen
var items: Array = []           # [{id, name, heal, count}] the bag's snacks
var consume_item := Callable()  # live inventory transaction, supplied by the director
var last_hit := -1             # who the last bullet landed on (-1: nobody)
var _initial: Dictionary = {}
var _seed := 1
var _resolving := false
var _last_amount := 0


static func member(id: String, member_name: String, max_hp: int = 40, attack: int = 6, defense: int = 2, role: String = "guide") -> Dictionary:
	return {"id": id, "name": member_name, "hp": maxi(1, max_hp), "max_hp": maxi(1, max_hp), "attack": maxi(1, attack), "defense": maxi(0, defense), "defending": false, "down": false, "rest": 0, "role": role, "spells": Spells.for_role(role)}


static func enemy(def: Dictionary) -> Dictionary:
	var max_hp := clampi(int(def.get("hp", 60)), 1, 9999)
	return {
		"id": str(def.get("id", "enemy")), "name": str(def.get("name", "Someone")), "character": str(def.get("character", "")),
		"hp": max_hp, "max_hp": max_hp, "attack": clampi(int(def.get("attack", 5)), 0, 99), "defense": clampi(int(def.get("defense", 1)), 0, 99),
		"mercy": 0, "mercy_max": clampi(int(def.get("mercy_max", 100)), 1, 1000), "acts": def.get("acts", []), "lines": def.get("lines", {}),
		"waves": def.get("waves", []), "phases": def.get("phases", []), "next_wave": -1, "spared": false, "tired_out": false,
		"tired": bool(def.get("tired", false)), "tired_at": clampf(float(def.get("tired_at", TIRED_AT)), 0.0, 1.0), "slow": 0, "skip_wave": false,
		"order": str(def.get("order", "cycle")),
	}


## The battle's Rules (battle_data.gd clean_rules): damage, how you win, how enemies line up.
var rules: Dictionary = {"win": "any", "survive_turns": 5, "damage": 1.0, "soul_speed": 1.0, "lineup": "together"}


func setup(members: Array, foes: Array, seed_n: int = 1, assist: Dictionary = {}, battle_rules: Dictionary = {}) -> void:
	if not battle_rules.is_empty():
		rules = battle_rules.duplicate()
	party = members.slice(0, 3).duplicate(true)
	for m in party:
		m["rest"] = int(m.get("rest", 0))
	enemies = foes.slice(0, 3).duplicate(true)
	if str(rules.get("lineup", "together")) == "one_by_one":
		for i in range(1, enemies.size()):
			enemies[i]["waiting"] = true   # steps in when the one before is spared or tired out
	tp = 0
	turn = 0
	outcome = ""
	said = []
	assists = assist
	rng.seed = seed_n
	_seed = seed_n
	queue.clear()
	_initial = {"party": party.duplicate(true), "enemies": enemies.duplicate(true)}


func active_enemies() -> Array:
	return enemies.filter(func(e): return not bool(e.spared) and not bool(e.tired_out) and not bool(e.get("waiting", false)))


func standing() -> Array:
	return party.filter(func(m): return not bool(m.down))


func first_active() -> int:
	for i in enemies.size():
		if valid_enemy(i):
			return i
	return -1


## How good a FIGHT press was: 1.0 at the exact middle of the bar, down to 0.3 at the ends
## (Wide timing makes the sweet spot bigger). `x` is where the cursor was, 0..1.
func timing_quality(x: float) -> float:
	var off := absf(x - 0.5) * 2.0
	var window := 0.35 if bool(assists.get("wide_timing", false)) else 0.15
	if off <= window:
		return 1.0
	return clampf(1.0 - (off - window) / (1.0 - window) * 0.7, 0.3, 1.0)


func fight(who: int, target: int, x: float) -> int:
	if not can_act(who) or not valid_enemy(target):
		return 0
	var m: Dictionary = party[who]
	var e: Dictionary = enemies[target]
	var q := timing_quality(x)
	var dmg := maxi(1, int(round((int(m.attack) * 2.2 - int(e.defense)) * q * (1.0 + rng.randf() * 0.15))))
	if bool(assists.get("story", false)):
		dmg = maxi(dmg, int(e.max_hp) / 3)
	e.hp = maxi(0, int(e.hp) - dmg)
	tp = mini(TP_MAX, tp + int(round(4.0 + q * 4.0)))
	_say("%s hits %s for %d%s" % [m.name, e.name, dmg, " (perfect!)" if q >= 1.0 else ""])
	_after_damage(target)
	_check_end()
	return dmg


## An ACT: its text, its mercy (and TP cost, if any). Returns the text to show ("" if it can't).
func act(who: int, target: int, act_index: int) -> String:
	if not can_act(who) or not valid_enemy(target):
		return ""
	var e: Dictionary = enemies[target]
	var acts: Array = e.acts
	if act_index < 0 or act_index >= acts.size():
		return ""
	var a: Dictionary = acts[act_index]
	var cost := clampi(int(a.get("tp", 0)), 0, TP_MAX)
	if cost > tp and not _resolving:
		return "Not enough TP (%d needed)." % cost
	if not _resolving:
		tp -= cost
	var mercy := maxi(0, int(a.get("mercy", 20)))
	var was_full := int(e.mercy) >= int(e.mercy_max)
	e.mercy = clampi(int(e.mercy) + mercy, 0, int(e.mercy_max))
	var text := str(a.get("text", "%s and %s share a moment." % [party[who].name, e.name]))
	if text.strip_edges() == "":
		text = "%s and %s share a moment." % [party[who].name, e.name]
	_say(text)
	if bool(a.get("tired", false)):
		_make_tired(target)
	if int(a.get("slow", 0)) > 0:
		e.slow = maxi(int(e.slow), int(a.get("slow", 0)))
		_say("%s's next attack will be slower." % e.name)
	if bool(a.get("skip_wave", false)) and not bool(e.skip_wave):
		e.skip_wave = true
		_say("%s will sit the next attack out." % e.name)
	var next := int(a.get("next_wave", -1))
	if next >= 0 and next < (e.waves as Array).size():
		e.next_wave = next
		_say("Next: %s." % str(e.waves[next].get("name", "a quieter turn")))
	if int(e.mercy) >= int(e.mercy_max) and not was_full:
		_say("%s doesn't want to fight anymore. (SPARE them!)" % e.name)
	return text


func check_text(target: int) -> String:
	if target < 0 or target >= enemies.size():
		return "They have already settled down."
	var e: Dictionary = enemies[target]
	return "%s  -  HP %d/%d  ATK %d  DEF %d  -  %s" % [e.name, e.hp, e.max_hp, e.attack, e.defense, str(e.lines.get("check", "They look ready for a friendly fight."))]


func can_spare(target: int) -> bool:
	if not valid_enemy(target):
		return false
	var e: Dictionary = enemies[target]
	return int(e.mercy) >= int(e.mercy_max) or bool(assists.get("story", false))


func spare(who: int, target: int) -> bool:
	if not can_act(who) or not valid_enemy(target):
		return false
	var e: Dictionary = enemies[target]
	if not can_spare(target):
		_say("%s offers MERCY, but %s isn't ready to stop yet." % [party[who].name, e.name])
		return false
	e.spared = true
	_say("%s spared %s." % [party[who].name, e.name])
	_check_end()
	return true


func defend(who: int) -> void:
	if not can_act(who) or bool(party[who].defending):
		return
	party[who].defending = true
	if not _resolving:
		tp = mini(TP_MAX, tp + DEFEND_TP)
	_say("%s gets ready." % party[who].name)


## Heals a member (a snack, a spell, Rally). Someone who's down gets back up. Returns the HP gained.
func heal(who: int, amount: int, quiet: bool = false) -> int:
	if who < 0 or who >= party.size() or outcome != "":
		return 0
	var m: Dictionary = party[who]
	var before := int(m.hp)
	m.hp = mini(int(m.max_hp), int(m.hp) + maxi(0, amount))
	var gained := int(m.hp) - before
	if not quiet:
		_say("%s recovers %d HP." % [m.name, gained] if gained > 0 else "%s is already full of energy." % m.name)
	if bool(m.down) and int(m.hp) > 0:
		m.down = false
		m.rest = 0
		_say("%s is back on their feet!" % m.name)
	return gained


func use_item(who: int, amount: int, item_name: String) -> void:
	if who < 0 or who >= party.size() or outcome != "":
		return
	_say("%s gets %s." % [party[who].name, item_name])
	heal(who, amount)


func rally() -> bool:
	if (tp < RALLY_COST and not _resolving) or outcome != "":
		return false
	if not _resolving:
		tp -= RALLY_COST
	_say("Everyone cheers each other on! (+30% HP)")
	for i in party.size():
		heal(i, int(party[i].max_hp) * 3 / 10, true)
	return true


func run_away() -> void:
	outcome = "ran"
	_say("You ran off. (No harm done.)")


## The enemy's turn: a bullet from enemy `damage_from` reached your heart. It lands on `who`, or a
## random standing member (`last_hit` says who). Returns the damage (0 in Story mode).
func hit(damage_from: int, who: int = -1) -> int:
	last_hit = -1
	if outcome != "" or bool(assists.get("story", false)):
		return 0
	var targets: Array = []
	for i in party.size():
		if not bool(party[i].down):
			targets.append(i)
	if targets.is_empty():
		return 0
	var mi: int = who if who >= 0 and who < party.size() and not bool(party[who].down) else int(targets[rng.randi() % targets.size()])
	var m: Dictionary = party[mi]
	var dmg := maxi(1, int(enemies[damage_from].attack) - int(m.defense) / 2) if damage_from >= 0 and damage_from < enemies.size() else 3
	if bool(m.defending):
		dmg = maxi(1, dmg / 2)
	dmg = maxi(1, roundi(dmg * float(rules.get("damage", 1.0))))
	m.hp = maxi(0, int(m.hp) - dmg)
	last_hit = mi
	if int(m.hp) == 0:
		m.down = true
		m.rest = DOWN_TURNS
		_say("%s is knocked down." % m.name)
	if standing().is_empty():
		outcome = "knocked_down"
		_say("Everyone's knocked down... and gets back up. Nothing is lost.")
	return dmg


func graze() -> void:
	tp = mini(TP_MAX, tp + GRAZE_TP * (2 if bool(assists.get("big_graze", false)) else 1))


func end_enemy_turn() -> void:
	turn += 1
	queue.clear()
	for m in party:
		m.defending = false
		if bool(m.down) and outcome == "":
			m.rest = int(m.get("rest", DOWN_TURNS)) - 1
			if int(m.rest) <= 0:
				m.down = false
				m.rest = 0
				m.hp = maxi(1, int(m.max_hp) / 4)
				_say("%s gets back up!" % m.name)
	for e in enemies:
		e.slow = maxi(0, int(e.slow) - 1)
		e.skip_wave = false
		e.next_wave = -1
	if str(rules.get("win", "any")) == "survive" and outcome == "" and turn >= int(rules.get("survive_turns", 5)):
		for e in enemies:
			e.spared = true
			e.erase("waiting")
		_say("You held on for %d turns! Everyone calls it a draw." % turn)
		outcome = "spared"
	_announce_phases()


## A phase with its own line says it once, the turn it begins.
func _announce_phases() -> void:
	for e in active_enemies():
		var stage := phase_index(e)
		if stage >= 0 and stage != int(e.get("_phase_said", -1)):
			e["_phase_said"] = stage
			var line := str((e.get("phases", [])[stage] as Dictionary).get("line", ""))
			if line != "":
				_say("%s: %s" % [e.name, line])


func _check_end() -> void:
	if outcome != "" or not active_enemies().is_empty():
		return
	for e in enemies:   # One after another: the next steps in
		if bool(e.get("waiting", false)):
			e.waiting = false
			_say("%s steps in!" % e.name)
			return
	outcome = "spared" if enemies.all(func(e): return bool(e.spared)) else "won"


func _say(text: String) -> void:
	said.append(text)


## Try again: the encounter exactly as it began (HP, MERCY, TP, turn and the random numbers);
## the director refunds the snacks this battle used.
func recover() -> void:
	party = _initial.get("party", []).duplicate(true)
	enemies = _initial.get("enemies", []).duplicate(true)
	outcome = ""
	tp = 0
	turn = 0
	queue.clear()
	said.clear()
	rng.seed = _seed
	_resolving = false
	last_hit = -1


func can_act(who: int) -> bool:
	return outcome == "" and who >= 0 and who < party.size() and not bool(party[who].down)


func valid_enemy(target: int) -> bool:
	return target >= 0 and target < enemies.size() and not bool(enemies[target].spared) and not bool(enemies[target].tired_out) and not bool(enemies[target].get("waiting", false))


func _after_damage(target: int) -> void:
	var e: Dictionary = enemies[target]
	if str(rules.get("win", "any")) == "spare" and int(e.hp) <= 1:
		e.hp = 1   # "Spare everyone": FIGHT can't tire them out, only mercy ends it
		_make_tired(target)
		return
	if int(e.hp) == 0:
		e.tired_out = true
		_say("%s is all tired out." % e.name)
	elif float(e.hp) <= float(e.max_hp) * float(e.tired_at):
		_make_tired(target)


func _make_tired(target: int) -> void:
	var e: Dictionary = enemies[target]
	if bool(e.tired) or not valid_enemy(target):
		return
	e.tired = true
	_say("%s is getting TIRED. (Hush helps them rest.)" % e.name)


func spell(who: int, id: String) -> Dictionary:
	if who < 0 or who >= party.size() or not id in party[who].get("spells", []) or not Spells.BOOK.has(id):
		return {}
	return Spells.BOOK[id]


func magic(who: int, target: int, id: String) -> bool:
	var s := spell(who, id)
	if not can_act(who) or s.is_empty() or (tp < int(s.tp) and not _resolving):
		return false
	if s.target == "enemy" and not valid_enemy(target):
		return false
	if s.target == "ally" and (target < 0 or target >= party.size()):
		return false
	if s.effect == "pacify" and not bool(enemies[target].tired) and not bool(assists.get("story", false)):
		_say("%s isn't TIRED yet. Hush waits; the TP stays with you." % enemies[target].name)
		return false
	if not _resolving:
		tp -= int(s.tp)
	_say("%s casts %s." % [party[who].name, s.name])
	match str(s.effect):
		"damage":
			var e: Dictionary = enemies[target]
			var damage := maxi(1, int(s.power) - int(e.defense))
			e.hp = maxi(0, int(e.hp) - damage)
			_say("%s takes %d. A shower of paper stars." % [e.name, damage])
			_after_damage(target)
			_last_amount = damage
		"heal":
			_last_amount = heal(target, int(s.power))
		"heal_all":
			_last_amount = 0
			for i in party.size():
				_last_amount += heal(i, int(s.power), true)
			_say("Everyone recovers %d HP." % int(s.power))
		"shield":
			for m in party:
				m.defending = true
			_say("Everyone is sheltered: half damage this turn.")
		"pacify":
			enemies[target].spared = true
			_say("%s settles down. A peaceful goodnight." % enemies[target].name)
	_check_end()
	return true


## Recomputed from the base state whenever a plan is added or taken back. Plans are paid in the
## order they were chosen, so a DEFEND can fund a later member's spell. Returns {ok, tp, used,
## stock, helpers: {who: [helper...]}, helping: {helper: who}} or {ok: false, error}.
func preview(proposed: Variant = null) -> Dictionary:
	var actions: Array = queue if proposed == null else proposed
	var available := tp
	var used := {}
	var stock := {}
	var helpers_of := {}
	var helping := {}
	for i in items.size():
		stock[i] = int(items[i].get("count", 0))
	for a in actions:
		var who := int(a.get("who", -1))
		if not can_act(who) or used.has(who):
			return {"ok": false, "error": "That friend already has a part this turn."}
		used[who] = true
		var cmd := str(a.get("cmd", ""))
		var target := int(a.get("target", -1))
		var cost := 0
		if cmd in ["fight", "act", "spare"] and not valid_enemy(target):
			return {"ok": false, "error": "Choose someone still in the battle."}
		match cmd:
			"act":
				var ai := int(a.get("arg", -1))
				if ai < 0 or ai >= (enemies[target].acts as Array).size():
					return {"ok": false, "error": "Choose an ACT."}
				var act_def: Dictionary = enemies[target].acts[ai]
				cost = clampi(int(act_def.get("tp", 0)), 0, TP_MAX)
				var need := clampi(int(act_def.get("helpers", 0)), 0, 2)
				var got: Array = []
				for j in party.size():
					if need > 0 and can_act(j) and not used.has(j):
						used[j] = true
						helping[j] = who
						got.append(j)
						need -= 1
				if need > 0:
					return {"ok": false, "error": "This ACT needs more free friends. Back can change their plans."}
				helpers_of[who] = got
			"magic":
				var s := spell(who, str(a.get("spell", "")))
				if s.is_empty():
					return {"ok": false, "error": "That friend doesn't know this spell."}
				if (s.target == "enemy" and not valid_enemy(target)) or (s.target == "ally" and (target < 0 or target >= party.size())):
					return {"ok": false, "error": "Choose a valid spell target."}
				cost = int(s.tp)
			"item":
				var ix := int(a.get("arg", -1))
				if not stock.has(ix) or int(stock[ix]) < 1:
					return {"ok": false, "error": "That snack is already promised this turn."}
				if target < 0 or target >= party.size():
					return {"ok": false, "error": "Choose a friend for the snack."}
				stock[ix] = int(stock[ix]) - 1
			"defend":
				available = mini(TP_MAX, available + DEFEND_TP)
			"rally":
				cost = RALLY_COST
			"fight", "spare", "run":
				pass
			_:
				return {"ok": false, "error": "Choose a battle command."}
		if cost > available:
			return {"ok": false, "error": "Not enough TP (%d needed, %d free)." % [cost, available]}
		available -= cost
	return {"ok": true, "tp": available, "used": used, "stock": stock, "helpers": helpers_of, "helping": helping}


func plan(who: int, action: Dictionary) -> String:
	if _resolving:
		return "The turn is already playing."
	var a := action.duplicate(true)
	a["who"] = who
	var candidate := queue.duplicate(true)
	candidate.append(a)
	var p := preview(candidate)
	if not bool(p.ok):
		return str(p.error)
	queue = candidate
	return ""


## Takes the last plan back (its TP, snack and helpers are free again). Returns whose it was (-1: none).
func undo_choice() -> int:
	if queue.is_empty() or _resolving:
		return -1
	var last: Dictionary = queue.pop_back()
	return int(last.who)


func next_member() -> int:
	var p := preview()
	var used: Dictionary = p.get("used", {})
	for i in party.size():
		if can_act(i) and not used.has(i):
			return i
	return -1


## What member `who` will do this turn: their own plan, {"cmd": "help", "with": who} for a helper, or {}.
func planned(who: int) -> Dictionary:
	for a in queue:
		if int(a.who) == who:
			return a
	var helping: Dictionary = preview().get("helping", {})
	if helping.has(who):
		return {"cmd": "help", "who": who, "with": int(helping[who])}
	return {}


## The members whose FIGHT plays this turn, in party order (each gets a timing press).
func fighters() -> Array:
	var out: Array = []
	for a in queue:
		if str(a.cmd) == "fight":
			out.append(int(a.who))
	out.sort()
	return out


## Records the timing press (0..1, 0.5 = perfect) for a member's planned FIGHT.
func set_timing(who: int, x: float) -> void:
	for a in queue:
		if int(a.who) == who and str(a.cmd) == "fight":
			a["arg"] = clampf(x, 0.0, 1.0)


## [BATTLE] Commits the plans once, in the fixed order. Returns one event per plan that played:
## {cmd, who, target, amount, kind ("damage" | "heal" | "mercy" | "spare" | ""), retarget, cancelled,
## helpers, lines}.
func resolve_queue() -> Array:
	if _resolving or queue.is_empty():
		return []
	var plan_preview := preview()
	if not bool(plan_preview.ok):
		return []
	_resolving = true
	# Settle planned TP costs and Defend gains once, in selection order, before playing the actions.
	tp = int(plan_preview.get("tp", tp))
	var helpers_by_member: Dictionary = plan_preview.get("helpers", {})
	var turn_actions := queue.duplicate(true)
	queue.clear()
	turn_actions.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_priority := _action_priority(first)
		var second_priority := _action_priority(second)
		return first_priority < second_priority if first_priority != second_priority else int(first.who) < int(second.who)
	)
	var events: Array = []
	for action: Dictionary in turn_actions:
		var member_index := int(action.who)
		if outcome != "" or not can_act(member_index):
			tp = mini(TP_MAX, tp + _action_tp_cost(action))
			continue
		events.append(_resolve_action(action, helpers_by_member.get(member_index, [])))
	_resolving = false
	return events


func _resolve_action(action: Dictionary, helpers: Array) -> Dictionary:
	var member_index := int(action.who)
	var command := str(action.cmd)
	var target := int(action.get("target", member_index))
	var lines_before := said.size()
	var hp_before := party.map(func(member: Dictionary) -> int: return int(member.hp))
	var event := {
		"cmd": command, "who": member_index, "target": target, "amount": 0, "kind": "",
		"retarget": false, "cancelled": false, "helpers": helpers,
	}
	var spell_def: Dictionary = Spells.BOOK.get(str(action.get("spell", "")), {}) if command == "magic" else {}
	var targets_enemy := command in ["fight", "act", "spare"] or str(spell_def.get("target", "")) == "enemy"
	if targets_enemy and not valid_enemy(target):
		# Earlier actions may have ended an enemy's turn. Only attacks can switch targets.
		var can_retarget := command == "fight" or str(spell_def.get("effect", "")) == "damage"
		var next_target := first_active() if can_retarget else -1
		if next_target >= 0:
			_say("%s is resting, so %s turns to %s." % [enemies[target].name, party[member_index].name, enemies[next_target].name])
			event.target = next_target
			event.retarget = true
		else:
			tp = mini(TP_MAX, tp + _action_tp_cost(action))
			var target_name := str(enemies[target].name) if target >= 0 and target < enemies.size() else "They"
			_say("%s is already resting. %s keeps their energy." % [target_name, party[member_index].name])
			event.cancelled = true
	if not bool(event.cancelled):
		_apply_command(action, spell_def, event)
	if str(event.kind) == "heal":
		_record_healing(event, hp_before)
	event["lines"] = said.slice(lines_before)
	return event


func _apply_command(action: Dictionary, spell_def: Dictionary, event: Dictionary) -> void:
	var member_index := int(event.who)
	var target := int(event.target)
	match str(event.cmd):
		"fight":
			event.amount = fight(member_index, target, float(action.get("arg", 0.5)))
			event.kind = "damage"
		"act":
			_apply_act(member_index, target, int(action.arg), event)
		"magic":
			_last_amount = 0
			if magic(member_index, target, str(action.spell)):
				event.amount = _last_amount
				event.kind = {"damage": "damage", "heal": "heal", "heal_all": "heal", "pacify": "spare"}.get(str(spell_def.get("effect", "")), "")
			else:
				tp = mini(TP_MAX, tp + _action_tp_cost(action))
				event.cancelled = true
		"item":
			_apply_item(member_index, target, items[int(action.arg)], event)
		"spare":
			if spare(member_index, target):
				event.kind = "spare"
		"defend": defend(member_index)
		"rally":
			rally()
			event.kind = "heal"
		"run": run_away()


func _apply_act(member_index: int, target: int, act_index: int, event: Dictionary) -> void:
	var act_def: Dictionary = enemies[target].acts[act_index]
	var helpers: Array = event.helpers
	if not helpers.is_empty():
		var helper_names := PackedStringArray()
		for helper_index in helpers:
			helper_names.append(str(party[int(helper_index)].name))
		_say("%s and %s, together:" % [party[member_index].name, " and ".join(helper_names)])
	if str(act_def.get("name", "")) == "Check":
		_say(check_text(target))
		return
	var mercy_before := int(enemies[target].mercy)
	act(member_index, target, act_index)
	event.amount = int(enemies[target].mercy) - mercy_before
	event.kind = "mercy"


func _apply_item(member_index: int, target: int, item: Dictionary, event: Dictionary) -> void:
	# Recheck the live inventory at commit time because a plan only reserves the snack.
	if int(item.get("count", 0)) <= 0 or (consume_item.is_valid() and not bool(consume_item.call(str(item.get("id", ""))))):
		_say("That snack is no longer in the bag. Nothing was used.")
		event.cancelled = true
		return
	item.count = int(item.count) - 1
	var snack_name := str(item.get("name", "Snack"))
	if target == member_index:
		_say("%s eats the %s." % [party[member_index].name, snack_name])
	else:
		_say("%s gives %s the %s." % [party[member_index].name, party[target].name, snack_name])
	event.amount = heal(target, int(item.get("heal", 15)))
	event.kind = "heal"


func _record_healing(event: Dictionary, hp_before: Array) -> void:
	# Report actual HP gained, including for capped heals and party-wide spells.
	var recipients: Array = []
	var total_healed := 0
	for member_index in party.size():
		var hp_gained := int(party[member_index].hp) - int(hp_before[member_index])
		if hp_gained > 0:
			recipients.append({"who": member_index, "amount": hp_gained})
			total_healed += hp_gained
	event["healed"] = recipients
	event.amount = total_healed


func _action_tp_cost(action: Dictionary) -> int:
	match str(action.cmd):
		"act":
			var target := int(action.get("target", -1))
			var act_index := int(action.get("arg", -1))
			if target >= 0 and target < enemies.size() and act_index >= 0 and act_index < (enemies[target].acts as Array).size():
				return clampi(int(enemies[target].acts[act_index].get("tp", 0)), 0, TP_MAX)
			return 0
		"magic": return int(Spells.BOOK.get(str(action.get("spell", "")), {}).get("tp", 0))
		"rally": return RALLY_COST
	return 0


func _action_priority(action: Dictionary) -> int:
	match str(action.cmd):
		"defend": return 0
		"act": return 1
		"item", "rally": return 2
		"magic": return 4 if str(Spells.BOOK.get(str(action.get("spell", "")), {}).get("effect", "")) == "pacify" else 3
		"spare": return 4
		"fight": return 5
	return 6


## One enemy turn: every enemy still in the battle (and not sitting it out) attacks together. The lead
## (taking turns) sets the box, the length and the warning; each enemy adds up to two of its own
## spawners (all six when alone), a little sparser when there are more of them. Slow (an ACT) and the
## Slower bullets assist slow an enemy's bullets. Returns {wave, owners (enemy per spawner), lead,
## alive} or {} when nobody attacks.
func turn_plan(turn_index: int = -1) -> Dictionary:
	if turn_index < 0:
		turn_index = turn
	var alive: Array = []
	for i in enemies.size():
		if valid_enemy(i) and not bool(enemies[i].get("skip_wave", false)):
			alive.append(i)
	if alive.is_empty():
		return {}
	var lead := int(alive[turn_index % alive.size()])
	var lead_waves: Array = enemies[lead].get("waves", [])
	var wave := Patterns.clean_wave(lead_waves[_wave_index(enemies[lead], turn_index)] if not lead_waves.is_empty() else Patterns.template("rain"))
	var spawners: Array = []
	var owners: Array = []
	for i in alive:
		var foe: Dictionary = enemies[i]
		var own_waves: Array = foe.get("waves", [])
		var own := Patterns.clean_wave(own_waves[_wave_index(foe, turn_index)] if not own_waves.is_empty() else Patterns.template("rain"))
		var speed := (0.7 if bool(assists.get("slow_bullets", false)) else 1.0) * (0.65 if int(foe.get("slow", 0)) > 0 else 1.0)
		own = Patterns.scaled(own, speed, speed / maxf(1.0, sqrt(float(alive.size()))))
		for s in (own.spawners as Array).slice(0, 2 if alive.size() > 1 else 6):
			if int(i) != lead:
				s["seed"] = int(s.get("seed", 1)) + 7919 * (int(i) + 1)   # (two foes with one pattern don't overlap)
			spawners.append(s)
			owners.append(int(i))
	wave.spawners = spawners
	return {"wave": Patterns.prepare(wave), "owners": owners, "lead": lead, "alive": alive}


func phase_index(foe: Dictionary) -> int:
	var found := -1
	var phases: Array = foe.get("phases", [])
	for i in phases.size():
		var p: Dictionary = phases[i]
		if float(foe.mercy) / maxf(1, float(foe.mercy_max)) >= float(p.mercy) or float(foe.hp) / maxf(1, float(foe.max_hp)) <= float(p.hp):
			found = i
	return found


func _wave_index(foe: Dictionary, turn_index: int) -> int:
	var waves: Array = foe.get("waves", [])
	if waves.is_empty():
		return 0
	var chosen := int(foe.get("next_wave", -1))
	if chosen >= 0 and chosen < waves.size():
		return chosen
	var order := str(foe.get("order", "cycle"))
	var phases: Array = foe.get("phases", [])
	if not phases.is_empty():
		var stage := phase_index(foe)
		return clampi(int(phases[stage].wave), 0, waves.size() - 1) if stage >= 0 else 0
	if order == "once":
		return mini(turn_index, waves.size() - 1)
	if order == "shuffle":
		var mix := RandomNumberGenerator.new()   # (seeded: the same battle shuffles the same way every time)
		mix.seed = hash("%d:%d:%s" % [_seed, turn_index, str(foe.get("name", ""))])
		return mix.randi() % waves.size()
	return turn_index % waves.size()


## What the Battle Log keeps.
func summary(battle_name: String) -> Dictionary:
	return {"battle": battle_name, "outcome": outcome, "turns": turn, "tp": tp,
		"enemies": enemies.map(func(e): return {"name": e.name, "spared": e.spared, "tired_out": e.tired_out, "mercy": e.mercy}),
		"party": party.map(func(m): return str(m.name)), "when": Time.get_datetime_string_from_system()}
