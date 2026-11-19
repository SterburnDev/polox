extends RefCounted
## "Missing you" notes: when you leave, your closest friend's little notes are set for a day, three days
## and a week later (at the hour you usually play, never at night); coming back takes them all back.
## Only a friend's name and a kind line: nothing from your chats or your home (a note can show on a
## locked screen).
##   Android: the APK template's receiver (native/android: PoloxAndroid.schedule), after the system's
##            own permission question (Android 13+).
##   Windows: per-user Task Scheduler tasks in \Polox\ that run a small hidden PowerShell script showing
##            a toast (no admin rights, nothing installed; the tasks delete themselves after firing).
##   Elsewhere (the browser): no notes.
## Settings > Game > Missing-you notes switches them off; the first time, a friend asks.

const AndroidNative := preload("res://scripts/core/android_native.gd")

const DAYS := [1, 3, 7]
const IDS := [4101, 4103, 4107]
const EARLIEST_HOUR := 9
const LATEST_HOUR := 21
const MARKER := "scheduled.json"   # Windows: notes are set (so starting knows to take them back)
const TASK_FOLDER := "\\Polox\\"
const LINES := {
	1: ["%s misses you. Come say hi?", "%s saved you a seat by the window.", "%s found something they want to show you."],
	3: ["%s keeps glancing at the door.", "It's quiet without you. %s says hello.", "%s wrote your name in the dust on the shelf. Twice."],
	7: ["It's been a week. %s kept your tea warm.", "%s still talks about you. Visit soon?", "%s made you a little sign: WELCOME BACK."],
}

static var dry_run := false               # tests: record what would run instead of running it
static var last_commands: Array = []      # (tests) the Windows commands, in order
static var last_schedule: Array = []      # (tests) [{id, at_unix, title, text}]


static func enabled() -> bool:
	var n: Variant = GameState.settings.get("notifications", {})
	return bool(n.get("miss_you", true)) if n is Dictionary else true


static func supported() -> bool:
	return OS.get_name() == "Windows" or AndroidNative.available()


## The notes to set when leaving now: [{id, at_unix, title, text}] (empty with no friends or when off).
static func plan(now_unix: float, local_hour: int, friend_name: String) -> Array:
	var out: Array = []
	if friend_name == "":
		return out
	var hour := clampi(local_hour, EARLIEST_HOUR, LATEST_HOUR)
	var midnight := now_unix - _seconds_into_day(now_unix)
	for i in DAYS.size():
		var day: int = DAYS[i]
		var at := midnight + day * 86400.0 + hour * 3600.0
		while at - now_unix < 20.0 * 3600.0:   # never sooner than 20 hours after you left
			at += 86400.0
		var lines: Array = LINES[day]
		out.append({"id": IDS[i], "at_unix": at, "title": "Polox", "text": str(lines[(int(now_unix / 86400.0) + i) % lines.size()]) % friend_name})
	return out


static func _seconds_into_day(now_unix: float) -> float:
	var t := Time.get_datetime_dict_from_unix_time(int(now_unix + _tz_seconds()))
	return int(t.hour) * 3600.0 + int(t.minute) * 60.0 + int(t.second)


static func _tz_seconds() -> float:
	return float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0


## The friend who'd miss you most: the closest (ties: the loneliest).
static func closest_friend() -> String:
	var best := ""
	var score := -1.0
	for id in GameState.characters:
		var c: Dictionary = GameState.characters[id]
		var s := float(c.get("relationship", {}).get("affinity", 0.0)) + float(c.get("mood", {}).get("loneliness", 0.0))
		if s > score:
			score = s
			best = str(c.get("name", ""))
	return best


## Leaving (the window closes, the app goes to the background): set the notes.
static func on_leave() -> void:
	var notes: Array = []
	if enabled() and supported() and not GameState.characters.is_empty():
		notes = plan(Time.get_unix_time_from_system(), int(Time.get_datetime_dict_from_system().get("hour", 18)), closest_friend())
	last_schedule = notes
	if AndroidNative.available():
		for id in IDS:
			AndroidNative.cancel(id)
		for n in notes:
			AndroidNative.schedule(int(n.id), float(n.at_unix), str(n.title), str(n.text))
	elif OS.get_name() == "Windows":
		if notes.is_empty():
			cancel_all()
		else:
			_windows_schedule(notes)   # (one process: the same three tasks are replaced, in order)


## Coming back (or starting): take every waiting note back. On Windows only when some were set (a
## marker says so), so starting Polox runs nothing otherwise.
static func cancel_all() -> void:
	last_schedule = []
	if AndroidNative.available():
		for id in IDS:
			AndroidNative.cancel(id)
	elif OS.get_name() == "Windows" and FileAccess.file_exists(_dir().path_join(MARKER)):
		DirAccess.remove_absolute(_dir().path_join(MARKER))
		_powershell("Get-ScheduledTask -TaskPath '%s' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue" % TASK_FOLDER)


## Settings' "Send a test": a note now (Android: asks for permission first if needed).
static func test_note() -> String:
	var who := closest_friend()
	var text := ("%s says hi! This is how a note looks." % who) if who != "" else "This is how a Polox note looks."
	if AndroidNative.available():
		if not AndroidNative.notifications_allowed():
			AndroidNative.ask_notification_permission()
			return "Allow notes for Polox, then try again."
		return "Sent." if AndroidNative.notify_now(4100, "Polox", text) else "Android didn't show it."
	if OS.get_name() == "Windows":
		var script := _write_toast_script()
		if script == "" or not _write_notes([{"id": 4100, "title": "Polox", "text": text}]):
			return "Couldn't write the note."
		_run(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script, "-Id", "4100"])
		return "Sent."
	return "Notes work in the Windows and Android apps."


