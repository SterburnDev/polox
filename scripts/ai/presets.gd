extends RefCounted
## Provider presets. All speak the OpenAI-compatible /chat/completions format (Ollama also its own
## /api/chat, which ai_client.gd uses for it), so switching provider is a different base_url + model
## (+ that provider's own key).
##
## Keys are kept per provider (settings.ai.keys = {provider: key}): a key typed for one service is only
## ever sent to that service, never to a local Ollama or a custom server picked later. An old single
## "api_key" moves once to the provider it belongs to (migrate_keys).
## Tags: [AI_HELPER]

const KeyFormat := preload("res://scripts/ai/key_format.gd")

const ORDER: PackedStringArray = ["mock", "groq", "gemini", "venice", "ollama", "custom"]
## Providers whose key, if any, is the user's own and stays with them.
const KEYED: PackedStringArray = ["groq", "gemini", "venice", "custom"]

const PRESETS := {
	"mock": {
		"label": "Offline (no AI)",
		"base_url": "",
		"model": "mock",
		"needs_key": false,
		"timeout_s": 20,
		"extra": {},
		"help": "No internet needed.",
	},
	"groq": {
		"label": "Groq (free cloud)",
		"base_url": "https://api.groq.com/openai/v1",
		"model": "openai/gpt-oss-20b",
		"needs_key": true,
		"timeout_s": 20,
		# gpt-oss is a reasoning model; low effort keeps replies fast and cheap.
		"extra": {"reasoning_effort": "low"},
		"help": "Free key: console.groq.com/keys",
	},
	"gemini": {
		"label": "Google Gemini (free cloud)",
		"base_url": "https://generativelanguage.googleapis.com/v1beta/openai/",
		"model": "gemini-3.5-flash-lite",
		"needs_key": true,
		"timeout_s": 20,
		"extra": {},
		"help": "Free key: aistudio.google.com/apikey",
	},
	"venice": {
		"label": "Venice (private cloud)",
		"base_url": "https://api.venice.ai/api/v1",
		"model": "zai-org-glm-5",
		"needs_key": true,
		"timeout_s": 45,
		# Venice adds a system prompt of its own unless told not to (the friend's own words come
		# first), and its reasoning models answer faster for chat without visible thinking.
		"extra": {"venice_parameters": {"include_venice_system_prompt": false, "disable_thinking": true, "strip_thinking_response": true}},
		"help": "Key: venice.ai/settings/api",
	},
	"ollama": {
		"label": "Ollama (local & private)",
		"base_url": "http://127.0.0.1:11434/v1",
		"model": "",   # the first model installed on this PC (List models picks another, your own included)
		"needs_key": false,
		# Local models can take a while to load into memory on the first message.
		"timeout_s": 90,
		"warm_timeout_s": 30,
		"extra": {},
		"help": "On this PC (ollama.com). Your models: List models.",
	},
	# Phone Link: a paired phone asks the PC, which asks the real AI (the key stays on the PC).
	"pc": {
		"label": "Your PC (Phone Link)",
		"base_url": "",
		"model": "pc",
		"needs_key": false,
		"timeout_s": 120,
		"extra": {},
		"help": "Through your PC.",
	},
	"custom": {
		"label": "Custom server",
		"base_url": "",
		"model": "",
		"needs_key": false,
		"timeout_s": 30,
		"extra": {},
		"help": "Any OpenAI-style /chat/completions server.",
	},
}


static func get_preset(id: String) -> Dictionary:
	return PRESETS.get(id, PRESETS["custom"])


static func label(id: String) -> String:
	return str(get_preset(id).get("label", id))


## This provider's own key ("" when it has none). A key that is plainly another service's (by its
## mark, key_format.gd) is never this provider's, wherever it was filed: it would be sent there.
static func key_for(ai: Dictionary, id: String) -> String:
	var keys: Variant = ai.get("keys", {})
	var key := ""
	if keys is Dictionary and str((keys as Dictionary).get(id, "")).strip_edges() != "":
		key = str(keys[id]).strip_edges()
	elif id in KEYED:
		key = str(ai.get("api_key", "")).strip_edges()   # (a settings file not migrated yet, or a test)
	return key if KeyFormat.fits(key, id) else ""


## The old single key -> the provider it belongs to: by its well-known prefix, else the provider that
## was chosen with it (or "custom" when that needs no key, so it is never sent to a local Ollama).
## True when settings changed.
static func migrate_keys(ai: Dictionary) -> bool:
	var old := str(ai.get("api_key", "")).strip_edges()
	if not ai.has("api_key"):
		var moved := refile_keys(ai)
		return adopt_misfiled_key(ai) or moved
	ai.erase("api_key")
	if old == "":
		return true
	var keys: Dictionary = ai.get("keys", {}) if ai.get("keys") is Dictionary else {}
	var owner := guess_owner(old, str(ai.get("preset", "mock")))
	if str(keys.get(owner, "")) == "":
		keys[owner] = old
	ai["keys"] = keys
	return true


## Whose key it is by its mark (key_format.gd: Groq's gsk_, Google's AIza and the newer AQ., which
## Polox had filed under "Custom server" until 1.29, Venice's own), else the provider chosen with it.
## A key of a service that isn't a chat provider here (OpenAI's and Anthropic's sk-) is kept under
## "custom": it is sent only to a server the player points Polox at themselves.
static func guess_owner(key: String, preset: String) -> String:
	var whose := KeyFormat.kind(key)
	if whose in KEYED:
		return whose
	return preset if preset in KEYED and whose == "" else "custom"


