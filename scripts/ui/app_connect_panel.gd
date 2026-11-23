extends "res://scripts/ui/screen_panel.gd"
## Polox for Android: "Connect to your PC". Explains first, then listens for the PC on the
## home network (or uses the last address, Tailscale, a typed address), then pairs with the
## PC's QR code (camera, asked for only then) or the PIN on a big keypad (one thumb is enough).
## Playing without the PC is always one tap away: the app keeps its own copy.
## Tags: [PAIRING]

signal connected

const AppLink := preload("res://scripts/phone/app_link.gd")
const QrScanner := preload("res://scripts/ui/qr_scanner.gd")
const ThemeBuilderC := preload("res://scripts/ui/theme_builder.gd")

var main: Node
var phone: Node                 # phone_mode.gd (app == true)
var first := false
var repair := false             # "Pair again": ask for the PIN even when this phone is paired
var step := ""
var target: Dictionary = {}     # the PC picked: {name, url, path}
var pin := ""
var device_name := "Android phone"
var pair_phrase := ""
var _pin_label: Label
var _pin_field: LineEdit   # the same PIN through Android's own number keyboard
var _pairing := false      # (one PIN at a time, from the keypad or the keyboard)
var _msg: Label
var _scanner: Control
var _search_id := 0


func setup_connect(main_node: Node, phone_mode: Node, first_start: bool = false, pair_again: bool = false) -> void:
	main = main_node
	phone = phone_mode
	first = first_start
	repair = pair_again
	setup("Connect to your PC", Vector2(820, 640))
	device_name = str(phone.link.link.get("device_name", "Android phone")) if phone.link else "Android phone"
	if phone.paired() or not first:
		show_step("search")   # (from Settings: straight to finding the PC)
	else:
		show_step("intro")


func _clear() -> void:
	if _scanner:
		_scanner.stop()
		_scanner = null
	for c in body.get_children():
		c.queue_free()   # (freed at the end of the frame: removing them at once hung the app going from the intro to the search)
	_msg = null
	_pin_field = null


func _message() -> Label:
	_msg = UiKit.para("", 20, ThemeBuilderC.YELLOW)
	body.add_child(_msg)
	return _msg


func say(text: String) -> void:
	if _msg:
		_msg.text = text


func show_step(s: String) -> void:
	_clear()
	step = s
	match s:
		"intro":
			_intro()
		"search":
			_search()
		"pin":
			_pin_step()
		"qr":
			_qr_step()
		"verify":
			_verify_step()
		"done":
			_done_step()


# --- 1. What happens ----------------------------------------------------------------------------

func _intro() -> void:
	body.add_child(UiKit.para("Polox plays on this phone by itself. Connect it to Polox on your PC to sync your worlds both ways and let your friends talk through the PC's AI (its key stays on the PC).", 22))
	body.add_child(UiKit.para("Polox will listen on your Wi-Fi for your PC, which announces only its name. Nothing is sent until you pick it. If Android asks about nearby devices or your local network, allow it so Polox can hear your PC.", 20, ThemeBuilderC.MUTED))
	body.add_child(UiKit.para("On the PC: Settings > Phone Link > switch it on.", 20, ThemeBuilderC.MUTED))
	var row := UiKit.flow_row(12)   # (wraps on an upright phone)
	row.add_child(UiKit.button("Play without the PC", func(): close(), 0))
	var go := UiKit.button("Look for my PC", func(): show_step("search"), 0)
	row.add_child(go)
	body.add_child(UiKit.spacer(true))
	body.add_child(row)
	go.call_deferred("grab_focus")


# --- 2. Finding the PC -------------------------------------------------------------------------

func _search() -> void:
	_search_id += 1
	var my_id := _search_id
	body.add_child(UiKit.para("Looking for Polox on your Wi-Fi...", 22))
	var list := UiKit.vbox(10)
	body.add_child(list)
	_message()
	var row := UiKit.flow_row(10)
	row.add_child(UiKit.button("Scan the QR code", func(): show_step("qr"), 240))
	row.add_child(UiKit.button("Search again", func(): show_step("search"), 200))
	row.add_child(UiKit.button("Type the address", func(): _typed_address(list), 230))
	body.add_child(row)
	var r: Dictionary = await phone.link.find_pc(3.0)
	if not is_inside_tree() or my_id != _search_id or step != "search":
		return
	for c in list.get_children():
		c.queue_free()
	var shown := {}
	for h in r.get("heard", []):
		shown[str(h.url)] = true
		list.add_child(_pc_button("💻 %s" % str(h.name), str(h.url), "home", str(h.name)))
	if r.ok and not shown.has(str(r.url)):
		list.add_child(_pc_button("💻 %s (%s)" % [str(r.name), AppLink.path_label(str(r.path))], str(r.url), str(r.path), str(r.name)))
	if list.get_child_count() == 0:
		say("No PC found. Is Phone Link on, and is this phone on the same Wi-Fi? You can also scan the QR code or type the address shown on the PC (Settings > Phone Link).")
	elif not phone.paired() and list.get_child_count() == 1:
		# One PC answered and this phone isn't paired yet: straight to its PIN (Back returns here).
		(list.get_child(0) as Button).pressed.emit()
	elif phone.paired() and r.ok and not repair:
		# Already paired, and the PC answered: nothing to ask.
		phone.use_origin(str(r.url))
		phone.connection = r
		show_step("done")
	else:
		say("Tap your PC.")


