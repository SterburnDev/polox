extends RefCounted
## Whose key is this? An API key carries its maker's mark at the front, and Polox reads it so that a
## key is only ever kept for (and so only ever sent to) the service it belongs to. A key with no
## known mark belongs wherever the player put it: Venice publishes no format for its keys, and a
## custom server can hand out anything.
##
## Also here, because they need the same knowledge: tidying a pasted key, the keys kept in settings
## (for ChatLog), and taking anything shaped like a key out of text on its way to a log or a report.
## Tags: [AI_HELPER] [PERSONAL_DATA]

## The front of a key -> whose it is. Order matters where one mark begins with another.
const MARKS := [
	["sk-ant-", "anthropic"],
	["sk-or-", "openrouter"],
	["sk-", "openai"],   # sk-proj-, sk-svcacct-, sk-admin- and the older plain sk-
	["gsk_", "groq"],
	["AIza", "gemini"],
	["AQ.", "gemini"],   # Google's newer kind
	["VENICE-", "venice"],
]
const NAMES := {"anthropic": "Claude (Anthropic)", "openai": "OpenAI", "openrouter": "OpenRouter", "groq": "Groq",
	"gemini": "Google Gemini", "venice": "Venice"}
## Settings > AI providers that take a key of their own kind (Custom server takes any).
const CHAT_SLOTS: PackedStringArray = ["groq", "gemini", "venice"]
## Settings > Light World > Helper setup: the setting -> whose key it holds.
const HELPER_SLOTS := {"claude_api_key": "anthropic", "openai_key": "openai", "compatible_key": "custom", "google_maps_api_key": "gemini"}
const HELPER_BOXES := {"anthropic": "Claude API key", "openai": "OpenAI API key", "gemini": "Google Maps API key"}

static var _shapes: RegEx


## "anthropic", "openai", "openrouter", "groq", "gemini", "venice", or "" when the key has no known mark.
static func kind(key: String) -> String:
	var k := key.strip_edges()
	for mark in MARKS:
		if k.begins_with(str(mark[0])):
			# Still being typed and it could yet be a longer mark ("sk-a" on its way to "sk-ant-"):
			# not known yet, rather than called OpenAI's for a moment.
			for longer in MARKS:
				if str(longer[0]).length() > k.length() and str(longer[0]).begins_with(k):
					return ""
			return str(mark[1])
	return ""


## May this key be kept in this slot (a provider id, or "custom")? Only a key known to be someone
## else's is turned away: an unknown one is the player's call.
static func fits(key: String, slot: String) -> bool:
	var whose := kind(key)
	return slot == "custom" or whose == "" or whose == slot


## The Settings > AI provider to choose for this key ("" when its kind isn't one of them).
static func chat_slot(key: String) -> String:
	var whose := kind(key)
	return whose if whose in CHAT_SLOTS else ""


## Why this key isn't kept in this slot, and where it goes instead ("" when it fits).
static func mismatch(key: String, slot: String) -> String:
	if fits(key, slot):
		return ""
	var whose := kind(key)
	var in_chat := slot in CHAT_SLOTS
	var where := ""
	if whose in CHAT_SLOTS:
		where = ("Choose %s as the provider and paste it there." if in_chat else "It goes in Settings > AI, with %s as the provider.") % NAMES[whose]
	elif whose == "openrouter":
		where = "Choose Custom server and paste it there." if in_chat else "It goes in the Compatible key box."
	elif in_chat:
		where = "The home helper uses it: Settings > Light World > Helper setup." + (" For chats, choose Custom server." if whose == "openai" else "")
	else:
		where = "It goes in the %s box." % HELPER_BOXES[whose]
	return "That is a %s key, not a %s one, so it isn't kept here and is never sent to %s. %s" % [NAMES[whose], NAMES.get(slot, slot), NAMES.get(slot, slot), where]


## A key as it was pasted -> the key itself: without the spaces and line breaks around or inside it,
## quotes, "Bearer ", or the NAME= of a line copied from a terminal.
static func clean(pasted: String) -> String:
	var t := pasted.strip_edges()
	var named := RegEx.create_from_string("^(?:export\\s+|set\\s+|\\$env:)?[A-Z0-9_]*(?:KEY|TOKEN)[A-Z0-9_]*\\s*=\\s*(.{8,})$").search(t)
	if named:
		t = named.get_string(1).strip_edges()
	if t.to_lower().begins_with("bearer "):
		t = t.substr(7)
	var out := ""
	for c in t:
		var code := c.unicode_at(0)
		if code > 32 and code != 127 and not c in ["\"", "'", "`", "​", "﻿", " "]:
			out += c
	return out


## Every key kept in the settings: Settings > AI's (one per provider, and an old single one) and the
## home helpers'. ChatLog keeps all of them out of what it writes.
static func stored(settings: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var ai: Variant = settings.get("ai")
	if ai is Dictionary:
		var keys: Variant = (ai as Dictionary).get("keys")
		if keys is Dictionary:
			for id in keys:
				out.append(str(keys[id]).strip_edges())
		out.append(str((ai as Dictionary).get("api_key", "")).strip_edges())
	var lw: Variant = settings.get("light_world")
	if lw is Dictionary:
		for k in HELPER_SLOTS:
			out.append(str((lw as Dictionary).get(k, "")).strip_edges())
	var voice: Variant = settings.get("voice")
	if voice is Dictionary:
		out.append(str((voice as Dictionary).get("api_key", "")).strip_edges())
	var real := PackedStringArray()
	for k in out:
		if k != "" and not k in real:
			real.append(k)
	return real


## A fresh pattern for anything shaped like a known key (a caller on another thread keeps its own).
static func shapes() -> RegEx:
	return RegEx.create_from_string("(?<![A-Za-z0-9])(?:sk-[A-Za-z0-9_\\-]{16,}|gsk_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_\\-]{24,}|AQ\\.[A-Za-z0-9_\\-.]{16,}|VENICE-[A-Za-z0-9_\\-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|hf_[A-Za-z0-9]{20,}|xai-[A-Za-z0-9_\\-]{16,}|pplx-[A-Za-z0-9_\\-]{16,}|AKIA[0-9A-Z]{16})")


## The text with anything shaped like a known key taken out, whether or not it is one of the
## player's own: for logs, exports and crash reports.
static func scrub(text: String, pattern: RegEx = null) -> String:
	if pattern == null:
		if _shapes == null:
			_shapes = shapes()
		pattern = _shapes
	return pattern.sub(text, "[redacted]", true) if text.length() >= 19 else text
