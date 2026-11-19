extends Node
## Polox for Android, on the PC: the built APK (build\android\polox.apk + polox.json), building
## it from inside Polox (tools\export_android.ps1 in the background), and "Install on my phone"
## over USB (adb from tools\android-sdk). One job at a time; progress and results as signals.
## Phone Link serves the APK at /app/polox.apk (app_page.gd).

signal progress(text: String)
signal finished(job: String, ok: bool, message: String)

const APK := "res://build/android/polox.apk"
const ADB := "res://tools/android-sdk/platform-tools/adb.exe"
const SCRIPT := "res://tools/export_android.ps1"

var busy := false
var job := ""
var log_text := ""
var adb_override := ""          # tests: a stand-in adb
var devices: Array = []         # the last find_devices(): [{serial, state, model}]
var timeout_s := 600.0
var _pid := -1
var _pipe: FileAccess
var _err: FileAccess
var _t0 := 0
var _after: Callable = Callable()


static func apk_path() -> String:
	var dev := ProjectSettings.globalize_path(APK)
	if FileAccess.file_exists(dev) or not OS.has_feature("template"):
		return dev
	return OS.get_executable_path().get_base_dir().path_join("polox.apk")   # beside Polox.exe (tools\export_windows.bat)


## {present, version, version_code, size, sha256, built, current} for the built APK.
static func apk_info(apk: String = "", info_file: String = "") -> Dictionary:
	var a := apk if apk != "" else apk_path()
	var i := info_file if info_file != "" else a.get_base_dir().path_join("polox.json")
	var out := {"present": false, "version": "", "version_code": 0, "size": 0, "sha256": "", "built": "", "current": false}
	if not FileAccess.file_exists(a):
		return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(i).trim_prefix("﻿")) if FileAccess.file_exists(i) else null
	var size := FileAccess.get_size(a) if FileAccess.file_exists(a) else 0
	if not d is Dictionary or int(d.get("size", -1)) != size:
		return out   # no matching description: half-written, or built by hand
	out.present = true
	out.version = str(d.get("version", ""))
	out.version_code = int(d.get("version_code", 0))
	out.size = size
	out.sha256 = str(d.get("sha256", ""))
	out.built = str(d.get("built", ""))
	out.current = out.version == str(ProjectSettings.get_setting("application/config/version", ""))
	return out


## 1.8.0 -> 10800 (the Android version code; export_presets.cfg keeps the same number).
static func version_code(version: String) -> int:
	var p := version.split(".")
	if p.size() < 3:
		return 0
	return p[0].to_int() * 10000 + p[1].to_int() * 100 + p[2].to_int()


func adb_path() -> String:
	if adb_override != "":
		return adb_override
	var p := ProjectSettings.globalize_path(ADB)
	return p if FileAccess.file_exists(p) else ""


## "" when the app can be built here, else what to do first.
static func build_blocker() -> String:
	if OS.has_feature("web") or OS.has_feature("android"):
		return "The app is built on the PC."
	for need in [["res://tools/godot/Godot_v4.7.2-stable_win64_console.exe", "Polox's Godot isn't in tools\\godot (run tools\\get_godot.bat)."],
			["res://tools/jdk17/bin/keytool.exe", "Java isn't in tools\\jdk17 yet (tools\\get_android_tools.ps1)."],
			["res://tools/android-sdk/build-tools/36.1.0/apksigner.bat", "The Android SDK isn't in tools\\android-sdk yet (tools\\get_android_tools.ps1 -AcceptLicenses)."],
			["res://tools/engine/android/android_source.zip", "Polox's Android engine isn't built yet (tools\\pyenv\\Scripts\\python tools\\build_engine.py android)."]]:
		if not FileAccess.file_exists(ProjectSettings.globalize_path(str(need[0]))):
			return str(need[1])
	return ""


# --- Jobs ---------------------------------------------------------------------------------------

