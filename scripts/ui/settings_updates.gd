extends RefCounted
## UI for Settings > Gameplay > Updates, the Title screen's clickable update badge, and the
## "Update available" modal (Windows PC and Android mobile).
## Kept out of test_soul.gd's COPY_FILES budget; uses only ThemeBuilder.TYPE_SCALE sizes & themed controls.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const UpdateChecker := preload("res://scripts/core/update_checker.gd")


static func _find_main(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	var cur: Node = node
	while cur:
		var owner_main: Variant = cur.get("main")
		if owner_main is Node and owner_main != null:
			return owner_main
		if cur.has_method("open_panel") and cur.has_method("show_title"):
			return cur
		cur = cur.get_parent()
	return node.get_tree().current_scene


## Adds the Updates section at the bottom of Settings > Gameplay (desktop & Android).
static func add_rows(parent: Control) -> void:
	if not UpdateChecker.supported():
		return
	var heading := UiKit.label("Updates", 22, ThemeBuilder.YELLOW)
	heading.add_theme_constant_override("line_spacing", 0)
	parent.add_child(heading)
	parent.add_child(UiKit.para("Current version: %s (v%s)" % [UpdateChecker.current_label(), UpdateChecker.current_version()], 16, ThemeBuilder.MUTED))

	var auto := CheckBox.new()
	auto.name = "AutoUpdateCheck"
	auto.text = "Check for updates on startup"
	auto.tooltip_text = "Checks GitHub Releases (no personal data sent)"
	auto.button_pressed = UpdateChecker.auto_enabled()
	auto.toggled.connect(func(on): UpdateChecker.set_auto_enabled(on))
	parent.add_child(auto)

	var status := UiKit.para("", 16, ThemeBuilder.CREAM)
	status.name = "UpdateStatus"
	parent.add_child(status)

	var row := UiKit.flow_row(10)
	parent.add_child(row)
	var latest := [UpdateChecker.cached_or_saved()]
	var check_btn := UiKit.button("Check for updates", Callable(), 220)
	check_btn.name = "CheckUpdatesButton"
	var action_btn := UiKit.button("Releases page", Callable(), 200)
	action_btn.name = "OpenUpdateButton"
	var credits_btn := UiKit.button("Credits", func():
		var m := _find_main(parent)
		if m != null and m.has_method("open_credits"):
			m.open_credits(), 140)
	credits_btn.name = "CreditsButton"
	row.add_child(check_btn)
	row.add_child(action_btn)
	row.add_child(credits_btn)

	var sync_view := func(info: Dictionary, custom_msg: String = ""):
		if not is_instance_valid(status) or not is_instance_valid(action_btn):
			return
		latest[0] = info
		if custom_msg != "":
			status.text = custom_msg
			status.add_theme_color_override("font_color", ThemeBuilder.YELLOW)
		elif info.is_empty():
			status.text = "Tap Check for updates to check GitHub Releases."
			status.add_theme_color_override("font_color", ThemeBuilder.MUTED)
		elif bool(info.get("ok", false)) and bool(info.get("update_available", false)):
			status.text = "Update available: %s (v%s)" % [str(info.get("title", "")), str(info.get("latest_version", ""))]
			status.add_theme_color_override("font_color", ThemeBuilder.YELLOW)
			action_btn.text = "Download update"
		elif bool(info.get("ok", false)):
			status.text = "✓ You're up to date (v%s)." % UpdateChecker.current_version()
			status.add_theme_color_override("font_color", ThemeBuilder.CREAM)
			action_btn.text = "Releases page"
		else:
			status.text = str(info.get("error", "Couldn't check for updates."))
			status.add_theme_color_override("font_color", ThemeBuilder.YELLOW)
			action_btn.text = "Releases page"

	sync_view.call(latest[0])

	action_btn.pressed.connect(func():
		var info: Dictionary = latest[0]
		if bool(info.get("ok", false)) and bool(info.get("update_available", false)):
			open_update_panel(_find_main(parent), info)
		else:
			OS.shell_open(UpdateChecker.RELEASES_PAGE_URL))

	check_btn.pressed.connect(func():
		check_btn.disabled = true
		status.text = "Checking GitHub Releases…"
		status.add_theme_color_override("font_color", ThemeBuilder.MUTED)
		var main := _find_main(parent)
		var res := await UpdateChecker.check_now(main if main else parent, true)
		if is_instance_valid(check_btn):
			check_btn.disabled = false
		sync_view.call(res)
		if main != null and is_instance_valid(main) and main.get("screen") != null and bool(res.get("ok", false)) and bool(res.get("update_available", false)):
			attach_title_badge(main.screen, main, res))


## Attaches (or updates) a compact clickable update pill right under the Title screen's VersionLabel.
static func attach_title_badge(title_screen: Control, main: Node, info: Dictionary) -> void:
	if title_screen == null or not is_instance_valid(title_screen):
		return
	if not bool(info.get("ok", false)) or not bool(info.get("update_available", false)):
		return
	var ver_label := title_screen.find_child("VersionLabel", true, false) as Control
	if ver_label == null or ver_label.get_parent() == null:
		return
	var host := ver_label.get_parent()
	var old := host.find_child("UpdateBadge", false, false)
	if old:
		old.queue_free()
	var badge := UiKit.button("Update available: v%s" % str(info.get("latest_version", "")), func():
		open_update_panel(main, info), 0)
	badge.name = "UpdateBadge"
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.add_theme_font_size_override("font_size", 16)
	host.add_child(badge)
	host.move_child(badge, ver_label.get_index() + 1)


static func toast_available(main: Node, latest: String) -> void:
	if main != null and main.has_method("show_toast"):
		main.show_toast("Polox v%s is available (tap the badge or Settings > Gameplay)" % latest)


## Opens the "Update available" dialog with Android APK or Windows release guidance and safe HTTPS links.
static func open_update_panel(main: Node, info: Dictionary) -> Control:
	var p: Control = load("res://scripts/ui/screen_panel.gd").new()
	p.name = "UpdateDialog"
	if main != null and main.has_method("open_panel"):
		main.open_panel(p)
	p.setup("Update available", Vector2(760, 520))

	var summary := UiKit.para("%s (v%s) is ready — you are on v%s." % [
		str(info.get("title", "New version")),
		str(info.get("latest_version", "")),
		str(info.get("current_version", UpdateChecker.current_version())),
	], 20, ThemeBuilder.YELLOW)
	p.body.add_child(summary)

	var guide := "Open the GitHub release page to download the new Windows installer or portable zip (with SHA-256 checksums). Your worlds stay in PersonalData."
	if UpdateChecker.current_platform() == "android":
		guide = "Download and install the new APK over Polox to update in place — your worlds stay on your phone."
	p.body.add_child(UiKit.para(guide, 16, ThemeBuilder.MUTED))

	var notes := str(info.get("notes", "")).strip_edges()
	if notes != "":
		var col := UiKit.vbox(6)
		col.add_child(UiKit.label("What's new", 18, ThemeBuilder.CREAM))
		col.add_child(UiKit.para(notes, 16, ThemeBuilder.CREAM))
		var sc := UiKit.scroll(col)
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.body.add_child(sc)

	var release_url := UpdateChecker.safe_release_url(str(info.get("release_url", "")))
	if release_url == "":
		release_url = UpdateChecker.RELEASES_PAGE_URL
	var direct_url := UpdateChecker.safe_release_url(str(info.get("direct_url", "")))

	var row := UiKit.flow_row(10)
	if UpdateChecker.current_platform() == "android" and direct_url != "":
		var dl := UiKit.button("Download APK", func(): OS.shell_open(direct_url), 190)
		dl.name = "DownloadUpdate"
		row.add_child(dl)
		var page := UiKit.button("Release page", func(): OS.shell_open(release_url), 170)
		page.name = "OpenReleasePage"
		row.add_child(page)
	else:
		var page := UiKit.button("Open release page", func(): OS.shell_open(release_url), 220)
		page.name = "OpenReleasePage"
		row.add_child(page)

	var skip := UiKit.button("Skip this version", func():
		UpdateChecker.dismiss_version(str(info.get("latest_version", "")))
		p.close(), 200)
	skip.name = "SkipVersion"
	row.add_child(skip)

	var later := UiKit.button("Later", func(): p.close(), 120)
	later.name = "CloseUpdate"
	row.add_child(later)
	p.body.add_child(row)
	return p
