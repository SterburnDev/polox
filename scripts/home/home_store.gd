extends RefCounted
## Your real home's files, in <save root>/my_home/ (private: never in a world's snapshots, exports,
## templates or phone sync, never in logs; Settings > Light World > Forget my home deletes it all):
##   home.json      what Polox knows: the layout, facts with their sources, the conflicts, the timeline,
##                  open questions (home_model.gd). With the places and osm.json, it goes to paired phones
##                  when you let it (Settings > Light World > On my phone): the Light World there too.
##   private.json   your address and your survey answers: this computer only (load_home merges them in)
##   journal.json   your journal (journal_panel.gd): this computer only
##   places/        the Light World's places built from it (lw_*.json, realms.gd)
##   files/         things you saved yourself for Polox to read (a permit list, a sketch, photos)
##   Info/          what an AI found out, as files Polox reads: prompt.txt (the open request's question),
##                  answer.json (an answer an AI or you saved there, waiting to be looked at), kept/ (each
##                  answer the home was built from, newest last), set aside/ (looked at, not kept).
##                  This computer only. (Homes from before 1.29 have research/ instead; it is still read.)
##   snapshots/     zips of my_home before each batch of changes (home timeline undo)
## Tags: [PERSONAL_DATA]

const JsonUtil := preload("res://scripts/core/json_util.gd")

const HOME_FILE := "home.json"
const PRIVATE_FILE := "private.json"
## Kept out of home.json, so they never go to a phone.
const PRIVATE_KEYS: PackedStringArray = ["address", "answers"]
const MAX_SNAPSHOTS := 20
const MAX_BATCH_BYTES := 64 * 1024 * 1024
const TRANSACTION := ".transaction"
const REQUEST_FILE := "helper_request.json"   # helper_request.gd: private, never synced
const RESEARCH_FILE := "accepted_research.json" # comparison baseline, committed and restored with the home
static var last_error := ""
static var last_snapshot := ""


static func dir() -> String:
	return SaveManager.home_dir()


static func path(rel: String) -> String:
	return dir().path_join(rel)


static func exists() -> bool:
	if not recover_transaction():
		return false
	return FileAccess.file_exists(path(HOME_FILE))


static func load_home() -> Dictionary:
	if not recover_transaction():
		return {}
	var d: Variant = JsonUtil.read_json(path(HOME_FILE), {})
	var home: Dictionary = d if d is Dictionary else {}
	var p: Variant = JsonUtil.read_json(path(PRIVATE_FILE), {}) if FileAccess.file_exists(path(PRIVATE_FILE)) else {}
	if p is Dictionary:
		for k in PRIVATE_KEYS:
			if (p as Dictionary).has(k):
				home[k] = p[k]
		var timeline: Array = home.get("timeline", [])
		for entry in p.get("survey_timeline", []):
			if not entry in timeline:
				timeline.append(entry)
		home["timeline"] = timeline
	return home


static func save_home(home: Dictionary) -> bool:
	return apply_batch(home_writes(home))


## Split the normal model into its private and shareable files without writing.
## A mapper can include these with places/osm in one apply_batch transaction.
static func home_writes(home: Dictionary) -> Dictionary:
	home["updated"] = Time.get_datetime_string_from_system(false, false)
	if home.get("answers") is Dictionary and not (home.answers as Dictionary).is_empty():
		# A phone can rebuild after a furniture edit without receiving the Survey's private answers.
		home["base_plan"] = load("res://scripts/home/layout_builder.gd").build(home.answers, load("res://scripts/home/home_model.gd").facts_by_key(home))
	var shared := home.duplicate()
	var private := {}
	var old: Variant = JsonUtil.read_json(path(PRIVATE_FILE), {}) if FileAccess.file_exists(path(PRIVATE_FILE)) else {}
	if old is Dictionary:
		private = (old as Dictionary).duplicate()
	for k in PRIVATE_KEYS:
		if shared.has(k):
			private[k] = shared[k]
			shared.erase(k)
	var personal: Array = []
	var timeline: Array = []
	for entry in shared.get("timeline", []):
		if str(entry.get("source", "")) == "you" and str(entry.get("kind", "")) in ["memory", "renovation", "used_to_be"]:
			personal.append(entry)
		else:
			timeline.append(entry)
	shared["timeline"] = timeline
	if home.has("answers") or not personal.is_empty():
		private["survey_timeline"] = personal
	var writes := {HOME_FILE: shared}
	if not private.is_empty():
		writes[PRIVATE_FILE] = private
	return writes


