extends RefCounted
## Tile sets: named collections of little pictures (16/32/64 px) with flags
## (solid, walkable, height, tags, step sound, fade, optional 2-4 frame
## animation). A world keeps its own copies under tilesets/<set>/ so it stays
## portable; the Library (shared by every world) holds sets you can add to any
## world ("copy on use").
##
##   tileset.json = {version, id, name, tile_size, atlas?, tiles: [{id, name,
##                   image | rect, solid, walkable, height, tags, step, fade, frames, fps}]}
##   A tile's picture is its own PNG (`image`), or a rectangle of the set's
##   `atlas` PNG (`rect` = [x, y, w, h]).

const JsonUtil := preload("res://scripts/core/json_util.gd")

const META := "tileset.json"
const SIZES: PackedInt32Array = [16, 32, 64]
const MAX_FRAMES := 4
const STEP_SOUNDS: PackedStringArray = ["", "soft", "wood", "stone", "grass", "water", "metal"]
const RECHECK_MS := 1000

static var _cache := {}   # tileset.json path -> {set, by_id, mtime, checked}


static func world_dir() -> String:
	return SaveManager.abs_path("tilesets")


static func library_dir() -> String:
	return SaveManager.global_path("library/tilesets")


static func set_dir(set_id: String, library: bool = false) -> String:
	return (library_dir() if library else world_dir()).path_join(set_id)


static func defaults(id: String = "", name: String = "") -> Dictionary:
	return {"version": 2, "id": id, "name": name, "tile_size": 32, "tiles": [], "smart_groups": []}


static func tile_defaults(id: String = "", name: String = "") -> Dictionary:
	return {"id": id, "name": name, "image": "", "solid": false, "walkable": true, "slippery": false, "height": 1.0, "tags": [], "step": "", "fade": true, "frames": [], "fps": 4}


static func ids(library: bool = false) -> PackedStringArray:
	var out := PackedStringArray()
	for d in JsonUtil.list_dirs(library_dir() if library else world_dir()):
		if FileAccess.file_exists(set_dir(d, library).path_join(META)):
			out.append(d)
	return out


static func load_set(set_id: String, library: bool = false) -> Dictionary:
	var data: Variant = JsonUtil.read_json(set_dir(set_id, library).path_join(META), {})
	var s := JsonUtil.merge_defaults(data if data is Dictionary else {}, defaults(set_id, set_id.capitalize()))
	s["id"] = set_id
	# Version 2 adds optional smart-tile groups; v1 sets remain valid and are
	# upgraded in memory until the player next saves the tile set.
	s["version"] = maxi(2, int(s.get("version", 1)))
	if not s.get("smart_groups") is Array:
		s["smart_groups"] = []
	var tiles: Array = []
	for t in s.get("tiles", []):
		if t is Dictionary and str(t.get("id", "")) != "":
			tiles.append(JsonUtil.merge_defaults(t, tile_defaults()))
	s["tiles"] = tiles
	return s


static func save_set(s: Dictionary, library: bool = false) -> bool:
	var id := str(s.get("id", ""))
	if id == "":
		return false
	JsonUtil.ensure_dir(set_dir(id, library).path_join("tiles"))
	_cache.erase(set_dir(id, library).path_join(META))
	return JsonUtil.write_json(set_dir(id, library).path_join(META), s)


## A set of the active world, cached (re-read when its file changes). Fast
## enough to ask thousands of times while drawing or checking walking.
static func cached_set(set_id: String) -> Dictionary:
	if set_id == "" or SaveManager.slot_id == "":
		return {}
	var path := set_dir(set_id).path_join(META)
	var now := Time.get_ticks_msec()
	var e: Dictionary = _cache.get(path, {})
	if not e.is_empty() and now - int(e.checked) < RECHECK_MS:
		return e.set
	var mtime := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	if not e.is_empty() and int(e.mtime) == mtime:
		e["checked"] = now
		return e.set
	if mtime == 0:
		_cache.erase(path)
		return {}
	var s := load_set(set_id)
	var by_id := {}
	for t in s.tiles:
		by_id[str(t.id)] = t
	_cache[path] = {"set": s, "by_id": by_id, "mtime": mtime, "checked": now}
	return s


## A tile's flags (cached): solid, walkable, step, fade... ({} if unknown).
static func info(set_id: String, tile_id: String) -> Dictionary:
	if cached_set(set_id).is_empty():
		return {}
	var e: Dictionary = _cache.get(set_dir(set_id).path_join(META), {})
	return e.get("by_id", {}).get(tile_id, {})


static func clear_cache() -> void:
	_cache.clear()


