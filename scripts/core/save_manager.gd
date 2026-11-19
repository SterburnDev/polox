extends Node
## [PERSONAL_DATA] Autoload that owns the save folder: where it lives, which world (slot) is
## active, and reading/writing each kind of file. Everything is plain JSON
## so players can peek inside. The folder is the PersonalData folder (personal_data.gd: beside
## Polox.exe, the project folder from source, the app's storage on phones); older folders are brought
## over once at start (personal_data_migration.gd [MIGRATION]).
##
##   <root>/settings.json, audio/, library/, polox.json   shared by every world
##   <root>/slots/<id>/world.json, rooms/, characters/... one world each
##   <root>/trash/, snapshots/, exports/                   safety nets
## Tags: [PERSONAL_DATA] [MIGRATION]

signal root_changed(path: String)
signal slot_changed(id: String)
signal save_failed(path: String)
signal saved(path: String)          # any file written through _write (Phone Link pushes after these)

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const Migration := preload("res://scripts/core/migration.gd")
const PersonalData := preload("res://scripts/core/personal_data.gd")
const PersonalDataMigration := preload("res://scripts/core/personal_data_migration.gd")
const LayoutMigration := preload("res://scripts/core/layout_migration.gd")
const Slots := preload("res://scripts/core/slots.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")

## Pictures bigger than this on a side are shrunk when imported or loaded.
const MAX_TEXTURE_SIDE := 2048
## Performance mode (phones) shrinks pictures further when they load.
var max_texture_side := MAX_TEXTURE_SIDE
const MAX_PICTURE_FILE_BYTES := 40 * 1024 * 1024
const FOLDER_NAME := "Polox"
const ROOT_SUBFOLDERS: PackedStringArray = ["slots", "trash", "exports", "snapshots", "library", "audio/music", "audio/sfx"]
const SUBFOLDERS: PackedStringArray = ["rooms", "characters", "logs", "textures", "exports", "backups", "photos", "player"]
const HOME_FOLDER := "my_home"
const LIGHT_PREFIX := "lw_"

var root: String = ""
var slot_id: String = ""           # the active world ("" until one exists)
var _default_location := false     # true when nothing overrode the PersonalData folder
var migration_result: Dictionary = {}
var layout_result: Dictionary = {}
var _tex_cache: Dictionary = {}    # abs path -> [modified_time, Texture2D], most recently used last
var _loaded_files: Dictionary = {} # optimistic-write baselines; never synced or persisted
## Each baseline is a deep copy (rooms can be large on a phone); an evicted file just saves as before.
const MAX_LOADED_FILES := 256
## Pictures kept loaded at most (photos, faces, tiles): on a phone the video memory is small.
const TEX_CACHE_MAX := 96
const SOURCE_KEEP_SIDE := 512


func _init() -> void:
	root = _default_root()


## [MIGRATION] Runs before any other autoload: bring older save folders into PersonalData (copy +
## verify, never move or delete), then update the folder layout.
func _ready() -> void:
	if _default_location:
		var sources := PersonalData.legacy_folders(root)
		migration_result = PersonalDataMigration.run(root, sources)
		if not migration_result.ok:
			# Keep playing from the old folder rather than starting empty.
			push_warning("Moving your saves into PersonalData failed (%s); using the old folder." % migration_result.error)
			root = sources[0]
		elif not migration_result.ran:
			# Already migrated once: the Windows setup may have named another copy to bring over since.
			var requested := PersonalDataMigration.import_requested(root, PersonalData.requested_imports())
			if requested.ran:
				migration_result = requested
	_open_root()
	if _default_location:
		# After every migration (a brand-new folder must look empty to them): the folder's own map.
		PersonalData.write_guide(root)


## [PERSONAL_DATA] Save root: --save-root=PATH (developer tools and tests only), else the PersonalData
## folder. (POLOX_SAVE_ROOT used to override it; now it only names an old folder to bring over.)
func _default_root() -> String:
	# The test runner must never touch the player's real saves.
	for arg in OS.get_cmdline_args():
		if arg.ends_with("run_tests.gd"):
			return ProjectSettings.globalize_path("res://tests/.tmp_save/_boot")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-root="):
			return absolute_folder(arg.trim_prefix("--save-root="))
	_default_location = true
	return PersonalData.folder()


