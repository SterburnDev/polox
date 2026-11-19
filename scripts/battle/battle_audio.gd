extends RefCounted
## Polox's own battle tune, made in code like the rest of Polox's sound (Synth): a bouncy four-bar loop
## with a bass line and an arpeggio, a little different for each battle (its seed picks the key and the
## chord order). Battles play the battle cue's song instead (an add-on's, Settings > Music); this is
## the theme called "Polox's own tune" there, and the fallback when a song won't load.

const Synth := preload("res://scripts/core/synth.gd")
const RATE := 22050
const CHORDS := [[0, 4, 7], [5, 9, 12], [7, 11, 14], [-3, 0, 4], [2, 5, 9], [-5, -1, 2]]

static var _cache: Dictionary = {}
static var _mutex := Mutex.new()
const CACHE_MAX := 8

## Every battle sound, by what happened: [synth sound, loudness]. A file named battle_<kind>.ogg (or
## .wav / .mp3) in audio/sfx (the save folder's or the game's) replaces the synth for that kind.
const SFX := {
	"select": ["tick", 0.35], "back": ["click", 0.3], "press": ["place", 0.45], "hit": ["whoosh", 0.5],
	"hurt": ["remove", 0.55], "graze": ["blip", 0.22], "heal": ["sparkle", 0.4], "spell": ["sparkle", 0.45],
	"act": ["pop", 0.4], "spare": ["chime", 0.5], "tired": ["voice_low", 0.35], "down": ["door", 0.4],
	"telegraph": ["click", 0.25], "victory": ["fanfare", 0.5], "defeat": ["voice_low", 0.45], "up": ["boing", 0.35],
}
static var played: Array = []       # (tests) the last battle sounds, by kind
static var _custom_kinds: Dictionary = {}


## Plays the sound for `kind` (see SFX) under `node`.
static func sfx(node: Node, kind: String) -> void:
	played.append(kind)
	if played.size() > 40:
		played.pop_front()
	var pair: Array = SFX.get(kind, ["blip", 0.3])
	var custom := "battle_" + kind
	if not _custom_kinds.has(kind):
		_custom_kinds[kind] = Synth._custom(custom) != null
	Synth.play(node, custom if bool(_custom_kinds[kind]) else str(pair[0]), float(pair[1]))


static func loop(seed_n: int, bpm: float = 132.0) -> AudioStreamWAV:
	bpm = clampf(bpm, 60, 200)
	var key := "%d:%.2f" % [seed_n, bpm]
	_mutex.lock()
	if _cache.has(key):
		var cached: AudioStreamWAV = _cache[key]
		_mutex.unlock()
		return cached
	_mutex.unlock()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var root := 196.0 * pow(2.0, float(rng.randi() % 5) / 12.0)
	var order: Array = []
	for _b in 4:
		order.append(CHORDS[rng.randi() % CHORDS.size()])
	var beat := 60.0 / bpm
	var step := beat / 4.0   # sixteenth notes
	var steps := 16 * 4
	var total := int(steps * step * RATE)
	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		var t := float(i) / RATE
		var s := int(t / step)
		var bar: Array = order[(s / 16) % 4]
		var in_step := fmod(t, step) / step
		# Arpeggio: up through the chord, square wave, short notes.
		var note: int = bar[s % 3] + 12
		var f := root * pow(2.0, note / 12.0)
		var env := clampf(1.0 - in_step * 1.6, 0.0, 1.0)
		var v := (1.0 if fmod(t * f, 1.0) < 0.5 else -1.0) * 0.12 * env
		# Bass on every beat, triangle wave.
		var fb := root * 0.5 * pow(2.0, int(bar[0]) / 12.0)
		var bass_env := clampf(1.0 - fmod(t, beat) / beat * 1.2, 0.0, 1.0)
		v += (4.0 * absf(fmod(t * fb, 1.0) - 0.5) - 1.0) * 0.22 * bass_env
		# A soft tick on the off-beats.
		if s % 4 == 2 and in_step < 0.15:
			v += (rng.randf() * 2.0 - 1.0) * 0.05
		var sample := int(clampf(v, -1.0, 1.0) * 32767.0)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var w := Synth.looping(data, total, RATE)
	_mutex.lock()
	while _cache.size() >= CACHE_MAX:
		_cache.erase(_cache.keys()[0])
	_cache[key] = w
	_mutex.unlock()
	return w
