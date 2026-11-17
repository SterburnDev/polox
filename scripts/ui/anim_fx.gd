extends RefCounted
## The little motions the whole game shares: things popping in when placed, buttons pressing in, screens
## sliding up and fading, lists arriving one after another, toasts gliding, something you picked up flying
## to your bag, a door swinging. Each one is short (under half a second), can be interrupted (a new one on
## the same thing replaces it), and under Reduce motion becomes a short fade or nothing at all.

const FADE_S := 0.12

static var played := 0        # (tests) full animations started
static var faded := 0         # (tests) Reduce motion stand-ins
static var popped := 0        # (tests) pieces popped in


static func reduced() -> bool:
	return bool(GameState.settings.get("reduce_motion", false))


## One tween per thing: a new animation on a node stops the one before it.
static func _tween(node: Node) -> Tween:
	var old: Variant = node.get_meta("anim_tw") if node.has_meta("anim_tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := node.create_tween()
	node.set_meta("anim_tw", tw)
	return tw


## A piece appearing where you put it: up from small with a little bounce. Popping it again mid-pop starts
## over towards its real size (kept in "rest_scale"), never the half-grown one.
static func pop_in(node: Node3D) -> void:
	if node == null or not node.is_inside_tree():
		return
	var old: Variant = node.get_meta("anim_tw") if node.has_meta("anim_tw") else null
	var mid_pop: bool = old is Tween and (old as Tween).is_valid() and node.has_meta("rest_scale")
	var target: Vector3 = node.get_meta("rest_scale") if mid_pop else node.scale
	if reduced():
		faded += 1
		node.scale = target
		return
	played += 1
	popped += 1
	node.set_meta("rest_scale", target)
	node.scale = target * 0.2
	var tw := _tween(node)
	tw.tween_property(node, "scale", target * 1.12, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", target, 0.1)
	tw.tween_callback(func(): node.remove_meta("rest_scale"))


## A button pressing in under your finger, and back out.
static func press(c: Control) -> void:
	if reduced() or not c.is_inside_tree():
		return
	c.pivot_offset = c.size / 2.0
	var tw := _tween(c)
	tw.tween_property(c, "scale", Vector2(0.95, 0.95), 0.06)


static func release(c: Control) -> void:
	if not c.is_inside_tree():
		return
	if reduced():
		c.scale = Vector2.ONE
		return
	var tw := _tween(c)
	tw.tween_property(c, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A screen arriving: a bottom sheet slides up, a centred panel grows in a touch; both fade in.
static func panel_in(panel: Control, from_below: bool) -> void:
	if panel == null:
		return
	panel.modulate.a = 0.0
	var tw := _tween(panel)
	if reduced():
		faded += 1
		tw.tween_property(panel, "modulate:a", 1.0, FADE_S)
		return
	played += 1
	if from_below:
		var holder: Control = panel.get_parent() as Control
		if holder:
			holder.position.y = 60.0
			tw.parallel().tween_property(holder, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		panel.pivot_offset = panel.size / 2.0
		panel.scale = Vector2(0.96, 0.96)
		tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.16)


## A list arriving one item after another (the first dozen; the rest are simply there).
static func stagger(container: Control, max_items: int = 12) -> void:
	if container == null:
		return
	var i := 0
	for c in container.get_children():
		if not c is CanvasItem or i >= max_items:
			continue
		var ci := c as CanvasItem
		if reduced():
			continue
		ci.modulate.a = 0.0
		var tw := _tween(ci)
		tw.tween_interval(0.025 * i)
		tw.tween_property(ci, "modulate:a", 1.0, 0.14)
		i += 1


## A toast gliding in (inside a list it grows from a little smaller; on its own it slides from the side).
static func glide_in(c: Control) -> void:
	if reduced():
		faded += 1
		c.modulate.a = 0.0
		var tw0 := _tween(c)
		tw0.tween_property(c, "modulate:a", 1.0, FADE_S)
		return
	played += 1
	c.modulate.a = 0.0
	var tw := _tween(c)
	if c.get_parent() is Container:
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(0.9, 0.9)
		tw.tween_property(c, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		var start := c.position.x
		c.position.x = start + 36.0
		tw.tween_property(c, "position:x", start, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "modulate:a", 1.0, 0.18)


## Something you picked up flying from where it was (screen position) to your bag (the Bag button).
static func fly_to(layer: Node, tex: Texture2D, from: Vector2, to: Vector2) -> void:
	if reduced() or layer == null:
		faded += 1
		return
	played += 1
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size = Vector2(44, 44)
	icon.position = from - icon.size / 2.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.name = "FlyingToBag"
	layer.add_child(icon)
	var mid := (from + to) / 2.0 + Vector2(0, -90)
	var tw := icon.create_tween()
	tw.tween_method(func(t: float):
		var a := from.lerp(mid, t)
		var b := mid.lerp(to, t)
		icon.position = a.lerp(b, t) - icon.size / 2.0
		icon.scale = Vector2.ONE * lerpf(1.0, 0.5, t), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(icon.queue_free)


## A door swinging as you go through it (a quick turn and back).
static func swing(node: Node3D) -> void:
	if node == null or reduced():
		return
	played += 1
	var base := node.rotation.y
	var tw := _tween(node)
	tw.tween_property(node, "rotation:y", base + 0.45, 0.16).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "rotation:y", base, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
