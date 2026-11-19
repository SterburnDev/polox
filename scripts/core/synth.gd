extends RefCounted
## Tiny built-in sound synth, so the game has text blips and chimes without
## shipping audio files. Players can override any of these by dropping a
## file with the same name into an audio/sfx folder (see _custom below).

const RATE := 22050
## Frames repeated after a loop's end. Godot (4.7) reads the frame AT loop_end before it wraps and keeps no
## padding after a sound's data, so a loop needs its first frames again after its end: without them the
## mixer read past the buffer, and on Android (a big buffer ends at a protected page) that killed the game
## in the audio thread a few seconds in (SIGSEGV in "AudioTrack": the Light World's 8 s room tone).
const LOOP_PAD := 8

static var _cache: Dictionary = {}
static var history: Array = []     # (tests) the last sounds played, newest last
const RECORDED_STEPS := {
	"step_wood": preload("res://assets/kenney/impact/footstep_wood_000.ogg"),
	"step_stone": preload("res://assets/kenney/impact/footstep_concrete_000.ogg"),
	"step_grass": preload("res://assets/kenney/impact/footstep_grass_000.ogg"),
	# Tactile UI (Kenney's UI Audio, CC0, assets/kenney/ui_audio/): a key going down and coming back up,
	# a switch flipping on and off, a wall light switch's clack.
	"tick": preload("res://assets/kenney/ui_audio/click3.ogg"),
	"key_up": preload("res://assets/kenney/ui_audio/mouserelease1.ogg"),
	"switch_on": preload("res://assets/kenney/ui_audio/switch7.ogg"),
	"switch_off": preload("res://assets/kenney/ui_audio/switch2.ogg"),
	"light_switch": preload("res://assets/kenney/ui_audio/switch33.ogg"),
	"knob": preload("res://assets/kenney/ui_audio/switch19.ogg"),
	"tab": preload("res://assets/kenney/ui_audio/click5.ogg"),
}

## The four motifs share one shape (up a fifth, up a step, down to the third, then home), dressed
## differently for each place: a music box for the title, a warm low hum for home in the Light World, a
## minor bell for the Dream World, and a quick square-wave run for battles. Each is under three seconds.
const MOTIFS := {
	"motif_title": [[[523.25, 0.22], [783.99, 0.22], [880.0, 0.22], [659.25, 0.34], [698.46, 0.2], [659.25, 0.2], [587.33, 0.2], [523.25, 0.6]], "bell", 0.26],
	"motif_home": [[[261.63, 0.3], [392.0, 0.3], [440.0, 0.3], [329.63, 0.45], [349.23, 0.3], [261.63, 0.8]], "warm", 0.34],
	"motif_dark": [[[440.0, 0.26], [659.25, 0.26], [698.46, 0.26], [523.25, 0.4], [493.88, 0.26], [329.63, 0.75]], "bell", 0.24],
	"motif_battle": [[[440.0, 0.11], [659.25, 0.11], [698.46, 0.11], [523.25, 0.11], [440.0, 0.11], [659.25, 0.11], [783.99, 0.11], [880.0, 0.32]], "square", 0.12],
}


## Forgets every sound made so far (memory_relief.gd); each is made again when it's next played.
static func clear_cache() -> void:
	_cache.clear()


