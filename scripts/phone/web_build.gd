extends RefCounted
## The phone version of Polox (the Web export in build/web): is it there, is
## it complete, does it match this PC's Polox, and the post-export step that
## makes it work over plain HTTP too.
##
## Why the post-export step: Godot's web page refuses to start outside a
## "secure context" (HTTPS or localhost), and its audio start-up assumes
## AudioWorklet, which browsers only offer on secure pages. Over Tailscale
## Serve (HTTPS) neither matters; over http://192.168.x.x or http://100.x.y.z
## both stopped the game before the title screen (found in the Phase 13
## diagnosis). This build is single-threaded, which doesn't need a secure
## context, so the page skips that one check, and the audio falls back to
## the older ScriptProcessor output. Both patches are checked, idempotent,
## and recorded in build_info.json with the build id and file hashes.
## It also writes `<file>.gz` copies the server sends to browsers that take gzip.

const REQUIRED: PackedStringArray = ["index.html", "index.js", "index.wasm", "index.pck", "index.audio.worklet.js", "index.audio.position.worklet.js"]
const GZIP: PackedStringArray = ["index.wasm", "index.pck", "index.js"]
const BootDiag := preload("res://scripts/net/boot_diag.gd")
const SOURCE_DIRS: PackedStringArray = ["res://scripts", "res://scenes", "res://assets"]
const SOURCE_FILES: PackedStringArray = ["res://project.godot", "res://export_presets.cfg"]
const TEMPLATE := "res://tools/engine/web/web_nothreads_release.zip"   # Polox's web engine (tools/build_engine.py)
const GODOT_CONSOLE := "res://tools/godot/Godot_v4.7.2-stable_win64_console.exe"
## Polox.exe's build id, written from the source by tools\export_windows.bat (--write-build-id) and packed
## into the exe: inside an export the scripts are compiled, so hashing them there would give another id.
const BAKED_ID := "res://build_id.txt"

## [what to find, what it becomes(, optional)] (applied once; already-patched files are left alone). An
## optional patch is a nicety: an engine without its hook still gets the others.
const HTML_PATCHES := [
	["const missing = Engine.getMissingFeatures({\n\t\tthreads: GODOT_THREADS_ENABLED,\n\t});",
	 "const missing = Engine.getMissingFeatures({\n\t\tthreads: GODOT_THREADS_ENABLED,\n\t}).filter((m) => GODOT_THREADS_ENABLED || !m.startsWith('Secure Context')); // Polox: single-threaded, plain HTTP is fine"],
]
const JS_PATCHES := [
	["GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path)",
	 "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet?ctx.audioWorklet.addModule(path):Promise.resolve()"],
	["this._source.connect(this.getPositionWorklet());if(start)",
	 "if(GodotAudio.ctx.audioWorklet){this._source.connect(this.getPositionWorklet())}if(start)"],
	# Copying (the AI helper's Copy prompt) over plain HTTP: there's no navigator.clipboard there, so the
	# browser's own copy command on a hidden text box does it (allowed right after a tap).
	['if(!navigator.clipboard||!navigator.clipboard.writeText){return 1}navigator.clipboard.writeText(text).catch(function(e){GodotRuntime.error("Setting OS clipboard is only possible from an input callback for the Web platform. Exception:",e)});return 0}',
	 'const legacy=function(){const ta=document.createElement("textarea");ta.value=text;ta.setAttribute("readonly","");ta.style.position="fixed";ta.style.top="-1000px";ta.style.opacity="0";document.body.appendChild(ta);ta.select();let ok=false;try{ok=document.execCommand("copy")}catch(e){}document.body.removeChild(ta);return ok?0:1};if(!navigator.clipboard||!navigator.clipboard.writeText){return legacy()}navigator.clipboard.writeText(text).catch(function(e){legacy()});return 0}',
	 true],
]

static var _id_cache := ""


