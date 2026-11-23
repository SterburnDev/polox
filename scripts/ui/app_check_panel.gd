extends "res://scripts/ui/screen_panel.gd"
## Polox for Android: Settings > Your PC > Check connection. Runs app_check.gd and shows each
## rung as it finishes, what to do about the first one that fails, and whether the PC got the report.

const AppCheck := preload("res://scripts/phone/app_check.gd")

var phone: Node
var check: Node
var rows: VBoxContainer
var hint_label: Label
var sent_label: Label
var running := false


func setup_check(phone_mode: Node) -> void:
	phone = phone_mode
	setup("Check connection", Vector2(860, 640))
	body.add_child(UiKit.para("Each step from this phone to the PC, in order. The result goes to the PC's Doctor (no keys, PINs or chats).", 20, ThemeBuilder.MUTED))
	rows = UiKit.vbox(6)
	body.add_child(UiKit.scroll(rows))
	hint_label = UiKit.para("", 20, ThemeBuilder.YELLOW)
	body.add_child(hint_label)
	sent_label = UiKit.para("", 18, ThemeBuilder.MUTED)
	body.add_child(sent_label)
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button("Run again", run, 180))
	row.add_child(UiKit.button("Copy", func(): DisplayServer.clipboard_set(AppCheck.as_text(check.results) if check else ""), 140))
	body.add_child(row)
	check = AppCheck.new()
	add_child(check)
	check.rung.connect(_on_rung)
	run.call_deferred()


func _on_rung(r: Dictionary) -> void:
	var mark := "✓" if bool(r.ok) else ("!" if str(r.level) == "warn" else "✗")
	var color := ThemeBuilder.CREAM if bool(r.ok) else (ThemeBuilder.YELLOW if str(r.level) == "warn" else Color("#e86a8a"))
	var l := UiKit.para("%s  %s: %s" % [mark, r.name, r.detail], 18, color)
	rows.add_child(l)


func run() -> void:
	if running or not is_inside_tree():
		return
	running = true
	for c in rows.get_children():
		c.queue_free()
	hint_label.text = "Checking..."
	sent_label.text = ""
	var url: String = phone.origin
	check.sign = phone.get("signs") == true
	var out: Dictionary = await check.run(url, phone.token, phone.link, str(phone.client.only_slots))
	running = false
	if not is_inside_tree():
		return
	var bad := (check.results as Array).filter(func(x): return not bool(x.ok) and str(x.level) != "warn")
	hint_label.text = "All good." if bad.is_empty() else ("\n".join(check.hints) if not check.hints.is_empty() else "First problem: %s" % str(bad[0].name))
	sent_label.text = str(out.message)
