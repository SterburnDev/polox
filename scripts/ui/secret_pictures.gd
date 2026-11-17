extends RefCounted
## [EASTER_EGG] The pictures the title screen's Music secret (settings_music_tab.gd) picks from.
##
## There are two sets, and a copy of the game uses exactly one of them:
##
##   Public   res://assets/secret/yam_*.svg: original drawings made for Polox by
##            tools/art/make_secret_yams.py. They are in the repository and in every public build.
##   Private  the pictures listed under "secret_images" in res://assets/local/addon.json (the private,
##            git-ignored content pack: docs/RELEASES.md). A private build has them; a public one can't.
##
## Either way the pictures are imported textures built into the game: nothing is read from a folder at
## run time and nothing is fetched, so the secret works offline on Windows, Android and the browser.
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
## The key in the private pack's addon.json: a list of picture paths inside that pack.
const PRIVATE_LIST_KEY := "secret_images"
const PICTURE_EXTENSIONS: PackedStringArray = ["jpg", "jpeg", "png", "webp", "svg"]


## Every picture this copy of the game shows: the private set when the pack lists any that are in the
## game, otherwise the public set.
static func all() -> PackedStringArray:
	var private_set := private_pictures(Addons.builtin_dir())
	return private_set if not private_set.is_empty() else _in_this_copy(PUBLIC_PICTURES)


## True when this copy uses the private pack's pictures.
static func uses_private_set() -> bool:
	return not private_pictures(Addons.builtin_dir()).is_empty()


## The private pack's pictures that are really in the game. `pack_dir` is the pack's folder
## (res://assets/local, or "" when this copy has no pack). Paths that leave the pack, aren't pictures
## or weren't imported are skipped, so a mistake in the list can't break the secret.
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


## One at random (null only if every one failed to load).
static func pick(rng: RandomNumberGenerator = null) -> Texture2D:
	var remaining := all()
	var random := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	while not remaining.is_empty():
		var index := random.randi_range(0, remaining.size() - 1)
		var texture := load_picture(remaining[index])
		if texture:
			return texture
		remaining.remove_at(index)   # (a broken file: try another)
	return null
