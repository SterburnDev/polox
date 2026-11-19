extends RefCounted
## Original practice encounters. These dictionaries are copied into the Maker;
## the player can change the waves, ACTs, phases, pictures and music there.

const Whimsy := preload("res://scripts/variety/whimsy.gd")
const ORDER := ["tide_parcel", "pebble_lift", "copper_vane", "seed_post", "stillwater_lantern", "ribbon_turntable"]
const NAMES := {
	"tide_parcel": "Tide parcel", "pebble_lift": "Pebble lift", "copper_vane": "Copper weather vane",
	"seed_post": "Seed post", "stillwater_lantern": "Stillwater lantern", "ribbon_turntable": "Ribbon turntable",
}


static func wave(title: String, mode: String, spawners: Array, hint: String, box: Dictionary = {}) -> Dictionary:
	return {"name": title, "mode": mode, "duration": 7.0, "telegraph": 1.2,
		"box": box if not box.is_empty() else {"w": 260, "h": 180}, "spawners": spawners, "hint": hint}


static func raw(id: String) -> Dictionary:
	if not id in ORDER:
		return {}
	var waves: Array = []
	var act_name := ""
	var act_text := ""
	match id:
		"tide_parcel":
			act_name = "Fold a corner"
			act_text = "A careful fold leaves more room for everyone."
			waves = [
				wave("Incoming letters", "free", [{"bullet": "leaf", "path": "wave", "from": "left", "every": 0.7, "speed": 68, "amp": 18, "freq": 0.45, "seed": 101}], "Follow the gaps between the letters.", {"w": 280, "h": 180, "end_w": 220, "end_h": 150}),
				wave("Return envelopes", "free", [{"bullet": "leaf", "path": "wave", "from": "right", "start": 0.2, "every": 0.75, "speed": 72, "amp": 24, "freq": 0.35, "seed": 103}, {"bullet": "dot", "from": "top", "start": 2.0, "every": 1.5, "speed": 55, "seed": 107}], "Two delivery routes, with wide spaces between them."),
				wave("A little breathing room", "free", [{"bullet": "leaf", "from": "top", "every": 1.1, "speed": 50, "seed": 109}], "The folded corner makes a quieter route.", {"w": 300, "h": 200}),
			]
		"pebble_lift":
			act_name = "Lower the lift"
			act_text = "The lift slows to a gentle glide. Your feet feel light."
			waves = [
				wave("Ground-floor pebbles", "gravity", [{"bullet": "ball", "from": "point", "point": [0, 0.95], "angle": 0, "every": 1.6, "speed": 76, "seed": 211}], "Up / A jumps. Drag upward to jump; sideways to steer."),
				wave("A higher landing", "gravity", [{"bullet": "ball", "from": "point", "point": [1, 0.94], "angle": 180, "every": 1.5, "speed": 70, "seed": 223}, {"bullet": "dot", "from": "top", "start": 1.0, "every": 2.0, "speed": 42, "seed": 227}], "Hop over the floor pebbles; watch the slow falling ones."),
				wave("Weightless landing", "free", [{"bullet": "bubble", "from": "bottom", "every": 1.2, "speed": 45, "seed": 229}], "The lift lets you float for this turn."),
			]
		"copper_vane":
			act_name = "Point north"
			act_text = "The vane agrees to send the next breeze from one direction."
			waves = [
				wave("Two breezes", "shield", [{"bullet": "dot", "from": "point", "point": [0.5, 0], "angle": 90, "every": 1.8, "speed": 62, "seed": 307}, {"bullet": "dot", "from": "point", "point": [1, 0.5], "angle": 180, "start": 0.9, "every": 1.8, "speed": 62, "seed": 311}], "Aim the shield toward each incoming breeze."),
				wave("Turning forecast", "shield", [{"bullet": "dot", "from": "point", "point": [0, 0.5], "angle": 0, "every": 2.1, "speed": 58, "seed": 313}, {"bullet": "dot", "from": "point", "point": [0.5, 1], "angle": -90, "start": 1.05, "every": 2.1, "speed": 58, "seed": 317}], "The forecast changes. Turn toward the next dot."),
				wave("North wind only", "shield", [{"bullet": "dot", "from": "point", "point": [0.5, 0], "angle": 90, "every": 1.3, "speed": 48, "seed": 331}], "A steady shield facing upward is enough."),
			]
		"seed_post":
			act_name = "Sort the seeds"
			act_text = "You sort the seed packets by colour. The next delivery is neatly spaced."
			waves = [
				wave("Seed delivery", "shooter", [{"bullet": "bubble", "from": "point", "point": [0.3, 0], "every": 0.9, "speed": 54, "fragile": true, "seed": 401}, {"bullet": "bubble", "from": "point", "point": [0.7, 0], "start": 0.45, "every": 0.9, "speed": 54, "fragile": true, "seed": 409}], "Hold touch / Z / A to send pulses. Break the hollow seed pods."),
				wave("Sprouting routes", "shooter", [{"bullet": "bubble", "path": "wave", "from": "top", "every": 0.8, "speed": 54, "amp": 16, "freq": 0.4, "fragile": true, "seed": 419}], "The hollow pods drift; your pulses still open them."),
				wave("Sorted packets", "shooter", [{"bullet": "bubble", "from": "point", "point": [0.5, 0], "every": 1.0, "speed": 42, "fragile": true, "seed": 421}], "A single tidy delivery route."),
			]
		"stillwater_lantern":
			act_name = "Dim the lantern"
			act_text = "The lantern lowers its light and lets the coloured ripples rest."
			waves = [
				wave("Quiet ripples", "free", [{"bullet": "bubble", "from": "top", "every": 0.35, "speed": 68, "rule": "still", "seed": 503}], "Blue rings: hold still to let them pass."),
				wave("Wakeful ripples", "free", [{"bullet": "bubble", "from": "top", "every": 0.5, "speed": 64, "rule": "move", "seed": 509}, {"bullet": "dot", "from": "left", "start": 1.0, "every": 1.5, "speed": 48, "seed": 521}], "Amber arrows: keep moving. White dots always need a gap."),
				wave("Dimmed light", "free", [{"bullet": "bubble", "from": "top", "every": 1.3, "speed": 42, "seed": 523}], "The colours rest for one quiet turn."),
			]
		"ribbon_turntable":
			act_name = "Untie a loop"
			act_text = "You untie a loose loop. The turntable pauses to say thank you."
			waves = [
				wave("Unwinding ribbon", "free", [{"bullet": "petal", "path": "wave", "from": "top", "every": 0.65, "speed": 58, "amp": 16, "freq": 0.3, "seed": 601}], "The box tilts slowly. Keep following the open spaces.", {"w": 250, "h": 170, "end_w": 220, "end_h": 190}),
				wave("A second loop", "free", [{"bullet": "petal", "from": "left", "every": 0.7, "speed": 58, "seed": 607}, {"bullet": "bubble", "from": "top", "start": 0.4, "every": 1.4, "speed": 44, "seed": 613}], "The ribbon turns the other way; the gaps stay generous."),
				wave("Table at rest", "free", [{"bullet": "petal", "from": "top", "every": 1.2, "speed": 40, "seed": 617}], "A steady table for this turn."),
			]
			waves[0]["rotation"] = 22
			waves[1]["rotation"] = -26
	var enemy := {"character": "", "name": NAMES[id], "picture": "res://assets/battles/" + id + ".svg", "preset": "gentle",
		"hp": 80, "attack": 3, "defense": 0, "mercy_max": 100, "waves": waves,
		"phases": [{"mercy": 0.5, "hp": 0.5, "wave": 1, "name": "A little trust"}],
		"acts": [{"name": "Check", "text": "", "mercy": 0},
			{"name": act_name, "text": act_text, "mercy": 35, "next_wave": 2},
			{"name": "Share a small kindness", "text": "A small kindness brings a warm reply.", "mercy": 35},
			{"name": "Team bow", "text": "Your friends bow together. Everyone smiles.", "mercy": 65, "tp": 16, "helpers": 1}],
		"lines": {"intro": "A friendly practice. You can stop whenever you like.", "check": waves[0].hint,
			"spared": "Practice ends with a cheerful wave.", "won": "A happy rest. Nobody is hurt.", "idle": Whimsy.BATTLE_IDLE_QUIPS.get(id, [])}}
	return {"name": NAMES[id], "template": id, "music": "@original", "enemies": [enemy]}
