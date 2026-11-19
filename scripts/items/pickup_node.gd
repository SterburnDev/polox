extends Node3D
## A pickup in the world: the item's picture floating and bobbing over a
## little glow, clickable like any object. Ghosted in the editor once taken.

const Items := preload("res://scripts/items/items.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")

var sprite: Sprite3D
var _t := randf() * TAU


static func make(obj: Dictionary, ghost: bool) -> Node3D:
	var n: Node3D = load("res://scripts/items/pickup_node.gd").new()
	n.build(obj, ghost)
	return n


func build(obj: Dictionary, ghost: bool) -> void:
	var it := Items.load_item(str(obj.get("item", "")))
	sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD if not ghost else SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.shaded = false
	sprite.texture = Items.world_texture(it) if not it.is_empty() else Items.icon_texture(Items.defaults())
	sprite.pixel_size = 0.6 / maxf(1.0, sprite.texture.get_height())
	sprite.position.y = 0.55
	if ghost:
		sprite.modulate = Color(1, 1, 1, 0.35)
	add_child(sprite)
	var glow := Sprite3D.new()
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var col := Items.rarity_color(str(it.get("rarity", "common")))
	for y in 16:
		for x in 16:
			var r := Vector2(x - 7.5, y - 7.5).length() / 8.0
			img.set_pixel(x, y, Color(col, clampf(1.0 - r, 0.0, 1.0) * (0.25 if ghost else 0.6)))
	glow.texture = ImageTexture.create_from_image(img)
	glow.pixel_size = 0.05
	glow.axis = Vector3.AXIS_Y
	glow.position.y = 0.03
	glow.shaded = false
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	add_child(BlockFactory.body(Vector3(0.7, 1.0, 0.7), Vector3(0, 0.5, 0), BlockFactory.LAYER_OBJECTS, {"kind": "object", "id": str(obj.get("id", ""))}))


func _process(delta: float) -> void:
	_t += delta
	if sprite:
		sprite.position.y = 0.55 + sin(_t * 2.4) * 0.08
