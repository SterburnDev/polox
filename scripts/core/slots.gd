extends RefCounted
## Save slots: every world lives in its own folder under <root>/slots/<id>/
## with a slot.json card (name, cover, colour, notes, tags, playtime...).
## Deleting moves the folder to <root>/trash/ for 30 days. Zips (snapshots,
## bundles, restore, verify) live in slot_archive.gd.

const JsonUtil := preload("res://scripts/core/json_util.gd")

const META := "slot.json"
const TRASH_DAYS := 30
const EMOJIS: PackedStringArray = ["🌙", "⭐", "🌸", "🍄", "🏠", "🌊", "🔥", "🍵", "🎸", "🐱", "🦊", "🐸", "🌵", "🍰", "🎀", "👾", "🗝", "🕯", "☂", "🪐", "🎈", "📚", "🧸", "💜"]
const ACCENTS: PackedStringArray = ["#c9b6ff", "#ffb3c7", "#7ad6b0", "#8fd3ff", "#ffd166", "#ff9f43", "#e86a8a", "#9a94b0"]


static func defaults() -> Dictionary:
	return {
		"version": 1,
		"name": "My World",
		"emoji": "🌙",
		"accent": "#c9b6ff",
		"notes": "",
		"tags": [],
		"cover": "auto",            # "auto" (cover.png screenshot) | "custom" (cover_custom.png)
		"created": Time.get_datetime_string_from_system(false, false),
		"last_played": "",
		"playtime_s": 0,
		"autosave": {"enabled": true, "interval_min": 10, "on_room_change": true, "on_quit": true, "keep": 10},
	}


static func slots_root() -> String:
	return SaveManager.root.path_join("slots")


static func trash_root() -> String:
	return SaveManager.root.path_join("trash")


static func dir(id: String) -> String:
	return slots_root().path_join(id)


static func exists(id: String) -> bool:
	return id != "" and DirAccess.dir_exists_absolute(dir(id))


static func ids() -> PackedStringArray:
	return JsonUtil.list_dirs(slots_root())


static func meta(id: String) -> Dictionary:
	var m: Variant = JsonUtil.read_json(dir(id).path_join(META), {})
	var out := JsonUtil.merge_defaults(m if m is Dictionary else {}, defaults())
	out["id"] = id
	return out


static func save_meta(id: String, m: Dictionary) -> bool:
	var copy := m.duplicate(true)
	copy.erase("id")
	copy.erase("stats")
	return JsonUtil.write_json(dir(id).path_join(META), copy)


## Every slot's card, newest-played first, with live counts attached.
static func list() -> Array:
	var out: Array = []
	for id in ids():
		var m := meta(id)
		m["stats"] = stats(id)
		out.append(m)
	out.sort_custom(func(a, b): return str(a.last_played) > str(b.last_played))
	return out


## Makes an empty slot folder and card. Returns the new id.
static func create(name: String, emoji: String = "", accent: String = "") -> String:
	var id := SaveManager.unique_id(name if name.strip_edges() != "" else "world", ids())
	JsonUtil.ensure_dir(dir(id))
	var m := defaults()
	m["name"] = name.strip_edges() if name.strip_edges() != "" else "My World"
	if emoji != "":
		m["emoji"] = emoji
	if accent != "":
		m["accent"] = accent
	var n := ids().size()
	if emoji == "":
		m["emoji"] = EMOJIS[(n - 1) % EMOJIS.size()]
	if accent == "":
		m["accent"] = ACCENTS[(n - 1) % ACCENTS.size()]
	save_meta(id, m)
	return id


static func duplicate_slot(id: String) -> String:
	var m := meta(id)
	var new_id := SaveManager.unique_id(str(m.name) + " copy", ids())
	JsonUtil.copy_tree(dir(id), dir(new_id))
	m["name"] = str(m.name) + " (copy)"
	m["last_played"] = ""
	m["playtime_s"] = 0
	m["created"] = Time.get_datetime_string_from_system(false, false)
	save_meta(new_id, m)
	return new_id


## Counts and size shown on the card (walks the folder; slots are small).
static func stats(id: String) -> Dictionary:
	var d := dir(id)
	var rooms := JsonUtil.list_files(d.path_join("rooms"), ["json"]).size()
	var chars := 0
	for c in JsonUtil.list_dirs(d.path_join("characters")):
		if FileAccess.file_exists(d.path_join("characters").path_join(c).path_join("character.json")):
			chars += 1
	var items := JsonUtil.list_files(d.path_join("items"), ["json"]).size()
	return {"rooms": rooms, "characters": chars, "items": items, "bytes": folder_bytes(d, true)}


## Bytes in a folder; `skip_backups` leaves out backups/ (shown separately).
static func folder_bytes(path: String, skip_backups: bool = false) -> int:
	var total := 0
	if not DirAccess.dir_exists_absolute(path):
		return 0
	for sub in DirAccess.get_directories_at(path):
		if skip_backups and sub in ["backups", "conflicts"]:
			continue
		total += folder_bytes(path.path_join(sub))
	for f in DirAccess.get_files_at(path):
		var fa := FileAccess.open(path.path_join(f), FileAccess.READ)
		if fa:
			total += fa.get_length()
	return total


