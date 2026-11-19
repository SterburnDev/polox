extends RefCounted
## [EASTER_EGG] The pictures the Settings > Music secret (`yams👀`) picks from.
##
## Every picture is an imported texture built right into the game (`res://`): nothing is read from an
## external OS folder at run time and nothing is fetched over the network, so it works offline on
## Windows, Android, and the browser.
##
## Two sets + keyword-armed Secret Vault (`aero`, `frutiger`, `code`, `rot`):
##   Public Yams   res://assets/secret/yam_*.svg (original drawings by tools/art/make_secret_yams.py)
##   Secret Vault  When the player types `aero`, `frutiger`, `code`, or `rot` in Settings > Music and
##                 clicks `yams👀`, Polox pulls from the built-in local secret pack
##                 (`res://assets/local/secret/*` listed under "secret_images" in addon.json) if
##                 present in this copy, or falls back to the 4 original public vault artworks
##                 (`res://assets/secret/vault_*.svg`).
## Tags: [EASTER_EGG]

const Addons := preload("res://scripts/core/addons.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const PUBLIC_PICTURES: PackedStringArray = [
	"res://assets/secret/yam_01_hello.svg",
	"res://assets/secret/yam_02_family.svg",
	"res://assets/secret/yam_03_afloat.svg",
	"res://assets/secret/yam_04_moonlight.svg",
	"res://assets/secret/yam_05_tower.svg",
	"res://assets/secret/yam_06_peek.svg",
	"res://assets/secret/yam_07_seaside.svg",
	"res://assets/secret/yam_08_garden.svg",
]

const SECRET_KEYWORDS: PackedStringArray = ["aero", "frutiger", "code", "rot"]

const PUBLIC_VAULT_PICTURES := {
	"aero": "res://assets/secret/vault_aero.svg",
	"frutiger": "res://assets/secret/vault_frutiger.svg",
	"code": "res://assets/secret/vault_code.svg",
	"rot": "res://assets/secret/vault_rot.svg",
}

## The key in the built-in local pack's addon.json: a list of picture paths inside that pack.
const PRIVATE_LIST_KEY := "secret_images"
const PICTURE_EXTENSIONS: PackedStringArray = ["jpg", "jpeg", "png", "webp", "svg"]


## Every default picture this copy can show: the private pack's set when built in, else the 8 public yams.
static func all() -> PackedStringArray:
	var private_set := private_pictures(Addons.builtin_dir())
	return private_set if not private_set.is_empty() else _in_this_copy(PUBLIC_PICTURES)


## True when this copy has a built-in local secret image pack (res://assets/local/secret/*).
static func uses_private_set() -> bool:
	return not private_pictures(Addons.builtin_dir()).is_empty()


## True when `word` is one of the secret vault trigger words (aero, frutiger, code, rot).
static func is_secret_keyword(word: String) -> bool:
	return word.to_lower() in SECRET_KEYWORDS


## Pictures available for the keyword-armed Secret Vault (`aero`, `frutiger`, `code`, `rot`):
## uses the built-in local secret pack when present, otherwise the original public vault drawings.
static func vault_all(keyword: String = "") -> PackedStringArray:
	var private_set := private_pictures(Addons.builtin_dir())
	if not private_set.is_empty():
		return private_set
	var lower := keyword.to_lower()
	if PUBLIC_VAULT_PICTURES.has(lower):
		var direct := str(PUBLIC_VAULT_PICTURES[lower])
		if ResourceLoader.exists(direct):
			return PackedStringArray([direct])
	var fallback := PackedStringArray()
	for key in SECRET_KEYWORDS:
		var path := str(PUBLIC_VAULT_PICTURES[key])
		if ResourceLoader.exists(path):
			fallback.append(path)
	return fallback if not fallback.is_empty() else _in_this_copy(PUBLIC_PICTURES)


## Validated built-in secret pictures listed in `pack_dir/addon.json` ("secret_images").
## Paths that escape the pack, use unsupported extensions, or aren't imported are skipped.
static func private_pictures(pack_dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if pack_dir == "":
		return out
	var manifest_path := pack_dir.path_join(Addons.MANIFEST)
	if not FileAccess.file_exists(manifest_path):
		return out
	var manifest: Variant = JsonUtil.parse(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or not (manifest as Dictionary).get(PRIVATE_LIST_KEY) is Array:
		return out
	for entry in (manifest as Dictionary)[PRIVATE_LIST_KEY]:
		var relative := str(entry).replace("\\", "/")
		var inside_pack := not relative.begins_with("/") and not relative.contains("..") and not relative.contains(":")
		if not inside_pack or not relative.get_extension().to_lower() in PICTURE_EXTENSIONS:
			continue
		var path := pack_dir.path_join(relative)
		if ResourceLoader.exists(path) and not path in out:
			out.append(path)
	return out


static func _in_this_copy(paths: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for path in paths:
		if ResourceLoader.exists(path):
			out.append(path)
	return out


static func load_picture(path: String) -> Texture2D:
	return load(path) as Texture2D


## Picks one texture at random from `all()` (null only if every entry failed to load).
static func pick(rng: RandomNumberGenerator = null) -> Texture2D:
	return _pick_from(all(), rng)


## Picks the texture for clicking `yams👀`:
## - When a secret keyword (`aero`, `frutiger`, `code`, `rot`) was typed: pulls from `vault_all(keyword)`
##   (built-in local secret images when present, or the matching public vault SVG).
## - Without a keyword: picks from Polox's 8 public yam artworks (classic `yams👀` Easter egg).
static func pick_for_secret(keyword: String = "", rng: RandomNumberGenerator = null) -> Texture2D:
	if is_secret_keyword(keyword):
		return _pick_from(vault_all(keyword), rng)
	var public_yams := _in_this_copy(PUBLIC_PICTURES)
	return _pick_from(public_yams if not public_yams.is_empty() else all(), rng)


static func _pick_from(pool: PackedStringArray, rng: RandomNumberGenerator = null) -> Texture2D:
	var remaining := pool.duplicate()
	var random := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	while not remaining.is_empty():
		var index := random.randi_range(0, remaining.size() - 1)
		var texture := load_picture(remaining[index])
		if texture:
			return texture
		remaining.remove_at(index)   # Broken entry: try another
	return null
