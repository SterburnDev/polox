extends RefCounted
## Who may talk to Phone Link. While Phone Link is on, the PC always shows a
## 6-digit PIN (10 minutes, single use; a new one when it runs out and after
## each pairing). The phone trades it for a long random device token. Only a
## SHA-256 of each token is stored (phone/devices.json at the save root, never
## synced or exported), compared in constant time.
##
## Wrong PINs: 5 from one address -> that address waits 60 s (the phone shows
## the countdown); 20 in an hour from anywhere -> pairing pauses until you
## press "Unlock pairing" on the PC (kept across restarts). Pairing and auth
## failures go to phone/audit.log, never a token or a PIN.
## Tags: [PAIRING]

const HttpUtil := preload("res://scripts/phone/http_util.gd")
const PairingStore := preload("res://scripts/phone/pairing_store.gd")

const PIN_LIFETIME_S := 600.0
const WRONG_PER_ADDRESS := 5        # then a cooldown for that address
const COOLDOWN_S := 60.0
const WRONG_PER_HOUR := 20          # from anywhere: then pairing pauses until unlocked
const TRIES_PER_MINUTE := 30        # any tries from one address (a flood guard)
const MAX_WRONG_PER_CODE := 10      # then the PIN changes (the PC shows the new one)
const TOKEN_BYTES := 32
const SESSION_TOKEN_LIFETIME_S := 12.0 * 3600.0   # "Always ask for PIN": a key lasts one evening
const DEFAULT_DEVICE_NAME := "My phone"

var root := ""                      # the save root
var max_devices := 4
var always_ask := false             # every visit asks for the PIN (keys expire after a session)
var code := ""
var code_expires := 0.0             # unix seconds
var paused := false                 # too many wrong PINs this hour: only the PC can unlock
var _wrong_for_code := 0
var _attempts: Dictionary = {}      # ip -> [unix times] (every try)
var _wrong: Dictionary = {}         # ip -> wrong tries since its last cooldown
var _cooldown: Dictionary = {}      # ip -> unix time the cooldown ends
var _wrong_times: Array = []        # unix times of every wrong PIN (the hourly limit)
var _replace_id := ""               # "Rotate": the next pairing replaces this device
var _mutex := Mutex.new()


func _init(save_root: String) -> void:
	root = save_root
	paused = PairingStore.is_paused(root)


func devices_path() -> String:
	return PairingStore.devices_path(root)


## Paired devices (keys that ran out under "Always ask for PIN" are left out).
func devices() -> Array:
	var saved_devices := PairingStore.read_devices(root)
	var now_s := Time.get_unix_time_from_system()
	return saved_devices.filter(func(entry: Variant) -> bool:
		if not entry is Dictionary:
			return false
		# Entries from before session tokens have no expiry and keep working.
		var expires_s := float(entry.get("expires", 0.0))
		return expires_s <= 0.0 or expires_s > now_s
	)


func _save_devices(active_devices: Array) -> bool:
	return PairingStore.write_devices(root, active_devices)


# --- PIN ---------------------------------------------------------------------------------------

## A fresh 6-digit PIN for ten minutes. Replaces any older one.
func new_code(replace_device_id: String = "") -> String:
	_mutex.lock()
	_new_code_locked()
	_replace_id = replace_device_id
	_mutex.unlock()
	return code


func _new_code_locked() -> void:
	var random_value := 0
	for byte in Crypto.new().generate_random_bytes(4):
		random_value = (random_value << 8) | byte
	var fresh_pin := "%06d" % (absi(random_value) % 1000000)
	if fresh_pin == code:   # never show the same PIN twice in a row
		fresh_pin = "%06d" % ((fresh_pin.to_int() + 1 + (absi(random_value) % 999998)) % 1000000)
	code = fresh_pin
	code_expires = Time.get_unix_time_from_system() + PIN_LIFETIME_S
	_wrong_for_code = 0


func code_seconds_left() -> int:
	return maxi(0, ceili(code_expires - Time.get_unix_time_from_system())) if code != "" else 0


## The PIN as people read it: "482 913".
static func grouped(pin: String) -> String:
	return pin.substr(0, 3) + " " + pin.substr(3) if pin.length() == 6 else pin


## Keeps a PIN on screen while Phone Link is on: makes one when there is
## none or it ran out. Returns true when it changed.
func ensure_code() -> bool:
	if code != "" and code_seconds_left() > 0:
		return false
	new_code()
	return true


func cancel_code() -> void:
	code = ""
	code_expires = 0.0


