extends Node
class_name VoiceEngine

## Unified voice synthesis for Dialogue blips replacement AND Live Conversation mode.
## Supports:
## - "blips": classic Undertale-style text blips (DialogueBox handles playback)
## - "tts": offline System TTS (DisplayServer.tts_speak)
## - "local": local HTTP TTS server (e.g. Kokoro-FastAPI, Piper HTTP)
## - "api": cloud voice models (OpenAI, Groq, Google Gemini, ElevenLabs, Custom)

const VOICE_MODES := ["blips", "tts", "local", "api"]
const VOICE_MODE_LABELS := [
	"Classic blips (no voice)",
	"System TTS (offline)",
	"Local voice server (HTTP)",
	"API voice model (cloud)",
]
const API_PROVIDERS := ["openai", "groq", "gemini", "elevenlabs", "custom"]
const API_PROVIDER_LABELS := [
	"OpenAI (/audio/speech)",
	"Groq (/audio/speech)",
	"Google Gemini (native audio)",
	"ElevenLabs",
	"Custom OpenAI-compatible",
]
const RUNNER_NAME := "_PoloxVoiceRunner"
const TIMEOUT_S := 20.0

static var _gen: int = 0
static var _speaking: bool = false
static var tts_hook: Callable = Callable()        # optional test override
static var http_transport: Callable = Callable()  # optional test override


