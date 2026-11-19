extends Node
## Daily life in the Light World (game_world.light_life): using the furniture (the stairs take you between
## floors, asking which way between two; a plant can be watered, a desk sat at, a bed rested on; anything else
## answers with a small, ordinary moment), the things to do in the room you're in (tap yourself), your
## journal, the curtains, the view from the window, footsteps that sound like the floor, and the house's
## history when you walk into a room that used to be something else. No streaks, no timers.

const Furniture := preload("res://scripts/world/furniture.gd")
const ChoicePanel := preload("res://scripts/ui/choice_panel.gd")
const Realms := preload("res://scripts/world/realms.gd")
const Synth := preload("res://scripts/core/synth.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const OpenQuestions := preload("res://scripts/home/open_questions.gd")
const LayoutBuilder := preload("res://scripts/home/layout_builder.gd")
const Whimsy := preload("res://scripts/variety/whimsy.gd")

const LINES := {
	"bed": "Your bed. It looks soft.", "double_bed": "A big bed, neatly made.", "nightstand": "A lamp, a glass of water, a book you'll finish one day.",
	"wardrobe": "Clothes for every kind of day.", "dresser": "Socks, mostly.", "desk": "Your desk. Everything is roughly where you left it.",
	"computer": "The screen glows, patient.", "chair": "A good chair.", "bookshelf": "Books you've read, books you mean to.",
	"sofa": "The sofa has a dip just your shape.", "armchair": "The comfiest seat in the house.", "coffee_table": "A mug ring nobody mentions.",
	"tv": "Nothing on right now.", "dining_table": "Room for everyone.", "counter": "Crumbs, and the kettle.", "sink": "A drip, now and then.",
	"stove": "It smells a little like dinner.", "fridge": "It hums. There's something to snack on.", "toilet": "...", "bathtub": "A long bath sounds nice.",
	"shower": "The tiles are still a little warm.", "washbasin": "Your toothbrush, leaning.", "washer": "Spinning, somewhere in its dreams.",
	"lamp": "Warm light.", "plant": "It leans toward the window.", "rug": "Soft underfoot.", "runner": "Soft underfoot.", "piano": "A few keys, gently.",
	"bench": "A bench to sit and watch the street.", "flowers": "They smell like summer.", "mailbox": "Nothing today. Maybe tomorrow.",
	"tree": "Its leaves whisper.", "bush": "Something small rustles inside.", "car": "Parked, waiting.",
	"floor_cushion": "The floor is a perfectly good place to settle down.", "record_player": "A little crackle before the music.",
	"shoe_rack": "Your favourite pair, ready by the door.", "birdbath": "A tiny ripple. Someone was here a moment ago.",
	"bean_bag": "It sighs as you sink in. Five more minutes.", "fish_tank": "Three fish, one bubble at a time. They seem to know you.",
	"coat_rack": "A hat, a scarf, a bag for later.", "bar_stool": "It spins, just a little, when nobody's looking.",
	"wall_clock": "Ten past ten. It always looks like it's smiling.",
}

var world: Node


func setup(game_world: Node) -> void:
	world = game_world


func use(o: Dictionary) -> void:
	var model := str(o.get("model", ""))
	if model == "stairs":
		var up := str(o.get("door_target", ""))
		var down := str(o.get("down_target", ""))
		if up != "" and down != "":
			var p: Control = ChoicePanel.new()
			world.main.open_panel(p)
			p.ask("Stairs", "Up or down?", [["Up", func(): take_stairs(up)], ["Down", func(): take_stairs(down)], ["Stay here", func(): pass]])
		elif up != "" or down != "":
			take_stairs(up if up != "" else down)
		return
	match model:
		"light_switch":
			flip_switch(o)
			return
		"plant":
			water(o)
			return
		"desk", "computer":
			sit(o)
			return
		"bed", "double_bed":
			rest(o)
			return
	var text := str(o.get("interaction_text", "")).strip_edges()
	if text == "":
		var fallback := str(LINES.get(model, Furniture.name_of(model) + "."))
		text = Whimsy.inspect_furniture(model, str(o.get("id", "")), fallback)
	world.talk.show_text("", text)


## Arriving in a Light World place: a gentle line about an open question, only if you turned reminders
## on (Settings > Light World), and at most once a day. Otherwise nothing ever asks you anything.
func on_room_loaded(data: Dictionary) -> void:
	_here_room = ""
	_light_room(_switch_on(data))
	var in_light := Realms.is_light(data)
	set_process(in_light)
	if world and world.player and world.player.anim:
		world.player.anim.on_step = _on_step if in_light else _on_dream_step
	if not in_light:
		return
	var lw: Dictionary = GameState.settings.get("light_world", {}) if GameState.settings.get("light_world") is Dictionary else {}
	if not bool(lw.get("question_reminders", false)):
		return
	var today := Time.get_date_string_from_system()
	if str(lw.get("last_reminder", "")) == today:
		return
	var open: Array = OpenQuestions.open_list(HomeStore.load_home())
	if open.is_empty():
		return
	lw["last_reminder"] = today
	GameState.settings["light_world"] = lw
	GameState.save_settings()
	GameState.notify("☀ Polox is wondering about something in your home, whenever you like (My home > Not sure).")


func take_stairs(target: String) -> void:
	if target == "" or not SaveManager.room_exists(target):
		return
	Synth.play(world, "door", 0.4)
	await world.go_to_room(target)

# --- Daily life (Phase 33) ---------------------------------------------------------------------------

const FLOOR_STEPS := {"wood": "step_wood", "tile": "step_stone", "vinyl": "step_wood", "stone": "step_stone", "concrete": "step_stone",
	"carpet": "step_soft", "grass": "step_grass", "park": "step_grass", "road": "step_stone", "path": "step_stone", "woods": "step_grass",
	"sidewalk": "step_stone", "paved": "step_stone", "garden": "step_grass", "sand": "step_soft"}
const VIEWS := {"street": "The street outside. A car rolls past, slowly.", "yard": "The yard, a little overgrown. A bird hops along the fence.",
	"trees": "Trees, leaning in the breeze.", "house": "The house next door, its curtains drawn.", "sky": "Just sky, and a cloud taking its time."}

var _room_seen := {}     # room id -> the day its "used to be" moment was shown
var _here_room := ""
var _check_t := 0.0


## Footsteps that sound like the floor under you (wood, tiles, carpet, grass, the pavement).
func _on_step(_state: String) -> void:
	if world == null or world.player == null:
		return
	Synth.play(world, step_sound(world.room.data, world.player.cell()), 0.22)


## The Dream World's footsteps: soft and quiet (the Deep's ring like stone).
func _on_dream_step(_state: String) -> void:
	if world == null or world.player == null:
		return
	var deep := str(world.room.data.get("side", "")) == "dark"
	Synth.play(world, "step_stone" if deep else "step_soft", 0.12)


static func step_sound(data: Dictionary, cell: Vector2i) -> String:
	for a in data.get("floor_areas", []):
		var r: Array = a.get("rect", [0, 0, 0, 0])
		if Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(cell):
			var kind := str(a.get("kind", ""))
			if kind == "":
				# A room's floor: by its colour back to the kind it was made from.
				for k in ["wood", "carpet", "tile", "vinyl", "concrete", "stone"]:
					if str(a.get("color", "")) == str(LayoutBuilder.FLOOR_COLORS.get(k, "")):
						kind = k
			return str(FLOOR_STEPS.get(kind, "step_soft"))
	return "step_grass" if str(data.get("kind", "")) == "outdoor" or str(data.get("id", "")).begins_with("lw_floor_0") else "step_soft"


func _process(delta: float) -> void:
	if world == null or world.player == null or not Realms.is_light(world.room.data):
		set_process(false)
		return
	_check_t += delta
	if _check_t < 0.5:
		return
	_check_t = 0.0
	_moment_in_room()


## The room you're standing in (your house's places), or {}.
func room_here() -> Dictionary:
	var cell: Vector2i = world.player.cell()
	for r in world.room.data.get("rooms", []):
		var rr: Array = r.rect
		if Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3])).has_point(cell):
			return r
	return {}