## Marks a slot as played now and adds session time.
static func touch(id: String, played_seconds: float = 0.0) -> void:
	if not exists(id):
		return
	var m := meta(id)
	m["last_played"] = Time.get_datetime_string_from_system(false, false)
	m["playtime_s"] = int(m.get("playtime_s", 0)) + int(played_seconds)
	save_meta(id, m)


## Phone Link: may a paired phone see and play this world? (Default: yes.)
static func on_phone(id: String) -> bool:
	return exists(id) and bool(meta(id).get("on_phone", true))


static func set_on_phone(id: String, on: bool) -> void:
	if not exists(id):
		return
	var m := meta(id)
	m["on_phone"] = on
	save_meta(id, m)


## The worlds a paired phone may see: every world not in the trash, minus the
## ones switched off in the Save menu.
static func phone_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids():
		if on_phone(id):
			out.append(id)
	return out


static func cover_path(id: String) -> String:
	var m := meta(id)
	var custom := dir(id).path_join("cover_custom.png")
	if str(m.get("cover", "auto")) == "custom" and FileAccess.file_exists(custom):
		return custom
	var auto := dir(id).path_join("cover.png")
	return auto if FileAccess.file_exists(auto) else ""


# --- Trash -------------------------------------------------------------------------------

## Moves the slot folder to trash/<id>__<stamp>/ (nothing is deleted).
static func delete_to_trash(id: String) -> String:
	if not exists(id):
		return ""
	JsonUtil.ensure_dir(trash_root())
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var name := "%s__%s" % [id, stamp]
	if DirAccess.rename_absolute(dir(id), trash_root().path_join(name)) != OK:
		return ""
	JsonUtil.write_json(trash_root().path_join(name).path_join("trash.json"), {"original_id": id, "deleted_unix": Time.get_unix_time_from_system(), "deleted": Time.get_datetime_string_from_system(false, false)})
	return name


## Trashed worlds with how many days they have left.
static func trash_list() -> Array:
	var out: Array = []
	for name in JsonUtil.list_dirs(trash_root()):
		var t: Variant = JsonUtil.read_json(trash_root().path_join(name).path_join("trash.json"), {})
		var info: Dictionary = t if t is Dictionary else {}
		var m: Variant = JsonUtil.read_json(trash_root().path_join(name).path_join(META), {})
		var card := JsonUtil.merge_defaults(m if m is Dictionary else {}, defaults())
		var age_days := (Time.get_unix_time_from_system() - float(info.get("deleted_unix", 0))) / 86400.0
		out.append({"trash_name": name, "id": str(info.get("original_id", name)), "name": card.name, "emoji": card.emoji, "deleted": str(info.get("deleted", "")), "days_left": maxi(0, ceili(TRASH_DAYS - age_days))})
	out.sort_custom(func(a, b): return str(a.deleted) > str(b.deleted))
	return out


## Brings a trashed world back (under its old id, or a free one). Returns the id.
static func restore_from_trash(trash_name: String) -> String:
	var src := trash_root().path_join(trash_name)
	if not DirAccess.dir_exists_absolute(src):
		return ""
	var t: Variant = JsonUtil.read_json(src.path_join("trash.json"), {})
	var want := str(t.get("original_id", trash_name.split("__")[0])) if t is Dictionary else trash_name.split("__")[0]
	var id := want if not exists(want) else SaveManager.unique_id(want, ids())
	JsonUtil.ensure_dir(slots_root())
	if DirAccess.rename_absolute(src, dir(id)) != OK:
		return ""
	DirAccess.remove_absolute(dir(id).path_join("trash.json"))
	return id


static func delete_forever(trash_name: String) -> void:
	if trash_name.find("..") != -1 or trash_name == "":
		return
	JsonUtil.remove_tree(trash_root().path_join(trash_name))


## Removes trash older than TRASH_DAYS. Returns how many were removed.
static func purge_trash(now_unix: float = Time.get_unix_time_from_system()) -> int:
	var n := 0
	for name in JsonUtil.list_dirs(trash_root()):
		var t: Variant = JsonUtil.read_json(trash_root().path_join(name).path_join("trash.json"), {})
		var deleted := float(t.get("deleted_unix", now_unix)) if t is Dictionary else now_unix
		if now_unix - deleted > TRASH_DAYS * 86400.0:
			delete_forever(name)
			n += 1
	return n


# --- Formatting helpers for cards -------------------------------------------------------

static func playtime_text(seconds: int) -> String:
	if seconds < 60:
		return "under a minute"
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	return ("%dh %dm" % [h, m]) if h > 0 else ("%dm" % m)


static func size_text(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.0f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / 1048576.0)


static func ago_text(iso: String) -> String:
	if iso == "":
		return "never played"
	# The string is local time; the parser assumes UTC, so undo the zone offset.
	var unix := Time.get_unix_time_from_datetime_string(iso) - int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var diff := Time.get_unix_time_from_system() - unix
	if diff < 90:
		return "just now"
	if diff < 3600:
		return "%d min ago" % int(diff / 60)
	if diff < 86400:
		return "%d h ago" % int(diff / 3600)
	var days := int(diff / 86400)
	return "yesterday" if days == 1 else "%d days ago" % days
