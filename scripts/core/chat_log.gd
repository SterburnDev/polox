extends Node
## Autoload that appends every chat message to logs/<character_id>.jsonl.
## One JSON object per line keeps logs greppable and crash-safe: a partial
## last line is simply skipped on read.
## Tags: [PERSONAL_DATA]

signal logged(entry: Dictionary)

const JsonUtil := preload("res://scripts/core/json_util.gd")
const KeyFormat := preload("res://scripts/ai/key_format.gd")

## Strings that must never reach disk (every API key in the settings is registered here).
var _secrets: PackedStringArray = []


func set_secret(secret: String) -> void:
	set_secrets(PackedStringArray([secret]))


## Every key in the settings (each provider has its own): none of them may reach a log.
func set_secrets(secrets: PackedStringArray) -> void:
	_secrets.clear()
	for s in secrets:
		if s.strip_edges().length() >= 6 and not s.strip_edges() in _secrets:
			_secrets.append(s.strip_edges())


## The text without any key: the ones in the settings by name, and anything else shaped like a
## provider's key (one pasted into a chat by mistake, or not saved yet).
func redact(text: String) -> String:
	for s in _secrets:
		text = text.replace(s, "[redacted]")
	return KeyFormat.scrub(text)


func log_path(character_id: String) -> String:
	return SaveManager.logs_dir().path_join(character_id + ".jsonl")


