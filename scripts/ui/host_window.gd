extends PanelContainer
## host.bat's little window (Polox without the game, just Phone Link): the
## address to open on the phone (big, with a QR code), the PIN with its
## countdown, and what the phone is doing. The same lines go to the console.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const QrCode := preload("res://scripts/phone/qr_code.gd")
const Pairing := preload("res://scripts/phone/pairing.gd")

var server: Node                 # phone_server.gd
var _url: Label
var _mode: Label
var _pin: Label
var _pin_left: Label
var _status: Label
var _unlock: Button
var _qr: TextureRect
var _qr_for := ""
var _t := 0.0
var _printed_pin := ""
var _printed_url := ""
var _words: Label


func setup(srv: Node) -> void:
	server = srv
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.BG, ThemeBuilder.BG, 0, 0, 18))
	var v := UiKit.vbox(10)
	add_child(v)
	v.add_child(UiKit.label("Polox Phone Link", 32, ThemeBuilder.YELLOW))
	_mode = UiKit.para("", 16, ThemeBuilder.MUTED)
	v.add_child(_mode)
	v.add_child(UiKit.label("On your phone (same Wi-Fi), open:", 18, ThemeBuilder.CREAM))
	_url = UiKit.label("", 26, ThemeBuilder.YELLOW)
	_url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(_url)
	_qr = TextureRect.new()
	_qr.custom_minimum_size = Vector2(170, 170)
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.add_child(_qr)
	v.add_child(UiKit.label("PIN", 18, ThemeBuilder.CREAM))
	_pin = UiKit.label("", 56, ThemeBuilder.YELLOW)
	v.add_child(_pin)
	_pin_left = UiKit.label("", 16, ThemeBuilder.MUTED)
	v.add_child(_pin_left)
	_unlock = UiKit.button("Unlock pairing", func():
		server.pairing.unlock()
		refresh(), 220)
	_unlock.visible = false
	v.add_child(_unlock)
	_status = UiKit.para("", 18, ThemeBuilder.CREAM)
	v.add_child(_status)
	_words = UiKit.para("", 18, ThemeBuilder.YELLOW)
	v.add_child(_words)
	v.add_child(UiKit.para("Keep this window open while you play on the phone. Close it to switch Phone Link off.", 14, ThemeBuilder.MUTED))
	server.state_changed.connect(refresh)
	refresh()


## What the window shows, as text (also what the console gets and tests read).
func pin_text() -> String:
	if server.pairing.paused:
		return "paused"
	return Pairing.grouped(str(server.pairing.code))


func refresh() -> void:
	if server == null or _url == null:
		return
	var url: String = server.canonical_url()
	_url.text = url if url != "" else "(no network address found)"
	var extra: String = server.ts_url()
	_mode.text = "%s  •  listening on %s%s" % [server.mode_text(), server.bind_text(), ("\nAway from home (Tailscale on the phone): " + extra) if extra != "" and extra != url else ""]
	if url != _qr_for:
		_qr_for = url
		var q: RefCounted = QrCode.encode(url) if url != "" else null
		_qr.texture = ImageTexture.create_from_image(q.to_image(5)) if q else null
	var paused: bool = server.pairing.paused
	_pin.text = "Paused" if paused else pin_text()
	_unlock.visible = paused
	_tick()
	var lc: Dictionary = server.last_contact
	var sess: Dictionary = server.phone_session
	if not sess.is_empty():
		_status.text = "📱 Phone playing %s" % str(sess.get("name", ""))
	elif not lc.is_empty():
		_status.text = "📱 Phone connected (%s)" % (str(lc.get("via", "")) if str(lc.get("via", "")) != "" else str(lc.ip))
	else:
		_status.text = "○ Waiting for your phone..."
	_words.text = words_text()
	_words.visible = _words.text != ""
	_print_changes(url)


## After a pairing: the check words (or that an older phone paired without them).
func words_text() -> String:
	var phrase := str(server.get("last_pair_phrase")) if server.get("last_pair_phrase") != null else ""
	if phrase != "":
		return "Check these words match your phone: " + phrase
	if server.get("last_pair_legacy") == true and str(server.get("last_pair_device")) != "":
		return "⚠ %s paired the old way (no check words): update Polox on it." % str(server.get("last_pair_device"))
	return ""


func _tick() -> void:
	if server.pairing.paused:
		_pin_left.text = "Too many wrong PINs: pairing is paused until you unlock it."
		return
	var left: int = server.pairing.code_seconds_left()
	_pin_left.text = "new PIN in %d:%02d (and after each pairing)" % [left / 60, left % 60]


func _print_changes(url: String) -> void:
	if url != _printed_url:
		_printed_url = url
		print("[host] On your phone (same Wi-Fi), open: %s" % url)
	var p := pin_text()
	if p != _printed_pin and p != "":
		_printed_pin = p
		print("[host] PIN: %s" % p if p != "paused" else "[host] Pairing paused after too many wrong PINs: press Unlock pairing in the window.")


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.5 and server:
		_t = 0.0
		_tick()
		if pin_text() != _printed_pin:
			refresh()
