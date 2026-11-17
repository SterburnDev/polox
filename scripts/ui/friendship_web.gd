extends "res://scripts/ui/screen_panel.gd"
## Friendship web: you in the middle, your friends around you. Lines show
## how close everyone is (thicker and warmer = closer).

const Bonds := preload("res://scripts/characters/bonds.gd")


class Web extends Control:
	var nodes: Array = []      # [id, name, texture, position]
	var you_tex: Texture2D

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) * 0.38
		var n := GameState.characters.size()
		nodes.clear()
		var i := 0
		for id in GameState.characters:
			var c: Dictionary = GameState.characters[id]
			var ang := TAU * i / maxf(1.0, n) - PI / 2.0
			nodes.append([id, str(c.get("name", id)), SaveManager.load_texture(SaveManager.expression_path(c, "neutral")), center + Vector2(cos(ang), sin(ang)) * radius])
			i += 1
		# Friend <-> friend lines first, then you <-> friend, then faces on top.
		for a in nodes.size():
			for b in range(a + 1, nodes.size()):
				var v := Bonds.value(nodes[a][0], nodes[b][0])
				if v >= 1.0:
					draw_polyline(_curve(nodes[a][3], nodes[b][3], center, radius), _bond_color(v), 1.5 + v / 14.0, true)
		for node in nodes:
			var aff := float(GameState.get_character(node[0]).get("relationship", {}).get("affinity", 0))
			draw_line(center, node[3], Color(1.0, 0.82, 0.4, 0.35 + aff / 160.0), 1.5 + aff / 14.0, true)
		_face(center, you_tex, "You")
		for node in nodes:
			_face(node[3], node[2], node[1])

	## A soft arc from a to b that bows away from the middle, so friend links
	## never hide behind your own (straight) lines to the center.
	func _curve(a: Vector2, b: Vector2, center: Vector2, radius: float) -> PackedVector2Array:
		var mid := (a + b) / 2.0
		var away := mid - center
		if away.length() < radius * 0.2:
			away = (b - a).orthogonal()  # opposite friends: bow sideways
		var ctrl := mid + away.normalized() * radius * 0.45
		var pts := PackedVector2Array()
		for i in 17:
			var t := i / 16.0
			pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
		return pts

	func _bond_color(v: float) -> Color:
		return Color("#8fd3ff").lerp(Color("#ff8fab"), clampf(v / 100.0, 0.0, 1.0))

	func _face(p: Vector2, tex: Texture2D, label_text: String) -> void:
		draw_circle(p, 38, Color("#1d1736"))
		draw_arc(p, 38, 0, TAU, 32, Color("#f3e9d2"), 2.0, true)
		if tex:
			draw_texture_rect(tex, Rect2(p - Vector2(28, 28), Vector2(56, 56)), false)
		var font := get_theme_default_font()
		var w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18).x
		draw_string(font, p + Vector2(-w / 2.0, 60), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#f3e9d2"))


func _ready() -> void:
	setup("Friendship web", Vector2(1000, 660))
	body.add_child(UiKit.para("Gold lines: how close each friend is to you. Blue to pink lines: how close they are to each other (they bond by chatting and hanging out).", 18, ThemeBuilder.MUTED))
	var web := Web.new()
	web.size_flags_vertical = Control.SIZE_EXPAND_FILL
	web.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	web.you_tex = SaveManager.load_texture(str(GameState.world.get("player", {}).get("avatar", "")))
	body.add_child(web)
	var list := PackedStringArray()
	var ids: Array = GameState.characters.keys()
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			var v := Bonds.value(ids[a], ids[b])
			if v >= 5.0:
				list.append("%s & %s: %s" % [GameState.characters[ids[a]].get("name", ""), GameState.characters[ids[b]].get("name", ""), Bonds.label(v)])
	if not list.is_empty():
		body.add_child(UiKit.para("  •  ".join(list), 18, ThemeBuilder.MUTED))
