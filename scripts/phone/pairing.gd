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
##
## pair_v:1 (new phones opt in; old ones keep the cleartext exchange):
##   GET  /api/pairing?wrap=1 -> + {pair_v: 1, kdf, iter, salt, seal, pub}
##        salt: 16 random bytes made with each PIN (memory only); pub: this run's
##        RSA-2048 public key (SubjectPublicKeyInfo DER, base64; memory only).
##   POST /api/pair {pair_v: 1, salt, nonce, sealed, device, client}   (no "code")
##        sealed = RSA PKCS#1 v1.5 of "pair1|<salt>|<nonce>|<secret>|<PIN>"
##        (nonce 16 random bytes, secret 32 random bytes, both hex), so neither the
##        PIN nor the secret crosses the network readable, and a capture can't be
##        brute-forced offline. A ciphertext that doesn't open counts as a wrong PIN.
##   -> {ok, pair_v: 1, ct, tag, phrase, device_id}   (never a token field)
##        K = HMAC-SHA256(secret, PBKDF2-HMAC-SHA256(PIN, salt, iter, 32))
##        block i = HMAC-SHA256(K, "enc|1|<iter>|<salt>|<nonce>|<i>"); ct = token XOR blocks
##        tag = HMAC-SHA256(K, "tag|1|<iter>|<salt>|<nonce>|<ct>"), first 32 hex
##        phrase = VERIFY_WORDS[b % 64] for the first 3 bytes of
##        HMAC-SHA256(token, "polox verify v1|" + SHA-256 of the public key's DER)
## Tags: [PAIRING]

const HttpUtil := preload("res://scripts/phone/http_util.gd")
const PairingStore := preload("res://scripts/phone/pairing_store.gd")
const RequestSig := preload("res://scripts/phone/request_sig.gd")
const SIG_NONCES_MAX := 50000       # signed requests remembered at once (10 minutes' worth)

const PIN_LIFETIME_S := 600.0
const WRONG_PER_ADDRESS := 5        # then a cooldown for that address
const COOLDOWN_S := 60.0
const WRONG_PER_HOUR := 20          # from anywhere: then pairing pauses until unlocked
const TRIES_PER_MINUTE := 30        # any tries from one address (a flood guard)
const MAX_WRONG_PER_CODE := 10      # then the PIN changes (the PC shows the new one)
const TOKEN_BYTES := 32
const SESSION_TOKEN_LIFETIME_S := 12.0 * 3600.0   # "Always ask for PIN": a key lasts one evening
const DEFAULT_DEVICE_NAME := "My phone"
const PRUNE_AFTER_S := 3600.0       # flood-guard entries this old are forgotten
const PAIR_WRAP_VERSION := 1
const PAIR_WRAP_KDF := "pbkdf2-sha256"
const PAIR_WRAP_ITER := 10000
const PAIR_WRAP_MIN_ITER := 10000
const PAIR_WRAP_MAX_ITER := 100000
const PAIR_WRAP_SALT_BYTES := 16
const PAIR_WRAP_NONCE_BYTES := 16
const PAIR_WRAP_SECRET_BYTES := 32
const PAIR_WRAP_SEAL := "rsa2048-pkcs1v15"
const PAIR_WRAP_RSA_BYTES := 256    # RSA-2048: a sealed message is exactly this long
const PAIR_WRAP_TAG_BYTES := 16      # the tag is cut to this many bytes (32 hex)
const PAIR_SEAL_PREFIX := "pair1"
const PAIR_VERIFY_LABEL := "polox verify v1|"
const PAIR_FAILED := "Response didn't verify: possible interference"
const VERIFY_WORDS: PackedStringArray = [
	"amber", "apple", "arch", "arrow", "aspen", "atlas", "autumn", "basil",
	"beacon", "berry", "birch", "breeze", "brook", "cactus", "cedar", "cherry",
	"cinder", "cloud", "clover", "coast", "comet", "coral", "cove", "crane",
	"crystal", "daisy", "dawn", "deer", "delta", "dove", "dream", "drift",
	"dune", "echo", "elm", "ember", "fern", "field", "finch", "flint",
	"forest", "fox", "gale", "garden", "ginger", "glen", "gold", "grove",
	"harbor", "hazel", "heron", "hill", "honey", "iris", "island", "ivy",
	"jade", "jasper", "juniper", "lake", "lark", "laurel", "leaf", "lichen",
]