## An add-on's sound (addons.gd), then a player's file in audio/sfx/ (save folder or assets/), win over the synth.
static func get_sound(sound_name: String) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var custom := _custom(sound_name)
	if custom:
		_cache[sound_name] = custom
		return custom
	if RECORDED_STEPS.has(sound_name):
		_cache[sound_name] = RECORDED_STEPS[sound_name]
		return _cache[sound_name]
	var s: AudioStreamWAV
	match sound_name:
		"blip":
			s = _tone([[520.0, 0.035]], "square", 0.22)
		"click":
			s = _tone([[880.0, 0.03]], "square", 0.15)
		"tick":   # the soft UI click under every button
			s = _motif([[1480.0, 0.03]], "bell", 0.1)
		"motif_title", "motif_home", "motif_dark", "motif_battle":
			var m: Array = MOTIFS[sound_name]
			s = _motif(m[0], str(m[1]), float(m[2]))
		"pop":
			s = _tone([[660.0, 0.04], [990.0, 0.05]], "sine", 0.35)
		"chime":
			s = _tone([[784.0, 0.12], [988.0, 0.12], [1175.0, 0.25]], "sine", 0.3)
		"door":
			s = _tone([[330.0, 0.08], [247.0, 0.16]], "triangle", 0.35)
		"place":
			s = _tone([[200.0, 0.05], [300.0, 0.04]], "square", 0.2)
		"remove":
			s = _tone([[300.0, 0.04], [180.0, 0.07]], "square", 0.2)
		"sparkle":
			s = _tone([[1318.0, 0.06], [1568.0, 0.06], [2093.0, 0.12]], "sine", 0.28)
		"munch":
			s = _tone([[150.0, 0.04], [0.0, 0.03], [120.0, 0.05]], "square", 0.2)
		"fanfare":
			s = _tone([[523.0, 0.09], [659.0, 0.09], [784.0, 0.2]], "square", 0.18)
		# Platform Mode.
		"hum":
			s = _hum()
		"whoosh":
			s = _noise(0.45, 0.22, 900.0, 200.0)
		"page":   # a paper page turning: a soft, bright swish falling away
			s = _noise(0.26, 0.16, 5200.0, 1400.0, 11)
		"boing":
			s = _tone([[220.0, 0.05], [330.0, 0.05], [494.0, 0.09]], "triangle", 0.35)
		"land":
			s = _noise(0.06, 0.25, 300.0, 120.0)
		"step_soft", "step_wood", "step_stone", "step_grass", "step_water", "step_metal":
			s = _step(sound_name.trim_prefix("step_"))
		# Text-blip voices (voice.gd).
		"voice_soft":
			s = _tone([[540.0, 0.045]], "sine", 0.3)
		"voice_chirp":
			s = _tone([[700.0, 0.018], [980.0, 0.02]], "square", 0.16)
		"voice_low":
			s = _tone([[230.0, 0.05]], "triangle", 0.4)
		"voice_bell":
			s = _tone([[1046.0, 0.06]], "sine", 0.26)
		"voice_wood":
			s = _tone([[340.0, 0.022]], "triangle", 0.45)
		_:
			s = _tone([[440.0, 0.05]], "sine", 0.2)
	_cache[sound_name] = s
	return s


## Plays a sound once under `parent` at the player's sound volume (scaled).
static func play(parent: Node, sound_name: String, loudness: float = 0.6) -> void:
	history.append(sound_name)
	if history.size() > 40:
		history.pop_front()
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = get_sound(sound_name)
	p.volume_db = linear_to_db(maxf(0.001, float(GameState.settings.get("sfx_volume", 0.8)) * loudness))
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


static func _custom(sound_name: String) -> AudioStream:
	var addon := preload("res://scripts/core/addons.gd").sfx(sound_name)   # an add-on's sound first
	if addon:
		return addon
	for dir in [SaveManager.global_path("audio/sfx"), ProjectSettings.globalize_path("res://assets/audio/sfx")]:
		for ext in ["ogg", "mp3", "wav"]:
			var path: String = dir.path_join(sound_name + "." + ext)
			if FileAccess.file_exists(path):
				match ext:
					"ogg":
						return AudioStreamOggVorbis.load_from_file(path)
					"mp3":
						return AudioStreamMP3.load_from_file(path)
					_:
						return safe_wav(AudioStreamWAV.load_from_file(path))
	return null


## A WAV from a file, made safe to play: a loop ending past the last frame (a file's own loop chunk can say
## so) ends on the last frame instead, since Godot reads the frame at loop_end (see LOOP_PAD).
static func safe_wav(s: AudioStreamWAV) -> AudioStreamWAV:
	if s and s.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		var last := maxi(0, int(round(s.get_length() * s.mix_rate)) - 1)
		if s.loop_end <= 0 or s.loop_end > last:
			s.loop_end = last
		s.loop_begin = clampi(s.loop_begin, 0, maxi(0, s.loop_end - 1))
	return s


