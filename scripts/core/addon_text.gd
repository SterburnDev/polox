extends Translation
## The words on screen, as Polox shows them: every Label, Button and the like asks the TranslationServer
## for its text, and this answers with the old names made new (saves, chats and memories from before the
## Dream World) and then the add-ons' own words (addons.gd). Nothing saved is changed: turn an add-on off
## and its words are gone. `pairs` = [[from, to], ...], applied in order.
## Tags: [ADDONS]

var pairs: Array = []

## The names from before Dream World: worlds made then still say them in places' names, labels and chats.
const LEGACY := {
	"Dark Fountains": "Dream Gates", "Dark Fountain": "Dream Gate",
	"Dark World": "Dream World", "Darkeners": "Bramins", "Darkener": "Bramin",
}


static func legacy_pairs() -> Array:
	return pairs_from(LEGACY)


## [from, to] pairs from a {from: to} table: longest first (so "Bramins" goes before "Bramin"), each as
## written and in CAPITALS (a title card shouts).
static func pairs_from(table: Dictionary) -> Array:
	var keys: Array = table.keys()
	keys.sort_custom(func(a, b): return str(a).length() > str(b).length())
	var out: Array = []
	for k in keys:
		var a := str(k)
		var b := str(table[k])
		if a == "" or a == b:
			continue
		out.append([a, b])
		if a.to_upper() != a:
			out.append([a.to_upper(), b.to_upper()])
	return out


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	if pairs.is_empty():
		return &""
	var s := String(src_message)
	var out := s
	for p in pairs:
		if out.contains(p[0]):
			out = out.replace(p[0], p[1])
	return StringName(out) if out != s else &""


func _get_plural_message(src_message: StringName, _src_plural_message: StringName, _n: int, context: StringName) -> StringName:
	return _get_message(src_message, context)
