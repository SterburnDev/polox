extends "res://tests/test_case.gd"
## Add-ons (addons.gd): finding them reads only addon.json; on/off is kept in the settings; files that are
## missing, outside the add-on, the wrong kind or broken are listed and the game's own is used; words,
## pictures (the Soul), sounds, tiles and music cues change while an add-on is on and come back when it's
## off, saves untouched; scripts never run until trusted, and a changed script asks again; old names from
## before the Dream World read as today's; Title > Add-ons lists them and turns them on and off.
## Tags: [ADDONS]

const Addons := preload("res://scripts/core/addons.gd")
const Fixture := preload("res://tests/addon_fixture.gd")
const Soul := preload("res://scripts/ui/soul.gd")
const MusicPlayer := preload("res://scripts/world/music_player.gd")
const Synth := preload("res://scripts/core/synth.gd")
const Tilesets := preload("res://scripts/world/tilesets.gd")

var main: Node


func _fresh() -> void:
	fresh_save_root()
	GameState.settings.erase("addons")
	GameState.settings.erase("music_themes")
	Addons.reset()


func _png(size: int = 24, c: Color = Color("#b800c8")) -> PackedByteArray:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.fill_rect(Rect2i(size / 4, size / 4, size / 2, size / 2), c)
	return img.save_png_to_buffer()


func test_finding_an_addon_reads_only_its_manifest() -> void:
	_fresh()
	Fixture.write("lazy", {"name": "Lazy", "version": "1.0", "enabled_by_default": false,
		"overrides": {"textures": {"soul": "pictures/missing.png"}, "music": {"menu": "music/none.ogg"}}})
	Fixture.write("broken", {}, {})
	var f := FileAccess.open(Fixture.root().path_join("broken/addon.json"), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	DirAccess.make_dir_recursive_absolute(Fixture.root().path_join("no-manifest"))
	Fixture.use()
	var ids: Array = Addons.found().map(func(e): return str(e.id))
	eq(ids, ["broken", "lazy"], "folders with an addon.json, in name order (a folder without one is ignored)")
	var lazy := Addons.find("lazy")
	eq(str(lazy.name), "Lazy")
	eq(str(lazy.version), "1.0")
	check(not Addons.is_enabled("lazy"), "off by default when it says so")
	check(Addons.problems("lazy").is_empty(), "an add-on that's off isn't checked: its missing files aren't even looked at")
	check(Addons.problems("broken").any(func(p): return "valid JSON" in str(p)), "a manifest that isn't JSON says so")
	check(Addons.texture("soul") == null, "nothing changes while it's off")
	Addons.reset()


func test_bad_files_are_listed_and_the_games_own_is_used() -> void:
	_fresh()
	Fixture.write("bad", {"name": "Bad", "version": "0.1", "enabled_by_default": true, "overrides": {
		"textures": {"soul": "pictures/missing.png", "logo": "../../escape.png", "nonsense": "x.png"},
		"music": {"menu": "music/song.txt", "dark": "music/gone.ogg", "elevator": "music/x.ogg"},
		"sfx": {"chime": "C:/Windows/media/chimes.wav"},
		"weather": {"rain": "x"},
	}}, {"music/song.txt": "not music"})
	Fixture.use()
	check(Addons.is_active("bad"), "it's on (with what can be used)")
	var probs := " | ".join(Addons.problems("bad"))
	for want in ["missing.png is missing", "must be a file inside the add-on's folder", "isn't used by the game", "song.txt isn't a",
			"gone.ogg is missing", "elevator", "weather"]:
		check(want in probs, "listed: %s" % want)
	check(Addons.texture("soul") == null and not Soul.custom(), "the Soul stays Polox's own")
	eq(MusicPlayer.theme_path("menu"), MusicPlayer.OWN_PREFIX + "menu", "the menu keeps Polox's own tune")
	check(Synth._custom("chime") == null, "a sound outside the add-on is never played")
	# A file that's there but isn't a picture: found at use, listed, and the game's own is used.
	Fixture.write("fake", {"name": "Fake", "version": "1", "enabled_by_default": true, "overrides": {"textures": {"soul": "soul.png"}}}, {"soul.png": "this is not a png"})
	Fixture.use()
	check(not Soul.custom(), "a broken picture: the Dream Drop")
	check(Addons.problems("fake").any(func(p): return "can't be read" in str(p)), "and it says so")
	Addons.reset()


func test_on_and_off_are_kept_across_launches() -> void:
	_fresh()
	Fixture.write("pic", {"name": "Pic", "version": "1", "overrides": {"textures": {"soul": "soul.png"}}}, {"soul.png": _png()})
	Fixture.use()
	check(not Addons.is_enabled("pic"), "off by default")
	Addons.set_enabled("pic", true)
	check(Soul.custom(), "on: its picture is the Soul")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.settings_path()))
	eq(saved.addons.enabled.pic, true, "kept in settings.json")
	GameState.settings = SaveManager.load_settings()   # (a new launch reads the settings again)
	Addons.reset()
	Fixture.use()
	check(Addons.is_enabled("pic") and Soul.custom(), "still on after a restart")
	Addons.set_enabled("pic", false)
	check(not Soul.custom(), "off: the Dream Drop again")
	Addons.reset()


