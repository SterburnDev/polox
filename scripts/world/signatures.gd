extends Node
## The game's crafted moments, each a little scene (a title, a motif, a change in the light) that a tap skips
## and Reduce motion shortens to a fade:
## - the first look at your real home (game_world.reveal_home draws it in; this adds the title and the music),
## - the first walk down your street,
## - the first trip through the fountain into the Dream World,
## - coming home after a battle (every time, short).
## The "first" ones happen once: your home's in your private home folder, the fountain's in the world save.

const Moment := preload("res://scripts/ui/moment.gd")
const TitleCard := preload("res://scripts/ui/title_card.gd")
const Synth := preload("res://scripts/core/synth.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")

const AFTER_BATTLE := {
	"won": "You did it.",
	"spared": "Friends again.",
	"ran": "Safe and sound.",
	"knocked_down": "Nothing lost. Rest a moment.",
}

var world: Node
var last := ""          # (tests) the last moment played
var running := false


func seen(kind: String) -> bool:
	var d: Variant = GameState.world.get("moments_seen", {})
	return d is Dictionary and (d as Dictionary).has(kind)


func _mark(kind: String) -> void:
	var d: Dictionary = GameState.world.get("moments_seen", {}) if GameState.world.get("moments_seen") is Dictionary else {}
	d[kind] = Time.get_date_string_from_system()
	GameState.world["moments_seen"] = d
	GameState.save_world()


## A moment's motif, with the stage to itself: the music steps aside while it plays (music_player.gd).
func _motif(motif: String, volume: float) -> void:
	Synth.play(world, motif, volume)
	if world.get("music"):
		world.music.make_way(motif)


## A short change in the light: towards `tint`, then back (not under Reduce motion).
func _glow(tint: Color, strength: float, seconds: float) -> void:
	if Moment.reduced() or world.env == null:
		return
	var c0: Color = world.env.ambient_light_color
	var e0: float = world.env.ambient_light_energy
	var tw := create_tween()
	tw.tween_property(world.env, "ambient_light_color", c0.lerp(tint, 0.5), seconds * 0.35)
	tw.parallel().tween_property(world.env, "ambient_light_energy", e0 * strength, seconds * 0.35)
	tw.tween_property(world.env, "ambient_light_color", c0, seconds * 0.65)
	tw.parallel().tween_property(world.env, "ambient_light_energy", e0, seconds * 0.65)


## The title and music for the first look at your home (the drawing-in itself is reveal_home's).
func first_look_begins() -> Control:
	last = "first_look"
	_motif("motif_home", 0.5)
	_glow(Color("#ffd8a0"), 1.25, 2.4)
	return TitleCard.play(world.main, "Home.", "drawn from your answers", 1.8)


## The first time you step out onto your street: its name, birds overhead, the home motif in the open air.
func first_street(data: Dictionary) -> void:
	if running or not HomeStore.exists() or not str(data.get("id", "")).begins_with("lw_hood_"):
		return
	var home: Dictionary = HomeStore.load_home()
	if str(home.get("first_street", "")) != "":
		return
	home["first_street"] = Time.get_date_string_from_system()
	HomeStore.save_home(home)
	running = true
	last = "first_street"
	var m: Control = Moment.begin(world.main)
	_motif("motif_home", 0.4)
	var name := str(data.get("name", "Your street"))
	var card := TitleCard.play(world.main, name, "your street", 1.8)
	if world.get("street_life") and world.player:
		world.street_life.spawn_birds(world.player.position)
	_glow(Color("#fff1c8"), 1.15, 2.6)
	await m.wait(0.7 if Moment.reduced() else 2.8)
	if m.was_skipped and is_instance_valid(card):
		card.dismiss()
	m.finish()
	running = false


## The first trip through the fountain: the Dream World announces itself in violet light and a minor bell.
func first_fountain() -> void:
	if running or seen("first_fountain"):
		return
	_mark("first_fountain")
	running = true
	last = "first_fountain"
	var m: Control = Moment.begin(world.main)
	_motif("motif_dark", 0.5)
	var card := TitleCard.play(world.main, "The Dream World", "where your dreams live", 1.8)
	_glow(Color("#b48cff"), 1.5, 2.6)
	await m.wait(0.7 if Moment.reduced() else 2.8)
	if m.was_skipped and is_instance_valid(card):
		card.dismiss()
	m.finish()
	running = false


## Back from a battle (any outcome): warm light, the home motif, the nearest friend glad to see you.
func home_after_battle(summary: Dictionary) -> void:
	if running or world == null or world.player == null:
		return
	running = true
	last = "after_battle"
	var m: Control = Moment.begin(world.main)
	_motif("motif_home", 0.32)
	_glow(Color("#ffd8a0"), 1.3, 1.8)
	var card := TitleCard.play(world.main, "Welcome back", str(AFTER_BATTLE.get(str(summary.get("outcome", "")), "Home again.")), 1.0)
	var near: Node3D = null
	var best := 1e9
	for id in world.actors:
		var a: Node3D = world.actors[id]
		if is_instance_valid(a):
			var d: float = a.position.distance_to(world.player.position)
			if d < best:
				best = d
				near = a
	if near:
		near.emote("♥", ThemeBuilder.PINK)
		near.react("happy")
	await m.wait(0.6 if Moment.reduced() else 1.8)
	if m.was_skipped and is_instance_valid(card):
		card.dismiss()
	m.finish()
	running = false