static func default_dir() -> String:
	if OS.has_feature("android") or OS.has_feature("web"):
		return "user://web"   # (a phone or a browser never serves the phone version; looking for the PC's folders logged warnings on Android)
	var dev := ProjectSettings.globalize_path("res://build/web")
	if DirAccess.dir_exists_absolute(dev) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://tools")):
		return dev
	return OS.get_executable_path().get_base_dir().path_join("web")


## A fingerprint of this Polox's game code and settings (scripts, scenes,
## assets, project + export settings). Same source = same id, on any PC.
static func current_build_id() -> String:
	if _id_cache != "":
		return _id_cache
	if OS.has_feature("template"):
		var baked := baked_id(BAKED_ID)
		if baked != "":
			_id_cache = baked
			return _id_cache
	var files := PackedStringArray()
	for d in SOURCE_DIRS:
		_collect(d, files)
	for f in SOURCE_FILES:
		if FileAccess.file_exists(f):
			files.append(f)
	files.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for f in files:
		ctx.update(f.to_utf8_buffer())
		ctx.update(FileAccess.get_file_as_bytes(f))
	_id_cache = ctx.finish().hex_encode().substr(0, 16)
	return _id_cache


## The build id written at export time ("" if there is none).
static func baked_id(path: String) -> String:
	return FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""


## Writes this source's build id for an export to carry (tools\export_windows.bat). Returns it.
static func write_baked_id(path: String) -> String:
	var id := current_build_id()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(id)
	f.close()
	return id