## Walking into a room that used to be something else: a soft line, once a day per room. ("This used to
## be the playroom." "The deck was added in 2014.")
func _moment_in_room() -> void:
	var r := room_here()
	var id := str(r.get("id", ""))
	if id == _here_room:
		return
	_here_room = id
	if id == "":
		return
	var today := Time.get_date_string_from_system()
	if str(_room_seen.get(id, "")) == today:
		return
	var line := history_line(r)
	if line == "":
		return
	_room_seen[id] = today
	GameState.notify("☀ " + line)


## What the house remembers about a room: what it used to be (yours first), else a permit that names it.
static func history_line(r: Dictionary) -> String:
	var home: Dictionary = load("res://scripts/home/home_store.gd").load_home()
	var plan_room := {}
	for f in home.get("plan", {}).get("floors", []):
		for pr in f.get("rooms", []):
			if str(pr.id) == str(r.get("id", "")):
				plan_room = pr
	var was := str(plan_room.get("used_to_be", ""))
	if was != "":
		return "This used to be %s." % was
	var kind := str(r.get("kind", ""))
	for t in home.get("timeline", []):
		var text := str(t.get("text", "")).to_lower()
		if str(t.get("kind", "")) == "permit" and int(t.get("year", 0)) > 0 and (text.contains(kind) or (kind == "living" and text.contains("living room"))):
			return "In %d: %s" % [int(t.year), str(t.text)]
	return ""