var root := ""                      # the save root
var max_devices := 4
var always_ask := false             # every visit asks for the PIN (keys expire after a session)
var code := ""
var code_expires := 0.0             # unix seconds
var _wrap_salt := ""                # 16 random bytes as hex; lives and dies with this PIN
var _seal_key: CryptoKey = null     # pair_v:1: this run's RSA key (memory only, dropped when Phone Link stops)
var _seal_pub := ""                 # its public half: SubjectPublicKeyInfo DER, base64
var _seal_fp := ""                  # SHA-256 of that DER (hex), mixed into the check words
var paused := false                # too many wrong PINs this hour: only the PC can unlock
var _wrong_for_code := 0
var _attempts: Dictionary = {}      # ip -> [unix times] (every try)
var _wrong: Dictionary = {}         # ip -> wrong tries since its last cooldown
var _wrong_updated: Dictionary = {} # ip -> last wrong try (for pruning _wrong)
var _cooldown: Dictionary = {}      # ip -> unix time the cooldown ends
var _wrong_times: Array = []        # unix times of every wrong PIN (the hourly limit)
var _replace_id := ""               # "Rotate": the next pairing replaces this device
var _sig_nonces: Dictionary = {}    # signed requests' nonces -> unix time they may be forgotten (replays)
var _sig_nonces_pruned := 0.0
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
	var crypto := Crypto.new()
	var random_value := 0
	for byte in crypto.generate_random_bytes(4):
		random_value = (random_value << 8) | byte
	var fresh_pin := "%06d" % (absi(random_value) % 1000000)
	if fresh_pin == code:   # never show the same PIN twice in a row
		fresh_pin = "%06d" % ((fresh_pin.to_int() + 1 + (absi(random_value) % 999998)) % 1000000)
	code = fresh_pin
	_wrap_salt = crypto.generate_random_bytes(PAIR_WRAP_SALT_BYTES).hex_encode()
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
	_mutex.lock()
	code = ""
	_wrap_salt = ""
	code_expires = 0.0
	_mutex.unlock()


func unlock() -> void:
	_mutex.lock()
	paused = false
	_wrong_times.clear()
	_wrong.clear()
	_wrong_updated.clear()
	_cooldown.clear()
	PairingStore.write_paused(root, paused)
	_mutex.unlock()
	audit("pairing_unlocked")


## What the phone at `ip` should show before it types: {paused, cooldown (seconds)}.
func state_for(ip: String) -> Dictionary:
	_mutex.lock()
	var now_s := Time.get_unix_time_from_system()
	_prune_attempts_locked(now_s)
	var seconds_left := maxi(0, ceili(float(_cooldown.get(ip, 0.0)) - now_s))
	var state := {"paused": paused, "cooldown": seconds_left, "always_ask": always_ask}
	_mutex.unlock()
	return state


## This build speaks pair_v:1 (the PC advertises it in /hello.json and /api/pairing?wrap=1).
static func wrap_supported() -> bool:
	return valid_wrap_iter(PAIR_WRAP_ITER)


## Capability fields for GET /api/pairing?wrap=1 (an old request gets none of these).
## The RSA key is made the first time a phone asks (about 0.15 s), then kept for this run.
func wrap_info() -> Dictionary:
	_mutex.lock()
	var info := {}
	if wrap_supported() and _ensure_seal_key_locked():
		info = {"pair_v": PAIR_WRAP_VERSION, "kdf": PAIR_WRAP_KDF, "iter": PAIR_WRAP_ITER, "salt": _wrap_salt,
			"seal": PAIR_WRAP_SEAL, "pub": _seal_pub, "sig": RequestSig.VERSION, "now": int(Time.get_unix_time_from_system())}
	_mutex.unlock()
	return info


## Phone Link stopped: the RSA key goes with it (a new one next time).
func forget_wrap_key() -> void:
	_mutex.lock()
	_seal_key = null
	_seal_pub = ""
	_seal_fp = ""
	_mutex.unlock()


