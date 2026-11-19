extends RefCounted
## How Platform Mode's objects look (procedural meshes, no image files):
##   pillar      Platform Pillar: a tall glowing column with floating rune rings,
##               a soft hum and an idle bob, in its colour (Exit Pillar = mint)
##   jump_pad    a round pad with chevrons
##   one_way     a thin see-through ledge (you can jump up through it)
##   mover       a moving platform (drawn at its start point)
##   checkpoint  a lantern post (lights up once reached)
##   shard       a Memory Shard: a floating, turning crystal
##   hazard      a soft, bubbly patch (touching it just puts you back)
## Origin at the cell's floor centre; `elev` lifts ledges, movers and shards.

const BlockFactory := preload("res://scripts/world/block_factory.gd")
const IdleMotion := preload("res://scripts/platform/idle_motion.gd")
const Synth := preload("res://scripts/core/synth.gd")

const TYPES: PackedStringArray = ["pillar", "jump_pad", "one_way", "mover", "checkpoint", "shard", "hazard"]
const NAMES := {"pillar": "Platform Pillar", "jump_pad": "Jump pad", "one_way": "One-way ledge", "mover": "Moving platform",
	"checkpoint": "Checkpoint", "shard": "Memory Shard", "hazard": "Soft hazard"}
const DEFAULT_COLORS := {"pillar": "#c58cff", "jump_pad": "#ffd166", "one_way": "#8fd3ff", "mover": "#7ad6b0",
	"checkpoint": "#ffb3c7", "shard": "#7af0ff", "hazard": "#e86a8a"}


static func color_of(obj: Dictionary) -> Color:
	var c := str(obj.get("color", ""))
	return Color.from_string(c if c != "" else str(DEFAULT_COLORS.get(str(obj.get("type", "")), "#c9b6ff")), Color("#c9b6ff"))