## An older home.json still holding the address and answers: moved into private.json (once).
static func split_private() -> bool:
	if not exists():
		return true
	var d: Variant = JsonUtil.read_json(path(HOME_FILE), {})
	if d is Dictionary and Array(PRIVATE_KEYS).any(func(k): return (d as Dictionary).has(k)):
		var updated := str(d.get("updated", ""))
		if not save_home(load_home()):
			return false
		var again: Dictionary = JsonUtil.read_json(path(HOME_FILE), {})
		again["updated"] = updated   # a move, not a change
		if not JsonUtil.write_json(path(HOME_FILE), again):
			return false
	return true


static func files_dir() -> String:
	var d := path("files")
	JsonUtil.ensure_dir(d)
	return d


## Files you saved for Polox (images and PDFs), newest first.
static func user_files() -> PackedStringArray:
	var out := PackedStringArray()
	var d := path("files")
	if not DirAccess.dir_exists_absolute(d):
		return out
	for f in DirAccess.get_files_at(d):
		if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "pdf", "txt"]:
			out.append(d.path_join(f))
	return out


## Keeps a research answer as what the home is built from. Its copy goes to Info/kept (apply_batch does
## that for every kept answer); returns that file's path ("" on failure).
static func save_research(raw: Dictionary) -> String:
	if not apply_batch({RESEARCH_FILE: raw}):
		return ""
	return last_kept_info


# --- Info: what an AI found out, as files Polox reads --------------------------------------------------

const INFO_DIR := "Info"
const INFO_PROMPT := "prompt.txt"
const INFO_ANSWER := "answer.json"
const INFO_GUIDE := "READ ME.txt"
const INFO_KEPT := "kept"
const INFO_SET_ASIDE := "set aside"
const MAX_INFO_FILES := 20
const MAX_INFO_BYTES := 512 * 1024
const INFO_GUIDE_TEXT := """Info: what an AI found out about your home, as files Polox reads

prompt.txt     The question for the AI. Polox writes it when you choose "Use any AI" (in the Survey, or
               My home > Look again). Give it to an AI that can search the web. It holds your address,
               so it is deleted as soon as the request is finished.
answer.json    The AI's answer. An AI that can save files puts it here itself; or save the AI's reply
               here yourself. Polox checks it, shows you what it says, and builds only what you keep.
kept           Each answer your home was built from, newest last.
set aside      Answers you looked at and did not keep.

Nothing in this folder goes to your phone, to a cloud folder or into an export.
Settings > Light World > Forget my home deletes it with the rest of your home.
"""
static var last_kept_info := ""


static func info_dir() -> String:
	return path(INFO_DIR)


## The Info folder, with its guide. False when it can't be made.
static func ensure_info() -> bool:
	var d := info_dir()
	JsonUtil.ensure_dir(d)
	if not DirAccess.dir_exists_absolute(d):
		return false
	var guide := d.path_join(INFO_GUIDE)
	if FileAccess.get_file_as_string(guide) != INFO_GUIDE_TEXT:
		_write_text(guide, INFO_GUIDE_TEXT)
	return true


static func _write_text(file: String, text: String) -> bool:
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	return f.get_error() == OK


## The open request's question as Info/prompt.txt ("" takes it away: it holds your address).
static func set_info_prompt(text: String) -> void:
	var file := info_dir().path_join(INFO_PROMPT)
	if text.strip_edges() == "":
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
		return
	if ensure_info() and FileAccess.get_file_as_string(file) != text:
		_write_text(file, text)