## Things to do here: what fits the room you're in (tap yourself to see them). No streaks, no timers.
func things_to_do() -> Array:
	var out: Array = []
	var r := room_here()
	var rect := Rect2i()
	if not r.is_empty():
		var rr: Array = r.rect
		rect = Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3]))
	var in_room := func(o: Dictionary) -> bool:
		if rect.size.x == 0:
			return true
		var p: Array = o.get("pos", [0, 0, 0])
		return rect.has_point(Vector2i(int(p[0]), int(p[2])))
	var objs: Array = world.room.data.get("objects", [])
	for o in objs:
		if not Furniture.is_furniture(o) or not in_room.call(o):
			continue
		match str(o.get("model", "")):
			"plant":
				if not out.any(func(x): return x[2] == "water"):
					out.append(["Water the plant", func(): water(o), "water"])
			"desk", "computer":
				if not out.any(func(x): return x[2] == "desk"):
					out.append(["Sit at your desk", func(): sit(o), "desk"])
			"bed", "double_bed":
				if not out.any(func(x): return x[2] == "bed"):
					out.append(["Rest a while", func(): rest(o), "bed"])
	if _has_window(rect):
		var open := bool(_life().get("curtains", {}).get(str(r.get("id", "room")), true))
		out.append(["Close the curtains" if open else "Open the curtains", func(): curtains(str(r.get("id", "room"))), "curtains"])
		out.append(["Look out of the window", func(): look_out(), "window"])
	if str(world.room.data.get("id", "")).begins_with("lw_floor_"):
		out.append(["Write in your journal", func(): journal(), "journal"])
	var park := park_place()
	if park != "" and park != GameState.current_room_id:
		out.append(["Walk to the park", func(): world.go_to_room(park), "park"])
	return out


func _has_window(rect: Rect2i) -> bool:
	for e in world.room.data.get("edge_walls", []):
		if not bool(e.get("window", false)):
			continue
		var c := Vector2i(int(e.x), int(e.z))
		var c2 := Vector2i(int(e.x), int(e.z) - 1) if str(e.dir) == "h" else Vector2i(int(e.x) - 1, int(e.z))
		if rect.size.x == 0 or rect.has_point(c) or rect.has_point(c2):
			return true
	return false


## The block of your streets with the park in it, or "".
static func park_place() -> String:
	for id in SaveManager.list_light_rooms():
		if not str(id).begins_with("lw_hood_"):
			continue
		var p := SaveManager.load_room(id)
		for a in p.get("floor_areas", []):
			if str(a.get("kind", "")) == "park" and int(a.rect[2]) * int(a.rect[3]) >= 20:
				return str(id)
	return ""


func open_things_to_do() -> void:
	var list := things_to_do()
	var p: Control = ChoicePanel.new()
	world.main.open_panel(p)
	var options: Array = []
	for t in list:
		options.append([t[0], t[1]])
	options.append(["Nothing right now", func(): pass])
	p.ask("Here", "Your real home, quiet and ordinary." if not list.is_empty() else "Nothing to do here just now, and that's fine.", options)


