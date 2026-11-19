extends RefCounted
## Seasonal decorations from the real date: string lights along the walls and
## a few small things in the corners for holiday weeks (Halloween, winter
## holidays, New Year, Valentine's, the spring equinox, midsummer), your
## birthday and the dates you celebrate, plus a quiet season touch (autumn
## leaves, winter snow, spring flowers, a summer sunflower).
## Purely visual: no collision, never written to the room's file, rebuilt with
## the room. The Time Machine moves it too. Off in Settings > Game.

const Clock := preload("res://scripts/variety/clock.gd")
const Seasons := preload("res://scripts/world/seasons.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")
const PlatformObjects := preload("res://scripts/platform/platform_objects.gd")

## [theme, first "MM-DD", last "MM-DD"] (a window may wrap past New Year).
const WINDOWS := [
	["new_year", "12-31", "01-02"], ["valentine", "02-08", "02-14"], ["spring", "03-20", "03-27"],
	["midsummer", "06-19", "06-24"], ["halloween", "10-15", "10-31"], ["winter", "12-08", "12-31"],
]
const LIGHTS := {
	"winter": ["#ff5d5d", "#7dff9a", "#ffd166", "#7ab8ff"], "halloween": ["#ff9a3c", "#b07cff"],
	"valentine": ["#ff7aa8", "#ff4d6d", "#ffd1dc"], "new_year": ["#ffd166", "#e8e8ff"],
	"party": ["#ff5d5d", "#ffd166", "#7dff9a", "#7ab8ff", "#ff7aa8"], "spring": ["#ffd1dc", "#c8f7c5", "#fff3b0"],
	"midsummer": ["#ffcf70", "#fff3b0"],
}
const SEASON_ACCENT := {"autumn": "leaves", "winter": "snow", "spring": "flowers", "summer": "sunflower"}


static func enabled() -> bool:
	return bool(GameState.world.get("settings", {}).get("seasonal_decor", true))


## What's up today: {"themes": [...], "accent": "leaves"|..., "names": [...]}.
static func today(date: String = "") -> Dictionary:
	var d := date if date != "" else Clock.today()
	var parts := d.split("-")
	if parts.size() != 3:
		return {"themes": [], "accent": "", "names": []}
	var md := d.substr(5)
	var themes: Array = []
	for w in WINDOWS:
		if _in_window(md, str(w[1]), str(w[2])):
			themes.append(str(w[0]))
	var names: Array = []
	var dt := {"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2])}
	var h := Seasons.holiday(dt)
	if str(h.get("id", "")) == "birthday":
		themes.push_front("party")
		names.append(str(h.name))
	for c in VarietySave.data().get("celebrations", []):
		if c is Dictionary and str(c.get("date", "")) == md:
			if not themes.has("party"):
				themes.push_front("party")
			names.append(str(c.get("name", "a special day")))
	return {"themes": themes, "accent": str(SEASON_ACCENT.get(Seasons.season(dt), "")), "names": names}


static func _in_window(md: String, first: String, last: String) -> bool:
	if first <= last:
		return md >= first and md <= last
	return md >= first or md <= last   # wraps past New Year


## Builds today's decorations into a built room (room_view.gd). Cheap to call
## often: it only rebuilds when the date, the switch or the room changed.
## Returns the decor root (empty when there's nothing today or it's off).
static func build(room: Node3D, date: String = "") -> Node3D:
	if room == null or room.get("_content") == null:
		return null
	var content: Node3D = room.get("_content")
	var day := date if date != "" else Clock.today()
	var key := "%s|%s" % [day, enabled()]
	var old := content.get_node_or_null("SeasonalDecor")
	if old and str(old.get_meta("key", "")) == key:
		return old
	clear(room)
	var root := Node3D.new()
	root.name = "SeasonalDecor"
	root.set_meta("key", key)
	content.add_child(root)
	if not enabled():
		root.set_meta("themes", [])
		root.set_meta("accent", "")
		return root
	var t := today(day)
	var themes: Array = t.themes
	root.set_meta("themes", themes.duplicate())
	root.set_meta("accent", str(t.accent))
	var corners := _corners(room)
	if not themes.is_empty():
		var main := str(themes[0])
		_lights(room, LIGHTS.get(main, LIGHTS.party), root)
		for i in mini(corners.size(), 2):
			root.add_child(_corner_piece(main, room.cell_center(corners[i]), i))
		if themes.size() > 1 and corners.size() > 2:
			root.add_child(_corner_piece(str(themes[1]), room.cell_center(corners[2]), 2))
	if str(t.accent) != "" and corners.size() > 3:
		root.add_child(_accent(str(t.accent), room.cell_center(corners[3])))
	return root


static func clear(room: Node3D) -> void:
	var content: Node3D = room.get("_content")
	if content == null:
		return
	var old := content.get_node_or_null("SeasonalDecor")
	if old:
		content.remove_child(old)
		old.queue_free()
	var walls: Dictionary = room.get("_walls")
	for side in walls:
		var wall: Node = walls[side][0]
		for b in wall.get_children():
			if b.has_meta("seasonal"):
				wall.remove_child(b)
				b.queue_free()


## The four corner cells (or the walkable cells nearest them), back corners first.
static func _corners(room: Node3D) -> Array:
	var out: Array = []
	var w: int = room.w
	var d: int = room.d
	for c in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, d - 1), Vector2i(w - 1, d - 1)]:
		var cell: Vector2i = c if room.nav.walkable(c) else room.nav.nearest_walkable(c)
		if not out.has(cell):
			out.append(cell)
	return out


