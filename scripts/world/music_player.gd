extends Node
## Background music. Five cues, each one changed in Settings > Music: the title menu (main.gd), the Light
## World's creation (the Survey, survey_screen.gd), the Light World, the Dream World and battles
## (battle_director.gd). What a cue plays: your choice in Settings > Music if that song is here, else an
## add-on's song for that cue (addons.gd: the highest priority one that's on), else Polox's own tune (made
## in code, battle_audio.gd, so a fresh copy of the game ships no one else's music). Songs to choose from:
## the add-ons' that are on, and your own from the drop-in folders:
##   PersonalData/audio/music/  and, run from the source, assets/audio/music/
## A place plays the song named in its ambiance (Build mode > Room), otherwise its world's cue; a friend
## with a theme gets their song while you chat; a battle or the Survey holds the world's music where it is
## until it's over, and a motif (the title's chime, a moment's) has the stage to itself; Settings > Music
## plays any song while it's open. Songs crossfade; volume follows Settings.

const Synth := preload("res://scripts/core/synth.gd")
const Addons := preload("res://scripts/core/addons.gd")
const AudioExit := preload("res://scripts/core/audio_exit.gd")
const Realms := preload("res://scripts/world/realms.gd")
const BattleAudio := preload("res://scripts/battle/battle_audio.gd")
const EXTS: PackedStringArray = ["ogg", "mp3", "wav"]
## The songs that come with the game: none (songs come from add-ons and your own folders). Kept so a song
## list from before (places, friends, themes naming a title) still reads: a title that isn't here plays
## its cue instead.
const SONGS := []
const THEMES: PackedStringArray = ["menu", "survey", "light", "dark", "battle"]
const THEME_NAMES := {"menu": "Title menu", "survey": "Light World creation", "light": "Light World", "dark": "Dream World", "battle": "Battles"}
## Until you or an add-on choose others: Polox's own tune everywhere (the Survey's is its low hum).
const DEFAULT_THEMES := {"menu": "(own tune)", "light": "(own tune)", "dark": "(own tune)", "battle": "(own tune)", "survey": "(own tune)"}
const QUIET := "(quiet)"          # a theme or a place with no music
const OWN_TUNE := "(own tune)"    # Polox's own tune (battle_audio.gd); the Survey: its low hum
const OWN_PREFIX := "own://"      # a path for Polox's own tune for a cue (own://menu)
## Polox's own tune for each cue that plays one through here: [seed, beats per minute].
const OWN_TUNES := {"menu": [11, 92.0], "light": [3, 104.0], "dark": [7, 84.0]}

var _players: Array[AudioStreamPlayer] = []
var _paths := ["", ""]   # what each player has
var _active := 0
var _current := ""
var _room_track := ""   # what the place (or the menu) plays, to come back to after a theme or a song you picked
var _previewing := false
var _holds := 0          # a battle, a motif: the music waits until every hold is released
var _tween: Tween


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		# Streamed everywhere: in the browser (Phone Link) Godot otherwise decodes a whole song into memory
		# before it starts (a 3-minute song: ~60 MB and a long freeze on a phone).
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(p)
		_players.append(p)
	GameState.settings_changed.connect(_apply_volume)


func _exit_tree() -> void:
	_kill_tween()
	for p in _players:
		AudioExit.release(p)
	AudioExit.settle()   # AudioServer retires a stopped PLAYBACK_TYPE_STREAM on its next mix pass


static func folders() -> PackedStringArray:
	var out := PackedStringArray([SaveManager.global_path("audio/music")])
	if OS.has_feature("editor"):   # (an exported game has no assets/ folder: on Android every look logged a warning)
		out.append(ProjectSettings.globalize_path("res://assets/audio/music"))
	return out


## Your own songs (full paths), from the drop-in folders.
static func tracks() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in folders():
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				if f.get_extension().to_lower() in EXTS:
					out.append(dir.path_join(f))
	return out


## Every song: the add-ons' (the higher priority first), then yours: [{title, from, seconds (0 = not known),
## path}]. Your song with the same title as an add-on's replaces it.
static func songs() -> Array:
	var out: Array = []
	var titles: Array = []
	for s in Addons.songs():
		if str(s.title) in titles:
			continue
		out.append({"title": str(s.title), "from": str(s.get("from", "")), "seconds": int(s.get("seconds", 0)), "path": str(s.path)})
		titles.append(str(s.title))
	var mine := {}   # your songs' titles: two files with one title (song.ogg, song.mp3) list the first, the one find_track plays
	for t in tracks():
		var title := t.get_file().get_basename()
		if mine.has(title):
			continue
		mine[title] = true
		var at := titles.find(title)
		if at >= 0:
			out[at] = {"title": title, "from": "Your song", "seconds": 0, "path": t}   # yours replaces the add-on's
		else:
			out.append({"title": title, "from": "Your song", "seconds": 0, "path": t})
			titles.append(title)
	return out


