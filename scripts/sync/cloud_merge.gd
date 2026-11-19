extends RefCounted
## [CLOUD_SYNC] Combining two copies of a world that both changed since they last agreed.
##
## plan() compares three file lists ({path: sha256}): `base` (what both devices had at the last sync),
## `local` (this device now) and `remote` (the cloud copy). Each path lands in exactly one bucket:
##
##   take_remote    only the cloud changed or added it       -> this device takes the cloud's file
##   delete_local   only the cloud removed it                -> this device removes it
##   keep_local     only this device changed, added or removed it -> nothing to do here; it goes up
##   both_changed   both changed it, differently (or one edited what the other removed)
##
## merge_file() then tries each both_changed file: chat logs join by message id, JSON merges field by
## field against the base copy (json_merge.gd, the rules Phone Link already uses). A picture both
## sides repainted, a file one side deleted and the other edited, or a JSON value both set differently
## can't be combined by rule: that is a real conflict and a person decides (cloud_sync.gd).
## Nothing here touches a disk: it is all lists and bytes, so every rule has a direct test.
## Tags: [CLOUD_SYNC]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const JsonMerge := preload("res://scripts/sync/json_merge.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")


## Sorts every path into one bucket. Returns {take_remote, delete_local, keep_local, both_changed}
## (arrays of paths, each sorted) and `same` (how many paths already agree).
static func plan(base: Dictionary, local: Dictionary, remote: Dictionary) -> Dictionary:
	var result := {"take_remote": [], "delete_local": [], "keep_local": [], "both_changed": [], "same": 0}
	var every_path := {}
	for file_list in [base, local, remote]:
		for path in file_list:
			every_path[path] = true
	var paths := every_path.keys()
	paths.sort()
	for path in paths:
		var in_base := str(base.get(path, ""))
		var in_local := str(local.get(path, ""))
		var in_remote := str(remote.get(path, ""))
		if in_local == in_remote:
			result.same += 1
		elif in_local == in_base:
			(result.delete_local if in_remote == "" else result.take_remote).append(path)
		elif in_remote == in_base:
			result.keep_local.append(path)
		else:
			result.both_changed.append(path)
	return result


## Tries to combine one file both sides changed. An empty byte array means "that side has no such
## file". Returns {ok, bytes, why}: `bytes` is the combined file when ok; `why` says, for a person,
## what stood in the way when not.
static func merge_file(path: String, base_bytes: PackedByteArray, local_bytes: PackedByteArray, remote_bytes: PackedByteArray) -> Dictionary:
	if local_bytes.is_empty() or remote_bytes.is_empty():
		return _unmerged("one device removed it and the other changed it")
	if path.ends_with(".jsonl"):
		return {"ok": true, "bytes": SyncFiles.merge_jsonl(local_bytes, remote_bytes), "why": ""}
	if not path.ends_with(".json"):
		return _unmerged("both devices changed this picture")
	if base_bytes.is_empty():
		return _unmerged("both devices changed it and there is no earlier copy to compare with")
	var base: Variant = JsonUtil.parse(base_bytes.get_string_from_utf8())
	var mine: Variant = JsonUtil.parse(local_bytes.get_string_from_utf8())
	var theirs: Variant = JsonUtil.parse(remote_bytes.get_string_from_utf8())
	if base == null or mine == null or theirs == null:
		return _unmerged("one of its copies can't be read")
	var merged := JsonMerge.merge3(base, mine, theirs)
	if not (merged.conflicts as Array).is_empty():
		return _unmerged("both devices changed the same thing in it (%s)" % ", ".join(_changed_parts(merged.conflicts)))
	return {"ok": true, "bytes": JSON.stringify(merged.merged, "\t", false).to_utf8_buffer(), "why": ""}


## The top-level parts of a JSON file that conflict, for a person: ["/name", "/tiles/t1/x"] -> ["name", "tiles"].
static func _changed_parts(conflict_paths: Array) -> PackedStringArray:
	var parts := PackedStringArray()
	for conflict_path in conflict_paths:
		var top := str(conflict_path).trim_prefix("/").get_slice("/", 0).replace("_", " ")
		if top == "":
			top = "the whole file"
		if not top in parts and parts.size() < 3:
			parts.append(top)
	return parts


static func _unmerged(why: String) -> Dictionary:
	return {"ok": false, "bytes": PackedByteArray(), "why": why}


## A few words for a person about a file inside a world ("rooms/kitchen.json" -> the place "Kitchen"),
## for conflict lists. `bytes` is the file's contents when at hand: a place, friend or item is then
## called by the name the player gave it instead of its file name.
static func describe(path: String, bytes: PackedByteArray = PackedByteArray()) -> String:
	var parts := path.split("/")
	var name := parts[parts.size() - 1].get_basename()
	if parts.size() > 2:
		name = parts[1]   # (characters/<id>/..., items/<id>/...)
	if path.ends_with(".json") and not bytes.is_empty():
		var data: Variant = JsonUtil.parse(bytes.get_string_from_utf8())
		if data is Dictionary and str(data.get("name", "")) != "":
			name = str(data.name)
	match parts[0]:
		"rooms":
			return "the place \"%s\"" % name
		"characters":
			return "your friend \"%s\"" % name
		"logs":
			return "a chat (%s)" % name
		"items":
			return "the item \"%s\"" % name
		"player":
			return "your character"
		"textures":
			return "the picture \"%s\"" % name
	match path:
		"world.json":
			return "the world's own details"
		"slot.json":
			return "the world's card (name, colour, notes)"
		"inventory.json":
			return "your bag"
		"journal.json":
			return "your journal"
		"dreams.json":
			return "your dreams"
	return path