## The SHA-256 of this run's public key ("" before a phone asked): the PC's half of the check words.
func wrap_fingerprint() -> String:
	_mutex.lock()
	var fp := _seal_fp
	_mutex.unlock()
	return fp


func _ensure_seal_key_locked() -> bool:
	if _seal_key != null:
		return true
	var key := Crypto.new().generate_rsa(PAIR_WRAP_RSA_BYTES * 8)
	if key == null:
		return false
	var der := der_from_pem(key.save_to_string(true))
	if der.is_empty():
		return false
	_seal_key = key
	_seal_pub = Marshalls.raw_to_base64(der)
	_seal_fp = HttpUtil.sha256_bytes(der)
	audit("pair_key_made fingerprint=%s" % _seal_fp.left(16))
	return true


## Bound the in-memory flood maps without changing any live lockout or cooldown:
## only entries older than an hour go (every limit looks back a minute or an hour at most).
func _prune_attempts_locked(now_s: float) -> void:
	for ip: String in _attempts.keys():
		var recent: Array = (_attempts[ip] as Array).filter(func(t: float) -> bool: return now_s - t < PRUNE_AFTER_S)
		if recent.is_empty():
			_attempts.erase(ip)
		else:
			_attempts[ip] = recent
	for ip: String in _cooldown.keys():
		if now_s - float(_cooldown[ip]) >= PRUNE_AFTER_S:
			_cooldown.erase(ip)
	for ip: String in _wrong_updated.keys():
		if now_s - float(_wrong_updated[ip]) >= PRUNE_AFTER_S:
			_wrong_updated.erase(ip)
			_wrong.erase(ip)
	for ip: String in _wrong.keys():
		if not _wrong_updated.has(ip):
			_wrong.erase(ip)


## How many addresses the flood guard remembers (tests).
func tracked_addresses() -> int:
	_mutex.lock()
	var n := maxi(_attempts.size(), maxi(_cooldown.size(), _wrong.size()))
	_mutex.unlock()
	return n


## [PAIRING] Trades a PIN for a token. Returns {ok, token, device_id} or {ok: false, status, error,
## retry_after?, tries_left?, stale_salt?}. `host` is the address the phone used; `client_id` is the
## launcher's own id for this browser (pairing it again replaces its old entry). `wrap` is the request
## body: with pair_v the PIN comes sealed inside it and the answer is {ok, pair_v, ct, tag, phrase,
## device_id} instead (no token in it).
func pair(given_code: String, device_name: String, ip: String, host: String = "", client_id: String = "", wrap: Dictionary = {}) -> Dictionary:
	_mutex.lock()
	var result := _pair_locked(
		given_code.strip_edges(), device_name.strip_edges().left(40), ip,
		host.left(120), client_id.strip_edges().left(40), wrap.duplicate(true)
	)
	_mutex.unlock()
	return result


func _pair_locked(given_pin: String, device_name: String, ip: String, host: String, client_id: String, wrap: Dictionary) -> Dictionary:
	var now_s := Time.get_unix_time_from_system()
	_prune_attempts_locked(now_s)
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
	var wrapped := wrap.has("pair_v")
	if wrapped:
		var checked := _check_wrap_request_locked(wrap, given_pin, ip)
		if not bool(checked.ok):
			return checked
		wrap = checked.wrap
	if code == "" or now_s > code_expires:
		audit("pair_no_code ip=%s" % ip)
		return {"ok": false, "status": 401, "error": "That PIN ran out. Type the new PIN shown on your PC."}
	var secret := PackedByteArray()
	if wrapped:
		var opened := _open_seal_locked(str(wrap.sealed), str(wrap.salt), str(wrap.nonce))
		if opened.is_empty():
			audit("pair_seal_rejected ip=%s" % ip)
			return _wrong_pin(ip, now_s)   # (whatever didn't open counts as a wrong PIN: every limit applies)
		given_pin = str(opened.pin)
		secret = opened.secret
	if not HttpUtil.constant_time_equals(given_pin, code):
		_wipe(secret)
		return _wrong_pin(ip, now_s)
	return _register_device_locked(given_pin, device_name, ip, host, client_id, now_s, wrap, secret)


