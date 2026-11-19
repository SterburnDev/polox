extends "res://tests/test_case.gd"
## Phase 36, more soul: one art direction (a palette per world that follows you, every widget themed, one type
## scale), writing with a voice (the main screens' words cut by more than half, each friend sounding like
## themselves), a small sound palette (a soft click, footsteps in both worlds, four motifs), fewer and better
## features (a shorter menu, developer settings under Advanced), and the signature moments (your street, the
## fountain, coming home after a battle; the first look at your home is in test_animation).

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Voices := preload("res://scripts/ai/voices.gd")
const MockBrain := preload("res://scripts/ai/mock_brain.gd")
const ReplyParser := preload("res://scripts/ai/reply_parser.gd")
const Synth := preload("res://scripts/core/synth.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const WorldMenu := preload("res://scripts/world/world_menu.gd")
const TitleCard := preload("res://scripts/ui/title_card.gd")
const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const Moment := preload("res://scripts/ui/moment.gd")

## Words of UI copy in the main screens at 1.20.0 (every string of two or more words in these scripts), before
## this phase's writing pass. The pass has to leave at most half.
const COPY_BASELINE := 2021
const COPY_FILES := [
	"res://scripts/world/world_menu.gd", "res://scripts/ui/settings_screen.gd", "res://scripts/ui/settings_game_tab.gd",
	"res://scripts/ui/settings_light_tab.gd", "res://scripts/ui/world_map_view.gd", "res://scripts/home/map_home_panel.gd",
	"res://scripts/home/tell_polox_panel.gd", "res://scripts/ui/story_panel.gd", "res://scripts/ui/memory_book.gd",
	"res://scripts/home/journal_panel.gd", "res://scripts/ui/world_sheet.gd", "res://scripts/ui/hud.gd", "res://scripts/ai/presets.gd",
	"res://scripts/ui/title_screen.gd", "res://scripts/world/decor_editor.gd",
]
## Controls that are pure layout (nothing to theme).
const LAYOUT := ["Control", "Container", "VBoxContainer", "HBoxContainer", "BoxContainer", "GridContainer", "FlowContainer", "HFlowContainer",
	"VFlowContainer", "MarginContainer", "CenterContainer", "ScrollContainer", "AspectRatioContainer", "SubViewportContainer",
	"TextureRect", "ColorRect", "NinePatchRect", "ReferenceRect", "Label", "RichTextLabel", "Panel", "PanelContainer", "TextureButton",
	"VideoStreamPlayer", "SplitContainer", "HSplitContainer", "VSplitContainer"]

var main: Node


func _boot() -> Node:
	fresh_save_root()
	AIClient.configure({"preset": "mock"})
	GameState.settings["reduce_motion"] = true
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	main.begin_new_world()
	await frames(3)
	return main.game


func _shutdown() -> void:
	GameState.settings["reduce_motion"] = false
	ThemeBuilder.set_world("dark", null)
	main._close_all_panels()
	main.queue_free()
	await frames(2)


func _home() -> void:
	HomeMapper.build_home({"address": "12 Example Lane, Testville", "home_type": "house", "floors": 2,
		"rooms": {"bedroom": 2, "bathroom": 1, "kitchen": 1, "living": 1}, "my_room": {"floor": 1}}, {}, "")


func _scripts(dir: String, out: PackedStringArray) -> void:
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))


