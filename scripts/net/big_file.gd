extends RefCounted
## /test/big: a ~20 MB file (the size of the game's .wasm) for the phone's
## Connection Test to download and check. Random bytes made once per run, in
## memory, with their SHA-256; the page fetches /test/big.json first, then
## hashes what arrived and compares. Thread-safe (the servers call it from
## their socket threads).

const SIZE := 20 * 1024 * 1024

static var _bytes := PackedByteArray()
static var _sha := ""
static var _mutex := Mutex.new()


## {bytes, sha256, size}. The first call takes a fraction of a second.
static func get_file() -> Dictionary:
	_mutex.lock()
	if _bytes.is_empty():
		_bytes = Crypto.new().generate_random_bytes(SIZE)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(_bytes)
		_sha = ctx.finish().hex_encode()
	var out := {"bytes": _bytes, "sha256": _sha, "size": _bytes.size()}
	_mutex.unlock()
	return out


static func meta() -> Dictionary:
	var f := get_file()
	return {"size": int(f.size), "sha256": str(f.sha256)}
