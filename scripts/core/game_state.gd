extends Node
## Autoload holding the loaded world in memory: settings, world, characters,
## dreams and journal. Screens read from here and call save_* after edits.

signal settings_changed
signal world_loaded
signal character_changed(id: String)
signal dreams_changed
signal journal_changed
signal inventory_changed
signal toast(text: String)

const Defaults := preload("res://scripts/core/defaults.gd")
const MoodSim := preload("res://scripts/characters/mood_sim.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const WorldMigration := preload("res://scripts/core/world_migration.gd")

var settings: Dictionary = Defaults.settings()
var world: Dictionary = {}
var characters: Dictionary = {}   # id -> character dict
var dreams: Dictionary = Defaults.dreams()
var journal: Dictionary = Defaults.journal()
var inventory: Dictionary = Defaults.inventory()
var current_room_id: String = ""
var current_realm := "dark"


func _ready() -> void:
	SaveManager.save_failed.connect(func(path):
		notify("Couldn't save %s. Is the disk full, or the Documents folder read-only?" % path.get_file()))
	reload_settings()


## The last of the game to leave the tree (the scene goes before the autoloads): what would otherwise
## outlive the renderer and the audio server at quit is let go here.
func _exit_tree() -> void:
	preload("res://scripts/characters/player_look.gd").invalidate()
	preload("res://scripts/items/item_art.gd").clear_cache()
	# Every other cache of meshes, materials, shaders, pictures and sounds kept in a script.
	load("res://scripts/core/memory_relief.gd").release_at_exit()
	# Work started in the very last frame, whose keeper never joined the tree; and one mix pass for the
	# songs stopped on the way out (the music, a battle's, the Survey's). Only if this run used them.
	for closing in [["res://scripts/core/background_job.gd", "shutdown"], ["res://scripts/core/audio_exit.gd", "settle"]]:
		if ResourceLoader.has_cached(str(closing[0])):
			(load(str(closing[0])) as Script).call(str(closing[1]))


func reload_settings() -> void:
	SaveManager.ensure_layout()
	settings = SaveManager.load_settings()
	var keys_moved: bool = settings.get("ai") is Dictionary and preload("res://scripts/ai/presets.gd").migrate_keys(settings.ai)
	if not FileAccess.file_exists(SaveManager.settings_path()) or preload("res://scripts/core/graphics.gd").migrate(settings) or keys_moved:
		SaveManager.save_settings(settings)
	AIClient.configure(settings.get("ai", {}))
	settings_changed.emit()


func save_settings() -> void:
	SaveManager.save_settings(settings)
	AIClient.configure(settings.get("ai", {}))
	settings_changed.emit()


func has_world() -> bool:
	return SaveManager.has_world()


## Loads everything for play. Safe to call again after switching save roots. `from_other_device`: the files
## just came from the PC or the phone (a sync) and are up to date, so nothing is caught up or written back:
## writing them back changed them again, which sent them straight back to the other device, every sync.
func load_world(from_other_device: bool = false) -> void:
	SaveManager.forget_baselines()
	var upgraded := WorldMigration.run()
	world = SaveManager.load_world()
	characters.clear()
	var now := Time.get_unix_time_from_system()
	var hour := MoodSim.now_hour()
	for id in SaveManager.list_characters():
		var c := SaveManager.load_character(id)
		characters[id] = c
		if not from_other_device:
			MoodSim.catch_up(c, now, hour)  # time passed while the game was closed
			SaveManager.save_character(c)
	dreams = SaveManager.load_dreams()
	journal = SaveManager.load_journal()
	inventory = SaveManager.load_inventory()
	_report_recoveries()
	if bool(upgraded.get("migrated", false)):
		if int(upgraded.get("from", 0)) >= 7:
			notify("Everything here is the Dream World now. There's a Dream Gate in %s: the way home, to the Light World. A snapshot was saved first (Worlds > Restore)." % str(SaveManager.load_room(str(world.get("start_room", "home"))).get("name", "your start place")))
		elif int(upgraded.get("from", 0)) >= 6:
			notify("Your places opened up: outdoor places are outdoors and joined, and indoor ones sit in the world. A snapshot was saved first (Worlds > Restore).")
		else:
			notify("This world was upgraded for the new features (a snapshot was saved first: Worlds > Restore).")
	# Pick up where you left off (the start room is for the very first visit).
	current_room_id = str(world.get("last_room", ""))
	if current_room_id.begins_with("lw_") and not SaveManager.room_exists(current_room_id):
		current_room_id = load("res://scripts/world/light_home.gd").recover_entry()
	if current_room_id == "" or not SaveManager.room_exists(current_room_id):
		current_room_id = str(world.get("start_room", "home"))
	if not SaveManager.room_exists(current_room_id):
		var rooms := SaveManager.list_rooms()
		current_room_id = rooms[0] if not rooms.is_empty() else "home"
		if rooms.is_empty():
			SaveManager.save_room(Defaults.room("home", "Home"))
	preload("res://scripts/characters/player_look.gd").apply_room(SaveManager.load_room(current_room_id), false)
	preload("res://scripts/items/inventory.gd").normalize()
	if not from_other_device:
		preload("res://scripts/ai/chat_backup.gd").auto_backup_if_due()   # once a day while there are chats
	world_loaded.emit()


func save_world() -> void:
	preload("res://scripts/characters/player_look.gd").normalize()
	SaveManager.save_world(world)


## A file was broken (crash, disk full, hand edit) and its backup was used.
func _report_recoveries() -> void:
	if JsonUtil.recoveries.is_empty():
		return
	var names := PackedStringArray()
	for p in JsonUtil.recoveries:
		names.append(p.get_file())
	JsonUtil.recoveries.clear()
	notify("Restored %s from a backup copy (the broken file was kept as .broken)." % ", ".join(names))


func player_name() -> String:
	return str(world.get("player", {}).get("name", ""))


## What friends call you this time: your name, or now and then a nickname.
func call_name() -> String:
	var nicks := nicknames()
	if not nicks.is_empty() and (player_name() == "" or randf() < 0.35):
		return nicks[randi() % nicks.size()]
	return player_name()


func nicknames() -> PackedStringArray:
	var out := PackedStringArray()
	for n in str(world.get("player", {}).get("nicknames", "")).split(",", false):
		if n.strip_edges() != "":
			out.append(n.strip_edges())
	return out


func save_inventory() -> bool:
	preload("res://scripts/items/inventory.gd").normalize()
	if not SaveManager.save_inventory(inventory):
		return false
	inventory_changed.emit()
	return true


# --- Characters ----------------------------------------------------------------

func get_character(id: String) -> Dictionary:
	return characters.get(id, {})


func save_character(c: Dictionary) -> void:
	var id := str(c.get("id", ""))
	if id == "":
		return
	characters[id] = c
	SaveManager.save_character(c)
	character_changed.emit(id)


## Residents in a room right now: their daily routine for this part of the
## day decides (routines.gd), else their home room.
func characters_in_room(room_id: String) -> Array:
	var Routines: GDScript = load("res://scripts/variety/routines.gd")
	var out: Array = []
	for id in characters:
		if str(Routines.room_now(characters[id])) == room_id:
			out.append(characters[id])
	return out


func expression_names(c: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for k in c.get("expressions", {}):
		names.append(str(k))
	if not "neutral" in names:
		names.insert(0, "neutral")
	return names


# --- Dreams & journal ------------------------------------------------------------

func dream_list() -> Array:
	return dreams.get("dreams", [])


func save_dreams() -> void:
	SaveManager.save_dreams(dreams)
	dreams_changed.emit()


func add_dream(text: String) -> Dictionary:
	var d := {"id": "d%d" % Time.get_unix_time_from_system(), "text": text.strip_edges(), "status": "dreaming", "created": Defaults.now_iso()}
	dreams["dreams"].append(d)
	save_dreams()
	return d


## Adds a Memory Book moment. kind: "auto" or "manual".
func add_moment(title: String, text: String, character_id: String = "", kind: String = "auto", extra: Dictionary = {}) -> Dictionary:
	var m := {
		"id": "m%d_%d" % [Time.get_unix_time_from_system(), randi() % 1000],
		"ts": Defaults.now_iso(),
		"title": ChatLog.redact(title),
		"text": ChatLog.redact(text),   # a key pasted into a chat must not end up in the Memory Book
		"character": character_id,
		"room": current_room_id,
		"kind": kind,
	}
	m.merge(extra)
	journal["moments"].append(m)
	SaveManager.save_journal(journal)
	journal_changed.emit()
	return m


func notify(text: String) -> void:
	toast.emit(text)
