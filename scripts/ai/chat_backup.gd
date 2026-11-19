extends RefCounted
## Chat backups: every friend's conversations and memories in one file, to keep, move to another
## computer or bring back. <save folder>/chat_backups/<world>/chats_<date>_<kind>.zip holds
##   manifest.json        {app, kind, world, world_name, made, friends: [{id, name, messages}]}
##   logs/<id>.jsonl      the conversation, line for line
##   memories/<id>.json   {name, memory_notes, summary, summary_upto, relationship, ai_model}
## Made from Friends (Back up chats), once a day by itself while there are chats, and before every
## restore. Restoring merges, it never erases: messages come back without doubling the ones still here
## (each has an id), notes are joined, the closer relationship and the longer summary win. Kept: the
## last MAX_AUTO automatic backups and every other one (up to MAX_FILES). The folder is outside the
## world, so world snapshots don't carry it and it never syncs.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")

const MAX_AUTO := 10
const MAX_FILES := 40
const AUTO_EVERY_S := 20 * 3600
const MEMORY_KEYS := ["memory_notes", "summary", "summary_upto", "relationship", "ai_model"]


static func dir() -> String:
	return SaveManager.global_path("chat_backups").path_join(SaveManager.slot_id)


## A backup of this world's chats now. Returns its path, "" when there's no world or it can't be written.
static func backup(kind: String = "manual") -> String:
	if SaveManager.slot_id == "":
		return ""
	DirAccess.make_dir_recursive_absolute(dir())
	var stamp := Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "_")
	var path := dir().path_join("chats_%s_%s.zip" % [stamp, kind])
	var n := 2
	while FileAccess.file_exists(path):
		path = dir().path_join("chats_%s_%s_%d.zip" % [stamp, kind, n])
		n += 1
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return ""
	var friends: Array = []
	for id in SaveManager.list_characters():
		var c := SaveManager.load_character(id)
		var messages := 0
		var log_file := ChatLog.log_path(id)
		if FileAccess.file_exists(log_file):
			var bytes := FileAccess.get_file_as_bytes(log_file)
			messages = bytes.count(10)
			zip.start_file("logs/%s.jsonl" % id)
			zip.write_file(bytes)
			zip.close_file()
		var mem := {"name": str(c.get("name", id))}
		for k in MEMORY_KEYS:
			if c.has(k):
				mem[k] = c[k]
		zip.start_file("memories/%s.json" % id)
		zip.write_file(JSON.stringify(mem, "\t").to_utf8_buffer())
		zip.close_file()
		friends.append({"id": id, "name": str(c.get("name", id)), "messages": messages})
	var manifest := {"app": "Polox", "format": 1, "kind": kind, "world": SaveManager.slot_id,
		"world_name": str(GameState.world.get("name", "")), "made": Time.get_datetime_string_from_system(false, true), "friends": friends}
	zip.start_file("manifest.json")
	zip.write_file(JSON.stringify(manifest, "\t").to_utf8_buffer())
	zip.close_file()
	zip.close()
	prune()
	return path


## Once a day while there are chats (a world loading calls this). The path, or "".
static func auto_backup_if_due() -> String:
	if SaveManager.slot_id == "" or not _has_chats():
		return ""
	var newest := 0
	for b in list_backups():
		if str(b.kind) == "auto":
			newest = maxi(newest, int(b.made_unix))
	if newest > 0 and Time.get_unix_time_from_system() - newest < AUTO_EVERY_S:
		return ""
	return backup("auto")


static func _has_chats() -> bool:
	for id in SaveManager.list_characters():
		if FileAccess.file_exists(ChatLog.log_path(id)):
			return true
	return false


## This world's chat backups, newest first: [{path, file, kind, made_unix, size}].
static func list_backups() -> Array:
	var out: Array = []
	if SaveManager.slot_id == "" or not DirAccess.dir_exists_absolute(dir()):
		return out
	for f in DirAccess.get_files_at(dir()):
		if not f.begins_with("chats_") or not f.ends_with(".zip"):
			continue
		var p := dir().path_join(f)
		var parts := f.trim_suffix(".zip").split("_")
		out.append({"path": p, "file": f, "kind": parts[3] if parts.size() > 3 else "manual",
			"made_unix": FileAccess.get_modified_time(p), "size": FileAccess.get_file_as_bytes(p).size()})
	out.sort_custom(func(a, b): return int(a.made_unix) > int(b.made_unix) or (int(a.made_unix) == int(b.made_unix) and str(a.file) > str(b.file)))
	return out


## Keeps the newest MAX_AUTO automatic backups and at most MAX_FILES in all.
static func prune() -> void:
	var autos := 0
	var kept := 0
	for b in list_backups():
		var drop := false
		if str(b.kind) == "auto":
			autos += 1
			drop = autos > MAX_AUTO
		if not drop:
			kept += 1
			drop = kept > MAX_FILES
		if drop:
			DirAccess.remove_absolute(str(b.path))