static var force_ask := false   # tests: ask even in a test run


## After a real chat, once ever: the friend asks whether they may send notes (Yes switches them on,
## and on Android 13+ brings the system's own question; Not now switches them off).
## maybe_ask for a deferred call: the game is named by its instance id and looked up again when the
## call runs, so one that closed in between is simply not asked.
static func maybe_ask_later(main_id: int, friend_id: String) -> void:
	var main := instance_from_id(main_id) as Node
	if main != null and not main.is_queued_for_deletion():
		maybe_ask(main, friend_id)


static func maybe_ask(main: Node, friend_id: String) -> void:
	var n: Dictionary = GameState.settings.get("notifications", {}) if GameState.settings.get("notifications") is Dictionary else {}
	if bool(n.get("asked", false)) or not supported() or (_in_tests() and not force_ask):
		return
	if ChatLog.count_conversation(friend_id) < 2 or not main.panels.is_empty():
		return
	n["asked"] = true
	GameState.settings["notifications"] = n
	GameState.save_settings()
	var name := str(GameState.get_character(friend_id).get("name", "Your friend"))
	var p: Control = preload("res://scripts/ui/confirm_panel.gd").new()
	p.name = "MissYouAsk"
	main.open_panel(p)
	p.ask("A note now and then?", "%s wonders: may they send you a little note when they miss you?" % name, "Yes", "Not now")
	p.answered.connect(func(yes: bool):
		var s: Dictionary = GameState.settings.get("notifications", {}) if GameState.settings.get("notifications") is Dictionary else {}
		s["miss_you"] = yes
		GameState.settings["notifications"] = s
		GameState.save_settings()
		if yes:
			ask_permission())


## Android 13+: the system's own question, the first time.
static func ask_permission() -> void:
	if AndroidNative.available():
		AndroidNative.ask_notification_permission()


# --- Windows ----------------------------------------------------------------------------------------

static func _dir() -> String:
	return SaveManager.global_path("notes")


## The toast script (written each time, so an update can change it): shows note -Id from notes.json.
static func _write_toast_script() -> String:
	DirAccess.make_dir_recursive_absolute(_dir())
	var path := _dir().path_join("polox_note.ps1")
	var script := "\n".join(PackedStringArray([
		"# Polox: shows one 'missing you' note (from notes.json next to this file). Run by Task Scheduler.",
		"param([int]$Id)",
		"$ErrorActionPreference = 'Stop'",
		"$notes = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'notes.json') | ConvertFrom-Json",
		"$n = $notes | Where-Object { $_.id -eq $Id } | Select-Object -First 1",
		"if (-not $n) { exit 0 }",
		"[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null",
		"[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null",
		"$x = New-Object Windows.Data.Xml.Dom.XmlDocument",
		"$t = [Security.SecurityElement]::Escape([string]$n.title)",
		"$b = [Security.SecurityElement]::Escape([string]$n.text)",
		"$x.LoadXml(\"<toast><visual><binding template='ToastGeneric'><text>$t</text><text>$b</text></binding></visual></toast>\")",
		"$app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe'",
		"[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show((New-Object Windows.UI.Notifications.ToastNotification $x))",
	])) + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(script)
	f.close()
	return path


static func _write_notes(notes: Array) -> bool:
	var f := FileAccess.open(_dir().path_join("notes.json"), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(notes.map(func(n): return {"id": int(n.id), "title": str(n.title), "text": str(n.text)})))
	f.close()
	return true


## One per-user task per note, run hidden (conhost --headless), deleted a day after it fires.
static func _windows_schedule(notes: Array) -> void:
	var script := _write_toast_script()
	if script == "" or not _write_notes(notes):
		return
	var lines := PackedStringArray()
	for n in notes:
		var at := Time.get_datetime_string_from_unix_time(int(float(n.at_unix) + _tz_seconds()), false)   # local time
		var args := "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%s\" -Id %d" % [script.replace("/", "\\"), int(n.id)]
		lines.append("$a = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument '%s'" % args.replace("'", "''"))
		lines.append("$t = New-ScheduledTaskTrigger -Once -At ([datetime]'%s')" % at)
		lines.append("$t.EndBoundary = ([datetime]'%s').AddHours(12).ToString('s')" % at)
		lines.append("$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DeleteExpiredTaskAfter (New-TimeSpan -Days 1)")
		lines.append("Register-ScheduledTask -TaskPath '%s' -TaskName 'Note %d' -Action $a -Trigger $t -Settings $s -Force | Out-Null" % [TASK_FOLDER, int(n.id)])
	var f := FileAccess.open(_dir().path_join(MARKER), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"ids": notes.map(func(n): return int(n.id))}))
		f.close()
	_powershell("; ".join(lines))


static func _powershell(command: String) -> void:
	_run(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", command])


static func _run(args: Array) -> void:
	last_commands.append(" ".join(args))
	if dry_run or _in_tests():
		return   # tests never touch the PC's Task Scheduler
	# Not waiting: leaving stays instant (the PC finishes setting the notes after Polox has closed).
	OS.create_process("powershell.exe", PackedStringArray(args))


static func _in_tests() -> bool:
	for a in OS.get_cmdline_args():
		if a.ends_with("run_tests.gd"):
			return true
	return false