func _pc_button(text: String, url: String, path: String, name: String) -> Button:
	var b := UiKit.button("%s   %s" % [text, url.trim_prefix("http://").trim_prefix("https://")], func():
		target = {"url": url, "path": path, "name": name}
		show_step("pin"))
	b.custom_minimum_size.y = 64
	return b


func _typed_address(list: VBoxContainer) -> void:
	var row := UiKit.hbox(10)
	var field := UiKit.line_edit("192.168.1.20:8765")
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	row.add_child(UiKit.button("Use", func():
		var url := normalize_address(field.text)
		if url == "":
			say("That doesn't look like an address on your home network or Tailscale (for example 192.168.1.20:8765).")
			return
		say("Checking %s..." % url)
		var r: Dictionary = await phone.link.probe(url)
		if not is_inside_tree():
			return
		if r.ok:
			target = {"url": url, "path": "typed", "name": str(r.name)}
			show_step("pin")
		else:
			say("No Polox at %s (%s)." % [url, r.error]), 120))
	list.add_child(row)
	field.call_deferred("grab_focus")


## "192.168.1.20:8765" or a full address -> "http://192.168.1.20:8765" ("" when not allowed).
static func normalize_address(text: String) -> String:
	var t := text.strip_edges().trim_suffix("/")
	if t == "":
		return ""
	if not "://" in t:
		t = "http://" + t
	if t.count(":") == 1:   # no port: Phone Link's usual one
		t += ":8765"
	return t if AppLink.url_allowed(t) else ""


# --- 3. The PIN -------------------------------------------------------------------------------

func _pin_step() -> void:
	pin = ""
	body.add_child(UiKit.para("Pair with %s: type the 6-digit PIN on your PC's Phone Link screen." % (str(target.name) if str(target.get("name", "")) != "" else "your PC"), 22))
	_pin_label = UiKit.label("", 46, ThemeBuilderC.YELLOW)
	_pin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_pin_label)
	_show_pin()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "OK"]:
		var key := str(k)
		var b := UiKit.button(key, func(): press_key(key), 110)
		b.custom_minimum_size.y = 64
		b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS   # a key counts when the finger lands (a tiny slide can't lose it)
		grid.add_child(b)
	body.add_child(grid)
	_pin_field = UiKit.line_edit("...or type it with your keyboard", "")
	_pin_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_pin_field.max_length = 12   # (stray characters are dropped and the digits kept to six: _on_pin_typed)
	_pin_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin_field.text_changed.connect(_on_pin_typed)
	body.add_child(_pin_field)
	var name_field := UiKit.line_edit("This phone's name", device_name)
	name_field.max_length = 40
	name_field.text_changed.connect(func(t): device_name = t.strip_edges() if t.strip_edges() != "" else "Android phone")
	body.add_child(UiKit.field_row("Phone's name", name_field, 170))
	_message()
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button("Back", func(): show_step("search"), 140))
	row.add_child(UiKit.button("Scan the QR code instead", func(): show_step("qr"), 300))
	body.add_child(row)


func _show_pin() -> void:
	if _pin_label:
		var shown := ""
		for i in 6:
			shown += (pin[i] if i < pin.length() else "–") + (" " if i < 5 else "")
		_pin_label.text = shown


## One key of the keypad (digits, ⌫, OK). Typing digits on a keyboard works too.
func press_key(k: String) -> void:
	if k == "⌫":
		pin = pin.left(maxi(0, pin.length() - 1))
	elif k == "OK":
		if pin.length() == 6:
			submit_pin()
		else:
			say("The PIN has 6 digits.")
	elif k.is_valid_int() and pin.length() < 6:
		pin += k
		if pin.length() == 6:
			submit_pin()
	_show_pin()


## The number field (Android's keyboard): only digits count; six pair by themselves.
func _on_pin_typed(t: String) -> void:
	var digits := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			digits += ch
	digits = digits.left(6)
	if digits != t and _pin_field:
		_pin_field.text = digits
		_pin_field.caret_column = digits.length()
	pin = digits
	_show_pin()
	if pin.length() == 6:
		submit_pin()


func _unhandled_key_input(event: InputEvent) -> void:
	if step != "pin" or not event is InputEventKey or not event.pressed:
		return
	if _pin_field and _pin_field.has_focus():
		return   # the field types for itself
	var e := event as InputEventKey
	if e.unicode >= 48 and e.unicode <= 57:
		press_key(char(e.unicode))
	elif e.keycode == KEY_BACKSPACE:
		press_key("⌫")
	elif e.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		press_key("OK")
	else:
		return
	get_viewport().set_input_as_handled()


