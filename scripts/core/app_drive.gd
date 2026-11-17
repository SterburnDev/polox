extends RefCounted
## The "app_flow" drive (debug_drives.gd): Polox for Android's part in tests/test_android_app.gd,
## run as a real second Godot process with --app-mode. It goes through the app the way a person
## would (Connect to your PC > the PC it heard > the PIN on the keypad > Start, then play, offline
## play, the PC coming back, coming back to the app) and prints "[app] {json}" after each step.
## The test answers through a small command file (--app-cmd-file=): {"step": n, "pin": "..."}.
## Never used in play.
## Tags: [PAIRING]

const AppConnectPanel := preload("res://scripts/ui/app_connect_panel.gd")

var main: Node
var cmd_file := ""


func out(what: String, data: Dictionary = {}) -> void:
	data["what"] = what
	print("[app] " + JSON.stringify(data))


func _wait(seconds: float) -> void:
	await main.get_tree().create_timer(seconds).timeout


func _until(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		if cond.call():
			return true
		await _wait(0.1)
	return false


func _cmd(step: int, seconds: float = 90.0) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		if FileAccess.file_exists(cmd_file):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(cmd_file))
			if d is Dictionary and int(d.get("step", 0)) >= step:
				return d
		await _wait(0.15)
	return {}


func _panel() -> Control:
	for p in main.panels:
		if is_instance_valid(p) and p.get_script() == AppConnectPanel:
			return p
	return null


func _buttons(root: Node, prefix: String) -> Array:
	return root.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text.begins_with(prefix) and (b as Button).is_visible_in_tree())


func _tiles() -> int:
	return (SaveManager.load_room(GameState.current_room_id).get("tiles", []) as Array).size() if main.game else -1


func _place(cell: Vector2i) -> void:
	var b: Node = main.game.build
	b.enter()
	b.set_piece("cube")
	b.cursor = cell
	b.apply({})
	b.exit()
	main.flush_all()


func run(main_node: Node) -> void:
	main = main_node
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--app-cmd-file="):
			cmd_file = a.trim_prefix("--app-cmd-file=")
	var phone: Node = main.phone
	out("start", {"app": phone != null and bool(phone.app), "paired": phone != null and phone.paired()})
	if phone == null or not phone.app:
		return
	# 1. First start: the Connect screen explains, then looks for the PC.
	if not await _until(func(): return _panel() != null, 10.0):
		out("fail", {"why": "no Connect screen"})
		return
	var panel: Control = _panel()
	out("connect_panel", {"step": panel.step})
	panel.show_step("search")
	# One PC answering goes straight to its PIN; several are listed to tap.
	if not await _until(func(): return is_instance_valid(panel) and (panel.step == "pin" or _buttons(panel, "💻").size() > 0), 20.0):
		out("fail", {"why": "the PC was not found", "find": phone.link.last_find})
		return
	var straight: bool = panel.step == "pin"
	var pc_button: Button = null if straight else _buttons(panel, "💻")[0]
	var found_text: String = ("💻 %s   %s" % [str(panel.target.get("name", "")), str(panel.target.get("url", "")).trim_prefix("http://")]) if straight else pc_button.text
	out("found", {"button": found_text, "straight_to_pin": straight})
	var c1 := await _cmd(1)
	if pc_button:
		pc_button.pressed.emit()
	await _wait(0.2)
	for d in str(c1.get("pin", "")):
		panel.press_key(d)
	if not await _until(func(): return is_instance_valid(panel) and panel.step == "done", 20.0):
		out("fail", {"why": "pairing", "msg": panel._msg.text if is_instance_valid(panel) and panel._msg else ""})
		return
	out("paired", {"path": str(phone.connection.get("path", "")), "url": phone.origin, "pc": phone.link.pc_name(), "text": phone.connection_text(),
		"token_saved": phone.link.token().length() == 64})
	_buttons(panel, "Start")[0].pressed.emit()
	await _until(func(): return phone.client.state in ["ok", "conflict", "error", "offline"] and not phone.client.busy, 30.0)
	await _wait(0.5)
	out("synced", {"state": phone.client.state, "worlds": phone.link.link.get("worlds", []), "has_world": SaveManager.has_world(),
		"pulled": (phone.client.last_result.get("pulled", []) as Array).size()})
	# 2. Play: a block, then a sync (it goes to the PC).
	main.start_game()
	await _wait(1.0)
	var before := _tiles()
	_place(Vector2i(1, 4))
	var r: Dictionary = await phone.sync_now()
	out("pushed", {"ok": bool(r.get("ok", false)), "pushed": r.get("pushed", []), "tiles_before": before, "tiles": _tiles(), "room": GameState.current_room_id})
	# 3. The PC goes away: keep playing; the sync says "offline" and nothing is lost.
	await _cmd(2)
	_place(Vector2i(2, 4))
	var r2: Dictionary = await phone.sync_now()
	await phone.connect_pc(1.0)
	out("offline", {"ok": bool(r2.get("ok", false)), "state": phone.client.state, "playing": main.game != null, "tiles": _tiles(), "detail": phone.client.detail, "retry": phone._retry_in})
	# 4. The PC is back (and changed something meanwhile): the retry finds it and syncs both ways.
	await _cmd(3)
	await phone._retry_offline()
	await _until(func(): return not phone.client.busy, 20.0)
	out("resynced", {"state": phone.client.state, "path": str(phone.connection.get("path", "")), "pushed": phone.client.last_result.get("pushed", []), "pulled": phone.client.last_result.get("pulled", []),
		"world_name": str(SaveManager.load_world().get("name", "")) if SaveManager.has_world() else ""})
	# 5. Back from the background: a sync on resume.
	await _cmd(4)
	var syncs_before := int(phone.client.get_meta("syncs", 0))
	phone.client.status_changed.connect(func(s, _d):
		if s == "syncing":
			phone.client.set_meta("syncs", int(phone.client.get_meta("syncs", 0)) + 1))
	phone.on_lifecycle(true)
	await _wait(0.3)
	await _until(func(): return not phone.client.busy, 20.0)
	out("resumed", {"state": phone.client.state, "synced_again": int(phone.client.get_meta("syncs", 0)) > syncs_before})
	# 6. The PC offers a newer app.
	await phone.check_update()
	out("update", {"offer": phone.update_offer})
	out("done")