func test_words_change_while_on_and_old_names_read_as_new() -> void:
	_fresh()
	Fixture.use()
	eq(tr("Enter the Dark World"), "Enter the Dream World", "an old save's words read with today's names")
	eq(tr("Seal a Dark Fountain"), "Seal a Dream Gate")
	eq(tr("The Darkeners wave"), "The Bramins wave")
	eq(tr("THE DARK WORLD"), "THE DREAM WORLD", "in capitals too")
	eq(tr("A dark night"), "A dark night", "other words alone")
	Fixture.write("old-names", {"name": "Old names", "version": "1", "enabled_by_default": true, "overrides": {"text": {
		"Dream World": "Dark World", "Dream Gate": "Dark Fountain", "Bramins": "Darkeners", "Bramin": "Darkener"}}})
	Fixture.use()
	eq(tr("Enter the Dream World"), "Enter the Dark World", "an add-on's words")
	eq(tr("A Bramin and two Bramins"), "A Darkener and two Darkeners", "longest first")
	eq(tr("Seal a Dark Fountain"), "Seal a Dark Fountain", "old saves' words through both")
	var l := Label.new()
	l.text = "The Dream World"
	tree.root.add_child(l)
	await frames(1)
	eq(l.atr(l.text), "The Dark World", "a Label shows them")
	eq(l.text, "The Dream World", "but its text (and any save) is unchanged")
	Addons.set_enabled("old-names", false)
	eq(l.atr(l.text), "The Dream World", "off: the Dream World again")
	l.queue_free()
	Addons.reset()


func test_sounds_tiles_and_music_cues() -> void:
	_fresh()
	Tilesets.clear_cache()
	Fixture.write("bits", {"name": "Bits", "version": "1", "enabled_by_default": true, "overrides": {
		"sfx": {"chime": "chime.wav"}, "tiles": {"cozy_home/rug": "rug.png"}, "music": {"dark": "dark.wav"}}},
		{"chime.wav": Fixture.wav_bytes("pop"), "rug.png": _png(32, Color("#00ff00")), "dark.wav": Fixture.wav_bytes()})
	Fixture.use()
	Synth.clear_cache()
	var s := Synth.get_sound("chime")
	check(s is AudioStreamWAV and s != null, "an add-on's sound plays instead of the synth's")
	var img := Addons.tile("cozy_home", "rug")
	check(img != null and img.get_width() == 32, "an add-on's tile picture")
	eq(MusicPlayer.theme_path("dark"), Fixture.root().path_join("bits/dark.wav"), "an add-on's Dream World song")
	Fixture.theme("zz-theme", {"priority": 5})
	Fixture.use()
	eq(MusicPlayer.theme_path("dark"), Fixture.song_path("dream_song", "zz-theme"), "a higher priority add-on wins the cue")
	Addons.set_enabled("zz-theme", false)
	eq(MusicPlayer.theme_path("dark"), Fixture.root().path_join("bits/dark.wav"), "off: the other one's again")
	Addons.reset()
	Synth.clear_cache()