func _start(name: String, exe: String, args: PackedStringArray, after: Callable, limit_s: float) -> String:
	if busy:
		return "Busy with %s." % job
	var p: Dictionary = OS.execute_with_pipe(exe, args, false)
	if p.is_empty():
		return "Couldn't start %s." % exe.get_file()
	_pid = int(p.pid)
	_pipe = p.stdio
	_err = p.stderr
	_t0 = Time.get_ticks_msec()
	busy = true
	job = name
	log_text = ""
	timeout_s = limit_s
	_after = after
	return ""


func _process(_delta: float) -> void:
	if not busy:
		return
	log_text += _pipe.get_buffer(65536).get_string_from_utf8() + _err.get_buffer(65536).get_string_from_utf8()
	var secs := (Time.get_ticks_msec() - _t0) / 1000
	if OS.is_process_running(_pid):
		if job == "build":
			progress.emit("Building Polox for Android... %d:%02d" % [secs / 60, secs % 60])
		if secs > timeout_s:
			OS.kill(_pid)
			_finish(false, "Stopped after %d seconds." % int(timeout_s))
		return
	log_text += _pipe.get_buffer(1 << 20).get_string_from_utf8() + _err.get_buffer(1 << 20).get_string_from_utf8()
	var code := OS.get_process_exit_code(_pid)
	var after := _after
	busy = false
	_pid = -1
	after.call(code, log_text)


func _finish(ok: bool, msg: String) -> void:
	var j := job
	busy = false
	_pid = -1
	job = ""
	finished.emit(j, ok, msg)


## Builds build\android\polox.apk with Gradle (a few minutes; the first build also makes your signing key).
func start_build() -> String:
	var why := build_blocker()
	if why != "":
		return why
	var err := _start("build", "powershell.exe", PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path(SCRIPT), "-NoPause"]),
		func(code: int, text: String):
			var info := apk_info()
			if code == 0 and bool(info.present):
				_finish(true, "Polox for Android %s is ready (%.1f MB)." % [info.version, float(info.size) / 1048576.0])
			else:
				var last := text.strip_edges().split("\n")
				_finish(false, "The app build failed: %s" % (last[last.size() - 1].strip_edges() if not last.is_empty() else "code %d" % code)), 900.0)
	if err == "":
		progress.emit("Building Polox for Android... (a few minutes)")
	return err


## Phones plugged in over USB: [{serial, state, model}] ("device" = ready).
static func parse_devices(text: String) -> Array:
	var out: Array = []
	for line in text.split("\n"):
		var l := line.strip_edges()
		if l == "" or l.begins_with("List of devices") or l.begins_with("*") or l.begins_with("adb "):
			continue
		var parts := l.split(" ", false)
		if parts.size() < 2:
			continue
		var model := ""
		for p in parts:
			if p.begins_with("model:"):
				model = p.trim_prefix("model:").replace("_", " ")
		out.append({"serial": parts[0], "state": parts[1], "model": model})
	return out


## What a device state means for you, in plain words ("" when it's ready).
static func explain_state(state: String) -> String:
	match state:
		"device":
			return ""
		"unauthorized":
			return "Unlock the phone and tap Allow on \"Allow USB debugging?\" (tick \"Always allow from this computer\")."
		"offline":
			return "The phone is connected but not answering: unplug it, plug it back in, and unlock it."
		"no permissions", "no":
			return "Windows can't talk to the phone: try another USB cable or port (some cables only charge)."
	return "The phone says \"%s\": unplug it and plug it back in." % state