## A string of little glowing bulbs along the top of each wall (they hide with the wall).
static func _lights(room: Node3D, colors: Array, root: Node3D) -> void:
	var walls: Dictionary = room.get("_walls")
	var y: float = room.h - 0.25
	var bulb := SphereMesh.new()
	bulb.radius = 0.06
	bulb.height = 0.12
	bulb.radial_segments = 8
	bulb.rings = 4
	var count := 0
	for side in walls:
		var wall: Node3D = walls[side][0]
		var normal: Vector3 = walls[side][2]
		var along := Vector3(1, 0, 0) if absf(normal.z) > 0.5 else Vector3(0, 0, 1)
		var length: float = room.w if absf(normal.z) > 0.5 else room.d
		var n := maxi(3, int(length / 0.5))
		for i in n:
			var f := (i + 0.5) / n
			var sag := sin(f * PI * 6.0) * 0.06
			var b := MeshInstance3D.new()
			b.mesh = bulb
			b.material_override = PlatformObjects.glow(Color(str(colors[i % colors.size()])), 1.6)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Local to the wall: centred on it, nudged inward (away from the outside normal).
			b.position = along * (f - 0.5) * length + Vector3(0, y - wall.position.y - absf(sag), 0) - normal * 0.16
			b.set_meta("seasonal", true)
			wall.add_child(b)
			count += 1
	root.set_meta("bulbs", count)