static func get_config() -> Dictionary:
	var raw: Variant = GameState.settings.get("voice", {}) if GameState else {}
	var v: Dictionary = (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
	var mode := str(v.get("mode", "blips")).strip_edges().to_lower()
	if not (mode in VOICE_MODES):
		mode = "blips"
	v["mode"] = mode
	v["replace_blips"] = bool(v.get("replace_blips", true))
	var api_p := str(v.get("api_provider", "openai")).strip_edges().to_lower()
	if not (api_p in API_PROVIDERS):
		api_p = "openai"
	v["api_provider"] = api_p
	v["api_key"] = str(v.get("api_key", "")).strip_edges()
	v["base_url"] = str(v.get("base_url", "")).strip_edges()
	v["local_url"] = str(v.get("local_url", "http://127.0.0.1:8880/v1/audio/speech")).strip_edges()
	v["model"] = str(v.get("model", "")).strip_edges()
	v["voice_name"] = str(v.get("voice_name", "")).strip_edges()
	v["stt_url"] = str(v.get("stt_url", "")).strip_edges()
	v["rate"] = clampf(float(v.get("rate", 1.05)), 0.5, 2.0)
	v["auto_listen"] = bool(v.get("auto_listen", true))
	return v


static func effective_mode(for_live: bool = false) -> String:
	var v := get_config()
	var m := str(v.get("mode", "blips"))
	if for_live and m == "blips":
		return "tts"
	return m


static func replaces_blips() -> bool:
	var v := get_config()
	return str(v.get("mode", "blips")) != "blips" and bool(v.get("replace_blips", true))


static func is_speaking() -> bool:
	if _speaking:
		return true
	if DisplayServer.get_name() != "headless":
		return DisplayServer.tts_is_speaking()
	return false


static func clean_text_for_speech(raw: String) -> String:
	var txt := raw.replace("\r", " ").replace("\n", " ").strip_edges()
	while txt.contains("  "):
		txt = txt.replace("  ", " ")
	return txt


static func pitch_for_emotion(emotion: String) -> float:
	match emotion.to_lower():
		"happy", "excited":
			return 1.12
		"sad", "tired", "nervous":
			return 0.92
		"mad":
			return 0.96
		"thinking":
			return 1.0
		_:
			return 1.02


static func system_voices_available() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not DisplayServer.tts_get_voices().is_empty()


static func stop() -> void:
	_gen += 1
	_speaking = false
	if DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var runner := tree.root.get_node_or_null(RUNNER_NAME)
		if runner:
			if runner.has_method("stop_all"):
				runner.stop_all()
			runner.queue_free()


## Speaks text asynchronously. Never leaves dangling HTTPRequests or streams on stop/exit.
static func speak(host: Node, raw_text: String, emotion: String = "neutral", for_live: bool = false) -> bool:
	var txt := clean_text_for_speech(raw_text)
	if txt == "":
		return false
	var mode := effective_mode(for_live)
	if mode == "blips":
		return false
	stop()
	var mine := _gen
	var cfg := get_config()
	if mode == "tts":
		return await _speak_tts(host, txt, emotion, cfg, mine)
	if mode == "local":
		var ok_local := await _speak_local(host, txt, cfg, mine)
		if ok_local or mine != _gen:
			return ok_local
		return await _speak_tts(host, txt, emotion, cfg, mine)
	if mode == "api":
		var ok_api := await _speak_api(host, txt, cfg, mine)
		if ok_api or mine != _gen:
			return ok_api
		return await _speak_tts(host, txt, emotion, cfg, mine)
	return false


static func _speak_tts(host: Node, txt: String, emotion: String, cfg: Dictionary, mine: int) -> bool:
	if tts_hook.is_valid():
		_speaking = true
		tts_hook.call(txt, cfg)
		_speaking = false
		return true
	if DisplayServer.get_name() == "headless":
		return false
	var voices: Array = DisplayServer.tts_get_voices()
	if voices.is_empty():
		return false
	var chosen_id := _match_system_voice(voices, str(cfg.get("voice_name", "")))
	if chosen_id == "":
		chosen_id = str((voices[0] as Dictionary).get("id", "")) if voices[0] is Dictionary else str(voices[0])
	if chosen_id == "":
		return false
	var vol := int(round(clampf(float(GameState.settings.get("sfx_volume", 0.8)) * 100.0, 10.0, 100.0)))
	var rate := float(cfg.get("rate", 1.05))
	var pitch := pitch_for_emotion(emotion)
	_speaking = true
	DisplayServer.tts_speak(txt, chosen_id, vol, pitch, rate, mine, true)
	var tree := host.get_tree() if host and host.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree:
		var deadline := Time.get_ticks_msec() + 45000
		while mine == _gen and DisplayServer.tts_is_speaking() and Time.get_ticks_msec() < deadline:
			await tree.process_frame
	if mine == _gen:
		_speaking = false
	return true


static func _match_system_voice(voices: Array, wanted: String) -> String:
	var w := wanted.strip_edges().to_lower()
	if w != "":
		for item in voices:
			if item is Dictionary:
				var d := item as Dictionary
				var id := str(d.get("id", ""))
				var name := str(d.get("name", "")).to_lower()
				if id.to_lower().contains(w) or name.contains(w):
					return id
	for item in voices:
		if item is Dictionary and str((item as Dictionary).get("language", "")).to_lower().begins_with("en"):
			return str((item as Dictionary).get("id", ""))
	if not voices.is_empty() and voices[0] is Dictionary:
		return str((voices[0] as Dictionary).get("id", ""))
	return ""


static func _speak_local(host: Node, txt: String, cfg: Dictionary, mine: int) -> bool:
	var url := str(cfg.get("local_url", "")).strip_edges()
	if url == "":
		return false
	var body: Dictionary
	var low := url.to_lower()
	if low.contains("audio/speech") or low.ends_with("/v1"):
		if low.ends_with("/v1"):
			url = url.trim_suffix("/") + "/audio/speech"
		body = {
			"model": str(cfg.get("model", "")) if str(cfg.get("model", "")) != "" else "kokoro",
			"input": txt,
			"voice": str(cfg.get("voice_name", "")) if str(cfg.get("voice_name", "")) != "" else "af_heart",
			"response_format": "wav",
			"speed": float(cfg.get("rate", 1.05)),
		}
	else:
		body = {"text": txt}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var res := await _post_bytes(host, url, headers, JSON.stringify(body), mine)
	if mine != _gen or not res.get("ok", false):
		return false
	var stream := decode_audio_buffer(res.get("bytes", PackedByteArray()))
	if stream == null:
		return false
	return await _play_stream(host, stream, mine)


static func _speak_api(host: Node, txt: String, cfg: Dictionary, mine: int) -> bool:
	var key := str(cfg.get("api_key", "")).strip_edges()
	if key == "":
		key = _fallback_ai_key(str(cfg.get("api_provider", "openai")))
	if key == "":
		return false
	var provider := str(cfg.get("api_provider", "openai"))
	if provider == "gemini":
		return await _speak_gemini(host, txt, cfg, key, mine)
	if provider == "elevenlabs":
		return await _speak_elevenlabs(host, txt, cfg, key, mine)
	var base := str(cfg.get("base_url", "")).strip_edges()
	if base == "":
		base = "https://api.groq.com/openai/v1" if provider == "groq" else "https://api.openai.com/v1"
	var url := base if base.to_lower().ends_with("/audio/speech") else base.trim_suffix("/") + "/audio/speech"
	var model := str(cfg.get("model", ""))
	if model == "":
		model = "playai-tts" if provider == "groq" else "gpt-4o-mini-tts"
	var voice := str(cfg.get("voice_name", ""))
	if voice == "":
		voice = "Fritz-PlayAI" if provider == "groq" else "alloy"
	var body := {
		"model": model,
		"input": txt,
		"voice": voice,
		"response_format": "wav",
		"speed": float(cfg.get("rate", 1.05)),
	}
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + key])
	var res := await _post_bytes(host, url, headers, JSON.stringify(body), mine)
	if mine != _gen or not res.get("ok", false):
		return false
	var stream := decode_audio_buffer(res.get("bytes", PackedByteArray()))
	if stream == null:
		return false
	return await _play_stream(host, stream, mine)