func test_one_art_direction_palettes_follow_the_world() -> void:
	var g: Node = await _boot()
	var t: Theme = main.ui_theme
	var dark_panel: Color = (t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color
	_home()
	await g.dark.go_light()
	await frames(2)
	eq(ThemeBuilder.world, "light", "your real home's palette")
	var light_panel: Color = (t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color
	check(not light_panel.is_equal_approx(dark_panel), "the panels change with the world")
	check(light_panel.r > light_panel.b, "warm (tea-brown) in the Light World")
	check(dark_panel.b > dark_panel.r, "violet in the Dream World")
	g.open_bag()
	await frames(2)
	var sb: StyleBoxFlat = (main.panels.back() as Control).get("panel").get_theme_stylebox("panel") as StyleBoxFlat
	check(sb.bg_color.r > sb.bg_color.b, "a screen opened at home is warm too")
	main._close_all_panels()
	await g.dark.go_dark()
	await frames(2)
	eq(ThemeBuilder.world, "dark", "back in the Dream World")
	check((t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color.is_equal_approx(dark_panel), "and its palette")
	# The accents and text never change.
	for w in ["dark", "light", "deep"]:
		check(ThemeBuilder.PALETTES.has(w), "a %s palette" % w)
	eq(ThemeBuilder.CREAM, Color("#f3e9d2"))
	await _shutdown()


func test_every_widget_is_themed() -> void:
	var t := ThemeBuilder.build()
	var types := t.get_type_list()
	var files := PackedStringArray()
	_scripts("res://scripts", files)
	var used := {}
	var re := RegEx.create_from_string("\\b([A-Z][A-Za-z0-9]+)\\.new\\(\\)")
	for f in files:
		for m in re.search_all(FileAccess.get_file_as_string(f)):
			var cls := m.get_string(1)
			if ClassDB.class_exists(cls) and ClassDB.is_parent_class(cls, "Control"):
				used[cls] = f.get_file()
	check(used.has("Button") and used.has("CheckBox"), "scanned the widgets (%d kinds)" % used.size())
	var bare := {}
	for cls in used:
		if cls in LAYOUT:
			continue
		if not types.has(cls):
			bare[cls] = used[cls]
	eq(bare, {}, "widgets with no look of their own (they'd look like default Godot)")
	for kind in ["CheckButton", "ProgressBar", "SpinBox", "ColorPickerButton", "Window", "HSeparator", "TabBar"]:
		check(types.has(kind), "%s is themed" % kind)
	check(t.get_icon("grabber", "HSlider") != null and t.get_icon("checked", "CheckButton") != null, "our own knob and switch")


func test_one_type_scale() -> void:
	var files := PackedStringArray()
	_scripts("res://scripts", files)
	var over := RegEx.create_from_string("add_theme_font_size_override\\(\"(?:font_size|normal_font_size|bold_font_size)\",\\s*(\\d+)\\)")
	var kit := RegEx.create_from_string("UiKit\\.(?:label|para|title)\\(\"(?:[^\"\\\\]|\\\\.)*\",\\s*(\\d+)")
	var off := {}
	var seen := 0
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		for re in [over, kit]:
			for m in (re as RegEx).search_all(text):
				var size := int(m.get_string(1))
				seen += 1
				if size != 0 and not size in ThemeBuilder.TYPE_SCALE:
					off["%s: %d" % [f.get_file(), size]] = true
	check(seen > 200, "scanned the text sizes (%d)" % seen)
	eq(off, {}, "sizes off the type scale")


## Words of UI copy: string literals of two or more words, outside comments.
static func copy_words(path: String) -> int:
	var lit := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var word := RegEx.create_from_string("[A-Za-z]")
	var holder := RegEx.create_from_string("%[-+0-9.]*[sdif]")   # (%s, %d... aren't words)
	var n := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		for m in lit.search_all(line):
			var t := m.get_string(1)
			if t.contains("res://") or t.contains("user://") or t.begins_with("#"):
				continue
			var count := 0
			for w in holder.sub(t.replace("\\n", " "), " ", true).split(" ", false):
				if word.search(w):
					count += 1
			if count >= 2:
				n += count
	return n


func test_ui_words_cut_by_half() -> void:
	var total := 0
	for f in COPY_FILES:
		total += copy_words(f)
	print("    (UI copy: %d words, from %d)" % [total, COPY_BASELINE])
	check(total * 2 <= COPY_BASELINE, "the main screens say it in half the words (%d of %d)" % [total, COPY_BASELINE])
	# The privacy promises still say exactly what's sent.
	var home := FileAccess.get_file_as_string("res://scripts/home/map_home_panel.gd")
	check(home.contains("OpenStreetMap") and home.contains("Nothing else"), "Map my streets still says what it sends")


func test_each_friend_sounds_like_themselves() -> void:
	var vibes: Array = load("res://scripts/ui/onboarding.gd").VIBES
	var voices := {}
	for v in vibes:
		voices[Voices.of({"personality": v[1], "speech_style": v[2]})] = true
	eq(voices.size(), 4, "the four kinds of friend have four voices")
	eq(Voices.of({"visitor": true, "speech_style": "warm, a little mysterious, short sentences"}), "traveler", "travellers have their own")
	eq(Voices.of({"name": "Mochi", "personality": "Gentle, curious and a little dramatic about snacks."}), "gentle")
	# No line is shared between voices, for any kind of moment.
	for kind in ["hello", "bye", "sad", "happy", "question", "flavor", "npc", "reply"]:
		var owner := {}
		for v in Voices.VOICES:
			for l in Voices.lines(v, kind):
				check(not owner.has(l) or owner[l] == v, "\"%s\" is %s's and %s's" % [l, owner.get(l, ""), v])
				owner[l] = v
	for v in Voices.VOICES:
		for kind in ["gift_love", "gift_meh", "gift_nice"]:
			for l in Voices.lines(v, kind):
				check(str(l).contains("{gift}"), "%s thanks you for the gift by name: %s" % [v, l])
	# In Mock mode a greeting sounds different per friend.
	var brain := MockBrain.new(5)
	var emo := PackedStringArray(["neutral", "happy", "sad", "surprised", "thinking", "embarrassed"])
	var heard := {}
	for v in vibes:
		var c := {"name": "Friend", "personality": v[1], "speech_style": v[2]}
		var said := ReplyParser.joined_text(ReplyParser.parse(brain.respond({"mode": "chat", "character": c, "user_text": "hi", "emotions": emo}), emo).segments)
		heard[said] = true
		check(Voices.lines(Voices.of(c), "hello").any(func(l): return said.begins_with(str(l).split("{")[0].substr(0, 8))), "%s greets in their voice: %s" % [Voices.of(c), said])
	eq(heard.size(), 4, "four different hellos")


func test_a_small_sound_palette() -> void:
	var g: Node = await _boot()
	for name in ["tick", "step_soft", "step_wood", "step_stone", "step_grass", "motif_title", "motif_home", "motif_dark", "motif_battle"]:
		check(Synth.get_sound(name) != null, name)
	var datas := {}
	for name in ["motif_title", "motif_home", "motif_dark", "motif_battle"]:
		var s: AudioStreamWAV = Synth.get_sound(name)
		var secs := s.data.size() / 2.0 / Synth.RATE
		check(secs > 0.8 and secs < 3.0, "%s is short (%.1f s)" % [name, secs])
		var peak := 0
		for i in range(0, s.data.size(), 2):
			var v := s.data[i] | (s.data[i + 1] << 8)
			if v >= 32768:
				v -= 65536
			peak = maxi(peak, absi(v))
		var level := peak / 32767.0
		check(level > 0.08 and level < 0.5, "%s sits at a gentle level (%.2f)" % [name, level])
		datas[s.data] = true
	eq(datas.size(), 4, "four different motifs")
	# A soft click under every button (and none when it's off).
	var b := UiKit.button("Hi")
	main.add_child(b)
	Synth.history.clear()
	b.pressed.emit()
	check(Synth.history.has("tick"), "buttons click softly")
	GameState.settings["ui_sounds"] = false
	Synth.history.clear()
	b.pressed.emit()
	check(not Synth.history.has("tick"), "not with Button clicks off")
	GameState.settings["ui_sounds"] = true
	b.queue_free()
	# Footsteps in the Dream World too.
	Synth.history.clear()
	g.player.anim.on_step.call("walk")
	check(Synth.history.has("step_soft"), "soft steps in the Dream World")
	# Motifs where they belong: a battle starts with one.
	Synth.history.clear()
	await _shutdown()


func test_fewer_better_features() -> void:
	var g: Node = await _boot()
	var menu: Control = WorldMenu.make(g)
	main.open_panel(menu)
	await frames(2)
	var labels: Array = menu.find_children("*", "Button", true, false).map(func(b): return str(b.text))
	check(labels.size() <= 24, "a shorter menu (%d buttons)" % labels.size())
	for gone in ["Chat Log", "World Bible", "Battle Maker", "Item Workshop", "Open save folder"]:
		check(not labels.has(gone), "%s moved off the main menu" % gone)
	check(labels.has("More"), "...to More")
	main._close_all_panels()
	var more: Control = WorldMenu.more(g)
	main.open_panel(more)
	await frames(2)
	var more_labels: Array = more.find_children("*", "Button", true, false).map(func(b): return str(b.text))
	for there in ["Chat Log", "World Bible", "Battle Maker", "Item Workshop", "New friend", "How to play"]:
		check(more_labels.has(there), "%s is one tap further" % there)
	main._close_all_panels()
	# Settings > AI: the server, model and limits under Advanced (open by itself for a custom server).
	var s: Control = load("res://scripts/ui/settings_screen.gd").new()
	main.open_panel(s)
	await frames(3)
	var adv: Control = s.find_child("AiAdvanced", true, false)
	check(adv != null and not adv.visible, "developer settings tucked under Advanced")
	var server_row_visible := false
	for l in s.find_children("*", "Label", true, false):
		if str(l.text) == "Server address" and l.is_visible_in_tree():
			server_row_visible = true
	check(not server_row_visible, "no server address on the first look")
	(s.find_child("AiAdvancedToggle", true, false) as Button).pressed.emit()
	await frames(1)
	check(adv.visible, "one tap shows them")
	main._close_all_panels()
	# A key field nothing used is gone (Street View is a link in My home > Sources instead).
	var s2: Control = load("res://scripts/ui/settings_screen.gd").new()
	main.open_panel(s2)
	await frames(3)
	check(s2.find_child("MapsKey", true, false) == null, "no Google Maps key field that does nothing")
	main._close_all_panels()
	# The skip hint never covers a button: top centre.
	var m: Control = Moment.begin(main)
	await frames(2)
	check(m.hint.get_global_rect().position.y < 200.0, "Tap to skip sits at the top")
	m.finish()
	await _shutdown()


func test_signature_moments() -> void:
	var g: Node = await _boot()
	var sig: Node = g.signatures
	# The first trip through the fountain: once.
	_home()
	await g.dark.go_light()
	await frames(2)
	TitleCard.shown.clear()
	Synth.history.clear()
	await g.dark.go_dark()
	await frames(2)
	eq(sig.last, "first_fountain", "the first trip through the fountain is a moment")
	check(TitleCard.shown.has("The Dream World"), "with a title")
	check(Synth.history.has("motif_dark"), "and the Dream World's motif")
	sig.last = ""
	await g.dark.go_light()
	await frames(2)
	await g.dark.go_dark()
	await frames(2)
	check(sig.last != "first_fountain", "only the first time")
	# The first walk down your street: once (remembered in your private home folder).
	sig.last = ""
	await sig.first_street({"id": "lw_hood_1_1", "name": "Example Lane"})
	eq(sig.last, "first_street", "your street, the first time")
	check(TitleCard.shown.has("Example Lane"), "its name as the title")
	check(str(HomeStore.load_home().get("first_street", "")) != "", "remembered with your home")
	sig.last = ""
	await sig.first_street({"id": "lw_hood_1_1", "name": "Example Lane"})
	eq(sig.last, "", "not again")
	# Coming home after a battle: every time, short, a friend glad to see you.
	Synth.history.clear()
	await sig.home_after_battle({"outcome": "spared"})
	eq(sig.last, "after_battle")
	check(TitleCard.shown.has("Welcome back"), "welcome back")
	check(Synth.history.has("motif_home"), "the home motif")
	# Skippable with a tap (without Reduce motion it would take 1.8 s).
	GameState.settings["reduce_motion"] = false
	var t0 := Time.get_ticks_msec()
	var done := [false]
	var run := func():
		await sig.home_after_battle({"outcome": "won"})
		done[0] = true
	run.call()
	await frames(2)
	for c in main.find_children("*", "Control", true, false):
		if c.get_script() == Moment:
			c.skip()
	for i in 20:
		if done[0]:
			break
		await frames(1)
	check(done[0] and Time.get_ticks_msec() - t0 < 1200, "a tap skips it")
	await _shutdown()
