extends "res://tests/test_case.gd"
## Offline tests for GitHub Releases update detection (Windows PC & Android mobile).

const UpdateChecker := preload("res://scripts/core/update_checker.gd")
const SettingsUpdates := preload("res://scripts/ui/settings_updates.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")


func _sample_release_json(tag: String = "v1.0.5", extra_html: String = "https://github.com/SterburnDev/polox/releases/tag/v1.0.5") -> String:
	return JSON.stringify({
		"tag_name": tag,
		"name": "Polox Public Beta 1.05",
		"draft": false,
		"prerelease": false,
		"html_url": extra_html,
		"published_at": "2026-12-01T12:00:00Z",
		"body": "Bug fixes and improvements.\r\n\r\n\r\n- Faster cloud sync\r\n- Update detection",
		"assets": [
			{
				"name": "Polox-1.0.5-Setup.exe",
				"browser_download_url": "https://github.com/SterburnDev/polox/releases/download/v1.0.5/Polox-1.0.5-Setup.exe",
			},
			{
				"name": "Polox-1.0.5-Windows-Portable.zip",
				"browser_download_url": "https://github.com/SterburnDev/polox/releases/download/v1.0.5/Polox-1.0.5-Windows-Portable.zip",
			},
			{
				"name": "Polox-1.0.5-Android.apk",
				"browser_download_url": "https://github.com/SterburnDev/polox/releases/download/v1.0.5/Polox-1.0.5-Android.apk",
			},
		],
	})


func _reset_state() -> void:
	UpdateChecker.transport = Callable()
	UpdateChecker.reset_runtime_state()
	GameState.settings.erase("updates")


func test_version_parsing_and_comparison() -> void:
	eq(Array(UpdateChecker.parse_version("v1.0.2")), [1, 0, 2], "parses v-prefixed version")
	eq(Array(UpdateChecker.parse_version("1.0.10-beta1")), [1, 0, 10], "parses version with pre-release suffix")
	check(UpdateChecker.parse_version("invalid").is_empty(), "rejects non-numeric tags")
	eq(UpdateChecker.compare_versions("1.0.2", "1.0.10"), -1, "1.0.2 < 1.0.10 numerically")
	eq(UpdateChecker.compare_versions("1.1", "1.0.99"), 1, "1.1 > 1.0.99")
	eq(UpdateChecker.compare_versions("v1.0.2", "1.0.2.0"), 0, "equal lengths compare cleanly")
	check(UpdateChecker.is_newer("v1.0.3", "1.0.2"), "newer tag detected")
	check(not UpdateChecker.is_newer("v1.0.2", "1.0.2"), "same version is not newer")
	check(not UpdateChecker.is_newer("v1.0.1", "1.0.2"), "older version is not newer")


func test_safe_release_url_validation() -> void:
	eq(UpdateChecker.safe_release_url("https://github.com/SterburnDev/polox/releases/tag/v1.0.3"),
		"https://github.com/SterburnDev/polox/releases/tag/v1.0.3", "allows project release page")
	eq(UpdateChecker.safe_release_url("https://objects.githubusercontent.com/github-production-release-asset/polox.apk"),
		"https://objects.githubusercontent.com/github-production-release-asset/polox.apk", "allows GitHub asset CDN")
	eq(UpdateChecker.safe_release_url("https://release-assets.githubusercontent.com/polox.apk"),
		"https://release-assets.githubusercontent.com/polox.apk", "allows release-assets CDN")
	for bad in [
		"http://github.com/SterburnDev/polox/releases",
		"https://evil.example/SterburnDev/polox/releases",
		"https://github.com/otheruser/polox/releases",
		"https://github.com/SterburnDev/polox/releases\nEvil",
		"https://user@evil.example/SterburnDev/polox/releases",
		"javascript:alert(1)",
	]:
		eq(UpdateChecker.safe_release_url(bad), "", "blocks unsafe URL: " + bad)


func test_parse_release_for_windows_and_android() -> void:
	var body := _sample_release_json("v1.0.5")
	var win := UpdateChecker.parse_release(body, "1.0.2", "windows")
	check(win.ok and win.update_available and win.status == "update_available", "Windows sees v1.0.5 > 1.0.2")
	eq(str(win.latest_version), "1.0.5")
	eq(str(win.direct_name), "Polox-1.0.5-Setup.exe", "Windows picks Setup asset")
	var droid := UpdateChecker.parse_release(body, "1.0.2", "android")
	check(droid.ok and droid.update_available, "Android sees v1.0.5 > 1.0.2")
	eq(str(droid.direct_name), "Polox-1.0.5-Android.apk", "Android picks APK asset")
	check(not str(droid.notes).contains("\n\n\n"), "release notes collapse excessive blank lines")
	# Drafts and prereleases never trigger a stable update prompt.
	var draft := UpdateChecker.parse_release('{"tag_name":"v9.9.9","draft":true,"prerelease":false}', "1.0.2", "windows")
	check(draft.ok and not draft.update_available, "draft release ignored")
	# Unsafe html_url falls back cleanly to RELEASES_PAGE_URL.
	var bad_link := UpdateChecker.parse_release(_sample_release_json("v1.0.5", "https://evil.example/phish"), "1.0.2", "windows")
	eq(str(bad_link.release_url), UpdateChecker.RELEASES_PAGE_URL, "bad html_url falls back safely")


