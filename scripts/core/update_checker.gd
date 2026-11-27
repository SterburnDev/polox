extends RefCounted
## Privacy-respecting update check against public GitHub Releases (desktop PC and Android APK).
## Checks https://api.github.com/repos/SterburnDev/polox/releases/latest at most once every 12 hours
## when enabled, sending no personal data or tokens. Any link opened in the player's browser is
## strictly validated against GitHub HTTPS release/asset origins first.

const REPO := "SterburnDev/polox"
const LATEST_API_URL := "https://api.github.com/repos/SterburnDev/polox/releases/latest"
const RELEASES_PAGE_URL := "https://github.com/SterburnDev/polox/releases"
const SETTINGS_KEY := "updates"
const CHECK_INTERVAL_S := 43200   # 12 hours between automatic startup checks
const REQUEST_TIMEOUT_S := 8.0
const MAX_BODY_BYTES := 262144
const MAX_NOTES_CHARS := 600

## Optional offline test transport: func(url: String, headers: PackedStringArray) -> Array
## returning [result_code, http_status, resp_headers, body_bytes].
static var transport: Callable
static var _cached_result: Dictionary = {}
static var _toast_shown_version := ""
static var _in_flight := false


static func reset_runtime_state() -> void:
	_cached_result = {}
	_toast_shown_version = ""
	_in_flight = false


static func supported() -> bool:
	return not OS.has_feature("web")


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "1.0.2"))


static func current_label() -> String:
	return str(ProjectSettings.get_setting("application/config/release_label", "Polox Public Beta 1.02"))


static func current_platform() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.get_name() == "Windows":
		return "windows"
	return "other"


static func config() -> Dictionary:
	var saved: Variant = GameState.settings.get(SETTINGS_KEY, {})
	return saved.duplicate(true) if saved is Dictionary else {}


static func _save(key: String, value: Variant) -> void:
	var cfg := config()
	cfg[key] = value
	GameState.settings[SETTINGS_KEY] = cfg
	GameState.save_settings()


static func auto_enabled() -> bool:
	return bool(config().get("auto_check", true))


static func set_auto_enabled(on: bool) -> void:
	_save("auto_check", on)


static func dismissed_version() -> String:
	return str(config().get("dismissed_version", ""))


static func dismiss_version(ver: String) -> void:
	_save("dismissed_version", ver.strip_edges())


## Parses "v1.0.2", "1.0.10-beta" -> PackedInt32Array([1, 0, 2]) (empty if unparseable).
static func parse_version(raw: String) -> PackedInt32Array:
	var clean := raw.strip_edges()
	if clean.begins_with("v") or clean.begins_with("V"):
		clean = clean.substr(1)
	if clean == "":
		return PackedInt32Array()
	var parts := clean.split(".", false)
	var nums := PackedInt32Array()
	for p in parts:
		var seg := p.get_slice("-", 0).get_slice("+", 0)
		var digits := ""
		for i in seg.length():
			var ch := seg.unicode_at(i)
			if ch >= 48 and ch <= 57:
				digits += char(ch)
			else:
				break
		if digits == "":
			return PackedInt32Array()
		nums.append(int(digits))
	return nums


static func compare_versions(a: String, b: String) -> int:
	var va := parse_version(a)
	var vb := parse_version(b)
	if va.is_empty() or vb.is_empty():
		return 0
	var n := maxi(va.size(), vb.size())
	for i in n:
		var da := va[i] if i < va.size() else 0
		var db := vb[i] if i < vb.size() else 0
		if da < db:
			return -1
		if da > db:
			return 1
	return 0


static func is_newer(remote_tag: String, local_version: String = "") -> bool:
	var local_v := local_version if local_version != "" else current_version()
	var va := parse_version(remote_tag)
	var vb := parse_version(local_v)
	if va.is_empty() or vb.is_empty():
		return false
	return compare_versions(remote_tag, local_v) > 0


## Validates external update URLs so Polox only opens GitHub Releases / GitHub release asset CDN URLs over HTTPS.
static func safe_release_url(url: String) -> String:
	var clean := url.strip_edges()
	if clean == "" or not clean.begins_with("https://"):
		return ""
	for i in clean.length():
		var code := clean.unicode_at(i)
		if code <= 32 or code == 127:
			return ""
	var without_scheme := clean.substr(8)
	var slash := without_scheme.find("/")
	var host := (without_scheme.substr(0, slash) if slash != -1 else without_scheme).to_lower()
	var path := without_scheme.substr(slash) if slash != -1 else "/"
	if host.contains("@") or host.contains(":") or host == "":
		return ""
	if host == "github.com" and path.to_lower().begins_with("/sterburndev/polox/releases"):
		return clean
	if host in ["objects.githubusercontent.com", "release-assets.githubusercontent.com"]:
		return clean
	return ""


