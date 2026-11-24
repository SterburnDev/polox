extends Node
## Explicit home-helper request to the paired PC. No retries: a lookup may
## incur provider charges. The PC checks the provider still matches consent.
##
## The wait is a frame loop, like helper_http.gd's: HTTPRequest.cancel_request() never emits
## request_completed, so waiting on that signal left a cancelled call suspended for good with its
## request node still in the tree. Every way out of run() frees the request node.
## Tags: [AI_HELPER]

const JsonUtil := preload("res://scripts/core/json_util.gd")
const RequestSig := preload("res://scripts/phone/request_sig.gd")

## Set by cancel(): run() answers {"why": "cancelled"} at the next frame and nothing is read late.
var cancelled := false
var _http: HTTPRequest


func run(phone: Node, provider: String, prompt: String, schema: Dictionary, web: bool) -> Dictionary:
	if phone == null or not phone.paired():
		return {"ok": false, "error": "Connect to your PC first.", "why": "offline"}
	if is_instance_valid(_http):
		return {"ok": false, "error": "The PC helper is already working on a request.", "why": "busy"}
	if not is_inside_tree():
		return {"ok": false, "error": "Couldn't reach your PC. Reconnect and try again.", "why": "offline"}
	cancelled = false
	var http := HTTPRequest.new()
	http.timeout = 600.0
	http.body_size_limit = 2 * 1024 * 1024
	http.max_redirects = 0
	_http = http
	add_child(http)
	var box := {"done": false, "reply": []}
	http.request_completed.connect(func(a, b, c, d) -> void:
		box.done = true
		box.reply = [a, b, c, d])
	var body := JSON.stringify({"provider": provider, "prompt": prompt, "schema": schema, "web": web})
	var signs: bool = phone.get("signs") == true   # (phone_mode.gd: paired with pair_v:1, so it signs)
	var signed := RequestSig.signed(str(phone.token), "POST", "/api/home-helper", body.to_utf8_buffer()) if signs else {}
	var headers := PackedStringArray(["Content-Type: application/json", str(signed.header) if signs else "Authorization: Bearer " + str(phone.token)])
	var error := http.request(str(phone.origin).trim_suffix("/") + "/api/home-helper", headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_release()
		return {"ok": false, "error": "Couldn't reach your PC. Reconnect and try again.", "why": "offline"}
	var deadline := Time.get_ticks_msec() + 615000
	while not bool(box.done) and not cancelled and is_inside_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var reply: Array = box.reply
	_release()
	if cancelled or not is_inside_tree():
		return {"ok": false, "error": "Cancelled.", "why": "cancelled"}
	if not bool(box.done):
		return {"ok": false, "error": "The PC didn't answer in time.", "why": "timeout"}
	# (An answer that never arrived has no body: it is not parsed, so nothing is logged as a JSON error.)
	var value: Variant = null
	if reply.size() >= 4 and int(reply[0]) == HTTPRequest.RESULT_SUCCESS and reply[3] is PackedByteArray:
		if signs and not RequestSig.verify_answer(str(phone.token), str(signed.nonce), int(reply[1]), reply[2], reply[3]):
			return {"ok": false, "error": "The PC's answer didn't verify: possible interference on the network.", "why": "offline"}
		value = JsonUtil.parse((reply[3] as PackedByteArray).get_string_from_utf8())
	if not value is Dictionary:
		return {"ok": false, "error": "The PC didn't finish the request. Reconnect before trying again.", "why": "offline"}
	return value


func cancel() -> void:
	cancelled = true
	if is_instance_valid(_http):
		_http.cancel_request()


func _exit_tree() -> void:
	cancel()


func _release() -> void:
	if is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
	_http = null
