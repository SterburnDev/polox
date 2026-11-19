extends RefCounted
## Add-ons: folders that change some of Polox's pictures, music, sounds, tiles and words, and (only once
## you trust them) run scripts. Each one is a folder with an addon.json (docs/ADDONS.md):
##
##   {"id": "my-addon", "name": "My add-on", "version": "1.0.0", "description": "...", "priority": 0,
##    "enabled_by_default": false,
##    "overrides": {"music": {"menu": "music/menu.ogg"}, "songs": [{"file": "...", "title": "...", "from": "..."}],
##                  "textures": {"soul": "pictures/soul.png"}, "sfx": {"chime": "sounds/chime.ogg"},
##                  (a song can carry "seconds" and "gain_db", -24..6, to sit level with the others)
##                  "tiles": {"cozy_home/rug": "tiles/rug.png"}, "text": {"Dream World": "Somewhere"},
##                  "scripts": ["scripts/hello.gd"]}}
##
## Where they live: the save folder's addons/ (every build), bundled-addons/ (they come with the game: Polox
## Originals), local-addons/ in a source checkout, and assets/local/addons/ in a private export.
## The custom soundtrack and Soul in assets/local/ use the same
## kind of folder with an addon.json, always on, under every add-on and not listed. A copy of the game
## without it plays Polox's own tunes and draws the Dream Drop. In a music cue "@own" means Polox's own
## tune (the Light World's creation: its low hum), and the Soul "@dream_drop" means the Dream Drop. Finding an add-on reads only its addon.json. Turning one on checks
## its files (inside its folder, the right kind, not too big, there); anything missing or broken is listed in
## Add-ons and the game's own thing is used instead. Scripts never run until you trust that exact version
## (a SHA-256 of every script file): a changed script asks again. Your choices are kept in settings.json
## ("addons"). When two add-ons change the same thing, the higher priority wins (then the later name).
## Tags: [ADDONS]

const AddonText := preload("res://scripts/core/addon_text.gd")

const MANIFEST := "addon.json"
const LOCAL_DIR := "res://local-addons"
const BUNDLED_DIR := "res://bundled-addons"
const BUILTIN_DIR := "res://assets/local"
const PRIVATE_ADDONS_DIR := BUILTIN_DIR + "/addons"
## The game's own things an add-on can name instead of a file.
const OWN := {"music": "@own", "textures": "@dream_drop"}
const MAX_MANIFEST_BYTES := 64 * 1024
const MAX_FILE_BYTES := 64 * 1024 * 1024
const MAX_TEXT := 200
## Music cues: the title menu, making your home (the Light World's creation), the Light World, the
## Dream World, battles.
const MUSIC_CUES: PackedStringArray = ["menu", "survey", "light", "dark", "battle"]
const CUE_NAMES := {"menu": "Title menu", "survey": "Light World creation", "light": "Light World", "dark": "Dream World", "battle": "Battle"}
const EXTS := {
	"music": ["ogg", "mp3", "wav"], "songs": ["ogg", "mp3", "wav"], "sfx": ["ogg", "mp3", "wav"],
	"textures": ["png", "jpg", "jpeg", "webp"], "tiles": ["png", "jpg", "jpeg", "webp"], "scripts": ["gd"],
}
const KINDS: PackedStringArray = ["music", "songs", "textures", "sfx", "tiles", "text", "scripts"]
## Pictures the game asks add-ons for (anything else is listed as unused).
const TEXTURE_KEYS: PackedStringArray = ["soul", "logo"]

## For the test runner: the folders to look in instead of the usual ones.
static var override_folders: Variant = null
## For the test runner: the built-in folder to use (null: none in tests, BUILTIN_DIR otherwise).
static var builtin_override: Variant = null
static var _builtin := {}           # what's built in (an add-on entry, always on), or {}
static var revision := 0            # goes up whenever what's active changes (pictures, music and words follow)
static var _found: Array = []       # every add-on found: {id, name, version, description, dir, manifest, priority, default, errors}
static var _active: Array = []      # the ones on, checked, lowest priority first: {id, name, dir, files: {kind: {key: path}}, text, scripts}
static var _problems := {}          # id -> [message]
static var _translation: Translation
static var _keeper: Node            # takes the Translation out when the game closes (_keep)
static var _scripts := {}           # id -> [Node]
static var _tex_cache := {}
static var _host: Node              # where trusted scripts' nodes live (main)


