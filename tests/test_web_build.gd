extends "res://tests/test_case.gd"
## The phone (Web) build, as found by trying it in a browser at phone size:
## symbols and emoji need our own pixel font there, a fresh start mustn't
## leave an empty world behind, built-in templates mustn't sync (every copy
## stamps its own), and every screen has to fit a phone either way up.

const SymbolFont := preload("res://scripts/ui/symbol_font.gd")
const SyncFiles := preload("res://scripts/phone/sync_files.gd")
const Slots := preload("res://scripts/core/slots.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const TemplateFactory := preload("res://scripts/world/template_factory.gd")
const WorldMenu := preload("res://scripts/world/world_menu.gd")

var main: Node


## Every non-ASCII character in the game's own text: either the game font
## has it, or the pixel symbols do (the browser has no other fonts).
func test_every_symbol_has_a_glyph() -> void:
	var base: Font = ThemeDB.fallback_font
	var pixel := SymbolFont.font()
	var missing := {}
	var files := PackedStringArray()
	_scripts("res://scripts", files)
	check(files.size() > 100, "scanned the scripts")
	for f in files:
		for line in FileAccess.get_file_as_string(f).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for i in line.length():
				var cp := line.unicode_at(i)
				if cp < 0x80 or base.has_char(cp) or pixel.has_char(cp):
					continue
				missing[line[i]] = f.get_file()
	eq(missing, {}, "symbols with no glyph on a phone")
	# Unknown emoji from an AI are dropped there instead of showing boxes.
	SymbolFont.install()
	check(SymbolFont.active())
	eq(SymbolFont.displayable("hi 🥺 ♥ ✓"), "hi  ♥ ✓")
	var fb: Array[Font] = []
	fb.assign(base.fallbacks.filter(func(x): return x != pixel))
	base.fallbacks = fb
	check(not SymbolFont.active())
	eq(SymbolFont.displayable("hi 🥺"), "hi 🥺", "on a PC the system draws them")


func _scripts(dir: String, out: PackedStringArray) -> void:
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))


func test_a_fresh_start_leaves_no_empty_world() -> void:
	fresh_save_root()
	TemplateFactory.ensure_builtin()   # what the game does on every start
	eq(Slots.ids(), PackedStringArray(), "building the templates made no world")
	check(not GameState.has_world(), "the title says Begin")
	# A leftover empty folder (from before the fix) can't hide a real world.
	var root := fresh_save_root()
	StarterContent.create_world("Real", "Sam")
	var real := SaveManager.slot_id
	SaveManager.new_slot("Empty")
	SaveManager.set_root(root)
	eq(SaveManager.slot_id, real, "the world with a world.json is picked")
	check(GameState.has_world(), "so the title offers Continue")


func test_builtin_templates_stay_off_the_sync() -> void:
	var slots := PackedStringArray(["w"])
	check(not SyncFiles.allowed("library/templates/cozy_room/template.json", slots), "built-in: each side makes its own")
	check(not SyncFiles.allowed("library/templates/garden/thumb.png", slots))
	check(SyncFiles.allowed("library/templates/my_cabin/template.json", slots), "yours still sync")
	check(SyncFiles.allowed("library/tilesets/cozy_home/tileset.json", slots))


func test_every_screen_fits_a_phone() -> void:
	var before := tree.root.size
	var scale_before := tree.root.content_scale_factor
	var min_before := tree.root.min_size
	tree.root.min_size = Vector2i.ZERO   # a desktop start earlier set 960 x 600, which would clamp a phone size
	for size in [Vector2i(390, 844), Vector2i(844, 390)]:
		fresh_save_root()
		GameState.settings["touch_ui"] = "on"
		AIClient.configure({"preset": "mock"})
		tree.root.size = size
		eq(tree.root.size, size, "the window really is phone-sized")
		main = load("res://scenes/main.tscn").instantiate()
		tree.root.add_child(main)
		await frames(2)
		main.begin_new_world()
		await frames(3)
		var g: Node = main.game
		var view: Vector2 = main.ui.get_viewport_rect().size
		var screens := {
			"menu": WorldMenu.make(g), "bag": WorldMenu.bag(g), "me": WorldMenu.sheet(g, 0),
			"looks": WorldMenu.sheet(g, 1), "gear": WorldMenu.sheet(g, 2), "workshop": WorldMenu.workshop(g),
			"dreams": load("res://scripts/ui/dreams_board.gd").new(), "memory": load("res://scripts/ui/memory_book.gd").new(),
			"friends": WorldMenu.friends(g), "rooms": WorldMenu.room_list(g),
			"bible": load("res://scripts/ui/world_bible_editor.gd").new(), "chat log": load("res://scripts/ui/log_viewer.gd").new(),
			"settings": load("res://scripts/ui/settings_screen.gd").new(), "help": load("res://scripts/ui/help_panel.gd").new(),
			"worlds": load("res://scripts/ui/save_menu.gd").new(),
		}
		for key in screens:
			var p: Control = screens[key]
			if "main" in p:
				p.set("main", main)
			main.open_panel(p)
			await frames(3)
			await tree.create_timer(0.3).timeout   # (after it has slid up: Phase 35)
			var r: Rect2 = (p.get("panel") as Control).get_global_rect()
			var where := "%s at %s" % [key, size]
			check(r.position.x >= -0.5 and r.end.x <= view.x + 0.5 and r.position.y >= -0.5 and r.end.y <= view.y + 0.5, "%s: the panel (and its Close) is on screen: %s" % [where, r])
			var body: Control = p.get("body")
			var room: float = (p.get("_hscroll") as Control).size.x
			check(body.get_combined_minimum_size().x <= room + 0.5, "%s: nothing needs sliding sideways (%d > %d)" % [where, int(body.get_combined_minimum_size().x), int(room)])
			p.queue_free()
			await frames(1)
		# Worlds with several worlds, in both looks (the list rows were the widest thing).
		var MenuLook: GDScript = load("res://scripts/ui/save_menu_look.gd")
		Slots.create("Second world")
		Slots.create("Third world")
		var look: Dictionary = MenuLook.prefs()
		for layout in ["grid", "list"]:
			look["layout"] = layout
			MenuLook.save_prefs(look)
			var w: Control = load("res://scripts/ui/save_menu.gd").new()
			main.open_panel(w)
			await frames(3)
			var room: float = (w.get("_hscroll") as Control).size.x
			check((w.get("body") as Control).get_combined_minimum_size().x <= room + 0.5, "worlds (%s, 3 worlds) at %s fits" % [layout, size])
			w.queue_free()
			await frames(1)
		look["layout"] = "grid"
		MenuLook.save_prefs(look)
		# Build mode is its own layout (docks, not a panel).
		g.build.enter()
		await frames(4)
		var off := []
		for c in (g.build.shell as Control).find_children("*", "Control", true, false):
			if (c is Button or c is Label or c is LineEdit) and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().end.x > view.x + 1.0 and not _in_scroll(c, g.build.shell):
				off.append(str(c.get("text")))
		eq(off, [], "build mode at %s: everything on screen" % size)
		g.build.exit()
		await frames(2)
		main.queue_free()
		await frames(2)
	tree.root.min_size = min_before
	tree.root.size = before
	tree.root.content_scale_factor = scale_before   # (main scaled the window for a phone)
	GameState.settings["touch_ui"] = "auto"


static func _in_scroll(c: Node, stop: Node) -> bool:
	var p := c.get_parent()
	while p and p != stop:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false
