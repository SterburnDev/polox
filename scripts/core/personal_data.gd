extends RefCounted
## [PERSONAL_DATA] [PLATFORM] Where Polox keeps everything personal: settings and AI keys, worlds (your
## friends, chats, your home and street), the Phone Link pairing, backups, logs and helper history. One
## folder, resolved here and nowhere else (save_manager.gd asks for it at start):
##
##   Windows, a portable Polox.exe     <the folder Polox.exe is in>/PersonalData
##                                    (from the executable's own path, so a shortcut or another working
##                                    directory finds the same folder)
##   Windows, installed by the setup  %LOCALAPPDATA%/Polox/PersonalData: outside the program folder, so
##                                    upgrades, repairs and an uninstall never touch your worlds. The
##                                    setup marks the copy as installed with a small file beside
##                                    Polox.exe (INSTALL_MARKER; tools/release/installer/polox.iss).
##   Windows/Linux/macOS, from source <the project folder>/PersonalData (run.bat, host.bat, the editor)
##   Android, the browser             the app's private storage: user://Polox (the installed package is
##                                    read-only there; Settings shows the path and Back up now exports it)
##   A desktop copy that can't write its folder (a read-only drive, Program Files without the marker)
##                                    Documents/Polox, and Settings says why (fallback_reason)
##
## Overrides, for developer tools only: --save-root=PATH (tests, screenshot drives, the Hub's checks).
## POLOX_SAVE_ROOT is no longer an override: it names an old folder to bring over once
## (personal_data_migration.gd [MIGRATION]). The folder is git-ignored and left out of every export.
## Tags: [PERSONAL_DATA] [PLATFORM]

const FOLDER := "PersonalData"
const MOBILE_FOLDER := "Polox"     # (Android and the browser: unchanged, so phone saves stay where they are)
const DOCUMENTS_FOLDER := "Polox"
## Written beside Polox.exe by the Windows setup. JSON: {"layout": "installed", "import_from": [folders]}.
## "import_from" lists PersonalData folders of portable copies to bring over (personal_data_migration.gd).
const INSTALL_MARKER := "polox-install.json"
const INSTALLED_LAYOUT := "installed"
const APP_DATA_FOLDER := "Polox"   # (inside %LOCALAPPDATA%)

## Why the usual folder wasn't used ("" when it was): shown in Settings > Gameplay > Your files.
static var fallback_reason := ""


## The PersonalData folder for this copy of Polox (the --save-root override is handled by the caller).
static func folder() -> String:
	fallback_reason = ""
	if OS.has_feature("android") or OS.has_feature("web"):
		return OS.get_user_data_dir().path_join(MOBILE_FOLDER)
	var wanted := installed_data_folder() if is_installed() else install_dir().path_join(FOLDER)
	if writable(wanted):
		if not OS.has_feature("template"):   # (from source it's inside the project: keep Godot from importing it)
			mark_ignored(wanted)
		return wanted
	fallback_reason = "Polox's own folder can't be written (%s), so your data is in Documents." % install_dir()
	return documents_folder()


## The folder this copy of Polox lives in: beside the exported executable, or the project folder.
static func install_dir() -> String:
	if OS.has_feature("template"):   # an exported game (not the editor binary running the project)
		return OS.get_executable_path().get_base_dir()
	return ProjectSettings.globalize_path("res://").trim_suffix("/")


## What the setup wrote beside Polox.exe, or {} for a portable copy and for a run from source.
## `beside` is for tests: the folder to look in instead of this copy's own.
static func install_marker(beside: String = "") -> Dictionary:
	var marker_path := (beside if beside != "" else install_dir()).path_join(INSTALL_MARKER)
	if not FileAccess.file_exists(marker_path):
		return {}
	# (JsonUtil.parse: a damaged marker is quietly "not installed", not an error in the log)
	var text := FileAccess.get_file_as_string(marker_path).trim_prefix(char(0xFEFF))   # (a byte-order mark, if an editor added one)
	var parsed: Variant = preload("res://scripts/core/json_util.gd").parse(text)
	return parsed if parsed is Dictionary else {}