## pair_v:1 requests, before anything is decrypted: {ok: true, wrap: {salt, nonce, sealed}} or a refusal.
func _check_wrap_request_locked(wrap: Dictionary, given_pin: String, ip: String) -> Dictionary:
	var unsupported := {"ok": false, "status": 400, "error": "This pairing version isn't supported. Update Polox on this phone, or reload the page."}
	if _wire_int(wrap.get("pair_v")) != PAIR_WRAP_VERSION:
		audit("pair_wrap_rejected reason=version ip=%s" % ip)
		return unsupported
	if wrap.has("iter") and (not valid_wrap_iter(_wire_int(wrap.iter)) or _wire_int(wrap.iter) != PAIR_WRAP_ITER):
		audit("pair_wrap_rejected reason=iter ip=%s" % ip)
		return unsupported
	if given_pin != "":
		audit("pair_wrap_rejected reason=cleartext_pin ip=%s" % ip)   # a wrapped request never carries the PIN itself
		return unsupported
	var salt := str(wrap.get("salt", "")).to_lower()
	if not _valid_hex(salt, PAIR_WRAP_SALT_BYTES) or not HttpUtil.constant_time_equals(salt, _wrap_salt):
		audit("pair_stale_salt ip=%s" % ip)
		return {"ok": false, "status": 409, "error": "The PC has a new PIN. Type the new PIN shown on your PC.", "stale_salt": true}
	var nonce := str(wrap.get("nonce", "")).to_lower()
	if not _valid_hex(nonce, PAIR_WRAP_NONCE_BYTES):
		audit("pair_wrap_rejected reason=nonce ip=%s" % ip)
		return {"ok": false, "status": 400, "error": "The pairing request was incomplete. Reload and try again."}
	var sealed := str(wrap.get("sealed", "")).to_lower()
	if not _valid_hex(sealed, PAIR_WRAP_RSA_BYTES):
		audit("pair_wrap_rejected reason=seal ip=%s" % ip)
		return {"ok": false, "status": 400, "error": "The pairing request was incomplete. Reload and try again."}
	return {"ok": true, "wrap": {"pair_v": PAIR_WRAP_VERSION, "salt": salt, "nonce": nonce, "sealed": sealed}}


## Opens a sealed "pair1|salt|nonce|secret|PIN" with this run's key: {pin, secret} or {} when it doesn't
## open or doesn't belong to this request (another PIN's salt, another nonce).
func _open_seal_locked(sealed_hex: String, salt: String, nonce: String) -> Dictionary:
	if _seal_key == null or not _valid_hex(sealed_hex, PAIR_WRAP_RSA_BYTES):
		return {}
	var plain := Crypto.new().decrypt(_seal_key, sealed_hex.hex_decode())
	if plain.is_empty() or plain.size() > 200:
		_wipe(plain)
		return {}
	var parts := plain.get_string_from_ascii().split("|")
	_wipe(plain)
	var fits := parts.size() == 5 and parts[0] == PAIR_SEAL_PREFIX
	fits = fits and HttpUtil.constant_time_equals(parts[1] if fits else "", salt)
	fits = fits and HttpUtil.constant_time_equals(parts[2] if fits else "", nonce)
	fits = fits and _valid_hex(parts[3] if fits else "", PAIR_WRAP_SECRET_BYTES)
	fits = fits and (parts[4] if fits else "").length() <= 12
	if not fits:
		return {}
	return {"pin": parts[4], "secret": parts[3].hex_decode()}


