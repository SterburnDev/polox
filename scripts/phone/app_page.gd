extends RefCounted
## /app on Phone Link: "Get Polox for Android". The page explains, step by step, what Android will
## ask, and links /app/polox.apk (the APK the PC built: android_app.gd). /app/version.json tells
## an installed app which version the PC has, so it can offer the update. No pairing needed: the
## APK holds the game only (no saves, settings or keys), the same as the phone browser version.
## iPhones keep the browser version (Apple doesn't allow installing apps this way).

const LauncherPage := preload("res://scripts/phone/launcher_page.gd")
const AndroidApp := preload("res://scripts/phone/android_app.gd")


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


static func html(info: Dictionary, apk: Dictionary) -> String:
	var body := "<main><div class=\"card\"><h1>Polox for Android</h1>"
	if bool(apk.get("present", false)):
		body += "<p class=\"conn\">● Version <b>%s</b> from <b>%s</b> (%.0f MB)</p>" % [_esc(str(apk.version)), _esc(str(info.get("pc_name", "your PC"))), float(apk.size) / 1048576.0]
		body += "<a class=\"btn main\" href=\"/app/polox.apk\" download=\"polox.apk\">Download polox.apk</a>"
		body += "<h2 style=\"margin-top:18px\">What Android will ask</h2><ol>"
		var steps := AndroidApp.steps_download(str(info.get("lan_url", "")) if str(info.get("lan_url", "")) != "" else str(info.get("canonical", "")))
		for i in range(1, steps.size()):
			body += "<li><p>%s</p></li>" % _esc(steps[i])
		body += "</ol><p>Then open Polox: it finds this PC by itself and asks for the PIN (or scan the code on the PC).</p>"
	else:
		body += "<div class=\"big\">🛠</div><h2>Not built yet</h2><p>On the PC: Settings > Phone Link > Polox for Android > <b>Build the app</b>. Then come back here.</p>"
	body += "<p>iPhone? Use the browser version: go back and tap Play (Apple doesn't allow installing apps this way).</p>"
	body += "</div><div class=\"foot\"><a class=\"btn small\" href=\"/\">Back</a></div></main>"
	return ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
		+ "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">"
		+ "<meta name=\"referrer\" content=\"no-referrer\"><meta name=\"theme-color\" content=\"#120e24\">"
		+ "<title>Polox for Android</title><style>" + LauncherPage.STYLE + " ol { padding-left: 22px; } li p { margin: 4px 0; }</style></head><body>"
		+ body + "</body></html>")


## What an installed app asks before offering an update.
static func version_json(apk: Dictionary) -> String:
	return JSON.stringify({
		"ok": true, "app": "Polox", "available": bool(apk.get("present", false)),
		"version": str(apk.get("version", "")), "version_code": int(apk.get("version_code", 0)),
		"size": int(apk.get("size", 0)), "sha256": str(apk.get("sha256", "")),
		"pc_version": str(ProjectSettings.get_setting("application/config/version", "")),
	})
