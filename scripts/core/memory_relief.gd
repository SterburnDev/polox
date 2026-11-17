extends RefCounted
## What the game lets go when the phone runs short of memory (NOTIFICATION_OS_MEMORY_WARNING, which main.gd
## hears: Android's warnings come through Polox's plugin, see android_native.gd). Only pictures and sounds
## kept to be quick next time: each is made again when it's next needed, and whatever is on screen or
## playing keeps its own copy, so nothing visible or audible changes.

const Synth := preload("res://scripts/core/synth.gd")
const Ambience := preload("res://scripts/world/ambience.gd")
const SurfaceDetail := preload("res://scripts/world/surface_detail.gd")
const ItemArt := preload("res://scripts/items/item_art.gd")
const VectorIcons := preload("res://scripts/ui/vector_icons.gd")
const SilhouettePainter := preload("res://scripts/world/silhouette_painter.gd")
const PlayerLook := preload("res://scripts/characters/player_look.gd")

static var releases := 0   # (tests, the phone's report) how many warnings were answered

## What scripts keep for the whole run in a static variable, made by the renderer or the audio server:
## meshes, materials, shaders, pictures, sounds. [script, the variables that hold them]. Named here,
## not preloaded: only the scripts this run really used are touched (release_at_exit), and a script
## never becomes part of every start just to have its empty cache emptied. Variables that go together
## (a picture and what was measured from it) are listed together, so each cache is rebuilt whole.
const AT_EXIT := [
	["res://scripts/core/synth.gd", ["_cache"]],
	["res://scripts/world/ambience.gd", ["_cache"]],
	["res://scripts/world/surface_detail.gd", ["_cache"]],
	["res://scripts/items/item_art.gd", ["_cache"]],
	["res://scripts/ui/vector_icons.gd", ["_cache"]],
	["res://scripts/world/silhouette_painter.gd", ["_cache"]],
	["res://scripts/characters/player_look.gd", ["_cache"]],
	["res://scripts/world/block_factory.gd", ["_mat_cache", "_parts_cache", "_plant_tex", "_sign_face_tex"]],
	["res://scripts/world/furniture.gd", ["_mats"]],
	["res://scripts/world/licensed_props.gd", ["_baked", "_paints", "_bounds"]],
	["res://scripts/world/surface_materials.gd", ["_tex", "_mats", "_shader"]],
	["res://scripts/world/edge_walls.gd", ["_shader", "_glass_shader", "_floor_shader", "_building_shader", "_street_shader"]],
	["res://scripts/world/tile_atlas.gd", ["_atlases"]],
	["res://scripts/world/tilesets.gd", ["_cache"]],
	["res://scripts/battle/battle_audio.gd", ["_cache"]],
	["res://scripts/battle/bullet_art.gd", ["_tex", "_mask", "_stamp", "_checked", "_active_custom"]],
	["res://scripts/characters/actor.gd", ["_emote_tex"]],
	["res://scripts/characters/actor_anim.gd", ["_puff"]],
	["res://scripts/builder/build_ghost.gd", ["_dot"]],
	["res://scripts/builder/editor_palette.gd", ["_thumbs"]],
	["res://scripts/ui/soul.gd", ["_tex"]],
	["res://scripts/core/addons.gd", ["_tex_cache"]],
]


static func release() -> void:
	Synth.clear_cache()
	Ambience.clear_cache()
	SurfaceDetail.clear_cache()
	ItemArt.clear_cache()
	VectorIcons.clear_cache()
	SilhouettePainter.clear_cache()
	PlayerLook.invalidate()
	releases += 1


## The game is closing (game_state.gd, the last of the game to leave the tree): every cache in AT_EXIT
## is emptied, so no mesh, material, shader, picture or sound made during the run is still held by a
## script when the renderer and the audio server shut down. What is on screen keeps its own until its
## node is freed, a moment later. Returns how many variables were emptied (tests).
static func release_at_exit() -> int:
	var emptied := 0
	for entry in AT_EXIT:
		var path := str(entry[0])
		if not ResourceLoader.has_cached(path):
			continue   # never used in this run: nothing was kept
		var script := load(path) as Script
		if script == null:
			continue
		for name in entry[1]:
			var held: Variant = script.get(name)
			if held is Dictionary:
				(held as Dictionary).clear()
			elif held is Array:
				(held as Array).clear()
			elif held != null:
				script.set(name, null)
			else:
				continue
			emptied += 1
	return emptied