static func glow(c: Color, energy: float = 1.2, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.6
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _mi(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	return mi


static func make(obj: Dictionary, quiet: bool = false) -> Node3D:
	var type := str(obj.get("type", ""))
	var root := Node3D.new()
	var c := color_of(obj)
	var lift := Node3D.new()
	lift.position.y = float(obj.get("elev", 0))
	root.add_child(lift)
	var meta := {"kind": "object", "id": str(obj.get("id", ""))}
	match type:
		"pillar":
			_pillar(lift, c, str(obj.get("label", "")), quiet)
			lift.add_child(BlockFactory.body(Vector3(0.8, 3.0, 0.8), Vector3(0, 1.5, 0), BlockFactory.LAYER_OBJECTS, meta))
		"jump_pad":
			var base := CylinderMesh.new()
			base.radial_segments = 12
			base.rings = 1
			base.top_radius = 0.44
			base.bottom_radius = 0.46
			base.height = 0.12
			lift.add_child(_mi(base, BlockFactory.material("#3a2a6e"), Vector3(0, 0.06, 0)))
			var top := CylinderMesh.new()
			top.radial_segments = 12
			top.rings = 1
			top.top_radius = 0.36
			top.bottom_radius = 0.36
			top.height = 0.04
			lift.add_child(_mi(top, glow(c, 1.6), Vector3(0, 0.14, 0)))
			for i in 3:
				var chev := PrismMesh.new()
				chev.size = Vector3(0.3, 0.12, 0.05)
				var arrow := _mi(chev, glow(c.lightened(0.3), 2.0), Vector3(0, 0.25 + i * 0.16, 0))
				arrow.add_child(IdleMotion.bob(0.04, 3.0 + i))
				lift.add_child(arrow)
			lift.add_child(BlockFactory.body(Vector3(0.9, 0.2, 0.9), Vector3(0, 0.1, 0), BlockFactory.LAYER_OBJECTS, meta))
		"one_way":
			var slab := BoxMesh.new()
			slab.size = Vector3(1.0, 0.12, 1.0)
			lift.add_child(_mi(slab, glow(c, 0.5, 0.55), Vector3(0, -0.06, 0)))
			var edge := BoxMesh.new()
			edge.size = Vector3(1.0, 0.04, 0.06)
			for z in [-0.47, 0.47]:
				lift.add_child(_mi(edge, glow(c.lightened(0.4), 1.4), Vector3(0, 0.01, z)))
			lift.add_child(BlockFactory.body(Vector3(1, 0.15, 1), Vector3(0, -0.06, 0), BlockFactory.LAYER_OBJECTS, meta))
		"mover":
			var plate := BoxMesh.new()
			plate.size = Vector3(1.0, 0.3, 1.0)
			lift.add_child(_mi(plate, BlockFactory.material(c.to_html(false)), Vector3(0, -0.15, 0)))
			var dir := Vector3(float(obj.get("dx", 3)), float(obj.get("dy", 0)), float(obj.get("dz", 0)))
			if dir.length() > 0.01:
				var arrow := PrismMesh.new()
				arrow.size = Vector3(0.3, 0.3, 0.06)
				var a := _mi(arrow, glow(Color.WHITE, 1.0, 0.8), Vector3(0, 0.03, 0))
				a.rotation = Vector3(-PI / 2.0, atan2(-dir.x, -dir.z), 0)
				lift.add_child(a)
			lift.add_child(BlockFactory.body(Vector3(1, 0.3, 1), Vector3(0, -0.15, 0), BlockFactory.LAYER_OBJECTS, meta))
		"checkpoint":
			var post := CylinderMesh.new()
			post.radial_segments = 12
			post.rings = 1
			post.top_radius = 0.05
			post.bottom_radius = 0.07
			post.height = 1.3
			lift.add_child(_mi(post, BlockFactory.material("#5b4b8a"), Vector3(0, 0.65, 0)))
			var lamp := SphereMesh.new()
			lamp.radial_segments = 12
			lamp.rings = 6
			lamp.radius = 0.16
			lamp.height = 0.32
			var bulb := _mi(lamp, glow(c, 0.4), Vector3(0, 1.42, 0))
			bulb.name = "Lamp"
			lift.add_child(bulb)
			lift.add_child(BlockFactory.body(Vector3(0.4, 1.6, 0.4), Vector3(0, 0.8, 0), BlockFactory.LAYER_OBJECTS, meta))
		"shard":
			var crystal := SphereMesh.new()
			crystal.radial_segments = 4
			crystal.rings = 1
			crystal.radius = 0.2
			crystal.height = 0.55
			var gem := _mi(crystal, glow(c, 2.0, 0.9), Vector3(0, 0.75, 0))
			gem.name = "Gem"
			gem.add_child(IdleMotion.spin_bob(1.6, 0.08, 2.0))
			lift.add_child(gem)
			lift.add_child(BlockFactory.body(Vector3(0.5, 0.7, 0.5), Vector3(0, 0.75, 0), BlockFactory.LAYER_OBJECTS, meta))
		"hazard":
			var goo := CylinderMesh.new()
			goo.radial_segments = 12
			goo.rings = 1
			goo.top_radius = 0.46
			goo.bottom_radius = 0.48
			goo.height = 0.08
			lift.add_child(_mi(goo, glow(c, 0.8, 0.75), Vector3(0, 0.04, 0)))
			for i in 4:
				var bub := SphereMesh.new()
				bub.radial_segments = 12
				bub.rings = 6
				bub.radius = 0.06 + 0.02 * (i % 2)
				bub.height = bub.radius * 2.0
				var b := _mi(bub, glow(c.lightened(0.35), 1.2, 0.8), Vector3(cos(i * 1.7) * 0.25, 0.1, sin(i * 1.7) * 0.25))
				b.add_child(IdleMotion.bob(0.05, 2.0 + i * 0.7))
				lift.add_child(b)
			lift.add_child(BlockFactory.body(Vector3(0.9, 0.15, 0.9), Vector3(0, 0.07, 0), BlockFactory.LAYER_OBJECTS, meta))
	return root


## The pillar: stone foot, glowing column, three rune rings that drift and
## turn, a light on top, and (unless quiet) a low hum you hear up close.
static func _pillar(at: Node3D, c: Color, label: String, quiet: bool) -> void:
	var foot := CylinderMesh.new()
	foot.radial_segments = 12
	foot.rings = 1
	foot.top_radius = 0.34
	foot.bottom_radius = 0.42
	foot.height = 0.3
	at.add_child(_mi(foot, BlockFactory.material("#2e2552"), Vector3(0, 0.15, 0)))
	var col := CylinderMesh.new()
	col.radial_segments = 12
	col.rings = 1
	col.top_radius = 0.16
	col.bottom_radius = 0.22
	col.height = 2.4
	at.add_child(_mi(col, glow(c, 0.9), Vector3(0, 1.5, 0)))
	var orb := SphereMesh.new()
	orb.radial_segments = 12
	orb.rings = 6
	orb.radius = 0.24
	orb.height = 0.48
	var o := _mi(orb, glow(c.lightened(0.4), 2.2), Vector3(0, 2.95, 0))
	o.add_child(IdleMotion.bob(0.07, 1.4))
	at.add_child(o)
	for i in 3:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.3 + i * 0.04
		ring.outer_radius = 0.36 + i * 0.04
		ring.rings = 24
		ring.ring_segments = 6
		var r := _mi(ring, glow(c.lightened(0.2 + i * 0.1), 1.8), Vector3(0, 0.9 + i * 0.7, 0), Vector3(0.25 * (i - 1), 0, 0.2))
		r.name = "Ring%d" % i
		r.add_child(IdleMotion.spin_bob(0.6 + i * 0.35, 0.06, 1.1 + i * 0.4))
		at.add_child(r)
	var light := OmniLight3D.new()
	light.add_to_group("polox_lamp")
	light.light_color = c
	light.light_energy = 0.9
	light.omni_range = 3.2
	light.position.y = 2.2
	at.add_child(light)
	if label != "":
		var l := Label3D.new()
		l.text = label
		l.font_size = 36
		l.pixel_size = 0.006
		l.outline_size = 10
		l.outline_modulate = Color("#120e24")
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position.y = 3.5
		at.add_child(l)
	if not quiet and DisplayServer.get_name() != "headless":
		var hum := AudioStreamPlayer3D.new()
		hum.stream = Synth.get_sound("hum")
		hum.unit_size = 1.5
		hum.max_distance = 7.0
		hum.volume_db = linear_to_db(maxf(0.001, float(GameState.settings.get("sfx_volume", 0.8)) * 0.35))
		hum.autoplay = true
		hum.position.y = 1.5
		at.add_child(hum)


## The ring burst when a pillar wakes: three glowing rings racing outward.
static func burst(parent: Node3D, at: Vector3, c: Color) -> void:
	for i in 3:
		var ring := TorusMesh.new()
		ring.rings = 24
		ring.ring_segments = 8
		ring.inner_radius = 0.45
		ring.outer_radius = 0.55
		var mi := _mi(ring, glow(c.lightened(0.3), 2.5, 0.9), at + Vector3(0, 0.6 + i * 0.6, 0))
		parent.add_child(mi)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "scale", Vector3.ONE * (5.0 + i), 0.8).set_delay(i * 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi.material_override, "albedo_color:a", 0.0, 0.8).set_delay(i * 0.08)
		tw.chain().tween_callback(mi.queue_free)