func water(o: Dictionary) -> void:
	world.controller.walk_beside(world.room.obj_cell(o), func():
		world.player.emote("✦", Color("#7fb4d8"))
		load("res://scripts/core/synth.gd").play(world, "pop", 0.3)
		world.talk.show_text("", "The soil drinks it up. The leaves seem to lift a little."))


func sit(o: Dictionary) -> void:
	world.controller.walk_beside(world.room.obj_cell(o), func():
		world.talk.show_text("", "You sit for a while. It's quiet. Everything is roughly where you left it."))


func rest(o: Dictionary) -> void:
	world.controller.walk_beside(world.room.obj_cell(o), func():
		world.player.emote("z", Color("#c9b6ff"))
		world.talk.show_text("", "You lie down for a minute and listen to the house."))


func curtains(room_id: String) -> void:
	var life := _life()
	var c: Dictionary = life.get("curtains", {}) if life.get("curtains") is Dictionary else {}
	var open := not bool(c.get(room_id, true))
	c[room_id] = open
	life["curtains"] = c
	_save_life(life)
	world.talk.show_text("", "You open the curtains. Light spills in." if open else "You draw the curtains. The room goes soft and dim.")
	world.daylight.apply()


func look_out() -> void:
	var a: Dictionary = load("res://scripts/home/home_store.gd").load_home().get("answers", {})
	var view := str((a.get("my_room", {}) as Dictionary).get("view", "")) if a.get("my_room") is Dictionary else ""
	var line := str(VIEWS.get(view, "Outside, the day goes on."))
	if load("res://scripts/world/daylight.gd").is_night(world.daylight.current_hour()):
		line = "It's dark out. A streetlight hums somewhere."
	world.talk.show_text("", line)


## Your journal: private (my_home/journal.json), never synced or sent anywhere.
func journal() -> void:
	var p: Control = load("res://scripts/home/journal_panel.gd").new()
	world.main.open_panel(p)


static func _life() -> Dictionary:
	var d: Variant = load("res://scripts/core/json_util.gd").read_json(load("res://scripts/home/home_store.gd").path("life.json"), {})
	return d if d is Dictionary else {}


static func _save_life(d: Dictionary) -> void:
	load("res://scripts/core/json_util.gd").write_json(load("res://scripts/home/home_store.gd").path("life.json"), d)


## How much light a room's curtains let in (daylight.gd dims a room with them drawn).
func curtains_open_here() -> bool:
	var r := room_here()
	return bool(_life().get("curtains", {}).get(str(r.get("id", "room")), true))


## [GLASS_UI] A light switch, flicked: the rocker tips over with a clack, its pilot light changes, and the
## room's lamps go on or off (and stay that way: it's saved with the room).
func flip_switch(o: Dictionary) -> void:
	var on := not bool(o.get("on", true))
	o["on"] = on
	SaveManager.save_room(world.room.data)
	load("res://scripts/core/synth.gd").play(world, "light_switch", 0.7)
	var Furniture := preload("res://scripts/world/furniture.gd")
	for n in world.get_tree().get_nodes_in_group(&"polox_rocker"):
		if str(n.get_meta("id", "")) != str(o.get("id", "")):
			continue
		var tilt := Furniture.SWITCH_TILT if on else -Furniture.SWITCH_TILT
		if preload("res://scripts/ui/anim_fx.gd").reduced():
			n.rotation.x = tilt
		else:
			n.create_tween().tween_property(n, "rotation:x", tilt, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var pilot := (n.get_parent() as Node).get_node_or_null("Pilot") as MeshInstance3D
		if pilot:
			pilot.material_override = Furniture._mat(Color("#ffb867") if on else Color("#5a5262"), on)
	_light_room(on)


## Are this room's lamps switched on? (On unless a switch here says off.)
static func _switch_on(data: Dictionary) -> bool:
	for o in data.get("objects", []):
		if o is Dictionary and str(o.get("model", "")) == "light_switch":
			return bool(o.get("on", true))
	return true


## The room's lamps (furniture lights: floor lamps, lanterns) on or off.
func _light_room(on: bool) -> void:
	if world == null or not world.is_inside_tree():
		return
	for l in world.get_tree().get_nodes_in_group("polox_lamp"):
		if l is OmniLight3D and l.name == "Glow":
			l.visible = on
