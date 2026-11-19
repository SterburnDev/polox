extends RefCounted
## Drawing in arena coordinates keeps rotated input, bullets and hitboxes together.

const Art := preload("res://scripts/battle/bullet_art.gd")
const Motion := preload("res://scripts/battle/heart_motion.gd")
const Soul := preload("res://scripts/ui/soul.gd")
const COLORS := {"free": Color("#e86a8a"), "gravity": Color("#a7b7ff"), "shield": Color("#7ad6b0"), "shooter": Color("#ffd166")}
const HINTS := {"free": "Drag anywhere, or use the directions.", "gravity": "Up / A jumps. Drag up to jump, sideways to steer.", "shield": "Aim toward the incoming dots.", "shooter": "Hold touch / Z / A to pulse. Hollow pods can open."}


## The Soul (soul.gd) where the dodging cursor is. Only the picture: where it moves and what hits it are
## heart_motion.gd's and the hit radius's, the same as ever. `r` = the old heart's radius; the picture is a
## little larger than the heart was (its rim is see-through), and a mode other than free rings it in the
## mode's colour.
static func draw_soul(ci: CanvasItem, at: Vector2, mode: String, r: float = 9.0) -> void:
	var ring: Color = Color(0, 0, 0, 0) if mode == "free" else Color(COLORS.get(mode, COLORS.free), 0.85)
	Soul.draw(ci, at, r * 2.3, ring)


## Hazard zones (Battle Maker > Arena): pink stripes sting, blue slows you. Drawn under the bullets.
static func draw_hazards(ci: CanvasItem, hazards: Array, extent: Vector2, k: float) -> void:
	for h in hazards:
		var hr := Rect2(Vector2(float(h.x), float(h.y)) * extent - extent / 2, Vector2(float(h.w), float(h.h)) * extent)
		var col := Color("#e86a8a") if str(h.kind) == "hurt" else Color("#65c7ff")
		ci.draw_rect(hr, Color(col, 0.18))
		if str(h.kind) == "hurt":
			var step := 12.0
			var x := hr.position.x - hr.size.y
			while x < hr.end.x:
				var a := Vector2(maxf(x, hr.position.x), hr.end.y - maxf(0.0, hr.position.x - x))
				var b := Vector2(minf(x + hr.size.y, hr.end.x), hr.position.y + maxf(0.0, x + hr.size.y - hr.end.x))
				ci.draw_line(a, b, Color(col, 0.35), 1.5 / k)
				x += step
		ci.draw_rect(hr, Color(col, 0.75), false, 2.0 / k)


static func draw(s: Control, offset: Vector2) -> void:
	var k: float = s._arena_scale
	var extent: Vector2 = s._arena
	s.draw_set_transform(s.box.get_center() + offset, s._rotation, Vector2.ONE * k)
	var r := Rect2(-extent / 2, extent)
	s.draw_rect(r, Color(0, 0, 0, 0.9))
	if s.skin and s.skin.has("box"):
		s.draw_texture_rect(s.skin.get_tex("box"), r.grow(4), false)
	s.draw_rect(r, Color.WHITE, false, 3.0 / k)
	draw_hazards(s, (s.wave as Dictionary).get("hazards", []), extent, k)
	for i in s.field.count:
		var b = s.field.slots[i]
		if s.field.removed(b) or not Rect2(Vector2.ZERO, extent).has_point(b.position):
			continue
		var at: Vector2 = b.position - extent / 2
		Art.draw(s, b.kind, at, b.scale)
		if b.rule == "still":
			s.draw_arc(at, 9.0 * b.scale, 0, TAU, 12, Color("#65c7ff"), 2)
			s.draw_line(at + Vector2(-2, -3), at + Vector2(-2, 3), Color("#65c7ff"), 1)
			s.draw_line(at + Vector2(2, -3), at + Vector2(2, 3), Color("#65c7ff"), 1)
		elif b.rule == "move":
			s.draw_line(at + Vector2(-7, -7), at + Vector2(0, -11), Color("#ffbf69"), 2)
			s.draw_line(at + Vector2(0, -11), at + Vector2(7, -7), Color("#ffbf69"), 2)
	var heart: Vector2 = s.heart - extent / 2
	var motion = s.motion
	if motion.mode == "shield":
		var angle: float = motion.shield.angle()
		s.draw_arc(heart, Motion.SHIELD_R, angle - 0.85, angle + 0.85, 16, Color("#7ad6b0"), 4)
	for i in Motion.PULSE_MAX:
		if motion.pulse_live[i]:
			var at: Vector2 = motion.pulses[i] - extent / 2
			s.draw_line(at + Vector2(0, 3), at + Vector2(0, -3), Color("#ffd166"), 3)
	if s.phase == "telegraph":
		for o in s._warnings:
			var glow := Color("#ffd166", 0.65)
			if str(o.kind) == "edge":
				match str(o.side):
					"top": s.draw_line(r.position, r.position + Vector2(extent.x, 0), glow, 5)
					"bottom": s.draw_line(r.end - Vector2(extent.x, 0), r.end, glow, 5)
					"left": s.draw_line(r.position, r.position + Vector2(0, extent.y), glow, 5)
					"right": s.draw_line(r.end - Vector2(0, extent.y), r.end, glow, 5)
			else:
				s.draw_circle(Vector2(float(o.at[0]), float(o.at[1])) * extent - extent / 2, 8, glow)
	if s.invuln <= 0 or int(s.invuln * 12) % 2 == 0:
		if s.skin and s.skin.has("heart"):
			s.draw_texture_rect(s.skin.get_tex("heart"), Rect2(heart - Vector2(9, 9), Vector2(18, 18)), false)
		else:
			draw_soul(s, heart, str(motion.mode))
	s.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var width := minf(s.size.x - 24, 620)
	var top: float = s.box.get_center().y + (extent.y * cos(s._rotation) + extent.x * absf(sin(s._rotation))) * k / 2 + 26
	var hint: String = s._mode_hint
	if s.phase == "telegraph":
		hint = s._telegraph_hint
	s.draw_multiline_string(ThemeDB.fallback_font, Vector2((s.size.x - width) / 2, top), hint, HORIZONTAL_ALIGNMENT_CENTER, width, 18, 3, Color("#f3e9d2"))