static func _collect(dir: String, out: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_collect(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".import") and not f.ends_with(".uid") and not f.begins_with("."):
			out.append(dir.path_join(f))


static func templates_present() -> bool:
	return FileAccess.file_exists(TEMPLATE)


## The Web preset exists, is single-threaded and points at our templates.
static func preset_problems() -> PackedStringArray:
	var out := PackedStringArray()
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		out.append("export_presets.cfg is missing")
		return out
	var web := ""
	for s in cfg.get_sections():
		if s.begins_with("preset.") and not s.ends_with(".options") and str(cfg.get_value(s, "platform", "")) == "Web":
			web = s
	if web == "":
		out.append("there is no Web export preset")
		return out
	if bool(cfg.get_value(web + ".options", "variant/thread_support", false)):
		out.append("Thread Support is ON (it needs cross-origin isolation, impossible over plain HTTP)")
	if str(cfg.get_value(web + ".options", "custom_template/release", "")) == "":
		out.append("the Web preset has no custom template path")
	return out


## {present, complete, missing[], files{name: size}, mb, build_id, current, patched, gzip, error}
static func inspect(dir: String = "") -> Dictionary:
	var d := dir if dir != "" else default_dir()
	var out := {"dir": d, "present": FileAccess.file_exists(d.path_join("index.html")), "complete": false, "missing": [],
		"files": {}, "mb": 0.0, "build_id": "", "current": false, "patched": false, "gzip": false, "built": ""}
	var total := 0
	for f in REQUIRED:
		var p := d.path_join(f)
		if FileAccess.file_exists(p):
			out.files[f] = FileAccess.get_size(p)
			total += int(out.files[f])
		else:
			out.missing.append(f)
	out.complete = out.missing.is_empty()
	out.mb = total / 1048576.0
	var bi: Variant = JSON.parse_string(FileAccess.get_file_as_string(d.path_join("build_info.json"))) if FileAccess.file_exists(d.path_join("build_info.json")) else null
	if bi is Dictionary:
		out.build_id = str(bi.get("build_id", ""))
		out.built = str(bi.get("built", ""))
		out.patched = bool(bi.get("patched", false))
	out.current = out.build_id != "" and out.build_id == current_build_id()
	out.gzip = FileAccess.file_exists(d.path_join("index.wasm.gz"))
	return out


## After every Web export: patch for plain HTTP, gzip copies, build_info.json.
## Returns {ok, error, patched_html, patched_js, gz}.
static func postprocess(dir: String = "") -> Dictionary:
	var d := dir if dir != "" else default_dir()
	var res := {"ok": false, "error": "", "patched_html": 0, "patched_js": 0, "gz": []}
	for f in REQUIRED:
		if not FileAccess.file_exists(d.path_join(f)):
			res.error = "%s is missing from %s (did the export finish?)" % [f, d]
			return res
	var h := _patch_file(d.path_join("index.html"), HTML_PATCHES)
	if h < 0:
		res.error = "index.html isn't the Godot page Polox knows (its start-up check changed), so plain-HTTP play can't be enabled. Tailscale Serve (HTTPS) still works."
		return res
	var j := _patch_file(d.path_join("index.js"), JS_PATCHES)
	if j < 0:
		res.error = "index.js isn't the engine version Polox knows (its audio start-up changed), so plain-HTTP play can't be enabled. Tailscale Serve (HTTPS) still works."
		return res
	res.patched_html = h
	res.patched_js = j
	# Start-up diagnostics (rung R6): one current copy at the top of the page.
	var page := FileAccess.get_file_as_string(d.path_join("index.html"))
	var with_diag := BootDiag.inject(page)
	if with_diag == "":
		res.error = "index.html has no <head>, so the start-up diagnostics can't be added."
		return res
	if with_diag != page:
		var hf := FileAccess.open(d.path_join("index.html"), FileAccess.WRITE)
		hf.store_string(with_diag)
		hf.close()
		res.patched_html += 1
	for f in GZIP:
		var src := d.path_join(f)
		var gz := src + ".gz"
		var bytes := FileAccess.get_file_as_bytes(src)
		var packed := bytes.compress(FileAccess.COMPRESSION_GZIP)
		if packed.size() < 2 or packed[0] != 0x1f or packed[1] != 0x8b or packed.size() >= bytes.size():
			if FileAccess.file_exists(gz):
				DirAccess.remove_absolute(gz)
			continue
		var fa := FileAccess.open(gz, FileAccess.WRITE)
		fa.store_buffer(packed)
		fa.close()
		res.gz.append(f)
	var files := {}
	for f in REQUIRED:
		var p := d.path_join(f)
		files[f] = {"size": FileAccess.get_size(p), "sha256": FileAccess.get_sha256(p)}
	var info := {
		"app": "Polox", "build_id": current_build_id(), "version": str(ProjectSettings.get_setting("application/config/version", "")),
		"built": Time.get_datetime_string_from_system(), "patched": true, "files": files,
	}
	var out := FileAccess.open(d.path_join("build_info.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify(info, "\t"))
	out.close()
	res.ok = true
	return res


## Applies [find, replace] pairs once. Returns how many it changed (0 = all
## already applied), or -1 if one can't be found either way.
static func _patch_file(path: String, patches: Array) -> int:
	var text := FileAccess.get_file_as_string(path)
	var changed := 0
	for p in patches:
		if text.contains(str(p[1])):
			continue
		if text.count(str(p[0])) != 1:
			if _optional(p):
				continue
			return -1
		text = text.replace(str(p[0]), str(p[1]))
		changed += 1
	if changed > 0:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	return changed


## True if a built page and engine script carry both plain-HTTP patches.
static func patched_on_disk(dir: String = "") -> bool:
	var d := dir if dir != "" else default_dir()
	var html := FileAccess.get_file_as_string(d.path_join("index.html"))
	var js := FileAccess.get_file_as_string(d.path_join("index.js"))
	if not html.contains(BootDiag.block()):
		return false   # no (or an older) start-up diagnostics block: build it again
	for p in HTML_PATCHES:
		if not html.contains(str(p[1])):
			return false
	for p in JS_PATCHES:
		if not _optional(p) and not js.contains(str(p[1])):
			return false
	return true


static func _optional(patch: Array) -> bool:
	return patch.size() > 2 and bool(patch[2])


## The command that rebuilds the phone version (export + this post-process).
static func export_args() -> PackedStringArray:
	return PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--export-release", "Web", ProjectSettings.globalize_path("res://build/web/index.html")])


static func godot_console() -> String:
	var p := ProjectSettings.globalize_path(GODOT_CONSOLE)
	return p if FileAccess.file_exists(p) else ""