## A folder given on the command line, as a full path with forward slashes. A relative one
## ("tests/.tmp_save/look") is taken from the folder the game was started in, once, here: left
## relative, parts of the game that compare or rebuild paths saw two different folders (a second,
## empty world appeared and files were "recovered" from their backups).
static func absolute_folder(given: String) -> String:
	var folder := given.replace("\\", "/")
	if folder.is_absolute_path():
		return folder.simplify_path()
	var started_in := DirAccess.open(".")
	if started_in == null:
		return folder
	return started_in.get_current_dir().replace("\\", "/").path_join(folder).simplify_path()


func set_root(new_root: String) -> void:
	root = new_root
	slot_id = ""
	_tex_cache.clear()
	_loaded_files.clear()
	_open_root()
	root_changed.emit(new_root)


## Makes the root usable: folders, layout migration, and the active slot.
func _open_root() -> void:
	if not load("res://scripts/home/home_store.gd").recover_transaction():
		push_warning("Home recovery needs attention; its saved recovery copies were kept.")
	for sub in ROOT_SUBFOLDERS:
		JsonUtil.ensure_dir(root.path_join(sub))
	if LayoutMigration.needs_migration(root):
		layout_result = LayoutMigration.migrate(root)
		if not layout_result.ok:
			push_warning("Layout migration failed: " + str(layout_result.error))
	var settings: Variant = JsonUtil.read_json(settings_path(), {})
	var wanted := str(settings.get("active_slot", "")) if settings is Dictionary else ""
	if not Slots.exists(wanted):
		wanted = str(layout_result.get("slot_id", ""))
	if not Slots.exists(wanted):
		var all := Slots.list()
		wanted = str(all[0].id) if not all.is_empty() else ""
	# An empty folder (a first start that never made a world) mustn't hide a real one.
	if wanted != "" and not FileAccess.file_exists(Slots.dir(wanted).path_join("world.json")):
		for m in Slots.list():
			if FileAccess.file_exists(Slots.dir(str(m.id)).path_join("world.json")):
				wanted = str(m.id)
				break
	slot_id = wanted
	if slot_id != "":
		ensure_layout()
		# Remember the pick, so the next start (or another PC reading the file) agrees.
		if settings is Dictionary and str(settings.get("active_slot", "")) != slot_id:
			settings["active_slot"] = slot_id
			JsonUtil.write_json(settings_path(), settings)


## Switches the active world. Pass "" to have none (title screen only).
func set_slot(id: String) -> void:
	if id != "" and not Slots.exists(id):
		return
	slot_id = id
	_tex_cache.clear()
	_loaded_files.clear()
	if slot_id != "":
		ensure_layout()
	var settings: Variant = JsonUtil.read_json(settings_path(), {})
	var s: Dictionary = settings if settings is Dictionary else {}
	if str(s.get("active_slot", "")) != slot_id:
		s["active_slot"] = slot_id
		JsonUtil.write_json(settings_path(), s)
	slot_changed.emit(slot_id)


## A brand-new empty world folder, made active. Returns its id.
func new_slot(world_name: String, emoji: String = "", accent: String = "") -> String:
	var id := Slots.create(world_name, emoji, accent)
	set_slot(id)
	return id


## Guarantees there is an active slot (tests and old code paths write
## world files without creating one first).
func ensure_slot(world_name: String = "My World") -> String:
	if slot_id == "":
		new_slot(world_name)
	return slot_id


func slot_dir() -> String:
	if slot_id == "":
		ensure_slot()
	return Slots.dir(slot_id)


func ensure_layout() -> void:
	if slot_id == "":
		return
	for sub in SUBFOLDERS:
		JsonUtil.ensure_dir(slot_dir().path_join(sub))


# --- Paths -------------------------------------------------------------------

## A path inside the active world's folder (absolute paths pass through).
func abs_path(rel: String) -> String:
	if rel.is_absolute_path():
		return rel
	return slot_dir().path_join(rel)


## A path shared by every world (settings, audio, library, exports).
func global_path(rel: String) -> String:
	return root.path_join(rel)


