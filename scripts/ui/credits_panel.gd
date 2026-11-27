extends "res://scripts/ui/screen_panel.gd"
class_name CreditsPanel

## Full project credits: creator, AI collaborators, third-party asset creators,
## custom soundtrack pack, and open-source tools.


func _ready() -> void:
	setup("Credits", Vector2(920, 620))
	var col := UiKit.vbox(12)
	var sc := UiKit.scroll(col)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(sc)

	col.add_child(UiKit.para(
		"Polox Public Beta — a cozy, local-first life-sim built for PC and Android.",
		18,
		ThemeBuilder.CREAM
	))

	_section(col, "Created By", [
		"SterburnDev — Creator, Game Design, World Direction & Music Curation",
	])

	_section(col, "AI Collaborators", [
		"Google Gemini / Antigravity — Co-engineering, Voice & Live Mode, Web Search, Reasoning Controls, Cloud & Mobile Releases",
		"Anthropic Claude — Architecture, World Systems, Dialogue, Battle Mechanics, Mobile UI & Automated Test Suites",
		"OpenAI Codex / GPT — Code Review, Audits & Technical Assistance",
	])

	_section(col, "3D & Visual Assets", [
		"Kenney (kenney.nl) — Furniture Kit & Nature Kit props (CC0 1.0 Universal)",
		"Poly Haven (polyhaven.com) — Wood Floor PBR & Aerial Grass Rock textures (CC0 1.0 Universal)",
		"Polox Originals — Procedural Cozy House, Night Village & Character Sprites",
		"Mochi Soul Pack — Custom UI/Soul sprite integration",
	])

	_section(col, "Built-in Soundtrack Overrides", [
		"Light World Creation — Your Name Please",
		"Title Menu — Eek! (Surasshu)",
		"Dream World — Extras Menu (Sonic Mega Collection OST)",
		"Battle — Those Who Fight (Final Fantasy VII OST)",
		"Light World — House Theme (MOTHER / EarthBound Beginnings)",
	])

	_section(col, "Engine & Build Toolchain", [
		"Godot Engine 4.7.2 — Core 3D/2D Runtime & GDScript (MIT License)",
		"Blender — Trailer & 3D Asset Pipeline",
		"Inno Setup, Android SDK & Gradle — Windows Installer & Android APK Builds",
		"Gitleaks — Automated Secret Scanning",
	])

	_section(col, "Optional Connected Services", [
		"AI & Voice Providers — Google Gemini, Groq, Venice, OpenRouter, Ollama, OpenAI-compatible & ElevenLabs (user keys stay on device)",
		"Search & Sync — DuckDuckGo, Wikipedia, Google Drive / Android Cloud Folders, Tailscale & GitHub Releases (update checks)",
		"Maps — OpenStreetMap / Nominatim & optional Google Maps Street View previews",
	])

	var btn_row := UiKit.flow_row(10)
	var repo_btn := UiKit.button("GitHub Repo", func(): OS.shell_open("https://github.com/SterburnDev/polox"), 190)
	repo_btn.name = "CreditsRepoButton"
	btn_row.add_child(repo_btn)
	var notices_btn := UiKit.button("Close", close, 130)
	notices_btn.name = "CreditsCloseButton"
	btn_row.add_child(notices_btn)
	body.add_child(btn_row)


func _section(parent: Control, heading: String, entries: Array[String]) -> void:
	var h := UiKit.label(heading, 20, ThemeBuilder.YELLOW)
	h.add_theme_constant_override("line_spacing", 0)
	parent.add_child(h)
	for entry in entries:
		parent.add_child(UiKit.para("• " + entry, 16, ThemeBuilder.CREAM))