## A song as a stream that loops (its file's path in its "path" meta, for checks), or null.
static func load_stream(path: String) -> AudioStream:
	var s := _load_stream(path)
	if s:
		s.set_meta(&"path", path)
	return s


static func _load_stream(path: String) -> AudioStream:
	if path.begins_with(OWN_PREFIX):
		var tune: Array = OWN_TUNES.get(path.trim_prefix(OWN_PREFIX), [1, 100.0])
		return BattleAudio.loop(int(tune[0]), float(tune[1]))
	if path.begins_with("res://"):
		var r := load(path) as AudioStream   # imported (built in: assets/local)
		if r is AudioStreamMP3 or r is AudioStreamOggVorbis:
			r.set("loop", true)
		return r
	match path.get_extension().to_lower():
		"ogg":
			var s := AudioStreamOggVorbis.load_from_file(path)
			if s:
				s.loop = true
			return s
		"mp3":
			var s := AudioStreamMP3.load_from_file(path)
			if s:
				s.loop = true
			return s
		"wav":
			var s := AudioStreamWAV.load_from_file(path)
			if s:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = 0   # (Synth.safe_wav: the last frame, since Godot reads the frame at loop_end)
			return Synth.safe_wav(s)
	return null


## Where a song is, by title or file name (with or without extension), or "".
static func find_track(file_name: String) -> String:
	var want := file_name.strip_edges()
	if want == "" or want == QUIET or want == OWN_TUNE:
		return ""
	for t in tracks():
		if t.get_file().get_basename() == want.get_basename() or t.get_file().get_basename() == want:
			return t
	for s in Addons.songs():
		if str(s.title) == want or str(s.path).get_file().get_basename() == want.get_basename():
			return str(s.path)
	return ""


## Song titles for pickers.
static func track_names() -> PackedStringArray:
	var out := PackedStringArray()
	for s in songs():
		out.append(str(s.title))
	return out


## What you chose for a cue in Settings > Music, if it can play ("" = nothing chosen, or a song that's gone).
static func chosen(kind: String) -> String:
	var themes: Variant = GameState.settings.get("music_themes", {})
	var v := str((themes as Dictionary).get(kind, "")) if themes is Dictionary else ""
	if v == QUIET or v == OWN_TUNE or (v != "" and find_track(v) != ""):
		return v
	return ""


## The song a cue plays: a title, QUIET, or OWN_TUNE.
static func theme(kind: String) -> String:
	var v := chosen(kind)
	if v != "":
		return v
	var cue := Addons.music_cue(kind)
	if cue == Addons.OWN.music:
		return OWN_TUNE
	if cue != "":
		for s in Addons.songs():
			if str(s.path) == cue:
				return str(s.title)
		return cue.get_file().get_basename()
	return str(DEFAULT_THEMES.get(kind, OWN_TUNE))


static func set_theme(kind: String, song: String) -> void:
	var themes: Dictionary = (GameState.settings.get("music_themes") as Dictionary).duplicate() if GameState.settings.get("music_themes") is Dictionary else {}
	if song == "":
		themes.erase(kind)   # back to the add-on's or Polox's own
	else:
		themes[kind] = song
	GameState.settings["music_themes"] = themes
	GameState.save_settings()


## Where a cue's song is ("" = quiet, or (battles, the Survey) their own sound; own://<cue> = Polox's tune).
static func theme_path(kind: String) -> String:
	var v := chosen(kind)
	if v == "":
		var cue := Addons.music_cue(kind)
		if cue == Addons.OWN.music:
			return OWN_PREFIX + kind if OWN_TUNES.has(kind) else ""
		if cue != "":
			var title := theme(kind)
			for t in tracks():   # a song of yours with the cue song's title replaces it
				if t.get_file().get_basename() == title:
					return t
			return cue
		v = str(DEFAULT_THEMES.get(kind, OWN_TUNE))
	if v == QUIET:
		return ""
	if v == OWN_TUNE:
		return OWN_PREFIX + kind if OWN_TUNES.has(kind) else ""
	return find_track(v)


## A place's song: its own (Build mode > Room), else its world's theme ("" = quiet).
static func room_path(room: Dictionary) -> String:
	var own := str(room.get("ambiance", {}).get("music", ""))
	if own == QUIET:
		return ""
	var path := find_track(own)
	return path if path != "" else theme_path("light" if Realms.is_light(room) else "dark")