func test_scripts_run_only_once_trusted() -> void:
	_fresh()
	var src := "extends Node\nfunc _addon_start(api: Dictionary) -> void:\n\tset_meta(&\"started\", api.id)\n"
	Fixture.write("scripted", {"name": "Scripted", "version": "1", "enabled_by_default": true, "overrides": {"scripts": ["hello.gd"]}}, {"hello.gd": src})
	var host := Node.new()
	tree.root.add_child(host)
	Fixture.use()
	Addons.refresh(host)
	eq(Addons.running_scripts("scripted"), 0, "not trusted: nothing runs")
	check(Addons.problems("scripted").any(func(p): return "trust them" in str(p)), "and it says why")
	check(not Addons.is_trusted("scripted"))
	Addons.set_trusted("scripted", true)
	eq(Addons.running_scripts("scripted"), 1, "trusted: it runs")
	var n := host.get_child(0) if host.get_child_count() > 0 else null
	check(n != null and str(n.get_meta(&"started", "")) == "scripted", "and is started with its id")
	# The script changes: it has to be trusted again.
	Fixture.write("scripted", {"name": "Scripted", "version": "1", "enabled_by_default": true, "overrides": {"scripts": ["hello.gd"]}}, {"hello.gd": src + "# changed\n"})
	Addons.refresh(host)
	check(not Addons.is_trusted("scripted"), "a changed script isn't trusted any more")
	eq(Addons.running_scripts("scripted"), 0, "so it doesn't run")
	Addons.set_trusted("scripted", true)
	Addons.set_enabled("scripted", false)
	eq(Addons.running_scripts("scripted"), 0, "an add-on that's off runs nothing")
	Addons.reset()
	await frames(1)
	host.queue_free()


func test_the_soul_is_mochi_or_the_dream_drop() -> void:
	_fresh()
	Fixture.use()
	check(not Soul.custom(), "no add-on: Polox's own Soul")
	var t := Soul.texture()
	eq(t.get_size(), Vector2(Soul.SIZE, Soul.SIZE), "the Dream Drop")
	var drop := t.get_image()
	check(drop.get_pixel(Soul.SIZE / 2, Soul.SIZE / 2 + 10).a > 0.9 and drop.get_pixel(2, 2).a == 0.0, "a drop on nothing")
	Fixture.write("mochi", {"name": "Mochi", "version": "1", "enabled_by_default": true, "overrides": {"textures": {"soul": "m.png"}}}, {"m.png": _png(200)})
	Fixture.use()
	check(Soul.custom(), "an add-on's picture")
	var img := Soul.texture().get_image()
	eq(img.get_size(), Vector2i(Soul.SIZE, Soul.SIZE), "made square")
	check(img.get_pixel(1, 1).a == 0.0, "its white background is gone")
	var mid := img.get_pixel(Soul.SIZE / 2, Soul.SIZE / 2)
	check(mid.a > 0.9 and mid.b > 0.6 and mid.g < 0.3, "the picture itself is kept (%s)" % mid)
	var rim_found := false
	for x in Soul.SIZE / 2:
		var c := img.get_pixel(x, Soul.SIZE / 2)
		if c.a > 0.3 and c.r > 0.9 and c.g > 0.9:
			rim_found = true
	check(rim_found, "with a light rim to see it on black")
	Addons.reset()


