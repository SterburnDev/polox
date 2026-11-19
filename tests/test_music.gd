extends "res://tests/test_case.gd"
## Music: the five cues and Settings > Music. A fresh copy of Polox ships no songs and plays its own tune
## for every cue; an add-on brings songs and cue songs (here the test theme, addon_fixture.gd: the menu
## Title Song after the title's chime, the Light World Light Song, the Dream World Dream Song,
## battles Battle Song and the Light World's creation (the Survey) Making Home); the world's song waits
## for a battle, a moment's motif or the Survey and carries on after; a place can have its own song or
## none; your own songs join (and replace one of the same name); Settings > Music plays any song and
## changes the cues; Settings opens on the tab it names.

const MusicPlayer := preload("res://scripts/world/music_player.gd")
const Realms := preload("res://scripts/world/realms.gd")
const LightHome := preload("res://scripts/world/light_home.gd")
const BattleData := preload("res://scripts/battle/battle_data.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const Synth := preload("res://scripts/core/synth.gd")
const Ambience := preload("res://scripts/world/ambience.gd")
const BattleAudio := preload("res://scripts/battle/battle_audio.gd")
const Addons := preload("res://scripts/core/addons.gd")
const Fixture := preload("res://tests/addon_fixture.gd")

var main: Node


func _path(id: String) -> String:
	return Fixture.song_path(id)


## A fresh save folder with the test theme on.
func _fresh() -> void:
	fresh_save_root()
	GameState.settings.erase("music_themes")
	GameState.settings.erase("addons")
	Fixture.theme()
	Fixture.use()


func _stream_path(s: AudioStream) -> String:
	return str(s.get_meta(&"path", "")) if s else ""


func _boot_title() -> void:
	_fresh()
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)


func _boot_world() -> Node:
	await _boot_title()
	main.begin_new_world()
	await frames(3)
	LightHome.ensure_entry()
	LightHome.defer_survey()
	for n in main.ui.find_children("*", "", true, false):   # the start-up cards (a player taps Got it)
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()
	await frames(2)
	return main.game


func _shutdown() -> void:
	GameState.settings.erase("music_themes")
	if main.game and main.game.build.active:
		main.game.build.exit()
	main.queue_free()
	await frames(2)
	Addons.reset()


func _wait_until(cond: Callable, ms: int = 5000) -> bool:
	var t := Time.get_ticks_msec()
	while not bool(cond.call()) and Time.get_ticks_msec() - t < ms:
		await frames(2)
	return bool(cond.call())


func _start_battle(g: Node, battle: Dictionary = {}) -> Control:
	var foe := str(g.actors.keys()[0])
	g.battles.start(battle if not battle.is_empty() else BattleData.from_template("friendly_spar", GameState.get_character(foe)), [])
	await _wait_until(func(): return g.battles.screen != null, 4000)
	return g.battles.screen


func _end_battle(g: Node, scr: Control) -> void:
	scr.state.outcome = "ran"
	scr.finish()
	await _wait_until(func(): return g.battles.screen == null, 2000)


