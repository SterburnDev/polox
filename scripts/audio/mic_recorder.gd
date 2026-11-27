extends Node
class_name MicRecorder

## Desktop / local microphone capture + STT upload (OpenAI Whisper, Groq Whisper,
## Google Gemini audio transcription, or a Local Whisper-compatible HTTP server).
## Android live speech prefers native RecognizerIntent via AndroidNative first.

const BUS_NAME := "PoloxMicCapture"
const VoiceEngine := preload("res://scripts/audio/voice_engine.gd")

static var transport: Callable = Callable()   # optional test override

var _player: AudioStreamPlayer
var _effect: AudioEffectRecord
var _bus_idx: int = -1
var _recording: bool = false


func is_recording() -> bool:
	return _recording


func start() -> bool:
	stop_and_discard()
	if DisplayServer.get_name() == "headless":
		return false
	if AudioServer.get_input_device_list().is_empty():
		return false
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx < 0:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
		var rec := AudioEffectRecord.new()
		AudioServer.add_bus_effect(_bus_idx, rec, 0)
		var silence := AudioEffectAmplify.new()
		silence.volume_db = -80.0
		AudioServer.add_bus_effect(_bus_idx, silence, 1)
	_effect = AudioServer.get_bus_effect(_bus_idx, 0) as AudioEffectRecord
	if _effect == null:
		return false
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS_NAME
	add_child(_player)
	_player.play()
	_effect.set_recording_active(true)
	_recording = true
	return true


func stop_get_wav() -> PackedByteArray:
	_recording = false
	var wav: AudioStreamWAV = null
	if _effect and _effect.is_recording_active():
		_effect.set_recording_active(false)
		wav = _effect.get_recording()
	_teardown_capture()
	if wav == null:
		return PackedByteArray()
	return encode_wav_16bit(wav)


func stop_and_discard() -> void:
	_recording = false
	if _effect and _effect.is_recording_active():
		_effect.set_recording_active(false)
	_teardown_capture()


func _teardown_capture() -> void:
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null
		_player.queue_free()
	_player = null
	_effect = null
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx >= 0:
		AudioServer.remove_bus(idx)
	_bus_idx = -1


func _exit_tree() -> void:
	stop_and_discard()


## Converts an AudioStreamWAV recording into standard 16-bit PCM RIFF/WAVE bytes.
static func encode_wav_16bit(wav: AudioStreamWAV) -> PackedByteArray:
	if wav == null or wav.data.is_empty():
		return PackedByteArray()
	var pcm := wav.data
	var channels := 2 if wav.stereo else 1
	var bits := 16
	if wav.format == AudioStreamWAV.FORMAT_8_BITS:
		var conv := PackedByteArray()
		conv.resize(pcm.size() * 2)
		for i in range(pcm.size()):
			var signed_8: int = pcm[i] - 256 if pcm[i] > 127 else pcm[i]
			var s16: int = signed_8 * 256
			conv[i * 2] = s16 & 0xFF
			conv[i * 2 + 1] = (s16 >> 8) & 0xFF
		pcm = conv
	var sample_rate := maxi(8000, wav.mix_rate)
	var byte_rate := sample_rate * channels * (bits / 8)
	var block_align := channels * (bits / 8)
	var data_size := pcm.size()
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_data("RIFF".to_utf8_buffer())
	buf.put_32(36 + data_size)
	buf.put_data("WAVE".to_utf8_buffer())
	buf.put_data("fmt ".to_utf8_buffer())
	buf.put_32(16)
	buf.put_16(1)
	buf.put_16(channels)
	buf.put_32(sample_rate)
	buf.put_32(byte_rate)
	buf.put_16(block_align)
	buf.put_16(bits)
	buf.put_data("data".to_utf8_buffer())
	buf.put_32(data_size)
	buf.put_data(pcm)
	return buf.data_array