func _register_device_locked(given_pin: String, device_name: String, ip: String, host: String, client_id: String, now_s: float, wrap: Dictionary, secret: PackedByteArray = PackedByteArray()) -> Dictionary:
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
		_wipe(secret)
		audit("pair_refused_full ip=%s" % ip)
		var existing_host := str(active_devices[0].get("host", "")) if not active_devices.is_empty() else ""
		var hint := ""
		if existing_host != "" and existing_host != host:
			hint = " (One was paired at %s: the phone keeps pairings per address.)" % existing_host
		return {"ok": false, "status": 409, "error": "%d phones are paired already. On the PC: Phone Link > Forget one first.%s" % [max_devices, hint]}
	var token := Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()
	var device_id := "d" + Crypto.new().generate_random_bytes(6).hex_encode()
	var response := {"ok": true, "device_id": device_id}
	var wrapped := not secret.is_empty()
	if wrapped:
		var sealed_answer := wrap_token(given_pin, secret, token, str(wrap.salt), str(wrap.nonce), PAIR_WRAP_ITER, _seal_fp)
		_wipe(secret)
		if sealed_answer.is_empty():
			audit("pair_wrap_failed ip=%s" % ip)
			return {"ok": false, "status": 500, "error": "The PC couldn't finish pairing. Type the same PIN again."}
		response.merge(sealed_answer, true)
	else:
		response["token"] = token
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
	if wrapped:
		device_entry["sig"] = true   # it signs every request (request_sig.gd): its key alone never opens anything
	active_devices.append(device_entry)
	# Commit first so a failed write leaves the same PIN available for a retry.
	if not _save_devices(active_devices):
		return {"ok": false, "status": 507, "error": "The PC couldn't save this pairing. Free some storage and try the same PIN again."}
	_replace_id = ""
	_wrong.erase(ip)
	_wrong_updated.erase(ip)
	_new_code_locked()   # single use: the PC shows a fresh PIN for the next phone
	audit("pair_ok device=%s ip=%s" % [_audit_text(device_name), ip])
	if wrapped:
		audit("pair_wrap_ok device=%s" % device_id)
		audit("pair_phrase device=%s words=%s" % [device_id, str(response.get("phrase", "")).replace(" ", "-")])
	else:
		audit("pair_legacy device=%s ip=%s" % [device_id, ip])   # an older phone: its key crossed the network as is
	return response


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
	_wrong_updated[ip] = now_s
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


# --- pair_v:1 wrapping (shared by the PC and the Android app) ------------------------------------

static func valid_wrap_iter(iterations: int) -> bool:
	return iterations >= PAIR_WRAP_MIN_ITER and iterations <= PAIR_WRAP_MAX_ITER


## Lowercase hex of exactly `byte_count` bytes (no sign, no prefix: stricter than is_valid_hex_number).
static func _valid_hex(value: String, byte_count: int) -> bool:
	if value.length() != byte_count * 2:
		return false
	for i in value.length():
		var c := value.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


## Standard base64 (letters, digits, + / and = padding at the end only).
static func _is_base64(value: String) -> bool:
	var padding := false
	for i in value.length():
		var c := value.unicode_at(i)
		if c == 61:
			padding = true
			continue
		if padding or not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 43 or c == 47):
			return false
	return true


## A whole number from JSON (-1 for anything else: strings, arrays, fractions).
static func _wire_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and absf(value) < 1.0e9 and value == floorf(value):
		return int(value)
	return -1


