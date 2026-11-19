extends RefCounted
## Versioned upgrades of a world's files. Each step runs once, right before
## the world loads, and only after a "pre_migration" snapshot zip of the
## whole world exists (Worlds > Restore can always go back).
##
## v1 -> v2 (Phase 10): the player gets two forms (the old avatar becomes
## Real Me: a painted avatar stays as it was, the untouched default becomes
## the matching doll), friends get liked/disliked tags from their Likes and
## Dislikes text, and the world gets the starter items and a small bag.
## Tags: [MIGRATION]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const Doll := preload("res://scripts/characters/doll.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const GiftRules := preload("res://scripts/items/gift_rules.gd")
const StarterItems := preload("res://scripts/items/starter_items.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const Places := preload("res://scripts/world/places.gd")
const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const Realms := preload("res://scripts/world/realms.gd")


static func version_of(raw: Dictionary) -> int:
	return int(raw.get("version", 1))


## Upgrades the active world if it's older than this game. Returns
## {migrated: bool, from: int, snapshot: String, error: String}.
static func run() -> Dictionary:
	var raw: Variant = JsonUtil.read_json(SaveManager.world_path(), null)
	if not raw is Dictionary:
		return {"migrated": false}
	var from := version_of(raw)
	if from >= Defaults.WORLD_VERSION:
		return {"migrated": false, "from": from}
	var snap := SlotArchive.snapshot(SaveManager.slot_id, "pre_migration")
	if snap == "":
		# No snapshot, no upgrade: the game still runs on the old data (the
		# readers cope with missing fields) and tries again next time.
		push_warning("World upgrade skipped: the safety snapshot could not be written")
		return {"migrated": false, "from": from, "error": "snapshot failed"}
	if from < 2:
		_to_v2(raw)
	if from < 3:
		_to_v3()
	if from < 4:
		_to_v4()
	if from < 5:
		_to_v5()
	if from < 6:
		_to_v6(raw)
	if from < 7:
		_to_v7()
	if from < 8:
		_to_v8(raw)
	raw["version"] = Defaults.WORLD_VERSION
	JsonUtil.write_json(SaveManager.world_path(), raw)
	return {"migrated": true, "from": from, "snapshot": snap}


## v7 -> v8 (Phase 29): the worlds swap places. Everything in this world is the Dream World (every place
## is labelled "realm": "dark"; nothing moves, nothing is removed), and the start place gets the way
## home: a fountain to the Light World, your real home. Fountains inside the Dream World that said "Back to
## the Light World" now name the place they lead back to.
static func _to_v8(raw: Dictionary) -> void:
	var rooms := {}
	for id in SaveManager.list_rooms():
		rooms[str(id)] = SaveManager.load_room(id)
	for id in rooms:
		var room: Dictionary = rooms[id]
		room["realm"] = Realms.DARK
		for f in DarkWorlds.fountains(room):
			if str(f.get("leads", "")) == "light" and str(f.get("label", "")) == "Back to the Light World":
				var t := DarkWorlds.target(f)
				f["label"] = "Back to %s" % str((rooms.get(t, {}) as Dictionary).get("name", "where you came from"))
	var start := str(raw.get("start_room", "home"))
	if Realms.dark_gate(rooms, start).is_empty():
		add_gate_to_start(rooms, start)
	for id in rooms:
		SaveManager.save_room(rooms[id])


## The way home in the start place (else the first ordinary place with room for it).
static func add_gate_to_start(rooms: Dictionary, start: String) -> String:
	var order: Array = [start] if rooms.has(start) else []
	for id in rooms:
		if not id in order and not DarkWorlds.is_dark(rooms[id]):
			order.append(id)
	for id in order:
		var room: Dictionary = rooms[id]
		var sp: Array = room.get("spawn", [6, 7])
		if not Realms.add_gate(room, Vector2i(int(sp[0]), int(sp[1])), Realms.LIGHT, Realms.ENTRY).is_empty():
			return str(id)
	return ""


## v6 -> v7 (1.13.3): places that still looked like the old rooms open up (Places.open_up_all): outdoorsy
## names become outdoor places, the rest sit in the world (ground and sky around their walls), and the
## starter Garden and Tile Playground are joined edge to edge. Places changed in Build mode stay.
static func _to_v7() -> void:
	var rooms := {}
	for id in SaveManager.list_rooms():
		rooms[str(id)] = SaveManager.load_room(id)
	for id in Places.open_up_all(rooms):
		SaveManager.save_room(rooms[id])


## v5 -> v6 (Phase 25): the Light World and Dream Worlds. Every place is on the Light World side,
## except places set to Dream World Me: they become Dream World places, each reached by a new Dark
## Fountain beside the door that led there (or in the start place), linked both ways. The doors stay.
static func _to_v6(raw: Dictionary) -> void:
	var rooms := {}
	for id in SaveManager.list_rooms():
		# The raw file decides (loading fills in the default side, which would hide Dream World Me places).
		var raw_room: Variant = JsonUtil.read_json(SaveManager.room_path(id), {})
		var room := SaveManager.load_room(id)
		if raw_room is Dictionary and not (raw_room as Dictionary).has("side"):
			room.erase("side")
			DarkWorlds.upgrade_room(room)
			SaveManager.save_room(room)
		rooms[id] = room
	var changed := DarkWorlds.link_old_dark_places(rooms, str(raw.get("start_room", "home")))
	for id in changed:
		SaveManager.save_room(changed[id])


## v4 -> v5 (Phase 24): rooms become places. Each gets the place fields without changing how it
## looks: indoors, all four walls, its own sky colour or picture, no joined edges.
static func _to_v5() -> void:
	for id in SaveManager.list_rooms():
		var room := SaveManager.load_room(id)
		if Places.upgrade_room(room):
			SaveManager.save_room(room)


## v3 -> v4 (Phase 17): the Tile Playground (made by the game in new worlds)
## gets a Platform Pillar, so Platform Mode can be tried. Nothing else changes.
static func _to_v4() -> void:
	for id in SaveManager.list_rooms():
		var room := SaveManager.load_room(id)
		if not str(id).begins_with("tile_playground") and str(room.get("name", "")) != "Tile Playground":
			continue
		if room.get("objects", []).any(func(o): return str(o.get("type", "")) == "platform_pillar"):
			continue
		for cell in [Vector2i(3, 8), Vector2i(2, 8), Vector2i(4, 9), Vector2i(1, 1)]:
			if RoomEditor.in_bounds(room, cell.x, cell.y) and RoomEditor.object_at(room, cell.x, cell.y).is_empty() and RoomEditor.stack_top(room, cell.x, cell.y) == 0.0:
				var o := RoomEditor.add_object(room, cell.x, cell.y, "platform_pillar")
				if not o.is_empty():
					o.merge({"label": "Try Platform Mode", "color": "#c58cff", "repeat": "repeat", "target_room": "", "target_spawn": []}, true)
					SaveManager.save_room(room)
				break


## v2 -> v3: turn each room's old tile lists into sparse, versioned layers.
## The world snapshot above is made before any room is touched.
static func _to_v3() -> void:
	for id in SaveManager.list_rooms():
		var room := SaveManager.load_room(id)
		RoomEditor.sanitize(room)
		room["tile_layers_version"] = 1
		SaveManager.save_room(room)


static func _to_v2(raw: Dictionary) -> void:
	var player: Dictionary = raw.get("player", {}) if raw.get("player") is Dictionary else {}
	var avatar := str(player.get("avatar", ""))
	var forms := {}
	var real := PlayerLook.form_defaults("real")
	if avatar != "" and FileAccess.file_exists(SaveManager.abs_path(avatar)) and not is_default_avatar(SaveManager.abs_path(avatar)):
		real["mode"] = "custom"
		real["expressions"] = {"neutral": avatar}  # the painted file stays exactly where it was
	else:
		real["expressions"] = PlayerLook.write_doll_files("real", real.doll)
		avatar = str(real.expressions.neutral)
	forms["real"] = real
	var dark := PlayerLook.form_defaults("dark")
	dark["expressions"] = PlayerLook.write_doll_files("dark", dark.doll)
	forms["dark"] = dark
	player["forms"] = forms
	player["form"] = "real"
	player["avatar"] = avatar
	raw["player"] = player
	for id in SaveManager.list_characters():
		var path := SaveManager.character_dir(id).path_join("character.json")
		var c: Variant = JsonUtil.read_json(path, null)
		if not c is Dictionary:
			continue
		if not c.has("liked_tags"):
			c["liked_tags"] = GiftRules.derive_tags(str(c.get("likes", "")))
		if not c.has("disliked_tags"):
			c["disliked_tags"] = GiftRules.derive_tags(str(c.get("dislikes", "")))
		JsonUtil.write_json(path, c)
	StarterItems.install(true)


## True if the file is the untouched default avatar the game used to draw.
static func is_default_avatar(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return false
	img.convert(Image.FORMAT_RGBA8)
	var def := SpriteFactory.player()
	return img.get_size() == def.get_size() and img.get_data() == def.get_data()