func world_path() -> String:
	return abs_path("world.json")


func settings_path() -> String:
	return global_path("settings.json")


## Light World places ("lw_" ids, realms.gd) live in my_home/places/, outside every world.
func room_path(id: String) -> String:
	if id.begins_with(LIGHT_PREFIX):
		return home_dir().path_join("places").path_join(id + ".json")
	return abs_path("rooms").path_join(id + ".json")


## Your real home (the Light World): private, shared by every world on this PC, never synced,
## exported or snapshotted with a world. Settings > Light World > Forget my home deletes it all.
func home_dir() -> String:
	return root.path_join(HOME_FOLDER)


func character_dir(id: String) -> String:
	return abs_path("characters").path_join(id)


func logs_dir() -> String:
	return abs_path("logs")


# --- World / settings / dreams / journal ---------------------------------------

func has_world() -> bool:
	return slot_id != "" and FileAccess.file_exists(world_path())


func load_world() -> Dictionary:
	return _load_kind(world_path(), Defaults.world())


func save_world(data: Dictionary) -> bool:
	return _write(world_path(), data)


## Every save goes through here so a failure can be shown to the player.
func _write(file: String, data: Variant) -> bool:
	var output: Variant = data
	var tracked: bool = data is Dictionary and _loaded_files.has(file)
	var exists := FileAccess.file_exists(file)
	var changed_on_disk: bool = tracked and ((not exists and str(_loaded_files[file].sha) != "") or (exists and str(_loaded_files[file].sha) != FileAccess.get_sha256(file)))
	# (parse_file, not read_json: reading must not "rescue" a deleted file from its .bak here.)
	var latest: Variant = JsonUtil.parse_file(file) if changed_on_disk else null
	# A stale editor must not resurrect a remotely deleted file or overwrite an
	# unreadable replacement. Keep its local work separately for recovery.
	if changed_on_disk and not latest is Dictionary:
		var stash := global_path("conflicts/local_save").path_join("%d_%s" % [Time.get_ticks_usec(), file.get_file()])
		if JsonUtil.write_json(stash, data):
			GameState.notify("This file changed or was removed elsewhere. Your local copy was kept in conflicts/local_save.")
		save_failed.emit(file)
		return false
	if latest is Dictionary:
		var base: Variant = _loaded_files[file].data
		var merge: Script = load("res://scripts/sync/json_merge.gd")
		# A sync chose newer disk data while an editor/conversation was still open.
		# Preserve only the fields this local caller changed from its loaded baseline.
		var merged: Dictionary = merge.merge3(base, latest, data)
		if not merged.merged is Dictionary:
			save_failed.emit(file)
			return false
		if not (merged.conflicts as Array).is_empty():
			var stash := global_path("conflicts/local_save").path_join("%d_%s" % [Time.get_ticks_usec(), file.get_file()])
			if not JsonUtil.write_json(stash, data):
				save_failed.emit(file)
				return false
			GameState.notify("Changes overlapped with a sync. The synced values were kept; your local copy is in conflicts/local_save.")
		output = merged.merged
	var ok := JsonUtil.write_json(file, output)
	if not ok:
		save_failed.emit(file)
	else:
		if data is Dictionary and output is Dictionary and not is_same(data, output):
			data.clear()
			data.merge(output, true)
		_remember(file, output)
		saved.emit(file)
	return ok


func _remember(file: String, data: Variant) -> void:
	_loaded_files.erase(file)
	# Only files a sync can change underneath the game (a world's, the shared home's) need a baseline;
	# settings.json and the other files at the root never sync, so a save there simply writes.
	if not (file.begins_with(root.path_join("slots").path_join("")) or file.begins_with(home_dir().path_join(""))):
		return
	_loaded_files[file] = {"sha": FileAccess.get_sha256(file) if FileAccess.file_exists(file) else "", "data": data.duplicate(true) if data is Dictionary or data is Array else data}
	while _loaded_files.size() > MAX_LOADED_FILES:
		_loaded_files.erase(_loaded_files.keys()[0])