## Audit lines are one line each: a phone's name can't start a line of its own.
static func _audit_text(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		out += "?" if c < 32 or c == 127 else text[i]
	return out


static func _wipe(bytes: PackedByteArray) -> void:
	bytes.fill(0)


static func hmac_sha256(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	var hmac := HMACContext.new()
	if hmac.start(HashingContext.HASH_SHA256, key) != OK:
		return PackedByteArray()
	if hmac.update(message) != OK:
		return PackedByteArray()
	return hmac.finish()


## PBKDF2-HMAC-SHA256. The iteration bounds are part of the wire protocol: a
## hostile answer can't make a phone do no work or an unbounded amount.
static func pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iterations: int, length: int = 32) -> PackedByteArray:
	if not valid_wrap_iter(iterations) or length <= 0 or length > 1024 or salt.is_empty():
		return PackedByteArray()
	var out := PackedByteArray()
	var block := 1
	while out.size() < length:
		var index := PackedByteArray([(block >> 24) & 0xff, (block >> 16) & 0xff, (block >> 8) & 0xff, block & 0xff])
		var input := salt.duplicate()
		input.append_array(index)
		var u := hmac_sha256(password, input)
		if u.size() != 32:
			return PackedByteArray()
		var t := u.duplicate()
		for _iteration in range(1, iterations):
			var next_u := hmac_sha256(password, u)
			if next_u.size() != 32:
				return PackedByteArray()
			for i in 32:
				t[i] ^= next_u[i]
			_wipe(u)
			u = next_u
		out.append_array(t.slice(0, mini(32, length - out.size())))
		_wipe(u)
		_wipe(t)
		_wipe(input)
		block += 1
	return out


## K = HMAC-SHA256(secret, PBKDF2-HMAC-SHA256(PIN, salt, iter, 32)). Empty when anything is off.
static func wrap_key(pin: String, secret: PackedByteArray, salt: String, iterations: int) -> PackedByteArray:
	if secret.size() != PAIR_WRAP_SECRET_BYTES or not _valid_hex(salt, PAIR_WRAP_SALT_BYTES) or not valid_wrap_iter(iterations):
		return PackedByteArray()
	var pin_bytes := pin.to_utf8_buffer()
	var salt_bytes := salt.hex_decode()
	var stretched := pbkdf2_sha256(pin_bytes, salt_bytes, iterations, 32)
	_wipe(pin_bytes)
	_wipe(salt_bytes)
	if stretched.size() != 32:
		return PackedByteArray()
	var key := hmac_sha256(secret, stretched)
	_wipe(stretched)
	return key


static func _keystream(key: PackedByteArray, iterations: int, salt: String, nonce: String, length: int) -> PackedByteArray:
	var out := PackedByteArray()
	var prefix := "enc|1|%d|%s|%s|" % [iterations, salt, nonce]
	var block := 0
	while out.size() < length:
		var part := hmac_sha256(key, (prefix + str(block)).to_ascii_buffer())
		out.append_array(part)
		_wipe(part)
		block += 1
	var stream := out.slice(0, length)
	_wipe(out)
	return stream


static func _wrap_tag(key: PackedByteArray, iterations: int, salt: String, nonce: String, ct: String) -> String:
	var mac := hmac_sha256(key, ("tag|1|%d|%s|%s|%s" % [iterations, salt, nonce, ct]).to_ascii_buffer())
	var tag := mac.hex_encode().left(PAIR_WRAP_TAG_BYTES * 2)
	_wipe(mac)
	return tag


## Three words both screens show. `fingerprint`: SHA-256 (hex) of the PC's public key as the phone
## used it, so a phone that sealed its PIN to someone else's key sees different words than the PC.
static func phrase_for_token(token: String, fingerprint: String) -> String:
	if VERIFY_WORDS.size() != 64:
		return ""
	var token_bytes := token.to_utf8_buffer()
	var digest := hmac_sha256(token_bytes, (PAIR_VERIFY_LABEL + fingerprint).to_ascii_buffer())
	_wipe(token_bytes)
	if digest.size() != 32:
		return ""
	var words := PackedStringArray()
	for i in 3:
		words.append(VERIFY_WORDS[digest[i] % 64])
	_wipe(digest)
	return " ".join(words)


## The PC's side: encrypts and authenticates the 64-character token. {pair_v, ct, tag, phrase} or {}.
static func wrap_token(pin: String, secret: PackedByteArray, token: String, salt: String, nonce: String, iterations: int, fingerprint: String) -> Dictionary:
	if not _valid_hex(nonce, PAIR_WRAP_NONCE_BYTES) or not _valid_hex(token, TOKEN_BYTES):
		return {}
	var key := wrap_key(pin, secret, salt, iterations)
	if key.size() != 32:
		return {}
	var stream := _keystream(key, iterations, salt, nonce, TOKEN_BYTES * 2)
	var plain := token.to_ascii_buffer()
	for i in plain.size():
		plain[i] ^= stream[i]
	var ct := plain.hex_encode()
	var tag := _wrap_tag(key, iterations, salt, nonce, ct)
	_wipe(key)
	_wipe(stream)
	_wipe(plain)
	return {"pair_v": PAIR_WRAP_VERSION, "ct": ct, "tag": tag, "phrase": phrase_for_token(token, fingerprint)}


## The phone's side: checks the tag before anything else and fails closed. {ok, token, phrase} or
## {ok: false, error: PAIR_FAILED}. Nothing is returned that a caller could keep by mistake.
static func unwrap_token(pin: String, secret: PackedByteArray, salt: String, nonce: String, iterations: int, ct: String, tag: String, fingerprint: String) -> Dictionary:
	ct = ct.to_lower()
	tag = tag.to_lower()
	var failed := {"ok": false, "error": PAIR_FAILED}
	if not _valid_hex(nonce, PAIR_WRAP_NONCE_BYTES) or not _valid_hex(ct, TOKEN_BYTES * 2) or not _valid_hex(tag, PAIR_WRAP_TAG_BYTES):
		return failed
	var key := wrap_key(pin, secret, salt, iterations)
	if key.size() != 32:
		return failed
	if not HttpUtil.constant_time_equals(_wrap_tag(key, iterations, salt, nonce, ct), tag):
		_wipe(key)
		return failed
	var stream := _keystream(key, iterations, salt, nonce, TOKEN_BYTES * 2)
	var plain := ct.hex_decode()
	for i in plain.size():
		plain[i] ^= stream[i]
	var token := plain.get_string_from_ascii()
	_wipe(key)
	_wipe(stream)
	_wipe(plain)
	if not _valid_hex(token, TOKEN_BYTES):
		return failed
	return {"ok": true, "token": token, "phrase": phrase_for_token(token, fingerprint)}


## DER bytes inside a PEM block ("" lines and headers dropped).
static func der_from_pem(pem: String) -> PackedByteArray:
	var body := ""
	for line in pem.split("\n"):
		var l := line.strip_edges()
		if l != "" and not l.begins_with("-----"):
			body += l
	return Marshalls.base64_to_raw(body) if body != "" else PackedByteArray()


static func pem_from_der(der: PackedByteArray) -> String:
	var b64 := Marshalls.raw_to_base64(der)
	var lines := PackedStringArray(["-----BEGIN PUBLIC KEY-----"])
	for i in range(0, b64.length(), 64):
		lines.append(b64.substr(i, 64))
	lines.append("-----END PUBLIC KEY-----")
	return "\n".join(lines) + "\n"


## The phone's side of the request: from the PC's /api/pairing?wrap=1 answer and the typed PIN,
## {ok, body: {pair_v, salt, nonce, sealed}, open: {...what unwrap_token needs}} or {ok: false, error}.
static func seal_request(capability: Dictionary, pin: String) -> Dictionary:
	var failed := {"ok": false, "error": PAIR_FAILED}
	var salt := str(capability.get("salt", "")).to_lower()
	var iterations := _wire_int(capability.get("iter"))
	if _wire_int(capability.get("pair_v")) != PAIR_WRAP_VERSION or str(capability.get("kdf", "")) != PAIR_WRAP_KDF or str(capability.get("seal", "")) != PAIR_WRAP_SEAL:
		return failed
	if not valid_wrap_iter(iterations) or not _valid_hex(salt, PAIR_WRAP_SALT_BYTES):
		return failed
	var pub := str(capability.get("pub", ""))
	if pub.length() < 300 or pub.length() > 800 or pub.length() % 4 != 0 or not _is_base64(pub):
		return failed
	var der := Marshalls.base64_to_raw(pub)
	var key := CryptoKey.new()
	if der.size() < 200 or der.size() > 600 or key.load_from_string(pem_from_der(der), true) != OK:
		return failed
	var crypto := Crypto.new()
	var nonce := crypto.generate_random_bytes(PAIR_WRAP_NONCE_BYTES).hex_encode()
	var secret := crypto.generate_random_bytes(PAIR_WRAP_SECRET_BYTES)
	var message := ("%s|%s|%s|%s|%s" % [PAIR_SEAL_PREFIX, salt, nonce, secret.hex_encode(), pin]).to_ascii_buffer()
	var sealed := crypto.encrypt(key, message)
	_wipe(message)
	if sealed.size() != PAIR_WRAP_RSA_BYTES:
		_wipe(secret)
		return failed
	return {"ok": true, "body": {"pair_v": PAIR_WRAP_VERSION, "salt": salt, "nonce": nonce, "sealed": sealed.hex_encode()},
		"open": {"secret": secret, "salt": salt, "nonce": nonce, "iter": iterations, "fingerprint": HttpUtil.sha256_bytes(der)}}


## The phone's side of the answer (after seal_request): {ok, token, phrase} or {ok: false, error}.
## An answer without pair_v, or with a token field, is refused: this phone asked for pair_v:1.
static func open_answer(answer: Dictionary, pin: String, opener: Dictionary) -> Dictionary:
	var secret: PackedByteArray = opener.get("secret", PackedByteArray())
	if _wire_int(answer.get("pair_v")) != PAIR_WRAP_VERSION or answer.has("token"):
		_wipe(secret)
		return {"ok": false, "error": PAIR_FAILED}
	var opened := unwrap_token(pin, secret, str(opener.salt), str(opener.nonce), int(opener.iter),
		str(answer.get("ct", "")), str(answer.get("tag", "")), str(opener.fingerprint))
	_wipe(secret)
	if bool(opened.ok) and answer.has("phrase") and not HttpUtil.constant_time_equals(str(answer.phrase), str(opened.phrase)):
		return {"ok": false, "error": PAIR_FAILED}
	return opened


# --- Tokens -----------------------------------------------------------------------------------

## [PAIRING] Who sent this request (the parsed request: method, path, query, headers, body). Safe on
## the server thread too. {device} for a good Polox-Sig signature, or for a bearer key of a phone that
## paired the old way; {clock: true, now} when a signature's time is too far from the PC's; {replayed: true}
## for a nonce seen before; {} otherwise. A phone that paired with pair_v:1 signs: its bare key is refused.
func authenticate(req: Dictionary) -> Dictionary:
	var headers: Dictionary = req.get("headers", {})
	var auth := str(headers.get("authorization", ""))
	_mutex.lock()
	var result := {}
	if auth.to_lower().begins_with(RequestSig.SCHEME.to_lower() + " "):
		result = _check_signature_locked(req, auth)
	else:
		var device := check_token(HttpUtil.bearer(headers))
		if not device.is_empty() and bool(device.get("sig", false)):
			audit("bearer_refused device=%s" % str(device.get("id", "")))
		elif not device.is_empty():
			result = {"device": device}
	_mutex.unlock()
	return result


func _check_signature_locked(req: Dictionary, auth: String) -> Dictionary:
	var fields := RequestSig.parse(auth)
	if fields.is_empty():
		return {}
	var now_s := Time.get_unix_time_from_system()
	if absf(float(fields.ts) - now_s) > RequestSig.WINDOW_S:
		return {"clock": true, "now": int(now_s)}
	var body: PackedByteArray = req.get("body", PackedByteArray())
	var signed_target := RequestSig.canonical(str(req.get("path", "")), req.get("query", {}))
	var body_sha := HttpUtil.sha256_bytes(body)
	var found := {}
	for device: Dictionary in devices():   # every one, whichever matches: the same work for any request
		var expected := RequestSig.sign_with_hash(str(device.get("token_sha256", "")), str(req.get("method", "")), signed_target, int(fields.ts), str(fields.nonce), body_sha)
		if expected != "" and HttpUtil.constant_time_equals(expected, str(fields.sig)):
			found = device
	if found.is_empty():
		return {}
	_prune_nonces_locked(now_s)
	if _sig_nonces.has(fields.nonce):
		audit("sig_replayed device=%s" % str(found.get("id", "")))
		return {"replayed": true}
	if _sig_nonces.size() >= SIG_NONCES_MAX:
		audit("sig_busy nonces=%d" % _sig_nonces.size())
		return {"busy": true}
	_sig_nonces[fields.nonce] = now_s + RequestSig.WINDOW_S * 2.0   # outlives every time the window accepts
	return {"device": found, "nonce": fields.nonce}   # (a signed request: the answer is signed back)


func _prune_nonces_locked(now_s: float) -> void:
	if now_s - _sig_nonces_pruned < 30.0 and _sig_nonces.size() < SIG_NONCES_MAX:
		return
	_sig_nonces_pruned = now_s
	for nonce: String in _sig_nonces.keys():
		if float(_sig_nonces[nonce]) < now_s:
			_sig_nonces.erase(nonce)


## authenticate() for the server thread's /hello.json: only whether a paired phone sent it.
func request_is_paired(req: Dictionary) -> bool:
	return authenticate(req).has("device")


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