# --- Where add-ons are --------------------------------------------------------------------------------

static func folders() -> PackedStringArray:
	if override_folders != null:
		return PackedStringArray(override_folders)
	var out := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--addons-root="):
			out.append(a.trim_prefix("--addons-root="))
	if _testing():
		return out   # the test suite never sees the add-ons on this PC
	out.append(BUNDLED_DIR)
	if OS.has_feature("template"):
		out.append(PRIVATE_ADDONS_DIR)
	else:
		out.append(ProjectSettings.globalize_path(LOCAL_DIR))
	out.append(SaveManager.global_path("addons"))
	return out


static func _testing() -> bool:
	for a in OS.get_cmdline_args():
		if a.ends_with("run_tests.gd"):
			return true
	return false


## The folder "Open add-ons folder" opens (made if it isn't there yet): the first one you can add to.
static func open_folder_path() -> String:
	var dir := SaveManager.global_path("addons")
	for d in folders():
		if not d.begins_with("res://"):
			dir = d
			break
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## The built-in folder (assets/local), or "".
static func builtin_dir() -> String:
	if builtin_override != null:
		return str(builtin_override)
	return "" if _testing() else BUILTIN_DIR


## What's built in: {name, description}, or {} (nothing: Polox's own).
static func builtin() -> Dictionary:
	return _builtin


# --- Finding (metadata only) -------------------------------------------------------------------------

## Looks for add-ons. Reads each addon.json and nothing else.
static func discover() -> Array:
	_found.clear()
	_builtin = {}
	var bdir := builtin_dir()
	if bdir != "" and FileAccess.file_exists(bdir.path_join(MANIFEST)):
		var errors: Array = []
		var m := _read_manifest(bdir.path_join(MANIFEST), errors)
		if not m.is_empty():
			_builtin = {"id": "built-in", "name": str(m.get("name", "Built in")).left(60), "version": str(m.get("version", "")),
				"description": str(m.get("description", "")).left(300), "author": "", "dir": bdir, "manifest": m,
				"priority": -1000, "default": true, "errors": errors, "builtin": true}
	var seen := {}
	for root in folders():
		if not DirAccess.dir_exists_absolute(root):
			continue
		var subs := Array(DirAccess.get_directories_at(root))
		subs.sort()
		for sub in subs:
			if str(sub).begins_with("."):
				continue
			var dir: String = root.path_join(sub)
			var mpath := dir.path_join(MANIFEST)
			if not FileAccess.file_exists(mpath):
				continue
			var entry := {"id": str(sub), "name": str(sub), "version": "", "description": "", "author": "", "dir": dir,
				"manifest": {}, "priority": 0, "default": false, "errors": []}
			var m := _read_manifest(mpath, entry.errors)
			if not m.is_empty():
				entry.manifest = m
				var want_id := str(m.get("id", sub)).strip_edges()
				entry.id = want_id if _good_id(want_id) else str(sub)
				if want_id != entry.id:
					entry.errors.append("Its id \"%s\" can't be used (letters, numbers, - and _ only): using \"%s\"." % [want_id.left(40), entry.id])
				entry.name = str(m.get("name", entry.id)).strip_edges().left(60)
				if entry.name == "":
					entry.name = entry.id
				entry.version = str(m.get("version", "")).strip_edges().left(20)
				entry.description = str(m.get("description", "")).strip_edges().left(300)
				entry.author = str(m.get("author", "")).strip_edges().left(60)
				entry.priority = int(m.get("priority", 0)) if (m.get("priority", 0) is int or m.get("priority", 0) is float) else 0
				entry.default = bool(m.get("enabled_by_default", false))
				if entry.version == "":
					entry.errors.append("addon.json has no version.")
			if seen.has(entry.id):
				entry.errors.append("Another add-on already uses the id \"%s\" (%s): this one is skipped." % [entry.id, str(seen[entry.id])])
				entry["duplicate"] = true
			else:
				seen[entry.id] = dir
			_found.append(entry)
	return _found


