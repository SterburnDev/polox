extends RefCounted
## Save-folder layout versions. Layout 1 (Update 1) kept one world directly
## in the save root; layout 2 keeps worlds in slots/<id>/ with settings and
## audio shared at the root. A zip snapshot of the whole folder is taken
## before anything moves, and files are moved (same drive), never copied or
## deleted. The current layout is recorded in <root>/polox.json.
## Tags: [MIGRATION]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const Slots := preload("res://scripts/core/slots.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")

const LAYOUT := 2
const INFO_FILE := "polox.json"
## Everything that belonged to the single world in layout 1.
const WORLD_FILES: PackedStringArray = ["world.json", "dreams.json", "journal.json"]
const WORLD_DIRS: PackedStringArray = ["rooms", "characters", "logs", "textures", "exports", "backups", "photos", "player", "items"]


static func current_layout(root: String) -> int:
	var info: Variant = JsonUtil.read_json(root.path_join(INFO_FILE), {})
	if info is Dictionary and info.has("layout"):
		return int(info.layout)
	# No info file: a root with a world.json at the top is layout 1; anything else is fresh.
	return 1 if FileAccess.file_exists(root.path_join("world.json")) or DirAccess.dir_exists_absolute(root.path_join("rooms")) else LAYOUT


static func needs_migration(root: String) -> bool:
	return current_layout(root) < LAYOUT


## Runs every step needed to reach LAYOUT. Returns {ok, slot_id, snapshot, error}.
static func migrate(root: String) -> Dictionary:
	var result := {"ok": true, "slot_id": "", "snapshot": "", "error": ""}
	if current_layout(root) == 1:
		result = _to_layout_2(root)
		if not result.ok:
			return result
	JsonUtil.write_json(root.path_join(INFO_FILE), {"layout": LAYOUT, "migrated": Time.get_datetime_string_from_system(false, false)})
	return result


static func _to_layout_2(root: String) -> Dictionary:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	JsonUtil.ensure_dir(root.path_join("snapshots"))
	var zip := root.path_join("snapshots").path_join("before_layout2_%s.zip" % stamp)
	if not SlotArchive.zip_folder(root, zip):
		return {"ok": false, "slot_id": "", "snapshot": "", "error": "could not snapshot the save folder first"}
	var world: Variant = JsonUtil.read_json(root.path_join("world.json"), {})
	var name := str(world.get("name", "My World")) if world is Dictionary else "My World"
	var id := SaveManager.unique_id(name, Slots.ids())
	var dest := root.path_join("slots").path_join(id)
	JsonUtil.ensure_dir(dest)
	for f in WORLD_FILES:
		for suffix in ["", ".bak", ".tmp", ".broken"]:
			if FileAccess.file_exists(root.path_join(f + suffix)):
				DirAccess.rename_absolute(root.path_join(f + suffix), dest.path_join(f + suffix))
	for d in WORLD_DIRS:
		if DirAccess.dir_exists_absolute(root.path_join(d)):
			DirAccess.rename_absolute(root.path_join(d), dest.path_join(d))
	var m := Slots.defaults()
	m["name"] = name
	m["created"] = str(world.get("created", m.created)) if world is Dictionary else m.created
	m["last_played"] = Time.get_datetime_string_from_system(false, false)
	JsonUtil.write_json(dest.path_join(Slots.META), m)
	return {"ok": true, "slot_id": id, "snapshot": zip, "error": ""}