## True for a copy the Windows setup installed (its data lives outside the program folder).
static func is_installed(beside: String = "") -> bool:
	if beside == "" and not OS.has_feature("template"):
		return false   # (run from source: the project folder is the "install", marker or not)
	return str(install_marker(beside).get("layout", "")) == INSTALLED_LAYOUT


## An installed copy's data folder: %LOCALAPPDATA%/Polox/PersonalData. Windows always sets
## LOCALAPPDATA for a signed-in user; the roaming data folder stands in if it's somehow missing.
static func installed_data_folder() -> String:
	var local_app_data := OS.get_environment("LOCALAPPDATA").replace("\\", "/").trim_suffix("/")
	var base := local_app_data if local_app_data != "" else OS.get_data_dir()
	return base.path_join(APP_DATA_FOLDER).path_join(FOLDER)


## PersonalData folders the setup was asked to bring over: a portable copy the player pointed at, and a
## PersonalData folder already inside the program folder (the setup ran over a portable copy). Only
## entries that are folders; the caller decides what's new (personal_data_migration.gd import_requested).
static func requested_imports(beside: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var listed: Variant = install_marker(beside).get("import_from", [])
	if not listed is Array:
		return out
	for entry in listed:
		var folder_path := str(entry).replace("\\", "/").trim_suffix("/")
		if folder_path != "" and not folder_path in out and DirAccess.dir_exists_absolute(folder_path):
			out.append(folder_path)
	return out


static func documents_folder() -> String:
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return (docs if docs != "" else OS.get_user_data_dir()).path_join(DOCUMENTS_FOLDER)


## A .gdignore so the editor and `--import` never import the pictures, songs and worlds in `dir` (they'd
## get .import files beside them and copies in .godot/imported).
static func mark_ignored(dir: String) -> void:
	var p := dir.path_join(".gdignore")
	if not FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.close()


## True when `dir` exists (or can be made) and a file can be written in it.
static func writable(dir: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		return false
	var probe := dir.path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## Where older versions and other copies of Polox kept the same things, the main one first:
##   1. what the Windows setup was asked to bring over (requested_imports), and a PersonalData folder
##      a portable copy left in the program folder the setup was run over
##   2. the POLOX_SAVE_ROOT folder (a developer setup set this; it no longer overrides anything)
##   3. <the project>/.polox-local/player (run.bat and host.bat used it when it existed, so a source
##      copy's real saves are here even when the variable isn't set for this process)
##   4. Documents/Polox (the old default)
##   5. Documents/PocketDarkWorld (the old name, in its old layout): only when none of the others exist,
##      because its contents were already copied into Documents/Polox by the old migration.
## Only folders that exist and aren't the current one.
static func legacy_folders(current: String) -> PackedStringArray:
	var out := PackedStringArray()
	if OS.has_feature("android") or OS.has_feature("web"):
		return out
	# What the player asked the setup for comes first: the first folder found supplies the settings.
	var candidates: Array = Array(requested_imports())
	if is_installed():
		# The setup may have run over a portable copy: its PersonalData is still in the program folder.
		candidates.append(install_dir().path_join(FOLDER))
	candidates.append_array([OS.get_environment("POLOX_SAVE_ROOT"), install_dir().path_join(".polox-local/player"), documents_folder()])
	_collect(candidates, current, out)
	if out.is_empty():
		_collect([preload("res://scripts/core/migration.gd").legacy_root(documents_folder())], current, out)
	return out


static func _collect(candidates: Array, current: String, out: PackedStringArray) -> void:
	for c in candidates:
		var p := str(c).replace("\\", "/").trim_suffix("/")
		if p == "" or p == current.replace("\\", "/").trim_suffix("/") or p in out:
			continue
		if FileAccess.file_exists(p.path_join("settings.json")) or DirAccess.dir_exists_absolute(p.path_join("slots")) or FileAccess.file_exists(p.path_join("world.json")):
			out.append(p)


## Opens the folder in the system's file manager (PCs). Android and the browser can't open their
## private storage; Settings shows the path and offers Back up now there instead.
static func open(path: String) -> bool:
	if OS.has_feature("android") or OS.has_feature("web"):
		return false
	DirAccess.make_dir_recursive_absolute(path)
	return OS.shell_open(path) == OK


# --- The folder explains itself --------------------------------------------------------------------

const GUIDE_FILE := "Where things are.txt"
## The names players use for the two layouts -> the folder each one really is. Nothing is renamed:
## Phone Link and cloud sync send these folder names to your other devices.
const LAYOUT_LINKS := {"Dream World layout": "slots", "Light World layout": "my_home"}
## Beside an installed Polox.exe (the setup's uninstaller removes it: tools/release/installer/polox.iss).
const INSTALL_DATA_LINK := "Personal data.url"


## [PERSONAL_DATA] A plain map of the folder ("Where things are.txt") and, on Windows, two shortcuts
## beside it named the way players speak of it: "Dream World layout" opens slots (the worlds you build)
## and "Light World layout" opens my_home (your real home, once it is mapped). Written only when it would
## differ (a newer Polox, or the folder was moved). PCs only: a phone's storage isn't browsed.
static func write_guide(root: String) -> void:
	if OS.has_feature("android") or OS.has_feature("web") or not DirAccess.dir_exists_absolute(root):
		return
	var windows := OS.get_name() == "Windows"
	_write_if_different(root.path_join(GUIDE_FILE), guide_text("\\" if windows else "/", windows))
	if not windows:
		return
	# Clean up legacy "Dark World layout.url" shortcut when updating from older saves.
	var legacy_link := root.path_join("Dark World layout.url")
	if FileAccess.file_exists(legacy_link):
		DirAccess.remove_absolute(legacy_link)
	for label in LAYOUT_LINKS:
		var target := root.path_join(str(LAYOUT_LINKS[label]))
		var link := root.path_join(str(label) + ".url")
		if DirAccess.dir_exists_absolute(target):
			_write_if_different(link, folder_shortcut(target))
		elif FileAccess.file_exists(link):
			DirAccess.remove_absolute(link)   # (Forget my home took the folder away)
	# An installed copy keeps this folder in your own AppData, not beside Polox.exe: a shortcut beside
	# the program leads here (nothing is written when the program folder can't be written to).
	if is_installed():
		_write_if_different(install_dir().path_join(INSTALL_DATA_LINK), folder_shortcut(root))


static func guide_text(sep: String, shortcuts: bool) -> String:
	var lines := PackedStringArray([
		"Polox: where your things are",
		"Polox writes this file when it starts. Changing it changes nothing.",
		"",
		"Dream World layout  (the places you build and the Bramins who live there)",
		"    slots/<a world>/rooms/          one file per place",
		"    slots/<a world>/                the rest of that world: friends, chats, items, journal, photos",
		"",
		"Light World layout  (your real home and street)",
		"    my_home/places/                 the rooms and streets Polox built",
		"    my_home/home.json               what Polox knows about your home: the plan, each fact and where it came from",
		"    my_home/Info/                   what an AI found out, as files Polox reads (see READ ME.txt in it)",
		"    (my_home appears once you have mapped your home)",
		"",
		"Also here",
		"    settings.json                   your settings and your AI keys",
		"    library/, audio/                things every world shares",
		"    snapshots/, trash/, exports/    safety copies, and what you exported",
		"    phone/                          Phone Link pairing (this computer only)",
		"    logs/                           what went wrong, if something did",
	])
	if shortcuts:
		lines.append("")
		lines.append("The two shortcuts beside this file open the two layout folders.")
	return "\n".join(lines).replace("/", sep) + "\n"


## A Windows Internet Shortcut (.url) that opens a folder: a plain text file, so nothing here needs
## another program to make it and nothing walks into it by mistake (it is not a link the system follows).
static func folder_shortcut(target: String) -> String:
	var url := "file:///"
	for ch in target.replace("\\", "/"):
		var code := ch.unicode_at(0)
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or ch in ["/", ":", ".", "_", "-", "~", "(", ")"]:
			url += ch
		else:
			for byte in ch.to_utf8_buffer():
				url += "%%%02X" % byte
	var shell := OS.get_environment("SystemRoot").path_join("System32").path_join("shell32.dll").replace("/", "\\")
	return "[InternetShortcut]\r\nURL=%s\r\nIconFile=%s\r\nIconIndex=3\r\n" % [url, shell]


static func _write_if_different(file: String, text: String) -> void:
	if FileAccess.file_exists(file) and FileAccess.get_file_as_string(file) == text:
		return
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f:
		f.store_string(text)
