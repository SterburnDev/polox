extends RefCounted
## [PAIRING] Signed requests (sig v1): a phone that paired with pair_v:1 never sends its key again.
## Every request to the PC carries
##   Authorization: Polox-Sig v=1,ts=<unix seconds>,nonce=<32 hex>,sig=<64 hex>
##   sig = HMAC-SHA256(SHA-256(token) as bytes,
##         "polox-sig|1|<METHOD>|<target>|<ts>|<nonce>|<SHA-256 hex of the body>")
##   target = hex(UTF-8 of the decoded path) + "?" + the query's "hex(key)=hex(value)" pairs, sorted, joined by "&"
## The PC stores exactly SHA-256(token) per phone, so it checks the signature against every paired
## phone without keeping anything new. Decoded and hex-encoded, the target survives a proxy (Tailscale
## Serve, the bundled server) writing the address differently. The PC takes a time within WINDOW_S of
## its own and each nonce once; when the clocks are further apart it answers 401 {clock: true, now},
## and the phone corrects its offset and tries once more.
## The launcher has the same in JavaScript (launcher_page.gd, sigHeader).

const HttpUtil := preload("res://scripts/phone/http_util.gd")

const SCHEME := "Polox-Sig"
const VERSION := 1
const WINDOW_S := 300.0

## The PC's clock minus this device's (seconds), learned from the PC's answers.
static var clock_offset := 0


static func now() -> int:
	return int(Time.get_unix_time_from_system()) + clock_offset


## Takes the PC's time from an answer that has one ({now} in /api/pairing?wrap=1 and in a clock refusal).
static func learn_clock(answer: Variant) -> bool:
	if not answer is Dictionary or not (answer as Dictionary).has("now"):
		return false
	var pc_now: Variant = answer.now
	if not (pc_now is int or pc_now is float) or float(pc_now) < 1.0e9 or float(pc_now) > 1.0e10:
		return false
	clock_offset = int(pc_now) - int(Time.get_unix_time_from_system())
	return true


static func _hex(text: String) -> String:
	return text.to_utf8_buffer().hex_encode()


## The signed form of a decoded path and query (what the PC's request parser gives).
static func canonical(path: String, query: Dictionary) -> String:
	var pairs := {}
	for k in query:
		pairs[_hex(str(k))] = _hex(str(query[k]))
	var keys: Array = pairs.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%s" % [k, pairs[k]])
	return _hex(path) + "?" + "&".join(parts)


## The same from an address as the phone sends it ("/api/file?path=slots%2Fa%2Fworld.json", or a full URL).
static func target(url: String) -> String:
	var rest := url
	var scheme_end := rest.find("://")
	if scheme_end >= 0:
		var slash := rest.find("/", scheme_end + 3)
		rest = rest.substr(slash) if slash >= 0 else "/"
	var q := rest.find("?")
	var raw_path := rest.substr(0, q) if q >= 0 else rest
	return canonical(HttpUtil.url_decode(raw_path), HttpUtil.parse_query(rest.substr(q + 1)) if q >= 0 else {})


static func message(method: String, signed_target: String, ts: int, nonce: String, body_sha256: String) -> String:
	return "polox-sig|%d|%s|%s|%d|%s|%s" % [VERSION, method.to_upper(), signed_target, ts, nonce, body_sha256]


static func _hmac(key: PackedByteArray, text: String) -> String:
	var ctx := HMACContext.new()
	if ctx.start(HashingContext.HASH_SHA256, key) != OK or ctx.update(text.to_utf8_buffer()) != OK:
		return ""
	return ctx.finish().hex_encode()


## The signature for a stored key hash (64 hex, what devices.json keeps).
static func sign_with_hash(token_sha256: String, method: String, signed_target: String, ts: int, nonce: String, body_sha256: String) -> String:
	var key := token_sha256.hex_decode()
	if key.size() != 32:
		return ""
	var sig := _hmac(key, message(method, signed_target, ts, nonce, body_sha256))
	key.fill(0)
	return sig


## The whole header line for a request ("Authorization: Polox-Sig ...").
static func header(token: String, method: String, url: String, body: PackedByteArray = PackedByteArray()) -> String:
	var ts := now()
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	var sig := sign_with_hash(HttpUtil.sha256_bytes(token.to_utf8_buffer()), method, target(url), ts, nonce, HttpUtil.sha256_bytes(body))
	return "Authorization: %s v=%d,ts=%d,nonce=%s,sig=%s" % [SCHEME, VERSION, ts, nonce, sig]


## {ts, nonce, sig} from an Authorization value, or {} when it isn't a well-formed Polox-Sig v1.
static func parse(value: String) -> Dictionary:
	if not value.to_lower().begins_with(SCHEME.to_lower() + " "):
		return {}
	var fields := {}
	for part in value.substr(SCHEME.length() + 1).split(",", false):
		var eq := part.find("=")
		if eq > 0:
			fields[part.substr(0, eq).strip_edges().to_lower()] = part.substr(eq + 1).strip_edges()
	var ts := str(fields.get("ts", ""))
	var nonce := str(fields.get("nonce", "")).to_lower()
	var sig := str(fields.get("sig", "")).to_lower()
	if str(fields.get("v", "")) != str(VERSION) or not ts.is_valid_int() or ts.length() > 12 or not _lower_hex(nonce, 32) or not _lower_hex(sig, 64):
		return {}
	return {"ts": ts.to_int(), "nonce": nonce, "sig": sig}


static func _lower_hex(value: String, length: int) -> bool:
	if value.length() != length:
		return false
	for i in value.length():
		var c := value.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true