## notes = [[frequency_hz, seconds], ...] played back to back, with a short
## fade on each note so nothing clicks.
static func _tone(notes: Array, wave: String, volume: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	for n in notes:
		var freq: float = n[0]
		var count := int(RATE * float(n[1]))
		for i in count:
			var t := float(i) / RATE
			var ph := fmod(t * freq, 1.0)
			var v := _wave(wave, ph) if freq > 0.0 else 0.0  # freq 0 = a rest
			var env := minf(1.0, minf(i / (RATE * 0.004), (count - i) / (RATE * 0.012)))
			var sample := int(clampf(v * env * volume, -1.0, 1.0) * 32767.0)
			data.append(sample & 0xFF)
			data.append((sample >> 8) & 0xFF)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## Notes that ring and fade like a struck bell or a soft key (the motifs and the UI tick): "bell" is a
## sine with a quiet octave above, "warm" a triangle softened with a sine, "square" a soft square.
static func _motif(notes: Array, voice: String, volume: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	for n in notes:
		var freq: float = n[0]
		var count := int(RATE * float(n[1]))
		for i in count:
			var t := float(i) / RATE
			var ph := fmod(t * freq, 1.0)
			var v := 0.0
			match voice:
				"warm":
					v = _wave("triangle", ph) * 0.6 + sin(ph * TAU) * 0.4
				"square":
					v = _wave("square", ph) * 0.7 + sin(ph * TAU) * 0.3
				_:
					v = sin(ph * TAU) * 0.8 + sin(fmod(ph * 2.0, 1.0) * TAU) * 0.2
			var env := minf(1.0, i / (RATE * 0.006)) * exp(-3.2 * t / maxf(0.05, float(n[1]))) * minf(1.0, (count - i) / (RATE * 0.01))
			var sample := int(clampf(v * env * volume, -1.0, 1.0) * 32767.0)
			data.append(sample & 0xFF)
			data.append((sample >> 8) & 0xFF)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## A short burst of filtered noise: `cut_from` -> `cut_to` Hz-ish (a one-pole
## low-pass sweeping down), for whooshes, landings and footsteps.
static func _noise(seconds: float, volume: float, cut_from: float, cut_to: float, seed_value: int = 7) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data := PackedByteArray()
	var count := int(RATE * seconds)
	var y := 0.0
	for i in count:
		var f := lerpf(cut_from, cut_to, float(i) / count)
		var a := clampf(TAU * f / RATE, 0.0, 1.0)
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		var env := minf(1.0, minf(i / (RATE * 0.003), (count - i) / (RATE * 0.02)))
		var sample := int(clampf(y * 2.2 * env * volume, -1.0, 1.0) * 32767.0)
		data.append(sample & 0xFF)
		data.append((sample >> 8) & 0xFF)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


## Footsteps by surface (a tile's "step sound").
static func _step(kind: String) -> AudioStreamWAV:
	match kind:
		"wood":
			return _tone([[180.0, 0.03], [120.0, 0.03]], "triangle", 0.3)
		"stone":
			return _noise(0.05, 0.3, 2400.0, 900.0, 3)
		"grass":
			return _noise(0.07, 0.2, 1800.0, 600.0, 5)
		"water":
			return _tone([[520.0, 0.03], [380.0, 0.05]], "sine", 0.18)
		"metal":
			return _tone([[1200.0, 0.02], [900.0, 0.04]], "square", 0.08)
	return _noise(0.05, 0.18, 700.0, 250.0, 11)


## The pillars' low hum: two close sine tones beating slowly, one second, looping.
static func _hum() -> AudioStreamWAV:
	var data := PackedByteArray()
	var count := RATE
	for i in count:
		var t := float(i) / RATE
		var v := sin(TAU * 110.0 * t) * 0.5 + sin(TAU * 111.0 * t) * 0.35 + sin(TAU * 220.0 * t) * 0.1
		var sample := int(clampf(v * 0.25, -1.0, 1.0) * 32767.0)
		data.append(sample & 0xFF)
		data.append((sample >> 8) & 0xFF)
	return looping(data, count, RATE)


## A looping 16-bit sound: `frames` frames of `data` (2 bytes a frame, 4 in stereo), with the first
## LOOP_PAD frames again after the end, so the frame read at loop_end is the loop going on.
static func looping(data: PackedByteArray, frames: int, rate: int, stereo: bool = false) -> AudioStreamWAV:
	var frame_bytes := 4 if stereo else 2
	var padded := data.slice(0, frames * frame_bytes)
	padded.append_array(data.slice(0, mini(LOOP_PAD, frames) * frame_bytes))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = stereo
	s.data = padded
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = frames
	return s


static func _wave(wave: String, ph: float) -> float:
	var v := 0.0
	match wave:
		"square":
			v = 1.0 if ph < 0.5 else -1.0
		"triangle":
			v = 4.0 * absf(ph - 0.5) - 1.0
		_:
			v = sin(ph * TAU)
	return v
