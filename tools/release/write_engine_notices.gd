extends SceneTree
## Writes the Godot engine's own licence and every third-party notice it carries to a text file, read
## from the engine binary itself (Engine.get_license_text and friends), so the notices always match
## the engine that was used. tools/release/build_installer.py runs it and ships the result in the
## setup's licenses folder.
##
##   godot --headless --path <any empty project> --script tools/release/write_engine_notices.gd -- --out=FILE
##
## It is run on an empty scratch project on purpose: it must never start Polox's autoloads (they open
## the PersonalData folder).

func _init() -> void:
	var out_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_path = argument.trim_prefix("--out=")
	if out_path == "":
		printerr("write_engine_notices: pass -- --out=FILE")
		quit(2)
		return
	var lines := PackedStringArray()
	var version := Engine.get_version_info()
	lines.append("Godot Engine %s.%s.%s" % [version.major, version.minor, version.patch])
	lines.append("https://godotengine.org")
	lines.append("")
	lines.append("Polox is made with the Godot Engine. This file reproduces the engine's licence and the")
	lines.append("notices of the third-party software built into it, as the engine reports them.")
	lines.append("")
	lines.append("=== Godot Engine licence ===")
	lines.append("")
	lines.append(Engine.get_license_text())
	lines.append("")
	lines.append("=== Third-party components ===")
	for component in Engine.get_copyright_info():
		lines.append("")
		lines.append("- " + str(component.get("name", "")))
		for part in component.get("parts", []):
			for holder in part.get("copyright", []):
				lines.append("    (c) " + str(holder))
			lines.append("    Licence: " + str(part.get("license", "")))
	lines.append("")
	lines.append("=== Licence texts ===")
	var licence_texts := Engine.get_license_info()
	var names := licence_texts.keys()
	names.sort()
	for licence_name in names:
		lines.append("")
		lines.append("--- %s ---" % licence_name)
		lines.append("")
		lines.append(str(licence_texts[licence_name]))
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("write_engine_notices: can't write " + out_path)
		quit(1)
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("wrote %s (%d components, %d licence texts)" % [out_path, Engine.get_copyright_info().size(), names.size()])
	quit(0)
