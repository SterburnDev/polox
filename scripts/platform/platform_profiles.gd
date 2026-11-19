extends RefCounted
## Original movement rules, tuned in blocks/s and blocks/s². These are inspired
## presets, not a port or a frame-exact reproduction of another game's code.

const IDS := ["polox", "classic", "adventure"]
const NAMES := ["Polox", "Classic Momentum", "Adventure Momentum"]
const VALUES := {
	"polox": {"walk": 4.0, "speed": 7.0, "accel": 40.0, "brake": 46.0, "friction": 46.0, "air": 16.0, "gravity": 28.0, "jump": 8.69, "cut": 8.69, "slope": 0.0, "roll_friction": 46.0, "launch": 7.0, "max": 7.0, "turn": 40.0},
	"classic": {"walk": 8.0, "speed": 11.0, "accel": 7.5, "brake": 32.0, "friction": 5.0, "air": 5.5, "gravity": 28.0, "jump": 9.8, "cut": 4.4, "slope": 20.0, "roll_friction": 1.8, "launch": 18.0, "max": 22.0, "turn": 0.0},
	"adventure": {"walk": 7.0, "speed": 12.0, "accel": 16.0, "brake": 30.0, "friction": 7.0, "air": 7.0, "gravity": 28.0, "jump": 9.4, "cut": 4.5, "slope": 13.0, "roll_friction": 2.6, "launch": 17.0, "max": 21.0, "turn": 22.0},
}

## One short line of controls per profile, under its name on the HUD (ported from the movement branch,
## worded for the controls as they are now: platform_body.gd roll_or_charge()).
const HINTS := {
	"polox": "Move, jump, Run for speed",
	"classic": "Along the course · Roll: tap while moving; stopped, tap to charge, tap to go",
	"adventure": "Steer with the camera · Roll: tap while moving; stopped, tap to charge, tap to go",
}


static func hint(id: String) -> String:
	return str(HINTS[normalize(id)])


static func normalize(id: String) -> String:
	return id if id in IDS else "polox"

static func values(id: String) -> Dictionary:
	return VALUES[normalize(id)]

static func label(id: String) -> String:
	return NAMES[IDS.find(normalize(id))]

static func course(room: Dictionary) -> String:
	return str(resolve(room).id)

static func resolve(room: Dictionary) -> Dictionary:
	# Old courses remain Polox. A creator can explicitly opt a course into the
	# player's saved preference; a 2D plane is still required for Classic.
	var id := str(room.get("physics_profile", "polox"))
	if id == "player":
		id = str(GameState.settings.get("platform_profile", "polox"))
	id = normalize(id)
	var note := ""
	if id == "classic" and plane(room) == "":
		id = "polox"
		note = "Classic needs an X or Z course plane. Playing as Polox here."
	return {"id": id, "note": note}

static func plane(room: Dictionary) -> String:
	var id := str(room.get("platform_plane", ""))
	return id if id in ["x", "z"] else ""

static func jump_reach(id: String, running: bool = true) -> Vector2:
	var p := values(id)
	return Vector2(floorf(float(p.jump) * float(p.jump) / (2.0 * float(p.gravity))), floorf(float(p.speed if running else p.walk) * 2.0 * float(p.jump) / float(p.gravity)))

static func issues(room: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if str(room.get("physics_profile", "")) in ["classic", "player"] and plane(room) == "":
		out.append("Classic Momentum needs an X or Z course plane.")
	return out
