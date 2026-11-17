extends RefCounted
## Loading and saving of the Creator's faces (PNG files on disk), kept apart
## from the Creator's UI so both stay small and the file logic is testable.

const Defaults := preload("res://scripts/core/defaults.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const GRIDS := [16, 32, 64, 128]


static func blank(n: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func has_pixels(img: Image) -> bool:
	return img != null and not img.is_invisible()


## Every face slot for a character (the 8 defaults + its custom ones), all at
## one grid size taken from the neutral face. In avatar mode the faces come
## from the player's form data["form"]. Returns {order: Array, slots: {name: Image}}.
static func load_slots(data: Dictionary, avatar_mode: bool) -> Dictionary:
	const PlayerLook := preload("res://scripts/characters/player_look.gd")
	var names: Array = []
	names.append_array(Defaults.DEFAULT_EXPRESSIONS)
	var faces: Dictionary = PlayerLook.form_data(str(data.get("form", "real"))).expressions if avatar_mode else data.get("expressions", {})
	for e in faces:
		if not e in names:
			names.append(str(e))
	var grid := 32
	var images := {}
	for n in names:
		var path := ""
		if avatar_mode:
			path = SaveManager.abs_path(str(faces.get(n, ""))) if str(faces.get(n, "")) != "" else ""
		else:
			path = SaveManager.expression_path(data, n)
		if path == "" or not FileAccess.file_exists(path):
			continue
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			images[n] = img
			if n == "neutral" or images.size() == 1:
				grid = img.get_width() if img.get_width() in GRIDS else 32
	var slots := {}
	for n in names:
		var img: Image = images.get(n, blank(grid))
		if img.get_size() != Vector2i(grid, grid):
			img.resize(grid, grid, Image.INTERPOLATE_NEAREST)
		slots[n] = img
	return {"order": names, "slots": slots}


## Writes every painted face to characters/<id>/expressions/ and deletes
## removed ones. Returns the {emotion: relative path} map for character.json.
static func save_faces(char_id: String, order: Array, slots: Dictionary, removed: Array) -> Dictionary:
	var dir := SaveManager.character_dir(char_id)
	JsonUtil.ensure_dir(dir.path_join("expressions"))
	var exprs := {}
	for n in order:
		if has_pixels(slots[n]):
			var rel := "expressions/%s.png" % n
			slots[n].save_png(dir.path_join(rel))
			SaveManager.forget_texture(dir.path_join(rel))
			exprs[n] = rel
	for n in removed:
		if not slots.has(n):
			DirAccess.remove_absolute(dir.path_join("expressions/%s.png" % n))
	return exprs
