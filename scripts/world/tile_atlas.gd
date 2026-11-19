extends RefCounted
## One texture per tile set (built at run time from the set's pictures), so a
## whole chunk of a layer that uses that set draws as ONE mesh. Each tile gets a
## row slot of MAX_FRAMES cells (frame 0, 1, 2, 3 side by side), which lets the
## shader animate it by sliding the UV, with no work on the CPU.
## Rebuilt automatically when the set changes on disk.

const Tilesets := preload("res://scripts/world/tilesets.gd")

const MAX_TEX := 8192

static var _atlases := {}   # set dir -> {stamp, texture, tp, cols, slots: {tile: [slot, frames, fps]}, w, h}


## {texture, tp, w, h, slots} for a set of the active world ({} if it has no tiles).
static func for_set(set_id: String) -> Dictionary:
	var s := Tilesets.cached_set(set_id)
	if s.is_empty():
		return {}
	var dir := Tilesets.set_dir(set_id)
	var meta_path := dir.path_join(Tilesets.META)
	var stamp := FileAccess.get_sha256(meta_path) if FileAccess.file_exists(meta_path) else ""
	var cached: Dictionary = _atlases.get(dir, {})
	if not cached.is_empty() and str(cached.stamp) == stamp:
		return cached
	var tiles: Array = s.get("tiles", [])
	if tiles.is_empty():
		return {}
	var tp := clampi(int(s.get("tile_size", 32)), 4, 256)
	var per_row := 1
	while ceili(tiles.size() / float(per_row)) * tp > MAX_TEX and per_row * Tilesets.MAX_FRAMES * tp < MAX_TEX:
		per_row += 1
	var rows := ceili(tiles.size() / float(per_row))
	var w := per_row * Tilesets.MAX_FRAMES * tp
	var h := rows * tp
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var slots := {}
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		var id := str(t.id)
		var base := Vector2i((i % per_row) * Tilesets.MAX_FRAMES * tp, (i / per_row) * tp)
		var frames := 1 + mini((t.get("frames", []) as Array).size(), Tilesets.MAX_FRAMES - 1)
		var drawn := 0
		for f in frames:
			var pic := Tilesets.tile_image(set_id, id, f)
			if pic == null:
				break
			pic.convert(Image.FORMAT_RGBA8)
			if pic.get_size() != Vector2i(tp, tp):
				pic.resize(tp, tp, Image.INTERPOLATE_NEAREST)
			img.blit_rect(pic, Rect2i(0, 0, tp, tp), base + Vector2i(f * tp, 0))
			drawn += 1
		if drawn > 0:
			slots[id] = [base, drawn, maxf(1.0, float(t.get("fps", 4)))]
	var entry := {"stamp": stamp, "texture": ImageTexture.create_from_image(img), "tp": tp, "w": w, "h": h, "slots": slots}
	_atlases[dir] = entry
	return entry


## UV corners (u0, v0, u1, v1) of a tile's first frame, inset half a pixel so
## neighbours never bleed in. Empty if the tile isn't in the atlas.
static func uv_rect(atlas: Dictionary, tile_id: String) -> Array:
	var slot: Variant = (atlas.get("slots", {}) as Dictionary).get(tile_id)
	if slot == null:
		return []
	var base: Vector2i = slot[0]
	var tp := float(atlas.tp)
	var w := float(atlas.w)
	var h := float(atlas.h)
	return [(base.x + 0.5) / w, (base.y + 0.5) / h, (base.x + tp - 0.5) / w, (base.y + tp - 0.5) / h]


static func clear() -> void:
	_atlases.clear()
