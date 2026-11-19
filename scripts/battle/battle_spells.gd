extends RefCounted
## Original, data-only capabilities. IDs, not executable callbacks, travel with a battle.
const ROLES := ["guide", "guardian", "dreamer"]
const ROLE_NAMES := ["Guide", "Guardian", "Dreamer"]
const BOOK := {
	"lantern": {"name": "Lantern spark", "tp": 24, "effect": "damage", "power": 24, "target": "enemy", "hint": "A warm flash; tires them out."},
	"mend": {"name": "Mend", "tp": 24, "effect": "heal", "power": 24, "target": "ally", "hint": "Heal a friend, or help them back up."},
	"hush": {"name": "Hush", "tp": 16, "effect": "pacify", "power": 0, "target": "enemy", "hint": "A TIRED foe settles down peacefully."},
	"comet": {"name": "Paper comet", "tp": 40, "effect": "damage", "power": 42, "target": "enemy", "hint": "A bright paper trail with a strong finish."},
	"shelter": {"name": "Shelter", "tp": 32, "effect": "shield", "power": 0, "target": "party", "hint": "Everyone takes half damage this turn."},
	"chorus": {"name": "Little chorus", "tp": 48, "effect": "heal_all", "power": 20, "target": "party", "hint": "Heal everyone, including downed friends."},
}
const LOADOUTS := {"guide": ["lantern", "mend", "hush"], "guardian": ["comet", "shelter"], "dreamer": ["mend", "hush", "chorus"]}

static func for_role(role: String) -> Array:
	return (LOADOUTS.get(role, LOADOUTS.guide) as Array).duplicate()

static func clean_ids(raw: Variant, role: String = "guide") -> Array:
	if not raw is Array:
		return for_role(role)
	var out: Array = []
	for id in raw:
		if id is String and BOOK.has(id) and not id in out:
			out.append(id)
	return out
