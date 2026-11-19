extends RefCounted
## Test add-ons, written into the test save folder: a theme with nine short songs (the music cues and a
## few more), and a helper to write any add-on. Tests point Addons at them (Addons.override_folders), so
## the suite never depends on the add-ons on this PC.

const Addons := preload("res://scripts/core/addons.gd")
const Synth := preload("res://scripts/core/synth.gd")

## [file id, title, from, seconds listed]
const THEME_SONGS := [
	["title_song", "Title Song", "", 63],
	["making_home", "Making Home", "Test Album 1", 48],
	["egg_song", "Egg Song", "Test Album 5", 62],
	["light_song", "Light Song", "Test Album 5", 120],
	["snow_song", "Snow Song", "", 77],
	["strong_song", "Strong Song", "", 71],
	["dream_song", "Dream Song", "", 80],
	["falls_song", "Falls Song", "Test Album", 124],
	["battle_song", "Battle Song", "Test Album", 57],
]
const THEME_CUES := {"menu": "title_song", "light": "light_song", "dark": "dream_song", "battle": "battle_song", "survey": "making_home"}


static func root() -> String:
	return SaveManager.global_path("_test_addons")


## Writes an add-on folder `id` with `manifest` (as addon.json) and `files` {relative path: PackedByteArray
## or String}. Returns its folder.
static func write(id: String, manifest: Dictionary, files: Dictionary = {}) -> String:
	var dir := root().path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	for rel in files:
		var path := dir.path_join(str(rel))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if files[rel] is PackedByteArray:
			f.store_buffer(files[rel])
		else:
			f.store_string(str(files[rel]))
		f.close()
	var m := FileAccess.open(dir.path_join("addon.json"), FileAccess.WRITE)
	m.store_string(JSON.stringify(manifest, "  "))
	m.close()
	return dir


## A short WAV song's bytes.
static func wav_bytes(sound: String = "chime") -> PackedByteArray:
	var tmp := root().path_join("_tmp.wav")
	DirAccess.make_dir_recursive_absolute(root())
	(Synth.get_sound(sound) as AudioStreamWAV).save_to_wav(tmp)
	var b := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	return b


## The test theme: nine songs, the five cues, on by default. Returns its folder.
static func theme(id: String = "test-theme", extra: Dictionary = {}) -> String:
	var files := {}
	var songs: Array = []
	var bytes := wav_bytes()
	for s in THEME_SONGS:
		files["music/%s.wav" % s[0]] = bytes
		songs.append({"file": "music/%s.wav" % s[0], "title": s[1], "from": s[2], "seconds": s[3]})
	var cues := {}
	for cue in THEME_CUES:
		cues[cue] = "music/%s.wav" % THEME_CUES[cue]
	var m := {"id": id, "name": "Test Theme", "version": "1.0.0", "enabled_by_default": true, "overrides": {"music": cues, "songs": songs}}
	m.merge(extra, true)
	return write(id, m, files)


## Looks only in the test add-ons folder, and finds what's there now.
static func use(host: Node = null) -> void:
	Addons.override_folders = PackedStringArray([root()])
	Addons.refresh(host)


static func song_path(id: String, addon: String = "test-theme") -> String:
	return root().path_join(addon).path_join("music/%s.wav" % id)