func unlock() -> void:
	_mutex.lock()
	paused = false
	_wrong_times.clear()
	_wrong.clear()
	_cooldown.clear()
	PairingStore.write_paused(root, paused)
	_mutex.unlock()
	audit("pairing_unlocked")


## What the phone at `ip` should show before it types: {paused, cooldown (seconds)}.
func state_for(ip: String) -> Dictionary:
	_mutex.lock()
	var seconds_left := maxi(0, ceili(float(_cooldown.get(ip, 0.0)) - Time.get_unix_time_from_system()))
	var state := {"paused": paused, "cooldown": seconds_left, "always_ask": always_ask}
	_mutex.unlock()
	return state


## [PAIRING] Trades a PIN for a token. Returns {ok, token, device_id} or {ok: false, status, error,
## retry_after?, tries_left?}. `host` is the address the phone used; `client_id` is the
## launcher's own id for this browser (pairing it again replaces its old entry).
func pair(given_code: String, device_name: String, ip: String, host: String = "", client_id: String = "") -> Dictionary:
	_mutex.lock()
	var result := _pair_locked(
		given_code.strip_edges(), device_name.strip_edges().left(40), ip,
		host.left(120), client_id.strip_edges().left(40)
	)
	_mutex.unlock()
	return result


func _pair_locked(given_pin: String, device_name: String, ip: String, host: String, client_id: String) -> Dictionary:
	var now_s := Time.get_unix_time_from_system()
	if paused:
		audit("pair_paused ip=%s" % ip)
		return _paused_response()
	var wait_s := ceili(float(_cooldown.get(ip, 0.0)) - now_s)
	if wait_s > 0:
		return _cooldown_response(wait_s)
	# Count every eligible request before checking the PIN, including expired and correct PINs.
	var recent_attempts: Array = (_attempts.get(ip, []) as Array).filter(func(t: float) -> bool: return now_s - t < 60.0)
	if recent_attempts.size() >= TRIES_PER_MINUTE:
		audit("pair_rate_limited ip=%s" % ip)
		return {"ok": false, "status": 429, "error": "Too many tries. Wait a minute.", "retry_after": 60}
	recent_attempts.append(now_s)
	_attempts[ip] = recent_attempts
	if code == "" or now_s > code_expires:
		audit("pair_no_code ip=%s" % ip)
		return {"ok": false, "status": 401, "error": "That PIN ran out. Type the new PIN shown on your PC."}
	if not HttpUtil.constant_time_equals(given_pin, code):
		return _wrong_pin(ip, now_s)
	return _register_device_locked(device_name, ip, host, client_id, now_s)


func _register_device_locked(device_name: String, ip: String, host: String, client_id: String, now_s: float) -> Dictionary:
	var display_name := device_name if device_name != "" else DEFAULT_DEVICE_NAME
	var active_devices := devices()
	# A replacement or returning browser can reuse its existing slot on a full device list.
	if _replace_id != "":
		active_devices = active_devices.filter(func(device: Dictionary) -> bool: return str(device.get("id", "")) != _replace_id)
	if client_id != "":
		active_devices = active_devices.filter(func(device: Dictionary) -> bool: return str(device.get("client", "")) != client_id)
	if active_devices.size() >= max_devices:
		active_devices = _drop_stale_devices(active_devices, display_name)
	if active_devices.size() >= max_devices:
		audit("pair_refused_full ip=%s" % ip)
		var existing_host := str(active_devices[0].get("host", "")) if not active_devices.is_empty() else ""
		var hint := ""
		if existing_host != "" and existing_host != host:
			hint = " (One was paired at %s: the phone keeps pairings per address.)" % existing_host
		return {"ok": false, "status": 409, "error": "%d phones are paired already. On the PC: Phone Link > Forget one first.%s" % [max_devices, hint]}
	var token := Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()
	var device_id := "d" + Crypto.new().generate_random_bytes(6).hex_encode()
	var device_entry := {
		"id": device_id,
		"name": display_name,
		"token_sha256": HttpUtil.sha256_bytes(token.to_utf8_buffer()),
		"paired": Time.get_datetime_string_from_system(),
		"last_seen": Time.get_datetime_string_from_system(),
		"host": host,
		"client": client_id,
	}
	if always_ask:
		device_entry["expires"] = now_s + SESSION_TOKEN_LIFETIME_S
	active_devices.append(device_entry)
	# Commit first so a failed write leaves the same PIN available for a retry.
	if not _save_devices(active_devices):
		return {"ok": false, "status": 507, "error": "The PC couldn't save this pairing. Free some storage and try the same PIN again."}
	_replace_id = ""
	_wrong.erase(ip)
	_new_code_locked()   # single use: the PC shows a fresh PIN for the next phone
	audit("pair_ok device=%s ip=%s" % [device_name, ip])
	return {"ok": true, "token": token, "device_id": device_id}


