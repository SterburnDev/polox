extends Node
## Per-slot autosave: rolling zip snapshots on a timer, on room change and on
## quit (as the slot's card settings say), a cover screenshot for the Worlds
## menu now and then, and playtime bookkeeping. Game files themselves are
## written the moment they change; snapshots are the "go back in time" net.

signal saved(kind: String)

const Slots := preload("res://scripts/core/slots.gd")
const SlotArchive := preload("res://scripts/core/slot_archive.gd")

const COVER_EVERY := 120.0
const TOUCH_EVERY := 30.0
## Going to the background takes a snapshot at most this often (closing the game always does).
const BACKGROUND_SNAPSHOT_EVERY := 300.0
const COVER_SIZE := Vector2i(480, 270)

var main: Node
var _snapshot_in := 0.0
var _cover_in := 3.0
var _touch_in := TOUCH_EVERY
var _played := 0.0
var _capturing := false
var _slot := ""                   # the slot this session's playtime belongs to
var _cached: Dictionary = {}      # slot.json autosave settings (re-read every TOUCH_EVERY)
var _last_flush_snapshot := -1.0e9
## A snapshot zipping on a worker thread: {task, slot, path, kind, result}. Zipping the whole world
## on the main thread stalled every walk through a door (a quarter second on a fast PC).
var _bg: Dictionary = {}
var _bg_task := -1


func setup(main_node: Node) -> void:
	main = main_node


func _settings() -> Dictionary:
	if _cached.is_empty():
		_cached = Slots.meta(SaveManager.slot_id).get("autosave", Slots.defaults().autosave) if SaveManager.slot_id != "" else Slots.defaults().autosave
	return _cached


func on_game_started() -> void:
	_commit_playtime()
	_slot = SaveManager.slot_id
	_cached = {}
	_snapshot_in = float(_settings().get("interval_min", 10)) * 60.0
	_cover_in = 3.0
	_played = 0.0
	Slots.touch(_slot)


func _process(delta: float) -> void:
	if _bg_task >= 0 and WorkerThreadPool.is_task_completed(_bg_task):
		finish_background()
	if main.game == null:
		return
	_played += delta
	_touch_in -= delta
	if _touch_in <= 0.0:
		_touch_in = TOUCH_EVERY
		_cached = {}  # pick up card edits
		_commit_playtime()
	_cover_in -= delta
	if _cover_in <= 0.0:
		_cover_in = COVER_EVERY
		capture_cover()
	var s := _settings()
	if bool(s.get("enabled", true)):
		_snapshot_in -= delta
		if _snapshot_in <= 0.0:
			_snapshot_in = maxf(1.0, float(s.get("interval_min", 10))) * 60.0
			snapshot_background("auto")


func _commit_playtime() -> void:
	if _slot != "" and _played > 0.0 and Slots.exists(_slot):
		Slots.touch(_slot, _played)
	_played = 0.0


## Zips the active world (and prunes old automatic snapshots).
func snapshot(kind: String) -> String:
	if SaveManager.slot_id == "":
		return ""
	finish_background()
	if main.game:
		main.game.flush_all()
	var path := SlotArchive.snapshot(SaveManager.slot_id, kind)
	if path != "":
		SlotArchive.prune(SaveManager.slot_id, int(_settings().get("keep", 10)))
		saved.emit(kind)
	return path


## The same snapshot with the zipping on a worker thread (room changes and the timer). The game's
## files are written as .tmp then renamed, so the zip only ever reads whole files. One at a time:
## a request while one is still zipping is skipped (the next door or the timer takes it).
func snapshot_background(kind: String) -> void:
	if SaveManager.slot_id == "" or not _bg.is_empty():
		return
	if main.game:
		main.game.flush_all()
	var slot := SaveManager.slot_id
	var path := SlotArchive.snapshot_path(slot, kind)
	if path == "":
		return
	# Every key exists before the task starts; the worker only overwrites "result", and the main thread
	# reads the job only once the task is done.
	var job := {"slot": slot, "path": path, "kind": kind, "result": false}
	var folder := Slots.dir(slot)
	_bg = job
	_bg_task = WorkerThreadPool.add_task(func(): job.result = SlotArchive.zip_folder(folder, path), false, "Polox snapshot")


## Waits for a background snapshot (if any), then prunes and announces it on the main thread.
func finish_background() -> void:
	if _bg.is_empty():
		return
	var job := _bg
	_bg = {}
	WorkerThreadPool.wait_for_task_completion(_bg_task)
	_bg_task = -1
	if bool(job.result) and Slots.exists(str(job.slot)):
		SlotArchive.prune(str(job.slot), int(_settings().get("keep", 10)) if str(job.slot) == SaveManager.slot_id else 10)
		saved.emit(str(job.kind))


func _exit_tree() -> void:
	finish_background()


## The player pressed Save / Quick-save in the Worlds menu or with F5.
func save_now(quick: bool = false) -> void:
	if main.game == null:
		return
	main.game.flush_all()
	_commit_playtime()
	await capture_cover()
	var zip := snapshot("quick" if quick else "manual")
	GameState.notify("Saved ✓" if zip != "" else "Saved (snapshot failed: disk full?)")


func on_room_changed() -> void:
	if bool(_settings().get("on_room_change", true)):
		snapshot_background("auto")
	_cover_in = 2.0


## Window close / app pause: flush is already done; take the quit snapshot. Closing: right away (it
## must be done before Polox ends). Going to the background (if the last one was a while ago): zipped on
## a worker thread, since a big world took seconds exactly when Android was putting the app away; a zip
## cut short there leaves only a ".part" file, never a broken backup.
func on_flush(closing: bool = false) -> void:
	_commit_playtime()
	var now := Time.get_ticks_msec() / 1000.0
	if main.game and bool(_settings().get("on_quit", true)) and (closing or now - _last_flush_snapshot >= BACKGROUND_SNAPSHOT_EVERY):
		_last_flush_snapshot = now
		if closing:
			snapshot("auto")
		else:
			snapshot_background("auto")


func on_game_ending() -> void:
	finish_background()
	_commit_playtime()
	_slot = ""


## A small screenshot of the room without the UI, for the slot card.
func capture_cover() -> void:
	# Automatic GPU readback is unnecessary during phone play and can stall or
	# crash device drivers. Saves/snapshots still run; retain the existing cover.
	if OS.has_feature("android"):
		return
	if _capturing or main.game == null or SaveManager.slot_id == "" or DisplayServer.get_name() == "headless":
		return
	if not main.panels.is_empty() or main.game._transitioning:
		return
	if str(Slots.meta(SaveManager.slot_id).get("cover", "auto")) == "custom":
		return
	_capturing = true
	var layers: Array = [main.ui.get_parent(), main.toast_layer()]
	for l in layers:
		l.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := main.get_viewport().get_texture().get_image()
	for l in layers:
		l.visible = true
	_capturing = false
	if img == null or img.is_empty() or SaveManager.slot_id == "":
		return
	var scale := minf(float(COVER_SIZE.x) / img.get_width(), float(COVER_SIZE.y) / img.get_height())
	img.resize(maxi(1, roundi(img.get_width() * scale)), maxi(1, roundi(img.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	img.save_png(Slots.dir(SaveManager.slot_id).path_join("cover.png"))
	SaveManager.forget_texture(Slots.dir(SaveManager.slot_id).path_join("cover.png"))