## Explicit restore/import paths replace files themselves and then reload; discard any
## older write baseline before loading that intentional replacement.
func forget_baselines(file: String = "") -> void:
	if file == "":
		_loaded_files.clear()
	else:
		_loaded_files.erase(file)


func forget_baselines_under(folder: String) -> void:
	for file in _loaded_files.keys():
		if str(file).begins_with(folder.path_join("")):
			_loaded_files.erase(file)


func load_settings() -> Dictionary:
	return _load_kind(settings_path(), Defaults.settings())


func save_settings(data: Dictionary) -> bool:
	data["active_slot"] = slot_id
	return _write(settings_path(), data)


func load_dreams() -> Dictionary:
	return _load_kind(abs_path("dreams.json"), Defaults.dreams())


func save_dreams(data: Dictionary) -> bool:
	return _write(abs_path("dreams.json"), data)


func load_inventory() -> Dictionary:
	return _load_kind(abs_path("inventory.json"), Defaults.inventory())


func save_inventory(data: Dictionary) -> bool:
	return _write(abs_path("inventory.json"), data)


func load_journal() -> Dictionary:
	return _load_kind(abs_path("journal.json"), Defaults.journal())


func save_journal(data: Dictionary) -> bool:
	return _write(abs_path("journal.json"), data)


func _load_kind(file: String, defaults: Dictionary) -> Dictionary:
	var data: Variant = JsonUtil.read_json(file, {})
	if not data is Dictionary:
		data = {}
	# Incidental reads (maps, inspectors) must not replace an open editor's baseline.
	# GameState.load_world clears baselines when it actually adopts a new disk state.
	if not _loaded_files.has(file):
		_remember(file, data)
	return JsonUtil.merge_defaults(data, defaults)


# --- Rooms -------------------------------------------------------------------

## This world's places: the Dream World (Light World places are listed by list_light_rooms).
func list_rooms() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in JsonUtil.list_files(abs_path("rooms"), ["json"]):
		ids.append(f.get_basename())
	return ids


## The Light World's places (your real home and street), shared by every world.
func list_light_rooms() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in JsonUtil.list_files(home_dir().path_join("places"), ["json"]):
		if f.get_basename().begins_with(LIGHT_PREFIX):
			ids.append(f.get_basename())
	return ids


func room_exists(id: String) -> bool:
	return FileAccess.file_exists(room_path(id))


func load_room(id: String) -> Dictionary:
	if id.begins_with(LIGHT_PREFIX) and not load("res://scripts/home/home_store.gd").recover_transaction():
		return Defaults.room(id, id.capitalize())
	var room := _load_kind(room_path(id), Defaults.room(id, id.capitalize()))
	room["id"] = id
	var dropped := RoomEditor.sanitize(room)
	if dropped > 0:
		push_warning("Room %s: dropped %d malformed entries" % [id, dropped])
	return room


func save_room(data: Dictionary) -> bool:
	return _write(room_path(str(data.get("id", "room"))), data)


## Its .bak/.tmp go too (read_json would otherwise bring a deleted room back), and so does its write
## baseline (a new room with this id is a new file, not a conflict with the deleted one).
func delete_room(id: String) -> void:
	JsonUtil.remove_file(room_path(id))
	forget_baselines(room_path(id))


# --- Characters ----------------------------------------------------------------

func list_characters() -> PackedStringArray:
	var ids := PackedStringArray()
	for d in JsonUtil.list_dirs(abs_path("characters")):
		if FileAccess.file_exists(character_dir(d).path_join("character.json")):
			ids.append(d)
	return ids


func load_character(id: String) -> Dictionary:
	var c := _load_kind(character_dir(id).path_join("character.json"), Defaults.character(id, id.capitalize()))
	c["id"] = id
	return c


func save_character(data: Dictionary) -> bool:
	var id := str(data.get("id", ""))
	if id == "":
		return false
	return _write(character_dir(id).path_join("character.json"), data)


func delete_character(id: String) -> void:
	if id != "":
		JsonUtil.remove_tree(character_dir(id))
		forget_baselines_under(character_dir(id))


## Absolute path of a character's expression PNG ("" if it has none).
func expression_path(character: Dictionary, emotion: String) -> String:
	var rel := str(character.get("expressions", {}).get(emotion, ""))
	if rel == "":
		return ""
	return character_dir(str(character.get("id", ""))).path_join(rel)