## Appends one message. `role` is "user", "ai" or "note" (a game note such as
## a gift's effect, never sent to the AI as speech); `extra` may add fields such
## as {"kind": "npc_chat", "with": "other_id"} or {"failed": true}.
func append(character_id: String, room: String, role: String, text: String, emotion: String = "", extra: Dictionary = {}) -> Dictionary:
	var entry := {
		# A unique id, so the phone's and the PC's copies of a log can be merged.
		"id": "%s%d%04d" % ["w" if OS.has_feature("web") else ("a" if OS.has_feature("android") else "p"), int(Time.get_unix_time_from_system() * 1000.0), randi() % 10000],
		"ts": Time.get_datetime_string_from_system(false, false),
		"room": room,
		"character": character_id,
		"role": role,
		"text": redact(text),
		"emotion": emotion,
	}
	for k in extra:
		entry[k] = extra[k]
	var file := log_path(character_id)
	JsonUtil.ensure_dir(file.get_base_dir())
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(file) else FileAccess.WRITE
	var f := FileAccess.open(file, mode)
	if f == null:
		push_warning("Chat log not writable: %s" % file)
		return entry
	# If a previous write was cut off mid-line, start on a fresh line so the
	# broken fragment can't swallow this message.
	f.seek_end()
	var length := f.get_position()
	if length > 0:
		f.seek(length - 1)
		if f.get_8() != 10:
			f.seek_end()
			f.store_string("
")
	f.seek_end()
	f.store_line(JSON.stringify(entry))
	f.close()
	logged.emit(entry)
	return entry


## All entries for one character, oldest first.
func read_all(character_id: String) -> Array:
	var out: Array = []
	var file := log_path(character_id)
	if not FileAccess.file_exists(file):
		return out
	var f := FileAccess.open(file, FileAccess.READ)
	while f != null and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var data: Variant = JsonUtil.parse(line)
		if data is Dictionary:
			out.append(data)
	return out


## The last `n` player<->character messages (skips NPC-to-NPC chatter),
## used as conversation history in prompts. Reads only the tail of the file,
## so a years-long log costs the same as a fresh one.
func recent(character_id: String, n: int) -> Array:
	if n >= 100000:
		return _conversation_only(read_all(character_id))
	var file := log_path(character_id)
	if not FileAccess.file_exists(file):
		return []
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return []
	var length := f.get_length()
	var chunk := 16384
	for _pass in 16:
		var start := maxi(0, length - chunk)
		f.seek(start)
		var text := f.get_buffer(length - start).get_string_from_utf8()
		if start > 0:
			text = text.substr(text.find("\n") + 1)  # drop the partial first line
		var entries: Array = []
		for line in text.split("\n"):
			var data: Variant = JsonUtil.parse(line.strip_edges())
			if data is Dictionary:
				entries.append(data)
		var convo := _conversation_only(entries)
		if convo.size() >= n or start == 0:
			f.close()
			return convo.slice(max(0, convo.size() - n))
		chunk *= 4
	f.close()
	return []


func _conversation_only(entries: Array) -> Array:
	var convo: Array = []
	for e in entries:
		if str(e.get("kind", "")) != "npc_chat":
			convo.append(e)
	return convo


func count_conversation(character_id: String) -> int:
	var n := 0
	for e in read_all(character_id):
		if str(e.get("kind", "")) != "npc_chat":
			n += 1
	return n


## Every character id that has a log file.
func logged_characters() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in JsonUtil.list_files(SaveManager.logs_dir(), ["jsonl"]):
		ids.append(f.get_basename())
	return ids


## Filtered view for the Log Viewer. Empty filter values mean "any".
## filters: {character, room, date_from "YYYY-MM-DD", date_to, search}
func query(filters: Dictionary) -> Array:
	var ids: PackedStringArray = logged_characters()
	var want_char := str(filters.get("character", ""))
	if want_char != "":
		ids = PackedStringArray([want_char])
	var room := str(filters.get("room", ""))
	var from := str(filters.get("date_from", ""))
	var to := str(filters.get("date_to", ""))
	var search := str(filters.get("search", "")).to_lower()
	var out: Array = []
	for id in ids:
		for e in read_all(id):
			var day := str(e.get("ts", "")).substr(0, 10)
			if room != "" and str(e.get("room", "")) != room:
				continue
			if from != "" and day < from:
				continue
			if to != "" and day > to:
				continue
			if search != "" and str(e.get("text", "")).to_lower().find(search) == -1:
				continue
			out.append(e)
	# Timestamps are whole seconds, so several messages can share one; the
	# sort must be stable or a quick exchange would come out shuffled.
	var keyed: Array = []
	for i in out.size():
		keyed.append([str(out[i].get("ts", "")), i])
	keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var sorted: Array = []
	for k in keyed:
		sorted.append(out[k[1]])
	return sorted


## Writes the filtered entries to exports/ as both .txt and .jsonl.
## Returns the two file paths.
func export(filters: Dictionary, names: Dictionary = {}) -> PackedStringArray:
	var entries := query(filters)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var dir := SaveManager.abs_path("exports")
	JsonUtil.ensure_dir(dir)
	var txt_path := dir.path_join("chat_logs_%s.txt" % stamp)
	var jsonl_path := dir.path_join("chat_logs_%s.jsonl" % stamp)
	var txt := FileAccess.open(txt_path, FileAccess.WRITE)
	var jl := FileAccess.open(jsonl_path, FileAccess.WRITE)
	if txt == null or jl == null:
		return PackedStringArray()
	txt.store_line("Polox chat log export (%d messages)" % entries.size())
	for e in entries:
		# (Logs are written without keys; a line from before a key was known is cleaned on its way out.)
		txt.store_line(redact(format_line(e, names)))
		jl.store_line(redact(JSON.stringify(e)))
	txt.close()
	jl.close()
	return PackedStringArray([txt_path, jsonl_path])


## One human-readable line, e.g. "[2026-10-05 18:30] (home) You: hi".
func format_line(e: Dictionary, names: Dictionary = {}) -> String:
	var who := "You" if e.get("role", "") == "user" else ("Note" if e.get("role", "") == "note" else str(names.get(e.get("character", ""), e.get("character", "?"))))
	var mood := " (%s)" % e.get("emotion") if str(e.get("emotion", "")) != "" and e.get("role", "") != "user" else ""
	var fail := " [not delivered]" if e.get("failed", false) else ""
	return "[%s] (%s) %s%s: %s%s" % [str(e.get("ts", "")).replace("T", " ").substr(0, 16), e.get("room", ""), who, mood, e.get("text", ""), fail]
