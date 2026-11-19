extends RefCounted
## Brings a character from Character.AI, Chai or another chat app into Polox as a friend, to talk with
## through whichever AI Polox uses (Ollama, Venice...). Neither Character.AI nor Chai offers an API
## Polox could call, so the character comes over instead of the chat:
##   - a character card file (.json, or .png with the card inside): the "chara_card_v2" / "v3" format
##     that SillyTavern, chub and the Character.AI export tools write, or the older flat one;
##   - or text pasted from the app: "Name: ...", "Greeting: ...", "Description: ..." lines, or just a
##     description (the name is asked for).
## {{char}} and {{user}} in a card become the character's and your names. Long texts are kept to sizes
## a small local model can carry. Nothing is sent anywhere by importing.

const Defaults := preload("res://scripts/core/defaults.gd")
const SpriteFactory := preload("res://scripts/characters/sprite_factory.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const MAX_FIELD := 1500        # characters per description-like field
const MAX_EXAMPLES := 1500
const MAX_GREETING := 600
const SPRITE_HEIGHT := 128     # the card's picture, fitted (actors scale any picture to one height)
const LABELS := {
	"name": ["name", "character", "character name", "bot name"],
	"greeting": ["greeting", "first message", "first_mes", "opening", "intro"],
	"personality": ["personality", "traits"],
	"description": ["description", "definition", "about", "bio", "persona", "long description"],
	"scenario": ["scenario", "setting", "story"],
	"examples": ["example dialogue", "examples", "example messages", "mes_example", "dialogue"],
	"speech": ["speech style", "voice", "how they talk"],
}


## A card from text: JSON (a card), or labelled/plain text. {ok, card, error}.
static func from_text(text: String, from: String = "") -> Dictionary:
	var t := text.strip_edges()
	if t == "":
		return {"ok": false, "error": "Paste a character card or the character's description first."}
	if t.begins_with("{"):
		var data: Variant = JSON.parse_string(t)
		if not data is Dictionary:
			return {"ok": false, "error": "That looks like JSON but doesn't read as a character card."}
		return from_card(data, from)
	return from_labelled(t, from)


## A card from a file: .json or a .png holding a card ("chara" / "ccv3" text chunk). {ok, card, error}.
static func from_file(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "That file isn't there."}
	if FileAccess.get_file_as_bytes(path).size() > 20 * 1024 * 1024:
		return {"ok": false, "error": "That file is too big for a character card."}
	if ext == "json":
		return from_text(FileAccess.get_file_as_string(path))
	if ext == "png":
		var bytes := FileAccess.get_file_as_bytes(path)
		var json := png_card_text(bytes)
		var img := Image.new()
		var picture: Image = img if img.load_png_from_buffer(bytes) == OK else null
		if json == "":
			if picture == null:
				return {"ok": false, "error": "That picture couldn't be read."}
			return {"ok": false, "error": "That picture has no character card inside. Paste the character's text instead.", "picture_only": true}
		var r := from_text(json)
		if r.ok and picture:
			r.card["picture"] = picture
		return r
	return {"ok": false, "error": "Choose a .json or .png character card."}


## The card JSON inside a PNG: a tEXt or uncompressed iTXt chunk named "ccv3" (preferred) or "chara",
## base64. "" when there is none.
static func png_card_text(bytes: PackedByteArray) -> String:
	if bytes.size() < 8 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return ""
	var found := {}
	var p := 8
	while p + 8 <= bytes.size():
		var length := (bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3]
		var kind := bytes.slice(p + 4, p + 8).get_string_from_ascii()
		if length < 0 or p + 12 + length > bytes.size():
			break
		var data := bytes.slice(p + 8, p + 8 + length)
		if kind == "tEXt" or kind == "iTXt":
			var zero := data.find(0)
			if zero > 0:
				var key := data.slice(0, zero).get_string_from_ascii().to_lower()
				var value := data.slice(zero + 1)
				if kind == "iTXt":
					# compression flag, method, language\0, translated keyword\0, then the text
					if value.size() < 2 or value[0] != 0:
						p += 12 + length
						continue
					var rest := value.slice(2)
					var z1 := rest.find(0)
					var z2 := rest.find(0, z1 + 1) if z1 >= 0 else -1
					value = rest.slice(z2 + 1) if z2 >= 0 else PackedByteArray()
				if key in ["ccv3", "chara"]:
					found[key] = value.get_string_from_utf8().strip_edges()
		if kind == "IEND":
			break
		p += 12 + length
	for key in ["ccv3", "chara"]:
		if found.has(key):
			var raw: String = found[key]
			var decoded := Marshalls.base64_to_utf8(raw) if not raw.begins_with("{") else raw
			if decoded.strip_edges().begins_with("{"):
				return decoded
	return ""


## A parsed card (v1 flat, v2 or v3) -> the friend's fields. {ok, card, error}.
static func from_card(data: Dictionary, from: String = "") -> Dictionary:
	var d: Dictionary = data
	if str(data.get("spec", "")).begins_with("chara_card") and data.get("data") is Dictionary:
		d = data.data
	var name := _clean(str(d.get("name", "")), 60)
	if name == "":
		return {"ok": false, "error": "The card has no name."}
	var description := str(d.get("description", ""))
	var personality := str(d.get("personality", ""))
	var card := {
		"name": name,
		"personality": _fit(personality if personality.strip_edges() != "" else description, name),
		"backstory": _fit(str(d.get("scenario", "")) if personality.strip_edges() == "" else (description + "\n" + str(d.get("scenario", ""))), name),
		"greeting": _fit(str(d.get("first_mes", "")), name, MAX_GREETING),
		"examples": _fit(str(d.get("mes_example", "")), name, MAX_EXAMPLES),
		"system_prompt": _fit(str(d.get("system_prompt", "")), name, 600),
		"creator": _clean(str(d.get("creator", "")), 80),
		"tags": (d.get("tags", []) as Array).slice(0, 12).map(func(x): return _clean(str(x), 30)) if d.get("tags") is Array else [],
		"from": from if from != "" else ("a character card" if data.has("spec") else "another app"),
	}
	return {"ok": true, "card": card, "error": ""}


## "Name: Ava\nGreeting: Hi!\nDescription: ..." (any order, any case; a line without a label continues
## the one before), or plain text (a description; the name comes from the player).
static func from_labelled(text: String, from: String = "") -> Dictionary:
	var fields := {}
	var current := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		var colon := line.find(":")
		var label := line.substr(0, colon).strip_edges().to_lower() if colon > 0 and colon <= 24 else ""
		var matched := ""
		for field in LABELS:
			if label in LABELS[field]:
				matched = field
		if matched != "":
			current = matched
			fields[current] = str(fields.get(current, "")) + line.substr(colon + 1).strip_edges()
		elif current != "":
			fields[current] = str(fields[current]) + "\n" + line
		else:
			fields["description"] = str(fields.get("description", "")) + ("\n" if fields.has("description") else "") + line
	var card := {
		"name": _clean(str(fields.get("name", "")), 60),
		"personality": str(fields.get("personality", "")) if str(fields.get("personality", "")) != "" else str(fields.get("description", "")),
		"backstory": (str(fields.get("description", "")) + "\n" + str(fields.get("scenario", ""))) if str(fields.get("personality", "")) != "" else str(fields.get("scenario", "")),
		"greeting": str(fields.get("greeting", "")),
		"examples": str(fields.get("examples", "")),
		"speech_style": str(fields.get("speech", "")),
		"from": from if from != "" else "pasted text",
	}
	for k in ["personality", "backstory", "examples"]:
		card[k] = _fit(str(card[k]), str(card.name), MAX_FIELD if k != "examples" else MAX_EXAMPLES)
	card["greeting"] = _fit(str(card.greeting), str(card.name), MAX_GREETING)
	if str(card.personality).strip_edges() == "" and str(card.greeting).strip_edges() == "":
		return {"ok": false, "error": "That doesn't describe a character yet. Paste their description (and name, greeting if you have them)."}
	return {"ok": true, "card": card, "error": ""}


## A new friend from a card (with `name` if the card had none). Returns the new id, "" on failure.
static func create_friend(card: Dictionary, name_override: String = "") -> String:
	var name := name_override.strip_edges() if name_override.strip_edges() != "" else str(card.get("name", "")).strip_edges()
	if name == "":
		return ""
	var id := SaveManager.unique_id(name, SaveManager.list_characters())
	var c := Defaults.character(id, name)
	var you := GameState.player_name() if GameState.player_name() != "" else "you"
	for k in ["personality", "backstory", "greeting", "examples", "system_prompt", "speech_style"]:
		if str(card.get(k, "")).strip_edges() != "":
			c[k] = str(card[k]).replace("{{char}}", name).replace("{{user}}", you).replace("{{Char}}", name).replace("{{User}}", you)
	c["relationship_to_player"] = "a friend who came over from " + str(card.get("from", "another app"))
	c["imported"] = {"from": str(card.get("from", "")), "creator": str(card.get("creator", "")), "tags": card.get("tags", []), "when": Defaults.now_iso()}
	c["voice_sound"] = "blip"
	var dir := SaveManager.character_dir(id)
	var picture: Variant = card.get("picture")
	if picture is Image and not (picture as Image).is_empty():
		c["expressions"] = _write_picture(dir, picture)
	else:
		c["expressions"] = SpriteFactory.write_blob_set(dir, _colour_for(name))
	GameState.save_character(c)
	return id if FileAccess.file_exists(SaveManager.character_dir(id).path_join("character.json")) or SaveManager.list_characters().has(id) else ""


static func _write_picture(dir: String, picture: Image) -> Dictionary:
	var img := picture.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var h := img.get_height()
	var w := img.get_width()
	if h > SPRITE_HEIGHT:
		img.resize(maxi(1, roundi(float(w) * SPRITE_HEIGHT / h)), SPRITE_HEIGHT, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(dir.path_join("expressions"))
	img.save_png(dir.path_join("expressions/neutral.png"))
	var out := {}
	for e in Defaults.DEFAULT_EXPRESSIONS:
		out[e] = "expressions/neutral.png"   # one picture for every feeling (the editor can add more)
	return out


static func _colour_for(name: String) -> Color:
	return Color.from_hsv(float(abs(name.hash()) % 360) / 360.0, 0.35, 0.95)


static func _clean(text: String, n: int) -> String:
	# Control characters out (tabs and line breaks stay), by code point: no NUL string is ever made.
	var t := text.strip_edges()
	var out := ""
	for i in mini(t.length(), n + 64):
		var cp := t.unicode_at(i)
		if cp >= 32 or cp == 9 or cp == 10:
			out += t[i]
	return out.substr(0, n)


static func _fit(text: String, name: String, n: int = MAX_FIELD) -> String:
	var t := _clean(text, 100000).replace("{{char}}", name).replace("{{Char}}", name)
	return t if t.length() <= n else t.substr(0, n).strip_edges() + "…"