# --- Ids ---------------------------------------------------------------------

## Makes a readable id from a name that doesn't clash with `taken`.
func unique_id(display_name: String, taken: PackedStringArray) -> String:
	var base := JsonUtil.slugify(display_name)
	var id := base
	var n := 2
	while id in taken:
		id = "%s_%d" % [base, n]
		n += 1
	return id


# --- Textures ----------------------------------------------------------------

## Loads a PNG/JPG from disk as a texture, cached until the file changes.
## Returns null if it can't be read (callers fall back to a color).
func load_texture(file: String) -> Texture2D:
	if file == "":
		return null
	var full := abs_path(file)
	if not FileAccess.file_exists(full):
		return null
	var mtime := FileAccess.get_modified_time(full)
	if _tex_cache.has(full) and _tex_cache[full][0] == mtime:
		var hit: Array = _tex_cache[full]
		_tex_cache.erase(full)
		_tex_cache[full] = hit   # most recently used last
		return hit[1]
	var img := load_picture(full)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	# A character-sized picture keeps its pixels on the CPU (transform_fx.gd SOURCE_IMAGE): blinking, the
	# Dream World look and the transformation read them there instead of back from a phone's GPU.
	if maxi(img.get_width(), img.get_height()) <= SOURCE_KEEP_SIDE:
		tex.set_meta(&"polox_source_image", img)
	_tex_cache.erase(full)
	_tex_cache[full] = [mtime, tex]
	while _tex_cache.size() > TEX_CACHE_MAX:
		_tex_cache.erase(_tex_cache.keys()[0])   # the least recently used (anything on screen keeps its own copy)
	return tex


## Opens a PNG/JPG/WebP as an Image, refusing absurd files and shrinking huge
## ones to MAX_TEXTURE_SIDE so a phone photo can't eat all the video memory.
## Returns null if the file can't be used.
func load_picture(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_PICTURE_FILE_BYTES or f.get_length() == 0:
		return null
	f.close()
	var img := Image.load_from_file(path)
	if img == null or img.is_empty() or img.get_width() < 1 or img.get_height() < 1:
		return null
	if img.get_width() > max_texture_side or img.get_height() > max_texture_side:
		var scale := float(max_texture_side) / maxf(img.get_width(), img.get_height())
		img.resize(maxi(1, roundi(img.get_width() * scale)), maxi(1, roundi(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func forget_texture(file: String) -> void:
	_tex_cache.erase(abs_path(file))


## Brings a player-chosen picture into textures/ (validated, shrunk if huge,
## always saved as PNG) and returns its relative path, or "" if unusable.
func import_texture(src: String) -> String:
	var img := load_picture(src)
	if img == null:
		return ""
	var dest_name := "%s_%d.png" % [JsonUtil.slugify(src.get_file().get_basename()), Time.get_ticks_msec() % 100000]
	var rel := "textures/" + dest_name
	JsonUtil.ensure_dir(abs_path("textures"))
	if img.save_png(abs_path(rel)) != OK:
		return ""
	return rel


# --- Backup / folders --------------------------------------------------------

## Zips the active world into its backups/ folder (a "manual" snapshot).
## Settings (and the API key) live outside the world, so they are never inside.
func backup() -> String:
	if slot_id == "":
		return ""
	return preload("res://scripts/core/slot_archive.gd").snapshot(slot_id, "manual")


## [PERSONAL_DATA] Settings > Gameplay > Open Personal Data Folder: the whole folder (every world,
## settings, keys, backups). Phones and the browser can't show their private storage: they say where it is.
func open_personal_data() -> void:
	if not PersonalData.open(root):
		GameState.notify("Your data is in Polox's own storage here. Back up now saves a copy.")


func open_folder(sub: String = "") -> void:
	if OS.has_feature("web") or OS.has_feature("android"):
		GameState.notify("On the phone your files live inside Polox's own storage; use the PC to open them.")
		return
	var target := abs_path(sub) if sub != "" else slot_dir()
	JsonUtil.ensure_dir(target)
	OS.shell_open(target)
