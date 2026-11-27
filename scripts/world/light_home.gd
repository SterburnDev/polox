extends RefCounted
## Your real home as Light World places (realms.gd). Until Polox knows your home (the Survey, Phase
## 30), the Light World is a plain, comfortable room of your own: a bed, a desk, a wardrobe, a rug, a
## lamp, a plant, and the Dream Gate back to the Dream World. Light World places use real-life
## colours and sizes (a cell is a metre), soft daylight, and you're always Real Me there.

const Realms := preload("res://scripts/world/realms.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const FloorPaths := preload("res://scripts/world/floor_paths.gd")

## Real-life colours (warm, lightly worn, nothing neon).
const WALL_CREAM := "#efe6d8"
const FLOOR_OAK := "#c9a27a"
const GRASS := "#7fa86a"
## A Light World place's surroundings: real sky by the clock, a lawn, a row of trees beyond.
const SCENERY := {"sky": "auto", "ground": true, "ground_color": GRASS, "layers": [
	{"kind": "trees", "color": "#5f8a5a", "distance": 2, "seed": 21},
	{"kind": "hills", "color": "#8fae8a", "distance": 3, "seed": 22}]}


## A Light World place's common fields (realm, look, Real Me, no weather indoors, no music).
static func base_place(id: String, place_name: String, w: int, d: int, kind: String = "indoor") -> Dictionary:
	var r := Defaults.room(id, place_name)
	r["realm"] = Realms.LIGHT
	r["look"] = "real"
	r["player_form"] = "real"
	r["kind"] = kind
	r["size"] = {"w": w, "d": d, "h": 2.6}
	r["floor"] = {"color": FLOOR_OAK if kind == "indoor" else GRASS, "texture": ""}
	r["wall"] = {"color": WALL_CREAM, "texture": ""}
	r["sky"] = {"color": "#9ec8e8", "texture": ""}
	r["walls"] = {"north": kind == "indoor", "east": kind == "indoor", "south": kind == "indoor", "west": kind == "indoor"}
	r["background"] = SCENERY.duplicate(true)
	r["ambiance"] = {"music": "", "lighting": "real", "weather": "none" if kind == "indoor" else "auto"}
	r["spawn"] = [w / 2, d - 2]
	return r


static func add(room: Dictionary, model: String, x: int, z: int, rot: int = 0, color: String = "") -> Dictionary:
	var o := Furniture.make(model, x, z, rot, color)
	o["id"] = RoomEditor.next_object_id(room, model)
	(room["objects"] as Array).append(o)
	return o


## Your room before Polox knows your home.
static func placeholder() -> Dictionary:
	var r := base_place(Realms.ENTRY, "My room", 7, 6)
	add(r, "bed", 0, 0)
	add(r, "nightstand", 1, 0)
	add(r, "desk", 4, 0)
	add(r, "chair", 4, 1, 2)
	add(r, "wardrobe", 6, 0)
	add(r, "rug", 2, 2)
	add(r, "lamp", 6, 4)
	add(r, "plant", 0, 5)
	add(r, "light_switch", 3, 0)   # (by the desk: the lamps' switch)
	add(r, "lantern", 2, 5)
	r["spawn"] = [3, 4]
	Realms.add_gate(r, Vector2i(4, 4), Realms.DARK, "")
	return r


## What never belongs in the Light World (your real home and streets): blocks and terrain, Platform Mode's
## pieces, battle spots, Dream Doors, Dream Gates other than the way to the Dream World.
const NOT_HERE: PackedStringArray = ["platform_pillar", "jump_pad", "one_way", "mover", "checkpoint", "shard", "hazard", "battle_spot", "dream_door", "pickup"]


static func belongs(o: Variant) -> bool:
	if not o is Dictionary:
		return false
	var t := str(o.get("type", ""))
	if t in NOT_HERE:
		return false
	return t != "dark_fountain" or Realms.is_gate(o)


## Takes out anything that doesn't belong, sets an older street's front door into your house, and moves any
## furniture that shuts part of a floor off (floor_paths.gd), with the spawn where you can walk away from it
## (on load, in memory). Returns how many things it took out.
static func sanitize(room: Dictionary) -> int:
	if not Realms.is_light(room):
		return 0
	var before := (room.get("objects", []) as Array).size() + (room.get("tiles", []) as Array).size()
	room["objects"] = (room.get("objects", []) as Array).filter(func(o): return belongs(o))
	room["tiles"] = []
	room["tile_layers"] = preload("res://scripts/world/tile_layers.gd").default_layers()
	fit_front_door(room)
	restore_street_exit(room)
	# [LIGHT_WORLD_MAP] Your house on your street wears what a helper found out about it (home_look.gd):
	# a street made before its colours were known follows them from the next visit, in memory.
	if room.get("buildings") is Array and not (room.buildings as Array).is_empty():
		var look_script: Script = load("res://scripts/home/home_look.gd")
		look_script.apply_to_street(room, look_script.of(load("res://scripts/home/home_store.gd").load_home()))
	FloorPaths.open_pockets(room)
	FloorPaths.safe_spawn(room)
	return maxi(0, before - (room.objects as Array).size())


## Restore the connection discarded by older house rebuilds, without research
## or changing the saved street map.
static func street_entry() -> String:
	for id in SaveManager.list_light_rooms():
		if str(id).begins_with("lw_hood_"):
			for o in SaveManager.load_room(str(id)).get("objects", []):
				if str(o.get("type", "")) == "door" and str(o.get("door_target", "")) == "lw_floor_0":
					return str(id)
	return ""


static func restore_street_exit(room: Dictionary) -> void:
	if str(room.get("id", "")) != "lw_floor_0":
		return
	for o in room.get("objects", []):
		if str(o.get("type", "")) == "door" and str(o.get("door_target", "")).begins_with("lw_hood_") and SaveManager.room_exists(str(o.door_target)):
			return
	var target := street_entry()
	if target == "":
		return
	var w := int(room.size.w)
	var d := int(room.size.d)
	for offset in w:
		var x := posmod(w / 2 + offset, w)
		var door := RoomEditor.add_object(room, x, d - 1, "door")
		if not door.is_empty():
			door.merge({"door_target": target, "street_gate": true, "label": "Go outside", "interaction_text": "Out to the street"}, true)
			return


## Your front door on your street (hood_builder.gd): a little taller than you (people are 1.3 high,
## actor.gd) and as wide as the neighbours' painted doors (the door piece is 2.17 high, 1.12 wide).
const FRONT_DOOR_SCALE := 0.65


## A door next to your house on your street becomes its front door, once ("front_door"): turned to face
## out, down to the street's size, and drawn in the house's wall (room_view.gd) instead of standing in the
## middle of the first cell of your path, as tall as the house. Streets made before this get it here.
static func fit_front_door(room: Dictionary) -> void:
	var house := _house_cells(room)
	if house.is_empty():
		return
	for o in room.get("objects", []):
		if not o is Dictionary or str(o.get("type", "")) != "door" or o.has("front_door"):
			continue
		var pos: Array = o.get("pos", [0, 0, 0])
		var cell := Vector2i(int(pos[0]), int(pos[2]))
		var rot := posmod(int(o.get("rot", 0)), 4)
		for k in 4:
			var r := (rot + k) % 4   # (the way it already faces first)
			if house.has(cell - BlockFactory.facing(r)):
				o["rot"] = r
				o["scale"] = FRONT_DOOR_SCALE
				o["front_door"] = true
				break


## Where your front door stands in your house's wall: [the house's cell behind it, the way it faces];
## [] when it's been moved or turned away from the house in Build mode (it stands in its cell then).
static func door_wall(room: Dictionary, o: Dictionary) -> Array:
	if not bool(o.get("front_door", false)):
		return []
	var f := BlockFactory.facing(int(o.get("rot", 0)))
	var pos: Array = o.get("pos", [0, 0, 0])
	var behind := Vector2i(int(pos[0]), int(pos[2])) - f
	return [behind, f] if _house_cells(room).has(behind) else []


## Your house's cells in a street place (its "mine" building): {Vector2i: true}; {} anywhere else.
static func _house_cells(room: Dictionary) -> Dictionary:
	var out := {}
	if not room.has("hood"):
		return out
	for b in room.get("buildings", []):
		if b is Dictionary and str(b.get("kind", "")) == "mine":
			for c in b.get("cells", []):
				out[Vector2i(int(c[0]), int(c[1]))] = true
	return out


## Where the Light World starts: the floor with your room (once Polox knows your home), else the plain
## room. "" when there's no Light World yet.
static func entry_id() -> String:
	for id in SaveManager.list_light_rooms():
		if str(id) != Realms.ENTRY and bool(SaveManager.load_room(id).get("entry", false)):
			return str(id)
	return Realms.ENTRY if SaveManager.room_exists(Realms.ENTRY) else ""


## Your room, made if it isn't there yet. Returns the entry place's id.
static func ensure_entry() -> String:
	var e := entry_id()
	if e != "":
		return e
	SaveManager.save_room(placeholder())
	return Realms.ENTRY


## A placeholder made by an older paired phone is not a completed Survey.
## An explicit "another time" stays local, just like the Survey draft and answers.
static func needs_survey() -> bool:
	var entry := entry_id()
	if entry != "" and entry != Realms.ENTRY:
		return false
	return not FileAccess.file_exists(SaveManager.home_dir().path_join("survey_skipped.json"))


static func defer_survey() -> void:
	preload("res://scripts/core/json_util.gd").write_json(SaveManager.home_dir().path_join("survey_skipped.json"), {"skipped": true})


## Ready-made Light World templates so players can skip the Light World creation sequence completely.
const TEMPLATES := [
	{"id": "starter_room", "name": "Cozy Bedroom", "desc": "Warm oak floor, bed, desk, wardrobe, rug, and the Dream Gate."},
	{"id": "studio_loft", "name": "Sunlit Studio", "desc": "A spacious 10x8 studio with double bed, armchair, desk, dining table, and bookshelf."},
	{"id": "two_room_flat", "name": "Cozy Apartment (2 rooms)", "desc": "Your bedroom connected by a door to a bright living & dining room."},
	{"id": "garden_cottage", "name": "Garden Cottage (Room + Yard)", "desc": "A cozy cottage room with a front door out to a sunny Light World yard."},
]


static func _clear_old_template_entries() -> void:
	var places_dir := SaveManager.home_dir().path_join("places")
	for id in SaveManager.list_light_rooms():
		var rid := str(id)
		if rid.begins_with("lw_template_"):
			DirAccess.remove_absolute(places_dir.path_join(rid + ".json"))
			continue
		var r := SaveManager.load_room(rid)
		if bool(r.get("entry", false)):
			r.erase("entry")
			SaveManager.save_room(r)


static func _template_link(a: Dictionary, b: Dictionary, ax: int, az: int, bx: int, bz: int, label_ab: String, label_ba: String) -> void:
	var d1 := RoomEditor.add_object(a, ax, az, "door")
	if not d1.is_empty():
		d1.merge({"door_target": str(b.id), "label": label_ab}, true)
	var d2 := RoomEditor.add_object(b, bx, bz, "door")
	if not d2.is_empty():
		d2.merge({"door_target": str(a.id), "label": label_ba}, true)


## Builds and saves one of TEMPLATES as the Light World, marks the Survey skipped, and returns its entry id.
static func apply_template(template_id: String) -> String:
	_clear_old_template_entries()
	defer_survey()
	match template_id:
		"studio_loft":
			var r := base_place("lw_template_studio", "Sunlit Studio", 10, 8)
			r["entry"] = true
			r["wall"] = {"color": "#f2efe8", "texture": ""}
			add(r, "double_bed", 0, 0)
			add(r, "nightstand", 2, 0)
			add(r, "bookshelf", 4, 0)
			add(r, "desk", 7, 0)
			add(r, "chair", 7, 1, 2)
			add(r, "wardrobe", 9, 0)
			add(r, "armchair", 1, 5, 1)
			add(r, "coffee_table", 2, 5)
			add(r, "rug", 2, 4)
			add(r, "dining_table", 6, 4)
			add(r, "chair", 6, 3, 2)
			add(r, "lamp", 9, 6)
			add(r, "plant", 0, 7)
			add(r, "light_switch", 6, 0)
			r["spawn"] = [4, 5]
			Realms.add_gate(r, Vector2i(8, 6), Realms.DARK, "")
			SaveManager.save_room(r)
			return "lw_template_studio"
		"two_room_flat":
			var bed := base_place("lw_template_bed", "My Bedroom", 7, 6)
			bed["entry"] = true
			bed["wall"] = {"color": "#e8eef5", "texture": ""}
			add(bed, "bed", 0, 0)
			add(bed, "nightstand", 1, 0)
			add(bed, "desk", 4, 0)
			add(bed, "chair", 4, 1, 2)
			add(bed, "wardrobe", 0, 4)
			add(bed, "rug", 2, 2)
			add(bed, "light_switch", 3, 0)
			bed["spawn"] = [3, 4]
			Realms.add_gate(bed, Vector2i(1, 4), Realms.DARK, "")
			var living := base_place("lw_template_living", "Living Room", 9, 7)
			living["wall"] = {"color": "#efe6d8", "texture": ""}
			add(living, "couch", 3, 1)
			add(living, "coffee_table", 3, 2)
			add(living, "tv", 3, 0)
			add(living, "bookshelf", 7, 0)
			add(living, "dining_table", 6, 4)
			add(living, "chair", 6, 3, 2)
			add(living, "lamp", 8, 1)
			add(living, "plant", 0, 6)
			add(living, "rug", 3, 3)
			living["spawn"] = [1, 3]
			_template_link(bed, living, 6, 3, 0, 3, "Living Room", "My Bedroom")
			SaveManager.save_room(bed)
			SaveManager.save_room(living)
			return "lw_template_bed"
		"garden_cottage":
			var cottage := base_place("lw_template_cottage", "Garden Cottage", 8, 6)
			cottage["entry"] = true
			cottage["wall"] = {"color": "#f5ecd8", "texture": ""}
			add(cottage, "bed", 0, 0)
			add(cottage, "nightstand", 1, 0)
			add(cottage, "desk", 5, 0)
			add(cottage, "chair", 5, 1, 2)
			add(cottage, "bookshelf", 3, 0)
			add(cottage, "rug", 3, 3)
			add(cottage, "lamp", 7, 1)
			add(cottage, "plant", 0, 4)
			add(cottage, "light_switch", 2, 0)
			cottage["spawn"] = [4, 4]
			Realms.add_gate(cottage, Vector2i(6, 4), Realms.DARK, "")
			var yard := base_place("lw_template_yard", "Front Yard", 10, 8, "outdoor")
			add(yard, "bench", 2, 2)
			add(yard, "birdbath", 6, 3)
			add(yard, "plant", 1, 5)
			add(yard, "plant", 8, 5)
			add(yard, "lantern", 4, 1)
			yard["spawn"] = [4, 2]
			_template_link(cottage, yard, 4, 5, 4, 0, "Step outside", "Back inside")
			SaveManager.save_room(cottage)
			SaveManager.save_room(yard)
			return "lw_template_cottage"
		_:
			var r := placeholder()
			SaveManager.save_room(r)
			return Realms.ENTRY


## A saved visit home must remain a visit home even if a generated room disappeared.
static func recover_entry() -> String:
	var entry := entry_id()
	if entry != "":
		return entry
	var store: Script = load("res://scripts/home/home_store.gd")
	var home: Dictionary = store.load_home() if store.exists() else {}
	var plan: Dictionary = home.get("plan", {})
	if not (plan.get("floors", []) as Array).is_empty():
		store.snapshot("before_recovery")
		var places: Script = load("res://scripts/home/home_places.gd")
		entry = places.save_all(places.build(plan))
		if entry != "":
			return entry
	return ensure_entry()
