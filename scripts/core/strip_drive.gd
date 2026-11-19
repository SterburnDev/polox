extends RefCounted
## The "fountain_strips" drive (debug_drives.gd): plays each Dream Gate animation and saves a
## strip of frames captured while it plays (--strip-dir=<folder>), for checking them by eye at PC
## and phone size: opening, idle, entering, transforming, returning, sealing. Never used in play.

const DarkWorlds := preload("res://scripts/world/dark_worlds.gd")
const Moment := preload("res://scripts/ui/moment.gd")

const FRAMES := 6
const IDLE_WAIT_MS := 20000   # the longest one animation may take before the drive moves on

var main: Node
var dir := ""


func _wait(seconds: float) -> void:
	await main.get_tree().create_timer(seconds).timeout


## Waits until the gate's animation is over (never longer than IDLE_WAIT_MS).
func _until_idle(g: Node) -> void:
	var end := Time.get_ticks_msec() + IDLE_WAIT_MS
	while is_instance_valid(g) and g.dark.busy and Time.get_ticks_msec() < end:
		await _wait(0.1)


func _grab(out: Array) -> void:
	await RenderingServer.frame_post_draw
	var img := main.get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 3, img.get_height() / 3, Image.INTERPOLATE_BILINEAR)
	out.append(img)


## Captures FRAMES pictures `every` seconds apart while the moment plays, then saves the strip.
func _capture(name: String, every: float) -> void:
	var shots: Array = []
	for i in FRAMES:
		if "--strip-debug" in OS.get_cmdline_user_args():
			var overlays: Array = main.toast_layer().get_children().filter(func(n): return n.get_script() == load("res://scripts/ui/fall_overlay.gd"))
			print("[strip-debug] %s %d moment=%s overlays=%d p=%s" % [name, Time.get_ticks_msec(), main.game.dark.last_moment, overlays.size(), str(overlays[0].progress) if not overlays.is_empty() else "-"])
		await _grab(shots)
		await _wait(every)
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var strip := Image.create(w * shots.size() + 4 * (shots.size() - 1), h, false, Image.FORMAT_RGBA8)
	strip.fill(Color("#120e24"))
	for i in shots.size():
		var s: Image = shots[i]
		s.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(s, Rect2i(0, 0, w, h), Vector2i(i * (w + 4), 0))
	strip.save_png(dir.path_join("strip_%s.png" % name))
	print("[strip] ", name)


## The morph's own frames, as the sprite shows them (the screen capture above is slower than the morph).
func _morph_strip(g: Node) -> void:
	var TransformFx: Script = load("res://scripts/characters/transform_fx.gd")
	var PlayerLook: Script = load("res://scripts/characters/player_look.gd")
	var a: Image = PlayerLook.base_image("real", "neutral")
	var b: Image = PlayerLook.base_image("dark", "neutral")
	var frames: Array = TransformFx.morph_frames(a, b)
	var w := a.get_width() * 4
	var h := a.get_height() * 4
	var strip := Image.create((w + 4) * (frames.size() + 2), h, false, Image.FORMAT_RGBA8)
	strip.fill(Color("#2e2552"))
	var all: Array = [a] + frames + [b]
	for i in all.size():
		var f: Image = (all[i] as Image).duplicate()
		f.convert(Image.FORMAT_RGBA8)
		f.resize(w, h, Image.INTERPOLATE_NEAREST)
		strip.blend_rect(f, Rect2i(0, 0, w, h), Vector2i(i * (w + 4), 0))
	strip.save_png(dir.path_join("strip_transform_frames.png"))


func run(main_node: Node) -> void:
	main = main_node
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--strip-dir="):
			dir = a.trim_prefix("--strip-dir=")
	DirAccess.make_dir_recursive_absolute(dir)
	main.begin_new_world()
	await _wait(0.6)
	var g: Node = main.game
	g.daylight.hour_override = 15.0
	g.daylight.apply()
	for n in main.ui.find_children("*", "", true, false):
		if n.get_script() and str(n.get_script().resource_path).ends_with("today_card.gd"):
			n.queue_free()
	var data: Dictionary = g.room.data
	var sp: Array = data.get("spawn", [6, 7])
	var f := DarkWorlds.place_fountain(data, Vector2i(int(sp[0]), int(sp[1]) - 2))
	SaveManager.save_room(data)
	g.rebuild_room()
	await _wait(0.4)
	f = g.room.find_object(str(f.id))
	g.player.position = g.room.cell_center(Vector2i(int(f.pos[0]), int(f.pos[2]) + 2))
	g.cam.snap_to_target()
	for c in main.toast_layer().get_children():
		if c.has_method("dismiss"):
			c.dismiss()
	# 1. Opening.
	g.dark.make_dark(f)
	await _capture("opening", 0.3)
	await _until_idle(g)
	# 2. Idle.
	await _capture("idle", 0.25)
	# 3. Entering (the fall, the landing) and 4. transforming (at its end).
	f = g.room.find_object(str(f.id))
	g.dark.enter(f)
	await _capture("entering", 0.33)
	var t0 := Time.get_ticks_msec()
	while g.dark.last_moment != "transforming" and g.dark.busy and Time.get_ticks_msec() - t0 < 6000:
		await _wait(0.02)
	await _capture("transforming", 0.05)
	_morph_strip(g)
	await _until_idle(g)
	await _wait(0.4)
	# 5. Returning.
	var back: Array = DarkWorlds.fountains(g.room.data)
	if not back.is_empty():
		g.dark.go_back(back[0])
		await _capture("returning", 0.33)
		await _until_idle(g)
	await _wait(0.4)
	# 6. Sealing.
	f = g.room.find_object(str(f.id))
	g.dark.seal(f)
	await _capture("sealing", 0.28)
	await _until_idle(g)
	print("[strip] done")