## An answer waiting in Info: answer.json, else the newest other .json, .txt or .md file an AI or you
## saved there (an AI doesn't always use the name it was given). "" when there is none.
static func waiting_answer() -> String:
	var d := info_dir()
	if not DirAccess.dir_exists_absolute(d):
		return ""
	if FileAccess.file_exists(d.path_join(INFO_ANSWER)):
		return d.path_join(INFO_ANSWER)
	var newest := ""
	var newest_time := -1
	for f in DirAccess.get_files_at(d):
		var low := str(f).to_lower()
		if low in [INFO_PROMPT, INFO_GUIDE.to_lower()] or not low.get_extension() in ["json", "txt", "md"]:
			continue
		var modified := int(FileAccess.get_modified_time(d.path_join(f)))
		if modified > newest_time:
			newest = d.path_join(f)
			newest_time = modified
	return newest


## An answer file's text ("" when it is unreadable, empty or over 512 KiB: nothing that big is an answer).
static func read_answer(file: String) -> String:
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null or f.get_length() <= 0 or f.get_length() > MAX_INFO_BYTES:
		return ""
	return f.get_as_text()


## Whether `file` is the waiting answer and when it was last saved (the panel notices a new one by this).
static func answer_stamp(file: String) -> String:
	return "" if file == "" else "%s|%d" % [file, int(FileAccess.get_modified_time(file))]


## A looked-at answer file leaves the inbox, as it arrived: into kept/ or set aside/, so it isn't offered twice.
static func file_answer_away(file: String, kept: bool) -> void:
	if file == "" or not FileAccess.file_exists(file):
		return
	var folder := info_dir().path_join(INFO_KEPT if kept else INFO_SET_ASIDE)
	JsonUtil.ensure_dir(folder)
	var target := folder.path_join("%s as it arrived.%s" % [_info_stamp(), file.get_extension().to_lower()])
	if DirAccess.rename_absolute(file, target) != OK:
		DirAccess.remove_absolute(file)
	_prune_info(folder)


## What the home is now built from, kept as a file in Info/kept (newest last).
static func keep_info(research: Dictionary) -> String:
	if research.is_empty() or not ensure_info():
		return ""
	var folder := info_dir().path_join(INFO_KEPT)
	JsonUtil.ensure_dir(folder)
	var file := folder.path_join("%s.json" % _info_stamp())
	if not JsonUtil.write_json(file, research):
		return ""
	_prune_info(folder)
	last_kept_info = file
	return file