func test_a_fresh_copy_plays_polox_own_tune_and_add_ons_bring_songs() -> void:
	fresh_save_root()
	GameState.settings.erase("music_themes")
	Addons.reset()
	Addons.override_folders = PackedStringArray([])
	Addons.refresh()
	eq(MusicPlayer.SONGS.size(), 0, "no songs ship with the game")
	eq(MusicPlayer.songs().size(), 0, "none to pick without an add-on")
	for kind in ["menu", "light", "dark"]:
		eq(MusicPlayer.theme(kind), MusicPlayer.OWN_TUNE, "the %s cue: Polox's own tune" % kind)
		eq(MusicPlayer.theme_path(kind), MusicPlayer.OWN_PREFIX + kind, "made in code")
		var w: AudioStream = MusicPlayer.load_stream(MusicPlayer.theme_path(kind))
		check(w is AudioStreamWAV and (w as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s: it loops" % kind)
	eq(MusicPlayer.theme_path("battle"), "", "battles: their own tune (battle_audio.gd)")
	eq(MusicPlayer.theme_path("survey"), "", "the Light World's creation: its own hum")
	eq(MusicPlayer.theme("survey"), MusicPlayer.OWN_TUNE)
	Fixture.theme()
	Fixture.use()
	eq(MusicPlayer.songs().size(), Fixture.THEME_SONGS.size(), "an add-on's songs")
	eq(str(MusicPlayer.songs()[0].title), "Title Song", "in its order")
	eq(MusicPlayer.find_track("Light Song"), _path("light_song"), "found by title")
	eq(MusicPlayer.find_track("battle_song"), _path("battle_song"), "or by file name")
	eq(MusicPlayer.find_track("Not a song here"), "", "not a song")
	eq(MusicPlayer.track_names().size(), Fixture.THEME_SONGS.size(), "the pickers list them all")
	var w: AudioStream = MusicPlayer.load_stream(_path("light_song"))
	check(w is AudioStreamWAV and (w as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "an add-on's song loops")
	Addons.reset()


## Godot reads the frame at loop_end before a loop wraps and keeps nothing after a sound's data, so every
## looping sound the game makes has its first frames again there. (On the phone the Light World's room tone
## read past its buffer 8 s in, and the game died in the audio thread: SIGSEGV in "AudioTrack", 1.27.10.)
func test_every_looping_sound_has_its_start_again_after_its_end() -> void:
	fresh_save_root()
	var sounds := {"the pillars' hum": Synth._hum(), "Polox's own battle tune": BattleAudio.loop(7), "the Survey's hum": preload("res://scripts/home/survey_screen.gd").drone()}
	for k in ["home_day", "home_night", "street_day", "street_night"]:
		sounds["the Light World's " + k] = Ambience.loop(k)
	for what in sounds:
		var w: AudioStreamWAV = sounds[what]
		var fb := 4 if w.stereo else 2
		var frames := w.data.size() / fb
		check(w.loop_mode == AudioStreamWAV.LOOP_FORWARD and frames >= w.loop_end + Synth.LOOP_PAD, "%s: frames after its loop end (%d, loop end %d)" % [what, frames, w.loop_end])
		check(w.data.slice(w.loop_end * fb, (w.loop_end + Synth.LOOP_PAD) * fb) == w.data.slice(0, Synth.LOOP_PAD * fb), "%s: and they're its start, so it loops without a seam" % what)
	Synth._hum().save_to_wav(SaveManager.global_path("audio/music/loop_me.wav"))
	var mine: AudioStreamWAV = MusicPlayer.load_stream(SaveManager.global_path("audio/music/loop_me.wav"))
	check(mine != null and mine.loop_end < mine.data.size() / (4 if mine.stereo else 2), "your own WAV song's loop ends on its last frame")


func test_the_five_themes_and_changing_them() -> void:
	_fresh()
	eq(MusicPlayer.theme_path("menu"), _path("title_song"), "the menu: Title Song")
	eq(MusicPlayer.theme_path("light"), _path("light_song"), "the Light World: Light Song")
	eq(MusicPlayer.theme_path("dark"), _path("dream_song"), "the Dream World: Dream Song")
	eq(MusicPlayer.theme_path("battle"), _path("battle_song"), "battles: Battle Song")
	eq(MusicPlayer.theme_path("survey"), _path("making_home"), "the Survey: Making Home")
	MusicPlayer.set_theme("light", "Falls Song")
	eq(MusicPlayer.theme_path("light"), _path("falls_song"), "a theme changes")
	eq(str(GameState.settings.music_themes.light), "Falls Song", "and is saved in the settings")
	MusicPlayer.set_theme("light", MusicPlayer.QUIET)
	eq(MusicPlayer.theme_path("light"), "", "or goes quiet")
	MusicPlayer.set_theme("battle", MusicPlayer.OWN_TUNE)
	eq(MusicPlayer.battle_path({}), "", "battles can have Polox's own tune")
	eq(MusicPlayer.battle_path({"music": "Egg Song"}), _path("egg_song"), "a battle's own song still wins")
	MusicPlayer.set_theme("dark", "A song that was deleted")
	eq(MusicPlayer.theme_path("dark"), _path("dream_song"), "a song that's gone: the add-on's cue plays")
	MusicPlayer.set_theme("light", "")
	eq(MusicPlayer.theme_path("light"), _path("light_song"), "Automatic: the add-on's cue again")
	Addons.set_enabled("test-theme", false)
	eq(MusicPlayer.theme_path("light"), MusicPlayer.OWN_PREFIX + "light", "the add-on off: Polox's own tune")
	eq(MusicPlayer.battle_path({"music": "Egg Song"}), "", "and its songs are gone")
	GameState.settings.erase("music_themes")
	Addons.reset()


func test_a_place_plays_its_own_song_or_its_worlds_theme() -> void:
	_fresh()
	var light := {"id": Realms.ENTRY, "ambiance": {"music": ""}}
	var dark := {"id": "garden", "ambiance": {"music": ""}}
	eq(MusicPlayer.room_path(light), _path("light_song"), "the Light World's theme")
	eq(MusicPlayer.room_path(dark), _path("dream_song"), "the Dream World's theme")
	dark.ambiance.music = "Snow Song"
	eq(MusicPlayer.room_path(dark), _path("snow_song"), "a place's own song")
	dark.ambiance.music = MusicPlayer.QUIET
	eq(MusicPlayer.room_path(dark), "", "or none")
	dark.ambiance.music = "a_deleted_song"
	eq(MusicPlayer.room_path(dark), _path("dream_song"), "a song that's gone: the theme")
	Addons.reset()


func test_your_own_songs_join_and_can_replace_one() -> void:
	_fresh()
	var wav: AudioStreamWAV = preload("res://scripts/core/synth.gd").get_sound("chime")
	wav.save_to_wav(SaveManager.global_path("audio/music/my_song.wav"))
	wav.save_to_wav(SaveManager.global_path("audio/music/Light Song.wav"))
	var all := MusicPlayer.songs()
	eq(all.size(), Fixture.THEME_SONGS.size() + 1, "the add-on's and yours")
	eq(str(all[0].title), "Title Song", "the add-on's first")
	var mine: Array = all.filter(func(s): return str(s.title) == "my_song")
	check(mine.size() == 1 and str(mine[0].from) == "Your song", "yours, by its file name")
	check(MusicPlayer.find_track("Light Song").ends_with("audio/music/Light Song.wav"), "a song of yours with an add-on song's title replaces it")
	var fest: Array = all.filter(func(s): return str(s.title) == "Light Song")
	check(fest.size() == 1 and str(fest[0].from) == "Your song" and int(fest[0].seconds) == 0, "and the list says it's yours")
	check(MusicPlayer.theme_path("light").ends_with("audio/music/Light Song.wav"), "so the Light World plays yours")
	eq(MusicPlayer.track_names().size(), Fixture.THEME_SONGS.size() + 1, "listed once")
	var f := FileAccess.open(SaveManager.global_path("audio/music/my_song.mp3"), FileAccess.WRITE)
	f.store_string("(only listed, never played)")
	f.close()
	mine = MusicPlayer.songs().filter(func(s): return str(s.title) == "my_song")
	check(mine.size() == 1 and str(mine[0].path) == MusicPlayer.find_track("my_song"), "two files with one name: the list shows the one that plays")
	eq(MusicPlayer.folders().size(), 2 if OS.has_feature("editor") else 1, "assets/audio/music only when run from the source")
	Addons.reset()


func test_a_volume_change_during_a_fade_is_kept() -> void:
	_fresh()
	var m: Node = MusicPlayer.new()
	tree.root.add_child(m)
	var was := float(GameState.settings.get("music_volume", 0.7))
	GameState.settings["music_volume"] = 0.7
	m.crossfade(_path("light_song"))
	await frames(3)
	GameState.settings["music_volume"] = 0.3   # Settings > Comfort & sound, while the song fades in
	GameState.save_settings()
	check(await _wait_until(func(): return not m._tween.is_valid(), 4000), "the fade ends")
	var p: AudioStreamPlayer = m._players[m._active]
	check(p.playing and absf(p.volume_db - linear_to_db(0.3 * 0.6)) < 0.1, "at the new volume (%.1f dB)" % p.volume_db)
	check(not m._players[1 - m._active].playing, "the other player stopped")
	GameState.settings["music_volume"] = was
	GameState.save_settings()
	m.queue_free()
	await frames(1)
	Addons.reset()


## Closing the game with Settings > Music playing a song: the page hands the music back on its way out,
## after the player has left the scene. Nothing may start then (1.27.8 logged "Playback can only happen
## when a node is inside the scene tree" and left a fade behind).
func test_a_player_leaving_the_scene_starts_nothing() -> void:
	_fresh()
	var m: Node = MusicPlayer.new()
	tree.root.add_child(m)
	m.crossfade(_path("light_song"))
	await frames(2)
	tree.root.remove_child(m)
	m.preview(_path("falls_song"))
	m.preview("")
	m.hold()
	m.release()
	m.make_way("motif_title")
	check(m._tween == null or not m._tween.is_valid(), "no fade is left running")
	check(not m.held(), "holds still balance")
	m.free()
	Addons.reset()


func test_the_menu_theme_follows_the_titles_chime() -> void:
	await _boot_title()
	var m: Node = main.music
	check(m._players.all(func(p): return p.playback_type == AudioServer.PLAYBACK_TYPE_STREAM), "songs stream (in the browser a sample decodes the whole song first)")
	eq(m.current_track(), _path("title_song"), "the title plays Title Song")
	check(m.held(), "after the title's chime")
	check(await _wait_until(func(): return m.is_playing(), 4000), "then it plays")
	main.open_worlds()
	await frames(2)
	check(m.is_playing() and m.current_track() == _path("title_song"), "the Worlds screen keeps it")
	main.go_back()
	await frames(2)
	main.show_onboarding()
	await frames(2)
	eq(m.current_track(), "", "making a world: the Survey's song, no menu theme")
	var mapper: Node = main.get_node_or_null("NewWorldHomeMapper")
	check(mapper != null and mapper.screen._tune.stream != null and _stream_path(mapper.screen._tune.stream) == _path("making_home"), "the Survey plays Making Home")
	if mapper:
		mapper.screen._finish("skipped")
	await _wait_until(func(): return main.screen != null, 8000)
	main.go_back()
	await frames(2)
	eq(m.current_track(), _path("title_song"), "back on the title, Title Song again")
	main.begin_new_world()
	await frames(3)
	eq(m.current_track(), "", "a world starts: the menu theme stops")
	check(main.music_now() == main.game.music, "the world plays its own")
	for args in [["--host"], ["--ping"], ["--doctor"], ["--write-build-id"]]:
		check(main.service_only(PackedStringArray(args)), "%s: no game, no menu theme" % args[0])
	check(not main.service_only(PackedStringArray(["--touch-ui", "--save-root=x"])), "the game itself has it")
	await _shutdown()


func test_the_worlds_play_their_themes_and_battles_battle_song() -> void:
	var g: Node = await _boot_world()
	check(not Realms.is_light(g.room.data), "starting in the Dream World")
	eq(g.music.current_track(), _path("dream_song"), "the Dream World plays Dream Song")
	check(await _wait_until(func(): return g.music.is_playing(), 3000), "out loud")
	var scr: Control = await _start_battle(g)
	check(scr != null, "a battle")
	check(g.music.held(), "the world's song waits from the encounter on")
	check(scr.music_stream != null and _stream_path(scr.music_stream) == _path("battle_song"), "the battle plays Battle Song")
	eq(scr.music.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "streamed, like the world's songs")
	check(await _wait_until(func(): return scr.music.playing, 3000), "out loud")
	await _end_battle(g, scr)
	eq(g.music.current_track(), _path("dream_song"), "afterwards, Dream Song")
	check(await _wait_until(func(): return g.music.is_playing(), 6000), "carries on (after the welcome-back motif)")
	MusicPlayer.set_theme("battle", MusicPlayer.OWN_TUNE)
	scr = await _start_battle(g)
	check(scr != null and scr.music_stream is AudioStreamWAV, "Polox's own tune, made for the battle")
	await _end_battle(g, scr)
	MusicPlayer.set_theme("battle", "Strong Song")
	scr = await _start_battle(g)
	check(scr != null and _stream_path(scr.music_stream) == _path("strong_song"), "or another song")
	await _end_battle(g, scr)
	await _shutdown()


func test_a_moments_motif_and_the_survey_have_the_stage() -> void:
	var g: Node = await _boot_world()
	check(await _wait_until(func(): return g.music.is_playing(), 3000), "Dream Song plays")
	g.signatures.first_fountain()
	check(g.music.held(), "the music steps aside for the Dream World's motif")
	check(await _wait_until(func(): return g.music.is_playing(), 5000), "and comes back after it")
	var was: Node = tree.current_scene
	tree.current_scene = main   # (as in the game: main.tscn is the scene)
	var survey: Control = preload("res://scripts/home/survey_screen.gd").new()
	survey.available = {}
	main.toast_layer().add_child(survey)
	await frames(2)
	check(g.music.held(), "the world's song waits for the Survey (Map my home)")
	check(survey._tune.playing and _stream_path(survey._tune.stream) == _path("making_home"), "the Survey plays its theme, Making Home")
	eq(survey._tune.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "streamed, like the world's songs")
	survey.queue_free()
	await frames(2)
	check(not g.music.held(), "the song comes back when the Survey closes")
	MusicPlayer.set_theme("survey", MusicPlayer.OWN_TUNE)
	survey = preload("res://scripts/home/survey_screen.gd").new()
	survey.available = {}
	main.toast_layer().add_child(survey)
	await frames(2)
	check(survey._tune.playing and survey._tune.stream is AudioStreamWAV, "or its own low hum, if you pick that")
	survey.queue_free()
	await frames(2)
	GameState.settings.erase("music_themes")
	tree.current_scene = was
	await _shutdown()


func test_a_place_can_have_its_own_song_or_none() -> void:
	var g: Node = await _boot_world()
	var b: Node = g.build
	b.enter()
	await frames(1)
	b.set_mode("room")
	await frames(1)
	var opt: OptionButton = b.shell.room_tab._music
	eq(opt.get_item_text(opt.selected), "Music: the world's theme", "a place plays its world's theme")
	eq(opt.get_item_text(1), "Music: quiet", "or nothing")
	var snow := -1
	for i in opt.item_count:
		if opt.get_item_text(i) == "Music: Snow Song":
			snow = i
	check(snow > 1, "every song is offered")
	opt.select(snow)
	opt.item_selected.emit(snow)
	await frames(2)
	eq(str(g.room.data.ambiance.music), "Snow Song", "the place keeps its song")
	eq(g.music.current_track(), _path("snow_song"), "and plays it")
	opt.select(1)
	opt.item_selected.emit(1)
	await frames(2)
	eq(str(g.room.data.ambiance.music), MusicPlayer.QUIET)
	eq(g.music.current_track(), "", "a quiet place")
	await _shutdown()


func test_settings_music_plays_any_song_and_changes_the_themes() -> void:
	await _boot_title()
	check(await _wait_until(func(): return main.music.is_playing(), 4000), "the menu theme plays")
	var s: Control = SettingsScreen.new()
	s.main = main
	s.start_on = "Music"
	main.open_panel(s)
	await frames(2)
	var tabs: TabContainer = s.find_children("*", "TabContainer", true, false)[0]
	eq(tabs.get_tab_title(tabs.current_tab), "Music", "Settings > Music")
	var page: Node = tabs.get_current_tab_control()
	for kind in MusicPlayer.THEMES:
		var opt: OptionButton = page.find_child("Theme_" + kind, true, false)
		check(opt != null and opt.get_item_text(opt.selected) == "Automatic", "the %s cue shows Automatic (the add-on's song)" % kind)
	var at: int = MusicPlayer.track_names().find("Light Song")
	var play: Button = page.find_child("Play%d" % at, true, false)
	check(play != null and play.text == "▶", "every song has a play button")
	check(str(page._notes[at].text) == "Test Album 5 • 2:00 • Light World", "Light Song: where it's from, how long, what it's the theme of (%s)" % page._notes[at].text)
	var ah: int = MusicPlayer.track_names().find("Making Home")
	check(str(page._notes[ah].text) == "Test Album 1 • 0:48 • Light World creation", "Making Home: the Light World's creation (%s)" % page._notes[ah].text)
	play.pressed.emit()
	await frames(2)
	eq(main.music.current_track(), _path("light_song"), "a song plays from the page")
	check(main.music.previewing() and play.text == "■", "with a stop button")
	play.pressed.emit()
	await frames(2)
	eq(main.music.current_track(), _path("title_song"), "stop: the menu theme comes back")
	var menu_opt: OptionButton = page.find_child("Theme_menu", true, false)
	var falls_song := -1
	for i in menu_opt.item_count:
		if menu_opt.get_item_text(i) == "Falls Song":
			falls_song = i
	menu_opt.select(falls_song)
	menu_opt.item_selected.emit(falls_song)
	await frames(2)
	eq(MusicPlayer.theme("menu"), "Falls Song", "a new menu theme is saved")
	eq(main.music.current_track(), _path("falls_song"), "and plays at once")
	var wf: int = MusicPlayer.track_names().find("Falls Song")
	eq(str(page._notes[wf].text), "Test Album • 2:04 • title menu", "the list says so")
	page.toggle(0)
	await frames(2)
	eq(main.music.current_track(), _path("title_song"), "listening to Title Song")
	main.go_back()   # closes Settings while it plays
	await frames(3)
	check(not main.music.previewing(), "closing Settings ends the song you picked")
	eq(main.music.current_track(), _path("falls_song"), "back to the (new) menu theme")
	await _shutdown()


func test_settings_open_on_the_tab_they_name() -> void:
	await _boot_title()
	main.open_phone_link_settings()
	await frames(2)
	var s: Control = main.panels.back()
	var tabs: TabContainer = s.find_children("*", "TabContainer", true, false)[0]
	eq(tabs.get_tab_title(tabs.current_tab), "Phone Link", "Phone Link's banner opens Phone Link (it opened the Light World tab)")
	var titles: Array = []
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	eq(titles, ["Gameplay", "Display", "Audio", "Music", "Controls", "Accessibility", "AI", "Light World", "Phone Link", "Cloud sync"], "categories; Music sits beside Audio (Cloud sync since 1.29)")
	main.go_back()
	await frames(2)
	var old := SettingsScreen.new()
	old.start_on = "Comfort & sound"   # (What's new and older help still say this)
	main.open_panel(old)
	await frames(2)
	eq(old.tabs.get_tab_title(old.tabs.current_tab), "Gameplay", "an old tab name opens its new page")
	await _shutdown()
