extends RefCounted
## Where animation frames live. A character's: characters/<id>/anims/<state>_<n>.png
## with `anims` in its character.json; a player form's: player/anims/<form>/...
## with `anims` in that form's data in world.json. Paths are relative to the
## world folder, so they travel with backups, bundles and Phone Link.
##
##   anims = {state: {frames: ["characters/mochi/anims/run_0.png", ...], fps, loop}}

const JsonUtil := preload("res://scripts/core/json_util.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")

const MAX_FRAMES := 8


## target = {kind: "character", id} or {kind: "player", form}
static func folder_rel(target: Dictionary) -> String:
	if str(target.get("kind", "")) == "player":
		return "player/anims/%s" % str(target.get("form", "real"))
	return "characters/%s/anims" % str(target.get("id", ""))


static func anims_of(target: Dictionary) -> Dictionary:
	var a: Variant
	if str(target.get("kind", "")) == "player":
		a = PlayerLook.form_data(str(target.get("form", "real"))).get("anims", {})
	else:
		a = GameState.get_character(str(target.get("id", ""))).get("anims", {})
	return a if a is Dictionary else {}


static func _store(target: Dictionary, anims: Dictionary) -> void:
	if str(target.get("kind", "")) == "player":
		var form := str(target.get("form", "real"))
		PlayerLook.set_field(form, "anims", anims)
	else:
		var c := GameState.get_character(str(target.get("id", "")))
		if c.is_empty():
			return
		c["anims"] = anims
		GameState.save_character(c)


## The frames of one state as Images ([] if none).
static func images(target: Dictionary, state: String) -> Array:
	var out: Array = []
	var a: Variant = anims_of(target).get(state)
	if not a is Dictionary:
		return out
	for p in a.get("frames", []):
		var img := SaveManager.load_picture(SaveManager.abs_path(str(p)))
		if img:
			out.append(img)
	return out


static func settings_of(target: Dictionary, state: String) -> Dictionary:
	var a: Variant = anims_of(target).get(state)
	return a if a is Dictionary else {}


## Writes a state's frames (replacing the old ones). An empty list removes the state.
static func save_state(target: Dictionary, state: String, frames: Array, fps: float, loop: bool) -> void:
	var folder := folder_rel(target)
	JsonUtil.ensure_dir(SaveManager.abs_path(folder))
	for f in DirAccess.get_files_at(SaveManager.abs_path(folder)):
		if f.begins_with(state + "_") and f.ends_with(".png"):
			DirAccess.remove_absolute(SaveManager.abs_path(folder).path_join(f))
			SaveManager.forget_texture(folder.path_join(f))
	var anims := anims_of(target).duplicate(true)
	if frames.is_empty():
		anims.erase(state)
	else:
		var rels: Array = []
		for i in mini(frames.size(), MAX_FRAMES):
			var rel := folder.path_join("%s_%d.png" % [state, i])
			(frames[i] as Image).save_png(SaveManager.abs_path(rel))
			SaveManager.forget_texture(rel)
			rels.append(rel)
		anims[state] = {"frames": rels, "fps": clampf(fps, 1.0, 24.0), "loop": loop}
	_store(target, anims)


## Cuts a horizontal sprite strip into square frames (height x height), at most 8.
static func slice_strip(img: Image) -> Array:
	var out: Array = []
	var h := img.get_height()
	if h <= 0:
		return out
	var n := clampi(img.get_width() / h, 1, MAX_FRAMES)
	for i in n:
		var f := img.get_region(Rect2i(i * h, 0, h, h))
		f.convert(Image.FORMAT_RGBA8)
		if not f.is_invisible():
			out.append(f)
	return out