func test_check_now_offline_mock_caching_and_errors() -> void:
	fresh_save_root()
	_reset_state()
	var calls := [0]
	var local_v := UpdateChecker.current_version()
	var parts := UpdateChecker.parse_version(local_v)
	var next_v := "%d.%d.%d" % [parts[0], parts[1], parts[2] + 1]
	UpdateChecker.transport = func(_url: String, _headers: PackedStringArray) -> Array:
		calls[0] += 1
		return [HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), _sample_release_json("v" + next_v).to_utf8_buffer()]

	var host := Node.new()
	tree.root.add_child(host)
	var r1: Dictionary = await UpdateChecker.check_now(host, false)
	check(r1.ok and r1.update_available and str(r1.latest_version) == next_v, "mock transport detects newer version")
	eq(int(calls[0]), 1, "one request sent")

	# Non-forced call within 12h interval reuses cached result with zero network calls.
	var r2: Dictionary = await UpdateChecker.check_now(host, false)
	eq(int(calls[0]), 1, "second non-forced check respects 12h interval")
	eq(str(r2.latest_version), next_v, "returns cached info")

	# Rate limit and offline error handling.
	UpdateChecker.transport = func(_url: String, _headers: PackedStringArray) -> Array:
		return [HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(), PackedByteArray()]
	var limited: Dictionary = await UpdateChecker.check_now(host, true)
	check(not limited.ok and limited.status == "rate_limited", "handles GitHub rate limiting")

	UpdateChecker.transport = func(_url: String, _headers: PackedStringArray) -> Array:
		return [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	var offline: Dictionary = await UpdateChecker.check_now(host, true)
	check(not offline.ok and offline.status == "offline", "handles offline/timeout safely")

	host.queue_free()
	await frames(2)
	_reset_state()


func test_settings_and_title_update_ui() -> void:
	fresh_save_root()
	_reset_state()
	GameState.settings["ui_sounds"] = false
	var local_v := UpdateChecker.current_version()
	var parts := UpdateChecker.parse_version(local_v)
	var next_v := "%d.%d.%d" % [parts[0], parts[1], parts[2] + 1]
	UpdateChecker.transport = func(_url: String, _headers: PackedStringArray) -> Array:
		return [HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), _sample_release_json("v" + next_v).to_utf8_buffer()]

	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)

	var settings := SettingsScreen.new()
	settings.main = main
	settings.start_on = "Gameplay"
	main.open_panel(settings)
	await frames(3)

	var check_btn := settings.find_child("CheckUpdatesButton", true, false) as Button
	var status_lbl := settings.find_child("UpdateStatus", true, false) as Label
	var open_btn := settings.find_child("OpenUpdateButton", true, false) as Button
	var auto_cb := settings.find_child("AutoUpdateCheck", true, false) as CheckBox
	check(check_btn != null and status_lbl != null and open_btn != null and auto_cb != null, "Settings > Gameplay renders Updates UI")
	check(auto_cb.button_pressed, "startup update check on by default")
	auto_cb.button_pressed = false
	check(not UpdateChecker.auto_enabled(), "player can disable startup update checks")

	check_btn.pressed.emit()
	await frames(4)
	check(status_lbl.text.contains("v" + next_v), "Settings updates to show newer version: " + status_lbl.text)
	eq(open_btn.text, "Download update", "button text updates when update found")
	var badge := main.screen.find_child("UpdateBadge", true, false) as Button
	check(badge != null and badge.text.contains("v" + next_v), "TitleScreen displays clickable UpdateBadge")

	open_btn.pressed.emit()
	await frames(2)
	var dlg := main.find_child("UpdateDialog", true, false) as Control
	check(dlg != null, "UpdateDialog opens")
	var skip_btn := dlg.find_child("SkipVersion", true, false) as Button
	check(skip_btn != null, "has Skip this version button")
	skip_btn.pressed.emit()
	await frames(2)
	eq(UpdateChecker.dismissed_version(), next_v, "skipping saves dismissed_version")

	main._close_all_panels()
	main.queue_free()
	await frames(3)
	_reset_state()
