extends RefCounted
## Text-blip voices: each character (and the player) picks a sound, a pitch
## and a talking speed. The sounds are synthesized (see synth.gd), and a
## file named voice_<sound>.ogg/.wav in audio/sfx/ replaces one.

const Synth := preload("res://scripts/core/synth.gd")

const SOUNDS := [["blip", "Blip"], ["soft", "Soft"], ["chirp", "Chirp"], ["low", "Low hum"], ["bell", "Bell"], ["wood", "Wooden"]]


static func sound_ids() -> PackedStringArray:
	return PackedStringArray(SOUNDS.map(func(s): return str(s[0])))


static func stream(sound: String) -> AudioStream:
	return Synth.get_sound("blip" if sound == "" or sound == "blip" or not sound in sound_ids() else "voice_" + sound)


## {sound, pitch, speed} for a character card.
static func of_character(c: Dictionary) -> Dictionary:
	return {
		"sound": str(c.get("voice_sound", "blip")),
		"pitch": clampf(float(c.get("voice_pitch", 1.0)), 0.5, 2.0),
		"speed": clampf(float(c.get("voice_speed", 1.0)), 0.5, 2.0),
	}


static func of_player() -> Dictionary:
	var v: Variant = GameState.world.get("player", {}).get("voice", {})
	var d: Dictionary = v if v is Dictionary else {}
	return {
		"sound": str(d.get("sound", "soft")),
		"pitch": clampf(float(d.get("pitch", 1.15)), 0.5, 2.0),
		"speed": clampf(float(d.get("speed", 1.0)), 0.5, 2.0),
	}


## Plays one blip of a voice under `parent` (used by the "Hear" buttons).
static func preview(parent: Node, voice: Dictionary) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream(str(voice.get("sound", "blip")))
	p.pitch_scale = float(voice.get("pitch", 1.0))
	p.volume_db = linear_to_db(maxf(0.001, float(GameState.settings.get("sfx_volume", 0.8)) * 0.6))
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