## A tile's picture as an Image (its own PNG, or its rectangle of the set's atlas).
static func tile_image(set_id: String, tile_id: String, frame: int = 0) -> Image:
	var s := cached_set(set_id)
	var t := info(set_id, tile_id)
	if t.is_empty():
		return null
	if frame == 0:   # an add-on's picture for this tile ("<set>/<tile>", addons.gd) wins
		var own := preload("res://scripts/core/addons.gd").tile(set_id, tile_id)
		if own:
			return own
	if frame == 0 and t.get("rect") is Array and (t.rect as Array).size() == 4 and str(s.get("atlas", "")) != "":
		var atlas := Image.load_from_file(set_dir(set_id).path_join(str(s.atlas)))
		if atlas == null:
			return null
		var r := Rect2i(int(t.rect[0]), int(t.rect[1]), int(t.rect[2]), int(t.rect[3]))
		return atlas.get_region(r.intersection(Rect2i(Vector2i.ZERO, atlas.get_size())))
	var rel := tile_path(set_id, tile_id, frame)
	if rel == "":
		return null
	var abs_path := SaveManager.abs_path(rel)
	return Image.load_from_file(abs_path) if FileAccess.file_exists(abs_path) else null


static func exists(set_id: String, library: bool = false) -> bool:
	if not library and SaveManager.slot_id == "":
		return false   # no world yet (first start): asking must not create an empty one
	return FileAccess.file_exists(set_dir(set_id, library).path_join(META))


## All sets of the active world, loaded.
static func all(library: bool = false) -> Array:
	var out: Array = []
	for id in ids(library):
		out.append(load_set(id, library))
	return out


static func find_tile(s: Dictionary, tile_id: String) -> Dictionary:
	for t in s.get("tiles", []):
		if str(t.get("id", "")) == tile_id:
			return t
	return {}


## Relative (to the world) path of a tile's picture, or "" if unknown.
static func tile_path(set_id: String, tile_id: String, frame: int = 0) -> String:
	var t := info(set_id, tile_id)
	if t.is_empty():
		return ""
	var frames: Array = t.get("frames", [])
	if frame > 0 and frame < frames.size() + 1 and not frames.is_empty():
		return "tilesets/%s/%s" % [set_id, frames[frame - 1]]
	return "tilesets/%s/%s" % [set_id, t.get("image", "")]


# --- Making sets ----------------------------------------------------------------------

static func create(name: String, tile_size: int = 32, library: bool = false) -> Dictionary:
	var id := SaveManager.unique_id(name, ids(library))
	var s := defaults(id, name.strip_edges() if name.strip_edges() != "" else "Tiles")
	s["tile_size"] = tile_size if tile_size in SIZES else 32
	save_set(s, library)
	return s


## Adds a tile from an Image (resized to the set's size). Returns the tile.
static func add_tile(s: Dictionary, tile_name: String, img: Image, flags: Dictionary = {}, library: bool = false) -> Dictionary:
	var taken := PackedStringArray()
	for t in s.tiles:
		taken.append(str(t.id))
	var want := str(flags.get("id", tile_name if tile_name.strip_edges() != "" else "tile"))
	var tid := SaveManager.unique_id(want, taken)
	var t := tile_defaults(tid, tile_name.strip_edges() if tile_name.strip_edges() != "" else tid.capitalize())
	for k in flags:
		if k != "id":
			t[k] = flags[k]
	t["image"] = "tiles/%s.png" % tid
	var n := int(s.get("tile_size", 32))
	var copy := img.duplicate() as Image
	copy.convert(Image.FORMAT_RGBA8)
	if copy.get_size() != Vector2i(n, n):
		copy.resize(n, n, Image.INTERPOLATE_NEAREST if copy.get_width() <= n * 2 else Image.INTERPOLATE_LANCZOS)
	JsonUtil.ensure_dir(set_dir(str(s.id), library).path_join("tiles"))
	copy.save_png(set_dir(str(s.id), library).path_join(t.image))
	s["tiles"].append(t)
	save_set(s, library)
	return t


## Replaces a tile's picture (keeps its id and flags). Animation frames go in `frames`.
static func set_tile_image(s: Dictionary, tile_id: String, img: Image, frame: int = 0, library: bool = false) -> void:
	var t := find_tile(s, tile_id)
	if t.is_empty():
		return
	var n := int(s.get("tile_size", 32))
	var copy := img.duplicate() as Image
	copy.convert(Image.FORMAT_RGBA8)
	if copy.get_size() != Vector2i(n, n):
		copy.resize(n, n, Image.INTERPOLATE_NEAREST)
	var rel := str(t.image) if frame == 0 else "tiles/%s_f%d.png" % [tile_id, frame]
	copy.save_png(set_dir(str(s.id), library).path_join(rel))
	SaveManager.forget_texture(set_dir(str(s.id), library).path_join(rel))
	if frame > 0:
		var frames: Array = t.get("frames", [])
		while frames.size() < frame:
			frames.append(rel)
		frames[frame - 1] = rel
		t["frames"] = frames.slice(0, MAX_FRAMES - 1)
	save_set(s, library)