## What a backup holds (its manifest), {} if it isn't one.
static func manifest(path: String) -> Dictionary:
	var check := SlotArchive.inspect_zip(path)
	if not bool(check.ok) or not "manifest.json" in check.files:
		return {}
	var m: Variant = JSON.parse_string(SlotArchive.read_zip_file(path, "manifest.json").get_string_from_utf8())
	return m if m is Dictionary and str(m.get("app", "")) == "Polox" and m.get("friends") is Array else {}


## Brings a backup's chats and memories back into this world, merged with what's here. A backup of the
## present state is made first. Friends who aren't in this world are skipped (and named).
## {ok, error, friends, added, skipped: [names]}
static func restore(path: String) -> Dictionary:
	var m := manifest(path)
	if m.is_empty():
		return {"ok": false, "error": "That isn't a Polox chat backup (or it's damaged)."}
	if backup("before_restore") == "":
		return {"ok": false, "error": "Couldn't back up the chats as they are now, so nothing was restored."}
	var restored := 0
	var added := 0
	var skipped: Array = []
	var here := SaveManager.list_characters()
	for f in m.friends:
		if not f is Dictionary:
			continue
		var id := str(f.get("id", ""))
		if not id.is_valid_filename() or id.contains("/") or id.contains("\\") or id.begins_with("."):
			continue
		if not here.has(id):
			skipped.append(str(f.get("name", id)))
			continue
		added += _merge_log(id, SlotArchive.read_zip_file(path, "logs/%s.jsonl" % id))
		var mem: Variant = JSON.parse_string(SlotArchive.read_zip_file(path, "memories/%s.json" % id).get_string_from_utf8())
		if mem is Dictionary:
			_merge_memories(id, mem)
		restored += 1
	return {"ok": true, "error": "", "friends": restored, "added": added, "skipped": skipped}


## The log here plus the backup's lines that aren't here (by message id, else time + who + words),
## in time order. Returns how many came back.
static func _merge_log(id: String, bytes: PackedByteArray) -> int:
	if bytes.is_empty():
		return 0
	var mine := ChatLog.read_all(id)
	var seen := {}
	for e in mine:
		seen[_key(e)] = true
	var merged: Array = mine.duplicate()
	var added := 0
	for line in bytes.get_string_from_utf8().split("\n", false):
		var e: Variant = JSON.parse_string(line)
		if not e is Dictionary or not str(e.get("role", "")) in ["user", "ai", "note"]:
			continue
		if seen.has(_key(e)):
			continue
		seen[_key(e)] = true
		e["character"] = id
		merged.append(e)
		added += 1
	if added == 0:
		return 0
	# Time order to the millisecond (a line and its answer often share a second): each id carries the
	# moment it was written; then the order they were in.
	var keyed: Array = []
	for i in merged.size():
		keyed.append(["%s|%s|%08d" % [str(merged[i].get("ts", "")), _ms(merged[i]), i], merged[i]])
	keyed.sort_custom(func(a, b): return str(a[0]) < str(b[0]))
	var out := PackedStringArray()
	for pair in keyed:
		out.append(JSON.stringify(pair[1]))
	JsonUtil.write_bytes(ChatLog.log_path(id), ("\n".join(out) + "\n").to_utf8_buffer())
	return added


## The millisecond a message was written, from its id (a letter, the Unix time in ms, four random
## digits: chat_log.gd), zero-padded for sorting; "" when it has no such id.
static func _ms(e: Dictionary) -> String:
	var id := str(e.get("id", ""))
	if id.length() >= 15 and id.substr(1).is_valid_int():
		return id.substr(1, id.length() - 5).lpad(16, "0")
	return ""


static func _key(e: Dictionary) -> String:
	return str(e.id) if str(e.get("id", "")) != "" else "%s|%s|%s" % [str(e.get("ts", "")), str(e.get("role", "")), str(e.get("text", ""))]


static func _merge_memories(id: String, mem: Dictionary) -> void:
	var c := GameState.get_character(id)
	if c.is_empty():
		return
	var notes: Array = (c.get("memory_notes", []) as Array).duplicate() if c.get("memory_notes") is Array else []
	var lower := notes.map(func(n): return str(n).to_lower())
	for n in (mem.get("memory_notes", []) if mem.get("memory_notes") is Array else []):
		if str(n).strip_edges() != "" and not str(n).to_lower() in lower:
			notes.append(str(n))
			lower.append(str(n).to_lower())
	c["memory_notes"] = notes
	if str(mem.get("summary", "")).length() > str(c.get("summary", "")).length():
		c["summary"] = str(mem.summary)
		c["summary_upto"] = 0   # (re-folded from the merged log next time it's due)
	var rel: Dictionary = c.get("relationship", {}) if c.get("relationship") is Dictionary else {}
	var theirs: Dictionary = mem.get("relationship", {}) if mem.get("relationship") is Dictionary else {}
	for k in ["affinity", "trust"]:
		rel[k] = maxf(float(rel.get(k, 0.0)), float(theirs.get(k, 0.0)))
	c["relationship"] = rel
	if str(c.get("ai_model", "")) == "" and str(mem.get("ai_model", "")) != "":
		c["ai_model"] = str(mem.ai_model)
	GameState.save_character(c)
