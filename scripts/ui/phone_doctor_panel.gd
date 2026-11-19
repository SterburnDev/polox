extends "res://scripts/ui/screen_panel.gd"
## The Phone Link Doctor screen: every check with ✓ / ⚠ / ✗, what it means in
## plain words and how to fix it; Run again, Copy diagnostics (safe to paste:
## no keys, tokens, codes or chat) and the firewall helper.

const PhoneDoctor := preload("res://scripts/phone/phone_doctor.gd")
const BackgroundJob := preload("res://scripts/core/background_job.gd")
const Firewall := preload("res://scripts/phone/firewall.gd")
const FixActions := preload("res://scripts/net/fix_actions.gd")

var main: Node
var results: Array = []
var _list: VBoxContainer
var _status: Label
var _job: Dictionary = {}     # background_job.gd box
var _snap: Dictionary = {}


func _ready() -> void:
	setup("Phone Link Doctor", Vector2(1060, 700))
	var top := UiKit.flow_row(10)
	top.add_child(UiKit.button("Run again", run_checks, 150))
	var copy := UiKit.button("Copy diagnostics", copy_diagnostics, 210)
	copy.tooltip_text = "Versions, addresses, these results and the last 50 requests. No keys, tokens, codes or chats."
	top.add_child(copy)
	if OS.get_name() == "Windows":
		var fw := UiKit.button("Firewall helper", func(): Firewall.open_helper(), 200)
		fw.tooltip_text = "Opens allow_phone_link.bat: it explains, asks Windows for admin rights and can be undone"
		top.add_child(fw)
	body.add_child(top)
	_status = UiKit.label("", 18, ThemeBuilder.MUTED)
	body.add_child(_status)
	_list = UiKit.vbox(10)
	body.add_child(UiKit.scroll(_list))
	run_checks()


func run_checks() -> void:
	if not _job.is_empty() and not bool(_job.done):
		return
	_status.text = "Checking... (a few seconds: Tailscale, the firewall and every address)"
	for c in _list.get_children():
		c.queue_free()
	_snap = PhoneDoctor.snapshot(main.phone_link)
	var snap := _snap
	_job = BackgroundJob.run(func() -> Variant: return PhoneDoctor.run(snap))


func _process(_delta: float) -> void:
	if not _job.is_empty() and bool(_job.done):
		results = _job.result if _job.result is Array else []
		_job = {}
		_show()


func _show() -> void:
	var fails := results.filter(func(r): return r.status == "fail").size()
	var warns := results.filter(func(r): return r.status == "warn").size()
	_status.text = "All green." if fails == 0 and warns == 0 else ("No problems (%d note(s) below)." % warns if fails == 0 else "%d problem(s), %d note(s). Fix them top to bottom." % [fails, warns])
	for r in results:
		var row := UiKit.hbox(12)
		var icon := UiKit.label(str(PhoneDoctor.ICONS.get(r.status, "?")), 26, {"ok": ThemeBuilder.MINT, "warn": ThemeBuilder.YELLOW, "fail": ThemeBuilder.DANGER}.get(r.status, ThemeBuilder.MUTED))
		icon.custom_minimum_size.x = 30
		row.add_child(icon)
		var col := UiKit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.label(str(r.title), 20, ThemeBuilder.CREAM))
		col.add_child(UiKit.para(str(r.detail), 18, ThemeBuilder.MUTED))
		if str(r.fix) != "" and str(r.status) in ["fail", "warn"]:
			col.add_child(UiKit.para("→ " + str(r.fix), 18, ThemeBuilder.YELLOW))
		if r.has("action") and str(r.status) in ["fail", "warn"]:
			var act := str(r.action)
			var arg := str(r.get("arg", ""))
			col.add_child(UiKit.button(FixActions.label(act), func():
				FixActions.run(act, arg, main)
				if act == "keep_awake":
					run_checks(), 280))
		row.add_child(col)
		_list.add_child(row)


func copy_diagnostics() -> void:
	var text := PhoneDoctor.diagnostics(_snap, results)
	DisplayServer.clipboard_set(text)
	GameState.notify("Diagnostics copied (no keys, tokens or chats in it).")