static func _info_stamp() -> String:
	return "%s_%03d" % [Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_"), Time.get_ticks_msec() % 1000]


static func _prune_info(folder: String) -> void:
	var files := Array(DirAccess.get_files_at(folder))
	files.sort()
	while files.size() > MAX_INFO_FILES:
		DirAccess.remove_absolute(folder.path_join(str(files.pop_front())))


## The Info folder follows what was just committed. Never part of the transaction: a failure here
## loses nothing the home needs.
static func _info_after(writes: Dictionary) -> void:
	var closing: Variant = writes.get(REQUEST_FILE)
	if closing is Dictionary and str(closing.get("state", "pending")) != "pending":
		set_info_prompt("")
		if str(closing.get("via", "")) == "manual" and str(closing.get("task", "")) == "research":
			file_answer_away(waiting_answer(), str(closing.state) == "applied")
	var research: Variant = writes.get(RESEARCH_FILE)
	if research is Dictionary and not (research as Dictionary).is_empty():
		keep_info(research)


## The newest saved research answer, or {}.
static func last_research() -> Dictionary:
	if not recover_transaction():
		return {}
	if FileAccess.file_exists(path(RESEARCH_FILE)):
		var accepted: Variant = JsonUtil.read_json(path(RESEARCH_FILE), {})
		return accepted if accepted is Dictionary else {}
	var d := path("research")
	if not DirAccess.dir_exists_absolute(d):
		return {}
	var files := Array(DirAccess.get_files_at(d)).filter(func(f): return str(f).ends_with(".json"))
	files.sort()
	if files.is_empty():
		return {}
	var r: Variant = JsonUtil.read_json(d.path_join(str(files[-1])), {})
	return r if r is Dictionary else {}


## Zips home.json and places/ before a batch of changes. Returns the zip path ("" when nothing to save).
static func snapshot(kind: String = "change") -> String:
	if not exists():
		return ""
	var d := path("snapshots")
	JsonUtil.ensure_dir(d)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var zp := d.path_join("%s_%s_%d.zip" % [JsonUtil.slugify(kind), stamp, Time.get_ticks_usec()])
	var zw := ZIPPacker.new()
	if zw.open(zp) != OK:
		return ""
	var files: Array = [HOME_FILE]
	# Include even an empty baseline, so Undo never falls through to a newer legacy answer.
	if not FileAccess.file_exists(path(RESEARCH_FILE)):
		if not JsonUtil.write_json(path(RESEARCH_FILE), last_research()):
			zw.close()
			DirAccess.remove_absolute(zp)
			return ""
	files.append(RESEARCH_FILE)
	if FileAccess.file_exists(path(PRIVATE_FILE)):
		files.append(PRIVATE_FILE)
	if FileAccess.file_exists(path("osm.json")):
		files.append("osm.json")
	var pd := path("places")
	if DirAccess.dir_exists_absolute(pd):
		for f in DirAccess.get_files_at(pd):
			if str(f).ends_with(".json"):
				files.append("places/" + str(f))
	var ok := true
	for rel in files:
		var source := FileAccess.open(path(str(rel)), FileAccess.READ)
		if source == null:
			ok = false
			break
		var bytes := source.get_buffer(source.get_length())
		source.close()
		if zw.start_file(str(rel)) != OK or zw.write_file(bytes) != OK or zw.close_file() != OK:
			ok = false
			break
	if zw.close() != OK:
		ok = false
	if not ok:
		DirAccess.remove_absolute(zp)
		return ""
	_prune(d)
	last_snapshot = zp
	return zp


## The snapshots kept (newest first): [{"path", "kind", "when"}] for My home > Timeline > Earlier versions.
static func snapshots() -> Array:
	var d := path("snapshots")
	var out: Array = []
	if not DirAccess.dir_exists_absolute(d):
		return out
	var re := RegEx.create_from_string("^(.+)_(\\d{4}-\\d{2}-\\d{2})_(\\d{2})(\\d{2})(\\d{2})_\\d+\\.zip$")
	for f in DirAccess.get_files_at(d):
		var m := re.search(f)
		if m == null:
			continue
		out.append({"path": d.path_join(f), "kind": m.get_string(1), "when": "%s %s:%s" % [m.get_string(2), m.get_string(3), m.get_string(4)],
			"mtime": FileAccess.get_modified_time(d.path_join(f))})
	out.sort_custom(func(a, b): return int(a.mtime) > int(b.mtime) or (int(a.mtime) == int(b.mtime) and str(a.path) > str(b.path)))
	return out


static func _prune(d: String) -> void:
	var zips := Array(DirAccess.get_files_at(d)).filter(func(f): return str(f).ends_with(".zip"))
	zips.sort_custom(func(a, b): return FileAccess.get_modified_time(d.path_join(str(a))) < FileAccess.get_modified_time(d.path_join(str(b))))
	while zips.size() > MAX_SNAPSHOTS:
		DirAccess.remove_absolute(d.path_join(str(zips.pop_front())))


## Puts home.json and places/ back exactly as they were in a snapshot.
static func restore(zip_path: String) -> bool:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return false
	var writes := {}
	var total := 0
	for rel in zr.get_files():
		if rel == "places/":
			continue # ZIPPacker adds this directory record for nested files.
		if rel == REQUEST_FILE or not _allowed(rel) or writes.has(rel) or writes.size() >= 1024:
			zr.close()
			return false
		var bytes := zr.read_file(rel)
		total += bytes.size()
		var data: Variant = JsonUtil.parse(bytes.get_string_from_utf8())
		if total > MAX_BATCH_BYTES or not _valid_file(rel, data):
			zr.close()
			return false
		writes[rel] = data
	zr.close()
	if not writes.has(HOME_FILE):
		return false
	if not writes.has(RESEARCH_FILE):
		writes[RESEARCH_FILE] = {} # legacy snapshots must not retain a newer comparison baseline
	var removals := PackedStringArray()
	# Absence is part of the snapshot too. In legacy archives the private fields
	# remain inline in home.json; removing the newer overlay preserves those values.
	if not writes.has(PRIVATE_FILE):
		removals.append(PRIVATE_FILE)
	for f in (DirAccess.get_files_at(path("places")) if DirAccess.dir_exists_absolute(path("places")) else PackedStringArray()):
		var rel := "places/" + f
		if _allowed(rel) and not writes.has(rel):
			removals.append(rel)
	# Old snapshots predate OSM backup. Never pair old streets with a newer cache.
	if not writes.has("osm.json") and FileAccess.file_exists(path("osm.json")):
		removals.append("osm.json")
	return apply_batch(writes, removals)


static func _allowed(rel: String) -> bool:
	if rel.contains("..") or rel.contains("\\") or rel.contains(":") or rel.begins_with("/"):
		return false
	# The helper request rides in the same transaction, so "applied" is recorded with the change.
	if rel in [HOME_FILE, PRIVATE_FILE, "osm.json", REQUEST_FILE, RESEARCH_FILE]:
		return true
	var bits := rel.split("/")
	return bits.size() == 2 and bits[0] == "places" and bits[1].begins_with("lw_") and bits[1].ends_with(".json")


static func _valid_file(rel: String, data: Variant) -> bool:
	if not _allowed(rel) or not data is Dictionary:
		return false
	if rel.begins_with("places/"):
		return str(data.get("id", "")) == rel.get_file().get_basename()
	return true


## Never confuse an unreadable/short read with a successfully read empty file.
static func _read_bytes_checked(file: String) -> Dictionary:
	var source := FileAccess.open(file, FileAccess.READ)
	if source == null:
		return {"ok": false}
	var length := source.get_length()
	var bytes := source.get_buffer(length)
	var ok := source.get_error() == OK and bytes.size() == length and source.get_length() == length
	source.close()
	return {"ok": ok, "bytes": bytes}


## A missing primary may still have a recoverable atomic-write sibling. Read it
## without repairing live files: the transaction must preserve it before writing.
static func _original_bytes(rel: String) -> Dictionary:
	var full := path(rel)
	if FileAccess.file_exists(full):
		var read := _read_bytes_checked(full)
		read["exists"] = true
		return read
	var has_sibling := false
	for suffix in [".tmp", ".bak"]:
		if not FileAccess.file_exists(full + suffix):
			continue
		has_sibling = true
		var read := _read_bytes_checked(full + suffix)
		if not read.ok:
			return {"ok": false}
		if _valid_file(rel, JsonUtil.parse(read.bytes.get_string_from_utf8())):
			return {"ok": true, "exists": true, "bytes": read.bytes}
	return {"ok": not has_sibling, "exists": false}


## Stage a coherent home change and byte-for-byte originals before touching live files.
## A private journal makes an interrupted transaction roll back at next load.
## No awaits: another main-thread job cannot interleave with this commit.
static func apply_batch(writes: Dictionary, removals: PackedStringArray = []) -> bool:
	last_error = ""
	if not recover_transaction():
		return false
	if writes.is_empty() and removals.is_empty():
		return true
	var total := 0
	for rel in writes:
		if not rel is String or not _valid_file(rel, writes[rel]):
			last_error = "The proposed home files are invalid."
			return false
		total += JSON.stringify(writes[rel]).to_utf8_buffer().size()
	for rel in removals:
		if not _allowed(rel) or writes.has(rel):
			last_error = "The proposed home removal is invalid."
			return false
	if writes.size() + removals.size() > 1024 or total > MAX_BATCH_BYTES:
		last_error = "The proposed home is too large."
		return false
	var tx := path(TRANSACTION)
	JsonUtil.remove_tree(tx)
	JsonUtil.ensure_dir(tx)
	var original := {}
	var all: Array = writes.keys()
	for rel in removals:
		if not rel in all:
			all.append(rel)
	for rel in all:
		var read := _original_bytes(str(rel))
		if not read.ok:
			last_error = "Couldn't read the existing home or its recovery copies."
			return false
		original[rel] = read.exists
		if bool(original[rel]):
			if not JsonUtil.write_bytes(tx.path_join("old").path_join(str(rel)), read.bytes):
				last_error = "Couldn't preserve the existing home."
				return false
	for rel in writes:
		if not JsonUtil.write_json(tx.path_join("new").path_join(str(rel)), writes[rel]):
			last_error = "Couldn't stage the proposed home."
			return false
	var journal := {"version": 1, "state": "prepared", "original": original}
	if not JsonUtil.write_json(tx.path_join("journal.json"), journal):
		last_error = "Couldn't record the home transaction."
		return false
	var ok := true
	for rel in writes:
		var read := _read_bytes_checked(tx.path_join("new").path_join(str(rel)))
		if not read.ok or not JsonUtil.write_bytes(path(str(rel)), read.bytes):
			ok = false
			break
	if ok:
		for rel in removals:
			if not JsonUtil.remove_file(path(rel)):
				ok = false
				break
	if ok:
		journal.state = "committed"
		ok = JsonUtil.write_json(tx.path_join("journal.json"), journal)
	if not ok:
		last_error = "Couldn't apply the home; the previous version is being restored."
		recover_transaction()
		_forget(all)
		return false
	JsonUtil.remove_tree(tx)
	_forget(all)
	_info_after(writes)
	return true


## These files changed underneath SaveManager's write baselines (this process wrote them, not a sync):
## the next load adopts them, so a later room edit isn't mistaken for a sync conflict.
static func _forget(rels: Array) -> void:
	for rel in rels:
		SaveManager.forget_baselines(path(str(rel)))


static func recover_transaction() -> bool:
	var tx := path(TRANSACTION)
	if not DirAccess.dir_exists_absolute(tx):
		return true
	var journal_path := tx.path_join("journal.json")
	# Staging cannot touch live files until its journal exists.
	if not FileAccess.file_exists(journal_path) and not FileAccess.file_exists(journal_path + ".bak") and not FileAccess.file_exists(journal_path + ".tmp"):
		JsonUtil.remove_tree(tx)
		return true
	var journal: Variant = JsonUtil.read_json(journal_path, null)
	if not journal is Dictionary or not journal.get("original") is Dictionary or int(journal.get("version", 0)) != 1:
		last_error = "The home recovery record is unreadable; the saved copies were kept."
		return false
	if str(journal.get("state", "")) == "committed":
		JsonUtil.remove_tree(tx)
		return true
	# Preflight every original before *any* rollback write/removal. Keep the bytes
	# in memory so a later failed read cannot partially restore or erase live saves.
	var originals := {}
	for rel in journal.original:
		if not rel is String or not _allowed(rel):
			last_error = "The home recovery record contains an invalid path."
			return false
		if bool(journal.original[rel]):
			var read := _read_bytes_checked(tx.path_join("old").path_join(rel))
			if not read.ok:
				last_error = "A home recovery copy is missing or unreadable; the remaining copies were kept."
				return false
			originals[rel] = read.bytes
	for rel in journal.original:
		if bool(journal.original[rel]):
			var original_bytes: PackedByteArray = originals[rel]
			var live := _read_bytes_checked(path(rel))
			if not live.ok or live.bytes != original_bytes:
				if not JsonUtil.write_bytes(path(rel), original_bytes):
					last_error = "Couldn't restore the previous home. Free storage and try again."
					return false
				# The .bak now holds the rejected version: it must not be "rescued" later.
				DirAccess.remove_absolute(path(rel) + ".bak")
		elif not JsonUtil.remove_file(path(rel)):
			last_error = "Couldn't remove an interrupted home file."
			return false
		# An absent original must not be resurrected by generic JSON backup recovery.
		if not bool(journal.original[rel]):
			for suffix in [".tmp", ".bak"]:
				if FileAccess.file_exists(path(rel) + suffix):
					DirAccess.remove_absolute(path(rel) + suffix)
	JsonUtil.remove_tree(tx)
	_forget(journal.original.keys())
	return true


## Forget my home: everything in my_home goes (the survey answers, the layout, places, files, research,
## snapshots). The Dream World's way home stays: next time it asks about home again.
static func forget_all() -> void:
	JsonUtil.remove_tree(dir())