## Entries named like this phone that haven't been seen for a week (it paired again since), oldest first,
## until there's room for one more.
func _drop_stale_devices(active_devices: Array, device_name: String) -> Array:
	var week_ago := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system() - 7 * 86400.0))
	var stale_devices := active_devices.filter(func(device: Dictionary) -> bool:
		var last_seen := str(device.get("last_seen", device.get("paired", "")))
		return str(device.get("name", "")) == device_name and last_seen < week_ago
	)
	stale_devices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("last_seen", "")) < str(b.get("last_seen", "")))
	var remaining_devices := active_devices.duplicate()
	while remaining_devices.size() >= max_devices and not stale_devices.is_empty():
		var stale_device: Dictionary = stale_devices.pop_front()
		remaining_devices.erase(stale_device)
		audit("stale_device_dropped device=%s last_seen=%s" % [str(stale_device.get("name", "")), str(stale_device.get("last_seen", ""))])
	return remaining_devices


func _wrong_pin(ip: String, now_s: float) -> Dictionary:
	_wrong_for_code += 1
	_wrong_times = _wrong_times.filter(func(t: float) -> bool: return now_s - t < 3600.0)
	_wrong_times.append(now_s)
	var wrong_from_address := int(_wrong.get(ip, 0)) + 1
	_wrong[ip] = wrong_from_address
	audit("pair_wrong_code ip=%s" % ip)
	if _wrong_times.size() >= WRONG_PER_HOUR:
		paused = true
		PairingStore.write_paused(root, paused)
		audit("pairing_paused wrong_this_hour=%d" % _wrong_times.size())
		return _paused_response()
	if _wrong_for_code >= MAX_WRONG_PER_CODE:
		_new_code_locked()
		audit("pair_code_changed ip=%s" % ip)
	if wrong_from_address >= WRONG_PER_ADDRESS:
		_wrong[ip] = 0
		_cooldown[ip] = now_s + COOLDOWN_S
		audit("pair_cooldown ip=%s" % ip)
		return _cooldown_response(int(COOLDOWN_S))
	return {"ok": false, "status": 401, "error": "That PIN isn't right.", "tries_left": WRONG_PER_ADDRESS - wrong_from_address}


static func _paused_response() -> Dictionary:
	return {"ok": false, "status": 423, "error": "Pairing is paused after too many wrong PINs. On the PC: Phone Link > Unlock pairing."}


static func _cooldown_response(wait_s: int) -> Dictionary:
	return {"ok": false, "status": 429, "error": "Too many wrong PINs. Wait %d seconds." % wait_s, "retry_after": wait_s}


# --- Tokens -----------------------------------------------------------------------------------

## The device a bearer token belongs to ({} if none). Compares hashes in constant time.
func check_token(token: String) -> Dictionary:
	if token.length() != TOKEN_BYTES * 2:
		return {}
	var token_hash := HttpUtil.sha256_bytes(token.to_utf8_buffer())
	var found := {}
	for device: Dictionary in devices():
		if HttpUtil.constant_time_equals(token_hash, str(device.get("token_sha256", ""))):
			found = device
	return found


func touch(device_id: String) -> void:
	_mutex.lock()
	var active_devices := devices()
	for device: Dictionary in active_devices:
		if str(device.get("id", "")) == device_id:
			device["last_seen"] = Time.get_datetime_string_from_system()
	_save_devices(active_devices)
	_mutex.unlock()


func unpair(device_id: String) -> void:
	_mutex.lock()
	var remaining_devices := devices().filter(func(device: Dictionary) -> bool: return str(device.get("id", "")) != device_id)
	_save_devices(remaining_devices)
	_mutex.unlock()
	audit("unpaired device=%s" % device_id)


## Revokes the device's token at once and makes a PIN that pairs it again
## (its saved games on the phone are untouched).
func rotate(device_id: String) -> String:
	unpair(device_id)
	audit("token_rotated device=%s" % device_id)
	return new_code()


# --- Audit log -----------------------------------------------------------------------------------

func audit(line: String) -> void:
	PairingStore.append_audit(root, line)


func audit_tail(line_count: int = 30) -> PackedStringArray:
	return PairingStore.audit_tail(root, line_count)