static func _mesh(m: Mesh, color: String, pos: Vector3, energy: float = 0.25, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = PlatformObjects.glow(Color(color), energy)
	mi.position = pos
	mi.scale = scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _glyph(text: String, color: String, pos: Vector3, size: int = 96) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.modulate = Color(color)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	l.pixel_size = 0.005
	l.outline_size = 8
	l.outline_modulate = Color("#120e24")
	l.position = pos
	return l


## A small thing for a holiday corner.
static func _corner_piece(theme: String, at: Vector3, i: int) -> Node3D:
	var n := Node3D.new()
	n.name = "Decor_%s_%d" % [theme, i]
	n.position = Vector3(at.x, 0, at.z)
	match theme:
		"halloween":
			n.add_child(_mesh(_sphere(0.24), "#ff8a2a", Vector3(0, 0.2, 0), 0.35, Vector3(1.2, 0.85, 1.2)))
			var stem := CylinderMesh.new()
			stem.radial_segments = 12
			stem.rings = 1
			stem.top_radius = 0.03
			stem.bottom_radius = 0.04
			stem.height = 0.1
			n.add_child(_mesh(stem, "#4a7a3a", Vector3(0, 0.42, 0)))
			for ex in [-0.08, 0.08]:   # glowing eyes, so it reads as a jack-o'-lantern
				n.add_child(_mesh(_sphere(0.035), "#ffe08a", Vector3(ex, 0.26, 0.27), 2.0))
		"winter":
			var cone := CylinderMesh.new()
			cone.radial_segments = 12
			cone.rings = 1
			cone.top_radius = 0.0
			cone.bottom_radius = 0.32
			cone.height = 0.8
			n.add_child(_mesh(cone, "#2f8a55", Vector3(0, 0.5, 0), 0.2))
			n.add_child(_glyph("★", "#ffd166", Vector3(0, 1.0, 0), 72))
			for k in 5:
				var a := k * TAU / 5.0
				n.add_child(_mesh(_sphere(0.04), ["#ff5d5d", "#ffd166", "#7ab8ff"][k % 3], Vector3(cos(a) * 0.2, 0.35 + k * 0.05, sin(a) * 0.2), 1.2))
		"new_year", "party":
			for k in 3:
				var col := str((["#ffd166", "#e8e8ff", "#ffcf70"] if theme == "new_year" else ["#ff5d5d", "#7ab8ff", "#ff7aa8"])[k])
				var off := Vector3((k - 1) * 0.2, 1.1 + 0.12 * (k % 2), (k % 2) * 0.12)
				n.add_child(_mesh(_sphere(0.15), col, off, 0.4, Vector3(1, 1.2, 1)))
				var string := CylinderMesh.new()
				string.radial_segments = 12
				string.rings = 1
				string.top_radius = 0.005
				string.bottom_radius = 0.005
				string.height = off.y - 0.15
				n.add_child(_mesh(string, "#e8e8ff", Vector3(off.x, (off.y - 0.15) / 2.0, off.z)))
		"valentine":
			n.add_child(_glyph("♥", "#ff7aa8", Vector3(0, 0.9, 0), 120))
			n.add_child(_glyph("♥", "#ff4d6d", Vector3(0.18, 0.6, 0.1), 80))
		"spring":
			n.add_child(_flowers(["#ffd1dc", "#fff3b0", "#c8b6ff"]))
		"midsummer":
			n.add_child(_mesh(_sphere(0.16), "#ffcf70", Vector3(0, 0.9, 0), 1.6, Vector3(1, 1.3, 1)))
			var pole := CylinderMesh.new()
			pole.radial_segments = 12
			pole.rings = 1
			pole.top_radius = 0.02
			pole.bottom_radius = 0.03
			pole.height = 0.75
			n.add_child(_mesh(pole, "#6b4f3a", Vector3(0, 0.375, 0)))
	return n


static func _flowers(colors: Array) -> Node3D:
	var n := Node3D.new()
	for k in 5:
		var a := k * TAU / 5.0
		var p := Vector3(cos(a) * 0.16, 0.16, sin(a) * 0.16)
		var stem := CylinderMesh.new()
		stem.radial_segments = 12
		stem.rings = 1
		stem.top_radius = 0.01
		stem.bottom_radius = 0.012
		stem.height = 0.16
		n.add_child(_mesh(stem, "#5aa05a", Vector3(p.x, 0.08, p.z)))
		n.add_child(_mesh(_sphere(0.05), str(colors[k % colors.size()]), p, 0.5))
	return n


## The season's quiet touch in one corner.
static func _accent(kind: String, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "Accent_" + kind
	n.position = Vector3(at.x, 0, at.z)
	match kind:
		"leaves":
			for k in 4:
				n.add_child(_mesh(_sphere(0.16), ["#d9822b", "#b5452f", "#e0b04a", "#a0522d"][k], Vector3((k % 2) * 0.18 - 0.09, 0.04, (k / 2) * 0.18 - 0.09), 0.2, Vector3(1.3, 0.3, 1.3)))
		"snow":
			for k in 3:
				n.add_child(_mesh(_sphere(0.2 - k * 0.04), "#f4f8ff", Vector3(k * 0.16 - 0.16, 0.05, (k % 2) * 0.12), 0.35, Vector3(1.3, 0.45, 1.3)))
		"flowers":
			n.add_child(_flowers(["#ffd1dc", "#c8b6ff", "#fff3b0"]))
		"sunflower":
			var stem := CylinderMesh.new()
			stem.radial_segments = 12
			stem.rings = 1
			stem.top_radius = 0.015
			stem.bottom_radius = 0.02
			stem.height = 0.55
			n.add_child(_mesh(stem, "#5aa05a", Vector3(0, 0.275, 0)))
			n.add_child(_mesh(_sphere(0.12), "#ffd166", Vector3(0, 0.6, 0), 0.6, Vector3(1, 1, 0.35)))
			n.add_child(_mesh(_sphere(0.06), "#6b4f3a", Vector3(0, 0.6, 0.04), 0.2, Vector3(1, 1, 0.4)))
	return n