static func _speak_gemini(host: Node, txt: String, cfg: Dictionary, key: String, mine: int) -> bool:
	var model := str(cfg.get("model", ""))
	if model == "":
		model = "gemini-2.5-flash-preview-tts"
	var voice := str(cfg.get("voice_name", ""))
	if voice == "":
		voice = "Kore"
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % model.uri_encode()
	var body := {
		"contents": [{"parts": [{"text": txt}]}],
		"generationConfig": {
			"responseModalities": ["AUDIO"],
			"speechConfig": {
				"voiceConfig": {
					"prebuiltVoiceConfig": {"voiceName": voice},
				},
			},
		},
	}
	var headers := PackedStringArray(["Content-Type: application/json", "x-goog-api-key: " + key])
	var res := await _post_bytes(host, url, headers, JSON.stringify(body), mine)
	if mine != _gen or not res.get("ok", false):
		return false
	var stream := decode_gemini_audio_json((res.get("bytes", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if stream == null:
		return false
	return await _play_stream(host, stream, mine)


static func _speak_elevenlabs(host: Node, txt: String, cfg: Dictionary, key: String, mine: int) -> bool:
	var voice_id := str(cfg.get("voice_name", ""))
	if voice_id == "":
		voice_id = "21m00Tcm4TlvDq8ikWAM"
	var model := str(cfg.get("model", ""))
	if model == "":
		model = "eleven_multilingual_v2"
	var url := "https://api.elevenlabs.io/v1/text-to-speech/%s" % voice_id.uri_encode()
	var body := {"text": txt, "model_id": model}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: audio/mpeg",
		"xi-api-key: " + key,
	])
	var res := await _post_bytes(host, url, headers, JSON.stringify(body), mine)
	if mine != _gen or not res.get("ok", false):
		return false
	var stream := decode_audio_buffer(res.get("bytes", PackedByteArray()))
	if stream == null:
		return false
	return await _play_stream(host, stream, mine)


static func _fallback_ai_key(provider: String) -> String:
	var ai: Dictionary = GameState.settings.get("ai", {}) if GameState else {}
	var keys: Variant = ai.get("keys", {})
	if keys is Dictionary and (keys as Dictionary).has(provider):
		return str((keys as Dictionary).get(provider, "")).strip_edges()
	return str(ai.get("api_key", "")).strip_edges()


## Decodes WAV, MP3, or OGG bytes returned by HTTP TTS APIs into a playable AudioStream.
static func decode_audio_buffer(bytes: PackedByteArray) -> AudioStream:
	if bytes.size() < 12:
		return null
	if bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46:
		return AudioStreamWAV.load_from_buffer(bytes)
	if (bytes[0] == 0x49 and bytes[1] == 0x44 and bytes[2] == 0x33) or (bytes[0] == 0xFF and (bytes[1] & 0xE0) == 0xE0):
		return AudioStreamMP3.load_from_buffer(bytes)
	if bytes[0] == 0x4F and bytes[1] == 0x67 and bytes[2] == 0x67 and bytes[3] == 0x53:
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	return AudioStreamWAV.load_from_buffer(bytes)


## Parses Gemini's generateContent AUDIO JSON response (base64 L16 24kHz PCM -> AudioStreamWAV).
static func decode_gemini_audio_json(json_text: String) -> AudioStream:
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return null
	var cands: Variant = (parsed as Dictionary).get("candidates", [])
	if not (cands is Array) or (cands as Array).is_empty():
		return null
	var first: Variant = (cands as Array)[0]
	if not (first is Dictionary):
		return null
	var parts: Variant = (first as Dictionary).get("content", {}).get("parts", [])
	if not (parts is Array):
		return null
	for p in parts:
		if not (p is Dictionary):
			continue
		var inline: Variant = (p as Dictionary).get("inlineData", {})
		if inline is Dictionary and str((inline as Dictionary).get("data", "")) != "":
			var mime := str((inline as Dictionary).get("mimeType", "audio/pcm")).to_lower()
			var raw := Marshalls.base64_to_raw(str((inline as Dictionary).get("data", "")))
			if raw.is_empty():
				return null
			if mime.contains("wav") or mime.contains("mp3") or mime.contains("ogg") or mime.contains("mpeg"):
				return decode_audio_buffer(raw)
			var rate := 24000
			var idx := mime.find("rate=")
			if idx >= 0:
				var sub := mime.substr(idx + 5).to_int()
				if sub > 0:
					rate = sub
			var wav := AudioStreamWAV.new()
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = rate
			wav.stereo = false
			wav.data = raw
			return wav
	return null


static func _runner(host: Node) -> Node:
	var tree := host.get_tree() if host and host.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null or tree.root == null:
		return null
	var existing := tree.root.get_node_or_null(RUNNER_NAME)
	if existing:
		return existing
	var n: Node = preload("res://scripts/audio/voice_runner.gd").new()
	n.name = RUNNER_NAME
	tree.root.add_child(n)
	return n


static func _post_bytes(host: Node, url: String, headers: PackedStringArray, body_text: String, mine: int) -> Dictionary:
	if http_transport.is_valid():
		var mock_res: Variant = await http_transport.call(url, headers, body_text)
		return mock_res if mock_res is Dictionary else {"ok": false, "bytes": PackedByteArray()}
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "bytes": PackedByteArray()}
	var r := _runner(host)
	if r == null:
		return {"ok": false, "bytes": PackedByteArray()}
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	r.add_child(http)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body_text)
	if err != OK:
		http.queue_free()
		return {"ok": false, "bytes": PackedByteArray()}
	var res: Array = await http.request_completed
	http.queue_free()
	if mine != _gen:
		return {"ok": false, "bytes": PackedByteArray()}
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) < 200 or int(res[1]) >= 300:
		return {"ok": false, "bytes": PackedByteArray()}
	return {"ok": true, "bytes": res[3]}


static func _play_stream(host: Node, stream: AudioStream, mine: int) -> bool:
	var r := _runner(host)
	if r == null:
		return false
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = linear_to_db(maxf(0.05, float(GameState.settings.get("sfx_volume", 0.8))))
	r.add_child(player)
	_speaking = true
	player.play()
	var tree := r.get_tree()
	while mine == _gen and is_instance_valid(player) and player.playing and tree:
		await tree.process_frame
	if is_instance_valid(player):
		player.stop()
		player.stream = null
		player.queue_free()
	if mine == _gen:
		_speaking = false
	return mine == _gen