## Chooses the primary release URL and platform-specific download asset for Android or Windows.
static func pick_download_url(release: Dictionary, platform: String = "") -> Dictionary:
	var plat := platform if platform != "" else current_platform()
	var release_url := safe_release_url(str(release.get("html_url", "")))
	if release_url == "":
		release_url = RELEASES_PAGE_URL
	var direct_url := ""
	var direct_name := ""
	var assets_raw: Variant = release.get("assets", [])
	if assets_raw is Array:
		var apk_url := ""
		var apk_name := ""
		var setup_url := ""
		var setup_name := ""
		var zip_url := ""
		var zip_name := ""
		for a in assets_raw:
			if not a is Dictionary:
				continue
			var name := str(a.get("name", ""))
			var url := safe_release_url(str(a.get("browser_download_url", "")))
			if url == "":
				continue
			var lower := name.to_lower()
			if lower.ends_with(".apk") and apk_url == "":
				apk_url = url
				apk_name = name
			elif lower.ends_with("-setup.exe") and setup_url == "":
				setup_url = url
				setup_name = name
			elif lower.ends_with("-windows-portable.zip") and zip_url == "":
				zip_url = url
				zip_name = name
		if plat == "android" and apk_url != "":
			direct_url = apk_url
			direct_name = apk_name
		elif plat == "windows":
			if setup_url != "":
				direct_url = setup_url
				direct_name = setup_name
			elif zip_url != "":
				direct_url = zip_url
				direct_name = zip_name
	return {"release_url": release_url, "direct_url": direct_url, "direct_name": direct_name}


static func _clean_notes(raw: String) -> String:
	var text := raw.replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	while text.contains("\n\n\n"):
		text = text.replace("\n\n\n", "\n\n")
	if text.length() > MAX_NOTES_CHARS:
		text = text.left(MAX_NOTES_CHARS - 1).strip_edges() + "…"
	return text


static func parse_release(body_text: String, local_version: String = "", platform: String = "") -> Dictionary:
	var local_v := local_version if local_version != "" else current_version()
	var base := {
		"ok": false, "status": "parse_error", "update_available": false,
		"current_version": local_v, "latest_version": "", "latest_tag": "",
		"title": "", "published_at": "", "notes": "",
		"release_url": RELEASES_PAGE_URL, "direct_url": "", "direct_name": "", "error": "",
	}
	var parsed: Variant = JSON.parse_string(body_text)
	if not parsed is Dictionary:
		base.error = "Couldn't read the update info from GitHub."
		return base
	var rel: Dictionary = parsed
	if bool(rel.get("draft", false)) or bool(rel.get("prerelease", false)):
		base.ok = true
		base.status = "up_to_date"
		return base
	var tag := str(rel.get("tag_name", "")).strip_edges()
	var ver_nums := parse_version(tag)
	if ver_nums.is_empty():
		base.error = "The release version tag wasn't recognized."
		return base
	var norm_ver_parts := PackedStringArray()
	for n in ver_nums:
		norm_ver_parts.append(str(n))
	var latest_ver := ".".join(norm_ver_parts)
	var links := pick_download_url(rel, platform)
	var newer := is_newer(tag, local_v)
	base.ok = true
	base.status = "update_available" if newer else "up_to_date"
	base.update_available = newer
	base.latest_version = latest_ver
	base.latest_tag = tag
	base.title = str(rel.get("name", tag)).strip_edges()
	if base.title == "":
		base.title = tag
	base.published_at = str(rel.get("published_at", "")).left(10)
	base.notes = _clean_notes(str(rel.get("body", "")))
	base.release_url = str(links.release_url)
	base.direct_url = str(links.direct_url)
	base.direct_name = str(links.direct_name)
	return base