## What's built in (assets/local on this PC: the soundtrack and Mochi) is on under every add-on and isn't
## listed; Polox Originals (bundled with the game) puts Polox's own tunes and the Dream Drop back.
func test_built_in_soundtrack_and_soul_and_polox_originals() -> void:
	_fresh()
	var bdir := Fixture.write("_built", {"name": "Built in", "version": "1", "overrides": {
		"music": {"menu": "menu.wav", "dark": "dark.wav", "survey": "home.wav"},
		"songs": [{"file": "menu.wav", "title": "Menu Tune", "gain_db": -3}],
		"textures": {"soul": "soul.png"}}},
		{"menu.wav": Fixture.wav_bytes(), "dark.wav": Fixture.wav_bytes(), "home.wav": Fixture.wav_bytes(), "soul.png": _png(64)})
	Addons.builtin_override = bdir
	Addons.override_folders = PackedStringArray([ProjectSettings.globalize_path(Addons.BUNDLED_DIR)])
	Addons.refresh()
	eq(Addons.builtin().get("name", ""), "Built in", "found")
	check(Addons.find("built-in").is_empty() and Addons.found().all(func(e): return str(e.id) != "_built"), "not in the Add-ons list")
	check(Addons.find("polox-originals").get("name", "") == "Polox Originals" and not Addons.is_enabled("polox-originals"), "Polox Originals comes with the game, off")
	eq(MusicPlayer.theme_path("menu"), bdir.path_join("menu.wav"), "the built-in title song")
	eq(MusicPlayer.theme("menu"), "Menu Tune")
	eq(MusicPlayer.gain_db(MusicPlayer.theme_path("menu")), -3.0, "at its level")
	eq(MusicPlayer.theme_path("light"), MusicPlayer.OWN_PREFIX + "light", "a cue it doesn't fill: Polox's own")
	check(Soul.custom(), "the built-in Soul")
	Addons.set_enabled("polox-originals", true)
	eq(MusicPlayer.theme_path("menu"), MusicPlayer.OWN_PREFIX + "menu", "Polox Originals: Polox's own tune on the title")
	eq(MusicPlayer.theme("dark"), MusicPlayer.OWN_TUNE, "and in the Dream World")
	eq(MusicPlayer.theme_path("survey"), "", "and its low hum while you make your home")
	eq(MusicPlayer.theme_path("battle"), "", "and its own battle tune")
	check(not Soul.custom(), "and the Dream Drop")
	check(Addons.problems("polox-originals").is_empty(), "with nothing missing (%s)" % [Addons.problems("polox-originals")])
	Fixture.theme("zz-theme", {"priority": 10})
	Addons.override_folders = PackedStringArray([ProjectSettings.globalize_path(Addons.BUNDLED_DIR), Fixture.root()])
	Addons.refresh()
	eq(MusicPlayer.theme_path("menu"), Fixture.song_path("title_song", "zz-theme"), "a higher add-on (UTDR Theme's 10) still wins")
	Addons.set_enabled("polox-originals", false)
	Addons.set_enabled("zz-theme", false)
	eq(MusicPlayer.theme_path("dark"), bdir.path_join("dark.wav"), "both off: the built-in song again")
	check(Soul.custom(), "and the built-in Soul")
	Fixture.write("bad-own", {"name": "Bad own", "version": "1", "enabled_by_default": true, "overrides": {"music": {"menu": "@nothing"}, "textures": {"logo": "@dream_drop"}}})
	Addons.refresh()
	check(Addons.problems("bad-own").size() == 2, "only @own for music and @dream_drop for the Soul (%s)" % [Addons.problems("bad-own")])
	Addons.reset()


func test_title_addons_button_lists_and_toggles() -> void:
	_fresh()
	Fixture.write("pic", {"name": "Pic", "version": "2.0", "description": "A picture.", "overrides": {"textures": {"soul": "soul.png"}}}, {"soul.png": _png()})
	Fixture.write("bad", {"name": "Bad", "version": "1", "enabled_by_default": true, "overrides": {"textures": {"soul": "nope.png"}}})
	Addons.override_folders = PackedStringArray([Fixture.root()])
	AIClient.configure({"preset": "mock"})
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)
	var b: Button = main.screen.find_child("AddonsButton", true, false)
	check(b != null and b.text == "Add-ons", "the title has an Add-ons button")
	b.pressed.emit()
	await frames(2)
	var panel: Control = main.panels.back()
	check(panel.find_child("AddonList", true, false) != null, "it opens the add-ons list")
	check(panel.find_child("AddonsFolder", true, false) != null, "and says where the folder is")
	var card: Node = panel.find_child("Addon_pic", true, false)
	check(card != null, "each add-on has a card")
	var toggle: CheckButton = card.find_child("Enabled", true, false)
	check(not toggle.button_pressed, "off")
	toggle.button_pressed = true
	await frames(2)
	check(Addons.is_enabled("pic") and Soul.custom(), "switched on from the list")
	var bad: Node = panel.find_child("Addon_bad", true, false)
	check(bad != null and bad.find_children("*", "Label", true, false).any(func(l): return "nope.png is missing" in str(l.text)), "a missing file is shown on its card")
	main.go_back()
	await frames(1)
	main.queue_free()
	await frames(2)
	Addons.reset()