## A key filed under a provider whose it plainly isn't (an older version, or a hand-edited file)
## moves to its own provider, or to "custom", when nothing is there yet. If something is, it stays
## where it was, unused (key_for). True when settings changed.
static func refile_keys(ai: Dictionary) -> bool:
	var keys: Variant = ai.get("keys", {})
	if not keys is Dictionary:
		return false
	var changed := false
	for id in KeyFormat.CHAT_SLOTS:
		var filed := str((keys as Dictionary).get(id, "")).strip_edges()
		if filed == "" or KeyFormat.fits(filed, id):
			continue
		var owner := guess_owner(filed, id)
		if str((keys as Dictionary).get(owner, "")).strip_edges() in ["", filed]:
			keys[owner] = filed
			keys.erase(id)
			changed = true
	return changed


## A key that an older version filed under "Custom server" although its prefix says whose it is: that
## provider gets it too, if it has none (the custom entry stays as it was). True when settings changed.
static func adopt_misfiled_key(ai: Dictionary) -> bool:
	var keys: Variant = ai.get("keys", {})
	if not keys is Dictionary:
		return false
	var filed := str((keys as Dictionary).get("custom", "")).strip_edges()
	var owner := guess_owner(filed, "custom")
	if filed == "" or owner == "custom" or str((keys as Dictionary).get(owner, "")).strip_edges() != "":
		return false
	keys[owner] = filed
	return true


## Fills base_url/model/timeout from the preset when the user left them blank (or switched presets), and
## the provider's own key, so settings.json can stay minimal.
static func resolve(ai: Dictionary) -> Dictionary:
	var id := str(ai.get("preset", "mock"))
	var preset := get_preset(id)
	var out := ai.duplicate(true)
	if str(out.get("base_url", "")).strip_edges() == "":
		out["base_url"] = preset.get("base_url", "")
	if str(out.get("model", "")).strip_edges() == "":
		out["model"] = preset.get("model", "")
	if not out.has("timeout_s") or float(out.get("timeout_s", 0)) <= 0 or (id == "ollama" and is_equal_approx(float(out.get("timeout_s", 0)), 20.0)):
		out["timeout_s"] = preset.get("timeout_s", 20)
	if preset.has("warm_timeout_s") and (not out.has("warm_timeout_s") or float(out.get("warm_timeout_s", 0)) <= 0):
		out["warm_timeout_s"] = preset.get("warm_timeout_s", 30)
	out["api_key"] = key_for(ai, id)
	out.erase("keys")
	out["needs_key"] = preset.get("needs_key", false)
	out["extra"] = (preset.get("extra", {}) as Dictionary).duplicate(true)
	out["reasoning_effort"] = normalize_effort(str(ai.get("reasoning_effort", "auto")))
	out["web_search"] = bool(ai.get("web_search", false))
	return out


static func effort_ids() -> Array[String]:
	return ["auto", "off", "low", "medium", "high"]


static func normalize_effort(raw: String) -> String:
	var low := raw.strip_edges().to_lower()
	if low in effort_ids():
		return low
	return "auto"


static func uses_native_search(cfg: Dictionary) -> bool:
	var preset := str(cfg.get("preset", ""))
	var url := str(cfg.get("base_url", "")).to_lower()
	return preset in ["gemini", "venice"] or url.contains("generativelanguage.googleapis.com") or url.contains("api.venice.ai") or url.contains("openrouter.ai")


static func apply_reasoning_and_search(body: Dictionary, cfg: Dictionary, opts: Dictionary, allow_reasoning: bool, allow_search: bool) -> void:
	var preset := str(cfg.get("preset", ""))
	var url := str(cfg.get("base_url", "")).to_lower()
	var effort := normalize_effort(str(opts.get("reasoning_effort", cfg.get("reasoning_effort", "auto"))))
	if allow_reasoning and effort != "auto":
		body["reasoning_effort"] = "none" if effort == "off" else effort
	if allow_search:
		if preset == "venice" or url.contains("api.venice.ai"):
			var vp: Dictionary = (body.get("venice_parameters", {}) as Dictionary).duplicate()
			vp["enable_web_search"] = "on"
			body["venice_parameters"] = vp
		elif url.contains("openrouter.ai"):
			var plugins: Array = (body.get("plugins", []) as Array).duplicate()
			var has_web := false
			for p in plugins:
				if p is Dictionary and str((p as Dictionary).get("id", "")) == "web":
					has_web = true
					break
			if not has_web:
				plugins.append({"id": "web"})
			body["plugins"] = plugins


## Every key in the settings (so ChatLog can keep all of them out of logs).
static func all_keys(ai: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var keys: Variant = ai.get("keys", {})
	if keys is Dictionary:
		for k in keys:
			if str(keys[k]).strip_edges() != "":
				out.append(str(keys[k]).strip_edges())
	if str(ai.get("api_key", "")).strip_edges() != "":
		out.append(str(ai.api_key).strip_edges())
	return out


## "localhost" is rewritten to 127.0.0.1: Godot may try IPv6 (::1) first, and
## local servers like Ollama usually listen on IPv4 only, which made
## requests hang until the timeout.
static func endpoint(base_url: String, route: String = "chat/completions") -> String:
	var base := base_url.strip_edges().trim_suffix("/").replace("://localhost", "://127.0.0.1")
	return base + "/" + route


## Ollama's own address from its OpenAI-style one: http://127.0.0.1:11434/v1 -> http://127.0.0.1:11434
static func ollama_host(base_url: String) -> String:
	var base := base_url.strip_edges().trim_suffix("/").replace("://localhost", "://127.0.0.1")
	if base.ends_with("/v1"):
		base = base.left(-3)
	return base if base != "" else "http://127.0.0.1:11434"