## Sends WAV bytes to configured STT endpoint (Local Whisper, Groq/OpenAI Whisper, or Gemini).
func transcribe_wav(wav_bytes: PackedByteArray) -> Dictionary:
	if wav_bytes.size() <= 44:
		return {"ok": false, "text": "", "error": "Recording was empty."}
	var v := VoiceEngine.get_config()
	var stt_url := str(v.get("stt_url", "")).strip_edges()
	var ai: Dictionary = GameState.settings.get("ai", {}) if GameState else {}
	var api_provider := str(v.get("api_provider", "openai"))
	var key := str(v.get("api_key", "")).strip_edges()
	if key == "":
		key = VoiceEngine._fallback_ai_key(api_provider)

	if stt_url != "":
		return await _post_whisper_multipart(stt_url, key, "whisper-1", wav_bytes)

	if api_provider == "gemini" or (key == "" and str(ai.get("preset", "")) == "gemini"):
		var gem_key := key if key != "" else VoiceEngine._fallback_ai_key("gemini")
		if gem_key != "":
			return await _post_gemini_stt(gem_key, wav_bytes)

	var ai_preset := str(ai.get("preset", ""))
	if api_provider == "groq" or ai_preset == "groq":
		var g_key := key if key != "" else VoiceEngine._fallback_ai_key("groq")
		if g_key != "":
			return await _post_whisper_multipart("https://api.groq.com/openai/v1/audio/transcriptions", g_key, "whisper-large-v3-turbo", wav_bytes)

	if key != "" and (api_provider == "openai" or api_provider == "custom"):
		var base := str(v.get("base_url", "")).strip_edges()
		if base == "":
			base = "https://api.openai.com/v1"
		var url := base if base.to_lower().ends_with("/audio/transcriptions") else base.trim_suffix("/") + "/audio/transcriptions"
		return await _post_whisper_multipart(url, key, "whisper-1", wav_bytes)

	return {"ok": false, "text": "", "error": "No speech-to-text provider or local Whisper URL is set in Settings > Audio."}


func _post_whisper_multipart(url: String, key: String, model: String, wav_bytes: PackedByteArray) -> Dictionary:
	var boundary := "----PoloxMicBoundary7f3a"
	var body := PackedByteArray()
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n%s\r\n" % [boundary, model]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(wav_bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary])
	if key != "":
		headers.append("Authorization: Bearer " + key)
	var res := await _post_raw(url, headers, body)
	if not res.get("ok", false):
		return {"ok": false, "text": "", "error": str(res.get("error", "Speech transcription failed."))}
	var parsed: Variant = JSON.parse_string(str(res.get("text", "")))
	if parsed is Dictionary and str((parsed as Dictionary).get("text", "")).strip_edges() != "":
		return {"ok": true, "text": str((parsed as Dictionary).get("text", "")).strip_edges(), "error": ""}
	return {"ok": false, "text": "", "error": "Didn't catch any speech."}


func _post_gemini_stt(key: String, wav_bytes: PackedByteArray) -> Dictionary:
	var url := "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
	var payload := {
		"contents": [{
			"parts": [
				{"text": "Transcribe only what the user said verbatim, with normal punctuation and no extra commentary."},
				{"inlineData": {"mimeType": "audio/wav", "data": Marshalls.raw_to_base64(wav_bytes)}},
			],
		}],
	}
	var headers := PackedStringArray(["Content-Type: application/json", "x-goog-api-key: " + key])
	var res := await _post_raw(url, headers, JSON.stringify(payload).to_utf8_buffer())
	if not res.get("ok", false):
		return {"ok": false, "text": "", "error": str(res.get("error", "Gemini speech transcription failed."))}
	var parsed: Variant = JSON.parse_string(str(res.get("text", "")))
	if parsed is Dictionary and (parsed as Dictionary).get("candidates") is Array:
		var cands: Array = (parsed as Dictionary).get("candidates", [])
		if not cands.is_empty() and cands[0] is Dictionary:
			var parts: Variant = (cands[0] as Dictionary).get("content", {}).get("parts", [])
			if parts is Array:
				for p in parts:
					if p is Dictionary and str((p as Dictionary).get("text", "")).strip_edges() != "":
						return {"ok": true, "text": str((p as Dictionary).get("text", "")).strip_edges(), "error": ""}
	return {"ok": false, "text": "", "error": "Didn't catch any speech."}


func _post_raw(url: String, headers: PackedStringArray, raw_body: PackedByteArray) -> Dictionary:
	if transport.is_valid():
		var m: Variant = await transport.call(url, headers, raw_body)
		return m if m is Dictionary else {"ok": false, "text": "", "error": "Test transport returned invalid data."}
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "text": "", "error": "Network requests are disabled in headless tests."}
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var err := http.request_raw(url, headers, HTTPClient.METHOD_POST, raw_body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "text": "", "error": "Couldn't reach the speech server."}
	var done: Array = await http.request_completed
	http.queue_free()
	var code: int = int(done[1]) if done.size() > 1 else 0
	var text := (done[3] as PackedByteArray).get_string_from_utf8() if done.size() > 3 else ""
	if int(done[0]) != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return {"ok": false, "text": "", "error": "Speech server returned error %d." % code}
	return {"ok": true, "text": text, "error": ""}
