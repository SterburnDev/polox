extends SceneTree
## Live API check: one small real request per outside service, sent by the game's own code, and what
## the game made of the answer. It is the evidence behind docs/API_VERIFICATION.md.
##
##   godot --headless --path . --script res://tools/api_live_check.gd -- --save-root=<an empty scratch folder>
##       [--settings=<a settings.json to read keys from>] [--paid] [--only=ollama,venice] [--out=<report.md>]
##       [--only=lookup --lookup-out=<answer.json>]   a whole house lookup of a public landmark (see _lookup)
##
## Without --settings only the keyless requests run: a made-up key has to be refused in words that
## say so, public lists have to contain the models Polox asks for, the map services have to answer.
## With --settings, each provider that has a key in that file is asked for one short answer.
## --paid allows the requests that cost money on a real key (OpenAI and Anthropic: a few cents).
## Keys are never printed or written anywhere; nothing is saved outside --save-root.
## Tags: [AI_HELPER]

const FAKE_KEY := "polox-live-check-not-a-real-key"
const HELLO := [
	{"role": "system", "content": "Reply only with JSON."},
	{"role": "user", "content": "Reply with {\"segments\":[{\"emotion\":\"happy\",\"text\":\"Hello!\"}],\"memory_note\":\"\"}"},
]
## The Eiffel Tower: a public landmark, so no one's home goes to the map services from here.
const LANDMARK := "Tour Eiffel, Paris"
const LANDMARK_LAT := 48.8584
const LANDMARK_LON := 2.2945