func submit_pin() -> void:
	if _pairing:
		return
	_pairing = true
	say("Pairing...")
	var how := "typed" if str(target.get("path", "")) == "typed" else str(target.get("path", "home"))
	var r: Dictionary = await phone.pair_with(str(target.url), pin, device_name, how)
	_pairing = false
	if not is_inside_tree():
		return
	if r.ok:
		phone.link.link["device_name"] = device_name
		phone.link.save_link()
		_show_paired_step(r)
	else:
		pin = ""
		if _pin_field:
			_pin_field.text = ""
		_show_pin()
		say(pin_error(str(r.get("error", ""))))


func _show_paired_step(result: Dictionary) -> void:
	pair_phrase = str(result.get("phrase", ""))
	show_step("verify" if pair_phrase != "" else "done")


func _verify_step() -> void:
	title_label.text = "Check the words"
	body.add_child(UiKit.para("Check these words match your PC", 24, ThemeBuilderC.YELLOW))
	var words := UiKit.label(pair_phrase, 38, ThemeBuilderC.CREAM)
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(words)
	body.add_child(UiKit.para("The same three words must be on the PC's Phone Link screen. This keeps a relay from pairing in your place.", 20, ThemeBuilderC.MUTED))
	body.add_child(UiKit.button("They match", func(): show_step("done"), 220))
	body.add_child(UiKit.button("They don't match", func(): _reject_phrase(), 240))
	_message()


func _reject_phrase() -> void:
	await phone.unpair()
	if not is_inside_tree():
		return
	pair_phrase = ""
	pin = ""
	show_step("pin")
	say("Those words didn't match, so the new pairing was removed. Check the PC and type its new PIN.")


static func pin_error(e: String) -> String:
	if e.contains("verify") or e.contains("interference"):
		return "Response didn't verify: possible interference. Check the PC and try again; no new key was stored."
	if e.contains("new PIN") or e.contains("stale"):
		return "The PC has a new PIN. Type the new PIN shown on your PC."
	if e.contains("wrong") or e.contains("PIN") or e.contains("code"):
		return "That PIN didn't match. Check the PC's screen (the PIN changes every 10 minutes) and try again. (%s)" % e
	if e.contains("offline"):
		return "The PC stopped answering. Is Phone Link still on?"
	return "Pairing didn't work: %s" % e


# --- 4. The QR code ---------------------------------------------------------------------------

func _qr_step() -> void:
	body.add_child(UiKit.para("Point the camera at the code on your PC (Settings > Phone Link > Polox for Android > Pair the app). Polox asks for the camera only now, only for this.", 20))
	_scanner = QrScanner.new()
	_scanner.custom_minimum_size = Vector2(360, 300)
	_scanner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(_scanner)
	_message()
	_scanner.status.connect(say)
	_scanner.found.connect(on_scanned)
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button("Back", func(): show_step("search"), 140))
	row.add_child(UiKit.button("Type the PIN instead", func(): show_step("search"), 260))
	body.add_child(row)
	_scanner.start()


## A code was read: if it's Polox's, pair with it (the first of its addresses that answers).
func on_scanned(text: String) -> void:
	var q := AppLink.parse_qr(text)
	if q.is_empty():
		say("That's not Polox's pairing code. Use the one under Polox for Android on the PC.")
		if _scanner:
			_scanner.resume()
		return
	if _scanner:
		_scanner.stop()
	say("Found %s. Pairing..." % str(q.name))
	var last_error := ""
	for url in q.urls:
		var r: Dictionary = await phone.pair_with(str(url), str(q.pin), device_name, "qr")
		if not is_inside_tree():
			return
		if r.ok:
			_show_paired_step(r)
			return
		last_error = str(r.get("error", ""))
	say(pin_error(last_error) + " You can type the PIN instead.")


# --- 5. Done ----------------------------------------------------------------------------------

func _done_step() -> void:
	title_label.text = "Connected"
	body.add_child(UiKit.para("✓ Paired with %s. %s." % [phone.link.pc_name() if phone.link.pc_name() != "" else "your PC", phone.connection_text()], 26, ThemeBuilderC.YELLOW))
	body.add_child(UiKit.para("Your worlds sync now and whenever the PC is reachable. Without it, keep playing: changes wait on this phone.", 20, ThemeBuilderC.MUTED))
	var ok := UiKit.button("Start", func():
		connected.emit()
		close(), 220)
	body.add_child(UiKit.spacer(true))
	body.add_child(ok)
	ok.call_deferred("grab_focus")


func on_back() -> bool:
	if step == "verify":
		_reject_phrase()
		return true
	if step in ["pin", "qr"]:
		show_step("search")
		return true
	_clear()
	close()
	return true
