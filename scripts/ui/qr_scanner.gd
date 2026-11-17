extends Control
## The camera view for "Scan the QR code" in Polox for Android. The camera permission is asked
## for only when this opens (never at start-up). It shows the back camera, reads a frame a few
## times a second off the main thread (qr_decode.gd) and reports the first code it can read.
## Without a camera or the permission it says so plainly; the PIN keypad always works instead.
## Tags: [PAIRING]

signal found(text: String)
signal status(text: String)

const QrDecode := preload("res://scripts/phone/qr_decode.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

const EVERY_S := 0.35
const GRAY_SHADER := "shader_type canvas_item;\nvoid fragment() { float y = texture(TEXTURE, UV).r; COLOR = vec4(y, y, y, 1.0); }"

var feed: CameraFeed
var tex: CameraTexture
var view: TextureRect
var scanning := false
var frames_read := 0
var _t := 0.0
var _busy := false
var _stopped := false
var _task := -1             # the picture being read (a WorkerThreadPool task), -1 when none
var _job: Dictionary = {}   # where that reading puts its answer: {done, text}


func _ready() -> void:
	clip_contents = true
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	view = TextureRect.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRAY_SHADER
	mat.shader = sh
	view.material = mat   # the camera's brightness plane shows as gray, not red
	add_child(view)
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = ThemeBuilder.YELLOW
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)


func start() -> void:
	_stopped = false
	if OS.has_feature("android") and not "android.permission.CAMERA" in OS.get_granted_permissions():
		status.emit("Polox asks for the camera only to read the code on your PC.")
		if not get_tree().on_request_permissions_result.is_connected(_on_permission):
			get_tree().on_request_permissions_result.connect(_on_permission)
		if not OS.request_permission("android.permission.CAMERA"):
			return   # Android shows its question; _on_permission continues
	_open_camera()


func _on_permission(permission: String, granted: bool) -> void:
	if not permission.ends_with("CAMERA") or _stopped:
		return
	if granted:
		_open_camera()
	else:
		status.emit("No camera: type the PIN instead. (To scan later, allow the camera in Android Settings > Apps > Polox > Permissions.)")


func _open_camera() -> void:
	CameraServer.monitoring_feeds = true
	for _i in 30:   # the camera list arrives a moment after monitoring starts
		if CameraServer.get_feed_count() > 0 or not is_inside_tree():
			break
		await get_tree().process_frame
	if not is_inside_tree() or _stopped:
		return
	feed = pick_feed(CameraServer.feeds())
	if feed == null:
		status.emit("No camera found on this device. Type the PIN instead.")
		return
	_pick_format(feed)
	feed.feed_is_active = true
	tex = CameraTexture.new()
	tex.camera_feed_id = feed.get_id()
	tex.which_feed = CameraServer.FEED_Y_IMAGE   # brightness only (or the whole picture on RGB cameras)
	view.texture = tex
	scanning = true
	status.emit("Hold the phone straight in front of the PC's screen, with the whole code inside the frame.")


## The back camera when there is one, else the first.
static func pick_feed(feeds: Array) -> CameraFeed:
	for f in feeds:
		if (f as CameraFeed).get_position() == CameraFeed.FEED_BACK:
			return f
	return feeds[0] if not feeds.is_empty() else null


## A modest picture size is plenty for a code on a screen and quicker to read.
static func _pick_format(f: CameraFeed) -> void:
	var best := -1
	var best_score := 1 << 30
	var formats: Array = f.formats
	for i in formats.size():
		var d: Dictionary = formats[i]
		var w := int(d.get("width", 0))
		if w <= 0:
			continue
		var score := absi(w - 1280)
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		f.set_format(best, {})


func _process(delta: float) -> void:
	_collect()
	if not scanning or _busy or tex == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = EVERY_S
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	frames_read += 1
	_busy = true
	# The reading goes into a box this node looks in each frame (_collect), not back through a call
	# into this node: the scanner may be closed, and freed, while a picture is still being read.
	var job := {"done": false, "text": ""}
	_job = job
	_task = WorkerThreadPool.add_task(func() -> void:
		job["text"] = QrDecode.decode_image(img)
		job["done"] = true)


## Takes a finished reading from its box and hands its task back to the pool (a task that is never
## waited for is kept by the pool for good).
func _collect() -> void:
	if _task < 0 or not bool(_job.get("done", false)):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var text := str(_job.get("text", ""))
	_job = {}
	_decoded(text)


func _decoded(text: String) -> void:
	_busy = false
	if text != "" and scanning and not _stopped:
		scanning = false
		found.emit(text)


## After a code that wasn't Polox's: keep looking.
func resume() -> void:
	if tex != null and not _stopped:
		scanning = true


func stop() -> void:
	_stopped = true
	scanning = false
	if feed:
		feed.feed_is_active = false
	feed = null
	if view:
		view.texture = null
	tex = null


func _exit_tree() -> void:
	stop()
	# A picture still being read (a fraction of a second): waited for, so its task is handed back.
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_job = {}
		_busy = false