## adb install's answer in plain words: [ok, message].
static func explain_install(text: String) -> Array:
	if "Success" in text:
		return [true, "Installed: Polox is in your phone's app list."]
	var t := text
	if "INSTALL_FAILED_UPDATE_INCOMPATIBLE" in t or "signatures do not match" in t:
		return [false, "The phone has a Polox signed with a different key (another PC's build). Uninstall Polox on the phone first (its worlds come back from this PC when it syncs; anything it never synced is lost), then install again."]
	if "INSTALL_FAILED_VERSION_DOWNGRADE" in t:
		return [false, "The phone has a newer Polox than this PC's. Update Polox on the PC first, or uninstall it on the phone."]
	if "INSTALL_FAILED_INSUFFICIENT_STORAGE" in t:
		return [false, "The phone is out of space: Polox needs about 100 MB."]
	if "INSTALL_FAILED_USER_RESTRICTED" in t or "INSTALL_FAILED_ABORTED" in t:
		return [false, "The phone said no: look for a prompt on the phone (\"Install via USB\") and allow it, then try again. Some Samsung phones also need Auto Blocker switched off for USB installs (Settings > Security and privacy > Auto Blocker)."]
	if "no devices" in t or "device not found" in t:
		return [false, "No phone found: plug it in with USB debugging on (see the steps)."]
	if "unauthorized" in t:
		return [false, explain_state("unauthorized")]
	var lines := t.strip_edges().split("\n")
	return [false, "The install failed: %s" % (lines[lines.size() - 1].strip_edges() if not lines.is_empty() else "no answer from adb")]


## Looks for phones: finished("devices", ok, message), and `devices` holds the list.
func find_devices() -> String:
	var adb := adb_path()
	if adb == "":
		return "adb isn't in tools\\android-sdk yet (tools\\get_android_tools.ps1 -AcceptLicenses)."
	return _start("devices", adb, PackedStringArray(["devices", "-l"]), func(code: int, text: String):
		devices = parse_devices(text) if code == 0 else []
		var ready := devices.filter(func(d): return str(d.state) == "device")
		if code != 0:
			_finish(false, "adb didn't run (code %d)." % code)
		elif devices.is_empty():
			_finish(false, "No phone found over USB. Follow the steps: USB debugging on, then plug it in.")
		elif ready.is_empty():
			_finish(false, explain_state(str(devices[0].state)))
		else:
			_finish(true, "Found %s." % (str(ready[0].model) if str(ready[0].model) != "" else str(ready[0].serial))), 60.0)


## Installs (or updates) Polox on the phone over USB: finished("install", ok, message).
func install(serial: String = "") -> String:
	var adb := adb_path()
	if adb == "":
		return "adb isn't in tools\\android-sdk yet (tools\\get_android_tools.ps1 -AcceptLicenses)."
	if not bool(apk_info().present):
		return "Build the app first (Build the app)."
	var args := PackedStringArray()
	if serial != "":
		args.append_array(["-s", serial])
	args.append_array(["install", "-r", apk_path()])
	var err := _start("install", adb, args, func(_code: int, text: String):
		var r := explain_install(text)
		_finish(bool(r[0]), str(r[1])), 240.0)
	if err == "":
		progress.emit("Installing on your phone... (watch the phone for a prompt)")
	return err


## adb leaves a helper running in the background (on 127.0.0.1 only); stop it when we're done.
func stop_adb() -> void:
	var adb := adb_path()
	if adb != "" and adb_override == "":
		OS.create_process(adb, PackedStringArray(["kill-server"]))


# --- What the phone will ask (shown step by step on the PC) ---------------------------------------

static func steps_usb() -> PackedStringArray:
	return PackedStringArray([
		"On the phone: Settings > About phone > Software information, then tap Build number 7 times (\"Developer mode has been turned on\").",
		"Settings > Developer options > switch on USB debugging.",
		"Plug the phone into this PC with a USB cable and unlock it. Tap Allow on \"Allow USB debugging?\".",
		"Click Install on my phone here. If the phone asks \"Install via USB?\", tap Allow.",
		"Done: open Polox from the phone's app list. You can switch USB debugging off again afterwards.",
	])


static func steps_download(address: String) -> PackedStringArray:
	return PackedStringArray([
		"On the phone, open %s in Chrome and tap Get the Android app (or open %s/app)." % [address, address],
		"Tap Download polox.apk. Chrome may warn that the file can harm your device: tap Download anyway (it's your own build).",
		"Open the download. Android says it isn't allowed to install unknown apps from Chrome: tap Settings, switch on \"Allow from this source\", then go back.",
		"Tap Install. If Play Protect asks to scan the app or says it's unrecognised, choose More details > Install anyway.",
		"Done: open Polox. To update later, the app offers the new version itself; the same steps, without the Settings part.",
	])