static func remove_tile(s: Dictionary, tile_id: String, library: bool = false) -> void:
	var t := find_tile(s, tile_id)
	if t.is_empty():
		return
	DirAccess.remove_absolute(set_dir(str(s.id), library).path_join(str(t.image)))
	for f in t.get("frames", []):
		DirAccess.remove_absolute(set_dir(str(s.id), library).path_join(str(f)))
	s["tiles"].erase(t)
	save_set(s, library)


static func move_tile(s: Dictionary, tile_id: String, delta: int) -> void:
	var tiles: Array = s.tiles
	for i in tiles.size():
		if str(tiles[i].id) == tile_id:
			var j := clampi(i + delta, 0, tiles.size() - 1)
			var t: Dictionary = tiles.pop_at(i)
			tiles.insert(j, t)
			break
	save_set(s)


static func delete_set(set_id: String, library: bool = false) -> void:
	if set_id != "":
		_cache.erase(set_dir(set_id, library).path_join(META))
		JsonUtil.remove_tree(set_dir(set_id, library))


## Rooms of the active world that use a tile of this set (for "in use" warnings).
static func rooms_using(set_id: String, tile_id: String = "") -> PackedStringArray:
	const TileLayers := preload("res://scripts/world/tile_layers.gd")
	var out := PackedStringArray()
	var prefix := "tilesets/%s/" % set_id
	for rid in SaveManager.list_rooms():
		var r := SaveManager.load_room(rid)
		var used := TileLayers.tiles_used(r).any(func(st): return st[0] == set_id and (tile_id == "" or st[1] == tile_id))
		for e in r.get("tiles", []):
			if str(e.get("texture", "")).begins_with(prefix) and (tile_id == "" or str(e.get("texture", "")).get_file().get_basename() == tile_id):
				used = true
		for o in r.get("objects", []):
			if str(o.get("texture", "")).begins_with(prefix):
				used = true
		if used:
			out.append(rid)
	return out


# --- Library (copy on use) ------------------------------------------------------------------

static func copy_to_library(set_id: String) -> bool:
	if not exists(set_id):
		return false
	JsonUtil.remove_tree(set_dir(set_id, true))
	JsonUtil.copy_tree(set_dir(set_id), set_dir(set_id, true))
	return true


## Brings a Library set into the active world (skips if already there).
static func copy_from_library(set_id: String) -> bool:
	if not exists(set_id, true):
		return false
	if exists(set_id):
		return true
	JsonUtil.copy_tree(set_dir(set_id, true), set_dir(set_id))
	return true


# --- Atlas slicing / bundles -------------------------------------------------------------------

## Cuts a PNG atlas into tile_size squares. Returns [{x, y, image}] for every
## cell that has any pixels (empty cells are skipped).
static func slice_atlas(img: Image, tile_size: int, margin: int = 0, spacing: int = 0) -> Array:
	var out: Array = []
	var n := maxi(1, tile_size)
	var y := margin
	var row := 0
	while y + n <= img.get_height():
		var x := margin
		var col := 0
		while x + n <= img.get_width():
			var cell := img.get_region(Rect2i(x, y, n, n))
			if not cell.is_invisible():
				out.append({"x": col, "y": row, "image": cell})
			x += n + spacing
			col += 1
		y += n + spacing
		row += 1
	return out


static func export_set(set_id: String, dest: String) -> bool:
	if not exists(set_id):
		return false
	return preload("res://scripts/core/slot_archive.gd").zip_folder(set_dir(set_id), dest)


## Imports a .polox-tiles zip as a new set of the active world. Returns {ok, id, error}.
static func import_set(path: String) -> Dictionary:
	var Archive := preload("res://scripts/core/slot_archive.gd")
	var check: Dictionary = Archive.inspect_zip(path)
	if not check.ok:
		return {"ok": false, "id": "", "error": check.error}
	if not META in check.files:
		return {"ok": false, "id": "", "error": "not a tile set (no tileset.json inside)"}
	var meta: Variant = JsonUtil.parse(preload("res://scripts/core/slot_archive.gd").read_zip_file(path, META).get_string_from_utf8())
	var name := str(meta.get("name", path.get_file().get_basename())) if meta is Dictionary else path.get_file().get_basename()
	var id := SaveManager.unique_id(name, ids())
	var r: Dictionary = Archive.unzip_to(path, set_dir(id))
	if not r.ok:
		JsonUtil.remove_tree(set_dir(id))
		return {"ok": false, "id": "", "error": r.error}
	var s := load_set(id)
	s["id"] = id
	s["name"] = name
	save_set(s)
	return {"ok": true, "id": id, "error": ""}