var _started := false
var _rows: Array = []
var _keys: Dictionary = {}        # provider -> key, from --settings (never printed)
var _saved_ai: Dictionary = {}
var _saved_light_world: Dictionary = {}
var _paid := false
var _only := PackedStringArray()
var _lookup_out := ""


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	await process_frame
	var out_path := ""
	var has_root := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settings="):
			_read_settings(arg.trim_prefix("--settings="))
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--lookup-out="):
			_lookup_out = arg.trim_prefix("--lookup-out=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
		elif arg == "--paid":
			_paid = true
		elif arg.begins_with("--save-root="):
			has_root = true
	if not has_root:
		printerr("Give --save-root=<an empty scratch folder>: this check must not run on your real save.")
		quit(2)
		return
	_ai().set("backoff_base_s", 0.3)
	var checks := {"groq": _chat.bind("groq"), "gemini": _chat.bind("gemini"), "venice": _chat.bind("venice"),
		"venice_models": _venice_models, "ollama": _ollama, "gemini_native": _gemini_native,
		"anthropic": _anthropic, "openai": _openai, "nominatim": _nominatim, "overpass": _overpass,
		"tailscale": _tailscale, "other_key": _other_key, "lookup": _lookup}
	for name in checks:
		if name == "lookup" and not "lookup" in _only:
			continue   # (a minute of real searching: only when asked for by name)
		if _only.is_empty() or name in _only:
			await (checks[name] as Callable).call()
	_ai().call("configure", {"preset": "mock"})
	var report := _report()
	print(report)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(report)
	var failed := _rows.filter(func(r): return r.result == "FAIL").size()
	quit(1 if failed > 0 else 0)


# --- helpers --------------------------------------------------------------------------------------

func _ai() -> Node:
	return root.get_node("AIClient")   # (autoloads don't exist yet when this script compiles)


func _settings() -> Dictionary:
	return root.get_node("GameState").get("settings")


func _read_settings(path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		printerr("--settings: that file isn't a Polox settings.json.")
		return
	_saved_ai = data.get("ai", {}) if data.get("ai") is Dictionary else {}
	_saved_light_world = data.get("light_world", {}) if data.get("light_world") is Dictionary else {}
	# (As the game does when it loads settings: an old or misfiled key goes to the provider it belongs to.)
	(load("res://scripts/ai/presets.gd") as Script).call("migrate_keys", _saved_ai)
	var keys: Variant = _saved_ai.get("keys", {})
	if keys is Dictionary:
		for provider in keys:
			if str(keys[provider]).strip_edges() != "":
				_keys[str(provider)] = str(keys[provider]).strip_edges()
	for pair in [["openai", "openai_key"], ["anthropic", "claude_api_key"]]:
		if str(_saved_light_world.get(pair[1], "")).strip_edges() != "":
			_keys[pair[0]] = str(_saved_light_world[pair[1]]).strip_edges()


## One line of the report. `detail` is scrubbed of every key this run knows.
func _row(service: String, request: String, result: String, detail: String) -> void:
	var clean := detail.replace(FAKE_KEY, "[made-up key]")
	for provider in _keys:
		clean = clean.replace(str(_keys[provider]), "[key]")
	_rows.append({"service": service, "request": request, "result": result, "detail": clean.replace("\n", " ").replace("|", "/").left(260)})
	print("  [%s] %s: %s" % [result, service, request])


func _report() -> String:
	var lines := PackedStringArray(["| Service | Request | Result | What the game said |", "| --- | --- | --- | --- |"])
	for r in _rows:
		lines.append("| %s | %s | %s | %s |" % [r.service, r.request, r.result, r.detail])
	return "\n".join(lines) + "\n"


func _http_get(url: String, headers: PackedStringArray = PackedStringArray(), timeout_s: float = 20.0) -> Array:
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	root.add_child(http)
	var res: Array = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	if http.request(url, headers) == OK:
		res = await http.request_completed
	http.queue_free()
	return res


# --- the chat providers (scripts/ai/ai_client.gd) ---------------------------------------------------

func _chat(preset: String) -> void:
	var Presets: Script = load("res://scripts/ai/presets.gd")
	var label := str(Presets.call("label", preset))
	var model := str((Presets.call("get_preset", preset) as Dictionary).get("model", ""))
	# 1. A made-up key: the real server must refuse it and the game must say why in plain words.
	_ai().call("configure", {"preset": preset, "keys": {preset: FAKE_KEY}})
	var refused: Dictionary = await _ai().call("chat", HELLO, {"max_tokens": 60})
	var said := str(refused.get("error", ""))
	var understood := not bool(refused.get("ok", false)) and (said.contains("API key") or said.contains("this network"))
	_row(label, "POST chat/completions (%s), made-up key" % model, "ok" if understood else "FAIL",
		"HTTP %d: %s" % [int(refused.get("code", 0)), said])
	# 2. A real key, when the settings file has one for this provider.
	if not _keys.has(preset):
		_row(label, "POST chat/completions (%s), real key" % model, "not run", "No %s key in the settings file given." % label)
		return
	_ai().call("configure", {"preset": preset, "keys": {preset: _keys[preset]}})
	var test: Dictionary = await _ai().call("test_connection")
	_row(label, "POST chat/completions (%s), real key" % model, "ok" if bool(test.ok) else "FAIL", str(test.message))
	var models: PackedStringArray = await _ai().call("list_models")
	_row(label, "GET models, real key", "ok" if model in models else "FAIL", "%d models; default \"%s\" %s." % [models.size(), model, "listed" if model in models else "NOT listed"])


## Venice lists its models without a key: the default one has to be there.
func _venice_models() -> void:
	var Presets: Script = load("res://scripts/ai/presets.gd")
	var model := str((Presets.call("get_preset", "venice") as Dictionary).get("model", ""))
	_ai().call("configure", {"preset": "venice"})
	var models: PackedStringArray = await _ai().call("list_models")
	_row("Venice", "GET models (no key needed)", "ok" if model in models else "FAIL",
		"%d models; default \"%s\" %s." % [models.size(), model, "listed" if model in models else "NOT listed"])


func _ollama() -> void:
	var ai := {"preset": "ollama"}
	if str(_saved_ai.get("preset", "")) == "ollama":
		ai["model"] = str(_saved_ai.get("model", ""))
		ai["base_url"] = str(_saved_ai.get("base_url", ""))
	_ai().call("configure", ai)
	var installed: Array = await _ai().call("ollama_models")
	if installed.is_empty():
		var offline: Dictionary = await _ai().call("chat", HELLO, {"max_tokens": 60})
		var said := str(offline.get("error", ""))
		_row("Ollama", "GET /api/tags, POST /api/chat with Ollama not running", "ok" if said.contains("Ollama") and not bool(offline.get("ok", false)) else "FAIL", said)
		return
	_row("Ollama", "GET /api/tags", "ok", "%d chat models installed." % installed.size())
	_ai().set("config", (_ai().get("config") as Dictionary).merged({"timeout_s": 240.0}, true))
	var test: Dictionary = await _ai().call("test_connection")
	_row("Ollama", "POST /api/chat (%s)" % str((_ai().get("config") as Dictionary).get("model", "")), "ok" if bool(test.ok) else "FAIL", str(test.message))
	# A model that isn't installed: the game must switch to an installed one and still answer.
	var healed: Dictionary = await _ai().call("chat", HELLO, {"max_tokens": 60, "model": "polox-live-check-missing-model:1b"})
	_row("Ollama", "POST /api/chat with a model that isn't installed", "ok" if bool(healed.get("ok", false)) else "FAIL",
		str(_ai().get("last_switch")) if bool(healed.get("ok", false)) else str(healed.get("error", "")))


# --- the home helpers (scripts/home/research.gd, helper_http.gd) -------------------------------------

const TELL_PROMPT := "Reply with only this JSON and nothing else: {\"changes\": [], \"questions\": [\"Is this a test?\"]}"


func _research(light_world: Dictionary, ai: Dictionary) -> Node:
	_settings()["light_world"] = light_world
	_settings()["ai"] = ai
	var node: Node = (load("res://scripts/home/research.gd") as Script).new()
	root.add_child(node)
	node.set("_prompt", TELL_PROMPT)
	node.set("_web", false)
	return node


func _gemini_native() -> void:
	var model := str((load("res://scripts/home/research.gd") as Script).get_script_constant_map().get("GEMINI_MODEL", ""))
	var node := _research({}, {"preset": "gemini", "keys": {"gemini": FAKE_KEY}})
	var refused: Dictionary = await node.call("_gemini")
	node.queue_free()
	_row("Gemini (home helper)", "POST models/%s:generateContent, made-up key" % model,
		"ok" if str(refused.get("why", "")) == "key" else "FAIL", str(refused.get("error", "")))
	if not _keys.has("gemini"):
		_row("Gemini (home helper)", "POST models/%s:generateContent, real key" % model, "not run", "No Gemini key in the settings file given.")
		return
	node = _research({}, {"preset": "gemini", "keys": {"gemini": _keys.gemini}})
	var answer: Dictionary = await node.call("_gemini")
	node.queue_free()
	_row("Gemini (home helper)", "POST models/%s:generateContent, real key" % model,
		"ok" if bool(answer.get("ok", false)) or str(answer.get("why", "")) == "shape" else "FAIL",
		"answered" if bool(answer.get("ok", false)) else str(answer.get("error", "")))


func _anthropic() -> void:
	var model := str((load("res://scripts/home/research.gd") as Script).get_script_constant_map().get("CLAUDE_MODEL", ""))
	var node := _research({"claude_api_key": FAKE_KEY}, {})
	var refused: Dictionary = await node.call("_claude_api")
	node.queue_free()
	_row("Anthropic (home helper)", "POST /v1/messages (%s), made-up key" % model,
		"ok" if str(refused.get("why", "")) == "key" else "FAIL", str(refused.get("error", "")))
	if not _keys.has("anthropic") or not _paid:
		_row("Anthropic (home helper)", "POST /v1/messages (%s), real key" % model, "not run",
			"No Anthropic key in the settings file given." if not _keys.has("anthropic") else "Costs money: run with --paid.")
		return
	node = _research({"claude_api_key": _keys.anthropic}, {})
	var answer: Dictionary = await node.call("_claude_api")
	node.queue_free()
	_row("Anthropic (home helper)", "POST /v1/messages (%s), real key" % model,
		"ok" if bool(answer.get("ok", false)) or str(answer.get("why", "")) == "shape" else "FAIL",
		"answered" if bool(answer.get("ok", false)) else str(answer.get("error", "")))


func _openai() -> void:
	var Tell: Script = load("res://scripts/home/tell_polox.gd")
	var schema: Dictionary = Tell.get_script_constant_map().get("WORDS_SCHEMA", {})
	var model := str(_saved_light_world.get("openai_model", "")).strip_edges()
	var helper: Node = (load("res://scripts/home/helper_http.gd") as Script).new()
	root.add_child(helper)
	var refused: Dictionary = await helper.call("run", "openai", {"openai_key": FAKE_KEY, "openai_model": model if model != "" else "gpt-5"}, TELL_PROMPT, schema, false)
	_row("OpenAI (home helper)", "POST /v1/responses, made-up key", "ok" if str(refused.get("why", "")) == "key" else "FAIL", str(refused.get("error", "")))
	if not _keys.has("openai") or model == "" or not _paid:
		_row("OpenAI (home helper)", "POST /v1/responses, real key", "not run",
			"No OpenAI key and model in the settings file given." if not _keys.has("openai") or model == "" else "Costs money: run with --paid.")
		helper.queue_free()
		return
	var answer: Dictionary = await helper.call("run", "openai", {"openai_key": _keys.openai, "openai_model": model}, TELL_PROMPT, schema, false)
	helper.queue_free()
	_row("OpenAI (home helper)", "POST /v1/responses (%s), real key, structured output" % model, "ok" if bool(answer.get("ok", false)) else "FAIL",
		("answered with the asked JSON shape: " + JSON.stringify(answer.get("value", {})).left(120)) if bool(answer.get("ok", false)) else str(answer.get("error", "")))


# --- the map services (scripts/home/osm.gd) ----------------------------------------------------------

func _nominatim() -> void:
	_settings()["light_world"] = {}
	var osm: Node = (load("res://scripts/home/osm.gd") as Script).new()
	root.add_child(osm)
	var found: Dictionary = await osm.call("locate", LANDMARK)
	osm.queue_free()
	var candidates: Array = found.get("candidates", []) if found.get("candidates") is Array else []
	var near := false
	for c in candidates:
		if c is Dictionary and absf(float(c.get("lat", 0.0)) - LANDMARK_LAT) < 0.02 and absf(float(c.get("lon", 0.0)) - LANDMARK_LON) < 0.02:
			near = true
	_row("OpenStreetMap Nominatim", "GET /search (a public landmark)", "ok" if near else "FAIL",
		("%d place(s) found, one at the landmark." % candidates.size()) if near else str(found.get("error", found.get("state", ""))))


func _overpass() -> void:
	# Each server the player can choose in Settings is asked by itself (the game never switches server
	# behind the player's back, so a busy one has to say so and point at the choice).
	var servers: Array = (load("res://scripts/home/osm.gd") as Script).get_script_constant_map().get("MAP_SERVERS", [])
	for server in servers:
		_settings()["light_world"] = {"overpass_url": str(server[1])}
		var osm: Node = (load("res://scripts/home/osm.gd") as Script).new()
		root.add_child(osm)
		var box := {"done": false, "result": {}}
		osm.connect("finished", func(result: Dictionary):
			box.done = true
			box.result = result)
		osm.call("fetch", LANDMARK_LAT, LANDMARK_LON, 120, true)
		var waited := 0.0
		while not box.done and waited < 120.0:
			await create_timer(0.25).timeout
			waited += 0.25
		osm.queue_free()
		var result: Dictionary = box.result
		var extract: Dictionary = result.get("extract", {}) if result.get("extract") is Dictionary else {}
		var features: Array = extract.get("features", []) if extract.get("features") is Array else []
		var error := str(result.get("error", "no answer in 120 s"))
		var busy_but_clear := not bool(result.get("ok", false)) and error.contains("pick another map server")
		_row("OpenStreetMap Overpass", "POST %s (120 m around a public landmark)" % str(server[1]).trim_prefix("https://"),
			"ok" if bool(result.get("ok", false)) else ("busy" if busy_but_clear else "FAIL"),
			("%d map features, state \"%s\"." % [features.size(), str(result.get("state", ""))]) if bool(result.get("ok", false)) else error)
	_settings()["light_world"] = {}


# --- Tailscale on this PC (scripts/phone/tailscale.gd) -------------------------------------------------

## Read-only: `tailscale status --json` and `tailscale serve status --json` through the game's wrapper.
## Nothing is switched on or off, and no name or address is reported.
func _tailscale() -> void:
	var ts: RefCounted = (load("res://scripts/phone/tailscale.gd") as Script).new()
	if not bool(ts.call("installed")):
		_row("Tailscale (this PC)", "tailscale status --json", "not run", "Tailscale isn't installed on this PC.")
		return
	var status: Dictionary = ts.call("status")
	var understood := bool(status.get("running", false)) and str(status.get("dns_name", "")) != ""
	_row("Tailscale (this PC)", "tailscale status --json", "ok" if understood or str(status.get("error", "")) != "" else "FAIL",
		("running, signed in: %s, MagicDNS: %s, HTTPS certificates: %s, %d other device(s)" % [str(status.get("logged_in", false)), str(status.get("magicdns", false)),
			str(status.get("https", false)), (status.get("peers", []) as Array).size()]) if understood else str(status.get("error", "not running")))
	if not understood:
		return
	var serve: Dictionary = ts.call("serve_status", str(status.dns_name))
	var public_ports: int = (serve.get("funnel", {}) as Dictionary).size()
	_row("Tailscale (this PC)", "tailscale serve status --json", "ok",
		"%d Serve mapping(s) read; %d of them public (Funnel). Polox never turns Funnel on." % [(serve.get("ports", {}) as Dictionary).size(), public_ports])


# --- a whole house lookup ----------------------------------------------------------------------------

## A public museum building (a house that anyone may visit), never anyone's home.
const LOOKUP_PLACE := "Frank Lloyd Wright Home and Studio, 951 Chicago Avenue, Oak Park, Illinois, USA (a public museum)"


## The Light World's lookup from end to end, for real: the prompt the game writes (how the game works,
## how the house gets built, which tools to use, what to find out), Gemini searching the web with it,
## and its answer through the same strict check as any helper's. Reports what kinds of thing came
## back (never the text), and saves the answer with --lookup-out for a drive to build from.
func _lookup() -> void:
	var service := "House lookup (Gemini with Google Search)"
	if not _keys.has("gemini"):
		_row(service, "the game's whole prompt, a public landmark", "not run", "No Gemini key in the settings file given.")
		return
	_settings()["light_world"] = {}
	_settings()["ai"] = {"preset": "gemini", "keys": {"gemini": _keys.gemini}}
	var node: Node = (load("res://scripts/home/research.gd") as Script).new()
	root.add_child(node)
	var started := Time.get_ticks_msec()
	node.call("start", "gemini", LOOKUP_PLACE, {"home_type": "house", "floors": 2})
	var res: Dictionary = await node.finished
	node.queue_free()
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	if not bool(res.get("ok", false)):
		_row(service, "the game's whole prompt, a public landmark", "FAIL", "%s (%s, %.0f s)" % [str(res.get("error", "")), str(res.get("why", "")), seconds])
		return
	var research: Dictionary = res.get("research", {})
	var keys := {}
	for f in research.get("facts", []):
		keys[str(f.key)] = true
	var kinds := {}
	for s in research.get("sources", []):
		kinds[str(s.kind)] = true
	var look: Dictionary = (load("res://scripts/home/home_look.gd") as Script).call("of", research)
	var fact_keys: Array = keys.keys()
	fact_keys.sort()
	var source_kinds: Array = kinds.keys()
	source_kinds.sort()
	_row(service, "the game's whole prompt, a public landmark", "ok" if int(res.get("searched", 0)) > 0 else "FAIL",
		"%.0f s, %d web searches; %d facts (%s); %d sources (%s); %d rooms; colours the builder can use: %s; year built found: %s" % [
			seconds, int(res.get("searched", 0)), (research.get("facts", []) as Array).size(), ", ".join(PackedStringArray(fact_keys)),
			(research.get("sources", []) as Array).size(), ", ".join(PackedStringArray(source_kinds)), (research.get("rooms", []) as Array).size(),
			", ".join(PackedStringArray(look.keys())) if not look.is_empty() else "none", str(keys.has("year_built"))])
	if _lookup_out != "":
		var f := FileAccess.open(_lookup_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(res.get("raw", {}), "  "))


# --- a key Polox couldn't place ----------------------------------------------------------------------

## A key kept under "custom" because its prefix was unknown: is it one Google accepts? (Only yes or no
## is reported.) Reading the list of models is free and changes nothing.
func _other_key() -> void:
	if not _keys.has("custom"):
		return
	var res := await _http_get("https://generativelanguage.googleapis.com/v1beta/models?pageSize=1", PackedStringArray(["x-goog-api-key: " + str(_keys.custom)]))
	var accepted := int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200
	_row("A key filed under \"Custom server\"", "GET Google's model list with it", "ok",
		"Google accepts this key: it is a Gemini key." if accepted else "Google does not accept this key (HTTP %d): it belongs to some other service." % int(res[1]))
