extends "res://tests/test_case.gd"
## Phase 10, your character: the doll maker's art, Real Me / Dream World Me
## (switching, room ties, custom drawings), the Player Profile in every
## prompt, voices, and the v1 -> v2 world upgrade (snapshot first).

const Doll := preload("res://scripts/characters/doll.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const Conversation := preload("res://scripts/ai/conversation.gd")
const PromptBuilder := preload("res://scripts/ai/prompt_builder.gd")
const WorldMigration := preload("res://scripts/core/world_migration.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")
const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Defaults := preload("res://scripts/core/defaults.gd")
const Voice := preload("res://scripts/characters/voice.gd")
const Feelings := preload("res://scripts/characters/feelings.gd")


func test_doll_styles_expressions_and_randomize() -> void:
	var base := Doll.compose(Doll.defaults(), "neutral")
	eq(base.get_size(), Vector2i(32, 32))
	check(not base.is_invisible(), "draws something")
	# Every style of every part changes the picture (and none crash).
	for part in Doll.PARTS:
		var seen := {}
		for s in Doll.STYLES[part]:
			var r := Doll.defaults()
			r[part]["style"] = str(s[0])
			seen[Doll.compose(r, "neutral").get_data().hex_encode().md5_text()] = true
		eq(seen.size(), (Doll.STYLES[part] as Array).size(), "%s styles all look different" % part)
	check(Doll.STYLES.hair.size() >= 6 and Doll.STYLES.hair.size() <= 8, "6-8 hair styles")
	var faces := {}
	for e in Defaults.DEFAULT_EXPRESSIONS:
		faces[Doll.compose(Doll.defaults(), e).get_data().hex_encode().md5_text()] = true
	eq(faces.size(), Defaults.DEFAULT_EXPRESSIONS.size(), "each expression has its own face")
	var tinted := Doll.defaults()
	tinted.outfit.color = "#2266ff"
	check(Doll.compose(tinted).get_data() != base.get_data(), "colour (HSV tint) changes the picture")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rand := Doll.randomize(rng)
	eq(Doll.normalize(rand), rand, "random recipes are valid")
	eq(Doll.normalize({"hair": {"style": "nonsense", "color": "zzz"}}).hair, Doll.defaults().hair, "bad recipes repair themselves")
	check(Doll.describe(Doll.preset("night")).contains("visor"), "describes the look: " + Doll.describe(Doll.preset("night")))


func test_saved_doll_presets_are_shared() -> void:
	fresh_save_root()
	var id := Doll.save_preset("Rainy day me", Doll.preset("gardener"))
	var found := Doll.saved_presets().filter(func(p): return p.id == id)
	eq(found.size(), 1)
	eq(found[0].recipe, Doll.preset("gardener"))
	check(FileAccess.file_exists(SaveManager.global_path("library/dolls/%s.json" % id)), "kept in the Library (all worlds)")
	Doll.delete_preset(id)
	eq(Doll.saved_presets().size(), 0)


func test_two_forms_are_editable_but_wearing_follows_the_realm() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	GameState.load_world()
	eq(PlayerLook.current(), "dark", "the starter world is Dream World")
	for f in PlayerLook.FORMS:
		eq(PlayerLook.form_data(f).expressions.size(), 8, "%s has all faces on disk" % f)
	check(PlayerLook.texture("real", "neutral") != PlayerLook.texture("dark", "neutral"), "two different looks")
	var night := Doll.preset("sleepy")
	PlayerLook.save_doll("dark", night)
	eq(PlayerLook.form_data("dark").doll, Doll.normalize(night))
	check(not PlayerLook.set_form("real"), "cannot wear Light appearance in Dream World")
	check(PlayerLook.set_form("dark"), "current realm appearance can be worn")
	eq(str(SaveManager.load_world().player.form), "dark", "the correct form is saved")
	var room := SaveManager.load_room("garden")
	room["player_form"] = "real"
	check(not PlayerLook.apply_room(room), "legacy per-room override cannot break realm rule")
	eq(PlayerLook.current(), "dark")
	check(PlayerLook.apply_room({"id": "lw_test", "realm": "light", "player_form": "dark"}), "entering Light selects Real Me despite override")
	eq(PlayerLook.current(), "real")
	check(not PlayerLook.set_form("dark"), "cannot wear Dark appearance in Light World")
	check(PlayerLook.apply_room(SaveManager.load_room("home")), "returning Dark restores Dark appearance")
	eq(PlayerLook.form_data("dark").doll, Doll.normalize(night), "customized other outfit is retained")


func test_forms_in_the_world_and_player_faces() -> void:
	fresh_save_root()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	var g: Node = main.game
	var dark_tex: Texture2D = g.player.sprite.texture
	g.switch_form()
	await frames(1)
	eq(PlayerLook.current(), "dark")
	check(g.player.sprite.texture == dark_tex, "manual switch cannot wear the wrong realm's appearance")
	# Legacy room overrides no longer cross realms.
	var garden := SaveManager.load_room("garden")
	garden["player_form"] = "real"
	SaveManager.save_room(garden)
	g.load_room("garden")
	await frames(1)
	eq(PlayerLook.current(), "dark", "Dark garden ignores legacy Real Me override")
	var light_id: String = load("res://scripts/world/light_home.gd").ensure_entry()
	g.load_room(light_id)
	await frames(1)
	eq(PlayerLook.current(), "real", "actual Light World travel selects Real Me")
	check(g.player.sprite.texture != dark_tex, "realm travel refreshes the visible appearance")
	var neutral: Texture2D = g.player.sprite.texture
	g.set_player_emotion("happy", 0.0)
	check(g.player.sprite.texture != neutral, "your face changes with what you say")
	eq(Feelings.guess("I passed my exam, yay!"), "happy")
	eq(Feelings.guess("rough day honestly"), "sad")
	eq(Feelings.guess("what should I cook?"), "thinking")
	# The walk animation squashes on landing.
	var pts: Array[Vector3] = [g.room.cell_center(g.player.cell() + Vector2i(1, 0))]
	g.player.walk(pts)
	var squashed := false
	for i in 20:
		await frames(1)
		squashed = squashed or g.player.sprite.scale.x > 1.01
	check(squashed, "walk bob squashes on landing")
	main.queue_free()
	await frames(2)


func test_profile_and_looks_reach_every_prompt() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	var p: Dictionary = GameState.world.player
	p["pronouns"] = "they/them"
	p["nicknames"] = "Sammy, Captain"
	p["about"] = "I grow tomatoes and I'm learning the cello."
	PlayerLook.set_field("real", "looks", "a tall kid in a yellow raincoat")
	PlayerLook.set_field("dark", "looks", "a traveler in a midnight cape")
	GameState.add_dream("Play the cello at the town fair")
	var ctx := Conversation.new().base_context(GameState.get_character(id))
	ctx["user_text"] = "hi"
	var sys := str(PromptBuilder.build_messages(ctx)[0].content)
	for bit in ["they/them", "Sammy, Captain", "learning the cello", "midnight cape", "Dream World Me", "cello at the town fair"]:
		check(sys.contains(bit), "prompt mentions '%s'" % bit)
	check(not sys.contains("yellow raincoat"), "prompt describes the worn realm appearance")
	p["share_dreams"] = false
	ctx = Conversation.new().base_context(GameState.get_character(id))
	ctx["user_text"] = "hi"
	check(not str(PromptBuilder.build_messages(ctx)[0].content).contains("town fair"), "dreams can be kept private")
	# Nicknames show up in what friends call you.
	var names := {}
	for i in 60:
		names[GameState.call_name()] = true
	check(names.has("Sammy") or names.has("Captain"), "friends use nicknames now and then")


func test_voices_for_everyone() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	var v := Voice.of_character(GameState.get_character(id))
	eq(v.sound, "chirp", "Mochi has her own blip")
	check(Voice.stream("chirp") != Voice.stream("blip"), "different sounds")
	check(Voice.stream("low") is AudioStreamWAV, "synthesized")
	GameState.world.player["voice"] = {"sound": "bell", "pitch": 1.4, "speed": 1.5}
	eq(Voice.of_player().sound, "bell")
	var box: Control = preload("res://scripts/ui/dialogue_box.gd").new()
	tree.root.add_child(box)
	await frames(1)
	box.player_voice = Voice.of_player()
	box.open("Mochi", {}, v)
	eq(box.voice.sound, "chirp")
	box.show_player_line("hello there friend", "happy")
	check(box._you_typing, "your line types out in your voice")
	box.queue_free()


func test_old_world_upgrade_snapshots_first_and_keeps_a_painted_avatar() -> void:
	fresh_save_root()
	SaveManager.new_slot("Old")
	StarterContent.create_world("Old", "Sam")
	var cid := StarterContent.create_mochi()
	# Turn it back into a version-1 world with a hand-painted avatar.
	var w: Dictionary = JsonUtil.read_json(SaveManager.world_path(), {})
	w["version"] = 1
	w.player.erase("forms")
	w.player.erase("form")
	var painted := SpriteFactory.player(Color("#33cc66"))
	JsonUtil.ensure_dir(SaveManager.abs_path("player"))
	painted.save_png(SaveManager.abs_path("player/avatar.png"))
	w.player["avatar"] = "player/avatar.png"
	JsonUtil.write_json(SaveManager.world_path(), w)
	var c: Dictionary = JsonUtil.read_json(SaveManager.character_dir(cid).path_join("character.json"), {})
	c.erase("liked_tags")
	c.erase("disliked_tags")
	JsonUtil.write_json(SaveManager.character_dir(cid).path_join("character.json"), c)
	DirAccess.remove_absolute(SaveManager.abs_path("inventory.json"))
	var before_bytes := FileAccess.get_file_as_bytes(SaveManager.abs_path("player/avatar.png"))
	GameState.load_world()
	var snaps := SlotArchive.backups(SaveManager.slot_id).filter(func(b): return b.kind == "pre_migration")
	eq(snaps.size(), 1, "a snapshot was taken before upgrading")
	var inside := SlotArchive.read_zip_file(str(snaps[0].path), "world.json").get_string_from_utf8()
	check(inside.contains("\"version\": 1") or inside.contains("\"version\":1"), "the snapshot holds the old version")
	eq(int(SaveManager.load_world().version), Defaults.WORLD_VERSION)
	eq(PlayerLook.form_data("real").mode, "custom", "a painted avatar stays your Real Me")
	eq(PlayerLook.face_rel("real", "neutral"), "player/avatar.png", "same file, not moved")
	eq(FileAccess.get_file_as_bytes(SaveManager.abs_path("player/avatar.png")), before_bytes, "and not changed")
	eq(PlayerLook.form_data("dark").mode, "doll", "Dream World Me arrives as a doll")
	check(GameState.get_character(cid).liked_tags.has("tea"), "liked tags from the Likes text: %s" % str(GameState.get_character(cid).liked_tags))
	check(GameState.inventory.stacks.size() > 0, "starter bag")
	# Second load: nothing more to do.
	GameState.load_world()
	eq(SlotArchive.backups(SaveManager.slot_id).filter(func(b): return b.kind == "pre_migration").size(), 1, "migrates once")


func test_default_avatar_becomes_the_matching_doll() -> void:
	fresh_save_root()
	SaveManager.new_slot("Old")
	StarterContent.create_world("Old", "Sam")
	var w: Dictionary = JsonUtil.read_json(SaveManager.world_path(), {})
	w["version"] = 1
	w.player.erase("forms")
	SpriteFactory.player().save_png(SaveManager.abs_path("player/avatar.png"))
	w.player["avatar"] = "player/avatar.png"
	JsonUtil.write_json(SaveManager.world_path(), w)
	check(WorldMigration.is_default_avatar(SaveManager.abs_path("player/avatar.png")))
	GameState.load_world()
	eq(PlayerLook.form_data("real").mode, "doll", "the untouched default is now the doll")
	eq(PlayerLook.form_data("real").doll, Doll.preset("cozy"), "the cozy hoodie preset, same look")
