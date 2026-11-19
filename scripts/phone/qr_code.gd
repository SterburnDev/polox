extends RefCounted
## A small QR code encoder (byte mode, error correction level M, versions
## 1-10: up to 213 bytes), so the PC can show the Phone Link address as a
## QR code without any library or network. Follows the QR spec (ISO 18004):
## Reed-Solomon over GF(256), interleaved blocks, all 8 masks scored with the
## standard penalty rules.

## Per version (index 0 = version 1), level M.
const TOTAL_CODEWORDS := [26, 44, 70, 100, 134, 172, 196, 242, 292, 346]
const EC_PER_BLOCK := [10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
const BLOCKS := [1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
const ALIGNMENT := [[], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]]
const FORMAT_BITS_M := 0

var version := 1
var size := 21
var modules: Array = []      # [row][col] -> bool (dark)
var _function: Array = []    # [row][col] -> bool (reserved)


## Encodes text. Returns null if it's too long for version 10.
static func encode(text: String) -> RefCounted:
	var data := text.to_utf8_buffer()
	for v in range(1, 11):
		var count_bits := 8 if v < 10 else 16
		var cap_bits: int = (int(TOTAL_CODEWORDS[v - 1]) - int(EC_PER_BLOCK[v - 1]) * int(BLOCKS[v - 1])) * 8
		if 4 + count_bits + data.size() * 8 <= cap_bits:
			var q: RefCounted = load("res://scripts/phone/qr_code.gd").new()
			q._build(v, data)
			return q
	return null


func _build(v: int, data: PackedByteArray) -> void:
	version = v
	size = 17 + 4 * v
	modules = []
	_function = []
	for y in size:
		var row: Array = []
		row.resize(size)
		row.fill(false)
		modules.append(row)
		_function.append(row.duplicate())
	_draw_function_patterns()
	var codewords := _add_ecc_and_interleave(_data_codewords(data))
	_draw_codewords(codewords)
	var best := 0
	var best_score := -1
	for mask in 8:
		_apply_mask(mask)
		_draw_format_bits(mask)
		var score := _penalty()
		if best_score < 0 or score < best_score:
			best = mask
			best_score = score
		_apply_mask(mask)  # XOR again = undo
	_apply_mask(best)
	_draw_format_bits(best)


func dark(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size and y < size and bool(modules[y][x])


## A crisp black-on-white picture with the standard 4-module quiet zone.
func to_image(scale: int = 8) -> Image:
	var n := (size + 8) * scale
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in size:
		for x in size:
			if modules[y][x]:
				img.fill_rect(Rect2i((x + 4) * scale, (y + 4) * scale, scale, scale), Color.BLACK)
	return img


# --- Function patterns ------------------------------------------------------------------------

func _set_function(x: int, y: int, is_dark: bool) -> void:
	modules[y][x] = is_dark
	_function[y][x] = true


func _draw_function_patterns() -> void:
	for i in size:
		_set_function(6, i, i % 2 == 0)
		_set_function(i, 6, i % 2 == 0)
	_draw_finder(3, 3)
	_draw_finder(size - 4, 3)
	_draw_finder(3, size - 4)
	var pos: Array = ALIGNMENT[version - 1]
	var last := pos.size() - 1
	for i in pos.size():
		for j in pos.size():
			if (i == 0 and j == 0) or (i == 0 and j == last) or (i == last and j == 0):
				continue
			_draw_alignment(int(pos[i]), int(pos[j]))
	_draw_format_bits(0)  # reserves the area; the real bits come after masking
	_draw_version()


func _draw_finder(cx: int, cy: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var dist := maxi(absi(dx), absi(dy))
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and y >= 0 and x < size and y < size:
				_set_function(x, y, dist != 2 and dist != 4)


func _draw_alignment(cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_function(cx + dx, cy + dy, maxi(absi(dx), absi(dy)) != 1)


static func _bit(value: int, i: int) -> bool:
	return ((value >> i) & 1) != 0


func _draw_format_bits(mask: int) -> void:
	var data := (FORMAT_BITS_M << 3) | mask
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	for i in range(0, 6):
		_set_function(8, i, _bit(bits, i))
	_set_function(8, 7, _bit(bits, 6))
	_set_function(8, 8, _bit(bits, 7))
	_set_function(7, 8, _bit(bits, 8))
	for i in range(9, 15):
		_set_function(14 - i, 8, _bit(bits, i))
	for i in range(0, 8):
		_set_function(size - 1 - i, 8, _bit(bits, i))
	for i in range(8, 15):
		_set_function(8, size - 15 + i, _bit(bits, i))
	_set_function(8, size - 8, true)  # the dark module


func _draw_version() -> void:
	if version < 7:
		return
	var rem := version
	for i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	var bits := (version << 12) | rem
	for i in 18:
		var b := _bit(bits, i)
		var a := size - 11 + i % 3
		var c := i / 3
		_set_function(a, c, b)
		_set_function(c, a, b)


# --- Data -----------------------------------------------------------------------------------------

func _data_codewords(data: PackedByteArray) -> PackedByteArray:
	var cap: int = int(TOTAL_CODEWORDS[version - 1]) - int(EC_PER_BLOCK[version - 1]) * int(BLOCKS[version - 1])
	var bits: Array[int] = []
	_append_bits(bits, 0b0100, 4)
	_append_bits(bits, data.size(), 8 if version < 10 else 16)
	for b in data:
		_append_bits(bits, b, 8)
	var cap_bits := cap * 8
	_append_bits(bits, 0, mini(4, cap_bits - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var out := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var byte := 0
		for j in 8:
			byte = (byte << 1) | bits[i + j]
		out.append(byte)
	var pad := 0xEC
	while out.size() < cap:
		out.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC
	return out


static func _append_bits(bits: Array[int], value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


func _add_ecc_and_interleave(data: PackedByteArray) -> PackedByteArray:
	var num_blocks: int = BLOCKS[version - 1]
	var ecc_len: int = EC_PER_BLOCK[version - 1]
	var raw: int = TOTAL_CODEWORDS[version - 1]
	var num_short := num_blocks - raw % num_blocks
	var short_len := raw / num_blocks
	var divisor := _rs_divisor(ecc_len)
	var blocks: Array = []
	var k := 0
	for i in num_blocks:
		var dat_len := short_len - ecc_len + (0 if i < num_short else 1)
		var dat := data.slice(k, k + dat_len)
		k += dat_len
		var ecc := _rs_remainder(dat, divisor)
		if i < num_short:
			dat.append(0)  # placeholder so every block has the same length
		dat.append_array(ecc)
		blocks.append(dat)
	var out := PackedByteArray()
	for i in (blocks[0] as PackedByteArray).size():
		for j in blocks.size():
			if i != short_len - ecc_len or j >= num_short:
				out.append((blocks[j] as PackedByteArray)[i])
	return out


static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z


static func _rs_divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result.fill(0)
	result[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 0x02)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(divisor.size())
	result.fill(0)
	for b in data:
		var factor := b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i in result.size():
			result[i] ^= _gf_mul(divisor[i], factor)
	return result


func _draw_codewords(data: PackedByteArray) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if not _function[y][x] and i < data.size() * 8:
					modules[y][x] = _bit(data[i >> 3], 7 - (i & 7))
					i += 1
		right -= 2


func _apply_mask(mask: int) -> void:
	for y in size:
		for x in size:
			if _function[y][x]:
				continue
			var invert := false
			match mask:
				0:
					invert = (x + y) % 2 == 0
				1:
					invert = y % 2 == 0
				2:
					invert = x % 3 == 0
				3:
					invert = (x + y) % 3 == 0
				4:
					invert = (x / 3 + y / 2) % 2 == 0
				5:
					invert = x * y % 2 + x * y % 3 == 0
				6:
					invert = (x * y % 2 + x * y % 3) % 2 == 0
				7:
					invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				modules[y][x] = not modules[y][x]


## The standard penalty: long runs, 2x2 blocks, finder look-alikes, dark balance.
func _penalty() -> int:
	var score := 0
	for horizontal in [true, false]:
		for a in size:
			var run := 1
			for b in range(1, size):
				var cur := dark(b, a) if horizontal else dark(a, b)
				var prev := dark(b - 1, a) if horizontal else dark(a, b - 1)
				if cur == prev:
					run += 1
					if run == 5:
						score += 3
					elif run > 5:
						score += 1
				else:
					run = 1
			for b in range(0, size - 10):
				var p1 := true
				var p2 := true
				var pat := [true, false, true, true, true, false, true, false, false, false, false]
				for k in 11:
					var v := dark(b + k, a) if horizontal else dark(a, b + k)
					p1 = p1 and v == pat[k]
					p2 = p2 and v == pat[10 - k]
				if p1:
					score += 40
				if p2:
					score += 40
	var dark_count := 0
	for y in size:
		for x in size:
			if dark(x, y):
				dark_count += 1
			if x < size - 1 and y < size - 1:
				var c := dark(x, y)
				if c == dark(x + 1, y) and c == dark(x, y + 1) and c == dark(x + 1, y + 1):
					score += 3
	var total := size * size
	var k := ceili(absf(dark_count * 20.0 - total * 10.0) / total) - 1
	score += maxi(0, k) * 10
	return score