## Returns the most recent update result (in memory or saved in settings.json), re-evaluating
## `update_available` against this build's version in case the player already upgraded.
static func cached_or_saved() -> Dictionary:
	var local_v := current_version()
	if not _cached_result.is_empty():
		var copy := _cached_result.duplicate(true)
		if bool(copy.get("ok", false)) and str(copy.get("latest_version", "")) != "":
			copy["current_version"] = local_v
			copy["update_available"] = is_newer(str(copy.get("latest_version", "")), local_v)
			copy["status"] = "update_available" if bool(copy.update_available) else "up_to_date"
		return copy
	var saved: Variant = config().get("last_known", {})
	if not saved is Dictionary or (saved as Dictionary).is_empty():
		return {}
	var known := (saved as Dictionary).duplicate(true)
	var latest := str(known.get("latest_version", ""))
	if latest == "" or parse_version(latest).is_empty():
		return {}
	known["ok"] = true
	known["current_version"] = local_v
	known["update_available"] = is_newer(latest, local_v)
	known["status"] = "update_available" if bool(known.update_available) else "up_to_date"
	known["release_url"] = safe_release_url(str(known.get("release_url", "")))
	if str(known.release_url) == "":
		known["release_url"] = RELEASES_PAGE_URL
	known["direct_url"] = safe_release_url(str(known.get("direct_url", "")))
	return known


## Checks GitHub Releases for a newer public release. When `force` is false, respects the
## 12-hour interval (returning cached info without making a network request).
static func check_now(host: Node, force: bool = false) -> Dictionary:
	var local_v := current_version()
	if not supported():
		return {"ok": false, "status": "unsupported", "update_available": false,
			"current_version": local_v, "error": "Updates are managed through your PC in the browser version."}
	var now := int(Time.get_unix_time_from_system())
	if not force:
		var last := int(config().get("last_checked_unix", 0))
		if last > 0 and now - last < CHECK_INTERVAL_S:
			var cached := cached_or_saved()
			if not cached.is_empty():
				return cached
			return {"ok": true, "status": "throttled", "update_available": false,
				"current_version": local_v, "error": ""}
	if _in_flight:
		return {"ok": false, "status": "busy", "update_available": false,
			"current_version": local_v, "error": "Already checking for updates…"}
	_in_flight = true
	var headers := PackedStringArray([
		"User-Agent: Polox/%s" % local_v,
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
	])
	var raw: Array = []
	if transport.is_valid():
		raw = await transport.call(LATEST_API_URL, headers)
	else:
		if host == null or not is_instance_valid(host) or not host.is_inside_tree():
			_in_flight = false
			return {"ok": false, "status": "offline", "update_available": false,
				"current_version": local_v, "error": "Couldn't start update check."}
		var req := HTTPRequest.new()
		req.timeout = REQUEST_TIMEOUT_S
		req.body_size_limit = MAX_BODY_BYTES
		req.use_threads = true
		host.add_child(req)
		var err := req.request(LATEST_API_URL, headers, HTTPClient.METHOD_GET)
		if err != OK:
			req.queue_free()
			_in_flight = false
			return {"ok": false, "status": "offline", "update_available": false,
				"current_version": local_v, "error": "Couldn't reach GitHub Releases."}
		raw = await req.request_completed
		req.queue_free()
	_in_flight = false
	if raw.size() < 4:
		return {"ok": false, "status": "offline", "update_available": false,
			"current_version": local_v, "error": "Couldn't reach GitHub Releases."}
	var res_code := int(raw[0])
	var http_code := int(raw[1])
	var body_bytes: PackedByteArray = raw[3] if raw[3] is PackedByteArray else PackedByteArray()
	if res_code != HTTPRequest.RESULT_SUCCESS or http_code == 0:
		return {"ok": false, "status": "offline", "update_available": false,
			"current_version": local_v, "error": "Offline or timed out checking GitHub Releases."}
	if http_code == 403 or http_code == 429:
		return {"ok": false, "status": "rate_limited", "update_available": false,
			"current_version": local_v, "error": "GitHub rate limit reached. Try again later."}
	if http_code == 404:
		return {"ok": false, "status": "no_releases", "update_available": false,
			"current_version": local_v, "error": "No public releases published yet."}
	if http_code < 200 or http_code >= 300:
		return {"ok": false, "status": "http_error", "update_available": false,
			"current_version": local_v, "error": "GitHub returned HTTP %d." % http_code}
	var result := parse_release(body_bytes.get_string_from_utf8(), local_v)
	if bool(result.get("ok", false)):
		_cached_result = result.duplicate(true)
		var cfg := config()
		cfg["last_checked_unix"] = now
		cfg["last_known"] = {
			"latest_version": result.latest_version,
			"latest_tag": result.latest_tag,
			"title": result.title,
			"published_at": result.published_at,
			"notes": result.notes,
			"release_url": result.release_url,
			"direct_url": result.direct_url,
			"direct_name": result.direct_name,
		}
		GameState.settings[SETTINGS_KEY] = cfg
		GameState.save_settings()
	return result