## A battle's song: its own if it names one that's here, else the battle theme ("" = Polox's own tune).
static func battle_path(battle: Dictionary) -> String:
	if str(battle.get("music", "")) in ["@original", "@silence"]:
		return ""
	var own := find_track(str(battle.get("music", "")))
	return own if own != "" else theme_path("battle")


## The title and the screens opened from it.
func play_menu() -> void:
	_room_track = theme_path("menu")
	if not _previewing:
		crossfade(_room_track)


## Leaving the menu (a world starts, or one's being made): nothing more from here.
func silence() -> void:
	_room_track = ""
	_previewing = false
	crossfade("")


## Picks and crossfades to the right song for a place.
func play_for_room(room: Dictionary) -> void:
	_room_track = room_path(room)
	if not _previewing:
		crossfade(_room_track)


## A friend's theme while you talk with them. Returns false if not found.
func play_theme(file_name: String) -> bool:
	var path := find_track(file_name)
	if path == "":
		return false
	crossfade(path)
	return true


func back_to_room() -> void:
	crossfade(_room_track)


## Settings > Music: a song to listen to now ("" = back to what was playing).
func preview(path: String) -> void:
	_previewing = path != ""
	crossfade(path if _previewing else _room_track)


func previewing() -> bool:
	return _previewing


func current_track() -> String:
	return _current


## A song is coming out of the speakers now (not waiting, not quiet).
func is_playing() -> bool:
	var p := _players[_active]
	return _holds == 0 and _current != "" and p.playing and not p.stream_paused


## A motif (synth.gd) has the stage: the music steps aside while it plays and comes back after.
func make_way(motif: String) -> void:
	if not is_inside_tree():
		return
	var seconds := 0.0
	for note in Synth.MOTIFS.get(motif, [[]])[0]:
		seconds += float(note[1])
	hold()
	get_tree().create_timer(seconds + 0.2).timeout.connect(release)


## A battle brings its own music: the world's fades and pauses where it is, and carries on after (release).
func hold() -> void:
	_holds += 1
	if _holds > 1:
		return
	_kill_tween()
	if not is_inside_tree():
		return
	_tween = create_tween().set_parallel(true)
	for p in _players:
		_tween.tween_property(p, "volume_db", -80.0, 0.6)
	_tween.chain().tween_callback(func():
		_players[1 - _active].stop()
		_players[_active].stream_paused = true)


func release() -> void:
	if _holds == 0:
		return
	_holds -= 1
	if _holds > 0:
		return
	_kill_tween()
	if not is_inside_tree():
		return
	_players[1 - _active].stop()
	var p := _players[_active]
	if _current == "" or _paths[_active] != _current or p.stream == null:
		p.stop()
		_paths[_active] = ""
		_fade_to(_current)   # (the song changed while it waited)
		return
	p.stream_paused = false
	if not p.playing:
		p.play()
	_tween = create_tween()
	_tween.tween_property(p, "volume_db", _target_db(), 1.2)
	_tween.tween_callback(_apply_volume)   # (the volume may have changed while it faded in)


func held() -> bool:
	return _holds > 0


func crossfade(path: String) -> void:
	if path == _current:
		return
	_current = path
	if _holds == 0:
		_fade_to(path)


func _fade_to(path: String) -> void:
	_kill_tween()
	if not is_inside_tree():   # (the game is closing, e.g. Settings > Music handing the music back as it goes)
		return
	var old := _players[_active]
	_active = 1 - _active
	var new := _players[_active]
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(old, "volume_db", -80.0, 1.5)
	new.stop()
	new.stream_paused = false
	_paths[_active] = path
	if path != "":
		new.stream = load_stream(path)
		if new.stream:
			new.volume_db = -40.0
			new.play()
			_tween.tween_property(new, "volume_db", _target_db(), 1.5)
	_tween.chain().tween_callback(func():
		old.stop()
		old.stream = null)   # a quiet player still decodes: stop it once it has faded
	_tween.tween_callback(_apply_volume)   # (and a volume changed during the fade holds, not the old one)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


## How loud a song plays (Settings' music volume); the Survey's song too.
static func song_db() -> float:
	return linear_to_db(maxf(0.0001, float(GameState.settings.get("music_volume", 0.7)) * 0.6))


## How much louder or quieter an add-on's song is meant to play (its "gain_db"), 0 for any other.
static func gain_db(path: String) -> float:
	if path == "" or path.begins_with(OWN_PREFIX):
		return 0.0
	for s in Addons.songs():
		if str(s.path) == path:
			return float(s.get("gain_db", 0.0))
	return 0.0


func _target_db() -> float:
	return song_db() + gain_db(str(_paths[_active]))


func _apply_volume() -> void:
	if _holds == 0 and _current != "" and _players[_active].playing:
		_players[_active].volume_db = _target_db()
