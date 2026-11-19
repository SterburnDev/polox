extends RefCounted
## Default shapes for every save file. SaveManager merges these into whatever
## it loads, so older or hand-edited files gain new fields automatically.

const VERSION := 1
## world.json is at version 3 since Phase 14 (versioned tile-layer rooms); see world_migration.gd.
const WORLD_VERSION := 8

const DEFAULT_EXPRESSIONS: PackedStringArray = [
	"neutral", "happy", "sad", "angry", "surprised", "embarrassed", "thinking", "sleepy",
]


static func now_iso() -> String:
	return Time.get_datetime_string_from_system(false, false)


static func world() -> Dictionary:
	return {
		"version": WORLD_VERSION,
		"name": "My Pocket World",
		"world_bible": {
			"setting": "",
			"lore": "",
			"themes": "",
			"life_context": "",
		},
		# forms: {"real": {...}, "dark": {...}} (see player_look.gd); filled when the world is made.
		"player": {
			"name": "", "pronouns": "", "avatar": "", "birthday": "",
			"nicknames": "", "about": "", "share_dreams": true,
			"form": "real", "forms": {}, "show_gear": true,
			"voice": {"sound": "soft", "pitch": 1.15, "speed": 1.0},
		},
		"settings": {"real_time_lighting": true, "daily_events": true, "seasonal_decor": true, "seasons": true, "hemisphere": "north"},
		"start_room": "home",
		"bonds": {},
		"created": now_iso(),
	}


static func room(id: String = "home", room_name: String = "Home") -> Dictionary:
	return {
		"version": VERSION,
		"id": id,
		"name": room_name,
		"size": {"w": 12, "d": 10, "h": 3},
		"floor": {"color": "#5b4b8a", "texture": ""},
		"wall": {"color": "#2e2552", "texture": ""},
		"sky": {"color": "#120e24", "texture": ""},
		"tiles": [],
		"tile_layers": preload("res://scripts/world/tile_layers.gd").default_layers(),
		"tile_layers_version": 1,
		"objects": [],
		"spawn": [6, 7],
		"player_form": "",
		"kind": "indoor",
		"walls": {"north": true, "east": true, "south": true, "west": true},
		"background": {"sky": "auto", "ground": true, "ground_color": "#6a9a5b", "layers": [   # (Places.INDOOR_SCENERY: in the world, not a void)
			{"kind": "hills", "color": "#4f7a5c", "distance": 3, "seed": 1}]},
		"edges": {},
		"side": "light",
		"ambiance": {"music": "", "lighting": "cozy", "weather": "auto"},
		"layers": {
			"backdrop": {"visible": true, "lock": false, "opacity": 1.0},
			"pieces": {"visible": true, "lock": false, "opacity": 1.0},
		},
	}


static func character(id: String = "", char_name: String = "") -> Dictionary:
	return {
		"version": VERSION,
		"id": id,
		"name": char_name,
		"personality": "",
		"backstory": "",
		"quirks": "",
		"speech_style": "",
		"likes": "",
		"dislikes": "",
		"relationship_to_player": "a new friend",
		"voice_pitch": 1.0,
		"voice_sound": "blip",
		"voice_speed": 1.0,
		"liked_tags": [],
		"disliked_tags": [],
		"gifts_received": [],
		"expressions": {},
		"home_room": "home",
		"pos": [],
		"mood": {"happiness": 0.7, "energy": 0.7, "loneliness": 0.3},
		"relationship": {"affinity": 10.0, "trust": 10.0},
		"memory_notes": [],
		"summary": "",
		"summary_upto": 0,
		"last_talked": "",
		"last_update": now_iso(),
		"last_update_unix": Time.get_unix_time_from_system(),
		"created": now_iso(),
	}


static func settings() -> Dictionary:
	return {
		"version": VERSION,
		"ai": {
			"preset": "mock",
			"base_url": "",
			"model": "",
			"api_key": "",
			"temperature": 0.85,
			"max_tokens": 400,
			"timeout_s": 20,
			"requests_per_minute": 20,
			"npc_chatter": true,
		},
		"ui_scale": 1.0,
		"text_speed": 45,
		"camera_preset": "cozy",
		"wheel_mode": "zoom",
		"music_volume": 0.7,
		"sfx_volume": 0.8,
		"text_blips": true,
		"quick_replies": true,
		"recap": true,
		"onboarded": false,
		# Phone Link is never on at startup (only host.bat starts it by itself).
		# No "version" here: loading fills in defaults, and a version from the defaults would make an
		# old file look already upgraded (that is how Update 4's upgrade never ran: Phase 19 postmortem).
		"phone_link": {"mode": "auto", "port": 8765, "auto_off_hours": 6, "max_devices": 4, "always_ask": false, "keep_awake": true},
	}


static func inventory() -> Dictionary:
	return {"version": VERSION, "stacks": [], "equipped": {"weapon": "", "head": "", "body": "", "accessory": ""}}


static func dreams() -> Dictionary:
	return {"version": VERSION, "dreams": []}


static func journal() -> Dictionary:
	return {"version": VERSION, "moments": []}
