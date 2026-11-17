extends RefCounted
## Creates a fresh world: a cozy furnished home room, a small garden linked
## by a door, the player's avatar and a first friend ("Mochi") with all
## default expressions. Onboarding fills in the names and World Bible.

const Defaults := preload("res://scripts/core/defaults.gd")
const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const TilesetFactory := preload("res://scripts/world/tileset_factory.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const StarterItems := preload("res://scripts/items/starter_items.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const Templates := preload("res://scripts/world/templates.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const Places := preload("res://scripts/world/places.gd")


## Every new world starts with the four starter tile sets (copied from the Library).
static func add_starter_tilesets() -> void:
	TilesetFactory.ensure_builtin()
	for id in TilesetFactory.BUILTIN:
		Tilesets.copy_from_library(id)


static func create_world(world_name: String = "", player_name: String = "", bible: Dictionary = {}, look: String = "cozy") -> void:
	SaveManager.ensure_slot(world_name if world_name.strip_edges() != "" else "My World")
	var w := Defaults.world()
	if world_name.strip_edges() != "":
		w["name"] = world_name.strip_edges()
	w["player"]["name"] = player_name.strip_edges()
	for k in bible:
		w["world_bible"][k] = bible[k]
	add_player_forms(w, look)
	SaveManager.save_world(w)
	SaveManager.save_room(home_room())
	SaveManager.save_room(garden_room())
	SaveManager.save_dreams(Defaults.dreams())
	SaveManager.save_journal(Defaults.journal())
	add_starter_tilesets()
	_add_playground_room()
	_open_up_places()
	_add_way_home()
	StarterItems.install(true)


## Every world's start place has the way home: a fountain to the Light World (your real home).
static func _add_way_home() -> void:
	var rooms := {}
	for id in SaveManager.list_rooms():
		rooms[str(id)] = SaveManager.load_room(id)
	var host := preload("res://scripts/core/world_migration.gd").add_gate_to_start(rooms, "home")
	if host != "":
		SaveManager.save_room(rooms[host])


## New worlds start as one world: the garden and the playground outdoors, joined edge to edge, and
## home indoors with the ground and sky around it (Places.open_up_all, the same as the v7 upgrade).
static func _open_up_places() -> void:
	var rooms := {}
	for id in SaveManager.list_rooms():
		rooms[str(id)] = SaveManager.load_room(id)
	for id in Places.open_up_all(rooms):
		SaveManager.save_room(rooms[id])


## Real Me (the cozy hoodie doll) and Dream World Me (the night wanderer),
## both drawn into player/<form>/.
static func add_player_forms(w: Dictionary, look: String = "cozy") -> void:
	var forms := {}
	for f in PlayerLook.FORMS:
		var d := PlayerLook.form_defaults(f)
		if f == "real" and look != "cozy":
			d["doll"] = preload("res://scripts/characters/doll.gd").preset(look)
		d["expressions"] = PlayerLook.write_doll_files(f, d.doll)
		forms[f] = d
	w["player"]["forms"] = forms
	w["player"]["form"] = "real"
	w["player"]["avatar"] = str(forms.real.expressions.neutral)


## An empty world: one plain room, your avatar, nobody home yet.
static func create_blank(world_name: String, player_name: String = "") -> void:
	SaveManager.ensure_slot(world_name if world_name.strip_edges() != "" else "My World")
	var w := Defaults.world()
	w["name"] = world_name.strip_edges() if world_name.strip_edges() != "" else "My World"
	w["player"]["name"] = player_name.strip_edges()
	add_player_forms(w)
	SaveManager.save_world(w)
	SaveManager.save_room(Defaults.room("home", "Home"))
	SaveManager.save_dreams(Defaults.dreams())
	SaveManager.save_journal(Defaults.journal())
	add_starter_tilesets()
	_add_playground_room()
	_open_up_places()
	_add_way_home()
	StarterItems.install(true)


## The playground is a normal editable room reached from the garden. Keeping it
## connected means players can inspect the tiles without changing their home.
static func _add_playground_room() -> void:
	TemplateFactory.ensure_builtin()
	var ids := Templates.new_level("tile_playground")
	if ids.is_empty():
		return
	var demo_id := str(ids[0])
	var home := SaveManager.load_room("home")
	var entrance := RoomEditor.add_object(home, 11, 8, "door")
	if not entrance.is_empty():
		entrance["door_target"] = demo_id
		entrance["interaction_text"] = "Visit the Tile Playground"
		SaveManager.save_room(home)
	var demo := SaveManager.load_room(demo_id)
	var exit_door := RoomEditor.add_object(demo, 0, 10, "door")
	if not exit_door.is_empty():
		exit_door["door_target"] = "home"
		exit_door["interaction_text"] = "Back home"
		SaveManager.save_room(demo)


static func home_room() -> Dictionary:
	var r := Defaults.room("home", "Home")
	r["spawn"] = [6, 7]
	var tiles: Array = []
	# A little table with a slab top, a bookshelf of cubes, and two pillars.
	tiles.append({"x": 3, "y": 0, "z": 2, "type": "cube", "color": "#8b5e3c", "texture": "", "rot": 0})
	tiles.append({"x": 4, "y": 0, "z": 2, "type": "cube", "color": "#8b5e3c", "texture": "", "rot": 0})
	tiles.append({"x": 3, "y": 1, "z": 2, "type": "cube", "color": "#a0714d", "texture": "", "rot": 0})
	tiles.append({"x": 8, "y": 0, "z": 4, "type": "slab", "color": "#e8d3b0", "texture": "", "rot": 0})
	tiles.append({"x": 9, "y": 0, "z": 4, "type": "slab", "color": "#e8d3b0", "texture": "", "rot": 0})
	tiles.append({"x": 1, "y": 0, "z": 1, "type": "pillar", "color": "#7b6bb5", "texture": "", "rot": 0})
	tiles.append({"x": 10, "y": 0, "z": 1, "type": "pillar", "color": "#7b6bb5", "texture": "", "rot": 0})
	r["tiles"] = tiles
	r["objects"] = [
		{"id": "sign_welcome", "type": "sign", "pos": [5, 0, 1], "rot": 0, "scale": 1.0, "color": "", "texture": "",
			"interaction_text": "Welcome home. This little world is yours. Build it, fill it, and come back whenever you need a soft place to land.", "door_target": ""},
		{"id": "plant_1", "type": "prop", "pos": [1, 0, 8], "rot": 0, "scale": 1.0, "color": "", "texture": "",
			"interaction_text": "A happy little plant. It seems to lean toward you.", "door_target": ""},
		{"id": "plant_2", "type": "prop", "pos": [10, 0, 8], "rot": 0, "scale": 1.0, "color": "", "texture": "",
			"interaction_text": "This plant has clearly been talked to a lot.", "door_target": ""},
		{"id": "door_garden", "type": "door", "pos": [11, 0, 5], "rot": 1, "scale": 1.0, "color": "", "texture": "",
			"interaction_text": "To the garden", "door_target": "garden"},
	]
	return r


static func garden_room() -> Dictionary:
	var r := Defaults.room("garden", "Garden")
	r["size"] = {"w": 10, "d": 10, "h": 2}
	r["floor"] = {"color": "#3f7a5a", "texture": ""}
	r["wall"] = {"color": "#2a4d3c", "texture": ""}
	r["sky"] = {"color": "#1b2440", "texture": ""}
	r["spawn"] = [1, 5]
	r["tiles"] = [
		{"x": 6, "y": 0, "z": 3, "type": "slab", "color": "#c9a66b", "texture": "", "rot": 0},
		{"x": 7, "y": 0, "z": 3, "type": "slab", "color": "#c9a66b", "texture": "", "rot": 0},
	]
	r["objects"] = [
		{"id": "door_home", "type": "door", "pos": [0, 0, 5], "rot": 1, "scale": 1.0, "color": "", "texture": "",
			"interaction_text": "Back home", "door_target": "home"},
		{"id": "plant_g1", "type": "prop", "pos": [4, 0, 1], "rot": 0, "scale": 1.3, "color": "", "texture": "",
			"interaction_text": "A big leafy friend.", "door_target": ""},
		{"id": "sign_garden", "type": "sign", "pos": [5, 0, 7], "rot": 0, "scale": 1.0, "color": "", "texture": "",
			"interaction_text": "The garden is quiet. Maybe someone will move in here someday.", "door_target": ""},
	]
	return r


## The first friend. Returns the character id.
static func create_mochi(char_name: String = "Mochi", body: Color = Color("#c9b6ff")) -> String:
	var id := SaveManager.unique_id(char_name, SaveManager.list_characters())
	var c := Defaults.character(id, char_name)
	c["personality"] = "Gentle, curious and a little dramatic about snacks. Thinks every small win deserves a celebration."
	c["backstory"] = "Sprouted from a houseplant the day this world was first imagined, and has kept the lights warm ever since."
	c["quirks"] = "hums while thinking, names every dust bunny, keeps a 'diary of Good Things'"
	c["speech_style"] = "soft and playful, short sentences, sometimes ends with ~"
	c["likes"] = "tea, rainy windows, the player's stories, tiny victories"
	c["dislikes"] = "loud alarms, cold toast"
	c["relationship_to_player"] = "your very first friend in this world"
	c["voice_pitch"] = 1.15
	c["voice_sound"] = "chirp"
	c["liked_tags"] = ["tea", "sweet", "cozy", "rain", "stories"]
	c["disliked_tags"] = ["loud", "cold"]
	c["home_room"] = "home"
	c["pos"] = [7, 4]
	c["expressions"] = SpriteFactory.write_blob_set(SaveManager.character_dir(id), body)
	SaveManager.save_character(c)
	return id