static func _read_manifest(path: String, errors: Array) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("Can't open addon.json.")
		return {}
	if f.get_length() > MAX_MANIFEST_BYTES:
		errors.append("addon.json is too big (over 64 KB).")
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		errors.append("addon.json isn't valid JSON (an object with a name, a version and overrides).")
		return {}
	return parsed


static func _good_id(id: String) -> bool:
	if id == "" or id.length() > 64:
		return false
	for c in id:
		if not (c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"):
			return false
	return true


static func found() -> Array:
	return _found


static func find(id: String) -> Dictionary:
	for e in _found:
		if e.id == id and not e.has("duplicate"):
			return e
	return {}


# --- On / off -----------------------------------------------------------------------------------------

static func _state() -> Dictionary:
	var s: Variant = GameState.settings.get("addons", {})
	return (s as Dictionary).duplicate(true) if s is Dictionary else {}


static func is_enabled(id: String) -> bool:
	var e := find(id)
	if e.is_empty():
		return false
	var on: Variant = _state().get("enabled", {})
	return bool((on as Dictionary).get(id, e.default)) if on is Dictionary else bool(e.default)


static func set_enabled(id: String, on: bool) -> void:
	var s := _state()
	var en: Dictionary = s.get("enabled", {}) if s.get("enabled") is Dictionary else {}
	en[id] = on
	s["enabled"] = en
	GameState.settings["addons"] = s
	GameState.save_settings()
	apply()


static func is_active(id: String) -> bool:
	for a in _active:
		if a.id == id:
			return true
	return false


static func problems(id: String) -> Array:
	var out: Array = []
	var e := find(id)
	if e.is_empty():
		for f in _found:
			if f.id == id:
				out.append_array(f.errors)
	else:
		out.append_array(e.errors)
	out.append_array(_problems.get(id, []))
	return out


## Finds add-ons and switches on the ones that are on (start of the game, and Add-ons > Look again).
static func refresh(host: Node = null) -> void:
	if host != null:
		_host = host
	discover()
	apply()


## Checks every add-on that's on and makes what they change live (words now; pictures, music and sounds
## the next time the game asks for them).
static func apply() -> void:
	_problems.clear()
	_tex_cache.clear()
	_active.clear()
	if not _builtin.is_empty():
		_active.append(_check(_builtin))
	for e in _found:
		if e.has("duplicate") or e.manifest.is_empty() or not is_enabled(e.id):
			continue
		_active.append(_check(e))
	_active.sort_custom(func(a, b): return a.priority < b.priority if a.priority != b.priority else str(a.name) < str(b.name))
	_install_text()
	_run_scripts()
	Synth_clear()
	Tilesets_clear()
	revision += 1


## Turns everything off for this run (tests).
static func reset() -> void:
	_stop_scripts()
	_found.clear()
	_builtin = {}
	_active.clear()
	_problems.clear()
	_tex_cache.clear()
	builtin_override = null
	if _translation:
		TranslationServer.remove_translation(_translation)
		_translation = null
	override_folders = null
	revision += 1


static func _problem(id: String, text: String) -> void:
	if not _problems.has(id):
		_problems[id] = []
	if not text in _problems[id]:
		_problems[id].append(text)


## One add-on's overrides, checked: what can't be used is listed (and the game keeps its own).
static func _check(e: Dictionary) -> Dictionary:
	var out := {"id": e.id, "name": e.name, "dir": e.dir, "priority": e.priority, "files": {}, "songs": [], "text": {}, "scripts": []}
	var ov: Variant = e.manifest.get("overrides", {})
	if not ov is Dictionary:
		_problem(e.id, "\"overrides\" should be an object: nothing from this add-on is used.")
		return out
	for kind in ov.keys():
		if not str(kind) in KINDS:
			_problem(e.id, "Unknown override \"%s\" (known: %s): skipped." % [str(kind).left(30), ", ".join(KINDS)])
	for kind in ["music", "textures", "sfx", "tiles"]:
		var table: Variant = ov.get(kind, {})
		if not table is Dictionary:
			_problem(e.id, "\"%s\" should be an object of name: file." % kind)
			continue
		var good := {}
		for key in table.keys():
			var k := str(key)
			if kind == "music" and not k in MUSIC_CUES:
				_problem(e.id, "Music cue \"%s\" isn't one of %s: skipped." % [k.left(30), ", ".join(MUSIC_CUES)])
				continue
			if kind == "textures" and not k in TEXTURE_KEYS:
				_problem(e.id, "Picture \"%s\" isn't used by the game (%s): skipped." % [k.left(30), ", ".join(TEXTURE_KEYS)])
				continue
			if kind == "tiles" and k.split("/").size() != 2:
				_problem(e.id, "Tile \"%s\" should be <tile set>/<tile>: skipped." % k.left(40))
				continue
			var want := str(table[key]).strip_edges()
			if want.begins_with("@"):
				if OWN.get(kind, "") == want and (kind != "textures" or k == "soul"):
					good[k] = want   # the game's own
				else:
					_problem(e.id, "%s \"%s\": \"%s\" isn't one of the game's own (music: @own, the soul: @dream_drop). Skipped." % [kind, k, want.left(30)])
				continue
			var path := _file(e, kind, want, "%s \"%s\"" % [kind, k])
			if path != "":
				good[k] = path
		out.files[kind] = good
	var songs: Variant = ov.get("songs", [])
	if songs is Array:
		for s in songs:
			if not s is Dictionary or str(s.get("file", "")) == "":
				_problem(e.id, "Each song needs a \"file\" (and a \"title\").")
				continue
			var path := _file(e, "songs", str(s.file), "song \"%s\"" % str(s.get("title", s.file)).left(40))
			if path != "":
				out.songs.append({"title": str(s.get("title", str(s.file).get_file().get_basename())).left(80), "from": str(s.get("from", e.name)).left(80),
					"seconds": int(s.get("seconds", 0)) if (s.get("seconds", 0) is int or s.get("seconds", 0) is float) else 0,
					"gain_db": clampf(float(s.get("gain_db", 0.0)), -24.0, 6.0) if (s.get("gain_db", 0) is int or s.get("gain_db", 0) is float) else 0.0, "path": path})
	else:
		_problem(e.id, "\"songs\" should be a list.")
	var text: Variant = ov.get("text", {})
	if text is Dictionary:
		for key in text.keys():
			var a := str(key)
			var b := str(text[key])
			if a.strip_edges() == "" or a.length() > MAX_TEXT or b.length() > MAX_TEXT:
				_problem(e.id, "Text \"%s\" is empty or too long: skipped." % a.left(30))
				continue
			out.text[a] = b
	else:
		_problem(e.id, "\"text\" should be an object of \"game words\": \"your words\".")
	var scripts: Variant = ov.get("scripts", [])
	if scripts is Array:
		for s in scripts:
			var path := _file(e, "scripts", str(s), "script")
			if path != "":
				out.scripts.append(path)
	else:
		_problem(e.id, "\"scripts\" should be a list of .gd files.")
	return out


## A file an add-on names, if it can be used: inside the add-on's folder, the right kind, there, not too big.
static func _file(e: Dictionary, kind: String, rel: String, what: String) -> String:
	rel = rel.strip_edges().replace("\\", "/")
	if rel == "" or rel.is_absolute_path() or rel.begins_with("/") or ".." in rel.split("/") or ":" in rel:
		_problem(e.id, "%s: \"%s\" must be a file inside the add-on's folder. Using the game's own." % [what.capitalize(), rel.left(60)])
		return ""
	if not rel.get_extension().to_lower() in EXTS[kind]:
		_problem(e.id, "%s: %s isn't a %s file. Using the game's own." % [what.capitalize(), rel.get_file().left(60), "/".join(EXTS[kind])])
		return ""
	var path: String = e.dir.path_join(rel)
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return path   # built into the game (imported: an exported game has no file to measure)
	if not FileAccess.file_exists(path):
		_problem(e.id, "%s: %s is missing. Using the game's own." % [what.capitalize(), rel.left(60)])
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() == 0 or f.get_length() > MAX_FILE_BYTES:
		_problem(e.id, "%s: %s is empty, unreadable or over 64 MB. Using the game's own." % [what.capitalize(), rel.left(60)])
		return ""
	return path


# --- What the game asks for ---------------------------------------------------------------------------

## The file the winning add-on gives for `kind`/`key` ({id, path}), or {}.
static func override(kind: String, key: String) -> Dictionary:
	for i in range(_active.size() - 1, -1, -1):
		var a: Dictionary = _active[i]
		var table: Dictionary = a.files.get(kind, {})
		if table.has(key):
			return {"id": a.id, "path": table[key]}
	return {}


## A music cue's song from an add-on (a full path), or "".
static func music_cue(cue: String) -> String:
	return str(override("music", cue).get("path", ""))


## Songs from the add-ons that are on (for Settings > Music and places), the higher priority first:
## [{title, from, path}], every cue's file included.
static func songs() -> Array:
	var out: Array = []
	var paths := {}
	for i in range(_active.size() - 1, -1, -1):
		var a: Dictionary = _active[i]
		for s in a.songs:
			if not paths.has(s.path):
				paths[s.path] = true
				out.append(s)
		var cues: Dictionary = a.files.get("music", {})
		for cue in MUSIC_CUES:
			if cues.has(cue) and not str(cues[cue]).begins_with("@") and not paths.has(cues[cue]):
				paths[cues[cue]] = true
				out.append({"title": str(cues[cue]).get_file().get_basename(), "from": a.name, "path": cues[cue]})
	return out


## A picture from an add-on, or null (the game draws its own). A broken file is listed and skipped.
static func texture(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var o := override("textures", key)
	var tex: Texture2D = null
	if not o.is_empty() and not str(o.path).begins_with("@"):
		var img := load_image(o.id, o.path)
		if img:
			tex = ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func load_image(id: String, path: String) -> Image:
	var img: Image = null
	if path.begins_with("res://"):
		var t := load(path) as Texture2D
		img = t.get_image() if t else null
	else:
		img = Image.load_from_file(path)
	if img == null or img.is_empty() or img.get_width() > 4096 or img.get_height() > 4096:
		_problem(id, "Picture %s can't be read (or is over 4096 px). Using the game's own." % path.get_file())
		return null
	return img


## A sound effect from an add-on, or null.
static func sfx(sound_name: String) -> AudioStream:
	var o := override("sfx", sound_name)
	if o.is_empty() or str(o.path).begins_with("@"):
		return null
	var s := load_audio(str(o.path))
	if s == null:
		_problem(o.id, "Sound %s can't be played. Using the game's own." % str(o.path).get_file())
	return s


static func load_audio(path: String) -> AudioStream:
	if path.begins_with("res://"):
		return load(path) as AudioStream
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return load("res://scripts/core/synth.gd").safe_wav(AudioStreamWAV.load_from_file(path))
	return null


## A tile's picture from an add-on ("<set>/<tile>"), or null.
static func tile(set_id: String, tile_id: String) -> Image:
	var o := override("tiles", set_id + "/" + tile_id)
	if o.is_empty() or str(o.path).begins_with("@"):
		return null
	return load_image(o.id, o.path)


## Words as the game shows them (add-ons' words in): for text drawn by hand, not by a Label.
static func text(s: String) -> String:
	return TranslationServer.translate(s) if _translation else s


static func Synth_clear() -> void:
	load("res://scripts/core/synth.gd").clear_cache()
	load("res://scripts/battle/battle_audio.gd")._custom_kinds.clear()


static func Tilesets_clear() -> void:
	load("res://scripts/world/tilesets.gd").clear_cache()


# --- Words --------------------------------------------------------------------------------------------

## The words the game shows go through one Translation: the names from before Dream World (old saves,
## old chats) become today's, then the add-ons' own words (the higher priority last) apply.
static func _install_text() -> void:
	if _translation:
		TranslationServer.remove_translation(_translation)
	var pairs: Array = AddonText.legacy_pairs()
	for a in _active:
		pairs.append_array(AddonText.pairs_from(a.text))
	var t := AddonText.new()
	t.locale = TranslationServer.get_locale()
	t.pairs = pairs
	_translation = t
	TranslationServer.add_translation(t)
	_keep()


## The words' Translation is a script: it must leave the TranslationServer before the game closes (left
## there, Godot crashes on exit, after the scripting has shut down). A node in the tree does that.
static func _keep() -> void:
	if _keeper != null and is_instance_valid(_keeper) and not _keeper.is_queued_for_deletion():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_keeper = Keeper.new()
	_keeper.name = "AddonsWords"
	tree.root.add_child.call_deferred(_keeper)


## Takes the words' Translation out (the game is closing, or the tests are done).
static func drop_text() -> void:
	if _translation:
		TranslationServer.remove_translation(_translation)
		_translation = null


class Keeper extends Node:
	func _exit_tree() -> void:
		load("res://scripts/core/addons.gd").drop_text()
		queue_free()


# --- Scripts ------------------------------------------------------------------------------------------

## A fingerprint of an add-on's scripts as they are now ("" = it has none).
static func scripts_hash(id: String) -> String:
	for a in _active:
		if a.id == id:
			return _hash_of(a.scripts)
	var e := find(id)
	if e.is_empty():
		return ""
	var paths: Array = []
	var ov: Variant = e.manifest.get("overrides", {})
	if ov is Dictionary and ov.get("scripts") is Array:
		for s in ov.scripts:
			var p: String = e.dir.path_join(str(s))
			if FileAccess.file_exists(p):
				paths.append(p)
	return _hash_of(paths)


static func _hash_of(paths: Array) -> String:
	if paths.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for p in paths:
		ctx.update(str(p).get_file().to_utf8_buffer())
		var f := FileAccess.open(str(p), FileAccess.READ)
		if f:
			ctx.update(f.get_buffer(f.get_length()))
	return ctx.finish().hex_encode()


static func script_files(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var e := find(id)
	var ov: Variant = e.get("manifest", {}).get("overrides", {}) if not e.is_empty() else {}
	if ov is Dictionary and ov.get("scripts") is Array:
		for s in ov.scripts:
			out.append(str(s))
	return out


static func is_trusted(id: String) -> bool:
	var h := scripts_hash(id)
	var t: Variant = _state().get("trusted_scripts", {})
	return h != "" and t is Dictionary and str((t as Dictionary).get(id, "")) == h


static func set_trusted(id: String, on: bool) -> void:
	var s := _state()
	var t: Dictionary = s.get("trusted_scripts", {}) if s.get("trusted_scripts") is Dictionary else {}
	if on:
		t[id] = scripts_hash(id)
	else:
		t.erase(id)
	s["trusted_scripts"] = t
	GameState.settings["addons"] = s
	GameState.save_settings()
	apply()


## Scripts that run now: only an add-on that's on, whose scripts you trusted as they are.
static func running_scripts(id: String) -> int:
	return (_scripts.get(id, []) as Array).size()


static func _stop_scripts() -> void:
	for id in _scripts:
		for n in _scripts[id]:
			if is_instance_valid(n):
				if n.has_method("_addon_stop"):
					n._addon_stop()
				n.queue_free()
	_scripts.clear()


static func _run_scripts() -> void:
	_stop_scripts()
	for a in _active:
		if a.scripts.is_empty():
			continue
		if not is_trusted(a.id):
			_problem(a.id, "Its scripts haven't run: trust them in Add-ons first (they can do anything the game can).")
			continue
		if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
			continue
		var nodes: Array = []
		for path in a.scripts:
			var gd := GDScript.new()
			gd.source_code = FileAccess.get_file_as_string(path)
			if gd.reload() != OK or not gd.can_instantiate():
				_problem(a.id, "Script %s has errors and didn't run." % str(path).get_file())
				continue
			var obj: Variant = gd.new()
			if not obj is Node:
				_problem(a.id, "Script %s must extend Node; it didn't run." % str(path).get_file())
				if obj is Object and not obj is RefCounted:
					(obj as Object).free()
				continue
			var n: Node = obj
			n.name = "Addon_%s_%s" % [a.id, str(path).get_file().get_basename()]
			_host.add_child(n)
			if n.has_method("_addon_start"):
				n._addon_start({"id": a.id, "folder": a.dir, "notify": func(t: String): GameState.notify(str(t).left(200))})
			nodes.append(n)
		_scripts[a.id] = nodes
